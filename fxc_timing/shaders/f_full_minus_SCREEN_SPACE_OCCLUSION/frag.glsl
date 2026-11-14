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

layout(std140) uniform FogInfo
{
    highp vec4 params0;
    highp vec4 params1;
    highp vec4 params2;
    vec4 color;
    vec4 sun;
    vec4 sun_dir;
} _FogInfo;

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
uniform mediump sampler2D brdf_lut;
uniform mediump sampler2D prefiltered_radiance;
uniform mediump sampler2D prefiltered_radiance_b;
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
in highp vec3 v_position;
in vec4 v_color;
layout(location = 0) out vec4 frag_color;

void main()
{
    highp float _5766 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_5766 = _5766;
    vec3 _5770 = normalize(v_normal) * mp_copy_5766;
    vec4 _5812 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _5815 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _17653 = vec2(0.0);
    if (_5815)
    {
        highp vec2 _17652 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _17652 = v_texture_coords_1;
        }
        else
        {
            _17652 = v_texture_coords;
        }
        highp vec2 _6015 = _17652 * texture_transforms.base_color_transform.zw;
        highp float _6021 = _6015.x;
        highp float _6026 = _6015.y;
        _17653 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6021) + (texture_transforms.base_color_rotation.y * _6026), ((-texture_transforms.base_color_rotation.y) * _6021) + (texture_transforms.base_color_rotation.x * _6026));
    }
    else
    {
        _17653 = v_texture_coords;
    }
    vec4 _5829 = texture(base_color_texture, _17653);
    vec3 _5831 = _5829.xyz;
    float _18709 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_5829.w * _5812.w) * frag_info.color.w);
    vec3 _17668 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _17656 = vec2(0.0);
        if (_5815)
        {
            highp vec2 _17655 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _17655 = v_texture_coords_1;
            }
            else
            {
                _17655 = v_texture_coords;
            }
            highp vec2 _6110 = _17655 * texture_transforms.normal_transform.zw;
            highp float _6116 = _6110.x;
            highp float _6121 = _6110.y;
            _17656 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6116) + (texture_transforms.normal_rotation.y * _6121), ((-texture_transforms.normal_rotation.y) * _6116) + (texture_transforms.normal_rotation.x * _6121));
        }
        else
        {
            _17656 = v_texture_coords;
        }
        vec3 _6169 = ((texture(normal_texture, _17656).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6173 = _6169.xy * vec2(frag_info.normal_scale);
        vec3 _17104 = _6169;
        _17104.x = _6173.x;
        _17104.y = _6173.y;
        highp vec3 _6179 = -v_viewvector;
        highp vec3 _6269 = dFdx(_6179);
        highp vec3 _6271 = dFdy(_6179);
        highp vec2 _6273 = dFdx(_17656);
        highp vec2 _6275 = dFdy(_17656);
        bvec2 _18711 = bvec2(length(_6273) == 0.0);
        highp vec2 _18712 = vec2(_18711.x ? vec2(1.0, 0.0).x : _6273.x, _18711.y ? vec2(1.0, 0.0).y : _6273.y);
        bvec2 _18713 = bvec2(length(_6275) == 0.0);
        highp vec2 _18714 = vec2(_18713.x ? vec2(0.0, 1.0).x : _6275.x, _18713.y ? vec2(0.0, 1.0).y : _6275.y);
        highp vec3 _6288 = cross(_6271, _5770);
        highp vec3 _6291 = cross(_5770, _6269);
        highp float _6316 = (dot(cross(_6269, _6271), _5770) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6319 = ((_6288 * _18712.x) + (_6291 * _18714.x)) * _6316;
        highp float _17663 = 0.0;
        if (gl_FrontFacing)
        {
            _17663 = -_6316;
        }
        else
        {
            _17663 = _6316;
        }
        highp vec3 _6329 = ((_6288 * _18712.y) + (_6291 * _18714.y)) * _17663;
        highp float _6338 = inversesqrt(max(max(dot(_6319, _6319), dot(_6329, _6329)), 9.9999996826552253889678874634872e-21));
        vec3 _6210 = v_tangent.xyz - (_5770 * dot(_5770, v_tangent.xyz));
        highp float _6213 = dot(_6210, _6210);
        bool _6215 = _6213 > 1.0000000133514319600180897396058e-10;
        bool _6222 = false;
        if (_6215)
        {
            _6222 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6222 = _6215;
        }
        mat3 _17666 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6222)
        {
            highp vec3 _6227 = _6210 * inversesqrt(_6213);
            _17666 = mat3(_6227, normalize(cross(_5770, _6227)) * sign(v_tangent.w), _5770);
        }
        else
        {
            _17666 = mat3(_6319 * _6338, _6329 * _6338, _5770);
        }
        _17668 = normalize(_17666 * _17104);
    }
    else
    {
        _17668 = _5770;
    }
    highp vec2 _17670 = vec2(0.0);
    if (_5815)
    {
        highp vec2 _17669 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _17669 = v_texture_coords_1;
        }
        else
        {
            _17669 = v_texture_coords;
        }
        highp vec2 _6403 = _17669 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6409 = _6403.x;
        highp float _6414 = _6403.y;
        _17670 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6409) + (texture_transforms.metallic_roughness_rotation.y * _6414), ((-texture_transforms.metallic_roughness_rotation.y) * _6409) + (texture_transforms.metallic_roughness_rotation.x * _6414));
    }
    else
    {
        _17670 = v_texture_coords;
    }
    vec4 _5898 = texture(metallic_roughness_texture, _17670);
    float _5904 = clamp(_5898.z * frag_info.metallic_factor, 0.0, 1.0);
    float _5911 = clamp(_5898.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _17672 = vec2(0.0);
    if (_5815)
    {
        highp vec2 _17671 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _17671 = v_texture_coords_1;
        }
        else
        {
            _17671 = v_texture_coords;
        }
        highp vec2 _6474 = _17671 * texture_transforms.occlusion_transform.zw;
        highp float _6480 = _6474.x;
        highp float _6485 = _6474.y;
        _17672 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6480) + (texture_transforms.occlusion_rotation.y * _6485), ((-texture_transforms.occlusion_rotation.y) * _6480) + (texture_transforms.occlusion_rotation.x * _6485));
    }
    else
    {
        _17672 = v_texture_coords;
    }
    float _17673 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _17673 = texture(occlusion_texture, _17672).x;
    }
    else
    {
        _17673 = 1.0;
    }
    float _5938 = 1.0 - ((1.0 - _17673) * frag_info.occlusion_strength);
    highp vec2 _17675 = vec2(0.0);
    if (_5815)
    {
        highp vec2 _17674 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _17674 = v_texture_coords_1;
        }
        else
        {
            _17674 = v_texture_coords;
        }
        highp vec2 _6545 = _17674 * texture_transforms.emissive_transform.zw;
        highp float _6551 = _6545.x;
        highp float _6556 = _6545.y;
        _17675 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6551) + (texture_transforms.emissive_rotation.y * _6556), ((-texture_transforms.emissive_rotation.y) * _6551) + (texture_transforms.emissive_rotation.x * _6556));
    }
    else
    {
        _17675 = v_texture_coords;
    }
    vec3 _5957 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _17691 = vec3(0.0);
    if (dot(abs(_5957), vec3(1.0)) > 0.0)
    {
        vec3 _5966 = texture(emissive_texture, _17675).xyz;
        _17691 = mix(_5966 * vec3(0.077399380505084991455078125), pow((_5966 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5966)) * _5957;
    }
    else
    {
        _17691 = vec3(0.0);
    }
    highp float hp_copy_17716 = 0.0;
    vec3 _6796 = vec4((mix(_5831 * vec3(0.077399380505084991455078125), pow((_5831 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5831)) * _5812.xyz) * frag_info.color.xyz, _18709).xyz;
    vec3 _7511 = dFdx(_17668);
    vec3 _7513 = dFdy(_17668);
    float _17716 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _17716 = sqrt(clamp((_5911 * _5911) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7511, _7511), dot(_7513, _7513))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _17716 = _5911;
    }
    hp_copy_17716 = _17716;
    float _17943 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _17943 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _17943 = _5938;
    }
    bool _6821 = frag_info.has_directional_light > 0.5;
    float _17717 = 0.0;
    vec3 _18017 = vec3(0.0);
    if (_6821)
    {
        highp vec3 _6827 = -normalize(frag_info.directional_light_direction.xyz);
        _18017 = _6827;
        _17717 = dot(_5770, _6827);
    }
    else
    {
        _18017 = vec3(0.0);
        _17717 = 0.0;
    }
    float _6834 = clamp(_17717 * 6.666666507720947265625, 0.0, 1.0);
    bool _6843 = false;
    if (_6821)
    {
        _6843 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _6843 = _6821;
    }
    float _17726 = 0.0;
    if (_6843 && (_6834 > 0.0))
    {
        int _7592 = int(frag_info.shadow_cascade_count);
        float _7787 = max(dot(_5770, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _7790 = _7787 * _7787;
        highp vec3 _7810 = v_position + (_5770 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _7790, 0.0)) / _7790, 8.0))));
        highp float _7598 = frag_info.directional_light_color.w * 0.5;
        float _7600 = frag_info.dielectric_f0.w;
        highp float hp_copy_7600 = _7600;
        float _17718 = 0.0;
        if (_7600 > 0.0)
        {
            _17718 = smoothstep(_7600 - max(frag_info.shadow_fade, hp_copy_7600 * 0.100000001490116119384765625), _7600, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _17718 = 0.0;
        }
        float _17720 = 0.0;
        float _17722 = 0.0;
        if (_17718 < 1.0)
        {
            float _17721 = 0.0;
            float _17723 = 0.0;
            _17723 = 0.0;
            _17721 = 0.0;
            float _18488 = 0.0;
            float _18491 = 0.0;
            for (int _17719 = 0; _17719 < _7592; _17723 = _18491, _17721 = _18488, _17719++)
            {
                if (_17723 < 1.0)
                {
                    highp vec4 _7632 = vec4(_7810, 1.0);
                    highp vec4 _18360 = vec4(0.0);
                    highp float _18363 = 0.0;
                    if (_17719 == 0)
                    {
                        _18363 = frag_info.cascade_box_sizes.x;
                        _18360 = frag_info.light_space_matrix[0] * _7632;
                    }
                    else
                    {
                        highp vec4 _18361 = vec4(0.0);
                        highp float _18364 = 0.0;
                        if (_17719 == 1)
                        {
                            _18364 = frag_info.cascade_box_sizes.y;
                            _18361 = frag_info.light_space_matrix[1] * _7632;
                        }
                        else
                        {
                            highp vec4 _18362 = vec4(0.0);
                            highp float _18365 = 0.0;
                            if (_17719 == 2)
                            {
                                _18365 = frag_info.cascade_box_sizes.z;
                                _18362 = frag_info.light_space_matrix[2] * _7632;
                            }
                            else
                            {
                                _18365 = frag_info.cascade_box_sizes.w;
                                _18362 = frag_info.light_space_matrix[3] * _7632;
                            }
                            _18364 = _18365;
                            _18361 = _18362;
                        }
                        _18363 = _18364;
                        _18360 = _18361;
                    }
                    highp vec3 _7677 = _18360.xyz / vec3(_18360.w);
                    highp vec2 _7680 = _7677.xy * 0.5;
                    highp vec2 _7682 = _7680 + vec2(0.5);
                    highp float _7689 = max(frag_info.shadow_softness / _18363, frag_info.shadow_texel_size);
                    highp float _7691 = _7682.x;
                    bool _7693 = _7691 < _7689;
                    bool _7702 = false;
                    if (!_7693)
                    {
                        _7702 = _7691 > (1.0 - _7689);
                    }
                    else
                    {
                        _7702 = _7693;
                    }
                    bool _7710 = false;
                    if (!_7702)
                    {
                        _7710 = _7682.y < _7689;
                    }
                    else
                    {
                        _7710 = _7702;
                    }
                    bool _7719 = false;
                    if (!_7710)
                    {
                        _7719 = _7682.y > (1.0 - _7689);
                    }
                    else
                    {
                        _7719 = _7710;
                    }
                    bool _7726 = false;
                    if (!_7719)
                    {
                        _7726 = _7677.z < 0.0;
                    }
                    else
                    {
                        _7726 = _7719;
                    }
                    bool _7733 = false;
                    if (!_7726)
                    {
                        _7733 = _7677.z > 1.0;
                    }
                    else
                    {
                        _7733 = _7726;
                    }
                    float _18489 = 0.0;
                    float _18492 = 0.0;
                    if (!_7733)
                    {
                        highp vec2 _7826 = vec2(_7689);
                        highp vec2 _7831 = vec2(_7689 + max(_7598, 9.9999997473787516355514526367188e-05));
                        highp vec2 _7839 = vec2(0.5) - _7680;
                        highp vec2 _7841 = smoothstep(_7826, _7831, _7682) * smoothstep(_7826, _7831, _7839);
                        float _18366 = 0.0;
                        if (_7598 > 0.0)
                        {
                            _18366 = _7841.x * _7841.y;
                        }
                        else
                        {
                            _18366 = 1.0;
                        }
                        float _7742 = min(_18366, 1.0 - _17723);
                        float _18490 = 0.0;
                        float _18493 = 0.0;
                        if (_7742 > 0.0)
                        {
                            highp float _7980 = _7677.z - (frag_info.shadow_bias / (7.0 * _18363));
                            highp float _7986 = 1.0 / (float(_7592) + frag_info.spot_shadow_params.x);
                            highp float _7988 = frag_info.directional_light_direction.w;
                            float mp_copy_7988 = _7988;
                            float _7994 = step(0.5, mp_copy_7988) * (1.0 - step(1.5, mp_copy_7988));
                            float _18396 = 0.0;
                            float _18400 = 0.0;
                            if (_7994 < 0.5)
                            {
                                highp float _8005 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_8005 = _8005;
                                _18400 = sin(mp_copy_8005);
                                _18396 = cos(mp_copy_8005);
                            }
                            else
                            {
                                _18400 = 0.0;
                                _18396 = 1.0;
                            }
                            highp float _18403 = 0.0;
                            if ((_7988 > 1.5) && (_7988 < 2.5))
                            {
                                highp float _8029 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _8034 = max(_8029 * _7980, frag_info.shadow_texel_size);
                                float _18392 = 0.0;
                                highp float _18393 = 0.0;
                                _18393 = 0.0;
                                _18392 = 0.0;
                                highp float _8056 = 0.0;
                                float _8059 = 0.0;
                                for (int _18391 = 0; _18391 < 9; _18393 = _8056, _18392 = _8059, _18391++)
                                {
                                    vec2 _18482 = vec2(0.0);
                                    do
                                    {
                                        if (_18391 == 0)
                                        {
                                            _18482 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_18391 == 1)
                                        {
                                            _18482 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_18391 == 2)
                                        {
                                            _18482 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_18391 == 3)
                                        {
                                            _18482 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_18391 == 4)
                                        {
                                            _18482 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_18391 == 5)
                                        {
                                            _18482 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_18391 == 6)
                                        {
                                            _18482 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_18391 == 7)
                                        {
                                            _18482 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_18391 == 8)
                                        {
                                            _18482 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_18391 == 9)
                                        {
                                            _18482 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_18391 == 10)
                                        {
                                            _18482 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_18391 == 11)
                                        {
                                            _18482 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_18391 == 12)
                                        {
                                            _18482 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_18391 == 13)
                                        {
                                            _18482 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_18391 == 14)
                                        {
                                            _18482 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_18391 == 15)
                                        {
                                            _18482 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _18482 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8363 = clamp(_7682 + (vec2((_18482.x * _18396) - (_18482.y * _18400), (_18482.x * _18400) + (_18482.y * _18396)) * _8034), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8372 = _8363.y;
                                    highp vec2 _8373 = vec2((float(_17719) + _8363.x) * _7986, _8372);
                                    _8373.y = 1.0 - _8372;
                                    highp vec4 _8380 = textureLod(shadow_map, _8373, 0.0);
                                    highp float _8381 = _8380.x;
                                    highp float _8051 = step(_8381, _7980);
                                    float mp_copy_8051 = _8051;
                                    _8056 = _18393 + (_8381 * _8051);
                                    _8059 = _18392 + mp_copy_8051;
                                }
                                highp float _18394 = 0.0;
                                if (_18392 > 0.0)
                                {
                                    _18394 = _18393 / _18392;
                                }
                                else
                                {
                                    _18394 = _7980;
                                }
                                _18403 = clamp(_8029 * max(_7980 - _18394, 0.0), frag_info.shadow_texel_size, _7689);
                            }
                            else
                            {
                                _18403 = _7689;
                            }
                            bool _8090 = _7988 > 2.5;
                            bool _18404 = false;
                            float _18428 = 0.0;
                            if ((_7988 < 1.5) || _8090)
                            {
                                highp vec2 _8414 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8418 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8419 = clamp(_7682, _8414, _8418);
                                highp float _8421 = float(_17719);
                                highp float _8428 = _8419.y;
                                highp vec2 _8429 = vec2((_8421 + _8419.x) * _7986, _8428);
                                _8429.y = 1.0 - _8428;
                                highp float _8441 = float(_7980 <= textureLod(shadow_map, _8429, 0.0).x);
                                float mp_copy_8441 = _8441;
                                float _8451 = (-1.0) * _18396;
                                float _8455 = (-1.0) * _18400;
                                highp vec2 _8479 = clamp(_7682 + (vec2(_8451 - _8455, _8455 + _8451) * _18403), _8414, _8418);
                                highp float _8488 = _8479.y;
                                highp vec2 _8489 = vec2((_8421 + _8479.x) * _7986, _8488);
                                _8489.y = 1.0 - _8488;
                                highp float _8501 = float(_7980 <= textureLod(shadow_map, _8489, 0.0).x);
                                float mp_copy_8501 = _8501;
                                highp vec2 _8539 = clamp(_7682 + (vec2(_18396 - _8455, _18400 + _8451) * _18403), _8414, _8418);
                                highp float _8548 = _8539.y;
                                highp vec2 _8549 = vec2((_8421 + _8539.x) * _7986, _8548);
                                _8549.y = 1.0 - _8548;
                                highp float _8561 = float(_7980 <= textureLod(shadow_map, _8549, 0.0).x);
                                float mp_copy_8561 = _8561;
                                highp vec2 _8599 = clamp(_7682 + (vec2(_8451 - _18400, _8455 + _18396) * _18403), _8414, _8418);
                                highp float _8608 = _8599.y;
                                highp vec2 _8609 = vec2((_8421 + _8599.x) * _7986, _8608);
                                _8609.y = 1.0 - _8608;
                                highp float _8621 = float(_7980 <= textureLod(shadow_map, _8609, 0.0).x);
                                float mp_copy_8621 = _8621;
                                highp vec2 _8659 = clamp(_7682 + (vec2(_18396 - _18400, _18400 + _18396) * _18403), _8414, _8418);
                                highp float _8668 = _8659.y;
                                highp vec2 _8669 = vec2((_8421 + _8659.x) * _7986, _8668);
                                _8669.y = 1.0 - _8668;
                                highp float _8681 = float(_7980 <= textureLod(shadow_map, _8669, 0.0).x);
                                float mp_copy_8681 = _8681;
                                float _8136 = (((mp_copy_8441 + mp_copy_8501) + mp_copy_8561) + mp_copy_8621) + mp_copy_8681;
                                _18428 = _8136 * 0.20000000298023223876953125;
                                _18404 = (_8136 < 0.5) || (_8136 > 4.5);
                            }
                            else
                            {
                                _18428 = 0.0;
                                _18404 = false;
                            }
                            float _18427 = 0.0;
                            if (_18404)
                            {
                                _18427 = _18428;
                            }
                            else
                            {
                                float _18429 = 0.0;
                                if (_8090)
                                {
                                    highp vec2 _8709 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _8713 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _8714 = clamp(_7682 + (vec2(-0.707099974155426025390625) * _18403), _8709, _8713);
                                    highp vec2 _8725 = (vec2(_8714.x, 1.0 - _8714.y) / _8709) - vec2(0.5);
                                    highp vec2 _8727 = floor(_8725);
                                    highp vec2 _8730 = _8725 - _8727;
                                    highp vec2 _8735 = (_8727 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _8737 = float(_17719);
                                    highp vec2 _8745 = vec2((_8737 + _8735.x) * _7986, _8735.y);
                                    highp float _8749 = frag_info.shadow_texel_size * _7986;
                                    highp vec2 _8752 = vec2(_8749, frag_info.shadow_texel_size);
                                    highp vec2 _8761 = vec2(_8749, 0.0);
                                    highp vec2 _8769 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _8798 = _8730.x;
                                    highp float _8807 = mix(mix(float(_7980 <= textureLod(shadow_map, _8745, 0.0).x), float(_7980 <= textureLod(shadow_map, _8745 + _8761, 0.0).x), _8798), mix(float(_7980 <= textureLod(shadow_map, _8745 + _8769, 0.0).x), float(_7980 <= textureLod(shadow_map, _8745 + _8752, 0.0).x), _8798), _8730.y);
                                    float mp_copy_8807 = _8807;
                                    highp vec2 _8841 = clamp(_7682 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _18403), _8709, _8713);
                                    highp vec2 _8852 = (vec2(_8841.x, 1.0 - _8841.y) / _8709) - vec2(0.5);
                                    highp vec2 _8854 = floor(_8852);
                                    highp vec2 _8857 = _8852 - _8854;
                                    highp vec2 _8862 = (_8854 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8872 = vec2((_8737 + _8862.x) * _7986, _8862.y);
                                    highp float _8925 = _8857.x;
                                    highp float _8934 = mix(mix(float(_7980 <= textureLod(shadow_map, _8872, 0.0).x), float(_7980 <= textureLod(shadow_map, _8872 + _8761, 0.0).x), _8925), mix(float(_7980 <= textureLod(shadow_map, _8872 + _8769, 0.0).x), float(_7980 <= textureLod(shadow_map, _8872 + _8752, 0.0).x), _8925), _8857.y);
                                    float mp_copy_8934 = _8934;
                                    highp vec2 _8968 = clamp(_7682 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _18403), _8709, _8713);
                                    highp vec2 _8979 = (vec2(_8968.x, 1.0 - _8968.y) / _8709) - vec2(0.5);
                                    highp vec2 _8981 = floor(_8979);
                                    highp vec2 _8984 = _8979 - _8981;
                                    highp vec2 _8989 = (_8981 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8999 = vec2((_8737 + _8989.x) * _7986, _8989.y);
                                    highp float _9052 = _8984.x;
                                    highp float _9061 = mix(mix(float(_7980 <= textureLod(shadow_map, _8999, 0.0).x), float(_7980 <= textureLod(shadow_map, _8999 + _8761, 0.0).x), _9052), mix(float(_7980 <= textureLod(shadow_map, _8999 + _8769, 0.0).x), float(_7980 <= textureLod(shadow_map, _8999 + _8752, 0.0).x), _9052), _8984.y);
                                    float mp_copy_9061 = _9061;
                                    highp vec2 _9095 = clamp(_7682 + (vec2(0.707099974155426025390625) * _18403), _8709, _8713);
                                    highp vec2 _9106 = (vec2(_9095.x, 1.0 - _9095.y) / _8709) - vec2(0.5);
                                    highp vec2 _9108 = floor(_9106);
                                    highp vec2 _9111 = _9106 - _9108;
                                    highp vec2 _9116 = (_9108 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9126 = vec2((_8737 + _9116.x) * _7986, _9116.y);
                                    highp float _9179 = _9111.x;
                                    highp float _9188 = mix(mix(float(_7980 <= textureLod(shadow_map, _9126, 0.0).x), float(_7980 <= textureLod(shadow_map, _9126 + _8761, 0.0).x), _9179), mix(float(_7980 <= textureLod(shadow_map, _9126 + _8769, 0.0).x), float(_7980 <= textureLod(shadow_map, _9126 + _8752, 0.0).x), _9179), _9111.y);
                                    float mp_copy_9188 = _9188;
                                    _18429 = (((mp_copy_8807 + mp_copy_8934) + mp_copy_9061) + mp_copy_9188) * 0.25;
                                }
                                else
                                {
                                    int _8183 = (_7994 > 0.5) ? 17 : 16;
                                    float _18423 = 0.0;
                                    _18423 = 0.0;
                                    float _8211 = 0.0;
                                    for (int _18405 = 0; _18405 < 17; _18423 = _8211, _18405++)
                                    {
                                        if (_18405 >= _8183)
                                        {
                                            break;
                                        }
                                        vec2 _18406 = vec2(0.0);
                                        do
                                        {
                                            if (_18405 == 0)
                                            {
                                                _18406 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_18405 == 1)
                                            {
                                                _18406 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_18405 == 2)
                                            {
                                                _18406 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_18405 == 3)
                                            {
                                                _18406 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_18405 == 4)
                                            {
                                                _18406 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_18405 == 5)
                                            {
                                                _18406 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_18405 == 6)
                                            {
                                                _18406 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_18405 == 7)
                                            {
                                                _18406 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_18405 == 8)
                                            {
                                                _18406 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_18405 == 9)
                                            {
                                                _18406 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_18405 == 10)
                                            {
                                                _18406 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_18405 == 11)
                                            {
                                                _18406 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_18405 == 12)
                                            {
                                                _18406 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_18405 == 13)
                                            {
                                                _18406 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_18405 == 14)
                                            {
                                                _18406 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_18405 == 15)
                                            {
                                                _18406 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _18406 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _18408 = vec2(0.0);
                                        do
                                        {
                                            if (_18405 < 3)
                                            {
                                                _18408 = vec2(float(_18405) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_18405 < 6)
                                            {
                                                _18408 = vec2((float(_18405 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_18405 < 11)
                                            {
                                                _18408 = vec2((float(_18405 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_18405 < 14)
                                            {
                                                _18408 = vec2((float(_18405 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _18408 = vec2(float(_18405 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8200 = mix(_18406, _18408, vec2(_7994));
                                        float _9328 = _8200.x;
                                        float _9332 = _8200.y;
                                        highp vec2 _9358 = clamp(_7682 + (vec2((_9328 * _18396) - (_9332 * _18400), (_9328 * _18400) + (_9332 * _18396)) * _18403), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9367 = _9358.y;
                                        highp vec2 _9368 = vec2((float(_17719) + _9358.x) * _7986, _9367);
                                        _9368.y = 1.0 - _9367;
                                        highp float _9380 = float(_7980 <= textureLod(shadow_map, _9368, 0.0).x);
                                        float mp_copy_9380 = _9380;
                                        _8211 = _18423 + mp_copy_9380;
                                    }
                                    _18429 = _18423 / float(_8183);
                                }
                                _18427 = _18429;
                            }
                            bool _8225 = _17719 == (_7592 - 1);
                            bool _8231 = false;
                            if (_8225)
                            {
                                _8231 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8231 = _8225;
                            }
                            float _18430 = 0.0;
                            if (_8231)
                            {
                                highp vec2 _8238 = vec2(frag_info.shadow_fade / _18363);
                                highp vec2 _8246 = smoothstep(vec2(0.0), _8238, _7682) * smoothstep(vec2(0.0), _8238, _7839);
                                _18430 = mix(1.0, _18427, _8246.x * _8246.y);
                            }
                            else
                            {
                                _18430 = _18427;
                            }
                            _18493 = _17723 + _7742;
                            _18490 = _17721 + (_7742 * _18430);
                        }
                        else
                        {
                            _18493 = _17723;
                            _18490 = _17721;
                        }
                        _18492 = _18493;
                        _18489 = _18490;
                    }
                    else
                    {
                        _18492 = _17723;
                        _18489 = _17721;
                    }
                    _18491 = _18492;
                    _18488 = _18489;
                }
                else
                {
                    _18491 = _17723;
                    _18488 = _17721;
                }
            }
            _17722 = _17723;
            _17720 = _17721;
        }
        else
        {
            _17722 = 0.0;
            _17720 = 0.0;
        }
        _17726 = mix(_17720 + (1.0 - _17722), 1.0, _17718);
    }
    else
    {
        _17726 = 1.0;
    }
    vec3 mp_copy_17727 = vec3(0.0);
    float _6856 = _6834 * _17726;
    bool _9387 = view_info.camera_forward.w > 0.5;
    highp vec3 _17727 = vec3(0.0);
    if (_9387)
    {
        _17727 = -view_info.camera_forward.xyz;
    }
    else
    {
        _17727 = normalize(v_viewvector);
    }
    highp float _9431 = 0.0;
    mp_copy_17727 = _17727;
    vec3 _6865 = mix(frag_info.dielectric_f0.xyz, _6796, vec3(_5904));
    float _6868 = dot(_17668, _17727);
    float _6869 = max(_6868, 0.0);
    float _6873 = max(dot(_5770, _17727), 0.0);
    vec3 _6877 = reflect(-mp_copy_17727, _17668);
    highp vec2 _17728 = vec2(0.0);
    do
    {
        _9431 = frag_info.punctual_dims.x;
        if (_9431 < 0.5)
        {
            _17728 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9443 = v_position - frag_info.camera_position.xyz;
            highp float _9458 = dot(_9443, frag_info.camera_forward.xyz);
            highp float _9464 = max(_9458, 9.9999997473787516355514526367188e-05);
            highp vec2 _9567 = (vec3(dot(_9443, frag_info.camera_right.xyz), dot(_9443, frag_info.camera_up.xyz), _9464).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9464, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _9582 = float(int(((((clamp(floor((log2(max(_9458 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9567.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9567.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _17728 = vec2(textureLod(punctual_index, vec2((mod(_9582, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9582 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _17728 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _6882 = int(_17728.x + 0.5);
    mediump int _6886 = int(_17728.y + 0.5);
    highp vec3 _18089 = vec3(0.0);
    _18089 = vec3(0.0);
    highp vec3 _18646 = vec3(0.0);
    for (int _17729 = 0; _17729 < _6886; _18089 = _18646, _17729++)
    {
        highp float _9615 = float(_6882 + _17729);
        highp float _9646 = (float(int(textureLod(punctual_index, vec2((mod(_9615, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9615 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9431;
        highp vec2 _9647 = vec2(0.0625, _9646);
        highp vec4 _9650 = textureLod(punctual_lights, _9647, 0.0);
        highp vec4 _9667 = textureLod(punctual_lights, vec2(0.1875, _9646), 0.0);
        highp float _6904 = _9650.w;
        highp vec3 _6906 = _9667.xyz;
        highp vec3 _18647 = vec3(0.0);
        if (_6904 > 2.5)
        {
            highp vec4 _9684 = textureLod(punctual_lights, vec2(0.3125, _9646), 0.0);
            highp vec4 _9701 = textureLod(punctual_lights, vec2(0.4375, _9646), 0.0);
            highp vec3 _6920 = _9684.xyz * (_9684.w * 0.5);
            highp vec3 _6926 = _9701.xyz * (_9701.w * 0.5);
            highp vec3 _6928 = _9650.xyz;
            highp vec3 _6930 = _6928 - _6920;
            highp vec3 _6932 = _6930 - _6926;
            highp vec3 _6936 = _6928 + _6920;
            highp vec3 _6938 = _6936 - _6926;
            highp vec3 _6950 = _6930 + _6926;
            highp vec3 _6954 = _6928 - v_position;
            highp float _6960 = _9667.w;
            highp float _6964 = (dot(_6954, _6954) * _6960) * _6960;
            highp float _6969 = clamp(1.0 - (_6964 * _6964), 0.0, 1.0);
            float mp_copy_6969 = _6969;
            vec2 _9708 = (clamp(vec2(_17716, sqrt(1.0 - _6869)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _9710 = _9708.x;
            float _9715 = _9708.y;
            vec4 _6993 = textureLod(brdf_lut, vec2((_9710 + 1.0) * 0.3333333432674407958984375, _9715), 0.0);
            vec4 _6997 = textureLod(brdf_lut, vec2((_9710 + 2.0) * 0.3333333432674407958984375, _9715), 0.0);
            vec3 _9758 = normalize(mp_copy_17727 - (_17668 * _6868));
            mat3 _9780 = transpose(mat3(_9758, -cross(_17668, _9758), _17668));
            mat3 _9781 = mat3(vec3(_6993.x, 0.0, _6993.y), vec3(0.0, 1.0, 0.0), vec3(_6993.z, 0.0, _6993.w)) * _9780;
            highp vec3 _9785 = _6932 - v_position;
            highp vec3 _9787 = normalize(_9781 * _9785);
            vec3 mp_copy_9787 = _9787;
            highp vec3 _9791 = _6938 - v_position;
            highp vec3 _9793 = normalize(_9781 * _9791);
            vec3 mp_copy_9793 = _9793;
            highp vec3 _9797 = (_6936 + _6926) - v_position;
            highp vec3 _9799 = normalize(_9781 * _9797);
            vec3 mp_copy_9799 = _9799;
            highp vec3 _9803 = _6950 - v_position;
            highp vec3 _9805 = normalize(_9781 * _9803);
            vec3 mp_copy_9805 = _9805;
            float _9834 = dot(_9787, _9793);
            float _9836 = abs(_9834);
            float _9850 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9836)) * _9836)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9836) * _9836));
            float _18299 = 0.0;
            if (_9834 > 0.0)
            {
                _18299 = _9850;
            }
            else
            {
                _18299 = (0.5 * inversesqrt(max(1.0 - (_9834 * _9834), 1.0000000116860974230803549289703e-07))) - _9850;
            }
            float _9883 = dot(_9793, _9799);
            float _9885 = abs(_9883);
            float _9899 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9885)) * _9885)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9885) * _9885));
            float _18300 = 0.0;
            if (_9883 > 0.0)
            {
                _18300 = _9899;
            }
            else
            {
                _18300 = (0.5 * inversesqrt(max(1.0 - (_9883 * _9883), 1.0000000116860974230803549289703e-07))) - _9899;
            }
            float _9932 = dot(_9799, _9805);
            float _9934 = abs(_9932);
            float _9948 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9934)) * _9934)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9934) * _9934));
            float _18301 = 0.0;
            if (_9932 > 0.0)
            {
                _18301 = _9948;
            }
            else
            {
                _18301 = (0.5 * inversesqrt(max(1.0 - (_9932 * _9932), 1.0000000116860974230803549289703e-07))) - _9948;
            }
            float _9981 = dot(_9805, _9787);
            float _9983 = abs(_9981);
            float _9997 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9983)) * _9983)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9983) * _9983));
            float _18302 = 0.0;
            if (_9981 > 0.0)
            {
                _18302 = _9997;
            }
            else
            {
                _18302 = (0.5 * inversesqrt(max(1.0 - (_9981 * _9981), 1.0000000116860974230803549289703e-07))) - _9997;
            }
            vec3 _9820 = (((cross(mp_copy_9787, mp_copy_9793) * _18299) + (cross(mp_copy_9793, mp_copy_9799) * _18300)) + (cross(mp_copy_9799, mp_copy_9805) * _18301)) + (cross(mp_copy_9805, mp_copy_9787) * _18302);
            float _10023 = length(_9820);
            mat3 _10083 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _9780;
            highp vec3 _10089 = normalize(_10083 * _9785);
            vec3 mp_copy_10089 = _10089;
            highp vec3 _10095 = normalize(_10083 * _9791);
            vec3 mp_copy_10095 = _10095;
            highp vec3 _10101 = normalize(_10083 * _9797);
            vec3 mp_copy_10101 = _10101;
            highp vec3 _10107 = normalize(_10083 * _9803);
            vec3 mp_copy_10107 = _10107;
            float _10136 = dot(_10089, _10095);
            float _10138 = abs(_10136);
            float _10152 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10138)) * _10138)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10138) * _10138));
            float _18303 = 0.0;
            if (_10136 > 0.0)
            {
                _18303 = _10152;
            }
            else
            {
                _18303 = (0.5 * inversesqrt(max(1.0 - (_10136 * _10136), 1.0000000116860974230803549289703e-07))) - _10152;
            }
            float _10185 = dot(_10095, _10101);
            float _10187 = abs(_10185);
            float _10201 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10187)) * _10187)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10187) * _10187));
            float _18304 = 0.0;
            if (_10185 > 0.0)
            {
                _18304 = _10201;
            }
            else
            {
                _18304 = (0.5 * inversesqrt(max(1.0 - (_10185 * _10185), 1.0000000116860974230803549289703e-07))) - _10201;
            }
            float _10234 = dot(_10101, _10107);
            float _10236 = abs(_10234);
            float _10250 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10236)) * _10236)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10236) * _10236));
            float _18305 = 0.0;
            if (_10234 > 0.0)
            {
                _18305 = _10250;
            }
            else
            {
                _18305 = (0.5 * inversesqrt(max(1.0 - (_10234 * _10234), 1.0000000116860974230803549289703e-07))) - _10250;
            }
            float _10283 = dot(_10107, _10089);
            float _10285 = abs(_10283);
            float _10299 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10285)) * _10285)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10285) * _10285));
            float _18306 = 0.0;
            if (_10283 > 0.0)
            {
                _18306 = _10299;
            }
            else
            {
                _18306 = (0.5 * inversesqrt(max(1.0 - (_10283 * _10283), 1.0000000116860974230803549289703e-07))) - _10299;
            }
            vec3 _10122 = (((cross(mp_copy_10089, mp_copy_10095) * _18303) + (cross(mp_copy_10095, mp_copy_10101) * _18304)) + (cross(mp_copy_10101, mp_copy_10107) * _18305)) + (cross(mp_copy_10107, mp_copy_10089) * _18306);
            float _10325 = length(_10122);
            _18647 = _18089 + (((_6906 * (mp_copy_6969 * mp_copy_6969)) * step(0.0, dot(cross(_6938 - _6932, _6950 - _6932), v_position - _6932))) * (((((_6865 * _6997.x) + ((vec3(1.0) - _6865) * _6997.y)) * max(((_10023 * _10023) + _9820.z) / (_10023 + 1.0), 0.0)) * 1.0) + ((_6796 * (1.0 - _5904)) * max(((_10325 * _10325) + _10122.z) / (_10325 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_18243 = 0.0;
            vec3 _18216 = vec3(0.0);
            highp vec3 _18239 = vec3(0.0);
            float _18243 = 0.0;
            if (_6904 < 0.5)
            {
                _18243 = _17716;
                _18239 = _6906;
                _18216 = -normalize(textureLod(punctual_lights, vec2(0.3125, _9646), 0.0).xyz);
            }
            else
            {
                highp vec3 _7084 = _9650.xyz - v_position;
                highp float _7087 = dot(_7084, _7084);
                highp float _7091 = inversesqrt(max(_7087, 9.9999999392252902907785028219223e-09));
                highp vec3 _7092 = _7084 * _7091;
                vec3 mp_copy_7092 = _7092;
                highp float _7094 = _9667.w;
                highp float _7099 = (_7087 * _7094) * _7094;
                highp float _7104 = clamp(1.0 - (_7099 * _7099), 0.0, 1.0);
                float mp_copy_7104 = _7104;
                if (_7104 <= 0.0)
                {
                    _18646 = _18089;
                    continue;
                }
                highp vec4 _10369 = textureLod(punctual_lights, vec2(0.4375, _9646), 0.0);
                highp float _7112 = _10369.w;
                float _18248 = 0.0;
                if (_7112 > 0.0)
                {
                    highp float _7139 = (_17716 * _17716) + ((_7112 * 0.5) * _7091);
                    float mp_copy_7139 = _7139;
                    _18248 = sqrt(min(mp_copy_7139, 1.0));
                }
                else
                {
                    _18248 = _17716;
                }
                highp vec3 _7146 = _6906 * ((mp_copy_7104 * mp_copy_7104) / max(pow(max(_7087, _7112 * _7112), _10369.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _18240 = vec3(0.0);
                if (_6904 > 1.5)
                {
                    highp vec4 _10386 = textureLod(punctual_lights, vec2(0.3125, _9646), 0.0);
                    highp float _7165 = clamp((dot(normalize(_10386.xyz), -mp_copy_7092) * _10386.w) + _10369.x, 0.0, 1.0);
                    float mp_copy_7165 = _7165;
                    highp vec3 _7170 = _7146 * (mp_copy_7165 * mp_copy_7165);
                    if (_7165 <= 0.0)
                    {
                        _18646 = _18089;
                        continue;
                    }
                    bool _7176 = _7165 > 0.0;
                    bool _7182 = false;
                    if (_7176)
                    {
                        _7182 = _10369.y > (-0.5);
                    }
                    else
                    {
                        _7182 = _7176;
                    }
                    bool _7188 = false;
                    if (_7182)
                    {
                        _7188 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7188 = _7182;
                    }
                    highp vec3 _18241 = vec3(0.0);
                    if (_7188)
                    {
                        float _18207 = 0.0;
                        do
                        {
                            highp vec4 _10498 = mat4(textureLod(punctual_lights, vec2(0.5625, _9646), 0.0), textureLod(punctual_lights, vec2(0.6875, _9646), 0.0), textureLod(punctual_lights, vec2(0.8125, _9646), 0.0), textureLod(punctual_lights, vec2(0.9375, _9646), 0.0)) * vec4(v_position + (_5770 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10500 = _10498.w;
                            if (_10500 <= 0.0)
                            {
                                _18207 = 1.0;
                                break;
                            }
                            highp vec3 _10509 = _10498.xyz / vec3(_10500);
                            highp vec2 _10514 = (_10509.xy * 0.5) + vec2(0.5);
                            highp float _10516 = _10514.x;
                            bool _10517 = _10516 < 0.0;
                            bool _10524 = false;
                            if (!_10517)
                            {
                                _10524 = _10516 > 1.0;
                            }
                            else
                            {
                                _10524 = _10517;
                            }
                            bool _10531 = false;
                            if (!_10524)
                            {
                                _10531 = _10514.y < 0.0;
                            }
                            else
                            {
                                _10531 = _10524;
                            }
                            bool _10538 = false;
                            if (!_10531)
                            {
                                _10538 = _10514.y > 1.0;
                            }
                            else
                            {
                                _10538 = _10531;
                            }
                            bool _10545 = false;
                            if (!_10538)
                            {
                                _10545 = _10509.z < 0.0;
                            }
                            else
                            {
                                _10545 = _10538;
                            }
                            bool _10552 = false;
                            if (!_10545)
                            {
                                _10552 = _10509.z > 1.0;
                            }
                            else
                            {
                                _10552 = _10545;
                            }
                            if (_10552)
                            {
                                _18207 = 1.0;
                                break;
                            }
                            highp float _10559 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _10564 = frag_info.shadow_cascade_count + float(int(_10369.y + 0.5));
                            highp float _10569 = _10509.z - frag_info.spot_shadow_params.y;
                            highp float _10580 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_10580 = _10580;
                            highp vec2 _10587 = vec2(cos(mp_copy_10580), sin(mp_copy_10580)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _10589 = _10587.x;
                            highp float _10591 = _10587.y;
                            highp vec2 _10599 = vec2(_10589 - _10591, _10589 + _10591) * 0.707106769084930419921875;
                            highp float _10792 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10516, 0.0, 1.0)) / _10559, 1.0 - clamp(_10514.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10792 = _10792;
                            highp vec2 _10607 = _10514 + _10587;
                            highp float _10814 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10607.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10607.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10814 = _10814;
                            highp vec2 _10615 = _10514 - _10587;
                            highp float _10836 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10615.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10615.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10836 = _10836;
                            highp vec2 _10628 = _10514 + vec2(-_10591, _10589);
                            highp float _10858 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10628.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10628.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10858 = _10858;
                            highp vec2 _10641 = _10514 + vec2(_10591, -_10589);
                            highp float _10880 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10641.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10641.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10880 = _10880;
                            float _10646 = (((mp_copy_10792 + mp_copy_10814) + mp_copy_10836) + mp_copy_10858) + mp_copy_10880;
                            if ((_10646 < 0.5) || (_10646 > 4.5))
                            {
                                _18207 = _10646 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _10658 = _10514 + _10599;
                            highp float _10902 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10658.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10658.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10902 = _10902;
                            highp vec2 _10665 = _10514 - _10599;
                            highp float _10924 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10665.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10665.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10924 = _10924;
                            highp float _10673 = _10599.y;
                            highp float _10676 = _10599.x;
                            highp vec2 _10678 = _10514 + vec2(-_10673, _10676);
                            highp float _10946 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10678.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10678.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10946 = _10946;
                            highp vec2 _10691 = _10514 + vec2(_10673, -_10676);
                            highp float _10968 = float(_10569 <= textureLod(shadow_map, vec2((_10564 + clamp(_10691.x, 0.0, 1.0)) / _10559, 1.0 - clamp(_10691.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10968 = _10968;
                            _18207 = (_10646 + (((mp_copy_10902 + mp_copy_10924) + mp_copy_10946) + mp_copy_10968)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18241 = _7170 * _18207;
                    }
                    else
                    {
                        _18241 = _7170;
                    }
                    _18240 = _18241;
                }
                else
                {
                    bool _7204 = _6904 > 0.5;
                    bool _7210 = false;
                    if (_7204)
                    {
                        _7210 = _10369.y > (-0.5);
                    }
                    else
                    {
                        _7210 = _7204;
                    }
                    bool _7216 = false;
                    if (_7210)
                    {
                        _7216 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7216 = _7210;
                    }
                    highp vec3 _18242 = vec3(0.0);
                    if (_7216)
                    {
                        float _18194 = 0.0;
                        do
                        {
                            highp vec4 _11281 = textureLod(punctual_lights, vec2(0.5625, _9646), 0.0);
                            highp vec4 _11298 = textureLod(punctual_lights, vec2(0.6875, _9646), 0.0);
                            highp vec3 _11040 = (v_position + (_5770 * _11281.z)) - textureLod(punctual_lights, _9647, 0.0).xyz;
                            highp vec3 _11042 = abs(_11040);
                            highp float _11044 = _11042.x;
                            highp float _11046 = _11042.y;
                            bool _11047 = _11044 >= _11046;
                            bool _11055 = false;
                            if (_11047)
                            {
                                _11055 = _11044 >= _11042.z;
                            }
                            else
                            {
                                _11055 = _11047;
                            }
                            highp vec3 _18184 = vec3(0.0);
                            float _18186 = 0.0;
                            if (_11055)
                            {
                                highp float _11058 = _11040.x;
                                bool _11059 = _11058 >= 0.0;
                                highp vec3 _18183 = vec3(0.0);
                                if (_11059)
                                {
                                    _18183 = vec3(-_11040.z, _11040.y, _11058);
                                }
                                else
                                {
                                    _18183 = vec3(_11040.zy, -_11058);
                                }
                                _18186 = _11059 ? 0.0 : 1.0;
                                _18184 = _18183;
                            }
                            else
                            {
                                highp vec3 _18185 = vec3(0.0);
                                float _18188 = 0.0;
                                if (_11046 >= _11042.z)
                                {
                                    highp float _11092 = _11040.y;
                                    bool _11093 = _11092 >= 0.0;
                                    highp vec3 _18182 = vec3(0.0);
                                    if (_11093)
                                    {
                                        _18182 = vec3(-_11040.x, _11040.z, _11092);
                                    }
                                    else
                                    {
                                        _18182 = vec3(_11040.xz, -_11092);
                                    }
                                    _18188 = _11093 ? 2.0 : 3.0;
                                    _18185 = _18182;
                                }
                                else
                                {
                                    highp float _11120 = _11040.z;
                                    bool _11121 = _11120 >= 0.0;
                                    highp vec3 _18181 = vec3(0.0);
                                    if (_11121)
                                    {
                                        _18181 = _11040;
                                    }
                                    else
                                    {
                                        _18181 = vec3(-_11040.x, _11040.y, -_11120);
                                    }
                                    _18188 = _11121 ? 4.0 : 5.0;
                                    _18185 = _18181;
                                }
                                _18186 = _18188;
                                _18184 = _18185;
                            }
                            if (_18184.z <= 0.0)
                            {
                                _18194 = 1.0;
                                break;
                            }
                            highp vec2 _11161 = ((_18184.xy / vec2(_18184.z)) * 0.5) + vec2(0.5);
                            highp float _11172 = (_11281.x - (_11281.y / _18184.z)) - _11298.x;
                            if ((_11172 < 0.0) || (_11172 > 1.0))
                            {
                                _18194 = 1.0;
                                break;
                            }
                            highp float hp_copy_18191 = 0.0;
                            highp float _11184 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _11190 = _18186 >= 4.0;
                            highp float _11192 = (frag_info.shadow_cascade_count + _10369.y) + float(_11190);
                            float _18191 = 0.0;
                            if (_11190)
                            {
                                _18191 = _18186 - 4.0;
                            }
                            else
                            {
                                _18191 = _18186;
                            }
                            hp_copy_18191 = _18191;
                            highp float _11209 = _11298.y * 0.5;
                            highp float _11212 = _11281.w * 0.0040000001899898052215576171875;
                            highp vec2 _11323 = vec2(_11209);
                            highp vec2 _11326 = vec2(1.0 - _11209);
                            highp vec2 _11332 = vec2(mod(hp_copy_18191, 2.0), 1.0 - floor(hp_copy_18191 * 0.5)) * 0.5;
                            highp vec2 _11335 = _11332 + (clamp(_11161, _11323, _11326) * 0.5);
                            highp float _11228 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _18193 = 0.0;
                            _18193 = float(_11172 <= textureLod(shadow_map, vec2((_11192 + _11335.x) / _11184, 1.0 - _11335.y), 0.0).x);
                            for (int _18192 = 0; _18192 < 8; )
                            {
                                highp float _11238 = _11228 + (float(_18192) * 0.785398185253143310546875);
                                float mp_copy_11238 = _11238;
                                highp vec2 _11372 = _11332 + (clamp(_11161 + (vec2(cos(mp_copy_11238), sin(mp_copy_11238)) * _11212), _11323, _11326) * 0.5);
                                highp float _11389 = float(_11172 <= textureLod(shadow_map, vec2((_11192 + _11372.x) / _11184, 1.0 - _11372.y), 0.0).x);
                                float mp_copy_11389 = _11389;
                                _18193 += mp_copy_11389;
                                _18192++;
                                continue;
                            }
                            _18194 = _18193 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18242 = _7146 * _18194;
                    }
                    else
                    {
                        _18242 = _7146;
                    }
                    _18240 = _18242;
                }
                _18243 = _18248;
                _18239 = _18240;
                _18216 = _7092;
            }
            hp_copy_18243 = _18243;
            highp vec3 _18270 = vec3(0.0);
            highp vec3 _18271 = vec3(0.0);
            do
            {
                float _11455 = max(dot(_17668, _18216), 0.0);
                highp float hp_copy_11455 = _11455;
                if (_11455 <= 0.0)
                {
                    _18271 = vec3(0.0);
                    _18270 = vec3(0.0);
                    break;
                }
                float _11461 = max(_6869, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11461 = _11461;
                vec3 _11464 = _18216 + mp_copy_17727;
                float _11467 = dot(_11464, _11464);
                vec3 _18268 = vec3(0.0);
                vec3 _18269 = vec3(0.0);
                if (_11467 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11475 = _11464 * inversesqrt(_11467);
                    float _18267 = 0.0;
                    do
                    {
                        float _11532 = dot(_17668, _11475);
                        if (_11532 <= 0.0)
                        {
                            _18267 = 0.0;
                            break;
                        }
                        float _11539 = _18243 * _18243;
                        vec3 _11542 = cross(_17668, _11475);
                        float _11545 = _11532 * _11539;
                        float _11554 = _11539 / (dot(_11542, _11542) + (_11545 * _11545));
                        _18267 = min((_11554 * _11554) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _11592 = _6865 + ((vec3(1.0) - _6865) * pow(clamp(1.0 - max(dot(_11475, _17727), 0.0), 0.0, 1.0), 5.0));
                    _18269 = (_11592 * min(_18267 * (0.5 / max(mix((2.0 * hp_copy_11455) * _11461, hp_copy_11455 + hp_copy_11461, hp_copy_18243 * hp_copy_18243), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _18268 = _11592;
                }
                else
                {
                    _18269 = vec3(0.0);
                    _18268 = _6865;
                }
                _18271 = (_18269 * _18239) * _11455;
                _18270 = (((((vec3(1.0) - _18268) * (1.0 - _5904)) * _6796) * 0.3183098733425140380859375) * _18239) * _11455;
                break;
            } while(false);
            _18647 = _18089 + (_18270 + _18271);
        }
        _18646 = _18647;
    }
    mat3 _7264 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _7272 = _7264 * vec3(_17668.x, _17668.y, _17668.z);
    vec3 _17730 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _11639 = _6877 + (((step(vec3(0.0), _6877) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_11639 = _11639;
        highp vec3 _11641 = vec3(1.0) / hp_copy_11639;
        highp vec3 _11658 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _11641, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _11641);
        _17730 = normalize((v_position + (_6877 * max(min(min(_11658.x, _11658.y), _11658.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _17730 = _6877;
    }
    bool _11886 = false;
    vec3 _7277 = _7264 * _17730;
    float _11705 = _7272.y;
    float _11706 = 0.48860299587249755859375 * _11705;
    float _11712 = _7272.z;
    float _11713 = 0.48860299587249755859375 * _11712;
    float _11719 = _7272.x;
    float _11720 = 0.48860299587249755859375 * _11719;
    float _11727 = 1.09254801273345947265625 * _11719;
    float _11730 = _11727 * _11705;
    float _11740 = (1.09254801273345947265625 * _11705) * _11712;
    float _11752 = 0.3153919875621795654296875 * (((3.0 * _11712) * _11712) - 1.0);
    float _11762 = _11727 * _11712;
    float _11778 = 0.546274006366729736328125 * ((_11719 * _11719) - (_11705 * _11705));
    vec3 _7280 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _11706)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _11713)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _11720)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _11730)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _11740)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _11752)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _11762)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _11778), vec3(0.0));
    vec3 _17731 = vec3(0.0);
    do
    {
        _11886 = radiance_layout_info.mip_layout > 0.5;
        if (_11886)
        {
            vec2 _11965 = vec2(atan(_7277.z, _7277.x), asin(clamp(_7277.y, -1.0, 1.0)));
            highp vec2 hp_copy_11965 = _11965;
            _17731 = textureLod(prefiltered_radiance, (hp_copy_11965 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17716, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _11984 = vec2(atan(_7277.z, _7277.x), asin(clamp(_7277.y, -1.0, 1.0)));
        highp vec2 hp_copy_11984 = _11984;
        highp vec2 _11989 = (hp_copy_11984 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _11896 = clamp(_11989.y, 0.00390625, 0.99609375);
        float _11900 = clamp(_17716, 0.0, 1.0) * 7.0;
        float _11902 = floor(_11900);
        highp float _11921 = _11989.x;
        _17731 = mix(textureLod(prefiltered_radiance, vec2(_11921, (_11902 + _11896) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_11921, (min(_11902 + 1.0, 7.0) + _11896) * 0.125), 0.0).xyz, vec3(_11900 - _11902));
        break;
    } while(false);
    bool _7287 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _17736 = vec3(0.0);
    highp vec3 _17737 = vec3(0.0);
    if (_7287)
    {
        vec3 _17732 = vec3(0.0);
        do
        {
            if (_11886)
            {
                vec2 _12277 = vec2(atan(_7277.z, _7277.x), asin(clamp(_7277.y, -1.0, 1.0)));
                highp vec2 hp_copy_12277 = _12277;
                _17732 = textureLod(prefiltered_radiance_b, (hp_copy_12277 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17716, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _12296 = vec2(atan(_7277.z, _7277.x), asin(clamp(_7277.y, -1.0, 1.0)));
            highp vec2 hp_copy_12296 = _12296;
            highp vec2 _12301 = (hp_copy_12296 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12208 = clamp(_12301.y, 0.00390625, 0.99609375);
            float _12212 = clamp(_17716, 0.0, 1.0) * 7.0;
            float _12214 = floor(_12212);
            highp float _12233 = _12301.x;
            _17732 = mix(textureLod(prefiltered_radiance_b, vec2(_12233, (_12214 + _12208) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12233, (min(_12214 + 1.0, 7.0) + _12208) * 0.125), 0.0).xyz, vec3(_12212 - _12214));
            break;
        } while(false);
        highp vec3 _7298 = vec3(frag_info.radiance_blend.x);
        _17737 = mix(_17731, _17732, _7298);
        _17736 = mix(_7280, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _11706)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _11713)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _11720)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _11730)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _11740)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _11752)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _11762)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _11778), vec3(0.0)), _7298);
    }
    else
    {
        _17737 = _17731;
        _17736 = _7280;
    }
    highp float _12314 = 0.0;
    highp vec3 _7309 = _17736 * frag_info.environment_intensity;
    float _17738 = 0.0;
    do
    {
        _12314 = frag_info.gi_grid.w;
        if (_12314 <= 0.0)
        {
            _17738 = 0.0;
            break;
        }
        highp vec3 _12327 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _12335 = min(_12327, (frag_info.gi_counts.xyz - vec3(1.0)) - _12327);
        _17738 = clamp(min(_12335.x, min(_12335.y, _12335.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _17929 = vec3(0.0);
    if (_17738 > 0.0)
    {
        highp vec3 _12427 = v_position + (((_17668 * 0.20000000298023223876953125) + (mp_copy_17727 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _12430 = _12427 / frag_info.gi_grid.xyz;
        highp vec3 _12432 = floor(_12430);
        highp vec3 _12438 = clamp(_12430 - _12432, vec3(0.0), vec3(1.0));
        vec3 mp_copy_12438 = _12438;
        highp vec3 _12560 = _12432 - frag_info.gi_anchor.xyz;
        bool _12563 = any(lessThan(_12560, vec3(0.0)));
        bool _12571 = false;
        if (!_12563)
        {
            _12571 = any(greaterThanEqual(_12560, frag_info.gi_counts.xyz));
        }
        else
        {
            _12571 = _12563;
        }
        vec3 mp_copy_17739 = vec3(0.0);
        highp float _12572 = _12571 ? 0.0 : 1.0;
        float mp_copy_12572 = _12572;
        vec3 _12574 = vec3(1.0) - mp_copy_12438;
        vec3 _12578 = max(_12574, vec3(0.001000000047497451305389404296875));
        highp vec3 _12594 = (_12432 * frag_info.gi_grid.xyz) - _12427;
        highp float _12596 = length(_12594);
        highp vec3 _17739 = vec3(0.0);
        if (_12596 > 9.9999997473787516355514526367188e-06)
        {
            _17739 = _12594 / vec3(_12596);
        }
        else
        {
            _17739 = _17668;
        }
        mp_copy_17739 = _17739;
        float _12614 = pow((dot(_17739, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12739 = _12432 - (frag_info.gi_counts.xyz * floor(_12432 / frag_info.gi_counts.xyz));
        highp float _12755 = _12739.x + (frag_info.gi_counts.x * (_12739.y + (frag_info.gi_counts.y * _12739.z)));
        bool _12625 = frag_info.gi_visibility.x > 0.0;
        float _17744 = 0.0;
        if (_12625)
        {
            highp float _12763 = floor(_12755 / frag_info.gi_counts.w);
            highp vec2 _12777 = vec2((_12755 - (_12763 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12763 * 16.0));
            vec3 _12637 = -mp_copy_17739;
            vec3 _12825 = _12637 / vec3((abs(_12637.x) + abs(_12637.y)) + abs(_12637.z));
            vec2 _17740 = vec2(0.0);
            if (_12825.z >= 0.0)
            {
                _17740 = _12825.xy;
            }
            else
            {
                _17740 = (vec2(1.0) - abs(_12825.yx)) * vec2((_12825.x >= 0.0) ? 1.0 : (-1.0), (_12825.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12641 = texture(irradiance_field, clamp((_12777 + vec2(1.0)) + (clamp((_17740 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12777 + vec2(0.5), _12777 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12646 = _12641.x * frag_info.gi_visibility.z;
            highp float _12658 = abs((_12646 * _12646) - ((_12641.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12664 = (_12596 - _12646) - frag_info.gi_visibility.y;
            highp float _17741 = 0.0;
            if (_12664 <= 0.0)
            {
                _17741 = 1.0;
            }
            else
            {
                _17741 = _12658 / (_12658 + (_12664 * _12664));
            }
            _17744 = _12614 * mix(1.0, max(0.0500000007450580596923828125, (_17741 * _17741) * _17741), frag_info.gi_visibility.x);
        }
        else
        {
            _17744 = _12614;
        }
        float _12692 = max(9.9999999747524270787835121154785e-07, _17744);
        float _17745 = 0.0;
        if (_12692 < 0.20000000298023223876953125)
        {
            _17745 = _12692 * ((_12692 * _12692) * 25.0);
        }
        else
        {
            _17745 = _12692;
        }
        float _12707 = _17745 * (((_12578.x * _12578.y) * _12578.z) * mp_copy_12572);
        highp float _12866 = floor(_12755 / frag_info.gi_counts.w);
        highp vec2 _12880 = vec2((_12755 - (_12866 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12866 * 8.0));
        vec3 _12928 = _17668 / vec3((abs(_17668.x) + abs(_17668.y)) + abs(_17668.z));
        bool _12931 = _12928.z >= 0.0;
        vec2 _17746 = vec2(0.0);
        if (_12931)
        {
            _17746 = _12928.xy;
        }
        else
        {
            _17746 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12719 = texture(irradiance_field, clamp((_12880 + vec2(1.0)) + (clamp((_17746 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12880 + vec2(0.5), _12880 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13014 = _12432 + vec3(1.0, 0.0, 0.0);
        highp vec3 _13019 = _13014 - frag_info.gi_anchor.xyz;
        bool _13022 = any(lessThan(_13019, vec3(0.0)));
        bool _13030 = false;
        if (!_13022)
        {
            _13030 = any(greaterThanEqual(_13019, frag_info.gi_counts.xyz));
        }
        else
        {
            _13030 = _13022;
        }
        vec3 mp_copy_17748 = vec3(0.0);
        highp float _13031 = _13030 ? 0.0 : 1.0;
        float mp_copy_13031 = _13031;
        vec3 _13037 = max(mix(_12574, mp_copy_12438, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13053 = (_13014 * frag_info.gi_grid.xyz) - _12427;
        highp float _13055 = length(_13053);
        highp vec3 _17748 = vec3(0.0);
        if (_13055 > 9.9999997473787516355514526367188e-06)
        {
            _17748 = _13053 / vec3(_13055);
        }
        else
        {
            _17748 = _17668;
        }
        mp_copy_17748 = _17748;
        float _13073 = pow((dot(_17748, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13198 = _13014 - (frag_info.gi_counts.xyz * floor(_13014 / frag_info.gi_counts.xyz));
        highp float _13214 = _13198.x + (frag_info.gi_counts.x * (_13198.y + (frag_info.gi_counts.y * _13198.z)));
        float _17753 = 0.0;
        if (_12625)
        {
            highp float _13222 = floor(_13214 / frag_info.gi_counts.w);
            highp vec2 _13236 = vec2((_13214 - (_13222 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13222 * 16.0));
            vec3 _13096 = -mp_copy_17748;
            vec3 _13284 = _13096 / vec3((abs(_13096.x) + abs(_13096.y)) + abs(_13096.z));
            vec2 _17749 = vec2(0.0);
            if (_13284.z >= 0.0)
            {
                _17749 = _13284.xy;
            }
            else
            {
                _17749 = (vec2(1.0) - abs(_13284.yx)) * vec2((_13284.x >= 0.0) ? 1.0 : (-1.0), (_13284.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13100 = texture(irradiance_field, clamp((_13236 + vec2(1.0)) + (clamp((_17749 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13236 + vec2(0.5), _13236 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13105 = _13100.x * frag_info.gi_visibility.z;
            highp float _13117 = abs((_13105 * _13105) - ((_13100.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13123 = (_13055 - _13105) - frag_info.gi_visibility.y;
            highp float _17750 = 0.0;
            if (_13123 <= 0.0)
            {
                _17750 = 1.0;
            }
            else
            {
                _17750 = _13117 / (_13117 + (_13123 * _13123));
            }
            _17753 = _13073 * mix(1.0, max(0.0500000007450580596923828125, (_17750 * _17750) * _17750), frag_info.gi_visibility.x);
        }
        else
        {
            _17753 = _13073;
        }
        float _13151 = max(9.9999999747524270787835121154785e-07, _17753);
        float _17754 = 0.0;
        if (_13151 < 0.20000000298023223876953125)
        {
            _17754 = _13151 * ((_13151 * _13151) * 25.0);
        }
        else
        {
            _17754 = _13151;
        }
        float _13166 = _17754 * (((_13037.x * _13037.y) * _13037.z) * mp_copy_13031);
        highp float _13325 = floor(_13214 / frag_info.gi_counts.w);
        highp vec2 _13339 = vec2((_13214 - (_13325 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13325 * 8.0));
        vec2 _17755 = vec2(0.0);
        if (_12931)
        {
            _17755 = _12928.xy;
        }
        else
        {
            _17755 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13178 = texture(irradiance_field, clamp((_13339 + vec2(1.0)) + (clamp((_17755 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13339 + vec2(0.5), _13339 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13473 = _12432 + vec3(0.0, 1.0, 0.0);
        highp vec3 _13478 = _13473 - frag_info.gi_anchor.xyz;
        bool _13481 = any(lessThan(_13478, vec3(0.0)));
        bool _13489 = false;
        if (!_13481)
        {
            _13489 = any(greaterThanEqual(_13478, frag_info.gi_counts.xyz));
        }
        else
        {
            _13489 = _13481;
        }
        vec3 mp_copy_17757 = vec3(0.0);
        highp float _13490 = _13489 ? 0.0 : 1.0;
        float mp_copy_13490 = _13490;
        vec3 _13496 = max(mix(_12574, mp_copy_12438, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13512 = (_13473 * frag_info.gi_grid.xyz) - _12427;
        highp float _13514 = length(_13512);
        highp vec3 _17757 = vec3(0.0);
        if (_13514 > 9.9999997473787516355514526367188e-06)
        {
            _17757 = _13512 / vec3(_13514);
        }
        else
        {
            _17757 = _17668;
        }
        mp_copy_17757 = _17757;
        float _13532 = pow((dot(_17757, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13657 = _13473 - (frag_info.gi_counts.xyz * floor(_13473 / frag_info.gi_counts.xyz));
        highp float _13673 = _13657.x + (frag_info.gi_counts.x * (_13657.y + (frag_info.gi_counts.y * _13657.z)));
        float _17762 = 0.0;
        if (_12625)
        {
            highp float _13681 = floor(_13673 / frag_info.gi_counts.w);
            highp vec2 _13695 = vec2((_13673 - (_13681 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13681 * 16.0));
            vec3 _13555 = -mp_copy_17757;
            vec3 _13743 = _13555 / vec3((abs(_13555.x) + abs(_13555.y)) + abs(_13555.z));
            vec2 _17758 = vec2(0.0);
            if (_13743.z >= 0.0)
            {
                _17758 = _13743.xy;
            }
            else
            {
                _17758 = (vec2(1.0) - abs(_13743.yx)) * vec2((_13743.x >= 0.0) ? 1.0 : (-1.0), (_13743.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13559 = texture(irradiance_field, clamp((_13695 + vec2(1.0)) + (clamp((_17758 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13695 + vec2(0.5), _13695 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13564 = _13559.x * frag_info.gi_visibility.z;
            highp float _13576 = abs((_13564 * _13564) - ((_13559.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13582 = (_13514 - _13564) - frag_info.gi_visibility.y;
            highp float _17759 = 0.0;
            if (_13582 <= 0.0)
            {
                _17759 = 1.0;
            }
            else
            {
                _17759 = _13576 / (_13576 + (_13582 * _13582));
            }
            _17762 = _13532 * mix(1.0, max(0.0500000007450580596923828125, (_17759 * _17759) * _17759), frag_info.gi_visibility.x);
        }
        else
        {
            _17762 = _13532;
        }
        float _13610 = max(9.9999999747524270787835121154785e-07, _17762);
        float _17763 = 0.0;
        if (_13610 < 0.20000000298023223876953125)
        {
            _17763 = _13610 * ((_13610 * _13610) * 25.0);
        }
        else
        {
            _17763 = _13610;
        }
        float _13625 = _17763 * (((_13496.x * _13496.y) * _13496.z) * mp_copy_13490);
        highp float _13784 = floor(_13673 / frag_info.gi_counts.w);
        highp vec2 _13798 = vec2((_13673 - (_13784 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13784 * 8.0));
        vec2 _17764 = vec2(0.0);
        if (_12931)
        {
            _17764 = _12928.xy;
        }
        else
        {
            _17764 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13637 = texture(irradiance_field, clamp((_13798 + vec2(1.0)) + (clamp((_17764 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13798 + vec2(0.5), _13798 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13932 = _12432 + vec3(1.0, 1.0, 0.0);
        highp vec3 _13937 = _13932 - frag_info.gi_anchor.xyz;
        bool _13940 = any(lessThan(_13937, vec3(0.0)));
        bool _13948 = false;
        if (!_13940)
        {
            _13948 = any(greaterThanEqual(_13937, frag_info.gi_counts.xyz));
        }
        else
        {
            _13948 = _13940;
        }
        vec3 mp_copy_17766 = vec3(0.0);
        highp float _13949 = _13948 ? 0.0 : 1.0;
        float mp_copy_13949 = _13949;
        vec3 _13955 = max(mix(_12574, mp_copy_12438, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13971 = (_13932 * frag_info.gi_grid.xyz) - _12427;
        highp float _13973 = length(_13971);
        highp vec3 _17766 = vec3(0.0);
        if (_13973 > 9.9999997473787516355514526367188e-06)
        {
            _17766 = _13971 / vec3(_13973);
        }
        else
        {
            _17766 = _17668;
        }
        mp_copy_17766 = _17766;
        float _13991 = pow((dot(_17766, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14116 = _13932 - (frag_info.gi_counts.xyz * floor(_13932 / frag_info.gi_counts.xyz));
        highp float _14132 = _14116.x + (frag_info.gi_counts.x * (_14116.y + (frag_info.gi_counts.y * _14116.z)));
        float _17771 = 0.0;
        if (_12625)
        {
            highp float _14140 = floor(_14132 / frag_info.gi_counts.w);
            highp vec2 _14154 = vec2((_14132 - (_14140 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14140 * 16.0));
            vec3 _14014 = -mp_copy_17766;
            vec3 _14202 = _14014 / vec3((abs(_14014.x) + abs(_14014.y)) + abs(_14014.z));
            vec2 _17767 = vec2(0.0);
            if (_14202.z >= 0.0)
            {
                _17767 = _14202.xy;
            }
            else
            {
                _17767 = (vec2(1.0) - abs(_14202.yx)) * vec2((_14202.x >= 0.0) ? 1.0 : (-1.0), (_14202.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14018 = texture(irradiance_field, clamp((_14154 + vec2(1.0)) + (clamp((_17767 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14154 + vec2(0.5), _14154 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14023 = _14018.x * frag_info.gi_visibility.z;
            highp float _14035 = abs((_14023 * _14023) - ((_14018.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14041 = (_13973 - _14023) - frag_info.gi_visibility.y;
            highp float _17768 = 0.0;
            if (_14041 <= 0.0)
            {
                _17768 = 1.0;
            }
            else
            {
                _17768 = _14035 / (_14035 + (_14041 * _14041));
            }
            _17771 = _13991 * mix(1.0, max(0.0500000007450580596923828125, (_17768 * _17768) * _17768), frag_info.gi_visibility.x);
        }
        else
        {
            _17771 = _13991;
        }
        float _14069 = max(9.9999999747524270787835121154785e-07, _17771);
        float _17772 = 0.0;
        if (_14069 < 0.20000000298023223876953125)
        {
            _17772 = _14069 * ((_14069 * _14069) * 25.0);
        }
        else
        {
            _17772 = _14069;
        }
        float _14084 = _17772 * (((_13955.x * _13955.y) * _13955.z) * mp_copy_13949);
        highp float _14243 = floor(_14132 / frag_info.gi_counts.w);
        highp vec2 _14257 = vec2((_14132 - (_14243 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14243 * 8.0));
        vec2 _17773 = vec2(0.0);
        if (_12931)
        {
            _17773 = _12928.xy;
        }
        else
        {
            _17773 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14096 = texture(irradiance_field, clamp((_14257 + vec2(1.0)) + (clamp((_17773 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14257 + vec2(0.5), _14257 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14391 = _12432 + vec3(0.0, 0.0, 1.0);
        highp vec3 _14396 = _14391 - frag_info.gi_anchor.xyz;
        bool _14399 = any(lessThan(_14396, vec3(0.0)));
        bool _14407 = false;
        if (!_14399)
        {
            _14407 = any(greaterThanEqual(_14396, frag_info.gi_counts.xyz));
        }
        else
        {
            _14407 = _14399;
        }
        vec3 mp_copy_17775 = vec3(0.0);
        highp float _14408 = _14407 ? 0.0 : 1.0;
        float mp_copy_14408 = _14408;
        vec3 _14414 = max(mix(_12574, mp_copy_12438, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14430 = (_14391 * frag_info.gi_grid.xyz) - _12427;
        highp float _14432 = length(_14430);
        highp vec3 _17775 = vec3(0.0);
        if (_14432 > 9.9999997473787516355514526367188e-06)
        {
            _17775 = _14430 / vec3(_14432);
        }
        else
        {
            _17775 = _17668;
        }
        mp_copy_17775 = _17775;
        float _14450 = pow((dot(_17775, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14575 = _14391 - (frag_info.gi_counts.xyz * floor(_14391 / frag_info.gi_counts.xyz));
        highp float _14591 = _14575.x + (frag_info.gi_counts.x * (_14575.y + (frag_info.gi_counts.y * _14575.z)));
        float _17780 = 0.0;
        if (_12625)
        {
            highp float _14599 = floor(_14591 / frag_info.gi_counts.w);
            highp vec2 _14613 = vec2((_14591 - (_14599 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14599 * 16.0));
            vec3 _14473 = -mp_copy_17775;
            vec3 _14661 = _14473 / vec3((abs(_14473.x) + abs(_14473.y)) + abs(_14473.z));
            vec2 _17776 = vec2(0.0);
            if (_14661.z >= 0.0)
            {
                _17776 = _14661.xy;
            }
            else
            {
                _17776 = (vec2(1.0) - abs(_14661.yx)) * vec2((_14661.x >= 0.0) ? 1.0 : (-1.0), (_14661.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14477 = texture(irradiance_field, clamp((_14613 + vec2(1.0)) + (clamp((_17776 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14613 + vec2(0.5), _14613 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14482 = _14477.x * frag_info.gi_visibility.z;
            highp float _14494 = abs((_14482 * _14482) - ((_14477.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14500 = (_14432 - _14482) - frag_info.gi_visibility.y;
            highp float _17777 = 0.0;
            if (_14500 <= 0.0)
            {
                _17777 = 1.0;
            }
            else
            {
                _17777 = _14494 / (_14494 + (_14500 * _14500));
            }
            _17780 = _14450 * mix(1.0, max(0.0500000007450580596923828125, (_17777 * _17777) * _17777), frag_info.gi_visibility.x);
        }
        else
        {
            _17780 = _14450;
        }
        float _14528 = max(9.9999999747524270787835121154785e-07, _17780);
        float _17781 = 0.0;
        if (_14528 < 0.20000000298023223876953125)
        {
            _17781 = _14528 * ((_14528 * _14528) * 25.0);
        }
        else
        {
            _17781 = _14528;
        }
        float _14543 = _17781 * (((_14414.x * _14414.y) * _14414.z) * mp_copy_14408);
        highp float _14702 = floor(_14591 / frag_info.gi_counts.w);
        highp vec2 _14716 = vec2((_14591 - (_14702 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14702 * 8.0));
        vec2 _17782 = vec2(0.0);
        if (_12931)
        {
            _17782 = _12928.xy;
        }
        else
        {
            _17782 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14555 = texture(irradiance_field, clamp((_14716 + vec2(1.0)) + (clamp((_17782 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14716 + vec2(0.5), _14716 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14850 = _12432 + vec3(1.0, 0.0, 1.0);
        highp vec3 _14855 = _14850 - frag_info.gi_anchor.xyz;
        bool _14858 = any(lessThan(_14855, vec3(0.0)));
        bool _14866 = false;
        if (!_14858)
        {
            _14866 = any(greaterThanEqual(_14855, frag_info.gi_counts.xyz));
        }
        else
        {
            _14866 = _14858;
        }
        vec3 mp_copy_17784 = vec3(0.0);
        highp float _14867 = _14866 ? 0.0 : 1.0;
        float mp_copy_14867 = _14867;
        vec3 _14873 = max(mix(_12574, mp_copy_12438, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14889 = (_14850 * frag_info.gi_grid.xyz) - _12427;
        highp float _14891 = length(_14889);
        highp vec3 _17784 = vec3(0.0);
        if (_14891 > 9.9999997473787516355514526367188e-06)
        {
            _17784 = _14889 / vec3(_14891);
        }
        else
        {
            _17784 = _17668;
        }
        mp_copy_17784 = _17784;
        float _14909 = pow((dot(_17784, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15034 = _14850 - (frag_info.gi_counts.xyz * floor(_14850 / frag_info.gi_counts.xyz));
        highp float _15050 = _15034.x + (frag_info.gi_counts.x * (_15034.y + (frag_info.gi_counts.y * _15034.z)));
        float _17789 = 0.0;
        if (_12625)
        {
            highp float _15058 = floor(_15050 / frag_info.gi_counts.w);
            highp vec2 _15072 = vec2((_15050 - (_15058 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15058 * 16.0));
            vec3 _14932 = -mp_copy_17784;
            vec3 _15120 = _14932 / vec3((abs(_14932.x) + abs(_14932.y)) + abs(_14932.z));
            vec2 _17785 = vec2(0.0);
            if (_15120.z >= 0.0)
            {
                _17785 = _15120.xy;
            }
            else
            {
                _17785 = (vec2(1.0) - abs(_15120.yx)) * vec2((_15120.x >= 0.0) ? 1.0 : (-1.0), (_15120.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14936 = texture(irradiance_field, clamp((_15072 + vec2(1.0)) + (clamp((_17785 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15072 + vec2(0.5), _15072 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14941 = _14936.x * frag_info.gi_visibility.z;
            highp float _14953 = abs((_14941 * _14941) - ((_14936.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14959 = (_14891 - _14941) - frag_info.gi_visibility.y;
            highp float _17786 = 0.0;
            if (_14959 <= 0.0)
            {
                _17786 = 1.0;
            }
            else
            {
                _17786 = _14953 / (_14953 + (_14959 * _14959));
            }
            _17789 = _14909 * mix(1.0, max(0.0500000007450580596923828125, (_17786 * _17786) * _17786), frag_info.gi_visibility.x);
        }
        else
        {
            _17789 = _14909;
        }
        float _14987 = max(9.9999999747524270787835121154785e-07, _17789);
        float _17790 = 0.0;
        if (_14987 < 0.20000000298023223876953125)
        {
            _17790 = _14987 * ((_14987 * _14987) * 25.0);
        }
        else
        {
            _17790 = _14987;
        }
        float _15002 = _17790 * (((_14873.x * _14873.y) * _14873.z) * mp_copy_14867);
        highp float _15161 = floor(_15050 / frag_info.gi_counts.w);
        highp vec2 _15175 = vec2((_15050 - (_15161 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15161 * 8.0));
        vec2 _17791 = vec2(0.0);
        if (_12931)
        {
            _17791 = _12928.xy;
        }
        else
        {
            _17791 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15014 = texture(irradiance_field, clamp((_15175 + vec2(1.0)) + (clamp((_17791 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15175 + vec2(0.5), _15175 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15309 = _12432 + vec3(0.0, 1.0, 1.0);
        highp vec3 _15314 = _15309 - frag_info.gi_anchor.xyz;
        bool _15317 = any(lessThan(_15314, vec3(0.0)));
        bool _15325 = false;
        if (!_15317)
        {
            _15325 = any(greaterThanEqual(_15314, frag_info.gi_counts.xyz));
        }
        else
        {
            _15325 = _15317;
        }
        vec3 mp_copy_17793 = vec3(0.0);
        highp float _15326 = _15325 ? 0.0 : 1.0;
        float mp_copy_15326 = _15326;
        vec3 _15332 = max(mix(_12574, mp_copy_12438, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15348 = (_15309 * frag_info.gi_grid.xyz) - _12427;
        highp float _15350 = length(_15348);
        highp vec3 _17793 = vec3(0.0);
        if (_15350 > 9.9999997473787516355514526367188e-06)
        {
            _17793 = _15348 / vec3(_15350);
        }
        else
        {
            _17793 = _17668;
        }
        mp_copy_17793 = _17793;
        float _15368 = pow((dot(_17793, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15493 = _15309 - (frag_info.gi_counts.xyz * floor(_15309 / frag_info.gi_counts.xyz));
        highp float _15509 = _15493.x + (frag_info.gi_counts.x * (_15493.y + (frag_info.gi_counts.y * _15493.z)));
        float _17798 = 0.0;
        if (_12625)
        {
            highp float _15517 = floor(_15509 / frag_info.gi_counts.w);
            highp vec2 _15531 = vec2((_15509 - (_15517 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15517 * 16.0));
            vec3 _15391 = -mp_copy_17793;
            vec3 _15579 = _15391 / vec3((abs(_15391.x) + abs(_15391.y)) + abs(_15391.z));
            vec2 _17794 = vec2(0.0);
            if (_15579.z >= 0.0)
            {
                _17794 = _15579.xy;
            }
            else
            {
                _17794 = (vec2(1.0) - abs(_15579.yx)) * vec2((_15579.x >= 0.0) ? 1.0 : (-1.0), (_15579.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15395 = texture(irradiance_field, clamp((_15531 + vec2(1.0)) + (clamp((_17794 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15531 + vec2(0.5), _15531 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15400 = _15395.x * frag_info.gi_visibility.z;
            highp float _15412 = abs((_15400 * _15400) - ((_15395.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15418 = (_15350 - _15400) - frag_info.gi_visibility.y;
            highp float _17795 = 0.0;
            if (_15418 <= 0.0)
            {
                _17795 = 1.0;
            }
            else
            {
                _17795 = _15412 / (_15412 + (_15418 * _15418));
            }
            _17798 = _15368 * mix(1.0, max(0.0500000007450580596923828125, (_17795 * _17795) * _17795), frag_info.gi_visibility.x);
        }
        else
        {
            _17798 = _15368;
        }
        float _15446 = max(9.9999999747524270787835121154785e-07, _17798);
        float _17799 = 0.0;
        if (_15446 < 0.20000000298023223876953125)
        {
            _17799 = _15446 * ((_15446 * _15446) * 25.0);
        }
        else
        {
            _17799 = _15446;
        }
        float _15461 = _17799 * (((_15332.x * _15332.y) * _15332.z) * mp_copy_15326);
        highp float _15620 = floor(_15509 / frag_info.gi_counts.w);
        highp vec2 _15634 = vec2((_15509 - (_15620 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15620 * 8.0));
        vec2 _17800 = vec2(0.0);
        if (_12931)
        {
            _17800 = _12928.xy;
        }
        else
        {
            _17800 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15473 = texture(irradiance_field, clamp((_15634 + vec2(1.0)) + (clamp((_17800 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15634 + vec2(0.5), _15634 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15768 = _12432 + vec3(1.0);
        highp vec3 _15773 = _15768 - frag_info.gi_anchor.xyz;
        bool _15776 = any(lessThan(_15773, vec3(0.0)));
        bool _15784 = false;
        if (!_15776)
        {
            _15784 = any(greaterThanEqual(_15773, frag_info.gi_counts.xyz));
        }
        else
        {
            _15784 = _15776;
        }
        vec3 mp_copy_17802 = vec3(0.0);
        highp float _15785 = _15784 ? 0.0 : 1.0;
        float mp_copy_15785 = _15785;
        vec3 _15791 = max(mp_copy_12438, vec3(0.001000000047497451305389404296875));
        highp vec3 _15807 = (_15768 * frag_info.gi_grid.xyz) - _12427;
        highp float _15809 = length(_15807);
        highp vec3 _17802 = vec3(0.0);
        if (_15809 > 9.9999997473787516355514526367188e-06)
        {
            _17802 = _15807 / vec3(_15809);
        }
        else
        {
            _17802 = _17668;
        }
        mp_copy_17802 = _17802;
        float _15827 = pow((dot(_17802, _17668) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15952 = _15768 - (frag_info.gi_counts.xyz * floor(_15768 / frag_info.gi_counts.xyz));
        highp float _15968 = _15952.x + (frag_info.gi_counts.x * (_15952.y + (frag_info.gi_counts.y * _15952.z)));
        float _17807 = 0.0;
        if (_12625)
        {
            highp float _15976 = floor(_15968 / frag_info.gi_counts.w);
            highp vec2 _15990 = vec2((_15968 - (_15976 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15976 * 16.0));
            vec3 _15850 = -mp_copy_17802;
            vec3 _16038 = _15850 / vec3((abs(_15850.x) + abs(_15850.y)) + abs(_15850.z));
            vec2 _17803 = vec2(0.0);
            if (_16038.z >= 0.0)
            {
                _17803 = _16038.xy;
            }
            else
            {
                _17803 = (vec2(1.0) - abs(_16038.yx)) * vec2((_16038.x >= 0.0) ? 1.0 : (-1.0), (_16038.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15854 = texture(irradiance_field, clamp((_15990 + vec2(1.0)) + (clamp((_17803 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15990 + vec2(0.5), _15990 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15859 = _15854.x * frag_info.gi_visibility.z;
            highp float _15871 = abs((_15859 * _15859) - ((_15854.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15877 = (_15809 - _15859) - frag_info.gi_visibility.y;
            highp float _17804 = 0.0;
            if (_15877 <= 0.0)
            {
                _17804 = 1.0;
            }
            else
            {
                _17804 = _15871 / (_15871 + (_15877 * _15877));
            }
            _17807 = _15827 * mix(1.0, max(0.0500000007450580596923828125, (_17804 * _17804) * _17804), frag_info.gi_visibility.x);
        }
        else
        {
            _17807 = _15827;
        }
        float _15905 = max(9.9999999747524270787835121154785e-07, _17807);
        float _17808 = 0.0;
        if (_15905 < 0.20000000298023223876953125)
        {
            _17808 = _15905 * ((_15905 * _15905) * 25.0);
        }
        else
        {
            _17808 = _15905;
        }
        float _15920 = _17808 * (((_15791.x * _15791.y) * _15791.z) * mp_copy_15785);
        highp float _16079 = floor(_15968 / frag_info.gi_counts.w);
        highp vec2 _16093 = vec2((_15968 - (_16079 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16079 * 8.0));
        vec2 _17809 = vec2(0.0);
        if (_12931)
        {
            _17809 = _12928.xy;
        }
        else
        {
            _17809 = (vec2(1.0) - abs(_12928.yx)) * vec2((_12928.x >= 0.0) ? 1.0 : (-1.0), (_12928.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12485 = ((((((vec4(max(_12719.xyz, vec3(0.0)) * _12707, _12707) + vec4(max(_13178.xyz, vec3(0.0)) * _13166, _13166)) + vec4(max(_13637.xyz, vec3(0.0)) * _13625, _13625)) + vec4(max(_14096.xyz, vec3(0.0)) * _14084, _14084)) + vec4(max(_14555.xyz, vec3(0.0)) * _14543, _14543)) + vec4(max(_15014.xyz, vec3(0.0)) * _15002, _15002)) + vec4(max(_15473.xyz, vec3(0.0)) * _15461, _15461)) + vec4(max(texture(irradiance_field, clamp((_16093 + vec2(1.0)) + (clamp((_17809 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16093 + vec2(0.5), _16093 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _15920, _15920);
        highp float _12487 = _12485.w;
        highp vec3 _17811 = vec3(0.0);
        if (_12487 > 9.9999999747524270787835121154785e-07)
        {
            _17811 = _12485.xyz / vec3(_12487);
        }
        else
        {
            _17811 = vec3(0.0);
        }
        _17929 = mix(_7309, _17811 * _12314, vec3(_17738));
    }
    else
    {
        _17929 = _7309;
    }
    vec2 _7335 = clamp(vec2(_6873, _17716), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7337 = texture(brdf_lut, vec2(_7335.x * 0.3333333432674407958984375, _7335.y));
    float _7341 = _7337.x;
    float _7344 = _7337.y;
    vec3 _7346 = ((_6865 + ((max(vec3(1.0 - _17716), _6865) - _6865) * pow(clamp(1.0 - _6873, 0.0, 1.0), 5.0))) * _7341) + vec3(_7344);
    float _7352 = 1.0 - (_7341 + _7344);
    vec3 _7356 = vec3(1.0) - _6865;
    vec3 _7359 = _6865 + (_7356 * vec3(0.0476190485060214996337890625));
    vec3 _7370 = ((_7346 * _7352) * _7359) / (vec3(1.0) - (_7359 * _7352));
    float _7373 = 1.0 - _5904;
    float _18003 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _18003 = clamp((pow(_6869 + _17943, exp2(((-16.0) * _17716) - 1.0)) - 1.0) + _17943, 0.0, 1.0);
    }
    else
    {
        _18003 = _17943;
    }
    highp vec3 _18156 = vec3(0.0);
    if (_6821)
    {
        highp vec3 _18080 = vec3(0.0);
        highp vec3 _18081 = vec3(0.0);
        do
        {
            float _16262 = max(dot(_17668, _18017), 0.0);
            highp float hp_copy_16262 = _16262;
            if (_16262 <= 0.0)
            {
                _18081 = vec3(0.0);
                _18080 = vec3(0.0);
                break;
            }
            float _16268 = max(_6869, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_16268 = _16268;
            vec3 _16271 = _18017 + mp_copy_17727;
            float _16274 = dot(_16271, _16271);
            vec3 _18078 = vec3(0.0);
            vec3 _18079 = vec3(0.0);
            if (_16274 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _16282 = _16271 * inversesqrt(_16274);
                float _18077 = 0.0;
                do
                {
                    float _16339 = dot(_17668, _16282);
                    if (_16339 <= 0.0)
                    {
                        _18077 = 0.0;
                        break;
                    }
                    float _16346 = _17716 * _17716;
                    vec3 _16349 = cross(_17668, _16282);
                    float _16352 = _16339 * _16346;
                    float _16361 = _16346 / (dot(_16349, _16349) + (_16352 * _16352));
                    _18077 = min((_16361 * _16361) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _16399 = _6865 + (_7356 * pow(clamp(1.0 - max(dot(_16282, _17727), 0.0), 0.0, 1.0), 5.0));
                _18079 = (_16399 * min(_18077 * (0.5 / max(mix((2.0 * hp_copy_16262) * _16268, hp_copy_16262 + hp_copy_16268, hp_copy_17716 * hp_copy_17716), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _18078 = _16399;
            }
            else
            {
                _18079 = vec3(0.0);
                _18078 = _6865;
            }
            _18081 = (_18079 * frag_info.directional_light_color.xyz) * _16262;
            _18080 = (((((vec3(1.0) - _18078) * _7373) * _6796) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _16262;
            break;
        } while(false);
        _18156 = _18089 + ((_18080 + _18081) * _6856);
    }
    else
    {
        _18156 = _18089;
    }
    bool _7464 = _FogInfo.params0.y > 0.5;
    bool _7470 = false;
    if (_7464)
    {
        _7470 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7470 = _7464;
    }
    highp vec3 _18161 = vec3(0.0);
    if (_7470)
    {
        vec3 mp_copy_18157 = vec3(0.0);
        highp vec3 _18157 = vec3(0.0);
        if (_9387)
        {
            _18157 = -view_info.camera_forward.xyz;
        }
        else
        {
            _18157 = normalize(v_viewvector);
        }
        mp_copy_18157 = _18157;
        vec3 _7475 = _7264 * (-mp_copy_18157);
        vec3 _18158 = vec3(0.0);
        do
        {
            if (_11886)
            {
                vec2 _16521 = vec2(atan(_7475.z, _7475.x), asin(clamp(_7475.y, -1.0, 1.0)));
                highp vec2 hp_copy_16521 = _16521;
                _18158 = textureLod(prefiltered_radiance, (hp_copy_16521 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _16540 = vec2(atan(_7475.z, _7475.x), asin(clamp(_7475.y, -1.0, 1.0)));
            highp vec2 hp_copy_16540 = _16540;
            highp vec2 _16545 = (hp_copy_16540 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _16452 = clamp(_16545.y, 0.00390625, 0.99609375);
            float _16458 = floor(0.0);
            highp float _16477 = _16545.x;
            _18158 = mix(textureLod(prefiltered_radiance, vec2(_16477, (_16458 + _16452) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_16477, (min(_16458 + 1.0, 7.0) + _16452) * 0.125), 0.0).xyz, vec3(-_16458));
            break;
        } while(false);
        highp vec3 _18160 = vec3(0.0);
        if (_7287)
        {
            vec3 _18159 = vec3(0.0);
            do
            {
                if (_11886)
                {
                    vec2 _16650 = vec2(atan(_7475.z, _7475.x), asin(clamp(_7475.y, -1.0, 1.0)));
                    highp vec2 hp_copy_16650 = _16650;
                    _18159 = textureLod(prefiltered_radiance_b, (hp_copy_16650 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _16669 = vec2(atan(_7475.z, _7475.x), asin(clamp(_7475.y, -1.0, 1.0)));
                highp vec2 hp_copy_16669 = _16669;
                highp vec2 _16674 = (hp_copy_16669 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _16581 = clamp(_16674.y, 0.00390625, 0.99609375);
                float _16587 = floor(0.0);
                highp float _16606 = _16674.x;
                _18159 = mix(textureLod(prefiltered_radiance_b, vec2(_16606, (_16587 + _16581) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_16606, (min(_16587 + 1.0, 7.0) + _16581) * 0.125), 0.0).xyz, vec3(-_16587));
                break;
            } while(false);
            _18160 = mix(_18158, _18159, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _18160 = _18158;
        }
        _18161 = _18160 * frag_info.environment_intensity;
    }
    else
    {
        _18161 = _FogInfo.color.xyz;
    }
    highp vec4 _7499 = vec4(min(((((((_7370 + ((_6796 * _7373) * ((vec3(1.0) - _7346) - _7370))) * _17929) * vec3(_5938)) + (((_7346 * (_17737 * frag_info.environment_intensity)) * 1.0) * _18003)) * mix(1.0, _6856, frag_info.radiance_blend.y)) + (_18156 * mix(1.0, _17943, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _17691, vec3(65504.0)), 1.0) * _18709;
    highp vec4 _18176 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _18176 = _7499;
            break;
        }
        int _16718 = int(_FogInfo.params0.x + 0.5);
        if (_16718 == 0)
        {
            _18176 = _7499;
            break;
        }
        highp float _18163 = 0.0;
        if (_9387)
        {
            _18163 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _18163 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_18163 > _FogInfo.params1.w))
        {
            _18176 = _7499;
            break;
        }
        float _18167 = 0.0;
        if (_16718 == 1)
        {
            _18167 = clamp((_18163 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _18168 = 0.0;
            if (_16718 == 2)
            {
                highp float _18166 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _18164 = vec3(0.0);
                    if (_9387)
                    {
                        _18164 = v_position - (view_info.camera_forward.xyz * _18163);
                    }
                    else
                    {
                        _18164 = v_position + v_viewvector;
                    }
                    highp float _16799 = -_FogInfo.params2.y;
                    highp float _16806 = _FogInfo.params1.x * exp(_16799 * (_18164.y - _FogInfo.params2.x));
                    highp float _16823 = _FogInfo.params2.y * (v_position.y - _18164.y);
                    highp float _18165 = 0.0;
                    if (abs(_16823) > 0.00124999997206032276153564453125)
                    {
                        _18165 = (_16806 - (_FogInfo.params1.x * exp(_16799 * (v_position.y - _FogInfo.params2.x)))) / _16823;
                    }
                    else
                    {
                        _18165 = _16806;
                    }
                    _18166 = _18165 * max(_18163 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _18166 = _FogInfo.params1.x * max(_18163 - _FogInfo.params1.y, 0.0);
                }
                _18168 = 1.0 - exp(-_18166);
            }
            else
            {
                highp float _16861 = _FogInfo.params1.x * max(_18163 - _FogInfo.params1.y, 0.0);
                _18168 = 1.0 - exp((-_16861) * _16861);
            }
            _18167 = _18168;
        }
        highp float _16873 = min(_18167, _FogInfo.params0.z);
        if (_16873 <= 0.0)
        {
            _18176 = _7499;
            break;
        }
        highp vec3 _16886 = mix(_FogInfo.color.xyz, _18161, vec3(_FogInfo.params0.w));
        bool _16889 = _FogInfo.sun.w > 0.5;
        bool _16895 = false;
        if (_16889)
        {
            _16895 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _16895 = _16889;
        }
        vec3 _18172 = vec3(0.0);
        if (_16895)
        {
            vec3 mp_copy_18169 = vec3(0.0);
            highp vec3 _18169 = vec3(0.0);
            if (_9387)
            {
                _18169 = -view_info.camera_forward.xyz;
            }
            else
            {
                _18169 = normalize(v_viewvector);
            }
            mp_copy_18169 = _18169;
            highp float _16911 = pow(max(dot(-mp_copy_18169, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_16911 = _16911;
            _18172 = _16886 + ((_FogInfo.sun.xyz * mp_copy_16911) * _FogInfo.params2.z);
        }
        else
        {
            _18172 = _16886;
        }
        highp float _16924 = _7499.w;
        float mp_copy_16924 = _16924;
        _18176 = vec4(mix(_7499.xyz, _18172 * mp_copy_16924, vec3(_16873)), _16924);
        break;
    } while(false);
    vec4 _18178 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _18178 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _18178 = _18176;
        break;
    } while(false);
    frag_color = _18178;
    float _18179 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _18179 = 1.0;
    }
    else
    {
        _18179 = abs(frag_info.fade);
    }
    frag_color *= _18179;
}

