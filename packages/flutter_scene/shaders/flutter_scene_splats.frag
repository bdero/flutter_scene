// Gaussian splat fragment stage: evaluates the Gaussian falloff across the
// footprint quad and outputs linear HDR premultiplied alpha (the translucent
// pass blends with premultiplied source-over).

in vec2 v_quad;  // position in the footprint, standard-deviation units
in vec4 v_color; // linear RGB and final opacity

out vec4 frag_color;

void main() {
  float r2 = dot(v_quad, v_quad);
  float alpha = v_color.a * exp(-0.5 * r2);
  // Below 8-bit blending precision; discarding also keeps the quad corners
  // from writing outside the elliptical footprint.
  if (alpha < 1.0 / 255.0) {
    discard;
  }
  frag_color = vec4(v_color.rgb * alpha, alpha);
}
