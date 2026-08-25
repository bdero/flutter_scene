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
#include <octahedral.glsl>
// The baked lightmap. Included only where it is used, so a plain lit entry
// compiles to exactly the same code it did before the slot existed.
#ifdef FLUTTER_SCENE_LIGHTMAP
#include <lightmap.glsl>
#endif

// Diffuse-irradiance spherical harmonics, fetched from rows 0 and 1 of the
// irradiance_field texture.
#include <diffuse_sh.glsl>
#ifndef FLUTTER_SCENE_LIGHTMAP
// The world-space irradiance field's atlas addressing and its receiver.
#include <irradiance_field.glsl>
#include <irradiance_receiver.glsl>
#endif

#include <material_shadow_sampling.glsl>

// Parallax-corrected reflection for a local environment probe: intersects
// the reflected ray with the probe's box proxy and re-aims the lookup from
// the capture point (the box center) at the hit, so reflections track the
// surfaces the probe captured instead of floating at infinity. Follows
// Lagarde and Zanuttini 2012, "Local Image-based Lighting With
// Parallax-corrected Cubemap" (SIGGRAPH). Returns [r] unchanged when no
// proxy is active.
vec3 ParallaxCorrectReflection(vec3 world_pos, vec3 r) {
  vec3 corrected = r;
  if (frag_info.probe_box.w > 0.5) {
    vec3 center = frag_info.probe_box.xyz;
    vec3 half_ext = frag_info.probe_extents.xyz;
    // Nudge zero components so the slab division stays finite.
    vec3 safe_r = r + (step(vec3(0.0), r) * 2.0 - 1.0) * 1e-6;
    vec3 inv_r = vec3(1.0) / safe_r;
    vec3 t_a = (center + half_ext - world_pos) * inv_r;
    vec3 t_b = (center - half_ext - world_pos) * inv_r;
    vec3 t_max = max(t_a, t_b);
    float t = min(min(t_max.x, t_max.y), t_max.z);
    vec3 hit = world_pos + r * max(t, 0.0);
    corrected = normalize(hit - center);
  }
  return corrected;
}

// Tile remaps for the shared brdf_lut atlas: the DFG terms in tile 0, the
// linearly-transformed-cosine matrix fit in tile 1, and its
// magnitude/Fresnel fit in tile 2.
vec2 DfgLutUv(vec2 uv) { return vec2(uv.x / 3.0, uv.y); }

vec2 LtcLutUv(vec2 uv, float tile) {
  // Half-texel bias inside a 64-wide tile so bilinear taps interpolate
  // between fitted samples without crossing tile boundaries.
  vec2 t = uv * (63.0 / 64.0) + 0.5 / 64.0;
  return vec2((t.x + tile) / 3.0, t.y);
}

// Rect area lights via linearly transformed cosines, following "Real-Time
// Polygonal-Light Shading with Linearly Transformed Cosines" (Heitz, Dupuy,
// Hill, Neubelt 2016). The edge integral uses the course-notes polynomial
// fit for theta / sin(theta); the horizon uses the closed-form
// clipped-sphere approximation, which trades exact clipping for a
// branch-free evaluation.
vec3 LtcEdgeVector(vec3 v1, vec3 v2) {
  float x = dot(v1, v2);
  float y = abs(x);
  float a = 0.8543985 + (0.4965155 + 0.0145206 * y) * y;
  float b = 3.4175940 + (4.1616724 + y) * y;
  float v = a / b;
  float theta_sintheta =
      x > 0.0 ? v : 0.5 * inversesqrt(max(1.0 - x * x, 1e-7)) - v;
  return cross(v1, v2) * theta_sintheta;
}

float LtcClippedSphere(vec3 f) {
  float l = length(f);
  return max((l * l + f.z) / (l + 1.0), 0.0);
}

// Integrates the transformed clamped-cosine over the rect [c0..c3] (counter
// clockwise seen from the lit side) as seen from point [p] with normal [n]
// and view direction [v].
float LtcIntegrate(vec3 n, vec3 v, vec3 p, mat3 inv_m, vec3 c0, vec3 c1,
                   vec3 c2, vec3 c3) {
  vec3 t1 = normalize(v - n * dot(v, n));
  vec3 t2 = -cross(n, t1);
  mat3 to_cosine = inv_m * transpose(mat3(t1, t2, n));
  vec3 l0 = normalize(to_cosine * (c0 - p));
  vec3 l1 = normalize(to_cosine * (c1 - p));
  vec3 l2 = normalize(to_cosine * (c2 - p));
  vec3 l3 = normalize(to_cosine * (c3 - p));
  vec3 form = LtcEdgeVector(l0, l1) + LtcEdgeVector(l1, l2) +
              LtcEdgeVector(l2, l3) + LtcEdgeVector(l3, l0);
  return LtcClippedSphere(form);
}

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

