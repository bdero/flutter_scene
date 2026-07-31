import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';

/// A deferred opaque draw. Holds the [RenderItem] (instanced or not), its
/// resolved pipeline, a per-pipeline grouping key, and the camera
/// distance, all captured when [SceneEncoder.submit] is called.
base class _OpaqueRecord {
  _OpaqueRecord(
    this.item,
    this.geometry,
    this.material,
    this.fade,
    this.pipeline,
    this.pipelineKey,
    this.depth,
  );
  late RenderItem item;
  // The geometry and material to draw, which differ from the item's own when
  // a level of detail was selected.
  late Geometry geometry;
  late Material material;
  // LOD cross-fade coverage for this draw (1 when not fading); see
  // [Material.lodFade].
  late double fade;
  late gpu.RenderPipeline pipeline;
  late int pipelineKey;
  late double depth;

  void reset(
    RenderItem item,
    Geometry geometry,
    Material material,
    double fade,
    gpu.RenderPipeline pipeline,
    int pipelineKey,
    double depth,
  ) {
    this.item = item;
    this.geometry = geometry;
    this.material = material;
    this.fade = fade;
    this.pipeline = pipeline;
    this.pipelineKey = pipelineKey;
    this.depth = depth;
  }

  int get geometryKey => identityHashCode(geometry);
  int get materialKey => identityHashCode(material);
}

/// A deferred translucent draw. Instanced draws retain their item so their
/// transforms can be sorted while the instance buffer is packed.
base class _TranslucentRecord {
  _TranslucentRecord(
    this.item,
    this.worldTransform,
    this.geometry,
    this.material,
    this.fade,
    this.pipeline,
    this.depth,
    this.windingFlipped,
    this.lightListOffset,
    this.lightListCount,
    this.jointsTexture,
    this.jointsTextureWidth,
  );
  late RenderItem item;
  late Matrix4 worldTransform;
  late Geometry geometry;
  late Material material;
  late double fade;
  late gpu.RenderPipeline pipeline;
  late double depth;
  late bool windingFlipped;
  // The owning item's punctual-light slice, captured at submit time.
  late int lightListOffset;
  late int lightListCount;
  // The owning item's joints texture, applied to the geometry right before
  // this draw so skinned items sharing one geometry keep their own skeleton.
  late gpu.Texture? jointsTexture;
  late int jointsTextureWidth;

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
    this.item = item;
    this.worldTransform = worldTransform;
    this.geometry = geometry;
    this.material = material;
    this.fade = fade;
    this.pipeline = pipeline;
    this.depth = depth;
    this.windingFlipped = windingFlipped;
    this.lightListOffset = lightListOffset;
    this.lightListCount = lightListCount;
    this.jointsTexture = jointsTexture;
    this.jointsTextureWidth = jointsTextureWidth;
  }
}

