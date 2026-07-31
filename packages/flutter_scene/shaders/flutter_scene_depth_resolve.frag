// Converts window-space depth to planar view-space depth.

uniform sampler2D scene_depth;

uniform DepthResolveInfo {
  // x near, y far, z/w unused.
  vec4 clip;
}
depth_resolve;

in vec2 v_uv;
out vec4 frag_color;

void main() {
  float depth = texture(scene_depth, v_uv).r;
  float near = depth_resolve.clip.x;
  float far = depth_resolve.clip.y;
  float linear_depth = near * far / max(far - depth * (far - near), 1e-6);
  frag_color = vec4(linear_depth, 0.0, 0.0, 1.0);
}
