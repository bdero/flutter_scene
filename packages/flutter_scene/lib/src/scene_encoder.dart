import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugPrint, internal, kDebugMode, visibleForTesting;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/material/instance_attributes.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/depth_raster.dart';
import 'package:flutter_scene/src/render/debug_view.dart';
import 'package:flutter_scene/src/render/draw_recorder.dart';
import 'package:flutter_scene/src/mesh_draw.dart';
import 'package:flutter_scene/src/render/mesh_draw_selection.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/render_profile.dart';
import 'package:flutter_scene/src/render/render_stats.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/instance_batching.dart';
import 'package:flutter_scene/src/shaders.dart';

/// A deferred opaque draw. Holds the [RenderItem] (instanced or not), its
/// resolved pipeline, a per-pipeline grouping key, and the camera
/// distance, all captured when [SceneEncoder.submit] is called.
base class _OpaqueRecord implements OpaqueBatchRecord {
  _OpaqueRecord(
    RenderItem item,
    Geometry geometry,
    Material material,
    this.fade,
    gpu.RenderPipeline pipeline,
    this.pipelineKey,
    this.windingFlipped,
  ) : _item = item,
      _geometry = geometry,
      _material = material,
      _pipeline = pipeline,
      geometryKey = identityHashCode(geometry),
      materialKey = identityHashCode(material);
  RenderItem? _item;
  RenderItem get item => _item!;
  @override
  bool get hasDrawSelector => hasMeshDrawSelector(item);
  // The geometry and material to draw, which differ from the item's own when
  // a level of detail was selected.
  Geometry? _geometry;
  @override
  Geometry get geometry => _geometry!;
  Material? _material;
  @override
  Material get material => _material!;
  // LOD cross-fade coverage for this draw (1 when not fading); see
  // [Material.lodFade].
  @override
  late double fade;
  gpu.RenderPipeline? _pipeline;
  @override
  gpu.RenderPipeline get pipeline => _pipeline!;
  late int pipelineKey;
  late bool windingFlipped;

  // View depth, NaN until the sort first needs it. Depth is the last
  // tie-breaker, so most records never compute it.
  double depth = double.nan;

  void reset(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    int pipelineKey,
    bool windingFlipped,
  ) {
    _item = item;
    _geometry = geometry;
    _material = material;
    this.fade = fade;
    _pipeline = pipeline;
    this.pipelineKey = pipelineKey;
    depth = double.nan;
    this.windingFlipped = windingFlipped;
    geometryKey = identityHashCode(geometry);
    materialKey = identityHashCode(material);
  }

  // Identity sort keys, cached at submit time rather than recomputed per
  // comparison. The opaque sort reads them O(n log n) times, and
  // identityHashCode is a runtime call that installs a hash in the object
  // header on first use, so computing them once per record keeps the
  // comparator to plain integer compares.
  late int geometryKey;
  late int materialKey;
  @override
  int get lightListOffset => item.lightListOffset;
  @override
  int get lightListCount => item.lightListCount;
  @override
  int get lightChannelMask => item.lightChannelMask;
  @override
  Object? get jointsTexture => item.jointsTexture;
  @override
  Object? get morphWeights => item.morphWeights;

  void release() {
    _item = null;
    _geometry = null;
    _material = null;
    _pipeline = null;
  }
}

/// A deferred translucent draw. Instanced draws retain their item so their
/// transforms can be sorted while the instance buffer is packed.
base class _TranslucentRecord {
  _TranslucentRecord(
    RenderItem item,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    this.fade,
    gpu.RenderPipeline pipeline,
    this.depth,
    this.windingFlipped,
    this.lightListOffset,
    this.lightListCount,
    this.jointsTexture,
    this.jointsTextureWidth,
  ) : _item = item,
      _worldTransform = worldTransform,
      _geometry = geometry,
      _material = material,
      _pipeline = pipeline;
  RenderItem? _item;
  RenderItem get item => _item!;
  Matrix4? _worldTransform;
  Matrix4 get worldTransform => _worldTransform!;
  Geometry? _geometry;
  Geometry get geometry => _geometry!;
  Material? _material;
  Material get material => _material!;
  late double fade;
  gpu.RenderPipeline? _pipeline;
  gpu.RenderPipeline get pipeline => _pipeline!;
  late double depth;
  late bool windingFlipped;
  // The owning item's punctual-light slice, captured at submit time.
  late int lightListOffset;
  late int lightListCount;
  // The owning item's joints texture, applied to the geometry right before
  // this draw so skinned items sharing one geometry keep their own skeleton.
  late gpu.Texture? jointsTexture;
  late int jointsTextureWidth;
  ui.Rect? screenBounds;
  ui.Rect? sceneColorSampleBounds;

  void reset(
    RenderItem item,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    double depth,
    bool windingFlipped,
    int lightListOffset,
    int lightListCount,
    gpu.Texture? jointsTexture,
    int jointsTextureWidth,
  ) {
    _item = item;
    _worldTransform = worldTransform;
    _geometry = geometry;
    _material = material;
    this.fade = fade;
    _pipeline = pipeline;
    this.depth = depth;
    this.windingFlipped = windingFlipped;
    this.lightListOffset = lightListOffset;
    this.lightListCount = lightListCount;
    this.jointsTexture = jointsTexture;
    this.jointsTextureWidth = jointsTextureWidth;
  }

  void release() {
    _item = null;
    _worldTransform = null;
    _geometry = null;
    _material = null;
    _pipeline = null;
    jointsTexture = null;
    screenBounds = null;
    sceneColorSampleBounds = null;
  }
}

const int _transmissionCoverageColumns = 32;
const int _transmissionCoverageRows = 32;

/// Maximum accumulated scene-color batches emitted in one frame, and the
/// default and upper bound of `Scene.sceneColorCaptureBatches`.
/// {@category Rendering}
const int maxSceneColorCaptureBatches = 8;

base class _ScreenCoverage {
  _ScreenCoverage(this.viewport);

  final ui.Size viewport;
  final Uint32List _rows = Uint32List(_transmissionCoverageRows);

  bool overlaps(ui.Rect bounds) {
    final cells = _cells(bounds);
    final mask = _columnMask(cells.left, cells.right);
    for (var row = cells.top; row <= cells.bottom; row++) {
      if ((_rows[row] & mask) != 0) return true;
    }
    return false;
  }

  void add(ui.Rect bounds) {
    final cells = _cells(bounds);
    final left = cells.left > 0 ? cells.left - 1 : 0;
    final right = cells.right + 1 < _transmissionCoverageColumns
        ? cells.right + 1
        : _transmissionCoverageColumns - 1;
    final top = cells.top > 0 ? cells.top - 1 : 0;
    final bottom = cells.bottom + 1 < _transmissionCoverageRows
        ? cells.bottom + 1
        : _transmissionCoverageRows - 1;
    final mask = _columnMask(left, right);
    for (var row = top; row <= bottom; row++) {
      _rows[row] |= mask;
    }
  }

  ({int left, int top, int right, int bottom}) _cells(ui.Rect bounds) {
    if (viewport.isEmpty || !bounds.isFinite || bounds.isEmpty) {
      return (
        left: 0,
        top: 0,
        right: _transmissionCoverageColumns - 1,
        bottom: _transmissionCoverageRows - 1,
      );
    }
    final left = (bounds.left / viewport.width * _transmissionCoverageColumns)
        .floor();
    final right =
        (bounds.right / viewport.width * _transmissionCoverageColumns).ceil() -
        1;
    final top = (bounds.top / viewport.height * _transmissionCoverageRows)
        .floor();
    final bottom =
        (bounds.bottom / viewport.height * _transmissionCoverageRows).ceil() -
        1;
    return (
      left: left.clamp(0, _transmissionCoverageColumns - 1),
      top: top.clamp(0, _transmissionCoverageRows - 1),
      right: right.clamp(0, _transmissionCoverageColumns - 1),
      bottom: bottom.clamp(0, _transmissionCoverageRows - 1),
    );
  }

  static int _columnMask(int left, int right) {
    final width = right - left + 1;
    if (width >= 32) return 0xffffffff;
    return ((1 << width) - 1) << left;
  }
}

int _sceneColorBatchEnd<T>(
  List<T> records,
  int cursor,
  ui.Size viewport, {
  required bool Function(T record) readsSceneColor,
  required ui.Rect Function(T record) outputBounds,
  required ui.Rect Function(T record) sampleBounds,
}) {
  final coverage = _ScreenCoverage(viewport);
  var end = cursor;
  while (end < records.length) {
    final record = records[end];
    if (end > cursor &&
        readsSceneColor(record) &&
        coverage.overlaps(sampleBounds(record))) {
      break;
    }
    coverage.add(outputBounds(record));
    end++;
  }
  return end;
}

/// Counts accumulated scene-color captures for sorted translucent draws.
@visibleForTesting
int sceneColorCaptureBatchCount(
  List<({ui.Rect bounds, bool readsSceneColor})> records,
  ui.Size viewport,
) {
  var cursor = 0;
  var batches = 0;
  while (cursor < records.length) {
    while (cursor < records.length && !records[cursor].readsSceneColor) {
      cursor++;
    }
    if (cursor == records.length) break;
    batches++;
    if (batches == maxSceneColorCaptureBatches) break;
    cursor = _sceneColorBatchEnd(
      records,
      cursor,
      viewport,
      readsSceneColor: (record) => record.readsSceneColor,
      outputBounds: (record) => record.bounds,
      sampleBounds: (record) => record.bounds,
    );
  }
  return batches;
}

/// The viewport size of the scene color pass currently being encoded.
///
/// Set by [SceneEncoder] at construction and read by geometry whose
/// projection math needs the pixel scale (splat footprints). Encoding is
/// single-threaded, so a frame-scoped module value is safe.
/// TODO(splats): thread the viewport through `Geometry.bind` instead once
/// another consumer appears.
ui.Size currentSceneEncoderViewport = ui.Size.zero;

