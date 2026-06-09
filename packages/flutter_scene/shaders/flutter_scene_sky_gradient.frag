// Built-in gradient sky: a vertical gradient between zenith, horizon, and
// ground colors with an HDR sun disk and a soft halo. Driven by the engine's
// sky vertex shader (`v_ray` is the world view direction); outputs linear HDR
// radiance with premultiplied alpha, like every sky fragment.

uniform GradientSkyInfo {
  vec4 zenith_color;
  vec4 horizon_color;
  vec4 ground_color;
  // xyz = direction toward the sun (world), w = sun disk sharpness exponent.
  vec4 sun_direction;
  // rgb = sun disk color (linear HDR).
  vec4 sun_color;
}
sky_info;

in vec3 v_ray;

out vec4 frag_color;

void main() {
  vec3 dir = normalize(v_ray);
  vec3 color;
  if (dir.y >= 0.0) {
    color = mix(sky_info.horizon_color.rgb, sky_info.zenith_color.rgb,
                sqrt(dir.y));
  } else {
    color = mix(sky_info.horizon_color.rgb, sky_info.ground_color.rgb,
                sqrt(-dir.y));
  }
  float s = max(dot(dir, normalize(sky_info.sun_direction.xyz)), 0.0);
  color += sky_info.sun_color.rgb * pow(s, sky_info.sun_direction.w);
  color += sky_info.sun_color.rgb * (0.15 * pow(s, 8.0));
  frag_color = vec4(color, 1.0);
}
