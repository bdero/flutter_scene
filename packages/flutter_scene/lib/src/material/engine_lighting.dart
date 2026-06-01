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
  /// The float count of the full `FragInfo` block (640 bytes / 160 floats:
  /// the mat4 `environment_transform` ends at float 155, followed by the
  /// `ssao_params` vec4 at floats 156..159). See the layout map in the
  /// implementation.
  static const fragInfoFloatCount = 160;

  /// Writes the engine lighting / IBL / shadow fields of `FragInfo` into
  /// [fragInfo] from [lighting] and [env]. Leaves the material-specific fields
  /// (color, factors, alpha mode) untouched for the caller to fill.
  static void packInto(
    Float32List fragInfo,
    Lighting lighting,
    EnvironmentMap env,
  ) {
    final light = lighting.directionalLight;
    final cascades = lighting.shadowMap == null
        ? const <ShadowCascade>[]
        : lighting.cascades;

    // diffuse_sh0..8 at [8..43] (xyz used).
    final shCoefficients = env.diffuseSphericalHarmonics;
    for (var i = 0; i < shCoefficients.length; i++) {
      fragInfo[8 + i * 4] = shCoefficients[i].x;
      fragInfo[9 + i * 4] = shCoefficients[i].y;
      fragInfo[10 + i * 4] = shCoefficients[i].z;
    }
    // directional_light_direction [44..47], directional_light_color [48..51].
    if (light != null) {
      fragInfo[44] = light.direction.x;
      fragInfo[45] = light.direction.y;
      fragInfo[46] = light.direction.z;
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
  }

  /// Binds the engine image-based-lighting and shadow samplers
  /// (`prefiltered_radiance`, `brdf_lut`, `shadow_map`) on [shader].
  static void bindEngineTextures(
    gpu.RenderPass pass,
    gpu.Shader shader,
    Lighting lighting,
    EnvironmentMap env,
  ) {
    // Specular IBL atlas: horizontal repeat (longitude wraps), vertical clamp
    // (roughness bands must not bleed).
    pass.bindTexture(
      shader.getUniformSlot('prefiltered_radiance'),
      env.prefilteredRadianceTexture,
      sampler: gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
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
}
