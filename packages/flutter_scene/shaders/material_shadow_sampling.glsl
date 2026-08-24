// Shadow-atlas and punctual-light sampling, shared by the full lighting
// framework (material_lighting.glsl) and materials that sample shadows
// without running the lighting (the shadow catcher).
//
// Requires, declared before this file is included: the FragInfo uniform block
// (as `frag_info`) and the `shadow_map` (unless FLUTTER_SCENE_SKIP_SHADOWS),
// `punctual_lights`, and `punctual_index` samplers from
// material_engine_lighting.glsl.

#ifndef FLUTTER_SCENE_SKIP_SHADOWS
// One rotated Poisson-disk PCF tap into a cascade's atlas tile.
// Samples the caster depth for the soft-shadow blocker search, with the
// same tile mapping as ShadowTap and no comparison.
float ShadowTapDepth(vec2 p, float ca, float sa, float radius, vec2 uv,
                     int cascade, float inv_count) {
  vec2 offset = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * radius;
  vec2 cuv = clamp(uv + offset, vec2(frag_info.shadow_texel_size),
                   vec2(1.0 - frag_info.shadow_texel_size));
  vec2 atlas_uv = vec2((float(cascade) + cuv.x) * inv_count, cuv.y);
  atlas_uv.y = 1.0 - atlas_uv.y;
  return texture(shadow_map, atlas_uv).r;
}

float ShadowTap(vec2 p, float ca, float sa, float radius, vec2 uv, int cascade,
                float inv_count, float receiver_depth) {
  vec2 offset = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca) * radius;
  // Keep samples a texel inside this cascade's tile. This also protects the
  // boundary if a custom backend applies filtering to the atlas.
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