/// Computes the view-axis depth used to order deferred scene draws.
@visibleForTesting
double sceneSortDepth(
  Matrix4 worldTransform,
  Aabb3? localBounds,
  Vector3 cameraPosition,
  Vector3 cameraForward,
) {
  // Kept allocation-free. This runs once per submitted draw per view, and
  // views multiply with the shadow, depth-prepass, and reflection passes.
  // `Aabb3.center` clones, `transformed3` clones, and `-` allocates again,
  // so the vector_math spelling costs three Vector3s per call.
  var cx = 0.0;
  var cy = 0.0;
  var cz = 0.0;
  if (localBounds != null) {
    final min = localBounds.min;
    final max = localBounds.max;
    cx = (min.x + max.x) * 0.5;
    cy = (min.y + max.y) * 0.5;
    cz = (min.z + max.z) * 0.5;
  }
  final m = worldTransform.storage;
  final worldX = m[0] * cx + m[4] * cy + m[8] * cz + m[12];
  final worldY = m[1] * cx + m[5] * cy + m[9] * cz + m[13];
  final worldZ = m[2] * cx + m[6] * cy + m[10] * cz + m[14];
  return (worldX - cameraPosition.x) * cameraForward.x +
      (worldY - cameraPosition.y) * cameraForward.y +
      (worldZ - cameraPosition.z) * cameraForward.z;
}

/// Render pipelines keyed by their (vertex shader, fragment shader, vertex
/// layout) triple.
///
/// A pipeline depends on its two shaders and its vertex layout (blend,
/// depth, and cull state are set on the render pass, not baked into the
/// pipeline). Shaders are loaded once and reused and layouts are interned to
/// a small stable id, so pipelines are cached for the process lifetime
/// instead of being rebuilt per draw call. The layout is part of the key
/// because one vertex shader can be drawn with more than one layout (for
/// example the same shader fed a single-buffer or a position-split layout);
/// keying on the shader pair alone would serve the wrong pipeline.
final Map<(gpu.Shader, gpu.Shader, int), gpu.RenderPipeline> _pipelineCache =
    {};

/// Pipeline keys the backend refused to build, so a rejected pairing is not
/// retried every frame. Keyed exactly like [_pipelineCache] and evicted with
/// it, so one bad shader variant does not disable the variants that build, and
/// a hot-reloaded shader gets a fresh attempt instead of staying invisible
/// until restart.
final Set<(gpu.Shader, gpu.Shader, int)> _rejectedPipelines = {};

// A sliced warm-up's build budget: while set, new pipelines stop building
// once builds have taken this long, and the draws that need the rest are
// skipped and counted, so the warm-up yields and tries them next slice.
Duration? _buildBudget;
final Stopwatch _buildClock = Stopwatch();
int _deferredBuilds = 0;

/// Runs [body] with new pipeline builds capped at [budget] of build time;
/// draws past it are skipped and counted in [deferredPipelineBuilds].
@internal
T withPipelineBuildBudget<T>(Duration budget, T Function() body) {
  _buildBudget = budget;
  _buildClock
    ..stop()
    ..reset();
  _deferredBuilds = 0;
  try {
    return body();
  } finally {
    _buildBudget = null;
  }
}

/// Draws the last [withPipelineBuildBudget] skipped for lack of budget.
@internal
int get deferredPipelineBuilds => _deferredBuilds;

bool _deferBuild((gpu.Shader, gpu.Shader, int) key) {
  final budget = _buildBudget;
  if (budget == null || _pipelineCache.containsKey(key)) return false;
  if (_buildClock.elapsed < budget) return false;
  _deferredBuilds++;
  return true;
}

/// Pipelines currently held in the process-wide cache.
int get pipelineCacheSize => _pipelineCache.length;

/// Returns the cached render pipeline for ([vertexShader], [fragmentShader],
/// [vertexLayout]), building and caching it on first use.
///
/// A `null` [vertexLayout] uses the shader bundle's reflection-derived
/// default layout (the skinned path); a described layout is lowered to the
/// flutter_gpu layout once, on the cache miss.
gpu.RenderPipeline resolvePipeline(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader, {
  VertexLayoutDescriptor? vertexLayout,
  String Function()? debugContext,
}) {
  final key = (vertexShader, fragmentShader, vertexLayoutId(vertexLayout));
  final cached = _pipelineCache[key];
  if (cached != null) return cached;
  activeRenderCounters.pipelineBuilds++;
  final stopwatch = kDebugMode || profileRendering
      ? (Stopwatch()..start())
      : null;
  if (_buildBudget != null) _buildClock.start();
  final pipeline = gpu.gpuContext.createRenderPipeline(
    vertexShader,
    fragmentShader,
    vertexLayout: vertexLayout?.toGpuLayout(),
  );
  _buildClock.stop();
  if (stopwatch != null) {
    stopwatch.stop();
    // A backend pipeline build is synchronous and lands mid-frame the first
    // time a shader pair draws, so a slow one is frame jank. Surface it so
    // the fix (pre-warming the draw during a load screen) has a target.
    if (stopwatch.elapsedMilliseconds >= 8) {
      debugPrint(
        'flutter_scene: pipeline build took '
        '${stopwatch.elapsedMilliseconds}ms mid-frame'
        '${debugContext != null ? ' for ${debugContext()}' : ''}. '
        'Draw this material once during a load screen to move the cost '
        'off the first visible frame.',
      );
    }
  }
  return _pipelineCache[key] = pipeline;
}

/// [resolvePipeline], or null when a sliced warm-up has spent its build
/// budget and the pipeline is not built yet (the caller skips the draw).
@internal
gpu.RenderPipeline? resolvePipelineOrDefer(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader, {
  VertexLayoutDescriptor? vertexLayout,
}) {
  if (_deferBuild((
    vertexShader,
    fragmentShader,
    vertexLayoutId(vertexLayout),
  ))) {
    return null;
  }
  return resolvePipeline(
    vertexShader,
    fragmentShader,
    vertexLayout: vertexLayout,
  );
}

/// Drops cached pipelines that use any of [shaders] (as vertex or fragment) so
/// the next draw rebuilds them.
///
/// Used after an in-place shader hot reload: `ShaderLibrary.reinitialize`
/// reloads a [gpu.Shader]'s code while keeping its Dart identity, so the
/// pipeline cache (keyed by the shader pair) would otherwise keep serving a
/// pipeline built from the old code. Hidden from the public surface; called by
/// the hot-reload coordinator.
void evictPipelinesForShaders(Set<gpu.Shader> shaders) {
  if (shaders.isEmpty) return;
  _pipelineCache.removeWhere(
    (key, _) => shaders.contains(key.$1) || shaders.contains(key.$2),
  );
  _rejectedPipelines.removeWhere(
    (key) => shaders.contains(key.$1) || shaders.contains(key.$2),
  );
}

/// [resolvePipeline], returning null instead of throwing when the backend
/// refuses to build the pipeline, and remembering the refusal so it is
/// attempted once rather than every frame.
///
/// Used by the scene encoder, where a pairing the backend cannot build (most
/// often a custom-attribute geometry drawn by a material whose vertex stage
/// does not declare those attributes) reaches the renderer from user data.
/// Throwing there escapes `paint` and blanks the frame, so the draw is skipped
/// and the reason reported once instead. Shader resolution and layout
/// validation stay outside this guard, so a missing shader or a malformed
/// layout still surfaces.
gpu.RenderPipeline? tryResolvePipeline(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader, {
  VertexLayoutDescriptor? vertexLayout,
  String Function()? debugContext,
}) {
  final key = (vertexShader, fragmentShader, vertexLayoutId(vertexLayout));
  if (_rejectedPipelines.contains(key)) return null;
  if (_deferBuild(key)) return null;
  try {
    return resolvePipeline(
      vertexShader,
      fragmentShader,
      vertexLayout: vertexLayout,
      debugContext: debugContext,
    );
  } on Exception catch (error) {
    _rejectedPipelines.add(key);
    debugPrint(
      'flutter_scene: skipping a draw whose pipeline failed to build'
      '${debugContext != null ? ' (${debugContext()})' : ''}. $error',
    );
    return null;
  }
}

// A pipeline is rejected once its draws fail in this many frames with no
// successful draw between. A shader the driver cannot build fails every
// frame, while a one-off failure (a descriptor pool running dry on Vulkan)
// does not recur.
const int _kRejectAfterFailedFrames = 3;

// Failure streaks for pipelines whose last draw failed, as (last failing
// frame, failing frame count). Cleared by a successful draw, so it is empty,
// and free to check, in steady state.
final Map<gpu.RenderPipeline, (int, int)> _failingPipelines = {};

int _drawFailureFrame = 0;

// Pipelines whose failed draws were already reported, so a failure that
// keeps recurring between successful draws is logged once.
final Expando<bool> _reportedDrawFailures = Expando();

/// Starts a new frame for the failed-draw streaks [drawOrRejectPipeline]
/// keeps, so a pipeline drawn in several passes of one frame counts once.
void beginDrawFailureFrame() {
  if (_failingPipelines.isNotEmpty) _drawFailureFrame++;
}

/// Draws [geometry] on [pass], skipping the draw instead of throwing when the
/// backend refuses it.
///
/// GLES compiles and links the program at the first draw, so a shader the
/// driver rejects fails here rather than in [tryResolvePipeline], and keeps
/// failing every frame after. Once [pipeline], the one bound for the draw,
/// fails in several frames with no successful draw between, it is
/// rejected like a failed build, so later frames skip its draws and the rest
/// of the scene still renders. A failure that does not persist only skips
/// the draw.
void drawOrRejectPipeline(
  gpu.RenderPass pass,
  Geometry geometry,
  gpu.RenderPipeline? pipeline, {
  int instanceCount = 1,
  Material? material,
}) {
  try {
    geometry.draw(pass, instanceCount: instanceCount);
  } on Exception catch (error) {
    if (pipeline == null) rethrow;
    _recordFailedDraw(pipeline, geometry, material, error);
    return;
  }
  if (_failingPipelines.isNotEmpty && pipeline != null) {
    _failingPipelines.remove(pipeline);
  }
}

