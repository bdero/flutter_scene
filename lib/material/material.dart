import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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

  gpu.Shader? _fragmentShader;
  gpu.Shader get fragmentShader {
    if (_fragmentShader == null) {
      throw Exception('Fragment shader has not been set');
    }
    return _fragmentShader!;
  }

  void setFragmentShader(gpu.Shader shader) {
    _fragmentShader = shader;
  }

  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer);
}

class UnlitMaterial extends Material {
  UnlitMaterial({gpu.Texture? colorTexture}) {
    setFragmentShader(baseShaderLibrary['UnlitFragment']!);
    setColorTexture(colorTexture ?? Material.getPlaceholderTexture());
  }

  late gpu.Texture _baseColorTexture;

  setColorTexture(gpu.Texture color) {
    _baseColorTexture = color;
  }

  @override
  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer) {
    var fragInfo = Float32List.fromList([
      1, 1, 1, 1, // color
      1, // vertex_color_weight
    ]);
    pass.bindUniform(fragmentShader.getUniformSlot("FragInfo"),
        transientsBuffer.emplace(fragInfo.buffer.asByteData()));
    pass.bindTexture(
        fragmentShader.getUniformSlot('base_color_texture'), _baseColorTexture);
  }
}
