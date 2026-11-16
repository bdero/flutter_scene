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
    highp float _4040 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4040 = _4040;
    vec3 _4044 = normalize(v_normal) * mp_copy_4040;
    vec4 _4086 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4089 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _9414 = vec2(0.0);
    if (_4089)
    {
        highp vec2 _9413 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _9413 = v_texture_coords_1;
        }
        else
        {
            _9413 = v_texture_coords;
        }
        highp vec2 _4292 = _9413 * texture_transforms.base_color_transform.zw;
        highp float _4298 = _4292.x;
        highp float _4303 = _4292.y;
        _9414 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4298) + (texture_transforms.base_color_rotation.y * _4303), ((-texture_transforms.base_color_rotation.y) * _4298) + (texture_transforms.base_color_rotation.x * _4303));
    }
    else
    {
        _9414 = v_texture_coords;
    }
    vec4 _4103 = texture(base_color_texture, _9414);
    vec3 _4105 = _4103.xyz;
    float _9927 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4103.w * _4086.w) * frag_info.color.w);
    vec3 _9429 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _9417 = vec2(0.0);
        if (_4089)
        {
            highp vec2 _9416 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _9416 = v_texture_coords_1;
            }
            else
            {
                _9416 = v_texture_coords;
            }
            highp vec2 _4387 = _9416 * texture_transforms.normal_transform.zw;
            highp float _4393 = _4387.x;
            highp float _4398 = _4387.y;
            _9417 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4393) + (texture_transforms.normal_rotation.y * _4398), ((-texture_transforms.normal_rotation.y) * _4393) + (texture_transforms.normal_rotation.x * _4398));
        }
        else
        {
            _9417 = v_texture_coords;
        }
        vec3 _4443 = ((texture(normal_texture, _9417).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4447 = _4443.xy * vec2(frag_info.normal_scale);
        vec3 _9177 = _4443;
        _9177.x = _4447.x;
        _9177.y = _4447.y;
        highp vec3 _4453 = -v_viewvector;
        highp vec3 _4543 = dFdx(_4453);
        highp vec3 _4545 = dFdy(_4453);
        highp vec2 _4547 = dFdx(_9417);
        highp vec2 _4549 = dFdy(_9417);
        bvec2 _9929 = bvec2(length(_4547) == 0.0);
        highp vec2 _9930 = vec2(_9929.x ? vec2(1.0, 0.0).x : _4547.x, _9929.y ? vec2(1.0, 0.0).y : _4547.y);
        bvec2 _9931 = bvec2(length(_4549) == 0.0);
        highp vec2 _9932 = vec2(_9931.x ? vec2(0.0, 1.0).x : _4549.x, _9931.y ? vec2(0.0, 1.0).y : _4549.y);
        highp vec3 _4562 = cross(_4545, _4044);
        highp vec3 _4565 = cross(_4044, _4543);
        highp float _4590 = (dot(cross(_4543, _4545), _4044) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4593 = ((_4562 * _9930.x) + (_4565 * _9932.x)) * _4590;
        highp float _9424 = 0.0;
        if (gl_FrontFacing)
        {
            _9424 = -_4590;
        }
        else
        {
            _9424 = _4590;
        }
        highp vec3 _4603 = ((_4562 * _9930.y) + (_4565 * _9932.y)) * _9424;
        highp float _4612 = inversesqrt(max(max(dot(_4593, _4593), dot(_4603, _4603)), 9.9999996826552253889678874634872e-21));
        vec3 _4484 = v_tangent.xyz - (_4044 * dot(_4044, v_tangent.xyz));
        highp float _4487 = dot(_4484, _4484);
        bool _4489 = _4487 > 1.0000000133514319600180897396058e-10;
        bool _4496 = false;
        if (_4489)
        {
            _4496 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4496 = _4489;
        }
        mat3 _9427 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4496)
        {
            highp vec3 _4501 = _4484 * inversesqrt(_4487);
            _9427 = mat3(_4501, normalize(cross(_4044, _4501)) * sign(v_tangent.w), _4044);
        }
        else
        {
            _9427 = mat3(_4593 * _4612, _4603 * _4612, _4044);
        }
        _9429 = normalize(_9427 * _9177);
    }
    else
    {
        _9429 = _4044;
    }
    highp vec2 _9431 = vec2(0.0);
    if (_4089)
    {
        highp vec2 _9430 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _9430 = v_texture_coords_1;
        }
        else
        {
            _9430 = v_texture_coords;
        }
        highp vec2 _4680 = _9430 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4686 = _4680.x;
        highp float _4691 = _4680.y;
        _9431 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4686) + (texture_transforms.metallic_roughness_rotation.y * _4691), ((-texture_transforms.metallic_roughness_rotation.y) * _4686) + (texture_transforms.metallic_roughness_rotation.x * _4691));
    }
    else
    {
        _9431 = v_texture_coords;
    }
    vec4 _4172 = texture(metallic_roughness_texture, _9431);
    float _4178 = clamp(_4172.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4185 = clamp(_4172.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _9433 = vec2(0.0);
    if (_4089)
    {
        highp vec2 _9432 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _9432 = v_texture_coords_1;
        }
        else
        {
            _9432 = v_texture_coords;
        }
        highp vec2 _4751 = _9432 * texture_transforms.occlusion_transform.zw;
        highp float _4757 = _4751.x;
        highp float _4762 = _4751.y;
        _9433 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4757) + (texture_transforms.occlusion_rotation.y * _4762), ((-texture_transforms.occlusion_rotation.y) * _4757) + (texture_transforms.occlusion_rotation.x * _4762));
    }
    else
    {
        _9433 = v_texture_coords;
    }
    float _9434 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _9434 = texture(occlusion_texture, _9433).x;
    }
    else
    {
        _9434 = 1.0;
    }
    float _4212 = 1.0 - ((1.0 - _9434) * frag_info.occlusion_strength);
    highp vec2 _9436 = vec2(0.0);
    if (_4089)
    {
        highp vec2 _9435 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _9435 = v_texture_coords_1;
        }
        else
        {
            _9435 = v_texture_coords;
        }
        highp vec2 _4822 = _9435 * texture_transforms.emissive_transform.zw;
        highp float _4828 = _4822.x;
        highp float _4833 = _4822.y;
        _9436 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4828) + (texture_transforms.emissive_rotation.y * _4833), ((-texture_transforms.emissive_rotation.y) * _4828) + (texture_transforms.emissive_rotation.x * _4833));
    }
    else
    {
        _9436 = v_texture_coords;
    }
    vec3 _4231 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _9452 = vec3(0.0);
    if (dot(abs(_4231), vec3(1.0)) > 0.0)
    {
        vec3 _4240 = texture(emissive_texture, _9436).xyz;
        _9452 = mix(_4240 * vec3(0.077399380505084991455078125), pow((_4240 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4240)) * _4231;
    }
    else
    {
        _9452 = vec3(0.0);
    }
    highp float hp_copy_9477 = 0.0;
    vec3 _5008 = vec4((mix(_4105 * vec3(0.077399380505084991455078125), pow((_4105 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4105)) * _4086.xyz) * frag_info.color.xyz, _9927).xyz;
    vec3 _5494 = dFdx(_9429);
    vec3 _5496 = dFdy(_9429);
    float _9477 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _9477 = sqrt(clamp((_4185 * _4185) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5494, _5494), dot(_5496, _5496))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _9477 = _4185;
    }
    hp_copy_9477 = _9477;
    float _9506 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _9506 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _9506 = _4212;
    }
    bool _5033 = frag_info.has_directional_light > 0.5;
    float _9478 = 0.0;
    vec3 _9520 = vec3(0.0);
    if (_5033)
    {
        highp vec3 _5039 = -normalize(frag_info.directional_light_direction.xyz);
        _9520 = _5039;
        _9478 = dot(_4044, _5039);
    }
    else
    {
        _9520 = vec3(0.0);
        _9478 = 0.0;
    }
    float _5046 = clamp(_9478 * 6.666666507720947265625, 0.0, 1.0);
    bool _5055 = false;
    if (_5033)
    {
        _5055 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5055 = _5033;
    }
    float _9487 = 0.0;
    if (_5055 && (_5046 > 0.0))
    {
        int _5575 = int(frag_info.shadow_cascade_count);
        float _5770 = max(dot(_4044, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5773 = _5770 * _5770;
        highp vec3 _5793 = v_position + (_4044 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5773, 0.0)) / _5773, 8.0))));
        highp float _5581 = frag_info.directional_light_color.w * 0.5;
        float _5583 = frag_info.dielectric_f0.w;
        highp float hp_copy_5583 = _5583;
        float _9479 = 0.0;
        if (_5583 > 0.0)
        {
            _9479 = smoothstep(_5583 - max(frag_info.shadow_fade, hp_copy_5583 * 0.100000001490116119384765625), _5583, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _9479 = 0.0;
        }
        float _9481 = 0.0;
        float _9483 = 0.0;
        if (_9479 < 1.0)
        {
            float _9482 = 0.0;
            float _9484 = 0.0;
            _9484 = 0.0;
            _9482 = 0.0;
            float _9763 = 0.0;
            float _9766 = 0.0;
            for (int _9480 = 0; _9480 < _5575; _9484 = _9766, _9482 = _9763, _9480++)
            {
                if (_9484 < 1.0)
                {
                    highp vec4 _5615 = vec4(_5793, 1.0);
                    highp vec4 _9639 = vec4(0.0);
                    highp float _9642 = 0.0;
                    if (_9480 == 0)
                    {
                        _9642 = frag_info.cascade_box_sizes.x;
                        _9639 = frag_info.light_space_matrix[0] * _5615;
                    }
                    else
                    {
                        highp vec4 _9640 = vec4(0.0);
                        highp float _9643 = 0.0;
                        if (_9480 == 1)
                        {
                            _9643 = frag_info.cascade_box_sizes.y;
                            _9640 = frag_info.light_space_matrix[1] * _5615;
                        }
                        else
                        {
                            highp vec4 _9641 = vec4(0.0);
                            highp float _9644 = 0.0;
                            if (_9480 == 2)
                            {
                                _9644 = frag_info.cascade_box_sizes.z;
                                _9641 = frag_info.light_space_matrix[2] * _5615;
                            }
                            else
                            {
                                _9644 = frag_info.cascade_box_sizes.w;
                                _9641 = frag_info.light_space_matrix[3] * _5615;
                            }
                            _9643 = _9644;
                            _9640 = _9641;
                        }
                        _9642 = _9643;
                        _9639 = _9640;
                    }
                    highp vec3 _5660 = _9639.xyz / vec3(_9639.w);
                    highp vec2 _5663 = _5660.xy * 0.5;
                    highp vec2 _5665 = _5663 + vec2(0.5);
                    highp float _5672 = max(frag_info.shadow_softness / _9642, frag_info.shadow_texel_size);
                    highp float _5674 = _5665.x;
                    bool _5676 = _5674 < _5672;
                    bool _5685 = false;
                    if (!_5676)
                    {
                        _5685 = _5674 > (1.0 - _5672);
                    }
                    else
                    {
                        _5685 = _5676;
                    }
                    bool _5693 = false;
                    if (!_5685)
                    {
                        _5693 = _5665.y < _5672;
                    }
                    else
                    {
                        _5693 = _5685;
                    }
                    bool _5702 = false;
                    if (!_5693)
                    {
                        _5702 = _5665.y > (1.0 - _5672);
                    }
                    else
                    {
                        _5702 = _5693;
                    }
                    bool _5709 = false;
                    if (!_5702)
                    {
                        _5709 = _5660.z < 0.0;
                    }
                    else
                    {
                        _5709 = _5702;
                    }
                    bool _5716 = false;
                    if (!_5709)
                    {
                        _5716 = _5660.z > 1.0;
                    }
                    else
                    {
                        _5716 = _5709;
                    }
                    float _9764 = 0.0;
                    float _9767 = 0.0;
                    if (!_5716)
                    {
                        highp vec2 _5809 = vec2(_5672);
                        highp vec2 _5814 = vec2(_5672 + max(_5581, 9.9999997473787516355514526367188e-05));
                        highp vec2 _5822 = vec2(0.5) - _5663;
                        highp vec2 _5824 = smoothstep(_5809, _5814, _5665) * smoothstep(_5809, _5814, _5822);
                        float _9645 = 0.0;
                        if (_5581 > 0.0)
                        {
                            _9645 = _5824.x * _5824.y;
                        }
                        else
                        {
                            _9645 = 1.0;
                        }
                        float _5725 = min(_9645, 1.0 - _9484);
                        float _9765 = 0.0;
                        float _9768 = 0.0;
                        if (_5725 > 0.0)
                        {
                            highp float _5938 = _5660.z - (frag_info.shadow_bias / (7.0 * _9642));
                            highp float _5944 = 1.0 / (float(_5575) + frag_info.spot_shadow_params.x);
                            highp float _5946 = frag_info.directional_light_direction.w;
                            float mp_copy_5946 = _5946;
                            float _5952 = step(0.5, mp_copy_5946) * (1.0 - step(1.5, mp_copy_5946));
                            float _9675 = 0.0;
                            float _9679 = 0.0;
                            if (_5952 < 0.5)
                            {
                                highp float _5963 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_5963 = _5963;
                                _9679 = sin(mp_copy_5963);
                                _9675 = cos(mp_copy_5963);
                            }
                            else
                            {
                                _9679 = 0.0;
                                _9675 = 1.0;
                            }
                            highp float _9682 = 0.0;
                            if ((_5946 > 1.5) && (_5946 < 2.5))
                            {
                                highp float _5987 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _5992 = max(_5987 * _5938, frag_info.shadow_texel_size);
                                float _9671 = 0.0;
                                highp float _9672 = 0.0;
                                _9672 = 0.0;
                                _9671 = 0.0;
                                highp float _6014 = 0.0;
                                float _6017 = 0.0;
                                for (int _9670 = 0; _9670 < 9; _9672 = _6014, _9671 = _6017, _9670++)
                                {
                                    vec2 _9757 = vec2(0.0);
                                    do
                                    {
                                        if (_9670 == 0)
                                        {
                                            _9757 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_9670 == 1)
                                        {
                                            _9757 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_9670 == 2)
                                        {
                                            _9757 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_9670 == 3)
                                        {
                                            _9757 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_9670 == 4)
                                        {
                                            _9757 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_9670 == 5)
                                        {
                                            _9757 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_9670 == 6)
                                        {
                                            _9757 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_9670 == 7)
                                        {
                                            _9757 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_9670 == 8)
                                        {
                                            _9757 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_9670 == 9)
                                        {
                                            _9757 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_9670 == 10)
                                        {
                                            _9757 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_9670 == 11)
                                        {
                                            _9757 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_9670 == 12)
                                        {
                                            _9757 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_9670 == 13)
                                        {
                                            _9757 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_9670 == 14)
                                        {
                                            _9757 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_9670 == 15)
                                        {
                                            _9757 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _9757 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6287 = clamp(_5665 + (vec2((_9757.x * _9675) - (_9757.y * _9679), (_9757.x * _9679) + (_9757.y * _9675)) * _5992), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6296 = _6287.y;
                                    highp vec2 _6297 = vec2((float(_9480) + _6287.x) * _5944, _6296);
                                    _6297.y = 1.0 - _6296;
                                    highp vec4 _6304 = textureLod(shadow_map, _6297, 0.0);
                                    highp float _6305 = _6304.x;
                                    highp float _6009 = step(_6305, _5938);
                                    float mp_copy_6009 = _6009;
                                    _6014 = _9672 + (_6305 * _6009);
                                    _6017 = _9671 + mp_copy_6009;
                                }
                                highp float _9673 = 0.0;
                                if (_9671 > 0.0)
                                {
                                    _9673 = _9672 / _9671;
                                }
                                else
                                {
                                    _9673 = _5938;
                                }
                                _9682 = clamp(_5987 * max(_5938 - _9673, 0.0), frag_info.shadow_texel_size, _5672);
                            }
                            else
                            {
                                _9682 = _5672;
                            }
                            bool _9683 = false;
                            float _9707 = 0.0;
                            if ((_5946 < 1.5) || (_5946 > 2.5))
                            {
                                highp vec2 _6338 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6342 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6343 = clamp(_5665, _6338, _6342);
                                highp float _6345 = float(_9480);
                                highp float _6352 = _6343.y;
                                highp vec2 _6353 = vec2((_6345 + _6343.x) * _5944, _6352);
                                _6353.y = 1.0 - _6352;
                                highp float _6365 = float(_5938 <= textureLod(shadow_map, _6353, 0.0).x);
                                float mp_copy_6365 = _6365;
                                float _6375 = (-1.0) * _9675;
                                float _6379 = (-1.0) * _9679;
                                highp vec2 _6403 = clamp(_5665 + (vec2(_6375 - _6379, _6379 + _6375) * _9682), _6338, _6342);
                                highp float _6412 = _6403.y;
                                highp vec2 _6413 = vec2((_6345 + _6403.x) * _5944, _6412);
                                _6413.y = 1.0 - _6412;
                                highp float _6425 = float(_5938 <= textureLod(shadow_map, _6413, 0.0).x);
                                float mp_copy_6425 = _6425;
                                highp vec2 _6463 = clamp(_5665 + (vec2(_9675 - _6379, _9679 + _6375) * _9682), _6338, _6342);
                                highp float _6472 = _6463.y;
                                highp vec2 _6473 = vec2((_6345 + _6463.x) * _5944, _6472);
                                _6473.y = 1.0 - _6472;
                                highp float _6485 = float(_5938 <= textureLod(shadow_map, _6473, 0.0).x);
                                float mp_copy_6485 = _6485;
                                highp vec2 _6523 = clamp(_5665 + (vec2(_6375 - _9679, _6379 + _9675) * _9682), _6338, _6342);
                                highp float _6532 = _6523.y;
                                highp vec2 _6533 = vec2((_6345 + _6523.x) * _5944, _6532);
                                _6533.y = 1.0 - _6532;
                                highp float _6545 = float(_5938 <= textureLod(shadow_map, _6533, 0.0).x);
                                float mp_copy_6545 = _6545;
                                highp vec2 _6583 = clamp(_5665 + (vec2(_9675 - _9679, _9679 + _9675) * _9682), _6338, _6342);
                                highp float _6592 = _6583.y;
                                highp vec2 _6593 = vec2((_6345 + _6583.x) * _5944, _6592);
                                _6593.y = 1.0 - _6592;
                                highp float _6605 = float(_5938 <= textureLod(shadow_map, _6593, 0.0).x);
                                float mp_copy_6605 = _6605;
                                float _6094 = (((mp_copy_6365 + mp_copy_6425) + mp_copy_6485) + mp_copy_6545) + mp_copy_6605;
                                _9707 = _6094 * 0.20000000298023223876953125;
                                _9683 = (_6094 < 0.5) || (_6094 > 4.5);
                            }
                            else
                            {
                                _9707 = 0.0;
                                _9683 = false;
                            }
                            float _9706 = 0.0;
                            if (_9683)
                            {
                                _9706 = _9707;
                            }
                            else
                            {
                                int _6107 = (_5952 > 0.5) ? 17 : 16;
                                float _9702 = 0.0;
                                _9702 = 0.0;
                                float _6135 = 0.0;
                                for (int _9684 = 0; _9684 < 17; _9702 = _6135, _9684++)
                                {
                                    if (_9684 >= _6107)
                                    {
                                        break;
                                    }
                                    vec2 _9685 = vec2(0.0);
                                    do
                                    {
                                        if (_9684 == 0)
                                        {
                                            _9685 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_9684 == 1)
                                        {
                                            _9685 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_9684 == 2)
                                        {
                                            _9685 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_9684 == 3)
                                        {
                                            _9685 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_9684 == 4)
                                        {
                                            _9685 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_9684 == 5)
                                        {
                                            _9685 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_9684 == 6)
                                        {
                                            _9685 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_9684 == 7)
                                        {
                                            _9685 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_9684 == 8)
                                        {
                                            _9685 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_9684 == 9)
                                        {
                                            _9685 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_9684 == 10)
                                        {
                                            _9685 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_9684 == 11)
                                        {
                                            _9685 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_9684 == 12)
                                        {
                                            _9685 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_9684 == 13)
                                        {
                                            _9685 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_9684 == 14)
                                        {
                                            _9685 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_9684 == 15)
                                        {
                                            _9685 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _9685 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _9687 = vec2(0.0);
                                    do
                                    {
                                        if (_9684 < 3)
                                        {
                                            _9687 = vec2(float(_9684) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_9684 < 6)
                                        {
                                            _9687 = vec2((float(_9684 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_9684 < 11)
                                        {
                                            _9687 = vec2((float(_9684 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_9684 < 14)
                                        {
                                            _9687 = vec2((float(_9684 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _9687 = vec2(float(_9684 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _6124 = mix(_9685, _9687, vec2(_5952));
                                    float _6744 = _6124.x;
                                    float _6748 = _6124.y;
                                    highp vec2 _6774 = clamp(_5665 + (vec2((_6744 * _9675) - (_6748 * _9679), (_6744 * _9679) + (_6748 * _9675)) * _9682), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6783 = _6774.y;
                                    highp vec2 _6784 = vec2((float(_9480) + _6774.x) * _5944, _6783);
                                    _6784.y = 1.0 - _6783;
                                    highp float _6796 = float(_5938 <= textureLod(shadow_map, _6784, 0.0).x);
                                    float mp_copy_6796 = _6796;
                                    _6135 = _9702 + mp_copy_6796;
                                }
                                _9706 = _9702 / float(_6107);
                            }
                            bool _6149 = _9480 == (_5575 - 1);
                            bool _6155 = false;
                            if (_6149)
                            {
                                _6155 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6155 = _6149;
                            }
                            float _9708 = 0.0;
                            if (_6155)
                            {
                                highp vec2 _6162 = vec2(frag_info.shadow_fade / _9642);
                                highp vec2 _6170 = smoothstep(vec2(0.0), _6162, _5665) * smoothstep(vec2(0.0), _6162, _5822);
                                _9708 = mix(1.0, _9706, _6170.x * _6170.y);
                            }
                            else
                            {
                                _9708 = _9706;
                            }
                            _9768 = _9484 + _5725;
                            _9765 = _9482 + (_5725 * _9708);
                        }
                        else
                        {
                            _9768 = _9484;
                            _9765 = _9482;
                        }
                        _9767 = _9768;
                        _9764 = _9765;
                    }
                    else
                    {
                        _9767 = _9484;
                        _9764 = _9482;
                    }
                    _9766 = _9767;
                    _9763 = _9764;
                }
                else
                {
                    _9766 = _9484;
                    _9763 = _9482;
                }
            }
            _9483 = _9484;
            _9481 = _9482;
        }
        else
        {
            _9483 = 0.0;
            _9481 = 0.0;
        }
        _9487 = mix(_9481 + (1.0 - _9483), 1.0, _9479);
    }
    else
    {
        _9487 = 1.0;
    }
    vec3 mp_copy_9488 = vec3(0.0);
    float _5068 = _5046 * _9487;
    bool _6803 = view_info.camera_forward.w > 0.5;
    highp vec3 _9488 = vec3(0.0);
    if (_6803)
    {
        _9488 = -view_info.camera_forward.xyz;
    }
    else
    {
        _9488 = normalize(v_viewvector);
    }
    highp float _6847 = 0.0;
    mp_copy_9488 = _9488;
    vec3 _5077 = mix(frag_info.dielectric_f0.xyz, _5008, vec3(_4178));
    float _5081 = max(dot(_9429, _9488), 0.0);
    float _5085 = max(dot(_4044, _9488), 0.0);
    highp vec2 _9489 = vec2(0.0);
    do
    {
        _6847 = frag_info.punctual_dims.x;
        if (_6847 < 0.5)
        {
            _9489 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _6859 = v_position - frag_info.camera_position.xyz;
            highp float _6874 = dot(_6859, frag_info.camera_forward.xyz);
            highp float _6880 = max(_6874, 9.9999997473787516355514526367188e-05);
            highp vec2 _6983 = (vec3(dot(_6859, frag_info.camera_right.xyz), dot(_6859, frag_info.camera_up.xyz), _6880).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_6880, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _6998 = float(int(((((clamp(floor((log2(max(_6874 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_6983.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_6983.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _9489 = vec2(textureLod(punctual_index, vec2((mod(_6998, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_6998 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _9489 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5094 = int(_9489.x + 0.5);
    mediump int _5098 = int(_9489.y + 0.5);
    highp vec3 _9534 = vec3(0.0);
    _9534 = vec3(0.0);
    highp vec3 _9876 = vec3(0.0);
    for (int _9490 = 0; _9490 < _5098; _9534 = _9876, _9490++)
    {
        highp float hp_copy_9591 = 0.0;
        highp float _7031 = float(_5094 + _9490);
        highp float _7062 = (float(int(textureLod(punctual_index, vec2((mod(_7031, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7031 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _6847;
        highp vec4 _7066 = textureLod(punctual_lights, vec2(0.0625, _7062), 0.0);
        highp vec4 _7083 = textureLod(punctual_lights, vec2(0.1875, _7062), 0.0);
        highp float _5116 = _7066.w;
        highp vec3 _5118 = _7083.xyz;
        vec3 _9577 = vec3(0.0);
        highp vec3 _9588 = vec3(0.0);
        float _9591 = 0.0;
        if (_5116 < 0.5)
        {
            _9591 = _9477;
            _9588 = _5118;
            _9577 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7062), 0.0).xyz);
        }
        else
        {
            highp vec3 _5126 = _7066.xyz - v_position;
            highp float _5129 = dot(_5126, _5126);
            highp float _5133 = inversesqrt(max(_5129, 9.9999999392252902907785028219223e-09));
            highp vec3 _5134 = _5126 * _5133;
            vec3 mp_copy_5134 = _5134;
            highp float _5136 = _7083.w;
            highp float _5141 = (_5129 * _5136) * _5136;
            highp float _5146 = clamp(1.0 - (_5141 * _5141), 0.0, 1.0);
            float mp_copy_5146 = _5146;
            if (_5146 <= 0.0)
            {
                _9876 = _9534;
                continue;
            }
            highp vec4 _7100 = textureLod(punctual_lights, vec2(0.4375, _7062), 0.0);
            highp float _5154 = _7100.w;
            float _9593 = 0.0;
            if (_5154 > 0.0)
            {
                highp float _5181 = (_9477 * _9477) + ((_5154 * 0.5) * _5133);
                float mp_copy_5181 = _5181;
                _9593 = sqrt(min(mp_copy_5181, 1.0));
            }
            else
            {
                _9593 = _9477;
            }
            highp vec3 _5188 = _5118 * ((mp_copy_5146 * mp_copy_5146) / max(pow(max(_5129, _5154 * _5154), _7100.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _9589 = vec3(0.0);
            if (_5116 > 1.5)
            {
                highp vec4 _7117 = textureLod(punctual_lights, vec2(0.3125, _7062), 0.0);
                highp float _5207 = clamp((dot(normalize(_7117.xyz), -mp_copy_5134) * _7117.w) + _7100.x, 0.0, 1.0);
                float mp_copy_5207 = _5207;
                highp vec3 _5212 = _5188 * (mp_copy_5207 * mp_copy_5207);
                if (_5207 <= 0.0)
                {
                    _9876 = _9534;
                    continue;
                }
                bool _5218 = _5207 > 0.0;
                bool _5224 = false;
                if (_5218)
                {
                    _5224 = _7100.y > (-0.5);
                }
                else
                {
                    _5224 = _5218;
                }
                bool _5230 = false;
                if (_5224)
                {
                    _5230 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5230 = _5224;
                }
                highp vec3 _9590 = vec3(0.0);
                if (_5230)
                {
                    float _9568 = 0.0;
                    do
                    {
                        highp vec4 _7229 = mat4(textureLod(punctual_lights, vec2(0.5625, _7062), 0.0), textureLod(punctual_lights, vec2(0.6875, _7062), 0.0), textureLod(punctual_lights, vec2(0.8125, _7062), 0.0), textureLod(punctual_lights, vec2(0.9375, _7062), 0.0)) * vec4(v_position + (_4044 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _7231 = _7229.w;
                        if (_7231 <= 0.0)
                        {
                            _9568 = 1.0;
                            break;
                        }
                        highp vec3 _7240 = _7229.xyz / vec3(_7231);
                        highp vec2 _7245 = (_7240.xy * 0.5) + vec2(0.5);
                        highp float _7247 = _7245.x;
                        bool _7248 = _7247 < 0.0;
                        bool _7255 = false;
                        if (!_7248)
                        {
                            _7255 = _7247 > 1.0;
                        }
                        else
                        {
                            _7255 = _7248;
                        }
                        bool _7262 = false;
                        if (!_7255)
                        {
                            _7262 = _7245.y < 0.0;
                        }
                        else
                        {
                            _7262 = _7255;
                        }
                        bool _7269 = false;
                        if (!_7262)
                        {
                            _7269 = _7245.y > 1.0;
                        }
                        else
                        {
                            _7269 = _7262;
                        }
                        bool _7276 = false;
                        if (!_7269)
                        {
                            _7276 = _7240.z < 0.0;
                        }
                        else
                        {
                            _7276 = _7269;
                        }
                        bool _7283 = false;
                        if (!_7276)
                        {
                            _7283 = _7240.z > 1.0;
                        }
                        else
                        {
                            _7283 = _7276;
                        }
                        if (_7283)
                        {
                            _9568 = 1.0;
                            break;
                        }
                        highp float _7290 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _7295 = frag_info.shadow_cascade_count + float(int(_7100.y + 0.5));
                        highp float _7300 = _7240.z - frag_info.spot_shadow_params.y;
                        highp float _7311 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_7311 = _7311;
                        highp vec2 _7318 = vec2(cos(mp_copy_7311), sin(mp_copy_7311)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _7320 = _7318.x;
                        highp float _7322 = _7318.y;
                        highp vec2 _7330 = vec2(_7320 - _7322, _7320 + _7322) * 0.707106769084930419921875;
                        highp float _7523 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7247, 0.0, 1.0)) / _7290, 1.0 - clamp(_7245.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7523 = _7523;
                        highp vec2 _7338 = _7245 + _7318;
                        highp float _7545 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7338.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7338.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7545 = _7545;
                        highp vec2 _7346 = _7245 - _7318;
                        highp float _7567 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7346.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7346.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7567 = _7567;
                        highp vec2 _7359 = _7245 + vec2(-_7322, _7320);
                        highp float _7589 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7359.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7359.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7589 = _7589;
                        highp vec2 _7372 = _7245 + vec2(_7322, -_7320);
                        highp float _7611 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7372.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7372.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7611 = _7611;
                        float _7377 = (((mp_copy_7523 + mp_copy_7545) + mp_copy_7567) + mp_copy_7589) + mp_copy_7611;
                        if ((_7377 < 0.5) || (_7377 > 4.5))
                        {
                            _9568 = _7377 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _7389 = _7245 + _7330;
                        highp float _7633 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7389.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7389.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7633 = _7633;
                        highp vec2 _7396 = _7245 - _7330;
                        highp float _7655 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7396.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7396.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7655 = _7655;
                        highp float _7404 = _7330.y;
                        highp float _7407 = _7330.x;
                        highp vec2 _7409 = _7245 + vec2(-_7404, _7407);
                        highp float _7677 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7409.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7409.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7677 = _7677;
                        highp vec2 _7422 = _7245 + vec2(_7404, -_7407);
                        highp float _7699 = float(_7300 <= textureLod(shadow_map, vec2((_7295 + clamp(_7422.x, 0.0, 1.0)) / _7290, 1.0 - clamp(_7422.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_7699 = _7699;
                        _9568 = (_7377 + (((mp_copy_7633 + mp_copy_7655) + mp_copy_7677) + mp_copy_7699)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _9590 = _5212 * _9568;
                }
                else
                {
                    _9590 = _5212;
                }
                _9589 = _9590;
            }
            else
            {
                _9589 = _5188;
            }
            _9591 = _9593;
            _9588 = _9589;
            _9577 = _5134;
        }
        hp_copy_9591 = _9591;
        highp vec3 _9606 = vec3(0.0);
        highp vec3 _9607 = vec3(0.0);
        do
        {
            float _7782 = max(dot(_9429, _9577), 0.0);
            highp float hp_copy_7782 = _7782;
            if (_7782 <= 0.0)
            {
                _9607 = vec3(0.0);
                _9606 = vec3(0.0);
                break;
            }
            float _7788 = max(_5081, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_7788 = _7788;
            vec3 _7791 = _9577 + mp_copy_9488;
            float _7794 = dot(_7791, _7791);
            vec3 _9604 = vec3(0.0);
            vec3 _9605 = vec3(0.0);
            if (_7794 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _7802 = _7791 * inversesqrt(_7794);
                float _9603 = 0.0;
                do
                {
                    float _7859 = dot(_9429, _7802);
                    if (_7859 <= 0.0)
                    {
                        _9603 = 0.0;
                        break;
                    }
                    float _7866 = _9591 * _9591;
                    vec3 _7869 = cross(_9429, _7802);
                    float _7872 = _7859 * _7866;
                    float _7881 = _7866 / (dot(_7869, _7869) + (_7872 * _7872));
                    _9603 = min((_7881 * _7881) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _7919 = _5077 + ((vec3(1.0) - _5077) * pow(clamp(1.0 - max(dot(_7802, _9488), 0.0), 0.0, 1.0), 5.0));
                _9605 = (_7919 * min(_9603 * (0.5 / max(mix((2.0 * hp_copy_7782) * _7788, hp_copy_7782 + hp_copy_7788, hp_copy_9591 * hp_copy_9591), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9604 = _7919;
            }
            else
            {
                _9605 = vec3(0.0);
                _9604 = _5077;
            }
            _9607 = (_9605 * _9588) * _7782;
            _9606 = (((((vec3(1.0) - _9604) * (1.0 - _4178)) * _5008) * 0.3183098733425140380859375) * _9588) * _7782;
            break;
        } while(false);
        _9876 = _9534 + (_9606 + _9607);
    }
    bool _8143 = false;
    highp vec3 hp_copy_9491 = vec3(0.0);
    mat3 _5285 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5293 = _5285 * vec3(_9429.x, _9429.y, _9429.z);
    vec3 _5296 = _5285 * reflect(-mp_copy_9488, _9429);
    float _7962 = _5293.y;
    float _7969 = _5293.z;
    float _7976 = _5293.x;
    float _7984 = 1.09254801273345947265625 * _7976;
    vec3 _5299 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _7962))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _7969))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _7976))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_7984 * _7962))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _7962) * _7969))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _7969) * _7969) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_7984 * _7969))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_7976 * _7976) - (_7962 * _7962)))), vec3(0.0));
    highp vec3 hp_copy_5299 = _5299;
    vec3 _9491 = vec3(0.0);
    do
    {
        _8143 = radiance_layout_info.mip_layout > 0.5;
        if (_8143)
        {
            vec2 _8222 = vec2(atan(_5296.z, _5296.x), asin(clamp(_5296.y, -1.0, 1.0)));
            highp vec2 hp_copy_8222 = _8222;
            _9491 = textureLod(prefiltered_radiance, (hp_copy_8222 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9477, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8241 = vec2(atan(_5296.z, _5296.x), asin(clamp(_5296.y, -1.0, 1.0)));
        highp vec2 hp_copy_8241 = _8241;
        highp vec2 _8246 = (hp_copy_8241 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8153 = clamp(_8246.y, 0.00390625, 0.99609375);
        float _8157 = clamp(_9477, 0.0, 1.0) * 7.0;
        float _8159 = floor(_8157);
        highp float _8178 = _8246.x;
        _9491 = mix(textureLod(prefiltered_radiance, vec2(_8178, (_8159 + _8153) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8178, (min(_8159 + 1.0, 7.0) + _8153) * 0.125), 0.0).xyz, vec3(_8157 - _8159));
        break;
    } while(false);
    hp_copy_9491 = _9491;
    highp vec3 _9497 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_9492 = vec3(0.0);
        vec3 _9492 = vec3(0.0);
        do
        {
            if (_8143)
            {
                vec2 _8351 = vec2(atan(_5296.z, _5296.x), asin(clamp(_5296.y, -1.0, 1.0)));
                highp vec2 hp_copy_8351 = _8351;
                _9492 = textureLod(prefiltered_radiance_b, (hp_copy_8351 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_9477, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8370 = vec2(atan(_5296.z, _5296.x), asin(clamp(_5296.y, -1.0, 1.0)));
            highp vec2 hp_copy_8370 = _8370;
            highp vec2 _8375 = (hp_copy_8370 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8282 = clamp(_8375.y, 0.00390625, 0.99609375);
            float _8286 = clamp(_9477, 0.0, 1.0) * 7.0;
            float _8288 = floor(_8286);
            highp float _8307 = _8375.x;
            _9492 = mix(textureLod(prefiltered_radiance_b, vec2(_8307, (_8288 + _8282) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_8307, (min(_8288 + 1.0, 7.0) + _8282) * 0.125), 0.0).xyz, vec3(_8286 - _8288));
            break;
        } while(false);
        hp_copy_9492 = _9492;
        _9497 = hp_copy_9491 + hp_copy_9492;
    }
    else
    {
        _9497 = _9491;
    }
    float _5314 = frag_info.environment_intensity;
    highp float hp_copy_5314 = _5314;
    vec2 _5327 = clamp(vec2(_5085, _9477), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5329 = texture(brdf_lut, vec2(_5327.x * 0.3333333432674407958984375, _5327.y));
    float _5333 = _5329.x;
    float _5336 = _5329.y;
    vec3 _5338 = ((_5077 + ((max(vec3(1.0 - _9477), _5077) - _5077) * pow(clamp(1.0 - _5085, 0.0, 1.0), 5.0))) * _5333) + vec3(_5336);
    float _5344 = 1.0 - (_5333 + _5336);
    vec3 _5348 = vec3(1.0) - _5077;
    vec3 _5351 = _5077 + (_5348 * vec3(0.0476190485060214996337890625));
    vec3 _5362 = ((_5338 * _5344) * _5351) / (vec3(1.0) - (_5351 * _5344));
    float _5365 = 1.0 - _4178;
    float _9511 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _9511 = clamp((pow(_5081 + _9506, exp2(((-16.0) * _9477) - 1.0)) - 1.0) + _9506, 0.0, 1.0);
    }
    else
    {
        _9511 = _9506;
    }
    highp vec3 _9544 = vec3(0.0);
    if (_5033)
    {
        highp vec3 _9528 = vec3(0.0);
        highp vec3 _9529 = vec3(0.0);
        do
        {
            float _8464 = max(dot(_9429, _9520), 0.0);
            highp float hp_copy_8464 = _8464;
            if (_8464 <= 0.0)
            {
                _9529 = vec3(0.0);
                _9528 = vec3(0.0);
                break;
            }
            float _8470 = max(_5081, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8470 = _8470;
            vec3 _8473 = _9520 + mp_copy_9488;
            float _8476 = dot(_8473, _8473);
            vec3 _9526 = vec3(0.0);
            vec3 _9527 = vec3(0.0);
            if (_8476 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8484 = _8473 * inversesqrt(_8476);
                float _9525 = 0.0;
                do
                {
                    float _8541 = dot(_9429, _8484);
                    if (_8541 <= 0.0)
                    {
                        _9525 = 0.0;
                        break;
                    }
                    float _8548 = _9477 * _9477;
                    vec3 _8551 = cross(_9429, _8484);
                    float _8554 = _8541 * _8548;
                    float _8563 = _8548 / (dot(_8551, _8551) + (_8554 * _8554));
                    _9525 = min((_8563 * _8563) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8601 = _5077 + (_5348 * pow(clamp(1.0 - max(dot(_8484, _9488), 0.0), 0.0, 1.0), 5.0));
                _9527 = (_8601 * min(_9525 * (0.5 / max(mix((2.0 * hp_copy_8464) * _8470, hp_copy_8464 + hp_copy_8470, hp_copy_9477 * hp_copy_9477), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _9526 = _8601;
            }
            else
            {
                _9527 = vec3(0.0);
                _9526 = _5077;
            }
            _9529 = (_9527 * frag_info.directional_light_color.xyz) * _8464;
            _9528 = (((((vec3(1.0) - _9526) * _5365) * _5008) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _8464;
            break;
        } while(false);
        _9544 = _9534 + ((_9528 + _9529) * _5068);
    }
    else
    {
        _9544 = _9534;
    }
    bool _5456 = _FogInfo.params0.y > 0.5;
    bool _5462 = false;
    if (_5456)
    {
        _5462 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5462 = _5456;
    }
    highp vec3 _9547 = vec3(0.0);
    if (_5462)
    {
        vec3 mp_copy_9545 = vec3(0.0);
        highp vec3 _9545 = vec3(0.0);
        if (_6803)
        {
            _9545 = -view_info.camera_forward.xyz;
        }
        else
        {
            _9545 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_9546 = vec3(0.0);
        mp_copy_9545 = _9545;
        vec3 _5467 = _5285 * (-mp_copy_9545);
        vec3 _9546 = vec3(0.0);
        do
        {
            if (_8143)
            {
                vec2 _8723 = vec2(atan(_5467.z, _5467.x), asin(clamp(_5467.y, -1.0, 1.0)));
                highp vec2 hp_copy_8723 = _8723;
                _9546 = textureLod(prefiltered_radiance, (hp_copy_8723 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _8742 = vec2(atan(_5467.z, _5467.x), asin(clamp(_5467.y, -1.0, 1.0)));
            highp vec2 hp_copy_8742 = _8742;
            highp vec2 _8747 = (hp_copy_8742 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8654 = clamp(_8747.y, 0.00390625, 0.99609375);
            float _8660 = floor(0.0);
            highp float _8679 = _8747.x;
            _9546 = mix(textureLod(prefiltered_radiance, vec2(_8679, (_8660 + _8654) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8679, (min(_8660 + 1.0, 7.0) + _8654) * 0.125), 0.0).xyz, vec3(-_8660));
            break;
        } while(false);
        hp_copy_9546 = _9546;
        _9547 = hp_copy_9546 * hp_copy_5314;
    }
    else
    {
        _9547 = _FogInfo.color.xyz;
    }
    highp vec4 _5482 = vec4(min(((((((_5362 + ((_5008 * _5365) * ((vec3(1.0) - _5338) - _5362))) * (hp_copy_5299 * hp_copy_5314)) * vec3(_4212)) + (((_5338 * (_9497 * _5314)) * 1.0) * _9511)) * mix(1.0, _5068, frag_info.radiance_blend.y)) + (_9544 * mix(1.0, _9506, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _9452, vec3(65504.0)), 1.0) * _9927;
    highp vec4 _9562 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _9562 = _5482;
            break;
        }
        int _8791 = int(_FogInfo.params0.x + 0.5);
        if (_8791 == 0)
        {
            _9562 = _5482;
            break;
        }
        highp float _9549 = 0.0;
        if (_6803)
        {
            _9549 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _9549 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_9549 > _FogInfo.params1.w))
        {
            _9562 = _5482;
            break;
        }
        float _9553 = 0.0;
        if (_8791 == 1)
        {
            _9553 = clamp((_9549 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _9554 = 0.0;
            if (_8791 == 2)
            {
                highp float _9552 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _9550 = vec3(0.0);
                    if (_6803)
                    {
                        _9550 = v_position - (view_info.camera_forward.xyz * _9549);
                    }
                    else
                    {
                        _9550 = v_position + v_viewvector;
                    }
                    highp float _8882 = -_FogInfo.params2.y;
                    highp float _8889 = _FogInfo.params1.x * exp(_8882 * (_9550.y - _FogInfo.params2.x));
                    highp float _8906 = _FogInfo.params2.y * (v_position.y - _9550.y);
                    highp float _9551 = 0.0;
                    if (abs(_8906) > 0.00124999997206032276153564453125)
                    {
                        _9551 = (_8889 - (_FogInfo.params1.x * exp(_8882 * (v_position.y - _FogInfo.params2.x)))) / _8906;
                    }
                    else
                    {
                        _9551 = _8889;
                    }
                    _9552 = _9551 * max(_9549 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _9552 = _FogInfo.params1.x * max(_9549 - _FogInfo.params1.y, 0.0);
                }
                _9554 = 1.0 - exp(-_9552);
            }
            else
            {
                highp float _8844 = _FogInfo.params1.x * max(_9549 - _FogInfo.params1.y, 0.0);
                _9554 = 1.0 - exp((-_8844) * _8844);
            }
            _9553 = _9554;
        }
        highp float _8946 = min(_9553, _FogInfo.params0.z);
        if (_8946 <= 0.0)
        {
            _9562 = _5482;
            break;
        }
        highp vec3 _8959 = mix(_FogInfo.color.xyz, _9547, vec3(_FogInfo.params0.w));
        bool _8962 = _FogInfo.sun.w > 0.5;
        bool _8968 = false;
        if (_8962)
        {
            _8968 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _8968 = _8962;
        }
        vec3 _9558 = vec3(0.0);
        if (_8968)
        {
            vec3 mp_copy_9555 = vec3(0.0);
            highp vec3 _9555 = vec3(0.0);
            if (_6803)
            {
                _9555 = -view_info.camera_forward.xyz;
            }
            else
            {
                _9555 = normalize(v_viewvector);
            }
            mp_copy_9555 = _9555;
            highp float _8984 = pow(max(dot(-mp_copy_9555, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_8984 = _8984;
            _9558 = _8959 + ((_FogInfo.sun.xyz * mp_copy_8984) * _FogInfo.params2.z);
        }
        else
        {
            _9558 = _8959;
        }
        highp float _8997 = _5482.w;
        float mp_copy_8997 = _8997;
        _9562 = vec4(mix(_5482.xyz, _9558 * mp_copy_8997, vec3(_8946)), _8997);
        break;
    } while(false);
    vec4 _9564 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _9564 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _9564 = _9562;
        break;
    } while(false);
    frag_color = _9564;
    float _9565 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _9565 = 1.0;
    }
    else
    {
        _9565 = abs(frag_info.fade);
    }
    frag_color *= _9565;
}

