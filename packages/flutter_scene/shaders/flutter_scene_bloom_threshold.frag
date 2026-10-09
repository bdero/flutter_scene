// Bloom prefilter: extracts the bright part of the scene color with a
// soft-knee threshold, writing it into the first bloom mip. Works on the
// premultiplied linear HDR color, the light each pixel actually holds, so
// light at zero alpha (additive draws over a transparent background) blooms
// too.
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
  // Firefly suppression (0 = off): within each aligned 2x2 group of source
  // texels, a tap is weighted by 1 / (1 + luminance / this scale), so an
  // isolated extreme pixel (a mirror glint of a small light) cannot flood
  // the bloom or flicker as it moves, while a uniformly bright region keeps
  // its full brightness.
  float firefly_scale;
  // Source texels per bloom texel, per axis.
  vec2 footprint;
  vec2 source_size;
  // Soft highlight compression (0 = off): a color whose brightest channel is
  // b is scaled by 1 / (1 + b / this), so no source texel blooms brighter
  // than this while ordinary highlights pass nearly unchanged.
  float highlight;
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
  vec3 color = min(max(s.rgb, vec3(0.0)), vec3(65504.0));
  if (threshold_info.apply_threshold < 0.5) {
    return color;
  }
  float brightness = max(color.r, max(color.g, color.b));
  if (threshold_info.highlight > 0.0) {
    float compression = 1.0 / (1.0 + brightness / threshold_info.highlight);
    color *= compression;
    brightness *= compression;
  }

  // Soft knee around the threshold so the bloom fades in gradually.
  float knee = threshold_info.knee;
  float soft =
      clamp(brightness - threshold_info.threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float contribution =
      max(soft, brightness - threshold_info.threshold) / max(brightness, 1e-4);
  return color * contribution;
}

// Source texel groups per axis: a box of up to kMaxTaps texels straddles at
// most this many aligned 2x2 groups.
const int kMaxGroups = kMaxTaps / 2 + 1;

void main() {
  vec2 size = threshold_info.source_size;
  // This texel's box, in source texels.
  vec2 lo = v_uv * size - 0.5 * threshold_info.footprint;
  vec2 hi = lo + threshold_info.footprint;
  // The aligned 2x2 groups the box touches. Groups align to even source
  // texels, so neighboring bloom texels group a shared texel the same way.
  vec2 first_group = floor(floor(lo) * 0.5);
  ivec2 groups = ivec2(floor((ceil(hi) - 1.0) * 0.5) - first_group) + 1;
  float scale = threshold_info.apply_threshold > 0.5
      ? threshold_info.firefly_scale
      : 0.0;
  vec3 sum = vec3(0.0);
  for (int gy = 0; gy < kMaxGroups; gy++) {
    if (gy >= groups.y) {
      break;
    }
    for (int gx = 0; gx < kMaxGroups; gx++) {
      if (gx >= groups.x) {
        break;
      }
      // The group's Karis-weighted average, carried by the box coverage of
      // its texels. Unweighted, this is exactly the box average.
      vec3 group_sum = vec3(0.0);
      float group_weight = 0.0;
      float group_coverage = 0.0;
      for (int j = 0; j < 2; j++) {
        for (int i = 0; i < 2; i++) {
          vec2 t = (first_group + vec2(float(gx), float(gy))) * 2.0 +
                   vec2(float(i), float(j));
          float wx = min(hi.x, t.x + 1.0) - max(lo.x, t.x);
          float wy = min(hi.y, t.y + 1.0) - max(lo.y, t.y);
          if (wx <= 0.0 || wy <= 0.0) {
            continue;
          }
          vec3 tap = Threshold((t + 0.5) / size);
          float coverage = wx * wy;
          float weight = coverage;
          if (scale > 0.0) {
            weight /= 1.0 + dot(tap, vec3(0.2126, 0.7152, 0.0722)) / scale;
          }
          group_sum += tap * weight;
          group_weight += weight;
          group_coverage += coverage;
        }
      }
      if (group_weight > 0.0) {
        sum += group_sum * (group_coverage / group_weight);
      }
    }
  }
  frag_color = vec4(
      sum / (threshold_info.footprint.x * threshold_info.footprint.y), 1.0);
}