void _recordFailedDraw(
  gpu.RenderPipeline pipeline,
  Geometry geometry,
  Material? material,
  Exception error,
) {
  final streak = _failingPipelines[pipeline];
  if (streak != null && streak.$1 == _drawFailureFrame) return;
  final failedFrames = (streak?.$2 ?? 0) + 1;
  final subject =
      '${material != null ? '${fmatSourcePathOf(material) ?? material.runtimeType} on ' : ''}'
      '${geometry.runtimeType}';
  if (failedFrames < _kRejectAfterFailedFrames) {
    _failingPipelines[pipeline] = (_drawFailureFrame, failedFrames);
    if (_reportedDrawFailures[pipeline] ?? false) return;
    _reportedDrawFailures[pipeline] = true;
    debugPrint(
      'flutter_scene: skipped a draw the backend refused ($subject). $error',
    );
    return;
  }
  _failingPipelines.remove(pipeline);
  for (final entry in _pipelineCache.entries) {
    if (!identical(entry.value, pipeline)) continue;
    _pipelineCache.remove(entry.key);
    _rejectedPipelines.add(entry.key);
    break;
  }
  debugPrint(
    'flutter_scene: skipping draws whose pipeline the backend refused in '
    '$failedFrames frames ($subject). $error',
  );
}

