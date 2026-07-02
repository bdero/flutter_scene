import 'dart:ui' as ui;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/geometry/vertex_layout.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/instance_packing.dart';
import 'package:flutter_scene/src/render/lod.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

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
  final RenderItem item;
  // The geometry and material to draw, which differ from the item's own when
  // a level of detail was selected.
  final Geometry geometry;
  final Material material;
  // LOD cross-fade coverage for this draw (1 when not fading); see
  // [Material.lodFade].
  final double fade;
  final gpu.RenderPipeline pipeline;
  final int pipelineKey;
  final double depth;
}

/// A deferred translucent draw. An instanced translucent item produces
/// one record per instance, so each carries its own world transform.
base class _TranslucentRecord {
  _TranslucentRecord(
    this.worldTransform,
    this.geometry,
    this.material,
    this.fade,
    this.pipeline,
    this.depth,
    this.windingFlipped,
  );
  final Matrix4 worldTransform;
  final Geometry geometry;
  final Material material;
  final double fade;
  final gpu.RenderPipeline pipeline;
  final double depth;
  final bool windingFlipped;
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
/// `gpu.HostBuffer` directly.
base class SceneEncoder {
  /// Creates an encoder that records into [renderPass], allocating
  /// transient uniforms from [transientsBuffer].
  ///
  /// `dimensions` is the viewport size used to derive the camera's view
  /// transform; [lighting] is the scene's IBL environment and analytic
  /// lights, passed to each material's `bind`. The render pass is
  /// configured for the opaque phase (depth writes on, blending off).
  SceneEncoder(
    gpu.RenderPass renderPass,
    gpu.HostBuffer transientsBuffer,
    this._camera,
    ui.Size dimensions,
    this._lighting,
    this._layerMask,
  ) : _renderPass = renderPass,
      _transientsBuffer = transientsBuffer {
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
  final gpu.RenderPass _renderPass;
  final gpu.HostBuffer _transientsBuffer;
  late final Matrix4 _cameraTransform;
  // The camera's vertical field of view in radians, or null for a
  // non-perspective camera (which disables screen-size LOD).
  late final double? _lodFovRadiansY;
  final List<_OpaqueRecord> _opaqueRecords = [];
  final List<_TranslucentRecord> _translucentRecords = [];

  /// View frustum derived from the camera's view-projection matrix at
  /// the start of this frame. Used by [submit] for per-item culling.
  late final Frustum frustum;

  /// Reusable AABB owned by this encoder so the per-item cull check can
  /// transform a local AABB into world space without allocating a new
  /// [Aabb3] for every item, every frame.
  final Aabb3 cullScratchAabb = Aabb3();

  // The pipeline currently bound on the render pass, or null before the
  // first bind. `clearBindings` does not clear the pipeline, so a draw
  // that reuses it can skip the rebind. Opaque draws are pipeline-sorted,
  // so reuse runs are common.
  gpu.RenderPipeline? _boundPipeline;

  /// Queues a draw call for [item], unless it is hidden or frustum
  /// culled.
  ///
  /// Both opaque and translucent draws are deferred; [flush] sorts and
  /// emits them. A translucent instanced item is queued as one draw per
  /// instance so each can be depth-sorted independently.
  void submit(RenderItem item) {
    if (!item.visible) return;
    if ((item.layers & _layerMask) == 0) return;

    // The world-space AABB is needed for frustum culling and, when the item
    // has levels of detail, for the screen-size metric; compute it once.
    final lod = item.lod;
    Aabb3? worldBounds;
    final localBounds = item.cullBounds;
    if ((item.frustumCulled || lod != null) && localBounds != null) {
      cullScratchAabb
        ..copyFrom(localBounds)
        ..transform(item.worldTransform);
      worldBounds = cullScratchAabb;
    }
    if (item.frustumCulled &&
        worldBounds != null &&
        !frustum.intersectsWithAabb3(worldBounds)) {
      return;
    }

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
        _OpaqueRecord(
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

    // Translucent. Instanced items are exploded into one record per
    // instance, like any other translucent draw.
    final instances = item.instanceTransforms;
    if (instances != null) {
      for (final instanceTransform in instances) {
        final worldTransform = item.worldTransform * instanceTransform;
        _translucentRecords.add(
          _TranslucentRecord(
            worldTransform,
            geometry,
            material,
            fade,
            pipeline,
            _depthOf(worldTransform),
            item.windingFlipped != (instanceTransform.determinant() < 0),
          ),
        );
      }
    } else {
      _translucentRecords.add(
        _TranslucentRecord(
          item.worldTransform,
          geometry,
          material,
          fade,
          pipeline,
          _depthOf(item.worldTransform),
          item.windingFlipped,
        ),
      );
    }
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

  void _encode(
    gpu.RenderPipeline pipeline,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
    bool windingFlipped,
    double fade,
  ) {
    _renderPass.clearBindings();
    _bindPipeline(pipeline);
    // The material reads its cross-fade coverage from this transient field as
    // it binds; reset for every draw so a shared material does not leak a
    // previous draw's fade.
    material.lodFade = fade;
    // A `vertex { }` material supplies its own vertex shader for this mesh
    // type; the geometry must bind FrameInfo (and skinned's joints texture)
    // against it, since its uniform slots can differ from the engine default.
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    geometry.bind(
      _renderPass,
      _transientsBuffer,
      worldTransform,
      _cameraTransform,
      _camera.position,
      shaderOverride: materialVertex,
    );
    if (geometry.bindsModelTransformInstance) {
      // The model matrix arrives through the instance-rate vertex buffer,
      // bound to the slot after the geometry's vertex streams.
      bindSingleInstanceTransform(
        _renderPass,
        worldTransform,
        slot: geometry.vertexStreamCount,
      );
    }
    material.bind(_renderPass, _transientsBuffer, _lighting);
    if (materialVertex != null) {
      material.bindVertexStage(_renderPass, materialVertex, _transientsBuffer);
    }
    if (windingFlipped) {
      // A mirrored (negative-determinant) transform reverses triangle
      // winding; flip the cull order so front faces aren't culled. Material
      // .bind set the default counter-clockwise winding.
      _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);
    geometry.draw(_renderPass);
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
    bool windingFlipped,
    double fade,
  ) {
    _renderPass.clearBindings();
    _bindPipeline(pipeline);
    material.lodFade = fade;
    final materialVertex = material.materialVertexShader(
      geometry.materialVertexVariant,
    );
    material.bind(_renderPass, _transientsBuffer, _lighting);
    if (materialVertex != null) {
      material.bindVertexStage(_renderPass, materialVertex, _transientsBuffer);
    }
    _renderPass.setPrimitiveType(geometry.primitiveType);

    if (geometry.instancedVertexLayout == null) {
      for (final instanceTransform in instances) {
        geometry.bind(
          _renderPass,
          _transientsBuffer,
          nodeTransform * instanceTransform,
          _cameraTransform,
          _camera.position,
          shaderOverride: materialVertex,
        );
        // Each instance can itself mirror; combine with the node's parity.
        final flip = windingFlipped != (instanceTransform.determinant() < 0);
        _renderPass.setWindingOrder(
          flip ? gpu.WindingOrder.clockwise : gpu.WindingOrder.counterClockwise,
        );
        geometry.draw(_renderPass);
      }
      return;
    }

    geometry.bind(
      _renderPass,
      _transientsBuffer,
      nodeTransform,
      _cameraTransform,
      _camera.position,
      shaderOverride: materialVertex,
    );
    final packed = packInstanceTransforms(
      nodeTransform,
      instances,
      nodeWindingFlipped: windingFlipped,
    );
    final instanceSlot = geometry.vertexStreamCount;
    if (packed.ccwCount > 0) {
      bindInstanceTransforms(_renderPass, packed.ccw, slot: instanceSlot);
      _renderPass.setWindingOrder(gpu.WindingOrder.counterClockwise);
      geometry.draw(_renderPass, instanceCount: packed.ccwCount);
    }
    if (packed.cwCount > 0) {
      bindInstanceTransforms(_renderPass, packed.cw, slot: instanceSlot);
      _renderPass.setWindingOrder(gpu.WindingOrder.clockwise);
      geometry.draw(_renderPass, instanceCount: packed.cwCount);
    }
  }

  /// Sorts and emits every deferred draw, then finishes recording.
  ///
  /// Opaque draws are sorted by pipeline (state-change grouping) and then
  /// front-to-back (early-Z), and drawn first. Translucent draws are then
  /// sorted back-to-front and drawn with premultiplied source-over
  /// blending and depth writes disabled. After this returns the encoder
  /// has finished recording into its render pass; the caller submits the
  /// owning command buffer.
  void flush() {
    _opaqueRecords.sort((a, b) {
      final byPipeline = a.pipelineKey.compareTo(b.pipelineKey);
      if (byPipeline != 0) return byPipeline;
      return a.depth.compareTo(b.depth);
    });
    for (final record in _opaqueRecords) {
      final item = record.item;
      final instances = item.instanceTransforms;
      if (instances != null) {
        _encodeInstanced(
          record.pipeline,
          item.worldTransform,
          record.geometry,
          record.material,
          instances,
          item.windingFlipped,
          record.fade,
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
    }
    _opaqueRecords.clear();

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
      _encode(
        record.pipeline,
        record.worldTransform,
        record.geometry,
        record.material,
        record.windingFlipped,
        record.fade,
      );
    }
    _translucentRecords.clear();
  }
}
