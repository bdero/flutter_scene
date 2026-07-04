// The engine lighting framework. Takes a MaterialInputs filled by a material's
// Surface() function and produces the final fragment color: image-based
// lighting (diffuse SH + prefiltered radiance + split-sum BRDF with
// multiscatter compensation), a single analytic directional light with
// cascaded soft shadows, emissive, and the linear-HDR premultiplied-alpha
// output contract (exposure and tone mapping run later in the resolve pass).
//
// Requires, declared before this file is included: the FragInfo uniform block
// (as `frag_info`), the world-space varyings `v_position` and `v_viewvector`,
// the `prefiltered_radiance`, `brdf_lut`, and `shadow_map` samplers, the
// MaterialInputs struct (material_inputs.glsl), and pbr.glsl + texture.glsl.

// Distance fog (the FogInfo block + ApplyFog), applied to the final lit color.
#include <fog.glsl>

// Evaluates the L2 diffuse-irradiance SH polynomial in direction `n`.
// The coefficients already include the cosine convolution and 1/pi, so
// the result is E(n)/pi. Must use the same real-SH basis the CPU-side
// projection in EnvironmentMap.computeDiffuseSphericalHarmonics uses.
// Fetches SH coefficient i (0..8) from a 9x1 coefficient texture.
vec3 DiffuseShCoefficient(sampler2D coefficients, float i) {
  return texture(coefficients, vec2((i + 0.5) / 9.0, 0.5)).xyz;
}

vec3 EvaluateDiffuseSH(sampler2D coefficients, vec3 n) {
  return DiffuseShCoefficient(coefficients, 0.0) * 0.282095 +
         DiffuseShCoefficient(coefficients, 1.0) * (0.488603 * n.y) +
         DiffuseShCoefficient(coefficients, 2.0) * (0.488603 * n.z) +
         DiffuseShCoefficient(coefficients, 3.0) * (0.488603 * n.x) +
         DiffuseShCoefficient(coefficients, 4.0) * (1.092548 * n.x * n.y) +
         DiffuseShCoefficient(coefficients, 5.0) * (1.092548 * n.y * n.z) +
         DiffuseShCoefficient(coefficients, 6.0) *
             (0.315392 * (3.0 * n.z * n.z - 1.0)) +
         DiffuseShCoefficient(coefficients, 7.0) * (1.092548 * n.x * n.z) +
         DiffuseShCoefficient(coefficients, 8.0) *
             (0.546274 * (n.x * n.x - n.y * n.y));
}

// One rotated Poisson-disk PCF tap into a cascade's atlas tile. Factored out
// so the kernel can be unrolled with inline literals at the call site (see the
// note in SampleCascade); the compiler inlines this.
float ShadowTap(vec2 p, float ca, float sa, float radius, vec2 uv, int cascade,
                float inv_count, float receiver_depth) {
  vec2 offset = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * radius;
  // Keep samples a texel inside this cascade's tile, so bilinear filtering of
  // the atlas never reaches across the tile boundary into a neighbouring
  // cascade's depths.
  vec2 cuv = clamp(uv + offset, vec2(frag_info.shadow_texel_size),
                   vec2(1.0 - frag_info.shadow_texel_size));
  vec2 atlas_uv = vec2((float(cascade) + cuv.x) * inv_count, cuv.y);
  // The shadow atlas is a render-to-texture target stored top-down. NDC->UV
  // (proj.xy * 0.5 + 0.5) maps NDC-top to v=1, but a top-down texture's top row
  // is v=0, so flip V to sample the matching row. This is intrinsic to the
  // top-down storage (not a backend Y-flip workaround), so it is unconditional.
  atlas_uv.y = 1.0 - atlas_uv.y;
  float caster_depth = texture(shadow_map, atlas_uv).r;
  return receiver_depth <= caster_depth ? 1.0 : 0.0;
}

