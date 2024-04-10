import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/shaders.dart';

import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/generated/scene_impeller.fb_flatbuffers.dart'
    as fb;

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

  static Material fromFlatbuffer(
      fb.Material fbMaterial, List<gpu.Texture> textures) {
    if (fbMaterial.type == fb.MaterialType.kUnlit) {
      return UnlitMaterial.fromFlatbuffer(fbMaterial, textures);
    } else if (fbMaterial.type == fb.MaterialType.kPhysicallyBased) {
      throw Exception('PBR materials are not yet supported');
    } else {
      throw Exception('Unknown material type');
    }
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
  static UnlitMaterial fromFlatbuffer(
      fb.Material fbMaterial, List<gpu.Texture> textures) {
    if (fbMaterial.type != fb.MaterialType.kUnlit) {
      throw Exception('Cannot unpack unlit material from non-unlit material');
    }

    UnlitMaterial material = UnlitMaterial();

    if (fbMaterial.baseColorFactor != null) {
      material.baseColorFactor = ui.Color.fromARGB(
          (fbMaterial.baseColorFactor!.a * 255).toInt(),
          (fbMaterial.baseColorFactor!.r * 255).toInt(),
          (fbMaterial.baseColorFactor!.g * 255).toInt(),
          (fbMaterial.baseColorFactor!.b * 255).toInt());
    }

    if (fbMaterial.baseColorTexture >= 0 &&
        fbMaterial.baseColorTexture < textures.length) {
      material.baseColorTexture = textures[fbMaterial.baseColorTexture];
    }

    return material;
  }

  UnlitMaterial({gpu.Texture? colorTexture}) {
    setFragmentShader(baseShaderLibrary['UnlitFragment']!);
    baseColorTexture = colorTexture ?? Material.getPlaceholderTexture();
  }

  late gpu.Texture baseColorTexture;
  ui.Color baseColorFactor = const ui.Color(0xFFFFFFFF);
  double vertexColorWeight = 1.0;

  @override
  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer) {
    var fragInfo = Float32List.fromList([
      baseColorFactor.red / 256.0, baseColorFactor.green / 256.0,
      baseColorFactor.blue / 256.0, baseColorFactor.alpha / 256.0, // color
      vertexColorWeight, // vertex_color_weight
    ]);
    pass.bindUniform(fragmentShader.getUniformSlot("FragInfo"),
        transientsBuffer.emplace(fragInfo.buffer.asByteData()));
    pass.bindTexture(
        fragmentShader.getUniformSlot('base_color_texture'), baseColorTexture);
  }
}
