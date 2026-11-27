import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart'
    show kLinearDepthBlackboardKey;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';
import 'package:flutter_scene/src/render/uniform_slots.dart';

/// The scene-owned GPU state of the irradiance field: the atlas the lit
/// shader samples, the ping-ponged blend history, and the feed's
/// accumulators.
///
/// Created with `createTexture` rather than from the transient pool because
/// every one of these has to survive across frames; a pooled allocation would
/// be recycled underneath the history.
class IrradianceFieldState {
  IrradianceFieldLayout? _layout;
  IrradianceGridPlacement? _placement;
  Vector3 _previousAnchor = Vector3.zero();

  gpu.Texture? _historyA;
  gpu.Texture? _historyB;
  gpu.Texture? _sampled;
  gpu.Texture? _irradianceAccumulator;
  gpu.Texture? _depthAccumulator;
  gpu.Texture? _sampleGeometry;
  gpu.Texture? _sampleRadiance;
  gpu.Texture? _shTexture;
  int _sampleFrame = 0;

  bool _historyIsA = true;
  bool _resetPending = true;
  int _updateCursor = 0;

  /// The atlas the lit shader samples, or null before the first update.
  gpu.Texture? get sampledAtlas => _sampled;

  /// The cheap receiver's spherical-harmonic texture, allocated on first
  /// use for this layout. Null before the first update.
  gpu.Texture? ensureShTexture() {
    final layout = _layout;
    if (layout == null) return null;
    return _shTexture ??= gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      layout.shWidth,
      layout.shHeight,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
  }

  /// This frame's layout, or null before the first update.
  IrradianceFieldLayout? get layout => _layout;

  /// The irradiance and depth-moment accumulators the blend reads, which a
  /// feed fills each frame. Null before the first update.
  gpu.Texture? get irradianceAccumulator => _irradianceAccumulator;
  gpu.Texture? get depthAccumulator => _depthAccumulator;

  /// This frame's lattice placement, or null before the first update.
  IrradianceGridPlacement? get placement => _placement;

  gpu.Texture get _writeHistory => _historyIsA ? _historyB! : _historyA!;
  gpu.Texture get _readHistory => _historyIsA ? _historyA! : _historyB!;

  /// Discards the accumulated field so it refills from scratch. Every probe
  /// blends at zero retention on the next update instead of lerping up from
  /// data that no longer describes its location.
  void invalidate() => _resetPending = true;

  /// Recomputes the layout and placement for this frame, reallocating when
  /// the grid changed. Returns false when the field cannot run.
  bool update({
    required GlobalIlluminationSettings settings,
    required Vector3 center,
    required Vector3 extents,
    Vector3? resolution,
  }) {
    final layout = IrradianceFieldLayout(resolution ?? settings.resolution);
    final placement = planIrradianceGrid(
      center: center,
      extents: extents,
      layout: layout,
    );
    if (_layout != layout) {
      _releaseTextures();
      _layout = layout;
      _resetPending = true;
    }
    // Respacing moves every probe, so the stored lighting no longer describes
    // any of their locations.
    if (_placement?.spacing != placement.spacing) {
      _resetPending = true;
    }
    _previousAnchor = _resetPending
        ? placement.anchor
        : (_placement?.anchor ?? placement.anchor);
    _placement = placement;
    _allocate(layout);
    return _sampled != null;
  }

  /// The scene's tick delta, which the blend's retention follows, so a scene
  /// driven by `Scene.update` with a fixed step blends repeatably.
  double frameSeconds = 1.0 / 60.0;

  // Clamped so a stall or a first frame cannot drive the retention exponent
  // somewhere useless.
  double get _blendSeconds =>
      frameSeconds <= 0.0 ? 1.0 / 60.0 : frameSeconds.clamp(1.0 / 240.0, 0.1);

  /// Whether the traced feed wrote this frame's per-probe state rows into
  /// [sampledAtlas], which the filter then leaves alone.
  bool traceOwnsProbeState = false;

  /// Whether the next blend resets every probe.
  bool get resetPending => _resetPending;

  /// The probes this frame's feed, blend, and filter refresh, 0 for all. The
  /// scene resolves it from the settings and the adaptive controller.
  int probeUpdateBudget = 0;

