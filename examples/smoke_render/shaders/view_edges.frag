// Outlines depth and normal discontinuities from the engine's linear depth and
// packed normals, for any camera projection. Exercises the custom-pass
// reconstruction contract (PostCameraInfo plus view_projection.glsl).

#include <view_projection.glsl>

uniform sampler2D input_color;
uniform sampler2D input_depth;

uniform PostFrameInfo {
  vec4 resolution;
  vec4 frame;
}
post_frame;

uniform PostCameraInfo {
  vec4 projection;
  vec4 camera_right;
  vec4 camera_up;
  vec4 camera_forward;
  vec4 camera_position;
}
cam;

in vec2 v_uv;
out vec4 frag_color;

vec3 ViewAt(vec2 uv) {
  return ViewPositionFromUv(
      uv, texture(input_depth, uv).r, cam.projection.xy,
      vec3(cam.camera_right.w, cam.camera_up.w, cam.camera_forward.w));
}

vec3 NormalAt(vec2 uv) {
  vec2 e = texture(input_depth, uv).gb;
  vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
  float t = max(-n.z, 0.0);
  n.x += n.x >= 0.0 ? -t : t;
  n.y += n.y >= 0.0 ? -t : t;
  return normalize(n);
}

void main() {
  vec4 scene = texture(input_color, v_uv);
  vec3 center = ViewAt(v_uv);
  vec3 normal = NormalAt(v_uv);
  vec2 texel = post_frame.resolution.zw;
  float edge = 0.0;
  for (int i = 0; i < 4; i++) {
    vec2 offset = i == 0   ? vec2(texel.x, 0.0)
                  : i == 1 ? vec2(-texel.x, 0.0)
                  : i == 2 ? vec2(0.0, texel.y)
                           : vec2(0.0, -texel.y);
    vec2 uv = v_uv + offset;
    // Distance off the center's tangent plane, so a slanted surface does not
    // read as an edge but a step does.
    float plane_gap = abs(dot(ViewAt(uv) - center, normal));
    edge = max(edge, smoothstep(0.05, 0.12, plane_gap));
    edge = max(edge, smoothstep(0.2, 0.5, 1.0 - dot(NormalAt(uv), normal)));
  }
  frag_color = vec4(mix(scene.rgb, vec3(0.02) * scene.a, edge), scene.a);
}
