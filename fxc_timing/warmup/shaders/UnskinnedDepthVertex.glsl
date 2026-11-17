#version 300 es
uniform float _impeller_y_flip;


layout(std140) uniform FrameInfo
{
    mat4 camera_transform;
    vec3 camera_position;
    float depth_bias;
    vec4 depth_offset;
    vec4 depth_slope;
} frame_info;

layout(location = 1) in vec4 model_transform_0;
layout(location = 2) in vec4 model_transform_1;
layout(location = 3) in vec4 model_transform_2;
layout(location = 4) in vec4 model_transform_3;
layout(location = 0) in vec3 position;
out vec3 v_position;
out vec3 v_viewvector;
out vec3 v_normal;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

void _impeller_user_main()
{
    vec3 _317 = (mat4(model_transform_0, model_transform_1, model_transform_2, model_transform_3) * vec4(position, 1.0)).xyz;
    v_position = _317;
    vec3 _648 = vec3(0.0);
    do
    {
        if (frame_info.depth_bias <= 0.0)
        {
            _648 = _317;
            break;
        }
        vec3 _476 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        if (dot(_476, _476) < 9.9999999600419720025001879548654e-13)
        {
            _648 = _317 - (normalize(cross(vec3(frame_info.camera_transform[0].x, frame_info.camera_transform[1].x, frame_info.camera_transform[2].x), vec3(frame_info.camera_transform[0].y, frame_info.camera_transform[1].y, frame_info.camera_transform[2].y))) * frame_info.depth_bias);
            break;
        }
        vec3 _446 = frame_info.camera_position - _317;
        float _449 = dot(_446, _446);
        if (_449 <= 9.9999999600419720025001879548654e-13)
        {
            _648 = _317;
            break;
        }
        _648 = _317 + (_446 * min(frame_info.depth_bias * inversesqrt(_449), 0.9900000095367431640625));
        break;
    } while(false);
    vec4 _372 = frame_info.camera_transform * vec4(_648, 1.0);
    vec4 _653 = vec4(0.0);
    if (any(notEqual(frame_info.depth_offset, vec4(0.0))))
    {
        float _649 = 0.0;
        if (any(notEqual(frame_info.depth_offset.zw, vec2(0.0))))
        {
            _649 = floor(fract(sin(dot(model_transform_3.xyz, vec3(12.98980045318603515625, 78.233001708984375, 37.71900177001953125))) * 43758.546875) * 3.0);
        }
        else
        {
            _649 = 0.0;
        }
        float _573 = length(_648) + length(frame_info.camera_position);
        vec3 _610 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        float _650 = 0.0;
        if (dot(_610, _610) < 9.9999999600419720025001879548654e-13)
        {
            _650 = _573 * length(vec3(frame_info.camera_transform[0].z, frame_info.camera_transform[1].z, frame_info.camera_transform[2].z));
        }
        else
        {
            _650 = _573 / max(abs(_372.w), max(_573 * 0.015625, 9.9999999747524270787835121154785e-07));
        }
        vec2 _538 = (frame_info.depth_offset.xy + (frame_info.depth_offset.zw * _649)) * clamp(_650, 1.0, 64.0);
        vec4 _647 = _372;
        _647.z = (_372.z * (1.0 + _538.x)) + (_538.y * _372.w);
        _653 = _647;
    }
    else
    {
        _653 = _372;
    }
    gl_Position = _653;
    v_viewvector = frame_info.camera_position - _317;
    v_normal = vec3(0.0);
    v_texture_coords = vec2(0.0);
    v_texture_coords_1 = vec2(0.0);
    v_color = vec4(0.0);
    v_tangent = vec4(0.0);
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}


void main() {
  _impeller_user_main();
  gl_Position.y *= _impeller_y_flip;
}
