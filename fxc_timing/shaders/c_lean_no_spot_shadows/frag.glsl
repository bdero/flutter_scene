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
    highp float _3862 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_3862 = _3862;
    vec3 _3866 = normalize(v_normal) * mp_copy_3862;
    vec4 _3908 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _3911 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9184 = vec2(0.0);
    if (_3911)
    {
        highp vec2 _9183 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9183 = v_texture_coords_1;
        }
        else
        {
            _9183 = v_texture_coords;
        }
        highp vec2 _4114 = _9183 * texture_transforms.base_color_transform.zw;
        highp float _4120 = _4114.x;
        highp float _4125 = _4114.y;
        _9184 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4120) + (texture_transforms.base_color_rotation.y * _4125), ((-texture_transforms.base_color_rotation.y) * _4120) + (texture_transforms.base_color_rotation.x * _4125));
    }
    else
    {
        _9184 = v_texture_coords;
    }
    vec4 _3925 = texture(base_color_texture, _9184);
    vec3 _3927 = _3925.xyz;
    float _9629 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3925.w * _3908.w) * frag_info.color.w);
    vec3 _9199 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9187 = vec2(0.0);
        if (_3911)
        {
            highp vec2 _9186 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9186 = v_texture_coords_1;
            }
            else
            {
                _9186 = v_texture_coords;
            }
            highp vec2 _4209 = _9186 * texture_transforms.normal_transform.zw;
            highp float _4215 = _4209.x;
            highp float _4220 = _4209.y;
            _9187 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4215) + (texture_transforms.normal_rotation.y * _4220), ((-texture_transforms.normal_rotation.y) * _4215) + (texture_transforms.normal_rotation.x * _4220));
        }
        else
        {
            _9187 = v_texture_coords;
        }
        vec3 _4265 = ((texture(normal_texture, _9187).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4269 = _4265.xy * vec2(frag_info.normal_scale);
        vec3 _8952 = _4265;
        _8952.x = _4269.x;
        _8952.y = _4269.y;
        highp vec3 _4275 = -v_viewvector;
        highp vec3 _4365 = dFdx(_4275);
        highp vec3 _4367 = dFdy(_4275);
        highp vec2 _4369 = dFdx(_9187);
        highp vec2 _4371 = dFdy(_9187);
        bvec2 _9631 = bvec2(length(_4369) == 0.0);
        highp vec2 _9632 = vec2(_9631.x ? vec2(1.0, 0.0).x : _4369.x, _9631.y ? vec2(1.0, 0.0).y : _4369.y);
        bvec2 _9633 = bvec2(length(_4371) == 0.0);
        highp vec2 _9634 = vec2(_9633.x ? vec2(0.0, 1.0).x : _4371.x, _9633.y ? vec2(0.0, 1.0).y : _4371.y);
        highp vec3 _4384 = cross(_4367, _3866);
        highp vec3 _4387 = cross(_3866, _4365);
        highp float _4412 = (dot(cross(_4365, _4367), _3866) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4415 = ((_4384 * _9632.x) + (_4387 * _9634.x)) * _4412;
        highp float _9194 = 0.0;
        if (gl_FrontFacing)
        {
            _9194 = -_4412;
        }
        else
        {
            _9194 = _4412;
        }
        highp vec3 _4425 = ((_4384 * _9632.y) + (_4387 * _9634.y)) * _9194;
        highp float _4434 = inversesqrt(max(max(dot(_4415, _4415), dot(_4425, _4425)), 9.9999996826552253889678874634872e-21));
        vec3 _4306 = v_tangent.xyz - (_3866 * dot(_3866, v_tangent.xyz));
        highp float _4309 = dot(_4306, _4306);
        bool _4311 = _4309 > 1.0000000133514319600180897396058e-10;
        bool _4318 = false;
        if (_4311)
        {
            _4318 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4318 = _4311;
        }
        mat3 _9197 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4318)
        {
            highp vec3 _4323 = _4306 * inversesqrt(_4309);
            _9197 = mat3(_4323, normalize(cross(_3866, _4323)) * sign(v_tangent.w), _3866);
        }
        else
        {
            _9197 = mat3(_4415 * _4434, _4425 * _4434, _3866);
        }
        _9199 = normalize(_9197 * _8952);
    }
    else
    {
        _9199 = _3866;
    }
    highp vec2 _9201 = vec2(0.0);
    if (_3911)
    {
        highp vec2 _9200 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9200 = v_texture_coords_1;
        }
        else
        {
            _9200 = v_texture_coords;
        }
        highp vec2 _4502 = _9200 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4508 = _4502.x;
        highp float _4513 = _4502.y;
        _9201 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4508) + (texture_transforms.metallic_roughness_rotation.y * _4513), ((-texture_transforms.metallic_roughness_rotation.y) * _4508) + (texture_transforms.metallic_roughness_rotation.x * _4513));
    }
    else
    {
        _9201 = v_texture_coords;
    }
    vec4 _3994 = texture(metallic_roughness_texture, _9201);
    float _4000 = clamp(_3994.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4007 = clamp(_3994.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9203 = vec2(0.0);
    if (_3911)
    {
        highp vec2 _9202 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9202 = v_texture_coords_1;
        }
        else
        {
            _9202 = v_texture_coords;
        }
        highp vec2 _4573 = _9202 * texture_transforms.occlusion_transform.zw;
        highp float _4579 = _4573.x;
        highp float _4584 = _4573.y;
        _9203 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4579) + (texture_transforms.occlusion_rotation.y * _4584), ((-texture_transforms.occlusion_rotation.y) * _4579) + (texture_transforms.occlusion_rotation.x * _4584));
    }
    else
    {
        _9203 = v_texture_coords;
    }
    float _9204 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9204 = texture(occlusion_texture, _9203).x;
    }
    else
    {
        _9204 = 1.0;
    }
    float _4034 = 1.0 - ((1.0 - _9204) * frag_info.occlusion_strength);
    highp vec2 _9206 = vec2(0.0);
    if (_3911)
    {
        highp vec2 _9205 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9205 = v_texture_coords_1;
        }
        else
        {
            _9205 = v_texture_coords;
        }
        highp vec2 _4644 = _9205 * texture_transforms.emissive_transform.zw;
        highp float _4650 = _4644.x;
        highp float _4655 = _4644.y;
        _9206 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4650) + (texture_transforms.emissive_rotation.y * _4655), ((-texture_transforms.emissive_rotation.y) * _4650) + (texture_transforms.emissive_rotation.x * _4655));
    }
    else
    {
        _9206 = v_texture_coords;
    }
    vec3 _4053 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9222 = vec3(0.0);
    if (dot(abs(_4053), vec3(1.0)) > 0.0)
    {
        vec3 _4062 = texture(emissive_texture, _9206).xyz;
        _9222 = mix(_4062 * vec3(0.077399380505084991455078125), pow((_4062 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4062)) * _4053;
    }
    else
    {
        _9222 = vec3(0.0);
    }
    highp float hp_copy_9247 = 0.0;
    vec3 _4825 = vec4((mix(_3927 * vec3(0.077399380505084991455078125), pow((_3927 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3927)) * _3908.xyz) * frag_info.color.xyz, _9629).xyz;
    vec3 _5284 = dFdx(_9199);
    vec3 _5286 = dFdy(_9199);
    float _9247 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9247 = sqrt(clamp((_4007 * _4007) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5284, _5284), dot(_5286, _5286))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9247 = _4007;
    }
    hp_copy_9247 = _9247;
    float _9276 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9276 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9276 = _4034;
    }
    bool _4850 = frag_info.has_directional_light > 0.5;
    float _9248 = 0.0;
    vec3 _9290 = vec3(0.0);
    if (_4850)
    {
        highp vec3 _4856 = -normalize(frag_info.directional_light_direction.xyz);
        _9290 = _4856;
        _9248 = dot(_3866, _4856);
    }
    else
    {
        _9290 = vec3(0.0);
        _9248 = 0.0;
    }
    float _4863 = clamp(_9248 * 6.666666507720947265625, 0.0, 1.0);
    bool _4872 = false;
    if (_4850)
    {
        _4872 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _4872 = _4850;
    }
    float _9257 = 0.0;
    if (_4872 && (_4863 > 0.0))
    {
        int _5365 = int(frag_info.shadow_cascade_count);
        float _5560 = max(dot(_3866, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5563 = _5560 * _5560;
        highp vec3 _5583 = v_position + (_3866 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5563, 0.0)) / _5563, 8.0))));
        highp float _5371 = frag_info.directional_light_color.w * 0.5;
        float _5373 = frag_info.dielectric_f0.w;
        highp float hp_copy_5373 = _5373;
        float _9249 = 0.0;
        if (_5373 > 0.0)
        {
            _9249 = smoothstep(_5373 - max(frag_info.shadow_fade, hp_copy_5373 * 0.100000001490116119384765625), _5373, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9249 = 0.0;
        }
        float _9251 = 0.0;
        float _9253 = 0.0;
        if (_9249 < 1.0)
        {
            float _9252 = 0.0;
            float _9254 = 0.0;
            _9254 = 0.0;
            _9252 = 0.0;
            float _9491 = 0.0;
            float _9494 = 0.0;
            for (int _9250 = 0; _9250 < _5365; _9254 = _9494, _9252 = _9491, _9250++)
            {
                if (_9254 < 1.0)
                {
                    highp vec4 _5405 = vec4(_5583, 1.0);
                    highp vec4 _9363 = vec4(0.0);
                    highp float _9366 = 0.0;
                    if (_9250 == 0)
                    {
                        _9366 = frag_info.cascade_box_sizes.x;
                        _9363 = frag_info.light_space_matrix[0] * _5405;
                    }
                    else
                    {
                        highp vec4 _9364 = vec4(0.0);
                        highp float _9367 = 0.0;
                        if (_9250 == 1)
                        {
                            _9367 = frag_info.cascade_box_sizes.y;
                            _9364 = frag_info.light_space_matrix[1] * _5405;
                        }
                        else
                        {
                            highp vec4 _9365 = vec4(0.0);
                            highp float _9368 = 0.0;
                            if (_9250 == 2)
                            {
                                _9368 = frag_info.cascade_box_sizes.z;
                                _9365 = frag_info.light_space_matrix[2] * _5405;
                            }
                            else
                            {
                                _9368 = frag_info.cascade_box_sizes.w;
                                _9365 = frag_info.light_space_matrix[3] * _5405;
                            }
                            _9367 = _9368;
                            _9364 = _9365;
                        }
                        _9366 = _9367;
                        _9363 = _9364;
                    }
                    highp vec3 _5450 = _9363.xyz / vec3(_9363.w);
                    highp vec2 _5453 = _5450.xy * 0.5;
                    highp vec2 _5455 = _5453 + vec2(0.5);
                    highp float _5462 = max(frag_info.shadow_softness / _9366, frag_info.shadow_texel_size);
                    highp float _5464 = _5455.x;
                    bool _5466 = _5464 < _5462;
                    bool _5475 = false;
                    if (!_5466)
                    {
                        _5475 = _5464 > (1.0 - _5462);
                    }
                    else
                    {
                        _5475 = _5466;
                    }
                    bool _5483 = false;
                    if (!_5475)
                    {
                        _5483 = _5455.y < _5462;
                    }
                    else
                    {
                        _5483 = _5475;
                    }
                    bool _5492 = false;
                    if (!_5483)
                    {
                        _5492 = _5455.y > (1.0 - _5462);
                    }
                    else
                    {
                        _5492 = _5483;
                    }
                    bool _5499 = false;
                    if (!_5492)
                    {
                        _5499 = _5450.z < 0.0;
                    }
                    else
                    {
                        _5499 = _5492;
                    }
                    bool _5506 = false;
                    if (!_5499)
                    {
                        _5506 = _5450.z > 1.0;
                    }
                    else
                    {
                        _5506 = _5499;
                    }
                    float _9492 = 0.0;
                    float _9495 = 0.0;
                    if (!_5506)
                    {
                        highp vec2 _5599 = vec2(_5462);
                        highp vec2 _5604 = vec2(_5462 + max(_5371, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5612 = vec2(0.5) - _5453;
                        highp vec2 _5614 = smoothstep(_5599, _5604, _5455) * smoothstep(_5599, _5604, _5612);
                        float _9369 = 0.0;
                        if (_5371 > 0.0)
                        {
                            _9369 = _5614.x * _5614.y;
                        }
                        else
                        {
                            _9369 = 1.0;
                        }
                        float _5515 = min(_9369, 1.0 - _9254);
                        float _9493 = 0.0;
                        float _9496 = 0.0;
                        if (_5515 > 0.0)
                        {
                            highp float _5753 = _5450.z - (frag_info.shadow_bias / (7.0 * _9366));
                            highp float _5759 = 1.0 / (float(_5365) + frag_info.spot_shadow_params.x);
                            highp float _5761 = frag_info.directional_light_direction.w;
                            float mp_copy_5761 = _5761;
                            float _5767 = step(0.5, mp_copy_5761) * (1.0 - step(1.5, mp_copy_5761));
                            float _9399 = 0.0;
                            float _9403 = 0.0;
                            if (_5767 < 0.5)
                            {
                                highp float _5778 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_5778 = _5778;
                                _9403 = sin(mp_copy_5778);
                                _9399 = cos(mp_copy_5778);
                            }
                            else
                            {
                                _9403 = 0.0;
                                _9399 = 1.0;
                            }
                            highp float _9406 = 0.0;
                            if ((_5761 > 1.5) && (_5761 < 2.5))
                            {
                                highp float _5802 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _5807 = max(_5802 * _5753, frag_info.shadow_texel_size);
                                float _9395 = 0.0;
                                highp float _9396 = 0.0;
                                _9396 = 0.0;
                                _9395 = 0.0;
                                highp float _5829 = 0.0;
                                float _5832 = 0.0;
                                for (int _9394 = 0; _9394 < 9; _9396 = _5829, _9395 = _5832, _9394++)
                                {
                                    vec2 _9485 = vec2(0.0);
                                    do
                                    {
                                        if (_9394 == 0)
                                        {
                                            _9485 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_9394 == 1)
                                        {
                                            _9485 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_9394 == 2)
                                        {
                                            _9485 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_9394 == 3)
                                        {
                                            _9485 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_9394 == 4)
                                        {
                                            _9485 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_9394 == 5)
                                        {
                                            _9485 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_9394 == 6)
                                        {
                                            _9485 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_9394 == 7)
                                        {
                                            _9485 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_9394 == 8)
                                        {
                                            _9485 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_9394 == 9)
                                        {
                                            _9485 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_9394 == 10)
                                        {
                                            _9485 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_9394 == 11)
                                        {
                                            _9485 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_9394 == 12)
                                        {
                                            _9485 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_9394 == 13)
                                        {
                                            _9485 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_9394 == 14)
                                        {
                                            _9485 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_9394 == 15)
                                        {
                                            _9485 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _9485 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6136 = clamp(_5455 + (vec2((_9485.x * _9399) - (_9485.y * _9403), (_9485.x * _9403) + (_9485.y * _9399)) * _5807), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6145 = _6136.y;
                                    highp vec2 _6146 = vec2((float(_9250) + _6136.x) * _5759, _6145);
                                    _6146.y = 1.0 - _6145;
                                    highp vec4 _6153 = textureLod(shadow_map, _6146, 0.0);
                                    highp float _6154 = _6153.x;
                                    highp float _5824 = step(_6154, _5753);
                                    float mp_copy_5824 = _5824;
                                    _5829 = _9396 + (_6154 * _5824);
                                    _5832 = _9395 + mp_copy_5824;
                                }
                                highp float _9397 = 0.0;
                                if (_9395 > 0.0)
                                {
                                    _9397 = _9396 / _9395;
                                }
                                else
                                {
                                    _9397 = _5753;
                                }
                                _9406 = clamp(_5802 * max(_5753 - _9397, 0.0), frag_info.shadow_texel_size, _5462);
                            }
                            else
                            {
                                _9406 = _5462;
                            }
                            bool _5863 = _5761 > 2.5;
                            bool _9407 = false;
                            float _9432 = 0.0;
                            if ((_5761 < 1.5) || _5863)
                            {
                                highp vec2 _6187 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6191 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6192 = clamp(_5455, _6187, _6191);
                                highp float _6194 = float(_9250);
                                highp float _6201 = _6192.y;
                                highp vec2 _6202 = vec2((_6194 + _6192.x) * _5759, _6201);
                                _6202.y = 1.0 - _6201;
                                highp float _6214 = float(_5753 <= textureLod(shadow_map, _6202, 0.0).x);
                                float mp_copy_6214 = _6214;
                                float _6224 = (-1.0) * _9399;
                                float _6228 = (-1.0) * _9403;
                                highp vec2 _6252 = clamp(_5455 + (vec2(_6224 - _6228, _6228 + _6224) * _9406), _6187, _6191);
                                highp float _6261 = _6252.y;
                                highp vec2 _6262 = vec2((_6194 + _6252.x) * _5759, _6261);
                                _6262.y = 1.0 - _6261;
                                highp float _6274 = float(_5753 <= textureLod(shadow_map, _6262, 0.0).x);
                                float mp_copy_6274 = _6274;
                                highp vec2 _6312 = clamp(_5455 + (vec2(_9399 - _6228, _9403 + _6224) * _9406), _6187, _6191);
                                highp float _6321 = _6312.y;
                                highp vec2 _6322 = vec2((_6194 + _6312.x) * _5759, _6321);
                                _6322.y = 1.0 - _6321;
                                highp float _6334 = float(_5753 <= textureLod(shadow_map, _6322, 0.0).x);
                                float mp_copy_6334 = _6334;
                                highp vec2 _6372 = clamp(_5455 + (vec2(_6224 - _9403, _6228 + _9399) * _9406), _6187, _6191);
                                highp float _6381 = _6372.y;
                                highp vec2 _6382 = vec2((_6194 + _6372.x) * _5759, _6381);
                                _6382.y = 1.0 - _6381;
                                highp float _6394 = float(_5753 <= textureLod(shadow_map, _6382, 0.0).x);
                                float mp_copy_6394 = _6394;
                                highp vec2 _6432 = clamp(_5455 + (vec2(_9399 - _9403, _9403 + _9399) * _9406), _6187, _6191);
                                highp float _6441 = _6432.y;
                                highp vec2 _6442 = vec2((_6194 + _6432.x) * _5759, _6441);
                                _6442.y = 1.0 - _6441;
                                highp float _6454 = float(_5753 <= textureLod(shadow_map, _6442, 0.0).x);
                                float mp_copy_6454 = _6454;
                                float _5909 = (((mp_copy_6214 + mp_copy_6274) + mp_copy_6334) + mp_copy_6394) + mp_copy_6454;
                                _9432 = _5909 * 0.20000000298023223876953125;
                                _9407 = (_5909 < 0.5) || (_5909 > 4.5);
                            }
                            else
                            {
                                _9432 = 0.0;
                                _9407 = false;
                            }
                            float _9430 = 0.0;
                            if (_9407)
                            {
                                _9430 = _9432;
                            }
                            else
                            {
                                float _9431 = 0.0;
                                if (_5863)
                                {
                                    highp vec2 _6673 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6677 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6678 = clamp(_5455 + (vec2(-0.707099974155426025390625) * _9406), _6673, _6677);
                                    highp vec2 _6689 = (vec2(_6678.x, 1.0 - _6678.y) / _6673) - vec2(0.5);
                                    highp vec2 _6691 = floor(_6689);
                                    highp vec2 _6694 = _6689 - _6691;
                                    highp vec2 _6699 = (_6691 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6701 = float(_9250);
                                    highp vec2 _6709 = vec2((_6701 + _6699.x) * _5759, _6699.y);
                                    highp float _6713 = frag_info.shadow_texel_size * _5759;
                                    highp vec2 _6716 = vec2(_6713, frag_info.shadow_texel_size);
                                    highp vec2 _6725 = vec2(_6713, 0.0);
                                    highp vec2 _6733 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _6762 = _6694.x;
                                    highp float _6771 = mix(mix(float(_5753 <= textureLod(shadow_map, _6709, 0.0).x), float(_5753 <= textureLod(shadow_map, _6709 + _6725, 0.0).x), _6762), mix(float(_5753 <= textureLod(shadow_map, _6709 + _6733, 0.0).x), float(_5753 <= textureLod(shadow_map, _6709 + _6716, 0.0).x), _6762), _6694.y);
                                    float mp_copy_6771 = _6771;
                                    highp vec2 _6805 = clamp(_5455 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _9406), _6673, _6677);
                                    highp vec2 _6816 = (vec2(_6805.x, 1.0 - _6805.y) / _6673) - vec2(0.5);
                                    highp vec2 _6818 = floor(_6816);
                                    highp vec2 _6821 = _6816 - _6818;
                                    highp vec2 _6826 = (_6818 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6836 = vec2((_6701 + _6826.x) * _5759, _6826.y);
                                    highp float _6889 = _6821.x;
                                    highp float _6898 = mix(mix(float(_5753 <= textureLod(shadow_map, _6836, 0.0).x), float(_5753 <= textureLod(shadow_map, _6836 + _6725, 0.0).x), _6889), mix(float(_5753 <= textureLod(shadow_map, _6836 + _6733, 0.0).x), float(_5753 <= textureLod(shadow_map, _6836 + _6716, 0.0).x), _6889), _6821.y);
                                    float mp_copy_6898 = _6898;
                                    highp vec2 _6932 = clamp(_5455 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _9406), _6673, _6677);
                                    highp vec2 _6943 = (vec2(_6932.x, 1.0 - _6932.y) / _6673) - vec2(0.5);
                                    highp vec2 _6945 = floor(_6943);
                                    highp vec2 _6948 = _6943 - _6945;
                                    highp vec2 _6953 = (_6945 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6963 = vec2((_6701 + _6953.x) * _5759, _6953.y);
                                    highp float _7016 = _6948.x;
                                    highp float _7025 = mix(mix(float(_5753 <= textureLod(shadow_map, _6963, 0.0).x), float(_5753 <= textureLod(shadow_map, _6963 + _6725, 0.0).x), _7016), mix(float(_5753 <= textureLod(shadow_map, _6963 + _6733, 0.0).x), float(_5753 <= textureLod(shadow_map, _6963 + _6716, 0.0).x), _7016), _6948.y);
                                    float mp_copy_7025 = _7025;
                                    highp vec2 _7059 = clamp(_5455 + (vec2(0.707099974155426025390625) * _9406), _6673, _6677);
                                    highp vec2 _7070 = (vec2(_7059.x, 1.0 - _7059.y) / _6673) - vec2(0.5);
                                    highp vec2 _7072 = floor(_7070);
                                    highp vec2 _7075 = _7070 - _7072;
                                    highp vec2 _7080 = (_7072 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7090 = vec2((_6701 + _7080.x) * _5759, _7080.y);
                                    highp float _7143 = _7075.x;
                                    highp float _7152 = mix(mix(float(_5753 <= textureLod(shadow_map, _7090, 0.0).x), float(_5753 <= textureLod(shadow_map, _7090 + _6725, 0.0).x), _7143), mix(float(_5753 <= textureLod(shadow_map, _7090 + _6733, 0.0).x), float(_5753 <= textureLod(shadow_map, _7090 + _6716, 0.0).x), _7143), _7075.y);
                                    float mp_copy_7152 = _7152;
                                    _9431 = (((mp_copy_6771 + mp_copy_6898) + mp_copy_7025) + mp_copy_7152) * 0.25;
                                }
                                else
                                {
                                    int _5925 = (_5767 > 0.5) ? 17 : 16;
                                    float _9426 = 0.0;
                                    _9426 = 0.0;
                                    float _5953 = 0.0;
                                    for (int _9408 = 0; _9408 < 17; _9426 = _5953, _9408++)
                                    {
                                        if (_9408 >= _5925)
                                        {
                                            break;
                                        }
                                        vec2 _9409 = vec2(0.0);
                                        do
                                        {
                                            if (_9408 == 0)
                                            {
                                                _9409 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_9408 == 1)
                                            {
                                                _9409 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_9408 == 2)
                                            {
                                                _9409 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_9408 == 3)
                                            {
                                                _9409 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_9408 == 4)
                                            {
                                                _9409 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_9408 == 5)
                                            {
                                                _9409 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_9408 == 6)
                                            {
                                                _9409 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_9408 == 7)
                                            {
                                                _9409 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_9408 == 8)
                                            {
                                                _9409 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_9408 == 9)
                                            {
                                                _9409 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_9408 == 10)
                                            {
                                                _9409 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_9408 == 11)
                                            {
                                                _9409 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_9408 == 12)
                                            {
                                                _9409 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_9408 == 13)
                                            {
                                                _9409 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_9408 == 14)
                                            {
                                                _9409 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_9408 == 15)
                                            {
                                                _9409 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _9409 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _9411 = vec2(0.0);
                                        do
                                        {
                                            if (_9408 < 3)
                                            {
                                                _9411 = vec2(float(_9408) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_9408 < 6)
                                            {
                                                _9411 = vec2((float(_9408 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_9408 < 11)
                                            {
                                                _9411 = vec2((float(_9408 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_9408 < 14)
                                            {
                                                _9411 = vec2((float(_9408 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _9411 = vec2(float(_9408 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _5942 = mix(_9409, _9411, vec2(_5767));
                                        float _6593 = _5942.x;
                                        float _6597 = _5942.y;
                                        highp vec2 _6623 = clamp(_5455 + (vec2((_6593 * _9399) - (_6597 * _9403), (_6593 * _9403) + (_6597 * _9399)) * _9406), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _6632 = _6623.y;
                                        highp vec2 _6633 = vec2((float(_9250) + _6623.x) * _5759, _6632);
                                        _6633.y = 1.0 - _6632;
                                        highp float _6645 = float(_5753 <= textureLod(shadow_map, _6633, 0.0).x);
                                        float mp_copy_6645 = _6645;
                                        _5953 = _9426 + mp_copy_6645;
                                    }
                                    _9431 = _9426 / float(_5925);
                                }
                                _9430 = _9431;
                            }
                            bool _5998 = _9250 == (_5365 - 1);
                            bool _6004 = false;
                            if (_5998)
                            {
                                _6004 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6004 = _5998;
                            }
                            float _9433 = 0.0;
                            if (_6004)
                            {
                                highp vec2 _6011 = vec2(frag_info.shadow_fade / _9366);
                                highp vec2 _6019 = smoothstep(vec2(0.0), _6011, _5455) * smoothstep(vec2(0.0), _6011, _5612);
                                _9433 = mix(1.0, _9430, _6019.x * _6019.y);
                            }
                            else
                            {
                                _9433 = _9430;
                            }
                            _9496 = _9254 + _5515;
                            _9493 = _9252 + (_5515 * _9433);
                        }
                        else
                        {
                            _9496 = _9254;
                            _9493 = _9252;
                        }
                        _9495 = _9496;
                        _9492 = _9493;
                    }
                    else
                    {
                        _9495 = _9254;
                        _9492 = _9252;
                    }
                    _9494 = _9495;
                    _9491 = _9492;
                }
                else
                {
                    _9494 = _9254;
                    _9491 = _9252;
                }
            }
            _9253 = _9254;
            _9251 = _9252;
        }
        else
        {
            _9253 = 0.0;
            _9251 = 0.0;
        }
        _9257 = mix(_9251 + (1.0 - _9253), 1.0, _9249);
    }
    else
    {
        _9257 = 1.0;
    }
    vec3 mp_copy_9258 = vec3(0.0);
    float _4885 = _4863 * _9257;
    bool _7160 = view_info.camera_forward.w > 0.5;
    highp vec3 _9258 = vec3(0.0);
    if (_7160)
    {
        _9258 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9258 = normalize(v_viewvector);
    }
    highp float _7204 = 0.0;
    mp_copy_9258 = _9258;
    vec3 _4894 = mix(frag_info.dielectric_f0.xyz, _4825, vec3(_4000));
    float _4898 = max(dot(_9199, _9258), 0.0);
    float _4902 = max(dot(_3866, _9258), 0.0);
    highp vec2 _9259 = vec2(0.0);
    do
    {
        _7204 = frag_info.punctual_dims.x;
        if (_7204 < 0.5)
        {
            _9259 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7216 = v_position - frag_info.camera_position.xyz;
            highp float _7231 = dot(_7216, frag_info.camera_forward.xyz);
            highp float _7237 = max(_7231, 9.9999997473787516355514526367188e-05);
            highp vec2 _7340 = (vec3(dot(_7216, frag_info.camera_right.xyz), dot(_7216, frag_info.camera_up.xyz), _7237).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7237, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7355 = float(int(((((clamp(floor((log2(max(_7231 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7340.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7340.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9259 = vec2(textureLod(punctual_index, vec2((mod(_7355, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7355 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9259 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _4911 = int(_9259.x + 0.5);
    mediump int _4915 = int(_9259.y + 0.5);
    highp vec3 _9304 = vec3(0.0);
    _9304 = vec3(0.0);
    highp vec3 _9589 = vec3(0.0);
    for (int _9260 = 0; _9260 < _4915; _9304 = _9589, _9260++)
    {
        highp float hp_copy_9342 = 0.0;
        highp float _7388 = float(_4911 + _9260);
        highp float _7419 = (float(int(textureLod(punctual_index, vec2((mod(_7388, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7388 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7204;
        highp vec4 _7423 = textureLod(punctual_lights, vec2(0.0625, _7419), 0.0);
        highp vec4 _7440 = textureLod(punctual_lights, vec2(0.1875, _7419), 0.0);
        highp float _4933 = _7423.w;
        highp vec3 _4935 = _7440.xyz;
        vec3 _9338 = vec3(0.0);
        highp vec3 _9340 = vec3(0.0);
        float _9342 = 0.0;
        if (_4933 < 0.5)
        {
            _9342 = _9247;
            _9340 = _4935;
            _9338 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7419), 0.0).xyz);
        }
        else
        {
            highp vec3 _4943 = _7423.xyz - v_position;
            highp float _4946 = dot(_4943, _4943);
            highp float _4950 = inversesqrt(max(_4946, 9.9999999392252902907785028219223e-09));
            highp vec3 _4951 = _4943 * _4950;
            vec3 mp_copy_4951 = _4951;
            highp float _4953 = _7440.w;
            highp float _4958 = (_4946 * _4953) * _4953;
            highp float _4963 = clamp(1.0 - (_4958 * _4958), 0.0, 1.0);
            float mp_copy_4963 = _4963;
            if (_4963 <= 0.0)
            {
                _9589 = _9304;
                continue;
            }
            highp vec4 _7457 = textureLod(punctual_lights, vec2(0.4375, _7419), 0.0);
            highp float _4971 = _7457.w;
            float _9344 = 0.0;
            if (_4971 > 0.0)
            {
                highp float _4998 = (_9247 * _9247) + ((_4971 * 0.5) * _4950);
                float mp_copy_4998 = _4998;
                _9344 = sqrt(min(mp_copy_4998, 1.0));
            }
            else
            {
                _9344 = _9247;
            }
            highp vec3 _5005 = _4935 * ((mp_copy_4963 * mp_copy_4963) / max(pow(max(_4946, _4971 * _4971), _7457.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _9341 = vec3(0.0);
            if (_4933 > 1.5)
            {
                highp vec4 _7474 = textureLod(punctual_lights, vec2(0.3125, _7419), 0.0);
                highp float _5024 = clamp((dot(normalize(_7474.xyz), -mp_copy_4951) * _7474.w) + _7457.x, 0.0, 1.0);
                float mp_copy_5024 = _5024;
                if (_5024 <= 0.0)
                {
                    _9589 = _9304;
                    continue;
                }
                _9341 = _5005 * (mp_copy_5024 * mp_copy_5024);
            }
            else
            {
                _9341 = _5005;
            }
            _9342 = _9344;
            _9340 = _9341;
            _9338 = _4951;
        }
        hp_copy_9342 = _9342;
        highp vec3 _9348 = vec3(0.0);
        highp vec3 _9349 = vec3(0.0);
        do
        {
            float _7557 = max(dot(_9199, _9338), 0.0);
            highp float hp_copy_7557 = _7557;
            if (_7557 <= 0.0)
            {
                _9349 = vec3(0.0);
                _9348 = vec3(0.0);
                break;
            }
            float _7563 = max(_4898, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_7563 = _7563;
            vec3 _7566 = _9338 + mp_copy_9258;
            float _7569 = dot(_7566, _7566);
            vec3 _9346 = vec3(0.0);
            vec3 _9347 = vec3(0.0);
            if (_7569 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _7577 = _7566 * inversesqrt(_7569);
                float _9345 = 0.0;
                do
                {
                    float _7634 = dot(_9199, _7577);
                    if (_7634 <= 0.0)
                    {
                        _9345 = 0.0;
                        break;
                    }
                    float _7641 = _9342 * _9342;
                    vec3 _7644 = cross(_9199, _7577);
                    float _7647 = _7634 * _7641;
                    float _7656 = _7641 / (dot(_7644, _7644) + (_7647 * _7647));
                    _9345 = min((_7656 * _7656) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _7694 = _4894 + ((vec3(1.0) - _4894) * pow(clamp(1.0 - max(dot(_7577, _9258), 0.0), 0.0, 1.0), 5.0));
                _9347 = (_7694 * min(_9345 * (0.5 / max(mix((2.0 * hp_copy_7557) * _7563, hp_copy_7557 + hp_copy_7563, hp_copy_9342 * hp_copy_9342), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9346 = _7694;
            }
            else
            {
                _9347 = vec3(0.0);
                _9346 = _4894;
            }
            _9349 = (_9347 * _9340) * _7557;
            _9348 = (((((vec3(1.0) - _9346) * (1.0 - _4000)) * _4825) * 0.3183098733425140380859375) * _9340) * _7557;
            break;
        } while(false);
        _9589 = _9304 + (_9348 + _9349);
    }
    bool _7918 = false;
    highp vec3 hp_copy_9261 = vec3(0.0);
    mat3 _5075 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5083 = _5075 * vec3(_9199.x, _9199.y, _9199.z);
    vec3 _5086 = _5075 * reflect(-mp_copy_9258, _9199);
    float _7737 = _5083.y;
    float _7744 = _5083.z;
    float _7751 = _5083.x;
    float _7759 = 1.09254801273345947265625 * _7751;
    vec3 _5089 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _7737))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _7744))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _7751))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_7759 * _7737))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _7737) * _7744))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _7744) * _7744) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_7759 * _7744))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_7751 * _7751) - (_7737 * _7737)))), vec3(0.0));
    highp vec3 hp_copy_5089 = _5089;
    vec3 _9261 = vec3(0.0);
    do
    {
        _7918 = radiance_layout_info.mip_layout > 0.5;
        if (_7918)
        {
            vec2 _7997 = vec2(atan(_5086.z, _5086.x), asin(clamp(_5086.y, -1.0, 1.0)));
            highp vec2 hp_copy_7997 = _7997;
            _9261 = textureLod(prefiltered_radiance, (hp_copy_7997 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9247, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8016 = vec2(atan(_5086.z, _5086.x), asin(clamp(_5086.y, -1.0, 1.0)));
        highp vec2 hp_copy_8016 = _8016;
        highp vec2 _8021 = (hp_copy_8016 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _7928 = clamp(_8021.y, 0.00390625, 0.99609375);
        float _7932 = clamp(_9247, 0.0, 1.0) * 7.0;
        float _7934 = floor(_7932);
        highp float _7953 = _8021.x;
        _9261 = mix(textureLod(prefiltered_radiance, vec2(_7953, (_7934 + _7928) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_7953, (min(_7934 + 1.0, 7.0) + _7928) * 0.125), 0.0).xyz, vec3(_7932 - _7934));
        break;
    } while(false);
    hp_copy_9261 = _9261;
    highp vec3 _9267 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9262 = vec3(0.0);
        vec3 _9262 = vec3(0.0);
        do
        {
            if (_7918)
            {
                vec2 _8126 = vec2(atan(_5086.z, _5086.x), asin(clamp(_5086.y, -1.0, 1.0)));
                highp vec2 hp_copy_8126 = _8126;
                _9262 = textureLod(prefiltered_radiance_b, (hp_copy_8126 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9247, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8145 = vec2(atan(_5086.z, _5086.x), asin(clamp(_5086.y, -1.0, 1.0)));
            highp vec2 hp_copy_8145 = _8145;
            highp vec2 _8150 = (hp_copy_8145 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8057 = clamp(_8150.y, 0.00390625, 0.99609375);
            float _8061 = clamp(_9247, 0.0, 1.0) * 7.0;
            float _8063 = floor(_8061);
            highp float _8082 = _8150.x;
            _9262 = mix(textureLod(prefiltered_radiance_b, vec2(_8082, (_8063 + _8057) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_8082, (min(_8063 + 1.0, 7.0) + _8057) * 0.125), 0.0).xyz, vec3(_8061 - _8063));
            break;
        } while(false);
        hp_copy_9262 = _9262;
        _9267 = hp_copy_9261 + hp_copy_9262;
    }
    else
    {
        _9267 = _9261;
    }
    float _5104 = frag_info.environment_intensity;
    highp float hp_copy_5104 = _5104;
    vec2 _5117 = clamp(vec2(_4902, _9247), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5119 = texture(brdf_lut, vec2(_5117.x * 0.3333333432674407958984375, _5117.y));
    float _5123 = _5119.x;
    float _5126 = _5119.y;
    vec3 _5128 = ((_4894 + ((max(vec3(1.0 - _9247), _4894) - _4894) * pow(clamp(1.0 - _4902, 0.0, 1.0), 5.0))) * _5123) + vec3(_5126);
    float _5134 = 1.0 - (_5123 + _5126);
    vec3 _5138 = vec3(1.0) - _4894;
    vec3 _5141 = _4894 + (_5138 * vec3(0.0476190485060214996337890625));
    vec3 _5152 = ((_5128 * _5134) * _5141) / (vec3(1.0) - (_5141 * _5134));
    float _5155 = 1.0 - _4000;
    float _9281 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9281 = clamp((pow(_4898 + _9276, exp2(((-16.0) * _9247) - 1.0)) - 1.0) + _9276, 0.0, 1.0);
    }
    else
    {
        _9281 = _9276;
    }
    highp vec3 _9314 = vec3(0.0);
    if (_4850)
    {
        highp vec3 _9298 = vec3(0.0);
        highp vec3 _9299 = vec3(0.0);
        do
        {
            float _8239 = max(dot(_9199, _9290), 0.0);
            highp float hp_copy_8239 = _8239;
            if (_8239 <= 0.0)
            {
                _9299 = vec3(0.0);
                _9298 = vec3(0.0);
                break;
            }
            float _8245 = max(_4898, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8245 = _8245;
            vec3 _8248 = _9290 + mp_copy_9258;
            float _8251 = dot(_8248, _8248);
            vec3 _9296 = vec3(0.0);
            vec3 _9297 = vec3(0.0);
            if (_8251 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8259 = _8248 * inversesqrt(_8251);
                float _9295 = 0.0;
                do
                {
                    float _8316 = dot(_9199, _8259);
                    if (_8316 <= 0.0)
                    {
                        _9295 = 0.0;
                        break;
                    }
                    float _8323 = _9247 * _9247;
                    vec3 _8326 = cross(_9199, _8259);
                    float _8329 = _8316 * _8323;
                    float _8338 = _8323 / (dot(_8326, _8326) + (_8329 * _8329));
                    _9295 = min((_8338 * _8338) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8376 = _4894 + (_5138 * pow(clamp(1.0 - max(dot(_8259, _9258), 0.0), 0.0, 1.0), 5.0));
                _9297 = (_8376 * min(_9295 * (0.5 / max(mix((2.0 * hp_copy_8239) * _8245, hp_copy_8239 + hp_copy_8245, hp_copy_9247 * hp_copy_9247), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9296 = _8376;
            }
            else
            {
                _9297 = vec3(0.0);
                _9296 = _4894;
            }
            _9299 = (_9297 * frag_info.directional_light_color.xyz) * _8239;
            _9298 = (((((vec3(1.0) - _9296) * _5155) * _4825) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8239;
            break;
        } while(false);
        _9314 = _9304 + ((_9298 + _9299) * _4885);
    }
    else
    {
        _9314 = _9304;
    }
    bool _5246 = _FogInfo.params0.y > 0.5;
    bool _5252 = false;
    if (_5246)
    {
        _5252 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5252 = _5246;
    }
    highp vec3 _9317 = vec3(0.0);
    if (_5252)
    {
        vec3 mp_copy_9315 = vec3(0.0);
        highp vec3 _9315 = vec3(0.0);
        if (_7160)
        {
            _9315 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9315 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9316 = vec3(0.0);
        mp_copy_9315 = _9315;
        vec3 _5257 = _5075 * (-mp_copy_9315);
        vec3 _9316 = vec3(0.0);
        do
        {
            if (_7918)
            {
                vec2 _8498 = vec2(atan(_5257.z, _5257.x), asin(clamp(_5257.y, -1.0, 1.0)));
                highp vec2 hp_copy_8498 = _8498;
                _9316 = textureLod(prefiltered_radiance, (hp_copy_8498 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _8517 = vec2(atan(_5257.z, _5257.x), asin(clamp(_5257.y, -1.0, 1.0)));
            highp vec2 hp_copy_8517 = _8517;
            highp vec2 _8522 = (hp_copy_8517 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8429 = clamp(_8522.y, 0.00390625, 0.99609375);
            float _8435 = floor(0.0);
            highp float _8454 = _8522.x;
            _9316 = mix(textureLod(prefiltered_radiance, vec2(_8454, (_8435 + _8429) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8454, (min(_8435 + 1.0, 7.0) + _8429) * 0.125), 0.0).xyz, vec3(-_8435));
            break;
        } while(false);
        hp_copy_9316 = _9316;
        _9317 = hp_copy_9316 * hp_copy_5104;
    }
    else
    {
        _9317 = _FogInfo.color.xyz;
    }
    highp vec4 _5272 = vec4(min(((((((_5152 + ((_4825 * _5155) * ((vec3(1.0) - _5128) - _5152))) * (hp_copy_5089 * hp_copy_5104)) * vec3(_4034)) + (((_5128 * (_9267 * _5104)) * 1.0) * _9281)) * mix(1.0, _4885, frag_info.radiance_blend.y)) + (_9314 * mix(1.0, _9276, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9222, vec3(65504.0)), 1.0) * _9629;
    highp vec4 _9332 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9332 = _5272;
            break;
        }
        int _8566 = int(_FogInfo.params0.x + 0.5);
        if (_8566 == 0)
        {
            _9332 = _5272;
            break;
        }
        highp float _9319 = 0.0;
        if (_7160)
        {
            _9319 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9319 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9319 > _FogInfo.params1.w))
        {
            _9332 = _5272;
            break;
        }
        float _9323 = 0.0;
        if (_8566 == 1)
        {
            _9323 = clamp((_9319 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9324 = 0.0;
            if (_8566 == 2)
            {
                highp float _9322 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9320 = vec3(0.0);
                    if (_7160)
                    {
                        _9320 = v_position - (view_info.camera_forward.xyz * _9319);
                    }
                    else
                    {
                        _9320 = v_position + v_viewvector;
                    }
                    highp float _8657 = -_FogInfo.params2.y;
                    highp float _8664 = _FogInfo.params1.x * exp(_8657 * (_9320.y - _FogInfo.params2.x));
                    highp float _8681 = _FogInfo.params2.y * (v_position.y - _9320.y);
                    highp float _9321 = 0.0;
                    if (abs(_8681) > 0.00124999997206032276153564453125)
                    {
                        _9321 = (_8664 - (_FogInfo.params1.x * exp(_8657 * (v_position.y - _FogInfo.params2.x)))) / _8681;
                    }
                    else
                    {
                        _9321 = _8664;
                    }
                    _9322 = _9321 * max(_9319 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9322 = _FogInfo.params1.x * max(_9319 - _FogInfo.params1.y, 0.0);
                }
                _9324 = 1.0 - exp(-_9322);
            }
            else
            {
                highp float _8619 = _FogInfo.params1.x * max(_9319 - _FogInfo.params1.y, 0.0);
                _9324 = 1.0 - exp((-_8619) * _8619);
            }
            _9323 = _9324;
        }
        highp float _8721 = min(_9323, _FogInfo.params0.z);
        if (_8721 <= 0.0)
        {
            _9332 = _5272;
            break;
        }
        highp vec3 _8734 = mix(_FogInfo.color.xyz, _9317, vec3(_FogInfo.params0.w));
        bool _8737 = _FogInfo.sun.w > 0.5;
        bool _8743 = false;
        if (_8737)
        {
            _8743 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _8743 = _8737;
        }
        vec3 _9328 = vec3(0.0);
        if (_8743)
        {
            vec3 mp_copy_9325 = vec3(0.0);
            highp vec3 _9325 = vec3(0.0);
            if (_7160)
            {
                _9325 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9325 = normalize(v_viewvector);
            }
            mp_copy_9325 = _9325;
            highp float _8759 = pow(max(dot(-mp_copy_9325, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_8759 = _8759;
            _9328 = _8734 + ((_FogInfo.sun.xyz * mp_copy_8759) * _FogInfo.params2.z);
        }
        else
        {
            _9328 = _8734;
        }
        highp float _8772 = _5272.w;
        float mp_copy_8772 = _8772;
        _9332 = vec4(mix(_5272.xyz, _9328 * mp_copy_8772, vec3(_8721)), _8772);
        break;
    } while(false);
    vec4 _9334 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9334 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9334 = _9332;
        break;
    } while(false);
    frag_color = _9334;
    float _9335 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9335 = 1.0;
    }
    else
    {
        _9335 = abs(frag_info.fade);
    }
    frag_color *= _9335;
}

