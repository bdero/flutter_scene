#version 300 es
precision mediump float;
precision highp int;

layout(std140) uniform ViewInfo
{
    highp vec4 camera_forward;
} view_info;

layout(std140) uniform RadianceLayoutInfo
{
    float mip_layout;
} radiance_layout_info;

layout(std140) uniform DebugViewInfo
{
    vec4 view;
    vec4 params;
    vec4 left;
    highp vec4 depth;
} debug_view_info;

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
    vec4 emissive_factor;
    highp vec4 punctual_dims;
    highp vec4 spot_shadow_params;
    highp vec4 scene_inputs;
    highp vec4 camera_forward;
    highp vec4 camera_right;
    highp vec4 camera_up;
    highp vec4 transmission_info;
    highp vec4 probe_box;
    highp vec4 probe_extents;
    highp vec4 directional_light_direction;
    highp vec4 directional_light_color;
    highp mat4 light_space_matrix[4];
    highp vec4 cascade_box_sizes;
    float vertex_color_weight;
    float metallic_factor;
    float roughness_factor;
    float has_normal_map;
    float normal_scale;
    float occlusion_strength;
    float environment_intensity;
    float has_directional_light;
    float casts_shadow;
    highp float shadow_bias;
    highp float shadow_normal_bias;
    highp float shadow_texel_size;
    float alpha_mode;
    float alpha_cutoff;
    highp float shadow_fade;
    highp float shadow_softness;
    highp float shadow_cascade_count;
    float fade;
    float specular_aa_variance;
    float specular_aa_threshold;
    highp mat4 environment_transform;
    highp vec4 ssao_params;
    highp vec4 radiance_blend;
    vec4 ssao_lighting;
    highp vec4 model_scale;
    vec4 dielectric_f0;
    highp vec4 gi_grid;
    highp vec4 gi_anchor;
    highp vec4 gi_counts;
    highp vec4 gi_atlas;
    highp vec4 gi_visibility;
    highp vec4 froxel_grid;
    highp vec4 view_projection;
    highp vec4 camera_position;
} frag_info;

layout(std140) uniform TextureTransforms
{
    highp vec4 base_color_transform;
    highp vec4 base_color_rotation;
    highp vec4 metallic_roughness_transform;
    highp vec4 metallic_roughness_rotation;
    highp vec4 normal_transform;
    highp vec4 normal_rotation;
    highp vec4 emissive_transform;
    highp vec4 emissive_rotation;
    highp vec4 occlusion_transform;
    highp vec4 occlusion_rotation;
} texture_transforms;

uniform highp sampler2D irradiance_field;
uniform highp sampler2D shadow_map;
uniform highp sampler2D punctual_lights;
uniform highp sampler2D punctual_index;
uniform mediump sampler2D ssao_texture;
uniform mediump sampler2D prefiltered_radiance;
uniform mediump sampler2D prefiltered_radiance_b;
uniform mediump sampler2D brdf_lut;
uniform mediump sampler2D base_color_texture;
uniform mediump sampler2D normal_texture;
uniform mediump sampler2D metallic_roughness_texture;
uniform mediump sampler2D occlusion_texture;
uniform mediump sampler2D emissive_texture;

in vec3 v_normal;
in highp vec3 v_viewvector;
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in vec4 v_tangent;
in vec4 v_color;
in highp vec3 v_position;
layout(location = 0) out vec4 frag_color;