  /// The rows [scheduleRows] will return for [probeUpdateBudget], without
  /// advancing the schedule, so a feed that runs before the blend can update
  /// the same probes.
  (int, int) peekScheduleRows(int probeUpdateBudget) {
    final layout = _layout!;
    if (probeUpdateBudget <= 0 || _resetPending) {
      return (0, layout.tileRows);
    }
    final rows = math.max(1, probeUpdateBudget ~/ layout.tilesPerRow);
    final start = _updateCursor % layout.tileRows;
    return (start, math.min(layout.tileRows, start + rows));
  }

  /// The tile rows this frame's blend and filter refresh, as a half-open
  /// range. A zero budget refreshes every row.
  (int, int) scheduleRows(int probeUpdateBudget) {
    final layout = _layout!;
    if (probeUpdateBudget <= 0 || _resetPending) {
      return (0, layout.tileRows);
    }
    final rows = math.max(1, probeUpdateBudget ~/ layout.tilesPerRow);
    final start = _updateCursor % layout.tileRows;
    final end = math.min(layout.tileRows, start + rows);
    _updateCursor = end >= layout.tileRows ? 0 : end;
    return (start, end);
  }

  /// Marks this frame's blend done, swapping the history buffers and clearing
  /// the pending reset.
  void finishBlend() {
    _historyIsA = !_historyIsA;
    _resetPending = false;
  }

  /// Frees every texture and buffer the field owns.
  void dispose() {
    _releaseTextures();
    _layout = null;
    _placement = null;
  }

  void _releaseTextures() {
    _historyA = null;
    _historyB = null;
    _sampled = null;
    _irradianceAccumulator = null;
    _depthAccumulator = null;
    _sampleGeometry = null;
    _sampleRadiance = null;
    _shTexture = null;
  }

  void _allocate(IrradianceFieldLayout layout) {
    if (_sampled != null) return;
    gpu.Texture create(int width, int height) => gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    _historyA = create(layout.atlasWidth, layout.atlasHeight);
    _historyB = create(layout.atlasWidth, layout.atlasHeight);
    _sampled = create(layout.atlasWidth, layout.atlasHeight);
    _irradianceAccumulator = create(
      layout.injectionIrradianceWidth,
      layout.injectionIrradianceHeight,
    );
    _depthAccumulator = create(
      layout.injectionDepthWidth,
      layout.injectionDepthHeight,
    );
    // One 8x8 block of screen samples per probe, the irradiance tile's size.
    _sampleGeometry = create(
      layout.injectionIrradianceWidth,
      layout.injectionIrradianceHeight,
    );
    _sampleRadiance = create(
      layout.injectionIrradianceWidth,
      layout.injectionIrradianceHeight,
    );
    _historyIsA = true;
    _clearTexture(_historyA!);
    _clearTexture(_historyB!);
    _clearTexture(_sampled!);
    _clearTexture(_irradianceAccumulator!);
    _clearTexture(_depthAccumulator!);
  }

  static void _clearTexture(gpu.Texture texture, [Vector4? clearValue]) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: texture,
          loadAction: gpu.LoadAction.clear,
          clearValue: clearValue ?? Vector4.zero(),
        ),
      ),
    );
    rendererSubmissions.submit(commandBuffer);
  }
}

// Fullscreen NDC triangles for the blend, filter, and strip passes.
final gpu.DeviceBuffer _fullscreenBuffer = gpu.gpuContext
    .createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
