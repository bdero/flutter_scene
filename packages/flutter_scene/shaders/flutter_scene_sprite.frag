uniform FragInfo {
  vec4 tint;      // linear RGBA, multiplied into the sampled color
  float additive; // 0: premultiplied source-over, 1: additive
  float soft;     // reserved for soft-particle depth fade (unused for now)
}
frag_info;

uniform sampler2D base_color_texture;

in vec2 v_uv;
in vec4 v_color;
in vec2 v_uv2;
in float v_frame_blend;

out vec4 frag_color;

const float kGamma = 2.2;
vec3 SRGBToLinear(vec3 color) { return pow(color, vec3(kGamma)); }

void main() {
  // Crossfade between adjacent flipbook cells (v_frame_blend is zero when
  // the geometry has blending off, collapsing to a single sample's value).
  vec4 base = mix(
      texture(base_color_texture, v_uv),
      texture(base_color_texture, v_uv2),
      v_frame_blend);
  // Linearize the sRGB-encoded texture; the resolve pass applies display
  // encoding. The scene-color target stores linear HDR premultiplied alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * v_color.rgb * frag_info.tint.rgb;
  float alpha = base.a * v_color.a * frag_info.tint.a;

  // The color encoder's translucent pass blends with premultiplied
  // source-over: out = src.rgb + (1 - src.a) * dst. Premultiplying the color
  // by alpha gives normal blending; forcing the output alpha to zero (while
  // keeping the premultiplied color) turns the same pass additive, so both
  // modes share one pipeline.
  float out_alpha = mix(alpha, 0.0, frag_info.additive);
  frag_color = vec4(rgb * alpha, out_alpha);
}
