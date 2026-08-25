import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/global_illumination.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/render/depth_prepass.dart'
    show kLinearDepthBlackboardKey;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

/// The scene-owned GPU state of the irradiance field: the atlas the lit
/// shader samples, the ping-ponged blend history, and the scatter
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
  gpu.DeviceBuffer? _instanceBuffer;
  int _instanceCapacity = 0;

  bool _historyIsA = true;
  bool _resetPending = true;
  int _updateCursor = 0;
  int _lastUpdateMicros = 0;

  /// The atlas the lit shader samples, or null before the first update.
  gpu.Texture? get sampledAtlas => _sampled;

  /// This frame's layout, or null before the first update.
  IrradianceFieldLayout? get layout => _layout;

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

  /// Seconds since the previous update, clamped so a stall or a first frame
  /// cannot drive the retention exponent somewhere useless.
  double consumeDeltaSeconds() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final previous = _lastUpdateMicros;
    _lastUpdateMicros = now;
    if (previous == 0) return 1.0 / 60.0;
    return ((now - previous) / 1e6).clamp(1.0 / 240.0, 1.0 / 10.0);
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
    _instanceBuffer = null;
    _instanceCapacity = 0;
    _layout = null;
    _placement = null;
  }

  void _releaseTextures() {
    _historyA = null;
    _historyB = null;
    _sampled = null;
    _irradianceAccumulator = null;
    _depthAccumulator = null;
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

  /// A device buffer holding the sample indices `0..count`, one per instance.
  /// Grown on demand and reused, since it only changes with the injection
  /// resolution.
  gpu.BufferView _instances(int count) {
    if (_instanceBuffer == null || _instanceCapacity < count) {
      final capacity = math.max(count, 1024);
      final indices = Float32List(capacity);
      for (var i = 0; i < capacity; i++) {
        indices[i] = i.toDouble();
      }
      _instanceBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
        ByteData.sublistView(indices),
      );
      _instanceCapacity = capacity;
    }
    return gpu.BufferView(
      _instanceBuffer!,
      offsetInBytes: 0,
      lengthInBytes: count * 4,
    );
  }
}