// Samples one cascade's tile of the shadow atlas strip with a rotated
// 16-tap Poisson-disk PCF. `world_pos` and `n` are world-space.
float SampleCascade(int cascade, int count, mat4 cascade_matrix, float box,
                    vec3 world_pos, vec3 n) {
  // Normal-offset bias. A soft PCF kernel on a surface tilted relative
  // to the light straddles a depth gradient and would self-shadow, so
  // lift the receiver along its normal far enough that the whole kernel
  // clears the surface. The offset scales with the kernel's world
  // radius (shadow_softness) and the surface's slope to the light. It
  // depends only on geometry, not the cascade, so all cascades agree
  // and there is no banding at their seams.
  vec3 light_toward = -normalize(frag_info.directional_light_direction.xyz);
  float ndotl = max(dot(n, light_toward), 0.15);
  float slope = min(sqrt(max(1.0 - ndotl * ndotl, 0.0)) / (ndotl * ndotl),
                    8.0);
  float normal_offset =
      frag_info.shadow_normal_bias + frag_info.shadow_softness * slope;
  vec3 biased = world_pos + n * normal_offset;

  vec4 light_clip = cascade_matrix * vec4(biased, 1.0);
  vec3 proj = light_clip.xyz / light_clip.w;
  vec2 uv = proj.xy * 0.5 + 0.5;
  // The depth bias is world-space; convert it to this cascade's clip-z (its
  // orthographic depth range is 7 * box: the toward-sun reach + forward margin
  // in light.dart, _casterReachRadii + _forwardMarginRadii, over the half-width
  // that makes box) so a caster crosses the shadow threshold at the same world
  // height in every cascade, with no discontinuity where cascades meet.
  float receiver_depth = proj.z - frag_info.shadow_bias / (7.0 * box);

  // World-space penumbra -> this cascade's UV space, floored at a texel.
  float radius =
      max(frag_info.shadow_softness / box, frag_info.shadow_texel_size);
  // The atlas also holds spot-shadow tiles after the cascades, so normalize the
  // atlas-x by the total tile count. Spot count 0 leaves this at 1 / cascades.
  float inv_count = 1.0 / (float(count) + frag_info.spot_shadow_params.x);

  // A per-fragment rotation hides the 16-tap pattern as a smooth edge.
  float noise = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  float angle = noise * 6.28318530718;
  float ca = cos(angle);
  float sa = sin(angle);

  // 16-tap Poisson-disk PCF, unrolled with the kernel as inline literals.
  //
  // TODO(flutter_scene): this would naturally loop over a file-scope
  // `const vec2 kPoissonDisk[16] = vec2[](...)`, but *any* const array (even
  // one filled element by element, which the SPIR-V optimizer folds back into
  // a constant) makes impellerc/SPIRV-Cross emit a GLSL array constructor
  // (`vec2[](...)`) in its `#version 100` GLES output. That is invalid
  // ES 1.00, so the shader fails to compile on conformant ES drivers
  // (e.g. Mesa/llvmpipe under headless CI); lenient drivers accept it. Flutter
  // GPU shaders should compile anywhere Flutter runs, so the real fix belongs
  // upstream (impellerc should emit valid ES 1.00, or the bundle's GLES stage
  // should target ES 3.00). Restore the const-array loop once that lands.
  // See: <upstream issue>.
#define _SHADOW_TAP(px, py) \
  ShadowTap(vec2(px, py), ca, sa, radius, uv, cascade, inv_count, \
            receiver_depth)
  float lit = 0.0;
  lit += _SHADOW_TAP(-0.94201624, -0.39906216);
  lit += _SHADOW_TAP(0.94558609, -0.76890725);
  lit += _SHADOW_TAP(-0.09418410, -0.92938870);
  lit += _SHADOW_TAP(0.34495938, 0.29387760);
  lit += _SHADOW_TAP(-0.91588581, 0.45771432);
  lit += _SHADOW_TAP(-0.81544232, -0.87912464);
  lit += _SHADOW_TAP(-0.38277543, 0.27676845);
  lit += _SHADOW_TAP(0.97484398, 0.75648379);
  lit += _SHADOW_TAP(0.44323325, -0.97511554);
  lit += _SHADOW_TAP(0.53742981, -0.47373420);
  lit += _SHADOW_TAP(-0.26496911, -0.41893023);
  lit += _SHADOW_TAP(0.79197514, 0.19090188);
  lit += _SHADOW_TAP(-0.24188840, 0.99706507);
  lit += _SHADOW_TAP(-0.81409955, 0.91437590);
  lit += _SHADOW_TAP(0.19984126, 0.78641367);
  lit += _SHADOW_TAP(0.14383161, -0.14100790);
#undef _SHADOW_TAP
  float shadow = lit / 16.0;

  // Only the last cascade has a real outer edge (inner cascades hand
  // off to the next), so fade just it back to lit at the boundary.
  if (cascade == count - 1 && frag_info.shadow_fade > 0.0) {
    float fade = frag_info.shadow_fade / box;
    vec2 edge = smoothstep(vec2(0.0), vec2(fade), uv) *
                smoothstep(vec2(0.0), vec2(fade), vec2(1.0) - uv);
    shadow = mix(1.0, shadow, edge.x * edge.y);
  }
  return shadow;
}

