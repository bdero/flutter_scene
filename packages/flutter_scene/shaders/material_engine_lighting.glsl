// The engine lighting inputs a lit material receives: the FragInfo uniform
// block (the analytic light, shadow cascades, and image-based-lighting SH and
// environment data) and the IBL / shadow samplers. material_lighting.glsl
// reads these to evaluate the lit color. The standard PBR shader and every
// generated lit `.fmat` material share this single declaration of the engine
// lighting interface.

uniform FragInfo {
  vec4 color;
  vec4 emissive_factor;
  // Punctual light texture dimensions, for normalizing the shader's fetch
  // coordinates. x: parameters-texture row count (all scene lights). y/z:
  // light-index texture width/height. (Reuses the first of the once-diffuse-SH
  // slots, which are unused now that SH is sampled from sh_coefficients.)
  vec4 punctual_dims;
  // Spot-shadow parameters (more of the unused SH region). x: shadow-casting
  // spot count (0 disables spot shadows; their atlas tiles follow the
  // directional cascades, and their matrices ride in the params texture).
  // y: clip-space depth bias. z: world-space normal bias. w: PCF softness in
  // texels.
  vec4 spot_shadow_params;
  // Material scene inputs (more of the unused SH region; see
  // Material.sceneInputs). x: the accumulated scene-color snapshot is bound
  // this draw (scene_opaque_color sampler, emitted only into materials that
  // declare engine_inputs). y: the opaque linear-depth texture is bound
  // (scene_depth sampler, same). z: engine time in seconds, for material
  // animation (GetTime()). w: tan of the half horizontal field of view
  // (0 when non-perspective), for screen-space marches. Screen UVs come
  // from gl_FragCoord.xy * ssao_params.zw (the reciprocal render-target
  // size, packed regardless of occlusion).
  vec4 scene_inputs;
  // xyz: the camera's world-space forward direction (unit length), so a
  // material can compute its fragment's planar view depth
  // (dot(-v_viewvector, camera_forward.xyz)) and difference it against the
  // scene_depth sample. w: tan of the half vertical field of view.
  vec4 camera_forward;
  // Remaining camera basis axes for projecting world-space offsets back to
  // screen UV. camera_right.w carries the sun's angular radius (radians) for
  // the soft-shadow penumbra; camera_up.w flags the occlusion texture's
  // indirect-light layout (radiance in rgb, visibility in a).
  vec4 camera_right;
  vec4 camera_up;
  // Rough-transmission atlas. x: available. y: valid band count. zw:
  // reciprocal atlas dimensions.
  vec4 transmission_info;
  // The primary environment's parallax box proxy (a reflection probe's
  // capture volume). probe_box.xyz is the world-space box center (also the
  // capture point) and probe_box.w is 1 when the proxy is active;
  // probe_extents.xyz is the box half extents. When active, reflection
  // lookups intersect the reflected ray with the box and sample toward the
  // hit. These reuse the retired diffuse-SH uniform rows (SH now rides the
  // sh_coefficients texture).
  vec4 probe_box;
  vec4 probe_extents;
  // Directional light: xyz = direction the light travels (toward the scene),
  // w = shadow filter (0 rotated Poisson, 1 fixed PCF). The second vector's
  // rgb is color premultiplied by intensity, and its w is the cascade
  // cross-fade fraction (0 hands off between cascades without blending).
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
  // direct light). z: the number of additional analytic lights packed into the
  // punctual_lights data texture (point, spot, and directional lights past the
  // first shadowed one); the material loops over this many. w is the
  // per-object slice offset into the light-index buffer. Both environments
  // share RadianceLayoutInfo (the layout is a per-backend choice, not
  // per-environment).
  vec4 radiance_blend;
  // Screen-space occlusion lighting controls. x is the fraction applied to
  // analytic direct lights. y is the multi-bounce amount (how much occluded
  // indirect diffuse converges toward the albedo instead of black). z is 1
  // when the occlusion texture's gba channels carry a packed view-space bent
  // normal. w is reserved.
  vec4 ssao_lighting;
  // xyz: the draw's model scale (world-space lengths of the model transform's
  // basis vectors), for scaling local-space lengths like the transmission
  // thickness into world units. Replaces the old v_model_scale varying; an
  // instanced draw carries its node's scale (not per-instance), and a skinned
  // draw its node's (not per-joint). w unused.
  vec4 model_scale;
  // xyz: the dielectric specular reflectance at normal incidence for the
  // standard (non-physical) shader path, clamp(((ior - 1) / (ior + 1))^2 *
  // specular_color * specular_factor, 0, 1), 0.04 for a default material.
  // The physical path derives its own from material inputs. w unused.
  vec4 dielectric_f0;
  // World-space irradiance field. gi_grid.xyz is the probe spacing and
  // gi_grid.w the field's intensity, 0 disabling the whole receiver.
  vec4 gi_grid;
  // gi_anchor.xyz is the lattice index of the volume's minimum-corner probe
  // (probes sit on an infinite lattice through the world origin, so the
  // volume can scroll without moving a probe that stayed inside it).
  // gi_anchor.w is the self-shadow bias as a fraction of the cell edge.
  vec4 gi_anchor;
  // gi_counts.xyz is the probe count per axis; gi_counts.w the probe tiles
  // per atlas row.
  vec4 gi_counts;
  // gi_atlas.x/y are the irradiance and depth regions' first atlas rows;
  // gi_atlas.zw the reciprocal atlas dimensions.
  vec4 gi_atlas;
  // gi_visibility.x is the Chebyshev strength (0 compiles the depth fetches
  // out), .y its world-space bias, .z the distance normalization the stored
  // moments were divided by, and .w the boundary fade width in cells.
  vec4 gi_visibility;
}
frag_info;

