import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
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
import 'package:flutter_scene/src/render/custom_render_pass.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/render_profile.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/instance_batching.dart';

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
    this.depth,
    this.windingFlipped,
  ) : _item = item,
      _geometry = geometry,
      _material = material,
      _pipeline = pipeline,
      geometryKey = identityHashCode(geometry),
      materialKey = identityHashCode(material);
  RenderItem? _item;
  RenderItem get item => _item!;
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
  late double depth;
  late bool windingFlipped;

  void reset(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    int pipelineKey,
    double depth,
    bool windingFlipped,
  ) {
    _item = item;
    _geometry = geometry;
    _material = material;
    this.fade = fade;
    _pipeline = pipeline;
    this.pipelineKey = pipelineKey;
    this.depth = depth;
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

/// Maximum accumulated scene-color batches emitted in one frame.
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
  final stopwatch = kDebugMode || profileRendering
      ? (Stopwatch()..start())
      : null;
  final pipeline = gpu.gpuContext.createRenderPipeline(
    vertexShader,
    fragmentShader,
    vertexLayout: vertexLayout?.toGpuLayout(),
  );
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
///    sorted by pipeline (to reduce state changes) and then front-to-back
///    (so the depth test can reject occluded fragments early).
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
  }) : _renderPass = renderPass,
       _transientsBuffer = transientsBuffer {
    currentSceneEncoderViewport = _dimensions;
    _cameraTransform = cameraTransform ?? _camera.getViewTransform(_dimensions);
    frustum = Frustum.matrix(_cameraTransform);
    // The screen-size LOD metric is perspective-specific; with any other
    // projection LOD nodes draw their highest-detail level.
    final camera = _camera;
    _lodFovRadiansY = camera is PerspectiveCamera ? camera.fovRadiansY : null;

    // Begin the opaque phase.
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  }

  final Camera _camera;
  final ui.Size _dimensions;
  final Lighting _lighting;
  final int _layerMask;
  final List<Plane> _cullingPlanes;
  final bool _cullInstances;
  // Not final because opaque and translucent draws can use separate passes.
  gpu.RenderPass _renderPass;
  final TransientWriter _transientsBuffer;
  late final Matrix4 _cameraTransform;
  // The camera's vertical field of view in radians, or null for a
  // non-perspective camera (which disables screen-size LOD).
  late final double? _lodFovRadiansY;
  final List<_OpaqueRecord> _opaqueRecords = [];
  final List<_TranslucentRecord> _translucentRecords = [];
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

  // The pipeline currently bound on the render pass, or null before the
  // first bind. `clearBindings` does not clear the pipeline, so a draw
  // that reuses it can skip the rebind. Opaque draws are pipeline-sorted,
  // so reuse runs are common.
  gpu.RenderPipeline? _boundPipeline;
  Material? _boundMaterial;
  gpu.Shader? _boundMaterialVertex;
  gpu.Shader? _boundFrameInfoShader;
  double _boundFrameInfoDepthBias = double.nan;
  double _boundMaterialFade = double.nan;
  int _boundMaterialLightOffset = -1;
  int _boundMaterialLightCount = -1;
  int _boundMaterialLightChannelMask = -1;
  gpu.WindingOrder? _boundWindingOrder;
  gpu.PrimitiveType? _boundPrimitiveType;
  int _encodedDraws = 0;
  int _encodedInstances = 0;

  /// Queues a draw call for [item], unless it is hidden or frustum
  /// culled.
  ///
  /// Both opaque and translucent draws are deferred; [flush] sorts and
  /// emits them. A translucent instanced item is queued as one draw per
  /// instance so each can be depth-sorted independently.
  void submit(RenderItem item) {
    if (!item.drawsColor) return;
    if ((item.layers & _layerMask) == 0) return;
    if (_cullInstances) {
      if (!item.cullVisibleInstances(frustum, _cullingPlanes)) return;
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
      for (final selection in _resolveLod(lod, worldBounds)) {
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
    final pipeline = tryResolvePipeline(
      material.materialVertexShader(geometry.materialVertexVariant) ??
          geometry.vertexShader,
      material.fragmentShaderForLighting(_lighting),
      // A material declaring `instance_attributes` widens the instance-rate
      // slot, so the pipeline depends on the material as well as the geometry.
      vertexLayout: geometry.instancedVertexLayoutFor(
        material.instanceAttributes,
      ),
      debugContext: () =>
          '${fmatSourcePathOf(material) ?? material.runtimeType} on '
          '${geometry.runtimeType}'
          '${geometry.hasCustomAttributes ? ' with custom vertex attributes' : ''}',
    );
    if (pipeline == null) return;

    if (material.isOpaque()) {
      _opaqueRecords.add(
        _obtainOpaqueRecord(
          item,
          geometry,
          material,
          fade,
          pipeline,
          identityHashCode(pipeline),
          _depthOf(item.worldTransform, geometry),
          item.windingFor(geometry),
        ),
      );
      return;
    }

    // Keep instanced translucency in one record. The instances are sorted
    // back to front while their transform buffer is packed at draw time.
    final instances = item.instanceTransforms;
    if (instances != null) {
      final bounds = item.worldBounds;
      _translucentRecords.add(
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
      _translucentRecords.add(
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
    double depth,
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
        depth,
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
      depth,
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
  // when no screen-size metric is available (no bounds, or a non-perspective
  // camera).
  List<({int level, double fade})> _resolveLod(
    LodSelection lod,
    Aabb3? worldBounds,
  ) {
    final fovRadiansY = _lodFovRadiansY;
    if (worldBounds == null || fovRadiansY == null) {
      return const [(level: 0, fade: 1.0)];
    }
    // The circumscribed sphere of the world AABB (conservative, so detail is
    // kept slightly longer than a tight sphere would).
    final radius = worldBounds.max.distanceTo(worldBounds.min) * 0.5;
    final size = lodScreenSize(
      center: worldBounds.center,
      radius: radius,
      cameraPosition: _camera.position,
      fovRadiansY: fovRadiansY,
    );
    return lod.resolve(size);
  }

  double _depthOf(Matrix4 worldTransform, [Geometry? geometry]) {
    return sceneSortDepth(
      worldTransform,
      geometry?.localBounds,
      _camera.position,
      _camera.forward,
    );
  }

  double _depthOfPoint(double x, double y, double z) {
    final position = _camera.position;
    final forward = _camera.forward;
    return (x - position.x) * forward.x +
        (y - position.y) * forward.y +
        (z - position.z) * forward.z;
  }

  // Binds [pipeline] unless it is already the bound one. `clearBindings`
  // leaves the pipeline in place, so consecutive draws that share a
  // pipeline only need to bind it once.
  void _bindPipeline(gpu.RenderPipeline pipeline) {
    if (identical(_boundPipeline, pipeline)) return;
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
    _boundMaterialVertex = null;
    _boundFrameInfoShader = null;
    _boundFrameInfoDepthBias = double.nan;
    _boundMaterialFade = double.nan;
    _boundMaterialLightOffset = -1;
    _boundMaterialLightCount = -1;
    _boundMaterialLightChannelMask = -1;
    _boundWindingOrder = null;
    _boundPrimitiveType = null;
  }

  void _bindMaterial(
    Material material,
    gpu.Shader? materialVertex,
    double fade,
  ) {
    final lightOffset = material.lightListOffset;
    final lightCount = material.lightListCount;
    final lightChannelMask = material.lightChannelMask;
    if (identical(_boundMaterial, material) &&
        identical(_boundMaterialVertex, materialVertex) &&
        _boundMaterialFade == fade &&
        _boundMaterialLightOffset == lightOffset &&
        _boundMaterialLightCount == lightCount &&
        _boundMaterialLightChannelMask == lightChannelMask) {
      return;
    }
    material.lodFade = fade;
    material.bind(_renderPass, _transientsBuffer, _lighting);
    _boundWindingOrder = null;
    if (materialVertex != null) {
      material.bindVertexStage(_renderPass, materialVertex, _transientsBuffer);
    }
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
    gpu.Shader? materialVertex,
    double depthBias,
  ) {
    if (geometry is UnskinnedGeometry) {
      geometry.bindGeometryBuffers(_renderPass);
      final shader = materialVertex ?? geometry.vertexShader;
      if (!identical(_boundFrameInfoShader, shader) ||
          _boundFrameInfoDepthBias != depthBias) {
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          shader,
          _cameraTransform,
          _camera.position,
          depthBias: depthBias,
        );
        _boundFrameInfoShader = shader;
        _boundFrameInfoDepthBias = depthBias;
      }
    } else {
      geometry.bind(
        _renderPass,
        _transientsBuffer,
        worldTransform,
        _cameraTransform,
        _camera.position,
        shaderOverride: materialVertex,
        depthBias: depthBias,
      );
    }
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

  void _drawGeometry(Geometry geometry, {int instanceCount = 1}) {
    if (profileRendering) {
      _encodedDraws++;
      _encodedInstances += instanceCount;
    }
    geometry.draw(_renderPass, instanceCount: instanceCount);
  }

  void _encode(
    gpu.RenderPipeline pipeline,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    bool windingFlipped,
    double fade,
  ) {
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
    _bindGeometry(geometry, worldTransform, materialVertex, material.depthBias);
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
    _bindMaterial(material, materialVertex, fade);
    // A mirrored transform reverses triangle winding. Set both cases because
    // a cached material bind no longer resets it between compatible draws.
    _setWindingOrder(
      windingFlipped
          ? gpu.WindingOrder.counterClockwise
          : gpu.WindingOrder.clockwise,
    );
    _setPrimitiveType(geometry.primitiveType);
    _drawGeometry(geometry);
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
  }) {
    checkInstanceRecordWidth(material.instanceAttributes, attributeFloats);
    if (!identical(_boundPipeline, pipeline)) {
      _clearBindings();
    }
    _bindPipeline(pipeline);
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    _bindMaterial(material, materialVertex, fade);
    _setPrimitiveType(geometry.primitiveType);

    if (geometry.instancedVertexLayout == null) {
      final count = instanceIndices?.length ?? instances.length;
      for (var slot = 0; slot < count; slot++) {
        final instanceIndex = instanceIndices?[slot] ?? slot;
        final instanceTransform = instances[instanceIndex];
        _bindGeometry(
          geometry,
          nodeTransform * instanceTransform,
          materialVertex,
          material.depthBias,
        );
        // Each instance can itself mirror; combine with the node's parity.
        final flip = windingFlipped != (instanceTransform.determinant() < 0);
        _setWindingOrder(
          flip ? gpu.WindingOrder.counterClockwise : gpu.WindingOrder.clockwise,
        );
        _drawGeometry(geometry);
      }
      return;
    }

    _bindGeometry(geometry, nodeTransform, materialVertex, material.depthBias);
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
      _drawGeometry(geometry, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, instanceCount: packed.cwCount);
    }
  }

  void _encodeInstancedBatches(
    gpu.RenderPipeline pipeline,
    Geometry geometry,
    Material material,
    List<InstanceDataBatch> batches,
    double fade,
  ) {
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
    _bindMaterial(material, materialVertex, fade);
    _setPrimitiveType(geometry.primitiveType);
    _bindGeometry(
      geometry,
      _identityTransform,
      materialVertex,
      material.depthBias,
    );
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
      _drawGeometry(geometry, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, instanceCount: packed.cwCount);
    }
  }

  static final Matrix4 _identityTransform = Matrix4.identity();

  /// Sorts and emits every deferred draw, then finishes recording.
  ///
  /// Opaque draws are sorted by pipeline (state-change grouping) and then
  /// front-to-back (early-Z), and drawn first. Translucent draws are then
  /// sorted back-to-front and drawn with premultiplied source-over
  /// blending and depth writes disabled. After this returns the encoder
  /// has finished recording into its render pass; the caller submits the
  /// owning command buffer.
  void flush() {
    flushOpaque();
    flushTranslucent();
  }

  /// Emits only the opaque phase (see [flush]). Used with [flushTranslucent]
  /// when the scene pass snapshots the opaque color between them.
  void flushOpaque() {
    final sortWatch = profileRendering ? (Stopwatch()..start()) : null;
    _opaqueRecords.sort((a, b) {
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
      return a.depth.compareTo(b.depth);
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
      if (end > index + 1) {
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
        );
      } else {
        _encode(
          record.pipeline,
          item.worldTransform,
          record.geometry,
          record.material,
          record.windingFlipped,
          record.fade,
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

  void _prepareTranslucent() {
    if (_translucentPrepared) return;
    final sortWatch = profileRendering ? (Stopwatch()..start()) : null;
    _translucentRecords.sort((a, b) => b.depth.compareTo(a.depth));
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

    if (translucentPass != null) {
      _renderPass = translucentPass;
      _boundPipeline = null;
      _boundMaterial = null;
      _boundMaterialVertex = null;
      _boundFrameInfoShader = null;
      _boundFrameInfoDepthBias = double.nan;
      _boundMaterialFade = double.nan;
      _boundMaterialLightOffset = -1;
      _boundMaterialLightCount = -1;
      _boundMaterialLightChannelMask = -1;
      _boundWindingOrder = null;
      _boundPrimitiveType = null;
      EngineLightingUniforms.invalidateBindMemo();
    }
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
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
      _renderPass.setDepthCompareOperation(record.material.depthCompare);
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
              ? _camera.position
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
        );
      } else {
        _encode(
          record.pipeline,
          record.worldTransform,
          record.geometry,
          record.material,
          record.windingFlipped,
          record.fade,
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

  static bool _readsSceneColor(Material material) {
    final inputs = material.sceneInputs;
    return inputs.contains(RenderInput.opaqueSceneColor) ||
        inputs.contains(RenderInput.filteredSceneColor);
  }
}
