uniform FragInfo {
  vec4 color;
  float vertex_color_weight;
  // LOD cross-fade coverage; see lod_fade.glsl.
  float fade;
}
frag_info;

#include <lod_fade.glsl>

uniform sampler2D base_color_texture;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

// Distance fog (the FogInfo block + ApplyFog). Declared after the varyings it
// reads (v_position, v_viewvector).
#include <fog.glsl>

const float kGamma = 2.2;
vec3 SRGBToLinear(vec3 color) { return pow(color, vec3(kGamma)); }

void main() {
  ApplyLodFade(frag_info.fade);
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base = texture(base_color_texture, v_texture_coords);
  // Linearize the sRGB-encoded base color so what we write to the
  // floating-point scene-color target is linear; the tone-mapping resolve
  // pass applies display encoding. Output is premultiplied by alpha.
  vec3 rgb = SRGBToLinear(base.rgb) * vertex_color.rgb * frag_info.color.rgb;
  float alpha = base.a * vertex_color.a * frag_info.color.a;
  // Unlit has no environment bound, so pass the flat fog color as the sky color;
  // the sky-color mix in ApplyFog is then inert (sky-colored fog is a lit-path
  // feature).
  frag_color = ApplyFog(vec4(rgb, 1.0) * alpha, fog.color.rgb);
}