// Occludes indirect specular by intersecting the unoccluded-direction cone
// around the bent normal (aperture from the visibility) with the specular
// lobe's cone around the reflection vector (aperture from roughness). The
// arc overlap uses a linear approximation instead of the exact spherical-cap
// intersection (Jimenez et al. 2016, section 6).
float ComputeBentConeOcclusion(vec3 bent_normal, vec3 reflection,
                               float visibility, float roughness) {
  float vis_angle = acos(sqrt(clamp(1.0 - visibility, 0.0, 1.0)));
  float lobe_angle = max(
      acos(clamp(exp2(-3.32193 * roughness * roughness), 0.0, 1.0)), 0.1);
  float between = acos(clamp(dot(bent_normal, reflection), -1.0, 1.0));
  float overlap = clamp(
      (between - vis_angle + lobe_angle) / (2.0 * lobe_angle), 0.0, 1.0);
  return 1.0 - smoothstep(0.0, 1.0, overlap);
}

// Approximates the light that keeps bouncing inside an occluded cavity,
// tinted by the surface albedo, so occlusion converges toward the surface
// color instead of black (cubic fit from Jimenez et al. 2016, "Practical
// Realtime Strategies for Accurate Indirect Occlusion"). Applied only to
// indirect diffuse.
vec3 MultiBounceOcclusion(float visibility, vec3 albedo) {
  vec3 a = 2.0404 * albedo - 0.3324;
  vec3 b = -4.7951 * albedo + 0.6417;
  vec3 c = 2.7552 * albedo + 0.6903;
  return max(vec3(visibility),
             ((visibility * a + b) * visibility + c) * visibility);
}

// Widens a specular lobe to cover unresolved normal variation in one pixel.
float SpecularAARoughness(vec3 normal, float roughness) {
  // This toggle is a frame uniform, so the derivatives remain under uniform
  // control flow.
  if (frag_info.specular_aa_variance <= 0.0) {
    return roughness;
  }
  vec3 d_normal_x = dFdx(normal);
  vec3 d_normal_y = dFdy(normal);
  float variance = frag_info.specular_aa_variance *
                   max(dot(d_normal_x, d_normal_x),
                       dot(d_normal_y, d_normal_y));
  float kernel = min(2.0 * variance, frag_info.specular_aa_threshold);
  float square_roughness =
      clamp(roughness * roughness + kernel, kMinRoughness * kMinRoughness, 1.0);
  return sqrt(square_roughness);
}

#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
// One light's independent dielectric clearcoat lobe. The complete underlying
// material is attenuated by the view Fresnel only after every contribution has
// been accumulated.
vec3 EvaluateClearcoatLight(vec3 light_vector, vec3 radiance,
                            vec3 coat_normal, vec3 camera_normal,
                            float coat_roughness) {
  float n_dot_l = max(dot(coat_normal, light_vector), 0.0);
  if (n_dot_l <= 0.0) return vec3(0.0);

  vec3 h = light_vector + camera_normal;
  float h_len_sq = dot(h, h);
  if (h_len_sq <= 1e-8) return vec3(0.0);
  vec3 half_vector = h * inversesqrt(h_len_sq);
  float n_dot_v = max(dot(coat_normal, camera_normal), 1e-4);
  float distribution =
      DistributionGGX(coat_normal, half_vector, coat_roughness);
  float visibility = VisibilitySmithGGXCorrelated(
      n_dot_v, n_dot_l, coat_roughness);
  vec3 fresnel = FresnelSchlick(
      max(dot(half_vector, camera_normal), 0.0), vec3(0.04));
  return radiance * n_dot_l * distribution * visibility * fresnel;
}
#endif

