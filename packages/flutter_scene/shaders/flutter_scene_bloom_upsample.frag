// Bloom upsample: a 3x3 tent filter that blurs the smaller mip as it is
// added back up the chain. texel_size is the size of one texel in the
// source (smaller) mip; scatter widens the tent for a softer bloom. The
// larger mip one level up is added here in the shader (base) rather than
// blended into a loaded attachment, so the target is always cleared and
// written once (some backends re-clear a reloaded attachment, dropping the
// accumulation).
uniform BloomFilterInfo {
  vec2 texel_size;
  float scatter;
  float _pad0;
}
filter_info;

uniform sampler2D source;
uniform sampler2D base;

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

  sum += texture(base, v_uv).rgb;

  frag_color = vec4(sum, 1.0);
}
