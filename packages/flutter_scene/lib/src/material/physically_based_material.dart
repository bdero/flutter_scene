import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/shaders.dart';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:vector_math/vector_math.dart';

/// A glTF-style metallic-roughness physically based material with
/// image-based lighting.
///
/// Wraps the `StandardFragment` shader and exposes the parameters from
/// the [glTF 2.0 PBR metallic-roughness model](https://github.com/KhronosGroup/glTF/tree/main/specification/2.0#materials):
///
///  * Albedo: [baseColorFactor], [baseColorTexture] (multiplied with the
///    optional per-vertex color, weighted by [vertexColorWeight]).
///  * Metallic-roughness: [metallicFactor], [roughnessFactor],
///    [metallicRoughnessTexture] (B = metallic, G = roughness).
///  * Normal: [normalTexture] with [normalScale].
///  * Emissive: [emissiveFactor], [emissiveTexture].
///  * Occlusion: [occlusionTexture] with [occlusionStrength].
///  * Lighting: [environment] (overrides the [Scene]-wide environment
///    when set).
///
/// Translucency is determined by [baseColorFactor]'s alpha component;
/// the material is treated as opaque when alpha is exactly `1`.
class PhysicallyBasedMaterial extends Material {
  /// Builds a [PhysicallyBasedMaterial] from a flatbuffer material
  /// description, resolving texture indices against [textures].
  ///
  /// Throws if [fbMaterial] is not a PBR material.
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

  /// Creates a PBR material with the given textures.
  ///
  /// All textures are optional; missing textures are replaced with
  /// neutral placeholders at draw time. Per-channel scaling factors
  /// (e.g. [metallicFactor], [roughnessFactor]) default to neutral and
  /// can be tweaked after construction.
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

  /// The albedo (base color) texture, sampled in linear space and
  /// multiplied by [baseColorFactor]. Defaults to white when null.
  gpu.Texture? baseColorTexture;

  /// Linear RGBA tint multiplied with [baseColorTexture]. Alpha controls
  /// translucency: values below `1` push the material into the depth-
  /// sorted translucent pass.
  Vector4 baseColorFactor = Colors.white;

  /// How strongly per-vertex colors influence the final albedo. `0`
  /// disables vertex color contribution; `1` (the default) fully
  /// applies it.
  double vertexColorWeight = 1.0;

  /// The combined metallic-roughness texture (B = metallic,
  /// G = roughness). Defaults to white when null.
  gpu.Texture? metallicRoughnessTexture;

  /// Scalar multiplier applied to the metallic channel. `0` is fully
  /// dielectric, `1` is fully metallic.
  double metallicFactor = 1.0;

  /// Scalar multiplier applied to the roughness channel. `0` is a
  /// perfect mirror, `1` is fully diffuse.
  double roughnessFactor = 1.0;

  /// Tangent-space normal map. Defaults to a flat normal when null.
  gpu.Texture? normalTexture;

  /// Strength of [normalTexture]'s perturbation. `1` is the unmodified
  /// map.
  double normalScale = 1.0;

  /// Optional emissive texture. Defaults to white when null and is
  /// gated by [emissiveFactor].
  gpu.Texture? emissiveTexture;

  /// Linear RGBA emissive tint. Alpha is unused; the default
  /// `Vector4.zero()` disables emission.
  Vector4 emissiveFactor = Vector4.zero();

  /// Optional ambient-occlusion texture (R channel). Defaults to white
  /// when null.
  gpu.Texture? occlusionTexture;

  /// Strength of [occlusionTexture]'s effect. `0` ignores the map; `1`
  /// applies it fully.
  double occlusionStrength = 1.0;

