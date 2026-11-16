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
uniform highp sampler2D punctual_lights;

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
    highp float _3636 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_3636 = _3636;
    vec3 _3640 = normalize(v_normal) * mp_copy_3636;
    vec4 _3682 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _3685 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _8430 = vec2(0.0);
    if (_3685)
    {
        highp vec2 _8429 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _8429 = v_texture_coords_1;
        }
        else
        {
            _8429 = v_texture_coords;
        }
        highp vec2 _3888 = _8429 * texture_transforms.base_color_transform.zw;
        highp float _3894 = _3888.x;
        highp float _3899 = _3888.y;
        _8430 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _3894) + (texture_transforms.base_color_rotation.y * _3899), ((-texture_transforms.base_color_rotation.y) * _3894) + (texture_transforms.base_color_rotation.x * _3899));
    }
    else
    {
        _8430 = v_texture_coords;
    }
    vec4 _3699 = texture(base_color_texture, _8430);
    vec3 _3701 = _3699.xyz;
    float _8818 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3699.w * _3682.w) * frag_info.color.w);
    vec3 _8445 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _8433 = vec2(0.0);
        if (_3685)
        {
            highp vec2 _8432 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _8432 = v_texture_coords_1;
            }
            else
            {
                _8432 = v_texture_coords;
            }
            highp vec2 _3983 = _8432 * texture_transforms.normal_transform.zw;
            highp float _3989 = _3983.x;
            highp float _3994 = _3983.y;
            _8433 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _3989) + (texture_transforms.normal_rotation.y * _3994), ((-texture_transforms.normal_rotation.y) * _3989) + (texture_transforms.normal_rotation.x * _3994));
        }
        else
        {
            _8433 = v_texture_coords;
        }
        vec3 _4039 = ((texture(normal_texture, _8433).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4043 = _4039.xy * vec2(frag_info.normal_scale);
        vec3 _8214 = _4039;
        _8214.x = _4043.x;
        _8214.y = _4043.y;
        highp vec3 _4049 = -v_viewvector;
        highp vec3 _4139 = dFdx(_4049);
        highp vec3 _4141 = dFdy(_4049);
        highp vec2 _4143 = dFdx(_8433);
        highp vec2 _4145 = dFdy(_8433);
        bvec2 _8820 = bvec2(length(_4143) == 0.0);
        highp vec2 _8821 = vec2(_8820.x ? vec2(1.0, 0.0).x : _4143.x, _8820.y ? vec2(1.0, 0.0).y : _4143.y);
        bvec2 _8822 = bvec2(length(_4145) == 0.0);
        highp vec2 _8823 = vec2(_8822.x ? vec2(0.0, 1.0).x : _4145.x, _8822.y ? vec2(0.0, 1.0).y : _4145.y);
        highp vec3 _4158 = cross(_4141, _3640);
        highp vec3 _4161 = cross(_3640, _4139);
        highp float _4186 = (dot(cross(_4139, _4141), _3640) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4189 = ((_4158 * _8821.x) + (_4161 * _8823.x)) * _4186;
        highp float _8440 = 0.0;
        if (gl_FrontFacing)
        {
            _8440 = -_4186;
        }
        else
        {
            _8440 = _4186;
        }
        highp vec3 _4199 = ((_4158 * _8821.y) + (_4161 * _8823.y)) * _8440;
        highp float _4208 = inversesqrt(max(max(dot(_4189, _4189), dot(_4199, _4199)), 9.9999996826552253889678874634872e-21));
        vec3 _4080 = v_tangent.xyz - (_3640 * dot(_3640, v_tangent.xyz));
        highp float _4083 = dot(_4080, _4080);
        bool _4085 = _4083 > 1.0000000133514319600180897396058e-10;
        bool _4092 = false;
        if (_4085)
        {
            _4092 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4092 = _4085;
        }
        mat3 _8443 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4092)
        {
            highp vec3 _4097 = _4080 * inversesqrt(_4083);
            _8443 = mat3(_4097, normalize(cross(_3640, _4097)) * sign(v_tangent.w), _3640);
        }
        else
        {
            _8443 = mat3(_4189 * _4208, _4199 * _4208, _3640);
        }
        _8445 = normalize(_8443 * _8214);
    }
    else
    {
        _8445 = _3640;
    }
    highp vec2 _8447 = vec2(0.0);
    if (_3685)
    {
        highp vec2 _8446 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _8446 = v_texture_coords_1;
        }
        else
        {
            _8446 = v_texture_coords;
        }
        highp vec2 _4276 = _8446 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4282 = _4276.x;
        highp float _4287 = _4276.y;
        _8447 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4282) + (texture_transforms.metallic_roughness_rotation.y * _4287), ((-texture_transforms.metallic_roughness_rotation.y) * _4282) + (texture_transforms.metallic_roughness_rotation.x * _4287));
    }
    else
    {
        _8447 = v_texture_coords;
    }
    vec4 _3768 = texture(metallic_roughness_texture, _8447);
    float _3774 = clamp(_3768.z * frag_info.metallic_factor, 0.0, 1.0);
    float _3781 = clamp(_3768.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _8449 = vec2(0.0);
    if (_3685)
    {
        highp vec2 _8448 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _8448 = v_texture_coords_1;
        }
        else
        {
            _8448 = v_texture_coords;
        }
        highp vec2 _4347 = _8448 * texture_transforms.occlusion_transform.zw;
        highp float _4353 = _4347.x;
        highp float _4358 = _4347.y;
        _8449 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4353) + (texture_transforms.occlusion_rotation.y * _4358), ((-texture_transforms.occlusion_rotation.y) * _4353) + (texture_transforms.occlusion_rotation.x * _4358));
    }
    else
    {
        _8449 = v_texture_coords;
    }
    float _8450 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _8450 = texture(occlusion_texture, _8449).x;
    }
    else
    {
        _8450 = 1.0;
    }
    float _3808 = 1.0 - ((1.0 - _8450) * frag_info.occlusion_strength);
    highp vec2 _8452 = vec2(0.0);
    if (_3685)
    {
        highp vec2 _8451 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _8451 = v_texture_coords_1;
        }
        else
        {
            _8451 = v_texture_coords;
        }
        highp vec2 _4418 = _8451 * texture_transforms.emissive_transform.zw;
        highp float _4424 = _4418.x;
        highp float _4429 = _4418.y;
        _8452 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4424) + (texture_transforms.emissive_rotation.y * _4429), ((-texture_transforms.emissive_rotation.y) * _4424) + (texture_transforms.emissive_rotation.x * _4429));
    }
    else
    {
        _8452 = v_texture_coords;
    }
    vec3 _3827 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _8468 = vec3(0.0);
    if (dot(abs(_3827), vec3(1.0)) > 0.0)
    {
        vec3 _3836 = texture(emissive_texture, _8452).xyz;
        _8468 = mix(_3836 * vec3(0.077399380505084991455078125), pow((_3836 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3836)) * _3827;
    }
    else
    {
        _8468 = vec3(0.0);
    }
    highp float hp_copy_8493 = 0.0;
    vec3 _4555 = vec4((mix(_3701 * vec3(0.077399380505084991455078125), pow((_3701 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3701)) * _3682.xyz) * frag_info.color.xyz, _8818).xyz;
    vec3 _4867 = dFdx(_8445);
    vec3 _4869 = dFdy(_8445);
    float _8493 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _8493 = sqrt(clamp((_3781 * _3781) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_4867, _4867), dot(_4869, _4869))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _8493 = _3781;
    }
    hp_copy_8493 = _8493;
    float _8518 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _8518 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _8518 = _3808;
    }
    bool _4580 = frag_info.has_directional_light > 0.5;
    float _8494 = 0.0;
    vec3 _8530 = vec3(0.0);
    if (_4580)
    {
        highp vec3 _4586 = -normalize(frag_info.directional_light_direction.xyz);
        _8530 = _4586;
        _8494 = dot(_3640, _4586);
    }
    else
    {
        _8530 = vec3(0.0);
        _8494 = 0.0;
    }
    float _4593 = clamp(_8494 * 6.666666507720947265625, 0.0, 1.0);
    bool _4602 = false;
    if (_4580)
    {
        _4602 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _4602 = _4580;
    }
    float _8503 = 0.0;
    if (_4602 && (_4593 > 0.0))
    {
        int _4948 = int(frag_info.shadow_cascade_count);
        float _5143 = max(dot(_3640, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5146 = _5143 * _5143;
        highp vec3 _5166 = v_position + (_3640 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5146, 0.0)) / _5146, 8.0))));
        highp float _4954 = frag_info.directional_light_color.w * 0.5;
        float _4956 = frag_info.dielectric_f0.w;
        highp float hp_copy_4956 = _4956;
        float _8495 = 0.0;
        if (_4956 > 0.0)
        {
            _8495 = smoothstep(_4956 - max(frag_info.shadow_fade, hp_copy_4956 * 0.100000001490116119384765625), _4956, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _8495 = 0.0;
        }
        float _8497 = 0.0;
        float _8499 = 0.0;
        if (_8495 < 1.0)
        {
            float _8498 = 0.0;
            float _8500 = 0.0;
            _8500 = 0.0;
            _8498 = 0.0;
            float _8702 = 0.0;
            float _8705 = 0.0;
            for (int _8496 = 0; _8496 < _4948; _8500 = _8705, _8498 = _8702, _8496++)
            {
                if (_8500 < 1.0)
                {
                    highp vec4 _4988 = vec4(_5166, 1.0);
                    highp vec4 _8574 = vec4(0.0);
                    highp float _8577 = 0.0;
                    if (_8496 == 0)
                    {
                        _8577 = frag_info.cascade_box_sizes.x;
                        _8574 = frag_info.light_space_matrix[0] * _4988;
                    }
                    else
                    {
                        highp vec4 _8575 = vec4(0.0);
                        highp float _8578 = 0.0;
                        if (_8496 == 1)
                        {
                            _8578 = frag_info.cascade_box_sizes.y;
                            _8575 = frag_info.light_space_matrix[1] * _4988;
                        }
                        else
                        {
                            highp vec4 _8576 = vec4(0.0);
                            highp float _8579 = 0.0;
                            if (_8496 == 2)
                            {
                                _8579 = frag_info.cascade_box_sizes.z;
                                _8576 = frag_info.light_space_matrix[2] * _4988;
                            }
                            else
                            {
                                _8579 = frag_info.cascade_box_sizes.w;
                                _8576 = frag_info.light_space_matrix[3] * _4988;
                            }
                            _8578 = _8579;
                            _8575 = _8576;
                        }
                        _8577 = _8578;
                        _8574 = _8575;
                    }
                    highp vec3 _5033 = _8574.xyz / vec3(_8574.w);
                    highp vec2 _5036 = _5033.xy * 0.5;
                    highp vec2 _5038 = _5036 + vec2(0.5);
                    highp float _5045 = max(frag_info.shadow_softness / _8577, frag_info.shadow_texel_size);
                    highp float _5047 = _5038.x;
                    bool _5049 = _5047 < _5045;
                    bool _5058 = false;
                    if (!_5049)
                    {
                        _5058 = _5047 > (1.0 - _5045);
                    }
                    else
                    {
                        _5058 = _5049;
                    }
                    bool _5066 = false;
                    if (!_5058)
                    {
                        _5066 = _5038.y < _5045;
                    }
                    else
                    {
                        _5066 = _5058;
                    }
                    bool _5075 = false;
                    if (!_5066)
                    {
                        _5075 = _5038.y > (1.0 - _5045);
                    }
                    else
                    {
                        _5075 = _5066;
                    }
                    bool _5082 = false;
                    if (!_5075)
                    {
                        _5082 = _5033.z < 0.0;
                    }
                    else
                    {
                        _5082 = _5075;
                    }
                    bool _5089 = false;
                    if (!_5082)
                    {
                        _5089 = _5033.z > 1.0;
                    }
                    else
                    {
                        _5089 = _5082;
                    }
                    float _8703 = 0.0;
                    float _8706 = 0.0;
                    if (!_5089)
                    {
                        highp vec2 _5182 = vec2(_5045);
                        highp vec2 _5187 = vec2(_5045 + max(_4954, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5195 = vec2(0.5) - _5036;
                        highp vec2 _5197 = smoothstep(_5182, _5187, _5038) * smoothstep(_5182, _5187, _5195);
                        float _8580 = 0.0;
                        if (_4954 > 0.0)
                        {
                            _8580 = _5197.x * _5197.y;
                        }
                        else
                        {
                            _8580 = 1.0;
                        }
                        float _5098 = min(_8580, 1.0 - _8500);
                        float _8704 = 0.0;
                        float _8707 = 0.0;
                        if (_5098 > 0.0)
                        {
                            highp float _5336 = _5033.z - (frag_info.shadow_bias / (7.0 * _8577));
                            highp float _5342 = 1.0 / (float(_4948) + frag_info.spot_shadow_params.x);
                            highp float _5344 = frag_info.directional_light_direction.w;
                            float mp_copy_5344 = _5344;
                            float _5350 = step(0.5, mp_copy_5344) * (1.0 - step(1.5, mp_copy_5344));
                            float _8610 = 0.0;
                            float _8614 = 0.0;
                            if (_5350 < 0.5)
                            {
                                highp float _5361 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_5361 = _5361;
                                _8614 = sin(mp_copy_5361);
                                _8610 = cos(mp_copy_5361);
                            }
                            else
                            {
                                _8614 = 0.0;
                                _8610 = 1.0;
                            }
                            highp float _8617 = 0.0;
                            if ((_5344 > 1.5) && (_5344 < 2.5))
                            {
                                highp float _5385 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _5390 = max(_5385 * _5336, frag_info.shadow_texel_size);
                                float _8606 = 0.0;
                                highp float _8607 = 0.0;
                                _8607 = 0.0;
                                _8606 = 0.0;
                                highp float _5412 = 0.0;
                                float _5415 = 0.0;
                                for (int _8605 = 0; _8605 < 9; _8607 = _5412, _8606 = _5415, _8605++)
                                {
                                    vec2 _8696 = vec2(0.0);
                                    do
                                    {
                                        if (_8605 == 0)
                                        {
                                            _8696 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_8605 == 1)
                                        {
                                            _8696 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_8605 == 2)
                                        {
                                            _8696 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_8605 == 3)
                                        {
                                            _8696 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_8605 == 4)
                                        {
                                            _8696 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_8605 == 5)
                                        {
                                            _8696 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_8605 == 6)
                                        {
                                            _8696 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_8605 == 7)
                                        {
                                            _8696 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_8605 == 8)
                                        {
                                            _8696 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_8605 == 9)
                                        {
                                            _8696 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_8605 == 10)
                                        {
                                            _8696 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_8605 == 11)
                                        {
                                            _8696 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_8605 == 12)
                                        {
                                            _8696 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_8605 == 13)
                                        {
                                            _8696 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_8605 == 14)
                                        {
                                            _8696 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_8605 == 15)
                                        {
                                            _8696 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _8696 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _5719 = clamp(_5038 + (vec2((_8696.x * _8610) - (_8696.y * _8614), (_8696.x * _8614) + (_8696.y * _8610)) * _5390), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _5728 = _5719.y;
                                    highp vec2 _5729 = vec2((float(_8496) + _5719.x) * _5342, _5728);
                                    _5729.y = 1.0 - _5728;
                                    highp vec4 _5736 = textureLod(shadow_map, _5729, 0.0);
                                    highp float _5737 = _5736.x;
                                    highp float _5407 = step(_5737, _5336);
                                    float mp_copy_5407 = _5407;
                                    _5412 = _8607 + (_5737 * _5407);
                                    _5415 = _8606 + mp_copy_5407;
                                }
                                highp float _8608 = 0.0;
                                if (_8606 > 0.0)
                                {
                                    _8608 = _8607 / _8606;
                                }
                                else
                                {
                                    _8608 = _5336;
                                }
                                _8617 = clamp(_5385 * max(_5336 - _8608, 0.0), frag_info.shadow_texel_size, _5045);
                            }
                            else
                            {
                                _8617 = _5045;
                            }
                            bool _5446 = _5344 > 2.5;
                            bool _8618 = false;
                            float _8643 = 0.0;
                            if ((_5344 < 1.5) || _5446)
                            {
                                highp vec2 _5770 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _5774 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _5775 = clamp(_5038, _5770, _5774);
                                highp float _5777 = float(_8496);
                                highp float _5784 = _5775.y;
                                highp vec2 _5785 = vec2((_5777 + _5775.x) * _5342, _5784);
                                _5785.y = 1.0 - _5784;
                                highp float _5797 = float(_5336 <= textureLod(shadow_map, _5785, 0.0).x);
                                float mp_copy_5797 = _5797;
                                float _5807 = (-1.0) * _8610;
                                float _5811 = (-1.0) * _8614;
                                highp vec2 _5835 = clamp(_5038 + (vec2(_5807 - _5811, _5811 + _5807) * _8617), _5770, _5774);
                                highp float _5844 = _5835.y;
                                highp vec2 _5845 = vec2((_5777 + _5835.x) * _5342, _5844);
                                _5845.y = 1.0 - _5844;
                                highp float _5857 = float(_5336 <= textureLod(shadow_map, _5845, 0.0).x);
                                float mp_copy_5857 = _5857;
                                highp vec2 _5895 = clamp(_5038 + (vec2(_8610 - _5811, _8614 + _5807) * _8617), _5770, _5774);
                                highp float _5904 = _5895.y;
                                highp vec2 _5905 = vec2((_5777 + _5895.x) * _5342, _5904);
                                _5905.y = 1.0 - _5904;
                                highp float _5917 = float(_5336 <= textureLod(shadow_map, _5905, 0.0).x);
                                float mp_copy_5917 = _5917;
                                highp vec2 _5955 = clamp(_5038 + (vec2(_5807 - _8614, _5811 + _8610) * _8617), _5770, _5774);
                                highp float _5964 = _5955.y;
                                highp vec2 _5965 = vec2((_5777 + _5955.x) * _5342, _5964);
                                _5965.y = 1.0 - _5964;
                                highp float _5977 = float(_5336 <= textureLod(shadow_map, _5965, 0.0).x);
                                float mp_copy_5977 = _5977;
                                highp vec2 _6015 = clamp(_5038 + (vec2(_8610 - _8614, _8614 + _8610) * _8617), _5770, _5774);
                                highp float _6024 = _6015.y;
                                highp vec2 _6025 = vec2((_5777 + _6015.x) * _5342, _6024);
                                _6025.y = 1.0 - _6024;
                                highp float _6037 = float(_5336 <= textureLod(shadow_map, _6025, 0.0).x);
                                float mp_copy_6037 = _6037;
                                float _5492 = (((mp_copy_5797 + mp_copy_5857) + mp_copy_5917) + mp_copy_5977) + mp_copy_6037;
                                _8643 = _5492 * 0.20000000298023223876953125;
                                _8618 = (_5492 < 0.5) || (_5492 > 4.5);
                            }
                            else
                            {
                                _8643 = 0.0;
                                _8618 = false;
                            }
                            float _8641 = 0.0;
                            if (_8618)
                            {
                                _8641 = _8643;
                            }
                            else
                            {
                                float _8642 = 0.0;
                                if (_5446)
                                {
                                    highp vec2 _6256 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6260 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6261 = clamp(_5038 + (vec2(-0.707099974155426025390625) * _8617), _6256, _6260);
                                    highp vec2 _6272 = (vec2(_6261.x, 1.0 - _6261.y) / _6256) - vec2(0.5);
                                    highp vec2 _6274 = floor(_6272);
                                    highp vec2 _6277 = _6272 - _6274;
                                    highp vec2 _6282 = (_6274 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6284 = float(_8496);
                                    highp vec2 _6292 = vec2((_6284 + _6282.x) * _5342, _6282.y);
                                    highp float _6296 = frag_info.shadow_texel_size * _5342;
                                    highp vec2 _6299 = vec2(_6296, frag_info.shadow_texel_size);
                                    highp vec2 _6308 = vec2(_6296, 0.0);
                                    highp vec2 _6316 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _6345 = _6277.x;
                                    highp float _6354 = mix(mix(float(_5336 <= textureLod(shadow_map, _6292, 0.0).x), float(_5336 <= textureLod(shadow_map, _6292 + _6308, 0.0).x), _6345), mix(float(_5336 <= textureLod(shadow_map, _6292 + _6316, 0.0).x), float(_5336 <= textureLod(shadow_map, _6292 + _6299, 0.0).x), _6345), _6277.y);
                                    float mp_copy_6354 = _6354;
                                    highp vec2 _6388 = clamp(_5038 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _8617), _6256, _6260);
                                    highp vec2 _6399 = (vec2(_6388.x, 1.0 - _6388.y) / _6256) - vec2(0.5);
                                    highp vec2 _6401 = floor(_6399);
                                    highp vec2 _6404 = _6399 - _6401;
                                    highp vec2 _6409 = (_6401 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6419 = vec2((_6284 + _6409.x) * _5342, _6409.y);
                                    highp float _6472 = _6404.x;
                                    highp float _6481 = mix(mix(float(_5336 <= textureLod(shadow_map, _6419, 0.0).x), float(_5336 <= textureLod(shadow_map, _6419 + _6308, 0.0).x), _6472), mix(float(_5336 <= textureLod(shadow_map, _6419 + _6316, 0.0).x), float(_5336 <= textureLod(shadow_map, _6419 + _6299, 0.0).x), _6472), _6404.y);
                                    float mp_copy_6481 = _6481;
                                    highp vec2 _6515 = clamp(_5038 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _8617), _6256, _6260);
                                    highp vec2 _6526 = (vec2(_6515.x, 1.0 - _6515.y) / _6256) - vec2(0.5);
                                    highp vec2 _6528 = floor(_6526);
                                    highp vec2 _6531 = _6526 - _6528;
                                    highp vec2 _6536 = (_6528 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6546 = vec2((_6284 + _6536.x) * _5342, _6536.y);
                                    highp float _6599 = _6531.x;
                                    highp float _6608 = mix(mix(float(_5336 <= textureLod(shadow_map, _6546, 0.0).x), float(_5336 <= textureLod(shadow_map, _6546 + _6308, 0.0).x), _6599), mix(float(_5336 <= textureLod(shadow_map, _6546 + _6316, 0.0).x), float(_5336 <= textureLod(shadow_map, _6546 + _6299, 0.0).x), _6599), _6531.y);
                                    float mp_copy_6608 = _6608;
                                    highp vec2 _6642 = clamp(_5038 + (vec2(0.707099974155426025390625) * _8617), _6256, _6260);
                                    highp vec2 _6653 = (vec2(_6642.x, 1.0 - _6642.y) / _6256) - vec2(0.5);
                                    highp vec2 _6655 = floor(_6653);
                                    highp vec2 _6658 = _6653 - _6655;
                                    highp vec2 _6663 = (_6655 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6673 = vec2((_6284 + _6663.x) * _5342, _6663.y);
                                    highp float _6726 = _6658.x;
                                    highp float _6735 = mix(mix(float(_5336 <= textureLod(shadow_map, _6673, 0.0).x), float(_5336 <= textureLod(shadow_map, _6673 + _6308, 0.0).x), _6726), mix(float(_5336 <= textureLod(shadow_map, _6673 + _6316, 0.0).x), float(_5336 <= textureLod(shadow_map, _6673 + _6299, 0.0).x), _6726), _6658.y);
                                    float mp_copy_6735 = _6735;
                                    _8642 = (((mp_copy_6354 + mp_copy_6481) + mp_copy_6608) + mp_copy_6735) * 0.25;
                                }
                                else
                                {
                                    int _5508 = (_5350 > 0.5) ? 17 : 16;
                                    float _8637 = 0.0;
                                    _8637 = 0.0;
                                    float _5536 = 0.0;
                                    for (int _8619 = 0; _8619 < 17; _8637 = _5536, _8619++)
                                    {
                                        if (_8619 >= _5508)
                                        {
                                            break;
                                        }
                                        vec2 _8620 = vec2(0.0);
                                        do
                                        {
                                            if (_8619 == 0)
                                            {
                                                _8620 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_8619 == 1)
                                            {
                                                _8620 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_8619 == 2)
                                            {
                                                _8620 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_8619 == 3)
                                            {
                                                _8620 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_8619 == 4)
                                            {
                                                _8620 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_8619 == 5)
                                            {
                                                _8620 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_8619 == 6)
                                            {
                                                _8620 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_8619 == 7)
                                            {
                                                _8620 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_8619 == 8)
                                            {
                                                _8620 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_8619 == 9)
                                            {
                                                _8620 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_8619 == 10)
                                            {
                                                _8620 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_8619 == 11)
                                            {
                                                _8620 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_8619 == 12)
                                            {
                                                _8620 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_8619 == 13)
                                            {
                                                _8620 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_8619 == 14)
                                            {
                                                _8620 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_8619 == 15)
                                            {
                                                _8620 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _8620 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _8622 = vec2(0.0);
                                        do
                                        {
                                            if (_8619 < 3)
                                            {
                                                _8622 = vec2(float(_8619) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_8619 < 6)
                                            {
                                                _8622 = vec2((float(_8619 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_8619 < 11)
                                            {
                                                _8622 = vec2((float(_8619 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_8619 < 14)
                                            {
                                                _8622 = vec2((float(_8619 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _8622 = vec2(float(_8619 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _5525 = mix(_8620, _8622, vec2(_5350));
                                        float _6176 = _5525.x;
                                        float _6180 = _5525.y;
                                        highp vec2 _6206 = clamp(_5038 + (vec2((_6176 * _8610) - (_6180 * _8614), (_6176 * _8614) + (_6180 * _8610)) * _8617), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _6215 = _6206.y;
                                        highp vec2 _6216 = vec2((float(_8496) + _6206.x) * _5342, _6215);
                                        _6216.y = 1.0 - _6215;
                                        highp float _6228 = float(_5336 <= textureLod(shadow_map, _6216, 0.0).x);
                                        float mp_copy_6228 = _6228;
                                        _5536 = _8637 + mp_copy_6228;
                                    }
                                    _8642 = _8637 / float(_5508);
                                }
                                _8641 = _8642;
                            }
                            bool _5581 = _8496 == (_4948 - 1);
                            bool _5587 = false;
                            if (_5581)
                            {
                                _5587 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _5587 = _5581;
                            }
                            float _8644 = 0.0;
                            if (_5587)
                            {
                                highp vec2 _5594 = vec2(frag_info.shadow_fade / _8577);
                                highp vec2 _5602 = smoothstep(vec2(0.0), _5594, _5038) * smoothstep(vec2(0.0), _5594, _5195);
                                _8644 = mix(1.0, _8641, _5602.x * _5602.y);
                            }
                            else
                            {
                                _8644 = _8641;
                            }
                            _8707 = _8500 + _5098;
                            _8704 = _8498 + (_5098 * _8644);
                        }
                        else
                        {
                            _8707 = _8500;
                            _8704 = _8498;
                        }
                        _8706 = _8707;
                        _8703 = _8704;
                    }
                    else
                    {
                        _8706 = _8500;
                        _8703 = _8498;
                    }
                    _8705 = _8706;
                    _8702 = _8703;
                }
                else
                {
                    _8705 = _8500;
                    _8702 = _8498;
                }
            }
            _8499 = _8500;
            _8497 = _8498;
        }
        else
        {
            _8499 = 0.0;
            _8497 = 0.0;
        }
        _8503 = mix(_8497 + (1.0 - _8499), 1.0, _8495);
    }
    else
    {
        _8503 = 1.0;
    }
    vec3 mp_copy_8504 = vec3(0.0);
    float _4615 = _4593 * _8503;
    bool _6743 = view_info.camera_forward.w > 0.5;
    highp vec3 _8504 = vec3(0.0);
    if (_6743)
    {
        _8504 = -view_info.camera_forward.xyz;
    }
    else
    {
        _8504 = normalize(v_viewvector);
    }
    bool _7180 = false;
    highp vec3 hp_copy_8505 = vec3(0.0);
    mp_copy_8504 = _8504;
    vec3 _4624 = mix(frag_info.dielectric_f0.xyz, _4555, vec3(_3774));
    float _4628 = max(dot(_8445, _8504), 0.0);
    float _4632 = max(dot(_3640, _8504), 0.0);
    mat3 _4658 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _4666 = _4658 * vec3(_8445.x, _8445.y, _8445.z);
    vec3 _4669 = _4658 * reflect(-mp_copy_8504, _8445);
    float _6999 = _4666.y;
    float _7006 = _4666.z;
    float _7013 = _4666.x;
    float _7021 = 1.09254801273345947265625 * _7013;
    vec3 _4672 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _6999))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _7006))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _7013))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_7021 * _6999))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _6999) * _7006))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _7006) * _7006) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_7021 * _7006))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_7013 * _7013) - (_6999 * _6999)))), vec3(0.0));
    highp vec3 hp_copy_4672 = _4672;
    vec3 _8505 = vec3(0.0);
    do
    {
        _7180 = radiance_layout_info.mip_layout > 0.5;
        if (_7180)
        {
            vec2 _7259 = vec2(atan(_4669.z, _4669.x), asin(clamp(_4669.y, -1.0, 1.0)));
            highp vec2 hp_copy_7259 = _7259;
            _8505 = textureLod(prefiltered_radiance, (hp_copy_7259 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_8493, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _7278 = vec2(atan(_4669.z, _4669.x), asin(clamp(_4669.y, -1.0, 1.0)));
        highp vec2 hp_copy_7278 = _7278;
        highp vec2 _7283 = (hp_copy_7278 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _7190 = clamp(_7283.y, 0.00390625, 0.99609375);
        float _7194 = clamp(_8493, 0.0, 1.0) * 7.0;
        float _7196 = floor(_7194);
        highp float _7215 = _7283.x;
        _8505 = mix(textureLod(prefiltered_radiance, vec2(_7215, (_7196 + _7190) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_7215, (min(_7196 + 1.0, 7.0) + _7190) * 0.125), 0.0).xyz, vec3(_7194 - _7196));
        break;
    } while(false);
    hp_copy_8505 = _8505;
    highp vec3 _8511 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_8506 = vec3(0.0);
        vec3 _8506 = vec3(0.0);
        do
        {
            if (_7180)
            {
                vec2 _7388 = vec2(atan(_4669.z, _4669.x), asin(clamp(_4669.y, -1.0, 1.0)));
                highp vec2 hp_copy_7388 = _7388;
                _8506 = textureLod(prefiltered_radiance_b, (hp_copy_7388 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_8493, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _7407 = vec2(atan(_4669.z, _4669.x), asin(clamp(_4669.y, -1.0, 1.0)));
            highp vec2 hp_copy_7407 = _7407;
            highp vec2 _7412 = (hp_copy_7407 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _7319 = clamp(_7412.y, 0.00390625, 0.99609375);
            float _7323 = clamp(_8493, 0.0, 1.0) * 7.0;
            float _7325 = floor(_7323);
            highp float _7344 = _7412.x;
            _8506 = mix(textureLod(prefiltered_radiance_b, vec2(_7344, (_7325 + _7319) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_7344, (min(_7325 + 1.0, 7.0) + _7319) * 0.125), 0.0).xyz, vec3(_7323 - _7325));
            break;
        } while(false);
        hp_copy_8506 = _8506;
        _8511 = hp_copy_8505 + hp_copy_8506;
    }
    else
    {
        _8511 = _8505;
    }
    float _4687 = frag_info.environment_intensity;
    highp float hp_copy_4687 = _4687;
    vec2 _4700 = clamp(vec2(_4632, _8493), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _4702 = texture(brdf_lut, vec2(_4700.x * 0.3333333432674407958984375, _4700.y));
    float _4706 = _4702.x;
    float _4709 = _4702.y;
    vec3 _4711 = ((_4624 + ((max(vec3(1.0 - _8493), _4624) - _4624) * pow(clamp(1.0 - _4632, 0.0, 1.0), 5.0))) * _4706) + vec3(_4709);
    float _4717 = 1.0 - (_4706 + _4709);
    vec3 _4721 = vec3(1.0) - _4624;
    vec3 _4724 = _4624 + (_4721 * vec3(0.0476190485060214996337890625));
    vec3 _4735 = ((_4711 * _4717) * _4724) / (vec3(1.0) - (_4724 * _4717));
    float _4738 = 1.0 - _3774;
    float _8523 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _8523 = clamp((pow(_4628 + _8518, exp2(((-16.0) * _8493) - 1.0)) - 1.0) + _8518, 0.0, 1.0);
    }
    else
    {
        _8523 = _8518;
    }
    highp vec3 _8552 = vec3(0.0);
    if (_4580)
    {
        highp vec3 _8538 = vec3(0.0);
        highp vec3 _8539 = vec3(0.0);
        do
        {
            float _7501 = max(dot(_8445, _8530), 0.0);
            highp float hp_copy_7501 = _7501;
            if (_7501 <= 0.0)
            {
                _8539 = vec3(0.0);
                _8538 = vec3(0.0);
                break;
            }
            float _7507 = max(_4628, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_7507 = _7507;
            vec3 _7510 = _8530 + mp_copy_8504;
            float _7513 = dot(_7510, _7510);
            vec3 _8536 = vec3(0.0);
            vec3 _8537 = vec3(0.0);
            if (_7513 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _7521 = _7510 * inversesqrt(_7513);
                float _8535 = 0.0;
                do
                {
                    float _7578 = dot(_8445, _7521);
                    if (_7578 <= 0.0)
                    {
                        _8535 = 0.0;
                        break;
                    }
                    float _7585 = _8493 * _8493;
                    vec3 _7588 = cross(_8445, _7521);
                    float _7591 = _7578 * _7585;
                    float _7600 = _7585 / (dot(_7588, _7588) + (_7591 * _7591));
                    _8535 = min((_7600 * _7600) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _7638 = _4624 + (_4721 * pow(clamp(1.0 - max(dot(_7521, _8504), 0.0), 0.0, 1.0), 5.0));
                _8537 = (_7638 * min(_8535 * (0.5 / max(mix((2.0 * hp_copy_7501) * _7507, hp_copy_7501 + hp_copy_7507, hp_copy_8493 * hp_copy_8493), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _8536 = _7638;
            }
            else
            {
                _8537 = vec3(0.0);
                _8536 = _4624;
            }
            _8539 = (_8537 * frag_info.directional_light_color.xyz) * _7501;
            _8538 = (((((vec3(1.0) - _8536) * _4738) * _4555) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _7501;
            break;
        } while(false);
        _8552 = (_8538 + _8539) * _4615;
    }
    else
    {
        _8552 = vec3(0.0);
    }
    bool _4829 = _FogInfo.params0.y > 0.5;
    bool _4835 = false;
    if (_4829)
    {
        _4835 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _4835 = _4829;
    }
    highp vec3 _8555 = vec3(0.0);
    if (_4835)
    {
        vec3 mp_copy_8553 = vec3(0.0);
        highp vec3 _8553 = vec3(0.0);
        if (_6743)
        {
            _8553 = -view_info.camera_forward.xyz;
        }
        else
        {
            _8553 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_8554 = vec3(0.0);
        mp_copy_8553 = _8553;
        vec3 _4840 = _4658 * (-mp_copy_8553);
        vec3 _8554 = vec3(0.0);
        do
        {
            if (_7180)
            {
                vec2 _7760 = vec2(atan(_4840.z, _4840.x), asin(clamp(_4840.y, -1.0, 1.0)));
                highp vec2 hp_copy_7760 = _7760;
                _8554 = textureLod(prefiltered_radiance, (hp_copy_7760 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _7779 = vec2(atan(_4840.z, _4840.x), asin(clamp(_4840.y, -1.0, 1.0)));
            highp vec2 hp_copy_7779 = _7779;
            highp vec2 _7784 = (hp_copy_7779 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _7691 = clamp(_7784.y, 0.00390625, 0.99609375);
            float _7697 = floor(0.0);
            highp float _7716 = _7784.x;
            _8554 = mix(textureLod(prefiltered_radiance, vec2(_7716, (_7697 + _7691) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_7716, (min(_7697 + 1.0, 7.0) + _7691) * 0.125), 0.0).xyz, vec3(-_7697));
            break;
        } while(false);
        hp_copy_8554 = _8554;
        _8555 = hp_copy_8554 * hp_copy_4687;
    }
    else
    {
        _8555 = _FogInfo.color.xyz;
    }
    highp vec4 _4855 = vec4(min(((((((_4735 + ((_4555 * _4738) * ((vec3(1.0) - _4711) - _4735))) * (hp_copy_4672 * hp_copy_4687)) * vec3(_3808)) + (((_4711 * (_8511 * _4687)) * 1.0) * _8523)) * mix(1.0, _4615, frag_info.radiance_blend.y)) + (_8552 * mix(1.0, _8518, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _8468, vec3(65504.0)), 1.0) * _8818;
    highp vec4 _8570 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _8570 = _4855;
            break;
        }
        int _7828 = int(_FogInfo.params0.x + 0.5);
        if (_7828 == 0)
        {
            _8570 = _4855;
            break;
        }
        highp float _8557 = 0.0;
        if (_6743)
        {
            _8557 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _8557 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_8557 > _FogInfo.params1.w))
        {
            _8570 = _4855;
            break;
        }
        float _8561 = 0.0;
        if (_7828 == 1)
        {
            _8561 = clamp((_8557 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _8562 = 0.0;
            if (_7828 == 2)
            {
                highp float _8560 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _8558 = vec3(0.0);
                    if (_6743)
                    {
                        _8558 = v_position - (view_info.camera_forward.xyz * _8557);
                    }
                    else
                    {
                        _8558 = v_position + v_viewvector;
                    }
                    highp float _7919 = -_FogInfo.params2.y;
                    highp float _7926 = _FogInfo.params1.x * exp(_7919 * (_8558.y - _FogInfo.params2.x));
                    highp float _7943 = _FogInfo.params2.y * (v_position.y - _8558.y);
                    highp float _8559 = 0.0;
                    if (abs(_7943) > 0.00124999997206032276153564453125)
                    {
                        _8559 = (_7926 - (_FogInfo.params1.x * exp(_7919 * (v_position.y - _FogInfo.params2.x)))) / _7943;
                    }
                    else
                    {
                        _8559 = _7926;
                    }
                    _8560 = _8559 * max(_8557 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _8560 = _FogInfo.params1.x * max(_8557 - _FogInfo.params1.y, 0.0);
                }
                _8562 = 1.0 - exp(-_8560);
            }
            else
            {
                highp float _7881 = _FogInfo.params1.x * max(_8557 - _FogInfo.params1.y, 0.0);
                _8562 = 1.0 - exp((-_7881) * _7881);
            }
            _8561 = _8562;
        }
        highp float _7983 = min(_8561, _FogInfo.params0.z);
        if (_7983 <= 0.0)
        {
            _8570 = _4855;
            break;
        }
        highp vec3 _7996 = mix(_FogInfo.color.xyz, _8555, vec3(_FogInfo.params0.w));
        bool _7999 = _FogInfo.sun.w > 0.5;
        bool _8005 = false;
        if (_7999)
        {
            _8005 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _8005 = _7999;
        }
        vec3 _8566 = vec3(0.0);
        if (_8005)
        {
            vec3 mp_copy_8563 = vec3(0.0);
            highp vec3 _8563 = vec3(0.0);
            if (_6743)
            {
                _8563 = -view_info.camera_forward.xyz;
            }
            else
            {
                _8563 = normalize(v_viewvector);
            }
            mp_copy_8563 = _8563;
            highp float _8021 = pow(max(dot(-mp_copy_8563, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_8021 = _8021;
            _8566 = _7996 + ((_FogInfo.sun.xyz * mp_copy_8021) * _FogInfo.params2.z);
        }
        else
        {
            _8566 = _7996;
        }
        highp float _8034 = _4855.w;
        float mp_copy_8034 = _8034;
        _8570 = vec4(mix(_4855.xyz, _8566 * mp_copy_8034, vec3(_7983)), _8034);
        break;
    } while(false);
    vec4 _8572 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _8572 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _8572 = _8570;
        break;
    } while(false);
    frag_color = _8572;
    float _8573 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _8573 = 1.0;
    }
    else
    {
        _8573 = abs(frag_info.fade);
    }
    frag_color *= _8573;
}

