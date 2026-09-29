// Bloom prefilter: extracts the bright part of the scene color with a
// soft-knee threshold, writing it into the first bloom mip. Works on
// un-premultiplied linear HDR radiance.
//
// The first mip can be many times smaller than the scene, so each texel
// averages a grid of bilinear taps spanning its whole source footprint.
// A single tap would catch a small highlight at full strength or miss it
// entirely depending on its sub-pixel position, which pops as things move
// and stamps blocky copies through the blur chain.
uniform BloomThresholdInfo {
  float threshold;
  float knee;
  // Taps per axis, spaced at most one source texel apart so their bilinear
  // footprints overlap into an even box.
  float taps;
  float _pad0;
  // Source texels per bloom texel, per axis.
  vec2 footprint;
  vec2 source_texel;
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
  int taps = int(threshold_info.taps);
  vec2 spacing = threshold_info.footprint / threshold_info.taps;
  vec2 origin = v_uv + threshold_info.source_texel *
                           (0.5 * spacing - 0.5 * threshold_info.footprint);
  vec3 sum = vec3(0.0);
  for (int y = 0; y < kMaxTaps; y++) {
    if (y >= taps) {
      break;
    }
    for (int x = 0; x < kMaxTaps; x++) {
      if (x >= taps) {
        break;
      }
      sum += Threshold(origin + threshold_info.source_texel *
                                    (spacing * vec2(float(x), float(y))));
    }
  }
  frag_color = vec4(sum / (threshold_info.taps * threshold_info.taps), 1.0);
}
