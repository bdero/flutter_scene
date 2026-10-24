uniform sampler3D volume;
uniform VolumeParams {
  float z;
} volume_params;
in vec2 v_uv;
out vec4 frag_color;
void main() {
  vec4 texel = texture(volume, vec3(v_uv, volume_params.z));
  frag_color = vec4(texel.r, texel.g, 0.0, 1.0);
}
