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
    highp float _4092 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4092 = _4092;
    vec3 _4096 = normalize(v_normal) * mp_copy_4092;
    vec4 _4138 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4141 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9848 = vec2(0.0);
    if (_4141)
    {
        highp vec2 _9847 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9847 = v_texture_coords_1;
        }
        else
        {
            _9847 = v_texture_coords;
        }
        highp vec2 _4344 = _9847 * texture_transforms.base_color_transform.zw;
        highp float _4350 = _4344.x;
        highp float _4355 = _4344.y;
        _9848 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4350) + (texture_transforms.base_color_rotation.y * _4355), ((-texture_transforms.base_color_rotation.y) * _4350) + (texture_transforms.base_color_rotation.x * _4355));
    }
    else
    {
        _9848 = v_texture_coords;
    }
    vec4 _4155 = texture(base_color_texture, _9848);
    vec3 _4157 = _4155.xyz;
    float _10322 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4155.w * _4138.w) * frag_info.color.w);
    vec3 _9863 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9851 = vec2(0.0);
        if (_4141)
        {
            highp vec2 _9850 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9850 = v_texture_coords_1;
            }
            else
            {
                _9850 = v_texture_coords;
            }
            highp vec2 _4439 = _9850 * texture_transforms.normal_transform.zw;
            highp float _4445 = _4439.x;
            highp float _4450 = _4439.y;
            _9851 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4445) + (texture_transforms.normal_rotation.y * _4450), ((-texture_transforms.normal_rotation.y) * _4445) + (texture_transforms.normal_rotation.x * _4450));
        }
        else
        {
            _9851 = v_texture_coords;
        }
        vec3 _4495 = ((texture(normal_texture, _9851).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4499 = _4495.xy * vec2(frag_info.normal_scale);
        vec3 _9584 = _4495;
        _9584.x = _4499.x;
        _9584.y = _4499.y;
        highp vec3 _4505 = -v_viewvector;
        highp vec3 _4595 = dFdx(_4505);
        highp vec3 _4597 = dFdy(_4505);
        highp vec2 _4599 = dFdx(_9851);
        highp vec2 _4601 = dFdy(_9851);
        bvec2 _10324 = bvec2(length(_4599) == 0.0);
        highp vec2 _10325 = vec2(_10324.x ? vec2(1.0, 0.0).x : _4599.x, _10324.y ? vec2(1.0, 0.0).y : _4599.y);
        bvec2 _10326 = bvec2(length(_4601) == 0.0);
        highp vec2 _10327 = vec2(_10326.x ? vec2(0.0, 1.0).x : _4601.x, _10326.y ? vec2(0.0, 1.0).y : _4601.y);
        highp vec3 _4614 = cross(_4597, _4096);
        highp vec3 _4617 = cross(_4096, _4595);
        highp float _4642 = (dot(cross(_4595, _4597), _4096) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4645 = ((_4614 * _10325.x) + (_4617 * _10327.x)) * _4642;
        highp float _9858 = 0.0;
        if (gl_FrontFacing)
        {
            _9858 = -_4642;
        }
        else
        {
            _9858 = _4642;
        }
        highp vec3 _4655 = ((_4614 * _10325.y) + (_4617 * _10327.y)) * _9858;
        highp float _4664 = inversesqrt(max(max(dot(_4645, _4645), dot(_4655, _4655)), 9.9999996826552253889678874634872e-21));
        vec3 _4536 = v_tangent.xyz - (_4096 * dot(_4096, v_tangent.xyz));
        highp float _4539 = dot(_4536, _4536);
        bool _4541 = _4539 > 1.0000000133514319600180897396058e-10;
        bool _4548 = false;
        if (_4541)
        {
            _4548 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4548 = _4541;
        }
        mat3 _9861 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4548)
        {
            highp vec3 _4553 = _4536 * inversesqrt(_4539);
            _9861 = mat3(_4553, normalize(cross(_4096, _4553)) * sign(v_tangent.w), _4096);
        }
        else
        {
            _9861 = mat3(_4645 * _4664, _4655 * _4664, _4096);
        }
        _9863 = normalize(_9861 * _9584);
    }
    else
    {
        _9863 = _4096;
    }
    highp vec2 _9865 = vec2(0.0);
    if (_4141)
    {
        highp vec2 _9864 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9864 = v_texture_coords_1;
        }
        else
        {
            _9864 = v_texture_coords;
        }
        highp vec2 _4732 = _9864 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4738 = _4732.x;
        highp float _4743 = _4732.y;
        _9865 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4738) + (texture_transforms.metallic_roughness_rotation.y * _4743), ((-texture_transforms.metallic_roughness_rotation.y) * _4738) + (texture_transforms.metallic_roughness_rotation.x * _4743));
    }
    else
    {
        _9865 = v_texture_coords;
    }
    vec4 _4224 = texture(metallic_roughness_texture, _9865);
    float _4230 = clamp(_4224.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4237 = clamp(_4224.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9867 = vec2(0.0);
    if (_4141)
    {
        highp vec2 _9866 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9866 = v_texture_coords_1;
        }
        else
        {
            _9866 = v_texture_coords;
        }
        highp vec2 _4803 = _9866 * texture_transforms.occlusion_transform.zw;
        highp float _4809 = _4803.x;
        highp float _4814 = _4803.y;
        _9867 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4809) + (texture_transforms.occlusion_rotation.y * _4814), ((-texture_transforms.occlusion_rotation.y) * _4809) + (texture_transforms.occlusion_rotation.x * _4814));
    }
    else
    {
        _9867 = v_texture_coords;
    }
    float _9868 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9868 = texture(occlusion_texture, _9867).x;
    }
    else
    {
        _9868 = 1.0;
    }
    float _4264 = 1.0 - ((1.0 - _9868) * frag_info.occlusion_strength);
    highp vec2 _9870 = vec2(0.0);
    if (_4141)
    {
        highp vec2 _9869 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9869 = v_texture_coords_1;
        }
        else
        {
            _9869 = v_texture_coords;
        }
        highp vec2 _4874 = _9869 * texture_transforms.emissive_transform.zw;
        highp float _4880 = _4874.x;
        highp float _4885 = _4874.y;
        _9870 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4880) + (texture_transforms.emissive_rotation.y * _4885), ((-texture_transforms.emissive_rotation.y) * _4880) + (texture_transforms.emissive_rotation.x * _4885));
    }
    else
    {
        _9870 = v_texture_coords;
    }
    vec3 _4283 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9886 = vec3(0.0);
    if (dot(abs(_4283), vec3(1.0)) > 0.0)
    {
        vec3 _4292 = texture(emissive_texture, _9870).xyz;
        _9886 = mix(_4292 * vec3(0.077399380505084991455078125), pow((_4292 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4292)) * _4283;
    }
    else
    {
        _9886 = vec3(0.0);
    }
    highp float hp_copy_9911 = 0.0;
    vec3 _5060 = vec4((mix(_4157 * vec3(0.077399380505084991455078125), pow((_4157 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4157)) * _4138.xyz) * frag_info.color.xyz, _10322).xyz;
    vec3 _5546 = dFdx(_9863);
    vec3 _5548 = dFdy(_9863);
    float _9911 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9911 = sqrt(clamp((_4237 * _4237) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5546, _5546), dot(_5548, _5548))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9911 = _4237;
    }
    hp_copy_9911 = _9911;
    float _9940 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9940 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9940 = _4264;
    }
    bool _5085 = frag_info.has_directional_light > 0.5;
    float _9912 = 0.0;
    vec3 _9954 = vec3(0.0);
    if (_5085)
    {
        highp vec3 _5091 = -normalize(frag_info.directional_light_direction.xyz);
        _9954 = _5091;
        _9912 = dot(_4096, _5091);
    }
    else
    {
        _9954 = vec3(0.0);
        _9912 = 0.0;
    }
    float _5098 = clamp(_9912 * 6.666666507720947265625, 0.0, 1.0);
    bool _5107 = false;
    if (_5085)
    {
        _5107 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5107 = _5085;
    }
    float _9921 = 0.0;
    if (_5107 && (_5098 > 0.0))
    {
        int _5627 = int(frag_info.shadow_cascade_count);
        float _5822 = max(dot(_4096, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5825 = _5822 * _5822;
        highp vec3 _5845 = v_position + (_4096 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5825, 0.0)) / _5825, 8.0))));
        highp float _5633 = frag_info.directional_light_color.w * 0.5;
        float _5635 = frag_info.dielectric_f0.w;
        highp float hp_copy_5635 = _5635;
        float _9913 = 0.0;
        if (_5635 > 0.0)
        {
            _9913 = smoothstep(_5635 - max(frag_info.shadow_fade, hp_copy_5635 * 0.100000001490116119384765625), _5635, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9913 = 0.0;
        }
        float _9915 = 0.0;
        float _9917 = 0.0;
        if (_9913 < 1.0)
        {
            float _9916 = 0.0;
            float _9918 = 0.0;
            _9918 = 0.0;
            _9916 = 0.0;
            float _10171 = 0.0;
            float _10174 = 0.0;
            for (int _9914 = 0; _9914 < _5627; _9918 = _10174, _9916 = _10171, _9914++)
            {
                if (_9918 < 1.0)
                {
                    highp vec4 _5667 = vec4(_5845, 1.0);
                    highp vec4 _10073 = vec4(0.0);
                    highp float _10076 = 0.0;
                    if (_9914 == 0)
                    {
                        _10076 = frag_info.cascade_box_sizes.x;
                        _10073 = frag_info.light_space_matrix[0] * _5667;
                    }
                    else
                    {
                        highp vec4 _10074 = vec4(0.0);
                        highp float _10077 = 0.0;
                        if (_9914 == 1)
                        {
                            _10077 = frag_info.cascade_box_sizes.y;
                            _10074 = frag_info.light_space_matrix[1] * _5667;
                        }
                        else
                        {
                            highp vec4 _10075 = vec4(0.0);
                            highp float _10078 = 0.0;
                            if (_9914 == 2)
                            {
                                _10078 = frag_info.cascade_box_sizes.z;
                                _10075 = frag_info.light_space_matrix[2] * _5667;
                            }
                            else
                            {
                                _10078 = frag_info.cascade_box_sizes.w;
                                _10075 = frag_info.light_space_matrix[3] * _5667;
                            }
                            _10077 = _10078;
                            _10074 = _10075;
                        }
                        _10076 = _10077;
                        _10073 = _10074;
                    }
                    highp vec3 _5712 = _10073.xyz / vec3(_10073.w);
                    highp vec2 _5715 = _5712.xy * 0.5;
                    highp vec2 _5717 = _5715 + vec2(0.5);
                    highp float _5724 = max(frag_info.shadow_softness / _10076, frag_info.shadow_texel_size);
                    highp float _5726 = _5717.x;
                    bool _5728 = _5726 < _5724;
                    bool _5737 = false;
                    if (!_5728)
                    {
                        _5737 = _5726 > (1.0 - _5724);
                    }
                    else
                    {
                        _5737 = _5728;
                    }
                    bool _5745 = false;
                    if (!_5737)
                    {
                        _5745 = _5717.y < _5724;
                    }
                    else
                    {
                        _5745 = _5737;
                    }
                    bool _5754 = false;
                    if (!_5745)
                    {
                        _5754 = _5717.y > (1.0 - _5724);
                    }
                    else
                    {
                        _5754 = _5745;
                    }
                    bool _5761 = false;
                    if (!_5754)
                    {
                        _5761 = _5712.z < 0.0;
                    }
                    else
                    {
                        _5761 = _5754;
                    }
                    bool _5768 = false;
                    if (!_5761)
                    {
                        _5768 = _5712.z > 1.0;
                    }
                    else
                    {
                        _5768 = _5761;
                    }
                    float _10172 = 0.0;
                    float _10175 = 0.0;
                    if (!_5768)
                    {
                        highp vec2 _5861 = vec2(_5724);
                        highp vec2 _5866 = vec2(_5724 + max(_5633, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5874 = vec2(0.5) - _5715;
                        highp vec2 _5876 = smoothstep(_5861, _5866, _5717) * smoothstep(_5861, _5866, _5874);
                        float _10079 = 0.0;
                        if (_5633 > 0.0)
                        {
                            _10079 = _5876.x * _5876.y;
                        }
                        else
                        {
                            _10079 = 1.0;
                        }
                        float _5777 = min(_10079, 1.0 - _9918);
                        float _10173 = 0.0;
                        float _10176 = 0.0;
                        if (_5777 > 0.0)
                        {
                            highp float _5997 = _5712.z - (frag_info.shadow_bias / (7.0 * _10076));
                            highp float _6003 = 1.0 / (float(_5627) + frag_info.spot_shadow_params.x);
                            highp float _6005 = frag_info.directional_light_direction.w;
                            float mp_copy_6005 = _6005;
                            float _6011 = step(0.5, mp_copy_6005) * (1.0 - step(1.5, mp_copy_6005));
                            float _10104 = 0.0;
                            float _10105 = 0.0;
                            if (_6011 < 0.5)
                            {
                                highp float _6022 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6022 = _6022;
                                _10105 = sin(mp_copy_6022);
                                _10104 = cos(mp_copy_6022);
                            }
                            else
                            {
                                _10105 = 0.0;
                                _10104 = 1.0;
                            }
                            bool _6039 = _6005 > 2.5;
                            bool _10106 = false;
                            float _10127 = 0.0;
                            if ((_6005 < 1.5) || _6039)
                            {
                                highp vec2 _6237 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6241 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6242 = clamp(_5717, _6237, _6241);
                                highp float _6244 = float(_9914);
                                highp float _6251 = _6242.y;
                                highp vec2 _6252 = vec2((_6244 + _6242.x) * _6003, _6251);
                                _6252.y = 1.0 - _6251;
                                highp float _6264 = float(_5997 <= textureLod(shadow_map, _6252, 0.0).x);
                                float mp_copy_6264 = _6264;
                                float _6274 = (-1.0) * _10104;
                                float _6278 = (-1.0) * _10105;
                                highp vec2 _6302 = clamp(_5717 + (vec2(_6274 - _6278, _6278 + _6274) * _5724), _6237, _6241);
                                highp float _6311 = _6302.y;
                                highp vec2 _6312 = vec2((_6244 + _6302.x) * _6003, _6311);
                                _6312.y = 1.0 - _6311;
                                highp float _6324 = float(_5997 <= textureLod(shadow_map, _6312, 0.0).x);
                                float mp_copy_6324 = _6324;
                                highp vec2 _6362 = clamp(_5717 + (vec2(_10104 - _6278, _10105 + _6274) * _5724), _6237, _6241);
                                highp float _6371 = _6362.y;
                                highp vec2 _6372 = vec2((_6244 + _6362.x) * _6003, _6371);
                                _6372.y = 1.0 - _6371;
                                highp float _6384 = float(_5997 <= textureLod(shadow_map, _6372, 0.0).x);
                                float mp_copy_6384 = _6384;
                                highp vec2 _6422 = clamp(_5717 + (vec2(_6274 - _10105, _6278 + _10104) * _5724), _6237, _6241);
                                highp float _6431 = _6422.y;
                                highp vec2 _6432 = vec2((_6244 + _6422.x) * _6003, _6431);
                                _6432.y = 1.0 - _6431;
                                highp float _6444 = float(_5997 <= textureLod(shadow_map, _6432, 0.0).x);
                                float mp_copy_6444 = _6444;
                                highp vec2 _6482 = clamp(_5717 + (vec2(_10104 - _10105, _10105 + _10104) * _5724), _6237, _6241);
                                highp float _6491 = _6482.y;
                                highp vec2 _6492 = vec2((_6244 + _6482.x) * _6003, _6491);
                                _6492.y = 1.0 - _6491;
                                highp float _6504 = float(_5997 <= textureLod(shadow_map, _6492, 0.0).x);
                                float mp_copy_6504 = _6504;
                                float _6085 = (((mp_copy_6264 + mp_copy_6324) + mp_copy_6384) + mp_copy_6444) + mp_copy_6504;
                                _10127 = _6085 * 0.20000000298023223876953125;
                                _10106 = (_6085 < 0.5) || (_6085 > 4.5);
                            }
                            else
                            {
                                _10127 = 0.0;
                                _10106 = false;
                            }
                            float _10125 = 0.0;
                            if (_10106)
                            {
                                _10125 = _10127;
                            }
                            else
                            {
                                float _10126 = 0.0;
                                if (_6039)
                                {
                                    highp vec2 _6723 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6727 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6728 = clamp(_5717 + (vec2(-0.707099974155426025390625) * _5724), _6723, _6727);
                                    highp vec2 _6739 = (vec2(_6728.x, 1.0 - _6728.y) / _6723) - vec2(0.5);
                                    highp vec2 _6741 = floor(_6739);
                                    highp vec2 _6744 = _6739 - _6741;
                                    highp vec2 _6749 = (_6741 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6751 = float(_9914);
                                    highp vec2 _6759 = vec2((_6751 + _6749.x) * _6003, _6749.y);
                                    highp float _6763 = frag_info.shadow_texel_size * _6003;
                                    highp vec2 _6766 = vec2(_6763, frag_info.shadow_texel_size);
                                    highp vec2 _6775 = vec2(_6763, 0.0);
                                    highp vec2 _6783 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _6812 = _6744.x;
                                    highp float _6821 = mix(mix(float(_5997 <= textureLod(shadow_map, _6759, 0.0).x), float(_5997 <= textureLod(shadow_map, _6759 + _6775, 0.0).x), _6812), mix(float(_5997 <= textureLod(shadow_map, _6759 + _6783, 0.0).x), float(_5997 <= textureLod(shadow_map, _6759 + _6766, 0.0).x), _6812), _6744.y);
                                    float mp_copy_6821 = _6821;
                                    highp vec2 _6855 = clamp(_5717 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _5724), _6723, _6727);
                                    highp vec2 _6866 = (vec2(_6855.x, 1.0 - _6855.y) / _6723) - vec2(0.5);
                                    highp vec2 _6868 = floor(_6866);
                                    highp vec2 _6871 = _6866 - _6868;
                                    highp vec2 _6876 = (_6868 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6886 = vec2((_6751 + _6876.x) * _6003, _6876.y);
                                    highp float _6939 = _6871.x;
                                    highp float _6948 = mix(mix(float(_5997 <= textureLod(shadow_map, _6886, 0.0).x), float(_5997 <= textureLod(shadow_map, _6886 + _6775, 0.0).x), _6939), mix(float(_5997 <= textureLod(shadow_map, _6886 + _6783, 0.0).x), float(_5997 <= textureLod(shadow_map, _6886 + _6766, 0.0).x), _6939), _6871.y);
                                    float mp_copy_6948 = _6948;
                                    highp vec2 _6982 = clamp(_5717 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _5724), _6723, _6727);
                                    highp vec2 _6993 = (vec2(_6982.x, 1.0 - _6982.y) / _6723) - vec2(0.5);
                                    highp vec2 _6995 = floor(_6993);
                                    highp vec2 _6998 = _6993 - _6995;
                                    highp vec2 _7003 = (_6995 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7013 = vec2((_6751 + _7003.x) * _6003, _7003.y);
                                    highp float _7066 = _6998.x;
                                    highp float _7075 = mix(mix(float(_5997 <= textureLod(shadow_map, _7013, 0.0).x), float(_5997 <= textureLod(shadow_map, _7013 + _6775, 0.0).x), _7066), mix(float(_5997 <= textureLod(shadow_map, _7013 + _6783, 0.0).x), float(_5997 <= textureLod(shadow_map, _7013 + _6766, 0.0).x), _7066), _6998.y);
                                    float mp_copy_7075 = _7075;
                                    highp vec2 _7109 = clamp(_5717 + (vec2(0.707099974155426025390625) * _5724), _6723, _6727);
                                    highp vec2 _7120 = (vec2(_7109.x, 1.0 - _7109.y) / _6723) - vec2(0.5);
                                    highp vec2 _7122 = floor(_7120);
                                    highp vec2 _7125 = _7120 - _7122;
                                    highp vec2 _7130 = (_7122 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7140 = vec2((_6751 + _7130.x) * _6003, _7130.y);
                                    highp float _7193 = _7125.x;
                                    highp float _7202 = mix(mix(float(_5997 <= textureLod(shadow_map, _7140, 0.0).x), float(_5997 <= textureLod(shadow_map, _7140 + _6775, 0.0).x), _7193), mix(float(_5997 <= textureLod(shadow_map, _7140 + _6783, 0.0).x), float(_5997 <= textureLod(shadow_map, _7140 + _6766, 0.0).x), _7193), _7125.y);
                                    float mp_copy_7202 = _7202;
                                    _10126 = (((mp_copy_6821 + mp_copy_6948) + mp_copy_7075) + mp_copy_7202) * 0.25;
                                }
                                else
                                {
                                    int _6101 = (_6011 > 0.5) ? 17 : 16;
                                    float _10121 = 0.0;
                                    _10121 = 0.0;
                                    float _6129 = 0.0;
                                    for (int _10107 = 0; _10107 < 17; _10121 = _6129, _10107++)
                                    {
                                        if (_10107 >= _6101)
                                        {
                                            break;
                                        }
                                        vec2 _10108 = vec2(0.0);
                                        do
                                        {
                                            if (_10107 == 0)
                                            {
                                                _10108 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10107 == 1)
                                            {
                                                _10108 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10107 == 2)
                                            {
                                                _10108 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10107 == 3)
                                            {
                                                _10108 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10107 == 4)
                                            {
                                                _10108 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10107 == 5)
                                            {
                                                _10108 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10107 == 6)
                                            {
                                                _10108 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10107 == 7)
                                            {
                                                _10108 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10107 == 8)
                                            {
                                                _10108 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10107 == 9)
                                            {
                                                _10108 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10107 == 10)
                                            {
                                                _10108 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10107 == 11)
                                            {
                                                _10108 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10107 == 12)
                                            {
                                                _10108 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10107 == 13)
                                            {
                                                _10108 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10107 == 14)
                                            {
                                                _10108 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10107 == 15)
                                            {
                                                _10108 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10108 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10110 = vec2(0.0);
                                        do
                                        {
                                            if (_10107 < 3)
                                            {
                                                _10110 = vec2(float(_10107) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10107 < 6)
                                            {
                                                _10110 = vec2((float(_10107 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10107 < 11)
                                            {
                                                _10110 = vec2((float(_10107 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10107 < 14)
                                            {
                                                _10110 = vec2((float(_10107 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10110 = vec2(float(_10107 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6118 = mix(_10108, _10110, vec2(_6011));
                                        float _6643 = _6118.x;
                                        float _6647 = _6118.y;
                                        highp vec2 _6673 = clamp(_5717 + (vec2((_6643 * _10104) - (_6647 * _10105), (_6643 * _10105) + (_6647 * _10104)) * _5724), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _6682 = _6673.y;
                                        highp vec2 _6683 = vec2((float(_9914) + _6673.x) * _6003, _6682);
                                        _6683.y = 1.0 - _6682;
                                        highp float _6695 = float(_5997 <= textureLod(shadow_map, _6683, 0.0).x);
                                        float mp_copy_6695 = _6695;
                                        _6129 = _10121 + mp_copy_6695;
                                    }
                                    _10126 = _10121 / float(_6101);
                                }
                                _10125 = _10126;
                            }
                            bool _6174 = _9914 == (_5627 - 1);
                            bool _6180 = false;
                            if (_6174)
                            {
                                _6180 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6180 = _6174;
                            }
                            float _10128 = 0.0;
                            if (_6180)
                            {
                                highp vec2 _6187 = vec2(frag_info.shadow_fade / _10076);
                                highp vec2 _6195 = smoothstep(vec2(0.0), _6187, _5717) * smoothstep(vec2(0.0), _6187, _5874);
                                _10128 = mix(1.0, _10125, _6195.x * _6195.y);
                            }
                            else
                            {
                                _10128 = _10125;
                            }
                            _10176 = _9918 + _5777;
                            _10173 = _9916 + (_5777 * _10128);
                        }
                        else
                        {
                            _10176 = _9918;
                            _10173 = _9916;
                        }
                        _10175 = _10176;
                        _10172 = _10173;
                    }
                    else
                    {
                        _10175 = _9918;
                        _10172 = _9916;
                    }
                    _10174 = _10175;
                    _10171 = _10172;
                }
                else
                {
                    _10174 = _9918;
                    _10171 = _9916;
                }
            }
            _9917 = _9918;
            _9915 = _9916;
        }
        else
        {
            _9917 = 0.0;
            _9915 = 0.0;
        }
        _9921 = mix(_9915 + (1.0 - _9917), 1.0, _9913);
    }
    else
    {
        _9921 = 1.0;
    }
    vec3 mp_copy_9922 = vec3(0.0);
    float _5120 = _5098 * _9921;
    bool _7210 = view_info.camera_forward.w > 0.5;
    highp vec3 _9922 = vec3(0.0);
    if (_7210)
    {
        _9922 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9922 = normalize(v_viewvector);
    }
    highp float _7254 = 0.0;
    mp_copy_9922 = _9922;
    vec3 _5129 = mix(frag_info.dielectric_f0.xyz, _5060, vec3(_4230));
    float _5133 = max(dot(_9863, _9922), 0.0);
    float _5137 = max(dot(_4096, _9922), 0.0);
    highp vec2 _9923 = vec2(0.0);
    do
    {
        _7254 = frag_info.punctual_dims.x;
        if (_7254 < 0.5)
        {
            _9923 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7266 = v_position - frag_info.camera_position.xyz;
            highp float _7281 = dot(_7266, frag_info.camera_forward.xyz);
            highp float _7287 = max(_7281, 9.9999997473787516355514526367188e-05);
            highp vec2 _7390 = (vec3(dot(_7266, frag_info.camera_right.xyz), dot(_7266, frag_info.camera_up.xyz), _7287).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7287, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7405 = float(int(((((clamp(floor((log2(max(_7281 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7390.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7390.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9923 = vec2(textureLod(punctual_index, vec2((mod(_7405, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7405 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9923 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5146 = int(_9923.x + 0.5);
    mediump int _5150 = int(_9923.y + 0.5);
    highp vec3 _9968 = vec3(0.0);
    _9968 = vec3(0.0);
    highp vec3 _10275 = vec3(0.0);
    for (int _9924 = 0; _9924 < _5150; _9968 = _10275, _9924++)
    {
        highp float hp_copy_10025 = 0.0;
        highp float _7438 = float(_5146 + _9924);
        highp float _7469 = (float(int(textureLod(punctual_index, vec2((mod(_7438, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7438 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7254;
        highp vec4 _7473 = textureLod(punctual_lights, vec2(0.0625, _7469), 0.0);
        highp vec4 _7490 = textureLod(punctual_lights, vec2(0.1875, _7469), 0.0);
        highp float _5168 = _7473.w;
        highp vec3 _5170 = _7490.xyz;
        vec3 _10011 = vec3(0.0);
        highp vec3 _10022 = vec3(0.0);
        float _10025 = 0.0;
        if (_5168 < 0.5)
        {
            _10025 = _9911;
            _10022 = _5170;
            _10011 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7469), 0.0).xyz);
        }
        else
        {
            highp vec3 _5178 = _7473.xyz - v_position;
            highp float _5181 = dot(_5178, _5178);
            highp float _5185 = inversesqrt(max(_5181, 9.9999999392252902907785028219223e-09));
            highp vec3 _5186 = _5178 * _5185;
            vec3 mp_copy_5186 = _5186;
            highp float _5188 = _7490.w;
            highp float _5193 = (_5181 * _5188) * _5188;
            highp float _5198 = clamp(1.0 - (_5193 * _5193), 0.0, 1.0);
            float mp_copy_5198 = _5198;
            if (_5198 <= 0.0)
            {
                _10275 = _9968;
                continue;
            }
            highp vec4 _7507 = textureLod(punctual_lights, vec2(0.4375, _7469), 0.0);
            highp float _5206 = _7507.w;
            float _10027 = 0.0;
            if (_5206 > 0.0)
            {
                highp float _5233 = (_9911 * _9911) + ((_5206 * 0.5) * _5185);
                float mp_copy_5233 = _5233;
                _10027 = sqrt(min(mp_copy_5233, 1.0));
            }
            else
            {
                _10027 = _9911;
            }
            highp vec3 _5240 = _5170 * ((mp_copy_5198 * mp_copy_5198) / max(pow(max(_5181, _5206 * _5206), _7507.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10023 = vec3(0.0);
            if (_5168 > 1.5)
            {
                highp vec4 _7524 = textureLod(punctual_lights, vec2(0.3125, _7469), 0.0);
                highp float _5259 = clamp((dot(normalize(_7524.xyz), -mp_copy_5186) * _7524.w) + _7507.x, 0.0, 1.0);
                float mp_copy_5259 = _5259;
                highp vec3 _5264 = _5240 * (mp_copy_5259 * mp_copy_5259);
                if (_5259 <= 0.0)
                {
                    _10275 = _9968;
                    continue;
                }
                bool _5270 = _5259 > 0.0;
                bool _5276 = false;
                if (_5270)
                {
                    _5276 = _7507.y > (-0.5);
                }
                else
                {
                    _5276 = _5270;
                }
                bool _5282 = false;
                if (_5276)
                {
                    _5282 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5282 = _5276;
                }
                highp vec3 _10024 = vec3(0.0);
                if (_5282)
                {
                    float _10002 = 0.0;
                    do
                    {
                        highp vec4 _7636 = mat4(textureLod(punctual_lights, vec2(0.5625, _7469), 0.0), textureLod(punctual_lights, vec2(0.6875, _7469), 0.0), textureLod(punctual_lights, vec2(0.8125, _7469), 0.0), textureLod(punctual_lights, vec2(0.9375, _7469), 0.0)) * vec4(v_position + (_4096 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _7638 = _7636.w;
                        if (_7638 <= 0.0)
                        {
                            _10002 = 1.0;
                            break;
                        }
                        highp vec3 _7647 = _7636.xyz / vec3(_7638);
                        highp vec2 _7652 = (_7647.xy * 0.5) + vec2(0.5);
                        highp float _7654 = _7652.x;
                        bool _7655 = _7654 < 0.0;
                        bool _7662 = false;
                        if (!_7655)
                        {
                            _7662 = _7654 > 1.0;
                        }
                        else
                        {
                            _7662 = _7655;
                        }
                        bool _7669 = false;
                        if (!_7662)
                        {
                            _7669 = _7652.y < 0.0;
                        }
                        else
                        {
                            _7669 = _7662;
                        }
                        bool _7676 = false;
                        if (!_7669)
                        {
                            _7676 = _7652.y > 1.0;
                        }
                        else
                        {
                            _7676 = _7669;
                        }
                        bool _7683 = false;
                        if (!_7676)
                        {
                            _7683 = _7647.z < 0.0;
                        }
                        else
                        {
                            _7683 = _7676;
                        }
                        bool _7690 = false;
                        if (!_7683)
                        {
                            _7690 = _7647.z > 1.0;
                        }
                        else
                        {
                            _7690 = _7683;
                        }
                        if (_7690)
                        {
                            _10002 = 1.0;
                            break;
                        }
                        highp float _7697 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _7702 = frag_info.shadow_cascade_count + float(int(_7507.y + 0.5));
                        highp float _7707 = _7647.z - frag_info.spot_shadow_params.y;
                        highp float _7718 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_7718 = _7718;
                        highp vec2 _7725 = vec2(cos(mp_copy_7718), sin(mp_copy_7718)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _7727 = _7725.x;
                        highp float _7729 = _7725.y;
                        highp vec2 _7737 = vec2(_7727 - _7729, _7727 + _7729) * 0.707106769084930419921875;
                        highp float _7930 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7654, 0.0, 1.0)) / _7697, 1.0 - clamp(_7652.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7930 = _7930;
                        highp vec2 _7745 = _7652 + _7725;
                        highp float _7952 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7745.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7745.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7952 = _7952;
                        highp vec2 _7753 = _7652 - _7725;
                        highp float _7974 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7753.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7753.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7974 = _7974;
                        highp vec2 _7766 = _7652 + vec2(-_7729, _7727);
                        highp float _7996 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7766.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7766.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7996 = _7996;
                        highp vec2 _7779 = _7652 + vec2(_7729, -_7727);
                        highp float _8018 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7779.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7779.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8018 = _8018;
                        float _7784 = (((mp_copy_7930 + mp_copy_7952) + mp_copy_7974) + mp_copy_7996) + mp_copy_8018;
                        if ((_7784 < 0.5) || (_7784 > 4.5))
                        {
                            _10002 = _7784 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _7796 = _7652 + _7737;
                        highp float _8040 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7796.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7796.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8040 = _8040;
                        highp vec2 _7803 = _7652 - _7737;
                        highp float _8062 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7803.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7803.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8062 = _8062;
                        highp float _7811 = _7737.y;
                        highp float _7814 = _7737.x;
                        highp vec2 _7816 = _7652 + vec2(-_7811, _7814);
                        highp float _8084 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7816.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7816.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8084 = _8084;
                        highp vec2 _7829 = _7652 + vec2(_7811, -_7814);
                        highp float _8106 = float(_7707 <= textureLod(shadow_map, vec2((_7702 + clamp(_7829.x, 0.0, 1.0)) / _7697, 1.0 - clamp(_7829.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8106 = _8106;
                        _10002 = (_7784 + (((mp_copy_8040 + mp_copy_8062) + mp_copy_8084) + mp_copy_8106)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10024 = _5264 * _10002;
                }
                else
                {
                    _10024 = _5264;
                }
                _10023 = _10024;
            }
            else
            {
                _10023 = _5240;
            }
            _10025 = _10027;
            _10022 = _10023;
            _10011 = _5186;
        }
        hp_copy_10025 = _10025;
        highp vec3 _10040 = vec3(0.0);
        highp vec3 _10041 = vec3(0.0);
        do
        {
            float _8189 = max(dot(_9863, _10011), 0.0);
            highp float hp_copy_8189 = _8189;
            if (_8189 <= 0.0)
            {
                _10041 = vec3(0.0);
                _10040 = vec3(0.0);
                break;
            }
            float _8195 = max(_5133, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8195 = _8195;
            vec3 _8198 = _10011 + mp_copy_9922;
            float _8201 = dot(_8198, _8198);
            vec3 _10038 = vec3(0.0);
            vec3 _10039 = vec3(0.0);
            if (_8201 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8209 = _8198 * inversesqrt(_8201);
                float _10037 = 0.0;
                do
                {
                    float _8266 = dot(_9863, _8209);
                    if (_8266 <= 0.0)
                    {
                        _10037 = 0.0;
                        break;
                    }
                    float _8273 = _10025 * _10025;
                    vec3 _8276 = cross(_9863, _8209);
                    float _8279 = _8266 * _8273;
                    float _8288 = _8273 / (dot(_8276, _8276) + (_8279 * _8279));
                    _10037 = min((_8288 * _8288) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8326 = _5129 + ((vec3(1.0) - _5129) * pow(clamp(1.0 - max(dot(_8209, _9922), 0.0), 0.0, 1.0), 5.0));
                _10039 = (_8326 * min(_10037 * (0.5 / max(mix((2.0 * hp_copy_8189) * _8195, hp_copy_8189 + hp_copy_8195, hp_copy_10025 * hp_copy_10025), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10038 = _8326;
            }
            else
            {
                _10039 = vec3(0.0);
                _10038 = _5129;
            }
            _10041 = (_10039 * _10022) * _8189;
            _10040 = (((((vec3(1.0) - _10038) * (1.0 - _4230)) * _5060) * 0.3183098733425140380859375) * _10022) * _8189;
            break;
        } while(false);
        _10275 = _9968 + (_10040 + _10041);
    }
    bool _8550 = false;
    highp vec3 hp_copy_9925 = vec3(0.0);
    mat3 _5337 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5345 = _5337 * vec3(_9863.x, _9863.y, _9863.z);
    vec3 _5348 = _5337 * reflect(-mp_copy_9922, _9863);
    float _8369 = _5345.y;
    float _8376 = _5345.z;
    float _8383 = _5345.x;
    float _8391 = 1.09254801273345947265625 * _8383;
    vec3 _5351 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8369))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8376))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8383))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8391 * _8369))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8369) * _8376))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8376) * _8376) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8391 * _8376))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8383 * _8383) - (_8369 * _8369)))), vec3(0.0));
    highp vec3 hp_copy_5351 = _5351;
    vec3 _9925 = vec3(0.0);
    do
    {
        _8550 = radiance_layout_info.mip_layout > 0.5;
        if (_8550)
        {
            vec2 _8629 = vec2(atan(_5348.z, _5348.x), asin(clamp(_5348.y, -1.0, 1.0)));
            highp vec2 hp_copy_8629 = _8629;
            _9925 = textureLod(prefiltered_radiance, (hp_copy_8629 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9911, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8648 = vec2(atan(_5348.z, _5348.x), asin(clamp(_5348.y, -1.0, 1.0)));
        highp vec2 hp_copy_8648 = _8648;
        highp vec2 _8653 = (hp_copy_8648 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8560 = clamp(_8653.y, 0.00390625, 0.99609375);
        float _8564 = clamp(_9911, 0.0, 1.0) * 7.0;
        float _8566 = floor(_8564);
        highp float _8585 = _8653.x;
        _9925 = mix(textureLod(prefiltered_radiance, vec2(_8585, (_8566 + _8560) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8585, (min(_8566 + 1.0, 7.0) + _8560) * 0.125), 0.0).xyz, vec3(_8564 - _8566));
        break;
    } while(false);
    hp_copy_9925 = _9925;
    highp vec3 _9931 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9926 = vec3(0.0);
        vec3 _9926 = vec3(0.0);
        do
        {
            if (_8550)
            {
                vec2 _8758 = vec2(atan(_5348.z, _5348.x), asin(clamp(_5348.y, -1.0, 1.0)));
                highp vec2 hp_copy_8758 = _8758;
                _9926 = textureLod(prefiltered_radiance_b, (hp_copy_8758 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9911, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8777 = vec2(atan(_5348.z, _5348.x), asin(clamp(_5348.y, -1.0, 1.0)));
            highp vec2 hp_copy_8777 = _8777;
            highp vec2 _8782 = (hp_copy_8777 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8689 = clamp(_8782.y, 0.00390625, 0.99609375);
            float _8693 = clamp(_9911, 0.0, 1.0) * 7.0;
            float _8695 = floor(_8693);
            highp float _8714 = _8782.x;
            _9926 = mix(textureLod(prefiltered_radiance_b, vec2(_8714, (_8695 + _8689) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_8714, (min(_8695 + 1.0, 7.0) + _8689) * 0.125), 0.0).xyz, vec3(_8693 - _8695));
            break;
        } while(false);
        hp_copy_9926 = _9926;
        _9931 = hp_copy_9925 + hp_copy_9926;
    }
    else
    {
        _9931 = _9925;
    }
    float _5366 = frag_info.environment_intensity;
    highp float hp_copy_5366 = _5366;
    vec2 _5379 = clamp(vec2(_5137, _9911), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5381 = texture(brdf_lut, vec2(_5379.x * 0.3333333432674407958984375, _5379.y));
    float _5385 = _5381.x;
    float _5388 = _5381.y;
    vec3 _5390 = ((_5129 + ((max(vec3(1.0 - _9911), _5129) - _5129) * pow(clamp(1.0 - _5137, 0.0, 1.0), 5.0))) * _5385) + vec3(_5388);
    float _5396 = 1.0 - (_5385 + _5388);
    vec3 _5400 = vec3(1.0) - _5129;
    vec3 _5403 = _5129 + (_5400 * vec3(0.0476190485060214996337890625));
    vec3 _5414 = ((_5390 * _5396) * _5403) / (vec3(1.0) - (_5403 * _5396));
    float _5417 = 1.0 - _4230;
    float _9945 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9945 = clamp((pow(_5133 + _9940, exp2(((-16.0) * _9911) - 1.0)) - 1.0) + _9940, 0.0, 1.0);
    }
    else
    {
        _9945 = _9940;
    }
    highp vec3 _9978 = vec3(0.0);
    if (_5085)
    {
        highp vec3 _9962 = vec3(0.0);
        highp vec3 _9963 = vec3(0.0);
        do
        {
            float _8871 = max(dot(_9863, _9954), 0.0);
            highp float hp_copy_8871 = _8871;
            if (_8871 <= 0.0)
            {
                _9963 = vec3(0.0);
                _9962 = vec3(0.0);
                break;
            }
            float _8877 = max(_5133, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8877 = _8877;
            vec3 _8880 = _9954 + mp_copy_9922;
            float _8883 = dot(_8880, _8880);
            vec3 _9960 = vec3(0.0);
            vec3 _9961 = vec3(0.0);
            if (_8883 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8891 = _8880 * inversesqrt(_8883);
                float _9959 = 0.0;
                do
                {
                    float _8948 = dot(_9863, _8891);
                    if (_8948 <= 0.0)
                    {
                        _9959 = 0.0;
                        break;
                    }
                    float _8955 = _9911 * _9911;
                    vec3 _8958 = cross(_9863, _8891);
                    float _8961 = _8948 * _8955;
                    float _8970 = _8955 / (dot(_8958, _8958) + (_8961 * _8961));
                    _9959 = min((_8970 * _8970) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9008 = _5129 + (_5400 * pow(clamp(1.0 - max(dot(_8891, _9922), 0.0), 0.0, 1.0), 5.0));
                _9961 = (_9008 * min(_9959 * (0.5 / max(mix((2.0 * hp_copy_8871) * _8877, hp_copy_8871 + hp_copy_8877, hp_copy_9911 * hp_copy_9911), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9960 = _9008;
            }
            else
            {
                _9961 = vec3(0.0);
                _9960 = _5129;
            }
            _9963 = (_9961 * frag_info.directional_light_color.xyz) * _8871;
            _9962 = (((((vec3(1.0) - _9960) * _5417) * _5060) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8871;
            break;
        } while(false);
        _9978 = _9968 + ((_9962 + _9963) * _5120);
    }
    else
    {
        _9978 = _9968;
    }
    bool _5508 = _FogInfo.params0.y > 0.5;
    bool _5514 = false;
    if (_5508)
    {
        _5514 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5514 = _5508;
    }
    highp vec3 _9981 = vec3(0.0);
    if (_5514)
    {
        vec3 mp_copy_9979 = vec3(0.0);
        highp vec3 _9979 = vec3(0.0);
        if (_7210)
        {
            _9979 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9979 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9980 = vec3(0.0);
        mp_copy_9979 = _9979;
        vec3 _5519 = _5337 * (-mp_copy_9979);
        vec3 _9980 = vec3(0.0);
        do
        {
            if (_8550)
            {
                vec2 _9130 = vec2(atan(_5519.z, _5519.x), asin(clamp(_5519.y, -1.0, 1.0)));
                highp vec2 hp_copy_9130 = _9130;
                _9980 = textureLod(prefiltered_radiance, (hp_copy_9130 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9149 = vec2(atan(_5519.z, _5519.x), asin(clamp(_5519.y, -1.0, 1.0)));
            highp vec2 hp_copy_9149 = _9149;
            highp vec2 _9154 = (hp_copy_9149 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9061 = clamp(_9154.y, 0.00390625, 0.99609375);
            float _9067 = floor(0.0);
            highp float _9086 = _9154.x;
            _9980 = mix(textureLod(prefiltered_radiance, vec2(_9086, (_9067 + _9061) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9086, (min(_9067 + 1.0, 7.0) + _9061) * 0.125), 0.0).xyz, vec3(-_9067));
            break;
        } while(false);
        hp_copy_9980 = _9980;
        _9981 = hp_copy_9980 * hp_copy_5366;
    }
    else
    {
        _9981 = _FogInfo.color.xyz;
    }
    highp vec4 _5534 = vec4(min(((((((_5414 + ((_5060 * _5417) * ((vec3(1.0) - _5390) - _5414))) * (hp_copy_5351 * hp_copy_5366)) * vec3(_4264)) + (((_5390 * (_9931 * _5366)) * 1.0) * _9945)) * mix(1.0, _5120, frag_info.radiance_blend.y)) + (_9978 * mix(1.0, _9940, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9886, vec3(65504.0)), 1.0) * _10322;
    highp vec4 _9996 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9996 = _5534;
            break;
        }
        int _9198 = int(_FogInfo.params0.x + 0.5);
        if (_9198 == 0)
        {
            _9996 = _5534;
            break;
        }
        highp float _9983 = 0.0;
        if (_7210)
        {
            _9983 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9983 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9983 > _FogInfo.params1.w))
        {
            _9996 = _5534;
            break;
        }
        float _9987 = 0.0;
        if (_9198 == 1)
        {
            _9987 = clamp((_9983 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9988 = 0.0;
            if (_9198 == 2)
            {
                highp float _9986 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9984 = vec3(0.0);
                    if (_7210)
                    {
                        _9984 = v_position - (view_info.camera_forward.xyz * _9983);
                    }
                    else
                    {
                        _9984 = v_position + v_viewvector;
                    }
                    highp float _9289 = -_FogInfo.params2.y;
                    highp float _9296 = _FogInfo.params1.x * exp(_9289 * (_9984.y - _FogInfo.params2.x));
                    highp float _9313 = _FogInfo.params2.y * (v_position.y - _9984.y);
                    highp float _9985 = 0.0;
                    if (abs(_9313) > 0.00124999997206032276153564453125)
                    {
                        _9985 = (_9296 - (_FogInfo.params1.x * exp(_9289 * (v_position.y - _FogInfo.params2.x)))) / _9313;
                    }
                    else
                    {
                        _9985 = _9296;
                    }
                    _9986 = _9985 * max(_9983 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9986 = _FogInfo.params1.x * max(_9983 - _FogInfo.params1.y, 0.0);
                }
                _9988 = 1.0 - exp(-_9986);
            }
            else
            {
                highp float _9251 = _FogInfo.params1.x * max(_9983 - _FogInfo.params1.y, 0.0);
                _9988 = 1.0 - exp((-_9251) * _9251);
            }
            _9987 = _9988;
        }
        highp float _9353 = min(_9987, _FogInfo.params0.z);
        if (_9353 <= 0.0)
        {
            _9996 = _5534;
            break;
        }
        highp vec3 _9366 = mix(_FogInfo.color.xyz, _9981, vec3(_FogInfo.params0.w));
        bool _9369 = _FogInfo.sun.w > 0.5;
        bool _9375 = false;
        if (_9369)
        {
            _9375 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _9375 = _9369;
        }
        vec3 _9992 = vec3(0.0);
        if (_9375)
        {
            vec3 mp_copy_9989 = vec3(0.0);
            highp vec3 _9989 = vec3(0.0);
            if (_7210)
            {
                _9989 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9989 = normalize(v_viewvector);
            }
            mp_copy_9989 = _9989;
            highp float _9391 = pow(max(dot(-mp_copy_9989, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_9391 = _9391;
            _9992 = _9366 + ((_FogInfo.sun.xyz * mp_copy_9391) * _FogInfo.params2.z);
        }
        else
        {
            _9992 = _9366;
        }
        highp float _9404 = _5534.w;
        float mp_copy_9404 = _9404;
        _9996 = vec4(mix(_5534.xyz, _9992 * mp_copy_9404, vec3(_9353)), _9404);
        break;
    } while(false);
    vec4 _9998 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9998 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9998 = _9996;
        break;
    } while(false);
    frag_color = _9998;
    float _9999 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9999 = 1.0;
    }
    else
    {
        _9999 = abs(frag_info.fade);
    }
    frag_color *= _9999;
}

