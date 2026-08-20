// Morph target (blend shape) evaluation for the morphed vertex variants.
// Included by the shared vertex bodies when FLUTTER_SCENE_MORPH_TARGETS is
// defined; the plain variants never see any of this.
//
// Deltas ride an RGBA32F texture in which each target owns a contiguous band
// of rows: the position rows first, then (when present) the normal rows.
// Vertices wrap left to right inside a band at the texture's width, so a
// wrap boundary never crosses into another target's rows. The CPU picks the
// highest-magnitude nonzero weights each frame and uploads them as
// (band start row, weight) pairs; the loop below runs the fixed pair count
// with dynamically indexed rows.

const int kMaxMorphTargets = 8;

uniform MorphInfo {
  // x: active pair count, y: texture width in texels,
  // z: rows per attribute per band, w: 1 when normal rows are present.
  vec4 morph_params;
  // x: the target's band start row, y: the target's weight.
  vec4 morph_pairs[kMaxMorphTargets];
}
morph_info;

uniform sampler2D morph_texture;

vec3 MorphDelta(int row_start, int vertex_index) {
  int width = int(morph_info.morph_params.y);
  ivec2 texel = ivec2(vertex_index % width, row_start + vertex_index / width);
  return texelFetch(morph_texture, texel, 0).xyz;
}

vec3 MorphedPosition(vec3 base_position) {
  vec3 result = base_position;
  int count = int(morph_info.morph_params.x);
  for (int i = 0; i < kMaxMorphTargets; i++) {
    if (i >= count) {
      break;
    }
    result += morph_info.morph_pairs[i].y *
        MorphDelta(int(morph_info.morph_pairs[i].x), gl_VertexIndex);
  }
  return result;
}

// Sums the weighted normal deltas and renormalizes, keeping the base normal
// when the sum collapses to near zero. Matches the CPU blend rule.
vec3 MorphedNormal(vec3 base_normal) {
  if (morph_info.morph_params.w < 0.5) {
    return base_normal;
  }
  vec3 result = base_normal;
  int count = int(morph_info.morph_params.x);
  int rows_per_attribute = int(morph_info.morph_params.z);
  for (int i = 0; i < kMaxMorphTargets; i++) {
    if (i >= count) {
      break;
    }
    result += morph_info.morph_pairs[i].y *
        MorphDelta(int(morph_info.morph_pairs[i].x) + rows_per_attribute,
                   gl_VertexIndex);
  }
  float length_squared = dot(result, result);
  return length_squared > 1e-12 ? result * inversesqrt(length_squared)
                                : base_normal;
}
