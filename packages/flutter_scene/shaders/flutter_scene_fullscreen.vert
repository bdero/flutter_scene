// Vertex shader for full-screen post-process passes (e.g. tone mapping,
// the environment prefilter).
//
// Driven by a 6-vertex buffer of NDC positions covering the screen. The
// UV is derived from the position; V increases downward (origin at the
// top), matching the standard texture-sampling convention. Passes that
// sample a render-to-texture input account for that target's per-backend
// Y orientation themselves (see flutter_scene_tonemap.frag's flip_y).
in vec2 position;

out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position, 0.0, 1.0);
}
