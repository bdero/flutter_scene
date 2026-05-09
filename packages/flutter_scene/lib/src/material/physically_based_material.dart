import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:vector_math/vector_math.dart';

class PhysicallyBasedMaterial extends Material {
  static PhysicallyBasedMaterial fromFlatbuffer(
    fb.Material fbMaterial,
    List<gpu.Texture> textures,
  ) {
    if (fbMaterial.type != fb.MaterialType.kPhysicallyBased) {
      throw Exception('Cannot unpack PBR material from non-PBR material');
    }

    PhysicallyBasedMaterial material = PhysicallyBasedMaterial();

    // Base color.

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

    // Metallic-roughness.

    material.metallicFactor = fbMaterial.metallicFactor;
    material.roughnessFactor = fbMaterial.roughnessFactor;

    debugPrint('Total texture count: ${textures.length}');
    if (fbMaterial.metallicRoughnessTexture >= 0 &&
        fbMaterial.metallicRoughnessTexture < textures.length) {
      material.metallicRoughnessTexture =
          textures[fbMaterial.metallicRoughnessTexture];
    }

    // Normal.

    if (fbMaterial.normalTexture >= 0 &&
        fbMaterial.normalTexture < textures.length) {
      material.normalTexture = textures[fbMaterial.normalTexture];
    }

    material.normalScale = fbMaterial.normalScale;

    // Emissive.

    if (fbMaterial.emissiveFactor != null) {
      material.emissiveFactor = Vector4(
        fbMaterial.emissiveFactor!.x,
        fbMaterial.emissiveFactor!.y,
        fbMaterial.emissiveFactor!.z,
        1,
      );
    }

    if (fbMaterial.emissiveTexture >= 0 &&
        fbMaterial.emissiveTexture < textures.length) {
      material.emissiveTexture = textures[fbMaterial.emissiveTexture];
    }

    // Occlusion.

    material.occlusionStrength = fbMaterial.occlusionStrength;

    if (fbMaterial.occlusionTexture >= 0 &&
        fbMaterial.occlusionTexture < textures.length) {
      material.occlusionTexture = textures[fbMaterial.occlusionTexture];
    }

    return material;
  }

  PhysicallyBasedMaterial({
    this.baseColorTexture,
    this.metallicRoughnessTexture,
    this.normalTexture,
    this.emissiveTexture,
    this.occlusionTexture,
    this.environment,
  }) {
    setFragmentShader(baseShaderLibrary['StandardFragment']!);
  }

  gpu.Texture? baseColorTexture;
  Vector4 baseColorFactor = Colors.white;
  double vertexColorWeight = 1.0;

  gpu.Texture? metallicRoughnessTexture;
  double metallicFactor = 1.0;
  double roughnessFactor = 1.0;

  gpu.Texture? normalTexture;
  double normalScale = 1.0;

  gpu.Texture? emissiveTexture;
  Vector4 emissiveFactor = Vector4.zero();

  gpu.Texture? occlusionTexture;
  double occlusionStrength = 1.0;

  Environment? environment;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Environment environment,
  ) {
    super.bind(pass, transientsBuffer, environment);

    Environment env = this.environment ?? environment;

    var fragInfo = Float32List.fromList([
      baseColorFactor.r, baseColorFactor.g,
      baseColorFactor.b, baseColorFactor.a, // color
      emissiveFactor.r, emissiveFactor.g,
      emissiveFactor.b,
      emissiveFactor.a, // emissive_factor
      vertexColorWeight, // vertex_color_weight
      environment.exposure, // exposure
      metallicFactor, // metallic
      roughnessFactor, // roughness
      normalTexture != null ? 1.0 : 0.0, // has_normal_map
      normalScale, // normal_scale
      occlusionStrength, // occlusion_strength
      environment.intensity, // environment_intensity
    ]);
    pass.bindUniform(
      fragmentShader.getUniformSlot("FragInfo"),
      transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('base_color_texture'),
      Material.whitePlaceholder(baseColorTexture),
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('emissive_texture'),
      Material.whitePlaceholder(emissiveTexture),
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('metallic_roughness_texture'),
      Material.whitePlaceholder(metallicRoughnessTexture),
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('normal_texture'),
      Material.normalPlaceholder(normalTexture),
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('occlusion_texture'),
      Material.whitePlaceholder(occlusionTexture),
      sampler: gpu.SamplerOptions(
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('radiance_texture'),
      env.environmentMap.radianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('irradiance_texture'),
      env.environmentMap.irradianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    pass.bindTexture(
      fragmentShader.getUniformSlot('brdf_lut'),
      Material.getBrdfLutTexture(),
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }

  @override
  bool isOpaque() {
    return baseColorFactor.a == 1;
  }
}