final gpu.BufferView _fullscreenView = gpu.BufferView(
  _fullscreenBuffer,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Feeds the probe accumulators from the visible surfaces' shaded radiance
/// and distance.
///
/// Each probe first picks a fixed set of screen samples inside the screen
/// rectangle its trilinear support covers, then every accumulator texel
/// gathers its own probe's samples, so the cost follows the probe count and
/// no pass blends. Only this frame's scheduled tile rows are fed.
class IrradianceInjectPass extends RenderGraphPass {
  IrradianceInjectPass({
    required this.state,
    required this.settings,
    required this.dimensions,
    required this.cameraPosition,
    required this.cameraRight,
    required this.cameraUp,
    required this.cameraForward,
    required this.projection,
    required this.sceneRadiance,
  });

  final IrradianceFieldState state;
  final GlobalIlluminationSettings settings;
  final ui.Size dimensions;
  final Vector3 cameraPosition;
  final Vector3 cameraRight;
  final Vector3 cameraUp;
  final Vector3 cameraForward;
  final ProjectionParams projection;
  final gpu.Texture? sceneRadiance;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _sampleShader =
      baseShaderLibrary['IrradianceSampleFragment']!;
  static final gpu.Shader _gatherShader =
      baseShaderLibrary['IrradianceGatherFragment']!;

  @override
  String get name => 'IrradianceInjectPass';

  @override
  void execute(RenderGraphContext context) {
    state.traceOwnsProbeState = false;
    final layout = state._layout;
    final placement = state._placement;
    final radiance = sceneRadiance;
    if (layout == null || placement == null) return;
    if (radiance == null) {
      IrradianceFieldState._clearTexture(state._irradianceAccumulator!);
      IrradianceFieldState._clearTexture(state._depthAccumulator!);
      return;
    }
    final depthNormal = context.blackboard.get<gpu.Texture>(
      kLinearDepthBlackboardKey,
    );
    if (depthNormal == null) return;

    final divisor = settings.injectionResolution.divisor;
    final sourceWidth = math.max(1, dimensions.width ~/ divisor);
    final sourceHeight = math.max(1, dimensions.height ~/ divisor);
    // The blend advances the schedule after this pass, so both see the same
    // rows.
    final (startRow, endRow) = state.peekScheduleRows(state.probeUpdateBudget);
    state._sampleFrame = (state._sampleFrame + 1) % 4096;

    final spacing = placement.spacing;
    final anchor = placement.anchor;
    final counts = layout.resolution;
    final info = Float32List(40);
    info[0] = sourceWidth.toDouble();
    info[1] = sourceHeight.toDouble();
    info[4] = projection.scaleX;
    info[5] = projection.scaleY;
    info[6] = projection.far;
    info[7] = settings.fireflyClamp;
    info[8] = cameraPosition.x;
    info[9] = cameraPosition.y;
    info[10] = cameraPosition.z;
    info[11] = settings.emissiveGiBoost;
    info[12] = cameraRight.x;
    info[13] = cameraRight.y;
    info[14] = cameraRight.z;
    info[15] = projection.offsetX;
    info[16] = cameraUp.x;
    info[17] = cameraUp.y;
    info[18] = cameraUp.z;
    info[19] = projection.offsetY;
    info[20] = cameraForward.x;
    info[21] = cameraForward.y;
    info[22] = cameraForward.z;
    info[23] = projection.orthographicFlag;
    info[24] = spacing.x;
    info[25] = spacing.y;
    info[26] = spacing.z;
    info[27] = placement.maxProbeDistance;
    info[28] = anchor.x;
    info[29] = anchor.y;
    info[30] = anchor.z;
    info[31] = state._sampleFrame.toDouble();
    info[32] = counts.x;
    info[33] = counts.y;
    info[34] = counts.z;
    info[35] = layout.tilesPerRow.toDouble();
    info[36] = startRow.toDouble();
    info[37] = endRow.toDouble();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    for (final (target, output) in [
      (state._sampleGeometry!, 0.0),
      (state._sampleRadiance!, 1.0),
    ]) {
      info[38] = output;
      final renderPass = _fullscreenPass(commandBuffer, target);
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _sampleShader));
      bindVertexBufferCompat(renderPass, _fullscreenView, 6);
      renderPass.bindTexture(
        _sampleShader.cachedUniformSlot('linear_depth_normal'),
        depthNormal,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _sampleShader.cachedUniformSlot('scene_radiance'),
        radiance,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _sampleShader.cachedUniformSlot('SampleInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      drawCompat(renderPass, 6);
    }

    for (final (target, tile, interior, depth) in [
      (
        state._irradianceAccumulator!,
        IrradianceFieldLayout.irradianceTile,
        kIrradianceInterior,
        0.0,
      ),
      (
        state._depthAccumulator!,
        IrradianceFieldLayout.depthTile,
        kDepthMomentInterior,
        1.0,
      ),
    ]) {
      final gather = Float32List(12)
        ..[0] = tile.toDouble()
        ..[1] = interior.toDouble()
        ..[2] = depth
        ..[3] = layout.tilesPerRow.toDouble()
        ..[4] = layout.probeCount.toDouble()
        ..[5] = startRow.toDouble()
        ..[6] = endRow.toDouble()
        ..[8] = 1.0 / layout.injectionIrradianceWidth
        ..[9] = 1.0 / layout.injectionIrradianceHeight;
      final renderPass = _fullscreenPass(commandBuffer, target);
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _gatherShader));
      bindVertexBufferCompat(renderPass, _fullscreenView, 6);
      renderPass.bindTexture(
        _gatherShader.cachedUniformSlot('sample_geometry'),
        state._sampleGeometry!,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _gatherShader.cachedUniformSlot('sample_radiance'),
        state._sampleRadiance!,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _gatherShader.cachedUniformSlot('GatherInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(gather)),
      );
      drawCompat(renderPass, 6);
    }
    rendererSubmissions.submit(commandBuffer);
  }

  static gpu.RenderPass _fullscreenPass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture target,
  ) {
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: gpu.LoadAction.clear,
          clearValue: Vector4.zero(),
        ),
      ),
    );
    // GLES holds cull mode, winding, and blending as global state that leaks
    // across passes, so each pass sets its own.
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);
    return renderPass;
  }
}