// One analytic light's Cook-Torrance contribution. `light_vector` points from
// the surface toward the light (unit length); `radiance` is the light color
// premultiplied by intensity and any distance/cone attenuation. Returns the
// linear direct term; the caller multiplies in any shadow visibility. Shared by
// the directional light and every punctual light so the BRDF lives in one place.
vec3 EvaluateAnalyticLight(MaterialInputs material, vec3 light_vector,
                           vec3 radiance, vec3 normal,
                           vec3 camera_normal, vec3 albedo, float metallic,
                           float roughness, vec3 reflectance, float n_dot_v,
                           float specular_scale, vec3 anisotropic_tangent,
                           vec3 anisotropic_bitangent) {
  float signed_n_dot_l = dot(normal, light_vector);
  float n_dot_l = max(signed_n_dot_l, 0.0);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 transmitted_diffuse = material.diffuse_transmission_color *
                             (1.0 / kPi) * radiance *
                             max(-signed_n_dot_l, 0.0) *
                             material.diffuse_transmission;
#endif
  if (n_dot_l <= 0.0) {
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    return transmitted_diffuse;
#else
    return vec3(0.0);
#endif
  }
  float n_dot_v_safe = max(n_dot_v, 1e-4);
  // GetWorldNormal already faces the visible side, so back-side light exits
  // above. Strong normal-map perturbations can still let light_vector approach
  // -camera_normal while n_dot_l remains positive. Avoid normalizing that
  // degenerate half vector and introducing a NaN.
  vec3 h = light_vector + camera_normal;
  float h_len_sq = dot(h, h);
  vec3 specular = vec3(0.0);
  vec3 specular_fresnel = reflectance;
  if (h_len_sq > 1e-8) {
    vec3 half_vector = h * inversesqrt(h_len_sq);
    float distribution = DistributionGGX(normal, half_vector, roughness);
    float visibility =
        VisibilitySmithGGXCorrelated(n_dot_v_safe, n_dot_l, roughness);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    float anisotropy = clamp(material.anisotropy, 0.0, 1.0);
    if (anisotropy > 1e-4) {
      float alpha_b = max(roughness * roughness, 0.001);
      float alpha_t = mix(alpha_b, 1.0, anisotropy * anisotropy);
      distribution = DistributionGGXAnisotropic(
          normal, half_vector, anisotropic_tangent,
          anisotropic_bitangent, alpha_t, alpha_b);
      visibility = VisibilityGGXAnisotropic(
          n_dot_l, n_dot_v_safe,
          dot(anisotropic_tangent, camera_normal),
          dot(anisotropic_bitangent, camera_normal),
          dot(anisotropic_tangent, light_vector),
          dot(anisotropic_bitangent, light_vector), alpha_t, alpha_b);
    }
#endif
    specular_fresnel =
        FresnelSchlick(max(dot(half_vector, camera_normal), 0.0), reflectance);
    // `visibility` already folds in 1 / (4 * NoL * NoV).
    specular = distribution * visibility * specular_fresnel * specular_scale;
  }
  vec3 diffuse =
      (vec3(1.0) - specular_fresnel) * (1.0 - metallic) * albedo * (1.0 / kPi);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  float specular_transmission =
      clamp(material.transmission, 0.0, 1.0) * (1.0 - metallic);
  float total_transmission = clamp(
      material.diffuse_transmission + specular_transmission, 0.0, 1.0);
  diffuse *= 1.0 - total_transmission;
#endif
  vec3 result = (diffuse + specular) * radiance * n_dot_l;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  if (dot(material.sheen_color, material.sheen_color) > 0.0) {
    vec3 sheen_half = normalize(light_vector + camera_normal);
    float n_dot_h = max(dot(normal, sheen_half), 0.0);
    float sheen_distribution = DistributionCharlie(
        max(material.sheen_roughness, kMinRoughness), n_dot_h);
    float sheen_visibility = VisibilitySheen(
        n_dot_l, max(n_dot_v, 1e-4),
        max(material.sheen_roughness, kMinRoughness));
    result += material.sheen_color * sheen_distribution * sheen_visibility *
              radiance * n_dot_l;
  }
  result += transmitted_diffuse;
#endif
  return result;
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
  float roughness = SpecularAARoughness(normal, material.roughness);

#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 coat_normal = normalize(material.clearcoat_normal);
  float coat_roughness = SpecularAARoughness(
      coat_normal, material.clearcoat_roughness);
  float coat_n_dot_v = clamp(abs(dot(coat_normal, normalize(v_viewvector))),
                             0.0, 0.99);
  vec3 coat_direct = vec3(0.0);
  vec3 coat_ibl = vec3(0.0);
#endif

  // Diffuse occlusion: the material's (baked) occlusion modulated by the
  // screen-space ambient occlusion when it is enabled. Occlusion only ever
  // affects indirect lighting, never the analytic direct light below.
  float occlusion = material.occlusion;
  vec3 diffuse_occlusion = vec3(occlusion);
  vec3 ao_bent_normal = vec3(0.0);
  float ao_bent_valid = 0.0;
  vec4 ssao_sample = vec4(1.0);
#ifndef FLUTTER_SCENE_SKIP_SSAO
  if (frag_info.ssao_params.x > 0.5) {
    vec2 screen_uv = gl_FragCoord.xy * frag_info.ssao_params.zw;
    // TODO(flutter_scene): the occlusion target is stored top-down like the
    // other render-to-texture targets, which matches gl_FragCoord here. If a
    // backend reports gl_FragCoord with a flipped origin, this sample needs
    // screen_uv.y = 1.0 - screen_uv.y; verify against the depth prepass on
    // each backend.
    // Both terms estimate the same visibility. Multiplying them counts the
    // same blocked hemisphere twice and over-darkens surfaces with baked AO.
    ssao_sample = texture(ssao_texture, screen_uv);
    // With indirect light active the texture carries radiance in rgb and
    // visibility in a; otherwise visibility rides in r.
    occlusion = min(
        occlusion,
        frag_info.camera_up.w > 0.5 ? ssao_sample.a : ssao_sample.r);
    if (frag_info.ssao_lighting.z > 0.5 && frag_info.camera_up.w < 0.5) {
      // The packed view-space bent normal, rotated into world space with the
      // camera basis the depth prepass rendered from.
      vec3 bent_view = OctDecode(ssao_sample.ba);
      ao_bent_normal = normalize(
          frag_info.camera_right.xyz * bent_view.x +
          frag_info.camera_up.xyz * bent_view.y +
          frag_info.camera_forward.xyz * bent_view.z);
      ao_bent_valid = 1.0;
    }
    // Occluded creases keep albedo-tinted bounce light instead of darkening
    // to gray.
    diffuse_occlusion = mix(
        vec3(occlusion), MultiBounceOcclusion(occlusion, albedo),
        clamp(frag_info.ssao_lighting.y, 0.0, 1.0));
  }
#endif

  vec3 camera_normal = normalize(v_viewvector);

  vec3 anisotropic_tangent = vec3(1.0, 0.0, 0.0);
  vec3 anisotropic_bitangent = vec3(0.0, 1.0, 0.0);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 geometric_normal = GetWorldNormal();
  mat3 tangent_frame = TangentFrame(
      geometric_normal, -v_viewvector, material.anisotropy_uv);
  vec3 tangent_candidate =
      tangent_frame[0] * material.anisotropy_direction.x +
      tangent_frame[1] * material.anisotropy_direction.y;
  float tangent_length_squared = dot(tangent_candidate, tangent_candidate);
  if (tangent_length_squared > 1e-10) {
    anisotropic_tangent =
        tangent_candidate * inversesqrt(tangent_length_squared);
  } else if (abs(geometric_normal.z) < 0.999) {
    anisotropic_tangent =
        normalize(cross(vec3(0.0, 0.0, 1.0), geometric_normal));
  } else {
    anisotropic_tangent = vec3(1.0, 0.0, 0.0);
  }
  anisotropic_bitangent =
      normalize(cross(geometric_normal, anisotropic_tangent));
#endif

#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  float ior_f0 = pow((max(material.ior, 1.0) - 1.0) /
                         (max(material.ior, 1.0) + 1.0),
                     2.0);
  vec3 dielectric_reflectance = clamp(
      vec3(ior_f0) * material.specular_color * material.specular_weight,
      vec3(0.0), vec3(1.0));
