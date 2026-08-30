// The per-frame engine data a material reads in screen space: the shared
// FragInfo uniform block and the accessors over it. The lit lighting framework
// includes this, and a generated unlit `.fmat` that declares engine_inputs
// includes it directly, so both paths share one declaration of the block.
// Binding it costs no texture unit, which is what makes it safe for unlit.
//
// The scene-color and scene-depth samplers compile in only when the material
// declares them (FLUTTER_SCENE_SCENE_COLOR/FLUTTER_SCENE_SCENE_DEPTH, written
// by the `.fmat` emitter). A declared-but-unread resource has backend-dependent
// liveness, so what a shader declares is decided here at compile time, never at
// bind time.

#ifndef MATERIAL_SCENE_INPUTS_GLSL_
#define MATERIAL_SCENE_INPUTS_GLSL_

uniform FragInfo {
  vec4 color;
  vec4 emissive_factor;
  // Punctual light texture dimensions, for normalizing the shader's fetch
  // coordinates. x: parameters-texture row count (all scene lights). y/z:
  // light-index texture width/height (the froxel data texture's dimensions in
  // froxel mode). w: the froxel depth-slice bias (see froxel_grid). (Reuses
  // the first of the once-diffuse-SH slots, which are unused now that SH is
  // sampled from sh_coefficients.)
  vec4 punctual_dims;
  // Spot-shadow parameters (more of the unused SH region). x: total
  // non-cascade shadow atlas tile count, the spot tiles then the point-shadow
  // tiles (0 disables both; the tiles follow the directional cascades, and the
  // per-light shadow data rides in the params texture). y: clip-space spot
  // depth bias. z: world-space spot normal bias. w: spot PCF softness in
  // texels (point lights carry per-light equivalents in their params rows).
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
  // Froxel clustered lighting for this view. xyz: the froxel grid's tile and
  // slice counts (z of 0 selects the per-object light lists instead); w: the
  // depth-slice scale (slice = log2(viewDepth) * w + punctual_dims.w). The
  // froxel table and its light records share the punctual_index texture:
  // texels [0, x*y*z) hold each froxel's records offset (.r, absolute) and
  // light count (.g); records (.r a light row) follow.
  vec4 froxel_grid;
}
frag_info;

// Engine time in seconds (wrapped to keep float precision), for material
// animation. Zero when the engine provides no time.
float GetTime() { return frag_info.scene_inputs.z; }

// The screen UV of this fragment, for sampling screen-space engine inputs
// (the scene_opaque_color / scene_depth samplers below).
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

#ifdef FLUTTER_SCENE_SCENE_COLOR
// The accumulated scene color behind this draw (linear HDR).
uniform sampler2D scene_opaque_color;

// Samples the composed scene behind this fragment, offset in screen UV (pass
// vec2(0.0) for no distortion). Returns black when the snapshot is
// unavailable.
vec3 GetSceneColor(vec2 uv_offset) {
  if (frag_info.scene_inputs.x < 0.5) return vec3(0.0);
  vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), vec2(0.999));
  return texture(scene_opaque_color, uv).rgb;
}
#endif

// The depth reported when no opaque depth is bound. Far enough that a
// depth-difference effect fades out instead of popping, and that an unprojected
// point lands well outside any projection volume.
const float kSceneDepthUnavailable = 1.0e8;

#ifdef FLUTTER_SCENE_SCENE_DEPTH
// The opaque linear (planar view-space) depth, world units. Explicitly highp:
// the impeller headers default samplers to mediump, which quantizes far depth.
uniform highp sampler2D scene_depth;

// The opaque depth behind this fragment, offset in screen UV. Returns a huge
// depth when unavailable, so depth-difference effects fade out instead of
// popping.
float GetSceneDepth(vec2 uv_offset) {
  if (frag_info.scene_inputs.y < 0.5) return kSceneDepthUnavailable;
  vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), vec2(0.999));
  return texture(scene_depth, uv).r;
}

// The world-space point on the opaque surface behind this fragment, offset in
// screen UV. The inverse of ProjectWorldOffsetToScreenUv, reusing the same
// camera basis and half-fov tangents.
//
// When depth is unavailable or the camera is not perspective, this returns a
// point at the same huge sentinel depth GetSceneDepth reports, so a reader
// fades out or falls outside its own volume. Returning the fragment's own
// position instead would sit exactly on a projection volume's boundary, where
// round-off splits a decal's inside test across its box faces.
vec3 GetSceneWorldPosition(vec2 uv_offset) {
  if (frag_info.scene_inputs.y < 0.5 || frag_info.scene_inputs.w <= 0.0 ||
      frag_info.camera_forward.w <= 0.0) {
    return v_position + v_viewvector +
           frag_info.camera_forward.xyz * kSceneDepthUnavailable;
  }
  vec2 uv = clamp(GetScreenUv() + uv_offset, vec2(0.001), vec2(0.999));
  float view_z = texture(scene_depth, uv).r;
  // Screen UV back to view-space offsets at that depth (V grows downward).
  float view_x = (uv.x * 2.0 - 1.0) * view_z * frag_info.scene_inputs.w;
  float view_y = (1.0 - uv.y * 2.0) * view_z * frag_info.camera_forward.w;
  vec3 camera_position = v_position + v_viewvector;
  return camera_position + frag_info.camera_forward.xyz * view_z +
         frag_info.camera_right.xyz * view_x +
         frag_info.camera_up.xyz * view_y;
}
#endif

#endif  // MATERIAL_SCENE_INPUTS_GLSL_