/// Folds this frame's fed samples into the stored field.
///
/// One render pass over the write-side history with a draw per region, each
/// scoped by a viewport so a nonzero update budget refreshes a slice of the
/// probes per frame.
class IrradianceBlendPass extends RenderGraphPass {
  IrradianceBlendPass({
    required this.state,
    required this.settings,
    required this.shStrip,
    required this.environmentTransform,
    required this.environmentBlend,
    required this.environmentIntensity,
  });

  final IrradianceFieldState state;
  final GlobalIlluminationSettings settings;
  final gpu.Texture shStrip;
  final Matrix3 environmentTransform;
  final double environmentBlend;
  final double environmentIntensity;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _irradianceShader =
      baseShaderLibrary['IrradianceBlendFragment']!;
  static final gpu.Shader _depthShader =
      baseShaderLibrary['IrradianceBlendDepthFragment']!;

  /// Sigma multiple beyond which a texel's luminance move counts as a real
  /// lighting change rather than sampling noise.
  static const double _changeScale = 1.5;

  /// How far retention drops on a detected change, and the floor it stops at,
  /// so a change converges quickly without discarding the history outright.
  static const double _changeDrop = 0.35;
  static const double _retentionFloor = 0.55;

  @override
  String get name => 'IrradianceBlendPass';

