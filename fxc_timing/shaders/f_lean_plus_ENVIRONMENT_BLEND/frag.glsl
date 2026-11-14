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
    highp float _4263 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4263 = _4263;
    vec3 _4267 = normalize(v_normal) * mp_copy_4263;
    vec4 _4309 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4312 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _10606 = vec2(0.0);
    if (_4312)
    {
        highp vec2 _10605 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _10605 = v_texture_coords_1;
        }
        else
        {
            _10605 = v_texture_coords;
        }
        highp vec2 _4512 = _10605 * texture_transforms.base_color_transform.zw;
        highp float _4518 = _4512.x;
        highp float _4523 = _4512.y;
        _10606 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4518) + (texture_transforms.base_color_rotation.y * _4523), ((-texture_transforms.base_color_rotation.y) * _4518) + (texture_transforms.base_color_rotation.x * _4523));
    }
    else
    {
        _10606 = v_texture_coords;
    }
    vec4 _4326 = texture(base_color_texture, _10606);
    vec3 _4328 = _4326.xyz;
    float _11136 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4326.w * _4309.w) * frag_info.color.w);
    vec3 _10621 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _10609 = vec2(0.0);
        if (_4312)
        {
            highp vec2 _10608 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _10608 = v_texture_coords_1;
            }
            else
            {
                _10608 = v_texture_coords;
            }
            highp vec2 _4607 = _10608 * texture_transforms.normal_transform.zw;
            highp float _4613 = _4607.x;
            highp float _4618 = _4607.y;
            _10609 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4613) + (texture_transforms.normal_rotation.y * _4618), ((-texture_transforms.normal_rotation.y) * _4613) + (texture_transforms.normal_rotation.x * _4618));
        }
        else
        {
            _10609 = v_texture_coords;
        }
        vec3 _4666 = ((texture(normal_texture, _10609).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4670 = _4666.xy * vec2(frag_info.normal_scale);
        vec3 _10305 = _4666;
        _10305.x = _4670.x;
        _10305.y = _4670.y;
        highp vec3 _4676 = -v_viewvector;
        highp vec3 _4766 = dFdx(_4676);
        highp vec3 _4768 = dFdy(_4676);
        highp vec2 _4770 = dFdx(_10609);
        highp vec2 _4772 = dFdy(_10609);
        bvec2 _11138 = bvec2(length(_4770) == 0.0);
        highp vec2 _11139 = vec2(_11138.x ? vec2(1.0, 0.0).x : _4770.x, _11138.y ? vec2(1.0, 0.0).y : _4770.y);
        bvec2 _11140 = bvec2(length(_4772) == 0.0);
        highp vec2 _11141 = vec2(_11140.x ? vec2(0.0, 1.0).x : _4772.x, _11140.y ? vec2(0.0, 1.0).y : _4772.y);
        highp vec3 _4785 = cross(_4768, _4267);
        highp vec3 _4788 = cross(_4267, _4766);
        highp float _4813 = (dot(cross(_4766, _4768), _4267) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4816 = ((_4785 * _11139.x) + (_4788 * _11141.x)) * _4813;
        highp float _10616 = 0.0;
        if (gl_FrontFacing)
        {
            _10616 = -_4813;
        }
        else
        {
            _10616 = _4813;
        }
        highp vec3 _4826 = ((_4785 * _11139.y) + (_4788 * _11141.y)) * _10616;
        highp float _4835 = inversesqrt(max(max(dot(_4816, _4816), dot(_4826, _4826)), 9.9999996826552253889678874634872e-21));
        vec3 _4707 = v_tangent.xyz - (_4267 * dot(_4267, v_tangent.xyz));
        highp float _4710 = dot(_4707, _4707);
        bool _4712 = _4710 > 1.0000000133514319600180897396058e-10;
        bool _4719 = false;
        if (_4712)
        {
            _4719 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4719 = _4712;
        }
        mat3 _10619 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4719)
        {
            highp vec3 _4724 = _4707 * inversesqrt(_4710);
            _10619 = mat3(_4724, normalize(cross(_4267, _4724)) * sign(v_tangent.w), _4267);
        }
        else
        {
            _10619 = mat3(_4816 * _4835, _4826 * _4835, _4267);
        }
        _10621 = normalize(_10619 * _10305);
    }
    else
    {
        _10621 = _4267;
    }
    highp vec2 _10623 = vec2(0.0);
    if (_4312)
    {
        highp vec2 _10622 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _10622 = v_texture_coords_1;
        }
        else
        {
            _10622 = v_texture_coords;
        }
        highp vec2 _4900 = _10622 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4906 = _4900.x;
        highp float _4911 = _4900.y;
        _10623 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4906) + (texture_transforms.metallic_roughness_rotation.y * _4911), ((-texture_transforms.metallic_roughness_rotation.y) * _4906) + (texture_transforms.metallic_roughness_rotation.x * _4911));
    }
    else
    {
        _10623 = v_texture_coords;
    }
    vec4 _4395 = texture(metallic_roughness_texture, _10623);
    float _4401 = clamp(_4395.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4408 = clamp(_4395.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _10625 = vec2(0.0);
    if (_4312)
    {
        highp vec2 _10624 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _10624 = v_texture_coords_1;
        }
        else
        {
            _10624 = v_texture_coords;
        }
        highp vec2 _4971 = _10624 * texture_transforms.occlusion_transform.zw;
        highp float _4977 = _4971.x;
        highp float _4982 = _4971.y;
        _10625 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4977) + (texture_transforms.occlusion_rotation.y * _4982), ((-texture_transforms.occlusion_rotation.y) * _4977) + (texture_transforms.occlusion_rotation.x * _4982));
    }
    else
    {
        _10625 = v_texture_coords;
    }
    float _10626 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _10626 = texture(occlusion_texture, _10625).x;
    }
    else
    {
        _10626 = 1.0;
    }
    float _4435 = 1.0 - ((1.0 - _10626) * frag_info.occlusion_strength);
    highp vec2 _10628 = vec2(0.0);
    if (_4312)
    {
        highp vec2 _10627 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _10627 = v_texture_coords_1;
        }
        else
        {
            _10627 = v_texture_coords;
        }
        highp vec2 _5042 = _10627 * texture_transforms.emissive_transform.zw;
        highp float _5048 = _5042.x;
        highp float _5053 = _5042.y;
        _10628 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5048) + (texture_transforms.emissive_rotation.y * _5053), ((-texture_transforms.emissive_rotation.y) * _5048) + (texture_transforms.emissive_rotation.x * _5053));
    }
    else
    {
        _10628 = v_texture_coords;
    }
    vec3 _4454 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _10644 = vec3(0.0);
    if (dot(abs(_4454), vec3(1.0)) > 0.0)
    {
        vec3 _4463 = texture(emissive_texture, _10628).xyz;
        _10644 = mix(_4463 * vec3(0.077399380505084991455078125), pow((_4463 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4463)) * _4454;
    }
    else
    {
        _10644 = vec3(0.0);
    }
    highp float hp_copy_10669 = 0.0;
    vec3 _5236 = vec4((mix(_4328 * vec3(0.077399380505084991455078125), pow((_4328 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4328)) * _4309.xyz) * frag_info.color.xyz, _11136).xyz;
    vec3 _5743 = dFdx(_10621);
    vec3 _5745 = dFdy(_10621);
    float _10669 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10669 = sqrt(clamp((_4408 * _4408) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5743, _5743), dot(_5745, _5745))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10669 = _4408;
    }
    hp_copy_10669 = _10669;
    float _10700 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _10700 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _10700 = _4435;
    }
    bool _5261 = frag_info.has_directional_light > 0.5;
    float _10670 = 0.0;
    vec3 _10714 = vec3(0.0);
    if (_5261)
    {
        highp vec3 _5267 = -normalize(frag_info.directional_light_direction.xyz);
        _10714 = _5267;
        _10670 = dot(_4267, _5267);
    }
    else
    {
        _10714 = vec3(0.0);
        _10670 = 0.0;
    }
    float _5274 = clamp(_10670 * 6.666666507720947265625, 0.0, 1.0);
    bool _5283 = false;
    if (_5261)
    {
        _5283 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5283 = _5261;
    }
    float _10679 = 0.0;
    if (_5283 && (_5274 > 0.0))
    {
        int _5824 = int(frag_info.shadow_cascade_count);
        float _6019 = max(dot(_4267, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6022 = _6019 * _6019;
        highp vec3 _6042 = v_position + (_4267 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6022, 0.0)) / _6022, 8.0))));
        highp float _5830 = frag_info.directional_light_color.w * 0.5;
        float _5832 = frag_info.dielectric_f0.w;
        highp float hp_copy_5832 = _5832;
        float _10671 = 0.0;
        if (_5832 > 0.0)
        {
            _10671 = smoothstep(_5832 - max(frag_info.shadow_fade, hp_copy_5832 * 0.100000001490116119384765625), _5832, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10671 = 0.0;
        }
        float _10673 = 0.0;
        float _10675 = 0.0;
        if (_10671 < 1.0)
        {
            float _10674 = 0.0;
            float _10676 = 0.0;
            _10676 = 0.0;
            _10674 = 0.0;
            float _10961 = 0.0;
            float _10964 = 0.0;
            for (int _10672 = 0; _10672 < _5824; _10676 = _10964, _10674 = _10961, _10672++)
            {
                if (_10676 < 1.0)
                {
                    highp vec4 _5864 = vec4(_6042, 1.0);
                    highp vec4 _10833 = vec4(0.0);
                    highp float _10836 = 0.0;
                    if (_10672 == 0)
                    {
                        _10836 = frag_info.cascade_box_sizes.x;
                        _10833 = frag_info.light_space_matrix[0] * _5864;
                    }
                    else
                    {
                        highp vec4 _10834 = vec4(0.0);
                        highp float _10837 = 0.0;
                        if (_10672 == 1)
                        {
                            _10837 = frag_info.cascade_box_sizes.y;
                            _10834 = frag_info.light_space_matrix[1] * _5864;
                        }
                        else
                        {
                            highp vec4 _10835 = vec4(0.0);
                            highp float _10838 = 0.0;
                            if (_10672 == 2)
                            {
                                _10838 = frag_info.cascade_box_sizes.z;
                                _10835 = frag_info.light_space_matrix[2] * _5864;
                            }
                            else
                            {
                                _10838 = frag_info.cascade_box_sizes.w;
                                _10835 = frag_info.light_space_matrix[3] * _5864;
                            }
                            _10837 = _10838;
                            _10834 = _10835;
                        }
                        _10836 = _10837;
                        _10833 = _10834;
                    }
                    highp vec3 _5909 = _10833.xyz / vec3(_10833.w);
                    highp vec2 _5912 = _5909.xy * 0.5;
                    highp vec2 _5914 = _5912 + vec2(0.5);
                    highp float _5921 = max(frag_info.shadow_softness / _10836, frag_info.shadow_texel_size);
                    highp float _5923 = _5914.x;
                    bool _5925 = _5923 < _5921;
                    bool _5934 = false;
                    if (!_5925)
                    {
                        _5934 = _5923 > (1.0 - _5921);
                    }
                    else
                    {
                        _5934 = _5925;
                    }
                    bool _5942 = false;
                    if (!_5934)
                    {
                        _5942 = _5914.y < _5921;
                    }
                    else
                    {
                        _5942 = _5934;
                    }
                    bool _5951 = false;
                    if (!_5942)
                    {
                        _5951 = _5914.y > (1.0 - _5921);
                    }
                    else
                    {
                        _5951 = _5942;
                    }
                    bool _5958 = false;
                    if (!_5951)
                    {
                        _5958 = _5909.z < 0.0;
                    }
                    else
                    {
                        _5958 = _5951;
                    }
                    bool _5965 = false;
                    if (!_5958)
                    {
                        _5965 = _5909.z > 1.0;
                    }
                    else
                    {
                        _5965 = _5958;
                    }
                    float _10962 = 0.0;
                    float _10965 = 0.0;
                    if (!_5965)
                    {
                        highp vec2 _6058 = vec2(_5921);
                        highp vec2 _6063 = vec2(_5921 + max(_5830, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6071 = vec2(0.5) - _5912;
                        highp vec2 _6073 = smoothstep(_6058, _6063, _5914) * smoothstep(_6058, _6063, _6071);
                        float _10839 = 0.0;
                        if (_5830 > 0.0)
                        {
                            _10839 = _6073.x * _6073.y;
                        }
                        else
                        {
                            _10839 = 1.0;
                        }
                        float _5974 = min(_10839, 1.0 - _10676);
                        float _10963 = 0.0;
                        float _10966 = 0.0;
                        if (_5974 > 0.0)
                        {
                            highp float _6212 = _5909.z - (frag_info.shadow_bias / (7.0 * _10836));
                            highp float _6218 = 1.0 / (float(_5824) + frag_info.spot_shadow_params.x);
                            highp float _6220 = frag_info.directional_light_direction.w;
                            float mp_copy_6220 = _6220;
                            float _6226 = step(0.5, mp_copy_6220) * (1.0 - step(1.5, mp_copy_6220));
                            float _10869 = 0.0;
                            float _10873 = 0.0;
                            if (_6226 < 0.5)
                            {
                                highp float _6237 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6237 = _6237;
                                _10873 = sin(mp_copy_6237);
                                _10869 = cos(mp_copy_6237);
                            }
                            else
                            {
                                _10873 = 0.0;
                                _10869 = 1.0;
                            }
                            highp float _10876 = 0.0;
                            if ((_6220 > 1.5) && (_6220 < 2.5))
                            {
                                highp float _6261 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6266 = max(_6261 * _6212, frag_info.shadow_texel_size);
                                float _10865 = 0.0;
                                highp float _10866 = 0.0;
                                _10866 = 0.0;
                                _10865 = 0.0;
                                highp float _6288 = 0.0;
                                float _6291 = 0.0;
                                for (int _10864 = 0; _10864 < 9; _10866 = _6288, _10865 = _6291, _10864++)
                                {
                                    vec2 _10955 = vec2(0.0);
                                    do
                                    {
                                        if (_10864 == 0)
                                        {
                                            _10955 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10864 == 1)
                                        {
                                            _10955 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10864 == 2)
                                        {
                                            _10955 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10864 == 3)
                                        {
                                            _10955 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10864 == 4)
                                        {
                                            _10955 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10864 == 5)
                                        {
                                            _10955 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10864 == 6)
                                        {
                                            _10955 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10864 == 7)
                                        {
                                            _10955 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10864 == 8)
                                        {
                                            _10955 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10864 == 9)
                                        {
                                            _10955 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10864 == 10)
                                        {
                                            _10955 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10864 == 11)
                                        {
                                            _10955 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10864 == 12)
                                        {
                                            _10955 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10864 == 13)
                                        {
                                            _10955 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10864 == 14)
                                        {
                                            _10955 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10864 == 15)
                                        {
                                            _10955 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10955 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6595 = clamp(_5914 + (vec2((_10955.x * _10869) - (_10955.y * _10873), (_10955.x * _10873) + (_10955.y * _10869)) * _6266), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6604 = _6595.y;
                                    highp vec2 _6605 = vec2((float(_10672) + _6595.x) * _6218, _6604);
                                    _6605.y = 1.0 - _6604;
                                    highp vec4 _6612 = textureLod(shadow_map, _6605, 0.0);
                                    highp float _6613 = _6612.x;
                                    highp float _6283 = step(_6613, _6212);
                                    float mp_copy_6283 = _6283;
                                    _6288 = _10866 + (_6613 * _6283);
                                    _6291 = _10865 + mp_copy_6283;
                                }
                                highp float _10867 = 0.0;
                                if (_10865 > 0.0)
                                {
                                    _10867 = _10866 / _10865;
                                }
                                else
                                {
                                    _10867 = _6212;
                                }
                                _10876 = clamp(_6261 * max(_6212 - _10867, 0.0), frag_info.shadow_texel_size, _5921);
                            }
                            else
                            {
                                _10876 = _5921;
                            }
                            bool _6322 = _6220 > 2.5;
                            bool _10877 = false;
                            float _10901 = 0.0;
                            if ((_6220 < 1.5) || _6322)
                            {
                                highp vec2 _6646 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6650 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6651 = clamp(_5914, _6646, _6650);
                                highp float _6653 = float(_10672);
                                highp float _6660 = _6651.y;
                                highp vec2 _6661 = vec2((_6653 + _6651.x) * _6218, _6660);
                                _6661.y = 1.0 - _6660;
                                highp float _6673 = float(_6212 <= textureLod(shadow_map, _6661, 0.0).x);
                                float mp_copy_6673 = _6673;
                                float _6683 = (-1.0) * _10869;
                                float _6687 = (-1.0) * _10873;
                                highp vec2 _6711 = clamp(_5914 + (vec2(_6683 - _6687, _6687 + _6683) * _10876), _6646, _6650);
                                highp float _6720 = _6711.y;
                                highp vec2 _6721 = vec2((_6653 + _6711.x) * _6218, _6720);
                                _6721.y = 1.0 - _6720;
                                highp float _6733 = float(_6212 <= textureLod(shadow_map, _6721, 0.0).x);
                                float mp_copy_6733 = _6733;
                                highp vec2 _6771 = clamp(_5914 + (vec2(_10869 - _6687, _10873 + _6683) * _10876), _6646, _6650);
                                highp float _6780 = _6771.y;
                                highp vec2 _6781 = vec2((_6653 + _6771.x) * _6218, _6780);
                                _6781.y = 1.0 - _6780;
                                highp float _6793 = float(_6212 <= textureLod(shadow_map, _6781, 0.0).x);
                                float mp_copy_6793 = _6793;
                                highp vec2 _6831 = clamp(_5914 + (vec2(_6683 - _10873, _6687 + _10869) * _10876), _6646, _6650);
                                highp float _6840 = _6831.y;
                                highp vec2 _6841 = vec2((_6653 + _6831.x) * _6218, _6840);
                                _6841.y = 1.0 - _6840;
                                highp float _6853 = float(_6212 <= textureLod(shadow_map, _6841, 0.0).x);
                                float mp_copy_6853 = _6853;
                                highp vec2 _6891 = clamp(_5914 + (vec2(_10869 - _10873, _10873 + _10869) * _10876), _6646, _6650);
                                highp float _6900 = _6891.y;
                                highp vec2 _6901 = vec2((_6653 + _6891.x) * _6218, _6900);
                                _6901.y = 1.0 - _6900;
                                highp float _6913 = float(_6212 <= textureLod(shadow_map, _6901, 0.0).x);
                                float mp_copy_6913 = _6913;
                                float _6368 = (((mp_copy_6673 + mp_copy_6733) + mp_copy_6793) + mp_copy_6853) + mp_copy_6913;
                                _10901 = _6368 * 0.20000000298023223876953125;
                                _10877 = (_6368 < 0.5) || (_6368 > 4.5);
                            }
                            else
                            {
                                _10901 = 0.0;
                                _10877 = false;
                            }
                            float _10900 = 0.0;
                            if (_10877)
                            {
                                _10900 = _10901;
                            }
                            else
                            {
                                float _10902 = 0.0;
                                if (_6322)
                                {
                                    highp vec2 _6941 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6945 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6946 = clamp(_5914 + (vec2(-0.707099974155426025390625) * _10876), _6941, _6945);
                                    highp vec2 _6957 = (vec2(_6946.x, 1.0 - _6946.y) / _6941) - vec2(0.5);
                                    highp vec2 _6959 = floor(_6957);
                                    highp vec2 _6962 = _6957 - _6959;
                                    highp vec2 _6967 = (_6959 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6969 = float(_10672);
                                    highp vec2 _6977 = vec2((_6969 + _6967.x) * _6218, _6967.y);
                                    highp float _6981 = frag_info.shadow_texel_size * _6218;
                                    highp vec2 _6984 = vec2(_6981, frag_info.shadow_texel_size);
                                    highp vec2 _6993 = vec2(_6981, 0.0);
                                    highp vec2 _7001 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7030 = _6962.x;
                                    highp float _7039 = mix(mix(float(_6212 <= textureLod(shadow_map, _6977, 0.0).x), float(_6212 <= textureLod(shadow_map, _6977 + _6993, 0.0).x), _7030), mix(float(_6212 <= textureLod(shadow_map, _6977 + _7001, 0.0).x), float(_6212 <= textureLod(shadow_map, _6977 + _6984, 0.0).x), _7030), _6962.y);
                                    float mp_copy_7039 = _7039;
                                    highp vec2 _7073 = clamp(_5914 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10876), _6941, _6945);
                                    highp vec2 _7084 = (vec2(_7073.x, 1.0 - _7073.y) / _6941) - vec2(0.5);
                                    highp vec2 _7086 = floor(_7084);
                                    highp vec2 _7089 = _7084 - _7086;
                                    highp vec2 _7094 = (_7086 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7104 = vec2((_6969 + _7094.x) * _6218, _7094.y);
                                    highp float _7157 = _7089.x;
                                    highp float _7166 = mix(mix(float(_6212 <= textureLod(shadow_map, _7104, 0.0).x), float(_6212 <= textureLod(shadow_map, _7104 + _6993, 0.0).x), _7157), mix(float(_6212 <= textureLod(shadow_map, _7104 + _7001, 0.0).x), float(_6212 <= textureLod(shadow_map, _7104 + _6984, 0.0).x), _7157), _7089.y);
                                    float mp_copy_7166 = _7166;
                                    highp vec2 _7200 = clamp(_5914 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10876), _6941, _6945);
                                    highp vec2 _7211 = (vec2(_7200.x, 1.0 - _7200.y) / _6941) - vec2(0.5);
                                    highp vec2 _7213 = floor(_7211);
                                    highp vec2 _7216 = _7211 - _7213;
                                    highp vec2 _7221 = (_7213 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7231 = vec2((_6969 + _7221.x) * _6218, _7221.y);
                                    highp float _7284 = _7216.x;
                                    highp float _7293 = mix(mix(float(_6212 <= textureLod(shadow_map, _7231, 0.0).x), float(_6212 <= textureLod(shadow_map, _7231 + _6993, 0.0).x), _7284), mix(float(_6212 <= textureLod(shadow_map, _7231 + _7001, 0.0).x), float(_6212 <= textureLod(shadow_map, _7231 + _6984, 0.0).x), _7284), _7216.y);
                                    float mp_copy_7293 = _7293;
                                    highp vec2 _7327 = clamp(_5914 + (vec2(0.707099974155426025390625) * _10876), _6941, _6945);
                                    highp vec2 _7338 = (vec2(_7327.x, 1.0 - _7327.y) / _6941) - vec2(0.5);
                                    highp vec2 _7340 = floor(_7338);
                                    highp vec2 _7343 = _7338 - _7340;
                                    highp vec2 _7348 = (_7340 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7358 = vec2((_6969 + _7348.x) * _6218, _7348.y);
                                    highp float _7411 = _7343.x;
                                    highp float _7420 = mix(mix(float(_6212 <= textureLod(shadow_map, _7358, 0.0).x), float(_6212 <= textureLod(shadow_map, _7358 + _6993, 0.0).x), _7411), mix(float(_6212 <= textureLod(shadow_map, _7358 + _7001, 0.0).x), float(_6212 <= textureLod(shadow_map, _7358 + _6984, 0.0).x), _7411), _7343.y);
                                    float mp_copy_7420 = _7420;
                                    _10902 = (((mp_copy_7039 + mp_copy_7166) + mp_copy_7293) + mp_copy_7420) * 0.25;
                                }
                                else
                                {
                                    int _6415 = (_6226 > 0.5) ? 17 : 16;
                                    float _10896 = 0.0;
                                    _10896 = 0.0;
                                    float _6443 = 0.0;
                                    for (int _10878 = 0; _10878 < 17; _10896 = _6443, _10878++)
                                    {
                                        if (_10878 >= _6415)
                                        {
                                            break;
                                        }
                                        vec2 _10879 = vec2(0.0);
                                        do
                                        {
                                            if (_10878 == 0)
                                            {
                                                _10879 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10878 == 1)
                                            {
                                                _10879 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10878 == 2)
                                            {
                                                _10879 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10878 == 3)
                                            {
                                                _10879 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10878 == 4)
                                            {
                                                _10879 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10878 == 5)
                                            {
                                                _10879 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10878 == 6)
                                            {
                                                _10879 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10878 == 7)
                                            {
                                                _10879 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10878 == 8)
                                            {
                                                _10879 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10878 == 9)
                                            {
                                                _10879 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10878 == 10)
                                            {
                                                _10879 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10878 == 11)
                                            {
                                                _10879 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10878 == 12)
                                            {
                                                _10879 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10878 == 13)
                                            {
                                                _10879 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10878 == 14)
                                            {
                                                _10879 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10878 == 15)
                                            {
                                                _10879 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10879 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10881 = vec2(0.0);
                                        do
                                        {
                                            if (_10878 < 3)
                                            {
                                                _10881 = vec2(float(_10878) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10878 < 6)
                                            {
                                                _10881 = vec2((float(_10878 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10878 < 11)
                                            {
                                                _10881 = vec2((float(_10878 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10878 < 14)
                                            {
                                                _10881 = vec2((float(_10878 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10881 = vec2(float(_10878 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6432 = mix(_10879, _10881, vec2(_6226));
                                        float _7560 = _6432.x;
                                        float _7564 = _6432.y;
                                        highp vec2 _7590 = clamp(_5914 + (vec2((_7560 * _10869) - (_7564 * _10873), (_7560 * _10873) + (_7564 * _10869)) * _10876), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7599 = _7590.y;
                                        highp vec2 _7600 = vec2((float(_10672) + _7590.x) * _6218, _7599);
                                        _7600.y = 1.0 - _7599;
                                        highp float _7612 = float(_6212 <= textureLod(shadow_map, _7600, 0.0).x);
                                        float mp_copy_7612 = _7612;
                                        _6443 = _10896 + mp_copy_7612;
                                    }
                                    _10902 = _10896 / float(_6415);
                                }
                                _10900 = _10902;
                            }
                            bool _6457 = _10672 == (_5824 - 1);
                            bool _6463 = false;
                            if (_6457)
                            {
                                _6463 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6463 = _6457;
                            }
                            float _10903 = 0.0;
                            if (_6463)
                            {
                                highp vec2 _6470 = vec2(frag_info.shadow_fade / _10836);
                                highp vec2 _6478 = smoothstep(vec2(0.0), _6470, _5914) * smoothstep(vec2(0.0), _6470, _6071);
                                _10903 = mix(1.0, _10900, _6478.x * _6478.y);
                            }
                            else
                            {
                                _10903 = _10900;
                            }
                            _10966 = _10676 + _5974;
                            _10963 = _10674 + (_5974 * _10903);
                        }
                        else
                        {
                            _10966 = _10676;
                            _10963 = _10674;
                        }
                        _10965 = _10966;
                        _10962 = _10963;
                    }
                    else
                    {
                        _10965 = _10676;
                        _10962 = _10674;
                    }
                    _10964 = _10965;
                    _10961 = _10962;
                }
                else
                {
                    _10964 = _10676;
                    _10961 = _10674;
                }
            }
            _10675 = _10676;
            _10673 = _10674;
        }
        else
        {
            _10675 = 0.0;
            _10673 = 0.0;
        }
        _10679 = mix(_10673 + (1.0 - _10675), 1.0, _10671);
    }
    else
    {
        _10679 = 1.0;
    }
    vec3 mp_copy_10680 = vec3(0.0);
    float _5296 = _5274 * _10679;
    bool _7619 = view_info.camera_forward.w > 0.5;
    highp vec3 _10680 = vec3(0.0);
    if (_7619)
    {
        _10680 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10680 = normalize(v_viewvector);
    }
    highp float _7663 = 0.0;
    mp_copy_10680 = _10680;
    vec3 _5305 = mix(frag_info.dielectric_f0.xyz, _5236, vec3(_4401));
    float _5309 = max(dot(_10621, _10680), 0.0);
    float _5313 = max(dot(_4267, _10680), 0.0);
    highp vec2 _10681 = vec2(0.0);
    do
    {
        _7663 = frag_info.punctual_dims.x;
        if (_7663 < 0.5)
        {
            _10681 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7675 = v_position - frag_info.camera_position.xyz;
            highp float _7690 = dot(_7675, frag_info.camera_forward.xyz);
            highp float _7696 = max(_7690, 9.9999997473787516355514526367188e-05);
            highp vec2 _7799 = (vec3(dot(_7675, frag_info.camera_right.xyz), dot(_7675, frag_info.camera_up.xyz), _7696).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7696, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7814 = float(int(((((clamp(floor((log2(max(_7690 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7799.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7799.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10681 = vec2(textureLod(punctual_index, vec2((mod(_7814, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7814 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10681 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5322 = int(_10681.x + 0.5);
    mediump int _5326 = int(_10681.y + 0.5);
    highp vec3 _10726 = vec3(0.0);
    _10726 = vec3(0.0);
    highp vec3 _11077 = vec3(0.0);
    for (int _10682 = 0; _10682 < _5326; _10726 = _11077, _10682++)
    {
        highp float hp_copy_10785 = 0.0;
        highp float _7847 = float(_5322 + _10682);
        highp float _7878 = (float(int(textureLod(punctual_index, vec2((mod(_7847, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7847 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7663;
        highp vec4 _7882 = textureLod(punctual_lights, vec2(0.0625, _7878), 0.0);
        highp vec4 _7899 = textureLod(punctual_lights, vec2(0.1875, _7878), 0.0);
        highp float _5344 = _7882.w;
        highp vec3 _5346 = _7899.xyz;
        vec3 _10771 = vec3(0.0);
        highp vec3 _10782 = vec3(0.0);
        float _10785 = 0.0;
        if (_5344 < 0.5)
        {
            _10785 = _10669;
            _10782 = _5346;
            _10771 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7878), 0.0).xyz);
        }
        else
        {
            highp vec3 _5360 = _7882.xyz - v_position;
            highp float _5363 = dot(_5360, _5360);
            highp float _5367 = inversesqrt(max(_5363, 9.9999999392252902907785028219223e-09));
            highp vec3 _5368 = _5360 * _5367;
            vec3 mp_copy_5368 = _5368;
            highp float _5370 = _7899.w;
            highp float _5375 = (_5363 * _5370) * _5370;
            highp float _5380 = clamp(1.0 - (_5375 * _5375), 0.0, 1.0);
            float mp_copy_5380 = _5380;
            if (_5380 <= 0.0)
            {
                _11077 = _10726;
                continue;
            }
            highp vec4 _7933 = textureLod(punctual_lights, vec2(0.4375, _7878), 0.0);
            highp float _5388 = _7933.w;
            float _10787 = 0.0;
            if (_5388 > 0.0)
            {
                highp float _5415 = (_10669 * _10669) + ((_5388 * 0.5) * _5367);
                float mp_copy_5415 = _5415;
                _10787 = sqrt(min(mp_copy_5415, 1.0));
            }
            else
            {
                _10787 = _10669;
            }
            highp vec3 _5422 = _5346 * ((mp_copy_5380 * mp_copy_5380) / max(pow(max(_5363, _5388 * _5388), _7933.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10783 = vec3(0.0);
            if (_5344 > 1.5)
            {
                highp vec4 _7950 = textureLod(punctual_lights, vec2(0.3125, _7878), 0.0);
                highp float _5441 = clamp((dot(normalize(_7950.xyz), -mp_copy_5368) * _7950.w) + _7933.x, 0.0, 1.0);
                float mp_copy_5441 = _5441;
                highp vec3 _5446 = _5422 * (mp_copy_5441 * mp_copy_5441);
                if (_5441 <= 0.0)
                {
                    _11077 = _10726;
                    continue;
                }
                bool _5452 = _5441 > 0.0;
                bool _5458 = false;
                if (_5452)
                {
                    _5458 = _7933.y > (-0.5);
                }
                else
                {
                    _5458 = _5452;
                }
                bool _5464 = false;
                if (_5458)
                {
                    _5464 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5464 = _5458;
                }
                highp vec3 _10784 = vec3(0.0);
                if (_5464)
                {
                    float _10762 = 0.0;
                    do
                    {
                        highp vec4 _8062 = mat4(textureLod(punctual_lights, vec2(0.5625, _7878), 0.0), textureLod(punctual_lights, vec2(0.6875, _7878), 0.0), textureLod(punctual_lights, vec2(0.8125, _7878), 0.0), textureLod(punctual_lights, vec2(0.9375, _7878), 0.0)) * vec4(v_position + (_4267 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8064 = _8062.w;
                        if (_8064 <= 0.0)
                        {
                            _10762 = 1.0;
                            break;
                        }
                        highp vec3 _8073 = _8062.xyz / vec3(_8064);
                        highp vec2 _8078 = (_8073.xy * 0.5) + vec2(0.5);
                        highp float _8080 = _8078.x;
                        bool _8081 = _8080 < 0.0;
                        bool _8088 = false;
                        if (!_8081)
                        {
                            _8088 = _8080 > 1.0;
                        }
                        else
                        {
                            _8088 = _8081;
                        }
                        bool _8095 = false;
                        if (!_8088)
                        {
                            _8095 = _8078.y < 0.0;
                        }
                        else
                        {
                            _8095 = _8088;
                        }
                        bool _8102 = false;
                        if (!_8095)
                        {
                            _8102 = _8078.y > 1.0;
                        }
                        else
                        {
                            _8102 = _8095;
                        }
                        bool _8109 = false;
                        if (!_8102)
                        {
                            _8109 = _8073.z < 0.0;
                        }
                        else
                        {
                            _8109 = _8102;
                        }
                        bool _8116 = false;
                        if (!_8109)
                        {
                            _8116 = _8073.z > 1.0;
                        }
                        else
                        {
                            _8116 = _8109;
                        }
                        if (_8116)
                        {
                            _10762 = 1.0;
                            break;
                        }
                        highp float _8123 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8128 = frag_info.shadow_cascade_count + float(int(_7933.y + 0.5));
                        highp float _8133 = _8073.z - frag_info.spot_shadow_params.y;
                        highp float _8144 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8144 = _8144;
                        highp vec2 _8151 = vec2(cos(mp_copy_8144), sin(mp_copy_8144)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8153 = _8151.x;
                        highp float _8155 = _8151.y;
                        highp vec2 _8163 = vec2(_8153 - _8155, _8153 + _8155) * 0.707106769084930419921875;
                        highp float _8356 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8080, 0.0, 1.0)) / _8123, 1.0 - clamp(_8078.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8356 = _8356;
                        highp vec2 _8171 = _8078 + _8151;
                        highp float _8378 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8171.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8171.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8378 = _8378;
                        highp vec2 _8179 = _8078 - _8151;
                        highp float _8400 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8179.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8179.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8400 = _8400;
                        highp vec2 _8192 = _8078 + vec2(-_8155, _8153);
                        highp float _8422 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8192.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8192.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8422 = _8422;
                        highp vec2 _8205 = _8078 + vec2(_8155, -_8153);
                        highp float _8444 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8205.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8205.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8444 = _8444;
                        float _8210 = (((mp_copy_8356 + mp_copy_8378) + mp_copy_8400) + mp_copy_8422) + mp_copy_8444;
                        if ((_8210 < 0.5) || (_8210 > 4.5))
                        {
                            _10762 = _8210 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8222 = _8078 + _8163;
                        highp float _8466 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8222.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8222.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8466 = _8466;
                        highp vec2 _8229 = _8078 - _8163;
                        highp float _8488 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8229.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8229.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8488 = _8488;
                        highp float _8237 = _8163.y;
                        highp float _8240 = _8163.x;
                        highp vec2 _8242 = _8078 + vec2(-_8237, _8240);
                        highp float _8510 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8242.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8242.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8510 = _8510;
                        highp vec2 _8255 = _8078 + vec2(_8237, -_8240);
                        highp float _8532 = float(_8133 <= textureLod(shadow_map, vec2((_8128 + clamp(_8255.x, 0.0, 1.0)) / _8123, 1.0 - clamp(_8255.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8532 = _8532;
                        _10762 = (_8210 + (((mp_copy_8466 + mp_copy_8488) + mp_copy_8510) + mp_copy_8532)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10784 = _5446 * _10762;
                }
                else
                {
                    _10784 = _5446;
                }
                _10783 = _10784;
            }
            else
            {
                _10783 = _5422;
            }
            _10785 = _10787;
            _10782 = _10783;
            _10771 = _5368;
        }
        hp_copy_10785 = _10785;
        highp vec3 _10800 = vec3(0.0);
        highp vec3 _10801 = vec3(0.0);
        do
        {
            float _8598 = max(dot(_10621, _10771), 0.0);
            highp float hp_copy_8598 = _8598;
            if (_8598 <= 0.0)
            {
                _10801 = vec3(0.0);
                _10800 = vec3(0.0);
                break;
            }
            float _8604 = max(_5309, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8604 = _8604;
            vec3 _8607 = _10771 + mp_copy_10680;
            float _8610 = dot(_8607, _8607);
            vec3 _10798 = vec3(0.0);
            vec3 _10799 = vec3(0.0);
            if (_8610 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8618 = _8607 * inversesqrt(_8610);
                float _10797 = 0.0;
                do
                {
                    float _8675 = dot(_10621, _8618);
                    if (_8675 <= 0.0)
                    {
                        _10797 = 0.0;
                        break;
                    }
                    float _8682 = _10785 * _10785;
                    vec3 _8685 = cross(_10621, _8618);
                    float _8688 = _8675 * _8682;
                    float _8697 = _8682 / (dot(_8685, _8685) + (_8688 * _8688));
                    _10797 = min((_8697 * _8697) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8735 = _5305 + ((vec3(1.0) - _5305) * pow(clamp(1.0 - max(dot(_8618, _10680), 0.0), 0.0, 1.0), 5.0));
                _10799 = (_8735 * min(_10797 * (0.5 / max(mix((2.0 * hp_copy_8598) * _8604, hp_copy_8598 + hp_copy_8604, hp_copy_10785 * hp_copy_10785), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10798 = _8735;
            }
            else
            {
                _10799 = vec3(0.0);
                _10798 = _5305;
            }
            _10801 = (_10799 * _10782) * _8598;
            _10800 = (((((vec3(1.0) - _10798) * (1.0 - _4401)) * _5236) * 0.3183098733425140380859375) * _10782) * _8598;
            break;
        } while(false);
        _11077 = _10726 + (_10800 + _10801);
    }
    bool _8959 = false;
    mat3 _5513 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5521 = _5513 * vec3(_10621.x, _10621.y, _10621.z);
    vec3 _5524 = _5513 * reflect(-mp_copy_10680, _10621);
    float _8778 = _5521.y;
    float _8779 = 0.48860299587249755859375 * _8778;
    float _8785 = _5521.z;
    float _8786 = 0.48860299587249755859375 * _8785;
    float _8792 = _5521.x;
    float _8793 = 0.48860299587249755859375 * _8792;
    float _8800 = 1.09254801273345947265625 * _8792;
    float _8803 = _8800 * _8778;
    float _8813 = (1.09254801273345947265625 * _8778) * _8785;
    float _8825 = 0.3153919875621795654296875 * (((3.0 * _8785) * _8785) - 1.0);
    float _8835 = _8800 * _8785;
    float _8851 = 0.546274006366729736328125 * ((_8792 * _8792) - (_8778 * _8778));
    vec3 _5527 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _8779)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _8786)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _8793)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _8803)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _8813)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _8825)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _8835)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _8851), vec3(0.0));
    vec3 _10683 = vec3(0.0);
    do
    {
        _8959 = radiance_layout_info.mip_layout > 0.5;
        if (_8959)
        {
            vec2 _9038 = vec2(atan(_5524.z, _5524.x), asin(clamp(_5524.y, -1.0, 1.0)));
            highp vec2 hp_copy_9038 = _9038;
            _10683 = textureLod(prefiltered_radiance, (hp_copy_9038 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10669, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9057 = vec2(atan(_5524.z, _5524.x), asin(clamp(_5524.y, -1.0, 1.0)));
        highp vec2 hp_copy_9057 = _9057;
        highp vec2 _9062 = (hp_copy_9057 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8969 = clamp(_9062.y, 0.00390625, 0.99609375);
        float _8973 = clamp(_10669, 0.0, 1.0) * 7.0;
        float _8975 = floor(_8973);
        highp float _8994 = _9062.x;
        _10683 = mix(textureLod(prefiltered_radiance, vec2(_8994, (_8975 + _8969) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8994, (min(_8975 + 1.0, 7.0) + _8969) * 0.125), 0.0).xyz, vec3(_8973 - _8975));
        break;
    } while(false);
    bool _5534 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _10688 = vec3(0.0);
    highp vec3 _10689 = vec3(0.0);
    if (_5534)
    {
        vec3 _10684 = vec3(0.0);
        do
        {
            if (_8959)
            {
                vec2 _9350 = vec2(atan(_5524.z, _5524.x), asin(clamp(_5524.y, -1.0, 1.0)));
                highp vec2 hp_copy_9350 = _9350;
                _10684 = textureLod(prefiltered_radiance_b, (hp_copy_9350 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10669, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9369 = vec2(atan(_5524.z, _5524.x), asin(clamp(_5524.y, -1.0, 1.0)));
            highp vec2 hp_copy_9369 = _9369;
            highp vec2 _9374 = (hp_copy_9369 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9281 = clamp(_9374.y, 0.00390625, 0.99609375);
            float _9285 = clamp(_10669, 0.0, 1.0) * 7.0;
            float _9287 = floor(_9285);
            highp float _9306 = _9374.x;
            _10684 = mix(textureLod(prefiltered_radiance_b, vec2(_9306, (_9287 + _9281) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9306, (min(_9287 + 1.0, 7.0) + _9281) * 0.125), 0.0).xyz, vec3(_9285 - _9287));
            break;
        } while(false);
        highp vec3 _5545 = vec3(frag_info.radiance_blend.x);
        _10689 = mix(_10683, _10684, _5545);
        _10688 = mix(_5527, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _8779)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _8786)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _8793)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _8803)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _8813)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _8825)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _8835)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _8851), vec3(0.0)), _5545);
    }
    else
    {
        _10689 = _10683;
        _10688 = _5527;
    }
    vec2 _5567 = clamp(vec2(_5313, _10669), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5569 = texture(brdf_lut, vec2(_5567.x * 0.3333333432674407958984375, _5567.y));
    float _5573 = _5569.x;
    float _5576 = _5569.y;
    vec3 _5578 = ((_5305 + ((max(vec3(1.0 - _10669), _5305) - _5305) * pow(clamp(1.0 - _5313, 0.0, 1.0), 5.0))) * _5573) + vec3(_5576);
    float _5584 = 1.0 - (_5573 + _5576);
    vec3 _5588 = vec3(1.0) - _5305;
    vec3 _5591 = _5305 + (_5588 * vec3(0.0476190485060214996337890625));
    vec3 _5602 = ((_5578 * _5584) * _5591) / (vec3(1.0) - (_5591 * _5584));
    float _5605 = 1.0 - _4401;
    float _10703 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _10703 = clamp((pow(_5309 + _10700, exp2(((-16.0) * _10669) - 1.0)) - 1.0) + _10700, 0.0, 1.0);
    }
    else
    {
        _10703 = _10700;
    }
    highp vec3 _10736 = vec3(0.0);
    if (_5261)
    {
        highp vec3 _10720 = vec3(0.0);
        highp vec3 _10721 = vec3(0.0);
        do
        {
            float _9463 = max(dot(_10621, _10714), 0.0);
            highp float hp_copy_9463 = _9463;
            if (_9463 <= 0.0)
            {
                _10721 = vec3(0.0);
                _10720 = vec3(0.0);
                break;
            }
            float _9469 = max(_5309, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9469 = _9469;
            vec3 _9472 = _10714 + mp_copy_10680;
            float _9475 = dot(_9472, _9472);
            vec3 _10718 = vec3(0.0);
            vec3 _10719 = vec3(0.0);
            if (_9475 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9483 = _9472 * inversesqrt(_9475);
                float _10717 = 0.0;
                do
                {
                    float _9540 = dot(_10621, _9483);
                    if (_9540 <= 0.0)
                    {
                        _10717 = 0.0;
                        break;
                    }
                    float _9547 = _10669 * _10669;
                    vec3 _9550 = cross(_10621, _9483);
                    float _9553 = _9540 * _9547;
                    float _9562 = _9547 / (dot(_9550, _9550) + (_9553 * _9553));
                    _10717 = min((_9562 * _9562) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9600 = _5305 + (_5588 * pow(clamp(1.0 - max(dot(_9483, _10680), 0.0), 0.0, 1.0), 5.0));
                _10719 = (_9600 * min(_10717 * (0.5 / max(mix((2.0 * hp_copy_9463) * _9469, hp_copy_9463 + hp_copy_9469, hp_copy_10669 * hp_copy_10669), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10718 = _9600;
            }
            else
            {
                _10719 = vec3(0.0);
                _10718 = _5305;
            }
            _10721 = (_10719 * frag_info.directional_light_color.xyz) * _9463;
            _10720 = (((((vec3(1.0) - _10718) * _5605) * _5236) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9463;
            break;
        } while(false);
        _10736 = _10726 + ((_10720 + _10721) * _5296);
    }
    else
    {
        _10736 = _10726;
    }
    bool _5696 = _FogInfo.params0.y > 0.5;
    bool _5702 = false;
    if (_5696)
    {
        _5702 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5702 = _5696;
    }
    highp vec3 _10741 = vec3(0.0);
    if (_5702)
    {
        vec3 mp_copy_10737 = vec3(0.0);
        highp vec3 _10737 = vec3(0.0);
        if (_7619)
        {
            _10737 = -view_info.camera_forward.xyz;
        }
        else
        {
            _10737 = normalize(v_viewvector);
        }
        mp_copy_10737 = _10737;
        vec3 _5707 = _5513 * (-mp_copy_10737);
        vec3 _10738 = vec3(0.0);
        do
        {
            if (_8959)
            {
                vec2 _9722 = vec2(atan(_5707.z, _5707.x), asin(clamp(_5707.y, -1.0, 1.0)));
                highp vec2 hp_copy_9722 = _9722;
                _10738 = textureLod(prefiltered_radiance, (hp_copy_9722 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9741 = vec2(atan(_5707.z, _5707.x), asin(clamp(_5707.y, -1.0, 1.0)));
            highp vec2 hp_copy_9741 = _9741;
            highp vec2 _9746 = (hp_copy_9741 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9653 = clamp(_9746.y, 0.00390625, 0.99609375);
            float _9659 = floor(0.0);
            highp float _9678 = _9746.x;
            _10738 = mix(textureLod(prefiltered_radiance, vec2(_9678, (_9659 + _9653) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9678, (min(_9659 + 1.0, 7.0) + _9653) * 0.125), 0.0).xyz, vec3(-_9659));
            break;
        } while(false);
        highp vec3 _10740 = vec3(0.0);
        if (_5534)
        {
            vec3 _10739 = vec3(0.0);
            do
            {
                if (_8959)
                {
                    vec2 _9851 = vec2(atan(_5707.z, _5707.x), asin(clamp(_5707.y, -1.0, 1.0)));
                    highp vec2 hp_copy_9851 = _9851;
                    _10739 = textureLod(prefiltered_radiance_b, (hp_copy_9851 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _9870 = vec2(atan(_5707.z, _5707.x), asin(clamp(_5707.y, -1.0, 1.0)));
                highp vec2 hp_copy_9870 = _9870;
                highp vec2 _9875 = (hp_copy_9870 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _9782 = clamp(_9875.y, 0.00390625, 0.99609375);
                float _9788 = floor(0.0);
                highp float _9807 = _9875.x;
                _10739 = mix(textureLod(prefiltered_radiance_b, vec2(_9807, (_9788 + _9782) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9807, (min(_9788 + 1.0, 7.0) + _9782) * 0.125), 0.0).xyz, vec3(-_9788));
                break;
            } while(false);
            _10740 = mix(_10738, _10739, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _10740 = _10738;
        }
        _10741 = _10740 * frag_info.environment_intensity;
    }
    else
    {
        _10741 = _FogInfo.color.xyz;
    }
    highp vec4 _5731 = vec4(min(((((((_5602 + ((_5236 * _5605) * ((vec3(1.0) - _5578) - _5602))) * (_10688 * frag_info.environment_intensity)) * vec3(_4435)) + (((_5578 * (_10689 * frag_info.environment_intensity)) * 1.0) * _10703)) * mix(1.0, _5296, frag_info.radiance_blend.y)) + (_10736 * mix(1.0, _10700, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _10644, vec3(65504.0)), 1.0) * _11136;
    highp vec4 _10756 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _10756 = _5731;
            break;
        }
        int _9919 = int(_FogInfo.params0.x + 0.5);
        if (_9919 == 0)
        {
            _10756 = _5731;
            break;
        }
        highp float _10743 = 0.0;
        if (_7619)
        {
            _10743 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _10743 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_10743 > _FogInfo.params1.w))
        {
            _10756 = _5731;
            break;
        }
        float _10747 = 0.0;
        if (_9919 == 1)
        {
            _10747 = clamp((_10743 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _10748 = 0.0;
            if (_9919 == 2)
            {
                highp float _10746 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _10744 = vec3(0.0);
                    if (_7619)
                    {
                        _10744 = v_position - (view_info.camera_forward.xyz * _10743);
                    }
                    else
                    {
                        _10744 = v_position + v_viewvector;
                    }
                    highp float _10000 = -_FogInfo.params2.y;
                    highp float _10007 = _FogInfo.params1.x * exp(_10000 * (_10744.y - _FogInfo.params2.x));
                    highp float _10024 = _FogInfo.params2.y * (v_position.y - _10744.y);
                    highp float _10745 = 0.0;
                    if (abs(_10024) > 0.00124999997206032276153564453125)
                    {
                        _10745 = (_10007 - (_FogInfo.params1.x * exp(_10000 * (v_position.y - _FogInfo.params2.x)))) / _10024;
                    }
                    else
                    {
                        _10745 = _10007;
                    }
                    _10746 = _10745 * max(_10743 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _10746 = _FogInfo.params1.x * max(_10743 - _FogInfo.params1.y, 0.0);
                }
                _10748 = 1.0 - exp(-_10746);
            }
            else
            {
                highp float _10062 = _FogInfo.params1.x * max(_10743 - _FogInfo.params1.y, 0.0);
                _10748 = 1.0 - exp((-_10062) * _10062);
            }
            _10747 = _10748;
        }
        highp float _10074 = min(_10747, _FogInfo.params0.z);
        if (_10074 <= 0.0)
        {
            _10756 = _5731;
            break;
        }
        highp vec3 _10087 = mix(_FogInfo.color.xyz, _10741, vec3(_FogInfo.params0.w));
        bool _10090 = _FogInfo.sun.w > 0.5;
        bool _10096 = false;
        if (_10090)
        {
            _10096 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _10096 = _10090;
        }
        vec3 _10752 = vec3(0.0);
        if (_10096)
        {
            vec3 mp_copy_10749 = vec3(0.0);
            highp vec3 _10749 = vec3(0.0);
            if (_7619)
            {
                _10749 = -view_info.camera_forward.xyz;
            }
            else
            {
                _10749 = normalize(v_viewvector);
            }
            mp_copy_10749 = _10749;
            highp float _10112 = pow(max(dot(-mp_copy_10749, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_10112 = _10112;
            _10752 = _10087 + ((_FogInfo.sun.xyz * mp_copy_10112) * _FogInfo.params2.z);
        }
        else
        {
            _10752 = _10087;
        }
        highp float _10125 = _5731.w;
        float mp_copy_10125 = _10125;
        _10756 = vec4(mix(_5731.xyz, _10752 * mp_copy_10125, vec3(_10074)), _10125);
        break;
    } while(false);
    vec4 _10758 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10758 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10758 = _10756;
        break;
    } while(false);
    frag_color = _10758;
    float _10759 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10759 = 1.0;
    }
    else
    {
        _10759 = abs(frag_info.fade);
    }
    frag_color *= _10759;
}

