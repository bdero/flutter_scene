// Selection outline fragment shader (full-screen post pass).
//
// Reads the display-referred scene color and a selection mask (highlighted
// objects drawn flat by the mask pass) and composites a uniform-width outline
// around the masked silhouettes. The outline color comes from the mask, so
// differently-colored highlights work in one pass. A pixel becomes outline when
// it is outside a silhouette but a covered neighbor lies within the configured
// thickness (a single-pass dilation; jump-flood can replace it for very wide
// glows later).
//
// Both inputs are render-to-texture targets stored top-down on every backend
// (the same convention the resolve pass relies on), so they sample at v_uv
// with no fragment-stage flip.

uniform sampler2D scene_color;
uniform sampler2D selection_mask;

uniform OutlineInfo {
  vec2 texel_size; // 1.0 / resolution
  float thickness; // outline width in texels
  float _pad;
}
outline_info;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  vec4 base = texture(scene_color, v_uv);
  vec4 center = texture(selection_mask, v_uv);

  // Constant kernel bounds (GLSL ES 1.00 requires it); samples outside the
  // configured thickness are skipped.
  const int kRadius = 4;
  float t = clamp(outline_info.thickness, 1.0, float(kRadius));
  float t2 = t * t;
  float bestCoverage = 0.0;
  vec3 outlineColor = vec3(0.0);
  for (int y = -kRadius; y <= kRadius; y++) {
    for (int x = -kRadius; x <= kRadius; x++) {
      vec2 d = vec2(float(x), float(y));
      if (dot(d, d) > t2) {
        continue;
      }
      vec4 s = texture(selection_mask, v_uv + d * outline_info.texel_size);
      if (s.a > bestCoverage) {
        bestCoverage = s.a;
        outlineColor = s.rgb;
      }
    }
  }

  // Outline where the center is outside a silhouette but a neighbor is inside.
  float edge = (center.a < 0.001 && bestCoverage > 0.001) ? 1.0 : 0.0;
  frag_color = vec4(mix(base.rgb, outlineColor, edge), base.a);
}
