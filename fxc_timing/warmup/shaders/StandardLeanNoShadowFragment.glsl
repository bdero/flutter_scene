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
    highp float _2611 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_2611 = _2611;
    vec3 _2615 = normalize(v_normal) * mp_copy_2611;
    vec4 _2657 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _2660 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _5972 = vec2(0.0);
    if (_2660)
    {
        highp vec2 _5971 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _5971 = v_texture_coords_1;
        }
        else
        {
            _5971 = v_texture_coords;
        }
        highp vec2 _2863 = _5971 * texture_transforms.base_color_transform.zw;
        highp float _2869 = _2863.x;
        highp float _2874 = _2863.y;
        _5972 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _2869) + (texture_transforms.base_color_rotation.y * _2874), ((-texture_transforms.base_color_rotation.y) * _2869) + (texture_transforms.base_color_rotation.x * _2874));
    }
    else
    {
        _5972 = v_texture_coords;
    }
    vec4 _2674 = texture(base_color_texture, _5972);
    vec3 _2676 = _2674.xyz;
    float _6186 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_2674.w * _2657.w) * frag_info.color.w);
    vec3 _5987 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _5975 = vec2(0.0);
        if (_2660)
        {
            highp vec2 _5974 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _5974 = v_texture_coords_1;
            }
            else
            {
                _5974 = v_texture_coords;
            }
            highp vec2 _2958 = _5974 * texture_transforms.normal_transform.zw;
            highp float _2964 = _2958.x;
            highp float _2969 = _2958.y;
            _5975 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _2964) + (texture_transforms.normal_rotation.y * _2969), ((-texture_transforms.normal_rotation.y) * _2964) + (texture_transforms.normal_rotation.x * _2969));
        }
        else
        {
            _5975 = v_texture_coords;
        }
        vec3 _3014 = ((texture(normal_texture, _5975).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _3018 = _3014.xy * vec2(frag_info.normal_scale);
        vec3 _5851 = _3014;
        _5851.x = _3018.x;
        _5851.y = _3018.y;
        highp vec3 _3024 = -v_viewvector;
        highp vec3 _3114 = dFdx(_3024);
        highp vec3 _3116 = dFdy(_3024);
        highp vec2 _3118 = dFdx(_5975);
        highp vec2 _3120 = dFdy(_5975);
        bvec2 _6188 = bvec2(length(_3118) == 0.0);
        highp vec2 _6189 = vec2(_6188.x ? vec2(1.0, 0.0).x : _3118.x, _6188.y ? vec2(1.0, 0.0).y : _3118.y);
        bvec2 _6190 = bvec2(length(_3120) == 0.0);
        highp vec2 _6191 = vec2(_6190.x ? vec2(0.0, 1.0).x : _3120.x, _6190.y ? vec2(0.0, 1.0).y : _3120.y);
        highp vec3 _3133 = cross(_3116, _2615);
        highp vec3 _3136 = cross(_2615, _3114);
        highp float _3161 = (dot(cross(_3114, _3116), _2615) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _3164 = ((_3133 * _6189.x) + (_3136 * _6191.x)) * _3161;
        highp float _5982 = 0.0;
        if (gl_FrontFacing)
        {
            _5982 = -_3161;
        }
        else
        {
            _5982 = _3161;
        }
        highp vec3 _3174 = ((_3133 * _6189.y) + (_3136 * _6191.y)) * _5982;
        highp float _3183 = inversesqrt(max(max(dot(_3164, _3164), dot(_3174, _3174)), 9.9999996826552253889678874634872e-21));
        vec3 _3055 = v_tangent.xyz - (_2615 * dot(_2615, v_tangent.xyz));
        highp float _3058 = dot(_3055, _3055);
        bool _3060 = _3058 > 1.0000000133514319600180897396058e-10;
        bool _3067 = false;
        if (_3060)
        {
            _3067 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _3067 = _3060;
        }
        mat3 _5985 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_3067)
        {
            highp vec3 _3072 = _3055 * inversesqrt(_3058);
            _5985 = mat3(_3072, normalize(cross(_2615, _3072)) * sign(v_tangent.w), _2615);
        }
        else
        {
            _5985 = mat3(_3164 * _3183, _3174 * _3183, _2615);
        }
        _5987 = normalize(_5985 * _5851);
    }
    else
    {
        _5987 = _2615;
    }
    highp vec2 _5989 = vec2(0.0);
    if (_2660)
    {
        highp vec2 _5988 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _5988 = v_texture_coords_1;
        }
        else
        {
            _5988 = v_texture_coords;
        }
        highp vec2 _3251 = _5988 * texture_transforms.metallic_roughness_transform.zw;
        highp float _3257 = _3251.x;
        highp float _3262 = _3251.y;
        _5989 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _3257) + (texture_transforms.metallic_roughness_rotation.y * _3262), ((-texture_transforms.metallic_roughness_rotation.y) * _3257) + (texture_transforms.metallic_roughness_rotation.x * _3262));
    }
    else
    {
        _5989 = v_texture_coords;
    }
    vec4 _2743 = texture(metallic_roughness_texture, _5989);
    float _2749 = clamp(_2743.z * frag_info.metallic_factor, 0.0, 1.0);
    float _2756 = clamp(_2743.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _5991 = vec2(0.0);
    if (_2660)
    {
        highp vec2 _5990 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _5990 = v_texture_coords_1;
        }
        else
        {
            _5990 = v_texture_coords;
        }
        highp vec2 _3322 = _5990 * texture_transforms.occlusion_transform.zw;
        highp float _3328 = _3322.x;
        highp float _3333 = _3322.y;
        _5991 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _3328) + (texture_transforms.occlusion_rotation.y * _3333), ((-texture_transforms.occlusion_rotation.y) * _3328) + (texture_transforms.occlusion_rotation.x * _3333));
    }
    else
    {
        _5991 = v_texture_coords;
    }
    float _5992 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _5992 = texture(occlusion_texture, _5991).x;
    }
    else
    {
        _5992 = 1.0;
    }
    float _2783 = 1.0 - ((1.0 - _5992) * frag_info.occlusion_strength);
    highp vec2 _5994 = vec2(0.0);
    if (_2660)
    {
        highp vec2 _5993 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _5993 = v_texture_coords_1;
        }
        else
        {
            _5993 = v_texture_coords;
        }
        highp vec2 _3393 = _5993 * texture_transforms.emissive_transform.zw;
        highp float _3399 = _3393.x;
        highp float _3404 = _3393.y;
        _5994 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _3399) + (texture_transforms.emissive_rotation.y * _3404), ((-texture_transforms.emissive_rotation.y) * _3399) + (texture_transforms.emissive_rotation.x * _3404));
    }
    else
    {
        _5994 = v_texture_coords;
    }
    vec3 _2802 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _6010 = vec3(0.0);
    if (dot(abs(_2802), vec3(1.0)) > 0.0)
    {
        vec3 _2811 = texture(emissive_texture, _5994).xyz;
        _6010 = mix(_2811 * vec3(0.077399380505084991455078125), pow((_2811 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _2811)) * _2802;
    }
    else
    {
        _6010 = vec3(0.0);
    }
    highp float hp_copy_6035 = 0.0;
    vec3 _3571 = vec4((mix(_2676 * vec3(0.077399380505084991455078125), pow((_2676 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _2676)) * _2657.xyz) * frag_info.color.xyz, _6186).xyz;
    vec3 _4011 = dFdx(_5987);
    vec3 _4013 = dFdy(_5987);
    float _6035 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _6035 = sqrt(clamp((_2756 * _2756) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_4011, _4011), dot(_4013, _4013))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _6035 = _2756;
    }
    hp_copy_6035 = _6035;
    float _6053 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _6053 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _6053 = _2783;
    }
    bool _3596 = frag_info.has_directional_light > 0.5;
    float _6036 = 0.0;
    vec3 _6062 = vec3(0.0);
    if (_3596)
    {
        highp vec3 _3602 = -normalize(frag_info.directional_light_direction.xyz);
        _6062 = _3602;
        _6036 = dot(_2615, _3602);
    }
    else
    {
        _6062 = vec3(0.0);
        _6036 = 0.0;
    }
    vec3 mp_copy_6037 = vec3(0.0);
    float _3609 = clamp(_6036 * 6.666666507720947265625, 0.0, 1.0);
    bool _4059 = view_info.camera_forward.w > 0.5;
    highp vec3 _6037 = vec3(0.0);
    if (_4059)
    {
        _6037 = -view_info.camera_forward.xyz;
    }
    else
    {
        _6037 = normalize(v_viewvector);
    }
    highp float _4103 = 0.0;
    mp_copy_6037 = _6037;
    vec3 _3621 = mix(frag_info.dielectric_f0.xyz, _3571, vec3(_2749));
    float _3625 = max(dot(_5987, _6037), 0.0);
    float _3629 = max(dot(_2615, _6037), 0.0);
    highp vec2 _6038 = vec2(0.0);
    do
    {
        _4103 = frag_info.punctual_dims.x;
        if (_4103 < 0.5)
        {
            _6038 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _4115 = v_position - frag_info.camera_position.xyz;
            highp float _4130 = dot(_4115, frag_info.camera_forward.xyz);
            highp float _4136 = max(_4130, 9.9999997473787516355514526367188e-05);
            highp vec2 _4239 = (vec3(dot(_4115, frag_info.camera_right.xyz), dot(_4115, frag_info.camera_up.xyz), _4136).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_4136, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _4254 = float(int(((((clamp(floor((log2(max(_4130 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_4239.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_4239.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _6038 = vec2(textureLod(punctual_index, vec2((mod(_4254, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4254 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _6038 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _3638 = int(_6038.x + 0.5);
    mediump int _3642 = int(_6038.y + 0.5);
    highp vec3 _6073 = vec3(0.0);
    _6073 = vec3(0.0);
    highp vec3 _6146 = vec3(0.0);
    for (int _6039 = 0; _6039 < _3642; _6073 = _6146, _6039++)
    {
        highp float hp_copy_6111 = 0.0;
        highp float _4287 = float(_3638 + _6039);
        highp float _4318 = (float(int(textureLod(punctual_index, vec2((mod(_4287, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4287 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _4103;
        highp vec4 _4322 = textureLod(punctual_lights, vec2(0.0625, _4318), 0.0);
        highp vec4 _4339 = textureLod(punctual_lights, vec2(0.1875, _4318), 0.0);
        highp float _3660 = _4322.w;
        highp vec3 _3662 = _4339.xyz;
        vec3 _6107 = vec3(0.0);
        highp vec3 _6109 = vec3(0.0);
        float _6111 = 0.0;
        if (_3660 < 0.5)
        {
            _6111 = _6035;
            _6109 = _3662;
            _6107 = -normalize(textureLod(punctual_lights, vec2(0.3125, _4318), 0.0).xyz);
        }
        else
        {
            highp vec3 _3670 = _4322.xyz - v_position;
            highp float _3673 = dot(_3670, _3670);
            highp float _3677 = inversesqrt(max(_3673, 9.9999999392252902907785028219223e-09));
            highp vec3 _3678 = _3670 * _3677;
            vec3 mp_copy_3678 = _3678;
            highp float _3680 = _4339.w;
            highp float _3685 = (_3673 * _3680) * _3680;
            highp float _3690 = clamp(1.0 - (_3685 * _3685), 0.0, 1.0);
            float mp_copy_3690 = _3690;
            if (_3690 <= 0.0)
            {
                _6146 = _6073;
                continue;
            }
            highp vec4 _4356 = textureLod(punctual_lights, vec2(0.4375, _4318), 0.0);
            highp float _3698 = _4356.w;
            float _6113 = 0.0;
            if (_3698 > 0.0)
            {
                highp float _3725 = (_6035 * _6035) + ((_3698 * 0.5) * _3677);
                float mp_copy_3725 = _3725;
                _6113 = sqrt(min(mp_copy_3725, 1.0));
            }
            else
            {
                _6113 = _6035;
            }
            highp vec3 _3732 = _3662 * ((mp_copy_3690 * mp_copy_3690) / max(pow(max(_3673, _3698 * _3698), _4356.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _6110 = vec3(0.0);
            if (_3660 > 1.5)
            {
                highp vec4 _4373 = textureLod(punctual_lights, vec2(0.3125, _4318), 0.0);
                highp float _3751 = clamp((dot(normalize(_4373.xyz), -mp_copy_3678) * _4373.w) + _4356.x, 0.0, 1.0);
                float mp_copy_3751 = _3751;
                if (_3751 <= 0.0)
                {
                    _6146 = _6073;
                    continue;
                }
                _6110 = _3732 * (mp_copy_3751 * mp_copy_3751);
            }
            else
            {
                _6110 = _3732;
            }
            _6111 = _6113;
            _6109 = _6110;
            _6107 = _3678;
        }
        hp_copy_6111 = _6111;
        highp vec3 _6117 = vec3(0.0);
        highp vec3 _6118 = vec3(0.0);
        do
        {
            float _4456 = max(dot(_5987, _6107), 0.0);
            highp float hp_copy_4456 = _4456;
            if (_4456 <= 0.0)
            {
                _6118 = vec3(0.0);
                _6117 = vec3(0.0);
                break;
            }
            float _4462 = max(_3625, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_4462 = _4462;
            vec3 _4465 = _6107 + mp_copy_6037;
            float _4468 = dot(_4465, _4465);
            vec3 _6115 = vec3(0.0);
            vec3 _6116 = vec3(0.0);
            if (_4468 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _4476 = _4465 * inversesqrt(_4468);
                float _6114 = 0.0;
                do
                {
                    float _4533 = dot(_5987, _4476);
                    if (_4533 <= 0.0)
                    {
                        _6114 = 0.0;
                        break;
                    }
                    float _4540 = _6111 * _6111;
                    vec3 _4543 = cross(_5987, _4476);
                    float _4546 = _4533 * _4540;
                    float _4555 = _4540 / (dot(_4543, _4543) + (_4546 * _4546));
                    _6114 = min((_4555 * _4555) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _4593 = _3621 + ((vec3(1.0) - _3621) * pow(clamp(1.0 - max(dot(_4476, _6037), 0.0), 0.0, 1.0), 5.0));
                _6116 = (_4593 * min(_6114 * (0.5 / max(mix((2.0 * hp_copy_4456) * _4462, hp_copy_4456 + hp_copy_4462, hp_copy_6111 * hp_copy_6111), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _6115 = _4593;
            }
            else
            {
                _6116 = vec3(0.0);
                _6115 = _3621;
            }
            _6118 = (_6116 * _6109) * _4456;
            _6117 = (((((vec3(1.0) - _6115) * (1.0 - _2749)) * _3571) * 0.3183098733425140380859375) * _6109) * _4456;
            break;
        } while(false);
        _6146 = _6073 + (_6117 + _6118);
    }
    bool _4817 = false;
    highp vec3 hp_copy_6040 = vec3(0.0);
    mat3 _3802 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _3810 = _3802 * vec3(_5987.x, _5987.y, _5987.z);
    vec3 _3813 = _3802 * reflect(-mp_copy_6037, _5987);
    float _4636 = _3810.y;
    float _4643 = _3810.z;
    float _4650 = _3810.x;
    float _4658 = 1.09254801273345947265625 * _4650;
    vec3 _3816 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _4636))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _4643))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _4650))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_4658 * _4636))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _4636) * _4643))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _4643) * _4643) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_4658 * _4643))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_4650 * _4650) - (_4636 * _4636)))), vec3(0.0));
    highp vec3 hp_copy_3816 = _3816;
    vec3 _6040 = vec3(0.0);
    do
    {
        _4817 = radiance_layout_info.mip_layout > 0.5;
        if (_4817)
        {
            vec2 _4896 = vec2(atan(_3813.z, _3813.x), asin(clamp(_3813.y, -1.0, 1.0)));
            highp vec2 hp_copy_4896 = _4896;
            _6040 = textureLod(prefiltered_radiance, (hp_copy_4896 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6035, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _4915 = vec2(atan(_3813.z, _3813.x), asin(clamp(_3813.y, -1.0, 1.0)));
        highp vec2 hp_copy_4915 = _4915;
        highp vec2 _4920 = (hp_copy_4915 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _4827 = clamp(_4920.y, 0.00390625, 0.99609375);
        float _4831 = clamp(_6035, 0.0, 1.0) * 7.0;
        float _4833 = floor(_4831);
        highp float _4852 = _4920.x;
        _6040 = mix(textureLod(prefiltered_radiance, vec2(_4852, (_4833 + _4827) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_4852, (min(_4833 + 1.0, 7.0) + _4827) * 0.125), 0.0).xyz, vec3(_4831 - _4833));
        break;
    } while(false);
    hp_copy_6040 = _6040;
    highp vec3 _6046 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_6041 = vec3(0.0);
        vec3 _6041 = vec3(0.0);
        do
        {
            if (_4817)
            {
                vec2 _5025 = vec2(atan(_3813.z, _3813.x), asin(clamp(_3813.y, -1.0, 1.0)));
                highp vec2 hp_copy_5025 = _5025;
                _6041 = textureLod(prefiltered_radiance_b, (hp_copy_5025 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6035, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _5044 = vec2(atan(_3813.z, _3813.x), asin(clamp(_3813.y, -1.0, 1.0)));
            highp vec2 hp_copy_5044 = _5044;
            highp vec2 _5049 = (hp_copy_5044 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _4956 = clamp(_5049.y, 0.00390625, 0.99609375);
            float _4960 = clamp(_6035, 0.0, 1.0) * 7.0;
            float _4962 = floor(_4960);
            highp float _4981 = _5049.x;
            _6041 = mix(textureLod(prefiltered_radiance_b, vec2(_4981, (_4962 + _4956) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_4981, (min(_4962 + 1.0, 7.0) + _4956) * 0.125), 0.0).xyz, vec3(_4960 - _4962));
            break;
        } while(false);
        hp_copy_6041 = _6041;
        _6046 = hp_copy_6040 + hp_copy_6041;
    }
    else
    {
        _6046 = _6040;
    }
    float _3831 = frag_info.environment_intensity;
    highp float hp_copy_3831 = _3831;
    vec2 _3844 = clamp(vec2(_3629, _6035), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _3846 = texture(brdf_lut, vec2(_3844.x * 0.3333333432674407958984375, _3844.y));
    float _3850 = _3846.x;
    float _3853 = _3846.y;
    vec3 _3855 = ((_3621 + ((max(vec3(1.0 - _6035), _3621) - _3621) * pow(clamp(1.0 - _3629, 0.0, 1.0), 5.0))) * _3850) + vec3(_3853);
    float _3861 = 1.0 - (_3850 + _3853);
    vec3 _3865 = vec3(1.0) - _3621;
    vec3 _3868 = _3621 + (_3865 * vec3(0.0476190485060214996337890625));
    vec3 _3879 = ((_3855 * _3861) * _3868) / (vec3(1.0) - (_3868 * _3861));
    float _3882 = 1.0 - _2749;
    float _6055 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _6055 = clamp((pow(_3625 + _6053, exp2(((-16.0) * _6035) - 1.0)) - 1.0) + _6053, 0.0, 1.0);
    }
    else
    {
        _6055 = _6053;
    }
    highp vec3 _6083 = vec3(0.0);
    if (_3596)
    {
        highp vec3 _6067 = vec3(0.0);
        highp vec3 _6068 = vec3(0.0);
        do
        {
            float _5138 = max(dot(_5987, _6062), 0.0);
            highp float hp_copy_5138 = _5138;
            if (_5138 <= 0.0)
            {
                _6068 = vec3(0.0);
                _6067 = vec3(0.0);
                break;
            }
            float _5144 = max(_3625, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_5144 = _5144;
            vec3 _5147 = _6062 + mp_copy_6037;
            float _5150 = dot(_5147, _5147);
            vec3 _6065 = vec3(0.0);
            vec3 _6066 = vec3(0.0);
            if (_5150 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _5158 = _5147 * inversesqrt(_5150);
                float _6064 = 0.0;
                do
                {
                    float _5215 = dot(_5987, _5158);
                    if (_5215 <= 0.0)
                    {
                        _6064 = 0.0;
                        break;
                    }
                    float _5222 = _6035 * _6035;
                    vec3 _5225 = cross(_5987, _5158);
                    float _5228 = _5215 * _5222;
                    float _5237 = _5222 / (dot(_5225, _5225) + (_5228 * _5228));
                    _6064 = min((_5237 * _5237) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _5275 = _3621 + (_3865 * pow(clamp(1.0 - max(dot(_5158, _6037), 0.0), 0.0, 1.0), 5.0));
                _6066 = (_5275 * min(_6064 * (0.5 / max(mix((2.0 * hp_copy_5138) * _5144, hp_copy_5138 + hp_copy_5144, hp_copy_6035 * hp_copy_6035), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _6065 = _5275;
            }
            else
            {
                _6066 = vec3(0.0);
                _6065 = _3621;
            }
            _6068 = (_6066 * frag_info.directional_light_color.xyz) * _5138;
            _6067 = (((((vec3(1.0) - _6065) * _3882) * _3571) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _5138;
            break;
        } while(false);
        _6083 = _6073 + ((_6067 + _6068) * _3609);
    }
    else
    {
        _6083 = _6073;
    }
    bool _3973 = _FogInfo.params0.y > 0.5;
    bool _3979 = false;
    if (_3973)
    {
        _3979 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _3979 = _3973;
    }
    highp vec3 _6086 = vec3(0.0);
    if (_3979)
    {
        vec3 mp_copy_6084 = vec3(0.0);
        highp vec3 _6084 = vec3(0.0);
        if (_4059)
        {
            _6084 = -view_info.camera_forward.xyz;
        }
        else
        {
            _6084 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_6085 = vec3(0.0);
        mp_copy_6084 = _6084;
        vec3 _3984 = _3802 * (-mp_copy_6084);
        vec3 _6085 = vec3(0.0);
        do
        {
            if (_4817)
            {
                vec2 _5397 = vec2(atan(_3984.z, _3984.x), asin(clamp(_3984.y, -1.0, 1.0)));
                highp vec2 hp_copy_5397 = _5397;
                _6085 = textureLod(prefiltered_radiance, (hp_copy_5397 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _5416 = vec2(atan(_3984.z, _3984.x), asin(clamp(_3984.y, -1.0, 1.0)));
            highp vec2 hp_copy_5416 = _5416;
            highp vec2 _5421 = (hp_copy_5416 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _5328 = clamp(_5421.y, 0.00390625, 0.99609375);
            float _5334 = floor(0.0);
            highp float _5353 = _5421.x;
            _6085 = mix(textureLod(prefiltered_radiance, vec2(_5353, (_5334 + _5328) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_5353, (min(_5334 + 1.0, 7.0) + _5328) * 0.125), 0.0).xyz, vec3(-_5334));
            break;
        } while(false);
        hp_copy_6085 = _6085;
        _6086 = hp_copy_6085 * hp_copy_3831;
    }
    else
    {
        _6086 = _FogInfo.color.xyz;
    }
    highp vec4 _3999 = vec4(min(((((((_3879 + ((_3571 * _3882) * ((vec3(1.0) - _3855) - _3879))) * (hp_copy_3816 * hp_copy_3831)) * vec3(_2783)) + (((_3855 * (_6046 * _3831)) * 1.0) * _6055)) * mix(1.0, _3609, frag_info.radiance_blend.y)) + (_6083 * mix(1.0, _6053, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _6010, vec3(65504.0)), 1.0) * _6186;
    highp vec4 _6101 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _6101 = _3999;
            break;
        }
        int _5465 = int(_FogInfo.params0.x + 0.5);
        if (_5465 == 0)
        {
            _6101 = _3999;
            break;
        }
        highp float _6088 = 0.0;
        if (_4059)
        {
            _6088 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _6088 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_6088 > _FogInfo.params1.w))
        {
            _6101 = _3999;
            break;
        }
        float _6092 = 0.0;
        if (_5465 == 1)
        {
            _6092 = clamp((_6088 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _6093 = 0.0;
            if (_5465 == 2)
            {
                highp float _6091 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _6089 = vec3(0.0);
                    if (_4059)
                    {
                        _6089 = v_position - (view_info.camera_forward.xyz * _6088);
                    }
                    else
                    {
                        _6089 = v_position + v_viewvector;
                    }
                    highp float _5556 = -_FogInfo.params2.y;
                    highp float _5563 = _FogInfo.params1.x * exp(_5556 * (_6089.y - _FogInfo.params2.x));
                    highp float _5580 = _FogInfo.params2.y * (v_position.y - _6089.y);
                    highp float _6090 = 0.0;
                    if (abs(_5580) > 0.00124999997206032276153564453125)
                    {
                        _6090 = (_5563 - (_FogInfo.params1.x * exp(_5556 * (v_position.y - _FogInfo.params2.x)))) / _5580;
                    }
                    else
                    {
                        _6090 = _5563;
                    }
                    _6091 = _6090 * max(_6088 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _6091 = _FogInfo.params1.x * max(_6088 - _FogInfo.params1.y, 0.0);
                }
                _6093 = 1.0 - exp(-_6091);
            }
            else
            {
                highp float _5518 = _FogInfo.params1.x * max(_6088 - _FogInfo.params1.y, 0.0);
                _6093 = 1.0 - exp((-_5518) * _5518);
            }
            _6092 = _6093;
        }
        highp float _5620 = min(_6092, _FogInfo.params0.z);
        if (_5620 <= 0.0)
        {
            _6101 = _3999;
            break;
        }
        highp vec3 _5633 = mix(_FogInfo.color.xyz, _6086, vec3(_FogInfo.params0.w));
        bool _5636 = _FogInfo.sun.w > 0.5;
        bool _5642 = false;
        if (_5636)
        {
            _5642 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _5642 = _5636;
        }
        vec3 _6097 = vec3(0.0);
        if (_5642)
        {
            vec3 mp_copy_6094 = vec3(0.0);
            highp vec3 _6094 = vec3(0.0);
            if (_4059)
            {
                _6094 = -view_info.camera_forward.xyz;
            }
            else
            {
                _6094 = normalize(v_viewvector);
            }
            mp_copy_6094 = _6094;
            highp float _5658 = pow(max(dot(-mp_copy_6094, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_5658 = _5658;
            _6097 = _5633 + ((_FogInfo.sun.xyz * mp_copy_5658) * _FogInfo.params2.z);
        }
        else
        {
            _6097 = _5633;
        }
        highp float _5671 = _3999.w;
        float mp_copy_5671 = _5671;
        _6101 = vec4(mix(_3999.xyz, _6097 * mp_copy_5671, vec3(_5620)), _5671);
        break;
    } while(false);
    vec4 _6103 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _6103 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _6103 = _6101;
        break;
    } while(false);
    frag_color = _6103;
    float _6104 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _6104 = 1.0;
    }
    else
    {
        _6104 = abs(frag_info.fade);
    }
    frag_color *= _6104;
}