  /// Per-material image-based-lighting environment, overriding the
  /// scene-wide `Scene.environment` when set.
  EnvironmentMap? environment;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);

    final EnvironmentMap env = environment ?? lighting.environmentMap;
    final DirectionalLight? light = lighting.directionalLight;
    final shadowMatrix =
        lighting.shadowMap == null ? null : lighting.lightSpaceMatrix;

    // FragInfo std140 layout (320 bytes / 80 floats):
    //   [0..3]   vec4  color
    //   [4..7]   vec4  emissive_factor
    //   [8..43]  vec4  diffuse_sh0..8 (xyz used, w padding)
    //   [44..47] vec4  directional_light_direction (xyz used)
    //   [48..51] vec4  directional_light_color (rgb = color * intensity)
    //   [52..67] mat4  light_space_matrix (column-major)
    //   [68]     float vertex_color_weight
    //   [69]     float metallic_factor
    //   [70]     float roughness_factor
    //   [71]     float has_normal_map
    //   [72]     float normal_scale
    //   [73]     float occlusion_strength
    //   [74]     float environment_intensity
    //   [75]     float has_directional_light
    //   [76]     float casts_shadow
    //   [77]     float shadow_bias
    //   [78]     float shadow_normal_bias
    //   [79]     float shadow_texel_size
    final fragInfo = Float32List(80);
    fragInfo[0] = baseColorFactor.r;
    fragInfo[1] = baseColorFactor.g;
    fragInfo[2] = baseColorFactor.b;
    fragInfo[3] = baseColorFactor.a;
    fragInfo[4] = emissiveFactor.r;
    fragInfo[5] = emissiveFactor.g;
    fragInfo[6] = emissiveFactor.b;
    fragInfo[7] = emissiveFactor.a;
    final shCoefficients = env.diffuseSphericalHarmonics;
    for (var i = 0; i < shCoefficients.length; i++) {
      fragInfo[8 + i * 4] = shCoefficients[i].x;
      fragInfo[9 + i * 4] = shCoefficients[i].y;
      fragInfo[10 + i * 4] = shCoefficients[i].z;
    }
    if (light != null) {
      fragInfo[44] = light.direction.x;
      fragInfo[45] = light.direction.y;
      fragInfo[46] = light.direction.z;
      fragInfo[48] = light.color.x * light.intensity;
      fragInfo[49] = light.color.y * light.intensity;
      fragInfo[50] = light.color.z * light.intensity;
    }
    if (shadowMatrix != null) {
      fragInfo.setRange(52, 68, shadowMatrix.storage);
    }
    fragInfo[68] = vertexColorWeight;
    fragInfo[69] = metallicFactor;
    fragInfo[70] = roughnessFactor;
    fragInfo[71] = normalTexture != null ? 1.0 : 0.0;
    fragInfo[72] = normalScale;
    fragInfo[73] = occlusionStrength;
    fragInfo[74] = lighting.environmentIntensity;
    fragInfo[75] = light != null ? 1.0 : 0.0;
    fragInfo[76] = shadowMatrix != null ? 1.0 : 0.0;
    fragInfo[77] = light?.shadowDepthBias ?? 0.0;
    fragInfo[78] = light?.shadowNormalBias ?? 0.0;
    fragInfo[79] = light == null ? 0.0 : 1.0 / light.shadowMapResolution;
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
    // Specular IBL atlas: horizontal repeat (the panorama wraps in
    // longitude), vertical clamp (it's a stack of roughness bands;
    // wrapping V would bleed between them).
    pass.bindTexture(
      fragmentShader.getUniformSlot('prefiltered_radiance'),
      env.prefilteredRadianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
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
    // Nearest + clamp (the SamplerOptions defaults): the shader does a
    // manual PCF comparison, so we don't want linear-filtered depths, and
    // out-of-bounds PCF taps should clamp rather than wrap. When there's
    // no shadow this frame, the white placeholder reads as depth 1.0
    // (always lit) and casts_shadow is 0 anyway.
    pass.bindTexture(
      fragmentShader.getUniformSlot('shadow_map'),
      Material.whitePlaceholder(lighting.shadowMap),
      sampler: gpu.SamplerOptions(),
    );
  }

  @override
  bool isOpaque() {
    return baseColorFactor.a == 1;
  }
}
