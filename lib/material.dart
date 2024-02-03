import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/shaders.dart';

abstract class Material {
  static gpu.Texture? _placeholderTexture;

  static gpu.Texture getPlaceholderTexture() {
    if (_placeholderTexture != null) {
      return _placeholderTexture!;
    }
    _placeholderTexture =
        gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1);
    if (_placeholderTexture == null) {
      throw Exception("Failed to create placeholder texture.");
    }
    _placeholderTexture!
        .overwrite(Uint32List.fromList(<int>[0xFFFFFFFF]).buffer.asByteData());
    return _placeholderTexture!;
  }

  late gpu.Shader _vertexShader;
  late gpu.Shader _fragmentShader;
  gpu.RenderPipeline? _pipeline;

  void setShaders(gpu.Shader vertexShader, gpu.Shader fragmentShader) {
    _vertexShader = vertexShader;
    _fragmentShader = fragmentShader;
    _pipeline = null;
  }

  void bind(
      gpu.RenderPass pass, gpu.HostBuffer transientsBuffer, vm.Matrix4 mvp) {
    _pipeline ??=
        gpu.gpuContext.createRenderPipeline(_vertexShader, _fragmentShader);
    pass.bindPipeline(_pipeline!);

    final mvpSlot = _vertexShader.getUniformSlot('VertexInfo');
    final mvpView = transientsBuffer.emplace(mvp.storage.buffer.asByteData());
    pass.bindUniform(mvpSlot, mvpView);
  }
}

class UnlitMaterial extends Material {
  UnlitMaterial({gpu.Texture? colorTexture}) {
    setShaders(baseShaderLibrary['TextureVertex']!,
        baseShaderLibrary['TextureFragment']!);
    setColorTexture(colorTexture ?? Material.getPlaceholderTexture());
  }

  late gpu.Texture _color;

  setColorTexture(gpu.Texture color) {
    _color = color;
  }

  @override
  void bind(
      gpu.RenderPass pass, gpu.HostBuffer transientsBuffer, vm.Matrix4 mvp) {
    pass.bindTexture(_fragmentShader.getUniformSlot('tex'), _color!);
    super.bind(pass, transientsBuffer, mvp);
  }
}
