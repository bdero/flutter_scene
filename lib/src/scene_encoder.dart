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

base class SceneEncoder {
  SceneEncoder(
    gpu.RenderTarget renderTarget,
    this._camera,
    ui.Size dimensions,
    this._environment,
  ) {
    _cameraTransform = _camera.getViewTransform(dimensions);
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
