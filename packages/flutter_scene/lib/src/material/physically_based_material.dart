import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/engine_lighting.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

import 'package:vector_math/vector_math.dart';

/// How a [PhysicallyBasedMaterial]'s alpha channel is interpreted,
/// matching glTF's `alphaMode`.
/// {@category Materials}
enum AlphaMode {
  /// Alpha is ignored; the material renders fully opaque.
  opaque,

  /// Alpha-tested: a fragment whose alpha is below
  /// [PhysicallyBasedMaterial.alphaCutoff] is discarded and the rest
  /// render fully opaque. Used for cut-out foliage and similar.
  mask,

  /// Alpha-blended: drawn in the depth-sorted translucent pass with
  /// source-over blending.
  blend,
}

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
/// {@category Materials}
class PhysicallyBasedMaterial extends Material {
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
    setFragmentShaderName('StandardFragment');
  }

  /// The raw slot sources, for serialization. Same values as the public slot
  /// fields ([baseColorTexture] and friends).
  @internal
  TextureSource? get baseColorTextureSource => baseColorTexture;
  @internal
  TextureSource? get metallicRoughnessTextureSource => metallicRoughnessTexture;
  @internal
  TextureSource? get normalTextureSource => normalTexture;
  @internal
  TextureSource? get emissiveTextureSource => emissiveTexture;
  @internal
  TextureSource? get occlusionTextureSource => occlusionTexture;

  /// The albedo (base color) texture, sampled in linear space and
  /// multiplied by [baseColorFactor]. Defaults to white when null.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? baseColorTexture;

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
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? metallicRoughnessTexture;

  /// Scalar multiplier applied to the metallic channel. `0` is fully
  /// dielectric, `1` is fully metallic.
  double metallicFactor = 1.0;

  /// Scalar multiplier applied to the roughness channel. `0` is a
  /// perfect mirror, `1` is fully diffuse.
  double roughnessFactor = 1.0;

  /// Tangent-space normal map. Defaults to a flat normal when null.
  ///
  /// Accepts a [Texture2D] (usually with [TextureContent.normal]) or a
  /// `RenderTexture` (sampled live).
  TextureSource? normalTexture;

  /// Strength of [normalTexture]'s perturbation. `1` is the unmodified
  /// map.
  double normalScale = 1.0;

  /// Optional emissive texture. Defaults to white when null and is
  /// gated by [emissiveFactor].
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? emissiveTexture;

  /// Linear RGBA emissive tint. Alpha is unused; the default
  /// `Vector4.zero()` disables emission.
  Vector4 emissiveFactor = Vector4.zero();

  /// Optional ambient-occlusion texture (R channel). Defaults to white
  /// when null.
  ///
  /// Accepts a [Texture2D] or a `RenderTexture` (sampled live).
  TextureSource? occlusionTexture;

  /// Strength of [occlusionTexture]'s effect. `0` ignores the map; `1`
  /// applies it fully.
  double occlusionStrength = 1.0;

  /// Per-material image-based-lighting environment, overriding the
  /// scene-wide `Scene.environment` when set.
  EnvironmentMap? environment;

  /// How the material's alpha is interpreted; see [AlphaMode].
  ///
  /// [AlphaMode.blend] always routes the material through the
  /// translucent pass regardless of [baseColorFactor]'s alpha.
  AlphaMode alphaMode = AlphaMode.opaque;

  /// Alpha-test threshold used when [alphaMode] is [AlphaMode.mask]:
  /// fragments whose alpha falls below this are discarded.
  double alphaCutoff = 0.5;

  /// Strength of geometric specular antialiasing.
  ///
  /// A normal map or high-curvature surface carries more normal detail than a
  /// pixel can resolve, which the specular highlight turns into shimmer as the
  /// camera or surface moves. This estimates that sub-pixel normal variation
  /// from screen-space derivatives and widens the effective roughness to
  /// suppress it (Kaplanyan/Tokuyoshi). `0` disables the effect; the default
  /// (`0.15`) matches the common recommendation.
  double specularAntiAliasingVariance = 0.15;

  /// Upper bound on the extra roughness [specularAntiAliasingVariance] may add,
  /// in the squared-roughness domain. Caps the effect so strongly varying
  /// normals cannot over-roughen a surface. Default `0.2`.
  double specularAntiAliasingThreshold = 0.2;

  @override
  void bind(
    gpu.RenderPass pass,
    gpu.HostBuffer transientsBuffer,
    Lighting lighting,
  ) {
    super.bind(pass, transientsBuffer, lighting);

    final EnvironmentMap env = environment ?? lighting.environmentMap;

    // FragInfo std140 layout (624 bytes / 156 floats). EngineLightingUniforms
    // packs the shared engine lighting, image-based-lighting, and shadow
    // fields (identical for every lit material); this material fills only its
    // own, disjoint fields:
    //   [0..3]    vec4  color
    //   [4..7]    vec4  emissive_factor
    //   [120]     float vertex_color_weight
    //   [121]     float metallic_factor
    //   [122]     float roughness_factor
    //   [123]     float has_normal_map
    //   [124]     float normal_scale
    //   [125]     float occlusion_strength
    //   [132]     float alpha_mode (0 opaque, 1 mask, 2 blend)
    //   [133]     float alpha_cutoff
    //   [138]     float specular_aa_variance
    //   [139]     float specular_aa_threshold
    final fragInfo = Float32List(EngineLightingUniforms.fragInfoFloatCount);
    EngineLightingUniforms.packInto(fragInfo, lighting, env);
    fragInfo[0] = baseColorFactor.r;
    fragInfo[1] = baseColorFactor.g;
    fragInfo[2] = baseColorFactor.b;
    fragInfo[3] = baseColorFactor.a;
    fragInfo[4] = emissiveFactor.r;
    fragInfo[5] = emissiveFactor.g;
    fragInfo[6] = emissiveFactor.b;
    fragInfo[7] = emissiveFactor.a;
    fragInfo[120] = vertexColorWeight;
    fragInfo[121] = metallicFactor;
    fragInfo[122] = roughnessFactor;
    fragInfo[123] = normalTexture != null ? 1.0 : 0.0;
    fragInfo[124] = normalScale;
    fragInfo[125] = occlusionStrength;
    fragInfo[132] = alphaMode.index.toDouble();
    fragInfo[133] = alphaCutoff;
    fragInfo[138] = specularAntiAliasingVariance;
    fragInfo[139] = specularAntiAliasingThreshold;
    fragInfo[EngineLightingUniforms.fadeIndex] = lodFade;
    pass.bindUniform(
      fragmentShader.getUniformSlot("FragInfo"),
      transientsBuffer.emplace(ByteData.sublistView(fragInfo)),
    );

    _bindSlot(pass, 'base_color_texture', baseColorTexture);
    _bindSlot(pass, 'emissive_texture', emissiveTexture);
    _bindSlot(pass, 'metallic_roughness_texture', metallicRoughnessTexture);
    _bindSlot(pass, 'normal_texture', normalTexture, normal: true);
    _bindSlot(pass, 'occlusion_texture', occlusionTexture);
    // Image-based-lighting atlas, BRDF LUT, and shadow map. Shared with
    // PreprocessedMaterial: the sampler choices (radiance repeat/clamp, LUT
    // clamp/clamp, shadow bilinear/clamp) and the white shadow placeholder
    // live in EngineLightingUniforms.
    EngineLightingUniforms.bindEngineTextures(
      pass,
      fragmentShader,
      lighting,
      env,
    );
    EngineLightingUniforms.bindFog(
      pass,
      fragmentShader,
      transientsBuffer,
      lighting,
    );
  }

  static final gpu.SamplerOptions _repeatSampler = gpu.SamplerOptions(
    widthAddressMode: gpu.SamplerAddressMode.repeat,
    heightAddressMode: gpu.SamplerAddressMode.repeat,
  );

  // Binds one texture slot, substituting the neutral placeholder when the
  // slot is empty (or its render texture has no completed frame yet). A
  // RenderTexture source brings its own sampler; static textures use the
  // material's repeat default.
  void _bindSlot(
    gpu.RenderPass pass,
    String name,
    TextureSource? source, {
    bool normal = false,
  }) {
    final resolved = resolveTextureSource(source);
    pass.bindTexture(
      fragmentShader.getUniformSlot(name),
      normal
          ? Material.normalPlaceholder(resolved)
          : Material.whitePlaceholder(resolved),
      sampler: textureSourceSampler(source) ?? _repeatSampler,
    );
  }

  @override
  gpu.Texture? get reflectionRoughnessTexture =>
      resolveTextureSource(metallicRoughnessTexture);

  @override
  double get reflectionRoughnessFactor => roughnessFactor;

  @override
  bool isOpaque() {
    // BLEND always goes through the translucent pass. OPAQUE and MASK
    // are drawn in the opaque pass (MASK relies on the shader's
    // alpha-test discard); a sub-1 baseColorFactor alpha still forces
    // the translucent pass so directly-constructed translucent
    // materials keep working without an explicit alpha mode.
    if (alphaMode == AlphaMode.blend) return false;
    return baseColorFactor.a >= 1.0;
  }
}