// The unit quad the scatter expands, corners in [0, 1].
final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
  ByteData.sublistView(
    Float32List.fromList(<double>[
      0.0, 0.0, 1.0, 0.0, 0.0, 1.0, //
      0.0, 1.0, 1.0, 0.0, 1.0, 1.0, //
    ]),
  ),
);
final gpu.BufferView _quadView = gpu.BufferView(
  _quadBuffer,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

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

/// Slot 0 the per-vertex unit quad, slot 1 the per-instance sample index (a
/// float, since the broadest GLES tier has no integer vertex attributes).
final VertexLayoutDescriptor _injectLayout = VertexLayoutDescriptor(
  buffers: const [
    VertexBufferDescriptor(
      strideInBytes: 8,
      attributes: [
        VertexAttributeDescriptor(
          name: 'corner',
          format: gpu.VertexFormat.float32x2,
        ),
      ],
    ),
    VertexBufferDescriptor(
      strideInBytes: 4,
      stepMode: gpu.VertexStepMode.instance,
      attributes: [
        VertexAttributeDescriptor(
          name: 'texel_index',
          format: gpu.VertexFormat.float32,
        ),
      ],
    ),
  ],
);

final gpu.SamplerOptions _nearestClamp = gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.nearest,
  magFilter: gpu.MinMagFilter.nearest,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

final gpu.ColorBlendEquation _additive = gpu.ColorBlendEquation(
  colorBlendOperation: gpu.BlendOperation.add,
  sourceColorBlendFactor: gpu.BlendFactor.one,
  destinationColorBlendFactor: gpu.BlendFactor.one,
  alphaBlendOperation: gpu.BlendOperation.add,
  sourceAlphaBlendFactor: gpu.BlendFactor.one,
  destinationAlphaBlendFactor: gpu.BlendFactor.one,
);

/// Scatters the visible surfaces' shaded radiance and distance into the probe
/// accumulators.
///
/// One instanced quad per (screen texel, cage corner), eight draws covering
/// the cage. Instanced quads rather than points because that is the pattern
/// the splat renderer already proves on every backend; a point-primitive
/// variant would cut the vertex work but nothing in the engine exercises
/// `gl_PointSize` today.
class IrradianceInjectPass extends RenderGraphPass {
  IrradianceInjectPass({
    required this.state,
    required this.settings,
    required this.dimensions,
    required this.cameraPosition,
    required this.cameraRight,
    required this.cameraUp,
    required this.cameraForward,
    required this.tanHalfFovX,
    required this.tanHalfFovY,
    required this.far,
    required this.sceneRadiance,
  });

  final IrradianceFieldState state;
  final GlobalIlluminationSettings settings;
  final ui.Size dimensions;
  final Vector3 cameraPosition;
  final Vector3 cameraRight;
  final Vector3 cameraUp;
  final Vector3 cameraForward;
  final double tanHalfFovX;
  final double tanHalfFovY;
  final double far;
  final gpu.Texture? sceneRadiance;

  static final gpu.Shader _vertexShader =
      baseShaderLibrary['IrradianceInjectVertex']!;
  static final gpu.Shader _irradianceShader =
      baseShaderLibrary['IrradianceInjectFragment']!;
  static final gpu.Shader _depthShader =
      baseShaderLibrary['IrradianceInjectDepthFragment']!;

  @override
  String get name => 'IrradianceInjectPass';

  @override
  void execute(RenderGraphContext context) {
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
    final texels = sourceWidth * sourceHeight;
    if (texels == 0) return;
    final instances = state._instances(texels);

    // A nonzero update budget leaves unscheduled probes accumulating across
    // frames, so their samples are still there when their turn comes.
    final clear = settings.probeUpdateBudget <= 0;

    _scatter(
      context: context,
      target: state._irradianceAccumulator!,
      fragmentShader: _irradianceShader,
      depthNormal: depthNormal,
      radiance: radiance,
      instances: instances,
      instanceCount: texels,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      layout: layout,
      placement: placement,
      tileSize: IrradianceFieldLayout.irradianceTile.toDouble(),
      interior: kIrradianceInterior.toDouble(),
      // A cosine lobe spans the whole hemisphere, so every interior texel of
      // the tile can see this sample.
      footprint: -1.0,
      targetWidth: layout.injectionIrradianceWidth,
      targetHeight: layout.injectionIrradianceHeight,
      clear: clear,
    );
    _scatter(
      context: context,
      target: state._depthAccumulator!,
      fragmentShader: _depthShader,
      depthNormal: depthNormal,
      radiance: radiance,
      instances: instances,
      instanceCount: texels,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      layout: layout,
      placement: placement,
      tileSize: IrradianceFieldLayout.depthTile.toDouble(),
      interior: kDepthMomentInterior.toDouble(),
      footprint: kDepthScatterRadius.toDouble(),
      targetWidth: layout.injectionDepthWidth,
      targetHeight: layout.injectionDepthHeight,
      clear: clear,
    );
  }

  void _scatter({
    required RenderGraphContext context,
    required gpu.Texture target,
    required gpu.Shader fragmentShader,
    required gpu.Texture depthNormal,
    required gpu.Texture radiance,
    required gpu.BufferView instances,
    required int instanceCount,
    required int sourceWidth,
    required int sourceHeight,
    required IrradianceFieldLayout layout,
    required IrradianceGridPlacement placement,
    required double tileSize,
    required double interior,
    required double footprint,
    required int targetWidth,
    required int targetHeight,
    required bool clear,
  }) {
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: target,
          loadAction: clear ? gpu.LoadAction.clear : gpu.LoadAction.load,
          clearValue: Vector4.zero(),
        ),
      ),
    );
    renderPass.bindPipeline(
      resolvePipeline(
        _vertexShader,
        fragmentShader,
        vertexLayout: _injectLayout,
      ),
    );
    // GLES holds cull mode and winding as global state that leaks across
    // passes, so the scatter sets its own rather than inheriting.
    renderPass.setCullMode(gpu.CullMode.none);
    renderPass.setPrimitiveType(gpu.PrimitiveType.triangle);
    renderPass.setColorBlendEnable(true);
    renderPass.setColorBlendEquation(_additive);
    bindVertexBufferCompat(renderPass, _quadView, 6);
    renderPass.bindVertexBuffer(instances, slot: 1);
    renderPass.bindTexture(
      _vertexShader.getUniformSlot('linear_depth_normal'),
      depthNormal,
      sampler: _nearestClamp,
    );
    renderPass.bindTexture(
      _vertexShader.getUniformSlot('scene_radiance'),
      radiance,
      sampler: _nearestClamp,
    );

    final tileInfo = Float32List(4)
      ..[0] = tileSize
      ..[1] = interior;
    renderPass.bindUniform(
      fragmentShader.getUniformSlot('InjectTileInfo'),
      context.transientsBuffer.emplace(ByteData.sublistView(tileInfo)),
    );

    final spacing = placement.spacing;
    final anchor = placement.anchor;
    final counts = layout.resolution;
    final info = Float32List(48);
    info[0] = sourceWidth.toDouble();
    info[1] = sourceHeight.toDouble();
    info[2] = 1.0 / sourceWidth;
    info[3] = 1.0 / sourceHeight;
    info[4] = tanHalfFovX;
    info[5] = tanHalfFovY;
    info[6] = far;
    info[7] = settings.fireflyClamp;
    info[8] = cameraPosition.x;
    info[9] = cameraPosition.y;
    info[10] = cameraPosition.z;
    info[11] = settings.emissiveGiBoost;
    info[12] = cameraRight.x;
    info[13] = cameraRight.y;
    info[14] = cameraRight.z;
    info[16] = cameraUp.x;
    info[17] = cameraUp.y;
    info[18] = cameraUp.z;
    info[20] = cameraForward.x;
    info[21] = cameraForward.y;
    info[22] = cameraForward.z;
    info[24] = spacing.x;
    info[25] = spacing.y;
    info[26] = spacing.z;
    info[27] = placement.maxProbeDistance;
    info[28] = anchor.x;
    info[29] = anchor.y;
    info[30] = anchor.z;
    info[32] = counts.x;
    info[33] = counts.y;
    info[34] = counts.z;
    info[35] = layout.tilesPerRow.toDouble();
    info[36] = tileSize;
    info[37] = interior;
    info[38] = footprint;
    info[40] = targetWidth.toDouble();
    info[41] = targetHeight.toDouble();
    info[42] = 1.0 / targetWidth;
    info[43] = 1.0 / targetHeight;

    for (var corner = 0; corner < 8; corner++) {
      info[44] = (corner & 1) != 0 ? 1.0 : 0.0;
      info[45] = (corner & 2) != 0 ? 1.0 : 0.0;
      info[46] = (corner & 4) != 0 ? 1.0 : 0.0;
      renderPass.bindUniform(
        _vertexShader.getUniformSlot('InjectInfo'),
        context.transientsBuffer.emplace(ByteData.sublistView(info)),
      );
      drawCompat(renderPass, 6, instanceCount: instanceCount);
    }
    rendererSubmissions.submit(commandBuffer);
  }
}

