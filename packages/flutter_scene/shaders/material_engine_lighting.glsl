// The engine lighting inputs a lit material receives: the image-based-lighting
// and shadow samplers, plus the shared FragInfo block it pulls in from
// material_scene_inputs.glsl (the analytic light, shadow cascades, and the SH
// and environment data all ride that block). material_lighting.glsl reads these
// to evaluate the lit color. The standard PBR shader and every generated lit
// `.fmat` material share this single declaration of the engine lighting
// interface.

#include <material_scene_inputs.glsl>

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

