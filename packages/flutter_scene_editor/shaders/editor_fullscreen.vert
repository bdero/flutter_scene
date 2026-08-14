// Full-screen vertex for the editor's debug shaders. Mirrors the engine's
// FullscreenVertex contract (6-vertex NDC quad, V increases downward).
in vec2 position;

out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position.x, position.y, 0.0, 1.0);
}
