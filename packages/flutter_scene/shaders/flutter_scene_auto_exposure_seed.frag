// Auto exposure metering seed: samples the linear HDR scene color into a
// small grid of center-weighted log-luminance samples. Each texel stores
// (weight * log-luminance, weight, 0, 1); the plain-average downsample
// chain reduces both channels together, and the adaptation pass divides
// them back out, so the result is the weighted geometric mean luminance.

uniform sampler2D scene_color;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  // The scene color is premultiplied; meter the un-premultiplied radiance
  // so translucent coverage does not read as darkness. Empty background
  // (alpha 0) meters as black.
  vec4 s = texture(scene_color, v_uv);
  vec3 color = s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
  float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
  float log_luminance = log(max(luminance, 1e-4));

  // Center-weighted metering: the middle of the frame counts four times as
  // much as the corners, so bright skies and dark floor edges pull the
  // adaptation around less than the subject.
  float w = 1.0 - 0.75 * smoothstep(0.2, 0.7, length(v_uv - 0.5));

  frag_color = vec4(log_luminance * w, w, 0.0, 1.0);
}
