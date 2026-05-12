import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:vector_math/vector_math.dart';

/// A material that draws geometry with a flat color or texture, ignoring
/// scene lighting.
///
/// Useful for UI overlays, debug visualization, or stylized rendering.
/// The final color is `baseColorFactor * baseColorTexture`, optionally
/// blended with the per-vertex color via [vertexColorWeight].
///
/// Wraps the `UnlitFragment` shader from [baseShaderLibrary].
class UnlitMaterial extends Material {
  /// Builds an [UnlitMaterial] from a flatbuffer material description,
  /// resolving texture indices against [textures].
  ///
  /// Throws if [fbMaterial] is not an unlit material.
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

  /// Creates an [UnlitMaterial], optionally textured.
  ///
  /// When [colorTexture] is null a 1×1 white placeholder is used so the
  /// final color reduces to [baseColorFactor].
  UnlitMaterial({gpu.Texture? colorTexture}) {
    setFragmentShader(baseShaderLibrary['UnlitFragment']!);
    baseColorTexture = Material.whitePlaceholder(colorTexture);
  }

  /// The base color texture, sampled and multiplied by [baseColorFactor].
  ///
  /// Always non-null after construction; pass `null` to the constructor
  /// to fall back to a 1×1 white placeholder.
  late gpu.Texture baseColorTexture;

  /// Linear RGBA tint multiplied with [baseColorTexture].
  Vector4 baseColorFactor = Colors.white;

  /// How strongly per-vertex colors influence the final color. `0`
  /// disables vertex color contribution; `1` (the default) fully
  /// applies it.
  double vertexColorWeight = 1.0;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);

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
