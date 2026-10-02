// Bloom prefilter: extracts the bright part of the scene color with a
// soft-knee threshold, writing it into the first bloom mip. Works on
// un-premultiplied linear HDR radiance.
//
// The first mip can be many times smaller than the scene, so each texel
// averages its whole source footprint as an exact box: every source texel the
// box touches is weighted by how much of it the box covers. Adjacent boxes
// tile the source, so a highlight contributes the same total at any position.
// A single tap would catch a small highlight at full strength or miss it
// entirely depending on its sub-pixel position, which pops as things move
// and stamps blocky copies through the blur chain.
uniform BloomThresholdInfo {
  float threshold;
  float knee;
  // 0 for a plain box average (the second stage of a two-stage prefilter).
  float apply_threshold;
  float _pad0;
  // Source texels per bloom texel, per axis.
  vec2 footprint;
  vec2 source_size;
}
threshold_info;

uniform sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

// Matches kMaxBloomThresholdTaps in bloom_pass.dart.
const int kMaxTaps = 16;

vec3 Threshold(vec2 uv) {
  vec4 s = texture(source, uv);
  // Bound to [0, half-float max] before anything else: an infinite sample makes
  // the contribution below Inf/Inf = NaN. The floor comes first so a NaN maps
  // to 0; min(NaN, x) returns x on most GPUs, which would bloom a NaN pixel at
  // full strength across the screen.
  vec3 color = s.a > 0.0 ? min(max(s.rgb / s.a, vec3(0.0)), vec3(65504.0))
                         : vec3(0.0);
  if (threshold_info.apply_threshold < 0.5) {
    return color;
  }
  float brightness = max(color.r, max(color.g, color.b));

  // Soft knee around the threshold so the bloom fades in gradually.
  float knee = threshold_info.knee;
  float soft =
      clamp(brightness - threshold_info.threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float contribution =
      max(soft, brightness - threshold_info.threshold) / max(brightness, 1e-4);
  return color * contribution;
}

void main() {
  vec2 size = threshold_info.source_size;
  // This texel's box, in source texels.
  vec2 lo = v_uv * size - 0.5 * threshold_info.footprint;
  vec2 hi = lo + threshold_info.footprint;
  vec2 first = floor(lo);
  ivec2 taps = ivec2(ceil(hi) - first);
  vec3 sum = vec3(0.0);
  for (int y = 0; y < kMaxTaps; y++) {
    if (y >= taps.y) {
      break;
    }
    float ty = first.y + float(y);
    float wy = min(hi.y, ty + 1.0) - max(lo.y, ty);
    for (int x = 0; x < kMaxTaps; x++) {
      if (x >= taps.x) {
        break;
      }
      float tx = first.x + float(x);
      float wx = min(hi.x, tx + 1.0) - max(lo.x, tx);
      sum += Threshold((vec2(tx, ty) + 0.5) / size) * (wx * wy);
    }
  }
  frag_color = vec4(
      sum / (threshold_info.footprint.x * threshold_info.footprint.y), 1.0);
}
