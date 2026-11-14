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
    highp float _4508 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4508 = _4508;
    vec3 _4512 = normalize(v_normal) * mp_copy_4508;
    vec4 _4554 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4557 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _10742 = vec2(0.0);
    if (_4557)
    {
        highp vec2 _10741 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _10741 = v_texture_coords_1;
        }
        else
        {
            _10741 = v_texture_coords;
        }
        highp vec2 _4760 = _10741 * texture_transforms.base_color_transform.zw;
        highp float _4766 = _4760.x;
        highp float _4771 = _4760.y;
        _10742 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4766) + (texture_transforms.base_color_rotation.y * _4771), ((-texture_transforms.base_color_rotation.y) * _4766) + (texture_transforms.base_color_rotation.x * _4771));
    }
    else
    {
        _10742 = v_texture_coords;
    }
    vec4 _4571 = texture(base_color_texture, _10742);
    vec3 _4573 = _4571.xyz;
    float _11529 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4571.w * _4554.w) * frag_info.color.w);
    vec3 _10757 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _10745 = vec2(0.0);
        if (_4557)
        {
            highp vec2 _10744 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _10744 = v_texture_coords_1;
            }
            else
            {
                _10744 = v_texture_coords;
            }
            highp vec2 _4855 = _10744 * texture_transforms.normal_transform.zw;
            highp float _4861 = _4855.x;
            highp float _4866 = _4855.y;
            _10745 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4861) + (texture_transforms.normal_rotation.y * _4866), ((-texture_transforms.normal_rotation.y) * _4861) + (texture_transforms.normal_rotation.x * _4866));
        }
        else
        {
            _10745 = v_texture_coords;
        }
        vec3 _4911 = ((texture(normal_texture, _10745).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4915 = _4911.xy * vec2(frag_info.normal_scale);
        vec3 _10452 = _4911;
        _10452.x = _4915.x;
        _10452.y = _4915.y;
        highp vec3 _4921 = -v_viewvector;
        highp vec3 _5011 = dFdx(_4921);
        highp vec3 _5013 = dFdy(_4921);
        highp vec2 _5015 = dFdx(_10745);
        highp vec2 _5017 = dFdy(_10745);
        bvec2 _11531 = bvec2(length(_5015) == 0.0);
        highp vec2 _11532 = vec2(_11531.x ? vec2(1.0, 0.0).x : _5015.x, _11531.y ? vec2(1.0, 0.0).y : _5015.y);
        bvec2 _11533 = bvec2(length(_5017) == 0.0);
        highp vec2 _11534 = vec2(_11533.x ? vec2(0.0, 1.0).x : _5017.x, _11533.y ? vec2(0.0, 1.0).y : _5017.y);
        highp vec3 _5030 = cross(_5013, _4512);
        highp vec3 _5033 = cross(_4512, _5011);
        highp float _5058 = (dot(cross(_5011, _5013), _4512) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _5061 = ((_5030 * _11532.x) + (_5033 * _11534.x)) * _5058;
        highp float _10752 = 0.0;
        if (gl_FrontFacing)
        {
            _10752 = -_5058;
        }
        else
        {
            _10752 = _5058;
        }
        highp vec3 _5071 = ((_5030 * _11532.y) + (_5033 * _11534.y)) * _10752;
        highp float _5080 = inversesqrt(max(max(dot(_5061, _5061), dot(_5071, _5071)), 9.9999996826552253889678874634872e-21));
        vec3 _4952 = v_tangent.xyz - (_4512 * dot(_4512, v_tangent.xyz));
        highp float _4955 = dot(_4952, _4952);
        bool _4957 = _4955 > 1.0000000133514319600180897396058e-10;
        bool _4964 = false;
        if (_4957)
        {
            _4964 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4964 = _4957;
        }
        mat3 _10755 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4964)
        {
            highp vec3 _4969 = _4952 * inversesqrt(_4955);
            _10755 = mat3(_4969, normalize(cross(_4512, _4969)) * sign(v_tangent.w), _4512);
        }
        else
        {
            _10755 = mat3(_5061 * _5080, _5071 * _5080, _4512);
        }
        _10757 = normalize(_10755 * _10452);
    }
    else
    {
        _10757 = _4512;
    }
    highp vec2 _10759 = vec2(0.0);
    if (_4557)
    {
        highp vec2 _10758 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _10758 = v_texture_coords_1;
        }
        else
        {
            _10758 = v_texture_coords;
        }
        highp vec2 _5148 = _10758 * texture_transforms.metallic_roughness_transform.zw;
        highp float _5154 = _5148.x;
        highp float _5159 = _5148.y;
        _10759 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _5154) + (texture_transforms.metallic_roughness_rotation.y * _5159), ((-texture_transforms.metallic_roughness_rotation.y) * _5154) + (texture_transforms.metallic_roughness_rotation.x * _5159));
    }
    else
    {
        _10759 = v_texture_coords;
    }
    vec4 _4640 = texture(metallic_roughness_texture, _10759);
    float _4646 = clamp(_4640.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4653 = clamp(_4640.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _10761 = vec2(0.0);
    if (_4557)
    {
        highp vec2 _10760 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _10760 = v_texture_coords_1;
        }
        else
        {
            _10760 = v_texture_coords;
        }
        highp vec2 _5219 = _10760 * texture_transforms.occlusion_transform.zw;
        highp float _5225 = _5219.x;
        highp float _5230 = _5219.y;
        _10761 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _5225) + (texture_transforms.occlusion_rotation.y * _5230), ((-texture_transforms.occlusion_rotation.y) * _5225) + (texture_transforms.occlusion_rotation.x * _5230));
    }
    else
    {
        _10761 = v_texture_coords;
    }
    float _10762 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _10762 = texture(occlusion_texture, _10761).x;
    }
    else
    {
        _10762 = 1.0;
    }
    float _4680 = 1.0 - ((1.0 - _10762) * frag_info.occlusion_strength);
    highp vec2 _10764 = vec2(0.0);
    if (_4557)
    {
        highp vec2 _10763 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _10763 = v_texture_coords_1;
        }
        else
        {
            _10763 = v_texture_coords;
        }
        highp vec2 _5290 = _10763 * texture_transforms.emissive_transform.zw;
        highp float _5296 = _5290.x;
        highp float _5301 = _5290.y;
        _10764 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5296) + (texture_transforms.emissive_rotation.y * _5301), ((-texture_transforms.emissive_rotation.y) * _5296) + (texture_transforms.emissive_rotation.x * _5301));
    }
    else
    {
        _10764 = v_texture_coords;
    }
    vec3 _4699 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _10780 = vec3(0.0);
    if (dot(abs(_4699), vec3(1.0)) > 0.0)
    {
        vec3 _4708 = texture(emissive_texture, _10764).xyz;
        _10780 = mix(_4708 * vec3(0.077399380505084991455078125), pow((_4708 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4708)) * _4699;
    }
    else
    {
        _10780 = vec3(0.0);
    }
    highp float hp_copy_10805 = 0.0;
    vec3 _5486 = vec4((mix(_4573 * vec3(0.077399380505084991455078125), pow((_4573 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4573)) * _4554.xyz) * frag_info.color.xyz, _11529).xyz;
    vec3 _6082 = dFdx(_10757);
    vec3 _6084 = dFdy(_10757);
    float _10805 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10805 = sqrt(clamp((_4653 * _4653) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_6082, _6082), dot(_6084, _6084))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10805 = _4653;
    }
    hp_copy_10805 = _10805;
    vec4 _10828 = vec4(0.0);
    float _10846 = 0.0;
    vec3 _10861 = vec3(0.0);
    float _10888 = 0.0;
    vec3 _10908 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _5513 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _10806 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _10806 = _5513.w;
        }
        else
        {
            _10806 = _5513.x;
        }
        float _5526 = min(_4680, _10806);
        bool _5529 = frag_info.ssao_lighting.z > 0.5;
        bool _5535 = false;
        if (_5529)
        {
            _5535 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _5535 = _5529;
        }
        vec3 _10862 = vec3(0.0);
        if (_5535)
        {
            vec2 _6122 = (_5513.zw * 2.0) - vec2(1.0);
            float _6124 = _6122.x;
            float _6126 = _6122.y;
            float _6134 = (1.0 - abs(_6124)) - abs(_6126);
            vec3 _6135 = vec3(_6124, _6126, _6134);
            vec3 _10809 = vec3(0.0);
            if (_6134 < 0.0)
            {
                vec2 _6148 = (vec2(1.0) - abs(_6135.yx)) * vec2((_6124 >= 0.0) ? 1.0 : (-1.0), (_6126 >= 0.0) ? 1.0 : (-1.0));
                vec3 _10501 = _6135;
                _10501.x = _6148.x;
                _10501.y = _6148.y;
                _10809 = _10501;
            }
            else
            {
                _10809 = _6135;
            }
            vec3 _6156 = -normalize(_10809);
            _10862 = normalize(((frag_info.camera_right.xyz * _6156.x) + (frag_info.camera_up.xyz * _6156.y)) + (frag_info.camera_forward.xyz * _6156.z));
        }
        else
        {
            _10862 = vec3(0.0);
        }
        vec3 _5563 = vec3(_5526);
        _10908 = mix(_5563, max(_5563, ((((((_5486 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _5526) + ((_5486 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _5526) + ((_5486 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _5526), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _10888 = _5526;
        _10861 = _10862;
        _10846 = float(_5535);
        _10828 = _5513;
    }
    else
    {
        _10908 = vec3(_4680);
        _10888 = _4680;
        _10861 = vec3(0.0);
        _10846 = 0.0;
        _10828 = vec4(1.0);
    }
    bool _5575 = frag_info.has_directional_light > 0.5;
    float _10813 = 0.0;
    vec3 _10936 = vec3(0.0);
    if (_5575)
    {
        highp vec3 _5581 = -normalize(frag_info.directional_light_direction.xyz);
        _10936 = _5581;
        _10813 = dot(_4512, _5581);
    }
    else
    {
        _10936 = vec3(0.0);
        _10813 = 0.0;
    }
    float _5588 = clamp(_10813 * 6.666666507720947265625, 0.0, 1.0);
    bool _5597 = false;
    if (_5575)
    {
        _5597 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5597 = _5575;
    }
    float _10822 = 0.0;
    if (_5597 && (_5588 > 0.0))
    {
        int _6247 = int(frag_info.shadow_cascade_count);
        float _6442 = max(dot(_4512, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6445 = _6442 * _6442;
        highp vec3 _6465 = v_position + (_4512 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6445, 0.0)) / _6445, 8.0))));
        highp float _6253 = frag_info.directional_light_color.w * 0.5;
        float _6255 = frag_info.dielectric_f0.w;
        highp float hp_copy_6255 = _6255;
        float _10814 = 0.0;
        if (_6255 > 0.0)
        {
            _10814 = smoothstep(_6255 - max(frag_info.shadow_fade, hp_copy_6255 * 0.100000001490116119384765625), _6255, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10814 = 0.0;
        }
        float _10816 = 0.0;
        float _10818 = 0.0;
        if (_10814 < 1.0)
        {
            float _10817 = 0.0;
            float _10819 = 0.0;
            _10819 = 0.0;
            _10817 = 0.0;
            float _11192 = 0.0;
            float _11195 = 0.0;
            for (int _10815 = 0; _10815 < _6247; _10819 = _11195, _10817 = _11192, _10815++)
            {
                if (_10819 < 1.0)
                {
                    highp vec4 _6287 = vec4(_6465, 1.0);
                    highp vec4 _11064 = vec4(0.0);
                    highp float _11067 = 0.0;
                    if (_10815 == 0)
                    {
                        _11067 = frag_info.cascade_box_sizes.x;
                        _11064 = frag_info.light_space_matrix[0] * _6287;
                    }
                    else
                    {
                        highp vec4 _11065 = vec4(0.0);
                        highp float _11068 = 0.0;
                        if (_10815 == 1)
                        {
                            _11068 = frag_info.cascade_box_sizes.y;
                            _11065 = frag_info.light_space_matrix[1] * _6287;
                        }
                        else
                        {
                            highp vec4 _11066 = vec4(0.0);
                            highp float _11069 = 0.0;
                            if (_10815 == 2)
                            {
                                _11069 = frag_info.cascade_box_sizes.z;
                                _11066 = frag_info.light_space_matrix[2] * _6287;
                            }
                            else
                            {
                                _11069 = frag_info.cascade_box_sizes.w;
                                _11066 = frag_info.light_space_matrix[3] * _6287;
                            }
                            _11068 = _11069;
                            _11065 = _11066;
                        }
                        _11067 = _11068;
                        _11064 = _11065;
                    }
                    highp vec3 _6332 = _11064.xyz / vec3(_11064.w);
                    highp vec2 _6335 = _6332.xy * 0.5;
                    highp vec2 _6337 = _6335 + vec2(0.5);
                    highp float _6344 = max(frag_info.shadow_softness / _11067, frag_info.shadow_texel_size);
                    highp float _6346 = _6337.x;
                    bool _6348 = _6346 < _6344;
                    bool _6357 = false;
                    if (!_6348)
                    {
                        _6357 = _6346 > (1.0 - _6344);
                    }
                    else
                    {
                        _6357 = _6348;
                    }
                    bool _6365 = false;
                    if (!_6357)
                    {
                        _6365 = _6337.y < _6344;
                    }
                    else
                    {
                        _6365 = _6357;
                    }
                    bool _6374 = false;
                    if (!_6365)
                    {
                        _6374 = _6337.y > (1.0 - _6344);
                    }
                    else
                    {
                        _6374 = _6365;
                    }
                    bool _6381 = false;
                    if (!_6374)
                    {
                        _6381 = _6332.z < 0.0;
                    }
                    else
                    {
                        _6381 = _6374;
                    }
                    bool _6388 = false;
                    if (!_6381)
                    {
                        _6388 = _6332.z > 1.0;
                    }
                    else
                    {
                        _6388 = _6381;
                    }
                    float _11193 = 0.0;
                    float _11196 = 0.0;
                    if (!_6388)
                    {
                        highp vec2 _6481 = vec2(_6344);
                        highp vec2 _6486 = vec2(_6344 + max(_6253, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6494 = vec2(0.5) - _6335;
                        highp vec2 _6496 = smoothstep(_6481, _6486, _6337) * smoothstep(_6481, _6486, _6494);
                        float _11070 = 0.0;
                        if (_6253 > 0.0)
                        {
                            _11070 = _6496.x * _6496.y;
                        }
                        else
                        {
                            _11070 = 1.0;
                        }
                        float _6397 = min(_11070, 1.0 - _10819);
                        float _11194 = 0.0;
                        float _11197 = 0.0;
                        if (_6397 > 0.0)
                        {
                            highp float _6635 = _6332.z - (frag_info.shadow_bias / (7.0 * _11067));
                            highp float _6641 = 1.0 / (float(_6247) + frag_info.spot_shadow_params.x);
                            highp float _6643 = frag_info.directional_light_direction.w;
                            float mp_copy_6643 = _6643;
                            float _6649 = step(0.5, mp_copy_6643) * (1.0 - step(1.5, mp_copy_6643));
                            float _11100 = 0.0;
                            float _11104 = 0.0;
                            if (_6649 < 0.5)
                            {
                                highp float _6660 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6660 = _6660;
                                _11104 = sin(mp_copy_6660);
                                _11100 = cos(mp_copy_6660);
                            }
                            else
                            {
                                _11104 = 0.0;
                                _11100 = 1.0;
                            }
                            highp float _11107 = 0.0;
                            if ((_6643 > 1.5) && (_6643 < 2.5))
                            {
                                highp float _6684 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6689 = max(_6684 * _6635, frag_info.shadow_texel_size);
                                float _11096 = 0.0;
                                highp float _11097 = 0.0;
                                _11097 = 0.0;
                                _11096 = 0.0;
                                highp float _6711 = 0.0;
                                float _6714 = 0.0;
                                for (int _11095 = 0; _11095 < 9; _11097 = _6711, _11096 = _6714, _11095++)
                                {
                                    vec2 _11186 = vec2(0.0);
                                    do
                                    {
                                        if (_11095 == 0)
                                        {
                                            _11186 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_11095 == 1)
                                        {
                                            _11186 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_11095 == 2)
                                        {
                                            _11186 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_11095 == 3)
                                        {
                                            _11186 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_11095 == 4)
                                        {
                                            _11186 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_11095 == 5)
                                        {
                                            _11186 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_11095 == 6)
                                        {
                                            _11186 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_11095 == 7)
                                        {
                                            _11186 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_11095 == 8)
                                        {
                                            _11186 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_11095 == 9)
                                        {
                                            _11186 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_11095 == 10)
                                        {
                                            _11186 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_11095 == 11)
                                        {
                                            _11186 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_11095 == 12)
                                        {
                                            _11186 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_11095 == 13)
                                        {
                                            _11186 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_11095 == 14)
                                        {
                                            _11186 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_11095 == 15)
                                        {
                                            _11186 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _11186 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _7018 = clamp(_6337 + (vec2((_11186.x * _11100) - (_11186.y * _11104), (_11186.x * _11104) + (_11186.y * _11100)) * _6689), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _7027 = _7018.y;
                                    highp vec2 _7028 = vec2((float(_10815) + _7018.x) * _6641, _7027);
                                    _7028.y = 1.0 - _7027;
                                    highp vec4 _7035 = textureLod(shadow_map, _7028, 0.0);
                                    highp float _7036 = _7035.x;
                                    highp float _6706 = step(_7036, _6635);
                                    float mp_copy_6706 = _6706;
                                    _6711 = _11097 + (_7036 * _6706);
                                    _6714 = _11096 + mp_copy_6706;
                                }
                                highp float _11098 = 0.0;
                                if (_11096 > 0.0)
                                {
                                    _11098 = _11097 / _11096;
                                }
                                else
                                {
                                    _11098 = _6635;
                                }
                                _11107 = clamp(_6684 * max(_6635 - _11098, 0.0), frag_info.shadow_texel_size, _6344);
                            }
                            else
                            {
                                _11107 = _6344;
                            }
                            bool _6745 = _6643 > 2.5;
                            bool _11108 = false;
                            float _11133 = 0.0;
                            if ((_6643 < 1.5) || _6745)
                            {
                                highp vec2 _7069 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _7073 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _7074 = clamp(_6337, _7069, _7073);
                                highp float _7076 = float(_10815);
                                highp float _7083 = _7074.y;
                                highp vec2 _7084 = vec2((_7076 + _7074.x) * _6641, _7083);
                                _7084.y = 1.0 - _7083;
                                highp float _7096 = float(_6635 <= textureLod(shadow_map, _7084, 0.0).x);
                                float mp_copy_7096 = _7096;
                                float _7106 = (-1.0) * _11100;
                                float _7110 = (-1.0) * _11104;
                                highp vec2 _7134 = clamp(_6337 + (vec2(_7106 - _7110, _7110 + _7106) * _11107), _7069, _7073);
                                highp float _7143 = _7134.y;
                                highp vec2 _7144 = vec2((_7076 + _7134.x) * _6641, _7143);
                                _7144.y = 1.0 - _7143;
                                highp float _7156 = float(_6635 <= textureLod(shadow_map, _7144, 0.0).x);
                                float mp_copy_7156 = _7156;
                                highp vec2 _7194 = clamp(_6337 + (vec2(_11100 - _7110, _11104 + _7106) * _11107), _7069, _7073);
                                highp float _7203 = _7194.y;
                                highp vec2 _7204 = vec2((_7076 + _7194.x) * _6641, _7203);
                                _7204.y = 1.0 - _7203;
                                highp float _7216 = float(_6635 <= textureLod(shadow_map, _7204, 0.0).x);
                                float mp_copy_7216 = _7216;
                                highp vec2 _7254 = clamp(_6337 + (vec2(_7106 - _11104, _7110 + _11100) * _11107), _7069, _7073);
                                highp float _7263 = _7254.y;
                                highp vec2 _7264 = vec2((_7076 + _7254.x) * _6641, _7263);
                                _7264.y = 1.0 - _7263;
                                highp float _7276 = float(_6635 <= textureLod(shadow_map, _7264, 0.0).x);
                                float mp_copy_7276 = _7276;
                                highp vec2 _7314 = clamp(_6337 + (vec2(_11100 - _11104, _11104 + _11100) * _11107), _7069, _7073);
                                highp float _7323 = _7314.y;
                                highp vec2 _7324 = vec2((_7076 + _7314.x) * _6641, _7323);
                                _7324.y = 1.0 - _7323;
                                highp float _7336 = float(_6635 <= textureLod(shadow_map, _7324, 0.0).x);
                                float mp_copy_7336 = _7336;
                                float _6791 = (((mp_copy_7096 + mp_copy_7156) + mp_copy_7216) + mp_copy_7276) + mp_copy_7336;
                                _11133 = _6791 * 0.20000000298023223876953125;
                                _11108 = (_6791 < 0.5) || (_6791 > 4.5);
                            }
                            else
                            {
                                _11133 = 0.0;
                                _11108 = false;
                            }
                            float _11131 = 0.0;
                            if (_11108)
                            {
                                _11131 = _11133;
                            }
                            else
                            {
                                float _11132 = 0.0;
                                if (_6745)
                                {
                                    highp vec2 _7555 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7559 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7560 = clamp(_6337 + (vec2(-0.707099974155426025390625) * _11107), _7555, _7559);
                                    highp vec2 _7571 = (vec2(_7560.x, 1.0 - _7560.y) / _7555) - vec2(0.5);
                                    highp vec2 _7573 = floor(_7571);
                                    highp vec2 _7576 = _7571 - _7573;
                                    highp vec2 _7581 = (_7573 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7583 = float(_10815);
                                    highp vec2 _7591 = vec2((_7583 + _7581.x) * _6641, _7581.y);
                                    highp float _7595 = frag_info.shadow_texel_size * _6641;
                                    highp vec2 _7598 = vec2(_7595, frag_info.shadow_texel_size);
                                    highp vec2 _7607 = vec2(_7595, 0.0);
                                    highp vec2 _7615 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7644 = _7576.x;
                                    highp float _7653 = mix(mix(float(_6635 <= textureLod(shadow_map, _7591, 0.0).x), float(_6635 <= textureLod(shadow_map, _7591 + _7607, 0.0).x), _7644), mix(float(_6635 <= textureLod(shadow_map, _7591 + _7615, 0.0).x), float(_6635 <= textureLod(shadow_map, _7591 + _7598, 0.0).x), _7644), _7576.y);
                                    float mp_copy_7653 = _7653;
                                    highp vec2 _7687 = clamp(_6337 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _11107), _7555, _7559);
                                    highp vec2 _7698 = (vec2(_7687.x, 1.0 - _7687.y) / _7555) - vec2(0.5);
                                    highp vec2 _7700 = floor(_7698);
                                    highp vec2 _7703 = _7698 - _7700;
                                    highp vec2 _7708 = (_7700 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7718 = vec2((_7583 + _7708.x) * _6641, _7708.y);
                                    highp float _7771 = _7703.x;
                                    highp float _7780 = mix(mix(float(_6635 <= textureLod(shadow_map, _7718, 0.0).x), float(_6635 <= textureLod(shadow_map, _7718 + _7607, 0.0).x), _7771), mix(float(_6635 <= textureLod(shadow_map, _7718 + _7615, 0.0).x), float(_6635 <= textureLod(shadow_map, _7718 + _7598, 0.0).x), _7771), _7703.y);
                                    float mp_copy_7780 = _7780;
                                    highp vec2 _7814 = clamp(_6337 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _11107), _7555, _7559);
                                    highp vec2 _7825 = (vec2(_7814.x, 1.0 - _7814.y) / _7555) - vec2(0.5);
                                    highp vec2 _7827 = floor(_7825);
                                    highp vec2 _7830 = _7825 - _7827;
                                    highp vec2 _7835 = (_7827 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7845 = vec2((_7583 + _7835.x) * _6641, _7835.y);
                                    highp float _7898 = _7830.x;
                                    highp float _7907 = mix(mix(float(_6635 <= textureLod(shadow_map, _7845, 0.0).x), float(_6635 <= textureLod(shadow_map, _7845 + _7607, 0.0).x), _7898), mix(float(_6635 <= textureLod(shadow_map, _7845 + _7615, 0.0).x), float(_6635 <= textureLod(shadow_map, _7845 + _7598, 0.0).x), _7898), _7830.y);
                                    float mp_copy_7907 = _7907;
                                    highp vec2 _7941 = clamp(_6337 + (vec2(0.707099974155426025390625) * _11107), _7555, _7559);
                                    highp vec2 _7952 = (vec2(_7941.x, 1.0 - _7941.y) / _7555) - vec2(0.5);
                                    highp vec2 _7954 = floor(_7952);
                                    highp vec2 _7957 = _7952 - _7954;
                                    highp vec2 _7962 = (_7954 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7972 = vec2((_7583 + _7962.x) * _6641, _7962.y);
                                    highp float _8025 = _7957.x;
                                    highp float _8034 = mix(mix(float(_6635 <= textureLod(shadow_map, _7972, 0.0).x), float(_6635 <= textureLod(shadow_map, _7972 + _7607, 0.0).x), _8025), mix(float(_6635 <= textureLod(shadow_map, _7972 + _7615, 0.0).x), float(_6635 <= textureLod(shadow_map, _7972 + _7598, 0.0).x), _8025), _7957.y);
                                    float mp_copy_8034 = _8034;
                                    _11132 = (((mp_copy_7653 + mp_copy_7780) + mp_copy_7907) + mp_copy_8034) * 0.25;
                                }
                                else
                                {
                                    int _6807 = (_6649 > 0.5) ? 17 : 16;
                                    float _11127 = 0.0;
                                    _11127 = 0.0;
                                    float _6835 = 0.0;
                                    for (int _11109 = 0; _11109 < 17; _11127 = _6835, _11109++)
                                    {
                                        if (_11109 >= _6807)
                                        {
                                            break;
                                        }
                                        vec2 _11110 = vec2(0.0);
                                        do
                                        {
                                            if (_11109 == 0)
                                            {
                                                _11110 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_11109 == 1)
                                            {
                                                _11110 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_11109 == 2)
                                            {
                                                _11110 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_11109 == 3)
                                            {
                                                _11110 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_11109 == 4)
                                            {
                                                _11110 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_11109 == 5)
                                            {
                                                _11110 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_11109 == 6)
                                            {
                                                _11110 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_11109 == 7)
                                            {
                                                _11110 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_11109 == 8)
                                            {
                                                _11110 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_11109 == 9)
                                            {
                                                _11110 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_11109 == 10)
                                            {
                                                _11110 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_11109 == 11)
                                            {
                                                _11110 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_11109 == 12)
                                            {
                                                _11110 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_11109 == 13)
                                            {
                                                _11110 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_11109 == 14)
                                            {
                                                _11110 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_11109 == 15)
                                            {
                                                _11110 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _11110 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _11112 = vec2(0.0);
                                        do
                                        {
                                            if (_11109 < 3)
                                            {
                                                _11112 = vec2(float(_11109) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_11109 < 6)
                                            {
                                                _11112 = vec2((float(_11109 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_11109 < 11)
                                            {
                                                _11112 = vec2((float(_11109 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_11109 < 14)
                                            {
                                                _11112 = vec2((float(_11109 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _11112 = vec2(float(_11109 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6824 = mix(_11110, _11112, vec2(_6649));
                                        float _7475 = _6824.x;
                                        float _7479 = _6824.y;
                                        highp vec2 _7505 = clamp(_6337 + (vec2((_7475 * _11100) - (_7479 * _11104), (_7475 * _11104) + (_7479 * _11100)) * _11107), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7514 = _7505.y;
                                        highp vec2 _7515 = vec2((float(_10815) + _7505.x) * _6641, _7514);
                                        _7515.y = 1.0 - _7514;
                                        highp float _7527 = float(_6635 <= textureLod(shadow_map, _7515, 0.0).x);
                                        float mp_copy_7527 = _7527;
                                        _6835 = _11127 + mp_copy_7527;
                                    }
                                    _11132 = _11127 / float(_6807);
                                }
                                _11131 = _11132;
                            }
                            bool _6880 = _10815 == (_6247 - 1);
                            bool _6886 = false;
                            if (_6880)
                            {
                                _6886 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6886 = _6880;
                            }
                            float _11134 = 0.0;
                            if (_6886)
                            {
                                highp vec2 _6893 = vec2(frag_info.shadow_fade / _11067);
                                highp vec2 _6901 = smoothstep(vec2(0.0), _6893, _6337) * smoothstep(vec2(0.0), _6893, _6494);
                                _11134 = mix(1.0, _11131, _6901.x * _6901.y);
                            }
                            else
                            {
                                _11134 = _11131;
                            }
                            _11197 = _10819 + _6397;
                            _11194 = _10817 + (_6397 * _11134);
                        }
                        else
                        {
                            _11197 = _10819;
                            _11194 = _10817;
                        }
                        _11196 = _11197;
                        _11193 = _11194;
                    }
                    else
                    {
                        _11196 = _10819;
                        _11193 = _10817;
                    }
                    _11195 = _11196;
                    _11192 = _11193;
                }
                else
                {
                    _11195 = _10819;
                    _11192 = _10817;
                }
            }
            _10818 = _10819;
            _10816 = _10817;
        }
        else
        {
            _10818 = 0.0;
            _10816 = 0.0;
        }
        _10822 = mix(_10816 + (1.0 - _10818), 1.0, _10814);
    }
    else
    {
        _10822 = 1.0;
    }
    bool _5610 = frag_info.ssao_lighting.w > 0.5;
    bool _5616 = false;
    if (_5610)
    {
        _5616 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _5616 = _5610;
    }
    float _10834 = 0.0;
    if (_5616)
    {
        _10834 = min(_10822, _10828.y);
    }
    else
    {
        _10834 = _10822;
    }
    vec3 mp_copy_10835 = vec3(0.0);
    float _5625 = _5588 * _10834;
    bool _8042 = view_info.camera_forward.w > 0.5;
    highp vec3 _10835 = vec3(0.0);
    if (_8042)
    {
        _10835 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10835 = normalize(v_viewvector);
    }
    highp float _8086 = 0.0;
    mp_copy_10835 = _10835;
    vec3 _5634 = mix(frag_info.dielectric_f0.xyz, _5486, vec3(_4646));
    float _5638 = max(dot(_10757, _10835), 0.0);
    float _5642 = max(dot(_4512, _10835), 0.0);
    vec3 _5646 = reflect(-mp_copy_10835, _10757);
    highp vec2 _10836 = vec2(0.0);
    do
    {
        _8086 = frag_info.punctual_dims.x;
        if (_8086 < 0.5)
        {
            _10836 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _8098 = v_position - frag_info.camera_position.xyz;
            highp float _8113 = dot(_8098, frag_info.camera_forward.xyz);
            highp float _8119 = max(_8113, 9.9999997473787516355514526367188e-05);
            highp vec2 _8222 = (vec3(dot(_8098, frag_info.camera_right.xyz), dot(_8098, frag_info.camera_up.xyz), _8119).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_8119, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _8237 = float(int(((((clamp(floor((log2(max(_8113 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_8222.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_8222.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10836 = vec2(textureLod(punctual_index, vec2((mod(_8237, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8237 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10836 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5651 = int(_10836.x + 0.5);
    mediump int _5655 = int(_10836.y + 0.5);
    highp vec3 _10952 = vec3(0.0);
    _10952 = vec3(0.0);
    highp vec3 _11476 = vec3(0.0);
    for (int _10837 = 0; _10837 < _5655; _10952 = _11476, _10837++)
    {
        highp float hp_copy_11016 = 0.0;
        highp float _8270 = float(_5651 + _10837);
        highp float _8301 = (float(int(textureLod(punctual_index, vec2((mod(_8270, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8270 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _8086;
        highp vec4 _8305 = textureLod(punctual_lights, vec2(0.0625, _8301), 0.0);
        highp vec4 _8322 = textureLod(punctual_lights, vec2(0.1875, _8301), 0.0);
        highp float _5673 = _8305.w;
        highp vec3 _5675 = _8322.xyz;
        vec3 _11002 = vec3(0.0);
        highp vec3 _11013 = vec3(0.0);
        float _11016 = 0.0;
        if (_5673 < 0.5)
        {
            _11016 = _10805;
            _11013 = _5675;
            _11002 = -normalize(textureLod(punctual_lights, vec2(0.3125, _8301), 0.0).xyz);
        }
        else
        {
            highp vec3 _5683 = _8305.xyz - v_position;
            highp float _5686 = dot(_5683, _5683);
            highp float _5690 = inversesqrt(max(_5686, 9.9999999392252902907785028219223e-09));
            highp vec3 _5691 = _5683 * _5690;
            vec3 mp_copy_5691 = _5691;
            highp float _5693 = _8322.w;
            highp float _5698 = (_5686 * _5693) * _5693;
            highp float _5703 = clamp(1.0 - (_5698 * _5698), 0.0, 1.0);
            float mp_copy_5703 = _5703;
            if (_5703 <= 0.0)
            {
                _11476 = _10952;
                continue;
            }
            highp vec4 _8339 = textureLod(punctual_lights, vec2(0.4375, _8301), 0.0);
            highp float _5711 = _8339.w;
            float _11018 = 0.0;
            if (_5711 > 0.0)
            {
                highp float _5738 = (_10805 * _10805) + ((_5711 * 0.5) * _5690);
                float mp_copy_5738 = _5738;
                _11018 = sqrt(min(mp_copy_5738, 1.0));
            }
            else
            {
                _11018 = _10805;
            }
            highp vec3 _5745 = _5675 * ((mp_copy_5703 * mp_copy_5703) / max(pow(max(_5686, _5711 * _5711), _8339.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _11014 = vec3(0.0);
            if (_5673 > 1.5)
            {
                highp vec4 _8356 = textureLod(punctual_lights, vec2(0.3125, _8301), 0.0);
                highp float _5764 = clamp((dot(normalize(_8356.xyz), -mp_copy_5691) * _8356.w) + _8339.x, 0.0, 1.0);
                float mp_copy_5764 = _5764;
                highp vec3 _5769 = _5745 * (mp_copy_5764 * mp_copy_5764);
                if (_5764 <= 0.0)
                {
                    _11476 = _10952;
                    continue;
                }
                bool _5775 = _5764 > 0.0;
                bool _5781 = false;
                if (_5775)
                {
                    _5781 = _8339.y > (-0.5);
                }
                else
                {
                    _5781 = _5775;
                }
                bool _5787 = false;
                if (_5781)
                {
                    _5787 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5787 = _5781;
                }
                highp vec3 _11015 = vec3(0.0);
                if (_5787)
                {
                    float _10993 = 0.0;
                    do
                    {
                        highp vec4 _8468 = mat4(textureLod(punctual_lights, vec2(0.5625, _8301), 0.0), textureLod(punctual_lights, vec2(0.6875, _8301), 0.0), textureLod(punctual_lights, vec2(0.8125, _8301), 0.0), textureLod(punctual_lights, vec2(0.9375, _8301), 0.0)) * vec4(v_position + (_4512 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8470 = _8468.w;
                        if (_8470 <= 0.0)
                        {
                            _10993 = 1.0;
                            break;
                        }
                        highp vec3 _8479 = _8468.xyz / vec3(_8470);
                        highp vec2 _8484 = (_8479.xy * 0.5) + vec2(0.5);
                        highp float _8486 = _8484.x;
                        bool _8487 = _8486 < 0.0;
                        bool _8494 = false;
                        if (!_8487)
                        {
                            _8494 = _8486 > 1.0;
                        }
                        else
                        {
                            _8494 = _8487;
                        }
                        bool _8501 = false;
                        if (!_8494)
                        {
                            _8501 = _8484.y < 0.0;
                        }
                        else
                        {
                            _8501 = _8494;
                        }
                        bool _8508 = false;
                        if (!_8501)
                        {
                            _8508 = _8484.y > 1.0;
                        }
                        else
                        {
                            _8508 = _8501;
                        }
                        bool _8515 = false;
                        if (!_8508)
                        {
                            _8515 = _8479.z < 0.0;
                        }
                        else
                        {
                            _8515 = _8508;
                        }
                        bool _8522 = false;
                        if (!_8515)
                        {
                            _8522 = _8479.z > 1.0;
                        }
                        else
                        {
                            _8522 = _8515;
                        }
                        if (_8522)
                        {
                            _10993 = 1.0;
                            break;
                        }
                        highp float _8529 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8534 = frag_info.shadow_cascade_count + float(int(_8339.y + 0.5));
                        highp float _8539 = _8479.z - frag_info.spot_shadow_params.y;
                        highp float _8550 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8550 = _8550;
                        highp vec2 _8557 = vec2(cos(mp_copy_8550), sin(mp_copy_8550)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8559 = _8557.x;
                        highp float _8561 = _8557.y;
                        highp vec2 _8569 = vec2(_8559 - _8561, _8559 + _8561) * 0.707106769084930419921875;
                        highp float _8762 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8486, 0.0, 1.0)) / _8529, 1.0 - clamp(_8484.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8762 = _8762;
                        highp vec2 _8577 = _8484 + _8557;
                        highp float _8784 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8577.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8577.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8784 = _8784;
                        highp vec2 _8585 = _8484 - _8557;
                        highp float _8806 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8585.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8585.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8806 = _8806;
                        highp vec2 _8598 = _8484 + vec2(-_8561, _8559);
                        highp float _8828 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8598.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8598.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8828 = _8828;
                        highp vec2 _8611 = _8484 + vec2(_8561, -_8559);
                        highp float _8850 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8611.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8611.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8850 = _8850;
                        float _8616 = (((mp_copy_8762 + mp_copy_8784) + mp_copy_8806) + mp_copy_8828) + mp_copy_8850;
                        if ((_8616 < 0.5) || (_8616 > 4.5))
                        {
                            _10993 = _8616 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8628 = _8484 + _8569;
                        highp float _8872 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8628.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8628.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8872 = _8872;
                        highp vec2 _8635 = _8484 - _8569;
                        highp float _8894 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8635.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8635.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8894 = _8894;
                        highp float _8643 = _8569.y;
                        highp float _8646 = _8569.x;
                        highp vec2 _8648 = _8484 + vec2(-_8643, _8646);
                        highp float _8916 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8648.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8648.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8916 = _8916;
                        highp vec2 _8661 = _8484 + vec2(_8643, -_8646);
                        highp float _8938 = float(_8539 <= textureLod(shadow_map, vec2((_8534 + clamp(_8661.x, 0.0, 1.0)) / _8529, 1.0 - clamp(_8661.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8938 = _8938;
                        _10993 = (_8616 + (((mp_copy_8872 + mp_copy_8894) + mp_copy_8916) + mp_copy_8938)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _11015 = _5769 * _10993;
                }
                else
                {
                    _11015 = _5769;
                }
                _11014 = _11015;
            }
            else
            {
                _11014 = _5745;
            }
            _11016 = _11018;
            _11013 = _11014;
            _11002 = _5691;
        }
        hp_copy_11016 = _11016;
        highp vec3 _11031 = vec3(0.0);
        highp vec3 _11032 = vec3(0.0);
        do
        {
            float _9021 = max(dot(_10757, _11002), 0.0);
            highp float hp_copy_9021 = _9021;
            if (_9021 <= 0.0)
            {
                _11032 = vec3(0.0);
                _11031 = vec3(0.0);
                break;
            }
            float _9027 = max(_5638, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9027 = _9027;
            vec3 _9030 = _11002 + mp_copy_10835;
            float _9033 = dot(_9030, _9030);
            vec3 _11029 = vec3(0.0);
            vec3 _11030 = vec3(0.0);
            if (_9033 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9041 = _9030 * inversesqrt(_9033);
                float _11028 = 0.0;
                do
                {
                    float _9098 = dot(_10757, _9041);
                    if (_9098 <= 0.0)
                    {
                        _11028 = 0.0;
                        break;
                    }
                    float _9105 = _11016 * _11016;
                    vec3 _9108 = cross(_10757, _9041);
                    float _9111 = _9098 * _9105;
                    float _9120 = _9105 / (dot(_9108, _9108) + (_9111 * _9111));
                    _11028 = min((_9120 * _9120) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9158 = _5634 + ((vec3(1.0) - _5634) * pow(clamp(1.0 - max(dot(_9041, _10835), 0.0), 0.0, 1.0), 5.0));
                _11030 = (_9158 * min(_11028 * (0.5 / max(mix((2.0 * hp_copy_9021) * _9027, hp_copy_9021 + hp_copy_9027, hp_copy_11016 * hp_copy_11016), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _11029 = _9158;
            }
            else
            {
                _11030 = vec3(0.0);
                _11029 = _5634;
            }
            _11032 = (_11030 * _11013) * _9021;
            _11031 = (((((vec3(1.0) - _11029) * (1.0 - _4646)) * _5486) * 0.3183098733425140380859375) * _11013) * _9021;
            break;
        } while(false);
        _11476 = _10952 + (_11031 + _11032);
    }
    bool _9382 = false;
    highp vec3 hp_copy_10868 = vec3(0.0);
    mat3 _5842 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _5845 = _10846 > 0.5;
    bvec3 _5848 = bvec3(_5845);
    highp vec3 _5849 = vec3(_5848.x ? _10861.x : _10757.x, _5848.y ? _10861.y : _10757.y, _5848.z ? _10861.z : _10757.z);
    vec3 mp_copy_5849 = _5849;
    vec3 _5850 = _5842 * mp_copy_5849;
    vec3 _5853 = _5842 * _5646;
    float _9201 = _5850.y;
    float _9208 = _5850.z;
    float _9215 = _5850.x;
    float _9223 = 1.09254801273345947265625 * _9215;
    vec3 _5856 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _9201))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _9208))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _9215))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_9223 * _9201))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _9201) * _9208))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _9208) * _9208) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_9223 * _9208))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_9215 * _9215) - (_9201 * _9201)))), vec3(0.0));
    highp vec3 hp_copy_5856 = _5856;
    vec3 _10868 = vec3(0.0);
    do
    {
        _9382 = radiance_layout_info.mip_layout > 0.5;
        if (_9382)
        {
            vec2 _9461 = vec2(atan(_5853.z, _5853.x), asin(clamp(_5853.y, -1.0, 1.0)));
            highp vec2 hp_copy_9461 = _9461;
            _10868 = textureLod(prefiltered_radiance, (hp_copy_9461 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10805, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9480 = vec2(atan(_5853.z, _5853.x), asin(clamp(_5853.y, -1.0, 1.0)));
        highp vec2 hp_copy_9480 = _9480;
        highp vec2 _9485 = (hp_copy_9480 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _9392 = clamp(_9485.y, 0.00390625, 0.99609375);
        float _9396 = clamp(_10805, 0.0, 1.0) * 7.0;
        float _9398 = floor(_9396);
        highp float _9417 = _9485.x;
        _10868 = mix(textureLod(prefiltered_radiance, vec2(_9417, (_9398 + _9392) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9417, (min(_9398 + 1.0, 7.0) + _9392) * 0.125), 0.0).xyz, vec3(_9396 - _9398));
        break;
    } while(false);
    hp_copy_10868 = _10868;
    highp vec3 _10874 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_10869 = vec3(0.0);
        vec3 _10869 = vec3(0.0);
        do
        {
            if (_9382)
            {
                vec2 _9590 = vec2(atan(_5853.z, _5853.x), asin(clamp(_5853.y, -1.0, 1.0)));
                highp vec2 hp_copy_9590 = _9590;
                _10869 = textureLod(prefiltered_radiance_b, (hp_copy_9590 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10805, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9609 = vec2(atan(_5853.z, _5853.x), asin(clamp(_5853.y, -1.0, 1.0)));
            highp vec2 hp_copy_9609 = _9609;
            highp vec2 _9614 = (hp_copy_9609 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9521 = clamp(_9614.y, 0.00390625, 0.99609375);
            float _9525 = clamp(_10805, 0.0, 1.0) * 7.0;
            float _9527 = floor(_9525);
            highp float _9546 = _9614.x;
            _10869 = mix(textureLod(prefiltered_radiance_b, vec2(_9546, (_9527 + _9521) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9546, (min(_9527 + 1.0, 7.0) + _9521) * 0.125), 0.0).xyz, vec3(_9525 - _9527));
            break;
        } while(false);
        hp_copy_10869 = _10869;
        _10874 = hp_copy_10868 + hp_copy_10869;
    }
    else
    {
        _10874 = _10868;
    }
    float _5871 = frag_info.environment_intensity;
    highp float hp_copy_5871 = _5871;
    vec2 _5884 = clamp(vec2(_5642, _10805), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5886 = texture(brdf_lut, vec2(_5884.x * 0.3333333432674407958984375, _5884.y));
    float _5890 = _5886.x;
    float _5893 = _5886.y;
    vec3 _5895 = ((_5634 + ((max(vec3(1.0 - _10805), _5634) - _5634) * pow(clamp(1.0 - _5642, 0.0, 1.0), 5.0))) * _5890) + vec3(_5893);
    float _5901 = 1.0 - (_5890 + _5893);
    vec3 _5905 = vec3(1.0) - _5634;
    vec3 _5908 = _5634 + (_5905 * vec3(0.0476190485060214996337890625));
    vec3 _5919 = ((_5895 * _5901) * _5908) / (vec3(1.0) - (_5908 * _5901));
    float _5922 = 1.0 - _4646;
    vec3 _5923 = _5486 * _5922;
    float _10913 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _5845)
    {
        float _9656 = max(acos(clamp(exp2(((-3.321929931640625) * _10805) * _10805), 0.0, 1.0)), 0.100000001490116119384765625);
        _10913 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_10861, _5646), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _10888, 0.0, 1.0)))) + _9656) / (2.0 * _9656), 0.0, 1.0));
    }
    else
    {
        float _10914 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _10914 = clamp((pow(_5638 + _10888, exp2(((-16.0) * _10805) - 1.0)) - 1.0) + _10888, 0.0, 1.0);
        }
        else
        {
            _10914 = _10888;
        }
        _10913 = _10914;
    }
    highp vec3 _5982 = ((((_5919 + (_5923 * ((vec3(1.0) - _5895) - _5919))) * (hp_copy_5856 * hp_copy_5871)) * _10908) + (((_5895 * (_10874 * _5871)) * 1.0) * _10913)) * mix(1.0, _5625, frag_info.radiance_blend.y);
    highp vec3 _10965 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _10965 = _5982 + ((_10828.xyz * _5923) * _4680);
    }
    else
    {
        _10965 = _5982;
    }
    highp vec3 _10969 = vec3(0.0);
    if (_5575)
    {
        highp vec3 _10944 = vec3(0.0);
        highp vec3 _10945 = vec3(0.0);
        do
        {
            float _9739 = max(dot(_10757, _10936), 0.0);
            highp float hp_copy_9739 = _9739;
            if (_9739 <= 0.0)
            {
                _10945 = vec3(0.0);
                _10944 = vec3(0.0);
                break;
            }
            float _9745 = max(_5638, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9745 = _9745;
            vec3 _9748 = _10936 + mp_copy_10835;
            float _9751 = dot(_9748, _9748);
            vec3 _10942 = vec3(0.0);
            vec3 _10943 = vec3(0.0);
            if (_9751 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9759 = _9748 * inversesqrt(_9751);
                float _10941 = 0.0;
                do
                {
                    float _9816 = dot(_10757, _9759);
                    if (_9816 <= 0.0)
                    {
                        _10941 = 0.0;
                        break;
                    }
                    float _9823 = _10805 * _10805;
                    vec3 _9826 = cross(_10757, _9759);
                    float _9829 = _9816 * _9823;
                    float _9838 = _9823 / (dot(_9826, _9826) + (_9829 * _9829));
                    _10941 = min((_9838 * _9838) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9876 = _5634 + (_5905 * pow(clamp(1.0 - max(dot(_9759, _10835), 0.0), 0.0, 1.0), 5.0));
                _10943 = (_9876 * min(_10941 * (0.5 / max(mix((2.0 * hp_copy_9739) * _9745, hp_copy_9739 + hp_copy_9745, hp_copy_10805 * hp_copy_10805), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10942 = _9876;
            }
            else
            {
                _10943 = vec3(0.0);
                _10942 = _5634;
            }
            _10945 = (_10943 * frag_info.directional_light_color.xyz) * _9739;
            _10944 = (((((vec3(1.0) - _10942) * _5922) * _5486) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9739;
            break;
        } while(false);
        _10969 = _10952 + ((_10944 + _10945) * _5625);
    }
    else
    {
        _10969 = _10952;
    }
    bool _6044 = _FogInfo.params0.y > 0.5;
    bool _6050 = false;
    if (_6044)
    {
        _6050 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _6050 = _6044;
    }
    highp vec3 _10972 = vec3(0.0);
    if (_6050)
    {
        vec3 mp_copy_10970 = vec3(0.0);
        highp vec3 _10970 = vec3(0.0);
        if (_8042)
        {
            _10970 = -view_info.camera_forward.xyz;
        }
        else
        {
            _10970 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_10971 = vec3(0.0);
        mp_copy_10970 = _10970;
        vec3 _6055 = _5842 * (-mp_copy_10970);
        vec3 _10971 = vec3(0.0);
        do
        {
            if (_9382)
            {
                vec2 _9998 = vec2(atan(_6055.z, _6055.x), asin(clamp(_6055.y, -1.0, 1.0)));
                highp vec2 hp_copy_9998 = _9998;
                _10971 = textureLod(prefiltered_radiance, (hp_copy_9998 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _10017 = vec2(atan(_6055.z, _6055.x), asin(clamp(_6055.y, -1.0, 1.0)));
            highp vec2 hp_copy_10017 = _10017;
            highp vec2 _10022 = (hp_copy_10017 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9929 = clamp(_10022.y, 0.00390625, 0.99609375);
            float _9935 = floor(0.0);
            highp float _9954 = _10022.x;
            _10971 = mix(textureLod(prefiltered_radiance, vec2(_9954, (_9935 + _9929) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9954, (min(_9935 + 1.0, 7.0) + _9929) * 0.125), 0.0).xyz, vec3(-_9935));
            break;
        } while(false);
        hp_copy_10971 = _10971;
        _10972 = hp_copy_10971 * hp_copy_5871;
    }
    else
    {
        _10972 = _FogInfo.color.xyz;
    }
    highp vec4 _6070 = vec4(min((_10965 + (_10969 * mix(1.0, _10888, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _10780, vec3(65504.0)), 1.0) * _11529;
    highp vec4 _10987 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _10987 = _6070;
            break;
        }
        int _10066 = int(_FogInfo.params0.x + 0.5);
        if (_10066 == 0)
        {
            _10987 = _6070;
            break;
        }
        highp float _10974 = 0.0;
        if (_8042)
        {
            _10974 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _10974 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_10974 > _FogInfo.params1.w))
        {
            _10987 = _6070;
            break;
        }
        float _10978 = 0.0;
        if (_10066 == 1)
        {
            _10978 = clamp((_10974 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _10979 = 0.0;
            if (_10066 == 2)
            {
                highp float _10977 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _10975 = vec3(0.0);
                    if (_8042)
                    {
                        _10975 = v_position - (view_info.camera_forward.xyz * _10974);
                    }
                    else
                    {
                        _10975 = v_position + v_viewvector;
                    }
                    highp float _10157 = -_FogInfo.params2.y;
                    highp float _10164 = _FogInfo.params1.x * exp(_10157 * (_10975.y - _FogInfo.params2.x));
                    highp float _10181 = _FogInfo.params2.y * (v_position.y - _10975.y);
                    highp float _10976 = 0.0;
                    if (abs(_10181) > 0.00124999997206032276153564453125)
                    {
                        _10976 = (_10164 - (_FogInfo.params1.x * exp(_10157 * (v_position.y - _FogInfo.params2.x)))) / _10181;
                    }
                    else
                    {
                        _10976 = _10164;
                    }
                    _10977 = _10976 * max(_10974 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _10977 = _FogInfo.params1.x * max(_10974 - _FogInfo.params1.y, 0.0);
                }
                _10979 = 1.0 - exp(-_10977);
            }
            else
            {
                highp float _10119 = _FogInfo.params1.x * max(_10974 - _FogInfo.params1.y, 0.0);
                _10979 = 1.0 - exp((-_10119) * _10119);
            }
            _10978 = _10979;
        }
        highp float _10221 = min(_10978, _FogInfo.params0.z);
        if (_10221 <= 0.0)
        {
            _10987 = _6070;
            break;
        }
        highp vec3 _10234 = mix(_FogInfo.color.xyz, _10972, vec3(_FogInfo.params0.w));
        bool _10237 = _FogInfo.sun.w > 0.5;
        bool _10243 = false;
        if (_10237)
        {
            _10243 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _10243 = _10237;
        }
        vec3 _10983 = vec3(0.0);
        if (_10243)
        {
            vec3 mp_copy_10980 = vec3(0.0);
            highp vec3 _10980 = vec3(0.0);
            if (_8042)
            {
                _10980 = -view_info.camera_forward.xyz;
            }
            else
            {
                _10980 = normalize(v_viewvector);
            }
            mp_copy_10980 = _10980;
            highp float _10259 = pow(max(dot(-mp_copy_10980, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_10259 = _10259;
            _10983 = _10234 + ((_FogInfo.sun.xyz * mp_copy_10259) * _FogInfo.params2.z);
        }
        else
        {
            _10983 = _10234;
        }
        highp float _10272 = _6070.w;
        float mp_copy_10272 = _10272;
        _10987 = vec4(mix(_6070.xyz, _10983 * mp_copy_10272, vec3(_10221)), _10272);
        break;
    } while(false);
    vec4 _10989 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10989 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10989 = _10987;
        break;
    } while(false);
    frag_color = _10989;
    float _10990 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10990 = 1.0;
    }
    else
    {
        _10990 = abs(frag_info.fade);
    }
    frag_color *= _10990;
}