#else
  // The standard path takes its dielectric F0 from the draw's FragInfo, the
  // same ior * specular_color * specular_weight product the physical path
  // forms above, precomputed on the CPU. A default material packs 0.04, so
  // a scalar ior or specular tweak no longer needs the physical shader.
  vec3 dielectric_reflectance = frag_info.dielectric_f0.xyz;
#endif
  vec3 reflectance = mix(dielectric_reflectance, albedo, metallic);

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
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  if (material.iridescence > 0.0) {
    reflectance = mix(
        reflectance,
        ThinFilmFresnel(reflectance, material.iridescence_ior,
                        material.iridescence_thickness, n_dot_v_energy),
        material.iridescence);
  }
#endif

  // reflect() needs the incident ray (camera -> surface); camera_normal
  // points surface -> camera, so negate it. Sampling the environment with
  // the un-negated vector would mirror reflections to the opposite side.
  vec3 reflection_normal = reflect(-camera_normal, normal);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  float anisotropy = clamp(material.anisotropy, 0.0, 1.0);
  vec3 anisotropic_normal =
      cross(cross(anisotropic_bitangent, camera_normal),
            anisotropic_bitangent);
  float anisotropic_normal_length_squared =
      dot(anisotropic_normal, anisotropic_normal);
  if (anisotropic_normal_length_squared > 1e-10) {
    anisotropic_normal *= inversesqrt(anisotropic_normal_length_squared);
  } else {
    anisotropic_normal = normal;
  }
  // Tighten the lookup toward the anisotropy direction for smooth, strongly
  // anisotropic surfaces while rough surfaces return toward the normal.
  // TODO(anisotropic-ibl): prefilter radiance for anisotropic GGX instead of
  // bending an isotropic lookup direction.
  float bend = 1.0 - anisotropy * (1.0 - roughness);
  bend *= bend;
  bend *= bend;
  vec3 bent_normal = normalize(mix(anisotropic_normal, normal, bend));
  reflection_normal = reflect(-camera_normal, bent_normal);
  reflection_normal = normalize(
      mix(reflection_normal, bent_normal, roughness * roughness));
