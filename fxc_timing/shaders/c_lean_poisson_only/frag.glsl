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
    highp float _3889 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_3889 = _3889;
    vec3 _3893 = normalize(v_normal) * mp_copy_3889;
    vec4 _3935 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _3938 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9042 = vec2(0.0);
    if (_3938)
    {
        highp vec2 _9041 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9041 = v_texture_coords_1;
        }
        else
        {
            _9041 = v_texture_coords;
        }
        highp vec2 _4141 = _9041 * texture_transforms.base_color_transform.zw;
        highp float _4147 = _4141.x;
        highp float _4152 = _4141.y;
        _9042 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4147) + (texture_transforms.base_color_rotation.y * _4152), ((-texture_transforms.base_color_rotation.y) * _4147) + (texture_transforms.base_color_rotation.x * _4152));
    }
    else
    {
        _9042 = v_texture_coords;
    }
    vec4 _3952 = texture(base_color_texture, _9042);
    vec3 _3954 = _3952.xyz;
    float _9510 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3952.w * _3935.w) * frag_info.color.w);
    vec3 _9057 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9045 = vec2(0.0);
        if (_3938)
        {
            highp vec2 _9044 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9044 = v_texture_coords_1;
            }
            else
            {
                _9044 = v_texture_coords;
            }
            highp vec2 _4236 = _9044 * texture_transforms.normal_transform.zw;
            highp float _4242 = _4236.x;
            highp float _4247 = _4236.y;
            _9045 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4242) + (texture_transforms.normal_rotation.y * _4247), ((-texture_transforms.normal_rotation.y) * _4242) + (texture_transforms.normal_rotation.x * _4247));
        }
        else
        {
            _9045 = v_texture_coords;
        }
        vec3 _4292 = ((texture(normal_texture, _9045).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4296 = _4292.xy * vec2(frag_info.normal_scale);
        vec3 _8814 = _4292;
        _8814.x = _4296.x;
        _8814.y = _4296.y;
        highp vec3 _4302 = -v_viewvector;
        highp vec3 _4392 = dFdx(_4302);
        highp vec3 _4394 = dFdy(_4302);
        highp vec2 _4396 = dFdx(_9045);
        highp vec2 _4398 = dFdy(_9045);
        bvec2 _9512 = bvec2(length(_4396) == 0.0);
        highp vec2 _9513 = vec2(_9512.x ? vec2(1.0, 0.0).x : _4396.x, _9512.y ? vec2(1.0, 0.0).y : _4396.y);
        bvec2 _9514 = bvec2(length(_4398) == 0.0);
        highp vec2 _9515 = vec2(_9514.x ? vec2(0.0, 1.0).x : _4398.x, _9514.y ? vec2(0.0, 1.0).y : _4398.y);
        highp vec3 _4411 = cross(_4394, _3893);
        highp vec3 _4414 = cross(_3893, _4392);
        highp float _4439 = (dot(cross(_4392, _4394), _3893) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4442 = ((_4411 * _9513.x) + (_4414 * _9515.x)) * _4439;
        highp float _9052 = 0.0;
        if (gl_FrontFacing)
        {
            _9052 = -_4439;
        }
        else
        {
            _9052 = _4439;
        }
        highp vec3 _4452 = ((_4411 * _9513.y) + (_4414 * _9515.y)) * _9052;
        highp float _4461 = inversesqrt(max(max(dot(_4442, _4442), dot(_4452, _4452)), 9.9999996826552253889678874634872e-21));
        vec3 _4333 = v_tangent.xyz - (_3893 * dot(_3893, v_tangent.xyz));
        highp float _4336 = dot(_4333, _4333);
        bool _4338 = _4336 > 1.0000000133514319600180897396058e-10;
        bool _4345 = false;
        if (_4338)
        {
            _4345 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4345 = _4338;
        }
        mat3 _9055 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4345)
        {
            highp vec3 _4350 = _4333 * inversesqrt(_4336);
            _9055 = mat3(_4350, normalize(cross(_3893, _4350)) * sign(v_tangent.w), _3893);
        }
        else
        {
            _9055 = mat3(_4442 * _4461, _4452 * _4461, _3893);
        }
        _9057 = normalize(_9055 * _8814);
    }
    else
    {
        _9057 = _3893;
    }
    highp vec2 _9059 = vec2(0.0);
    if (_3938)
    {
        highp vec2 _9058 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9058 = v_texture_coords_1;
        }
        else
        {
            _9058 = v_texture_coords;
        }
        highp vec2 _4529 = _9058 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4535 = _4529.x;
        highp float _4540 = _4529.y;
        _9059 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4535) + (texture_transforms.metallic_roughness_rotation.y * _4540), ((-texture_transforms.metallic_roughness_rotation.y) * _4535) + (texture_transforms.metallic_roughness_rotation.x * _4540));
    }
    else
    {
        _9059 = v_texture_coords;
    }
    vec4 _4021 = texture(metallic_roughness_texture, _9059);
    float _4027 = clamp(_4021.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4034 = clamp(_4021.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9061 = vec2(0.0);
    if (_3938)
    {
        highp vec2 _9060 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9060 = v_texture_coords_1;
        }
        else
        {
            _9060 = v_texture_coords;
        }
        highp vec2 _4600 = _9060 * texture_transforms.occlusion_transform.zw;
        highp float _4606 = _4600.x;
        highp float _4611 = _4600.y;
        _9061 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4606) + (texture_transforms.occlusion_rotation.y * _4611), ((-texture_transforms.occlusion_rotation.y) * _4606) + (texture_transforms.occlusion_rotation.x * _4611));
    }
    else
    {
        _9061 = v_texture_coords;
    }
    float _9062 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9062 = texture(occlusion_texture, _9061).x;
    }
    else
    {
        _9062 = 1.0;
    }
    float _4061 = 1.0 - ((1.0 - _9062) * frag_info.occlusion_strength);
    highp vec2 _9064 = vec2(0.0);
    if (_3938)
    {
        highp vec2 _9063 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9063 = v_texture_coords_1;
        }
        else
        {
            _9063 = v_texture_coords;
        }
        highp vec2 _4671 = _9063 * texture_transforms.emissive_transform.zw;
        highp float _4677 = _4671.x;
        highp float _4682 = _4671.y;
        _9064 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4677) + (texture_transforms.emissive_rotation.y * _4682), ((-texture_transforms.emissive_rotation.y) * _4677) + (texture_transforms.emissive_rotation.x * _4682));
    }
    else
    {
        _9064 = v_texture_coords;
    }
    vec3 _4080 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9080 = vec3(0.0);
    if (dot(abs(_4080), vec3(1.0)) > 0.0)
    {
        vec3 _4089 = texture(emissive_texture, _9064).xyz;
        _9080 = mix(_4089 * vec3(0.077399380505084991455078125), pow((_4089 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4089)) * _4080;
    }
    else
    {
        _9080 = vec3(0.0);
    }
    highp float hp_copy_9105 = 0.0;
    vec3 _4857 = vec4((mix(_3954 * vec3(0.077399380505084991455078125), pow((_3954 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3954)) * _3935.xyz) * frag_info.color.xyz, _9510).xyz;
    vec3 _5343 = dFdx(_9057);
    vec3 _5345 = dFdy(_9057);
    float _9105 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9105 = sqrt(clamp((_4034 * _4034) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5343, _5343), dot(_5345, _5345))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9105 = _4034;
    }
    hp_copy_9105 = _9105;
    float _9134 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9134 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9134 = _4061;
    }
    bool _4882 = frag_info.has_directional_light > 0.5;
    float _9106 = 0.0;
    vec3 _9148 = vec3(0.0);
    if (_4882)
    {
        highp vec3 _4888 = -normalize(frag_info.directional_light_direction.xyz);
        _9148 = _4888;
        _9106 = dot(_3893, _4888);
    }
    else
    {
        _9148 = vec3(0.0);
        _9106 = 0.0;
    }
    float _4895 = clamp(_9106 * 6.666666507720947265625, 0.0, 1.0);
    bool _4904 = false;
    if (_4882)
    {
        _4904 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _4904 = _4882;
    }
    float _9115 = 0.0;
    if (_4904 && (_4895 > 0.0))
    {
        int _5424 = int(frag_info.shadow_cascade_count);
        float _5619 = max(dot(_3893, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5622 = _5619 * _5619;
        highp vec3 _5642 = v_position + (_3893 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5622, 0.0)) / _5622, 8.0))));
        highp float _5430 = frag_info.directional_light_color.w * 0.5;
        float _5432 = frag_info.dielectric_f0.w;
        highp float hp_copy_5432 = _5432;
        float _9107 = 0.0;
        if (_5432 > 0.0)
        {
            _9107 = smoothstep(_5432 - max(frag_info.shadow_fade, hp_copy_5432 * 0.100000001490116119384765625), _5432, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9107 = 0.0;
        }
        float _9109 = 0.0;
        float _9111 = 0.0;
        if (_9107 < 1.0)
        {
            float _9110 = 0.0;
            float _9112 = 0.0;
            _9112 = 0.0;
            _9110 = 0.0;
            float _9361 = 0.0;
            float _9364 = 0.0;
            for (int _9108 = 0; _9108 < _5424; _9112 = _9364, _9110 = _9361, _9108++)
            {
                if (_9112 < 1.0)
                {
                    highp vec4 _5464 = vec4(_5642, 1.0);
                    highp vec4 _9267 = vec4(0.0);
                    highp float _9270 = 0.0;
                    if (_9108 == 0)
                    {
                        _9270 = frag_info.cascade_box_sizes.x;
                        _9267 = frag_info.light_space_matrix[0] * _5464;
                    }
                    else
                    {
                        highp vec4 _9268 = vec4(0.0);
                        highp float _9271 = 0.0;
                        if (_9108 == 1)
                        {
                            _9271 = frag_info.cascade_box_sizes.y;
                            _9268 = frag_info.light_space_matrix[1] * _5464;
                        }
                        else
                        {
                            highp vec4 _9269 = vec4(0.0);
                            highp float _9272 = 0.0;
                            if (_9108 == 2)
                            {
                                _9272 = frag_info.cascade_box_sizes.z;
                                _9269 = frag_info.light_space_matrix[2] * _5464;
                            }
                            else
                            {
                                _9272 = frag_info.cascade_box_sizes.w;
                                _9269 = frag_info.light_space_matrix[3] * _5464;
                            }
                            _9271 = _9272;
                            _9268 = _9269;
                        }
                        _9270 = _9271;
                        _9267 = _9268;
                    }
                    highp vec3 _5509 = _9267.xyz / vec3(_9267.w);
                    highp vec2 _5512 = _5509.xy * 0.5;
                    highp vec2 _5514 = _5512 + vec2(0.5);
                    highp float _5521 = max(frag_info.shadow_softness / _9270, frag_info.shadow_texel_size);
                    highp float _5523 = _5514.x;
                    bool _5525 = _5523 < _5521;
                    bool _5534 = false;
                    if (!_5525)
                    {
                        _5534 = _5523 > (1.0 - _5521);
                    }
                    else
                    {
                        _5534 = _5525;
                    }
                    bool _5542 = false;
                    if (!_5534)
                    {
                        _5542 = _5514.y < _5521;
                    }
                    else
                    {
                        _5542 = _5534;
                    }
                    bool _5551 = false;
                    if (!_5542)
                    {
                        _5551 = _5514.y > (1.0 - _5521);
                    }
                    else
                    {
                        _5551 = _5542;
                    }
                    bool _5558 = false;
                    if (!_5551)
                    {
                        _5558 = _5509.z < 0.0;
                    }
                    else
                    {
                        _5558 = _5551;
                    }
                    bool _5565 = false;
                    if (!_5558)
                    {
                        _5565 = _5509.z > 1.0;
                    }
                    else
                    {
                        _5565 = _5558;
                    }
                    float _9362 = 0.0;
                    float _9365 = 0.0;
                    if (!_5565)
                    {
                        highp vec2 _5658 = vec2(_5521);
                        highp vec2 _5663 = vec2(_5521 + max(_5430, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5671 = vec2(0.5) - _5512;
                        highp vec2 _5673 = smoothstep(_5658, _5663, _5514) * smoothstep(_5658, _5663, _5671);
                        float _9273 = 0.0;
                        if (_5430 > 0.0)
                        {
                            _9273 = _5673.x * _5673.y;
                        }
                        else
                        {
                            _9273 = 1.0;
                        }
                        float _5574 = min(_9273, 1.0 - _9112);
                        float _9363 = 0.0;
                        float _9366 = 0.0;
                        if (_5574 > 0.0)
                        {
                            highp float _5769 = _5509.z - (frag_info.shadow_bias / (7.0 * _9270));
                            highp float _5775 = 1.0 / (float(_5424) + frag_info.spot_shadow_params.x);
                            highp float _5777 = frag_info.directional_light_direction.w;
                            float mp_copy_5777 = _5777;
                            float _5783 = step(0.5, mp_copy_5777) * (1.0 - step(1.5, mp_copy_5777));
                            float _9298 = 0.0;
                            float _9299 = 0.0;
                            if (_5783 < 0.5)
                            {
                                highp float _5794 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_5794 = _5794;
                                _9299 = sin(mp_copy_5794);
                                _9298 = cos(mp_copy_5794);
                            }
                            else
                            {
                                _9299 = 0.0;
                                _9298 = 1.0;
                            }
                            bool _9300 = false;
                            float _9320 = 0.0;
                            if ((_5777 < 1.5) || (_5777 > 2.5))
                            {
                                highp vec2 _5975 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _5979 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _5980 = clamp(_5514, _5975, _5979);
                                highp float _5982 = float(_9108);
                                highp float _5989 = _5980.y;
                                highp vec2 _5990 = vec2((_5982 + _5980.x) * _5775, _5989);
                                _5990.y = 1.0 - _5989;
                                highp float _6002 = float(_5769 <= textureLod(shadow_map, _5990, 0.0).x);
                                float mp_copy_6002 = _6002;
                                float _6012 = (-1.0) * _9298;
                                float _6016 = (-1.0) * _9299;
                                highp vec2 _6040 = clamp(_5514 + (vec2(_6012 - _6016, _6016 + _6012) * _5521), _5975, _5979);
                                highp float _6049 = _6040.y;
                                highp vec2 _6050 = vec2((_5982 + _6040.x) * _5775, _6049);
                                _6050.y = 1.0 - _6049;
                                highp float _6062 = float(_5769 <= textureLod(shadow_map, _6050, 0.0).x);
                                float mp_copy_6062 = _6062;
                                highp vec2 _6100 = clamp(_5514 + (vec2(_9298 - _6016, _9299 + _6012) * _5521), _5975, _5979);
                                highp float _6109 = _6100.y;
                                highp vec2 _6110 = vec2((_5982 + _6100.x) * _5775, _6109);
                                _6110.y = 1.0 - _6109;
                                highp float _6122 = float(_5769 <= textureLod(shadow_map, _6110, 0.0).x);
                                float mp_copy_6122 = _6122;
                                highp vec2 _6160 = clamp(_5514 + (vec2(_6012 - _9299, _6016 + _9298) * _5521), _5975, _5979);
                                highp float _6169 = _6160.y;
                                highp vec2 _6170 = vec2((_5982 + _6160.x) * _5775, _6169);
                                _6170.y = 1.0 - _6169;
                                highp float _6182 = float(_5769 <= textureLod(shadow_map, _6170, 0.0).x);
                                float mp_copy_6182 = _6182;
                                highp vec2 _6220 = clamp(_5514 + (vec2(_9298 - _9299, _9299 + _9298) * _5521), _5975, _5979);
                                highp float _6229 = _6220.y;
                                highp vec2 _6230 = vec2((_5982 + _6220.x) * _5775, _6229);
                                _6230.y = 1.0 - _6229;
                                highp float _6242 = float(_5769 <= textureLod(shadow_map, _6230, 0.0).x);
                                float mp_copy_6242 = _6242;
                                float _5857 = (((mp_copy_6002 + mp_copy_6062) + mp_copy_6122) + mp_copy_6182) + mp_copy_6242;
                                _9320 = _5857 * 0.20000000298023223876953125;
                                _9300 = (_5857 < 0.5) || (_5857 > 4.5);
                            }
                            else
                            {
                                _9320 = 0.0;
                                _9300 = false;
                            }
                            float _9319 = 0.0;
                            if (_9300)
                            {
                                _9319 = _9320;
                            }
                            else
                            {
                                int _5870 = (_5783 > 0.5) ? 17 : 16;
                                float _9315 = 0.0;
                                _9315 = 0.0;
                                float _5898 = 0.0;
                                for (int _9301 = 0; _9301 < 17; _9315 = _5898, _9301++)
                                {
                                    if (_9301 >= _5870)
                                    {
                                        break;
                                    }
                                    vec2 _9302 = vec2(0.0);
                                    do
                                    {
                                        if (_9301 == 0)
                                        {
                                            _9302 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_9301 == 1)
                                        {
                                            _9302 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_9301 == 2)
                                        {
                                            _9302 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_9301 == 3)
                                        {
                                            _9302 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_9301 == 4)
                                        {
                                            _9302 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_9301 == 5)
                                        {
                                            _9302 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_9301 == 6)
                                        {
                                            _9302 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_9301 == 7)
                                        {
                                            _9302 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_9301 == 8)
                                        {
                                            _9302 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_9301 == 9)
                                        {
                                            _9302 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_9301 == 10)
                                        {
                                            _9302 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_9301 == 11)
                                        {
                                            _9302 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_9301 == 12)
                                        {
                                            _9302 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_9301 == 13)
                                        {
                                            _9302 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_9301 == 14)
                                        {
                                            _9302 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_9301 == 15)
                                        {
                                            _9302 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _9302 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _9304 = vec2(0.0);
                                    do
                                    {
                                        if (_9301 < 3)
                                        {
                                            _9304 = vec2(float(_9301) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_9301 < 6)
                                        {
                                            _9304 = vec2((float(_9301 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_9301 < 11)
                                        {
                                            _9304 = vec2((float(_9301 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_9301 < 14)
                                        {
                                            _9304 = vec2((float(_9301 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _9304 = vec2(float(_9301 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _5887 = mix(_9302, _9304, vec2(_5783));
                                    float _6381 = _5887.x;
                                    float _6385 = _5887.y;
                                    highp vec2 _6411 = clamp(_5514 + (vec2((_6381 * _9298) - (_6385 * _9299), (_6381 * _9299) + (_6385 * _9298)) * _5521), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6420 = _6411.y;
                                    highp vec2 _6421 = vec2((float(_9108) + _6411.x) * _5775, _6420);
                                    _6421.y = 1.0 - _6420;
                                    highp float _6433 = float(_5769 <= textureLod(shadow_map, _6421, 0.0).x);
                                    float mp_copy_6433 = _6433;
                                    _5898 = _9315 + mp_copy_6433;
                                }
                                _9319 = _9315 / float(_5870);
                            }
                            bool _5912 = _9108 == (_5424 - 1);
                            bool _5918 = false;
                            if (_5912)
                            {
                                _5918 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _5918 = _5912;
                            }
                            float _9321 = 0.0;
                            if (_5918)
                            {
                                highp vec2 _5925 = vec2(frag_info.shadow_fade / _9270);
                                highp vec2 _5933 = smoothstep(vec2(0.0), _5925, _5514) * smoothstep(vec2(0.0), _5925, _5671);
                                _9321 = mix(1.0, _9319, _5933.x * _5933.y);
                            }
                            else
                            {
                                _9321 = _9319;
                            }
                            _9366 = _9112 + _5574;
                            _9363 = _9110 + (_5574 * _9321);
                        }
                        else
                        {
                            _9366 = _9112;
                            _9363 = _9110;
                        }
                        _9365 = _9366;
                        _9362 = _9363;
                    }
                    else
                    {
                        _9365 = _9112;
                        _9362 = _9110;
                    }
                    _9364 = _9365;
                    _9361 = _9362;
                }
                else
                {
                    _9364 = _9112;
                    _9361 = _9110;
                }
            }
            _9111 = _9112;
            _9109 = _9110;
        }
        else
        {
            _9111 = 0.0;
            _9109 = 0.0;
        }
        _9115 = mix(_9109 + (1.0 - _9111), 1.0, _9107);
    }
    else
    {
        _9115 = 1.0;
    }
    vec3 mp_copy_9116 = vec3(0.0);
    float _4917 = _4895 * _9115;
    bool _6440 = view_info.camera_forward.w > 0.5;
    highp vec3 _9116 = vec3(0.0);
    if (_6440)
    {
        _9116 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9116 = normalize(v_viewvector);
    }
    highp float _6484 = 0.0;
    mp_copy_9116 = _9116;
    vec3 _4926 = mix(frag_info.dielectric_f0.xyz, _4857, vec3(_4027));
    float _4930 = max(dot(_9057, _9116), 0.0);
    float _4934 = max(dot(_3893, _9116), 0.0);
    highp vec2 _9117 = vec2(0.0);
    do
    {
        _6484 = frag_info.punctual_dims.x;
        if (_6484 < 0.5)
        {
            _9117 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _6496 = v_position - frag_info.camera_position.xyz;
            highp float _6511 = dot(_6496, frag_info.camera_forward.xyz);
            highp float _6517 = max(_6511, 9.9999997473787516355514526367188e-05);
            highp vec2 _6620 = (vec3(dot(_6496, frag_info.camera_right.xyz), dot(_6496, frag_info.camera_up.xyz), _6517).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_6517, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _6635 = float(int(((((clamp(floor((log2(max(_6511 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_6620.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_6620.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9117 = vec2(textureLod(punctual_index, vec2((mod(_6635, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_6635 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9117 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _4943 = int(_9117.x + 0.5);
    mediump int _4947 = int(_9117.y + 0.5);
    highp vec3 _9162 = vec3(0.0);
    _9162 = vec3(0.0);
    highp vec3 _9462 = vec3(0.0);
    for (int _9118 = 0; _9118 < _4947; _9162 = _9462, _9118++)
    {
        highp float hp_copy_9219 = 0.0;
        highp float _6668 = float(_4943 + _9118);
        highp float _6699 = (float(int(textureLod(punctual_index, vec2((mod(_6668, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_6668 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _6484;
        highp vec4 _6703 = textureLod(punctual_lights, vec2(0.0625, _6699), 0.0);
        highp vec4 _6720 = textureLod(punctual_lights, vec2(0.1875, _6699), 0.0);
        highp float _4965 = _6703.w;
        highp vec3 _4967 = _6720.xyz;
        vec3 _9205 = vec3(0.0);
        highp vec3 _9216 = vec3(0.0);
        float _9219 = 0.0;
        if (_4965 < 0.5)
        {
            _9219 = _9105;
            _9216 = _4967;
            _9205 = -normalize(textureLod(punctual_lights, vec2(0.3125, _6699), 0.0).xyz);
        }
        else
        {
            highp vec3 _4975 = _6703.xyz - v_position;
            highp float _4978 = dot(_4975, _4975);
            highp float _4982 = inversesqrt(max(_4978, 9.9999999392252902907785028219223e-09));
            highp vec3 _4983 = _4975 * _4982;
            vec3 mp_copy_4983 = _4983;
            highp float _4985 = _6720.w;
            highp float _4990 = (_4978 * _4985) * _4985;
            highp float _4995 = clamp(1.0 - (_4990 * _4990), 0.0, 1.0);
            float mp_copy_4995 = _4995;
            if (_4995 <= 0.0)
            {
                _9462 = _9162;
                continue;
            }
            highp vec4 _6737 = textureLod(punctual_lights, vec2(0.4375, _6699), 0.0);
            highp float _5003 = _6737.w;
            float _9221 = 0.0;
            if (_5003 > 0.0)
            {
                highp float _5030 = (_9105 * _9105) + ((_5003 * 0.5) * _4982);
                float mp_copy_5030 = _5030;
                _9221 = sqrt(min(mp_copy_5030, 1.0));
            }
            else
            {
                _9221 = _9105;
            }
            highp vec3 _5037 = _4967 * ((mp_copy_4995 * mp_copy_4995) / max(pow(max(_4978, _5003 * _5003), _6737.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _9217 = vec3(0.0);
            if (_4965 > 1.5)
            {
                highp vec4 _6754 = textureLod(punctual_lights, vec2(0.3125, _6699), 0.0);
                highp float _5056 = clamp((dot(normalize(_6754.xyz), -mp_copy_4983) * _6754.w) + _6737.x, 0.0, 1.0);
                float mp_copy_5056 = _5056;
                highp vec3 _5061 = _5037 * (mp_copy_5056 * mp_copy_5056);
                if (_5056 <= 0.0)
                {
                    _9462 = _9162;
                    continue;
                }
                bool _5067 = _5056 > 0.0;
                bool _5073 = false;
                if (_5067)
                {
                    _5073 = _6737.y > (-0.5);
                }
                else
                {
                    _5073 = _5067;
                }
                bool _5079 = false;
                if (_5073)
                {
                    _5079 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5079 = _5073;
                }
                highp vec3 _9218 = vec3(0.0);
                if (_5079)
                {
                    float _9196 = 0.0;
                    do
                    {
                        highp vec4 _6866 = mat4(textureLod(punctual_lights, vec2(0.5625, _6699), 0.0), textureLod(punctual_lights, vec2(0.6875, _6699), 0.0), textureLod(punctual_lights, vec2(0.8125, _6699), 0.0), textureLod(punctual_lights, vec2(0.9375, _6699), 0.0)) * vec4(v_position + (_3893 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _6868 = _6866.w;
                        if (_6868 <= 0.0)
                        {
                            _9196 = 1.0;
                            break;
                        }
                        highp vec3 _6877 = _6866.xyz / vec3(_6868);
                        highp vec2 _6882 = (_6877.xy * 0.5) + vec2(0.5);
                        highp float _6884 = _6882.x;
                        bool _6885 = _6884 < 0.0;
                        bool _6892 = false;
                        if (!_6885)
                        {
                            _6892 = _6884 > 1.0;
                        }
                        else
                        {
                            _6892 = _6885;
                        }
                        bool _6899 = false;
                        if (!_6892)
                        {
                            _6899 = _6882.y < 0.0;
                        }
                        else
                        {
                            _6899 = _6892;
                        }
                        bool _6906 = false;
                        if (!_6899)
                        {
                            _6906 = _6882.y > 1.0;
                        }
                        else
                        {
                            _6906 = _6899;
                        }
                        bool _6913 = false;
                        if (!_6906)
                        {
                            _6913 = _6877.z < 0.0;
                        }
                        else
                        {
                            _6913 = _6906;
                        }
                        bool _6920 = false;
                        if (!_6913)
                        {
                            _6920 = _6877.z > 1.0;
                        }
                        else
                        {
                            _6920 = _6913;
                        }
                        if (_6920)
                        {
                            _9196 = 1.0;
                            break;
                        }
                        highp float _6927 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _6932 = frag_info.shadow_cascade_count + float(int(_6737.y + 0.5));
                        highp float _6937 = _6877.z - frag_info.spot_shadow_params.y;
                        highp float _6948 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_6948 = _6948;
                        highp vec2 _6955 = vec2(cos(mp_copy_6948), sin(mp_copy_6948)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _6957 = _6955.x;
                        highp float _6959 = _6955.y;
                        highp vec2 _6967 = vec2(_6957 - _6959, _6957 + _6959) * 0.707106769084930419921875;
                        highp float _7160 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_6884, 0.0, 1.0)) / _6927, 1.0 - clamp(_6882.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7160 = _7160;
                        highp vec2 _6975 = _6882 + _6955;
                        highp float _7182 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_6975.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_6975.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7182 = _7182;
                        highp vec2 _6983 = _6882 - _6955;
                        highp float _7204 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_6983.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_6983.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7204 = _7204;
                        highp vec2 _6996 = _6882 + vec2(-_6959, _6957);
                        highp float _7226 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_6996.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_6996.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7226 = _7226;
                        highp vec2 _7009 = _6882 + vec2(_6959, -_6957);
                        highp float _7248 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_7009.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_7009.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7248 = _7248;
                        float _7014 = (((mp_copy_7160 + mp_copy_7182) + mp_copy_7204) + mp_copy_7226) + mp_copy_7248;
                        if ((_7014 < 0.5) || (_7014 > 4.5))
                        {
                            _9196 = _7014 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _7026 = _6882 + _6967;
                        highp float _7270 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_7026.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_7026.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7270 = _7270;
                        highp vec2 _7033 = _6882 - _6967;
                        highp float _7292 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_7033.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_7033.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7292 = _7292;
                        highp float _7041 = _6967.y;
                        highp float _7044 = _6967.x;
                        highp vec2 _7046 = _6882 + vec2(-_7041, _7044);
                        highp float _7314 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_7046.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_7046.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7314 = _7314;
                        highp vec2 _7059 = _6882 + vec2(_7041, -_7044);
                        highp float _7336 = float(_6937 <= textureLod(shadow_map, vec2((_6932 + clamp(_7059.x, 0.0, 1.0)) / _6927, 1.0 - clamp(_7059.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7336 = _7336;
                        _9196 = (_7014 + (((mp_copy_7270 + mp_copy_7292) + mp_copy_7314) + mp_copy_7336)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _9218 = _5061 * _9196;
                }
                else
                {
                    _9218 = _5061;
                }
                _9217 = _9218;
            }
            else
            {
                _9217 = _5037;
            }
            _9219 = _9221;
            _9216 = _9217;
            _9205 = _4983;
        }
        hp_copy_9219 = _9219;
        highp vec3 _9234 = vec3(0.0);
        highp vec3 _9235 = vec3(0.0);
        do
        {
            float _7419 = max(dot(_9057, _9205), 0.0);
            highp float hp_copy_7419 = _7419;
            if (_7419 <= 0.0)
            {
                _9235 = vec3(0.0);
                _9234 = vec3(0.0);
                break;
            }
            float _7425 = max(_4930, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_7425 = _7425;
            vec3 _7428 = _9205 + mp_copy_9116;
            float _7431 = dot(_7428, _7428);
            vec3 _9232 = vec3(0.0);
            vec3 _9233 = vec3(0.0);
            if (_7431 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _7439 = _7428 * inversesqrt(_7431);
                float _9231 = 0.0;
                do
                {
                    float _7496 = dot(_9057, _7439);
                    if (_7496 <= 0.0)
                    {
                        _9231 = 0.0;
                        break;
                    }
                    float _7503 = _9219 * _9219;
                    vec3 _7506 = cross(_9057, _7439);
                    float _7509 = _7496 * _7503;
                    float _7518 = _7503 / (dot(_7506, _7506) + (_7509 * _7509));
                    _9231 = min((_7518 * _7518) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _7556 = _4926 + ((vec3(1.0) - _4926) * pow(clamp(1.0 - max(dot(_7439, _9116), 0.0), 0.0, 1.0), 5.0));
                _9233 = (_7556 * min(_9231 * (0.5 / max(mix((2.0 * hp_copy_7419) * _7425, hp_copy_7419 + hp_copy_7425, hp_copy_9219 * hp_copy_9219), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9232 = _7556;
            }
            else
            {
                _9233 = vec3(0.0);
                _9232 = _4926;
            }
            _9235 = (_9233 * _9216) * _7419;
            _9234 = (((((vec3(1.0) - _9232) * (1.0 - _4027)) * _4857) * 0.3183098733425140380859375) * _9216) * _7419;
            break;
        } while(false);
        _9462 = _9162 + (_9234 + _9235);
    }
    bool _7780 = false;
    highp vec3 hp_copy_9119 = vec3(0.0);
    mat3 _5134 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5142 = _5134 * vec3(_9057.x, _9057.y, _9057.z);
    vec3 _5145 = _5134 * reflect(-mp_copy_9116, _9057);
    float _7599 = _5142.y;
    float _7606 = _5142.z;
    float _7613 = _5142.x;
    float _7621 = 1.09254801273345947265625 * _7613;
    vec3 _5148 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _7599))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _7606))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _7613))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_7621 * _7599))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _7599) * _7606))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _7606) * _7606) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_7621 * _7606))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_7613 * _7613) - (_7599 * _7599)))), vec3(0.0));
    highp vec3 hp_copy_5148 = _5148;
    vec3 _9119 = vec3(0.0);
    do
    {
        _7780 = radiance_layout_info.mip_layout > 0.5;
        if (_7780)
        {
            vec2 _7859 = vec2(atan(_5145.z, _5145.x), asin(clamp(_5145.y, -1.0, 1.0)));
            highp vec2 hp_copy_7859 = _7859;
            _9119 = textureLod(prefiltered_radiance, (hp_copy_7859 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9105, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _7878 = vec2(atan(_5145.z, _5145.x), asin(clamp(_5145.y, -1.0, 1.0)));
        highp vec2 hp_copy_7878 = _7878;
        highp vec2 _7883 = (hp_copy_7878 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _7790 = clamp(_7883.y, 0.00390625, 0.99609375);
        float _7794 = clamp(_9105, 0.0, 1.0) * 7.0;
        float _7796 = floor(_7794);
        highp float _7815 = _7883.x;
        _9119 = mix(textureLod(prefiltered_radiance, vec2(_7815, (_7796 + _7790) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_7815, (min(_7796 + 1.0, 7.0) + _7790) * 0.125), 0.0).xyz, vec3(_7794 - _7796));
        break;
    } while(false);
    hp_copy_9119 = _9119;
    highp vec3 _9125 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9120 = vec3(0.0);
        vec3 _9120 = vec3(0.0);
        do
        {
            if (_7780)
            {
                vec2 _7988 = vec2(atan(_5145.z, _5145.x), asin(clamp(_5145.y, -1.0, 1.0)));
                highp vec2 hp_copy_7988 = _7988;
                _9120 = textureLod(prefiltered_radiance_b, (hp_copy_7988 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9105, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8007 = vec2(atan(_5145.z, _5145.x), asin(clamp(_5145.y, -1.0, 1.0)));
            highp vec2 hp_copy_8007 = _8007;
            highp vec2 _8012 = (hp_copy_8007 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _7919 = clamp(_8012.y, 0.00390625, 0.99609375);
            float _7923 = clamp(_9105, 0.0, 1.0) * 7.0;
            float _7925 = floor(_7923);
            highp float _7944 = _8012.x;
            _9120 = mix(textureLod(prefiltered_radiance_b, vec2(_7944, (_7925 + _7919) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_7944, (min(_7925 + 1.0, 7.0) + _7919) * 0.125), 0.0).xyz, vec3(_7923 - _7925));
            break;
        } while(false);
        hp_copy_9120 = _9120;
        _9125 = hp_copy_9119 + hp_copy_9120;
    }
    else
    {
        _9125 = _9119;
    }
    float _5163 = frag_info.environment_intensity;
    highp float hp_copy_5163 = _5163;
    vec2 _5176 = clamp(vec2(_4934, _9105), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5178 = texture(brdf_lut, vec2(_5176.x * 0.3333333432674407958984375, _5176.y));
    float _5182 = _5178.x;
    float _5185 = _5178.y;
    vec3 _5187 = ((_4926 + ((max(vec3(1.0 - _9105), _4926) - _4926) * pow(clamp(1.0 - _4934, 0.0, 1.0), 5.0))) * _5182) + vec3(_5185);
    float _5193 = 1.0 - (_5182 + _5185);
    vec3 _5197 = vec3(1.0) - _4926;
    vec3 _5200 = _4926 + (_5197 * vec3(0.0476190485060214996337890625));
    vec3 _5211 = ((_5187 * _5193) * _5200) / (vec3(1.0) - (_5200 * _5193));
    float _5214 = 1.0 - _4027;
    float _9139 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9139 = clamp((pow(_4930 + _9134, exp2(((-16.0) * _9105) - 1.0)) - 1.0) + _9134, 0.0, 1.0);
    }
    else
    {
        _9139 = _9134;
    }
    highp vec3 _9172 = vec3(0.0);
    if (_4882)
    {
        highp vec3 _9156 = vec3(0.0);
        highp vec3 _9157 = vec3(0.0);
        do
        {
            float _8101 = max(dot(_9057, _9148), 0.0);
            highp float hp_copy_8101 = _8101;
            if (_8101 <= 0.0)
            {
                _9157 = vec3(0.0);
                _9156 = vec3(0.0);
                break;
            }
            float _8107 = max(_4930, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8107 = _8107;
            vec3 _8110 = _9148 + mp_copy_9116;
            float _8113 = dot(_8110, _8110);
            vec3 _9154 = vec3(0.0);
            vec3 _9155 = vec3(0.0);
            if (_8113 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8121 = _8110 * inversesqrt(_8113);
                float _9153 = 0.0;
                do
                {
                    float _8178 = dot(_9057, _8121);
                    if (_8178 <= 0.0)
                    {
                        _9153 = 0.0;
                        break;
                    }
                    float _8185 = _9105 * _9105;
                    vec3 _8188 = cross(_9057, _8121);
                    float _8191 = _8178 * _8185;
                    float _8200 = _8185 / (dot(_8188, _8188) + (_8191 * _8191));
                    _9153 = min((_8200 * _8200) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8238 = _4926 + (_5197 * pow(clamp(1.0 - max(dot(_8121, _9116), 0.0), 0.0, 1.0), 5.0));
                _9155 = (_8238 * min(_9153 * (0.5 / max(mix((2.0 * hp_copy_8101) * _8107, hp_copy_8101 + hp_copy_8107, hp_copy_9105 * hp_copy_9105), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9154 = _8238;
            }
            else
            {
                _9155 = vec3(0.0);
                _9154 = _4926;
            }
            _9157 = (_9155 * frag_info.directional_light_color.xyz) * _8101;
            _9156 = (((((vec3(1.0) - _9154) * _5214) * _4857) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8101;
            break;
        } while(false);
        _9172 = _9162 + ((_9156 + _9157) * _4917);
    }
    else
    {
        _9172 = _9162;
    }
    bool _5305 = _FogInfo.params0.y > 0.5;
    bool _5311 = false;
    if (_5305)
    {
        _5311 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5311 = _5305;
    }
    highp vec3 _9175 = vec3(0.0);
    if (_5311)
    {
        vec3 mp_copy_9173 = vec3(0.0);
        highp vec3 _9173 = vec3(0.0);
        if (_6440)
        {
            _9173 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9173 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9174 = vec3(0.0);
        mp_copy_9173 = _9173;
        vec3 _5316 = _5134 * (-mp_copy_9173);
        vec3 _9174 = vec3(0.0);
        do
        {
            if (_7780)
            {
                vec2 _8360 = vec2(atan(_5316.z, _5316.x), asin(clamp(_5316.y, -1.0, 1.0)));
                highp vec2 hp_copy_8360 = _8360;
                _9174 = textureLod(prefiltered_radiance, (hp_copy_8360 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _8379 = vec2(atan(_5316.z, _5316.x), asin(clamp(_5316.y, -1.0, 1.0)));
            highp vec2 hp_copy_8379 = _8379;
            highp vec2 _8384 = (hp_copy_8379 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8291 = clamp(_8384.y, 0.00390625, 0.99609375);
            float _8297 = floor(0.0);
            highp float _8316 = _8384.x;
            _9174 = mix(textureLod(prefiltered_radiance, vec2(_8316, (_8297 + _8291) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8316, (min(_8297 + 1.0, 7.0) + _8291) * 0.125), 0.0).xyz, vec3(-_8297));
            break;
        } while(false);
        hp_copy_9174 = _9174;
        _9175 = hp_copy_9174 * hp_copy_5163;
    }
    else
    {
        _9175 = _FogInfo.color.xyz;
    }
    highp vec4 _5331 = vec4(min(((((((_5211 + ((_4857 * _5214) * ((vec3(1.0) - _5187) - _5211))) * (hp_copy_5148 * hp_copy_5163)) * vec3(_4061)) + (((_5187 * (_9125 * _5163)) * 1.0) * _9139)) * mix(1.0, _4917, frag_info.radiance_blend.y)) + (_9172 * mix(1.0, _9134, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9080, vec3(65504.0)), 1.0) * _9510;
    highp vec4 _9190 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9190 = _5331;
            break;
        }
        int _8428 = int(_FogInfo.params0.x + 0.5);
        if (_8428 == 0)
        {
            _9190 = _5331;
            break;
        }
        highp float _9177 = 0.0;
        if (_6440)
        {
            _9177 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9177 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9177 > _FogInfo.params1.w))
        {
            _9190 = _5331;
            break;
        }
        float _9181 = 0.0;
        if (_8428 == 1)
        {
            _9181 = clamp((_9177 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9182 = 0.0;
            if (_8428 == 2)
            {
                highp float _9180 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9178 = vec3(0.0);
                    if (_6440)
                    {
                        _9178 = v_position - (view_info.camera_forward.xyz * _9177);
                    }
                    else
                    {
                        _9178 = v_position + v_viewvector;
                    }
                    highp float _8519 = -_FogInfo.params2.y;
                    highp float _8526 = _FogInfo.params1.x * exp(_8519 * (_9178.y - _FogInfo.params2.x));
                    highp float _8543 = _FogInfo.params2.y * (v_position.y - _9178.y);
                    highp float _9179 = 0.0;
                    if (abs(_8543) > 0.00124999997206032276153564453125)
                    {
                        _9179 = (_8526 - (_FogInfo.params1.x * exp(_8519 * (v_position.y - _FogInfo.params2.x)))) / _8543;
                    }
                    else
                    {
                        _9179 = _8526;
                    }
                    _9180 = _9179 * max(_9177 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9180 = _FogInfo.params1.x * max(_9177 - _FogInfo.params1.y, 0.0);
                }
                _9182 = 1.0 - exp(-_9180);
            }
            else
            {
                highp float _8481 = _FogInfo.params1.x * max(_9177 - _FogInfo.params1.y, 0.0);
                _9182 = 1.0 - exp((-_8481) * _8481);
            }
            _9181 = _9182;
        }
        highp float _8583 = min(_9181, _FogInfo.params0.z);
        if (_8583 <= 0.0)
        {
            _9190 = _5331;
            break;
        }
        highp vec3 _8596 = mix(_FogInfo.color.xyz, _9175, vec3(_FogInfo.params0.w));
        bool _8599 = _FogInfo.sun.w > 0.5;
        bool _8605 = false;
        if (_8599)
        {
            _8605 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _8605 = _8599;
        }
        vec3 _9186 = vec3(0.0);
        if (_8605)
        {
            vec3 mp_copy_9183 = vec3(0.0);
            highp vec3 _9183 = vec3(0.0);
            if (_6440)
            {
                _9183 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9183 = normalize(v_viewvector);
            }
            mp_copy_9183 = _9183;
            highp float _8621 = pow(max(dot(-mp_copy_9183, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_8621 = _8621;
            _9186 = _8596 + ((_FogInfo.sun.xyz * mp_copy_8621) * _FogInfo.params2.z);
        }
        else
        {
            _9186 = _8596;
        }
        highp float _8634 = _5331.w;
        float mp_copy_8634 = _8634;
        _9190 = vec4(mix(_5331.xyz, _9186 * mp_copy_8634, vec3(_8583)), _8634);
        break;
    } while(false);
    vec4 _9192 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9192 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9192 = _9190;
        break;
    } while(false);
    frag_color = _9192;
    float _9193 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9193 = 1.0;
    }
    else
    {
        _9193 = abs(frag_info.fade);
    }
    frag_color *= _9193;
}

