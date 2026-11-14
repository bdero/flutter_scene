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
    highp float _6011 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_6011 = _6011;
    vec3 _6015 = normalize(v_normal) * mp_copy_6011;
    vec4 _6057 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _6060 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _17789 = vec2(0.0);
    if (_6060)
    {
        highp vec2 _17788 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _17788 = v_texture_coords_1;
        }
        else
        {
            _17788 = v_texture_coords;
        }
        highp vec2 _6263 = _17788 * texture_transforms.base_color_transform.zw;
        highp float _6269 = _6263.x;
        highp float _6274 = _6263.y;
        _17789 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6269) + (texture_transforms.base_color_rotation.y * _6274), ((-texture_transforms.base_color_rotation.y) * _6269) + (texture_transforms.base_color_rotation.x * _6274));
    }
    else
    {
        _17789 = v_texture_coords;
    }
    vec4 _6074 = texture(base_color_texture, _17789);
    vec3 _6076 = _6074.xyz;
    float _19426 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_6074.w * _6057.w) * frag_info.color.w);
    vec3 _17804 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _17792 = vec2(0.0);
        if (_6060)
        {
            highp vec2 _17791 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _17791 = v_texture_coords_1;
            }
            else
            {
                _17791 = v_texture_coords;
            }
            highp vec2 _6358 = _17791 * texture_transforms.normal_transform.zw;
            highp float _6364 = _6358.x;
            highp float _6369 = _6358.y;
            _17792 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6364) + (texture_transforms.normal_rotation.y * _6369), ((-texture_transforms.normal_rotation.y) * _6364) + (texture_transforms.normal_rotation.x * _6369));
        }
        else
        {
            _17792 = v_texture_coords;
        }
        vec3 _6414 = ((texture(normal_texture, _17792).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6418 = _6414.xy * vec2(frag_info.normal_scale);
        vec3 _17251 = _6414;
        _17251.x = _6418.x;
        _17251.y = _6418.y;
        highp vec3 _6424 = -v_viewvector;
        highp vec3 _6514 = dFdx(_6424);
        highp vec3 _6516 = dFdy(_6424);
        highp vec2 _6518 = dFdx(_17792);
        highp vec2 _6520 = dFdy(_17792);
        bvec2 _19428 = bvec2(length(_6518) == 0.0);
        highp vec2 _19429 = vec2(_19428.x ? vec2(1.0, 0.0).x : _6518.x, _19428.y ? vec2(1.0, 0.0).y : _6518.y);
        bvec2 _19430 = bvec2(length(_6520) == 0.0);
        highp vec2 _19431 = vec2(_19430.x ? vec2(0.0, 1.0).x : _6520.x, _19430.y ? vec2(0.0, 1.0).y : _6520.y);
        highp vec3 _6533 = cross(_6516, _6015);
        highp vec3 _6536 = cross(_6015, _6514);
        highp float _6561 = (dot(cross(_6514, _6516), _6015) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6564 = ((_6533 * _19429.x) + (_6536 * _19431.x)) * _6561;
        highp float _17799 = 0.0;
        if (gl_FrontFacing)
        {
            _17799 = -_6561;
        }
        else
        {
            _17799 = _6561;
        }
        highp vec3 _6574 = ((_6533 * _19429.y) + (_6536 * _19431.y)) * _17799;
        highp float _6583 = inversesqrt(max(max(dot(_6564, _6564), dot(_6574, _6574)), 9.9999996826552253889678874634872e-21));
        vec3 _6455 = v_tangent.xyz - (_6015 * dot(_6015, v_tangent.xyz));
        highp float _6458 = dot(_6455, _6455);
        bool _6460 = _6458 > 1.0000000133514319600180897396058e-10;
        bool _6467 = false;
        if (_6460)
        {
            _6467 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6467 = _6460;
        }
        mat3 _17802 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6467)
        {
            highp vec3 _6472 = _6455 * inversesqrt(_6458);
            _17802 = mat3(_6472, normalize(cross(_6015, _6472)) * sign(v_tangent.w), _6015);
        }
        else
        {
            _17802 = mat3(_6564 * _6583, _6574 * _6583, _6015);
        }
        _17804 = normalize(_17802 * _17251);
    }
    else
    {
        _17804 = _6015;
    }
    highp vec2 _17806 = vec2(0.0);
    if (_6060)
    {
        highp vec2 _17805 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _17805 = v_texture_coords_1;
        }
        else
        {
            _17805 = v_texture_coords;
        }
        highp vec2 _6651 = _17805 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6657 = _6651.x;
        highp float _6662 = _6651.y;
        _17806 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6657) + (texture_transforms.metallic_roughness_rotation.y * _6662), ((-texture_transforms.metallic_roughness_rotation.y) * _6657) + (texture_transforms.metallic_roughness_rotation.x * _6662));
    }
    else
    {
        _17806 = v_texture_coords;
    }
    vec4 _6143 = texture(metallic_roughness_texture, _17806);
    float _6149 = clamp(_6143.z * frag_info.metallic_factor, 0.0, 1.0);
    float _6156 = clamp(_6143.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _17808 = vec2(0.0);
    if (_6060)
    {
        highp vec2 _17807 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _17807 = v_texture_coords_1;
        }
        else
        {
            _17807 = v_texture_coords;
        }
        highp vec2 _6722 = _17807 * texture_transforms.occlusion_transform.zw;
        highp float _6728 = _6722.x;
        highp float _6733 = _6722.y;
        _17808 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6728) + (texture_transforms.occlusion_rotation.y * _6733), ((-texture_transforms.occlusion_rotation.y) * _6728) + (texture_transforms.occlusion_rotation.x * _6733));
    }
    else
    {
        _17808 = v_texture_coords;
    }
    float _17809 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _17809 = texture(occlusion_texture, _17808).x;
    }
    else
    {
        _17809 = 1.0;
    }
    float _6183 = 1.0 - ((1.0 - _17809) * frag_info.occlusion_strength);
    highp vec2 _17811 = vec2(0.0);
    if (_6060)
    {
        highp vec2 _17810 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _17810 = v_texture_coords_1;
        }
        else
        {
            _17810 = v_texture_coords;
        }
        highp vec2 _6793 = _17810 * texture_transforms.emissive_transform.zw;
        highp float _6799 = _6793.x;
        highp float _6804 = _6793.y;
        _17811 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6799) + (texture_transforms.emissive_rotation.y * _6804), ((-texture_transforms.emissive_rotation.y) * _6799) + (texture_transforms.emissive_rotation.x * _6804));
    }
    else
    {
        _17811 = v_texture_coords;
    }
    vec3 _6202 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _17827 = vec3(0.0);
    if (dot(abs(_6202), vec3(1.0)) > 0.0)
    {
        vec3 _6211 = texture(emissive_texture, _17811).xyz;
        _17827 = mix(_6211 * vec3(0.077399380505084991455078125), pow((_6211 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6211)) * _6202;
    }
    else
    {
        _17827 = vec3(0.0);
    }
    highp float hp_copy_17852 = 0.0;
    vec3 _7046 = vec4((mix(_6076 * vec3(0.077399380505084991455078125), pow((_6076 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6076)) * _6057.xyz) * frag_info.color.xyz, _19426).xyz;
    vec3 _7850 = dFdx(_17804);
    vec3 _7852 = dFdy(_17804);
    float _17852 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _17852 = sqrt(clamp((_6156 * _6156) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7850, _7850), dot(_7852, _7852))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _17852 = _6156;
    }
    hp_copy_17852 = _17852;
    vec4 _17875 = vec4(0.0);
    float _17893 = 0.0;
    vec3 _17908 = vec3(0.0);
    float _18191 = 0.0;
    vec3 _18331 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _7073 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _17853 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _17853 = _7073.w;
        }
        else
        {
            _17853 = _7073.x;
        }
        float _7086 = min(_6183, _17853);
        bool _7089 = frag_info.ssao_lighting.z > 0.5;
        bool _7095 = false;
        if (_7089)
        {
            _7095 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _7095 = _7089;
        }
        vec3 _17909 = vec3(0.0);
        if (_7095)
        {
            vec2 _7890 = (_7073.zw * 2.0) - vec2(1.0);
            float _7892 = _7890.x;
            float _7894 = _7890.y;
            float _7902 = (1.0 - abs(_7892)) - abs(_7894);
            vec3 _7903 = vec3(_7892, _7894, _7902);
            vec3 _17856 = vec3(0.0);
            if (_7902 < 0.0)
            {
                vec2 _7916 = (vec2(1.0) - abs(_7903.yx)) * vec2((_7892 >= 0.0) ? 1.0 : (-1.0), (_7894 >= 0.0) ? 1.0 : (-1.0));
                vec3 _17300 = _7903;
                _17300.x = _7916.x;
                _17300.y = _7916.y;
                _17856 = _17300;
            }
            else
            {
                _17856 = _7903;
            }
            vec3 _7924 = -normalize(_17856);
            _17909 = normalize(((frag_info.camera_right.xyz * _7924.x) + (frag_info.camera_up.xyz * _7924.y)) + (frag_info.camera_forward.xyz * _7924.z));
        }
        else
        {
            _17909 = vec3(0.0);
        }
        vec3 _7123 = vec3(_7086);
        _18331 = mix(_7123, max(_7123, ((((((_7046 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _7086) + ((_7046 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _7086) + ((_7046 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _7086), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _18191 = _7086;
        _17908 = _17909;
        _17893 = float(_7095);
        _17875 = _7073;
    }
    else
    {
        _18331 = vec3(_6183);
        _18191 = _6183;
        _17908 = vec3(0.0);
        _17893 = 0.0;
        _17875 = vec4(1.0);
    }
    bool _7135 = frag_info.has_directional_light > 0.5;
    float _17860 = 0.0;
    vec3 _18479 = vec3(0.0);
    if (_7135)
    {
        highp vec3 _7141 = -normalize(frag_info.directional_light_direction.xyz);
        _18479 = _7141;
        _17860 = dot(_6015, _7141);
    }
    else
    {
        _18479 = vec3(0.0);
        _17860 = 0.0;
    }
    float _7148 = clamp(_17860 * 6.666666507720947265625, 0.0, 1.0);
    bool _7157 = false;
    if (_7135)
    {
        _7157 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _7157 = _7135;
    }
    float _17869 = 0.0;
    if (_7157 && (_7148 > 0.0))
    {
        int _8015 = int(frag_info.shadow_cascade_count);
        float _8210 = max(dot(_6015, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _8213 = _8210 * _8210;
        highp vec3 _8233 = v_position + (_6015 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _8213, 0.0)) / _8213, 8.0))));
        highp float _8021 = frag_info.directional_light_color.w * 0.5;
        float _8023 = frag_info.dielectric_f0.w;
        highp float hp_copy_8023 = _8023;
        float _17861 = 0.0;
        if (_8023 > 0.0)
        {
            _17861 = smoothstep(_8023 - max(frag_info.shadow_fade, hp_copy_8023 * 0.100000001490116119384765625), _8023, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _17861 = 0.0;
        }
        float _17863 = 0.0;
        float _17865 = 0.0;
        if (_17861 < 1.0)
        {
            float _17864 = 0.0;
            float _17866 = 0.0;
            _17866 = 0.0;
            _17864 = 0.0;
            float _18959 = 0.0;
            float _18962 = 0.0;
            for (int _17862 = 0; _17862 < _8015; _17866 = _18962, _17864 = _18959, _17862++)
            {
                if (_17866 < 1.0)
                {
                    highp vec4 _8055 = vec4(_8233, 1.0);
                    highp vec4 _18831 = vec4(0.0);
                    highp float _18834 = 0.0;
                    if (_17862 == 0)
                    {
                        _18834 = frag_info.cascade_box_sizes.x;
                        _18831 = frag_info.light_space_matrix[0] * _8055;
                    }
                    else
                    {
                        highp vec4 _18832 = vec4(0.0);
                        highp float _18835 = 0.0;
                        if (_17862 == 1)
                        {
                            _18835 = frag_info.cascade_box_sizes.y;
                            _18832 = frag_info.light_space_matrix[1] * _8055;
                        }
                        else
                        {
                            highp vec4 _18833 = vec4(0.0);
                            highp float _18836 = 0.0;
                            if (_17862 == 2)
                            {
                                _18836 = frag_info.cascade_box_sizes.z;
                                _18833 = frag_info.light_space_matrix[2] * _8055;
                            }
                            else
                            {
                                _18836 = frag_info.cascade_box_sizes.w;
                                _18833 = frag_info.light_space_matrix[3] * _8055;
                            }
                            _18835 = _18836;
                            _18832 = _18833;
                        }
                        _18834 = _18835;
                        _18831 = _18832;
                    }
                    highp vec3 _8100 = _18831.xyz / vec3(_18831.w);
                    highp vec2 _8103 = _8100.xy * 0.5;
                    highp vec2 _8105 = _8103 + vec2(0.5);
                    highp float _8112 = max(frag_info.shadow_softness / _18834, frag_info.shadow_texel_size);
                    highp float _8114 = _8105.x;
                    bool _8116 = _8114 < _8112;
                    bool _8125 = false;
                    if (!_8116)
                    {
                        _8125 = _8114 > (1.0 - _8112);
                    }
                    else
                    {
                        _8125 = _8116;
                    }
                    bool _8133 = false;
                    if (!_8125)
                    {
                        _8133 = _8105.y < _8112;
                    }
                    else
                    {
                        _8133 = _8125;
                    }
                    bool _8142 = false;
                    if (!_8133)
                    {
                        _8142 = _8105.y > (1.0 - _8112);
                    }
                    else
                    {
                        _8142 = _8133;
                    }
                    bool _8149 = false;
                    if (!_8142)
                    {
                        _8149 = _8100.z < 0.0;
                    }
                    else
                    {
                        _8149 = _8142;
                    }
                    bool _8156 = false;
                    if (!_8149)
                    {
                        _8156 = _8100.z > 1.0;
                    }
                    else
                    {
                        _8156 = _8149;
                    }
                    float _18960 = 0.0;
                    float _18963 = 0.0;
                    if (!_8156)
                    {
                        highp vec2 _8249 = vec2(_8112);
                        highp vec2 _8254 = vec2(_8112 + max(_8021, 9.9999997473787516355514526367188e-05));
                        highp vec2 _8262 = vec2(0.5) - _8103;
                        highp vec2 _8264 = smoothstep(_8249, _8254, _8105) * smoothstep(_8249, _8254, _8262);
                        float _18837 = 0.0;
                        if (_8021 > 0.0)
                        {
                            _18837 = _8264.x * _8264.y;
                        }
                        else
                        {
                            _18837 = 1.0;
                        }
                        float _8165 = min(_18837, 1.0 - _17866);
                        float _18961 = 0.0;
                        float _18964 = 0.0;
                        if (_8165 > 0.0)
                        {
                            highp float _8403 = _8100.z - (frag_info.shadow_bias / (7.0 * _18834));
                            highp float _8409 = 1.0 / (float(_8015) + frag_info.spot_shadow_params.x);
                            highp float _8411 = frag_info.directional_light_direction.w;
                            float mp_copy_8411 = _8411;
                            float _8417 = step(0.5, mp_copy_8411) * (1.0 - step(1.5, mp_copy_8411));
                            float _18867 = 0.0;
                            float _18871 = 0.0;
                            if (_8417 < 0.5)
                            {
                                highp float _8428 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_8428 = _8428;
                                _18871 = sin(mp_copy_8428);
                                _18867 = cos(mp_copy_8428);
                            }
                            else
                            {
                                _18871 = 0.0;
                                _18867 = 1.0;
                            }
                            highp float _18874 = 0.0;
                            if ((_8411 > 1.5) && (_8411 < 2.5))
                            {
                                highp float _8452 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _8457 = max(_8452 * _8403, frag_info.shadow_texel_size);
                                float _18863 = 0.0;
                                highp float _18864 = 0.0;
                                _18864 = 0.0;
                                _18863 = 0.0;
                                highp float _8479 = 0.0;
                                float _8482 = 0.0;
                                for (int _18862 = 0; _18862 < 9; _18864 = _8479, _18863 = _8482, _18862++)
                                {
                                    vec2 _18953 = vec2(0.0);
                                    do
                                    {
                                        if (_18862 == 0)
                                        {
                                            _18953 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_18862 == 1)
                                        {
                                            _18953 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_18862 == 2)
                                        {
                                            _18953 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_18862 == 3)
                                        {
                                            _18953 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_18862 == 4)
                                        {
                                            _18953 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_18862 == 5)
                                        {
                                            _18953 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_18862 == 6)
                                        {
                                            _18953 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_18862 == 7)
                                        {
                                            _18953 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_18862 == 8)
                                        {
                                            _18953 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_18862 == 9)
                                        {
                                            _18953 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_18862 == 10)
                                        {
                                            _18953 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_18862 == 11)
                                        {
                                            _18953 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_18862 == 12)
                                        {
                                            _18953 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_18862 == 13)
                                        {
                                            _18953 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_18862 == 14)
                                        {
                                            _18953 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_18862 == 15)
                                        {
                                            _18953 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _18953 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8786 = clamp(_8105 + (vec2((_18953.x * _18867) - (_18953.y * _18871), (_18953.x * _18871) + (_18953.y * _18867)) * _8457), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8795 = _8786.y;
                                    highp vec2 _8796 = vec2((float(_17862) + _8786.x) * _8409, _8795);
                                    _8796.y = 1.0 - _8795;
                                    highp vec4 _8803 = textureLod(shadow_map, _8796, 0.0);
                                    highp float _8804 = _8803.x;
                                    highp float _8474 = step(_8804, _8403);
                                    float mp_copy_8474 = _8474;
                                    _8479 = _18864 + (_8804 * _8474);
                                    _8482 = _18863 + mp_copy_8474;
                                }
                                highp float _18865 = 0.0;
                                if (_18863 > 0.0)
                                {
                                    _18865 = _18864 / _18863;
                                }
                                else
                                {
                                    _18865 = _8403;
                                }
                                _18874 = clamp(_8452 * max(_8403 - _18865, 0.0), frag_info.shadow_texel_size, _8112);
                            }
                            else
                            {
                                _18874 = _8112;
                            }
                            bool _8513 = _8411 > 2.5;
                            bool _18875 = false;
                            float _18900 = 0.0;
                            if ((_8411 < 1.5) || _8513)
                            {
                                highp vec2 _8837 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8841 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8842 = clamp(_8105, _8837, _8841);
                                highp float _8844 = float(_17862);
                                highp float _8851 = _8842.y;
                                highp vec2 _8852 = vec2((_8844 + _8842.x) * _8409, _8851);
                                _8852.y = 1.0 - _8851;
                                highp float _8864 = float(_8403 <= textureLod(shadow_map, _8852, 0.0).x);
                                float mp_copy_8864 = _8864;
                                float _8874 = (-1.0) * _18867;
                                float _8878 = (-1.0) * _18871;
                                highp vec2 _8902 = clamp(_8105 + (vec2(_8874 - _8878, _8878 + _8874) * _18874), _8837, _8841);
                                highp float _8911 = _8902.y;
                                highp vec2 _8912 = vec2((_8844 + _8902.x) * _8409, _8911);
                                _8912.y = 1.0 - _8911;
                                highp float _8924 = float(_8403 <= textureLod(shadow_map, _8912, 0.0).x);
                                float mp_copy_8924 = _8924;
                                highp vec2 _8962 = clamp(_8105 + (vec2(_18867 - _8878, _18871 + _8874) * _18874), _8837, _8841);
                                highp float _8971 = _8962.y;
                                highp vec2 _8972 = vec2((_8844 + _8962.x) * _8409, _8971);
                                _8972.y = 1.0 - _8971;
                                highp float _8984 = float(_8403 <= textureLod(shadow_map, _8972, 0.0).x);
                                float mp_copy_8984 = _8984;
                                highp vec2 _9022 = clamp(_8105 + (vec2(_8874 - _18871, _8878 + _18867) * _18874), _8837, _8841);
                                highp float _9031 = _9022.y;
                                highp vec2 _9032 = vec2((_8844 + _9022.x) * _8409, _9031);
                                _9032.y = 1.0 - _9031;
                                highp float _9044 = float(_8403 <= textureLod(shadow_map, _9032, 0.0).x);
                                float mp_copy_9044 = _9044;
                                highp vec2 _9082 = clamp(_8105 + (vec2(_18867 - _18871, _18871 + _18867) * _18874), _8837, _8841);
                                highp float _9091 = _9082.y;
                                highp vec2 _9092 = vec2((_8844 + _9082.x) * _8409, _9091);
                                _9092.y = 1.0 - _9091;
                                highp float _9104 = float(_8403 <= textureLod(shadow_map, _9092, 0.0).x);
                                float mp_copy_9104 = _9104;
                                float _8559 = (((mp_copy_8864 + mp_copy_8924) + mp_copy_8984) + mp_copy_9044) + mp_copy_9104;
                                _18900 = _8559 * 0.20000000298023223876953125;
                                _18875 = (_8559 < 0.5) || (_8559 > 4.5);
                            }
                            else
                            {
                                _18900 = 0.0;
                                _18875 = false;
                            }
                            float _18898 = 0.0;
                            if (_18875)
                            {
                                _18898 = _18900;
                            }
                            else
                            {
                                float _18899 = 0.0;
                                if (_8513)
                                {
                                    highp vec2 _9323 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _9327 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _9328 = clamp(_8105 + (vec2(-0.707099974155426025390625) * _18874), _9323, _9327);
                                    highp vec2 _9339 = (vec2(_9328.x, 1.0 - _9328.y) / _9323) - vec2(0.5);
                                    highp vec2 _9341 = floor(_9339);
                                    highp vec2 _9344 = _9339 - _9341;
                                    highp vec2 _9349 = (_9341 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _9351 = float(_17862);
                                    highp vec2 _9359 = vec2((_9351 + _9349.x) * _8409, _9349.y);
                                    highp float _9363 = frag_info.shadow_texel_size * _8409;
                                    highp vec2 _9366 = vec2(_9363, frag_info.shadow_texel_size);
                                    highp vec2 _9375 = vec2(_9363, 0.0);
                                    highp vec2 _9383 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _9412 = _9344.x;
                                    highp float _9421 = mix(mix(float(_8403 <= textureLod(shadow_map, _9359, 0.0).x), float(_8403 <= textureLod(shadow_map, _9359 + _9375, 0.0).x), _9412), mix(float(_8403 <= textureLod(shadow_map, _9359 + _9383, 0.0).x), float(_8403 <= textureLod(shadow_map, _9359 + _9366, 0.0).x), _9412), _9344.y);
                                    float mp_copy_9421 = _9421;
                                    highp vec2 _9455 = clamp(_8105 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _18874), _9323, _9327);
                                    highp vec2 _9466 = (vec2(_9455.x, 1.0 - _9455.y) / _9323) - vec2(0.5);
                                    highp vec2 _9468 = floor(_9466);
                                    highp vec2 _9471 = _9466 - _9468;
                                    highp vec2 _9476 = (_9468 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9486 = vec2((_9351 + _9476.x) * _8409, _9476.y);
                                    highp float _9539 = _9471.x;
                                    highp float _9548 = mix(mix(float(_8403 <= textureLod(shadow_map, _9486, 0.0).x), float(_8403 <= textureLod(shadow_map, _9486 + _9375, 0.0).x), _9539), mix(float(_8403 <= textureLod(shadow_map, _9486 + _9383, 0.0).x), float(_8403 <= textureLod(shadow_map, _9486 + _9366, 0.0).x), _9539), _9471.y);
                                    float mp_copy_9548 = _9548;
                                    highp vec2 _9582 = clamp(_8105 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _18874), _9323, _9327);
                                    highp vec2 _9593 = (vec2(_9582.x, 1.0 - _9582.y) / _9323) - vec2(0.5);
                                    highp vec2 _9595 = floor(_9593);
                                    highp vec2 _9598 = _9593 - _9595;
                                    highp vec2 _9603 = (_9595 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9613 = vec2((_9351 + _9603.x) * _8409, _9603.y);
                                    highp float _9666 = _9598.x;
                                    highp float _9675 = mix(mix(float(_8403 <= textureLod(shadow_map, _9613, 0.0).x), float(_8403 <= textureLod(shadow_map, _9613 + _9375, 0.0).x), _9666), mix(float(_8403 <= textureLod(shadow_map, _9613 + _9383, 0.0).x), float(_8403 <= textureLod(shadow_map, _9613 + _9366, 0.0).x), _9666), _9598.y);
                                    float mp_copy_9675 = _9675;
                                    highp vec2 _9709 = clamp(_8105 + (vec2(0.707099974155426025390625) * _18874), _9323, _9327);
                                    highp vec2 _9720 = (vec2(_9709.x, 1.0 - _9709.y) / _9323) - vec2(0.5);
                                    highp vec2 _9722 = floor(_9720);
                                    highp vec2 _9725 = _9720 - _9722;
                                    highp vec2 _9730 = (_9722 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9740 = vec2((_9351 + _9730.x) * _8409, _9730.y);
                                    highp float _9793 = _9725.x;
                                    highp float _9802 = mix(mix(float(_8403 <= textureLod(shadow_map, _9740, 0.0).x), float(_8403 <= textureLod(shadow_map, _9740 + _9375, 0.0).x), _9793), mix(float(_8403 <= textureLod(shadow_map, _9740 + _9383, 0.0).x), float(_8403 <= textureLod(shadow_map, _9740 + _9366, 0.0).x), _9793), _9725.y);
                                    float mp_copy_9802 = _9802;
                                    _18899 = (((mp_copy_9421 + mp_copy_9548) + mp_copy_9675) + mp_copy_9802) * 0.25;
                                }
                                else
                                {
                                    int _8575 = (_8417 > 0.5) ? 17 : 16;
                                    float _18894 = 0.0;
                                    _18894 = 0.0;
                                    float _8603 = 0.0;
                                    for (int _18876 = 0; _18876 < 17; _18894 = _8603, _18876++)
                                    {
                                        if (_18876 >= _8575)
                                        {
                                            break;
                                        }
                                        vec2 _18877 = vec2(0.0);
                                        do
                                        {
                                            if (_18876 == 0)
                                            {
                                                _18877 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_18876 == 1)
                                            {
                                                _18877 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_18876 == 2)
                                            {
                                                _18877 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_18876 == 3)
                                            {
                                                _18877 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_18876 == 4)
                                            {
                                                _18877 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_18876 == 5)
                                            {
                                                _18877 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_18876 == 6)
                                            {
                                                _18877 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_18876 == 7)
                                            {
                                                _18877 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_18876 == 8)
                                            {
                                                _18877 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_18876 == 9)
                                            {
                                                _18877 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_18876 == 10)
                                            {
                                                _18877 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_18876 == 11)
                                            {
                                                _18877 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_18876 == 12)
                                            {
                                                _18877 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_18876 == 13)
                                            {
                                                _18877 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_18876 == 14)
                                            {
                                                _18877 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_18876 == 15)
                                            {
                                                _18877 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _18877 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _18879 = vec2(0.0);
                                        do
                                        {
                                            if (_18876 < 3)
                                            {
                                                _18879 = vec2(float(_18876) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_18876 < 6)
                                            {
                                                _18879 = vec2((float(_18876 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_18876 < 11)
                                            {
                                                _18879 = vec2((float(_18876 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_18876 < 14)
                                            {
                                                _18879 = vec2((float(_18876 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _18879 = vec2(float(_18876 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8592 = mix(_18877, _18879, vec2(_8417));
                                        float _9243 = _8592.x;
                                        float _9247 = _8592.y;
                                        highp vec2 _9273 = clamp(_8105 + (vec2((_9243 * _18867) - (_9247 * _18871), (_9243 * _18871) + (_9247 * _18867)) * _18874), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9282 = _9273.y;
                                        highp vec2 _9283 = vec2((float(_17862) + _9273.x) * _8409, _9282);
                                        _9283.y = 1.0 - _9282;
                                        highp float _9295 = float(_8403 <= textureLod(shadow_map, _9283, 0.0).x);
                                        float mp_copy_9295 = _9295;
                                        _8603 = _18894 + mp_copy_9295;
                                    }
                                    _18899 = _18894 / float(_8575);
                                }
                                _18898 = _18899;
                            }
                            bool _8648 = _17862 == (_8015 - 1);
                            bool _8654 = false;
                            if (_8648)
                            {
                                _8654 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8654 = _8648;
                            }
                            float _18901 = 0.0;
                            if (_8654)
                            {
                                highp vec2 _8661 = vec2(frag_info.shadow_fade / _18834);
                                highp vec2 _8669 = smoothstep(vec2(0.0), _8661, _8105) * smoothstep(vec2(0.0), _8661, _8262);
                                _18901 = mix(1.0, _18898, _8669.x * _8669.y);
                            }
                            else
                            {
                                _18901 = _18898;
                            }
                            _18964 = _17866 + _8165;
                            _18961 = _17864 + (_8165 * _18901);
                        }
                        else
                        {
                            _18964 = _17866;
                            _18961 = _17864;
                        }
                        _18963 = _18964;
                        _18960 = _18961;
                    }
                    else
                    {
                        _18963 = _17866;
                        _18960 = _17864;
                    }
                    _18962 = _18963;
                    _18959 = _18960;
                }
                else
                {
                    _18962 = _17866;
                    _18959 = _17864;
                }
            }
            _17865 = _17866;
            _17863 = _17864;
        }
        else
        {
            _17865 = 0.0;
            _17863 = 0.0;
        }
        _17869 = mix(_17863 + (1.0 - _17865), 1.0, _17861);
    }
    else
    {
        _17869 = 1.0;
    }
    bool _7170 = frag_info.ssao_lighting.w > 0.5;
    bool _7176 = false;
    if (_7170)
    {
        _7176 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _7176 = _7170;
    }
    float _17881 = 0.0;
    if (_7176)
    {
        _17881 = min(_17869, _17875.y);
    }
    else
    {
        _17881 = _17869;
    }
    vec3 mp_copy_17882 = vec3(0.0);
    float _7185 = _7148 * _17881;
    bool _9810 = view_info.camera_forward.w > 0.5;
    highp vec3 _17882 = vec3(0.0);
    if (_9810)
    {
        _17882 = -view_info.camera_forward.xyz;
    }
    else
    {
        _17882 = normalize(v_viewvector);
    }
    highp float _9854 = 0.0;
    mp_copy_17882 = _17882;
    vec3 _7194 = mix(frag_info.dielectric_f0.xyz, _7046, vec3(_6149));
    float _7197 = dot(_17804, _17882);
    float _7198 = max(_7197, 0.0);
    float _7202 = max(dot(_6015, _17882), 0.0);
    vec3 _7206 = reflect(-mp_copy_17882, _17804);
    highp vec2 _17883 = vec2(0.0);
    do
    {
        _9854 = frag_info.punctual_dims.x;
        if (_9854 < 0.5)
        {
            _17883 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9866 = v_position - frag_info.camera_position.xyz;
            highp float _9881 = dot(_9866, frag_info.camera_forward.xyz);
            highp float _9887 = max(_9881, 9.9999997473787516355514526367188e-05);
            highp vec2 _9990 = (vec3(dot(_9866, frag_info.camera_right.xyz), dot(_9866, frag_info.camera_up.xyz), _9887).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9887, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _10005 = float(int(((((clamp(floor((log2(max(_9881 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_9990.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_9990.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _17883 = vec2(textureLod(punctual_index, vec2((mod(_10005, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_10005 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _17883 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _7211 = int(_17883.x + 0.5);
    mediump int _7215 = int(_17883.y + 0.5);
    highp vec3 _18555 = vec3(0.0);
    _18555 = vec3(0.0);
    highp vec3 _19369 = vec3(0.0);
    for (int _17884 = 0; _17884 < _7215; _18555 = _19369, _17884++)
    {
        highp float _10038 = float(_7211 + _17884);
        highp float _10069 = (float(int(textureLod(punctual_index, vec2((mod(_10038, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_10038 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9854;
        highp vec2 _10070 = vec2(0.0625, _10069);
        highp vec4 _10073 = textureLod(punctual_lights, _10070, 0.0);
        highp vec4 _10090 = textureLod(punctual_lights, vec2(0.1875, _10069), 0.0);
        highp float _7233 = _10073.w;
        highp vec3 _7235 = _10090.xyz;
        highp vec3 _19370 = vec3(0.0);
        if (_7233 > 2.5)
        {
            highp vec4 _11364 = textureLod(punctual_lights, vec2(0.3125, _10069), 0.0);
            highp vec4 _11381 = textureLod(punctual_lights, vec2(0.4375, _10069), 0.0);
            highp vec3 _7425 = _11364.xyz * (_11364.w * 0.5);
            highp vec3 _7431 = _11381.xyz * (_11381.w * 0.5);
            highp vec3 _7433 = _10073.xyz;
            highp vec3 _7435 = _7433 - _7425;
            highp vec3 _7437 = _7435 - _7431;
            highp vec3 _7441 = _7433 + _7425;
            highp vec3 _7443 = _7441 - _7431;
            highp vec3 _7455 = _7435 + _7431;
            highp vec3 _7459 = _7433 - v_position;
            highp float _7465 = _10090.w;
            highp float _7469 = (dot(_7459, _7459) * _7465) * _7465;
            highp float _7474 = clamp(1.0 - (_7469 * _7469), 0.0, 1.0);
            float mp_copy_7474 = _7474;
            vec2 _11388 = (clamp(vec2(_17852, sqrt(1.0 - _7198)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _11390 = _11388.x;
            float _11395 = _11388.y;
            vec4 _7498 = textureLod(brdf_lut, vec2((_11390 + 1.0) * 0.3333333432674407958984375, _11395), 0.0);
            vec4 _7502 = textureLod(brdf_lut, vec2((_11390 + 2.0) * 0.3333333432674407958984375, _11395), 0.0);
            vec3 _11438 = normalize(mp_copy_17882 - (_17804 * _7197));
            mat3 _11460 = transpose(mat3(_11438, -cross(_17804, _11438), _17804));
            mat3 _11461 = mat3(vec3(_7498.x, 0.0, _7498.y), vec3(0.0, 1.0, 0.0), vec3(_7498.z, 0.0, _7498.w)) * _11460;
            highp vec3 _11465 = _7437 - v_position;
            highp vec3 _11467 = normalize(_11461 * _11465);
            vec3 mp_copy_11467 = _11467;
            highp vec3 _11471 = _7443 - v_position;
            highp vec3 _11473 = normalize(_11461 * _11471);
            vec3 mp_copy_11473 = _11473;
            highp vec3 _11477 = (_7441 + _7431) - v_position;
            highp vec3 _11479 = normalize(_11461 * _11477);
            vec3 mp_copy_11479 = _11479;
            highp vec3 _11483 = _7455 - v_position;
            highp vec3 _11485 = normalize(_11461 * _11483);
            vec3 mp_copy_11485 = _11485;
            float _11514 = dot(_11467, _11473);
            float _11516 = abs(_11514);
            float _11530 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11516)) * _11516)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11516) * _11516));
            float _18770 = 0.0;
            if (_11514 > 0.0)
            {
                _18770 = _11530;
            }
            else
            {
                _18770 = (0.5 * inversesqrt(max(1.0 - (_11514 * _11514), 1.0000000116860974230803549289703e-07))) - _11530;
            }
            float _11563 = dot(_11473, _11479);
            float _11565 = abs(_11563);
            float _11579 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11565)) * _11565)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11565) * _11565));
            float _18771 = 0.0;
            if (_11563 > 0.0)
            {
                _18771 = _11579;
            }
            else
            {
                _18771 = (0.5 * inversesqrt(max(1.0 - (_11563 * _11563), 1.0000000116860974230803549289703e-07))) - _11579;
            }
            float _11612 = dot(_11479, _11485);
            float _11614 = abs(_11612);
            float _11628 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11614)) * _11614)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11614) * _11614));
            float _18772 = 0.0;
            if (_11612 > 0.0)
            {
                _18772 = _11628;
            }
            else
            {
                _18772 = (0.5 * inversesqrt(max(1.0 - (_11612 * _11612), 1.0000000116860974230803549289703e-07))) - _11628;
            }
            float _11661 = dot(_11485, _11467);
            float _11663 = abs(_11661);
            float _11677 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11663)) * _11663)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11663) * _11663));
            float _18773 = 0.0;
            if (_11661 > 0.0)
            {
                _18773 = _11677;
            }
            else
            {
                _18773 = (0.5 * inversesqrt(max(1.0 - (_11661 * _11661), 1.0000000116860974230803549289703e-07))) - _11677;
            }
            vec3 _11500 = (((cross(mp_copy_11467, mp_copy_11473) * _18770) + (cross(mp_copy_11473, mp_copy_11479) * _18771)) + (cross(mp_copy_11479, mp_copy_11485) * _18772)) + (cross(mp_copy_11485, mp_copy_11467) * _18773);
            float _11703 = length(_11500);
            mat3 _11763 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _11460;
            highp vec3 _11769 = normalize(_11763 * _11465);
            vec3 mp_copy_11769 = _11769;
            highp vec3 _11775 = normalize(_11763 * _11471);
            vec3 mp_copy_11775 = _11775;
            highp vec3 _11781 = normalize(_11763 * _11477);
            vec3 mp_copy_11781 = _11781;
            highp vec3 _11787 = normalize(_11763 * _11483);
            vec3 mp_copy_11787 = _11787;
            float _11816 = dot(_11769, _11775);
            float _11818 = abs(_11816);
            float _11832 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11818)) * _11818)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11818) * _11818));
            float _18774 = 0.0;
            if (_11816 > 0.0)
            {
                _18774 = _11832;
            }
            else
            {
                _18774 = (0.5 * inversesqrt(max(1.0 - (_11816 * _11816), 1.0000000116860974230803549289703e-07))) - _11832;
            }
            float _11865 = dot(_11775, _11781);
            float _11867 = abs(_11865);
            float _11881 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11867)) * _11867)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11867) * _11867));
            float _18775 = 0.0;
            if (_11865 > 0.0)
            {
                _18775 = _11881;
            }
            else
            {
                _18775 = (0.5 * inversesqrt(max(1.0 - (_11865 * _11865), 1.0000000116860974230803549289703e-07))) - _11881;
            }
            float _11914 = dot(_11781, _11787);
            float _11916 = abs(_11914);
            float _11930 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11916)) * _11916)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11916) * _11916));
            float _18776 = 0.0;
            if (_11914 > 0.0)
            {
                _18776 = _11930;
            }
            else
            {
                _18776 = (0.5 * inversesqrt(max(1.0 - (_11914 * _11914), 1.0000000116860974230803549289703e-07))) - _11930;
            }
            float _11963 = dot(_11787, _11769);
            float _11965 = abs(_11963);
            float _11979 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _11965)) * _11965)) / (3.41759395599365234375 + ((4.1616725921630859375 + _11965) * _11965));
            float _18777 = 0.0;
            if (_11963 > 0.0)
            {
                _18777 = _11979;
            }
            else
            {
                _18777 = (0.5 * inversesqrt(max(1.0 - (_11963 * _11963), 1.0000000116860974230803549289703e-07))) - _11979;
            }
            vec3 _11802 = (((cross(mp_copy_11769, mp_copy_11775) * _18774) + (cross(mp_copy_11775, mp_copy_11781) * _18775)) + (cross(mp_copy_11781, mp_copy_11787) * _18776)) + (cross(mp_copy_11787, mp_copy_11769) * _18777);
            float _12005 = length(_11802);
            _19370 = _18555 + (((_7235 * (mp_copy_7474 * mp_copy_7474)) * step(0.0, dot(cross(_7443 - _7437, _7455 - _7437), v_position - _7437))) * (((((_7194 * _7502.x) + ((vec3(1.0) - _7194) * _7502.y)) * max(((_11703 * _11703) + _11500.z) / (_11703 + 1.0), 0.0)) * 1.0) + ((_7046 * (1.0 - _6149)) * max(((_12005 * _12005) + _11802.z) / (_12005 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_18714 = 0.0;
            vec3 _18687 = vec3(0.0);
            highp vec3 _18710 = vec3(0.0);
            float _18714 = 0.0;
            if (_7233 < 0.5)
            {
                _18714 = _17852;
                _18710 = _7235;
                _18687 = -normalize(textureLod(punctual_lights, vec2(0.3125, _10069), 0.0).xyz);
            }
            else
            {
                highp vec3 _7246 = _10073.xyz - v_position;
                highp float _7249 = dot(_7246, _7246);
                highp float _7253 = inversesqrt(max(_7249, 9.9999999392252902907785028219223e-09));
                highp vec3 _7254 = _7246 * _7253;
                vec3 mp_copy_7254 = _7254;
                highp float _7256 = _10090.w;
                highp float _7261 = (_7249 * _7256) * _7256;
                highp float _7266 = clamp(1.0 - (_7261 * _7261), 0.0, 1.0);
                float mp_copy_7266 = _7266;
                if (_7266 <= 0.0)
                {
                    _19369 = _18555;
                    continue;
                }
                highp vec4 _10107 = textureLod(punctual_lights, vec2(0.4375, _10069), 0.0);
                highp float _7274 = _10107.w;
                float _18719 = 0.0;
                if (_7274 > 0.0)
                {
                    highp float _7301 = (_17852 * _17852) + ((_7274 * 0.5) * _7253);
                    float mp_copy_7301 = _7301;
                    _18719 = sqrt(min(mp_copy_7301, 1.0));
                }
                else
                {
                    _18719 = _17852;
                }
                highp vec3 _7308 = _7235 * ((mp_copy_7266 * mp_copy_7266) / max(pow(max(_7249, _7274 * _7274), _10107.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _18711 = vec3(0.0);
                if (_7233 > 1.5)
                {
                    highp vec4 _10545 = textureLod(punctual_lights, vec2(0.3125, _10069), 0.0);
                    highp float _7353 = clamp((dot(normalize(_10545.xyz), -mp_copy_7254) * _10545.w) + _10107.x, 0.0, 1.0);
                    float mp_copy_7353 = _7353;
                    highp vec3 _7358 = _7308 * (mp_copy_7353 * mp_copy_7353);
                    if (_7353 <= 0.0)
                    {
                        _19369 = _18555;
                        continue;
                    }
                    bool _7364 = _7353 > 0.0;
                    bool _7370 = false;
                    if (_7364)
                    {
                        _7370 = _10107.y > (-0.5);
                    }
                    else
                    {
                        _7370 = _7364;
                    }
                    bool _7376 = false;
                    if (_7370)
                    {
                        _7376 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7376 = _7370;
                    }
                    highp vec3 _18713 = vec3(0.0);
                    if (_7376)
                    {
                        float _18678 = 0.0;
                        do
                        {
                            highp vec4 _10657 = mat4(textureLod(punctual_lights, vec2(0.5625, _10069), 0.0), textureLod(punctual_lights, vec2(0.6875, _10069), 0.0), textureLod(punctual_lights, vec2(0.8125, _10069), 0.0), textureLod(punctual_lights, vec2(0.9375, _10069), 0.0)) * vec4(v_position + (_6015 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10659 = _10657.w;
                            if (_10659 <= 0.0)
                            {
                                _18678 = 1.0;
                                break;
                            }
                            highp vec3 _10668 = _10657.xyz / vec3(_10659);
                            highp vec2 _10673 = (_10668.xy * 0.5) + vec2(0.5);
                            highp float _10675 = _10673.x;
                            bool _10676 = _10675 < 0.0;
                            bool _10683 = false;
                            if (!_10676)
                            {
                                _10683 = _10675 > 1.0;
                            }
                            else
                            {
                                _10683 = _10676;
                            }
                            bool _10690 = false;
                            if (!_10683)
                            {
                                _10690 = _10673.y < 0.0;
                            }
                            else
                            {
                                _10690 = _10683;
                            }
                            bool _10697 = false;
                            if (!_10690)
                            {
                                _10697 = _10673.y > 1.0;
                            }
                            else
                            {
                                _10697 = _10690;
                            }
                            bool _10704 = false;
                            if (!_10697)
                            {
                                _10704 = _10668.z < 0.0;
                            }
                            else
                            {
                                _10704 = _10697;
                            }
                            bool _10711 = false;
                            if (!_10704)
                            {
                                _10711 = _10668.z > 1.0;
                            }
                            else
                            {
                                _10711 = _10704;
                            }
                            if (_10711)
                            {
                                _18678 = 1.0;
                                break;
                            }
                            highp float _10718 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _10723 = frag_info.shadow_cascade_count + float(int(_10107.y + 0.5));
                            highp float _10728 = _10668.z - frag_info.spot_shadow_params.y;
                            highp float _10739 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_10739 = _10739;
                            highp vec2 _10746 = vec2(cos(mp_copy_10739), sin(mp_copy_10739)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _10748 = _10746.x;
                            highp float _10750 = _10746.y;
                            highp vec2 _10758 = vec2(_10748 - _10750, _10748 + _10750) * 0.707106769084930419921875;
                            highp float _10951 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10675, 0.0, 1.0)) / _10718, 1.0 - clamp(_10673.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10951 = _10951;
                            highp vec2 _10766 = _10673 + _10746;
                            highp float _10973 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10766.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10766.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10973 = _10973;
                            highp vec2 _10774 = _10673 - _10746;
                            highp float _10995 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10774.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10774.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_10995 = _10995;
                            highp vec2 _10787 = _10673 + vec2(-_10750, _10748);
                            highp float _11017 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10787.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10787.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11017 = _11017;
                            highp vec2 _10800 = _10673 + vec2(_10750, -_10748);
                            highp float _11039 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10800.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10800.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11039 = _11039;
                            float _10805 = (((mp_copy_10951 + mp_copy_10973) + mp_copy_10995) + mp_copy_11017) + mp_copy_11039;
                            if ((_10805 < 0.5) || (_10805 > 4.5))
                            {
                                _18678 = _10805 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _10817 = _10673 + _10758;
                            highp float _11061 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10817.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10817.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11061 = _11061;
                            highp vec2 _10824 = _10673 - _10758;
                            highp float _11083 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10824.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10824.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11083 = _11083;
                            highp float _10832 = _10758.y;
                            highp float _10835 = _10758.x;
                            highp vec2 _10837 = _10673 + vec2(-_10832, _10835);
                            highp float _11105 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10837.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10837.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11105 = _11105;
                            highp vec2 _10850 = _10673 + vec2(_10832, -_10835);
                            highp float _11127 = float(_10728 <= textureLod(shadow_map, vec2((_10723 + clamp(_10850.x, 0.0, 1.0)) / _10718, 1.0 - clamp(_10850.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11127 = _11127;
                            _18678 = (_10805 + (((mp_copy_11061 + mp_copy_11083) + mp_copy_11105) + mp_copy_11127)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18713 = _7358 * _18678;
                    }
                    else
                    {
                        _18713 = _7358;
                    }
                    _18711 = _18713;
                }
                else
                {
                    bool _7313 = _7233 > 0.5;
                    bool _7319 = false;
                    if (_7313)
                    {
                        _7319 = _10107.y > (-0.5);
                    }
                    else
                    {
                        _7319 = _7313;
                    }
                    bool _7325 = false;
                    if (_7319)
                    {
                        _7325 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7325 = _7319;
                    }
                    highp vec3 _18712 = vec3(0.0);
                    if (_7325)
                    {
                        float _18665 = 0.0;
                        do
                        {
                            highp vec4 _10420 = textureLod(punctual_lights, vec2(0.5625, _10069), 0.0);
                            highp vec4 _10437 = textureLod(punctual_lights, vec2(0.6875, _10069), 0.0);
                            highp vec3 _10179 = (v_position + (_6015 * _10420.z)) - textureLod(punctual_lights, _10070, 0.0).xyz;
                            highp vec3 _10181 = abs(_10179);
                            highp float _10183 = _10181.x;
                            highp float _10185 = _10181.y;
                            bool _10186 = _10183 >= _10185;
                            bool _10194 = false;
                            if (_10186)
                            {
                                _10194 = _10183 >= _10181.z;
                            }
                            else
                            {
                                _10194 = _10186;
                            }
                            highp vec3 _18655 = vec3(0.0);
                            float _18657 = 0.0;
                            if (_10194)
                            {
                                highp float _10260 = _10179.x;
                                bool _10261 = _10260 >= 0.0;
                                highp vec3 _18654 = vec3(0.0);
                                if (_10261)
                                {
                                    _18654 = vec3(-_10179.z, _10179.y, _10260);
                                }
                                else
                                {
                                    _18654 = vec3(_10179.zy, -_10260);
                                }
                                _18657 = _10261 ? 0.0 : 1.0;
                                _18655 = _18654;
                            }
                            else
                            {
                                highp vec3 _18656 = vec3(0.0);
                                float _18658 = 0.0;
                                if (_10185 >= _10181.z)
                                {
                                    highp float _10231 = _10179.y;
                                    bool _10232 = _10231 >= 0.0;
                                    highp vec3 _18653 = vec3(0.0);
                                    if (_10232)
                                    {
                                        _18653 = vec3(-_10179.x, _10179.z, _10231);
                                    }
                                    else
                                    {
                                        _18653 = vec3(_10179.xz, -_10231);
                                    }
                                    _18658 = _10232 ? 2.0 : 3.0;
                                    _18656 = _18653;
                                }
                                else
                                {
                                    highp float _10203 = _10179.z;
                                    bool _10204 = _10203 >= 0.0;
                                    highp vec3 _18652 = vec3(0.0);
                                    if (_10204)
                                    {
                                        _18652 = _10179;
                                    }
                                    else
                                    {
                                        _18652 = vec3(-_10179.x, _10179.y, -_10203);
                                    }
                                    _18658 = _10204 ? 4.0 : 5.0;
                                    _18656 = _18652;
                                }
                                _18657 = _18658;
                                _18655 = _18656;
                            }
                            if (_18655.z <= 0.0)
                            {
                                _18665 = 1.0;
                                break;
                            }
                            highp vec2 _10300 = ((_18655.xy / vec2(_18655.z)) * 0.5) + vec2(0.5);
                            highp float _10311 = (_10420.x - (_10420.y / _18655.z)) - _10437.x;
                            if ((_10311 < 0.0) || (_10311 > 1.0))
                            {
                                _18665 = 1.0;
                                break;
                            }
                            highp float hp_copy_18662 = 0.0;
                            highp float _10323 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _10329 = _18657 >= 4.0;
                            highp float _10331 = (frag_info.shadow_cascade_count + _10107.y) + float(_10329);
                            float _18662 = 0.0;
                            if (_10329)
                            {
                                _18662 = _18657 - 4.0;
                            }
                            else
                            {
                                _18662 = _18657;
                            }
                            hp_copy_18662 = _18662;
                            highp float _10348 = _10437.y * 0.5;
                            highp float _10351 = _10420.w * 0.0040000001899898052215576171875;
                            highp vec2 _10462 = vec2(_10348);
                            highp vec2 _10465 = vec2(1.0 - _10348);
                            highp vec2 _10471 = vec2(mod(hp_copy_18662, 2.0), 1.0 - floor(hp_copy_18662 * 0.5)) * 0.5;
                            highp vec2 _10474 = _10471 + (clamp(_10300, _10462, _10465) * 0.5);
                            highp float _10367 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _18664 = 0.0;
                            _18664 = float(_10311 <= textureLod(shadow_map, vec2((_10331 + _10474.x) / _10323, 1.0 - _10474.y), 0.0).x);
                            for (int _18663 = 0; _18663 < 8; )
                            {
                                highp float _10377 = _10367 + (float(_18663) * 0.785398185253143310546875);
                                float mp_copy_10377 = _10377;
                                highp vec2 _10511 = _10471 + (clamp(_10300 + (vec2(cos(mp_copy_10377), sin(mp_copy_10377)) * _10351), _10462, _10465) * 0.5);
                                highp float _10528 = float(_10311 <= textureLod(shadow_map, vec2((_10331 + _10511.x) / _10323, 1.0 - _10511.y), 0.0).x);
                                float mp_copy_10528 = _10528;
                                _18664 += mp_copy_10528;
                                _18663++;
                                continue;
                            }
                            _18665 = _18664 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _18712 = _7308 * _18665;
                    }
                    else
                    {
                        _18712 = _7308;
                    }
                    _18711 = _18712;
                }
                _18714 = _18719;
                _18710 = _18711;
                _18687 = _7254;
            }
            hp_copy_18714 = _18714;
            highp vec3 _18741 = vec3(0.0);
            highp vec3 _18742 = vec3(0.0);
            do
            {
                float _11210 = max(dot(_17804, _18687), 0.0);
                highp float hp_copy_11210 = _11210;
                if (_11210 <= 0.0)
                {
                    _18742 = vec3(0.0);
                    _18741 = vec3(0.0);
                    break;
                }
                float _11216 = max(_7198, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11216 = _11216;
                vec3 _11219 = _18687 + mp_copy_17882;
                float _11222 = dot(_11219, _11219);
                vec3 _18739 = vec3(0.0);
                vec3 _18740 = vec3(0.0);
                if (_11222 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11230 = _11219 * inversesqrt(_11222);
                    float _18738 = 0.0;
                    do
                    {
                        float _11287 = dot(_17804, _11230);
                        if (_11287 <= 0.0)
                        {
                            _18738 = 0.0;
                            break;
                        }
                        float _11294 = _18714 * _18714;
                        vec3 _11297 = cross(_17804, _11230);
                        float _11300 = _11287 * _11294;
                        float _11309 = _11294 / (dot(_11297, _11297) + (_11300 * _11300));
                        _18738 = min((_11309 * _11309) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _11347 = _7194 + ((vec3(1.0) - _7194) * pow(clamp(1.0 - max(dot(_11230, _17882), 0.0), 0.0, 1.0), 5.0));
                    _18740 = (_11347 * min(_18738 * (0.5 / max(mix((2.0 * hp_copy_11210) * _11216, hp_copy_11210 + hp_copy_11216, hp_copy_18714 * hp_copy_18714), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _18739 = _11347;
                }
                else
                {
                    _18740 = vec3(0.0);
                    _18739 = _7194;
                }
                _18742 = (_18740 * _18710) * _11210;
                _18741 = (((((vec3(1.0) - _18739) * (1.0 - _6149)) * _7046) * 0.3183098733425140380859375) * _18710) * _11210;
                break;
            } while(false);
            _19370 = _18555 + (_18741 + _18742);
        }
        _19369 = _19370;
    }
    mat3 _7593 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7596 = _17893 > 0.5;
    bvec3 _7599 = bvec3(_7596);
    highp vec3 _7600 = vec3(_7599.x ? _17908.x : _17804.x, _7599.y ? _17908.y : _17804.y, _7599.z ? _17908.z : _17804.z);
    vec3 mp_copy_7600 = _7600;
    vec3 _7601 = _7593 * mp_copy_7600;
    vec3 _17915 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _12062 = _7206 + (((step(vec3(0.0), _7206) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_12062 = _12062;
        highp vec3 _12064 = vec3(1.0) / hp_copy_12062;
        highp vec3 _12081 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _12064, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _12064);
        _17915 = normalize((v_position + (_7206 * max(min(min(_12081.x, _12081.y), _12081.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _17915 = _7206;
    }
    bool _12309 = false;
    highp vec3 hp_copy_17916 = vec3(0.0);
    vec3 _7606 = _7593 * _17915;
    float _12128 = _7601.y;
    float _12135 = _7601.z;
    float _12142 = _7601.x;
    float _12150 = 1.09254801273345947265625 * _12142;
    vec3 _7609 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _12128))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _12135))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _12142))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_12150 * _12128))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _12128) * _12135))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _12135) * _12135) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_12150 * _12135))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_12142 * _12142) - (_12128 * _12128)))), vec3(0.0));
    highp vec3 hp_copy_7609 = _7609;
    vec3 _17916 = vec3(0.0);
    do
    {
        _12309 = radiance_layout_info.mip_layout > 0.5;
        if (_12309)
        {
            vec2 _12388 = vec2(atan(_7606.z, _7606.x), asin(clamp(_7606.y, -1.0, 1.0)));
            highp vec2 hp_copy_12388 = _12388;
            _17916 = textureLod(prefiltered_radiance, (hp_copy_12388 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17852, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _12407 = vec2(atan(_7606.z, _7606.x), asin(clamp(_7606.y, -1.0, 1.0)));
        highp vec2 hp_copy_12407 = _12407;
        highp vec2 _12412 = (hp_copy_12407 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _12319 = clamp(_12412.y, 0.00390625, 0.99609375);
        float _12323 = clamp(_17852, 0.0, 1.0) * 7.0;
        float _12325 = floor(_12323);
        highp float _12344 = _12412.x;
        _17916 = mix(textureLod(prefiltered_radiance, vec2(_12344, (_12325 + _12319) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_12344, (min(_12325 + 1.0, 7.0) + _12319) * 0.125), 0.0).xyz, vec3(_12323 - _12325));
        break;
    } while(false);
    hp_copy_17916 = _17916;
    highp vec3 _17922 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_17917 = vec3(0.0);
        vec3 _17917 = vec3(0.0);
        do
        {
            if (_12309)
            {
                vec2 _12517 = vec2(atan(_7606.z, _7606.x), asin(clamp(_7606.y, -1.0, 1.0)));
                highp vec2 hp_copy_12517 = _12517;
                _17917 = textureLod(prefiltered_radiance_b, (hp_copy_12517 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_17852, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _12536 = vec2(atan(_7606.z, _7606.x), asin(clamp(_7606.y, -1.0, 1.0)));
            highp vec2 hp_copy_12536 = _12536;
            highp vec2 _12541 = (hp_copy_12536 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12448 = clamp(_12541.y, 0.00390625, 0.99609375);
            float _12452 = clamp(_17852, 0.0, 1.0) * 7.0;
            float _12454 = floor(_12452);
            highp float _12473 = _12541.x;
            _17917 = mix(textureLod(prefiltered_radiance_b, vec2(_12473, (_12454 + _12448) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12473, (min(_12454 + 1.0, 7.0) + _12448) * 0.125), 0.0).xyz, vec3(_12452 - _12454));
            break;
        } while(false);
        hp_copy_17917 = _17917;
        _17922 = hp_copy_17916 + hp_copy_17917;
    }
    else
    {
        _17922 = _17916;
    }
    highp float _12554 = 0.0;
    float _7624 = frag_info.environment_intensity;
    highp float hp_copy_7624 = _7624;
    highp vec3 _7626 = hp_copy_7609 * hp_copy_7624;
    float _17923 = 0.0;
    do
    {
        _12554 = frag_info.gi_grid.w;
        if (_12554 <= 0.0)
        {
            _17923 = 0.0;
            break;
        }
        highp vec3 _12567 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _12575 = min(_12567, (frag_info.gi_counts.xyz - vec3(1.0)) - _12567);
        _17923 = clamp(min(_12575.x, min(_12575.y, _12575.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _18114 = vec3(0.0);
    if (_17923 > 0.0)
    {
        highp vec3 _12667 = v_position + (((_17804 * 0.20000000298023223876953125) + (mp_copy_17882 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _12670 = _12667 / frag_info.gi_grid.xyz;
        highp vec3 _12672 = floor(_12670);
        highp vec3 _12678 = clamp(_12670 - _12672, vec3(0.0), vec3(1.0));
        vec3 mp_copy_12678 = _12678;
        highp vec3 _12800 = _12672 - frag_info.gi_anchor.xyz;
        bool _12803 = any(lessThan(_12800, vec3(0.0)));
        bool _12811 = false;
        if (!_12803)
        {
            _12811 = any(greaterThanEqual(_12800, frag_info.gi_counts.xyz));
        }
        else
        {
            _12811 = _12803;
        }
        vec3 mp_copy_17924 = vec3(0.0);
        highp float _12812 = _12811 ? 0.0 : 1.0;
        float mp_copy_12812 = _12812;
        vec3 _12814 = vec3(1.0) - mp_copy_12678;
        vec3 _12818 = max(_12814, vec3(0.001000000047497451305389404296875));
        highp vec3 _12834 = (_12672 * frag_info.gi_grid.xyz) - _12667;
        highp float _12836 = length(_12834);
        highp vec3 _17924 = vec3(0.0);
        if (_12836 > 9.9999997473787516355514526367188e-06)
        {
            _17924 = _12834 / vec3(_12836);
        }
        else
        {
            _17924 = _17804;
        }
        mp_copy_17924 = _17924;
        float _12854 = pow((dot(_17924, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12979 = _12672 - (frag_info.gi_counts.xyz * floor(_12672 / frag_info.gi_counts.xyz));
        highp float _12995 = _12979.x + (frag_info.gi_counts.x * (_12979.y + (frag_info.gi_counts.y * _12979.z)));
        bool _12865 = frag_info.gi_visibility.x > 0.0;
        float _17929 = 0.0;
        if (_12865)
        {
            highp float _13003 = floor(_12995 / frag_info.gi_counts.w);
            highp vec2 _13017 = vec2((_12995 - (_13003 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13003 * 16.0));
            vec3 _12877 = -mp_copy_17924;
            vec3 _13065 = _12877 / vec3((abs(_12877.x) + abs(_12877.y)) + abs(_12877.z));
            vec2 _17925 = vec2(0.0);
            if (_13065.z >= 0.0)
            {
                _17925 = _13065.xy;
            }
            else
            {
                _17925 = (vec2(1.0) - abs(_13065.yx)) * vec2((_13065.x >= 0.0) ? 1.0 : (-1.0), (_13065.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12881 = texture(irradiance_field, clamp((_13017 + vec2(1.0)) + (clamp((_17925 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13017 + vec2(0.5), _13017 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12886 = _12881.x * frag_info.gi_visibility.z;
            highp float _12898 = abs((_12886 * _12886) - ((_12881.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12904 = (_12836 - _12886) - frag_info.gi_visibility.y;
            highp float _17926 = 0.0;
            if (_12904 <= 0.0)
            {
                _17926 = 1.0;
            }
            else
            {
                _17926 = _12898 / (_12898 + (_12904 * _12904));
            }
            _17929 = _12854 * mix(1.0, max(0.0500000007450580596923828125, (_17926 * _17926) * _17926), frag_info.gi_visibility.x);
        }
        else
        {
            _17929 = _12854;
        }
        float _12932 = max(9.9999999747524270787835121154785e-07, _17929);
        float _17930 = 0.0;
        if (_12932 < 0.20000000298023223876953125)
        {
            _17930 = _12932 * ((_12932 * _12932) * 25.0);
        }
        else
        {
            _17930 = _12932;
        }
        float _12947 = _17930 * (((_12818.x * _12818.y) * _12818.z) * mp_copy_12812);
        highp float _13106 = floor(_12995 / frag_info.gi_counts.w);
        highp vec2 _13120 = vec2((_12995 - (_13106 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13106 * 8.0));
        vec3 _13168 = _17804 / vec3((abs(_17804.x) + abs(_17804.y)) + abs(_17804.z));
        bool _13171 = _13168.z >= 0.0;
        vec2 _17931 = vec2(0.0);
        if (_13171)
        {
            _17931 = _13168.xy;
        }
        else
        {
            _17931 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12959 = texture(irradiance_field, clamp((_13120 + vec2(1.0)) + (clamp((_17931 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13120 + vec2(0.5), _13120 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13254 = _12672 + vec3(1.0, 0.0, 0.0);
        highp vec3 _13259 = _13254 - frag_info.gi_anchor.xyz;
        bool _13262 = any(lessThan(_13259, vec3(0.0)));
        bool _13270 = false;
        if (!_13262)
        {
            _13270 = any(greaterThanEqual(_13259, frag_info.gi_counts.xyz));
        }
        else
        {
            _13270 = _13262;
        }
        vec3 mp_copy_17933 = vec3(0.0);
        highp float _13271 = _13270 ? 0.0 : 1.0;
        float mp_copy_13271 = _13271;
        vec3 _13277 = max(mix(_12814, mp_copy_12678, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13293 = (_13254 * frag_info.gi_grid.xyz) - _12667;
        highp float _13295 = length(_13293);
        highp vec3 _17933 = vec3(0.0);
        if (_13295 > 9.9999997473787516355514526367188e-06)
        {
            _17933 = _13293 / vec3(_13295);
        }
        else
        {
            _17933 = _17804;
        }
        mp_copy_17933 = _17933;
        float _13313 = pow((dot(_17933, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13438 = _13254 - (frag_info.gi_counts.xyz * floor(_13254 / frag_info.gi_counts.xyz));
        highp float _13454 = _13438.x + (frag_info.gi_counts.x * (_13438.y + (frag_info.gi_counts.y * _13438.z)));
        float _17938 = 0.0;
        if (_12865)
        {
            highp float _13462 = floor(_13454 / frag_info.gi_counts.w);
            highp vec2 _13476 = vec2((_13454 - (_13462 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13462 * 16.0));
            vec3 _13336 = -mp_copy_17933;
            vec3 _13524 = _13336 / vec3((abs(_13336.x) + abs(_13336.y)) + abs(_13336.z));
            vec2 _17934 = vec2(0.0);
            if (_13524.z >= 0.0)
            {
                _17934 = _13524.xy;
            }
            else
            {
                _17934 = (vec2(1.0) - abs(_13524.yx)) * vec2((_13524.x >= 0.0) ? 1.0 : (-1.0), (_13524.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13340 = texture(irradiance_field, clamp((_13476 + vec2(1.0)) + (clamp((_17934 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13476 + vec2(0.5), _13476 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13345 = _13340.x * frag_info.gi_visibility.z;
            highp float _13357 = abs((_13345 * _13345) - ((_13340.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13363 = (_13295 - _13345) - frag_info.gi_visibility.y;
            highp float _17935 = 0.0;
            if (_13363 <= 0.0)
            {
                _17935 = 1.0;
            }
            else
            {
                _17935 = _13357 / (_13357 + (_13363 * _13363));
            }
            _17938 = _13313 * mix(1.0, max(0.0500000007450580596923828125, (_17935 * _17935) * _17935), frag_info.gi_visibility.x);
        }
        else
        {
            _17938 = _13313;
        }
        float _13391 = max(9.9999999747524270787835121154785e-07, _17938);
        float _17939 = 0.0;
        if (_13391 < 0.20000000298023223876953125)
        {
            _17939 = _13391 * ((_13391 * _13391) * 25.0);
        }
        else
        {
            _17939 = _13391;
        }
        float _13406 = _17939 * (((_13277.x * _13277.y) * _13277.z) * mp_copy_13271);
        highp float _13565 = floor(_13454 / frag_info.gi_counts.w);
        highp vec2 _13579 = vec2((_13454 - (_13565 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13565 * 8.0));
        vec2 _17940 = vec2(0.0);
        if (_13171)
        {
            _17940 = _13168.xy;
        }
        else
        {
            _17940 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13418 = texture(irradiance_field, clamp((_13579 + vec2(1.0)) + (clamp((_17940 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13579 + vec2(0.5), _13579 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13713 = _12672 + vec3(0.0, 1.0, 0.0);
        highp vec3 _13718 = _13713 - frag_info.gi_anchor.xyz;
        bool _13721 = any(lessThan(_13718, vec3(0.0)));
        bool _13729 = false;
        if (!_13721)
        {
            _13729 = any(greaterThanEqual(_13718, frag_info.gi_counts.xyz));
        }
        else
        {
            _13729 = _13721;
        }
        vec3 mp_copy_17942 = vec3(0.0);
        highp float _13730 = _13729 ? 0.0 : 1.0;
        float mp_copy_13730 = _13730;
        vec3 _13736 = max(mix(_12814, mp_copy_12678, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13752 = (_13713 * frag_info.gi_grid.xyz) - _12667;
        highp float _13754 = length(_13752);
        highp vec3 _17942 = vec3(0.0);
        if (_13754 > 9.9999997473787516355514526367188e-06)
        {
            _17942 = _13752 / vec3(_13754);
        }
        else
        {
            _17942 = _17804;
        }
        mp_copy_17942 = _17942;
        float _13772 = pow((dot(_17942, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13897 = _13713 - (frag_info.gi_counts.xyz * floor(_13713 / frag_info.gi_counts.xyz));
        highp float _13913 = _13897.x + (frag_info.gi_counts.x * (_13897.y + (frag_info.gi_counts.y * _13897.z)));
        float _17947 = 0.0;
        if (_12865)
        {
            highp float _13921 = floor(_13913 / frag_info.gi_counts.w);
            highp vec2 _13935 = vec2((_13913 - (_13921 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13921 * 16.0));
            vec3 _13795 = -mp_copy_17942;
            vec3 _13983 = _13795 / vec3((abs(_13795.x) + abs(_13795.y)) + abs(_13795.z));
            vec2 _17943 = vec2(0.0);
            if (_13983.z >= 0.0)
            {
                _17943 = _13983.xy;
            }
            else
            {
                _17943 = (vec2(1.0) - abs(_13983.yx)) * vec2((_13983.x >= 0.0) ? 1.0 : (-1.0), (_13983.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13799 = texture(irradiance_field, clamp((_13935 + vec2(1.0)) + (clamp((_17943 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13935 + vec2(0.5), _13935 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13804 = _13799.x * frag_info.gi_visibility.z;
            highp float _13816 = abs((_13804 * _13804) - ((_13799.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13822 = (_13754 - _13804) - frag_info.gi_visibility.y;
            highp float _17944 = 0.0;
            if (_13822 <= 0.0)
            {
                _17944 = 1.0;
            }
            else
            {
                _17944 = _13816 / (_13816 + (_13822 * _13822));
            }
            _17947 = _13772 * mix(1.0, max(0.0500000007450580596923828125, (_17944 * _17944) * _17944), frag_info.gi_visibility.x);
        }
        else
        {
            _17947 = _13772;
        }
        float _13850 = max(9.9999999747524270787835121154785e-07, _17947);
        float _17948 = 0.0;
        if (_13850 < 0.20000000298023223876953125)
        {
            _17948 = _13850 * ((_13850 * _13850) * 25.0);
        }
        else
        {
            _17948 = _13850;
        }
        float _13865 = _17948 * (((_13736.x * _13736.y) * _13736.z) * mp_copy_13730);
        highp float _14024 = floor(_13913 / frag_info.gi_counts.w);
        highp vec2 _14038 = vec2((_13913 - (_14024 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14024 * 8.0));
        vec2 _17949 = vec2(0.0);
        if (_13171)
        {
            _17949 = _13168.xy;
        }
        else
        {
            _17949 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13877 = texture(irradiance_field, clamp((_14038 + vec2(1.0)) + (clamp((_17949 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14038 + vec2(0.5), _14038 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14172 = _12672 + vec3(1.0, 1.0, 0.0);
        highp vec3 _14177 = _14172 - frag_info.gi_anchor.xyz;
        bool _14180 = any(lessThan(_14177, vec3(0.0)));
        bool _14188 = false;
        if (!_14180)
        {
            _14188 = any(greaterThanEqual(_14177, frag_info.gi_counts.xyz));
        }
        else
        {
            _14188 = _14180;
        }
        vec3 mp_copy_17951 = vec3(0.0);
        highp float _14189 = _14188 ? 0.0 : 1.0;
        float mp_copy_14189 = _14189;
        vec3 _14195 = max(mix(_12814, mp_copy_12678, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14211 = (_14172 * frag_info.gi_grid.xyz) - _12667;
        highp float _14213 = length(_14211);
        highp vec3 _17951 = vec3(0.0);
        if (_14213 > 9.9999997473787516355514526367188e-06)
        {
            _17951 = _14211 / vec3(_14213);
        }
        else
        {
            _17951 = _17804;
        }
        mp_copy_17951 = _17951;
        float _14231 = pow((dot(_17951, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14356 = _14172 - (frag_info.gi_counts.xyz * floor(_14172 / frag_info.gi_counts.xyz));
        highp float _14372 = _14356.x + (frag_info.gi_counts.x * (_14356.y + (frag_info.gi_counts.y * _14356.z)));
        float _17956 = 0.0;
        if (_12865)
        {
            highp float _14380 = floor(_14372 / frag_info.gi_counts.w);
            highp vec2 _14394 = vec2((_14372 - (_14380 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14380 * 16.0));
            vec3 _14254 = -mp_copy_17951;
            vec3 _14442 = _14254 / vec3((abs(_14254.x) + abs(_14254.y)) + abs(_14254.z));
            vec2 _17952 = vec2(0.0);
            if (_14442.z >= 0.0)
            {
                _17952 = _14442.xy;
            }
            else
            {
                _17952 = (vec2(1.0) - abs(_14442.yx)) * vec2((_14442.x >= 0.0) ? 1.0 : (-1.0), (_14442.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14258 = texture(irradiance_field, clamp((_14394 + vec2(1.0)) + (clamp((_17952 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14394 + vec2(0.5), _14394 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14263 = _14258.x * frag_info.gi_visibility.z;
            highp float _14275 = abs((_14263 * _14263) - ((_14258.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14281 = (_14213 - _14263) - frag_info.gi_visibility.y;
            highp float _17953 = 0.0;
            if (_14281 <= 0.0)
            {
                _17953 = 1.0;
            }
            else
            {
                _17953 = _14275 / (_14275 + (_14281 * _14281));
            }
            _17956 = _14231 * mix(1.0, max(0.0500000007450580596923828125, (_17953 * _17953) * _17953), frag_info.gi_visibility.x);
        }
        else
        {
            _17956 = _14231;
        }
        float _14309 = max(9.9999999747524270787835121154785e-07, _17956);
        float _17957 = 0.0;
        if (_14309 < 0.20000000298023223876953125)
        {
            _17957 = _14309 * ((_14309 * _14309) * 25.0);
        }
        else
        {
            _17957 = _14309;
        }
        float _14324 = _17957 * (((_14195.x * _14195.y) * _14195.z) * mp_copy_14189);
        highp float _14483 = floor(_14372 / frag_info.gi_counts.w);
        highp vec2 _14497 = vec2((_14372 - (_14483 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14483 * 8.0));
        vec2 _17958 = vec2(0.0);
        if (_13171)
        {
            _17958 = _13168.xy;
        }
        else
        {
            _17958 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14336 = texture(irradiance_field, clamp((_14497 + vec2(1.0)) + (clamp((_17958 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14497 + vec2(0.5), _14497 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14631 = _12672 + vec3(0.0, 0.0, 1.0);
        highp vec3 _14636 = _14631 - frag_info.gi_anchor.xyz;
        bool _14639 = any(lessThan(_14636, vec3(0.0)));
        bool _14647 = false;
        if (!_14639)
        {
            _14647 = any(greaterThanEqual(_14636, frag_info.gi_counts.xyz));
        }
        else
        {
            _14647 = _14639;
        }
        vec3 mp_copy_17960 = vec3(0.0);
        highp float _14648 = _14647 ? 0.0 : 1.0;
        float mp_copy_14648 = _14648;
        vec3 _14654 = max(mix(_12814, mp_copy_12678, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14670 = (_14631 * frag_info.gi_grid.xyz) - _12667;
        highp float _14672 = length(_14670);
        highp vec3 _17960 = vec3(0.0);
        if (_14672 > 9.9999997473787516355514526367188e-06)
        {
            _17960 = _14670 / vec3(_14672);
        }
        else
        {
            _17960 = _17804;
        }
        mp_copy_17960 = _17960;
        float _14690 = pow((dot(_17960, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14815 = _14631 - (frag_info.gi_counts.xyz * floor(_14631 / frag_info.gi_counts.xyz));
        highp float _14831 = _14815.x + (frag_info.gi_counts.x * (_14815.y + (frag_info.gi_counts.y * _14815.z)));
        float _17965 = 0.0;
        if (_12865)
        {
            highp float _14839 = floor(_14831 / frag_info.gi_counts.w);
            highp vec2 _14853 = vec2((_14831 - (_14839 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14839 * 16.0));
            vec3 _14713 = -mp_copy_17960;
            vec3 _14901 = _14713 / vec3((abs(_14713.x) + abs(_14713.y)) + abs(_14713.z));
            vec2 _17961 = vec2(0.0);
            if (_14901.z >= 0.0)
            {
                _17961 = _14901.xy;
            }
            else
            {
                _17961 = (vec2(1.0) - abs(_14901.yx)) * vec2((_14901.x >= 0.0) ? 1.0 : (-1.0), (_14901.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14717 = texture(irradiance_field, clamp((_14853 + vec2(1.0)) + (clamp((_17961 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14853 + vec2(0.5), _14853 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14722 = _14717.x * frag_info.gi_visibility.z;
            highp float _14734 = abs((_14722 * _14722) - ((_14717.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14740 = (_14672 - _14722) - frag_info.gi_visibility.y;
            highp float _17962 = 0.0;
            if (_14740 <= 0.0)
            {
                _17962 = 1.0;
            }
            else
            {
                _17962 = _14734 / (_14734 + (_14740 * _14740));
            }
            _17965 = _14690 * mix(1.0, max(0.0500000007450580596923828125, (_17962 * _17962) * _17962), frag_info.gi_visibility.x);
        }
        else
        {
            _17965 = _14690;
        }
        float _14768 = max(9.9999999747524270787835121154785e-07, _17965);
        float _17966 = 0.0;
        if (_14768 < 0.20000000298023223876953125)
        {
            _17966 = _14768 * ((_14768 * _14768) * 25.0);
        }
        else
        {
            _17966 = _14768;
        }
        float _14783 = _17966 * (((_14654.x * _14654.y) * _14654.z) * mp_copy_14648);
        highp float _14942 = floor(_14831 / frag_info.gi_counts.w);
        highp vec2 _14956 = vec2((_14831 - (_14942 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14942 * 8.0));
        vec2 _17967 = vec2(0.0);
        if (_13171)
        {
            _17967 = _13168.xy;
        }
        else
        {
            _17967 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14795 = texture(irradiance_field, clamp((_14956 + vec2(1.0)) + (clamp((_17967 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14956 + vec2(0.5), _14956 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15090 = _12672 + vec3(1.0, 0.0, 1.0);
        highp vec3 _15095 = _15090 - frag_info.gi_anchor.xyz;
        bool _15098 = any(lessThan(_15095, vec3(0.0)));
        bool _15106 = false;
        if (!_15098)
        {
            _15106 = any(greaterThanEqual(_15095, frag_info.gi_counts.xyz));
        }
        else
        {
            _15106 = _15098;
        }
        vec3 mp_copy_17969 = vec3(0.0);
        highp float _15107 = _15106 ? 0.0 : 1.0;
        float mp_copy_15107 = _15107;
        vec3 _15113 = max(mix(_12814, mp_copy_12678, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15129 = (_15090 * frag_info.gi_grid.xyz) - _12667;
        highp float _15131 = length(_15129);
        highp vec3 _17969 = vec3(0.0);
        if (_15131 > 9.9999997473787516355514526367188e-06)
        {
            _17969 = _15129 / vec3(_15131);
        }
        else
        {
            _17969 = _17804;
        }
        mp_copy_17969 = _17969;
        float _15149 = pow((dot(_17969, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15274 = _15090 - (frag_info.gi_counts.xyz * floor(_15090 / frag_info.gi_counts.xyz));
        highp float _15290 = _15274.x + (frag_info.gi_counts.x * (_15274.y + (frag_info.gi_counts.y * _15274.z)));
        float _17974 = 0.0;
        if (_12865)
        {
            highp float _15298 = floor(_15290 / frag_info.gi_counts.w);
            highp vec2 _15312 = vec2((_15290 - (_15298 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15298 * 16.0));
            vec3 _15172 = -mp_copy_17969;
            vec3 _15360 = _15172 / vec3((abs(_15172.x) + abs(_15172.y)) + abs(_15172.z));
            vec2 _17970 = vec2(0.0);
            if (_15360.z >= 0.0)
            {
                _17970 = _15360.xy;
            }
            else
            {
                _17970 = (vec2(1.0) - abs(_15360.yx)) * vec2((_15360.x >= 0.0) ? 1.0 : (-1.0), (_15360.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15176 = texture(irradiance_field, clamp((_15312 + vec2(1.0)) + (clamp((_17970 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15312 + vec2(0.5), _15312 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15181 = _15176.x * frag_info.gi_visibility.z;
            highp float _15193 = abs((_15181 * _15181) - ((_15176.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15199 = (_15131 - _15181) - frag_info.gi_visibility.y;
            highp float _17971 = 0.0;
            if (_15199 <= 0.0)
            {
                _17971 = 1.0;
            }
            else
            {
                _17971 = _15193 / (_15193 + (_15199 * _15199));
            }
            _17974 = _15149 * mix(1.0, max(0.0500000007450580596923828125, (_17971 * _17971) * _17971), frag_info.gi_visibility.x);
        }
        else
        {
            _17974 = _15149;
        }
        float _15227 = max(9.9999999747524270787835121154785e-07, _17974);
        float _17975 = 0.0;
        if (_15227 < 0.20000000298023223876953125)
        {
            _17975 = _15227 * ((_15227 * _15227) * 25.0);
        }
        else
        {
            _17975 = _15227;
        }
        float _15242 = _17975 * (((_15113.x * _15113.y) * _15113.z) * mp_copy_15107);
        highp float _15401 = floor(_15290 / frag_info.gi_counts.w);
        highp vec2 _15415 = vec2((_15290 - (_15401 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15401 * 8.0));
        vec2 _17976 = vec2(0.0);
        if (_13171)
        {
            _17976 = _13168.xy;
        }
        else
        {
            _17976 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15254 = texture(irradiance_field, clamp((_15415 + vec2(1.0)) + (clamp((_17976 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15415 + vec2(0.5), _15415 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15549 = _12672 + vec3(0.0, 1.0, 1.0);
        highp vec3 _15554 = _15549 - frag_info.gi_anchor.xyz;
        bool _15557 = any(lessThan(_15554, vec3(0.0)));
        bool _15565 = false;
        if (!_15557)
        {
            _15565 = any(greaterThanEqual(_15554, frag_info.gi_counts.xyz));
        }
        else
        {
            _15565 = _15557;
        }
        vec3 mp_copy_17978 = vec3(0.0);
        highp float _15566 = _15565 ? 0.0 : 1.0;
        float mp_copy_15566 = _15566;
        vec3 _15572 = max(mix(_12814, mp_copy_12678, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15588 = (_15549 * frag_info.gi_grid.xyz) - _12667;
        highp float _15590 = length(_15588);
        highp vec3 _17978 = vec3(0.0);
        if (_15590 > 9.9999997473787516355514526367188e-06)
        {
            _17978 = _15588 / vec3(_15590);
        }
        else
        {
            _17978 = _17804;
        }
        mp_copy_17978 = _17978;
        float _15608 = pow((dot(_17978, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15733 = _15549 - (frag_info.gi_counts.xyz * floor(_15549 / frag_info.gi_counts.xyz));
        highp float _15749 = _15733.x + (frag_info.gi_counts.x * (_15733.y + (frag_info.gi_counts.y * _15733.z)));
        float _17983 = 0.0;
        if (_12865)
        {
            highp float _15757 = floor(_15749 / frag_info.gi_counts.w);
            highp vec2 _15771 = vec2((_15749 - (_15757 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15757 * 16.0));
            vec3 _15631 = -mp_copy_17978;
            vec3 _15819 = _15631 / vec3((abs(_15631.x) + abs(_15631.y)) + abs(_15631.z));
            vec2 _17979 = vec2(0.0);
            if (_15819.z >= 0.0)
            {
                _17979 = _15819.xy;
            }
            else
            {
                _17979 = (vec2(1.0) - abs(_15819.yx)) * vec2((_15819.x >= 0.0) ? 1.0 : (-1.0), (_15819.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15635 = texture(irradiance_field, clamp((_15771 + vec2(1.0)) + (clamp((_17979 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15771 + vec2(0.5), _15771 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15640 = _15635.x * frag_info.gi_visibility.z;
            highp float _15652 = abs((_15640 * _15640) - ((_15635.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15658 = (_15590 - _15640) - frag_info.gi_visibility.y;
            highp float _17980 = 0.0;
            if (_15658 <= 0.0)
            {
                _17980 = 1.0;
            }
            else
            {
                _17980 = _15652 / (_15652 + (_15658 * _15658));
            }
            _17983 = _15608 * mix(1.0, max(0.0500000007450580596923828125, (_17980 * _17980) * _17980), frag_info.gi_visibility.x);
        }
        else
        {
            _17983 = _15608;
        }
        float _15686 = max(9.9999999747524270787835121154785e-07, _17983);
        float _17984 = 0.0;
        if (_15686 < 0.20000000298023223876953125)
        {
            _17984 = _15686 * ((_15686 * _15686) * 25.0);
        }
        else
        {
            _17984 = _15686;
        }
        float _15701 = _17984 * (((_15572.x * _15572.y) * _15572.z) * mp_copy_15566);
        highp float _15860 = floor(_15749 / frag_info.gi_counts.w);
        highp vec2 _15874 = vec2((_15749 - (_15860 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15860 * 8.0));
        vec2 _17985 = vec2(0.0);
        if (_13171)
        {
            _17985 = _13168.xy;
        }
        else
        {
            _17985 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15713 = texture(irradiance_field, clamp((_15874 + vec2(1.0)) + (clamp((_17985 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15874 + vec2(0.5), _15874 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _16008 = _12672 + vec3(1.0);
        highp vec3 _16013 = _16008 - frag_info.gi_anchor.xyz;
        bool _16016 = any(lessThan(_16013, vec3(0.0)));
        bool _16024 = false;
        if (!_16016)
        {
            _16024 = any(greaterThanEqual(_16013, frag_info.gi_counts.xyz));
        }
        else
        {
            _16024 = _16016;
        }
        vec3 mp_copy_17987 = vec3(0.0);
        highp float _16025 = _16024 ? 0.0 : 1.0;
        float mp_copy_16025 = _16025;
        vec3 _16031 = max(mp_copy_12678, vec3(0.001000000047497451305389404296875));
        highp vec3 _16047 = (_16008 * frag_info.gi_grid.xyz) - _12667;
        highp float _16049 = length(_16047);
        highp vec3 _17987 = vec3(0.0);
        if (_16049 > 9.9999997473787516355514526367188e-06)
        {
            _17987 = _16047 / vec3(_16049);
        }
        else
        {
            _17987 = _17804;
        }
        mp_copy_17987 = _17987;
        float _16067 = pow((dot(_17987, _17804) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _16192 = _16008 - (frag_info.gi_counts.xyz * floor(_16008 / frag_info.gi_counts.xyz));
        highp float _16208 = _16192.x + (frag_info.gi_counts.x * (_16192.y + (frag_info.gi_counts.y * _16192.z)));
        float _17992 = 0.0;
        if (_12865)
        {
            highp float _16216 = floor(_16208 / frag_info.gi_counts.w);
            highp vec2 _16230 = vec2((_16208 - (_16216 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16216 * 16.0));
            vec3 _16090 = -mp_copy_17987;
            vec3 _16278 = _16090 / vec3((abs(_16090.x) + abs(_16090.y)) + abs(_16090.z));
            vec2 _17988 = vec2(0.0);
            if (_16278.z >= 0.0)
            {
                _17988 = _16278.xy;
            }
            else
            {
                _17988 = (vec2(1.0) - abs(_16278.yx)) * vec2((_16278.x >= 0.0) ? 1.0 : (-1.0), (_16278.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _16094 = texture(irradiance_field, clamp((_16230 + vec2(1.0)) + (clamp((_17988 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16230 + vec2(0.5), _16230 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _16099 = _16094.x * frag_info.gi_visibility.z;
            highp float _16111 = abs((_16099 * _16099) - ((_16094.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _16117 = (_16049 - _16099) - frag_info.gi_visibility.y;
            highp float _17989 = 0.0;
            if (_16117 <= 0.0)
            {
                _17989 = 1.0;
            }
            else
            {
                _17989 = _16111 / (_16111 + (_16117 * _16117));
            }
            _17992 = _16067 * mix(1.0, max(0.0500000007450580596923828125, (_17989 * _17989) * _17989), frag_info.gi_visibility.x);
        }
        else
        {
            _17992 = _16067;
        }
        float _16145 = max(9.9999999747524270787835121154785e-07, _17992);
        float _17993 = 0.0;
        if (_16145 < 0.20000000298023223876953125)
        {
            _17993 = _16145 * ((_16145 * _16145) * 25.0);
        }
        else
        {
            _17993 = _16145;
        }
        float _16160 = _17993 * (((_16031.x * _16031.y) * _16031.z) * mp_copy_16025);
        highp float _16319 = floor(_16208 / frag_info.gi_counts.w);
        highp vec2 _16333 = vec2((_16208 - (_16319 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16319 * 8.0));
        vec2 _17994 = vec2(0.0);
        if (_13171)
        {
            _17994 = _13168.xy;
        }
        else
        {
            _17994 = (vec2(1.0) - abs(_13168.yx)) * vec2((_13168.x >= 0.0) ? 1.0 : (-1.0), (_13168.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12725 = ((((((vec4(max(_12959.xyz, vec3(0.0)) * _12947, _12947) + vec4(max(_13418.xyz, vec3(0.0)) * _13406, _13406)) + vec4(max(_13877.xyz, vec3(0.0)) * _13865, _13865)) + vec4(max(_14336.xyz, vec3(0.0)) * _14324, _14324)) + vec4(max(_14795.xyz, vec3(0.0)) * _14783, _14783)) + vec4(max(_15254.xyz, vec3(0.0)) * _15242, _15242)) + vec4(max(_15713.xyz, vec3(0.0)) * _15701, _15701)) + vec4(max(texture(irradiance_field, clamp((_16333 + vec2(1.0)) + (clamp((_17994 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16333 + vec2(0.5), _16333 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _16160, _16160);
        highp float _12727 = _12725.w;
        highp vec3 _17996 = vec3(0.0);
        if (_12727 > 9.9999999747524270787835121154785e-07)
        {
            _17996 = _12725.xyz / vec3(_12727);
        }
        else
        {
            _17996 = vec3(0.0);
        }
        _18114 = mix(_7626, _17996 * _12554, vec3(_17923));
    }
    else
    {
        _18114 = _7626;
    }
    vec2 _7652 = clamp(vec2(_7202, _17852), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7654 = texture(brdf_lut, vec2(_7652.x * 0.3333333432674407958984375, _7652.y));
    float _7658 = _7654.x;
    float _7661 = _7654.y;
    vec3 _7663 = ((_7194 + ((max(vec3(1.0 - _17852), _7194) - _7194) * pow(clamp(1.0 - _7202, 0.0, 1.0), 5.0))) * _7658) + vec3(_7661);
    float _7669 = 1.0 - (_7658 + _7661);
    vec3 _7673 = vec3(1.0) - _7194;
    vec3 _7676 = _7194 + (_7673 * vec3(0.0476190485060214996337890625));
    vec3 _7687 = ((_7663 * _7669) * _7676) / (vec3(1.0) - (_7676 * _7669));
    float _7690 = 1.0 - _6149;
    vec3 _7691 = _7046 * _7690;
    float _18393 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7596)
    {
        float _16455 = max(acos(clamp(exp2(((-3.321929931640625) * _17852) * _17852), 0.0, 1.0)), 0.100000001490116119384765625);
        _18393 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_17908, _7206), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _18191, 0.0, 1.0)))) + _16455) / (2.0 * _16455), 0.0, 1.0));
    }
    else
    {
        float _18394 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _18394 = clamp((pow(_7198 + _18191, exp2(((-16.0) * _17852) - 1.0)) - 1.0) + _18191, 0.0, 1.0);
        }
        else
        {
            _18394 = _18191;
        }
        _18393 = _18394;
    }
    highp vec3 _7750 = ((((_7687 + (_7691 * ((vec3(1.0) - _7663) - _7687))) * _18114) * _18331) + (((_7663 * (_17922 * _7624)) * 1.0) * _18393)) * mix(1.0, _7185, frag_info.radiance_blend.y);
    highp vec3 _18625 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _18625 = _7750 + ((_17875.xyz * _7691) * _6183);
    }
    else
    {
        _18625 = _7750;
    }
    highp vec3 _18629 = vec3(0.0);
    if (_7135)
    {
        highp vec3 _18544 = vec3(0.0);
        highp vec3 _18545 = vec3(0.0);
        do
        {
            float _16538 = max(dot(_17804, _18479), 0.0);
            highp float hp_copy_16538 = _16538;
            if (_16538 <= 0.0)
            {
                _18545 = vec3(0.0);
                _18544 = vec3(0.0);
                break;
            }
            float _16544 = max(_7198, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_16544 = _16544;
            vec3 _16547 = _18479 + mp_copy_17882;
            float _16550 = dot(_16547, _16547);
            vec3 _18542 = vec3(0.0);
            vec3 _18543 = vec3(0.0);
            if (_16550 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _16558 = _16547 * inversesqrt(_16550);
                float _18541 = 0.0;
                do
                {
                    float _16615 = dot(_17804, _16558);
                    if (_16615 <= 0.0)
                    {
                        _18541 = 0.0;
                        break;
                    }
                    float _16622 = _17852 * _17852;
                    vec3 _16625 = cross(_17804, _16558);
                    float _16628 = _16615 * _16622;
                    float _16637 = _16622 / (dot(_16625, _16625) + (_16628 * _16628));
                    _18541 = min((_16637 * _16637) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _16675 = _7194 + (_7673 * pow(clamp(1.0 - max(dot(_16558, _17882), 0.0), 0.0, 1.0), 5.0));
                _18543 = (_16675 * min(_18541 * (0.5 / max(mix((2.0 * hp_copy_16538) * _16544, hp_copy_16538 + hp_copy_16544, hp_copy_17852 * hp_copy_17852), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _18542 = _16675;
            }
            else
            {
                _18543 = vec3(0.0);
                _18542 = _7194;
            }
            _18545 = (_18543 * frag_info.directional_light_color.xyz) * _16538;
            _18544 = (((((vec3(1.0) - _18542) * _7690) * _7046) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _16538;
            break;
        } while(false);
        _18629 = _18555 + ((_18544 + _18545) * _7185);
    }
    else
    {
        _18629 = _18555;
    }
    bool _7812 = _FogInfo.params0.y > 0.5;
    bool _7818 = false;
    if (_7812)
    {
        _7818 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7818 = _7812;
    }
    highp vec3 _18632 = vec3(0.0);
    if (_7818)
    {
        vec3 mp_copy_18630 = vec3(0.0);
        highp vec3 _18630 = vec3(0.0);
        if (_9810)
        {
            _18630 = -view_info.camera_forward.xyz;
        }
        else
        {
            _18630 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_18631 = vec3(0.0);
        mp_copy_18630 = _18630;
        vec3 _7823 = _7593 * (-mp_copy_18630);
        vec3 _18631 = vec3(0.0);
        do
        {
            if (_12309)
            {
                vec2 _16797 = vec2(atan(_7823.z, _7823.x), asin(clamp(_7823.y, -1.0, 1.0)));
                highp vec2 hp_copy_16797 = _16797;
                _18631 = textureLod(prefiltered_radiance, (hp_copy_16797 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _16816 = vec2(atan(_7823.z, _7823.x), asin(clamp(_7823.y, -1.0, 1.0)));
            highp vec2 hp_copy_16816 = _16816;
            highp vec2 _16821 = (hp_copy_16816 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _16728 = clamp(_16821.y, 0.00390625, 0.99609375);
            float _16734 = floor(0.0);
            highp float _16753 = _16821.x;
            _18631 = mix(textureLod(prefiltered_radiance, vec2(_16753, (_16734 + _16728) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_16753, (min(_16734 + 1.0, 7.0) + _16728) * 0.125), 0.0).xyz, vec3(-_16734));
            break;
        } while(false);
        hp_copy_18631 = _18631;
        _18632 = hp_copy_18631 * hp_copy_7624;
    }
    else
    {
        _18632 = _FogInfo.color.xyz;
    }
    highp vec4 _7838 = vec4(min((_18625 + (_18629 * mix(1.0, _18191, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _17827, vec3(65504.0)), 1.0) * _19426;
    highp vec4 _18647 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _18647 = _7838;
            break;
        }
        int _16865 = int(_FogInfo.params0.x + 0.5);
        if (_16865 == 0)
        {
            _18647 = _7838;
            break;
        }
        highp float _18634 = 0.0;
        if (_9810)
        {
            _18634 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _18634 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_18634 > _FogInfo.params1.w))
        {
            _18647 = _7838;
            break;
        }
        float _18638 = 0.0;
        if (_16865 == 1)
        {
            _18638 = clamp((_18634 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _18639 = 0.0;
            if (_16865 == 2)
            {
                highp float _18637 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _18635 = vec3(0.0);
                    if (_9810)
                    {
                        _18635 = v_position - (view_info.camera_forward.xyz * _18634);
                    }
                    else
                    {
                        _18635 = v_position + v_viewvector;
                    }
                    highp float _16956 = -_FogInfo.params2.y;
                    highp float _16963 = _FogInfo.params1.x * exp(_16956 * (_18635.y - _FogInfo.params2.x));
                    highp float _16980 = _FogInfo.params2.y * (v_position.y - _18635.y);
                    highp float _18636 = 0.0;
                    if (abs(_16980) > 0.00124999997206032276153564453125)
                    {
                        _18636 = (_16963 - (_FogInfo.params1.x * exp(_16956 * (v_position.y - _FogInfo.params2.x)))) / _16980;
                    }
                    else
                    {
                        _18636 = _16963;
                    }
                    _18637 = _18636 * max(_18634 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _18637 = _FogInfo.params1.x * max(_18634 - _FogInfo.params1.y, 0.0);
                }
                _18639 = 1.0 - exp(-_18637);
            }
            else
            {
                highp float _16918 = _FogInfo.params1.x * max(_18634 - _FogInfo.params1.y, 0.0);
                _18639 = 1.0 - exp((-_16918) * _16918);
            }
            _18638 = _18639;
        }
        highp float _17020 = min(_18638, _FogInfo.params0.z);
        if (_17020 <= 0.0)
        {
            _18647 = _7838;
            break;
        }
        highp vec3 _17033 = mix(_FogInfo.color.xyz, _18632, vec3(_FogInfo.params0.w));
        bool _17036 = _FogInfo.sun.w > 0.5;
        bool _17042 = false;
        if (_17036)
        {
            _17042 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _17042 = _17036;
        }
        vec3 _18643 = vec3(0.0);
        if (_17042)
        {
            vec3 mp_copy_18640 = vec3(0.0);
            highp vec3 _18640 = vec3(0.0);
            if (_9810)
            {
                _18640 = -view_info.camera_forward.xyz;
            }
            else
            {
                _18640 = normalize(v_viewvector);
            }
            mp_copy_18640 = _18640;
            highp float _17058 = pow(max(dot(-mp_copy_18640, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_17058 = _17058;
            _18643 = _17033 + ((_FogInfo.sun.xyz * mp_copy_17058) * _FogInfo.params2.z);
        }
        else
        {
            _18643 = _17033;
        }
        highp float _17071 = _7838.w;
        float mp_copy_17071 = _17071;
        _18647 = vec4(mix(_7838.xyz, _18643 * mp_copy_17071, vec3(_17020)), _17071);
        break;
    } while(false);
    vec4 _18649 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _18649 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _18649 = _18647;
        break;
    } while(false);
    frag_color = _18649;
    float _18650 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _18650 = 1.0;
    }
    else
    {
        _18650 = abs(frag_info.fade);
    }
    frag_color *= _18650;
}