// Soft cascaded-shadow lookup. Returns 1.0 (lit) .. 0.0 (fully
// shadowed). `world_pos` and `n` are world-space; `n` is the
// (perturbed) shading normal. Picks the first (highest-resolution)
// cascade whose box contains the fragment.
// Tries cascade IDX (a literal): if the fragment lies inside its tile with
// room for the PCF kernel, samples it and marks `found`. IDX is a literal so
// no uniform array or vector is indexed with a dynamic index (invalid in GLSL
// ES 1.00, and misread for indices past the first by some GLES drivers).
#define _TRY_CASCADE(IDX)                                                    \
  if (!found && count > IDX) {                                               \
    mat4 cascade_matrix = frag_info.light_space_matrix[IDX];                 \
    float box = frag_info.cascade_box_sizes[IDX];                            \
    vec4 light_clip = cascade_matrix * vec4(world_pos, 1.0);                 \
    vec3 proj = light_clip.xyz / light_clip.w;                              \
    vec2 uv = proj.xy * 0.5 + 0.5;                                           \
    float margin =                                                          \
        max(frag_info.shadow_softness / box, frag_info.shadow_texel_size);   \
    if (!(uv.x < margin || uv.x > 1.0 - margin || uv.y < margin ||          \
          uv.y > 1.0 - margin || proj.z < 0.0 || proj.z > 1.0)) {           \
      result = SampleCascade(IDX, count, cascade_matrix, box, world_pos, n); \
      found = true;                                                          \
    }                                                                        \
  }

float SampleShadow(vec3 world_pos, vec3 n) {
  int count = int(frag_info.shadow_cascade_count);
  // Unrolled with literal cascade indices: see _TRY_CASCADE. A single `return`
  // (no early return inside a loop) also avoids a nested-loop pattern that
  // crashes a Direct3D shader compiler.
  float result = 1.0;
  bool found = false;
  _TRY_CASCADE(0)
  _TRY_CASCADE(1)
  _TRY_CASCADE(2)
  _TRY_CASCADE(3)
  return result;
}
#undef _TRY_CASCADE

// Empirical specular occlusion derived from the diffuse occlusion factor,
// the view angle, and roughness (Lagarde and de Rousiers 2014, "Physically
// Based Rendering" course notes). Rough surfaces are returned unchanged;
// smoother surfaces lose indirect specular at normal incidence. Applied
// only to indirect specular.
float ComputeSpecularOcclusion(float n_dot_v, float occlusion,
                               float roughness) {
  return clamp(
      pow(n_dot_v + occlusion, exp2(-16.0 * roughness - 1.0)) - 1.0 +
          occlusion,
      0.0, 1.0);
}

