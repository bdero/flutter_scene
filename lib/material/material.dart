import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/asset_helpers.dart';

import 'package:flutter_scene/material/environment.dart';
import 'package:flutter_scene/material/mesh_standard_material.dart';
import 'package:flutter_scene/material/mesh_unlit_material.dart';
import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

abstract class Material {
  static gpu.Texture? _whitePlaceholderTexture;

  static gpu.Texture getWhitePlaceholderTexture() {
    if (_whitePlaceholderTexture != null) {
      return _whitePlaceholderTexture!;
    }
    _whitePlaceholderTexture =
        gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1);
    if (_whitePlaceholderTexture == null) {
      throw Exception('Failed to create white placeholder texture.');
    }
    _whitePlaceholderTexture!
        .overwrite(Uint32List.fromList(<int>[0xFFFF7F7F]).buffer.asByteData());
    return _whitePlaceholderTexture!;
  }

  static gpu.Texture whitePlaceholder(gpu.Texture? texture) {
    return texture ?? getWhitePlaceholderTexture();
  }

  static gpu.Texture? _normalPlaceholderTexture;

  static gpu.Texture getNormalPlaceholderTexture() {
    if (_normalPlaceholderTexture != null) {
      return _normalPlaceholderTexture!;
    }
    _normalPlaceholderTexture =
        gpu.gpuContext.createTexture(gpu.StorageMode.hostVisible, 1, 1);
    if (_normalPlaceholderTexture == null) {
      throw Exception('Failed to create normal placeholder texture.');
    }
    _normalPlaceholderTexture!
        .overwrite(Uint32List.fromList(<int>[0xFFFF7574]).buffer.asByteData());
    return _normalPlaceholderTexture!;
  }

  static gpu.Texture normalPlaceholder(gpu.Texture? texture) {
    return texture ?? getNormalPlaceholderTexture();
  }

  static gpu.Texture? _brdfLutTexture;

  static gpu.Texture getBrdfLutTexture() {
    if (_brdfLutTexture == null) {
      throw Exception('BRDF LUT texture has not been initialized.');
    }
    return _brdfLutTexture!;
  }

  static Future<void> initializeStaticResources() {
    return gpuTextureFromAsset('packages/flutter_scene/assets/ibl_brdf_lut.png')
        .then((gpu.Texture value) {
      _brdfLutTexture = value;
    });
  }

  static Material fromFlatbuffer(
      fb.Material fbMaterial, List<gpu.Texture> textures) {
    switch (fbMaterial.type) {
      case fb.MaterialType.kUnlit:
        return MeshUnlitMaterial.fromFlatbuffer(fbMaterial, textures);
      case fb.MaterialType.kPhysicallyBased:
        return MeshStandardMaterial.fromFlatbuffer(fbMaterial, textures);
      default:
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

  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer,
      Environment environment);

  bool isOpaque() {
    return true;
  }
}
