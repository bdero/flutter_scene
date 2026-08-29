// Up to four expanding rings warp the display-referred image, with a
// per-pulse chromatic split. Runs through the
// custom-pass API, after tone mapping so FXAA cleans up the resampled edges
// and the warp includes bloom.
//
// The ring profile is the derivative of a gaussian centered on the ring
// radius, pushing outward ahead of the front and pulling inward behind it,
// which reads as a shockwave rather than a static bulge.

uniform sampler2D input_color;

// x: live pulse count. y: viewport aspect (w/h). zw: reserved.
// pulse_center: per pulse, xy center uv, z radius, w thickness.
// pulse_shape: per pulse, x strength, y chromatic aberration, zw reserved.
uniform DistortionInfo {
  vec4 params;
  vec4 pulse_center[4];
  vec4 pulse_shape[4];
}
distortion;

in vec2 v_uv;
out vec4 frag_color;

const int kMaxPulses = 4;

// Un-premultiplies a sampled premultiplied-alpha color.
vec3 Unpremultiply(vec4 c) { return c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }

void main() {
  vec2 aspect = vec2(distortion.params.y, 1.0);
  int count = int(distortion.params.x);

  vec2 offset = vec2(0.0);
  vec2 chroma_offset = vec2(0.0);
  for (int i = 0; i < kMaxPulses; i++) {
    if (i >= count) break;
    vec4 center = distortion.pulse_center[i];
    vec4 shape = distortion.pulse_shape[i];

    vec2 d = (v_uv - center.xy) * aspect;
    float r = length(d);
    float w = (r - center.z) / max(center.w, 1e-4);
    float g = w * exp(-w * w) * 2.0;
    vec2 dir = d / max(r, 1e-5);

    vec2 contribution = (dir * (g * shape.x)) / aspect;
    offset += contribution;
    chroma_offset += contribution * shape.y;
  }

  // The image here is display-encoded premultiplied alpha, so each tap must
  // be unpremultiplied before recombining and repremultiplied after, or
  // coverage edges fringe with alpha-weighted color.
  vec4 center_tap = texture(input_color, v_uv + offset);
  vec3 color = vec3(
      Unpremultiply(texture(input_color, v_uv + offset + chroma_offset)).r,
      Unpremultiply(center_tap).g,
      Unpremultiply(texture(input_color, v_uv + offset - chroma_offset)).b);
  float alpha = center_tap.a;

  frag_color = vec4(color * alpha, alpha);
}