// The number of additional analytic lights (point, spot, and directional
// lights past the first) the loop below can shade in one draw. Must match
// kMaxPunctualLights in lib/src/render/punctual_lights.dart. The loop is
// unrolled to this constant bound because GLSL ES 1.00 requires a compile-time
// loop bound; the active count (frag_info.radiance_blend.z) ends it early.
#define MAX_PUNCTUAL_LIGHTS 16

// Reads column `col` (0..7) of light `light_index`'s row from the
// punctual_lights parameters texture (8 texels wide, punctual_dims.x rows
// tall). Fetched by computed UV rather than a dynamically-indexed uniform
// array, which a GLSL ES 1.00 fragment shader may not do.
vec4 FetchPunctualTexel(int light_index, int col) {
  // 8 texels per light row: 0.0625 = 0.5 / 8 centers the first column.
  vec2 uv = vec2((float(col) + 0.5) * 0.125,
                 (float(light_index) + 0.5) / frag_info.punctual_dims.x);
  return texture(punctual_lights, uv);
}

// Reads entry `j` of the per-object light-index buffer, returning the light row
// it points at. The buffer is a 2D texture (index in .r); `j` is decomposed to
// a texel with the width/height in punctual_dims.yz.
float FetchPunctualIndex(int j) {
  float width = frag_info.punctual_dims.y;
  float fj = float(j);
  vec2 uv = vec2((mod(fj, width) + 0.5) / width,
                 (floor(fj / width) + 0.5) / frag_info.punctual_dims.z);
  return texture(punctual_index, uv).r;
}

// One analytic light's Cook-Torrance contribution. `light_vector` points from
// the surface toward the light (unit length); `radiance` is the light color
// premultiplied by intensity and any distance/cone attenuation. Returns the
// linear direct term; the caller multiplies in any shadow visibility. Shared by
// the directional light and every punctual light so the BRDF lives in one place.
vec3 EvaluateAnalyticLight(vec3 light_vector, vec3 radiance, vec3 normal,
                           vec3 camera_normal, vec3 albedo, float metallic,
                           float roughness, vec3 reflectance, float n_dot_v) {
  float n_dot_l = max(dot(normal, light_vector), 0.0);
  if (n_dot_l <= 0.0) {
    return vec3(0.0);
  }
  vec3 half_vector = normalize(light_vector + camera_normal);
  float n_dot_v_safe = max(n_dot_v, 1e-4);
  float distribution = DistributionGGX(normal, half_vector, roughness);
  float visibility =
      VisibilitySmithGGXCorrelated(n_dot_v_safe, n_dot_l, roughness);
  vec3 specular_fresnel =
      FresnelSchlick(max(dot(half_vector, camera_normal), 0.0), reflectance);
  // `visibility` already folds in 1 / (4 * NoL * NoV).
  vec3 specular = distribution * visibility * specular_fresnel;
  vec3 diffuse =
      (vec3(1.0) - specular_fresnel) * (1.0 - metallic) * albedo * (1.0 / kPi);
  return (diffuse + specular) * radiance * n_dot_l;
}

// One shadow comparison tap for a spot: places the in-tile `uv` in the spot's
// atlas tile (`tile` of `total`, stored top-down so V is flipped) and returns 1
// lit / 0 shadowed. `uv` is clamped into the tile so the kernel never reads a
// neighbouring tile (the atlas is nearest-sampled, so there is no bilinear
// bleed once it stays in-tile).
float SpotShadowTap(vec2 uv, float tile, float total, float receiver) {
  vec2 atlas_uv = vec2((tile + clamp(uv.x, 0.0, 1.0)) / total,
                       1.0 - clamp(uv.y, 0.0, 1.0));
  return receiver <= texture(shadow_map, atlas_uv).r ? 1.0 : 0.0;
}

// Number of ring taps around the center for the spot-shadow PCF.
#define SPOT_PCF_RING 8

