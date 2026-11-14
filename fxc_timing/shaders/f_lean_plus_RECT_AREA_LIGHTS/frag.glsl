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
uniform mediump sampler2D brdf_lut;
uniform highp sampler2D irradiance_field;
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
    highp float _4656 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4656 = _4656;
    vec3 _4660 = normalize(v_normal) * mp_copy_4656;
    vec4 _4702 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4705 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _11526 = vec2(0.0);
    if (_4705)
    {
        highp vec2 _11525 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _11525 = v_texture_coords_1;
        }
        else
        {
            _11525 = v_texture_coords;
        }
        highp vec2 _4908 = _11525 * texture_transforms.base_color_transform.zw;
        highp float _4914 = _4908.x;
        highp float _4919 = _4908.y;
        _11526 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4914) + (texture_transforms.base_color_rotation.y * _4919), ((-texture_transforms.base_color_rotation.y) * _4914) + (texture_transforms.base_color_rotation.x * _4919));
    }
    else
    {
        _11526 = v_texture_coords;
    }
    vec4 _4719 = texture(base_color_texture, _11526);
    vec3 _4721 = _4719.xyz;
    float _12098 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4719.w * _4702.w) * frag_info.color.w);
    vec3 _11541 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _11529 = vec2(0.0);
        if (_4705)
        {
            highp vec2 _11528 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _11528 = v_texture_coords_1;
            }
            else
            {
                _11528 = v_texture_coords;
            }
            highp vec2 _5003 = _11528 * texture_transforms.normal_transform.zw;
            highp float _5009 = _5003.x;
            highp float _5014 = _5003.y;
            _11529 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _5009) + (texture_transforms.normal_rotation.y * _5014), ((-texture_transforms.normal_rotation.y) * _5009) + (texture_transforms.normal_rotation.x * _5014));
        }
        else
        {
            _11529 = v_texture_coords;
        }
        vec3 _5059 = ((texture(normal_texture, _11529).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _5063 = _5059.xy * vec2(frag_info.normal_scale);
        vec3 _11237 = _5059;
        _11237.x = _5063.x;
        _11237.y = _5063.y;
        highp vec3 _5069 = -v_viewvector;
        highp vec3 _5159 = dFdx(_5069);
        highp vec3 _5161 = dFdy(_5069);
        highp vec2 _5163 = dFdx(_11529);
        highp vec2 _5165 = dFdy(_11529);
        bvec2 _12100 = bvec2(length(_5163) == 0.0);
        highp vec2 _12101 = vec2(_12100.x ? vec2(1.0, 0.0).x : _5163.x, _12100.y ? vec2(1.0, 0.0).y : _5163.y);
        bvec2 _12102 = bvec2(length(_5165) == 0.0);
        highp vec2 _12103 = vec2(_12102.x ? vec2(0.0, 1.0).x : _5165.x, _12102.y ? vec2(0.0, 1.0).y : _5165.y);
        highp vec3 _5178 = cross(_5161, _4660);
        highp vec3 _5181 = cross(_4660, _5159);
        highp float _5206 = (dot(cross(_5159, _5161), _4660) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _5209 = ((_5178 * _12101.x) + (_5181 * _12103.x)) * _5206;
        highp float _11536 = 0.0;
        if (gl_FrontFacing)
        {
            _11536 = -_5206;
        }
        else
        {
            _11536 = _5206;
        }
        highp vec3 _5219 = ((_5178 * _12101.y) + (_5181 * _12103.y)) * _11536;
        highp float _5228 = inversesqrt(max(max(dot(_5209, _5209), dot(_5219, _5219)), 9.9999996826552253889678874634872e-21));
        vec3 _5100 = v_tangent.xyz - (_4660 * dot(_4660, v_tangent.xyz));
        highp float _5103 = dot(_5100, _5100);
        bool _5105 = _5103 > 1.0000000133514319600180897396058e-10;
        bool _5112 = false;
        if (_5105)
        {
            _5112 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _5112 = _5105;
        }
        mat3 _11539 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_5112)
        {
            highp vec3 _5117 = _5100 * inversesqrt(_5103);
            _11539 = mat3(_5117, normalize(cross(_4660, _5117)) * sign(v_tangent.w), _4660);
        }
        else
        {
            _11539 = mat3(_5209 * _5228, _5219 * _5228, _4660);
        }
        _11541 = normalize(_11539 * _11237);
    }
    else
    {
        _11541 = _4660;
    }
    highp vec2 _11543 = vec2(0.0);
    if (_4705)
    {
        highp vec2 _11542 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _11542 = v_texture_coords_1;
        }
        else
        {
            _11542 = v_texture_coords;
        }
        highp vec2 _5296 = _11542 * texture_transforms.metallic_roughness_transform.zw;
        highp float _5302 = _5296.x;
        highp float _5307 = _5296.y;
        _11543 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _5302) + (texture_transforms.metallic_roughness_rotation.y * _5307), ((-texture_transforms.metallic_roughness_rotation.y) * _5302) + (texture_transforms.metallic_roughness_rotation.x * _5307));
    }
    else
    {
        _11543 = v_texture_coords;
    }
    vec4 _4788 = texture(metallic_roughness_texture, _11543);
    float _4794 = clamp(_4788.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4801 = clamp(_4788.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _11545 = vec2(0.0);
    if (_4705)
    {
        highp vec2 _11544 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _11544 = v_texture_coords_1;
        }
        else
        {
            _11544 = v_texture_coords;
        }
        highp vec2 _5367 = _11544 * texture_transforms.occlusion_transform.zw;
        highp float _5373 = _5367.x;
        highp float _5378 = _5367.y;
        _11545 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _5373) + (texture_transforms.occlusion_rotation.y * _5378), ((-texture_transforms.occlusion_rotation.y) * _5373) + (texture_transforms.occlusion_rotation.x * _5378));
    }
    else
    {
        _11545 = v_texture_coords;
    }
    float _11546 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _11546 = texture(occlusion_texture, _11545).x;
    }
    else
    {
        _11546 = 1.0;
    }
    float _4828 = 1.0 - ((1.0 - _11546) * frag_info.occlusion_strength);
    highp vec2 _11548 = vec2(0.0);
    if (_4705)
    {
        highp vec2 _11547 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _11547 = v_texture_coords_1;
        }
        else
        {
            _11547 = v_texture_coords;
        }
        highp vec2 _5438 = _11547 * texture_transforms.emissive_transform.zw;
        highp float _5444 = _5438.x;
        highp float _5449 = _5438.y;
        _11548 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5444) + (texture_transforms.emissive_rotation.y * _5449), ((-texture_transforms.emissive_rotation.y) * _5444) + (texture_transforms.emissive_rotation.x * _5449));
    }
    else
    {
        _11548 = v_texture_coords;
    }
    vec3 _4847 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _11564 = vec3(0.0);
    if (dot(abs(_4847), vec3(1.0)) > 0.0)
    {
        vec3 _4856 = texture(emissive_texture, _11548).xyz;
        _11564 = mix(_4856 * vec3(0.077399380505084991455078125), pow((_4856 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4856)) * _4847;
    }
    else
    {
        _11564 = vec3(0.0);
    }
    highp float hp_copy_11589 = 0.0;
    vec3 _5668 = vec4((mix(_4721 * vec3(0.077399380505084991455078125), pow((_4721 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4721)) * _4702.xyz) * frag_info.color.xyz, _12098).xyz;
    vec3 _6319 = dFdx(_11541);
    vec3 _6321 = dFdy(_11541);
    float _11589 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _11589 = sqrt(clamp((_4801 * _4801) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_6319, _6319), dot(_6321, _6321))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _11589 = _4801;
    }
    hp_copy_11589 = _11589;
    float _11618 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _11618 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _11618 = _4828;
    }
    bool _5693 = frag_info.has_directional_light > 0.5;
    float _11590 = 0.0;
    vec3 _11632 = vec3(0.0);
    if (_5693)
    {
        highp vec3 _5699 = -normalize(frag_info.directional_light_direction.xyz);
        _11632 = _5699;
        _11590 = dot(_4660, _5699);
    }
    else
    {
        _11632 = vec3(0.0);
        _11590 = 0.0;
    }
    float _5706 = clamp(_11590 * 6.666666507720947265625, 0.0, 1.0);
    bool _5715 = false;
    if (_5693)
    {
        _5715 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5715 = _5693;
    }
    float _11599 = 0.0;
    if (_5715 && (_5706 > 0.0))
    {
        int _6400 = int(frag_info.shadow_cascade_count);
        float _6595 = max(dot(_4660, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6598 = _6595 * _6595;
        highp vec3 _6618 = v_position + (_4660 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6598, 0.0)) / _6598, 8.0))));
        highp float _6406 = frag_info.directional_light_color.w * 0.5;
        float _6408 = frag_info.dielectric_f0.w;
        highp float hp_copy_6408 = _6408;
        float _11591 = 0.0;
        if (_6408 > 0.0)
        {
            _11591 = smoothstep(_6408 - max(frag_info.shadow_fade, hp_copy_6408 * 0.100000001490116119384765625), _6408, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _11591 = 0.0;
        }
        float _11593 = 0.0;
        float _11595 = 0.0;
        if (_11591 < 1.0)
        {
            float _11594 = 0.0;
            float _11596 = 0.0;
            _11596 = 0.0;
            _11594 = 0.0;
            float _11912 = 0.0;
            float _11915 = 0.0;
            for (int _11592 = 0; _11592 < _6400; _11596 = _11915, _11594 = _11912, _11592++)
            {
                if (_11596 < 1.0)
                {
                    highp vec4 _6440 = vec4(_6618, 1.0);
                    highp vec4 _11784 = vec4(0.0);
                    highp float _11787 = 0.0;
                    if (_11592 == 0)
                    {
                        _11787 = frag_info.cascade_box_sizes.x;
                        _11784 = frag_info.light_space_matrix[0] * _6440;
                    }
                    else
                    {
                        highp vec4 _11785 = vec4(0.0);
                        highp float _11788 = 0.0;
                        if (_11592 == 1)
                        {
                            _11788 = frag_info.cascade_box_sizes.y;
                            _11785 = frag_info.light_space_matrix[1] * _6440;
                        }
                        else
                        {
                            highp vec4 _11786 = vec4(0.0);
                            highp float _11789 = 0.0;
                            if (_11592 == 2)
                            {
                                _11789 = frag_info.cascade_box_sizes.z;
                                _11786 = frag_info.light_space_matrix[2] * _6440;
                            }
                            else
                            {
                                _11789 = frag_info.cascade_box_sizes.w;
                                _11786 = frag_info.light_space_matrix[3] * _6440;
                            }
                            _11788 = _11789;
                            _11785 = _11786;
                        }
                        _11787 = _11788;
                        _11784 = _11785;
                    }
                    highp vec3 _6485 = _11784.xyz / vec3(_11784.w);
                    highp vec2 _6488 = _6485.xy * 0.5;
                    highp vec2 _6490 = _6488 + vec2(0.5);
                    highp float _6497 = max(frag_info.shadow_softness / _11787, frag_info.shadow_texel_size);
                    highp float _6499 = _6490.x;
                    bool _6501 = _6499 < _6497;
                    bool _6510 = false;
                    if (!_6501)
                    {
                        _6510 = _6499 > (1.0 - _6497);
                    }
                    else
                    {
                        _6510 = _6501;
                    }
                    bool _6518 = false;
                    if (!_6510)
                    {
                        _6518 = _6490.y < _6497;
                    }
                    else
                    {
                        _6518 = _6510;
                    }
                    bool _6527 = false;
                    if (!_6518)
                    {
                        _6527 = _6490.y > (1.0 - _6497);
                    }
                    else
                    {
                        _6527 = _6518;
                    }
                    bool _6534 = false;
                    if (!_6527)
                    {
                        _6534 = _6485.z < 0.0;
                    }
                    else
                    {
                        _6534 = _6527;
                    }
                    bool _6541 = false;
                    if (!_6534)
                    {
                        _6541 = _6485.z > 1.0;
                    }
                    else
                    {
                        _6541 = _6534;
                    }
                    float _11913 = 0.0;
                    float _11916 = 0.0;
                    if (!_6541)
                    {
                        highp vec2 _6634 = vec2(_6497);
                        highp vec2 _6639 = vec2(_6497 + max(_6406, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6647 = vec2(0.5) - _6488;
                        highp vec2 _6649 = smoothstep(_6634, _6639, _6490) * smoothstep(_6634, _6639, _6647);
                        float _11790 = 0.0;
                        if (_6406 > 0.0)
                        {
                            _11790 = _6649.x * _6649.y;
                        }
                        else
                        {
                            _11790 = 1.0;
                        }
                        float _6550 = min(_11790, 1.0 - _11596);
                        float _11914 = 0.0;
                        float _11917 = 0.0;
                        if (_6550 > 0.0)
                        {
                            highp float _6788 = _6485.z - (frag_info.shadow_bias / (7.0 * _11787));
                            highp float _6794 = 1.0 / (float(_6400) + frag_info.spot_shadow_params.x);
                            highp float _6796 = frag_info.directional_light_direction.w;
                            float mp_copy_6796 = _6796;
                            float _6802 = step(0.5, mp_copy_6796) * (1.0 - step(1.5, mp_copy_6796));
                            float _11820 = 0.0;
                            float _11824 = 0.0;
                            if (_6802 < 0.5)
                            {
                                highp float _6813 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6813 = _6813;
                                _11824 = sin(mp_copy_6813);
                                _11820 = cos(mp_copy_6813);
                            }
                            else
                            {
                                _11824 = 0.0;
                                _11820 = 1.0;
                            }
                            highp float _11827 = 0.0;
                            if ((_6796 > 1.5) && (_6796 < 2.5))
                            {
                                highp float _6837 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6842 = max(_6837 * _6788, frag_info.shadow_texel_size);
                                float _11816 = 0.0;
                                highp float _11817 = 0.0;
                                _11817 = 0.0;
                                _11816 = 0.0;
                                highp float _6864 = 0.0;
                                float _6867 = 0.0;
                                for (int _11815 = 0; _11815 < 9; _11817 = _6864, _11816 = _6867, _11815++)
                                {
                                    vec2 _11906 = vec2(0.0);
                                    do
                                    {
                                        if (_11815 == 0)
                                        {
                                            _11906 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_11815 == 1)
                                        {
                                            _11906 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_11815 == 2)
                                        {
                                            _11906 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_11815 == 3)
                                        {
                                            _11906 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_11815 == 4)
                                        {
                                            _11906 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_11815 == 5)
                                        {
                                            _11906 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_11815 == 6)
                                        {
                                            _11906 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_11815 == 7)
                                        {
                                            _11906 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_11815 == 8)
                                        {
                                            _11906 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_11815 == 9)
                                        {
                                            _11906 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_11815 == 10)
                                        {
                                            _11906 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_11815 == 11)
                                        {
                                            _11906 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_11815 == 12)
                                        {
                                            _11906 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_11815 == 13)
                                        {
                                            _11906 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_11815 == 14)
                                        {
                                            _11906 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_11815 == 15)
                                        {
                                            _11906 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _11906 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _7171 = clamp(_6490 + (vec2((_11906.x * _11820) - (_11906.y * _11824), (_11906.x * _11824) + (_11906.y * _11820)) * _6842), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _7180 = _7171.y;
                                    highp vec2 _7181 = vec2((float(_11592) + _7171.x) * _6794, _7180);
                                    _7181.y = 1.0 - _7180;
                                    highp vec4 _7188 = textureLod(shadow_map, _7181, 0.0);
                                    highp float _7189 = _7188.x;
                                    highp float _6859 = step(_7189, _6788);
                                    float mp_copy_6859 = _6859;
                                    _6864 = _11817 + (_7189 * _6859);
                                    _6867 = _11816 + mp_copy_6859;
                                }
                                highp float _11818 = 0.0;
                                if (_11816 > 0.0)
                                {
                                    _11818 = _11817 / _11816;
                                }
                                else
                                {
                                    _11818 = _6788;
                                }
                                _11827 = clamp(_6837 * max(_6788 - _11818, 0.0), frag_info.shadow_texel_size, _6497);
                            }
                            else
                            {
                                _11827 = _6497;
                            }
                            bool _6898 = _6796 > 2.5;
                            bool _11828 = false;
                            float _11853 = 0.0;
                            if ((_6796 < 1.5) || _6898)
                            {
                                highp vec2 _7222 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _7226 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _7227 = clamp(_6490, _7222, _7226);
                                highp float _7229 = float(_11592);
                                highp float _7236 = _7227.y;
                                highp vec2 _7237 = vec2((_7229 + _7227.x) * _6794, _7236);
                                _7237.y = 1.0 - _7236;
                                highp float _7249 = float(_6788 <= textureLod(shadow_map, _7237, 0.0).x);
                                float mp_copy_7249 = _7249;
                                float _7259 = (-1.0) * _11820;
                                float _7263 = (-1.0) * _11824;
                                highp vec2 _7287 = clamp(_6490 + (vec2(_7259 - _7263, _7263 + _7259) * _11827), _7222, _7226);
                                highp float _7296 = _7287.y;
                                highp vec2 _7297 = vec2((_7229 + _7287.x) * _6794, _7296);
                                _7297.y = 1.0 - _7296;
                                highp float _7309 = float(_6788 <= textureLod(shadow_map, _7297, 0.0).x);
                                float mp_copy_7309 = _7309;
                                highp vec2 _7347 = clamp(_6490 + (vec2(_11820 - _7263, _11824 + _7259) * _11827), _7222, _7226);
                                highp float _7356 = _7347.y;
                                highp vec2 _7357 = vec2((_7229 + _7347.x) * _6794, _7356);
                                _7357.y = 1.0 - _7356;
                                highp float _7369 = float(_6788 <= textureLod(shadow_map, _7357, 0.0).x);
                                float mp_copy_7369 = _7369;
                                highp vec2 _7407 = clamp(_6490 + (vec2(_7259 - _11824, _7263 + _11820) * _11827), _7222, _7226);
                                highp float _7416 = _7407.y;
                                highp vec2 _7417 = vec2((_7229 + _7407.x) * _6794, _7416);
                                _7417.y = 1.0 - _7416;
                                highp float _7429 = float(_6788 <= textureLod(shadow_map, _7417, 0.0).x);
                                float mp_copy_7429 = _7429;
                                highp vec2 _7467 = clamp(_6490 + (vec2(_11820 - _11824, _11824 + _11820) * _11827), _7222, _7226);
                                highp float _7476 = _7467.y;
                                highp vec2 _7477 = vec2((_7229 + _7467.x) * _6794, _7476);
                                _7477.y = 1.0 - _7476;
                                highp float _7489 = float(_6788 <= textureLod(shadow_map, _7477, 0.0).x);
                                float mp_copy_7489 = _7489;
                                float _6944 = (((mp_copy_7249 + mp_copy_7309) + mp_copy_7369) + mp_copy_7429) + mp_copy_7489;
                                _11853 = _6944 * 0.20000000298023223876953125;
                                _11828 = (_6944 < 0.5) || (_6944 > 4.5);
                            }
                            else
                            {
                                _11853 = 0.0;
                                _11828 = false;
                            }
                            float _11851 = 0.0;
                            if (_11828)
                            {
                                _11851 = _11853;
                            }
                            else
                            {
                                float _11852 = 0.0;
                                if (_6898)
                                {
                                    highp vec2 _7708 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7712 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7713 = clamp(_6490 + (vec2(-0.707099974155426025390625) * _11827), _7708, _7712);
                                    highp vec2 _7724 = (vec2(_7713.x, 1.0 - _7713.y) / _7708) - vec2(0.5);
                                    highp vec2 _7726 = floor(_7724);
                                    highp vec2 _7729 = _7724 - _7726;
                                    highp vec2 _7734 = (_7726 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7736 = float(_11592);
                                    highp vec2 _7744 = vec2((_7736 + _7734.x) * _6794, _7734.y);
                                    highp float _7748 = frag_info.shadow_texel_size * _6794;
                                    highp vec2 _7751 = vec2(_7748, frag_info.shadow_texel_size);
                                    highp vec2 _7760 = vec2(_7748, 0.0);
                                    highp vec2 _7768 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7797 = _7729.x;
                                    highp float _7806 = mix(mix(float(_6788 <= textureLod(shadow_map, _7744, 0.0).x), float(_6788 <= textureLod(shadow_map, _7744 + _7760, 0.0).x), _7797), mix(float(_6788 <= textureLod(shadow_map, _7744 + _7768, 0.0).x), float(_6788 <= textureLod(shadow_map, _7744 + _7751, 0.0).x), _7797), _7729.y);
                                    float mp_copy_7806 = _7806;
                                    highp vec2 _7840 = clamp(_6490 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _11827), _7708, _7712);
                                    highp vec2 _7851 = (vec2(_7840.x, 1.0 - _7840.y) / _7708) - vec2(0.5);
                                    highp vec2 _7853 = floor(_7851);
                                    highp vec2 _7856 = _7851 - _7853;
                                    highp vec2 _7861 = (_7853 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7871 = vec2((_7736 + _7861.x) * _6794, _7861.y);
                                    highp float _7924 = _7856.x;
                                    highp float _7933 = mix(mix(float(_6788 <= textureLod(shadow_map, _7871, 0.0).x), float(_6788 <= textureLod(shadow_map, _7871 + _7760, 0.0).x), _7924), mix(float(_6788 <= textureLod(shadow_map, _7871 + _7768, 0.0).x), float(_6788 <= textureLod(shadow_map, _7871 + _7751, 0.0).x), _7924), _7856.y);
                                    float mp_copy_7933 = _7933;
                                    highp vec2 _7967 = clamp(_6490 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _11827), _7708, _7712);
                                    highp vec2 _7978 = (vec2(_7967.x, 1.0 - _7967.y) / _7708) - vec2(0.5);
                                    highp vec2 _7980 = floor(_7978);
                                    highp vec2 _7983 = _7978 - _7980;
                                    highp vec2 _7988 = (_7980 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7998 = vec2((_7736 + _7988.x) * _6794, _7988.y);
                                    highp float _8051 = _7983.x;
                                    highp float _8060 = mix(mix(float(_6788 <= textureLod(shadow_map, _7998, 0.0).x), float(_6788 <= textureLod(shadow_map, _7998 + _7760, 0.0).x), _8051), mix(float(_6788 <= textureLod(shadow_map, _7998 + _7768, 0.0).x), float(_6788 <= textureLod(shadow_map, _7998 + _7751, 0.0).x), _8051), _7983.y);
                                    float mp_copy_8060 = _8060;
                                    highp vec2 _8094 = clamp(_6490 + (vec2(0.707099974155426025390625) * _11827), _7708, _7712);
                                    highp vec2 _8105 = (vec2(_8094.x, 1.0 - _8094.y) / _7708) - vec2(0.5);
                                    highp vec2 _8107 = floor(_8105);
                                    highp vec2 _8110 = _8105 - _8107;
                                    highp vec2 _8115 = (_8107 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8125 = vec2((_7736 + _8115.x) * _6794, _8115.y);
                                    highp float _8178 = _8110.x;
                                    highp float _8187 = mix(mix(float(_6788 <= textureLod(shadow_map, _8125, 0.0).x), float(_6788 <= textureLod(shadow_map, _8125 + _7760, 0.0).x), _8178), mix(float(_6788 <= textureLod(shadow_map, _8125 + _7768, 0.0).x), float(_6788 <= textureLod(shadow_map, _8125 + _7751, 0.0).x), _8178), _8110.y);
                                    float mp_copy_8187 = _8187;
                                    _11852 = (((mp_copy_7806 + mp_copy_7933) + mp_copy_8060) + mp_copy_8187) * 0.25;
                                }
                                else
                                {
                                    int _6960 = (_6802 > 0.5) ? 17 : 16;
                                    float _11847 = 0.0;
                                    _11847 = 0.0;
                                    float _6988 = 0.0;
                                    for (int _11829 = 0; _11829 < 17; _11847 = _6988, _11829++)
                                    {
                                        if (_11829 >= _6960)
                                        {
                                            break;
                                        }
                                        vec2 _11830 = vec2(0.0);
                                        do
                                        {
                                            if (_11829 == 0)
                                            {
                                                _11830 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_11829 == 1)
                                            {
                                                _11830 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_11829 == 2)
                                            {
                                                _11830 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_11829 == 3)
                                            {
                                                _11830 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_11829 == 4)
                                            {
                                                _11830 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_11829 == 5)
                                            {
                                                _11830 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_11829 == 6)
                                            {
                                                _11830 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_11829 == 7)
                                            {
                                                _11830 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_11829 == 8)
                                            {
                                                _11830 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_11829 == 9)
                                            {
                                                _11830 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_11829 == 10)
                                            {
                                                _11830 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_11829 == 11)
                                            {
                                                _11830 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_11829 == 12)
                                            {
                                                _11830 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_11829 == 13)
                                            {
                                                _11830 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_11829 == 14)
                                            {
                                                _11830 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_11829 == 15)
                                            {
                                                _11830 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _11830 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _11832 = vec2(0.0);
                                        do
                                        {
                                            if (_11829 < 3)
                                            {
                                                _11832 = vec2(float(_11829) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_11829 < 6)
                                            {
                                                _11832 = vec2((float(_11829 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_11829 < 11)
                                            {
                                                _11832 = vec2((float(_11829 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_11829 < 14)
                                            {
                                                _11832 = vec2((float(_11829 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _11832 = vec2(float(_11829 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6977 = mix(_11830, _11832, vec2(_6802));
                                        float _7628 = _6977.x;
                                        float _7632 = _6977.y;
                                        highp vec2 _7658 = clamp(_6490 + (vec2((_7628 * _11820) - (_7632 * _11824), (_7628 * _11824) + (_7632 * _11820)) * _11827), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7667 = _7658.y;
                                        highp vec2 _7668 = vec2((float(_11592) + _7658.x) * _6794, _7667);
                                        _7668.y = 1.0 - _7667;
                                        highp float _7680 = float(_6788 <= textureLod(shadow_map, _7668, 0.0).x);
                                        float mp_copy_7680 = _7680;
                                        _6988 = _11847 + mp_copy_7680;
                                    }
                                    _11852 = _11847 / float(_6960);
                                }
                                _11851 = _11852;
                            }
                            bool _7033 = _11592 == (_6400 - 1);
                            bool _7039 = false;
                            if (_7033)
                            {
                                _7039 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _7039 = _7033;
                            }
                            float _11854 = 0.0;
                            if (_7039)
                            {
                                highp vec2 _7046 = vec2(frag_info.shadow_fade / _11787);
                                highp vec2 _7054 = smoothstep(vec2(0.0), _7046, _6490) * smoothstep(vec2(0.0), _7046, _6647);
                                _11854 = mix(1.0, _11851, _7054.x * _7054.y);
                            }
                            else
                            {
                                _11854 = _11851;
                            }
                            _11917 = _11596 + _6550;
                            _11914 = _11594 + (_6550 * _11854);
                        }
                        else
                        {
                            _11917 = _11596;
                            _11914 = _11594;
                        }
                        _11916 = _11917;
                        _11913 = _11914;
                    }
                    else
                    {
                        _11916 = _11596;
                        _11913 = _11594;
                    }
                    _11915 = _11916;
                    _11912 = _11913;
                }
                else
                {
                    _11915 = _11596;
                    _11912 = _11594;
                }
            }
            _11595 = _11596;
            _11593 = _11594;
        }
        else
        {
            _11595 = 0.0;
            _11593 = 0.0;
        }
        _11599 = mix(_11593 + (1.0 - _11595), 1.0, _11591);
    }
    else
    {
        _11599 = 1.0;
    }
    vec3 mp_copy_11600 = vec3(0.0);
    float _5728 = _5706 * _11599;
    bool _8195 = view_info.camera_forward.w > 0.5;
    highp vec3 _11600 = vec3(0.0);
    if (_8195)
    {
        _11600 = -view_info.camera_forward.xyz;
    }
    else
    {
        _11600 = normalize(v_viewvector);
    }
    highp float _8239 = 0.0;
    mp_copy_11600 = _11600;
    vec3 _5737 = mix(frag_info.dielectric_f0.xyz, _5668, vec3(_4794));
    float _5740 = dot(_11541, _11600);
    float _5741 = max(_5740, 0.0);
    float _5745 = max(dot(_4660, _11600), 0.0);
    highp vec2 _11601 = vec2(0.0);
    do
    {
        _8239 = frag_info.punctual_dims.x;
        if (_8239 < 0.5)
        {
            _11601 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _8251 = v_position - frag_info.camera_position.xyz;
            highp float _8266 = dot(_8251, frag_info.camera_forward.xyz);
            highp float _8272 = max(_8266, 9.9999997473787516355514526367188e-05);
            highp vec2 _8375 = (vec3(dot(_8251, frag_info.camera_right.xyz), dot(_8251, frag_info.camera_up.xyz), _8272).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_8272, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _8390 = float(int(((((clamp(floor((log2(max(_8266 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_8375.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_8375.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _11601 = vec2(textureLod(punctual_index, vec2((mod(_8390, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8390 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _11601 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5754 = int(_11601.x + 0.5);
    mediump int _5758 = int(_11601.y + 0.5);
    highp vec3 _11646 = vec3(0.0);
    _11646 = vec3(0.0);
    highp vec3 _12046 = vec3(0.0);
    for (int _11602 = 0; _11602 < _5758; _11646 = _12046, _11602++)
    {
        highp float _8423 = float(_5754 + _11602);
        highp float _8454 = (float(int(textureLod(punctual_index, vec2((mod(_8423, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8423 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _8239;
        highp vec4 _8458 = textureLod(punctual_lights, vec2(0.0625, _8454), 0.0);
        highp vec4 _8475 = textureLod(punctual_lights, vec2(0.1875, _8454), 0.0);
        highp float _5776 = _8458.w;
        highp vec3 _5778 = _8475.xyz;
        highp vec3 _12047 = vec3(0.0);
        if (_5776 > 2.5)
        {
            highp vec4 _9328 = textureLod(punctual_lights, vec2(0.3125, _8454), 0.0);
            highp vec4 _9345 = textureLod(punctual_lights, vec2(0.4375, _8454), 0.0);
            highp vec3 _5942 = _9328.xyz * (_9328.w * 0.5);
            highp vec3 _5948 = _9345.xyz * (_9345.w * 0.5);
            highp vec3 _5950 = _8458.xyz;
            highp vec3 _5952 = _5950 - _5942;
            highp vec3 _5954 = _5952 - _5948;
            highp vec3 _5958 = _5950 + _5942;
            highp vec3 _5960 = _5958 - _5948;
            highp vec3 _5972 = _5952 + _5948;
            highp vec3 _5976 = _5950 - v_position;
            highp float _5982 = _8475.w;
            highp float _5986 = (dot(_5976, _5976) * _5982) * _5982;
            highp float _5991 = clamp(1.0 - (_5986 * _5986), 0.0, 1.0);
            float mp_copy_5991 = _5991;
            vec2 _9352 = (clamp(vec2(_11589, sqrt(1.0 - _5741)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _9354 = _9352.x;
            float _9359 = _9352.y;
            vec4 _6015 = textureLod(brdf_lut, vec2((_9354 + 1.0) * 0.3333333432674407958984375, _9359), 0.0);
            vec4 _6019 = textureLod(brdf_lut, vec2((_9354 + 2.0) * 0.3333333432674407958984375, _9359), 0.0);
            vec3 _9402 = normalize(mp_copy_11600 - (_11541 * _5740));
            mat3 _9424 = transpose(mat3(_9402, -cross(_11541, _9402), _11541));
            mat3 _9425 = mat3(vec3(_6015.x, 0.0, _6015.y), vec3(0.0, 1.0, 0.0), vec3(_6015.z, 0.0, _6015.w)) * _9424;
            highp vec3 _9429 = _5954 - v_position;
            highp vec3 _9431 = normalize(_9425 * _9429);
            vec3 mp_copy_9431 = _9431;
            highp vec3 _9435 = _5960 - v_position;
            highp vec3 _9437 = normalize(_9425 * _9435);
            vec3 mp_copy_9437 = _9437;
            highp vec3 _9441 = (_5958 + _5948) - v_position;
            highp vec3 _9443 = normalize(_9425 * _9441);
            vec3 mp_copy_9443 = _9443;
            highp vec3 _9447 = _5972 - v_position;
            highp vec3 _9449 = normalize(_9425 * _9447);
            vec3 mp_copy_9449 = _9449;
            float _9478 = dot(_9431, _9437);
            float _9480 = abs(_9478);
            float _9494 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9480)) * _9480)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9480) * _9480));
            float _11735 = 0.0;
            if (_9478 > 0.0)
            {
                _11735 = _9494;
            }
            else
            {
                _11735 = (0.5 * inversesqrt(max(1.0 - (_9478 * _9478), 1.0000000116860974230803549289703e-07))) - _9494;
            }
            float _9527 = dot(_9437, _9443);
            float _9529 = abs(_9527);
            float _9543 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9529)) * _9529)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9529) * _9529));
            float _11736 = 0.0;
            if (_9527 > 0.0)
            {
                _11736 = _9543;
            }
            else
            {
                _11736 = (0.5 * inversesqrt(max(1.0 - (_9527 * _9527), 1.0000000116860974230803549289703e-07))) - _9543;
            }
            float _9576 = dot(_9443, _9449);
            float _9578 = abs(_9576);
            float _9592 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9578)) * _9578)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9578) * _9578));
            float _11737 = 0.0;
            if (_9576 > 0.0)
            {
                _11737 = _9592;
            }
            else
            {
                _11737 = (0.5 * inversesqrt(max(1.0 - (_9576 * _9576), 1.0000000116860974230803549289703e-07))) - _9592;
            }
            float _9625 = dot(_9449, _9431);
            float _9627 = abs(_9625);
            float _9641 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9627)) * _9627)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9627) * _9627));
            float _11738 = 0.0;
            if (_9625 > 0.0)
            {
                _11738 = _9641;
            }
            else
            {
                _11738 = (0.5 * inversesqrt(max(1.0 - (_9625 * _9625), 1.0000000116860974230803549289703e-07))) - _9641;
            }
            vec3 _9464 = (((cross(mp_copy_9431, mp_copy_9437) * _11735) + (cross(mp_copy_9437, mp_copy_9443) * _11736)) + (cross(mp_copy_9443, mp_copy_9449) * _11737)) + (cross(mp_copy_9449, mp_copy_9431) * _11738);
            float _9667 = length(_9464);
            mat3 _9727 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _9424;
            highp vec3 _9733 = normalize(_9727 * _9429);
            vec3 mp_copy_9733 = _9733;
            highp vec3 _9739 = normalize(_9727 * _9435);
            vec3 mp_copy_9739 = _9739;
            highp vec3 _9745 = normalize(_9727 * _9441);
            vec3 mp_copy_9745 = _9745;
            highp vec3 _9751 = normalize(_9727 * _9447);
            vec3 mp_copy_9751 = _9751;
            float _9780 = dot(_9733, _9739);
            float _9782 = abs(_9780);
            float _9796 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9782)) * _9782)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9782) * _9782));
            float _11739 = 0.0;
            if (_9780 > 0.0)
            {
                _11739 = _9796;
            }
            else
            {
                _11739 = (0.5 * inversesqrt(max(1.0 - (_9780 * _9780), 1.0000000116860974230803549289703e-07))) - _9796;
            }
            float _9829 = dot(_9739, _9745);
            float _9831 = abs(_9829);
            float _9845 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9831)) * _9831)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9831) * _9831));
            float _11740 = 0.0;
            if (_9829 > 0.0)
            {
                _11740 = _9845;
            }
            else
            {
                _11740 = (0.5 * inversesqrt(max(1.0 - (_9829 * _9829), 1.0000000116860974230803549289703e-07))) - _9845;
            }
            float _9878 = dot(_9745, _9751);
            float _9880 = abs(_9878);
            float _9894 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9880)) * _9880)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9880) * _9880));
            float _11741 = 0.0;
            if (_9878 > 0.0)
            {
                _11741 = _9894;
            }
            else
            {
                _11741 = (0.5 * inversesqrt(max(1.0 - (_9878 * _9878), 1.0000000116860974230803549289703e-07))) - _9894;
            }
            float _9927 = dot(_9751, _9733);
            float _9929 = abs(_9927);
            float _9943 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9929)) * _9929)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9929) * _9929));
            float _11742 = 0.0;
            if (_9927 > 0.0)
            {
                _11742 = _9943;
            }
            else
            {
                _11742 = (0.5 * inversesqrt(max(1.0 - (_9927 * _9927), 1.0000000116860974230803549289703e-07))) - _9943;
            }
            vec3 _9766 = (((cross(mp_copy_9733, mp_copy_9739) * _11739) + (cross(mp_copy_9739, mp_copy_9745) * _11740)) + (cross(mp_copy_9745, mp_copy_9751) * _11741)) + (cross(mp_copy_9751, mp_copy_9733) * _11742);
            float _9969 = length(_9766);
            _12047 = _11646 + (((_5778 * (mp_copy_5991 * mp_copy_5991)) * step(0.0, dot(cross(_5960 - _5954, _5972 - _5954), v_position - _5954))) * (((((_5737 * _6019.x) + ((vec3(1.0) - _5737) * _6019.y)) * max(((_9667 * _9667) + _9464.z) / (_9667 + 1.0), 0.0)) * 1.0) + ((_5668 * (1.0 - _4794)) * max(((_9969 * _9969) + _9766.z) / (_9969 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_11703 = 0.0;
            vec3 _11689 = vec3(0.0);
            highp vec3 _11700 = vec3(0.0);
            float _11703 = 0.0;
            if (_5776 < 0.5)
            {
                _11703 = _11589;
                _11700 = _5778;
                _11689 = -normalize(textureLod(punctual_lights, vec2(0.3125, _8454), 0.0).xyz);
            }
            else
            {
                highp vec3 _5789 = _8458.xyz - v_position;
                highp float _5792 = dot(_5789, _5789);
                highp float _5796 = inversesqrt(max(_5792, 9.9999999392252902907785028219223e-09));
                highp vec3 _5797 = _5789 * _5796;
                vec3 mp_copy_5797 = _5797;
                highp float _5799 = _8475.w;
                highp float _5804 = (_5792 * _5799) * _5799;
                highp float _5809 = clamp(1.0 - (_5804 * _5804), 0.0, 1.0);
                float mp_copy_5809 = _5809;
                if (_5809 <= 0.0)
                {
                    _12046 = _11646;
                    continue;
                }
                highp vec4 _8492 = textureLod(punctual_lights, vec2(0.4375, _8454), 0.0);
                highp float _5817 = _8492.w;
                float _11705 = 0.0;
                if (_5817 > 0.0)
                {
                    highp float _5844 = (_11589 * _11589) + ((_5817 * 0.5) * _5796);
                    float mp_copy_5844 = _5844;
                    _11705 = sqrt(min(mp_copy_5844, 1.0));
                }
                else
                {
                    _11705 = _11589;
                }
                highp vec3 _5851 = _5778 * ((mp_copy_5809 * mp_copy_5809) / max(pow(max(_5792, _5817 * _5817), _8492.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _11701 = vec3(0.0);
                if (_5776 > 1.5)
                {
                    highp vec4 _8509 = textureLod(punctual_lights, vec2(0.3125, _8454), 0.0);
                    highp float _5870 = clamp((dot(normalize(_8509.xyz), -mp_copy_5797) * _8509.w) + _8492.x, 0.0, 1.0);
                    float mp_copy_5870 = _5870;
                    highp vec3 _5875 = _5851 * (mp_copy_5870 * mp_copy_5870);
                    if (_5870 <= 0.0)
                    {
                        _12046 = _11646;
                        continue;
                    }
                    bool _5881 = _5870 > 0.0;
                    bool _5887 = false;
                    if (_5881)
                    {
                        _5887 = _8492.y > (-0.5);
                    }
                    else
                    {
                        _5887 = _5881;
                    }
                    bool _5893 = false;
                    if (_5887)
                    {
                        _5893 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _5893 = _5887;
                    }
                    highp vec3 _11702 = vec3(0.0);
                    if (_5893)
                    {
                        float _11680 = 0.0;
                        do
                        {
                            highp vec4 _8621 = mat4(textureLod(punctual_lights, vec2(0.5625, _8454), 0.0), textureLod(punctual_lights, vec2(0.6875, _8454), 0.0), textureLod(punctual_lights, vec2(0.8125, _8454), 0.0), textureLod(punctual_lights, vec2(0.9375, _8454), 0.0)) * vec4(v_position + (_4660 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _8623 = _8621.w;
                            if (_8623 <= 0.0)
                            {
                                _11680 = 1.0;
                                break;
                            }
                            highp vec3 _8632 = _8621.xyz / vec3(_8623);
                            highp vec2 _8637 = (_8632.xy * 0.5) + vec2(0.5);
                            highp float _8639 = _8637.x;
                            bool _8640 = _8639 < 0.0;
                            bool _8647 = false;
                            if (!_8640)
                            {
                                _8647 = _8639 > 1.0;
                            }
                            else
                            {
                                _8647 = _8640;
                            }
                            bool _8654 = false;
                            if (!_8647)
                            {
                                _8654 = _8637.y < 0.0;
                            }
                            else
                            {
                                _8654 = _8647;
                            }
                            bool _8661 = false;
                            if (!_8654)
                            {
                                _8661 = _8637.y > 1.0;
                            }
                            else
                            {
                                _8661 = _8654;
                            }
                            bool _8668 = false;
                            if (!_8661)
                            {
                                _8668 = _8632.z < 0.0;
                            }
                            else
                            {
                                _8668 = _8661;
                            }
                            bool _8675 = false;
                            if (!_8668)
                            {
                                _8675 = _8632.z > 1.0;
                            }
                            else
                            {
                                _8675 = _8668;
                            }
                            if (_8675)
                            {
                                _11680 = 1.0;
                                break;
                            }
                            highp float _8682 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _8687 = frag_info.shadow_cascade_count + float(int(_8492.y + 0.5));
                            highp float _8692 = _8632.z - frag_info.spot_shadow_params.y;
                            highp float _8703 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_8703 = _8703;
                            highp vec2 _8710 = vec2(cos(mp_copy_8703), sin(mp_copy_8703)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _8712 = _8710.x;
                            highp float _8714 = _8710.y;
                            highp vec2 _8722 = vec2(_8712 - _8714, _8712 + _8714) * 0.707106769084930419921875;
                            highp float _8915 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8639, 0.0, 1.0)) / _8682, 1.0 - clamp(_8637.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_8915 = _8915;
                            highp vec2 _8730 = _8637 + _8710;
                            highp float _8937 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8730.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8730.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_8937 = _8937;
                            highp vec2 _8738 = _8637 - _8710;
                            highp float _8959 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8738.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8738.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_8959 = _8959;
                            highp vec2 _8751 = _8637 + vec2(-_8714, _8712);
                            highp float _8981 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8751.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8751.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_8981 = _8981;
                            highp vec2 _8764 = _8637 + vec2(_8714, -_8712);
                            highp float _9003 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8764.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8764.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_9003 = _9003;
                            float _8769 = (((mp_copy_8915 + mp_copy_8937) + mp_copy_8959) + mp_copy_8981) + mp_copy_9003;
                            if ((_8769 < 0.5) || (_8769 > 4.5))
                            {
                                _11680 = _8769 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _8781 = _8637 + _8722;
                            highp float _9025 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8781.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8781.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_9025 = _9025;
                            highp vec2 _8788 = _8637 - _8722;
                            highp float _9047 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8788.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8788.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_9047 = _9047;
                            highp float _8796 = _8722.y;
                            highp float _8799 = _8722.x;
                            highp vec2 _8801 = _8637 + vec2(-_8796, _8799);
                            highp float _9069 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8801.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8801.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_9069 = _9069;
                            highp vec2 _8814 = _8637 + vec2(_8796, -_8799);
                            highp float _9091 = float(_8692 <= textureLod(shadow_map, vec2((_8687 + clamp(_8814.x, 0.0, 1.0)) / _8682, 1.0 - clamp(_8814.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_9091 = _9091;
                            _11680 = (_8769 + (((mp_copy_9025 + mp_copy_9047) + mp_copy_9069) + mp_copy_9091)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _11702 = _5875 * _11680;
                    }
                    else
                    {
                        _11702 = _5875;
                    }
                    _11701 = _11702;
                }
                else
                {
                    _11701 = _5851;
                }
                _11703 = _11705;
                _11700 = _11701;
                _11689 = _5797;
            }
            hp_copy_11703 = _11703;
            highp vec3 _11718 = vec3(0.0);
            highp vec3 _11719 = vec3(0.0);
            do
            {
                float _9174 = max(dot(_11541, _11689), 0.0);
                highp float hp_copy_9174 = _9174;
                if (_9174 <= 0.0)
                {
                    _11719 = vec3(0.0);
                    _11718 = vec3(0.0);
                    break;
                }
                float _9180 = max(_5741, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_9180 = _9180;
                vec3 _9183 = _11689 + mp_copy_11600;
                float _9186 = dot(_9183, _9183);
                vec3 _11716 = vec3(0.0);
                vec3 _11717 = vec3(0.0);
                if (_9186 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _9194 = _9183 * inversesqrt(_9186);
                    float _11715 = 0.0;
                    do
                    {
                        float _9251 = dot(_11541, _9194);
                        if (_9251 <= 0.0)
                        {
                            _11715 = 0.0;
                            break;
                        }
                        float _9258 = _11703 * _11703;
                        vec3 _9261 = cross(_11541, _9194);
                        float _9264 = _9251 * _9258;
                        float _9273 = _9258 / (dot(_9261, _9261) + (_9264 * _9264));
                        _11715 = min((_9273 * _9273) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _9311 = _5737 + ((vec3(1.0) - _5737) * pow(clamp(1.0 - max(dot(_9194, _11600), 0.0), 0.0, 1.0), 5.0));
                    _11717 = (_9311 * min(_11715 * (0.5 / max(mix((2.0 * hp_copy_9174) * _9180, hp_copy_9174 + hp_copy_9180, hp_copy_11703 * hp_copy_11703), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _11716 = _9311;
                }
                else
                {
                    _11717 = vec3(0.0);
                    _11716 = _5737;
                }
                _11719 = (_11717 * _11700) * _9174;
                _11718 = (((((vec3(1.0) - _11716) * (1.0 - _4794)) * _5668) * 0.3183098733425140380859375) * _11700) * _9174;
                break;
            } while(false);
            _12047 = _11646 + (_11718 + _11719);
        }
        _12046 = _12047;
    }
    bool _10203 = false;
    highp vec3 hp_copy_11603 = vec3(0.0);
    mat3 _6110 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _6118 = _6110 * vec3(_11541.x, _11541.y, _11541.z);
    vec3 _6121 = _6110 * reflect(-mp_copy_11600, _11541);
    float _10022 = _6118.y;
    float _10029 = _6118.z;
    float _10036 = _6118.x;
    float _10044 = 1.09254801273345947265625 * _10036;
    vec3 _6124 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _10022))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _10029))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _10036))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_10044 * _10022))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _10022) * _10029))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _10029) * _10029) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_10044 * _10029))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_10036 * _10036) - (_10022 * _10022)))), vec3(0.0));
    highp vec3 hp_copy_6124 = _6124;
    vec3 _11603 = vec3(0.0);
    do
    {
        _10203 = radiance_layout_info.mip_layout > 0.5;
        if (_10203)
        {
            vec2 _10282 = vec2(atan(_6121.z, _6121.x), asin(clamp(_6121.y, -1.0, 1.0)));
            highp vec2 hp_copy_10282 = _10282;
            _11603 = textureLod(prefiltered_radiance, (hp_copy_10282 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_11589, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _10301 = vec2(atan(_6121.z, _6121.x), asin(clamp(_6121.y, -1.0, 1.0)));
        highp vec2 hp_copy_10301 = _10301;
        highp vec2 _10306 = (hp_copy_10301 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _10213 = clamp(_10306.y, 0.00390625, 0.99609375);
        float _10217 = clamp(_11589, 0.0, 1.0) * 7.0;
        float _10219 = floor(_10217);
        highp float _10238 = _10306.x;
        _11603 = mix(textureLod(prefiltered_radiance, vec2(_10238, (_10219 + _10213) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_10238, (min(_10219 + 1.0, 7.0) + _10213) * 0.125), 0.0).xyz, vec3(_10217 - _10219));
        break;
    } while(false);
    hp_copy_11603 = _11603;
    highp vec3 _11609 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_11604 = vec3(0.0);
        vec3 _11604 = vec3(0.0);
        do
        {
            if (_10203)
            {
                vec2 _10411 = vec2(atan(_6121.z, _6121.x), asin(clamp(_6121.y, -1.0, 1.0)));
                highp vec2 hp_copy_10411 = _10411;
                _11604 = textureLod(prefiltered_radiance_b, (hp_copy_10411 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_11589, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _10430 = vec2(atan(_6121.z, _6121.x), asin(clamp(_6121.y, -1.0, 1.0)));
            highp vec2 hp_copy_10430 = _10430;
            highp vec2 _10435 = (hp_copy_10430 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _10342 = clamp(_10435.y, 0.00390625, 0.99609375);
            float _10346 = clamp(_11589, 0.0, 1.0) * 7.0;
            float _10348 = floor(_10346);
            highp float _10367 = _10435.x;
            _11604 = mix(textureLod(prefiltered_radiance_b, vec2(_10367, (_10348 + _10342) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_10367, (min(_10348 + 1.0, 7.0) + _10342) * 0.125), 0.0).xyz, vec3(_10346 - _10348));
            break;
        } while(false);
        hp_copy_11604 = _11604;
        _11609 = hp_copy_11603 + hp_copy_11604;
    }
    else
    {
        _11609 = _11603;
    }
    float _6139 = frag_info.environment_intensity;
    highp float hp_copy_6139 = _6139;
    vec2 _6152 = clamp(vec2(_5745, _11589), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _6154 = texture(brdf_lut, vec2(_6152.x * 0.3333333432674407958984375, _6152.y));
    float _6158 = _6154.x;
    float _6161 = _6154.y;
    vec3 _6163 = ((_5737 + ((max(vec3(1.0 - _11589), _5737) - _5737) * pow(clamp(1.0 - _5745, 0.0, 1.0), 5.0))) * _6158) + vec3(_6161);
    float _6169 = 1.0 - (_6158 + _6161);
    vec3 _6173 = vec3(1.0) - _5737;
    vec3 _6176 = _5737 + (_6173 * vec3(0.0476190485060214996337890625));
    vec3 _6187 = ((_6163 * _6169) * _6176) / (vec3(1.0) - (_6176 * _6169));
    float _6190 = 1.0 - _4794;
    float _11623 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _11623 = clamp((pow(_5741 + _11618, exp2(((-16.0) * _11589) - 1.0)) - 1.0) + _11618, 0.0, 1.0);
    }
    else
    {
        _11623 = _11618;
    }
    highp vec3 _11656 = vec3(0.0);
    if (_5693)
    {
        highp vec3 _11640 = vec3(0.0);
        highp vec3 _11641 = vec3(0.0);
        do
        {
            float _10524 = max(dot(_11541, _11632), 0.0);
            highp float hp_copy_10524 = _10524;
            if (_10524 <= 0.0)
            {
                _11641 = vec3(0.0);
                _11640 = vec3(0.0);
                break;
            }
            float _10530 = max(_5741, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_10530 = _10530;
            vec3 _10533 = _11632 + mp_copy_11600;
            float _10536 = dot(_10533, _10533);
            vec3 _11638 = vec3(0.0);
            vec3 _11639 = vec3(0.0);
            if (_10536 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _10544 = _10533 * inversesqrt(_10536);
                float _11637 = 0.0;
                do
                {
                    float _10601 = dot(_11541, _10544);
                    if (_10601 <= 0.0)
                    {
                        _11637 = 0.0;
                        break;
                    }
                    float _10608 = _11589 * _11589;
                    vec3 _10611 = cross(_11541, _10544);
                    float _10614 = _10601 * _10608;
                    float _10623 = _10608 / (dot(_10611, _10611) + (_10614 * _10614));
                    _11637 = min((_10623 * _10623) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _10661 = _5737 + (_6173 * pow(clamp(1.0 - max(dot(_10544, _11600), 0.0), 0.0, 1.0), 5.0));
                _11639 = (_10661 * min(_11637 * (0.5 / max(mix((2.0 * hp_copy_10524) * _10530, hp_copy_10524 + hp_copy_10530, hp_copy_11589 * hp_copy_11589), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _11638 = _10661;
            }
            else
            {
                _11639 = vec3(0.0);
                _11638 = _5737;
            }
            _11641 = (_11639 * frag_info.directional_light_color.xyz) * _10524;
            _11640 = (((((vec3(1.0) - _11638) * _6190) * _5668) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _10524;
            break;
        } while(false);
        _11656 = _11646 + ((_11640 + _11641) * _5728);
    }
    else
    {
        _11656 = _11646;
    }
    bool _6281 = _FogInfo.params0.y > 0.5;
    bool _6287 = false;
    if (_6281)
    {
        _6287 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _6287 = _6281;
    }
    highp vec3 _11659 = vec3(0.0);
    if (_6287)
    {
        vec3 mp_copy_11657 = vec3(0.0);
        highp vec3 _11657 = vec3(0.0);
        if (_8195)
        {
            _11657 = -view_info.camera_forward.xyz;
        }
        else
        {
            _11657 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_11658 = vec3(0.0);
        mp_copy_11657 = _11657;
        vec3 _6292 = _6110 * (-mp_copy_11657);
        vec3 _11658 = vec3(0.0);
        do
        {
            if (_10203)
            {
                vec2 _10783 = vec2(atan(_6292.z, _6292.x), asin(clamp(_6292.y, -1.0, 1.0)));
                highp vec2 hp_copy_10783 = _10783;
                _11658 = textureLod(prefiltered_radiance, (hp_copy_10783 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _10802 = vec2(atan(_6292.z, _6292.x), asin(clamp(_6292.y, -1.0, 1.0)));
            highp vec2 hp_copy_10802 = _10802;
            highp vec2 _10807 = (hp_copy_10802 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _10714 = clamp(_10807.y, 0.00390625, 0.99609375);
            float _10720 = floor(0.0);
            highp float _10739 = _10807.x;
            _11658 = mix(textureLod(prefiltered_radiance, vec2(_10739, (_10720 + _10714) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_10739, (min(_10720 + 1.0, 7.0) + _10714) * 0.125), 0.0).xyz, vec3(-_10720));
            break;
        } while(false);
        hp_copy_11658 = _11658;
        _11659 = hp_copy_11658 * hp_copy_6139;
    }
    else
    {
        _11659 = _FogInfo.color.xyz;
    }
    highp vec4 _6307 = vec4(min(((((((_6187 + ((_5668 * _6190) * ((vec3(1.0) - _6163) - _6187))) * (hp_copy_6124 * hp_copy_6139)) * vec3(_4828)) + (((_6163 * (_11609 * _6139)) * 1.0) * _11623)) * mix(1.0, _5728, frag_info.radiance_blend.y)) + (_11656 * mix(1.0, _11618, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _11564, vec3(65504.0)), 1.0) * _12098;
    highp vec4 _11674 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _11674 = _6307;
            break;
        }
        int _10851 = int(_FogInfo.params0.x + 0.5);
        if (_10851 == 0)
        {
            _11674 = _6307;
            break;
        }
        highp float _11661 = 0.0;
        if (_8195)
        {
            _11661 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _11661 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_11661 > _FogInfo.params1.w))
        {
            _11674 = _6307;
            break;
        }
        float _11665 = 0.0;
        if (_10851 == 1)
        {
            _11665 = clamp((_11661 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _11666 = 0.0;
            if (_10851 == 2)
            {
                highp float _11664 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _11662 = vec3(0.0);
                    if (_8195)
                    {
                        _11662 = v_position - (view_info.camera_forward.xyz * _11661);
                    }
                    else
                    {
                        _11662 = v_position + v_viewvector;
                    }
                    highp float _10942 = -_FogInfo.params2.y;
                    highp float _10949 = _FogInfo.params1.x * exp(_10942 * (_11662.y - _FogInfo.params2.x));
                    highp float _10966 = _FogInfo.params2.y * (v_position.y - _11662.y);
                    highp float _11663 = 0.0;
                    if (abs(_10966) > 0.00124999997206032276153564453125)
                    {
                        _11663 = (_10949 - (_FogInfo.params1.x * exp(_10942 * (v_position.y - _FogInfo.params2.x)))) / _10966;
                    }
                    else
                    {
                        _11663 = _10949;
                    }
                    _11664 = _11663 * max(_11661 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _11664 = _FogInfo.params1.x * max(_11661 - _FogInfo.params1.y, 0.0);
                }
                _11666 = 1.0 - exp(-_11664);
            }
            else
            {
                highp float _10904 = _FogInfo.params1.x * max(_11661 - _FogInfo.params1.y, 0.0);
                _11666 = 1.0 - exp((-_10904) * _10904);
            }
            _11665 = _11666;
        }
        highp float _11006 = min(_11665, _FogInfo.params0.z);
        if (_11006 <= 0.0)
        {
            _11674 = _6307;
            break;
        }
        highp vec3 _11019 = mix(_FogInfo.color.xyz, _11659, vec3(_FogInfo.params0.w));
        bool _11022 = _FogInfo.sun.w > 0.5;
        bool _11028 = false;
        if (_11022)
        {
            _11028 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _11028 = _11022;
        }
        vec3 _11670 = vec3(0.0);
        if (_11028)
        {
            vec3 mp_copy_11667 = vec3(0.0);
            highp vec3 _11667 = vec3(0.0);
            if (_8195)
            {
                _11667 = -view_info.camera_forward.xyz;
            }
            else
            {
                _11667 = normalize(v_viewvector);
            }
            mp_copy_11667 = _11667;
            highp float _11044 = pow(max(dot(-mp_copy_11667, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_11044 = _11044;
            _11670 = _11019 + ((_FogInfo.sun.xyz * mp_copy_11044) * _FogInfo.params2.z);
        }
        else
        {
            _11670 = _11019;
        }
        highp float _11057 = _6307.w;
        float mp_copy_11057 = _11057;
        _11674 = vec4(mix(_6307.xyz, _11670 * mp_copy_11057, vec3(_11006)), _11057);
        break;
    } while(false);
    vec4 _11676 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _11676 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _11676 = _11674;
        break;
    } while(false);
    frag_color = _11676;
    float _11677 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _11677 = 1.0;
    }
    else
    {
        _11677 = abs(frag_info.fade);
    }
    frag_color *= _11677;
}

