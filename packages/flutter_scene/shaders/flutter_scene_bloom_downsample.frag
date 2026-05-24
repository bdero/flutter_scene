// Bloom downsample: a 13-tap filter that halves the resolution while
// blurring, used to build the bloom mip chain. texel_size is the size of
// one texel in the source (larger) mip.
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
  vec2 t = filter_info.texel_size;

  vec3 a = texture(source, v_uv + t * vec2(-2.0, -2.0)).rgb;
  vec3 b = texture(source, v_uv + t * vec2(0.0, -2.0)).rgb;
  vec3 c = texture(source, v_uv + t * vec2(2.0, -2.0)).rgb;
  vec3 d = texture(source, v_uv + t * vec2(-2.0, 0.0)).rgb;
  vec3 e = texture(source, v_uv).rgb;
  vec3 f = texture(source, v_uv + t * vec2(2.0, 0.0)).rgb;
  vec3 g = texture(source, v_uv + t * vec2(-2.0, 2.0)).rgb;
  vec3 h = texture(source, v_uv + t * vec2(0.0, 2.0)).rgb;
  vec3 i = texture(source, v_uv + t * vec2(2.0, 2.0)).rgb;
  vec3 j = texture(source, v_uv + t * vec2(-1.0, -1.0)).rgb;
  vec3 k = texture(source, v_uv + t * vec2(1.0, -1.0)).rgb;
  vec3 l = texture(source, v_uv + t * vec2(-1.0, 1.0)).rgb;
  vec3 m = texture(source, v_uv + t * vec2(1.0, 1.0)).rgb;

  vec3 result = e * 0.125;
  result += (a + c + g + i) * 0.03125;
  result += (b + d + f + h) * 0.0625;
  result += (j + k + l + m) * 0.125;

  frag_color = vec4(result, 1.0);
}
