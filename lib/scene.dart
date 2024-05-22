import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/mesh.dart';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/node.dart';
import 'package:flutter_scene/camera.dart';
import 'package:flutter_scene/surface.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/geometry/geometry.dart';

base class SceneEncoder {
  SceneEncoder(gpu.RenderTarget renderTarget, this._cameraTransform) {
    _commandBuffer = gpu.gpuContext.createCommandBuffer();
    _transientsBuffer = gpu.gpuContext.createHostBuffer();
    _renderPass = _commandBuffer.createRenderPass(renderTarget);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  }

  final Matrix4 _cameraTransform;
  late final gpu.CommandBuffer _commandBuffer;
  late final gpu.HostBuffer _transientsBuffer;
  late final gpu.RenderPass _renderPass;

  void encode(Matrix4 transform, Geometry geometry, Material material) {
    final mvp = _cameraTransform * transform.transposed();
    _renderPass.clearBindings();
    var pipeline = gpu.gpuContext
        .createRenderPipeline(geometry.vertexShader, material.fragmentShader);
    _renderPass.bindPipeline(pipeline);
    geometry.bind(_renderPass, _transientsBuffer, mvp);
    material.bind(_renderPass, _transientsBuffer);
    _renderPass.draw();
  }

  void finish() {
    _commandBuffer.submit();
  }
}

mixin SceneGraph {
  void add(Node child);
  void addMesh(Mesh mesh);
  void remove(Node child);
}

base class Scene implements SceneGraph {
  Scene() {
    root.registerAsRoot(this);
  }

  final Node root = Node();
  final Surface surface = Surface();

  @override
  void add(Node child) {
    root.add(child);
  }

  @override
  void addMesh(Mesh mesh) {
    final node = Node(mesh: mesh);
    add(node);
  }

  @override
  void remove(Node child) {
    root.remove(child);
  }

  void render(Camera camera, ui.Canvas canvas, {ui.Rect? viewport}) {
    final drawArea = viewport ?? canvas.getLocalClipBounds();
    if (drawArea.isEmpty) {
      return;
    }
    final gpu.RenderTarget renderTarget =
        surface.getNextRenderTarget(drawArea.size);

    final encoder =
        SceneEncoder(renderTarget, camera.getTransform(drawArea.size));
    root.render(encoder, Matrix4.identity());
    encoder.finish();

    final image = renderTarget.colorAttachments[0].texture.asImage();
    canvas.drawImage(image, drawArea.topLeft, ui.Paint());
  }
}
