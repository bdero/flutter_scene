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

uniform highp sampler2D shadow_map;
uniform highp sampler2D punctual_lights;
uniform highp sampler2D punctual_index;
uniform mediump sampler2D ssao_texture;
uniform highp sampler2D irradiance_field;
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
in highp vec3 v_position;
in vec4 v_color;
layout(location = 0) out vec4 frag_color;

void main()
{
    highp float _4121 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4121 = _4121;
    vec3 _4125 = normalize(v_normal) * mp_copy_4121;
    vec4 _4167 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4170 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9844 = vec2(0.0);
    if (_4170)
    {
        highp vec2 _9843 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9843 = v_texture_coords_1;
        }
        else
        {
            _9843 = v_texture_coords;
        }
        highp vec2 _4373 = _9843 * texture_transforms.base_color_transform.zw;
        highp float _4379 = _4373.x;
        highp float _4384 = _4373.y;
        _9844 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4379) + (texture_transforms.base_color_rotation.y * _4384), ((-texture_transforms.base_color_rotation.y) * _4379) + (texture_transforms.base_color_rotation.x * _4384));
    }
    else
    {
        _9844 = v_texture_coords;
    }
    vec4 _4184 = texture(base_color_texture, _9844);
    vec3 _4186 = _4184.xyz;
    float _10319 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4184.w * _4167.w) * frag_info.color.w);
    vec3 _9859 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9847 = vec2(0.0);
        if (_4170)
        {
            highp vec2 _9846 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9846 = v_texture_coords_1;
            }
            else
            {
                _9846 = v_texture_coords;
            }
            highp vec2 _4468 = _9846 * texture_transforms.normal_transform.zw;
            highp float _4474 = _4468.x;
            highp float _4479 = _4468.y;
            _9847 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4474) + (texture_transforms.normal_rotation.y * _4479), ((-texture_transforms.normal_rotation.y) * _4474) + (texture_transforms.normal_rotation.x * _4479));
        }
        else
        {
            _9847 = v_texture_coords;
        }
        vec3 _4524 = ((texture(normal_texture, _9847).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4528 = _4524.xy * vec2(frag_info.normal_scale);
        vec3 _9580 = _4524;
        _9580.x = _4528.x;
        _9580.y = _4528.y;
        highp vec3 _4534 = -v_viewvector;
        highp vec3 _4624 = dFdx(_4534);
        highp vec3 _4626 = dFdy(_4534);
        highp vec2 _4628 = dFdx(_9847);
        highp vec2 _4630 = dFdy(_9847);
        bvec2 _10321 = bvec2(length(_4628) == 0.0);
        highp vec2 _10322 = vec2(_10321.x ? vec2(1.0, 0.0).x : _4628.x, _10321.y ? vec2(1.0, 0.0).y : _4628.y);
        bvec2 _10323 = bvec2(length(_4630) == 0.0);
        highp vec2 _10324 = vec2(_10323.x ? vec2(0.0, 1.0).x : _4630.x, _10323.y ? vec2(0.0, 1.0).y : _4630.y);
        highp vec3 _4643 = cross(_4626, _4125);
        highp vec3 _4646 = cross(_4125, _4624);
        highp float _4671 = (dot(cross(_4624, _4626), _4125) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4674 = ((_4643 * _10322.x) + (_4646 * _10324.x)) * _4671;
        highp float _9854 = 0.0;
        if (gl_FrontFacing)
        {
            _9854 = -_4671;
        }
        else
        {
            _9854 = _4671;
        }
        highp vec3 _4684 = ((_4643 * _10322.y) + (_4646 * _10324.y)) * _9854;
        highp float _4693 = inversesqrt(max(max(dot(_4674, _4674), dot(_4684, _4684)), 9.9999996826552253889678874634872e-21));
        vec3 _4565 = v_tangent.xyz - (_4125 * dot(_4125, v_tangent.xyz));
        highp float _4568 = dot(_4565, _4565);
        bool _4570 = _4568 > 1.0000000133514319600180897396058e-10;
        bool _4577 = false;
        if (_4570)
        {
            _4577 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4577 = _4570;
        }
        mat3 _9857 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4577)
        {
            highp vec3 _4582 = _4565 * inversesqrt(_4568);
            _9857 = mat3(_4582, normalize(cross(_4125, _4582)) * sign(v_tangent.w), _4125);
        }
        else
        {
            _9857 = mat3(_4674 * _4693, _4684 * _4693, _4125);
        }
        _9859 = normalize(_9857 * _9580);
    }
    else
    {
        _9859 = _4125;
    }
    highp vec2 _9861 = vec2(0.0);
    if (_4170)
    {
        highp vec2 _9860 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9860 = v_texture_coords_1;
        }
        else
        {
            _9860 = v_texture_coords;
        }
        highp vec2 _4761 = _9860 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4767 = _4761.x;
        highp float _4772 = _4761.y;
        _9861 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4767) + (texture_transforms.metallic_roughness_rotation.y * _4772), ((-texture_transforms.metallic_roughness_rotation.y) * _4767) + (texture_transforms.metallic_roughness_rotation.x * _4772));
    }
    else
    {
        _9861 = v_texture_coords;
    }
    vec4 _4253 = texture(metallic_roughness_texture, _9861);
    float _4259 = clamp(_4253.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4266 = clamp(_4253.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9863 = vec2(0.0);
    if (_4170)
    {
        highp vec2 _9862 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9862 = v_texture_coords_1;
        }
        else
        {
            _9862 = v_texture_coords;
        }
        highp vec2 _4832 = _9862 * texture_transforms.occlusion_transform.zw;
        highp float _4838 = _4832.x;
        highp float _4843 = _4832.y;
        _9863 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4838) + (texture_transforms.occlusion_rotation.y * _4843), ((-texture_transforms.occlusion_rotation.y) * _4838) + (texture_transforms.occlusion_rotation.x * _4843));
    }
    else
    {
        _9863 = v_texture_coords;
    }
    float _9864 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9864 = texture(occlusion_texture, _9863).x;
    }
    else
    {
        _9864 = 1.0;
    }
    float _4293 = 1.0 - ((1.0 - _9864) * frag_info.occlusion_strength);
    highp vec2 _9866 = vec2(0.0);
    if (_4170)
    {
        highp vec2 _9865 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9865 = v_texture_coords_1;
        }
        else
        {
            _9865 = v_texture_coords;
        }
        highp vec2 _4903 = _9865 * texture_transforms.emissive_transform.zw;
        highp float _4909 = _4903.x;
        highp float _4914 = _4903.y;
        _9866 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4909) + (texture_transforms.emissive_rotation.y * _4914), ((-texture_transforms.emissive_rotation.y) * _4909) + (texture_transforms.emissive_rotation.x * _4914));
    }
    else
    {
        _9866 = v_texture_coords;
    }
    vec3 _4312 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9882 = vec3(0.0);
    if (dot(abs(_4312), vec3(1.0)) > 0.0)
    {
        vec3 _4321 = texture(emissive_texture, _9866).xyz;
        _9882 = mix(_4321 * vec3(0.077399380505084991455078125), pow((_4321 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4321)) * _4312;
    }
    else
    {
        _9882 = vec3(0.0);
    }
    highp float hp_copy_9907 = 0.0;
    vec3 _5089 = vec4((mix(_4186 * vec3(0.077399380505084991455078125), pow((_4186 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4186)) * _4167.xyz) * frag_info.color.xyz, _10319).xyz;
    vec3 _5575 = dFdx(_9859);
    vec3 _5577 = dFdy(_9859);
    float _9907 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9907 = sqrt(clamp((_4266 * _4266) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5575, _5575), dot(_5577, _5577))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9907 = _4266;
    }
    hp_copy_9907 = _9907;
    float _9936 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9936 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9936 = _4293;
    }
    bool _5114 = frag_info.has_directional_light > 0.5;
    float _9908 = 0.0;
    vec3 _9950 = vec3(0.0);
    if (_5114)
    {
        highp vec3 _5120 = -normalize(frag_info.directional_light_direction.xyz);
        _9950 = _5120;
        _9908 = dot(_4125, _5120);
    }
    else
    {
        _9950 = vec3(0.0);
        _9908 = 0.0;
    }
    float _5127 = clamp(_9908 * 6.666666507720947265625, 0.0, 1.0);
    bool _5136 = false;
    if (_5114)
    {
        _5136 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5136 = _5114;
    }
    float _9917 = 0.0;
    if (_5136 && (_5127 > 0.0))
    {
        int _5656 = int(frag_info.shadow_cascade_count);
        float _5851 = max(dot(_4125, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5854 = _5851 * _5851;
        highp vec3 _5874 = v_position + (_4125 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5854, 0.0)) / _5854, 8.0))));
        highp float _5662 = frag_info.directional_light_color.w * 0.5;
        float _5664 = frag_info.dielectric_f0.w;
        highp float hp_copy_5664 = _5664;
        float _9909 = 0.0;
        if (_5664 > 0.0)
        {
            _9909 = smoothstep(_5664 - max(frag_info.shadow_fade, hp_copy_5664 * 0.100000001490116119384765625), _5664, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9909 = 0.0;
        }
        float _9911 = 0.0;
        float _9913 = 0.0;
        if (_9909 < 1.0)
        {
            float _9912 = 0.0;
            float _9914 = 0.0;
            _9914 = 0.0;
            _9912 = 0.0;
            float _10165 = 0.0;
            float _10168 = 0.0;
            for (int _9910 = 0; _9910 < _5656; _9914 = _10168, _9912 = _10165, _9910++)
            {
                if (_9914 < 1.0)
                {
                    highp vec4 _5696 = vec4(_5874, 1.0);
                    highp vec4 _10069 = vec4(0.0);
                    highp float _10072 = 0.0;
                    if (_9910 == 0)
                    {
                        _10072 = frag_info.cascade_box_sizes.x;
                        _10069 = frag_info.light_space_matrix[0] * _5696;
                    }
                    else
                    {
                        highp vec4 _10070 = vec4(0.0);
                        highp float _10073 = 0.0;
                        if (_9910 == 1)
                        {
                            _10073 = frag_info.cascade_box_sizes.y;
                            _10070 = frag_info.light_space_matrix[1] * _5696;
                        }
                        else
                        {
                            highp vec4 _10071 = vec4(0.0);
                            highp float _10074 = 0.0;
                            if (_9910 == 2)
                            {
                                _10074 = frag_info.cascade_box_sizes.z;
                                _10071 = frag_info.light_space_matrix[2] * _5696;
                            }
                            else
                            {
                                _10074 = frag_info.cascade_box_sizes.w;
                                _10071 = frag_info.light_space_matrix[3] * _5696;
                            }
                            _10073 = _10074;
                            _10070 = _10071;
                        }
                        _10072 = _10073;
                        _10069 = _10070;
                    }
                    highp vec3 _5741 = _10069.xyz / vec3(_10069.w);
                    highp vec2 _5744 = _5741.xy * 0.5;
                    highp vec2 _5746 = _5744 + vec2(0.5);
                    highp float _5753 = max(frag_info.shadow_softness / _10072, frag_info.shadow_texel_size);
                    highp float _5755 = _5746.x;
                    bool _5757 = _5755 < _5753;
                    bool _5766 = false;
                    if (!_5757)
                    {
                        _5766 = _5755 > (1.0 - _5753);
                    }
                    else
                    {
                        _5766 = _5757;
                    }
                    bool _5774 = false;
                    if (!_5766)
                    {
                        _5774 = _5746.y < _5753;
                    }
                    else
                    {
                        _5774 = _5766;
                    }
                    bool _5783 = false;
                    if (!_5774)
                    {
                        _5783 = _5746.y > (1.0 - _5753);
                    }
                    else
                    {
                        _5783 = _5774;
                    }
                    bool _5790 = false;
                    if (!_5783)
                    {
                        _5790 = _5741.z < 0.0;
                    }
                    else
                    {
                        _5790 = _5783;
                    }
                    bool _5797 = false;
                    if (!_5790)
                    {
                        _5797 = _5741.z > 1.0;
                    }
                    else
                    {
                        _5797 = _5790;
                    }
                    float _10166 = 0.0;
                    float _10169 = 0.0;
                    if (!_5797)
                    {
                        highp vec2 _5890 = vec2(_5753);
                        highp vec2 _5895 = vec2(_5753 + max(_5662, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5903 = vec2(0.5) - _5744;
                        highp vec2 _5905 = smoothstep(_5890, _5895, _5746) * smoothstep(_5890, _5895, _5903);
                        float _10075 = 0.0;
                        if (_5662 > 0.0)
                        {
                            _10075 = _5905.x * _5905.y;
                        }
                        else
                        {
                            _10075 = 1.0;
                        }
                        float _5806 = min(_10075, 1.0 - _9914);
                        float _10167 = 0.0;
                        float _10170 = 0.0;
                        if (_5806 > 0.0)
                        {
                            highp float _6030 = _5741.z - (frag_info.shadow_bias / (7.0 * _10072));
                            highp float _6036 = 1.0 / (float(_5656) + frag_info.spot_shadow_params.x);
                            highp float _6038 = frag_info.directional_light_direction.w;
                            float mp_copy_6038 = _6038;
                            float _10105 = 0.0;
                            float _10109 = 0.0;
                            if ((step(0.5, mp_copy_6038) * (1.0 - step(1.5, mp_copy_6038))) < 0.5)
                            {
                                highp float _6055 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6055 = _6055;
                                _10109 = sin(mp_copy_6055);
                                _10105 = cos(mp_copy_6055);
                            }
                            else
                            {
                                _10109 = 0.0;
                                _10105 = 1.0;
                            }
                            highp float _10112 = 0.0;
                            if ((_6038 > 1.5) && (_6038 < 2.5))
                            {
                                highp float _6079 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6084 = max(_6079 * _6030, frag_info.shadow_texel_size);
                                float _10101 = 0.0;
                                highp float _10102 = 0.0;
                                _10102 = 0.0;
                                _10101 = 0.0;
                                highp float _6106 = 0.0;
                                float _6109 = 0.0;
                                for (int _10100 = 0; _10100 < 9; _10102 = _6106, _10101 = _6109, _10100++)
                                {
                                    vec2 _10159 = vec2(0.0);
                                    do
                                    {
                                        if (_10100 == 0)
                                        {
                                            _10159 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10100 == 1)
                                        {
                                            _10159 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10100 == 2)
                                        {
                                            _10159 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10100 == 3)
                                        {
                                            _10159 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10100 == 4)
                                        {
                                            _10159 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10100 == 5)
                                        {
                                            _10159 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10100 == 6)
                                        {
                                            _10159 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10100 == 7)
                                        {
                                            _10159 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10100 == 8)
                                        {
                                            _10159 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10100 == 9)
                                        {
                                            _10159 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10100 == 10)
                                        {
                                            _10159 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10100 == 11)
                                        {
                                            _10159 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10100 == 12)
                                        {
                                            _10159 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10100 == 13)
                                        {
                                            _10159 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10100 == 14)
                                        {
                                            _10159 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10100 == 15)
                                        {
                                            _10159 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10159 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6373 = clamp(_5746 + (vec2((_10159.x * _10105) - (_10159.y * _10109), (_10159.x * _10109) + (_10159.y * _10105)) * _6084), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6382 = _6373.y;
                                    highp vec2 _6383 = vec2((float(_9910) + _6373.x) * _6036, _6382);
                                    _6383.y = 1.0 - _6382;
                                    highp vec4 _6390 = textureLod(shadow_map, _6383, 0.0);
                                    highp float _6391 = _6390.x;
                                    highp float _6101 = step(_6391, _6030);
                                    float mp_copy_6101 = _6101;
                                    _6106 = _10102 + (_6391 * _6101);
                                    _6109 = _10101 + mp_copy_6101;
                                }
                                highp float _10103 = 0.0;
                                if (_10101 > 0.0)
                                {
                                    _10103 = _10102 / _10101;
                                }
                                else
                                {
                                    _10103 = _6030;
                                }
                                _10112 = clamp(_6079 * max(_6030 - _10103, 0.0), frag_info.shadow_texel_size, _5753);
                            }
                            else
                            {
                                _10112 = _5753;
                            }
                            bool _6140 = _6038 > 2.5;
                            bool _10113 = false;
                            float _10118 = 0.0;
                            if ((_6038 < 1.5) || _6140)
                            {
                                highp vec2 _6424 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6428 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6429 = clamp(_5746, _6424, _6428);
                                highp float _6431 = float(_9910);
                                highp float _6438 = _6429.y;
                                highp vec2 _6439 = vec2((_6431 + _6429.x) * _6036, _6438);
                                _6439.y = 1.0 - _6438;
                                highp float _6451 = float(_6030 <= textureLod(shadow_map, _6439, 0.0).x);
                                float mp_copy_6451 = _6451;
                                float _6461 = (-1.0) * _10105;
                                float _6465 = (-1.0) * _10109;
                                highp vec2 _6489 = clamp(_5746 + (vec2(_6461 - _6465, _6465 + _6461) * _10112), _6424, _6428);
                                highp float _6498 = _6489.y;
                                highp vec2 _6499 = vec2((_6431 + _6489.x) * _6036, _6498);
                                _6499.y = 1.0 - _6498;
                                highp float _6511 = float(_6030 <= textureLod(shadow_map, _6499, 0.0).x);
                                float mp_copy_6511 = _6511;
                                highp vec2 _6549 = clamp(_5746 + (vec2(_10105 - _6465, _10109 + _6461) * _10112), _6424, _6428);
                                highp float _6558 = _6549.y;
                                highp vec2 _6559 = vec2((_6431 + _6549.x) * _6036, _6558);
                                _6559.y = 1.0 - _6558;
                                highp float _6571 = float(_6030 <= textureLod(shadow_map, _6559, 0.0).x);
                                float mp_copy_6571 = _6571;
                                highp vec2 _6609 = clamp(_5746 + (vec2(_6461 - _10109, _6465 + _10105) * _10112), _6424, _6428);
                                highp float _6618 = _6609.y;
                                highp vec2 _6619 = vec2((_6431 + _6609.x) * _6036, _6618);
                                _6619.y = 1.0 - _6618;
                                highp float _6631 = float(_6030 <= textureLod(shadow_map, _6619, 0.0).x);
                                float mp_copy_6631 = _6631;
                                highp vec2 _6669 = clamp(_5746 + (vec2(_10105 - _10109, _10109 + _10105) * _10112), _6424, _6428);
                                highp float _6678 = _6669.y;
                                highp vec2 _6679 = vec2((_6431 + _6669.x) * _6036, _6678);
                                _6679.y = 1.0 - _6678;
                                highp float _6691 = float(_6030 <= textureLod(shadow_map, _6679, 0.0).x);
                                float mp_copy_6691 = _6691;
                                float _6186 = (((mp_copy_6451 + mp_copy_6511) + mp_copy_6571) + mp_copy_6631) + mp_copy_6691;
                                _10118 = _6186 * 0.20000000298023223876953125;
                                _10113 = (_6186 < 0.5) || (_6186 > 4.5);
                            }
                            else
                            {
                                _10118 = 0.0;
                                _10113 = false;
                            }
                            float _10116 = 0.0;
                            if (_10113)
                            {
                                _10116 = _10118;
                            }
                            else
                            {
                                float _10117 = 0.0;
                                if (_6140)
                                {
                                    highp vec2 _6719 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6723 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6724 = clamp(_5746 + (vec2(-0.707099974155426025390625) * _10112), _6719, _6723);
                                    highp vec2 _6735 = (vec2(_6724.x, 1.0 - _6724.y) / _6719) - vec2(0.5);
                                    highp vec2 _6737 = floor(_6735);
                                    highp vec2 _6740 = _6735 - _6737;
                                    highp vec2 _6745 = (_6737 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6747 = float(_9910);
                                    highp vec2 _6755 = vec2((_6747 + _6745.x) * _6036, _6745.y);
                                    highp float _6759 = frag_info.shadow_texel_size * _6036;
                                    highp vec2 _6762 = vec2(_6759, frag_info.shadow_texel_size);
                                    highp vec2 _6771 = vec2(_6759, 0.0);
                                    highp vec2 _6779 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _6808 = _6740.x;
                                    highp float _6817 = mix(mix(float(_6030 <= textureLod(shadow_map, _6755, 0.0).x), float(_6030 <= textureLod(shadow_map, _6755 + _6771, 0.0).x), _6808), mix(float(_6030 <= textureLod(shadow_map, _6755 + _6779, 0.0).x), float(_6030 <= textureLod(shadow_map, _6755 + _6762, 0.0).x), _6808), _6740.y);
                                    float mp_copy_6817 = _6817;
                                    highp vec2 _6851 = clamp(_5746 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10112), _6719, _6723);
                                    highp vec2 _6862 = (vec2(_6851.x, 1.0 - _6851.y) / _6719) - vec2(0.5);
                                    highp vec2 _6864 = floor(_6862);
                                    highp vec2 _6867 = _6862 - _6864;
                                    highp vec2 _6872 = (_6864 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6882 = vec2((_6747 + _6872.x) * _6036, _6872.y);
                                    highp float _6935 = _6867.x;
                                    highp float _6944 = mix(mix(float(_6030 <= textureLod(shadow_map, _6882, 0.0).x), float(_6030 <= textureLod(shadow_map, _6882 + _6771, 0.0).x), _6935), mix(float(_6030 <= textureLod(shadow_map, _6882 + _6779, 0.0).x), float(_6030 <= textureLod(shadow_map, _6882 + _6762, 0.0).x), _6935), _6867.y);
                                    float mp_copy_6944 = _6944;
                                    highp vec2 _6978 = clamp(_5746 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10112), _6719, _6723);
                                    highp vec2 _6989 = (vec2(_6978.x, 1.0 - _6978.y) / _6719) - vec2(0.5);
                                    highp vec2 _6991 = floor(_6989);
                                    highp vec2 _6994 = _6989 - _6991;
                                    highp vec2 _6999 = (_6991 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7009 = vec2((_6747 + _6999.x) * _6036, _6999.y);
                                    highp float _7062 = _6994.x;
                                    highp float _7071 = mix(mix(float(_6030 <= textureLod(shadow_map, _7009, 0.0).x), float(_6030 <= textureLod(shadow_map, _7009 + _6771, 0.0).x), _7062), mix(float(_6030 <= textureLod(shadow_map, _7009 + _6779, 0.0).x), float(_6030 <= textureLod(shadow_map, _7009 + _6762, 0.0).x), _7062), _6994.y);
                                    float mp_copy_7071 = _7071;
                                    highp vec2 _7105 = clamp(_5746 + (vec2(0.707099974155426025390625) * _10112), _6719, _6723);
                                    highp vec2 _7116 = (vec2(_7105.x, 1.0 - _7105.y) / _6719) - vec2(0.5);
                                    highp vec2 _7118 = floor(_7116);
                                    highp vec2 _7121 = _7116 - _7118;
                                    highp vec2 _7126 = (_7118 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7136 = vec2((_6747 + _7126.x) * _6036, _7126.y);
                                    highp float _7189 = _7121.x;
                                    highp float _7198 = mix(mix(float(_6030 <= textureLod(shadow_map, _7136, 0.0).x), float(_6030 <= textureLod(shadow_map, _7136 + _6771, 0.0).x), _7189), mix(float(_6030 <= textureLod(shadow_map, _7136 + _6779, 0.0).x), float(_6030 <= textureLod(shadow_map, _7136 + _6762, 0.0).x), _7189), _7121.y);
                                    float mp_copy_7198 = _7198;
                                    _10117 = (((mp_copy_6817 + mp_copy_6944) + mp_copy_7071) + mp_copy_7198) * 0.25;
                                }
                                else
                                {
                                    _10117 = _10118;
                                }
                                _10116 = _10117;
                            }
                            bool _6235 = _9910 == (_5656 - 1);
                            bool _6241 = false;
                            if (_6235)
                            {
                                _6241 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6241 = _6235;
                            }
                            float _10119 = 0.0;
                            if (_6241)
                            {
                                highp vec2 _6248 = vec2(frag_info.shadow_fade / _10072);
                                highp vec2 _6256 = smoothstep(vec2(0.0), _6248, _5746) * smoothstep(vec2(0.0), _6248, _5903);
                                _10119 = mix(1.0, _10116, _6256.x * _6256.y);
                            }
                            else
                            {
                                _10119 = _10116;
                            }
                            _10170 = _9914 + _5806;
                            _10167 = _9912 + (_5806 * _10119);
                        }
                        else
                        {
                            _10170 = _9914;
                            _10167 = _9912;
                        }
                        _10169 = _10170;
                        _10166 = _10167;
                    }
                    else
                    {
                        _10169 = _9914;
                        _10166 = _9912;
                    }
                    _10168 = _10169;
                    _10165 = _10166;
                }
                else
                {
                    _10168 = _9914;
                    _10165 = _9912;
                }
            }
            _9913 = _9914;
            _9911 = _9912;
        }
        else
        {
            _9913 = 0.0;
            _9911 = 0.0;
        }
        _9917 = mix(_9911 + (1.0 - _9913), 1.0, _9909);
    }
    else
    {
        _9917 = 1.0;
    }
    vec3 mp_copy_9918 = vec3(0.0);
    float _5149 = _5127 * _9917;
    bool _7206 = view_info.camera_forward.w > 0.5;
    highp vec3 _9918 = vec3(0.0);
    if (_7206)
    {
        _9918 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9918 = normalize(v_viewvector);
    }
    highp float _7250 = 0.0;
    mp_copy_9918 = _9918;
    vec3 _5158 = mix(frag_info.dielectric_f0.xyz, _5089, vec3(_4259));
    float _5162 = max(dot(_9859, _9918), 0.0);
    float _5166 = max(dot(_4125, _9918), 0.0);
    highp vec2 _9919 = vec2(0.0);
    do
    {
        _7250 = frag_info.punctual_dims.x;
        if (_7250 < 0.5)
        {
            _9919 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7262 = v_position - frag_info.camera_position.xyz;
            highp float _7277 = dot(_7262, frag_info.camera_forward.xyz);
            highp float _7283 = max(_7277, 9.9999997473787516355514526367188e-05);
            highp vec2 _7386 = (vec3(dot(_7262, frag_info.camera_right.xyz), dot(_7262, frag_info.camera_up.xyz), _7283).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7283, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7401 = float(int(((((clamp(floor((log2(max(_7277 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7386.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7386.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9919 = vec2(textureLod(punctual_index, vec2((mod(_7401, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7401 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9919 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5175 = int(_9919.x + 0.5);
    mediump int _5179 = int(_9919.y + 0.5);
    highp vec3 _9964 = vec3(0.0);
    _9964 = vec3(0.0);
    highp vec3 _10269 = vec3(0.0);
    for (int _9920 = 0; _9920 < _5179; _9964 = _10269, _9920++)
    {
        highp float hp_copy_10021 = 0.0;
        highp float _7434 = float(_5175 + _9920);
        highp float _7465 = (float(int(textureLod(punctual_index, vec2((mod(_7434, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7434 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7250;
        highp vec4 _7469 = textureLod(punctual_lights, vec2(0.0625, _7465), 0.0);
        highp vec4 _7486 = textureLod(punctual_lights, vec2(0.1875, _7465), 0.0);
        highp float _5197 = _7469.w;
        highp vec3 _5199 = _7486.xyz;
        vec3 _10007 = vec3(0.0);
        highp vec3 _10018 = vec3(0.0);
        float _10021 = 0.0;
        if (_5197 < 0.5)
        {
            _10021 = _9907;
            _10018 = _5199;
            _10007 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7465), 0.0).xyz);
        }
        else
        {
            highp vec3 _5207 = _7469.xyz - v_position;
            highp float _5210 = dot(_5207, _5207);
            highp float _5214 = inversesqrt(max(_5210, 9.9999999392252902907785028219223e-09));
            highp vec3 _5215 = _5207 * _5214;
            vec3 mp_copy_5215 = _5215;
            highp float _5217 = _7486.w;
            highp float _5222 = (_5210 * _5217) * _5217;
            highp float _5227 = clamp(1.0 - (_5222 * _5222), 0.0, 1.0);
            float mp_copy_5227 = _5227;
            if (_5227 <= 0.0)
            {
                _10269 = _9964;
                continue;
            }
            highp vec4 _7503 = textureLod(punctual_lights, vec2(0.4375, _7465), 0.0);
            highp float _5235 = _7503.w;
            float _10023 = 0.0;
            if (_5235 > 0.0)
            {
                highp float _5262 = (_9907 * _9907) + ((_5235 * 0.5) * _5214);
                float mp_copy_5262 = _5262;
                _10023 = sqrt(min(mp_copy_5262, 1.0));
            }
            else
            {
                _10023 = _9907;
            }
            highp vec3 _5269 = _5199 * ((mp_copy_5227 * mp_copy_5227) / max(pow(max(_5210, _5235 * _5235), _7503.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10019 = vec3(0.0);
            if (_5197 > 1.5)
            {
                highp vec4 _7520 = textureLod(punctual_lights, vec2(0.3125, _7465), 0.0);
                highp float _5288 = clamp((dot(normalize(_7520.xyz), -mp_copy_5215) * _7520.w) + _7503.x, 0.0, 1.0);
                float mp_copy_5288 = _5288;
                highp vec3 _5293 = _5269 * (mp_copy_5288 * mp_copy_5288);
                if (_5288 <= 0.0)
                {
                    _10269 = _9964;
                    continue;
                }
                bool _5299 = _5288 > 0.0;
                bool _5305 = false;
                if (_5299)
                {
                    _5305 = _7503.y > (-0.5);
                }
                else
                {
                    _5305 = _5299;
                }
                bool _5311 = false;
                if (_5305)
                {
                    _5311 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5311 = _5305;
                }
                highp vec3 _10020 = vec3(0.0);
                if (_5311)
                {
                    float _9998 = 0.0;
                    do
                    {
                        highp vec4 _7632 = mat4(textureLod(punctual_lights, vec2(0.5625, _7465), 0.0), textureLod(punctual_lights, vec2(0.6875, _7465), 0.0), textureLod(punctual_lights, vec2(0.8125, _7465), 0.0), textureLod(punctual_lights, vec2(0.9375, _7465), 0.0)) * vec4(v_position + (_4125 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _7634 = _7632.w;
                        if (_7634 <= 0.0)
                        {
                            _9998 = 1.0;
                            break;
                        }
                        highp vec3 _7643 = _7632.xyz / vec3(_7634);
                        highp vec2 _7648 = (_7643.xy * 0.5) + vec2(0.5);
                        highp float _7650 = _7648.x;
                        bool _7651 = _7650 < 0.0;
                        bool _7658 = false;
                        if (!_7651)
                        {
                            _7658 = _7650 > 1.0;
                        }
                        else
                        {
                            _7658 = _7651;
                        }
                        bool _7665 = false;
                        if (!_7658)
                        {
                            _7665 = _7648.y < 0.0;
                        }
                        else
                        {
                            _7665 = _7658;
                        }
                        bool _7672 = false;
                        if (!_7665)
                        {
                            _7672 = _7648.y > 1.0;
                        }
                        else
                        {
                            _7672 = _7665;
                        }
                        bool _7679 = false;
                        if (!_7672)
                        {
                            _7679 = _7643.z < 0.0;
                        }
                        else
                        {
                            _7679 = _7672;
                        }
                        bool _7686 = false;
                        if (!_7679)
                        {
                            _7686 = _7643.z > 1.0;
                        }
                        else
                        {
                            _7686 = _7679;
                        }
                        if (_7686)
                        {
                            _9998 = 1.0;
                            break;
                        }
                        highp float _7693 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _7698 = frag_info.shadow_cascade_count + float(int(_7503.y + 0.5));
                        highp float _7703 = _7643.z - frag_info.spot_shadow_params.y;
                        highp float _7714 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_7714 = _7714;
                        highp vec2 _7721 = vec2(cos(mp_copy_7714), sin(mp_copy_7714)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _7723 = _7721.x;
                        highp float _7725 = _7721.y;
                        highp vec2 _7733 = vec2(_7723 - _7725, _7723 + _7725) * 0.707106769084930419921875;
                        highp float _7926 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7650, 0.0, 1.0)) / _7693, 1.0 - clamp(_7648.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7926 = _7926;
                        highp vec2 _7741 = _7648 + _7721;
                        highp float _7948 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7741.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7741.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7948 = _7948;
                        highp vec2 _7749 = _7648 - _7721;
                        highp float _7970 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7749.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7749.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7970 = _7970;
                        highp vec2 _7762 = _7648 + vec2(-_7725, _7723);
                        highp float _7992 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7762.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7762.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7992 = _7992;
                        highp vec2 _7775 = _7648 + vec2(_7725, -_7723);
                        highp float _8014 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7775.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7775.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8014 = _8014;
                        float _7780 = (((mp_copy_7926 + mp_copy_7948) + mp_copy_7970) + mp_copy_7992) + mp_copy_8014;
                        if ((_7780 < 0.5) || (_7780 > 4.5))
                        {
                            _9998 = _7780 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _7792 = _7648 + _7733;
                        highp float _8036 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7792.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7792.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8036 = _8036;
                        highp vec2 _7799 = _7648 - _7733;
                        highp float _8058 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7799.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7799.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8058 = _8058;
                        highp float _7807 = _7733.y;
                        highp float _7810 = _7733.x;
                        highp vec2 _7812 = _7648 + vec2(-_7807, _7810);
                        highp float _8080 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7812.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7812.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8080 = _8080;
                        highp vec2 _7825 = _7648 + vec2(_7807, -_7810);
                        highp float _8102 = float(_7703 <= textureLod(shadow_map, vec2((_7698 + clamp(_7825.x, 0.0, 1.0)) / _7693, 1.0 - clamp(_7825.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8102 = _8102;
                        _9998 = (_7780 + (((mp_copy_8036 + mp_copy_8058) + mp_copy_8080) + mp_copy_8102)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10020 = _5293 * _9998;
                }
                else
                {
                    _10020 = _5293;
                }
                _10019 = _10020;
            }
            else
            {
                _10019 = _5269;
            }
            _10021 = _10023;
            _10018 = _10019;
            _10007 = _5215;
        }
        hp_copy_10021 = _10021;
        highp vec3 _10036 = vec3(0.0);
        highp vec3 _10037 = vec3(0.0);
        do
        {
            float _8185 = max(dot(_9859, _10007), 0.0);
            highp float hp_copy_8185 = _8185;
            if (_8185 <= 0.0)
            {
                _10037 = vec3(0.0);
                _10036 = vec3(0.0);
                break;
            }
            float _8191 = max(_5162, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8191 = _8191;
            vec3 _8194 = _10007 + mp_copy_9918;
            float _8197 = dot(_8194, _8194);
            vec3 _10034 = vec3(0.0);
            vec3 _10035 = vec3(0.0);
            if (_8197 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8205 = _8194 * inversesqrt(_8197);
                float _10033 = 0.0;
                do
                {
                    float _8262 = dot(_9859, _8205);
                    if (_8262 <= 0.0)
                    {
                        _10033 = 0.0;
                        break;
                    }
                    float _8269 = _10021 * _10021;
                    vec3 _8272 = cross(_9859, _8205);
                    float _8275 = _8262 * _8269;
                    float _8284 = _8269 / (dot(_8272, _8272) + (_8275 * _8275));
                    _10033 = min((_8284 * _8284) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8322 = _5158 + ((vec3(1.0) - _5158) * pow(clamp(1.0 - max(dot(_8205, _9918), 0.0), 0.0, 1.0), 5.0));
                _10035 = (_8322 * min(_10033 * (0.5 / max(mix((2.0 * hp_copy_8185) * _8191, hp_copy_8185 + hp_copy_8191, hp_copy_10021 * hp_copy_10021), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10034 = _8322;
            }
            else
            {
                _10035 = vec3(0.0);
                _10034 = _5158;
            }
            _10037 = (_10035 * _10018) * _8185;
            _10036 = (((((vec3(1.0) - _10034) * (1.0 - _4259)) * _5089) * 0.3183098733425140380859375) * _10018) * _8185;
            break;
        } while(false);
        _10269 = _9964 + (_10036 + _10037);
    }
    bool _8546 = false;
    highp vec3 hp_copy_9921 = vec3(0.0);
    mat3 _5366 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5374 = _5366 * vec3(_9859.x, _9859.y, _9859.z);
    vec3 _5377 = _5366 * reflect(-mp_copy_9918, _9859);
    float _8365 = _5374.y;
    float _8372 = _5374.z;
    float _8379 = _5374.x;
    float _8387 = 1.09254801273345947265625 * _8379;
    vec3 _5380 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8365))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8372))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8379))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8387 * _8365))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8365) * _8372))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8372) * _8372) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8387 * _8372))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8379 * _8379) - (_8365 * _8365)))), vec3(0.0));
    highp vec3 hp_copy_5380 = _5380;
    vec3 _9921 = vec3(0.0);
    do
    {
        _8546 = radiance_layout_info.mip_layout > 0.5;
        if (_8546)
        {
            vec2 _8625 = vec2(atan(_5377.z, _5377.x), asin(clamp(_5377.y, -1.0, 1.0)));
            highp vec2 hp_copy_8625 = _8625;
            _9921 = textureLod(prefiltered_radiance, (hp_copy_8625 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9907, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8644 = vec2(atan(_5377.z, _5377.x), asin(clamp(_5377.y, -1.0, 1.0)));
        highp vec2 hp_copy_8644 = _8644;
        highp vec2 _8649 = (hp_copy_8644 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8556 = clamp(_8649.y, 0.00390625, 0.99609375);
        float _8560 = clamp(_9907, 0.0, 1.0) * 7.0;
        float _8562 = floor(_8560);
        highp float _8581 = _8649.x;
        _9921 = mix(textureLod(prefiltered_radiance, vec2(_8581, (_8562 + _8556) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8581, (min(_8562 + 1.0, 7.0) + _8556) * 0.125), 0.0).xyz, vec3(_8560 - _8562));
        break;
    } while(false);
    hp_copy_9921 = _9921;
    highp vec3 _9927 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9922 = vec3(0.0);
        vec3 _9922 = vec3(0.0);
        do
        {
            if (_8546)
            {
                vec2 _8754 = vec2(atan(_5377.z, _5377.x), asin(clamp(_5377.y, -1.0, 1.0)));
                highp vec2 hp_copy_8754 = _8754;
                _9922 = textureLod(prefiltered_radiance_b, (hp_copy_8754 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9907, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8773 = vec2(atan(_5377.z, _5377.x), asin(clamp(_5377.y, -1.0, 1.0)));
            highp vec2 hp_copy_8773 = _8773;
            highp vec2 _8778 = (hp_copy_8773 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8685 = clamp(_8778.y, 0.00390625, 0.99609375);
            float _8689 = clamp(_9907, 0.0, 1.0) * 7.0;
            float _8691 = floor(_8689);
            highp float _8710 = _8778.x;
            _9922 = mix(textureLod(prefiltered_radiance_b, vec2(_8710, (_8691 + _8685) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_8710, (min(_8691 + 1.0, 7.0) + _8685) * 0.125), 0.0).xyz, vec3(_8689 - _8691));
            break;
        } while(false);
        hp_copy_9922 = _9922;
        _9927 = hp_copy_9921 + hp_copy_9922;
    }
    else
    {
        _9927 = _9921;
    }
    float _5395 = frag_info.environment_intensity;
    highp float hp_copy_5395 = _5395;
    vec2 _5408 = clamp(vec2(_5166, _9907), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5410 = texture(brdf_lut, vec2(_5408.x * 0.3333333432674407958984375, _5408.y));
    float _5414 = _5410.x;
    float _5417 = _5410.y;
    vec3 _5419 = ((_5158 + ((max(vec3(1.0 - _9907), _5158) - _5158) * pow(clamp(1.0 - _5166, 0.0, 1.0), 5.0))) * _5414) + vec3(_5417);
    float _5425 = 1.0 - (_5414 + _5417);
    vec3 _5429 = vec3(1.0) - _5158;
    vec3 _5432 = _5158 + (_5429 * vec3(0.0476190485060214996337890625));
    vec3 _5443 = ((_5419 * _5425) * _5432) / (vec3(1.0) - (_5432 * _5425));
    float _5446 = 1.0 - _4259;
    float _9941 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9941 = clamp((pow(_5162 + _9936, exp2(((-16.0) * _9907) - 1.0)) - 1.0) + _9936, 0.0, 1.0);
    }
    else
    {
        _9941 = _9936;
    }
    highp vec3 _9974 = vec3(0.0);
    if (_5114)
    {
        highp vec3 _9958 = vec3(0.0);
        highp vec3 _9959 = vec3(0.0);
        do
        {
            float _8867 = max(dot(_9859, _9950), 0.0);
            highp float hp_copy_8867 = _8867;
            if (_8867 <= 0.0)
            {
                _9959 = vec3(0.0);
                _9958 = vec3(0.0);
                break;
            }
            float _8873 = max(_5162, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8873 = _8873;
            vec3 _8876 = _9950 + mp_copy_9918;
            float _8879 = dot(_8876, _8876);
            vec3 _9956 = vec3(0.0);
            vec3 _9957 = vec3(0.0);
            if (_8879 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8887 = _8876 * inversesqrt(_8879);
                float _9955 = 0.0;
                do
                {
                    float _8944 = dot(_9859, _8887);
                    if (_8944 <= 0.0)
                    {
                        _9955 = 0.0;
                        break;
                    }
                    float _8951 = _9907 * _9907;
                    vec3 _8954 = cross(_9859, _8887);
                    float _8957 = _8944 * _8951;
                    float _8966 = _8951 / (dot(_8954, _8954) + (_8957 * _8957));
                    _9955 = min((_8966 * _8966) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9004 = _5158 + (_5429 * pow(clamp(1.0 - max(dot(_8887, _9918), 0.0), 0.0, 1.0), 5.0));
                _9957 = (_9004 * min(_9955 * (0.5 / max(mix((2.0 * hp_copy_8867) * _8873, hp_copy_8867 + hp_copy_8873, hp_copy_9907 * hp_copy_9907), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9956 = _9004;
            }
            else
            {
                _9957 = vec3(0.0);
                _9956 = _5158;
            }
            _9959 = (_9957 * frag_info.directional_light_color.xyz) * _8867;
            _9958 = (((((vec3(1.0) - _9956) * _5446) * _5089) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8867;
            break;
        } while(false);
        _9974 = _9964 + ((_9958 + _9959) * _5149);
    }
    else
    {
        _9974 = _9964;
    }
    bool _5537 = _FogInfo.params0.y > 0.5;
    bool _5543 = false;
    if (_5537)
    {
        _5543 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5543 = _5537;
    }
    highp vec3 _9977 = vec3(0.0);
    if (_5543)
    {
        vec3 mp_copy_9975 = vec3(0.0);
        highp vec3 _9975 = vec3(0.0);
        if (_7206)
        {
            _9975 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9975 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9976 = vec3(0.0);
        mp_copy_9975 = _9975;
        vec3 _5548 = _5366 * (-mp_copy_9975);
        vec3 _9976 = vec3(0.0);
        do
        {
            if (_8546)
            {
                vec2 _9126 = vec2(atan(_5548.z, _5548.x), asin(clamp(_5548.y, -1.0, 1.0)));
                highp vec2 hp_copy_9126 = _9126;
                _9976 = textureLod(prefiltered_radiance, (hp_copy_9126 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9145 = vec2(atan(_5548.z, _5548.x), asin(clamp(_5548.y, -1.0, 1.0)));
            highp vec2 hp_copy_9145 = _9145;
            highp vec2 _9150 = (hp_copy_9145 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9057 = clamp(_9150.y, 0.00390625, 0.99609375);
            float _9063 = floor(0.0);
            highp float _9082 = _9150.x;
            _9976 = mix(textureLod(prefiltered_radiance, vec2(_9082, (_9063 + _9057) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9082, (min(_9063 + 1.0, 7.0) + _9057) * 0.125), 0.0).xyz, vec3(-_9063));
            break;
        } while(false);
        hp_copy_9976 = _9976;
        _9977 = hp_copy_9976 * hp_copy_5395;
    }
    else
    {
        _9977 = _FogInfo.color.xyz;
    }
    highp vec4 _5563 = vec4(min(((((((_5443 + ((_5089 * _5446) * ((vec3(1.0) - _5419) - _5443))) * (hp_copy_5380 * hp_copy_5395)) * vec3(_4293)) + (((_5419 * (_9927 * _5395)) * 1.0) * _9941)) * mix(1.0, _5149, frag_info.radiance_blend.y)) + (_9974 * mix(1.0, _9936, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9882, vec3(65504.0)), 1.0) * _10319;
    highp vec4 _9992 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9992 = _5563;
            break;
        }
        int _9194 = int(_FogInfo.params0.x + 0.5);
        if (_9194 == 0)
        {
            _9992 = _5563;
            break;
        }
        highp float _9979 = 0.0;
        if (_7206)
        {
            _9979 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9979 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9979 > _FogInfo.params1.w))
        {
            _9992 = _5563;
            break;
        }
        float _9983 = 0.0;
        if (_9194 == 1)
        {
            _9983 = clamp((_9979 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9984 = 0.0;
            if (_9194 == 2)
            {
                highp float _9982 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9980 = vec3(0.0);
                    if (_7206)
                    {
                        _9980 = v_position - (view_info.camera_forward.xyz * _9979);
                    }
                    else
                    {
                        _9980 = v_position + v_viewvector;
                    }
                    highp float _9285 = -_FogInfo.params2.y;
                    highp float _9292 = _FogInfo.params1.x * exp(_9285 * (_9980.y - _FogInfo.params2.x));
                    highp float _9309 = _FogInfo.params2.y * (v_position.y - _9980.y);
                    highp float _9981 = 0.0;
                    if (abs(_9309) > 0.00124999997206032276153564453125)
                    {
                        _9981 = (_9292 - (_FogInfo.params1.x * exp(_9285 * (v_position.y - _FogInfo.params2.x)))) / _9309;
                    }
                    else
                    {
                        _9981 = _9292;
                    }
                    _9982 = _9981 * max(_9979 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9982 = _FogInfo.params1.x * max(_9979 - _FogInfo.params1.y, 0.0);
                }
                _9984 = 1.0 - exp(-_9982);
            }
            else
            {
                highp float _9247 = _FogInfo.params1.x * max(_9979 - _FogInfo.params1.y, 0.0);
                _9984 = 1.0 - exp((-_9247) * _9247);
            }
            _9983 = _9984;
        }
        highp float _9349 = min(_9983, _FogInfo.params0.z);
        if (_9349 <= 0.0)
        {
            _9992 = _5563;
            break;
        }
        highp vec3 _9362 = mix(_FogInfo.color.xyz, _9977, vec3(_FogInfo.params0.w));
        bool _9365 = _FogInfo.sun.w > 0.5;
        bool _9371 = false;
        if (_9365)
        {
            _9371 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _9371 = _9365;
        }
        vec3 _9988 = vec3(0.0);
        if (_9371)
        {
            vec3 mp_copy_9985 = vec3(0.0);
            highp vec3 _9985 = vec3(0.0);
            if (_7206)
            {
                _9985 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9985 = normalize(v_viewvector);
            }
            mp_copy_9985 = _9985;
            highp float _9387 = pow(max(dot(-mp_copy_9985, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_9387 = _9387;
            _9988 = _9362 + ((_FogInfo.sun.xyz * mp_copy_9387) * _FogInfo.params2.z);
        }
        else
        {
            _9988 = _9362;
        }
        highp float _9400 = _5563.w;
        float mp_copy_9400 = _9400;
        _9992 = vec4(mix(_5563.xyz, _9988 * mp_copy_9400, vec3(_9349)), _9400);
        break;
    } while(false);
    vec4 _9994 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9994 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9994 = _9992;
        break;
    } while(false);
    frag_color = _9994;
    float _9995 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9995 = 1.0;
    }
    else
    {
        _9995 = abs(frag_info.fade);
    }
    frag_color *= _9995;
}

