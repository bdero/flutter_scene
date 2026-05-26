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
  // World -> light-clip-space matrix per shadow cascade; the first
  // shadow_cascade_count entries are valid. Used when casts_shadow > 0.5.
  mat4 light_space_matrix[4];
  // World-space orthographic box size of each cascade (x..w map to
  // cascade 0..3), used to scale world-space softness and fade widths
  // into a cascade's UV space.
  vec4 cascade_box_sizes;
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
  // World-space width over which shadowing fades back to lit at the far
  // cascade's edge, softening the shadow distance limit. 0 disables it.
  float shadow_fade;
  // World-space radius of the soft-shadow (PCF) penumbra.
  float shadow_softness;
  // Number of valid cascades in light_space_matrix (1 to 4).
  float shadow_cascade_count;
  // 1 to invert the prefiltered-radiance atlas latitude when sampling, 0
  // otherwise. Set on backends that store render-to-texture bottom-up (OpenGL
  // ES); see SamplePrefilteredRadiance and y_flip.dart. Temporary workaround.
  float prefilter_flip_y;
  // Rotates the image-based-lighting environment: the diffuse-SH and
  // prefiltered-radiance lookup directions are transformed by this before
  // sampling. Identity leaves the environment unrotated. A mat4 (not mat3)
  // so the std140 columns are tightly packed vec4s: Impeller's OpenGL ES
  // backend mis-reads a std140 mat3 uniform (padded vec3 columns), which
  // collapsed env_normal/env_reflection to a constant on GLES.
  mat4 environment_transform;
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
#include <material_inputs.glsl>
#include <material_lighting.glsl>

// Fills the surface description for the standard glTF metallic-roughness
// material from the FragInfo parameters and the material textures. The shared
// lighting framework (material_lighting.glsl) consumes it.
void Surface(inout MaterialInputs material) {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, v_texture_coords);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // MASK alpha mode: discard fragments below the cutoff, render the
  // rest fully opaque (glTF treats MASK output as binary). Done here, before
  // the normal-map derivatives, so the discard's effect on screen-space
  // derivatives matches the original monolithic shader.
  if (frag_info.alpha_mode == 1.0) {
    if (alpha < frag_info.alpha_cutoff) {
      discard;
    }
    alpha = 1.0;
  }
  material.base_color = vec4(albedo, alpha);

  // Note: PerturbNormal needs the non-normalized view vector
  //       (camera_position - vertex_position).
  vec3 normal = normalize(v_normal);
  if (frag_info.has_normal_map > 0.5) {
    normal =
        PerturbNormal(normal_texture, normal, v_viewvector, v_texture_coords);
  }
  material.normal = normal;

  vec4 metallic_roughness =
      texture(metallic_roughness_texture, v_texture_coords);
  material.metallic = clamp(metallic_roughness.b * frag_info.metallic_factor,
                            0.0, 1.0);
  material.roughness =
      clamp(metallic_roughness.g * frag_info.roughness_factor, kMinRoughness,
            1.0);

  float occlusion = texture(occlusion_texture, v_texture_coords).r;
  material.occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  material.emissive =
      SRGBToLinear(texture(emissive_texture, v_texture_coords).rgb) *
      frag_info.emissive_factor.rgb;

  PrepareMaterial(material);
}

void main() {
  MaterialInputs material = InitMaterialInputs();
  Surface(material);
  frag_color = EvaluateLighting(material);
}