// Spot-shadow visibility (1 lit .. 0 shadowed) for the shadow-casting spot in
// row `light_row`, slot `slot`. Its world -> spot-clip matrix rides in the
// light's own params row (texels 4-7); its shadow tile follows the directional
// cascades in the shared atlas. A center tap plus a per-fragment-rotated ring
// (radius from spot_shadow_params.w, the softness) gives a soft penumbra; a
// softness of 0 collapses the kernel to a hard edge. Fragments outside the spot
// frustum read as lit (the cone attenuation already zeroed them).
float SampleSpotShadow(int light_row, int slot, vec3 world_pos, vec3 normal) {
  mat4 m = mat4(FetchPunctualTexel(light_row, 4), FetchPunctualTexel(light_row, 5),
                FetchPunctualTexel(light_row, 6), FetchPunctualTexel(light_row, 7));
  vec4 clip = m * vec4(world_pos + normal * frag_info.spot_shadow_params.z, 1.0);
  if (clip.w <= 0.0) {
    return 1.0;
  }
  vec3 proj = clip.xyz / clip.w;
  vec2 uv = proj.xy * 0.5 + 0.5;
  if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0 || proj.z < 0.0 ||
      proj.z > 1.0) {
    return 1.0;
  }
  float total = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
  float tile = frag_info.shadow_cascade_count + float(slot);
  float receiver = proj.z - frag_info.spot_shadow_params.y;
  // Penumbra radius in tile-UV (resolution-independent). softness 0 = hard.
  float radius = frag_info.spot_shadow_params.w * 0.004;

  float lit = SpotShadowTap(uv, tile, total, receiver);
  // A per-fragment rotation hides the ring pattern as a smooth edge.
  float noise = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  float base = noise * 6.28318530718;
  for (int i = 0; i < SPOT_PCF_RING; i++) {
    float a = base + float(i) * (6.28318530718 / float(SPOT_PCF_RING));
    vec2 offset = vec2(cos(a), sin(a)) * radius;
    lit += SpotShadowTap(uv + offset, tile, total, receiver);
  }
  return lit / float(SPOT_PCF_RING + 1);
}