/// Folds this frame's scattered samples into the stored field.
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

    final dt = state.consumeDeltaSeconds();
    // Retention is authored at 60 Hz and raised to this frame's real service
    // interval, so a throttled frame rate converges at the same wall-clock
    // rate instead of blending in more noise per frame.
    final retention = math
        .pow(settings.hysteresis.clamp(0.0, 0.999), math.min(1.0, dt * 60.0))
        .toDouble();
    final (startRow, endRow) = state.scheduleRows(settings.probeUpdateBudget);
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
        _irradianceShader.getUniformSlot('injection'),
        state._irradianceAccumulator!,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _irradianceShader.getUniformSlot('history'),
        history,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _irradianceShader.getUniformSlot('sh_strip'),
        shStrip,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _irradianceShader.getUniformSlot('BlendInfo'),
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
        _depthShader.getUniformSlot('injection'),
        state._depthAccumulator!,
        sampler: _nearestClamp,
      );
      renderPass.bindTexture(
        _depthShader.getUniformSlot('history'),
        history,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _depthShader.getUniformSlot('BlendDepthInfo'),
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
      _stripShader.getUniformSlot('sh_strip'),
      shStrip,
      sampler: _nearestClamp,
    );
    renderPass.bindUniform(
      _stripShader.getUniformSlot('StripInfo'),
      context.transientsBuffer.emplace(
        ByteData.sublistView(
          Float32List(4)..[0] = layout.irradianceOriginY.toDouble(),
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
        _filterShader.getUniformSlot('atlas'),
        blended,
        sampler: _nearestClamp,
      );
      renderPass.bindUniform(
        _filterShader.getUniformSlot('FilterInfo'),
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
