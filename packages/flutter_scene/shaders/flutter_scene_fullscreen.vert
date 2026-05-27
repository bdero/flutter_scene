// Vertex shader for full-screen post-process passes (e.g. tone mapping,
// the environment prefilter).
//
// Driven by a 6-vertex buffer of NDC positions covering the screen. The
// UV is derived from the position; V increases downward (origin at the
// top), matching the standard texture-sampling convention. Passes that
// sample a render-to-texture input account for that target's per-backend
// Y orientation themselves (see flutter_scene_resolve.frag's flip_y).
// flip_y is -1 on backends where flutter_scene flips render-to-texture in
// the vertex stage (the OpenGL ES Y-flip workaround; see y_flip.dart), +1
// otherwise. It negates gl_Position.y so this pass's offscreen target is
// stored top-down, leaving v_uv (the input sampling coords) untouched.
uniform FlipInfo {
  float flip_y;
}
flip_info;
in vec2 position;

out vec2 v_uv;

void main() {
  v_uv = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
  gl_Position = vec4(position.x, position.y * flip_info.flip_y, 0.0, 1.0);
}
