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
    highp float _4881 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4881 = _4881;
    vec3 _4885 = normalize(v_normal) * mp_copy_4881;
    vec4 _4927 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4930 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _14935 = vec2(0.0);
    if (_4930)
    {
        highp vec2 _14934 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _14934 = v_texture_coords_1;
        }
        else
        {
            _14934 = v_texture_coords;
        }
        highp vec2 _5133 = _14934 * texture_transforms.base_color_transform.zw;
        highp float _5139 = _5133.x;
        highp float _5144 = _5133.y;
        _14935 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _5139) + (texture_transforms.base_color_rotation.y * _5144), ((-texture_transforms.base_color_rotation.y) * _5139) + (texture_transforms.base_color_rotation.x * _5144));
    }
    else
    {
        _14935 = v_texture_coords;
    }
    vec4 _4944 = texture(base_color_texture, _14935);
    vec3 _4946 = _4944.xyz;
    float _15826 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4944.w * _4927.w) * frag_info.color.w);
    vec3 _14950 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _14938 = vec2(0.0);
        if (_4930)
        {
            highp vec2 _14937 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _14937 = v_texture_coords_1;
            }
            else
            {
                _14937 = v_texture_coords;
            }
            highp vec2 _5228 = _14937 * texture_transforms.normal_transform.zw;
            highp float _5234 = _5228.x;
            highp float _5239 = _5228.y;
            _14938 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _5234) + (texture_transforms.normal_rotation.y * _5239), ((-texture_transforms.normal_rotation.y) * _5234) + (texture_transforms.normal_rotation.x * _5239));
        }
        else
        {
            _14938 = v_texture_coords;
        }
        vec3 _5284 = ((texture(normal_texture, _14938).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _5288 = _5284.xy * vec2(frag_info.normal_scale);
        vec3 _14478 = _5284;
        _14478.x = _5288.x;
        _14478.y = _5288.y;
        highp vec3 _5294 = -v_viewvector;
        highp vec3 _5384 = dFdx(_5294);
        highp vec3 _5386 = dFdy(_5294);
        highp vec2 _5388 = dFdx(_14938);
        highp vec2 _5390 = dFdy(_14938);
        bvec2 _15828 = bvec2(length(_5388) == 0.0);
        highp vec2 _15829 = vec2(_15828.x ? vec2(1.0, 0.0).x : _5388.x, _15828.y ? vec2(1.0, 0.0).y : _5388.y);
        bvec2 _15830 = bvec2(length(_5390) == 0.0);
        highp vec2 _15831 = vec2(_15830.x ? vec2(0.0, 1.0).x : _5390.x, _15830.y ? vec2(0.0, 1.0).y : _5390.y);
        highp vec3 _5403 = cross(_5386, _4885);
        highp vec3 _5406 = cross(_4885, _5384);
        highp float _5431 = (dot(cross(_5384, _5386), _4885) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _5434 = ((_5403 * _15829.x) + (_5406 * _15831.x)) * _5431;
        highp float _14945 = 0.0;
        if (gl_FrontFacing)
        {
            _14945 = -_5431;
        }
        else
        {
            _14945 = _5431;
        }
        highp vec3 _5444 = ((_5403 * _15829.y) + (_5406 * _15831.y)) * _14945;
        highp float _5453 = inversesqrt(max(max(dot(_5434, _5434), dot(_5444, _5444)), 9.9999996826552253889678874634872e-21));
        vec3 _5325 = v_tangent.xyz - (_4885 * dot(_4885, v_tangent.xyz));
        highp float _5328 = dot(_5325, _5325);
        bool _5330 = _5328 > 1.0000000133514319600180897396058e-10;
        bool _5337 = false;
        if (_5330)
        {
            _5337 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _5337 = _5330;
        }
        mat3 _14948 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_5337)
        {
            highp vec3 _5342 = _5325 * inversesqrt(_5328);
            _14948 = mat3(_5342, normalize(cross(_4885, _5342)) * sign(v_tangent.w), _4885);
        }
        else
        {
            _14948 = mat3(_5434 * _5453, _5444 * _5453, _4885);
        }
        _14950 = normalize(_14948 * _14478);
    }
    else
    {
        _14950 = _4885;
    }
    highp vec2 _14952 = vec2(0.0);
    if (_4930)
    {
        highp vec2 _14951 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _14951 = v_texture_coords_1;
        }
        else
        {
            _14951 = v_texture_coords;
        }
        highp vec2 _5521 = _14951 * texture_transforms.metallic_roughness_transform.zw;
        highp float _5527 = _5521.x;
        highp float _5532 = _5521.y;
        _14952 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _5527) + (texture_transforms.metallic_roughness_rotation.y * _5532), ((-texture_transforms.metallic_roughness_rotation.y) * _5527) + (texture_transforms.metallic_roughness_rotation.x * _5532));
    }
    else
    {
        _14952 = v_texture_coords;
    }
    vec4 _5013 = texture(metallic_roughness_texture, _14952);
    float _5019 = clamp(_5013.z * frag_info.metallic_factor, 0.0, 1.0);
    float _5026 = clamp(_5013.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _14954 = vec2(0.0);
    if (_4930)
    {
        highp vec2 _14953 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _14953 = v_texture_coords_1;
        }
        else
        {
            _14953 = v_texture_coords;
        }
        highp vec2 _5592 = _14953 * texture_transforms.occlusion_transform.zw;
        highp float _5598 = _5592.x;
        highp float _5603 = _5592.y;
        _14954 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _5598) + (texture_transforms.occlusion_rotation.y * _5603), ((-texture_transforms.occlusion_rotation.y) * _5598) + (texture_transforms.occlusion_rotation.x * _5603));
    }
    else
    {
        _14954 = v_texture_coords;
    }
    float _14955 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _14955 = texture(occlusion_texture, _14954).x;
    }
    else
    {
        _14955 = 1.0;
    }
    float _5053 = 1.0 - ((1.0 - _14955) * frag_info.occlusion_strength);
    highp vec2 _14957 = vec2(0.0);
    if (_4930)
    {
        highp vec2 _14956 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _14956 = v_texture_coords_1;
        }
        else
        {
            _14956 = v_texture_coords;
        }
        highp vec2 _5663 = _14956 * texture_transforms.emissive_transform.zw;
        highp float _5669 = _5663.x;
        highp float _5674 = _5663.y;
        _14957 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5669) + (texture_transforms.emissive_rotation.y * _5674), ((-texture_transforms.emissive_rotation.y) * _5669) + (texture_transforms.emissive_rotation.x * _5674));
    }
    else
    {
        _14957 = v_texture_coords;
    }
    vec3 _5072 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _14973 = vec3(0.0);
    if (dot(abs(_5072), vec3(1.0)) > 0.0)
    {
        vec3 _5081 = texture(emissive_texture, _14957).xyz;
        _14973 = mix(_5081 * vec3(0.077399380505084991455078125), pow((_5081 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5081)) * _5072;
    }
    else
    {
        _14973 = vec3(0.0);
    }
    highp float hp_copy_14998 = 0.0;
    vec3 _5855 = vec4((mix(_4946 * vec3(0.077399380505084991455078125), pow((_4946 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4946)) * _4927.xyz) * frag_info.color.xyz, _15826).xyz;
    vec3 _6356 = dFdx(_14950);
    vec3 _6358 = dFdy(_14950);
    float _14998 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _14998 = sqrt(clamp((_5026 * _5026) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_6356, _6356), dot(_6358, _6358))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _14998 = _5026;
    }
    hp_copy_14998 = _14998;
    float _15221 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _15221 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _15221 = _5053;
    }
    bool _5880 = frag_info.has_directional_light > 0.5;
    float _14999 = 0.0;
    vec3 _15294 = vec3(0.0);
    if (_5880)
    {
        highp vec3 _5886 = -normalize(frag_info.directional_light_direction.xyz);
        _15294 = _5886;
        _14999 = dot(_4885, _5886);
    }
    else
    {
        _15294 = vec3(0.0);
        _14999 = 0.0;
    }
    float _5893 = clamp(_14999 * 6.666666507720947265625, 0.0, 1.0);
    bool _5902 = false;
    if (_5880)
    {
        _5902 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5902 = _5880;
    }
    float _15008 = 0.0;
    if (_5902 && (_5893 > 0.0))
    {
        int _6437 = int(frag_info.shadow_cascade_count);
        float _6632 = max(dot(_4885, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6635 = _6632 * _6632;
        highp vec3 _6655 = v_position + (_4885 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6635, 0.0)) / _6635, 8.0))));
        highp float _6443 = frag_info.directional_light_color.w * 0.5;
        float _6445 = frag_info.dielectric_f0.w;
        highp float hp_copy_6445 = _6445;
        float _15000 = 0.0;
        if (_6445 > 0.0)
        {
            _15000 = smoothstep(_6445 - max(frag_info.shadow_fade, hp_copy_6445 * 0.100000001490116119384765625), _6445, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _15000 = 0.0;
        }
        float _15002 = 0.0;
        float _15004 = 0.0;
        if (_15000 < 1.0)
        {
            float _15003 = 0.0;
            float _15005 = 0.0;
            _15005 = 0.0;
            _15003 = 0.0;
            float _15657 = 0.0;
            float _15660 = 0.0;
            for (int _15001 = 0; _15001 < _6437; _15005 = _15660, _15003 = _15657, _15001++)
            {
                if (_15005 < 1.0)
                {
                    highp vec4 _6477 = vec4(_6655, 1.0);
                    highp vec4 _15529 = vec4(0.0);
                    highp float _15532 = 0.0;
                    if (_15001 == 0)
                    {
                        _15532 = frag_info.cascade_box_sizes.x;
                        _15529 = frag_info.light_space_matrix[0] * _6477;
                    }
                    else
                    {
                        highp vec4 _15530 = vec4(0.0);
                        highp float _15533 = 0.0;
                        if (_15001 == 1)
                        {
                            _15533 = frag_info.cascade_box_sizes.y;
                            _15530 = frag_info.light_space_matrix[1] * _6477;
                        }
                        else
                        {
                            highp vec4 _15531 = vec4(0.0);
                            highp float _15534 = 0.0;
                            if (_15001 == 2)
                            {
                                _15534 = frag_info.cascade_box_sizes.z;
                                _15531 = frag_info.light_space_matrix[2] * _6477;
                            }
                            else
                            {
                                _15534 = frag_info.cascade_box_sizes.w;
                                _15531 = frag_info.light_space_matrix[3] * _6477;
                            }
                            _15533 = _15534;
                            _15530 = _15531;
                        }
                        _15532 = _15533;
                        _15529 = _15530;
                    }
                    highp vec3 _6522 = _15529.xyz / vec3(_15529.w);
                    highp vec2 _6525 = _6522.xy * 0.5;
                    highp vec2 _6527 = _6525 + vec2(0.5);
                    highp float _6534 = max(frag_info.shadow_softness / _15532, frag_info.shadow_texel_size);
                    highp float _6536 = _6527.x;
                    bool _6538 = _6536 < _6534;
                    bool _6547 = false;
                    if (!_6538)
                    {
                        _6547 = _6536 > (1.0 - _6534);
                    }
                    else
                    {
                        _6547 = _6538;
                    }
                    bool _6555 = false;
                    if (!_6547)
                    {
                        _6555 = _6527.y < _6534;
                    }
                    else
                    {
                        _6555 = _6547;
                    }
                    bool _6564 = false;
                    if (!_6555)
                    {
                        _6564 = _6527.y > (1.0 - _6534);
                    }
                    else
                    {
                        _6564 = _6555;
                    }
                    bool _6571 = false;
                    if (!_6564)
                    {
                        _6571 = _6522.z < 0.0;
                    }
                    else
                    {
                        _6571 = _6564;
                    }
                    bool _6578 = false;
                    if (!_6571)
                    {
                        _6578 = _6522.z > 1.0;
                    }
                    else
                    {
                        _6578 = _6571;
                    }
                    float _15658 = 0.0;
                    float _15661 = 0.0;
                    if (!_6578)
                    {
                        highp vec2 _6671 = vec2(_6534);
                        highp vec2 _6676 = vec2(_6534 + max(_6443, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6684 = vec2(0.5) - _6525;
                        highp vec2 _6686 = smoothstep(_6671, _6676, _6527) * smoothstep(_6671, _6676, _6684);
                        float _15535 = 0.0;
                        if (_6443 > 0.0)
                        {
                            _15535 = _6686.x * _6686.y;
                        }
                        else
                        {
                            _15535 = 1.0;
                        }
                        float _6587 = min(_15535, 1.0 - _15005);
                        float _15659 = 0.0;
                        float _15662 = 0.0;
                        if (_6587 > 0.0)
                        {
                            highp float _6825 = _6522.z - (frag_info.shadow_bias / (7.0 * _15532));
                            highp float _6831 = 1.0 / (float(_6437) + frag_info.spot_shadow_params.x);
                            highp float _6833 = frag_info.directional_light_direction.w;
                            float mp_copy_6833 = _6833;
                            float _6839 = step(0.5, mp_copy_6833) * (1.0 - step(1.5, mp_copy_6833));
                            float _15565 = 0.0;
                            float _15569 = 0.0;
                            if (_6839 < 0.5)
                            {
                                highp float _6850 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6850 = _6850;
                                _15569 = sin(mp_copy_6850);
                                _15565 = cos(mp_copy_6850);
                            }
                            else
                            {
                                _15569 = 0.0;
                                _15565 = 1.0;
                            }
                            highp float _15572 = 0.0;
                            if ((_6833 > 1.5) && (_6833 < 2.5))
                            {
                                highp float _6874 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6879 = max(_6874 * _6825, frag_info.shadow_texel_size);
                                float _15561 = 0.0;
                                highp float _15562 = 0.0;
                                _15562 = 0.0;
                                _15561 = 0.0;
                                highp float _6901 = 0.0;
                                float _6904 = 0.0;
                                for (int _15560 = 0; _15560 < 9; _15562 = _6901, _15561 = _6904, _15560++)
                                {
                                    vec2 _15651 = vec2(0.0);
                                    do
                                    {
                                        if (_15560 == 0)
                                        {
                                            _15651 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_15560 == 1)
                                        {
                                            _15651 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_15560 == 2)
                                        {
                                            _15651 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_15560 == 3)
                                        {
                                            _15651 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_15560 == 4)
                                        {
                                            _15651 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_15560 == 5)
                                        {
                                            _15651 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_15560 == 6)
                                        {
                                            _15651 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_15560 == 7)
                                        {
                                            _15651 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_15560 == 8)
                                        {
                                            _15651 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_15560 == 9)
                                        {
                                            _15651 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_15560 == 10)
                                        {
                                            _15651 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_15560 == 11)
                                        {
                                            _15651 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_15560 == 12)
                                        {
                                            _15651 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_15560 == 13)
                                        {
                                            _15651 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_15560 == 14)
                                        {
                                            _15651 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_15560 == 15)
                                        {
                                            _15651 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _15651 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _7208 = clamp(_6527 + (vec2((_15651.x * _15565) - (_15651.y * _15569), (_15651.x * _15569) + (_15651.y * _15565)) * _6879), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _7217 = _7208.y;
                                    highp vec2 _7218 = vec2((float(_15001) + _7208.x) * _6831, _7217);
                                    _7218.y = 1.0 - _7217;
                                    highp vec4 _7225 = textureLod(shadow_map, _7218, 0.0);
                                    highp float _7226 = _7225.x;
                                    highp float _6896 = step(_7226, _6825);
                                    float mp_copy_6896 = _6896;
                                    _6901 = _15562 + (_7226 * _6896);
                                    _6904 = _15561 + mp_copy_6896;
                                }
                                highp float _15563 = 0.0;
                                if (_15561 > 0.0)
                                {
                                    _15563 = _15562 / _15561;
                                }
                                else
                                {
                                    _15563 = _6825;
                                }
                                _15572 = clamp(_6874 * max(_6825 - _15563, 0.0), frag_info.shadow_texel_size, _6534);
                            }
                            else
                            {
                                _15572 = _6534;
                            }
                            bool _6935 = _6833 > 2.5;
                            bool _15573 = false;
                            float _15598 = 0.0;
                            if ((_6833 < 1.5) || _6935)
                            {
                                highp vec2 _7259 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _7263 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _7264 = clamp(_6527, _7259, _7263);
                                highp float _7266 = float(_15001);
                                highp float _7273 = _7264.y;
                                highp vec2 _7274 = vec2((_7266 + _7264.x) * _6831, _7273);
                                _7274.y = 1.0 - _7273;
                                highp float _7286 = float(_6825 <= textureLod(shadow_map, _7274, 0.0).x);
                                float mp_copy_7286 = _7286;
                                float _7296 = (-1.0) * _15565;
                                float _7300 = (-1.0) * _15569;
                                highp vec2 _7324 = clamp(_6527 + (vec2(_7296 - _7300, _7300 + _7296) * _15572), _7259, _7263);
                                highp float _7333 = _7324.y;
                                highp vec2 _7334 = vec2((_7266 + _7324.x) * _6831, _7333);
                                _7334.y = 1.0 - _7333;
                                highp float _7346 = float(_6825 <= textureLod(shadow_map, _7334, 0.0).x);
                                float mp_copy_7346 = _7346;
                                highp vec2 _7384 = clamp(_6527 + (vec2(_15565 - _7300, _15569 + _7296) * _15572), _7259, _7263);
                                highp float _7393 = _7384.y;
                                highp vec2 _7394 = vec2((_7266 + _7384.x) * _6831, _7393);
                                _7394.y = 1.0 - _7393;
                                highp float _7406 = float(_6825 <= textureLod(shadow_map, _7394, 0.0).x);
                                float mp_copy_7406 = _7406;
                                highp vec2 _7444 = clamp(_6527 + (vec2(_7296 - _15569, _7300 + _15565) * _15572), _7259, _7263);
                                highp float _7453 = _7444.y;
                                highp vec2 _7454 = vec2((_7266 + _7444.x) * _6831, _7453);
                                _7454.y = 1.0 - _7453;
                                highp float _7466 = float(_6825 <= textureLod(shadow_map, _7454, 0.0).x);
                                float mp_copy_7466 = _7466;
                                highp vec2 _7504 = clamp(_6527 + (vec2(_15565 - _15569, _15569 + _15565) * _15572), _7259, _7263);
                                highp float _7513 = _7504.y;
                                highp vec2 _7514 = vec2((_7266 + _7504.x) * _6831, _7513);
                                _7514.y = 1.0 - _7513;
                                highp float _7526 = float(_6825 <= textureLod(shadow_map, _7514, 0.0).x);
                                float mp_copy_7526 = _7526;
                                float _6981 = (((mp_copy_7286 + mp_copy_7346) + mp_copy_7406) + mp_copy_7466) + mp_copy_7526;
                                _15598 = _6981 * 0.20000000298023223876953125;
                                _15573 = (_6981 < 0.5) || (_6981 > 4.5);
                            }
                            else
                            {
                                _15598 = 0.0;
                                _15573 = false;
                            }
                            float _15596 = 0.0;
                            if (_15573)
                            {
                                _15596 = _15598;
                            }
                            else
                            {
                                float _15597 = 0.0;
                                if (_6935)
                                {
                                    highp vec2 _7745 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7749 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7750 = clamp(_6527 + (vec2(-0.707099974155426025390625) * _15572), _7745, _7749);
                                    highp vec2 _7761 = (vec2(_7750.x, 1.0 - _7750.y) / _7745) - vec2(0.5);
                                    highp vec2 _7763 = floor(_7761);
                                    highp vec2 _7766 = _7761 - _7763;
                                    highp vec2 _7771 = (_7763 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7773 = float(_15001);
                                    highp vec2 _7781 = vec2((_7773 + _7771.x) * _6831, _7771.y);
                                    highp float _7785 = frag_info.shadow_texel_size * _6831;
                                    highp vec2 _7788 = vec2(_7785, frag_info.shadow_texel_size);
                                    highp vec2 _7797 = vec2(_7785, 0.0);
                                    highp vec2 _7805 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7834 = _7766.x;
                                    highp float _7843 = mix(mix(float(_6825 <= textureLod(shadow_map, _7781, 0.0).x), float(_6825 <= textureLod(shadow_map, _7781 + _7797, 0.0).x), _7834), mix(float(_6825 <= textureLod(shadow_map, _7781 + _7805, 0.0).x), float(_6825 <= textureLod(shadow_map, _7781 + _7788, 0.0).x), _7834), _7766.y);
                                    float mp_copy_7843 = _7843;
                                    highp vec2 _7877 = clamp(_6527 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _15572), _7745, _7749);
                                    highp vec2 _7888 = (vec2(_7877.x, 1.0 - _7877.y) / _7745) - vec2(0.5);
                                    highp vec2 _7890 = floor(_7888);
                                    highp vec2 _7893 = _7888 - _7890;
                                    highp vec2 _7898 = (_7890 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7908 = vec2((_7773 + _7898.x) * _6831, _7898.y);
                                    highp float _7961 = _7893.x;
                                    highp float _7970 = mix(mix(float(_6825 <= textureLod(shadow_map, _7908, 0.0).x), float(_6825 <= textureLod(shadow_map, _7908 + _7797, 0.0).x), _7961), mix(float(_6825 <= textureLod(shadow_map, _7908 + _7805, 0.0).x), float(_6825 <= textureLod(shadow_map, _7908 + _7788, 0.0).x), _7961), _7893.y);
                                    float mp_copy_7970 = _7970;
                                    highp vec2 _8004 = clamp(_6527 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _15572), _7745, _7749);
                                    highp vec2 _8015 = (vec2(_8004.x, 1.0 - _8004.y) / _7745) - vec2(0.5);
                                    highp vec2 _8017 = floor(_8015);
                                    highp vec2 _8020 = _8015 - _8017;
                                    highp vec2 _8025 = (_8017 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8035 = vec2((_7773 + _8025.x) * _6831, _8025.y);
                                    highp float _8088 = _8020.x;
                                    highp float _8097 = mix(mix(float(_6825 <= textureLod(shadow_map, _8035, 0.0).x), float(_6825 <= textureLod(shadow_map, _8035 + _7797, 0.0).x), _8088), mix(float(_6825 <= textureLod(shadow_map, _8035 + _7805, 0.0).x), float(_6825 <= textureLod(shadow_map, _8035 + _7788, 0.0).x), _8088), _8020.y);
                                    float mp_copy_8097 = _8097;
                                    highp vec2 _8131 = clamp(_6527 + (vec2(0.707099974155426025390625) * _15572), _7745, _7749);
                                    highp vec2 _8142 = (vec2(_8131.x, 1.0 - _8131.y) / _7745) - vec2(0.5);
                                    highp vec2 _8144 = floor(_8142);
                                    highp vec2 _8147 = _8142 - _8144;
                                    highp vec2 _8152 = (_8144 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8162 = vec2((_7773 + _8152.x) * _6831, _8152.y);
                                    highp float _8215 = _8147.x;
                                    highp float _8224 = mix(mix(float(_6825 <= textureLod(shadow_map, _8162, 0.0).x), float(_6825 <= textureLod(shadow_map, _8162 + _7797, 0.0).x), _8215), mix(float(_6825 <= textureLod(shadow_map, _8162 + _7805, 0.0).x), float(_6825 <= textureLod(shadow_map, _8162 + _7788, 0.0).x), _8215), _8147.y);
                                    float mp_copy_8224 = _8224;
                                    _15597 = (((mp_copy_7843 + mp_copy_7970) + mp_copy_8097) + mp_copy_8224) * 0.25;
                                }
                                else
                                {
                                    int _6997 = (_6839 > 0.5) ? 17 : 16;
                                    float _15592 = 0.0;
                                    _15592 = 0.0;
                                    float _7025 = 0.0;
                                    for (int _15574 = 0; _15574 < 17; _15592 = _7025, _15574++)
                                    {
                                        if (_15574 >= _6997)
                                        {
                                            break;
                                        }
                                        vec2 _15575 = vec2(0.0);
                                        do
                                        {
                                            if (_15574 == 0)
                                            {
                                                _15575 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_15574 == 1)
                                            {
                                                _15575 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_15574 == 2)
                                            {
                                                _15575 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_15574 == 3)
                                            {
                                                _15575 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_15574 == 4)
                                            {
                                                _15575 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_15574 == 5)
                                            {
                                                _15575 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_15574 == 6)
                                            {
                                                _15575 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_15574 == 7)
                                            {
                                                _15575 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_15574 == 8)
                                            {
                                                _15575 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_15574 == 9)
                                            {
                                                _15575 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_15574 == 10)
                                            {
                                                _15575 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_15574 == 11)
                                            {
                                                _15575 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_15574 == 12)
                                            {
                                                _15575 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_15574 == 13)
                                            {
                                                _15575 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_15574 == 14)
                                            {
                                                _15575 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_15574 == 15)
                                            {
                                                _15575 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _15575 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _15577 = vec2(0.0);
                                        do
                                        {
                                            if (_15574 < 3)
                                            {
                                                _15577 = vec2(float(_15574) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_15574 < 6)
                                            {
                                                _15577 = vec2((float(_15574 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_15574 < 11)
                                            {
                                                _15577 = vec2((float(_15574 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_15574 < 14)
                                            {
                                                _15577 = vec2((float(_15574 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _15577 = vec2(float(_15574 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _7014 = mix(_15575, _15577, vec2(_6839));
                                        float _7665 = _7014.x;
                                        float _7669 = _7014.y;
                                        highp vec2 _7695 = clamp(_6527 + (vec2((_7665 * _15565) - (_7669 * _15569), (_7665 * _15569) + (_7669 * _15565)) * _15572), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7704 = _7695.y;
                                        highp vec2 _7705 = vec2((float(_15001) + _7695.x) * _6831, _7704);
                                        _7705.y = 1.0 - _7704;
                                        highp float _7717 = float(_6825 <= textureLod(shadow_map, _7705, 0.0).x);
                                        float mp_copy_7717 = _7717;
                                        _7025 = _15592 + mp_copy_7717;
                                    }
                                    _15597 = _15592 / float(_6997);
                                }
                                _15596 = _15597;
                            }
                            bool _7070 = _15001 == (_6437 - 1);
                            bool _7076 = false;
                            if (_7070)
                            {
                                _7076 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _7076 = _7070;
                            }
                            float _15599 = 0.0;
                            if (_7076)
                            {
                                highp vec2 _7083 = vec2(frag_info.shadow_fade / _15532);
                                highp vec2 _7091 = smoothstep(vec2(0.0), _7083, _6527) * smoothstep(vec2(0.0), _7083, _6684);
                                _15599 = mix(1.0, _15596, _7091.x * _7091.y);
                            }
                            else
                            {
                                _15599 = _15596;
                            }
                            _15662 = _15005 + _6587;
                            _15659 = _15003 + (_6587 * _15599);
                        }
                        else
                        {
                            _15662 = _15005;
                            _15659 = _15003;
                        }
                        _15661 = _15662;
                        _15658 = _15659;
                    }
                    else
                    {
                        _15661 = _15005;
                        _15658 = _15003;
                    }
                    _15660 = _15661;
                    _15657 = _15658;
                }
                else
                {
                    _15660 = _15005;
                    _15657 = _15003;
                }
            }
            _15004 = _15005;
            _15002 = _15003;
        }
        else
        {
            _15004 = 0.0;
            _15002 = 0.0;
        }
        _15008 = mix(_15002 + (1.0 - _15004), 1.0, _15000);
    }
    else
    {
        _15008 = 1.0;
    }
    vec3 mp_copy_15009 = vec3(0.0);
    float _5915 = _5893 * _15008;
    bool _8232 = view_info.camera_forward.w > 0.5;
    highp vec3 _15009 = vec3(0.0);
    if (_8232)
    {
        _15009 = -view_info.camera_forward.xyz;
    }
    else
    {
        _15009 = normalize(v_viewvector);
    }
    highp float _8276 = 0.0;
    mp_copy_15009 = _15009;
    vec3 _5924 = mix(frag_info.dielectric_f0.xyz, _5855, vec3(_5019));
    float _5928 = max(dot(_14950, _15009), 0.0);
    float _5932 = max(dot(_4885, _15009), 0.0);
    highp vec2 _15010 = vec2(0.0);
    do
    {
        _8276 = frag_info.punctual_dims.x;
        if (_8276 < 0.5)
        {
            _15010 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _8288 = v_position - frag_info.camera_position.xyz;
            highp float _8303 = dot(_8288, frag_info.camera_forward.xyz);
            highp float _8309 = max(_8303, 9.9999997473787516355514526367188e-05);
            highp vec2 _8412 = (vec3(dot(_8288, frag_info.camera_right.xyz), dot(_8288, frag_info.camera_up.xyz), _8309).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_8309, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _8427 = float(int(((((clamp(floor((log2(max(_8303 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_8412.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_8412.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _15010 = vec2(textureLod(punctual_index, vec2((mod(_8427, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8427 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _15010 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5941 = int(_15010.x + 0.5);
    mediump int _5945 = int(_15010.y + 0.5);
    highp vec3 _15367 = vec3(0.0);
    _15367 = vec3(0.0);
    highp vec3 _15773 = vec3(0.0);
    for (int _15011 = 0; _15011 < _5945; _15367 = _15773, _15011++)
    {
        highp float hp_copy_15481 = 0.0;
        highp float _8460 = float(_5941 + _15011);
        highp float _8491 = (float(int(textureLod(punctual_index, vec2((mod(_8460, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8460 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _8276;
        highp vec4 _8495 = textureLod(punctual_lights, vec2(0.0625, _8491), 0.0);
        highp vec4 _8512 = textureLod(punctual_lights, vec2(0.1875, _8491), 0.0);
        highp float _5963 = _8495.w;
        highp vec3 _5965 = _8512.xyz;
        vec3 _15467 = vec3(0.0);
        highp vec3 _15478 = vec3(0.0);
        float _15481 = 0.0;
        if (_5963 < 0.5)
        {
            _15481 = _14998;
            _15478 = _5965;
            _15467 = -normalize(textureLod(punctual_lights, vec2(0.3125, _8491), 0.0).xyz);
        }
        else
        {
            highp vec3 _5973 = _8495.xyz - v_position;
            highp float _5976 = dot(_5973, _5973);
            highp float _5980 = inversesqrt(max(_5976, 9.9999999392252902907785028219223e-09));
            highp vec3 _5981 = _5973 * _5980;
            vec3 mp_copy_5981 = _5981;
            highp float _5983 = _8512.w;
            highp float _5988 = (_5976 * _5983) * _5983;
            highp float _5993 = clamp(1.0 - (_5988 * _5988), 0.0, 1.0);
            float mp_copy_5993 = _5993;
            if (_5993 <= 0.0)
            {
                _15773 = _15367;
                continue;
            }
            highp vec4 _8529 = textureLod(punctual_lights, vec2(0.4375, _8491), 0.0);
            highp float _6001 = _8529.w;
            float _15483 = 0.0;
            if (_6001 > 0.0)
            {
                highp float _6028 = (_14998 * _14998) + ((_6001 * 0.5) * _5980);
                float mp_copy_6028 = _6028;
                _15483 = sqrt(min(mp_copy_6028, 1.0));
            }
            else
            {
                _15483 = _14998;
            }
            highp vec3 _6035 = _5965 * ((mp_copy_5993 * mp_copy_5993) / max(pow(max(_5976, _6001 * _6001), _8529.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _15479 = vec3(0.0);
            if (_5963 > 1.5)
            {
                highp vec4 _8546 = textureLod(punctual_lights, vec2(0.3125, _8491), 0.0);
                highp float _6054 = clamp((dot(normalize(_8546.xyz), -mp_copy_5981) * _8546.w) + _8529.x, 0.0, 1.0);
                float mp_copy_6054 = _6054;
                highp vec3 _6059 = _6035 * (mp_copy_6054 * mp_copy_6054);
                if (_6054 <= 0.0)
                {
                    _15773 = _15367;
                    continue;
                }
                bool _6065 = _6054 > 0.0;
                bool _6071 = false;
                if (_6065)
                {
                    _6071 = _8529.y > (-0.5);
                }
                else
                {
                    _6071 = _6065;
                }
                bool _6077 = false;
                if (_6071)
                {
                    _6077 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _6077 = _6071;
                }
                highp vec3 _15480 = vec3(0.0);
                if (_6077)
                {
                    float _15458 = 0.0;
                    do
                    {
                        highp vec4 _8658 = mat4(textureLod(punctual_lights, vec2(0.5625, _8491), 0.0), textureLod(punctual_lights, vec2(0.6875, _8491), 0.0), textureLod(punctual_lights, vec2(0.8125, _8491), 0.0), textureLod(punctual_lights, vec2(0.9375, _8491), 0.0)) * vec4(v_position + (_4885 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8660 = _8658.w;
                        if (_8660 <= 0.0)
                        {
                            _15458 = 1.0;
                            break;
                        }
                        highp vec3 _8669 = _8658.xyz / vec3(_8660);
                        highp vec2 _8674 = (_8669.xy * 0.5) + vec2(0.5);
                        highp float _8676 = _8674.x;
                        bool _8677 = _8676 < 0.0;
                        bool _8684 = false;
                        if (!_8677)
                        {
                            _8684 = _8676 > 1.0;
                        }
                        else
                        {
                            _8684 = _8677;
                        }
                        bool _8691 = false;
                        if (!_8684)
                        {
                            _8691 = _8674.y < 0.0;
                        }
                        else
                        {
                            _8691 = _8684;
                        }
                        bool _8698 = false;
                        if (!_8691)
                        {
                            _8698 = _8674.y > 1.0;
                        }
                        else
                        {
                            _8698 = _8691;
                        }
                        bool _8705 = false;
                        if (!_8698)
                        {
                            _8705 = _8669.z < 0.0;
                        }
                        else
                        {
                            _8705 = _8698;
                        }
                        bool _8712 = false;
                        if (!_8705)
                        {
                            _8712 = _8669.z > 1.0;
                        }
                        else
                        {
                            _8712 = _8705;
                        }
                        if (_8712)
                        {
                            _15458 = 1.0;
                            break;
                        }
                        highp float _8719 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8724 = frag_info.shadow_cascade_count + float(int(_8529.y + 0.5));
                        highp float _8729 = _8669.z - frag_info.spot_shadow_params.y;
                        highp float _8740 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8740 = _8740;
                        highp vec2 _8747 = vec2(cos(mp_copy_8740), sin(mp_copy_8740)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8749 = _8747.x;
                        highp float _8751 = _8747.y;
                        highp vec2 _8759 = vec2(_8749 - _8751, _8749 + _8751) * 0.707106769084930419921875;
                        highp float _8952 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8676, 0.0, 1.0)) / _8719, 1.0 - clamp(_8674.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8952 = _8952;
                        highp vec2 _8767 = _8674 + _8747;
                        highp float _8974 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8767.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8767.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8974 = _8974;
                        highp vec2 _8775 = _8674 - _8747;
                        highp float _8996 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8775.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8775.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8996 = _8996;
                        highp vec2 _8788 = _8674 + vec2(-_8751, _8749);
                        highp float _9018 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8788.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8788.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9018 = _9018;
                        highp vec2 _8801 = _8674 + vec2(_8751, -_8749);
                        highp float _9040 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8801.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8801.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9040 = _9040;
                        float _8806 = (((mp_copy_8952 + mp_copy_8974) + mp_copy_8996) + mp_copy_9018) + mp_copy_9040;
                        if ((_8806 < 0.5) || (_8806 > 4.5))
                        {
                            _15458 = _8806 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8818 = _8674 + _8759;
                        highp float _9062 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8818.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8818.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9062 = _9062;
                        highp vec2 _8825 = _8674 - _8759;
                        highp float _9084 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8825.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8825.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9084 = _9084;
                        highp float _8833 = _8759.y;
                        highp float _8836 = _8759.x;
                        highp vec2 _8838 = _8674 + vec2(-_8833, _8836);
                        highp float _9106 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8838.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8838.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9106 = _9106;
                        highp vec2 _8851 = _8674 + vec2(_8833, -_8836);
                        highp float _9128 = float(_8729 <= textureLod(shadow_map, vec2((_8724 + clamp(_8851.x, 0.0, 1.0)) / _8719, 1.0 - clamp(_8851.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9128 = _9128;
                        _15458 = (_8806 + (((mp_copy_9062 + mp_copy_9084) + mp_copy_9106) + mp_copy_9128)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _15480 = _6059 * _15458;
                }
                else
                {
                    _15480 = _6059;
                }
                _15479 = _15480;
            }
            else
            {
                _15479 = _6035;
            }
            _15481 = _15483;
            _15478 = _15479;
            _15467 = _5981;
        }
        hp_copy_15481 = _15481;
        highp vec3 _15496 = vec3(0.0);
        highp vec3 _15497 = vec3(0.0);
        do
        {
            float _9211 = max(dot(_14950, _15467), 0.0);
            highp float hp_copy_9211 = _9211;
            if (_9211 <= 0.0)
            {
                _15497 = vec3(0.0);
                _15496 = vec3(0.0);
                break;
            }
            float _9217 = max(_5928, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9217 = _9217;
            vec3 _9220 = _15467 + mp_copy_15009;
            float _9223 = dot(_9220, _9220);
            vec3 _15494 = vec3(0.0);
            vec3 _15495 = vec3(0.0);
            if (_9223 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9231 = _9220 * inversesqrt(_9223);
                float _15493 = 0.0;
                do
                {
                    float _9288 = dot(_14950, _9231);
                    if (_9288 <= 0.0)
                    {
                        _15493 = 0.0;
                        break;
                    }
                    float _9295 = _15481 * _15481;
                    vec3 _9298 = cross(_14950, _9231);
                    float _9301 = _9288 * _9295;
                    float _9310 = _9295 / (dot(_9298, _9298) + (_9301 * _9301));
                    _15493 = min((_9310 * _9310) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9348 = _5924 + ((vec3(1.0) - _5924) * pow(clamp(1.0 - max(dot(_9231, _15009), 0.0), 0.0, 1.0), 5.0));
                _15495 = (_9348 * min(_15493 * (0.5 / max(mix((2.0 * hp_copy_9211) * _9217, hp_copy_9211 + hp_copy_9217, hp_copy_15481 * hp_copy_15481), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _15494 = _9348;
            }
            else
            {
                _15495 = vec3(0.0);
                _15494 = _5924;
            }
            _15497 = (_15495 * _15478) * _9211;
            _15496 = (((((vec3(1.0) - _15494) * (1.0 - _5019)) * _5855) * 0.3183098733425140380859375) * _15478) * _9211;
            break;
        } while(false);
        _15773 = _15367 + (_15496 + _15497);
    }
    bool _9572 = false;
    highp vec3 hp_copy_15012 = vec3(0.0);
    mat3 _6132 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _6140 = _6132 * vec3(_14950.x, _14950.y, _14950.z);
    vec3 _6143 = _6132 * reflect(-mp_copy_15009, _14950);
    float _9391 = _6140.y;
    float _9398 = _6140.z;
    float _9405 = _6140.x;
    float _9413 = 1.09254801273345947265625 * _9405;
    vec3 _6146 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _9391))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _9398))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _9405))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_9413 * _9391))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _9391) * _9398))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _9398) * _9398) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_9413 * _9398))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_9405 * _9405) - (_9391 * _9391)))), vec3(0.0));
    highp vec3 hp_copy_6146 = _6146;
    vec3 _15012 = vec3(0.0);
    do
    {
        _9572 = radiance_layout_info.mip_layout > 0.5;
        if (_9572)
        {
            vec2 _9651 = vec2(atan(_6143.z, _6143.x), asin(clamp(_6143.y, -1.0, 1.0)));
            highp vec2 hp_copy_9651 = _9651;
            _15012 = textureLod(prefiltered_radiance, (hp_copy_9651 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_14998, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9670 = vec2(atan(_6143.z, _6143.x), asin(clamp(_6143.y, -1.0, 1.0)));
        highp vec2 hp_copy_9670 = _9670;
        highp vec2 _9675 = (hp_copy_9670 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _9582 = clamp(_9675.y, 0.00390625, 0.99609375);
        float _9586 = clamp(_14998, 0.0, 1.0) * 7.0;
        float _9588 = floor(_9586);
        highp float _9607 = _9675.x;
        _15012 = mix(textureLod(prefiltered_radiance, vec2(_9607, (_9588 + _9582) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9607, (min(_9588 + 1.0, 7.0) + _9582) * 0.125), 0.0).xyz, vec3(_9586 - _9588));
        break;
    } while(false);
    hp_copy_15012 = _15012;
    highp vec3 _15018 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_15013 = vec3(0.0);
        vec3 _15013 = vec3(0.0);
        do
        {
            if (_9572)
            {
                vec2 _9780 = vec2(atan(_6143.z, _6143.x), asin(clamp(_6143.y, -1.0, 1.0)));
                highp vec2 hp_copy_9780 = _9780;
                _15013 = textureLod(prefiltered_radiance_b, (hp_copy_9780 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_14998, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9799 = vec2(atan(_6143.z, _6143.x), asin(clamp(_6143.y, -1.0, 1.0)));
            highp vec2 hp_copy_9799 = _9799;
            highp vec2 _9804 = (hp_copy_9799 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9711 = clamp(_9804.y, 0.00390625, 0.99609375);
            float _9715 = clamp(_14998, 0.0, 1.0) * 7.0;
            float _9717 = floor(_9715);
            highp float _9736 = _9804.x;
            _15013 = mix(textureLod(prefiltered_radiance_b, vec2(_9736, (_9717 + _9711) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9736, (min(_9717 + 1.0, 7.0) + _9711) * 0.125), 0.0).xyz, vec3(_9715 - _9717));
            break;
        } while(false);
        hp_copy_15013 = _15013;
        _15018 = hp_copy_15012 + hp_copy_15013;
    }
    else
    {
        _15018 = _15012;
    }
    highp float _9817 = 0.0;
    float _6161 = frag_info.environment_intensity;
    highp float hp_copy_6161 = _6161;
    highp vec3 _6163 = hp_copy_6146 * hp_copy_6161;
    float _15019 = 0.0;
    do
    {
        _9817 = frag_info.gi_grid.w;
        if (_9817 <= 0.0)
        {
            _15019 = 0.0;
            break;
        }
        highp vec3 _9830 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _9838 = min(_9830, (frag_info.gi_counts.xyz - vec3(1.0)) - _9830);
        _15019 = clamp(min(_9838.x, min(_9838.y, _9838.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _15210 = vec3(0.0);
    if (_15019 > 0.0)
    {
        highp vec3 _9930 = v_position + (((_14950 * 0.20000000298023223876953125) + (mp_copy_15009 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _9933 = _9930 / frag_info.gi_grid.xyz;
        highp vec3 _9935 = floor(_9933);
        highp vec3 _9941 = clamp(_9933 - _9935, vec3(0.0), vec3(1.0));
        vec3 mp_copy_9941 = _9941;
        highp vec3 _10063 = _9935 - frag_info.gi_anchor.xyz;
        bool _10066 = any(lessThan(_10063, vec3(0.0)));
        bool _10074 = false;
        if (!_10066)
        {
            _10074 = any(greaterThanEqual(_10063, frag_info.gi_counts.xyz));
        }
        else
        {
            _10074 = _10066;
        }
        vec3 mp_copy_15020 = vec3(0.0);
        highp float _10075 = _10074 ? 0.0 : 1.0;
        float mp_copy_10075 = _10075;
        vec3 _10077 = vec3(1.0) - mp_copy_9941;
        vec3 _10081 = max(_10077, vec3(0.001000000047497451305389404296875));
        highp vec3 _10097 = (_9935 * frag_info.gi_grid.xyz) - _9930;
        highp float _10099 = length(_10097);
        highp vec3 _15020 = vec3(0.0);
        if (_10099 > 9.9999997473787516355514526367188e-06)
        {
            _15020 = _10097 / vec3(_10099);
        }
        else
        {
            _15020 = _14950;
        }
        mp_copy_15020 = _15020;
        float _10117 = pow((dot(_15020, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10242 = _9935 - (frag_info.gi_counts.xyz * floor(_9935 / frag_info.gi_counts.xyz));
        highp float _10258 = _10242.x + (frag_info.gi_counts.x * (_10242.y + (frag_info.gi_counts.y * _10242.z)));
        bool _10128 = frag_info.gi_visibility.x > 0.0;
        float _15025 = 0.0;
        if (_10128)
        {
            highp float _10266 = floor(_10258 / frag_info.gi_counts.w);
            highp vec2 _10280 = vec2((_10258 - (_10266 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10266 * 16.0));
            vec3 _10140 = -mp_copy_15020;
            vec3 _10328 = _10140 / vec3((abs(_10140.x) + abs(_10140.y)) + abs(_10140.z));
            vec2 _15021 = vec2(0.0);
            if (_10328.z >= 0.0)
            {
                _15021 = _10328.xy;
            }
            else
            {
                _15021 = (vec2(1.0) - abs(_10328.yx)) * vec2((_10328.x >= 0.0) ? 1.0 : (-1.0), (_10328.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10144 = texture(irradiance_field, clamp((_10280 + vec2(1.0)) + (clamp((_15021 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10280 + vec2(0.5), _10280 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10149 = _10144.x * frag_info.gi_visibility.z;
            highp float _10161 = abs((_10149 * _10149) - ((_10144.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10167 = (_10099 - _10149) - frag_info.gi_visibility.y;
            highp float _15022 = 0.0;
            if (_10167 <= 0.0)
            {
                _15022 = 1.0;
            }
            else
            {
                _15022 = _10161 / (_10161 + (_10167 * _10167));
            }
            _15025 = _10117 * mix(1.0, max(0.0500000007450580596923828125, (_15022 * _15022) * _15022), frag_info.gi_visibility.x);
        }
        else
        {
            _15025 = _10117;
        }
        float _10195 = max(9.9999999747524270787835121154785e-07, _15025);
        float _15026 = 0.0;
        if (_10195 < 0.20000000298023223876953125)
        {
            _15026 = _10195 * ((_10195 * _10195) * 25.0);
        }
        else
        {
            _15026 = _10195;
        }
        float _10210 = _15026 * (((_10081.x * _10081.y) * _10081.z) * mp_copy_10075);
        highp float _10369 = floor(_10258 / frag_info.gi_counts.w);
        highp vec2 _10383 = vec2((_10258 - (_10369 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10369 * 8.0));
        vec3 _10431 = _14950 / vec3((abs(_14950.x) + abs(_14950.y)) + abs(_14950.z));
        bool _10434 = _10431.z >= 0.0;
        vec2 _15027 = vec2(0.0);
        if (_10434)
        {
            _15027 = _10431.xy;
        }
        else
        {
            _15027 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10222 = texture(irradiance_field, clamp((_10383 + vec2(1.0)) + (clamp((_15027 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10383 + vec2(0.5), _10383 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10517 = _9935 + vec3(1.0, 0.0, 0.0);
        highp vec3 _10522 = _10517 - frag_info.gi_anchor.xyz;
        bool _10525 = any(lessThan(_10522, vec3(0.0)));
        bool _10533 = false;
        if (!_10525)
        {
            _10533 = any(greaterThanEqual(_10522, frag_info.gi_counts.xyz));
        }
        else
        {
            _10533 = _10525;
        }
        vec3 mp_copy_15029 = vec3(0.0);
        highp float _10534 = _10533 ? 0.0 : 1.0;
        float mp_copy_10534 = _10534;
        vec3 _10540 = max(mix(_10077, mp_copy_9941, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10556 = (_10517 * frag_info.gi_grid.xyz) - _9930;
        highp float _10558 = length(_10556);
        highp vec3 _15029 = vec3(0.0);
        if (_10558 > 9.9999997473787516355514526367188e-06)
        {
            _15029 = _10556 / vec3(_10558);
        }
        else
        {
            _15029 = _14950;
        }
        mp_copy_15029 = _15029;
        float _10576 = pow((dot(_15029, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10701 = _10517 - (frag_info.gi_counts.xyz * floor(_10517 / frag_info.gi_counts.xyz));
        highp float _10717 = _10701.x + (frag_info.gi_counts.x * (_10701.y + (frag_info.gi_counts.y * _10701.z)));
        float _15034 = 0.0;
        if (_10128)
        {
            highp float _10725 = floor(_10717 / frag_info.gi_counts.w);
            highp vec2 _10739 = vec2((_10717 - (_10725 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10725 * 16.0));
            vec3 _10599 = -mp_copy_15029;
            vec3 _10787 = _10599 / vec3((abs(_10599.x) + abs(_10599.y)) + abs(_10599.z));
            vec2 _15030 = vec2(0.0);
            if (_10787.z >= 0.0)
            {
                _15030 = _10787.xy;
            }
            else
            {
                _15030 = (vec2(1.0) - abs(_10787.yx)) * vec2((_10787.x >= 0.0) ? 1.0 : (-1.0), (_10787.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10603 = texture(irradiance_field, clamp((_10739 + vec2(1.0)) + (clamp((_15030 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10739 + vec2(0.5), _10739 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10608 = _10603.x * frag_info.gi_visibility.z;
            highp float _10620 = abs((_10608 * _10608) - ((_10603.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10626 = (_10558 - _10608) - frag_info.gi_visibility.y;
            highp float _15031 = 0.0;
            if (_10626 <= 0.0)
            {
                _15031 = 1.0;
            }
            else
            {
                _15031 = _10620 / (_10620 + (_10626 * _10626));
            }
            _15034 = _10576 * mix(1.0, max(0.0500000007450580596923828125, (_15031 * _15031) * _15031), frag_info.gi_visibility.x);
        }
        else
        {
            _15034 = _10576;
        }
        float _10654 = max(9.9999999747524270787835121154785e-07, _15034);
        float _15035 = 0.0;
        if (_10654 < 0.20000000298023223876953125)
        {
            _15035 = _10654 * ((_10654 * _10654) * 25.0);
        }
        else
        {
            _15035 = _10654;
        }
        float _10669 = _15035 * (((_10540.x * _10540.y) * _10540.z) * mp_copy_10534);
        highp float _10828 = floor(_10717 / frag_info.gi_counts.w);
        highp vec2 _10842 = vec2((_10717 - (_10828 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10828 * 8.0));
        vec2 _15036 = vec2(0.0);
        if (_10434)
        {
            _15036 = _10431.xy;
        }
        else
        {
            _15036 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10681 = texture(irradiance_field, clamp((_10842 + vec2(1.0)) + (clamp((_15036 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10842 + vec2(0.5), _10842 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10976 = _9935 + vec3(0.0, 1.0, 0.0);
        highp vec3 _10981 = _10976 - frag_info.gi_anchor.xyz;
        bool _10984 = any(lessThan(_10981, vec3(0.0)));
        bool _10992 = false;
        if (!_10984)
        {
            _10992 = any(greaterThanEqual(_10981, frag_info.gi_counts.xyz));
        }
        else
        {
            _10992 = _10984;
        }
        vec3 mp_copy_15038 = vec3(0.0);
        highp float _10993 = _10992 ? 0.0 : 1.0;
        float mp_copy_10993 = _10993;
        vec3 _10999 = max(mix(_10077, mp_copy_9941, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11015 = (_10976 * frag_info.gi_grid.xyz) - _9930;
        highp float _11017 = length(_11015);
        highp vec3 _15038 = vec3(0.0);
        if (_11017 > 9.9999997473787516355514526367188e-06)
        {
            _15038 = _11015 / vec3(_11017);
        }
        else
        {
            _15038 = _14950;
        }
        mp_copy_15038 = _15038;
        float _11035 = pow((dot(_15038, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11160 = _10976 - (frag_info.gi_counts.xyz * floor(_10976 / frag_info.gi_counts.xyz));
        highp float _11176 = _11160.x + (frag_info.gi_counts.x * (_11160.y + (frag_info.gi_counts.y * _11160.z)));
        float _15043 = 0.0;
        if (_10128)
        {
            highp float _11184 = floor(_11176 / frag_info.gi_counts.w);
            highp vec2 _11198 = vec2((_11176 - (_11184 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11184 * 16.0));
            vec3 _11058 = -mp_copy_15038;
            vec3 _11246 = _11058 / vec3((abs(_11058.x) + abs(_11058.y)) + abs(_11058.z));
            vec2 _15039 = vec2(0.0);
            if (_11246.z >= 0.0)
            {
                _15039 = _11246.xy;
            }
            else
            {
                _15039 = (vec2(1.0) - abs(_11246.yx)) * vec2((_11246.x >= 0.0) ? 1.0 : (-1.0), (_11246.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11062 = texture(irradiance_field, clamp((_11198 + vec2(1.0)) + (clamp((_15039 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11198 + vec2(0.5), _11198 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11067 = _11062.x * frag_info.gi_visibility.z;
            highp float _11079 = abs((_11067 * _11067) - ((_11062.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11085 = (_11017 - _11067) - frag_info.gi_visibility.y;
            highp float _15040 = 0.0;
            if (_11085 <= 0.0)
            {
                _15040 = 1.0;
            }
            else
            {
                _15040 = _11079 / (_11079 + (_11085 * _11085));
            }
            _15043 = _11035 * mix(1.0, max(0.0500000007450580596923828125, (_15040 * _15040) * _15040), frag_info.gi_visibility.x);
        }
        else
        {
            _15043 = _11035;
        }
        float _11113 = max(9.9999999747524270787835121154785e-07, _15043);
        float _15044 = 0.0;
        if (_11113 < 0.20000000298023223876953125)
        {
            _15044 = _11113 * ((_11113 * _11113) * 25.0);
        }
        else
        {
            _15044 = _11113;
        }
        float _11128 = _15044 * (((_10999.x * _10999.y) * _10999.z) * mp_copy_10993);
        highp float _11287 = floor(_11176 / frag_info.gi_counts.w);
        highp vec2 _11301 = vec2((_11176 - (_11287 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11287 * 8.0));
        vec2 _15045 = vec2(0.0);
        if (_10434)
        {
            _15045 = _10431.xy;
        }
        else
        {
            _15045 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11140 = texture(irradiance_field, clamp((_11301 + vec2(1.0)) + (clamp((_15045 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11301 + vec2(0.5), _11301 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11435 = _9935 + vec3(1.0, 1.0, 0.0);
        highp vec3 _11440 = _11435 - frag_info.gi_anchor.xyz;
        bool _11443 = any(lessThan(_11440, vec3(0.0)));
        bool _11451 = false;
        if (!_11443)
        {
            _11451 = any(greaterThanEqual(_11440, frag_info.gi_counts.xyz));
        }
        else
        {
            _11451 = _11443;
        }
        vec3 mp_copy_15047 = vec3(0.0);
        highp float _11452 = _11451 ? 0.0 : 1.0;
        float mp_copy_11452 = _11452;
        vec3 _11458 = max(mix(_10077, mp_copy_9941, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11474 = (_11435 * frag_info.gi_grid.xyz) - _9930;
        highp float _11476 = length(_11474);
        highp vec3 _15047 = vec3(0.0);
        if (_11476 > 9.9999997473787516355514526367188e-06)
        {
            _15047 = _11474 / vec3(_11476);
        }
        else
        {
            _15047 = _14950;
        }
        mp_copy_15047 = _15047;
        float _11494 = pow((dot(_15047, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11619 = _11435 - (frag_info.gi_counts.xyz * floor(_11435 / frag_info.gi_counts.xyz));
        highp float _11635 = _11619.x + (frag_info.gi_counts.x * (_11619.y + (frag_info.gi_counts.y * _11619.z)));
        float _15052 = 0.0;
        if (_10128)
        {
            highp float _11643 = floor(_11635 / frag_info.gi_counts.w);
            highp vec2 _11657 = vec2((_11635 - (_11643 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11643 * 16.0));
            vec3 _11517 = -mp_copy_15047;
            vec3 _11705 = _11517 / vec3((abs(_11517.x) + abs(_11517.y)) + abs(_11517.z));
            vec2 _15048 = vec2(0.0);
            if (_11705.z >= 0.0)
            {
                _15048 = _11705.xy;
            }
            else
            {
                _15048 = (vec2(1.0) - abs(_11705.yx)) * vec2((_11705.x >= 0.0) ? 1.0 : (-1.0), (_11705.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11521 = texture(irradiance_field, clamp((_11657 + vec2(1.0)) + (clamp((_15048 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11657 + vec2(0.5), _11657 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11526 = _11521.x * frag_info.gi_visibility.z;
            highp float _11538 = abs((_11526 * _11526) - ((_11521.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11544 = (_11476 - _11526) - frag_info.gi_visibility.y;
            highp float _15049 = 0.0;
            if (_11544 <= 0.0)
            {
                _15049 = 1.0;
            }
            else
            {
                _15049 = _11538 / (_11538 + (_11544 * _11544));
            }
            _15052 = _11494 * mix(1.0, max(0.0500000007450580596923828125, (_15049 * _15049) * _15049), frag_info.gi_visibility.x);
        }
        else
        {
            _15052 = _11494;
        }
        float _11572 = max(9.9999999747524270787835121154785e-07, _15052);
        float _15053 = 0.0;
        if (_11572 < 0.20000000298023223876953125)
        {
            _15053 = _11572 * ((_11572 * _11572) * 25.0);
        }
        else
        {
            _15053 = _11572;
        }
        float _11587 = _15053 * (((_11458.x * _11458.y) * _11458.z) * mp_copy_11452);
        highp float _11746 = floor(_11635 / frag_info.gi_counts.w);
        highp vec2 _11760 = vec2((_11635 - (_11746 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11746 * 8.0));
        vec2 _15054 = vec2(0.0);
        if (_10434)
        {
            _15054 = _10431.xy;
        }
        else
        {
            _15054 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11599 = texture(irradiance_field, clamp((_11760 + vec2(1.0)) + (clamp((_15054 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11760 + vec2(0.5), _11760 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11894 = _9935 + vec3(0.0, 0.0, 1.0);
        highp vec3 _11899 = _11894 - frag_info.gi_anchor.xyz;
        bool _11902 = any(lessThan(_11899, vec3(0.0)));
        bool _11910 = false;
        if (!_11902)
        {
            _11910 = any(greaterThanEqual(_11899, frag_info.gi_counts.xyz));
        }
        else
        {
            _11910 = _11902;
        }
        vec3 mp_copy_15056 = vec3(0.0);
        highp float _11911 = _11910 ? 0.0 : 1.0;
        float mp_copy_11911 = _11911;
        vec3 _11917 = max(mix(_10077, mp_copy_9941, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11933 = (_11894 * frag_info.gi_grid.xyz) - _9930;
        highp float _11935 = length(_11933);
        highp vec3 _15056 = vec3(0.0);
        if (_11935 > 9.9999997473787516355514526367188e-06)
        {
            _15056 = _11933 / vec3(_11935);
        }
        else
        {
            _15056 = _14950;
        }
        mp_copy_15056 = _15056;
        float _11953 = pow((dot(_15056, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12078 = _11894 - (frag_info.gi_counts.xyz * floor(_11894 / frag_info.gi_counts.xyz));
        highp float _12094 = _12078.x + (frag_info.gi_counts.x * (_12078.y + (frag_info.gi_counts.y * _12078.z)));
        float _15061 = 0.0;
        if (_10128)
        {
            highp float _12102 = floor(_12094 / frag_info.gi_counts.w);
            highp vec2 _12116 = vec2((_12094 - (_12102 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12102 * 16.0));
            vec3 _11976 = -mp_copy_15056;
            vec3 _12164 = _11976 / vec3((abs(_11976.x) + abs(_11976.y)) + abs(_11976.z));
            vec2 _15057 = vec2(0.0);
            if (_12164.z >= 0.0)
            {
                _15057 = _12164.xy;
            }
            else
            {
                _15057 = (vec2(1.0) - abs(_12164.yx)) * vec2((_12164.x >= 0.0) ? 1.0 : (-1.0), (_12164.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11980 = texture(irradiance_field, clamp((_12116 + vec2(1.0)) + (clamp((_15057 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12116 + vec2(0.5), _12116 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11985 = _11980.x * frag_info.gi_visibility.z;
            highp float _11997 = abs((_11985 * _11985) - ((_11980.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12003 = (_11935 - _11985) - frag_info.gi_visibility.y;
            highp float _15058 = 0.0;
            if (_12003 <= 0.0)
            {
                _15058 = 1.0;
            }
            else
            {
                _15058 = _11997 / (_11997 + (_12003 * _12003));
            }
            _15061 = _11953 * mix(1.0, max(0.0500000007450580596923828125, (_15058 * _15058) * _15058), frag_info.gi_visibility.x);
        }
        else
        {
            _15061 = _11953;
        }
        float _12031 = max(9.9999999747524270787835121154785e-07, _15061);
        float _15062 = 0.0;
        if (_12031 < 0.20000000298023223876953125)
        {
            _15062 = _12031 * ((_12031 * _12031) * 25.0);
        }
        else
        {
            _15062 = _12031;
        }
        float _12046 = _15062 * (((_11917.x * _11917.y) * _11917.z) * mp_copy_11911);
        highp float _12205 = floor(_12094 / frag_info.gi_counts.w);
        highp vec2 _12219 = vec2((_12094 - (_12205 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12205 * 8.0));
        vec2 _15063 = vec2(0.0);
        if (_10434)
        {
            _15063 = _10431.xy;
        }
        else
        {
            _15063 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12058 = texture(irradiance_field, clamp((_12219 + vec2(1.0)) + (clamp((_15063 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12219 + vec2(0.5), _12219 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12353 = _9935 + vec3(1.0, 0.0, 1.0);
        highp vec3 _12358 = _12353 - frag_info.gi_anchor.xyz;
        bool _12361 = any(lessThan(_12358, vec3(0.0)));
        bool _12369 = false;
        if (!_12361)
        {
            _12369 = any(greaterThanEqual(_12358, frag_info.gi_counts.xyz));
        }
        else
        {
            _12369 = _12361;
        }
        vec3 mp_copy_15065 = vec3(0.0);
        highp float _12370 = _12369 ? 0.0 : 1.0;
        float mp_copy_12370 = _12370;
        vec3 _12376 = max(mix(_10077, mp_copy_9941, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _12392 = (_12353 * frag_info.gi_grid.xyz) - _9930;
        highp float _12394 = length(_12392);
        highp vec3 _15065 = vec3(0.0);
        if (_12394 > 9.9999997473787516355514526367188e-06)
        {
            _15065 = _12392 / vec3(_12394);
        }
        else
        {
            _15065 = _14950;
        }
        mp_copy_15065 = _15065;
        float _12412 = pow((dot(_15065, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12537 = _12353 - (frag_info.gi_counts.xyz * floor(_12353 / frag_info.gi_counts.xyz));
        highp float _12553 = _12537.x + (frag_info.gi_counts.x * (_12537.y + (frag_info.gi_counts.y * _12537.z)));
        float _15070 = 0.0;
        if (_10128)
        {
            highp float _12561 = floor(_12553 / frag_info.gi_counts.w);
            highp vec2 _12575 = vec2((_12553 - (_12561 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12561 * 16.0));
            vec3 _12435 = -mp_copy_15065;
            vec3 _12623 = _12435 / vec3((abs(_12435.x) + abs(_12435.y)) + abs(_12435.z));
            vec2 _15066 = vec2(0.0);
            if (_12623.z >= 0.0)
            {
                _15066 = _12623.xy;
            }
            else
            {
                _15066 = (vec2(1.0) - abs(_12623.yx)) * vec2((_12623.x >= 0.0) ? 1.0 : (-1.0), (_12623.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12439 = texture(irradiance_field, clamp((_12575 + vec2(1.0)) + (clamp((_15066 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12575 + vec2(0.5), _12575 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12444 = _12439.x * frag_info.gi_visibility.z;
            highp float _12456 = abs((_12444 * _12444) - ((_12439.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12462 = (_12394 - _12444) - frag_info.gi_visibility.y;
            highp float _15067 = 0.0;
            if (_12462 <= 0.0)
            {
                _15067 = 1.0;
            }
            else
            {
                _15067 = _12456 / (_12456 + (_12462 * _12462));
            }
            _15070 = _12412 * mix(1.0, max(0.0500000007450580596923828125, (_15067 * _15067) * _15067), frag_info.gi_visibility.x);
        }
        else
        {
            _15070 = _12412;
        }
        float _12490 = max(9.9999999747524270787835121154785e-07, _15070);
        float _15071 = 0.0;
        if (_12490 < 0.20000000298023223876953125)
        {
            _15071 = _12490 * ((_12490 * _12490) * 25.0);
        }
        else
        {
            _15071 = _12490;
        }
        float _12505 = _15071 * (((_12376.x * _12376.y) * _12376.z) * mp_copy_12370);
        highp float _12664 = floor(_12553 / frag_info.gi_counts.w);
        highp vec2 _12678 = vec2((_12553 - (_12664 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12664 * 8.0));
        vec2 _15072 = vec2(0.0);
        if (_10434)
        {
            _15072 = _10431.xy;
        }
        else
        {
            _15072 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12517 = texture(irradiance_field, clamp((_12678 + vec2(1.0)) + (clamp((_15072 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12678 + vec2(0.5), _12678 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12812 = _9935 + vec3(0.0, 1.0, 1.0);
        highp vec3 _12817 = _12812 - frag_info.gi_anchor.xyz;
        bool _12820 = any(lessThan(_12817, vec3(0.0)));
        bool _12828 = false;
        if (!_12820)
        {
            _12828 = any(greaterThanEqual(_12817, frag_info.gi_counts.xyz));
        }
        else
        {
            _12828 = _12820;
        }
        vec3 mp_copy_15074 = vec3(0.0);
        highp float _12829 = _12828 ? 0.0 : 1.0;
        float mp_copy_12829 = _12829;
        vec3 _12835 = max(mix(_10077, mp_copy_9941, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _12851 = (_12812 * frag_info.gi_grid.xyz) - _9930;
        highp float _12853 = length(_12851);
        highp vec3 _15074 = vec3(0.0);
        if (_12853 > 9.9999997473787516355514526367188e-06)
        {
            _15074 = _12851 / vec3(_12853);
        }
        else
        {
            _15074 = _14950;
        }
        mp_copy_15074 = _15074;
        float _12871 = pow((dot(_15074, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12996 = _12812 - (frag_info.gi_counts.xyz * floor(_12812 / frag_info.gi_counts.xyz));
        highp float _13012 = _12996.x + (frag_info.gi_counts.x * (_12996.y + (frag_info.gi_counts.y * _12996.z)));
        float _15079 = 0.0;
        if (_10128)
        {
            highp float _13020 = floor(_13012 / frag_info.gi_counts.w);
            highp vec2 _13034 = vec2((_13012 - (_13020 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13020 * 16.0));
            vec3 _12894 = -mp_copy_15074;
            vec3 _13082 = _12894 / vec3((abs(_12894.x) + abs(_12894.y)) + abs(_12894.z));
            vec2 _15075 = vec2(0.0);
            if (_13082.z >= 0.0)
            {
                _15075 = _13082.xy;
            }
            else
            {
                _15075 = (vec2(1.0) - abs(_13082.yx)) * vec2((_13082.x >= 0.0) ? 1.0 : (-1.0), (_13082.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12898 = texture(irradiance_field, clamp((_13034 + vec2(1.0)) + (clamp((_15075 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13034 + vec2(0.5), _13034 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12903 = _12898.x * frag_info.gi_visibility.z;
            highp float _12915 = abs((_12903 * _12903) - ((_12898.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12921 = (_12853 - _12903) - frag_info.gi_visibility.y;
            highp float _15076 = 0.0;
            if (_12921 <= 0.0)
            {
                _15076 = 1.0;
            }
            else
            {
                _15076 = _12915 / (_12915 + (_12921 * _12921));
            }
            _15079 = _12871 * mix(1.0, max(0.0500000007450580596923828125, (_15076 * _15076) * _15076), frag_info.gi_visibility.x);
        }
        else
        {
            _15079 = _12871;
        }
        float _12949 = max(9.9999999747524270787835121154785e-07, _15079);
        float _15080 = 0.0;
        if (_12949 < 0.20000000298023223876953125)
        {
            _15080 = _12949 * ((_12949 * _12949) * 25.0);
        }
        else
        {
            _15080 = _12949;
        }
        float _12964 = _15080 * (((_12835.x * _12835.y) * _12835.z) * mp_copy_12829);
        highp float _13123 = floor(_13012 / frag_info.gi_counts.w);
        highp vec2 _13137 = vec2((_13012 - (_13123 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13123 * 8.0));
        vec2 _15081 = vec2(0.0);
        if (_10434)
        {
            _15081 = _10431.xy;
        }
        else
        {
            _15081 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12976 = texture(irradiance_field, clamp((_13137 + vec2(1.0)) + (clamp((_15081 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13137 + vec2(0.5), _13137 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13271 = _9935 + vec3(1.0);
        highp vec3 _13276 = _13271 - frag_info.gi_anchor.xyz;
        bool _13279 = any(lessThan(_13276, vec3(0.0)));
        bool _13287 = false;
        if (!_13279)
        {
            _13287 = any(greaterThanEqual(_13276, frag_info.gi_counts.xyz));
        }
        else
        {
            _13287 = _13279;
        }
        vec3 mp_copy_15083 = vec3(0.0);
        highp float _13288 = _13287 ? 0.0 : 1.0;
        float mp_copy_13288 = _13288;
        vec3 _13294 = max(mp_copy_9941, vec3(0.001000000047497451305389404296875));
        highp vec3 _13310 = (_13271 * frag_info.gi_grid.xyz) - _9930;
        highp float _13312 = length(_13310);
        highp vec3 _15083 = vec3(0.0);
        if (_13312 > 9.9999997473787516355514526367188e-06)
        {
            _15083 = _13310 / vec3(_13312);
        }
        else
        {
            _15083 = _14950;
        }
        mp_copy_15083 = _15083;
        float _13330 = pow((dot(_15083, _14950) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13455 = _13271 - (frag_info.gi_counts.xyz * floor(_13271 / frag_info.gi_counts.xyz));
        highp float _13471 = _13455.x + (frag_info.gi_counts.x * (_13455.y + (frag_info.gi_counts.y * _13455.z)));
        float _15088 = 0.0;
        if (_10128)
        {
            highp float _13479 = floor(_13471 / frag_info.gi_counts.w);
            highp vec2 _13493 = vec2((_13471 - (_13479 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13479 * 16.0));
            vec3 _13353 = -mp_copy_15083;
            vec3 _13541 = _13353 / vec3((abs(_13353.x) + abs(_13353.y)) + abs(_13353.z));
            vec2 _15084 = vec2(0.0);
            if (_13541.z >= 0.0)
            {
                _15084 = _13541.xy;
            }
            else
            {
                _15084 = (vec2(1.0) - abs(_13541.yx)) * vec2((_13541.x >= 0.0) ? 1.0 : (-1.0), (_13541.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13357 = texture(irradiance_field, clamp((_13493 + vec2(1.0)) + (clamp((_15084 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13493 + vec2(0.5), _13493 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13362 = _13357.x * frag_info.gi_visibility.z;
            highp float _13374 = abs((_13362 * _13362) - ((_13357.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13380 = (_13312 - _13362) - frag_info.gi_visibility.y;
            highp float _15085 = 0.0;
            if (_13380 <= 0.0)
            {
                _15085 = 1.0;
            }
            else
            {
                _15085 = _13374 / (_13374 + (_13380 * _13380));
            }
            _15088 = _13330 * mix(1.0, max(0.0500000007450580596923828125, (_15085 * _15085) * _15085), frag_info.gi_visibility.x);
        }
        else
        {
            _15088 = _13330;
        }
        float _13408 = max(9.9999999747524270787835121154785e-07, _15088);
        float _15089 = 0.0;
        if (_13408 < 0.20000000298023223876953125)
        {
            _15089 = _13408 * ((_13408 * _13408) * 25.0);
        }
        else
        {
            _15089 = _13408;
        }
        float _13423 = _15089 * (((_13294.x * _13294.y) * _13294.z) * mp_copy_13288);
        highp float _13582 = floor(_13471 / frag_info.gi_counts.w);
        highp vec2 _13596 = vec2((_13471 - (_13582 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13582 * 8.0));
        vec2 _15090 = vec2(0.0);
        if (_10434)
        {
            _15090 = _10431.xy;
        }
        else
        {
            _15090 = (vec2(1.0) - abs(_10431.yx)) * vec2((_10431.x >= 0.0) ? 1.0 : (-1.0), (_10431.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9988 = ((((((vec4(max(_10222.xyz, vec3(0.0)) * _10210, _10210) + vec4(max(_10681.xyz, vec3(0.0)) * _10669, _10669)) + vec4(max(_11140.xyz, vec3(0.0)) * _11128, _11128)) + vec4(max(_11599.xyz, vec3(0.0)) * _11587, _11587)) + vec4(max(_12058.xyz, vec3(0.0)) * _12046, _12046)) + vec4(max(_12517.xyz, vec3(0.0)) * _12505, _12505)) + vec4(max(_12976.xyz, vec3(0.0)) * _12964, _12964)) + vec4(max(texture(irradiance_field, clamp((_13596 + vec2(1.0)) + (clamp((_15090 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13596 + vec2(0.5), _13596 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _13423, _13423);
        highp float _9990 = _9988.w;
        highp vec3 _15092 = vec3(0.0);
        if (_9990 > 9.9999999747524270787835121154785e-07)
        {
            _15092 = _9988.xyz / vec3(_9990);
        }
        else
        {
            _15092 = vec3(0.0);
        }
        _15210 = mix(_6163, _15092 * _9817, vec3(_15019));
    }
    else
    {
        _15210 = _6163;
    }
    vec2 _6189 = clamp(vec2(_5932, _14998), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _6191 = texture(brdf_lut, vec2(_6189.x * 0.3333333432674407958984375, _6189.y));
    float _6195 = _6191.x;
    float _6198 = _6191.y;
    vec3 _6200 = ((_5924 + ((max(vec3(1.0 - _14998), _5924) - _5924) * pow(clamp(1.0 - _5932, 0.0, 1.0), 5.0))) * _6195) + vec3(_6198);
    float _6206 = 1.0 - (_6195 + _6198);
    vec3 _6210 = vec3(1.0) - _5924;
    vec3 _6213 = _5924 + (_6210 * vec3(0.0476190485060214996337890625));
    vec3 _6224 = ((_6200 * _6206) * _6213) / (vec3(1.0) - (_6213 * _6206));
    float _6227 = 1.0 - _5019;
    float _15283 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _15283 = clamp((pow(_5928 + _15221, exp2(((-16.0) * _14998) - 1.0)) - 1.0) + _15221, 0.0, 1.0);
    }
    else
    {
        _15283 = _15221;
    }
    highp vec3 _15434 = vec3(0.0);
    if (_5880)
    {
        highp vec3 _15359 = vec3(0.0);
        highp vec3 _15360 = vec3(0.0);
        do
        {
            float _13765 = max(dot(_14950, _15294), 0.0);
            highp float hp_copy_13765 = _13765;
            if (_13765 <= 0.0)
            {
                _15360 = vec3(0.0);
                _15359 = vec3(0.0);
                break;
            }
            float _13771 = max(_5928, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_13771 = _13771;
            vec3 _13774 = _15294 + mp_copy_15009;
            float _13777 = dot(_13774, _13774);
            vec3 _15357 = vec3(0.0);
            vec3 _15358 = vec3(0.0);
            if (_13777 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _13785 = _13774 * inversesqrt(_13777);
                float _15356 = 0.0;
                do
                {
                    float _13842 = dot(_14950, _13785);
                    if (_13842 <= 0.0)
                    {
                        _15356 = 0.0;
                        break;
                    }
                    float _13849 = _14998 * _14998;
                    vec3 _13852 = cross(_14950, _13785);
                    float _13855 = _13842 * _13849;
                    float _13864 = _13849 / (dot(_13852, _13852) + (_13855 * _13855));
                    _15356 = min((_13864 * _13864) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _13902 = _5924 + (_6210 * pow(clamp(1.0 - max(dot(_13785, _15009), 0.0), 0.0, 1.0), 5.0));
                _15358 = (_13902 * min(_15356 * (0.5 / max(mix((2.0 * hp_copy_13765) * _13771, hp_copy_13765 + hp_copy_13771, hp_copy_14998 * hp_copy_14998), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _15357 = _13902;
            }
            else
            {
                _15358 = vec3(0.0);
                _15357 = _5924;
            }
            _15360 = (_15358 * frag_info.directional_light_color.xyz) * _13765;
            _15359 = (((((vec3(1.0) - _15357) * _6227) * _5855) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _13765;
            break;
        } while(false);
        _15434 = _15367 + ((_15359 + _15360) * _5915);
    }
    else
    {
        _15434 = _15367;
    }
    bool _6318 = _FogInfo.params0.y > 0.5;
    bool _6324 = false;
    if (_6318)
    {
        _6324 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _6324 = _6318;
    }
    highp vec3 _15437 = vec3(0.0);
    if (_6324)
    {
        vec3 mp_copy_15435 = vec3(0.0);
        highp vec3 _15435 = vec3(0.0);
        if (_8232)
        {
            _15435 = -view_info.camera_forward.xyz;
        }
        else
        {
            _15435 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_15436 = vec3(0.0);
        mp_copy_15435 = _15435;
        vec3 _6329 = _6132 * (-mp_copy_15435);
        vec3 _15436 = vec3(0.0);
        do
        {
            if (_9572)
            {
                vec2 _14024 = vec2(atan(_6329.z, _6329.x), asin(clamp(_6329.y, -1.0, 1.0)));
                highp vec2 hp_copy_14024 = _14024;
                _15436 = textureLod(prefiltered_radiance, (hp_copy_14024 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _14043 = vec2(atan(_6329.z, _6329.x), asin(clamp(_6329.y, -1.0, 1.0)));
            highp vec2 hp_copy_14043 = _14043;
            highp vec2 _14048 = (hp_copy_14043 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _13955 = clamp(_14048.y, 0.00390625, 0.99609375);
            float _13961 = floor(0.0);
            highp float _13980 = _14048.x;
            _15436 = mix(textureLod(prefiltered_radiance, vec2(_13980, (_13961 + _13955) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_13980, (min(_13961 + 1.0, 7.0) + _13955) * 0.125), 0.0).xyz, vec3(-_13961));
            break;
        } while(false);
        hp_copy_15436 = _15436;
        _15437 = hp_copy_15436 * hp_copy_6161;
    }
    else
    {
        _15437 = _FogInfo.color.xyz;
    }
    highp vec4 _6344 = vec4(min(((((((_6224 + ((_5855 * _6227) * ((vec3(1.0) - _6200) - _6224))) * _15210) * vec3(_5053)) + (((_6200 * (_15018 * _6161)) * 1.0) * _15283)) * mix(1.0, _5915, frag_info.radiance_blend.y)) + (_15434 * mix(1.0, _15221, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _14973, vec3(65504.0)), 1.0) * _15826;
    highp vec4 _15452 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _15452 = _6344;
            break;
        }
        int _14092 = int(_FogInfo.params0.x + 0.5);
        if (_14092 == 0)
        {
            _15452 = _6344;
            break;
        }
        highp float _15439 = 0.0;
        if (_8232)
        {
            _15439 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _15439 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_15439 > _FogInfo.params1.w))
        {
            _15452 = _6344;
            break;
        }
        float _15443 = 0.0;
        if (_14092 == 1)
        {
            _15443 = clamp((_15439 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _15444 = 0.0;
            if (_14092 == 2)
            {
                highp float _15442 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _15440 = vec3(0.0);
                    if (_8232)
                    {
                        _15440 = v_position - (view_info.camera_forward.xyz * _15439);
                    }
                    else
                    {
                        _15440 = v_position + v_viewvector;
                    }
                    highp float _14183 = -_FogInfo.params2.y;
                    highp float _14190 = _FogInfo.params1.x * exp(_14183 * (_15440.y - _FogInfo.params2.x));
                    highp float _14207 = _FogInfo.params2.y * (v_position.y - _15440.y);
                    highp float _15441 = 0.0;
                    if (abs(_14207) > 0.00124999997206032276153564453125)
                    {
                        _15441 = (_14190 - (_FogInfo.params1.x * exp(_14183 * (v_position.y - _FogInfo.params2.x)))) / _14207;
                    }
                    else
                    {
                        _15441 = _14190;
                    }
                    _15442 = _15441 * max(_15439 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _15442 = _FogInfo.params1.x * max(_15439 - _FogInfo.params1.y, 0.0);
                }
                _15444 = 1.0 - exp(-_15442);
            }
            else
            {
                highp float _14145 = _FogInfo.params1.x * max(_15439 - _FogInfo.params1.y, 0.0);
                _15444 = 1.0 - exp((-_14145) * _14145);
            }
            _15443 = _15444;
        }
        highp float _14247 = min(_15443, _FogInfo.params0.z);
        if (_14247 <= 0.0)
        {
            _15452 = _6344;
            break;
        }
        highp vec3 _14260 = mix(_FogInfo.color.xyz, _15437, vec3(_FogInfo.params0.w));
        bool _14263 = _FogInfo.sun.w > 0.5;
        bool _14269 = false;
        if (_14263)
        {
            _14269 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _14269 = _14263;
        }
        vec3 _15448 = vec3(0.0);
        if (_14269)
        {
            vec3 mp_copy_15445 = vec3(0.0);
            highp vec3 _15445 = vec3(0.0);
            if (_8232)
            {
                _15445 = -view_info.camera_forward.xyz;
            }
            else
            {
                _15445 = normalize(v_viewvector);
            }
            mp_copy_15445 = _15445;
            highp float _14285 = pow(max(dot(-mp_copy_15445, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_14285 = _14285;
            _15448 = _14260 + ((_FogInfo.sun.xyz * mp_copy_14285) * _FogInfo.params2.z);
        }
        else
        {
            _15448 = _14260;
        }
        highp float _14298 = _6344.w;
        float mp_copy_14298 = _14298;
        _15452 = vec4(mix(_6344.xyz, _15448 * mp_copy_14298, vec3(_14247)), _14298);
        break;
    } while(false);
    vec4 _15454 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _15454 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _15454 = _15452;
        break;
    } while(false);
    frag_color = _15454;
    float _15455 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _15455 = 1.0;
    }
    else
    {
        _15455 = abs(frag_info.fade);
    }
    frag_color *= _15455;
}

