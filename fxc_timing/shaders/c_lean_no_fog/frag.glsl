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
    highp float _4240 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4240 = _4240;
    vec3 _4244 = normalize(v_normal) * mp_copy_4240;
    vec4 _4286 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4289 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9947 = vec2(0.0);
    if (_4289)
    {
        highp vec2 _9946 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9946 = v_texture_coords_1;
        }
        else
        {
            _9946 = v_texture_coords;
        }
        highp vec2 _4492 = _9946 * texture_transforms.base_color_transform.zw;
        highp float _4498 = _4492.x;
        highp float _4503 = _4492.y;
        _9947 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4498) + (texture_transforms.base_color_rotation.y * _4503), ((-texture_transforms.base_color_rotation.y) * _4498) + (texture_transforms.base_color_rotation.x * _4503));
    }
    else
    {
        _9947 = v_texture_coords;
    }
    vec4 _4303 = texture(base_color_texture, _9947);
    vec3 _4305 = _4303.xyz;
    float _10448 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4303.w * _4286.w) * frag_info.color.w);
    vec3 _9962 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9950 = vec2(0.0);
        if (_4289)
        {
            highp vec2 _9949 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9949 = v_texture_coords_1;
            }
            else
            {
                _9949 = v_texture_coords;
            }
            highp vec2 _4587 = _9949 * texture_transforms.normal_transform.zw;
            highp float _4593 = _4587.x;
            highp float _4598 = _4587.y;
            _9950 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4593) + (texture_transforms.normal_rotation.y * _4598), ((-texture_transforms.normal_rotation.y) * _4593) + (texture_transforms.normal_rotation.x * _4598));
        }
        else
        {
            _9950 = v_texture_coords;
        }
        vec3 _4643 = ((texture(normal_texture, _9950).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4647 = _4643.xy * vec2(frag_info.normal_scale);
        vec3 _9692 = _4643;
        _9692.x = _4647.x;
        _9692.y = _4647.y;
        highp vec3 _4653 = -v_viewvector;
        highp vec3 _4743 = dFdx(_4653);
        highp vec3 _4745 = dFdy(_4653);
        highp vec2 _4747 = dFdx(_9950);
        highp vec2 _4749 = dFdy(_9950);
        bvec2 _10450 = bvec2(length(_4747) == 0.0);
        highp vec2 _10451 = vec2(_10450.x ? vec2(1.0, 0.0).x : _4747.x, _10450.y ? vec2(1.0, 0.0).y : _4747.y);
        bvec2 _10452 = bvec2(length(_4749) == 0.0);
        highp vec2 _10453 = vec2(_10452.x ? vec2(0.0, 1.0).x : _4749.x, _10452.y ? vec2(0.0, 1.0).y : _4749.y);
        highp vec3 _4762 = cross(_4745, _4244);
        highp vec3 _4765 = cross(_4244, _4743);
        highp float _4790 = (dot(cross(_4743, _4745), _4244) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4793 = ((_4762 * _10451.x) + (_4765 * _10453.x)) * _4790;
        highp float _9957 = 0.0;
        if (gl_FrontFacing)
        {
            _9957 = -_4790;
        }
        else
        {
            _9957 = _4790;
        }
        highp vec3 _4803 = ((_4762 * _10451.y) + (_4765 * _10453.y)) * _9957;
        highp float _4812 = inversesqrt(max(max(dot(_4793, _4793), dot(_4803, _4803)), 9.9999996826552253889678874634872e-21));
        vec3 _4684 = v_tangent.xyz - (_4244 * dot(_4244, v_tangent.xyz));
        highp float _4687 = dot(_4684, _4684);
        bool _4689 = _4687 > 1.0000000133514319600180897396058e-10;
        bool _4696 = false;
        if (_4689)
        {
            _4696 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4696 = _4689;
        }
        mat3 _9960 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4696)
        {
            highp vec3 _4701 = _4684 * inversesqrt(_4687);
            _9960 = mat3(_4701, normalize(cross(_4244, _4701)) * sign(v_tangent.w), _4244);
        }
        else
        {
            _9960 = mat3(_4793 * _4812, _4803 * _4812, _4244);
        }
        _9962 = normalize(_9960 * _9692);
    }
    else
    {
        _9962 = _4244;
    }
    highp vec2 _9964 = vec2(0.0);
    if (_4289)
    {
        highp vec2 _9963 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9963 = v_texture_coords_1;
        }
        else
        {
            _9963 = v_texture_coords;
        }
        highp vec2 _4880 = _9963 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4886 = _4880.x;
        highp float _4891 = _4880.y;
        _9964 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4886) + (texture_transforms.metallic_roughness_rotation.y * _4891), ((-texture_transforms.metallic_roughness_rotation.y) * _4886) + (texture_transforms.metallic_roughness_rotation.x * _4891));
    }
    else
    {
        _9964 = v_texture_coords;
    }
    vec4 _4372 = texture(metallic_roughness_texture, _9964);
    float _4378 = clamp(_4372.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4385 = clamp(_4372.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9966 = vec2(0.0);
    if (_4289)
    {
        highp vec2 _9965 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9965 = v_texture_coords_1;
        }
        else
        {
            _9965 = v_texture_coords;
        }
        highp vec2 _4951 = _9965 * texture_transforms.occlusion_transform.zw;
        highp float _4957 = _4951.x;
        highp float _4962 = _4951.y;
        _9966 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4957) + (texture_transforms.occlusion_rotation.y * _4962), ((-texture_transforms.occlusion_rotation.y) * _4957) + (texture_transforms.occlusion_rotation.x * _4962));
    }
    else
    {
        _9966 = v_texture_coords;
    }
    float _9967 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9967 = texture(occlusion_texture, _9966).x;
    }
    else
    {
        _9967 = 1.0;
    }
    float _4412 = 1.0 - ((1.0 - _9967) * frag_info.occlusion_strength);
    highp vec2 _9969 = vec2(0.0);
    if (_4289)
    {
        highp vec2 _9968 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9968 = v_texture_coords_1;
        }
        else
        {
            _9968 = v_texture_coords;
        }
        highp vec2 _5022 = _9968 * texture_transforms.emissive_transform.zw;
        highp float _5028 = _5022.x;
        highp float _5033 = _5022.y;
        _9969 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5028) + (texture_transforms.emissive_rotation.y * _5033), ((-texture_transforms.emissive_rotation.y) * _5028) + (texture_transforms.emissive_rotation.x * _5033));
    }
    else
    {
        _9969 = v_texture_coords;
    }
    vec3 _4431 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9985 = vec3(0.0);
    if (dot(abs(_4431), vec3(1.0)) > 0.0)
    {
        vec3 _4440 = texture(emissive_texture, _9969).xyz;
        _9985 = mix(_4440 * vec3(0.077399380505084991455078125), pow((_4440 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4440)) * _4431;
    }
    else
    {
        _9985 = vec3(0.0);
    }
    highp float hp_copy_10010 = 0.0;
    vec3 _5208 = vec4((mix(_4305 * vec3(0.077399380505084991455078125), pow((_4305 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4305)) * _4286.xyz) * frag_info.color.xyz, _10448).xyz;
    vec3 _5694 = dFdx(_9962);
    vec3 _5696 = dFdy(_9962);
    float _10010 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10010 = sqrt(clamp((_4385 * _4385) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5694, _5694), dot(_5696, _5696))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10010 = _4385;
    }
    hp_copy_10010 = _10010;
    float _10039 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _10039 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _10039 = _4412;
    }
    bool _5233 = frag_info.has_directional_light > 0.5;
    float _10011 = 0.0;
    vec3 _10053 = vec3(0.0);
    if (_5233)
    {
        highp vec3 _5239 = -normalize(frag_info.directional_light_direction.xyz);
        _10053 = _5239;
        _10011 = dot(_4244, _5239);
    }
    else
    {
        _10053 = vec3(0.0);
        _10011 = 0.0;
    }
    float _5246 = clamp(_10011 * 6.666666507720947265625, 0.0, 1.0);
    bool _5255 = false;
    if (_5233)
    {
        _5255 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5255 = _5233;
    }
    float _10020 = 0.0;
    if (_5255 && (_5246 > 0.0))
    {
        int _5775 = int(frag_info.shadow_cascade_count);
        float _5970 = max(dot(_4244, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5973 = _5970 * _5970;
        highp vec3 _5993 = v_position + (_4244 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5973, 0.0)) / _5973, 8.0))));
        highp float _5781 = frag_info.directional_light_color.w * 0.5;
        float _5783 = frag_info.dielectric_f0.w;
        highp float hp_copy_5783 = _5783;
        float _10012 = 0.0;
        if (_5783 > 0.0)
        {
            _10012 = smoothstep(_5783 - max(frag_info.shadow_fade, hp_copy_5783 * 0.100000001490116119384765625), _5783, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10012 = 0.0;
        }
        float _10014 = 0.0;
        float _10016 = 0.0;
        if (_10012 < 1.0)
        {
            float _10015 = 0.0;
            float _10017 = 0.0;
            _10017 = 0.0;
            _10015 = 0.0;
            float _10282 = 0.0;
            float _10285 = 0.0;
            for (int _10013 = 0; _10013 < _5775; _10017 = _10285, _10015 = _10282, _10013++)
            {
                if (_10017 < 1.0)
                {
                    highp vec4 _5815 = vec4(_5993, 1.0);
                    highp vec4 _10154 = vec4(0.0);
                    highp float _10157 = 0.0;
                    if (_10013 == 0)
                    {
                        _10157 = frag_info.cascade_box_sizes.x;
                        _10154 = frag_info.light_space_matrix[0] * _5815;
                    }
                    else
                    {
                        highp vec4 _10155 = vec4(0.0);
                        highp float _10158 = 0.0;
                        if (_10013 == 1)
                        {
                            _10158 = frag_info.cascade_box_sizes.y;
                            _10155 = frag_info.light_space_matrix[1] * _5815;
                        }
                        else
                        {
                            highp vec4 _10156 = vec4(0.0);
                            highp float _10159 = 0.0;
                            if (_10013 == 2)
                            {
                                _10159 = frag_info.cascade_box_sizes.z;
                                _10156 = frag_info.light_space_matrix[2] * _5815;
                            }
                            else
                            {
                                _10159 = frag_info.cascade_box_sizes.w;
                                _10156 = frag_info.light_space_matrix[3] * _5815;
                            }
                            _10158 = _10159;
                            _10155 = _10156;
                        }
                        _10157 = _10158;
                        _10154 = _10155;
                    }
                    highp vec3 _5860 = _10154.xyz / vec3(_10154.w);
                    highp vec2 _5863 = _5860.xy * 0.5;
                    highp vec2 _5865 = _5863 + vec2(0.5);
                    highp float _5872 = max(frag_info.shadow_softness / _10157, frag_info.shadow_texel_size);
                    highp float _5874 = _5865.x;
                    bool _5876 = _5874 < _5872;
                    bool _5885 = false;
                    if (!_5876)
                    {
                        _5885 = _5874 > (1.0 - _5872);
                    }
                    else
                    {
                        _5885 = _5876;
                    }
                    bool _5893 = false;
                    if (!_5885)
                    {
                        _5893 = _5865.y < _5872;
                    }
                    else
                    {
                        _5893 = _5885;
                    }
                    bool _5902 = false;
                    if (!_5893)
                    {
                        _5902 = _5865.y > (1.0 - _5872);
                    }
                    else
                    {
                        _5902 = _5893;
                    }
                    bool _5909 = false;
                    if (!_5902)
                    {
                        _5909 = _5860.z < 0.0;
                    }
                    else
                    {
                        _5909 = _5902;
                    }
                    bool _5916 = false;
                    if (!_5909)
                    {
                        _5916 = _5860.z > 1.0;
                    }
                    else
                    {
                        _5916 = _5909;
                    }
                    float _10283 = 0.0;
                    float _10286 = 0.0;
                    if (!_5916)
                    {
                        highp vec2 _6009 = vec2(_5872);
                        highp vec2 _6014 = vec2(_5872 + max(_5781, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6022 = vec2(0.5) - _5863;
                        highp vec2 _6024 = smoothstep(_6009, _6014, _5865) * smoothstep(_6009, _6014, _6022);
                        float _10160 = 0.0;
                        if (_5781 > 0.0)
                        {
                            _10160 = _6024.x * _6024.y;
                        }
                        else
                        {
                            _10160 = 1.0;
                        }
                        float _5925 = min(_10160, 1.0 - _10017);
                        float _10284 = 0.0;
                        float _10287 = 0.0;
                        if (_5925 > 0.0)
                        {
                            highp float _6163 = _5860.z - (frag_info.shadow_bias / (7.0 * _10157));
                            highp float _6169 = 1.0 / (float(_5775) + frag_info.spot_shadow_params.x);
                            highp float _6171 = frag_info.directional_light_direction.w;
                            float mp_copy_6171 = _6171;
                            float _6177 = step(0.5, mp_copy_6171) * (1.0 - step(1.5, mp_copy_6171));
                            float _10190 = 0.0;
                            float _10194 = 0.0;
                            if (_6177 < 0.5)
                            {
                                highp float _6188 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6188 = _6188;
                                _10194 = sin(mp_copy_6188);
                                _10190 = cos(mp_copy_6188);
                            }
                            else
                            {
                                _10194 = 0.0;
                                _10190 = 1.0;
                            }
                            highp float _10197 = 0.0;
                            if ((_6171 > 1.5) && (_6171 < 2.5))
                            {
                                highp float _6212 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6217 = max(_6212 * _6163, frag_info.shadow_texel_size);
                                float _10186 = 0.0;
                                highp float _10187 = 0.0;
                                _10187 = 0.0;
                                _10186 = 0.0;
                                highp float _6239 = 0.0;
                                float _6242 = 0.0;
                                for (int _10185 = 0; _10185 < 9; _10187 = _6239, _10186 = _6242, _10185++)
                                {
                                    vec2 _10276 = vec2(0.0);
                                    do
                                    {
                                        if (_10185 == 0)
                                        {
                                            _10276 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10185 == 1)
                                        {
                                            _10276 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10185 == 2)
                                        {
                                            _10276 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10185 == 3)
                                        {
                                            _10276 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10185 == 4)
                                        {
                                            _10276 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10185 == 5)
                                        {
                                            _10276 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10185 == 6)
                                        {
                                            _10276 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10185 == 7)
                                        {
                                            _10276 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10185 == 8)
                                        {
                                            _10276 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10185 == 9)
                                        {
                                            _10276 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10185 == 10)
                                        {
                                            _10276 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10185 == 11)
                                        {
                                            _10276 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10185 == 12)
                                        {
                                            _10276 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10185 == 13)
                                        {
                                            _10276 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10185 == 14)
                                        {
                                            _10276 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10185 == 15)
                                        {
                                            _10276 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10276 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6546 = clamp(_5865 + (vec2((_10276.x * _10190) - (_10276.y * _10194), (_10276.x * _10194) + (_10276.y * _10190)) * _6217), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6555 = _6546.y;
                                    highp vec2 _6556 = vec2((float(_10013) + _6546.x) * _6169, _6555);
                                    _6556.y = 1.0 - _6555;
                                    highp vec4 _6563 = textureLod(shadow_map, _6556, 0.0);
                                    highp float _6564 = _6563.x;
                                    highp float _6234 = step(_6564, _6163);
                                    float mp_copy_6234 = _6234;
                                    _6239 = _10187 + (_6564 * _6234);
                                    _6242 = _10186 + mp_copy_6234;
                                }
                                highp float _10188 = 0.0;
                                if (_10186 > 0.0)
                                {
                                    _10188 = _10187 / _10186;
                                }
                                else
                                {
                                    _10188 = _6163;
                                }
                                _10197 = clamp(_6212 * max(_6163 - _10188, 0.0), frag_info.shadow_texel_size, _5872);
                            }
                            else
                            {
                                _10197 = _5872;
                            }
                            bool _6273 = _6171 > 2.5;
                            bool _10198 = false;
                            float _10223 = 0.0;
                            if ((_6171 < 1.5) || _6273)
                            {
                                highp vec2 _6597 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6601 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6602 = clamp(_5865, _6597, _6601);
                                highp float _6604 = float(_10013);
                                highp float _6611 = _6602.y;
                                highp vec2 _6612 = vec2((_6604 + _6602.x) * _6169, _6611);
                                _6612.y = 1.0 - _6611;
                                highp float _6624 = float(_6163 <= textureLod(shadow_map, _6612, 0.0).x);
                                float mp_copy_6624 = _6624;
                                float _6634 = (-1.0) * _10190;
                                float _6638 = (-1.0) * _10194;
                                highp vec2 _6662 = clamp(_5865 + (vec2(_6634 - _6638, _6638 + _6634) * _10197), _6597, _6601);
                                highp float _6671 = _6662.y;
                                highp vec2 _6672 = vec2((_6604 + _6662.x) * _6169, _6671);
                                _6672.y = 1.0 - _6671;
                                highp float _6684 = float(_6163 <= textureLod(shadow_map, _6672, 0.0).x);
                                float mp_copy_6684 = _6684;
                                highp vec2 _6722 = clamp(_5865 + (vec2(_10190 - _6638, _10194 + _6634) * _10197), _6597, _6601);
                                highp float _6731 = _6722.y;
                                highp vec2 _6732 = vec2((_6604 + _6722.x) * _6169, _6731);
                                _6732.y = 1.0 - _6731;
                                highp float _6744 = float(_6163 <= textureLod(shadow_map, _6732, 0.0).x);
                                float mp_copy_6744 = _6744;
                                highp vec2 _6782 = clamp(_5865 + (vec2(_6634 - _10194, _6638 + _10190) * _10197), _6597, _6601);
                                highp float _6791 = _6782.y;
                                highp vec2 _6792 = vec2((_6604 + _6782.x) * _6169, _6791);
                                _6792.y = 1.0 - _6791;
                                highp float _6804 = float(_6163 <= textureLod(shadow_map, _6792, 0.0).x);
                                float mp_copy_6804 = _6804;
                                highp vec2 _6842 = clamp(_5865 + (vec2(_10190 - _10194, _10194 + _10190) * _10197), _6597, _6601);
                                highp float _6851 = _6842.y;
                                highp vec2 _6852 = vec2((_6604 + _6842.x) * _6169, _6851);
                                _6852.y = 1.0 - _6851;
                                highp float _6864 = float(_6163 <= textureLod(shadow_map, _6852, 0.0).x);
                                float mp_copy_6864 = _6864;
                                float _6319 = (((mp_copy_6624 + mp_copy_6684) + mp_copy_6744) + mp_copy_6804) + mp_copy_6864;
                                _10223 = _6319 * 0.20000000298023223876953125;
                                _10198 = (_6319 < 0.5) || (_6319 > 4.5);
                            }
                            else
                            {
                                _10223 = 0.0;
                                _10198 = false;
                            }
                            float _10221 = 0.0;
                            if (_10198)
                            {
                                _10221 = _10223;
                            }
                            else
                            {
                                float _10222 = 0.0;
                                if (_6273)
                                {
                                    highp vec2 _7083 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7087 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7088 = clamp(_5865 + (vec2(-0.707099974155426025390625) * _10197), _7083, _7087);
                                    highp vec2 _7099 = (vec2(_7088.x, 1.0 - _7088.y) / _7083) - vec2(0.5);
                                    highp vec2 _7101 = floor(_7099);
                                    highp vec2 _7104 = _7099 - _7101;
                                    highp vec2 _7109 = (_7101 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7111 = float(_10013);
                                    highp vec2 _7119 = vec2((_7111 + _7109.x) * _6169, _7109.y);
                                    highp float _7123 = frag_info.shadow_texel_size * _6169;
                                    highp vec2 _7126 = vec2(_7123, frag_info.shadow_texel_size);
                                    highp vec2 _7135 = vec2(_7123, 0.0);
                                    highp vec2 _7143 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7172 = _7104.x;
                                    highp float _7181 = mix(mix(float(_6163 <= textureLod(shadow_map, _7119, 0.0).x), float(_6163 <= textureLod(shadow_map, _7119 + _7135, 0.0).x), _7172), mix(float(_6163 <= textureLod(shadow_map, _7119 + _7143, 0.0).x), float(_6163 <= textureLod(shadow_map, _7119 + _7126, 0.0).x), _7172), _7104.y);
                                    float mp_copy_7181 = _7181;
                                    highp vec2 _7215 = clamp(_5865 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10197), _7083, _7087);
                                    highp vec2 _7226 = (vec2(_7215.x, 1.0 - _7215.y) / _7083) - vec2(0.5);
                                    highp vec2 _7228 = floor(_7226);
                                    highp vec2 _7231 = _7226 - _7228;
                                    highp vec2 _7236 = (_7228 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7246 = vec2((_7111 + _7236.x) * _6169, _7236.y);
                                    highp float _7299 = _7231.x;
                                    highp float _7308 = mix(mix(float(_6163 <= textureLod(shadow_map, _7246, 0.0).x), float(_6163 <= textureLod(shadow_map, _7246 + _7135, 0.0).x), _7299), mix(float(_6163 <= textureLod(shadow_map, _7246 + _7143, 0.0).x), float(_6163 <= textureLod(shadow_map, _7246 + _7126, 0.0).x), _7299), _7231.y);
                                    float mp_copy_7308 = _7308;
                                    highp vec2 _7342 = clamp(_5865 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10197), _7083, _7087);
                                    highp vec2 _7353 = (vec2(_7342.x, 1.0 - _7342.y) / _7083) - vec2(0.5);
                                    highp vec2 _7355 = floor(_7353);
                                    highp vec2 _7358 = _7353 - _7355;
                                    highp vec2 _7363 = (_7355 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7373 = vec2((_7111 + _7363.x) * _6169, _7363.y);
                                    highp float _7426 = _7358.x;
                                    highp float _7435 = mix(mix(float(_6163 <= textureLod(shadow_map, _7373, 0.0).x), float(_6163 <= textureLod(shadow_map, _7373 + _7135, 0.0).x), _7426), mix(float(_6163 <= textureLod(shadow_map, _7373 + _7143, 0.0).x), float(_6163 <= textureLod(shadow_map, _7373 + _7126, 0.0).x), _7426), _7358.y);
                                    float mp_copy_7435 = _7435;
                                    highp vec2 _7469 = clamp(_5865 + (vec2(0.707099974155426025390625) * _10197), _7083, _7087);
                                    highp vec2 _7480 = (vec2(_7469.x, 1.0 - _7469.y) / _7083) - vec2(0.5);
                                    highp vec2 _7482 = floor(_7480);
                                    highp vec2 _7485 = _7480 - _7482;
                                    highp vec2 _7490 = (_7482 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7500 = vec2((_7111 + _7490.x) * _6169, _7490.y);
                                    highp float _7553 = _7485.x;
                                    highp float _7562 = mix(mix(float(_6163 <= textureLod(shadow_map, _7500, 0.0).x), float(_6163 <= textureLod(shadow_map, _7500 + _7135, 0.0).x), _7553), mix(float(_6163 <= textureLod(shadow_map, _7500 + _7143, 0.0).x), float(_6163 <= textureLod(shadow_map, _7500 + _7126, 0.0).x), _7553), _7485.y);
                                    float mp_copy_7562 = _7562;
                                    _10222 = (((mp_copy_7181 + mp_copy_7308) + mp_copy_7435) + mp_copy_7562) * 0.25;
                                }
                                else
                                {
                                    int _6335 = (_6177 > 0.5) ? 17 : 16;
                                    float _10217 = 0.0;
                                    _10217 = 0.0;
                                    float _6363 = 0.0;
                                    for (int _10199 = 0; _10199 < 17; _10217 = _6363, _10199++)
                                    {
                                        if (_10199 >= _6335)
                                        {
                                            break;
                                        }
                                        vec2 _10200 = vec2(0.0);
                                        do
                                        {
                                            if (_10199 == 0)
                                            {
                                                _10200 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10199 == 1)
                                            {
                                                _10200 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10199 == 2)
                                            {
                                                _10200 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10199 == 3)
                                            {
                                                _10200 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10199 == 4)
                                            {
                                                _10200 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10199 == 5)
                                            {
                                                _10200 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10199 == 6)
                                            {
                                                _10200 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10199 == 7)
                                            {
                                                _10200 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10199 == 8)
                                            {
                                                _10200 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10199 == 9)
                                            {
                                                _10200 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10199 == 10)
                                            {
                                                _10200 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10199 == 11)
                                            {
                                                _10200 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10199 == 12)
                                            {
                                                _10200 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10199 == 13)
                                            {
                                                _10200 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10199 == 14)
                                            {
                                                _10200 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10199 == 15)
                                            {
                                                _10200 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10200 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10202 = vec2(0.0);
                                        do
                                        {
                                            if (_10199 < 3)
                                            {
                                                _10202 = vec2(float(_10199) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10199 < 6)
                                            {
                                                _10202 = vec2((float(_10199 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10199 < 11)
                                            {
                                                _10202 = vec2((float(_10199 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10199 < 14)
                                            {
                                                _10202 = vec2((float(_10199 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10202 = vec2(float(_10199 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6352 = mix(_10200, _10202, vec2(_6177));
                                        float _7003 = _6352.x;
                                        float _7007 = _6352.y;
                                        highp vec2 _7033 = clamp(_5865 + (vec2((_7003 * _10190) - (_7007 * _10194), (_7003 * _10194) + (_7007 * _10190)) * _10197), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7042 = _7033.y;
                                        highp vec2 _7043 = vec2((float(_10013) + _7033.x) * _6169, _7042);
                                        _7043.y = 1.0 - _7042;
                                        highp float _7055 = float(_6163 <= textureLod(shadow_map, _7043, 0.0).x);
                                        float mp_copy_7055 = _7055;
                                        _6363 = _10217 + mp_copy_7055;
                                    }
                                    _10222 = _10217 / float(_6335);
                                }
                                _10221 = _10222;
                            }
                            bool _6408 = _10013 == (_5775 - 1);
                            bool _6414 = false;
                            if (_6408)
                            {
                                _6414 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6414 = _6408;
                            }
                            float _10224 = 0.0;
                            if (_6414)
                            {
                                highp vec2 _6421 = vec2(frag_info.shadow_fade / _10157);
                                highp vec2 _6429 = smoothstep(vec2(0.0), _6421, _5865) * smoothstep(vec2(0.0), _6421, _6022);
                                _10224 = mix(1.0, _10221, _6429.x * _6429.y);
                            }
                            else
                            {
                                _10224 = _10221;
                            }
                            _10287 = _10017 + _5925;
                            _10284 = _10015 + (_5925 * _10224);
                        }
                        else
                        {
                            _10287 = _10017;
                            _10284 = _10015;
                        }
                        _10286 = _10287;
                        _10283 = _10284;
                    }
                    else
                    {
                        _10286 = _10017;
                        _10283 = _10015;
                    }
                    _10285 = _10286;
                    _10282 = _10283;
                }
                else
                {
                    _10285 = _10017;
                    _10282 = _10015;
                }
            }
            _10016 = _10017;
            _10014 = _10015;
        }
        else
        {
            _10016 = 0.0;
            _10014 = 0.0;
        }
        _10020 = mix(_10014 + (1.0 - _10016), 1.0, _10012);
    }
    else
    {
        _10020 = 1.0;
    }
    vec3 mp_copy_10021 = vec3(0.0);
    float _5268 = _5246 * _10020;
    highp vec3 _10021 = vec3(0.0);
    if (view_info.camera_forward.w > 0.5)
    {
        _10021 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10021 = normalize(v_viewvector);
    }
    highp float _7614 = 0.0;
    mp_copy_10021 = _10021;
    vec3 _5277 = mix(frag_info.dielectric_f0.xyz, _5208, vec3(_4378));
    float _5281 = max(dot(_9962, _10021), 0.0);
    float _5285 = max(dot(_4244, _10021), 0.0);
    highp vec2 _10022 = vec2(0.0);
    do
    {
        _7614 = frag_info.punctual_dims.x;
        if (_7614 < 0.5)
        {
            _10022 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7626 = v_position - frag_info.camera_position.xyz;
            highp float _7641 = dot(_7626, frag_info.camera_forward.xyz);
            highp float _7647 = max(_7641, 9.9999997473787516355514526367188e-05);
            highp vec2 _7750 = (vec3(dot(_7626, frag_info.camera_right.xyz), dot(_7626, frag_info.camera_up.xyz), _7647).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7647, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7765 = float(int(((((clamp(floor((log2(max(_7641 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7750.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7750.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10022 = vec2(textureLod(punctual_index, vec2((mod(_7765, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7765 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10022 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5294 = int(_10022.x + 0.5);
    mediump int _5298 = int(_10022.y + 0.5);
    highp vec3 _10067 = vec3(0.0);
    _10067 = vec3(0.0);
    highp vec3 _10398 = vec3(0.0);
    for (int _10023 = 0; _10023 < _5298; _10067 = _10398, _10023++)
    {
        highp float hp_copy_10106 = 0.0;
        highp float _7798 = float(_5294 + _10023);
        highp float _7829 = (float(int(textureLod(punctual_index, vec2((mod(_7798, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7798 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7614;
        highp vec4 _7833 = textureLod(punctual_lights, vec2(0.0625, _7829), 0.0);
        highp vec4 _7850 = textureLod(punctual_lights, vec2(0.1875, _7829), 0.0);
        highp float _5316 = _7833.w;
        highp vec3 _5318 = _7850.xyz;
        vec3 _10092 = vec3(0.0);
        highp vec3 _10103 = vec3(0.0);
        float _10106 = 0.0;
        if (_5316 < 0.5)
        {
            _10106 = _10010;
            _10103 = _5318;
            _10092 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7829), 0.0).xyz);
        }
        else
        {
            highp vec3 _5326 = _7833.xyz - v_position;
            highp float _5329 = dot(_5326, _5326);
            highp float _5333 = inversesqrt(max(_5329, 9.9999999392252902907785028219223e-09));
            highp vec3 _5334 = _5326 * _5333;
            vec3 mp_copy_5334 = _5334;
            highp float _5336 = _7850.w;
            highp float _5341 = (_5329 * _5336) * _5336;
            highp float _5346 = clamp(1.0 - (_5341 * _5341), 0.0, 1.0);
            float mp_copy_5346 = _5346;
            if (_5346 <= 0.0)
            {
                _10398 = _10067;
                continue;
            }
            highp vec4 _7867 = textureLod(punctual_lights, vec2(0.4375, _7829), 0.0);
            highp float _5354 = _7867.w;
            float _10108 = 0.0;
            if (_5354 > 0.0)
            {
                highp float _5381 = (_10010 * _10010) + ((_5354 * 0.5) * _5333);
                float mp_copy_5381 = _5381;
                _10108 = sqrt(min(mp_copy_5381, 1.0));
            }
            else
            {
                _10108 = _10010;
            }
            highp vec3 _5388 = _5318 * ((mp_copy_5346 * mp_copy_5346) / max(pow(max(_5329, _5354 * _5354), _7867.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10104 = vec3(0.0);
            if (_5316 > 1.5)
            {
                highp vec4 _7884 = textureLod(punctual_lights, vec2(0.3125, _7829), 0.0);
                highp float _5407 = clamp((dot(normalize(_7884.xyz), -mp_copy_5334) * _7884.w) + _7867.x, 0.0, 1.0);
                float mp_copy_5407 = _5407;
                highp vec3 _5412 = _5388 * (mp_copy_5407 * mp_copy_5407);
                if (_5407 <= 0.0)
                {
                    _10398 = _10067;
                    continue;
                }
                bool _5418 = _5407 > 0.0;
                bool _5424 = false;
                if (_5418)
                {
                    _5424 = _7867.y > (-0.5);
                }
                else
                {
                    _5424 = _5418;
                }
                bool _5430 = false;
                if (_5424)
                {
                    _5430 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5430 = _5424;
                }
                highp vec3 _10105 = vec3(0.0);
                if (_5430)
                {
                    float _10083 = 0.0;
                    do
                    {
                        highp vec4 _7996 = mat4(textureLod(punctual_lights, vec2(0.5625, _7829), 0.0), textureLod(punctual_lights, vec2(0.6875, _7829), 0.0), textureLod(punctual_lights, vec2(0.8125, _7829), 0.0), textureLod(punctual_lights, vec2(0.9375, _7829), 0.0)) * vec4(v_position + (_4244 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _7998 = _7996.w;
                        if (_7998 <= 0.0)
                        {
                            _10083 = 1.0;
                            break;
                        }
                        highp vec3 _8007 = _7996.xyz / vec3(_7998);
                        highp vec2 _8012 = (_8007.xy * 0.5) + vec2(0.5);
                        highp float _8014 = _8012.x;
                        bool _8015 = _8014 < 0.0;
                        bool _8022 = false;
                        if (!_8015)
                        {
                            _8022 = _8014 > 1.0;
                        }
                        else
                        {
                            _8022 = _8015;
                        }
                        bool _8029 = false;
                        if (!_8022)
                        {
                            _8029 = _8012.y < 0.0;
                        }
                        else
                        {
                            _8029 = _8022;
                        }
                        bool _8036 = false;
                        if (!_8029)
                        {
                            _8036 = _8012.y > 1.0;
                        }
                        else
                        {
                            _8036 = _8029;
                        }
                        bool _8043 = false;
                        if (!_8036)
                        {
                            _8043 = _8007.z < 0.0;
                        }
                        else
                        {
                            _8043 = _8036;
                        }
                        bool _8050 = false;
                        if (!_8043)
                        {
                            _8050 = _8007.z > 1.0;
                        }
                        else
                        {
                            _8050 = _8043;
                        }
                        if (_8050)
                        {
                            _10083 = 1.0;
                            break;
                        }
                        highp float _8057 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8062 = frag_info.shadow_cascade_count + float(int(_7867.y + 0.5));
                        highp float _8067 = _8007.z - frag_info.spot_shadow_params.y;
                        highp float _8078 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8078 = _8078;
                        highp vec2 _8085 = vec2(cos(mp_copy_8078), sin(mp_copy_8078)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8087 = _8085.x;
                        highp float _8089 = _8085.y;
                        highp vec2 _8097 = vec2(_8087 - _8089, _8087 + _8089) * 0.707106769084930419921875;
                        highp float _8290 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8014, 0.0, 1.0)) / _8057, 1.0 - clamp(_8012.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8290 = _8290;
                        highp vec2 _8105 = _8012 + _8085;
                        highp float _8312 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8105.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8105.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8312 = _8312;
                        highp vec2 _8113 = _8012 - _8085;
                        highp float _8334 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8113.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8113.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8334 = _8334;
                        highp vec2 _8126 = _8012 + vec2(-_8089, _8087);
                        highp float _8356 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8126.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8126.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8356 = _8356;
                        highp vec2 _8139 = _8012 + vec2(_8089, -_8087);
                        highp float _8378 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8139.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8139.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8378 = _8378;
                        float _8144 = (((mp_copy_8290 + mp_copy_8312) + mp_copy_8334) + mp_copy_8356) + mp_copy_8378;
                        if ((_8144 < 0.5) || (_8144 > 4.5))
                        {
                            _10083 = _8144 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8156 = _8012 + _8097;
                        highp float _8400 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8156.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8156.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8400 = _8400;
                        highp vec2 _8163 = _8012 - _8097;
                        highp float _8422 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8163.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8163.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8422 = _8422;
                        highp float _8171 = _8097.y;
                        highp float _8174 = _8097.x;
                        highp vec2 _8176 = _8012 + vec2(-_8171, _8174);
                        highp float _8444 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8176.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8176.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8444 = _8444;
                        highp vec2 _8189 = _8012 + vec2(_8171, -_8174);
                        highp float _8466 = float(_8067 <= textureLod(shadow_map, vec2((_8062 + clamp(_8189.x, 0.0, 1.0)) / _8057, 1.0 - clamp(_8189.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8466 = _8466;
                        _10083 = (_8144 + (((mp_copy_8400 + mp_copy_8422) + mp_copy_8444) + mp_copy_8466)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10105 = _5412 * _10083;
                }
                else
                {
                    _10105 = _5412;
                }
                _10104 = _10105;
            }
            else
            {
                _10104 = _5388;
            }
            _10106 = _10108;
            _10103 = _10104;
            _10092 = _5334;
        }
        hp_copy_10106 = _10106;
        highp vec3 _10121 = vec3(0.0);
        highp vec3 _10122 = vec3(0.0);
        do
        {
            float _8549 = max(dot(_9962, _10092), 0.0);
            highp float hp_copy_8549 = _8549;
            if (_8549 <= 0.0)
            {
                _10122 = vec3(0.0);
                _10121 = vec3(0.0);
                break;
            }
            float _8555 = max(_5281, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8555 = _8555;
            vec3 _8558 = _10092 + mp_copy_10021;
            float _8561 = dot(_8558, _8558);
            vec3 _10119 = vec3(0.0);
            vec3 _10120 = vec3(0.0);
            if (_8561 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8569 = _8558 * inversesqrt(_8561);
                float _10118 = 0.0;
                do
                {
                    float _8626 = dot(_9962, _8569);
                    if (_8626 <= 0.0)
                    {
                        _10118 = 0.0;
                        break;
                    }
                    float _8633 = _10106 * _10106;
                    vec3 _8636 = cross(_9962, _8569);
                    float _8639 = _8626 * _8633;
                    float _8648 = _8633 / (dot(_8636, _8636) + (_8639 * _8639));
                    _10118 = min((_8648 * _8648) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8686 = _5277 + ((vec3(1.0) - _5277) * pow(clamp(1.0 - max(dot(_8569, _10021), 0.0), 0.0, 1.0), 5.0));
                _10120 = (_8686 * min(_10118 * (0.5 / max(mix((2.0 * hp_copy_8549) * _8555, hp_copy_8549 + hp_copy_8555, hp_copy_10106 * hp_copy_10106), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10119 = _8686;
            }
            else
            {
                _10120 = vec3(0.0);
                _10119 = _5277;
            }
            _10122 = (_10120 * _10103) * _8549;
            _10121 = (((((vec3(1.0) - _10119) * (1.0 - _4378)) * _5208) * 0.3183098733425140380859375) * _10103) * _8549;
            break;
        } while(false);
        _10398 = _10067 + (_10121 + _10122);
    }
    bool _8910 = false;
    highp vec3 hp_copy_10024 = vec3(0.0);
    mat3 _5485 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5493 = _5485 * vec3(_9962.x, _9962.y, _9962.z);
    vec3 _5496 = _5485 * reflect(-mp_copy_10021, _9962);
    float _8729 = _5493.y;
    float _8736 = _5493.z;
    float _8743 = _5493.x;
    float _8751 = 1.09254801273345947265625 * _8743;
    vec3 _5499 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8729))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8736))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8743))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8751 * _8729))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8729) * _8736))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8736) * _8736) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8751 * _8736))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8743 * _8743) - (_8729 * _8729)))), vec3(0.0));
    highp vec3 hp_copy_5499 = _5499;
    vec3 _10024 = vec3(0.0);
    do
    {
        _8910 = radiance_layout_info.mip_layout > 0.5;
        if (_8910)
        {
            vec2 _8989 = vec2(atan(_5496.z, _5496.x), asin(clamp(_5496.y, -1.0, 1.0)));
            highp vec2 hp_copy_8989 = _8989;
            _10024 = textureLod(prefiltered_radiance, (hp_copy_8989 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10010, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9008 = vec2(atan(_5496.z, _5496.x), asin(clamp(_5496.y, -1.0, 1.0)));
        highp vec2 hp_copy_9008 = _9008;
        highp vec2 _9013 = (hp_copy_9008 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8920 = clamp(_9013.y, 0.00390625, 0.99609375);
        float _8924 = clamp(_10010, 0.0, 1.0) * 7.0;
        float _8926 = floor(_8924);
        highp float _8945 = _9013.x;
        _10024 = mix(textureLod(prefiltered_radiance, vec2(_8945, (_8926 + _8920) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8945, (min(_8926 + 1.0, 7.0) + _8920) * 0.125), 0.0).xyz, vec3(_8924 - _8926));
        break;
    } while(false);
    hp_copy_10024 = _10024;
    highp vec3 _10030 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_10025 = vec3(0.0);
        vec3 _10025 = vec3(0.0);
        do
        {
            if (_8910)
            {
                vec2 _9118 = vec2(atan(_5496.z, _5496.x), asin(clamp(_5496.y, -1.0, 1.0)));
                highp vec2 hp_copy_9118 = _9118;
                _10025 = textureLod(prefiltered_radiance_b, (hp_copy_9118 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10010, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9137 = vec2(atan(_5496.z, _5496.x), asin(clamp(_5496.y, -1.0, 1.0)));
            highp vec2 hp_copy_9137 = _9137;
            highp vec2 _9142 = (hp_copy_9137 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9049 = clamp(_9142.y, 0.00390625, 0.99609375);
            float _9053 = clamp(_10010, 0.0, 1.0) * 7.0;
            float _9055 = floor(_9053);
            highp float _9074 = _9142.x;
            _10025 = mix(textureLod(prefiltered_radiance_b, vec2(_9074, (_9055 + _9049) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9074, (min(_9055 + 1.0, 7.0) + _9049) * 0.125), 0.0).xyz, vec3(_9053 - _9055));
            break;
        } while(false);
        hp_copy_10025 = _10025;
        _10030 = hp_copy_10024 + hp_copy_10025;
    }
    else
    {
        _10030 = _10024;
    }
    float _5514 = frag_info.environment_intensity;
    highp float hp_copy_5514 = _5514;
    vec2 _5527 = clamp(vec2(_5285, _10010), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5529 = texture(brdf_lut, vec2(_5527.x * 0.3333333432674407958984375, _5527.y));
    float _5533 = _5529.x;
    float _5536 = _5529.y;
    vec3 _5538 = ((_5277 + ((max(vec3(1.0 - _10010), _5277) - _5277) * pow(clamp(1.0 - _5285, 0.0, 1.0), 5.0))) * _5533) + vec3(_5536);
    float _5544 = 1.0 - (_5533 + _5536);
    vec3 _5548 = vec3(1.0) - _5277;
    vec3 _5551 = _5277 + (_5548 * vec3(0.0476190485060214996337890625));
    vec3 _5562 = ((_5538 * _5544) * _5551) / (vec3(1.0) - (_5551 * _5544));
    float _5565 = 1.0 - _4378;
    float _10044 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _10044 = clamp((pow(_5281 + _10039, exp2(((-16.0) * _10010) - 1.0)) - 1.0) + _10039, 0.0, 1.0);
    }
    else
    {
        _10044 = _10039;
    }
    highp vec3 _10077 = vec3(0.0);
    if (_5233)
    {
        highp vec3 _10061 = vec3(0.0);
        highp vec3 _10062 = vec3(0.0);
        do
        {
            float _9231 = max(dot(_9962, _10053), 0.0);
            highp float hp_copy_9231 = _9231;
            if (_9231 <= 0.0)
            {
                _10062 = vec3(0.0);
                _10061 = vec3(0.0);
                break;
            }
            float _9237 = max(_5281, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9237 = _9237;
            vec3 _9240 = _10053 + mp_copy_10021;
            float _9243 = dot(_9240, _9240);
            vec3 _10059 = vec3(0.0);
            vec3 _10060 = vec3(0.0);
            if (_9243 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9251 = _9240 * inversesqrt(_9243);
                float _10058 = 0.0;
                do
                {
                    float _9308 = dot(_9962, _9251);
                    if (_9308 <= 0.0)
                    {
                        _10058 = 0.0;
                        break;
                    }
                    float _9315 = _10010 * _10010;
                    vec3 _9318 = cross(_9962, _9251);
                    float _9321 = _9308 * _9315;
                    float _9330 = _9315 / (dot(_9318, _9318) + (_9321 * _9321));
                    _10058 = min((_9330 * _9330) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9368 = _5277 + (_5548 * pow(clamp(1.0 - max(dot(_9251, _10021), 0.0), 0.0, 1.0), 5.0));
                _10060 = (_9368 * min(_10058 * (0.5 / max(mix((2.0 * hp_copy_9231) * _9237, hp_copy_9231 + hp_copy_9237, hp_copy_10010 * hp_copy_10010), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10059 = _9368;
            }
            else
            {
                _10060 = vec3(0.0);
                _10059 = _5277;
            }
            _10062 = (_10060 * frag_info.directional_light_color.xyz) * _9231;
            _10061 = (((((vec3(1.0) - _10059) * _5565) * _5208) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9231;
            break;
        } while(false);
        _10077 = _10067 + ((_10061 + _10062) * _5268);
    }
    else
    {
        _10077 = _10067;
    }
    vec4 _10079 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10079 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10079 = vec4(min(((((((_5562 + ((_5208 * _5565) * ((vec3(1.0) - _5538) - _5562))) * (hp_copy_5499 * hp_copy_5514)) * vec3(_4412)) + (((_5538 * (_10030 * _5514)) * 1.0) * _10044)) * mix(1.0, _5268, frag_info.radiance_blend.y)) + (_10077 * mix(1.0, _10039, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9985, vec3(65504.0)), 1.0) * _10448;
        break;
    } while(false);
    frag_color = _10079;
    float _10080 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10080 = 1.0;
    }
    else
    {
        _10080 = abs(frag_info.fade);
    }
    frag_color *= _10080;
}

