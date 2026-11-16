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
    highp float _3831 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_3831 = _3831;
    vec3 _3835 = normalize(v_normal) * mp_copy_3831;
    vec4 _3877 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _3880 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9333 = vec2(0.0);
    if (_3880)
    {
        highp vec2 _9332 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9332 = v_texture_coords_1;
        }
        else
        {
            _9332 = v_texture_coords;
        }
        highp vec2 _4083 = _9332 * texture_transforms.base_color_transform.zw;
        highp float _4089 = _4083.x;
        highp float _4094 = _4083.y;
        _9333 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4089) + (texture_transforms.base_color_rotation.y * _4094), ((-texture_transforms.base_color_rotation.y) * _4089) + (texture_transforms.base_color_rotation.x * _4094));
    }
    else
    {
        _9333 = v_texture_coords;
    }
    vec4 _3894 = texture(base_color_texture, _9333);
    vec3 _3896 = _3894.xyz;
    float _9766 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3894.w * _3877.w) * frag_info.color.w);
    vec3 _9348 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9336 = vec2(0.0);
        if (_3880)
        {
            highp vec2 _9335 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9335 = v_texture_coords_1;
            }
            else
            {
                _9335 = v_texture_coords;
            }
            highp vec2 _4178 = _9335 * texture_transforms.normal_transform.zw;
            highp float _4184 = _4178.x;
            highp float _4189 = _4178.y;
            _9336 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4184) + (texture_transforms.normal_rotation.y * _4189), ((-texture_transforms.normal_rotation.y) * _4184) + (texture_transforms.normal_rotation.x * _4189));
        }
        else
        {
            _9336 = v_texture_coords;
        }
        vec3 _4234 = ((texture(normal_texture, _9336).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4238 = _4234.xy * vec2(frag_info.normal_scale);
        vec3 _9078 = _4234;
        _9078.x = _4238.x;
        _9078.y = _4238.y;
        highp vec3 _4244 = -v_viewvector;
        highp vec3 _4334 = dFdx(_4244);
        highp vec3 _4336 = dFdy(_4244);
        highp vec2 _4338 = dFdx(_9336);
        highp vec2 _4340 = dFdy(_9336);
        bvec2 _9768 = bvec2(length(_4338) == 0.0);
        highp vec2 _9769 = vec2(_9768.x ? vec2(1.0, 0.0).x : _4338.x, _9768.y ? vec2(1.0, 0.0).y : _4338.y);
        bvec2 _9770 = bvec2(length(_4340) == 0.0);
        highp vec2 _9771 = vec2(_9770.x ? vec2(0.0, 1.0).x : _4340.x, _9770.y ? vec2(0.0, 1.0).y : _4340.y);
        highp vec3 _4353 = cross(_4336, _3835);
        highp vec3 _4356 = cross(_3835, _4334);
        highp float _4381 = (dot(cross(_4334, _4336), _3835) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4384 = ((_4353 * _9769.x) + (_4356 * _9771.x)) * _4381;
        highp float _9343 = 0.0;
        if (gl_FrontFacing)
        {
            _9343 = -_4381;
        }
        else
        {
            _9343 = _4381;
        }
        highp vec3 _4394 = ((_4353 * _9769.y) + (_4356 * _9771.y)) * _9343;
        highp float _4403 = inversesqrt(max(max(dot(_4384, _4384), dot(_4394, _4394)), 9.9999996826552253889678874634872e-21));
        vec3 _4275 = v_tangent.xyz - (_3835 * dot(_3835, v_tangent.xyz));
        highp float _4278 = dot(_4275, _4275);
        bool _4280 = _4278 > 1.0000000133514319600180897396058e-10;
        bool _4287 = false;
        if (_4280)
        {
            _4287 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4287 = _4280;
        }
        mat3 _9346 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4287)
        {
            highp vec3 _4292 = _4275 * inversesqrt(_4278);
            _9346 = mat3(_4292, normalize(cross(_3835, _4292)) * sign(v_tangent.w), _3835);
        }
        else
        {
            _9346 = mat3(_4384 * _4403, _4394 * _4403, _3835);
        }
        _9348 = normalize(_9346 * _9078);
    }
    else
    {
        _9348 = _3835;
    }
    highp vec2 _9350 = vec2(0.0);
    if (_3880)
    {
        highp vec2 _9349 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9349 = v_texture_coords_1;
        }
        else
        {
            _9349 = v_texture_coords;
        }
        highp vec2 _4471 = _9349 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4477 = _4471.x;
        highp float _4482 = _4471.y;
        _9350 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4477) + (texture_transforms.metallic_roughness_rotation.y * _4482), ((-texture_transforms.metallic_roughness_rotation.y) * _4477) + (texture_transforms.metallic_roughness_rotation.x * _4482));
    }
    else
    {
        _9350 = v_texture_coords;
    }
    vec4 _3963 = texture(metallic_roughness_texture, _9350);
    float _3969 = clamp(_3963.z * frag_info.metallic_factor, 0.0, 1.0);
    float _3976 = clamp(_3963.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9352 = vec2(0.0);
    if (_3880)
    {
        highp vec2 _9351 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9351 = v_texture_coords_1;
        }
        else
        {
            _9351 = v_texture_coords;
        }
        highp vec2 _4542 = _9351 * texture_transforms.occlusion_transform.zw;
        highp float _4548 = _4542.x;
        highp float _4553 = _4542.y;
        _9352 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4548) + (texture_transforms.occlusion_rotation.y * _4553), ((-texture_transforms.occlusion_rotation.y) * _4548) + (texture_transforms.occlusion_rotation.x * _4553));
    }
    else
    {
        _9352 = v_texture_coords;
    }
    float _9353 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9353 = texture(occlusion_texture, _9352).x;
    }
    else
    {
        _9353 = 1.0;
    }
    float _4003 = 1.0 - ((1.0 - _9353) * frag_info.occlusion_strength);
    highp vec2 _9355 = vec2(0.0);
    if (_3880)
    {
        highp vec2 _9354 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9354 = v_texture_coords_1;
        }
        else
        {
            _9354 = v_texture_coords;
        }
        highp vec2 _4613 = _9354 * texture_transforms.emissive_transform.zw;
        highp float _4619 = _4613.x;
        highp float _4624 = _4613.y;
        _9355 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4619) + (texture_transforms.emissive_rotation.y * _4624), ((-texture_transforms.emissive_rotation.y) * _4619) + (texture_transforms.emissive_rotation.x * _4624));
    }
    else
    {
        _9355 = v_texture_coords;
    }
    vec3 _4022 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9371 = vec3(0.0);
    if (dot(abs(_4022), vec3(1.0)) > 0.0)
    {
        vec3 _4031 = texture(emissive_texture, _9355).xyz;
        _9371 = mix(_4031 * vec3(0.077399380505084991455078125), pow((_4031 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4031)) * _4022;
    }
    else
    {
        _9371 = vec3(0.0);
    }
    highp float hp_copy_9396 = 0.0;
    vec3 _4799 = vec4((mix(_3896 * vec3(0.077399380505084991455078125), pow((_3896 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3896)) * _3877.xyz) * frag_info.color.xyz, _9766).xyz;
    vec3 _5285 = dFdx(_9348);
    vec3 _5287 = dFdy(_9348);
    float _9396 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9396 = sqrt(clamp((_3976 * _3976) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5285, _5285), dot(_5287, _5287))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9396 = _3976;
    }
    hp_copy_9396 = _9396;
    float _9425 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9425 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9425 = _4003;
    }
    bool _4824 = frag_info.has_directional_light > 0.5;
    float _9397 = 0.0;
    vec3 _9439 = vec3(0.0);
    if (_4824)
    {
        highp vec3 _4830 = -normalize(frag_info.directional_light_direction.xyz);
        _9439 = _4830;
        _9397 = dot(_3835, _4830);
    }
    else
    {
        _9439 = vec3(0.0);
        _9397 = 0.0;
    }
    float _4837 = clamp(_9397 * 6.666666507720947265625, 0.0, 1.0);
    bool _4846 = false;
    if (_4824)
    {
        _4846 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _4846 = _4824;
    }
    float _9406 = 0.0;
    if (_4846 && (_4837 > 0.0))
    {
        int _5366 = int(frag_info.shadow_cascade_count);
        float _5561 = max(dot(_3835, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5564 = _5561 * _5561;
        highp vec3 _5584 = v_position + (_3835 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5564, 0.0)) / _5564, 8.0))));
        highp float _5372 = frag_info.directional_light_color.w * 0.5;
        float _5374 = frag_info.dielectric_f0.w;
        highp float hp_copy_5374 = _5374;
        float _9398 = 0.0;
        if (_5374 > 0.0)
        {
            _9398 = smoothstep(_5374 - max(frag_info.shadow_fade, hp_copy_5374 * 0.100000001490116119384765625), _5374, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9398 = 0.0;
        }
        float _9400 = 0.0;
        float _9402 = 0.0;
        if (_9398 < 1.0)
        {
            float _9401 = 0.0;
            float _9403 = 0.0;
            _9403 = 0.0;
            _9401 = 0.0;
            float _9627 = 0.0;
            float _9630 = 0.0;
            for (int _9399 = 0; _9399 < _5366; _9403 = _9630, _9401 = _9627, _9399++)
            {
                if (_9403 < 1.0)
                {
                    highp vec4 _5406 = vec4(_5584, 1.0);
                    highp vec4 _9558 = vec4(0.0);
                    highp float _9561 = 0.0;
                    if (_9399 == 0)
                    {
                        _9561 = frag_info.cascade_box_sizes.x;
                        _9558 = frag_info.light_space_matrix[0] * _5406;
                    }
                    else
                    {
                        highp vec4 _9559 = vec4(0.0);
                        highp float _9562 = 0.0;
                        if (_9399 == 1)
                        {
                            _9562 = frag_info.cascade_box_sizes.y;
                            _9559 = frag_info.light_space_matrix[1] * _5406;
                        }
                        else
                        {
                            highp vec4 _9560 = vec4(0.0);
                            highp float _9563 = 0.0;
                            if (_9399 == 2)
                            {
                                _9563 = frag_info.cascade_box_sizes.z;
                                _9560 = frag_info.light_space_matrix[2] * _5406;
                            }
                            else
                            {
                                _9563 = frag_info.cascade_box_sizes.w;
                                _9560 = frag_info.light_space_matrix[3] * _5406;
                            }
                            _9562 = _9563;
                            _9559 = _9560;
                        }
                        _9561 = _9562;
                        _9558 = _9559;
                    }
                    highp vec3 _5451 = _9558.xyz / vec3(_9558.w);
                    highp vec2 _5454 = _5451.xy * 0.5;
                    highp vec2 _5456 = _5454 + vec2(0.5);
                    highp float _5463 = max(frag_info.shadow_softness / _9561, frag_info.shadow_texel_size);
                    highp float _5465 = _5456.x;
                    bool _5467 = _5465 < _5463;
                    bool _5476 = false;
                    if (!_5467)
                    {
                        _5476 = _5465 > (1.0 - _5463);
                    }
                    else
                    {
                        _5476 = _5467;
                    }
                    bool _5484 = false;
                    if (!_5476)
                    {
                        _5484 = _5456.y < _5463;
                    }
                    else
                    {
                        _5484 = _5476;
                    }
                    bool _5493 = false;
                    if (!_5484)
                    {
                        _5493 = _5456.y > (1.0 - _5463);
                    }
                    else
                    {
                        _5493 = _5484;
                    }
                    bool _5500 = false;
                    if (!_5493)
                    {
                        _5500 = _5451.z < 0.0;
                    }
                    else
                    {
                        _5500 = _5493;
                    }
                    bool _5507 = false;
                    if (!_5500)
                    {
                        _5507 = _5451.z > 1.0;
                    }
                    else
                    {
                        _5507 = _5500;
                    }
                    float _9628 = 0.0;
                    float _9631 = 0.0;
                    if (!_5507)
                    {
                        highp vec2 _5600 = vec2(_5463);
                        highp vec2 _5605 = vec2(_5463 + max(_5372, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5613 = vec2(0.5) - _5454;
                        highp vec2 _5615 = smoothstep(_5600, _5605, _5456) * smoothstep(_5600, _5605, _5613);
                        float _9564 = 0.0;
                        if (_5372 > 0.0)
                        {
                            _9564 = _5615.x * _5615.y;
                        }
                        else
                        {
                            _9564 = 1.0;
                        }
                        float _5516 = min(_9564, 1.0 - _9403);
                        float _9629 = 0.0;
                        float _9632 = 0.0;
                        if (_5516 > 0.0)
                        {
                            highp float _5722 = _5451.z - (frag_info.shadow_bias / (7.0 * _9561));
                            highp float _5728 = 1.0 / (float(_5366) + frag_info.spot_shadow_params.x);
                            highp float _5730 = frag_info.directional_light_direction.w;
                            float mp_copy_5730 = _5730;
                            float _9589 = 0.0;
                            float _9590 = 0.0;
                            if ((step(0.5, mp_copy_5730) * (1.0 - step(1.5, mp_copy_5730))) < 0.5)
                            {
                                highp float _5747 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_5747 = _5747;
                                _9590 = sin(mp_copy_5747);
                                _9589 = cos(mp_copy_5747);
                            }
                            else
                            {
                                _9590 = 0.0;
                                _9589 = 1.0;
                            }
                            bool _5764 = _5730 > 2.5;
                            bool _9591 = false;
                            float _9595 = 0.0;
                            if ((_5730 < 1.5) || _5764)
                            {
                                highp vec2 _5922 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _5926 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _5927 = clamp(_5456, _5922, _5926);
                                highp float _5929 = float(_9399);
                                highp float _5936 = _5927.y;
                                highp vec2 _5937 = vec2((_5929 + _5927.x) * _5728, _5936);
                                _5937.y = 1.0 - _5936;
                                highp float _5949 = float(_5722 <= textureLod(shadow_map, _5937, 0.0).x);
                                float mp_copy_5949 = _5949;
                                float _5959 = (-1.0) * _9589;
                                float _5963 = (-1.0) * _9590;
                                highp vec2 _5987 = clamp(_5456 + (vec2(_5959 - _5963, _5963 + _5959) * _5463), _5922, _5926);
                                highp float _5996 = _5987.y;
                                highp vec2 _5997 = vec2((_5929 + _5987.x) * _5728, _5996);
                                _5997.y = 1.0 - _5996;
                                highp float _6009 = float(_5722 <= textureLod(shadow_map, _5997, 0.0).x);
                                float mp_copy_6009 = _6009;
                                highp vec2 _6047 = clamp(_5456 + (vec2(_9589 - _5963, _9590 + _5959) * _5463), _5922, _5926);
                                highp float _6056 = _6047.y;
                                highp vec2 _6057 = vec2((_5929 + _6047.x) * _5728, _6056);
                                _6057.y = 1.0 - _6056;
                                highp float _6069 = float(_5722 <= textureLod(shadow_map, _6057, 0.0).x);
                                float mp_copy_6069 = _6069;
                                highp vec2 _6107 = clamp(_5456 + (vec2(_5959 - _9590, _5963 + _9589) * _5463), _5922, _5926);
                                highp float _6116 = _6107.y;
                                highp vec2 _6117 = vec2((_5929 + _6107.x) * _5728, _6116);
                                _6117.y = 1.0 - _6116;
                                highp float _6129 = float(_5722 <= textureLod(shadow_map, _6117, 0.0).x);
                                float mp_copy_6129 = _6129;
                                highp vec2 _6167 = clamp(_5456 + (vec2(_9589 - _9590, _9590 + _9589) * _5463), _5922, _5926);
                                highp float _6176 = _6167.y;
                                highp vec2 _6177 = vec2((_5929 + _6167.x) * _5728, _6176);
                                _6177.y = 1.0 - _6176;
                                highp float _6189 = float(_5722 <= textureLod(shadow_map, _6177, 0.0).x);
                                float mp_copy_6189 = _6189;
                                float _5810 = (((mp_copy_5949 + mp_copy_6009) + mp_copy_6069) + mp_copy_6129) + mp_copy_6189;
                                _9595 = _5810 * 0.20000000298023223876953125;
                                _9591 = (_5810 < 0.5) || (_5810 > 4.5);
                            }
                            else
                            {
                                _9595 = 0.0;
                                _9591 = false;
                            }
                            float _9593 = 0.0;
                            if (_9591)
                            {
                                _9593 = _9595;
                            }
                            else
                            {
                                float _9594 = 0.0;
                                if (_5764)
                                {
                                    highp vec2 _6217 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _6221 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _6222 = clamp(_5456 + (vec2(-0.707099974155426025390625) * _5463), _6217, _6221);
                                    highp vec2 _6233 = (vec2(_6222.x, 1.0 - _6222.y) / _6217) - vec2(0.5);
                                    highp vec2 _6235 = floor(_6233);
                                    highp vec2 _6238 = _6233 - _6235;
                                    highp vec2 _6243 = (_6235 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _6245 = float(_9399);
                                    highp vec2 _6253 = vec2((_6245 + _6243.x) * _5728, _6243.y);
                                    highp float _6257 = frag_info.shadow_texel_size * _5728;
                                    highp vec2 _6260 = vec2(_6257, frag_info.shadow_texel_size);
                                    highp vec2 _6269 = vec2(_6257, 0.0);
                                    highp vec2 _6277 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _6306 = _6238.x;
                                    highp float _6315 = mix(mix(float(_5722 <= textureLod(shadow_map, _6253, 0.0).x), float(_5722 <= textureLod(shadow_map, _6253 + _6269, 0.0).x), _6306), mix(float(_5722 <= textureLod(shadow_map, _6253 + _6277, 0.0).x), float(_5722 <= textureLod(shadow_map, _6253 + _6260, 0.0).x), _6306), _6238.y);
                                    float mp_copy_6315 = _6315;
                                    highp vec2 _6349 = clamp(_5456 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _5463), _6217, _6221);
                                    highp vec2 _6360 = (vec2(_6349.x, 1.0 - _6349.y) / _6217) - vec2(0.5);
                                    highp vec2 _6362 = floor(_6360);
                                    highp vec2 _6365 = _6360 - _6362;
                                    highp vec2 _6370 = (_6362 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6380 = vec2((_6245 + _6370.x) * _5728, _6370.y);
                                    highp float _6433 = _6365.x;
                                    highp float _6442 = mix(mix(float(_5722 <= textureLod(shadow_map, _6380, 0.0).x), float(_5722 <= textureLod(shadow_map, _6380 + _6269, 0.0).x), _6433), mix(float(_5722 <= textureLod(shadow_map, _6380 + _6277, 0.0).x), float(_5722 <= textureLod(shadow_map, _6380 + _6260, 0.0).x), _6433), _6365.y);
                                    float mp_copy_6442 = _6442;
                                    highp vec2 _6476 = clamp(_5456 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _5463), _6217, _6221);
                                    highp vec2 _6487 = (vec2(_6476.x, 1.0 - _6476.y) / _6217) - vec2(0.5);
                                    highp vec2 _6489 = floor(_6487);
                                    highp vec2 _6492 = _6487 - _6489;
                                    highp vec2 _6497 = (_6489 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6507 = vec2((_6245 + _6497.x) * _5728, _6497.y);
                                    highp float _6560 = _6492.x;
                                    highp float _6569 = mix(mix(float(_5722 <= textureLod(shadow_map, _6507, 0.0).x), float(_5722 <= textureLod(shadow_map, _6507 + _6269, 0.0).x), _6560), mix(float(_5722 <= textureLod(shadow_map, _6507 + _6277, 0.0).x), float(_5722 <= textureLod(shadow_map, _6507 + _6260, 0.0).x), _6560), _6492.y);
                                    float mp_copy_6569 = _6569;
                                    highp vec2 _6603 = clamp(_5456 + (vec2(0.707099974155426025390625) * _5463), _6217, _6221);
                                    highp vec2 _6614 = (vec2(_6603.x, 1.0 - _6603.y) / _6217) - vec2(0.5);
                                    highp vec2 _6616 = floor(_6614);
                                    highp vec2 _6619 = _6614 - _6616;
                                    highp vec2 _6624 = (_6616 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _6634 = vec2((_6245 + _6624.x) * _5728, _6624.y);
                                    highp float _6687 = _6619.x;
                                    highp float _6696 = mix(mix(float(_5722 <= textureLod(shadow_map, _6634, 0.0).x), float(_5722 <= textureLod(shadow_map, _6634 + _6269, 0.0).x), _6687), mix(float(_5722 <= textureLod(shadow_map, _6634 + _6277, 0.0).x), float(_5722 <= textureLod(shadow_map, _6634 + _6260, 0.0).x), _6687), _6619.y);
                                    float mp_copy_6696 = _6696;
                                    _9594 = (((mp_copy_6315 + mp_copy_6442) + mp_copy_6569) + mp_copy_6696) * 0.25;
                                }
                                else
                                {
                                    _9594 = _9595;
                                }
                                _9593 = _9594;
                            }
                            bool _5859 = _9399 == (_5366 - 1);
                            bool _5865 = false;
                            if (_5859)
                            {
                                _5865 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _5865 = _5859;
                            }
                            float _9596 = 0.0;
                            if (_5865)
                            {
                                highp vec2 _5872 = vec2(frag_info.shadow_fade / _9561);
                                highp vec2 _5880 = smoothstep(vec2(0.0), _5872, _5456) * smoothstep(vec2(0.0), _5872, _5613);
                                _9596 = mix(1.0, _9593, _5880.x * _5880.y);
                            }
                            else
                            {
                                _9596 = _9593;
                            }
                            _9632 = _9403 + _5516;
                            _9629 = _9401 + (_5516 * _9596);
                        }
                        else
                        {
                            _9632 = _9403;
                            _9629 = _9401;
                        }
                        _9631 = _9632;
                        _9628 = _9629;
                    }
                    else
                    {
                        _9631 = _9403;
                        _9628 = _9401;
                    }
                    _9630 = _9631;
                    _9627 = _9628;
                }
                else
                {
                    _9630 = _9403;
                    _9627 = _9401;
                }
            }
            _9402 = _9403;
            _9400 = _9401;
        }
        else
        {
            _9402 = 0.0;
            _9400 = 0.0;
        }
        _9406 = mix(_9400 + (1.0 - _9402), 1.0, _9398);
    }
    else
    {
        _9406 = 1.0;
    }
    vec3 mp_copy_9407 = vec3(0.0);
    float _4859 = _4837 * _9406;
    bool _6704 = view_info.camera_forward.w > 0.5;
    highp vec3 _9407 = vec3(0.0);
    if (_6704)
    {
        _9407 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9407 = normalize(v_viewvector);
    }
    highp float _6748 = 0.0;
    mp_copy_9407 = _9407;
    vec3 _4868 = mix(frag_info.dielectric_f0.xyz, _4799, vec3(_3969));
    float _4872 = max(dot(_9348, _9407), 0.0);
    float _4876 = max(dot(_3835, _9407), 0.0);
    highp vec2 _9408 = vec2(0.0);
    do
    {
        _6748 = frag_info.punctual_dims.x;
        if (_6748 < 0.5)
        {
            _9408 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _6760 = v_position - frag_info.camera_position.xyz;
            highp float _6775 = dot(_6760, frag_info.camera_forward.xyz);
            highp float _6781 = max(_6775, 9.9999997473787516355514526367188e-05);
            highp vec2 _6884 = (vec3(dot(_6760, frag_info.camera_right.xyz), dot(_6760, frag_info.camera_up.xyz), _6781).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_6781, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _6899 = float(int(((((clamp(floor((log2(max(_6775 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_6884.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_6884.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9408 = vec2(textureLod(punctual_index, vec2((mod(_6899, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_6899 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9408 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _4885 = int(_9408.x + 0.5);
    mediump int _4889 = int(_9408.y + 0.5);
    highp vec3 _9453 = vec3(0.0);
    _9453 = vec3(0.0);
    highp vec3 _9719 = vec3(0.0);
    for (int _9409 = 0; _9409 < _4889; _9453 = _9719, _9409++)
    {
        highp float hp_copy_9510 = 0.0;
        highp float _6932 = float(_4885 + _9409);
        highp float _6963 = (float(int(textureLod(punctual_index, vec2((mod(_6932, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_6932 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _6748;
        highp vec4 _6967 = textureLod(punctual_lights, vec2(0.0625, _6963), 0.0);
        highp vec4 _6984 = textureLod(punctual_lights, vec2(0.1875, _6963), 0.0);
        highp float _4907 = _6967.w;
        highp vec3 _4909 = _6984.xyz;
        vec3 _9496 = vec3(0.0);
        highp vec3 _9507 = vec3(0.0);
        float _9510 = 0.0;
        if (_4907 < 0.5)
        {
            _9510 = _9396;
            _9507 = _4909;
            _9496 = -normalize(textureLod(punctual_lights, vec2(0.3125, _6963), 0.0).xyz);
        }
        else
        {
            highp vec3 _4917 = _6967.xyz - v_position;
            highp float _4920 = dot(_4917, _4917);
            highp float _4924 = inversesqrt(max(_4920, 9.9999999392252902907785028219223e-09));
            highp vec3 _4925 = _4917 * _4924;
            vec3 mp_copy_4925 = _4925;
            highp float _4927 = _6984.w;
            highp float _4932 = (_4920 * _4927) * _4927;
            highp float _4937 = clamp(1.0 - (_4932 * _4932), 0.0, 1.0);
            float mp_copy_4937 = _4937;
            if (_4937 <= 0.0)
            {
                _9719 = _9453;
                continue;
            }
            highp vec4 _7001 = textureLod(punctual_lights, vec2(0.4375, _6963), 0.0);
            highp float _4945 = _7001.w;
            float _9512 = 0.0;
            if (_4945 > 0.0)
            {
                highp float _4972 = (_9396 * _9396) + ((_4945 * 0.5) * _4924);
                float mp_copy_4972 = _4972;
                _9512 = sqrt(min(mp_copy_4972, 1.0));
            }
            else
            {
                _9512 = _9396;
            }
            highp vec3 _4979 = _4909 * ((mp_copy_4937 * mp_copy_4937) / max(pow(max(_4920, _4945 * _4945), _7001.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _9508 = vec3(0.0);
            if (_4907 > 1.5)
            {
                highp vec4 _7018 = textureLod(punctual_lights, vec2(0.3125, _6963), 0.0);
                highp float _4998 = clamp((dot(normalize(_7018.xyz), -mp_copy_4925) * _7018.w) + _7001.x, 0.0, 1.0);
                float mp_copy_4998 = _4998;
                highp vec3 _5003 = _4979 * (mp_copy_4998 * mp_copy_4998);
                if (_4998 <= 0.0)
                {
                    _9719 = _9453;
                    continue;
                }
                bool _5009 = _4998 > 0.0;
                bool _5015 = false;
                if (_5009)
                {
                    _5015 = _7001.y > (-0.5);
                }
                else
                {
                    _5015 = _5009;
                }
                bool _5021 = false;
                if (_5015)
                {
                    _5021 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5021 = _5015;
                }
                highp vec3 _9509 = vec3(0.0);
                if (_5021)
                {
                    float _9487 = 0.0;
                    do
                    {
                        highp vec4 _7130 = mat4(textureLod(punctual_lights, vec2(0.5625, _6963), 0.0), textureLod(punctual_lights, vec2(0.6875, _6963), 0.0), textureLod(punctual_lights, vec2(0.8125, _6963), 0.0), textureLod(punctual_lights, vec2(0.9375, _6963), 0.0)) * vec4(v_position + (_3835 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _7132 = _7130.w;
                        if (_7132 <= 0.0)
                        {
                            _9487 = 1.0;
                            break;
                        }
                        highp vec3 _7141 = _7130.xyz / vec3(_7132);
                        highp vec2 _7146 = (_7141.xy * 0.5) + vec2(0.5);
                        highp float _7148 = _7146.x;
                        bool _7149 = _7148 < 0.0;
                        bool _7156 = false;
                        if (!_7149)
                        {
                            _7156 = _7148 > 1.0;
                        }
                        else
                        {
                            _7156 = _7149;
                        }
                        bool _7163 = false;
                        if (!_7156)
                        {
                            _7163 = _7146.y < 0.0;
                        }
                        else
                        {
                            _7163 = _7156;
                        }
                        bool _7170 = false;
                        if (!_7163)
                        {
                            _7170 = _7146.y > 1.0;
                        }
                        else
                        {
                            _7170 = _7163;
                        }
                        bool _7177 = false;
                        if (!_7170)
                        {
                            _7177 = _7141.z < 0.0;
                        }
                        else
                        {
                            _7177 = _7170;
                        }
                        bool _7184 = false;
                        if (!_7177)
                        {
                            _7184 = _7141.z > 1.0;
                        }
                        else
                        {
                            _7184 = _7177;
                        }
                        if (_7184)
                        {
                            _9487 = 1.0;
                            break;
                        }
                        highp float _7191 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _7196 = frag_info.shadow_cascade_count + float(int(_7001.y + 0.5));
                        highp float _7201 = _7141.z - frag_info.spot_shadow_params.y;
                        highp float _7212 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_7212 = _7212;
                        highp vec2 _7219 = vec2(cos(mp_copy_7212), sin(mp_copy_7212)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _7221 = _7219.x;
                        highp float _7223 = _7219.y;
                        highp vec2 _7231 = vec2(_7221 - _7223, _7221 + _7223) * 0.707106769084930419921875;
                        highp float _7424 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7148, 0.0, 1.0)) / _7191, 1.0 - clamp(_7146.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7424 = _7424;
                        highp vec2 _7239 = _7146 + _7219;
                        highp float _7446 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7239.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7239.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7446 = _7446;
                        highp vec2 _7247 = _7146 - _7219;
                        highp float _7468 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7247.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7247.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7468 = _7468;
                        highp vec2 _7260 = _7146 + vec2(-_7223, _7221);
                        highp float _7490 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7260.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7260.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7490 = _7490;
                        highp vec2 _7273 = _7146 + vec2(_7223, -_7221);
                        highp float _7512 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7273.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7273.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7512 = _7512;
                        float _7278 = (((mp_copy_7424 + mp_copy_7446) + mp_copy_7468) + mp_copy_7490) + mp_copy_7512;
                        if ((_7278 < 0.5) || (_7278 > 4.5))
                        {
                            _9487 = _7278 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _7290 = _7146 + _7231;
                        highp float _7534 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7290.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7290.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7534 = _7534;
                        highp vec2 _7297 = _7146 - _7231;
                        highp float _7556 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7297.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7297.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7556 = _7556;
                        highp float _7305 = _7231.y;
                        highp float _7308 = _7231.x;
                        highp vec2 _7310 = _7146 + vec2(-_7305, _7308);
                        highp float _7578 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7310.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7310.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7578 = _7578;
                        highp vec2 _7323 = _7146 + vec2(_7305, -_7308);
                        highp float _7600 = float(_7201 <= textureLod(shadow_map, vec2((_7196 + clamp(_7323.x, 0.0, 1.0)) / _7191, 1.0 - clamp(_7323.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7600 = _7600;
                        _9487 = (_7278 + (((mp_copy_7534 + mp_copy_7556) + mp_copy_7578) + mp_copy_7600)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _9509 = _5003 * _9487;
                }
                else
                {
                    _9509 = _5003;
                }
                _9508 = _9509;
            }
            else
            {
                _9508 = _4979;
            }
            _9510 = _9512;
            _9507 = _9508;
            _9496 = _4925;
        }
        hp_copy_9510 = _9510;
        highp vec3 _9525 = vec3(0.0);
        highp vec3 _9526 = vec3(0.0);
        do
        {
            float _7683 = max(dot(_9348, _9496), 0.0);
            highp float hp_copy_7683 = _7683;
            if (_7683 <= 0.0)
            {
                _9526 = vec3(0.0);
                _9525 = vec3(0.0);
                break;
            }
            float _7689 = max(_4872, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_7689 = _7689;
            vec3 _7692 = _9496 + mp_copy_9407;
            float _7695 = dot(_7692, _7692);
            vec3 _9523 = vec3(0.0);
            vec3 _9524 = vec3(0.0);
            if (_7695 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _7703 = _7692 * inversesqrt(_7695);
                float _9522 = 0.0;
                do
                {
                    float _7760 = dot(_9348, _7703);
                    if (_7760 <= 0.0)
                    {
                        _9522 = 0.0;
                        break;
                    }
                    float _7767 = _9510 * _9510;
                    vec3 _7770 = cross(_9348, _7703);
                    float _7773 = _7760 * _7767;
                    float _7782 = _7767 / (dot(_7770, _7770) + (_7773 * _7773));
                    _9522 = min((_7782 * _7782) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _7820 = _4868 + ((vec3(1.0) - _4868) * pow(clamp(1.0 - max(dot(_7703, _9407), 0.0), 0.0, 1.0), 5.0));
                _9524 = (_7820 * min(_9522 * (0.5 / max(mix((2.0 * hp_copy_7683) * _7689, hp_copy_7683 + hp_copy_7689, hp_copy_9510 * hp_copy_9510), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9523 = _7820;
            }
            else
            {
                _9524 = vec3(0.0);
                _9523 = _4868;
            }
            _9526 = (_9524 * _9507) * _7683;
            _9525 = (((((vec3(1.0) - _9523) * (1.0 - _3969)) * _4799) * 0.3183098733425140380859375) * _9507) * _7683;
            break;
        } while(false);
        _9719 = _9453 + (_9525 + _9526);
    }
    bool _8044 = false;
    highp vec3 hp_copy_9410 = vec3(0.0);
    mat3 _5076 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5084 = _5076 * vec3(_9348.x, _9348.y, _9348.z);
    vec3 _5087 = _5076 * reflect(-mp_copy_9407, _9348);
    float _7863 = _5084.y;
    float _7870 = _5084.z;
    float _7877 = _5084.x;
    float _7885 = 1.09254801273345947265625 * _7877;
    vec3 _5090 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _7863))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _7870))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _7877))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_7885 * _7863))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _7863) * _7870))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _7870) * _7870) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_7885 * _7870))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_7877 * _7877) - (_7863 * _7863)))), vec3(0.0));
    highp vec3 hp_copy_5090 = _5090;
    vec3 _9410 = vec3(0.0);
    do
    {
        _8044 = radiance_layout_info.mip_layout > 0.5;
        if (_8044)
        {
            vec2 _8123 = vec2(atan(_5087.z, _5087.x), asin(clamp(_5087.y, -1.0, 1.0)));
            highp vec2 hp_copy_8123 = _8123;
            _9410 = textureLod(prefiltered_radiance, (hp_copy_8123 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9396, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8142 = vec2(atan(_5087.z, _5087.x), asin(clamp(_5087.y, -1.0, 1.0)));
        highp vec2 hp_copy_8142 = _8142;
        highp vec2 _8147 = (hp_copy_8142 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8054 = clamp(_8147.y, 0.00390625, 0.99609375);
        float _8058 = clamp(_9396, 0.0, 1.0) * 7.0;
        float _8060 = floor(_8058);
        highp float _8079 = _8147.x;
        _9410 = mix(textureLod(prefiltered_radiance, vec2(_8079, (_8060 + _8054) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8079, (min(_8060 + 1.0, 7.0) + _8054) * 0.125), 0.0).xyz, vec3(_8058 - _8060));
        break;
    } while(false);
    hp_copy_9410 = _9410;
    highp vec3 _9416 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9411 = vec3(0.0);
        vec3 _9411 = vec3(0.0);
        do
        {
            if (_8044)
            {
                vec2 _8252 = vec2(atan(_5087.z, _5087.x), asin(clamp(_5087.y, -1.0, 1.0)));
                highp vec2 hp_copy_8252 = _8252;
                _9411 = textureLod(prefiltered_radiance_b, (hp_copy_8252 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9396, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8271 = vec2(atan(_5087.z, _5087.x), asin(clamp(_5087.y, -1.0, 1.0)));
            highp vec2 hp_copy_8271 = _8271;
            highp vec2 _8276 = (hp_copy_8271 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8183 = clamp(_8276.y, 0.00390625, 0.99609375);
            float _8187 = clamp(_9396, 0.0, 1.0) * 7.0;
            float _8189 = floor(_8187);
            highp float _8208 = _8276.x;
            _9411 = mix(textureLod(prefiltered_radiance_b, vec2(_8208, (_8189 + _8183) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_8208, (min(_8189 + 1.0, 7.0) + _8183) * 0.125), 0.0).xyz, vec3(_8187 - _8189));
            break;
        } while(false);
        hp_copy_9411 = _9411;
        _9416 = hp_copy_9410 + hp_copy_9411;
    }
    else
    {
        _9416 = _9410;
    }
    float _5105 = frag_info.environment_intensity;
    highp float hp_copy_5105 = _5105;
    vec2 _5118 = clamp(vec2(_4876, _9396), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5120 = texture(brdf_lut, vec2(_5118.x * 0.3333333432674407958984375, _5118.y));
    float _5124 = _5120.x;
    float _5127 = _5120.y;
    vec3 _5129 = ((_4868 + ((max(vec3(1.0 - _9396), _4868) - _4868) * pow(clamp(1.0 - _4876, 0.0, 1.0), 5.0))) * _5124) + vec3(_5127);
    float _5135 = 1.0 - (_5124 + _5127);
    vec3 _5139 = vec3(1.0) - _4868;
    vec3 _5142 = _4868 + (_5139 * vec3(0.0476190485060214996337890625));
    vec3 _5153 = ((_5129 * _5135) * _5142) / (vec3(1.0) - (_5142 * _5135));
    float _5156 = 1.0 - _3969;
    float _9430 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9430 = clamp((pow(_4872 + _9425, exp2(((-16.0) * _9396) - 1.0)) - 1.0) + _9425, 0.0, 1.0);
    }
    else
    {
        _9430 = _9425;
    }
    highp vec3 _9463 = vec3(0.0);
    if (_4824)
    {
        highp vec3 _9447 = vec3(0.0);
        highp vec3 _9448 = vec3(0.0);
        do
        {
            float _8365 = max(dot(_9348, _9439), 0.0);
            highp float hp_copy_8365 = _8365;
            if (_8365 <= 0.0)
            {
                _9448 = vec3(0.0);
                _9447 = vec3(0.0);
                break;
            }
            float _8371 = max(_4872, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8371 = _8371;
            vec3 _8374 = _9439 + mp_copy_9407;
            float _8377 = dot(_8374, _8374);
            vec3 _9445 = vec3(0.0);
            vec3 _9446 = vec3(0.0);
            if (_8377 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8385 = _8374 * inversesqrt(_8377);
                float _9444 = 0.0;
                do
                {
                    float _8442 = dot(_9348, _8385);
                    if (_8442 <= 0.0)
                    {
                        _9444 = 0.0;
                        break;
                    }
                    float _8449 = _9396 * _9396;
                    vec3 _8452 = cross(_9348, _8385);
                    float _8455 = _8442 * _8449;
                    float _8464 = _8449 / (dot(_8452, _8452) + (_8455 * _8455));
                    _9444 = min((_8464 * _8464) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8502 = _4868 + (_5139 * pow(clamp(1.0 - max(dot(_8385, _9407), 0.0), 0.0, 1.0), 5.0));
                _9446 = (_8502 * min(_9444 * (0.5 / max(mix((2.0 * hp_copy_8365) * _8371, hp_copy_8365 + hp_copy_8371, hp_copy_9396 * hp_copy_9396), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9445 = _8502;
            }
            else
            {
                _9446 = vec3(0.0);
                _9445 = _4868;
            }
            _9448 = (_9446 * frag_info.directional_light_color.xyz) * _8365;
            _9447 = (((((vec3(1.0) - _9445) * _5156) * _4799) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8365;
            break;
        } while(false);
        _9463 = _9453 + ((_9447 + _9448) * _4859);
    }
    else
    {
        _9463 = _9453;
    }
    bool _5247 = _FogInfo.params0.y > 0.5;
    bool _5253 = false;
    if (_5247)
    {
        _5253 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5253 = _5247;
    }
    highp vec3 _9466 = vec3(0.0);
    if (_5253)
    {
        vec3 mp_copy_9464 = vec3(0.0);
        highp vec3 _9464 = vec3(0.0);
        if (_6704)
        {
            _9464 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9464 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9465 = vec3(0.0);
        mp_copy_9464 = _9464;
        vec3 _5258 = _5076 * (-mp_copy_9464);
        vec3 _9465 = vec3(0.0);
        do
        {
            if (_8044)
            {
                vec2 _8624 = vec2(atan(_5258.z, _5258.x), asin(clamp(_5258.y, -1.0, 1.0)));
                highp vec2 hp_copy_8624 = _8624;
                _9465 = textureLod(prefiltered_radiance, (hp_copy_8624 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _8643 = vec2(atan(_5258.z, _5258.x), asin(clamp(_5258.y, -1.0, 1.0)));
            highp vec2 hp_copy_8643 = _8643;
            highp vec2 _8648 = (hp_copy_8643 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8555 = clamp(_8648.y, 0.00390625, 0.99609375);
            float _8561 = floor(0.0);
            highp float _8580 = _8648.x;
            _9465 = mix(textureLod(prefiltered_radiance, vec2(_8580, (_8561 + _8555) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8580, (min(_8561 + 1.0, 7.0) + _8555) * 0.125), 0.0).xyz, vec3(-_8561));
            break;
        } while(false);
        hp_copy_9465 = _9465;
        _9466 = hp_copy_9465 * hp_copy_5105;
    }
    else
    {
        _9466 = _FogInfo.color.xyz;
    }
    highp vec4 _5273 = vec4(min(((((((_5153 + ((_4799 * _5156) * ((vec3(1.0) - _5129) - _5153))) * (hp_copy_5090 * hp_copy_5105)) * vec3(_4003)) + (((_5129 * (_9416 * _5105)) * 1.0) * _9430)) * mix(1.0, _4859, frag_info.radiance_blend.y)) + (_9463 * mix(1.0, _9425, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9371, vec3(65504.0)), 1.0) * _9766;
    highp vec4 _9481 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9481 = _5273;
            break;
        }
        int _8692 = int(_FogInfo.params0.x + 0.5);
        if (_8692 == 0)
        {
            _9481 = _5273;
            break;
        }
        highp float _9468 = 0.0;
        if (_6704)
        {
            _9468 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9468 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9468 > _FogInfo.params1.w))
        {
            _9481 = _5273;
            break;
        }
        float _9472 = 0.0;
        if (_8692 == 1)
        {
            _9472 = clamp((_9468 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9473 = 0.0;
            if (_8692 == 2)
            {
                highp float _9471 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9469 = vec3(0.0);
                    if (_6704)
                    {
                        _9469 = v_position - (view_info.camera_forward.xyz * _9468);
                    }
                    else
                    {
                        _9469 = v_position + v_viewvector;
                    }
                    highp float _8783 = -_FogInfo.params2.y;
                    highp float _8790 = _FogInfo.params1.x * exp(_8783 * (_9469.y - _FogInfo.params2.x));
                    highp float _8807 = _FogInfo.params2.y * (v_position.y - _9469.y);
                    highp float _9470 = 0.0;
                    if (abs(_8807) > 0.00124999997206032276153564453125)
                    {
                        _9470 = (_8790 - (_FogInfo.params1.x * exp(_8783 * (v_position.y - _FogInfo.params2.x)))) / _8807;
                    }
                    else
                    {
                        _9470 = _8790;
                    }
                    _9471 = _9470 * max(_9468 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9471 = _FogInfo.params1.x * max(_9468 - _FogInfo.params1.y, 0.0);
                }
                _9473 = 1.0 - exp(-_9471);
            }
            else
            {
                highp float _8745 = _FogInfo.params1.x * max(_9468 - _FogInfo.params1.y, 0.0);
                _9473 = 1.0 - exp((-_8745) * _8745);
            }
            _9472 = _9473;
        }
        highp float _8847 = min(_9472, _FogInfo.params0.z);
        if (_8847 <= 0.0)
        {
            _9481 = _5273;
            break;
        }
        highp vec3 _8860 = mix(_FogInfo.color.xyz, _9466, vec3(_FogInfo.params0.w));
        bool _8863 = _FogInfo.sun.w > 0.5;
        bool _8869 = false;
        if (_8863)
        {
            _8869 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _8869 = _8863;
        }
        vec3 _9477 = vec3(0.0);
        if (_8869)
        {
            vec3 mp_copy_9474 = vec3(0.0);
            highp vec3 _9474 = vec3(0.0);
            if (_6704)
            {
                _9474 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9474 = normalize(v_viewvector);
            }
            mp_copy_9474 = _9474;
            highp float _8885 = pow(max(dot(-mp_copy_9474, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_8885 = _8885;
            _9477 = _8860 + ((_FogInfo.sun.xyz * mp_copy_8885) * _FogInfo.params2.z);
        }
        else
        {
            _9477 = _8860;
        }
        highp float _8898 = _5273.w;
        float mp_copy_8898 = _8898;
        _9481 = vec4(mix(_5273.xyz, _9477 * mp_copy_8898, vec3(_8847)), _8898);
        break;
    } while(false);
    vec4 _9483 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9483 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9483 = _9481;
        break;
    } while(false);
    frag_color = _9483;
    float _9484 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9484 = 1.0;
    }
    else
    {
        _9484 = abs(frag_info.fade);
    }
    frag_color *= _9484;
}