// Lights a surface described by `material` and returns the final fragment
// color (linear HDR, premultiplied by alpha). This is the engine-owned half of
// the material contract; a material's Surface() function fills `material` and
// main() calls this.
vec4 EvaluateLighting(MaterialInputs material) {
  vec3 albedo = material.base_color.rgb;
  float alpha = material.base_color.a;
  vec3 normal = material.normal;
  float metallic = material.metallic;
  float roughness = material.roughness;

  // Geometric specular antialiasing (Kaplanyan/Tokuyoshi). A
  // normal map or high-curvature surface carries more normal detail than a
  // pixel can resolve; the specular lobe turns that sub-pixel variation into
  // shimmering highlights. Estimate the variation from the screen-space
  // derivatives of the shading normal and widen the roughness so the lobe is
  // averaged over the pixel's cone of normals. The condition is on a uniform,
  // so the derivatives are evaluated under uniform control flow.
  if (frag_info.specular_aa_variance > 0.0) {
    vec3 d_normal_x = dFdx(normal);
    vec3 d_normal_y = dFdy(normal);
    float variance = frag_info.specular_aa_variance *
                     (dot(d_normal_x, d_normal_x) + dot(d_normal_y, d_normal_y));
    float kernel = min(2.0 * variance, frag_info.specular_aa_threshold);
    // Widen in the squared-roughness (alpha) domain, then convert back:
    // alpha = roughness^2, so roughness^4 is the alpha^2 the kernel adds to.
    float widened = clamp(roughness * roughness * roughness * roughness + kernel,
                          0.0, 1.0);
    roughness = clamp(sqrt(sqrt(widened)), kMinRoughness, 1.0);
  }

  // Diffuse occlusion: the material's (baked) occlusion modulated by the
  // screen-space ambient occlusion when it is enabled. Occlusion only ever
  // affects indirect lighting, never the analytic direct light below.
  float occlusion = material.occlusion;
  if (frag_info.ssao_params.x > 0.5) {
    vec2 screen_uv = gl_FragCoord.xy * frag_info.ssao_params.zw;
    // TODO(flutter_scene): the occlusion target is stored top-down like the
    // other render-to-texture targets, which matches gl_FragCoord here. If a
    // backend reports gl_FragCoord with a flipped origin, this sample needs
    // screen_uv.y = 1.0 - screen_uv.y; verify against the depth prepass on
    // each backend.
    occlusion *= texture(ssao_texture, screen_uv).r;
  }

  vec3 camera_normal = normalize(v_viewvector);

  vec3 reflectance = mix(vec3(0.04), albedo, metallic);

  // 1 when the surface is facing the camera, 0 when it's perpendicular to the
  // camera.
  float n_dot_v = max(dot(normal, camera_normal), 0.0);

  // The view angle for the image-based specular energy (Fresnel and the split-
  // sum LUT) uses the geometric normal, not the perturbed one. That energy term
  // is a macro-surface quantity, and near grazing the Fresnel is steep, so
  // feeding it the normal-mapped n_dot_v turns sub-pixel normal detail into a
  // blotchy brightness aliasing. The reflection direction below still uses the
  // perturbed normal, so surface relief is preserved where it belongs.
  float n_dot_v_energy = max(dot(GetWorldNormal(), camera_normal), 0.0);

  // reflect() needs the incident ray (camera -> surface); camera_normal
  // points surface -> camera, so negate it. Sampling the environment with
  // the un-negated vector would mirror reflections to the opposite side.
  vec3 reflection_normal = reflect(-camera_normal, normal);

  // Roughness-dependent Fresnel reflectance for the indirect specular lobe.
  vec3 k_S = FresnelSchlickRoughness(n_dot_v_energy, reflectance, roughness);

  // The IBL environment can be rotated; transform the lookup directions.
  mat3 environment_transform = mat3(frag_info.environment_transform);
  vec3 env_normal = environment_transform * normal;
  vec3 env_reflection = environment_transform * reflection_normal;
  vec3 irradiance = max(EvaluateDiffuseSH(sh_coefficients, env_normal),
                        vec3(0.0));
  vec3 prefiltered_color =
      SampleRadianceEnv(prefiltered_radiance, prefiltered_radiance_cube,
                        env_reflection, roughness);
  // Cross-fade a secondary environment in (area transitions) when active. Both
  // share the bound layout, so the same samplers' _b pair is read.
  float env_blend = frag_info.radiance_blend.x;
  if (env_blend > 0.0) {
    vec3 irradiance_b = max(EvaluateDiffuseSH(sh_coefficients_b, env_normal),
                            vec3(0.0));
    vec3 prefiltered_b =
        SampleRadianceEnv(prefiltered_radiance_b, prefiltered_radiance_cube_b,
                          env_reflection, roughness);
    irradiance = mix(irradiance, irradiance_b, env_blend);
    prefiltered_color = mix(prefiltered_color, prefiltered_b, env_blend);
  }
  irradiance *= frag_info.environment_intensity;
  prefiltered_color *= frag_info.environment_intensity;

  // Split-sum DFG terms (Karis '13) from the RGBA16F environment-BRDF LUT
  // (scale in R, bias in G), indexed by (n_dot_v, roughness) with roughness up
  // the V axis; sampled slightly inside [0, 1] to avoid edge-tap artifacts.
  vec2 f_ab = texture(
                  brdf_lut,
                  clamp(vec2(n_dot_v_energy, roughness), 0.0, 0.99))
                  .rg;

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
  // Occluding indirect specular with the diffuse factor over-darkens glossy
  // reflections, so derive a dedicated specular occlusion when it is
  // enabled; otherwise the specular lobe uses the same occlusion (the
  // historical behavior).
  float specular_occlusion = frag_info.ssao_params.y > 0.5
      ? ComputeSpecularOcclusion(n_dot_v, occlusion, roughness)
      : occlusion;
  // Sun direction and how squarely this surface faces it. `facing` ramps from
  // 0 (at or past the terminator) to 1 (sun-facing) over a small band, so the
  // sun's influence falls off smoothly rather than at a hard line.
  float geometric_n_dot_l = 0.0;
  vec3 light_vector = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    light_vector = -normalize(frag_info.directional_light_direction.xyz);
    geometric_n_dot_l = dot(GetWorldNormal(), light_vector);
  }
  // Whether the surface faces the sun is a geometric property, so gate the
  // shadow terms on the geometric normal. Using the perturbed normal lets a
  // normal map's relief push n_dot_l across the terminator on a nearly sun-
  // facing face (worst near a low sun), spuriously darkening the shadow-ambient
  // term on bumpy top faces.
  float facing = clamp(geometric_n_dot_l / 0.15, 0.0, 1.0);

  // Sun-shadow visibility (1 lit .. 0 shadowed). The shadow map is only
  // meaningful for sun-facing surfaces; a back face receives no sun by
  // definition, so it is treated as fully shadowed (facing = 0) without a
  // shadow-map lookup, whose normal-offset bias assumes a sun-facing receiver
  // and would otherwise stripe the back face with acne.
  float shadow =
      (frag_info.has_directional_light > 0.5 && frag_info.casts_shadow > 0.5 &&
       facing > 0.0)
          ? SampleShadow(v_position, GetWorldNormal())
          : 1.0;
  float sun_visibility = facing * shadow;

  // When shadow_ambient_strength (radiance_blend.y) is non-zero, the sun's
  // occlusion also darkens the IBL ambient: a sky-baked environment already
  // contains the sun's energy, so the ambient alone otherwise reads as fully
  // lit inside shadows.
  float ambient_shadow = mix(1.0, sun_visibility, frag_info.radiance_blend.y);

  vec3 ambient =
      (indirect_diffuse * occlusion + indirect_specular * specular_occlusion) *
      ambient_shadow;

  // Analytic directional light (Cook-Torrance, layered on top of the IBL
  // ambient term). The shadowed first directional light shades here; its shadow
  // visibility multiplies the whole term.
  vec3 direct = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    direct = EvaluateAnalyticLight(light_vector,
                                   frag_info.directional_light_color.rgb, normal,
                                   camera_normal, albedo, metallic, roughness,
                                   reflectance, n_dot_v) *
             shadow;
  }

  // Additional analytic lights (point, spot, and directional lights past the
  // first); point lights do not cast shadows. The scene may hold any number of
  // lights; per-object culling gives this object a contiguous slice of the
  // light-index buffer, and the loop shades only that slice. The loop bound is
  // the compile-time per-object budget MAX_PUNCTUAL_LIGHTS; the object's count
  // ends it early. Every fetch is a computed-UV texture read, so no uniform
  // array is dynamically indexed.
  //
  // TODO(lighting): this stays a single uniform-gated loop. A per-draw
  // (per-object) punctual on/off permutation is rejected: it varies the pipeline
  // within a frame and defeats material-sorted batching, worst on tile GPUs. A
  // coarse (per-frame-global / capability-tier) permutation that compiles the
  // loop out for sun/IBL-only scenes is a possible low-end win, but only if the
  // never-entered loop is measured to cost occupancy on real hardware. Froxel
  // clustering is the high-end tier (no per-draw light state).
  // punctual_dims.x is the parameters-texture row count; 0 means the scene has
  // no punctual lights this frame, so ignore any stale per-object count (and
  // never divide by the zero texture height in the fetch helpers).
  int punctual_count =
      frag_info.punctual_dims.x < 0.5 ? 0 : int(frag_info.radiance_blend.z);
  int punctual_offset = int(frag_info.radiance_blend.w);
  for (int i = 0; i < MAX_PUNCTUAL_LIGHTS; i++) {
    if (i >= punctual_count) {
      break;
    }
    // Resolve this slot to a light row through the per-object index buffer.
    int light_row = int(FetchPunctualIndex(punctual_offset + i) + 0.5);
    vec4 l0 = FetchPunctualTexel(light_row, 0); // position.xyz, type
    vec4 l1 = FetchPunctualTexel(light_row, 1); // color.rgb, inverse range
    float type = l0.w;
    vec3 radiance = l1.rgb;
    vec3 punctual_light_vector;
    if (type < 0.5) {
      // Directional: the travel direction is in texel 2; no attenuation.
      punctual_light_vector = -normalize(FetchPunctualTexel(light_row, 2).xyz);
    } else {
      vec3 to_light = l0.xyz - v_position;
      float dist_sq = dot(to_light, to_light);
      punctual_light_vector = to_light * inversesqrt(max(dist_sq, 1e-8));
      // Windowed inverse-square distance falloff: with an inverse range of 0
      // (infinite range) the window is 1 and this is a pure inverse square,
      // clamped near the source.
      float inv_range = l1.w;
      float factor = dist_sq * inv_range * inv_range;
      float window = clamp(1.0 - factor * factor, 0.0, 1.0);
      radiance *= (window * window) / max(dist_sq, 1e-4);
      if (type > 1.5) {
        // Spot cone: a squared linear ramp on the cosine between the inner and
        // outer cone, using the precomputed scale (texel 2 w) and offset.
        vec4 l2 = FetchPunctualTexel(light_row, 2); // direction.xyz, angular scale
        vec4 l3 = FetchPunctualTexel(light_row, 3); // spot offset, shadow slot
        float cd = dot(normalize(l2.xyz), -punctual_light_vector);
        float cone = clamp(cd * l2.w + l3.x, 0.0, 1.0);
        radiance *= cone * cone;
        // Spot shadow, when this spot has a slot in the shared atlas. Gate on
        // the geometric normal (the shadow is a geometric property).
        if (l3.y > -0.5 && frag_info.spot_shadow_params.x > 0.5) {
          radiance *= SampleSpotShadow(
              light_row, int(l3.y + 0.5), v_position, GetWorldNormal());
        }
      }
    }
    direct += EvaluateAnalyticLight(punctual_light_vector, radiance, normal,
                                    camera_normal, albedo, metallic, roughness,
                                    reflectance, n_dot_v);
  }

  vec3 emissive = material.emissive;

  // Linear HDR, premultiplied by alpha. Exposure, the tone-mapping
  // operator, and display encoding are applied later by the tone-mapping
  // resolve pass (see flutter_scene_resolve.frag), so this writes into a
  // floating-point scene-color target.
  vec3 out_color = ambient + direct + emissive;

  // Sky-colored fog: when active, sample the environment in the view direction
  // (rotated by the same environment_transform, cross-faded like the IBL, and
  // scaled by environment_intensity) so far geometry dissolves into the sky
  // behind it, matching the unfogged skybox at the horizon. Only sampled when
  // fog and its sky-color influence are on, so it is free otherwise.
  vec3 sky_fog_color = fog.color.rgb;
  if (fog.params0.y > 0.5 && fog.params0.w > 0.0) {
    // Sample the sharpest prefiltered level: the fog color should match the
    // crisp skybox as closely as the environment resolution allows, so avoid
    // extra roughness blur on top of the bake.
    const float kSkyFogRoughness = 0.0;
    vec3 sky_dir = environment_transform * normalize(-v_viewvector);
    sky_fog_color = SampleRadianceEnv(
        prefiltered_radiance, prefiltered_radiance_cube, sky_dir,
        kSkyFogRoughness);
    if (env_blend > 0.0) {
      sky_fog_color = mix(
          sky_fog_color,
          SampleRadianceEnv(prefiltered_radiance_b, prefiltered_radiance_cube_b,
                            sky_dir, kSkyFogRoughness),
          env_blend);
    }
    sky_fog_color *= frag_info.environment_intensity;
  }
  return ApplyFog(vec4(out_color, 1.0) * alpha, sky_fog_color);
}