#endif

  // Roughness-dependent Fresnel reflectance for the indirect specular lobe.
  vec3 k_S = FresnelSchlickRoughness(n_dot_v_energy, reflectance, roughness);

  // The IBL environment can be rotated; transform the lookup directions.
  // Irradiance samples along the bent normal when the occlusion chain
  // carries one: the SH lookup then ignores directions the screen-space
  // march found blocked. Geometric, so normal-map detail is dropped there,
  // which the smooth SH barely resolves anyway.
  mat3 environment_transform = mat3(frag_info.environment_transform);
  vec3 env_normal = environment_transform *
                    (ao_bent_valid > 0.5 ? ao_bent_normal : normal);
  vec3 env_reflection =
      environment_transform *
      ParallaxCorrectReflection(v_position, reflection_normal);
#ifdef FLUTTER_SCENE_LIGHTMAP
  // The bake already carries this surface's indirect diffuse, so it replaces
  // the SH ambient rather than adding to it. A bake has no direction, so the
  // back side reads the same value.
  vec3 irradiance = BakedDiffuseRadiance();
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 transmitted_irradiance = irradiance;
#endif
#else
  vec3 irradiance = max(EvaluateDiffuseSH(irradiance_field, env_normal, 0),
                        vec3(0.0));
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 transmitted_irradiance = max(
      EvaluateDiffuseSH(irradiance_field, -env_normal, 0), vec3(0.0));
#endif
#endif
  vec3 prefiltered_color =
      SampleRadianceEnv(prefiltered_radiance,
                        env_reflection, roughness);
  // Cross-fade a secondary environment in (area transitions) when active. Both
  // share the bound layout, so the same samplers' _b pair is read.
  float env_blend = frag_info.radiance_blend.x;
  if (env_blend > 0.0) {
#ifndef FLUTTER_SCENE_LIGHTMAP
    vec3 irradiance_b = max(EvaluateDiffuseSH(irradiance_field, env_normal, 1),
                            vec3(0.0));
#endif
    // env_reflection is box-corrected for the primary probe; the secondary
    // reuses it, so a probe->environment crossfade samples the secondary with
    // the probe's parallax vector. Transient and weight-blended, so
    // effectively invisible. TODO(probe-crossfade-parallax): box-correct the
    // secondary against its own volume.
    vec3 prefiltered_b =
        SampleRadianceEnv(prefiltered_radiance_b,
                          env_reflection, roughness);
    // A baked diffuse ambient belongs to the surface, not to either
    // environment, so only the specular lobe cross-fades here.
#ifndef FLUTTER_SCENE_LIGHTMAP
    irradiance = mix(irradiance, irradiance_b, env_blend);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    vec3 transmitted_irradiance_b = max(
        EvaluateDiffuseSH(irradiance_field, -env_normal, 1), vec3(0.0));
    transmitted_irradiance = mix(
        transmitted_irradiance, transmitted_irradiance_b, env_blend);
#endif
#endif
    prefiltered_color = mix(prefiltered_color, prefiltered_b, env_blend);
  }
  // environment_intensity scales the image-based lighting; a bake carries its
  // own lightmap_intensity instead.
#ifndef FLUTTER_SCENE_LIGHTMAP
  irradiance *= frag_info.environment_intensity;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  transmitted_irradiance *= frag_info.environment_intensity;
#endif
#endif
  prefiltered_color *= frag_info.environment_intensity;

#ifndef FLUTTER_SCENE_LIGHTMAP
  // The world-space irradiance field replaces the environment's diffuse term
  // inside its volume, so bounce light persists for surfaces off screen and
  // colored bleed reads correctly, and fades back to it across the outermost
  // cell. The field's own empty content is the environment, so an unfilled
  // field is exactly the image above and the transition is continuous.
  //
  // The lookup direction is the camera-invariant shading normal, never the
  // screen-derived bent normal: the visibility select is a hard boundary, so
  // a camera-dependent normal makes it flicker like z-fighting. The field's
  // stored radiance already carries the environment intensity, so it is not
  // scaled again here.
  float gi_coverage = IrradianceFieldCoverage(v_position);
  if (gi_coverage > 0.0) {
    vec3 gi = SampleIrradianceField(v_position, normal, camera_normal);
    irradiance = mix(irradiance, gi, gi_coverage);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    // TODO(gi-transmission): the transmitted direction repeats the whole
    // eight-tap cage. The weights only depend on the normal through the wrap
    // term, so one pass could return both lobes.
    vec3 gi_back = SampleIrradianceField(v_position, -normal, camera_normal);
    transmitted_irradiance = mix(transmitted_irradiance, gi_back, gi_coverage);
#endif
  }
