import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/camera.dart';
import 'package:flutter_scene/geometry/geometry.dart';
import 'package:flutter_scene/material/environment.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/mesh.dart';
import 'package:flutter_scene/node.dart';
import 'package:flutter_scene/surface.dart';

base class SceneEncoder {
  SceneEncoder(gpu.RenderTarget renderTarget, this._camera, ui.Size dimensions,
      this._environment) {
    _cameraTransform = _camera.getViewTransform(dimensions);
    _commandBuffer = gpu.gpuContext.createCommandBuffer();
    _transientsBuffer = gpu.gpuContext.createHostBuffer();
    _renderPass = _commandBuffer.createRenderPass(renderTarget);
    _renderPass.setDepthWriteEnable(true);
    _renderPass.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
  }

  final Camera _camera;
  final Environment _environment;
  late final Matrix4 _cameraTransform;
  late final gpu.CommandBuffer _commandBuffer;
  late final gpu.HostBuffer _transientsBuffer;
  late final gpu.RenderPass _renderPass;

  void encode(Matrix4 transform, Geometry geometry, Material material) {
    _renderPass.clearBindings();
    var pipeline = gpu.gpuContext
        .createRenderPipeline(geometry.vertexShader, material.fragmentShader);
    _renderPass.bindPipeline(pipeline);

    // TODO(bdero): Fix transforms so that we don't need to transpose them...
    geometry.bind(_renderPass, _transientsBuffer, transform.transposed(),
        _cameraTransform, _camera.position);
    material.bind(_renderPass, _transientsBuffer, _environment);
    _renderPass.draw();
  }

  void finish() {
    _commandBuffer.submit();
  }
}

mixin SceneGraph {
  /// Add a child node.
  void add(Node child);

  /// Add a mesh as a child node.
  void addMesh(Mesh mesh);

  /// Remove a child node.
  void remove(Node child);

  /// Remove all children nodes.
  void removeAll();
}

base class Scene implements SceneGraph {
  Scene() {
    initializeStaticResources();
    root.registerAsRoot(this);
  }

  static Future<void>? _initializeStaticResources;
  static bool _readyToRender = false;

  static Future<void> initializeStaticResources() {
    if (_initializeStaticResources != null) {
      return _initializeStaticResources!;
    }
    _initializeStaticResources =
        Material.initializeStaticResources().onError((e, stacktrace) {
      print('Failed to initialize static Flutter Scene resources: $e');
      _initializeStaticResources = null;
    }).then((_) {
      _readyToRender = true;
    });
    return _initializeStaticResources!;
  }

  final Node root = Node();
  final Surface surface = Surface();

  final Environment environment = Environment();

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

  @override
  void removeAll() {
    root.removeAll();
  }

  void render(Camera camera, ui.Canvas canvas, {ui.Rect? viewport}) {
    if (!_readyToRender) {
      debugPrint('Flutter Scene is not ready to render. Skipping frame.');
      debugPrint(
          'You may wait on the Future returned by Scene.initializeStaticResources() before rendering.');
      return;
    }

    final drawArea = viewport ?? canvas.getLocalClipBounds();
    if (drawArea.isEmpty) {
      return;
    }
    final gpu.RenderTarget renderTarget =
        surface.getNextRenderTarget(drawArea.size);

    final encoder =
        SceneEncoder(renderTarget, camera, drawArea.size, environment);
    root.render(encoder, Matrix4.identity());
    encoder.finish();

    final image = renderTarget.colorAttachments[0].texture.asImage();
    canvas.drawImage(image, drawArea.topLeft, ui.Paint());
  }
}
