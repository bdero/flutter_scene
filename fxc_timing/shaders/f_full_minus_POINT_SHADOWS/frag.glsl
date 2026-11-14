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
uniform mediump sampler2D brdf_lut;
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
    highp float _5654 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_5654 = _5654;
    vec3 _5658 = normalize(v_normal) * mp_copy_5654;
    vec4 _5700 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _5703 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _17301 = vec2(0.0);
    if (_5703)
    {
        highp vec2 _17300 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _17300 = v_texture_coords_1;
        }
        else
        {
            _17300 = v_texture_coords;
        }
        highp vec2 _5903 = _17300 * texture_transforms.base_color_transform.zw;
        highp float _5909 = _5903.x;
        highp float _5914 = _5903.y;
        _17301 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _5909) + (texture_transforms.base_color_rotation.y * _5914), ((-texture_transforms.base_color_rotation.y) * _5909) + (texture_transforms.base_color_rotation.x * _5914));
    }
    else
    {
        _17301 = v_texture_coords;
    }
    vec4 _5717 = texture(base_color_texture, _17301);
    vec3 _5719 = _5717.xyz;
    float _18804 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_5717.w * _5700.w) * frag_info.color.w);
    vec3 _17316 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _17304 = vec2(0.0);
        if (_5703)
        {
            highp vec2 _17303 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _17303 = v_texture_coords_1;
            }
            else
            {
                _17303 = v_texture_coords;
            }
            highp vec2 _5998 = _17303 * texture_transforms.normal_transform.zw;
            highp float _6004 = _5998.x;
            highp float _6009 = _5998.y;
            _17304 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6004) + (texture_transforms.normal_rotation.y * _6009), ((-texture_transforms.normal_rotation.y) * _6004) + (texture_transforms.normal_rotation.x * _6009));
        }
        else
        {
            _17304 = v_texture_coords;
        }
        vec3 _6057 = ((texture(normal_texture, _17304).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6061 = _6057.xy * vec2(frag_info.normal_scale);
        vec3 _16780 = _6057;
        _16780.x = _6061.x;
        _16780.y = _6061.y;
        highp vec3 _6067 = -v_viewvector;
        highp vec3 _6157 = dFdx(_6067);
        highp vec3 _6159 = dFdy(_6067);
        highp vec2 _6161 = dFdx(_17304);
        highp vec2 _6163 = dFdy(_17304);
        bvec2 _18806 = bvec2(length(_6161) == 0.0);
        highp vec2 _18807 = vec2(_18806.x ? vec2(1.0, 0.0).x : _6161.x, _18806.y ? vec2(1.0, 0.0).y : _6161.y);
        bvec2 _18808 = bvec2(length(_6163) == 0.0);
        highp vec2 _18809 = vec2(_18808.x ? vec2(0.0, 1.0).x : _6163.x, _18808.y ? vec2(0.0, 1.0).y : _6163.y);
        highp vec3 _6176 = cross(_6159, _5658);
        highp vec3 _6179 = cross(_5658, _6157);
        highp float _6204 = (dot(cross(_6157, _6159), _5658) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6207 = ((_6176 * _18807.x) + (_6179 * _18809.x)) * _6204;
        highp float _17311 = 0.0;
        if (gl_FrontFacing)
        {
            _17311 = -_6204;
        }
        else
        {
            _17311 = _6204;
        }
        highp vec3 _6217 = ((_6176 * _18807.y) + (_6179 * _18809.y)) * _17311;
        highp float _6226 = inversesqrt(max(max(dot(_6207, _6207), dot(_6217, _6217)), 9.9999996826552253889678874634872e-21));
        vec3 _6098 = v_tangent.xyz - (_5658 * dot(_5658, v_tangent.xyz));
        highp float _6101 = dot(_6098, _6098);
        bool _6103 = _6101 > 1.0000000133514319600180897396058e-10;
        bool _6110 = false;
        if (_6103)
        {
            _6110 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6110 = _6103;
        }
        mat3 _17314 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6110)
        {
            highp vec3 _6115 = _6098 * inversesqrt(_6101);
            _17314 = mat3(_6115, normalize(cross(_5658, _6115)) * sign(v_tangent.w), _5658);
        }
        else
        {
            _17314 = mat3(_6207 * _6226, _6217 * _6226, _5658);
        }
        _17316 = normalize(_17314 * _16780);
    }
    else
    {
        _17316 = _5658;
    }
    highp vec2 _17318 = vec2(0.0);
    if (_5703)
    {
        highp vec2 _17317 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _17317 = v_texture_coords_1;
        }
        else
        {
            _17317 = v_texture_coords;
        }
        highp vec2 _6291 = _17317 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6297 = _6291.x;
        highp float _6302 = _6291.y;
        _17318 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6297) + (texture_transforms.metallic_roughness_rotation.y * _6302), ((-texture_transforms.metallic_roughness_rotation.y) * _6297) + (texture_transforms.metallic_roughness_rotation.x * _6302));
    }
    else
    {
        _17318 = v_texture_coords;
    }
    vec4 _5786 = texture(metallic_roughness_texture, _17318);
    float _5792 = clamp(_5786.z * frag_info.metallic_factor, 0.0, 1.0);
    float _5799 = clamp(_5786.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _17320 = vec2(0.0);
    if (_5703)
    {
        highp vec2 _17319 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _17319 = v_texture_coords_1;
        }
        else
        {
            _17319 = v_texture_coords;
        }
        highp vec2 _6362 = _17319 * texture_transforms.occlusion_transform.zw;
        highp float _6368 = _6362.x;
        highp float _6373 = _6362.y;
        _17320 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6368) + (texture_transforms.occlusion_rotation.y * _6373), ((-texture_transforms.occlusion_rotation.y) * _6368) + (texture_transforms.occlusion_rotation.x * _6373));
    }
    else
    {
        _17320 = v_texture_coords;
    }
    float _17321 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _17321 = texture(occlusion_texture, _17320).x;
    }
    else
    {
        _17321 = 1.0;
    }
    float _5826 = 1.0 - ((1.0 - _17321) * frag_info.occlusion_strength);
    highp vec2 _17323 = vec2(0.0);
    if (_5703)
    {
        highp vec2 _17322 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _17322 = v_texture_coords_1;
        }
        else
        {
            _17322 = v_texture_coords;
        }
        highp vec2 _6433 = _17322 * texture_transforms.emissive_transform.zw;
        highp float _6439 = _6433.x;
        highp float _6444 = _6433.y;
        _17323 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6439) + (texture_transforms.emissive_rotation.y * _6444), ((-texture_transforms.emissive_rotation.y) * _6439) + (texture_transforms.emissive_rotation.x * _6444));
    }
    else
    {
        _17323 = v_texture_coords;
    }
    vec3 _5845 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _17339 = vec3(0.0);
    if (dot(abs(_5845), vec3(1.0)) > 0.0)
    {
        vec3 _5854 = texture(emissive_texture, _17323).xyz;
        _17339 = mix(_5854 * vec3(0.077399380505084991455078125), pow((_5854 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5854)) * _5845;
    }
    else
    {
        _17339 = vec3(0.0);
    }
    highp float hp_copy_17364 = 0.0;
    vec3 _6689 = vec4((mix(_5719 * vec3(0.077399380505084991455078125), pow((_5719 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5719)) * _5700.xyz) * frag_info.color.xyz, _18804).xyz;
    vec3 _7488 = dFdx(_17316);
    vec3 _7490 = dFdy(_17316);
    float _17364 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _17364 = sqrt(clamp((_5799 * _5799) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7488, _7488), dot(_7490, _7490))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _17364 = _5799;
    }
    hp_copy_17364 = _17364;
    vec4 _17389 = vec4(0.0);
    float _17407 = 0.0;
    vec3 _17422 = vec3(0.0);
    float _17705 = 0.0;
    vec3 _17844 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _6716 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _17365 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _17365 = _6716.w;
        }
        else
        {
            _17365 = _6716.x;
        }
        float _6729 = min(_5826, _17365);
        bool _6732 = frag_info.ssao_lighting.z > 0.5;
        bool _6738 = false;
        if (_6732)
        {
            _6738 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _6738 = _6732;
        }
        vec3 _17423 = vec3(0.0);
        if (_6738)
        {
            vec2 _7528 = (_6716.zw * 2.0) - vec2(1.0);
            float _7530 = _7528.x;
            float _7532 = _7528.y;
            float _7540 = (1.0 - abs(_7530)) - abs(_7532);
            vec3 _7541 = vec3(_7530, _7532, _7540);
            vec3 _17368 = vec3(0.0);
            if (_7540 < 0.0)
            {
                vec2 _7554 = (vec2(1.0) - abs(_7541.yx)) * vec2((_7530 >= 0.0) ? 1.0 : (-1.0), (_7532 >= 0.0) ? 1.0 : (-1.0));
                vec3 _16829 = _7541;
                _16829.x = _7554.x;
                _16829.y = _7554.y;
                _17368 = _16829;
            }
            else
            {
                _17368 = _7541;
            }
            vec3 _7562 = -normalize(_17368);
            _17423 = normalize(((frag_info.camera_right.xyz * _7562.x) + (frag_info.camera_up.xyz * _7562.y)) + (frag_info.camera_forward.xyz * _7562.z));
        }
        else
        {
            _17423 = vec3(0.0);
        }
        vec3 _6766 = vec3(_6729);
        _17844 = mix(_6766, max(_6766, ((((((_6689 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _6729) + ((_6689 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _6729) + ((_6689 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _6729), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _17705 = _6729;
        _17422 = _17423;
        _17407 = float(_6738);
        _17389 = _6716;
    }
    else
    {
        _17844 = vec3(_5826);
        _17705 = _5826;
        _17422 = vec3(0.0);
        _17407 = 0.0;
        _17389 = vec4(1.0);
    }
    bool _6778 = frag_info.has_directional_light > 0.5;
    float _17372 = 0.0;
    vec3 _17992 = vec3(0.0);
    if (_6778)
    {
        highp vec3 _6784 = -normalize(frag_info.directional_light_direction.xyz);
        _17992 = _6784;
        _17372 = dot(_5658, _6784);
    }
    else
    {
        _17992 = vec3(0.0);
        _17372 = 0.0;
    }
    float _6791 = clamp(_17372 * 6.666666507720947265625, 0.0, 1.0);
    bool _6800 = false;
    if (_6778)
    {
        _6800 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _6800 = _6778;
    }
    float _17381 = 0.0;
    if (_6800 && (_6791 > 0.0))
    {
        int _7653 = int(frag_info.shadow_cascade_count);
        float _7848 = max(dot(_5658, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _7851 = _7848 * _7848;
        highp vec3 _7871 = v_position + (_5658 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _7851, 0.0)) / _7851, 8.0))));
        highp float _7659 = frag_info.directional_light_color.w * 0.5;
        float _7661 = frag_info.dielectric_f0.w;
        highp float hp_copy_7661 = _7661;
        float _17373 = 0.0;
        if (_7661 > 0.0)
        {
            _17373 = smoothstep(_7661 - max(frag_info.shadow_fade, hp_copy_7661 * 0.100000001490116119384765625), _7661, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _17373 = 0.0;
        }
        float _17375 = 0.0;
        float _17377 = 0.0;
        if (_17373 < 1.0)
        {
            float _17376 = 0.0;
            float _17378 = 0.0;
            _17378 = 0.0;
            _17376 = 0.0;
            float _18399 = 0.0;
            float _18402 = 0.0;
            for (int _17374 = 0; _17374 < _7653; _17378 = _18402, _17376 = _18399, _17374++)
            {
                if (_17378 < 1.0)
                {
                    highp vec4 _7693 = vec4(_7871, 1.0);
                    highp vec4 _18271 = vec4(0.0);
                    highp float _18274 = 0.0;
                    if (_17374 == 0)
                    {
                        _18274 = frag_info.cascade_box_sizes.x;
                        _18271 = frag_info.light_space_matrix[0] * _7693;
                    }
                    else
                    {
                        highp vec4 _18272 = vec4(0.0);
                        highp float _18275 = 0.0;
                        if (_17374 == 1)
                        {
                            _18275 = frag_info.cascade_box_sizes.y;
                            _18272 = frag_info.light_space_matrix[1] * _7693;
                        }
                        else
                        {
                            highp vec4 _18273 = vec4(0.0);
                            highp float _18276 = 0.0;
                            if (_17374 == 2)
                            {
                                _18276 = frag_info.cascade_box_sizes.z;
                                _18273 = frag_info.light_space_matrix[2] * _7693;
                            }
                            else
                            {
                                _18276 = frag_info.cascade_box_sizes.w;
                                _18273 = frag_info.light_space_matrix[3] * _7693;
                            }
                            _18275 = _18276;
                            _18272 = _18273;
                        }
                        _18274 = _18275;
                        _18271 = _18272;
                    }
                    highp vec3 _7738 = _18271.xyz / vec3(_18271.w);
                    highp vec2 _7741 = _7738.xy * 0.5;
                    highp vec2 _7743 = _7741 + vec2(0.5);
                    highp float _7750 = max(frag_info.shadow_softness / _18274, frag_info.shadow_texel_size);
                    highp float _7752 = _7743.x;
                    bool _7754 = _7752 < _7750;
                    bool _7763 = false;
                    if (!_7754)
                    {
                        _7763 = _7752 > (1.0 - _7750);
                    }
                    else
                    {
                        _7763 = _7754;
                    }
                    bool _7771 = false;
                    if (!_7763)
                    {
                        _7771 = _7743.y < _7750;
                    }
                    else
                    {
                        _7771 = _7763;
                    }
                    bool _7780 = false;
                    if (!_7771)
                    {
                        _7780 = _7743.y > (1.0 - _7750);
                    }
                    else
                    {
                        _7780 = _7771;
                    }
                    bool _7787 = false;
                    if (!_7780)
                    {
                        _7787 = _7738.z < 0.0;
                    }
                    else
                    {
                        _7787 = _7780;
                    }
                    bool _7794 = false;
                    if (!_7787)
                    {
                        _7794 = _7738.z > 1.0;
                    }
                    else
                    {
                        _7794 = _7787;
                    }
                    float _18400 = 0.0;
                    float _18403 = 0.0;
                    if (!_7794)
                    {
                        highp vec2 _7887 = vec2(_7750);
                        highp vec2 _7892 = vec2(_7750 + max(_7659, 9.9999997473787516355514526367188e-05));
                        highp vec2 _7900 = vec2(0.5) - _7741;
                        highp vec2 _7902 = smoothstep(_7887, _7892, _7743) * smoothstep(_7887, _7892, _7900);
                        float _18277 = 0.0;
                        if (_7659 > 0.0)
                        {
                            _18277 = _7902.x * _7902.y;
                        }
                        else
                        {
                            _18277 = 1.0;
                        }
                        float _7803 = min(_18277, 1.0 - _17378);
                        float _18401 = 0.0;
                        float _18404 = 0.0;
                        if (_7803 > 0.0)
                        {
                            highp float _8041 = _7738.z - (frag_info.shadow_bias / (7.0 * _18274));
                            highp float _8047 = 1.0 / (float(_7653) + frag_info.spot_shadow_params.x);
                            highp float _8049 = frag_info.directional_light_direction.w;
                            float mp_copy_8049 = _8049;
                            float _8055 = step(0.5, mp_copy_8049) * (1.0 - step(1.5, mp_copy_8049));
                            float _18307 = 0.0;
                            float _18311 = 0.0;
                            if (_8055 < 0.5)
                            {
                                highp float _8066 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_8066 = _8066;
                                _18311 = sin(mp_copy_8066);
                                _18307 = cos(mp_copy_8066);
                            }
                            else
                            {
                                _18311 = 0.0;
                                _18307 = 1.0;
                            }
                            highp float _18314 = 0.0;
                            if ((_8049 > 1.5) && (_8049 < 2.5))
                            {
                                highp float _8090 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _8095 = max(_8090 * _8041, frag_info.shadow_texel_size);
                                float _18303 = 0.0;
                                highp float _18304 = 0.0;
                                _18304 = 0.0;
                                _18303 = 0.0;
                                highp float _8117 = 0.0;
                                float _8120 = 0.0;
                                for (int _18302 = 0; _18302 < 9; _18304 = _8117, _18303 = _8120, _18302++)
                                {
                                    vec2 _18393 = vec2(0.0);
                                    do
                                    {
                                        if (_18302 == 0)
                                        {
                                            _18393 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_18302 == 1)
                                        {
                                            _18393 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_18302 == 2)
                                        {
                                            _18393 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_18302 == 3)
                                        {
                                            _18393 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_18302 == 4)
                                        {
                                            _18393 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_18302 == 5)
                                        {
                                            _18393 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_18302 == 6)
                                        {
                                            _18393 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_18302 == 7)
                                        {
                                            _18393 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_18302 == 8)
                                        {
                                            _18393 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_18302 == 9)
                                        {
                                            _18393 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_18302 == 10)
                                        {
                                            _18393 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_18302 == 11)
                                        {
                                            _18393 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_18302 == 12)
                                        {
                                            _18393 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_18302 == 13)
                                        {
                                            _18393 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_18302 == 14)
                                        {
                                            _18393 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_18302 == 15)
                                        {
                                            _18393 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _18393 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8424 = clamp(_7743 + (vec2((_18393.x * _18307) - (_18393.y * _18311), (_18393.x * _18311) + (_18393.y * _18307)) * _8095), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8433 = _8424.y;
                                    highp vec2 _8434 = vec2((float(_17374) + _8424.x) * _8047, _8433);
                                    _8434.y = 1.0 - _8433;
                                    highp vec4 _8441 = textureLod(shadow_map, _8434, 0.0);
                                    highp float _8442 = _8441.x;
                                    highp float _8112 = step(_8442, _8041);
                                    float mp_copy_8112 = _8112;
                                    _8117 = _18304 + (_8442 * _8112);
                                    _8120 = _18303 + mp_copy_8112;
                                }
                                highp float _18305 = 0.0;
                                if (_18303 > 0.0)
                                {
                                    _18305 = _18304 / _18303;
                                }
                                else
                                {
                                    _18305 = _8041;
                                }
                                _18314 = clamp(_8090 * max(_8041 - _18305, 0.0), frag_info.shadow_texel_size, _7750);
                            }
                            else
                            {
                                _18314 = _7750;
                            }
                            bool _8151 = _8049 > 2.5;
                            bool _18315 = false;
                            float _18339 = 0.0;
                            if ((_8049 < 1.5) || _8151)
                            {
                                highp vec2 _8475 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8479 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8480 = clamp(_7743, _8475, _8479);
                                highp float _8482 = float(_17374);
                                highp float _8489 = _8480.y;
                                highp vec2 _8490 = vec2((_8482 + _8480.x) * _8047, _8489);
                                _8490.y = 1.0 - _8489;
                                highp float _8502 = float(_8041 <= textureLod(shadow_map, _8490, 0.0).x);
                                float mp_copy_8502 = _8502;
                                float _8512 = (-1.0) * _18307;
                                float _8516 = (-1.0) * _18311;
                                highp vec2 _8540 = clamp(_7743 + (vec2(_8512 - _8516, _8516 + _8512) * _18314), _8475, _8479);
                                highp float _8549 = _8540.y;
                                highp vec2 _8550 = vec2((_8482 + _8540.x) * _8047, _8549);
                                _8550.y = 1.0 - _8549;
                                highp float _8562 = float(_8041 <= textureLod(shadow_map, _8550, 0.0).x);
                                float mp_copy_8562 = _8562;
                                highp vec2 _8600 = clamp(_7743 + (vec2(_18307 - _8516, _18311 + _8512) * _18314), _8475, _8479);
                                highp float _8609 = _8600.y;
                                highp vec2 _8610 = vec2((_8482 + _8600.x) * _8047, _8609);
                                _8610.y = 1.0 - _8609;
                                highp float _8622 = float(_8041 <= textureLod(shadow_map, _8610, 0.0).x);
                                float mp_copy_8622 = _8622;
                                highp vec2 _8660 = clamp(_7743 + (vec2(_8512 - _18311, _8516 + _18307) * _18314), _8475, _8479);
                                highp float _8669 = _8660.y;
                                highp vec2 _8670 = vec2((_8482 + _8660.x) * _8047, _8669);
                                _8670.y = 1.0 - _8669;
                                highp float _8682 = float(_8041 <= textureLod(shadow_map, _8670, 0.0).x);
                                float mp_copy_8682 = _8682;
                                highp vec2 _8720 = clamp(_7743 + (vec2(_18307 - _18311, _18311 + _18307) * _18314), _8475, _8479);
                                highp float _8729 = _8720.y;
                                highp vec2 _8730 = vec2((_8482 + _8720.x) * _8047, _8729);
                                _8730.y = 1.0 - _8729;
                                highp float _8742 = float(_8041 <= textureLod(shadow_map, _8730, 0.0).x);
                                float mp_copy_8742 = _8742;
                                float _8197 = (((mp_copy_8502 + mp_copy_8562) + mp_copy_8622) + mp_copy_8682) + mp_copy_8742;
                                _18339 = _8197 * 0.20000000298023223876953125;
                                _18315 = (_8197 < 0.5) || (_8197 > 4.5);
                            }
                            else
                            {
                                _18339 = 0.0;
                                _18315 = false;
                            }
                            float _18338 = 0.0;
                            if (_18315)
                            {
                                _18338 = _18339;
                            }
                            else
                            {
                                float _18340 = 0.0;
                                if (_8151)
                                {
                                    highp vec2 _8770 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _8774 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _8775 = clamp(_7743 + (vec2(-0.707099974155426025390625) * _18314), _8770, _8774);
                                    highp vec2 _8786 = (vec2(_8775.x, 1.0 - _8775.y) / _8770) - vec2(0.5);
                                    highp vec2 _8788 = floor(_8786);
                                    highp vec2 _8791 = _8786 - _8788;
                                    highp vec2 _8796 = (_8788 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _8798 = float(_17374);
                                    highp vec2 _8806 = vec2((_8798 + _8796.x) * _8047, _8796.y);
                                    highp float _8810 = frag_info.shadow_texel_size * _8047;
                                    highp vec2 _8813 = vec2(_8810, frag_info.shadow_texel_size);
                                    highp vec2 _8822 = vec2(_8810, 0.0);
                                    highp vec2 _8830 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _8859 = _8791.x;
                                    highp float _8868 = mix(mix(float(_8041 <= textureLod(shadow_map, _8806, 0.0).x), float(_8041 <= textureLod(shadow_map, _8806 + _8822, 0.0).x), _8859), mix(float(_8041 <= textureLod(shadow_map, _8806 + _8830, 0.0).x), float(_8041 <= textureLod(shadow_map, _8806 + _8813, 0.0).x), _8859), _8791.y);
                                    float mp_copy_8868 = _8868;
                                    highp vec2 _8902 = clamp(_7743 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _18314), _8770, _8774);
                                    highp vec2 _8913 = (vec2(_8902.x, 1.0 - _8902.y) / _8770) - vec2(0.5);
                                    highp vec2 _8915 = floor(_8913);
                                    highp vec2 _8918 = _8913 - _8915;
                                    highp vec2 _8923 = (_8915 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8933 = vec2((_8798 + _8923.x) * _8047, _8923.y);
                                    highp float _8986 = _8918.x;
                                    highp float _8995 = mix(mix(float(_8041 <= textureLod(shadow_map, _8933, 0.0).x), float(_8041 <= textureLod(shadow_map, _8933 + _8822, 0.0).x), _8986), mix(float(_8041 <= textureLod(shadow_map, _8933 + _8830, 0.0).x), float(_8041 <= textureLod(shadow_map, _8933 + _8813, 0.0).x), _8986), _8918.y);
                                    float mp_copy_8995 = _8995;
                                    highp vec2 _9029 = clamp(_7743 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _18314), _8770, _8774);
                                    highp vec2 _9040 = (vec2(_9029.x, 1.0 - _9029.y) / _8770) - vec2(0.5);
                                    highp vec2 _9042 = floor(_9040);
                                    highp vec2 _9045 = _9040 - _9042;
                                    highp vec2 _9050 = (_9042 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9060 = vec2((_8798 + _9050.x) * _8047, _9050.y);
                                    highp float _9113 = _9045.x;
                                    highp float _9122 = mix(mix(float(_8041 <= textureLod(shadow_map, _9060, 0.0).x), float(_8041 <= textureLod(shadow_map, _9060 + _8822, 0.0).x), _9113), mix(float(_8041 <= textureLod(shadow_map, _9060 + _8830, 0.0).x), float(_8041 <= textureLod(shadow_map, _9060 + _8813, 0.0).x), _9113), _9045.y);
                                    float mp_copy_9122 = _9122;
                                    highp vec2 _9156 = clamp(_7743 + (vec2(0.707099974155426025390625) * _18314), _8770, _8774);
                                    highp vec2 _9167 = (vec2(_9156.x, 1.0 - _9156.y) / _8770) - vec2(0.5);
                                    highp vec2 _9169 = floor(_9167);
                                    highp vec2 _9172 = _9167 - _9169;
                                    highp vec2 _9177 = (_9169 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9187 = vec2((_8798 + _9177.x) * _8047, _9177.y);
                                    highp float _9240 = _9172.x;
                                    highp float _9249 = mix(mix(float(_8041 <= textureLod(shadow_map, _9187, 0.0).x), float(_8041 <= textureLod(shadow_map, _9187 + _8822, 0.0).x), _9240), mix(float(_8041 <= textureLod(shadow_map, _9187 + _8830, 0.0).x), float(_8041 <= textureLod(shadow_map, _9187 + _8813, 0.0).x), _9240), _9172.y);
                                    float mp_copy_9249 = _9249;
                                    _18340 = (((mp_copy_8868 + mp_copy_8995) + mp_copy_9122) + mp_copy_9249) * 0.25;
                                }
                                else
                                {
                                    int _8244 = (_8055 > 0.5) ? 17 : 16;
                                    float _18334 = 0.0;
                                    _18334 = 0.0;
                                    float _8272 = 0.0;
                                    for (int _18316 = 0; _18316 < 17; _18334 = _8272, _18316++)
                                    {
                                        if (_18316 >= _8244)
                                        {
                                            break;
                                        }
                                        vec2 _18317 = vec2(0.0);
                                        do
                                        {
                                            if (_18316 == 0)
                                            {
                                                _18317 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_18316 == 1)
                                            {
                                                _18317 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_18316 == 2)
                                            {
                                                _18317 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_18316 == 3)
                                            {
                                                _18317 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_18316 == 4)
                                            {
                                                _18317 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_18316 == 5)
                                            {
                                                _18317 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_18316 == 6)
                                            {
                                                _18317 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_18316 == 7)
                                            {
                                                _18317 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_18316 == 8)
                                            {
                                                _18317 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_18316 == 9)
                                            {
                                                _18317 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_18316 == 10)
                                            {
                                                _18317 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_18316 == 11)
                                            {
                                                _18317 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_18316 == 12)
                                            {
                                                _18317 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_18316 == 13)
                                            {
                                                _18317 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_18316 == 14)
                                            {
                                                _18317 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_18316 == 15)
                                            {
                                                _18317 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _18317 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _18319 = vec2(0.0);
                                        do
                                        {
                                            if (_18316 < 3)
                                            {
                                                _18319 = vec2(float(_18316) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_18316 < 6)
                                            {
                                                _18319 = vec2((float(_18316 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_18316 < 11)
                                            {
                                                _18319 = vec2((float(_18316 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_18316 < 14)
                                            {
                                                _18319 = vec2((float(_18316 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _18319 = vec2(float(_18316 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8261 = mix(_18317, _18319, vec2(_8055));
                                        float _9389 = _8261.x;
                                        float _9393 = _8261.y;
                                        highp vec2 _9419 = clamp(_7743 + (vec2((_9389 * _18307) - (_9393 * _18311), (_9389 * _18311) + (_9393 * _18307)) * _18314), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9428 = _9419.y;
                                        highp vec2 _9429 = vec2((float(_17374) + _9419.x) * _8047, _9428);
                                        _9429.y = 1.0 - _9428;
                                        highp float _9441 = float(_8041 <= textureLod(shadow_map, _9429, 0.0).x);
                                        float mp_copy_9441 = _9441;
                                        _8272 = _18334 + mp_copy_9441;
                                    }
                                    _18340 = _18334 / float(_8244);
                                }
                                _18338 = _18340;
                            }
                            bool _8286 = _17374 == (_7653 - 1);
                            bool _8292 = false;
                            if (_8286)
                            {
                                _8292 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8292 = _8286;
                            }
                            float _18341 = 0.0;
                            if (_8292)
                            {
                                highp vec2 _8299 = vec2(frag_info.shadow_fade / _18274);
                                highp vec2 _8307 = smoothstep(vec2(0.0), _8299, _7743) * smoothstep(vec2(0.0), _8299, _7900);
                                _18341 = mix(1.0, _18338, _8307.x * _8307.y);
                            }
                            else
                            {
                                _18341 = _18338;
                            }
                            _18404 = _17378 + _7803;
                            _18401 = _17376 + (_7803 * _18341);
                        }
                        else
                        {
                            _18404 = _17378;
                            _18401 = _17376;
                        }
                        _18403 = _18404;
                        _18400 = _18401;
                    }
                    else
                    {
                        _18403 = _17378;
                        _18400 = _17376;
                    }
                    _18402 = _18403;
                    _18399 = _18400;
                }
                else
                {
                    _18402 = _17378;
                    _18399 = _17376;
                }
            }
            _17377 = _17378;
            _17375 = _17376;
        }
        else
        {
            _17377 = 0.0;
            _17375 = 0.0;
        }
        _17381 = mix(_17375 + (1.0 - _17377), 1.0, _17373);
    }
    else
    {
        _17381 = 1.0;
    }
    bool _6813 = frag_info.ssao_lighting.w > 0.5;
    bool _6819 = false;
    if (_6813)
    {
        _6819 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _6819 = _6813;
    }
    float _17393 = 0.0;
    if (_6819)
    {
        _17393 = min(_17381, _17389.y);
    }
    else
    {
        _17393 = _17381;
    }
    vec3 mp_copy_17394 = vec3(0.0);
    float _6828 = _6791 * _17393;
    bool _9448 = view_info.camera_forward.w > 0.5;
    highp vec3 _17394 = vec3(0.0);
    if (_9448)
    {
        _17394 = -view_info.camera_forward.xyz;
    }
    else
    {
        _17394 = normalize(v_viewvector);
    }
    highp float _9492 = 0.0;
    mp_copy_17394 = _17394;
    vec3 _6837 = mix(frag_info.dielectric_f0.xyz, _6689, vec3(_5792));
    float _6840 = dot(_17316, _17394);
    float _6841 = max(_6840, 0.0);
    float _6845 = max(dot(_5658, _17394), 0.0);
    vec3 _6849 = reflect(-mp_copy_17394, _17316);
    highp vec2 _17395 = vec2(0.0);
    do
    {
        _9492 = frag_info.punctual_dims.x;
        if (_9492 < 0.5)
        {
            _17395 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9504 = v_position - frag_info.camera_position.xyz;
            highp float _9519 = dot(_9504, frag_info.camera_forward.xyz);
            highp float _9525 = max(_9519, 9.9999997473787516355514526367188e-05);
            highp vec2 _9628 = (vec3(dot(_9504, frag_info.camera_right.xyz), dot(_9504, frag_info.camera_up.xyz), _9525).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9525, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _9643 = float(int(((((clamp(floor((log2(max(_9519 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9628.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9628.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _17395 = vec2(textureLod(punctual_index, vec2((mod(_9643, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9643 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _17395 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _6854 = int(_17395.x + 0.5);
    mediump int _6858 = int(_17395.y + 0.5);
    highp vec3 _18066 = vec3(0.0);
    _18066 = vec3(0.0);
    highp vec3 _18737 = vec3(0.0);
    for (int _17396 = 0; _17396 < _6858; _18066 = _18737, _17396++)
    {
        highp float _9676 = float(_6854 + _17396);
        highp float _9707 = (float(int(textureLod(punctual_index, vec2((mod(_9676, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9676 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9492;
        highp vec4 _9711 = textureLod(punctual_lights, vec2(0.0625, _9707), 0.0);
        highp vec4 _9728 = textureLod(punctual_lights, vec2(0.1875, _9707), 0.0);
        highp float _6876 = _9711.w;
        highp vec3 _6878 = _9728.xyz;
        highp vec3 _18738 = vec3(0.0);
        if (_6876 > 2.5)
        {
            highp vec4 _9745 = textureLod(punctual_lights, vec2(0.3125, _9707), 0.0);
            highp vec4 _9762 = textureLod(punctual_lights, vec2(0.4375, _9707), 0.0);
            highp vec3 _6892 = _9745.xyz * (_9745.w * 0.5);
            highp vec3 _6898 = _9762.xyz * (_9762.w * 0.5);
            highp vec3 _6900 = _9711.xyz;
            highp vec3 _6902 = _6900 - _6892;
            highp vec3 _6904 = _6902 - _6898;
            highp vec3 _6908 = _6900 + _6892;
            highp vec3 _6910 = _6908 - _6898;
            highp vec3 _6922 = _6902 + _6898;
            highp vec3 _6926 = _6900 - v_position;
            highp float _6932 = _9728.w;
            highp float _6936 = (dot(_6926, _6926) * _6932) * _6932;
            highp float _6941 = clamp(1.0 - (_6936 * _6936), 0.0, 1.0);
            float mp_copy_6941 = _6941;
            vec2 _9769 = (clamp(vec2(_17364, sqrt(1.0 - _6841)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _9771 = _9769.x;
            float _9776 = _9769.y;
            vec4 _6965 = textureLod(brdf_lut, vec2((_9771 + 1.0) * 0.3333333432674407958984375, _9776), 0.0);
            vec4 _6969 = textureLod(brdf_lut, vec2((_9771 + 2.0) * 0.3333333432674407958984375, _9776), 0.0);
            vec3 _9819 = normalize(mp_copy_17394 - (_17316 * _6840));
            mat3 _9841 = transpose(mat3(_9819, -cross(_17316, _9819), _17316));
            mat3 _9842 = mat3(vec3(_6965.x, 0.0, _6965.y), vec3(0.0, 1.0, 0.0), vec3(_6965.z, 0.0, _6965.w)) * _9841;
            highp vec3 _9846 = _6904 - v_position;
            highp vec3 _9848 = normalize(_9842 * _9846);
            vec3 mp_copy_9848 = _9848;
            highp vec3 _9852 = _6910 - v_position;
            highp vec3 _9854 = normalize(_9842 * _9852);
            vec3 mp_copy_9854 = _9854;
            highp vec3 _9858 = (_6908 + _6898) - v_position;
            highp vec3 _9860 = normalize(_9842 * _9858);
            vec3 mp_copy_9860 = _9860;
            highp vec3 _9864 = _6922 - v_position;
            highp vec3 _9866 = normalize(_9842 * _9864);
            vec3 mp_copy_9866 = _9866;
            float _9895 = dot(_9848, _9854);
            float _9897 = abs(_9895);
            float _9911 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9897)) * _9897)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9897) * _9897));
            float _18222 = 0.0;
            if (_9895 > 0.0)
            {
                _18222 = _9911;
            }
            else
            {
                _18222 = (0.5 * inversesqrt(max(1.0 - (_9895 * _9895), 1.0000000116860974230803549289703e-07))) - _9911;
            }
            float _9944 = dot(_9854, _9860);
            float _9946 = abs(_9944);
            float _9960 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9946)) * _9946)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9946) * _9946));
            float _18223 = 0.0;
            if (_9944 > 0.0)
            {
                _18223 = _9960;
            }
            else
            {
                _18223 = (0.5 * inversesqrt(max(1.0 - (_9944 * _9944), 1.0000000116860974230803549289703e-07))) - _9960;
            }
            float _9993 = dot(_9860, _9866);
            float _9995 = abs(_9993);
            float _10009 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9995)) * _9995)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9995) * _9995));
            float _18224 = 0.0;
            if (_9993 > 0.0)
            {
                _18224 = _10009;
            }
            else
            {
                _18224 = (0.5 * inversesqrt(max(1.0 - (_9993 * _9993), 1.0000000116860974230803549289703e-07))) - _10009;
            }
            float _10042 = dot(_9866, _9848);
            float _10044 = abs(_10042);
            float _10058 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10044)) * _10044)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10044) * _10044));
            float _18225 = 0.0;
            if (_10042 > 0.0)
            {
                _18225 = _10058;
            }
            else
            {
                _18225 = (0.5 * inversesqrt(max(1.0 - (_10042 * _10042), 1.0000000116860974230803549289703e-07))) - _10058;
            }
            vec3 _9881 = (((cross(mp_copy_9848, mp_copy_9854) * _18222) + (cross(mp_copy_9854, mp_copy_9860) * _18223)) + (cross(mp_copy_9860, mp_copy_9866) * _18224)) + (cross(mp_copy_9866, mp_copy_9848) * _18225);
            float _10084 = length(_9881);
            mat3 _10144 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _9841;
            highp vec3 _10150 = normalize(_10144 * _9846);
            vec3 mp_copy_10150 = _10150;
            highp vec3 _10156 = normalize(_10144 * _9852);
            vec3 mp_copy_10156 = _10156;
            highp vec3 _10162 = normalize(_10144 * _9858);
            vec3 mp_copy_10162 = _10162;
            highp vec3 _10168 = normalize(_10144 * _9864);
            vec3 mp_copy_10168 = _10168;
            float _10197 = dot(_10150, _10156);
            float _10199 = abs(_10197);
            float _10213 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10199)) * _10199)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10199) * _10199));
            float _18226 = 0.0;
            if (_10197 > 0.0)
            {
                _18226 = _10213;
            }
            else
            {
                _18226 = (0.5 * inversesqrt(max(1.0 - (_10197 * _10197), 1.0000000116860974230803549289703e-07))) - _10213;
            }
            float _10246 = dot(_10156, _10162);
            float _10248 = abs(_10246);
            float _10262 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10248)) * _10248)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10248) * _10248));
            float _18227 = 0.0;
            if (_10246 > 0.0)
            {
                _18227 = _10262;
            }
            else
            {
                _18227 = (0.5 * inversesqrt(max(1.0 - (_10246 * _10246), 1.0000000116860974230803549289703e-07))) - _10262;
            }
            float _10295 = dot(_10162, _10168);
            float _10297 = abs(_10295);
            float _10311 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10297)) * _10297)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10297) * _10297));
            float _18228 = 0.0;
            if (_10295 > 0.0)
            {
                _18228 = _10311;
            }
            else
            {
                _18228 = (0.5 * inversesqrt(max(1.0 - (_10295 * _10295), 1.0000000116860974230803549289703e-07))) - _10311;
            }
            float _10344 = dot(_10168, _10150);
            float _10346 = abs(_10344);
            float _10360 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10346)) * _10346)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10346) * _10346));
            float _18229 = 0.0;
            if (_10344 > 0.0)
            {
                _18229 = _10360;
            }
            else
            {
                _18229 = (0.5 * inversesqrt(max(1.0 - (_10344 * _10344), 1.0000000116860974230803549289703e-07))) - _10360;
            }
            vec3 _10183 = (((cross(mp_copy_10150, mp_copy_10156) * _18226) + (cross(mp_copy_10156, mp_copy_10162) * _18227)) + (cross(mp_copy_10162, mp_copy_10168) * _18228)) + (cross(mp_copy_10168, mp_copy_10150) * _18229);
            float _10386 = length(_10183);
            _18738 = _18066 + (((_6878 * (mp_copy_6941 * mp_copy_6941)) * step(0.0, dot(cross(_6910 - _6904, _6922 - _6904), v_position - _6904))) * (((((_6837 * _6969.x) + ((vec3(1.0) - _6837) * _6969.y)) * max(((_10084 * _10084) + _9881.z) / (_10084 + 1.0), 0.0)) * 1.0) + ((_6689 * (1.0 - _5792)) * max(((_10386 * _10386) + _10183.z) / (_10386 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_18190 = 0.0;
            vec3 _18176 = vec3(0.0);
            highp vec3 _18187 = vec3(0.0);
            float _18190 = 0.0;
            if (_6876 < 0.5)
            {
                _18190 = _17364;
                _18187 = _6878;
                _18176 = -normalize(textureLod(punctual_lights, vec2(0.3125, _9707), 0.0).xyz);
            }
            else
            {
                highp vec3 _7056 = _9711.xyz - v_position;
                highp float _7059 = dot(_7056, _7056);
                highp float _7063 = inversesqrt(max(_7059, 9.9999999392252902907785028219223e-09));
                highp vec3 _7064 = _7056 * _7063;
                vec3 mp_copy_7064 = _7064;
                highp float _7066 = _9728.w;
                highp float _7071 = (_7059 * _7066) * _7066;
                highp float _7076 = clamp(1.0 - (_7071 * _7071), 0.0, 1.0);
                float mp_copy_7076 = _7076;
                if (_7076 <= 0.0)
                {
                    _18737 = _18066;
                    continue;
                }
                highp vec4 _10430 = textureLod(punctual_lights, vec2(0.4375, _9707), 0.0);
                highp float _7084 = _10430.w;
                float _18192 = 0.0;
                if (_7084 > 0.0)
                {
                    highp float _7111 = (_17364 * _17364) + ((_7084 * 0.5) * _7063);
                    float mp_copy_7111 = _7111;
                    _18192 = sqrt(min(mp_copy_7111, 1.0));
                }
                else
                {
                    _18192 = _17364;
                }
                highp vec3 _7118 = _6878 * ((mp_copy_7076 * mp_copy_7076) / max(pow(max(_7059, _7084 * _7084), _10430.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _18188 = vec3(0.0);
                if (_6876 > 1.5)
                {
                    highp vec4 _10447 = textureLod(punctual_lights, vec2(0.3125, _9707), 0.0);
                    highp float _7137 = clamp((dot(normalize(_10447.xyz), -mp_copy_7064) * _10447.w) + _10430.x, 0.0, 1.0);
                    float mp_copy_7137 = _7137;
                    highp vec3 _7142 = _7118 * (mp_copy_7137 * mp_copy_7137);
                    if (_7137 <= 0.0)
                    {
                        _18737 = _18066;
                        continue;
                    }
                    bool _7148 = _7137 > 0.0;
                    bool _7154 = false;
                    if (_7148)
                    {
                        _7154 = _10430.y > (-0.5);
                    }
                    else
                    {
                        _7154 = _7148;
                    }
                    bool _7160 = false;
                    if (_7154)
                    {
                        _7160 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7160 = _7154;
                    }
                    highp vec3 _18189 = vec3(0.0);
                    if (_7160)
                    {
                        float _18167 = 0.0;
                        do
                        {
                            highp vec4 _10559 = mat4(textureLod(punctual_lights, vec2(0.5625, _9707), 0.0), textureLod(punctual_lights, vec2(0.6875, _9707), 0.0), textureLod(punctual_lights, vec2(0.8125, _9707), 0.0), textureLod(punctual_lights, vec2(0.9375, _9707), 0.0)) * vec4(v_position + (_5658 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10561 = _10559.w;
                            if (_10561 <= 0.0)
                            {
                                _18167 = 1.0;
                                break;
                            }
                            highp vec3 _10570 = _10559.xyz / vec3(_10561);
                            highp vec2 _10575 = (_10570.xy * 0.5) + vec2(0.5);
                            highp float _10577 = _10575.x;
                            bool _10578 = _10577 < 0.0;
                            bool _10585 = false;
                            if (!_10578)
                            {
                                _10585 = _10577 > 1.0;
                            }
                            else
                            {
                                _10585 = _10578;
                            }
                            bool _10592 = false;
                            if (!_10585)
                            {
                                _10592 = _10575.y < 0.0;
                            }
                            else
                            {
                                _10592 = _10585;
                            }
                            bool _10599 = false;
                            if (!_10592)
                            {
                                _10599 = _10575.y > 1.0;
                            }
                            else
                            {
                                _10599 = _10592;
                            }
                            bool _10606 = false;
                            if (!_10599)
                            {
                                _10606 = _10570.z < 0.0;
                            }
                            else
                            {
                                _10606 = _10599;
                            }
                            bool _10613 = false;
                            if (!_10606)
                            {
                                _10613 = _10570.z > 1.0;
                            }
                            else
                            {
                                _10613 = _10606;
                            }
                            if (_10613)
                            {
                                _18167 = 1.0;
                                break;
                            }
                            highp float _10620 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _10625 = frag_info.shadow_cascade_count + float(int(_10430.y + 0.5));
                            highp float _10630 = _10570.z - frag_info.spot_shadow_params.y;
                            highp float _10641 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_10641 = _10641;
                            highp vec2 _10648 = vec2(cos(mp_copy_10641), sin(mp_copy_10641)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _10650 = _10648.x;
                            highp float _10652 = _10648.y;
                            highp vec2 _10660 = vec2(_10650 - _10652, _10650 + _10652) * 0.707106769084930419921875;
                            highp float _10853 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10577, 0.0, 1.0)) / _10620, 1.0 - clamp(_10575.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10853 = _10853;
                            highp vec2 _10668 = _10575 + _10648;
                            highp float _10875 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10668.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10668.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10875 = _10875;
                            highp vec2 _10676 = _10575 - _10648;
                            highp float _10897 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10676.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10676.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10897 = _10897;
                            highp vec2 _10689 = _10575 + vec2(-_10652, _10650);
                            highp float _10919 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10689.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10689.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10919 = _10919;
                            highp vec2 _10702 = _10575 + vec2(_10652, -_10650);
                            highp float _10941 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10702.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10702.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10941 = _10941;
                            float _10707 = (((mp_copy_10853 + mp_copy_10875) + mp_copy_10897) + mp_copy_10919) + mp_copy_10941;
                            if ((_10707 < 0.5) || (_10707 > 4.5))
                            {
                                _18167 = _10707 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _10719 = _10575 + _10660;
                            highp float _10963 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10719.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10719.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10963 = _10963;
                            highp vec2 _10726 = _10575 - _10660;
                            highp float _10985 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10726.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10726.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10985 = _10985;
                            highp float _10734 = _10660.y;
                            highp float _10737 = _10660.x;
                            highp vec2 _10739 = _10575 + vec2(-_10734, _10737);
                            highp float _11007 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10739.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10739.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11007 = _11007;
                            highp vec2 _10752 = _10575 + vec2(_10734, -_10737);
                            highp float _11029 = float(_10630 <= textureLod(shadow_map, vec2((_10625 + clamp(_10752.x, 0.0, 1.0)) / _10620, 1.0 - clamp(_10752.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11029 = _11029;
                            _18167 = (_10707 + (((mp_copy_10963 + mp_copy_10985) + mp_copy_11007) + mp_copy_11029)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18189 = _7142 * _18167;
                    }
                    else
                    {
                        _18189 = _7142;
                    }
                    _18188 = _18189;
                }
                else
                {
                    _18188 = _7118;
                }
                _18190 = _18192;
                _18187 = _18188;
                _18176 = _7064;
            }
            hp_copy_18190 = _18190;
            highp vec3 _18205 = vec3(0.0);
            highp vec3 _18206 = vec3(0.0);
            do
            {
                float _11095 = max(dot(_17316, _18176), 0.0);
                highp float hp_copy_11095 = _11095;
                if (_11095 <= 0.0)
                {
                    _18206 = vec3(0.0);
                    _18205 = vec3(0.0);
                    break;
                }
                float _11101 = max(_6841, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11101 = _11101;
                vec3 _11104 = _18176 + mp_copy_17394;
                float _11107 = dot(_11104, _11104);
                vec3 _18203 = vec3(0.0);
                vec3 _18204 = vec3(0.0);
                if (_11107 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11115 = _11104 * inversesqrt(_11107);
                    float _18202 = 0.0;
                    do
                    {
                        float _11172 = dot(_17316, _11115);
                        if (_11172 <= 0.0)
                        {
                            _18202 = 0.0;
                            break;
                        }
                        float _11179 = _18190 * _18190;
                        vec3 _11182 = cross(_17316, _11115);
                        float _11185 = _11172 * _11179;
                        float _11194 = _11179 / (dot(_11182, _11182) + (_11185 * _11185));
                        _18202 = min((_11194 * _11194) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _11232 = _6837 + ((vec3(1.0) - _6837) * pow(clamp(1.0 - max(dot(_11115, _17394), 0.0), 0.0, 1.0), 5.0));
                    _18204 = (_11232 * min(_18202 * (0.5 / max(mix((2.0 * hp_copy_11095) * _11101, hp_copy_11095 + hp_copy_11101, hp_copy_18190 * hp_copy_18190), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _18203 = _11232;
                }
                else
                {
                    _18204 = vec3(0.0);
                    _18203 = _6837;
                }
                _18206 = (_18204 * _18187) * _11095;
                _18205 = (((((vec3(1.0) - _18203) * (1.0 - _5792)) * _6689) * 0.3183098733425140380859375) * _18187) * _11095;
                break;
            } while(false);
            _18738 = _18066 + (_18205 + _18206);
        }
        _18737 = _18738;
    }
    mat3 _7210 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7213 = _17407 > 0.5;
    bvec3 _7216 = bvec3(_7213);
    highp vec3 _7217 = vec3(_7216.x ? _17422.x : _17316.x, _7216.y ? _17422.y : _17316.y, _7216.z ? _17422.z : _17316.z);
    vec3 mp_copy_7217 = _7217;
    vec3 _7218 = _7210 * mp_copy_7217;
    vec3 _17427 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _11279 = _6849 + (((step(vec3(0.0), _6849) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_11279 = _11279;
        highp vec3 _11281 = vec3(1.0) / hp_copy_11279;
        highp vec3 _11298 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _11281, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _11281);
        _17427 = normalize((v_position + (_6849 * max(min(min(_11298.x, _11298.y), _11298.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _17427 = _6849;
    }
    bool _11526 = false;
    vec3 _7223 = _7210 * _17427;
    float _11345 = _7218.y;
    float _11346 = 0.48860299587249755859375 * _11345;
    float _11352 = _7218.z;
    float _11353 = 0.48860299587249755859375 * _11352;
    float _11359 = _7218.x;
    float _11360 = 0.48860299587249755859375 * _11359;
    float _11367 = 1.09254801273345947265625 * _11359;
    float _11370 = _11367 * _11345;
    float _11380 = (1.09254801273345947265625 * _11345) * _11352;
    float _11392 = 0.3153919875621795654296875 * (((3.0 * _11352) * _11352) - 1.0);
    float _11402 = _11367 * _11352;
    float _11418 = 0.546274006366729736328125 * ((_11359 * _11359) - (_11345 * _11345));
    vec3 _7226 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _11346)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _11353)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _11360)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _11370)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _11380)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _11392)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _11402)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _11418), vec3(0.0));
    vec3 _17428 = vec3(0.0);
    do
    {
        _11526 = radiance_layout_info.mip_layout > 0.5;
        if (_11526)
        {
            vec2 _11605 = vec2(atan(_7223.z, _7223.x), asin(clamp(_7223.y, -1.0, 1.0)));
            highp vec2 hp_copy_11605 = _11605;
            _17428 = textureLod(prefiltered_radiance, (hp_copy_11605 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17364, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _11624 = vec2(atan(_7223.z, _7223.x), asin(clamp(_7223.y, -1.0, 1.0)));
        highp vec2 hp_copy_11624 = _11624;
        highp vec2 _11629 = (hp_copy_11624 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _11536 = clamp(_11629.y, 0.00390625, 0.99609375);
        float _11540 = clamp(_17364, 0.0, 1.0) * 7.0;
        float _11542 = floor(_11540);
        highp float _11561 = _11629.x;
        _17428 = mix(textureLod(prefiltered_radiance, vec2(_11561, (_11542 + _11536) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_11561, (min(_11542 + 1.0, 7.0) + _11536) * 0.125), 0.0).xyz, vec3(_11540 - _11542));
        break;
    } while(false);
    bool _7233 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _17433 = vec3(0.0);
    highp vec3 _17434 = vec3(0.0);
    if (_7233)
    {
        vec3 _17429 = vec3(0.0);
        do
        {
            if (_11526)
            {
                vec2 _11917 = vec2(atan(_7223.z, _7223.x), asin(clamp(_7223.y, -1.0, 1.0)));
                highp vec2 hp_copy_11917 = _11917;
                _17429 = textureLod(prefiltered_radiance_b, (hp_copy_11917 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17364, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _11936 = vec2(atan(_7223.z, _7223.x), asin(clamp(_7223.y, -1.0, 1.0)));
            highp vec2 hp_copy_11936 = _11936;
            highp vec2 _11941 = (hp_copy_11936 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _11848 = clamp(_11941.y, 0.00390625, 0.99609375);
            float _11852 = clamp(_17364, 0.0, 1.0) * 7.0;
            float _11854 = floor(_11852);
            highp float _11873 = _11941.x;
            _17429 = mix(textureLod(prefiltered_radiance_b, vec2(_11873, (_11854 + _11848) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_11873, (min(_11854 + 1.0, 7.0) + _11848) * 0.125), 0.0).xyz, vec3(_11852 - _11854));
            break;
        } while(false);
        highp vec3 _7244 = vec3(frag_info.radiance_blend.x);
        _17434 = mix(_17428, _17429, _7244);
        _17433 = mix(_7226, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _11346)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _11353)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _11360)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _11370)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _11380)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _11392)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _11402)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _11418), vec3(0.0)), _7244);
    }
    else
    {
        _17434 = _17428;
        _17433 = _7226;
    }
    highp float _11954 = 0.0;
    highp vec3 _7255 = _17433 * frag_info.environment_intensity;
    float _17435 = 0.0;
    do
    {
        _11954 = frag_info.gi_grid.w;
        if (_11954 <= 0.0)
        {
            _17435 = 0.0;
            break;
        }
        highp vec3 _11967 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _11975 = min(_11967, (frag_info.gi_counts.xyz - vec3(1.0)) - _11967);
        _17435 = clamp(min(_11975.x, min(_11975.y, _11975.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _17626 = vec3(0.0);
    if (_17435 > 0.0)
    {
        highp vec3 _12067 = v_position + (((_17316 * 0.20000000298023223876953125) + (mp_copy_17394 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _12070 = _12067 / frag_info.gi_grid.xyz;
        highp vec3 _12072 = floor(_12070);
        highp vec3 _12078 = clamp(_12070 - _12072, vec3(0.0), vec3(1.0));
        vec3 mp_copy_12078 = _12078;
        highp vec3 _12200 = _12072 - frag_info.gi_anchor.xyz;
        bool _12203 = any(lessThan(_12200, vec3(0.0)));
        bool _12211 = false;
        if (!_12203)
        {
            _12211 = any(greaterThanEqual(_12200, frag_info.gi_counts.xyz));
        }
        else
        {
            _12211 = _12203;
        }
        vec3 mp_copy_17436 = vec3(0.0);
        highp float _12212 = _12211 ? 0.0 : 1.0;
        float mp_copy_12212 = _12212;
        vec3 _12214 = vec3(1.0) - mp_copy_12078;
        vec3 _12218 = max(_12214, vec3(0.001000000047497451305389404296875));
        highp vec3 _12234 = (_12072 * frag_info.gi_grid.xyz) - _12067;
        highp float _12236 = length(_12234);
        highp vec3 _17436 = vec3(0.0);
        if (_12236 > 9.9999997473787516355514526367188e-06)
        {
            _17436 = _12234 / vec3(_12236);
        }
        else
        {
            _17436 = _17316;
        }
        mp_copy_17436 = _17436;
        float _12254 = pow((dot(_17436, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12379 = _12072 - (frag_info.gi_counts.xyz * floor(_12072 / frag_info.gi_counts.xyz));
        highp float _12395 = _12379.x + (frag_info.gi_counts.x * (_12379.y + (frag_info.gi_counts.y * _12379.z)));
        bool _12265 = frag_info.gi_visibility.x > 0.0;
        float _17441 = 0.0;
        if (_12265)
        {
            highp float _12403 = floor(_12395 / frag_info.gi_counts.w);
            highp vec2 _12417 = vec2((_12395 - (_12403 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12403 * 16.0));
            vec3 _12277 = -mp_copy_17436;
            vec3 _12465 = _12277 / vec3((abs(_12277.x) + abs(_12277.y)) + abs(_12277.z));
            vec2 _17437 = vec2(0.0);
            if (_12465.z >= 0.0)
            {
                _17437 = _12465.xy;
            }
            else
            {
                _17437 = (vec2(1.0) - abs(_12465.yx)) * vec2((_12465.x >= 0.0) ? 1.0 : (-1.0), (_12465.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12281 = texture(irradiance_field, clamp((_12417 + vec2(1.0)) + (clamp((_17437 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12417 + vec2(0.5), _12417 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12286 = _12281.x * frag_info.gi_visibility.z;
            highp float _12298 = abs((_12286 * _12286) - ((_12281.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12304 = (_12236 - _12286) - frag_info.gi_visibility.y;
            highp float _17438 = 0.0;
            if (_12304 <= 0.0)
            {
                _17438 = 1.0;
            }
            else
            {
                _17438 = _12298 / (_12298 + (_12304 * _12304));
            }
            _17441 = _12254 * mix(1.0, max(0.0500000007450580596923828125, (_17438 * _17438) * _17438), frag_info.gi_visibility.x);
        }
        else
        {
            _17441 = _12254;
        }
        float _12332 = max(9.9999999747524270787835121154785e-07, _17441);
        float _17442 = 0.0;
        if (_12332 < 0.20000000298023223876953125)
        {
            _17442 = _12332 * ((_12332 * _12332) * 25.0);
        }
        else
        {
            _17442 = _12332;
        }
        float _12347 = _17442 * (((_12218.x * _12218.y) * _12218.z) * mp_copy_12212);
        highp float _12506 = floor(_12395 / frag_info.gi_counts.w);
        highp vec2 _12520 = vec2((_12395 - (_12506 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12506 * 8.0));
        vec3 _12568 = _17316 / vec3((abs(_17316.x) + abs(_17316.y)) + abs(_17316.z));
        bool _12571 = _12568.z >= 0.0;
        vec2 _17443 = vec2(0.0);
        if (_12571)
        {
            _17443 = _12568.xy;
        }
        else
        {
            _17443 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12359 = texture(irradiance_field, clamp((_12520 + vec2(1.0)) + (clamp((_17443 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12520 + vec2(0.5), _12520 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12654 = _12072 + vec3(1.0, 0.0, 0.0);
        highp vec3 _12659 = _12654 - frag_info.gi_anchor.xyz;
        bool _12662 = any(lessThan(_12659, vec3(0.0)));
        bool _12670 = false;
        if (!_12662)
        {
            _12670 = any(greaterThanEqual(_12659, frag_info.gi_counts.xyz));
        }
        else
        {
            _12670 = _12662;
        }
        vec3 mp_copy_17445 = vec3(0.0);
        highp float _12671 = _12670 ? 0.0 : 1.0;
        float mp_copy_12671 = _12671;
        vec3 _12677 = max(mix(_12214, mp_copy_12078, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _12693 = (_12654 * frag_info.gi_grid.xyz) - _12067;
        highp float _12695 = length(_12693);
        highp vec3 _17445 = vec3(0.0);
        if (_12695 > 9.9999997473787516355514526367188e-06)
        {
            _17445 = _12693 / vec3(_12695);
        }
        else
        {
            _17445 = _17316;
        }
        mp_copy_17445 = _17445;
        float _12713 = pow((dot(_17445, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12838 = _12654 - (frag_info.gi_counts.xyz * floor(_12654 / frag_info.gi_counts.xyz));
        highp float _12854 = _12838.x + (frag_info.gi_counts.x * (_12838.y + (frag_info.gi_counts.y * _12838.z)));
        float _17450 = 0.0;
        if (_12265)
        {
            highp float _12862 = floor(_12854 / frag_info.gi_counts.w);
            highp vec2 _12876 = vec2((_12854 - (_12862 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12862 * 16.0));
            vec3 _12736 = -mp_copy_17445;
            vec3 _12924 = _12736 / vec3((abs(_12736.x) + abs(_12736.y)) + abs(_12736.z));
            vec2 _17446 = vec2(0.0);
            if (_12924.z >= 0.0)
            {
                _17446 = _12924.xy;
            }
            else
            {
                _17446 = (vec2(1.0) - abs(_12924.yx)) * vec2((_12924.x >= 0.0) ? 1.0 : (-1.0), (_12924.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12740 = texture(irradiance_field, clamp((_12876 + vec2(1.0)) + (clamp((_17446 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12876 + vec2(0.5), _12876 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12745 = _12740.x * frag_info.gi_visibility.z;
            highp float _12757 = abs((_12745 * _12745) - ((_12740.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12763 = (_12695 - _12745) - frag_info.gi_visibility.y;
            highp float _17447 = 0.0;
            if (_12763 <= 0.0)
            {
                _17447 = 1.0;
            }
            else
            {
                _17447 = _12757 / (_12757 + (_12763 * _12763));
            }
            _17450 = _12713 * mix(1.0, max(0.0500000007450580596923828125, (_17447 * _17447) * _17447), frag_info.gi_visibility.x);
        }
        else
        {
            _17450 = _12713;
        }
        float _12791 = max(9.9999999747524270787835121154785e-07, _17450);
        float _17451 = 0.0;
        if (_12791 < 0.20000000298023223876953125)
        {
            _17451 = _12791 * ((_12791 * _12791) * 25.0);
        }
        else
        {
            _17451 = _12791;
        }
        float _12806 = _17451 * (((_12677.x * _12677.y) * _12677.z) * mp_copy_12671);
        highp float _12965 = floor(_12854 / frag_info.gi_counts.w);
        highp vec2 _12979 = vec2((_12854 - (_12965 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12965 * 8.0));
        vec2 _17452 = vec2(0.0);
        if (_12571)
        {
            _17452 = _12568.xy;
        }
        else
        {
            _17452 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12818 = texture(irradiance_field, clamp((_12979 + vec2(1.0)) + (clamp((_17452 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12979 + vec2(0.5), _12979 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13113 = _12072 + vec3(0.0, 1.0, 0.0);
        highp vec3 _13118 = _13113 - frag_info.gi_anchor.xyz;
        bool _13121 = any(lessThan(_13118, vec3(0.0)));
        bool _13129 = false;
        if (!_13121)
        {
            _13129 = any(greaterThanEqual(_13118, frag_info.gi_counts.xyz));
        }
        else
        {
            _13129 = _13121;
        }
        vec3 mp_copy_17454 = vec3(0.0);
        highp float _13130 = _13129 ? 0.0 : 1.0;
        float mp_copy_13130 = _13130;
        vec3 _13136 = max(mix(_12214, mp_copy_12078, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13152 = (_13113 * frag_info.gi_grid.xyz) - _12067;
        highp float _13154 = length(_13152);
        highp vec3 _17454 = vec3(0.0);
        if (_13154 > 9.9999997473787516355514526367188e-06)
        {
            _17454 = _13152 / vec3(_13154);
        }
        else
        {
            _17454 = _17316;
        }
        mp_copy_17454 = _17454;
        float _13172 = pow((dot(_17454, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13297 = _13113 - (frag_info.gi_counts.xyz * floor(_13113 / frag_info.gi_counts.xyz));
        highp float _13313 = _13297.x + (frag_info.gi_counts.x * (_13297.y + (frag_info.gi_counts.y * _13297.z)));
        float _17459 = 0.0;
        if (_12265)
        {
            highp float _13321 = floor(_13313 / frag_info.gi_counts.w);
            highp vec2 _13335 = vec2((_13313 - (_13321 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13321 * 16.0));
            vec3 _13195 = -mp_copy_17454;
            vec3 _13383 = _13195 / vec3((abs(_13195.x) + abs(_13195.y)) + abs(_13195.z));
            vec2 _17455 = vec2(0.0);
            if (_13383.z >= 0.0)
            {
                _17455 = _13383.xy;
            }
            else
            {
                _17455 = (vec2(1.0) - abs(_13383.yx)) * vec2((_13383.x >= 0.0) ? 1.0 : (-1.0), (_13383.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13199 = texture(irradiance_field, clamp((_13335 + vec2(1.0)) + (clamp((_17455 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13335 + vec2(0.5), _13335 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13204 = _13199.x * frag_info.gi_visibility.z;
            highp float _13216 = abs((_13204 * _13204) - ((_13199.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13222 = (_13154 - _13204) - frag_info.gi_visibility.y;
            highp float _17456 = 0.0;
            if (_13222 <= 0.0)
            {
                _17456 = 1.0;
            }
            else
            {
                _17456 = _13216 / (_13216 + (_13222 * _13222));
            }
            _17459 = _13172 * mix(1.0, max(0.0500000007450580596923828125, (_17456 * _17456) * _17456), frag_info.gi_visibility.x);
        }
        else
        {
            _17459 = _13172;
        }
        float _13250 = max(9.9999999747524270787835121154785e-07, _17459);
        float _17460 = 0.0;
        if (_13250 < 0.20000000298023223876953125)
        {
            _17460 = _13250 * ((_13250 * _13250) * 25.0);
        }
        else
        {
            _17460 = _13250;
        }
        float _13265 = _17460 * (((_13136.x * _13136.y) * _13136.z) * mp_copy_13130);
        highp float _13424 = floor(_13313 / frag_info.gi_counts.w);
        highp vec2 _13438 = vec2((_13313 - (_13424 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13424 * 8.0));
        vec2 _17461 = vec2(0.0);
        if (_12571)
        {
            _17461 = _12568.xy;
        }
        else
        {
            _17461 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13277 = texture(irradiance_field, clamp((_13438 + vec2(1.0)) + (clamp((_17461 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13438 + vec2(0.5), _13438 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13572 = _12072 + vec3(1.0, 1.0, 0.0);
        highp vec3 _13577 = _13572 - frag_info.gi_anchor.xyz;
        bool _13580 = any(lessThan(_13577, vec3(0.0)));
        bool _13588 = false;
        if (!_13580)
        {
            _13588 = any(greaterThanEqual(_13577, frag_info.gi_counts.xyz));
        }
        else
        {
            _13588 = _13580;
        }
        vec3 mp_copy_17463 = vec3(0.0);
        highp float _13589 = _13588 ? 0.0 : 1.0;
        float mp_copy_13589 = _13589;
        vec3 _13595 = max(mix(_12214, mp_copy_12078, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13611 = (_13572 * frag_info.gi_grid.xyz) - _12067;
        highp float _13613 = length(_13611);
        highp vec3 _17463 = vec3(0.0);
        if (_13613 > 9.9999997473787516355514526367188e-06)
        {
            _17463 = _13611 / vec3(_13613);
        }
        else
        {
            _17463 = _17316;
        }
        mp_copy_17463 = _17463;
        float _13631 = pow((dot(_17463, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13756 = _13572 - (frag_info.gi_counts.xyz * floor(_13572 / frag_info.gi_counts.xyz));
        highp float _13772 = _13756.x + (frag_info.gi_counts.x * (_13756.y + (frag_info.gi_counts.y * _13756.z)));
        float _17468 = 0.0;
        if (_12265)
        {
            highp float _13780 = floor(_13772 / frag_info.gi_counts.w);
            highp vec2 _13794 = vec2((_13772 - (_13780 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13780 * 16.0));
            vec3 _13654 = -mp_copy_17463;
            vec3 _13842 = _13654 / vec3((abs(_13654.x) + abs(_13654.y)) + abs(_13654.z));
            vec2 _17464 = vec2(0.0);
            if (_13842.z >= 0.0)
            {
                _17464 = _13842.xy;
            }
            else
            {
                _17464 = (vec2(1.0) - abs(_13842.yx)) * vec2((_13842.x >= 0.0) ? 1.0 : (-1.0), (_13842.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13658 = texture(irradiance_field, clamp((_13794 + vec2(1.0)) + (clamp((_17464 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13794 + vec2(0.5), _13794 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13663 = _13658.x * frag_info.gi_visibility.z;
            highp float _13675 = abs((_13663 * _13663) - ((_13658.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13681 = (_13613 - _13663) - frag_info.gi_visibility.y;
            highp float _17465 = 0.0;
            if (_13681 <= 0.0)
            {
                _17465 = 1.0;
            }
            else
            {
                _17465 = _13675 / (_13675 + (_13681 * _13681));
            }
            _17468 = _13631 * mix(1.0, max(0.0500000007450580596923828125, (_17465 * _17465) * _17465), frag_info.gi_visibility.x);
        }
        else
        {
            _17468 = _13631;
        }
        float _13709 = max(9.9999999747524270787835121154785e-07, _17468);
        float _17469 = 0.0;
        if (_13709 < 0.20000000298023223876953125)
        {
            _17469 = _13709 * ((_13709 * _13709) * 25.0);
        }
        else
        {
            _17469 = _13709;
        }
        float _13724 = _17469 * (((_13595.x * _13595.y) * _13595.z) * mp_copy_13589);
        highp float _13883 = floor(_13772 / frag_info.gi_counts.w);
        highp vec2 _13897 = vec2((_13772 - (_13883 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13883 * 8.0));
        vec2 _17470 = vec2(0.0);
        if (_12571)
        {
            _17470 = _12568.xy;
        }
        else
        {
            _17470 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13736 = texture(irradiance_field, clamp((_13897 + vec2(1.0)) + (clamp((_17470 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13897 + vec2(0.5), _13897 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14031 = _12072 + vec3(0.0, 0.0, 1.0);
        highp vec3 _14036 = _14031 - frag_info.gi_anchor.xyz;
        bool _14039 = any(lessThan(_14036, vec3(0.0)));
        bool _14047 = false;
        if (!_14039)
        {
            _14047 = any(greaterThanEqual(_14036, frag_info.gi_counts.xyz));
        }
        else
        {
            _14047 = _14039;
        }
        vec3 mp_copy_17472 = vec3(0.0);
        highp float _14048 = _14047 ? 0.0 : 1.0;
        float mp_copy_14048 = _14048;
        vec3 _14054 = max(mix(_12214, mp_copy_12078, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14070 = (_14031 * frag_info.gi_grid.xyz) - _12067;
        highp float _14072 = length(_14070);
        highp vec3 _17472 = vec3(0.0);
        if (_14072 > 9.9999997473787516355514526367188e-06)
        {
            _17472 = _14070 / vec3(_14072);
        }
        else
        {
            _17472 = _17316;
        }
        mp_copy_17472 = _17472;
        float _14090 = pow((dot(_17472, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14215 = _14031 - (frag_info.gi_counts.xyz * floor(_14031 / frag_info.gi_counts.xyz));
        highp float _14231 = _14215.x + (frag_info.gi_counts.x * (_14215.y + (frag_info.gi_counts.y * _14215.z)));
        float _17477 = 0.0;
        if (_12265)
        {
            highp float _14239 = floor(_14231 / frag_info.gi_counts.w);
            highp vec2 _14253 = vec2((_14231 - (_14239 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14239 * 16.0));
            vec3 _14113 = -mp_copy_17472;
            vec3 _14301 = _14113 / vec3((abs(_14113.x) + abs(_14113.y)) + abs(_14113.z));
            vec2 _17473 = vec2(0.0);
            if (_14301.z >= 0.0)
            {
                _17473 = _14301.xy;
            }
            else
            {
                _17473 = (vec2(1.0) - abs(_14301.yx)) * vec2((_14301.x >= 0.0) ? 1.0 : (-1.0), (_14301.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14117 = texture(irradiance_field, clamp((_14253 + vec2(1.0)) + (clamp((_17473 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14253 + vec2(0.5), _14253 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14122 = _14117.x * frag_info.gi_visibility.z;
            highp float _14134 = abs((_14122 * _14122) - ((_14117.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14140 = (_14072 - _14122) - frag_info.gi_visibility.y;
            highp float _17474 = 0.0;
            if (_14140 <= 0.0)
            {
                _17474 = 1.0;
            }
            else
            {
                _17474 = _14134 / (_14134 + (_14140 * _14140));
            }
            _17477 = _14090 * mix(1.0, max(0.0500000007450580596923828125, (_17474 * _17474) * _17474), frag_info.gi_visibility.x);
        }
        else
        {
            _17477 = _14090;
        }
        float _14168 = max(9.9999999747524270787835121154785e-07, _17477);
        float _17478 = 0.0;
        if (_14168 < 0.20000000298023223876953125)
        {
            _17478 = _14168 * ((_14168 * _14168) * 25.0);
        }
        else
        {
            _17478 = _14168;
        }
        float _14183 = _17478 * (((_14054.x * _14054.y) * _14054.z) * mp_copy_14048);
        highp float _14342 = floor(_14231 / frag_info.gi_counts.w);
        highp vec2 _14356 = vec2((_14231 - (_14342 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14342 * 8.0));
        vec2 _17479 = vec2(0.0);
        if (_12571)
        {
            _17479 = _12568.xy;
        }
        else
        {
            _17479 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14195 = texture(irradiance_field, clamp((_14356 + vec2(1.0)) + (clamp((_17479 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14356 + vec2(0.5), _14356 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14490 = _12072 + vec3(1.0, 0.0, 1.0);
        highp vec3 _14495 = _14490 - frag_info.gi_anchor.xyz;
        bool _14498 = any(lessThan(_14495, vec3(0.0)));
        bool _14506 = false;
        if (!_14498)
        {
            _14506 = any(greaterThanEqual(_14495, frag_info.gi_counts.xyz));
        }
        else
        {
            _14506 = _14498;
        }
        vec3 mp_copy_17481 = vec3(0.0);
        highp float _14507 = _14506 ? 0.0 : 1.0;
        float mp_copy_14507 = _14507;
        vec3 _14513 = max(mix(_12214, mp_copy_12078, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14529 = (_14490 * frag_info.gi_grid.xyz) - _12067;
        highp float _14531 = length(_14529);
        highp vec3 _17481 = vec3(0.0);
        if (_14531 > 9.9999997473787516355514526367188e-06)
        {
            _17481 = _14529 / vec3(_14531);
        }
        else
        {
            _17481 = _17316;
        }
        mp_copy_17481 = _17481;
        float _14549 = pow((dot(_17481, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14674 = _14490 - (frag_info.gi_counts.xyz * floor(_14490 / frag_info.gi_counts.xyz));
        highp float _14690 = _14674.x + (frag_info.gi_counts.x * (_14674.y + (frag_info.gi_counts.y * _14674.z)));
        float _17486 = 0.0;
        if (_12265)
        {
            highp float _14698 = floor(_14690 / frag_info.gi_counts.w);
            highp vec2 _14712 = vec2((_14690 - (_14698 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14698 * 16.0));
            vec3 _14572 = -mp_copy_17481;
            vec3 _14760 = _14572 / vec3((abs(_14572.x) + abs(_14572.y)) + abs(_14572.z));
            vec2 _17482 = vec2(0.0);
            if (_14760.z >= 0.0)
            {
                _17482 = _14760.xy;
            }
            else
            {
                _17482 = (vec2(1.0) - abs(_14760.yx)) * vec2((_14760.x >= 0.0) ? 1.0 : (-1.0), (_14760.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14576 = texture(irradiance_field, clamp((_14712 + vec2(1.0)) + (clamp((_17482 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14712 + vec2(0.5), _14712 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14581 = _14576.x * frag_info.gi_visibility.z;
            highp float _14593 = abs((_14581 * _14581) - ((_14576.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14599 = (_14531 - _14581) - frag_info.gi_visibility.y;
            highp float _17483 = 0.0;
            if (_14599 <= 0.0)
            {
                _17483 = 1.0;
            }
            else
            {
                _17483 = _14593 / (_14593 + (_14599 * _14599));
            }
            _17486 = _14549 * mix(1.0, max(0.0500000007450580596923828125, (_17483 * _17483) * _17483), frag_info.gi_visibility.x);
        }
        else
        {
            _17486 = _14549;
        }
        float _14627 = max(9.9999999747524270787835121154785e-07, _17486);
        float _17487 = 0.0;
        if (_14627 < 0.20000000298023223876953125)
        {
            _17487 = _14627 * ((_14627 * _14627) * 25.0);
        }
        else
        {
            _17487 = _14627;
        }
        float _14642 = _17487 * (((_14513.x * _14513.y) * _14513.z) * mp_copy_14507);
        highp float _14801 = floor(_14690 / frag_info.gi_counts.w);
        highp vec2 _14815 = vec2((_14690 - (_14801 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14801 * 8.0));
        vec2 _17488 = vec2(0.0);
        if (_12571)
        {
            _17488 = _12568.xy;
        }
        else
        {
            _17488 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14654 = texture(irradiance_field, clamp((_14815 + vec2(1.0)) + (clamp((_17488 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14815 + vec2(0.5), _14815 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14949 = _12072 + vec3(0.0, 1.0, 1.0);
        highp vec3 _14954 = _14949 - frag_info.gi_anchor.xyz;
        bool _14957 = any(lessThan(_14954, vec3(0.0)));
        bool _14965 = false;
        if (!_14957)
        {
            _14965 = any(greaterThanEqual(_14954, frag_info.gi_counts.xyz));
        }
        else
        {
            _14965 = _14957;
        }
        vec3 mp_copy_17490 = vec3(0.0);
        highp float _14966 = _14965 ? 0.0 : 1.0;
        float mp_copy_14966 = _14966;
        vec3 _14972 = max(mix(_12214, mp_copy_12078, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14988 = (_14949 * frag_info.gi_grid.xyz) - _12067;
        highp float _14990 = length(_14988);
        highp vec3 _17490 = vec3(0.0);
        if (_14990 > 9.9999997473787516355514526367188e-06)
        {
            _17490 = _14988 / vec3(_14990);
        }
        else
        {
            _17490 = _17316;
        }
        mp_copy_17490 = _17490;
        float _15008 = pow((dot(_17490, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15133 = _14949 - (frag_info.gi_counts.xyz * floor(_14949 / frag_info.gi_counts.xyz));
        highp float _15149 = _15133.x + (frag_info.gi_counts.x * (_15133.y + (frag_info.gi_counts.y * _15133.z)));
        float _17495 = 0.0;
        if (_12265)
        {
            highp float _15157 = floor(_15149 / frag_info.gi_counts.w);
            highp vec2 _15171 = vec2((_15149 - (_15157 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15157 * 16.0));
            vec3 _15031 = -mp_copy_17490;
            vec3 _15219 = _15031 / vec3((abs(_15031.x) + abs(_15031.y)) + abs(_15031.z));
            vec2 _17491 = vec2(0.0);
            if (_15219.z >= 0.0)
            {
                _17491 = _15219.xy;
            }
            else
            {
                _17491 = (vec2(1.0) - abs(_15219.yx)) * vec2((_15219.x >= 0.0) ? 1.0 : (-1.0), (_15219.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15035 = texture(irradiance_field, clamp((_15171 + vec2(1.0)) + (clamp((_17491 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15171 + vec2(0.5), _15171 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15040 = _15035.x * frag_info.gi_visibility.z;
            highp float _15052 = abs((_15040 * _15040) - ((_15035.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15058 = (_14990 - _15040) - frag_info.gi_visibility.y;
            highp float _17492 = 0.0;
            if (_15058 <= 0.0)
            {
                _17492 = 1.0;
            }
            else
            {
                _17492 = _15052 / (_15052 + (_15058 * _15058));
            }
            _17495 = _15008 * mix(1.0, max(0.0500000007450580596923828125, (_17492 * _17492) * _17492), frag_info.gi_visibility.x);
        }
        else
        {
            _17495 = _15008;
        }
        float _15086 = max(9.9999999747524270787835121154785e-07, _17495);
        float _17496 = 0.0;
        if (_15086 < 0.20000000298023223876953125)
        {
            _17496 = _15086 * ((_15086 * _15086) * 25.0);
        }
        else
        {
            _17496 = _15086;
        }
        float _15101 = _17496 * (((_14972.x * _14972.y) * _14972.z) * mp_copy_14966);
        highp float _15260 = floor(_15149 / frag_info.gi_counts.w);
        highp vec2 _15274 = vec2((_15149 - (_15260 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15260 * 8.0));
        vec2 _17497 = vec2(0.0);
        if (_12571)
        {
            _17497 = _12568.xy;
        }
        else
        {
            _17497 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15113 = texture(irradiance_field, clamp((_15274 + vec2(1.0)) + (clamp((_17497 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15274 + vec2(0.5), _15274 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15408 = _12072 + vec3(1.0);
        highp vec3 _15413 = _15408 - frag_info.gi_anchor.xyz;
        bool _15416 = any(lessThan(_15413, vec3(0.0)));
        bool _15424 = false;
        if (!_15416)
        {
            _15424 = any(greaterThanEqual(_15413, frag_info.gi_counts.xyz));
        }
        else
        {
            _15424 = _15416;
        }
        vec3 mp_copy_17499 = vec3(0.0);
        highp float _15425 = _15424 ? 0.0 : 1.0;
        float mp_copy_15425 = _15425;
        vec3 _15431 = max(mp_copy_12078, vec3(0.001000000047497451305389404296875));
        highp vec3 _15447 = (_15408 * frag_info.gi_grid.xyz) - _12067;
        highp float _15449 = length(_15447);
        highp vec3 _17499 = vec3(0.0);
        if (_15449 > 9.9999997473787516355514526367188e-06)
        {
            _17499 = _15447 / vec3(_15449);
        }
        else
        {
            _17499 = _17316;
        }
        mp_copy_17499 = _17499;
        float _15467 = pow((dot(_17499, _17316) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15592 = _15408 - (frag_info.gi_counts.xyz * floor(_15408 / frag_info.gi_counts.xyz));
        highp float _15608 = _15592.x + (frag_info.gi_counts.x * (_15592.y + (frag_info.gi_counts.y * _15592.z)));
        float _17504 = 0.0;
        if (_12265)
        {
            highp float _15616 = floor(_15608 / frag_info.gi_counts.w);
            highp vec2 _15630 = vec2((_15608 - (_15616 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15616 * 16.0));
            vec3 _15490 = -mp_copy_17499;
            vec3 _15678 = _15490 / vec3((abs(_15490.x) + abs(_15490.y)) + abs(_15490.z));
            vec2 _17500 = vec2(0.0);
            if (_15678.z >= 0.0)
            {
                _17500 = _15678.xy;
            }
            else
            {
                _17500 = (vec2(1.0) - abs(_15678.yx)) * vec2((_15678.x >= 0.0) ? 1.0 : (-1.0), (_15678.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15494 = texture(irradiance_field, clamp((_15630 + vec2(1.0)) + (clamp((_17500 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15630 + vec2(0.5), _15630 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15499 = _15494.x * frag_info.gi_visibility.z;
            highp float _15511 = abs((_15499 * _15499) - ((_15494.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15517 = (_15449 - _15499) - frag_info.gi_visibility.y;
            highp float _17501 = 0.0;
            if (_15517 <= 0.0)
            {
                _17501 = 1.0;
            }
            else
            {
                _17501 = _15511 / (_15511 + (_15517 * _15517));
            }
            _17504 = _15467 * mix(1.0, max(0.0500000007450580596923828125, (_17501 * _17501) * _17501), frag_info.gi_visibility.x);
        }
        else
        {
            _17504 = _15467;
        }
        float _15545 = max(9.9999999747524270787835121154785e-07, _17504);
        float _17505 = 0.0;
        if (_15545 < 0.20000000298023223876953125)
        {
            _17505 = _15545 * ((_15545 * _15545) * 25.0);
        }
        else
        {
            _17505 = _15545;
        }
        float _15560 = _17505 * (((_15431.x * _15431.y) * _15431.z) * mp_copy_15425);
        highp float _15719 = floor(_15608 / frag_info.gi_counts.w);
        highp vec2 _15733 = vec2((_15608 - (_15719 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15719 * 8.0));
        vec2 _17506 = vec2(0.0);
        if (_12571)
        {
            _17506 = _12568.xy;
        }
        else
        {
            _17506 = (vec2(1.0) - abs(_12568.yx)) * vec2((_12568.x >= 0.0) ? 1.0 : (-1.0), (_12568.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12125 = ((((((vec4(max(_12359.xyz, vec3(0.0)) * _12347, _12347) + vec4(max(_12818.xyz, vec3(0.0)) * _12806, _12806)) + vec4(max(_13277.xyz, vec3(0.0)) * _13265, _13265)) + vec4(max(_13736.xyz, vec3(0.0)) * _13724, _13724)) + vec4(max(_14195.xyz, vec3(0.0)) * _14183, _14183)) + vec4(max(_14654.xyz, vec3(0.0)) * _14642, _14642)) + vec4(max(_15113.xyz, vec3(0.0)) * _15101, _15101)) + vec4(max(texture(irradiance_field, clamp((_15733 + vec2(1.0)) + (clamp((_17506 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15733 + vec2(0.5), _15733 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _15560, _15560);
        highp float _12127 = _12125.w;
        highp vec3 _17508 = vec3(0.0);
        if (_12127 > 9.9999999747524270787835121154785e-07)
        {
            _17508 = _12125.xyz / vec3(_12127);
        }
        else
        {
            _17508 = vec3(0.0);
        }
        _17626 = mix(_7255, _17508 * _11954, vec3(_17435));
    }
    else
    {
        _17626 = _7255;
    }
    vec2 _7281 = clamp(vec2(_6845, _17364), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7283 = texture(brdf_lut, vec2(_7281.x * 0.3333333432674407958984375, _7281.y));
    float _7287 = _7283.x;
    float _7290 = _7283.y;
    vec3 _7292 = ((_6837 + ((max(vec3(1.0 - _17364), _6837) - _6837) * pow(clamp(1.0 - _6845, 0.0, 1.0), 5.0))) * _7287) + vec3(_7290);
    float _7298 = 1.0 - (_7287 + _7290);
    vec3 _7302 = vec3(1.0) - _6837;
    vec3 _7305 = _6837 + (_7302 * vec3(0.0476190485060214996337890625));
    vec3 _7316 = ((_7292 * _7298) * _7305) / (vec3(1.0) - (_7305 * _7298));
    float _7319 = 1.0 - _5792;
    vec3 _7320 = _6689 * _7319;
    float _17905 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7213)
    {
        float _15841 = max(acos(clamp(exp2(((-3.321929931640625) * _17364) * _17364), 0.0, 1.0)), 0.100000001490116119384765625);
        _17905 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_17422, _6849), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _17705, 0.0, 1.0)))) + _15841) / (2.0 * _15841), 0.0, 1.0));
    }
    else
    {
        float _17906 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _17906 = clamp((pow(_6841 + _17705, exp2(((-16.0) * _17364) - 1.0)) - 1.0) + _17705, 0.0, 1.0);
        }
        else
        {
            _17906 = _17705;
        }
        _17905 = _17906;
    }
    highp vec3 _7379 = ((((_7316 + (_7320 * ((vec3(1.0) - _7292) - _7316))) * _17626) * _17844) + (((_7292 * (_17434 * frag_info.environment_intensity)) * 1.0) * _17905)) * mix(1.0, _6828, frag_info.radiance_blend.y);
    highp vec3 _18137 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _18137 = _7379 + ((_17389.xyz * _7320) * _5826);
    }
    else
    {
        _18137 = _7379;
    }
    highp vec3 _18141 = vec3(0.0);
    if (_6778)
    {
        highp vec3 _18056 = vec3(0.0);
        highp vec3 _18057 = vec3(0.0);
        do
        {
            float _15938 = max(dot(_17316, _17992), 0.0);
            highp float hp_copy_15938 = _15938;
            if (_15938 <= 0.0)
            {
                _18057 = vec3(0.0);
                _18056 = vec3(0.0);
                break;
            }
            float _15944 = max(_6841, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_15944 = _15944;
            vec3 _15947 = _17992 + mp_copy_17394;
            float _15950 = dot(_15947, _15947);
            vec3 _18054 = vec3(0.0);
            vec3 _18055 = vec3(0.0);
            if (_15950 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _15958 = _15947 * inversesqrt(_15950);
                float _18053 = 0.0;
                do
                {
                    float _16015 = dot(_17316, _15958);
                    if (_16015 <= 0.0)
                    {
                        _18053 = 0.0;
                        break;
                    }
                    float _16022 = _17364 * _17364;
                    vec3 _16025 = cross(_17316, _15958);
                    float _16028 = _16015 * _16022;
                    float _16037 = _16022 / (dot(_16025, _16025) + (_16028 * _16028));
                    _18053 = min((_16037 * _16037) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _16075 = _6837 + (_7302 * pow(clamp(1.0 - max(dot(_15958, _17394), 0.0), 0.0, 1.0), 5.0));
                _18055 = (_16075 * min(_18053 * (0.5 / max(mix((2.0 * hp_copy_15938) * _15944, hp_copy_15938 + hp_copy_15944, hp_copy_17364 * hp_copy_17364), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _18054 = _16075;
            }
            else
            {
                _18055 = vec3(0.0);
                _18054 = _6837;
            }
            _18057 = (_18055 * frag_info.directional_light_color.xyz) * _15938;
            _18056 = (((((vec3(1.0) - _18054) * _7319) * _6689) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _15938;
            break;
        } while(false);
        _18141 = _18066 + ((_18056 + _18057) * _6828);
    }
    else
    {
        _18141 = _18066;
    }
    bool _7441 = _FogInfo.params0.y > 0.5;
    bool _7447 = false;
    if (_7441)
    {
        _7447 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7447 = _7441;
    }
    highp vec3 _18146 = vec3(0.0);
    if (_7447)
    {
        vec3 mp_copy_18142 = vec3(0.0);
        highp vec3 _18142 = vec3(0.0);
        if (_9448)
        {
            _18142 = -view_info.camera_forward.xyz;
        }
        else
        {
            _18142 = normalize(v_viewvector);
        }
        mp_copy_18142 = _18142;
        vec3 _7452 = _7210 * (-mp_copy_18142);
        vec3 _18143 = vec3(0.0);
        do
        {
            if (_11526)
            {
                vec2 _16197 = vec2(atan(_7452.z, _7452.x), asin(clamp(_7452.y, -1.0, 1.0)));
                highp vec2 hp_copy_16197 = _16197;
                _18143 = textureLod(prefiltered_radiance, (hp_copy_16197 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _16216 = vec2(atan(_7452.z, _7452.x), asin(clamp(_7452.y, -1.0, 1.0)));
            highp vec2 hp_copy_16216 = _16216;
            highp vec2 _16221 = (hp_copy_16216 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _16128 = clamp(_16221.y, 0.00390625, 0.99609375);
            float _16134 = floor(0.0);
            highp float _16153 = _16221.x;
            _18143 = mix(textureLod(prefiltered_radiance, vec2(_16153, (_16134 + _16128) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_16153, (min(_16134 + 1.0, 7.0) + _16128) * 0.125), 0.0).xyz, vec3(-_16134));
            break;
        } while(false);
        highp vec3 _18145 = vec3(0.0);
        if (_7233)
        {
            vec3 _18144 = vec3(0.0);
            do
            {
                if (_11526)
                {
                    vec2 _16326 = vec2(atan(_7452.z, _7452.x), asin(clamp(_7452.y, -1.0, 1.0)));
                    highp vec2 hp_copy_16326 = _16326;
                    _18144 = textureLod(prefiltered_radiance_b, (hp_copy_16326 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _16345 = vec2(atan(_7452.z, _7452.x), asin(clamp(_7452.y, -1.0, 1.0)));
                highp vec2 hp_copy_16345 = _16345;
                highp vec2 _16350 = (hp_copy_16345 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _16257 = clamp(_16350.y, 0.00390625, 0.99609375);
                float _16263 = floor(0.0);
                highp float _16282 = _16350.x;
                _18144 = mix(textureLod(prefiltered_radiance_b, vec2(_16282, (_16263 + _16257) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_16282, (min(_16263 + 1.0, 7.0) + _16257) * 0.125), 0.0).xyz, vec3(-_16263));
                break;
            } while(false);
            _18145 = mix(_18143, _18144, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _18145 = _18143;
        }
        _18146 = _18145 * frag_info.environment_intensity;
    }
    else
    {
        _18146 = _FogInfo.color.xyz;
    }
    highp vec4 _7476 = vec4(min((_18137 + (_18141 * mix(1.0, _17705, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _17339, vec3(65504.0)), 1.0) * _18804;
    highp vec4 _18161 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _18161 = _7476;
            break;
        }
        int _16394 = int(_FogInfo.params0.x + 0.5);
        if (_16394 == 0)
        {
            _18161 = _7476;
            break;
        }
        highp float _18148 = 0.0;
        if (_9448)
        {
            _18148 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _18148 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_18148 > _FogInfo.params1.w))
        {
            _18161 = _7476;
            break;
        }
        float _18152 = 0.0;
        if (_16394 == 1)
        {
            _18152 = clamp((_18148 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _18153 = 0.0;
            if (_16394 == 2)
            {
                highp float _18151 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _18149 = vec3(0.0);
                    if (_9448)
                    {
                        _18149 = v_position - (view_info.camera_forward.xyz * _18148);
                    }
                    else
                    {
                        _18149 = v_position + v_viewvector;
                    }
                    highp float _16475 = -_FogInfo.params2.y;
                    highp float _16482 = _FogInfo.params1.x * exp(_16475 * (_18149.y - _FogInfo.params2.x));
                    highp float _16499 = _FogInfo.params2.y * (v_position.y - _18149.y);
                    highp float _18150 = 0.0;
                    if (abs(_16499) > 0.00124999997206032276153564453125)
                    {
                        _18150 = (_16482 - (_FogInfo.params1.x * exp(_16475 * (v_position.y - _FogInfo.params2.x)))) / _16499;
                    }
                    else
                    {
                        _18150 = _16482;
                    }
                    _18151 = _18150 * max(_18148 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _18151 = _FogInfo.params1.x * max(_18148 - _FogInfo.params1.y, 0.0);
                }
                _18153 = 1.0 - exp(-_18151);
            }
            else
            {
                highp float _16537 = _FogInfo.params1.x * max(_18148 - _FogInfo.params1.y, 0.0);
                _18153 = 1.0 - exp((-_16537) * _16537);
            }
            _18152 = _18153;
        }
        highp float _16549 = min(_18152, _FogInfo.params0.z);
        if (_16549 <= 0.0)
        {
            _18161 = _7476;
            break;
        }
        highp vec3 _16562 = mix(_FogInfo.color.xyz, _18146, vec3(_FogInfo.params0.w));
        bool _16565 = _FogInfo.sun.w > 0.5;
        bool _16571 = false;
        if (_16565)
        {
            _16571 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _16571 = _16565;
        }
        vec3 _18157 = vec3(0.0);
        if (_16571)
        {
            vec3 mp_copy_18154 = vec3(0.0);
            highp vec3 _18154 = vec3(0.0);
            if (_9448)
            {
                _18154 = -view_info.camera_forward.xyz;
            }
            else
            {
                _18154 = normalize(v_viewvector);
            }
            mp_copy_18154 = _18154;
            highp float _16587 = pow(max(dot(-mp_copy_18154, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_16587 = _16587;
            _18157 = _16562 + ((_FogInfo.sun.xyz * mp_copy_16587) * _FogInfo.params2.z);
        }
        else
        {
            _18157 = _16562;
        }
        highp float _16600 = _7476.w;
        float mp_copy_16600 = _16600;
        _18161 = vec4(mix(_7476.xyz, _18157 * mp_copy_16600, vec3(_16549)), _16600);
        break;
    } while(false);
    vec4 _18163 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _18163 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _18163 = _18161;
        break;
    } while(false);
    frag_color = _18163;
    float _18164 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _18164 = 1.0;
    }
    else
    {
        _18164 = abs(frag_info.fade);
    }
    frag_color *= _18164;
}