#endif

  // Split-sum DFG terms (Karis '13) from the RGBA16F environment-BRDF LUT
  // (scale in R, bias in G), indexed by (n_dot_v, roughness) with roughness up
  // the V axis; sampled slightly inside [0, 1] to avoid edge-tap artifacts.
  vec2 f_ab = texture(
                  brdf_lut,
                  DfgLutUv(clamp(vec2(n_dot_v_energy, roughness), 0.0, 0.99)))
                  .rg;

  // Single- and multiple-scattering energy compensation (Fdez-Aguera 2019;
  // see https://bruop.github.io/ibl/). Without the multiscatter term, rough
  // metals lose noticeable energy.
  vec3 FssEss = k_S * f_ab.x + f_ab.y;
  float Ems = 1.0 - (f_ab.x + f_ab.y);
  vec3 F_avg = reflectance + (1.0 - reflectance) / 21.0;
  vec3 FmsEms = Ems * FssEss * F_avg / (1.0 - F_avg * Ems);
  vec3 diffuse_color = albedo * (1.0 - metallic);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  float specular_transmission =
      clamp(material.transmission, 0.0, 1.0) * (1.0 - metallic);
  float total_transmission = clamp(
      material.diffuse_transmission + specular_transmission, 0.0, 1.0);
  diffuse_color *= 1.0 - total_transmission;
#endif
  vec3 k_D = diffuse_color * (1.0 - FssEss + FmsEms);

  vec3 indirect_specular = FssEss * prefiltered_color * material.specular;
  vec3 indirect_diffuse = (FmsEms + k_D) * irradiance;
  // Occluding indirect specular with the diffuse factor over-darkens glossy
  // reflections, so derive a dedicated specular occlusion when it is
  // enabled; otherwise the specular lobe uses the same occlusion (the
  // historical behavior).
  float specular_occlusion;
  if (frag_info.ssao_params.y > 1.5 && ao_bent_valid > 0.5) {
    specular_occlusion = ComputeBentConeOcclusion(
        ao_bent_normal, reflect(-camera_normal, normal), occlusion, roughness);
  } else if (frag_info.ssao_params.y > 0.5) {
    specular_occlusion = ComputeSpecularOcclusion(n_dot_v, occlusion,
                                                  roughness);
  } else {
    specular_occlusion = occlusion;
  }
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
  float shadow = 1.0;
#ifndef FLUTTER_SCENE_SKIP_SHADOWS
  shadow =
      (frag_info.has_directional_light > 0.5 && frag_info.casts_shadow > 0.5 &&
       facing > 0.0)
          ? SampleShadow(v_position, GetWorldNormal())
          : 1.0;
#endif
#ifndef FLUTTER_SCENE_SKIP_SSAO
  // Screen-space contact shadow for the sun, marched by the occlusion pass.
  // Applies whether or not a shadow map is active, grounding small contacts
  // that shadow-map resolution and bias miss.
  if (frag_info.ssao_lighting.w > 0.5 && frag_info.camera_up.w < 0.5) {
    shadow = min(shadow, ssao_sample.g);
  }
#endif
  float sun_visibility = facing * shadow;

  // When shadow_ambient_strength (radiance_blend.y) is non-zero, the sun's
  // occlusion also darkens the IBL ambient: a sky-baked environment already
  // contains the sun's energy, so the ambient alone otherwise reads as fully
  // lit inside shadows.
  float ambient_shadow = mix(1.0, sun_visibility, frag_info.radiance_blend.y);

  vec3 ambient =
      (indirect_diffuse * diffuse_occlusion +
       indirect_specular * specular_occlusion) *
      ambient_shadow;
#ifndef FLUTTER_SCENE_SKIP_SSAO
  // Screen-space bounce: the occlusion pass's gathered radiance lights the
  // diffuse lobe. Its own bitfield already resolved visibility, so only the
  // baked occlusion map applies.
  if (frag_info.camera_up.w > 0.5) {
    ambient += ssao_sample.rgb * diffuse_color * material.occlusion;
  }
