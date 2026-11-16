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

layout(std140) uniform FogInfo
{
    highp vec4 params0;
    highp vec4 params1;
    highp vec4 params2;
    vec4 color;
    vec4 sun;
    vec4 sun_dir;
} _FogInfo;

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

uniform highp sampler2D punctual_lights;
uniform highp sampler2D punctual_index;
uniform highp sampler2D shadow_map;
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
    highp float _2945 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_2945 = _2945;
    vec3 _2949 = normalize(v_normal) * mp_copy_2945;
    vec4 _2991 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _2994 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _6697 = vec2(0.0);
    if (_2994)
    {
        highp vec2 _6696 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _6696 = v_texture_coords_1;
        }
        else
        {
            _6696 = v_texture_coords;
        }
        highp vec2 _3197 = _6696 * texture_transforms.base_color_transform.zw;
        highp float _3203 = _3197.x;
        highp float _3208 = _3197.y;
        _6697 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _3203) + (texture_transforms.base_color_rotation.y * _3208), ((-texture_transforms.base_color_rotation.y) * _3203) + (texture_transforms.base_color_rotation.x * _3208));
    }
    else
    {
        _6697 = v_texture_coords;
    }
    vec4 _3008 = texture(base_color_texture, _6697);
    vec3 _3010 = _3008.xyz;
    float _6945 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3008.w * _2991.w) * frag_info.color.w);
    vec3 _6712 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _6700 = vec2(0.0);
        if (_2994)
        {
            highp vec2 _6699 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _6699 = v_texture_coords_1;
            }
            else
            {
                _6699 = v_texture_coords;
            }
            highp vec2 _3292 = _6699 * texture_transforms.normal_transform.zw;
            highp float _3298 = _3292.x;
            highp float _3303 = _3292.y;
            _6700 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _3298) + (texture_transforms.normal_rotation.y * _3303), ((-texture_transforms.normal_rotation.y) * _3298) + (texture_transforms.normal_rotation.x * _3303));
        }
        else
        {
            _6700 = v_texture_coords;
        }
        vec3 _3348 = ((texture(normal_texture, _6700).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _3352 = _3348.xy * vec2(frag_info.normal_scale);
        vec3 _6535 = _3348;
        _6535.x = _3352.x;
        _6535.y = _3352.y;
        highp vec3 _3358 = -v_viewvector;
        highp vec3 _3448 = dFdx(_3358);
        highp vec3 _3450 = dFdy(_3358);
        highp vec2 _3452 = dFdx(_6700);
        highp vec2 _3454 = dFdy(_6700);
        bvec2 _6947 = bvec2(length(_3452) == 0.0);
        highp vec2 _6948 = vec2(_6947.x ? vec2(1.0, 0.0).x : _3452.x, _6947.y ? vec2(1.0, 0.0).y : _3452.y);
        bvec2 _6949 = bvec2(length(_3454) == 0.0);
        highp vec2 _6950 = vec2(_6949.x ? vec2(0.0, 1.0).x : _3454.x, _6949.y ? vec2(0.0, 1.0).y : _3454.y);
        highp vec3 _3467 = cross(_3450, _2949);
        highp vec3 _3470 = cross(_2949, _3448);
        highp float _3495 = (dot(cross(_3448, _3450), _2949) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _3498 = ((_3467 * _6948.x) + (_3470 * _6950.x)) * _3495;
        highp float _6707 = 0.0;
        if (gl_FrontFacing)
        {
            _6707 = -_3495;
        }
        else
        {
            _6707 = _3495;
        }
        highp vec3 _3508 = ((_3467 * _6948.y) + (_3470 * _6950.y)) * _6707;
        highp float _3517 = inversesqrt(max(max(dot(_3498, _3498), dot(_3508, _3508)), 9.9999996826552253889678874634872e-21));
        vec3 _3389 = v_tangent.xyz - (_2949 * dot(_2949, v_tangent.xyz));
        highp float _3392 = dot(_3389, _3389);
        bool _3394 = _3392 > 1.0000000133514319600180897396058e-10;
        bool _3401 = false;
        if (_3394)
        {
            _3401 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _3401 = _3394;
        }
        mat3 _6710 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_3401)
        {
            highp vec3 _3406 = _3389 * inversesqrt(_3392);
            _6710 = mat3(_3406, normalize(cross(_2949, _3406)) * sign(v_tangent.w), _2949);
        }
        else
        {
            _6710 = mat3(_3498 * _3517, _3508 * _3517, _2949);
        }
        _6712 = normalize(_6710 * _6535);
    }
    else
    {
        _6712 = _2949;
    }
    highp vec2 _6714 = vec2(0.0);
    if (_2994)
    {
        highp vec2 _6713 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _6713 = v_texture_coords_1;
        }
        else
        {
            _6713 = v_texture_coords;
        }
        highp vec2 _3585 = _6713 * texture_transforms.metallic_roughness_transform.zw;
        highp float _3591 = _3585.x;
        highp float _3596 = _3585.y;
        _6714 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _3591) + (texture_transforms.metallic_roughness_rotation.y * _3596), ((-texture_transforms.metallic_roughness_rotation.y) * _3591) + (texture_transforms.metallic_roughness_rotation.x * _3596));
    }
    else
    {
        _6714 = v_texture_coords;
    }
    vec4 _3077 = texture(metallic_roughness_texture, _6714);
    float _3083 = clamp(_3077.z * frag_info.metallic_factor, 0.0, 1.0);
    float _3090 = clamp(_3077.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _6716 = vec2(0.0);
    if (_2994)
    {
        highp vec2 _6715 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _6715 = v_texture_coords_1;
        }
        else
        {
            _6715 = v_texture_coords;
        }
        highp vec2 _3656 = _6715 * texture_transforms.occlusion_transform.zw;
        highp float _3662 = _3656.x;
        highp float _3667 = _3656.y;
        _6716 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _3662) + (texture_transforms.occlusion_rotation.y * _3667), ((-texture_transforms.occlusion_rotation.y) * _3662) + (texture_transforms.occlusion_rotation.x * _3667));
    }
    else
    {
        _6716 = v_texture_coords;
    }
    float _6717 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _6717 = texture(occlusion_texture, _6716).x;
    }
    else
    {
        _6717 = 1.0;
    }
    float _3117 = 1.0 - ((1.0 - _6717) * frag_info.occlusion_strength);
    highp vec2 _6719 = vec2(0.0);
    if (_2994)
    {
        highp vec2 _6718 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _6718 = v_texture_coords_1;
        }
        else
        {
            _6718 = v_texture_coords;
        }
        highp vec2 _3727 = _6718 * texture_transforms.emissive_transform.zw;
        highp float _3733 = _3727.x;
        highp float _3738 = _3727.y;
        _6719 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _3733) + (texture_transforms.emissive_rotation.y * _3738), ((-texture_transforms.emissive_rotation.y) * _3733) + (texture_transforms.emissive_rotation.x * _3738));
    }
    else
    {
        _6719 = v_texture_coords;
    }
    vec3 _3136 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _6735 = vec3(0.0);
    if (dot(abs(_3136), vec3(1.0)) > 0.0)
    {
        vec3 _3145 = texture(emissive_texture, _6719).xyz;
        _6735 = mix(_3145 * vec3(0.077399380505084991455078125), pow((_3145 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3145)) * _3136;
    }
    else
    {
        _6735 = vec3(0.0);
    }
    vec3 _3897 = vec4((mix(_3010 * vec3(0.077399380505084991455078125), pow((_3010 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3010)) * _2991.xyz) * frag_info.color.xyz, _6945).xyz;
    vec3 _4325 = dFdx(_6712);
    vec3 _4327 = dFdy(_6712);
    float _6760 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _6760 = sqrt(clamp((_3090 * _3090) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_4325, _4325), dot(_4327, _4327))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _6760 = _3090;
    }
    float _6776 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _6776 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _6776 = _3117;
    }
    vec3 mp_copy_6761 = vec3(0.0);
    bool _4364 = view_info.camera_forward.w > 0.5;
    highp vec3 _6761 = vec3(0.0);
    if (_4364)
    {
        _6761 = -view_info.camera_forward.xyz;
    }
    else
    {
        _6761 = normalize(v_viewvector);
    }
    highp float _4408 = 0.0;
    mp_copy_6761 = _6761;
    vec3 _3934 = mix(frag_info.dielectric_f0.xyz, _3897, vec3(_3083));
    float _3938 = max(dot(_6712, _6761), 0.0);
    float _3942 = max(dot(_2949, _6761), 0.0);
    highp vec2 _6762 = vec2(0.0);
    do
    {
        _4408 = frag_info.punctual_dims.x;
        if (_4408 < 0.5)
        {
            _6762 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _4420 = v_position - frag_info.camera_position.xyz;
            highp float _4435 = dot(_4420, frag_info.camera_forward.xyz);
            highp float _4441 = max(_4435, 9.9999997473787516355514526367188e-05);
            highp vec2 _4544 = (vec3(dot(_4420, frag_info.camera_right.xyz), dot(_4420, frag_info.camera_up.xyz), _4441).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_4441, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _4559 = float(int(((((clamp(floor((log2(max(_4435 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_4544.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_4544.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _6762 = vec2(textureLod(punctual_index, vec2((mod(_4559, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4559 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _6762 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _3951 = int(_6762.x + 0.5);
    mediump int _3955 = int(_6762.y + 0.5);
    highp vec3 _6783 = vec3(0.0);
    _6783 = vec3(0.0);
    highp vec3 _6896 = vec3(0.0);
    for (int _6763 = 0; _6763 < _3955; _6783 = _6896, _6763++)
    {
        highp float hp_copy_6832 = 0.0;
        highp float _4592 = float(_3951 + _6763);
        highp float _4623 = (float(int(textureLod(punctual_index, vec2((mod(_4592, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4592 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _4408;
        highp vec4 _4627 = textureLod(punctual_lights, vec2(0.0625, _4623), 0.0);
        highp vec4 _4644 = textureLod(punctual_lights, vec2(0.1875, _4623), 0.0);
        highp float _3973 = _4627.w;
        highp vec3 _3975 = _4644.xyz;
        vec3 _6818 = vec3(0.0);
        highp vec3 _6829 = vec3(0.0);
        float _6832 = 0.0;
        if (_3973 < 0.5)
        {
            _6832 = _6760;
            _6829 = _3975;
            _6818 = -normalize(textureLod(punctual_lights, vec2(0.3125, _4623), 0.0).xyz);
        }
        else
        {
            highp vec3 _3983 = _4627.xyz - v_position;
            highp float _3986 = dot(_3983, _3983);
            highp float _3990 = inversesqrt(max(_3986, 9.9999999392252902907785028219223e-09));
            highp vec3 _3991 = _3983 * _3990;
            vec3 mp_copy_3991 = _3991;
            highp float _3993 = _4644.w;
            highp float _3998 = (_3986 * _3993) * _3993;
            highp float _4003 = clamp(1.0 - (_3998 * _3998), 0.0, 1.0);
            float mp_copy_4003 = _4003;
            if (_4003 <= 0.0)
            {
                _6896 = _6783;
                continue;
            }
            highp vec4 _4661 = textureLod(punctual_lights, vec2(0.4375, _4623), 0.0);
            highp float _4011 = _4661.w;
            float _6834 = 0.0;
            if (_4011 > 0.0)
            {
                highp float _4038 = (_6760 * _6760) + ((_4011 * 0.5) * _3990);
                float mp_copy_4038 = _4038;
                _6834 = sqrt(min(mp_copy_4038, 1.0));
            }
            else
            {
                _6834 = _6760;
            }
            highp vec3 _4045 = _3975 * ((mp_copy_4003 * mp_copy_4003) / max(pow(max(_3986, _4011 * _4011), _4661.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _6830 = vec3(0.0);
            if (_3973 > 1.5)
            {
                highp vec4 _4678 = textureLod(punctual_lights, vec2(0.3125, _4623), 0.0);
                highp float _4064 = clamp((dot(normalize(_4678.xyz), -mp_copy_3991) * _4678.w) + _4661.x, 0.0, 1.0);
                float mp_copy_4064 = _4064;
                highp vec3 _4069 = _4045 * (mp_copy_4064 * mp_copy_4064);
                if (_4064 <= 0.0)
                {
                    _6896 = _6783;
                    continue;
                }
                bool _4075 = _4064 > 0.0;
                bool _4081 = false;
                if (_4075)
                {
                    _4081 = _4661.y > (-0.5);
                }
                else
                {
                    _4081 = _4075;
                }
                bool _4087 = false;
                if (_4081)
                {
                    _4087 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _4087 = _4081;
                }
                highp vec3 _6831 = vec3(0.0);
                if (_4087)
                {
                    float _6809 = 0.0;
                    do
                    {
                        highp vec4 _4790 = mat4(textureLod(punctual_lights, vec2(0.5625, _4623), 0.0), textureLod(punctual_lights, vec2(0.6875, _4623), 0.0), textureLod(punctual_lights, vec2(0.8125, _4623), 0.0), textureLod(punctual_lights, vec2(0.9375, _4623), 0.0)) * vec4(v_position + (_2949 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _4792 = _4790.w;
                        if (_4792 <= 0.0)
                        {
                            _6809 = 1.0;
                            break;
                        }
                        highp vec3 _4801 = _4790.xyz / vec3(_4792);
                        highp vec2 _4806 = (_4801.xy * 0.5) + vec2(0.5);
                        highp float _4808 = _4806.x;
                        bool _4809 = _4808 < 0.0;
                        bool _4816 = false;
                        if (!_4809)
                        {
                            _4816 = _4808 > 1.0;
                        }
                        else
                        {
                            _4816 = _4809;
                        }
                        bool _4823 = false;
                        if (!_4816)
                        {
                            _4823 = _4806.y < 0.0;
                        }
                        else
                        {
                            _4823 = _4816;
                        }
                        bool _4830 = false;
                        if (!_4823)
                        {
                            _4830 = _4806.y > 1.0;
                        }
                        else
                        {
                            _4830 = _4823;
                        }
                        bool _4837 = false;
                        if (!_4830)
                        {
                            _4837 = _4801.z < 0.0;
                        }
                        else
                        {
                            _4837 = _4830;
                        }
                        bool _4844 = false;
                        if (!_4837)
                        {
                            _4844 = _4801.z > 1.0;
                        }
                        else
                        {
                            _4844 = _4837;
                        }
                        if (_4844)
                        {
                            _6809 = 1.0;
                            break;
                        }
                        highp float _4851 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _4856 = frag_info.shadow_cascade_count + float(int(_4661.y + 0.5));
                        highp float _4861 = _4801.z - frag_info.spot_shadow_params.y;
                        highp float _4872 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_4872 = _4872;
                        highp vec2 _4879 = vec2(cos(mp_copy_4872), sin(mp_copy_4872)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _4881 = _4879.x;
                        highp float _4883 = _4879.y;
                        highp vec2 _4891 = vec2(_4881 - _4883, _4881 + _4883) * 0.707106769084930419921875;
                        highp float _5084 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4808, 0.0, 1.0)) / _4851, 1.0 - clamp(_4806.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5084 = _5084;
                        highp vec2 _4899 = _4806 + _4879;
                        highp float _5106 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4899.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4899.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5106 = _5106;
                        highp vec2 _4907 = _4806 - _4879;
                        highp float _5128 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4907.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4907.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5128 = _5128;
                        highp vec2 _4920 = _4806 + vec2(-_4883, _4881);
                        highp float _5150 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4920.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4920.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5150 = _5150;
                        highp vec2 _4933 = _4806 + vec2(_4883, -_4881);
                        highp float _5172 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4933.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4933.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5172 = _5172;
                        float _4938 = (((mp_copy_5084 + mp_copy_5106) + mp_copy_5128) + mp_copy_5150) + mp_copy_5172;
                        if ((_4938 < 0.5) || (_4938 > 4.5))
                        {
                            _6809 = _4938 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _4950 = _4806 + _4891;
                        highp float _5194 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4950.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4950.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5194 = _5194;
                        highp vec2 _4957 = _4806 - _4891;
                        highp float _5216 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4957.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4957.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5216 = _5216;
                        highp float _4965 = _4891.y;
                        highp float _4968 = _4891.x;
                        highp vec2 _4970 = _4806 + vec2(-_4965, _4968);
                        highp float _5238 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4970.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4970.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5238 = _5238;
                        highp vec2 _4983 = _4806 + vec2(_4965, -_4968);
                        highp float _5260 = float(_4861 <= textureLod(shadow_map, vec2((_4856 + clamp(_4983.x, 0.0, 1.0)) / _4851, 1.0 - clamp(_4983.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_5260 = _5260;
                        _6809 = (_4938 + (((mp_copy_5194 + mp_copy_5216) + mp_copy_5238) + mp_copy_5260)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _6831 = _4069 * _6809;
                }
                else
                {
                    _6831 = _4069;
                }
                _6830 = _6831;
            }
            else
            {
                _6830 = _4045;
            }
            _6832 = _6834;
            _6829 = _6830;
            _6818 = _3991;
        }
        hp_copy_6832 = _6832;
        highp vec3 _6847 = vec3(0.0);
        highp vec3 _6848 = vec3(0.0);
        do
        {
            float _5343 = max(dot(_6712, _6818), 0.0);
            highp float hp_copy_5343 = _5343;
            if (_5343 <= 0.0)
            {
                _6848 = vec3(0.0);
                _6847 = vec3(0.0);
                break;
            }
            float _5349 = max(_3938, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_5349 = _5349;
            vec3 _5352 = _6818 + mp_copy_6761;
            float _5355 = dot(_5352, _5352);
            vec3 _6845 = vec3(0.0);
            vec3 _6846 = vec3(0.0);
            if (_5355 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _5363 = _5352 * inversesqrt(_5355);
                float _6844 = 0.0;
                do
                {
                    float _5420 = dot(_6712, _5363);
                    if (_5420 <= 0.0)
                    {
                        _6844 = 0.0;
                        break;
                    }
                    float _5427 = _6832 * _6832;
                    vec3 _5430 = cross(_6712, _5363);
                    float _5433 = _5420 * _5427;
                    float _5442 = _5427 / (dot(_5430, _5430) + (_5433 * _5433));
                    _6844 = min((_5442 * _5442) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _5480 = _3934 + ((vec3(1.0) - _3934) * pow(clamp(1.0 - max(dot(_5363, _6761), 0.0), 0.0, 1.0), 5.0));
                _6846 = (_5480 * min(_6844 * (0.5 / max(mix((2.0 * hp_copy_5343) * _5349, hp_copy_5343 + hp_copy_5349, hp_copy_6832 * hp_copy_6832), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _6845 = _5480;
            }
            else
            {
                _6846 = vec3(0.0);
                _6845 = _3934;
            }
            _6848 = (_6846 * _6829) * _5343;
            _6847 = (((((vec3(1.0) - _6845) * (1.0 - _3083)) * _3897) * 0.3183098733425140380859375) * _6829) * _5343;
            break;
        } while(false);
        _6896 = _6783 + (_6847 + _6848);
    }
    bool _5704 = false;
    highp vec3 hp_copy_6764 = vec3(0.0);
    mat3 _4142 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _4150 = _4142 * vec3(_6712.x, _6712.y, _6712.z);
    vec3 _4153 = _4142 * reflect(-mp_copy_6761, _6712);
    float _5523 = _4150.y;
    float _5530 = _4150.z;
    float _5537 = _4150.x;
    float _5545 = 1.09254801273345947265625 * _5537;
    vec3 _4156 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _5523))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _5530))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _5537))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_5545 * _5523))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _5523) * _5530))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _5530) * _5530) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_5545 * _5530))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_5537 * _5537) - (_5523 * _5523)))), vec3(0.0));
    highp vec3 hp_copy_4156 = _4156;
    vec3 _6764 = vec3(0.0);
    do
    {
        _5704 = radiance_layout_info.mip_layout > 0.5;
        if (_5704)
        {
            vec2 _5783 = vec2(atan(_4153.z, _4153.x), asin(clamp(_4153.y, -1.0, 1.0)));
            highp vec2 hp_copy_5783 = _5783;
            _6764 = textureLod(prefiltered_radiance, (hp_copy_5783 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6760, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _5802 = vec2(atan(_4153.z, _4153.x), asin(clamp(_4153.y, -1.0, 1.0)));
        highp vec2 hp_copy_5802 = _5802;
        highp vec2 _5807 = (hp_copy_5802 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _5714 = clamp(_5807.y, 0.00390625, 0.99609375);
        float _5718 = clamp(_6760, 0.0, 1.0) * 7.0;
        float _5720 = floor(_5718);
        highp float _5739 = _5807.x;
        _6764 = mix(textureLod(prefiltered_radiance, vec2(_5739, (_5720 + _5714) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_5739, (min(_5720 + 1.0, 7.0) + _5714) * 0.125), 0.0).xyz, vec3(_5718 - _5720));
        break;
    } while(false);
    hp_copy_6764 = _6764;
    highp vec3 _6770 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_6765 = vec3(0.0);
        vec3 _6765 = vec3(0.0);
        do
        {
            if (_5704)
            {
                vec2 _5912 = vec2(atan(_4153.z, _4153.x), asin(clamp(_4153.y, -1.0, 1.0)));
                highp vec2 hp_copy_5912 = _5912;
                _6765 = textureLod(prefiltered_radiance_b, (hp_copy_5912 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6760, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _5931 = vec2(atan(_4153.z, _4153.x), asin(clamp(_4153.y, -1.0, 1.0)));
            highp vec2 hp_copy_5931 = _5931;
            highp vec2 _5936 = (hp_copy_5931 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _5843 = clamp(_5936.y, 0.00390625, 0.99609375);
            float _5847 = clamp(_6760, 0.0, 1.0) * 7.0;
            float _5849 = floor(_5847);
            highp float _5868 = _5936.x;
            _6765 = mix(textureLod(prefiltered_radiance_b, vec2(_5868, (_5849 + _5843) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_5868, (min(_5849 + 1.0, 7.0) + _5843) * 0.125), 0.0).xyz, vec3(_5847 - _5849));
            break;
        } while(false);
        hp_copy_6765 = _6765;
        _6770 = hp_copy_6764 + hp_copy_6765;
    }
    else
    {
        _6770 = _6764;
    }
    float _4171 = frag_info.environment_intensity;
    highp float hp_copy_4171 = _4171;
    vec2 _4184 = clamp(vec2(_3942, _6760), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _4186 = texture(brdf_lut, vec2(_4184.x * 0.3333333432674407958984375, _4184.y));
    float _4190 = _4186.x;
    float _4193 = _4186.y;
    vec3 _4195 = ((_3934 + ((max(vec3(1.0 - _6760), _3934) - _3934) * pow(clamp(1.0 - _3942, 0.0, 1.0), 5.0))) * _4190) + vec3(_4193);
    float _4201 = 1.0 - (_4190 + _4193);
    vec3 _4208 = _3934 + ((vec3(1.0) - _3934) * vec3(0.0476190485060214996337890625));
    vec3 _4219 = ((_4195 * _4201) * _4208) / (vec3(1.0) - (_4208 * _4201));
    float _6778 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _6778 = clamp((pow(_3938 + _6776, exp2(((-16.0) * _6760) - 1.0)) - 1.0) + _6776, 0.0, 1.0);
    }
    else
    {
        _6778 = _6776;
    }
    bool _4287 = _FogInfo.params0.y > 0.5;
    bool _4293 = false;
    if (_4287)
    {
        _4293 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _4293 = _4287;
    }
    highp vec3 _6788 = vec3(0.0);
    if (_4293)
    {
        vec3 mp_copy_6786 = vec3(0.0);
        highp vec3 _6786 = vec3(0.0);
        if (_4364)
        {
            _6786 = -view_info.camera_forward.xyz;
        }
        else
        {
            _6786 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_6787 = vec3(0.0);
        mp_copy_6786 = _6786;
        vec3 _4298 = _4142 * (-mp_copy_6786);
        vec3 _6787 = vec3(0.0);
        do
        {
            if (_5704)
            {
                vec2 _6081 = vec2(atan(_4298.z, _4298.x), asin(clamp(_4298.y, -1.0, 1.0)));
                highp vec2 hp_copy_6081 = _6081;
                _6787 = textureLod(prefiltered_radiance, (hp_copy_6081 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _6100 = vec2(atan(_4298.z, _4298.x), asin(clamp(_4298.y, -1.0, 1.0)));
            highp vec2 hp_copy_6100 = _6100;
            highp vec2 _6105 = (hp_copy_6100 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _6012 = clamp(_6105.y, 0.00390625, 0.99609375);
            float _6018 = floor(0.0);
            highp float _6037 = _6105.x;
            _6787 = mix(textureLod(prefiltered_radiance, vec2(_6037, (_6018 + _6012) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_6037, (min(_6018 + 1.0, 7.0) + _6012) * 0.125), 0.0).xyz, vec3(-_6018));
            break;
        } while(false);
        hp_copy_6787 = _6787;
        _6788 = hp_copy_6787 * hp_copy_4171;
    }
    else
    {
        _6788 = _FogInfo.color.xyz;
    }
    highp vec4 _4313 = vec4(min(((((((_4219 + ((_3897 * (1.0 - _3083)) * ((vec3(1.0) - _4195) - _4219))) * (hp_copy_4156 * hp_copy_4171)) * vec3(_3117)) + (((_4195 * (_6770 * _4171)) * 1.0) * _6778)) * mix(1.0, 0.0, frag_info.radiance_blend.y)) + (_6783 * mix(1.0, _6776, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _6735, vec3(65504.0)), 1.0) * _6945;
    highp vec4 _6803 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _6803 = _4313;
            break;
        }
        int _6149 = int(_FogInfo.params0.x + 0.5);
        if (_6149 == 0)
        {
            _6803 = _4313;
            break;
        }
        highp float _6790 = 0.0;
        if (_4364)
        {
            _6790 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _6790 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_6790 > _FogInfo.params1.w))
        {
            _6803 = _4313;
            break;
        }
        float _6794 = 0.0;
        if (_6149 == 1)
        {
            _6794 = clamp((_6790 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _6795 = 0.0;
            if (_6149 == 2)
            {
                highp float _6793 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _6791 = vec3(0.0);
                    if (_4364)
                    {
                        _6791 = v_position - (view_info.camera_forward.xyz * _6790);
                    }
                    else
                    {
                        _6791 = v_position + v_viewvector;
                    }
                    highp float _6240 = -_FogInfo.params2.y;
                    highp float _6247 = _FogInfo.params1.x * exp(_6240 * (_6791.y - _FogInfo.params2.x));
                    highp float _6264 = _FogInfo.params2.y * (v_position.y - _6791.y);
                    highp float _6792 = 0.0;
                    if (abs(_6264) > 0.00124999997206032276153564453125)
                    {
                        _6792 = (_6247 - (_FogInfo.params1.x * exp(_6240 * (v_position.y - _FogInfo.params2.x)))) / _6264;
                    }
                    else
                    {
                        _6792 = _6247;
                    }
                    _6793 = _6792 * max(_6790 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _6793 = _FogInfo.params1.x * max(_6790 - _FogInfo.params1.y, 0.0);
                }
                _6795 = 1.0 - exp(-_6793);
            }
            else
            {
                highp float _6202 = _FogInfo.params1.x * max(_6790 - _FogInfo.params1.y, 0.0);
                _6795 = 1.0 - exp((-_6202) * _6202);
            }
            _6794 = _6795;
        }
        highp float _6304 = min(_6794, _FogInfo.params0.z);
        if (_6304 <= 0.0)
        {
            _6803 = _4313;
            break;
        }
        highp vec3 _6317 = mix(_FogInfo.color.xyz, _6788, vec3(_FogInfo.params0.w));
        bool _6320 = _FogInfo.sun.w > 0.5;
        bool _6326 = false;
        if (_6320)
        {
            _6326 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _6326 = _6320;
        }
        vec3 _6799 = vec3(0.0);
        if (_6326)
        {
            vec3 mp_copy_6796 = vec3(0.0);
            highp vec3 _6796 = vec3(0.0);
            if (_4364)
            {
                _6796 = -view_info.camera_forward.xyz;
            }
            else
            {
                _6796 = normalize(v_viewvector);
            }
            mp_copy_6796 = _6796;
            highp float _6342 = pow(max(dot(-mp_copy_6796, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_6342 = _6342;
            _6799 = _6317 + ((_FogInfo.sun.xyz * mp_copy_6342) * _FogInfo.params2.z);
        }
        else
        {
            _6799 = _6317;
        }
        highp float _6355 = _4313.w;
        float mp_copy_6355 = _6355;
        _6803 = vec4(mix(_4313.xyz, _6799 * mp_copy_6355, vec3(_6304)), _6355);
        break;
    } while(false);
    vec4 _6805 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _6805 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _6805 = _6803;
        break;
    } while(false);
    frag_color = _6805;
    float _6806 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _6806 = 1.0;
    }
    else
    {
        _6806 = abs(frag_info.fade);
    }
    frag_color *= _6806;
}

