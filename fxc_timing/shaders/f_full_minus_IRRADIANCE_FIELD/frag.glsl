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
uniform mediump sampler2D brdf_lut;
uniform highp sampler2D irradiance_field;
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
    highp float _5394 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_5394 = _5394;
    vec3 _5398 = normalize(v_normal) * mp_copy_5394;
    vec4 _5440 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _5443 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _13461 = vec2(0.0);
    if (_5443)
    {
        highp vec2 _13460 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _13460 = v_texture_coords_1;
        }
        else
        {
            _13460 = v_texture_coords;
        }
        highp vec2 _5643 = _13460 * texture_transforms.base_color_transform.zw;
        highp float _5649 = _5643.x;
        highp float _5654 = _5643.y;
        _13461 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _5649) + (texture_transforms.base_color_rotation.y * _5654), ((-texture_transforms.base_color_rotation.y) * _5649) + (texture_transforms.base_color_rotation.x * _5654));
    }
    else
    {
        _13461 = v_texture_coords;
    }
    vec4 _5457 = texture(base_color_texture, _13461);
    vec3 _5459 = _5457.xyz;
    float _14501 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_5457.w * _5440.w) * frag_info.color.w);
    vec3 _13476 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _13464 = vec2(0.0);
        if (_5443)
        {
            highp vec2 _13463 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _13463 = v_texture_coords_1;
            }
            else
            {
                _13463 = v_texture_coords;
            }
            highp vec2 _5738 = _13463 * texture_transforms.normal_transform.zw;
            highp float _5744 = _5738.x;
            highp float _5749 = _5738.y;
            _13464 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _5744) + (texture_transforms.normal_rotation.y * _5749), ((-texture_transforms.normal_rotation.y) * _5744) + (texture_transforms.normal_rotation.x * _5749));
        }
        else
        {
            _13464 = v_texture_coords;
        }
        vec3 _5797 = ((texture(normal_texture, _13464).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _5801 = _5797.xy * vec2(frag_info.normal_scale);
        vec3 _13079 = _5797;
        _13079.x = _5801.x;
        _13079.y = _5801.y;
        highp vec3 _5807 = -v_viewvector;
        highp vec3 _5897 = dFdx(_5807);
        highp vec3 _5899 = dFdy(_5807);
        highp vec2 _5901 = dFdx(_13464);
        highp vec2 _5903 = dFdy(_13464);
        bvec2 _14503 = bvec2(length(_5901) == 0.0);
        highp vec2 _14504 = vec2(_14503.x ? vec2(1.0, 0.0).x : _5901.x, _14503.y ? vec2(1.0, 0.0).y : _5901.y);
        bvec2 _14505 = bvec2(length(_5903) == 0.0);
        highp vec2 _14506 = vec2(_14505.x ? vec2(0.0, 1.0).x : _5903.x, _14505.y ? vec2(0.0, 1.0).y : _5903.y);
        highp vec3 _5916 = cross(_5899, _5398);
        highp vec3 _5919 = cross(_5398, _5897);
        highp float _5944 = (dot(cross(_5897, _5899), _5398) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _5947 = ((_5916 * _14504.x) + (_5919 * _14506.x)) * _5944;
        highp float _13471 = 0.0;
        if (gl_FrontFacing)
        {
            _13471 = -_5944;
        }
        else
        {
            _13471 = _5944;
        }
        highp vec3 _5957 = ((_5916 * _14504.y) + (_5919 * _14506.y)) * _13471;
        highp float _5966 = inversesqrt(max(max(dot(_5947, _5947), dot(_5957, _5957)), 9.9999996826552253889678874634872e-21));
        vec3 _5838 = v_tangent.xyz - (_5398 * dot(_5398, v_tangent.xyz));
        highp float _5841 = dot(_5838, _5838);
        bool _5843 = _5841 > 1.0000000133514319600180897396058e-10;
        bool _5850 = false;
        if (_5843)
        {
            _5850 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _5850 = _5843;
        }
        mat3 _13474 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_5850)
        {
            highp vec3 _5855 = _5838 * inversesqrt(_5841);
            _13474 = mat3(_5855, normalize(cross(_5398, _5855)) * sign(v_tangent.w), _5398);
        }
        else
        {
            _13474 = mat3(_5947 * _5966, _5957 * _5966, _5398);
        }
        _13476 = normalize(_13474 * _13079);
    }
    else
    {
        _13476 = _5398;
    }
    highp vec2 _13478 = vec2(0.0);
    if (_5443)
    {
        highp vec2 _13477 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _13477 = v_texture_coords_1;
        }
        else
        {
            _13477 = v_texture_coords;
        }
        highp vec2 _6031 = _13477 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6037 = _6031.x;
        highp float _6042 = _6031.y;
        _13478 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6037) + (texture_transforms.metallic_roughness_rotation.y * _6042), ((-texture_transforms.metallic_roughness_rotation.y) * _6037) + (texture_transforms.metallic_roughness_rotation.x * _6042));
    }
    else
    {
        _13478 = v_texture_coords;
    }
    vec4 _5526 = texture(metallic_roughness_texture, _13478);
    float _5532 = clamp(_5526.z * frag_info.metallic_factor, 0.0, 1.0);
    float _5539 = clamp(_5526.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _13480 = vec2(0.0);
    if (_5443)
    {
        highp vec2 _13479 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _13479 = v_texture_coords_1;
        }
        else
        {
            _13479 = v_texture_coords;
        }
        highp vec2 _6102 = _13479 * texture_transforms.occlusion_transform.zw;
        highp float _6108 = _6102.x;
        highp float _6113 = _6102.y;
        _13480 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6108) + (texture_transforms.occlusion_rotation.y * _6113), ((-texture_transforms.occlusion_rotation.y) * _6108) + (texture_transforms.occlusion_rotation.x * _6113));
    }
    else
    {
        _13480 = v_texture_coords;
    }
    float _13481 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _13481 = texture(occlusion_texture, _13480).x;
    }
    else
    {
        _13481 = 1.0;
    }
    float _5566 = 1.0 - ((1.0 - _13481) * frag_info.occlusion_strength);
    highp vec2 _13483 = vec2(0.0);
    if (_5443)
    {
        highp vec2 _13482 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _13482 = v_texture_coords_1;
        }
        else
        {
            _13482 = v_texture_coords;
        }
        highp vec2 _6173 = _13482 * texture_transforms.emissive_transform.zw;
        highp float _6179 = _6173.x;
        highp float _6184 = _6173.y;
        _13483 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6179) + (texture_transforms.emissive_rotation.y * _6184), ((-texture_transforms.emissive_rotation.y) * _6179) + (texture_transforms.emissive_rotation.x * _6184));
    }
    else
    {
        _13483 = v_texture_coords;
    }
    vec3 _5585 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _13499 = vec3(0.0);
    if (dot(abs(_5585), vec3(1.0)) > 0.0)
    {
        vec3 _5594 = texture(emissive_texture, _13483).xyz;
        _13499 = mix(_5594 * vec3(0.077399380505084991455078125), pow((_5594 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5594)) * _5585;
    }
    else
    {
        _13499 = vec3(0.0);
    }
    highp float hp_copy_13524 = 0.0;
    vec3 _6428 = vec4((mix(_5459 * vec3(0.077399380505084991455078125), pow((_5459 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5459)) * _5440.xyz) * frag_info.color.xyz, _14501).xyz;
    vec3 _7238 = dFdx(_13476);
    vec3 _7240 = dFdy(_13476);
    float _13524 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _13524 = sqrt(clamp((_5539 * _5539) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7238, _7238), dot(_7240, _7240))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _13524 = _5539;
    }
    hp_copy_13524 = _13524;
    vec4 _13549 = vec4(0.0);
    float _13567 = 0.0;
    vec3 _13582 = vec3(0.0);
    float _13612 = 0.0;
    vec3 _13633 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _6455 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _13525 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _13525 = _6455.w;
        }
        else
        {
            _13525 = _6455.x;
        }
        float _6468 = min(_5566, _13525);
        bool _6471 = frag_info.ssao_lighting.z > 0.5;
        bool _6477 = false;
        if (_6471)
        {
            _6477 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _6477 = _6471;
        }
        vec3 _13583 = vec3(0.0);
        if (_6477)
        {
            vec2 _7278 = (_6455.zw * 2.0) - vec2(1.0);
            float _7280 = _7278.x;
            float _7282 = _7278.y;
            float _7290 = (1.0 - abs(_7280)) - abs(_7282);
            vec3 _7291 = vec3(_7280, _7282, _7290);
            vec3 _13528 = vec3(0.0);
            if (_7290 < 0.0)
            {
                vec2 _7304 = (vec2(1.0) - abs(_7291.yx)) * vec2((_7280 >= 0.0) ? 1.0 : (-1.0), (_7282 >= 0.0) ? 1.0 : (-1.0));
                vec3 _13128 = _7291;
                _13128.x = _7304.x;
                _13128.y = _7304.y;
                _13528 = _13128;
            }
            else
            {
                _13528 = _7291;
            }
            vec3 _7312 = -normalize(_13528);
            _13583 = normalize(((frag_info.camera_right.xyz * _7312.x) + (frag_info.camera_up.xyz * _7312.y)) + (frag_info.camera_forward.xyz * _7312.z));
        }
        else
        {
            _13583 = vec3(0.0);
        }
        vec3 _6505 = vec3(_6468);
        _13633 = mix(_6505, max(_6505, ((((((_6428 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _6468) + ((_6428 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _6468) + ((_6428 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _6468), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _13612 = _6468;
        _13582 = _13583;
        _13567 = float(_6477);
        _13549 = _6455;
    }
    else
    {
        _13633 = vec3(_5566);
        _13612 = _5566;
        _13582 = vec3(0.0);
        _13567 = 0.0;
        _13549 = vec4(1.0);
    }
    bool _6517 = frag_info.has_directional_light > 0.5;
    float _13532 = 0.0;
    vec3 _13663 = vec3(0.0);
    if (_6517)
    {
        highp vec3 _6523 = -normalize(frag_info.directional_light_direction.xyz);
        _13663 = _6523;
        _13532 = dot(_5398, _6523);
    }
    else
    {
        _13663 = vec3(0.0);
        _13532 = 0.0;
    }
    float _6530 = clamp(_13532 * 6.666666507720947265625, 0.0, 1.0);
    bool _6539 = false;
    if (_6517)
    {
        _6539 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _6539 = _6517;
    }
    float _13541 = 0.0;
    if (_6539 && (_6530 > 0.0))
    {
        int _7403 = int(frag_info.shadow_cascade_count);
        float _7598 = max(dot(_5398, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _7601 = _7598 * _7598;
        highp vec3 _7621 = v_position + (_5398 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _7601, 0.0)) / _7601, 8.0))));
        highp float _7409 = frag_info.directional_light_color.w * 0.5;
        float _7411 = frag_info.dielectric_f0.w;
        highp float hp_copy_7411 = _7411;
        float _13533 = 0.0;
        if (_7411 > 0.0)
        {
            _13533 = smoothstep(_7411 - max(frag_info.shadow_fade, hp_copy_7411 * 0.100000001490116119384765625), _7411, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _13533 = 0.0;
        }
        float _13535 = 0.0;
        float _13537 = 0.0;
        if (_13533 < 1.0)
        {
            float _13536 = 0.0;
            float _13538 = 0.0;
            _13538 = 0.0;
            _13536 = 0.0;
            float _14028 = 0.0;
            float _14031 = 0.0;
            for (int _13534 = 0; _13534 < _7403; _13538 = _14031, _13536 = _14028, _13534++)
            {
                if (_13538 < 1.0)
                {
                    highp vec4 _7443 = vec4(_7621, 1.0);
                    highp vec4 _13900 = vec4(0.0);
                    highp float _13903 = 0.0;
                    if (_13534 == 0)
                    {
                        _13903 = frag_info.cascade_box_sizes.x;
                        _13900 = frag_info.light_space_matrix[0] * _7443;
                    }
                    else
                    {
                        highp vec4 _13901 = vec4(0.0);
                        highp float _13904 = 0.0;
                        if (_13534 == 1)
                        {
                            _13904 = frag_info.cascade_box_sizes.y;
                            _13901 = frag_info.light_space_matrix[1] * _7443;
                        }
                        else
                        {
                            highp vec4 _13902 = vec4(0.0);
                            highp float _13905 = 0.0;
                            if (_13534 == 2)
                            {
                                _13905 = frag_info.cascade_box_sizes.z;
                                _13902 = frag_info.light_space_matrix[2] * _7443;
                            }
                            else
                            {
                                _13905 = frag_info.cascade_box_sizes.w;
                                _13902 = frag_info.light_space_matrix[3] * _7443;
                            }
                            _13904 = _13905;
                            _13901 = _13902;
                        }
                        _13903 = _13904;
                        _13900 = _13901;
                    }
                    highp vec3 _7488 = _13900.xyz / vec3(_13900.w);
                    highp vec2 _7491 = _7488.xy * 0.5;
                    highp vec2 _7493 = _7491 + vec2(0.5);
                    highp float _7500 = max(frag_info.shadow_softness / _13903, frag_info.shadow_texel_size);
                    highp float _7502 = _7493.x;
                    bool _7504 = _7502 < _7500;
                    bool _7513 = false;
                    if (!_7504)
                    {
                        _7513 = _7502 > (1.0 - _7500);
                    }
                    else
                    {
                        _7513 = _7504;
                    }
                    bool _7521 = false;
                    if (!_7513)
                    {
                        _7521 = _7493.y < _7500;
                    }
                    else
                    {
                        _7521 = _7513;
                    }
                    bool _7530 = false;
                    if (!_7521)
                    {
                        _7530 = _7493.y > (1.0 - _7500);
                    }
                    else
                    {
                        _7530 = _7521;
                    }
                    bool _7537 = false;
                    if (!_7530)
                    {
                        _7537 = _7488.z < 0.0;
                    }
                    else
                    {
                        _7537 = _7530;
                    }
                    bool _7544 = false;
                    if (!_7537)
                    {
                        _7544 = _7488.z > 1.0;
                    }
                    else
                    {
                        _7544 = _7537;
                    }
                    float _14029 = 0.0;
                    float _14032 = 0.0;
                    if (!_7544)
                    {
                        highp vec2 _7637 = vec2(_7500);
                        highp vec2 _7642 = vec2(_7500 + max(_7409, 9.9999997473787516355514526367188e-05));
                        highp vec2 _7650 = vec2(0.5) - _7491;
                        highp vec2 _7652 = smoothstep(_7637, _7642, _7493) * smoothstep(_7637, _7642, _7650);
                        float _13906 = 0.0;
                        if (_7409 > 0.0)
                        {
                            _13906 = _7652.x * _7652.y;
                        }
                        else
                        {
                            _13906 = 1.0;
                        }
                        float _7553 = min(_13906, 1.0 - _13538);
                        float _14030 = 0.0;
                        float _14033 = 0.0;
                        if (_7553 > 0.0)
                        {
                            highp float _7791 = _7488.z - (frag_info.shadow_bias / (7.0 * _13903));
                            highp float _7797 = 1.0 / (float(_7403) + frag_info.spot_shadow_params.x);
                            highp float _7799 = frag_info.directional_light_direction.w;
                            float mp_copy_7799 = _7799;
                            float _7805 = step(0.5, mp_copy_7799) * (1.0 - step(1.5, mp_copy_7799));
                            float _13936 = 0.0;
                            float _13940 = 0.0;
                            if (_7805 < 0.5)
                            {
                                highp float _7816 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_7816 = _7816;
                                _13940 = sin(mp_copy_7816);
                                _13936 = cos(mp_copy_7816);
                            }
                            else
                            {
                                _13940 = 0.0;
                                _13936 = 1.0;
                            }
                            highp float _13943 = 0.0;
                            if ((_7799 > 1.5) && (_7799 < 2.5))
                            {
                                highp float _7840 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _7845 = max(_7840 * _7791, frag_info.shadow_texel_size);
                                float _13932 = 0.0;
                                highp float _13933 = 0.0;
                                _13933 = 0.0;
                                _13932 = 0.0;
                                highp float _7867 = 0.0;
                                float _7870 = 0.0;
                                for (int _13931 = 0; _13931 < 9; _13933 = _7867, _13932 = _7870, _13931++)
                                {
                                    vec2 _14022 = vec2(0.0);
                                    do
                                    {
                                        if (_13931 == 0)
                                        {
                                            _14022 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_13931 == 1)
                                        {
                                            _14022 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_13931 == 2)
                                        {
                                            _14022 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_13931 == 3)
                                        {
                                            _14022 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_13931 == 4)
                                        {
                                            _14022 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_13931 == 5)
                                        {
                                            _14022 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_13931 == 6)
                                        {
                                            _14022 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_13931 == 7)
                                        {
                                            _14022 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_13931 == 8)
                                        {
                                            _14022 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_13931 == 9)
                                        {
                                            _14022 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_13931 == 10)
                                        {
                                            _14022 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_13931 == 11)
                                        {
                                            _14022 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_13931 == 12)
                                        {
                                            _14022 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_13931 == 13)
                                        {
                                            _14022 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_13931 == 14)
                                        {
                                            _14022 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_13931 == 15)
                                        {
                                            _14022 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _14022 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8174 = clamp(_7493 + (vec2((_14022.x * _13936) - (_14022.y * _13940), (_14022.x * _13940) + (_14022.y * _13936)) * _7845), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8183 = _8174.y;
                                    highp vec2 _8184 = vec2((float(_13534) + _8174.x) * _7797, _8183);
                                    _8184.y = 1.0 - _8183;
                                    highp vec4 _8191 = textureLod(shadow_map, _8184, 0.0);
                                    highp float _8192 = _8191.x;
                                    highp float _7862 = step(_8192, _7791);
                                    float mp_copy_7862 = _7862;
                                    _7867 = _13933 + (_8192 * _7862);
                                    _7870 = _13932 + mp_copy_7862;
                                }
                                highp float _13934 = 0.0;
                                if (_13932 > 0.0)
                                {
                                    _13934 = _13933 / _13932;
                                }
                                else
                                {
                                    _13934 = _7791;
                                }
                                _13943 = clamp(_7840 * max(_7791 - _13934, 0.0), frag_info.shadow_texel_size, _7500);
                            }
                            else
                            {
                                _13943 = _7500;
                            }
                            bool _7901 = _7799 > 2.5;
                            bool _13944 = false;
                            float _13968 = 0.0;
                            if ((_7799 < 1.5) || _7901)
                            {
                                highp vec2 _8225 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8229 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8230 = clamp(_7493, _8225, _8229);
                                highp float _8232 = float(_13534);
                                highp float _8239 = _8230.y;
                                highp vec2 _8240 = vec2((_8232 + _8230.x) * _7797, _8239);
                                _8240.y = 1.0 - _8239;
                                highp float _8252 = float(_7791 <= textureLod(shadow_map, _8240, 0.0).x);
                                float mp_copy_8252 = _8252;
                                float _8262 = (-1.0) * _13936;
                                float _8266 = (-1.0) * _13940;
                                highp vec2 _8290 = clamp(_7493 + (vec2(_8262 - _8266, _8266 + _8262) * _13943), _8225, _8229);
                                highp float _8299 = _8290.y;
                                highp vec2 _8300 = vec2((_8232 + _8290.x) * _7797, _8299);
                                _8300.y = 1.0 - _8299;
                                highp float _8312 = float(_7791 <= textureLod(shadow_map, _8300, 0.0).x);
                                float mp_copy_8312 = _8312;
                                highp vec2 _8350 = clamp(_7493 + (vec2(_13936 - _8266, _13940 + _8262) * _13943), _8225, _8229);
                                highp float _8359 = _8350.y;
                                highp vec2 _8360 = vec2((_8232 + _8350.x) * _7797, _8359);
                                _8360.y = 1.0 - _8359;
                                highp float _8372 = float(_7791 <= textureLod(shadow_map, _8360, 0.0).x);
                                float mp_copy_8372 = _8372;
                                highp vec2 _8410 = clamp(_7493 + (vec2(_8262 - _13940, _8266 + _13936) * _13943), _8225, _8229);
                                highp float _8419 = _8410.y;
                                highp vec2 _8420 = vec2((_8232 + _8410.x) * _7797, _8419);
                                _8420.y = 1.0 - _8419;
                                highp float _8432 = float(_7791 <= textureLod(shadow_map, _8420, 0.0).x);
                                float mp_copy_8432 = _8432;
                                highp vec2 _8470 = clamp(_7493 + (vec2(_13936 - _13940, _13940 + _13936) * _13943), _8225, _8229);
                                highp float _8479 = _8470.y;
                                highp vec2 _8480 = vec2((_8232 + _8470.x) * _7797, _8479);
                                _8480.y = 1.0 - _8479;
                                highp float _8492 = float(_7791 <= textureLod(shadow_map, _8480, 0.0).x);
                                float mp_copy_8492 = _8492;
                                float _7947 = (((mp_copy_8252 + mp_copy_8312) + mp_copy_8372) + mp_copy_8432) + mp_copy_8492;
                                _13968 = _7947 * 0.20000000298023223876953125;
                                _13944 = (_7947 < 0.5) || (_7947 > 4.5);
                            }
                            else
                            {
                                _13968 = 0.0;
                                _13944 = false;
                            }
                            float _13967 = 0.0;
                            if (_13944)
                            {
                                _13967 = _13968;
                            }
                            else
                            {
                                float _13969 = 0.0;
                                if (_7901)
                                {
                                    highp vec2 _8520 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _8524 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _8525 = clamp(_7493 + (vec2(-0.707099974155426025390625) * _13943), _8520, _8524);
                                    highp vec2 _8536 = (vec2(_8525.x, 1.0 - _8525.y) / _8520) - vec2(0.5);
                                    highp vec2 _8538 = floor(_8536);
                                    highp vec2 _8541 = _8536 - _8538;
                                    highp vec2 _8546 = (_8538 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _8548 = float(_13534);
                                    highp vec2 _8556 = vec2((_8548 + _8546.x) * _7797, _8546.y);
                                    highp float _8560 = frag_info.shadow_texel_size * _7797;
                                    highp vec2 _8563 = vec2(_8560, frag_info.shadow_texel_size);
                                    highp vec2 _8572 = vec2(_8560, 0.0);
                                    highp vec2 _8580 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _8609 = _8541.x;
                                    highp float _8618 = mix(mix(float(_7791 <= textureLod(shadow_map, _8556, 0.0).x), float(_7791 <= textureLod(shadow_map, _8556 + _8572, 0.0).x), _8609), mix(float(_7791 <= textureLod(shadow_map, _8556 + _8580, 0.0).x), float(_7791 <= textureLod(shadow_map, _8556 + _8563, 0.0).x), _8609), _8541.y);
                                    float mp_copy_8618 = _8618;
                                    highp vec2 _8652 = clamp(_7493 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _13943), _8520, _8524);
                                    highp vec2 _8663 = (vec2(_8652.x, 1.0 - _8652.y) / _8520) - vec2(0.5);
                                    highp vec2 _8665 = floor(_8663);
                                    highp vec2 _8668 = _8663 - _8665;
                                    highp vec2 _8673 = (_8665 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8683 = vec2((_8548 + _8673.x) * _7797, _8673.y);
                                    highp float _8736 = _8668.x;
                                    highp float _8745 = mix(mix(float(_7791 <= textureLod(shadow_map, _8683, 0.0).x), float(_7791 <= textureLod(shadow_map, _8683 + _8572, 0.0).x), _8736), mix(float(_7791 <= textureLod(shadow_map, _8683 + _8580, 0.0).x), float(_7791 <= textureLod(shadow_map, _8683 + _8563, 0.0).x), _8736), _8668.y);
                                    float mp_copy_8745 = _8745;
                                    highp vec2 _8779 = clamp(_7493 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _13943), _8520, _8524);
                                    highp vec2 _8790 = (vec2(_8779.x, 1.0 - _8779.y) / _8520) - vec2(0.5);
                                    highp vec2 _8792 = floor(_8790);
                                    highp vec2 _8795 = _8790 - _8792;
                                    highp vec2 _8800 = (_8792 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8810 = vec2((_8548 + _8800.x) * _7797, _8800.y);
                                    highp float _8863 = _8795.x;
                                    highp float _8872 = mix(mix(float(_7791 <= textureLod(shadow_map, _8810, 0.0).x), float(_7791 <= textureLod(shadow_map, _8810 + _8572, 0.0).x), _8863), mix(float(_7791 <= textureLod(shadow_map, _8810 + _8580, 0.0).x), float(_7791 <= textureLod(shadow_map, _8810 + _8563, 0.0).x), _8863), _8795.y);
                                    float mp_copy_8872 = _8872;
                                    highp vec2 _8906 = clamp(_7493 + (vec2(0.707099974155426025390625) * _13943), _8520, _8524);
                                    highp vec2 _8917 = (vec2(_8906.x, 1.0 - _8906.y) / _8520) - vec2(0.5);
                                    highp vec2 _8919 = floor(_8917);
                                    highp vec2 _8922 = _8917 - _8919;
                                    highp vec2 _8927 = (_8919 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8937 = vec2((_8548 + _8927.x) * _7797, _8927.y);
                                    highp float _8990 = _8922.x;
                                    highp float _8999 = mix(mix(float(_7791 <= textureLod(shadow_map, _8937, 0.0).x), float(_7791 <= textureLod(shadow_map, _8937 + _8572, 0.0).x), _8990), mix(float(_7791 <= textureLod(shadow_map, _8937 + _8580, 0.0).x), float(_7791 <= textureLod(shadow_map, _8937 + _8563, 0.0).x), _8990), _8922.y);
                                    float mp_copy_8999 = _8999;
                                    _13969 = (((mp_copy_8618 + mp_copy_8745) + mp_copy_8872) + mp_copy_8999) * 0.25;
                                }
                                else
                                {
                                    int _7994 = (_7805 > 0.5) ? 17 : 16;
                                    float _13963 = 0.0;
                                    _13963 = 0.0;
                                    float _8022 = 0.0;
                                    for (int _13945 = 0; _13945 < 17; _13963 = _8022, _13945++)
                                    {
                                        if (_13945 >= _7994)
                                        {
                                            break;
                                        }
                                        vec2 _13946 = vec2(0.0);
                                        do
                                        {
                                            if (_13945 == 0)
                                            {
                                                _13946 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_13945 == 1)
                                            {
                                                _13946 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_13945 == 2)
                                            {
                                                _13946 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_13945 == 3)
                                            {
                                                _13946 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_13945 == 4)
                                            {
                                                _13946 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_13945 == 5)
                                            {
                                                _13946 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_13945 == 6)
                                            {
                                                _13946 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_13945 == 7)
                                            {
                                                _13946 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_13945 == 8)
                                            {
                                                _13946 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_13945 == 9)
                                            {
                                                _13946 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_13945 == 10)
                                            {
                                                _13946 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_13945 == 11)
                                            {
                                                _13946 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_13945 == 12)
                                            {
                                                _13946 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_13945 == 13)
                                            {
                                                _13946 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_13945 == 14)
                                            {
                                                _13946 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_13945 == 15)
                                            {
                                                _13946 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _13946 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _13948 = vec2(0.0);
                                        do
                                        {
                                            if (_13945 < 3)
                                            {
                                                _13948 = vec2(float(_13945) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_13945 < 6)
                                            {
                                                _13948 = vec2((float(_13945 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_13945 < 11)
                                            {
                                                _13948 = vec2((float(_13945 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_13945 < 14)
                                            {
                                                _13948 = vec2((float(_13945 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _13948 = vec2(float(_13945 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8011 = mix(_13946, _13948, vec2(_7805));
                                        float _9139 = _8011.x;
                                        float _9143 = _8011.y;
                                        highp vec2 _9169 = clamp(_7493 + (vec2((_9139 * _13936) - (_9143 * _13940), (_9139 * _13940) + (_9143 * _13936)) * _13943), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9178 = _9169.y;
                                        highp vec2 _9179 = vec2((float(_13534) + _9169.x) * _7797, _9178);
                                        _9179.y = 1.0 - _9178;
                                        highp float _9191 = float(_7791 <= textureLod(shadow_map, _9179, 0.0).x);
                                        float mp_copy_9191 = _9191;
                                        _8022 = _13963 + mp_copy_9191;
                                    }
                                    _13969 = _13963 / float(_7994);
                                }
                                _13967 = _13969;
                            }
                            bool _8036 = _13534 == (_7403 - 1);
                            bool _8042 = false;
                            if (_8036)
                            {
                                _8042 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8042 = _8036;
                            }
                            float _13970 = 0.0;
                            if (_8042)
                            {
                                highp vec2 _8049 = vec2(frag_info.shadow_fade / _13903);
                                highp vec2 _8057 = smoothstep(vec2(0.0), _8049, _7493) * smoothstep(vec2(0.0), _8049, _7650);
                                _13970 = mix(1.0, _13967, _8057.x * _8057.y);
                            }
                            else
                            {
                                _13970 = _13967;
                            }
                            _14033 = _13538 + _7553;
                            _14030 = _13536 + (_7553 * _13970);
                        }
                        else
                        {
                            _14033 = _13538;
                            _14030 = _13536;
                        }
                        _14032 = _14033;
                        _14029 = _14030;
                    }
                    else
                    {
                        _14032 = _13538;
                        _14029 = _13536;
                    }
                    _14031 = _14032;
                    _14028 = _14029;
                }
                else
                {
                    _14031 = _13538;
                    _14028 = _13536;
                }
            }
            _13537 = _13538;
            _13535 = _13536;
        }
        else
        {
            _13537 = 0.0;
            _13535 = 0.0;
        }
        _13541 = mix(_13535 + (1.0 - _13537), 1.0, _13533);
    }
    else
    {
        _13541 = 1.0;
    }
    bool _6552 = frag_info.ssao_lighting.w > 0.5;
    bool _6558 = false;
    if (_6552)
    {
        _6558 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _6558 = _6552;
    }
    float _13553 = 0.0;
    if (_6558)
    {
        _13553 = min(_13541, _13549.y);
    }
    else
    {
        _13553 = _13541;
    }
    vec3 mp_copy_13554 = vec3(0.0);
    float _6567 = _6530 * _13553;
    bool _9198 = view_info.camera_forward.w > 0.5;
    highp vec3 _13554 = vec3(0.0);
    if (_9198)
    {
        _13554 = -view_info.camera_forward.xyz;
    }
    else
    {
        _13554 = normalize(v_viewvector);
    }
    highp float _9242 = 0.0;
    mp_copy_13554 = _13554;
    vec3 _6576 = mix(frag_info.dielectric_f0.xyz, _6428, vec3(_5532));
    float _6579 = dot(_13476, _13554);
    float _6580 = max(_6579, 0.0);
    float _6584 = max(dot(_5398, _13554), 0.0);
    vec3 _6588 = reflect(-mp_copy_13554, _13476);
    highp vec2 _13555 = vec2(0.0);
    do
    {
        _9242 = frag_info.punctual_dims.x;
        if (_9242 < 0.5)
        {
            _13555 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9254 = v_position - frag_info.camera_position.xyz;
            highp float _9269 = dot(_9254, frag_info.camera_forward.xyz);
            highp float _9275 = max(_9269, 9.9999997473787516355514526367188e-05);
            highp vec2 _9378 = (vec3(dot(_9254, frag_info.camera_right.xyz), dot(_9254, frag_info.camera_up.xyz), _9275).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9275, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _9393 = float(int(((((clamp(floor((log2(max(_9269 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9378.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9378.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _13555 = vec2(textureLod(punctual_index, vec2((mod(_9393, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9393 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _13555 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _6593 = int(_13555.x + 0.5);
    mediump int _6597 = int(_13555.y + 0.5);
    highp vec3 _13678 = vec3(0.0);
    _13678 = vec3(0.0);
    highp vec3 _14438 = vec3(0.0);
    for (int _13556 = 0; _13556 < _6597; _13678 = _14438, _13556++)
    {
        highp float _9426 = float(_6593 + _13556);
        highp float _9457 = (float(int(textureLod(punctual_index, vec2((mod(_9426, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9426 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9242;
        highp vec2 _9458 = vec2(0.0625, _9457);
        highp vec4 _9461 = textureLod(punctual_lights, _9458, 0.0);
        highp vec4 _9478 = textureLod(punctual_lights, vec2(0.1875, _9457), 0.0);
        highp float _6615 = _9461.w;
        highp vec3 _6617 = _9478.xyz;
        highp vec3 _14439 = vec3(0.0);
        if (_6615 > 2.5)
        {
            highp vec4 _9495 = textureLod(punctual_lights, vec2(0.3125, _9457), 0.0);
            highp vec4 _9512 = textureLod(punctual_lights, vec2(0.4375, _9457), 0.0);
            highp vec3 _6631 = _9495.xyz * (_9495.w * 0.5);
            highp vec3 _6637 = _9512.xyz * (_9512.w * 0.5);
            highp vec3 _6639 = _9461.xyz;
            highp vec3 _6641 = _6639 - _6631;
            highp vec3 _6643 = _6641 - _6637;
            highp vec3 _6647 = _6639 + _6631;
            highp vec3 _6649 = _6647 - _6637;
            highp vec3 _6661 = _6641 + _6637;
            highp vec3 _6665 = _6639 - v_position;
            highp float _6671 = _9478.w;
            highp float _6675 = (dot(_6665, _6665) * _6671) * _6671;
            highp float _6680 = clamp(1.0 - (_6675 * _6675), 0.0, 1.0);
            float mp_copy_6680 = _6680;
            vec2 _9519 = (clamp(vec2(_13524, sqrt(1.0 - _6580)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _9521 = _9519.x;
            float _9526 = _9519.y;
            vec4 _6704 = textureLod(brdf_lut, vec2((_9521 + 1.0) * 0.3333333432674407958984375, _9526), 0.0);
            vec4 _6708 = textureLod(brdf_lut, vec2((_9521 + 2.0) * 0.3333333432674407958984375, _9526), 0.0);
            vec3 _9569 = normalize(mp_copy_13554 - (_13476 * _6579));
            mat3 _9591 = transpose(mat3(_9569, -cross(_13476, _9569), _13476));
            mat3 _9592 = mat3(vec3(_6704.x, 0.0, _6704.y), vec3(0.0, 1.0, 0.0), vec3(_6704.z, 0.0, _6704.w)) * _9591;
            highp vec3 _9596 = _6643 - v_position;
            highp vec3 _9598 = normalize(_9592 * _9596);
            vec3 mp_copy_9598 = _9598;
            highp vec3 _9602 = _6649 - v_position;
            highp vec3 _9604 = normalize(_9592 * _9602);
            vec3 mp_copy_9604 = _9604;
            highp vec3 _9608 = (_6647 + _6637) - v_position;
            highp vec3 _9610 = normalize(_9592 * _9608);
            vec3 mp_copy_9610 = _9610;
            highp vec3 _9614 = _6661 - v_position;
            highp vec3 _9616 = normalize(_9592 * _9614);
            vec3 mp_copy_9616 = _9616;
            float _9645 = dot(_9598, _9604);
            float _9647 = abs(_9645);
            float _9661 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9647)) * _9647)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9647) * _9647));
            float _13839 = 0.0;
            if (_9645 > 0.0)
            {
                _13839 = _9661;
            }
            else
            {
                _13839 = (0.5 * inversesqrt(max(1.0 - (_9645 * _9645), 1.0000000116860974230803549289703e-07))) - _9661;
            }
            float _9694 = dot(_9604, _9610);
            float _9696 = abs(_9694);
            float _9710 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9696)) * _9696)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9696) * _9696));
            float _13840 = 0.0;
            if (_9694 > 0.0)
            {
                _13840 = _9710;
            }
            else
            {
                _13840 = (0.5 * inversesqrt(max(1.0 - (_9694 * _9694), 1.0000000116860974230803549289703e-07))) - _9710;
            }
            float _9743 = dot(_9610, _9616);
            float _9745 = abs(_9743);
            float _9759 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9745)) * _9745)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9745) * _9745));
            float _13841 = 0.0;
            if (_9743 > 0.0)
            {
                _13841 = _9759;
            }
            else
            {
                _13841 = (0.5 * inversesqrt(max(1.0 - (_9743 * _9743), 1.0000000116860974230803549289703e-07))) - _9759;
            }
            float _9792 = dot(_9616, _9598);
            float _9794 = abs(_9792);
            float _9808 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9794)) * _9794)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9794) * _9794));
            float _13842 = 0.0;
            if (_9792 > 0.0)
            {
                _13842 = _9808;
            }
            else
            {
                _13842 = (0.5 * inversesqrt(max(1.0 - (_9792 * _9792), 1.0000000116860974230803549289703e-07))) - _9808;
            }
            vec3 _9631 = (((cross(mp_copy_9598, mp_copy_9604) * _13839) + (cross(mp_copy_9604, mp_copy_9610) * _13840)) + (cross(mp_copy_9610, mp_copy_9616) * _13841)) + (cross(mp_copy_9616, mp_copy_9598) * _13842);
            float _9834 = length(_9631);
            mat3 _9894 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _9591;
            highp vec3 _9900 = normalize(_9894 * _9596);
            vec3 mp_copy_9900 = _9900;
            highp vec3 _9906 = normalize(_9894 * _9602);
            vec3 mp_copy_9906 = _9906;
            highp vec3 _9912 = normalize(_9894 * _9608);
            vec3 mp_copy_9912 = _9912;
            highp vec3 _9918 = normalize(_9894 * _9614);
            vec3 mp_copy_9918 = _9918;
            float _9947 = dot(_9900, _9906);
            float _9949 = abs(_9947);
            float _9963 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9949)) * _9949)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9949) * _9949));
            float _13843 = 0.0;
            if (_9947 > 0.0)
            {
                _13843 = _9963;
            }
            else
            {
                _13843 = (0.5 * inversesqrt(max(1.0 - (_9947 * _9947), 1.0000000116860974230803549289703e-07))) - _9963;
            }
            float _9996 = dot(_9906, _9912);
            float _9998 = abs(_9996);
            float _10012 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _9998)) * _9998)) / (3.41759395599365234375 + ((4.1616725921630859375 + _9998) * _9998));
            float _13844 = 0.0;
            if (_9996 > 0.0)
            {
                _13844 = _10012;
            }
            else
            {
                _13844 = (0.5 * inversesqrt(max(1.0 - (_9996 * _9996), 1.0000000116860974230803549289703e-07))) - _10012;
            }
            float _10045 = dot(_9912, _9918);
            float _10047 = abs(_10045);
            float _10061 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10047)) * _10047)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10047) * _10047));
            float _13845 = 0.0;
            if (_10045 > 0.0)
            {
                _13845 = _10061;
            }
            else
            {
                _13845 = (0.5 * inversesqrt(max(1.0 - (_10045 * _10045), 1.0000000116860974230803549289703e-07))) - _10061;
            }
            float _10094 = dot(_9918, _9900);
            float _10096 = abs(_10094);
            float _10110 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10096)) * _10096)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10096) * _10096));
            float _13846 = 0.0;
            if (_10094 > 0.0)
            {
                _13846 = _10110;
            }
            else
            {
                _13846 = (0.5 * inversesqrt(max(1.0 - (_10094 * _10094), 1.0000000116860974230803549289703e-07))) - _10110;
            }
            vec3 _9933 = (((cross(mp_copy_9900, mp_copy_9906) * _13843) + (cross(mp_copy_9906, mp_copy_9912) * _13844)) + (cross(mp_copy_9912, mp_copy_9918) * _13845)) + (cross(mp_copy_9918, mp_copy_9900) * _13846);
            float _10136 = length(_9933);
            _14439 = _13678 + (((_6617 * (mp_copy_6680 * mp_copy_6680)) * step(0.0, dot(cross(_6649 - _6643, _6661 - _6643), v_position - _6643))) * (((((_6576 * _6708.x) + ((vec3(1.0) - _6576) * _6708.y)) * max(((_9834 * _9834) + _9631.z) / (_9834 + 1.0), 0.0)) * 1.0) + ((_6428 * (1.0 - _5532)) * max(((_10136 * _10136) + _9933.z) / (_10136 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_13783 = 0.0;
            vec3 _13756 = vec3(0.0);
            highp vec3 _13779 = vec3(0.0);
            float _13783 = 0.0;
            if (_6615 < 0.5)
            {
                _13783 = _13524;
                _13779 = _6617;
                _13756 = -normalize(textureLod(punctual_lights, vec2(0.3125, _9457), 0.0).xyz);
            }
            else
            {
                highp vec3 _6795 = _9461.xyz - v_position;
                highp float _6798 = dot(_6795, _6795);
                highp float _6802 = inversesqrt(max(_6798, 9.9999999392252902907785028219223e-09));
                highp vec3 _6803 = _6795 * _6802;
                vec3 mp_copy_6803 = _6803;
                highp float _6805 = _9478.w;
                highp float _6810 = (_6798 * _6805) * _6805;
                highp float _6815 = clamp(1.0 - (_6810 * _6810), 0.0, 1.0);
                float mp_copy_6815 = _6815;
                if (_6815 <= 0.0)
                {
                    _14438 = _13678;
                    continue;
                }
                highp vec4 _10180 = textureLod(punctual_lights, vec2(0.4375, _9457), 0.0);
                highp float _6823 = _10180.w;
                float _13788 = 0.0;
                if (_6823 > 0.0)
                {
                    highp float _6850 = (_13524 * _13524) + ((_6823 * 0.5) * _6802);
                    float mp_copy_6850 = _6850;
                    _13788 = sqrt(min(mp_copy_6850, 1.0));
                }
                else
                {
                    _13788 = _13524;
                }
                highp vec3 _6857 = _6617 * ((mp_copy_6815 * mp_copy_6815) / max(pow(max(_6798, _6823 * _6823), _10180.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _13780 = vec3(0.0);
                if (_6615 > 1.5)
                {
                    highp vec4 _10197 = textureLod(punctual_lights, vec2(0.3125, _9457), 0.0);
                    highp float _6876 = clamp((dot(normalize(_10197.xyz), -mp_copy_6803) * _10197.w) + _10180.x, 0.0, 1.0);
                    float mp_copy_6876 = _6876;
                    highp vec3 _6881 = _6857 * (mp_copy_6876 * mp_copy_6876);
                    if (_6876 <= 0.0)
                    {
                        _14438 = _13678;
                        continue;
                    }
                    bool _6887 = _6876 > 0.0;
                    bool _6893 = false;
                    if (_6887)
                    {
                        _6893 = _10180.y > (-0.5);
                    }
                    else
                    {
                        _6893 = _6887;
                    }
                    bool _6899 = false;
                    if (_6893)
                    {
                        _6899 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _6899 = _6893;
                    }
                    highp vec3 _13781 = vec3(0.0);
                    if (_6899)
                    {
                        float _13747 = 0.0;
                        do
                        {
                            highp vec4 _10309 = mat4(textureLod(punctual_lights, vec2(0.5625, _9457), 0.0), textureLod(punctual_lights, vec2(0.6875, _9457), 0.0), textureLod(punctual_lights, vec2(0.8125, _9457), 0.0), textureLod(punctual_lights, vec2(0.9375, _9457), 0.0)) * vec4(v_position + (_5398 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10311 = _10309.w;
                            if (_10311 <= 0.0)
                            {
                                _13747 = 1.0;
                                break;
                            }
                            highp vec3 _10320 = _10309.xyz / vec3(_10311);
                            highp vec2 _10325 = (_10320.xy * 0.5) + vec2(0.5);
                            highp float _10327 = _10325.x;
                            bool _10328 = _10327 < 0.0;
                            bool _10335 = false;
                            if (!_10328)
                            {
                                _10335 = _10327 > 1.0;
                            }
                            else
                            {
                                _10335 = _10328;
                            }
                            bool _10342 = false;
                            if (!_10335)
                            {
                                _10342 = _10325.y < 0.0;
                            }
                            else
                            {
                                _10342 = _10335;
                            }
                            bool _10349 = false;
                            if (!_10342)
                            {
                                _10349 = _10325.y > 1.0;
                            }
                            else
                            {
                                _10349 = _10342;
                            }
                            bool _10356 = false;
                            if (!_10349)
                            {
                                _10356 = _10320.z < 0.0;
                            }
                            else
                            {
                                _10356 = _10349;
                            }
                            bool _10363 = false;
                            if (!_10356)
                            {
                                _10363 = _10320.z > 1.0;
                            }
                            else
                            {
                                _10363 = _10356;
                            }
                            if (_10363)
                            {
                                _13747 = 1.0;
                                break;
                            }
                            highp float _10370 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _10375 = frag_info.shadow_cascade_count + float(int(_10180.y + 0.5));
                            highp float _10380 = _10320.z - frag_info.spot_shadow_params.y;
                            highp float _10391 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_10391 = _10391;
                            highp vec2 _10398 = vec2(cos(mp_copy_10391), sin(mp_copy_10391)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _10400 = _10398.x;
                            highp float _10402 = _10398.y;
                            highp vec2 _10410 = vec2(_10400 - _10402, _10400 + _10402) * 0.707106769084930419921875;
                            highp float _10603 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10327, 0.0, 1.0)) / _10370, 1.0 - clamp(_10325.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10603 = _10603;
                            highp vec2 _10418 = _10325 + _10398;
                            highp float _10625 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10418.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10418.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10625 = _10625;
                            highp vec2 _10426 = _10325 - _10398;
                            highp float _10647 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10426.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10426.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10647 = _10647;
                            highp vec2 _10439 = _10325 + vec2(-_10402, _10400);
                            highp float _10669 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10439.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10439.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10669 = _10669;
                            highp vec2 _10452 = _10325 + vec2(_10402, -_10400);
                            highp float _10691 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10452.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10452.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10691 = _10691;
                            float _10457 = (((mp_copy_10603 + mp_copy_10625) + mp_copy_10647) + mp_copy_10669) + mp_copy_10691;
                            if ((_10457 < 0.5) || (_10457 > 4.5))
                            {
                                _13747 = _10457 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _10469 = _10325 + _10410;
                            highp float _10713 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10469.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10469.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10713 = _10713;
                            highp vec2 _10476 = _10325 - _10410;
                            highp float _10735 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10476.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10476.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10735 = _10735;
                            highp float _10484 = _10410.y;
                            highp float _10487 = _10410.x;
                            highp vec2 _10489 = _10325 + vec2(-_10484, _10487);
                            highp float _10757 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10489.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10489.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10757 = _10757;
                            highp vec2 _10502 = _10325 + vec2(_10484, -_10487);
                            highp float _10779 = float(_10380 <= textureLod(shadow_map, vec2((_10375 + clamp(_10502.x, 0.0, 1.0)) / _10370, 1.0 - clamp(_10502.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10779 = _10779;
                            _13747 = (_10457 + (((mp_copy_10713 + mp_copy_10735) + mp_copy_10757) + mp_copy_10779)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _13781 = _6881 * _13747;
                    }
                    else
                    {
                        _13781 = _6881;
                    }
                    _13780 = _13781;
                }
                else
                {
                    bool _6915 = _6615 > 0.5;
                    bool _6921 = false;
                    if (_6915)
                    {
                        _6921 = _10180.y > (-0.5);
                    }
                    else
                    {
                        _6921 = _6915;
                    }
                    bool _6927 = false;
                    if (_6921)
                    {
                        _6927 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _6927 = _6921;
                    }
                    highp vec3 _13782 = vec3(0.0);
                    if (_6927)
                    {
                        float _13734 = 0.0;
                        do
                        {
                            highp vec4 _11092 = textureLod(punctual_lights, vec2(0.5625, _9457), 0.0);
                            highp vec4 _11109 = textureLod(punctual_lights, vec2(0.6875, _9457), 0.0);
                            highp vec3 _10851 = (v_position + (_5398 * _11092.z)) - textureLod(punctual_lights, _9458, 0.0).xyz;
                            highp vec3 _10853 = abs(_10851);
                            highp float _10855 = _10853.x;
                            highp float _10857 = _10853.y;
                            bool _10858 = _10855 >= _10857;
                            bool _10866 = false;
                            if (_10858)
                            {
                                _10866 = _10855 >= _10853.z;
                            }
                            else
                            {
                                _10866 = _10858;
                            }
                            highp vec3 _13724 = vec3(0.0);
                            float _13726 = 0.0;
                            if (_10866)
                            {
                                highp float _10869 = _10851.x;
                                bool _10870 = _10869 >= 0.0;
                                highp vec3 _13723 = vec3(0.0);
                                if (_10870)
                                {
                                    _13723 = vec3(-_10851.z, _10851.y, _10869);
                                }
                                else
                                {
                                    _13723 = vec3(_10851.zy, -_10869);
                                }
                                _13726 = _10870 ? 0.0 : 1.0;
                                _13724 = _13723;
                            }
                            else
                            {
                                highp vec3 _13725 = vec3(0.0);
                                float _13728 = 0.0;
                                if (_10857 >= _10853.z)
                                {
                                    highp float _10903 = _10851.y;
                                    bool _10904 = _10903 >= 0.0;
                                    highp vec3 _13722 = vec3(0.0);
                                    if (_10904)
                                    {
                                        _13722 = vec3(-_10851.x, _10851.z, _10903);
                                    }
                                    else
                                    {
                                        _13722 = vec3(_10851.xz, -_10903);
                                    }
                                    _13728 = _10904 ? 2.0 : 3.0;
                                    _13725 = _13722;
                                }
                                else
                                {
                                    highp float _10931 = _10851.z;
                                    bool _10932 = _10931 >= 0.0;
                                    highp vec3 _13721 = vec3(0.0);
                                    if (_10932)
                                    {
                                        _13721 = _10851;
                                    }
                                    else
                                    {
                                        _13721 = vec3(-_10851.x, _10851.y, -_10931);
                                    }
                                    _13728 = _10932 ? 4.0 : 5.0;
                                    _13725 = _13721;
                                }
                                _13726 = _13728;
                                _13724 = _13725;
                            }
                            if (_13724.z <= 0.0)
                            {
                                _13734 = 1.0;
                                break;
                            }
                            highp vec2 _10972 = ((_13724.xy / vec2(_13724.z)) * 0.5) + vec2(0.5);
                            highp float _10983 = (_11092.x - (_11092.y / _13724.z)) - _11109.x;
                            if ((_10983 < 0.0) || (_10983 > 1.0))
                            {
                                _13734 = 1.0;
                                break;
                            }
                            highp float hp_copy_13731 = 0.0;
                            highp float _10995 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _11001 = _13726 >= 4.0;
                            highp float _11003 = (frag_info.shadow_cascade_count + _10180.y) + float(_11001);
                            float _13731 = 0.0;
                            if (_11001)
                            {
                                _13731 = _13726 - 4.0;
                            }
                            else
                            {
                                _13731 = _13726;
                            }
                            hp_copy_13731 = _13731;
                            highp float _11020 = _11109.y * 0.5;
                            highp float _11023 = _11092.w * 0.0040000001899898052215576171875;
                            highp vec2 _11134 = vec2(_11020);
                            highp vec2 _11137 = vec2(1.0 - _11020);
                            highp vec2 _11143 = vec2(mod(hp_copy_13731, 2.0), 1.0 - floor(hp_copy_13731 * 0.5)) * 0.5;
                            highp vec2 _11146 = _11143 + (clamp(_10972, _11134, _11137) * 0.5);
                            highp float _11039 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _13733 = 0.0;
                            _13733 = float(_10983 <= textureLod(shadow_map, vec2((_11003 + _11146.x) / _10995, 1.0 - _11146.y), 0.0).x);
                            for (int _13732 = 0; _13732 < 8; )
                            {
                                highp float _11049 = _11039 + (float(_13732) * 0.785398185253143310546875);
                                float mp_copy_11049 = _11049;
                                highp vec2 _11183 = _11143 + (clamp(_10972 + (vec2(cos(mp_copy_11049), sin(mp_copy_11049)) * _11023), _11134, _11137) * 0.5);
                                highp float _11200 = float(_10983 <= textureLod(shadow_map, vec2((_11003 + _11183.x) / _10995, 1.0 - _11183.y), 0.0).x);
                                float mp_copy_11200 = _11200;
                                _13733 += mp_copy_11200;
                                _13732++;
                                continue;
                            }
                            _13734 = _13733 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _13782 = _6857 * _13734;
                    }
                    else
                    {
                        _13782 = _6857;
                    }
                    _13780 = _13782;
                }
                _13783 = _13788;
                _13779 = _13780;
                _13756 = _6803;
            }
            hp_copy_13783 = _13783;
            highp vec3 _13810 = vec3(0.0);
            highp vec3 _13811 = vec3(0.0);
            do
            {
                float _11266 = max(dot(_13476, _13756), 0.0);
                highp float hp_copy_11266 = _11266;
                if (_11266 <= 0.0)
                {
                    _13811 = vec3(0.0);
                    _13810 = vec3(0.0);
                    break;
                }
                float _11272 = max(_6580, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11272 = _11272;
                vec3 _11275 = _13756 + mp_copy_13554;
                float _11278 = dot(_11275, _11275);
                vec3 _13808 = vec3(0.0);
                vec3 _13809 = vec3(0.0);
                if (_11278 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11286 = _11275 * inversesqrt(_11278);
                    float _13807 = 0.0;
                    do
                    {
                        float _11343 = dot(_13476, _11286);
                        if (_11343 <= 0.0)
                        {
                            _13807 = 0.0;
                            break;
                        }
                        float _11350 = _13783 * _13783;
                        vec3 _11353 = cross(_13476, _11286);
                        float _11356 = _11343 * _11350;
                        float _11365 = _11350 / (dot(_11353, _11353) + (_11356 * _11356));
                        _13807 = min((_11365 * _11365) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _11403 = _6576 + ((vec3(1.0) - _6576) * pow(clamp(1.0 - max(dot(_11286, _13554), 0.0), 0.0, 1.0), 5.0));
                    _13809 = (_11403 * min(_13807 * (0.5 / max(mix((2.0 * hp_copy_11266) * _11272, hp_copy_11266 + hp_copy_11272, hp_copy_13783 * hp_copy_13783), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _13808 = _11403;
                }
                else
                {
                    _13809 = vec3(0.0);
                    _13808 = _6576;
                }
                _13811 = (_13809 * _13779) * _11266;
                _13810 = (((((vec3(1.0) - _13808) * (1.0 - _5532)) * _6428) * 0.3183098733425140380859375) * _13779) * _11266;
                break;
            } while(false);
            _14439 = _13678 + (_13810 + _13811);
        }
        _14438 = _14439;
    }
    mat3 _6975 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _6978 = _13567 > 0.5;
    bvec3 _6981 = bvec3(_6978);
    highp vec3 _6982 = vec3(_6981.x ? _13582.x : _13476.x, _6981.y ? _13582.y : _13476.y, _6981.z ? _13582.z : _13476.z);
    vec3 mp_copy_6982 = _6982;
    vec3 _6983 = _6975 * mp_copy_6982;
    vec3 _13587 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _11450 = _6588 + (((step(vec3(0.0), _6588) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_11450 = _11450;
        highp vec3 _11452 = vec3(1.0) / hp_copy_11450;
        highp vec3 _11469 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _11452, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _11452);
        _13587 = normalize((v_position + (_6588 * max(min(min(_11469.x, _11469.y), _11469.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _13587 = _6588;
    }
    bool _11697 = false;
    vec3 _6988 = _6975 * _13587;
    float _11516 = _6983.y;
    float _11517 = 0.48860299587249755859375 * _11516;
    float _11523 = _6983.z;
    float _11524 = 0.48860299587249755859375 * _11523;
    float _11530 = _6983.x;
    float _11531 = 0.48860299587249755859375 * _11530;
    float _11538 = 1.09254801273345947265625 * _11530;
    float _11541 = _11538 * _11516;
    float _11551 = (1.09254801273345947265625 * _11516) * _11523;
    float _11563 = 0.3153919875621795654296875 * (((3.0 * _11523) * _11523) - 1.0);
    float _11573 = _11538 * _11523;
    float _11589 = 0.546274006366729736328125 * ((_11530 * _11530) - (_11516 * _11516));
    vec3 _6991 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _11517)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _11524)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _11531)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _11541)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _11551)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _11563)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _11573)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _11589), vec3(0.0));
    vec3 _13588 = vec3(0.0);
    do
    {
        _11697 = radiance_layout_info.mip_layout > 0.5;
        if (_11697)
        {
            vec2 _11776 = vec2(atan(_6988.z, _6988.x), asin(clamp(_6988.y, -1.0, 1.0)));
            highp vec2 hp_copy_11776 = _11776;
            _13588 = textureLod(prefiltered_radiance, (hp_copy_11776 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_13524, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _11795 = vec2(atan(_6988.z, _6988.x), asin(clamp(_6988.y, -1.0, 1.0)));
        highp vec2 hp_copy_11795 = _11795;
        highp vec2 _11800 = (hp_copy_11795 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _11707 = clamp(_11800.y, 0.00390625, 0.99609375);
        float _11711 = clamp(_13524, 0.0, 1.0) * 7.0;
        float _11713 = floor(_11711);
        highp float _11732 = _11800.x;
        _13588 = mix(textureLod(prefiltered_radiance, vec2(_11732, (_11713 + _11707) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_11732, (min(_11713 + 1.0, 7.0) + _11707) * 0.125), 0.0).xyz, vec3(_11711 - _11713));
        break;
    } while(false);
    bool _6998 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _13593 = vec3(0.0);
    highp vec3 _13594 = vec3(0.0);
    if (_6998)
    {
        vec3 _13589 = vec3(0.0);
        do
        {
            if (_11697)
            {
                vec2 _12088 = vec2(atan(_6988.z, _6988.x), asin(clamp(_6988.y, -1.0, 1.0)));
                highp vec2 hp_copy_12088 = _12088;
                _13589 = textureLod(prefiltered_radiance_b, (hp_copy_12088 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_13524, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _12107 = vec2(atan(_6988.z, _6988.x), asin(clamp(_6988.y, -1.0, 1.0)));
            highp vec2 hp_copy_12107 = _12107;
            highp vec2 _12112 = (hp_copy_12107 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12019 = clamp(_12112.y, 0.00390625, 0.99609375);
            float _12023 = clamp(_13524, 0.0, 1.0) * 7.0;
            float _12025 = floor(_12023);
            highp float _12044 = _12112.x;
            _13589 = mix(textureLod(prefiltered_radiance_b, vec2(_12044, (_12025 + _12019) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12044, (min(_12025 + 1.0, 7.0) + _12019) * 0.125), 0.0).xyz, vec3(_12023 - _12025));
            break;
        } while(false);
        highp vec3 _7009 = vec3(frag_info.radiance_blend.x);
        _13594 = mix(_13588, _13589, _7009);
        _13593 = mix(_6991, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _11517)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _11524)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _11531)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _11541)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _11551)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _11563)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _11573)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _11589), vec3(0.0)), _7009);
    }
    else
    {
        _13594 = _13588;
        _13593 = _6991;
    }
    vec2 _7031 = clamp(vec2(_6584, _13524), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7033 = texture(brdf_lut, vec2(_7031.x * 0.3333333432674407958984375, _7031.y));
    float _7037 = _7033.x;
    float _7040 = _7033.y;
    vec3 _7042 = ((_6576 + ((max(vec3(1.0 - _13524), _6576) - _6576) * pow(clamp(1.0 - _6584, 0.0, 1.0), 5.0))) * _7037) + vec3(_7040);
    float _7048 = 1.0 - (_7037 + _7040);
    vec3 _7052 = vec3(1.0) - _6576;
    vec3 _7055 = _6576 + (_7052 * vec3(0.0476190485060214996337890625));
    vec3 _7066 = ((_7042 * _7048) * _7055) / (vec3(1.0) - (_7055 * _7048));
    float _7069 = 1.0 - _5532;
    vec3 _7070 = _6428 * _7069;
    float _13637 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _6978)
    {
        float _12140 = max(acos(clamp(exp2(((-3.321929931640625) * _13524) * _13524), 0.0, 1.0)), 0.100000001490116119384765625);
        _13637 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_13582, _6588), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _13612, 0.0, 1.0)))) + _12140) / (2.0 * _12140), 0.0, 1.0));
    }
    else
    {
        float _13638 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _13638 = clamp((pow(_6580 + _13612, exp2(((-16.0) * _13524) - 1.0)) - 1.0) + _13612, 0.0, 1.0);
        }
        else
        {
            _13638 = _13612;
        }
        _13637 = _13638;
    }
    highp vec3 _7129 = ((((_7066 + (_7070 * ((vec3(1.0) - _7042) - _7066))) * (_13593 * frag_info.environment_intensity)) * _13633) + (((_7042 * (_13594 * frag_info.environment_intensity)) * 1.0) * _13637)) * mix(1.0, _6567, frag_info.radiance_blend.y);
    highp vec3 _13692 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _13692 = _7129 + ((_13549.xyz * _7070) * _5566);
    }
    else
    {
        _13692 = _7129;
    }
    highp vec3 _13696 = vec3(0.0);
    if (_6517)
    {
        highp vec3 _13670 = vec3(0.0);
        highp vec3 _13671 = vec3(0.0);
        do
        {
            float _12237 = max(dot(_13476, _13663), 0.0);
            highp float hp_copy_12237 = _12237;
            if (_12237 <= 0.0)
            {
                _13671 = vec3(0.0);
                _13670 = vec3(0.0);
                break;
            }
            float _12243 = max(_6580, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_12243 = _12243;
            vec3 _12246 = _13663 + mp_copy_13554;
            float _12249 = dot(_12246, _12246);
            vec3 _13668 = vec3(0.0);
            vec3 _13669 = vec3(0.0);
            if (_12249 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _12257 = _12246 * inversesqrt(_12249);
                float _13667 = 0.0;
                do
                {
                    float _12314 = dot(_13476, _12257);
                    if (_12314 <= 0.0)
                    {
                        _13667 = 0.0;
                        break;
                    }
                    float _12321 = _13524 * _13524;
                    vec3 _12324 = cross(_13476, _12257);
                    float _12327 = _12314 * _12321;
                    float _12336 = _12321 / (dot(_12324, _12324) + (_12327 * _12327));
                    _13667 = min((_12336 * _12336) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _12374 = _6576 + (_7052 * pow(clamp(1.0 - max(dot(_12257, _13554), 0.0), 0.0, 1.0), 5.0));
                _13669 = (_12374 * min(_13667 * (0.5 / max(mix((2.0 * hp_copy_12237) * _12243, hp_copy_12237 + hp_copy_12243, hp_copy_13524 * hp_copy_13524), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _13668 = _12374;
            }
            else
            {
                _13669 = vec3(0.0);
                _13668 = _6576;
            }
            _13671 = (_13669 * frag_info.directional_light_color.xyz) * _12237;
            _13670 = (((((vec3(1.0) - _13668) * _7069) * _6428) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _12237;
            break;
        } while(false);
        _13696 = _13678 + ((_13670 + _13671) * _6567);
    }
    else
    {
        _13696 = _13678;
    }
    bool _7191 = _FogInfo.params0.y > 0.5;
    bool _7197 = false;
    if (_7191)
    {
        _7197 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7197 = _7191;
    }
    highp vec3 _13701 = vec3(0.0);
    if (_7197)
    {
        vec3 mp_copy_13697 = vec3(0.0);
        highp vec3 _13697 = vec3(0.0);
        if (_9198)
        {
            _13697 = -view_info.camera_forward.xyz;
        }
        else
        {
            _13697 = normalize(v_viewvector);
        }
        mp_copy_13697 = _13697;
        vec3 _7202 = _6975 * (-mp_copy_13697);
        vec3 _13698 = vec3(0.0);
        do
        {
            if (_11697)
            {
                vec2 _12496 = vec2(atan(_7202.z, _7202.x), asin(clamp(_7202.y, -1.0, 1.0)));
                highp vec2 hp_copy_12496 = _12496;
                _13698 = textureLod(prefiltered_radiance, (hp_copy_12496 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _12515 = vec2(atan(_7202.z, _7202.x), asin(clamp(_7202.y, -1.0, 1.0)));
            highp vec2 hp_copy_12515 = _12515;
            highp vec2 _12520 = (hp_copy_12515 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12427 = clamp(_12520.y, 0.00390625, 0.99609375);
            float _12433 = floor(0.0);
            highp float _12452 = _12520.x;
            _13698 = mix(textureLod(prefiltered_radiance, vec2(_12452, (_12433 + _12427) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_12452, (min(_12433 + 1.0, 7.0) + _12427) * 0.125), 0.0).xyz, vec3(-_12433));
            break;
        } while(false);
        highp vec3 _13700 = vec3(0.0);
        if (_6998)
        {
            vec3 _13699 = vec3(0.0);
            do
            {
                if (_11697)
                {
                    vec2 _12625 = vec2(atan(_7202.z, _7202.x), asin(clamp(_7202.y, -1.0, 1.0)));
                    highp vec2 hp_copy_12625 = _12625;
                    _13699 = textureLod(prefiltered_radiance_b, (hp_copy_12625 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _12644 = vec2(atan(_7202.z, _7202.x), asin(clamp(_7202.y, -1.0, 1.0)));
                highp vec2 hp_copy_12644 = _12644;
                highp vec2 _12649 = (hp_copy_12644 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _12556 = clamp(_12649.y, 0.00390625, 0.99609375);
                float _12562 = floor(0.0);
                highp float _12581 = _12649.x;
                _13699 = mix(textureLod(prefiltered_radiance_b, vec2(_12581, (_12562 + _12556) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12581, (min(_12562 + 1.0, 7.0) + _12556) * 0.125), 0.0).xyz, vec3(-_12562));
                break;
            } while(false);
            _13700 = mix(_13698, _13699, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _13700 = _13698;
        }
        _13701 = _13700 * frag_info.environment_intensity;
    }
    else
    {
        _13701 = _FogInfo.color.xyz;
    }
    highp vec4 _7226 = vec4(min((_13692 + (_13696 * mix(1.0, _13612, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _13499, vec3(65504.0)), 1.0) * _14501;
    highp vec4 _13716 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _13716 = _7226;
            break;
        }
        int _12693 = int(_FogInfo.params0.x + 0.5);
        if (_12693 == 0)
        {
            _13716 = _7226;
            break;
        }
        highp float _13703 = 0.0;
        if (_9198)
        {
            _13703 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _13703 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_13703 > _FogInfo.params1.w))
        {
            _13716 = _7226;
            break;
        }
        float _13707 = 0.0;
        if (_12693 == 1)
        {
            _13707 = clamp((_13703 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _13708 = 0.0;
            if (_12693 == 2)
            {
                highp float _13706 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _13704 = vec3(0.0);
                    if (_9198)
                    {
                        _13704 = v_position - (view_info.camera_forward.xyz * _13703);
                    }
                    else
                    {
                        _13704 = v_position + v_viewvector;
                    }
                    highp float _12774 = -_FogInfo.params2.y;
                    highp float _12781 = _FogInfo.params1.x * exp(_12774 * (_13704.y - _FogInfo.params2.x));
                    highp float _12798 = _FogInfo.params2.y * (v_position.y - _13704.y);
                    highp float _13705 = 0.0;
                    if (abs(_12798) > 0.00124999997206032276153564453125)
                    {
                        _13705 = (_12781 - (_FogInfo.params1.x * exp(_12774 * (v_position.y - _FogInfo.params2.x)))) / _12798;
                    }
                    else
                    {
                        _13705 = _12781;
                    }
                    _13706 = _13705 * max(_13703 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _13706 = _FogInfo.params1.x * max(_13703 - _FogInfo.params1.y, 0.0);
                }
                _13708 = 1.0 - exp(-_13706);
            }
            else
            {
                highp float _12836 = _FogInfo.params1.x * max(_13703 - _FogInfo.params1.y, 0.0);
                _13708 = 1.0 - exp((-_12836) * _12836);
            }
            _13707 = _13708;
        }
        highp float _12848 = min(_13707, _FogInfo.params0.z);
        if (_12848 <= 0.0)
        {
            _13716 = _7226;
            break;
        }
        highp vec3 _12861 = mix(_FogInfo.color.xyz, _13701, vec3(_FogInfo.params0.w));
        bool _12864 = _FogInfo.sun.w > 0.5;
        bool _12870 = false;
        if (_12864)
        {
            _12870 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _12870 = _12864;
        }
        vec3 _13712 = vec3(0.0);
        if (_12870)
        {
            vec3 mp_copy_13709 = vec3(0.0);
            highp vec3 _13709 = vec3(0.0);
            if (_9198)
            {
                _13709 = -view_info.camera_forward.xyz;
            }
            else
            {
                _13709 = normalize(v_viewvector);
            }
            mp_copy_13709 = _13709;
            highp float _12886 = pow(max(dot(-mp_copy_13709, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_12886 = _12886;
            _13712 = _12861 + ((_FogInfo.sun.xyz * mp_copy_12886) * _FogInfo.params2.z);
        }
        else
        {
            _13712 = _12861;
        }
        highp float _12899 = _7226.w;
        float mp_copy_12899 = _12899;
        _13716 = vec4(mix(_7226.xyz, _13712 * mp_copy_12899, vec3(_12848)), _12899);
        break;
    } while(false);
    vec4 _13718 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _13718 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _13718 = _13716;
        break;
    } while(false);
    frag_color = _13718;
    float _13719 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _13719 = 1.0;
    }
    else
    {
        _13719 = abs(frag_info.fade);
    }
    frag_color *= _13719;
}

