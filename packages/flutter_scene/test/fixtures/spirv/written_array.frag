#version 450
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;
void main() {
  float t[4] = float[4](0.5, -0.25, 1.0, 0.125);
  t[int(uv.x * 4.0) & 3] = uv.y;
  color = vec4(t[int(uv.y * 4.0) & 3], 0.0, 0.0, 1.0);
}
