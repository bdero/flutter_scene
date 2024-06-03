import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/material/environment.dart';
import 'package:flutter_scene/material/material.dart';
import 'package:flutter_scene/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;

class MeshStandardMaterial extends Material {
  static MeshStandardMaterial fromFlatbuffer(
      fb.Material fbMaterial, List<gpu.Texture> textures) {
    if (fbMaterial.type != fb.MaterialType.kPhysicallyBased) {
      throw Exception('Cannot unpack PBR material from non-PBR material');
    }

    MeshStandardMaterial material = MeshStandardMaterial();

    // Base color.

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

    // Metallic-roughness.

    material.metallicFactor = fbMaterial.metallicFactor;
    material.roughnessFactor = fbMaterial.roughnessFactor;

    debugPrint(
        'Metallic texture index: ${fbMaterial.metallicRoughnessTexture}');
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
      material.emissiveFactor = ui.Color.fromARGB(
          255,
          (fbMaterial.emissiveFactor!.x * 255).toInt(),
          (fbMaterial.emissiveFactor!.y * 255).toInt(),
          (fbMaterial.emissiveFactor!.z * 255).toInt());
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

  MeshStandardMaterial(
      {this.baseColorTexture,
      this.metallicRoughnessTexture,
      this.normalTexture,
      this.emissiveTexture,
      this.occlusionTexture,
      this.environment}) {
    setFragmentShader(baseShaderLibrary['StandardFragment']!);
  }

  gpu.Texture? baseColorTexture;
  ui.Color baseColorFactor = const ui.Color(0xFFFFFFFF);
  double vertexColorWeight = 1.0;

  gpu.Texture? metallicRoughnessTexture;
  double metallicFactor = 1.0;
  double roughnessFactor = 1.0;

  gpu.Texture? normalTexture;
  double normalScale = 1.0;

  gpu.Texture? emissiveTexture;
  ui.Color emissiveFactor = const ui.Color(0x00000000);

  gpu.Texture? occlusionTexture;
  double occlusionStrength = 1.0;

  Environment? environment;

  @override
  void bind(gpu.RenderPass pass, gpu.HostBuffer transientsBuffer,
      Environment environment) {
    Environment env = this.environment ?? environment;

    var fragInfo = Float32List.fromList([
      baseColorFactor.red / 256.0, baseColorFactor.green / 256.0,
      baseColorFactor.blue / 256.0, baseColorFactor.alpha / 256.0, // color
      emissiveFactor.red / 256.0, emissiveFactor.green / 256.0,
      emissiveFactor.blue / 256.0,
      emissiveFactor.alpha / 256.0, // emissive_factor
      vertexColorWeight, // vertex_color_weight
      environment.exposure, // exposure
      metallicFactor, // metallic
      roughnessFactor, // roughness
      normalTexture != null ? 1.0 : 0.0, // has_normal_map
      normalScale, // normal_scale
      occlusionStrength, // occlusion_strength
      environment.intensity, // environment_intensity
    ]);
    pass.bindUniform(fragmentShader.getUniformSlot("FragInfo"),
        transientsBuffer.emplace(ByteData.sublistView(fragInfo)));
    pass.bindTexture(fragmentShader.getUniformSlot('base_color_texture'),
        Material.whitePlaceholder(baseColorTexture),
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
    pass.bindTexture(fragmentShader.getUniformSlot('emissive_texture'),
        Material.whitePlaceholder(emissiveTexture),
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
    pass.bindTexture(
        fragmentShader.getUniformSlot('metallic_roughness_texture'),
        Material.whitePlaceholder(metallicRoughnessTexture),
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
    pass.bindTexture(fragmentShader.getUniformSlot('normal_texture'),
        Material.normalPlaceholder(normalTexture),
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
    pass.bindTexture(fragmentShader.getUniformSlot('occlusion_texture'),
        Material.whitePlaceholder(occlusionTexture),
        sampler: gpu.SamplerOptions(
            widthAddressMode: gpu.SamplerAddressMode.repeat,
            heightAddressMode: gpu.SamplerAddressMode.repeat));
    pass.bindTexture(fragmentShader.getUniformSlot('radiance_texture'),
        env.environmentMap.radianceTexture,
        sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
            heightAddressMode: gpu.SamplerAddressMode.clampToEdge));
    pass.bindTexture(fragmentShader.getUniformSlot('irradiance_texture'),
        env.environmentMap.irradianceTexture,
        sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
            heightAddressMode: gpu.SamplerAddressMode.clampToEdge));
    pass.bindTexture(
        fragmentShader.getUniformSlot('brdf_lut'), Material.getBrdfLutTexture(),
        sampler: gpu.SamplerOptions(
            minFilter: gpu.MinMagFilter.linear,
            magFilter: gpu.MinMagFilter.linear,
            widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
            heightAddressMode: gpu.SamplerAddressMode.clampToEdge));
  }

  @override
  bool isOpaque() {
    return baseColorFactor.alpha == 255;
  }
}
