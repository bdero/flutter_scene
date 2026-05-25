// Example custom post-processing effect: a horizontal wave that scrolls
// over time. Shows the PostEffect contract: sample input_color at v_uv,
// read time from the engine-provided PostFrameInfo block, and take custom
// parameters from a WaveInfo block set by name from Dart.
uniform sampler2D input_color;

uniform PostFrameInfo {
  vec2 resolution;
  vec2 texel_size;
  float time;
  float _pad0;
}
frame;

uniform WaveInfo {
  float amplitude;
  float frequency;
  float speed;
  float _pad1;
}
wave;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  float offset =
      sin(v_uv.y * wave.frequency + frame.time * wave.speed) * wave.amplitude;
  frag_color = texture(input_color, vec2(v_uv.x + offset, v_uv.y));
}
