// Copies two 9-texel diffuse-SH coefficient textures into the rows of a 9x2
// composite (row 0 primary, row 1 secondary), so the lit shader reads both
// cross-fade environments through the single sh_coefficients sampler.

uniform sampler2D sh_primary;
uniform sampler2D sh_secondary;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec2 uv = vec2(v_uv.x, 0.5);
  frag_color = v_uv.y < 0.5 ? texture(sh_primary, uv)
                            : texture(sh_secondary, uv);
}
