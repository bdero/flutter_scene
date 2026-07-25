// Bloom prefilter: extracts the bright part of the scene color with a
// soft-knee threshold, writing it into the first (half-resolution) bloom
// mip. Works on un-premultiplied linear HDR radiance.
uniform BloomThresholdInfo {
  float threshold;
  float knee;
  float _pad0;
  float _pad1;
}
threshold_info;

uniform sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 s = texture(source, v_uv);
  // Clamp to a finite HDR ceiling first: an infinite radiance sample makes the
  // contribution below Inf/Inf = NaN, which the downsample then spreads into a
  // black bloom tile. Half-float max is far above any real bloom source.
  vec3 color = s.a > 0.0 ? min(s.rgb / s.a, vec3(65504.0)) : vec3(0.0);
  float brightness = max(color.r, max(color.g, color.b));

  // Soft knee around the threshold so the bloom fades in gradually.
  float knee = threshold_info.knee;
  float soft = clamp(brightness - threshold_info.threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float contribution =
      max(soft, brightness - threshold_info.threshold) / max(brightness, 1e-4);

  frag_color = vec4(color * contribution, 1.0);
}