// The per-draw model scale (see FragInfo.model_scale).
vec3 GetModelScale() { return frag_info.model_scale.xyz; }

// FLUTTER_SCENE_SHADOW_CATCHER compiles out the image-based-lighting
// samplers: a shadow catcher never evaluates the lighting, and a declared
// sampler stays in the binding surface whether or not any live code reads it
// (backends disagree on the liveness of dead declarations), so the runtime
// would otherwise have to bind environment textures the shader cannot use.
#ifndef FLUTTER_SCENE_SHADOW_CATCHER
// The prefiltered radiance in whichever layout this backend builds, a
// roughness-mip cubemap or the 2D equirect atlas (see RadianceSampler).
uniform RadianceSampler prefiltered_radiance;
uniform sampler2D brdf_lut;
#endif
#ifndef FLUTTER_SCENE_SKIP_SHADOWS
uniform sampler2D shadow_map;
#endif
#ifndef FLUTTER_SCENE_SHADOW_CATCHER
// The environment's diffuse SH coefficients and, when the world-space
// irradiance field is on, that field's probe atlas. Coefficient i sits at
// texel (i, row), row 0 the primary environment and row 1 the cross-fade
// secondary; a scene with no cross-fade binds the primary's 9x1 texture and
// both rows land on it. Fetched (never sampled) so a bilinear filter cannot
// smear a neighbouring probe texel into a coefficient, which is what lets the
// probe atlas extend this same texture downward and cost no extra sampler.
// Declared highp because the probe regions carry distances.
//
// A baked-lightmap variant supplies its diffuse ambient from the lightmap
// instead, so the coefficients are not declared there and the lightmap sampler
// costs no extra texture unit.
#ifndef FLUTTER_SCENE_LIGHTMAP
uniform highp sampler2D irradiance_field;
#endif
// The secondary environment cross-faded in by frag_info.radiance_blend.x: its
// prefiltered radiance, in the same layout as the primary. Its diffuse SH
// rides in sh_coefficients row 1. A dummy is bound when no cross-fade is
// active.
uniform RadianceSampler prefiltered_radiance_b;
#endif
// Screen-space ambient occlusion (occlusion factor in .r). A white
// placeholder is bound when occlusion is disabled, so the sample is a
// no-op; frag_info.ssao_params.x gates it regardless.
#ifndef FLUTTER_SCENE_SKIP_SSAO
uniform sampler2D ssao_texture;
#endif
// A shadow catcher's no-shadow variant compiles its spot loop out, leaving
// the punctual textures with no live reference, so it declares neither.
#if !defined(FLUTTER_SCENE_SHADOW_CATCHER) || !defined(FLUTTER_SCENE_SKIP_SHADOWS)
// The additional analytic lights (point, spot, and directional lights past the
// first) as an RGBA32F data texture: one light per row, four texels wide. Read
// by computed UV (not a dynamically-indexed uniform array, which GLSL ES 1.00
// forbids in a fragment shader). frag_info.radiance_blend.z is the row count; a
// white placeholder is bound and never read when it is zero. Column layout:
//   0: position.xyz, type (0 directional, 1 point, 2 spot)
//   1: color.rgb * intensity, inverse range (0 = infinite)
//   2: direction.xyz, spot angular scale
//   3: spot angular offset, unused, unused, unused
uniform sampler2D punctual_lights;
// The per-object light-index buffer: a 2D RGBA32F texture whose texels (row
// major, index in .r) are light rows into punctual_lights. Each object shades
// the slice [radiance_blend.w, radiance_blend.w + radiance_blend.z). Read by
// computed UV (punctual_dims.yz give its width/height). A white placeholder is
// bound and never read when the per-object count is 0.
uniform sampler2D punctual_index;
#endif

// Engine time in seconds (wrapped to keep float precision), for material
// animation. Zero when the engine provides no time.
float GetTime() { return frag_info.scene_inputs.z; }

// The screen UV of this fragment, for sampling screen-space engine inputs
// (the scene_opaque_color / scene_depth samplers emitted into materials that
// declare engine_inputs).
vec2 GetScreenUv() { return gl_FragCoord.xy * frag_info.ssao_params.zw; }

// Projects a world-space offset from this fragment back into scene-color UV.
// A zero/non-perspective field of view leaves the sample at this fragment.
vec2 ProjectWorldOffsetToScreenUv(vec3 world_offset) {
  if (frag_info.scene_inputs.w <= 0.0 || frag_info.camera_forward.w <= 0.0) {
    return GetScreenUv();
  }
  vec3 from_camera = -v_viewvector + world_offset;
  float view_z = dot(from_camera, frag_info.camera_forward.xyz);
  if (view_z <= 1e-5) return GetScreenUv();
  float view_x = dot(from_camera, frag_info.camera_right.xyz);
  float view_y = dot(from_camera, frag_info.camera_up.xyz);
  return vec2(0.5 + 0.5 * view_x / (view_z * frag_info.scene_inputs.w),
              0.5 - 0.5 * view_y /
                        (view_z * frag_info.camera_forward.w));
}

// This fragment's planar view-space depth (world units along the camera
// forward axis), comparable against the opaque scene depth.
float GetFragmentViewDepth() {
  return dot(-v_viewvector, frag_info.camera_forward.xyz);
}