void main()
{
    highp float _7150 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_7150 = _7150;
    vec3 _7152 = normalize(v_normal);
    vec3 _7154 = _7152 * mp_copy_7150;
    vec4 _7195 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _7198 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _30817 = vec2(0.0);
    if (_7198)
    {
        highp vec2 _30816 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _30816 = v_texture_coords_1;
        }
        else
        {
            _30816 = v_texture_coords;
        }
        highp vec2 _7385 = _30816 * texture_transforms.base_color_transform.zw;
        highp float _7391 = _7385.x;
        highp float _7396 = _7385.y;
        _30817 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _7391) - (texture_transforms.base_color_rotation.y * _7396), (texture_transforms.base_color_rotation.y * _7391) + (texture_transforms.base_color_rotation.x * _7396));
    }
    else
    {
        _30817 = v_texture_coords;
    }
    vec4 _7212 = texture(base_color_texture, _30817);
    vec3 _7214 = _7212.xyz;
    vec3 _7222 = (mix(_7214 * vec3(0.077399380505084991455078125), pow((_7214 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7214)) * _7195.xyz) * frag_info.color.xyz;
    float _35252 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_7212.w * _7195.w) * frag_info.color.w);
    float _7238 = _7222.x;
    float _7239 = _7222.y;
    float _7240 = _7222.z;
    vec4 _7241 = vec4(_7238, _7239, _7240, _35252);
    vec3 _30829 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _30820 = vec2(0.0);
        if (_7198)
        {
            highp vec2 _30819 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _30819 = v_texture_coords_1;
            }
            else
            {
                _30819 = v_texture_coords;
            }
            highp vec2 _7479 = _30819 * texture_transforms.normal_transform.zw;
            highp float _7485 = _7479.x;
            highp float _7490 = _7479.y;
            _30820 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _7485) - (texture_transforms.normal_rotation.y * _7490), (texture_transforms.normal_rotation.y * _7485) + (texture_transforms.normal_rotation.x * _7490));
        }
        else
        {
            _30820 = v_texture_coords;
        }
        vec3 _7537 = ((texture(normal_texture, _30820).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _7541 = _7537.xy * vec2(frag_info.normal_scale);
        vec3 _29728 = _7537;
        _29728.x = _7541.x;
        _29728.y = _7541.y;
        highp vec3 _7547 = -v_viewvector;
        mat3 _30828 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _7577 = v_tangent.xyz - (_7154 * dot(_7154, v_tangent.xyz));
            highp float _7580 = dot(_7577, _7577);
            bool _7582 = _7580 <= 1.0000000133514319600180897396058e-10;
            bool _7590 = false;
            if (!_7582)
            {
                _7590 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _7590 = _7582;
            }
            if (_7590)
            {
                highp vec2 _7648 = dFdx(_30820);
                highp vec2 _7650 = dFdy(_30820);
                bvec2 _35254 = bvec2(length(_7648) == 0.0);
                highp vec2 _35255 = vec2(_35254.x ? vec2(1.0, 0.0).x : _7648.x, _35254.y ? vec2(1.0, 0.0).y : _7648.y);
                bvec2 _35256 = bvec2(length(_7650) == 0.0);
                highp vec2 _35257 = vec2(_35256.x ? vec2(0.0, 1.0).x : _7650.x, _35256.y ? vec2(0.0, 1.0).y : _7650.y);
                highp vec3 _7663 = cross(dFdy(_7547), _7154);
                highp vec3 _7666 = cross(_7154, dFdx(_7547));
                highp vec3 _7675 = (_7663 * _35255.x) + (_7666 * _35257.x);
                highp vec3 _7684 = (_7663 * _35255.y) + (_7666 * _35257.y);
                highp float _7693 = inversesqrt(max(max(dot(_7675, _7675), dot(_7684, _7684)), 9.9999996826552253889678874634872e-21));
                _30828 = mat3(_7675 * _7693, _7684 * _7693, _7154);
                break;
            }
            highp vec3 _7600 = _7577 * inversesqrt(_7580);
            _30828 = mat3(_7600, normalize(cross(_7154, _7600)) * sign(v_tangent.w), _7154);
            break;
        } while(false);
        _30829 = normalize(_30828 * _29728);
    }
    else
    {
        _30829 = _7154;
    }
    highp vec2 _30831 = vec2(0.0);
    if (_7198)
    {
        highp vec2 _30830 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _30830 = v_texture_coords_1;
        }
        else
        {
            _30830 = v_texture_coords;
        }
        highp vec2 _7755 = _30830 * texture_transforms.metallic_roughness_transform.zw;
        highp float _7761 = _7755.x;
        highp float _7766 = _7755.y;
        _30831 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _7761) - (texture_transforms.metallic_roughness_rotation.y * _7766), (texture_transforms.metallic_roughness_rotation.y * _7761) + (texture_transforms.metallic_roughness_rotation.x * _7766));
    }
    else
    {
        _30831 = v_texture_coords;
    }
    vec4 _7281 = texture(metallic_roughness_texture, _30831);
    float _7287 = clamp(_7281.z * frag_info.metallic_factor, 0.0, 1.0);
    float _7294 = clamp(_7281.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _30833 = vec2(0.0);
    if (_7198)
    {
        highp vec2 _30832 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _30832 = v_texture_coords_1;
        }
        else
        {
            _30832 = v_texture_coords;
        }
        highp vec2 _7825 = _30832 * texture_transforms.occlusion_transform.zw;
        highp float _7831 = _7825.x;
        highp float _7836 = _7825.y;
        _30833 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _7831) - (texture_transforms.occlusion_rotation.y * _7836), (texture_transforms.occlusion_rotation.y * _7831) + (texture_transforms.occlusion_rotation.x * _7836));
    }
    else
    {
        _30833 = v_texture_coords;
    }
    vec4 _7309 = texture(occlusion_texture, _30833);
    float _7316 = 1.0 - ((1.0 - _7309.x) * frag_info.occlusion_strength);
    highp vec2 _30835 = vec2(0.0);
    if (_7198)
    {
        highp vec2 _30834 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _30834 = v_texture_coords_1;
        }
        else
        {
            _30834 = v_texture_coords;
        }
        highp vec2 _7895 = _30834 * texture_transforms.emissive_transform.zw;
        highp float _7901 = _7895.x;
        highp float _7906 = _7895.y;
        _30835 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _7901) - (texture_transforms.emissive_rotation.y * _7906), (texture_transforms.emissive_rotation.y * _7901) + (texture_transforms.emissive_rotation.x * _7906));
    }
    else
    {
        _30835 = v_texture_coords;
    }
    vec4 _7331 = texture(emissive_texture, _30835);
    vec3 _7332 = _7331.xyz;
    vec3 _7340 = (mix(_7332 * vec3(0.077399380505084991455078125), pow((_7332 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7332)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w;
    float _30865 = 0.0;
    do
    {
        if (debug_view_info.view.x < 0.5)
        {
            _30865 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _30865 = 1.0;
            break;
        }
        _30865 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    if (_30865 > 2.5)
    {
        vec4 _34031 = vec4(0.0);
        do
        {
            if (debug_view_info.view.x < 20.0)
            {
                vec3 _34017 = vec3(0.0);
                if (debug_view_info.view.x == 1.0)
                {
                    float _8380 = length(_7154);
                    vec3 _34015 = vec3(0.0);
                    if (_8380 > 9.9999999747524270787835121154785e-07)
                    {
                        _34015 = _7154 / vec3(_8380);
                    }
                    else
                    {
                        _34015 = vec3(0.0);
                    }
                    _34017 = ((_34015 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                }
                else
                {
                    vec3 _34018 = vec3(0.0);
                    if (debug_view_info.view.x == 2.0)
                    {
                        float _8403 = length(_30829);
                        vec3 _34013 = vec3(0.0);
                        if (_8403 > 9.9999999747524270787835121154785e-07)
                        {
                            _34013 = _30829 / vec3(_8403);
                        }
                        else
                        {
                            _34013 = vec3(0.0);
                        }
                        _34018 = ((_34013 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                    }
                    else
                    {
                        vec3 _34019 = vec3(0.0);
                        if (debug_view_info.view.x == 3.0)
                        {
                            float _8426 = length(v_tangent.xyz);
                            vec3 _34011 = vec3(0.0);
                            if (_8426 > 9.9999999747524270787835121154785e-07)
                            {
                                _34011 = v_tangent.xyz / vec3(_8426);
                            }
                            else
                            {
                                _34011 = vec3(0.0);
                            }
                            _34019 = ((_34011 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _34020 = vec3(0.0);
                            if (debug_view_info.view.x == 4.0)
                            {
                                highp float _8059 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_8059 = _8059;
                                vec3 _8060 = cross(_7152, v_tangent.xyz) * mp_copy_8059;
                                float _8449 = length(_8060);
                                vec3 _34009 = vec3(0.0);
                                if (_8449 > 9.9999999747524270787835121154785e-07)
                                {
                                    _34009 = _8060 / vec3(_8449);
                                }
                                else
                                {
                                    _34009 = vec3(0.0);
                                }
                                _34020 = ((_34009 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _34021 = vec3(0.0);
                                if (debug_view_info.view.x == 5.0)
                                {
                                    _34021 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _34022 = vec3(0.0);
                                    if (debug_view_info.view.x == 6.0)
                                    {
                                        _34022 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec3 _34023 = vec3(0.0);
                                        if (debug_view_info.view.x == 7.0)
                                        {
                                            _34023 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                        }
                                        else
                                        {
                                            vec3 _34024 = vec3(0.0);
                                            if (debug_view_info.view.x == 8.0)
                                            {
                                                vec3 _8484 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                _34024 = mix(_8484 * 12.9200000762939453125, (pow(max(_8484, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _8484));
                                            }
                                            else
                                            {
                                                vec3 _34025 = vec3(0.0);
                                                if (debug_view_info.view.x == 9.0)
                                                {
                                                    vec3 mp_copy_34005 = vec3(0.0);
                                                    highp vec3 _34005 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _34005 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _34005 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_34005 = _34005;
                                                    float _8520 = length(mp_copy_34005);
                                                    vec3 _34006 = vec3(0.0);
                                                    if (_8520 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _34006 = mp_copy_34005 / vec3(_8520);
                                                    }
                                                    else
                                                    {
                                                        _34006 = vec3(0.0);
                                                    }
                                                    _34025 = ((_34006 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                }
                                                else
                                                {
                                                    vec3 _34026 = vec3(0.0);
                                                    if (debug_view_info.view.x == 10.0)
                                                    {
                                                        float _8563 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                        float _8564 = (v_position.x - debug_view_info.params.x) / _8563;
                                                        bool _8568 = debug_view_info.view.w > 1.5;
                                                        float _33989 = 0.0;
                                                        if (_8568)
                                                        {
                                                            _33989 = fract(_8564);
                                                        }
                                                        else
                                                        {
                                                            float _33990 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _33990 = ((_8564 < 0.0) || (_8564 > 1.0)) ? 0.0 : _8564;
                                                            }
                                                            else
                                                            {
                                                                _33990 = clamp(_8564, 0.0, 1.0);
                                                            }
                                                            _33989 = _33990;
                                                        }
                                                        float _8615 = (v_position.y - debug_view_info.params.x) / _8563;
                                                        float _33995 = 0.0;
                                                        if (_8568)
                                                        {
                                                            _33995 = fract(_8615);
                                                        }
                                                        else
                                                        {
                                                            float _33996 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _33996 = ((_8615 < 0.0) || (_8615 > 1.0)) ? 0.0 : _8615;
                                                            }
                                                            else
                                                            {
                                                                _33996 = clamp(_8615, 0.0, 1.0);
                                                            }
                                                            _33995 = _33996;
                                                        }
                                                        float _8666 = (v_position.z - debug_view_info.params.x) / _8563;
                                                        float _34001 = 0.0;
                                                        if (_8568)
                                                        {
                                                            _34001 = fract(_8666);
                                                        }
                                                        else
                                                        {
                                                            float _34002 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34002 = ((_8666 < 0.0) || (_8666 > 1.0)) ? 0.0 : _8666;
                                                            }
                                                            else
                                                            {
                                                                _34002 = clamp(_8666, 0.0, 1.0);
                                                            }
                                                            _34001 = _34002;
                                                        }
                                                        _34026 = vec3(_33989 * debug_view_info.view.z, _33995 * debug_view_info.view.z, _34001 * debug_view_info.view.z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _34027 = vec3(0.0);
                                                        if (debug_view_info.view.x == 11.0)
                                                        {
                                                            bvec3 _8135 = bvec3(gl_FrontFacing);
                                                            _34027 = vec3(_8135.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _8135.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _8135.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _34028 = vec3(0.0);
                                                            if (debug_view_info.view.x == 12.0)
                                                            {
                                                                highp vec2 _8693 = v_texture_coords;
                                                                vec2 mp_copy_8693 = _8693;
                                                                vec2 _8705 = floor(mp_copy_8693 * 8.0);
                                                                float _8707 = _8705.x;
                                                                float _8709 = _8705.y;
                                                                float _8717 = _8707 + (_8709 * 8.0);
                                                                vec2 _8726 = step(vec2(0.0), mp_copy_8693) * step(mp_copy_8693, vec2(1.0));
                                                                _34028 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_8707 + _8709, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_8717 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_8717 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_8726.x * _8726.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _34029 = vec3(0.0);
                                                                if (debug_view_info.view.x == 13.0)
                                                                {
                                                                    highp vec2 _8776 = v_texture_coords_1;
                                                                    vec2 mp_copy_8776 = _8776;
                                                                    vec2 _8788 = floor(mp_copy_8776 * 8.0);
                                                                    float _8790 = _8788.x;
                                                                    float _8792 = _8788.y;
                                                                    float _8800 = _8790 + (_8792 * 8.0);
                                                                    vec2 _8809 = step(vec2(0.0), mp_copy_8776) * step(mp_copy_8776, vec2(1.0));
                                                                    _34029 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_8790 + _8792, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_8800 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_8800 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_8809.x * _8809.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _34030 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 14.0)
                                                                    {
                                                                        highp float _8875 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _8881 = debug_view_info.depth.x > 0.5;
                                                                        bool _8887 = false;
                                                                        if (_8881)
                                                                        {
                                                                            _8887 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _8887 = _8881;
                                                                        }
                                                                        highp float _33975 = 0.0;
                                                                        if (_8887)
                                                                        {
                                                                            _33975 = 1.1920928955078125e-07 / _8875;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _33976 = 0.0;
                                                                            if (_8881)
                                                                            {
                                                                                _33976 = 5.9604644775390625e-08 / (_8875 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _33976 = 5.9604644775390625e-08 / (_8875 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _33975 = _33976;
                                                                        }
                                                                        highp float _8916 = dot(_7154, view_info.camera_forward.xyz);
                                                                        highp float _8922 = sqrt(max(1.0 - (_8916 * _8916), 0.0));
                                                                        highp float _33973 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _33973 = (debug_view_info.depth.z * _8922) / max(abs(_8916), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _33973 = (((1.0 / (_8875 * _8875)) * debug_view_info.depth.z) * _8922) / max(abs(dot(_7154, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _8960 = log2(max(max(8.0 * _33975, _33973 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_8960 = _8960;
                                                                        float _8999 = (mp_copy_8960 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                        float _33985 = 0.0;
                                                                        if (debug_view_info.view.w > 1.5)
                                                                        {
                                                                            _33985 = fract(_8999);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _33986 = 0.0;
                                                                            if (debug_view_info.view.w > 0.5)
                                                                            {
                                                                                _33986 = ((_8999 < 0.0) || (_8999 > 1.0)) ? 0.0 : _8999;
                                                                            }
                                                                            else
                                                                            {
                                                                                _33986 = clamp(_8999, 0.0, 1.0);
                                                                            }
                                                                            _33985 = _33986;
                                                                        }
                                                                        _34030 = clamp(vec3(1.5) - abs(vec3(4.0 * _33985) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _9032 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _34030 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9032.x + _9032.y, 2.0)));
                                                                    }
                                                                    _34029 = _34030;
                                                                }
                                                                _34028 = _34029;
                                                            }
                                                            _34027 = _34028;
                                                        }
                                                        _34026 = _34027;
                                                    }
                                                    _34025 = _34026;
                                                }
                                                _34024 = _34025;
                                            }
                                            _34023 = _34024;
                                        }
                                        _34022 = _34023;
                                    }
                                    _34021 = _34022;
                                }
                                _34020 = _34021;
                            }
                            _34019 = _34020;
                        }
                        _34018 = _34019;
                    }
                    _34017 = _34018;
                }
                _34031 = vec4(_34017, 1.0);
                break;
            }
            vec3 _33952 = vec3(0.0);
            if (debug_view_info.view.x < 40.0)
            {
                vec3 _33953 = vec3(0.0);
                if (debug_view_info.view.x == 20.0)
                {
                    vec3 _9053 = max(_7241.xyz * debug_view_info.view.z, vec3(0.0));
                    _33953 = mix(_9053 * 12.9200000762939453125, (pow(max(_9053, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _9053));
                }
                else
                {
                    vec3 _33954 = vec3(0.0);
                    if (debug_view_info.view.x == 21.0)
                    {
                        float _9092 = (_35252 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                        float _33948 = 0.0;
                        if (debug_view_info.view.w > 1.5)
                        {
                            _33948 = fract(_9092);
                        }
                        else
                        {
                            float _33949 = 0.0;
                            if (debug_view_info.view.w > 0.5)
                            {
                                _33949 = ((_9092 < 0.0) || (_9092 > 1.0)) ? 0.0 : _9092;
                            }
                            else
                            {
                                _33949 = clamp(_9092, 0.0, 1.0);
                            }
                            _33948 = _33949;
                        }
                        _33954 = vec3(_33948 * debug_view_info.view.z);
                    }
                    else
                    {
                        vec3 _33955 = vec3(0.0);
                        if (debug_view_info.view.x == 22.0)
                        {
                            float _9143 = (_7287 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                            float _33944 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _33944 = fract(_9143);
                            }
                            else
                            {
                                float _33945 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _33945 = ((_9143 < 0.0) || (_9143 > 1.0)) ? 0.0 : _9143;
                                }
                                else
                                {
                                    _33945 = clamp(_9143, 0.0, 1.0);
                                }
                                _33944 = _33945;
                            }
                            _33955 = vec3(_33944 * debug_view_info.view.z);
                        }
                        else
                        {
                            vec3 _33956 = vec3(0.0);
                            if (debug_view_info.view.x == 23.0)
                            {
                                float _9194 = (_7294 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _33940 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _33940 = fract(_9194);
                                }
                                else
                                {
                                    float _33941 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _33941 = ((_9194 < 0.0) || (_9194 > 1.0)) ? 0.0 : _9194;
                                    }
                                    else
                                    {
                                        _33941 = clamp(_9194, 0.0, 1.0);
                                    }
                                    _33940 = _33941;
                                }
                                _33956 = vec3(_33940 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _33957 = vec3(0.0);
                                if (debug_view_info.view.x == 24.0)
                                {
                                    float _9245 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _33936 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _33936 = fract(_9245);
                                    }
                                    else
                                    {
                                        float _33937 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _33937 = ((_9245 < 0.0) || (_9245 > 1.0)) ? 0.0 : _9245;
                                        }
                                        else
                                        {
                                            _33937 = clamp(_9245, 0.0, 1.0);
                                        }
                                        _33936 = _33937;
                                    }
                                    _33957 = vec3(_33936 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _33958 = vec3(0.0);
                                    if (debug_view_info.view.x == 25.0)
                                    {
                                        float _9296 = (_7316 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _33932 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _33932 = fract(_9296);
                                        }
                                        else
                                        {
                                            float _33933 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _33933 = ((_9296 < 0.0) || (_9296 > 1.0)) ? 0.0 : _9296;
                                            }
                                            else
                                            {
                                                _33933 = clamp(_9296, 0.0, 1.0);
                                            }
                                            _33932 = _33933;
                                        }
                                        _33958 = vec3(_33932 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _33959 = vec3(0.0);
                                        if (debug_view_info.view.x == 26.0)
                                        {
                                            vec3 _9332 = max(_7340 * debug_view_info.view.z, vec3(0.0));
                                            _33959 = mix(_9332 * 12.9200000762939453125, (pow(max(_9332, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _9332));
                                        }
                                        else
                                        {
                                            vec2 _9353 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _33959 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9353.x + _9353.y, 2.0)));
                                        }
                                        _33958 = _33959;
                                    }
                                    _33957 = _33958;
                                }
                                _33956 = _33957;
                            }
                            _33955 = _33956;
                        }
                        _33954 = _33955;
                    }
                    _33953 = _33954;
                }
                _33952 = _33953;
            }
            else
            {
                vec3 _33960 = vec3(0.0);
                if (debug_view_info.view.x < 60.0)
                {
                    vec2 _9374 = floor(gl_FragCoord.xy * vec2(0.125));
                    _33960 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9374.x + _9374.y, 2.0)));
                }
                else
                {
                    vec3 _33961 = vec3(0.0);
                    if (debug_view_info.view.x < 70.0)
                    {
                        vec3 _33962 = vec3(0.0);
                        if (debug_view_info.view.x == 60.0)
                        {
                            _33962 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _33963 = vec3(0.0);
                            if (debug_view_info.view.x == 61.0)
                            {
                                _33963 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec2 _9462 = floor(gl_FragCoord.xy * vec2(0.125));
                                _33963 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9462.x + _9462.y, 2.0)));
                            }
                            _33962 = _33963;
                        }
                        _33961 = _33962;
                    }
                    else
                    {
                        vec3 _33964 = vec3(0.0);
                        if (debug_view_info.view.x < 80.0)
                        {
                            vec3 _33965 = vec3(0.0);
                            if (debug_view_info.view.x == 70.0)
                            {
                                bool _9479 = v_texture_coords.x < 0.0;
                                bool _9486 = false;
                                if (!_9479)
                                {
                                    _9486 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _9486 = _9479;
                                }
                                bool _9493 = false;
                                if (!_9486)
                                {
                                    _9493 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _9493 = _9486;
                                }
                                bool _9500 = false;
                                if (!_9493)
                                {
                                    _9500 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _9500 = _9493;
                                }
                                bvec3 _9503 = bvec3(_9500);
                                highp vec3 _9504 = vec3(_9503.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _9503.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _9503.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _9529 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                highp vec3 _9530 = vec3(_9529.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _9504.x, _9529.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _9504.y, _9529.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _9504.z);
                                float _9544 = length(v_normal);
                                bvec3 _9551 = bvec3((_9544 < 0.300000011920928955078125) || (_9544 > 1.7000000476837158203125));
                                highp vec3 _9552 = vec3(_9551.x ? vec3(1.0, 0.5, 0.0).x : _9530.x, _9551.y ? vec3(1.0, 0.5, 0.0).y : _9530.y, _9551.z ? vec3(1.0, 0.5, 0.0).z : _9530.z);
                                bool _9557 = _7287 > 0.0500000007450580596923828125;
                                bool _9563 = false;
                                if (_9557)
                                {
                                    _9563 = _7287 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _9563 = _9557;
                                }
                                vec3 _9575 = vec3(0.0);
                                bvec3 _9565 = bvec3(_9563);
                                highp vec3 _9566 = vec3(_9565.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _9552.x, _9565.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _9552.y, _9565.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _9552.z);
                                vec3 _33930 = vec3(0.0);
                                do
                                {
                                    _9575 = _7241.xyz;
                                    float _9576 = dot(_9575, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7287 > 0.5)
                                    {
                                        _33930 = _9566;
                                        break;
                                    }
                                    if (_9576 < 0.0130000002682209014892578125)
                                    {
                                        _33930 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_9576 > 0.87000000476837158203125)
                                    {
                                        _33930 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _33930 = _9566;
                                    break;
                                } while(false);
                                vec3 _33931 = vec3(0.0);
                                do
                                {
                                    vec3 _9621 = ((_9575 + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                    bool _9636 = min(min(_7238, _7239), _7240) < 0.0;
                                    bool _9649 = false;
                                    if (!_9636)
                                    {
                                        _9649 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                    }
                                    else
                                    {
                                        _9649 = _9636;
                                    }
                                    if (any(isnan(_9621)))
                                    {
                                        _33931 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_9621)))
                                    {
                                        _33931 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_9649)
                                    {
                                        _33931 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _33931 = _33930;
                                    break;
                                } while(false);
                                _33965 = _33931;
                            }
                            else
                            {
                                vec3 _33966 = vec3(0.0);
                                if (debug_view_info.view.x == 71.0)
                                {
                                    vec3 _33929 = vec3(0.0);
                                    do
                                    {
                                        vec3 _9689 = ((_7241.xyz + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                        bool _9704 = min(min(_7238, _7239), _7240) < 0.0;
                                        bool _9717 = false;
                                        if (!_9704)
                                        {
                                            _9717 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                        }
                                        else
                                        {
                                            _9717 = _9704;
                                        }
                                        if (any(isnan(_9689)))
                                        {
                                            _33929 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_9689)))
                                        {
                                            _33929 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_9717)
                                        {
                                            _33929 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _33929 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _33966 = _33929;
                                }
                                else
                                {
                                    vec3 _33967 = vec3(0.0);
                                    if (debug_view_info.view.x == 72.0)
                                    {
                                        vec3 _33928 = vec3(0.0);
                                        do
                                        {
                                            float _9739 = dot(_7241.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7287 > 0.5)
                                            {
                                                _33928 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_9739 < 0.0130000002682209014892578125)
                                            {
                                                _33928 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_9739 > 0.87000000476837158203125)
                                            {
                                                _33928 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _33928 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _33967 = _33928;
                                    }
                                    else
                                    {
                                        vec3 _33968 = vec3(0.0);
                                        if (debug_view_info.view.x == 73.0)
                                        {
                                            bool _9761 = _7287 > 0.0500000007450580596923828125;
                                            bool _9767 = false;
                                            if (_9761)
                                            {
                                                _9767 = _7287 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _9767 = _9761;
                                            }
                                            bvec3 _9769 = bvec3(_9767);
                                            _33968 = vec3(_9769.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _9769.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _9769.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _33969 = vec3(0.0);
                                            if (debug_view_info.view.x == 74.0)
                                            {
                                                float _9775 = length(v_normal);
                                                bvec3 _9782 = bvec3((_9775 < 0.300000011920928955078125) || (_9775 > 1.7000000476837158203125));
                                                _33969 = vec3(_9782.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _9782.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _9782.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _33970 = vec3(0.0);
                                                if (debug_view_info.view.x == 75.0)
                                                {
                                                    bvec3 _9805 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                                    _33970 = vec3(_9805.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _9805.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _9805.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _33971 = vec3(0.0);
                                                    if (debug_view_info.view.x == 76.0)
                                                    {
                                                        bool _9823 = v_texture_coords.x < 0.0;
                                                        bool _9830 = false;
                                                        if (!_9823)
                                                        {
                                                            _9830 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _9830 = _9823;
                                                        }
                                                        bool _9837 = false;
                                                        if (!_9830)
                                                        {
                                                            _9837 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _9837 = _9830;
                                                        }
                                                        bool _9844 = false;
                                                        if (!_9837)
                                                        {
                                                            _9844 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _9844 = _9837;
                                                        }
                                                        bvec3 _9847 = bvec3(_9844);
                                                        _33971 = vec3(_9847.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _9847.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _9847.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _9860 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _33971 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9860.x + _9860.y, 2.0)));
                                                    }
                                                    _33970 = _33971;
                                                }
                                                _33969 = _33970;
                                            }
                                            _33968 = _33969;
                                        }
                                        _33967 = _33968;
                                    }
                                    _33966 = _33967;
                                }
                                _33965 = _33966;
                            }
                            _33964 = _33965;
                        }
                        else
                        {
                            vec3 _33972 = vec3(0.0);
                            if (debug_view_info.view.x == 80.0)
                            {
                                _33972 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _9878 = floor(gl_FragCoord.xy * vec2(0.125));
                                _33972 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9878.x + _9878.y, 2.0)));
                            }
                            _33964 = _33972;
                        }
                        _33961 = _33964;
                    }
                    _33960 = _33961;
                }
                _33952 = _33960;
            }
            _34031 = vec4(_33952, 1.0);
            break;
        } while(false);
        vec4 _34759 = vec4(0.0);
        do
        {
            if (debug_view_info.left.x < 20.0)
            {
                vec3 _34745 = vec3(0.0);
                if (debug_view_info.left.x == 1.0)
                {
                    float _10313 = length(_7154);
                    vec3 _34743 = vec3(0.0);
                    if (_10313 > 9.9999999747524270787835121154785e-07)
                    {
                        _34743 = _7154 / vec3(_10313);
                    }
                    else
                    {
                        _34743 = vec3(0.0);
                    }
                    _34745 = ((_34743 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                }
                else
                {
                    vec3 _34746 = vec3(0.0);
                    if (debug_view_info.left.x == 2.0)
                    {
                        float _10336 = length(_30829);
                        vec3 _34741 = vec3(0.0);
                        if (_10336 > 9.9999999747524270787835121154785e-07)
                        {
                            _34741 = _30829 / vec3(_10336);
                        }
                        else
                        {
                            _34741 = vec3(0.0);
                        }
                        _34746 = ((_34741 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                    }
                    else
                    {
                        vec3 _34747 = vec3(0.0);
                        if (debug_view_info.left.x == 3.0)
                        {
                            float _10359 = length(v_tangent.xyz);
                            vec3 _34739 = vec3(0.0);
                            if (_10359 > 9.9999999747524270787835121154785e-07)
                            {
                                _34739 = v_tangent.xyz / vec3(_10359);
                            }
                            else
                            {
                                _34739 = vec3(0.0);
                            }
                            _34747 = ((_34739 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                        }
                        else
                        {
                            vec3 _34748 = vec3(0.0);
                            if (debug_view_info.left.x == 4.0)
                            {
                                highp float _9992 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_9992 = _9992;
                                vec3 _9993 = cross(_7152, v_tangent.xyz) * mp_copy_9992;
                                float _10382 = length(_9993);
                                vec3 _34737 = vec3(0.0);
                                if (_10382 > 9.9999999747524270787835121154785e-07)
                                {
                                    _34737 = _9993 / vec3(_10382);
                                }
                                else
                                {
                                    _34737 = vec3(0.0);
                                }
                                _34748 = ((_34737 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                            }
                            else
                            {
                                vec3 _34749 = vec3(0.0);
                                if (debug_view_info.left.x == 5.0)
                                {
                                    _34749 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _34750 = vec3(0.0);
                                    if (debug_view_info.left.x == 6.0)
                                    {
                                        _34750 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.left.y;
                                    }
                                    else
                                    {
                                        vec3 _34751 = vec3(0.0);
                                        if (debug_view_info.left.x == 7.0)
                                        {
                                            _34751 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.left.y;
                                        }
                                        else
                                        {
                                            vec3 _34752 = vec3(0.0);
                                            if (debug_view_info.left.x == 8.0)
                                            {
                                                vec3 _10417 = max(v_color.xyz * debug_view_info.left.y, vec3(0.0));
                                                _34752 = mix(_10417 * 12.9200000762939453125, (pow(max(_10417, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _10417));
                                            }
                                            else
                                            {
                                                vec3 _34753 = vec3(0.0);
                                                if (debug_view_info.left.x == 9.0)
                                                {
                                                    vec3 mp_copy_34733 = vec3(0.0);
                                                    highp vec3 _34733 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _34733 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _34733 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_34733 = _34733;
                                                    float _10453 = length(mp_copy_34733);
                                                    vec3 _34734 = vec3(0.0);
                                                    if (_10453 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _34734 = mp_copy_34733 / vec3(_10453);
                                                    }
                                                    else
                                                    {
                                                        _34734 = vec3(0.0);
                                                    }
                                                    _34753 = ((_34734 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                                                }
                                                else
                                                {
                                                    vec3 _34754 = vec3(0.0);
                                                    if (debug_view_info.left.x == 10.0)
                                                    {
                                                        float _10496 = max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                                        float _10497 = (v_position.x - debug_view_info.left.z) / _10496;
                                                        bool _10501 = debug_view_info.view.w > 1.5;
                                                        float _34717 = 0.0;
                                                        if (_10501)
                                                        {
                                                            _34717 = fract(_10497);
                                                        }
                                                        else
                                                        {
                                                            float _34718 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34718 = ((_10497 < 0.0) || (_10497 > 1.0)) ? 0.0 : _10497;
                                                            }
                                                            else
                                                            {
                                                                _34718 = clamp(_10497, 0.0, 1.0);
                                                            }
                                                            _34717 = _34718;
                                                        }
                                                        float _10548 = (v_position.y - debug_view_info.left.z) / _10496;
                                                        float _34723 = 0.0;
                                                        if (_10501)
                                                        {
                                                            _34723 = fract(_10548);
                                                        }
                                                        else
                                                        {
                                                            float _34724 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34724 = ((_10548 < 0.0) || (_10548 > 1.0)) ? 0.0 : _10548;
                                                            }
                                                            else
                                                            {
                                                                _34724 = clamp(_10548, 0.0, 1.0);
                                                            }
                                                            _34723 = _34724;
                                                        }
                                                        float _10599 = (v_position.z - debug_view_info.left.z) / _10496;
                                                        float _34729 = 0.0;
                                                        if (_10501)
                                                        {
                                                            _34729 = fract(_10599);
                                                        }
                                                        else
                                                        {
                                                            float _34730 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34730 = ((_10599 < 0.0) || (_10599 > 1.0)) ? 0.0 : _10599;
                                                            }
                                                            else
                                                            {
                                                                _34730 = clamp(_10599, 0.0, 1.0);
                                                            }
                                                            _34729 = _34730;
                                                        }
                                                        _34754 = vec3(_34717 * debug_view_info.left.y, _34723 * debug_view_info.left.y, _34729 * debug_view_info.left.y);
                                                    }
                                                    else
                                                    {
                                                        vec3 _34755 = vec3(0.0);
                                                        if (debug_view_info.left.x == 11.0)
                                                        {
                                                            bvec3 _10068 = bvec3(gl_FrontFacing);
                                                            _34755 = vec3(_10068.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _10068.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _10068.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _34756 = vec3(0.0);
                                                            if (debug_view_info.left.x == 12.0)
                                                            {
                                                                highp vec2 _10626 = v_texture_coords;
                                                                vec2 mp_copy_10626 = _10626;
                                                                vec2 _10638 = floor(mp_copy_10626 * 8.0);
                                                                float _10640 = _10638.x;
                                                                float _10642 = _10638.y;
                                                                float _10650 = _10640 + (_10642 * 8.0);
                                                                vec2 _10659 = step(vec2(0.0), mp_copy_10626) * step(mp_copy_10626, vec2(1.0));
                                                                _34756 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_10640 + _10642, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_10650 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_10650 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_10659.x * _10659.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _34757 = vec3(0.0);
                                                                if (debug_view_info.left.x == 13.0)
                                                                {
                                                                    highp vec2 _10709 = v_texture_coords_1;
                                                                    vec2 mp_copy_10709 = _10709;
                                                                    vec2 _10721 = floor(mp_copy_10709 * 8.0);
                                                                    float _10723 = _10721.x;
                                                                    float _10725 = _10721.y;
                                                                    float _10733 = _10723 + (_10725 * 8.0);
                                                                    vec2 _10742 = step(vec2(0.0), mp_copy_10709) * step(mp_copy_10709, vec2(1.0));
                                                                    _34757 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_10723 + _10725, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_10733 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_10733 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_10742.x * _10742.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _34758 = vec3(0.0);
                                                                    if (debug_view_info.left.x == 14.0)
                                                                    {
                                                                        highp float _10808 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _10814 = debug_view_info.depth.x > 0.5;
                                                                        bool _10820 = false;
                                                                        if (_10814)
                                                                        {
                                                                            _10820 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _10820 = _10814;
                                                                        }
                                                                        highp float _34703 = 0.0;
                                                                        if (_10820)
                                                                        {
                                                                            _34703 = 1.1920928955078125e-07 / _10808;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _34704 = 0.0;
                                                                            if (_10814)
                                                                            {
                                                                                _34704 = 5.9604644775390625e-08 / (_10808 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _34704 = 5.9604644775390625e-08 / (_10808 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _34703 = _34704;
                                                                        }
                                                                        highp float _10849 = dot(_7154, view_info.camera_forward.xyz);
                                                                        highp float _10855 = sqrt(max(1.0 - (_10849 * _10849), 0.0));
                                                                        highp float _34701 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _34701 = (debug_view_info.depth.z * _10855) / max(abs(_10849), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _34701 = (((1.0 / (_10808 * _10808)) * debug_view_info.depth.z) * _10855) / max(abs(dot(_7154, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _10893 = log2(max(max(8.0 * _34703, _34701 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_10893 = _10893;
                                                                        float _10932 = (mp_copy_10893 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                                                        float _34713 = 0.0;
                                                                        if (debug_view_info.view.w > 1.5)
                                                                        {
                                                                            _34713 = fract(_10932);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _34714 = 0.0;
                                                                            if (debug_view_info.view.w > 0.5)
                                                                            {
                                                                                _34714 = ((_10932 < 0.0) || (_10932 > 1.0)) ? 0.0 : _10932;
                                                                            }
                                                                            else
                                                                            {
                                                                                _34714 = clamp(_10932, 0.0, 1.0);
                                                                            }
                                                                            _34713 = _34714;
                                                                        }
                                                                        _34758 = clamp(vec3(1.5) - abs(vec3(4.0 * _34713) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.left.y;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _10965 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _34758 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_10965.x + _10965.y, 2.0)));
                                                                    }
                                                                    _34757 = _34758;
                                                                }
                                                                _34756 = _34757;
                                                            }
                                                            _34755 = _34756;
                                                        }
                                                        _34754 = _34755;
                                                    }
                                                    _34753 = _34754;
                                                }
                                                _34752 = _34753;
                                            }
                                            _34751 = _34752;
                                        }
                                        _34750 = _34751;
                                    }
                                    _34749 = _34750;
                                }
                                _34748 = _34749;
                            }
                            _34747 = _34748;
                        }
                        _34746 = _34747;
                    }
                    _34745 = _34746;
                }
                _34759 = vec4(_34745, 1.0);
                break;
            }
            vec3 _34680 = vec3(0.0);
            if (debug_view_info.left.x < 40.0)
            {
                vec3 _34681 = vec3(0.0);
                if (debug_view_info.left.x == 20.0)
                {
                    vec3 _10986 = max(_7241.xyz * debug_view_info.left.y, vec3(0.0));
                    _34681 = mix(_10986 * 12.9200000762939453125, (pow(max(_10986, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _10986));
                }
                else
                {
                    vec3 _34682 = vec3(0.0);
                    if (debug_view_info.left.x == 21.0)
                    {
                        float _11025 = (_35252 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                        float _34676 = 0.0;
                        if (debug_view_info.view.w > 1.5)
                        {
                            _34676 = fract(_11025);
                        }
                        else
                        {
                            float _34677 = 0.0;
                            if (debug_view_info.view.w > 0.5)
                            {
                                _34677 = ((_11025 < 0.0) || (_11025 > 1.0)) ? 0.0 : _11025;
                            }
                            else
                            {
                                _34677 = clamp(_11025, 0.0, 1.0);
                            }
                            _34676 = _34677;
                        }
                        _34682 = vec3(_34676 * debug_view_info.left.y);
                    }
                    else
                    {
                        vec3 _34683 = vec3(0.0);
                        if (debug_view_info.left.x == 22.0)
                        {
                            float _11076 = (_7287 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                            float _34672 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _34672 = fract(_11076);
                            }
                            else
                            {
                                float _34673 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _34673 = ((_11076 < 0.0) || (_11076 > 1.0)) ? 0.0 : _11076;
                                }
                                else
                                {
                                    _34673 = clamp(_11076, 0.0, 1.0);
                                }
                                _34672 = _34673;
                            }
                            _34683 = vec3(_34672 * debug_view_info.left.y);
                        }
                        else
                        {
                            vec3 _34684 = vec3(0.0);
                            if (debug_view_info.left.x == 23.0)
                            {
                                float _11127 = (_7294 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                float _34668 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _34668 = fract(_11127);
                                }
                                else
                                {
                                    float _34669 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _34669 = ((_11127 < 0.0) || (_11127 > 1.0)) ? 0.0 : _11127;
                                    }
                                    else
                                    {
                                        _34669 = clamp(_11127, 0.0, 1.0);
                                    }
                                    _34668 = _34669;
                                }
                                _34684 = vec3(_34668 * debug_view_info.left.y);
                            }
                            else
                            {
                                vec3 _34685 = vec3(0.0);
                                if (debug_view_info.left.x == 24.0)
                                {
                                    float _11178 = (1.0 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                    float _34664 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _34664 = fract(_11178);
                                    }
                                    else
                                    {
                                        float _34665 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _34665 = ((_11178 < 0.0) || (_11178 > 1.0)) ? 0.0 : _11178;
                                        }
                                        else
                                        {
                                            _34665 = clamp(_11178, 0.0, 1.0);
                                        }
                                        _34664 = _34665;
                                    }
                                    _34685 = vec3(_34664 * debug_view_info.left.y);
                                }
                                else
                                {
                                    vec3 _34686 = vec3(0.0);
                                    if (debug_view_info.left.x == 25.0)
                                    {
                                        float _11229 = (_7316 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                        float _34660 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _34660 = fract(_11229);
                                        }
                                        else
                                        {
                                            float _34661 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _34661 = ((_11229 < 0.0) || (_11229 > 1.0)) ? 0.0 : _11229;
                                            }
                                            else
                                            {
                                                _34661 = clamp(_11229, 0.0, 1.0);
                                            }
                                            _34660 = _34661;
                                        }
                                        _34686 = vec3(_34660 * debug_view_info.left.y);
                                    }
                                    else
                                    {
                                        vec3 _34687 = vec3(0.0);
                                        if (debug_view_info.left.x == 26.0)
                                        {
                                            vec3 _11265 = max(_7340 * debug_view_info.left.y, vec3(0.0));
                                            _34687 = mix(_11265 * 12.9200000762939453125, (pow(max(_11265, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _11265));
                                        }
                                        else
                                        {
                                            vec2 _11286 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _34687 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11286.x + _11286.y, 2.0)));
                                        }
                                        _34686 = _34687;
                                    }
                                    _34685 = _34686;
                                }
                                _34684 = _34685;
                            }
                            _34683 = _34684;
                        }
                        _34682 = _34683;
                    }
                    _34681 = _34682;
                }
                _34680 = _34681;
            }
            else
            {
                vec3 _34688 = vec3(0.0);
                if (debug_view_info.left.x < 60.0)
                {
                    vec2 _11307 = floor(gl_FragCoord.xy * vec2(0.125));
                    _34688 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11307.x + _11307.y, 2.0)));
                }
                else
                {
                    vec3 _34689 = vec3(0.0);
                    if (debug_view_info.left.x < 70.0)
                    {
                        vec3 _34690 = vec3(0.0);
                        if (debug_view_info.left.x == 60.0)
                        {
                            _34690 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.left.y;
                        }
                        else
                        {
                            vec3 _34691 = vec3(0.0);
                            if (debug_view_info.left.x == 61.0)
                            {
                                _34691 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.left.y;
                            }
                            else
                            {
                                vec2 _11395 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34691 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11395.x + _11395.y, 2.0)));
                            }
                            _34690 = _34691;
                        }
                        _34689 = _34690;
                    }
                    else
                    {
                        vec3 _34692 = vec3(0.0);
                        if (debug_view_info.left.x < 80.0)
                        {
                            vec3 _34693 = vec3(0.0);
                            if (debug_view_info.left.x == 70.0)
                            {
                                bool _11412 = v_texture_coords.x < 0.0;
                                bool _11419 = false;
                                if (!_11412)
                                {
                                    _11419 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _11419 = _11412;
                                }
                                bool _11426 = false;
                                if (!_11419)
                                {
                                    _11426 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _11426 = _11419;
                                }
                                bool _11433 = false;
                                if (!_11426)
                                {
                                    _11433 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _11433 = _11426;
                                }
                                bvec3 _11436 = bvec3(_11433);
                                highp vec3 _11437 = vec3(_11436.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _11436.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _11436.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _11462 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                highp vec3 _11463 = vec3(_11462.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _11437.x, _11462.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _11437.y, _11462.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _11437.z);
                                float _11477 = length(v_normal);
                                bvec3 _11484 = bvec3((_11477 < 0.300000011920928955078125) || (_11477 > 1.7000000476837158203125));
                                highp vec3 _11485 = vec3(_11484.x ? vec3(1.0, 0.5, 0.0).x : _11463.x, _11484.y ? vec3(1.0, 0.5, 0.0).y : _11463.y, _11484.z ? vec3(1.0, 0.5, 0.0).z : _11463.z);
                                bool _11490 = _7287 > 0.0500000007450580596923828125;
                                bool _11496 = false;
                                if (_11490)
                                {
                                    _11496 = _7287 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _11496 = _11490;
                                }
                                vec3 _11508 = vec3(0.0);
                                bvec3 _11498 = bvec3(_11496);
                                highp vec3 _11499 = vec3(_11498.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _11485.x, _11498.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _11485.y, _11498.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _11485.z);
                                vec3 _34658 = vec3(0.0);
                                do
                                {
                                    _11508 = _7241.xyz;
                                    float _11509 = dot(_11508, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7287 > 0.5)
                                    {
                                        _34658 = _11499;
                                        break;
                                    }
                                    if (_11509 < 0.0130000002682209014892578125)
                                    {
                                        _34658 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_11509 > 0.87000000476837158203125)
                                    {
                                        _34658 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _34658 = _11499;
                                    break;
                                } while(false);
                                vec3 _34659 = vec3(0.0);
                                do
                                {
                                    vec3 _11554 = ((_11508 + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                    bool _11569 = min(min(_7238, _7239), _7240) < 0.0;
                                    bool _11582 = false;
                                    if (!_11569)
                                    {
                                        _11582 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                    }
                                    else
                                    {
                                        _11582 = _11569;
                                    }
                                    if (any(isnan(_11554)))
                                    {
                                        _34659 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_11554)))
                                    {
                                        _34659 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_11582)
                                    {
                                        _34659 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _34659 = _34658;
                                    break;
                                } while(false);
                                _34693 = _34659;
                            }
                            else
                            {
                                vec3 _34694 = vec3(0.0);
                                if (debug_view_info.left.x == 71.0)
                                {
                                    vec3 _34657 = vec3(0.0);
                                    do
                                    {
                                        vec3 _11622 = ((_7241.xyz + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                        bool _11637 = min(min(_7238, _7239), _7240) < 0.0;
                                        bool _11650 = false;
                                        if (!_11637)
                                        {
                                            _11650 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                        }
                                        else
                                        {
                                            _11650 = _11637;
                                        }
                                        if (any(isnan(_11622)))
                                        {
                                            _34657 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_11622)))
                                        {
                                            _34657 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_11650)
                                        {
                                            _34657 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _34657 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _34694 = _34657;
                                }
                                else
                                {
                                    vec3 _34695 = vec3(0.0);
                                    if (debug_view_info.left.x == 72.0)
                                    {
                                        vec3 _34656 = vec3(0.0);
                                        do
                                        {
                                            float _11672 = dot(_7241.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7287 > 0.5)
                                            {
                                                _34656 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_11672 < 0.0130000002682209014892578125)
                                            {
                                                _34656 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_11672 > 0.87000000476837158203125)
                                            {
                                                _34656 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _34656 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _34695 = _34656;
                                    }
                                    else
                                    {
                                        vec3 _34696 = vec3(0.0);
                                        if (debug_view_info.left.x == 73.0)
                                        {
                                            bool _11694 = _7287 > 0.0500000007450580596923828125;
                                            bool _11700 = false;
                                            if (_11694)
                                            {
                                                _11700 = _7287 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _11700 = _11694;
                                            }
                                            bvec3 _11702 = bvec3(_11700);
                                            _34696 = vec3(_11702.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _11702.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _11702.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _34697 = vec3(0.0);
                                            if (debug_view_info.left.x == 74.0)
                                            {
                                                float _11708 = length(v_normal);
                                                bvec3 _11715 = bvec3((_11708 < 0.300000011920928955078125) || (_11708 > 1.7000000476837158203125));
                                                _34697 = vec3(_11715.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _11715.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _11715.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _34698 = vec3(0.0);
                                                if (debug_view_info.left.x == 75.0)
                                                {
                                                    bvec3 _11738 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                                    _34698 = vec3(_11738.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _11738.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _11738.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _34699 = vec3(0.0);
                                                    if (debug_view_info.left.x == 76.0)
                                                    {
                                                        bool _11756 = v_texture_coords.x < 0.0;
                                                        bool _11763 = false;
                                                        if (!_11756)
                                                        {
                                                            _11763 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _11763 = _11756;
                                                        }
                                                        bool _11770 = false;
                                                        if (!_11763)
                                                        {
                                                            _11770 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _11770 = _11763;
                                                        }
                                                        bool _11777 = false;
                                                        if (!_11770)
                                                        {
                                                            _11777 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _11777 = _11770;
                                                        }
                                                        bvec3 _11780 = bvec3(_11777);
                                                        _34699 = vec3(_11780.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _11780.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _11780.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _11793 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _34699 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11793.x + _11793.y, 2.0)));
                                                    }
                                                    _34698 = _34699;
                                                }
                                                _34697 = _34698;
                                            }
                                            _34696 = _34697;
                                        }
                                        _34695 = _34696;
                                    }
                                    _34694 = _34695;
                                }
                                _34693 = _34694;
                            }
                            _34692 = _34693;
                        }
                        else
                        {
                            vec3 _34700 = vec3(0.0);
                            if (debug_view_info.left.x == 80.0)
                            {
                                _34700 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _11811 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34700 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11811.x + _11811.y, 2.0)));
                            }
                            _34692 = _34700;
                        }
                        _34689 = _34692;
                    }
                    _34688 = _34689;
                }
                _34680 = _34688;
            }
            _34759 = vec4(_34680, 1.0);
            break;
        } while(false);
        bvec4 _11830 = bvec4(gl_FragCoord.x >= debug_view_info.view.y);
        frag_color = vec4(_11830.x ? _34031.x : _34759.x, _11830.y ? _34031.y : _34759.y, _11830.z ? _34031.z : _34759.z, _11830.w ? _34031.w : _34759.w);
    }
    else
    {
        if ((_30865 > 0.5) && (_30865 < 1.5))
        {
            vec4 _33927 = vec4(0.0);
            do
            {
                if (debug_view_info.view.x < 20.0)
                {
                    vec3 _33913 = vec3(0.0);
                    if (debug_view_info.view.x == 1.0)
                    {
                        float _12250 = length(_7154);
                        vec3 _33911 = vec3(0.0);
                        if (_12250 > 9.9999999747524270787835121154785e-07)
                        {
                            _33911 = _7154 / vec3(_12250);
                        }
                        else
                        {
                            _33911 = vec3(0.0);
                        }
                        _33913 = ((_33911 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                    }
                    else
                    {
                        vec3 _33914 = vec3(0.0);
                        if (debug_view_info.view.x == 2.0)
                        {
                            float _12273 = length(_30829);
                            vec3 _33909 = vec3(0.0);
                            if (_12273 > 9.9999999747524270787835121154785e-07)
                            {
                                _33909 = _30829 / vec3(_12273);
                            }
                            else
                            {
                                _33909 = vec3(0.0);
                            }
                            _33914 = ((_33909 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _33915 = vec3(0.0);
                            if (debug_view_info.view.x == 3.0)
                            {
                                float _12296 = length(v_tangent.xyz);
                                vec3 _33907 = vec3(0.0);
                                if (_12296 > 9.9999999747524270787835121154785e-07)
                                {
                                    _33907 = v_tangent.xyz / vec3(_12296);
                                }
                                else
                                {
                                    _33907 = vec3(0.0);
                                }
                                _33915 = ((_33907 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _33916 = vec3(0.0);
                                if (debug_view_info.view.x == 4.0)
                                {
                                    highp float _11929 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                    float mp_copy_11929 = _11929;
                                    vec3 _11930 = cross(_7152, v_tangent.xyz) * mp_copy_11929;
                                    float _12319 = length(_11930);
                                    vec3 _33905 = vec3(0.0);
                                    if (_12319 > 9.9999999747524270787835121154785e-07)
                                    {
                                        _33905 = _11930 / vec3(_12319);
                                    }
                                    else
                                    {
                                        _33905 = vec3(0.0);
                                    }
                                    _33916 = ((_33905 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _33917 = vec3(0.0);
                                    if (debug_view_info.view.x == 5.0)
                                    {
                                        _33917 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                    }
                                    else
                                    {
                                        vec3 _33918 = vec3(0.0);
                                        if (debug_view_info.view.x == 6.0)
                                        {
                                            _33918 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                        }
                                        else
                                        {
                                            vec3 _33919 = vec3(0.0);
                                            if (debug_view_info.view.x == 7.0)
                                            {
                                                _33919 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                            }
                                            else
                                            {
                                                vec3 _33920 = vec3(0.0);
                                                if (debug_view_info.view.x == 8.0)
                                                {
                                                    vec3 _12354 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                    _33920 = mix(_12354 * 12.9200000762939453125, (pow(max(_12354, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _12354));
                                                }
                                                else
                                                {
                                                    vec3 _33921 = vec3(0.0);
                                                    if (debug_view_info.view.x == 9.0)
                                                    {
                                                        vec3 mp_copy_33901 = vec3(0.0);
                                                        highp vec3 _33901 = vec3(0.0);
                                                        if (view_info.camera_forward.w > 0.5)
                                                        {
                                                            _33901 = -view_info.camera_forward.xyz;
                                                        }
                                                        else
                                                        {
                                                            _33901 = normalize(v_viewvector);
                                                        }
                                                        mp_copy_33901 = _33901;
                                                        float _12390 = length(mp_copy_33901);
                                                        vec3 _33902 = vec3(0.0);
                                                        if (_12390 > 9.9999999747524270787835121154785e-07)
                                                        {
                                                            _33902 = mp_copy_33901 / vec3(_12390);
                                                        }
                                                        else
                                                        {
                                                            _33902 = vec3(0.0);
                                                        }
                                                        _33921 = ((_33902 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                    }
                                                    else
                                                    {
                                                        vec3 _33922 = vec3(0.0);
                                                        if (debug_view_info.view.x == 10.0)
                                                        {
                                                            float _12433 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                            float _12434 = (v_position.x - debug_view_info.params.x) / _12433;
                                                            bool _12438 = debug_view_info.view.w > 1.5;
                                                            float _33885 = 0.0;
                                                            if (_12438)
                                                            {
                                                                _33885 = fract(_12434);
                                                            }
                                                            else
                                                            {
                                                                float _33886 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _33886 = ((_12434 < 0.0) || (_12434 > 1.0)) ? 0.0 : _12434;
                                                                }
                                                                else
                                                                {
                                                                    _33886 = clamp(_12434, 0.0, 1.0);
                                                                }
                                                                _33885 = _33886;
                                                            }
                                                            float _12485 = (v_position.y - debug_view_info.params.x) / _12433;
                                                            float _33891 = 0.0;
                                                            if (_12438)
                                                            {
                                                                _33891 = fract(_12485);
                                                            }
                                                            else
                                                            {
                                                                float _33892 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _33892 = ((_12485 < 0.0) || (_12485 > 1.0)) ? 0.0 : _12485;
                                                                }
                                                                else
                                                                {
                                                                    _33892 = clamp(_12485, 0.0, 1.0);
                                                                }
                                                                _33891 = _33892;
                                                            }
                                                            float _12536 = (v_position.z - debug_view_info.params.x) / _12433;
                                                            float _33897 = 0.0;
                                                            if (_12438)
                                                            {
                                                                _33897 = fract(_12536);
                                                            }
                                                            else
                                                            {
                                                                float _33898 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _33898 = ((_12536 < 0.0) || (_12536 > 1.0)) ? 0.0 : _12536;
                                                                }
                                                                else
                                                                {
                                                                    _33898 = clamp(_12536, 0.0, 1.0);
                                                                }
                                                                _33897 = _33898;
                                                            }
                                                            _33922 = vec3(_33885 * debug_view_info.view.z, _33891 * debug_view_info.view.z, _33897 * debug_view_info.view.z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _33923 = vec3(0.0);
                                                            if (debug_view_info.view.x == 11.0)
                                                            {
                                                                bvec3 _12005 = bvec3(gl_FrontFacing);
                                                                _33923 = vec3(_12005.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _12005.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _12005.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                            }
                                                            else
                                                            {
                                                                vec3 _33924 = vec3(0.0);
                                                                if (debug_view_info.view.x == 12.0)
                                                                {
                                                                    highp vec2 _12563 = v_texture_coords;
                                                                    vec2 mp_copy_12563 = _12563;
                                                                    vec2 _12575 = floor(mp_copy_12563 * 8.0);
                                                                    float _12577 = _12575.x;
                                                                    float _12579 = _12575.y;
                                                                    float _12587 = _12577 + (_12579 * 8.0);
                                                                    vec2 _12596 = step(vec2(0.0), mp_copy_12563) * step(mp_copy_12563, vec2(1.0));
                                                                    _33924 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_12577 + _12579, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_12587 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_12587 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_12596.x * _12596.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _33925 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 13.0)
                                                                    {
                                                                        highp vec2 _12646 = v_texture_coords_1;
                                                                        vec2 mp_copy_12646 = _12646;
                                                                        vec2 _12658 = floor(mp_copy_12646 * 8.0);
                                                                        float _12660 = _12658.x;
                                                                        float _12662 = _12658.y;
                                                                        float _12670 = _12660 + (_12662 * 8.0);
                                                                        vec2 _12679 = step(vec2(0.0), mp_copy_12646) * step(mp_copy_12646, vec2(1.0));
                                                                        _33925 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_12660 + _12662, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_12670 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_12670 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_12679.x * _12679.y));
                                                                    }
                                                                    else
                                                                    {
                                                                        vec3 _33926 = vec3(0.0);
                                                                        if (debug_view_info.view.x == 14.0)
                                                                        {
                                                                            highp float _12745 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                            bool _12751 = debug_view_info.depth.x > 0.5;
                                                                            bool _12757 = false;
                                                                            if (_12751)
                                                                            {
                                                                                _12757 = debug_view_info.depth.y > 0.5;
                                                                            }
                                                                            else
                                                                            {
                                                                                _12757 = _12751;
                                                                            }
                                                                            highp float _33871 = 0.0;
                                                                            if (_12757)
                                                                            {
                                                                                _33871 = 1.1920928955078125e-07 / _12745;
                                                                            }
                                                                            else
                                                                            {
                                                                                highp float _33872 = 0.0;
                                                                                if (_12751)
                                                                                {
                                                                                    _33872 = 5.9604644775390625e-08 / (_12745 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                }
                                                                                else
                                                                                {
                                                                                    _33872 = 5.9604644775390625e-08 / (_12745 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                }
                                                                                _33871 = _33872;
                                                                            }
                                                                            highp float _12786 = dot(_7154, view_info.camera_forward.xyz);
                                                                            highp float _12792 = sqrt(max(1.0 - (_12786 * _12786), 0.0));
                                                                            highp float _33869 = 0.0;
                                                                            if (view_info.camera_forward.w > 0.5)
                                                                            {
                                                                                _33869 = (debug_view_info.depth.z * _12792) / max(abs(_12786), 9.9999999747524270787835121154785e-07);
                                                                            }
                                                                            else
                                                                            {
                                                                                _33869 = (((1.0 / (_12745 * _12745)) * debug_view_info.depth.z) * _12792) / max(abs(dot(_7154, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                            }
                                                                            highp float _12830 = log2(max(max(8.0 * _33871, _33869 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                            float mp_copy_12830 = _12830;
                                                                            float _12869 = (mp_copy_12830 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                            float _33881 = 0.0;
                                                                            if (debug_view_info.view.w > 1.5)
                                                                            {
                                                                                _33881 = fract(_12869);
                                                                            }
                                                                            else
                                                                            {
                                                                                float _33882 = 0.0;
                                                                                if (debug_view_info.view.w > 0.5)
                                                                                {
                                                                                    _33882 = ((_12869 < 0.0) || (_12869 > 1.0)) ? 0.0 : _12869;
                                                                                }
                                                                                else
                                                                                {
                                                                                    _33882 = clamp(_12869, 0.0, 1.0);
                                                                                }
                                                                                _33881 = _33882;
                                                                            }
                                                                            _33926 = clamp(vec3(1.5) - abs(vec3(4.0 * _33881) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                        }
                                                                        else
                                                                        {
                                                                            vec2 _12902 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                            _33926 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_12902.x + _12902.y, 2.0)));
                                                                        }
                                                                        _33925 = _33926;
                                                                    }
                                                                    _33924 = _33925;
                                                                }
                                                                _33923 = _33924;
                                                            }
                                                            _33922 = _33923;
                                                        }
                                                        _33921 = _33922;
                                                    }
                                                    _33920 = _33921;
                                                }
                                                _33919 = _33920;
                                            }
                                            _33918 = _33919;
                                        }
                                        _33917 = _33918;
                                    }
                                    _33916 = _33917;
                                }
                                _33915 = _33916;
                            }
                            _33914 = _33915;
                        }
                        _33913 = _33914;
                    }
                    _33927 = vec4(_33913, 1.0);
                    break;
                }
                vec3 _33848 = vec3(0.0);
                if (debug_view_info.view.x < 40.0)
                {
                    vec3 _33849 = vec3(0.0);
                    if (debug_view_info.view.x == 20.0)
                    {
                        vec3 _12923 = max(_7241.xyz * debug_view_info.view.z, vec3(0.0));
                        _33849 = mix(_12923 * 12.9200000762939453125, (pow(max(_12923, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _12923));
                    }
                    else
                    {
                        vec3 _33850 = vec3(0.0);
                        if (debug_view_info.view.x == 21.0)
                        {
                            float _12962 = (_35252 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                            float _33844 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _33844 = fract(_12962);
                            }
                            else
                            {
                                float _33845 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _33845 = ((_12962 < 0.0) || (_12962 > 1.0)) ? 0.0 : _12962;
                                }
                                else
                                {
                                    _33845 = clamp(_12962, 0.0, 1.0);
                                }
                                _33844 = _33845;
                            }
                            _33850 = vec3(_33844 * debug_view_info.view.z);
                        }
                        else
                        {
                            vec3 _33851 = vec3(0.0);
                            if (debug_view_info.view.x == 22.0)
                            {
                                float _13013 = (_7287 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _33840 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _33840 = fract(_13013);
                                }
                                else
                                {
                                    float _33841 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _33841 = ((_13013 < 0.0) || (_13013 > 1.0)) ? 0.0 : _13013;
                                    }
                                    else
                                    {
                                        _33841 = clamp(_13013, 0.0, 1.0);
                                    }
                                    _33840 = _33841;
                                }
                                _33851 = vec3(_33840 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _33852 = vec3(0.0);
                                if (debug_view_info.view.x == 23.0)
                                {
                                    float _13064 = (_7294 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _33836 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _33836 = fract(_13064);
                                    }
                                    else
                                    {
                                        float _33837 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _33837 = ((_13064 < 0.0) || (_13064 > 1.0)) ? 0.0 : _13064;
                                        }
                                        else
                                        {
                                            _33837 = clamp(_13064, 0.0, 1.0);
                                        }
                                        _33836 = _33837;
                                    }
                                    _33852 = vec3(_33836 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _33853 = vec3(0.0);
                                    if (debug_view_info.view.x == 24.0)
                                    {
                                        float _13115 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _33832 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _33832 = fract(_13115);
                                        }
                                        else
                                        {
                                            float _33833 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _33833 = ((_13115 < 0.0) || (_13115 > 1.0)) ? 0.0 : _13115;
                                            }
                                            else
                                            {
                                                _33833 = clamp(_13115, 0.0, 1.0);
                                            }
                                            _33832 = _33833;
                                        }
                                        _33853 = vec3(_33832 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _33854 = vec3(0.0);
                                        if (debug_view_info.view.x == 25.0)
                                        {
                                            float _13166 = (_7316 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                            float _33828 = 0.0;
                                            if (debug_view_info.view.w > 1.5)
                                            {
                                                _33828 = fract(_13166);
                                            }
                                            else
                                            {
                                                float _33829 = 0.0;
                                                if (debug_view_info.view.w > 0.5)
                                                {
                                                    _33829 = ((_13166 < 0.0) || (_13166 > 1.0)) ? 0.0 : _13166;
                                                }
                                                else
                                                {
                                                    _33829 = clamp(_13166, 0.0, 1.0);
                                                }
                                                _33828 = _33829;
                                            }
                                            _33854 = vec3(_33828 * debug_view_info.view.z);
                                        }
                                        else
                                        {
                                            vec3 _33855 = vec3(0.0);
                                            if (debug_view_info.view.x == 26.0)
                                            {
                                                vec3 _13202 = max(_7340 * debug_view_info.view.z, vec3(0.0));
                                                _33855 = mix(_13202 * 12.9200000762939453125, (pow(max(_13202, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _13202));
                                            }
                                            else
                                            {
                                                vec2 _13223 = floor(gl_FragCoord.xy * vec2(0.125));
                                                _33855 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13223.x + _13223.y, 2.0)));
                                            }
                                            _33854 = _33855;
                                        }
                                        _33853 = _33854;
                                    }
                                    _33852 = _33853;
                                }
                                _33851 = _33852;
                            }
                            _33850 = _33851;
                        }
                        _33849 = _33850;
                    }
                    _33848 = _33849;
                }
                else
                {
                    vec3 _33856 = vec3(0.0);
                    if (debug_view_info.view.x < 60.0)
                    {
                        vec2 _13244 = floor(gl_FragCoord.xy * vec2(0.125));
                        _33856 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13244.x + _13244.y, 2.0)));
                    }
                    else
                    {
                        vec3 _33857 = vec3(0.0);
                        if (debug_view_info.view.x < 70.0)
                        {
                            vec3 _33858 = vec3(0.0);
                            if (debug_view_info.view.x == 60.0)
                            {
                                _33858 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _33859 = vec3(0.0);
                                if (debug_view_info.view.x == 61.0)
                                {
                                    _33859 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec2 _13332 = floor(gl_FragCoord.xy * vec2(0.125));
                                    _33859 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13332.x + _13332.y, 2.0)));
                                }
                                _33858 = _33859;
                            }
                            _33857 = _33858;
                        }
                        else
                        {
                            vec3 _33860 = vec3(0.0);
                            if (debug_view_info.view.x < 80.0)
                            {
                                vec3 _33861 = vec3(0.0);
                                if (debug_view_info.view.x == 70.0)
                                {
                                    bool _13349 = v_texture_coords.x < 0.0;
                                    bool _13356 = false;
                                    if (!_13349)
                                    {
                                        _13356 = v_texture_coords.x > 1.0;
                                    }
                                    else
                                    {
                                        _13356 = _13349;
                                    }
                                    bool _13363 = false;
                                    if (!_13356)
                                    {
                                        _13363 = v_texture_coords.y < 0.0;
                                    }
                                    else
                                    {
                                        _13363 = _13356;
                                    }
                                    bool _13370 = false;
                                    if (!_13363)
                                    {
                                        _13370 = v_texture_coords.y > 1.0;
                                    }
                                    else
                                    {
                                        _13370 = _13363;
                                    }
                                    bvec3 _13373 = bvec3(_13370);
                                    highp vec3 _13374 = vec3(_13373.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _13373.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _13373.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                    bvec3 _13399 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                    highp vec3 _13400 = vec3(_13399.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _13374.x, _13399.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _13374.y, _13399.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _13374.z);
                                    float _13414 = length(v_normal);
                                    bvec3 _13421 = bvec3((_13414 < 0.300000011920928955078125) || (_13414 > 1.7000000476837158203125));
                                    highp vec3 _13422 = vec3(_13421.x ? vec3(1.0, 0.5, 0.0).x : _13400.x, _13421.y ? vec3(1.0, 0.5, 0.0).y : _13400.y, _13421.z ? vec3(1.0, 0.5, 0.0).z : _13400.z);
                                    bool _13427 = _7287 > 0.0500000007450580596923828125;
                                    bool _13433 = false;
                                    if (_13427)
                                    {
                                        _13433 = _7287 < 0.949999988079071044921875;
                                    }
                                    else
                                    {
                                        _13433 = _13427;
                                    }
                                    vec3 _13445 = vec3(0.0);
                                    bvec3 _13435 = bvec3(_13433);
                                    highp vec3 _13436 = vec3(_13435.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _13422.x, _13435.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _13422.y, _13435.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _13422.z);
                                    vec3 _33826 = vec3(0.0);
                                    do
                                    {
                                        _13445 = _7241.xyz;
                                        float _13446 = dot(_13445, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                        if (_7287 > 0.5)
                                        {
                                            _33826 = _13436;
                                            break;
                                        }
                                        if (_13446 < 0.0130000002682209014892578125)
                                        {
                                            _33826 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                            break;
                                        }
                                        if (_13446 > 0.87000000476837158203125)
                                        {
                                            _33826 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                            break;
                                        }
                                        _33826 = _13436;
                                        break;
                                    } while(false);
                                    vec3 _33827 = vec3(0.0);
                                    do
                                    {
                                        vec3 _13491 = ((_13445 + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                        bool _13506 = min(min(_7238, _7239), _7240) < 0.0;
                                        bool _13519 = false;
                                        if (!_13506)
                                        {
                                            _13519 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                        }
                                        else
                                        {
                                            _13519 = _13506;
                                        }
                                        if (any(isnan(_13491)))
                                        {
                                            _33827 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_13491)))
                                        {
                                            _33827 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_13519)
                                        {
                                            _33827 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _33827 = _33826;
                                        break;
                                    } while(false);
                                    _33861 = _33827;
                                }
                                else
                                {
                                    vec3 _33862 = vec3(0.0);
                                    if (debug_view_info.view.x == 71.0)
                                    {
                                        vec3 _33825 = vec3(0.0);
                                        do
                                        {
                                            vec3 _13559 = ((_7241.xyz + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                            bool _13574 = min(min(_7238, _7239), _7240) < 0.0;
                                            bool _13587 = false;
                                            if (!_13574)
                                            {
                                                _13587 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                            }
                                            else
                                            {
                                                _13587 = _13574;
                                            }
                                            if (any(isnan(_13559)))
                                            {
                                                _33825 = vec3(1.0, 0.0, 0.0);
                                                break;
                                            }
                                            if (any(isinf(_13559)))
                                            {
                                                _33825 = vec3(0.0, 1.0, 0.0);
                                                break;
                                            }
                                            if (_13587)
                                            {
                                                _33825 = vec3(0.0, 0.25, 1.0);
                                                break;
                                            }
                                            _33825 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _33862 = _33825;
                                    }
                                    else
                                    {
                                        vec3 _33863 = vec3(0.0);
                                        if (debug_view_info.view.x == 72.0)
                                        {
                                            vec3 _33824 = vec3(0.0);
                                            do
                                            {
                                                float _13609 = dot(_7241.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                                if (_7287 > 0.5)
                                                {
                                                    _33824 = vec3(0.3499999940395355224609375);
                                                    break;
                                                }
                                                if (_13609 < 0.0130000002682209014892578125)
                                                {
                                                    _33824 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                    break;
                                                }
                                                if (_13609 > 0.87000000476837158203125)
                                                {
                                                    _33824 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                    break;
                                                }
                                                _33824 = vec3(0.3499999940395355224609375);
                                                break;
                                            } while(false);
                                            _33863 = _33824;
                                        }
                                        else
                                        {
                                            vec3 _33864 = vec3(0.0);
                                            if (debug_view_info.view.x == 73.0)
                                            {
                                                bool _13631 = _7287 > 0.0500000007450580596923828125;
                                                bool _13637 = false;
                                                if (_13631)
                                                {
                                                    _13637 = _7287 < 0.949999988079071044921875;
                                                }
                                                else
                                                {
                                                    _13637 = _13631;
                                                }
                                                bvec3 _13639 = bvec3(_13637);
                                                _33864 = vec3(_13639.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _13639.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _13639.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _33865 = vec3(0.0);
                                                if (debug_view_info.view.x == 74.0)
                                                {
                                                    float _13645 = length(v_normal);
                                                    bvec3 _13652 = bvec3((_13645 < 0.300000011920928955078125) || (_13645 > 1.7000000476837158203125));
                                                    _33865 = vec3(_13652.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _13652.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _13652.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _33866 = vec3(0.0);
                                                    if (debug_view_info.view.x == 75.0)
                                                    {
                                                        bvec3 _13675 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                                        _33866 = vec3(_13675.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _13675.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _13675.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _33867 = vec3(0.0);
                                                        if (debug_view_info.view.x == 76.0)
                                                        {
                                                            bool _13693 = v_texture_coords.x < 0.0;
                                                            bool _13700 = false;
                                                            if (!_13693)
                                                            {
                                                                _13700 = v_texture_coords.x > 1.0;
                                                            }
                                                            else
                                                            {
                                                                _13700 = _13693;
                                                            }
                                                            bool _13707 = false;
                                                            if (!_13700)
                                                            {
                                                                _13707 = v_texture_coords.y < 0.0;
                                                            }
                                                            else
                                                            {
                                                                _13707 = _13700;
                                                            }
                                                            bool _13714 = false;
                                                            if (!_13707)
                                                            {
                                                                _13714 = v_texture_coords.y > 1.0;
                                                            }
                                                            else
                                                            {
                                                                _13714 = _13707;
                                                            }
                                                            bvec3 _13717 = bvec3(_13714);
                                                            _33867 = vec3(_13717.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _13717.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _13717.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                        }
                                                        else
                                                        {
                                                            vec2 _13730 = floor(gl_FragCoord.xy * vec2(0.125));
                                                            _33867 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13730.x + _13730.y, 2.0)));
                                                        }
                                                        _33866 = _33867;
                                                    }
                                                    _33865 = _33866;
                                                }
                                                _33864 = _33865;
                                            }
                                            _33863 = _33864;
                                        }
                                        _33862 = _33863;
                                    }
                                    _33861 = _33862;
                                }
                                _33860 = _33861;
                            }
                            else
                            {
                                vec3 _33868 = vec3(0.0);
                                if (debug_view_info.view.x == 80.0)
                                {
                                    _33868 = vec3(0.0);
                                }
                                else
                                {
                                    vec2 _13748 = floor(gl_FragCoord.xy * vec2(0.125));
                                    _33868 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13748.x + _13748.y, 2.0)));
                                }
                                _33860 = _33868;
                            }
                            _33857 = _33860;
                        }
                        _33856 = _33857;
                    }
                    _33848 = _33856;
                }
                _33927 = vec4(_33848, 1.0);
                break;
            } while(false);
            frag_color = _33927;
        }
        else
        {
            highp float hp_copy_30874 = 0.0;
            vec3 _13970 = _7241.xyz;
            float _30874 = 0.0;
            do
            {
                if (frag_info.specular_aa_variance <= 0.0)
                {
                    _30874 = _7294;
                    break;
                }
                vec3 _14788 = dFdx(_30829);
                vec3 _14790 = dFdy(_30829);
                _30874 = sqrt(clamp((_7294 * _7294) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_14788, _14788), dot(_14790, _14790))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
                break;
            } while(false);
            hp_copy_30874 = _30874;
            float _30884 = 0.0;
            vec3 _30889 = vec3(0.0);
            float _31162 = 0.0;
            vec4 _31538 = vec4(0.0);
            vec3 _31689 = vec3(0.0);
            if (frag_info.ssao_params.x > 0.5)
            {
                vec4 _13997 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
                float _30875 = 0.0;
                if (frag_info.camera_up.w > 0.5)
                {
                    _30875 = _13997.w;
                }
                else
                {
                    _30875 = _13997.x;
                }
                float _14010 = min(_7316, _30875);
                bool _14013 = frag_info.ssao_lighting.z > 0.5;
                bool _14019 = false;
                if (_14013)
                {
                    _14019 = frag_info.camera_up.w < 0.5;
                }
                else
                {
                    _14019 = _14013;
                }
                vec3 _30890 = vec3(0.0);
                if (_14019)
                {
                    vec2 _14823 = (_13997.zw * 2.0) - vec2(1.0);
                    float _14825 = _14823.x;
                    float _14827 = _14823.y;
                    float _14835 = (1.0 - abs(_14825)) - abs(_14827);
                    vec3 _14836 = vec3(_14825, _14827, _14835);
                    vec3 _30878 = vec3(0.0);
                    if (_14835 < 0.0)
                    {
                        vec2 _14849 = (vec2(1.0) - abs(_14836.yx)) * vec2((_14825 >= 0.0) ? 1.0 : (-1.0), (_14827 >= 0.0) ? 1.0 : (-1.0));
                        vec3 _30071 = _14836;
                        _30071.x = _14849.x;
                        _30071.y = _14849.y;
                        _30878 = _30071;
                    }
                    else
                    {
                        _30878 = _14836;
                    }
                    vec3 _14857 = -normalize(_30878);
                    _30890 = normalize(((frag_info.camera_right.xyz * _14857.x) + (frag_info.camera_up.xyz * _14857.y)) + (frag_info.camera_forward.xyz * _14857.z));
                }
                else
                {
                    _30890 = vec3(0.0);
                }
                vec3 _14047 = vec3(_14010);
                _31689 = mix(_14047, max(_14047, ((((((_13970 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _14010) + ((_13970 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _14010) + ((_13970 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _14010), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
                _31538 = _13997;
                _31162 = _14010;
                _30889 = _30890;
                _30884 = float(_14019);
            }
            else
            {
                _31689 = vec3(_7316);
                _31538 = vec4(1.0);
                _31162 = _7316;
                _30889 = vec3(0.0);
                _30884 = 0.0;
            }
            vec3 mp_copy_30882 = vec3(0.0);
            bool _14906 = view_info.camera_forward.w > 0.5;
            highp vec3 _30882 = vec3(0.0);
            if (_14906)
            {
                _30882 = -view_info.camera_forward.xyz;
            }
            else
            {
                _30882 = normalize(v_viewvector);
            }
            mp_copy_30882 = _30882;
            vec3 _14065 = mix(frag_info.dielectric_f0.xyz, _13970, vec3(_7287));
            float _14068 = dot(_30829, _30882);
            float _14069 = max(_14068, 0.0);
            float _14073 = max(dot(_7154, _30882), 0.0);
            vec3 _14077 = reflect(-mp_copy_30882, _30829);
            mat3 _14090 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
            bool _14093 = _30884 > 0.5;
            bvec3 _14096 = bvec3(_14093);
            highp vec3 _14097 = vec3(_14096.x ? _30889.x : _30829.x, _14096.y ? _30889.y : _30829.y, _14096.z ? _30889.z : _30829.z);
            vec3 mp_copy_14097 = _14097;
            vec3 _14098 = _14090 * mp_copy_14097;
            vec3 _30893 = vec3(0.0);
            if (frag_info.probe_box.w > 0.5)
            {
                vec3 _14973 = _14077 + (((step(vec3(0.0), _14077) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
                highp vec3 hp_copy_14973 = _14973;
                highp vec3 _14975 = vec3(1.0) / hp_copy_14973;
                highp vec3 _14992 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _14975, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _14975);
                _30893 = normalize((v_position + (_14077 * max(min(min(_14992.x, _14992.y), _14992.z), 0.0))) - frag_info.probe_box.xyz);
            }
            else
            {
                _30893 = _14077;
            }
            bool _15220 = false;
            vec3 _14103 = _14090 * _30893;
            float _15039 = _14098.y;
            float _15040 = 0.48860299587249755859375 * _15039;
            float _15046 = _14098.z;
            float _15047 = 0.48860299587249755859375 * _15046;
            float _15053 = _14098.x;
            float _15054 = 0.48860299587249755859375 * _15053;
            float _15061 = 1.09254801273345947265625 * _15053;
            float _15064 = _15061 * _15039;
            float _15074 = (1.09254801273345947265625 * _15039) * _15046;
            float _15086 = 0.3153919875621795654296875 * (((3.0 * _15046) * _15046) - 1.0);
            float _15096 = _15061 * _15046;
            float _15112 = 0.546274006366729736328125 * ((_15053 * _15053) - (_15039 * _15039));
            vec3 _14106 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _15040)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _15047)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _15054)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _15064)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _15074)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _15086)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _15096)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _15112), vec3(0.0));
            vec3 _30894 = vec3(0.0);
            do
            {
                _15220 = radiance_layout_info.mip_layout > 0.5;
                if (_15220)
                {
                    vec2 _15299 = vec2(atan(_14103.z, _14103.x), asin(clamp(_14103.y, -1.0, 1.0)));
                    highp vec2 hp_copy_15299 = _15299;
                    _30894 = textureLod(prefiltered_radiance, (hp_copy_15299 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_30874, 0.0, 1.0) * 7.0).xyz;
                    break;
                }
                vec2 _15318 = vec2(atan(_14103.z, _14103.x), asin(clamp(_14103.y, -1.0, 1.0)));
                highp vec2 hp_copy_15318 = _15318;
                highp vec2 _15323 = (hp_copy_15318 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _15230 = clamp(_15323.y, 0.00390625, 0.99609375);
                float _15234 = clamp(_30874, 0.0, 1.0) * 7.0;
                float _15236 = floor(_15234);
                highp float _15255 = _15323.x;
                _30894 = mix(texture(prefiltered_radiance, vec2(_15255, (_15236 + _15230) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_15255, (min(_15236 + 1.0, 7.0) + _15230) * 0.125)).xyz, vec3(_15234 - _15236));
                break;
            } while(false);
            bool _14113 = frag_info.radiance_blend.x > 0.0;
            highp vec3 _30899 = vec3(0.0);
            highp vec3 _30900 = vec3(0.0);
            if (_14113)
            {
                vec3 _30895 = vec3(0.0);
                do
                {
                    if (_15220)
                    {
                        vec2 _15611 = vec2(atan(_14103.z, _14103.x), asin(clamp(_14103.y, -1.0, 1.0)));
                        highp vec2 hp_copy_15611 = _15611;
                        _30895 = textureLod(prefiltered_radiance_b, (hp_copy_15611 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_30874, 0.0, 1.0) * 7.0).xyz;
                        break;
                    }
                    vec2 _15630 = vec2(atan(_14103.z, _14103.x), asin(clamp(_14103.y, -1.0, 1.0)));
                    highp vec2 hp_copy_15630 = _15630;
                    highp vec2 _15635 = (hp_copy_15630 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _15542 = clamp(_15635.y, 0.00390625, 0.99609375);
                    float _15546 = clamp(_30874, 0.0, 1.0) * 7.0;
                    float _15548 = floor(_15546);
                    highp float _15567 = _15635.x;
                    _30895 = mix(texture(prefiltered_radiance_b, vec2(_15567, (_15548 + _15542) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_15567, (min(_15548 + 1.0, 7.0) + _15542) * 0.125)).xyz, vec3(_15546 - _15548));
                    break;
                } while(false);
                highp vec3 _14124 = vec3(frag_info.radiance_blend.x);
                _30900 = mix(_30894, _30895, _14124);
                _30899 = mix(_14106, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _15040)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _15047)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _15054)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _15064)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _15074)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _15086)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _15096)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _15112), vec3(0.0)), _14124);
            }
            else
            {
                _30900 = _30894;
                _30899 = _14106;
            }
            highp float _15648 = 0.0;
            highp vec3 _14135 = _30899 * frag_info.environment_intensity;
            float _30901 = 0.0;
            do
            {
                _15648 = frag_info.gi_grid.w;
                if (_15648 <= 0.0)
                {
                    _30901 = 0.0;
                    break;
                }
                highp vec3 _15661 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
                highp vec3 _15669 = min(_15661, (frag_info.gi_counts.xyz - vec3(1.0)) - _15661);
                _30901 = clamp(min(_15669.x, min(_15669.y, _15669.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
                break;
            } while(false);
            highp vec3 _31092 = vec3(0.0);
            if (_30901 > 0.0)
            {
                highp vec3 _15761 = v_position + (((_30829 * 0.20000000298023223876953125) + (mp_copy_30882 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
                highp vec3 _15764 = _15761 / frag_info.gi_grid.xyz;
                highp vec3 _15766 = floor(_15764);
                highp vec3 _15772 = clamp(_15764 - _15766, vec3(0.0), vec3(1.0));
                vec3 mp_copy_15772 = _15772;
                highp vec3 _15894 = _15766 - frag_info.gi_anchor.xyz;
                bool _15897 = any(lessThan(_15894, vec3(0.0)));
                bool _15905 = false;
                if (!_15897)
                {
                    _15905 = any(greaterThanEqual(_15894, frag_info.gi_counts.xyz));
                }
                else
                {
                    _15905 = _15897;
                }
                vec3 mp_copy_30902 = vec3(0.0);
                highp float _15906 = _15905 ? 0.0 : 1.0;
                float mp_copy_15906 = _15906;
                vec3 _15908 = vec3(1.0) - mp_copy_15772;
                vec3 _15912 = max(_15908, vec3(0.001000000047497451305389404296875));
                highp vec3 _15928 = (_15766 * frag_info.gi_grid.xyz) - _15761;
                highp float _15930 = length(_15928);
                highp vec3 _30902 = vec3(0.0);
                if (_15930 > 9.9999997473787516355514526367188e-06)
                {
                    _30902 = _15928 / vec3(_15930);
                }
                else
                {
                    _30902 = _30829;
                }
                mp_copy_30902 = _30902;
                float _15948 = pow((dot(_30902, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _16073 = _15766 - (frag_info.gi_counts.xyz * floor(_15766 / frag_info.gi_counts.xyz));
                highp float _16089 = _16073.x + (frag_info.gi_counts.x * (_16073.y + (frag_info.gi_counts.y * _16073.z)));
                bool _15959 = frag_info.gi_visibility.x > 0.0;
                float _30907 = 0.0;
                if (_15959)
                {
                    highp float _16097 = floor(_16089 / frag_info.gi_counts.w);
                    highp vec2 _16111 = vec2((_16089 - (_16097 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16097 * 16.0));
                    vec3 _15971 = -mp_copy_30902;
                    vec3 _16159 = _15971 / vec3((abs(_15971.x) + abs(_15971.y)) + abs(_15971.z));
                    vec2 _30903 = vec2(0.0);
                    if (_16159.z >= 0.0)
                    {
                        _30903 = _16159.xy;
                    }
                    else
                    {
                        _30903 = (vec2(1.0) - abs(_16159.yx)) * vec2((_16159.x >= 0.0) ? 1.0 : (-1.0), (_16159.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _15975 = texture(irradiance_field, clamp((_16111 + vec2(1.0)) + (clamp((_30903 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16111 + vec2(0.5), _16111 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _15980 = _15975.x * frag_info.gi_visibility.z;
                    highp float _15992 = abs((_15980 * _15980) - ((_15975.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _15998 = (_15930 - _15980) - frag_info.gi_visibility.y;
                    highp float _30904 = 0.0;
                    if (_15998 <= 0.0)
                    {
                        _30904 = 1.0;
                    }
                    else
                    {
                        _30904 = _15992 / (_15992 + (_15998 * _15998));
                    }
                    _30907 = _15948 * mix(1.0, max(0.0500000007450580596923828125, (_30904 * _30904) * _30904), frag_info.gi_visibility.x);
                }
                else
                {
                    _30907 = _15948;
                }
                float _16026 = max(9.9999999747524270787835121154785e-07, _30907);
                float _30908 = 0.0;
                if (_16026 < 0.20000000298023223876953125)
                {
                    _30908 = _16026 * ((_16026 * _16026) * 25.0);
                }
                else
                {
                    _30908 = _16026;
                }
                float _16041 = _30908 * (((_15912.x * _15912.y) * _15912.z) * mp_copy_15906);
                highp float _16200 = floor(_16089 / frag_info.gi_counts.w);
                highp vec2 _16214 = vec2((_16089 - (_16200 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16200 * 8.0));
                vec3 _16262 = _30829 / vec3((abs(_30829.x) + abs(_30829.y)) + abs(_30829.z));
                bool _16265 = _16262.z >= 0.0;
                vec2 _30909 = vec2(0.0);
                if (_16265)
                {
                    _30909 = _16262.xy;
                }
                else
                {
                    _30909 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16053 = texture(irradiance_field, clamp((_16214 + vec2(1.0)) + (clamp((_30909 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16214 + vec2(0.5), _16214 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _16348 = _15766 + vec3(1.0, 0.0, 0.0);
                highp vec3 _16353 = _16348 - frag_info.gi_anchor.xyz;
                bool _16356 = any(lessThan(_16353, vec3(0.0)));
                bool _16364 = false;
                if (!_16356)
                {
                    _16364 = any(greaterThanEqual(_16353, frag_info.gi_counts.xyz));
                }
                else
                {
                    _16364 = _16356;
                }
                vec3 mp_copy_30911 = vec3(0.0);
                highp float _16365 = _16364 ? 0.0 : 1.0;
                float mp_copy_16365 = _16365;
                vec3 _16371 = max(mix(_15908, mp_copy_15772, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _16387 = (_16348 * frag_info.gi_grid.xyz) - _15761;
                highp float _16389 = length(_16387);
                highp vec3 _30911 = vec3(0.0);
                if (_16389 > 9.9999997473787516355514526367188e-06)
                {
                    _30911 = _16387 / vec3(_16389);
                }
                else
                {
                    _30911 = _30829;
                }
                mp_copy_30911 = _30911;
                float _16407 = pow((dot(_30911, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _16532 = _16348 - (frag_info.gi_counts.xyz * floor(_16348 / frag_info.gi_counts.xyz));
                highp float _16548 = _16532.x + (frag_info.gi_counts.x * (_16532.y + (frag_info.gi_counts.y * _16532.z)));
                float _30916 = 0.0;
                if (_15959)
                {
                    highp float _16556 = floor(_16548 / frag_info.gi_counts.w);
                    highp vec2 _16570 = vec2((_16548 - (_16556 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16556 * 16.0));
                    vec3 _16430 = -mp_copy_30911;
                    vec3 _16618 = _16430 / vec3((abs(_16430.x) + abs(_16430.y)) + abs(_16430.z));
                    vec2 _30912 = vec2(0.0);
                    if (_16618.z >= 0.0)
                    {
                        _30912 = _16618.xy;
                    }
                    else
                    {
                        _30912 = (vec2(1.0) - abs(_16618.yx)) * vec2((_16618.x >= 0.0) ? 1.0 : (-1.0), (_16618.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _16434 = texture(irradiance_field, clamp((_16570 + vec2(1.0)) + (clamp((_30912 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16570 + vec2(0.5), _16570 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _16439 = _16434.x * frag_info.gi_visibility.z;
                    highp float _16451 = abs((_16439 * _16439) - ((_16434.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _16457 = (_16389 - _16439) - frag_info.gi_visibility.y;
                    highp float _30913 = 0.0;
                    if (_16457 <= 0.0)
                    {
                        _30913 = 1.0;
                    }
                    else
                    {
                        _30913 = _16451 / (_16451 + (_16457 * _16457));
                    }
                    _30916 = _16407 * mix(1.0, max(0.0500000007450580596923828125, (_30913 * _30913) * _30913), frag_info.gi_visibility.x);
                }
                else
                {
                    _30916 = _16407;
                }
                float _16485 = max(9.9999999747524270787835121154785e-07, _30916);
                float _30917 = 0.0;
                if (_16485 < 0.20000000298023223876953125)
                {
                    _30917 = _16485 * ((_16485 * _16485) * 25.0);
                }
                else
                {
                    _30917 = _16485;
                }
                float _16500 = _30917 * (((_16371.x * _16371.y) * _16371.z) * mp_copy_16365);
                highp float _16659 = floor(_16548 / frag_info.gi_counts.w);
                highp vec2 _16673 = vec2((_16548 - (_16659 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16659 * 8.0));
                vec2 _30918 = vec2(0.0);
                if (_16265)
                {
                    _30918 = _16262.xy;
                }
                else
                {
                    _30918 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16512 = texture(irradiance_field, clamp((_16673 + vec2(1.0)) + (clamp((_30918 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16673 + vec2(0.5), _16673 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _16807 = _15766 + vec3(0.0, 1.0, 0.0);
                highp vec3 _16812 = _16807 - frag_info.gi_anchor.xyz;
                bool _16815 = any(lessThan(_16812, vec3(0.0)));
                bool _16823 = false;
                if (!_16815)
                {
                    _16823 = any(greaterThanEqual(_16812, frag_info.gi_counts.xyz));
                }
                else
                {
                    _16823 = _16815;
                }
                vec3 mp_copy_30920 = vec3(0.0);
                highp float _16824 = _16823 ? 0.0 : 1.0;
                float mp_copy_16824 = _16824;
                vec3 _16830 = max(mix(_15908, mp_copy_15772, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _16846 = (_16807 * frag_info.gi_grid.xyz) - _15761;
                highp float _16848 = length(_16846);
                highp vec3 _30920 = vec3(0.0);
                if (_16848 > 9.9999997473787516355514526367188e-06)
                {
                    _30920 = _16846 / vec3(_16848);
                }
                else
                {
                    _30920 = _30829;
                }
                mp_copy_30920 = _30920;
                float _16866 = pow((dot(_30920, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _16991 = _16807 - (frag_info.gi_counts.xyz * floor(_16807 / frag_info.gi_counts.xyz));
                highp float _17007 = _16991.x + (frag_info.gi_counts.x * (_16991.y + (frag_info.gi_counts.y * _16991.z)));
                float _30925 = 0.0;
                if (_15959)
                {
                    highp float _17015 = floor(_17007 / frag_info.gi_counts.w);
                    highp vec2 _17029 = vec2((_17007 - (_17015 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17015 * 16.0));
                    vec3 _16889 = -mp_copy_30920;
                    vec3 _17077 = _16889 / vec3((abs(_16889.x) + abs(_16889.y)) + abs(_16889.z));
                    vec2 _30921 = vec2(0.0);
                    if (_17077.z >= 0.0)
                    {
                        _30921 = _17077.xy;
                    }
                    else
                    {
                        _30921 = (vec2(1.0) - abs(_17077.yx)) * vec2((_17077.x >= 0.0) ? 1.0 : (-1.0), (_17077.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _16893 = texture(irradiance_field, clamp((_17029 + vec2(1.0)) + (clamp((_30921 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17029 + vec2(0.5), _17029 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _16898 = _16893.x * frag_info.gi_visibility.z;
                    highp float _16910 = abs((_16898 * _16898) - ((_16893.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _16916 = (_16848 - _16898) - frag_info.gi_visibility.y;
                    highp float _30922 = 0.0;
                    if (_16916 <= 0.0)
                    {
                        _30922 = 1.0;
                    }
                    else
                    {
                        _30922 = _16910 / (_16910 + (_16916 * _16916));
                    }
                    _30925 = _16866 * mix(1.0, max(0.0500000007450580596923828125, (_30922 * _30922) * _30922), frag_info.gi_visibility.x);
                }
                else
                {
                    _30925 = _16866;
                }
                float _16944 = max(9.9999999747524270787835121154785e-07, _30925);
                float _30926 = 0.0;
                if (_16944 < 0.20000000298023223876953125)
                {
                    _30926 = _16944 * ((_16944 * _16944) * 25.0);
                }
                else
                {
                    _30926 = _16944;
                }
                float _16959 = _30926 * (((_16830.x * _16830.y) * _16830.z) * mp_copy_16824);
                highp float _17118 = floor(_17007 / frag_info.gi_counts.w);
                highp vec2 _17132 = vec2((_17007 - (_17118 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_17118 * 8.0));
                vec2 _30927 = vec2(0.0);
                if (_16265)
                {
                    _30927 = _16262.xy;
                }
                else
                {
                    _30927 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16971 = texture(irradiance_field, clamp((_17132 + vec2(1.0)) + (clamp((_30927 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _17132 + vec2(0.5), _17132 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _17266 = _15766 + vec3(1.0, 1.0, 0.0);
                highp vec3 _17271 = _17266 - frag_info.gi_anchor.xyz;
                bool _17274 = any(lessThan(_17271, vec3(0.0)));
                bool _17282 = false;
                if (!_17274)
                {
                    _17282 = any(greaterThanEqual(_17271, frag_info.gi_counts.xyz));
                }
                else
                {
                    _17282 = _17274;
                }
                vec3 mp_copy_30929 = vec3(0.0);
                highp float _17283 = _17282 ? 0.0 : 1.0;
                float mp_copy_17283 = _17283;
                vec3 _17289 = max(mix(_15908, mp_copy_15772, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _17305 = (_17266 * frag_info.gi_grid.xyz) - _15761;
                highp float _17307 = length(_17305);
                highp vec3 _30929 = vec3(0.0);
                if (_17307 > 9.9999997473787516355514526367188e-06)
                {
                    _30929 = _17305 / vec3(_17307);
                }
                else
                {
                    _30929 = _30829;
                }
                mp_copy_30929 = _30929;
                float _17325 = pow((dot(_30929, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _17450 = _17266 - (frag_info.gi_counts.xyz * floor(_17266 / frag_info.gi_counts.xyz));
                highp float _17466 = _17450.x + (frag_info.gi_counts.x * (_17450.y + (frag_info.gi_counts.y * _17450.z)));
                float _30934 = 0.0;
                if (_15959)
                {
                    highp float _17474 = floor(_17466 / frag_info.gi_counts.w);
                    highp vec2 _17488 = vec2((_17466 - (_17474 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17474 * 16.0));
                    vec3 _17348 = -mp_copy_30929;
                    vec3 _17536 = _17348 / vec3((abs(_17348.x) + abs(_17348.y)) + abs(_17348.z));
                    vec2 _30930 = vec2(0.0);
                    if (_17536.z >= 0.0)
                    {
                        _30930 = _17536.xy;
                    }
                    else
                    {
                        _30930 = (vec2(1.0) - abs(_17536.yx)) * vec2((_17536.x >= 0.0) ? 1.0 : (-1.0), (_17536.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _17352 = texture(irradiance_field, clamp((_17488 + vec2(1.0)) + (clamp((_30930 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17488 + vec2(0.5), _17488 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _17357 = _17352.x * frag_info.gi_visibility.z;
                    highp float _17369 = abs((_17357 * _17357) - ((_17352.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _17375 = (_17307 - _17357) - frag_info.gi_visibility.y;
                    highp float _30931 = 0.0;
                    if (_17375 <= 0.0)
                    {
                        _30931 = 1.0;
                    }
                    else
                    {
                        _30931 = _17369 / (_17369 + (_17375 * _17375));
                    }
                    _30934 = _17325 * mix(1.0, max(0.0500000007450580596923828125, (_30931 * _30931) * _30931), frag_info.gi_visibility.x);
                }
                else
                {
                    _30934 = _17325;
                }
                float _17403 = max(9.9999999747524270787835121154785e-07, _30934);
                float _30935 = 0.0;
                if (_17403 < 0.20000000298023223876953125)
                {
                    _30935 = _17403 * ((_17403 * _17403) * 25.0);
                }
                else
                {
                    _30935 = _17403;
                }
                float _17418 = _30935 * (((_17289.x * _17289.y) * _17289.z) * mp_copy_17283);
                highp float _17577 = floor(_17466 / frag_info.gi_counts.w);
                highp vec2 _17591 = vec2((_17466 - (_17577 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_17577 * 8.0));
                vec2 _30936 = vec2(0.0);
                if (_16265)
                {
                    _30936 = _16262.xy;
                }
                else
                {
                    _30936 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _17430 = texture(irradiance_field, clamp((_17591 + vec2(1.0)) + (clamp((_30936 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _17591 + vec2(0.5), _17591 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _17725 = _15766 + vec3(0.0, 0.0, 1.0);
                highp vec3 _17730 = _17725 - frag_info.gi_anchor.xyz;
                bool _17733 = any(lessThan(_17730, vec3(0.0)));
                bool _17741 = false;
                if (!_17733)
                {
                    _17741 = any(greaterThanEqual(_17730, frag_info.gi_counts.xyz));
                }
                else
                {
                    _17741 = _17733;
                }
                vec3 mp_copy_30938 = vec3(0.0);
                highp float _17742 = _17741 ? 0.0 : 1.0;
                float mp_copy_17742 = _17742;
                vec3 _17748 = max(mix(_15908, mp_copy_15772, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _17764 = (_17725 * frag_info.gi_grid.xyz) - _15761;
                highp float _17766 = length(_17764);
                highp vec3 _30938 = vec3(0.0);
                if (_17766 > 9.9999997473787516355514526367188e-06)
                {
                    _30938 = _17764 / vec3(_17766);
                }
                else
                {
                    _30938 = _30829;
                }
                mp_copy_30938 = _30938;
                float _17784 = pow((dot(_30938, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _17909 = _17725 - (frag_info.gi_counts.xyz * floor(_17725 / frag_info.gi_counts.xyz));
                highp float _17925 = _17909.x + (frag_info.gi_counts.x * (_17909.y + (frag_info.gi_counts.y * _17909.z)));
                float _30943 = 0.0;
                if (_15959)
                {
                    highp float _17933 = floor(_17925 / frag_info.gi_counts.w);
                    highp vec2 _17947 = vec2((_17925 - (_17933 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17933 * 16.0));
                    vec3 _17807 = -mp_copy_30938;
                    vec3 _17995 = _17807 / vec3((abs(_17807.x) + abs(_17807.y)) + abs(_17807.z));
                    vec2 _30939 = vec2(0.0);
                    if (_17995.z >= 0.0)
                    {
                        _30939 = _17995.xy;
                    }
                    else
                    {
                        _30939 = (vec2(1.0) - abs(_17995.yx)) * vec2((_17995.x >= 0.0) ? 1.0 : (-1.0), (_17995.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _17811 = texture(irradiance_field, clamp((_17947 + vec2(1.0)) + (clamp((_30939 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17947 + vec2(0.5), _17947 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _17816 = _17811.x * frag_info.gi_visibility.z;
                    highp float _17828 = abs((_17816 * _17816) - ((_17811.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _17834 = (_17766 - _17816) - frag_info.gi_visibility.y;
                    highp float _30940 = 0.0;
                    if (_17834 <= 0.0)
                    {
                        _30940 = 1.0;
                    }
                    else
                    {
                        _30940 = _17828 / (_17828 + (_17834 * _17834));
                    }
                    _30943 = _17784 * mix(1.0, max(0.0500000007450580596923828125, (_30940 * _30940) * _30940), frag_info.gi_visibility.x);
                }
                else
                {
                    _30943 = _17784;
                }
                float _17862 = max(9.9999999747524270787835121154785e-07, _30943);
                float _30944 = 0.0;
                if (_17862 < 0.20000000298023223876953125)
                {
                    _30944 = _17862 * ((_17862 * _17862) * 25.0);
                }
                else
                {
                    _30944 = _17862;
                }
                float _17877 = _30944 * (((_17748.x * _17748.y) * _17748.z) * mp_copy_17742);
                highp float _18036 = floor(_17925 / frag_info.gi_counts.w);
                highp vec2 _18050 = vec2((_17925 - (_18036 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18036 * 8.0));
                vec2 _30945 = vec2(0.0);
                if (_16265)
                {
                    _30945 = _16262.xy;
                }
                else
                {
                    _30945 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _17889 = texture(irradiance_field, clamp((_18050 + vec2(1.0)) + (clamp((_30945 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18050 + vec2(0.5), _18050 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _18184 = _15766 + vec3(1.0, 0.0, 1.0);
                highp vec3 _18189 = _18184 - frag_info.gi_anchor.xyz;
                bool _18192 = any(lessThan(_18189, vec3(0.0)));
                bool _18200 = false;
                if (!_18192)
                {
                    _18200 = any(greaterThanEqual(_18189, frag_info.gi_counts.xyz));
                }
                else
                {
                    _18200 = _18192;
                }
                vec3 mp_copy_30947 = vec3(0.0);
                highp float _18201 = _18200 ? 0.0 : 1.0;
                float mp_copy_18201 = _18201;
                vec3 _18207 = max(mix(_15908, mp_copy_15772, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _18223 = (_18184 * frag_info.gi_grid.xyz) - _15761;
                highp float _18225 = length(_18223);
                highp vec3 _30947 = vec3(0.0);
                if (_18225 > 9.9999997473787516355514526367188e-06)
                {
                    _30947 = _18223 / vec3(_18225);
                }
                else
                {
                    _30947 = _30829;
                }
                mp_copy_30947 = _30947;
                float _18243 = pow((dot(_30947, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _18368 = _18184 - (frag_info.gi_counts.xyz * floor(_18184 / frag_info.gi_counts.xyz));
                highp float _18384 = _18368.x + (frag_info.gi_counts.x * (_18368.y + (frag_info.gi_counts.y * _18368.z)));
                float _30952 = 0.0;
                if (_15959)
                {
                    highp float _18392 = floor(_18384 / frag_info.gi_counts.w);
                    highp vec2 _18406 = vec2((_18384 - (_18392 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_18392 * 16.0));
                    vec3 _18266 = -mp_copy_30947;
                    vec3 _18454 = _18266 / vec3((abs(_18266.x) + abs(_18266.y)) + abs(_18266.z));
                    vec2 _30948 = vec2(0.0);
                    if (_18454.z >= 0.0)
                    {
                        _30948 = _18454.xy;
                    }
                    else
                    {
                        _30948 = (vec2(1.0) - abs(_18454.yx)) * vec2((_18454.x >= 0.0) ? 1.0 : (-1.0), (_18454.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _18270 = texture(irradiance_field, clamp((_18406 + vec2(1.0)) + (clamp((_30948 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _18406 + vec2(0.5), _18406 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _18275 = _18270.x * frag_info.gi_visibility.z;
                    highp float _18287 = abs((_18275 * _18275) - ((_18270.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _18293 = (_18225 - _18275) - frag_info.gi_visibility.y;
                    highp float _30949 = 0.0;
                    if (_18293 <= 0.0)
                    {
                        _30949 = 1.0;
                    }
                    else
                    {
                        _30949 = _18287 / (_18287 + (_18293 * _18293));
                    }
                    _30952 = _18243 * mix(1.0, max(0.0500000007450580596923828125, (_30949 * _30949) * _30949), frag_info.gi_visibility.x);
                }
                else
                {
                    _30952 = _18243;
                }
                float _18321 = max(9.9999999747524270787835121154785e-07, _30952);
                float _30953 = 0.0;
                if (_18321 < 0.20000000298023223876953125)
                {
                    _30953 = _18321 * ((_18321 * _18321) * 25.0);
                }
                else
                {
                    _30953 = _18321;
                }
                float _18336 = _30953 * (((_18207.x * _18207.y) * _18207.z) * mp_copy_18201);
                highp float _18495 = floor(_18384 / frag_info.gi_counts.w);
                highp vec2 _18509 = vec2((_18384 - (_18495 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18495 * 8.0));
                vec2 _30954 = vec2(0.0);
                if (_16265)
                {
                    _30954 = _16262.xy;
                }
                else
                {
                    _30954 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _18348 = texture(irradiance_field, clamp((_18509 + vec2(1.0)) + (clamp((_30954 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18509 + vec2(0.5), _18509 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _18643 = _15766 + vec3(0.0, 1.0, 1.0);
                highp vec3 _18648 = _18643 - frag_info.gi_anchor.xyz;
                bool _18651 = any(lessThan(_18648, vec3(0.0)));
                bool _18659 = false;
                if (!_18651)
                {
                    _18659 = any(greaterThanEqual(_18648, frag_info.gi_counts.xyz));
                }
                else
                {
                    _18659 = _18651;
                }
                vec3 mp_copy_30956 = vec3(0.0);
                highp float _18660 = _18659 ? 0.0 : 1.0;
                float mp_copy_18660 = _18660;
                vec3 _18666 = max(mix(_15908, mp_copy_15772, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _18682 = (_18643 * frag_info.gi_grid.xyz) - _15761;
                highp float _18684 = length(_18682);
                highp vec3 _30956 = vec3(0.0);
                if (_18684 > 9.9999997473787516355514526367188e-06)
                {
                    _30956 = _18682 / vec3(_18684);
                }
                else
                {
                    _30956 = _30829;
                }
                mp_copy_30956 = _30956;
                float _18702 = pow((dot(_30956, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _18827 = _18643 - (frag_info.gi_counts.xyz * floor(_18643 / frag_info.gi_counts.xyz));
                highp float _18843 = _18827.x + (frag_info.gi_counts.x * (_18827.y + (frag_info.gi_counts.y * _18827.z)));
                float _30961 = 0.0;
                if (_15959)
                {
                    highp float _18851 = floor(_18843 / frag_info.gi_counts.w);
                    highp vec2 _18865 = vec2((_18843 - (_18851 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_18851 * 16.0));
                    vec3 _18725 = -mp_copy_30956;
                    vec3 _18913 = _18725 / vec3((abs(_18725.x) + abs(_18725.y)) + abs(_18725.z));
                    vec2 _30957 = vec2(0.0);
                    if (_18913.z >= 0.0)
                    {
                        _30957 = _18913.xy;
                    }
                    else
                    {
                        _30957 = (vec2(1.0) - abs(_18913.yx)) * vec2((_18913.x >= 0.0) ? 1.0 : (-1.0), (_18913.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _18729 = texture(irradiance_field, clamp((_18865 + vec2(1.0)) + (clamp((_30957 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _18865 + vec2(0.5), _18865 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _18734 = _18729.x * frag_info.gi_visibility.z;
                    highp float _18746 = abs((_18734 * _18734) - ((_18729.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _18752 = (_18684 - _18734) - frag_info.gi_visibility.y;
                    highp float _30958 = 0.0;
                    if (_18752 <= 0.0)
                    {
                        _30958 = 1.0;
                    }
                    else
                    {
                        _30958 = _18746 / (_18746 + (_18752 * _18752));
                    }
                    _30961 = _18702 * mix(1.0, max(0.0500000007450580596923828125, (_30958 * _30958) * _30958), frag_info.gi_visibility.x);
                }
                else
                {
                    _30961 = _18702;
                }
                float _18780 = max(9.9999999747524270787835121154785e-07, _30961);
                float _30962 = 0.0;
                if (_18780 < 0.20000000298023223876953125)
                {
                    _30962 = _18780 * ((_18780 * _18780) * 25.0);
                }
                else
                {
                    _30962 = _18780;
                }
                float _18795 = _30962 * (((_18666.x * _18666.y) * _18666.z) * mp_copy_18660);
                highp float _18954 = floor(_18843 / frag_info.gi_counts.w);
                highp vec2 _18968 = vec2((_18843 - (_18954 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18954 * 8.0));
                vec2 _30963 = vec2(0.0);
                if (_16265)
                {
                    _30963 = _16262.xy;
                }
                else
                {
                    _30963 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _18807 = texture(irradiance_field, clamp((_18968 + vec2(1.0)) + (clamp((_30963 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18968 + vec2(0.5), _18968 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _19102 = _15766 + vec3(1.0);
                highp vec3 _19107 = _19102 - frag_info.gi_anchor.xyz;
                bool _19110 = any(lessThan(_19107, vec3(0.0)));
                bool _19118 = false;
                if (!_19110)
                {
                    _19118 = any(greaterThanEqual(_19107, frag_info.gi_counts.xyz));
                }
                else
                {
                    _19118 = _19110;
                }
                vec3 mp_copy_30965 = vec3(0.0);
                highp float _19119 = _19118 ? 0.0 : 1.0;
                float mp_copy_19119 = _19119;
                vec3 _19125 = max(mp_copy_15772, vec3(0.001000000047497451305389404296875));
                highp vec3 _19141 = (_19102 * frag_info.gi_grid.xyz) - _15761;
                highp float _19143 = length(_19141);
                highp vec3 _30965 = vec3(0.0);
                if (_19143 > 9.9999997473787516355514526367188e-06)
                {
                    _30965 = _19141 / vec3(_19143);
                }
                else
                {
                    _30965 = _30829;
                }
                mp_copy_30965 = _30965;
                float _19161 = pow((dot(_30965, _30829) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _19286 = _19102 - (frag_info.gi_counts.xyz * floor(_19102 / frag_info.gi_counts.xyz));
                highp float _19302 = _19286.x + (frag_info.gi_counts.x * (_19286.y + (frag_info.gi_counts.y * _19286.z)));
                float _30970 = 0.0;
                if (_15959)
                {
                    highp float _19310 = floor(_19302 / frag_info.gi_counts.w);
                    highp vec2 _19324 = vec2((_19302 - (_19310 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_19310 * 16.0));
                    vec3 _19184 = -mp_copy_30965;
                    vec3 _19372 = _19184 / vec3((abs(_19184.x) + abs(_19184.y)) + abs(_19184.z));
                    vec2 _30966 = vec2(0.0);
                    if (_19372.z >= 0.0)
                    {
                        _30966 = _19372.xy;
                    }
                    else
                    {
                        _30966 = (vec2(1.0) - abs(_19372.yx)) * vec2((_19372.x >= 0.0) ? 1.0 : (-1.0), (_19372.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _19188 = texture(irradiance_field, clamp((_19324 + vec2(1.0)) + (clamp((_30966 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _19324 + vec2(0.5), _19324 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _19193 = _19188.x * frag_info.gi_visibility.z;
                    highp float _19205 = abs((_19193 * _19193) - ((_19188.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _19211 = (_19143 - _19193) - frag_info.gi_visibility.y;
                    highp float _30967 = 0.0;
                    if (_19211 <= 0.0)
                    {
                        _30967 = 1.0;
                    }
                    else
                    {
                        _30967 = _19205 / (_19205 + (_19211 * _19211));
                    }
                    _30970 = _19161 * mix(1.0, max(0.0500000007450580596923828125, (_30967 * _30967) * _30967), frag_info.gi_visibility.x);
                }
                else
                {
                    _30970 = _19161;
                }
                float _19239 = max(9.9999999747524270787835121154785e-07, _30970);
                float _30971 = 0.0;
                if (_19239 < 0.20000000298023223876953125)
                {
                    _30971 = _19239 * ((_19239 * _19239) * 25.0);
                }
                else
                {
                    _30971 = _19239;
                }
                float _19254 = _30971 * (((_19125.x * _19125.y) * _19125.z) * mp_copy_19119);
                highp float _19413 = floor(_19302 / frag_info.gi_counts.w);
                highp vec2 _19427 = vec2((_19302 - (_19413 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_19413 * 8.0));
                vec2 _30972 = vec2(0.0);
                if (_16265)
                {
                    _30972 = _16262.xy;
                }
                else
                {
                    _30972 = (vec2(1.0) - abs(_16262.yx)) * vec2((_16262.x >= 0.0) ? 1.0 : (-1.0), (_16262.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _15819 = ((((((vec4(max(_16053.xyz, vec3(0.0)) * _16041, _16041) + vec4(max(_16512.xyz, vec3(0.0)) * _16500, _16500)) + vec4(max(_16971.xyz, vec3(0.0)) * _16959, _16959)) + vec4(max(_17430.xyz, vec3(0.0)) * _17418, _17418)) + vec4(max(_17889.xyz, vec3(0.0)) * _17877, _17877)) + vec4(max(_18348.xyz, vec3(0.0)) * _18336, _18336)) + vec4(max(_18807.xyz, vec3(0.0)) * _18795, _18795)) + vec4(max(texture(irradiance_field, clamp((_19427 + vec2(1.0)) + (clamp((_30972 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _19427 + vec2(0.5), _19427 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _19254, _19254);
                highp float _15821 = _15819.w;
                highp vec3 _30974 = vec3(0.0);
                if (_15821 > 9.9999999747524270787835121154785e-07)
                {
                    _30974 = _15819.xyz / vec3(_15821);
                }
                else
                {
                    _30974 = vec3(0.0);
                }
                _31092 = mix(_14135, _30974 * _15648, vec3(_30901));
            }
            else
            {
                _31092 = _14135;
            }
            vec2 _14161 = clamp(vec2(_14073, _30874), vec2(0.0), vec2(0.9900000095367431640625));
            vec4 _14163 = texture(brdf_lut, vec2(_14161.x * 0.3333333432674407958984375, _14161.y));
            float _14167 = _14163.x;
            float _14170 = _14163.y;
            vec3 _14172 = ((_14065 + ((max(vec3(1.0 - _30874), _14065) - _14065) * pow(clamp(1.0 - _14073, 0.0, 1.0), 5.0))) * _14167) + vec3(_14170);
            float _14178 = 1.0 - (_14167 + _14170);
            vec3 _14182 = vec3(1.0) - _14065;
            vec3 _14185 = _14065 + (_14182 * vec3(0.0476190485060214996337890625));
            vec3 _14196 = ((_14172 * _14178) * _14185) / (vec3(1.0) - (_14185 * _14178));
            float _14199 = 1.0 - _7287;
            vec3 _14200 = _13970 * _14199;
            float _31830 = 0.0;
            if ((frag_info.ssao_params.y > 1.5) && _14093)
            {
                float _19535 = max(acos(clamp(exp2(((-3.321929931640625) * _30874) * _30874), 0.0, 1.0)), 0.100000001490116119384765625);
                _31830 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_30889, _14077), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _31162, 0.0, 1.0)))) + _19535) / (2.0 * _19535), 0.0, 1.0));
            }
            else
            {
                float _31831 = 0.0;
                if (frag_info.ssao_params.y > 0.5)
                {
                    _31831 = clamp((pow(_14069 + _31162, exp2(((-16.0) * _30874) - 1.0)) - 1.0) + _31162, 0.0, 1.0);
                }
                else
                {
                    _31831 = _31162;
                }
                _31830 = _31831;
            }
            bool _14249 = frag_info.has_directional_light > 0.5;
            float _31284 = 0.0;
            vec3 _31914 = vec3(0.0);
            if (_14249)
            {
                highp vec3 _14255 = -normalize(frag_info.directional_light_direction.xyz);
                _31914 = _14255;
                _31284 = dot(_7154, _14255);
            }
            else
            {
                _31914 = vec3(0.0);
                _31284 = 0.0;
            }
            float _14262 = clamp(_31284 * 6.666666507720947265625, 0.0, 1.0);
            bool _14271 = false;
            if (_14249)
            {
                _14271 = frag_info.casts_shadow > 0.5;
            }
            else
            {
                _14271 = _14249;
            }
            float _31521 = 0.0;
            if (_14271 && (_14262 > 0.0))
            {
                int _19656 = int(frag_info.shadow_cascade_count);
                float _20105 = max(dot(_7154, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
                float _20108 = _20105 * _20105;
                highp vec3 _20128 = v_position + (_7154 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _20108, 0.0)) / _20108, 8.0))));
                highp float _19662 = frag_info.directional_light_color.w * 0.5;
                float _31338 = 0.0;
                float _31378 = 0.0;
                if (_19656 > 0)
                {
                    highp vec4 _19679 = frag_info.light_space_matrix[0] * vec4(_20128, 1.0);
                    highp vec3 _19685 = _19679.xyz / vec3(_19679.w);
                    highp vec2 _19688 = _19685.xy * 0.5;
                    highp vec2 _19690 = _19688 + vec2(0.5);
                    highp float _19697 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
                    highp float _19699 = _19690.x;
                    bool _19701 = _19699 < _19697;
                    bool _19710 = false;
                    if (!_19701)
                    {
                        _19710 = _19699 > (1.0 - _19697);
                    }
                    else
                    {
                        _19710 = _19701;
                    }
                    bool _19718 = false;
                    if (!_19710)
                    {
                        _19718 = _19690.y < _19697;
                    }
                    else
                    {
                        _19718 = _19710;
                    }
                    bool _19727 = false;
                    if (!_19718)
                    {
                        _19727 = _19690.y > (1.0 - _19697);
                    }
                    else
                    {
                        _19727 = _19718;
                    }
                    bool _19734 = false;
                    if (!_19727)
                    {
                        _19734 = _19685.z < 0.0;
                    }
                    else
                    {
                        _19734 = _19727;
                    }
                    bool _19741 = false;
                    if (!_19734)
                    {
                        _19741 = _19685.z > 1.0;
                    }
                    else
                    {
                        _19741 = _19734;
                    }
                    float _31339 = 0.0;
                    float _31379 = 0.0;
                    if (!_19741)
                    {
                        highp vec2 _20136 = vec2(_19697);
                        highp vec2 _20141 = vec2(_19697 + max(_19662, 9.9999997473787516355514526367188e-05));
                        highp vec2 _20149 = vec2(0.5) - _19688;
                        highp vec2 _20151 = smoothstep(_20136, _20141, _19690) * smoothstep(_20136, _20141, _20149);
                        float _31285 = 0.0;
                        if (_19662 > 0.0)
                        {
                            _31285 = _20151.x * _20151.y;
                        }
                        else
                        {
                            _31285 = 1.0;
                        }
                        float _19750 = min(_31285, 1.0);
                        bool _19752 = _19750 > 0.0;
                        float _31380 = 0.0;
                        if (_19752)
                        {
                            highp float _20263 = _19685.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                            highp float _20269 = 1.0 / (float(_19656) + frag_info.spot_shadow_params.x);
                            highp float _20271 = frag_info.directional_light_direction.w;
                            float mp_copy_20271 = _20271;
                            float _20277 = step(0.5, mp_copy_20271) * (1.0 - step(1.5, mp_copy_20271));
                            highp float _20288 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _20277);
                            float mp_copy_20288 = _20288;
                            float _20290 = cos(mp_copy_20288);
                            float _20292 = sin(mp_copy_20288);
                            highp float _31303 = 0.0;
                            if ((_20271 > 1.5) && (_20271 < 2.5))
                            {
                                highp float _20311 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _20316 = max(_20311 * _20263, frag_info.shadow_texel_size);
                                float _31293 = 0.0;
                                highp float _31294 = 0.0;
                                _31294 = 0.0;
                                _31293 = 0.0;
                                highp float _20338 = 0.0;
                                float _20341 = 0.0;
                                for (int _31292 = 0; _31292 < 9; _31294 = _20338, _31293 = _20341, _31292++)
                                {
                                    vec2 _33820 = vec2(0.0);
                                    do
                                    {
                                        if (_31292 == 0)
                                        {
                                            _33820 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31292 == 1)
                                        {
                                            _33820 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31292 == 2)
                                        {
                                            _33820 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31292 == 3)
                                        {
                                            _33820 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31292 == 4)
                                        {
                                            _33820 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31292 == 5)
                                        {
                                            _33820 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31292 == 6)
                                        {
                                            _33820 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31292 == 7)
                                        {
                                            _33820 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31292 == 8)
                                        {
                                            _33820 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31292 == 9)
                                        {
                                            _33820 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31292 == 10)
                                        {
                                            _33820 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31292 == 11)
                                        {
                                            _33820 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31292 == 12)
                                        {
                                            _33820 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31292 == 13)
                                        {
                                            _33820 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31292 == 14)
                                        {
                                            _33820 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31292 == 15)
                                        {
                                            _33820 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33820 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _20583 = clamp(_19690 + (vec2((_33820.x * _20290) - (_33820.y * _20292), (_33820.x * _20292) + (_33820.y * _20290)) * _20316), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _20592 = _20583.y;
                                    highp vec2 _20593 = vec2(_20583.x * _20269, _20592);
                                    _20593.y = 1.0 - _20592;
                                    highp vec4 _20600 = textureLod(shadow_map, _20593, 0.0);
                                    highp float _20601 = _20600.x;
                                    highp float _20333 = step(_20601, _20263);
                                    float mp_copy_20333 = _20333;
                                    _20338 = _31294 + (_20601 * _20333);
                                    _20341 = _31293 + mp_copy_20333;
                                }
                                highp float _31295 = 0.0;
                                if (_31293 > 0.0)
                                {
                                    _31295 = _31294 / _31293;
                                }
                                else
                                {
                                    _31295 = _20263;
                                }
                                _31303 = clamp(_20311 * max(_20263 - _31295, 0.0), frag_info.shadow_texel_size, _19697);
                            }
                            else
                            {
                                _31303 = _19697;
                            }
                            float _31310 = 0.0;
                            if (_20271 > 2.5)
                            {
                                highp vec2 _20629 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _20633 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _20634 = clamp(_19690 + (vec2(-0.707099974155426025390625) * _31303), _20629, _20633);
                                highp vec2 _20645 = (vec2(_20634.x, 1.0 - _20634.y) / _20629) - vec2(0.5);
                                highp vec2 _20647 = floor(_20645);
                                highp vec2 _20650 = _20645 - _20647;
                                highp vec2 _20655 = (_20647 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20665 = vec2(_20655.x * _20269, _20655.y);
                                highp float _20669 = frag_info.shadow_texel_size * _20269;
                                highp vec2 _20672 = vec2(_20669, frag_info.shadow_texel_size);
                                highp vec2 _20681 = vec2(_20669, 0.0);
                                highp vec2 _20689 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _20718 = _20650.x;
                                highp float _20727 = mix(mix(float(_20263 <= textureLod(shadow_map, _20665, 0.0).x), float(_20263 <= textureLod(shadow_map, _20665 + _20681, 0.0).x), _20718), mix(float(_20263 <= textureLod(shadow_map, _20665 + _20689, 0.0).x), float(_20263 <= textureLod(shadow_map, _20665 + _20672, 0.0).x), _20718), _20650.y);
                                float mp_copy_20727 = _20727;
                                highp vec2 _20761 = clamp(_19690 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31303), _20629, _20633);
                                highp vec2 _20772 = (vec2(_20761.x, 1.0 - _20761.y) / _20629) - vec2(0.5);
                                highp vec2 _20774 = floor(_20772);
                                highp vec2 _20777 = _20772 - _20774;
                                highp vec2 _20782 = (_20774 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20792 = vec2(_20782.x * _20269, _20782.y);
                                highp float _20845 = _20777.x;
                                highp float _20854 = mix(mix(float(_20263 <= textureLod(shadow_map, _20792, 0.0).x), float(_20263 <= textureLod(shadow_map, _20792 + _20681, 0.0).x), _20845), mix(float(_20263 <= textureLod(shadow_map, _20792 + _20689, 0.0).x), float(_20263 <= textureLod(shadow_map, _20792 + _20672, 0.0).x), _20845), _20777.y);
                                float mp_copy_20854 = _20854;
                                highp vec2 _20888 = clamp(_19690 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31303), _20629, _20633);
                                highp vec2 _20899 = (vec2(_20888.x, 1.0 - _20888.y) / _20629) - vec2(0.5);
                                highp vec2 _20901 = floor(_20899);
                                highp vec2 _20904 = _20899 - _20901;
                                highp vec2 _20909 = (_20901 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20919 = vec2(_20909.x * _20269, _20909.y);
                                highp float _20972 = _20904.x;
                                highp float _20981 = mix(mix(float(_20263 <= textureLod(shadow_map, _20919, 0.0).x), float(_20263 <= textureLod(shadow_map, _20919 + _20681, 0.0).x), _20972), mix(float(_20263 <= textureLod(shadow_map, _20919 + _20689, 0.0).x), float(_20263 <= textureLod(shadow_map, _20919 + _20672, 0.0).x), _20972), _20904.y);
                                float mp_copy_20981 = _20981;
                                highp vec2 _21015 = clamp(_19690 + (vec2(0.707099974155426025390625) * _31303), _20629, _20633);
                                highp vec2 _21026 = (vec2(_21015.x, 1.0 - _21015.y) / _20629) - vec2(0.5);
                                highp vec2 _21028 = floor(_21026);
                                highp vec2 _21031 = _21026 - _21028;
                                highp vec2 _21036 = (_21028 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21046 = vec2(_21036.x * _20269, _21036.y);
                                highp float _21099 = _21031.x;
                                highp float _21108 = mix(mix(float(_20263 <= textureLod(shadow_map, _21046, 0.0).x), float(_20263 <= textureLod(shadow_map, _21046 + _20681, 0.0).x), _21099), mix(float(_20263 <= textureLod(shadow_map, _21046 + _20689, 0.0).x), float(_20263 <= textureLod(shadow_map, _21046 + _20672, 0.0).x), _21099), _21031.y);
                                float mp_copy_21108 = _21108;
                                _31310 = (((mp_copy_20727 + mp_copy_20854) + mp_copy_20981) + mp_copy_21108) * 0.25;
                            }
                            else
                            {
                                int _20404 = (_20277 > 0.5) ? 17 : 16;
                                float _31306 = 0.0;
                                _31306 = 0.0;
                                float _20432 = 0.0;
                                for (int _31296 = 0; _31296 < 17; _31306 = _20432, _31296++)
                                {
                                    if (_31296 >= _20404)
                                    {
                                        break;
                                    }
                                    vec2 _31297 = vec2(0.0);
                                    do
                                    {
                                        if (_31296 == 0)
                                        {
                                            _31297 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31296 == 1)
                                        {
                                            _31297 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31296 == 2)
                                        {
                                            _31297 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31296 == 3)
                                        {
                                            _31297 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31296 == 4)
                                        {
                                            _31297 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31296 == 5)
                                        {
                                            _31297 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31296 == 6)
                                        {
                                            _31297 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31296 == 7)
                                        {
                                            _31297 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31296 == 8)
                                        {
                                            _31297 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31296 == 9)
                                        {
                                            _31297 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31296 == 10)
                                        {
                                            _31297 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31296 == 11)
                                        {
                                            _31297 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31296 == 12)
                                        {
                                            _31297 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31296 == 13)
                                        {
                                            _31297 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31296 == 14)
                                        {
                                            _31297 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31296 == 15)
                                        {
                                            _31297 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31297 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31299 = vec2(0.0);
                                    do
                                    {
                                        if (_31296 < 3)
                                        {
                                            _31299 = vec2(float(_31296) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31296 < 6)
                                        {
                                            _31299 = vec2((float(_31296 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31296 < 11)
                                        {
                                            _31299 = vec2((float(_31296 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31296 < 14)
                                        {
                                            _31299 = vec2((float(_31296 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31299 = vec2(float(_31296 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _20421 = mix(_31297, _31299, vec2(_20277));
                                    float _21248 = _20421.x;
                                    float _21252 = _20421.y;
                                    highp vec2 _21278 = clamp(_19690 + (vec2((_21248 * _20290) - (_21252 * _20292), (_21248 * _20292) + (_21252 * _20290)) * _31303), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _21288 = vec2(_21278.x * _20269, _21278.y);
                                    _21288.y = 1.0 - _21278.y;
                                    highp float _21300 = float(_20263 <= textureLod(shadow_map, _21288, 0.0).x);
                                    float mp_copy_21300 = _21300;
                                    _20432 = _31306 + mp_copy_21300;
                                }
                                _31310 = _31306 / float(_20404);
                            }
                            bool _20445 = 0 == (_19656 - 1);
                            bool _20451 = false;
                            if (_20445)
                            {
                                _20451 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _20451 = _20445;
                            }
                            float _31311 = 0.0;
                            if (_20451)
                            {
                                highp vec2 _20458 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                                highp vec2 _20466 = smoothstep(vec2(0.0), _20458, _19690) * smoothstep(vec2(0.0), _20458, _20149);
                                _31311 = mix(1.0, _31310, _20466.x * _20466.y);
                            }
                            else
                            {
                                _31311 = _31310;
                            }
                            _31380 = _19750 * _31311;
                        }
                        else
                        {
                            _31380 = 0.0;
                        }
                        _31379 = _31380;
                        _31339 = _19752 ? _19750 : 0.0;
                    }
                    else
                    {
                        _31379 = 0.0;
                        _31339 = 0.0;
                    }
                    _31378 = _31379;
                    _31338 = _31339;
                }
                else
                {
                    _31378 = 0.0;
                    _31338 = 0.0;
                }
                float _31397 = 0.0;
                float _31437 = 0.0;
                if ((_31338 < 1.0) && (_19656 > 1))
                {
                    highp vec4 _19785 = frag_info.light_space_matrix[1] * vec4(_20128, 1.0);
                    highp vec3 _19791 = _19785.xyz / vec3(_19785.w);
                    highp vec2 _19794 = _19791.xy * 0.5;
                    highp vec2 _19796 = _19794 + vec2(0.5);
                    highp float _19803 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
                    highp float _19805 = _19796.x;
                    bool _19807 = _19805 < _19803;
                    bool _19816 = false;
                    if (!_19807)
                    {
                        _19816 = _19805 > (1.0 - _19803);
                    }
                    else
                    {
                        _19816 = _19807;
                    }
                    bool _19824 = false;
                    if (!_19816)
                    {
                        _19824 = _19796.y < _19803;
                    }
                    else
                    {
                        _19824 = _19816;
                    }
                    bool _19833 = false;
                    if (!_19824)
                    {
                        _19833 = _19796.y > (1.0 - _19803);
                    }
                    else
                    {
                        _19833 = _19824;
                    }
                    bool _19840 = false;
                    if (!_19833)
                    {
                        _19840 = _19791.z < 0.0;
                    }
                    else
                    {
                        _19840 = _19833;
                    }
                    bool _19847 = false;
                    if (!_19840)
                    {
                        _19847 = _19791.z > 1.0;
                    }
                    else
                    {
                        _19847 = _19840;
                    }
                    float _31398 = 0.0;
                    float _31438 = 0.0;
                    if (!_19847)
                    {
                        highp vec2 _21308 = vec2(_19803);
                        highp vec2 _21313 = vec2(_19803 + max(_19662, 9.9999997473787516355514526367188e-05));
                        highp vec2 _21321 = vec2(0.5) - _19794;
                        highp vec2 _21323 = smoothstep(_21308, _21313, _19796) * smoothstep(_21308, _21313, _21321);
                        float _31341 = 0.0;
                        if (_19662 > 0.0)
                        {
                            _31341 = _21323.x * _21323.y;
                        }
                        else
                        {
                            _31341 = 1.0;
                        }
                        float _19856 = min(_31341, 1.0 - _31338);
                        float _31399 = 0.0;
                        float _31439 = 0.0;
                        if (_19856 > 0.0)
                        {
                            highp float _21435 = _19791.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                            highp float _21441 = 1.0 / (float(_19656) + frag_info.spot_shadow_params.x);
                            highp float _21443 = frag_info.directional_light_direction.w;
                            float mp_copy_21443 = _21443;
                            float _21449 = step(0.5, mp_copy_21443) * (1.0 - step(1.5, mp_copy_21443));
                            highp float _21460 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _21449);
                            float mp_copy_21460 = _21460;
                            float _21462 = cos(mp_copy_21460);
                            float _21464 = sin(mp_copy_21460);
                            highp float _31359 = 0.0;
                            if ((_21443 > 1.5) && (_21443 < 2.5))
                            {
                                highp float _21483 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _21488 = max(_21483 * _21435, frag_info.shadow_texel_size);
                                float _31349 = 0.0;
                                highp float _31350 = 0.0;
                                _31350 = 0.0;
                                _31349 = 0.0;
                                highp float _21510 = 0.0;
                                float _21513 = 0.0;
                                for (int _31348 = 0; _31348 < 9; _31350 = _21510, _31349 = _21513, _31348++)
                                {
                                    vec2 _33816 = vec2(0.0);
                                    do
                                    {
                                        if (_31348 == 0)
                                        {
                                            _33816 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31348 == 1)
                                        {
                                            _33816 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31348 == 2)
                                        {
                                            _33816 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31348 == 3)
                                        {
                                            _33816 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31348 == 4)
                                        {
                                            _33816 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31348 == 5)
                                        {
                                            _33816 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31348 == 6)
                                        {
                                            _33816 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31348 == 7)
                                        {
                                            _33816 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31348 == 8)
                                        {
                                            _33816 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31348 == 9)
                                        {
                                            _33816 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31348 == 10)
                                        {
                                            _33816 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31348 == 11)
                                        {
                                            _33816 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31348 == 12)
                                        {
                                            _33816 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31348 == 13)
                                        {
                                            _33816 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31348 == 14)
                                        {
                                            _33816 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31348 == 15)
                                        {
                                            _33816 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33816 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _21755 = clamp(_19796 + (vec2((_33816.x * _21462) - (_33816.y * _21464), (_33816.x * _21464) + (_33816.y * _21462)) * _21488), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _21764 = _21755.y;
                                    highp vec2 _21765 = vec2((1.0 + _21755.x) * _21441, _21764);
                                    _21765.y = 1.0 - _21764;
                                    highp vec4 _21772 = textureLod(shadow_map, _21765, 0.0);
                                    highp float _21773 = _21772.x;
                                    highp float _21505 = step(_21773, _21435);
                                    float mp_copy_21505 = _21505;
                                    _21510 = _31350 + (_21773 * _21505);
                                    _21513 = _31349 + mp_copy_21505;
                                }
                                highp float _31351 = 0.0;
                                if (_31349 > 0.0)
                                {
                                    _31351 = _31350 / _31349;
                                }
                                else
                                {
                                    _31351 = _21435;
                                }
                                _31359 = clamp(_21483 * max(_21435 - _31351, 0.0), frag_info.shadow_texel_size, _19803);
                            }
                            else
                            {
                                _31359 = _19803;
                            }
                            float _31366 = 0.0;
                            if (_21443 > 2.5)
                            {
                                highp vec2 _21801 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _21805 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _21806 = clamp(_19796 + (vec2(-0.707099974155426025390625) * _31359), _21801, _21805);
                                highp vec2 _21817 = (vec2(_21806.x, 1.0 - _21806.y) / _21801) - vec2(0.5);
                                highp vec2 _21819 = floor(_21817);
                                highp vec2 _21822 = _21817 - _21819;
                                highp vec2 _21827 = (_21819 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21837 = vec2((1.0 + _21827.x) * _21441, _21827.y);
                                highp float _21841 = frag_info.shadow_texel_size * _21441;
                                highp vec2 _21844 = vec2(_21841, frag_info.shadow_texel_size);
                                highp vec2 _21853 = vec2(_21841, 0.0);
                                highp vec2 _21861 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _21890 = _21822.x;
                                highp float _21899 = mix(mix(float(_21435 <= textureLod(shadow_map, _21837, 0.0).x), float(_21435 <= textureLod(shadow_map, _21837 + _21853, 0.0).x), _21890), mix(float(_21435 <= textureLod(shadow_map, _21837 + _21861, 0.0).x), float(_21435 <= textureLod(shadow_map, _21837 + _21844, 0.0).x), _21890), _21822.y);
                                float mp_copy_21899 = _21899;
                                highp vec2 _21933 = clamp(_19796 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31359), _21801, _21805);
                                highp vec2 _21944 = (vec2(_21933.x, 1.0 - _21933.y) / _21801) - vec2(0.5);
                                highp vec2 _21946 = floor(_21944);
                                highp vec2 _21949 = _21944 - _21946;
                                highp vec2 _21954 = (_21946 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21964 = vec2((1.0 + _21954.x) * _21441, _21954.y);
                                highp float _22017 = _21949.x;
                                highp float _22026 = mix(mix(float(_21435 <= textureLod(shadow_map, _21964, 0.0).x), float(_21435 <= textureLod(shadow_map, _21964 + _21853, 0.0).x), _22017), mix(float(_21435 <= textureLod(shadow_map, _21964 + _21861, 0.0).x), float(_21435 <= textureLod(shadow_map, _21964 + _21844, 0.0).x), _22017), _21949.y);
                                float mp_copy_22026 = _22026;
                                highp vec2 _22060 = clamp(_19796 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31359), _21801, _21805);
                                highp vec2 _22071 = (vec2(_22060.x, 1.0 - _22060.y) / _21801) - vec2(0.5);
                                highp vec2 _22073 = floor(_22071);
                                highp vec2 _22076 = _22071 - _22073;
                                highp vec2 _22081 = (_22073 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _22091 = vec2((1.0 + _22081.x) * _21441, _22081.y);
                                highp float _22144 = _22076.x;
                                highp float _22153 = mix(mix(float(_21435 <= textureLod(shadow_map, _22091, 0.0).x), float(_21435 <= textureLod(shadow_map, _22091 + _21853, 0.0).x), _22144), mix(float(_21435 <= textureLod(shadow_map, _22091 + _21861, 0.0).x), float(_21435 <= textureLod(shadow_map, _22091 + _21844, 0.0).x), _22144), _22076.y);
                                float mp_copy_22153 = _22153;
                                highp vec2 _22187 = clamp(_19796 + (vec2(0.707099974155426025390625) * _31359), _21801, _21805);
                                highp vec2 _22198 = (vec2(_22187.x, 1.0 - _22187.y) / _21801) - vec2(0.5);
                                highp vec2 _22200 = floor(_22198);
                                highp vec2 _22203 = _22198 - _22200;
                                highp vec2 _22208 = (_22200 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _22218 = vec2((1.0 + _22208.x) * _21441, _22208.y);
                                highp float _22271 = _22203.x;
                                highp float _22280 = mix(mix(float(_21435 <= textureLod(shadow_map, _22218, 0.0).x), float(_21435 <= textureLod(shadow_map, _22218 + _21853, 0.0).x), _22271), mix(float(_21435 <= textureLod(shadow_map, _22218 + _21861, 0.0).x), float(_21435 <= textureLod(shadow_map, _22218 + _21844, 0.0).x), _22271), _22203.y);
                                float mp_copy_22280 = _22280;
                                _31366 = (((mp_copy_21899 + mp_copy_22026) + mp_copy_22153) + mp_copy_22280) * 0.25;
                            }
                            else
                            {
                                int _21576 = (_21449 > 0.5) ? 17 : 16;
                                float _31362 = 0.0;
                                _31362 = 0.0;
                                float _21604 = 0.0;
                                for (int _31352 = 0; _31352 < 17; _31362 = _21604, _31352++)
                                {
                                    if (_31352 >= _21576)
                                    {
                                        break;
                                    }
                                    vec2 _31353 = vec2(0.0);
                                    do
                                    {
                                        if (_31352 == 0)
                                        {
                                            _31353 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31352 == 1)
                                        {
                                            _31353 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31352 == 2)
                                        {
                                            _31353 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31352 == 3)
                                        {
                                            _31353 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31352 == 4)
                                        {
                                            _31353 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31352 == 5)
                                        {
                                            _31353 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31352 == 6)
                                        {
                                            _31353 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31352 == 7)
                                        {
                                            _31353 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31352 == 8)
                                        {
                                            _31353 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31352 == 9)
                                        {
                                            _31353 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31352 == 10)
                                        {
                                            _31353 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31352 == 11)
                                        {
                                            _31353 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31352 == 12)
                                        {
                                            _31353 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31352 == 13)
                                        {
                                            _31353 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31352 == 14)
                                        {
                                            _31353 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31352 == 15)
                                        {
                                            _31353 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31353 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31355 = vec2(0.0);
                                    do
                                    {
                                        if (_31352 < 3)
                                        {
                                            _31355 = vec2(float(_31352) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31352 < 6)
                                        {
                                            _31355 = vec2((float(_31352 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31352 < 11)
                                        {
                                            _31355 = vec2((float(_31352 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31352 < 14)
                                        {
                                            _31355 = vec2((float(_31352 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31355 = vec2(float(_31352 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _21593 = mix(_31353, _31355, vec2(_21449));
                                    float _22420 = _21593.x;
                                    float _22424 = _21593.y;
                                    highp vec2 _22450 = clamp(_19796 + (vec2((_22420 * _21462) - (_22424 * _21464), (_22420 * _21464) + (_22424 * _21462)) * _31359), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _22460 = vec2((1.0 + _22450.x) * _21441, _22450.y);
                                    _22460.y = 1.0 - _22450.y;
                                    highp float _22472 = float(_21435 <= textureLod(shadow_map, _22460, 0.0).x);
                                    float mp_copy_22472 = _22472;
                                    _21604 = _31362 + mp_copy_22472;
                                }
                                _31366 = _31362 / float(_21576);
                            }
                            bool _21617 = 1 == (_19656 - 1);
                            bool _21623 = false;
                            if (_21617)
                            {
                                _21623 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _21623 = _21617;
                            }
                            float _31367 = 0.0;
                            if (_21623)
                            {
                                highp vec2 _21630 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                                highp vec2 _21638 = smoothstep(vec2(0.0), _21630, _19796) * smoothstep(vec2(0.0), _21630, _21321);
                                _31367 = mix(1.0, _31366, _21638.x * _21638.y);
                            }
                            else
                            {
                                _31367 = _31366;
                            }
                            _31439 = _31378 + (_19856 * _31367);
                            _31399 = _31338 + _19856;
                        }
                        else
                        {
                            _31439 = _31378;
                            _31399 = _31338;
                        }
                        _31438 = _31439;
                        _31398 = _31399;
                    }
                    else
                    {
                        _31438 = _31378;
                        _31398 = _31338;
                    }
                    _31437 = _31438;
                    _31397 = _31398;
                }
                else
                {
                    _31437 = _31378;
                    _31397 = _31338;
                }
                float _31456 = 0.0;
                float _31496 = 0.0;
                if ((_31397 < 1.0) && (_19656 > 2))
                {
                    highp vec4 _19891 = frag_info.light_space_matrix[2] * vec4(_20128, 1.0);
                    highp vec3 _19897 = _19891.xyz / vec3(_19891.w);
                    highp vec2 _19900 = _19897.xy * 0.5;
                    highp vec2 _19902 = _19900 + vec2(0.5);
                    highp float _19909 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
                    highp float _19911 = _19902.x;
                    bool _19913 = _19911 < _19909;
                    bool _19922 = false;
                    if (!_19913)
                    {
                        _19922 = _19911 > (1.0 - _19909);
                    }
                    else
                    {
                        _19922 = _19913;
                    }
                    bool _19930 = false;
                    if (!_19922)
                    {
                        _19930 = _19902.y < _19909;
                    }
                    else
                    {
                        _19930 = _19922;
                    }
                    bool _19939 = false;
                    if (!_19930)
                    {
                        _19939 = _19902.y > (1.0 - _19909);
                    }
                    else
                    {
                        _19939 = _19930;
                    }
                    bool _19946 = false;
                    if (!_19939)
                    {
                        _19946 = _19897.z < 0.0;
                    }
                    else
                    {
                        _19946 = _19939;
                    }
                    bool _19953 = false;
                    if (!_19946)
                    {
                        _19953 = _19897.z > 1.0;
                    }
                    else
                    {
                        _19953 = _19946;
                    }
                    float _31457 = 0.0;
                    float _31497 = 0.0;
                    if (!_19953)
                    {
                        highp vec2 _22480 = vec2(_19909);
                        highp vec2 _22485 = vec2(_19909 + max(_19662, 9.9999997473787516355514526367188e-05));
                        highp vec2 _22493 = vec2(0.5) - _19900;
                        highp vec2 _22495 = smoothstep(_22480, _22485, _19902) * smoothstep(_22480, _22485, _22493);
                        float _31400 = 0.0;
                        if (_19662 > 0.0)
                        {
                            _31400 = _22495.x * _22495.y;
                        }
                        else
                        {
                            _31400 = 1.0;
                        }
                        float _19962 = min(_31400, 1.0 - _31397);
                        float _31458 = 0.0;
                        float _31498 = 0.0;
                        if (_19962 > 0.0)
                        {
                            highp float _22607 = _19897.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                            highp float _22613 = 1.0 / (float(_19656) + frag_info.spot_shadow_params.x);
                            highp float _22615 = frag_info.directional_light_direction.w;
                            float mp_copy_22615 = _22615;
                            float _22621 = step(0.5, mp_copy_22615) * (1.0 - step(1.5, mp_copy_22615));
                            highp float _22632 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _22621);
                            float mp_copy_22632 = _22632;
                            float _22634 = cos(mp_copy_22632);
                            float _22636 = sin(mp_copy_22632);
                            highp float _31418 = 0.0;
                            if ((_22615 > 1.5) && (_22615 < 2.5))
                            {
                                highp float _22655 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _22660 = max(_22655 * _22607, frag_info.shadow_texel_size);
                                float _31408 = 0.0;
                                highp float _31409 = 0.0;
                                _31409 = 0.0;
                                _31408 = 0.0;
                                highp float _22682 = 0.0;
                                float _22685 = 0.0;
                                for (int _31407 = 0; _31407 < 9; _31409 = _22682, _31408 = _22685, _31407++)
                                {
                                    vec2 _33812 = vec2(0.0);
                                    do
                                    {
                                        if (_31407 == 0)
                                        {
                                            _33812 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31407 == 1)
                                        {
                                            _33812 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31407 == 2)
                                        {
                                            _33812 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31407 == 3)
                                        {
                                            _33812 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31407 == 4)
                                        {
                                            _33812 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31407 == 5)
                                        {
                                            _33812 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31407 == 6)
                                        {
                                            _33812 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31407 == 7)
                                        {
                                            _33812 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31407 == 8)
                                        {
                                            _33812 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31407 == 9)
                                        {
                                            _33812 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31407 == 10)
                                        {
                                            _33812 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31407 == 11)
                                        {
                                            _33812 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31407 == 12)
                                        {
                                            _33812 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31407 == 13)
                                        {
                                            _33812 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31407 == 14)
                                        {
                                            _33812 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31407 == 15)
                                        {
                                            _33812 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33812 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _22927 = clamp(_19902 + (vec2((_33812.x * _22634) - (_33812.y * _22636), (_33812.x * _22636) + (_33812.y * _22634)) * _22660), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _22936 = _22927.y;
                                    highp vec2 _22937 = vec2((2.0 + _22927.x) * _22613, _22936);
                                    _22937.y = 1.0 - _22936;
                                    highp vec4 _22944 = textureLod(shadow_map, _22937, 0.0);
                                    highp float _22945 = _22944.x;
                                    highp float _22677 = step(_22945, _22607);
                                    float mp_copy_22677 = _22677;
                                    _22682 = _31409 + (_22945 * _22677);
                                    _22685 = _31408 + mp_copy_22677;
                                }
                                highp float _31410 = 0.0;
                                if (_31408 > 0.0)
                                {
                                    _31410 = _31409 / _31408;
                                }
                                else
                                {
                                    _31410 = _22607;
                                }
                                _31418 = clamp(_22655 * max(_22607 - _31410, 0.0), frag_info.shadow_texel_size, _19909);
                            }
                            else
                            {
                                _31418 = _19909;
                            }
                            float _31425 = 0.0;
                            if (_22615 > 2.5)
                            {
                                highp vec2 _22973 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _22977 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _22978 = clamp(_19902 + (vec2(-0.707099974155426025390625) * _31418), _22973, _22977);
                                highp vec2 _22989 = (vec2(_22978.x, 1.0 - _22978.y) / _22973) - vec2(0.5);
                                highp vec2 _22991 = floor(_22989);
                                highp vec2 _22994 = _22989 - _22991;
                                highp vec2 _22999 = (_22991 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23009 = vec2((2.0 + _22999.x) * _22613, _22999.y);
                                highp float _23013 = frag_info.shadow_texel_size * _22613;
                                highp vec2 _23016 = vec2(_23013, frag_info.shadow_texel_size);
                                highp vec2 _23025 = vec2(_23013, 0.0);
                                highp vec2 _23033 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _23062 = _22994.x;
                                highp float _23071 = mix(mix(float(_22607 <= textureLod(shadow_map, _23009, 0.0).x), float(_22607 <= textureLod(shadow_map, _23009 + _23025, 0.0).x), _23062), mix(float(_22607 <= textureLod(shadow_map, _23009 + _23033, 0.0).x), float(_22607 <= textureLod(shadow_map, _23009 + _23016, 0.0).x), _23062), _22994.y);
                                float mp_copy_23071 = _23071;
                                highp vec2 _23105 = clamp(_19902 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31418), _22973, _22977);
                                highp vec2 _23116 = (vec2(_23105.x, 1.0 - _23105.y) / _22973) - vec2(0.5);
                                highp vec2 _23118 = floor(_23116);
                                highp vec2 _23121 = _23116 - _23118;
                                highp vec2 _23126 = (_23118 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23136 = vec2((2.0 + _23126.x) * _22613, _23126.y);
                                highp float _23189 = _23121.x;
                                highp float _23198 = mix(mix(float(_22607 <= textureLod(shadow_map, _23136, 0.0).x), float(_22607 <= textureLod(shadow_map, _23136 + _23025, 0.0).x), _23189), mix(float(_22607 <= textureLod(shadow_map, _23136 + _23033, 0.0).x), float(_22607 <= textureLod(shadow_map, _23136 + _23016, 0.0).x), _23189), _23121.y);
                                float mp_copy_23198 = _23198;
                                highp vec2 _23232 = clamp(_19902 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31418), _22973, _22977);
                                highp vec2 _23243 = (vec2(_23232.x, 1.0 - _23232.y) / _22973) - vec2(0.5);
                                highp vec2 _23245 = floor(_23243);
                                highp vec2 _23248 = _23243 - _23245;
                                highp vec2 _23253 = (_23245 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23263 = vec2((2.0 + _23253.x) * _22613, _23253.y);
                                highp float _23316 = _23248.x;
                                highp float _23325 = mix(mix(float(_22607 <= textureLod(shadow_map, _23263, 0.0).x), float(_22607 <= textureLod(shadow_map, _23263 + _23025, 0.0).x), _23316), mix(float(_22607 <= textureLod(shadow_map, _23263 + _23033, 0.0).x), float(_22607 <= textureLod(shadow_map, _23263 + _23016, 0.0).x), _23316), _23248.y);
                                float mp_copy_23325 = _23325;
                                highp vec2 _23359 = clamp(_19902 + (vec2(0.707099974155426025390625) * _31418), _22973, _22977);
                                highp vec2 _23370 = (vec2(_23359.x, 1.0 - _23359.y) / _22973) - vec2(0.5);
                                highp vec2 _23372 = floor(_23370);
                                highp vec2 _23375 = _23370 - _23372;
                                highp vec2 _23380 = (_23372 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23390 = vec2((2.0 + _23380.x) * _22613, _23380.y);
                                highp float _23443 = _23375.x;
                                highp float _23452 = mix(mix(float(_22607 <= textureLod(shadow_map, _23390, 0.0).x), float(_22607 <= textureLod(shadow_map, _23390 + _23025, 0.0).x), _23443), mix(float(_22607 <= textureLod(shadow_map, _23390 + _23033, 0.0).x), float(_22607 <= textureLod(shadow_map, _23390 + _23016, 0.0).x), _23443), _23375.y);
                                float mp_copy_23452 = _23452;
                                _31425 = (((mp_copy_23071 + mp_copy_23198) + mp_copy_23325) + mp_copy_23452) * 0.25;
                            }
                            else
                            {
                                int _22748 = (_22621 > 0.5) ? 17 : 16;
                                float _31421 = 0.0;
                                _31421 = 0.0;
                                float _22776 = 0.0;
                                for (int _31411 = 0; _31411 < 17; _31421 = _22776, _31411++)
                                {
                                    if (_31411 >= _22748)
                                    {
                                        break;
                                    }
                                    vec2 _31412 = vec2(0.0);
                                    do
                                    {
                                        if (_31411 == 0)
                                        {
                                            _31412 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31411 == 1)
                                        {
                                            _31412 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31411 == 2)
                                        {
                                            _31412 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31411 == 3)
                                        {
                                            _31412 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31411 == 4)
                                        {
                                            _31412 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31411 == 5)
                                        {
                                            _31412 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31411 == 6)
                                        {
                                            _31412 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31411 == 7)
                                        {
                                            _31412 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31411 == 8)
                                        {
                                            _31412 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31411 == 9)
                                        {
                                            _31412 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31411 == 10)
                                        {
                                            _31412 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31411 == 11)
                                        {
                                            _31412 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31411 == 12)
                                        {
                                            _31412 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31411 == 13)
                                        {
                                            _31412 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31411 == 14)
                                        {
                                            _31412 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31411 == 15)
                                        {
                                            _31412 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31412 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31414 = vec2(0.0);
                                    do
                                    {
                                        if (_31411 < 3)
                                        {
                                            _31414 = vec2(float(_31411) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31411 < 6)
                                        {
                                            _31414 = vec2((float(_31411 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31411 < 11)
                                        {
                                            _31414 = vec2((float(_31411 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31411 < 14)
                                        {
                                            _31414 = vec2((float(_31411 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31414 = vec2(float(_31411 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _22765 = mix(_31412, _31414, vec2(_22621));
                                    float _23592 = _22765.x;
                                    float _23596 = _22765.y;
                                    highp vec2 _23622 = clamp(_19902 + (vec2((_23592 * _22634) - (_23596 * _22636), (_23592 * _22636) + (_23596 * _22634)) * _31418), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _23632 = vec2((2.0 + _23622.x) * _22613, _23622.y);
                                    _23632.y = 1.0 - _23622.y;
                                    highp float _23644 = float(_22607 <= textureLod(shadow_map, _23632, 0.0).x);
                                    float mp_copy_23644 = _23644;
                                    _22776 = _31421 + mp_copy_23644;
                                }
                                _31425 = _31421 / float(_22748);
                            }
                            bool _22789 = 2 == (_19656 - 1);
                            bool _22795 = false;
                            if (_22789)
                            {
                                _22795 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _22795 = _22789;
                            }
                            float _31426 = 0.0;
                            if (_22795)
                            {
                                highp vec2 _22802 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                                highp vec2 _22810 = smoothstep(vec2(0.0), _22802, _19902) * smoothstep(vec2(0.0), _22802, _22493);
                                _31426 = mix(1.0, _31425, _22810.x * _22810.y);
                            }
                            else
                            {
                                _31426 = _31425;
                            }
                            _31498 = _31437 + (_19962 * _31426);
                            _31458 = _31397 + _19962;
                        }
                        else
                        {
                            _31498 = _31437;
                            _31458 = _31397;
                        }
                        _31497 = _31498;
                        _31457 = _31458;
                    }
                    else
                    {
                        _31497 = _31437;
                        _31457 = _31397;
                    }
                    _31496 = _31497;
                    _31456 = _31457;
                }
                else
                {
                    _31496 = _31437;
                    _31456 = _31397;
                }
                float _31515 = 0.0;
                float _31518 = 0.0;
                if ((_31456 < 1.0) && (_19656 > 3))
                {
                    highp vec4 _19997 = frag_info.light_space_matrix[3] * vec4(_20128, 1.0);
                    highp vec3 _20003 = _19997.xyz / vec3(_19997.w);
                    highp vec2 _20006 = _20003.xy * 0.5;
                    highp vec2 _20008 = _20006 + vec2(0.5);
                    highp float _20015 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
                    highp float _20017 = _20008.x;
                    bool _20019 = _20017 < _20015;
                    bool _20028 = false;
                    if (!_20019)
                    {
                        _20028 = _20017 > (1.0 - _20015);
                    }
                    else
                    {
                        _20028 = _20019;
                    }
                    bool _20036 = false;
                    if (!_20028)
                    {
                        _20036 = _20008.y < _20015;
                    }
                    else
                    {
                        _20036 = _20028;
                    }
                    bool _20045 = false;
                    if (!_20036)
                    {
                        _20045 = _20008.y > (1.0 - _20015);
                    }
                    else
                    {
                        _20045 = _20036;
                    }
                    bool _20052 = false;
                    if (!_20045)
                    {
                        _20052 = _20003.z < 0.0;
                    }
                    else
                    {
                        _20052 = _20045;
                    }
                    bool _20059 = false;
                    if (!_20052)
                    {
                        _20059 = _20003.z > 1.0;
                    }
                    else
                    {
                        _20059 = _20052;
                    }
                    float _31516 = 0.0;
                    float _31519 = 0.0;
                    if (!_20059)
                    {
                        highp vec2 _23652 = vec2(_20015);
                        highp vec2 _23657 = vec2(_20015 + max(_19662, 9.9999997473787516355514526367188e-05));
                        highp vec2 _23665 = vec2(0.5) - _20006;
                        highp vec2 _23667 = smoothstep(_23652, _23657, _20008) * smoothstep(_23652, _23657, _23665);
                        float _31459 = 0.0;
                        if (_19662 > 0.0)
                        {
                            _31459 = _23667.x * _23667.y;
                        }
                        else
                        {
                            _31459 = 1.0;
                        }
                        float _20068 = min(_31459, 1.0 - _31456);
                        float _31517 = 0.0;
                        float _31520 = 0.0;
                        if (_20068 > 0.0)
                        {
                            highp float _23779 = _20003.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                            highp float _23785 = 1.0 / (float(_19656) + frag_info.spot_shadow_params.x);
                            highp float _23787 = frag_info.directional_light_direction.w;
                            float mp_copy_23787 = _23787;
                            float _23793 = step(0.5, mp_copy_23787) * (1.0 - step(1.5, mp_copy_23787));
                            highp float _23804 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _23793);
                            float mp_copy_23804 = _23804;
                            float _23806 = cos(mp_copy_23804);
                            float _23808 = sin(mp_copy_23804);
                            highp float _31477 = 0.0;
                            if ((_23787 > 1.5) && (_23787 < 2.5))
                            {
                                highp float _23827 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _23832 = max(_23827 * _23779, frag_info.shadow_texel_size);
                                float _31467 = 0.0;
                                highp float _31468 = 0.0;
                                _31468 = 0.0;
                                _31467 = 0.0;
                                highp float _23854 = 0.0;
                                float _23857 = 0.0;
                                for (int _31466 = 0; _31466 < 9; _31468 = _23854, _31467 = _23857, _31466++)
                                {
                                    vec2 _33808 = vec2(0.0);
                                    do
                                    {
                                        if (_31466 == 0)
                                        {
                                            _33808 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31466 == 1)
                                        {
                                            _33808 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31466 == 2)
                                        {
                                            _33808 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31466 == 3)
                                        {
                                            _33808 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31466 == 4)
                                        {
                                            _33808 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31466 == 5)
                                        {
                                            _33808 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31466 == 6)
                                        {
                                            _33808 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31466 == 7)
                                        {
                                            _33808 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31466 == 8)
                                        {
                                            _33808 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31466 == 9)
                                        {
                                            _33808 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31466 == 10)
                                        {
                                            _33808 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31466 == 11)
                                        {
                                            _33808 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31466 == 12)
                                        {
                                            _33808 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31466 == 13)
                                        {
                                            _33808 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31466 == 14)
                                        {
                                            _33808 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31466 == 15)
                                        {
                                            _33808 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33808 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _24099 = clamp(_20008 + (vec2((_33808.x * _23806) - (_33808.y * _23808), (_33808.x * _23808) + (_33808.y * _23806)) * _23832), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _24108 = _24099.y;
                                    highp vec2 _24109 = vec2((3.0 + _24099.x) * _23785, _24108);
                                    _24109.y = 1.0 - _24108;
                                    highp vec4 _24116 = textureLod(shadow_map, _24109, 0.0);
                                    highp float _24117 = _24116.x;
                                    highp float _23849 = step(_24117, _23779);
                                    float mp_copy_23849 = _23849;
                                    _23854 = _31468 + (_24117 * _23849);
                                    _23857 = _31467 + mp_copy_23849;
                                }
                                highp float _31469 = 0.0;
                                if (_31467 > 0.0)
                                {
                                    _31469 = _31468 / _31467;
                                }
                                else
                                {
                                    _31469 = _23779;
                                }
                                _31477 = clamp(_23827 * max(_23779 - _31469, 0.0), frag_info.shadow_texel_size, _20015);
                            }
                            else
                            {
                                _31477 = _20015;
                            }
                            float _31484 = 0.0;
                            if (_23787 > 2.5)
                            {
                                highp vec2 _24145 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _24149 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _24150 = clamp(_20008 + (vec2(-0.707099974155426025390625) * _31477), _24145, _24149);
                                highp vec2 _24161 = (vec2(_24150.x, 1.0 - _24150.y) / _24145) - vec2(0.5);
                                highp vec2 _24163 = floor(_24161);
                                highp vec2 _24166 = _24161 - _24163;
                                highp vec2 _24171 = (_24163 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24181 = vec2((3.0 + _24171.x) * _23785, _24171.y);
                                highp float _24185 = frag_info.shadow_texel_size * _23785;
                                highp vec2 _24188 = vec2(_24185, frag_info.shadow_texel_size);
                                highp vec2 _24197 = vec2(_24185, 0.0);
                                highp vec2 _24205 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _24234 = _24166.x;
                                highp float _24243 = mix(mix(float(_23779 <= textureLod(shadow_map, _24181, 0.0).x), float(_23779 <= textureLod(shadow_map, _24181 + _24197, 0.0).x), _24234), mix(float(_23779 <= textureLod(shadow_map, _24181 + _24205, 0.0).x), float(_23779 <= textureLod(shadow_map, _24181 + _24188, 0.0).x), _24234), _24166.y);
                                float mp_copy_24243 = _24243;
                                highp vec2 _24277 = clamp(_20008 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31477), _24145, _24149);
                                highp vec2 _24288 = (vec2(_24277.x, 1.0 - _24277.y) / _24145) - vec2(0.5);
                                highp vec2 _24290 = floor(_24288);
                                highp vec2 _24293 = _24288 - _24290;
                                highp vec2 _24298 = (_24290 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24308 = vec2((3.0 + _24298.x) * _23785, _24298.y);
                                highp float _24361 = _24293.x;
                                highp float _24370 = mix(mix(float(_23779 <= textureLod(shadow_map, _24308, 0.0).x), float(_23779 <= textureLod(shadow_map, _24308 + _24197, 0.0).x), _24361), mix(float(_23779 <= textureLod(shadow_map, _24308 + _24205, 0.0).x), float(_23779 <= textureLod(shadow_map, _24308 + _24188, 0.0).x), _24361), _24293.y);
                                float mp_copy_24370 = _24370;
                                highp vec2 _24404 = clamp(_20008 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31477), _24145, _24149);
                                highp vec2 _24415 = (vec2(_24404.x, 1.0 - _24404.y) / _24145) - vec2(0.5);
                                highp vec2 _24417 = floor(_24415);
                                highp vec2 _24420 = _24415 - _24417;
                                highp vec2 _24425 = (_24417 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24435 = vec2((3.0 + _24425.x) * _23785, _24425.y);
                                highp float _24488 = _24420.x;
                                highp float _24497 = mix(mix(float(_23779 <= textureLod(shadow_map, _24435, 0.0).x), float(_23779 <= textureLod(shadow_map, _24435 + _24197, 0.0).x), _24488), mix(float(_23779 <= textureLod(shadow_map, _24435 + _24205, 0.0).x), float(_23779 <= textureLod(shadow_map, _24435 + _24188, 0.0).x), _24488), _24420.y);
                                float mp_copy_24497 = _24497;
                                highp vec2 _24531 = clamp(_20008 + (vec2(0.707099974155426025390625) * _31477), _24145, _24149);
                                highp vec2 _24542 = (vec2(_24531.x, 1.0 - _24531.y) / _24145) - vec2(0.5);
                                highp vec2 _24544 = floor(_24542);
                                highp vec2 _24547 = _24542 - _24544;
                                highp vec2 _24552 = (_24544 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24562 = vec2((3.0 + _24552.x) * _23785, _24552.y);
                                highp float _24615 = _24547.x;
                                highp float _24624 = mix(mix(float(_23779 <= textureLod(shadow_map, _24562, 0.0).x), float(_23779 <= textureLod(shadow_map, _24562 + _24197, 0.0).x), _24615), mix(float(_23779 <= textureLod(shadow_map, _24562 + _24205, 0.0).x), float(_23779 <= textureLod(shadow_map, _24562 + _24188, 0.0).x), _24615), _24547.y);
                                float mp_copy_24624 = _24624;
                                _31484 = (((mp_copy_24243 + mp_copy_24370) + mp_copy_24497) + mp_copy_24624) * 0.25;
                            }
                            else
                            {
                                int _23920 = (_23793 > 0.5) ? 17 : 16;
                                float _31480 = 0.0;
                                _31480 = 0.0;
                                float _23948 = 0.0;
                                for (int _31470 = 0; _31470 < 17; _31480 = _23948, _31470++)
                                {
                                    if (_31470 >= _23920)
                                    {
                                        break;
                                    }
                                    vec2 _31471 = vec2(0.0);
                                    do
                                    {
                                        if (_31470 == 0)
                                        {
                                            _31471 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31470 == 1)
                                        {
                                            _31471 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31470 == 2)
                                        {
                                            _31471 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31470 == 3)
                                        {
                                            _31471 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31470 == 4)
                                        {
                                            _31471 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31470 == 5)
                                        {
                                            _31471 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31470 == 6)
                                        {
                                            _31471 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31470 == 7)
                                        {
                                            _31471 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31470 == 8)
                                        {
                                            _31471 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31470 == 9)
                                        {
                                            _31471 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31470 == 10)
                                        {
                                            _31471 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31470 == 11)
                                        {
                                            _31471 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31470 == 12)
                                        {
                                            _31471 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31470 == 13)
                                        {
                                            _31471 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31470 == 14)
                                        {
                                            _31471 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31470 == 15)
                                        {
                                            _31471 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31471 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31473 = vec2(0.0);
                                    do
                                    {
                                        if (_31470 < 3)
                                        {
                                            _31473 = vec2(float(_31470) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31470 < 6)
                                        {
                                            _31473 = vec2((float(_31470 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31470 < 11)
                                        {
                                            _31473 = vec2((float(_31470 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31470 < 14)
                                        {
                                            _31473 = vec2((float(_31470 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31473 = vec2(float(_31470 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _23937 = mix(_31471, _31473, vec2(_23793));
                                    float _24764 = _23937.x;
                                    float _24768 = _23937.y;
                                    highp vec2 _24794 = clamp(_20008 + (vec2((_24764 * _23806) - (_24768 * _23808), (_24764 * _23808) + (_24768 * _23806)) * _31477), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _24804 = vec2((3.0 + _24794.x) * _23785, _24794.y);
                                    _24804.y = 1.0 - _24794.y;
                                    highp float _24816 = float(_23779 <= textureLod(shadow_map, _24804, 0.0).x);
                                    float mp_copy_24816 = _24816;
                                    _23948 = _31480 + mp_copy_24816;
                                }
                                _31484 = _31480 / float(_23920);
                            }
                            bool _23961 = 3 == (_19656 - 1);
                            bool _23967 = false;
                            if (_23961)
                            {
                                _23967 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _23967 = _23961;
                            }
                            float _31485 = 0.0;
                            if (_23967)
                            {
                                highp vec2 _23974 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                                highp vec2 _23982 = smoothstep(vec2(0.0), _23974, _20008) * smoothstep(vec2(0.0), _23974, _23665);
                                _31485 = mix(1.0, _31484, _23982.x * _23982.y);
                            }
                            else
                            {
                                _31485 = _31484;
                            }
                            _31520 = _31456 + _20068;
                            _31517 = _31496 + (_20068 * _31485);
                        }
                        else
                        {
                            _31520 = _31456;
                            _31517 = _31496;
                        }
                        _31519 = _31520;
                        _31516 = _31517;
                    }
                    else
                    {
                        _31519 = _31456;
                        _31516 = _31496;
                    }
                    _31518 = _31519;
                    _31515 = _31516;
                }
                else
                {
                    _31518 = _31456;
                    _31515 = _31496;
                }
                _31521 = _31515 + (1.0 - _31518);
            }
            else
            {
                _31521 = 1.0;
            }
            bool _14284 = frag_info.ssao_lighting.w > 0.5;
            bool _14290 = false;
            if (_14284)
            {
                _14290 = frag_info.camera_up.w < 0.5;
            }
            else
            {
                _14290 = _14284;
            }
            float _31672 = 0.0;
            if (_14290)
            {
                _31672 = min(_31521, _31538.y);
            }
            else
            {
                _31672 = _31521;
            }
            float _14299 = _14262 * _31672;
            highp vec3 _14312 = ((((_14196 + (_14200 * ((vec3(1.0) - _14172) - _14196))) * _31092) * _31689) + (((_14172 * (_30900 * frag_info.environment_intensity)) * 1.0) * _31830)) * mix(1.0, _14299, frag_info.radiance_blend.y);
            highp vec3 _32087 = vec3(0.0);
            if (frag_info.camera_up.w > 0.5)
            {
                _32087 = _14312 + ((_31538.xyz * _14200) * _7316);
            }
            else
            {
                _32087 = _14312;
            }
            highp vec3 _32093 = vec3(0.0);
            if (_14249)
            {
                highp vec3 _31990 = vec3(0.0);
                highp vec3 _31991 = vec3(0.0);
                do
                {
                    float _24882 = max(dot(_30829, _31914), 0.0);
                    highp float hp_copy_24882 = _24882;
                    if (_24882 <= 0.0)
                    {
                        _31991 = vec3(0.0);
                        _31990 = vec3(0.0);
                        break;
                    }
                    float _24888 = max(_14069, 9.9999997473787516355514526367188e-05);
                    highp float hp_copy_24888 = _24888;
                    vec3 _24891 = _31914 + mp_copy_30882;
                    float _24894 = dot(_24891, _24891);
                    vec3 _31988 = vec3(0.0);
                    vec3 _31989 = vec3(0.0);
                    if (_24894 > 9.9999999392252902907785028219223e-09)
                    {
                        vec3 _24902 = _24891 * inversesqrt(_24894);
                        float _31987 = 0.0;
                        do
                        {
                            float _24959 = dot(_30829, _24902);
                            if (_24959 <= 0.0)
                            {
                                _31987 = 0.0;
                                break;
                            }
                            float _24966 = _30874 * _30874;
                            vec3 _24969 = cross(_30829, _24902);
                            float _24972 = _24959 * _24966;
                            float _24981 = _24966 / (dot(_24969, _24969) + (_24972 * _24972));
                            _31987 = min((_24981 * _24981) * 0.3183098733425140380859375, 65504.0);
                            break;
                        } while(false);
                        vec3 _25019 = _14065 + (_14182 * pow(clamp(1.0 - max(dot(_24902, _30882), 0.0), 0.0, 1.0), 5.0));
                        _31989 = (_25019 * min(_31987 * (0.5 / max(mix((2.0 * hp_copy_24882) * _24888, hp_copy_24882 + hp_copy_24888, hp_copy_30874 * hp_copy_30874), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                        _31988 = _25019;
                    }
                    else
                    {
                        _31989 = vec3(0.0);
                        _31988 = _14065;
                    }
                    _31991 = (_31989 * frag_info.directional_light_color.xyz) * _24882;
                    _31990 = (((((vec3(1.0) - _31988) * _14199) * _13970) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _24882;
                    break;
                } while(false);
                _32093 = (_31990 + _31991) * _14299;
            }
            else
            {
                _32093 = vec3(0.0);
            }
            highp vec2 _31992 = vec2(0.0);
            do
            {
                if (frag_info.punctual_dims.x < 0.5)
                {
                    _31992 = vec2(0.0);
                    break;
                }
                if (frag_info.froxel_grid.z > 0.5)
                {
                    highp vec3 _25055 = v_position - frag_info.camera_position.xyz;
                    highp float _25070 = dot(_25055, frag_info.camera_forward.xyz);
                    highp float _25076 = max(_25070, 9.9999997473787516355514526367188e-05);
                    highp vec2 _25179 = (vec3(dot(_25055, frag_info.camera_right.xyz), dot(_25055, frag_info.camera_up.xyz), _25076).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_25076, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
                    int _25147 = int(((((clamp(floor((log2(max(_25070 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_25179.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_25179.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5);
                    int _25192 = int(frag_info.punctual_dims.y + 0.5);
                    _31992 = vec2(texelFetch(punctual_index, ivec2(_25147 % _25192, _25147 / _25192), 0).xy);
                    break;
                }
                _31992 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
                break;
            } while(false);
            mediump int _14355 = int(_31992.x + 0.5);
            mediump int _14359 = int(_31992.y + 0.5);
            highp vec3 _32091 = vec3(0.0);
            _32091 = _32093;
            highp vec3 _34861 = vec3(0.0);
            for (int _31993 = 0; _31993 < _14359; _32091 = _34861, _31993++)
            {
                int _14368 = _14355 + _31993;
                int _25215 = int(frag_info.punctual_dims.y + 0.5);
                int _14371 = int(texelFetch(punctual_index, ivec2(_14368 % _25215, _14368 / _25215), 0).x + 0.5);
                ivec2 _25231 = ivec2(0, _14371);
                highp vec4 _25233 = texelFetch(punctual_lights, _25231, 0);
                highp vec4 _25241 = texelFetch(punctual_lights, ivec2(1, _14371), 0);
                highp float _14377 = _25233.w;
                highp vec3 _14379 = _25241.xyz;
                if (_14377 > 2.5)
                {
                    highp vec4 _25249 = texelFetch(punctual_lights, ivec2(2, _14371), 0);
                    highp vec4 _25257 = texelFetch(punctual_lights, ivec2(3, _14371), 0);
                    highp vec3 _14393 = _25249.xyz * (_25249.w * 0.5);
                    highp vec3 _14399 = _25257.xyz * (_25257.w * 0.5);
                    highp vec3 _14401 = _25233.xyz;
                    highp vec3 _14403 = _14401 - _14393;
                    highp vec3 _14405 = _14403 - _14399;
                    highp vec3 _14409 = _14401 + _14393;
                    highp vec3 _14411 = _14409 - _14399;
                    highp vec3 _14423 = _14403 + _14399;
                    highp vec3 _14427 = _14401 - v_position;
                    highp float _14433 = _25241.w;
                    highp float _14437 = (dot(_14427, _14427) * _14433) * _14433;
                    highp float _14442 = clamp(1.0 - (_14437 * _14437), 0.0, 1.0);
                    float mp_copy_14442 = _14442;
                    vec2 _25264 = (clamp(vec2(_30874, sqrt(1.0 - _14069)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
                    float _25266 = _25264.x;
                    float _25271 = _25264.y;
                    vec4 _14466 = textureLod(brdf_lut, vec2((_25266 + 1.0) * 0.3333333432674407958984375, _25271), 0.0);
                    vec4 _14470 = textureLod(brdf_lut, vec2((_25266 + 2.0) * 0.3333333432674407958984375, _25271), 0.0);
                    vec3 _25314 = normalize(mp_copy_30882 - (_30829 * _14068));
                    mat3 _25336 = transpose(mat3(_25314, -cross(_30829, _25314), _30829));
                    mat3 _25337 = mat3(vec3(_14466.x, 0.0, _14466.y), vec3(0.0, 1.0, 0.0), vec3(_14466.z, 0.0, _14466.w)) * _25336;
                    highp vec3 _25341 = _14405 - v_position;
                    highp vec3 _25343 = normalize(_25337 * _25341);
                    vec3 mp_copy_25343 = _25343;
                    highp vec3 _25347 = _14411 - v_position;
                    highp vec3 _25349 = normalize(_25337 * _25347);
                    vec3 mp_copy_25349 = _25349;
                    highp vec3 _25353 = (_14409 + _14399) - v_position;
                    highp vec3 _25355 = normalize(_25337 * _25353);
                    vec3 mp_copy_25355 = _25355;
                    highp vec3 _25359 = _14423 - v_position;
                    highp vec3 _25361 = normalize(_25337 * _25359);
                    vec3 mp_copy_25361 = _25361;
                    float _25390 = dot(_25343, _25349);
                    float _25392 = abs(_25390);
                    float _25406 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25392)) * _25392)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25392) * _25392));
                    float _33748 = 0.0;
                    if (_25390 > 0.0)
                    {
                        _33748 = _25406;
                    }
                    else
                    {
                        _33748 = (0.5 * inversesqrt(max(1.0 - (_25390 * _25390), 1.0000000116860974230803549289703e-07))) - _25406;
                    }
                    float _25439 = dot(_25349, _25355);
                    float _25441 = abs(_25439);
                    float _25455 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25441)) * _25441)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25441) * _25441));
                    float _33749 = 0.0;
                    if (_25439 > 0.0)
                    {
                        _33749 = _25455;
                    }
                    else
                    {
                        _33749 = (0.5 * inversesqrt(max(1.0 - (_25439 * _25439), 1.0000000116860974230803549289703e-07))) - _25455;
                    }
                    float _25488 = dot(_25355, _25361);
                    float _25490 = abs(_25488);
                    float _25504 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25490)) * _25490)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25490) * _25490));
                    float _33750 = 0.0;
                    if (_25488 > 0.0)
                    {
                        _33750 = _25504;
                    }
                    else
                    {
                        _33750 = (0.5 * inversesqrt(max(1.0 - (_25488 * _25488), 1.0000000116860974230803549289703e-07))) - _25504;
                    }
                    float _25537 = dot(_25361, _25343);
                    float _25539 = abs(_25537);
                    float _25553 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25539)) * _25539)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25539) * _25539));
                    float _33751 = 0.0;
                    if (_25537 > 0.0)
                    {
                        _33751 = _25553;
                    }
                    else
                    {
                        _33751 = (0.5 * inversesqrt(max(1.0 - (_25537 * _25537), 1.0000000116860974230803549289703e-07))) - _25553;
                    }
                    vec3 _25376 = (((cross(mp_copy_25343, mp_copy_25349) * _33748) + (cross(mp_copy_25349, mp_copy_25355) * _33749)) + (cross(mp_copy_25355, mp_copy_25361) * _33750)) + (cross(mp_copy_25361, mp_copy_25343) * _33751);
                    float _25579 = length(_25376);
                    mat3 _25639 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _25336;
                    highp vec3 _25645 = normalize(_25639 * _25341);
                    vec3 mp_copy_25645 = _25645;
                    highp vec3 _25651 = normalize(_25639 * _25347);
                    vec3 mp_copy_25651 = _25651;
                    highp vec3 _25657 = normalize(_25639 * _25353);
                    vec3 mp_copy_25657 = _25657;
                    highp vec3 _25663 = normalize(_25639 * _25359);
                    vec3 mp_copy_25663 = _25663;
                    float _25692 = dot(_25645, _25651);
                    float _25694 = abs(_25692);
                    float _25708 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25694)) * _25694)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25694) * _25694));
                    float _33752 = 0.0;
                    if (_25692 > 0.0)
                    {
                        _33752 = _25708;
                    }
                    else
                    {
                        _33752 = (0.5 * inversesqrt(max(1.0 - (_25692 * _25692), 1.0000000116860974230803549289703e-07))) - _25708;
                    }
                    float _25741 = dot(_25651, _25657);
                    float _25743 = abs(_25741);
                    float _25757 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25743)) * _25743)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25743) * _25743));
                    float _33753 = 0.0;
                    if (_25741 > 0.0)
                    {
                        _33753 = _25757;
                    }
                    else
                    {
                        _33753 = (0.5 * inversesqrt(max(1.0 - (_25741 * _25741), 1.0000000116860974230803549289703e-07))) - _25757;
                    }
                    float _25790 = dot(_25657, _25663);
                    float _25792 = abs(_25790);
                    float _25806 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25792)) * _25792)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25792) * _25792));
                    float _33754 = 0.0;
                    if (_25790 > 0.0)
                    {
                        _33754 = _25806;
                    }
                    else
                    {
                        _33754 = (0.5 * inversesqrt(max(1.0 - (_25790 * _25790), 1.0000000116860974230803549289703e-07))) - _25806;
                    }
                    float _25839 = dot(_25663, _25645);
                    float _25841 = abs(_25839);
                    float _25855 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25841)) * _25841)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25841) * _25841));
                    float _33755 = 0.0;
                    if (_25839 > 0.0)
                    {
                        _33755 = _25855;
                    }
                    else
                    {
                        _33755 = (0.5 * inversesqrt(max(1.0 - (_25839 * _25839), 1.0000000116860974230803549289703e-07))) - _25855;
                    }
                    vec3 _25678 = (((cross(mp_copy_25645, mp_copy_25651) * _33752) + (cross(mp_copy_25651, mp_copy_25657) * _33753)) + (cross(mp_copy_25657, mp_copy_25663) * _33754)) + (cross(mp_copy_25663, mp_copy_25645) * _33755);
                    float _25881 = length(_25678);
                    _34861 = _32091 + (((_14379 * (mp_copy_14442 * mp_copy_14442)) * step(0.0, dot(cross(_14411 - _14405, _14423 - _14405), v_position - _14405))) * (((((_14065 * _14470.x) + (_14182 * _14470.y)) * max(((_25579 * _25579) + _25376.z) / (_25579 + 1.0), 0.0)) * 1.0) + (_14200 * max(((_25881 * _25881) + _25678.z) / (_25881 + 1.0), 0.0))));
                }
                else
                {
                    highp float hp_copy_33692 = 0.0;
                    vec3 _33665 = vec3(0.0);
                    highp vec3 _33688 = vec3(0.0);
                    float _33692 = 0.0;
                    if (_14377 < 0.5)
                    {
                        _33692 = _30874;
                        _33688 = _14379;
                        _33665 = -normalize(texelFetch(punctual_lights, ivec2(2, _14371), 0).xyz);
                    }
                    else
                    {
                        highp vec3 _14557 = _25233.xyz - v_position;
                        highp float _14560 = dot(_14557, _14557);
                        highp float _14564 = inversesqrt(max(_14560, 9.9999999392252902907785028219223e-09));
                        highp vec3 _14565 = _14557 * _14564;
                        vec3 mp_copy_14565 = _14565;
                        highp float _14567 = _25241.w;
                        highp float _14572 = (_14560 * _14567) * _14567;
                        highp float _14577 = clamp(1.0 - (_14572 * _14572), 0.0, 1.0);
                        float mp_copy_14577 = _14577;
                        highp vec4 _25907 = texelFetch(punctual_lights, ivec2(3, _14371), 0);
                        highp float _14581 = _25907.w;
                        float _33696 = 0.0;
                        if (_14581 > 0.0)
                        {
                            highp float _14608 = (_30874 * _30874) + ((_14581 * 0.5) * _14564);
                            float mp_copy_14608 = _14608;
                            _33696 = sqrt(min(mp_copy_14608, 1.0));
                        }
                        else
                        {
                            _33696 = _30874;
                        }
                        highp vec3 _14615 = _14379 * ((mp_copy_14577 * mp_copy_14577) / max(pow(max(_14560, _14581 * _14581), _25907.z * 0.5), 9.9999997473787516355514526367188e-05));
                        highp vec3 _33689 = vec3(0.0);
                        if (_14377 > 1.5)
                        {
                            highp vec4 _25915 = texelFetch(punctual_lights, ivec2(2, _14371), 0);
                            highp float _14634 = clamp((dot(normalize(_25915.xyz), -mp_copy_14565) * _25915.w) + _25907.x, 0.0, 1.0);
                            float mp_copy_14634 = _14634;
                            highp vec3 _14639 = _14615 * (mp_copy_14634 * mp_copy_14634);
                            highp float _14641 = _25907.y;
                            bool _14642 = _14641 > (-0.5);
                            bool _14648 = false;
                            if (_14642)
                            {
                                _14648 = frag_info.spot_shadow_params.x > 0.5;
                            }
                            else
                            {
                                _14648 = _14642;
                            }
                            highp vec3 _33690 = vec3(0.0);
                            if (_14648)
                            {
                                float _33656 = 0.0;
                                do
                                {
                                    highp vec4 _26000 = mat4(texelFetch(punctual_lights, ivec2(4, _14371), 0), texelFetch(punctual_lights, ivec2(5, _14371), 0), texelFetch(punctual_lights, ivec2(6, _14371), 0), texelFetch(punctual_lights, ivec2(7, _14371), 0)) * vec4(v_position + (_7154 * frag_info.spot_shadow_params.z), 1.0);
                                    highp float _26002 = _26000.w;
                                    if (_26002 <= 0.0)
                                    {
                                        _33656 = 1.0;
                                        break;
                                    }
                                    highp vec3 _26011 = _26000.xyz / vec3(_26002);
                                    highp vec2 _26016 = (_26011.xy * 0.5) + vec2(0.5);
                                    highp float _26018 = _26016.x;
                                    bool _26019 = _26018 < 0.0;
                                    bool _26026 = false;
                                    if (!_26019)
                                    {
                                        _26026 = _26018 > 1.0;
                                    }
                                    else
                                    {
                                        _26026 = _26019;
                                    }
                                    bool _26033 = false;
                                    if (!_26026)
                                    {
                                        _26033 = _26016.y < 0.0;
                                    }
                                    else
                                    {
                                        _26033 = _26026;
                                    }
                                    bool _26040 = false;
                                    if (!_26033)
                                    {
                                        _26040 = _26016.y > 1.0;
                                    }
                                    else
                                    {
                                        _26040 = _26033;
                                    }
                                    bool _26047 = false;
                                    if (!_26040)
                                    {
                                        _26047 = _26011.z < 0.0;
                                    }
                                    else
                                    {
                                        _26047 = _26040;
                                    }
                                    bool _26054 = false;
                                    if (!_26047)
                                    {
                                        _26054 = _26011.z > 1.0;
                                    }
                                    else
                                    {
                                        _26054 = _26047;
                                    }
                                    if (_26054)
                                    {
                                        _33656 = 1.0;
                                        break;
                                    }
                                    highp float _26061 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                    highp float _26066 = frag_info.shadow_cascade_count + float(int(_14641 + 0.5));
                                    highp float _26071 = _26011.z - frag_info.spot_shadow_params.y;
                                    highp float _26074 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                                    highp float _26087 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                    float _33655 = 0.0;
                                    _33655 = float(_26071 <= textureLod(shadow_map, vec2((_26066 + clamp(_26018, 0.0, 1.0)) / _26061, 1.0 - clamp(_26016.y, 0.0, 1.0)), 0.0).x);
                                    for (int _33654 = 0; _33654 < 8; )
                                    {
                                        highp float _26097 = _26087 + (float(_33654) * 0.785398185253143310546875);
                                        float mp_copy_26097 = _26097;
                                        highp vec2 _26107 = _26016 + (vec2(cos(mp_copy_26097), sin(mp_copy_26097)) * _26074);
                                        highp float _26197 = float(_26071 <= textureLod(shadow_map, vec2((_26066 + clamp(_26107.x, 0.0, 1.0)) / _26061, 1.0 - clamp(_26107.y, 0.0, 1.0)), 0.0).x);
                                        float mp_copy_26197 = _26197;
                                        _33655 += mp_copy_26197;
                                        _33654++;
                                        continue;
                                    }
                                    _33656 = _33655 * 0.111111111938953399658203125;
                                    break;
                                } while(false);
                                _33690 = _14639 * _33656;
                            }
                            else
                            {
                                _33690 = _14639;
                            }
                            _33689 = _33690;
                        }
                        else
                        {
                            bool _14664 = _14377 > 0.5;
                            bool _14670 = false;
                            if (_14664)
                            {
                                _14670 = _25907.y > (-0.5);
                            }
                            else
                            {
                                _14670 = _14664;
                            }
                            bool _14676 = false;
                            if (_14670)
                            {
                                _14676 = frag_info.spot_shadow_params.x > 0.5;
                            }
                            else
                            {
                                _14676 = _14670;
                            }
                            highp vec3 _33691 = vec3(0.0);
                            if (_14676)
                            {
                                float _33641 = 0.0;
                                do
                                {
                                    highp vec4 _26501 = texelFetch(punctual_lights, ivec2(4, _14371), 0);
                                    highp vec4 _26509 = texelFetch(punctual_lights, ivec2(5, _14371), 0);
                                    highp vec3 _26269 = (v_position + (_7154 * _26501.z)) - texelFetch(punctual_lights, _25231, 0).xyz;
                                    highp vec3 _26271 = abs(_26269);
                                    highp float _26273 = _26271.x;
                                    highp float _26275 = _26271.y;
                                    bool _26276 = _26273 >= _26275;
                                    bool _26284 = false;
                                    if (_26276)
                                    {
                                        _26284 = _26273 >= _26271.z;
                                    }
                                    else
                                    {
                                        _26284 = _26276;
                                    }
                                    highp vec3 _33631 = vec3(0.0);
                                    float _33633 = 0.0;
                                    if (_26284)
                                    {
                                        highp float _26287 = _26269.x;
                                        bool _26288 = _26287 >= 0.0;
                                        highp vec3 _33630 = vec3(0.0);
                                        if (_26288)
                                        {
                                            _33630 = vec3(-_26269.z, _26269.y, _26287);
                                        }
                                        else
                                        {
                                            _33630 = vec3(_26269.zy, -_26287);
                                        }
                                        _33633 = _26288 ? 0.0 : 1.0;
                                        _33631 = _33630;
                                    }
                                    else
                                    {
                                        highp vec3 _33632 = vec3(0.0);
                                        float _33635 = 0.0;
                                        if (_26275 >= _26271.z)
                                        {
                                            highp float _26321 = _26269.y;
                                            bool _26322 = _26321 >= 0.0;
                                            highp vec3 _33629 = vec3(0.0);
                                            if (_26322)
                                            {
                                                _33629 = vec3(-_26269.x, _26269.z, _26321);
                                            }
                                            else
                                            {
                                                _33629 = vec3(_26269.xz, -_26321);
                                            }
                                            _33635 = _26322 ? 2.0 : 3.0;
                                            _33632 = _33629;
                                        }
                                        else
                                        {
                                            highp float _26349 = _26269.z;
                                            bool _26350 = _26349 >= 0.0;
                                            highp vec3 _33628 = vec3(0.0);
                                            if (_26350)
                                            {
                                                _33628 = _26269;
                                            }
                                            else
                                            {
                                                _33628 = vec3(-_26269.x, _26269.y, -_26349);
                                            }
                                            _33635 = _26350 ? 4.0 : 5.0;
                                            _33632 = _33628;
                                        }
                                        _33633 = _33635;
                                        _33631 = _33632;
                                    }
                                    if (_33631.z <= 0.0)
                                    {
                                        _33641 = 1.0;
                                        break;
                                    }
                                    highp vec2 _26390 = ((_33631.xy / vec2(_33631.z)) * 0.5) + vec2(0.5);
                                    highp float _26401 = (_26501.x - (_26501.y / _33631.z)) - _26509.x;
                                    if ((_26401 < 0.0) || (_26401 > 1.0))
                                    {
                                        _33641 = 1.0;
                                        break;
                                    }
                                    highp float hp_copy_33638 = 0.0;
                                    highp float _26413 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                    bool _26419 = _33633 >= 4.0;
                                    highp float _26421 = (frag_info.shadow_cascade_count + _25907.y) + float(_26419);
                                    float _33638 = 0.0;
                                    if (_26419)
                                    {
                                        _33638 = _33633 - 4.0;
                                    }
                                    else
                                    {
                                        _33638 = _33633;
                                    }
                                    hp_copy_33638 = _33638;
                                    highp float _26438 = _26509.y * 0.5;
                                    highp float _26441 = _26501.w * 0.0040000001899898052215576171875;
                                    highp vec2 _26525 = vec2(_26438);
                                    highp vec2 _26528 = vec2(1.0 - _26438);
                                    highp vec2 _26534 = vec2(mod(hp_copy_33638, 2.0), 1.0 - floor(hp_copy_33638 * 0.5)) * 0.5;
                                    highp vec2 _26537 = _26534 + (clamp(_26390, _26525, _26528) * 0.5);
                                    highp float _26457 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                    float _33640 = 0.0;
                                    _33640 = float(_26401 <= textureLod(shadow_map, vec2((_26421 + _26537.x) / _26413, 1.0 - _26537.y), 0.0).x);
                                    for (int _33639 = 0; _33639 < 8; )
                                    {
                                        highp float _26467 = _26457 + (float(_33639) * 0.785398185253143310546875);
                                        float mp_copy_26467 = _26467;
                                        highp vec2 _26574 = _26534 + (clamp(_26390 + (vec2(cos(mp_copy_26467), sin(mp_copy_26467)) * _26441), _26525, _26528) * 0.5);
                                        highp float _26591 = float(_26401 <= textureLod(shadow_map, vec2((_26421 + _26574.x) / _26413, 1.0 - _26574.y), 0.0).x);
                                        float mp_copy_26591 = _26591;
                                        _33640 += mp_copy_26591;
                                        _33639++;
                                        continue;
                                    }
                                    _33641 = _33640 * 0.111111111938953399658203125;
                                    break;
                                } while(false);
                                _33691 = _14615 * _33641;
                            }
                            else
                            {
                                _33691 = _14615;
                            }
                            _33689 = _33691;
                        }
                        _33692 = _33696;
                        _33688 = _33689;
                        _33665 = _14565;
                    }
                    hp_copy_33692 = _33692;
                    highp vec3 _33719 = vec3(0.0);
                    highp vec3 _33720 = vec3(0.0);
                    do
                    {
                        float _26657 = max(dot(_30829, _33665), 0.0);
                        highp float hp_copy_26657 = _26657;
                        if (_26657 <= 0.0)
                        {
                            _33720 = vec3(0.0);
                            _33719 = vec3(0.0);
                            break;
                        }
                        float _26663 = max(_14069, 9.9999997473787516355514526367188e-05);
                        highp float hp_copy_26663 = _26663;
                        vec3 _26666 = _33665 + mp_copy_30882;
                        float _26669 = dot(_26666, _26666);
                        vec3 _33717 = vec3(0.0);
                        vec3 _33718 = vec3(0.0);
                        if (_26669 > 9.9999999392252902907785028219223e-09)
                        {
                            vec3 _26677 = _26666 * inversesqrt(_26669);
                            float _33716 = 0.0;
                            do
                            {
                                float _26734 = dot(_30829, _26677);
                                if (_26734 <= 0.0)
                                {
                                    _33716 = 0.0;
                                    break;
                                }
                                float _26741 = _33692 * _33692;
                                vec3 _26744 = cross(_30829, _26677);
                                float _26747 = _26734 * _26741;
                                float _26756 = _26741 / (dot(_26744, _26744) + (_26747 * _26747));
                                _33716 = min((_26756 * _26756) * 0.3183098733425140380859375, 65504.0);
                                break;
                            } while(false);
                            vec3 _26794 = _14065 + (_14182 * pow(clamp(1.0 - max(dot(_26677, _30882), 0.0), 0.0, 1.0), 5.0));
                            _33718 = (_26794 * min(_33716 * (0.5 / max(mix((2.0 * hp_copy_26657) * _26663, hp_copy_26657 + hp_copy_26663, hp_copy_33692 * hp_copy_33692), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                            _33717 = _26794;
                        }
                        else
                        {
                            _33718 = vec3(0.0);
                            _33717 = _14065;
                        }
                        _33720 = (_33718 * _33688) * _26657;
                        _33719 = (((((vec3(1.0) - _33717) * _14199) * _13970) * 0.3183098733425140380859375) * _33688) * _26657;
                        break;
                    } while(false);
                    _34861 = _32091 + (_33719 + _33720);
                }
            }
            bool _14733 = _FogInfo.params0.y > 0.5;
            bool _14739 = false;
            if (_14733)
            {
                _14739 = _FogInfo.params0.w > 0.0;
            }
            else
            {
                _14739 = _14733;
            }
            highp vec3 _32098 = vec3(0.0);
            if (_14739)
            {
                vec3 mp_copy_32094 = vec3(0.0);
                highp vec3 _32094 = vec3(0.0);
                if (_14906)
                {
                    _32094 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _32094 = normalize(v_viewvector);
                }
                mp_copy_32094 = _32094;
                vec3 _14744 = _14090 * (-mp_copy_32094);
                vec3 _32095 = vec3(0.0);
                do
                {
                    if (_15220)
                    {
                        vec2 _26916 = vec2(atan(_14744.z, _14744.x), asin(clamp(_14744.y, -1.0, 1.0)));
                        highp vec2 hp_copy_26916 = _26916;
                        _32095 = textureLod(prefiltered_radiance, (hp_copy_26916 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                        break;
                    }
                    vec2 _26935 = vec2(atan(_14744.z, _14744.x), asin(clamp(_14744.y, -1.0, 1.0)));
                    highp vec2 hp_copy_26935 = _26935;
                    highp vec2 _26940 = (hp_copy_26935 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _26847 = clamp(_26940.y, 0.00390625, 0.99609375);
                    float _26853 = floor(0.0);
                    highp float _26872 = _26940.x;
                    _32095 = mix(texture(prefiltered_radiance, vec2(_26872, (_26853 + _26847) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_26872, (min(_26853 + 1.0, 7.0) + _26847) * 0.125)).xyz, vec3(-_26853));
                    break;
                } while(false);
                highp vec3 _32097 = vec3(0.0);
                if (_14113)
                {
                    vec3 _32096 = vec3(0.0);
                    do
                    {
                        if (_15220)
                        {
                            vec2 _27045 = vec2(atan(_14744.z, _14744.x), asin(clamp(_14744.y, -1.0, 1.0)));
                            highp vec2 hp_copy_27045 = _27045;
                            _32096 = textureLod(prefiltered_radiance_b, (hp_copy_27045 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                            break;
                        }
                        vec2 _27064 = vec2(atan(_14744.z, _14744.x), asin(clamp(_14744.y, -1.0, 1.0)));
                        highp vec2 hp_copy_27064 = _27064;
                        highp vec2 _27069 = (hp_copy_27064 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                        highp float _26976 = clamp(_27069.y, 0.00390625, 0.99609375);
                        float _26982 = floor(0.0);
                        highp float _27001 = _27069.x;
                        _32096 = mix(texture(prefiltered_radiance_b, vec2(_27001, (_26982 + _26976) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_27001, (min(_26982 + 1.0, 7.0) + _26976) * 0.125)).xyz, vec3(-_26982));
                        break;
                    } while(false);
                    _32097 = mix(_32095, _32096, vec3(frag_info.radiance_blend.x));
                }
                else
                {
                    _32097 = _32095;
                }
                _32098 = _32097 * frag_info.environment_intensity;
            }
            else
            {
                _32098 = _FogInfo.color.xyz;
            }
            highp vec4 _14768 = vec4(min((_32087 + (_32091 * mix(1.0, _31162, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7340, vec3(65504.0)), 1.0) * _35252;
            highp vec4 _32113 = vec4(0.0);
            do
            {
                if (_FogInfo.params0.y < 0.5)
                {
                    _32113 = _14768;
                    break;
                }
                int _27113 = int(_FogInfo.params0.x + 0.5);
                if (_27113 == 0)
                {
                    _32113 = _14768;
                    break;
                }
                highp float _32100 = 0.0;
                if (_14906)
                {
                    _32100 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
                }
                else
                {
                    _32100 = length(v_viewvector);
                }
                if ((_FogInfo.params1.w > 0.0) && (_32100 > _FogInfo.params1.w))
                {
                    _32113 = _14768;
                    break;
                }
                float _32104 = 0.0;
                if (_27113 == 1)
                {
                    _32104 = clamp((_32100 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
                }
                else
                {
                    float _32105 = 0.0;
                    if (_27113 == 2)
                    {
                        highp float _32103 = 0.0;
                        if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                        {
                            highp vec3 _32101 = vec3(0.0);
                            if (_14906)
                            {
                                _32101 = v_position - (view_info.camera_forward.xyz * _32100);
                            }
                            else
                            {
                                _32101 = v_position + v_viewvector;
                            }
                            highp float _27194 = -_FogInfo.params2.y;
                            highp float _27201 = _FogInfo.params1.x * exp(_27194 * (_32101.y - _FogInfo.params2.x));
                            highp float _27218 = _FogInfo.params2.y * (v_position.y - _32101.y);
                            highp float _32102 = 0.0;
                            if (abs(_27218) > 0.00124999997206032276153564453125)
                            {
                                _32102 = (_27201 - (_FogInfo.params1.x * exp(_27194 * (v_position.y - _FogInfo.params2.x)))) / _27218;
                            }
                            else
                            {
                                _32102 = _27201;
                            }
                            _32103 = _32102 * max(_32100 - _FogInfo.params1.y, 0.0);
                        }
                        else
                        {
                            _32103 = _FogInfo.params1.x * max(_32100 - _FogInfo.params1.y, 0.0);
                        }
                        _32105 = 1.0 - exp(-_32103);
                    }
                    else
                    {
                        highp float _27256 = _FogInfo.params1.x * max(_32100 - _FogInfo.params1.y, 0.0);
                        _32105 = 1.0 - exp((-_27256) * _27256);
                    }
                    _32104 = _32105;
                }
                highp float _27268 = min(_32104, _FogInfo.params0.z);
                if (_27268 <= 0.0)
                {
                    _32113 = _14768;
                    break;
                }
                highp vec3 _27281 = mix(_FogInfo.color.xyz, _32098, vec3(_FogInfo.params0.w));
                bool _27284 = _FogInfo.sun.w > 0.5;
                bool _27290 = false;
                if (_27284)
                {
                    _27290 = _FogInfo.params2.z > 0.0;
                }
                else
                {
                    _27290 = _27284;
                }
                vec3 _32109 = vec3(0.0);
                if (_27290)
                {
                    vec3 mp_copy_32106 = vec3(0.0);
                    highp vec3 _32106 = vec3(0.0);
                    if (_14906)
                    {
                        _32106 = -view_info.camera_forward.xyz;
                    }
                    else
                    {
                        _32106 = normalize(v_viewvector);
                    }
                    mp_copy_32106 = _32106;
                    highp float _27306 = pow(max(dot(-mp_copy_32106, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                    float mp_copy_27306 = _27306;
                    _32109 = _27281 + ((_FogInfo.sun.xyz * mp_copy_27306) * _FogInfo.params2.z);
                }
                else
                {
                    _32109 = _27281;
                }
                highp float _27319 = _14768.w;
                float mp_copy_27319 = _27319;
                _32113 = vec4(mix(_14768.xyz, _32109 * mp_copy_27319, vec3(_27268)), _27319);
                break;
            } while(false);
            vec4 _33626 = vec4(0.0);
            if (_30865 > 1.5)
            {
                vec4 _33625 = vec4(0.0);
                do
                {
                    if (debug_view_info.view.x < 20.0)
                    {
                        vec3 _33611 = vec3(0.0);
                        if (debug_view_info.view.x == 1.0)
                        {
                            float _27772 = length(_7154);
                            vec3 _33609 = vec3(0.0);
                            if (_27772 > 9.9999999747524270787835121154785e-07)
                            {
                                _33609 = _7154 / vec3(_27772);
                            }
                            else
                            {
                                _33609 = vec3(0.0);
                            }
                            _33611 = ((_33609 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _33612 = vec3(0.0);
                            if (debug_view_info.view.x == 2.0)
                            {
                                float _27795 = length(_30829);
                                vec3 _33607 = vec3(0.0);
                                if (_27795 > 9.9999999747524270787835121154785e-07)
                                {
                                    _33607 = _30829 / vec3(_27795);
                                }
                                else
                                {
                                    _33607 = vec3(0.0);
                                }
                                _33612 = ((_33607 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _33613 = vec3(0.0);
                                if (debug_view_info.view.x == 3.0)
                                {
                                    float _27818 = length(v_tangent.xyz);
                                    vec3 _33605 = vec3(0.0);
                                    if (_27818 > 9.9999999747524270787835121154785e-07)
                                    {
                                        _33605 = v_tangent.xyz / vec3(_27818);
                                    }
                                    else
                                    {
                                        _33605 = vec3(0.0);
                                    }
                                    _33613 = ((_33605 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _33614 = vec3(0.0);
                                    if (debug_view_info.view.x == 4.0)
                                    {
                                        highp float _27451 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                        float mp_copy_27451 = _27451;
                                        vec3 _27452 = cross(_7152, v_tangent.xyz) * mp_copy_27451;
                                        float _27841 = length(_27452);
                                        vec3 _33603 = vec3(0.0);
                                        if (_27841 > 9.9999999747524270787835121154785e-07)
                                        {
                                            _33603 = _27452 / vec3(_27841);
                                        }
                                        else
                                        {
                                            _33603 = vec3(0.0);
                                        }
                                        _33614 = ((_33603 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec3 _33615 = vec3(0.0);
                                        if (debug_view_info.view.x == 5.0)
                                        {
                                            _33615 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                        }
                                        else
                                        {
                                            vec3 _33616 = vec3(0.0);
                                            if (debug_view_info.view.x == 6.0)
                                            {
                                                _33616 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                            }
                                            else
                                            {
                                                vec3 _33617 = vec3(0.0);
                                                if (debug_view_info.view.x == 7.0)
                                                {
                                                    _33617 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                                }
                                                else
                                                {
                                                    vec3 _33618 = vec3(0.0);
                                                    if (debug_view_info.view.x == 8.0)
                                                    {
                                                        vec3 _27876 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                        _33618 = mix(_27876 * 12.9200000762939453125, (pow(max(_27876, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _27876));
                                                    }
                                                    else
                                                    {
                                                        vec3 _33619 = vec3(0.0);
                                                        if (debug_view_info.view.x == 9.0)
                                                        {
                                                            vec3 mp_copy_33599 = vec3(0.0);
                                                            highp vec3 _33599 = vec3(0.0);
                                                            if (_14906)
                                                            {
                                                                _33599 = -view_info.camera_forward.xyz;
                                                            }
                                                            else
                                                            {
                                                                _33599 = normalize(v_viewvector);
                                                            }
                                                            mp_copy_33599 = _33599;
                                                            float _27912 = length(mp_copy_33599);
                                                            vec3 _33600 = vec3(0.0);
                                                            if (_27912 > 9.9999999747524270787835121154785e-07)
                                                            {
                                                                _33600 = mp_copy_33599 / vec3(_27912);
                                                            }
                                                            else
                                                            {
                                                                _33600 = vec3(0.0);
                                                            }
                                                            _33619 = ((_33600 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                        }
                                                        else
                                                        {
                                                            vec3 _33620 = vec3(0.0);
                                                            if (debug_view_info.view.x == 10.0)
                                                            {
                                                                float _27955 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                float _27956 = (v_position.x - debug_view_info.params.x) / _27955;
                                                                bool _27960 = debug_view_info.view.w > 1.5;
                                                                float _33583 = 0.0;
                                                                if (_27960)
                                                                {
                                                                    _33583 = fract(_27956);
                                                                }
                                                                else
                                                                {
                                                                    float _33584 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33584 = ((_27956 < 0.0) || (_27956 > 1.0)) ? 0.0 : _27956;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33584 = clamp(_27956, 0.0, 1.0);
                                                                    }
                                                                    _33583 = _33584;
                                                                }
                                                                float _28007 = (v_position.y - debug_view_info.params.x) / _27955;
                                                                float _33589 = 0.0;
                                                                if (_27960)
                                                                {
                                                                    _33589 = fract(_28007);
                                                                }
                                                                else
                                                                {
                                                                    float _33590 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33590 = ((_28007 < 0.0) || (_28007 > 1.0)) ? 0.0 : _28007;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33590 = clamp(_28007, 0.0, 1.0);
                                                                    }
                                                                    _33589 = _33590;
                                                                }
                                                                float _28058 = (v_position.z - debug_view_info.params.x) / _27955;
                                                                float _33595 = 0.0;
                                                                if (_27960)
                                                                {
                                                                    _33595 = fract(_28058);
                                                                }
                                                                else
                                                                {
                                                                    float _33596 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33596 = ((_28058 < 0.0) || (_28058 > 1.0)) ? 0.0 : _28058;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33596 = clamp(_28058, 0.0, 1.0);
                                                                    }
                                                                    _33595 = _33596;
                                                                }
                                                                _33620 = vec3(_33583 * debug_view_info.view.z, _33589 * debug_view_info.view.z, _33595 * debug_view_info.view.z);
                                                            }
                                                            else
                                                            {
                                                                vec3 _33621 = vec3(0.0);
                                                                if (debug_view_info.view.x == 11.0)
                                                                {
                                                                    bvec3 _27527 = bvec3(gl_FrontFacing);
                                                                    _33621 = vec3(_27527.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _27527.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _27527.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                                }
                                                                else
                                                                {
                                                                    vec3 _33622 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 12.0)
                                                                    {
                                                                        highp vec2 _28085 = v_texture_coords;
                                                                        vec2 mp_copy_28085 = _28085;
                                                                        vec2 _28097 = floor(mp_copy_28085 * 8.0);
                                                                        float _28099 = _28097.x;
                                                                        float _28101 = _28097.y;
                                                                        float _28109 = _28099 + (_28101 * 8.0);
                                                                        vec2 _28118 = step(vec2(0.0), mp_copy_28085) * step(mp_copy_28085, vec2(1.0));
                                                                        _33622 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_28099 + _28101, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_28109 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_28109 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_28118.x * _28118.y));
                                                                    }
                                                                    else
                                                                    {
                                                                        vec3 _33623 = vec3(0.0);
                                                                        if (debug_view_info.view.x == 13.0)
                                                                        {
                                                                            highp vec2 _28168 = v_texture_coords_1;
                                                                            vec2 mp_copy_28168 = _28168;
                                                                            vec2 _28180 = floor(mp_copy_28168 * 8.0);
                                                                            float _28182 = _28180.x;
                                                                            float _28184 = _28180.y;
                                                                            float _28192 = _28182 + (_28184 * 8.0);
                                                                            vec2 _28201 = step(vec2(0.0), mp_copy_28168) * step(mp_copy_28168, vec2(1.0));
                                                                            _33623 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_28182 + _28184, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_28192 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_28192 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_28201.x * _28201.y));
                                                                        }
                                                                        else
                                                                        {
                                                                            vec3 _33624 = vec3(0.0);
                                                                            if (debug_view_info.view.x == 14.0)
                                                                            {
                                                                                highp float _28267 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                                bool _28273 = debug_view_info.depth.x > 0.5;
                                                                                bool _28279 = false;
                                                                                if (_28273)
                                                                                {
                                                                                    _28279 = debug_view_info.depth.y > 0.5;
                                                                                }
                                                                                else
                                                                                {
                                                                                    _28279 = _28273;
                                                                                }
                                                                                highp float _33569 = 0.0;
                                                                                if (_28279)
                                                                                {
                                                                                    _33569 = 1.1920928955078125e-07 / _28267;
                                                                                }
                                                                                else
                                                                                {
                                                                                    highp float _33570 = 0.0;
                                                                                    if (_28273)
                                                                                    {
                                                                                        _33570 = 5.9604644775390625e-08 / (_28267 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        _33570 = 5.9604644775390625e-08 / (_28267 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                    }
                                                                                    _33569 = _33570;
                                                                                }
                                                                                highp float _28308 = dot(_7154, view_info.camera_forward.xyz);
                                                                                highp float _28314 = sqrt(max(1.0 - (_28308 * _28308), 0.0));
                                                                                highp float _33567 = 0.0;
                                                                                if (_14906)
                                                                                {
                                                                                    _33567 = (debug_view_info.depth.z * _28314) / max(abs(_28308), 9.9999999747524270787835121154785e-07);
                                                                                }
                                                                                else
                                                                                {
                                                                                    _33567 = (((1.0 / (_28267 * _28267)) * debug_view_info.depth.z) * _28314) / max(abs(dot(_7154, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                                }
                                                                                highp float _28352 = log2(max(max(8.0 * _33569, _33567 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                                float mp_copy_28352 = _28352;
                                                                                float _28391 = (mp_copy_28352 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                                float _33579 = 0.0;
                                                                                if (debug_view_info.view.w > 1.5)
                                                                                {
                                                                                    _33579 = fract(_28391);
                                                                                }
                                                                                else
                                                                                {
                                                                                    float _33580 = 0.0;
                                                                                    if (debug_view_info.view.w > 0.5)
                                                                                    {
                                                                                        _33580 = ((_28391 < 0.0) || (_28391 > 1.0)) ? 0.0 : _28391;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        _33580 = clamp(_28391, 0.0, 1.0);
                                                                                    }
                                                                                    _33579 = _33580;
                                                                                }
                                                                                _33624 = clamp(vec3(1.5) - abs(vec3(4.0 * _33579) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                            }
                                                                            else
                                                                            {
                                                                                vec2 _28424 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                                _33624 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28424.x + _28424.y, 2.0)));
                                                                            }
                                                                            _33623 = _33624;
                                                                        }
                                                                        _33622 = _33623;
                                                                    }
                                                                    _33621 = _33622;
                                                                }
                                                                _33620 = _33621;
                                                            }
                                                            _33619 = _33620;
                                                        }
                                                        _33618 = _33619;
                                                    }
                                                    _33617 = _33618;
                                                }
                                                _33616 = _33617;
                                            }
                                            _33615 = _33616;
                                        }
                                        _33614 = _33615;
                                    }
                                    _33613 = _33614;
                                }
                                _33612 = _33613;
                            }
                            _33611 = _33612;
                        }
                        _33625 = vec4(_33611, 1.0);
                        break;
                    }
                    vec3 _33546 = vec3(0.0);
                    if (debug_view_info.view.x < 40.0)
                    {
                        vec3 _33547 = vec3(0.0);
                        if (debug_view_info.view.x == 20.0)
                        {
                            vec3 _28445 = max(_13970 * debug_view_info.view.z, vec3(0.0));
                            _33547 = mix(_28445 * 12.9200000762939453125, (pow(max(_28445, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _28445));
                        }
                        else
                        {
                            vec3 _33548 = vec3(0.0);
                            if (debug_view_info.view.x == 21.0)
                            {
                                float _28484 = (_35252 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _33542 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _33542 = fract(_28484);
                                }
                                else
                                {
                                    float _33543 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _33543 = ((_28484 < 0.0) || (_28484 > 1.0)) ? 0.0 : _28484;
                                    }
                                    else
                                    {
                                        _33543 = clamp(_28484, 0.0, 1.0);
                                    }
                                    _33542 = _33543;
                                }
                                _33548 = vec3(_33542 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _33549 = vec3(0.0);
                                if (debug_view_info.view.x == 22.0)
                                {
                                    float _28535 = (_7287 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _33538 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _33538 = fract(_28535);
                                    }
                                    else
                                    {
                                        float _33539 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _33539 = ((_28535 < 0.0) || (_28535 > 1.0)) ? 0.0 : _28535;
                                        }
                                        else
                                        {
                                            _33539 = clamp(_28535, 0.0, 1.0);
                                        }
                                        _33538 = _33539;
                                    }
                                    _33549 = vec3(_33538 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _33550 = vec3(0.0);
                                    if (debug_view_info.view.x == 23.0)
                                    {
                                        float _28586 = (_7294 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _33534 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _33534 = fract(_28586);
                                        }
                                        else
                                        {
                                            float _33535 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _33535 = ((_28586 < 0.0) || (_28586 > 1.0)) ? 0.0 : _28586;
                                            }
                                            else
                                            {
                                                _33535 = clamp(_28586, 0.0, 1.0);
                                            }
                                            _33534 = _33535;
                                        }
                                        _33550 = vec3(_33534 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _33551 = vec3(0.0);
                                        if (debug_view_info.view.x == 24.0)
                                        {
                                            float _28637 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                            float _33530 = 0.0;
                                            if (debug_view_info.view.w > 1.5)
                                            {
                                                _33530 = fract(_28637);
                                            }
                                            else
                                            {
                                                float _33531 = 0.0;
                                                if (debug_view_info.view.w > 0.5)
                                                {
                                                    _33531 = ((_28637 < 0.0) || (_28637 > 1.0)) ? 0.0 : _28637;
                                                }
                                                else
                                                {
                                                    _33531 = clamp(_28637, 0.0, 1.0);
                                                }
                                                _33530 = _33531;
                                            }
                                            _33551 = vec3(_33530 * debug_view_info.view.z);
                                        }
                                        else
                                        {
                                            vec3 _33552 = vec3(0.0);
                                            if (debug_view_info.view.x == 25.0)
                                            {
                                                float _28688 = (_7316 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                float _33526 = 0.0;
                                                if (debug_view_info.view.w > 1.5)
                                                {
                                                    _33526 = fract(_28688);
                                                }
                                                else
                                                {
                                                    float _33527 = 0.0;
                                                    if (debug_view_info.view.w > 0.5)
                                                    {
                                                        _33527 = ((_28688 < 0.0) || (_28688 > 1.0)) ? 0.0 : _28688;
                                                    }
                                                    else
                                                    {
                                                        _33527 = clamp(_28688, 0.0, 1.0);
                                                    }
                                                    _33526 = _33527;
                                                }
                                                _33552 = vec3(_33526 * debug_view_info.view.z);
                                            }
                                            else
                                            {
                                                vec3 _33553 = vec3(0.0);
                                                if (debug_view_info.view.x == 26.0)
                                                {
                                                    vec3 _28724 = max(_7340 * debug_view_info.view.z, vec3(0.0));
                                                    _33553 = mix(_28724 * 12.9200000762939453125, (pow(max(_28724, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _28724));
                                                }
                                                else
                                                {
                                                    vec2 _28745 = floor(gl_FragCoord.xy * vec2(0.125));
                                                    _33553 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28745.x + _28745.y, 2.0)));
                                                }
                                                _33552 = _33553;
                                            }
                                            _33551 = _33552;
                                        }
                                        _33550 = _33551;
                                    }
                                    _33549 = _33550;
                                }
                                _33548 = _33549;
                            }
                            _33547 = _33548;
                        }
                        _33546 = _33547;
                    }
                    else
                    {
                        vec3 _33554 = vec3(0.0);
                        if (debug_view_info.view.x < 60.0)
                        {
                            vec2 _28766 = floor(gl_FragCoord.xy * vec2(0.125));
                            _33554 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28766.x + _28766.y, 2.0)));
                        }
                        else
                        {
                            vec3 _33555 = vec3(0.0);
                            if (debug_view_info.view.x < 70.0)
                            {
                                vec3 _33556 = vec3(0.0);
                                if (debug_view_info.view.x == 60.0)
                                {
                                    _33556 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _33557 = vec3(0.0);
                                    if (debug_view_info.view.x == 61.0)
                                    {
                                        _33557 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec2 _28854 = floor(gl_FragCoord.xy * vec2(0.125));
                                        _33557 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28854.x + _28854.y, 2.0)));
                                    }
                                    _33556 = _33557;
                                }
                                _33555 = _33556;
                            }
                            else
                            {
                                vec3 _33558 = vec3(0.0);
                                if (debug_view_info.view.x < 80.0)
                                {
                                    vec3 _33559 = vec3(0.0);
                                    if (debug_view_info.view.x == 70.0)
                                    {
                                        bool _28871 = v_texture_coords.x < 0.0;
                                        bool _28878 = false;
                                        if (!_28871)
                                        {
                                            _28878 = v_texture_coords.x > 1.0;
                                        }
                                        else
                                        {
                                            _28878 = _28871;
                                        }
                                        bool _28885 = false;
                                        if (!_28878)
                                        {
                                            _28885 = v_texture_coords.y < 0.0;
                                        }
                                        else
                                        {
                                            _28885 = _28878;
                                        }
                                        bool _28892 = false;
                                        if (!_28885)
                                        {
                                            _28892 = v_texture_coords.y > 1.0;
                                        }
                                        else
                                        {
                                            _28892 = _28885;
                                        }
                                        bvec3 _28895 = bvec3(_28892);
                                        highp vec3 _28896 = vec3(_28895.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _28895.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _28895.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        bvec3 _28921 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                        highp vec3 _28922 = vec3(_28921.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _28896.x, _28921.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _28896.y, _28921.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _28896.z);
                                        float _28936 = length(v_normal);
                                        bvec3 _28943 = bvec3((_28936 < 0.300000011920928955078125) || (_28936 > 1.7000000476837158203125));
                                        highp vec3 _28944 = vec3(_28943.x ? vec3(1.0, 0.5, 0.0).x : _28922.x, _28943.y ? vec3(1.0, 0.5, 0.0).y : _28922.y, _28943.z ? vec3(1.0, 0.5, 0.0).z : _28922.z);
                                        bool _28949 = _7287 > 0.0500000007450580596923828125;
                                        bool _28955 = false;
                                        if (_28949)
                                        {
                                            _28955 = _7287 < 0.949999988079071044921875;
                                        }
                                        else
                                        {
                                            _28955 = _28949;
                                        }
                                        bvec3 _28957 = bvec3(_28955);
                                        highp vec3 _28958 = vec3(_28957.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _28944.x, _28957.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _28944.y, _28957.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _28944.z);
                                        vec3 _33524 = vec3(0.0);
                                        do
                                        {
                                            float _28968 = dot(_13970, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7287 > 0.5)
                                            {
                                                _33524 = _28958;
                                                break;
                                            }
                                            if (_28968 < 0.0130000002682209014892578125)
                                            {
                                                _33524 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_28968 > 0.87000000476837158203125)
                                            {
                                                _33524 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _33524 = _28958;
                                            break;
                                        } while(false);
                                        vec3 _33525 = vec3(0.0);
                                        do
                                        {
                                            vec3 _29013 = ((_13970 + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                            bool _29028 = min(min(_7238, _7239), _7240) < 0.0;
                                            bool _29041 = false;
                                            if (!_29028)
                                            {
                                                _29041 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                            }
                                            else
                                            {
                                                _29041 = _29028;
                                            }
                                            if (any(isnan(_29013)))
                                            {
                                                _33525 = vec3(1.0, 0.0, 0.0);
                                                break;
                                            }
                                            if (any(isinf(_29013)))
                                            {
                                                _33525 = vec3(0.0, 1.0, 0.0);
                                                break;
                                            }
                                            if (_29041)
                                            {
                                                _33525 = vec3(0.0, 0.25, 1.0);
                                                break;
                                            }
                                            _33525 = _33524;
                                            break;
                                        } while(false);
                                        _33559 = _33525;
                                    }
                                    else
                                    {
                                        vec3 _33560 = vec3(0.0);
                                        if (debug_view_info.view.x == 71.0)
                                        {
                                            vec3 _33523 = vec3(0.0);
                                            do
                                            {
                                                vec3 _29081 = ((_13970 + _30829) + _7340) + vec3((_7287 + _7294) + _7316);
                                                bool _29096 = min(min(_7238, _7239), _7240) < 0.0;
                                                bool _29109 = false;
                                                if (!_29096)
                                                {
                                                    _29109 = min(min(_7340.x, _7340.y), _7340.z) < 0.0;
                                                }
                                                else
                                                {
                                                    _29109 = _29096;
                                                }
                                                if (any(isnan(_29081)))
                                                {
                                                    _33523 = vec3(1.0, 0.0, 0.0);
                                                    break;
                                                }
                                                if (any(isinf(_29081)))
                                                {
                                                    _33523 = vec3(0.0, 1.0, 0.0);
                                                    break;
                                                }
                                                if (_29109)
                                                {
                                                    _33523 = vec3(0.0, 0.25, 1.0);
                                                    break;
                                                }
                                                _33523 = vec3(0.3499999940395355224609375);
                                                break;
                                            } while(false);
                                            _33560 = _33523;
                                        }
                                        else
                                        {
                                            vec3 _33561 = vec3(0.0);
                                            if (debug_view_info.view.x == 72.0)
                                            {
                                                vec3 _33522 = vec3(0.0);
                                                do
                                                {
                                                    float _29131 = dot(_13970, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                                    if (_7287 > 0.5)
                                                    {
                                                        _33522 = vec3(0.3499999940395355224609375);
                                                        break;
                                                    }
                                                    if (_29131 < 0.0130000002682209014892578125)
                                                    {
                                                        _33522 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                        break;
                                                    }
                                                    if (_29131 > 0.87000000476837158203125)
                                                    {
                                                        _33522 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                        break;
                                                    }
                                                    _33522 = vec3(0.3499999940395355224609375);
                                                    break;
                                                } while(false);
                                                _33561 = _33522;
                                            }
                                            else
                                            {
                                                vec3 _33562 = vec3(0.0);
                                                if (debug_view_info.view.x == 73.0)
                                                {
                                                    bool _29153 = _7287 > 0.0500000007450580596923828125;
                                                    bool _29159 = false;
                                                    if (_29153)
                                                    {
                                                        _29159 = _7287 < 0.949999988079071044921875;
                                                    }
                                                    else
                                                    {
                                                        _29159 = _29153;
                                                    }
                                                    bvec3 _29161 = bvec3(_29159);
                                                    _33562 = vec3(_29161.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _29161.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _29161.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _33563 = vec3(0.0);
                                                    if (debug_view_info.view.x == 74.0)
                                                    {
                                                        float _29167 = length(v_normal);
                                                        bvec3 _29174 = bvec3((_29167 < 0.300000011920928955078125) || (_29167 > 1.7000000476837158203125));
                                                        _33563 = vec3(_29174.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _29174.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _29174.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _33564 = vec3(0.0);
                                                        if (debug_view_info.view.x == 75.0)
                                                        {
                                                            bvec3 _29197 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30829), normalize(_7154)) < 0.999000012874603271484375));
                                                            _33564 = vec3(_29197.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _29197.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _29197.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _33565 = vec3(0.0);
                                                            if (debug_view_info.view.x == 76.0)
                                                            {
                                                                bool _29215 = v_texture_coords.x < 0.0;
                                                                bool _29222 = false;
                                                                if (!_29215)
                                                                {
                                                                    _29222 = v_texture_coords.x > 1.0;
                                                                }
                                                                else
                                                                {
                                                                    _29222 = _29215;
                                                                }
                                                                bool _29229 = false;
                                                                if (!_29222)
                                                                {
                                                                    _29229 = v_texture_coords.y < 0.0;
                                                                }
                                                                else
                                                                {
                                                                    _29229 = _29222;
                                                                }
                                                                bool _29236 = false;
                                                                if (!_29229)
                                                                {
                                                                    _29236 = v_texture_coords.y > 1.0;
                                                                }
                                                                else
                                                                {
                                                                    _29236 = _29229;
                                                                }
                                                                bvec3 _29239 = bvec3(_29236);
                                                                _33565 = vec3(_29239.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _29239.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _29239.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                            }
                                                            else
                                                            {
                                                                vec2 _29252 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                _33565 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_29252.x + _29252.y, 2.0)));
                                                            }
                                                            _33564 = _33565;
                                                        }
                                                        _33563 = _33564;
                                                    }
                                                    _33562 = _33563;
                                                }
                                                _33561 = _33562;
                                            }
                                            _33560 = _33561;
                                        }
                                        _33559 = _33560;
                                    }
                                    _33558 = _33559;
                                }
                                else
                                {
                                    vec3 _33566 = vec3(0.0);
                                    if (debug_view_info.view.x == 80.0)
                                    {
                                        _33566 = vec3(0.0);
                                    }
                                    else
                                    {
                                        vec2 _29270 = floor(gl_FragCoord.xy * vec2(0.125));
                                        _33566 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_29270.x + _29270.y, 2.0)));
                                    }
                                    _33558 = _33566;
                                }
                                _33555 = _33558;
                            }
                            _33554 = _33555;
                        }
                        _33546 = _33554;
                    }
                    _33625 = vec4(_33546, 1.0);
                    break;
                } while(false);
                bvec4 _29289 = bvec4(gl_FragCoord.x >= debug_view_info.view.y);
                _33626 = vec4(_29289.x ? _33625.x : _32113.x, _29289.y ? _33625.y : _32113.y, _29289.z ? _33625.z : _32113.z, _29289.w ? _33625.w : _32113.w);
            }
            else
            {
                _33626 = _32113;
            }
            frag_color = _33626;
        }
    }
    float _34760 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _34760 = 1.0;
    }
    else
    {
        _34760 = abs(frag_info.fade);
    }
    frag_color *= _34760;
}

