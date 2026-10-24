uniform sampler2DArray layers;
uniform ArrayParams {
  float layer;
} array_params;
in vec2 v_uv;
out vec4 frag_color;
void main() {
  vec4 texel = texture(layers, vec3(v_uv, array_params.layer));
  frag_color = vec4(texel.r, texel.g, 0.0, 1.0);
}
