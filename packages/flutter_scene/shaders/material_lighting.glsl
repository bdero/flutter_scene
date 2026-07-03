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
  float inv_count = 1.0 / float(count);

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
  float n_dot_l = 0.0;
  float geometric_n_dot_l = 0.0;
  vec3 light_vector = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    light_vector = -normalize(frag_info.directional_light_direction.xyz);
    n_dot_l = dot(normal, light_vector);
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
  // ambient term).
  vec3 direct = vec3(0.0);
  if (frag_info.has_directional_light > 0.5 && n_dot_l > 0.0) {
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
             n_dot_l * shadow;
  }

  vec3 emissive = material.emissive;

  // Linear HDR, premultiplied by alpha. Exposure, the tone-mapping
  // operator, and display encoding are applied later by the tone-mapping
  // resolve pass (see flutter_scene_resolve.frag), so this writes into a
  // floating-point scene-color target.
  vec3 out_color = ambient + direct + emissive;
  return ApplyFog(vec4(out_color, 1.0) * alpha);
}
