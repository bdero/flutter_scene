// Vertex shader for full-screen post-process passes (e.g. tone mapping).
//
// Driven by a 6-vertex buffer of NDC positions covering the screen. The
// UV is derived from the position; V is flipped because the inputs are
// render-to-texture targets whose origin is at the top.
in vec2 position;

out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position, 0.0, 1.0);
}
