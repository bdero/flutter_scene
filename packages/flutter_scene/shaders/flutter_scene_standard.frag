uniform FragInfo {
  vec4 color;
  vec4 emissive_factor;
  // Diffuse irradiance L2 spherical-harmonic coefficients (xyz = RGB,
  // w unused). The cosine convolution (A_l band factors) and the 1/pi
  // Lambertian term are already folded in, so evaluating the polynomial
  // yields E(n)/pi, ready to multiply by the diffuse albedo.
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
  float metallic_factor;
  float roughness_factor;
  float has_normal_map;
  float normal_scale;
  float occlusion_strength;
  float environment_intensity;
  float has_directional_light;
  float casts_shadow;
  float shadow_bias;
  float shadow_normal_bias;
  float shadow_texel_size; // 1 / shadow map resolution
  // 1.0 on backends whose render-to-texture targets sample top-down
  // (Metal/Vulkan), 0.0 where they sample bottom-up (OpenGL ES). Applied
  // when sampling the shadow map and the prefiltered-radiance atlas; the
  // Dart side fills it (Flutter GPU has no backend macro).
  float render_target_flip_y;
  // glTF alpha mode: 0 opaque, 1 mask, 2 blend. In mask mode a fragment
  // whose alpha is below alpha_cutoff is discarded and the rest are
  // forced fully opaque.
  float alpha_mode;
  float alpha_cutoff;
  // UV-space half-width over which shadowing fades back to lit at the
  // shadow map border, softening the box edge. 0 disables the fade.
  float shadow_fade;
  // UV-space radius of the soft-shadow (PCF) sampling disk; the shadow
  // penumbra width.
  float shadow_softness;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform sampler2D prefiltered_radiance; // PMREM-style roughness-band atlas
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

// A 16-tap Poisson disk, sampled by the soft-shadow PCF kernel.
const vec2 kPoissonDisk[16] = vec2[](
    vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725),
    vec2(-0.09418410, -0.92938870), vec2(0.34495938, 0.29387760),
    vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464),
    vec2(-0.38277543, 0.27676845), vec2(0.97484398, 0.75648379),
    vec2(0.44323325, -0.97511554), vec2(0.53742981, -0.47373420),
    vec2(-0.26496911, -0.41893023), vec2(0.79197514, 0.19090188),
    vec2(-0.24188840, 0.99706507), vec2(-0.81409955, 0.91437590),
    vec2(0.19984126, 0.78641367), vec2(0.14383161, -0.14100790));

// Soft PCF shadow lookup. Returns 1.0 (lit) .. 0.0 (fully shadowed).
// `world_pos` and `n` are world-space; `n` is the (perturbed) shading
// normal, used for normal-offset bias to fight grazing-angle acne.
float SampleShadow(vec3 world_pos, vec3 n) {
  vec3 biased_pos = world_pos + n * frag_info.shadow_normal_bias;
  vec4 light_clip = frag_info.light_space_matrix * vec4(biased_pos, 1.0);
  vec3 proj = light_clip.xyz / light_clip.w;
  vec2 uv = proj.xy * 0.5 + 0.5;
  // The shadow map is a render-to-texture target; flip V to match its
  // sampled Y orientation (top-down on Metal/Vulkan, bottom-up on OpenGL
  // ES -- see render_target_flip_y).
  if (frag_info.render_target_flip_y > 0.5) {
    uv.y = 1.0 - uv.y;
  }
  // Outside the orthographic shadow frustum: treat as lit.
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || proj.z < 0.0 ||
      proj.z > 1.0) {
    return 1.0;
  }
  float receiver_depth = proj.z - frag_info.shadow_bias;

  // Poisson-disk PCF. The disk radius is the penumbra width; a
  // per-fragment rotation hides the sample pattern so 16 taps read as
  // a smooth soft edge instead of banding.
  float radius = max(frag_info.shadow_softness, frag_info.shadow_texel_size);
  float noise = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  float angle = noise * 6.28318530718;
  float ca = cos(angle);
  float sa = sin(angle);
  float lit = 0.0;
  for (int i = 0; i < 16; i++) {
    vec2 p = kPoissonDisk[i];
    vec2 offset = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * radius;
    float caster_depth = texture(shadow_map, uv + offset).r;
    lit += receiver_depth <= caster_depth ? 1.0 : 0.0;
  }
  float shadow = lit / 16.0;

  // Fade shadowing back to lit over the outer `shadow_fade` of UV space
  // so the shadow map's box edge is soft rather than a hard cutoff.
  float fade = frag_info.shadow_fade;
  if (fade > 0.0) {
    vec2 edge = smoothstep(vec2(0.0), vec2(fade), uv) *
                smoothstep(vec2(0.0), vec2(fade), vec2(1.0) - uv);
    shadow = mix(1.0, shadow, edge.x * edge.y);
  }
  return shadow;
}

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, v_texture_coords);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // MASK alpha mode: discard fragments below the cutoff, render the
  // rest fully opaque (glTF treats MASK output as binary).
  if (frag_info.alpha_mode == 1.0) {
    if (alpha < frag_info.alpha_cutoff) {
      discard;
    }
    alpha = 1.0;
  }
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

  vec3 irradiance = max(EvaluateDiffuseSH(normal), vec3(0.0)) *
                    frag_info.environment_intensity;
  vec3 prefiltered_color =
      SamplePrefilteredRadiance(prefiltered_radiance, reflection_normal,
                                roughness, frag_info.render_target_flip_y) *
      frag_info.environment_intensity;

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
  // floating-point scene-color target.
  vec3 out_color = ambient + direct + emissive;
  frag_color = vec4(out_color, 1.0) * alpha;
}
