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

layout(std140) uniform DebugViewInfo
{
    vec4 view;
    vec4 params;
    vec4 left;
    highp vec4 depth;
} debug_view_info;

layout(std140) uniform FogInfo
{
    highp vec4 params0;
    highp vec4 params1;
    highp vec4 params2;
    vec4 color;
    vec4 sun;
    vec4 sun_dir;
} _FogInfo;

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
in vec4 v_color;
in highp vec3 v_position;
layout(location = 0) out vec4 frag_color;

void main()
{
    highp float _7183 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_7183 = _7183;
    vec3 _7185 = normalize(v_normal);
    vec3 _7187 = _7185 * mp_copy_7183;
    vec4 _7228 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _7231 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _24758 = vec2(0.0);
    if (_7231)
    {
        highp vec2 _24757 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _24757 = v_texture_coords_1;
        }
        else
        {
            _24757 = v_texture_coords;
        }
        highp vec2 _7418 = _24757 * texture_transforms.base_color_transform.zw;
        highp float _7424 = _7418.x;
        highp float _7429 = _7418.y;
        _24758 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _7424) - (texture_transforms.base_color_rotation.y * _7429), (texture_transforms.base_color_rotation.y * _7424) + (texture_transforms.base_color_rotation.x * _7429));
    }
    else
    {
        _24758 = v_texture_coords;
    }
    vec4 _7245 = texture(base_color_texture, _24758);
    vec3 _7247 = _7245.xyz;
    vec3 _7255 = (mix(_7247 * vec3(0.077399380505084991455078125), pow((_7247 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7247)) * _7228.xyz) * frag_info.color.xyz;
    float _28247 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_7245.w * _7228.w) * frag_info.color.w);
    float _7271 = _7255.x;
    float _7272 = _7255.y;
    float _7273 = _7255.z;
    vec4 _7274 = vec4(_7271, _7272, _7273, _28247);
    vec3 _24770 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _24761 = vec2(0.0);
        if (_7231)
        {
            highp vec2 _24760 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _24760 = v_texture_coords_1;
            }
            else
            {
                _24760 = v_texture_coords;
            }
            highp vec2 _7512 = _24760 * texture_transforms.normal_transform.zw;
            highp float _7518 = _7512.x;
            highp float _7523 = _7512.y;
            _24761 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _7518) - (texture_transforms.normal_rotation.y * _7523), (texture_transforms.normal_rotation.y * _7518) + (texture_transforms.normal_rotation.x * _7523));
        }
        else
        {
            _24761 = v_texture_coords;
        }
        vec3 _7570 = ((texture(normal_texture, _24761).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _7574 = _7570.xy * vec2(frag_info.normal_scale);
        vec3 _23963 = _7570;
        _23963.x = _7574.x;
        _23963.y = _7574.y;
        highp vec3 _7580 = -v_viewvector;
        mat3 _24769 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _7610 = v_tangent.xyz - (_7187 * dot(_7187, v_tangent.xyz));
            highp float _7613 = dot(_7610, _7610);
            bool _7615 = _7613 <= 1.0000000133514319600180897396058e-10;
            bool _7623 = false;
            if (!_7615)
            {
                _7623 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _7623 = _7615;
            }
            if (_7623)
            {
                highp vec2 _7681 = dFdx(_24761);
                highp vec2 _7683 = dFdy(_24761);
                bvec2 _28249 = bvec2(length(_7681) == 0.0);
                highp vec2 _28250 = vec2(_28249.x ? vec2(1.0, 0.0).x : _7681.x, _28249.y ? vec2(1.0, 0.0).y : _7681.y);
                bvec2 _28251 = bvec2(length(_7683) == 0.0);
                highp vec2 _28252 = vec2(_28251.x ? vec2(0.0, 1.0).x : _7683.x, _28251.y ? vec2(0.0, 1.0).y : _7683.y);
                highp vec3 _7696 = cross(dFdy(_7580), _7187);
                highp vec3 _7699 = cross(_7187, dFdx(_7580));
                highp vec3 _7708 = (_7696 * _28250.x) + (_7699 * _28252.x);
                highp vec3 _7717 = (_7696 * _28250.y) + (_7699 * _28252.y);
                highp float _7726 = inversesqrt(max(max(dot(_7708, _7708), dot(_7717, _7717)), 9.9999996826552253889678874634872e-21));
                _24769 = mat3(_7708 * _7726, _7717 * _7726, _7187);
                break;
            }
            highp vec3 _7633 = _7610 * inversesqrt(_7613);
            _24769 = mat3(_7633, normalize(cross(_7187, _7633)) * sign(v_tangent.w), _7187);
            break;
        } while(false);
        _24770 = normalize(_24769 * _23963);
    }
    else
    {
        _24770 = _7187;
    }
    highp vec2 _24772 = vec2(0.0);
    if (_7231)
    {
        highp vec2 _24771 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _24771 = v_texture_coords_1;
        }
        else
        {
            _24771 = v_texture_coords;
        }
        highp vec2 _7788 = _24771 * texture_transforms.metallic_roughness_transform.zw;
        highp float _7794 = _7788.x;
        highp float _7799 = _7788.y;
        _24772 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _7794) - (texture_transforms.metallic_roughness_rotation.y * _7799), (texture_transforms.metallic_roughness_rotation.y * _7794) + (texture_transforms.metallic_roughness_rotation.x * _7799));
    }
    else
    {
        _24772 = v_texture_coords;
    }
    vec4 _7314 = texture(metallic_roughness_texture, _24772);
    float _7320 = clamp(_7314.z * frag_info.metallic_factor, 0.0, 1.0);
    float _7327 = clamp(_7314.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _24774 = vec2(0.0);
    if (_7231)
    {
        highp vec2 _24773 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _24773 = v_texture_coords_1;
        }
        else
        {
            _24773 = v_texture_coords;
        }
        highp vec2 _7858 = _24773 * texture_transforms.occlusion_transform.zw;
        highp float _7864 = _7858.x;
        highp float _7869 = _7858.y;
        _24774 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _7864) - (texture_transforms.occlusion_rotation.y * _7869), (texture_transforms.occlusion_rotation.y * _7864) + (texture_transforms.occlusion_rotation.x * _7869));
    }
    else
    {
        _24774 = v_texture_coords;
    }
    vec4 _7342 = texture(occlusion_texture, _24774);
    float _7349 = 1.0 - ((1.0 - _7342.x) * frag_info.occlusion_strength);
    highp vec2 _24776 = vec2(0.0);
    if (_7231)
    {
        highp vec2 _24775 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _24775 = v_texture_coords_1;
        }
        else
        {
            _24775 = v_texture_coords;
        }
        highp vec2 _7928 = _24775 * texture_transforms.emissive_transform.zw;
        highp float _7934 = _7928.x;
        highp float _7939 = _7928.y;
        _24776 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _7934) - (texture_transforms.emissive_rotation.y * _7939), (texture_transforms.emissive_rotation.y * _7934) + (texture_transforms.emissive_rotation.x * _7939));
    }
    else
    {
        _24776 = v_texture_coords;
    }
    bool _7996 = false;
    vec4 _7364 = texture(emissive_texture, _24776);
    vec3 _7365 = _7364.xyz;
    vec3 _7373 = (mix(_7365 * vec3(0.077399380505084991455078125), pow((_7365 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7365)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w;
    float _24806 = 0.0;
    do
    {
        _7996 = debug_view_info.view.x < 0.5;
        if (_7996)
        {
            _24806 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _24806 = 1.0;
            break;
        }
        _24806 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    bool _7979 = _24806 < 0.5;
    bool _7988 = false;
    if (!_7979)
    {
        _7988 = (_24806 > 1.5) && (_24806 < 2.5);
    }
    else
    {
        _7988 = _7979;
    }
    vec4 _27479 = vec4(0.0);
    if (_7988)
    {
        highp float hp_copy_24823 = 0.0;
        vec3 _8222 = _7274.xyz;
        float _24823 = 0.0;
        do
        {
            if (frag_info.specular_aa_variance <= 0.0)
            {
                _24823 = _7327;
                break;
            }
            vec3 _9040 = dFdx(_24770);
            vec3 _9042 = dFdy(_24770);
            _24823 = sqrt(clamp((_7327 * _7327) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_9040, _9040), dot(_9042, _9042))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
            break;
        } while(false);
        hp_copy_24823 = _24823;
        float _24833 = 0.0;
        vec3 _24838 = vec3(0.0);
        float _25111 = 0.0;
        vec4 _25487 = vec4(0.0);
        vec3 _25638 = vec3(0.0);
        if (frag_info.ssao_params.x > 0.5)
        {
            vec4 _8249 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
            float _24824 = 0.0;
            if (frag_info.camera_up.w > 0.5)
            {
                _24824 = _8249.w;
            }
            else
            {
                _24824 = _8249.x;
            }
            float _8262 = min(_7349, _24824);
            bool _8265 = frag_info.ssao_lighting.z > 0.5;
            bool _8271 = false;
            if (_8265)
            {
                _8271 = frag_info.camera_up.w < 0.5;
            }
            else
            {
                _8271 = _8265;
            }
            vec3 _24839 = vec3(0.0);
            if (_8271)
            {
                vec2 _9075 = (_8249.zw * 2.0) - vec2(1.0);
                float _9077 = _9075.x;
                float _9079 = _9075.y;
                float _9087 = (1.0 - abs(_9077)) - abs(_9079);
                vec3 _9088 = vec3(_9077, _9079, _9087);
                vec3 _24827 = vec3(0.0);
                if (_9087 < 0.0)
                {
                    vec2 _9101 = (vec2(1.0) - abs(_9088.yx)) * vec2((_9077 >= 0.0) ? 1.0 : (-1.0), (_9079 >= 0.0) ? 1.0 : (-1.0));
                    vec3 _24012 = _9088;
                    _24012.x = _9101.x;
                    _24012.y = _9101.y;
                    _24827 = _24012;
                }
                else
                {
                    _24827 = _9088;
                }
                vec3 _9109 = -normalize(_24827);
                _24839 = normalize(((frag_info.camera_right.xyz * _9109.x) + (frag_info.camera_up.xyz * _9109.y)) + (frag_info.camera_forward.xyz * _9109.z));
            }
            else
            {
                _24839 = vec3(0.0);
            }
            vec3 _8299 = vec3(_8262);
            _25638 = mix(_8299, max(_8299, ((((((_8222 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _8262) + ((_8222 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _8262) + ((_8222 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _8262), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
            _25487 = _8249;
            _25111 = _8262;
            _24838 = _24839;
            _24833 = float(_8271);
        }
        else
        {
            _25638 = vec3(_7349);
            _25487 = vec4(1.0);
            _25111 = _7349;
            _24838 = vec3(0.0);
            _24833 = 0.0;
        }
        vec3 mp_copy_24831 = vec3(0.0);
        bool _9158 = view_info.camera_forward.w > 0.5;
        highp vec3 _24831 = vec3(0.0);
        if (_9158)
        {
            _24831 = -view_info.camera_forward.xyz;
        }
        else
        {
            _24831 = normalize(v_viewvector);
        }
        mp_copy_24831 = _24831;
        vec3 _8317 = mix(frag_info.dielectric_f0.xyz, _8222, vec3(_7320));
        float _8320 = dot(_24770, _24831);
        float _8321 = max(_8320, 0.0);
        float _8325 = max(dot(_7187, _24831), 0.0);
        vec3 _8329 = reflect(-mp_copy_24831, _24770);
        mat3 _8342 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
        bool _8345 = _24833 > 0.5;
        bvec3 _8348 = bvec3(_8345);
        highp vec3 _8349 = vec3(_8348.x ? _24838.x : _24770.x, _8348.y ? _24838.y : _24770.y, _8348.z ? _24838.z : _24770.z);
        vec3 mp_copy_8349 = _8349;
        vec3 _8350 = _8342 * mp_copy_8349;
        vec3 _24842 = vec3(0.0);
        if (frag_info.probe_box.w > 0.5)
        {
            vec3 _9225 = _8329 + (((step(vec3(0.0), _8329) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
            highp vec3 hp_copy_9225 = _9225;
            highp vec3 _9227 = vec3(1.0) / hp_copy_9225;
            highp vec3 _9244 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _9227, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _9227);
            _24842 = normalize((v_position + (_8329 * max(min(min(_9244.x, _9244.y), _9244.z), 0.0))) - frag_info.probe_box.xyz);
        }
        else
        {
            _24842 = _8329;
        }
        bool _9472 = false;
        vec3 _8355 = _8342 * _24842;
        float _9291 = _8350.y;
        float _9292 = 0.48860299587249755859375 * _9291;
        float _9298 = _8350.z;
        float _9299 = 0.48860299587249755859375 * _9298;
        float _9305 = _8350.x;
        float _9306 = 0.48860299587249755859375 * _9305;
        float _9313 = 1.09254801273345947265625 * _9305;
        float _9316 = _9313 * _9291;
        float _9326 = (1.09254801273345947265625 * _9291) * _9298;
        float _9338 = 0.3153919875621795654296875 * (((3.0 * _9298) * _9298) - 1.0);
        float _9348 = _9313 * _9298;
        float _9364 = 0.546274006366729736328125 * ((_9305 * _9305) - (_9291 * _9291));
        vec3 _8358 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _9292)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _9299)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _9306)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _9316)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _9326)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _9338)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _9348)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _9364), vec3(0.0));
        vec3 _24843 = vec3(0.0);
        do
        {
            _9472 = radiance_layout_info.mip_layout > 0.5;
            if (_9472)
            {
                vec2 _9551 = vec2(atan(_8355.z, _8355.x), asin(clamp(_8355.y, -1.0, 1.0)));
                highp vec2 hp_copy_9551 = _9551;
                _24843 = textureLod(prefiltered_radiance, (hp_copy_9551 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24823, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9570 = vec2(atan(_8355.z, _8355.x), asin(clamp(_8355.y, -1.0, 1.0)));
            highp vec2 hp_copy_9570 = _9570;
            highp vec2 _9575 = (hp_copy_9570 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9482 = clamp(_9575.y, 0.00390625, 0.99609375);
            float _9486 = clamp(_24823, 0.0, 1.0) * 7.0;
            float _9488 = floor(_9486);
            highp float _9507 = _9575.x;
            _24843 = mix(texture(prefiltered_radiance, vec2(_9507, (_9488 + _9482) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_9507, (min(_9488 + 1.0, 7.0) + _9482) * 0.125)).xyz, vec3(_9486 - _9488));
            break;
        } while(false);
        bool _8365 = frag_info.radiance_blend.x > 0.0;
        highp vec3 _24848 = vec3(0.0);
        highp vec3 _24849 = vec3(0.0);
        if (_8365)
        {
            vec3 _24844 = vec3(0.0);
            do
            {
                if (_9472)
                {
                    vec2 _9863 = vec2(atan(_8355.z, _8355.x), asin(clamp(_8355.y, -1.0, 1.0)));
                    highp vec2 hp_copy_9863 = _9863;
                    _24844 = textureLod(prefiltered_radiance_b, (hp_copy_9863 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24823, 0.0, 1.0) * 7.0).xyz;
                    break;
                }
                vec2 _9882 = vec2(atan(_8355.z, _8355.x), asin(clamp(_8355.y, -1.0, 1.0)));
                highp vec2 hp_copy_9882 = _9882;
                highp vec2 _9887 = (hp_copy_9882 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _9794 = clamp(_9887.y, 0.00390625, 0.99609375);
                float _9798 = clamp(_24823, 0.0, 1.0) * 7.0;
                float _9800 = floor(_9798);
                highp float _9819 = _9887.x;
                _24844 = mix(texture(prefiltered_radiance_b, vec2(_9819, (_9800 + _9794) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_9819, (min(_9800 + 1.0, 7.0) + _9794) * 0.125)).xyz, vec3(_9798 - _9800));
                break;
            } while(false);
            highp vec3 _8376 = vec3(frag_info.radiance_blend.x);
            _24849 = mix(_24843, _24844, _8376);
            _24848 = mix(_8358, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _9292)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _9299)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _9306)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _9316)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _9326)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _9338)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _9348)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _9364), vec3(0.0)), _8376);
        }
        else
        {
            _24849 = _24843;
            _24848 = _8358;
        }
        highp float _9900 = 0.0;
        highp vec3 _8387 = _24848 * frag_info.environment_intensity;
        float _24850 = 0.0;
        do
        {
            _9900 = frag_info.gi_grid.w;
            if (_9900 <= 0.0)
            {
                _24850 = 0.0;
                break;
            }
            highp vec3 _9913 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
            highp vec3 _9921 = min(_9913, (frag_info.gi_counts.xyz - vec3(1.0)) - _9913);
            _24850 = clamp(min(_9921.x, min(_9921.y, _9921.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
            break;
        } while(false);
        highp vec3 _25041 = vec3(0.0);
        if (_24850 > 0.0)
        {
            highp vec3 _10013 = v_position + (((_24770 * 0.20000000298023223876953125) + (mp_copy_24831 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
            highp vec3 _10016 = _10013 / frag_info.gi_grid.xyz;
            highp vec3 _10018 = floor(_10016);
            highp vec3 _10024 = clamp(_10016 - _10018, vec3(0.0), vec3(1.0));
            vec3 mp_copy_10024 = _10024;
            highp vec3 _10146 = _10018 - frag_info.gi_anchor.xyz;
            bool _10149 = any(lessThan(_10146, vec3(0.0)));
            bool _10157 = false;
            if (!_10149)
            {
                _10157 = any(greaterThanEqual(_10146, frag_info.gi_counts.xyz));
            }
            else
            {
                _10157 = _10149;
            }
            vec3 mp_copy_24851 = vec3(0.0);
            highp float _10158 = _10157 ? 0.0 : 1.0;
            float mp_copy_10158 = _10158;
            vec3 _10160 = vec3(1.0) - mp_copy_10024;
            vec3 _10164 = max(_10160, vec3(0.001000000047497451305389404296875));
            highp vec3 _10180 = (_10018 * frag_info.gi_grid.xyz) - _10013;
            highp float _10182 = length(_10180);
            highp vec3 _24851 = vec3(0.0);
            if (_10182 > 9.9999997473787516355514526367188e-06)
            {
                _24851 = _10180 / vec3(_10182);
            }
            else
            {
                _24851 = _24770;
            }
            mp_copy_24851 = _24851;
            float _10200 = pow((dot(_24851, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10325 = _10018 - (frag_info.gi_counts.xyz * floor(_10018 / frag_info.gi_counts.xyz));
            highp float _10341 = _10325.x + (frag_info.gi_counts.x * (_10325.y + (frag_info.gi_counts.y * _10325.z)));
            bool _10211 = frag_info.gi_visibility.x > 0.0;
            float _24856 = 0.0;
            if (_10211)
            {
                highp float _10349 = floor(_10341 / frag_info.gi_counts.w);
                highp vec2 _10363 = vec2((_10341 - (_10349 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10349 * 16.0));
                vec3 _10223 = -mp_copy_24851;
                vec3 _10411 = _10223 / vec3((abs(_10223.x) + abs(_10223.y)) + abs(_10223.z));
                vec2 _24852 = vec2(0.0);
                if (_10411.z >= 0.0)
                {
                    _24852 = _10411.xy;
                }
                else
                {
                    _24852 = (vec2(1.0) - abs(_10411.yx)) * vec2((_10411.x >= 0.0) ? 1.0 : (-1.0), (_10411.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10227 = texture(irradiance_field, clamp((_10363 + vec2(1.0)) + (clamp((_24852 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10363 + vec2(0.5), _10363 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10232 = _10227.x * frag_info.gi_visibility.z;
                highp float _10244 = abs((_10232 * _10232) - ((_10227.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10250 = (_10182 - _10232) - frag_info.gi_visibility.y;
                highp float _24853 = 0.0;
                if (_10250 <= 0.0)
                {
                    _24853 = 1.0;
                }
                else
                {
                    _24853 = _10244 / (_10244 + (_10250 * _10250));
                }
                _24856 = _10200 * mix(1.0, max(0.0500000007450580596923828125, (_24853 * _24853) * _24853), frag_info.gi_visibility.x);
            }
            else
            {
                _24856 = _10200;
            }
            float _10278 = max(9.9999999747524270787835121154785e-07, _24856);
            float _24857 = 0.0;
            if (_10278 < 0.20000000298023223876953125)
            {
                _24857 = _10278 * ((_10278 * _10278) * 25.0);
            }
            else
            {
                _24857 = _10278;
            }
            float _10293 = _24857 * (((_10164.x * _10164.y) * _10164.z) * mp_copy_10158);
            highp float _10452 = floor(_10341 / frag_info.gi_counts.w);
            highp vec2 _10466 = vec2((_10341 - (_10452 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10452 * 8.0));
            vec3 _10514 = _24770 / vec3((abs(_24770.x) + abs(_24770.y)) + abs(_24770.z));
            bool _10517 = _10514.z >= 0.0;
            vec2 _24858 = vec2(0.0);
            if (_10517)
            {
                _24858 = _10514.xy;
            }
            else
            {
                _24858 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10305 = texture(irradiance_field, clamp((_10466 + vec2(1.0)) + (clamp((_24858 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10466 + vec2(0.5), _10466 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _10600 = _10018 + vec3(1.0, 0.0, 0.0);
            highp vec3 _10605 = _10600 - frag_info.gi_anchor.xyz;
            bool _10608 = any(lessThan(_10605, vec3(0.0)));
            bool _10616 = false;
            if (!_10608)
            {
                _10616 = any(greaterThanEqual(_10605, frag_info.gi_counts.xyz));
            }
            else
            {
                _10616 = _10608;
            }
            vec3 mp_copy_24860 = vec3(0.0);
            highp float _10617 = _10616 ? 0.0 : 1.0;
            float mp_copy_10617 = _10617;
            vec3 _10623 = max(mix(_10160, mp_copy_10024, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _10639 = (_10600 * frag_info.gi_grid.xyz) - _10013;
            highp float _10641 = length(_10639);
            highp vec3 _24860 = vec3(0.0);
            if (_10641 > 9.9999997473787516355514526367188e-06)
            {
                _24860 = _10639 / vec3(_10641);
            }
            else
            {
                _24860 = _24770;
            }
            mp_copy_24860 = _24860;
            float _10659 = pow((dot(_24860, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10784 = _10600 - (frag_info.gi_counts.xyz * floor(_10600 / frag_info.gi_counts.xyz));
            highp float _10800 = _10784.x + (frag_info.gi_counts.x * (_10784.y + (frag_info.gi_counts.y * _10784.z)));
            float _24865 = 0.0;
            if (_10211)
            {
                highp float _10808 = floor(_10800 / frag_info.gi_counts.w);
                highp vec2 _10822 = vec2((_10800 - (_10808 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10808 * 16.0));
                vec3 _10682 = -mp_copy_24860;
                vec3 _10870 = _10682 / vec3((abs(_10682.x) + abs(_10682.y)) + abs(_10682.z));
                vec2 _24861 = vec2(0.0);
                if (_10870.z >= 0.0)
                {
                    _24861 = _10870.xy;
                }
                else
                {
                    _24861 = (vec2(1.0) - abs(_10870.yx)) * vec2((_10870.x >= 0.0) ? 1.0 : (-1.0), (_10870.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10686 = texture(irradiance_field, clamp((_10822 + vec2(1.0)) + (clamp((_24861 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10822 + vec2(0.5), _10822 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10691 = _10686.x * frag_info.gi_visibility.z;
                highp float _10703 = abs((_10691 * _10691) - ((_10686.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10709 = (_10641 - _10691) - frag_info.gi_visibility.y;
                highp float _24862 = 0.0;
                if (_10709 <= 0.0)
                {
                    _24862 = 1.0;
                }
                else
                {
                    _24862 = _10703 / (_10703 + (_10709 * _10709));
                }
                _24865 = _10659 * mix(1.0, max(0.0500000007450580596923828125, (_24862 * _24862) * _24862), frag_info.gi_visibility.x);
            }
            else
            {
                _24865 = _10659;
            }
            float _10737 = max(9.9999999747524270787835121154785e-07, _24865);
            float _24866 = 0.0;
            if (_10737 < 0.20000000298023223876953125)
            {
                _24866 = _10737 * ((_10737 * _10737) * 25.0);
            }
            else
            {
                _24866 = _10737;
            }
            float _10752 = _24866 * (((_10623.x * _10623.y) * _10623.z) * mp_copy_10617);
            highp float _10911 = floor(_10800 / frag_info.gi_counts.w);
            highp vec2 _10925 = vec2((_10800 - (_10911 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10911 * 8.0));
            vec2 _24867 = vec2(0.0);
            if (_10517)
            {
                _24867 = _10514.xy;
            }
            else
            {
                _24867 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10764 = texture(irradiance_field, clamp((_10925 + vec2(1.0)) + (clamp((_24867 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10925 + vec2(0.5), _10925 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11059 = _10018 + vec3(0.0, 1.0, 0.0);
            highp vec3 _11064 = _11059 - frag_info.gi_anchor.xyz;
            bool _11067 = any(lessThan(_11064, vec3(0.0)));
            bool _11075 = false;
            if (!_11067)
            {
                _11075 = any(greaterThanEqual(_11064, frag_info.gi_counts.xyz));
            }
            else
            {
                _11075 = _11067;
            }
            vec3 mp_copy_24869 = vec3(0.0);
            highp float _11076 = _11075 ? 0.0 : 1.0;
            float mp_copy_11076 = _11076;
            vec3 _11082 = max(mix(_10160, mp_copy_10024, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11098 = (_11059 * frag_info.gi_grid.xyz) - _10013;
            highp float _11100 = length(_11098);
            highp vec3 _24869 = vec3(0.0);
            if (_11100 > 9.9999997473787516355514526367188e-06)
            {
                _24869 = _11098 / vec3(_11100);
            }
            else
            {
                _24869 = _24770;
            }
            mp_copy_24869 = _24869;
            float _11118 = pow((dot(_24869, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11243 = _11059 - (frag_info.gi_counts.xyz * floor(_11059 / frag_info.gi_counts.xyz));
            highp float _11259 = _11243.x + (frag_info.gi_counts.x * (_11243.y + (frag_info.gi_counts.y * _11243.z)));
            float _24874 = 0.0;
            if (_10211)
            {
                highp float _11267 = floor(_11259 / frag_info.gi_counts.w);
                highp vec2 _11281 = vec2((_11259 - (_11267 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11267 * 16.0));
                vec3 _11141 = -mp_copy_24869;
                vec3 _11329 = _11141 / vec3((abs(_11141.x) + abs(_11141.y)) + abs(_11141.z));
                vec2 _24870 = vec2(0.0);
                if (_11329.z >= 0.0)
                {
                    _24870 = _11329.xy;
                }
                else
                {
                    _24870 = (vec2(1.0) - abs(_11329.yx)) * vec2((_11329.x >= 0.0) ? 1.0 : (-1.0), (_11329.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11145 = texture(irradiance_field, clamp((_11281 + vec2(1.0)) + (clamp((_24870 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11281 + vec2(0.5), _11281 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11150 = _11145.x * frag_info.gi_visibility.z;
                highp float _11162 = abs((_11150 * _11150) - ((_11145.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11168 = (_11100 - _11150) - frag_info.gi_visibility.y;
                highp float _24871 = 0.0;
                if (_11168 <= 0.0)
                {
                    _24871 = 1.0;
                }
                else
                {
                    _24871 = _11162 / (_11162 + (_11168 * _11168));
                }
                _24874 = _11118 * mix(1.0, max(0.0500000007450580596923828125, (_24871 * _24871) * _24871), frag_info.gi_visibility.x);
            }
            else
            {
                _24874 = _11118;
            }
            float _11196 = max(9.9999999747524270787835121154785e-07, _24874);
            float _24875 = 0.0;
            if (_11196 < 0.20000000298023223876953125)
            {
                _24875 = _11196 * ((_11196 * _11196) * 25.0);
            }
            else
            {
                _24875 = _11196;
            }
            float _11211 = _24875 * (((_11082.x * _11082.y) * _11082.z) * mp_copy_11076);
            highp float _11370 = floor(_11259 / frag_info.gi_counts.w);
            highp vec2 _11384 = vec2((_11259 - (_11370 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11370 * 8.0));
            vec2 _24876 = vec2(0.0);
            if (_10517)
            {
                _24876 = _10514.xy;
            }
            else
            {
                _24876 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11223 = texture(irradiance_field, clamp((_11384 + vec2(1.0)) + (clamp((_24876 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11384 + vec2(0.5), _11384 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11518 = _10018 + vec3(1.0, 1.0, 0.0);
            highp vec3 _11523 = _11518 - frag_info.gi_anchor.xyz;
            bool _11526 = any(lessThan(_11523, vec3(0.0)));
            bool _11534 = false;
            if (!_11526)
            {
                _11534 = any(greaterThanEqual(_11523, frag_info.gi_counts.xyz));
            }
            else
            {
                _11534 = _11526;
            }
            vec3 mp_copy_24878 = vec3(0.0);
            highp float _11535 = _11534 ? 0.0 : 1.0;
            float mp_copy_11535 = _11535;
            vec3 _11541 = max(mix(_10160, mp_copy_10024, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11557 = (_11518 * frag_info.gi_grid.xyz) - _10013;
            highp float _11559 = length(_11557);
            highp vec3 _24878 = vec3(0.0);
            if (_11559 > 9.9999997473787516355514526367188e-06)
            {
                _24878 = _11557 / vec3(_11559);
            }
            else
            {
                _24878 = _24770;
            }
            mp_copy_24878 = _24878;
            float _11577 = pow((dot(_24878, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11702 = _11518 - (frag_info.gi_counts.xyz * floor(_11518 / frag_info.gi_counts.xyz));
            highp float _11718 = _11702.x + (frag_info.gi_counts.x * (_11702.y + (frag_info.gi_counts.y * _11702.z)));
            float _24883 = 0.0;
            if (_10211)
            {
                highp float _11726 = floor(_11718 / frag_info.gi_counts.w);
                highp vec2 _11740 = vec2((_11718 - (_11726 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11726 * 16.0));
                vec3 _11600 = -mp_copy_24878;
                vec3 _11788 = _11600 / vec3((abs(_11600.x) + abs(_11600.y)) + abs(_11600.z));
                vec2 _24879 = vec2(0.0);
                if (_11788.z >= 0.0)
                {
                    _24879 = _11788.xy;
                }
                else
                {
                    _24879 = (vec2(1.0) - abs(_11788.yx)) * vec2((_11788.x >= 0.0) ? 1.0 : (-1.0), (_11788.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11604 = texture(irradiance_field, clamp((_11740 + vec2(1.0)) + (clamp((_24879 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11740 + vec2(0.5), _11740 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11609 = _11604.x * frag_info.gi_visibility.z;
                highp float _11621 = abs((_11609 * _11609) - ((_11604.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11627 = (_11559 - _11609) - frag_info.gi_visibility.y;
                highp float _24880 = 0.0;
                if (_11627 <= 0.0)
                {
                    _24880 = 1.0;
                }
                else
                {
                    _24880 = _11621 / (_11621 + (_11627 * _11627));
                }
                _24883 = _11577 * mix(1.0, max(0.0500000007450580596923828125, (_24880 * _24880) * _24880), frag_info.gi_visibility.x);
            }
            else
            {
                _24883 = _11577;
            }
            float _11655 = max(9.9999999747524270787835121154785e-07, _24883);
            float _24884 = 0.0;
            if (_11655 < 0.20000000298023223876953125)
            {
                _24884 = _11655 * ((_11655 * _11655) * 25.0);
            }
            else
            {
                _24884 = _11655;
            }
            float _11670 = _24884 * (((_11541.x * _11541.y) * _11541.z) * mp_copy_11535);
            highp float _11829 = floor(_11718 / frag_info.gi_counts.w);
            highp vec2 _11843 = vec2((_11718 - (_11829 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11829 * 8.0));
            vec2 _24885 = vec2(0.0);
            if (_10517)
            {
                _24885 = _10514.xy;
            }
            else
            {
                _24885 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11682 = texture(irradiance_field, clamp((_11843 + vec2(1.0)) + (clamp((_24885 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11843 + vec2(0.5), _11843 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11977 = _10018 + vec3(0.0, 0.0, 1.0);
            highp vec3 _11982 = _11977 - frag_info.gi_anchor.xyz;
            bool _11985 = any(lessThan(_11982, vec3(0.0)));
            bool _11993 = false;
            if (!_11985)
            {
                _11993 = any(greaterThanEqual(_11982, frag_info.gi_counts.xyz));
            }
            else
            {
                _11993 = _11985;
            }
            vec3 mp_copy_24887 = vec3(0.0);
            highp float _11994 = _11993 ? 0.0 : 1.0;
            float mp_copy_11994 = _11994;
            vec3 _12000 = max(mix(_10160, mp_copy_10024, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12016 = (_11977 * frag_info.gi_grid.xyz) - _10013;
            highp float _12018 = length(_12016);
            highp vec3 _24887 = vec3(0.0);
            if (_12018 > 9.9999997473787516355514526367188e-06)
            {
                _24887 = _12016 / vec3(_12018);
            }
            else
            {
                _24887 = _24770;
            }
            mp_copy_24887 = _24887;
            float _12036 = pow((dot(_24887, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12161 = _11977 - (frag_info.gi_counts.xyz * floor(_11977 / frag_info.gi_counts.xyz));
            highp float _12177 = _12161.x + (frag_info.gi_counts.x * (_12161.y + (frag_info.gi_counts.y * _12161.z)));
            float _24892 = 0.0;
            if (_10211)
            {
                highp float _12185 = floor(_12177 / frag_info.gi_counts.w);
                highp vec2 _12199 = vec2((_12177 - (_12185 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12185 * 16.0));
                vec3 _12059 = -mp_copy_24887;
                vec3 _12247 = _12059 / vec3((abs(_12059.x) + abs(_12059.y)) + abs(_12059.z));
                vec2 _24888 = vec2(0.0);
                if (_12247.z >= 0.0)
                {
                    _24888 = _12247.xy;
                }
                else
                {
                    _24888 = (vec2(1.0) - abs(_12247.yx)) * vec2((_12247.x >= 0.0) ? 1.0 : (-1.0), (_12247.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12063 = texture(irradiance_field, clamp((_12199 + vec2(1.0)) + (clamp((_24888 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12199 + vec2(0.5), _12199 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12068 = _12063.x * frag_info.gi_visibility.z;
                highp float _12080 = abs((_12068 * _12068) - ((_12063.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12086 = (_12018 - _12068) - frag_info.gi_visibility.y;
                highp float _24889 = 0.0;
                if (_12086 <= 0.0)
                {
                    _24889 = 1.0;
                }
                else
                {
                    _24889 = _12080 / (_12080 + (_12086 * _12086));
                }
                _24892 = _12036 * mix(1.0, max(0.0500000007450580596923828125, (_24889 * _24889) * _24889), frag_info.gi_visibility.x);
            }
            else
            {
                _24892 = _12036;
            }
            float _12114 = max(9.9999999747524270787835121154785e-07, _24892);
            float _24893 = 0.0;
            if (_12114 < 0.20000000298023223876953125)
            {
                _24893 = _12114 * ((_12114 * _12114) * 25.0);
            }
            else
            {
                _24893 = _12114;
            }
            float _12129 = _24893 * (((_12000.x * _12000.y) * _12000.z) * mp_copy_11994);
            highp float _12288 = floor(_12177 / frag_info.gi_counts.w);
            highp vec2 _12302 = vec2((_12177 - (_12288 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12288 * 8.0));
            vec2 _24894 = vec2(0.0);
            if (_10517)
            {
                _24894 = _10514.xy;
            }
            else
            {
                _24894 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12141 = texture(irradiance_field, clamp((_12302 + vec2(1.0)) + (clamp((_24894 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12302 + vec2(0.5), _12302 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12436 = _10018 + vec3(1.0, 0.0, 1.0);
            highp vec3 _12441 = _12436 - frag_info.gi_anchor.xyz;
            bool _12444 = any(lessThan(_12441, vec3(0.0)));
            bool _12452 = false;
            if (!_12444)
            {
                _12452 = any(greaterThanEqual(_12441, frag_info.gi_counts.xyz));
            }
            else
            {
                _12452 = _12444;
            }
            vec3 mp_copy_24896 = vec3(0.0);
            highp float _12453 = _12452 ? 0.0 : 1.0;
            float mp_copy_12453 = _12453;
            vec3 _12459 = max(mix(_10160, mp_copy_10024, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12475 = (_12436 * frag_info.gi_grid.xyz) - _10013;
            highp float _12477 = length(_12475);
            highp vec3 _24896 = vec3(0.0);
            if (_12477 > 9.9999997473787516355514526367188e-06)
            {
                _24896 = _12475 / vec3(_12477);
            }
            else
            {
                _24896 = _24770;
            }
            mp_copy_24896 = _24896;
            float _12495 = pow((dot(_24896, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12620 = _12436 - (frag_info.gi_counts.xyz * floor(_12436 / frag_info.gi_counts.xyz));
            highp float _12636 = _12620.x + (frag_info.gi_counts.x * (_12620.y + (frag_info.gi_counts.y * _12620.z)));
            float _24901 = 0.0;
            if (_10211)
            {
                highp float _12644 = floor(_12636 / frag_info.gi_counts.w);
                highp vec2 _12658 = vec2((_12636 - (_12644 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12644 * 16.0));
                vec3 _12518 = -mp_copy_24896;
                vec3 _12706 = _12518 / vec3((abs(_12518.x) + abs(_12518.y)) + abs(_12518.z));
                vec2 _24897 = vec2(0.0);
                if (_12706.z >= 0.0)
                {
                    _24897 = _12706.xy;
                }
                else
                {
                    _24897 = (vec2(1.0) - abs(_12706.yx)) * vec2((_12706.x >= 0.0) ? 1.0 : (-1.0), (_12706.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12522 = texture(irradiance_field, clamp((_12658 + vec2(1.0)) + (clamp((_24897 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12658 + vec2(0.5), _12658 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12527 = _12522.x * frag_info.gi_visibility.z;
                highp float _12539 = abs((_12527 * _12527) - ((_12522.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12545 = (_12477 - _12527) - frag_info.gi_visibility.y;
                highp float _24898 = 0.0;
                if (_12545 <= 0.0)
                {
                    _24898 = 1.0;
                }
                else
                {
                    _24898 = _12539 / (_12539 + (_12545 * _12545));
                }
                _24901 = _12495 * mix(1.0, max(0.0500000007450580596923828125, (_24898 * _24898) * _24898), frag_info.gi_visibility.x);
            }
            else
            {
                _24901 = _12495;
            }
            float _12573 = max(9.9999999747524270787835121154785e-07, _24901);
            float _24902 = 0.0;
            if (_12573 < 0.20000000298023223876953125)
            {
                _24902 = _12573 * ((_12573 * _12573) * 25.0);
            }
            else
            {
                _24902 = _12573;
            }
            float _12588 = _24902 * (((_12459.x * _12459.y) * _12459.z) * mp_copy_12453);
            highp float _12747 = floor(_12636 / frag_info.gi_counts.w);
            highp vec2 _12761 = vec2((_12636 - (_12747 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12747 * 8.0));
            vec2 _24903 = vec2(0.0);
            if (_10517)
            {
                _24903 = _10514.xy;
            }
            else
            {
                _24903 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12600 = texture(irradiance_field, clamp((_12761 + vec2(1.0)) + (clamp((_24903 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12761 + vec2(0.5), _12761 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12895 = _10018 + vec3(0.0, 1.0, 1.0);
            highp vec3 _12900 = _12895 - frag_info.gi_anchor.xyz;
            bool _12903 = any(lessThan(_12900, vec3(0.0)));
            bool _12911 = false;
            if (!_12903)
            {
                _12911 = any(greaterThanEqual(_12900, frag_info.gi_counts.xyz));
            }
            else
            {
                _12911 = _12903;
            }
            vec3 mp_copy_24905 = vec3(0.0);
            highp float _12912 = _12911 ? 0.0 : 1.0;
            float mp_copy_12912 = _12912;
            vec3 _12918 = max(mix(_10160, mp_copy_10024, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12934 = (_12895 * frag_info.gi_grid.xyz) - _10013;
            highp float _12936 = length(_12934);
            highp vec3 _24905 = vec3(0.0);
            if (_12936 > 9.9999997473787516355514526367188e-06)
            {
                _24905 = _12934 / vec3(_12936);
            }
            else
            {
                _24905 = _24770;
            }
            mp_copy_24905 = _24905;
            float _12954 = pow((dot(_24905, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13079 = _12895 - (frag_info.gi_counts.xyz * floor(_12895 / frag_info.gi_counts.xyz));
            highp float _13095 = _13079.x + (frag_info.gi_counts.x * (_13079.y + (frag_info.gi_counts.y * _13079.z)));
            float _24910 = 0.0;
            if (_10211)
            {
                highp float _13103 = floor(_13095 / frag_info.gi_counts.w);
                highp vec2 _13117 = vec2((_13095 - (_13103 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13103 * 16.0));
                vec3 _12977 = -mp_copy_24905;
                vec3 _13165 = _12977 / vec3((abs(_12977.x) + abs(_12977.y)) + abs(_12977.z));
                vec2 _24906 = vec2(0.0);
                if (_13165.z >= 0.0)
                {
                    _24906 = _13165.xy;
                }
                else
                {
                    _24906 = (vec2(1.0) - abs(_13165.yx)) * vec2((_13165.x >= 0.0) ? 1.0 : (-1.0), (_13165.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12981 = texture(irradiance_field, clamp((_13117 + vec2(1.0)) + (clamp((_24906 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13117 + vec2(0.5), _13117 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12986 = _12981.x * frag_info.gi_visibility.z;
                highp float _12998 = abs((_12986 * _12986) - ((_12981.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _13004 = (_12936 - _12986) - frag_info.gi_visibility.y;
                highp float _24907 = 0.0;
                if (_13004 <= 0.0)
                {
                    _24907 = 1.0;
                }
                else
                {
                    _24907 = _12998 / (_12998 + (_13004 * _13004));
                }
                _24910 = _12954 * mix(1.0, max(0.0500000007450580596923828125, (_24907 * _24907) * _24907), frag_info.gi_visibility.x);
            }
            else
            {
                _24910 = _12954;
            }
            float _13032 = max(9.9999999747524270787835121154785e-07, _24910);
            float _24911 = 0.0;
            if (_13032 < 0.20000000298023223876953125)
            {
                _24911 = _13032 * ((_13032 * _13032) * 25.0);
            }
            else
            {
                _24911 = _13032;
            }
            float _13047 = _24911 * (((_12918.x * _12918.y) * _12918.z) * mp_copy_12912);
            highp float _13206 = floor(_13095 / frag_info.gi_counts.w);
            highp vec2 _13220 = vec2((_13095 - (_13206 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13206 * 8.0));
            vec2 _24912 = vec2(0.0);
            if (_10517)
            {
                _24912 = _10514.xy;
            }
            else
            {
                _24912 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13059 = texture(irradiance_field, clamp((_13220 + vec2(1.0)) + (clamp((_24912 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13220 + vec2(0.5), _13220 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _13354 = _10018 + vec3(1.0);
            highp vec3 _13359 = _13354 - frag_info.gi_anchor.xyz;
            bool _13362 = any(lessThan(_13359, vec3(0.0)));
            bool _13370 = false;
            if (!_13362)
            {
                _13370 = any(greaterThanEqual(_13359, frag_info.gi_counts.xyz));
            }
            else
            {
                _13370 = _13362;
            }
            vec3 mp_copy_24914 = vec3(0.0);
            highp float _13371 = _13370 ? 0.0 : 1.0;
            float mp_copy_13371 = _13371;
            vec3 _13377 = max(mp_copy_10024, vec3(0.001000000047497451305389404296875));
            highp vec3 _13393 = (_13354 * frag_info.gi_grid.xyz) - _10013;
            highp float _13395 = length(_13393);
            highp vec3 _24914 = vec3(0.0);
            if (_13395 > 9.9999997473787516355514526367188e-06)
            {
                _24914 = _13393 / vec3(_13395);
            }
            else
            {
                _24914 = _24770;
            }
            mp_copy_24914 = _24914;
            float _13413 = pow((dot(_24914, _24770) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13538 = _13354 - (frag_info.gi_counts.xyz * floor(_13354 / frag_info.gi_counts.xyz));
            highp float _13554 = _13538.x + (frag_info.gi_counts.x * (_13538.y + (frag_info.gi_counts.y * _13538.z)));
            float _24919 = 0.0;
            if (_10211)
            {
                highp float _13562 = floor(_13554 / frag_info.gi_counts.w);
                highp vec2 _13576 = vec2((_13554 - (_13562 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13562 * 16.0));
                vec3 _13436 = -mp_copy_24914;
                vec3 _13624 = _13436 / vec3((abs(_13436.x) + abs(_13436.y)) + abs(_13436.z));
                vec2 _24915 = vec2(0.0);
                if (_13624.z >= 0.0)
                {
                    _24915 = _13624.xy;
                }
                else
                {
                    _24915 = (vec2(1.0) - abs(_13624.yx)) * vec2((_13624.x >= 0.0) ? 1.0 : (-1.0), (_13624.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _13440 = texture(irradiance_field, clamp((_13576 + vec2(1.0)) + (clamp((_24915 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13576 + vec2(0.5), _13576 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _13445 = _13440.x * frag_info.gi_visibility.z;
                highp float _13457 = abs((_13445 * _13445) - ((_13440.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _13463 = (_13395 - _13445) - frag_info.gi_visibility.y;
                highp float _24916 = 0.0;
                if (_13463 <= 0.0)
                {
                    _24916 = 1.0;
                }
                else
                {
                    _24916 = _13457 / (_13457 + (_13463 * _13463));
                }
                _24919 = _13413 * mix(1.0, max(0.0500000007450580596923828125, (_24916 * _24916) * _24916), frag_info.gi_visibility.x);
            }
            else
            {
                _24919 = _13413;
            }
            float _13491 = max(9.9999999747524270787835121154785e-07, _24919);
            float _24920 = 0.0;
            if (_13491 < 0.20000000298023223876953125)
            {
                _24920 = _13491 * ((_13491 * _13491) * 25.0);
            }
            else
            {
                _24920 = _13491;
            }
            float _13506 = _24920 * (((_13377.x * _13377.y) * _13377.z) * mp_copy_13371);
            highp float _13665 = floor(_13554 / frag_info.gi_counts.w);
            highp vec2 _13679 = vec2((_13554 - (_13665 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13665 * 8.0));
            vec2 _24921 = vec2(0.0);
            if (_10517)
            {
                _24921 = _10514.xy;
            }
            else
            {
                _24921 = (vec2(1.0) - abs(_10514.yx)) * vec2((_10514.x >= 0.0) ? 1.0 : (-1.0), (_10514.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10071 = ((((((vec4(max(_10305.xyz, vec3(0.0)) * _10293, _10293) + vec4(max(_10764.xyz, vec3(0.0)) * _10752, _10752)) + vec4(max(_11223.xyz, vec3(0.0)) * _11211, _11211)) + vec4(max(_11682.xyz, vec3(0.0)) * _11670, _11670)) + vec4(max(_12141.xyz, vec3(0.0)) * _12129, _12129)) + vec4(max(_12600.xyz, vec3(0.0)) * _12588, _12588)) + vec4(max(_13059.xyz, vec3(0.0)) * _13047, _13047)) + vec4(max(texture(irradiance_field, clamp((_13679 + vec2(1.0)) + (clamp((_24921 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13679 + vec2(0.5), _13679 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _13506, _13506);
            highp float _10073 = _10071.w;
            highp vec3 _24923 = vec3(0.0);
            if (_10073 > 9.9999999747524270787835121154785e-07)
            {
                _24923 = _10071.xyz / vec3(_10073);
            }
            else
            {
                _24923 = vec3(0.0);
            }
            _25041 = mix(_8387, _24923 * _9900, vec3(_24850));
        }
        else
        {
            _25041 = _8387;
        }
        vec2 _8413 = clamp(vec2(_8325, _24823), vec2(0.0), vec2(0.9900000095367431640625));
        vec4 _8415 = texture(brdf_lut, vec2(_8413.x * 0.3333333432674407958984375, _8413.y));
        float _8419 = _8415.x;
        float _8422 = _8415.y;
        vec3 _8424 = ((_8317 + ((max(vec3(1.0 - _24823), _8317) - _8317) * pow(clamp(1.0 - _8325, 0.0, 1.0), 5.0))) * _8419) + vec3(_8422);
        float _8430 = 1.0 - (_8419 + _8422);
        vec3 _8434 = vec3(1.0) - _8317;
        vec3 _8437 = _8317 + (_8434 * vec3(0.0476190485060214996337890625));
        vec3 _8448 = ((_8424 * _8430) * _8437) / (vec3(1.0) - (_8437 * _8430));
        float _8451 = 1.0 - _7320;
        vec3 _8452 = _8222 * _8451;
        float _25779 = 0.0;
        if ((frag_info.ssao_params.y > 1.5) && _8345)
        {
            float _13787 = max(acos(clamp(exp2(((-3.321929931640625) * _24823) * _24823), 0.0, 1.0)), 0.100000001490116119384765625);
            _25779 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_24838, _8329), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _25111, 0.0, 1.0)))) + _13787) / (2.0 * _13787), 0.0, 1.0));
        }
        else
        {
            float _25780 = 0.0;
            if (frag_info.ssao_params.y > 0.5)
            {
                _25780 = clamp((pow(_8321 + _25111, exp2(((-16.0) * _24823) - 1.0)) - 1.0) + _25111, 0.0, 1.0);
            }
            else
            {
                _25780 = _25111;
            }
            _25779 = _25780;
        }
        bool _8501 = frag_info.has_directional_light > 0.5;
        float _25233 = 0.0;
        vec3 _25863 = vec3(0.0);
        if (_8501)
        {
            highp vec3 _8507 = -normalize(frag_info.directional_light_direction.xyz);
            _25863 = _8507;
            _25233 = dot(_7187, _8507);
        }
        else
        {
            _25863 = vec3(0.0);
            _25233 = 0.0;
        }
        float _8514 = clamp(_25233 * 6.666666507720947265625, 0.0, 1.0);
        bool _8523 = false;
        if (_8501)
        {
            _8523 = frag_info.casts_shadow > 0.5;
        }
        else
        {
            _8523 = _8501;
        }
        float _25470 = 0.0;
        if (_8523 && (_8514 > 0.0))
        {
            int _13908 = int(frag_info.shadow_cascade_count);
            float _14357 = max(dot(_7187, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
            float _14360 = _14357 * _14357;
            highp vec3 _14380 = v_position + (_7187 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _14360, 0.0)) / _14360, 8.0))));
            highp float _13914 = frag_info.directional_light_color.w * 0.5;
            float _25287 = 0.0;
            float _25327 = 0.0;
            if (_13908 > 0)
            {
                highp vec4 _13931 = frag_info.light_space_matrix[0] * vec4(_14380, 1.0);
                highp vec3 _13937 = _13931.xyz / vec3(_13931.w);
                highp vec2 _13940 = _13937.xy * 0.5;
                highp vec2 _13942 = _13940 + vec2(0.5);
                highp float _13949 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
                highp float _13951 = _13942.x;
                bool _13953 = _13951 < _13949;
                bool _13962 = false;
                if (!_13953)
                {
                    _13962 = _13951 > (1.0 - _13949);
                }
                else
                {
                    _13962 = _13953;
                }
                bool _13970 = false;
                if (!_13962)
                {
                    _13970 = _13942.y < _13949;
                }
                else
                {
                    _13970 = _13962;
                }
                bool _13979 = false;
                if (!_13970)
                {
                    _13979 = _13942.y > (1.0 - _13949);
                }
                else
                {
                    _13979 = _13970;
                }
                bool _13986 = false;
                if (!_13979)
                {
                    _13986 = _13937.z < 0.0;
                }
                else
                {
                    _13986 = _13979;
                }
                bool _13993 = false;
                if (!_13986)
                {
                    _13993 = _13937.z > 1.0;
                }
                else
                {
                    _13993 = _13986;
                }
                float _25288 = 0.0;
                float _25328 = 0.0;
                if (!_13993)
                {
                    highp vec2 _14388 = vec2(_13949);
                    highp vec2 _14393 = vec2(_13949 + max(_13914, 9.9999997473787516355514526367188e-05));
                    highp vec2 _14401 = vec2(0.5) - _13940;
                    highp vec2 _14403 = smoothstep(_14388, _14393, _13942) * smoothstep(_14388, _14393, _14401);
                    float _25234 = 0.0;
                    if (_13914 > 0.0)
                    {
                        _25234 = _14403.x * _14403.y;
                    }
                    else
                    {
                        _25234 = 1.0;
                    }
                    float _14002 = min(_25234, 1.0);
                    bool _14004 = _14002 > 0.0;
                    float _25329 = 0.0;
                    if (_14004)
                    {
                        highp float _14515 = _13937.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                        highp float _14521 = 1.0 / (float(_13908) + frag_info.spot_shadow_params.x);
                        highp float _14523 = frag_info.directional_light_direction.w;
                        float mp_copy_14523 = _14523;
                        float _14529 = step(0.5, mp_copy_14523) * (1.0 - step(1.5, mp_copy_14523));
                        highp float _14540 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14529);
                        float mp_copy_14540 = _14540;
                        float _14542 = cos(mp_copy_14540);
                        float _14544 = sin(mp_copy_14540);
                        highp float _25252 = 0.0;
                        if ((_14523 > 1.5) && (_14523 < 2.5))
                        {
                            highp float _14563 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _14568 = max(_14563 * _14515, frag_info.shadow_texel_size);
                            float _25242 = 0.0;
                            highp float _25243 = 0.0;
                            _25243 = 0.0;
                            _25242 = 0.0;
                            highp float _14590 = 0.0;
                            float _14593 = 0.0;
                            for (int _25241 = 0; _25241 < 9; _25243 = _14590, _25242 = _14593, _25241++)
                            {
                                vec2 _27749 = vec2(0.0);
                                do
                                {
                                    if (_25241 == 0)
                                    {
                                        _27749 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25241 == 1)
                                    {
                                        _27749 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25241 == 2)
                                    {
                                        _27749 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25241 == 3)
                                    {
                                        _27749 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25241 == 4)
                                    {
                                        _27749 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25241 == 5)
                                    {
                                        _27749 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25241 == 6)
                                    {
                                        _27749 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25241 == 7)
                                    {
                                        _27749 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25241 == 8)
                                    {
                                        _27749 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25241 == 9)
                                    {
                                        _27749 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25241 == 10)
                                    {
                                        _27749 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25241 == 11)
                                    {
                                        _27749 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25241 == 12)
                                    {
                                        _27749 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25241 == 13)
                                    {
                                        _27749 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25241 == 14)
                                    {
                                        _27749 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25241 == 15)
                                    {
                                        _27749 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27749 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _14835 = clamp(_13942 + (vec2((_27749.x * _14542) - (_27749.y * _14544), (_27749.x * _14544) + (_27749.y * _14542)) * _14568), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _14844 = _14835.y;
                                highp vec2 _14845 = vec2(_14835.x * _14521, _14844);
                                _14845.y = 1.0 - _14844;
                                highp vec4 _14852 = texture(shadow_map, _14845);
                                highp float _14853 = _14852.x;
                                highp float _14585 = step(_14853, _14515);
                                float mp_copy_14585 = _14585;
                                _14590 = _25243 + (_14853 * _14585);
                                _14593 = _25242 + mp_copy_14585;
                            }
                            highp float _25244 = 0.0;
                            if (_25242 > 0.0)
                            {
                                _25244 = _25243 / _25242;
                            }
                            else
                            {
                                _25244 = _14515;
                            }
                            _25252 = clamp(_14563 * max(_14515 - _25244, 0.0), frag_info.shadow_texel_size, _13949);
                        }
                        else
                        {
                            _25252 = _13949;
                        }
                        float _25259 = 0.0;
                        if (_14523 > 2.5)
                        {
                            highp vec2 _14881 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _14885 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _14886 = clamp(_13942 + (vec2(-0.707099974155426025390625) * _25252), _14881, _14885);
                            highp vec2 _14897 = (vec2(_14886.x, 1.0 - _14886.y) / _14881) - vec2(0.5);
                            highp vec2 _14899 = floor(_14897);
                            highp vec2 _14902 = _14897 - _14899;
                            highp vec2 _14907 = (_14899 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _14917 = vec2(_14907.x * _14521, _14907.y);
                            highp float _14921 = frag_info.shadow_texel_size * _14521;
                            highp vec2 _14924 = vec2(_14921, frag_info.shadow_texel_size);
                            highp vec2 _14933 = vec2(_14921, 0.0);
                            highp vec2 _14941 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _14970 = _14902.x;
                            highp float _14979 = mix(mix(float(_14515 <= texture(shadow_map, _14917).x), float(_14515 <= texture(shadow_map, _14917 + _14933).x), _14970), mix(float(_14515 <= texture(shadow_map, _14917 + _14941).x), float(_14515 <= texture(shadow_map, _14917 + _14924).x), _14970), _14902.y);
                            float mp_copy_14979 = _14979;
                            highp vec2 _15013 = clamp(_13942 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25252), _14881, _14885);
                            highp vec2 _15024 = (vec2(_15013.x, 1.0 - _15013.y) / _14881) - vec2(0.5);
                            highp vec2 _15026 = floor(_15024);
                            highp vec2 _15029 = _15024 - _15026;
                            highp vec2 _15034 = (_15026 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15044 = vec2(_15034.x * _14521, _15034.y);
                            highp float _15097 = _15029.x;
                            highp float _15106 = mix(mix(float(_14515 <= texture(shadow_map, _15044).x), float(_14515 <= texture(shadow_map, _15044 + _14933).x), _15097), mix(float(_14515 <= texture(shadow_map, _15044 + _14941).x), float(_14515 <= texture(shadow_map, _15044 + _14924).x), _15097), _15029.y);
                            float mp_copy_15106 = _15106;
                            highp vec2 _15140 = clamp(_13942 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25252), _14881, _14885);
                            highp vec2 _15151 = (vec2(_15140.x, 1.0 - _15140.y) / _14881) - vec2(0.5);
                            highp vec2 _15153 = floor(_15151);
                            highp vec2 _15156 = _15151 - _15153;
                            highp vec2 _15161 = (_15153 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15171 = vec2(_15161.x * _14521, _15161.y);
                            highp float _15224 = _15156.x;
                            highp float _15233 = mix(mix(float(_14515 <= texture(shadow_map, _15171).x), float(_14515 <= texture(shadow_map, _15171 + _14933).x), _15224), mix(float(_14515 <= texture(shadow_map, _15171 + _14941).x), float(_14515 <= texture(shadow_map, _15171 + _14924).x), _15224), _15156.y);
                            float mp_copy_15233 = _15233;
                            highp vec2 _15267 = clamp(_13942 + (vec2(0.707099974155426025390625) * _25252), _14881, _14885);
                            highp vec2 _15278 = (vec2(_15267.x, 1.0 - _15267.y) / _14881) - vec2(0.5);
                            highp vec2 _15280 = floor(_15278);
                            highp vec2 _15283 = _15278 - _15280;
                            highp vec2 _15288 = (_15280 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15298 = vec2(_15288.x * _14521, _15288.y);
                            highp float _15351 = _15283.x;
                            highp float _15360 = mix(mix(float(_14515 <= texture(shadow_map, _15298).x), float(_14515 <= texture(shadow_map, _15298 + _14933).x), _15351), mix(float(_14515 <= texture(shadow_map, _15298 + _14941).x), float(_14515 <= texture(shadow_map, _15298 + _14924).x), _15351), _15283.y);
                            float mp_copy_15360 = _15360;
                            _25259 = (((mp_copy_14979 + mp_copy_15106) + mp_copy_15233) + mp_copy_15360) * 0.25;
                        }
                        else
                        {
                            int _14656 = (_14529 > 0.5) ? 17 : 16;
                            float _25255 = 0.0;
                            _25255 = 0.0;
                            float _14684 = 0.0;
                            for (int _25245 = 0; _25245 < 17; _25255 = _14684, _25245++)
                            {
                                if (_25245 >= _14656)
                                {
                                    break;
                                }
                                vec2 _25246 = vec2(0.0);
                                do
                                {
                                    if (_25245 == 0)
                                    {
                                        _25246 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25245 == 1)
                                    {
                                        _25246 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25245 == 2)
                                    {
                                        _25246 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25245 == 3)
                                    {
                                        _25246 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25245 == 4)
                                    {
                                        _25246 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25245 == 5)
                                    {
                                        _25246 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25245 == 6)
                                    {
                                        _25246 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25245 == 7)
                                    {
                                        _25246 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25245 == 8)
                                    {
                                        _25246 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25245 == 9)
                                    {
                                        _25246 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25245 == 10)
                                    {
                                        _25246 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25245 == 11)
                                    {
                                        _25246 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25245 == 12)
                                    {
                                        _25246 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25245 == 13)
                                    {
                                        _25246 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25245 == 14)
                                    {
                                        _25246 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25245 == 15)
                                    {
                                        _25246 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25246 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25248 = vec2(0.0);
                                do
                                {
                                    if (_25245 < 3)
                                    {
                                        _25248 = vec2(float(_25245) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25245 < 6)
                                    {
                                        _25248 = vec2((float(_25245 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25245 < 11)
                                    {
                                        _25248 = vec2((float(_25245 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25245 < 14)
                                    {
                                        _25248 = vec2((float(_25245 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25248 = vec2(float(_25245 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _14673 = mix(_25246, _25248, vec2(_14529));
                                float _15500 = _14673.x;
                                float _15504 = _14673.y;
                                highp vec2 _15530 = clamp(_13942 + (vec2((_15500 * _14542) - (_15504 * _14544), (_15500 * _14544) + (_15504 * _14542)) * _25252), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _15540 = vec2(_15530.x * _14521, _15530.y);
                                _15540.y = 1.0 - _15530.y;
                                highp float _15552 = float(_14515 <= texture(shadow_map, _15540).x);
                                float mp_copy_15552 = _15552;
                                _14684 = _25255 + mp_copy_15552;
                            }
                            _25259 = _25255 / float(_14656);
                        }
                        bool _14697 = 0 == (_13908 - 1);
                        bool _14703 = false;
                        if (_14697)
                        {
                            _14703 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _14703 = _14697;
                        }
                        float _25260 = 0.0;
                        if (_14703)
                        {
                            highp vec2 _14710 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                            highp vec2 _14718 = smoothstep(vec2(0.0), _14710, _13942) * smoothstep(vec2(0.0), _14710, _14401);
                            _25260 = mix(1.0, _25259, _14718.x * _14718.y);
                        }
                        else
                        {
                            _25260 = _25259;
                        }
                        _25329 = _14002 * _25260;
                    }
                    else
                    {
                        _25329 = 0.0;
                    }
                    _25328 = _25329;
                    _25288 = _14004 ? _14002 : 0.0;
                }
                else
                {
                    _25328 = 0.0;
                    _25288 = 0.0;
                }
                _25327 = _25328;
                _25287 = _25288;
            }
            else
            {
                _25327 = 0.0;
                _25287 = 0.0;
            }
            float _25346 = 0.0;
            float _25386 = 0.0;
            if ((_25287 < 1.0) && (_13908 > 1))
            {
                highp vec4 _14037 = frag_info.light_space_matrix[1] * vec4(_14380, 1.0);
                highp vec3 _14043 = _14037.xyz / vec3(_14037.w);
                highp vec2 _14046 = _14043.xy * 0.5;
                highp vec2 _14048 = _14046 + vec2(0.5);
                highp float _14055 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
                highp float _14057 = _14048.x;
                bool _14059 = _14057 < _14055;
                bool _14068 = false;
                if (!_14059)
                {
                    _14068 = _14057 > (1.0 - _14055);
                }
                else
                {
                    _14068 = _14059;
                }
                bool _14076 = false;
                if (!_14068)
                {
                    _14076 = _14048.y < _14055;
                }
                else
                {
                    _14076 = _14068;
                }
                bool _14085 = false;
                if (!_14076)
                {
                    _14085 = _14048.y > (1.0 - _14055);
                }
                else
                {
                    _14085 = _14076;
                }
                bool _14092 = false;
                if (!_14085)
                {
                    _14092 = _14043.z < 0.0;
                }
                else
                {
                    _14092 = _14085;
                }
                bool _14099 = false;
                if (!_14092)
                {
                    _14099 = _14043.z > 1.0;
                }
                else
                {
                    _14099 = _14092;
                }
                float _25347 = 0.0;
                float _25387 = 0.0;
                if (!_14099)
                {
                    highp vec2 _15560 = vec2(_14055);
                    highp vec2 _15565 = vec2(_14055 + max(_13914, 9.9999997473787516355514526367188e-05));
                    highp vec2 _15573 = vec2(0.5) - _14046;
                    highp vec2 _15575 = smoothstep(_15560, _15565, _14048) * smoothstep(_15560, _15565, _15573);
                    float _25290 = 0.0;
                    if (_13914 > 0.0)
                    {
                        _25290 = _15575.x * _15575.y;
                    }
                    else
                    {
                        _25290 = 1.0;
                    }
                    float _14108 = min(_25290, 1.0 - _25287);
                    float _25348 = 0.0;
                    float _25388 = 0.0;
                    if (_14108 > 0.0)
                    {
                        highp float _15687 = _14043.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                        highp float _15693 = 1.0 / (float(_13908) + frag_info.spot_shadow_params.x);
                        highp float _15695 = frag_info.directional_light_direction.w;
                        float mp_copy_15695 = _15695;
                        float _15701 = step(0.5, mp_copy_15695) * (1.0 - step(1.5, mp_copy_15695));
                        highp float _15712 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _15701);
                        float mp_copy_15712 = _15712;
                        float _15714 = cos(mp_copy_15712);
                        float _15716 = sin(mp_copy_15712);
                        highp float _25308 = 0.0;
                        if ((_15695 > 1.5) && (_15695 < 2.5))
                        {
                            highp float _15735 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _15740 = max(_15735 * _15687, frag_info.shadow_texel_size);
                            float _25298 = 0.0;
                            highp float _25299 = 0.0;
                            _25299 = 0.0;
                            _25298 = 0.0;
                            highp float _15762 = 0.0;
                            float _15765 = 0.0;
                            for (int _25297 = 0; _25297 < 9; _25299 = _15762, _25298 = _15765, _25297++)
                            {
                                vec2 _27745 = vec2(0.0);
                                do
                                {
                                    if (_25297 == 0)
                                    {
                                        _27745 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25297 == 1)
                                    {
                                        _27745 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25297 == 2)
                                    {
                                        _27745 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25297 == 3)
                                    {
                                        _27745 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25297 == 4)
                                    {
                                        _27745 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25297 == 5)
                                    {
                                        _27745 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25297 == 6)
                                    {
                                        _27745 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25297 == 7)
                                    {
                                        _27745 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25297 == 8)
                                    {
                                        _27745 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25297 == 9)
                                    {
                                        _27745 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25297 == 10)
                                    {
                                        _27745 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25297 == 11)
                                    {
                                        _27745 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25297 == 12)
                                    {
                                        _27745 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25297 == 13)
                                    {
                                        _27745 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25297 == 14)
                                    {
                                        _27745 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25297 == 15)
                                    {
                                        _27745 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27745 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _16007 = clamp(_14048 + (vec2((_27745.x * _15714) - (_27745.y * _15716), (_27745.x * _15716) + (_27745.y * _15714)) * _15740), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _16016 = _16007.y;
                                highp vec2 _16017 = vec2((1.0 + _16007.x) * _15693, _16016);
                                _16017.y = 1.0 - _16016;
                                highp vec4 _16024 = texture(shadow_map, _16017);
                                highp float _16025 = _16024.x;
                                highp float _15757 = step(_16025, _15687);
                                float mp_copy_15757 = _15757;
                                _15762 = _25299 + (_16025 * _15757);
                                _15765 = _25298 + mp_copy_15757;
                            }
                            highp float _25300 = 0.0;
                            if (_25298 > 0.0)
                            {
                                _25300 = _25299 / _25298;
                            }
                            else
                            {
                                _25300 = _15687;
                            }
                            _25308 = clamp(_15735 * max(_15687 - _25300, 0.0), frag_info.shadow_texel_size, _14055);
                        }
                        else
                        {
                            _25308 = _14055;
                        }
                        float _25315 = 0.0;
                        if (_15695 > 2.5)
                        {
                            highp vec2 _16053 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _16057 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _16058 = clamp(_14048 + (vec2(-0.707099974155426025390625) * _25308), _16053, _16057);
                            highp vec2 _16069 = (vec2(_16058.x, 1.0 - _16058.y) / _16053) - vec2(0.5);
                            highp vec2 _16071 = floor(_16069);
                            highp vec2 _16074 = _16069 - _16071;
                            highp vec2 _16079 = (_16071 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16089 = vec2((1.0 + _16079.x) * _15693, _16079.y);
                            highp float _16093 = frag_info.shadow_texel_size * _15693;
                            highp vec2 _16096 = vec2(_16093, frag_info.shadow_texel_size);
                            highp vec2 _16105 = vec2(_16093, 0.0);
                            highp vec2 _16113 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _16142 = _16074.x;
                            highp float _16151 = mix(mix(float(_15687 <= texture(shadow_map, _16089).x), float(_15687 <= texture(shadow_map, _16089 + _16105).x), _16142), mix(float(_15687 <= texture(shadow_map, _16089 + _16113).x), float(_15687 <= texture(shadow_map, _16089 + _16096).x), _16142), _16074.y);
                            float mp_copy_16151 = _16151;
                            highp vec2 _16185 = clamp(_14048 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25308), _16053, _16057);
                            highp vec2 _16196 = (vec2(_16185.x, 1.0 - _16185.y) / _16053) - vec2(0.5);
                            highp vec2 _16198 = floor(_16196);
                            highp vec2 _16201 = _16196 - _16198;
                            highp vec2 _16206 = (_16198 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16216 = vec2((1.0 + _16206.x) * _15693, _16206.y);
                            highp float _16269 = _16201.x;
                            highp float _16278 = mix(mix(float(_15687 <= texture(shadow_map, _16216).x), float(_15687 <= texture(shadow_map, _16216 + _16105).x), _16269), mix(float(_15687 <= texture(shadow_map, _16216 + _16113).x), float(_15687 <= texture(shadow_map, _16216 + _16096).x), _16269), _16201.y);
                            float mp_copy_16278 = _16278;
                            highp vec2 _16312 = clamp(_14048 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25308), _16053, _16057);
                            highp vec2 _16323 = (vec2(_16312.x, 1.0 - _16312.y) / _16053) - vec2(0.5);
                            highp vec2 _16325 = floor(_16323);
                            highp vec2 _16328 = _16323 - _16325;
                            highp vec2 _16333 = (_16325 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16343 = vec2((1.0 + _16333.x) * _15693, _16333.y);
                            highp float _16396 = _16328.x;
                            highp float _16405 = mix(mix(float(_15687 <= texture(shadow_map, _16343).x), float(_15687 <= texture(shadow_map, _16343 + _16105).x), _16396), mix(float(_15687 <= texture(shadow_map, _16343 + _16113).x), float(_15687 <= texture(shadow_map, _16343 + _16096).x), _16396), _16328.y);
                            float mp_copy_16405 = _16405;
                            highp vec2 _16439 = clamp(_14048 + (vec2(0.707099974155426025390625) * _25308), _16053, _16057);
                            highp vec2 _16450 = (vec2(_16439.x, 1.0 - _16439.y) / _16053) - vec2(0.5);
                            highp vec2 _16452 = floor(_16450);
                            highp vec2 _16455 = _16450 - _16452;
                            highp vec2 _16460 = (_16452 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16470 = vec2((1.0 + _16460.x) * _15693, _16460.y);
                            highp float _16523 = _16455.x;
                            highp float _16532 = mix(mix(float(_15687 <= texture(shadow_map, _16470).x), float(_15687 <= texture(shadow_map, _16470 + _16105).x), _16523), mix(float(_15687 <= texture(shadow_map, _16470 + _16113).x), float(_15687 <= texture(shadow_map, _16470 + _16096).x), _16523), _16455.y);
                            float mp_copy_16532 = _16532;
                            _25315 = (((mp_copy_16151 + mp_copy_16278) + mp_copy_16405) + mp_copy_16532) * 0.25;
                        }
                        else
                        {
                            int _15828 = (_15701 > 0.5) ? 17 : 16;
                            float _25311 = 0.0;
                            _25311 = 0.0;
                            float _15856 = 0.0;
                            for (int _25301 = 0; _25301 < 17; _25311 = _15856, _25301++)
                            {
                                if (_25301 >= _15828)
                                {
                                    break;
                                }
                                vec2 _25302 = vec2(0.0);
                                do
                                {
                                    if (_25301 == 0)
                                    {
                                        _25302 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25301 == 1)
                                    {
                                        _25302 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25301 == 2)
                                    {
                                        _25302 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25301 == 3)
                                    {
                                        _25302 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25301 == 4)
                                    {
                                        _25302 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25301 == 5)
                                    {
                                        _25302 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25301 == 6)
                                    {
                                        _25302 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25301 == 7)
                                    {
                                        _25302 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25301 == 8)
                                    {
                                        _25302 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25301 == 9)
                                    {
                                        _25302 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25301 == 10)
                                    {
                                        _25302 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25301 == 11)
                                    {
                                        _25302 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25301 == 12)
                                    {
                                        _25302 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25301 == 13)
                                    {
                                        _25302 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25301 == 14)
                                    {
                                        _25302 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25301 == 15)
                                    {
                                        _25302 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25302 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25304 = vec2(0.0);
                                do
                                {
                                    if (_25301 < 3)
                                    {
                                        _25304 = vec2(float(_25301) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25301 < 6)
                                    {
                                        _25304 = vec2((float(_25301 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25301 < 11)
                                    {
                                        _25304 = vec2((float(_25301 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25301 < 14)
                                    {
                                        _25304 = vec2((float(_25301 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25304 = vec2(float(_25301 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _15845 = mix(_25302, _25304, vec2(_15701));
                                float _16672 = _15845.x;
                                float _16676 = _15845.y;
                                highp vec2 _16702 = clamp(_14048 + (vec2((_16672 * _15714) - (_16676 * _15716), (_16672 * _15716) + (_16676 * _15714)) * _25308), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _16712 = vec2((1.0 + _16702.x) * _15693, _16702.y);
                                _16712.y = 1.0 - _16702.y;
                                highp float _16724 = float(_15687 <= texture(shadow_map, _16712).x);
                                float mp_copy_16724 = _16724;
                                _15856 = _25311 + mp_copy_16724;
                            }
                            _25315 = _25311 / float(_15828);
                        }
                        bool _15869 = 1 == (_13908 - 1);
                        bool _15875 = false;
                        if (_15869)
                        {
                            _15875 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _15875 = _15869;
                        }
                        float _25316 = 0.0;
                        if (_15875)
                        {
                            highp vec2 _15882 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                            highp vec2 _15890 = smoothstep(vec2(0.0), _15882, _14048) * smoothstep(vec2(0.0), _15882, _15573);
                            _25316 = mix(1.0, _25315, _15890.x * _15890.y);
                        }
                        else
                        {
                            _25316 = _25315;
                        }
                        _25388 = _25327 + (_14108 * _25316);
                        _25348 = _25287 + _14108;
                    }
                    else
                    {
                        _25388 = _25327;
                        _25348 = _25287;
                    }
                    _25387 = _25388;
                    _25347 = _25348;
                }
                else
                {
                    _25387 = _25327;
                    _25347 = _25287;
                }
                _25386 = _25387;
                _25346 = _25347;
            }
            else
            {
                _25386 = _25327;
                _25346 = _25287;
            }
            float _25405 = 0.0;
            float _25445 = 0.0;
            if ((_25346 < 1.0) && (_13908 > 2))
            {
                highp vec4 _14143 = frag_info.light_space_matrix[2] * vec4(_14380, 1.0);
                highp vec3 _14149 = _14143.xyz / vec3(_14143.w);
                highp vec2 _14152 = _14149.xy * 0.5;
                highp vec2 _14154 = _14152 + vec2(0.5);
                highp float _14161 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
                highp float _14163 = _14154.x;
                bool _14165 = _14163 < _14161;
                bool _14174 = false;
                if (!_14165)
                {
                    _14174 = _14163 > (1.0 - _14161);
                }
                else
                {
                    _14174 = _14165;
                }
                bool _14182 = false;
                if (!_14174)
                {
                    _14182 = _14154.y < _14161;
                }
                else
                {
                    _14182 = _14174;
                }
                bool _14191 = false;
                if (!_14182)
                {
                    _14191 = _14154.y > (1.0 - _14161);
                }
                else
                {
                    _14191 = _14182;
                }
                bool _14198 = false;
                if (!_14191)
                {
                    _14198 = _14149.z < 0.0;
                }
                else
                {
                    _14198 = _14191;
                }
                bool _14205 = false;
                if (!_14198)
                {
                    _14205 = _14149.z > 1.0;
                }
                else
                {
                    _14205 = _14198;
                }
                float _25406 = 0.0;
                float _25446 = 0.0;
                if (!_14205)
                {
                    highp vec2 _16732 = vec2(_14161);
                    highp vec2 _16737 = vec2(_14161 + max(_13914, 9.9999997473787516355514526367188e-05));
                    highp vec2 _16745 = vec2(0.5) - _14152;
                    highp vec2 _16747 = smoothstep(_16732, _16737, _14154) * smoothstep(_16732, _16737, _16745);
                    float _25349 = 0.0;
                    if (_13914 > 0.0)
                    {
                        _25349 = _16747.x * _16747.y;
                    }
                    else
                    {
                        _25349 = 1.0;
                    }
                    float _14214 = min(_25349, 1.0 - _25346);
                    float _25407 = 0.0;
                    float _25447 = 0.0;
                    if (_14214 > 0.0)
                    {
                        highp float _16859 = _14149.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                        highp float _16865 = 1.0 / (float(_13908) + frag_info.spot_shadow_params.x);
                        highp float _16867 = frag_info.directional_light_direction.w;
                        float mp_copy_16867 = _16867;
                        float _16873 = step(0.5, mp_copy_16867) * (1.0 - step(1.5, mp_copy_16867));
                        highp float _16884 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16873);
                        float mp_copy_16884 = _16884;
                        float _16886 = cos(mp_copy_16884);
                        float _16888 = sin(mp_copy_16884);
                        highp float _25367 = 0.0;
                        if ((_16867 > 1.5) && (_16867 < 2.5))
                        {
                            highp float _16907 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _16912 = max(_16907 * _16859, frag_info.shadow_texel_size);
                            float _25357 = 0.0;
                            highp float _25358 = 0.0;
                            _25358 = 0.0;
                            _25357 = 0.0;
                            highp float _16934 = 0.0;
                            float _16937 = 0.0;
                            for (int _25356 = 0; _25356 < 9; _25358 = _16934, _25357 = _16937, _25356++)
                            {
                                vec2 _27741 = vec2(0.0);
                                do
                                {
                                    if (_25356 == 0)
                                    {
                                        _27741 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25356 == 1)
                                    {
                                        _27741 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25356 == 2)
                                    {
                                        _27741 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25356 == 3)
                                    {
                                        _27741 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25356 == 4)
                                    {
                                        _27741 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25356 == 5)
                                    {
                                        _27741 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25356 == 6)
                                    {
                                        _27741 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25356 == 7)
                                    {
                                        _27741 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25356 == 8)
                                    {
                                        _27741 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25356 == 9)
                                    {
                                        _27741 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25356 == 10)
                                    {
                                        _27741 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25356 == 11)
                                    {
                                        _27741 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25356 == 12)
                                    {
                                        _27741 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25356 == 13)
                                    {
                                        _27741 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25356 == 14)
                                    {
                                        _27741 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25356 == 15)
                                    {
                                        _27741 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27741 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _17179 = clamp(_14154 + (vec2((_27741.x * _16886) - (_27741.y * _16888), (_27741.x * _16888) + (_27741.y * _16886)) * _16912), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _17188 = _17179.y;
                                highp vec2 _17189 = vec2((2.0 + _17179.x) * _16865, _17188);
                                _17189.y = 1.0 - _17188;
                                highp vec4 _17196 = texture(shadow_map, _17189);
                                highp float _17197 = _17196.x;
                                highp float _16929 = step(_17197, _16859);
                                float mp_copy_16929 = _16929;
                                _16934 = _25358 + (_17197 * _16929);
                                _16937 = _25357 + mp_copy_16929;
                            }
                            highp float _25359 = 0.0;
                            if (_25357 > 0.0)
                            {
                                _25359 = _25358 / _25357;
                            }
                            else
                            {
                                _25359 = _16859;
                            }
                            _25367 = clamp(_16907 * max(_16859 - _25359, 0.0), frag_info.shadow_texel_size, _14161);
                        }
                        else
                        {
                            _25367 = _14161;
                        }
                        float _25374 = 0.0;
                        if (_16867 > 2.5)
                        {
                            highp vec2 _17225 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _17229 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _17230 = clamp(_14154 + (vec2(-0.707099974155426025390625) * _25367), _17225, _17229);
                            highp vec2 _17241 = (vec2(_17230.x, 1.0 - _17230.y) / _17225) - vec2(0.5);
                            highp vec2 _17243 = floor(_17241);
                            highp vec2 _17246 = _17241 - _17243;
                            highp vec2 _17251 = (_17243 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17261 = vec2((2.0 + _17251.x) * _16865, _17251.y);
                            highp float _17265 = frag_info.shadow_texel_size * _16865;
                            highp vec2 _17268 = vec2(_17265, frag_info.shadow_texel_size);
                            highp vec2 _17277 = vec2(_17265, 0.0);
                            highp vec2 _17285 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _17314 = _17246.x;
                            highp float _17323 = mix(mix(float(_16859 <= texture(shadow_map, _17261).x), float(_16859 <= texture(shadow_map, _17261 + _17277).x), _17314), mix(float(_16859 <= texture(shadow_map, _17261 + _17285).x), float(_16859 <= texture(shadow_map, _17261 + _17268).x), _17314), _17246.y);
                            float mp_copy_17323 = _17323;
                            highp vec2 _17357 = clamp(_14154 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25367), _17225, _17229);
                            highp vec2 _17368 = (vec2(_17357.x, 1.0 - _17357.y) / _17225) - vec2(0.5);
                            highp vec2 _17370 = floor(_17368);
                            highp vec2 _17373 = _17368 - _17370;
                            highp vec2 _17378 = (_17370 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17388 = vec2((2.0 + _17378.x) * _16865, _17378.y);
                            highp float _17441 = _17373.x;
                            highp float _17450 = mix(mix(float(_16859 <= texture(shadow_map, _17388).x), float(_16859 <= texture(shadow_map, _17388 + _17277).x), _17441), mix(float(_16859 <= texture(shadow_map, _17388 + _17285).x), float(_16859 <= texture(shadow_map, _17388 + _17268).x), _17441), _17373.y);
                            float mp_copy_17450 = _17450;
                            highp vec2 _17484 = clamp(_14154 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25367), _17225, _17229);
                            highp vec2 _17495 = (vec2(_17484.x, 1.0 - _17484.y) / _17225) - vec2(0.5);
                            highp vec2 _17497 = floor(_17495);
                            highp vec2 _17500 = _17495 - _17497;
                            highp vec2 _17505 = (_17497 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17515 = vec2((2.0 + _17505.x) * _16865, _17505.y);
                            highp float _17568 = _17500.x;
                            highp float _17577 = mix(mix(float(_16859 <= texture(shadow_map, _17515).x), float(_16859 <= texture(shadow_map, _17515 + _17277).x), _17568), mix(float(_16859 <= texture(shadow_map, _17515 + _17285).x), float(_16859 <= texture(shadow_map, _17515 + _17268).x), _17568), _17500.y);
                            float mp_copy_17577 = _17577;
                            highp vec2 _17611 = clamp(_14154 + (vec2(0.707099974155426025390625) * _25367), _17225, _17229);
                            highp vec2 _17622 = (vec2(_17611.x, 1.0 - _17611.y) / _17225) - vec2(0.5);
                            highp vec2 _17624 = floor(_17622);
                            highp vec2 _17627 = _17622 - _17624;
                            highp vec2 _17632 = (_17624 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17642 = vec2((2.0 + _17632.x) * _16865, _17632.y);
                            highp float _17695 = _17627.x;
                            highp float _17704 = mix(mix(float(_16859 <= texture(shadow_map, _17642).x), float(_16859 <= texture(shadow_map, _17642 + _17277).x), _17695), mix(float(_16859 <= texture(shadow_map, _17642 + _17285).x), float(_16859 <= texture(shadow_map, _17642 + _17268).x), _17695), _17627.y);
                            float mp_copy_17704 = _17704;
                            _25374 = (((mp_copy_17323 + mp_copy_17450) + mp_copy_17577) + mp_copy_17704) * 0.25;
                        }
                        else
                        {
                            int _17000 = (_16873 > 0.5) ? 17 : 16;
                            float _25370 = 0.0;
                            _25370 = 0.0;
                            float _17028 = 0.0;
                            for (int _25360 = 0; _25360 < 17; _25370 = _17028, _25360++)
                            {
                                if (_25360 >= _17000)
                                {
                                    break;
                                }
                                vec2 _25361 = vec2(0.0);
                                do
                                {
                                    if (_25360 == 0)
                                    {
                                        _25361 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25360 == 1)
                                    {
                                        _25361 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25360 == 2)
                                    {
                                        _25361 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25360 == 3)
                                    {
                                        _25361 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25360 == 4)
                                    {
                                        _25361 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25360 == 5)
                                    {
                                        _25361 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25360 == 6)
                                    {
                                        _25361 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25360 == 7)
                                    {
                                        _25361 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25360 == 8)
                                    {
                                        _25361 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25360 == 9)
                                    {
                                        _25361 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25360 == 10)
                                    {
                                        _25361 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25360 == 11)
                                    {
                                        _25361 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25360 == 12)
                                    {
                                        _25361 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25360 == 13)
                                    {
                                        _25361 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25360 == 14)
                                    {
                                        _25361 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25360 == 15)
                                    {
                                        _25361 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25361 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25363 = vec2(0.0);
                                do
                                {
                                    if (_25360 < 3)
                                    {
                                        _25363 = vec2(float(_25360) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25360 < 6)
                                    {
                                        _25363 = vec2((float(_25360 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25360 < 11)
                                    {
                                        _25363 = vec2((float(_25360 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25360 < 14)
                                    {
                                        _25363 = vec2((float(_25360 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25363 = vec2(float(_25360 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _17017 = mix(_25361, _25363, vec2(_16873));
                                float _17844 = _17017.x;
                                float _17848 = _17017.y;
                                highp vec2 _17874 = clamp(_14154 + (vec2((_17844 * _16886) - (_17848 * _16888), (_17844 * _16888) + (_17848 * _16886)) * _25367), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _17884 = vec2((2.0 + _17874.x) * _16865, _17874.y);
                                _17884.y = 1.0 - _17874.y;
                                highp float _17896 = float(_16859 <= texture(shadow_map, _17884).x);
                                float mp_copy_17896 = _17896;
                                _17028 = _25370 + mp_copy_17896;
                            }
                            _25374 = _25370 / float(_17000);
                        }
                        bool _17041 = 2 == (_13908 - 1);
                        bool _17047 = false;
                        if (_17041)
                        {
                            _17047 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _17047 = _17041;
                        }
                        float _25375 = 0.0;
                        if (_17047)
                        {
                            highp vec2 _17054 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                            highp vec2 _17062 = smoothstep(vec2(0.0), _17054, _14154) * smoothstep(vec2(0.0), _17054, _16745);
                            _25375 = mix(1.0, _25374, _17062.x * _17062.y);
                        }
                        else
                        {
                            _25375 = _25374;
                        }
                        _25447 = _25386 + (_14214 * _25375);
                        _25407 = _25346 + _14214;
                    }
                    else
                    {
                        _25447 = _25386;
                        _25407 = _25346;
                    }
                    _25446 = _25447;
                    _25406 = _25407;
                }
                else
                {
                    _25446 = _25386;
                    _25406 = _25346;
                }
                _25445 = _25446;
                _25405 = _25406;
            }
            else
            {
                _25445 = _25386;
                _25405 = _25346;
            }
            float _25464 = 0.0;
            float _25467 = 0.0;
            if ((_25405 < 1.0) && (_13908 > 3))
            {
                highp vec4 _14249 = frag_info.light_space_matrix[3] * vec4(_14380, 1.0);
                highp vec3 _14255 = _14249.xyz / vec3(_14249.w);
                highp vec2 _14258 = _14255.xy * 0.5;
                highp vec2 _14260 = _14258 + vec2(0.5);
                highp float _14267 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
                highp float _14269 = _14260.x;
                bool _14271 = _14269 < _14267;
                bool _14280 = false;
                if (!_14271)
                {
                    _14280 = _14269 > (1.0 - _14267);
                }
                else
                {
                    _14280 = _14271;
                }
                bool _14288 = false;
                if (!_14280)
                {
                    _14288 = _14260.y < _14267;
                }
                else
                {
                    _14288 = _14280;
                }
                bool _14297 = false;
                if (!_14288)
                {
                    _14297 = _14260.y > (1.0 - _14267);
                }
                else
                {
                    _14297 = _14288;
                }
                bool _14304 = false;
                if (!_14297)
                {
                    _14304 = _14255.z < 0.0;
                }
                else
                {
                    _14304 = _14297;
                }
                bool _14311 = false;
                if (!_14304)
                {
                    _14311 = _14255.z > 1.0;
                }
                else
                {
                    _14311 = _14304;
                }
                float _25465 = 0.0;
                float _25468 = 0.0;
                if (!_14311)
                {
                    highp vec2 _17904 = vec2(_14267);
                    highp vec2 _17909 = vec2(_14267 + max(_13914, 9.9999997473787516355514526367188e-05));
                    highp vec2 _17917 = vec2(0.5) - _14258;
                    highp vec2 _17919 = smoothstep(_17904, _17909, _14260) * smoothstep(_17904, _17909, _17917);
                    float _25408 = 0.0;
                    if (_13914 > 0.0)
                    {
                        _25408 = _17919.x * _17919.y;
                    }
                    else
                    {
                        _25408 = 1.0;
                    }
                    float _14320 = min(_25408, 1.0 - _25405);
                    float _25466 = 0.0;
                    float _25469 = 0.0;
                    if (_14320 > 0.0)
                    {
                        highp float _18031 = _14255.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                        highp float _18037 = 1.0 / (float(_13908) + frag_info.spot_shadow_params.x);
                        highp float _18039 = frag_info.directional_light_direction.w;
                        float mp_copy_18039 = _18039;
                        float _18045 = step(0.5, mp_copy_18039) * (1.0 - step(1.5, mp_copy_18039));
                        highp float _18056 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _18045);
                        float mp_copy_18056 = _18056;
                        float _18058 = cos(mp_copy_18056);
                        float _18060 = sin(mp_copy_18056);
                        highp float _25426 = 0.0;
                        if ((_18039 > 1.5) && (_18039 < 2.5))
                        {
                            highp float _18079 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _18084 = max(_18079 * _18031, frag_info.shadow_texel_size);
                            float _25416 = 0.0;
                            highp float _25417 = 0.0;
                            _25417 = 0.0;
                            _25416 = 0.0;
                            highp float _18106 = 0.0;
                            float _18109 = 0.0;
                            for (int _25415 = 0; _25415 < 9; _25417 = _18106, _25416 = _18109, _25415++)
                            {
                                vec2 _27737 = vec2(0.0);
                                do
                                {
                                    if (_25415 == 0)
                                    {
                                        _27737 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25415 == 1)
                                    {
                                        _27737 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25415 == 2)
                                    {
                                        _27737 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25415 == 3)
                                    {
                                        _27737 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25415 == 4)
                                    {
                                        _27737 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25415 == 5)
                                    {
                                        _27737 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25415 == 6)
                                    {
                                        _27737 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25415 == 7)
                                    {
                                        _27737 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25415 == 8)
                                    {
                                        _27737 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25415 == 9)
                                    {
                                        _27737 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25415 == 10)
                                    {
                                        _27737 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25415 == 11)
                                    {
                                        _27737 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25415 == 12)
                                    {
                                        _27737 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25415 == 13)
                                    {
                                        _27737 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25415 == 14)
                                    {
                                        _27737 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25415 == 15)
                                    {
                                        _27737 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27737 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _18351 = clamp(_14260 + (vec2((_27737.x * _18058) - (_27737.y * _18060), (_27737.x * _18060) + (_27737.y * _18058)) * _18084), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _18360 = _18351.y;
                                highp vec2 _18361 = vec2((3.0 + _18351.x) * _18037, _18360);
                                _18361.y = 1.0 - _18360;
                                highp vec4 _18368 = texture(shadow_map, _18361);
                                highp float _18369 = _18368.x;
                                highp float _18101 = step(_18369, _18031);
                                float mp_copy_18101 = _18101;
                                _18106 = _25417 + (_18369 * _18101);
                                _18109 = _25416 + mp_copy_18101;
                            }
                            highp float _25418 = 0.0;
                            if (_25416 > 0.0)
                            {
                                _25418 = _25417 / _25416;
                            }
                            else
                            {
                                _25418 = _18031;
                            }
                            _25426 = clamp(_18079 * max(_18031 - _25418, 0.0), frag_info.shadow_texel_size, _14267);
                        }
                        else
                        {
                            _25426 = _14267;
                        }
                        float _25433 = 0.0;
                        if (_18039 > 2.5)
                        {
                            highp vec2 _18397 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _18401 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _18402 = clamp(_14260 + (vec2(-0.707099974155426025390625) * _25426), _18397, _18401);
                            highp vec2 _18413 = (vec2(_18402.x, 1.0 - _18402.y) / _18397) - vec2(0.5);
                            highp vec2 _18415 = floor(_18413);
                            highp vec2 _18418 = _18413 - _18415;
                            highp vec2 _18423 = (_18415 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18433 = vec2((3.0 + _18423.x) * _18037, _18423.y);
                            highp float _18437 = frag_info.shadow_texel_size * _18037;
                            highp vec2 _18440 = vec2(_18437, frag_info.shadow_texel_size);
                            highp vec2 _18449 = vec2(_18437, 0.0);
                            highp vec2 _18457 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _18486 = _18418.x;
                            highp float _18495 = mix(mix(float(_18031 <= texture(shadow_map, _18433).x), float(_18031 <= texture(shadow_map, _18433 + _18449).x), _18486), mix(float(_18031 <= texture(shadow_map, _18433 + _18457).x), float(_18031 <= texture(shadow_map, _18433 + _18440).x), _18486), _18418.y);
                            float mp_copy_18495 = _18495;
                            highp vec2 _18529 = clamp(_14260 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25426), _18397, _18401);
                            highp vec2 _18540 = (vec2(_18529.x, 1.0 - _18529.y) / _18397) - vec2(0.5);
                            highp vec2 _18542 = floor(_18540);
                            highp vec2 _18545 = _18540 - _18542;
                            highp vec2 _18550 = (_18542 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18560 = vec2((3.0 + _18550.x) * _18037, _18550.y);
                            highp float _18613 = _18545.x;
                            highp float _18622 = mix(mix(float(_18031 <= texture(shadow_map, _18560).x), float(_18031 <= texture(shadow_map, _18560 + _18449).x), _18613), mix(float(_18031 <= texture(shadow_map, _18560 + _18457).x), float(_18031 <= texture(shadow_map, _18560 + _18440).x), _18613), _18545.y);
                            float mp_copy_18622 = _18622;
                            highp vec2 _18656 = clamp(_14260 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25426), _18397, _18401);
                            highp vec2 _18667 = (vec2(_18656.x, 1.0 - _18656.y) / _18397) - vec2(0.5);
                            highp vec2 _18669 = floor(_18667);
                            highp vec2 _18672 = _18667 - _18669;
                            highp vec2 _18677 = (_18669 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18687 = vec2((3.0 + _18677.x) * _18037, _18677.y);
                            highp float _18740 = _18672.x;
                            highp float _18749 = mix(mix(float(_18031 <= texture(shadow_map, _18687).x), float(_18031 <= texture(shadow_map, _18687 + _18449).x), _18740), mix(float(_18031 <= texture(shadow_map, _18687 + _18457).x), float(_18031 <= texture(shadow_map, _18687 + _18440).x), _18740), _18672.y);
                            float mp_copy_18749 = _18749;
                            highp vec2 _18783 = clamp(_14260 + (vec2(0.707099974155426025390625) * _25426), _18397, _18401);
                            highp vec2 _18794 = (vec2(_18783.x, 1.0 - _18783.y) / _18397) - vec2(0.5);
                            highp vec2 _18796 = floor(_18794);
                            highp vec2 _18799 = _18794 - _18796;
                            highp vec2 _18804 = (_18796 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18814 = vec2((3.0 + _18804.x) * _18037, _18804.y);
                            highp float _18867 = _18799.x;
                            highp float _18876 = mix(mix(float(_18031 <= texture(shadow_map, _18814).x), float(_18031 <= texture(shadow_map, _18814 + _18449).x), _18867), mix(float(_18031 <= texture(shadow_map, _18814 + _18457).x), float(_18031 <= texture(shadow_map, _18814 + _18440).x), _18867), _18799.y);
                            float mp_copy_18876 = _18876;
                            _25433 = (((mp_copy_18495 + mp_copy_18622) + mp_copy_18749) + mp_copy_18876) * 0.25;
                        }
                        else
                        {
                            int _18172 = (_18045 > 0.5) ? 17 : 16;
                            float _25429 = 0.0;
                            _25429 = 0.0;
                            float _18200 = 0.0;
                            for (int _25419 = 0; _25419 < 17; _25429 = _18200, _25419++)
                            {
                                if (_25419 >= _18172)
                                {
                                    break;
                                }
                                vec2 _25420 = vec2(0.0);
                                do
                                {
                                    if (_25419 == 0)
                                    {
                                        _25420 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25419 == 1)
                                    {
                                        _25420 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25419 == 2)
                                    {
                                        _25420 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25419 == 3)
                                    {
                                        _25420 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25419 == 4)
                                    {
                                        _25420 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25419 == 5)
                                    {
                                        _25420 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25419 == 6)
                                    {
                                        _25420 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25419 == 7)
                                    {
                                        _25420 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25419 == 8)
                                    {
                                        _25420 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25419 == 9)
                                    {
                                        _25420 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25419 == 10)
                                    {
                                        _25420 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25419 == 11)
                                    {
                                        _25420 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25419 == 12)
                                    {
                                        _25420 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25419 == 13)
                                    {
                                        _25420 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25419 == 14)
                                    {
                                        _25420 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25419 == 15)
                                    {
                                        _25420 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25420 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25422 = vec2(0.0);
                                do
                                {
                                    if (_25419 < 3)
                                    {
                                        _25422 = vec2(float(_25419) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25419 < 6)
                                    {
                                        _25422 = vec2((float(_25419 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25419 < 11)
                                    {
                                        _25422 = vec2((float(_25419 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25419 < 14)
                                    {
                                        _25422 = vec2((float(_25419 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25422 = vec2(float(_25419 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _18189 = mix(_25420, _25422, vec2(_18045));
                                float _19016 = _18189.x;
                                float _19020 = _18189.y;
                                highp vec2 _19046 = clamp(_14260 + (vec2((_19016 * _18058) - (_19020 * _18060), (_19016 * _18060) + (_19020 * _18058)) * _25426), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _19056 = vec2((3.0 + _19046.x) * _18037, _19046.y);
                                _19056.y = 1.0 - _19046.y;
                                highp float _19068 = float(_18031 <= texture(shadow_map, _19056).x);
                                float mp_copy_19068 = _19068;
                                _18200 = _25429 + mp_copy_19068;
                            }
                            _25433 = _25429 / float(_18172);
                        }
                        bool _18213 = 3 == (_13908 - 1);
                        bool _18219 = false;
                        if (_18213)
                        {
                            _18219 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _18219 = _18213;
                        }
                        float _25434 = 0.0;
                        if (_18219)
                        {
                            highp vec2 _18226 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                            highp vec2 _18234 = smoothstep(vec2(0.0), _18226, _14260) * smoothstep(vec2(0.0), _18226, _17917);
                            _25434 = mix(1.0, _25433, _18234.x * _18234.y);
                        }
                        else
                        {
                            _25434 = _25433;
                        }
                        _25469 = _25405 + _14320;
                        _25466 = _25445 + (_14320 * _25434);
                    }
                    else
                    {
                        _25469 = _25405;
                        _25466 = _25445;
                    }
                    _25468 = _25469;
                    _25465 = _25466;
                }
                else
                {
                    _25468 = _25405;
                    _25465 = _25445;
                }
                _25467 = _25468;
                _25464 = _25465;
            }
            else
            {
                _25467 = _25405;
                _25464 = _25445;
            }
            _25470 = _25464 + (1.0 - _25467);
        }
        else
        {
            _25470 = 1.0;
        }
        bool _8536 = frag_info.ssao_lighting.w > 0.5;
        bool _8542 = false;
        if (_8536)
        {
            _8542 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _8542 = _8536;
        }
        float _25621 = 0.0;
        if (_8542)
        {
            _25621 = min(_25470, _25487.y);
        }
        else
        {
            _25621 = _25470;
        }
        float _8551 = _8514 * _25621;
        highp vec3 _8564 = ((((_8448 + (_8452 * ((vec3(1.0) - _8424) - _8448))) * _25041) * _25638) + (((_8424 * (_24849 * frag_info.environment_intensity)) * 1.0) * _25779)) * mix(1.0, _8551, frag_info.radiance_blend.y);
        highp vec3 _26036 = vec3(0.0);
        if (frag_info.camera_up.w > 0.5)
        {
            _26036 = _8564 + ((_25487.xyz * _8452) * _7349);
        }
        else
        {
            _26036 = _8564;
        }
        highp vec3 _26042 = vec3(0.0);
        if (_8501)
        {
            highp vec3 _25939 = vec3(0.0);
            highp vec3 _25940 = vec3(0.0);
            do
            {
                float _19134 = max(dot(_24770, _25863), 0.0);
                highp float hp_copy_19134 = _19134;
                if (_19134 <= 0.0)
                {
                    _25940 = vec3(0.0);
                    _25939 = vec3(0.0);
                    break;
                }
                float _19140 = max(_8321, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_19140 = _19140;
                vec3 _19143 = _25863 + mp_copy_24831;
                float _19146 = dot(_19143, _19143);
                vec3 _25937 = vec3(0.0);
                vec3 _25938 = vec3(0.0);
                if (_19146 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _19154 = _19143 * inversesqrt(_19146);
                    float _25936 = 0.0;
                    do
                    {
                        float _19211 = dot(_24770, _19154);
                        if (_19211 <= 0.0)
                        {
                            _25936 = 0.0;
                            break;
                        }
                        float _19218 = _24823 * _24823;
                        vec3 _19221 = cross(_24770, _19154);
                        float _19224 = _19211 * _19218;
                        float _19233 = _19218 / (dot(_19221, _19221) + (_19224 * _19224));
                        _25936 = min((_19233 * _19233) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _19271 = _8317 + (_8434 * pow(clamp(1.0 - max(dot(_19154, _24831), 0.0), 0.0, 1.0), 5.0));
                    _25938 = (_19271 * min(_25936 * (0.5 / max(mix((2.0 * hp_copy_19134) * _19140, hp_copy_19134 + hp_copy_19140, hp_copy_24823 * hp_copy_24823), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _25937 = _19271;
                }
                else
                {
                    _25938 = vec3(0.0);
                    _25937 = _8317;
                }
                _25940 = (_25938 * frag_info.directional_light_color.xyz) * _19134;
                _25939 = (((((vec3(1.0) - _25937) * _8451) * _8222) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _19134;
                break;
            } while(false);
            _26042 = (_25939 + _25940) * _8551;
        }
        else
        {
            _26042 = vec3(0.0);
        }
        highp float _19295 = 0.0;
        highp vec2 _25941 = vec2(0.0);
        do
        {
            _19295 = frag_info.punctual_dims.x;
            if (_19295 < 0.5)
            {
                _25941 = vec2(0.0);
                break;
            }
            if (frag_info.froxel_grid.z > 0.5)
            {
                highp vec3 _19307 = v_position - frag_info.camera_position.xyz;
                highp float _19322 = dot(_19307, frag_info.camera_forward.xyz);
                highp float _19328 = max(_19322, 9.9999997473787516355514526367188e-05);
                highp vec2 _19431 = (vec3(dot(_19307, frag_info.camera_right.xyz), dot(_19307, frag_info.camera_up.xyz), _19328).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_19328, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
                highp float _19446 = float(int(((((clamp(floor((log2(max(_19322 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_19431.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_19431.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
                _25941 = vec2(texture(punctual_index, vec2((mod(_19446, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_19446 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z)).xy);
                break;
            }
            _25941 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
            break;
        } while(false);
        mediump int _8607 = int(_25941.x + 0.5);
        mediump int _8611 = int(_25941.y + 0.5);
        highp vec3 _26040 = vec3(0.0);
        _26040 = _26042;
        highp vec3 _27853 = vec3(0.0);
        for (int _25942 = 0; _25942 < _8611; _26040 = _27853, _25942++)
        {
            highp float _19479 = float(_8607 + _25942);
            highp vec4 _19497 = texture(punctual_index, vec2((mod(_19479, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_19479 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z));
            highp float _19510 = (float(int(_19497.x + 0.5)) + 0.5) / _19295;
            highp vec2 _19511 = vec2(0.0625, _19510);
            highp vec4 _19514 = texture(punctual_lights, _19511);
            highp vec4 _19531 = texture(punctual_lights, vec2(0.1875, _19510));
            highp float _8629 = _19514.w;
            highp vec3 _8631 = _19531.xyz;
            if (_8629 > 2.5)
            {
                highp vec4 _19548 = texture(punctual_lights, vec2(0.3125, _19510));
                highp vec4 _19565 = texture(punctual_lights, vec2(0.4375, _19510));
                highp vec3 _8645 = _19548.xyz * (_19548.w * 0.5);
                highp vec3 _8651 = _19565.xyz * (_19565.w * 0.5);
                highp vec3 _8653 = _19514.xyz;
                highp vec3 _8655 = _8653 - _8645;
                highp vec3 _8657 = _8655 - _8651;
                highp vec3 _8661 = _8653 + _8645;
                highp vec3 _8663 = _8661 - _8651;
                highp vec3 _8675 = _8655 + _8651;
                highp vec3 _8679 = _8653 - v_position;
                highp float _8685 = _19531.w;
                highp float _8689 = (dot(_8679, _8679) * _8685) * _8685;
                highp float _8694 = clamp(1.0 - (_8689 * _8689), 0.0, 1.0);
                float mp_copy_8694 = _8694;
                vec2 _19572 = (clamp(vec2(_24823, sqrt(1.0 - _8321)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
                float _19574 = _19572.x;
                float _19579 = _19572.y;
                vec4 _8718 = texture(brdf_lut, vec2((_19574 + 1.0) * 0.3333333432674407958984375, _19579));
                vec4 _8722 = texture(brdf_lut, vec2((_19574 + 2.0) * 0.3333333432674407958984375, _19579));
                vec3 _19622 = normalize(mp_copy_24831 - (_24770 * _8320));
                mat3 _19644 = transpose(mat3(_19622, -cross(_24770, _19622), _24770));
                mat3 _19645 = mat3(vec3(_8718.x, 0.0, _8718.y), vec3(0.0, 1.0, 0.0), vec3(_8718.z, 0.0, _8718.w)) * _19644;
                highp vec3 _19649 = _8657 - v_position;
                highp vec3 _19651 = normalize(_19645 * _19649);
                vec3 mp_copy_19651 = _19651;
                highp vec3 _19655 = _8663 - v_position;
                highp vec3 _19657 = normalize(_19645 * _19655);
                vec3 mp_copy_19657 = _19657;
                highp vec3 _19661 = (_8661 + _8651) - v_position;
                highp vec3 _19663 = normalize(_19645 * _19661);
                vec3 mp_copy_19663 = _19663;
                highp vec3 _19667 = _8675 - v_position;
                highp vec3 _19669 = normalize(_19645 * _19667);
                vec3 mp_copy_19669 = _19669;
                float _19698 = dot(_19651, _19657);
                float _19700 = abs(_19698);
                float _19714 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19700)) * _19700)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19700) * _19700));
                float _27677 = 0.0;
                if (_19698 > 0.0)
                {
                    _27677 = _19714;
                }
                else
                {
                    _27677 = (0.5 * inversesqrt(max(1.0 - (_19698 * _19698), 1.0000000116860974230803549289703e-07))) - _19714;
                }
                float _19747 = dot(_19657, _19663);
                float _19749 = abs(_19747);
                float _19763 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19749)) * _19749)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19749) * _19749));
                float _27678 = 0.0;
                if (_19747 > 0.0)
                {
                    _27678 = _19763;
                }
                else
                {
                    _27678 = (0.5 * inversesqrt(max(1.0 - (_19747 * _19747), 1.0000000116860974230803549289703e-07))) - _19763;
                }
                float _19796 = dot(_19663, _19669);
                float _19798 = abs(_19796);
                float _19812 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19798)) * _19798)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19798) * _19798));
                float _27679 = 0.0;
                if (_19796 > 0.0)
                {
                    _27679 = _19812;
                }
                else
                {
                    _27679 = (0.5 * inversesqrt(max(1.0 - (_19796 * _19796), 1.0000000116860974230803549289703e-07))) - _19812;
                }
                float _19845 = dot(_19669, _19651);
                float _19847 = abs(_19845);
                float _19861 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19847)) * _19847)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19847) * _19847));
                float _27680 = 0.0;
                if (_19845 > 0.0)
                {
                    _27680 = _19861;
                }
                else
                {
                    _27680 = (0.5 * inversesqrt(max(1.0 - (_19845 * _19845), 1.0000000116860974230803549289703e-07))) - _19861;
                }
                vec3 _19684 = (((cross(mp_copy_19651, mp_copy_19657) * _27677) + (cross(mp_copy_19657, mp_copy_19663) * _27678)) + (cross(mp_copy_19663, mp_copy_19669) * _27679)) + (cross(mp_copy_19669, mp_copy_19651) * _27680);
                float _19887 = length(_19684);
                mat3 _19947 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _19644;
                highp vec3 _19953 = normalize(_19947 * _19649);
                vec3 mp_copy_19953 = _19953;
                highp vec3 _19959 = normalize(_19947 * _19655);
                vec3 mp_copy_19959 = _19959;
                highp vec3 _19965 = normalize(_19947 * _19661);
                vec3 mp_copy_19965 = _19965;
                highp vec3 _19971 = normalize(_19947 * _19667);
                vec3 mp_copy_19971 = _19971;
                float _20000 = dot(_19953, _19959);
                float _20002 = abs(_20000);
                float _20016 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20002)) * _20002)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20002) * _20002));
                float _27681 = 0.0;
                if (_20000 > 0.0)
                {
                    _27681 = _20016;
                }
                else
                {
                    _27681 = (0.5 * inversesqrt(max(1.0 - (_20000 * _20000), 1.0000000116860974230803549289703e-07))) - _20016;
                }
                float _20049 = dot(_19959, _19965);
                float _20051 = abs(_20049);
                float _20065 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20051)) * _20051)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20051) * _20051));
                float _27682 = 0.0;
                if (_20049 > 0.0)
                {
                    _27682 = _20065;
                }
                else
                {
                    _27682 = (0.5 * inversesqrt(max(1.0 - (_20049 * _20049), 1.0000000116860974230803549289703e-07))) - _20065;
                }
                float _20098 = dot(_19965, _19971);
                float _20100 = abs(_20098);
                float _20114 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20100)) * _20100)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20100) * _20100));
                float _27683 = 0.0;
                if (_20098 > 0.0)
                {
                    _27683 = _20114;
                }
                else
                {
                    _27683 = (0.5 * inversesqrt(max(1.0 - (_20098 * _20098), 1.0000000116860974230803549289703e-07))) - _20114;
                }
                float _20147 = dot(_19971, _19953);
                float _20149 = abs(_20147);
                float _20163 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20149)) * _20149)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20149) * _20149));
                float _27684 = 0.0;
                if (_20147 > 0.0)
                {
                    _27684 = _20163;
                }
                else
                {
                    _27684 = (0.5 * inversesqrt(max(1.0 - (_20147 * _20147), 1.0000000116860974230803549289703e-07))) - _20163;
                }
                vec3 _19986 = (((cross(mp_copy_19953, mp_copy_19959) * _27681) + (cross(mp_copy_19959, mp_copy_19965) * _27682)) + (cross(mp_copy_19965, mp_copy_19971) * _27683)) + (cross(mp_copy_19971, mp_copy_19953) * _27684);
                float _20189 = length(_19986);
                _27853 = _26040 + (((_8631 * (mp_copy_8694 * mp_copy_8694)) * step(0.0, dot(cross(_8663 - _8657, _8675 - _8657), v_position - _8657))) * (((((_8317 * _8722.x) + (_8434 * _8722.y)) * max(((_19887 * _19887) + _19684.z) / (_19887 + 1.0), 0.0)) * 1.0) + (_8452 * max(((_20189 * _20189) + _19986.z) / (_20189 + 1.0), 0.0))));
            }
            else
            {
                highp float hp_copy_27621 = 0.0;
                vec3 _27594 = vec3(0.0);
                highp vec3 _27617 = vec3(0.0);
                float _27621 = 0.0;
                if (_8629 < 0.5)
                {
                    _27621 = _24823;
                    _27617 = _8631;
                    _27594 = -normalize(texture(punctual_lights, vec2(0.3125, _19510)).xyz);
                }
                else
                {
                    highp vec3 _8809 = _19514.xyz - v_position;
                    highp float _8812 = dot(_8809, _8809);
                    highp float _8816 = inversesqrt(max(_8812, 9.9999999392252902907785028219223e-09));
                    highp vec3 _8817 = _8809 * _8816;
                    vec3 mp_copy_8817 = _8817;
                    highp float _8819 = _19531.w;
                    highp float _8824 = (_8812 * _8819) * _8819;
                    highp float _8829 = clamp(1.0 - (_8824 * _8824), 0.0, 1.0);
                    float mp_copy_8829 = _8829;
                    highp vec4 _20233 = texture(punctual_lights, vec2(0.4375, _19510));
                    highp float _8833 = _20233.w;
                    float _27625 = 0.0;
                    if (_8833 > 0.0)
                    {
                        highp float _8860 = (_24823 * _24823) + ((_8833 * 0.5) * _8816);
                        float mp_copy_8860 = _8860;
                        _27625 = sqrt(min(mp_copy_8860, 1.0));
                    }
                    else
                    {
                        _27625 = _24823;
                    }
                    highp vec3 _8867 = _8631 * ((mp_copy_8829 * mp_copy_8829) / max(pow(max(_8812, _8833 * _8833), _20233.z * 0.5), 9.9999997473787516355514526367188e-05));
                    highp vec3 _27618 = vec3(0.0);
                    if (_8629 > 1.5)
                    {
                        highp vec4 _20250 = texture(punctual_lights, vec2(0.3125, _19510));
                        highp float _8886 = clamp((dot(normalize(_20250.xyz), -mp_copy_8817) * _20250.w) + _20233.x, 0.0, 1.0);
                        float mp_copy_8886 = _8886;
                        highp vec3 _8891 = _8867 * (mp_copy_8886 * mp_copy_8886);
                        highp float _8893 = _20233.y;
                        bool _8894 = _8893 > (-0.5);
                        bool _8900 = false;
                        if (_8894)
                        {
                            _8900 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8900 = _8894;
                        }
                        highp vec3 _27619 = vec3(0.0);
                        if (_8900)
                        {
                            float _27585 = 0.0;
                            do
                            {
                                highp vec4 _20473 = texture(punctual_lights, vec2(0.5625, _19510));
                                highp vec4 _20490 = texture(punctual_lights, vec2(0.6875, _19510));
                                highp vec4 _20507 = texture(punctual_lights, vec2(0.8125, _19510));
                                highp vec4 _20524 = texture(punctual_lights, vec2(0.9375, _19510));
                                highp vec4 _20335 = mat4(_20473, _20490, _20507, _20524) * vec4(v_position + (_7187 * frag_info.spot_shadow_params.z), 1.0);
                                highp float _20337 = _20335.w;
                                if (_20337 <= 0.0)
                                {
                                    _27585 = 1.0;
                                    break;
                                }
                                highp vec3 _20346 = _20335.xyz / vec3(_20337);
                                highp vec2 _20351 = (_20346.xy * 0.5) + vec2(0.5);
                                highp float _20353 = _20351.x;
                                bool _20354 = _20353 < 0.0;
                                bool _20361 = false;
                                if (!_20354)
                                {
                                    _20361 = _20353 > 1.0;
                                }
                                else
                                {
                                    _20361 = _20354;
                                }
                                bool _20368 = false;
                                if (!_20361)
                                {
                                    _20368 = _20351.y < 0.0;
                                }
                                else
                                {
                                    _20368 = _20361;
                                }
                                bool _20375 = false;
                                if (!_20368)
                                {
                                    _20375 = _20351.y > 1.0;
                                }
                                else
                                {
                                    _20375 = _20368;
                                }
                                bool _20382 = false;
                                if (!_20375)
                                {
                                    _20382 = _20346.z < 0.0;
                                }
                                else
                                {
                                    _20382 = _20375;
                                }
                                bool _20389 = false;
                                if (!_20382)
                                {
                                    _20389 = _20346.z > 1.0;
                                }
                                else
                                {
                                    _20389 = _20382;
                                }
                                if (_20389)
                                {
                                    _27585 = 1.0;
                                    break;
                                }
                                highp float _20396 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                highp float _20401 = frag_info.shadow_cascade_count + float(int(_8893 + 0.5));
                                highp float _20406 = _20346.z - frag_info.spot_shadow_params.y;
                                highp float _20409 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                                highp float _20422 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27584 = 0.0;
                                _27584 = float(_20406 <= texture(shadow_map, vec2((_20401 + clamp(_20353, 0.0, 1.0)) / _20396, 1.0 - clamp(_20351.y, 0.0, 1.0))).x);
                                for (int _27583 = 0; _27583 < 8; )
                                {
                                    highp float _20432 = _20422 + (float(_27583) * 0.785398185253143310546875);
                                    float mp_copy_20432 = _20432;
                                    highp vec2 _20442 = _20351 + (vec2(cos(mp_copy_20432), sin(mp_copy_20432)) * _20409);
                                    highp float _20568 = float(_20406 <= texture(shadow_map, vec2((_20401 + clamp(_20442.x, 0.0, 1.0)) / _20396, 1.0 - clamp(_20442.y, 0.0, 1.0))).x);
                                    float mp_copy_20568 = _20568;
                                    _27584 += mp_copy_20568;
                                    _27583++;
                                    continue;
                                }
                                _27585 = _27584 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27619 = _8891 * _27585;
                        }
                        else
                        {
                            _27619 = _8891;
                        }
                        _27618 = _27619;
                    }
                    else
                    {
                        bool _8916 = _8629 > 0.5;
                        bool _8922 = false;
                        if (_8916)
                        {
                            _8922 = _20233.y > (-0.5);
                        }
                        else
                        {
                            _8922 = _8916;
                        }
                        bool _8928 = false;
                        if (_8922)
                        {
                            _8928 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8928 = _8922;
                        }
                        highp vec3 _27620 = vec3(0.0);
                        if (_8928)
                        {
                            float _27570 = 0.0;
                            do
                            {
                                highp vec4 _20881 = texture(punctual_lights, vec2(0.5625, _19510));
                                highp vec4 _20898 = texture(punctual_lights, vec2(0.6875, _19510));
                                highp vec4 _20915 = texture(punctual_lights, _19511);
                                highp vec3 _20640 = (v_position + (_7187 * _20881.z)) - _20915.xyz;
                                highp vec3 _20642 = abs(_20640);
                                highp float _20644 = _20642.x;
                                highp float _20646 = _20642.y;
                                bool _20647 = _20644 >= _20646;
                                bool _20655 = false;
                                if (_20647)
                                {
                                    _20655 = _20644 >= _20642.z;
                                }
                                else
                                {
                                    _20655 = _20647;
                                }
                                highp vec3 _27560 = vec3(0.0);
                                float _27562 = 0.0;
                                if (_20655)
                                {
                                    highp float _20658 = _20640.x;
                                    bool _20659 = _20658 >= 0.0;
                                    highp vec3 _27559 = vec3(0.0);
                                    if (_20659)
                                    {
                                        _27559 = vec3(-_20640.z, _20640.y, _20658);
                                    }
                                    else
                                    {
                                        _27559 = vec3(_20640.zy, -_20658);
                                    }
                                    _27562 = _20659 ? 0.0 : 1.0;
                                    _27560 = _27559;
                                }
                                else
                                {
                                    highp vec3 _27561 = vec3(0.0);
                                    float _27564 = 0.0;
                                    if (_20646 >= _20642.z)
                                    {
                                        highp float _20692 = _20640.y;
                                        bool _20693 = _20692 >= 0.0;
                                        highp vec3 _27558 = vec3(0.0);
                                        if (_20693)
                                        {
                                            _27558 = vec3(-_20640.x, _20640.z, _20692);
                                        }
                                        else
                                        {
                                            _27558 = vec3(_20640.xz, -_20692);
                                        }
                                        _27564 = _20693 ? 2.0 : 3.0;
                                        _27561 = _27558;
                                    }
                                    else
                                    {
                                        highp float _20720 = _20640.z;
                                        bool _20721 = _20720 >= 0.0;
                                        highp vec3 _27557 = vec3(0.0);
                                        if (_20721)
                                        {
                                            _27557 = _20640;
                                        }
                                        else
                                        {
                                            _27557 = vec3(-_20640.x, _20640.y, -_20720);
                                        }
                                        _27564 = _20721 ? 4.0 : 5.0;
                                        _27561 = _27557;
                                    }
                                    _27562 = _27564;
                                    _27560 = _27561;
                                }
                                if (_27560.z <= 0.0)
                                {
                                    _27570 = 1.0;
                                    break;
                                }
                                highp vec2 _20761 = ((_27560.xy / vec2(_27560.z)) * 0.5) + vec2(0.5);
                                highp float _20772 = (_20881.x - (_20881.y / _27560.z)) - _20898.x;
                                if ((_20772 < 0.0) || (_20772 > 1.0))
                                {
                                    _27570 = 1.0;
                                    break;
                                }
                                highp float hp_copy_27567 = 0.0;
                                highp float _20784 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                bool _20790 = _27562 >= 4.0;
                                highp float _20792 = (frag_info.shadow_cascade_count + _20233.y) + float(_20790);
                                float _27567 = 0.0;
                                if (_20790)
                                {
                                    _27567 = _27562 - 4.0;
                                }
                                else
                                {
                                    _27567 = _27562;
                                }
                                hp_copy_27567 = _27567;
                                highp float _20809 = _20898.y * 0.5;
                                highp float _20812 = _20881.w * 0.0040000001899898052215576171875;
                                highp vec2 _20923 = vec2(_20809);
                                highp vec2 _20926 = vec2(1.0 - _20809);
                                highp vec2 _20932 = vec2(mod(hp_copy_27567, 2.0), 1.0 - floor(hp_copy_27567 * 0.5)) * 0.5;
                                highp vec2 _20935 = _20932 + (clamp(_20761, _20923, _20926) * 0.5);
                                highp float _20828 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27569 = 0.0;
                                _27569 = float(_20772 <= texture(shadow_map, vec2((_20792 + _20935.x) / _20784, 1.0 - _20935.y)).x);
                                for (int _27568 = 0; _27568 < 8; )
                                {
                                    highp float _20838 = _20828 + (float(_27568) * 0.785398185253143310546875);
                                    float mp_copy_20838 = _20838;
                                    highp vec2 _20972 = _20932 + (clamp(_20761 + (vec2(cos(mp_copy_20838), sin(mp_copy_20838)) * _20812), _20923, _20926) * 0.5);
                                    highp float _20989 = float(_20772 <= texture(shadow_map, vec2((_20792 + _20972.x) / _20784, 1.0 - _20972.y)).x);
                                    float mp_copy_20989 = _20989;
                                    _27569 += mp_copy_20989;
                                    _27568++;
                                    continue;
                                }
                                _27570 = _27569 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27620 = _8867 * _27570;
                        }
                        else
                        {
                            _27620 = _8867;
                        }
                        _27618 = _27620;
                    }
                    _27621 = _27625;
                    _27617 = _27618;
                    _27594 = _8817;
                }
                hp_copy_27621 = _27621;
                highp vec3 _27648 = vec3(0.0);
                highp vec3 _27649 = vec3(0.0);
                do
                {
                    float _21055 = max(dot(_24770, _27594), 0.0);
                    highp float hp_copy_21055 = _21055;
                    if (_21055 <= 0.0)
                    {
                        _27649 = vec3(0.0);
                        _27648 = vec3(0.0);
                        break;
                    }
                    float _21061 = max(_8321, 9.9999997473787516355514526367188e-05);
                    highp float hp_copy_21061 = _21061;
                    vec3 _21064 = _27594 + mp_copy_24831;
                    float _21067 = dot(_21064, _21064);
                    vec3 _27646 = vec3(0.0);
                    vec3 _27647 = vec3(0.0);
                    if (_21067 > 9.9999999392252902907785028219223e-09)
                    {
                        vec3 _21075 = _21064 * inversesqrt(_21067);
                        float _27645 = 0.0;
                        do
                        {
                            float _21132 = dot(_24770, _21075);
                            if (_21132 <= 0.0)
                            {
                                _27645 = 0.0;
                                break;
                            }
                            float _21139 = _27621 * _27621;
                            vec3 _21142 = cross(_24770, _21075);
                            float _21145 = _21132 * _21139;
                            float _21154 = _21139 / (dot(_21142, _21142) + (_21145 * _21145));
                            _27645 = min((_21154 * _21154) * 0.3183098733425140380859375, 65504.0);
                            break;
                        } while(false);
                        vec3 _21192 = _8317 + (_8434 * pow(clamp(1.0 - max(dot(_21075, _24831), 0.0), 0.0, 1.0), 5.0));
                        _27647 = (_21192 * min(_27645 * (0.5 / max(mix((2.0 * hp_copy_21055) * _21061, hp_copy_21055 + hp_copy_21061, hp_copy_27621 * hp_copy_27621), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                        _27646 = _21192;
                    }
                    else
                    {
                        _27647 = vec3(0.0);
                        _27646 = _8317;
                    }
                    _27649 = (_27647 * _27617) * _21055;
                    _27648 = (((((vec3(1.0) - _27646) * _8451) * _8222) * 0.3183098733425140380859375) * _27617) * _21055;
                    break;
                } while(false);
                _27853 = _26040 + (_27648 + _27649);
            }
        }
        bool _8985 = _FogInfo.params0.y > 0.5;
        bool _8991 = false;
        if (_8985)
        {
            _8991 = _FogInfo.params0.w > 0.0;
        }
        else
        {
            _8991 = _8985;
        }
        highp vec3 _26047 = vec3(0.0);
        if (_8991)
        {
            vec3 mp_copy_26043 = vec3(0.0);
            highp vec3 _26043 = vec3(0.0);
            if (_9158)
            {
                _26043 = -view_info.camera_forward.xyz;
            }
            else
            {
                _26043 = normalize(v_viewvector);
            }
            mp_copy_26043 = _26043;
            vec3 _8996 = _8342 * (-mp_copy_26043);
            vec3 _26044 = vec3(0.0);
            do
            {
                if (_9472)
                {
                    vec2 _21314 = vec2(atan(_8996.z, _8996.x), asin(clamp(_8996.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21314 = _21314;
                    _26044 = textureLod(prefiltered_radiance, (hp_copy_21314 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _21333 = vec2(atan(_8996.z, _8996.x), asin(clamp(_8996.y, -1.0, 1.0)));
                highp vec2 hp_copy_21333 = _21333;
                highp vec2 _21338 = (hp_copy_21333 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _21245 = clamp(_21338.y, 0.00390625, 0.99609375);
                float _21251 = floor(0.0);
                highp float _21270 = _21338.x;
                _26044 = mix(texture(prefiltered_radiance, vec2(_21270, (_21251 + _21245) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_21270, (min(_21251 + 1.0, 7.0) + _21245) * 0.125)).xyz, vec3(-_21251));
                break;
            } while(false);
            highp vec3 _26046 = vec3(0.0);
            if (_8365)
            {
                vec3 _26045 = vec3(0.0);
                do
                {
                    if (_9472)
                    {
                        vec2 _21443 = vec2(atan(_8996.z, _8996.x), asin(clamp(_8996.y, -1.0, 1.0)));
                        highp vec2 hp_copy_21443 = _21443;
                        _26045 = textureLod(prefiltered_radiance_b, (hp_copy_21443 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                        break;
                    }
                    vec2 _21462 = vec2(atan(_8996.z, _8996.x), asin(clamp(_8996.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21462 = _21462;
                    highp vec2 _21467 = (hp_copy_21462 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _21374 = clamp(_21467.y, 0.00390625, 0.99609375);
                    float _21380 = floor(0.0);
                    highp float _21399 = _21467.x;
                    _26045 = mix(texture(prefiltered_radiance_b, vec2(_21399, (_21380 + _21374) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_21399, (min(_21380 + 1.0, 7.0) + _21374) * 0.125)).xyz, vec3(-_21380));
                    break;
                } while(false);
                _26046 = mix(_26044, _26045, vec3(frag_info.radiance_blend.x));
            }
            else
            {
                _26046 = _26044;
            }
            _26047 = _26046 * frag_info.environment_intensity;
        }
        else
        {
            _26047 = _FogInfo.color.xyz;
        }
        highp vec4 _9020 = vec4(min((_26036 + (_26040 * mix(1.0, _25111, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7373, vec3(65504.0)), 1.0) * _28247;
        highp vec4 _26062 = vec4(0.0);
        do
        {
            if (_FogInfo.params0.y < 0.5)
            {
                _26062 = _9020;
                break;
            }
            int _21511 = int(_FogInfo.params0.x + 0.5);
            if (_21511 == 0)
            {
                _26062 = _9020;
                break;
            }
            highp float _26049 = 0.0;
            if (_9158)
            {
                _26049 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
            }
            else
            {
                _26049 = length(v_viewvector);
            }
            if ((_FogInfo.params1.w > 0.0) && (_26049 > _FogInfo.params1.w))
            {
                _26062 = _9020;
                break;
            }
            float _26053 = 0.0;
            if (_21511 == 1)
            {
                _26053 = clamp((_26049 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
            }
            else
            {
                float _26054 = 0.0;
                if (_21511 == 2)
                {
                    highp float _26052 = 0.0;
                    if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                    {
                        highp vec3 _26050 = vec3(0.0);
                        if (_9158)
                        {
                            _26050 = v_position - (view_info.camera_forward.xyz * _26049);
                        }
                        else
                        {
                            _26050 = v_position + v_viewvector;
                        }
                        highp float _21592 = -_FogInfo.params2.y;
                        highp float _21599 = _FogInfo.params1.x * exp(_21592 * (_26050.y - _FogInfo.params2.x));
                        highp float _21616 = _FogInfo.params2.y * (v_position.y - _26050.y);
                        highp float _26051 = 0.0;
                        if (abs(_21616) > 0.00124999997206032276153564453125)
                        {
                            _26051 = (_21599 - (_FogInfo.params1.x * exp(_21592 * (v_position.y - _FogInfo.params2.x)))) / _21616;
                        }
                        else
                        {
                            _26051 = _21599;
                        }
                        _26052 = _26051 * max(_26049 - _FogInfo.params1.y, 0.0);
                    }
                    else
                    {
                        _26052 = _FogInfo.params1.x * max(_26049 - _FogInfo.params1.y, 0.0);
                    }
                    _26054 = 1.0 - exp(-_26052);
                }
                else
                {
                    highp float _21654 = _FogInfo.params1.x * max(_26049 - _FogInfo.params1.y, 0.0);
                    _26054 = 1.0 - exp((-_21654) * _21654);
                }
                _26053 = _26054;
            }
            highp float _21666 = min(_26053, _FogInfo.params0.z);
            if (_21666 <= 0.0)
            {
                _26062 = _9020;
                break;
            }
            highp vec3 _21679 = mix(_FogInfo.color.xyz, _26047, vec3(_FogInfo.params0.w));
            bool _21682 = _FogInfo.sun.w > 0.5;
            bool _21688 = false;
            if (_21682)
            {
                _21688 = _FogInfo.params2.z > 0.0;
            }
            else
            {
                _21688 = _21682;
            }
            vec3 _26058 = vec3(0.0);
            if (_21688)
            {
                vec3 mp_copy_26055 = vec3(0.0);
                highp vec3 _26055 = vec3(0.0);
                if (_9158)
                {
                    _26055 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _26055 = normalize(v_viewvector);
                }
                mp_copy_26055 = _26055;
                highp float _21704 = pow(max(dot(-mp_copy_26055, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                float mp_copy_21704 = _21704;
                _26058 = _21679 + ((_FogInfo.sun.xyz * mp_copy_21704) * _FogInfo.params2.z);
            }
            else
            {
                _26058 = _21679;
            }
            highp float _21717 = _9020.w;
            float mp_copy_21717 = _21717;
            _26062 = vec4(mix(_9020.xyz, _26058 * mp_copy_21717, vec3(_21666)), _21717);
            break;
        } while(false);
        _27479 = _26062;
    }
    else
    {
        _27479 = vec4(0.0);
    }
    float _27482 = 0.0;
    do
    {
        if (_7996)
        {
            _27482 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _27482 = 1.0;
            break;
        }
        _27482 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    bool _21767 = gl_FragCoord.x >= debug_view_info.view.y;
    bool _21769 = _27482 > 0.5;
    vec4 _27554 = vec4(0.0);
    if (_21769)
    {
        bool _21775 = (_27482 > 2.5) && (!_21767);
        vec4 _27483 = vec4(0.0);
        if (_21775)
        {
            _27483 = vec4(debug_view_info.left.x, debug_view_info.view.y, debug_view_info.left.y, debug_view_info.view.w);
        }
        else
        {
            _27483 = debug_view_info.view;
        }
        vec2 _27484 = vec2(0.0);
        if (_21775)
        {
            _27484 = debug_view_info.left.zw;
        }
        else
        {
            _27484 = debug_view_info.params.xy;
        }
        vec4 _27552 = vec4(0.0);
        do
        {
            if (_27483.x < 20.0)
            {
                vec3 _27538 = vec3(0.0);
                if (_27483.x == 1.0)
                {
                    float _22252 = length(_7187);
                    vec3 _27537 = vec3(0.0);
                    if (_22252 > 9.9999999747524270787835121154785e-07)
                    {
                        _27537 = _7187 / vec3(_22252);
                    }
                    else
                    {
                        _27537 = vec3(0.0);
                    }
                    _27538 = ((_27537 * 0.5) + vec3(0.5)) * _27483.z;
                }
                else
                {
                    vec3 _27539 = vec3(0.0);
                    if (_27483.x == 2.0)
                    {
                        float _22275 = length(_24770);
                        vec3 _27536 = vec3(0.0);
                        if (_22275 > 9.9999999747524270787835121154785e-07)
                        {
                            _27536 = _24770 / vec3(_22275);
                        }
                        else
                        {
                            _27536 = vec3(0.0);
                        }
                        _27539 = ((_27536 * 0.5) + vec3(0.5)) * _27483.z;
                    }
                    else
                    {
                        vec3 _27540 = vec3(0.0);
                        if (_27483.x == 3.0)
                        {
                            float _22298 = length(v_tangent.xyz);
                            vec3 _27535 = vec3(0.0);
                            if (_22298 > 9.9999999747524270787835121154785e-07)
                            {
                                _27535 = v_tangent.xyz / vec3(_22298);
                            }
                            else
                            {
                                _27535 = vec3(0.0);
                            }
                            _27540 = ((_27535 * 0.5) + vec3(0.5)) * _27483.z;
                        }
                        else
                        {
                            vec3 _27541 = vec3(0.0);
                            if (_27483.x == 4.0)
                            {
                                highp float _21931 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_21931 = _21931;
                                vec3 _21932 = cross(_7185, v_tangent.xyz) * mp_copy_21931;
                                float _22321 = length(_21932);
                                vec3 _27534 = vec3(0.0);
                                if (_22321 > 9.9999999747524270787835121154785e-07)
                                {
                                    _27534 = _21932 / vec3(_22321);
                                }
                                else
                                {
                                    _27534 = vec3(0.0);
                                }
                                _27541 = ((_27534 * 0.5) + vec3(0.5)) * _27483.z;
                            }
                            else
                            {
                                vec3 _27542 = vec3(0.0);
                                if (_27483.x == 5.0)
                                {
                                    _27542 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _27543 = vec3(0.0);
                                    if (_27483.x == 6.0)
                                    {
                                        _27543 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * _27483.z;
                                    }
                                    else
                                    {
                                        vec3 _27544 = vec3(0.0);
                                        if (_27483.x == 7.0)
                                        {
                                            _27544 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * _27483.z;
                                        }
                                        else
                                        {
                                            vec3 _27545 = vec3(0.0);
                                            if (_27483.x == 8.0)
                                            {
                                                vec3 _22356 = max(v_color.xyz * _27483.z, vec3(0.0));
                                                _27545 = mix(_22356 * 12.9200000762939453125, (pow(max(_22356, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22356));
                                            }
                                            else
                                            {
                                                vec3 _27546 = vec3(0.0);
                                                if (_27483.x == 9.0)
                                                {
                                                    vec3 mp_copy_27532 = vec3(0.0);
                                                    highp vec3 _27532 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _27532 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _27532 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_27532 = _27532;
                                                    float _22392 = length(mp_copy_27532);
                                                    vec3 _27533 = vec3(0.0);
                                                    if (_22392 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _27533 = mp_copy_27532 / vec3(_22392);
                                                    }
                                                    else
                                                    {
                                                        _27533 = vec3(0.0);
                                                    }
                                                    _27546 = ((_27533 * 0.5) + vec3(0.5)) * _27483.z;
                                                }
                                                else
                                                {
                                                    vec3 _27547 = vec3(0.0);
                                                    if (_27483.x == 10.0)
                                                    {
                                                        float _22435 = max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                                                        float _22436 = (v_position.x - _27484.x) / _22435;
                                                        bool _22440 = _27483.w > 1.5;
                                                        float _27526 = 0.0;
                                                        if (_22440)
                                                        {
                                                            _27526 = fract(_22436);
                                                        }
                                                        else
                                                        {
                                                            float _27527 = 0.0;
                                                            if (_27483.w > 0.5)
                                                            {
                                                                _27527 = ((_22436 < 0.0) || (_22436 > 1.0)) ? 0.0 : _22436;
                                                            }
                                                            else
                                                            {
                                                                _27527 = clamp(_22436, 0.0, 1.0);
                                                            }
                                                            _27526 = _27527;
                                                        }
                                                        float _22487 = (v_position.y - _27484.x) / _22435;
                                                        float _27528 = 0.0;
                                                        if (_22440)
                                                        {
                                                            _27528 = fract(_22487);
                                                        }
                                                        else
                                                        {
                                                            float _27529 = 0.0;
                                                            if (_27483.w > 0.5)
                                                            {
                                                                _27529 = ((_22487 < 0.0) || (_22487 > 1.0)) ? 0.0 : _22487;
                                                            }
                                                            else
                                                            {
                                                                _27529 = clamp(_22487, 0.0, 1.0);
                                                            }
                                                            _27528 = _27529;
                                                        }
                                                        float _22538 = (v_position.z - _27484.x) / _22435;
                                                        float _27530 = 0.0;
                                                        if (_22440)
                                                        {
                                                            _27530 = fract(_22538);
                                                        }
                                                        else
                                                        {
                                                            float _27531 = 0.0;
                                                            if (_27483.w > 0.5)
                                                            {
                                                                _27531 = ((_22538 < 0.0) || (_22538 > 1.0)) ? 0.0 : _22538;
                                                            }
                                                            else
                                                            {
                                                                _27531 = clamp(_22538, 0.0, 1.0);
                                                            }
                                                            _27530 = _27531;
                                                        }
                                                        _27547 = vec3(_27526 * _27483.z, _27528 * _27483.z, _27530 * _27483.z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _27548 = vec3(0.0);
                                                        if (_27483.x == 11.0)
                                                        {
                                                            bvec3 _22007 = bvec3(gl_FrontFacing);
                                                            _27548 = vec3(_22007.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _22007.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _22007.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _27549 = vec3(0.0);
                                                            if (_27483.x == 12.0)
                                                            {
                                                                highp vec2 _22565 = v_texture_coords;
                                                                vec2 mp_copy_22565 = _22565;
                                                                vec2 _22577 = floor(mp_copy_22565 * 8.0);
                                                                float _22579 = _22577.x;
                                                                float _22581 = _22577.y;
                                                                float _22589 = _22579 + (_22581 * 8.0);
                                                                vec2 _22598 = step(vec2(0.0), mp_copy_22565) * step(mp_copy_22565, vec2(1.0));
                                                                _27549 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22579 + _22581, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22589 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22589 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22598.x * _22598.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _27550 = vec3(0.0);
                                                                if (_27483.x == 13.0)
                                                                {
                                                                    highp vec2 _22648 = v_texture_coords_1;
                                                                    vec2 mp_copy_22648 = _22648;
                                                                    vec2 _22660 = floor(mp_copy_22648 * 8.0);
                                                                    float _22662 = _22660.x;
                                                                    float _22664 = _22660.y;
                                                                    float _22672 = _22662 + (_22664 * 8.0);
                                                                    vec2 _22681 = step(vec2(0.0), mp_copy_22648) * step(mp_copy_22648, vec2(1.0));
                                                                    _27550 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22662 + _22664, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22672 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22672 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22681.x * _22681.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _27551 = vec3(0.0);
                                                                    if (_27483.x == 14.0)
                                                                    {
                                                                        highp float _22747 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _22753 = debug_view_info.depth.x > 0.5;
                                                                        bool _22759 = false;
                                                                        if (_22753)
                                                                        {
                                                                            _22759 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _22759 = _22753;
                                                                        }
                                                                        highp float _27522 = 0.0;
                                                                        if (_22759)
                                                                        {
                                                                            _27522 = 1.1920928955078125e-07 / _22747;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _27523 = 0.0;
                                                                            if (_22753)
                                                                            {
                                                                                _27523 = 5.9604644775390625e-08 / (_22747 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _27523 = 5.9604644775390625e-08 / (_22747 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _27522 = _27523;
                                                                        }
                                                                        highp float _22788 = dot(_7187, view_info.camera_forward.xyz);
                                                                        highp float _22794 = sqrt(max(1.0 - (_22788 * _22788), 0.0));
                                                                        highp float _27520 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _27520 = (debug_view_info.depth.z * _22794) / max(abs(_22788), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _27520 = (((1.0 / (_22747 * _22747)) * debug_view_info.depth.z) * _22794) / max(abs(dot(_7187, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _22832 = log2(max(max(8.0 * _27522, _27520 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_22832 = _22832;
                                                                        float _22871 = (mp_copy_22832 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                                                                        float _27524 = 0.0;
                                                                        if (_27483.w > 1.5)
                                                                        {
                                                                            _27524 = fract(_22871);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _27525 = 0.0;
                                                                            if (_27483.w > 0.5)
                                                                            {
                                                                                _27525 = ((_22871 < 0.0) || (_22871 > 1.0)) ? 0.0 : _22871;
                                                                            }
                                                                            else
                                                                            {
                                                                                _27525 = clamp(_22871, 0.0, 1.0);
                                                                            }
                                                                            _27524 = _27525;
                                                                        }
                                                                        _27551 = clamp(vec3(1.5) - abs(vec3(4.0 * _27524) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * _27483.z;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _22904 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _27551 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_22904.x + _22904.y, 2.0)));
                                                                    }
                                                                    _27550 = _27551;
                                                                }
                                                                _27549 = _27550;
                                                            }
                                                            _27548 = _27549;
                                                        }
                                                        _27547 = _27548;
                                                    }
                                                    _27546 = _27547;
                                                }
                                                _27545 = _27546;
                                            }
                                            _27544 = _27545;
                                        }
                                        _27543 = _27544;
                                    }
                                    _27542 = _27543;
                                }
                                _27541 = _27542;
                            }
                            _27540 = _27541;
                        }
                        _27539 = _27540;
                    }
                    _27538 = _27539;
                }
                _27552 = vec4(_27538, 1.0);
                break;
            }
            vec3 _27499 = vec3(0.0);
            if (_27483.x < 40.0)
            {
                vec3 _27500 = vec3(0.0);
                if (_27483.x == 20.0)
                {
                    vec3 _22925 = max(_7274.xyz * _27483.z, vec3(0.0));
                    _27500 = mix(_22925 * 12.9200000762939453125, (pow(max(_22925, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22925));
                }
                else
                {
                    vec3 _27501 = vec3(0.0);
                    if (_27483.x == 21.0)
                    {
                        float _22964 = (_28247 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                        float _27497 = 0.0;
                        if (_27483.w > 1.5)
                        {
                            _27497 = fract(_22964);
                        }
                        else
                        {
                            float _27498 = 0.0;
                            if (_27483.w > 0.5)
                            {
                                _27498 = ((_22964 < 0.0) || (_22964 > 1.0)) ? 0.0 : _22964;
                            }
                            else
                            {
                                _27498 = clamp(_22964, 0.0, 1.0);
                            }
                            _27497 = _27498;
                        }
                        _27501 = vec3(_27497 * _27483.z);
                    }
                    else
                    {
                        vec3 _27502 = vec3(0.0);
                        if (_27483.x == 22.0)
                        {
                            float _23015 = (_7320 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                            float _27495 = 0.0;
                            if (_27483.w > 1.5)
                            {
                                _27495 = fract(_23015);
                            }
                            else
                            {
                                float _27496 = 0.0;
                                if (_27483.w > 0.5)
                                {
                                    _27496 = ((_23015 < 0.0) || (_23015 > 1.0)) ? 0.0 : _23015;
                                }
                                else
                                {
                                    _27496 = clamp(_23015, 0.0, 1.0);
                                }
                                _27495 = _27496;
                            }
                            _27502 = vec3(_27495 * _27483.z);
                        }
                        else
                        {
                            vec3 _27503 = vec3(0.0);
                            if (_27483.x == 23.0)
                            {
                                float _23066 = (_7327 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                                float _27493 = 0.0;
                                if (_27483.w > 1.5)
                                {
                                    _27493 = fract(_23066);
                                }
                                else
                                {
                                    float _27494 = 0.0;
                                    if (_27483.w > 0.5)
                                    {
                                        _27494 = ((_23066 < 0.0) || (_23066 > 1.0)) ? 0.0 : _23066;
                                    }
                                    else
                                    {
                                        _27494 = clamp(_23066, 0.0, 1.0);
                                    }
                                    _27493 = _27494;
                                }
                                _27503 = vec3(_27493 * _27483.z);
                            }
                            else
                            {
                                vec3 _27504 = vec3(0.0);
                                if (_27483.x == 24.0)
                                {
                                    float _23117 = (1.0 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                                    float _27491 = 0.0;
                                    if (_27483.w > 1.5)
                                    {
                                        _27491 = fract(_23117);
                                    }
                                    else
                                    {
                                        float _27492 = 0.0;
                                        if (_27483.w > 0.5)
                                        {
                                            _27492 = ((_23117 < 0.0) || (_23117 > 1.0)) ? 0.0 : _23117;
                                        }
                                        else
                                        {
                                            _27492 = clamp(_23117, 0.0, 1.0);
                                        }
                                        _27491 = _27492;
                                    }
                                    _27504 = vec3(_27491 * _27483.z);
                                }
                                else
                                {
                                    vec3 _27505 = vec3(0.0);
                                    if (_27483.x == 25.0)
                                    {
                                        float _23168 = (_7349 - _27484.x) / max(_27484.y - _27484.x, 9.9999999747524270787835121154785e-07);
                                        float _27489 = 0.0;
                                        if (_27483.w > 1.5)
                                        {
                                            _27489 = fract(_23168);
                                        }
                                        else
                                        {
                                            float _27490 = 0.0;
                                            if (_27483.w > 0.5)
                                            {
                                                _27490 = ((_23168 < 0.0) || (_23168 > 1.0)) ? 0.0 : _23168;
                                            }
                                            else
                                            {
                                                _27490 = clamp(_23168, 0.0, 1.0);
                                            }
                                            _27489 = _27490;
                                        }
                                        _27505 = vec3(_27489 * _27483.z);
                                    }
                                    else
                                    {
                                        vec3 _27506 = vec3(0.0);
                                        if (_27483.x == 26.0)
                                        {
                                            vec3 _23204 = max(_7373 * _27483.z, vec3(0.0));
                                            _27506 = mix(_23204 * 12.9200000762939453125, (pow(max(_23204, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _23204));
                                        }
                                        else
                                        {
                                            vec2 _23225 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _27506 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23225.x + _23225.y, 2.0)));
                                        }
                                        _27505 = _27506;
                                    }
                                    _27504 = _27505;
                                }
                                _27503 = _27504;
                            }
                            _27502 = _27503;
                        }
                        _27501 = _27502;
                    }
                    _27500 = _27501;
                }
                _27499 = _27500;
            }
            else
            {
                vec3 _27507 = vec3(0.0);
                if (_27483.x < 60.0)
                {
                    vec2 _23246 = floor(gl_FragCoord.xy * vec2(0.125));
                    _27507 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23246.x + _23246.y, 2.0)));
                }
                else
                {
                    vec3 _27508 = vec3(0.0);
                    if (_27483.x < 70.0)
                    {
                        vec3 _27509 = vec3(0.0);
                        if (_27483.x == 60.0)
                        {
                            _27509 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _27483.z;
                        }
                        else
                        {
                            vec3 _27510 = vec3(0.0);
                            if (_27483.x == 61.0)
                            {
                                _27510 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _27483.z;
                            }
                            else
                            {
                                vec2 _23334 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27510 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23334.x + _23334.y, 2.0)));
                            }
                            _27509 = _27510;
                        }
                        _27508 = _27509;
                    }
                    else
                    {
                        vec3 _27511 = vec3(0.0);
                        if (_27483.x < 80.0)
                        {
                            vec3 _27512 = vec3(0.0);
                            if (_27483.x == 70.0)
                            {
                                bool _23351 = v_texture_coords.x < 0.0;
                                bool _23358 = false;
                                if (!_23351)
                                {
                                    _23358 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _23358 = _23351;
                                }
                                bool _23365 = false;
                                if (!_23358)
                                {
                                    _23365 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _23365 = _23358;
                                }
                                bool _23372 = false;
                                if (!_23365)
                                {
                                    _23372 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _23372 = _23365;
                                }
                                bvec3 _23375 = bvec3(_23372);
                                highp vec3 _23376 = vec3(_23375.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23375.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23375.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _23401 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24770), normalize(_7187)) < 0.999000012874603271484375));
                                highp vec3 _23402 = vec3(_23401.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _23376.x, _23401.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _23376.y, _23401.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _23376.z);
                                float _23416 = length(v_normal);
                                bvec3 _23423 = bvec3((_23416 < 0.300000011920928955078125) || (_23416 > 1.7000000476837158203125));
                                highp vec3 _23424 = vec3(_23423.x ? vec3(1.0, 0.5, 0.0).x : _23402.x, _23423.y ? vec3(1.0, 0.5, 0.0).y : _23402.y, _23423.z ? vec3(1.0, 0.5, 0.0).z : _23402.z);
                                bool _23429 = _7320 > 0.0500000007450580596923828125;
                                bool _23435 = false;
                                if (_23429)
                                {
                                    _23435 = _7320 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _23435 = _23429;
                                }
                                vec3 _23447 = vec3(0.0);
                                bvec3 _23437 = bvec3(_23435);
                                highp vec3 _23438 = vec3(_23437.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _23424.x, _23437.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _23424.y, _23437.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _23424.z);
                                vec3 _27487 = vec3(0.0);
                                do
                                {
                                    _23447 = _7274.xyz;
                                    float _23448 = dot(_23447, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7320 > 0.5)
                                    {
                                        _27487 = _23438;
                                        break;
                                    }
                                    if (_23448 < 0.0130000002682209014892578125)
                                    {
                                        _27487 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_23448 > 0.87000000476837158203125)
                                    {
                                        _27487 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _27487 = _23438;
                                    break;
                                } while(false);
                                vec3 _27488 = vec3(0.0);
                                do
                                {
                                    vec3 _23493 = ((_23447 + _24770) + _7373) + vec3((_7320 + _7327) + _7349);
                                    bool _23508 = min(min(_7271, _7272), _7273) < 0.0;
                                    bool _23521 = false;
                                    if (!_23508)
                                    {
                                        _23521 = min(min(_7373.x, _7373.y), _7373.z) < 0.0;
                                    }
                                    else
                                    {
                                        _23521 = _23508;
                                    }
                                    if (any(isnan(_23493)))
                                    {
                                        _27488 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_23493)))
                                    {
                                        _27488 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_23521)
                                    {
                                        _27488 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _27488 = _27487;
                                    break;
                                } while(false);
                                _27512 = _27488;
                            }
                            else
                            {
                                vec3 _27513 = vec3(0.0);
                                if (_27483.x == 71.0)
                                {
                                    vec3 _27486 = vec3(0.0);
                                    do
                                    {
                                        vec3 _23561 = ((_7274.xyz + _24770) + _7373) + vec3((_7320 + _7327) + _7349);
                                        bool _23576 = min(min(_7271, _7272), _7273) < 0.0;
                                        bool _23589 = false;
                                        if (!_23576)
                                        {
                                            _23589 = min(min(_7373.x, _7373.y), _7373.z) < 0.0;
                                        }
                                        else
                                        {
                                            _23589 = _23576;
                                        }
                                        if (any(isnan(_23561)))
                                        {
                                            _27486 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_23561)))
                                        {
                                            _27486 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_23589)
                                        {
                                            _27486 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _27486 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _27513 = _27486;
                                }
                                else
                                {
                                    vec3 _27514 = vec3(0.0);
                                    if (_27483.x == 72.0)
                                    {
                                        vec3 _27485 = vec3(0.0);
                                        do
                                        {
                                            float _23611 = dot(_7274.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7320 > 0.5)
                                            {
                                                _27485 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_23611 < 0.0130000002682209014892578125)
                                            {
                                                _27485 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_23611 > 0.87000000476837158203125)
                                            {
                                                _27485 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _27485 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _27514 = _27485;
                                    }
                                    else
                                    {
                                        vec3 _27515 = vec3(0.0);
                                        if (_27483.x == 73.0)
                                        {
                                            bool _23633 = _7320 > 0.0500000007450580596923828125;
                                            bool _23639 = false;
                                            if (_23633)
                                            {
                                                _23639 = _7320 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _23639 = _23633;
                                            }
                                            bvec3 _23641 = bvec3(_23639);
                                            _27515 = vec3(_23641.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _23641.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _23641.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _27516 = vec3(0.0);
                                            if (_27483.x == 74.0)
                                            {
                                                float _23647 = length(v_normal);
                                                bvec3 _23654 = bvec3((_23647 < 0.300000011920928955078125) || (_23647 > 1.7000000476837158203125));
                                                _27516 = vec3(_23654.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _23654.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _23654.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _27517 = vec3(0.0);
                                                if (_27483.x == 75.0)
                                                {
                                                    bvec3 _23677 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24770), normalize(_7187)) < 0.999000012874603271484375));
                                                    _27517 = vec3(_23677.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _23677.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _23677.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _27518 = vec3(0.0);
                                                    if (_27483.x == 76.0)
                                                    {
                                                        bool _23695 = v_texture_coords.x < 0.0;
                                                        bool _23702 = false;
                                                        if (!_23695)
                                                        {
                                                            _23702 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23702 = _23695;
                                                        }
                                                        bool _23709 = false;
                                                        if (!_23702)
                                                        {
                                                            _23709 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _23709 = _23702;
                                                        }
                                                        bool _23716 = false;
                                                        if (!_23709)
                                                        {
                                                            _23716 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23716 = _23709;
                                                        }
                                                        bvec3 _23719 = bvec3(_23716);
                                                        _27518 = vec3(_23719.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23719.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23719.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _23732 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _27518 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23732.x + _23732.y, 2.0)));
                                                    }
                                                    _27517 = _27518;
                                                }
                                                _27516 = _27517;
                                            }
                                            _27515 = _27516;
                                        }
                                        _27514 = _27515;
                                    }
                                    _27513 = _27514;
                                }
                                _27512 = _27513;
                            }
                            _27511 = _27512;
                        }
                        else
                        {
                            vec3 _27519 = vec3(0.0);
                            if (_27483.x == 80.0)
                            {
                                _27519 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _23750 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27519 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23750.x + _23750.y, 2.0)));
                            }
                            _27511 = _27519;
                        }
                        _27508 = _27511;
                    }
                    _27507 = _27508;
                }
                _27499 = _27507;
            }
            _27552 = vec4(_27499, 1.0);
            break;
        } while(false);
        _27554 = _27552;
    }
    else
    {
        _27554 = vec4(0.0);
    }
    bool _21817 = false;
    if (_21769)
    {
        _21817 = ((_27482 < 1.5) || (_27482 > 2.5)) || _21767;
    }
    else
    {
        _21817 = _21769;
    }
    bvec4 _21821 = bvec4(_21817);
    frag_color = vec4(_21821.x ? _27554.x : _27479.x, _21821.y ? _27554.y : _27479.y, _21821.z ? _27554.z : _27479.z, _21821.w ? _27554.w : _27479.w);
    float _27555 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _27555 = 1.0;
    }
    else
    {
        _27555 = abs(frag_info.fade);
    }
    frag_color *= _27555;
}

