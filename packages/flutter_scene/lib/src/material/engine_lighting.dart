import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/light.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/material/material.dart';

/// Packs the engine lighting half of the shared `FragInfo` uniform block and
/// binds the image-based-lighting and shadow samplers.
///
/// The `FragInfo` block (declared in `shaders/material_engine_lighting.glsl`
/// and read by `EvaluateLighting` in `material_lighting.glsl`) mixes
/// material-specific fields with engine lighting / IBL / shadow fields. This
/// helper owns the lighting fields, which are identical for every lit material;
/// callers add their own material fields (if any) to the same buffer. Both
/// [PhysicallyBasedMaterial] and `PreprocessedMaterial` use it so the lighting
/// packing lives in one place.
class EngineLightingUniforms {
  /// The float count of the full `FragInfo` block (656 bytes / 164 floats:
  /// the mat4 `environment_transform` ends at float 155, the `ssao_params`
  /// vec4 at floats 156..159, then the `radiance_blend` vec4 at floats
  /// 160..163). See the layout map in the implementation.
  static const fragInfoFloatCount = 164;

  /// Index of the LOD cross-fade `fade` field in `FragInfo`, occupying std140
  /// padding before `environment_transform` (so the block size is unchanged).
  static const fadeIndex = 137;

  /// Default geometric-specular-antialiasing strength and threshold, matching
  /// [PhysicallyBasedMaterial]'s defaults. Packed at [138]/[139] (the remaining
  /// std140 padding after `fade`) so every lit material gets antialiasing by
  /// default; a material that exposes the knobs overwrites these afterward.
  static const defaultSpecularAaVariance = 0.15;
  static const defaultSpecularAaThreshold = 0.2;

  /// Writes the engine lighting / IBL / shadow fields of `FragInfo` into
  /// [fragInfo] from [lighting] and [env]. Leaves the material-specific fields
  /// (color, factors, alpha mode) untouched for the caller to fill.
  static void packInto(
    Float32List fragInfo,
    Lighting lighting,
    EnvironmentMap env,
  ) {
    // Default to fully drawn; a material with an active LOD cross-fade
    // overwrites this. Without it the zero-initialized slot would discard
    // every fragment.
    fragInfo[fadeIndex] = 1.0;
    final light = lighting.directionalLight;
    final cascades = lighting.shadowMap == null
        ? const <ShadowCascade>[]
        : lighting.cascades;

    // diffuse_sh0..8 at [8..43] are now unused: the shader samples the
    // sh_coefficients texture (bound in bindEngineTextures) instead, so the
    // GPU-computed coefficients of a baked sky need no read-back. Left zero.

    // directional_light_direction [44..47], directional_light_color [48..51].
    if (light != null) {
      // The world-space direction comes from the light node's transform;
      // fall back to the light's own field for a node-less light.
      final direction = lighting.directionalLightDirection ?? light.direction;
      fragInfo[44] = direction.x;
      fragInfo[45] = direction.y;
      fragInfo[46] = direction.z;
      fragInfo[48] = light.color.x * light.intensity;
      fragInfo[49] = light.color.y * light.intensity;
      fragInfo[50] = light.color.z * light.intensity;
    }
    // light_space_matrix[4] at [52..115], cascade_box_sizes at [116..119].
    for (var i = 0; i < cascades.length; i++) {
      fragInfo.setRange(
        52 + i * 16,
        68 + i * 16,
        cascades[i].lightSpaceMatrix.storage,
      );
      fragInfo[116 + i] = cascades[i].boxSize;
    }
    fragInfo[126] = lighting.environmentIntensity;
    fragInfo[127] = light != null ? 1.0 : 0.0;
    fragInfo[128] = cascades.isEmpty ? 0.0 : 1.0;
    fragInfo[129] = light?.shadowDepthBias ?? 0.0;
    fragInfo[130] = light?.shadowNormalBias ?? 0.0;
    fragInfo[131] = light == null ? 0.0 : 1.0 / light.shadowMapResolution;
    fragInfo[134] = light?.shadowFadeRange ?? 0.0;
    fragInfo[135] = light?.shadowSoftness ?? 0.0;
    fragInfo[136] = cascades.length.toDouble();
    // Geometric specular antialiasing at [138]/[139] (specular_aa_variance and
    // specular_aa_threshold). Defaults for every lit material; a material with
    // its own knobs overwrites these after packInto.
    fragInfo[138] = defaultSpecularAaVariance;
    fragInfo[139] = defaultSpecularAaThreshold;
    // environment_transform: a mat4 carrying the 3x3 rotation; std140 mat4
    // columns are 16 bytes each, at [140], [144], [148], [152].
    final envTransform = lighting.environmentTransform.storage;
    for (var col = 0; col < 3; col++) {
      fragInfo[140 + col * 4] = envTransform[col * 3];
      fragInfo[141 + col * 4] = envTransform[col * 3 + 1];
      fragInfo[142 + col * 4] = envTransform[col * 3 + 2];
    }
    fragInfo[155] = 1.0; // mat4 column 3 = (0, 0, 0, 1)
    // ssao_params at [156..159]: occlusion enabled, specular occlusion
    // enabled, and the reciprocal render-target size (for the gl_FragCoord
    // to occlusion-UV mapping).
    fragInfo[156] = lighting.ssaoMap != null ? 1.0 : 0.0;
    fragInfo[157] = lighting.specularOcclusionMode;
    final viewport = lighting.viewportSize;
    fragInfo[158] = viewport.width > 0 ? 1.0 / viewport.width : 0.0;
    fragInfo[159] = viewport.height > 0 ? 1.0 / viewport.height : 0.0;
    // radiance_blend at [160..163]: x is the IBL cross-fade factor toward the
    // secondary environment (0 and ignored when there is no secondary); y is
    // the shadow-ambient strength (how much the cast shadow darkens the IBL
    // ambient, 0 leaves it physical); zw reserved.
    fragInfo[160] = lighting.environmentMapB != null
        ? lighting.environmentBlend.clamp(0.0, 1.0)
        : 0.0;
    fragInfo[161] = light?.shadowAmbientStrength.clamp(0.0, 1.0) ?? 0.0;
  }

