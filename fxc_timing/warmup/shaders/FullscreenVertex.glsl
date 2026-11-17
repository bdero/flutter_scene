#version 300 es
uniform float _impeller_y_flip;


out vec2 v_uv;
layout(location = 0) in vec2 position;

void _impeller_user_main()
{
    v_uv = vec2((position.x * 0.5) + 0.5, 0.5 - (position.y * 0.5));
    gl_Position = vec4(position.x, position.y, 0.0, 1.0);
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}


void main() {
  _impeller_user_main();
  gl_Position.y *= _impeller_y_flip;
}
