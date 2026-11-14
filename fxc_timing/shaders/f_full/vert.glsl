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
    vec3 _516 = (mat4(model_transform_0, model_transform_1, model_transform_2, model_transform_3) * vec4(position, 1.0)).xyz;
    mat3 _526 = mat3(model_transform_0.xyz, model_transform_1.xyz, model_transform_2.xyz);
    mat3 _1221 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
    do
    {
        vec3 _741 = cross(model_transform_1.xyz, model_transform_2.xyz);
        float _769 = dot(model_transform_0.xyz, _741);
        if (_769 == 0.0)
        {
            _1221 = _526;
            break;
        }
        _1221 = mat3(_741, cross(model_transform_2.xyz, model_transform_0.xyz), cross(model_transform_0.xyz, model_transform_1.xyz)) * sign(_769);
        break;
    } while(false);
    vec3 _530 = _1221 * normal;
    vec3 _543 = _526 * tangent.xyz;
    float _547 = dot(_543, _543);
    float _1222 = 0.0;
    if (determinant(_526) < 0.0)
    {
        _1222 = -tangent.w;
    }
    else
    {
        _1222 = tangent.w;
    }
    vec4 _1223 = vec4(0.0);
    if (_547 > 1.0000000133514319600180897396058e-10)
    {
        _1223 = vec4(_543 * inversesqrt(_547), _1222);
    }
    else
    {
        _1223 = vec4(0.0);
    }
    v_position = _516;
    vec3 _1224 = vec3(0.0);
    do
    {
        if (frame_info.depth_bias <= 0.0)
        {
            _1224 = _516;
            break;
        }
        vec3 _839 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        if (dot(_839, _839) < 9.9999999600419720025001879548654e-13)
        {
            _1224 = _516 - (normalize(cross(vec3(frame_info.camera_transform[0].x, frame_info.camera_transform[1].x, frame_info.camera_transform[2].x), vec3(frame_info.camera_transform[0].y, frame_info.camera_transform[1].y, frame_info.camera_transform[2].y))) * frame_info.depth_bias);
            break;
        }
        vec3 _809 = frame_info.camera_position - _516;
        float _812 = dot(_809, _809);
        if (_812 <= 9.9999999600419720025001879548654e-13)
        {
            _1224 = _516;
            break;
        }
        _1224 = _516 + (_809 * min(frame_info.depth_bias * inversesqrt(_812), 0.9900000095367431640625));
        break;
    } while(false);
    vec4 _648 = frame_info.camera_transform * vec4(_1224, 1.0);
    bool _885 = any(notEqual(frame_info.depth_offset, vec4(0.0)));
    bool _892 = false;
    if (!_885)
    {
        _892 = any(notEqual(frame_info.depth_slope, vec4(0.0)));
    }
    else
    {
        _892 = _885;
    }
    vec4 _1242 = vec4(0.0);
    if (_892)
    {
        bool _897 = any(notEqual(frame_info.depth_offset.zw, vec2(0.0)));
        bool _904 = false;
        if (!_897)
        {
            _904 = frame_info.depth_slope.y != 0.0;
        }
        else
        {
            _904 = _897;
        }
        float _1225 = 0.0;
        if (_904)
        {
            _1225 = floor(fract(sin(dot(model_transform_3.xyz, vec3(12.98980045318603515625, 78.233001708984375, 37.71900177001953125))) * 43758.546875) * 3.0);
        }
        else
        {
            _1225 = 0.0;
        }
        float _984 = length(_1224) + length(frame_info.camera_position);
        vec3 _1021 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        bool _1025 = dot(_1021, _1021) < 9.9999999600419720025001879548654e-13;
        float _1227 = 0.0;
        if (_1025)
        {
            _1227 = _984 * length(vec3(frame_info.camera_transform[0].z, frame_info.camera_transform[1].z, frame_info.camera_transform[2].z));
        }
        else
        {
            _1227 = _984 / max(abs(_648.w), max(_984 * 0.015625, 9.9999999747524270787835121154785e-07));
        }
        vec2 _921 = (frame_info.depth_offset.xy + (frame_info.depth_offset.zw * _1225)) * clamp(_1227, 1.0, 64.0);
        float _1234 = 0.0;
        if (any(notEqual(frame_info.depth_slope, vec4(0.0))))
        {
            vec2 _1230 = vec2(0.0);
            do
            {
                float _1042 = dot(_530, _530);
                if (_1042 < 9.9999999600419720025001879548654e-13)
                {
                    _1230 = vec2(0.0);
                    break;
                }
                vec3 _1050 = _530 * inversesqrt(_1042);
                float _1054 = dot(_1050, normalize(cross(vec3(frame_info.camera_transform[0].x, frame_info.camera_transform[1].x, frame_info.camera_transform[2].x), vec3(frame_info.camera_transform[0].y, frame_info.camera_transform[1].y, frame_info.camera_transform[2].y))));
                float _1060 = sqrt(max(1.0 - (_1054 * _1054), 0.0));
                float _1228 = 0.0;
                float _1229 = 0.0;
                if (_1025)
                {
                    _1229 = 1.0;
                    _1228 = abs(_1054);
                }
                else
                {
                    vec3 _1069 = _1224 - frame_info.camera_position;
                    _1229 = max(length(_1069), 9.9999999747524270787835121154785e-07);
                    _1228 = abs(dot(_1050, _1069));
                }
                _1230 = vec2(_1060 / max(_1228, _1229 * 0.015625), _1060 / max(_1228, _1229 * 0.125));
                break;
            } while(false);
            _1234 = (frame_info.depth_slope.x * _1230.x) + ((frame_info.depth_slope.z + (frame_info.depth_slope.y * _1225)) * _1230.y);
        }
        else
        {
            _1234 = 0.0;
        }
        vec4 _1219 = _648;
        _1219.z = (_648.z * (1.0 + _921.x)) + ((_921.y + _1234) * _648.w);
        _1242 = _1219;
    }
    else
    {
        _1242 = _648;
    }
    gl_Position = _1242;
    v_viewvector = frame_info.camera_position - _516;
    float _1134 = length(_530);
    vec3 _1243 = vec3(0.0);
    if (_1134 > 0.0)
    {
        _1243 = _530 / vec3(_1134);
    }
    else
    {
        _1243 = _530;
    }
    v_normal = _1243;
    v_texture_coords = texture_coords;
    v_texture_coords_1 = texture_coords_1;
    v_color = color * instance_color;
    float _1151 = length(_1223.xyz);
    vec3 _1244 = vec3(0.0);
    if (_1151 > 0.0)
    {
        _1244 = _1223.xyz / vec3(_1151);
    }
    else
    {
        _1244 = _1223.xyz;
    }
    v_tangent = vec4(_1244, _1223.w);
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}


void main() {
  _impeller_user_main();
  gl_Position.y *= _impeller_y_flip;
}
