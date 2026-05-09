import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:vector_math/vector_math.dart';

class UnlitMaterial extends Material {
  static UnlitMaterial fromFlatbuffer(
    fb.Material fbMaterial,
    List<gpu.Texture> textures,
  ) {
    if (fbMaterial.type != fb.MaterialType.kUnlit) {
      throw Exception('Cannot unpack unlit material from non-unlit material');
    }

    UnlitMaterial material = UnlitMaterial();

    if (fbMaterial.baseColorFactor != null) {
      material.baseColorFactor = Vector4(
        fbMaterial.baseColorFactor!.r,
        fbMaterial.baseColorFactor!.g,
        fbMaterial.baseColorFactor!.b,
        fbMaterial.baseColorFactor!.a,
      );
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
  Vector4 baseColorFactor = Colors.white;
  double vertexColorWeight = 1.0;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Environment environment,
  ) {
    super.bind(pass, transientsBuffer, environment);

    var fragInfo = Float32List.fromList([
      baseColorFactor.r, baseColorFactor.g,
      baseColorFactor.b, baseColorFactor.a, // color
      vertexColorWeight, // vertex_color_weight
    ]);
    pass.bindUniform(
      fragmentShader.getUniformSlot("FragInfo"),
      transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('base_color_texture'),
      baseColorTexture,
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
  }
}
