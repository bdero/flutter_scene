import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/render_scene.dart';

/// A deferred opaque draw. Holds the [RenderItem] (instanced or not), its
/// resolved pipeline, a per-pipeline grouping key, and the camera
/// distance, all captured when [SceneEncoder.submit] is called.
base class _OpaqueRecord {
  _OpaqueRecord(this.item, this.pipeline, this.pipelineKey, this.depth);
  final RenderItem item;
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
    this.pipeline,
    this.depth,
  );
  final Matrix4 worldTransform;
  final Geometry geometry;
  final Material material;
  final gpu.RenderPipeline pipeline;
  final double depth;
}

/// Render pipelines keyed by their (vertex, fragment) shader pair.
///
/// A pipeline depends only on its two shaders (blend, depth, and cull
/// state are set on the render pass, not baked into the pipeline), and
/// shaders are loaded once and reused, so pipelines are cached for the
/// process lifetime instead of being rebuilt per draw call.
final Map<(gpu.Shader, gpu.Shader), gpu.RenderPipeline> _pipelineCache = {};

gpu.RenderPipeline _resolvePipeline(
  gpu.Shader vertexShader,
  gpu.Shader fragmentShader,
) {
  return _pipelineCache[(vertexShader, fragmentShader)] ??= gpu.gpuContext
      .createRenderPipeline(vertexShader, fragmentShader);
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
  ) : _renderPass = renderPass,
      _transientsBuffer = transientsBuffer {
    _cameraTransform = _camera.getViewTransform(dimensions);
    frustum = Frustum.matrix(_cameraTransform);

    // Begin the opaque phase.
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  }

  final Camera _camera;
  final Lighting _lighting;
  final gpu.RenderPass _renderPass;
  final gpu.HostBuffer _transientsBuffer;
  late final Matrix4 _cameraTransform;
  final List<_OpaqueRecord> _opaqueRecords = [];
  final List<_TranslucentRecord> _translucentRecords = [];

  /// View frustum derived from the camera's view-projection matrix at
  /// the start of this frame. Used by [submit] for per-item culling.
  late final Frustum frustum;

  /// Reusable AABB owned by this encoder so the per-item cull check can
  /// transform a local AABB into world space without allocating a new
  /// [Aabb3] for every item, every frame.
  final Aabb3 cullScratchAabb = Aabb3();

  /// Queues a draw call for [item], unless it is hidden or frustum
  /// culled.
  ///
  /// Both opaque and translucent draws are deferred; [flush] sorts and
  /// emits them. A translucent instanced item is queued as one draw per
  /// instance so each can be depth-sorted independently.
  void submit(RenderItem item) {
    if (!item.visible) return;
    if (item.frustumCulled) {
      final bounds = item.cullBounds;
      if (bounds != null) {
        cullScratchAabb
          ..copyFrom(bounds)
          ..transform(item.worldTransform);
        if (!frustum.intersectsWithAabb3(cullScratchAabb)) return;
      }
    }

    final pipeline = _resolvePipeline(
      item.geometry.vertexShader,
      item.material.fragmentShader,
    );

    if (item.material.isOpaque()) {
      _opaqueRecords.add(
        _OpaqueRecord(
          item,
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
            item.geometry,
            item.material,
            pipeline,
            _depthOf(worldTransform),
          ),
        );
      }
    } else {
      _translucentRecords.add(
        _TranslucentRecord(
          item.worldTransform,
          item.geometry,
          item.material,
          pipeline,
          _depthOf(item.worldTransform),
        ),
      );
    }
  }

  double _depthOf(Matrix4 worldTransform) =>
      worldTransform.getTranslation().distanceTo(_camera.position);

  void _encode(
    gpu.RenderPipeline pipeline,
    Matrix4 worldTransform,
    Geometry geometry,
    Material material,
  ) {
    _renderPass.clearBindings();
    _renderPass.bindPipeline(pipeline);
    geometry.bind(
      _renderPass,
      _transientsBuffer,
      worldTransform,
      _cameraTransform,
      _camera.position,
    );
    material.bind(_renderPass, _transientsBuffer, _lighting);
    _renderPass.draw();
  }

  /// Draws an opaque instanced item: binds the pipeline and the material
  /// once, then re-binds only the geometry (with each instance's world
  /// transform) and draws, once per instance.
  void _encodeInstanced(
    gpu.RenderPipeline pipeline,
    Matrix4 nodeTransform,
    Geometry geometry,
    Material material,
    List<Matrix4> instances,
  ) {
    _renderPass.clearBindings();
    _renderPass.bindPipeline(pipeline);
    material.bind(_renderPass, _transientsBuffer, _lighting);
    for (final instanceTransform in instances) {
      geometry.bind(
        _renderPass,
        _transientsBuffer,
        nodeTransform * instanceTransform,
        _cameraTransform,
        _camera.position,
      );
      _renderPass.draw();
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
          item.geometry,
          item.material,
          instances,
        );
      } else {
        _encode(
          record.pipeline,
          item.worldTransform,
          item.geometry,
          item.material,
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
      );
    }
    _translucentRecords.clear();
  }
}
