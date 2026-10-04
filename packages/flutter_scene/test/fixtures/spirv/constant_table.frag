#version 450
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;
const float table[8] = float[8](0.5, -0.25, 1.0, 0.125, -1.0, 2.0, 0.75, -0.5);
float Lookup(int i) { return table[i & 7]; }
float Twice(int i) { return table[(i + 1) & 7]; }
void main() {
  int i = int(uv.x * 8.0);
  color = vec4(Lookup(i), Twice(i), Lookup(i + 3), 1.0);
}
