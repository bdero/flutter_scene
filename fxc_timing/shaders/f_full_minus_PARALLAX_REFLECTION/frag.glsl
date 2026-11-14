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
    highp float _5952 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_5952 = _5952;
    vec3 _5956 = normalize(v_normal) * mp_copy_5952;
    vec4 _5998 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _6001 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _18019 = vec2(0.0);
    if (_6001)
    {
        highp vec2 _18018 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _18018 = v_texture_coords_1;
        }
        else
        {
            _18018 = v_texture_coords;
        }
        highp vec2 _6201 = _18018 * texture_transforms.base_color_transform.zw;
        highp float _6207 = _6201.x;
        highp float _6212 = _6201.y;
        _18019 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6207) + (texture_transforms.base_color_rotation.y * _6212), ((-texture_transforms.base_color_rotation.y) * _6207) + (texture_transforms.base_color_rotation.x * _6212));
    }
    else
    {
        _18019 = v_texture_coords;
    }
    vec4 _6015 = texture(base_color_texture, _18019);
    vec3 _6017 = _6015.xyz;
    float _19659 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_6015.w * _5998.w) * frag_info.color.w);
    vec3 _18034 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _18022 = vec2(0.0);
        if (_6001)
        {
            highp vec2 _18021 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _18021 = v_texture_coords_1;
            }
            else
            {
                _18021 = v_texture_coords;
            }
            highp vec2 _6296 = _18021 * texture_transforms.normal_transform.zw;
            highp float _6302 = _6296.x;
            highp float _6307 = _6296.y;
            _18022 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6302) + (texture_transforms.normal_rotation.y * _6307), ((-texture_transforms.normal_rotation.y) * _6302) + (texture_transforms.normal_rotation.x * _6307));
        }
        else
        {
            _18022 = v_texture_coords;
        }
        vec3 _6355 = ((texture(normal_texture, _18022).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6359 = _6355.xy * vec2(frag_info.normal_scale);
        vec3 _17456 = _6355;
        _17456.x = _6359.x;
        _17456.y = _6359.y;
        highp vec3 _6365 = -v_viewvector;
        highp vec3 _6455 = dFdx(_6365);
        highp vec3 _6457 = dFdy(_6365);
        highp vec2 _6459 = dFdx(_18022);
        highp vec2 _6461 = dFdy(_18022);
        bvec2 _19661 = bvec2(length(_6459) == 0.0);
        highp vec2 _19662 = vec2(_19661.x ? vec2(1.0, 0.0).x : _6459.x, _19661.y ? vec2(1.0, 0.0).y : _6459.y);
        bvec2 _19663 = bvec2(length(_6461) == 0.0);
        highp vec2 _19664 = vec2(_19663.x ? vec2(0.0, 1.0).x : _6461.x, _19663.y ? vec2(0.0, 1.0).y : _6461.y);
        highp vec3 _6474 = cross(_6457, _5956);
        highp vec3 _6477 = cross(_5956, _6455);
        highp float _6502 = (dot(cross(_6455, _6457), _5956) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6505 = ((_6474 * _19662.x) + (_6477 * _19664.x)) * _6502;
        highp float _18029 = 0.0;
        if (gl_FrontFacing)
        {
            _18029 = -_6502;
        }
        else
        {
            _18029 = _6502;
        }
        highp vec3 _6515 = ((_6474 * _19662.y) + (_6477 * _19664.y)) * _18029;
        highp float _6524 = inversesqrt(max(max(dot(_6505, _6505), dot(_6515, _6515)), 9.9999996826552253889678874634872e-21));
        vec3 _6396 = v_tangent.xyz - (_5956 * dot(_5956, v_tangent.xyz));
        highp float _6399 = dot(_6396, _6396);
        bool _6401 = _6399 > 1.0000000133514319600180897396058e-10;
        bool _6408 = false;
        if (_6401)
        {
            _6408 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6408 = _6401;
        }
        mat3 _18032 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6408)
        {
            highp vec3 _6413 = _6396 * inversesqrt(_6399);
            _18032 = mat3(_6413, normalize(cross(_5956, _6413)) * sign(v_tangent.w), _5956);
        }
        else
        {
            _18032 = mat3(_6505 * _6524, _6515 * _6524, _5956);
        }
        _18034 = normalize(_18032 * _17456);
    }
    else
    {
        _18034 = _5956;
    }
    highp vec2 _18036 = vec2(0.0);
    if (_6001)
    {
        highp vec2 _18035 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _18035 = v_texture_coords_1;
        }
        else
        {
            _18035 = v_texture_coords;
        }
        highp vec2 _6589 = _18035 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6595 = _6589.x;
        highp float _6600 = _6589.y;
        _18036 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6595) + (texture_transforms.metallic_roughness_rotation.y * _6600), ((-texture_transforms.metallic_roughness_rotation.y) * _6595) + (texture_transforms.metallic_roughness_rotation.x * _6600));
    }
    else
    {
        _18036 = v_texture_coords;
    }
    vec4 _6084 = texture(metallic_roughness_texture, _18036);
    float _6090 = clamp(_6084.z * frag_info.metallic_factor, 0.0, 1.0);
    float _6097 = clamp(_6084.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _18038 = vec2(0.0);
    if (_6001)
    {
        highp vec2 _18037 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _18037 = v_texture_coords_1;
        }
        else
        {
            _18037 = v_texture_coords;
        }
        highp vec2 _6660 = _18037 * texture_transforms.occlusion_transform.zw;
        highp float _6666 = _6660.x;
        highp float _6671 = _6660.y;
        _18038 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6666) + (texture_transforms.occlusion_rotation.y * _6671), ((-texture_transforms.occlusion_rotation.y) * _6666) + (texture_transforms.occlusion_rotation.x * _6671));
    }
    else
    {
        _18038 = v_texture_coords;
    }
    float _18039 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _18039 = texture(occlusion_texture, _18038).x;
    }
    else
    {
        _18039 = 1.0;
    }
    float _6124 = 1.0 - ((1.0 - _18039) * frag_info.occlusion_strength);
    highp vec2 _18041 = vec2(0.0);
    if (_6001)
    {
        highp vec2 _18040 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _18040 = v_texture_coords_1;
        }
        else
        {
            _18040 = v_texture_coords;
        }
        highp vec2 _6731 = _18040 * texture_transforms.emissive_transform.zw;
        highp float _6737 = _6731.x;
        highp float _6742 = _6731.y;
        _18041 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6737) + (texture_transforms.emissive_rotation.y * _6742), ((-texture_transforms.emissive_rotation.y) * _6737) + (texture_transforms.emissive_rotation.x * _6742));
    }
    else
    {
        _18041 = v_texture_coords;
    }
    vec3 _6143 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _18057 = vec3(0.0);
    if (dot(abs(_6143), vec3(1.0)) > 0.0)
    {
        vec3 _6152 = texture(emissive_texture, _18041).xyz;
        _18057 = mix(_6152 * vec3(0.077399380505084991455078125), pow((_6152 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6152)) * _6143;
    }
    else
    {
        _18057 = vec3(0.0);
    }
    highp float hp_copy_18082 = 0.0;
    vec3 _6990 = vec4((mix(_6017 * vec3(0.077399380505084991455078125), pow((_6017 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6017)) * _5998.xyz) * frag_info.color.xyz, _19659).xyz;
    vec3 _7813 = dFdx(_18034);
    vec3 _7815 = dFdy(_18034);
    float _18082 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _18082 = sqrt(clamp((_6097 * _6097) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7813, _7813), dot(_7815, _7815))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _18082 = _6097;
    }
    hp_copy_18082 = _18082;
    vec4 _18107 = vec4(0.0);
    float _18125 = 0.0;
    vec3 _18140 = vec3(0.0);
    float _18420 = 0.0;
    vec3 _18557 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _7017 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _18083 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _18083 = _7017.w;
        }
        else
        {
            _18083 = _7017.x;
        }
        float _7030 = min(_6124, _18083);
        bool _7033 = frag_info.ssao_lighting.z > 0.5;
        bool _7039 = false;
        if (_7033)
        {
            _7039 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _7039 = _7033;
        }
        vec3 _18141 = vec3(0.0);
        if (_7039)
        {
            vec2 _7853 = (_7017.zw * 2.0) - vec2(1.0);
            float _7855 = _7853.x;
            float _7857 = _7853.y;
            float _7865 = (1.0 - abs(_7855)) - abs(_7857);
            vec3 _7866 = vec3(_7855, _7857, _7865);
            vec3 _18086 = vec3(0.0);
            if (_7865 < 0.0)
            {
                vec2 _7879 = (vec2(1.0) - abs(_7866.yx)) * vec2((_7855 >= 0.0) ? 1.0 : (-1.0), (_7857 >= 0.0) ? 1.0 : (-1.0));
                vec3 _17505 = _7866;
                _17505.x = _7879.x;
                _17505.y = _7879.y;
                _18086 = _17505;
            }
            else
            {
                _18086 = _7866;
            }
            vec3 _7887 = -normalize(_18086);
            _18141 = normalize(((frag_info.camera_right.xyz * _7887.x) + (frag_info.camera_up.xyz * _7887.y)) + (frag_info.camera_forward.xyz * _7887.z));
        }
        else
        {
            _18141 = vec3(0.0);
        }
        vec3 _7067 = vec3(_7030);
        _18557 = mix(_7067, max(_7067, ((((((_6990 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _7030) + ((_6990 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _7030) + ((_6990 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _7030), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _18420 = _7030;
        _18140 = _18141;
        _18125 = float(_7039);
        _18107 = _7017;
    }
    else
    {
        _18557 = vec3(_6124);
        _18420 = _6124;
        _18140 = vec3(0.0);
        _18125 = 0.0;
        _18107 = vec4(1.0);
    }
    bool _7079 = frag_info.has_directional_light > 0.5;
    float _18090 = 0.0;
    vec3 _18703 = vec3(0.0);
    if (_7079)
    {
        highp vec3 _7085 = -normalize(frag_info.directional_light_direction.xyz);
        _18703 = _7085;
        _18090 = dot(_5956, _7085);
    }
    else
    {
        _18703 = vec3(0.0);
        _18090 = 0.0;
    }
    float _7092 = clamp(_18090 * 6.666666507720947265625, 0.0, 1.0);
    bool _7101 = false;
    if (_7079)
    {
        _7101 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _7101 = _7079;
    }
    float _18099 = 0.0;
    if (_7101 && (_7092 > 0.0))
    {
        int _7978 = int(frag_info.shadow_cascade_count);
        float _8173 = max(dot(_5956, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _8176 = _8173 * _8173;
        highp vec3 _8196 = v_position + (_5956 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _8176, 0.0)) / _8176, 8.0))));
        highp float _7984 = frag_info.directional_light_color.w * 0.5;
        float _7986 = frag_info.dielectric_f0.w;
        highp float hp_copy_7986 = _7986;
        float _18091 = 0.0;
        if (_7986 > 0.0)
        {
            _18091 = smoothstep(_7986 - max(frag_info.shadow_fade, hp_copy_7986 * 0.100000001490116119384765625), _7986, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _18091 = 0.0;
        }
        float _18093 = 0.0;
        float _18095 = 0.0;
        if (_18091 < 1.0)
        {
            float _18094 = 0.0;
            float _18096 = 0.0;
            _18096 = 0.0;
            _18094 = 0.0;
            float _19183 = 0.0;
            float _19186 = 0.0;
            for (int _18092 = 0; _18092 < _7978; _18096 = _19186, _18094 = _19183, _18092++)
            {
                if (_18096 < 1.0)
                {
                    highp vec4 _8018 = vec4(_8196, 1.0);
                    highp vec4 _19055 = vec4(0.0);
                    highp float _19058 = 0.0;
                    if (_18092 == 0)
                    {
                        _19058 = frag_info.cascade_box_sizes.x;
                        _19055 = frag_info.light_space_matrix[0] * _8018;
                    }
                    else
                    {
                        highp vec4 _19056 = vec4(0.0);
                        highp float _19059 = 0.0;
                        if (_18092 == 1)
                        {
                            _19059 = frag_info.cascade_box_sizes.y;
                            _19056 = frag_info.light_space_matrix[1] * _8018;
                        }
                        else
                        {
                            highp vec4 _19057 = vec4(0.0);
                            highp float _19060 = 0.0;
                            if (_18092 == 2)
                            {
                                _19060 = frag_info.cascade_box_sizes.z;
                                _19057 = frag_info.light_space_matrix[2] * _8018;
                            }
                            else
                            {
                                _19060 = frag_info.cascade_box_sizes.w;
                                _19057 = frag_info.light_space_matrix[3] * _8018;
                            }
                            _19059 = _19060;
                            _19056 = _19057;
                        }
                        _19058 = _19059;
                        _19055 = _19056;
                    }
                    highp vec3 _8063 = _19055.xyz / vec3(_19055.w);
                    highp vec2 _8066 = _8063.xy * 0.5;
                    highp vec2 _8068 = _8066 + vec2(0.5);
                    highp float _8075 = max(frag_info.shadow_softness / _19058, frag_info.shadow_texel_size);
                    highp float _8077 = _8068.x;
                    bool _8079 = _8077 < _8075;
                    bool _8088 = false;
                    if (!_8079)
                    {
                        _8088 = _8077 > (1.0 - _8075);
                    }
                    else
                    {
                        _8088 = _8079;
                    }
                    bool _8096 = false;
                    if (!_8088)
                    {
                        _8096 = _8068.y < _8075;
                    }
                    else
                    {
                        _8096 = _8088;
                    }
                    bool _8105 = false;
                    if (!_8096)
                    {
                        _8105 = _8068.y > (1.0 - _8075);
                    }
                    else
                    {
                        _8105 = _8096;
                    }
                    bool _8112 = false;
                    if (!_8105)
                    {
                        _8112 = _8063.z < 0.0;
                    }
                    else
                    {
                        _8112 = _8105;
                    }
                    bool _8119 = false;
                    if (!_8112)
                    {
                        _8119 = _8063.z > 1.0;
                    }
                    else
                    {
                        _8119 = _8112;
                    }
                    float _19184 = 0.0;
                    float _19187 = 0.0;
                    if (!_8119)
                    {
                        highp vec2 _8212 = vec2(_8075);
                        highp vec2 _8217 = vec2(_8075 + max(_7984, 9.9999997473787516355514526367188e-05));
                        highp vec2 _8225 = vec2(0.5) - _8066;
                        highp vec2 _8227 = smoothstep(_8212, _8217, _8068) * smoothstep(_8212, _8217, _8225);
                        float _19061 = 0.0;
                        if (_7984 > 0.0)
                        {
                            _19061 = _8227.x * _8227.y;
                        }
                        else
                        {
                            _19061 = 1.0;
                        }
                        float _8128 = min(_19061, 1.0 - _18096);
                        float _19185 = 0.0;
                        float _19188 = 0.0;
                        if (_8128 > 0.0)
                        {
                            highp float _8366 = _8063.z - (frag_info.shadow_bias / (7.0 * _19058));
                            highp float _8372 = 1.0 / (float(_7978) + frag_info.spot_shadow_params.x);
                            highp float _8374 = frag_info.directional_light_direction.w;
                            float mp_copy_8374 = _8374;
                            float _8380 = step(0.5, mp_copy_8374) * (1.0 - step(1.5, mp_copy_8374));
                            float _19091 = 0.0;
                            float _19095 = 0.0;
                            if (_8380 < 0.5)
                            {
                                highp float _8391 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_8391 = _8391;
                                _19095 = sin(mp_copy_8391);
                                _19091 = cos(mp_copy_8391);
                            }
                            else
                            {
                                _19095 = 0.0;
                                _19091 = 1.0;
                            }
                            highp float _19098 = 0.0;
                            if ((_8374 > 1.5) && (_8374 < 2.5))
                            {
                                highp float _8415 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _8420 = max(_8415 * _8366, frag_info.shadow_texel_size);
                                float _19087 = 0.0;
                                highp float _19088 = 0.0;
                                _19088 = 0.0;
                                _19087 = 0.0;
                                highp float _8442 = 0.0;
                                float _8445 = 0.0;
                                for (int _19086 = 0; _19086 < 9; _19088 = _8442, _19087 = _8445, _19086++)
                                {
                                    vec2 _19177 = vec2(0.0);
                                    do
                                    {
                                        if (_19086 == 0)
                                        {
                                            _19177 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_19086 == 1)
                                        {
                                            _19177 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_19086 == 2)
                                        {
                                            _19177 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_19086 == 3)
                                        {
                                            _19177 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_19086 == 4)
                                        {
                                            _19177 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_19086 == 5)
                                        {
                                            _19177 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_19086 == 6)
                                        {
                                            _19177 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_19086 == 7)
                                        {
                                            _19177 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_19086 == 8)
                                        {
                                            _19177 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_19086 == 9)
                                        {
                                            _19177 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_19086 == 10)
                                        {
                                            _19177 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_19086 == 11)
                                        {
                                            _19177 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_19086 == 12)
                                        {
                                            _19177 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_19086 == 13)
                                        {
                                            _19177 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_19086 == 14)
                                        {
                                            _19177 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_19086 == 15)
                                        {
                                            _19177 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _19177 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8749 = clamp(_8068 + (vec2((_19177.x * _19091) - (_19177.y * _19095), (_19177.x * _19095) + (_19177.y * _19091)) * _8420), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8758 = _8749.y;
                                    highp vec2 _8759 = vec2((float(_18092) + _8749.x) * _8372, _8758);
                                    _8759.y = 1.0 - _8758;
                                    highp vec4 _8766 = textureLod(shadow_map, _8759, 0.0);
                                    highp float _8767 = _8766.x;
                                    highp float _8437 = step(_8767, _8366);
                                    float mp_copy_8437 = _8437;
                                    _8442 = _19088 + (_8767 * _8437);
                                    _8445 = _19087 + mp_copy_8437;
                                }
                                highp float _19089 = 0.0;
                                if (_19087 > 0.0)
                                {
                                    _19089 = _19088 / _19087;
                                }
                                else
                                {
                                    _19089 = _8366;
                                }
                                _19098 = clamp(_8415 * max(_8366 - _19089, 0.0), frag_info.shadow_texel_size, _8075);
                            }
                            else
                            {
                                _19098 = _8075;
                            }
                            bool _8476 = _8374 > 2.5;
                            bool _19099 = false;
                            float _19123 = 0.0;
                            if ((_8374 < 1.5) || _8476)
                            {
                                highp vec2 _8800 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8804 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8805 = clamp(_8068, _8800, _8804);
                                highp float _8807 = float(_18092);
                                highp float _8814 = _8805.y;
                                highp vec2 _8815 = vec2((_8807 + _8805.x) * _8372, _8814);
                                _8815.y = 1.0 - _8814;
                                highp float _8827 = float(_8366 <= textureLod(shadow_map, _8815, 0.0).x);
                                float mp_copy_8827 = _8827;
                                float _8837 = (-1.0) * _19091;
                                float _8841 = (-1.0) * _19095;
                                highp vec2 _8865 = clamp(_8068 + (vec2(_8837 - _8841, _8841 + _8837) * _19098), _8800, _8804);
                                highp float _8874 = _8865.y;
                                highp vec2 _8875 = vec2((_8807 + _8865.x) * _8372, _8874);
                                _8875.y = 1.0 - _8874;
                                highp float _8887 = float(_8366 <= textureLod(shadow_map, _8875, 0.0).x);
                                float mp_copy_8887 = _8887;
                                highp vec2 _8925 = clamp(_8068 + (vec2(_19091 - _8841, _19095 + _8837) * _19098), _8800, _8804);
                                highp float _8934 = _8925.y;
                                highp vec2 _8935 = vec2((_8807 + _8925.x) * _8372, _8934);
                                _8935.y = 1.0 - _8934;
                                highp float _8947 = float(_8366 <= textureLod(shadow_map, _8935, 0.0).x);
                                float mp_copy_8947 = _8947;
                                highp vec2 _8985 = clamp(_8068 + (vec2(_8837 - _19095, _8841 + _19091) * _19098), _8800, _8804);
                                highp float _8994 = _8985.y;
                                highp vec2 _8995 = vec2((_8807 + _8985.x) * _8372, _8994);
                                _8995.y = 1.0 - _8994;
                                highp float _9007 = float(_8366 <= textureLod(shadow_map, _8995, 0.0).x);
                                float mp_copy_9007 = _9007;
                                highp vec2 _9045 = clamp(_8068 + (vec2(_19091 - _19095, _19095 + _19091) * _19098), _8800, _8804);
                                highp float _9054 = _9045.y;
                                highp vec2 _9055 = vec2((_8807 + _9045.x) * _8372, _9054);
                                _9055.y = 1.0 - _9054;
                                highp float _9067 = float(_8366 <= textureLod(shadow_map, _9055, 0.0).x);
                                float mp_copy_9067 = _9067;
                                float _8522 = (((mp_copy_8827 + mp_copy_8887) + mp_copy_8947) + mp_copy_9007) + mp_copy_9067;
                                _19123 = _8522 * 0.20000000298023223876953125;
                                _19099 = (_8522 < 0.5) || (_8522 > 4.5);
                            }
                            else
                            {
                                _19123 = 0.0;
                                _19099 = false;
                            }
                            float _19122 = 0.0;
                            if (_19099)
                            {
                                _19122 = _19123;
                            }
                            else
                            {
                                float _19124 = 0.0;
                                if (_8476)
                                {
                                    highp vec2 _9095 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _9099 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _9100 = clamp(_8068 + (vec2(-0.707099974155426025390625) * _19098), _9095, _9099);
                                    highp vec2 _9111 = (vec2(_9100.x, 1.0 - _9100.y) / _9095) - vec2(0.5);
                                    highp vec2 _9113 = floor(_9111);
                                    highp vec2 _9116 = _9111 - _9113;
                                    highp vec2 _9121 = (_9113 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _9123 = float(_18092);
                                    highp vec2 _9131 = vec2((_9123 + _9121.x) * _8372, _9121.y);
                                    highp float _9135 = frag_info.shadow_texel_size * _8372;
                                    highp vec2 _9138 = vec2(_9135, frag_info.shadow_texel_size);
                                    highp vec2 _9147 = vec2(_9135, 0.0);
                                    highp vec2 _9155 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _9184 = _9116.x;
                                    highp float _9193 = mix(mix(float(_8366 <= textureLod(shadow_map, _9131, 0.0).x), float(_8366 <= textureLod(shadow_map, _9131 + _9147, 0.0).x), _9184), mix(float(_8366 <= textureLod(shadow_map, _9131 + _9155, 0.0).x), float(_8366 <= textureLod(shadow_map, _9131 + _9138, 0.0).x), _9184), _9116.y);
                                    float mp_copy_9193 = _9193;
                                    highp vec2 _9227 = clamp(_8068 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _19098), _9095, _9099);
                                    highp vec2 _9238 = (vec2(_9227.x, 1.0 - _9227.y) / _9095) - vec2(0.5);
                                    highp vec2 _9240 = floor(_9238);
                                    highp vec2 _9243 = _9238 - _9240;
                                    highp vec2 _9248 = (_9240 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9258 = vec2((_9123 + _9248.x) * _8372, _9248.y);
                                    highp float _9311 = _9243.x;
                                    highp float _9320 = mix(mix(float(_8366 <= textureLod(shadow_map, _9258, 0.0).x), float(_8366 <= textureLod(shadow_map, _9258 + _9147, 0.0).x), _9311), mix(float(_8366 <= textureLod(shadow_map, _9258 + _9155, 0.0).x), float(_8366 <= textureLod(shadow_map, _9258 + _9138, 0.0).x), _9311), _9243.y);
                                    float mp_copy_9320 = _9320;
                                    highp vec2 _9354 = clamp(_8068 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _19098), _9095, _9099);
                                    highp vec2 _9365 = (vec2(_9354.x, 1.0 - _9354.y) / _9095) - vec2(0.5);
                                    highp vec2 _9367 = floor(_9365);
                                    highp vec2 _9370 = _9365 - _9367;
                                    highp vec2 _9375 = (_9367 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9385 = vec2((_9123 + _9375.x) * _8372, _9375.y);
                                    highp float _9438 = _9370.x;
                                    highp float _9447 = mix(mix(float(_8366 <= textureLod(shadow_map, _9385, 0.0).x), float(_8366 <= textureLod(shadow_map, _9385 + _9147, 0.0).x), _9438), mix(float(_8366 <= textureLod(shadow_map, _9385 + _9155, 0.0).x), float(_8366 <= textureLod(shadow_map, _9385 + _9138, 0.0).x), _9438), _9370.y);
                                    float mp_copy_9447 = _9447;
                                    highp vec2 _9481 = clamp(_8068 + (vec2(0.707099974155426025390625) * _19098), _9095, _9099);
                                    highp vec2 _9492 = (vec2(_9481.x, 1.0 - _9481.y) / _9095) - vec2(0.5);
                                    highp vec2 _9494 = floor(_9492);
                                    highp vec2 _9497 = _9492 - _9494;
                                    highp vec2 _9502 = (_9494 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9512 = vec2((_9123 + _9502.x) * _8372, _9502.y);
                                    highp float _9565 = _9497.x;
                                    highp float _9574 = mix(mix(float(_8366 <= textureLod(shadow_map, _9512, 0.0).x), float(_8366 <= textureLod(shadow_map, _9512 + _9147, 0.0).x), _9565), mix(float(_8366 <= textureLod(shadow_map, _9512 + _9155, 0.0).x), float(_8366 <= textureLod(shadow_map, _9512 + _9138, 0.0).x), _9565), _9497.y);
                                    float mp_copy_9574 = _9574;
                                    _19124 = (((mp_copy_9193 + mp_copy_9320) + mp_copy_9447) + mp_copy_9574) * 0.25;
                                }
                                else
                                {
                                    int _8569 = (_8380 > 0.5) ? 17 : 16;
                                    float _19118 = 0.0;
                                    _19118 = 0.0;
                                    float _8597 = 0.0;
                                    for (int _19100 = 0; _19100 < 17; _19118 = _8597, _19100++)
                                    {
                                        if (_19100 >= _8569)
                                        {
                                            break;
                                        }
                                        vec2 _19101 = vec2(0.0);
                                        do
                                        {
                                            if (_19100 == 0)
                                            {
                                                _19101 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_19100 == 1)
                                            {
                                                _19101 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_19100 == 2)
                                            {
                                                _19101 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_19100 == 3)
                                            {
                                                _19101 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_19100 == 4)
                                            {
                                                _19101 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_19100 == 5)
                                            {
                                                _19101 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_19100 == 6)
                                            {
                                                _19101 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_19100 == 7)
                                            {
                                                _19101 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_19100 == 8)
                                            {
                                                _19101 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_19100 == 9)
                                            {
                                                _19101 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_19100 == 10)
                                            {
                                                _19101 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_19100 == 11)
                                            {
                                                _19101 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_19100 == 12)
                                            {
                                                _19101 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_19100 == 13)
                                            {
                                                _19101 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_19100 == 14)
                                            {
                                                _19101 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_19100 == 15)
                                            {
                                                _19101 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _19101 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _19103 = vec2(0.0);
                                        do
                                        {
                                            if (_19100 < 3)
                                            {
                                                _19103 = vec2(float(_19100) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_19100 < 6)
                                            {
                                                _19103 = vec2((float(_19100 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_19100 < 11)
                                            {
                                                _19103 = vec2((float(_19100 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_19100 < 14)
                                            {
                                                _19103 = vec2((float(_19100 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _19103 = vec2(float(_19100 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8586 = mix(_19101, _19103, vec2(_8380));
                                        float _9714 = _8586.x;
                                        float _9718 = _8586.y;
                                        highp vec2 _9744 = clamp(_8068 + (vec2((_9714 * _19091) - (_9718 * _19095), (_9714 * _19095) + (_9718 * _19091)) * _19098), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9753 = _9744.y;
                                        highp vec2 _9754 = vec2((float(_18092) + _9744.x) * _8372, _9753);
                                        _9754.y = 1.0 - _9753;
                                        highp float _9766 = float(_8366 <= textureLod(shadow_map, _9754, 0.0).x);
                                        float mp_copy_9766 = _9766;
                                        _8597 = _19118 + mp_copy_9766;
                                    }
                                    _19124 = _19118 / float(_8569);
                                }
                                _19122 = _19124;
                            }
                            bool _8611 = _18092 == (_7978 - 1);
                            bool _8617 = false;
                            if (_8611)
                            {
                                _8617 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8617 = _8611;
                            }
                            float _19125 = 0.0;
                            if (_8617)
                            {
                                highp vec2 _8624 = vec2(frag_info.shadow_fade / _19058);
                                highp vec2 _8632 = smoothstep(vec2(0.0), _8624, _8068) * smoothstep(vec2(0.0), _8624, _8225);
                                _19125 = mix(1.0, _19122, _8632.x * _8632.y);
                            }
                            else
                            {
                                _19125 = _19122;
                            }
                            _19188 = _18096 + _8128;
                            _19185 = _18094 + (_8128 * _19125);
                        }
                        else
                        {
                            _19188 = _18096;
                            _19185 = _18094;
                        }
                        _19187 = _19188;
                        _19184 = _19185;
                    }
                    else
                    {
                        _19187 = _18096;
                        _19184 = _18094;
                    }
                    _19186 = _19187;
                    _19183 = _19184;
                }
                else
                {
                    _19186 = _18096;
                    _19183 = _18094;
                }
            }
            _18095 = _18096;
            _18093 = _18094;
        }
        else
        {
            _18095 = 0.0;
            _18093 = 0.0;
        }
        _18099 = mix(_18093 + (1.0 - _18095), 1.0, _18091);
    }
    else
    {
        _18099 = 1.0;
    }
    bool _7114 = frag_info.ssao_lighting.w > 0.5;
    bool _7120 = false;
    if (_7114)
    {
        _7120 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _7120 = _7114;
    }
    float _18111 = 0.0;
    if (_7120)
    {
        _18111 = min(_18099, _18107.y);
    }
    else
    {
        _18111 = _18099;
    }
    vec3 mp_copy_18112 = vec3(0.0);
    float _7129 = _7092 * _18111;
    bool _9773 = view_info.camera_forward.w > 0.5;
    highp vec3 _18112 = vec3(0.0);
    if (_9773)
    {
        _18112 = -view_info.camera_forward.xyz;
    }
    else
    {
        _18112 = normalize(v_viewvector);
    }
    highp float _9817 = 0.0;
    mp_copy_18112 = _18112;
    vec3 _7138 = mix(frag_info.dielectric_f0.xyz, _6990, vec3(_6090));
    float _7141 = dot(_18034, _18112);
    float _7142 = max(_7141, 0.0);
    float _7146 = max(dot(_5956, _18112), 0.0);
    vec3 _7150 = reflect(-mp_copy_18112, _18034);
    highp vec2 _18113 = vec2(0.0);
    do
    {
        _9817 = frag_info.punctual_dims.x;
        if (_9817 < 0.5)
        {
            _18113 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9829 = v_position - frag_info.camera_position.xyz;
            highp float _9844 = dot(_9829, frag_info.camera_forward.xyz);
            highp float _9850 = max(_9844, 9.9999997473787516355514526367188e-05);
            highp vec2 _9953 = (vec3(dot(_9829, frag_info.camera_right.xyz), dot(_9829, frag_info.camera_up.xyz), _9850).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9850, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _9968 = float(int(((((clamp(floor((log2(max(_9844 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9953.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9953.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _18113 = vec2(textureLod(punctual_index, vec2((mod(_9968, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_9968 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _18113 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _7155 = int(_18113.x + 0.5);
    mediump int _7159 = int(_18113.y + 0.5);
    highp vec3 _18776 = vec3(0.0);
    _18776 = vec3(0.0);
    highp vec3 _19593 = vec3(0.0);
    for (int _18114 = 0; _18114 < _7159; _18776 = _19593, _18114++)
    {
        highp float _10001 = float(_7155 + _18114);
        highp float _10032 = (float(int(textureLod(punctual_index, vec2((mod(_10001, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_10001 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9817;
        highp vec2 _10033 = vec2(0.0625, _10032);
        highp vec4 _10036 = textureLod(punctual_lights, _10033, 0.0);
        highp vec4 _10053 = textureLod(punctual_lights, vec2(0.1875, _10032), 0.0);
        highp float _7177 = _10036.w;
        highp vec3 _7179 = _10053.xyz;
        highp vec3 _19594 = vec3(0.0);
        if (_7177 > 2.5)
        {
            highp vec4 _10070 = textureLod(punctual_lights, vec2(0.3125, _10032), 0.0);
            highp vec4 _10087 = textureLod(punctual_lights, vec2(0.4375, _10032), 0.0);
            highp vec3 _7193 = _10070.xyz * (_10070.w * 0.5);
            highp vec3 _7199 = _10087.xyz * (_10087.w * 0.5);
            highp vec3 _7201 = _10036.xyz;
            highp vec3 _7203 = _7201 - _7193;
            highp vec3 _7205 = _7203 - _7199;
            highp vec3 _7209 = _7201 + _7193;
            highp vec3 _7211 = _7209 - _7199;
            highp vec3 _7223 = _7203 + _7199;
            highp vec3 _7227 = _7201 - v_position;
            highp float _7233 = _10053.w;
            highp float _7237 = (dot(_7227, _7227) * _7233) * _7233;
            highp float _7242 = clamp(1.0 - (_7237 * _7237), 0.0, 1.0);
            float mp_copy_7242 = _7242;
            vec2 _10094 = (clamp(vec2(_18082, sqrt(1.0 - _7142)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _10096 = _10094.x;
            float _10101 = _10094.y;
            vec4 _7266 = textureLod(brdf_lut, vec2((_10096 + 1.0) * 0.3333333432674407958984375, _10101), 0.0);
            vec4 _7270 = textureLod(brdf_lut, vec2((_10096 + 2.0) * 0.3333333432674407958984375, _10101), 0.0);
            vec3 _10144 = normalize(mp_copy_18112 - (_18034 * _7141));
            mat3 _10166 = transpose(mat3(_10144, -cross(_18034, _10144), _18034));
            mat3 _10167 = mat3(vec3(_7266.x, 0.0, _7266.y), vec3(0.0, 1.0, 0.0), vec3(_7266.z, 0.0, _7266.w)) * _10166;
            highp vec3 _10171 = _7205 - v_position;
            highp vec3 _10173 = normalize(_10167 * _10171);
            vec3 mp_copy_10173 = _10173;
            highp vec3 _10177 = _7211 - v_position;
            highp vec3 _10179 = normalize(_10167 * _10177);
            vec3 mp_copy_10179 = _10179;
            highp vec3 _10183 = (_7209 + _7199) - v_position;
            highp vec3 _10185 = normalize(_10167 * _10183);
            vec3 mp_copy_10185 = _10185;
            highp vec3 _10189 = _7223 - v_position;
            highp vec3 _10191 = normalize(_10167 * _10189);
            vec3 mp_copy_10191 = _10191;
            float _10220 = dot(_10173, _10179);
            float _10222 = abs(_10220);
            float _10236 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10222)) * _10222)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10222) * _10222));
            float _18994 = 0.0;
            if (_10220 > 0.0)
            {
                _18994 = _10236;
            }
            else
            {
                _18994 = (0.5 * inversesqrt(max(1.0 - (_10220 * _10220), 1.0000000116860974230803549289703e-07))) - _10236;
            }
            float _10269 = dot(_10179, _10185);
            float _10271 = abs(_10269);
            float _10285 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10271)) * _10271)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10271) * _10271));
            float _18995 = 0.0;
            if (_10269 > 0.0)
            {
                _18995 = _10285;
            }
            else
            {
                _18995 = (0.5 * inversesqrt(max(1.0 - (_10269 * _10269), 1.0000000116860974230803549289703e-07))) - _10285;
            }
            float _10318 = dot(_10185, _10191);
            float _10320 = abs(_10318);
            float _10334 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10320)) * _10320)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10320) * _10320));
            float _18996 = 0.0;
            if (_10318 > 0.0)
            {
                _18996 = _10334;
            }
            else
            {
                _18996 = (0.5 * inversesqrt(max(1.0 - (_10318 * _10318), 1.0000000116860974230803549289703e-07))) - _10334;
            }
            float _10367 = dot(_10191, _10173);
            float _10369 = abs(_10367);
            float _10383 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10369)) * _10369)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10369) * _10369));
            float _18997 = 0.0;
            if (_10367 > 0.0)
            {
                _18997 = _10383;
            }
            else
            {
                _18997 = (0.5 * inversesqrt(max(1.0 - (_10367 * _10367), 1.0000000116860974230803549289703e-07))) - _10383;
            }
            vec3 _10206 = (((cross(mp_copy_10173, mp_copy_10179) * _18994) + (cross(mp_copy_10179, mp_copy_10185) * _18995)) + (cross(mp_copy_10185, mp_copy_10191) * _18996)) + (cross(mp_copy_10191, mp_copy_10173) * _18997);
            float _10409 = length(_10206);
            mat3 _10469 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _10166;
            highp vec3 _10475 = normalize(_10469 * _10171);
            vec3 mp_copy_10475 = _10475;
            highp vec3 _10481 = normalize(_10469 * _10177);
            vec3 mp_copy_10481 = _10481;
            highp vec3 _10487 = normalize(_10469 * _10183);
            vec3 mp_copy_10487 = _10487;
            highp vec3 _10493 = normalize(_10469 * _10189);
            vec3 mp_copy_10493 = _10493;
            float _10522 = dot(_10475, _10481);
            float _10524 = abs(_10522);
            float _10538 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10524)) * _10524)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10524) * _10524));
            float _18998 = 0.0;
            if (_10522 > 0.0)
            {
                _18998 = _10538;
            }
            else
            {
                _18998 = (0.5 * inversesqrt(max(1.0 - (_10522 * _10522), 1.0000000116860974230803549289703e-07))) - _10538;
            }
            float _10571 = dot(_10481, _10487);
            float _10573 = abs(_10571);
            float _10587 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10573)) * _10573)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10573) * _10573));
            float _18999 = 0.0;
            if (_10571 > 0.0)
            {
                _18999 = _10587;
            }
            else
            {
                _18999 = (0.5 * inversesqrt(max(1.0 - (_10571 * _10571), 1.0000000116860974230803549289703e-07))) - _10587;
            }
            float _10620 = dot(_10487, _10493);
            float _10622 = abs(_10620);
            float _10636 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10622)) * _10622)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10622) * _10622));
            float _19000 = 0.0;
            if (_10620 > 0.0)
            {
                _19000 = _10636;
            }
            else
            {
                _19000 = (0.5 * inversesqrt(max(1.0 - (_10620 * _10620), 1.0000000116860974230803549289703e-07))) - _10636;
            }
            float _10669 = dot(_10493, _10475);
            float _10671 = abs(_10669);
            float _10685 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10671)) * _10671)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10671) * _10671));
            float _19001 = 0.0;
            if (_10669 > 0.0)
            {
                _19001 = _10685;
            }
            else
            {
                _19001 = (0.5 * inversesqrt(max(1.0 - (_10669 * _10669), 1.0000000116860974230803549289703e-07))) - _10685;
            }
            vec3 _10508 = (((cross(mp_copy_10475, mp_copy_10481) * _18998) + (cross(mp_copy_10481, mp_copy_10487) * _18999)) + (cross(mp_copy_10487, mp_copy_10493) * _19000)) + (cross(mp_copy_10493, mp_copy_10475) * _19001);
            float _10711 = length(_10508);
            _19594 = _18776 + (((_7179 * (mp_copy_7242 * mp_copy_7242)) * step(0.0, dot(cross(_7211 - _7205, _7223 - _7205), v_position - _7205))) * (((((_7138 * _7270.x) + ((vec3(1.0) - _7138) * _7270.y)) * max(((_10409 * _10409) + _10206.z) / (_10409 + 1.0), 0.0)) * 1.0) + ((_6990 * (1.0 - _6090)) * max(((_10711 * _10711) + _10508.z) / (_10711 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_18938 = 0.0;
            vec3 _18911 = vec3(0.0);
            highp vec3 _18934 = vec3(0.0);
            float _18938 = 0.0;
            if (_7177 < 0.5)
            {
                _18938 = _18082;
                _18934 = _7179;
                _18911 = -normalize(textureLod(punctual_lights, vec2(0.3125, _10032), 0.0).xyz);
            }
            else
            {
                highp vec3 _7357 = _10036.xyz - v_position;
                highp float _7360 = dot(_7357, _7357);
                highp float _7364 = inversesqrt(max(_7360, 9.9999999392252902907785028219223e-09));
                highp vec3 _7365 = _7357 * _7364;
                vec3 mp_copy_7365 = _7365;
                highp float _7367 = _10053.w;
                highp float _7372 = (_7360 * _7367) * _7367;
                highp float _7377 = clamp(1.0 - (_7372 * _7372), 0.0, 1.0);
                float mp_copy_7377 = _7377;
                if (_7377 <= 0.0)
                {
                    _19593 = _18776;
                    continue;
                }
                highp vec4 _10755 = textureLod(punctual_lights, vec2(0.4375, _10032), 0.0);
                highp float _7385 = _10755.w;
                float _18943 = 0.0;
                if (_7385 > 0.0)
                {
                    highp float _7412 = (_18082 * _18082) + ((_7385 * 0.5) * _7364);
                    float mp_copy_7412 = _7412;
                    _18943 = sqrt(min(mp_copy_7412, 1.0));
                }
                else
                {
                    _18943 = _18082;
                }
                highp vec3 _7419 = _7179 * ((mp_copy_7377 * mp_copy_7377) / max(pow(max(_7360, _7385 * _7385), _10755.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _18935 = vec3(0.0);
                if (_7177 > 1.5)
                {
                    highp vec4 _10772 = textureLod(punctual_lights, vec2(0.3125, _10032), 0.0);
                    highp float _7438 = clamp((dot(normalize(_10772.xyz), -mp_copy_7365) * _10772.w) + _10755.x, 0.0, 1.0);
                    float mp_copy_7438 = _7438;
                    highp vec3 _7443 = _7419 * (mp_copy_7438 * mp_copy_7438);
                    if (_7438 <= 0.0)
                    {
                        _19593 = _18776;
                        continue;
                    }
                    bool _7449 = _7438 > 0.0;
                    bool _7455 = false;
                    if (_7449)
                    {
                        _7455 = _10755.y > (-0.5);
                    }
                    else
                    {
                        _7455 = _7449;
                    }
                    bool _7461 = false;
                    if (_7455)
                    {
                        _7461 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7461 = _7455;
                    }
                    highp vec3 _18936 = vec3(0.0);
                    if (_7461)
                    {
                        float _18902 = 0.0;
                        do
                        {
                            highp vec4 _10884 = mat4(textureLod(punctual_lights, vec2(0.5625, _10032), 0.0), textureLod(punctual_lights, vec2(0.6875, _10032), 0.0), textureLod(punctual_lights, vec2(0.8125, _10032), 0.0), textureLod(punctual_lights, vec2(0.9375, _10032), 0.0)) * vec4(v_position + (_5956 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10886 = _10884.w;
                            if (_10886 <= 0.0)
                            {
                                _18902 = 1.0;
                                break;
                            }
                            highp vec3 _10895 = _10884.xyz / vec3(_10886);
                            highp vec2 _10900 = (_10895.xy * 0.5) + vec2(0.5);
                            highp float _10902 = _10900.x;
                            bool _10903 = _10902 < 0.0;
                            bool _10910 = false;
                            if (!_10903)
                            {
                                _10910 = _10902 > 1.0;
                            }
                            else
                            {
                                _10910 = _10903;
                            }
                            bool _10917 = false;
                            if (!_10910)
                            {
                                _10917 = _10900.y < 0.0;
                            }
                            else
                            {
                                _10917 = _10910;
                            }
                            bool _10924 = false;
                            if (!_10917)
                            {
                                _10924 = _10900.y > 1.0;
                            }
                            else
                            {
                                _10924 = _10917;
                            }
                            bool _10931 = false;
                            if (!_10924)
                            {
                                _10931 = _10895.z < 0.0;
                            }
                            else
                            {
                                _10931 = _10924;
                            }
                            bool _10938 = false;
                            if (!_10931)
                            {
                                _10938 = _10895.z > 1.0;
                            }
                            else
                            {
                                _10938 = _10931;
                            }
                            if (_10938)
                            {
                                _18902 = 1.0;
                                break;
                            }
                            highp float _10945 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _10950 = frag_info.shadow_cascade_count + float(int(_10755.y + 0.5));
                            highp float _10955 = _10895.z - frag_info.spot_shadow_params.y;
                            highp float _10966 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_10966 = _10966;
                            highp vec2 _10973 = vec2(cos(mp_copy_10966), sin(mp_copy_10966)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _10975 = _10973.x;
                            highp float _10977 = _10973.y;
                            highp vec2 _10985 = vec2(_10975 - _10977, _10975 + _10977) * 0.707106769084930419921875;
                            highp float _11178 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_10902, 0.0, 1.0)) / _10945, 1.0 - clamp(_10900.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11178 = _11178;
                            highp vec2 _10993 = _10900 + _10973;
                            highp float _11200 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_10993.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_10993.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11200 = _11200;
                            highp vec2 _11001 = _10900 - _10973;
                            highp float _11222 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11001.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11001.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11222 = _11222;
                            highp vec2 _11014 = _10900 + vec2(-_10977, _10975);
                            highp float _11244 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11014.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11014.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11244 = _11244;
                            highp vec2 _11027 = _10900 + vec2(_10977, -_10975);
                            highp float _11266 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11027.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11027.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11266 = _11266;
                            float _11032 = (((mp_copy_11178 + mp_copy_11200) + mp_copy_11222) + mp_copy_11244) + mp_copy_11266;
                            if ((_11032 < 0.5) || (_11032 > 4.5))
                            {
                                _18902 = _11032 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _11044 = _10900 + _10985;
                            highp float _11288 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11044.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11044.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11288 = _11288;
                            highp vec2 _11051 = _10900 - _10985;
                            highp float _11310 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11051.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11051.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11310 = _11310;
                            highp float _11059 = _10985.y;
                            highp float _11062 = _10985.x;
                            highp vec2 _11064 = _10900 + vec2(-_11059, _11062);
                            highp float _11332 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11064.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11064.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11332 = _11332;
                            highp vec2 _11077 = _10900 + vec2(_11059, -_11062);
                            highp float _11354 = float(_10955 <= textureLod(shadow_map, vec2((_10950 + clamp(_11077.x, 0.0, 1.0)) / _10945, 1.0 - clamp(_11077.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11354 = _11354;
                            _18902 = (_11032 + (((mp_copy_11288 + mp_copy_11310) + mp_copy_11332) + mp_copy_11354)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18936 = _7443 * _18902;
                    }
                    else
                    {
                        _18936 = _7443;
                    }
                    _18935 = _18936;
                }
                else
                {
                    bool _7477 = _7177 > 0.5;
                    bool _7483 = false;
                    if (_7477)
                    {
                        _7483 = _10755.y > (-0.5);
                    }
                    else
                    {
                        _7483 = _7477;
                    }
                    bool _7489 = false;
                    if (_7483)
                    {
                        _7489 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7489 = _7483;
                    }
                    highp vec3 _18937 = vec3(0.0);
                    if (_7489)
                    {
                        float _18889 = 0.0;
                        do
                        {
                            highp vec4 _11667 = textureLod(punctual_lights, vec2(0.5625, _10032), 0.0);
                            highp vec4 _11684 = textureLod(punctual_lights, vec2(0.6875, _10032), 0.0);
                            highp vec3 _11426 = (v_position + (_5956 * _11667.z)) - textureLod(punctual_lights, _10033, 0.0).xyz;
                            highp vec3 _11428 = abs(_11426);
                            highp float _11430 = _11428.x;
                            highp float _11432 = _11428.y;
                            bool _11433 = _11430 >= _11432;
                            bool _11441 = false;
                            if (_11433)
                            {
                                _11441 = _11430 >= _11428.z;
                            }
                            else
                            {
                                _11441 = _11433;
                            }
                            highp vec3 _18879 = vec3(0.0);
                            float _18881 = 0.0;
                            if (_11441)
                            {
                                highp float _11444 = _11426.x;
                                bool _11445 = _11444 >= 0.0;
                                highp vec3 _18878 = vec3(0.0);
                                if (_11445)
                                {
                                    _18878 = vec3(-_11426.z, _11426.y, _11444);
                                }
                                else
                                {
                                    _18878 = vec3(_11426.zy, -_11444);
                                }
                                _18881 = _11445 ? 0.0 : 1.0;
                                _18879 = _18878;
                            }
                            else
                            {
                                highp vec3 _18880 = vec3(0.0);
                                float _18883 = 0.0;
                                if (_11432 >= _11428.z)
                                {
                                    highp float _11478 = _11426.y;
                                    bool _11479 = _11478 >= 0.0;
                                    highp vec3 _18877 = vec3(0.0);
                                    if (_11479)
                                    {
                                        _18877 = vec3(-_11426.x, _11426.z, _11478);
                                    }
                                    else
                                    {
                                        _18877 = vec3(_11426.xz, -_11478);
                                    }
                                    _18883 = _11479 ? 2.0 : 3.0;
                                    _18880 = _18877;
                                }
                                else
                                {
                                    highp float _11506 = _11426.z;
                                    bool _11507 = _11506 >= 0.0;
                                    highp vec3 _18876 = vec3(0.0);
                                    if (_11507)
                                    {
                                        _18876 = _11426;
                                    }
                                    else
                                    {
                                        _18876 = vec3(-_11426.x, _11426.y, -_11506);
                                    }
                                    _18883 = _11507 ? 4.0 : 5.0;
                                    _18880 = _18876;
                                }
                                _18881 = _18883;
                                _18879 = _18880;
                            }
                            if (_18879.z <= 0.0)
                            {
                                _18889 = 1.0;
                                break;
                            }
                            highp vec2 _11547 = ((_18879.xy / vec2(_18879.z)) * 0.5) + vec2(0.5);
                            highp float _11558 = (_11667.x - (_11667.y / _18879.z)) - _11684.x;
                            if ((_11558 < 0.0) || (_11558 > 1.0))
                            {
                                _18889 = 1.0;
                                break;
                            }
                            highp float hp_copy_18886 = 0.0;
                            highp float _11570 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _11576 = _18881 >= 4.0;
                            highp float _11578 = (frag_info.shadow_cascade_count + _10755.y) + float(_11576);
                            float _18886 = 0.0;
                            if (_11576)
                            {
                                _18886 = _18881 - 4.0;
                            }
                            else
                            {
                                _18886 = _18881;
                            }
                            hp_copy_18886 = _18886;
                            highp float _11595 = _11684.y * 0.5;
                            highp float _11598 = _11667.w * 0.0040000001899898052215576171875;
                            highp vec2 _11709 = vec2(_11595);
                            highp vec2 _11712 = vec2(1.0 - _11595);
                            highp vec2 _11718 = vec2(mod(hp_copy_18886, 2.0), 1.0 - floor(hp_copy_18886 * 0.5)) * 0.5;
                            highp vec2 _11721 = _11718 + (clamp(_11547, _11709, _11712) * 0.5);
                            highp float _11614 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _18888 = 0.0;
                            _18888 = float(_11558 <= textureLod(shadow_map, vec2((_11578 + _11721.x) / _11570, 1.0 - _11721.y), 0.0).x);
                            for (int _18887 = 0; _18887 < 8; )
                            {
                                highp float _11624 = _11614 + (float(_18887) * 0.785398185253143310546875);
                                float mp_copy_11624 = _11624;
                                highp vec2 _11758 = _11718 + (clamp(_11547 + (vec2(cos(mp_copy_11624), sin(mp_copy_11624)) * _11598), _11709, _11712) * 0.5);
                                highp float _11775 = float(_11558 <= textureLod(shadow_map, vec2((_11578 + _11758.x) / _11570, 1.0 - _11758.y), 0.0).x);
                                float mp_copy_11775 = _11775;
                                _18888 += mp_copy_11775;
                                _18887++;
                                continue;
                            }
                            _18889 = _18888 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18937 = _7419 * _18889;
                    }
                    else
                    {
                        _18937 = _7419;
                    }
                    _18935 = _18937;
                }
                _18938 = _18943;
                _18934 = _18935;
                _18911 = _7365;
            }
            hp_copy_18938 = _18938;
            highp vec3 _18965 = vec3(0.0);
            highp vec3 _18966 = vec3(0.0);
            do
            {
                float _11841 = max(dot(_18034, _18911), 0.0);
                highp float hp_copy_11841 = _11841;
                if (_11841 <= 0.0)
                {
                    _18966 = vec3(0.0);
                    _18965 = vec3(0.0);
                    break;
                }
                float _11847 = max(_7142, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11847 = _11847;
                vec3 _11850 = _18911 + mp_copy_18112;
                float _11853 = dot(_11850, _11850);
                vec3 _18963 = vec3(0.0);
                vec3 _18964 = vec3(0.0);
                if (_11853 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11861 = _11850 * inversesqrt(_11853);
                    float _18962 = 0.0;
                    do
                    {
                        float _11918 = dot(_18034, _11861);
                        if (_11918 <= 0.0)
                        {
                            _18962 = 0.0;
                            break;
                        }
                        float _11925 = _18938 * _18938;
                        vec3 _11928 = cross(_18034, _11861);
                        float _11931 = _11918 * _11925;
                        float _11940 = _11925 / (dot(_11928, _11928) + (_11931 * _11931));
                        _18962 = min((_11940 * _11940) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _11978 = _7138 + ((vec3(1.0) - _7138) * pow(clamp(1.0 - max(dot(_11861, _18112), 0.0), 0.0, 1.0), 5.0));
                    _18964 = (_11978 * min(_18962 * (0.5 / max(mix((2.0 * hp_copy_11841) * _11847, hp_copy_11841 + hp_copy_11847, hp_copy_18938 * hp_copy_18938), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _18963 = _11978;
                }
                else
                {
                    _18964 = vec3(0.0);
                    _18963 = _7138;
                }
                _18966 = (_18964 * _18934) * _11841;
                _18965 = (((((vec3(1.0) - _18963) * (1.0 - _6090)) * _6990) * 0.3183098733425140380859375) * _18934) * _11841;
                break;
            } while(false);
            _19594 = _18776 + (_18965 + _18966);
        }
        _19593 = _19594;
    }
    bool _12202 = false;
    mat3 _7537 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7540 = _18125 > 0.5;
    bvec3 _7543 = bvec3(_7540);
    highp vec3 _7544 = vec3(_7543.x ? _18140.x : _18034.x, _7543.y ? _18140.y : _18034.y, _7543.z ? _18140.z : _18034.z);
    vec3 mp_copy_7544 = _7544;
    vec3 _7545 = _7537 * mp_copy_7544;
    vec3 _7548 = _7537 * _7150;
    float _12021 = _7545.y;
    float _12022 = 0.48860299587249755859375 * _12021;
    float _12028 = _7545.z;
    float _12029 = 0.48860299587249755859375 * _12028;
    float _12035 = _7545.x;
    float _12036 = 0.48860299587249755859375 * _12035;
    float _12043 = 1.09254801273345947265625 * _12035;
    float _12046 = _12043 * _12021;
    float _12056 = (1.09254801273345947265625 * _12021) * _12028;
    float _12068 = 0.3153919875621795654296875 * (((3.0 * _12028) * _12028) - 1.0);
    float _12078 = _12043 * _12028;
    float _12094 = 0.546274006366729736328125 * ((_12035 * _12035) - (_12021 * _12021));
    vec3 _7551 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _12022)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _12029)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _12036)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _12046)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _12056)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _12068)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _12078)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _12094), vec3(0.0));
    vec3 _18145 = vec3(0.0);
    do
    {
        _12202 = radiance_layout_info.mip_layout > 0.5;
        if (_12202)
        {
            vec2 _12281 = vec2(atan(_7548.z, _7548.x), asin(clamp(_7548.y, -1.0, 1.0)));
            highp vec2 hp_copy_12281 = _12281;
            _18145 = textureLod(prefiltered_radiance, (hp_copy_12281 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_18082, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _12300 = vec2(atan(_7548.z, _7548.x), asin(clamp(_7548.y, -1.0, 1.0)));
        highp vec2 hp_copy_12300 = _12300;
        highp vec2 _12305 = (hp_copy_12300 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _12212 = clamp(_12305.y, 0.00390625, 0.99609375);
        float _12216 = clamp(_18082, 0.0, 1.0) * 7.0;
        float _12218 = floor(_12216);
        highp float _12237 = _12305.x;
        _18145 = mix(textureLod(prefiltered_radiance, vec2(_12237, (_12218 + _12212) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_12237, (min(_12218 + 1.0, 7.0) + _12212) * 0.125), 0.0).xyz, vec3(_12216 - _12218));
        break;
    } while(false);
    bool _7558 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _18150 = vec3(0.0);
    highp vec3 _18151 = vec3(0.0);
    if (_7558)
    {
        vec3 _18146 = vec3(0.0);
        do
        {
            if (_12202)
            {
                vec2 _12593 = vec2(atan(_7548.z, _7548.x), asin(clamp(_7548.y, -1.0, 1.0)));
                highp vec2 hp_copy_12593 = _12593;
                _18146 = textureLod(prefiltered_radiance_b, (hp_copy_12593 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_18082, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _12612 = vec2(atan(_7548.z, _7548.x), asin(clamp(_7548.y, -1.0, 1.0)));
            highp vec2 hp_copy_12612 = _12612;
            highp vec2 _12617 = (hp_copy_12612 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12524 = clamp(_12617.y, 0.00390625, 0.99609375);
            float _12528 = clamp(_18082, 0.0, 1.0) * 7.0;
            float _12530 = floor(_12528);
            highp float _12549 = _12617.x;
            _18146 = mix(textureLod(prefiltered_radiance_b, vec2(_12549, (_12530 + _12524) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12549, (min(_12530 + 1.0, 7.0) + _12524) * 0.125), 0.0).xyz, vec3(_12528 - _12530));
            break;
        } while(false);
        highp vec3 _7569 = vec3(frag_info.radiance_blend.x);
        _18151 = mix(_18145, _18146, _7569);
        _18150 = mix(_7551, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _12022)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _12029)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _12036)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _12046)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _12056)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _12068)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _12078)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _12094), vec3(0.0)), _7569);
    }
    else
    {
        _18151 = _18145;
        _18150 = _7551;
    }
    highp float _12630 = 0.0;
    highp vec3 _7580 = _18150 * frag_info.environment_intensity;
    float _18152 = 0.0;
    do
    {
        _12630 = frag_info.gi_grid.w;
        if (_12630 <= 0.0)
        {
            _18152 = 0.0;
            break;
        }
        highp vec3 _12643 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _12651 = min(_12643, (frag_info.gi_counts.xyz - vec3(1.0)) - _12643);
        _18152 = clamp(min(_12651.x, min(_12651.y, _12651.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _18343 = vec3(0.0);
    if (_18152 > 0.0)
    {
        highp vec3 _12743 = v_position + (((_18034 * 0.20000000298023223876953125) + (mp_copy_18112 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _12746 = _12743 / frag_info.gi_grid.xyz;
        highp vec3 _12748 = floor(_12746);
        highp vec3 _12754 = clamp(_12746 - _12748, vec3(0.0), vec3(1.0));
        vec3 mp_copy_12754 = _12754;
        highp vec3 _12876 = _12748 - frag_info.gi_anchor.xyz;
        bool _12879 = any(lessThan(_12876, vec3(0.0)));
        bool _12887 = false;
        if (!_12879)
        {
            _12887 = any(greaterThanEqual(_12876, frag_info.gi_counts.xyz));
        }
        else
        {
            _12887 = _12879;
        }
        vec3 mp_copy_18153 = vec3(0.0);
        highp float _12888 = _12887 ? 0.0 : 1.0;
        float mp_copy_12888 = _12888;
        vec3 _12890 = vec3(1.0) - mp_copy_12754;
        vec3 _12894 = max(_12890, vec3(0.001000000047497451305389404296875));
        highp vec3 _12910 = (_12748 * frag_info.gi_grid.xyz) - _12743;
        highp float _12912 = length(_12910);
        highp vec3 _18153 = vec3(0.0);
        if (_12912 > 9.9999997473787516355514526367188e-06)
        {
            _18153 = _12910 / vec3(_12912);
        }
        else
        {
            _18153 = _18034;
        }
        mp_copy_18153 = _18153;
        float _12930 = pow((dot(_18153, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13055 = _12748 - (frag_info.gi_counts.xyz * floor(_12748 / frag_info.gi_counts.xyz));
        highp float _13071 = _13055.x + (frag_info.gi_counts.x * (_13055.y + (frag_info.gi_counts.y * _13055.z)));
        bool _12941 = frag_info.gi_visibility.x > 0.0;
        float _18158 = 0.0;
        if (_12941)
        {
            highp float _13079 = floor(_13071 / frag_info.gi_counts.w);
            highp vec2 _13093 = vec2((_13071 - (_13079 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13079 * 16.0));
            vec3 _12953 = -mp_copy_18153;
            vec3 _13141 = _12953 / vec3((abs(_12953.x) + abs(_12953.y)) + abs(_12953.z));
            vec2 _18154 = vec2(0.0);
            if (_13141.z >= 0.0)
            {
                _18154 = _13141.xy;
            }
            else
            {
                _18154 = (vec2(1.0) - abs(_13141.yx)) * vec2((_13141.x >= 0.0) ? 1.0 : (-1.0), (_13141.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12957 = texture(irradiance_field, clamp((_13093 + vec2(1.0)) + (clamp((_18154 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13093 + vec2(0.5), _13093 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12962 = _12957.x * frag_info.gi_visibility.z;
            highp float _12974 = abs((_12962 * _12962) - ((_12957.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12980 = (_12912 - _12962) - frag_info.gi_visibility.y;
            highp float _18155 = 0.0;
            if (_12980 <= 0.0)
            {
                _18155 = 1.0;
            }
            else
            {
                _18155 = _12974 / (_12974 + (_12980 * _12980));
            }
            _18158 = _12930 * mix(1.0, max(0.0500000007450580596923828125, (_18155 * _18155) * _18155), frag_info.gi_visibility.x);
        }
        else
        {
            _18158 = _12930;
        }
        float _13008 = max(9.9999999747524270787835121154785e-07, _18158);
        float _18159 = 0.0;
        if (_13008 < 0.20000000298023223876953125)
        {
            _18159 = _13008 * ((_13008 * _13008) * 25.0);
        }
        else
        {
            _18159 = _13008;
        }
        float _13023 = _18159 * (((_12894.x * _12894.y) * _12894.z) * mp_copy_12888);
        highp float _13182 = floor(_13071 / frag_info.gi_counts.w);
        highp vec2 _13196 = vec2((_13071 - (_13182 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13182 * 8.0));
        vec3 _13244 = _18034 / vec3((abs(_18034.x) + abs(_18034.y)) + abs(_18034.z));
        bool _13247 = _13244.z >= 0.0;
        vec2 _18160 = vec2(0.0);
        if (_13247)
        {
            _18160 = _13244.xy;
        }
        else
        {
            _18160 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13035 = texture(irradiance_field, clamp((_13196 + vec2(1.0)) + (clamp((_18160 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13196 + vec2(0.5), _13196 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13330 = _12748 + vec3(1.0, 0.0, 0.0);
        highp vec3 _13335 = _13330 - frag_info.gi_anchor.xyz;
        bool _13338 = any(lessThan(_13335, vec3(0.0)));
        bool _13346 = false;
        if (!_13338)
        {
            _13346 = any(greaterThanEqual(_13335, frag_info.gi_counts.xyz));
        }
        else
        {
            _13346 = _13338;
        }
        vec3 mp_copy_18162 = vec3(0.0);
        highp float _13347 = _13346 ? 0.0 : 1.0;
        float mp_copy_13347 = _13347;
        vec3 _13353 = max(mix(_12890, mp_copy_12754, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13369 = (_13330 * frag_info.gi_grid.xyz) - _12743;
        highp float _13371 = length(_13369);
        highp vec3 _18162 = vec3(0.0);
        if (_13371 > 9.9999997473787516355514526367188e-06)
        {
            _18162 = _13369 / vec3(_13371);
        }
        else
        {
            _18162 = _18034;
        }
        mp_copy_18162 = _18162;
        float _13389 = pow((dot(_18162, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13514 = _13330 - (frag_info.gi_counts.xyz * floor(_13330 / frag_info.gi_counts.xyz));
        highp float _13530 = _13514.x + (frag_info.gi_counts.x * (_13514.y + (frag_info.gi_counts.y * _13514.z)));
        float _18167 = 0.0;
        if (_12941)
        {
            highp float _13538 = floor(_13530 / frag_info.gi_counts.w);
            highp vec2 _13552 = vec2((_13530 - (_13538 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13538 * 16.0));
            vec3 _13412 = -mp_copy_18162;
            vec3 _13600 = _13412 / vec3((abs(_13412.x) + abs(_13412.y)) + abs(_13412.z));
            vec2 _18163 = vec2(0.0);
            if (_13600.z >= 0.0)
            {
                _18163 = _13600.xy;
            }
            else
            {
                _18163 = (vec2(1.0) - abs(_13600.yx)) * vec2((_13600.x >= 0.0) ? 1.0 : (-1.0), (_13600.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13416 = texture(irradiance_field, clamp((_13552 + vec2(1.0)) + (clamp((_18163 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13552 + vec2(0.5), _13552 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13421 = _13416.x * frag_info.gi_visibility.z;
            highp float _13433 = abs((_13421 * _13421) - ((_13416.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13439 = (_13371 - _13421) - frag_info.gi_visibility.y;
            highp float _18164 = 0.0;
            if (_13439 <= 0.0)
            {
                _18164 = 1.0;
            }
            else
            {
                _18164 = _13433 / (_13433 + (_13439 * _13439));
            }
            _18167 = _13389 * mix(1.0, max(0.0500000007450580596923828125, (_18164 * _18164) * _18164), frag_info.gi_visibility.x);
        }
        else
        {
            _18167 = _13389;
        }
        float _13467 = max(9.9999999747524270787835121154785e-07, _18167);
        float _18168 = 0.0;
        if (_13467 < 0.20000000298023223876953125)
        {
            _18168 = _13467 * ((_13467 * _13467) * 25.0);
        }
        else
        {
            _18168 = _13467;
        }
        float _13482 = _18168 * (((_13353.x * _13353.y) * _13353.z) * mp_copy_13347);
        highp float _13641 = floor(_13530 / frag_info.gi_counts.w);
        highp vec2 _13655 = vec2((_13530 - (_13641 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13641 * 8.0));
        vec2 _18169 = vec2(0.0);
        if (_13247)
        {
            _18169 = _13244.xy;
        }
        else
        {
            _18169 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13494 = texture(irradiance_field, clamp((_13655 + vec2(1.0)) + (clamp((_18169 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13655 + vec2(0.5), _13655 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13789 = _12748 + vec3(0.0, 1.0, 0.0);
        highp vec3 _13794 = _13789 - frag_info.gi_anchor.xyz;
        bool _13797 = any(lessThan(_13794, vec3(0.0)));
        bool _13805 = false;
        if (!_13797)
        {
            _13805 = any(greaterThanEqual(_13794, frag_info.gi_counts.xyz));
        }
        else
        {
            _13805 = _13797;
        }
        vec3 mp_copy_18171 = vec3(0.0);
        highp float _13806 = _13805 ? 0.0 : 1.0;
        float mp_copy_13806 = _13806;
        vec3 _13812 = max(mix(_12890, mp_copy_12754, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13828 = (_13789 * frag_info.gi_grid.xyz) - _12743;
        highp float _13830 = length(_13828);
        highp vec3 _18171 = vec3(0.0);
        if (_13830 > 9.9999997473787516355514526367188e-06)
        {
            _18171 = _13828 / vec3(_13830);
        }
        else
        {
            _18171 = _18034;
        }
        mp_copy_18171 = _18171;
        float _13848 = pow((dot(_18171, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13973 = _13789 - (frag_info.gi_counts.xyz * floor(_13789 / frag_info.gi_counts.xyz));
        highp float _13989 = _13973.x + (frag_info.gi_counts.x * (_13973.y + (frag_info.gi_counts.y * _13973.z)));
        float _18176 = 0.0;
        if (_12941)
        {
            highp float _13997 = floor(_13989 / frag_info.gi_counts.w);
            highp vec2 _14011 = vec2((_13989 - (_13997 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13997 * 16.0));
            vec3 _13871 = -mp_copy_18171;
            vec3 _14059 = _13871 / vec3((abs(_13871.x) + abs(_13871.y)) + abs(_13871.z));
            vec2 _18172 = vec2(0.0);
            if (_14059.z >= 0.0)
            {
                _18172 = _14059.xy;
            }
            else
            {
                _18172 = (vec2(1.0) - abs(_14059.yx)) * vec2((_14059.x >= 0.0) ? 1.0 : (-1.0), (_14059.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13875 = texture(irradiance_field, clamp((_14011 + vec2(1.0)) + (clamp((_18172 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14011 + vec2(0.5), _14011 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13880 = _13875.x * frag_info.gi_visibility.z;
            highp float _13892 = abs((_13880 * _13880) - ((_13875.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13898 = (_13830 - _13880) - frag_info.gi_visibility.y;
            highp float _18173 = 0.0;
            if (_13898 <= 0.0)
            {
                _18173 = 1.0;
            }
            else
            {
                _18173 = _13892 / (_13892 + (_13898 * _13898));
            }
            _18176 = _13848 * mix(1.0, max(0.0500000007450580596923828125, (_18173 * _18173) * _18173), frag_info.gi_visibility.x);
        }
        else
        {
            _18176 = _13848;
        }
        float _13926 = max(9.9999999747524270787835121154785e-07, _18176);
        float _18177 = 0.0;
        if (_13926 < 0.20000000298023223876953125)
        {
            _18177 = _13926 * ((_13926 * _13926) * 25.0);
        }
        else
        {
            _18177 = _13926;
        }
        float _13941 = _18177 * (((_13812.x * _13812.y) * _13812.z) * mp_copy_13806);
        highp float _14100 = floor(_13989 / frag_info.gi_counts.w);
        highp vec2 _14114 = vec2((_13989 - (_14100 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14100 * 8.0));
        vec2 _18178 = vec2(0.0);
        if (_13247)
        {
            _18178 = _13244.xy;
        }
        else
        {
            _18178 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13953 = texture(irradiance_field, clamp((_14114 + vec2(1.0)) + (clamp((_18178 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14114 + vec2(0.5), _14114 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14248 = _12748 + vec3(1.0, 1.0, 0.0);
        highp vec3 _14253 = _14248 - frag_info.gi_anchor.xyz;
        bool _14256 = any(lessThan(_14253, vec3(0.0)));
        bool _14264 = false;
        if (!_14256)
        {
            _14264 = any(greaterThanEqual(_14253, frag_info.gi_counts.xyz));
        }
        else
        {
            _14264 = _14256;
        }
        vec3 mp_copy_18180 = vec3(0.0);
        highp float _14265 = _14264 ? 0.0 : 1.0;
        float mp_copy_14265 = _14265;
        vec3 _14271 = max(mix(_12890, mp_copy_12754, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14287 = (_14248 * frag_info.gi_grid.xyz) - _12743;
        highp float _14289 = length(_14287);
        highp vec3 _18180 = vec3(0.0);
        if (_14289 > 9.9999997473787516355514526367188e-06)
        {
            _18180 = _14287 / vec3(_14289);
        }
        else
        {
            _18180 = _18034;
        }
        mp_copy_18180 = _18180;
        float _14307 = pow((dot(_18180, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14432 = _14248 - (frag_info.gi_counts.xyz * floor(_14248 / frag_info.gi_counts.xyz));
        highp float _14448 = _14432.x + (frag_info.gi_counts.x * (_14432.y + (frag_info.gi_counts.y * _14432.z)));
        float _18185 = 0.0;
        if (_12941)
        {
            highp float _14456 = floor(_14448 / frag_info.gi_counts.w);
            highp vec2 _14470 = vec2((_14448 - (_14456 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14456 * 16.0));
            vec3 _14330 = -mp_copy_18180;
            vec3 _14518 = _14330 / vec3((abs(_14330.x) + abs(_14330.y)) + abs(_14330.z));
            vec2 _18181 = vec2(0.0);
            if (_14518.z >= 0.0)
            {
                _18181 = _14518.xy;
            }
            else
            {
                _18181 = (vec2(1.0) - abs(_14518.yx)) * vec2((_14518.x >= 0.0) ? 1.0 : (-1.0), (_14518.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14334 = texture(irradiance_field, clamp((_14470 + vec2(1.0)) + (clamp((_18181 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14470 + vec2(0.5), _14470 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14339 = _14334.x * frag_info.gi_visibility.z;
            highp float _14351 = abs((_14339 * _14339) - ((_14334.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14357 = (_14289 - _14339) - frag_info.gi_visibility.y;
            highp float _18182 = 0.0;
            if (_14357 <= 0.0)
            {
                _18182 = 1.0;
            }
            else
            {
                _18182 = _14351 / (_14351 + (_14357 * _14357));
            }
            _18185 = _14307 * mix(1.0, max(0.0500000007450580596923828125, (_18182 * _18182) * _18182), frag_info.gi_visibility.x);
        }
        else
        {
            _18185 = _14307;
        }
        float _14385 = max(9.9999999747524270787835121154785e-07, _18185);
        float _18186 = 0.0;
        if (_14385 < 0.20000000298023223876953125)
        {
            _18186 = _14385 * ((_14385 * _14385) * 25.0);
        }
        else
        {
            _18186 = _14385;
        }
        float _14400 = _18186 * (((_14271.x * _14271.y) * _14271.z) * mp_copy_14265);
        highp float _14559 = floor(_14448 / frag_info.gi_counts.w);
        highp vec2 _14573 = vec2((_14448 - (_14559 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14559 * 8.0));
        vec2 _18187 = vec2(0.0);
        if (_13247)
        {
            _18187 = _13244.xy;
        }
        else
        {
            _18187 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14412 = texture(irradiance_field, clamp((_14573 + vec2(1.0)) + (clamp((_18187 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14573 + vec2(0.5), _14573 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14707 = _12748 + vec3(0.0, 0.0, 1.0);
        highp vec3 _14712 = _14707 - frag_info.gi_anchor.xyz;
        bool _14715 = any(lessThan(_14712, vec3(0.0)));
        bool _14723 = false;
        if (!_14715)
        {
            _14723 = any(greaterThanEqual(_14712, frag_info.gi_counts.xyz));
        }
        else
        {
            _14723 = _14715;
        }
        vec3 mp_copy_18189 = vec3(0.0);
        highp float _14724 = _14723 ? 0.0 : 1.0;
        float mp_copy_14724 = _14724;
        vec3 _14730 = max(mix(_12890, mp_copy_12754, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14746 = (_14707 * frag_info.gi_grid.xyz) - _12743;
        highp float _14748 = length(_14746);
        highp vec3 _18189 = vec3(0.0);
        if (_14748 > 9.9999997473787516355514526367188e-06)
        {
            _18189 = _14746 / vec3(_14748);
        }
        else
        {
            _18189 = _18034;
        }
        mp_copy_18189 = _18189;
        float _14766 = pow((dot(_18189, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14891 = _14707 - (frag_info.gi_counts.xyz * floor(_14707 / frag_info.gi_counts.xyz));
        highp float _14907 = _14891.x + (frag_info.gi_counts.x * (_14891.y + (frag_info.gi_counts.y * _14891.z)));
        float _18194 = 0.0;
        if (_12941)
        {
            highp float _14915 = floor(_14907 / frag_info.gi_counts.w);
            highp vec2 _14929 = vec2((_14907 - (_14915 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14915 * 16.0));
            vec3 _14789 = -mp_copy_18189;
            vec3 _14977 = _14789 / vec3((abs(_14789.x) + abs(_14789.y)) + abs(_14789.z));
            vec2 _18190 = vec2(0.0);
            if (_14977.z >= 0.0)
            {
                _18190 = _14977.xy;
            }
            else
            {
                _18190 = (vec2(1.0) - abs(_14977.yx)) * vec2((_14977.x >= 0.0) ? 1.0 : (-1.0), (_14977.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14793 = texture(irradiance_field, clamp((_14929 + vec2(1.0)) + (clamp((_18190 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14929 + vec2(0.5), _14929 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14798 = _14793.x * frag_info.gi_visibility.z;
            highp float _14810 = abs((_14798 * _14798) - ((_14793.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14816 = (_14748 - _14798) - frag_info.gi_visibility.y;
            highp float _18191 = 0.0;
            if (_14816 <= 0.0)
            {
                _18191 = 1.0;
            }
            else
            {
                _18191 = _14810 / (_14810 + (_14816 * _14816));
            }
            _18194 = _14766 * mix(1.0, max(0.0500000007450580596923828125, (_18191 * _18191) * _18191), frag_info.gi_visibility.x);
        }
        else
        {
            _18194 = _14766;
        }
        float _14844 = max(9.9999999747524270787835121154785e-07, _18194);
        float _18195 = 0.0;
        if (_14844 < 0.20000000298023223876953125)
        {
            _18195 = _14844 * ((_14844 * _14844) * 25.0);
        }
        else
        {
            _18195 = _14844;
        }
        float _14859 = _18195 * (((_14730.x * _14730.y) * _14730.z) * mp_copy_14724);
        highp float _15018 = floor(_14907 / frag_info.gi_counts.w);
        highp vec2 _15032 = vec2((_14907 - (_15018 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15018 * 8.0));
        vec2 _18196 = vec2(0.0);
        if (_13247)
        {
            _18196 = _13244.xy;
        }
        else
        {
            _18196 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14871 = texture(irradiance_field, clamp((_15032 + vec2(1.0)) + (clamp((_18196 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15032 + vec2(0.5), _15032 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15166 = _12748 + vec3(1.0, 0.0, 1.0);
        highp vec3 _15171 = _15166 - frag_info.gi_anchor.xyz;
        bool _15174 = any(lessThan(_15171, vec3(0.0)));
        bool _15182 = false;
        if (!_15174)
        {
            _15182 = any(greaterThanEqual(_15171, frag_info.gi_counts.xyz));
        }
        else
        {
            _15182 = _15174;
        }
        vec3 mp_copy_18198 = vec3(0.0);
        highp float _15183 = _15182 ? 0.0 : 1.0;
        float mp_copy_15183 = _15183;
        vec3 _15189 = max(mix(_12890, mp_copy_12754, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15205 = (_15166 * frag_info.gi_grid.xyz) - _12743;
        highp float _15207 = length(_15205);
        highp vec3 _18198 = vec3(0.0);
        if (_15207 > 9.9999997473787516355514526367188e-06)
        {
            _18198 = _15205 / vec3(_15207);
        }
        else
        {
            _18198 = _18034;
        }
        mp_copy_18198 = _18198;
        float _15225 = pow((dot(_18198, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15350 = _15166 - (frag_info.gi_counts.xyz * floor(_15166 / frag_info.gi_counts.xyz));
        highp float _15366 = _15350.x + (frag_info.gi_counts.x * (_15350.y + (frag_info.gi_counts.y * _15350.z)));
        float _18203 = 0.0;
        if (_12941)
        {
            highp float _15374 = floor(_15366 / frag_info.gi_counts.w);
            highp vec2 _15388 = vec2((_15366 - (_15374 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15374 * 16.0));
            vec3 _15248 = -mp_copy_18198;
            vec3 _15436 = _15248 / vec3((abs(_15248.x) + abs(_15248.y)) + abs(_15248.z));
            vec2 _18199 = vec2(0.0);
            if (_15436.z >= 0.0)
            {
                _18199 = _15436.xy;
            }
            else
            {
                _18199 = (vec2(1.0) - abs(_15436.yx)) * vec2((_15436.x >= 0.0) ? 1.0 : (-1.0), (_15436.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15252 = texture(irradiance_field, clamp((_15388 + vec2(1.0)) + (clamp((_18199 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15388 + vec2(0.5), _15388 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15257 = _15252.x * frag_info.gi_visibility.z;
            highp float _15269 = abs((_15257 * _15257) - ((_15252.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15275 = (_15207 - _15257) - frag_info.gi_visibility.y;
            highp float _18200 = 0.0;
            if (_15275 <= 0.0)
            {
                _18200 = 1.0;
            }
            else
            {
                _18200 = _15269 / (_15269 + (_15275 * _15275));
            }
            _18203 = _15225 * mix(1.0, max(0.0500000007450580596923828125, (_18200 * _18200) * _18200), frag_info.gi_visibility.x);
        }
        else
        {
            _18203 = _15225;
        }
        float _15303 = max(9.9999999747524270787835121154785e-07, _18203);
        float _18204 = 0.0;
        if (_15303 < 0.20000000298023223876953125)
        {
            _18204 = _15303 * ((_15303 * _15303) * 25.0);
        }
        else
        {
            _18204 = _15303;
        }
        float _15318 = _18204 * (((_15189.x * _15189.y) * _15189.z) * mp_copy_15183);
        highp float _15477 = floor(_15366 / frag_info.gi_counts.w);
        highp vec2 _15491 = vec2((_15366 - (_15477 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15477 * 8.0));
        vec2 _18205 = vec2(0.0);
        if (_13247)
        {
            _18205 = _13244.xy;
        }
        else
        {
            _18205 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15330 = texture(irradiance_field, clamp((_15491 + vec2(1.0)) + (clamp((_18205 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15491 + vec2(0.5), _15491 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15625 = _12748 + vec3(0.0, 1.0, 1.0);
        highp vec3 _15630 = _15625 - frag_info.gi_anchor.xyz;
        bool _15633 = any(lessThan(_15630, vec3(0.0)));
        bool _15641 = false;
        if (!_15633)
        {
            _15641 = any(greaterThanEqual(_15630, frag_info.gi_counts.xyz));
        }
        else
        {
            _15641 = _15633;
        }
        vec3 mp_copy_18207 = vec3(0.0);
        highp float _15642 = _15641 ? 0.0 : 1.0;
        float mp_copy_15642 = _15642;
        vec3 _15648 = max(mix(_12890, mp_copy_12754, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15664 = (_15625 * frag_info.gi_grid.xyz) - _12743;
        highp float _15666 = length(_15664);
        highp vec3 _18207 = vec3(0.0);
        if (_15666 > 9.9999997473787516355514526367188e-06)
        {
            _18207 = _15664 / vec3(_15666);
        }
        else
        {
            _18207 = _18034;
        }
        mp_copy_18207 = _18207;
        float _15684 = pow((dot(_18207, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15809 = _15625 - (frag_info.gi_counts.xyz * floor(_15625 / frag_info.gi_counts.xyz));
        highp float _15825 = _15809.x + (frag_info.gi_counts.x * (_15809.y + (frag_info.gi_counts.y * _15809.z)));
        float _18212 = 0.0;
        if (_12941)
        {
            highp float _15833 = floor(_15825 / frag_info.gi_counts.w);
            highp vec2 _15847 = vec2((_15825 - (_15833 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15833 * 16.0));
            vec3 _15707 = -mp_copy_18207;
            vec3 _15895 = _15707 / vec3((abs(_15707.x) + abs(_15707.y)) + abs(_15707.z));
            vec2 _18208 = vec2(0.0);
            if (_15895.z >= 0.0)
            {
                _18208 = _15895.xy;
            }
            else
            {
                _18208 = (vec2(1.0) - abs(_15895.yx)) * vec2((_15895.x >= 0.0) ? 1.0 : (-1.0), (_15895.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15711 = texture(irradiance_field, clamp((_15847 + vec2(1.0)) + (clamp((_18208 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15847 + vec2(0.5), _15847 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15716 = _15711.x * frag_info.gi_visibility.z;
            highp float _15728 = abs((_15716 * _15716) - ((_15711.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15734 = (_15666 - _15716) - frag_info.gi_visibility.y;
            highp float _18209 = 0.0;
            if (_15734 <= 0.0)
            {
                _18209 = 1.0;
            }
            else
            {
                _18209 = _15728 / (_15728 + (_15734 * _15734));
            }
            _18212 = _15684 * mix(1.0, max(0.0500000007450580596923828125, (_18209 * _18209) * _18209), frag_info.gi_visibility.x);
        }
        else
        {
            _18212 = _15684;
        }
        float _15762 = max(9.9999999747524270787835121154785e-07, _18212);
        float _18213 = 0.0;
        if (_15762 < 0.20000000298023223876953125)
        {
            _18213 = _15762 * ((_15762 * _15762) * 25.0);
        }
        else
        {
            _18213 = _15762;
        }
        float _15777 = _18213 * (((_15648.x * _15648.y) * _15648.z) * mp_copy_15642);
        highp float _15936 = floor(_15825 / frag_info.gi_counts.w);
        highp vec2 _15950 = vec2((_15825 - (_15936 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15936 * 8.0));
        vec2 _18214 = vec2(0.0);
        if (_13247)
        {
            _18214 = _13244.xy;
        }
        else
        {
            _18214 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15789 = texture(irradiance_field, clamp((_15950 + vec2(1.0)) + (clamp((_18214 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15950 + vec2(0.5), _15950 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _16084 = _12748 + vec3(1.0);
        highp vec3 _16089 = _16084 - frag_info.gi_anchor.xyz;
        bool _16092 = any(lessThan(_16089, vec3(0.0)));
        bool _16100 = false;
        if (!_16092)
        {
            _16100 = any(greaterThanEqual(_16089, frag_info.gi_counts.xyz));
        }
        else
        {
            _16100 = _16092;
        }
        vec3 mp_copy_18216 = vec3(0.0);
        highp float _16101 = _16100 ? 0.0 : 1.0;
        float mp_copy_16101 = _16101;
        vec3 _16107 = max(mp_copy_12754, vec3(0.001000000047497451305389404296875));
        highp vec3 _16123 = (_16084 * frag_info.gi_grid.xyz) - _12743;
        highp float _16125 = length(_16123);
        highp vec3 _18216 = vec3(0.0);
        if (_16125 > 9.9999997473787516355514526367188e-06)
        {
            _18216 = _16123 / vec3(_16125);
        }
        else
        {
            _18216 = _18034;
        }
        mp_copy_18216 = _18216;
        float _16143 = pow((dot(_18216, _18034) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _16268 = _16084 - (frag_info.gi_counts.xyz * floor(_16084 / frag_info.gi_counts.xyz));
        highp float _16284 = _16268.x + (frag_info.gi_counts.x * (_16268.y + (frag_info.gi_counts.y * _16268.z)));
        float _18221 = 0.0;
        if (_12941)
        {
            highp float _16292 = floor(_16284 / frag_info.gi_counts.w);
            highp vec2 _16306 = vec2((_16284 - (_16292 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16292 * 16.0));
            vec3 _16166 = -mp_copy_18216;
            vec3 _16354 = _16166 / vec3((abs(_16166.x) + abs(_16166.y)) + abs(_16166.z));
            vec2 _18217 = vec2(0.0);
            if (_16354.z >= 0.0)
            {
                _18217 = _16354.xy;
            }
            else
            {
                _18217 = (vec2(1.0) - abs(_16354.yx)) * vec2((_16354.x >= 0.0) ? 1.0 : (-1.0), (_16354.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _16170 = texture(irradiance_field, clamp((_16306 + vec2(1.0)) + (clamp((_18217 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16306 + vec2(0.5), _16306 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _16175 = _16170.x * frag_info.gi_visibility.z;
            highp float _16187 = abs((_16175 * _16175) - ((_16170.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _16193 = (_16125 - _16175) - frag_info.gi_visibility.y;
            highp float _18218 = 0.0;
            if (_16193 <= 0.0)
            {
                _18218 = 1.0;
            }
            else
            {
                _18218 = _16187 / (_16187 + (_16193 * _16193));
            }
            _18221 = _16143 * mix(1.0, max(0.0500000007450580596923828125, (_18218 * _18218) * _18218), frag_info.gi_visibility.x);
        }
        else
        {
            _18221 = _16143;
        }
        float _16221 = max(9.9999999747524270787835121154785e-07, _18221);
        float _18222 = 0.0;
        if (_16221 < 0.20000000298023223876953125)
        {
            _18222 = _16221 * ((_16221 * _16221) * 25.0);
        }
        else
        {
            _18222 = _16221;
        }
        float _16236 = _18222 * (((_16107.x * _16107.y) * _16107.z) * mp_copy_16101);
        highp float _16395 = floor(_16284 / frag_info.gi_counts.w);
        highp vec2 _16409 = vec2((_16284 - (_16395 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16395 * 8.0));
        vec2 _18223 = vec2(0.0);
        if (_13247)
        {
            _18223 = _13244.xy;
        }
        else
        {
            _18223 = (vec2(1.0) - abs(_13244.yx)) * vec2((_13244.x >= 0.0) ? 1.0 : (-1.0), (_13244.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12801 = ((((((vec4(max(_13035.xyz, vec3(0.0)) * _13023, _13023) + vec4(max(_13494.xyz, vec3(0.0)) * _13482, _13482)) + vec4(max(_13953.xyz, vec3(0.0)) * _13941, _13941)) + vec4(max(_14412.xyz, vec3(0.0)) * _14400, _14400)) + vec4(max(_14871.xyz, vec3(0.0)) * _14859, _14859)) + vec4(max(_15330.xyz, vec3(0.0)) * _15318, _15318)) + vec4(max(_15789.xyz, vec3(0.0)) * _15777, _15777)) + vec4(max(texture(irradiance_field, clamp((_16409 + vec2(1.0)) + (clamp((_18223 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16409 + vec2(0.5), _16409 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _16236, _16236);
        highp float _12803 = _12801.w;
        highp vec3 _18225 = vec3(0.0);
        if (_12803 > 9.9999999747524270787835121154785e-07)
        {
            _18225 = _12801.xyz / vec3(_12803);
        }
        else
        {
            _18225 = vec3(0.0);
        }
        _18343 = mix(_7580, _18225 * _12630, vec3(_18152));
    }
    else
    {
        _18343 = _7580;
    }
    vec2 _7606 = clamp(vec2(_7146, _18082), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7608 = texture(brdf_lut, vec2(_7606.x * 0.3333333432674407958984375, _7606.y));
    float _7612 = _7608.x;
    float _7615 = _7608.y;
    vec3 _7617 = ((_7138 + ((max(vec3(1.0 - _18082), _7138) - _7138) * pow(clamp(1.0 - _7146, 0.0, 1.0), 5.0))) * _7612) + vec3(_7615);
    float _7623 = 1.0 - (_7612 + _7615);
    vec3 _7627 = vec3(1.0) - _7138;
    vec3 _7630 = _7138 + (_7627 * vec3(0.0476190485060214996337890625));
    vec3 _7641 = ((_7617 * _7623) * _7630) / (vec3(1.0) - (_7630 * _7623));
    float _7644 = 1.0 - _6090;
    vec3 _7645 = _6990 * _7644;
    float _18618 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7540)
    {
        float _16517 = max(acos(clamp(exp2(((-3.321929931640625) * _18082) * _18082), 0.0, 1.0)), 0.100000001490116119384765625);
        _18618 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_18140, _7150), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _18420, 0.0, 1.0)))) + _16517) / (2.0 * _16517), 0.0, 1.0));
    }
    else
    {
        float _18619 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _18619 = clamp((pow(_7142 + _18420, exp2(((-16.0) * _18082) - 1.0)) - 1.0) + _18420, 0.0, 1.0);
        }
        else
        {
            _18619 = _18420;
        }
        _18618 = _18619;
    }
    highp vec3 _7704 = ((((_7641 + (_7645 * ((vec3(1.0) - _7617) - _7641))) * _18343) * _18557) + (((_7617 * (_18151 * frag_info.environment_intensity)) * 1.0) * _18618)) * mix(1.0, _7129, frag_info.radiance_blend.y);
    highp vec3 _18847 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _18847 = _7704 + ((_18107.xyz * _7645) * _6124);
    }
    else
    {
        _18847 = _7704;
    }
    highp vec3 _18851 = vec3(0.0);
    if (_7079)
    {
        highp vec3 _18767 = vec3(0.0);
        highp vec3 _18768 = vec3(0.0);
        do
        {
            float _16614 = max(dot(_18034, _18703), 0.0);
            highp float hp_copy_16614 = _16614;
            if (_16614 <= 0.0)
            {
                _18768 = vec3(0.0);
                _18767 = vec3(0.0);
                break;
            }
            float _16620 = max(_7142, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_16620 = _16620;
            vec3 _16623 = _18703 + mp_copy_18112;
            float _16626 = dot(_16623, _16623);
            vec3 _18765 = vec3(0.0);
            vec3 _18766 = vec3(0.0);
            if (_16626 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _16634 = _16623 * inversesqrt(_16626);
                float _18764 = 0.0;
                do
                {
                    float _16691 = dot(_18034, _16634);
                    if (_16691 <= 0.0)
                    {
                        _18764 = 0.0;
                        break;
                    }
                    float _16698 = _18082 * _18082;
                    vec3 _16701 = cross(_18034, _16634);
                    float _16704 = _16691 * _16698;
                    float _16713 = _16698 / (dot(_16701, _16701) + (_16704 * _16704));
                    _18764 = min((_16713 * _16713) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _16751 = _7138 + (_7627 * pow(clamp(1.0 - max(dot(_16634, _18112), 0.0), 0.0, 1.0), 5.0));
                _18766 = (_16751 * min(_18764 * (0.5 / max(mix((2.0 * hp_copy_16614) * _16620, hp_copy_16614 + hp_copy_16620, hp_copy_18082 * hp_copy_18082), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _18765 = _16751;
            }
            else
            {
                _18766 = vec3(0.0);
                _18765 = _7138;
            }
            _18768 = (_18766 * frag_info.directional_light_color.xyz) * _16614;
            _18767 = (((((vec3(1.0) - _18765) * _7644) * _6990) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _16614;
            break;
        } while(false);
        _18851 = _18776 + ((_18767 + _18768) * _7129);
    }
    else
    {
        _18851 = _18776;
    }
    bool _7766 = _FogInfo.params0.y > 0.5;
    bool _7772 = false;
    if (_7766)
    {
        _7772 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7772 = _7766;
    }
    highp vec3 _18856 = vec3(0.0);
    if (_7772)
    {
        vec3 mp_copy_18852 = vec3(0.0);
        highp vec3 _18852 = vec3(0.0);
        if (_9773)
        {
            _18852 = -view_info.camera_forward.xyz;
        }
        else
        {
            _18852 = normalize(v_viewvector);
        }
        mp_copy_18852 = _18852;
        vec3 _7777 = _7537 * (-mp_copy_18852);
        vec3 _18853 = vec3(0.0);
        do
        {
            if (_12202)
            {
                vec2 _16873 = vec2(atan(_7777.z, _7777.x), asin(clamp(_7777.y, -1.0, 1.0)));
                highp vec2 hp_copy_16873 = _16873;
                _18853 = textureLod(prefiltered_radiance, (hp_copy_16873 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _16892 = vec2(atan(_7777.z, _7777.x), asin(clamp(_7777.y, -1.0, 1.0)));
            highp vec2 hp_copy_16892 = _16892;
            highp vec2 _16897 = (hp_copy_16892 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _16804 = clamp(_16897.y, 0.00390625, 0.99609375);
            float _16810 = floor(0.0);
            highp float _16829 = _16897.x;
            _18853 = mix(textureLod(prefiltered_radiance, vec2(_16829, (_16810 + _16804) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_16829, (min(_16810 + 1.0, 7.0) + _16804) * 0.125), 0.0).xyz, vec3(-_16810));
            break;
        } while(false);
        highp vec3 _18855 = vec3(0.0);
        if (_7558)
        {
            vec3 _18854 = vec3(0.0);
            do
            {
                if (_12202)
                {
                    vec2 _17002 = vec2(atan(_7777.z, _7777.x), asin(clamp(_7777.y, -1.0, 1.0)));
                    highp vec2 hp_copy_17002 = _17002;
                    _18854 = textureLod(prefiltered_radiance_b, (hp_copy_17002 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _17021 = vec2(atan(_7777.z, _7777.x), asin(clamp(_7777.y, -1.0, 1.0)));
                highp vec2 hp_copy_17021 = _17021;
                highp vec2 _17026 = (hp_copy_17021 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _16933 = clamp(_17026.y, 0.00390625, 0.99609375);
                float _16939 = floor(0.0);
                highp float _16958 = _17026.x;
                _18854 = mix(textureLod(prefiltered_radiance_b, vec2(_16958, (_16939 + _16933) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_16958, (min(_16939 + 1.0, 7.0) + _16933) * 0.125), 0.0).xyz, vec3(-_16939));
                break;
            } while(false);
            _18855 = mix(_18853, _18854, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _18855 = _18853;
        }
        _18856 = _18855 * frag_info.environment_intensity;
    }
    else
    {
        _18856 = _FogInfo.color.xyz;
    }
    highp vec4 _7801 = vec4(min((_18847 + (_18851 * mix(1.0, _18420, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _18057, vec3(65504.0)), 1.0) * _19659;
    highp vec4 _18871 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _18871 = _7801;
            break;
        }
        int _17070 = int(_FogInfo.params0.x + 0.5);
        if (_17070 == 0)
        {
            _18871 = _7801;
            break;
        }
        highp float _18858 = 0.0;
        if (_9773)
        {
            _18858 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _18858 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_18858 > _FogInfo.params1.w))
        {
            _18871 = _7801;
            break;
        }
        float _18862 = 0.0;
        if (_17070 == 1)
        {
            _18862 = clamp((_18858 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _18863 = 0.0;
            if (_17070 == 2)
            {
                highp float _18861 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _18859 = vec3(0.0);
                    if (_9773)
                    {
                        _18859 = v_position - (view_info.camera_forward.xyz * _18858);
                    }
                    else
                    {
                        _18859 = v_position + v_viewvector;
                    }
                    highp float _17151 = -_FogInfo.params2.y;
                    highp float _17158 = _FogInfo.params1.x * exp(_17151 * (_18859.y - _FogInfo.params2.x));
                    highp float _17175 = _FogInfo.params2.y * (v_position.y - _18859.y);
                    highp float _18860 = 0.0;
                    if (abs(_17175) > 0.00124999997206032276153564453125)
                    {
                        _18860 = (_17158 - (_FogInfo.params1.x * exp(_17151 * (v_position.y - _FogInfo.params2.x)))) / _17175;
                    }
                    else
                    {
                        _18860 = _17158;
                    }
                    _18861 = _18860 * max(_18858 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _18861 = _FogInfo.params1.x * max(_18858 - _FogInfo.params1.y, 0.0);
                }
                _18863 = 1.0 - exp(-_18861);
            }
            else
            {
                highp float _17213 = _FogInfo.params1.x * max(_18858 - _FogInfo.params1.y, 0.0);
                _18863 = 1.0 - exp((-_17213) * _17213);
            }
            _18862 = _18863;
        }
        highp float _17225 = min(_18862, _FogInfo.params0.z);
        if (_17225 <= 0.0)
        {
            _18871 = _7801;
            break;
        }
        highp vec3 _17238 = mix(_FogInfo.color.xyz, _18856, vec3(_FogInfo.params0.w));
        bool _17241 = _FogInfo.sun.w > 0.5;
        bool _17247 = false;
        if (_17241)
        {
            _17247 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _17247 = _17241;
        }
        vec3 _18867 = vec3(0.0);
        if (_17247)
        {
            vec3 mp_copy_18864 = vec3(0.0);
            highp vec3 _18864 = vec3(0.0);
            if (_9773)
            {
                _18864 = -view_info.camera_forward.xyz;
            }
            else
            {
                _18864 = normalize(v_viewvector);
            }
            mp_copy_18864 = _18864;
            highp float _17263 = pow(max(dot(-mp_copy_18864, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_17263 = _17263;
            _18867 = _17238 + ((_FogInfo.sun.xyz * mp_copy_17263) * _FogInfo.params2.z);
        }
        else
        {
            _18867 = _17238;
        }
        highp float _17276 = _7801.w;
        float mp_copy_17276 = _17276;
        _18871 = vec4(mix(_7801.xyz, _18867 * mp_copy_17276, vec3(_17225)), _17276);
        break;
    } while(false);
    vec4 _18873 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _18873 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _18873 = _18871;
        break;
    } while(false);
    frag_color = _18873;
    float _18874 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _18874 = 1.0;
    }
    else
    {
        _18874 = abs(frag_info.fade);
    }
    frag_color *= _18874;
}

