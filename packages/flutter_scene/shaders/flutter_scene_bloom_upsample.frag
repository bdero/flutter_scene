// Bloom upsample: a 3x3 tent filter, one source texel wide, that blurs the
// smaller mip as it is added back up the chain. Spreading the taps further
// apart would widen the bloom but leave gaps between them, stamping a grid of
// copies around every highlight, so scatter instead weights the wider mips
// (level_weight) and the final level renormalizes (scale).
//
// The larger mip one level up is added here in the shader (base) rather than
// blended into a loaded attachment, so the target is always cleared and
// written once (some backends re-clear a reloaded attachment, dropping the
// accumulation).
uniform BloomUpsampleInfo {
  vec2 texel_size;
  float level_weight;
  float scale;
}
upsample_info;

uniform sampler2D source;
uniform sampler2D base;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec2 t = upsample_info.texel_size;

  vec3 sum = texture(source, v_uv + t * vec2(-1.0, -1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(0.0, -1.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(1.0, -1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(-1.0, 0.0)).rgb * 2.0;
  sum += texture(source, v_uv).rgb * 4.0;
  sum += texture(source, v_uv + t * vec2(1.0, 0.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(-1.0, 1.0)).rgb;
  sum += texture(source, v_uv + t * vec2(0.0, 1.0)).rgb * 2.0;
  sum += texture(source, v_uv + t * vec2(1.0, 1.0)).rgb;
  sum *= upsample_info.level_weight / 16.0;

  sum += texture(base, v_uv).rgb;

  frag_color = vec4(sum * upsample_info.scale, 1.0);
}
