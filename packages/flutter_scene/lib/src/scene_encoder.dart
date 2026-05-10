import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';

base class _TranslucentRecord {
  _TranslucentRecord(this.worldTransform, this.geometry, this.material);
  final Matrix4 worldTransform;
  final Geometry geometry;
  final Material material;
}

/// Records draw calls for one frame of a [Scene].
///
/// `SceneEncoder` is the bridge between the scene graph and Flutter GPU.
/// [Scene.render] constructs an encoder for each frame, walks the scene
/// graph with [Node.render] (which forwards to [encode]), then calls
/// [finish] to submit the recorded command buffer.
///
/// The encoder splits draws into two passes:
///
/// 1. **Opaque pass**, with depth writes enabled and color blending
///    disabled, executed in submission order as [encode] is called.
/// 2. **Translucent pass**, automatically deferred and depth-sorted back
///    to front from the camera, drawn with premultiplied source-over
///    blending.
///
/// Applications typically do not construct `SceneEncoder` directly;
/// custom [Geometry] or [Material] subclasses interact with it through
/// the `bind` callback.
base class SceneEncoder {
  /// Creates an encoder targeting [renderTarget] from the perspective of
  /// the supplied camera.
  ///
  /// `dimensions` is the viewport size used to compute the camera's view
  /// transform; the supplied environment is the default IBL environment
  /// applied to materials that don't override it. The opaque render pass
  /// is opened immediately.
  SceneEncoder(
    gpu.RenderTarget renderTarget,
    this._camera,
    ui.Size dimensions,
    this._environment,
  ) {
    _cameraTransform = _camera.getViewTransform(dimensions);
    frustum = Frustum.matrix(_cameraTransform);
    _commandBuffer = gpu.gpuContext.createCommandBuffer();
    _transientsBuffer = gpu.gpuContext.createHostBuffer();

    // Begin the opaque render pass.
    _renderPass = _commandBuffer.createRenderPass(renderTarget);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setColorBlendEnable(false);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  }

  final Camera _camera;
  final Environment _environment;
  late final Matrix4 _cameraTransform;
  late final gpu.CommandBuffer _commandBuffer;
  late final gpu.HostBuffer _transientsBuffer;
  late final gpu.RenderPass _renderPass;
  final List<_TranslucentRecord> _translucentRecords = [];

  /// View frustum derived from the camera's view-projection matrix at
  /// the start of this frame. Used by [Node.render] for subtree-level
  /// culling.
  late final Frustum frustum;

  /// Reusable AABB owned by this encoder so the per-node cull check can
  /// transform a local AABB into world space without allocating a new
  /// [Aabb3] every frame, every node.
  final Aabb3 cullScratchAabb = Aabb3();

  /// Records a draw call for [geometry] with [material] at
  /// [worldTransform].
  ///
  /// Opaque draws are encoded immediately into the active render pass.
  /// Translucent draws (where [Material.isOpaque] returns `false`) are
  /// queued and re-emitted in [finish] after a back-to-front depth sort.
  void encode(Matrix4 worldTransform, Geometry geometry, Material material) {
    if (material.isOpaque()) {
      _encode(worldTransform, geometry, material);
      return;
    }
    _translucentRecords.add(
      _TranslucentRecord(worldTransform, geometry, material),
    );
  }

  void _encode(Matrix4 worldTransform, Geometry geometry, Material material) {
    _renderPass.clearBindings();
    var pipeline = gpu.gpuContext.createRenderPipeline(
      geometry.vertexShader,
      material.fragmentShader,
    );
    _renderPass.bindPipeline(pipeline);

    geometry.bind(
      _renderPass,
      _transientsBuffer,
      worldTransform,
      _cameraTransform,
      _camera.position,
    );
    material.bind(_renderPass, _transientsBuffer, _environment);
    _renderPass.draw();
  }

  /// Flushes the deferred translucent pass and submits the command
  /// buffer.
  ///
  /// Translucent records are sorted back-to-front by translation distance
  /// to the camera, then drawn with premultiplied source-over blending
  /// and depth writes disabled. After this call the encoder's command
  /// buffer is no longer usable.
  void finish() {
    _translucentRecords.sort((a, b) {
      var aDistance = a.worldTransform.getTranslation().distanceTo(
        _camera.position,
      );
      var bDistance = b.worldTransform.getTranslation().distanceTo(
        _camera.position,
      );
      return bDistance.compareTo(aDistance);
    });
    _renderPass.setDepthWriteEnable(false);
    _renderPass.setColorBlendEnable(true);
    // Additive source-over blending.
    // Note: Expects premultiplied alpha output from the fragment stage!
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
    for (var record in _translucentRecords) {
      _encode(record.worldTransform, record.geometry, record.material);
    }
    _translucentRecords.clear();
    _commandBuffer.submit();
    _transientsBuffer.reset();
  }
}
