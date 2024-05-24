import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;

import 'package:flutter_scene/material/mesh_unlit_material.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

abstract class Material {
  static gpu.Texture? _placeholderTexture;

  static gpu.Texture getPlaceholderTexture() {
    if (_placeholderTexture != null) {
      return _placeholderTexture!;
    }
    _placeholderTexture =
        gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1);
    if (_placeholderTexture == null) {
      throw Exception('Failed to create placeholder texture.');
    }
    _placeholderTexture!
        .overwrite(Uint32List.fromList(<int>[0xFFFFFFFF]).buffer.asByteData());
    return _placeholderTexture!;
  }

  static Material fromFlatbuffer(
      fb.Material fbMaterial, List<gpu.Texture> textures) {
    if (fbMaterial.type == fb.MaterialType.kUnlit) {
      return MeshUnlitMaterial.fromFlatbuffer(fbMaterial, textures);
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
