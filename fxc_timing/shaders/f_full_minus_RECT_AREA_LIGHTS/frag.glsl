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
    highp float _5619 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_5619 = _5619;
    vec3 _5623 = normalize(v_normal) * mp_copy_5619;
    vec4 _5665 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _5668 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _16870 = vec2(0.0);
    if (_5668)
    {
        highp vec2 _16869 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _16869 = v_texture_coords_1;
        }
        else
        {
            _16869 = v_texture_coords;
        }
        highp vec2 _5868 = _16869 * texture_transforms.base_color_transform.zw;
        highp float _5874 = _5868.x;
        highp float _5879 = _5868.y;
        _16870 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _5874) + (texture_transforms.base_color_rotation.y * _5879), ((-texture_transforms.base_color_rotation.y) * _5874) + (texture_transforms.base_color_rotation.x * _5879));
    }
    else
    {
        _16870 = v_texture_coords;
    }
    vec4 _5682 = texture(base_color_texture, _16870);
    vec3 _5684 = _5682.xyz;
    float _18429 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_5682.w * _5665.w) * frag_info.color.w);
    vec3 _16885 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _16873 = vec2(0.0);
        if (_5668)
        {
            highp vec2 _16872 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _16872 = v_texture_coords_1;
            }
            else
            {
                _16872 = v_texture_coords;
            }
            highp vec2 _5963 = _16872 * texture_transforms.normal_transform.zw;
            highp float _5969 = _5963.x;
            highp float _5974 = _5963.y;
            _16873 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _5969) + (texture_transforms.normal_rotation.y * _5974), ((-texture_transforms.normal_rotation.y) * _5969) + (texture_transforms.normal_rotation.x * _5974));
        }
        else
        {
            _16873 = v_texture_coords;
        }
        vec3 _6022 = ((texture(normal_texture, _16873).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6026 = _6022.xy * vec2(frag_info.normal_scale);
        vec3 _16320 = _6022;
        _16320.x = _6026.x;
        _16320.y = _6026.y;
        highp vec3 _6032 = -v_viewvector;
        highp vec3 _6122 = dFdx(_6032);
        highp vec3 _6124 = dFdy(_6032);
        highp vec2 _6126 = dFdx(_16873);
        highp vec2 _6128 = dFdy(_16873);
        bvec2 _18431 = bvec2(length(_6126) == 0.0);
        highp vec2 _18432 = vec2(_18431.x ? vec2(1.0, 0.0).x : _6126.x, _18431.y ? vec2(1.0, 0.0).y : _6126.y);
        bvec2 _18433 = bvec2(length(_6128) == 0.0);
        highp vec2 _18434 = vec2(_18433.x ? vec2(0.0, 1.0).x : _6128.x, _18433.y ? vec2(0.0, 1.0).y : _6128.y);
        highp vec3 _6141 = cross(_6124, _5623);
        highp vec3 _6144 = cross(_5623, _6122);
        highp float _6169 = (dot(cross(_6122, _6124), _5623) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6172 = ((_6141 * _18432.x) + (_6144 * _18434.x)) * _6169;
        highp float _16880 = 0.0;
        if (gl_FrontFacing)
        {
            _16880 = -_6169;
        }
        else
        {
            _16880 = _6169;
        }
        highp vec3 _6182 = ((_6141 * _18432.y) + (_6144 * _18434.y)) * _16880;
        highp float _6191 = inversesqrt(max(max(dot(_6172, _6172), dot(_6182, _6182)), 9.9999996826552253889678874634872e-21));
        vec3 _6063 = v_tangent.xyz - (_5623 * dot(_5623, v_tangent.xyz));
        highp float _6066 = dot(_6063, _6063);
        bool _6068 = _6066 > 1.0000000133514319600180897396058e-10;
        bool _6075 = false;
        if (_6068)
        {
            _6075 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6075 = _6068;
        }
        mat3 _16883 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6075)
        {
            highp vec3 _6080 = _6063 * inversesqrt(_6066);
            _16883 = mat3(_6080, normalize(cross(_5623, _6080)) * sign(v_tangent.w), _5623);
        }
        else
        {
            _16883 = mat3(_6172 * _6191, _6182 * _6191, _5623);
        }
        _16885 = normalize(_16883 * _16320);
    }
    else
    {
        _16885 = _5623;
    }
    highp vec2 _16887 = vec2(0.0);
    if (_5668)
    {
        highp vec2 _16886 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _16886 = v_texture_coords_1;
        }
        else
        {
            _16886 = v_texture_coords;
        }
        highp vec2 _6256 = _16886 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6262 = _6256.x;
        highp float _6267 = _6256.y;
        _16887 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6262) + (texture_transforms.metallic_roughness_rotation.y * _6267), ((-texture_transforms.metallic_roughness_rotation.y) * _6262) + (texture_transforms.metallic_roughness_rotation.x * _6267));
    }
    else
    {
        _16887 = v_texture_coords;
    }
    vec4 _5751 = texture(metallic_roughness_texture, _16887);
    float _5757 = clamp(_5751.z * frag_info.metallic_factor, 0.0, 1.0);
    float _5764 = clamp(_5751.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _16889 = vec2(0.0);
    if (_5668)
    {
        highp vec2 _16888 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _16888 = v_texture_coords_1;
        }
        else
        {
            _16888 = v_texture_coords;
        }
        highp vec2 _6327 = _16888 * texture_transforms.occlusion_transform.zw;
        highp float _6333 = _6327.x;
        highp float _6338 = _6327.y;
        _16889 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6333) + (texture_transforms.occlusion_rotation.y * _6338), ((-texture_transforms.occlusion_rotation.y) * _6333) + (texture_transforms.occlusion_rotation.x * _6338));
    }
    else
    {
        _16889 = v_texture_coords;
    }
    float _16890 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _16890 = texture(occlusion_texture, _16889).x;
    }
    else
    {
        _16890 = 1.0;
    }
    float _5791 = 1.0 - ((1.0 - _16890) * frag_info.occlusion_strength);
    highp vec2 _16892 = vec2(0.0);
    if (_5668)
    {
        highp vec2 _16891 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _16891 = v_texture_coords_1;
        }
        else
        {
            _16891 = v_texture_coords;
        }
        highp vec2 _6398 = _16891 * texture_transforms.emissive_transform.zw;
        highp float _6404 = _6398.x;
        highp float _6409 = _6398.y;
        _16892 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6404) + (texture_transforms.emissive_rotation.y * _6409), ((-texture_transforms.emissive_rotation.y) * _6404) + (texture_transforms.emissive_rotation.x * _6409));
    }
    else
    {
        _16892 = v_texture_coords;
    }
    vec3 _5810 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _16908 = vec3(0.0);
    if (dot(abs(_5810), vec3(1.0)) > 0.0)
    {
        vec3 _5819 = texture(emissive_texture, _16892).xyz;
        _16908 = mix(_5819 * vec3(0.077399380505084991455078125), pow((_5819 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5819)) * _5810;
    }
    else
    {
        _16908 = vec3(0.0);
    }
    highp float hp_copy_16933 = 0.0;
    vec3 _6615 = vec4((mix(_5684 * vec3(0.077399380505084991455078125), pow((_5684 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _5684)) * _5665.xyz) * frag_info.color.xyz, _18429).xyz;
    vec3 _7275 = dFdx(_16885);
    vec3 _7277 = dFdy(_16885);
    float _16933 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _16933 = sqrt(clamp((_5764 * _5764) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7275, _7275), dot(_7277, _7277))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _16933 = _5764;
    }
    hp_copy_16933 = _16933;
    vec4 _16958 = vec4(0.0);
    float _16976 = 0.0;
    vec3 _16991 = vec3(0.0);
    float _17274 = 0.0;
    vec3 _17413 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _6642 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _16934 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _16934 = _6642.w;
        }
        else
        {
            _16934 = _6642.x;
        }
        float _6655 = min(_5791, _16934);
        bool _6658 = frag_info.ssao_lighting.z > 0.5;
        bool _6664 = false;
        if (_6658)
        {
            _6664 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _6664 = _6658;
        }
        vec3 _16992 = vec3(0.0);
        if (_6664)
        {
            vec2 _7315 = (_6642.zw * 2.0) - vec2(1.0);
            float _7317 = _7315.x;
            float _7319 = _7315.y;
            float _7327 = (1.0 - abs(_7317)) - abs(_7319);
            vec3 _7328 = vec3(_7317, _7319, _7327);
            vec3 _16937 = vec3(0.0);
            if (_7327 < 0.0)
            {
                vec2 _7341 = (vec2(1.0) - abs(_7328.yx)) * vec2((_7317 >= 0.0) ? 1.0 : (-1.0), (_7319 >= 0.0) ? 1.0 : (-1.0));
                vec3 _16369 = _7328;
                _16369.x = _7341.x;
                _16369.y = _7341.y;
                _16937 = _16369;
            }
            else
            {
                _16937 = _7328;
            }
            vec3 _7349 = -normalize(_16937);
            _16992 = normalize(((frag_info.camera_right.xyz * _7349.x) + (frag_info.camera_up.xyz * _7349.y)) + (frag_info.camera_forward.xyz * _7349.z));
        }
        else
        {
            _16992 = vec3(0.0);
        }
        vec3 _6692 = vec3(_6655);
        _17413 = mix(_6692, max(_6692, ((((((_6615 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _6655) + ((_6615 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _6655) + ((_6615 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _6655), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _17274 = _6655;
        _16991 = _16992;
        _16976 = float(_6664);
        _16958 = _6642;
    }
    else
    {
        _17413 = vec3(_5791);
        _17274 = _5791;
        _16991 = vec3(0.0);
        _16976 = 0.0;
        _16958 = vec4(1.0);
    }
    bool _6704 = frag_info.has_directional_light > 0.5;
    float _16941 = 0.0;
    vec3 _17561 = vec3(0.0);
    if (_6704)
    {
        highp vec3 _6710 = -normalize(frag_info.directional_light_direction.xyz);
        _17561 = _6710;
        _16941 = dot(_5623, _6710);
    }
    else
    {
        _17561 = vec3(0.0);
        _16941 = 0.0;
    }
    float _6717 = clamp(_16941 * 6.666666507720947265625, 0.0, 1.0);
    bool _6726 = false;
    if (_6704)
    {
        _6726 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _6726 = _6704;
    }
    float _16950 = 0.0;
    if (_6726 && (_6717 > 0.0))
    {
        int _7440 = int(frag_info.shadow_cascade_count);
        float _7635 = max(dot(_5623, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _7638 = _7635 * _7635;
        highp vec3 _7658 = v_position + (_5623 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _7638, 0.0)) / _7638, 8.0))));
        highp float _7446 = frag_info.directional_light_color.w * 0.5;
        float _7448 = frag_info.dielectric_f0.w;
        highp float hp_copy_7448 = _7448;
        float _16942 = 0.0;
        if (_7448 > 0.0)
        {
            _16942 = smoothstep(_7448 - max(frag_info.shadow_fade, hp_copy_7448 * 0.100000001490116119384765625), _7448, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _16942 = 0.0;
        }
        float _16944 = 0.0;
        float _16946 = 0.0;
        if (_16942 < 1.0)
        {
            float _16945 = 0.0;
            float _16947 = 0.0;
            _16947 = 0.0;
            _16945 = 0.0;
            float _18009 = 0.0;
            float _18012 = 0.0;
            for (int _16943 = 0; _16943 < _7440; _16947 = _18012, _16945 = _18009, _16943++)
            {
                if (_16947 < 1.0)
                {
                    highp vec4 _7480 = vec4(_7658, 1.0);
                    highp vec4 _17881 = vec4(0.0);
                    highp float _17884 = 0.0;
                    if (_16943 == 0)
                    {
                        _17884 = frag_info.cascade_box_sizes.x;
                        _17881 = frag_info.light_space_matrix[0] * _7480;
                    }
                    else
                    {
                        highp vec4 _17882 = vec4(0.0);
                        highp float _17885 = 0.0;
                        if (_16943 == 1)
                        {
                            _17885 = frag_info.cascade_box_sizes.y;
                            _17882 = frag_info.light_space_matrix[1] * _7480;
                        }
                        else
                        {
                            highp vec4 _17883 = vec4(0.0);
                            highp float _17886 = 0.0;
                            if (_16943 == 2)
                            {
                                _17886 = frag_info.cascade_box_sizes.z;
                                _17883 = frag_info.light_space_matrix[2] * _7480;
                            }
                            else
                            {
                                _17886 = frag_info.cascade_box_sizes.w;
                                _17883 = frag_info.light_space_matrix[3] * _7480;
                            }
                            _17885 = _17886;
                            _17882 = _17883;
                        }
                        _17884 = _17885;
                        _17881 = _17882;
                    }
                    highp vec3 _7525 = _17881.xyz / vec3(_17881.w);
                    highp vec2 _7528 = _7525.xy * 0.5;
                    highp vec2 _7530 = _7528 + vec2(0.5);
                    highp float _7537 = max(frag_info.shadow_softness / _17884, frag_info.shadow_texel_size);
                    highp float _7539 = _7530.x;
                    bool _7541 = _7539 < _7537;
                    bool _7550 = false;
                    if (!_7541)
                    {
                        _7550 = _7539 > (1.0 - _7537);
                    }
                    else
                    {
                        _7550 = _7541;
                    }
                    bool _7558 = false;
                    if (!_7550)
                    {
                        _7558 = _7530.y < _7537;
                    }
                    else
                    {
                        _7558 = _7550;
                    }
                    bool _7567 = false;
                    if (!_7558)
                    {
                        _7567 = _7530.y > (1.0 - _7537);
                    }
                    else
                    {
                        _7567 = _7558;
                    }
                    bool _7574 = false;
                    if (!_7567)
                    {
                        _7574 = _7525.z < 0.0;
                    }
                    else
                    {
                        _7574 = _7567;
                    }
                    bool _7581 = false;
                    if (!_7574)
                    {
                        _7581 = _7525.z > 1.0;
                    }
                    else
                    {
                        _7581 = _7574;
                    }
                    float _18010 = 0.0;
                    float _18013 = 0.0;
                    if (!_7581)
                    {
                        highp vec2 _7674 = vec2(_7537);
                        highp vec2 _7679 = vec2(_7537 + max(_7446, 9.9999997473787516355514526367188e-05));
                        highp vec2 _7687 = vec2(0.5) - _7528;
                        highp vec2 _7689 = smoothstep(_7674, _7679, _7530) * smoothstep(_7674, _7679, _7687);
                        float _17887 = 0.0;
                        if (_7446 > 0.0)
                        {
                            _17887 = _7689.x * _7689.y;
                        }
                        else
                        {
                            _17887 = 1.0;
                        }
                        float _7590 = min(_17887, 1.0 - _16947);
                        float _18011 = 0.0;
                        float _18014 = 0.0;
                        if (_7590 > 0.0)
                        {
                            highp float _7828 = _7525.z - (frag_info.shadow_bias / (7.0 * _17884));
                            highp float _7834 = 1.0 / (float(_7440) + frag_info.spot_shadow_params.x);
                            highp float _7836 = frag_info.directional_light_direction.w;
                            float mp_copy_7836 = _7836;
                            float _7842 = step(0.5, mp_copy_7836) * (1.0 - step(1.5, mp_copy_7836));
                            float _17917 = 0.0;
                            float _17921 = 0.0;
                            if (_7842 < 0.5)
                            {
                                highp float _7853 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_7853 = _7853;
                                _17921 = sin(mp_copy_7853);
                                _17917 = cos(mp_copy_7853);
                            }
                            else
                            {
                                _17921 = 0.0;
                                _17917 = 1.0;
                            }
                            highp float _17924 = 0.0;
                            if ((_7836 > 1.5) && (_7836 < 2.5))
                            {
                                highp float _7877 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _7882 = max(_7877 * _7828, frag_info.shadow_texel_size);
                                float _17913 = 0.0;
                                highp float _17914 = 0.0;
                                _17914 = 0.0;
                                _17913 = 0.0;
                                highp float _7904 = 0.0;
                                float _7907 = 0.0;
                                for (int _17912 = 0; _17912 < 9; _17914 = _7904, _17913 = _7907, _17912++)
                                {
                                    vec2 _18003 = vec2(0.0);
                                    do
                                    {
                                        if (_17912 == 0)
                                        {
                                            _18003 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_17912 == 1)
                                        {
                                            _18003 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_17912 == 2)
                                        {
                                            _18003 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_17912 == 3)
                                        {
                                            _18003 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_17912 == 4)
                                        {
                                            _18003 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_17912 == 5)
                                        {
                                            _18003 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_17912 == 6)
                                        {
                                            _18003 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_17912 == 7)
                                        {
                                            _18003 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_17912 == 8)
                                        {
                                            _18003 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_17912 == 9)
                                        {
                                            _18003 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_17912 == 10)
                                        {
                                            _18003 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_17912 == 11)
                                        {
                                            _18003 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_17912 == 12)
                                        {
                                            _18003 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_17912 == 13)
                                        {
                                            _18003 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_17912 == 14)
                                        {
                                            _18003 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_17912 == 15)
                                        {
                                            _18003 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _18003 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8211 = clamp(_7530 + (vec2((_18003.x * _17917) - (_18003.y * _17921), (_18003.x * _17921) + (_18003.y * _17917)) * _7882), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8220 = _8211.y;
                                    highp vec2 _8221 = vec2((float(_16943) + _8211.x) * _7834, _8220);
                                    _8221.y = 1.0 - _8220;
                                    highp vec4 _8228 = textureLod(shadow_map, _8221, 0.0);
                                    highp float _8229 = _8228.x;
                                    highp float _7899 = step(_8229, _7828);
                                    float mp_copy_7899 = _7899;
                                    _7904 = _17914 + (_8229 * _7899);
                                    _7907 = _17913 + mp_copy_7899;
                                }
                                highp float _17915 = 0.0;
                                if (_17913 > 0.0)
                                {
                                    _17915 = _17914 / _17913;
                                }
                                else
                                {
                                    _17915 = _7828;
                                }
                                _17924 = clamp(_7877 * max(_7828 - _17915, 0.0), frag_info.shadow_texel_size, _7537);
                            }
                            else
                            {
                                _17924 = _7537;
                            }
                            bool _7938 = _7836 > 2.5;
                            bool _17925 = false;
                            float _17949 = 0.0;
                            if ((_7836 < 1.5) || _7938)
                            {
                                highp vec2 _8262 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8266 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8267 = clamp(_7530, _8262, _8266);
                                highp float _8269 = float(_16943);
                                highp float _8276 = _8267.y;
                                highp vec2 _8277 = vec2((_8269 + _8267.x) * _7834, _8276);
                                _8277.y = 1.0 - _8276;
                                highp float _8289 = float(_7828 <= textureLod(shadow_map, _8277, 0.0).x);
                                float mp_copy_8289 = _8289;
                                float _8299 = (-1.0) * _17917;
                                float _8303 = (-1.0) * _17921;
                                highp vec2 _8327 = clamp(_7530 + (vec2(_8299 - _8303, _8303 + _8299) * _17924), _8262, _8266);
                                highp float _8336 = _8327.y;
                                highp vec2 _8337 = vec2((_8269 + _8327.x) * _7834, _8336);
                                _8337.y = 1.0 - _8336;
                                highp float _8349 = float(_7828 <= textureLod(shadow_map, _8337, 0.0).x);
                                float mp_copy_8349 = _8349;
                                highp vec2 _8387 = clamp(_7530 + (vec2(_17917 - _8303, _17921 + _8299) * _17924), _8262, _8266);
                                highp float _8396 = _8387.y;
                                highp vec2 _8397 = vec2((_8269 + _8387.x) * _7834, _8396);
                                _8397.y = 1.0 - _8396;
                                highp float _8409 = float(_7828 <= textureLod(shadow_map, _8397, 0.0).x);
                                float mp_copy_8409 = _8409;
                                highp vec2 _8447 = clamp(_7530 + (vec2(_8299 - _17921, _8303 + _17917) * _17924), _8262, _8266);
                                highp float _8456 = _8447.y;
                                highp vec2 _8457 = vec2((_8269 + _8447.x) * _7834, _8456);
                                _8457.y = 1.0 - _8456;
                                highp float _8469 = float(_7828 <= textureLod(shadow_map, _8457, 0.0).x);
                                float mp_copy_8469 = _8469;
                                highp vec2 _8507 = clamp(_7530 + (vec2(_17917 - _17921, _17921 + _17917) * _17924), _8262, _8266);
                                highp float _8516 = _8507.y;
                                highp vec2 _8517 = vec2((_8269 + _8507.x) * _7834, _8516);
                                _8517.y = 1.0 - _8516;
                                highp float _8529 = float(_7828 <= textureLod(shadow_map, _8517, 0.0).x);
                                float mp_copy_8529 = _8529;
                                float _7984 = (((mp_copy_8289 + mp_copy_8349) + mp_copy_8409) + mp_copy_8469) + mp_copy_8529;
                                _17949 = _7984 * 0.20000000298023223876953125;
                                _17925 = (_7984 < 0.5) || (_7984 > 4.5);
                            }
                            else
                            {
                                _17949 = 0.0;
                                _17925 = false;
                            }
                            float _17948 = 0.0;
                            if (_17925)
                            {
                                _17948 = _17949;
                            }
                            else
                            {
                                float _17950 = 0.0;
                                if (_7938)
                                {
                                    highp vec2 _8557 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _8561 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _8562 = clamp(_7530 + (vec2(-0.707099974155426025390625) * _17924), _8557, _8561);
                                    highp vec2 _8573 = (vec2(_8562.x, 1.0 - _8562.y) / _8557) - vec2(0.5);
                                    highp vec2 _8575 = floor(_8573);
                                    highp vec2 _8578 = _8573 - _8575;
                                    highp vec2 _8583 = (_8575 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _8585 = float(_16943);
                                    highp vec2 _8593 = vec2((_8585 + _8583.x) * _7834, _8583.y);
                                    highp float _8597 = frag_info.shadow_texel_size * _7834;
                                    highp vec2 _8600 = vec2(_8597, frag_info.shadow_texel_size);
                                    highp vec2 _8609 = vec2(_8597, 0.0);
                                    highp vec2 _8617 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _8646 = _8578.x;
                                    highp float _8655 = mix(mix(float(_7828 <= textureLod(shadow_map, _8593, 0.0).x), float(_7828 <= textureLod(shadow_map, _8593 + _8609, 0.0).x), _8646), mix(float(_7828 <= textureLod(shadow_map, _8593 + _8617, 0.0).x), float(_7828 <= textureLod(shadow_map, _8593 + _8600, 0.0).x), _8646), _8578.y);
                                    float mp_copy_8655 = _8655;
                                    highp vec2 _8689 = clamp(_7530 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _17924), _8557, _8561);
                                    highp vec2 _8700 = (vec2(_8689.x, 1.0 - _8689.y) / _8557) - vec2(0.5);
                                    highp vec2 _8702 = floor(_8700);
                                    highp vec2 _8705 = _8700 - _8702;
                                    highp vec2 _8710 = (_8702 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8720 = vec2((_8585 + _8710.x) * _7834, _8710.y);
                                    highp float _8773 = _8705.x;
                                    highp float _8782 = mix(mix(float(_7828 <= textureLod(shadow_map, _8720, 0.0).x), float(_7828 <= textureLod(shadow_map, _8720 + _8609, 0.0).x), _8773), mix(float(_7828 <= textureLod(shadow_map, _8720 + _8617, 0.0).x), float(_7828 <= textureLod(shadow_map, _8720 + _8600, 0.0).x), _8773), _8705.y);
                                    float mp_copy_8782 = _8782;
                                    highp vec2 _8816 = clamp(_7530 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _17924), _8557, _8561);
                                    highp vec2 _8827 = (vec2(_8816.x, 1.0 - _8816.y) / _8557) - vec2(0.5);
                                    highp vec2 _8829 = floor(_8827);
                                    highp vec2 _8832 = _8827 - _8829;
                                    highp vec2 _8837 = (_8829 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8847 = vec2((_8585 + _8837.x) * _7834, _8837.y);
                                    highp float _8900 = _8832.x;
                                    highp float _8909 = mix(mix(float(_7828 <= textureLod(shadow_map, _8847, 0.0).x), float(_7828 <= textureLod(shadow_map, _8847 + _8609, 0.0).x), _8900), mix(float(_7828 <= textureLod(shadow_map, _8847 + _8617, 0.0).x), float(_7828 <= textureLod(shadow_map, _8847 + _8600, 0.0).x), _8900), _8832.y);
                                    float mp_copy_8909 = _8909;
                                    highp vec2 _8943 = clamp(_7530 + (vec2(0.707099974155426025390625) * _17924), _8557, _8561);
                                    highp vec2 _8954 = (vec2(_8943.x, 1.0 - _8943.y) / _8557) - vec2(0.5);
                                    highp vec2 _8956 = floor(_8954);
                                    highp vec2 _8959 = _8954 - _8956;
                                    highp vec2 _8964 = (_8956 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _8974 = vec2((_8585 + _8964.x) * _7834, _8964.y);
                                    highp float _9027 = _8959.x;
                                    highp float _9036 = mix(mix(float(_7828 <= textureLod(shadow_map, _8974, 0.0).x), float(_7828 <= textureLod(shadow_map, _8974 + _8609, 0.0).x), _9027), mix(float(_7828 <= textureLod(shadow_map, _8974 + _8617, 0.0).x), float(_7828 <= textureLod(shadow_map, _8974 + _8600, 0.0).x), _9027), _8959.y);
                                    float mp_copy_9036 = _9036;
                                    _17950 = (((mp_copy_8655 + mp_copy_8782) + mp_copy_8909) + mp_copy_9036) * 0.25;
                                }
                                else
                                {
                                    int _8031 = (_7842 > 0.5) ? 17 : 16;
                                    float _17944 = 0.0;
                                    _17944 = 0.0;
                                    float _8059 = 0.0;
                                    for (int _17926 = 0; _17926 < 17; _17944 = _8059, _17926++)
                                    {
                                        if (_17926 >= _8031)
                                        {
                                            break;
                                        }
                                        vec2 _17927 = vec2(0.0);
                                        do
                                        {
                                            if (_17926 == 0)
                                            {
                                                _17927 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_17926 == 1)
                                            {
                                                _17927 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_17926 == 2)
                                            {
                                                _17927 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_17926 == 3)
                                            {
                                                _17927 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_17926 == 4)
                                            {
                                                _17927 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_17926 == 5)
                                            {
                                                _17927 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_17926 == 6)
                                            {
                                                _17927 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_17926 == 7)
                                            {
                                                _17927 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_17926 == 8)
                                            {
                                                _17927 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_17926 == 9)
                                            {
                                                _17927 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_17926 == 10)
                                            {
                                                _17927 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_17926 == 11)
                                            {
                                                _17927 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_17926 == 12)
                                            {
                                                _17927 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_17926 == 13)
                                            {
                                                _17927 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_17926 == 14)
                                            {
                                                _17927 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_17926 == 15)
                                            {
                                                _17927 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _17927 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _17929 = vec2(0.0);
                                        do
                                        {
                                            if (_17926 < 3)
                                            {
                                                _17929 = vec2(float(_17926) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_17926 < 6)
                                            {
                                                _17929 = vec2((float(_17926 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_17926 < 11)
                                            {
                                                _17929 = vec2((float(_17926 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_17926 < 14)
                                            {
                                                _17929 = vec2((float(_17926 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _17929 = vec2(float(_17926 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8048 = mix(_17927, _17929, vec2(_7842));
                                        float _9176 = _8048.x;
                                        float _9180 = _8048.y;
                                        highp vec2 _9206 = clamp(_7530 + (vec2((_9176 * _17917) - (_9180 * _17921), (_9176 * _17921) + (_9180 * _17917)) * _17924), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9215 = _9206.y;
                                        highp vec2 _9216 = vec2((float(_16943) + _9206.x) * _7834, _9215);
                                        _9216.y = 1.0 - _9215;
                                        highp float _9228 = float(_7828 <= textureLod(shadow_map, _9216, 0.0).x);
                                        float mp_copy_9228 = _9228;
                                        _8059 = _17944 + mp_copy_9228;
                                    }
                                    _17950 = _17944 / float(_8031);
                                }
                                _17948 = _17950;
                            }
                            bool _8073 = _16943 == (_7440 - 1);
                            bool _8079 = false;
                            if (_8073)
                            {
                                _8079 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8079 = _8073;
                            }
                            float _17951 = 0.0;
                            if (_8079)
                            {
                                highp vec2 _8086 = vec2(frag_info.shadow_fade / _17884);
                                highp vec2 _8094 = smoothstep(vec2(0.0), _8086, _7530) * smoothstep(vec2(0.0), _8086, _7687);
                                _17951 = mix(1.0, _17948, _8094.x * _8094.y);
                            }
                            else
                            {
                                _17951 = _17948;
                            }
                            _18014 = _16947 + _7590;
                            _18011 = _16945 + (_7590 * _17951);
                        }
                        else
                        {
                            _18014 = _16947;
                            _18011 = _16945;
                        }
                        _18013 = _18014;
                        _18010 = _18011;
                    }
                    else
                    {
                        _18013 = _16947;
                        _18010 = _16945;
                    }
                    _18012 = _18013;
                    _18009 = _18010;
                }
                else
                {
                    _18012 = _16947;
                    _18009 = _16945;
                }
            }
            _16946 = _16947;
            _16944 = _16945;
        }
        else
        {
            _16946 = 0.0;
            _16944 = 0.0;
        }
        _16950 = mix(_16944 + (1.0 - _16946), 1.0, _16942);
    }
    else
    {
        _16950 = 1.0;
    }
    bool _6739 = frag_info.ssao_lighting.w > 0.5;
    bool _6745 = false;
    if (_6739)
    {
        _6745 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _6745 = _6739;
    }
    float _16962 = 0.0;
    if (_6745)
    {
        _16962 = min(_16950, _16958.y);
    }
    else
    {
        _16962 = _16950;
    }
    vec3 mp_copy_16963 = vec3(0.0);
    float _6754 = _6717 * _16962;
    bool _9235 = view_info.camera_forward.w > 0.5;
    highp vec3 _16963 = vec3(0.0);
    if (_9235)
    {
        _16963 = -view_info.camera_forward.xyz;
    }
    else
    {
        _16963 = normalize(v_viewvector);
    }
    highp float _9279 = 0.0;
    mp_copy_16963 = _16963;
    vec3 _6763 = mix(frag_info.dielectric_f0.xyz, _6615, vec3(_5757));
    float _6767 = max(dot(_16885, _16963), 0.0);
    float _6771 = max(dot(_5623, _16963), 0.0);
    vec3 _6775 = reflect(-mp_copy_16963, _16885);
    highp vec2 _16964 = vec2(0.0);
    do
    {
        _9279 = frag_info.punctual_dims.x;
        if (_9279 < 0.5)
        {
            _16964 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9291 = v_position - frag_info.camera_position.xyz;
            highp float _9306 = dot(_9291, frag_info.camera_forward.xyz);
            highp float _9312 = max(_9306, 9.9999997473787516355514526367188e-05);
            highp vec2 _9415 = (vec3(dot(_9291, frag_info.camera_right.xyz), dot(_9291, frag_info.camera_up.xyz), _9312).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9312, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _9430 = float(int(((((clamp(floor((log2(max(_9306 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9415.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9415.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _16964 = vec2(textureLod(punctual_index, vec2((mod(_9430, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9430 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _16964 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _6780 = int(_16964.x + 0.5);
    mediump int _6784 = int(_16964.y + 0.5);
    highp vec3 _17635 = vec3(0.0);
    _17635 = vec3(0.0);
    highp vec3 _18365 = vec3(0.0);
    for (int _16965 = 0; _16965 < _6784; _17635 = _18365, _16965++)
    {
        highp float hp_copy_17797 = 0.0;
        highp float _9463 = float(_6780 + _16965);
        highp float _9494 = (float(int(textureLod(punctual_index, vec2((mod(_9463, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9463 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9279;
        highp vec2 _9495 = vec2(0.0625, _9494);
        highp vec4 _9498 = textureLod(punctual_lights, _9495, 0.0);
        highp vec4 _9515 = textureLod(punctual_lights, vec2(0.1875, _9494), 0.0);
        highp float _6802 = _9498.w;
        highp vec3 _6804 = _9515.xyz;
        vec3 _17770 = vec3(0.0);
        highp vec3 _17793 = vec3(0.0);
        float _17797 = 0.0;
        if (_6802 < 0.5)
        {
            _17797 = _16933;
            _17793 = _6804;
            _17770 = -normalize(textureLod(punctual_lights, vec2(0.3125, _9494), 0.0).xyz);
        }
        else
        {
            highp vec3 _6818 = _9498.xyz - v_position;
            highp float _6821 = dot(_6818, _6818);
            highp float _6825 = inversesqrt(max(_6821, 9.9999999392252902907785028219223e-09));
            highp vec3 _6826 = _6818 * _6825;
            vec3 mp_copy_6826 = _6826;
            highp float _6828 = _9515.w;
            highp float _6833 = (_6821 * _6828) * _6828;
            highp float _6838 = clamp(1.0 - (_6833 * _6833), 0.0, 1.0);
            float mp_copy_6838 = _6838;
            if (_6838 <= 0.0)
            {
                _18365 = _17635;
                continue;
            }
            highp vec4 _9549 = textureLod(punctual_lights, vec2(0.4375, _9494), 0.0);
            highp float _6846 = _9549.w;
            float _17802 = 0.0;
            if (_6846 > 0.0)
            {
                highp float _6873 = (_16933 * _16933) + ((_6846 * 0.5) * _6825);
                float mp_copy_6873 = _6873;
                _17802 = sqrt(min(mp_copy_6873, 1.0));
            }
            else
            {
                _17802 = _16933;
            }
            highp vec3 _6880 = _6804 * ((mp_copy_6838 * mp_copy_6838) / max(pow(max(_6821, _6846 * _6846), _9549.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _17794 = vec3(0.0);
            if (_6802 > 1.5)
            {
                highp vec4 _9566 = textureLod(punctual_lights, vec2(0.3125, _9494), 0.0);
                highp float _6899 = clamp((dot(normalize(_9566.xyz), -mp_copy_6826) * _9566.w) + _9549.x, 0.0, 1.0);
                float mp_copy_6899 = _6899;
                highp vec3 _6904 = _6880 * (mp_copy_6899 * mp_copy_6899);
                if (_6899 <= 0.0)
                {
                    _18365 = _17635;
                    continue;
                }
                bool _6910 = _6899 > 0.0;
                bool _6916 = false;
                if (_6910)
                {
                    _6916 = _9549.y > (-0.5);
                }
                else
                {
                    _6916 = _6910;
                }
                bool _6922 = false;
                if (_6916)
                {
                    _6922 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _6922 = _6916;
                }
                highp vec3 _17795 = vec3(0.0);
                if (_6922)
                {
                    float _17761 = 0.0;
                    do
                    {
                        highp vec4 _9678 = mat4(textureLod(punctual_lights, vec2(0.5625, _9494), 0.0), textureLod(punctual_lights, vec2(0.6875, _9494), 0.0), textureLod(punctual_lights, vec2(0.8125, _9494), 0.0), textureLod(punctual_lights, vec2(0.9375, _9494), 0.0)) * vec4(v_position + (_5623 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _9680 = _9678.w;
                        if (_9680 <= 0.0)
                        {
                            _17761 = 1.0;
                            break;
                        }
                        highp vec3 _9689 = _9678.xyz / vec3(_9680);
                        highp vec2 _9694 = (_9689.xy * 0.5) + vec2(0.5);
                        highp float _9696 = _9694.x;
                        bool _9697 = _9696 < 0.0;
                        bool _9704 = false;
                        if (!_9697)
                        {
                            _9704 = _9696 > 1.0;
                        }
                        else
                        {
                            _9704 = _9697;
                        }
                        bool _9711 = false;
                        if (!_9704)
                        {
                            _9711 = _9694.y < 0.0;
                        }
                        else
                        {
                            _9711 = _9704;
                        }
                        bool _9718 = false;
                        if (!_9711)
                        {
                            _9718 = _9694.y > 1.0;
                        }
                        else
                        {
                            _9718 = _9711;
                        }
                        bool _9725 = false;
                        if (!_9718)
                        {
                            _9725 = _9689.z < 0.0;
                        }
                        else
                        {
                            _9725 = _9718;
                        }
                        bool _9732 = false;
                        if (!_9725)
                        {
                            _9732 = _9689.z > 1.0;
                        }
                        else
                        {
                            _9732 = _9725;
                        }
                        if (_9732)
                        {
                            _17761 = 1.0;
                            break;
                        }
                        highp float _9739 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _9744 = frag_info.shadow_cascade_count + float(int(_9549.y + 0.5));
                        highp float _9749 = _9689.z - frag_info.spot_shadow_params.y;
                        highp float _9760 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_9760 = _9760;
                        highp vec2 _9767 = vec2(cos(mp_copy_9760), sin(mp_copy_9760)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _9769 = _9767.x;
                        highp float _9771 = _9767.y;
                        highp vec2 _9779 = vec2(_9769 - _9771, _9769 + _9771) * 0.707106769084930419921875;
                        highp float _9972 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9696, 0.0, 1.0)) / _9739, 1.0 - clamp(_9694.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9972 = _9972;
                        highp vec2 _9787 = _9694 + _9767;
                        highp float _9994 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9787.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9787.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_9994 = _9994;
                        highp vec2 _9795 = _9694 - _9767;
                        highp float _10016 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9795.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9795.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10016 = _10016;
                        highp vec2 _9808 = _9694 + vec2(-_9771, _9769);
                        highp float _10038 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9808.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9808.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10038 = _10038;
                        highp vec2 _9821 = _9694 + vec2(_9771, -_9769);
                        highp float _10060 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9821.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9821.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10060 = _10060;
                        float _9826 = (((mp_copy_9972 + mp_copy_9994) + mp_copy_10016) + mp_copy_10038) + mp_copy_10060;
                        if ((_9826 < 0.5) || (_9826 > 4.5))
                        {
                            _17761 = _9826 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _9838 = _9694 + _9779;
                        highp float _10082 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9838.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9838.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10082 = _10082;
                        highp vec2 _9845 = _9694 - _9779;
                        highp float _10104 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9845.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9845.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10104 = _10104;
                        highp float _9853 = _9779.y;
                        highp float _9856 = _9779.x;
                        highp vec2 _9858 = _9694 + vec2(-_9853, _9856);
                        highp float _10126 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9858.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9858.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10126 = _10126;
                        highp vec2 _9871 = _9694 + vec2(_9853, -_9856);
                        highp float _10148 = float(_9749 <= textureLod(shadow_map, vec2((_9744 + clamp(_9871.x, 0.0, 1.0)) / _9739, 1.0 - clamp(_9871.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_10148 = _10148;
                        _17761 = (_9826 + (((mp_copy_10082 + mp_copy_10104) + mp_copy_10126) + mp_copy_10148)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _17795 = _6904 * _17761;
                }
                else
                {
                    _17795 = _6904;
                }
                _17794 = _17795;
            }
            else
            {
                bool _6938 = _6802 > 0.5;
                bool _6944 = false;
                if (_6938)
                {
                    _6944 = _9549.y > (-0.5);
                }
                else
                {
                    _6944 = _6938;
                }
                bool _6950 = false;
                if (_6944)
                {
                    _6950 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _6950 = _6944;
                }
                highp vec3 _17796 = vec3(0.0);
                if (_6950)
                {
                    float _17748 = 0.0;
                    do
                    {
                        highp vec4 _10461 = textureLod(punctual_lights, vec2(0.5625, _9494), 0.0);
                        highp vec4 _10478 = textureLod(punctual_lights, vec2(0.6875, _9494), 0.0);
                        highp vec3 _10220 = (v_position + (_5623 * _10461.z)) - textureLod(punctual_lights, _9495, 0.0).xyz;
                        highp vec3 _10222 = abs(_10220);
                        highp float _10224 = _10222.x;
                        highp float _10226 = _10222.y;
                        bool _10227 = _10224 >= _10226;
                        bool _10235 = false;
                        if (_10227)
                        {
                            _10235 = _10224 >= _10222.z;
                        }
                        else
                        {
                            _10235 = _10227;
                        }
                        highp vec3 _17738 = vec3(0.0);
                        float _17740 = 0.0;
                        if (_10235)
                        {
                            highp float _10238 = _10220.x;
                            bool _10239 = _10238 >= 0.0;
                            highp vec3 _17737 = vec3(0.0);
                            if (_10239)
                            {
                                _17737 = vec3(-_10220.z, _10220.y, _10238);
                            }
                            else
                            {
                                _17737 = vec3(_10220.zy, -_10238);
                            }
                            _17740 = _10239 ? 0.0 : 1.0;
                            _17738 = _17737;
                        }
                        else
                        {
                            highp vec3 _17739 = vec3(0.0);
                            float _17742 = 0.0;
                            if (_10226 >= _10222.z)
                            {
                                highp float _10272 = _10220.y;
                                bool _10273 = _10272 >= 0.0;
                                highp vec3 _17736 = vec3(0.0);
                                if (_10273)
                                {
                                    _17736 = vec3(-_10220.x, _10220.z, _10272);
                                }
                                else
                                {
                                    _17736 = vec3(_10220.xz, -_10272);
                                }
                                _17742 = _10273 ? 2.0 : 3.0;
                                _17739 = _17736;
                            }
                            else
                            {
                                highp float _10300 = _10220.z;
                                bool _10301 = _10300 >= 0.0;
                                highp vec3 _17735 = vec3(0.0);
                                if (_10301)
                                {
                                    _17735 = _10220;
                                }
                                else
                                {
                                    _17735 = vec3(-_10220.x, _10220.y, -_10300);
                                }
                                _17742 = _10301 ? 4.0 : 5.0;
                                _17739 = _17735;
                            }
                            _17740 = _17742;
                            _17738 = _17739;
                        }
                        if (_17738.z <= 0.0)
                        {
                            _17748 = 1.0;
                            break;
                        }
                        highp vec2 _10341 = ((_17738.xy / vec2(_17738.z)) * 0.5) + vec2(0.5);
                        highp float _10352 = (_10461.x - (_10461.y / _17738.z)) - _10478.x;
                        if ((_10352 < 0.0) || (_10352 > 1.0))
                        {
                            _17748 = 1.0;
                            break;
                        }
                        highp float hp_copy_17745 = 0.0;
                        highp float _10364 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        bool _10370 = _17740 >= 4.0;
                        highp float _10372 = (frag_info.shadow_cascade_count + _9549.y) + float(_10370);
                        float _17745 = 0.0;
                        if (_10370)
                        {
                            _17745 = _17740 - 4.0;
                        }
                        else
                        {
                            _17745 = _17740;
                        }
                        hp_copy_17745 = _17745;
                        highp float _10389 = _10478.y * 0.5;
                        highp float _10392 = _10461.w * 0.0040000001899898052215576171875;
                        highp vec2 _10503 = vec2(_10389);
                        highp vec2 _10506 = vec2(1.0 - _10389);
                        highp vec2 _10512 = vec2(mod(hp_copy_17745, 2.0), 1.0 - floor(hp_copy_17745 * 0.5)) * 0.5;
                        highp vec2 _10515 = _10512 + (clamp(_10341, _10503, _10506) * 0.5);
                        highp float _10408 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float _17747 = 0.0;
                        _17747 = float(_10352 <= textureLod(shadow_map, vec2((_10372 + _10515.x) / _10364, 1.0 - _10515.y), 0.0).x);
                        for (int _17746 = 0; _17746 < 8; )
                        {
                            highp float _10418 = _10408 + (float(_17746) * 0.785398185253143310546875);
                            float mp_copy_10418 = _10418;
                            highp vec2 _10552 = _10512 + (clamp(_10341 + (vec2(cos(mp_copy_10418), sin(mp_copy_10418)) * _10392), _10503, _10506) * 0.5);
                            highp float _10569 = float(_10352 <= textureLod(shadow_map, vec2((_10372 + _10552.x) / _10364, 1.0 - _10552.y), 0.0).x);
                            float mp_copy_10569 = _10569;
                            _17747 += mp_copy_10569;
                            _17746++;
                            continue;
                        }
                        _17748 = _17747 * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _17796 = _6880 * _17748;
                }
                else
                {
                    _17796 = _6880;
                }
                _17794 = _17796;
            }
            _17797 = _17802;
            _17793 = _17794;
            _17770 = _6826;
        }
        hp_copy_17797 = _17797;
        highp vec3 _17824 = vec3(0.0);
        highp vec3 _17825 = vec3(0.0);
        do
        {
            float _10635 = max(dot(_16885, _17770), 0.0);
            highp float hp_copy_10635 = _10635;
            if (_10635 <= 0.0)
            {
                _17825 = vec3(0.0);
                _17824 = vec3(0.0);
                break;
            }
            float _10641 = max(_6767, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_10641 = _10641;
            vec3 _10644 = _17770 + mp_copy_16963;
            float _10647 = dot(_10644, _10644);
            vec3 _17822 = vec3(0.0);
            vec3 _17823 = vec3(0.0);
            if (_10647 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _10655 = _10644 * inversesqrt(_10647);
                float _17821 = 0.0;
                do
                {
                    float _10712 = dot(_16885, _10655);
                    if (_10712 <= 0.0)
                    {
                        _17821 = 0.0;
                        break;
                    }
                    float _10719 = _17797 * _17797;
                    vec3 _10722 = cross(_16885, _10655);
                    float _10725 = _10712 * _10719;
                    float _10734 = _10719 / (dot(_10722, _10722) + (_10725 * _10725));
                    _17821 = min((_10734 * _10734) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _10772 = _6763 + ((vec3(1.0) - _6763) * pow(clamp(1.0 - max(dot(_10655, _16963), 0.0), 0.0, 1.0), 5.0));
                _17823 = (_10772 * min(_17821 * (0.5 / max(mix((2.0 * hp_copy_10635) * _10641, hp_copy_10635 + hp_copy_10641, hp_copy_17797 * hp_copy_17797), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _17822 = _10772;
            }
            else
            {
                _17823 = vec3(0.0);
                _17822 = _6763;
            }
            _17825 = (_17823 * _17793) * _10635;
            _17824 = (((((vec3(1.0) - _17822) * (1.0 - _5757)) * _6615) * 0.3183098733425140380859375) * _17793) * _10635;
            break;
        } while(false);
        _18365 = _17635 + (_17824 + _17825);
    }
    mat3 _6997 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7000 = _16976 > 0.5;
    bvec3 _7003 = bvec3(_7000);
    highp vec3 _7004 = vec3(_7003.x ? _16991.x : _16885.x, _7003.y ? _16991.y : _16885.y, _7003.z ? _16991.z : _16885.z);
    vec3 mp_copy_7004 = _7004;
    vec3 _7005 = _6997 * mp_copy_7004;
    vec3 _16996 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _10819 = _6775 + (((step(vec3(0.0), _6775) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_10819 = _10819;
        highp vec3 _10821 = vec3(1.0) / hp_copy_10819;
        highp vec3 _10838 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _10821, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _10821);
        _16996 = normalize((v_position + (_6775 * max(min(min(_10838.x, _10838.y), _10838.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _16996 = _6775;
    }
    bool _11066 = false;
    vec3 _7010 = _6997 * _16996;
    float _10885 = _7005.y;
    float _10886 = 0.48860299587249755859375 * _10885;
    float _10892 = _7005.z;
    float _10893 = 0.48860299587249755859375 * _10892;
    float _10899 = _7005.x;
    float _10900 = 0.48860299587249755859375 * _10899;
    float _10907 = 1.09254801273345947265625 * _10899;
    float _10910 = _10907 * _10885;
    float _10920 = (1.09254801273345947265625 * _10885) * _10892;
    float _10932 = 0.3153919875621795654296875 * (((3.0 * _10892) * _10892) - 1.0);
    float _10942 = _10907 * _10892;
    float _10958 = 0.546274006366729736328125 * ((_10899 * _10899) - (_10885 * _10885));
    vec3 _7013 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _10886)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _10893)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _10900)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _10910)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _10920)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _10932)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _10942)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _10958), vec3(0.0));
    vec3 _16997 = vec3(0.0);
    do
    {
        _11066 = radiance_layout_info.mip_layout > 0.5;
        if (_11066)
        {
            vec2 _11145 = vec2(atan(_7010.z, _7010.x), asin(clamp(_7010.y, -1.0, 1.0)));
            highp vec2 hp_copy_11145 = _11145;
            _16997 = textureLod(prefiltered_radiance, (hp_copy_11145 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_16933, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _11164 = vec2(atan(_7010.z, _7010.x), asin(clamp(_7010.y, -1.0, 1.0)));
        highp vec2 hp_copy_11164 = _11164;
        highp vec2 _11169 = (hp_copy_11164 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _11076 = clamp(_11169.y, 0.00390625, 0.99609375);
        float _11080 = clamp(_16933, 0.0, 1.0) * 7.0;
        float _11082 = floor(_11080);
        highp float _11101 = _11169.x;
        _16997 = mix(textureLod(prefiltered_radiance, vec2(_11101, (_11082 + _11076) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_11101, (min(_11082 + 1.0, 7.0) + _11076) * 0.125), 0.0).xyz, vec3(_11080 - _11082));
        break;
    } while(false);
    bool _7020 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _17002 = vec3(0.0);
    highp vec3 _17003 = vec3(0.0);
    if (_7020)
    {
        vec3 _16998 = vec3(0.0);
        do
        {
            if (_11066)
            {
                vec2 _11457 = vec2(atan(_7010.z, _7010.x), asin(clamp(_7010.y, -1.0, 1.0)));
                highp vec2 hp_copy_11457 = _11457;
                _16998 = textureLod(prefiltered_radiance_b, (hp_copy_11457 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_16933, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _11476 = vec2(atan(_7010.z, _7010.x), asin(clamp(_7010.y, -1.0, 1.0)));
            highp vec2 hp_copy_11476 = _11476;
            highp vec2 _11481 = (hp_copy_11476 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _11388 = clamp(_11481.y, 0.00390625, 0.99609375);
            float _11392 = clamp(_16933, 0.0, 1.0) * 7.0;
            float _11394 = floor(_11392);
            highp float _11413 = _11481.x;
            _16998 = mix(textureLod(prefiltered_radiance_b, vec2(_11413, (_11394 + _11388) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_11413, (min(_11394 + 1.0, 7.0) + _11388) * 0.125), 0.0).xyz, vec3(_11392 - _11394));
            break;
        } while(false);
        highp vec3 _7031 = vec3(frag_info.radiance_blend.x);
        _17003 = mix(_16997, _16998, _7031);
        _17002 = mix(_7013, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _10886)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _10893)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _10900)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _10910)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _10920)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _10932)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _10942)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _10958), vec3(0.0)), _7031);
    }
    else
    {
        _17003 = _16997;
        _17002 = _7013;
    }
    highp float _11494 = 0.0;
    highp vec3 _7042 = _17002 * frag_info.environment_intensity;
    float _17004 = 0.0;
    do
    {
        _11494 = frag_info.gi_grid.w;
        if (_11494 <= 0.0)
        {
            _17004 = 0.0;
            break;
        }
        highp vec3 _11507 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _11515 = min(_11507, (frag_info.gi_counts.xyz - vec3(1.0)) - _11507);
        _17004 = clamp(min(_11515.x, min(_11515.y, _11515.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _17195 = vec3(0.0);
    if (_17004 > 0.0)
    {
        highp vec3 _11607 = v_position + (((_16885 * 0.20000000298023223876953125) + (mp_copy_16963 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _11610 = _11607 / frag_info.gi_grid.xyz;
        highp vec3 _11612 = floor(_11610);
        highp vec3 _11618 = clamp(_11610 - _11612, vec3(0.0), vec3(1.0));
        vec3 mp_copy_11618 = _11618;
        highp vec3 _11740 = _11612 - frag_info.gi_anchor.xyz;
        bool _11743 = any(lessThan(_11740, vec3(0.0)));
        bool _11751 = false;
        if (!_11743)
        {
            _11751 = any(greaterThanEqual(_11740, frag_info.gi_counts.xyz));
        }
        else
        {
            _11751 = _11743;
        }
        vec3 mp_copy_17005 = vec3(0.0);
        highp float _11752 = _11751 ? 0.0 : 1.0;
        float mp_copy_11752 = _11752;
        vec3 _11754 = vec3(1.0) - mp_copy_11618;
        vec3 _11758 = max(_11754, vec3(0.001000000047497451305389404296875));
        highp vec3 _11774 = (_11612 * frag_info.gi_grid.xyz) - _11607;
        highp float _11776 = length(_11774);
        highp vec3 _17005 = vec3(0.0);
        if (_11776 > 9.9999997473787516355514526367188e-06)
        {
            _17005 = _11774 / vec3(_11776);
        }
        else
        {
            _17005 = _16885;
        }
        mp_copy_17005 = _17005;
        float _11794 = pow((dot(_17005, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11919 = _11612 - (frag_info.gi_counts.xyz * floor(_11612 / frag_info.gi_counts.xyz));
        highp float _11935 = _11919.x + (frag_info.gi_counts.x * (_11919.y + (frag_info.gi_counts.y * _11919.z)));
        bool _11805 = frag_info.gi_visibility.x > 0.0;
        float _17010 = 0.0;
        if (_11805)
        {
            highp float _11943 = floor(_11935 / frag_info.gi_counts.w);
            highp vec2 _11957 = vec2((_11935 - (_11943 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11943 * 16.0));
            vec3 _11817 = -mp_copy_17005;
            vec3 _12005 = _11817 / vec3((abs(_11817.x) + abs(_11817.y)) + abs(_11817.z));
            vec2 _17006 = vec2(0.0);
            if (_12005.z >= 0.0)
            {
                _17006 = _12005.xy;
            }
            else
            {
                _17006 = (vec2(1.0) - abs(_12005.yx)) * vec2((_12005.x >= 0.0) ? 1.0 : (-1.0), (_12005.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11821 = texture(irradiance_field, clamp((_11957 + vec2(1.0)) + (clamp((_17006 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11957 + vec2(0.5), _11957 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11826 = _11821.x * frag_info.gi_visibility.z;
            highp float _11838 = abs((_11826 * _11826) - ((_11821.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11844 = (_11776 - _11826) - frag_info.gi_visibility.y;
            highp float _17007 = 0.0;
            if (_11844 <= 0.0)
            {
                _17007 = 1.0;
            }
            else
            {
                _17007 = _11838 / (_11838 + (_11844 * _11844));
            }
            _17010 = _11794 * mix(1.0, max(0.0500000007450580596923828125, (_17007 * _17007) * _17007), frag_info.gi_visibility.x);
        }
        else
        {
            _17010 = _11794;
        }
        float _11872 = max(9.9999999747524270787835121154785e-07, _17010);
        float _17011 = 0.0;
        if (_11872 < 0.20000000298023223876953125)
        {
            _17011 = _11872 * ((_11872 * _11872) * 25.0);
        }
        else
        {
            _17011 = _11872;
        }
        float _11887 = _17011 * (((_11758.x * _11758.y) * _11758.z) * mp_copy_11752);
        highp float _12046 = floor(_11935 / frag_info.gi_counts.w);
        highp vec2 _12060 = vec2((_11935 - (_12046 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12046 * 8.0));
        vec3 _12108 = _16885 / vec3((abs(_16885.x) + abs(_16885.y)) + abs(_16885.z));
        bool _12111 = _12108.z >= 0.0;
        vec2 _17012 = vec2(0.0);
        if (_12111)
        {
            _17012 = _12108.xy;
        }
        else
        {
            _17012 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11899 = texture(irradiance_field, clamp((_12060 + vec2(1.0)) + (clamp((_17012 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12060 + vec2(0.5), _12060 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12194 = _11612 + vec3(1.0, 0.0, 0.0);
        highp vec3 _12199 = _12194 - frag_info.gi_anchor.xyz;
        bool _12202 = any(lessThan(_12199, vec3(0.0)));
        bool _12210 = false;
        if (!_12202)
        {
            _12210 = any(greaterThanEqual(_12199, frag_info.gi_counts.xyz));
        }
        else
        {
            _12210 = _12202;
        }
        vec3 mp_copy_17014 = vec3(0.0);
        highp float _12211 = _12210 ? 0.0 : 1.0;
        float mp_copy_12211 = _12211;
        vec3 _12217 = max(mix(_11754, mp_copy_11618, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _12233 = (_12194 * frag_info.gi_grid.xyz) - _11607;
        highp float _12235 = length(_12233);
        highp vec3 _17014 = vec3(0.0);
        if (_12235 > 9.9999997473787516355514526367188e-06)
        {
            _17014 = _12233 / vec3(_12235);
        }
        else
        {
            _17014 = _16885;
        }
        mp_copy_17014 = _17014;
        float _12253 = pow((dot(_17014, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12378 = _12194 - (frag_info.gi_counts.xyz * floor(_12194 / frag_info.gi_counts.xyz));
        highp float _12394 = _12378.x + (frag_info.gi_counts.x * (_12378.y + (frag_info.gi_counts.y * _12378.z)));
        float _17019 = 0.0;
        if (_11805)
        {
            highp float _12402 = floor(_12394 / frag_info.gi_counts.w);
            highp vec2 _12416 = vec2((_12394 - (_12402 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12402 * 16.0));
            vec3 _12276 = -mp_copy_17014;
            vec3 _12464 = _12276 / vec3((abs(_12276.x) + abs(_12276.y)) + abs(_12276.z));
            vec2 _17015 = vec2(0.0);
            if (_12464.z >= 0.0)
            {
                _17015 = _12464.xy;
            }
            else
            {
                _17015 = (vec2(1.0) - abs(_12464.yx)) * vec2((_12464.x >= 0.0) ? 1.0 : (-1.0), (_12464.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12280 = texture(irradiance_field, clamp((_12416 + vec2(1.0)) + (clamp((_17015 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12416 + vec2(0.5), _12416 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12285 = _12280.x * frag_info.gi_visibility.z;
            highp float _12297 = abs((_12285 * _12285) - ((_12280.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12303 = (_12235 - _12285) - frag_info.gi_visibility.y;
            highp float _17016 = 0.0;
            if (_12303 <= 0.0)
            {
                _17016 = 1.0;
            }
            else
            {
                _17016 = _12297 / (_12297 + (_12303 * _12303));
            }
            _17019 = _12253 * mix(1.0, max(0.0500000007450580596923828125, (_17016 * _17016) * _17016), frag_info.gi_visibility.x);
        }
        else
        {
            _17019 = _12253;
        }
        float _12331 = max(9.9999999747524270787835121154785e-07, _17019);
        float _17020 = 0.0;
        if (_12331 < 0.20000000298023223876953125)
        {
            _17020 = _12331 * ((_12331 * _12331) * 25.0);
        }
        else
        {
            _17020 = _12331;
        }
        float _12346 = _17020 * (((_12217.x * _12217.y) * _12217.z) * mp_copy_12211);
        highp float _12505 = floor(_12394 / frag_info.gi_counts.w);
        highp vec2 _12519 = vec2((_12394 - (_12505 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12505 * 8.0));
        vec2 _17021 = vec2(0.0);
        if (_12111)
        {
            _17021 = _12108.xy;
        }
        else
        {
            _17021 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12358 = texture(irradiance_field, clamp((_12519 + vec2(1.0)) + (clamp((_17021 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12519 + vec2(0.5), _12519 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12653 = _11612 + vec3(0.0, 1.0, 0.0);
        highp vec3 _12658 = _12653 - frag_info.gi_anchor.xyz;
        bool _12661 = any(lessThan(_12658, vec3(0.0)));
        bool _12669 = false;
        if (!_12661)
        {
            _12669 = any(greaterThanEqual(_12658, frag_info.gi_counts.xyz));
        }
        else
        {
            _12669 = _12661;
        }
        vec3 mp_copy_17023 = vec3(0.0);
        highp float _12670 = _12669 ? 0.0 : 1.0;
        float mp_copy_12670 = _12670;
        vec3 _12676 = max(mix(_11754, mp_copy_11618, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _12692 = (_12653 * frag_info.gi_grid.xyz) - _11607;
        highp float _12694 = length(_12692);
        highp vec3 _17023 = vec3(0.0);
        if (_12694 > 9.9999997473787516355514526367188e-06)
        {
            _17023 = _12692 / vec3(_12694);
        }
        else
        {
            _17023 = _16885;
        }
        mp_copy_17023 = _17023;
        float _12712 = pow((dot(_17023, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12837 = _12653 - (frag_info.gi_counts.xyz * floor(_12653 / frag_info.gi_counts.xyz));
        highp float _12853 = _12837.x + (frag_info.gi_counts.x * (_12837.y + (frag_info.gi_counts.y * _12837.z)));
        float _17028 = 0.0;
        if (_11805)
        {
            highp float _12861 = floor(_12853 / frag_info.gi_counts.w);
            highp vec2 _12875 = vec2((_12853 - (_12861 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12861 * 16.0));
            vec3 _12735 = -mp_copy_17023;
            vec3 _12923 = _12735 / vec3((abs(_12735.x) + abs(_12735.y)) + abs(_12735.z));
            vec2 _17024 = vec2(0.0);
            if (_12923.z >= 0.0)
            {
                _17024 = _12923.xy;
            }
            else
            {
                _17024 = (vec2(1.0) - abs(_12923.yx)) * vec2((_12923.x >= 0.0) ? 1.0 : (-1.0), (_12923.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12739 = texture(irradiance_field, clamp((_12875 + vec2(1.0)) + (clamp((_17024 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12875 + vec2(0.5), _12875 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12744 = _12739.x * frag_info.gi_visibility.z;
            highp float _12756 = abs((_12744 * _12744) - ((_12739.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12762 = (_12694 - _12744) - frag_info.gi_visibility.y;
            highp float _17025 = 0.0;
            if (_12762 <= 0.0)
            {
                _17025 = 1.0;
            }
            else
            {
                _17025 = _12756 / (_12756 + (_12762 * _12762));
            }
            _17028 = _12712 * mix(1.0, max(0.0500000007450580596923828125, (_17025 * _17025) * _17025), frag_info.gi_visibility.x);
        }
        else
        {
            _17028 = _12712;
        }
        float _12790 = max(9.9999999747524270787835121154785e-07, _17028);
        float _17029 = 0.0;
        if (_12790 < 0.20000000298023223876953125)
        {
            _17029 = _12790 * ((_12790 * _12790) * 25.0);
        }
        else
        {
            _17029 = _12790;
        }
        float _12805 = _17029 * (((_12676.x * _12676.y) * _12676.z) * mp_copy_12670);
        highp float _12964 = floor(_12853 / frag_info.gi_counts.w);
        highp vec2 _12978 = vec2((_12853 - (_12964 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12964 * 8.0));
        vec2 _17030 = vec2(0.0);
        if (_12111)
        {
            _17030 = _12108.xy;
        }
        else
        {
            _17030 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12817 = texture(irradiance_field, clamp((_12978 + vec2(1.0)) + (clamp((_17030 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12978 + vec2(0.5), _12978 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13112 = _11612 + vec3(1.0, 1.0, 0.0);
        highp vec3 _13117 = _13112 - frag_info.gi_anchor.xyz;
        bool _13120 = any(lessThan(_13117, vec3(0.0)));
        bool _13128 = false;
        if (!_13120)
        {
            _13128 = any(greaterThanEqual(_13117, frag_info.gi_counts.xyz));
        }
        else
        {
            _13128 = _13120;
        }
        vec3 mp_copy_17032 = vec3(0.0);
        highp float _13129 = _13128 ? 0.0 : 1.0;
        float mp_copy_13129 = _13129;
        vec3 _13135 = max(mix(_11754, mp_copy_11618, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13151 = (_13112 * frag_info.gi_grid.xyz) - _11607;
        highp float _13153 = length(_13151);
        highp vec3 _17032 = vec3(0.0);
        if (_13153 > 9.9999997473787516355514526367188e-06)
        {
            _17032 = _13151 / vec3(_13153);
        }
        else
        {
            _17032 = _16885;
        }
        mp_copy_17032 = _17032;
        float _13171 = pow((dot(_17032, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13296 = _13112 - (frag_info.gi_counts.xyz * floor(_13112 / frag_info.gi_counts.xyz));
        highp float _13312 = _13296.x + (frag_info.gi_counts.x * (_13296.y + (frag_info.gi_counts.y * _13296.z)));
        float _17037 = 0.0;
        if (_11805)
        {
            highp float _13320 = floor(_13312 / frag_info.gi_counts.w);
            highp vec2 _13334 = vec2((_13312 - (_13320 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13320 * 16.0));
            vec3 _13194 = -mp_copy_17032;
            vec3 _13382 = _13194 / vec3((abs(_13194.x) + abs(_13194.y)) + abs(_13194.z));
            vec2 _17033 = vec2(0.0);
            if (_13382.z >= 0.0)
            {
                _17033 = _13382.xy;
            }
            else
            {
                _17033 = (vec2(1.0) - abs(_13382.yx)) * vec2((_13382.x >= 0.0) ? 1.0 : (-1.0), (_13382.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13198 = texture(irradiance_field, clamp((_13334 + vec2(1.0)) + (clamp((_17033 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13334 + vec2(0.5), _13334 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13203 = _13198.x * frag_info.gi_visibility.z;
            highp float _13215 = abs((_13203 * _13203) - ((_13198.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13221 = (_13153 - _13203) - frag_info.gi_visibility.y;
            highp float _17034 = 0.0;
            if (_13221 <= 0.0)
            {
                _17034 = 1.0;
            }
            else
            {
                _17034 = _13215 / (_13215 + (_13221 * _13221));
            }
            _17037 = _13171 * mix(1.0, max(0.0500000007450580596923828125, (_17034 * _17034) * _17034), frag_info.gi_visibility.x);
        }
        else
        {
            _17037 = _13171;
        }
        float _13249 = max(9.9999999747524270787835121154785e-07, _17037);
        float _17038 = 0.0;
        if (_13249 < 0.20000000298023223876953125)
        {
            _17038 = _13249 * ((_13249 * _13249) * 25.0);
        }
        else
        {
            _17038 = _13249;
        }
        float _13264 = _17038 * (((_13135.x * _13135.y) * _13135.z) * mp_copy_13129);
        highp float _13423 = floor(_13312 / frag_info.gi_counts.w);
        highp vec2 _13437 = vec2((_13312 - (_13423 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13423 * 8.0));
        vec2 _17039 = vec2(0.0);
        if (_12111)
        {
            _17039 = _12108.xy;
        }
        else
        {
            _17039 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13276 = texture(irradiance_field, clamp((_13437 + vec2(1.0)) + (clamp((_17039 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13437 + vec2(0.5), _13437 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13571 = _11612 + vec3(0.0, 0.0, 1.0);
        highp vec3 _13576 = _13571 - frag_info.gi_anchor.xyz;
        bool _13579 = any(lessThan(_13576, vec3(0.0)));
        bool _13587 = false;
        if (!_13579)
        {
            _13587 = any(greaterThanEqual(_13576, frag_info.gi_counts.xyz));
        }
        else
        {
            _13587 = _13579;
        }
        vec3 mp_copy_17041 = vec3(0.0);
        highp float _13588 = _13587 ? 0.0 : 1.0;
        float mp_copy_13588 = _13588;
        vec3 _13594 = max(mix(_11754, mp_copy_11618, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13610 = (_13571 * frag_info.gi_grid.xyz) - _11607;
        highp float _13612 = length(_13610);
        highp vec3 _17041 = vec3(0.0);
        if (_13612 > 9.9999997473787516355514526367188e-06)
        {
            _17041 = _13610 / vec3(_13612);
        }
        else
        {
            _17041 = _16885;
        }
        mp_copy_17041 = _17041;
        float _13630 = pow((dot(_17041, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13755 = _13571 - (frag_info.gi_counts.xyz * floor(_13571 / frag_info.gi_counts.xyz));
        highp float _13771 = _13755.x + (frag_info.gi_counts.x * (_13755.y + (frag_info.gi_counts.y * _13755.z)));
        float _17046 = 0.0;
        if (_11805)
        {
            highp float _13779 = floor(_13771 / frag_info.gi_counts.w);
            highp vec2 _13793 = vec2((_13771 - (_13779 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13779 * 16.0));
            vec3 _13653 = -mp_copy_17041;
            vec3 _13841 = _13653 / vec3((abs(_13653.x) + abs(_13653.y)) + abs(_13653.z));
            vec2 _17042 = vec2(0.0);
            if (_13841.z >= 0.0)
            {
                _17042 = _13841.xy;
            }
            else
            {
                _17042 = (vec2(1.0) - abs(_13841.yx)) * vec2((_13841.x >= 0.0) ? 1.0 : (-1.0), (_13841.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13657 = texture(irradiance_field, clamp((_13793 + vec2(1.0)) + (clamp((_17042 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13793 + vec2(0.5), _13793 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13662 = _13657.x * frag_info.gi_visibility.z;
            highp float _13674 = abs((_13662 * _13662) - ((_13657.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13680 = (_13612 - _13662) - frag_info.gi_visibility.y;
            highp float _17043 = 0.0;
            if (_13680 <= 0.0)
            {
                _17043 = 1.0;
            }
            else
            {
                _17043 = _13674 / (_13674 + (_13680 * _13680));
            }
            _17046 = _13630 * mix(1.0, max(0.0500000007450580596923828125, (_17043 * _17043) * _17043), frag_info.gi_visibility.x);
        }
        else
        {
            _17046 = _13630;
        }
        float _13708 = max(9.9999999747524270787835121154785e-07, _17046);
        float _17047 = 0.0;
        if (_13708 < 0.20000000298023223876953125)
        {
            _17047 = _13708 * ((_13708 * _13708) * 25.0);
        }
        else
        {
            _17047 = _13708;
        }
        float _13723 = _17047 * (((_13594.x * _13594.y) * _13594.z) * mp_copy_13588);
        highp float _13882 = floor(_13771 / frag_info.gi_counts.w);
        highp vec2 _13896 = vec2((_13771 - (_13882 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13882 * 8.0));
        vec2 _17048 = vec2(0.0);
        if (_12111)
        {
            _17048 = _12108.xy;
        }
        else
        {
            _17048 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13735 = texture(irradiance_field, clamp((_13896 + vec2(1.0)) + (clamp((_17048 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13896 + vec2(0.5), _13896 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14030 = _11612 + vec3(1.0, 0.0, 1.0);
        highp vec3 _14035 = _14030 - frag_info.gi_anchor.xyz;
        bool _14038 = any(lessThan(_14035, vec3(0.0)));
        bool _14046 = false;
        if (!_14038)
        {
            _14046 = any(greaterThanEqual(_14035, frag_info.gi_counts.xyz));
        }
        else
        {
            _14046 = _14038;
        }
        vec3 mp_copy_17050 = vec3(0.0);
        highp float _14047 = _14046 ? 0.0 : 1.0;
        float mp_copy_14047 = _14047;
        vec3 _14053 = max(mix(_11754, mp_copy_11618, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14069 = (_14030 * frag_info.gi_grid.xyz) - _11607;
        highp float _14071 = length(_14069);
        highp vec3 _17050 = vec3(0.0);
        if (_14071 > 9.9999997473787516355514526367188e-06)
        {
            _17050 = _14069 / vec3(_14071);
        }
        else
        {
            _17050 = _16885;
        }
        mp_copy_17050 = _17050;
        float _14089 = pow((dot(_17050, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14214 = _14030 - (frag_info.gi_counts.xyz * floor(_14030 / frag_info.gi_counts.xyz));
        highp float _14230 = _14214.x + (frag_info.gi_counts.x * (_14214.y + (frag_info.gi_counts.y * _14214.z)));
        float _17055 = 0.0;
        if (_11805)
        {
            highp float _14238 = floor(_14230 / frag_info.gi_counts.w);
            highp vec2 _14252 = vec2((_14230 - (_14238 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14238 * 16.0));
            vec3 _14112 = -mp_copy_17050;
            vec3 _14300 = _14112 / vec3((abs(_14112.x) + abs(_14112.y)) + abs(_14112.z));
            vec2 _17051 = vec2(0.0);
            if (_14300.z >= 0.0)
            {
                _17051 = _14300.xy;
            }
            else
            {
                _17051 = (vec2(1.0) - abs(_14300.yx)) * vec2((_14300.x >= 0.0) ? 1.0 : (-1.0), (_14300.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14116 = texture(irradiance_field, clamp((_14252 + vec2(1.0)) + (clamp((_17051 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14252 + vec2(0.5), _14252 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14121 = _14116.x * frag_info.gi_visibility.z;
            highp float _14133 = abs((_14121 * _14121) - ((_14116.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14139 = (_14071 - _14121) - frag_info.gi_visibility.y;
            highp float _17052 = 0.0;
            if (_14139 <= 0.0)
            {
                _17052 = 1.0;
            }
            else
            {
                _17052 = _14133 / (_14133 + (_14139 * _14139));
            }
            _17055 = _14089 * mix(1.0, max(0.0500000007450580596923828125, (_17052 * _17052) * _17052), frag_info.gi_visibility.x);
        }
        else
        {
            _17055 = _14089;
        }
        float _14167 = max(9.9999999747524270787835121154785e-07, _17055);
        float _17056 = 0.0;
        if (_14167 < 0.20000000298023223876953125)
        {
            _17056 = _14167 * ((_14167 * _14167) * 25.0);
        }
        else
        {
            _17056 = _14167;
        }
        float _14182 = _17056 * (((_14053.x * _14053.y) * _14053.z) * mp_copy_14047);
        highp float _14341 = floor(_14230 / frag_info.gi_counts.w);
        highp vec2 _14355 = vec2((_14230 - (_14341 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14341 * 8.0));
        vec2 _17057 = vec2(0.0);
        if (_12111)
        {
            _17057 = _12108.xy;
        }
        else
        {
            _17057 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14194 = texture(irradiance_field, clamp((_14355 + vec2(1.0)) + (clamp((_17057 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14355 + vec2(0.5), _14355 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14489 = _11612 + vec3(0.0, 1.0, 1.0);
        highp vec3 _14494 = _14489 - frag_info.gi_anchor.xyz;
        bool _14497 = any(lessThan(_14494, vec3(0.0)));
        bool _14505 = false;
        if (!_14497)
        {
            _14505 = any(greaterThanEqual(_14494, frag_info.gi_counts.xyz));
        }
        else
        {
            _14505 = _14497;
        }
        vec3 mp_copy_17059 = vec3(0.0);
        highp float _14506 = _14505 ? 0.0 : 1.0;
        float mp_copy_14506 = _14506;
        vec3 _14512 = max(mix(_11754, mp_copy_11618, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14528 = (_14489 * frag_info.gi_grid.xyz) - _11607;
        highp float _14530 = length(_14528);
        highp vec3 _17059 = vec3(0.0);
        if (_14530 > 9.9999997473787516355514526367188e-06)
        {
            _17059 = _14528 / vec3(_14530);
        }
        else
        {
            _17059 = _16885;
        }
        mp_copy_17059 = _17059;
        float _14548 = pow((dot(_17059, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14673 = _14489 - (frag_info.gi_counts.xyz * floor(_14489 / frag_info.gi_counts.xyz));
        highp float _14689 = _14673.x + (frag_info.gi_counts.x * (_14673.y + (frag_info.gi_counts.y * _14673.z)));
        float _17064 = 0.0;
        if (_11805)
        {
            highp float _14697 = floor(_14689 / frag_info.gi_counts.w);
            highp vec2 _14711 = vec2((_14689 - (_14697 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14697 * 16.0));
            vec3 _14571 = -mp_copy_17059;
            vec3 _14759 = _14571 / vec3((abs(_14571.x) + abs(_14571.y)) + abs(_14571.z));
            vec2 _17060 = vec2(0.0);
            if (_14759.z >= 0.0)
            {
                _17060 = _14759.xy;
            }
            else
            {
                _17060 = (vec2(1.0) - abs(_14759.yx)) * vec2((_14759.x >= 0.0) ? 1.0 : (-1.0), (_14759.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14575 = texture(irradiance_field, clamp((_14711 + vec2(1.0)) + (clamp((_17060 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14711 + vec2(0.5), _14711 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14580 = _14575.x * frag_info.gi_visibility.z;
            highp float _14592 = abs((_14580 * _14580) - ((_14575.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14598 = (_14530 - _14580) - frag_info.gi_visibility.y;
            highp float _17061 = 0.0;
            if (_14598 <= 0.0)
            {
                _17061 = 1.0;
            }
            else
            {
                _17061 = _14592 / (_14592 + (_14598 * _14598));
            }
            _17064 = _14548 * mix(1.0, max(0.0500000007450580596923828125, (_17061 * _17061) * _17061), frag_info.gi_visibility.x);
        }
        else
        {
            _17064 = _14548;
        }
        float _14626 = max(9.9999999747524270787835121154785e-07, _17064);
        float _17065 = 0.0;
        if (_14626 < 0.20000000298023223876953125)
        {
            _17065 = _14626 * ((_14626 * _14626) * 25.0);
        }
        else
        {
            _17065 = _14626;
        }
        float _14641 = _17065 * (((_14512.x * _14512.y) * _14512.z) * mp_copy_14506);
        highp float _14800 = floor(_14689 / frag_info.gi_counts.w);
        highp vec2 _14814 = vec2((_14689 - (_14800 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14800 * 8.0));
        vec2 _17066 = vec2(0.0);
        if (_12111)
        {
            _17066 = _12108.xy;
        }
        else
        {
            _17066 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14653 = texture(irradiance_field, clamp((_14814 + vec2(1.0)) + (clamp((_17066 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14814 + vec2(0.5), _14814 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14948 = _11612 + vec3(1.0);
        highp vec3 _14953 = _14948 - frag_info.gi_anchor.xyz;
        bool _14956 = any(lessThan(_14953, vec3(0.0)));
        bool _14964 = false;
        if (!_14956)
        {
            _14964 = any(greaterThanEqual(_14953, frag_info.gi_counts.xyz));
        }
        else
        {
            _14964 = _14956;
        }
        vec3 mp_copy_17068 = vec3(0.0);
        highp float _14965 = _14964 ? 0.0 : 1.0;
        float mp_copy_14965 = _14965;
        vec3 _14971 = max(mp_copy_11618, vec3(0.001000000047497451305389404296875));
        highp vec3 _14987 = (_14948 * frag_info.gi_grid.xyz) - _11607;
        highp float _14989 = length(_14987);
        highp vec3 _17068 = vec3(0.0);
        if (_14989 > 9.9999997473787516355514526367188e-06)
        {
            _17068 = _14987 / vec3(_14989);
        }
        else
        {
            _17068 = _16885;
        }
        mp_copy_17068 = _17068;
        float _15007 = pow((dot(_17068, _16885) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15132 = _14948 - (frag_info.gi_counts.xyz * floor(_14948 / frag_info.gi_counts.xyz));
        highp float _15148 = _15132.x + (frag_info.gi_counts.x * (_15132.y + (frag_info.gi_counts.y * _15132.z)));
        float _17073 = 0.0;
        if (_11805)
        {
            highp float _15156 = floor(_15148 / frag_info.gi_counts.w);
            highp vec2 _15170 = vec2((_15148 - (_15156 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15156 * 16.0));
            vec3 _15030 = -mp_copy_17068;
            vec3 _15218 = _15030 / vec3((abs(_15030.x) + abs(_15030.y)) + abs(_15030.z));
            vec2 _17069 = vec2(0.0);
            if (_15218.z >= 0.0)
            {
                _17069 = _15218.xy;
            }
            else
            {
                _17069 = (vec2(1.0) - abs(_15218.yx)) * vec2((_15218.x >= 0.0) ? 1.0 : (-1.0), (_15218.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15034 = texture(irradiance_field, clamp((_15170 + vec2(1.0)) + (clamp((_17069 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15170 + vec2(0.5), _15170 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15039 = _15034.x * frag_info.gi_visibility.z;
            highp float _15051 = abs((_15039 * _15039) - ((_15034.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15057 = (_14989 - _15039) - frag_info.gi_visibility.y;
            highp float _17070 = 0.0;
            if (_15057 <= 0.0)
            {
                _17070 = 1.0;
            }
            else
            {
                _17070 = _15051 / (_15051 + (_15057 * _15057));
            }
            _17073 = _15007 * mix(1.0, max(0.0500000007450580596923828125, (_17070 * _17070) * _17070), frag_info.gi_visibility.x);
        }
        else
        {
            _17073 = _15007;
        }
        float _15085 = max(9.9999999747524270787835121154785e-07, _17073);
        float _17074 = 0.0;
        if (_15085 < 0.20000000298023223876953125)
        {
            _17074 = _15085 * ((_15085 * _15085) * 25.0);
        }
        else
        {
            _17074 = _15085;
        }
        float _15100 = _17074 * (((_14971.x * _14971.y) * _14971.z) * mp_copy_14965);
        highp float _15259 = floor(_15148 / frag_info.gi_counts.w);
        highp vec2 _15273 = vec2((_15148 - (_15259 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15259 * 8.0));
        vec2 _17075 = vec2(0.0);
        if (_12111)
        {
            _17075 = _12108.xy;
        }
        else
        {
            _17075 = (vec2(1.0) - abs(_12108.yx)) * vec2((_12108.x >= 0.0) ? 1.0 : (-1.0), (_12108.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11665 = ((((((vec4(max(_11899.xyz, vec3(0.0)) * _11887, _11887) + vec4(max(_12358.xyz, vec3(0.0)) * _12346, _12346)) + vec4(max(_12817.xyz, vec3(0.0)) * _12805, _12805)) + vec4(max(_13276.xyz, vec3(0.0)) * _13264, _13264)) + vec4(max(_13735.xyz, vec3(0.0)) * _13723, _13723)) + vec4(max(_14194.xyz, vec3(0.0)) * _14182, _14182)) + vec4(max(_14653.xyz, vec3(0.0)) * _14641, _14641)) + vec4(max(texture(irradiance_field, clamp((_15273 + vec2(1.0)) + (clamp((_17075 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15273 + vec2(0.5), _15273 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _15100, _15100);
        highp float _11667 = _11665.w;
        highp vec3 _17077 = vec3(0.0);
        if (_11667 > 9.9999999747524270787835121154785e-07)
        {
            _17077 = _11665.xyz / vec3(_11667);
        }
        else
        {
            _17077 = vec3(0.0);
        }
        _17195 = mix(_7042, _17077 * _11494, vec3(_17004));
    }
    else
    {
        _17195 = _7042;
    }
    vec2 _7068 = clamp(vec2(_6771, _16933), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7070 = texture(brdf_lut, vec2(_7068.x * 0.3333333432674407958984375, _7068.y));
    float _7074 = _7070.x;
    float _7077 = _7070.y;
    vec3 _7079 = ((_6763 + ((max(vec3(1.0 - _16933), _6763) - _6763) * pow(clamp(1.0 - _6771, 0.0, 1.0), 5.0))) * _7074) + vec3(_7077);
    float _7085 = 1.0 - (_7074 + _7077);
    vec3 _7089 = vec3(1.0) - _6763;
    vec3 _7092 = _6763 + (_7089 * vec3(0.0476190485060214996337890625));
    vec3 _7103 = ((_7079 * _7085) * _7092) / (vec3(1.0) - (_7092 * _7085));
    float _7106 = 1.0 - _5757;
    vec3 _7107 = _6615 * _7106;
    float _17474 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7000)
    {
        float _15381 = max(acos(clamp(exp2(((-3.321929931640625) * _16933) * _16933), 0.0, 1.0)), 0.100000001490116119384765625);
        _17474 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_16991, _6775), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _17274, 0.0, 1.0)))) + _15381) / (2.0 * _15381), 0.0, 1.0));
    }
    else
    {
        float _17475 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _17475 = clamp((pow(_6767 + _17274, exp2(((-16.0) * _16933) - 1.0)) - 1.0) + _17274, 0.0, 1.0);
        }
        else
        {
            _17475 = _17274;
        }
        _17474 = _17475;
    }
    highp vec3 _7166 = ((((_7103 + (_7107 * ((vec3(1.0) - _7079) - _7103))) * _17195) * _17413) + (((_7079 * (_17003 * frag_info.environment_intensity)) * 1.0) * _17474)) * mix(1.0, _6754, frag_info.radiance_blend.y);
    highp vec3 _17706 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _17706 = _7166 + ((_16958.xyz * _7107) * _5791);
    }
    else
    {
        _17706 = _7166;
    }
    highp vec3 _17710 = vec3(0.0);
    if (_6704)
    {
        highp vec3 _17625 = vec3(0.0);
        highp vec3 _17626 = vec3(0.0);
        do
        {
            float _15478 = max(dot(_16885, _17561), 0.0);
            highp float hp_copy_15478 = _15478;
            if (_15478 <= 0.0)
            {
                _17626 = vec3(0.0);
                _17625 = vec3(0.0);
                break;
            }
            float _15484 = max(_6767, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_15484 = _15484;
            vec3 _15487 = _17561 + mp_copy_16963;
            float _15490 = dot(_15487, _15487);
            vec3 _17623 = vec3(0.0);
            vec3 _17624 = vec3(0.0);
            if (_15490 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _15498 = _15487 * inversesqrt(_15490);
                float _17622 = 0.0;
                do
                {
                    float _15555 = dot(_16885, _15498);
                    if (_15555 <= 0.0)
                    {
                        _17622 = 0.0;
                        break;
                    }
                    float _15562 = _16933 * _16933;
                    vec3 _15565 = cross(_16885, _15498);
                    float _15568 = _15555 * _15562;
                    float _15577 = _15562 / (dot(_15565, _15565) + (_15568 * _15568));
                    _17622 = min((_15577 * _15577) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _15615 = _6763 + (_7089 * pow(clamp(1.0 - max(dot(_15498, _16963), 0.0), 0.0, 1.0), 5.0));
                _17624 = (_15615 * min(_17622 * (0.5 / max(mix((2.0 * hp_copy_15478) * _15484, hp_copy_15478 + hp_copy_15484, hp_copy_16933 * hp_copy_16933), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _17623 = _15615;
            }
            else
            {
                _17624 = vec3(0.0);
                _17623 = _6763;
            }
            _17626 = (_17624 * frag_info.directional_light_color.xyz) * _15478;
            _17625 = (((((vec3(1.0) - _17623) * _7106) * _6615) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _15478;
            break;
        } while(false);
        _17710 = _17635 + ((_17625 + _17626) * _6754);
    }
    else
    {
        _17710 = _17635;
    }
    bool _7228 = _FogInfo.params0.y > 0.5;
    bool _7234 = false;
    if (_7228)
    {
        _7234 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7234 = _7228;
    }
    highp vec3 _17715 = vec3(0.0);
    if (_7234)
    {
        vec3 mp_copy_17711 = vec3(0.0);
        highp vec3 _17711 = vec3(0.0);
        if (_9235)
        {
            _17711 = -view_info.camera_forward.xyz;
        }
        else
        {
            _17711 = normalize(v_viewvector);
        }
        mp_copy_17711 = _17711;
        vec3 _7239 = _6997 * (-mp_copy_17711);
        vec3 _17712 = vec3(0.0);
        do
        {
            if (_11066)
            {
                vec2 _15737 = vec2(atan(_7239.z, _7239.x), asin(clamp(_7239.y, -1.0, 1.0)));
                highp vec2 hp_copy_15737 = _15737;
                _17712 = textureLod(prefiltered_radiance, (hp_copy_15737 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _15756 = vec2(atan(_7239.z, _7239.x), asin(clamp(_7239.y, -1.0, 1.0)));
            highp vec2 hp_copy_15756 = _15756;
            highp vec2 _15761 = (hp_copy_15756 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _15668 = clamp(_15761.y, 0.00390625, 0.99609375);
            float _15674 = floor(0.0);
            highp float _15693 = _15761.x;
            _17712 = mix(textureLod(prefiltered_radiance, vec2(_15693, (_15674 + _15668) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_15693, (min(_15674 + 1.0, 7.0) + _15668) * 0.125), 0.0).xyz, vec3(-_15674));
            break;
        } while(false);
        highp vec3 _17714 = vec3(0.0);
        if (_7020)
        {
            vec3 _17713 = vec3(0.0);
            do
            {
                if (_11066)
                {
                    vec2 _15866 = vec2(atan(_7239.z, _7239.x), asin(clamp(_7239.y, -1.0, 1.0)));
                    highp vec2 hp_copy_15866 = _15866;
                    _17713 = textureLod(prefiltered_radiance_b, (hp_copy_15866 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _15885 = vec2(atan(_7239.z, _7239.x), asin(clamp(_7239.y, -1.0, 1.0)));
                highp vec2 hp_copy_15885 = _15885;
                highp vec2 _15890 = (hp_copy_15885 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _15797 = clamp(_15890.y, 0.00390625, 0.99609375);
                float _15803 = floor(0.0);
                highp float _15822 = _15890.x;
                _17713 = mix(textureLod(prefiltered_radiance_b, vec2(_15822, (_15803 + _15797) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_15822, (min(_15803 + 1.0, 7.0) + _15797) * 0.125), 0.0).xyz, vec3(-_15803));
                break;
            } while(false);
            _17714 = mix(_17712, _17713, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _17714 = _17712;
        }
        _17715 = _17714 * frag_info.environment_intensity;
    }
    else
    {
        _17715 = _FogInfo.color.xyz;
    }
    highp vec4 _7263 = vec4(min((_17706 + (_17710 * mix(1.0, _17274, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _16908, vec3(65504.0)), 1.0) * _18429;
    highp vec4 _17730 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _17730 = _7263;
            break;
        }
        int _15934 = int(_FogInfo.params0.x + 0.5);
        if (_15934 == 0)
        {
            _17730 = _7263;
            break;
        }
        highp float _17717 = 0.0;
        if (_9235)
        {
            _17717 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _17717 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_17717 > _FogInfo.params1.w))
        {
            _17730 = _7263;
            break;
        }
        float _17721 = 0.0;
        if (_15934 == 1)
        {
            _17721 = clamp((_17717 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _17722 = 0.0;
            if (_15934 == 2)
            {
                highp float _17720 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _17718 = vec3(0.0);
                    if (_9235)
                    {
                        _17718 = v_position - (view_info.camera_forward.xyz * _17717);
                    }
                    else
                    {
                        _17718 = v_position + v_viewvector;
                    }
                    highp float _16015 = -_FogInfo.params2.y;
                    highp float _16022 = _FogInfo.params1.x * exp(_16015 * (_17718.y - _FogInfo.params2.x));
                    highp float _16039 = _FogInfo.params2.y * (v_position.y - _17718.y);
                    highp float _17719 = 0.0;
                    if (abs(_16039) > 0.00124999997206032276153564453125)
                    {
                        _17719 = (_16022 - (_FogInfo.params1.x * exp(_16015 * (v_position.y - _FogInfo.params2.x)))) / _16039;
                    }
                    else
                    {
                        _17719 = _16022;
                    }
                    _17720 = _17719 * max(_17717 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _17720 = _FogInfo.params1.x * max(_17717 - _FogInfo.params1.y, 0.0);
                }
                _17722 = 1.0 - exp(-_17720);
            }
            else
            {
                highp float _16077 = _FogInfo.params1.x * max(_17717 - _FogInfo.params1.y, 0.0);
                _17722 = 1.0 - exp((-_16077) * _16077);
            }
            _17721 = _17722;
        }
        highp float _16089 = min(_17721, _FogInfo.params0.z);
        if (_16089 <= 0.0)
        {
            _17730 = _7263;
            break;
        }
        highp vec3 _16102 = mix(_FogInfo.color.xyz, _17715, vec3(_FogInfo.params0.w));
        bool _16105 = _FogInfo.sun.w > 0.5;
        bool _16111 = false;
        if (_16105)
        {
            _16111 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _16111 = _16105;
        }
        vec3 _17726 = vec3(0.0);
        if (_16111)
        {
            vec3 mp_copy_17723 = vec3(0.0);
            highp vec3 _17723 = vec3(0.0);
            if (_9235)
            {
                _17723 = -view_info.camera_forward.xyz;
            }
            else
            {
                _17723 = normalize(v_viewvector);
            }
            mp_copy_17723 = _17723;
            highp float _16127 = pow(max(dot(-mp_copy_17723, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_16127 = _16127;
            _17726 = _16102 + ((_FogInfo.sun.xyz * mp_copy_16127) * _FogInfo.params2.z);
        }
        else
        {
            _17726 = _16102;
        }
        highp float _16140 = _7263.w;
        float mp_copy_16140 = _16140;
        _17730 = vec4(mix(_7263.xyz, _17726 * mp_copy_16140, vec3(_16089)), _16140);
        break;
    } while(false);
    vec4 _17732 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _17732 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _17732 = _17730;
        break;
    } while(false);
    frag_color = _17732;
    float _17733 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _17733 = 1.0;
    }
    else
    {
        _17733 = abs(frag_info.fade);
    }
    frag_color *= _17733;
}

