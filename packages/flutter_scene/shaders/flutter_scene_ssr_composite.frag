// Composites the screen-space reflection buffer (produced by
// flutter_scene_ssr.frag, possibly at a reduced resolution) over the
// full-resolution linear HDR scene color.
//
// The reflection is stored premultiplied by its blend strength (rgb =
// reflected color * strength, a = strength), so it upscales with plain
// bilinear filtering and composites with a premultiplied "over". The output
// follows the scene color's premultiplied-alpha contract.

uniform sampler2D input_color;
uniform sampler2D ssr_reflection;

uniform CompositeInfo {
  // x: debug view (0 = normal composite; nonzero shows the reflection buffer
  // directly, for the trace's debug visualizations).
  vec4 params;
}
composite;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  vec4 refl = texture(ssr_reflection, v_uv);

  int debug_view = int(composite.params.x + 0.5);
  if (debug_view != 0) {
    // The trace wrote its debug visualization opaquely; show it (upscaled).
    frag_color = vec4(refl.rgb, 1.0);
    return;
  }

  vec4 base = texture(input_color, v_uv);
  // Premultiplied over within the surface's coverage: base * (1 - strength) +
  // reflected * strength (refl.rgb is already premultiplied by strength).
  // Staying premultiplied lets light at zero alpha pass through.
  frag_color = vec4(base.rgb * (1.0 - refl.a) + refl.rgb * base.a, base.a);
}
