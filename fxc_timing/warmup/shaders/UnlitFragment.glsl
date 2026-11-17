#version 300 es
precision mediump float;
precision highp int;

layout(std140) uniform ViewInfo
{
    highp vec4 camera_forward;
} view_info;

layout(std140) uniform FogInfo
{
    highp vec4 params0;
    highp vec4 params1;
    highp vec4 params2;
    vec4 color;
    vec4 sun;
    vec4 sun_dir;
} _FogInfo;

layout(std140) uniform FragInfo
{
    vec4 color;
    float vertex_color_weight;
    float fade;
    float display_referred;
} frag_info;

layout(std140) uniform TextureTransform
{
    highp vec4 uv_transform;
    highp vec4 uv_rotation;
} texture_transform;

uniform highp sampler2D base_color_texture;

in highp vec3 v_viewvector;
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in highp vec3 v_position;
in vec4 v_color;
layout(location = 0) out vec4 frag_color;

void main()
{
    vec4 _548 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    highp vec2 _1136 = vec2(0.0);
    if (int(texture_transform.uv_rotation.z + 0.5) == 1)
    {
        _1136 = v_texture_coords_1;
    }
    else
    {
        _1136 = v_texture_coords;
    }
    highp vec2 _722 = _1136 * texture_transform.uv_transform.zw;
    highp float _728 = _722.x;
    highp float _733 = _722.y;
    highp vec4 _567 = texture(base_color_texture, texture_transform.uv_transform.xy + vec2((texture_transform.uv_rotation.x * _728) + (texture_transform.uv_rotation.y * _733), ((-texture_transform.uv_rotation.y) * _728) + (texture_transform.uv_rotation.x * _733)));
    bool _571 = frag_info.display_referred > 0.5;
    vec3 _1137 = vec3(0.0);
    if (_571)
    {
        _1137 = _567.xyz;
    }
    else
    {
        vec3 _582 = _567.xyz;
        _1137 = mix(_582 * vec3(0.077399380505084991455078125), pow((_582 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _582));
    }
    vec4 _610 = vec4((_1137 * _548.xyz) * frag_info.color.xyz, 1.0) * ((_567.w * _548.w) * frag_info.color.w);
    highp vec4 _1152 = vec4(0.0);
    if (_571)
    {
        _1152 = _610;
    }
    else
    {
        highp vec4 _1151 = vec4(0.0);
        do
        {
            if (_FogInfo.params0.y < 0.5)
            {
                _1151 = _610;
                break;
            }
            int _807 = int(_FogInfo.params0.x + 0.5);
            if (_807 == 0)
            {
                _1151 = _610;
                break;
            }
            bool _815 = view_info.camera_forward.w > 0.5;
            highp float _1138 = 0.0;
            if (_815)
            {
                _1138 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
            }
            else
            {
                _1138 = length(v_viewvector);
            }
            if ((_FogInfo.params1.w > 0.0) && (_1138 > _FogInfo.params1.w))
            {
                _1151 = _610;
                break;
            }
            float _1142 = 0.0;
            if (_807 == 1)
            {
                _1142 = clamp((_1138 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
            }
            else
            {
                float _1143 = 0.0;
                if (_807 == 2)
                {
                    highp float _1141 = 0.0;
                    if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                    {
                        highp vec3 _1139 = vec3(0.0);
                        if (_815)
                        {
                            _1139 = v_position - (view_info.camera_forward.xyz * _1138);
                        }
                        else
                        {
                            _1139 = v_position + v_viewvector;
                        }
                        highp float _888 = -_FogInfo.params2.y;
                        highp float _895 = _FogInfo.params1.x * exp(_888 * (_1139.y - _FogInfo.params2.x));
                        highp float _912 = _FogInfo.params2.y * (v_position.y - _1139.y);
                        highp float _1140 = 0.0;
                        if (abs(_912) > 0.00124999997206032276153564453125)
                        {
                            _1140 = (_895 - (_FogInfo.params1.x * exp(_888 * (v_position.y - _FogInfo.params2.x)))) / _912;
                        }
                        else
                        {
                            _1140 = _895;
                        }
                        _1141 = _1140 * max(_1138 - _FogInfo.params1.y, 0.0);
                    }
                    else
                    {
                        _1141 = _FogInfo.params1.x * max(_1138 - _FogInfo.params1.y, 0.0);
                    }
                    _1143 = 1.0 - exp(-_1141);
                }
                else
                {
                    highp float _950 = _FogInfo.params1.x * max(_1138 - _FogInfo.params1.y, 0.0);
                    _1143 = 1.0 - exp((-_950) * _950);
                }
                _1142 = _1143;
            }
            highp float _962 = min(_1142, _FogInfo.params0.z);
            if (_962 <= 0.0)
            {
                _1151 = _610;
                break;
            }
            highp vec3 _975 = mix(_FogInfo.color.xyz, _FogInfo.color.xyz, vec3(_FogInfo.params0.w));
            bool _978 = _FogInfo.sun.w > 0.5;
            bool _984 = false;
            if (_978)
            {
                _984 = _FogInfo.params2.z > 0.0;
            }
            else
            {
                _984 = _978;
            }
            vec3 _1147 = vec3(0.0);
            if (_984)
            {
                vec3 mp_copy_1144 = vec3(0.0);
                highp vec3 _1144 = vec3(0.0);
                if (_815)
                {
                    _1144 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _1144 = normalize(v_viewvector);
                }
                mp_copy_1144 = _1144;
                highp float _1000 = pow(max(dot(-mp_copy_1144, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                float mp_copy_1000 = _1000;
                _1147 = _975 + ((_FogInfo.sun.xyz * mp_copy_1000) * _FogInfo.params2.z);
            }
            else
            {
                _1147 = _975;
            }
            float _1013 = _610.w;
            _1151 = vec4(mix(_610.xyz, _1147 * _1013, vec3(_962)), _1013);
            break;
        } while(false);
        _1152 = _1151;
    }
    frag_color = _1152;
    float _1154 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _1154 = 1.0;
    }
    else
    {
        _1154 = abs(frag_info.fade);
    }
    frag_color *= _1154;
}