// 2x2 bilinear percentage-closer filtering for one tap. Evaluates four adjacent
// shadow texels and continuously interpolates the depth tests across fractional
// texels, producing smooth analog penumbras without noise rotation or stepping.
float ShadowTapBilinear(vec2 p, float radius, vec2 uv, int cascade,
                        float inv_count, float receiver_depth) {
  vec2 offset = p * radius;
  vec2 cuv = clamp(uv + offset, vec2(frag_info.shadow_texel_size),
                   vec2(1.0 - frag_info.shadow_texel_size));
  vec2 tile_tex =
      vec2(cuv.x, 1.0 - cuv.y) / frag_info.shadow_texel_size - vec2(0.5);
  vec2 base = floor(tile_tex);
  vec2 f = tile_tex - base;
  vec2 cuv00 = (base + vec2(0.5)) * frag_info.shadow_texel_size;
  vec2 atlas_uv00 = vec2((float(cascade) + cuv00.x) * inv_count, cuv00.y);
  vec2 step_uv = vec2(frag_info.shadow_texel_size * inv_count,
                      frag_info.shadow_texel_size);

  float d00 = texture(shadow_map, atlas_uv00).r;
  float d10 = texture(shadow_map, atlas_uv00 + vec2(step_uv.x, 0.0)).r;
  float d01 = texture(shadow_map, atlas_uv00 + vec2(0.0, step_uv.y)).r;
  float d11 = texture(shadow_map, atlas_uv00 + step_uv).r;

  float s00 = receiver_depth <= d00 ? 1.0 : 0.0;
  float s10 = receiver_depth <= d10 ? 1.0 : 0.0;
  float s01 = receiver_depth <= d01 ? 1.0 : 0.0;
  float s11 = receiver_depth <= d11 ? 1.0 : 0.0;

  return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

// Applies the directional shadow receiver's normal-offset bias. A soft PCF
// kernel on a surface tilted relative to the light straddles a depth gradient,
// so lift the receiver far enough that the whole kernel clears the surface.
// The offset depends only on world-space geometry, so every cascade agrees.
vec3 BiasDirectionalShadowPosition(vec3 world_pos, vec3 n) {
  vec3 light_toward = -normalize(frag_info.directional_light_direction.xyz);
  float ndotl = max(dot(n, light_toward), 0.15);
  float slope = min(sqrt(max(1.0 - ndotl * ndotl, 0.0)) / (ndotl * ndotl), 8.0);
  float normal_offset =
      frag_info.shadow_normal_bias + frag_info.shadow_softness * slope;
  return world_pos + n * normal_offset;
}

vec2 PoissonShadowTap(int i) {
  if (i == 0) return vec2(-0.94201624, -0.39906216);
  if (i == 1) return vec2(0.94558609, -0.76890725);
  if (i == 2) return vec2(-0.09418410, -0.92938870);
  if (i == 3) return vec2(0.34495938, 0.29387760);
  if (i == 4) return vec2(-0.91588581, 0.45771432);
  if (i == 5) return vec2(-0.81544232, -0.87912464);
  if (i == 6) return vec2(-0.38277543, 0.27676845);
  if (i == 7) return vec2(0.97484398, 0.75648379);
  if (i == 8) return vec2(0.44323325, -0.97511554);
  if (i == 9) return vec2(0.53742981, -0.47373420);
  if (i == 10) return vec2(-0.26496911, -0.41893023);
  if (i == 11) return vec2(0.79197514, 0.19090188);
  if (i == 12) return vec2(-0.24188840, 0.99706507);
  if (i == 13) return vec2(-0.81409955, 0.91437590);
  if (i == 14) return vec2(0.19984126, 0.78641367);
  if (i == 15) return vec2(0.14383161, -0.14100790);
  return vec2(0.0);
}

vec2 FixedShadowTap(int i) {
  if (i < 3) return vec2(float(i) - 1.0, -1.0);
  if (i < 6) return vec2(float(i - 3) * 0.5 - 0.5, -0.5);
  if (i < 11) return vec2(float(i - 6) * 0.5 - 1.0, 0.0);
  if (i < 14) return vec2(float(i - 11) * 0.5 - 0.5, 0.5);
  return vec2(float(i - 14) - 1.0, 1.0);
}

// Samples one cascade's tile of the shadow atlas strip. `biased_world_pos` is
// the world-space receiver after normal bias.
float SampleCascade(int cascade, int count, mat4 cascade_matrix, float box,
                    vec3 biased_world_pos) {
  vec4 light_clip = cascade_matrix * vec4(biased_world_pos, 1.0);
  vec3 proj = light_clip.xyz / light_clip.w;
  vec2 uv = proj.xy * 0.5 + 0.5;
  // The depth bias is world-space; convert it to this cascade's clip-z (its
  // orthographic depth range is 7 * box: the toward-sun reach + forward margin
  // in light.dart, _casterReachRadii + _forwardMarginRadii, over the half-width
  // that makes box) so a caster crosses the shadow threshold at the same world
  // height in every cascade, with no discontinuity where cascades meet.
  float receiver_depth = proj.z - frag_info.shadow_bias / (7.0 * box);

  // The atlas also holds spot-shadow tiles after the cascades, so normalize the
  // atlas-x by the total tile count. Spot count 0 leaves this at 1 / cascades.
  float inv_count = 1.0 / (float(count) + frag_info.spot_shadow_params.x);

  // Select the tap positions without duplicating the texture samples in both
  // branches. Duplicating both kernels here expands to 33 samples per cascade
  // in the generated GLES source even though the choice is uniform.
  float filter_index = frag_info.directional_light_direction.w;
  float fixed_filter = step(0.5, filter_index) * (1.0 - step(1.5, filter_index));
  float noise = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  float angle = noise * 6.28318530718 * (1.0 - fixed_filter);
  float ca = cos(angle);
  float sa = sin(angle);

  // World-space penumbra -> this cascade's UV space, floored at a texel.
  float max_radius =
      max(frag_info.shadow_softness / box, frag_info.shadow_texel_size);
  float radius = max_radius;
  if (filter_index > 1.5 && filter_index < 2.5) {
    // Percentage-closer soft shadows: find the mean blocker depth inside the
    // light's angular cone, then widen the filter with the blocker distance
    // so shadows sharpen at contact. The cascade's clip depth spans 7 * box
    // world units, so the cone's projected UV radius is
    // tan(angular radius) * 7 * depth and the box cancels out of both terms.
    float cone = tan(frag_info.camera_right.w);
    float search_radius =
        max(cone * 7.0 * receiver_depth, frag_info.shadow_texel_size);
    float blocker_sum = 0.0;
    float blocker_count = 0.0;
    for (int i = 0; i < 9; i++) {
      float caster = ShadowTapDepth(PoissonShadowTap(i), ca, sa, search_radius,
                                    uv, cascade, inv_count);
      float hit = step(caster, receiver_depth);
      blocker_sum += caster * hit;
      blocker_count += hit;
    }
    float mean_blocker =
        blocker_count > 0.0 ? blocker_sum / blocker_count : receiver_depth;
    float penumbra = cone * 7.0 * max(receiver_depth - mean_blocker, 0.0);
    radius = clamp(penumbra, frag_info.shadow_texel_size, max_radius);
  }

  // The Poisson positions are selected when fixed_filter is 0, the stable grid
  // positions when it is 1. The latter preserves the same 17-tap pattern.
  //
  // TODO(flutter_scene): use file-scope const arrays once impellerc/SPIRV-Cross
  // emits valid ES 1.00 array constructors for them.
  float shadow = 0.0;
  if (filter_index > 2.5) {
    // 4-tap bilinear PCF: 4 taps x 4 texels = 16 samples total (matching the
    // 16-sample budget), producing continuous analog filtering with zero
    // noise rotation or stepped banding.
    float lit = ShadowTapBilinear(vec2(-0.7071, -0.7071), radius, uv, cascade,
                                  inv_count, receiver_depth) +
                ShadowTapBilinear(vec2(0.7071, -0.7071), radius, uv, cascade,
                                  inv_count, receiver_depth) +
                ShadowTapBilinear(vec2(-0.7071, 0.7071), radius, uv, cascade,
                                  inv_count, receiver_depth) +
                ShadowTapBilinear(vec2(0.7071, 0.7071), radius, uv, cascade,
                                  inv_count, receiver_depth);
    shadow = lit * 0.25;
  } else {
    int sample_count = fixed_filter > 0.5 ? 17 : 16;
    float lit = 0.0;
    for (int i = 0; i < 17; i++) {
      if (i >= sample_count) break;
      vec2 tap = mix(PoissonShadowTap(i), FixedShadowTap(i), fixed_filter);
      lit += ShadowTap(tap, ca, sa, radius, uv, cascade, inv_count,
                       receiver_depth);
    }
    shadow = lit / float(sample_count);
  }

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

// How much of a cascade this fragment takes, falling from 1 at `band` inside
// the tile to 0 at its usable edge, so the next cascade supplies the rest. A
// zero band selects exactly 1.0, the hard hand-off where the first containing
// cascade takes the whole weight. Written as a select rather than an early
// return so no loop is emitted here (see SampleShadow); the ramp's width is
// floored to keep smoothstep well defined when it is unused.
float CascadeBlendWeight(vec2 uv, float margin, float band) {
  vec2 low = vec2(margin);
  vec2 high = vec2(margin + max(band, 1e-4));
  vec2 ramp = smoothstep(low, high, uv) * smoothstep(low, high, vec2(1.0) - uv);
  return band > 0.0 ? ramp.x * ramp.y : 1.0;
}

// Soft cascaded-shadow lookup. Returns 1.0 (lit) .. 0.0 (fully
// shadowed). `world_pos` and `n` are world-space; `n` is the geometric
// normal. Walks the cascades highest-resolution first, taking from each the
// weight its tile still has room for.
// Tries cascade IDX (a literal): if the fragment lies inside its tile with
// room for the PCF kernel, samples it and accumulates its weight. IDX is a
// literal so no uniform array or vector is indexed with a dynamic index
// (invalid in GLSL ES 1.00, and misread for indices past the first by some
// GLES drivers).
#define _TRY_CASCADE(IDX)                                                    \
  if (weight < 1.0 && count > IDX) {                                         \
    mat4 cascade_matrix = frag_info.light_space_matrix[IDX];                 \
    float box = frag_info.cascade_box_sizes[IDX];                            \
    vec4 light_clip = cascade_matrix * vec4(biased_world_pos, 1.0);          \
    vec3 proj = light_clip.xyz / light_clip.w;                              \
    vec2 uv = proj.xy * 0.5 + 0.5;                                           \
    float margin =                                                          \
        max(frag_info.shadow_softness / box, frag_info.shadow_texel_size);   \
    if (!(uv.x < margin || uv.x > 1.0 - margin || uv.y < margin ||          \
          uv.y > 1.0 - margin || proj.z < 0.0 || proj.z > 1.0)) {           \
      float take = min(CascadeBlendWeight(uv, margin, band),                 \
                       1.0 - weight);                                        \
      if (take > 0.0) {                                                      \
        shadow_sum += take * SampleCascade(IDX, count, cascade_matrix, box,  \
                                           biased_world_pos);                \
        weight += take;                                                      \
      }                                                                      \
    }                                                                        \
  }

float SampleShadow(vec3 world_pos, vec3 n) {
  int count = int(frag_info.shadow_cascade_count);
  // Select and sample with the same displaced position. Selecting with the
  // original point could choose a tile that normal bias moves outside, making
  // every PCF tap clamp to one edge texel and producing a visible band.
  vec3 biased_world_pos = BiasDirectionalShadowPosition(world_pos, n);
  // Cross-fade half-width in a cascade's UV space, from the light's
  // cascadeOverlap. At 0 every _TRY_CASCADE takes the full weight, so the
  // first containing cascade wins outright and the later ones are skipped.
  float band = frag_info.directional_light_color.w * 0.5;
  // Unrolled with literal cascade indices: see _TRY_CASCADE. A single `return`
  // (no early return inside a loop) also avoids a nested-loop pattern that
  // crashes a Direct3D shader compiler.
  float shadow_sum = 0.0;
  float weight = 0.0;
  _TRY_CASCADE(0)
  _TRY_CASCADE(1)
  _TRY_CASCADE(2)
  _TRY_CASCADE(3)
  // Weight no cascade covered reads as lit.
  return shadow_sum + (1.0 - weight);
}
#undef _TRY_CASCADE
#endif

// The number of additional analytic lights (point, spot, and directional
// lights past the first) the loop below can shade in one draw. Must match
// kMaxPunctualLights in lib/src/render/punctual_lights.dart. The loop is
// unrolled to this constant bound because GLSL ES 1.00 requires a compile-time
// loop bound; the active count (frag_info.radiance_blend.z) ends it early.
#define MAX_PUNCTUAL_LIGHTS 16

// A shadow catcher's no-shadow variant declares no punctual textures (its
// only punctual consumer is the spot loop the guard above removed), so the
// fetch helpers compile out with them.
#if !defined(FLUTTER_SCENE_SHADOW_CATCHER) || !defined(FLUTTER_SCENE_SKIP_SHADOWS)
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
#endif  // punctual fetch helpers

#ifndef FLUTTER_SCENE_SKIP_SHADOWS
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
#endif