  // Tiny constant uniform blocks (std140, 16 bytes) selecting the bound
  // prefiltered radiance's layout in the shader (RadianceLayoutInfo in
  // texture.glsl); device-resident so binding needs no per-frame buffer.
  // (mip_layout, cube_layout). Cube: read the samplerCube. Mip: the 2D mip
  // equirect. Atlas: the legacy 2D stacked-band equirect.
  static final gpu.BufferView _layoutCube = _layoutFlagBuffer(0.0, 1.0);
  static final gpu.BufferView _layoutMip = _layoutFlagBuffer(1.0, 0.0);
  static final gpu.BufferView _layoutAtlas = _layoutFlagBuffer(0.0, 0.0);

  static gpu.BufferView _layoutFlagBuffer(double mip, double cube) {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List(4)
          ..[0] = mip
          ..[1] = cube,
      ),
    );
    return gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 16);
  }

  /// Binds the prefiltered radiance sampler plus the `RadianceLayoutInfo`
  /// block that tells `SamplePrefilteredRadiance` which layout the bound
  /// texture uses. Every engine site that binds `prefiltered_radiance`
  /// goes through this so the texture and its layout flag never disagree.
  static void bindPrefilteredRadiance(
    gpu.RenderPass pass,
    gpu.Shader shader,
    EnvironmentMap env,
  ) {
    final cubeLayout = env.usesCubeRadianceLayout;
    final mipLayout = env.usesMipRadianceLayout;
    // 2D atlas (real on the equirect layouts, a dummy on the cube layout).
    // Horizontal repeat (longitude wraps), vertical clamp. The mip layout
    // needs a linear mip filter for textureLod to take effect; the legacy
    // band atlas has a single level, where the mip filter is inert.
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance'),
      env.prefilteredRadianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: mipLayout ? gpu.MipFilter.linear : gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    // Radiance cubemap (real on the cube layout, a dummy otherwise). Mip-linear
    // for the roughness textureLod; clamp the faces.
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance_cube'),
      env.prefilteredRadianceCube,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: gpu.MipFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    pass.bindUniform(
      shader.getUniformSlot('RadianceLayoutInfo'),
      cubeLayout ? _layoutCube : (mipLayout ? _layoutMip : _layoutAtlas),
    );
  }

  /// Binds the engine image-based-lighting and shadow samplers
  /// (`prefiltered_radiance`, `brdf_lut`, `shadow_map`) on [shader].
  static void bindEngineTextures(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
    EnvironmentMap env,
  ) {
    bindPrefilteredRadiance(pass, shader, env);
    pass.bindTexture(
      shader.getUniformSlot('brdf_lut'),
      Material.getBrdfLutTexture(),
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    pass.bindTexture(
      shader.getUniformSlot('shadow_map'),
      Material.whitePlaceholder(lighting.shadowMap),
      // The atlas is fp32. GLES devices may support rendering/sampling float
      // textures without GL_OES_texture_float_linear, making linear filtering
      // incomplete. The shader already performs PCF explicitly, so nearest is
      // the portable choice.
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
      ),
    );
    // Diffuse irradiance SH: a 9x1 coefficient texture, point-sampled (each
    // texel is one coefficient). Sampled in EvaluateDiffuseSH.
    pass.bindTexture(
      shader.getUniformSlot('sh_coefficients'),
      env.diffuseShTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    // The secondary cross-fade environment (the *_b samplers). When no
    // cross-fade is active the primary is bound here too (a valid no-op, since
    // frag_info.radiance_blend.x is 0 and the shader never reads it).
    _bindSecondaryRadiance(pass, shader, lighting.environmentMapB ?? env);
    // Screen-space ambient occlusion. Bilinear so a half-resolution
    // occlusion buffer upsamples smoothly; a white placeholder makes the
    // sample a no-op when occlusion is off. The shader gates it on
    // ssao_params.x regardless.
    pass.bindTexture(
      shader.getUniformSlot('ssao_texture'),
      Material.whitePlaceholder(lighting.ssaoMap),
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }

  /// Binds the secondary cross-fade environment's prefiltered radiance to the
  /// `prefiltered_radiance_b` / `prefiltered_radiance_cube_b` samplers (the
  /// specular pair only, no diffuse SH). Shared by the lit material and the
  /// environment skybox; both share the primary's [RadianceLayoutInfo], so the
  /// layout flag is not re-bound here.
  static void bindSecondaryRadiance(
    gpu.RenderPass pass,
    gpu.Shader shader,
    EnvironmentMap env,
  ) {
    final mipLayout = env.usesMipRadianceLayout;
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance_b'),
      env.prefilteredRadianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: mipLayout ? gpu.MipFilter.linear : gpu.MipFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance_cube_b'),
      env.prefilteredRadianceCube,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: gpu.MipFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }

  // Binds the secondary environment's prefiltered radiance and diffuse SH to
  // the `_b` samplers, with the same options as the primary (both share the
  // bound RadianceLayoutInfo, so the layout flag is not re-bound).
  static void _bindSecondaryRadiance(
    gpu.RenderPass pass,
    gpu.Shader shader,
    EnvironmentMap env,
  ) {
    bindSecondaryRadiance(pass, shader, env);
    pass.bindTexture(
      shader.getUniformSlot('sh_coefficients_b'),
      env.diffuseShTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.nearest,
        widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }
}
