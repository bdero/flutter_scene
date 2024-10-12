import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/material/environment.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

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
    baseColorTexture = Material.whitePlaceholder(colorTexture);
  }

  late gpu.Texture baseColorTexture;
  ui.Color baseColorFactor = const ui.Color(0xFFFFFFFF);
  double vertexColorWeight = 1.0;

  @override
  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer,
      Environment environment) {
    super.bind(pass, transientsBuffer, environment);

    var fragInfo = Float32List.fromList([
      baseColorFactor.red / 256.0, baseColorFactor.green / 256.0,
      baseColorFactor.blue / 256.0, baseColorFactor.alpha / 256.0, // color
      vertexColorWeight, // vertex_color_weight
    ]);
    pass.bindUniform(fragmentShader.getUniformSlot("FragInfo"),
        transientsBuffer.emplace(ByteData.sublistView(fragInfo)));
    pass.bindTexture(
        fragmentShader.getUniformSlot('base_color_texture'), baseColorTexture,
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
  }
}
