uniform FragInfo {
  vec4 color;
  vec4 emissive_factor;
  // Diffuse irradiance L2 spherical-harmonic coefficients (xyz = RGB,
  // w unused). The cosine convolution (A_l band factors) and the 1/pi
  // Lambertian term are already folded in, so evaluating the polynomial
  // yields E(n)/pi, ready to multiply by the diffuse albedo. When
  // use_diffuse_sh <= 0.5, irradiance_texture is sampled instead.
  vec4 diffuse_sh0;
  vec4 diffuse_sh1;
  vec4 diffuse_sh2;
  vec4 diffuse_sh3;
  vec4 diffuse_sh4;
  vec4 diffuse_sh5;
  vec4 diffuse_sh6;
  vec4 diffuse_sh7;
  vec4 diffuse_sh8;
  // Directional light: xyz = direction the light travels (toward the
  // scene); rgb of the second vector = color premultiplied by intensity.
  // Active only when has_directional_light > 0.5.
  vec4 directional_light_direction;
  vec4 directional_light_color;
  float vertex_color_weight;
  float exposure;
  float metallic_factor;
  float roughness_factor;
  float has_normal_map;
  float normal_scale;
  float occlusion_strength;
  float environment_intensity;
  // Tone mapping operator: 0 = Khronos PBR Neutral, 1 = ACES filmic,
  // 2 = Reinhard, anything else = linear (clamp). See ToneMappingMode.
  float tone_mapping_mode;
  float use_diffuse_sh;
  float has_directional_light;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform sampler2D radiance_texture;
uniform sampler2D irradiance_texture;

uniform sampler2D brdf_lut;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

#include <normals.glsl>
#include <pbr.glsl>
#include <texture.glsl>
#include <tone_mapping.glsl>

// Evaluates the L2 diffuse-irradiance SH polynomial in direction `n`.
// The coefficients already include the cosine convolution and 1/pi, so
// the result is E(n)/pi. Must use the same real-SH basis the CPU-side
// projection in EnvironmentMap.computeDiffuseSphericalHarmonics uses.
vec3 EvaluateDiffuseSH(vec3 n) {
  return frag_info.diffuse_sh0.xyz * 0.282095 +
         frag_info.diffuse_sh1.xyz * (0.488603 * n.y) +
         frag_info.diffuse_sh2.xyz * (0.488603 * n.z) +
         frag_info.diffuse_sh3.xyz * (0.488603 * n.x) +
         frag_info.diffuse_sh4.xyz * (1.092548 * n.x * n.y) +
         frag_info.diffuse_sh5.xyz * (1.092548 * n.y * n.z) +
         frag_info.diffuse_sh6.xyz * (0.315392 * (3.0 * n.z * n.z - 1.0)) +
         frag_info.diffuse_sh7.xyz * (1.092548 * n.x * n.z) +
         frag_info.diffuse_sh8.xyz * (0.546274 * (n.x * n.x - n.y * n.y));
}

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, v_texture_coords);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // Note: PerturbNormal needs the non-normalized view vector
  //       (camera_position - vertex_position).
  vec3 normal = normalize(v_normal);
  if (frag_info.has_normal_map > 0.5) {
    normal =
        PerturbNormal(normal_texture, normal, v_viewvector, v_texture_coords);
  }

  vec4 metallic_roughness =
      texture(metallic_roughness_texture, v_texture_coords);
  float metallic = clamp(metallic_roughness.b * frag_info.metallic_factor, 0.0,
                         1.0);
  float roughness =
      clamp(metallic_roughness.g * frag_info.roughness_factor, kMinRoughness,
            1.0);

  float occlusion = texture(occlusion_texture, v_texture_coords).r;
  occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  vec3 camera_normal = normalize(v_viewvector);

  vec3 reflectance = mix(vec3(0.04), albedo, metallic);

  // 1 when the surface is facing the camera, 0 when it's perpendicular to the
  // camera.
  float n_dot_v = max(dot(normal, camera_normal), 0.0);

  vec3 reflection_normal = reflect(camera_normal, normal);

  // Roughness-dependent Fresnel reflectance for the indirect specular lobe.
  vec3 k_S = FresnelSchlickRoughness(n_dot_v, reflectance, roughness);

  // TODO(bdero): This multiplier is here because the texture-based
  //              environment looks too dim. Should be resolved once HDR
  //              env maps + a real prefiltered cubemap land (roadmap
  //              Phase A item 4 / Phase B). The SH path is a correct
  //              irradiance integral and needs no fudge.
  const float kEnvironmentMultiplier = 2.0;
  vec3 irradiance;
  if (frag_info.use_diffuse_sh > 0.5) {
    irradiance = max(EvaluateDiffuseSH(normal), vec3(0.0)) *
                 frag_info.environment_intensity;
  } else {
    irradiance =
        SRGBToLinear(SampleEnvironmentTexture(irradiance_texture, normal)) *
        frag_info.environment_intensity * kEnvironmentMultiplier;
  }

  const float kMaxReflectionLod = 4.0;
  vec3 prefiltered_color =
      SRGBToLinear(SampleEnvironmentTextureLod(radiance_texture,
                                               reflection_normal,
                                               roughness * kMaxReflectionLod)
                       .rgb) *
      frag_info.environment_intensity * kEnvironmentMultiplier;
  // Hack: blend toward irradiance for rough surfaces because prefiltered
  // roughness LoDs aren't generated yet.
  // TODO(bdero): Remove once roughness LoDs are generated (roadmap Phase B).
  prefiltered_color =
      mix(irradiance, prefiltered_color, pow(1.02 - roughness, 12.0));

  // Split-sum DFG terms (Karis '13). The LUT is sampled slightly inside
  // [0, 1] to avoid edge-tap artifacts.
  vec2 f_ab = texture(brdf_lut, clamp(vec2(n_dot_v, roughness), 0.0, 0.99)).rg;

  // Single- and multiple-scattering energy compensation (Fdez-Aguera 2019;
  // see https://bruop.github.io/ibl/). Without the multiscatter term, rough
  // metals lose noticeable energy.
  vec3 FssEss = k_S * f_ab.x + f_ab.y;
  float Ems = 1.0 - (f_ab.x + f_ab.y);
  vec3 F_avg = reflectance + (1.0 - reflectance) / 21.0;
  vec3 FmsEms = Ems * FssEss * F_avg / (1.0 - F_avg * Ems);
  vec3 diffuse_color = albedo * (1.0 - metallic);
  vec3 k_D = diffuse_color * (1.0 - FssEss + FmsEms);

  vec3 indirect_specular = FssEss * prefiltered_color;
  vec3 indirect_diffuse = (FmsEms + k_D) * irradiance;
  vec3 ambient = (indirect_diffuse + indirect_specular) * occlusion;

  // Analytic directional light (Cook-Torrance, layered on top of the IBL
  // ambient term).
  vec3 direct = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    // surface -> light.
    vec3 light_vector = -normalize(frag_info.directional_light_direction.xyz);
    float n_dot_l = max(dot(normal, light_vector), 0.0);
    if (n_dot_l > 0.0) {
      vec3 half_vector = normalize(light_vector + camera_normal);
      float n_dot_v_safe = max(n_dot_v, 1e-4);
      float distribution = DistributionGGX(normal, half_vector, roughness);
      float visibility =
          VisibilitySmithGGXCorrelated(n_dot_v_safe, n_dot_l, roughness);
      vec3 specular_fresnel =
          FresnelSchlick(max(dot(half_vector, camera_normal), 0.0), reflectance);
      // `visibility` already folds in 1 / (4 * NoL * NoV).
      vec3 specular = distribution * visibility * specular_fresnel;
      vec3 diffuse = (vec3(1.0) - specular_fresnel) * (1.0 - metallic) *
                     albedo * (1.0 / kPi);
      direct = (diffuse + specular) * frag_info.directional_light_color.rgb *
               n_dot_l;
    }
  }

  vec3 emissive =
      SRGBToLinear(texture(emissive_texture, v_texture_coords).rgb) *
      frag_info.emissive_factor.rgb;

  vec3 out_color = ambient + direct + emissive;

  // Tone mapping. ACES applies `exposure` internally (with its 1/0.6
  // reference-white scale); the others take a plain pre-exposed color.
  if (frag_info.tone_mapping_mode < 0.5) {
    out_color = PBRNeutralToneMapping(out_color * frag_info.exposure);
  } else if (frag_info.tone_mapping_mode < 1.5) {
    out_color = ACESFilmicToneMapping(out_color, frag_info.exposure);
  } else if (frag_info.tone_mapping_mode < 2.5) {
    out_color = ReinhardToneMapping(out_color * frag_info.exposure);
  } else {
    out_color = clamp(out_color * frag_info.exposure, 0.0, 1.0);
  }

#ifndef IMPELLER_TARGET_METAL
  out_color = pow(out_color, vec3(1.0 / kGamma));
#endif

  // // Catch-all for unused uniforms (useful when debugging because unused
  // //uniforms are automatically culled from the shader).
  // frag_color =
  //     vec4(albedo, alpha) + vec4(normal, 1) + vec4(ambient, 1) +
  //     vec4(emissive, 1) +
  //     metallic_roughness //
  //         * frag_info.color * frag_info.emissive_factor * frag_info.exposure
  //         * frag_info.metallic_factor * frag_info.roughness_factor *
  //         frag_info.normal_scale * frag_info.occlusion_strength *
  //         frag_info.environment_intensity;

  frag_color = vec4(out_color, 1) * alpha;
}