/// The viewport size of the scene color pass currently being encoded.
///
/// Set by [SceneEncoder] at construction and read by geometry whose
/// projection math needs the pixel scale (splat footprints). Encoding is
/// single-threaded, so a frame-scoped module value is safe.
/// TODO(splats): thread the viewport through `Geometry.bind` instead once
/// another consumer appears.
ui.Size currentSceneEncoderViewport = ui.Size.zero;

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
}) {
  final key = (vertexShader, fragmentShader, vertexLayoutId(vertexLayout));
  return _pipelineCache[key] ??= gpu.gpuContext.createRenderPipeline(
    vertexShader,
    fragmentShader,
    vertexLayout: vertexLayout?.toGpuLayout(),
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
  static const bool _profile = bool.fromEnvironment('FLUTTER_SCENE_PROFILE');
  static int _profileSamples = 0;
  static int _sortMicros = 0;
  static int _encodeMicros = 0;
  static int _draws = 0;
  static int _instances = 0;

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
    ui.Size dimensions,
    this._lighting,
    this._layerMask,
    this._cullingPlanes,
    this._cullInstances,
  ) : _renderPass = renderPass,
      _transientsBuffer = transientsBuffer {
    currentSceneEncoderViewport = dimensions;
    _cameraTransform = _camera.getViewTransform(dimensions);
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
  final Lighting _lighting;
  final int _layerMask;
  final List<Plane> _cullingPlanes;
  final bool _cullInstances;
  // Not final: when the scene pass splits into two GPU passes to snapshot
  // the opaque color, [flushTranslucent] switches recording to the second
  // pass.
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
  double _boundMaterialFade = double.nan;
  int _boundMaterialLightOffset = -1;
  int _boundMaterialLightCount = -1;
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
    if (!item.visible) return;
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
    final pipeline = resolvePipeline(
      material.materialVertexShader(geometry.materialVertexVariant) ??
          geometry.vertexShader,
      material.fragmentShader,
      vertexLayout: geometry.instancedVertexLayout,
    );

    if (material.isOpaque()) {
      _opaqueRecords.add(
        _obtainOpaqueRecord(
          item,
          geometry,
          material,
          fade,
          pipeline,
          identityHashCode(pipeline),
          _depthOf(item.worldTransform),
        ),
      );
      return;
    }

    // Keep instanced translucency in one record. The instances are sorted
    // back to front while their transform buffer is packed at draw time.
    final instances = item.instanceTransforms;
    if (instances != null) {
      final center = item.worldBounds?.center;
      _translucentRecords.add(
        _obtainTranslucentRecord(
          item,
          item.worldTransform,
          geometry,
          material,
          fade,
          pipeline,
          center == null
              ? _depthOf(item.worldTransform)
              : center.distanceTo(_camera.position),
          item.windingFlipped,
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
          _depthOf(item.worldTransform),
          item.windingFlipped,
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
      );
    }
    return _opaqueRecordPool.removeLast()
      ..reset(item, geometry, material, fade, pipeline, pipelineKey, depth);
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

  double _depthOf(Matrix4 worldTransform) =>
      worldTransform.getTranslation().distanceTo(_camera.position);

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
    _boundMaterialFade = double.nan;
    _boundMaterialLightOffset = -1;
    _boundMaterialLightCount = -1;
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
    if (identical(_boundMaterial, material) &&
        identical(_boundMaterialVertex, materialVertex) &&
        _boundMaterialFade == fade &&
        _boundMaterialLightOffset == lightOffset &&
        _boundMaterialLightCount == lightCount) {
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
  ) {
    if (geometry is UnskinnedGeometry) {
      geometry.bindGeometryBuffers(_renderPass);
      final shader = materialVertex ?? geometry.vertexShader;
      if (!identical(_boundFrameInfoShader, shader)) {
        bindUnskinnedFrameInfo(
          _renderPass,
          _transientsBuffer,
          shader,
          _cameraTransform,
          _camera.position,
        );
        _boundFrameInfoShader = shader;
      }
    } else {
      geometry.bind(
        _renderPass,
        _transientsBuffer,
        worldTransform,
        _cameraTransform,
        _camera.position,
        shaderOverride: materialVertex,
      );
    }
  }

  void _bindPackedInstances(Float32List packed, int slot) {
    bindInstanceData(_renderPass, packed, slot: slot);
  }

  void _drawGeometry(Geometry geometry, {int instanceCount = 1}) {
    if (_profile) {
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
    _bindGeometry(geometry, worldTransform, materialVertex);
    if (geometry.bindsModelTransformInstance) {
      // The model matrix arrives through the instance-rate vertex buffer,
      // bound to the slot after the geometry's vertex streams.
      bindSingleInstanceData(
        _renderPass,
        worldTransform,
        slot: geometry.vertexStreamCount,
      );
    }
    _bindMaterial(material, materialVertex, fade);
    // A mirrored transform reverses triangle winding. Set both cases because
    // a cached material bind no longer resets it between compatible draws.
    _setWindingOrder(
      windingFlipped
          ? gpu.WindingOrder.clockwise
          : gpu.WindingOrder.counterClockwise,
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
  }) {
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
        );
        // Each instance can itself mirror; combine with the node's parity.
        final flip = windingFlipped != (instanceTransform.determinant() < 0);
        _setWindingOrder(
          flip ? gpu.WindingOrder.clockwise : gpu.WindingOrder.counterClockwise,
        );
        _drawGeometry(geometry);
      }
      return;
    }

    _bindGeometry(geometry, nodeTransform, materialVertex);
    final packed =
        sortBackToFrontFrom == null &&
            packedWorldData != null &&
            packedWorldWindingFlipped != null
        ? packInstanceDataBatches([
            InstanceDataBatch.cached(
              packedWorldData: packedWorldData,
              packedWindingFlipped: packedWorldWindingFlipped,
              indices: instanceIndices,
            ),
          ], scratch: transientInstancePackingScratch)
        : packInstanceData(
            nodeTransform,
            instances,
            colors,
            nodeWindingFlipped: windingFlipped,
            instanceWindingFlipped: instanceWindingFlipped,
            indices: instanceIndices,
            sortBackToFrontFrom: sortBackToFrontFrom,
            scratch: transientInstancePackingScratch,
          );
    final instanceSlot = geometry.vertexStreamCount;
    if (packed.ccwCount > 0) {
      _bindPackedInstances(packed.ccw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.clockwise);
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
    if (!identical(_boundPipeline, pipeline)) {
      _clearBindings();
    }
    _bindPipeline(pipeline);
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    _bindMaterial(material, materialVertex, fade);
    _setPrimitiveType(geometry.primitiveType);
    _bindGeometry(geometry, _identityTransform, materialVertex);
    final packed = packInstanceDataBatches(
      batches,
      scratch: transientInstancePackingScratch,
    );
    final instanceSlot = geometry.vertexStreamCount;
    if (packed.ccwCount > 0) {
      _bindPackedInstances(packed.ccw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.counterClockwise);
      _drawGeometry(geometry, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      _bindPackedInstances(packed.cw, instanceSlot);
      _setWindingOrder(gpu.WindingOrder.clockwise);
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

  /// Emits only the opaque phase (see [flush]). Used with
  /// [flushTranslucent] when the scene pass splits the frame into two GPU
  /// passes to snapshot the opaque color between them.
  void flushOpaque() {
    final sortWatch = _profile ? (Stopwatch()..start()) : null;
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
      final byFade = a.fade.compareTo(b.fade);
      if (byFade != 0) return byFade;
      return a.depth.compareTo(b.depth);
    });
    sortWatch?.stop();
    final encodeWatch = _profile ? (Stopwatch()..start()) : null;
    var index = 0;
    while (index < _opaqueRecords.length) {
      final record = _opaqueRecords[index];
      final item = record.item;
      record.material.lightListOffset = item.lightListOffset;
      record.material.lightListCount = item.lightListCount;
      item.applyJointsTexture(record.geometry);

      var end = index + 1;
      if (record.geometry.instancedVertexLayout != null &&
          item.jointsTexture == null) {
        while (end < _opaqueRecords.length &&
            _canBatchOpaque(record, _opaqueRecords[end])) {
          end++;
        }
      }
      if (end > index + 1) {
        final batches = <InstanceDataBatch>[];
        for (var batchIndex = index; batchIndex < end; batchIndex++) {
          final batchItem = _opaqueRecords[batchIndex].item;
          final instances = batchItem.instanceTransforms;
          if (instances == null) {
            batches.add(
              InstanceDataBatch.single(
                nodeTransform: batchItem.worldTransform,
                nodeWindingFlipped: batchItem.windingFlipped,
              ),
            );
            continue;
          }
          final packedWorldData = batchItem.instanceWorldData;
          final packedWinding = batchItem.instanceWorldWindingFlipped;
          if (packedWorldData != null && packedWinding != null) {
            batches.add(
              InstanceDataBatch.cached(
                packedWorldData: packedWorldData,
                packedWindingFlipped: packedWinding,
                indices: batchItem.visibleInstanceIndices,
              ),
            );
            continue;
          }
          batches.add(
            InstanceDataBatch(
              nodeTransform: batchItem.worldTransform,
              instances: instances,
              colors: batchItem.instanceColors!,
              nodeWindingFlipped: batchItem.windingFlipped,
              instanceWindingFlipped: batchItem.instanceWindingFlipped,
              indices: batchItem.visibleInstanceIndices,
            ),
          );
        }
        _encodeInstancedBatches(
          record.pipeline,
          record.geometry,
          record.material,
          batches,
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
          item.windingFlipped,
          record.fade,
          instanceWindingFlipped: item.instanceWindingFlipped,
          instanceIndices: item.visibleInstanceIndices,
          packedWorldData: item.instanceWorldData,
          packedWorldWindingFlipped: item.instanceWorldWindingFlipped,
        );
      } else {
        _encode(
          record.pipeline,
          item.worldTransform,
          record.geometry,
          record.material,
          item.windingFlipped,
          record.fade,
        );
      }
      index++;
    }
    encodeWatch?.stop();
    if (_profile) {
      _recordProfile(
        sortWatch!.elapsedMicroseconds,
        encodeWatch!.elapsedMicroseconds,
        _encodedDraws,
        _encodedInstances,
      );
    }
    for (final record in _opaqueRecords) {
      if (_opaqueRecordPool.length == _recordPoolLimit) break;
      _opaqueRecordPool.add(record);
    }
    _opaqueRecords.clear();
  }

  static void _recordProfile(
    int sortMicros,
    int encodeMicros,
    int draws,
    int instances,
  ) {
    _profileSamples++;
    _sortMicros += sortMicros;
    _encodeMicros += encodeMicros;
    _draws += draws;
    _instances += instances;
    if (_profileSamples < 120) return;
    // ignore: avoid_print
    print(
      'FLUTTER_SCENE_PROFILE_ENCODER '
      'sort_mean_us=${_sortMicros ~/ _profileSamples} '
      'encode_mean_us=${_encodeMicros ~/ _profileSamples} '
      'draws_mean=${_draws ~/ _profileSamples} '
      'instances_mean=${_instances ~/ _profileSamples}',
    );
    _profileSamples = 0;
    _sortMicros = 0;
    _encodeMicros = 0;
    _draws = 0;
    _instances = 0;
  }

  bool _canBatchOpaque(_OpaqueRecord first, _OpaqueRecord next) {
    final a = first.item;
    final b = next.item;
    return identical(first.pipeline, next.pipeline) &&
        identical(first.geometry, next.geometry) &&
        identical(first.material, next.material) &&
        first.fade == next.fade &&
        a.lightListOffset == b.lightListOffset &&
        a.lightListCount == b.lightListCount &&
        b.jointsTexture == null;
  }

  /// Emits only the translucent phase (see [flush]). When [translucentPass]
  /// is given, recording switches to it first (the split-pass path: the
  /// opaque color was resolved between the passes, so translucent materials
  /// can sample it); the new pass starts with no bound pipeline and needs
  /// the depth test re-asserted.
  void flushTranslucent({gpu.RenderPass? translucentPass}) {
    if (translucentPass != null) {
      _renderPass = translucentPass;
      _boundPipeline = null;
      _boundMaterial = null;
      _boundMaterialVertex = null;
      _boundFrameInfoShader = null;
      _boundWindingOrder = null;
      _boundPrimitiveType = null;
      _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    }

    _translucentRecords.sort((a, b) => b.depth.compareTo(a.depth));
    _renderPass.setDepthWriteEnable(false);
    _renderPass.setColorBlendEnable(true);
    // Premultiplied source-over blending.
    // Note: expects premultiplied-alpha output from the fragment stage.
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
    for (final record in _translucentRecords) {
      record.material.lightListOffset = record.lightListOffset;
      record.material.lightListCount = record.lightListCount;
      final joints = record.jointsTexture;
      if (joints != null) {
        record.geometry.setJointsTexture(joints, record.jointsTextureWidth);
      }
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
          sortBackToFrontFrom: _camera.position,
          packedWorldData: record.item.instanceWorldData,
          packedWorldWindingFlipped: record.item.instanceWorldWindingFlipped,
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
    for (final record in _translucentRecords) {
      if (_translucentRecordPool.length == _recordPoolLimit) break;
      _translucentRecordPool.add(record);
    }
    _translucentRecords.clear();
  }
}