/// Records draw calls for one frame's color pass into a single
/// `gpu.RenderPass`.
///
/// A render-graph pass (see `ScenePass`) creates a `gpu.RenderPass`,
/// constructs an encoder against it, calls [submit] for every
/// [RenderItem] the scene's spatial structure reports visible, then calls
/// [flush] to sort and emit the deferred draws.
///
/// The encoder splits draws into two phases within the one render pass:
///
/// 1. **Opaque**, with depth writes enabled and color blending disabled,
///    sorted by pipeline, material, and geometry (to reduce state changes
///    and batch identical draws), with front-to-back depth only breaking
///    ties among draws that share all three.
/// 2. **Translucent**, depth-sorted back to front from the camera, drawn
///    with premultiplied source-over blending.
///
/// Applications typically do not construct `SceneEncoder` directly;
/// custom [Geometry] or [Material] subclasses interact with it through
/// their `bind` callbacks, which receive the `gpu.RenderPass` and
/// `TransientWriter` directly.
base class SceneEncoder {
  static final RenderProfileAccumulator _profile = RenderProfileAccumulator();
  int _instancePackMicros = 0;
  int _instanceBindMicros = 0;
  int _instanceBytes = 0;
  int _opaqueSortMicros = 0;
  int _opaqueEncodeMicros = 0;

  /// Creates an encoder that records into [renderPass], allocating
  /// transient uniforms from [transientsBuffer].
  ///
  /// `dimensions` is the viewport size used to derive the camera's view
  /// transform; [lighting] is the scene's IBL environment and analytic
  /// lights, passed to each material's `bind`. The render pass is
  /// configured for the opaque phase (depth writes on, blending off).
  SceneEncoder(
    gpu.RenderPass renderPass,
    TransientWriter transientsBuffer,
    this._camera,
    this._dimensions,
    this._lighting,
    this._layerMask,
    this._cullingPlanes,
    this._cullInstances, {
    Matrix4? cameraTransform,
    Matrix4? displayReferredCameraTransform,
    DebugViewFrame? debugView,
    bool primaryView = true,
  }) : _renderPass = renderPass,
       _transientsBuffer = transientsBuffer,
       _debugView = debugView,
       _primaryView = primaryView {
    currentSceneEncoderViewport = _dimensions;
    // Read once. A camera's getters may allocate, and both feed every draw.
    _cameraPosition = _camera.position;
    _cameraForward = _camera.forward;
    _raster = depthRasterOf(_camera);
    _pixelSlope = pixelDepthSlopeOf(_camera, _dimensions);
    _pixelScale = pixelWorldScaleOf(_camera, _dimensions);
    _cameraTransform =
        cameraTransform ?? rasterViewTransformOf(_camera, _dimensions);
    _displayReferredCameraTransform = displayReferredCameraTransform;
    frustum = cullingFrustumOf(_camera, _dimensions);
    // A degenerate projection has no screen-size metric, so LOD nodes draw
    // their highest-detail level.
    final projection = ProjectionParams.of(_camera.projection, _dimensions);
    _lodProjection = projection.scaleY > 0.0 ? projection : null;

    // Begin the opaque phase.
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(_raster.nearerOrEqual);
  }

  final Camera _camera;
  late final Vector3 _cameraPosition;
  late final Vector3 _cameraForward;

  // How this view rasterizes depth (reversed or not, fitted near), shared
  // with every other pass that draws into its depth buffers.
  late final DepthRaster _raster;

  // The view's pixelDepthSlope, for slope-scaled depth offsets.
  late final double _pixelSlope;

  // The view's pixelWorldScale, for the depth gap debug view.
  late final double _pixelScale;

  // Whether this encodes a screen view's camera, for [MeshDrawSelector]s.
  final bool _primaryView;
  final ui.Size _dimensions;
  final Lighting _lighting;
  final int _layerMask;
  // The frame's surface debug view state, or null when none is active.
  final DebugViewFrame? _debugView;
  // The DebugViewInfo block for one draw, and the shared block that turns
  // the view off, emplaced once per encoder on first use.
  final Float32List _debugViewScratch = Float32List(DebugViewFrame.floatCount);
  gpu.BufferView? _debugViewInactive;
  // Which material the inactive block is bound for, so a run of draws with
  // one material binds it once.
  Material? _debugViewBoundMaterial;
  bool _debugViewBoundFallback = false;
  static final gpu.Shader _debugFallbackShader =
      baseShaderLibrary['DebugSurfaceFragment']!;
  final List<Plane> _cullingPlanes;
  final bool _cullInstances;
  // Not final because opaque and translucent draws can use separate passes.
  gpu.RenderPass _renderPass;
  final TransientWriter _transientsBuffer;
  // The view-projection draws rasterize with (see DepthRaster); culling uses
  // [frustum], built from the standard mapping.
  late final Matrix4 _cameraTransform;

  // The transform the display-referred layer draws with, when it differs from
  // the scene's. Under TAA the scene is jittered and resolved temporally, but
  // this layer composites after that resolve, so drawing it jittered would
  // shake it by the jitter every frame.
  late final Matrix4? _displayReferredCameraTransform;

  // Swapped in for the display-referred flush; null everywhere else. Only the
  // draw transform changes, not culling or screen bounds, which stay on the
  // scene's own frustum.
  Matrix4? _drawTransformOverride;

  Matrix4 get _drawCameraTransform =>
      _drawTransformOverride ?? _cameraTransform;
  // The projection terms for screen-size LOD, or null for a degenerate
  // projection (which disables it).
  late final ProjectionParams? _lodProjection;
  final List<_OpaqueRecord> _opaqueRecords = [];
  final List<_TranslucentRecord> _translucentRecords = [];
  final List<_TranslucentRecord> _displayReferredRecords = [];
  static final List<_OpaqueRecord> _opaqueRecordPool = [];
  static final List<_TranslucentRecord> _translucentRecordPool = [];
  // Refilled per batch group and consumed synchronously by
  // packInstanceDataBatches, which only reads it. The pool reuses both the
  // list and the batch objects in it, so a scene with many batched groups
  // allocates neither per group per frame.
  final InstanceDataBatchPool _batchPool = InstanceDataBatchPool();
  static const int _recordPoolLimit = 8192;

  /// View frustum derived from the camera's view-projection matrix at
  /// the start of this frame. Used by [submit] for per-item culling.
  late final Frustum frustum;

  /// The view-projection this encoder draws with.
  @internal
  Matrix4 get cameraTransform => _cameraTransform;

  // The pipeline currently bound on the render pass, or null before the
  // first bind. `clearBindings` does not clear the pipeline, so a draw
  // that reuses it can skip the rebind. Opaque draws are pipeline-sorted,
  // so reuse runs are common.
  gpu.RenderPipeline? _boundPipeline;
  Material? _boundMaterial;
  bool _boundMaterialFallback = false;
  gpu.Shader? _boundMaterialVertex;
  gpu.Shader? _boundFrameInfoShader;
  double _boundFrameInfoDepthBias = double.nan;
  int _boundFrameInfoDepthKey = -1;
  double _boundMaterialFade = double.nan;
  int _boundMaterialLightOffset = -1;
  int _boundMaterialLightCount = -1;
  int _boundMaterialLightChannelMask = -1;
  gpu.WindingOrder? _boundWindingOrder;
  gpu.PrimitiveType? _boundPrimitiveType;
  int _encodedDraws = 0;
  int _encodedInstances = 0;
  DrawPhase _phase = DrawPhase.opaque;

  /// Queues a draw call for [item], unless it is hidden or frustum
  /// culled.
  ///
  /// Both opaque and translucent draws are deferred; [flush] sorts and
  /// emits them. A translucent instanced item is queued as one draw per
  /// instance so each can be depth-sorted independently.
  void submit(RenderItem item) {
    activeRenderCounters.submitted++;
    if (!item.drawsColor) return;
    if ((item.layers & _layerMask) == 0) {
      activeRenderCounters.layerMasked++;
      activeDrawRecorder?.onSkip(item, DrawSkipReason.layerMasked);
      return;
    }
    if (_cullInstances) {
      if (!item.cullVisibleInstances(frustum, _cullingPlanes)) {
        activeRenderCounters.culled++;
        activeDrawRecorder?.onSkip(item, DrawSkipReason.frustumCulled);
        return;
      }
    } else {
      item.visibleInstanceIndices = null;
    }

    // The render scene already rejected this item through its BVH. Reuse its
    // retained world bounds for the LOD metric instead of transforming again.
    final lod = item.lod;
    final worldBounds = item.worldBounds;

    // Queue the level(s) of detail to draw (or cull). A cross-fading node
    // returns its two adjacent levels with complementary dither coverage.
    if (lod != null) {
      final selections = _resolveLod(lod, worldBounds);
      if (selections.isEmpty) {
        activeDrawRecorder?.onSkip(item, DrawSkipReason.lodCulled);
      }
      for (final selection in selections) {
        final level = lod.levels[selection.level];
        _record(item, level.geometry, level.material, selection.fade);
      }
      return;
    }
    _record(item, item.geometry, item.material, 1.0);
  }

  // Queues a single draw for [item] using the already-LOD-resolved [geometry]
  // and [material] at cross-fade coverage [fade].
  void _record(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
  ) {
    // A material with a `vertex { }` block supplies its own vertex shader for
    // this geometry's mesh type; otherwise the engine's standard one is used.
    // A material that cannot show the active debug view draws through the
    // engine's fallback debug fragment shader instead of its own.
    final fallback = _usesDebugFallback(item, material, geometry);
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    final pipeline = tryResolvePipeline(
      materialVertex ?? geometry.vertexShader,
      fallback
          ? _debugFallbackShader
          : material.fragmentShaderForLighting(_lighting),
      // A material declaring `instance_attributes` widens the instance-rate
      // slot, and its custom vertex `attributes` pick the geometry streams, so
      // the pipeline depends on the material as well as the geometry.
      vertexLayout: geometry.instancedVertexLayoutFor(
        material.instanceAttributes,
        material.vertexAttributesFor(materialVertex),
      ),
      debugContext: () =>
          '${fmatSourcePathOf(material) ?? material.runtimeType} on '
          '${geometry.runtimeType}'
          '${geometry.hasCustomAttributes ? ' with custom vertex attributes' : ''}',
    );
    if (pipeline == null) {
      activeRenderCounters.pipelineRejected++;
      activeDrawRecorder?.onSkip(item, DrawSkipReason.pipelineRejected);
      return;
    }

    // Display-referred surfaces draw past the tone curve into their own
    // layer, so they leave both scene buckets. They are depth-sorted like
    // translucency and share its record shape.
    if (material.displayReferred) {
      _addDepthSortedRecord(
        item,
        geometry,
        material,
        fade,
        pipeline,
        _displayReferredRecords,
      );
      return;
    }

    if (material.isOpaque()) {
      _opaqueRecords.add(
        _obtainOpaqueRecord(
          item,
          geometry,
          material,
          fade,
          pipeline,
          identityHashCode(pipeline),
          item.windingFor(geometry),
        ),
      );
      return;
    }

    _addDepthSortedRecord(
      item,
      geometry,
      material,
      fade,
      pipeline,
      _translucentRecords,
    );
  }

  // Appends one back-to-front record to [target]. Keeps instanced draws in a
  // single record; their instances are sorted while the transform buffer is
  // packed at draw time.
  void _addDepthSortedRecord(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    List<_TranslucentRecord> target,
  ) {
    final instances = item.instanceTransforms;
    if (instances != null) {
      final bounds = item.worldBounds;
      target.add(
        _obtainTranslucentRecord(
          item,
          item.worldTransform,
          geometry,
          material,
          fade,
          pipeline,
          bounds == null
              ? _depthOf(item.worldTransform)
              : _depthOfPoint(
                  (bounds.min.x + bounds.max.x) * 0.5,
                  (bounds.min.y + bounds.max.y) * 0.5,
                  (bounds.min.z + bounds.max.z) * 0.5,
                ),
          item.windingFor(geometry),
          item.lightListOffset,
          item.lightListCount,
          item.jointsTexture,
          item.jointsTextureWidth,
        ),
      );
    } else {
      target.add(
        _obtainTranslucentRecord(
          item,
          item.worldTransform,
          geometry,
          material,
          fade,
          pipeline,
          _depthOf(item.worldTransform, geometry),
          item.windingFor(geometry),
          item.lightListOffset,
          item.lightListCount,
          item.jointsTexture,
          item.jointsTextureWidth,
        ),
      );
    }
  }

  _OpaqueRecord _obtainOpaqueRecord(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    int pipelineKey,
    bool windingFlipped,
  ) {
    if (_opaqueRecordPool.isEmpty) {
      return _OpaqueRecord(
        item,
        geometry,
        material,
        fade,
        pipeline,
        pipelineKey,
        windingFlipped,
      );
    }
    return _opaqueRecordPool.removeLast()..reset(
      item,
      geometry,
      material,
      fade,
      pipeline,
      pipelineKey,
      windingFlipped,
    );
  }

  _TranslucentRecord _obtainTranslucentRecord(
    RenderItem item,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    double depth,
    bool windingFlipped,
    int lightListOffset,
    int lightListCount,
    gpu.Texture? jointsTexture,
    int jointsTextureWidth,
  ) {
    if (_translucentRecordPool.isEmpty) {
      return _TranslucentRecord(
        item,
        worldTransform,
        geometry,
        material,
        fade,
        pipeline,
        depth,
        windingFlipped,
        lightListOffset,
        lightListCount,
        jointsTexture,
        jointsTextureWidth,
      );
    }
    return _translucentRecordPool.removeLast()..reset(
      item,
      worldTransform,
      geometry,
      material,
      fade,
      pipeline,
      depth,
      windingFlipped,
      lightListOffset,
      lightListCount,
      jointsTexture,
      jointsTextureWidth,
    );
  }

  // The level(s) of detail to draw for [lod] from the item's [worldBounds],
  // each with a fade coverage; empty to cull. Falls back to the highest detail
  // when no screen-size metric is available (no bounds, or a degenerate
  // projection).
  List<({int level, double fade})> _resolveLod(
    LodSelection lod,
    Aabb3? worldBounds,
  ) {
    final projection = _lodProjection;
    if (worldBounds == null || projection == null) {
      return const [(level: 0, fade: 1.0)];
    }
    // The circumscribed sphere of the world AABB (conservative, so detail is
    // kept slightly longer than a tight sphere would).
    final radius = worldBounds.max.distanceTo(worldBounds.min) * 0.5;
    final size = projection.orthographic
        ? lodScreenSizeOrthographic(
            radius: radius,
            halfHeight: projection.scaleY,
          )
        : lodScreenSize(
            center: worldBounds.center,
            radius: radius,
            cameraPosition: _cameraPosition,
            fovRadiansY: 2.0 * math.atan(projection.scaleY),
          );
    return lod.resolve(size);
  }

  double _depthOf(Matrix4 worldTransform, [Geometry? geometry]) {
    return sceneSortDepth(
      worldTransform,
      geometry?.localBounds,
      _cameraPosition,
      _cameraForward,
    );
  }

  double _opaqueDepth(_OpaqueRecord record) {
    final cached = record.depth;
    if (!cached.isNaN) return cached;
    return record.depth = _depthOf(
      record.item.worldTransform,
      record.geometry,
    );
  }

  double _depthOfPoint(double x, double y, double z) {
    final position = _cameraPosition;
    final forward = _cameraForward;
    return (x - position.x) * forward.x +
        (y - position.y) * forward.y +
        (z - position.z) * forward.z;
  }

  // Binds [pipeline] unless it is already the bound one. `clearBindings`
  // leaves the pipeline in place, so consecutive draws that share a
  // pipeline only need to bind it once.
  void _bindPipeline(gpu.RenderPipeline pipeline) {
    if (identical(_boundPipeline, pipeline)) return;
    activeRenderCounters.pipelineBinds++;
    _renderPass.bindPipeline(pipeline);
    _boundPipeline = pipeline;
  }

  // Drops the pass's bindings. The engine-lighting memo tracks what is
  // already bound on the pass, so it has to be forgotten here or the next
  // draw skips rebinding slots that were just wiped; never call
  // `clearBindings` directly.
  void _clearBindings() {
    _renderPass.clearBindings();
    EngineLightingUniforms.invalidateBindMemo();
    _boundMaterial = null;
    _debugViewBoundMaterial = null;
    _boundMaterialVertex = null;
    _boundFrameInfoShader = null;
    _boundFrameInfoDepthBias = double.nan;
    _boundFrameInfoDepthKey = -1;
    _boundMaterialFade = double.nan;
    _boundMaterialLightOffset = -1;
    _boundMaterialLightCount = -1;
    _boundMaterialLightChannelMask = -1;
    _boundWindingOrder = null;
    _boundPrimitiveType = null;
  }

  // The debug view [item] shows this frame: its node override when one is
  // set, else the scene view, else none.
  DebugView _effectiveDebugView(RenderItem? item) {
    final frame = _debugView;
    if (frame == null) return DebugView.none;
    return frame.effectiveView(item?.debugView);
  }

  // Whether [material] draws through the engine's fallback debug shader for
  // [item]: a view is active for it, the material cannot show views itself,
  // and the geometry writes the standard varyings the fallback reads.
  bool _usesDebugFallback(
    RenderItem? item,
    Material material,
    Geometry geometry,
  ) {
    if (_debugView == null) return false;
    return _effectiveDebugView(item).isActive &&
        !material.participatesInDebugViews &&
        geometry.emitsStandardVaryings;
  }

  // Binds the DebugViewInfo block for the draw about to be recorded. Every
  // participating shader declares it, so it is bound even when no view is
  // active (once per material run, the shared off block); an active view
  // binds per draw, since the identity seeds are per item.
  void _bindDebugView(Material material, RenderItem? item, bool fallback) {
    if (!fallback && !material.participatesInDebugViews) return;
    final shader = fallback
        ? _debugFallbackShader
        : material.fragmentShaderForLighting(_lighting);
    if (fallback) {
      // The fallback replaces the material's own shader, so its bind never
      // supplied the view block the debug hook reads.
      EngineLightingUniforms.bindViewInfo(
        _renderPass,
        shader,
        _transientsBuffer,
        _lighting,
      );
    }
    final slot = shader.getUniformSlot('DebugViewInfo');
    final view = _effectiveDebugView(item);
    if (!view.isActive) {
      if (identical(_debugViewBoundMaterial, material) &&
          _debugViewBoundFallback == fallback) {
        return;
      }
      _renderPass.bindUniform(
        slot,
        _debugViewInactive ??= _transientsBuffer.emplace(
          ByteData.sublistView(DebugViewFrame.inactive),
        ),
      );
      _debugViewBoundMaterial = material;
      _debugViewBoundFallback = fallback;
      return;
    }
    _debugView!.pack(
      _debugViewScratch,
      view,
      objectSeed: item == null ? 0 : identityHashCode(item.sourceNode ?? item),
      materialSeed: identityHashCode(material),
      raster: _raster,
      pixelScale: _pixelScale,
    );
    _renderPass.bindUniform(
      slot,
      _transientsBuffer.emplace(ByteData.sublistView(_debugViewScratch)),
    );
    // A per-draw block; the next draw with this material must rebind.
    _debugViewBoundMaterial = null;
  }

  void _bindMaterial(
    Material material,
    gpu.Shader? materialVertex,
    double fade, {
    bool fallback = false,
  }) {
    final lightOffset = material.lightListOffset;
    final lightCount = material.lightListCount;
    final lightChannelMask = material.lightChannelMask;
    if (identical(_boundMaterial, material) &&
        identical(_boundMaterialVertex, materialVertex) &&
        _boundMaterialFallback == fallback &&
        _boundMaterialFade == fade &&
        _boundMaterialLightOffset == lightOffset &&
        _boundMaterialLightCount == lightCount &&
        _boundMaterialLightChannelMask == lightChannelMask) {
      return;
    }
    material.lodFade = fade;
    if (fallback) {
      // The fallback debug shader has none of the material's fragment slots;
      // only the pass state and the vertex stage bind.
      _renderPass.setCullMode(material.renderCullMode);
      _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
    } else {
      material.bind(_renderPass, _transientsBuffer, _lighting);
    }
    _boundWindingOrder = null;
    if (materialVertex != null) {
      material.bindVertexStage(_renderPass, materialVertex, _transientsBuffer);
    }
    _boundMaterialFallback = fallback;
    _boundMaterial = material;
    _boundMaterialVertex = materialVertex;
    _boundMaterialFade = fade;
    _boundMaterialLightOffset = lightOffset;
    _boundMaterialLightCount = lightCount;
    _boundMaterialLightChannelMask = lightChannelMask;
  }

  void _setWindingOrder(gpu.WindingOrder windingOrder) {
    if (_boundWindingOrder == windingOrder) return;
    _renderPass.setWindingOrder(windingOrder);
    _boundWindingOrder = windingOrder;
  }

  void _setPrimitiveType(gpu.PrimitiveType primitiveType) {
    if (_boundPrimitiveType == primitiveType) return;
    _renderPass.setPrimitiveType(primitiveType);
    _boundPrimitiveType = primitiveType;
  }

  void _bindGeometry(
    Geometry geometry,
    Matrix4 worldTransform,
    Material material,
    gpu.Shader? materialVertex,
  ) {
    final depthBias = material.depthBias;
    final depthKey = _depthOffsetKey(material);
    setCurrentDrawDepthOffset(
      _raster,
      material.depthLayer,
      material.tieBreakRank,
      pixelSlope: _pixelSlope,
    );
    geometry.useVertexAttributes(material.vertexAttributesFor(materialVertex));
    // Morphed geometry takes the full bind, which also binds its morph stage.
    if (geometry is UnskinnedGeometry && geometry.morphTargets == null) {
      geometry.bindGeometryBuffers(_renderPass);
      final shader = materialVertex ?? geometry.vertexShader;
      if (!identical(_boundFrameInfoShader, shader) ||
          _boundFrameInfoDepthBias != depthBias ||
          _boundFrameInfoDepthKey != depthKey) {
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          shader,
          _drawCameraTransform,
          _cameraPosition,
          depthBias: depthBias,
        );
        _boundFrameInfoShader = shader;
        _boundFrameInfoDepthBias = depthBias;
        _boundFrameInfoDepthKey = depthKey;
      }
    } else {
      geometry.bind(
        _renderPass,
        _transientsBuffer,
        worldTransform,
        _drawCameraTransform,
        _cameraPosition,
        shaderOverride: materialVertex,
        depthBias: depthBias,
      );
      // The full bind rebinds FrameInfo, possibly on the cached shader.
      _boundFrameInfoShader = null;
      _boundFrameInfoDepthBias = double.nan;
      _boundFrameInfoDepthKey = -1;
    }
  }

  // Identifies the depth offset [material] draws with under [_raster]: its
  // layer, plus its tie-break rank when the tie-break applies to it.
  int _depthOffsetKey(Material material) {
    final layer = material.depthLayer;
    final rank = _raster.tieBreak && layer == 0 ? material.tieBreakRank : 0;
    return (layer + kMaxDepthLayer) * 4 + rank;
  }

  void _bindPackedInstances(Float32List packed, int slot) {
    final watch = profileRendering ? (Stopwatch()..start()) : null;
    bindInstanceData(_renderPass, packed, slot: slot);
    if (profileRendering) {
      watch!.stop();
      _instanceBindMicros += watch.elapsedMicroseconds;
      _instanceBytes += packed.lengthInBytes;
    }
  }

  void _drawGeometry(
    Geometry geometry,
    Material material, {
    int instanceCount = 1,
  }) {
    if (profileRendering) {
      _encodedDraws++;
      _encodedInstances += instanceCount;
    }
    drawOrRejectPipeline(
      _renderPass,
      geometry,
      _boundPipeline,
      instanceCount: instanceCount,
      material: material,
    );
  }

  // Tells the capture recorder what the next draws are, at the cost of one
  // null check per encode in steady state.
  void _describeDraw(
    RenderItem item,
    Geometry geometry,
    Material material,
    gpu.Shader? materialVertex,
    gpu.RenderPipeline pipeline, {
    int batchedItems = 1,
    BatchBreakReason batchBreak = BatchBreakReason.none,
  }) {
    final recorder = activeDrawRecorder;
    if (recorder == null) return;
    recorder.setContext(
      DrawContext(
        phase: _phase,
        item: item,
        geometry: geometry,
        material: material,
        vertexShader: materialVertex ?? geometry.vertexShader,
        fragmentShader: material.fragmentShaderForLighting(_lighting),
        pipeline: pipeline,
        batchedItems: batchedItems,
        batchBreak: batchBreak,
      ),
    );
  }

  void _encode(
    gpu.RenderPipeline pipeline,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    bool windingFlipped,
    double fade, {
    RenderItem? item,
    BatchBreakReason batchBreak = BatchBreakReason.none,
  }) {
    if (item == null) {
      _encodeSingle(
        pipeline,
        worldTransform,
        geometry,
        material,
        windingFlipped,
        fade,
        batchBreak: batchBreak,
      );
      return;
    }
    final selection = beginMeshDraw(
      item,
      geometry,
      MeshDrawPass.color,
      _cameraPosition,
      _primaryView,
    );
    try {
      if (selection.instanceCount == 0) return;
      _encodeSingle(
        pipeline,
        worldTransform,
        geometry,
        material,
        windingFlipped,
        fade,
        item: item,
        batchBreak: batchBreak,
      );
    } finally {
      endMeshDraw(geometry);
    }
  }

  void _encodeSingle(
    gpu.RenderPipeline pipeline,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    bool windingFlipped,
    double fade, {
    RenderItem? item,
    BatchBreakReason batchBreak = BatchBreakReason.none,
  }) {
    final fallback = _usesDebugFallback(item, material, geometry);
    // Bindings persist across draws within a pass, and every draw binds its
    // full slot set, so clearing is only needed when the pipeline (and with
    // it the shaders' slot layouts) changes; a stale entry from a different
    // layout could otherwise leak into the next command. Opaque draws are
    // pipeline-sorted, so same-pipeline runs skip the clear, which lets the
    // per-draw engine-lighting rebind be skipped too (see
    // EngineLightingUniforms); each bind marshals its slot name across the
    // FFI, and re-issuing the full set per item dominated main-thread frame
    // time in draw-heavy scenes.
    if (!identical(_boundPipeline, pipeline)) {
      _clearBindings();
    }
    _bindPipeline(pipeline);
    // A `vertex { }` material supplies its own vertex shader for this mesh
    // type; the geometry must bind FrameInfo (and skinned's joints texture)
    // against it, since its uniform slots can differ from the engine default.
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    if (item != null) {
      _describeDraw(
        item,
        geometry,
        material,
        materialVertex,
        pipeline,
        batchBreak: batchBreak,
      );
    }
    _bindGeometry(geometry, worldTransform, material, materialVertex);
    if (geometry.bindsModelTransformInstance) {
      // The model matrix arrives through the instance-rate vertex buffer,
      // bound to the slot after the geometry's vertex streams.
      bindSingleInstanceData(
        _renderPass,
        worldTransform,
        slot: geometry.vertexStreamCount,
        // A single draw has no per-instance source, so declared attributes
        // read zero.
        attributeFloats: material.instanceAttributes?.floatCount ?? 0,
      );
    }
    _bindMaterial(material, materialVertex, fade, fallback: fallback);
    _bindDebugView(material, item, fallback);
    // A mirrored transform reverses triangle winding. Set both cases because
    // a cached material bind no longer resets it between compatible draws.
    _setWindingOrder(
      windingFlipped
          ? gpu.WindingOrder.counterClockwise
          : gpu.WindingOrder.clockwise,
    );
    _setPrimitiveType(geometry.primitiveType);
    _drawGeometry(geometry, material);
  }

  /// Draws an opaque instanced item with hardware instancing: the instance
  /// world transforms are packed into an instance-rate vertex buffer and the
  /// whole set draws with one call per winding-parity group (mirrored
  /// instances reverse triangle winding, so they draw as a second group
  /// under the flipped winding order).
  ///
  /// Geometry without an instanced vertex layout (skinned) falls back to a
  /// per-instance loop through the per-draw uniform path.
  void _encodeInstanced(
    gpu.RenderPipeline pipeline,
    Matrix4 nodeTransform,
    Geometry geometry,
    Material material,
    List<Matrix4> instances,
    List<Vector4> colors,
    bool windingFlipped,
    double fade, {
    List<bool>? instanceWindingFlipped,
    List<int>? instanceIndices,
    Vector3? sortBackToFrontFrom,
    Float32List? packedWorldData,
    Uint8List? packedWorldWindingFlipped,
    Float32List? attributeData,
    int attributeFloats = 0,
    RenderItem? item,
    BatchBreakReason batchBreak = BatchBreakReason.none,
  }) {
    final selection = item == null
        ? MeshDrawSelection.all
        : beginMeshDraw(
            item,
            geometry,
            MeshDrawPass.color,
            _cameraPosition,
            _primaryView,
          );
    try {
      if (selection.instanceCount == 0) return;
      _encodeInstancedBody(
        pipeline,
        nodeTransform,
        geometry,
        material,
        instances,
        colors,
        windingFlipped,
        fade,
        instanceWindingFlipped: instanceWindingFlipped,
        instanceIndices: instanceIndices,
        sortBackToFrontFrom: sortBackToFrontFrom,
        packedWorldData: packedWorldData,
        packedWorldWindingFlipped: packedWorldWindingFlipped,
        attributeData: attributeData,
        attributeFloats: attributeFloats,
        item: item,
        batchBreak: batchBreak,
        instanceLimit: selection.instanceCount,
      );
    } finally {
      endMeshDraw(geometry);
    }
  }

  void _encodeInstancedBody(
    gpu.RenderPipeline pipeline,
    Matrix4 nodeTransform,
    Geometry geometry,
    Material material,
    List<Matrix4> instances,
    List<Vector4> colors,
    bool windingFlipped,
    double fade, {
    List<bool>? instanceWindingFlipped,
    List<int>? instanceIndices,
    Vector3? sortBackToFrontFrom,
    Float32List? packedWorldData,
    Uint8List? packedWorldWindingFlipped,
    Float32List? attributeData,
    int attributeFloats = 0,
    RenderItem? item,
    BatchBreakReason batchBreak = BatchBreakReason.none,
    int? instanceLimit,
  }) {
    checkInstanceRecordWidth(material.instanceAttributes, attributeFloats);
    if (!identical(_boundPipeline, pipeline)) {
      _clearBindings();
    }
    _bindPipeline(pipeline);
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    if (item != null) {
      _describeDraw(
        item,
        geometry,
        material,
        materialVertex,
        pipeline,
        batchBreak: batchBreak,
      );
    }
    final fallback = _usesDebugFallback(item, material, geometry);
    _bindMaterial(material, materialVertex, fade, fallback: fallback);
    _bindDebugView(material, item, fallback);
    _setPrimitiveType(geometry.primitiveType);

    final allInstances = instanceIndices == null;
    instanceIndices = limitInstanceIndices(
      instanceIndices,
      instances.length,
      instanceLimit,
    );
    if (geometry.instancedVertexLayout == null) {
      final count = instanceIndices?.length ?? instances.length;
      for (var slot = 0; slot < count; slot++) {
        final instanceIndex = instanceIndices?[slot] ?? slot;
        final instanceTransform = instances[instanceIndex];
        _bindGeometry(
          geometry,
          nodeTransform * instanceTransform,
          material,
          materialVertex,
        );
        // Each instance can itself mirror; combine with the node's parity.
        final flip = windingFlipped != (instanceTransform.determinant() < 0);
        _setWindingOrder(
          flip ? gpu.WindingOrder.counterClockwise : gpu.WindingOrder.clockwise,
        );
        _drawGeometry(geometry, material);
      }
      return;
    }

    _bindGeometry(geometry, nodeTransform, material, materialVertex);
    if (sortBackToFrontFrom == null &&
        allInstances &&
        packedWorldData != null &&
        packedWorldWindingFlipped != null) {
      final flipped = bindRetainedInstanceData(
        _renderPass,
        packedWorldData,
        packedWorldWindingFlipped,
        slot: geometry.vertexStreamCount,
      );
      if (flipped != null) {
        _setWindingOrder(
          flipped
              ? gpu.WindingOrder.counterClockwise
              : gpu.WindingOrder.clockwise,
        );
        _drawGeometry(
          geometry,
          material,
          instanceCount: instanceIndices?.length ?? instances.length,
        );
        return;
      }
    }
    final packWatch = profileRendering ? (Stopwatch()..start()) : null;
    final packed =
        sortBackToFrontFrom == null &&
            packedWorldData != null &&
            packedWorldWindingFlipped != null
        ? packInstanceDataBatches(
            transientInstancePackingScratch.singleCachedBatch(
              packedWorldData: packedWorldData,
              packedWindingFlipped: packedWorldWindingFlipped,
              indices: instanceIndices,
              attributeFloats: attributeFloats,
            ),
            attributeFloats: attributeFloats,
            scratch: transientInstancePackingScratch,
          )
        : packInstanceData(
            nodeTransform,
            instances,
            colors,
            nodeWindingFlipped: windingFlipped,
            instanceWindingFlipped: instanceWindingFlipped,
            indices: instanceIndices,
            sortBackToFrontFrom: sortBackToFrontFrom,
            attributeData: attributeData,
            attributeFloats: attributeFloats,
            scratch: transientInstancePackingScratch,
          );
    if (profileRendering) {
      packWatch!.stop();
      _instancePackMicros += packWatch.elapsedMicroseconds;
    }
    transientInstancePackingScratch.releaseSingleBatch();
    final instanceSlot = geometry.vertexStreamCount;
    if (packed.ccwCount > 0) {
      _bindPackedInstances(packed.ccw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.clockwise);
      _drawGeometry(geometry, material, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, material, instanceCount: packed.cwCount);
    }
  }

  void _encodeInstancedBatches(
    gpu.RenderPipeline pipeline,
    Geometry geometry,
    Material material,
    List<InstanceDataBatch> batches,
    double fade, {
    RenderItem? item,
    int batchedItems = 1,
    BatchBreakReason batchBreak = BatchBreakReason.none,
  }) {
    // Cross-node batching synthesizes instances, so a material declaring
    // per-instance attributes is kept out of it (see opaqueBatchEnd).
    assert(material.instanceAttributes == null);
    if (!identical(_boundPipeline, pipeline)) {
      _clearBindings();
    }
    _bindPipeline(pipeline);
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    if (item != null) {
      _describeDraw(
        item,
        geometry,
        material,
        materialVertex,
        pipeline,
        batchedItems: batchedItems,
        batchBreak: batchBreak,
      );
    }
    final fallback = _usesDebugFallback(item, material, geometry);
    _bindMaterial(material, materialVertex, fade, fallback: fallback);
    // TODO(debug-views): a cross-node batch carries the first item's object
    // seed, so its members share one object color.
    _bindDebugView(material, item, fallback);
    _setPrimitiveType(geometry.primitiveType);
    _bindGeometry(geometry, _identityTransform, material, materialVertex);
    final packWatch = profileRendering ? (Stopwatch()..start()) : null;
    final packed = packInstanceDataBatches(
      batches,
      scratch: transientInstancePackingScratch,
    );
    if (profileRendering) {
      packWatch!.stop();
      _instancePackMicros += packWatch.elapsedMicroseconds;
    }
    final instanceSlot = geometry.vertexStreamCount;
    if (packed.ccwCount > 0) {
      _bindPackedInstances(packed.ccw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.clockwise);
      _drawGeometry(geometry, material, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, material, instanceCount: packed.cwCount);
    }
  }

  static final Matrix4 _identityTransform = Matrix4.identity();

  /// Sorts and emits every deferred draw, then finishes recording.
  ///
  /// Opaque draws are sorted by pipeline, material, and geometry, with
  /// front-to-back depth only as the last tie-breaker, and drawn first.
  /// Translucent draws are then sorted back-to-front and drawn with
  /// premultiplied source-over blending and depth writes disabled. After this
  /// returns the encoder has finished recording into its render pass; the
  /// caller submits the owning command buffer.
  void flush() {
    flushOpaque();
    flushTranslucent();
  }

  /// Emits only the opaque phase (see [flush]). Used with [flushTranslucent]
  /// when the scene pass snapshots the opaque color between them.
  void flushOpaque() {
    _phase = DrawPhase.opaque;
    final sortWatch = profileRendering ? (Stopwatch()..start()) : null;
    _opaqueRecords.sort((a, b) {
      final byOrder = a.item.renderOrder.compareTo(b.item.renderOrder);
      if (byOrder != 0) return byOrder;
      final byPipeline = a.pipelineKey.compareTo(b.pipelineKey);
      if (byPipeline != 0) return byPipeline;
      final byMaterial = a.materialKey.compareTo(b.materialKey);
      if (byMaterial != 0) return byMaterial;
      final byGeometry = a.geometryKey.compareTo(b.geometryKey);
      if (byGeometry != 0) return byGeometry;
      final byLightOffset = a.item.lightListOffset.compareTo(
        b.item.lightListOffset,
      );
      if (byLightOffset != 0) return byLightOffset;
      final byLightCount = a.item.lightListCount.compareTo(
        b.item.lightListCount,
      );
      if (byLightCount != 0) return byLightCount;
      final byChannels = a.item.lightChannelMask.compareTo(
        b.item.lightChannelMask,
      );
      if (byChannels != 0) return byChannels;
      final byFade = a.fade.compareTo(b.fade);
      if (byFade != 0) return byFade;
      return _opaqueDepth(a).compareTo(_opaqueDepth(b));
    });
    sortWatch?.stop();
    final encodeWatch = profileRendering ? (Stopwatch()..start()) : null;
    var index = 0;
    while (index < _opaqueRecords.length) {
      final record = _opaqueRecords[index];
      final item = record.item;
      record.material.lightListOffset = item.lightListOffset;
      record.material.lightListCount = item.lightListCount;
      record.material.lightChannelMask = item.lightChannelMask;
      record.material.setModelScaleFromTransform(item.worldTransform);
      item.applyJointsTexture(record.geometry);
      item.applyMorphWeights(record.geometry);

      final end = opaqueBatchEnd(_opaqueRecords, index);
      // Only a capture asks why a run ended; steady state skips the walk.
      final batchBreak = activeDrawRecorder == null
          ? BatchBreakReason.none
          : opaqueBatchBreakReason(
              _opaqueRecords[end - 1],
              end < _opaqueRecords.length ? _opaqueRecords[end] : null,
            );
      if (end > index + 1) {
        activeRenderCounters.batches++;
        activeRenderCounters.batchedItems += end - index;
        _batchPool.reset();
        for (var batchIndex = index; batchIndex < end; batchIndex++) {
          final item = _opaqueRecords[batchIndex].item;
          _batchPool.addFor(
            item,
            indices: item.visibleInstanceIndices,
            windingFlipped: _opaqueRecords[batchIndex].windingFlipped,
          );
        }
        _encodeInstancedBatches(
          record.pipeline,
          record.geometry,
          record.material,
          _batchPool.batches,
          record.fade,
          item: item,
          batchedItems: end - index,
          batchBreak: batchBreak,
        );
        index = end;
        continue;
      }

      final instances = item.instanceTransforms;
      if (instances != null) {
        _encodeInstanced(
          record.pipeline,
          item.worldTransform,
          record.geometry,
          record.material,
          instances,
          item.instanceColors!,
          record.windingFlipped,
          record.fade,
          instanceWindingFlipped: item.instanceWindingFlipped,
          instanceIndices: item.visibleInstanceIndices,
          packedWorldData: record.windingFlipped == item.windingFlipped
              ? item.instanceWorldData
              : null,
          packedWorldWindingFlipped:
              record.windingFlipped == item.windingFlipped
              ? item.instanceWorldWindingFlipped
              : null,
          attributeData: item.instanceAttributeData,
          attributeFloats: item.instanceAttributeFloats,
          item: item,
          batchBreak: batchBreak,
        );
      } else {
        _encode(
          record.pipeline,
          item.worldTransform,
          record.geometry,
          record.material,
          record.windingFlipped,
          record.fade,
          item: item,
          batchBreak: batchBreak,
        );
      }
      index++;
    }
    encodeWatch?.stop();
    if (profileRendering) {
      _opaqueSortMicros = sortWatch!.elapsedMicroseconds;
      _opaqueEncodeMicros = encodeWatch!.elapsedMicroseconds;
    }
    for (final record in _opaqueRecords) {
      if (_opaqueRecordPool.length == _recordPoolLimit) break;
      record.release();
      _opaqueRecordPool.add(record);
    }
    _opaqueRecords.clear();
  }

  void _recordProfile(
    int sortMicros,
    int encodeMicros,
    int draws,
    int instances,
  ) {
    _profile.add('sort', sortMicros);
    _profile.add('encode', encodeMicros);
    _profile.add('instance_pack', _instancePackMicros, trackMax: true);
    _profile.add('instance_bind', _instanceBindMicros);
    _profile.add('instance_bytes', _instanceBytes);
    _profile.add('draws', draws);
    _profile.add('instances', instances);
    final snapshot = _profile.endSample();
    _instancePackMicros = 0;
    _instanceBindMicros = 0;
    _instanceBytes = 0;
    _opaqueSortMicros = 0;
    _opaqueEncodeMicros = 0;
    if (snapshot == null) return;
    // ignore: avoid_print
    print(
      'FLUTTER_SCENE_PROFILE_ENCODER '
      'sort_mean_us=${snapshot.mean('sort')} '
      'encode_mean_us=${snapshot.mean('encode')} '
      'instance_pack_mean_us=${snapshot.mean('instance_pack')} '
      'instance_pack_max_us=${snapshot.max('instance_pack')} '
      'instance_bind_mean_us=${snapshot.mean('instance_bind')} '
      'instance_kib_mean=${snapshot.mean('instance_bytes') ~/ 1024} '
      'draws_mean=${snapshot.mean('draws')} '
      'instances_mean=${snapshot.mean('instances')}',
    );
  }

  bool _translucentPrepared = false;
  int _translucentCursor = 0;
  int _translucentSortMicros = 0;
  int _translucentEncodeMicros = 0;

  ui.Rect _screenBoundsOf(_TranslucentRecord record) {
    final cached = record.screenBounds;
    if (cached != null) return cached;
    final bounds = record.item.worldBounds;
    if (bounds == null || _dimensions.isEmpty || record.item.lod != null) {
      return record.screenBounds = ui.Offset.zero & _dimensions;
    }
    return record.screenBounds = _projectBounds(bounds);
  }

  ui.Rect _sceneColorSampleBoundsOf(_TranslucentRecord record) {
    final cached = record.sceneColorSampleBounds;
    if (cached != null) return cached;
    final expansion = record.material.sceneColorSampleBoundsExpansion;
    final bounds = record.item.worldBounds;
    if (expansion == null || bounds == null || record.item.lod != null) {
      return record.sceneColorSampleBounds = ui.Offset.zero & _dimensions;
    }
    var projected = _screenBoundsOf(record);
    if (expansion > 0) {
      final transform = record.worldTransform.storage;
      final scaleX = math.sqrt(
        transform[0] * transform[0] +
            transform[1] * transform[1] +
            transform[2] * transform[2],
      );
      final scaleY = math.sqrt(
        transform[4] * transform[4] +
            transform[5] * transform[5] +
            transform[6] * transform[6],
      );
      final scaleZ = math.sqrt(
        transform[8] * transform[8] +
            transform[9] * transform[9] +
            transform[10] * transform[10],
      );
      final worldExpansion =
          expansion * math.max(scaleX, math.max(scaleY, scaleZ));
      final expanded = Aabb3.copy(bounds)
        ..min.sub(Vector3.all(worldExpansion))
        ..max.add(Vector3.all(worldExpansion));
      projected = _projectBounds(expanded);
    }
    final filterFraction = record.material.sceneColorSampleFilterLodFraction;
    if (filterFraction > 0 && !projected.isEmpty) {
      final maxDimension = math.max(_dimensions.width, _dimensions.height);
      final lod = math.log(maxDimension) / math.ln2 * filterFraction;
      final filterRadius = 4.0 * math.pow(2.0, lod.ceil()).toDouble();
      projected = projected.inflate(filterRadius);
    }
    final viewport = ui.Offset.zero & _dimensions;
    return record.sceneColorSampleBounds = projected.intersect(viewport);
  }

  ui.Rect _projectBounds(Aabb3 bounds) {
    if (_dimensions.isEmpty) return ui.Offset.zero & _dimensions;

    final min = bounds.min;
    final max = bounds.max;
    var anyBehind = false;
    var anyInFront = false;
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (var i = 0; i < 8; i++) {
      final corner = Vector4(
        (i & 1) == 0 ? min.x : max.x,
        (i & 2) == 0 ? min.y : max.y,
        (i & 4) == 0 ? min.z : max.z,
        1,
      );
      final clip = _cameraTransform.transform(corner);
      if (clip.w <= 0) {
        anyBehind = true;
        continue;
      }
      anyInFront = true;
      final x = (clip.x / clip.w + 1) * 0.5 * _dimensions.width;
      final y = (1 - clip.y / clip.w) * 0.5 * _dimensions.height;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
    final viewport = ui.Offset.zero & _dimensions;
    if (!anyInFront || anyBehind) return viewport;
    return ui.Rect.fromLTRB(
      left.clamp(0.0, _dimensions.width),
      top.clamp(0.0, _dimensions.height),
      right.clamp(0.0, _dimensions.width),
      bottom.clamp(0.0, _dimensions.height),
    );
  }

  int _nextSceneColorBatchEnd() {
    _prepareTranslucent();
    assert(_translucentCursor < _translucentRecords.length);
    assert(_readsSceneColor(_translucentRecords[_translucentCursor].material));
    return _sceneColorBatchEnd(
      _translucentRecords,
      _translucentCursor,
      _dimensions,
      readsSceneColor: (record) => _readsSceneColor(record.material),
      outputBounds: _screenBoundsOf,
      sampleBounds: _sceneColorSampleBoundsOf,
    );
  }

  // Render order first, then farthest first.
  static int _backToFront(_TranslucentRecord a, _TranslucentRecord b) {
    final byOrder = a.item.renderOrder.compareTo(b.item.renderOrder);
    return byOrder != 0 ? byOrder : b.depth.compareTo(a.depth);
  }

  void _prepareTranslucent() {
    if (_translucentPrepared) return;
    final sortWatch = profileRendering ? (Stopwatch()..start()) : null;
    _translucentRecords.sort(_backToFront);
    sortWatch?.stop();
    _translucentSortMicros = sortWatch?.elapsedMicroseconds ?? 0;
    _translucentPrepared = true;
  }

  /// Whether a deferred translucent draw remains.
  bool get hasPendingTranslucent {
    _prepareTranslucent();
    return _translucentCursor < _translucentRecords.length;
  }

  /// Whether a pending translucent draw samples scene color.
  bool get hasPendingSceneColorReaders {
    _prepareTranslucent();
    for (var i = _translucentCursor; i < _translucentRecords.length; i++) {
      if (_readsSceneColor(_translucentRecords[i].material)) return true;
    }
    return false;
  }

  /// Whether the next translucent batch needs opaque scene color.
  bool get nextTranslucentBatchReadsSceneColor {
    _prepareTranslucent();
    if (_translucentCursor >= _translucentRecords.length) return false;
    return _readsSceneColor(_translucentRecords[_translucentCursor].material);
  }

  /// Whether the next translucent batch needs roughness-filtered scene color.
  bool get nextTranslucentBatchReadsFilteredSceneColor {
    _prepareTranslucent();
    if (_translucentCursor >= _translucentRecords.length) return false;
    return _translucentRecords[_translucentCursor].material.sceneInputs
        .contains(RenderInput.filteredSceneColor);
  }

  /// Number of pending translucent draws that read opaque scene color.
  int get pendingSceneColorReaderCount {
    _prepareTranslucent();
    var count = 0;
    for (var i = _translucentCursor; i < _translucentRecords.length; i++) {
      if (_readsSceneColor(_translucentRecords[i].material)) count++;
    }
    return count;
  }

  /// Whether the next overlap-safe scene-color batch needs filtered color.
  bool get nextSceneColorBatchReadsFilteredSceneColor {
    _prepareTranslucent();
    final end = _nextSceneColorBatchEnd();
    for (var i = _translucentCursor; i < end; i++) {
      if (_translucentRecords[i].material.sceneInputs.contains(
        RenderInput.filteredSceneColor,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Whether any pending translucent draw needs filtered scene color.
  bool get pendingTranslucentReadsFilteredSceneColor {
    _prepareTranslucent();
    for (var i = _translucentCursor; i < _translucentRecords.length; i++) {
      if (_translucentRecords[i].material.sceneInputs.contains(
        RenderInput.filteredSceneColor,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Emits one translucent batch in global back-to-front order.
  ///
  /// A batch ends immediately before the next material that reads scene
  /// color. Batching preserves global back-to-front order while letting the
  /// scene pass replace the render target between batches when needed.
  void flushNextTranslucentBatch({gpu.RenderPass? translucentPass}) {
    _prepareTranslucent();
    var end = _translucentCursor + 1;
    while (end < _translucentRecords.length &&
        !_readsSceneColor(_translucentRecords[end].material)) {
      end++;
    }
    _flushTranslucentThrough(end, translucentPass: translucentPass);
  }

  /// Emits one scene-color batch, grouping readers that cannot overlap.
  void flushNextSceneColorBatch({gpu.RenderPass? translucentPass}) {
    _flushTranslucentThrough(
      _nextSceneColorBatchEnd(),
      translucentPass: translucentPass,
    );
  }

  void _flushTranslucentThrough(int end, {gpu.RenderPass? translucentPass}) {
    _prepareTranslucent();
    if (_translucentCursor >= _translucentRecords.length) return;
    _phase = DrawPhase.translucent;

    if (translucentPass != null) {
      _renderPass = translucentPass;
      _boundPipeline = null;
      _boundMaterial = null;
      _boundMaterialVertex = null;
      _boundFrameInfoShader = null;
      _boundFrameInfoDepthBias = double.nan;
      _boundFrameInfoDepthKey = -1;
      _boundMaterialFade = double.nan;
      _boundMaterialLightOffset = -1;
      _boundMaterialLightCount = -1;
      _boundMaterialLightChannelMask = -1;
      _boundWindingOrder = null;
      _boundPrimitiveType = null;
      EngineLightingUniforms.invalidateBindMemo();
    }
    _renderPass.setDepthCompareOperation(_raster.nearerOrEqual);
    final encodeWatch = profileRendering ? (Stopwatch()..start()) : null;
    _renderPass.setDepthWriteEnable(false);
    _renderPass.setColorBlendEnable(true);
    _renderPass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );

    while (_translucentCursor < end) {
      final record = _translucentRecords[_translucentCursor++];
      _renderPass.setDepthWriteEnable(record.material.translucentDepthWrite);
      // Set per record, like the depth write above, so a projection volume
      // drawn with `always` cannot leak that test into the next draw.
      _renderPass.setDepthCompareOperation(
        _raster.compare(record.material.depthCompare),
      );
      record.material.lightListOffset = record.lightListOffset;
      record.material.lightListCount = record.lightListCount;
      record.material.lightChannelMask = record.item.lightChannelMask;
      record.material.setModelScaleFromTransform(record.item.worldTransform);
      final joints = record.jointsTexture;
      if (joints != null) {
        record.geometry.setJointsTexture(joints, record.jointsTextureWidth);
      }
      record.item.applyMorphWeights(record.geometry);
      final instances = record.item.instanceTransforms;
      if (instances != null) {
        _encodeInstanced(
          record.pipeline,
          record.worldTransform,
          record.geometry,
          record.material,
          instances,
          record.item.instanceColors!,
          record.windingFlipped,
          record.fade,
          instanceWindingFlipped: record.item.instanceWindingFlipped,
          instanceIndices: record.item.visibleInstanceIndices,
          sortBackToFrontFrom: record.item.sortTransparentInstances
              ? _cameraPosition
              : null,
          packedWorldData: record.windingFlipped == record.item.windingFlipped
              ? record.item.instanceWorldData
              : null,
          packedWorldWindingFlipped:
              record.windingFlipped == record.item.windingFlipped
              ? record.item.instanceWorldWindingFlipped
              : null,
          attributeData: record.item.instanceAttributeData,
          attributeFloats: record.item.instanceAttributeFloats,
          item: record.item,
        );
      } else {
        _encode(
          record.pipeline,
          record.worldTransform,
          record.geometry,
          record.material,
          record.windingFlipped,
          record.fade,
          item: record.item,
        );
      }
    }
    encodeWatch?.stop();
    _translucentEncodeMicros += encodeWatch?.elapsedMicroseconds ?? 0;

    if (_translucentCursor == _translucentRecords.length) {
      if (profileRendering) {
        _recordProfile(
          _opaqueSortMicros + _translucentSortMicros,
          _opaqueEncodeMicros + _translucentEncodeMicros,
          _encodedDraws,
          _encodedInstances,
        );
      }
      for (final record in _translucentRecords) {
        if (_translucentRecordPool.length == _recordPoolLimit) break;
        record.release();
        _translucentRecordPool.add(record);
      }
      _translucentRecords.clear();
      _translucentCursor = 0;
      _translucentPrepared = false;
      _translucentSortMicros = 0;
      _translucentEncodeMicros = 0;
    }
  }

  /// Emits only the translucent phase (see [flush]).
  void flushTranslucent({gpu.RenderPass? translucentPass}) {
    var pass = translucentPass;
    while (hasPendingTranslucent) {
      flushNextTranslucentBatch(translucentPass: pass);
      pass = null;
    }
  }

  /// Whether any recorded draw is display-referred (see
  /// [Material.displayReferred]).
  bool get hasDisplayReferred => _displayReferredRecords.isNotEmpty;

  /// Emits the display-referred layer into [pass], back to front with
  /// premultiplied source-over blending.
  ///
  /// The pass writes display-encoded color into its own target and shares the
  /// scene's depth attachment, so these surfaces are occluded by opaque
  /// geometry but never write depth and never order against translucency.
  void flushDisplayReferred(gpu.RenderPass pass) {
    if (_displayReferredRecords.isEmpty) return;
    _phase = DrawPhase.translucent;
    _drawTransformOverride = _displayReferredCameraTransform;
    _displayReferredRecords.sort(_backToFront);

    _renderPass = pass;
    _boundPipeline = null;
    _boundMaterial = null;
    _boundMaterialVertex = null;
    _boundFrameInfoShader = null;
    _boundFrameInfoDepthBias = double.nan;
    _boundFrameInfoDepthKey = -1;
    _boundMaterialFade = double.nan;
    _boundMaterialLightOffset = -1;
    _boundMaterialLightCount = -1;
    _boundMaterialLightChannelMask = -1;
    _boundWindingOrder = null;
    _boundPrimitiveType = null;
    EngineLightingUniforms.invalidateBindMemo();

    _renderPass.setDepthWriteEnable(false);
    _renderPass.setColorBlendEnable(true);
    _renderPass.setColorBlendEquation(
      gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
      ),
    );

    for (final record in _displayReferredRecords) {
      _renderPass.setDepthCompareOperation(
        _raster.compare(record.material.depthCompare),
      );
      record.material.lightListOffset = record.lightListOffset;
      record.material.lightListCount = record.lightListCount;
      record.material.lightChannelMask = record.item.lightChannelMask;
      record.material.setModelScaleFromTransform(record.item.worldTransform);
      final joints = record.jointsTexture;
      if (joints != null) {
        record.geometry.setJointsTexture(joints, record.jointsTextureWidth);
      }
      record.item.applyMorphWeights(record.geometry);
      final instances = record.item.instanceTransforms;
      if (instances != null) {
        _encodeInstanced(
          record.pipeline,
          record.worldTransform,
          record.geometry,
          record.material,
          instances,
          record.item.instanceColors!,
          record.windingFlipped,
          record.fade,
          instanceWindingFlipped: record.item.instanceWindingFlipped,
          instanceIndices: record.item.visibleInstanceIndices,
          sortBackToFrontFrom: record.item.sortTransparentInstances
              ? _cameraPosition
              : null,
          packedWorldData: record.windingFlipped == record.item.windingFlipped
              ? record.item.instanceWorldData
              : null,
          packedWorldWindingFlipped:
              record.windingFlipped == record.item.windingFlipped
              ? record.item.instanceWorldWindingFlipped
              : null,
          attributeData: record.item.instanceAttributeData,
          attributeFloats: record.item.instanceAttributeFloats,
          item: record.item,
        );
      } else {
        _encode(
          record.pipeline,
          record.worldTransform,
          record.geometry,
          record.material,
          record.windingFlipped,
          record.fade,
          item: record.item,
        );
      }
    }

    _drawTransformOverride = null;
    for (final record in _displayReferredRecords) {
      if (_translucentRecordPool.length == _recordPoolLimit) break;
      record.release();
      _translucentRecordPool.add(record);
    }
    _displayReferredRecords.clear();
  }

  static bool _readsSceneColor(Material material) {
    final inputs = material.sceneInputs;
    return inputs.contains(RenderInput.opaqueSceneColor) ||
        inputs.contains(RenderInput.filteredSceneColor);
  }
}
