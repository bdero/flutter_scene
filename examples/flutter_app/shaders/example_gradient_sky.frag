// Custom sky for a ShaderSkySource: a vertical gradient with a sun disk.
//
// The engine's sky vertex shader supplies the world-space view direction as
// `v_ray` and owns the full-screen draw, depth, and draw order. The shader
// outputs linear HDR radiance with premultiplied alpha; exposure and tone
// mapping are applied later by the resolve pass.

uniform GradientSkyInfo {
  vec4 zenith_color;
  vec4 horizon_color;
  vec4 ground_color;
  // xyz = sun direction (world), w = sun sharpness exponent.
  vec4 sun;
}
sky;

in vec3 v_ray;

out vec4 frag_color;

void main() {
  vec3 dir = normalize(v_ray);
  vec3 color;
  if (dir.y >= 0.0) {
    color = mix(sky.horizon_color.rgb, sky.zenith_color.rgb, sqrt(dir.y));
  } else {
    color = mix(sky.horizon_color.rgb, sky.ground_color.rgb, sqrt(-dir.y));
  }
  float s = max(dot(dir, normalize(sky.sun.xyz)), 0.0);
  // Bright (HDR) sun so the disk survives tone mapping, plus a soft glow.
  color += vec3(3.0, 2.7, 2.2) * pow(s, sky.sun.w);
  color += vec3(0.5, 0.45, 0.35) * pow(s, 8.0);
  frag_color = vec4(color, 1.0);
}