#endif
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  ambient += material.diffuse_transmission_color * (1.0 - metallic) *
             material.diffuse_transmission *
             transmitted_irradiance * occlusion * ambient_shadow;
  if (material.clearcoat > 0.0) {
    vec3 coat_reflection = reflect(-camera_normal, coat_normal);
    vec3 coat_prefiltered = SampleRadianceEnv(prefiltered_radiance,
        environment_transform * coat_reflection, coat_roughness);
    if (env_blend > 0.0) {
      vec3 coat_prefiltered_b = SampleRadianceEnv(prefiltered_radiance_b,
          environment_transform * coat_reflection, coat_roughness);
      coat_prefiltered = mix(coat_prefiltered, coat_prefiltered_b, env_blend);
    }
    vec2 coat_ab = texture(
        brdf_lut,
        DfgLutUv(vec2(coat_n_dot_v, min(coat_roughness, 0.99)))).rg;
    coat_ibl = coat_prefiltered *
               (vec3(0.04) * coat_ab.x + coat_ab.y) *
               frag_info.environment_intensity;
  }
  // TODO(sheen-ibl): replace this diffuse-scaled ambient term with a
  // preintegrated Charlie environment lobe and directional-albedo compensation.
  ambient += material.sheen_color * irradiance *
             (0.25 + 0.75 * (1.0 - n_dot_v_energy)) *
             (1.0 - 0.5 * material.sheen_roughness) * occlusion *
             ambient_shadow;
