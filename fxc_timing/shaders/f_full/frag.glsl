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
    highp float _6030 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_6030 = _6030;
    vec3 _6034 = normalize(v_normal) * mp_copy_6030;
    vec4 _6076 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _6079 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _18174 = vec2(0.0);
    if (_6079)
    {
        highp vec2 _18173 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _18173 = v_texture_coords_1;
        }
        else
        {
            _18173 = v_texture_coords;
        }
        highp vec2 _6279 = _18173 * texture_transforms.base_color_transform.zw;
        highp float _6285 = _6279.x;
        highp float _6290 = _6279.y;
        _18174 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6285) + (texture_transforms.base_color_rotation.y * _6290), ((-texture_transforms.base_color_rotation.y) * _6285) + (texture_transforms.base_color_rotation.x * _6290));
    }
    else
    {
        _18174 = v_texture_coords;
    }
    vec4 _6093 = texture(base_color_texture, _18174);
    vec3 _6095 = _6093.xyz;
    float _19822 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_6093.w * _6076.w) * frag_info.color.w);
    vec3 _18189 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _18177 = vec2(0.0);
        if (_6079)
        {
            highp vec2 _18176 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _18176 = v_texture_coords_1;
            }
            else
            {
                _18176 = v_texture_coords;
            }
            highp vec2 _6374 = _18176 * texture_transforms.normal_transform.zw;
            highp float _6380 = _6374.x;
            highp float _6385 = _6374.y;
            _18177 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6380) + (texture_transforms.normal_rotation.y * _6385), ((-texture_transforms.normal_rotation.y) * _6380) + (texture_transforms.normal_rotation.x * _6385));
        }
        else
        {
            _18177 = v_texture_coords;
        }
        vec3 _6433 = ((texture(normal_texture, _18177).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6437 = _6433.xy * vec2(frag_info.normal_scale);
        vec3 _17608 = _6433;
        _17608.x = _6437.x;
        _17608.y = _6437.y;
        highp vec3 _6443 = -v_viewvector;
        highp vec3 _6533 = dFdx(_6443);
        highp vec3 _6535 = dFdy(_6443);
        highp vec2 _6537 = dFdx(_18177);
        highp vec2 _6539 = dFdy(_18177);
        bvec2 _19824 = bvec2(length(_6537) == 0.0);
        highp vec2 _19825 = vec2(_19824.x ? vec2(1.0, 0.0).x : _6537.x, _19824.y ? vec2(1.0, 0.0).y : _6537.y);
        bvec2 _19826 = bvec2(length(_6539) == 0.0);
        highp vec2 _19827 = vec2(_19826.x ? vec2(0.0, 1.0).x : _6539.x, _19826.y ? vec2(0.0, 1.0).y : _6539.y);
        highp vec3 _6552 = cross(_6535, _6034);
        highp vec3 _6555 = cross(_6034, _6533);
        highp float _6580 = (dot(cross(_6533, _6535), _6034) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _6583 = ((_6552 * _19825.x) + (_6555 * _19827.x)) * _6580;
        highp float _18184 = 0.0;
        if (gl_FrontFacing)
        {
            _18184 = -_6580;
        }
        else
        {
            _18184 = _6580;
        }
        highp vec3 _6593 = ((_6552 * _19825.y) + (_6555 * _19827.y)) * _18184;
        highp float _6602 = inversesqrt(max(max(dot(_6583, _6583), dot(_6593, _6593)), 9.9999996826552253889678874634872e-21));
        vec3 _6474 = v_tangent.xyz - (_6034 * dot(_6034, v_tangent.xyz));
        highp float _6477 = dot(_6474, _6474);
        bool _6479 = _6477 > 1.0000000133514319600180897396058e-10;
        bool _6486 = false;
        if (_6479)
        {
            _6486 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _6486 = _6479;
        }
        mat3 _18187 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_6486)
        {
            highp vec3 _6491 = _6474 * inversesqrt(_6477);
            _18187 = mat3(_6491, normalize(cross(_6034, _6491)) * sign(v_tangent.w), _6034);
        }
        else
        {
            _18187 = mat3(_6583 * _6602, _6593 * _6602, _6034);
        }
        _18189 = normalize(_18187 * _17608);
    }
    else
    {
        _18189 = _6034;
    }
    highp vec2 _18191 = vec2(0.0);
    if (_6079)
    {
        highp vec2 _18190 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _18190 = v_texture_coords_1;
        }
        else
        {
            _18190 = v_texture_coords;
        }
        highp vec2 _6667 = _18190 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6673 = _6667.x;
        highp float _6678 = _6667.y;
        _18191 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6673) + (texture_transforms.metallic_roughness_rotation.y * _6678), ((-texture_transforms.metallic_roughness_rotation.y) * _6673) + (texture_transforms.metallic_roughness_rotation.x * _6678));
    }
    else
    {
        _18191 = v_texture_coords;
    }
    vec4 _6162 = texture(metallic_roughness_texture, _18191);
    float _6168 = clamp(_6162.z * frag_info.metallic_factor, 0.0, 1.0);
    float _6175 = clamp(_6162.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _18193 = vec2(0.0);
    if (_6079)
    {
        highp vec2 _18192 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _18192 = v_texture_coords_1;
        }
        else
        {
            _18192 = v_texture_coords;
        }
        highp vec2 _6738 = _18192 * texture_transforms.occlusion_transform.zw;
        highp float _6744 = _6738.x;
        highp float _6749 = _6738.y;
        _18193 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6744) + (texture_transforms.occlusion_rotation.y * _6749), ((-texture_transforms.occlusion_rotation.y) * _6744) + (texture_transforms.occlusion_rotation.x * _6749));
    }
    else
    {
        _18193 = v_texture_coords;
    }
    float _18194 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _18194 = texture(occlusion_texture, _18193).x;
    }
    else
    {
        _18194 = 1.0;
    }
    float _6202 = 1.0 - ((1.0 - _18194) * frag_info.occlusion_strength);
    highp vec2 _18196 = vec2(0.0);
    if (_6079)
    {
        highp vec2 _18195 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _18195 = v_texture_coords_1;
        }
        else
        {
            _18195 = v_texture_coords;
        }
        highp vec2 _6809 = _18195 * texture_transforms.emissive_transform.zw;
        highp float _6815 = _6809.x;
        highp float _6820 = _6809.y;
        _18196 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6815) + (texture_transforms.emissive_rotation.y * _6820), ((-texture_transforms.emissive_rotation.y) * _6815) + (texture_transforms.emissive_rotation.x * _6820));
    }
    else
    {
        _18196 = v_texture_coords;
    }
    vec3 _6221 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _18212 = vec3(0.0);
    if (dot(abs(_6221), vec3(1.0)) > 0.0)
    {
        vec3 _6230 = texture(emissive_texture, _18196).xyz;
        _18212 = mix(_6230 * vec3(0.077399380505084991455078125), pow((_6230 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6230)) * _6221;
    }
    else
    {
        _18212 = vec3(0.0);
    }
    highp float hp_copy_18237 = 0.0;
    vec3 _7070 = vec4((mix(_6095 * vec3(0.077399380505084991455078125), pow((_6095 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6095)) * _6076.xyz) * frag_info.color.xyz, _19822).xyz;
    vec3 _7895 = dFdx(_18189);
    vec3 _7897 = dFdy(_18189);
    float _18237 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _18237 = sqrt(clamp((_6175 * _6175) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7895, _7895), dot(_7897, _7897))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _18237 = _6175;
    }
    hp_copy_18237 = _18237;
    vec4 _18262 = vec4(0.0);
    float _18280 = 0.0;
    vec3 _18295 = vec3(0.0);
    float _18578 = 0.0;
    vec3 _18717 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _7097 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _18238 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _18238 = _7097.w;
        }
        else
        {
            _18238 = _7097.x;
        }
        float _7110 = min(_6202, _18238);
        bool _7113 = frag_info.ssao_lighting.z > 0.5;
        bool _7119 = false;
        if (_7113)
        {
            _7119 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _7119 = _7113;
        }
        vec3 _18296 = vec3(0.0);
        if (_7119)
        {
            vec2 _7935 = (_7097.zw * 2.0) - vec2(1.0);
            float _7937 = _7935.x;
            float _7939 = _7935.y;
            float _7947 = (1.0 - abs(_7937)) - abs(_7939);
            vec3 _7948 = vec3(_7937, _7939, _7947);
            vec3 _18241 = vec3(0.0);
            if (_7947 < 0.0)
            {
                vec2 _7961 = (vec2(1.0) - abs(_7948.yx)) * vec2((_7937 >= 0.0) ? 1.0 : (-1.0), (_7939 >= 0.0) ? 1.0 : (-1.0));
                vec3 _17657 = _7948;
                _17657.x = _7961.x;
                _17657.y = _7961.y;
                _18241 = _17657;
            }
            else
            {
                _18241 = _7948;
            }
            vec3 _7969 = -normalize(_18241);
            _18296 = normalize(((frag_info.camera_right.xyz * _7969.x) + (frag_info.camera_up.xyz * _7969.y)) + (frag_info.camera_forward.xyz * _7969.z));
        }
        else
        {
            _18296 = vec3(0.0);
        }
        vec3 _7147 = vec3(_7110);
        _18717 = mix(_7147, max(_7147, ((((((_7070 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _7110) + ((_7070 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _7110) + ((_7070 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _7110), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _18578 = _7110;
        _18295 = _18296;
        _18280 = float(_7119);
        _18262 = _7097;
    }
    else
    {
        _18717 = vec3(_6202);
        _18578 = _6202;
        _18295 = vec3(0.0);
        _18280 = 0.0;
        _18262 = vec4(1.0);
    }
    bool _7159 = frag_info.has_directional_light > 0.5;
    float _18245 = 0.0;
    vec3 _18865 = vec3(0.0);
    if (_7159)
    {
        highp vec3 _7165 = -normalize(frag_info.directional_light_direction.xyz);
        _18865 = _7165;
        _18245 = dot(_6034, _7165);
    }
    else
    {
        _18865 = vec3(0.0);
        _18245 = 0.0;
    }
    float _7172 = clamp(_18245 * 6.666666507720947265625, 0.0, 1.0);
    bool _7181 = false;
    if (_7159)
    {
        _7181 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _7181 = _7159;
    }
    float _18254 = 0.0;
    if (_7181 && (_7172 > 0.0))
    {
        int _8060 = int(frag_info.shadow_cascade_count);
        float _8255 = max(dot(_6034, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _8258 = _8255 * _8255;
        highp vec3 _8278 = v_position + (_6034 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _8258, 0.0)) / _8258, 8.0))));
        highp float _8066 = frag_info.directional_light_color.w * 0.5;
        float _8068 = frag_info.dielectric_f0.w;
        highp float hp_copy_8068 = _8068;
        float _18246 = 0.0;
        if (_8068 > 0.0)
        {
            _18246 = smoothstep(_8068 - max(frag_info.shadow_fade, hp_copy_8068 * 0.100000001490116119384765625), _8068, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _18246 = 0.0;
        }
        float _18248 = 0.0;
        float _18250 = 0.0;
        if (_18246 < 1.0)
        {
            float _18249 = 0.0;
            float _18251 = 0.0;
            _18251 = 0.0;
            _18249 = 0.0;
            float _19346 = 0.0;
            float _19349 = 0.0;
            for (int _18247 = 0; _18247 < _8060; _18251 = _19349, _18249 = _19346, _18247++)
            {
                if (_18251 < 1.0)
                {
                    highp vec4 _8100 = vec4(_8278, 1.0);
                    highp vec4 _19218 = vec4(0.0);
                    highp float _19221 = 0.0;
                    if (_18247 == 0)
                    {
                        _19221 = frag_info.cascade_box_sizes.x;
                        _19218 = frag_info.light_space_matrix[0] * _8100;
                    }
                    else
                    {
                        highp vec4 _19219 = vec4(0.0);
                        highp float _19222 = 0.0;
                        if (_18247 == 1)
                        {
                            _19222 = frag_info.cascade_box_sizes.y;
                            _19219 = frag_info.light_space_matrix[1] * _8100;
                        }
                        else
                        {
                            highp vec4 _19220 = vec4(0.0);
                            highp float _19223 = 0.0;
                            if (_18247 == 2)
                            {
                                _19223 = frag_info.cascade_box_sizes.z;
                                _19220 = frag_info.light_space_matrix[2] * _8100;
                            }
                            else
                            {
                                _19223 = frag_info.cascade_box_sizes.w;
                                _19220 = frag_info.light_space_matrix[3] * _8100;
                            }
                            _19222 = _19223;
                            _19219 = _19220;
                        }
                        _19221 = _19222;
                        _19218 = _19219;
                    }
                    highp vec3 _8145 = _19218.xyz / vec3(_19218.w);
                    highp vec2 _8148 = _8145.xy * 0.5;
                    highp vec2 _8150 = _8148 + vec2(0.5);
                    highp float _8157 = max(frag_info.shadow_softness / _19221, frag_info.shadow_texel_size);
                    highp float _8159 = _8150.x;
                    bool _8161 = _8159 < _8157;
                    bool _8170 = false;
                    if (!_8161)
                    {
                        _8170 = _8159 > (1.0 - _8157);
                    }
                    else
                    {
                        _8170 = _8161;
                    }
                    bool _8178 = false;
                    if (!_8170)
                    {
                        _8178 = _8150.y < _8157;
                    }
                    else
                    {
                        _8178 = _8170;
                    }
                    bool _8187 = false;
                    if (!_8178)
                    {
                        _8187 = _8150.y > (1.0 - _8157);
                    }
                    else
                    {
                        _8187 = _8178;
                    }
                    bool _8194 = false;
                    if (!_8187)
                    {
                        _8194 = _8145.z < 0.0;
                    }
                    else
                    {
                        _8194 = _8187;
                    }
                    bool _8201 = false;
                    if (!_8194)
                    {
                        _8201 = _8145.z > 1.0;
                    }
                    else
                    {
                        _8201 = _8194;
                    }
                    float _19347 = 0.0;
                    float _19350 = 0.0;
                    if (!_8201)
                    {
                        highp vec2 _8294 = vec2(_8157);
                        highp vec2 _8299 = vec2(_8157 + max(_8066, 9.9999997473787516355514526367188e-05));
                        highp vec2 _8307 = vec2(0.5) - _8148;
                        highp vec2 _8309 = smoothstep(_8294, _8299, _8150) * smoothstep(_8294, _8299, _8307);
                        float _19224 = 0.0;
                        if (_8066 > 0.0)
                        {
                            _19224 = _8309.x * _8309.y;
                        }
                        else
                        {
                            _19224 = 1.0;
                        }
                        float _8210 = min(_19224, 1.0 - _18251);
                        float _19348 = 0.0;
                        float _19351 = 0.0;
                        if (_8210 > 0.0)
                        {
                            highp float _8448 = _8145.z - (frag_info.shadow_bias / (7.0 * _19221));
                            highp float _8454 = 1.0 / (float(_8060) + frag_info.spot_shadow_params.x);
                            highp float _8456 = frag_info.directional_light_direction.w;
                            float mp_copy_8456 = _8456;
                            float _8462 = step(0.5, mp_copy_8456) * (1.0 - step(1.5, mp_copy_8456));
                            float _19254 = 0.0;
                            float _19258 = 0.0;
                            if (_8462 < 0.5)
                            {
                                highp float _8473 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_8473 = _8473;
                                _19258 = sin(mp_copy_8473);
                                _19254 = cos(mp_copy_8473);
                            }
                            else
                            {
                                _19258 = 0.0;
                                _19254 = 1.0;
                            }
                            highp float _19261 = 0.0;
                            if ((_8456 > 1.5) && (_8456 < 2.5))
                            {
                                highp float _8497 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _8502 = max(_8497 * _8448, frag_info.shadow_texel_size);
                                float _19250 = 0.0;
                                highp float _19251 = 0.0;
                                _19251 = 0.0;
                                _19250 = 0.0;
                                highp float _8524 = 0.0;
                                float _8527 = 0.0;
                                for (int _19249 = 0; _19249 < 9; _19251 = _8524, _19250 = _8527, _19249++)
                                {
                                    vec2 _19340 = vec2(0.0);
                                    do
                                    {
                                        if (_19249 == 0)
                                        {
                                            _19340 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_19249 == 1)
                                        {
                                            _19340 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_19249 == 2)
                                        {
                                            _19340 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_19249 == 3)
                                        {
                                            _19340 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_19249 == 4)
                                        {
                                            _19340 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_19249 == 5)
                                        {
                                            _19340 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_19249 == 6)
                                        {
                                            _19340 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_19249 == 7)
                                        {
                                            _19340 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_19249 == 8)
                                        {
                                            _19340 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_19249 == 9)
                                        {
                                            _19340 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_19249 == 10)
                                        {
                                            _19340 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_19249 == 11)
                                        {
                                            _19340 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_19249 == 12)
                                        {
                                            _19340 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_19249 == 13)
                                        {
                                            _19340 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_19249 == 14)
                                        {
                                            _19340 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_19249 == 15)
                                        {
                                            _19340 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _19340 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _8831 = clamp(_8150 + (vec2((_19340.x * _19254) - (_19340.y * _19258), (_19340.x * _19258) + (_19340.y * _19254)) * _8502), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _8840 = _8831.y;
                                    highp vec2 _8841 = vec2((float(_18247) + _8831.x) * _8454, _8840);
                                    _8841.y = 1.0 - _8840;
                                    highp vec4 _8848 = textureLod(shadow_map, _8841, 0.0);
                                    highp float _8849 = _8848.x;
                                    highp float _8519 = step(_8849, _8448);
                                    float mp_copy_8519 = _8519;
                                    _8524 = _19251 + (_8849 * _8519);
                                    _8527 = _19250 + mp_copy_8519;
                                }
                                highp float _19252 = 0.0;
                                if (_19250 > 0.0)
                                {
                                    _19252 = _19251 / _19250;
                                }
                                else
                                {
                                    _19252 = _8448;
                                }
                                _19261 = clamp(_8497 * max(_8448 - _19252, 0.0), frag_info.shadow_texel_size, _8157);
                            }
                            else
                            {
                                _19261 = _8157;
                            }
                            bool _8558 = _8456 > 2.5;
                            bool _19262 = false;
                            float _19286 = 0.0;
                            if ((_8456 < 1.5) || _8558)
                            {
                                highp vec2 _8882 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _8886 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _8887 = clamp(_8150, _8882, _8886);
                                highp float _8889 = float(_18247);
                                highp float _8896 = _8887.y;
                                highp vec2 _8897 = vec2((_8889 + _8887.x) * _8454, _8896);
                                _8897.y = 1.0 - _8896;
                                highp float _8909 = float(_8448 <= textureLod(shadow_map, _8897, 0.0).x);
                                float mp_copy_8909 = _8909;
                                float _8919 = (-1.0) * _19254;
                                float _8923 = (-1.0) * _19258;
                                highp vec2 _8947 = clamp(_8150 + (vec2(_8919 - _8923, _8923 + _8919) * _19261), _8882, _8886);
                                highp float _8956 = _8947.y;
                                highp vec2 _8957 = vec2((_8889 + _8947.x) * _8454, _8956);
                                _8957.y = 1.0 - _8956;
                                highp float _8969 = float(_8448 <= textureLod(shadow_map, _8957, 0.0).x);
                                float mp_copy_8969 = _8969;
                                highp vec2 _9007 = clamp(_8150 + (vec2(_19254 - _8923, _19258 + _8919) * _19261), _8882, _8886);
                                highp float _9016 = _9007.y;
                                highp vec2 _9017 = vec2((_8889 + _9007.x) * _8454, _9016);
                                _9017.y = 1.0 - _9016;
                                highp float _9029 = float(_8448 <= textureLod(shadow_map, _9017, 0.0).x);
                                float mp_copy_9029 = _9029;
                                highp vec2 _9067 = clamp(_8150 + (vec2(_8919 - _19258, _8923 + _19254) * _19261), _8882, _8886);
                                highp float _9076 = _9067.y;
                                highp vec2 _9077 = vec2((_8889 + _9067.x) * _8454, _9076);
                                _9077.y = 1.0 - _9076;
                                highp float _9089 = float(_8448 <= textureLod(shadow_map, _9077, 0.0).x);
                                float mp_copy_9089 = _9089;
                                highp vec2 _9127 = clamp(_8150 + (vec2(_19254 - _19258, _19258 + _19254) * _19261), _8882, _8886);
                                highp float _9136 = _9127.y;
                                highp vec2 _9137 = vec2((_8889 + _9127.x) * _8454, _9136);
                                _9137.y = 1.0 - _9136;
                                highp float _9149 = float(_8448 <= textureLod(shadow_map, _9137, 0.0).x);
                                float mp_copy_9149 = _9149;
                                float _8604 = (((mp_copy_8909 + mp_copy_8969) + mp_copy_9029) + mp_copy_9089) + mp_copy_9149;
                                _19286 = _8604 * 0.20000000298023223876953125;
                                _19262 = (_8604 < 0.5) || (_8604 > 4.5);
                            }
                            else
                            {
                                _19286 = 0.0;
                                _19262 = false;
                            }
                            float _19285 = 0.0;
                            if (_19262)
                            {
                                _19285 = _19286;
                            }
                            else
                            {
                                float _19287 = 0.0;
                                if (_8558)
                                {
                                    highp vec2 _9177 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _9181 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _9182 = clamp(_8150 + (vec2(-0.707099974155426025390625) * _19261), _9177, _9181);
                                    highp vec2 _9193 = (vec2(_9182.x, 1.0 - _9182.y) / _9177) - vec2(0.5);
                                    highp vec2 _9195 = floor(_9193);
                                    highp vec2 _9198 = _9193 - _9195;
                                    highp vec2 _9203 = (_9195 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _9205 = float(_18247);
                                    highp vec2 _9213 = vec2((_9205 + _9203.x) * _8454, _9203.y);
                                    highp float _9217 = frag_info.shadow_texel_size * _8454;
                                    highp vec2 _9220 = vec2(_9217, frag_info.shadow_texel_size);
                                    highp vec2 _9229 = vec2(_9217, 0.0);
                                    highp vec2 _9237 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _9266 = _9198.x;
                                    highp float _9275 = mix(mix(float(_8448 <= textureLod(shadow_map, _9213, 0.0).x), float(_8448 <= textureLod(shadow_map, _9213 + _9229, 0.0).x), _9266), mix(float(_8448 <= textureLod(shadow_map, _9213 + _9237, 0.0).x), float(_8448 <= textureLod(shadow_map, _9213 + _9220, 0.0).x), _9266), _9198.y);
                                    float mp_copy_9275 = _9275;
                                    highp vec2 _9309 = clamp(_8150 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _19261), _9177, _9181);
                                    highp vec2 _9320 = (vec2(_9309.x, 1.0 - _9309.y) / _9177) - vec2(0.5);
                                    highp vec2 _9322 = floor(_9320);
                                    highp vec2 _9325 = _9320 - _9322;
                                    highp vec2 _9330 = (_9322 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9340 = vec2((_9205 + _9330.x) * _8454, _9330.y);
                                    highp float _9393 = _9325.x;
                                    highp float _9402 = mix(mix(float(_8448 <= textureLod(shadow_map, _9340, 0.0).x), float(_8448 <= textureLod(shadow_map, _9340 + _9229, 0.0).x), _9393), mix(float(_8448 <= textureLod(shadow_map, _9340 + _9237, 0.0).x), float(_8448 <= textureLod(shadow_map, _9340 + _9220, 0.0).x), _9393), _9325.y);
                                    float mp_copy_9402 = _9402;
                                    highp vec2 _9436 = clamp(_8150 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _19261), _9177, _9181);
                                    highp vec2 _9447 = (vec2(_9436.x, 1.0 - _9436.y) / _9177) - vec2(0.5);
                                    highp vec2 _9449 = floor(_9447);
                                    highp vec2 _9452 = _9447 - _9449;
                                    highp vec2 _9457 = (_9449 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9467 = vec2((_9205 + _9457.x) * _8454, _9457.y);
                                    highp float _9520 = _9452.x;
                                    highp float _9529 = mix(mix(float(_8448 <= textureLod(shadow_map, _9467, 0.0).x), float(_8448 <= textureLod(shadow_map, _9467 + _9229, 0.0).x), _9520), mix(float(_8448 <= textureLod(shadow_map, _9467 + _9237, 0.0).x), float(_8448 <= textureLod(shadow_map, _9467 + _9220, 0.0).x), _9520), _9452.y);
                                    float mp_copy_9529 = _9529;
                                    highp vec2 _9563 = clamp(_8150 + (vec2(0.707099974155426025390625) * _19261), _9177, _9181);
                                    highp vec2 _9574 = (vec2(_9563.x, 1.0 - _9563.y) / _9177) - vec2(0.5);
                                    highp vec2 _9576 = floor(_9574);
                                    highp vec2 _9579 = _9574 - _9576;
                                    highp vec2 _9584 = (_9576 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _9594 = vec2((_9205 + _9584.x) * _8454, _9584.y);
                                    highp float _9647 = _9579.x;
                                    highp float _9656 = mix(mix(float(_8448 <= textureLod(shadow_map, _9594, 0.0).x), float(_8448 <= textureLod(shadow_map, _9594 + _9229, 0.0).x), _9647), mix(float(_8448 <= textureLod(shadow_map, _9594 + _9237, 0.0).x), float(_8448 <= textureLod(shadow_map, _9594 + _9220, 0.0).x), _9647), _9579.y);
                                    float mp_copy_9656 = _9656;
                                    _19287 = (((mp_copy_9275 + mp_copy_9402) + mp_copy_9529) + mp_copy_9656) * 0.25;
                                }
                                else
                                {
                                    int _8651 = (_8462 > 0.5) ? 17 : 16;
                                    float _19281 = 0.0;
                                    _19281 = 0.0;
                                    float _8679 = 0.0;
                                    for (int _19263 = 0; _19263 < 17; _19281 = _8679, _19263++)
                                    {
                                        if (_19263 >= _8651)
                                        {
                                            break;
                                        }
                                        vec2 _19264 = vec2(0.0);
                                        do
                                        {
                                            if (_19263 == 0)
                                            {
                                                _19264 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_19263 == 1)
                                            {
                                                _19264 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_19263 == 2)
                                            {
                                                _19264 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_19263 == 3)
                                            {
                                                _19264 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_19263 == 4)
                                            {
                                                _19264 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_19263 == 5)
                                            {
                                                _19264 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_19263 == 6)
                                            {
                                                _19264 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_19263 == 7)
                                            {
                                                _19264 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_19263 == 8)
                                            {
                                                _19264 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_19263 == 9)
                                            {
                                                _19264 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_19263 == 10)
                                            {
                                                _19264 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_19263 == 11)
                                            {
                                                _19264 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_19263 == 12)
                                            {
                                                _19264 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_19263 == 13)
                                            {
                                                _19264 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_19263 == 14)
                                            {
                                                _19264 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_19263 == 15)
                                            {
                                                _19264 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _19264 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _19266 = vec2(0.0);
                                        do
                                        {
                                            if (_19263 < 3)
                                            {
                                                _19266 = vec2(float(_19263) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_19263 < 6)
                                            {
                                                _19266 = vec2((float(_19263 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_19263 < 11)
                                            {
                                                _19266 = vec2((float(_19263 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_19263 < 14)
                                            {
                                                _19266 = vec2((float(_19263 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _19266 = vec2(float(_19263 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _8668 = mix(_19264, _19266, vec2(_8462));
                                        float _9796 = _8668.x;
                                        float _9800 = _8668.y;
                                        highp vec2 _9826 = clamp(_8150 + (vec2((_9796 * _19254) - (_9800 * _19258), (_9796 * _19258) + (_9800 * _19254)) * _19261), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _9835 = _9826.y;
                                        highp vec2 _9836 = vec2((float(_18247) + _9826.x) * _8454, _9835);
                                        _9836.y = 1.0 - _9835;
                                        highp float _9848 = float(_8448 <= textureLod(shadow_map, _9836, 0.0).x);
                                        float mp_copy_9848 = _9848;
                                        _8679 = _19281 + mp_copy_9848;
                                    }
                                    _19287 = _19281 / float(_8651);
                                }
                                _19285 = _19287;
                            }
                            bool _8693 = _18247 == (_8060 - 1);
                            bool _8699 = false;
                            if (_8693)
                            {
                                _8699 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _8699 = _8693;
                            }
                            float _19288 = 0.0;
                            if (_8699)
                            {
                                highp vec2 _8706 = vec2(frag_info.shadow_fade / _19221);
                                highp vec2 _8714 = smoothstep(vec2(0.0), _8706, _8150) * smoothstep(vec2(0.0), _8706, _8307);
                                _19288 = mix(1.0, _19285, _8714.x * _8714.y);
                            }
                            else
                            {
                                _19288 = _19285;
                            }
                            _19351 = _18251 + _8210;
                            _19348 = _18249 + (_8210 * _19288);
                        }
                        else
                        {
                            _19351 = _18251;
                            _19348 = _18249;
                        }
                        _19350 = _19351;
                        _19347 = _19348;
                    }
                    else
                    {
                        _19350 = _18251;
                        _19347 = _18249;
                    }
                    _19349 = _19350;
                    _19346 = _19347;
                }
                else
                {
                    _19349 = _18251;
                    _19346 = _18249;
                }
            }
            _18250 = _18251;
            _18248 = _18249;
        }
        else
        {
            _18250 = 0.0;
            _18248 = 0.0;
        }
        _18254 = mix(_18248 + (1.0 - _18250), 1.0, _18246);
    }
    else
    {
        _18254 = 1.0;
    }
    bool _7194 = frag_info.ssao_lighting.w > 0.5;
    bool _7200 = false;
    if (_7194)
    {
        _7200 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _7200 = _7194;
    }
    float _18266 = 0.0;
    if (_7200)
    {
        _18266 = min(_18254, _18262.y);
    }
    else
    {
        _18266 = _18254;
    }
    vec3 mp_copy_18267 = vec3(0.0);
    float _7209 = _7172 * _18266;
    bool _9855 = view_info.camera_forward.w > 0.5;
    highp vec3 _18267 = vec3(0.0);
    if (_9855)
    {
        _18267 = -view_info.camera_forward.xyz;
    }
    else
    {
        _18267 = normalize(v_viewvector);
    }
    highp float _9899 = 0.0;
    mp_copy_18267 = _18267;
    vec3 _7218 = mix(frag_info.dielectric_f0.xyz, _7070, vec3(_6168));
    float _7221 = dot(_18189, _18267);
    float _7222 = max(_7221, 0.0);
    float _7226 = max(dot(_6034, _18267), 0.0);
    vec3 _7230 = reflect(-mp_copy_18267, _18189);
    highp vec2 _18268 = vec2(0.0);
    do
    {
        _9899 = frag_info.punctual_dims.x;
        if (_9899 < 0.5)
        {
            _18268 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _9911 = v_position - frag_info.camera_position.xyz;
            highp float _9926 = dot(_9911, frag_info.camera_forward.xyz);
            highp float _9932 = max(_9926, 9.9999997473787516355514526367188e-05);
            highp vec2 _10035 = (vec3(dot(_9911, frag_info.camera_right.xyz), dot(_9911, frag_info.camera_up.xyz), _9932).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_9932, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _10050 = float(int(((((clamp(floor((log2(max(_9926 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_10035.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_10035.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _18268 = vec2(textureLod(punctual_index, vec2((mod(_10050, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_10050 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _18268 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _7235 = int(_18268.x + 0.5);
    mediump int _7239 = int(_18268.y + 0.5);
    highp vec3 _18939 = vec3(0.0);
    _18939 = vec3(0.0);
    highp vec3 _19756 = vec3(0.0);
    for (int _18269 = 0; _18269 < _7239; _18939 = _19756, _18269++)
    {
        highp float _10083 = float(_7235 + _18269);
        highp float _10114 = (float(int(textureLod(punctual_index, vec2((mod(_10083, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_10083 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _9899;
        highp vec2 _10115 = vec2(0.0625, _10114);
        highp vec4 _10118 = textureLod(punctual_lights, _10115, 0.0);
        highp vec4 _10135 = textureLod(punctual_lights, vec2(0.1875, _10114), 0.0);
        highp float _7257 = _10118.w;
        highp vec3 _7259 = _10135.xyz;
        highp vec3 _19757 = vec3(0.0);
        if (_7257 > 2.5)
        {
            highp vec4 _10152 = textureLod(punctual_lights, vec2(0.3125, _10114), 0.0);
            highp vec4 _10169 = textureLod(punctual_lights, vec2(0.4375, _10114), 0.0);
            highp vec3 _7273 = _10152.xyz * (_10152.w * 0.5);
            highp vec3 _7279 = _10169.xyz * (_10169.w * 0.5);
            highp vec3 _7281 = _10118.xyz;
            highp vec3 _7283 = _7281 - _7273;
            highp vec3 _7285 = _7283 - _7279;
            highp vec3 _7289 = _7281 + _7273;
            highp vec3 _7291 = _7289 - _7279;
            highp vec3 _7303 = _7283 + _7279;
            highp vec3 _7307 = _7281 - v_position;
            highp float _7313 = _10135.w;
            highp float _7317 = (dot(_7307, _7307) * _7313) * _7313;
            highp float _7322 = clamp(1.0 - (_7317 * _7317), 0.0, 1.0);
            float mp_copy_7322 = _7322;
            vec2 _10176 = (clamp(vec2(_18237, sqrt(1.0 - _7222)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _10178 = _10176.x;
            float _10183 = _10176.y;
            vec4 _7346 = textureLod(brdf_lut, vec2((_10178 + 1.0) * 0.3333333432674407958984375, _10183), 0.0);
            vec4 _7350 = textureLod(brdf_lut, vec2((_10178 + 2.0) * 0.3333333432674407958984375, _10183), 0.0);
            vec3 _10226 = normalize(mp_copy_18267 - (_18189 * _7221));
            mat3 _10248 = transpose(mat3(_10226, -cross(_18189, _10226), _18189));
            mat3 _10249 = mat3(vec3(_7346.x, 0.0, _7346.y), vec3(0.0, 1.0, 0.0), vec3(_7346.z, 0.0, _7346.w)) * _10248;
            highp vec3 _10253 = _7285 - v_position;
            highp vec3 _10255 = normalize(_10249 * _10253);
            vec3 mp_copy_10255 = _10255;
            highp vec3 _10259 = _7291 - v_position;
            highp vec3 _10261 = normalize(_10249 * _10259);
            vec3 mp_copy_10261 = _10261;
            highp vec3 _10265 = (_7289 + _7279) - v_position;
            highp vec3 _10267 = normalize(_10249 * _10265);
            vec3 mp_copy_10267 = _10267;
            highp vec3 _10271 = _7303 - v_position;
            highp vec3 _10273 = normalize(_10249 * _10271);
            vec3 mp_copy_10273 = _10273;
            float _10302 = dot(_10255, _10261);
            float _10304 = abs(_10302);
            float _10318 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10304)) * _10304)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10304) * _10304));
            float _19157 = 0.0;
            if (_10302 > 0.0)
            {
                _19157 = _10318;
            }
            else
            {
                _19157 = (0.5 * inversesqrt(max(1.0 - (_10302 * _10302), 1.0000000116860974230803549289703e-07))) - _10318;
            }
            float _10351 = dot(_10261, _10267);
            float _10353 = abs(_10351);
            float _10367 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10353)) * _10353)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10353) * _10353));
            float _19158 = 0.0;
            if (_10351 > 0.0)
            {
                _19158 = _10367;
            }
            else
            {
                _19158 = (0.5 * inversesqrt(max(1.0 - (_10351 * _10351), 1.0000000116860974230803549289703e-07))) - _10367;
            }
            float _10400 = dot(_10267, _10273);
            float _10402 = abs(_10400);
            float _10416 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10402)) * _10402)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10402) * _10402));
            float _19159 = 0.0;
            if (_10400 > 0.0)
            {
                _19159 = _10416;
            }
            else
            {
                _19159 = (0.5 * inversesqrt(max(1.0 - (_10400 * _10400), 1.0000000116860974230803549289703e-07))) - _10416;
            }
            float _10449 = dot(_10273, _10255);
            float _10451 = abs(_10449);
            float _10465 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10451)) * _10451)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10451) * _10451));
            float _19160 = 0.0;
            if (_10449 > 0.0)
            {
                _19160 = _10465;
            }
            else
            {
                _19160 = (0.5 * inversesqrt(max(1.0 - (_10449 * _10449), 1.0000000116860974230803549289703e-07))) - _10465;
            }
            vec3 _10288 = (((cross(mp_copy_10255, mp_copy_10261) * _19157) + (cross(mp_copy_10261, mp_copy_10267) * _19158)) + (cross(mp_copy_10267, mp_copy_10273) * _19159)) + (cross(mp_copy_10273, mp_copy_10255) * _19160);
            float _10491 = length(_10288);
            mat3 _10551 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _10248;
            highp vec3 _10557 = normalize(_10551 * _10253);
            vec3 mp_copy_10557 = _10557;
            highp vec3 _10563 = normalize(_10551 * _10259);
            vec3 mp_copy_10563 = _10563;
            highp vec3 _10569 = normalize(_10551 * _10265);
            vec3 mp_copy_10569 = _10569;
            highp vec3 _10575 = normalize(_10551 * _10271);
            vec3 mp_copy_10575 = _10575;
            float _10604 = dot(_10557, _10563);
            float _10606 = abs(_10604);
            float _10620 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10606)) * _10606)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10606) * _10606));
            float _19161 = 0.0;
            if (_10604 > 0.0)
            {
                _19161 = _10620;
            }
            else
            {
                _19161 = (0.5 * inversesqrt(max(1.0 - (_10604 * _10604), 1.0000000116860974230803549289703e-07))) - _10620;
            }
            float _10653 = dot(_10563, _10569);
            float _10655 = abs(_10653);
            float _10669 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10655)) * _10655)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10655) * _10655));
            float _19162 = 0.0;
            if (_10653 > 0.0)
            {
                _19162 = _10669;
            }
            else
            {
                _19162 = (0.5 * inversesqrt(max(1.0 - (_10653 * _10653), 1.0000000116860974230803549289703e-07))) - _10669;
            }
            float _10702 = dot(_10569, _10575);
            float _10704 = abs(_10702);
            float _10718 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10704)) * _10704)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10704) * _10704));
            float _19163 = 0.0;
            if (_10702 > 0.0)
            {
                _19163 = _10718;
            }
            else
            {
                _19163 = (0.5 * inversesqrt(max(1.0 - (_10702 * _10702), 1.0000000116860974230803549289703e-07))) - _10718;
            }
            float _10751 = dot(_10575, _10557);
            float _10753 = abs(_10751);
            float _10767 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _10753)) * _10753)) / (3.41759395599365234375 + ((4.1616725921630859375 + _10753) * _10753));
            float _19164 = 0.0;
            if (_10751 > 0.0)
            {
                _19164 = _10767;
            }
            else
            {
                _19164 = (0.5 * inversesqrt(max(1.0 - (_10751 * _10751), 1.0000000116860974230803549289703e-07))) - _10767;
            }
            vec3 _10590 = (((cross(mp_copy_10557, mp_copy_10563) * _19161) + (cross(mp_copy_10563, mp_copy_10569) * _19162)) + (cross(mp_copy_10569, mp_copy_10575) * _19163)) + (cross(mp_copy_10575, mp_copy_10557) * _19164);
            float _10793 = length(_10590);
            _19757 = _18939 + (((_7259 * (mp_copy_7322 * mp_copy_7322)) * step(0.0, dot(cross(_7291 - _7285, _7303 - _7285), v_position - _7285))) * (((((_7218 * _7350.x) + ((vec3(1.0) - _7218) * _7350.y)) * max(((_10491 * _10491) + _10288.z) / (_10491 + 1.0), 0.0)) * 1.0) + ((_7070 * (1.0 - _6168)) * max(((_10793 * _10793) + _10590.z) / (_10793 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_19101 = 0.0;
            vec3 _19074 = vec3(0.0);
            highp vec3 _19097 = vec3(0.0);
            float _19101 = 0.0;
            if (_7257 < 0.5)
            {
                _19101 = _18237;
                _19097 = _7259;
                _19074 = -normalize(textureLod(punctual_lights, vec2(0.3125, _10114), 0.0).xyz);
            }
            else
            {
                highp vec3 _7437 = _10118.xyz - v_position;
                highp float _7440 = dot(_7437, _7437);
                highp float _7444 = inversesqrt(max(_7440, 9.9999999392252902907785028219223e-09));
                highp vec3 _7445 = _7437 * _7444;
                vec3 mp_copy_7445 = _7445;
                highp float _7447 = _10135.w;
                highp float _7452 = (_7440 * _7447) * _7447;
                highp float _7457 = clamp(1.0 - (_7452 * _7452), 0.0, 1.0);
                float mp_copy_7457 = _7457;
                if (_7457 <= 0.0)
                {
                    _19756 = _18939;
                    continue;
                }
                highp vec4 _10837 = textureLod(punctual_lights, vec2(0.4375, _10114), 0.0);
                highp float _7465 = _10837.w;
                float _19106 = 0.0;
                if (_7465 > 0.0)
                {
                    highp float _7492 = (_18237 * _18237) + ((_7465 * 0.5) * _7444);
                    float mp_copy_7492 = _7492;
                    _19106 = sqrt(min(mp_copy_7492, 1.0));
                }
                else
                {
                    _19106 = _18237;
                }
                highp vec3 _7499 = _7259 * ((mp_copy_7457 * mp_copy_7457) / max(pow(max(_7440, _7465 * _7465), _10837.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _19098 = vec3(0.0);
                if (_7257 > 1.5)
                {
                    highp vec4 _10854 = textureLod(punctual_lights, vec2(0.3125, _10114), 0.0);
                    highp float _7518 = clamp((dot(normalize(_10854.xyz), -mp_copy_7445) * _10854.w) + _10837.x, 0.0, 1.0);
                    float mp_copy_7518 = _7518;
                    highp vec3 _7523 = _7499 * (mp_copy_7518 * mp_copy_7518);
                    if (_7518 <= 0.0)
                    {
                        _19756 = _18939;
                        continue;
                    }
                    bool _7529 = _7518 > 0.0;
                    bool _7535 = false;
                    if (_7529)
                    {
                        _7535 = _10837.y > (-0.5);
                    }
                    else
                    {
                        _7535 = _7529;
                    }
                    bool _7541 = false;
                    if (_7535)
                    {
                        _7541 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7541 = _7535;
                    }
                    highp vec3 _19099 = vec3(0.0);
                    if (_7541)
                    {
                        float _19065 = 0.0;
                        do
                        {
                            highp vec4 _10966 = mat4(textureLod(punctual_lights, vec2(0.5625, _10114), 0.0), textureLod(punctual_lights, vec2(0.6875, _10114), 0.0), textureLod(punctual_lights, vec2(0.8125, _10114), 0.0), textureLod(punctual_lights, vec2(0.9375, _10114), 0.0)) * vec4(v_position + (_6034 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _10968 = _10966.w;
                            if (_10968 <= 0.0)
                            {
                                _19065 = 1.0;
                                break;
                            }
                            highp vec3 _10977 = _10966.xyz / vec3(_10968);
                            highp vec2 _10982 = (_10977.xy * 0.5) + vec2(0.5);
                            highp float _10984 = _10982.x;
                            bool _10985 = _10984 < 0.0;
                            bool _10992 = false;
                            if (!_10985)
                            {
                                _10992 = _10984 > 1.0;
                            }
                            else
                            {
                                _10992 = _10985;
                            }
                            bool _10999 = false;
                            if (!_10992)
                            {
                                _10999 = _10982.y < 0.0;
                            }
                            else
                            {
                                _10999 = _10992;
                            }
                            bool _11006 = false;
                            if (!_10999)
                            {
                                _11006 = _10982.y > 1.0;
                            }
                            else
                            {
                                _11006 = _10999;
                            }
                            bool _11013 = false;
                            if (!_11006)
                            {
                                _11013 = _10977.z < 0.0;
                            }
                            else
                            {
                                _11013 = _11006;
                            }
                            bool _11020 = false;
                            if (!_11013)
                            {
                                _11020 = _10977.z > 1.0;
                            }
                            else
                            {
                                _11020 = _11013;
                            }
                            if (_11020)
                            {
                                _19065 = 1.0;
                                break;
                            }
                            highp float _11027 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _11032 = frag_info.shadow_cascade_count + float(int(_10837.y + 0.5));
                            highp float _11037 = _10977.z - frag_info.spot_shadow_params.y;
                            highp float _11048 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float mp_copy_11048 = _11048;
                            highp vec2 _11055 = vec2(cos(mp_copy_11048), sin(mp_copy_11048)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                            highp float _11057 = _11055.x;
                            highp float _11059 = _11055.y;
                            highp vec2 _11067 = vec2(_11057 - _11059, _11057 + _11059) * 0.707106769084930419921875;
                            highp float _11260 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_10984, 0.0, 1.0)) / _11027, 1.0 - clamp(_10982.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11260 = _11260;
                            highp vec2 _11075 = _10982 + _11055;
                            highp float _11282 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11075.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11075.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11282 = _11282;
                            highp vec2 _11083 = _10982 - _11055;
                            highp float _11304 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11083.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11083.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11304 = _11304;
                            highp vec2 _11096 = _10982 + vec2(-_11059, _11057);
                            highp float _11326 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11096.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11096.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11326 = _11326;
                            highp vec2 _11109 = _10982 + vec2(_11059, -_11057);
                            highp float _11348 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11109.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11109.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11348 = _11348;
                            float _11114 = (((mp_copy_11260 + mp_copy_11282) + mp_copy_11304) + mp_copy_11326) + mp_copy_11348;
                            if ((_11114 < 0.5) || (_11114 > 4.5))
                            {
                                _19065 = _11114 * 0.20000000298023223876953125;
                                break;
                            }
                            highp vec2 _11126 = _10982 + _11067;
                            highp float _11370 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11126.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11126.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11370 = _11370;
                            highp vec2 _11133 = _10982 - _11067;
                            highp float _11392 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11133.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11133.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11392 = _11392;
                            highp float _11141 = _11067.y;
                            highp float _11144 = _11067.x;
                            highp vec2 _11146 = _10982 + vec2(-_11141, _11144);
                            highp float _11414 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11146.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11146.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11414 = _11414;
                            highp vec2 _11159 = _10982 + vec2(_11141, -_11144);
                            highp float _11436 = float(_11037 <= textureLod(shadow_map, vec2((_11032 + clamp(_11159.x, 0.0, 1.0)) / _11027, 1.0 - clamp(_11159.y, 0.0, 1.0)), 0.0).x);
                            float mp_copy_11436 = _11436;
                            _19065 = (_11114 + (((mp_copy_11370 + mp_copy_11392) + mp_copy_11414) + mp_copy_11436)) * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _19099 = _7523 * _19065;
                    }
                    else
                    {
                        _19099 = _7523;
                    }
                    _19098 = _19099;
                }
                else
                {
                    bool _7557 = _7257 > 0.5;
                    bool _7563 = false;
                    if (_7557)
                    {
                        _7563 = _10837.y > (-0.5);
                    }
                    else
                    {
                        _7563 = _7557;
                    }
                    bool _7569 = false;
                    if (_7563)
                    {
                        _7569 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7569 = _7563;
                    }
                    highp vec3 _19100 = vec3(0.0);
                    if (_7569)
                    {
                        float _19052 = 0.0;
                        do
                        {
                            highp vec4 _11749 = textureLod(punctual_lights, vec2(0.5625, _10114), 0.0);
                            highp vec4 _11766 = textureLod(punctual_lights, vec2(0.6875, _10114), 0.0);
                            highp vec3 _11508 = (v_position + (_6034 * _11749.z)) - textureLod(punctual_lights, _10115, 0.0).xyz;
                            highp vec3 _11510 = abs(_11508);
                            highp float _11512 = _11510.x;
                            highp float _11514 = _11510.y;
                            bool _11515 = _11512 >= _11514;
                            bool _11523 = false;
                            if (_11515)
                            {
                                _11523 = _11512 >= _11510.z;
                            }
                            else
                            {
                                _11523 = _11515;
                            }
                            highp vec3 _19042 = vec3(0.0);
                            float _19044 = 0.0;
                            if (_11523)
                            {
                                highp float _11526 = _11508.x;
                                bool _11527 = _11526 >= 0.0;
                                highp vec3 _19041 = vec3(0.0);
                                if (_11527)
                                {
                                    _19041 = vec3(-_11508.z, _11508.y, _11526);
                                }
                                else
                                {
                                    _19041 = vec3(_11508.zy, -_11526);
                                }
                                _19044 = _11527 ? 0.0 : 1.0;
                                _19042 = _19041;
                            }
                            else
                            {
                                highp vec3 _19043 = vec3(0.0);
                                float _19046 = 0.0;
                                if (_11514 >= _11510.z)
                                {
                                    highp float _11560 = _11508.y;
                                    bool _11561 = _11560 >= 0.0;
                                    highp vec3 _19040 = vec3(0.0);
                                    if (_11561)
                                    {
                                        _19040 = vec3(-_11508.x, _11508.z, _11560);
                                    }
                                    else
                                    {
                                        _19040 = vec3(_11508.xz, -_11560);
                                    }
                                    _19046 = _11561 ? 2.0 : 3.0;
                                    _19043 = _19040;
                                }
                                else
                                {
                                    highp float _11588 = _11508.z;
                                    bool _11589 = _11588 >= 0.0;
                                    highp vec3 _19039 = vec3(0.0);
                                    if (_11589)
                                    {
                                        _19039 = _11508;
                                    }
                                    else
                                    {
                                        _19039 = vec3(-_11508.x, _11508.y, -_11588);
                                    }
                                    _19046 = _11589 ? 4.0 : 5.0;
                                    _19043 = _19039;
                                }
                                _19044 = _19046;
                                _19042 = _19043;
                            }
                            if (_19042.z <= 0.0)
                            {
                                _19052 = 1.0;
                                break;
                            }
                            highp vec2 _11629 = ((_19042.xy / vec2(_19042.z)) * 0.5) + vec2(0.5);
                            highp float _11640 = (_11749.x - (_11749.y / _19042.z)) - _11766.x;
                            if ((_11640 < 0.0) || (_11640 > 1.0))
                            {
                                _19052 = 1.0;
                                break;
                            }
                            highp float hp_copy_19049 = 0.0;
                            highp float _11652 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _11658 = _19044 >= 4.0;
                            highp float _11660 = (frag_info.shadow_cascade_count + _10837.y) + float(_11658);
                            float _19049 = 0.0;
                            if (_11658)
                            {
                                _19049 = _19044 - 4.0;
                            }
                            else
                            {
                                _19049 = _19044;
                            }
                            hp_copy_19049 = _19049;
                            highp float _11677 = _11766.y * 0.5;
                            highp float _11680 = _11749.w * 0.0040000001899898052215576171875;
                            highp vec2 _11791 = vec2(_11677);
                            highp vec2 _11794 = vec2(1.0 - _11677);
                            highp vec2 _11800 = vec2(mod(hp_copy_19049, 2.0), 1.0 - floor(hp_copy_19049 * 0.5)) * 0.5;
                            highp vec2 _11803 = _11800 + (clamp(_11629, _11791, _11794) * 0.5);
                            highp float _11696 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _19051 = 0.0;
                            _19051 = float(_11640 <= textureLod(shadow_map, vec2((_11660 + _11803.x) / _11652, 1.0 - _11803.y), 0.0).x);
                            for (int _19050 = 0; _19050 < 8; )
                            {
                                highp float _11706 = _11696 + (float(_19050) * 0.785398185253143310546875);
                                float mp_copy_11706 = _11706;
                                highp vec2 _11840 = _11800 + (clamp(_11629 + (vec2(cos(mp_copy_11706), sin(mp_copy_11706)) * _11680), _11791, _11794) * 0.5);
                                highp float _11857 = float(_11640 <= textureLod(shadow_map, vec2((_11660 + _11840.x) / _11652, 1.0 - _11840.y), 0.0).x);
                                float mp_copy_11857 = _11857;
                                _19051 += mp_copy_11857;
                                _19050++;
                                continue;
                            }
                            _19052 = _19051 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _19100 = _7499 * _19052;
                    }
                    else
                    {
                        _19100 = _7499;
                    }
                    _19098 = _19100;
                }
                _19101 = _19106;
                _19097 = _19098;
                _19074 = _7445;
            }
            hp_copy_19101 = _19101;
            highp vec3 _19128 = vec3(0.0);
            highp vec3 _19129 = vec3(0.0);
            do
            {
                float _11923 = max(dot(_18189, _19074), 0.0);
                highp float hp_copy_11923 = _11923;
                if (_11923 <= 0.0)
                {
                    _19129 = vec3(0.0);
                    _19128 = vec3(0.0);
                    break;
                }
                float _11929 = max(_7222, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_11929 = _11929;
                vec3 _11932 = _19074 + mp_copy_18267;
                float _11935 = dot(_11932, _11932);
                vec3 _19126 = vec3(0.0);
                vec3 _19127 = vec3(0.0);
                if (_11935 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _11943 = _11932 * inversesqrt(_11935);
                    float _19125 = 0.0;
                    do
                    {
                        float _12000 = dot(_18189, _11943);
                        if (_12000 <= 0.0)
                        {
                            _19125 = 0.0;
                            break;
                        }
                        float _12007 = _19101 * _19101;
                        vec3 _12010 = cross(_18189, _11943);
                        float _12013 = _12000 * _12007;
                        float _12022 = _12007 / (dot(_12010, _12010) + (_12013 * _12013));
                        _19125 = min((_12022 * _12022) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _12060 = _7218 + ((vec3(1.0) - _7218) * pow(clamp(1.0 - max(dot(_11943, _18267), 0.0), 0.0, 1.0), 5.0));
                    _19127 = (_12060 * min(_19125 * (0.5 / max(mix((2.0 * hp_copy_11923) * _11929, hp_copy_11923 + hp_copy_11929, hp_copy_19101 * hp_copy_19101), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _19126 = _12060;
                }
                else
                {
                    _19127 = vec3(0.0);
                    _19126 = _7218;
                }
                _19129 = (_19127 * _19097) * _11923;
                _19128 = (((((vec3(1.0) - _19126) * (1.0 - _6168)) * _7070) * 0.3183098733425140380859375) * _19097) * _11923;
                break;
            } while(false);
            _19757 = _18939 + (_19128 + _19129);
        }
        _19756 = _19757;
    }
    mat3 _7617 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7620 = _18280 > 0.5;
    bvec3 _7623 = bvec3(_7620);
    highp vec3 _7624 = vec3(_7623.x ? _18295.x : _18189.x, _7623.y ? _18295.y : _18189.y, _7623.z ? _18295.z : _18189.z);
    vec3 mp_copy_7624 = _7624;
    vec3 _7625 = _7617 * mp_copy_7624;
    vec3 _18300 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _12107 = _7230 + (((step(vec3(0.0), _7230) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_12107 = _12107;
        highp vec3 _12109 = vec3(1.0) / hp_copy_12107;
        highp vec3 _12126 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _12109, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _12109);
        _18300 = normalize((v_position + (_7230 * max(min(min(_12126.x, _12126.y), _12126.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _18300 = _7230;
    }
    bool _12354 = false;
    vec3 _7630 = _7617 * _18300;
    float _12173 = _7625.y;
    float _12174 = 0.48860299587249755859375 * _12173;
    float _12180 = _7625.z;
    float _12181 = 0.48860299587249755859375 * _12180;
    float _12187 = _7625.x;
    float _12188 = 0.48860299587249755859375 * _12187;
    float _12195 = 1.09254801273345947265625 * _12187;
    float _12198 = _12195 * _12173;
    float _12208 = (1.09254801273345947265625 * _12173) * _12180;
    float _12220 = 0.3153919875621795654296875 * (((3.0 * _12180) * _12180) - 1.0);
    float _12230 = _12195 * _12180;
    float _12246 = 0.546274006366729736328125 * ((_12187 * _12187) - (_12173 * _12173));
    vec3 _7633 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _12174)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _12181)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _12188)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _12198)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _12208)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _12220)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _12230)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _12246), vec3(0.0));
    vec3 _18301 = vec3(0.0);
    do
    {
        _12354 = radiance_layout_info.mip_layout > 0.5;
        if (_12354)
        {
            vec2 _12433 = vec2(atan(_7630.z, _7630.x), asin(clamp(_7630.y, -1.0, 1.0)));
            highp vec2 hp_copy_12433 = _12433;
            _18301 = textureLod(prefiltered_radiance, (hp_copy_12433 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_18237, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _12452 = vec2(atan(_7630.z, _7630.x), asin(clamp(_7630.y, -1.0, 1.0)));
        highp vec2 hp_copy_12452 = _12452;
        highp vec2 _12457 = (hp_copy_12452 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _12364 = clamp(_12457.y, 0.00390625, 0.99609375);
        float _12368 = clamp(_18237, 0.0, 1.0) * 7.0;
        float _12370 = floor(_12368);
        highp float _12389 = _12457.x;
        _18301 = mix(textureLod(prefiltered_radiance, vec2(_12389, (_12370 + _12364) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_12389, (min(_12370 + 1.0, 7.0) + _12364) * 0.125), 0.0).xyz, vec3(_12368 - _12370));
        break;
    } while(false);
    bool _7640 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _18306 = vec3(0.0);
    highp vec3 _18307 = vec3(0.0);
    if (_7640)
    {
        vec3 _18302 = vec3(0.0);
        do
        {
            if (_12354)
            {
                vec2 _12745 = vec2(atan(_7630.z, _7630.x), asin(clamp(_7630.y, -1.0, 1.0)));
                highp vec2 hp_copy_12745 = _12745;
                _18302 = textureLod(prefiltered_radiance_b, (hp_copy_12745 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_18237, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _12764 = vec2(atan(_7630.z, _7630.x), asin(clamp(_7630.y, -1.0, 1.0)));
            highp vec2 hp_copy_12764 = _12764;
            highp vec2 _12769 = (hp_copy_12764 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _12676 = clamp(_12769.y, 0.00390625, 0.99609375);
            float _12680 = clamp(_18237, 0.0, 1.0) * 7.0;
            float _12682 = floor(_12680);
            highp float _12701 = _12769.x;
            _18302 = mix(textureLod(prefiltered_radiance_b, vec2(_12701, (_12682 + _12676) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_12701, (min(_12682 + 1.0, 7.0) + _12676) * 0.125), 0.0).xyz, vec3(_12680 - _12682));
            break;
        } while(false);
        highp vec3 _7651 = vec3(frag_info.radiance_blend.x);
        _18307 = mix(_18301, _18302, _7651);
        _18306 = mix(_7633, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _12174)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _12181)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _12188)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _12198)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _12208)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _12220)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _12230)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _12246), vec3(0.0)), _7651);
    }
    else
    {
        _18307 = _18301;
        _18306 = _7633;
    }
    highp float _12782 = 0.0;
    highp vec3 _7662 = _18306 * frag_info.environment_intensity;
    float _18308 = 0.0;
    do
    {
        _12782 = frag_info.gi_grid.w;
        if (_12782 <= 0.0)
        {
            _18308 = 0.0;
            break;
        }
        highp vec3 _12795 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _12803 = min(_12795, (frag_info.gi_counts.xyz - vec3(1.0)) - _12795);
        _18308 = clamp(min(_12803.x, min(_12803.y, _12803.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _18499 = vec3(0.0);
    if (_18308 > 0.0)
    {
        highp vec3 _12895 = v_position + (((_18189 * 0.20000000298023223876953125) + (mp_copy_18267 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _12898 = _12895 / frag_info.gi_grid.xyz;
        highp vec3 _12900 = floor(_12898);
        highp vec3 _12906 = clamp(_12898 - _12900, vec3(0.0), vec3(1.0));
        vec3 mp_copy_12906 = _12906;
        highp vec3 _13028 = _12900 - frag_info.gi_anchor.xyz;
        bool _13031 = any(lessThan(_13028, vec3(0.0)));
        bool _13039 = false;
        if (!_13031)
        {
            _13039 = any(greaterThanEqual(_13028, frag_info.gi_counts.xyz));
        }
        else
        {
            _13039 = _13031;
        }
        vec3 mp_copy_18309 = vec3(0.0);
        highp float _13040 = _13039 ? 0.0 : 1.0;
        float mp_copy_13040 = _13040;
        vec3 _13042 = vec3(1.0) - mp_copy_12906;
        vec3 _13046 = max(_13042, vec3(0.001000000047497451305389404296875));
        highp vec3 _13062 = (_12900 * frag_info.gi_grid.xyz) - _12895;
        highp float _13064 = length(_13062);
        highp vec3 _18309 = vec3(0.0);
        if (_13064 > 9.9999997473787516355514526367188e-06)
        {
            _18309 = _13062 / vec3(_13064);
        }
        else
        {
            _18309 = _18189;
        }
        mp_copy_18309 = _18309;
        float _13082 = pow((dot(_18309, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13207 = _12900 - (frag_info.gi_counts.xyz * floor(_12900 / frag_info.gi_counts.xyz));
        highp float _13223 = _13207.x + (frag_info.gi_counts.x * (_13207.y + (frag_info.gi_counts.y * _13207.z)));
        bool _13093 = frag_info.gi_visibility.x > 0.0;
        float _18314 = 0.0;
        if (_13093)
        {
            highp float _13231 = floor(_13223 / frag_info.gi_counts.w);
            highp vec2 _13245 = vec2((_13223 - (_13231 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13231 * 16.0));
            vec3 _13105 = -mp_copy_18309;
            vec3 _13293 = _13105 / vec3((abs(_13105.x) + abs(_13105.y)) + abs(_13105.z));
            vec2 _18310 = vec2(0.0);
            if (_13293.z >= 0.0)
            {
                _18310 = _13293.xy;
            }
            else
            {
                _18310 = (vec2(1.0) - abs(_13293.yx)) * vec2((_13293.x >= 0.0) ? 1.0 : (-1.0), (_13293.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13109 = texture(irradiance_field, clamp((_13245 + vec2(1.0)) + (clamp((_18310 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13245 + vec2(0.5), _13245 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13114 = _13109.x * frag_info.gi_visibility.z;
            highp float _13126 = abs((_13114 * _13114) - ((_13109.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13132 = (_13064 - _13114) - frag_info.gi_visibility.y;
            highp float _18311 = 0.0;
            if (_13132 <= 0.0)
            {
                _18311 = 1.0;
            }
            else
            {
                _18311 = _13126 / (_13126 + (_13132 * _13132));
            }
            _18314 = _13082 * mix(1.0, max(0.0500000007450580596923828125, (_18311 * _18311) * _18311), frag_info.gi_visibility.x);
        }
        else
        {
            _18314 = _13082;
        }
        float _13160 = max(9.9999999747524270787835121154785e-07, _18314);
        float _18315 = 0.0;
        if (_13160 < 0.20000000298023223876953125)
        {
            _18315 = _13160 * ((_13160 * _13160) * 25.0);
        }
        else
        {
            _18315 = _13160;
        }
        float _13175 = _18315 * (((_13046.x * _13046.y) * _13046.z) * mp_copy_13040);
        highp float _13334 = floor(_13223 / frag_info.gi_counts.w);
        highp vec2 _13348 = vec2((_13223 - (_13334 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13334 * 8.0));
        vec3 _13396 = _18189 / vec3((abs(_18189.x) + abs(_18189.y)) + abs(_18189.z));
        bool _13399 = _13396.z >= 0.0;
        vec2 _18316 = vec2(0.0);
        if (_13399)
        {
            _18316 = _13396.xy;
        }
        else
        {
            _18316 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13187 = texture(irradiance_field, clamp((_13348 + vec2(1.0)) + (clamp((_18316 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13348 + vec2(0.5), _13348 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13482 = _12900 + vec3(1.0, 0.0, 0.0);
        highp vec3 _13487 = _13482 - frag_info.gi_anchor.xyz;
        bool _13490 = any(lessThan(_13487, vec3(0.0)));
        bool _13498 = false;
        if (!_13490)
        {
            _13498 = any(greaterThanEqual(_13487, frag_info.gi_counts.xyz));
        }
        else
        {
            _13498 = _13490;
        }
        vec3 mp_copy_18318 = vec3(0.0);
        highp float _13499 = _13498 ? 0.0 : 1.0;
        float mp_copy_13499 = _13499;
        vec3 _13505 = max(mix(_13042, mp_copy_12906, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13521 = (_13482 * frag_info.gi_grid.xyz) - _12895;
        highp float _13523 = length(_13521);
        highp vec3 _18318 = vec3(0.0);
        if (_13523 > 9.9999997473787516355514526367188e-06)
        {
            _18318 = _13521 / vec3(_13523);
        }
        else
        {
            _18318 = _18189;
        }
        mp_copy_18318 = _18318;
        float _13541 = pow((dot(_18318, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _13666 = _13482 - (frag_info.gi_counts.xyz * floor(_13482 / frag_info.gi_counts.xyz));
        highp float _13682 = _13666.x + (frag_info.gi_counts.x * (_13666.y + (frag_info.gi_counts.y * _13666.z)));
        float _18323 = 0.0;
        if (_13093)
        {
            highp float _13690 = floor(_13682 / frag_info.gi_counts.w);
            highp vec2 _13704 = vec2((_13682 - (_13690 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13690 * 16.0));
            vec3 _13564 = -mp_copy_18318;
            vec3 _13752 = _13564 / vec3((abs(_13564.x) + abs(_13564.y)) + abs(_13564.z));
            vec2 _18319 = vec2(0.0);
            if (_13752.z >= 0.0)
            {
                _18319 = _13752.xy;
            }
            else
            {
                _18319 = (vec2(1.0) - abs(_13752.yx)) * vec2((_13752.x >= 0.0) ? 1.0 : (-1.0), (_13752.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13568 = texture(irradiance_field, clamp((_13704 + vec2(1.0)) + (clamp((_18319 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13704 + vec2(0.5), _13704 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _13573 = _13568.x * frag_info.gi_visibility.z;
            highp float _13585 = abs((_13573 * _13573) - ((_13568.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _13591 = (_13523 - _13573) - frag_info.gi_visibility.y;
            highp float _18320 = 0.0;
            if (_13591 <= 0.0)
            {
                _18320 = 1.0;
            }
            else
            {
                _18320 = _13585 / (_13585 + (_13591 * _13591));
            }
            _18323 = _13541 * mix(1.0, max(0.0500000007450580596923828125, (_18320 * _18320) * _18320), frag_info.gi_visibility.x);
        }
        else
        {
            _18323 = _13541;
        }
        float _13619 = max(9.9999999747524270787835121154785e-07, _18323);
        float _18324 = 0.0;
        if (_13619 < 0.20000000298023223876953125)
        {
            _18324 = _13619 * ((_13619 * _13619) * 25.0);
        }
        else
        {
            _18324 = _13619;
        }
        float _13634 = _18324 * (((_13505.x * _13505.y) * _13505.z) * mp_copy_13499);
        highp float _13793 = floor(_13682 / frag_info.gi_counts.w);
        highp vec2 _13807 = vec2((_13682 - (_13793 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13793 * 8.0));
        vec2 _18325 = vec2(0.0);
        if (_13399)
        {
            _18325 = _13396.xy;
        }
        else
        {
            _18325 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _13646 = texture(irradiance_field, clamp((_13807 + vec2(1.0)) + (clamp((_18325 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13807 + vec2(0.5), _13807 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _13941 = _12900 + vec3(0.0, 1.0, 0.0);
        highp vec3 _13946 = _13941 - frag_info.gi_anchor.xyz;
        bool _13949 = any(lessThan(_13946, vec3(0.0)));
        bool _13957 = false;
        if (!_13949)
        {
            _13957 = any(greaterThanEqual(_13946, frag_info.gi_counts.xyz));
        }
        else
        {
            _13957 = _13949;
        }
        vec3 mp_copy_18327 = vec3(0.0);
        highp float _13958 = _13957 ? 0.0 : 1.0;
        float mp_copy_13958 = _13958;
        vec3 _13964 = max(mix(_13042, mp_copy_12906, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _13980 = (_13941 * frag_info.gi_grid.xyz) - _12895;
        highp float _13982 = length(_13980);
        highp vec3 _18327 = vec3(0.0);
        if (_13982 > 9.9999997473787516355514526367188e-06)
        {
            _18327 = _13980 / vec3(_13982);
        }
        else
        {
            _18327 = _18189;
        }
        mp_copy_18327 = _18327;
        float _14000 = pow((dot(_18327, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14125 = _13941 - (frag_info.gi_counts.xyz * floor(_13941 / frag_info.gi_counts.xyz));
        highp float _14141 = _14125.x + (frag_info.gi_counts.x * (_14125.y + (frag_info.gi_counts.y * _14125.z)));
        float _18332 = 0.0;
        if (_13093)
        {
            highp float _14149 = floor(_14141 / frag_info.gi_counts.w);
            highp vec2 _14163 = vec2((_14141 - (_14149 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14149 * 16.0));
            vec3 _14023 = -mp_copy_18327;
            vec3 _14211 = _14023 / vec3((abs(_14023.x) + abs(_14023.y)) + abs(_14023.z));
            vec2 _18328 = vec2(0.0);
            if (_14211.z >= 0.0)
            {
                _18328 = _14211.xy;
            }
            else
            {
                _18328 = (vec2(1.0) - abs(_14211.yx)) * vec2((_14211.x >= 0.0) ? 1.0 : (-1.0), (_14211.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14027 = texture(irradiance_field, clamp((_14163 + vec2(1.0)) + (clamp((_18328 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14163 + vec2(0.5), _14163 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14032 = _14027.x * frag_info.gi_visibility.z;
            highp float _14044 = abs((_14032 * _14032) - ((_14027.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14050 = (_13982 - _14032) - frag_info.gi_visibility.y;
            highp float _18329 = 0.0;
            if (_14050 <= 0.0)
            {
                _18329 = 1.0;
            }
            else
            {
                _18329 = _14044 / (_14044 + (_14050 * _14050));
            }
            _18332 = _14000 * mix(1.0, max(0.0500000007450580596923828125, (_18329 * _18329) * _18329), frag_info.gi_visibility.x);
        }
        else
        {
            _18332 = _14000;
        }
        float _14078 = max(9.9999999747524270787835121154785e-07, _18332);
        float _18333 = 0.0;
        if (_14078 < 0.20000000298023223876953125)
        {
            _18333 = _14078 * ((_14078 * _14078) * 25.0);
        }
        else
        {
            _18333 = _14078;
        }
        float _14093 = _18333 * (((_13964.x * _13964.y) * _13964.z) * mp_copy_13958);
        highp float _14252 = floor(_14141 / frag_info.gi_counts.w);
        highp vec2 _14266 = vec2((_14141 - (_14252 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14252 * 8.0));
        vec2 _18334 = vec2(0.0);
        if (_13399)
        {
            _18334 = _13396.xy;
        }
        else
        {
            _18334 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14105 = texture(irradiance_field, clamp((_14266 + vec2(1.0)) + (clamp((_18334 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14266 + vec2(0.5), _14266 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14400 = _12900 + vec3(1.0, 1.0, 0.0);
        highp vec3 _14405 = _14400 - frag_info.gi_anchor.xyz;
        bool _14408 = any(lessThan(_14405, vec3(0.0)));
        bool _14416 = false;
        if (!_14408)
        {
            _14416 = any(greaterThanEqual(_14405, frag_info.gi_counts.xyz));
        }
        else
        {
            _14416 = _14408;
        }
        vec3 mp_copy_18336 = vec3(0.0);
        highp float _14417 = _14416 ? 0.0 : 1.0;
        float mp_copy_14417 = _14417;
        vec3 _14423 = max(mix(_13042, mp_copy_12906, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14439 = (_14400 * frag_info.gi_grid.xyz) - _12895;
        highp float _14441 = length(_14439);
        highp vec3 _18336 = vec3(0.0);
        if (_14441 > 9.9999997473787516355514526367188e-06)
        {
            _18336 = _14439 / vec3(_14441);
        }
        else
        {
            _18336 = _18189;
        }
        mp_copy_18336 = _18336;
        float _14459 = pow((dot(_18336, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _14584 = _14400 - (frag_info.gi_counts.xyz * floor(_14400 / frag_info.gi_counts.xyz));
        highp float _14600 = _14584.x + (frag_info.gi_counts.x * (_14584.y + (frag_info.gi_counts.y * _14584.z)));
        float _18341 = 0.0;
        if (_13093)
        {
            highp float _14608 = floor(_14600 / frag_info.gi_counts.w);
            highp vec2 _14622 = vec2((_14600 - (_14608 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_14608 * 16.0));
            vec3 _14482 = -mp_copy_18336;
            vec3 _14670 = _14482 / vec3((abs(_14482.x) + abs(_14482.y)) + abs(_14482.z));
            vec2 _18337 = vec2(0.0);
            if (_14670.z >= 0.0)
            {
                _18337 = _14670.xy;
            }
            else
            {
                _18337 = (vec2(1.0) - abs(_14670.yx)) * vec2((_14670.x >= 0.0) ? 1.0 : (-1.0), (_14670.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14486 = texture(irradiance_field, clamp((_14622 + vec2(1.0)) + (clamp((_18337 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _14622 + vec2(0.5), _14622 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14491 = _14486.x * frag_info.gi_visibility.z;
            highp float _14503 = abs((_14491 * _14491) - ((_14486.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14509 = (_14441 - _14491) - frag_info.gi_visibility.y;
            highp float _18338 = 0.0;
            if (_14509 <= 0.0)
            {
                _18338 = 1.0;
            }
            else
            {
                _18338 = _14503 / (_14503 + (_14509 * _14509));
            }
            _18341 = _14459 * mix(1.0, max(0.0500000007450580596923828125, (_18338 * _18338) * _18338), frag_info.gi_visibility.x);
        }
        else
        {
            _18341 = _14459;
        }
        float _14537 = max(9.9999999747524270787835121154785e-07, _18341);
        float _18342 = 0.0;
        if (_14537 < 0.20000000298023223876953125)
        {
            _18342 = _14537 * ((_14537 * _14537) * 25.0);
        }
        else
        {
            _18342 = _14537;
        }
        float _14552 = _18342 * (((_14423.x * _14423.y) * _14423.z) * mp_copy_14417);
        highp float _14711 = floor(_14600 / frag_info.gi_counts.w);
        highp vec2 _14725 = vec2((_14600 - (_14711 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_14711 * 8.0));
        vec2 _18343 = vec2(0.0);
        if (_13399)
        {
            _18343 = _13396.xy;
        }
        else
        {
            _18343 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _14564 = texture(irradiance_field, clamp((_14725 + vec2(1.0)) + (clamp((_18343 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _14725 + vec2(0.5), _14725 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _14859 = _12900 + vec3(0.0, 0.0, 1.0);
        highp vec3 _14864 = _14859 - frag_info.gi_anchor.xyz;
        bool _14867 = any(lessThan(_14864, vec3(0.0)));
        bool _14875 = false;
        if (!_14867)
        {
            _14875 = any(greaterThanEqual(_14864, frag_info.gi_counts.xyz));
        }
        else
        {
            _14875 = _14867;
        }
        vec3 mp_copy_18345 = vec3(0.0);
        highp float _14876 = _14875 ? 0.0 : 1.0;
        float mp_copy_14876 = _14876;
        vec3 _14882 = max(mix(_13042, mp_copy_12906, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _14898 = (_14859 * frag_info.gi_grid.xyz) - _12895;
        highp float _14900 = length(_14898);
        highp vec3 _18345 = vec3(0.0);
        if (_14900 > 9.9999997473787516355514526367188e-06)
        {
            _18345 = _14898 / vec3(_14900);
        }
        else
        {
            _18345 = _18189;
        }
        mp_copy_18345 = _18345;
        float _14918 = pow((dot(_18345, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15043 = _14859 - (frag_info.gi_counts.xyz * floor(_14859 / frag_info.gi_counts.xyz));
        highp float _15059 = _15043.x + (frag_info.gi_counts.x * (_15043.y + (frag_info.gi_counts.y * _15043.z)));
        float _18350 = 0.0;
        if (_13093)
        {
            highp float _15067 = floor(_15059 / frag_info.gi_counts.w);
            highp vec2 _15081 = vec2((_15059 - (_15067 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15067 * 16.0));
            vec3 _14941 = -mp_copy_18345;
            vec3 _15129 = _14941 / vec3((abs(_14941.x) + abs(_14941.y)) + abs(_14941.z));
            vec2 _18346 = vec2(0.0);
            if (_15129.z >= 0.0)
            {
                _18346 = _15129.xy;
            }
            else
            {
                _18346 = (vec2(1.0) - abs(_15129.yx)) * vec2((_15129.x >= 0.0) ? 1.0 : (-1.0), (_15129.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _14945 = texture(irradiance_field, clamp((_15081 + vec2(1.0)) + (clamp((_18346 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15081 + vec2(0.5), _15081 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _14950 = _14945.x * frag_info.gi_visibility.z;
            highp float _14962 = abs((_14950 * _14950) - ((_14945.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _14968 = (_14900 - _14950) - frag_info.gi_visibility.y;
            highp float _18347 = 0.0;
            if (_14968 <= 0.0)
            {
                _18347 = 1.0;
            }
            else
            {
                _18347 = _14962 / (_14962 + (_14968 * _14968));
            }
            _18350 = _14918 * mix(1.0, max(0.0500000007450580596923828125, (_18347 * _18347) * _18347), frag_info.gi_visibility.x);
        }
        else
        {
            _18350 = _14918;
        }
        float _14996 = max(9.9999999747524270787835121154785e-07, _18350);
        float _18351 = 0.0;
        if (_14996 < 0.20000000298023223876953125)
        {
            _18351 = _14996 * ((_14996 * _14996) * 25.0);
        }
        else
        {
            _18351 = _14996;
        }
        float _15011 = _18351 * (((_14882.x * _14882.y) * _14882.z) * mp_copy_14876);
        highp float _15170 = floor(_15059 / frag_info.gi_counts.w);
        highp vec2 _15184 = vec2((_15059 - (_15170 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15170 * 8.0));
        vec2 _18352 = vec2(0.0);
        if (_13399)
        {
            _18352 = _13396.xy;
        }
        else
        {
            _18352 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15023 = texture(irradiance_field, clamp((_15184 + vec2(1.0)) + (clamp((_18352 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15184 + vec2(0.5), _15184 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15318 = _12900 + vec3(1.0, 0.0, 1.0);
        highp vec3 _15323 = _15318 - frag_info.gi_anchor.xyz;
        bool _15326 = any(lessThan(_15323, vec3(0.0)));
        bool _15334 = false;
        if (!_15326)
        {
            _15334 = any(greaterThanEqual(_15323, frag_info.gi_counts.xyz));
        }
        else
        {
            _15334 = _15326;
        }
        vec3 mp_copy_18354 = vec3(0.0);
        highp float _15335 = _15334 ? 0.0 : 1.0;
        float mp_copy_15335 = _15335;
        vec3 _15341 = max(mix(_13042, mp_copy_12906, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15357 = (_15318 * frag_info.gi_grid.xyz) - _12895;
        highp float _15359 = length(_15357);
        highp vec3 _18354 = vec3(0.0);
        if (_15359 > 9.9999997473787516355514526367188e-06)
        {
            _18354 = _15357 / vec3(_15359);
        }
        else
        {
            _18354 = _18189;
        }
        mp_copy_18354 = _18354;
        float _15377 = pow((dot(_18354, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15502 = _15318 - (frag_info.gi_counts.xyz * floor(_15318 / frag_info.gi_counts.xyz));
        highp float _15518 = _15502.x + (frag_info.gi_counts.x * (_15502.y + (frag_info.gi_counts.y * _15502.z)));
        float _18359 = 0.0;
        if (_13093)
        {
            highp float _15526 = floor(_15518 / frag_info.gi_counts.w);
            highp vec2 _15540 = vec2((_15518 - (_15526 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15526 * 16.0));
            vec3 _15400 = -mp_copy_18354;
            vec3 _15588 = _15400 / vec3((abs(_15400.x) + abs(_15400.y)) + abs(_15400.z));
            vec2 _18355 = vec2(0.0);
            if (_15588.z >= 0.0)
            {
                _18355 = _15588.xy;
            }
            else
            {
                _18355 = (vec2(1.0) - abs(_15588.yx)) * vec2((_15588.x >= 0.0) ? 1.0 : (-1.0), (_15588.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15404 = texture(irradiance_field, clamp((_15540 + vec2(1.0)) + (clamp((_18355 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15540 + vec2(0.5), _15540 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15409 = _15404.x * frag_info.gi_visibility.z;
            highp float _15421 = abs((_15409 * _15409) - ((_15404.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15427 = (_15359 - _15409) - frag_info.gi_visibility.y;
            highp float _18356 = 0.0;
            if (_15427 <= 0.0)
            {
                _18356 = 1.0;
            }
            else
            {
                _18356 = _15421 / (_15421 + (_15427 * _15427));
            }
            _18359 = _15377 * mix(1.0, max(0.0500000007450580596923828125, (_18356 * _18356) * _18356), frag_info.gi_visibility.x);
        }
        else
        {
            _18359 = _15377;
        }
        float _15455 = max(9.9999999747524270787835121154785e-07, _18359);
        float _18360 = 0.0;
        if (_15455 < 0.20000000298023223876953125)
        {
            _18360 = _15455 * ((_15455 * _15455) * 25.0);
        }
        else
        {
            _18360 = _15455;
        }
        float _15470 = _18360 * (((_15341.x * _15341.y) * _15341.z) * mp_copy_15335);
        highp float _15629 = floor(_15518 / frag_info.gi_counts.w);
        highp vec2 _15643 = vec2((_15518 - (_15629 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_15629 * 8.0));
        vec2 _18361 = vec2(0.0);
        if (_13399)
        {
            _18361 = _13396.xy;
        }
        else
        {
            _18361 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15482 = texture(irradiance_field, clamp((_15643 + vec2(1.0)) + (clamp((_18361 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _15643 + vec2(0.5), _15643 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _15777 = _12900 + vec3(0.0, 1.0, 1.0);
        highp vec3 _15782 = _15777 - frag_info.gi_anchor.xyz;
        bool _15785 = any(lessThan(_15782, vec3(0.0)));
        bool _15793 = false;
        if (!_15785)
        {
            _15793 = any(greaterThanEqual(_15782, frag_info.gi_counts.xyz));
        }
        else
        {
            _15793 = _15785;
        }
        vec3 mp_copy_18363 = vec3(0.0);
        highp float _15794 = _15793 ? 0.0 : 1.0;
        float mp_copy_15794 = _15794;
        vec3 _15800 = max(mix(_13042, mp_copy_12906, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _15816 = (_15777 * frag_info.gi_grid.xyz) - _12895;
        highp float _15818 = length(_15816);
        highp vec3 _18363 = vec3(0.0);
        if (_15818 > 9.9999997473787516355514526367188e-06)
        {
            _18363 = _15816 / vec3(_15818);
        }
        else
        {
            _18363 = _18189;
        }
        mp_copy_18363 = _18363;
        float _15836 = pow((dot(_18363, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _15961 = _15777 - (frag_info.gi_counts.xyz * floor(_15777 / frag_info.gi_counts.xyz));
        highp float _15977 = _15961.x + (frag_info.gi_counts.x * (_15961.y + (frag_info.gi_counts.y * _15961.z)));
        float _18368 = 0.0;
        if (_13093)
        {
            highp float _15985 = floor(_15977 / frag_info.gi_counts.w);
            highp vec2 _15999 = vec2((_15977 - (_15985 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_15985 * 16.0));
            vec3 _15859 = -mp_copy_18363;
            vec3 _16047 = _15859 / vec3((abs(_15859.x) + abs(_15859.y)) + abs(_15859.z));
            vec2 _18364 = vec2(0.0);
            if (_16047.z >= 0.0)
            {
                _18364 = _16047.xy;
            }
            else
            {
                _18364 = (vec2(1.0) - abs(_16047.yx)) * vec2((_16047.x >= 0.0) ? 1.0 : (-1.0), (_16047.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _15863 = texture(irradiance_field, clamp((_15999 + vec2(1.0)) + (clamp((_18364 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _15999 + vec2(0.5), _15999 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _15868 = _15863.x * frag_info.gi_visibility.z;
            highp float _15880 = abs((_15868 * _15868) - ((_15863.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _15886 = (_15818 - _15868) - frag_info.gi_visibility.y;
            highp float _18365 = 0.0;
            if (_15886 <= 0.0)
            {
                _18365 = 1.0;
            }
            else
            {
                _18365 = _15880 / (_15880 + (_15886 * _15886));
            }
            _18368 = _15836 * mix(1.0, max(0.0500000007450580596923828125, (_18365 * _18365) * _18365), frag_info.gi_visibility.x);
        }
        else
        {
            _18368 = _15836;
        }
        float _15914 = max(9.9999999747524270787835121154785e-07, _18368);
        float _18369 = 0.0;
        if (_15914 < 0.20000000298023223876953125)
        {
            _18369 = _15914 * ((_15914 * _15914) * 25.0);
        }
        else
        {
            _18369 = _15914;
        }
        float _15929 = _18369 * (((_15800.x * _15800.y) * _15800.z) * mp_copy_15794);
        highp float _16088 = floor(_15977 / frag_info.gi_counts.w);
        highp vec2 _16102 = vec2((_15977 - (_16088 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16088 * 8.0));
        vec2 _18370 = vec2(0.0);
        if (_13399)
        {
            _18370 = _13396.xy;
        }
        else
        {
            _18370 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _15941 = texture(irradiance_field, clamp((_16102 + vec2(1.0)) + (clamp((_18370 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16102 + vec2(0.5), _16102 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _16236 = _12900 + vec3(1.0);
        highp vec3 _16241 = _16236 - frag_info.gi_anchor.xyz;
        bool _16244 = any(lessThan(_16241, vec3(0.0)));
        bool _16252 = false;
        if (!_16244)
        {
            _16252 = any(greaterThanEqual(_16241, frag_info.gi_counts.xyz));
        }
        else
        {
            _16252 = _16244;
        }
        vec3 mp_copy_18372 = vec3(0.0);
        highp float _16253 = _16252 ? 0.0 : 1.0;
        float mp_copy_16253 = _16253;
        vec3 _16259 = max(mp_copy_12906, vec3(0.001000000047497451305389404296875));
        highp vec3 _16275 = (_16236 * frag_info.gi_grid.xyz) - _12895;
        highp float _16277 = length(_16275);
        highp vec3 _18372 = vec3(0.0);
        if (_16277 > 9.9999997473787516355514526367188e-06)
        {
            _18372 = _16275 / vec3(_16277);
        }
        else
        {
            _18372 = _18189;
        }
        mp_copy_18372 = _18372;
        float _16295 = pow((dot(_18372, _18189) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _16420 = _16236 - (frag_info.gi_counts.xyz * floor(_16236 / frag_info.gi_counts.xyz));
        highp float _16436 = _16420.x + (frag_info.gi_counts.x * (_16420.y + (frag_info.gi_counts.y * _16420.z)));
        float _18377 = 0.0;
        if (_13093)
        {
            highp float _16444 = floor(_16436 / frag_info.gi_counts.w);
            highp vec2 _16458 = vec2((_16436 - (_16444 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16444 * 16.0));
            vec3 _16318 = -mp_copy_18372;
            vec3 _16506 = _16318 / vec3((abs(_16318.x) + abs(_16318.y)) + abs(_16318.z));
            vec2 _18373 = vec2(0.0);
            if (_16506.z >= 0.0)
            {
                _18373 = _16506.xy;
            }
            else
            {
                _18373 = (vec2(1.0) - abs(_16506.yx)) * vec2((_16506.x >= 0.0) ? 1.0 : (-1.0), (_16506.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _16322 = texture(irradiance_field, clamp((_16458 + vec2(1.0)) + (clamp((_18373 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16458 + vec2(0.5), _16458 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _16327 = _16322.x * frag_info.gi_visibility.z;
            highp float _16339 = abs((_16327 * _16327) - ((_16322.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _16345 = (_16277 - _16327) - frag_info.gi_visibility.y;
            highp float _18374 = 0.0;
            if (_16345 <= 0.0)
            {
                _18374 = 1.0;
            }
            else
            {
                _18374 = _16339 / (_16339 + (_16345 * _16345));
            }
            _18377 = _16295 * mix(1.0, max(0.0500000007450580596923828125, (_18374 * _18374) * _18374), frag_info.gi_visibility.x);
        }
        else
        {
            _18377 = _16295;
        }
        float _16373 = max(9.9999999747524270787835121154785e-07, _18377);
        float _18378 = 0.0;
        if (_16373 < 0.20000000298023223876953125)
        {
            _18378 = _16373 * ((_16373 * _16373) * 25.0);
        }
        else
        {
            _18378 = _16373;
        }
        float _16388 = _18378 * (((_16259.x * _16259.y) * _16259.z) * mp_copy_16253);
        highp float _16547 = floor(_16436 / frag_info.gi_counts.w);
        highp vec2 _16561 = vec2((_16436 - (_16547 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16547 * 8.0));
        vec2 _18379 = vec2(0.0);
        if (_13399)
        {
            _18379 = _13396.xy;
        }
        else
        {
            _18379 = (vec2(1.0) - abs(_13396.yx)) * vec2((_13396.x >= 0.0) ? 1.0 : (-1.0), (_13396.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _12953 = ((((((vec4(max(_13187.xyz, vec3(0.0)) * _13175, _13175) + vec4(max(_13646.xyz, vec3(0.0)) * _13634, _13634)) + vec4(max(_14105.xyz, vec3(0.0)) * _14093, _14093)) + vec4(max(_14564.xyz, vec3(0.0)) * _14552, _14552)) + vec4(max(_15023.xyz, vec3(0.0)) * _15011, _15011)) + vec4(max(_15482.xyz, vec3(0.0)) * _15470, _15470)) + vec4(max(_15941.xyz, vec3(0.0)) * _15929, _15929)) + vec4(max(texture(irradiance_field, clamp((_16561 + vec2(1.0)) + (clamp((_18379 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16561 + vec2(0.5), _16561 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _16388, _16388);
        highp float _12955 = _12953.w;
        highp vec3 _18381 = vec3(0.0);
        if (_12955 > 9.9999999747524270787835121154785e-07)
        {
            _18381 = _12953.xyz / vec3(_12955);
        }
        else
        {
            _18381 = vec3(0.0);
        }
        _18499 = mix(_7662, _18381 * _12782, vec3(_18308));
    }
    else
    {
        _18499 = _7662;
    }
    vec2 _7688 = clamp(vec2(_7226, _18237), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7690 = texture(brdf_lut, vec2(_7688.x * 0.3333333432674407958984375, _7688.y));
    float _7694 = _7690.x;
    float _7697 = _7690.y;
    vec3 _7699 = ((_7218 + ((max(vec3(1.0 - _18237), _7218) - _7218) * pow(clamp(1.0 - _7226, 0.0, 1.0), 5.0))) * _7694) + vec3(_7697);
    float _7705 = 1.0 - (_7694 + _7697);
    vec3 _7709 = vec3(1.0) - _7218;
    vec3 _7712 = _7218 + (_7709 * vec3(0.0476190485060214996337890625));
    vec3 _7723 = ((_7699 * _7705) * _7712) / (vec3(1.0) - (_7712 * _7705));
    float _7726 = 1.0 - _6168;
    vec3 _7727 = _7070 * _7726;
    float _18778 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7620)
    {
        float _16669 = max(acos(clamp(exp2(((-3.321929931640625) * _18237) * _18237), 0.0, 1.0)), 0.100000001490116119384765625);
        _18778 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_18295, _7230), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _18578, 0.0, 1.0)))) + _16669) / (2.0 * _16669), 0.0, 1.0));
    }
    else
    {
        float _18779 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _18779 = clamp((pow(_7222 + _18578, exp2(((-16.0) * _18237) - 1.0)) - 1.0) + _18578, 0.0, 1.0);
        }
        else
        {
            _18779 = _18578;
        }
        _18778 = _18779;
    }
    highp vec3 _7786 = ((((_7723 + (_7727 * ((vec3(1.0) - _7699) - _7723))) * _18499) * _18717) + (((_7699 * (_18307 * frag_info.environment_intensity)) * 1.0) * _18778)) * mix(1.0, _7209, frag_info.radiance_blend.y);
    highp vec3 _19010 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _19010 = _7786 + ((_18262.xyz * _7727) * _6202);
    }
    else
    {
        _19010 = _7786;
    }
    highp vec3 _19014 = vec3(0.0);
    if (_7159)
    {
        highp vec3 _18929 = vec3(0.0);
        highp vec3 _18930 = vec3(0.0);
        do
        {
            float _16766 = max(dot(_18189, _18865), 0.0);
            highp float hp_copy_16766 = _16766;
            if (_16766 <= 0.0)
            {
                _18930 = vec3(0.0);
                _18929 = vec3(0.0);
                break;
            }
            float _16772 = max(_7222, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_16772 = _16772;
            vec3 _16775 = _18865 + mp_copy_18267;
            float _16778 = dot(_16775, _16775);
            vec3 _18927 = vec3(0.0);
            vec3 _18928 = vec3(0.0);
            if (_16778 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _16786 = _16775 * inversesqrt(_16778);
                float _18926 = 0.0;
                do
                {
                    float _16843 = dot(_18189, _16786);
                    if (_16843 <= 0.0)
                    {
                        _18926 = 0.0;
                        break;
                    }
                    float _16850 = _18237 * _18237;
                    vec3 _16853 = cross(_18189, _16786);
                    float _16856 = _16843 * _16850;
                    float _16865 = _16850 / (dot(_16853, _16853) + (_16856 * _16856));
                    _18926 = min((_16865 * _16865) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _16903 = _7218 + (_7709 * pow(clamp(1.0 - max(dot(_16786, _18267), 0.0), 0.0, 1.0), 5.0));
                _18928 = (_16903 * min(_18926 * (0.5 / max(mix((2.0 * hp_copy_16766) * _16772, hp_copy_16766 + hp_copy_16772, hp_copy_18237 * hp_copy_18237), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _18927 = _16903;
            }
            else
            {
                _18928 = vec3(0.0);
                _18927 = _7218;
            }
            _18930 = (_18928 * frag_info.directional_light_color.xyz) * _16766;
            _18929 = (((((vec3(1.0) - _18927) * _7726) * _7070) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _16766;
            break;
        } while(false);
        _19014 = _18939 + ((_18929 + _18930) * _7209);
    }
    else
    {
        _19014 = _18939;
    }
    bool _7848 = _FogInfo.params0.y > 0.5;
    bool _7854 = false;
    if (_7848)
    {
        _7854 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7854 = _7848;
    }
    highp vec3 _19019 = vec3(0.0);
    if (_7854)
    {
        vec3 mp_copy_19015 = vec3(0.0);
        highp vec3 _19015 = vec3(0.0);
        if (_9855)
        {
            _19015 = -view_info.camera_forward.xyz;
        }
        else
        {
            _19015 = normalize(v_viewvector);
        }
        mp_copy_19015 = _19015;
        vec3 _7859 = _7617 * (-mp_copy_19015);
        vec3 _19016 = vec3(0.0);
        do
        {
            if (_12354)
            {
                vec2 _17025 = vec2(atan(_7859.z, _7859.x), asin(clamp(_7859.y, -1.0, 1.0)));
                highp vec2 hp_copy_17025 = _17025;
                _19016 = textureLod(prefiltered_radiance, (hp_copy_17025 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _17044 = vec2(atan(_7859.z, _7859.x), asin(clamp(_7859.y, -1.0, 1.0)));
            highp vec2 hp_copy_17044 = _17044;
            highp vec2 _17049 = (hp_copy_17044 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _16956 = clamp(_17049.y, 0.00390625, 0.99609375);
            float _16962 = floor(0.0);
            highp float _16981 = _17049.x;
            _19016 = mix(textureLod(prefiltered_radiance, vec2(_16981, (_16962 + _16956) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_16981, (min(_16962 + 1.0, 7.0) + _16956) * 0.125), 0.0).xyz, vec3(-_16962));
            break;
        } while(false);
        highp vec3 _19018 = vec3(0.0);
        if (_7640)
        {
            vec3 _19017 = vec3(0.0);
            do
            {
                if (_12354)
                {
                    vec2 _17154 = vec2(atan(_7859.z, _7859.x), asin(clamp(_7859.y, -1.0, 1.0)));
                    highp vec2 hp_copy_17154 = _17154;
                    _19017 = textureLod(prefiltered_radiance_b, (hp_copy_17154 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _17173 = vec2(atan(_7859.z, _7859.x), asin(clamp(_7859.y, -1.0, 1.0)));
                highp vec2 hp_copy_17173 = _17173;
                highp vec2 _17178 = (hp_copy_17173 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _17085 = clamp(_17178.y, 0.00390625, 0.99609375);
                float _17091 = floor(0.0);
                highp float _17110 = _17178.x;
                _19017 = mix(textureLod(prefiltered_radiance_b, vec2(_17110, (_17091 + _17085) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_17110, (min(_17091 + 1.0, 7.0) + _17085) * 0.125), 0.0).xyz, vec3(-_17091));
                break;
            } while(false);
            _19018 = mix(_19016, _19017, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _19018 = _19016;
        }
        _19019 = _19018 * frag_info.environment_intensity;
    }
    else
    {
        _19019 = _FogInfo.color.xyz;
    }
    highp vec4 _7883 = vec4(min((_19010 + (_19014 * mix(1.0, _18578, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _18212, vec3(65504.0)), 1.0) * _19822;
    highp vec4 _19034 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _19034 = _7883;
            break;
        }
        int _17222 = int(_FogInfo.params0.x + 0.5);
        if (_17222 == 0)
        {
            _19034 = _7883;
            break;
        }
        highp float _19021 = 0.0;
        if (_9855)
        {
            _19021 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _19021 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_19021 > _FogInfo.params1.w))
        {
            _19034 = _7883;
            break;
        }
        float _19025 = 0.0;
        if (_17222 == 1)
        {
            _19025 = clamp((_19021 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _19026 = 0.0;
            if (_17222 == 2)
            {
                highp float _19024 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _19022 = vec3(0.0);
                    if (_9855)
                    {
                        _19022 = v_position - (view_info.camera_forward.xyz * _19021);
                    }
                    else
                    {
                        _19022 = v_position + v_viewvector;
                    }
                    highp float _17303 = -_FogInfo.params2.y;
                    highp float _17310 = _FogInfo.params1.x * exp(_17303 * (_19022.y - _FogInfo.params2.x));
                    highp float _17327 = _FogInfo.params2.y * (v_position.y - _19022.y);
                    highp float _19023 = 0.0;
                    if (abs(_17327) > 0.00124999997206032276153564453125)
                    {
                        _19023 = (_17310 - (_FogInfo.params1.x * exp(_17303 * (v_position.y - _FogInfo.params2.x)))) / _17327;
                    }
                    else
                    {
                        _19023 = _17310;
                    }
                    _19024 = _19023 * max(_19021 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _19024 = _FogInfo.params1.x * max(_19021 - _FogInfo.params1.y, 0.0);
                }
                _19026 = 1.0 - exp(-_19024);
            }
            else
            {
                highp float _17365 = _FogInfo.params1.x * max(_19021 - _FogInfo.params1.y, 0.0);
                _19026 = 1.0 - exp((-_17365) * _17365);
            }
            _19025 = _19026;
        }
        highp float _17377 = min(_19025, _FogInfo.params0.z);
        if (_17377 <= 0.0)
        {
            _19034 = _7883;
            break;
        }
        highp vec3 _17390 = mix(_FogInfo.color.xyz, _19019, vec3(_FogInfo.params0.w));
        bool _17393 = _FogInfo.sun.w > 0.5;
        bool _17399 = false;
        if (_17393)
        {
            _17399 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _17399 = _17393;
        }
        vec3 _19030 = vec3(0.0);
        if (_17399)
        {
            vec3 mp_copy_19027 = vec3(0.0);
            highp vec3 _19027 = vec3(0.0);
            if (_9855)
            {
                _19027 = -view_info.camera_forward.xyz;
            }
            else
            {
                _19027 = normalize(v_viewvector);
            }
            mp_copy_19027 = _19027;
            highp float _17415 = pow(max(dot(-mp_copy_19027, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_17415 = _17415;
            _19030 = _17390 + ((_FogInfo.sun.xyz * mp_copy_17415) * _FogInfo.params2.z);
        }
        else
        {
            _19030 = _17390;
        }
        highp float _17428 = _7883.w;
        float mp_copy_17428 = _17428;
        _19034 = vec4(mix(_7883.xyz, _19030 * mp_copy_17428, vec3(_17377)), _17428);
        break;
    } while(false);
    vec4 _19036 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _19036 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _19036 = _19034;
        break;
    } while(false);
    frag_color = _19036;
    float _19037 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _19037 = 1.0;
    }
    else
    {
        _19037 = abs(frag_info.fade);
    }
    frag_color *= _19037;
}