  @override
  void execute(RenderGraphContext context) {
    final layout = state._layout;
    final placement = state._placement;
    if (layout == null || placement == null) return;
    final target = state._writeHistory;
    final history = state._readHistory;

    final dt = state._blendSeconds;
    // Retention is authored at 60 Hz and raised to the tick delta, so a
    // faster frame rate converges no faster in wall-clock time. The exponent
    // stops at 1, so a slow frame keeps a 60 Hz frame's history.
    final retention = math
        .pow(settings.hysteresis.clamp(0.0, 0.999), math.min(1.0, dt * 60.0))
        .toDouble();
    final (startRow, endRow) = state.scheduleRows(state.probeUpdateBudget);
    final reset = state._resetPending ? 1.0 : 0.0;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: target, loadAction: gpu.LoadAction.load),
      ),
    );
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);

    final counts = layout.resolution;
    final anchor = placement.anchor;
    final previous = state._previousAnchor;

    // Irradiance region.
    {
      final info = Float32List(44);
      final rotation = environmentTransform.storage;
      for (var column = 0; column < 3; column++) {
        info[column * 4] = rotation[column * 3];
        info[column * 4 + 1] = rotation[column * 3 + 1];
        info[column * 4 + 2] = rotation[column * 3 + 2];
      }
      info[15] = 1.0;
      info[16] = retention;
      info[17] = _changeScale;
      info[18] = _changeDrop;
      info[19] = _retentionFloor;
      info[20] = environmentBlend;
      info[21] = environmentIntensity;
      info[22] = IrradianceFieldLayout.irradianceTile.toDouble();
      info[23] = kIrradianceInterior.toDouble();
      info[24] = counts.x;
      info[25] = counts.y;
      info[26] = counts.z;
      info[27] = layout.tilesPerRow.toDouble();
      info[28] = anchor.x;
      info[29] = anchor.y;
      info[30] = anchor.z;
      info[31] = layout.irradianceOriginY.toDouble();
      info[32] = previous.x;
      info[33] = previous.y;
      info[34] = previous.z;
      info[35] = reset;
      info[36] = startRow.toDouble();
      info[37] = endRow.toDouble();
      info[38] = layout.tileRows.toDouble();
      // Bindings persist across draws in a pass, and a stale entry from the
      // previous pipeline's slot layout leaks into the next command, so every
      // pipeline change clears first (the same rule the scene encoder
      // follows).
      renderPass.clearBindings();
      renderPass.bindPipeline(
        resolvePipeline(_vertexShader, _irradianceShader),
      );
      bindVertexBufferCompat(renderPass, _fullscreenView, 6);
      renderPass.bindTexture(
        _irradianceShader.cachedUniformSlot('injection'),
        state._irradianceAccumulator!,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _irradianceShader.cachedUniformSlot('history'),
        history,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _irradianceShader.cachedUniformSlot('sh_strip'),
        shStrip,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _irradianceShader.cachedUniformSlot('BlendInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      drawCompat(renderPass, 6);
    }

    // Depth-moment region. Its retention is deliberately decoupled from the
    // irradiance change detector; coupling them makes the visibility term
    // move whenever the lighting does.
    {
      final info = Float32List(20);
      info[0] = retention;
      info[1] = IrradianceFieldLayout.depthTile.toDouble();
      info[2] = kDepthMomentInterior.toDouble();
      info[3] = layout.depthOriginY.toDouble();
      info[4] = counts.x;
      info[5] = counts.y;
      info[6] = counts.z;
      info[7] = layout.tilesPerRow.toDouble();
      info[8] = anchor.x;
      info[9] = anchor.y;
      info[10] = anchor.z;
      info[12] = previous.x;
      info[13] = previous.y;
      info[14] = previous.z;
      info[15] = reset;
      info[16] = startRow.toDouble();
      info[17] = endRow.toDouble();
      info[18] = layout.tileRows.toDouble();
      renderPass.clearBindings();
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _depthShader));
      bindVertexBufferCompat(renderPass, _fullscreenView, 6);
      renderPass.bindTexture(
        _depthShader.cachedUniformSlot('injection'),
        state._depthAccumulator!,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _depthShader.cachedUniformSlot('history'),
        history,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _depthShader.cachedUniformSlot('BlendDepthInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      drawCompat(renderPass, 6);
    }

    rendererSubmissions.submit(commandBuffer);
    state.finishBlend();
  }
}

/// Copies the blended field into the atlas the lit shader samples, writing the
/// gutter and the environment strip on the way.
class IrradianceFilterPass extends RenderGraphPass {
  IrradianceFilterPass({
    required this.state,
    required this.settings,
    required this.shStrip,
  });

  final IrradianceFieldState state;
  final GlobalIlluminationSettings settings;
  final gpu.Texture shStrip;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _filterShader =
      baseShaderLibrary['IrradianceFilterFragment']!;
  static final gpu.Shader _stripShader =
      baseShaderLibrary['IrradianceStripFragment']!;

  /// Scales a texel's own standard deviation into a blur factor, so a
  /// converged probe keeps its detail and a noisy one is smoothed.
  static const double _blurGain = 8.0;

  @override
  String get name => 'IrradianceFilterPass';

