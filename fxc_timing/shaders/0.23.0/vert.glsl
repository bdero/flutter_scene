#version 300 es
uniform float _impeller_y_flip;


layout(std140) uniform FrameInfo
{
    mat4 camera_transform;
    vec3 camera_position;
    float depth_bias;
} frame_info;

layout(location = 6) in vec4 model_transform_0;
layout(location = 7) in vec4 model_transform_1;
layout(location = 8) in vec4 model_transform_2;
layout(location = 9) in vec4 model_transform_3;
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 5) in vec4 tangent;
layout(location = 2) in vec2 texture_coords;
layout(location = 3) in vec2 texture_coords_1;
layout(location = 4) in vec4 color;
layout(location = 10) in vec4 instance_color;
out vec3 v_position;
out vec3 v_viewvector;
out vec3 v_normal;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

void _impeller_user_main()
{
    vec3 _122 = (mat4(model_transform_0, model_transform_1, model_transform_2, model_transform_3) * vec4(position, 1.0)).xyz;
    mat3 _133 = mat3(model_transform_0.xyz, model_transform_1.xyz, model_transform_2.xyz);
    vec3 _148 = _133 * tangent.xyz;
    float _152 = dot(_148, _148);
    float _334 = 0.0;
    if (determinant(_133) < 0.0)
    {
        _334 = -tangent.w;
    }
    else
    {
        _334 = tangent.w;
    }
    vec4 _335 = vec4(0.0);
    if (_152 > 1.0000000133514319600180897396058e-10)
    {
        _335 = vec4(_148 * inversesqrt(_152), _334);
    }
    else
    {
        _335 = vec4(0.0);
    }
    vec3 _300 = vec3(0.0);
    v_position = _122;
    vec3 _336 = vec3(0.0);
    do
    {
        _300 = frame_info.camera_position - _122;
        float _303 = dot(_300, _300);
        if ((frame_info.depth_bias <= 0.0) || (_303 <= 9.9999999600419720025001879548654e-13))
        {
            _336 = _122;
            break;
        }
        _336 = _122 + (_300 * min(frame_info.depth_bias * inversesqrt(_303), 0.9900000095367431640625));
        break;
    } while(false);
    gl_Position = frame_info.camera_transform * vec4(_336, 1.0);
    v_viewvector = _300;
    v_normal = _133 * normal;
    v_texture_coords = texture_coords;
    v_texture_coords_1 = texture_coords_1;
    v_color = color * instance_color;
    v_tangent = _335;
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}


void main() {
  _impeller_user_main();
  gl_Position.y *= _impeller_y_flip;
}
