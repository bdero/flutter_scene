#version 300 es
uniform float _impeller_y_flip;


layout(std140) uniform FrameInfo
{
    mat4 model_transform;
    mat4 camera_transform;
    vec3 camera_position;
    float enable_skinning;
    float joint_texture_size;
    float depth_bias;
    vec4 depth_offset;
} frame_info;

uniform highp sampler2D joints_texture;

layout(location = 7) in vec4 weights;
layout(location = 6) in vec4 joints;
layout(location = 0) in vec3 position;
layout(location = 1) in vec3 normal;
layout(location = 5) in vec4 tangent;
layout(location = 2) in vec2 texture_coords;
layout(location = 3) in vec2 texture_coords_1;
layout(location = 4) in vec4 color;
out vec3 v_position;
out vec3 v_viewvector;
out vec3 v_normal;
out vec2 v_texture_coords;
out vec2 v_texture_coords_1;
out vec4 v_color;
out vec4 v_tangent;

void _impeller_user_main()
{
    mat4 _1754 = mat4(vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    if (frame_info.enable_skinning == 1.0)
    {
        float _581 = ((weights.x + weights.y) + weights.z) + weights.w;
        vec4 _1753 = vec4(0.0);
        if (_581 > 0.0)
        {
            _1753 = weights / vec4(_581);
        }
        else
        {
            _1753 = vec4(1.0, 0.0, 0.0, 0.0);
        }
        float _951 = 1.0 / frame_info.joint_texture_size;
        float _953 = joints.x * 4.0;
        float _957 = mod(_953, frame_info.joint_texture_size);
        float _966 = (floor(_953 / frame_info.joint_texture_size) + 0.5) * _951;
        mat4 _603 = mat4(textureLod(joints_texture, vec2((_957 + 0.5) * _951, _966), 0.0), textureLod(joints_texture, vec2((_957 + 1.5) * _951, _966), 0.0), textureLod(joints_texture, vec2((_957 + 2.5) * _951, _966), 0.0), textureLod(joints_texture, vec2((_957 + 3.5) * _951, _966), 0.0)) * _1753.x;
        float _1032 = joints.y * 4.0;
        float _1036 = mod(_1032, frame_info.joint_texture_size);
        float _1045 = (floor(_1032 / frame_info.joint_texture_size) + 0.5) * _951;
        mat4 _610 = mat4(textureLod(joints_texture, vec2((_1036 + 0.5) * _951, _1045), 0.0), textureLod(joints_texture, vec2((_1036 + 1.5) * _951, _1045), 0.0), textureLod(joints_texture, vec2((_1036 + 2.5) * _951, _1045), 0.0), textureLod(joints_texture, vec2((_1036 + 3.5) * _951, _1045), 0.0)) * _1753.y;
        float _1111 = joints.z * 4.0;
        float _1115 = mod(_1111, frame_info.joint_texture_size);
        float _1124 = (floor(_1111 / frame_info.joint_texture_size) + 0.5) * _951;
        mat4 _630 = mat4(textureLod(joints_texture, vec2((_1115 + 0.5) * _951, _1124), 0.0), textureLod(joints_texture, vec2((_1115 + 1.5) * _951, _1124), 0.0), textureLod(joints_texture, vec2((_1115 + 2.5) * _951, _1124), 0.0), textureLod(joints_texture, vec2((_1115 + 3.5) * _951, _1124), 0.0)) * _1753.z;
        float _1190 = joints.w * 4.0;
        float _1194 = mod(_1190, frame_info.joint_texture_size);
        float _1203 = (floor(_1190 / frame_info.joint_texture_size) + 0.5) * _951;
        mat4 _650 = mat4(textureLod(joints_texture, vec2((_1194 + 0.5) * _951, _1203), 0.0), textureLod(joints_texture, vec2((_1194 + 1.5) * _951, _1203), 0.0), textureLod(joints_texture, vec2((_1194 + 2.5) * _951, _1203), 0.0), textureLod(joints_texture, vec2((_1194 + 3.5) * _951, _1203), 0.0)) * _1753.w;
        _1754 = mat4(((_603[0] + _610[0]) + _630[0]) + _650[0], ((_603[1] + _610[1]) + _630[1]) + _650[1], ((_603[2] + _610[2]) + _630[2]) + _650[2], ((_603[3] + _610[3]) + _630[3]) + _650[3]);
    }
    else
    {
        _1754 = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
    }
    mat4 _696 = frame_info.model_transform * _1754;
    vec3 _731 = (_696 * vec4(position, 1.0)).xyz;
    vec3 _735 = _696[0].xyz;
    vec3 _737 = _696[1].xyz;
    vec3 _739 = _696[2].xyz;
    mat3 _740 = mat3(_735, _737, _739);
    mat3 _1755 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
    do
    {
        vec3 _1269 = cross(_737, _739);
        float _1297 = dot(_735, _1269);
        if (_1297 == 0.0)
        {
            _1755 = _740;
            break;
        }
        _1755 = mat3(_1269, cross(_739, _735), cross(_735, _737)) * sign(_1297);
        break;
    } while(false);
    vec3 _744 = _1755 * normal;
    vec3 _757 = _740 * tangent.xyz;
    float _761 = dot(_757, _757);
    float _1756 = 0.0;
    if (determinant(_740) < 0.0)
    {
        _1756 = -tangent.w;
    }
    else
    {
        _1756 = tangent.w;
    }
    vec4 _1757 = vec4(0.0);
    if (_761 > 1.0000000133514319600180897396058e-10)
    {
        _1757 = vec4(_757 * inversesqrt(_761), _1756);
    }
    else
    {
        _1757 = vec4(0.0);
    }
    v_position = _731;
    vec3 _1758 = vec3(0.0);
    do
    {
        if (frame_info.depth_bias <= 0.0)
        {
            _1758 = _731;
            break;
        }
        vec3 _1367 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        if (dot(_1367, _1367) < 9.9999999600419720025001879548654e-13)
        {
            _1758 = _731 - (normalize(cross(vec3(frame_info.camera_transform[0].x, frame_info.camera_transform[1].x, frame_info.camera_transform[2].x), vec3(frame_info.camera_transform[0].y, frame_info.camera_transform[1].y, frame_info.camera_transform[2].y))) * frame_info.depth_bias);
            break;
        }
        vec3 _1337 = frame_info.camera_position - _731;
        float _1340 = dot(_1337, _1337);
        if (_1340 <= 9.9999999600419720025001879548654e-13)
        {
            _1758 = _731;
            break;
        }
        _1758 = _731 + (_1337 * min(frame_info.depth_bias * inversesqrt(_1340), 0.9900000095367431640625));
        break;
    } while(false);
    vec4 _854 = frame_info.camera_transform * vec4(_1758, 1.0);
    vec4 _865 = vec4(frame_info.depth_offset.xy, 0.0, 0.0);
    vec4 _870 = vec4(frame_info.depth_offset.z, 0.0, frame_info.depth_offset.w, 0.0);
    bool _1413 = any(notEqual(_865, vec4(0.0)));
    bool _1420 = false;
    if (!_1413)
    {
        _1420 = any(notEqual(_870, vec4(0.0)));
    }
    else
    {
        _1420 = _1413;
    }
    vec4 _1776 = vec4(0.0);
    if (_1420)
    {
        vec2 _1423 = _865.zw;
        bool _1425 = any(notEqual(_1423, vec2(0.0)));
        float _1759 = 0.0;
        if ((!_1425) ? false : _1425)
        {
            float _1499 = fract(0.0);
            _1759 = floor(_1499 * 3.0);
        }
        else
        {
            _1759 = 0.0;
        }
        float _1512 = length(_1758) + length(frame_info.camera_position);
        vec3 _1549 = vec3(frame_info.camera_transform[0].w, frame_info.camera_transform[1].w, frame_info.camera_transform[2].w);
        bool _1553 = dot(_1549, _1549) < 9.9999999600419720025001879548654e-13;
        float _1761 = 0.0;
        if (_1553)
        {
            _1761 = _1512 * length(vec3(frame_info.camera_transform[0].z, frame_info.camera_transform[1].z, frame_info.camera_transform[2].z));
        }
        else
        {
            _1761 = _1512 / max(abs(_854.w), max(_1512 * 0.015625, 9.9999999747524270787835121154785e-07));
        }
        vec2 _1449 = (_865.xy + (_1423 * _1759)) * clamp(_1761, 1.0, 64.0);
        float _1768 = 0.0;
        if (any(notEqual(_870, vec4(0.0))))
        {
            vec2 _1764 = vec2(0.0);
            do
            {
                float _1570 = dot(_744, _744);
                if (_1570 < 9.9999999600419720025001879548654e-13)
                {
                    _1764 = vec2(0.0);
                    break;
                }
                vec3 _1578 = _744 * inversesqrt(_1570);
                float _1582 = dot(_1578, normalize(cross(vec3(frame_info.camera_transform[0].x, frame_info.camera_transform[1].x, frame_info.camera_transform[2].x), vec3(frame_info.camera_transform[0].y, frame_info.camera_transform[1].y, frame_info.camera_transform[2].y))));
                float _1588 = sqrt(max(1.0 - (_1582 * _1582), 0.0));
                float _1762 = 0.0;
                float _1763 = 0.0;
                if (_1553)
                {
                    _1763 = 1.0;
                    _1762 = abs(_1582);
                }
                else
                {
                    vec3 _1597 = _1758 - frame_info.camera_position;
                    _1763 = max(length(_1597), 9.9999999747524270787835121154785e-07);
                    _1762 = abs(dot(_1578, _1597));
                }
                _1764 = vec2(_1588 / max(_1762, _1763 * 0.015625), _1588 / max(_1762, _1763 * 0.125));
                break;
            } while(false);
            _1768 = (frame_info.depth_offset.z * _1764.x) + (frame_info.depth_offset.w * _1764.y);
        }
        else
        {
            _1768 = 0.0;
        }
        vec4 _1751 = _854;
        _1751.z = (_854.z * (1.0 + _1449.x)) + ((_1449.y + _1768) * _854.w);
        _1776 = _1751;
    }
    else
    {
        _1776 = _854;
    }
    gl_Position = _1776;
    v_viewvector = frame_info.camera_position - _731;
    float _1662 = length(_744);
    vec3 _1777 = vec3(0.0);
    if (_1662 > 0.0)
    {
        _1777 = _744 / vec3(_1662);
    }
    else
    {
        _1777 = _744;
    }
    v_normal = _1777;
    v_texture_coords = texture_coords;
    v_texture_coords_1 = texture_coords_1;
    v_color = color;
    float _1679 = length(_1757.xyz);
    vec3 _1778 = vec3(0.0);
    if (_1679 > 0.0)
    {
        _1778 = _1757.xyz / vec3(_1679);
    }
    else
    {
        _1778 = _1757.xyz;
    }
    v_tangent = vec4(_1778, _1757.w);
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
}


void main() {
  _impeller_user_main();
  gl_Position.y *= _impeller_y_flip;
}
