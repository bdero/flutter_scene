// The engine lighting inputs a lit material receives: the FragInfo uniform
// block (the analytic light, shadow cascades, and image-based-lighting SH and
// environment data) and the IBL / shadow samplers. material_lighting.glsl
// reads these to evaluate the lit color. The standard PBR shader and every
// generated lit `.fmat` material share this single declaration of the engine
// lighting interface.

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
  // Level-of-detail cross-fade coverage. 1 draws every fragment. A value in
  // (0, 1) keeps that fraction of fragments in a screen-space dither pattern
  // (the rest discard); a negative value keeps the complementary pattern of
  // |value|, so two adjacent LOD levels with fades summing to 1 tile the
  // screen between them. Occupies std140 padding before the mat4, so the
  // block size is unchanged. See lod_fade.glsl.
  float fade;
  // Geometric specular antialiasing (Kaplanyan/Tokuyoshi). specular_aa_variance
  // scales the screen-space normal-derivative variance estimate; a normal map
  // or high-curvature surface packs sub-pixel normal variation that the
  // specular lobe otherwise turns into shimmer, so this widens roughness to
  // average the lobe over the pixel's normal cone. specular_aa_threshold caps
  // how much extra roughness it can add. A variance of 0 disables it. Both
  // occupy the std140 padding after `fade` (before the mat4), so the block size
  // is unchanged.
  float specular_aa_variance;
  float specular_aa_threshold;
  // Rotates the image-based-lighting environment: the diffuse-SH and
  // prefiltered-radiance lookup directions are transformed by this before
  // sampling. Identity leaves the environment unrotated. A mat4 (not mat3)
  // so the std140 columns are tightly packed vec4s: Impeller's OpenGL ES
  // backend mis-reads a std140 mat3 uniform (padded vec3 columns), which
  // collapsed env_normal/env_reflection to a constant on GLES.
  mat4 environment_transform;
  // Screen-space ambient occlusion controls. x: occlusion enabled (sampled
  // from ssao_texture when > 0.5). y: specular occlusion enabled. zw:
  // reciprocal of the render-target size, to turn gl_FragCoord into the
  // occlusion-texture UV.
  vec4 ssao_params;
  // Image-based-lighting cross-fade and shadow-ambient control. x: blend
  // toward the secondary environment (the *_b samplers), 0 samples only the
  // primary. y: shadow-ambient strength, how much the cast shadow also darkens
  // the IBL ambient (0 leaves the ambient physical, 1 darkens it as much as the
  // direct light). zw reserved. Both environments share RadianceLayoutInfo (the
  // layout is a per-backend choice, not per-environment).
  vec4 radiance_blend;
}
frag_info;

uniform sampler2D prefiltered_radiance; // PMREM-style roughness-band atlas
// Roughness-mip prefiltered radiance cubemap (sampled instead of the 2D atlas
// when RadianceLayoutInfo.cube_layout is set; no pole distortion).
uniform samplerCube prefiltered_radiance_cube;
uniform sampler2D brdf_lut;
uniform sampler2D shadow_map;
// Diffuse irradiance SH coefficients: a 9x1 texture, coefficient i at texel i
// (RGB). Sampled instead of read from a uniform so a sky's coefficients,
// computed on the GPU, need no read-back. The diffuse_sh* uniform fields above
// are unused.
uniform sampler2D sh_coefficients;
// The secondary environment cross-faded in by frag_info.radiance_blend.x: its
// prefiltered radiance (2D atlas and cubemap, the same layout pair as the
// primary) and diffuse SH. A dummy is bound when no cross-fade is active.
uniform sampler2D prefiltered_radiance_b;
uniform samplerCube prefiltered_radiance_cube_b;
uniform sampler2D sh_coefficients_b;
// Screen-space ambient occlusion (occlusion factor in .r). A white
// placeholder is bound when occlusion is disabled, so the sample is a
// no-op; frag_info.ssao_params.x gates it regardless.
uniform sampler2D ssao_texture;