#endif

  // Analytic directional light (Cook-Torrance, layered on top of the IBL
  // ambient term). The shadowed first directional light shades here; its shadow
  // visibility multiplies the whole term.
  vec3 direct = vec3(0.0);
  if (frag_info.has_directional_light > 0.5) {
    direct = EvaluateAnalyticLight(material, light_vector,
                                   frag_info.directional_light_color.rgb, normal,
                                   camera_normal, albedo, metallic, roughness,
                                   reflectance, n_dot_v, material.specular,
                                   anisotropic_tangent,
                                   anisotropic_bitangent) *
             sun_visibility;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    coat_direct += EvaluateClearcoatLight(
        light_vector, frag_info.directional_light_color.rgb, coat_normal,
        camera_normal, coat_roughness) * sun_visibility;
#endif
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
    if (type > 2.5) {
      // Rect area light. Texel 2 carries the world right axis and width,
      // texel 3 the up axis and height; the light emits along
      // cross(right, up). The LTC form factor bakes in the cosine lobe and
      // inverse-square falloff, so only the range window applies here.
      vec4 a2 = FetchPunctualTexel(light_row, 2);
      vec4 a3 = FetchPunctualTexel(light_row, 3);
      vec3 half_w = a2.xyz * (a2.w * 0.5);
      vec3 half_h = a3.xyz * (a3.w * 0.5);
      vec3 c0 = l0.xyz - half_w - half_h;
      vec3 c1 = l0.xyz + half_w - half_h;
      vec3 c2 = l0.xyz + half_w + half_h;
      vec3 c3 = l0.xyz - half_w + half_h;
      vec3 to_center = l0.xyz - v_position;
      float dist_sq = dot(to_center, to_center);
      float factor = dist_sq * l1.w * l1.w;
      float window = clamp(1.0 - factor * factor, 0.0, 1.0);
      float facing =
          step(0.0, dot(cross(c1 - c0, c3 - c0), v_position - c0));
      vec2 ltc_uv = clamp(vec2(roughness, sqrt(1.0 - n_dot_v)), 0.0, 1.0);
      vec4 t1 = texture(brdf_lut, LtcLutUv(ltc_uv, 1.0));
      vec4 t2 = texture(brdf_lut, LtcLutUv(ltc_uv, 2.0));
      mat3 inv_m = mat3(
          vec3(t1.x, 0.0, t1.y), vec3(0.0, 1.0, 0.0), vec3(t1.z, 0.0, t1.w));
      float spec_shape = LtcIntegrate(
          normal, camera_normal, v_position, inv_m, c0, c1, c2, c3);
      float diff_shape = LtcIntegrate(
          normal, camera_normal, v_position, mat3(1.0), c0, c1, c2, c3);
      vec3 spec_color = reflectance * t2.x + (vec3(1.0) - reflectance) * t2.y;
      direct += radiance * (window * window) * facing *
                (spec_color * spec_shape * material.specular +
                 albedo * (1.0 - metallic) * diff_shape);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
      // The clearcoat's own LTC lobe over the same rect, with the coat's
      // normal and roughness and the dielectric F0 of 0.04. The base layer's
      // coat attenuation is applied once at the final composite.
      if (material.clearcoat > 0.0) {
        vec2 coat_ltc_uv = clamp(
            vec2(coat_roughness, sqrt(1.0 - coat_n_dot_v)), 0.0, 1.0);
        vec4 ct1 = texture(brdf_lut, LtcLutUv(coat_ltc_uv, 1.0));
        vec4 ct2 = texture(brdf_lut, LtcLutUv(coat_ltc_uv, 2.0));
        mat3 coat_inv_m = mat3(
            vec3(ct1.x, 0.0, ct1.y), vec3(0.0, 1.0, 0.0),
            vec3(ct1.z, 0.0, ct1.w));
        float coat_shape = LtcIntegrate(
            coat_normal, camera_normal, v_position, coat_inv_m,
            c0, c1, c2, c3);
        coat_direct += radiance * (window * window) * facing * coat_shape *
                       (0.04 * ct2.x + 0.96 * ct2.y);
      }
#endif
    } else {
    vec3 punctual_light_vector;
    if (type < 0.5) {
      // Directional: the travel direction is in texel 2; no attenuation.
      punctual_light_vector = -normalize(FetchPunctualTexel(light_row, 2).xyz);
    } else {
      vec3 to_light = l0.xyz - v_position;
      float dist_sq = dot(to_light, to_light);
      punctual_light_vector = to_light * inversesqrt(max(dist_sq, 1e-8));
      // Windowed distance falloff: with an inverse range of 0 (infinite
      // range) the window is 1. The falloff exponent (texel 3.z) is 2 for
      // the physical inverse square; lower exponents reach further without
      // brightening the near field (an artistic control), and pow(dist_sq,
      // e/2) = dist^e.
      float inv_range = l1.w;
      float factor = dist_sq * inv_range * inv_range;
      float window = clamp(1.0 - factor * factor, 0.0, 1.0);
      // spot offset, shadow slot, falloff exponent
      vec4 l3 = FetchPunctualTexel(light_row, 3);
      radiance *=
          (window * window) / max(pow(dist_sq, l3.z * 0.5), 1e-4);
      if (type > 1.5) {
        // Spot cone: a squared linear ramp on the cosine between the inner and
        // outer cone, using the precomputed scale (texel 2 w) and offset.
        vec4 l2 = FetchPunctualTexel(light_row, 2); // direction.xyz, angular scale
        float cd = dot(normalize(l2.xyz), -punctual_light_vector);
        float cone = clamp(cd * l2.w + l3.x, 0.0, 1.0);
        radiance *= cone * cone;
        // Spot shadow, when this spot has a slot in the shared atlas. Gate on
        // the geometric normal (the shadow is a geometric property).
#ifndef FLUTTER_SCENE_SKIP_SHADOWS
        if (l3.y > -0.5 && frag_info.spot_shadow_params.x > 0.5) {
          radiance *= SampleSpotShadow(
              light_row, int(l3.y + 0.5), v_position, GetWorldNormal());
        }
#endif
      }
    }
    direct += EvaluateAnalyticLight(
        material, punctual_light_vector, radiance, normal, camera_normal,
        albedo, metallic, roughness, reflectance, n_dot_v, material.specular,
        anisotropic_tangent, anisotropic_bitangent);
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
    coat_direct += EvaluateClearcoatLight(
        punctual_light_vector, radiance, coat_normal, camera_normal,
        coat_roughness);
#endif
    }
  }

  vec3 emissive = material.emissive;

  // Linear HDR, premultiplied by alpha. Exposure, the tone-mapping
  // operator, and display encoding are applied later by the tone-mapping
  // resolve pass (see flutter_scene_resolve.frag), so this writes into a
  // floating-point scene-color target.
  float direct_occlusion = mix(
      1.0, occlusion, clamp(frag_info.ssao_lighting.x, 0.0, 1.0));
  vec3 out_color = ambient + direct * direct_occlusion + emissive;
#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
  vec3 transmitted_light = material.transmission_color * albedo *
                           (vec3(1.0) - clamp(FssEss, 0.0, 1.0));
  out_color += transmitted_light * specular_transmission;
  float coat_fresnel = FresnelSchlick(
      coat_n_dot_v, vec3(0.04)).r;
  float coat_weight = clamp(material.clearcoat, 0.0, 1.0);
  out_color = out_color * (1.0 - coat_weight * coat_fresnel) +
              (coat_direct + coat_ibl) * coat_weight;
#endif

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
    sky_fog_color = SampleRadianceEnv(prefiltered_radiance, sky_dir,
        kSkyFogRoughness);
    if (env_blend > 0.0) {
      sky_fog_color = mix(
          sky_fog_color,
          SampleRadianceEnv(prefiltered_radiance_b,
                            sky_dir, kSkyFogRoughness),
          env_blend);
    }
    sky_fog_color *= frag_info.environment_intensity;
  }
  return ApplyFog(vec4(out_color, 1.0) * alpha, sky_fog_color);
}
