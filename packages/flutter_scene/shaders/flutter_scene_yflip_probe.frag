// Render-to-texture Y-orientation probe; see y_flip.dart.
//
// Paired with flutter_scene_fullscreen.vert (FlipInfo bound to +1, i.e. no
// flip), which sets v_uv.y = 0.5 - ndc_y * 0.5, so v_uv.y < 0.5 is the top
// half of NDC. Emit red there and black below. Reading the rendered texture
// back reveals how the backend stored it: red at the top row means top-down
// (Metal/Vulkan), red at the bottom row means bottom-up (OpenGL ES).
in vec2 v_uv;

out vec4 frag_color;

void main() {
  frag_color = vec4(v_uv.y < 0.5 ? 1.0 : 0.0, 0.0, 0.0, 1.0);
}
