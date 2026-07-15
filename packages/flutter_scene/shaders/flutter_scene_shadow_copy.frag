// Replays a cached static shadow tile into the frame's shadow atlas: copies
// the stored depth into both the color channel (what the lit shader samples)
// and the fragment depth (so the dynamic casters drawn after this depth-test
// correctly against the cached static geometry).

precision highp float;

uniform sampler2D source_texture;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  float depth = texture(source_texture, v_uv).r;
  frag_color = vec4(depth, 0.0, 0.0, 1.0);
  gl_FragDepth = depth;
}
