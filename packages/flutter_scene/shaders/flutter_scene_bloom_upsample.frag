// Bloom upsample: a 3x3 tent filter that blurs the smaller mip as it is
// added back up the chain. texel_size is the size of one texel in the
// source (smaller) mip; scatter widens the tent for a softer bloom.
uniform BloomFilterInfo {
  vec2 texel_size;
  float scatter;
  float _pad0;
}
filter_info;

uniform sampler2D source;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec2 t = filter_info.texel_size * mix(1.0, 3.0, clamp(filter_info.scatter, 0.0, 1.0));

  vec3 sum = texture(source, v_uv + t * vec2(-1.0, -1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(0.0, -1.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(1.0, -1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(-1.0, 0.0)).rgb * 2.0;
  sum += texture(source, v_uv).rgb * 4.0;
  sum += texture(source, v_uv + t * vec2(1.0, 0.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(-1.0, 1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(0.0, 1.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(1.0, 1.0)).rgb;
  sum *= 1.0 / 16.0;

  frag_color = vec4(sum, 1.0);
}
