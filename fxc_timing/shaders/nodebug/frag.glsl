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

layout(std140) uniform DebugViewInfo
{
    vec4 view;
    vec4 params;
    vec4 left;
    highp vec4 depth;
} debug_view_info;

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
    highp float _6011 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_6011 = _6011;
    vec3 _6015 = normalize(v_normal) * mp_copy_6011;
    vec4 _6056 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _6059 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _21185 = vec2(0.0);
    if (_6059)
    {
        highp vec2 _21184 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _21184 = v_texture_coords_1;
        }
        else
        {
            _21184 = v_texture_coords;
        }
        highp vec2 _6246 = _21184 * texture_transforms.base_color_transform.zw;
        highp float _6252 = _6246.x;
        highp float _6257 = _6246.y;
        _21185 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6252) - (texture_transforms.base_color_rotation.y * _6257), (texture_transforms.base_color_rotation.y * _6252) + (texture_transforms.base_color_rotation.x * _6257));
    }
    else
    {
        _21185 = v_texture_coords;
    }
    vec4 _6073 = texture(base_color_texture, _21185);
    vec3 _6075 = _6073.xyz;
    float _22825 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_6073.w * _6056.w) * frag_info.color.w);
    vec3 _21197 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _21188 = vec2(0.0);
        if (_6059)
        {
            highp vec2 _21187 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _21187 = v_texture_coords_1;
            }
            else
            {
                _21187 = v_texture_coords;
            }
            highp vec2 _6340 = _21187 * texture_transforms.normal_transform.zw;
            highp float _6346 = _6340.x;
            highp float _6351 = _6340.y;
            _21188 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6346) - (texture_transforms.normal_rotation.y * _6351), (texture_transforms.normal_rotation.y * _6346) + (texture_transforms.normal_rotation.x * _6351));
        }
        else
        {
            _21188 = v_texture_coords;
        }
        vec3 _6398 = ((texture(normal_texture, _21188).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6402 = _6398.xy * vec2(frag_info.normal_scale);
        vec3 _20488 = _6398;
        _20488.x = _6402.x;
        _20488.y = _6402.y;
        highp vec3 _6408 = -v_viewvector;
        mat3 _21196 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _6438 = v_tangent.xyz - (_6015 * dot(_6015, v_tangent.xyz));
            highp float _6441 = dot(_6438, _6438);
            bool _6443 = _6441 <= 1.0000000133514319600180897396058e-10;
            bool _6451 = false;
            if (!_6443)
            {
                _6451 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _6451 = _6443;
            }
            if (_6451)
            {
                highp vec2 _6509 = dFdx(_21188);
                highp vec2 _6511 = dFdy(_21188);
                bvec2 _22827 = bvec2(length(_6509) == 0.0);
                highp vec2 _22828 = vec2(_22827.x ? vec2(1.0, 0.0).x : _6509.x, _22827.y ? vec2(1.0, 0.0).y : _6509.y);
                bvec2 _22829 = bvec2(length(_6511) == 0.0);
                highp vec2 _22830 = vec2(_22829.x ? vec2(0.0, 1.0).x : _6511.x, _22829.y ? vec2(0.0, 1.0).y : _6511.y);
                highp vec3 _6524 = cross(dFdy(_6408), _6015);
                highp vec3 _6527 = cross(_6015, dFdx(_6408));
                highp vec3 _6536 = (_6524 * _22828.x) + (_6527 * _22830.x);
                highp vec3 _6545 = (_6524 * _22828.y) + (_6527 * _22830.y);
                highp float _6554 = inversesqrt(max(max(dot(_6536, _6536), dot(_6545, _6545)), 9.9999996826552253889678874634872e-21));
                _21196 = mat3(_6536 * _6554, _6545 * _6554, _6015);
                break;
            }
            highp vec3 _6461 = _6438 * inversesqrt(_6441);
            _21196 = mat3(_6461, normalize(cross(_6015, _6461)) * sign(v_tangent.w), _6015);
            break;
        } while(false);
        _21197 = normalize(_21196 * _20488);
    }
    else
    {
        _21197 = _6015;
    }
    highp vec2 _21199 = vec2(0.0);
    if (_6059)
    {
        highp vec2 _21198 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _21198 = v_texture_coords_1;
        }
        else
        {
            _21198 = v_texture_coords;
        }
        highp vec2 _6616 = _21198 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6622 = _6616.x;
        highp float _6627 = _6616.y;
        _21199 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6622) - (texture_transforms.metallic_roughness_rotation.y * _6627), (texture_transforms.metallic_roughness_rotation.y * _6622) + (texture_transforms.metallic_roughness_rotation.x * _6627));
    }
    else
    {
        _21199 = v_texture_coords;
    }
    vec4 _6142 = texture(metallic_roughness_texture, _21199);
    float _6148 = clamp(_6142.z * frag_info.metallic_factor, 0.0, 1.0);
    float _6155 = clamp(_6142.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _21201 = vec2(0.0);
    if (_6059)
    {
        highp vec2 _21200 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _21200 = v_texture_coords_1;
        }
        else
        {
            _21200 = v_texture_coords;
        }
        highp vec2 _6686 = _21200 * texture_transforms.occlusion_transform.zw;
        highp float _6692 = _6686.x;
        highp float _6697 = _6686.y;
        _21201 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6692) - (texture_transforms.occlusion_rotation.y * _6697), (texture_transforms.occlusion_rotation.y * _6692) + (texture_transforms.occlusion_rotation.x * _6697));
    }
    else
    {
        _21201 = v_texture_coords;
    }
    vec4 _6170 = texture(occlusion_texture, _21201);
    float _6177 = 1.0 - ((1.0 - _6170.x) * frag_info.occlusion_strength);
    highp vec2 _21203 = vec2(0.0);
    if (_6059)
    {
        highp vec2 _21202 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _21202 = v_texture_coords_1;
        }
        else
        {
            _21202 = v_texture_coords;
        }
        highp vec2 _6756 = _21202 * texture_transforms.emissive_transform.zw;
        highp float _6762 = _6756.x;
        highp float _6767 = _6756.y;
        _21203 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6762) - (texture_transforms.emissive_rotation.y * _6767), (texture_transforms.emissive_rotation.y * _6762) + (texture_transforms.emissive_rotation.x * _6767));
    }
    else
    {
        _21203 = v_texture_coords;
    }
    highp float hp_copy_21233 = 0.0;
    vec4 _6192 = texture(emissive_texture, _21203);
    vec3 _6193 = _6192.xyz;
    vec3 _7014 = vec4((mix(_6075 * vec3(0.077399380505084991455078125), pow((_6075 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6075)) * _6056.xyz) * frag_info.color.xyz, _22825).xyz;
    float _21233 = 0.0;
    do
    {
        if (frag_info.specular_aa_variance <= 0.0)
        {
            _21233 = _6155;
            break;
        }
        vec3 _7832 = dFdx(_21197);
        vec3 _7834 = dFdy(_21197);
        _21233 = sqrt(clamp((_6155 * _6155) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7832, _7832), dot(_7834, _7834))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
        break;
    } while(false);
    hp_copy_21233 = _21233;
    float _21243 = 0.0;
    vec3 _21248 = vec3(0.0);
    float _21521 = 0.0;
    vec4 _21897 = vec4(0.0);
    vec3 _22048 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _7041 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _21234 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _21234 = _7041.w;
        }
        else
        {
            _21234 = _7041.x;
        }
        float _7054 = min(_6177, _21234);
        bool _7057 = frag_info.ssao_lighting.z > 0.5;
        bool _7063 = false;
        if (_7057)
        {
            _7063 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _7063 = _7057;
        }
        vec3 _21249 = vec3(0.0);
        if (_7063)
        {
            vec2 _7867 = (_7041.zw * 2.0) - vec2(1.0);
            float _7869 = _7867.x;
            float _7871 = _7867.y;
            float _7879 = (1.0 - abs(_7869)) - abs(_7871);
            vec3 _7880 = vec3(_7869, _7871, _7879);
            vec3 _21237 = vec3(0.0);
            if (_7879 < 0.0)
            {
                vec2 _7893 = (vec2(1.0) - abs(_7880.yx)) * vec2((_7869 >= 0.0) ? 1.0 : (-1.0), (_7871 >= 0.0) ? 1.0 : (-1.0));
                vec3 _20537 = _7880;
                _20537.x = _7893.x;
                _20537.y = _7893.y;
                _21237 = _20537;
            }
            else
            {
                _21237 = _7880;
            }
            vec3 _7901 = -normalize(_21237);
            _21249 = normalize(((frag_info.camera_right.xyz * _7901.x) + (frag_info.camera_up.xyz * _7901.y)) + (frag_info.camera_forward.xyz * _7901.z));
        }
        else
        {
            _21249 = vec3(0.0);
        }
        vec3 _7091 = vec3(_7054);
        _22048 = mix(_7091, max(_7091, ((((((_7014 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _7054) + ((_7014 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _7054) + ((_7014 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _7054), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _21897 = _7041;
        _21521 = _7054;
        _21248 = _21249;
        _21243 = float(_7063);
    }
    else
    {
        _22048 = vec3(_6177);
        _21897 = vec4(1.0);
        _21521 = _6177;
        _21248 = vec3(0.0);
        _21243 = 0.0;
    }
    vec3 mp_copy_21241 = vec3(0.0);
    bool _7950 = view_info.camera_forward.w > 0.5;
    highp vec3 _21241 = vec3(0.0);
    if (_7950)
    {
        _21241 = -view_info.camera_forward.xyz;
    }
    else
    {
        _21241 = normalize(v_viewvector);
    }
    mp_copy_21241 = _21241;
    vec3 _7109 = mix(frag_info.dielectric_f0.xyz, _7014, vec3(_6148));
    float _7112 = dot(_21197, _21241);
    float _7113 = max(_7112, 0.0);
    float _7117 = max(dot(_6015, _21241), 0.0);
    vec3 _7121 = reflect(-mp_copy_21241, _21197);
    mat3 _7134 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7137 = _21243 > 0.5;
    bvec3 _7140 = bvec3(_7137);
    highp vec3 _7141 = vec3(_7140.x ? _21248.x : _21197.x, _7140.y ? _21248.y : _21197.y, _7140.z ? _21248.z : _21197.z);
    vec3 mp_copy_7141 = _7141;
    vec3 _7142 = _7134 * mp_copy_7141;
    vec3 _21252 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _8017 = _7121 + (((step(vec3(0.0), _7121) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_8017 = _8017;
        highp vec3 _8019 = vec3(1.0) / hp_copy_8017;
        highp vec3 _8036 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _8019, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _8019);
        _21252 = normalize((v_position + (_7121 * max(min(min(_8036.x, _8036.y), _8036.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _21252 = _7121;
    }
    bool _8264 = false;
    vec3 _7147 = _7134 * _21252;
    float _8083 = _7142.y;
    float _8084 = 0.48860299587249755859375 * _8083;
    float _8090 = _7142.z;
    float _8091 = 0.48860299587249755859375 * _8090;
    float _8097 = _7142.x;
    float _8098 = 0.48860299587249755859375 * _8097;
    float _8105 = 1.09254801273345947265625 * _8097;
    float _8108 = _8105 * _8083;
    float _8118 = (1.09254801273345947265625 * _8083) * _8090;
    float _8130 = 0.3153919875621795654296875 * (((3.0 * _8090) * _8090) - 1.0);
    float _8140 = _8105 * _8090;
    float _8156 = 0.546274006366729736328125 * ((_8097 * _8097) - (_8083 * _8083));
    vec3 _7150 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _8084)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _8091)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _8098)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _8108)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _8118)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _8130)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _8140)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _8156), vec3(0.0));
    vec3 _21253 = vec3(0.0);
    do
    {
        _8264 = radiance_layout_info.mip_layout > 0.5;
        if (_8264)
        {
            vec2 _8343 = vec2(atan(_7147.z, _7147.x), asin(clamp(_7147.y, -1.0, 1.0)));
            highp vec2 hp_copy_8343 = _8343;
            _21253 = textureLod(prefiltered_radiance, (hp_copy_8343 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_21233, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8362 = vec2(atan(_7147.z, _7147.x), asin(clamp(_7147.y, -1.0, 1.0)));
        highp vec2 hp_copy_8362 = _8362;
        highp vec2 _8367 = (hp_copy_8362 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8274 = clamp(_8367.y, 0.00390625, 0.99609375);
        float _8278 = clamp(_21233, 0.0, 1.0) * 7.0;
        float _8280 = floor(_8278);
        highp float _8299 = _8367.x;
        _21253 = mix(texture(prefiltered_radiance, vec2(_8299, (_8280 + _8274) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_8299, (min(_8280 + 1.0, 7.0) + _8274) * 0.125)).xyz, vec3(_8278 - _8280));
        break;
    } while(false);
    bool _7157 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _21258 = vec3(0.0);
    highp vec3 _21259 = vec3(0.0);
    if (_7157)
    {
        vec3 _21254 = vec3(0.0);
        do
        {
            if (_8264)
            {
                vec2 _8655 = vec2(atan(_7147.z, _7147.x), asin(clamp(_7147.y, -1.0, 1.0)));
                highp vec2 hp_copy_8655 = _8655;
                _21254 = textureLod(prefiltered_radiance_b, (hp_copy_8655 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_21233, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8674 = vec2(atan(_7147.z, _7147.x), asin(clamp(_7147.y, -1.0, 1.0)));
            highp vec2 hp_copy_8674 = _8674;
            highp vec2 _8679 = (hp_copy_8674 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8586 = clamp(_8679.y, 0.00390625, 0.99609375);
            float _8590 = clamp(_21233, 0.0, 1.0) * 7.0;
            float _8592 = floor(_8590);
            highp float _8611 = _8679.x;
            _21254 = mix(texture(prefiltered_radiance_b, vec2(_8611, (_8592 + _8586) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_8611, (min(_8592 + 1.0, 7.0) + _8586) * 0.125)).xyz, vec3(_8590 - _8592));
            break;
        } while(false);
        highp vec3 _7168 = vec3(frag_info.radiance_blend.x);
        _21259 = mix(_21253, _21254, _7168);
        _21258 = mix(_7150, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _8084)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _8091)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _8098)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _8108)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _8118)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _8130)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _8140)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _8156), vec3(0.0)), _7168);
    }
    else
    {
        _21259 = _21253;
        _21258 = _7150;
    }
    highp float _8692 = 0.0;
    highp vec3 _7179 = _21258 * frag_info.environment_intensity;
    float _21260 = 0.0;
    do
    {
        _8692 = frag_info.gi_grid.w;
        if (_8692 <= 0.0)
        {
            _21260 = 0.0;
            break;
        }
        highp vec3 _8705 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _8713 = min(_8705, (frag_info.gi_counts.xyz - vec3(1.0)) - _8705);
        _21260 = clamp(min(_8713.x, min(_8713.y, _8713.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _21451 = vec3(0.0);
    if (_21260 > 0.0)
    {
        highp vec3 _8805 = v_position + (((_21197 * 0.20000000298023223876953125) + (mp_copy_21241 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _8808 = _8805 / frag_info.gi_grid.xyz;
        highp vec3 _8810 = floor(_8808);
        highp vec3 _8816 = clamp(_8808 - _8810, vec3(0.0), vec3(1.0));
        vec3 mp_copy_8816 = _8816;
        highp vec3 _8938 = _8810 - frag_info.gi_anchor.xyz;
        bool _8941 = any(lessThan(_8938, vec3(0.0)));
        bool _8949 = false;
        if (!_8941)
        {
            _8949 = any(greaterThanEqual(_8938, frag_info.gi_counts.xyz));
        }
        else
        {
            _8949 = _8941;
        }
        vec3 mp_copy_21261 = vec3(0.0);
        highp float _8950 = _8949 ? 0.0 : 1.0;
        float mp_copy_8950 = _8950;
        vec3 _8952 = vec3(1.0) - mp_copy_8816;
        vec3 _8956 = max(_8952, vec3(0.001000000047497451305389404296875));
        highp vec3 _8972 = (_8810 * frag_info.gi_grid.xyz) - _8805;
        highp float _8974 = length(_8972);
        highp vec3 _21261 = vec3(0.0);
        if (_8974 > 9.9999997473787516355514526367188e-06)
        {
            _21261 = _8972 / vec3(_8974);
        }
        else
        {
            _21261 = _21197;
        }
        mp_copy_21261 = _21261;
        float _8992 = pow((dot(_21261, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9117 = _8810 - (frag_info.gi_counts.xyz * floor(_8810 / frag_info.gi_counts.xyz));
        highp float _9133 = _9117.x + (frag_info.gi_counts.x * (_9117.y + (frag_info.gi_counts.y * _9117.z)));
        bool _9003 = frag_info.gi_visibility.x > 0.0;
        float _21266 = 0.0;
        if (_9003)
        {
            highp float _9141 = floor(_9133 / frag_info.gi_counts.w);
            highp vec2 _9155 = vec2((_9133 - (_9141 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9141 * 16.0));
            vec3 _9015 = -mp_copy_21261;
            vec3 _9203 = _9015 / vec3((abs(_9015.x) + abs(_9015.y)) + abs(_9015.z));
            vec2 _21262 = vec2(0.0);
            if (_9203.z >= 0.0)
            {
                _21262 = _9203.xy;
            }
            else
            {
                _21262 = (vec2(1.0) - abs(_9203.yx)) * vec2((_9203.x >= 0.0) ? 1.0 : (-1.0), (_9203.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9019 = texture(irradiance_field, clamp((_9155 + vec2(1.0)) + (clamp((_21262 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9155 + vec2(0.5), _9155 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9024 = _9019.x * frag_info.gi_visibility.z;
            highp float _9036 = abs((_9024 * _9024) - ((_9019.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9042 = (_8974 - _9024) - frag_info.gi_visibility.y;
            highp float _21263 = 0.0;
            if (_9042 <= 0.0)
            {
                _21263 = 1.0;
            }
            else
            {
                _21263 = _9036 / (_9036 + (_9042 * _9042));
            }
            _21266 = _8992 * mix(1.0, max(0.0500000007450580596923828125, (_21263 * _21263) * _21263), frag_info.gi_visibility.x);
        }
        else
        {
            _21266 = _8992;
        }
        float _9070 = max(9.9999999747524270787835121154785e-07, _21266);
        float _21267 = 0.0;
        if (_9070 < 0.20000000298023223876953125)
        {
            _21267 = _9070 * ((_9070 * _9070) * 25.0);
        }
        else
        {
            _21267 = _9070;
        }
        float _9085 = _21267 * (((_8956.x * _8956.y) * _8956.z) * mp_copy_8950);
        highp float _9244 = floor(_9133 / frag_info.gi_counts.w);
        highp vec2 _9258 = vec2((_9133 - (_9244 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9244 * 8.0));
        vec3 _9306 = _21197 / vec3((abs(_21197.x) + abs(_21197.y)) + abs(_21197.z));
        bool _9309 = _9306.z >= 0.0;
        vec2 _21268 = vec2(0.0);
        if (_9309)
        {
            _21268 = _9306.xy;
        }
        else
        {
            _21268 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9097 = texture(irradiance_field, clamp((_9258 + vec2(1.0)) + (clamp((_21268 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9258 + vec2(0.5), _9258 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9392 = _8810 + vec3(1.0, 0.0, 0.0);
        highp vec3 _9397 = _9392 - frag_info.gi_anchor.xyz;
        bool _9400 = any(lessThan(_9397, vec3(0.0)));
        bool _9408 = false;
        if (!_9400)
        {
            _9408 = any(greaterThanEqual(_9397, frag_info.gi_counts.xyz));
        }
        else
        {
            _9408 = _9400;
        }
        vec3 mp_copy_21270 = vec3(0.0);
        highp float _9409 = _9408 ? 0.0 : 1.0;
        float mp_copy_9409 = _9409;
        vec3 _9415 = max(mix(_8952, mp_copy_8816, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9431 = (_9392 * frag_info.gi_grid.xyz) - _8805;
        highp float _9433 = length(_9431);
        highp vec3 _21270 = vec3(0.0);
        if (_9433 > 9.9999997473787516355514526367188e-06)
        {
            _21270 = _9431 / vec3(_9433);
        }
        else
        {
            _21270 = _21197;
        }
        mp_copy_21270 = _21270;
        float _9451 = pow((dot(_21270, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9576 = _9392 - (frag_info.gi_counts.xyz * floor(_9392 / frag_info.gi_counts.xyz));
        highp float _9592 = _9576.x + (frag_info.gi_counts.x * (_9576.y + (frag_info.gi_counts.y * _9576.z)));
        float _21275 = 0.0;
        if (_9003)
        {
            highp float _9600 = floor(_9592 / frag_info.gi_counts.w);
            highp vec2 _9614 = vec2((_9592 - (_9600 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9600 * 16.0));
            vec3 _9474 = -mp_copy_21270;
            vec3 _9662 = _9474 / vec3((abs(_9474.x) + abs(_9474.y)) + abs(_9474.z));
            vec2 _21271 = vec2(0.0);
            if (_9662.z >= 0.0)
            {
                _21271 = _9662.xy;
            }
            else
            {
                _21271 = (vec2(1.0) - abs(_9662.yx)) * vec2((_9662.x >= 0.0) ? 1.0 : (-1.0), (_9662.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9478 = texture(irradiance_field, clamp((_9614 + vec2(1.0)) + (clamp((_21271 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9614 + vec2(0.5), _9614 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9483 = _9478.x * frag_info.gi_visibility.z;
            highp float _9495 = abs((_9483 * _9483) - ((_9478.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9501 = (_9433 - _9483) - frag_info.gi_visibility.y;
            highp float _21272 = 0.0;
            if (_9501 <= 0.0)
            {
                _21272 = 1.0;
            }
            else
            {
                _21272 = _9495 / (_9495 + (_9501 * _9501));
            }
            _21275 = _9451 * mix(1.0, max(0.0500000007450580596923828125, (_21272 * _21272) * _21272), frag_info.gi_visibility.x);
        }
        else
        {
            _21275 = _9451;
        }
        float _9529 = max(9.9999999747524270787835121154785e-07, _21275);
        float _21276 = 0.0;
        if (_9529 < 0.20000000298023223876953125)
        {
            _21276 = _9529 * ((_9529 * _9529) * 25.0);
        }
        else
        {
            _21276 = _9529;
        }
        float _9544 = _21276 * (((_9415.x * _9415.y) * _9415.z) * mp_copy_9409);
        highp float _9703 = floor(_9592 / frag_info.gi_counts.w);
        highp vec2 _9717 = vec2((_9592 - (_9703 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9703 * 8.0));
        vec2 _21277 = vec2(0.0);
        if (_9309)
        {
            _21277 = _9306.xy;
        }
        else
        {
            _21277 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9556 = texture(irradiance_field, clamp((_9717 + vec2(1.0)) + (clamp((_21277 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9717 + vec2(0.5), _9717 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9851 = _8810 + vec3(0.0, 1.0, 0.0);
        highp vec3 _9856 = _9851 - frag_info.gi_anchor.xyz;
        bool _9859 = any(lessThan(_9856, vec3(0.0)));
        bool _9867 = false;
        if (!_9859)
        {
            _9867 = any(greaterThanEqual(_9856, frag_info.gi_counts.xyz));
        }
        else
        {
            _9867 = _9859;
        }
        vec3 mp_copy_21279 = vec3(0.0);
        highp float _9868 = _9867 ? 0.0 : 1.0;
        float mp_copy_9868 = _9868;
        vec3 _9874 = max(mix(_8952, mp_copy_8816, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9890 = (_9851 * frag_info.gi_grid.xyz) - _8805;
        highp float _9892 = length(_9890);
        highp vec3 _21279 = vec3(0.0);
        if (_9892 > 9.9999997473787516355514526367188e-06)
        {
            _21279 = _9890 / vec3(_9892);
        }
        else
        {
            _21279 = _21197;
        }
        mp_copy_21279 = _21279;
        float _9910 = pow((dot(_21279, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10035 = _9851 - (frag_info.gi_counts.xyz * floor(_9851 / frag_info.gi_counts.xyz));
        highp float _10051 = _10035.x + (frag_info.gi_counts.x * (_10035.y + (frag_info.gi_counts.y * _10035.z)));
        float _21284 = 0.0;
        if (_9003)
        {
            highp float _10059 = floor(_10051 / frag_info.gi_counts.w);
            highp vec2 _10073 = vec2((_10051 - (_10059 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10059 * 16.0));
            vec3 _9933 = -mp_copy_21279;
            vec3 _10121 = _9933 / vec3((abs(_9933.x) + abs(_9933.y)) + abs(_9933.z));
            vec2 _21280 = vec2(0.0);
            if (_10121.z >= 0.0)
            {
                _21280 = _10121.xy;
            }
            else
            {
                _21280 = (vec2(1.0) - abs(_10121.yx)) * vec2((_10121.x >= 0.0) ? 1.0 : (-1.0), (_10121.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9937 = texture(irradiance_field, clamp((_10073 + vec2(1.0)) + (clamp((_21280 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10073 + vec2(0.5), _10073 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9942 = _9937.x * frag_info.gi_visibility.z;
            highp float _9954 = abs((_9942 * _9942) - ((_9937.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9960 = (_9892 - _9942) - frag_info.gi_visibility.y;
            highp float _21281 = 0.0;
            if (_9960 <= 0.0)
            {
                _21281 = 1.0;
            }
            else
            {
                _21281 = _9954 / (_9954 + (_9960 * _9960));
            }
            _21284 = _9910 * mix(1.0, max(0.0500000007450580596923828125, (_21281 * _21281) * _21281), frag_info.gi_visibility.x);
        }
        else
        {
            _21284 = _9910;
        }
        float _9988 = max(9.9999999747524270787835121154785e-07, _21284);
        float _21285 = 0.0;
        if (_9988 < 0.20000000298023223876953125)
        {
            _21285 = _9988 * ((_9988 * _9988) * 25.0);
        }
        else
        {
            _21285 = _9988;
        }
        float _10003 = _21285 * (((_9874.x * _9874.y) * _9874.z) * mp_copy_9868);
        highp float _10162 = floor(_10051 / frag_info.gi_counts.w);
        highp vec2 _10176 = vec2((_10051 - (_10162 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10162 * 8.0));
        vec2 _21286 = vec2(0.0);
        if (_9309)
        {
            _21286 = _9306.xy;
        }
        else
        {
            _21286 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10015 = texture(irradiance_field, clamp((_10176 + vec2(1.0)) + (clamp((_21286 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10176 + vec2(0.5), _10176 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10310 = _8810 + vec3(1.0, 1.0, 0.0);
        highp vec3 _10315 = _10310 - frag_info.gi_anchor.xyz;
        bool _10318 = any(lessThan(_10315, vec3(0.0)));
        bool _10326 = false;
        if (!_10318)
        {
            _10326 = any(greaterThanEqual(_10315, frag_info.gi_counts.xyz));
        }
        else
        {
            _10326 = _10318;
        }
        vec3 mp_copy_21288 = vec3(0.0);
        highp float _10327 = _10326 ? 0.0 : 1.0;
        float mp_copy_10327 = _10327;
        vec3 _10333 = max(mix(_8952, mp_copy_8816, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10349 = (_10310 * frag_info.gi_grid.xyz) - _8805;
        highp float _10351 = length(_10349);
        highp vec3 _21288 = vec3(0.0);
        if (_10351 > 9.9999997473787516355514526367188e-06)
        {
            _21288 = _10349 / vec3(_10351);
        }
        else
        {
            _21288 = _21197;
        }
        mp_copy_21288 = _21288;
        float _10369 = pow((dot(_21288, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10494 = _10310 - (frag_info.gi_counts.xyz * floor(_10310 / frag_info.gi_counts.xyz));
        highp float _10510 = _10494.x + (frag_info.gi_counts.x * (_10494.y + (frag_info.gi_counts.y * _10494.z)));
        float _21293 = 0.0;
        if (_9003)
        {
            highp float _10518 = floor(_10510 / frag_info.gi_counts.w);
            highp vec2 _10532 = vec2((_10510 - (_10518 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10518 * 16.0));
            vec3 _10392 = -mp_copy_21288;
            vec3 _10580 = _10392 / vec3((abs(_10392.x) + abs(_10392.y)) + abs(_10392.z));
            vec2 _21289 = vec2(0.0);
            if (_10580.z >= 0.0)
            {
                _21289 = _10580.xy;
            }
            else
            {
                _21289 = (vec2(1.0) - abs(_10580.yx)) * vec2((_10580.x >= 0.0) ? 1.0 : (-1.0), (_10580.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10396 = texture(irradiance_field, clamp((_10532 + vec2(1.0)) + (clamp((_21289 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10532 + vec2(0.5), _10532 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10401 = _10396.x * frag_info.gi_visibility.z;
            highp float _10413 = abs((_10401 * _10401) - ((_10396.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10419 = (_10351 - _10401) - frag_info.gi_visibility.y;
            highp float _21290 = 0.0;
            if (_10419 <= 0.0)
            {
                _21290 = 1.0;
            }
            else
            {
                _21290 = _10413 / (_10413 + (_10419 * _10419));
            }
            _21293 = _10369 * mix(1.0, max(0.0500000007450580596923828125, (_21290 * _21290) * _21290), frag_info.gi_visibility.x);
        }
        else
        {
            _21293 = _10369;
        }
        float _10447 = max(9.9999999747524270787835121154785e-07, _21293);
        float _21294 = 0.0;
        if (_10447 < 0.20000000298023223876953125)
        {
            _21294 = _10447 * ((_10447 * _10447) * 25.0);
        }
        else
        {
            _21294 = _10447;
        }
        float _10462 = _21294 * (((_10333.x * _10333.y) * _10333.z) * mp_copy_10327);
        highp float _10621 = floor(_10510 / frag_info.gi_counts.w);
        highp vec2 _10635 = vec2((_10510 - (_10621 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10621 * 8.0));
        vec2 _21295 = vec2(0.0);
        if (_9309)
        {
            _21295 = _9306.xy;
        }
        else
        {
            _21295 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10474 = texture(irradiance_field, clamp((_10635 + vec2(1.0)) + (clamp((_21295 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10635 + vec2(0.5), _10635 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10769 = _8810 + vec3(0.0, 0.0, 1.0);
        highp vec3 _10774 = _10769 - frag_info.gi_anchor.xyz;
        bool _10777 = any(lessThan(_10774, vec3(0.0)));
        bool _10785 = false;
        if (!_10777)
        {
            _10785 = any(greaterThanEqual(_10774, frag_info.gi_counts.xyz));
        }
        else
        {
            _10785 = _10777;
        }
        vec3 mp_copy_21297 = vec3(0.0);
        highp float _10786 = _10785 ? 0.0 : 1.0;
        float mp_copy_10786 = _10786;
        vec3 _10792 = max(mix(_8952, mp_copy_8816, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10808 = (_10769 * frag_info.gi_grid.xyz) - _8805;
        highp float _10810 = length(_10808);
        highp vec3 _21297 = vec3(0.0);
        if (_10810 > 9.9999997473787516355514526367188e-06)
        {
            _21297 = _10808 / vec3(_10810);
        }
        else
        {
            _21297 = _21197;
        }
        mp_copy_21297 = _21297;
        float _10828 = pow((dot(_21297, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10953 = _10769 - (frag_info.gi_counts.xyz * floor(_10769 / frag_info.gi_counts.xyz));
        highp float _10969 = _10953.x + (frag_info.gi_counts.x * (_10953.y + (frag_info.gi_counts.y * _10953.z)));
        float _21302 = 0.0;
        if (_9003)
        {
            highp float _10977 = floor(_10969 / frag_info.gi_counts.w);
            highp vec2 _10991 = vec2((_10969 - (_10977 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10977 * 16.0));
            vec3 _10851 = -mp_copy_21297;
            vec3 _11039 = _10851 / vec3((abs(_10851.x) + abs(_10851.y)) + abs(_10851.z));
            vec2 _21298 = vec2(0.0);
            if (_11039.z >= 0.0)
            {
                _21298 = _11039.xy;
            }
            else
            {
                _21298 = (vec2(1.0) - abs(_11039.yx)) * vec2((_11039.x >= 0.0) ? 1.0 : (-1.0), (_11039.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10855 = texture(irradiance_field, clamp((_10991 + vec2(1.0)) + (clamp((_21298 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10991 + vec2(0.5), _10991 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10860 = _10855.x * frag_info.gi_visibility.z;
            highp float _10872 = abs((_10860 * _10860) - ((_10855.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10878 = (_10810 - _10860) - frag_info.gi_visibility.y;
            highp float _21299 = 0.0;
            if (_10878 <= 0.0)
            {
                _21299 = 1.0;
            }
            else
            {
                _21299 = _10872 / (_10872 + (_10878 * _10878));
            }
            _21302 = _10828 * mix(1.0, max(0.0500000007450580596923828125, (_21299 * _21299) * _21299), frag_info.gi_visibility.x);
        }
        else
        {
            _21302 = _10828;
        }
        float _10906 = max(9.9999999747524270787835121154785e-07, _21302);
        float _21303 = 0.0;
        if (_10906 < 0.20000000298023223876953125)
        {
            _21303 = _10906 * ((_10906 * _10906) * 25.0);
        }
        else
        {
            _21303 = _10906;
        }
        float _10921 = _21303 * (((_10792.x * _10792.y) * _10792.z) * mp_copy_10786);
        highp float _11080 = floor(_10969 / frag_info.gi_counts.w);
        highp vec2 _11094 = vec2((_10969 - (_11080 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11080 * 8.0));
        vec2 _21304 = vec2(0.0);
        if (_9309)
        {
            _21304 = _9306.xy;
        }
        else
        {
            _21304 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10933 = texture(irradiance_field, clamp((_11094 + vec2(1.0)) + (clamp((_21304 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11094 + vec2(0.5), _11094 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11228 = _8810 + vec3(1.0, 0.0, 1.0);
        highp vec3 _11233 = _11228 - frag_info.gi_anchor.xyz;
        bool _11236 = any(lessThan(_11233, vec3(0.0)));
        bool _11244 = false;
        if (!_11236)
        {
            _11244 = any(greaterThanEqual(_11233, frag_info.gi_counts.xyz));
        }
        else
        {
            _11244 = _11236;
        }
        vec3 mp_copy_21306 = vec3(0.0);
        highp float _11245 = _11244 ? 0.0 : 1.0;
        float mp_copy_11245 = _11245;
        vec3 _11251 = max(mix(_8952, mp_copy_8816, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11267 = (_11228 * frag_info.gi_grid.xyz) - _8805;
        highp float _11269 = length(_11267);
        highp vec3 _21306 = vec3(0.0);
        if (_11269 > 9.9999997473787516355514526367188e-06)
        {
            _21306 = _11267 / vec3(_11269);
        }
        else
        {
            _21306 = _21197;
        }
        mp_copy_21306 = _21306;
        float _11287 = pow((dot(_21306, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11412 = _11228 - (frag_info.gi_counts.xyz * floor(_11228 / frag_info.gi_counts.xyz));
        highp float _11428 = _11412.x + (frag_info.gi_counts.x * (_11412.y + (frag_info.gi_counts.y * _11412.z)));
        float _21311 = 0.0;
        if (_9003)
        {
            highp float _11436 = floor(_11428 / frag_info.gi_counts.w);
            highp vec2 _11450 = vec2((_11428 - (_11436 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11436 * 16.0));
            vec3 _11310 = -mp_copy_21306;
            vec3 _11498 = _11310 / vec3((abs(_11310.x) + abs(_11310.y)) + abs(_11310.z));
            vec2 _21307 = vec2(0.0);
            if (_11498.z >= 0.0)
            {
                _21307 = _11498.xy;
            }
            else
            {
                _21307 = (vec2(1.0) - abs(_11498.yx)) * vec2((_11498.x >= 0.0) ? 1.0 : (-1.0), (_11498.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11314 = texture(irradiance_field, clamp((_11450 + vec2(1.0)) + (clamp((_21307 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11450 + vec2(0.5), _11450 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11319 = _11314.x * frag_info.gi_visibility.z;
            highp float _11331 = abs((_11319 * _11319) - ((_11314.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11337 = (_11269 - _11319) - frag_info.gi_visibility.y;
            highp float _21308 = 0.0;
            if (_11337 <= 0.0)
            {
                _21308 = 1.0;
            }
            else
            {
                _21308 = _11331 / (_11331 + (_11337 * _11337));
            }
            _21311 = _11287 * mix(1.0, max(0.0500000007450580596923828125, (_21308 * _21308) * _21308), frag_info.gi_visibility.x);
        }
        else
        {
            _21311 = _11287;
        }
        float _11365 = max(9.9999999747524270787835121154785e-07, _21311);
        float _21312 = 0.0;
        if (_11365 < 0.20000000298023223876953125)
        {
            _21312 = _11365 * ((_11365 * _11365) * 25.0);
        }
        else
        {
            _21312 = _11365;
        }
        float _11380 = _21312 * (((_11251.x * _11251.y) * _11251.z) * mp_copy_11245);
        highp float _11539 = floor(_11428 / frag_info.gi_counts.w);
        highp vec2 _11553 = vec2((_11428 - (_11539 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11539 * 8.0));
        vec2 _21313 = vec2(0.0);
        if (_9309)
        {
            _21313 = _9306.xy;
        }
        else
        {
            _21313 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11392 = texture(irradiance_field, clamp((_11553 + vec2(1.0)) + (clamp((_21313 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11553 + vec2(0.5), _11553 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11687 = _8810 + vec3(0.0, 1.0, 1.0);
        highp vec3 _11692 = _11687 - frag_info.gi_anchor.xyz;
        bool _11695 = any(lessThan(_11692, vec3(0.0)));
        bool _11703 = false;
        if (!_11695)
        {
            _11703 = any(greaterThanEqual(_11692, frag_info.gi_counts.xyz));
        }
        else
        {
            _11703 = _11695;
        }
        vec3 mp_copy_21315 = vec3(0.0);
        highp float _11704 = _11703 ? 0.0 : 1.0;
        float mp_copy_11704 = _11704;
        vec3 _11710 = max(mix(_8952, mp_copy_8816, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11726 = (_11687 * frag_info.gi_grid.xyz) - _8805;
        highp float _11728 = length(_11726);
        highp vec3 _21315 = vec3(0.0);
        if (_11728 > 9.9999997473787516355514526367188e-06)
        {
            _21315 = _11726 / vec3(_11728);
        }
        else
        {
            _21315 = _21197;
        }
        mp_copy_21315 = _21315;
        float _11746 = pow((dot(_21315, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11871 = _11687 - (frag_info.gi_counts.xyz * floor(_11687 / frag_info.gi_counts.xyz));
        highp float _11887 = _11871.x + (frag_info.gi_counts.x * (_11871.y + (frag_info.gi_counts.y * _11871.z)));
        float _21320 = 0.0;
        if (_9003)
        {
            highp float _11895 = floor(_11887 / frag_info.gi_counts.w);
            highp vec2 _11909 = vec2((_11887 - (_11895 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11895 * 16.0));
            vec3 _11769 = -mp_copy_21315;
            vec3 _11957 = _11769 / vec3((abs(_11769.x) + abs(_11769.y)) + abs(_11769.z));
            vec2 _21316 = vec2(0.0);
            if (_11957.z >= 0.0)
            {
                _21316 = _11957.xy;
            }
            else
            {
                _21316 = (vec2(1.0) - abs(_11957.yx)) * vec2((_11957.x >= 0.0) ? 1.0 : (-1.0), (_11957.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11773 = texture(irradiance_field, clamp((_11909 + vec2(1.0)) + (clamp((_21316 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11909 + vec2(0.5), _11909 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11778 = _11773.x * frag_info.gi_visibility.z;
            highp float _11790 = abs((_11778 * _11778) - ((_11773.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11796 = (_11728 - _11778) - frag_info.gi_visibility.y;
            highp float _21317 = 0.0;
            if (_11796 <= 0.0)
            {
                _21317 = 1.0;
            }
            else
            {
                _21317 = _11790 / (_11790 + (_11796 * _11796));
            }
            _21320 = _11746 * mix(1.0, max(0.0500000007450580596923828125, (_21317 * _21317) * _21317), frag_info.gi_visibility.x);
        }
        else
        {
            _21320 = _11746;
        }
        float _11824 = max(9.9999999747524270787835121154785e-07, _21320);
        float _21321 = 0.0;
        if (_11824 < 0.20000000298023223876953125)
        {
            _21321 = _11824 * ((_11824 * _11824) * 25.0);
        }
        else
        {
            _21321 = _11824;
        }
        float _11839 = _21321 * (((_11710.x * _11710.y) * _11710.z) * mp_copy_11704);
        highp float _11998 = floor(_11887 / frag_info.gi_counts.w);
        highp vec2 _12012 = vec2((_11887 - (_11998 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11998 * 8.0));
        vec2 _21322 = vec2(0.0);
        if (_9309)
        {
            _21322 = _9306.xy;
        }
        else
        {
            _21322 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11851 = texture(irradiance_field, clamp((_12012 + vec2(1.0)) + (clamp((_21322 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12012 + vec2(0.5), _12012 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12146 = _8810 + vec3(1.0);
        highp vec3 _12151 = _12146 - frag_info.gi_anchor.xyz;
        bool _12154 = any(lessThan(_12151, vec3(0.0)));
        bool _12162 = false;
        if (!_12154)
        {
            _12162 = any(greaterThanEqual(_12151, frag_info.gi_counts.xyz));
        }
        else
        {
            _12162 = _12154;
        }
        vec3 mp_copy_21324 = vec3(0.0);
        highp float _12163 = _12162 ? 0.0 : 1.0;
        float mp_copy_12163 = _12163;
        vec3 _12169 = max(mp_copy_8816, vec3(0.001000000047497451305389404296875));
        highp vec3 _12185 = (_12146 * frag_info.gi_grid.xyz) - _8805;
        highp float _12187 = length(_12185);
        highp vec3 _21324 = vec3(0.0);
        if (_12187 > 9.9999997473787516355514526367188e-06)
        {
            _21324 = _12185 / vec3(_12187);
        }
        else
        {
            _21324 = _21197;
        }
        mp_copy_21324 = _21324;
        float _12205 = pow((dot(_21324, _21197) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12330 = _12146 - (frag_info.gi_counts.xyz * floor(_12146 / frag_info.gi_counts.xyz));
        highp float _12346 = _12330.x + (frag_info.gi_counts.x * (_12330.y + (frag_info.gi_counts.y * _12330.z)));
        float _21329 = 0.0;
        if (_9003)
        {
            highp float _12354 = floor(_12346 / frag_info.gi_counts.w);
            highp vec2 _12368 = vec2((_12346 - (_12354 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12354 * 16.0));
            vec3 _12228 = -mp_copy_21324;
            vec3 _12416 = _12228 / vec3((abs(_12228.x) + abs(_12228.y)) + abs(_12228.z));
            vec2 _21325 = vec2(0.0);
            if (_12416.z >= 0.0)
            {
                _21325 = _12416.xy;
            }
            else
            {
                _21325 = (vec2(1.0) - abs(_12416.yx)) * vec2((_12416.x >= 0.0) ? 1.0 : (-1.0), (_12416.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12232 = texture(irradiance_field, clamp((_12368 + vec2(1.0)) + (clamp((_21325 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12368 + vec2(0.5), _12368 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12237 = _12232.x * frag_info.gi_visibility.z;
            highp float _12249 = abs((_12237 * _12237) - ((_12232.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12255 = (_12187 - _12237) - frag_info.gi_visibility.y;
            highp float _21326 = 0.0;
            if (_12255 <= 0.0)
            {
                _21326 = 1.0;
            }
            else
            {
                _21326 = _12249 / (_12249 + (_12255 * _12255));
            }
            _21329 = _12205 * mix(1.0, max(0.0500000007450580596923828125, (_21326 * _21326) * _21326), frag_info.gi_visibility.x);
        }
        else
        {
            _21329 = _12205;
        }
        float _12283 = max(9.9999999747524270787835121154785e-07, _21329);
        float _21330 = 0.0;
        if (_12283 < 0.20000000298023223876953125)
        {
            _21330 = _12283 * ((_12283 * _12283) * 25.0);
        }
        else
        {
            _21330 = _12283;
        }
        float _12298 = _21330 * (((_12169.x * _12169.y) * _12169.z) * mp_copy_12163);
        highp float _12457 = floor(_12346 / frag_info.gi_counts.w);
        highp vec2 _12471 = vec2((_12346 - (_12457 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12457 * 8.0));
        vec2 _21331 = vec2(0.0);
        if (_9309)
        {
            _21331 = _9306.xy;
        }
        else
        {
            _21331 = (vec2(1.0) - abs(_9306.yx)) * vec2((_9306.x >= 0.0) ? 1.0 : (-1.0), (_9306.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _8863 = ((((((vec4(max(_9097.xyz, vec3(0.0)) * _9085, _9085) + vec4(max(_9556.xyz, vec3(0.0)) * _9544, _9544)) + vec4(max(_10015.xyz, vec3(0.0)) * _10003, _10003)) + vec4(max(_10474.xyz, vec3(0.0)) * _10462, _10462)) + vec4(max(_10933.xyz, vec3(0.0)) * _10921, _10921)) + vec4(max(_11392.xyz, vec3(0.0)) * _11380, _11380)) + vec4(max(_11851.xyz, vec3(0.0)) * _11839, _11839)) + vec4(max(texture(irradiance_field, clamp((_12471 + vec2(1.0)) + (clamp((_21331 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12471 + vec2(0.5), _12471 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _12298, _12298);
        highp float _8865 = _8863.w;
        highp vec3 _21333 = vec3(0.0);
        if (_8865 > 9.9999999747524270787835121154785e-07)
        {
            _21333 = _8863.xyz / vec3(_8865);
        }
        else
        {
            _21333 = vec3(0.0);
        }
        _21451 = mix(_7179, _21333 * _8692, vec3(_21260));
    }
    else
    {
        _21451 = _7179;
    }
    vec2 _7205 = clamp(vec2(_7117, _21233), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7207 = texture(brdf_lut, vec2(_7205.x * 0.3333333432674407958984375, _7205.y));
    float _7211 = _7207.x;
    float _7214 = _7207.y;
    vec3 _7216 = ((_7109 + ((max(vec3(1.0 - _21233), _7109) - _7109) * pow(clamp(1.0 - _7117, 0.0, 1.0), 5.0))) * _7211) + vec3(_7214);
    float _7222 = 1.0 - (_7211 + _7214);
    vec3 _7226 = vec3(1.0) - _7109;
    vec3 _7229 = _7109 + (_7226 * vec3(0.0476190485060214996337890625));
    vec3 _7240 = ((_7216 * _7222) * _7229) / (vec3(1.0) - (_7229 * _7222));
    float _7243 = 1.0 - _6148;
    vec3 _7244 = _7014 * _7243;
    float _22189 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7137)
    {
        float _12579 = max(acos(clamp(exp2(((-3.321929931640625) * _21233) * _21233), 0.0, 1.0)), 0.100000001490116119384765625);
        _22189 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_21248, _7121), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _21521, 0.0, 1.0)))) + _12579) / (2.0 * _12579), 0.0, 1.0));
    }
    else
    {
        float _22190 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _22190 = clamp((pow(_7113 + _21521, exp2(((-16.0) * _21233) - 1.0)) - 1.0) + _21521, 0.0, 1.0);
        }
        else
        {
            _22190 = _21521;
        }
        _22189 = _22190;
    }
    bool _7293 = frag_info.has_directional_light > 0.5;
    float _21643 = 0.0;
    vec3 _22273 = vec3(0.0);
    if (_7293)
    {
        highp vec3 _7299 = -normalize(frag_info.directional_light_direction.xyz);
        _22273 = _7299;
        _21643 = dot(_6015, _7299);
    }
    else
    {
        _22273 = vec3(0.0);
        _21643 = 0.0;
    }
    float _7306 = clamp(_21643 * 6.666666507720947265625, 0.0, 1.0);
    bool _7315 = false;
    if (_7293)
    {
        _7315 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _7315 = _7293;
    }
    float _21880 = 0.0;
    if (_7315 && (_7306 > 0.0))
    {
        int _12700 = int(frag_info.shadow_cascade_count);
        float _13149 = max(dot(_6015, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _13152 = _13149 * _13149;
        highp vec3 _13172 = v_position + (_6015 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _13152, 0.0)) / _13152, 8.0))));
        highp float _12706 = frag_info.directional_light_color.w * 0.5;
        float _21697 = 0.0;
        float _21737 = 0.0;
        if (_12700 > 0)
        {
            highp vec4 _12723 = frag_info.light_space_matrix[0] * vec4(_13172, 1.0);
            highp vec3 _12729 = _12723.xyz / vec3(_12723.w);
            highp vec2 _12732 = _12729.xy * 0.5;
            highp vec2 _12734 = _12732 + vec2(0.5);
            highp float _12741 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
            highp float _12743 = _12734.x;
            bool _12745 = _12743 < _12741;
            bool _12754 = false;
            if (!_12745)
            {
                _12754 = _12743 > (1.0 - _12741);
            }
            else
            {
                _12754 = _12745;
            }
            bool _12762 = false;
            if (!_12754)
            {
                _12762 = _12734.y < _12741;
            }
            else
            {
                _12762 = _12754;
            }
            bool _12771 = false;
            if (!_12762)
            {
                _12771 = _12734.y > (1.0 - _12741);
            }
            else
            {
                _12771 = _12762;
            }
            bool _12778 = false;
            if (!_12771)
            {
                _12778 = _12729.z < 0.0;
            }
            else
            {
                _12778 = _12771;
            }
            bool _12785 = false;
            if (!_12778)
            {
                _12785 = _12729.z > 1.0;
            }
            else
            {
                _12785 = _12778;
            }
            float _21698 = 0.0;
            float _21738 = 0.0;
            if (!_12785)
            {
                highp vec2 _13180 = vec2(_12741);
                highp vec2 _13185 = vec2(_12741 + max(_12706, 9.9999997473787516355514526367188e-05));
                highp vec2 _13193 = vec2(0.5) - _12732;
                highp vec2 _13195 = smoothstep(_13180, _13185, _12734) * smoothstep(_13180, _13185, _13193);
                float _21644 = 0.0;
                if (_12706 > 0.0)
                {
                    _21644 = _13195.x * _13195.y;
                }
                else
                {
                    _21644 = 1.0;
                }
                float _12794 = min(_21644, 1.0);
                bool _12796 = _12794 > 0.0;
                float _21739 = 0.0;
                if (_12796)
                {
                    highp float _13307 = _12729.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                    highp float _13313 = 1.0 / (float(_12700) + frag_info.spot_shadow_params.x);
                    highp float _13315 = frag_info.directional_light_direction.w;
                    float mp_copy_13315 = _13315;
                    float _13321 = step(0.5, mp_copy_13315) * (1.0 - step(1.5, mp_copy_13315));
                    highp float _13332 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _13321);
                    float mp_copy_13332 = _13332;
                    float _13334 = cos(mp_copy_13332);
                    float _13336 = sin(mp_copy_13332);
                    highp float _21662 = 0.0;
                    if ((_13315 > 1.5) && (_13315 < 2.5))
                    {
                        highp float _13355 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _13360 = max(_13355 * _13307, frag_info.shadow_texel_size);
                        float _21652 = 0.0;
                        highp float _21653 = 0.0;
                        _21653 = 0.0;
                        _21652 = 0.0;
                        highp float _13382 = 0.0;
                        float _13385 = 0.0;
                        for (int _21651 = 0; _21651 < 9; _21653 = _13382, _21652 = _13385, _21651++)
                        {
                            vec2 _22667 = vec2(0.0);
                            do
                            {
                                if (_21651 == 0)
                                {
                                    _22667 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21651 == 1)
                                {
                                    _22667 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21651 == 2)
                                {
                                    _22667 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21651 == 3)
                                {
                                    _22667 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21651 == 4)
                                {
                                    _22667 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21651 == 5)
                                {
                                    _22667 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21651 == 6)
                                {
                                    _22667 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21651 == 7)
                                {
                                    _22667 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21651 == 8)
                                {
                                    _22667 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21651 == 9)
                                {
                                    _22667 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21651 == 10)
                                {
                                    _22667 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21651 == 11)
                                {
                                    _22667 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21651 == 12)
                                {
                                    _22667 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21651 == 13)
                                {
                                    _22667 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21651 == 14)
                                {
                                    _22667 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21651 == 15)
                                {
                                    _22667 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22667 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _13627 = clamp(_12734 + (vec2((_22667.x * _13334) - (_22667.y * _13336), (_22667.x * _13336) + (_22667.y * _13334)) * _13360), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _13636 = _13627.y;
                            highp vec2 _13637 = vec2(_13627.x * _13313, _13636);
                            _13637.y = 1.0 - _13636;
                            highp vec4 _13644 = textureLod(shadow_map, _13637, 0.0);
                            highp float _13645 = _13644.x;
                            highp float _13377 = step(_13645, _13307);
                            float mp_copy_13377 = _13377;
                            _13382 = _21653 + (_13645 * _13377);
                            _13385 = _21652 + mp_copy_13377;
                        }
                        highp float _21654 = 0.0;
                        if (_21652 > 0.0)
                        {
                            _21654 = _21653 / _21652;
                        }
                        else
                        {
                            _21654 = _13307;
                        }
                        _21662 = clamp(_13355 * max(_13307 - _21654, 0.0), frag_info.shadow_texel_size, _12741);
                    }
                    else
                    {
                        _21662 = _12741;
                    }
                    float _21669 = 0.0;
                    if (_13315 > 2.5)
                    {
                        highp vec2 _13673 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _13677 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _13678 = clamp(_12734 + (vec2(-0.707099974155426025390625) * _21662), _13673, _13677);
                        highp vec2 _13689 = (vec2(_13678.x, 1.0 - _13678.y) / _13673) - vec2(0.5);
                        highp vec2 _13691 = floor(_13689);
                        highp vec2 _13694 = _13689 - _13691;
                        highp vec2 _13699 = (_13691 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13709 = vec2(_13699.x * _13313, _13699.y);
                        highp float _13713 = frag_info.shadow_texel_size * _13313;
                        highp vec2 _13716 = vec2(_13713, frag_info.shadow_texel_size);
                        highp vec2 _13725 = vec2(_13713, 0.0);
                        highp vec2 _13733 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _13762 = _13694.x;
                        highp float _13771 = mix(mix(float(_13307 <= textureLod(shadow_map, _13709, 0.0).x), float(_13307 <= textureLod(shadow_map, _13709 + _13725, 0.0).x), _13762), mix(float(_13307 <= textureLod(shadow_map, _13709 + _13733, 0.0).x), float(_13307 <= textureLod(shadow_map, _13709 + _13716, 0.0).x), _13762), _13694.y);
                        float mp_copy_13771 = _13771;
                        highp vec2 _13805 = clamp(_12734 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21662), _13673, _13677);
                        highp vec2 _13816 = (vec2(_13805.x, 1.0 - _13805.y) / _13673) - vec2(0.5);
                        highp vec2 _13818 = floor(_13816);
                        highp vec2 _13821 = _13816 - _13818;
                        highp vec2 _13826 = (_13818 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13836 = vec2(_13826.x * _13313, _13826.y);
                        highp float _13889 = _13821.x;
                        highp float _13898 = mix(mix(float(_13307 <= textureLod(shadow_map, _13836, 0.0).x), float(_13307 <= textureLod(shadow_map, _13836 + _13725, 0.0).x), _13889), mix(float(_13307 <= textureLod(shadow_map, _13836 + _13733, 0.0).x), float(_13307 <= textureLod(shadow_map, _13836 + _13716, 0.0).x), _13889), _13821.y);
                        float mp_copy_13898 = _13898;
                        highp vec2 _13932 = clamp(_12734 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21662), _13673, _13677);
                        highp vec2 _13943 = (vec2(_13932.x, 1.0 - _13932.y) / _13673) - vec2(0.5);
                        highp vec2 _13945 = floor(_13943);
                        highp vec2 _13948 = _13943 - _13945;
                        highp vec2 _13953 = (_13945 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13963 = vec2(_13953.x * _13313, _13953.y);
                        highp float _14016 = _13948.x;
                        highp float _14025 = mix(mix(float(_13307 <= textureLod(shadow_map, _13963, 0.0).x), float(_13307 <= textureLod(shadow_map, _13963 + _13725, 0.0).x), _14016), mix(float(_13307 <= textureLod(shadow_map, _13963 + _13733, 0.0).x), float(_13307 <= textureLod(shadow_map, _13963 + _13716, 0.0).x), _14016), _13948.y);
                        float mp_copy_14025 = _14025;
                        highp vec2 _14059 = clamp(_12734 + (vec2(0.707099974155426025390625) * _21662), _13673, _13677);
                        highp vec2 _14070 = (vec2(_14059.x, 1.0 - _14059.y) / _13673) - vec2(0.5);
                        highp vec2 _14072 = floor(_14070);
                        highp vec2 _14075 = _14070 - _14072;
                        highp vec2 _14080 = (_14072 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14090 = vec2(_14080.x * _13313, _14080.y);
                        highp float _14143 = _14075.x;
                        highp float _14152 = mix(mix(float(_13307 <= textureLod(shadow_map, _14090, 0.0).x), float(_13307 <= textureLod(shadow_map, _14090 + _13725, 0.0).x), _14143), mix(float(_13307 <= textureLod(shadow_map, _14090 + _13733, 0.0).x), float(_13307 <= textureLod(shadow_map, _14090 + _13716, 0.0).x), _14143), _14075.y);
                        float mp_copy_14152 = _14152;
                        _21669 = (((mp_copy_13771 + mp_copy_13898) + mp_copy_14025) + mp_copy_14152) * 0.25;
                    }
                    else
                    {
                        int _13448 = (_13321 > 0.5) ? 17 : 16;
                        float _21665 = 0.0;
                        _21665 = 0.0;
                        float _13476 = 0.0;
                        for (int _21655 = 0; _21655 < 17; _21665 = _13476, _21655++)
                        {
                            if (_21655 >= _13448)
                            {
                                break;
                            }
                            vec2 _21656 = vec2(0.0);
                            do
                            {
                                if (_21655 == 0)
                                {
                                    _21656 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21655 == 1)
                                {
                                    _21656 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21655 == 2)
                                {
                                    _21656 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21655 == 3)
                                {
                                    _21656 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21655 == 4)
                                {
                                    _21656 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21655 == 5)
                                {
                                    _21656 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21655 == 6)
                                {
                                    _21656 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21655 == 7)
                                {
                                    _21656 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21655 == 8)
                                {
                                    _21656 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21655 == 9)
                                {
                                    _21656 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21655 == 10)
                                {
                                    _21656 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21655 == 11)
                                {
                                    _21656 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21655 == 12)
                                {
                                    _21656 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21655 == 13)
                                {
                                    _21656 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21655 == 14)
                                {
                                    _21656 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21655 == 15)
                                {
                                    _21656 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21656 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21658 = vec2(0.0);
                            do
                            {
                                if (_21655 < 3)
                                {
                                    _21658 = vec2(float(_21655) - 1.0, -1.0);
                                    break;
                                }
                                if (_21655 < 6)
                                {
                                    _21658 = vec2((float(_21655 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21655 < 11)
                                {
                                    _21658 = vec2((float(_21655 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21655 < 14)
                                {
                                    _21658 = vec2((float(_21655 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21658 = vec2(float(_21655 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _13465 = mix(_21656, _21658, vec2(_13321));
                            float _14292 = _13465.x;
                            float _14296 = _13465.y;
                            highp vec2 _14322 = clamp(_12734 + (vec2((_14292 * _13334) - (_14296 * _13336), (_14292 * _13336) + (_14296 * _13334)) * _21662), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _14332 = vec2(_14322.x * _13313, _14322.y);
                            _14332.y = 1.0 - _14322.y;
                            highp float _14344 = float(_13307 <= textureLod(shadow_map, _14332, 0.0).x);
                            float mp_copy_14344 = _14344;
                            _13476 = _21665 + mp_copy_14344;
                        }
                        _21669 = _21665 / float(_13448);
                    }
                    bool _13489 = 0 == (_12700 - 1);
                    bool _13495 = false;
                    if (_13489)
                    {
                        _13495 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _13495 = _13489;
                    }
                    float _21670 = 0.0;
                    if (_13495)
                    {
                        highp vec2 _13502 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                        highp vec2 _13510 = smoothstep(vec2(0.0), _13502, _12734) * smoothstep(vec2(0.0), _13502, _13193);
                        _21670 = mix(1.0, _21669, _13510.x * _13510.y);
                    }
                    else
                    {
                        _21670 = _21669;
                    }
                    _21739 = _12794 * _21670;
                }
                else
                {
                    _21739 = 0.0;
                }
                _21738 = _21739;
                _21698 = _12796 ? _12794 : 0.0;
            }
            else
            {
                _21738 = 0.0;
                _21698 = 0.0;
            }
            _21737 = _21738;
            _21697 = _21698;
        }
        else
        {
            _21737 = 0.0;
            _21697 = 0.0;
        }
        float _21756 = 0.0;
        float _21796 = 0.0;
        if ((_21697 < 1.0) && (_12700 > 1))
        {
            highp vec4 _12829 = frag_info.light_space_matrix[1] * vec4(_13172, 1.0);
            highp vec3 _12835 = _12829.xyz / vec3(_12829.w);
            highp vec2 _12838 = _12835.xy * 0.5;
            highp vec2 _12840 = _12838 + vec2(0.5);
            highp float _12847 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
            highp float _12849 = _12840.x;
            bool _12851 = _12849 < _12847;
            bool _12860 = false;
            if (!_12851)
            {
                _12860 = _12849 > (1.0 - _12847);
            }
            else
            {
                _12860 = _12851;
            }
            bool _12868 = false;
            if (!_12860)
            {
                _12868 = _12840.y < _12847;
            }
            else
            {
                _12868 = _12860;
            }
            bool _12877 = false;
            if (!_12868)
            {
                _12877 = _12840.y > (1.0 - _12847);
            }
            else
            {
                _12877 = _12868;
            }
            bool _12884 = false;
            if (!_12877)
            {
                _12884 = _12835.z < 0.0;
            }
            else
            {
                _12884 = _12877;
            }
            bool _12891 = false;
            if (!_12884)
            {
                _12891 = _12835.z > 1.0;
            }
            else
            {
                _12891 = _12884;
            }
            float _21757 = 0.0;
            float _21797 = 0.0;
            if (!_12891)
            {
                highp vec2 _14352 = vec2(_12847);
                highp vec2 _14357 = vec2(_12847 + max(_12706, 9.9999997473787516355514526367188e-05));
                highp vec2 _14365 = vec2(0.5) - _12838;
                highp vec2 _14367 = smoothstep(_14352, _14357, _12840) * smoothstep(_14352, _14357, _14365);
                float _21700 = 0.0;
                if (_12706 > 0.0)
                {
                    _21700 = _14367.x * _14367.y;
                }
                else
                {
                    _21700 = 1.0;
                }
                float _12900 = min(_21700, 1.0 - _21697);
                float _21758 = 0.0;
                float _21798 = 0.0;
                if (_12900 > 0.0)
                {
                    highp float _14479 = _12835.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                    highp float _14485 = 1.0 / (float(_12700) + frag_info.spot_shadow_params.x);
                    highp float _14487 = frag_info.directional_light_direction.w;
                    float mp_copy_14487 = _14487;
                    float _14493 = step(0.5, mp_copy_14487) * (1.0 - step(1.5, mp_copy_14487));
                    highp float _14504 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14493);
                    float mp_copy_14504 = _14504;
                    float _14506 = cos(mp_copy_14504);
                    float _14508 = sin(mp_copy_14504);
                    highp float _21718 = 0.0;
                    if ((_14487 > 1.5) && (_14487 < 2.5))
                    {
                        highp float _14527 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _14532 = max(_14527 * _14479, frag_info.shadow_texel_size);
                        float _21708 = 0.0;
                        highp float _21709 = 0.0;
                        _21709 = 0.0;
                        _21708 = 0.0;
                        highp float _14554 = 0.0;
                        float _14557 = 0.0;
                        for (int _21707 = 0; _21707 < 9; _21709 = _14554, _21708 = _14557, _21707++)
                        {
                            vec2 _22663 = vec2(0.0);
                            do
                            {
                                if (_21707 == 0)
                                {
                                    _22663 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21707 == 1)
                                {
                                    _22663 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21707 == 2)
                                {
                                    _22663 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21707 == 3)
                                {
                                    _22663 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21707 == 4)
                                {
                                    _22663 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21707 == 5)
                                {
                                    _22663 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21707 == 6)
                                {
                                    _22663 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21707 == 7)
                                {
                                    _22663 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21707 == 8)
                                {
                                    _22663 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21707 == 9)
                                {
                                    _22663 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21707 == 10)
                                {
                                    _22663 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21707 == 11)
                                {
                                    _22663 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21707 == 12)
                                {
                                    _22663 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21707 == 13)
                                {
                                    _22663 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21707 == 14)
                                {
                                    _22663 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21707 == 15)
                                {
                                    _22663 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22663 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _14799 = clamp(_12840 + (vec2((_22663.x * _14506) - (_22663.y * _14508), (_22663.x * _14508) + (_22663.y * _14506)) * _14532), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _14808 = _14799.y;
                            highp vec2 _14809 = vec2((1.0 + _14799.x) * _14485, _14808);
                            _14809.y = 1.0 - _14808;
                            highp vec4 _14816 = textureLod(shadow_map, _14809, 0.0);
                            highp float _14817 = _14816.x;
                            highp float _14549 = step(_14817, _14479);
                            float mp_copy_14549 = _14549;
                            _14554 = _21709 + (_14817 * _14549);
                            _14557 = _21708 + mp_copy_14549;
                        }
                        highp float _21710 = 0.0;
                        if (_21708 > 0.0)
                        {
                            _21710 = _21709 / _21708;
                        }
                        else
                        {
                            _21710 = _14479;
                        }
                        _21718 = clamp(_14527 * max(_14479 - _21710, 0.0), frag_info.shadow_texel_size, _12847);
                    }
                    else
                    {
                        _21718 = _12847;
                    }
                    float _21725 = 0.0;
                    if (_14487 > 2.5)
                    {
                        highp vec2 _14845 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _14849 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _14850 = clamp(_12840 + (vec2(-0.707099974155426025390625) * _21718), _14845, _14849);
                        highp vec2 _14861 = (vec2(_14850.x, 1.0 - _14850.y) / _14845) - vec2(0.5);
                        highp vec2 _14863 = floor(_14861);
                        highp vec2 _14866 = _14861 - _14863;
                        highp vec2 _14871 = (_14863 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14881 = vec2((1.0 + _14871.x) * _14485, _14871.y);
                        highp float _14885 = frag_info.shadow_texel_size * _14485;
                        highp vec2 _14888 = vec2(_14885, frag_info.shadow_texel_size);
                        highp vec2 _14897 = vec2(_14885, 0.0);
                        highp vec2 _14905 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _14934 = _14866.x;
                        highp float _14943 = mix(mix(float(_14479 <= textureLod(shadow_map, _14881, 0.0).x), float(_14479 <= textureLod(shadow_map, _14881 + _14897, 0.0).x), _14934), mix(float(_14479 <= textureLod(shadow_map, _14881 + _14905, 0.0).x), float(_14479 <= textureLod(shadow_map, _14881 + _14888, 0.0).x), _14934), _14866.y);
                        float mp_copy_14943 = _14943;
                        highp vec2 _14977 = clamp(_12840 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21718), _14845, _14849);
                        highp vec2 _14988 = (vec2(_14977.x, 1.0 - _14977.y) / _14845) - vec2(0.5);
                        highp vec2 _14990 = floor(_14988);
                        highp vec2 _14993 = _14988 - _14990;
                        highp vec2 _14998 = (_14990 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15008 = vec2((1.0 + _14998.x) * _14485, _14998.y);
                        highp float _15061 = _14993.x;
                        highp float _15070 = mix(mix(float(_14479 <= textureLod(shadow_map, _15008, 0.0).x), float(_14479 <= textureLod(shadow_map, _15008 + _14897, 0.0).x), _15061), mix(float(_14479 <= textureLod(shadow_map, _15008 + _14905, 0.0).x), float(_14479 <= textureLod(shadow_map, _15008 + _14888, 0.0).x), _15061), _14993.y);
                        float mp_copy_15070 = _15070;
                        highp vec2 _15104 = clamp(_12840 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21718), _14845, _14849);
                        highp vec2 _15115 = (vec2(_15104.x, 1.0 - _15104.y) / _14845) - vec2(0.5);
                        highp vec2 _15117 = floor(_15115);
                        highp vec2 _15120 = _15115 - _15117;
                        highp vec2 _15125 = (_15117 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15135 = vec2((1.0 + _15125.x) * _14485, _15125.y);
                        highp float _15188 = _15120.x;
                        highp float _15197 = mix(mix(float(_14479 <= textureLod(shadow_map, _15135, 0.0).x), float(_14479 <= textureLod(shadow_map, _15135 + _14897, 0.0).x), _15188), mix(float(_14479 <= textureLod(shadow_map, _15135 + _14905, 0.0).x), float(_14479 <= textureLod(shadow_map, _15135 + _14888, 0.0).x), _15188), _15120.y);
                        float mp_copy_15197 = _15197;
                        highp vec2 _15231 = clamp(_12840 + (vec2(0.707099974155426025390625) * _21718), _14845, _14849);
                        highp vec2 _15242 = (vec2(_15231.x, 1.0 - _15231.y) / _14845) - vec2(0.5);
                        highp vec2 _15244 = floor(_15242);
                        highp vec2 _15247 = _15242 - _15244;
                        highp vec2 _15252 = (_15244 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15262 = vec2((1.0 + _15252.x) * _14485, _15252.y);
                        highp float _15315 = _15247.x;
                        highp float _15324 = mix(mix(float(_14479 <= textureLod(shadow_map, _15262, 0.0).x), float(_14479 <= textureLod(shadow_map, _15262 + _14897, 0.0).x), _15315), mix(float(_14479 <= textureLod(shadow_map, _15262 + _14905, 0.0).x), float(_14479 <= textureLod(shadow_map, _15262 + _14888, 0.0).x), _15315), _15247.y);
                        float mp_copy_15324 = _15324;
                        _21725 = (((mp_copy_14943 + mp_copy_15070) + mp_copy_15197) + mp_copy_15324) * 0.25;
                    }
                    else
                    {
                        int _14620 = (_14493 > 0.5) ? 17 : 16;
                        float _21721 = 0.0;
                        _21721 = 0.0;
                        float _14648 = 0.0;
                        for (int _21711 = 0; _21711 < 17; _21721 = _14648, _21711++)
                        {
                            if (_21711 >= _14620)
                            {
                                break;
                            }
                            vec2 _21712 = vec2(0.0);
                            do
                            {
                                if (_21711 == 0)
                                {
                                    _21712 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21711 == 1)
                                {
                                    _21712 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21711 == 2)
                                {
                                    _21712 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21711 == 3)
                                {
                                    _21712 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21711 == 4)
                                {
                                    _21712 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21711 == 5)
                                {
                                    _21712 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21711 == 6)
                                {
                                    _21712 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21711 == 7)
                                {
                                    _21712 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21711 == 8)
                                {
                                    _21712 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21711 == 9)
                                {
                                    _21712 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21711 == 10)
                                {
                                    _21712 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21711 == 11)
                                {
                                    _21712 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21711 == 12)
                                {
                                    _21712 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21711 == 13)
                                {
                                    _21712 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21711 == 14)
                                {
                                    _21712 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21711 == 15)
                                {
                                    _21712 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21712 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21714 = vec2(0.0);
                            do
                            {
                                if (_21711 < 3)
                                {
                                    _21714 = vec2(float(_21711) - 1.0, -1.0);
                                    break;
                                }
                                if (_21711 < 6)
                                {
                                    _21714 = vec2((float(_21711 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21711 < 11)
                                {
                                    _21714 = vec2((float(_21711 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21711 < 14)
                                {
                                    _21714 = vec2((float(_21711 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21714 = vec2(float(_21711 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _14637 = mix(_21712, _21714, vec2(_14493));
                            float _15464 = _14637.x;
                            float _15468 = _14637.y;
                            highp vec2 _15494 = clamp(_12840 + (vec2((_15464 * _14506) - (_15468 * _14508), (_15464 * _14508) + (_15468 * _14506)) * _21718), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _15504 = vec2((1.0 + _15494.x) * _14485, _15494.y);
                            _15504.y = 1.0 - _15494.y;
                            highp float _15516 = float(_14479 <= textureLod(shadow_map, _15504, 0.0).x);
                            float mp_copy_15516 = _15516;
                            _14648 = _21721 + mp_copy_15516;
                        }
                        _21725 = _21721 / float(_14620);
                    }
                    bool _14661 = 1 == (_12700 - 1);
                    bool _14667 = false;
                    if (_14661)
                    {
                        _14667 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _14667 = _14661;
                    }
                    float _21726 = 0.0;
                    if (_14667)
                    {
                        highp vec2 _14674 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                        highp vec2 _14682 = smoothstep(vec2(0.0), _14674, _12840) * smoothstep(vec2(0.0), _14674, _14365);
                        _21726 = mix(1.0, _21725, _14682.x * _14682.y);
                    }
                    else
                    {
                        _21726 = _21725;
                    }
                    _21798 = _21737 + (_12900 * _21726);
                    _21758 = _21697 + _12900;
                }
                else
                {
                    _21798 = _21737;
                    _21758 = _21697;
                }
                _21797 = _21798;
                _21757 = _21758;
            }
            else
            {
                _21797 = _21737;
                _21757 = _21697;
            }
            _21796 = _21797;
            _21756 = _21757;
        }
        else
        {
            _21796 = _21737;
            _21756 = _21697;
        }
        float _21815 = 0.0;
        float _21855 = 0.0;
        if ((_21756 < 1.0) && (_12700 > 2))
        {
            highp vec4 _12935 = frag_info.light_space_matrix[2] * vec4(_13172, 1.0);
            highp vec3 _12941 = _12935.xyz / vec3(_12935.w);
            highp vec2 _12944 = _12941.xy * 0.5;
            highp vec2 _12946 = _12944 + vec2(0.5);
            highp float _12953 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
            highp float _12955 = _12946.x;
            bool _12957 = _12955 < _12953;
            bool _12966 = false;
            if (!_12957)
            {
                _12966 = _12955 > (1.0 - _12953);
            }
            else
            {
                _12966 = _12957;
            }
            bool _12974 = false;
            if (!_12966)
            {
                _12974 = _12946.y < _12953;
            }
            else
            {
                _12974 = _12966;
            }
            bool _12983 = false;
            if (!_12974)
            {
                _12983 = _12946.y > (1.0 - _12953);
            }
            else
            {
                _12983 = _12974;
            }
            bool _12990 = false;
            if (!_12983)
            {
                _12990 = _12941.z < 0.0;
            }
            else
            {
                _12990 = _12983;
            }
            bool _12997 = false;
            if (!_12990)
            {
                _12997 = _12941.z > 1.0;
            }
            else
            {
                _12997 = _12990;
            }
            float _21816 = 0.0;
            float _21856 = 0.0;
            if (!_12997)
            {
                highp vec2 _15524 = vec2(_12953);
                highp vec2 _15529 = vec2(_12953 + max(_12706, 9.9999997473787516355514526367188e-05));
                highp vec2 _15537 = vec2(0.5) - _12944;
                highp vec2 _15539 = smoothstep(_15524, _15529, _12946) * smoothstep(_15524, _15529, _15537);
                float _21759 = 0.0;
                if (_12706 > 0.0)
                {
                    _21759 = _15539.x * _15539.y;
                }
                else
                {
                    _21759 = 1.0;
                }
                float _13006 = min(_21759, 1.0 - _21756);
                float _21817 = 0.0;
                float _21857 = 0.0;
                if (_13006 > 0.0)
                {
                    highp float _15651 = _12941.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                    highp float _15657 = 1.0 / (float(_12700) + frag_info.spot_shadow_params.x);
                    highp float _15659 = frag_info.directional_light_direction.w;
                    float mp_copy_15659 = _15659;
                    float _15665 = step(0.5, mp_copy_15659) * (1.0 - step(1.5, mp_copy_15659));
                    highp float _15676 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _15665);
                    float mp_copy_15676 = _15676;
                    float _15678 = cos(mp_copy_15676);
                    float _15680 = sin(mp_copy_15676);
                    highp float _21777 = 0.0;
                    if ((_15659 > 1.5) && (_15659 < 2.5))
                    {
                        highp float _15699 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _15704 = max(_15699 * _15651, frag_info.shadow_texel_size);
                        float _21767 = 0.0;
                        highp float _21768 = 0.0;
                        _21768 = 0.0;
                        _21767 = 0.0;
                        highp float _15726 = 0.0;
                        float _15729 = 0.0;
                        for (int _21766 = 0; _21766 < 9; _21768 = _15726, _21767 = _15729, _21766++)
                        {
                            vec2 _22659 = vec2(0.0);
                            do
                            {
                                if (_21766 == 0)
                                {
                                    _22659 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21766 == 1)
                                {
                                    _22659 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21766 == 2)
                                {
                                    _22659 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21766 == 3)
                                {
                                    _22659 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21766 == 4)
                                {
                                    _22659 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21766 == 5)
                                {
                                    _22659 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21766 == 6)
                                {
                                    _22659 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21766 == 7)
                                {
                                    _22659 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21766 == 8)
                                {
                                    _22659 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21766 == 9)
                                {
                                    _22659 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21766 == 10)
                                {
                                    _22659 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21766 == 11)
                                {
                                    _22659 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21766 == 12)
                                {
                                    _22659 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21766 == 13)
                                {
                                    _22659 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21766 == 14)
                                {
                                    _22659 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21766 == 15)
                                {
                                    _22659 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22659 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _15971 = clamp(_12946 + (vec2((_22659.x * _15678) - (_22659.y * _15680), (_22659.x * _15680) + (_22659.y * _15678)) * _15704), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _15980 = _15971.y;
                            highp vec2 _15981 = vec2((2.0 + _15971.x) * _15657, _15980);
                            _15981.y = 1.0 - _15980;
                            highp vec4 _15988 = textureLod(shadow_map, _15981, 0.0);
                            highp float _15989 = _15988.x;
                            highp float _15721 = step(_15989, _15651);
                            float mp_copy_15721 = _15721;
                            _15726 = _21768 + (_15989 * _15721);
                            _15729 = _21767 + mp_copy_15721;
                        }
                        highp float _21769 = 0.0;
                        if (_21767 > 0.0)
                        {
                            _21769 = _21768 / _21767;
                        }
                        else
                        {
                            _21769 = _15651;
                        }
                        _21777 = clamp(_15699 * max(_15651 - _21769, 0.0), frag_info.shadow_texel_size, _12953);
                    }
                    else
                    {
                        _21777 = _12953;
                    }
                    float _21784 = 0.0;
                    if (_15659 > 2.5)
                    {
                        highp vec2 _16017 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _16021 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _16022 = clamp(_12946 + (vec2(-0.707099974155426025390625) * _21777), _16017, _16021);
                        highp vec2 _16033 = (vec2(_16022.x, 1.0 - _16022.y) / _16017) - vec2(0.5);
                        highp vec2 _16035 = floor(_16033);
                        highp vec2 _16038 = _16033 - _16035;
                        highp vec2 _16043 = (_16035 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16053 = vec2((2.0 + _16043.x) * _15657, _16043.y);
                        highp float _16057 = frag_info.shadow_texel_size * _15657;
                        highp vec2 _16060 = vec2(_16057, frag_info.shadow_texel_size);
                        highp vec2 _16069 = vec2(_16057, 0.0);
                        highp vec2 _16077 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _16106 = _16038.x;
                        highp float _16115 = mix(mix(float(_15651 <= textureLod(shadow_map, _16053, 0.0).x), float(_15651 <= textureLod(shadow_map, _16053 + _16069, 0.0).x), _16106), mix(float(_15651 <= textureLod(shadow_map, _16053 + _16077, 0.0).x), float(_15651 <= textureLod(shadow_map, _16053 + _16060, 0.0).x), _16106), _16038.y);
                        float mp_copy_16115 = _16115;
                        highp vec2 _16149 = clamp(_12946 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21777), _16017, _16021);
                        highp vec2 _16160 = (vec2(_16149.x, 1.0 - _16149.y) / _16017) - vec2(0.5);
                        highp vec2 _16162 = floor(_16160);
                        highp vec2 _16165 = _16160 - _16162;
                        highp vec2 _16170 = (_16162 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16180 = vec2((2.0 + _16170.x) * _15657, _16170.y);
                        highp float _16233 = _16165.x;
                        highp float _16242 = mix(mix(float(_15651 <= textureLod(shadow_map, _16180, 0.0).x), float(_15651 <= textureLod(shadow_map, _16180 + _16069, 0.0).x), _16233), mix(float(_15651 <= textureLod(shadow_map, _16180 + _16077, 0.0).x), float(_15651 <= textureLod(shadow_map, _16180 + _16060, 0.0).x), _16233), _16165.y);
                        float mp_copy_16242 = _16242;
                        highp vec2 _16276 = clamp(_12946 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21777), _16017, _16021);
                        highp vec2 _16287 = (vec2(_16276.x, 1.0 - _16276.y) / _16017) - vec2(0.5);
                        highp vec2 _16289 = floor(_16287);
                        highp vec2 _16292 = _16287 - _16289;
                        highp vec2 _16297 = (_16289 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16307 = vec2((2.0 + _16297.x) * _15657, _16297.y);
                        highp float _16360 = _16292.x;
                        highp float _16369 = mix(mix(float(_15651 <= textureLod(shadow_map, _16307, 0.0).x), float(_15651 <= textureLod(shadow_map, _16307 + _16069, 0.0).x), _16360), mix(float(_15651 <= textureLod(shadow_map, _16307 + _16077, 0.0).x), float(_15651 <= textureLod(shadow_map, _16307 + _16060, 0.0).x), _16360), _16292.y);
                        float mp_copy_16369 = _16369;
                        highp vec2 _16403 = clamp(_12946 + (vec2(0.707099974155426025390625) * _21777), _16017, _16021);
                        highp vec2 _16414 = (vec2(_16403.x, 1.0 - _16403.y) / _16017) - vec2(0.5);
                        highp vec2 _16416 = floor(_16414);
                        highp vec2 _16419 = _16414 - _16416;
                        highp vec2 _16424 = (_16416 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16434 = vec2((2.0 + _16424.x) * _15657, _16424.y);
                        highp float _16487 = _16419.x;
                        highp float _16496 = mix(mix(float(_15651 <= textureLod(shadow_map, _16434, 0.0).x), float(_15651 <= textureLod(shadow_map, _16434 + _16069, 0.0).x), _16487), mix(float(_15651 <= textureLod(shadow_map, _16434 + _16077, 0.0).x), float(_15651 <= textureLod(shadow_map, _16434 + _16060, 0.0).x), _16487), _16419.y);
                        float mp_copy_16496 = _16496;
                        _21784 = (((mp_copy_16115 + mp_copy_16242) + mp_copy_16369) + mp_copy_16496) * 0.25;
                    }
                    else
                    {
                        int _15792 = (_15665 > 0.5) ? 17 : 16;
                        float _21780 = 0.0;
                        _21780 = 0.0;
                        float _15820 = 0.0;
                        for (int _21770 = 0; _21770 < 17; _21780 = _15820, _21770++)
                        {
                            if (_21770 >= _15792)
                            {
                                break;
                            }
                            vec2 _21771 = vec2(0.0);
                            do
                            {
                                if (_21770 == 0)
                                {
                                    _21771 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21770 == 1)
                                {
                                    _21771 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21770 == 2)
                                {
                                    _21771 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21770 == 3)
                                {
                                    _21771 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21770 == 4)
                                {
                                    _21771 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21770 == 5)
                                {
                                    _21771 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21770 == 6)
                                {
                                    _21771 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21770 == 7)
                                {
                                    _21771 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21770 == 8)
                                {
                                    _21771 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21770 == 9)
                                {
                                    _21771 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21770 == 10)
                                {
                                    _21771 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21770 == 11)
                                {
                                    _21771 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21770 == 12)
                                {
                                    _21771 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21770 == 13)
                                {
                                    _21771 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21770 == 14)
                                {
                                    _21771 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21770 == 15)
                                {
                                    _21771 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21771 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21773 = vec2(0.0);
                            do
                            {
                                if (_21770 < 3)
                                {
                                    _21773 = vec2(float(_21770) - 1.0, -1.0);
                                    break;
                                }
                                if (_21770 < 6)
                                {
                                    _21773 = vec2((float(_21770 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21770 < 11)
                                {
                                    _21773 = vec2((float(_21770 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21770 < 14)
                                {
                                    _21773 = vec2((float(_21770 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21773 = vec2(float(_21770 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _15809 = mix(_21771, _21773, vec2(_15665));
                            float _16636 = _15809.x;
                            float _16640 = _15809.y;
                            highp vec2 _16666 = clamp(_12946 + (vec2((_16636 * _15678) - (_16640 * _15680), (_16636 * _15680) + (_16640 * _15678)) * _21777), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _16676 = vec2((2.0 + _16666.x) * _15657, _16666.y);
                            _16676.y = 1.0 - _16666.y;
                            highp float _16688 = float(_15651 <= textureLod(shadow_map, _16676, 0.0).x);
                            float mp_copy_16688 = _16688;
                            _15820 = _21780 + mp_copy_16688;
                        }
                        _21784 = _21780 / float(_15792);
                    }
                    bool _15833 = 2 == (_12700 - 1);
                    bool _15839 = false;
                    if (_15833)
                    {
                        _15839 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _15839 = _15833;
                    }
                    float _21785 = 0.0;
                    if (_15839)
                    {
                        highp vec2 _15846 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                        highp vec2 _15854 = smoothstep(vec2(0.0), _15846, _12946) * smoothstep(vec2(0.0), _15846, _15537);
                        _21785 = mix(1.0, _21784, _15854.x * _15854.y);
                    }
                    else
                    {
                        _21785 = _21784;
                    }
                    _21857 = _21796 + (_13006 * _21785);
                    _21817 = _21756 + _13006;
                }
                else
                {
                    _21857 = _21796;
                    _21817 = _21756;
                }
                _21856 = _21857;
                _21816 = _21817;
            }
            else
            {
                _21856 = _21796;
                _21816 = _21756;
            }
            _21855 = _21856;
            _21815 = _21816;
        }
        else
        {
            _21855 = _21796;
            _21815 = _21756;
        }
        float _21874 = 0.0;
        float _21877 = 0.0;
        if ((_21815 < 1.0) && (_12700 > 3))
        {
            highp vec4 _13041 = frag_info.light_space_matrix[3] * vec4(_13172, 1.0);
            highp vec3 _13047 = _13041.xyz / vec3(_13041.w);
            highp vec2 _13050 = _13047.xy * 0.5;
            highp vec2 _13052 = _13050 + vec2(0.5);
            highp float _13059 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
            highp float _13061 = _13052.x;
            bool _13063 = _13061 < _13059;
            bool _13072 = false;
            if (!_13063)
            {
                _13072 = _13061 > (1.0 - _13059);
            }
            else
            {
                _13072 = _13063;
            }
            bool _13080 = false;
            if (!_13072)
            {
                _13080 = _13052.y < _13059;
            }
            else
            {
                _13080 = _13072;
            }
            bool _13089 = false;
            if (!_13080)
            {
                _13089 = _13052.y > (1.0 - _13059);
            }
            else
            {
                _13089 = _13080;
            }
            bool _13096 = false;
            if (!_13089)
            {
                _13096 = _13047.z < 0.0;
            }
            else
            {
                _13096 = _13089;
            }
            bool _13103 = false;
            if (!_13096)
            {
                _13103 = _13047.z > 1.0;
            }
            else
            {
                _13103 = _13096;
            }
            float _21875 = 0.0;
            float _21878 = 0.0;
            if (!_13103)
            {
                highp vec2 _16696 = vec2(_13059);
                highp vec2 _16701 = vec2(_13059 + max(_12706, 9.9999997473787516355514526367188e-05));
                highp vec2 _16709 = vec2(0.5) - _13050;
                highp vec2 _16711 = smoothstep(_16696, _16701, _13052) * smoothstep(_16696, _16701, _16709);
                float _21818 = 0.0;
                if (_12706 > 0.0)
                {
                    _21818 = _16711.x * _16711.y;
                }
                else
                {
                    _21818 = 1.0;
                }
                float _13112 = min(_21818, 1.0 - _21815);
                float _21876 = 0.0;
                float _21879 = 0.0;
                if (_13112 > 0.0)
                {
                    highp float _16823 = _13047.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                    highp float _16829 = 1.0 / (float(_12700) + frag_info.spot_shadow_params.x);
                    highp float _16831 = frag_info.directional_light_direction.w;
                    float mp_copy_16831 = _16831;
                    float _16837 = step(0.5, mp_copy_16831) * (1.0 - step(1.5, mp_copy_16831));
                    highp float _16848 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16837);
                    float mp_copy_16848 = _16848;
                    float _16850 = cos(mp_copy_16848);
                    float _16852 = sin(mp_copy_16848);
                    highp float _21836 = 0.0;
                    if ((_16831 > 1.5) && (_16831 < 2.5))
                    {
                        highp float _16871 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _16876 = max(_16871 * _16823, frag_info.shadow_texel_size);
                        float _21826 = 0.0;
                        highp float _21827 = 0.0;
                        _21827 = 0.0;
                        _21826 = 0.0;
                        highp float _16898 = 0.0;
                        float _16901 = 0.0;
                        for (int _21825 = 0; _21825 < 9; _21827 = _16898, _21826 = _16901, _21825++)
                        {
                            vec2 _22655 = vec2(0.0);
                            do
                            {
                                if (_21825 == 0)
                                {
                                    _22655 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21825 == 1)
                                {
                                    _22655 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21825 == 2)
                                {
                                    _22655 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21825 == 3)
                                {
                                    _22655 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21825 == 4)
                                {
                                    _22655 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21825 == 5)
                                {
                                    _22655 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21825 == 6)
                                {
                                    _22655 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21825 == 7)
                                {
                                    _22655 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21825 == 8)
                                {
                                    _22655 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21825 == 9)
                                {
                                    _22655 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21825 == 10)
                                {
                                    _22655 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21825 == 11)
                                {
                                    _22655 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21825 == 12)
                                {
                                    _22655 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21825 == 13)
                                {
                                    _22655 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21825 == 14)
                                {
                                    _22655 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21825 == 15)
                                {
                                    _22655 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22655 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _17143 = clamp(_13052 + (vec2((_22655.x * _16850) - (_22655.y * _16852), (_22655.x * _16852) + (_22655.y * _16850)) * _16876), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _17152 = _17143.y;
                            highp vec2 _17153 = vec2((3.0 + _17143.x) * _16829, _17152);
                            _17153.y = 1.0 - _17152;
                            highp vec4 _17160 = textureLod(shadow_map, _17153, 0.0);
                            highp float _17161 = _17160.x;
                            highp float _16893 = step(_17161, _16823);
                            float mp_copy_16893 = _16893;
                            _16898 = _21827 + (_17161 * _16893);
                            _16901 = _21826 + mp_copy_16893;
                        }
                        highp float _21828 = 0.0;
                        if (_21826 > 0.0)
                        {
                            _21828 = _21827 / _21826;
                        }
                        else
                        {
                            _21828 = _16823;
                        }
                        _21836 = clamp(_16871 * max(_16823 - _21828, 0.0), frag_info.shadow_texel_size, _13059);
                    }
                    else
                    {
                        _21836 = _13059;
                    }
                    float _21843 = 0.0;
                    if (_16831 > 2.5)
                    {
                        highp vec2 _17189 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _17193 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _17194 = clamp(_13052 + (vec2(-0.707099974155426025390625) * _21836), _17189, _17193);
                        highp vec2 _17205 = (vec2(_17194.x, 1.0 - _17194.y) / _17189) - vec2(0.5);
                        highp vec2 _17207 = floor(_17205);
                        highp vec2 _17210 = _17205 - _17207;
                        highp vec2 _17215 = (_17207 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17225 = vec2((3.0 + _17215.x) * _16829, _17215.y);
                        highp float _17229 = frag_info.shadow_texel_size * _16829;
                        highp vec2 _17232 = vec2(_17229, frag_info.shadow_texel_size);
                        highp vec2 _17241 = vec2(_17229, 0.0);
                        highp vec2 _17249 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _17278 = _17210.x;
                        highp float _17287 = mix(mix(float(_16823 <= textureLod(shadow_map, _17225, 0.0).x), float(_16823 <= textureLod(shadow_map, _17225 + _17241, 0.0).x), _17278), mix(float(_16823 <= textureLod(shadow_map, _17225 + _17249, 0.0).x), float(_16823 <= textureLod(shadow_map, _17225 + _17232, 0.0).x), _17278), _17210.y);
                        float mp_copy_17287 = _17287;
                        highp vec2 _17321 = clamp(_13052 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21836), _17189, _17193);
                        highp vec2 _17332 = (vec2(_17321.x, 1.0 - _17321.y) / _17189) - vec2(0.5);
                        highp vec2 _17334 = floor(_17332);
                        highp vec2 _17337 = _17332 - _17334;
                        highp vec2 _17342 = (_17334 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17352 = vec2((3.0 + _17342.x) * _16829, _17342.y);
                        highp float _17405 = _17337.x;
                        highp float _17414 = mix(mix(float(_16823 <= textureLod(shadow_map, _17352, 0.0).x), float(_16823 <= textureLod(shadow_map, _17352 + _17241, 0.0).x), _17405), mix(float(_16823 <= textureLod(shadow_map, _17352 + _17249, 0.0).x), float(_16823 <= textureLod(shadow_map, _17352 + _17232, 0.0).x), _17405), _17337.y);
                        float mp_copy_17414 = _17414;
                        highp vec2 _17448 = clamp(_13052 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21836), _17189, _17193);
                        highp vec2 _17459 = (vec2(_17448.x, 1.0 - _17448.y) / _17189) - vec2(0.5);
                        highp vec2 _17461 = floor(_17459);
                        highp vec2 _17464 = _17459 - _17461;
                        highp vec2 _17469 = (_17461 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17479 = vec2((3.0 + _17469.x) * _16829, _17469.y);
                        highp float _17532 = _17464.x;
                        highp float _17541 = mix(mix(float(_16823 <= textureLod(shadow_map, _17479, 0.0).x), float(_16823 <= textureLod(shadow_map, _17479 + _17241, 0.0).x), _17532), mix(float(_16823 <= textureLod(shadow_map, _17479 + _17249, 0.0).x), float(_16823 <= textureLod(shadow_map, _17479 + _17232, 0.0).x), _17532), _17464.y);
                        float mp_copy_17541 = _17541;
                        highp vec2 _17575 = clamp(_13052 + (vec2(0.707099974155426025390625) * _21836), _17189, _17193);
                        highp vec2 _17586 = (vec2(_17575.x, 1.0 - _17575.y) / _17189) - vec2(0.5);
                        highp vec2 _17588 = floor(_17586);
                        highp vec2 _17591 = _17586 - _17588;
                        highp vec2 _17596 = (_17588 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17606 = vec2((3.0 + _17596.x) * _16829, _17596.y);
                        highp float _17659 = _17591.x;
                        highp float _17668 = mix(mix(float(_16823 <= textureLod(shadow_map, _17606, 0.0).x), float(_16823 <= textureLod(shadow_map, _17606 + _17241, 0.0).x), _17659), mix(float(_16823 <= textureLod(shadow_map, _17606 + _17249, 0.0).x), float(_16823 <= textureLod(shadow_map, _17606 + _17232, 0.0).x), _17659), _17591.y);
                        float mp_copy_17668 = _17668;
                        _21843 = (((mp_copy_17287 + mp_copy_17414) + mp_copy_17541) + mp_copy_17668) * 0.25;
                    }
                    else
                    {
                        int _16964 = (_16837 > 0.5) ? 17 : 16;
                        float _21839 = 0.0;
                        _21839 = 0.0;
                        float _16992 = 0.0;
                        for (int _21829 = 0; _21829 < 17; _21839 = _16992, _21829++)
                        {
                            if (_21829 >= _16964)
                            {
                                break;
                            }
                            vec2 _21830 = vec2(0.0);
                            do
                            {
                                if (_21829 == 0)
                                {
                                    _21830 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21829 == 1)
                                {
                                    _21830 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21829 == 2)
                                {
                                    _21830 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21829 == 3)
                                {
                                    _21830 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21829 == 4)
                                {
                                    _21830 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21829 == 5)
                                {
                                    _21830 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21829 == 6)
                                {
                                    _21830 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21829 == 7)
                                {
                                    _21830 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21829 == 8)
                                {
                                    _21830 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21829 == 9)
                                {
                                    _21830 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21829 == 10)
                                {
                                    _21830 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21829 == 11)
                                {
                                    _21830 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21829 == 12)
                                {
                                    _21830 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21829 == 13)
                                {
                                    _21830 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21829 == 14)
                                {
                                    _21830 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21829 == 15)
                                {
                                    _21830 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21830 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21832 = vec2(0.0);
                            do
                            {
                                if (_21829 < 3)
                                {
                                    _21832 = vec2(float(_21829) - 1.0, -1.0);
                                    break;
                                }
                                if (_21829 < 6)
                                {
                                    _21832 = vec2((float(_21829 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21829 < 11)
                                {
                                    _21832 = vec2((float(_21829 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21829 < 14)
                                {
                                    _21832 = vec2((float(_21829 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21832 = vec2(float(_21829 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _16981 = mix(_21830, _21832, vec2(_16837));
                            float _17808 = _16981.x;
                            float _17812 = _16981.y;
                            highp vec2 _17838 = clamp(_13052 + (vec2((_17808 * _16850) - (_17812 * _16852), (_17808 * _16852) + (_17812 * _16850)) * _21836), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _17848 = vec2((3.0 + _17838.x) * _16829, _17838.y);
                            _17848.y = 1.0 - _17838.y;
                            highp float _17860 = float(_16823 <= textureLod(shadow_map, _17848, 0.0).x);
                            float mp_copy_17860 = _17860;
                            _16992 = _21839 + mp_copy_17860;
                        }
                        _21843 = _21839 / float(_16964);
                    }
                    bool _17005 = 3 == (_12700 - 1);
                    bool _17011 = false;
                    if (_17005)
                    {
                        _17011 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _17011 = _17005;
                    }
                    float _21844 = 0.0;
                    if (_17011)
                    {
                        highp vec2 _17018 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                        highp vec2 _17026 = smoothstep(vec2(0.0), _17018, _13052) * smoothstep(vec2(0.0), _17018, _16709);
                        _21844 = mix(1.0, _21843, _17026.x * _17026.y);
                    }
                    else
                    {
                        _21844 = _21843;
                    }
                    _21879 = _21815 + _13112;
                    _21876 = _21855 + (_13112 * _21844);
                }
                else
                {
                    _21879 = _21815;
                    _21876 = _21855;
                }
                _21878 = _21879;
                _21875 = _21876;
            }
            else
            {
                _21878 = _21815;
                _21875 = _21855;
            }
            _21877 = _21878;
            _21874 = _21875;
        }
        else
        {
            _21877 = _21815;
            _21874 = _21855;
        }
        _21880 = _21874 + (1.0 - _21877);
    }
    else
    {
        _21880 = 1.0;
    }
    bool _7328 = frag_info.ssao_lighting.w > 0.5;
    bool _7334 = false;
    if (_7328)
    {
        _7334 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _7334 = _7328;
    }
    float _22031 = 0.0;
    if (_7334)
    {
        _22031 = min(_21880, _21897.y);
    }
    else
    {
        _22031 = _21880;
    }
    float _7343 = _7306 * _22031;
    highp vec3 _7356 = ((((_7240 + (_7244 * ((vec3(1.0) - _7216) - _7240))) * _21451) * _22048) + (((_7216 * (_21259 * frag_info.environment_intensity)) * 1.0) * _22189)) * mix(1.0, _7343, frag_info.radiance_blend.y);
    highp vec3 _22446 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _22446 = _7356 + ((_21897.xyz * _7244) * _6177);
    }
    else
    {
        _22446 = _7356;
    }
    highp vec3 _22452 = vec3(0.0);
    if (_7293)
    {
        highp vec3 _22349 = vec3(0.0);
        highp vec3 _22350 = vec3(0.0);
        do
        {
            float _17926 = max(dot(_21197, _22273), 0.0);
            highp float hp_copy_17926 = _17926;
            if (_17926 <= 0.0)
            {
                _22350 = vec3(0.0);
                _22349 = vec3(0.0);
                break;
            }
            float _17932 = max(_7113, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_17932 = _17932;
            vec3 _17935 = _22273 + mp_copy_21241;
            float _17938 = dot(_17935, _17935);
            vec3 _22347 = vec3(0.0);
            vec3 _22348 = vec3(0.0);
            if (_17938 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _17946 = _17935 * inversesqrt(_17938);
                float _22346 = 0.0;
                do
                {
                    float _18003 = dot(_21197, _17946);
                    if (_18003 <= 0.0)
                    {
                        _22346 = 0.0;
                        break;
                    }
                    float _18010 = _21233 * _21233;
                    vec3 _18013 = cross(_21197, _17946);
                    float _18016 = _18003 * _18010;
                    float _18025 = _18010 / (dot(_18013, _18013) + (_18016 * _18016));
                    _22346 = min((_18025 * _18025) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _18063 = _7109 + (_7226 * pow(clamp(1.0 - max(dot(_17946, _21241), 0.0), 0.0, 1.0), 5.0));
                _22348 = (_18063 * min(_22346 * (0.5 / max(mix((2.0 * hp_copy_17926) * _17932, hp_copy_17926 + hp_copy_17932, hp_copy_21233 * hp_copy_21233), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _22347 = _18063;
            }
            else
            {
                _22348 = vec3(0.0);
                _22347 = _7109;
            }
            _22350 = (_22348 * frag_info.directional_light_color.xyz) * _17926;
            _22349 = (((((vec3(1.0) - _22347) * _7243) * _7014) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _17926;
            break;
        } while(false);
        _22452 = (_22349 + _22350) * _7343;
    }
    else
    {
        _22452 = vec3(0.0);
    }
    highp vec2 _22351 = vec2(0.0);
    do
    {
        if (frag_info.punctual_dims.x < 0.5)
        {
            _22351 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _18099 = v_position - frag_info.camera_position.xyz;
            highp float _18114 = dot(_18099, frag_info.camera_forward.xyz);
            highp float _18120 = max(_18114, 9.9999997473787516355514526367188e-05);
            highp vec2 _18223 = (vec3(dot(_18099, frag_info.camera_right.xyz), dot(_18099, frag_info.camera_up.xyz), _18120).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_18120, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            int _18191 = int(((((clamp(floor((log2(max(_18114 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_18223.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_18223.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5);
            int _18236 = int(frag_info.punctual_dims.y + 0.5);
            _22351 = vec2(texelFetch(punctual_index, ivec2(_18191 % _18236, _18191 / _18236), 0).xy);
            break;
        }
        _22351 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _7399 = int(_22351.x + 0.5);
    mediump int _7403 = int(_22351.y + 0.5);
    highp vec3 _22450 = vec3(0.0);
    _22450 = _22452;
    highp vec3 _22771 = vec3(0.0);
    for (int _22352 = 0; _22352 < _7403; _22450 = _22771, _22352++)
    {
        int _7412 = _7399 + _22352;
        int _18259 = int(frag_info.punctual_dims.y + 0.5);
        int _7415 = int(texelFetch(punctual_index, ivec2(_7412 % _18259, _7412 / _18259), 0).x + 0.5);
        ivec2 _18275 = ivec2(0, _7415);
        highp vec4 _18277 = texelFetch(punctual_lights, _18275, 0);
        highp vec4 _18285 = texelFetch(punctual_lights, ivec2(1, _7415), 0);
        highp float _7421 = _18277.w;
        highp vec3 _7423 = _18285.xyz;
        if (_7421 > 2.5)
        {
            highp vec4 _18293 = texelFetch(punctual_lights, ivec2(2, _7415), 0);
            highp vec4 _18301 = texelFetch(punctual_lights, ivec2(3, _7415), 0);
            highp vec3 _7437 = _18293.xyz * (_18293.w * 0.5);
            highp vec3 _7443 = _18301.xyz * (_18301.w * 0.5);
            highp vec3 _7445 = _18277.xyz;
            highp vec3 _7447 = _7445 - _7437;
            highp vec3 _7449 = _7447 - _7443;
            highp vec3 _7453 = _7445 + _7437;
            highp vec3 _7455 = _7453 - _7443;
            highp vec3 _7467 = _7447 + _7443;
            highp vec3 _7471 = _7445 - v_position;
            highp float _7477 = _18285.w;
            highp float _7481 = (dot(_7471, _7471) * _7477) * _7477;
            highp float _7486 = clamp(1.0 - (_7481 * _7481), 0.0, 1.0);
            float mp_copy_7486 = _7486;
            vec2 _18308 = (clamp(vec2(_21233, sqrt(1.0 - _7113)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _18310 = _18308.x;
            float _18315 = _18308.y;
            vec4 _7510 = textureLod(brdf_lut, vec2((_18310 + 1.0) * 0.3333333432674407958984375, _18315), 0.0);
            vec4 _7514 = textureLod(brdf_lut, vec2((_18310 + 2.0) * 0.3333333432674407958984375, _18315), 0.0);
            vec3 _18358 = normalize(mp_copy_21241 - (_21197 * _7112));
            mat3 _18380 = transpose(mat3(_18358, -cross(_21197, _18358), _21197));
            mat3 _18381 = mat3(vec3(_7510.x, 0.0, _7510.y), vec3(0.0, 1.0, 0.0), vec3(_7510.z, 0.0, _7510.w)) * _18380;
            highp vec3 _18385 = _7449 - v_position;
            highp vec3 _18387 = normalize(_18381 * _18385);
            vec3 mp_copy_18387 = _18387;
            highp vec3 _18391 = _7455 - v_position;
            highp vec3 _18393 = normalize(_18381 * _18391);
            vec3 mp_copy_18393 = _18393;
            highp vec3 _18397 = (_7453 + _7443) - v_position;
            highp vec3 _18399 = normalize(_18381 * _18397);
            vec3 mp_copy_18399 = _18399;
            highp vec3 _18403 = _7467 - v_position;
            highp vec3 _18405 = normalize(_18381 * _18403);
            vec3 mp_copy_18405 = _18405;
            float _18434 = dot(_18387, _18393);
            float _18436 = abs(_18434);
            float _18450 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18436)) * _18436)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18436) * _18436));
            float _22595 = 0.0;
            if (_18434 > 0.0)
            {
                _22595 = _18450;
            }
            else
            {
                _22595 = (0.5 * inversesqrt(max(1.0 - (_18434 * _18434), 1.0000000116860974230803549289703e-07))) - _18450;
            }
            float _18483 = dot(_18393, _18399);
            float _18485 = abs(_18483);
            float _18499 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18485)) * _18485)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18485) * _18485));
            float _22596 = 0.0;
            if (_18483 > 0.0)
            {
                _22596 = _18499;
            }
            else
            {
                _22596 = (0.5 * inversesqrt(max(1.0 - (_18483 * _18483), 1.0000000116860974230803549289703e-07))) - _18499;
            }
            float _18532 = dot(_18399, _18405);
            float _18534 = abs(_18532);
            float _18548 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18534)) * _18534)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18534) * _18534));
            float _22597 = 0.0;
            if (_18532 > 0.0)
            {
                _22597 = _18548;
            }
            else
            {
                _22597 = (0.5 * inversesqrt(max(1.0 - (_18532 * _18532), 1.0000000116860974230803549289703e-07))) - _18548;
            }
            float _18581 = dot(_18405, _18387);
            float _18583 = abs(_18581);
            float _18597 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18583)) * _18583)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18583) * _18583));
            float _22598 = 0.0;
            if (_18581 > 0.0)
            {
                _22598 = _18597;
            }
            else
            {
                _22598 = (0.5 * inversesqrt(max(1.0 - (_18581 * _18581), 1.0000000116860974230803549289703e-07))) - _18597;
            }
            vec3 _18420 = (((cross(mp_copy_18387, mp_copy_18393) * _22595) + (cross(mp_copy_18393, mp_copy_18399) * _22596)) + (cross(mp_copy_18399, mp_copy_18405) * _22597)) + (cross(mp_copy_18405, mp_copy_18387) * _22598);
            float _18623 = length(_18420);
            mat3 _18683 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _18380;
            highp vec3 _18689 = normalize(_18683 * _18385);
            vec3 mp_copy_18689 = _18689;
            highp vec3 _18695 = normalize(_18683 * _18391);
            vec3 mp_copy_18695 = _18695;
            highp vec3 _18701 = normalize(_18683 * _18397);
            vec3 mp_copy_18701 = _18701;
            highp vec3 _18707 = normalize(_18683 * _18403);
            vec3 mp_copy_18707 = _18707;
            float _18736 = dot(_18689, _18695);
            float _18738 = abs(_18736);
            float _18752 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18738)) * _18738)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18738) * _18738));
            float _22599 = 0.0;
            if (_18736 > 0.0)
            {
                _22599 = _18752;
            }
            else
            {
                _22599 = (0.5 * inversesqrt(max(1.0 - (_18736 * _18736), 1.0000000116860974230803549289703e-07))) - _18752;
            }
            float _18785 = dot(_18695, _18701);
            float _18787 = abs(_18785);
            float _18801 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18787)) * _18787)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18787) * _18787));
            float _22600 = 0.0;
            if (_18785 > 0.0)
            {
                _22600 = _18801;
            }
            else
            {
                _22600 = (0.5 * inversesqrt(max(1.0 - (_18785 * _18785), 1.0000000116860974230803549289703e-07))) - _18801;
            }
            float _18834 = dot(_18701, _18707);
            float _18836 = abs(_18834);
            float _18850 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18836)) * _18836)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18836) * _18836));
            float _22601 = 0.0;
            if (_18834 > 0.0)
            {
                _22601 = _18850;
            }
            else
            {
                _22601 = (0.5 * inversesqrt(max(1.0 - (_18834 * _18834), 1.0000000116860974230803549289703e-07))) - _18850;
            }
            float _18883 = dot(_18707, _18689);
            float _18885 = abs(_18883);
            float _18899 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18885)) * _18885)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18885) * _18885));
            float _22602 = 0.0;
            if (_18883 > 0.0)
            {
                _22602 = _18899;
            }
            else
            {
                _22602 = (0.5 * inversesqrt(max(1.0 - (_18883 * _18883), 1.0000000116860974230803549289703e-07))) - _18899;
            }
            vec3 _18722 = (((cross(mp_copy_18689, mp_copy_18695) * _22599) + (cross(mp_copy_18695, mp_copy_18701) * _22600)) + (cross(mp_copy_18701, mp_copy_18707) * _22601)) + (cross(mp_copy_18707, mp_copy_18689) * _22602);
            float _18925 = length(_18722);
            _22771 = _22450 + (((_7423 * (mp_copy_7486 * mp_copy_7486)) * step(0.0, dot(cross(_7455 - _7449, _7467 - _7449), v_position - _7449))) * (((((_7109 * _7514.x) + (_7226 * _7514.y)) * max(((_18623 * _18623) + _18420.z) / (_18623 + 1.0), 0.0)) * 1.0) + (_7244 * max(((_18925 * _18925) + _18722.z) / (_18925 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_22539 = 0.0;
            vec3 _22512 = vec3(0.0);
            highp vec3 _22535 = vec3(0.0);
            float _22539 = 0.0;
            if (_7421 < 0.5)
            {
                _22539 = _21233;
                _22535 = _7423;
                _22512 = -normalize(texelFetch(punctual_lights, ivec2(2, _7415), 0).xyz);
            }
            else
            {
                highp vec3 _7601 = _18277.xyz - v_position;
                highp float _7604 = dot(_7601, _7601);
                highp float _7608 = inversesqrt(max(_7604, 9.9999999392252902907785028219223e-09));
                highp vec3 _7609 = _7601 * _7608;
                vec3 mp_copy_7609 = _7609;
                highp float _7611 = _18285.w;
                highp float _7616 = (_7604 * _7611) * _7611;
                highp float _7621 = clamp(1.0 - (_7616 * _7616), 0.0, 1.0);
                float mp_copy_7621 = _7621;
                highp vec4 _18951 = texelFetch(punctual_lights, ivec2(3, _7415), 0);
                highp float _7625 = _18951.w;
                float _22543 = 0.0;
                if (_7625 > 0.0)
                {
                    highp float _7652 = (_21233 * _21233) + ((_7625 * 0.5) * _7608);
                    float mp_copy_7652 = _7652;
                    _22543 = sqrt(min(mp_copy_7652, 1.0));
                }
                else
                {
                    _22543 = _21233;
                }
                highp vec3 _7659 = _7423 * ((mp_copy_7621 * mp_copy_7621) / max(pow(max(_7604, _7625 * _7625), _18951.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _22536 = vec3(0.0);
                if (_7421 > 1.5)
                {
                    highp vec4 _18959 = texelFetch(punctual_lights, ivec2(2, _7415), 0);
                    highp float _7678 = clamp((dot(normalize(_18959.xyz), -mp_copy_7609) * _18959.w) + _18951.x, 0.0, 1.0);
                    float mp_copy_7678 = _7678;
                    highp vec3 _7683 = _7659 * (mp_copy_7678 * mp_copy_7678);
                    highp float _7685 = _18951.y;
                    bool _7686 = _7685 > (-0.5);
                    bool _7692 = false;
                    if (_7686)
                    {
                        _7692 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7692 = _7686;
                    }
                    highp vec3 _22537 = vec3(0.0);
                    if (_7692)
                    {
                        float _22503 = 0.0;
                        do
                        {
                            highp vec4 _19044 = mat4(texelFetch(punctual_lights, ivec2(4, _7415), 0), texelFetch(punctual_lights, ivec2(5, _7415), 0), texelFetch(punctual_lights, ivec2(6, _7415), 0), texelFetch(punctual_lights, ivec2(7, _7415), 0)) * vec4(v_position + (_6015 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _19046 = _19044.w;
                            if (_19046 <= 0.0)
                            {
                                _22503 = 1.0;
                                break;
                            }
                            highp vec3 _19055 = _19044.xyz / vec3(_19046);
                            highp vec2 _19060 = (_19055.xy * 0.5) + vec2(0.5);
                            highp float _19062 = _19060.x;
                            bool _19063 = _19062 < 0.0;
                            bool _19070 = false;
                            if (!_19063)
                            {
                                _19070 = _19062 > 1.0;
                            }
                            else
                            {
                                _19070 = _19063;
                            }
                            bool _19077 = false;
                            if (!_19070)
                            {
                                _19077 = _19060.y < 0.0;
                            }
                            else
                            {
                                _19077 = _19070;
                            }
                            bool _19084 = false;
                            if (!_19077)
                            {
                                _19084 = _19060.y > 1.0;
                            }
                            else
                            {
                                _19084 = _19077;
                            }
                            bool _19091 = false;
                            if (!_19084)
                            {
                                _19091 = _19055.z < 0.0;
                            }
                            else
                            {
                                _19091 = _19084;
                            }
                            bool _19098 = false;
                            if (!_19091)
                            {
                                _19098 = _19055.z > 1.0;
                            }
                            else
                            {
                                _19098 = _19091;
                            }
                            if (_19098)
                            {
                                _22503 = 1.0;
                                break;
                            }
                            highp float _19105 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _19110 = frag_info.shadow_cascade_count + float(int(_7685 + 0.5));
                            highp float _19115 = _19055.z - frag_info.spot_shadow_params.y;
                            highp float _19118 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                            highp float _19131 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _22502 = 0.0;
                            _22502 = float(_19115 <= textureLod(shadow_map, vec2((_19110 + clamp(_19062, 0.0, 1.0)) / _19105, 1.0 - clamp(_19060.y, 0.0, 1.0)), 0.0).x);
                            for (int _22501 = 0; _22501 < 8; )
                            {
                                highp float _19141 = _19131 + (float(_22501) * 0.785398185253143310546875);
                                float mp_copy_19141 = _19141;
                                highp vec2 _19151 = _19060 + (vec2(cos(mp_copy_19141), sin(mp_copy_19141)) * _19118);
                                highp float _19241 = float(_19115 <= textureLod(shadow_map, vec2((_19110 + clamp(_19151.x, 0.0, 1.0)) / _19105, 1.0 - clamp(_19151.y, 0.0, 1.0)), 0.0).x);
                                float mp_copy_19241 = _19241;
                                _22502 += mp_copy_19241;
                                _22501++;
                                continue;
                            }
                            _22503 = _22502 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _22537 = _7683 * _22503;
                    }
                    else
                    {
                        _22537 = _7683;
                    }
                    _22536 = _22537;
                }
                else
                {
                    bool _7708 = _7421 > 0.5;
                    bool _7714 = false;
                    if (_7708)
                    {
                        _7714 = _18951.y > (-0.5);
                    }
                    else
                    {
                        _7714 = _7708;
                    }
                    bool _7720 = false;
                    if (_7714)
                    {
                        _7720 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7720 = _7714;
                    }
                    highp vec3 _22538 = vec3(0.0);
                    if (_7720)
                    {
                        float _22488 = 0.0;
                        do
                        {
                            highp vec4 _19545 = texelFetch(punctual_lights, ivec2(4, _7415), 0);
                            highp vec4 _19553 = texelFetch(punctual_lights, ivec2(5, _7415), 0);
                            highp vec3 _19313 = (v_position + (_6015 * _19545.z)) - texelFetch(punctual_lights, _18275, 0).xyz;
                            highp vec3 _19315 = abs(_19313);
                            highp float _19317 = _19315.x;
                            highp float _19319 = _19315.y;
                            bool _19320 = _19317 >= _19319;
                            bool _19328 = false;
                            if (_19320)
                            {
                                _19328 = _19317 >= _19315.z;
                            }
                            else
                            {
                                _19328 = _19320;
                            }
                            highp vec3 _22478 = vec3(0.0);
                            float _22480 = 0.0;
                            if (_19328)
                            {
                                highp float _19331 = _19313.x;
                                bool _19332 = _19331 >= 0.0;
                                highp vec3 _22477 = vec3(0.0);
                                if (_19332)
                                {
                                    _22477 = vec3(-_19313.z, _19313.y, _19331);
                                }
                                else
                                {
                                    _22477 = vec3(_19313.zy, -_19331);
                                }
                                _22480 = _19332 ? 0.0 : 1.0;
                                _22478 = _22477;
                            }
                            else
                            {
                                highp vec3 _22479 = vec3(0.0);
                                float _22482 = 0.0;
                                if (_19319 >= _19315.z)
                                {
                                    highp float _19365 = _19313.y;
                                    bool _19366 = _19365 >= 0.0;
                                    highp vec3 _22476 = vec3(0.0);
                                    if (_19366)
                                    {
                                        _22476 = vec3(-_19313.x, _19313.z, _19365);
                                    }
                                    else
                                    {
                                        _22476 = vec3(_19313.xz, -_19365);
                                    }
                                    _22482 = _19366 ? 2.0 : 3.0;
                                    _22479 = _22476;
                                }
                                else
                                {
                                    highp float _19393 = _19313.z;
                                    bool _19394 = _19393 >= 0.0;
                                    highp vec3 _22475 = vec3(0.0);
                                    if (_19394)
                                    {
                                        _22475 = _19313;
                                    }
                                    else
                                    {
                                        _22475 = vec3(-_19313.x, _19313.y, -_19393);
                                    }
                                    _22482 = _19394 ? 4.0 : 5.0;
                                    _22479 = _22475;
                                }
                                _22480 = _22482;
                                _22478 = _22479;
                            }
                            if (_22478.z <= 0.0)
                            {
                                _22488 = 1.0;
                                break;
                            }
                            highp vec2 _19434 = ((_22478.xy / vec2(_22478.z)) * 0.5) + vec2(0.5);
                            highp float _19445 = (_19545.x - (_19545.y / _22478.z)) - _19553.x;
                            if ((_19445 < 0.0) || (_19445 > 1.0))
                            {
                                _22488 = 1.0;
                                break;
                            }
                            highp float hp_copy_22485 = 0.0;
                            highp float _19457 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _19463 = _22480 >= 4.0;
                            highp float _19465 = (frag_info.shadow_cascade_count + _18951.y) + float(_19463);
                            float _22485 = 0.0;
                            if (_19463)
                            {
                                _22485 = _22480 - 4.0;
                            }
                            else
                            {
                                _22485 = _22480;
                            }
                            hp_copy_22485 = _22485;
                            highp float _19482 = _19553.y * 0.5;
                            highp float _19485 = _19545.w * 0.0040000001899898052215576171875;
                            highp vec2 _19569 = vec2(_19482);
                            highp vec2 _19572 = vec2(1.0 - _19482);
                            highp vec2 _19578 = vec2(mod(hp_copy_22485, 2.0), 1.0 - floor(hp_copy_22485 * 0.5)) * 0.5;
                            highp vec2 _19581 = _19578 + (clamp(_19434, _19569, _19572) * 0.5);
                            highp float _19501 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _22487 = 0.0;
                            _22487 = float(_19445 <= textureLod(shadow_map, vec2((_19465 + _19581.x) / _19457, 1.0 - _19581.y), 0.0).x);
                            for (int _22486 = 0; _22486 < 8; )
                            {
                                highp float _19511 = _19501 + (float(_22486) * 0.785398185253143310546875);
                                float mp_copy_19511 = _19511;
                                highp vec2 _19618 = _19578 + (clamp(_19434 + (vec2(cos(mp_copy_19511), sin(mp_copy_19511)) * _19485), _19569, _19572) * 0.5);
                                highp float _19635 = float(_19445 <= textureLod(shadow_map, vec2((_19465 + _19618.x) / _19457, 1.0 - _19618.y), 0.0).x);
                                float mp_copy_19635 = _19635;
                                _22487 += mp_copy_19635;
                                _22486++;
                                continue;
                            }
                            _22488 = _22487 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _22538 = _7659 * _22488;
                    }
                    else
                    {
                        _22538 = _7659;
                    }
                    _22536 = _22538;
                }
                _22539 = _22543;
                _22535 = _22536;
                _22512 = _7609;
            }
            hp_copy_22539 = _22539;
            highp vec3 _22566 = vec3(0.0);
            highp vec3 _22567 = vec3(0.0);
            do
            {
                float _19701 = max(dot(_21197, _22512), 0.0);
                highp float hp_copy_19701 = _19701;
                if (_19701 <= 0.0)
                {
                    _22567 = vec3(0.0);
                    _22566 = vec3(0.0);
                    break;
                }
                float _19707 = max(_7113, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_19707 = _19707;
                vec3 _19710 = _22512 + mp_copy_21241;
                float _19713 = dot(_19710, _19710);
                vec3 _22564 = vec3(0.0);
                vec3 _22565 = vec3(0.0);
                if (_19713 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _19721 = _19710 * inversesqrt(_19713);
                    float _22563 = 0.0;
                    do
                    {
                        float _19778 = dot(_21197, _19721);
                        if (_19778 <= 0.0)
                        {
                            _22563 = 0.0;
                            break;
                        }
                        float _19785 = _22539 * _22539;
                        vec3 _19788 = cross(_21197, _19721);
                        float _19791 = _19778 * _19785;
                        float _19800 = _19785 / (dot(_19788, _19788) + (_19791 * _19791));
                        _22563 = min((_19800 * _19800) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _19838 = _7109 + (_7226 * pow(clamp(1.0 - max(dot(_19721, _21241), 0.0), 0.0, 1.0), 5.0));
                    _22565 = (_19838 * min(_22563 * (0.5 / max(mix((2.0 * hp_copy_19701) * _19707, hp_copy_19701 + hp_copy_19707, hp_copy_22539 * hp_copy_22539), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _22564 = _19838;
                }
                else
                {
                    _22565 = vec3(0.0);
                    _22564 = _7109;
                }
                _22567 = (_22565 * _22535) * _19701;
                _22566 = (((((vec3(1.0) - _22564) * _7243) * _7014) * 0.3183098733425140380859375) * _22535) * _19701;
                break;
            } while(false);
            _22771 = _22450 + (_22566 + _22567);
        }
    }
    bool _7777 = _FogInfo.params0.y > 0.5;
    bool _7783 = false;
    if (_7777)
    {
        _7783 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7783 = _7777;
    }
    highp vec3 _22457 = vec3(0.0);
    if (_7783)
    {
        vec3 mp_copy_22453 = vec3(0.0);
        highp vec3 _22453 = vec3(0.0);
        if (_7950)
        {
            _22453 = -view_info.camera_forward.xyz;
        }
        else
        {
            _22453 = normalize(v_viewvector);
        }
        mp_copy_22453 = _22453;
        vec3 _7788 = _7134 * (-mp_copy_22453);
        vec3 _22454 = vec3(0.0);
        do
        {
            if (_8264)
            {
                vec2 _19960 = vec2(atan(_7788.z, _7788.x), asin(clamp(_7788.y, -1.0, 1.0)));
                highp vec2 hp_copy_19960 = _19960;
                _22454 = textureLod(prefiltered_radiance, (hp_copy_19960 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _19979 = vec2(atan(_7788.z, _7788.x), asin(clamp(_7788.y, -1.0, 1.0)));
            highp vec2 hp_copy_19979 = _19979;
            highp vec2 _19984 = (hp_copy_19979 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _19891 = clamp(_19984.y, 0.00390625, 0.99609375);
            float _19897 = floor(0.0);
            highp float _19916 = _19984.x;
            _22454 = mix(texture(prefiltered_radiance, vec2(_19916, (_19897 + _19891) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_19916, (min(_19897 + 1.0, 7.0) + _19891) * 0.125)).xyz, vec3(-_19897));
            break;
        } while(false);
        highp vec3 _22456 = vec3(0.0);
        if (_7157)
        {
            vec3 _22455 = vec3(0.0);
            do
            {
                if (_8264)
                {
                    vec2 _20089 = vec2(atan(_7788.z, _7788.x), asin(clamp(_7788.y, -1.0, 1.0)));
                    highp vec2 hp_copy_20089 = _20089;
                    _22455 = textureLod(prefiltered_radiance_b, (hp_copy_20089 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _20108 = vec2(atan(_7788.z, _7788.x), asin(clamp(_7788.y, -1.0, 1.0)));
                highp vec2 hp_copy_20108 = _20108;
                highp vec2 _20113 = (hp_copy_20108 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _20020 = clamp(_20113.y, 0.00390625, 0.99609375);
                float _20026 = floor(0.0);
                highp float _20045 = _20113.x;
                _22455 = mix(texture(prefiltered_radiance_b, vec2(_20045, (_20026 + _20020) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_20045, (min(_20026 + 1.0, 7.0) + _20020) * 0.125)).xyz, vec3(-_20026));
                break;
            } while(false);
            _22456 = mix(_22454, _22455, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _22456 = _22454;
        }
        _22457 = _22456 * frag_info.environment_intensity;
    }
    else
    {
        _22457 = _FogInfo.color.xyz;
    }
    highp vec4 _7812 = vec4(min((_22446 + (_22450 * mix(1.0, _21521, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + ((mix(_6193 * vec3(0.077399380505084991455078125), pow((_6193 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6193)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w), vec3(65504.0)), 1.0) * _22825;
    highp vec4 _22472 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _22472 = _7812;
            break;
        }
        int _20157 = int(_FogInfo.params0.x + 0.5);
        if (_20157 == 0)
        {
            _22472 = _7812;
            break;
        }
        highp float _22459 = 0.0;
        if (_7950)
        {
            _22459 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _22459 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_22459 > _FogInfo.params1.w))
        {
            _22472 = _7812;
            break;
        }
        float _22463 = 0.0;
        if (_20157 == 1)
        {
            _22463 = clamp((_22459 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _22464 = 0.0;
            if (_20157 == 2)
            {
                highp float _22462 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _22460 = vec3(0.0);
                    if (_7950)
                    {
                        _22460 = v_position - (view_info.camera_forward.xyz * _22459);
                    }
                    else
                    {
                        _22460 = v_position + v_viewvector;
                    }
                    highp float _20238 = -_FogInfo.params2.y;
                    highp float _20245 = _FogInfo.params1.x * exp(_20238 * (_22460.y - _FogInfo.params2.x));
                    highp float _20262 = _FogInfo.params2.y * (v_position.y - _22460.y);
                    highp float _22461 = 0.0;
                    if (abs(_20262) > 0.00124999997206032276153564453125)
                    {
                        _22461 = (_20245 - (_FogInfo.params1.x * exp(_20238 * (v_position.y - _FogInfo.params2.x)))) / _20262;
                    }
                    else
                    {
                        _22461 = _20245;
                    }
                    _22462 = _22461 * max(_22459 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _22462 = _FogInfo.params1.x * max(_22459 - _FogInfo.params1.y, 0.0);
                }
                _22464 = 1.0 - exp(-_22462);
            }
            else
            {
                highp float _20300 = _FogInfo.params1.x * max(_22459 - _FogInfo.params1.y, 0.0);
                _22464 = 1.0 - exp((-_20300) * _20300);
            }
            _22463 = _22464;
        }
        highp float _20312 = min(_22463, _FogInfo.params0.z);
        if (_20312 <= 0.0)
        {
            _22472 = _7812;
            break;
        }
        highp vec3 _20325 = mix(_FogInfo.color.xyz, _22457, vec3(_FogInfo.params0.w));
        bool _20328 = _FogInfo.sun.w > 0.5;
        bool _20334 = false;
        if (_20328)
        {
            _20334 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _20334 = _20328;
        }
        vec3 _22468 = vec3(0.0);
        if (_20334)
        {
            vec3 mp_copy_22465 = vec3(0.0);
            highp vec3 _22465 = vec3(0.0);
            if (_7950)
            {
                _22465 = -view_info.camera_forward.xyz;
            }
            else
            {
                _22465 = normalize(v_viewvector);
            }
            mp_copy_22465 = _22465;
            highp float _20350 = pow(max(dot(-mp_copy_22465, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_20350 = _20350;
            _22468 = _20325 + ((_FogInfo.sun.xyz * mp_copy_20350) * _FogInfo.params2.z);
        }
        else
        {
            _22468 = _20325;
        }
        highp float _20363 = _7812.w;
        float mp_copy_20363 = _20363;
        _22472 = vec4(mix(_7812.xyz, _22468 * mp_copy_20363, vec3(_20312)), _20363);
        break;
    } while(false);
    frag_color = _22472;
    float _22473 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _22473 = 1.0;
    }
    else
    {
        _22473 = abs(frag_info.fade);
    }
    frag_color *= _22473;
}

