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
    highp float _4243 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4243 = _4243;
    vec3 _4247 = normalize(v_normal) * mp_copy_4243;
    vec4 _4289 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4292 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _10220 = vec2(0.0);
    if (_4292)
    {
        highp vec2 _10219 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _10219 = v_texture_coords_1;
        }
        else
        {
            _10219 = v_texture_coords;
        }
        highp vec2 _4495 = _10219 * texture_transforms.base_color_transform.zw;
        highp float _4501 = _4495.x;
        highp float _4506 = _4495.y;
        _10220 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4501) + (texture_transforms.base_color_rotation.y * _4506), ((-texture_transforms.base_color_rotation.y) * _4501) + (texture_transforms.base_color_rotation.x * _4506));
    }
    else
    {
        _10220 = v_texture_coords;
    }
    vec4 _4306 = texture(base_color_texture, _10220);
    vec3 _4308 = _4306.xyz;
    float _10739 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4306.w * _4289.w) * frag_info.color.w);
    vec3 _10235 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _10223 = vec2(0.0);
        if (_4292)
        {
            highp vec2 _10222 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _10222 = v_texture_coords_1;
            }
            else
            {
                _10222 = v_texture_coords;
            }
            highp vec2 _4590 = _10222 * texture_transforms.normal_transform.zw;
            highp float _4596 = _4590.x;
            highp float _4601 = _4590.y;
            _10223 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4596) + (texture_transforms.normal_rotation.y * _4601), ((-texture_transforms.normal_rotation.y) * _4596) + (texture_transforms.normal_rotation.x * _4601));
        }
        else
        {
            _10223 = v_texture_coords;
        }
        vec3 _4646 = ((texture(normal_texture, _10223).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4650 = _4646.xy * vec2(frag_info.normal_scale);
        vec3 _9947 = _4646;
        _9947.x = _4650.x;
        _9947.y = _4650.y;
        highp vec3 _4656 = -v_viewvector;
        highp vec3 _4746 = dFdx(_4656);
        highp vec3 _4748 = dFdy(_4656);
        highp vec2 _4750 = dFdx(_10223);
        highp vec2 _4752 = dFdy(_10223);
        bvec2 _10741 = bvec2(length(_4750) == 0.0);
        highp vec2 _10742 = vec2(_10741.x ? vec2(1.0, 0.0).x : _4750.x, _10741.y ? vec2(1.0, 0.0).y : _4750.y);
        bvec2 _10743 = bvec2(length(_4752) == 0.0);
        highp vec2 _10744 = vec2(_10743.x ? vec2(0.0, 1.0).x : _4752.x, _10743.y ? vec2(0.0, 1.0).y : _4752.y);
        highp vec3 _4765 = cross(_4748, _4247);
        highp vec3 _4768 = cross(_4247, _4746);
        highp float _4793 = (dot(cross(_4746, _4748), _4247) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4796 = ((_4765 * _10742.x) + (_4768 * _10744.x)) * _4793;
        highp float _10230 = 0.0;
        if (gl_FrontFacing)
        {
            _10230 = -_4793;
        }
        else
        {
            _10230 = _4793;
        }
        highp vec3 _4806 = ((_4765 * _10742.y) + (_4768 * _10744.y)) * _10230;
        highp float _4815 = inversesqrt(max(max(dot(_4796, _4796), dot(_4806, _4806)), 9.9999996826552253889678874634872e-21));
        vec3 _4687 = v_tangent.xyz - (_4247 * dot(_4247, v_tangent.xyz));
        highp float _4690 = dot(_4687, _4687);
        bool _4692 = _4690 > 1.0000000133514319600180897396058e-10;
        bool _4699 = false;
        if (_4692)
        {
            _4699 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4699 = _4692;
        }
        mat3 _10233 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4699)
        {
            highp vec3 _4704 = _4687 * inversesqrt(_4690);
            _10233 = mat3(_4704, normalize(cross(_4247, _4704)) * sign(v_tangent.w), _4247);
        }
        else
        {
            _10233 = mat3(_4796 * _4815, _4806 * _4815, _4247);
        }
        _10235 = normalize(_10233 * _9947);
    }
    else
    {
        _10235 = _4247;
    }
    highp vec2 _10237 = vec2(0.0);
    if (_4292)
    {
        highp vec2 _10236 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _10236 = v_texture_coords_1;
        }
        else
        {
            _10236 = v_texture_coords;
        }
        highp vec2 _4883 = _10236 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4889 = _4883.x;
        highp float _4894 = _4883.y;
        _10237 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4889) + (texture_transforms.metallic_roughness_rotation.y * _4894), ((-texture_transforms.metallic_roughness_rotation.y) * _4889) + (texture_transforms.metallic_roughness_rotation.x * _4894));
    }
    else
    {
        _10237 = v_texture_coords;
    }
    vec4 _4375 = texture(metallic_roughness_texture, _10237);
    float _4381 = clamp(_4375.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4388 = clamp(_4375.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _10239 = vec2(0.0);
    if (_4292)
    {
        highp vec2 _10238 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _10238 = v_texture_coords_1;
        }
        else
        {
            _10238 = v_texture_coords;
        }
        highp vec2 _4954 = _10238 * texture_transforms.occlusion_transform.zw;
        highp float _4960 = _4954.x;
        highp float _4965 = _4954.y;
        _10239 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4960) + (texture_transforms.occlusion_rotation.y * _4965), ((-texture_transforms.occlusion_rotation.y) * _4960) + (texture_transforms.occlusion_rotation.x * _4965));
    }
    else
    {
        _10239 = v_texture_coords;
    }
    float _10240 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _10240 = texture(occlusion_texture, _10239).x;
    }
    else
    {
        _10240 = 1.0;
    }
    float _4415 = 1.0 - ((1.0 - _10240) * frag_info.occlusion_strength);
    highp vec2 _10242 = vec2(0.0);
    if (_4292)
    {
        highp vec2 _10241 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _10241 = v_texture_coords_1;
        }
        else
        {
            _10241 = v_texture_coords;
        }
        highp vec2 _5025 = _10241 * texture_transforms.emissive_transform.zw;
        highp float _5031 = _5025.x;
        highp float _5036 = _5025.y;
        _10242 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5031) + (texture_transforms.emissive_rotation.y * _5036), ((-texture_transforms.emissive_rotation.y) * _5031) + (texture_transforms.emissive_rotation.x * _5036));
    }
    else
    {
        _10242 = v_texture_coords;
    }
    vec3 _4434 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _10258 = vec3(0.0);
    if (dot(abs(_4434), vec3(1.0)) > 0.0)
    {
        vec3 _4443 = texture(emissive_texture, _10242).xyz;
        _10258 = mix(_4443 * vec3(0.077399380505084991455078125), pow((_4443 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4443)) * _4434;
    }
    else
    {
        _10258 = vec3(0.0);
    }
    highp float hp_copy_10283 = 0.0;
    vec3 _5211 = vec4((mix(_4308 * vec3(0.077399380505084991455078125), pow((_4308 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4308)) * _4289.xyz) * frag_info.color.xyz, _10739).xyz;
    vec3 _5697 = dFdx(_10235);
    vec3 _5699 = dFdy(_10235);
    float _10283 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10283 = sqrt(clamp((_4388 * _4388) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5697, _5697), dot(_5699, _5699))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10283 = _4388;
    }
    hp_copy_10283 = _10283;
    float _10312 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _10312 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _10312 = _4415;
    }
    bool _5236 = frag_info.has_directional_light > 0.5;
    float _10284 = 0.0;
    vec3 _10326 = vec3(0.0);
    if (_5236)
    {
        highp vec3 _5242 = -normalize(frag_info.directional_light_direction.xyz);
        _10326 = _5242;
        _10284 = dot(_4247, _5242);
    }
    else
    {
        _10326 = vec3(0.0);
        _10284 = 0.0;
    }
    float _5249 = clamp(_10284 * 6.666666507720947265625, 0.0, 1.0);
    bool _5258 = false;
    if (_5236)
    {
        _5258 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5258 = _5236;
    }
    float _10293 = 0.0;
    if (_5258 && (_5249 > 0.0))
    {
        int _5778 = int(frag_info.shadow_cascade_count);
        float _5973 = max(dot(_4247, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5976 = _5973 * _5973;
        highp vec3 _5996 = v_position + (_4247 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5976, 0.0)) / _5976, 8.0))));
        highp float _5784 = frag_info.directional_light_color.w * 0.5;
        float _5786 = frag_info.dielectric_f0.w;
        highp float hp_copy_5786 = _5786;
        float _10285 = 0.0;
        if (_5786 > 0.0)
        {
            _10285 = smoothstep(_5786 - max(frag_info.shadow_fade, hp_copy_5786 * 0.100000001490116119384765625), _5786, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10285 = 0.0;
        }
        float _10287 = 0.0;
        float _10289 = 0.0;
        if (_10285 < 1.0)
        {
            float _10288 = 0.0;
            float _10290 = 0.0;
            _10290 = 0.0;
            _10288 = 0.0;
            float _10573 = 0.0;
            float _10576 = 0.0;
            for (int _10286 = 0; _10286 < _5778; _10290 = _10576, _10288 = _10573, _10286++)
            {
                if (_10290 < 1.0)
                {
                    highp vec4 _5818 = vec4(_5996, 1.0);
                    highp vec4 _10445 = vec4(0.0);
                    highp float _10448 = 0.0;
                    if (_10286 == 0)
                    {
                        _10448 = frag_info.cascade_box_sizes.x;
                        _10445 = frag_info.light_space_matrix[0] * _5818;
                    }
                    else
                    {
                        highp vec4 _10446 = vec4(0.0);
                        highp float _10449 = 0.0;
                        if (_10286 == 1)
                        {
                            _10449 = frag_info.cascade_box_sizes.y;
                            _10446 = frag_info.light_space_matrix[1] * _5818;
                        }
                        else
                        {
                            highp vec4 _10447 = vec4(0.0);
                            highp float _10450 = 0.0;
                            if (_10286 == 2)
                            {
                                _10450 = frag_info.cascade_box_sizes.z;
                                _10447 = frag_info.light_space_matrix[2] * _5818;
                            }
                            else
                            {
                                _10450 = frag_info.cascade_box_sizes.w;
                                _10447 = frag_info.light_space_matrix[3] * _5818;
                            }
                            _10449 = _10450;
                            _10446 = _10447;
                        }
                        _10448 = _10449;
                        _10445 = _10446;
                    }
                    highp vec3 _5863 = _10445.xyz / vec3(_10445.w);
                    highp vec2 _5866 = _5863.xy * 0.5;
                    highp vec2 _5868 = _5866 + vec2(0.5);
                    highp float _5875 = max(frag_info.shadow_softness / _10448, frag_info.shadow_texel_size);
                    highp float _5877 = _5868.x;
                    bool _5879 = _5877 < _5875;
                    bool _5888 = false;
                    if (!_5879)
                    {
                        _5888 = _5877 > (1.0 - _5875);
                    }
                    else
                    {
                        _5888 = _5879;
                    }
                    bool _5896 = false;
                    if (!_5888)
                    {
                        _5896 = _5868.y < _5875;
                    }
                    else
                    {
                        _5896 = _5888;
                    }
                    bool _5905 = false;
                    if (!_5896)
                    {
                        _5905 = _5868.y > (1.0 - _5875);
                    }
                    else
                    {
                        _5905 = _5896;
                    }
                    bool _5912 = false;
                    if (!_5905)
                    {
                        _5912 = _5863.z < 0.0;
                    }
                    else
                    {
                        _5912 = _5905;
                    }
                    bool _5919 = false;
                    if (!_5912)
                    {
                        _5919 = _5863.z > 1.0;
                    }
                    else
                    {
                        _5919 = _5912;
                    }
                    float _10574 = 0.0;
                    float _10577 = 0.0;
                    if (!_5919)
                    {
                        highp vec2 _6012 = vec2(_5875);
                        highp vec2 _6017 = vec2(_5875 + max(_5784, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6025 = vec2(0.5) - _5866;
                        highp vec2 _6027 = smoothstep(_6012, _6017, _5868) * smoothstep(_6012, _6017, _6025);
                        float _10451 = 0.0;
                        if (_5784 > 0.0)
                        {
                            _10451 = _6027.x * _6027.y;
                        }
                        else
                        {
                            _10451 = 1.0;
                        }
                        float _5928 = min(_10451, 1.0 - _10290);
                        float _10575 = 0.0;
                        float _10578 = 0.0;
                        if (_5928 > 0.0)
                        {
                            highp float _6166 = _5863.z - (frag_info.shadow_bias / (7.0 * _10448));
                            highp float _6172 = 1.0 / (float(_5778) + frag_info.spot_shadow_params.x);
                            highp float _6174 = frag_info.directional_light_direction.w;
                            float mp_copy_6174 = _6174;
                            float _6180 = step(0.5, mp_copy_6174) * (1.0 - step(1.5, mp_copy_6174));
                            float _10481 = 0.0;
                            float _10485 = 0.0;
                            if (_6180 < 0.5)
                            {
                                highp float _6191 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6191 = _6191;
                                _10485 = sin(mp_copy_6191);
                                _10481 = cos(mp_copy_6191);
                            }
                            else
                            {
                                _10485 = 0.0;
                                _10481 = 1.0;
                            }
                            highp float _10488 = 0.0;
                            if ((_6174 > 1.5) && (_6174 < 2.5))
                            {
                                highp float _6215 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6220 = max(_6215 * _6166, frag_info.shadow_texel_size);
                                float _10477 = 0.0;
                                highp float _10478 = 0.0;
                                _10478 = 0.0;
                                _10477 = 0.0;
                                highp float _6242 = 0.0;
                                float _6245 = 0.0;
                                for (int _10476 = 0; _10476 < 9; _10478 = _6242, _10477 = _6245, _10476++)
                                {
                                    vec2 _10567 = vec2(0.0);
                                    do
                                    {
                                        if (_10476 == 0)
                                        {
                                            _10567 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10476 == 1)
                                        {
                                            _10567 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10476 == 2)
                                        {
                                            _10567 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10476 == 3)
                                        {
                                            _10567 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10476 == 4)
                                        {
                                            _10567 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10476 == 5)
                                        {
                                            _10567 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10476 == 6)
                                        {
                                            _10567 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10476 == 7)
                                        {
                                            _10567 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10476 == 8)
                                        {
                                            _10567 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10476 == 9)
                                        {
                                            _10567 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10476 == 10)
                                        {
                                            _10567 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10476 == 11)
                                        {
                                            _10567 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10476 == 12)
                                        {
                                            _10567 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10476 == 13)
                                        {
                                            _10567 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10476 == 14)
                                        {
                                            _10567 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10476 == 15)
                                        {
                                            _10567 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10567 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6549 = clamp(_5868 + (vec2((_10567.x * _10481) - (_10567.y * _10485), (_10567.x * _10485) + (_10567.y * _10481)) * _6220), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6558 = _6549.y;
                                    highp vec2 _6559 = vec2((float(_10286) + _6549.x) * _6172, _6558);
                                    _6559.y = 1.0 - _6558;
                                    highp vec4 _6566 = textureLod(shadow_map, _6559, 0.0);
                                    highp float _6567 = _6566.x;
                                    highp float _6237 = step(_6567, _6166);
                                    float mp_copy_6237 = _6237;
                                    _6242 = _10478 + (_6567 * _6237);
                                    _6245 = _10477 + mp_copy_6237;
                                }
                                highp float _10479 = 0.0;
                                if (_10477 > 0.0)
                                {
                                    _10479 = _10478 / _10477;
                                }
                                else
                                {
                                    _10479 = _6166;
                                }
                                _10488 = clamp(_6215 * max(_6166 - _10479, 0.0), frag_info.shadow_texel_size, _5875);
                            }
                            else
                            {
                                _10488 = _5875;
                            }
                            bool _6276 = _6174 > 2.5;
                            bool _10489 = false;
                            float _10514 = 0.0;
                            if ((_6174 < 1.5) || _6276)
                            {
                                highp vec2 _6600 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6604 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6605 = clamp(_5868, _6600, _6604);
                                highp float _6607 = float(_10286);
                                highp float _6614 = _6605.y;
                                highp vec2 _6615 = vec2((_6607 + _6605.x) * _6172, _6614);
                                _6615.y = 1.0 - _6614;
                                highp float _6627 = float(_6166 <= textureLod(shadow_map, _6615, 0.0).x);
                                float mp_copy_6627 = _6627;
                                float _6637 = (-1.0) * _10481;
                                float _6641 = (-1.0) * _10485;
                                highp vec2 _6665 = clamp(_5868 + (vec2(_6637 - _6641, _6641 + _6637) * _10488), _6600, _6604);
                                highp float _6674 = _6665.y;
                                highp vec2 _6675 = vec2((_6607 + _6665.x) * _6172, _6674);
                                _6675.y = 1.0 - _6674;
                                highp float _6687 = float(_6166 <= textureLod(shadow_map, _6675, 0.0).x);
                                float mp_copy_6687 = _6687;
                                highp vec2 _6725 = clamp(_5868 + (vec2(_10481 - _6641, _10485 + _6637) * _10488), _6600, _6604);
                                highp float _6734 = _6725.y;
                                highp vec2 _6735 = vec2((_6607 + _6725.x) * _6172, _6734);
                                _6735.y = 1.0 - _6734;
                                highp float _6747 = float(_6166 <= textureLod(shadow_map, _6735, 0.0).x);
                                float mp_copy_6747 = _6747;
                                highp vec2 _6785 = clamp(_5868 + (vec2(_6637 - _10485, _6641 + _10481) * _10488), _6600, _6604);
                                highp float _6794 = _6785.y;
                                highp vec2 _6795 = vec2((_6607 + _6785.x) * _6172, _6794);
                                _6795.y = 1.0 - _6794;
                                highp float _6807 = float(_6166 <= textureLod(shadow_map, _6795, 0.0).x);
                                float mp_copy_6807 = _6807;
                                highp vec2 _6845 = clamp(_5868 + (vec2(_10481 - _10485, _10485 + _10481) * _10488), _6600, _6604);
                                highp float _6854 = _6845.y;
                                highp vec2 _6855 = vec2((_6607 + _6845.x) * _6172, _6854);
                                _6855.y = 1.0 - _6854;
                                highp float _6867 = float(_6166 <= textureLod(shadow_map, _6855, 0.0).x);
                                float mp_copy_6867 = _6867;
                                float _6322 = (((mp_copy_6627 + mp_copy_6687) + mp_copy_6747) + mp_copy_6807) + mp_copy_6867;
                                _10514 = _6322 * 0.20000000298023223876953125;
                                _10489 = (_6322 < 0.5) || (_6322 > 4.5);
                            }
                            else
                            {
                                _10514 = 0.0;
                                _10489 = false;
                            }
                            float _10512 = 0.0;
                            if (_10489)
                            {
                                _10512 = _10514;
                            }
                            else
                            {
                                float _10513 = 0.0;
                                if (_6276)
                                {
                                    highp vec2 _7086 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7090 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7091 = clamp(_5868 + (vec2(-0.707099974155426025390625) * _10488), _7086, _7090);
                                    highp vec2 _7102 = (vec2(_7091.x, 1.0 - _7091.y) / _7086) - vec2(0.5);
                                    highp vec2 _7104 = floor(_7102);
                                    highp vec2 _7107 = _7102 - _7104;
                                    highp vec2 _7112 = (_7104 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7114 = float(_10286);
                                    highp vec2 _7122 = vec2((_7114 + _7112.x) * _6172, _7112.y);
                                    highp float _7126 = frag_info.shadow_texel_size * _6172;
                                    highp vec2 _7129 = vec2(_7126, frag_info.shadow_texel_size);
                                    highp vec2 _7138 = vec2(_7126, 0.0);
                                    highp vec2 _7146 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7175 = _7107.x;
                                    highp float _7184 = mix(mix(float(_6166 <= textureLod(shadow_map, _7122, 0.0).x), float(_6166 <= textureLod(shadow_map, _7122 + _7138, 0.0).x), _7175), mix(float(_6166 <= textureLod(shadow_map, _7122 + _7146, 0.0).x), float(_6166 <= textureLod(shadow_map, _7122 + _7129, 0.0).x), _7175), _7107.y);
                                    float mp_copy_7184 = _7184;
                                    highp vec2 _7218 = clamp(_5868 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10488), _7086, _7090);
                                    highp vec2 _7229 = (vec2(_7218.x, 1.0 - _7218.y) / _7086) - vec2(0.5);
                                    highp vec2 _7231 = floor(_7229);
                                    highp vec2 _7234 = _7229 - _7231;
                                    highp vec2 _7239 = (_7231 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7249 = vec2((_7114 + _7239.x) * _6172, _7239.y);
                                    highp float _7302 = _7234.x;
                                    highp float _7311 = mix(mix(float(_6166 <= textureLod(shadow_map, _7249, 0.0).x), float(_6166 <= textureLod(shadow_map, _7249 + _7138, 0.0).x), _7302), mix(float(_6166 <= textureLod(shadow_map, _7249 + _7146, 0.0).x), float(_6166 <= textureLod(shadow_map, _7249 + _7129, 0.0).x), _7302), _7234.y);
                                    float mp_copy_7311 = _7311;
                                    highp vec2 _7345 = clamp(_5868 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10488), _7086, _7090);
                                    highp vec2 _7356 = (vec2(_7345.x, 1.0 - _7345.y) / _7086) - vec2(0.5);
                                    highp vec2 _7358 = floor(_7356);
                                    highp vec2 _7361 = _7356 - _7358;
                                    highp vec2 _7366 = (_7358 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7376 = vec2((_7114 + _7366.x) * _6172, _7366.y);
                                    highp float _7429 = _7361.x;
                                    highp float _7438 = mix(mix(float(_6166 <= textureLod(shadow_map, _7376, 0.0).x), float(_6166 <= textureLod(shadow_map, _7376 + _7138, 0.0).x), _7429), mix(float(_6166 <= textureLod(shadow_map, _7376 + _7146, 0.0).x), float(_6166 <= textureLod(shadow_map, _7376 + _7129, 0.0).x), _7429), _7361.y);
                                    float mp_copy_7438 = _7438;
                                    highp vec2 _7472 = clamp(_5868 + (vec2(0.707099974155426025390625) * _10488), _7086, _7090);
                                    highp vec2 _7483 = (vec2(_7472.x, 1.0 - _7472.y) / _7086) - vec2(0.5);
                                    highp vec2 _7485 = floor(_7483);
                                    highp vec2 _7488 = _7483 - _7485;
                                    highp vec2 _7493 = (_7485 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7503 = vec2((_7114 + _7493.x) * _6172, _7493.y);
                                    highp float _7556 = _7488.x;
                                    highp float _7565 = mix(mix(float(_6166 <= textureLod(shadow_map, _7503, 0.0).x), float(_6166 <= textureLod(shadow_map, _7503 + _7138, 0.0).x), _7556), mix(float(_6166 <= textureLod(shadow_map, _7503 + _7146, 0.0).x), float(_6166 <= textureLod(shadow_map, _7503 + _7129, 0.0).x), _7556), _7488.y);
                                    float mp_copy_7565 = _7565;
                                    _10513 = (((mp_copy_7184 + mp_copy_7311) + mp_copy_7438) + mp_copy_7565) * 0.25;
                                }
                                else
                                {
                                    int _6338 = (_6180 > 0.5) ? 17 : 16;
                                    float _10508 = 0.0;
                                    _10508 = 0.0;
                                    float _6366 = 0.0;
                                    for (int _10490 = 0; _10490 < 17; _10508 = _6366, _10490++)
                                    {
                                        if (_10490 >= _6338)
                                        {
                                            break;
                                        }
                                        vec2 _10491 = vec2(0.0);
                                        do
                                        {
                                            if (_10490 == 0)
                                            {
                                                _10491 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10490 == 1)
                                            {
                                                _10491 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10490 == 2)
                                            {
                                                _10491 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10490 == 3)
                                            {
                                                _10491 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10490 == 4)
                                            {
                                                _10491 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10490 == 5)
                                            {
                                                _10491 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10490 == 6)
                                            {
                                                _10491 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10490 == 7)
                                            {
                                                _10491 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10490 == 8)
                                            {
                                                _10491 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10490 == 9)
                                            {
                                                _10491 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10490 == 10)
                                            {
                                                _10491 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10490 == 11)
                                            {
                                                _10491 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10490 == 12)
                                            {
                                                _10491 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10490 == 13)
                                            {
                                                _10491 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10490 == 14)
                                            {
                                                _10491 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10490 == 15)
                                            {
                                                _10491 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10491 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10493 = vec2(0.0);
                                        do
                                        {
                                            if (_10490 < 3)
                                            {
                                                _10493 = vec2(float(_10490) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10490 < 6)
                                            {
                                                _10493 = vec2((float(_10490 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10490 < 11)
                                            {
                                                _10493 = vec2((float(_10490 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10490 < 14)
                                            {
                                                _10493 = vec2((float(_10490 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10493 = vec2(float(_10490 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6355 = mix(_10491, _10493, vec2(_6180));
                                        float _7006 = _6355.x;
                                        float _7010 = _6355.y;
                                        highp vec2 _7036 = clamp(_5868 + (vec2((_7006 * _10481) - (_7010 * _10485), (_7006 * _10485) + (_7010 * _10481)) * _10488), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7045 = _7036.y;
                                        highp vec2 _7046 = vec2((float(_10286) + _7036.x) * _6172, _7045);
                                        _7046.y = 1.0 - _7045;
                                        highp float _7058 = float(_6166 <= textureLod(shadow_map, _7046, 0.0).x);
                                        float mp_copy_7058 = _7058;
                                        _6366 = _10508 + mp_copy_7058;
                                    }
                                    _10513 = _10508 / float(_6338);
                                }
                                _10512 = _10513;
                            }
                            bool _6411 = _10286 == (_5778 - 1);
                            bool _6417 = false;
                            if (_6411)
                            {
                                _6417 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6417 = _6411;
                            }
                            float _10515 = 0.0;
                            if (_6417)
                            {
                                highp vec2 _6424 = vec2(frag_info.shadow_fade / _10448);
                                highp vec2 _6432 = smoothstep(vec2(0.0), _6424, _5868) * smoothstep(vec2(0.0), _6424, _6025);
                                _10515 = mix(1.0, _10512, _6432.x * _6432.y);
                            }
                            else
                            {
                                _10515 = _10512;
                            }
                            _10578 = _10290 + _5928;
                            _10575 = _10288 + (_5928 * _10515);
                        }
                        else
                        {
                            _10578 = _10290;
                            _10575 = _10288;
                        }
                        _10577 = _10578;
                        _10574 = _10575;
                    }
                    else
                    {
                        _10577 = _10290;
                        _10574 = _10288;
                    }
                    _10576 = _10577;
                    _10573 = _10574;
                }
                else
                {
                    _10576 = _10290;
                    _10573 = _10288;
                }
            }
            _10289 = _10290;
            _10287 = _10288;
        }
        else
        {
            _10289 = 0.0;
            _10287 = 0.0;
        }
        _10293 = mix(_10287 + (1.0 - _10289), 1.0, _10285);
    }
    else
    {
        _10293 = 1.0;
    }
    vec3 mp_copy_10294 = vec3(0.0);
    float _5271 = _5249 * _10293;
    bool _7573 = view_info.camera_forward.w > 0.5;
    highp vec3 _10294 = vec3(0.0);
    if (_7573)
    {
        _10294 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10294 = normalize(v_viewvector);
    }
    highp float _7617 = 0.0;
    mp_copy_10294 = _10294;
    vec3 _5280 = mix(frag_info.dielectric_f0.xyz, _5211, vec3(_4381));
    float _5284 = max(dot(_10235, _10294), 0.0);
    float _5288 = max(dot(_4247, _10294), 0.0);
    highp vec2 _10295 = vec2(0.0);
    do
    {
        _7617 = frag_info.punctual_dims.x;
        if (_7617 < 0.5)
        {
            _10295 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7629 = v_position - frag_info.camera_position.xyz;
            highp float _7644 = dot(_7629, frag_info.camera_forward.xyz);
            highp float _7650 = max(_7644, 9.9999997473787516355514526367188e-05);
            highp vec2 _7753 = (vec3(dot(_7629, frag_info.camera_right.xyz), dot(_7629, frag_info.camera_up.xyz), _7650).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7650, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7768 = float(int(((((clamp(floor((log2(max(_7644 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7753.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7753.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10295 = vec2(textureLod(punctual_index, vec2((mod(_7768, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7768 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10295 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5297 = int(_10295.x + 0.5);
    mediump int _5301 = int(_10295.y + 0.5);
    highp vec3 _10340 = vec3(0.0);
    _10340 = vec3(0.0);
    highp vec3 _10689 = vec3(0.0);
    for (int _10296 = 0; _10296 < _5301; _10340 = _10689, _10296++)
    {
        highp float hp_copy_10397 = 0.0;
        highp float _7801 = float(_5297 + _10296);
        highp float _7832 = (float(int(textureLod(punctual_index, vec2((mod(_7801, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7801 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7617;
        highp vec4 _7836 = textureLod(punctual_lights, vec2(0.0625, _7832), 0.0);
        highp vec4 _7853 = textureLod(punctual_lights, vec2(0.1875, _7832), 0.0);
        highp float _5319 = _7836.w;
        highp vec3 _5321 = _7853.xyz;
        vec3 _10383 = vec3(0.0);
        highp vec3 _10394 = vec3(0.0);
        float _10397 = 0.0;
        if (_5319 < 0.5)
        {
            _10397 = _10283;
            _10394 = _5321;
            _10383 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7832), 0.0).xyz);
        }
        else
        {
            highp vec3 _5329 = _7836.xyz - v_position;
            highp float _5332 = dot(_5329, _5329);
            highp float _5336 = inversesqrt(max(_5332, 9.9999999392252902907785028219223e-09));
            highp vec3 _5337 = _5329 * _5336;
            vec3 mp_copy_5337 = _5337;
            highp float _5339 = _7853.w;
            highp float _5344 = (_5332 * _5339) * _5339;
            highp float _5349 = clamp(1.0 - (_5344 * _5344), 0.0, 1.0);
            float mp_copy_5349 = _5349;
            if (_5349 <= 0.0)
            {
                _10689 = _10340;
                continue;
            }
            highp vec4 _7870 = textureLod(punctual_lights, vec2(0.4375, _7832), 0.0);
            highp float _5357 = _7870.w;
            float _10399 = 0.0;
            if (_5357 > 0.0)
            {
                highp float _5384 = (_10283 * _10283) + ((_5357 * 0.5) * _5336);
                float mp_copy_5384 = _5384;
                _10399 = sqrt(min(mp_copy_5384, 1.0));
            }
            else
            {
                _10399 = _10283;
            }
            highp vec3 _5391 = _5321 * ((mp_copy_5349 * mp_copy_5349) / max(pow(max(_5332, _5357 * _5357), _7870.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10395 = vec3(0.0);
            if (_5319 > 1.5)
            {
                highp vec4 _7887 = textureLod(punctual_lights, vec2(0.3125, _7832), 0.0);
                highp float _5410 = clamp((dot(normalize(_7887.xyz), -mp_copy_5337) * _7887.w) + _7870.x, 0.0, 1.0);
                float mp_copy_5410 = _5410;
                highp vec3 _5415 = _5391 * (mp_copy_5410 * mp_copy_5410);
                if (_5410 <= 0.0)
                {
                    _10689 = _10340;
                    continue;
                }
                bool _5421 = _5410 > 0.0;
                bool _5427 = false;
                if (_5421)
                {
                    _5427 = _7870.y > (-0.5);
                }
                else
                {
                    _5427 = _5421;
                }
                bool _5433 = false;
                if (_5427)
                {
                    _5433 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5433 = _5427;
                }
                highp vec3 _10396 = vec3(0.0);
                if (_5433)
                {
                    float _10374 = 0.0;
                    do
                    {
                        highp vec4 _7999 = mat4(textureLod(punctual_lights, vec2(0.5625, _7832), 0.0), textureLod(punctual_lights, vec2(0.6875, _7832), 0.0), textureLod(punctual_lights, vec2(0.8125, _7832), 0.0), textureLod(punctual_lights, vec2(0.9375, _7832), 0.0)) * vec4(v_position + (_4247 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8001 = _7999.w;
                        if (_8001 <= 0.0)
                        {
                            _10374 = 1.0;
                            break;
                        }
                        highp vec3 _8010 = _7999.xyz / vec3(_8001);
                        highp vec2 _8015 = (_8010.xy * 0.5) + vec2(0.5);
                        highp float _8017 = _8015.x;
                        bool _8018 = _8017 < 0.0;
                        bool _8025 = false;
                        if (!_8018)
                        {
                            _8025 = _8017 > 1.0;
                        }
                        else
                        {
                            _8025 = _8018;
                        }
                        bool _8032 = false;
                        if (!_8025)
                        {
                            _8032 = _8015.y < 0.0;
                        }
                        else
                        {
                            _8032 = _8025;
                        }
                        bool _8039 = false;
                        if (!_8032)
                        {
                            _8039 = _8015.y > 1.0;
                        }
                        else
                        {
                            _8039 = _8032;
                        }
                        bool _8046 = false;
                        if (!_8039)
                        {
                            _8046 = _8010.z < 0.0;
                        }
                        else
                        {
                            _8046 = _8039;
                        }
                        bool _8053 = false;
                        if (!_8046)
                        {
                            _8053 = _8010.z > 1.0;
                        }
                        else
                        {
                            _8053 = _8046;
                        }
                        if (_8053)
                        {
                            _10374 = 1.0;
                            break;
                        }
                        highp float _8060 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8065 = frag_info.shadow_cascade_count + float(int(_7870.y + 0.5));
                        highp float _8070 = _8010.z - frag_info.spot_shadow_params.y;
                        highp float _8081 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8081 = _8081;
                        highp vec2 _8088 = vec2(cos(mp_copy_8081), sin(mp_copy_8081)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8090 = _8088.x;
                        highp float _8092 = _8088.y;
                        highp vec2 _8100 = vec2(_8090 - _8092, _8090 + _8092) * 0.707106769084930419921875;
                        highp float _8293 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8017, 0.0, 1.0)) / _8060, 1.0 - clamp(_8015.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8293 = _8293;
                        highp vec2 _8108 = _8015 + _8088;
                        highp float _8315 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8108.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8108.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8315 = _8315;
                        highp vec2 _8116 = _8015 - _8088;
                        highp float _8337 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8116.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8116.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8337 = _8337;
                        highp vec2 _8129 = _8015 + vec2(-_8092, _8090);
                        highp float _8359 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8129.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8129.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8359 = _8359;
                        highp vec2 _8142 = _8015 + vec2(_8092, -_8090);
                        highp float _8381 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8142.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8142.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8381 = _8381;
                        float _8147 = (((mp_copy_8293 + mp_copy_8315) + mp_copy_8337) + mp_copy_8359) + mp_copy_8381;
                        if ((_8147 < 0.5) || (_8147 > 4.5))
                        {
                            _10374 = _8147 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8159 = _8015 + _8100;
                        highp float _8403 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8159.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8159.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8403 = _8403;
                        highp vec2 _8166 = _8015 - _8100;
                        highp float _8425 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8166.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8166.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8425 = _8425;
                        highp float _8174 = _8100.y;
                        highp float _8177 = _8100.x;
                        highp vec2 _8179 = _8015 + vec2(-_8174, _8177);
                        highp float _8447 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8179.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8179.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8447 = _8447;
                        highp vec2 _8192 = _8015 + vec2(_8174, -_8177);
                        highp float _8469 = float(_8070 <= textureLod(shadow_map, vec2((_8065 + clamp(_8192.x, 0.0, 1.0)) / _8060, 1.0 - clamp(_8192.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8469 = _8469;
                        _10374 = (_8147 + (((mp_copy_8403 + mp_copy_8425) + mp_copy_8447) + mp_copy_8469)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10396 = _5415 * _10374;
                }
                else
                {
                    _10396 = _5415;
                }
                _10395 = _10396;
            }
            else
            {
                _10395 = _5391;
            }
            _10397 = _10399;
            _10394 = _10395;
            _10383 = _5337;
        }
        hp_copy_10397 = _10397;
        highp vec3 _10412 = vec3(0.0);
        highp vec3 _10413 = vec3(0.0);
        do
        {
            float _8552 = max(dot(_10235, _10383), 0.0);
            highp float hp_copy_8552 = _8552;
            if (_8552 <= 0.0)
            {
                _10413 = vec3(0.0);
                _10412 = vec3(0.0);
                break;
            }
            float _8558 = max(_5284, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8558 = _8558;
            vec3 _8561 = _10383 + mp_copy_10294;
            float _8564 = dot(_8561, _8561);
            vec3 _10410 = vec3(0.0);
            vec3 _10411 = vec3(0.0);
            if (_8564 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8572 = _8561 * inversesqrt(_8564);
                float _10409 = 0.0;
                do
                {
                    float _8629 = dot(_10235, _8572);
                    if (_8629 <= 0.0)
                    {
                        _10409 = 0.0;
                        break;
                    }
                    float _8636 = _10397 * _10397;
                    vec3 _8639 = cross(_10235, _8572);
                    float _8642 = _8629 * _8636;
                    float _8651 = _8636 / (dot(_8639, _8639) + (_8642 * _8642));
                    _10409 = min((_8651 * _8651) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8689 = _5280 + ((vec3(1.0) - _5280) * pow(clamp(1.0 - max(dot(_8572, _10294), 0.0), 0.0, 1.0), 5.0));
                _10411 = (_8689 * min(_10409 * (0.5 / max(mix((2.0 * hp_copy_8552) * _8558, hp_copy_8552 + hp_copy_8558, hp_copy_10397 * hp_copy_10397), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10410 = _8689;
            }
            else
            {
                _10411 = vec3(0.0);
                _10410 = _5280;
            }
            _10413 = (_10411 * _10394) * _8552;
            _10412 = (((((vec3(1.0) - _10410) * (1.0 - _4381)) * _5211) * 0.3183098733425140380859375) * _10394) * _8552;
            break;
        } while(false);
        _10689 = _10340 + (_10412 + _10413);
    }
    bool _8913 = false;
    highp vec3 hp_copy_10297 = vec3(0.0);
    mat3 _5488 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5496 = _5488 * vec3(_10235.x, _10235.y, _10235.z);
    vec3 _5499 = _5488 * reflect(-mp_copy_10294, _10235);
    float _8732 = _5496.y;
    float _8739 = _5496.z;
    float _8746 = _5496.x;
    float _8754 = 1.09254801273345947265625 * _8746;
    vec3 _5502 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8732))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8739))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8746))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8754 * _8732))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8732) * _8739))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8739) * _8739) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8754 * _8739))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8746 * _8746) - (_8732 * _8732)))), vec3(0.0));
    highp vec3 hp_copy_5502 = _5502;
    vec3 _10297 = vec3(0.0);
    do
    {
        _8913 = radiance_layout_info.mip_layout > 0.5;
        if (_8913)
        {
            vec2 _8992 = vec2(atan(_5499.z, _5499.x), asin(clamp(_5499.y, -1.0, 1.0)));
            highp vec2 hp_copy_8992 = _8992;
            _10297 = textureLod(prefiltered_radiance, (hp_copy_8992 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10283, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9011 = vec2(atan(_5499.z, _5499.x), asin(clamp(_5499.y, -1.0, 1.0)));
        highp vec2 hp_copy_9011 = _9011;
        highp vec2 _9016 = (hp_copy_9011 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8923 = clamp(_9016.y, 0.00390625, 0.99609375);
        float _8927 = clamp(_10283, 0.0, 1.0) * 7.0;
        float _8929 = floor(_8927);
        highp float _8948 = _9016.x;
        _10297 = mix(textureLod(prefiltered_radiance, vec2(_8948, (_8929 + _8923) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8948, (min(_8929 + 1.0, 7.0) + _8923) * 0.125), 0.0).xyz, vec3(_8927 - _8929));
        break;
    } while(false);
    hp_copy_10297 = _10297;
    highp vec3 _10303 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_10298 = vec3(0.0);
        vec3 _10298 = vec3(0.0);
        do
        {
            if (_8913)
            {
                vec2 _9121 = vec2(atan(_5499.z, _5499.x), asin(clamp(_5499.y, -1.0, 1.0)));
                highp vec2 hp_copy_9121 = _9121;
                _10298 = textureLod(prefiltered_radiance_b, (hp_copy_9121 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10283, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9140 = vec2(atan(_5499.z, _5499.x), asin(clamp(_5499.y, -1.0, 1.0)));
            highp vec2 hp_copy_9140 = _9140;
            highp vec2 _9145 = (hp_copy_9140 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9052 = clamp(_9145.y, 0.00390625, 0.99609375);
            float _9056 = clamp(_10283, 0.0, 1.0) * 7.0;
            float _9058 = floor(_9056);
            highp float _9077 = _9145.x;
            _10298 = mix(textureLod(prefiltered_radiance_b, vec2(_9077, (_9058 + _9052) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9077, (min(_9058 + 1.0, 7.0) + _9052) * 0.125), 0.0).xyz, vec3(_9056 - _9058));
            break;
        } while(false);
        hp_copy_10298 = _10298;
        _10303 = hp_copy_10297 + hp_copy_10298;
    }
    else
    {
        _10303 = _10297;
    }
    float _5517 = frag_info.environment_intensity;
    highp float hp_copy_5517 = _5517;
    vec2 _5530 = clamp(vec2(_5288, _10283), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5532 = texture(brdf_lut, vec2(_5530.x * 0.3333333432674407958984375, _5530.y));
    float _5536 = _5532.x;
    float _5539 = _5532.y;
    vec3 _5541 = ((_5280 + ((max(vec3(1.0 - _10283), _5280) - _5280) * pow(clamp(1.0 - _5288, 0.0, 1.0), 5.0))) * _5536) + vec3(_5539);
    float _5547 = 1.0 - (_5536 + _5539);
    vec3 _5551 = vec3(1.0) - _5280;
    vec3 _5554 = _5280 + (_5551 * vec3(0.0476190485060214996337890625));
    vec3 _5565 = ((_5541 * _5547) * _5554) / (vec3(1.0) - (_5554 * _5547));
    float _5568 = 1.0 - _4381;
    float _10317 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _10317 = clamp((pow(_5284 + _10312, exp2(((-16.0) * _10283) - 1.0)) - 1.0) + _10312, 0.0, 1.0);
    }
    else
    {
        _10317 = _10312;
    }
    highp vec3 _10350 = vec3(0.0);
    if (_5236)
    {
        highp vec3 _10334 = vec3(0.0);
        highp vec3 _10335 = vec3(0.0);
        do
        {
            float _9234 = max(dot(_10235, _10326), 0.0);
            highp float hp_copy_9234 = _9234;
            if (_9234 <= 0.0)
            {
                _10335 = vec3(0.0);
                _10334 = vec3(0.0);
                break;
            }
            float _9240 = max(_5284, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9240 = _9240;
            vec3 _9243 = _10326 + mp_copy_10294;
            float _9246 = dot(_9243, _9243);
            vec3 _10332 = vec3(0.0);
            vec3 _10333 = vec3(0.0);
            if (_9246 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9254 = _9243 * inversesqrt(_9246);
                float _10331 = 0.0;
                do
                {
                    float _9311 = dot(_10235, _9254);
                    if (_9311 <= 0.0)
                    {
                        _10331 = 0.0;
                        break;
                    }
                    float _9318 = _10283 * _10283;
                    vec3 _9321 = cross(_10235, _9254);
                    float _9324 = _9311 * _9318;
                    float _9333 = _9318 / (dot(_9321, _9321) + (_9324 * _9324));
                    _10331 = min((_9333 * _9333) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9371 = _5280 + (_5551 * pow(clamp(1.0 - max(dot(_9254, _10294), 0.0), 0.0, 1.0), 5.0));
                _10333 = (_9371 * min(_10331 * (0.5 / max(mix((2.0 * hp_copy_9234) * _9240, hp_copy_9234 + hp_copy_9240, hp_copy_10283 * hp_copy_10283), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10332 = _9371;
            }
            else
            {
                _10333 = vec3(0.0);
                _10332 = _5280;
            }
            _10335 = (_10333 * frag_info.directional_light_color.xyz) * _9234;
            _10334 = (((((vec3(1.0) - _10332) * _5568) * _5211) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9234;
            break;
        } while(false);
        _10350 = _10340 + ((_10334 + _10335) * _5271);
    }
    else
    {
        _10350 = _10340;
    }
    bool _5659 = _FogInfo.params0.y > 0.5;
    bool _5665 = false;
    if (_5659)
    {
        _5665 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5665 = _5659;
    }
    highp vec3 _10353 = vec3(0.0);
    if (_5665)
    {
        vec3 mp_copy_10351 = vec3(0.0);
        highp vec3 _10351 = vec3(0.0);
        if (_7573)
        {
            _10351 = -view_info.camera_forward.xyz;
        }
        else
        {
            _10351 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_10352 = vec3(0.0);
        mp_copy_10351 = _10351;
        vec3 _5670 = _5488 * (-mp_copy_10351);
        vec3 _10352 = vec3(0.0);
        do
        {
            if (_8913)
            {
                vec2 _9493 = vec2(atan(_5670.z, _5670.x), asin(clamp(_5670.y, -1.0, 1.0)));
                highp vec2 hp_copy_9493 = _9493;
                _10352 = textureLod(prefiltered_radiance, (hp_copy_9493 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9512 = vec2(atan(_5670.z, _5670.x), asin(clamp(_5670.y, -1.0, 1.0)));
            highp vec2 hp_copy_9512 = _9512;
            highp vec2 _9517 = (hp_copy_9512 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9424 = clamp(_9517.y, 0.00390625, 0.99609375);
            float _9430 = floor(0.0);
            highp float _9449 = _9517.x;
            _10352 = mix(textureLod(prefiltered_radiance, vec2(_9449, (_9430 + _9424) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9449, (min(_9430 + 1.0, 7.0) + _9424) * 0.125), 0.0).xyz, vec3(-_9430));
            break;
        } while(false);
        hp_copy_10352 = _10352;
        _10353 = hp_copy_10352 * hp_copy_5517;
    }
    else
    {
        _10353 = _FogInfo.color.xyz;
    }
    highp vec4 _5685 = vec4(min(((((((_5565 + ((_5211 * _5568) * ((vec3(1.0) - _5541) - _5565))) * (hp_copy_5502 * hp_copy_5517)) * vec3(_4415)) + (((_5541 * (_10303 * _5517)) * 1.0) * _10317)) * mix(1.0, _5271, frag_info.radiance_blend.y)) + (_10350 * mix(1.0, _10312, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _10258, vec3(65504.0)), 1.0) * _10739;
    highp vec4 _10368 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _10368 = _5685;
            break;
        }
        int _9561 = int(_FogInfo.params0.x + 0.5);
        if (_9561 == 0)
        {
            _10368 = _5685;
            break;
        }
        highp float _10355 = 0.0;
        if (_7573)
        {
            _10355 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _10355 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_10355 > _FogInfo.params1.w))
        {
            _10368 = _5685;
            break;
        }
        float _10359 = 0.0;
        if (_9561 == 1)
        {
            _10359 = clamp((_10355 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _10360 = 0.0;
            if (_9561 == 2)
            {
                highp float _10358 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _10356 = vec3(0.0);
                    if (_7573)
                    {
                        _10356 = v_position - (view_info.camera_forward.xyz * _10355);
                    }
                    else
                    {
                        _10356 = v_position + v_viewvector;
                    }
                    highp float _9652 = -_FogInfo.params2.y;
                    highp float _9659 = _FogInfo.params1.x * exp(_9652 * (_10356.y - _FogInfo.params2.x));
                    highp float _9676 = _FogInfo.params2.y * (v_position.y - _10356.y);
                    highp float _10357 = 0.0;
                    if (abs(_9676) > 0.00124999997206032276153564453125)
                    {
                        _10357 = (_9659 - (_FogInfo.params1.x * exp(_9652 * (v_position.y - _FogInfo.params2.x)))) / _9676;
                    }
                    else
                    {
                        _10357 = _9659;
                    }
                    _10358 = _10357 * max(_10355 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _10358 = _FogInfo.params1.x * max(_10355 - _FogInfo.params1.y, 0.0);
                }
                _10360 = 1.0 - exp(-_10358);
            }
            else
            {
                highp float _9614 = _FogInfo.params1.x * max(_10355 - _FogInfo.params1.y, 0.0);
                _10360 = 1.0 - exp((-_9614) * _9614);
            }
            _10359 = _10360;
        }
        highp float _9716 = min(_10359, _FogInfo.params0.z);
        if (_9716 <= 0.0)
        {
            _10368 = _5685;
            break;
        }
        highp vec3 _9729 = mix(_FogInfo.color.xyz, _10353, vec3(_FogInfo.params0.w));
        bool _9732 = _FogInfo.sun.w > 0.5;
        bool _9738 = false;
        if (_9732)
        {
            _9738 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _9738 = _9732;
        }
        vec3 _10364 = vec3(0.0);
        if (_9738)
        {
            vec3 mp_copy_10361 = vec3(0.0);
            highp vec3 _10361 = vec3(0.0);
            if (_7573)
            {
                _10361 = -view_info.camera_forward.xyz;
            }
            else
            {
                _10361 = normalize(v_viewvector);
            }
            mp_copy_10361 = _10361;
            highp float _9754 = pow(max(dot(-mp_copy_10361, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_9754 = _9754;
            _10364 = _9729 + ((_FogInfo.sun.xyz * mp_copy_9754) * _FogInfo.params2.z);
        }
        else
        {
            _10364 = _9729;
        }
        highp float _9767 = _5685.w;
        float mp_copy_9767 = _9767;
        _10368 = vec4(mix(_5685.xyz, _10364 * mp_copy_9767, vec3(_9716)), _9767);
        break;
    } while(false);
    vec4 _10370 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10370 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10370 = _10368;
        break;
    } while(false);
    frag_color = _10370;
    float _10371 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10371 = 1.0;
    }
    else
    {
        _10371 = abs(frag_info.fade);
    }
    frag_color *= _10371;
}

