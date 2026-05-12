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
  // World -> light-clip-space matrix for sampling shadow_map. Used only
  // when casts_shadow > 0.5.
  mat4 light_space_matrix;
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
  float casts_shadow;
  float shadow_bias;
  float shadow_normal_bias;
  float shadow_texel_size; // 1 / shadow map resolution
  // When > 0.5, specular IBL samples the prefiltered_radiance atlas;
  // otherwise it samples radiance_texture directly (no roughness
  // prefiltering).
  float use_prefiltered_radiance;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform sampler2D radiance_texture;
uniform sampler2D prefiltered_radiance; // PMREM-style roughness-band atlas
uniform sampler2D irradiance_texture;

uniform sampler2D brdf_lut;
uniform sampler2D shadow_map;

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

// 3x3 PCF shadow lookup. Returns 1.0 (lit) .. 0.0 (fully shadowed).
// `world_pos` and `n` are world-space; `n` is the (perturbed) shading
// normal, used for normal-offset bias to fight grazing-angle acne.
float SampleShadow(vec3 world_pos, vec3 n) {
  vec3 biased_pos = world_pos + n * frag_info.shadow_normal_bias;
  vec4 light_clip = frag_info.light_space_matrix * vec4(biased_pos, 1.0);
  vec3 proj = light_clip.xyz / light_clip.w;
  vec2 uv = proj.xy * 0.5 + 0.5;
  // The shadow map is a render-to-texture target; its origin is at the
  // top, so flip V to match the standard texture sampling convention.
  uv.y = 1.0 - uv.y;
  // Outside the orthographic shadow frustum: treat as lit.
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || proj.z < 0.0 ||
      proj.z > 1.0) {
    return 1.0;
  }
  float receiver_depth = proj.z - frag_info.shadow_bias;
  float texel = frag_info.shadow_texel_size;
  float lit = 0.0;
  for (int dx = -1; dx <= 1; dx++) {
    for (int dy = -1; dy <= 1; dy++) {
      vec2 sample_uv = uv + vec2(float(dx), float(dy)) * texel;
      float caster_depth = texture(shadow_map, sample_uv).r;
      lit += receiver_depth <= caster_depth ? 1.0 : 0.0;
    }
  }
  return lit / 9.0;
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

  vec3 irradiance;
  if (frag_info.use_diffuse_sh > 0.5) {
    irradiance = max(EvaluateDiffuseSH(normal), vec3(0.0)) *
                 frag_info.environment_intensity;
  } else {
    // Legacy pre-convolved irradiance texture. The 2x factor compensates
    // for the historically-dim texture path; the SH path above (the
    // default) is a correct irradiance integral and needs no fudge.
    irradiance =
        SRGBToLinear(SampleEnvironmentTexture(irradiance_texture, normal)) *
        frag_info.environment_intensity * 2.0;
  }

  vec3 prefiltered_color;
  if (frag_info.use_prefiltered_radiance > 0.5) {
    prefiltered_color =
        SamplePrefilteredRadiance(prefiltered_radiance, reflection_normal,
                                  roughness) *
        frag_info.environment_intensity;
  } else {
    // No prefiltered atlas: sample the raw radiance map directly. Roughness
    // is ignored (glossy surfaces look mirror-like); only reached for
    // environments built without prefiltering, e.g. EnvironmentMap.empty().
    prefiltered_color =
        SRGBToLinear(SampleEnvironmentTexture(radiance_texture,
                                              reflection_normal)) *
        frag_info.environment_intensity;
  }

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
      float shadow =
          frag_info.casts_shadow > 0.5 ? SampleShadow(v_position, normal) : 1.0;
      direct = (diffuse + specular) * frag_info.directional_light_color.rgb *
               n_dot_l * shadow;
    }
  }

  vec3 emissive =
      SRGBToLinear(texture(emissive_texture, v_texture_coords).rgb) *
      frag_info.emissive_factor.rgb;

  // Linear HDR, premultiplied by alpha. Exposure, the tone-mapping
  // operator, and the display EOTF are applied later by the tone-mapping
  // resolve pass (see flutter_scene_tonemap.frag), so this writes into a
  // floating-point scene-color target. `frag_info.exposure` /
  // `frag_info.tone_mapping_mode` are unused here for the same reason.
  vec3 out_color = ambient + direct + emissive;
  frag_color = vec4(out_color, 1.0) * alpha;
}
