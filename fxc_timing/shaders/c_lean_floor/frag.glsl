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
uniform highp sampler2D punctual_lights;

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
    highp float _3279 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_3279 = _3279;
    vec3 _3283 = normalize(v_normal) * mp_copy_3279;
    vec4 _3325 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _3328 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _6979 = vec2(0.0);
    if (_3328)
    {
        highp vec2 _6978 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _6978 = v_texture_coords_1;
        }
        else
        {
            _6978 = v_texture_coords;
        }
        highp vec2 _3531 = _6978 * texture_transforms.base_color_transform.zw;
        highp float _3537 = _3531.x;
        highp float _3542 = _3531.y;
        _6979 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _3537) + (texture_transforms.base_color_rotation.y * _3542), ((-texture_transforms.base_color_rotation.y) * _3537) + (texture_transforms.base_color_rotation.x * _3542));
    }
    else
    {
        _6979 = v_texture_coords;
    }
    vec4 _3342 = texture(base_color_texture, _6979);
    vec3 _3344 = _3342.xyz;
    float _7298 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_3342.w * _3325.w) * frag_info.color.w);
    vec3 _6994 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _6982 = vec2(0.0);
        if (_3328)
        {
            highp vec2 _6981 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _6981 = v_texture_coords_1;
            }
            else
            {
                _6981 = v_texture_coords;
            }
            highp vec2 _3626 = _6981 * texture_transforms.normal_transform.zw;
            highp float _3632 = _3626.x;
            highp float _3637 = _3626.y;
            _6982 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _3632) + (texture_transforms.normal_rotation.y * _3637), ((-texture_transforms.normal_rotation.y) * _3632) + (texture_transforms.normal_rotation.x * _3637));
        }
        else
        {
            _6982 = v_texture_coords;
        }
        vec3 _3682 = ((texture(normal_texture, _6982).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _3686 = _3682.xy * vec2(frag_info.normal_scale);
        vec3 _6826 = _3682;
        _6826.x = _3686.x;
        _6826.y = _3686.y;
        highp vec3 _3692 = -v_viewvector;
        highp vec3 _3782 = dFdx(_3692);
        highp vec3 _3784 = dFdy(_3692);
        highp vec2 _3786 = dFdx(_6982);
        highp vec2 _3788 = dFdy(_6982);
        bvec2 _7300 = bvec2(length(_3786) == 0.0);
        highp vec2 _7301 = vec2(_7300.x ? vec2(1.0, 0.0).x : _3786.x, _7300.y ? vec2(1.0, 0.0).y : _3786.y);
        bvec2 _7302 = bvec2(length(_3788) == 0.0);
        highp vec2 _7303 = vec2(_7302.x ? vec2(0.0, 1.0).x : _3788.x, _7302.y ? vec2(0.0, 1.0).y : _3788.y);
        highp vec3 _3801 = cross(_3784, _3283);
        highp vec3 _3804 = cross(_3283, _3782);
        highp float _3829 = (dot(cross(_3782, _3784), _3283) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _3832 = ((_3801 * _7301.x) + (_3804 * _7303.x)) * _3829;
        highp float _6989 = 0.0;
        if (gl_FrontFacing)
        {
            _6989 = -_3829;
        }
        else
        {
            _6989 = _3829;
        }
        highp vec3 _3842 = ((_3801 * _7301.y) + (_3804 * _7303.y)) * _6989;
        highp float _3851 = inversesqrt(max(max(dot(_3832, _3832), dot(_3842, _3842)), 9.9999996826552253889678874634872e-21));
        vec3 _3723 = v_tangent.xyz - (_3283 * dot(_3283, v_tangent.xyz));
        highp float _3726 = dot(_3723, _3723);
        bool _3728 = _3726 > 1.0000000133514319600180897396058e-10;
        bool _3735 = false;
        if (_3728)
        {
            _3735 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _3735 = _3728;
        }
        mat3 _6992 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_3735)
        {
            highp vec3 _3740 = _3723 * inversesqrt(_3726);
            _6992 = mat3(_3740, normalize(cross(_3283, _3740)) * sign(v_tangent.w), _3283);
        }
        else
        {
            _6992 = mat3(_3832 * _3851, _3842 * _3851, _3283);
        }
        _6994 = normalize(_6992 * _6826);
    }
    else
    {
        _6994 = _3283;
    }
    highp vec2 _6996 = vec2(0.0);
    if (_3328)
    {
        highp vec2 _6995 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _6995 = v_texture_coords_1;
        }
        else
        {
            _6995 = v_texture_coords;
        }
        highp vec2 _3919 = _6995 * texture_transforms.metallic_roughness_transform.zw;
        highp float _3925 = _3919.x;
        highp float _3930 = _3919.y;
        _6996 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _3925) + (texture_transforms.metallic_roughness_rotation.y * _3930), ((-texture_transforms.metallic_roughness_rotation.y) * _3925) + (texture_transforms.metallic_roughness_rotation.x * _3930));
    }
    else
    {
        _6996 = v_texture_coords;
    }
    vec4 _3411 = texture(metallic_roughness_texture, _6996);
    float _3417 = clamp(_3411.z * frag_info.metallic_factor, 0.0, 1.0);
    float _3424 = clamp(_3411.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _6998 = vec2(0.0);
    if (_3328)
    {
        highp vec2 _6997 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _6997 = v_texture_coords_1;
        }
        else
        {
            _6997 = v_texture_coords;
        }
        highp vec2 _3990 = _6997 * texture_transforms.occlusion_transform.zw;
        highp float _3996 = _3990.x;
        highp float _4001 = _3990.y;
        _6998 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _3996) + (texture_transforms.occlusion_rotation.y * _4001), ((-texture_transforms.occlusion_rotation.y) * _3996) + (texture_transforms.occlusion_rotation.x * _4001));
    }
    else
    {
        _6998 = v_texture_coords;
    }
    float _6999 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _6999 = texture(occlusion_texture, _6998).x;
    }
    else
    {
        _6999 = 1.0;
    }
    float _3451 = 1.0 - ((1.0 - _6999) * frag_info.occlusion_strength);
    highp vec2 _7001 = vec2(0.0);
    if (_3328)
    {
        highp vec2 _7000 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _7000 = v_texture_coords_1;
        }
        else
        {
            _7000 = v_texture_coords;
        }
        highp vec2 _4061 = _7000 * texture_transforms.emissive_transform.zw;
        highp float _4067 = _4061.x;
        highp float _4072 = _4061.y;
        _7001 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _4067) + (texture_transforms.emissive_rotation.y * _4072), ((-texture_transforms.emissive_rotation.y) * _4067) + (texture_transforms.emissive_rotation.x * _4072));
    }
    else
    {
        _7001 = v_texture_coords;
    }
    vec3 _3470 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _7017 = vec3(0.0);
    if (dot(abs(_3470), vec3(1.0)) > 0.0)
    {
        vec3 _3479 = texture(emissive_texture, _7001).xyz;
        _7017 = mix(_3479 * vec3(0.077399380505084991455078125), pow((_3479 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3479)) * _3470;
    }
    else
    {
        _7017 = vec3(0.0);
    }
    highp float hp_copy_7042 = 0.0;
    vec3 _4198 = vec4((mix(_3344 * vec3(0.077399380505084991455078125), pow((_3344 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _3344)) * _3325.xyz) * frag_info.color.xyz, _7298).xyz;
    vec3 _4510 = dFdx(_6994);
    vec3 _4512 = dFdy(_6994);
    float _7042 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _7042 = sqrt(clamp((_3424 * _3424) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_4510, _4510), dot(_4512, _4512))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _7042 = _3424;
    }
    hp_copy_7042 = _7042;
    float _7067 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _7067 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _7067 = _3451;
    }
    bool _4223 = frag_info.has_directional_light > 0.5;
    float _7043 = 0.0;
    vec3 _7079 = vec3(0.0);
    if (_4223)
    {
        highp vec3 _4229 = -normalize(frag_info.directional_light_direction.xyz);
        _7079 = _4229;
        _7043 = dot(_3283, _4229);
    }
    else
    {
        _7079 = vec3(0.0);
        _7043 = 0.0;
    }
    float _4236 = clamp(_7043 * 6.666666507720947265625, 0.0, 1.0);
    bool _4245 = false;
    if (_4223)
    {
        _4245 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _4245 = _4223;
    }
    float _7052 = 0.0;
    if (_4245 && (_4236 > 0.0))
    {
        int _4591 = int(frag_info.shadow_cascade_count);
        float _4786 = max(dot(_3283, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _4789 = _4786 * _4786;
        highp vec3 _4809 = v_position + (_3283 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _4789, 0.0)) / _4789, 8.0))));
        highp float _4597 = frag_info.directional_light_color.w * 0.5;
        float _4599 = frag_info.dielectric_f0.w;
        highp float hp_copy_4599 = _4599;
        float _7044 = 0.0;
        if (_4599 > 0.0)
        {
            _7044 = smoothstep(_4599 - max(frag_info.shadow_fade, hp_copy_4599 * 0.100000001490116119384765625), _4599, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _7044 = 0.0;
        }
        float _7046 = 0.0;
        float _7048 = 0.0;
        if (_7044 < 1.0)
        {
            float _7047 = 0.0;
            float _7049 = 0.0;
            _7049 = 0.0;
            _7047 = 0.0;
            float _7199 = 0.0;
            float _7202 = 0.0;
            for (int _7045 = 0; _7045 < _4591; _7049 = _7202, _7047 = _7199, _7045++)
            {
                if (_7049 < 1.0)
                {
                    highp vec4 _4631 = vec4(_4809, 1.0);
                    highp vec4 _7105 = vec4(0.0);
                    highp float _7108 = 0.0;
                    if (_7045 == 0)
                    {
                        _7108 = frag_info.cascade_box_sizes.x;
                        _7105 = frag_info.light_space_matrix[0] * _4631;
                    }
                    else
                    {
                        highp vec4 _7106 = vec4(0.0);
                        highp float _7109 = 0.0;
                        if (_7045 == 1)
                        {
                            _7109 = frag_info.cascade_box_sizes.y;
                            _7106 = frag_info.light_space_matrix[1] * _4631;
                        }
                        else
                        {
                            highp vec4 _7107 = vec4(0.0);
                            highp float _7110 = 0.0;
                            if (_7045 == 2)
                            {
                                _7110 = frag_info.cascade_box_sizes.z;
                                _7107 = frag_info.light_space_matrix[2] * _4631;
                            }
                            else
                            {
                                _7110 = frag_info.cascade_box_sizes.w;
                                _7107 = frag_info.light_space_matrix[3] * _4631;
                            }
                            _7109 = _7110;
                            _7106 = _7107;
                        }
                        _7108 = _7109;
                        _7105 = _7106;
                    }
                    highp vec3 _4676 = _7105.xyz / vec3(_7105.w);
                    highp vec2 _4679 = _4676.xy * 0.5;
                    highp vec2 _4681 = _4679 + vec2(0.5);
                    highp float _4688 = max(frag_info.shadow_softness / _7108, frag_info.shadow_texel_size);
                    highp float _4690 = _4681.x;
                    bool _4692 = _4690 < _4688;
                    bool _4701 = false;
                    if (!_4692)
                    {
                        _4701 = _4690 > (1.0 - _4688);
                    }
                    else
                    {
                        _4701 = _4692;
                    }
                    bool _4709 = false;
                    if (!_4701)
                    {
                        _4709 = _4681.y < _4688;
                    }
                    else
                    {
                        _4709 = _4701;
                    }
                    bool _4718 = false;
                    if (!_4709)
                    {
                        _4718 = _4681.y > (1.0 - _4688);
                    }
                    else
                    {
                        _4718 = _4709;
                    }
                    bool _4725 = false;
                    if (!_4718)
                    {
                        _4725 = _4676.z < 0.0;
                    }
                    else
                    {
                        _4725 = _4718;
                    }
                    bool _4732 = false;
                    if (!_4725)
                    {
                        _4732 = _4676.z > 1.0;
                    }
                    else
                    {
                        _4732 = _4725;
                    }
                    float _7200 = 0.0;
                    float _7203 = 0.0;
                    if (!_4732)
                    {
                        highp vec2 _4825 = vec2(_4688);
                        highp vec2 _4830 = vec2(_4688 + max(_4597, 9.9999997473787516355514526367188e-05));
                        highp vec2 _4838 = vec2(0.5) - _4679;
                        highp vec2 _4840 = smoothstep(_4825, _4830, _4681) * smoothstep(_4825, _4830, _4838);
                        float _7111 = 0.0;
                        if (_4597 > 0.0)
                        {
                            _7111 = _4840.x * _4840.y;
                        }
                        else
                        {
                            _7111 = 1.0;
                        }
                        float _4741 = min(_7111, 1.0 - _7049);
                        float _7201 = 0.0;
                        float _7204 = 0.0;
                        if (_4741 > 0.0)
                        {
                            highp float _4936 = _4676.z - (frag_info.shadow_bias / (7.0 * _7108));
                            highp float _4942 = 1.0 / (float(_4591) + frag_info.spot_shadow_params.x);
                            highp float _4944 = frag_info.directional_light_direction.w;
                            float mp_copy_4944 = _4944;
                            float _4950 = step(0.5, mp_copy_4944) * (1.0 - step(1.5, mp_copy_4944));
                            float _7136 = 0.0;
                            float _7137 = 0.0;
                            if (_4950 < 0.5)
                            {
                                highp float _4961 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_4961 = _4961;
                                _7137 = sin(mp_copy_4961);
                                _7136 = cos(mp_copy_4961);
                            }
                            else
                            {
                                _7137 = 0.0;
                                _7136 = 1.0;
                            }
                            bool _7138 = false;
                            float _7158 = 0.0;
                            if ((_4944 < 1.5) || (_4944 > 2.5))
                            {
                                highp vec2 _5142 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _5146 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _5147 = clamp(_4681, _5142, _5146);
                                highp float _5149 = float(_7045);
                                highp float _5156 = _5147.y;
                                highp vec2 _5157 = vec2((_5149 + _5147.x) * _4942, _5156);
                                _5157.y = 1.0 - _5156;
                                highp float _5169 = float(_4936 <= textureLod(shadow_map, _5157, 0.0).x);
                                float mp_copy_5169 = _5169;
                                float _5179 = (-1.0) * _7136;
                                float _5183 = (-1.0) * _7137;
                                highp vec2 _5207 = clamp(_4681 + (vec2(_5179 - _5183, _5183 + _5179) * _4688), _5142, _5146);
                                highp float _5216 = _5207.y;
                                highp vec2 _5217 = vec2((_5149 + _5207.x) * _4942, _5216);
                                _5217.y = 1.0 - _5216;
                                highp float _5229 = float(_4936 <= textureLod(shadow_map, _5217, 0.0).x);
                                float mp_copy_5229 = _5229;
                                highp vec2 _5267 = clamp(_4681 + (vec2(_7136 - _5183, _7137 + _5179) * _4688), _5142, _5146);
                                highp float _5276 = _5267.y;
                                highp vec2 _5277 = vec2((_5149 + _5267.x) * _4942, _5276);
                                _5277.y = 1.0 - _5276;
                                highp float _5289 = float(_4936 <= textureLod(shadow_map, _5277, 0.0).x);
                                float mp_copy_5289 = _5289;
                                highp vec2 _5327 = clamp(_4681 + (vec2(_5179 - _7137, _5183 + _7136) * _4688), _5142, _5146);
                                highp float _5336 = _5327.y;
                                highp vec2 _5337 = vec2((_5149 + _5327.x) * _4942, _5336);
                                _5337.y = 1.0 - _5336;
                                highp float _5349 = float(_4936 <= textureLod(shadow_map, _5337, 0.0).x);
                                float mp_copy_5349 = _5349;
                                highp vec2 _5387 = clamp(_4681 + (vec2(_7136 - _7137, _7137 + _7136) * _4688), _5142, _5146);
                                highp float _5396 = _5387.y;
                                highp vec2 _5397 = vec2((_5149 + _5387.x) * _4942, _5396);
                                _5397.y = 1.0 - _5396;
                                highp float _5409 = float(_4936 <= textureLod(shadow_map, _5397, 0.0).x);
                                float mp_copy_5409 = _5409;
                                float _5024 = (((mp_copy_5169 + mp_copy_5229) + mp_copy_5289) + mp_copy_5349) + mp_copy_5409;
                                _7158 = _5024 * 0.20000000298023223876953125;
                                _7138 = (_5024 < 0.5) || (_5024 > 4.5);
                            }
                            else
                            {
                                _7158 = 0.0;
                                _7138 = false;
                            }
                            float _7157 = 0.0;
                            if (_7138)
                            {
                                _7157 = _7158;
                            }
                            else
                            {
                                int _5037 = (_4950 > 0.5) ? 17 : 16;
                                float _7153 = 0.0;
                                _7153 = 0.0;
                                float _5065 = 0.0;
                                for (int _7139 = 0; _7139 < 17; _7153 = _5065, _7139++)
                                {
                                    if (_7139 >= _5037)
                                    {
                                        break;
                                    }
                                    vec2 _7140 = vec2(0.0);
                                    do
                                    {
                                        if (_7139 == 0)
                                        {
                                            _7140 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_7139 == 1)
                                        {
                                            _7140 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_7139 == 2)
                                        {
                                            _7140 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_7139 == 3)
                                        {
                                            _7140 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_7139 == 4)
                                        {
                                            _7140 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_7139 == 5)
                                        {
                                            _7140 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_7139 == 6)
                                        {
                                            _7140 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_7139 == 7)
                                        {
                                            _7140 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_7139 == 8)
                                        {
                                            _7140 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_7139 == 9)
                                        {
                                            _7140 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_7139 == 10)
                                        {
                                            _7140 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_7139 == 11)
                                        {
                                            _7140 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_7139 == 12)
                                        {
                                            _7140 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_7139 == 13)
                                        {
                                            _7140 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_7139 == 14)
                                        {
                                            _7140 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_7139 == 15)
                                        {
                                            _7140 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _7140 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _7142 = vec2(0.0);
                                    do
                                    {
                                        if (_7139 < 3)
                                        {
                                            _7142 = vec2(float(_7139) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_7139 < 6)
                                        {
                                            _7142 = vec2((float(_7139 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_7139 < 11)
                                        {
                                            _7142 = vec2((float(_7139 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_7139 < 14)
                                        {
                                            _7142 = vec2((float(_7139 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _7142 = vec2(float(_7139 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _5054 = mix(_7140, _7142, vec2(_4950));
                                    float _5548 = _5054.x;
                                    float _5552 = _5054.y;
                                    highp vec2 _5578 = clamp(_4681 + (vec2((_5548 * _7136) - (_5552 * _7137), (_5548 * _7137) + (_5552 * _7136)) * _4688), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _5587 = _5578.y;
                                    highp vec2 _5588 = vec2((float(_7045) + _5578.x) * _4942, _5587);
                                    _5588.y = 1.0 - _5587;
                                    highp float _5600 = float(_4936 <= textureLod(shadow_map, _5588, 0.0).x);
                                    float mp_copy_5600 = _5600;
                                    _5065 = _7153 + mp_copy_5600;
                                }
                                _7157 = _7153 / float(_5037);
                            }
                            bool _5079 = _7045 == (_4591 - 1);
                            bool _5085 = false;
                            if (_5079)
                            {
                                _5085 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _5085 = _5079;
                            }
                            float _7159 = 0.0;
                            if (_5085)
                            {
                                highp vec2 _5092 = vec2(frag_info.shadow_fade / _7108);
                                highp vec2 _5100 = smoothstep(vec2(0.0), _5092, _4681) * smoothstep(vec2(0.0), _5092, _4838);
                                _7159 = mix(1.0, _7157, _5100.x * _5100.y);
                            }
                            else
                            {
                                _7159 = _7157;
                            }
                            _7204 = _7049 + _4741;
                            _7201 = _7047 + (_4741 * _7159);
                        }
                        else
                        {
                            _7204 = _7049;
                            _7201 = _7047;
                        }
                        _7203 = _7204;
                        _7200 = _7201;
                    }
                    else
                    {
                        _7203 = _7049;
                        _7200 = _7047;
                    }
                    _7202 = _7203;
                    _7199 = _7200;
                }
                else
                {
                    _7202 = _7049;
                    _7199 = _7047;
                }
            }
            _7048 = _7049;
            _7046 = _7047;
        }
        else
        {
            _7048 = 0.0;
            _7046 = 0.0;
        }
        _7052 = mix(_7046 + (1.0 - _7048), 1.0, _7044);
    }
    else
    {
        _7052 = 1.0;
    }
    vec3 mp_copy_7053 = vec3(0.0);
    float _4258 = _4236 * _7052;
    highp vec3 _7053 = vec3(0.0);
    if (view_info.camera_forward.w > 0.5)
    {
        _7053 = -view_info.camera_forward.xyz;
    }
    else
    {
        _7053 = normalize(v_viewvector);
    }
    bool _6044 = false;
    highp vec3 hp_copy_7054 = vec3(0.0);
    mp_copy_7053 = _7053;
    vec3 _4267 = mix(frag_info.dielectric_f0.xyz, _4198, vec3(_3417));
    float _4271 = max(dot(_6994, _7053), 0.0);
    float _4275 = max(dot(_3283, _7053), 0.0);
    mat3 _4301 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _4309 = _4301 * vec3(_6994.x, _6994.y, _6994.z);
    vec3 _4312 = _4301 * reflect(-mp_copy_7053, _6994);
    float _5863 = _4309.y;
    float _5870 = _4309.z;
    float _5877 = _4309.x;
    float _5885 = 1.09254801273345947265625 * _5877;
    vec3 _4315 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _5863))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _5870))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _5877))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_5885 * _5863))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _5863) * _5870))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _5870) * _5870) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_5885 * _5870))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_5877 * _5877) - (_5863 * _5863)))), vec3(0.0));
    highp vec3 hp_copy_4315 = _4315;
    vec3 _7054 = vec3(0.0);
    do
    {
        _6044 = radiance_layout_info.mip_layout > 0.5;
        if (_6044)
        {
            vec2 _6123 = vec2(atan(_4312.z, _4312.x), asin(clamp(_4312.y, -1.0, 1.0)));
            highp vec2 hp_copy_6123 = _6123;
            _7054 = textureLod(prefiltered_radiance, (hp_copy_6123 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_7042, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _6142 = vec2(atan(_4312.z, _4312.x), asin(clamp(_4312.y, -1.0, 1.0)));
        highp vec2 hp_copy_6142 = _6142;
        highp vec2 _6147 = (hp_copy_6142 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _6054 = clamp(_6147.y, 0.00390625, 0.99609375);
        float _6058 = clamp(_7042, 0.0, 1.0) * 7.0;
        float _6060 = floor(_6058);
        highp float _6079 = _6147.x;
        _7054 = mix(textureLod(prefiltered_radiance, vec2(_6079, (_6060 + _6054) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_6079, (min(_6060 + 1.0, 7.0) + _6054) * 0.125), 0.0).xyz, vec3(_6058 - _6060));
        break;
    } while(false);
    hp_copy_7054 = _7054;
    highp vec3 _7060 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_7055 = vec3(0.0);
        vec3 _7055 = vec3(0.0);
        do
        {
            if (_6044)
            {
                vec2 _6252 = vec2(atan(_4312.z, _4312.x), asin(clamp(_4312.y, -1.0, 1.0)));
                highp vec2 hp_copy_6252 = _6252;
                _7055 = textureLod(prefiltered_radiance_b, (hp_copy_6252 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_7042, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _6271 = vec2(atan(_4312.z, _4312.x), asin(clamp(_4312.y, -1.0, 1.0)));
            highp vec2 hp_copy_6271 = _6271;
            highp vec2 _6276 = (hp_copy_6271 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _6183 = clamp(_6276.y, 0.00390625, 0.99609375);
            float _6187 = clamp(_7042, 0.0, 1.0) * 7.0;
            float _6189 = floor(_6187);
            highp float _6208 = _6276.x;
            _7055 = mix(textureLod(prefiltered_radiance_b, vec2(_6208, (_6189 + _6183) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_6208, (min(_6189 + 1.0, 7.0) + _6183) * 0.125), 0.0).xyz, vec3(_6187 - _6189));
            break;
        } while(false);
        hp_copy_7055 = _7055;
        _7060 = hp_copy_7054 + hp_copy_7055;
    }
    else
    {
        _7060 = _7054;
    }
    float _4330 = frag_info.environment_intensity;
    highp float hp_copy_4330 = _4330;
    vec2 _4343 = clamp(vec2(_4275, _7042), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _4345 = texture(brdf_lut, vec2(_4343.x * 0.3333333432674407958984375, _4343.y));
    float _4349 = _4345.x;
    float _4352 = _4345.y;
    vec3 _4354 = ((_4267 + ((max(vec3(1.0 - _7042), _4267) - _4267) * pow(clamp(1.0 - _4275, 0.0, 1.0), 5.0))) * _4349) + vec3(_4352);
    float _4360 = 1.0 - (_4349 + _4352);
    vec3 _4364 = vec3(1.0) - _4267;
    vec3 _4367 = _4267 + (_4364 * vec3(0.0476190485060214996337890625));
    vec3 _4378 = ((_4354 * _4360) * _4367) / (vec3(1.0) - (_4367 * _4360));
    float _4381 = 1.0 - _3417;
    float _7072 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _7072 = clamp((pow(_4271 + _7067, exp2(((-16.0) * _7042) - 1.0)) - 1.0) + _7067, 0.0, 1.0);
    }
    else
    {
        _7072 = _7067;
    }
    highp vec3 _7101 = vec3(0.0);
    if (_4223)
    {
        highp vec3 _7087 = vec3(0.0);
        highp vec3 _7088 = vec3(0.0);
        do
        {
            float _6365 = max(dot(_6994, _7079), 0.0);
            highp float hp_copy_6365 = _6365;
            if (_6365 <= 0.0)
            {
                _7088 = vec3(0.0);
                _7087 = vec3(0.0);
                break;
            }
            float _6371 = max(_4271, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_6371 = _6371;
            vec3 _6374 = _7079 + mp_copy_7053;
            float _6377 = dot(_6374, _6374);
            vec3 _7085 = vec3(0.0);
            vec3 _7086 = vec3(0.0);
            if (_6377 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _6385 = _6374 * inversesqrt(_6377);
                float _7084 = 0.0;
                do
                {
                    float _6442 = dot(_6994, _6385);
                    if (_6442 <= 0.0)
                    {
                        _7084 = 0.0;
                        break;
                    }
                    float _6449 = _7042 * _7042;
                    vec3 _6452 = cross(_6994, _6385);
                    float _6455 = _6442 * _6449;
                    float _6464 = _6449 / (dot(_6452, _6452) + (_6455 * _6455));
                    _7084 = min((_6464 * _6464) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _6502 = _4267 + (_4364 * pow(clamp(1.0 - max(dot(_6385, _7053), 0.0), 0.0, 1.0), 5.0));
                _7086 = (_6502 * min(_7084 * (0.5 / max(mix((2.0 * hp_copy_6365) * _6371, hp_copy_6365 + hp_copy_6371, hp_copy_7042 * hp_copy_7042), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _7085 = _6502;
            }
            else
            {
                _7086 = vec3(0.0);
                _7085 = _4267;
            }
            _7088 = (_7086 * frag_info.directional_light_color.xyz) * _6365;
            _7087 = (((((vec3(1.0) - _7085) * _4381) * _4198) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _6365;
            break;
        } while(false);
        _7101 = (_7087 + _7088) * _4258;
    }
    else
    {
        _7101 = vec3(0.0);
    }
    vec4 _7103 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _7103 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _7103 = vec4(min(((((((_4378 + ((_4198 * _4381) * ((vec3(1.0) - _4354) - _4378))) * (hp_copy_4315 * hp_copy_4330)) * vec3(_3451)) + (((_4354 * (_7060 * _4330)) * 1.0) * _7072)) * mix(1.0, _4258, frag_info.radiance_blend.y)) + (_7101 * mix(1.0, _7067, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7017, vec3(65504.0)), 1.0) * _7298;
        break;
    } while(false);
    frag_color = _7103;
    float _7104 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _7104 = 1.0;
    }
    else
    {
        _7104 = abs(frag_info.fade);
    }
    frag_color *= _7104;
}

