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
    highp float _2609 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_2609 = _2609;
    vec3 _2613 = normalize(v_normal) * mp_copy_2609;
    vec4 _2655 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _2658 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _5970 = vec2(0.0);
    if (_2658)
    {
        highp vec2 _5969 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _5969 = v_texture_coords_1;
        }
        else
        {
            _5969 = v_texture_coords;
        }
        highp vec2 _2861 = _5969 * texture_transforms.base_color_transform.zw;
        highp float _2867 = _2861.x;
        highp float _2872 = _2861.y;
        _5970 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _2867) + (texture_transforms.base_color_rotation.y * _2872), ((-texture_transforms.base_color_rotation.y) * _2867) + (texture_transforms.base_color_rotation.x * _2872));
    }
    else
    {
        _5970 = v_texture_coords;
    }
    vec4 _2672 = texture(base_color_texture, _5970);
    vec3 _2674 = _2672.xyz;
    float _6184 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_2672.w * _2655.w) * frag_info.color.w);
    vec3 _5985 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _5973 = vec2(0.0);
        if (_2658)
        {
            highp vec2 _5972 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _5972 = v_texture_coords_1;
            }
            else
            {
                _5972 = v_texture_coords;
            }
            highp vec2 _2956 = _5972 * texture_transforms.normal_transform.zw;
            highp float _2962 = _2956.x;
            highp float _2967 = _2956.y;
            _5973 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _2962) + (texture_transforms.normal_rotation.y * _2967), ((-texture_transforms.normal_rotation.y) * _2962) + (texture_transforms.normal_rotation.x * _2967));
        }
        else
        {
            _5973 = v_texture_coords;
        }
        vec3 _3012 = ((texture(normal_texture, _5973).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _3016 = _3012.xy * vec2(frag_info.normal_scale);
        vec3 _5849 = _3012;
        _5849.x = _3016.x;
        _5849.y = _3016.y;
        highp vec3 _3022 = -v_viewvector;
        highp vec3 _3112 = dFdx(_3022);
        highp vec3 _3114 = dFdy(_3022);
        highp vec2 _3116 = dFdx(_5973);
        highp vec2 _3118 = dFdy(_5973);
        bvec2 _6186 = bvec2(length(_3116) == 0.0);
        highp vec2 _6187 = vec2(_6186.x ? vec2(1.0, 0.0).x : _3116.x, _6186.y ? vec2(1.0, 0.0).y : _3116.y);
        bvec2 _6188 = bvec2(length(_3118) == 0.0);
        highp vec2 _6189 = vec2(_6188.x ? vec2(0.0, 1.0).x : _3118.x, _6188.y ? vec2(0.0, 1.0).y : _3118.y);
        highp vec3 _3131 = cross(_3114, _2613);
        highp vec3 _3134 = cross(_2613, _3112);
        highp float _3159 = (dot(cross(_3112, _3114), _2613) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _3162 = ((_3131 * _6187.x) + (_3134 * _6189.x)) * _3159;
        highp float _5980 = 0.0;
        if (gl_FrontFacing)
        {
            _5980 = -_3159;
        }
        else
        {
            _5980 = _3159;
        }
        highp vec3 _3172 = ((_3131 * _6187.y) + (_3134 * _6189.y)) * _5980;
        highp float _3181 = inversesqrt(max(max(dot(_3162, _3162), dot(_3172, _3172)), 9.9999996826552253889678874634872e-21));
        vec3 _3053 = v_tangent.xyz - (_2613 * dot(_2613, v_tangent.xyz));
        highp float _3056 = dot(_3053, _3053);
        bool _3058 = _3056 > 1.0000000133514319600180897396058e-10;
        bool _3065 = false;
        if (_3058)
        {
            _3065 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _3065 = _3058;
        }
        mat3 _5983 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_3065)
        {
            highp vec3 _3070 = _3053 * inversesqrt(_3056);
            _5983 = mat3(_3070, normalize(cross(_2613, _3070)) * sign(v_tangent.w), _2613);
        }
        else
        {
            _5983 = mat3(_3162 * _3181, _3172 * _3181, _2613);
        }
        _5985 = normalize(_5983 * _5849);
    }
    else
    {
        _5985 = _2613;
    }
    highp vec2 _5987 = vec2(0.0);
    if (_2658)
    {
        highp vec2 _5986 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _5986 = v_texture_coords_1;
        }
        else
        {
            _5986 = v_texture_coords;
        }
        highp vec2 _3249 = _5986 * texture_transforms.metallic_roughness_transform.zw;
        highp float _3255 = _3249.x;
        highp float _3260 = _3249.y;
        _5987 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _3255) + (texture_transforms.metallic_roughness_rotation.y * _3260), ((-texture_transforms.metallic_roughness_rotation.y) * _3255) + (texture_transforms.metallic_roughness_rotation.x * _3260));
    }
    else
    {
        _5987 = v_texture_coords;
    }
    vec4 _2741 = texture(metallic_roughness_texture, _5987);
    float _2747 = clamp(_2741.z * frag_info.metallic_factor, 0.0, 1.0);
    float _2754 = clamp(_2741.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _5989 = vec2(0.0);
    if (_2658)
    {
        highp vec2 _5988 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _5988 = v_texture_coords_1;
        }
        else
        {
            _5988 = v_texture_coords;
        }
        highp vec2 _3320 = _5988 * texture_transforms.occlusion_transform.zw;
        highp float _3326 = _3320.x;
        highp float _3331 = _3320.y;
        _5989 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _3326) + (texture_transforms.occlusion_rotation.y * _3331), ((-texture_transforms.occlusion_rotation.y) * _3326) + (texture_transforms.occlusion_rotation.x * _3331));
    }
    else
    {
        _5989 = v_texture_coords;
    }
    float _5990 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _5990 = texture(occlusion_texture, _5989).x;
    }
    else
    {
        _5990 = 1.0;
    }
    float _2781 = 1.0 - ((1.0 - _5990) * frag_info.occlusion_strength);
    highp vec2 _5992 = vec2(0.0);
    if (_2658)
    {
        highp vec2 _5991 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _5991 = v_texture_coords_1;
        }
        else
        {
            _5991 = v_texture_coords;
        }
        highp vec2 _3391 = _5991 * texture_transforms.emissive_transform.zw;
        highp float _3397 = _3391.x;
        highp float _3402 = _3391.y;
        _5992 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _3397) + (texture_transforms.emissive_rotation.y * _3402), ((-texture_transforms.emissive_rotation.y) * _3397) + (texture_transforms.emissive_rotation.x * _3402));
    }
    else
    {
        _5992 = v_texture_coords;
    }
    vec3 _2800 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _6008 = vec3(0.0);
    if (dot(abs(_2800), vec3(1.0)) > 0.0)
    {
        vec3 _2809 = texture(emissive_texture, _5992).xyz;
        _6008 = mix(_2809 * vec3(0.077399380505084991455078125), pow((_2809 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _2809)) * _2800;
    }
    else
    {
        _6008 = vec3(0.0);
    }
    highp float hp_copy_6033 = 0.0;
    vec3 _3569 = vec4((mix(_2674 * vec3(0.077399380505084991455078125), pow((_2674 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _2674)) * _2655.xyz) * frag_info.color.xyz, _6184).xyz;
    vec3 _4009 = dFdx(_5985);
    vec3 _4011 = dFdy(_5985);
    float _6033 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _6033 = sqrt(clamp((_2754 * _2754) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_4009, _4009), dot(_4011, _4011))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _6033 = _2754;
    }
    hp_copy_6033 = _6033;
    float _6051 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _6051 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _6051 = _2781;
    }
    bool _3594 = frag_info.has_directional_light > 0.5;
    float _6034 = 0.0;
    vec3 _6060 = vec3(0.0);
    if (_3594)
    {
        highp vec3 _3600 = -normalize(frag_info.directional_light_direction.xyz);
        _6060 = _3600;
        _6034 = dot(_2613, _3600);
    }
    else
    {
        _6060 = vec3(0.0);
        _6034 = 0.0;
    }
    vec3 mp_copy_6035 = vec3(0.0);
    float _3607 = clamp(_6034 * 6.666666507720947265625, 0.0, 1.0);
    bool _4057 = view_info.camera_forward.w > 0.5;
    highp vec3 _6035 = vec3(0.0);
    if (_4057)
    {
        _6035 = -view_info.camera_forward.xyz;
    }
    else
    {
        _6035 = normalize(v_viewvector);
    }
    highp float _4101 = 0.0;
    mp_copy_6035 = _6035;
    vec3 _3619 = mix(frag_info.dielectric_f0.xyz, _3569, vec3(_2747));
    float _3623 = max(dot(_5985, _6035), 0.0);
    float _3627 = max(dot(_2613, _6035), 0.0);
    highp vec2 _6036 = vec2(0.0);
    do
    {
        _4101 = frag_info.punctual_dims.x;
        if (_4101 < 0.5)
        {
            _6036 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _4113 = v_position - frag_info.camera_position.xyz;
            highp float _4128 = dot(_4113, frag_info.camera_forward.xyz);
            highp float _4134 = max(_4128, 9.9999997473787516355514526367188e-05);
            highp vec2 _4237 = (vec3(dot(_4113, frag_info.camera_right.xyz), dot(_4113, frag_info.camera_up.xyz), _4134).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_4134, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _4252 = float(int(((((clamp(floor((log2(max(_4128 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_4237.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_4237.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _6036 = vec2(textureLod(punctual_index, vec2((mod(_4252, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4252 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _6036 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _3636 = int(_6036.x + 0.5);
    mediump int _3640 = int(_6036.y + 0.5);
    highp vec3 _6071 = vec3(0.0);
    _6071 = vec3(0.0);
    highp vec3 _6144 = vec3(0.0);
    for (int _6037 = 0; _6037 < _3640; _6071 = _6144, _6037++)
    {
        highp float hp_copy_6109 = 0.0;
        highp float _4285 = float(_3636 + _6037);
        highp float _4316 = (float(int(textureLod(punctual_index, vec2((mod(_4285, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_4285 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _4101;
        highp vec4 _4320 = textureLod(punctual_lights, vec2(0.0625, _4316), 0.0);
        highp vec4 _4337 = textureLod(punctual_lights, vec2(0.1875, _4316), 0.0);
        highp float _3658 = _4320.w;
        highp vec3 _3660 = _4337.xyz;
        vec3 _6105 = vec3(0.0);
        highp vec3 _6107 = vec3(0.0);
        float _6109 = 0.0;
        if (_3658 < 0.5)
        {
            _6109 = _6033;
            _6107 = _3660;
            _6105 = -normalize(textureLod(punctual_lights, vec2(0.3125, _4316), 0.0).xyz);
        }
        else
        {
            highp vec3 _3668 = _4320.xyz - v_position;
            highp float _3671 = dot(_3668, _3668);
            highp float _3675 = inversesqrt(max(_3671, 9.9999999392252902907785028219223e-09));
            highp vec3 _3676 = _3668 * _3675;
            vec3 mp_copy_3676 = _3676;
            highp float _3678 = _4337.w;
            highp float _3683 = (_3671 * _3678) * _3678;
            highp float _3688 = clamp(1.0 - (_3683 * _3683), 0.0, 1.0);
            float mp_copy_3688 = _3688;
            if (_3688 <= 0.0)
            {
                _6144 = _6071;
                continue;
            }
            highp vec4 _4354 = textureLod(punctual_lights, vec2(0.4375, _4316), 0.0);
            highp float _3696 = _4354.w;
            float _6111 = 0.0;
            if (_3696 > 0.0)
            {
                highp float _3723 = (_6033 * _6033) + ((_3696 * 0.5) * _3675);
                float mp_copy_3723 = _3723;
                _6111 = sqrt(min(mp_copy_3723, 1.0));
            }
            else
            {
                _6111 = _6033;
            }
            highp vec3 _3730 = _3660 * ((mp_copy_3688 * mp_copy_3688) / max(pow(max(_3671, _3696 * _3696), _4354.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _6108 = vec3(0.0);
            if (_3658 > 1.5)
            {
                highp vec4 _4371 = textureLod(punctual_lights, vec2(0.3125, _4316), 0.0);
                highp float _3749 = clamp((dot(normalize(_4371.xyz), -mp_copy_3676) * _4371.w) + _4354.x, 0.0, 1.0);
                float mp_copy_3749 = _3749;
                if (_3749 <= 0.0)
                {
                    _6144 = _6071;
                    continue;
                }
                _6108 = _3730 * (mp_copy_3749 * mp_copy_3749);
            }
            else
            {
                _6108 = _3730;
            }
            _6109 = _6111;
            _6107 = _6108;
            _6105 = _3676;
        }
        hp_copy_6109 = _6109;
        highp vec3 _6115 = vec3(0.0);
        highp vec3 _6116 = vec3(0.0);
        do
        {
            float _4454 = max(dot(_5985, _6105), 0.0);
            highp float hp_copy_4454 = _4454;
            if (_4454 <= 0.0)
            {
                _6116 = vec3(0.0);
                _6115 = vec3(0.0);
                break;
            }
            float _4460 = max(_3623, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_4460 = _4460;
            vec3 _4463 = _6105 + mp_copy_6035;
            float _4466 = dot(_4463, _4463);
            vec3 _6113 = vec3(0.0);
            vec3 _6114 = vec3(0.0);
            if (_4466 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _4474 = _4463 * inversesqrt(_4466);
                float _6112 = 0.0;
                do
                {
                    float _4531 = dot(_5985, _4474);
                    if (_4531 <= 0.0)
                    {
                        _6112 = 0.0;
                        break;
                    }
                    float _4538 = _6109 * _6109;
                    vec3 _4541 = cross(_5985, _4474);
                    float _4544 = _4531 * _4538;
                    float _4553 = _4538 / (dot(_4541, _4541) + (_4544 * _4544));
                    _6112 = min((_4553 * _4553) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _4591 = _3619 + ((vec3(1.0) - _3619) * pow(clamp(1.0 - max(dot(_4474, _6035), 0.0), 0.0, 1.0), 5.0));
                _6114 = (_4591 * min(_6112 * (0.5 / max(mix((2.0 * hp_copy_4454) * _4460, hp_copy_4454 + hp_copy_4460, hp_copy_6109 * hp_copy_6109), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _6113 = _4591;
            }
            else
            {
                _6114 = vec3(0.0);
                _6113 = _3619;
            }
            _6116 = (_6114 * _6107) * _4454;
            _6115 = (((((vec3(1.0) - _6113) * (1.0 - _2747)) * _3569) * 0.3183098733425140380859375) * _6107) * _4454;
            break;
        } while(false);
        _6144 = _6071 + (_6115 + _6116);
    }
    bool _4815 = false;
    highp vec3 hp_copy_6038 = vec3(0.0);
    mat3 _3800 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _3808 = _3800 * vec3(_5985.x, _5985.y, _5985.z);
    vec3 _3811 = _3800 * reflect(-mp_copy_6035, _5985);
    float _4634 = _3808.y;
    float _4641 = _3808.z;
    float _4648 = _3808.x;
    float _4656 = 1.09254801273345947265625 * _4648;
    vec3 _3814 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _4634))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _4641))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _4648))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_4656 * _4634))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _4634) * _4641))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _4641) * _4641) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_4656 * _4641))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_4648 * _4648) - (_4634 * _4634)))), vec3(0.0));
    highp vec3 hp_copy_3814 = _3814;
    vec3 _6038 = vec3(0.0);
    do
    {
        _4815 = radiance_layout_info.mip_layout > 0.5;
        if (_4815)
        {
            vec2 _4894 = vec2(atan(_3811.z, _3811.x), asin(clamp(_3811.y, -1.0, 1.0)));
            highp vec2 hp_copy_4894 = _4894;
            _6038 = textureLod(prefiltered_radiance, (hp_copy_4894 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6033, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _4913 = vec2(atan(_3811.z, _3811.x), asin(clamp(_3811.y, -1.0, 1.0)));
        highp vec2 hp_copy_4913 = _4913;
        highp vec2 _4918 = (hp_copy_4913 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _4825 = clamp(_4918.y, 0.00390625, 0.99609375);
        float _4829 = clamp(_6033, 0.0, 1.0) * 7.0;
        float _4831 = floor(_4829);
        highp float _4850 = _4918.x;
        _6038 = mix(textureLod(prefiltered_radiance, vec2(_4850, (_4831 + _4825) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_4850, (min(_4831 + 1.0, 7.0) + _4825) * 0.125), 0.0).xyz, vec3(_4829 - _4831));
        break;
    } while(false);
    hp_copy_6038 = _6038;
    highp vec3 _6044 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_6039 = vec3(0.0);
        vec3 _6039 = vec3(0.0);
        do
        {
            if (_4815)
            {
                vec2 _5023 = vec2(atan(_3811.z, _3811.x), asin(clamp(_3811.y, -1.0, 1.0)));
                highp vec2 hp_copy_5023 = _5023;
                _6039 = textureLod(prefiltered_radiance_b, (hp_copy_5023 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_6033, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _5042 = vec2(atan(_3811.z, _3811.x), asin(clamp(_3811.y, -1.0, 1.0)));
            highp vec2 hp_copy_5042 = _5042;
            highp vec2 _5047 = (hp_copy_5042 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _4954 = clamp(_5047.y, 0.00390625, 0.99609375);
            float _4958 = clamp(_6033, 0.0, 1.0) * 7.0;
            float _4960 = floor(_4958);
            highp float _4979 = _5047.x;
            _6039 = mix(textureLod(prefiltered_radiance_b, vec2(_4979, (_4960 + _4954) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_4979, (min(_4960 + 1.0, 7.0) + _4954) * 0.125), 0.0).xyz, vec3(_4958 - _4960));
            break;
        } while(false);
        hp_copy_6039 = _6039;
        _6044 = hp_copy_6038 + hp_copy_6039;
    }
    else
    {
        _6044 = _6038;
    }
    float _3829 = frag_info.environment_intensity;
    highp float hp_copy_3829 = _3829;
    vec2 _3842 = clamp(vec2(_3627, _6033), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _3844 = texture(brdf_lut, vec2(_3842.x * 0.3333333432674407958984375, _3842.y));
    float _3848 = _3844.x;
    float _3851 = _3844.y;
    vec3 _3853 = ((_3619 + ((max(vec3(1.0 - _6033), _3619) - _3619) * pow(clamp(1.0 - _3627, 0.0, 1.0), 5.0))) * _3848) + vec3(_3851);
    float _3859 = 1.0 - (_3848 + _3851);
    vec3 _3863 = vec3(1.0) - _3619;
    vec3 _3866 = _3619 + (_3863 * vec3(0.0476190485060214996337890625));
    vec3 _3877 = ((_3853 * _3859) * _3866) / (vec3(1.0) - (_3866 * _3859));
    float _3880 = 1.0 - _2747;
    float _6053 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _6053 = clamp((pow(_3623 + _6051, exp2(((-16.0) * _6033) - 1.0)) - 1.0) + _6051, 0.0, 1.0);
    }
    else
    {
        _6053 = _6051;
    }
    highp vec3 _6081 = vec3(0.0);
    if (_3594)
    {
        highp vec3 _6065 = vec3(0.0);
        highp vec3 _6066 = vec3(0.0);
        do
        {
            float _5136 = max(dot(_5985, _6060), 0.0);
            highp float hp_copy_5136 = _5136;
            if (_5136 <= 0.0)
            {
                _6066 = vec3(0.0);
                _6065 = vec3(0.0);
                break;
            }
            float _5142 = max(_3623, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_5142 = _5142;
            vec3 _5145 = _6060 + mp_copy_6035;
            float _5148 = dot(_5145, _5145);
            vec3 _6063 = vec3(0.0);
            vec3 _6064 = vec3(0.0);
            if (_5148 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _5156 = _5145 * inversesqrt(_5148);
                float _6062 = 0.0;
                do
                {
                    float _5213 = dot(_5985, _5156);
                    if (_5213 <= 0.0)
                    {
                        _6062 = 0.0;
                        break;
                    }
                    float _5220 = _6033 * _6033;
                    vec3 _5223 = cross(_5985, _5156);
                    float _5226 = _5213 * _5220;
                    float _5235 = _5220 / (dot(_5223, _5223) + (_5226 * _5226));
                    _6062 = min((_5235 * _5235) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _5273 = _3619 + (_3863 * pow(clamp(1.0 - max(dot(_5156, _6035), 0.0), 0.0, 1.0), 5.0));
                _6064 = (_5273 * min(_6062 * (0.5 / max(mix((2.0 * hp_copy_5136) * _5142, hp_copy_5136 + hp_copy_5142, hp_copy_6033 * hp_copy_6033), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _6063 = _5273;
            }
            else
            {
                _6064 = vec3(0.0);
                _6063 = _3619;
            }
            _6066 = (_6064 * frag_info.directional_light_color.xyz) * _5136;
            _6065 = (((((vec3(1.0) - _6063) * _3880) * _3569) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _5136;
            break;
        } while(false);
        _6081 = _6071 + ((_6065 + _6066) * _3607);
    }
    else
    {
        _6081 = _6071;
    }
    bool _3971 = _FogInfo.params0.y > 0.5;
    bool _3977 = false;
    if (_3971)
    {
        _3977 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _3977 = _3971;
    }
    highp vec3 _6084 = vec3(0.0);
    if (_3977)
    {
        vec3 mp_copy_6082 = vec3(0.0);
        highp vec3 _6082 = vec3(0.0);
        if (_4057)
        {
            _6082 = -view_info.camera_forward.xyz;
        }
        else
        {
            _6082 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_6083 = vec3(0.0);
        mp_copy_6082 = _6082;
        vec3 _3982 = _3800 * (-mp_copy_6082);
        vec3 _6083 = vec3(0.0);
        do
        {
            if (_4815)
            {
                vec2 _5395 = vec2(atan(_3982.z, _3982.x), asin(clamp(_3982.y, -1.0, 1.0)));
                highp vec2 hp_copy_5395 = _5395;
                _6083 = textureLod(prefiltered_radiance, (hp_copy_5395 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _5414 = vec2(atan(_3982.z, _3982.x), asin(clamp(_3982.y, -1.0, 1.0)));
            highp vec2 hp_copy_5414 = _5414;
            highp vec2 _5419 = (hp_copy_5414 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _5326 = clamp(_5419.y, 0.00390625, 0.99609375);
            float _5332 = floor(0.0);
            highp float _5351 = _5419.x;
            _6083 = mix(textureLod(prefiltered_radiance, vec2(_5351, (_5332 + _5326) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_5351, (min(_5332 + 1.0, 7.0) + _5326) * 0.125), 0.0).xyz, vec3(-_5332));
            break;
        } while(false);
        hp_copy_6083 = _6083;
        _6084 = hp_copy_6083 * hp_copy_3829;
    }
    else
    {
        _6084 = _FogInfo.color.xyz;
    }
    highp vec4 _3997 = vec4(min(((((((_3877 + ((_3569 * _3880) * ((vec3(1.0) - _3853) - _3877))) * (hp_copy_3814 * hp_copy_3829)) * vec3(_2781)) + (((_3853 * (_6044 * _3829)) * 1.0) * _6053)) * mix(1.0, _3607, frag_info.radiance_blend.y)) + (_6081 * mix(1.0, _6051, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _6008, vec3(65504.0)), 1.0) * _6184;
    highp vec4 _6099 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _6099 = _3997;
            break;
        }
        int _5463 = int(_FogInfo.params0.x + 0.5);
        if (_5463 == 0)
        {
            _6099 = _3997;
            break;
        }
        highp float _6086 = 0.0;
        if (_4057)
        {
            _6086 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _6086 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_6086 > _FogInfo.params1.w))
        {
            _6099 = _3997;
            break;
        }
        float _6090 = 0.0;
        if (_5463 == 1)
        {
            _6090 = clamp((_6086 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _6091 = 0.0;
            if (_5463 == 2)
            {
                highp float _6089 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _6087 = vec3(0.0);
                    if (_4057)
                    {
                        _6087 = v_position - (view_info.camera_forward.xyz * _6086);
                    }
                    else
                    {
                        _6087 = v_position + v_viewvector;
                    }
                    highp float _5554 = -_FogInfo.params2.y;
                    highp float _5561 = _FogInfo.params1.x * exp(_5554 * (_6087.y - _FogInfo.params2.x));
                    highp float _5578 = _FogInfo.params2.y * (v_position.y - _6087.y);
                    highp float _6088 = 0.0;
                    if (abs(_5578) > 0.00124999997206032276153564453125)
                    {
                        _6088 = (_5561 - (_FogInfo.params1.x * exp(_5554 * (v_position.y - _FogInfo.params2.x)))) / _5578;
                    }
                    else
                    {
                        _6088 = _5561;
                    }
                    _6089 = _6088 * max(_6086 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _6089 = _FogInfo.params1.x * max(_6086 - _FogInfo.params1.y, 0.0);
                }
                _6091 = 1.0 - exp(-_6089);
            }
            else
            {
                highp float _5516 = _FogInfo.params1.x * max(_6086 - _FogInfo.params1.y, 0.0);
                _6091 = 1.0 - exp((-_5516) * _5516);
            }
            _6090 = _6091;
        }
        highp float _5618 = min(_6090, _FogInfo.params0.z);
        if (_5618 <= 0.0)
        {
            _6099 = _3997;
            break;
        }
        highp vec3 _5631 = mix(_FogInfo.color.xyz, _6084, vec3(_FogInfo.params0.w));
        bool _5634 = _FogInfo.sun.w > 0.5;
        bool _5640 = false;
        if (_5634)
        {
            _5640 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _5640 = _5634;
        }
        vec3 _6095 = vec3(0.0);
        if (_5640)
        {
            vec3 mp_copy_6092 = vec3(0.0);
            highp vec3 _6092 = vec3(0.0);
            if (_4057)
            {
                _6092 = -view_info.camera_forward.xyz;
            }
            else
            {
                _6092 = normalize(v_viewvector);
            }
            mp_copy_6092 = _6092;
            highp float _5656 = pow(max(dot(-mp_copy_6092, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_5656 = _5656;
            _6095 = _5631 + ((_FogInfo.sun.xyz * mp_copy_5656) * _FogInfo.params2.z);
        }
        else
        {
            _6095 = _5631;
        }
        highp float _5669 = _3997.w;
        float mp_copy_5669 = _5669;
        _6099 = vec4(mix(_3997.xyz, _6095 * mp_copy_5669, vec3(_5618)), _5669);
        break;
    } while(false);
    vec4 _6101 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _6101 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _6101 = _6099;
        break;
    } while(false);
    frag_color = _6101;
    float _6102 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _6102 = 1.0;
    }
    else
    {
        _6102 = abs(frag_info.fade);
    }
    frag_color *= _6102;
}

