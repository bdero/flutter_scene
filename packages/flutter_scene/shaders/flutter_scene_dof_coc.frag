// Depth-of-field setup pass, run into a half-resolution target: downsamples
// the linear HDR scene color and computes the signed circle-of-confusion
// radius (in half-res pixels) from the camera's linear depth. Negative CoC is
// the near field (in front of focus), positive the far field; |coc| < 1 px is
// snapped to exactly 0 so in-focus pixels can be skipped downstream.

precision highp float;

uniform sampler2D scene_color;
uniform sampler2D linear_depth;

uniform CocInfo {
  // x: CoC scale K, half-res pixels per unit of (1 - S/d)
  // y: focus distance S (world units)
  // z: max foreground CoC radius (px)   w: max background CoC radius (px)
  vec4 params0;
  // xy: full-res texel size   zw: unused
  vec4 params1;
}
coc_info;

in vec2 v_uv;

out vec4 frag_color;

float CocAt(float depth) {
  float coc =
      coc_info.params0.x * (1.0 - coc_info.params0.y / max(depth, 1e-4));
  coc = clamp(coc, -coc_info.params0.z, coc_info.params0.w);
  return abs(coc) < 1.0 ? 0.0 : coc;
}

void main() {
  vec2 t = coc_info.params1.xy * 0.5;
  // 2x2 box. The color is Karis-weighted (1 / (1 + maxRGB)) so a single hot
  // pixel cannot flicker into a huge bokeh; the CoC takes the most-foreground
  // sample of the quad so near blur wins ties at silhouettes.
  vec3 color = vec3(0.0);
  float weight = 0.0;
  float coc = 1e9;
  for (int i = 0; i < 4; i++) {
    vec2 o = vec2((i == 1 || i == 3) ? t.x : -t.x, (i < 2) ? -t.y : t.y);
    vec3 c = texture(scene_color, v_uv + o).rgb;
    float w = 1.0 / (1.0 + max(c.r, max(c.g, c.b)));
    color += c * w;
    weight += w;
    coc = min(coc, CocAt(texture(linear_depth, v_uv + o).r));
  }
  frag_color = vec4(color / weight, coc);
}
