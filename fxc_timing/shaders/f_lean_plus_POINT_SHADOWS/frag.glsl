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
    highp float _4619 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4619 = _4619;
    vec3 _4623 = normalize(v_normal) * mp_copy_4619;
    vec4 _4665 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4668 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _11093 = vec2(0.0);
    if (_4668)
    {
        highp vec2 _11092 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _11092 = v_texture_coords_1;
        }
        else
        {
            _11092 = v_texture_coords;
        }
        highp vec2 _4871 = _11092 * texture_transforms.base_color_transform.zw;
        highp float _4877 = _4871.x;
        highp float _4882 = _4871.y;
        _11093 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4877) + (texture_transforms.base_color_rotation.y * _4882), ((-texture_transforms.base_color_rotation.y) * _4877) + (texture_transforms.base_color_rotation.x * _4882));
    }
    else
    {
        _11093 = v_texture_coords;
    }
    vec4 _4682 = texture(base_color_texture, _11093);
    vec3 _4684 = _4682.xyz;
    float _11709 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4682.w * _4665.w) * frag_info.color.w);
    vec3 _11108 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _11096 = vec2(0.0);
        if (_4668)
        {
            highp vec2 _11095 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _11095 = v_texture_coords_1;
            }
            else
            {
                _11095 = v_texture_coords;
            }
            highp vec2 _4966 = _11095 * texture_transforms.normal_transform.zw;
            highp float _4972 = _4966.x;
            highp float _4977 = _4966.y;
            _11096 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4972) + (texture_transforms.normal_rotation.y * _4977), ((-texture_transforms.normal_rotation.y) * _4972) + (texture_transforms.normal_rotation.x * _4977));
        }
        else
        {
            _11096 = v_texture_coords;
        }
        vec3 _5022 = ((texture(normal_texture, _11096).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _5026 = _5022.xy * vec2(frag_info.normal_scale);
        vec3 _10775 = _5022;
        _10775.x = _5026.x;
        _10775.y = _5026.y;
        highp vec3 _5032 = -v_viewvector;
        highp vec3 _5122 = dFdx(_5032);
        highp vec3 _5124 = dFdy(_5032);
        highp vec2 _5126 = dFdx(_11096);
        highp vec2 _5128 = dFdy(_11096);
        bvec2 _11711 = bvec2(length(_5126) == 0.0);
        highp vec2 _11712 = vec2(_11711.x ? vec2(1.0, 0.0).x : _5126.x, _11711.y ? vec2(1.0, 0.0).y : _5126.y);
        bvec2 _11713 = bvec2(length(_5128) == 0.0);
        highp vec2 _11714 = vec2(_11713.x ? vec2(0.0, 1.0).x : _5128.x, _11713.y ? vec2(0.0, 1.0).y : _5128.y);
        highp vec3 _5141 = cross(_5124, _4623);
        highp vec3 _5144 = cross(_4623, _5122);
        highp float _5169 = (dot(cross(_5122, _5124), _4623) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _5172 = ((_5141 * _11712.x) + (_5144 * _11714.x)) * _5169;
        highp float _11103 = 0.0;
        if (gl_FrontFacing)
        {
            _11103 = -_5169;
        }
        else
        {
            _11103 = _5169;
        }
        highp vec3 _5182 = ((_5141 * _11712.y) + (_5144 * _11714.y)) * _11103;
        highp float _5191 = inversesqrt(max(max(dot(_5172, _5172), dot(_5182, _5182)), 9.9999996826552253889678874634872e-21));
        vec3 _5063 = v_tangent.xyz - (_4623 * dot(_4623, v_tangent.xyz));
        highp float _5066 = dot(_5063, _5063);
        bool _5068 = _5066 > 1.0000000133514319600180897396058e-10;
        bool _5075 = false;
        if (_5068)
        {
            _5075 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _5075 = _5068;
        }
        mat3 _11106 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_5075)
        {
            highp vec3 _5080 = _5063 * inversesqrt(_5066);
            _11106 = mat3(_5080, normalize(cross(_4623, _5080)) * sign(v_tangent.w), _4623);
        }
        else
        {
            _11106 = mat3(_5172 * _5191, _5182 * _5191, _4623);
        }
        _11108 = normalize(_11106 * _10775);
    }
    else
    {
        _11108 = _4623;
    }
    highp vec2 _11110 = vec2(0.0);
    if (_4668)
    {
        highp vec2 _11109 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _11109 = v_texture_coords_1;
        }
        else
        {
            _11109 = v_texture_coords;
        }
        highp vec2 _5259 = _11109 * texture_transforms.metallic_roughness_transform.zw;
        highp float _5265 = _5259.x;
        highp float _5270 = _5259.y;
        _11110 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _5265) + (texture_transforms.metallic_roughness_rotation.y * _5270), ((-texture_transforms.metallic_roughness_rotation.y) * _5265) + (texture_transforms.metallic_roughness_rotation.x * _5270));
    }
    else
    {
        _11110 = v_texture_coords;
    }
    vec4 _4751 = texture(metallic_roughness_texture, _11110);
    float _4757 = clamp(_4751.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4764 = clamp(_4751.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _11112 = vec2(0.0);
    if (_4668)
    {
        highp vec2 _11111 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _11111 = v_texture_coords_1;
        }
        else
        {
            _11111 = v_texture_coords;
        }
        highp vec2 _5330 = _11111 * texture_transforms.occlusion_transform.zw;
        highp float _5336 = _5330.x;
        highp float _5341 = _5330.y;
        _11112 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _5336) + (texture_transforms.occlusion_rotation.y * _5341), ((-texture_transforms.occlusion_rotation.y) * _5336) + (texture_transforms.occlusion_rotation.x * _5341));
    }
    else
    {
        _11112 = v_texture_coords;
    }
    float _11113 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _11113 = texture(occlusion_texture, _11112).x;
    }
    else
    {
        _11113 = 1.0;
    }
    float _4791 = 1.0 - ((1.0 - _11113) * frag_info.occlusion_strength);
    highp vec2 _11115 = vec2(0.0);
    if (_4668)
    {
        highp vec2 _11114 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _11114 = v_texture_coords_1;
        }
        else
        {
            _11114 = v_texture_coords;
        }
        highp vec2 _5401 = _11114 * texture_transforms.emissive_transform.zw;
        highp float _5407 = _5401.x;
        highp float _5412 = _5401.y;
        _11115 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5407) + (texture_transforms.emissive_rotation.y * _5412), ((-texture_transforms.emissive_rotation.y) * _5407) + (texture_transforms.emissive_rotation.x * _5412));
    }
    else
    {
        _11115 = v_texture_coords;
    }
    vec3 _4810 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _11131 = vec3(0.0);
    if (dot(abs(_4810), vec3(1.0)) > 0.0)
    {
        vec3 _4819 = texture(emissive_texture, _11115).xyz;
        _11131 = mix(_4819 * vec3(0.077399380505084991455078125), pow((_4819 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4819)) * _4810;
    }
    else
    {
        _11131 = vec3(0.0);
    }
    highp float hp_copy_11156 = 0.0;
    vec3 _5592 = vec4((mix(_4684 * vec3(0.077399380505084991455078125), pow((_4684 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4684)) * _4665.xyz) * frag_info.color.xyz, _11709).xyz;
    vec3 _6104 = dFdx(_11108);
    vec3 _6106 = dFdy(_11108);
    float _11156 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _11156 = sqrt(clamp((_4764 * _4764) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_6104, _6104), dot(_6106, _6106))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _11156 = _4764;
    }
    hp_copy_11156 = _11156;
    float _11185 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _11185 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _11185 = _4791;
    }
    bool _5617 = frag_info.has_directional_light > 0.5;
    float _11157 = 0.0;
    vec3 _11199 = vec3(0.0);
    if (_5617)
    {
        highp vec3 _5623 = -normalize(frag_info.directional_light_direction.xyz);
        _11199 = _5623;
        _11157 = dot(_4623, _5623);
    }
    else
    {
        _11199 = vec3(0.0);
        _11157 = 0.0;
    }
    float _5630 = clamp(_11157 * 6.666666507720947265625, 0.0, 1.0);
    bool _5639 = false;
    if (_5617)
    {
        _5639 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5639 = _5617;
    }
    float _11166 = 0.0;
    if (_5639 && (_5630 > 0.0))
    {
        int _6185 = int(frag_info.shadow_cascade_count);
        float _6380 = max(dot(_4623, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _6383 = _6380 * _6380;
        highp vec3 _6403 = v_position + (_4623 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _6383, 0.0)) / _6383, 8.0))));
        highp float _6191 = frag_info.directional_light_color.w * 0.5;
        float _6193 = frag_info.dielectric_f0.w;
        highp float hp_copy_6193 = _6193;
        float _11158 = 0.0;
        if (_6193 > 0.0)
        {
            _11158 = smoothstep(_6193 - max(frag_info.shadow_fade, hp_copy_6193 * 0.100000001490116119384765625), _6193, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _11158 = 0.0;
        }
        float _11160 = 0.0;
        float _11162 = 0.0;
        if (_11158 < 1.0)
        {
            float _11161 = 0.0;
            float _11163 = 0.0;
            _11163 = 0.0;
            _11161 = 0.0;
            float _11520 = 0.0;
            float _11523 = 0.0;
            for (int _11159 = 0; _11159 < _6185; _11163 = _11523, _11161 = _11520, _11159++)
            {
                if (_11163 < 1.0)
                {
                    highp vec4 _6225 = vec4(_6403, 1.0);
                    highp vec4 _11392 = vec4(0.0);
                    highp float _11395 = 0.0;
                    if (_11159 == 0)
                    {
                        _11395 = frag_info.cascade_box_sizes.x;
                        _11392 = frag_info.light_space_matrix[0] * _6225;
                    }
                    else
                    {
                        highp vec4 _11393 = vec4(0.0);
                        highp float _11396 = 0.0;
                        if (_11159 == 1)
                        {
                            _11396 = frag_info.cascade_box_sizes.y;
                            _11393 = frag_info.light_space_matrix[1] * _6225;
                        }
                        else
                        {
                            highp vec4 _11394 = vec4(0.0);
                            highp float _11397 = 0.0;
                            if (_11159 == 2)
                            {
                                _11397 = frag_info.cascade_box_sizes.z;
                                _11394 = frag_info.light_space_matrix[2] * _6225;
                            }
                            else
                            {
                                _11397 = frag_info.cascade_box_sizes.w;
                                _11394 = frag_info.light_space_matrix[3] * _6225;
                            }
                            _11396 = _11397;
                            _11393 = _11394;
                        }
                        _11395 = _11396;
                        _11392 = _11393;
                    }
                    highp vec3 _6270 = _11392.xyz / vec3(_11392.w);
                    highp vec2 _6273 = _6270.xy * 0.5;
                    highp vec2 _6275 = _6273 + vec2(0.5);
                    highp float _6282 = max(frag_info.shadow_softness / _11395, frag_info.shadow_texel_size);
                    highp float _6284 = _6275.x;
                    bool _6286 = _6284 < _6282;
                    bool _6295 = false;
                    if (!_6286)
                    {
                        _6295 = _6284 > (1.0 - _6282);
                    }
                    else
                    {
                        _6295 = _6286;
                    }
                    bool _6303 = false;
                    if (!_6295)
                    {
                        _6303 = _6275.y < _6282;
                    }
                    else
                    {
                        _6303 = _6295;
                    }
                    bool _6312 = false;
                    if (!_6303)
                    {
                        _6312 = _6275.y > (1.0 - _6282);
                    }
                    else
                    {
                        _6312 = _6303;
                    }
                    bool _6319 = false;
                    if (!_6312)
                    {
                        _6319 = _6270.z < 0.0;
                    }
                    else
                    {
                        _6319 = _6312;
                    }
                    bool _6326 = false;
                    if (!_6319)
                    {
                        _6326 = _6270.z > 1.0;
                    }
                    else
                    {
                        _6326 = _6319;
                    }
                    float _11521 = 0.0;
                    float _11524 = 0.0;
                    if (!_6326)
                    {
                        highp vec2 _6419 = vec2(_6282);
                        highp vec2 _6424 = vec2(_6282 + max(_6191, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6432 = vec2(0.5) - _6273;
                        highp vec2 _6434 = smoothstep(_6419, _6424, _6275) * smoothstep(_6419, _6424, _6432);
                        float _11398 = 0.0;
                        if (_6191 > 0.0)
                        {
                            _11398 = _6434.x * _6434.y;
                        }
                        else
                        {
                            _11398 = 1.0;
                        }
                        float _6335 = min(_11398, 1.0 - _11163);
                        float _11522 = 0.0;
                        float _11525 = 0.0;
                        if (_6335 > 0.0)
                        {
                            highp float _6573 = _6270.z - (frag_info.shadow_bias / (7.0 * _11395));
                            highp float _6579 = 1.0 / (float(_6185) + frag_info.spot_shadow_params.x);
                            highp float _6581 = frag_info.directional_light_direction.w;
                            float mp_copy_6581 = _6581;
                            float _6587 = step(0.5, mp_copy_6581) * (1.0 - step(1.5, mp_copy_6581));
                            float _11428 = 0.0;
                            float _11432 = 0.0;
                            if (_6587 < 0.5)
                            {
                                highp float _6598 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6598 = _6598;
                                _11432 = sin(mp_copy_6598);
                                _11428 = cos(mp_copy_6598);
                            }
                            else
                            {
                                _11432 = 0.0;
                                _11428 = 1.0;
                            }
                            highp float _11435 = 0.0;
                            if ((_6581 > 1.5) && (_6581 < 2.5))
                            {
                                highp float _6622 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6627 = max(_6622 * _6573, frag_info.shadow_texel_size);
                                float _11424 = 0.0;
                                highp float _11425 = 0.0;
                                _11425 = 0.0;
                                _11424 = 0.0;
                                highp float _6649 = 0.0;
                                float _6652 = 0.0;
                                for (int _11423 = 0; _11423 < 9; _11425 = _6649, _11424 = _6652, _11423++)
                                {
                                    vec2 _11514 = vec2(0.0);
                                    do
                                    {
                                        if (_11423 == 0)
                                        {
                                            _11514 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_11423 == 1)
                                        {
                                            _11514 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_11423 == 2)
                                        {
                                            _11514 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_11423 == 3)
                                        {
                                            _11514 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_11423 == 4)
                                        {
                                            _11514 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_11423 == 5)
                                        {
                                            _11514 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_11423 == 6)
                                        {
                                            _11514 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_11423 == 7)
                                        {
                                            _11514 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_11423 == 8)
                                        {
                                            _11514 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_11423 == 9)
                                        {
                                            _11514 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_11423 == 10)
                                        {
                                            _11514 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_11423 == 11)
                                        {
                                            _11514 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_11423 == 12)
                                        {
                                            _11514 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_11423 == 13)
                                        {
                                            _11514 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_11423 == 14)
                                        {
                                            _11514 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_11423 == 15)
                                        {
                                            _11514 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _11514 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6956 = clamp(_6275 + (vec2((_11514.x * _11428) - (_11514.y * _11432), (_11514.x * _11432) + (_11514.y * _11428)) * _6627), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6965 = _6956.y;
                                    highp vec2 _6966 = vec2((float(_11159) + _6956.x) * _6579, _6965);
                                    _6966.y = 1.0 - _6965;
                                    highp vec4 _6973 = textureLod(shadow_map, _6966, 0.0);
                                    highp float _6974 = _6973.x;
                                    highp float _6644 = step(_6974, _6573);
                                    float mp_copy_6644 = _6644;
                                    _6649 = _11425 + (_6974 * _6644);
                                    _6652 = _11424 + mp_copy_6644;
                                }
                                highp float _11426 = 0.0;
                                if (_11424 > 0.0)
                                {
                                    _11426 = _11425 / _11424;
                                }
                                else
                                {
                                    _11426 = _6573;
                                }
                                _11435 = clamp(_6622 * max(_6573 - _11426, 0.0), frag_info.shadow_texel_size, _6282);
                            }
                            else
                            {
                                _11435 = _6282;
                            }
                            bool _6683 = _6581 > 2.5;
                            bool _11436 = false;
                            float _11461 = 0.0;
                            if ((_6581 < 1.5) || _6683)
                            {
                                highp vec2 _7007 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _7011 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _7012 = clamp(_6275, _7007, _7011);
                                highp float _7014 = float(_11159);
                                highp float _7021 = _7012.y;
                                highp vec2 _7022 = vec2((_7014 + _7012.x) * _6579, _7021);
                                _7022.y = 1.0 - _7021;
                                highp float _7034 = float(_6573 <= textureLod(shadow_map, _7022, 0.0).x);
                                float mp_copy_7034 = _7034;
                                float _7044 = (-1.0) * _11428;
                                float _7048 = (-1.0) * _11432;
                                highp vec2 _7072 = clamp(_6275 + (vec2(_7044 - _7048, _7048 + _7044) * _11435), _7007, _7011);
                                highp float _7081 = _7072.y;
                                highp vec2 _7082 = vec2((_7014 + _7072.x) * _6579, _7081);
                                _7082.y = 1.0 - _7081;
                                highp float _7094 = float(_6573 <= textureLod(shadow_map, _7082, 0.0).x);
                                float mp_copy_7094 = _7094;
                                highp vec2 _7132 = clamp(_6275 + (vec2(_11428 - _7048, _11432 + _7044) * _11435), _7007, _7011);
                                highp float _7141 = _7132.y;
                                highp vec2 _7142 = vec2((_7014 + _7132.x) * _6579, _7141);
                                _7142.y = 1.0 - _7141;
                                highp float _7154 = float(_6573 <= textureLod(shadow_map, _7142, 0.0).x);
                                float mp_copy_7154 = _7154;
                                highp vec2 _7192 = clamp(_6275 + (vec2(_7044 - _11432, _7048 + _11428) * _11435), _7007, _7011);
                                highp float _7201 = _7192.y;
                                highp vec2 _7202 = vec2((_7014 + _7192.x) * _6579, _7201);
                                _7202.y = 1.0 - _7201;
                                highp float _7214 = float(_6573 <= textureLod(shadow_map, _7202, 0.0).x);
                                float mp_copy_7214 = _7214;
                                highp vec2 _7252 = clamp(_6275 + (vec2(_11428 - _11432, _11432 + _11428) * _11435), _7007, _7011);
                                highp float _7261 = _7252.y;
                                highp vec2 _7262 = vec2((_7014 + _7252.x) * _6579, _7261);
                                _7262.y = 1.0 - _7261;
                                highp float _7274 = float(_6573 <= textureLod(shadow_map, _7262, 0.0).x);
                                float mp_copy_7274 = _7274;
                                float _6729 = (((mp_copy_7034 + mp_copy_7094) + mp_copy_7154) + mp_copy_7214) + mp_copy_7274;
                                _11461 = _6729 * 0.20000000298023223876953125;
                                _11436 = (_6729 < 0.5) || (_6729 > 4.5);
                            }
                            else
                            {
                                _11461 = 0.0;
                                _11436 = false;
                            }
                            float _11459 = 0.0;
                            if (_11436)
                            {
                                _11459 = _11461;
                            }
                            else
                            {
                                float _11460 = 0.0;
                                if (_6683)
                                {
                                    highp vec2 _7493 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7497 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7498 = clamp(_6275 + (vec2(-0.707099974155426025390625) * _11435), _7493, _7497);
                                    highp vec2 _7509 = (vec2(_7498.x, 1.0 - _7498.y) / _7493) - vec2(0.5);
                                    highp vec2 _7511 = floor(_7509);
                                    highp vec2 _7514 = _7509 - _7511;
                                    highp vec2 _7519 = (_7511 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7521 = float(_11159);
                                    highp vec2 _7529 = vec2((_7521 + _7519.x) * _6579, _7519.y);
                                    highp float _7533 = frag_info.shadow_texel_size * _6579;
                                    highp vec2 _7536 = vec2(_7533, frag_info.shadow_texel_size);
                                    highp vec2 _7545 = vec2(_7533, 0.0);
                                    highp vec2 _7553 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7582 = _7514.x;
                                    highp float _7591 = mix(mix(float(_6573 <= textureLod(shadow_map, _7529, 0.0).x), float(_6573 <= textureLod(shadow_map, _7529 + _7545, 0.0).x), _7582), mix(float(_6573 <= textureLod(shadow_map, _7529 + _7553, 0.0).x), float(_6573 <= textureLod(shadow_map, _7529 + _7536, 0.0).x), _7582), _7514.y);
                                    float mp_copy_7591 = _7591;
                                    highp vec2 _7625 = clamp(_6275 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _11435), _7493, _7497);
                                    highp vec2 _7636 = (vec2(_7625.x, 1.0 - _7625.y) / _7493) - vec2(0.5);
                                    highp vec2 _7638 = floor(_7636);
                                    highp vec2 _7641 = _7636 - _7638;
                                    highp vec2 _7646 = (_7638 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7656 = vec2((_7521 + _7646.x) * _6579, _7646.y);
                                    highp float _7709 = _7641.x;
                                    highp float _7718 = mix(mix(float(_6573 <= textureLod(shadow_map, _7656, 0.0).x), float(_6573 <= textureLod(shadow_map, _7656 + _7545, 0.0).x), _7709), mix(float(_6573 <= textureLod(shadow_map, _7656 + _7553, 0.0).x), float(_6573 <= textureLod(shadow_map, _7656 + _7536, 0.0).x), _7709), _7641.y);
                                    float mp_copy_7718 = _7718;
                                    highp vec2 _7752 = clamp(_6275 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _11435), _7493, _7497);
                                    highp vec2 _7763 = (vec2(_7752.x, 1.0 - _7752.y) / _7493) - vec2(0.5);
                                    highp vec2 _7765 = floor(_7763);
                                    highp vec2 _7768 = _7763 - _7765;
                                    highp vec2 _7773 = (_7765 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7783 = vec2((_7521 + _7773.x) * _6579, _7773.y);
                                    highp float _7836 = _7768.x;
                                    highp float _7845 = mix(mix(float(_6573 <= textureLod(shadow_map, _7783, 0.0).x), float(_6573 <= textureLod(shadow_map, _7783 + _7545, 0.0).x), _7836), mix(float(_6573 <= textureLod(shadow_map, _7783 + _7553, 0.0).x), float(_6573 <= textureLod(shadow_map, _7783 + _7536, 0.0).x), _7836), _7768.y);
                                    float mp_copy_7845 = _7845;
                                    highp vec2 _7879 = clamp(_6275 + (vec2(0.707099974155426025390625) * _11435), _7493, _7497);
                                    highp vec2 _7890 = (vec2(_7879.x, 1.0 - _7879.y) / _7493) - vec2(0.5);
                                    highp vec2 _7892 = floor(_7890);
                                    highp vec2 _7895 = _7890 - _7892;
                                    highp vec2 _7900 = (_7892 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7910 = vec2((_7521 + _7900.x) * _6579, _7900.y);
                                    highp float _7963 = _7895.x;
                                    highp float _7972 = mix(mix(float(_6573 <= textureLod(shadow_map, _7910, 0.0).x), float(_6573 <= textureLod(shadow_map, _7910 + _7545, 0.0).x), _7963), mix(float(_6573 <= textureLod(shadow_map, _7910 + _7553, 0.0).x), float(_6573 <= textureLod(shadow_map, _7910 + _7536, 0.0).x), _7963), _7895.y);
                                    float mp_copy_7972 = _7972;
                                    _11460 = (((mp_copy_7591 + mp_copy_7718) + mp_copy_7845) + mp_copy_7972) * 0.25;
                                }
                                else
                                {
                                    int _6745 = (_6587 > 0.5) ? 17 : 16;
                                    float _11455 = 0.0;
                                    _11455 = 0.0;
                                    float _6773 = 0.0;
                                    for (int _11437 = 0; _11437 < 17; _11455 = _6773, _11437++)
                                    {
                                        if (_11437 >= _6745)
                                        {
                                            break;
                                        }
                                        vec2 _11438 = vec2(0.0);
                                        do
                                        {
                                            if (_11437 == 0)
                                            {
                                                _11438 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_11437 == 1)
                                            {
                                                _11438 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_11437 == 2)
                                            {
                                                _11438 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_11437 == 3)
                                            {
                                                _11438 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_11437 == 4)
                                            {
                                                _11438 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_11437 == 5)
                                            {
                                                _11438 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_11437 == 6)
                                            {
                                                _11438 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_11437 == 7)
                                            {
                                                _11438 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_11437 == 8)
                                            {
                                                _11438 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_11437 == 9)
                                            {
                                                _11438 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_11437 == 10)
                                            {
                                                _11438 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_11437 == 11)
                                            {
                                                _11438 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_11437 == 12)
                                            {
                                                _11438 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_11437 == 13)
                                            {
                                                _11438 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_11437 == 14)
                                            {
                                                _11438 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_11437 == 15)
                                            {
                                                _11438 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _11438 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _11440 = vec2(0.0);
                                        do
                                        {
                                            if (_11437 < 3)
                                            {
                                                _11440 = vec2(float(_11437) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_11437 < 6)
                                            {
                                                _11440 = vec2((float(_11437 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_11437 < 11)
                                            {
                                                _11440 = vec2((float(_11437 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_11437 < 14)
                                            {
                                                _11440 = vec2((float(_11437 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _11440 = vec2(float(_11437 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6762 = mix(_11438, _11440, vec2(_6587));
                                        float _7413 = _6762.x;
                                        float _7417 = _6762.y;
                                        highp vec2 _7443 = clamp(_6275 + (vec2((_7413 * _11428) - (_7417 * _11432), (_7413 * _11432) + (_7417 * _11428)) * _11435), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7452 = _7443.y;
                                        highp vec2 _7453 = vec2((float(_11159) + _7443.x) * _6579, _7452);
                                        _7453.y = 1.0 - _7452;
                                        highp float _7465 = float(_6573 <= textureLod(shadow_map, _7453, 0.0).x);
                                        float mp_copy_7465 = _7465;
                                        _6773 = _11455 + mp_copy_7465;
                                    }
                                    _11460 = _11455 / float(_6745);
                                }
                                _11459 = _11460;
                            }
                            bool _6818 = _11159 == (_6185 - 1);
                            bool _6824 = false;
                            if (_6818)
                            {
                                _6824 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6824 = _6818;
                            }
                            float _11462 = 0.0;
                            if (_6824)
                            {
                                highp vec2 _6831 = vec2(frag_info.shadow_fade / _11395);
                                highp vec2 _6839 = smoothstep(vec2(0.0), _6831, _6275) * smoothstep(vec2(0.0), _6831, _6432);
                                _11462 = mix(1.0, _11459, _6839.x * _6839.y);
                            }
                            else
                            {
                                _11462 = _11459;
                            }
                            _11525 = _11163 + _6335;
                            _11522 = _11161 + (_6335 * _11462);
                        }
                        else
                        {
                            _11525 = _11163;
                            _11522 = _11161;
                        }
                        _11524 = _11525;
                        _11521 = _11522;
                    }
                    else
                    {
                        _11524 = _11163;
                        _11521 = _11161;
                    }
                    _11523 = _11524;
                    _11520 = _11521;
                }
                else
                {
                    _11523 = _11163;
                    _11520 = _11161;
                }
            }
            _11162 = _11163;
            _11160 = _11161;
        }
        else
        {
            _11162 = 0.0;
            _11160 = 0.0;
        }
        _11166 = mix(_11160 + (1.0 - _11162), 1.0, _11158);
    }
    else
    {
        _11166 = 1.0;
    }
    vec3 mp_copy_11167 = vec3(0.0);
    float _5652 = _5630 * _11166;
    bool _7980 = view_info.camera_forward.w > 0.5;
    highp vec3 _11167 = vec3(0.0);
    if (_7980)
    {
        _11167 = -view_info.camera_forward.xyz;
    }
    else
    {
        _11167 = normalize(v_viewvector);
    }
    highp float _8024 = 0.0;
    mp_copy_11167 = _11167;
    vec3 _5661 = mix(frag_info.dielectric_f0.xyz, _5592, vec3(_4757));
    float _5665 = max(dot(_11108, _11167), 0.0);
    float _5669 = max(dot(_4623, _11167), 0.0);
    highp vec2 _11168 = vec2(0.0);
    do
    {
        _8024 = frag_info.punctual_dims.x;
        if (_8024 < 0.5)
        {
            _11168 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _8036 = v_position - frag_info.camera_position.xyz;
            highp float _8051 = dot(_8036, frag_info.camera_forward.xyz);
            highp float _8057 = max(_8051, 9.9999997473787516355514526367188e-05);
            highp vec2 _8160 = (vec3(dot(_8036, frag_info.camera_right.xyz), dot(_8036, frag_info.camera_up.xyz), _8057).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_8057, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _8175 = float(int(((((clamp(floor((log2(max(_8051 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_8160.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_8160.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _11168 = vec2(textureLod(punctual_index, vec2((mod(_8175, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8175 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _11168 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5678 = int(_11168.x + 0.5);
    mediump int _5682 = int(_11168.y + 0.5);
    highp vec3 _11213 = vec3(0.0);
    _11213 = vec3(0.0);
    highp vec3 _11660 = vec3(0.0);
    for (int _11169 = 0; _11169 < _5682; _11213 = _11660, _11169++)
    {
        highp float hp_copy_11308 = 0.0;
        highp float _8208 = float(_5678 + _11169);
        highp float _8239 = (float(int(textureLod(punctual_index, vec2((mod(_8208, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_8208 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _8024;
        highp vec2 _8240 = vec2(0.0625, _8239);
        highp vec4 _8243 = textureLod(punctual_lights, _8240, 0.0);
        highp vec4 _8260 = textureLod(punctual_lights, vec2(0.1875, _8239), 0.0);
        highp float _5700 = _8243.w;
        highp vec3 _5702 = _8260.xyz;
        vec3 _11281 = vec3(0.0);
        highp vec3 _11304 = vec3(0.0);
        float _11308 = 0.0;
        if (_5700 < 0.5)
        {
            _11308 = _11156;
            _11304 = _5702;
            _11281 = -normalize(textureLod(punctual_lights, vec2(0.3125, _8239), 0.0).xyz);
        }
        else
        {
            highp vec3 _5710 = _8243.xyz - v_position;
            highp float _5713 = dot(_5710, _5710);
            highp float _5717 = inversesqrt(max(_5713, 9.9999999392252902907785028219223e-09));
            highp vec3 _5718 = _5710 * _5717;
            vec3 mp_copy_5718 = _5718;
            highp float _5720 = _8260.w;
            highp float _5725 = (_5713 * _5720) * _5720;
            highp float _5730 = clamp(1.0 - (_5725 * _5725), 0.0, 1.0);
            float mp_copy_5730 = _5730;
            if (_5730 <= 0.0)
            {
                _11660 = _11213;
                continue;
            }
            highp vec4 _8277 = textureLod(punctual_lights, vec2(0.4375, _8239), 0.0);
            highp float _5738 = _8277.w;
            float _11313 = 0.0;
            if (_5738 > 0.0)
            {
                highp float _5765 = (_11156 * _11156) + ((_5738 * 0.5) * _5717);
                float mp_copy_5765 = _5765;
                _11313 = sqrt(min(mp_copy_5765, 1.0));
            }
            else
            {
                _11313 = _11156;
            }
            highp vec3 _5772 = _5702 * ((mp_copy_5730 * mp_copy_5730) / max(pow(max(_5713, _5738 * _5738), _8277.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _11305 = vec3(0.0);
            if (_5700 > 1.5)
            {
                highp vec4 _8715 = textureLod(punctual_lights, vec2(0.3125, _8239), 0.0);
                highp float _5817 = clamp((dot(normalize(_8715.xyz), -mp_copy_5718) * _8715.w) + _8277.x, 0.0, 1.0);
                float mp_copy_5817 = _5817;
                highp vec3 _5822 = _5772 * (mp_copy_5817 * mp_copy_5817);
                if (_5817 <= 0.0)
                {
                    _11660 = _11213;
                    continue;
                }
                bool _5828 = _5817 > 0.0;
                bool _5834 = false;
                if (_5828)
                {
                    _5834 = _8277.y > (-0.5);
                }
                else
                {
                    _5834 = _5828;
                }
                bool _5840 = false;
                if (_5834)
                {
                    _5840 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5840 = _5834;
                }
                highp vec3 _11307 = vec3(0.0);
                if (_5840)
                {
                    float _11272 = 0.0;
                    do
                    {
                        highp vec4 _8827 = mat4(textureLod(punctual_lights, vec2(0.5625, _8239), 0.0), textureLod(punctual_lights, vec2(0.6875, _8239), 0.0), textureLod(punctual_lights, vec2(0.8125, _8239), 0.0), textureLod(punctual_lights, vec2(0.9375, _8239), 0.0)) * vec4(v_position + (_4623 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8829 = _8827.w;
                        if (_8829 <= 0.0)
                        {
                            _11272 = 1.0;
                            break;
                        }
                        highp vec3 _8838 = _8827.xyz / vec3(_8829);
                        highp vec2 _8843 = (_8838.xy * 0.5) + vec2(0.5);
                        highp float _8845 = _8843.x;
                        bool _8846 = _8845 < 0.0;
                        bool _8853 = false;
                        if (!_8846)
                        {
                            _8853 = _8845 > 1.0;
                        }
                        else
                        {
                            _8853 = _8846;
                        }
                        bool _8860 = false;
                        if (!_8853)
                        {
                            _8860 = _8843.y < 0.0;
                        }
                        else
                        {
                            _8860 = _8853;
                        }
                        bool _8867 = false;
                        if (!_8860)
                        {
                            _8867 = _8843.y > 1.0;
                        }
                        else
                        {
                            _8867 = _8860;
                        }
                        bool _8874 = false;
                        if (!_8867)
                        {
                            _8874 = _8838.z < 0.0;
                        }
                        else
                        {
                            _8874 = _8867;
                        }
                        bool _8881 = false;
                        if (!_8874)
                        {
                            _8881 = _8838.z > 1.0;
                        }
                        else
                        {
                            _8881 = _8874;
                        }
                        if (_8881)
                        {
                            _11272 = 1.0;
                            break;
                        }
                        highp float _8888 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8893 = frag_info.shadow_cascade_count + float(int(_8277.y + 0.5));
                        highp float _8898 = _8838.z - frag_info.spot_shadow_params.y;
                        highp float _8909 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8909 = _8909;
                        highp vec2 _8916 = vec2(cos(mp_copy_8909), sin(mp_copy_8909)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8918 = _8916.x;
                        highp float _8920 = _8916.y;
                        highp vec2 _8928 = vec2(_8918 - _8920, _8918 + _8920) * 0.707106769084930419921875;
                        highp float _9121 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8845, 0.0, 1.0)) / _8888, 1.0 - clamp(_8843.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9121 = _9121;
                        highp vec2 _8936 = _8843 + _8916;
                        highp float _9143 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8936.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8936.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9143 = _9143;
                        highp vec2 _8944 = _8843 - _8916;
                        highp float _9165 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8944.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8944.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9165 = _9165;
                        highp vec2 _8957 = _8843 + vec2(-_8920, _8918);
                        highp float _9187 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8957.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8957.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9187 = _9187;
                        highp vec2 _8970 = _8843 + vec2(_8920, -_8918);
                        highp float _9209 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8970.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8970.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9209 = _9209;
                        float _8975 = (((mp_copy_9121 + mp_copy_9143) + mp_copy_9165) + mp_copy_9187) + mp_copy_9209;
                        if ((_8975 < 0.5) || (_8975 > 4.5))
                        {
                            _11272 = _8975 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8987 = _8843 + _8928;
                        highp float _9231 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8987.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8987.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9231 = _9231;
                        highp vec2 _8994 = _8843 - _8928;
                        highp float _9253 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_8994.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_8994.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9253 = _9253;
                        highp float _9002 = _8928.y;
                        highp float _9005 = _8928.x;
                        highp vec2 _9007 = _8843 + vec2(-_9002, _9005);
                        highp float _9275 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_9007.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_9007.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9275 = _9275;
                        highp vec2 _9020 = _8843 + vec2(_9002, -_9005);
                        highp float _9297 = float(_8898 <= textureLod(shadow_map, vec2((_8893 + clamp(_9020.x, 0.0, 1.0)) / _8888, 1.0 - clamp(_9020.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9297 = _9297;
                        _11272 = (_8975 + (((mp_copy_9231 + mp_copy_9253) + mp_copy_9275) + mp_copy_9297)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _11307 = _5822 * _11272;
                }
                else
                {
                    _11307 = _5822;
                }
                _11305 = _11307;
            }
            else
            {
                bool _5777 = _5700 > 0.5;
                bool _5783 = false;
                if (_5777)
                {
                    _5783 = _8277.y > (-0.5);
                }
                else
                {
                    _5783 = _5777;
                }
                bool _5789 = false;
                if (_5783)
                {
                    _5789 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5789 = _5783;
                }
                highp vec3 _11306 = vec3(0.0);
                if (_5789)
                {
                    float _11259 = 0.0;
                    do
                    {
                        highp vec4 _8590 = textureLod(punctual_lights, vec2(0.5625, _8239), 0.0);
                        highp vec4 _8607 = textureLod(punctual_lights, vec2(0.6875, _8239), 0.0);
                        highp vec3 _8349 = (v_position + (_4623 * _8590.z)) - textureLod(punctual_lights, _8240, 0.0).xyz;
                        highp vec3 _8351 = abs(_8349);
                        highp float _8353 = _8351.x;
                        highp float _8355 = _8351.y;
                        bool _8356 = _8353 >= _8355;
                        bool _8364 = false;
                        if (_8356)
                        {
                            _8364 = _8353 >= _8351.z;
                        }
                        else
                        {
                            _8364 = _8356;
                        }
                        highp vec3 _11249 = vec3(0.0);
                        float _11251 = 0.0;
                        if (_8364)
                        {
                            highp float _8430 = _8349.x;
                            bool _8431 = _8430 >= 0.0;
                            highp vec3 _11248 = vec3(0.0);
                            if (_8431)
                            {
                                _11248 = vec3(-_8349.z, _8349.y, _8430);
                            }
                            else
                            {
                                _11248 = vec3(_8349.zy, -_8430);
                            }
                            _11251 = _8431 ? 0.0 : 1.0;
                            _11249 = _11248;
                        }
                        else
                        {
                            highp vec3 _11250 = vec3(0.0);
                            float _11252 = 0.0;
                            if (_8355 >= _8351.z)
                            {
                                highp float _8401 = _8349.y;
                                bool _8402 = _8401 >= 0.0;
                                highp vec3 _11247 = vec3(0.0);
                                if (_8402)
                                {
                                    _11247 = vec3(-_8349.x, _8349.z, _8401);
                                }
                                else
                                {
                                    _11247 = vec3(_8349.xz, -_8401);
                                }
                                _11252 = _8402 ? 2.0 : 3.0;
                                _11250 = _11247;
                            }
                            else
                            {
                                highp float _8373 = _8349.z;
                                bool _8374 = _8373 >= 0.0;
                                highp vec3 _11246 = vec3(0.0);
                                if (_8374)
                                {
                                    _11246 = _8349;
                                }
                                else
                                {
                                    _11246 = vec3(-_8349.x, _8349.y, -_8373);
                                }
                                _11252 = _8374 ? 4.0 : 5.0;
                                _11250 = _11246;
                            }
                            _11251 = _11252;
                            _11249 = _11250;
                        }
                        if (_11249.z <= 0.0)
                        {
                            _11259 = 1.0;
                            break;
                        }
                        highp vec2 _8470 = ((_11249.xy / vec2(_11249.z)) * 0.5) + vec2(0.5);
                        highp float _8481 = (_8590.x - (_8590.y / _11249.z)) - _8607.x;
                        if ((_8481 < 0.0) || (_8481 > 1.0))
                        {
                            _11259 = 1.0;
                            break;
                        }
                        highp float hp_copy_11256 = 0.0;
                        highp float _8493 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        bool _8499 = _11251 >= 4.0;
                        highp float _8501 = (frag_info.shadow_cascade_count + _8277.y) + float(_8499);
                        float _11256 = 0.0;
                        if (_8499)
                        {
                            _11256 = _11251 - 4.0;
                        }
                        else
                        {
                            _11256 = _11251;
                        }
                        hp_copy_11256 = _11256;
                        highp float _8518 = _8607.y * 0.5;
                        highp float _8521 = _8590.w * 0.0040000001899898052215576171875;
                        highp vec2 _8632 = vec2(_8518);
                        highp vec2 _8635 = vec2(1.0 - _8518);
                        highp vec2 _8641 = vec2(mod(hp_copy_11256, 2.0), 1.0 - floor(hp_copy_11256 * 0.5)) * 0.5;
                        highp vec2 _8644 = _8641 + (clamp(_8470, _8632, _8635) * 0.5);
                        highp float _8537 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float _11258 = 0.0;
                        _11258 = float(_8481 <= textureLod(shadow_map, vec2((_8501 + _8644.x) / _8493, 1.0 - _8644.y), 0.0).x);
                        for (int _11257 = 0; _11257 < 8; )
                        {
                            highp float _8547 = _8537 + (float(_11257) * 0.785398185253143310546875);
                            float mp_copy_8547 = _8547;
                            highp vec2 _8681 = _8641 + (clamp(_8470 + (vec2(cos(mp_copy_8547), sin(mp_copy_8547)) * _8521), _8632, _8635) * 0.5);
                            highp float _8698 = float(_8481 <= textureLod(shadow_map, vec2((_8501 + _8681.x) / _8493, 1.0 - _8681.y), 0.0).x);
                            float mp_copy_8698 = _8698;
                            _11258 += mp_copy_8698;
                            _11257++;
                            continue;
                        }
                        _11259 = _11258 * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _11306 = _5772 * _11259;
                }
                else
                {
                    _11306 = _5772;
                }
                _11305 = _11306;
            }
            _11308 = _11313;
            _11304 = _11305;
            _11281 = _5718;
        }
        hp_copy_11308 = _11308;
        highp vec3 _11335 = vec3(0.0);
        highp vec3 _11336 = vec3(0.0);
        do
        {
            float _9380 = max(dot(_11108, _11281), 0.0);
            highp float hp_copy_9380 = _9380;
            if (_9380 <= 0.0)
            {
                _11336 = vec3(0.0);
                _11335 = vec3(0.0);
                break;
            }
            float _9386 = max(_5665, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9386 = _9386;
            vec3 _9389 = _11281 + mp_copy_11167;
            float _9392 = dot(_9389, _9389);
            vec3 _11333 = vec3(0.0);
            vec3 _11334 = vec3(0.0);
            if (_9392 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9400 = _9389 * inversesqrt(_9392);
                float _11332 = 0.0;
                do
                {
                    float _9457 = dot(_11108, _9400);
                    if (_9457 <= 0.0)
                    {
                        _11332 = 0.0;
                        break;
                    }
                    float _9464 = _11308 * _11308;
                    vec3 _9467 = cross(_11108, _9400);
                    float _9470 = _9457 * _9464;
                    float _9479 = _9464 / (dot(_9467, _9467) + (_9470 * _9470));
                    _11332 = min((_9479 * _9479) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9517 = _5661 + ((vec3(1.0) - _5661) * pow(clamp(1.0 - max(dot(_9400, _11167), 0.0), 0.0, 1.0), 5.0));
                _11334 = (_9517 * min(_11332 * (0.5 / max(mix((2.0 * hp_copy_9380) * _9386, hp_copy_9380 + hp_copy_9386, hp_copy_11308 * hp_copy_11308), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _11333 = _9517;
            }
            else
            {
                _11334 = vec3(0.0);
                _11333 = _5661;
            }
            _11336 = (_11334 * _11304) * _9380;
            _11335 = (((((vec3(1.0) - _11333) * (1.0 - _4757)) * _5592) * 0.3183098733425140380859375) * _11304) * _9380;
            break;
        } while(false);
        _11660 = _11213 + (_11335 + _11336);
    }
    bool _9741 = false;
    highp vec3 hp_copy_11170 = vec3(0.0);
    mat3 _5895 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5903 = _5895 * vec3(_11108.x, _11108.y, _11108.z);
    vec3 _5906 = _5895 * reflect(-mp_copy_11167, _11108);
    float _9560 = _5903.y;
    float _9567 = _5903.z;
    float _9574 = _5903.x;
    float _9582 = 1.09254801273345947265625 * _9574;
    vec3 _5909 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _9560))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _9567))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _9574))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_9582 * _9560))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _9560) * _9567))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _9567) * _9567) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_9582 * _9567))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_9574 * _9574) - (_9560 * _9560)))), vec3(0.0));
    highp vec3 hp_copy_5909 = _5909;
    vec3 _11170 = vec3(0.0);
    do
    {
        _9741 = radiance_layout_info.mip_layout > 0.5;
        if (_9741)
        {
            vec2 _9820 = vec2(atan(_5906.z, _5906.x), asin(clamp(_5906.y, -1.0, 1.0)));
            highp vec2 hp_copy_9820 = _9820;
            _11170 = textureLod(prefiltered_radiance, (hp_copy_9820 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_11156, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9839 = vec2(atan(_5906.z, _5906.x), asin(clamp(_5906.y, -1.0, 1.0)));
        highp vec2 hp_copy_9839 = _9839;
        highp vec2 _9844 = (hp_copy_9839 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _9751 = clamp(_9844.y, 0.00390625, 0.99609375);
        float _9755 = clamp(_11156, 0.0, 1.0) * 7.0;
        float _9757 = floor(_9755);
        highp float _9776 = _9844.x;
        _11170 = mix(textureLod(prefiltered_radiance, vec2(_9776, (_9757 + _9751) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9776, (min(_9757 + 1.0, 7.0) + _9751) * 0.125), 0.0).xyz, vec3(_9755 - _9757));
        break;
    } while(false);
    hp_copy_11170 = _11170;
    highp vec3 _11176 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_11171 = vec3(0.0);
        vec3 _11171 = vec3(0.0);
        do
        {
            if (_9741)
            {
                vec2 _9949 = vec2(atan(_5906.z, _5906.x), asin(clamp(_5906.y, -1.0, 1.0)));
                highp vec2 hp_copy_9949 = _9949;
                _11171 = textureLod(prefiltered_radiance_b, (hp_copy_9949 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_11156, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9968 = vec2(atan(_5906.z, _5906.x), asin(clamp(_5906.y, -1.0, 1.0)));
            highp vec2 hp_copy_9968 = _9968;
            highp vec2 _9973 = (hp_copy_9968 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9880 = clamp(_9973.y, 0.00390625, 0.99609375);
            float _9884 = clamp(_11156, 0.0, 1.0) * 7.0;
            float _9886 = floor(_9884);
            highp float _9905 = _9973.x;
            _11171 = mix(textureLod(prefiltered_radiance_b, vec2(_9905, (_9886 + _9880) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9905, (min(_9886 + 1.0, 7.0) + _9880) * 0.125), 0.0).xyz, vec3(_9884 - _9886));
            break;
        } while(false);
        hp_copy_11171 = _11171;
        _11176 = hp_copy_11170 + hp_copy_11171;
    }
    else
    {
        _11176 = _11170;
    }
    float _5924 = frag_info.environment_intensity;
    highp float hp_copy_5924 = _5924;
    vec2 _5937 = clamp(vec2(_5669, _11156), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5939 = texture(brdf_lut, vec2(_5937.x * 0.3333333432674407958984375, _5937.y));
    float _5943 = _5939.x;
    float _5946 = _5939.y;
    vec3 _5948 = ((_5661 + ((max(vec3(1.0 - _11156), _5661) - _5661) * pow(clamp(1.0 - _5669, 0.0, 1.0), 5.0))) * _5943) + vec3(_5946);
    float _5954 = 1.0 - (_5943 + _5946);
    vec3 _5958 = vec3(1.0) - _5661;
    vec3 _5961 = _5661 + (_5958 * vec3(0.0476190485060214996337890625));
    vec3 _5972 = ((_5948 * _5954) * _5961) / (vec3(1.0) - (_5961 * _5954));
    float _5975 = 1.0 - _4757;
    float _11190 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _11190 = clamp((pow(_5665 + _11185, exp2(((-16.0) * _11156) - 1.0)) - 1.0) + _11185, 0.0, 1.0);
    }
    else
    {
        _11190 = _11185;
    }
    highp vec3 _11223 = vec3(0.0);
    if (_5617)
    {
        highp vec3 _11207 = vec3(0.0);
        highp vec3 _11208 = vec3(0.0);
        do
        {
            float _10062 = max(dot(_11108, _11199), 0.0);
            highp float hp_copy_10062 = _10062;
            if (_10062 <= 0.0)
            {
                _11208 = vec3(0.0);
                _11207 = vec3(0.0);
                break;
            }
            float _10068 = max(_5665, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_10068 = _10068;
            vec3 _10071 = _11199 + mp_copy_11167;
            float _10074 = dot(_10071, _10071);
            vec3 _11205 = vec3(0.0);
            vec3 _11206 = vec3(0.0);
            if (_10074 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _10082 = _10071 * inversesqrt(_10074);
                float _11204 = 0.0;
                do
                {
                    float _10139 = dot(_11108, _10082);
                    if (_10139 <= 0.0)
                    {
                        _11204 = 0.0;
                        break;
                    }
                    float _10146 = _11156 * _11156;
                    vec3 _10149 = cross(_11108, _10082);
                    float _10152 = _10139 * _10146;
                    float _10161 = _10146 / (dot(_10149, _10149) + (_10152 * _10152));
                    _11204 = min((_10161 * _10161) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _10199 = _5661 + (_5958 * pow(clamp(1.0 - max(dot(_10082, _11167), 0.0), 0.0, 1.0), 5.0));
                _11206 = (_10199 * min(_11204 * (0.5 / max(mix((2.0 * hp_copy_10062) * _10068, hp_copy_10062 + hp_copy_10068, hp_copy_11156 * hp_copy_11156), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _11205 = _10199;
            }
            else
            {
                _11206 = vec3(0.0);
                _11205 = _5661;
            }
            _11208 = (_11206 * frag_info.directional_light_color.xyz) * _10062;
            _11207 = (((((vec3(1.0) - _11205) * _5975) * _5592) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _10062;
            break;
        } while(false);
        _11223 = _11213 + ((_11207 + _11208) * _5652);
    }
    else
    {
        _11223 = _11213;
    }
    bool _6066 = _FogInfo.params0.y > 0.5;
    bool _6072 = false;
    if (_6066)
    {
        _6072 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _6072 = _6066;
    }
    highp vec3 _11226 = vec3(0.0);
    if (_6072)
    {
        vec3 mp_copy_11224 = vec3(0.0);
        highp vec3 _11224 = vec3(0.0);
        if (_7980)
        {
            _11224 = -view_info.camera_forward.xyz;
        }
        else
        {
            _11224 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_11225 = vec3(0.0);
        mp_copy_11224 = _11224;
        vec3 _6077 = _5895 * (-mp_copy_11224);
        vec3 _11225 = vec3(0.0);
        do
        {
            if (_9741)
            {
                vec2 _10321 = vec2(atan(_6077.z, _6077.x), asin(clamp(_6077.y, -1.0, 1.0)));
                highp vec2 hp_copy_10321 = _10321;
                _11225 = textureLod(prefiltered_radiance, (hp_copy_10321 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _10340 = vec2(atan(_6077.z, _6077.x), asin(clamp(_6077.y, -1.0, 1.0)));
            highp vec2 hp_copy_10340 = _10340;
            highp vec2 _10345 = (hp_copy_10340 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _10252 = clamp(_10345.y, 0.00390625, 0.99609375);
            float _10258 = floor(0.0);
            highp float _10277 = _10345.x;
            _11225 = mix(textureLod(prefiltered_radiance, vec2(_10277, (_10258 + _10252) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_10277, (min(_10258 + 1.0, 7.0) + _10252) * 0.125), 0.0).xyz, vec3(-_10258));
            break;
        } while(false);
        hp_copy_11225 = _11225;
        _11226 = hp_copy_11225 * hp_copy_5924;
    }
    else
    {
        _11226 = _FogInfo.color.xyz;
    }
    highp vec4 _6092 = vec4(min(((((((_5972 + ((_5592 * _5975) * ((vec3(1.0) - _5948) - _5972))) * (hp_copy_5909 * hp_copy_5924)) * vec3(_4791)) + (((_5948 * (_11176 * _5924)) * 1.0) * _11190)) * mix(1.0, _5652, frag_info.radiance_blend.y)) + (_11223 * mix(1.0, _11185, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _11131, vec3(65504.0)), 1.0) * _11709;
    highp vec4 _11241 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _11241 = _6092;
            break;
        }
        int _10389 = int(_FogInfo.params0.x + 0.5);
        if (_10389 == 0)
        {
            _11241 = _6092;
            break;
        }
        highp float _11228 = 0.0;
        if (_7980)
        {
            _11228 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _11228 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_11228 > _FogInfo.params1.w))
        {
            _11241 = _6092;
            break;
        }
        float _11232 = 0.0;
        if (_10389 == 1)
        {
            _11232 = clamp((_11228 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _11233 = 0.0;
            if (_10389 == 2)
            {
                highp float _11231 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _11229 = vec3(0.0);
                    if (_7980)
                    {
                        _11229 = v_position - (view_info.camera_forward.xyz * _11228);
                    }
                    else
                    {
                        _11229 = v_position + v_viewvector;
                    }
                    highp float _10480 = -_FogInfo.params2.y;
                    highp float _10487 = _FogInfo.params1.x * exp(_10480 * (_11229.y - _FogInfo.params2.x));
                    highp float _10504 = _FogInfo.params2.y * (v_position.y - _11229.y);
                    highp float _11230 = 0.0;
                    if (abs(_10504) > 0.00124999997206032276153564453125)
                    {
                        _11230 = (_10487 - (_FogInfo.params1.x * exp(_10480 * (v_position.y - _FogInfo.params2.x)))) / _10504;
                    }
                    else
                    {
                        _11230 = _10487;
                    }
                    _11231 = _11230 * max(_11228 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _11231 = _FogInfo.params1.x * max(_11228 - _FogInfo.params1.y, 0.0);
                }
                _11233 = 1.0 - exp(-_11231);
            }
            else
            {
                highp float _10442 = _FogInfo.params1.x * max(_11228 - _FogInfo.params1.y, 0.0);
                _11233 = 1.0 - exp((-_10442) * _10442);
            }
            _11232 = _11233;
        }
        highp float _10544 = min(_11232, _FogInfo.params0.z);
        if (_10544 <= 0.0)
        {
            _11241 = _6092;
            break;
        }
        highp vec3 _10557 = mix(_FogInfo.color.xyz, _11226, vec3(_FogInfo.params0.w));
        bool _10560 = _FogInfo.sun.w > 0.5;
        bool _10566 = false;
        if (_10560)
        {
            _10566 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _10566 = _10560;
        }
        vec3 _11237 = vec3(0.0);
        if (_10566)
        {
            vec3 mp_copy_11234 = vec3(0.0);
            highp vec3 _11234 = vec3(0.0);
            if (_7980)
            {
                _11234 = -view_info.camera_forward.xyz;
            }
            else
            {
                _11234 = normalize(v_viewvector);
            }
            mp_copy_11234 = _11234;
            highp float _10582 = pow(max(dot(-mp_copy_11234, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_10582 = _10582;
            _11237 = _10557 + ((_FogInfo.sun.xyz * mp_copy_10582) * _FogInfo.params2.z);
        }
        else
        {
            _11237 = _10557;
        }
        highp float _10595 = _6092.w;
        float mp_copy_10595 = _10595;
        _11241 = vec4(mix(_6092.xyz, _11237 * mp_copy_10595, vec3(_10544)), _10595);
        break;
    } while(false);
    vec4 _11243 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _11243 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _11243 = _11241;
        break;
    } while(false);
    frag_color = _11243;
    float _11244 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _11244 = 1.0;
    }
    else
    {
        _11244 = abs(frag_info.fade);
    }
    frag_color *= _11244;
}