  @override
  void execute(RenderGraphContext context) {
    final layout = state._layout;
    if (layout == null) return;
    // finishBlend already swapped, so the freshly blended atlas is the read
    // side now.
    final blended = state._readHistory;
    final target = state._sampled!;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: target, loadAction: gpu.LoadAction.load),
      ),
    );
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);

    // The environment strip and the reserved state rows. Every pipeline
    // change inside a pass clears the bindings first, or an entry from the
    // previous shader's slot layout leaks into the next draw.
    renderPass.clearBindings();
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _stripShader));
    bindVertexBufferCompat(renderPass, _fullscreenView, 6);
    renderPass.bindTexture(
      _stripShader.cachedUniformSlot('sh_strip'),
      shStrip,
      sampler: _nearestClamp,
    );
    renderPass.bindUniform(
      _stripShader.cachedUniformSlot('StripInfo'),
      context.transientsBuffer.emplace(
        ByteData.sublistView(
          Float32List(4)
            ..[0] = layout.irradianceOriginY.toDouble()
            ..[1] = state.traceOwnsProbeState ? 1.0 : 0.0,
        ),
      ),
    );
    drawCompat(renderPass, 6);

    void region({
      required int originY,
      required int tile,
      required int interior,
      required double blur,
    }) {
      final info = Float32List(8)
        ..[0] = originY.toDouble()
        ..[1] = tile.toDouble()
        ..[2] = interior.toDouble()
        ..[3] = blur
        ..[4] = layout.tilesPerRow.toDouble()
        ..[5] = layout.tileRows.toDouble();
      renderPass.clearBindings();
      renderPass.bindPipeline(resolvePipeline(_vertexShader, _filterShader));
      bindVertexBufferCompat(renderPass, _fullscreenView, 6);
      renderPass.bindTexture(
        _filterShader.cachedUniformSlot('atlas'),
        blended,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _filterShader.cachedUniformSlot('FilterInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      drawCompat(renderPass, 6);
    }

    region(
      originY: layout.irradianceOriginY,
      tile: IrradianceFieldLayout.irradianceTile,
      interior: kIrradianceInterior,
      blur: _blurGain,
    );
    // Depth moments are copied, never blurred. Blurring them across
    // directions inflates the variance the Chebyshev test reads, which turns
    // a wall into a soft suggestion.
    region(
      originY: layout.depthOriginY,
      tile: IrradianceFieldLayout.depthTile,
      interior: kDepthMomentInterior,
      blur: 0.0,
    );

    rendererSubmissions.submit(commandBuffer);
  }
}

/// Fits each probe of the sampled atlas to linear spherical harmonics for the
/// cheap receiver ([IrradianceFieldReceiver.sphericalHarmonics]).
///
/// Rewrites the whole texture every frame, a few texels per probe, so it
/// follows a scroll, a bake, or a reset with no bookkeeping.
class IrradianceShPass extends RenderGraphPass {
  IrradianceShPass({required this.state});

  final IrradianceFieldState state;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _shShader =
      baseShaderLibrary['IrradianceShFragment']!;

  @override
  String get name => 'IrradianceShPass';

  @override
  void execute(RenderGraphContext context) {
    final layout = state._layout;
    final placement = state._placement;
    final atlas = state._sampled;
    final target = state.ensureShTexture();
    if (layout == null || placement == null || atlas == null) return;
    if (target == null) return;

    final counts = layout.resolution;
    final anchor = placement.anchor;
    final info = Float32List(12)
      ..[0] = counts.x
      ..[1] = counts.y
      ..[2] = counts.z
      ..[3] = layout.tilesPerRow.toDouble()
      ..[4] = anchor.x
      ..[5] = anchor.y
      ..[6] = anchor.z
      ..[7] = layout.irradianceOriginY.toDouble()
      ..[8] = layout.shSlicesPerRow.toDouble()
      ..[9] = layout.shBlockHeight.toDouble();

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = IrradianceInjectPass._fullscreenPass(
      commandBuffer,
      target,
    );
    renderPass.bindPipeline(resolvePipeline(_vertexShader, _shShader));
    bindVertexBufferCompat(renderPass, _fullscreenView, 6);
    renderPass.bindTexture(
      _shShader.cachedUniformSlot('atlas'),
      atlas,
      sampler: _nearestClamp,
    );
    renderPass.bindUniform(
      _shShader.cachedUniformSlot('ShInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(info)),
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
  }
}
