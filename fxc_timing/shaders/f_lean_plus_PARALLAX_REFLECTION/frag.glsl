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
    highp float _4321 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4321 = _4321;
    vec3 _4325 = normalize(v_normal) * mp_copy_4321;
    vec4 _4367 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4370 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _10375 = vec2(0.0);
    if (_4370)
    {
        highp vec2 _10374 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _10374 = v_texture_coords_1;
        }
        else
        {
            _10374 = v_texture_coords;
        }
        highp vec2 _4573 = _10374 * texture_transforms.base_color_transform.zw;
        highp float _4579 = _4573.x;
        highp float _4584 = _4573.y;
        _10375 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4579) + (texture_transforms.base_color_rotation.y * _4584), ((-texture_transforms.base_color_rotation.y) * _4579) + (texture_transforms.base_color_rotation.x * _4584));
    }
    else
    {
        _10375 = v_texture_coords;
    }
    vec4 _4384 = texture(base_color_texture, _10375);
    vec3 _4386 = _4384.xyz;
    float _10898 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4384.w * _4367.w) * frag_info.color.w);
    vec3 _10390 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _10378 = vec2(0.0);
        if (_4370)
        {
            highp vec2 _10377 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _10377 = v_texture_coords_1;
            }
            else
            {
                _10377 = v_texture_coords;
            }
            highp vec2 _4668 = _10377 * texture_transforms.normal_transform.zw;
            highp float _4674 = _4668.x;
            highp float _4679 = _4668.y;
            _10378 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4674) + (texture_transforms.normal_rotation.y * _4679), ((-texture_transforms.normal_rotation.y) * _4674) + (texture_transforms.normal_rotation.x * _4679));
        }
        else
        {
            _10378 = v_texture_coords;
        }
        vec3 _4724 = ((texture(normal_texture, _10378).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4728 = _4724.xy * vec2(frag_info.normal_scale);
        vec3 _10099 = _4724;
        _10099.x = _4728.x;
        _10099.y = _4728.y;
        highp vec3 _4734 = -v_viewvector;
        highp vec3 _4824 = dFdx(_4734);
        highp vec3 _4826 = dFdy(_4734);
        highp vec2 _4828 = dFdx(_10378);
        highp vec2 _4830 = dFdy(_10378);
        bvec2 _10900 = bvec2(length(_4828) == 0.0);
        highp vec2 _10901 = vec2(_10900.x ? vec2(1.0, 0.0).x : _4828.x, _10900.y ? vec2(1.0, 0.0).y : _4828.y);
        bvec2 _10902 = bvec2(length(_4830) == 0.0);
        highp vec2 _10903 = vec2(_10902.x ? vec2(0.0, 1.0).x : _4830.x, _10902.y ? vec2(0.0, 1.0).y : _4830.y);
        highp vec3 _4843 = cross(_4826, _4325);
        highp vec3 _4846 = cross(_4325, _4824);
        highp float _4871 = (dot(cross(_4824, _4826), _4325) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4874 = ((_4843 * _10901.x) + (_4846 * _10903.x)) * _4871;
        highp float _10385 = 0.0;
        if (gl_FrontFacing)
        {
            _10385 = -_4871;
        }
        else
        {
            _10385 = _4871;
        }
        highp vec3 _4884 = ((_4843 * _10901.y) + (_4846 * _10903.y)) * _10385;
        highp float _4893 = inversesqrt(max(max(dot(_4874, _4874), dot(_4884, _4884)), 9.9999996826552253889678874634872e-21));
        vec3 _4765 = v_tangent.xyz - (_4325 * dot(_4325, v_tangent.xyz));
        highp float _4768 = dot(_4765, _4765);
        bool _4770 = _4768 > 1.0000000133514319600180897396058e-10;
        bool _4777 = false;
        if (_4770)
        {
            _4777 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4777 = _4770;
        }
        mat3 _10388 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4777)
        {
            highp vec3 _4782 = _4765 * inversesqrt(_4768);
            _10388 = mat3(_4782, normalize(cross(_4325, _4782)) * sign(v_tangent.w), _4325);
        }
        else
        {
            _10388 = mat3(_4874 * _4893, _4884 * _4893, _4325);
        }
        _10390 = normalize(_10388 * _10099);
    }
    else
    {
        _10390 = _4325;
    }
    highp vec2 _10392 = vec2(0.0);
    if (_4370)
    {
        highp vec2 _10391 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _10391 = v_texture_coords_1;
        }
        else
        {
            _10391 = v_texture_coords;
        }
        highp vec2 _4961 = _10391 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4967 = _4961.x;
        highp float _4972 = _4961.y;
        _10392 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4967) + (texture_transforms.metallic_roughness_rotation.y * _4972), ((-texture_transforms.metallic_roughness_rotation.y) * _4967) + (texture_transforms.metallic_roughness_rotation.x * _4972));
    }
    else
    {
        _10392 = v_texture_coords;
    }
    vec4 _4453 = texture(metallic_roughness_texture, _10392);
    float _4459 = clamp(_4453.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4466 = clamp(_4453.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _10394 = vec2(0.0);
    if (_4370)
    {
        highp vec2 _10393 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _10393 = v_texture_coords_1;
        }
        else
        {
            _10393 = v_texture_coords;
        }
        highp vec2 _5032 = _10393 * texture_transforms.occlusion_transform.zw;
        highp float _5038 = _5032.x;
        highp float _5043 = _5032.y;
        _10394 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _5038) + (texture_transforms.occlusion_rotation.y * _5043), ((-texture_transforms.occlusion_rotation.y) * _5038) + (texture_transforms.occlusion_rotation.x * _5043));
    }
    else
    {
        _10394 = v_texture_coords;
    }
    float _10395 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _10395 = texture(occlusion_texture, _10394).x;
    }
    else
    {
        _10395 = 1.0;
    }
    float _4493 = 1.0 - ((1.0 - _10395) * frag_info.occlusion_strength);
    highp vec2 _10397 = vec2(0.0);
    if (_4370)
    {
        highp vec2 _10396 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _10396 = v_texture_coords_1;
        }
        else
        {
            _10396 = v_texture_coords;
        }
        highp vec2 _5103 = _10396 * texture_transforms.emissive_transform.zw;
        highp float _5109 = _5103.x;
        highp float _5114 = _5103.y;
        _10397 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5109) + (texture_transforms.emissive_rotation.y * _5114), ((-texture_transforms.emissive_rotation.y) * _5109) + (texture_transforms.emissive_rotation.x * _5114));
    }
    else
    {
        _10397 = v_texture_coords;
    }
    vec3 _4512 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _10413 = vec3(0.0);
    if (dot(abs(_4512), vec3(1.0)) > 0.0)
    {
        vec3 _4521 = texture(emissive_texture, _10397).xyz;
        _10413 = mix(_4521 * vec3(0.077399380505084991455078125), pow((_4521 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4521)) * _4512;
    }
    else
    {
        _10413 = vec3(0.0);
    }
    highp float hp_copy_10438 = 0.0;
    vec3 _5291 = vec4((mix(_4386 * vec3(0.077399380505084991455078125), pow((_4386 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4386)) * _4367.xyz) * frag_info.color.xyz, _10898).xyz;
    vec3 _5779 = dFdx(_10390);
    vec3 _5781 = dFdy(_10390);
    float _10438 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10438 = sqrt(clamp((_4466 * _4466) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5779, _5779), dot(_5781, _5781))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10438 = _4466;
    }
    hp_copy_10438 = _10438;
    float _10469 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _10469 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _10469 = _4493;
    }
    bool _5316 = frag_info.has_directional_light > 0.5;
    float _10439 = 0.0;
    vec3 _10484 = vec3(0.0);
    if (_5316)
    {
        highp vec3 _5322 = -normalize(frag_info.directional_light_direction.xyz);
        _10484 = _5322;
        _10439 = dot(_4325, _5322);
    }
    else
    {
        _10484 = vec3(0.0);
        _10439 = 0.0;
    }
    float _5329 = clamp(_10439 * 6.666666507720947265625, 0.0, 1.0);
    bool _5338 = false;
    if (_5316)
    {
        _5338 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5338 = _5316;
    }
    float _10448 = 0.0;
    if (_5338 && (_5329 > 0.0))
    {
        int _5860 = int(frag_info.shadow_cascade_count);
        float _6055 = max(dot(_4325, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6058 = _6055 * _6055;
        highp vec3 _6078 = v_position + (_4325 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6058, 0.0)) / _6058, 8.0))));
        highp float _5866 = frag_info.directional_light_color.w * 0.5;
        float _5868 = frag_info.dielectric_f0.w;
        highp float hp_copy_5868 = _5868;
        float _10440 = 0.0;
        if (_5868 > 0.0)
        {
            _10440 = smoothstep(_5868 - max(frag_info.shadow_fade, hp_copy_5868 * 0.100000001490116119384765625), _5868, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10440 = 0.0;
        }
        float _10442 = 0.0;
        float _10444 = 0.0;
        if (_10440 < 1.0)
        {
            float _10443 = 0.0;
            float _10445 = 0.0;
            _10445 = 0.0;
            _10443 = 0.0;
            float _10732 = 0.0;
            float _10735 = 0.0;
            for (int _10441 = 0; _10441 < _5860; _10445 = _10735, _10443 = _10732, _10441++)
            {
                if (_10445 < 1.0)
                {
                    highp vec4 _5900 = vec4(_6078, 1.0);
                    highp vec4 _10604 = vec4(0.0);
                    highp float _10607 = 0.0;
                    if (_10441 == 0)
                    {
                        _10607 = frag_info.cascade_box_sizes.x;
                        _10604 = frag_info.light_space_matrix[0] * _5900;
                    }
                    else
                    {
                        highp vec4 _10605 = vec4(0.0);
                        highp float _10608 = 0.0;
                        if (_10441 == 1)
                        {
                            _10608 = frag_info.cascade_box_sizes.y;
                            _10605 = frag_info.light_space_matrix[1] * _5900;
                        }
                        else
                        {
                            highp vec4 _10606 = vec4(0.0);
                            highp float _10609 = 0.0;
                            if (_10441 == 2)
                            {
                                _10609 = frag_info.cascade_box_sizes.z;
                                _10606 = frag_info.light_space_matrix[2] * _5900;
                            }
                            else
                            {
                                _10609 = frag_info.cascade_box_sizes.w;
                                _10606 = frag_info.light_space_matrix[3] * _5900;
                            }
                            _10608 = _10609;
                            _10605 = _10606;
                        }
                        _10607 = _10608;
                        _10604 = _10605;
                    }
                    highp vec3 _5945 = _10604.xyz / vec3(_10604.w);
                    highp vec2 _5948 = _5945.xy * 0.5;
                    highp vec2 _5950 = _5948 + vec2(0.5);
                    highp float _5957 = max(frag_info.shadow_softness / _10607, frag_info.shadow_texel_size);
                    highp float _5959 = _5950.x;
                    bool _5961 = _5959 < _5957;
                    bool _5970 = false;
                    if (!_5961)
                    {
                        _5970 = _5959 > (1.0 - _5957);
                    }
                    else
                    {
                        _5970 = _5961;
                    }
                    bool _5978 = false;
                    if (!_5970)
                    {
                        _5978 = _5950.y < _5957;
                    }
                    else
                    {
                        _5978 = _5970;
                    }
                    bool _5987 = false;
                    if (!_5978)
                    {
                        _5987 = _5950.y > (1.0 - _5957);
                    }
                    else
                    {
                        _5987 = _5978;
                    }
                    bool _5994 = false;
                    if (!_5987)
                    {
                        _5994 = _5945.z < 0.0;
                    }
                    else
                    {
                        _5994 = _5987;
                    }
                    bool _6001 = false;
                    if (!_5994)
                    {
                        _6001 = _5945.z > 1.0;
                    }
                    else
                    {
                        _6001 = _5994;
                    }
                    float _10733 = 0.0;
                    float _10736 = 0.0;
                    if (!_6001)
                    {
                        highp vec2 _6094 = vec2(_5957);
                        highp vec2 _6099 = vec2(_5957 + max(_5866, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6107 = vec2(0.5) - _5948;
                        highp vec2 _6109 = smoothstep(_6094, _6099, _5950) * smoothstep(_6094, _6099, _6107);
                        float _10610 = 0.0;
                        if (_5866 > 0.0)
                        {
                            _10610 = _6109.x * _6109.y;
                        }
                        else
                        {
                            _10610 = 1.0;
                        }
                        float _6010 = min(_10610, 1.0 - _10445);
                        float _10734 = 0.0;
                        float _10737 = 0.0;
                        if (_6010 > 0.0)
                        {
                            highp float _6248 = _5945.z - (frag_info.shadow_bias / (7.0 * _10607));
                            highp float _6254 = 1.0 / (float(_5860) + frag_info.spot_shadow_params.x);
                            highp float _6256 = frag_info.directional_light_direction.w;
                            float mp_copy_6256 = _6256;
                            float _6262 = step(0.5, mp_copy_6256) * (1.0 - step(1.5, mp_copy_6256));
                            float _10640 = 0.0;
                            float _10644 = 0.0;
                            if (_6262 < 0.5)
                            {
                                highp float _6273 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6273 = _6273;
                                _10644 = sin(mp_copy_6273);
                                _10640 = cos(mp_copy_6273);
                            }
                            else
                            {
                                _10644 = 0.0;
                                _10640 = 1.0;
                            }
                            highp float _10647 = 0.0;
                            if ((_6256 > 1.5) && (_6256 < 2.5))
                            {
                                highp float _6297 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6302 = max(_6297 * _6248, frag_info.shadow_texel_size);
                                float _10636 = 0.0;
                                highp float _10637 = 0.0;
                                _10637 = 0.0;
                                _10636 = 0.0;
                                highp float _6324 = 0.0;
                                float _6327 = 0.0;
                                for (int _10635 = 0; _10635 < 9; _10637 = _6324, _10636 = _6327, _10635++)
                                {
                                    vec2 _10726 = vec2(0.0);
                                    do
                                    {
                                        if (_10635 == 0)
                                        {
                                            _10726 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10635 == 1)
                                        {
                                            _10726 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10635 == 2)
                                        {
                                            _10726 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10635 == 3)
                                        {
                                            _10726 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10635 == 4)
                                        {
                                            _10726 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10635 == 5)
                                        {
                                            _10726 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10635 == 6)
                                        {
                                            _10726 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10635 == 7)
                                        {
                                            _10726 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10635 == 8)
                                        {
                                            _10726 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10635 == 9)
                                        {
                                            _10726 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10635 == 10)
                                        {
                                            _10726 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10635 == 11)
                                        {
                                            _10726 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10635 == 12)
                                        {
                                            _10726 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10635 == 13)
                                        {
                                            _10726 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10635 == 14)
                                        {
                                            _10726 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10635 == 15)
                                        {
                                            _10726 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10726 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6631 = clamp(_5950 + (vec2((_10726.x * _10640) - (_10726.y * _10644), (_10726.x * _10644) + (_10726.y * _10640)) * _6302), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6640 = _6631.y;
                                    highp vec2 _6641 = vec2((float(_10441) + _6631.x) * _6254, _6640);
                                    _6641.y = 1.0 - _6640;
                                    highp vec4 _6648 = textureLod(shadow_map, _6641, 0.0);
                                    highp float _6649 = _6648.x;
                                    highp float _6319 = step(_6649, _6248);
                                    float mp_copy_6319 = _6319;
                                    _6324 = _10637 + (_6649 * _6319);
                                    _6327 = _10636 + mp_copy_6319;
                                }
                                highp float _10638 = 0.0;
                                if (_10636 > 0.0)
                                {
                                    _10638 = _10637 / _10636;
                                }
                                else
                                {
                                    _10638 = _6248;
                                }
                                _10647 = clamp(_6297 * max(_6248 - _10638, 0.0), frag_info.shadow_texel_size, _5957);
                            }
                            else
                            {
                                _10647 = _5957;
                            }
                            bool _6358 = _6256 > 2.5;
                            bool _10648 = false;
                            float _10673 = 0.0;
                            if ((_6256 < 1.5) || _6358)
                            {
                                highp vec2 _6682 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6686 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6687 = clamp(_5950, _6682, _6686);
                                highp float _6689 = float(_10441);
                                highp float _6696 = _6687.y;
                                highp vec2 _6697 = vec2((_6689 + _6687.x) * _6254, _6696);
                                _6697.y = 1.0 - _6696;
                                highp float _6709 = float(_6248 <= textureLod(shadow_map, _6697, 0.0).x);
                                float mp_copy_6709 = _6709;
                                float _6719 = (-1.0) * _10640;
                                float _6723 = (-1.0) * _10644;
                                highp vec2 _6747 = clamp(_5950 + (vec2(_6719 - _6723, _6723 + _6719) * _10647), _6682, _6686);
                                highp float _6756 = _6747.y;
                                highp vec2 _6757 = vec2((_6689 + _6747.x) * _6254, _6756);
                                _6757.y = 1.0 - _6756;
                                highp float _6769 = float(_6248 <= textureLod(shadow_map, _6757, 0.0).x);
                                float mp_copy_6769 = _6769;
                                highp vec2 _6807 = clamp(_5950 + (vec2(_10640 - _6723, _10644 + _6719) * _10647), _6682, _6686);
                                highp float _6816 = _6807.y;
                                highp vec2 _6817 = vec2((_6689 + _6807.x) * _6254, _6816);
                                _6817.y = 1.0 - _6816;
                                highp float _6829 = float(_6248 <= textureLod(shadow_map, _6817, 0.0).x);
                                float mp_copy_6829 = _6829;
                                highp vec2 _6867 = clamp(_5950 + (vec2(_6719 - _10644, _6723 + _10640) * _10647), _6682, _6686);
                                highp float _6876 = _6867.y;
                                highp vec2 _6877 = vec2((_6689 + _6867.x) * _6254, _6876);
                                _6877.y = 1.0 - _6876;
                                highp float _6889 = float(_6248 <= textureLod(shadow_map, _6877, 0.0).x);
                                float mp_copy_6889 = _6889;
                                highp vec2 _6927 = clamp(_5950 + (vec2(_10640 - _10644, _10644 + _10640) * _10647), _6682, _6686);
                                highp float _6936 = _6927.y;
                                highp vec2 _6937 = vec2((_6689 + _6927.x) * _6254, _6936);
                                _6937.y = 1.0 - _6936;
                                highp float _6949 = float(_6248 <= textureLod(shadow_map, _6937, 0.0).x);
                                float mp_copy_6949 = _6949;
                                float _6404 = (((mp_copy_6709 + mp_copy_6769) + mp_copy_6829) + mp_copy_6889) + mp_copy_6949;
                                _10673 = _6404 * 0.20000000298023223876953125;
                                _10648 = (_6404 < 0.5) || (_6404 > 4.5);
                            }
                            else
                            {
                                _10673 = 0.0;
                                _10648 = false;
                            }
                            float _10671 = 0.0;
                            if (_10648)
                            {
                                _10671 = _10673;
                            }
                            else
                            {
                                float _10672 = 0.0;
                                if (_6358)
                                {
                                    highp vec2 _7168 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7172 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7173 = clamp(_5950 + (vec2(-0.707099974155426025390625) * _10647), _7168, _7172);
                                    highp vec2 _7184 = (vec2(_7173.x, 1.0 - _7173.y) / _7168) - vec2(0.5);
                                    highp vec2 _7186 = floor(_7184);
                                    highp vec2 _7189 = _7184 - _7186;
                                    highp vec2 _7194 = (_7186 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7196 = float(_10441);
                                    highp vec2 _7204 = vec2((_7196 + _7194.x) * _6254, _7194.y);
                                    highp float _7208 = frag_info.shadow_texel_size * _6254;
                                    highp vec2 _7211 = vec2(_7208, frag_info.shadow_texel_size);
                                    highp vec2 _7220 = vec2(_7208, 0.0);
                                    highp vec2 _7228 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7257 = _7189.x;
                                    highp float _7266 = mix(mix(float(_6248 <= textureLod(shadow_map, _7204, 0.0).x), float(_6248 <= textureLod(shadow_map, _7204 + _7220, 0.0).x), _7257), mix(float(_6248 <= textureLod(shadow_map, _7204 + _7228, 0.0).x), float(_6248 <= textureLod(shadow_map, _7204 + _7211, 0.0).x), _7257), _7189.y);
                                    float mp_copy_7266 = _7266;
                                    highp vec2 _7300 = clamp(_5950 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10647), _7168, _7172);
                                    highp vec2 _7311 = (vec2(_7300.x, 1.0 - _7300.y) / _7168) - vec2(0.5);
                                    highp vec2 _7313 = floor(_7311);
                                    highp vec2 _7316 = _7311 - _7313;
                                    highp vec2 _7321 = (_7313 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7331 = vec2((_7196 + _7321.x) * _6254, _7321.y);
                                    highp float _7384 = _7316.x;
                                    highp float _7393 = mix(mix(float(_6248 <= textureLod(shadow_map, _7331, 0.0).x), float(_6248 <= textureLod(shadow_map, _7331 + _7220, 0.0).x), _7384), mix(float(_6248 <= textureLod(shadow_map, _7331 + _7228, 0.0).x), float(_6248 <= textureLod(shadow_map, _7331 + _7211, 0.0).x), _7384), _7316.y);
                                    float mp_copy_7393 = _7393;
                                    highp vec2 _7427 = clamp(_5950 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10647), _7168, _7172);
                                    highp vec2 _7438 = (vec2(_7427.x, 1.0 - _7427.y) / _7168) - vec2(0.5);
                                    highp vec2 _7440 = floor(_7438);
                                    highp vec2 _7443 = _7438 - _7440;
                                    highp vec2 _7448 = (_7440 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7458 = vec2((_7196 + _7448.x) * _6254, _7448.y);
                                    highp float _7511 = _7443.x;
                                    highp float _7520 = mix(mix(float(_6248 <= textureLod(shadow_map, _7458, 0.0).x), float(_6248 <= textureLod(shadow_map, _7458 + _7220, 0.0).x), _7511), mix(float(_6248 <= textureLod(shadow_map, _7458 + _7228, 0.0).x), float(_6248 <= textureLod(shadow_map, _7458 + _7211, 0.0).x), _7511), _7443.y);
                                    float mp_copy_7520 = _7520;
                                    highp vec2 _7554 = clamp(_5950 + (vec2(0.707099974155426025390625) * _10647), _7168, _7172);
                                    highp vec2 _7565 = (vec2(_7554.x, 1.0 - _7554.y) / _7168) - vec2(0.5);
                                    highp vec2 _7567 = floor(_7565);
                                    highp vec2 _7570 = _7565 - _7567;
                                    highp vec2 _7575 = (_7567 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7585 = vec2((_7196 + _7575.x) * _6254, _7575.y);
                                    highp float _7638 = _7570.x;
                                    highp float _7647 = mix(mix(float(_6248 <= textureLod(shadow_map, _7585, 0.0).x), float(_6248 <= textureLod(shadow_map, _7585 + _7220, 0.0).x), _7638), mix(float(_6248 <= textureLod(shadow_map, _7585 + _7228, 0.0).x), float(_6248 <= textureLod(shadow_map, _7585 + _7211, 0.0).x), _7638), _7570.y);
                                    float mp_copy_7647 = _7647;
                                    _10672 = (((mp_copy_7266 + mp_copy_7393) + mp_copy_7520) + mp_copy_7647) * 0.25;
                                }
                                else
                                {
                                    int _6420 = (_6262 > 0.5) ? 17 : 16;
                                    float _10667 = 0.0;
                                    _10667 = 0.0;
                                    float _6448 = 0.0;
                                    for (int _10649 = 0; _10649 < 17; _10667 = _6448, _10649++)
                                    {
                                        if (_10649 >= _6420)
                                        {
                                            break;
                                        }
                                        vec2 _10650 = vec2(0.0);
                                        do
                                        {
                                            if (_10649 == 0)
                                            {
                                                _10650 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10649 == 1)
                                            {
                                                _10650 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10649 == 2)
                                            {
                                                _10650 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10649 == 3)
                                            {
                                                _10650 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10649 == 4)
                                            {
                                                _10650 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10649 == 5)
                                            {
                                                _10650 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10649 == 6)
                                            {
                                                _10650 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10649 == 7)
                                            {
                                                _10650 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10649 == 8)
                                            {
                                                _10650 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10649 == 9)
                                            {
                                                _10650 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10649 == 10)
                                            {
                                                _10650 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10649 == 11)
                                            {
                                                _10650 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10649 == 12)
                                            {
                                                _10650 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10649 == 13)
                                            {
                                                _10650 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10649 == 14)
                                            {
                                                _10650 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10649 == 15)
                                            {
                                                _10650 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10650 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10652 = vec2(0.0);
                                        do
                                        {
                                            if (_10649 < 3)
                                            {
                                                _10652 = vec2(float(_10649) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10649 < 6)
                                            {
                                                _10652 = vec2((float(_10649 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10649 < 11)
                                            {
                                                _10652 = vec2((float(_10649 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10649 < 14)
                                            {
                                                _10652 = vec2((float(_10649 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10652 = vec2(float(_10649 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6437 = mix(_10650, _10652, vec2(_6262));
                                        float _7088 = _6437.x;
                                        float _7092 = _6437.y;
                                        highp vec2 _7118 = clamp(_5950 + (vec2((_7088 * _10640) - (_7092 * _10644), (_7088 * _10644) + (_7092 * _10640)) * _10647), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7127 = _7118.y;
                                        highp vec2 _7128 = vec2((float(_10441) + _7118.x) * _6254, _7127);
                                        _7128.y = 1.0 - _7127;
                                        highp float _7140 = float(_6248 <= textureLod(shadow_map, _7128, 0.0).x);
                                        float mp_copy_7140 = _7140;
                                        _6448 = _10667 + mp_copy_7140;
                                    }
                                    _10672 = _10667 / float(_6420);
                                }
                                _10671 = _10672;
                            }
                            bool _6493 = _10441 == (_5860 - 1);
                            bool _6499 = false;
                            if (_6493)
                            {
                                _6499 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6499 = _6493;
                            }
                            float _10674 = 0.0;
                            if (_6499)
                            {
                                highp vec2 _6506 = vec2(frag_info.shadow_fade / _10607);
                                highp vec2 _6514 = smoothstep(vec2(0.0), _6506, _5950) * smoothstep(vec2(0.0), _6506, _6107);
                                _10674 = mix(1.0, _10671, _6514.x * _6514.y);
                            }
                            else
                            {
                                _10674 = _10671;
                            }
                            _10737 = _10445 + _6010;
                            _10734 = _10443 + (_6010 * _10674);
                        }
                        else
                        {
                            _10737 = _10445;
                            _10734 = _10443;
                        }
                        _10736 = _10737;
                        _10733 = _10734;
                    }
                    else
                    {
                        _10736 = _10445;
                        _10733 = _10443;
                    }
                    _10735 = _10736;
                    _10732 = _10733;
                }
                else
                {
                    _10735 = _10445;
                    _10732 = _10443;
                }
            }
            _10444 = _10445;
            _10442 = _10443;
        }
        else
        {
            _10444 = 0.0;
            _10442 = 0.0;
        }
        _10448 = mix(_10442 + (1.0 - _10444), 1.0, _10440);
    }
    else
    {
        _10448 = 1.0;
    }
    vec3 mp_copy_10449 = vec3(0.0);
    float _5351 = _5329 * _10448;
    bool _7655 = view_info.camera_forward.w > 0.5;
    highp vec3 _10449 = vec3(0.0);
    if (_7655)
    {
        _10449 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10449 = normalize(v_viewvector);
    }
    highp float _7699 = 0.0;
    mp_copy_10449 = _10449;
    vec3 _5360 = mix(frag_info.dielectric_f0.xyz, _5291, vec3(_4459));
    float _5364 = max(dot(_10390, _10449), 0.0);
    float _5368 = max(dot(_4325, _10449), 0.0);
    vec3 _5372 = reflect(-mp_copy_10449, _10390);
    highp vec2 _10450 = vec2(0.0);
    do
    {
        _7699 = frag_info.punctual_dims.x;
        if (_7699 < 0.5)
        {
            _10450 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7711 = v_position - frag_info.camera_position.xyz;
            highp float _7726 = dot(_7711, frag_info.camera_forward.xyz);
            highp float _7732 = max(_7726, 9.9999997473787516355514526367188e-05);
            highp vec2 _7835 = (vec3(dot(_7711, frag_info.camera_right.xyz), dot(_7711, frag_info.camera_up.xyz), _7732).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7732, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7850 = float(int(((((clamp(floor((log2(max(_7726 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7835.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7835.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10450 = vec2(textureLod(punctual_index, vec2((mod(_7850, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7850 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10450 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5377 = int(_10450.x + 0.5);
    mediump int _5381 = int(_10450.y + 0.5);
    highp vec3 _10499 = vec3(0.0);
    _10499 = vec3(0.0);
    highp vec3 _10848 = vec3(0.0);
    for (int _10451 = 0; _10451 < _5381; _10499 = _10848, _10451++)
    {
        highp float hp_copy_10556 = 0.0;
        highp float _7883 = float(_5377 + _10451);
        highp float _7914 = (float(int(textureLod(punctual_index, vec2((mod(_7883, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7883 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7699;
        highp vec4 _7918 = textureLod(punctual_lights, vec2(0.0625, _7914), 0.0);
        highp vec4 _7935 = textureLod(punctual_lights, vec2(0.1875, _7914), 0.0);
        highp float _5399 = _7918.w;
        highp vec3 _5401 = _7935.xyz;
        vec3 _10542 = vec3(0.0);
        highp vec3 _10553 = vec3(0.0);
        float _10556 = 0.0;
        if (_5399 < 0.5)
        {
            _10556 = _10438;
            _10553 = _5401;
            _10542 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7914), 0.0).xyz);
        }
        else
        {
            highp vec3 _5409 = _7918.xyz - v_position;
            highp float _5412 = dot(_5409, _5409);
            highp float _5416 = inversesqrt(max(_5412, 9.9999999392252902907785028219223e-09));
            highp vec3 _5417 = _5409 * _5416;
            vec3 mp_copy_5417 = _5417;
            highp float _5419 = _7935.w;
            highp float _5424 = (_5412 * _5419) * _5419;
            highp float _5429 = clamp(1.0 - (_5424 * _5424), 0.0, 1.0);
            float mp_copy_5429 = _5429;
            if (_5429 <= 0.0)
            {
                _10848 = _10499;
                continue;
            }
            highp vec4 _7952 = textureLod(punctual_lights, vec2(0.4375, _7914), 0.0);
            highp float _5437 = _7952.w;
            float _10558 = 0.0;
            if (_5437 > 0.0)
            {
                highp float _5464 = (_10438 * _10438) + ((_5437 * 0.5) * _5416);
                float mp_copy_5464 = _5464;
                _10558 = sqrt(min(mp_copy_5464, 1.0));
            }
            else
            {
                _10558 = _10438;
            }
            highp vec3 _5471 = _5401 * ((mp_copy_5429 * mp_copy_5429) / max(pow(max(_5412, _5437 * _5437), _7952.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10554 = vec3(0.0);
            if (_5399 > 1.5)
            {
                highp vec4 _7969 = textureLod(punctual_lights, vec2(0.3125, _7914), 0.0);
                highp float _5490 = clamp((dot(normalize(_7969.xyz), -mp_copy_5417) * _7969.w) + _7952.x, 0.0, 1.0);
                float mp_copy_5490 = _5490;
                highp vec3 _5495 = _5471 * (mp_copy_5490 * mp_copy_5490);
                if (_5490 <= 0.0)
                {
                    _10848 = _10499;
                    continue;
                }
                bool _5501 = _5490 > 0.0;
                bool _5507 = false;
                if (_5501)
                {
                    _5507 = _7952.y > (-0.5);
                }
                else
                {
                    _5507 = _5501;
                }
                bool _5513 = false;
                if (_5507)
                {
                    _5513 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5513 = _5507;
                }
                highp vec3 _10555 = vec3(0.0);
                if (_5513)
                {
                    float _10533 = 0.0;
                    do
                    {
                        highp vec4 _8081 = mat4(textureLod(punctual_lights, vec2(0.5625, _7914), 0.0), textureLod(punctual_lights, vec2(0.6875, _7914), 0.0), textureLod(punctual_lights, vec2(0.8125, _7914), 0.0), textureLod(punctual_lights, vec2(0.9375, _7914), 0.0)) * vec4(v_position + (_4325 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8083 = _8081.w;
                        if (_8083 <= 0.0)
                        {
                            _10533 = 1.0;
                            break;
                        }
                        highp vec3 _8092 = _8081.xyz / vec3(_8083);
                        highp vec2 _8097 = (_8092.xy * 0.5) + vec2(0.5);
                        highp float _8099 = _8097.x;
                        bool _8100 = _8099 < 0.0;
                        bool _8107 = false;
                        if (!_8100)
                        {
                            _8107 = _8099 > 1.0;
                        }
                        else
                        {
                            _8107 = _8100;
                        }
                        bool _8114 = false;
                        if (!_8107)
                        {
                            _8114 = _8097.y < 0.0;
                        }
                        else
                        {
                            _8114 = _8107;
                        }
                        bool _8121 = false;
                        if (!_8114)
                        {
                            _8121 = _8097.y > 1.0;
                        }
                        else
                        {
                            _8121 = _8114;
                        }
                        bool _8128 = false;
                        if (!_8121)
                        {
                            _8128 = _8092.z < 0.0;
                        }
                        else
                        {
                            _8128 = _8121;
                        }
                        bool _8135 = false;
                        if (!_8128)
                        {
                            _8135 = _8092.z > 1.0;
                        }
                        else
                        {
                            _8135 = _8128;
                        }
                        if (_8135)
                        {
                            _10533 = 1.0;
                            break;
                        }
                        highp float _8142 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8147 = frag_info.shadow_cascade_count + float(int(_7952.y + 0.5));
                        highp float _8152 = _8092.z - frag_info.spot_shadow_params.y;
                        highp float _8163 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8163 = _8163;
                        highp vec2 _8170 = vec2(cos(mp_copy_8163), sin(mp_copy_8163)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8172 = _8170.x;
                        highp float _8174 = _8170.y;
                        highp vec2 _8182 = vec2(_8172 - _8174, _8172 + _8174) * 0.707106769084930419921875;
                        highp float _8375 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8099, 0.0, 1.0)) / _8142, 1.0 - clamp(_8097.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8375 = _8375;
                        highp vec2 _8190 = _8097 + _8170;
                        highp float _8397 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8190.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8190.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8397 = _8397;
                        highp vec2 _8198 = _8097 - _8170;
                        highp float _8419 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8198.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8198.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8419 = _8419;
                        highp vec2 _8211 = _8097 + vec2(-_8174, _8172);
                        highp float _8441 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8211.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8211.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8441 = _8441;
                        highp vec2 _8224 = _8097 + vec2(_8174, -_8172);
                        highp float _8463 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8224.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8224.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8463 = _8463;
                        float _8229 = (((mp_copy_8375 + mp_copy_8397) + mp_copy_8419) + mp_copy_8441) + mp_copy_8463;
                        if ((_8229 < 0.5) || (_8229 > 4.5))
                        {
                            _10533 = _8229 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8241 = _8097 + _8182;
                        highp float _8485 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8241.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8241.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8485 = _8485;
                        highp vec2 _8248 = _8097 - _8182;
                        highp float _8507 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8248.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8248.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8507 = _8507;
                        highp float _8256 = _8182.y;
                        highp float _8259 = _8182.x;
                        highp vec2 _8261 = _8097 + vec2(-_8256, _8259);
                        highp float _8529 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8261.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8261.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8529 = _8529;
                        highp vec2 _8274 = _8097 + vec2(_8256, -_8259);
                        highp float _8551 = float(_8152 <= textureLod(shadow_map, vec2((_8147 + clamp(_8274.x, 0.0, 1.0)) / _8142, 1.0 - clamp(_8274.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8551 = _8551;
                        _10533 = (_8229 + (((mp_copy_8485 + mp_copy_8507) + mp_copy_8529) + mp_copy_8551)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10555 = _5495 * _10533;
                }
                else
                {
                    _10555 = _5495;
                }
                _10554 = _10555;
            }
            else
            {
                _10554 = _5471;
            }
            _10556 = _10558;
            _10553 = _10554;
            _10542 = _5417;
        }
        hp_copy_10556 = _10556;
        highp vec3 _10571 = vec3(0.0);
        highp vec3 _10572 = vec3(0.0);
        do
        {
            float _8634 = max(dot(_10390, _10542), 0.0);
            highp float hp_copy_8634 = _8634;
            if (_8634 <= 0.0)
            {
                _10572 = vec3(0.0);
                _10571 = vec3(0.0);
                break;
            }
            float _8640 = max(_5364, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8640 = _8640;
            vec3 _8643 = _10542 + mp_copy_10449;
            float _8646 = dot(_8643, _8643);
            vec3 _10569 = vec3(0.0);
            vec3 _10570 = vec3(0.0);
            if (_8646 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8654 = _8643 * inversesqrt(_8646);
                float _10568 = 0.0;
                do
                {
                    float _8711 = dot(_10390, _8654);
                    if (_8711 <= 0.0)
                    {
                        _10568 = 0.0;
                        break;
                    }
                    float _8718 = _10556 * _10556;
                    vec3 _8721 = cross(_10390, _8654);
                    float _8724 = _8711 * _8718;
                    float _8733 = _8718 / (dot(_8721, _8721) + (_8724 * _8724));
                    _10568 = min((_8733 * _8733) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8771 = _5360 + ((vec3(1.0) - _5360) * pow(clamp(1.0 - max(dot(_8654, _10449), 0.0), 0.0, 1.0), 5.0));
                _10570 = (_8771 * min(_10568 * (0.5 / max(mix((2.0 * hp_copy_8634) * _8640, hp_copy_8634 + hp_copy_8640, hp_copy_10556 * hp_copy_10556), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10569 = _8771;
            }
            else
            {
                _10570 = vec3(0.0);
                _10569 = _5360;
            }
            _10572 = (_10570 * _10553) * _8634;
            _10571 = (((((vec3(1.0) - _10569) * (1.0 - _4459)) * _5291) * 0.3183098733425140380859375) * _10553) * _8634;
            break;
        } while(false);
        _10848 = _10499 + (_10571 + _10572);
    }
    mat3 _5568 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5576 = _5568 * vec3(_10390.x, _10390.y, _10390.z);
    vec3 _10452 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _8818 = _5372 + (((step(vec3(0.0), _5372) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_8818 = _8818;
        highp vec3 _8820 = vec3(1.0) / hp_copy_8818;
        highp vec3 _8837 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _8820, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _8820);
        _10452 = normalize((v_position + (_5372 * max(min(min(_8837.x, _8837.y), _8837.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _10452 = _5372;
    }
    bool _9065 = false;
    highp vec3 hp_copy_10453 = vec3(0.0);
    vec3 _5581 = _5568 * _10452;
    float _8884 = _5576.y;
    float _8891 = _5576.z;
    float _8898 = _5576.x;
    float _8906 = 1.09254801273345947265625 * _8898;
    vec3 _5584 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8884))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8891))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8898))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8906 * _8884))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8884) * _8891))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8891) * _8891) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8906 * _8891))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8898 * _8898) - (_8884 * _8884)))), vec3(0.0));
    highp vec3 hp_copy_5584 = _5584;
    vec3 _10453 = vec3(0.0);
    do
    {
        _9065 = radiance_layout_info.mip_layout > 0.5;
        if (_9065)
        {
            vec2 _9144 = vec2(atan(_5581.z, _5581.x), asin(clamp(_5581.y, -1.0, 1.0)));
            highp vec2 hp_copy_9144 = _9144;
            _10453 = textureLod(prefiltered_radiance, (hp_copy_9144 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10438, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9163 = vec2(atan(_5581.z, _5581.x), asin(clamp(_5581.y, -1.0, 1.0)));
        highp vec2 hp_copy_9163 = _9163;
        highp vec2 _9168 = (hp_copy_9163 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _9075 = clamp(_9168.y, 0.00390625, 0.99609375);
        float _9079 = clamp(_10438, 0.0, 1.0) * 7.0;
        float _9081 = floor(_9079);
        highp float _9100 = _9168.x;
        _10453 = mix(textureLod(prefiltered_radiance, vec2(_9100, (_9081 + _9075) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9100, (min(_9081 + 1.0, 7.0) + _9075) * 0.125), 0.0).xyz, vec3(_9079 - _9081));
        break;
    } while(false);
    hp_copy_10453 = _10453;
    highp vec3 _10459 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_10454 = vec3(0.0);
        vec3 _10454 = vec3(0.0);
        do
        {
            if (_9065)
            {
                vec2 _9273 = vec2(atan(_5581.z, _5581.x), asin(clamp(_5581.y, -1.0, 1.0)));
                highp vec2 hp_copy_9273 = _9273;
                _10454 = textureLod(prefiltered_radiance_b, (hp_copy_9273 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10438, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9292 = vec2(atan(_5581.z, _5581.x), asin(clamp(_5581.y, -1.0, 1.0)));
            highp vec2 hp_copy_9292 = _9292;
            highp vec2 _9297 = (hp_copy_9292 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9204 = clamp(_9297.y, 0.00390625, 0.99609375);
            float _9208 = clamp(_10438, 0.0, 1.0) * 7.0;
            float _9210 = floor(_9208);
            highp float _9229 = _9297.x;
            _10454 = mix(textureLod(prefiltered_radiance_b, vec2(_9229, (_9210 + _9204) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9229, (min(_9210 + 1.0, 7.0) + _9204) * 0.125), 0.0).xyz, vec3(_9208 - _9210));
            break;
        } while(false);
        hp_copy_10454 = _10454;
        _10459 = hp_copy_10453 + hp_copy_10454;
    }
    else
    {
        _10459 = _10453;
    }
    float _5599 = frag_info.environment_intensity;
    highp float hp_copy_5599 = _5599;
    vec2 _5612 = clamp(vec2(_5368, _10438), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5614 = texture(brdf_lut, vec2(_5612.x * 0.3333333432674407958984375, _5612.y));
    float _5618 = _5614.x;
    float _5621 = _5614.y;
    vec3 _5623 = ((_5360 + ((max(vec3(1.0 - _10438), _5360) - _5360) * pow(clamp(1.0 - _5368, 0.0, 1.0), 5.0))) * _5618) + vec3(_5621);
    float _5629 = 1.0 - (_5618 + _5621);
    vec3 _5633 = vec3(1.0) - _5360;
    vec3 _5636 = _5360 + (_5633 * vec3(0.0476190485060214996337890625));
    vec3 _5647 = ((_5623 * _5629) * _5636) / (vec3(1.0) - (_5636 * _5629));
    float _5650 = 1.0 - _4459;
    float _10474 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _10474 = clamp((pow(_5364 + _10469, exp2(((-16.0) * _10438) - 1.0)) - 1.0) + _10469, 0.0, 1.0);
    }
    else
    {
        _10474 = _10469;
    }
    highp vec3 _10509 = vec3(0.0);
    if (_5316)
    {
        highp vec3 _10492 = vec3(0.0);
        highp vec3 _10493 = vec3(0.0);
        do
        {
            float _9386 = max(dot(_10390, _10484), 0.0);
            highp float hp_copy_9386 = _9386;
            if (_9386 <= 0.0)
            {
                _10493 = vec3(0.0);
                _10492 = vec3(0.0);
                break;
            }
            float _9392 = max(_5364, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9392 = _9392;
            vec3 _9395 = _10484 + mp_copy_10449;
            float _9398 = dot(_9395, _9395);
            vec3 _10490 = vec3(0.0);
            vec3 _10491 = vec3(0.0);
            if (_9398 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9406 = _9395 * inversesqrt(_9398);
                float _10489 = 0.0;
                do
                {
                    float _9463 = dot(_10390, _9406);
                    if (_9463 <= 0.0)
                    {
                        _10489 = 0.0;
                        break;
                    }
                    float _9470 = _10438 * _10438;
                    vec3 _9473 = cross(_10390, _9406);
                    float _9476 = _9463 * _9470;
                    float _9485 = _9470 / (dot(_9473, _9473) + (_9476 * _9476));
                    _10489 = min((_9485 * _9485) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9523 = _5360 + (_5633 * pow(clamp(1.0 - max(dot(_9406, _10449), 0.0), 0.0, 1.0), 5.0));
                _10491 = (_9523 * min(_10489 * (0.5 / max(mix((2.0 * hp_copy_9386) * _9392, hp_copy_9386 + hp_copy_9392, hp_copy_10438 * hp_copy_10438), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10490 = _9523;
            }
            else
            {
                _10491 = vec3(0.0);
                _10490 = _5360;
            }
            _10493 = (_10491 * frag_info.directional_light_color.xyz) * _9386;
            _10492 = (((((vec3(1.0) - _10490) * _5650) * _5291) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9386;
            break;
        } while(false);
        _10509 = _10499 + ((_10492 + _10493) * _5351);
    }
    else
    {
        _10509 = _10499;
    }
    bool _5741 = _FogInfo.params0.y > 0.5;
    bool _5747 = false;
    if (_5741)
    {
        _5747 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5747 = _5741;
    }
    highp vec3 _10512 = vec3(0.0);
    if (_5747)
    {
        vec3 mp_copy_10510 = vec3(0.0);
        highp vec3 _10510 = vec3(0.0);
        if (_7655)
        {
            _10510 = -view_info.camera_forward.xyz;
        }
        else
        {
            _10510 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_10511 = vec3(0.0);
        mp_copy_10510 = _10510;
        vec3 _5752 = _5568 * (-mp_copy_10510);
        vec3 _10511 = vec3(0.0);
        do
        {
            if (_9065)
            {
                vec2 _9645 = vec2(atan(_5752.z, _5752.x), asin(clamp(_5752.y, -1.0, 1.0)));
                highp vec2 hp_copy_9645 = _9645;
                _10511 = textureLod(prefiltered_radiance, (hp_copy_9645 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9664 = vec2(atan(_5752.z, _5752.x), asin(clamp(_5752.y, -1.0, 1.0)));
            highp vec2 hp_copy_9664 = _9664;
            highp vec2 _9669 = (hp_copy_9664 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9576 = clamp(_9669.y, 0.00390625, 0.99609375);
            float _9582 = floor(0.0);
            highp float _9601 = _9669.x;
            _10511 = mix(textureLod(prefiltered_radiance, vec2(_9601, (_9582 + _9576) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9601, (min(_9582 + 1.0, 7.0) + _9576) * 0.125), 0.0).xyz, vec3(-_9582));
            break;
        } while(false);
        hp_copy_10511 = _10511;
        _10512 = hp_copy_10511 * hp_copy_5599;
    }
    else
    {
        _10512 = _FogInfo.color.xyz;
    }
    highp vec4 _5767 = vec4(min(((((((_5647 + ((_5291 * _5650) * ((vec3(1.0) - _5623) - _5647))) * (hp_copy_5584 * hp_copy_5599)) * vec3(_4493)) + (((_5623 * (_10459 * _5599)) * 1.0) * _10474)) * mix(1.0, _5351, frag_info.radiance_blend.y)) + (_10509 * mix(1.0, _10469, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _10413, vec3(65504.0)), 1.0) * _10898;
    highp vec4 _10527 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _10527 = _5767;
            break;
        }
        int _9713 = int(_FogInfo.params0.x + 0.5);
        if (_9713 == 0)
        {
            _10527 = _5767;
            break;
        }
        highp float _10514 = 0.0;
        if (_7655)
        {
            _10514 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _10514 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_10514 > _FogInfo.params1.w))
        {
            _10527 = _5767;
            break;
        }
        float _10518 = 0.0;
        if (_9713 == 1)
        {
            _10518 = clamp((_10514 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _10519 = 0.0;
            if (_9713 == 2)
            {
                highp float _10517 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _10515 = vec3(0.0);
                    if (_7655)
                    {
                        _10515 = v_position - (view_info.camera_forward.xyz * _10514);
                    }
                    else
                    {
                        _10515 = v_position + v_viewvector;
                    }
                    highp float _9804 = -_FogInfo.params2.y;
                    highp float _9811 = _FogInfo.params1.x * exp(_9804 * (_10515.y - _FogInfo.params2.x));
                    highp float _9828 = _FogInfo.params2.y * (v_position.y - _10515.y);
                    highp float _10516 = 0.0;
                    if (abs(_9828) > 0.00124999997206032276153564453125)
                    {
                        _10516 = (_9811 - (_FogInfo.params1.x * exp(_9804 * (v_position.y - _FogInfo.params2.x)))) / _9828;
                    }
                    else
                    {
                        _10516 = _9811;
                    }
                    _10517 = _10516 * max(_10514 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _10517 = _FogInfo.params1.x * max(_10514 - _FogInfo.params1.y, 0.0);
                }
                _10519 = 1.0 - exp(-_10517);
            }
            else
            {
                highp float _9766 = _FogInfo.params1.x * max(_10514 - _FogInfo.params1.y, 0.0);
                _10519 = 1.0 - exp((-_9766) * _9766);
            }
            _10518 = _10519;
        }
        highp float _9868 = min(_10518, _FogInfo.params0.z);
        if (_9868 <= 0.0)
        {
            _10527 = _5767;
            break;
        }
        highp vec3 _9881 = mix(_FogInfo.color.xyz, _10512, vec3(_FogInfo.params0.w));
        bool _9884 = _FogInfo.sun.w > 0.5;
        bool _9890 = false;
        if (_9884)
        {
            _9890 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _9890 = _9884;
        }
        vec3 _10523 = vec3(0.0);
        if (_9890)
        {
            vec3 mp_copy_10520 = vec3(0.0);
            highp vec3 _10520 = vec3(0.0);
            if (_7655)
            {
                _10520 = -view_info.camera_forward.xyz;
            }
            else
            {
                _10520 = normalize(v_viewvector);
            }
            mp_copy_10520 = _10520;
            highp float _9906 = pow(max(dot(-mp_copy_10520, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_9906 = _9906;
            _10523 = _9881 + ((_FogInfo.sun.xyz * mp_copy_9906) * _FogInfo.params2.z);
        }
        else
        {
            _10523 = _9881;
        }
        highp float _9919 = _5767.w;
        float mp_copy_9919 = _9919;
        _10527 = vec4(mix(_5767.xyz, _10523 * mp_copy_9919, vec3(_9868)), _9919);
        break;
    } while(false);
    vec4 _10529 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10529 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10529 = _10527;
        break;
    } while(false);
    frag_color = _10529;
    float _10530 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10530 = 1.0;
    }
    else
    {
        _10530 = abs(frag_info.fade);
    }
    frag_color *= _10530;
}

