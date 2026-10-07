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
    highp float _6047 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_6047 = _6047;
    vec3 _6051 = normalize(v_normal) * mp_copy_6047;
    vec4 _6092 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _6095 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _21405 = vec2(0.0);
    if (_6095)
    {
        highp vec2 _21404 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _21404 = v_texture_coords_1;
        }
        else
        {
            _21404 = v_texture_coords;
        }
        highp vec2 _6282 = _21404 * texture_transforms.base_color_transform.zw;
        highp float _6288 = _6282.x;
        highp float _6293 = _6282.y;
        _21405 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _6288) - (texture_transforms.base_color_rotation.y * _6293), (texture_transforms.base_color_rotation.y * _6288) + (texture_transforms.base_color_rotation.x * _6293));
    }
    else
    {
        _21405 = v_texture_coords;
    }
    vec4 _6109 = texture(base_color_texture, _21405);
    vec3 _6111 = _6109.xyz;
    float _23057 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_6109.w * _6092.w) * frag_info.color.w);
    vec3 _21417 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _21408 = vec2(0.0);
        if (_6095)
        {
            highp vec2 _21407 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _21407 = v_texture_coords_1;
            }
            else
            {
                _21407 = v_texture_coords;
            }
            highp vec2 _6376 = _21407 * texture_transforms.normal_transform.zw;
            highp float _6382 = _6376.x;
            highp float _6387 = _6376.y;
            _21408 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _6382) - (texture_transforms.normal_rotation.y * _6387), (texture_transforms.normal_rotation.y * _6382) + (texture_transforms.normal_rotation.x * _6387));
        }
        else
        {
            _21408 = v_texture_coords;
        }
        vec3 _6434 = ((texture(normal_texture, _21408).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _6438 = _6434.xy * vec2(frag_info.normal_scale);
        vec3 _20708 = _6434;
        _20708.x = _6438.x;
        _20708.y = _6438.y;
        highp vec3 _6444 = -v_viewvector;
        mat3 _21416 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _6474 = v_tangent.xyz - (_6051 * dot(_6051, v_tangent.xyz));
            highp float _6477 = dot(_6474, _6474);
            bool _6479 = _6477 <= 1.0000000133514319600180897396058e-10;
            bool _6487 = false;
            if (!_6479)
            {
                _6487 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _6487 = _6479;
            }
            if (_6487)
            {
                highp vec2 _6545 = dFdx(_21408);
                highp vec2 _6547 = dFdy(_21408);
                bvec2 _23059 = bvec2(length(_6545) == 0.0);
                highp vec2 _23060 = vec2(_23059.x ? vec2(1.0, 0.0).x : _6545.x, _23059.y ? vec2(1.0, 0.0).y : _6545.y);
                bvec2 _23061 = bvec2(length(_6547) == 0.0);
                highp vec2 _23062 = vec2(_23061.x ? vec2(0.0, 1.0).x : _6547.x, _23061.y ? vec2(0.0, 1.0).y : _6547.y);
                highp vec3 _6560 = cross(dFdy(_6444), _6051);
                highp vec3 _6563 = cross(_6051, dFdx(_6444));
                highp vec3 _6572 = (_6560 * _23060.x) + (_6563 * _23062.x);
                highp vec3 _6581 = (_6560 * _23060.y) + (_6563 * _23062.y);
                highp float _6590 = inversesqrt(max(max(dot(_6572, _6572), dot(_6581, _6581)), 9.9999996826552253889678874634872e-21));
                _21416 = mat3(_6572 * _6590, _6581 * _6590, _6051);
                break;
            }
            highp vec3 _6497 = _6474 * inversesqrt(_6477);
            _21416 = mat3(_6497, normalize(cross(_6051, _6497)) * sign(v_tangent.w), _6051);
            break;
        } while(false);
        _21417 = normalize(_21416 * _20708);
    }
    else
    {
        _21417 = _6051;
    }
    highp vec2 _21419 = vec2(0.0);
    if (_6095)
    {
        highp vec2 _21418 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _21418 = v_texture_coords_1;
        }
        else
        {
            _21418 = v_texture_coords;
        }
        highp vec2 _6652 = _21418 * texture_transforms.metallic_roughness_transform.zw;
        highp float _6658 = _6652.x;
        highp float _6663 = _6652.y;
        _21419 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _6658) - (texture_transforms.metallic_roughness_rotation.y * _6663), (texture_transforms.metallic_roughness_rotation.y * _6658) + (texture_transforms.metallic_roughness_rotation.x * _6663));
    }
    else
    {
        _21419 = v_texture_coords;
    }
    vec4 _6178 = texture(metallic_roughness_texture, _21419);
    float _6184 = clamp(_6178.z * frag_info.metallic_factor, 0.0, 1.0);
    float _6191 = clamp(_6178.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _21421 = vec2(0.0);
    if (_6095)
    {
        highp vec2 _21420 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _21420 = v_texture_coords_1;
        }
        else
        {
            _21420 = v_texture_coords;
        }
        highp vec2 _6722 = _21420 * texture_transforms.occlusion_transform.zw;
        highp float _6728 = _6722.x;
        highp float _6733 = _6722.y;
        _21421 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6728) - (texture_transforms.occlusion_rotation.y * _6733), (texture_transforms.occlusion_rotation.y * _6728) + (texture_transforms.occlusion_rotation.x * _6733));
    }
    else
    {
        _21421 = v_texture_coords;
    }
    vec4 _6206 = texture(occlusion_texture, _21421);
    float _6213 = 1.0 - ((1.0 - _6206.x) * frag_info.occlusion_strength);
    highp vec2 _21423 = vec2(0.0);
    if (_6095)
    {
        highp vec2 _21422 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _21422 = v_texture_coords_1;
        }
        else
        {
            _21422 = v_texture_coords;
        }
        highp vec2 _6792 = _21422 * texture_transforms.emissive_transform.zw;
        highp float _6798 = _6792.x;
        highp float _6803 = _6792.y;
        _21423 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6798) - (texture_transforms.emissive_rotation.y * _6803), (texture_transforms.emissive_rotation.y * _6798) + (texture_transforms.emissive_rotation.x * _6803));
    }
    else
    {
        _21423 = v_texture_coords;
    }
    highp float hp_copy_21453 = 0.0;
    vec4 _6228 = texture(emissive_texture, _21423);
    vec3 _6229 = _6228.xyz;
    vec3 _7052 = vec4((mix(_6111 * vec3(0.077399380505084991455078125), pow((_6111 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6111)) * _6092.xyz) * frag_info.color.xyz, _23057).xyz;
    float _21453 = 0.0;
    do
    {
        if (frag_info.specular_aa_variance <= 0.0)
        {
            _21453 = _6191;
            break;
        }
        vec3 _7870 = dFdx(_21417);
        vec3 _7872 = dFdy(_21417);
        _21453 = sqrt(clamp((_6191 * _6191) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7870, _7870), dot(_7872, _7872))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
        break;
    } while(false);
    hp_copy_21453 = _21453;
    float _21463 = 0.0;
    vec3 _21468 = vec3(0.0);
    float _21741 = 0.0;
    vec4 _22117 = vec4(0.0);
    vec3 _22268 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _7079 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        float _21454 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _21454 = _7079.w;
        }
        else
        {
            _21454 = _7079.x;
        }
        float _7092 = min(_6213, _21454);
        bool _7095 = frag_info.ssao_lighting.z > 0.5;
        bool _7101 = false;
        if (_7095)
        {
            _7101 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _7101 = _7095;
        }
        vec3 _21469 = vec3(0.0);
        if (_7101)
        {
            vec2 _7905 = (_7079.zw * 2.0) - vec2(1.0);
            float _7907 = _7905.x;
            float _7909 = _7905.y;
            float _7917 = (1.0 - abs(_7907)) - abs(_7909);
            vec3 _7918 = vec3(_7907, _7909, _7917);
            vec3 _21457 = vec3(0.0);
            if (_7917 < 0.0)
            {
                vec2 _7931 = (vec2(1.0) - abs(_7918.yx)) * vec2((_7907 >= 0.0) ? 1.0 : (-1.0), (_7909 >= 0.0) ? 1.0 : (-1.0));
                vec3 _20757 = _7918;
                _20757.x = _7931.x;
                _20757.y = _7931.y;
                _21457 = _20757;
            }
            else
            {
                _21457 = _7918;
            }
            vec3 _7939 = -normalize(_21457);
            _21469 = normalize(((frag_info.camera_right.xyz * _7939.x) + (frag_info.camera_up.xyz * _7939.y)) + (frag_info.camera_forward.xyz * _7939.z));
        }
        else
        {
            _21469 = vec3(0.0);
        }
        vec3 _7129 = vec3(_7092);
        _22268 = mix(_7129, max(_7129, ((((((_7052 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _7092) + ((_7052 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _7092) + ((_7052 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _7092), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _22117 = _7079;
        _21741 = _7092;
        _21468 = _21469;
        _21463 = float(_7101);
    }
    else
    {
        _22268 = vec3(_6213);
        _22117 = vec4(1.0);
        _21741 = _6213;
        _21468 = vec3(0.0);
        _21463 = 0.0;
    }
    vec3 mp_copy_21461 = vec3(0.0);
    bool _7988 = view_info.camera_forward.w > 0.5;
    highp vec3 _21461 = vec3(0.0);
    if (_7988)
    {
        _21461 = -view_info.camera_forward.xyz;
    }
    else
    {
        _21461 = normalize(v_viewvector);
    }
    mp_copy_21461 = _21461;
    vec3 _7147 = mix(frag_info.dielectric_f0.xyz, _7052, vec3(_6184));
    float _7150 = dot(_21417, _21461);
    float _7151 = max(_7150, 0.0);
    float _7155 = max(dot(_6051, _21461), 0.0);
    vec3 _7159 = reflect(-mp_copy_21461, _21417);
    mat3 _7172 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _7175 = _21463 > 0.5;
    bvec3 _7178 = bvec3(_7175);
    highp vec3 _7179 = vec3(_7178.x ? _21468.x : _21417.x, _7178.y ? _21468.y : _21417.y, _7178.z ? _21468.z : _21417.z);
    vec3 mp_copy_7179 = _7179;
    vec3 _7180 = _7172 * mp_copy_7179;
    vec3 _21472 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        vec3 _8055 = _7159 + (((step(vec3(0.0), _7159) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
        highp vec3 hp_copy_8055 = _8055;
        highp vec3 _8057 = vec3(1.0) / hp_copy_8055;
        highp vec3 _8074 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _8057, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _8057);
        _21472 = normalize((v_position + (_7159 * max(min(min(_8074.x, _8074.y), _8074.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _21472 = _7159;
    }
    bool _8302 = false;
    vec3 _7185 = _7172 * _21472;
    float _8121 = _7180.y;
    float _8122 = 0.48860299587249755859375 * _8121;
    float _8128 = _7180.z;
    float _8129 = 0.48860299587249755859375 * _8128;
    float _8135 = _7180.x;
    float _8136 = 0.48860299587249755859375 * _8135;
    float _8143 = 1.09254801273345947265625 * _8135;
    float _8146 = _8143 * _8121;
    float _8156 = (1.09254801273345947265625 * _8121) * _8128;
    float _8168 = 0.3153919875621795654296875 * (((3.0 * _8128) * _8128) - 1.0);
    float _8178 = _8143 * _8128;
    float _8194 = 0.546274006366729736328125 * ((_8135 * _8135) - (_8121 * _8121));
    vec3 _7188 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _8122)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _8129)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _8136)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _8146)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _8156)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _8168)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _8178)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _8194), vec3(0.0));
    vec3 _21473 = vec3(0.0);
    do
    {
        _8302 = radiance_layout_info.mip_layout > 0.5;
        if (_8302)
        {
            vec2 _8381 = vec2(atan(_7185.z, _7185.x), asin(clamp(_7185.y, -1.0, 1.0)));
            highp vec2 hp_copy_8381 = _8381;
            _21473 = textureLod(prefiltered_radiance, (hp_copy_8381 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_21453, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _8400 = vec2(atan(_7185.z, _7185.x), asin(clamp(_7185.y, -1.0, 1.0)));
        highp vec2 hp_copy_8400 = _8400;
        highp vec2 _8405 = (hp_copy_8400 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8312 = clamp(_8405.y, 0.00390625, 0.99609375);
        float _8316 = clamp(_21453, 0.0, 1.0) * 7.0;
        float _8318 = floor(_8316);
        highp float _8337 = _8405.x;
        _21473 = mix(texture(prefiltered_radiance, vec2(_8337, (_8318 + _8312) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_8337, (min(_8318 + 1.0, 7.0) + _8312) * 0.125)).xyz, vec3(_8316 - _8318));
        break;
    } while(false);
    bool _7195 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _21478 = vec3(0.0);
    highp vec3 _21479 = vec3(0.0);
    if (_7195)
    {
        vec3 _21474 = vec3(0.0);
        do
        {
            if (_8302)
            {
                vec2 _8693 = vec2(atan(_7185.z, _7185.x), asin(clamp(_7185.y, -1.0, 1.0)));
                highp vec2 hp_copy_8693 = _8693;
                _21474 = textureLod(prefiltered_radiance_b, (hp_copy_8693 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_21453, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _8712 = vec2(atan(_7185.z, _7185.x), asin(clamp(_7185.y, -1.0, 1.0)));
            highp vec2 hp_copy_8712 = _8712;
            highp vec2 _8717 = (hp_copy_8712 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _8624 = clamp(_8717.y, 0.00390625, 0.99609375);
            float _8628 = clamp(_21453, 0.0, 1.0) * 7.0;
            float _8630 = floor(_8628);
            highp float _8649 = _8717.x;
            _21474 = mix(texture(prefiltered_radiance_b, vec2(_8649, (_8630 + _8624) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_8649, (min(_8630 + 1.0, 7.0) + _8624) * 0.125)).xyz, vec3(_8628 - _8630));
            break;
        } while(false);
        highp vec3 _7206 = vec3(frag_info.radiance_blend.x);
        _21479 = mix(_21473, _21474, _7206);
        _21478 = mix(_7188, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _8122)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _8129)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _8136)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _8146)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _8156)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _8168)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _8178)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _8194), vec3(0.0)), _7206);
    }
    else
    {
        _21479 = _21473;
        _21478 = _7188;
    }
    highp float _8730 = 0.0;
    highp vec3 _7217 = _21478 * frag_info.environment_intensity;
    float _21480 = 0.0;
    do
    {
        _8730 = frag_info.gi_grid.w;
        if (_8730 <= 0.0)
        {
            _21480 = 0.0;
            break;
        }
        highp vec3 _8743 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _8751 = min(_8743, (frag_info.gi_counts.xyz - vec3(1.0)) - _8743);
        _21480 = clamp(min(_8751.x, min(_8751.y, _8751.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _21671 = vec3(0.0);
    if (_21480 > 0.0)
    {
        highp vec3 _8843 = v_position + (((_21417 * 0.20000000298023223876953125) + (mp_copy_21461 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _8846 = _8843 / frag_info.gi_grid.xyz;
        highp vec3 _8848 = floor(_8846);
        highp vec3 _8854 = clamp(_8846 - _8848, vec3(0.0), vec3(1.0));
        vec3 mp_copy_8854 = _8854;
        highp vec3 _8976 = _8848 - frag_info.gi_anchor.xyz;
        bool _8979 = any(lessThan(_8976, vec3(0.0)));
        bool _8987 = false;
        if (!_8979)
        {
            _8987 = any(greaterThanEqual(_8976, frag_info.gi_counts.xyz));
        }
        else
        {
            _8987 = _8979;
        }
        vec3 mp_copy_21481 = vec3(0.0);
        highp float _8988 = _8987 ? 0.0 : 1.0;
        float mp_copy_8988 = _8988;
        vec3 _8990 = vec3(1.0) - mp_copy_8854;
        vec3 _8994 = max(_8990, vec3(0.001000000047497451305389404296875));
        highp vec3 _9010 = (_8848 * frag_info.gi_grid.xyz) - _8843;
        highp float _9012 = length(_9010);
        highp vec3 _21481 = vec3(0.0);
        if (_9012 > 9.9999997473787516355514526367188e-06)
        {
            _21481 = _9010 / vec3(_9012);
        }
        else
        {
            _21481 = _21417;
        }
        mp_copy_21481 = _21481;
        float _9030 = pow((dot(_21481, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9155 = _8848 - (frag_info.gi_counts.xyz * floor(_8848 / frag_info.gi_counts.xyz));
        highp float _9171 = _9155.x + (frag_info.gi_counts.x * (_9155.y + (frag_info.gi_counts.y * _9155.z)));
        bool _9041 = frag_info.gi_visibility.x > 0.0;
        float _21486 = 0.0;
        if (_9041)
        {
            highp float _9179 = floor(_9171 / frag_info.gi_counts.w);
            highp vec2 _9193 = vec2((_9171 - (_9179 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9179 * 16.0));
            vec3 _9053 = -mp_copy_21481;
            vec3 _9241 = _9053 / vec3((abs(_9053.x) + abs(_9053.y)) + abs(_9053.z));
            vec2 _21482 = vec2(0.0);
            if (_9241.z >= 0.0)
            {
                _21482 = _9241.xy;
            }
            else
            {
                _21482 = (vec2(1.0) - abs(_9241.yx)) * vec2((_9241.x >= 0.0) ? 1.0 : (-1.0), (_9241.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9057 = texture(irradiance_field, clamp((_9193 + vec2(1.0)) + (clamp((_21482 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9193 + vec2(0.5), _9193 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9062 = _9057.x * frag_info.gi_visibility.z;
            highp float _9074 = abs((_9062 * _9062) - ((_9057.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9080 = (_9012 - _9062) - frag_info.gi_visibility.y;
            highp float _21483 = 0.0;
            if (_9080 <= 0.0)
            {
                _21483 = 1.0;
            }
            else
            {
                _21483 = _9074 / (_9074 + (_9080 * _9080));
            }
            _21486 = _9030 * mix(1.0, max(0.0500000007450580596923828125, (_21483 * _21483) * _21483), frag_info.gi_visibility.x);
        }
        else
        {
            _21486 = _9030;
        }
        float _9108 = max(9.9999999747524270787835121154785e-07, _21486);
        float _21487 = 0.0;
        if (_9108 < 0.20000000298023223876953125)
        {
            _21487 = _9108 * ((_9108 * _9108) * 25.0);
        }
        else
        {
            _21487 = _9108;
        }
        float _9123 = _21487 * (((_8994.x * _8994.y) * _8994.z) * mp_copy_8988);
        highp float _9282 = floor(_9171 / frag_info.gi_counts.w);
        highp vec2 _9296 = vec2((_9171 - (_9282 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9282 * 8.0));
        vec3 _9344 = _21417 / vec3((abs(_21417.x) + abs(_21417.y)) + abs(_21417.z));
        bool _9347 = _9344.z >= 0.0;
        vec2 _21488 = vec2(0.0);
        if (_9347)
        {
            _21488 = _9344.xy;
        }
        else
        {
            _21488 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9135 = texture(irradiance_field, clamp((_9296 + vec2(1.0)) + (clamp((_21488 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9296 + vec2(0.5), _9296 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9430 = _8848 + vec3(1.0, 0.0, 0.0);
        highp vec3 _9435 = _9430 - frag_info.gi_anchor.xyz;
        bool _9438 = any(lessThan(_9435, vec3(0.0)));
        bool _9446 = false;
        if (!_9438)
        {
            _9446 = any(greaterThanEqual(_9435, frag_info.gi_counts.xyz));
        }
        else
        {
            _9446 = _9438;
        }
        vec3 mp_copy_21490 = vec3(0.0);
        highp float _9447 = _9446 ? 0.0 : 1.0;
        float mp_copy_9447 = _9447;
        vec3 _9453 = max(mix(_8990, mp_copy_8854, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9469 = (_9430 * frag_info.gi_grid.xyz) - _8843;
        highp float _9471 = length(_9469);
        highp vec3 _21490 = vec3(0.0);
        if (_9471 > 9.9999997473787516355514526367188e-06)
        {
            _21490 = _9469 / vec3(_9471);
        }
        else
        {
            _21490 = _21417;
        }
        mp_copy_21490 = _21490;
        float _9489 = pow((dot(_21490, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9614 = _9430 - (frag_info.gi_counts.xyz * floor(_9430 / frag_info.gi_counts.xyz));
        highp float _9630 = _9614.x + (frag_info.gi_counts.x * (_9614.y + (frag_info.gi_counts.y * _9614.z)));
        float _21495 = 0.0;
        if (_9041)
        {
            highp float _9638 = floor(_9630 / frag_info.gi_counts.w);
            highp vec2 _9652 = vec2((_9630 - (_9638 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9638 * 16.0));
            vec3 _9512 = -mp_copy_21490;
            vec3 _9700 = _9512 / vec3((abs(_9512.x) + abs(_9512.y)) + abs(_9512.z));
            vec2 _21491 = vec2(0.0);
            if (_9700.z >= 0.0)
            {
                _21491 = _9700.xy;
            }
            else
            {
                _21491 = (vec2(1.0) - abs(_9700.yx)) * vec2((_9700.x >= 0.0) ? 1.0 : (-1.0), (_9700.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9516 = texture(irradiance_field, clamp((_9652 + vec2(1.0)) + (clamp((_21491 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9652 + vec2(0.5), _9652 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9521 = _9516.x * frag_info.gi_visibility.z;
            highp float _9533 = abs((_9521 * _9521) - ((_9516.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9539 = (_9471 - _9521) - frag_info.gi_visibility.y;
            highp float _21492 = 0.0;
            if (_9539 <= 0.0)
            {
                _21492 = 1.0;
            }
            else
            {
                _21492 = _9533 / (_9533 + (_9539 * _9539));
            }
            _21495 = _9489 * mix(1.0, max(0.0500000007450580596923828125, (_21492 * _21492) * _21492), frag_info.gi_visibility.x);
        }
        else
        {
            _21495 = _9489;
        }
        float _9567 = max(9.9999999747524270787835121154785e-07, _21495);
        float _21496 = 0.0;
        if (_9567 < 0.20000000298023223876953125)
        {
            _21496 = _9567 * ((_9567 * _9567) * 25.0);
        }
        else
        {
            _21496 = _9567;
        }
        float _9582 = _21496 * (((_9453.x * _9453.y) * _9453.z) * mp_copy_9447);
        highp float _9741 = floor(_9630 / frag_info.gi_counts.w);
        highp vec2 _9755 = vec2((_9630 - (_9741 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9741 * 8.0));
        vec2 _21497 = vec2(0.0);
        if (_9347)
        {
            _21497 = _9344.xy;
        }
        else
        {
            _21497 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9594 = texture(irradiance_field, clamp((_9755 + vec2(1.0)) + (clamp((_21497 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9755 + vec2(0.5), _9755 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9889 = _8848 + vec3(0.0, 1.0, 0.0);
        highp vec3 _9894 = _9889 - frag_info.gi_anchor.xyz;
        bool _9897 = any(lessThan(_9894, vec3(0.0)));
        bool _9905 = false;
        if (!_9897)
        {
            _9905 = any(greaterThanEqual(_9894, frag_info.gi_counts.xyz));
        }
        else
        {
            _9905 = _9897;
        }
        vec3 mp_copy_21499 = vec3(0.0);
        highp float _9906 = _9905 ? 0.0 : 1.0;
        float mp_copy_9906 = _9906;
        vec3 _9912 = max(mix(_8990, mp_copy_8854, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9928 = (_9889 * frag_info.gi_grid.xyz) - _8843;
        highp float _9930 = length(_9928);
        highp vec3 _21499 = vec3(0.0);
        if (_9930 > 9.9999997473787516355514526367188e-06)
        {
            _21499 = _9928 / vec3(_9930);
        }
        else
        {
            _21499 = _21417;
        }
        mp_copy_21499 = _21499;
        float _9948 = pow((dot(_21499, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10073 = _9889 - (frag_info.gi_counts.xyz * floor(_9889 / frag_info.gi_counts.xyz));
        highp float _10089 = _10073.x + (frag_info.gi_counts.x * (_10073.y + (frag_info.gi_counts.y * _10073.z)));
        float _21504 = 0.0;
        if (_9041)
        {
            highp float _10097 = floor(_10089 / frag_info.gi_counts.w);
            highp vec2 _10111 = vec2((_10089 - (_10097 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10097 * 16.0));
            vec3 _9971 = -mp_copy_21499;
            vec3 _10159 = _9971 / vec3((abs(_9971.x) + abs(_9971.y)) + abs(_9971.z));
            vec2 _21500 = vec2(0.0);
            if (_10159.z >= 0.0)
            {
                _21500 = _10159.xy;
            }
            else
            {
                _21500 = (vec2(1.0) - abs(_10159.yx)) * vec2((_10159.x >= 0.0) ? 1.0 : (-1.0), (_10159.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9975 = texture(irradiance_field, clamp((_10111 + vec2(1.0)) + (clamp((_21500 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10111 + vec2(0.5), _10111 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9980 = _9975.x * frag_info.gi_visibility.z;
            highp float _9992 = abs((_9980 * _9980) - ((_9975.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9998 = (_9930 - _9980) - frag_info.gi_visibility.y;
            highp float _21501 = 0.0;
            if (_9998 <= 0.0)
            {
                _21501 = 1.0;
            }
            else
            {
                _21501 = _9992 / (_9992 + (_9998 * _9998));
            }
            _21504 = _9948 * mix(1.0, max(0.0500000007450580596923828125, (_21501 * _21501) * _21501), frag_info.gi_visibility.x);
        }
        else
        {
            _21504 = _9948;
        }
        float _10026 = max(9.9999999747524270787835121154785e-07, _21504);
        float _21505 = 0.0;
        if (_10026 < 0.20000000298023223876953125)
        {
            _21505 = _10026 * ((_10026 * _10026) * 25.0);
        }
        else
        {
            _21505 = _10026;
        }
        float _10041 = _21505 * (((_9912.x * _9912.y) * _9912.z) * mp_copy_9906);
        highp float _10200 = floor(_10089 / frag_info.gi_counts.w);
        highp vec2 _10214 = vec2((_10089 - (_10200 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10200 * 8.0));
        vec2 _21506 = vec2(0.0);
        if (_9347)
        {
            _21506 = _9344.xy;
        }
        else
        {
            _21506 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10053 = texture(irradiance_field, clamp((_10214 + vec2(1.0)) + (clamp((_21506 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10214 + vec2(0.5), _10214 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10348 = _8848 + vec3(1.0, 1.0, 0.0);
        highp vec3 _10353 = _10348 - frag_info.gi_anchor.xyz;
        bool _10356 = any(lessThan(_10353, vec3(0.0)));
        bool _10364 = false;
        if (!_10356)
        {
            _10364 = any(greaterThanEqual(_10353, frag_info.gi_counts.xyz));
        }
        else
        {
            _10364 = _10356;
        }
        vec3 mp_copy_21508 = vec3(0.0);
        highp float _10365 = _10364 ? 0.0 : 1.0;
        float mp_copy_10365 = _10365;
        vec3 _10371 = max(mix(_8990, mp_copy_8854, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10387 = (_10348 * frag_info.gi_grid.xyz) - _8843;
        highp float _10389 = length(_10387);
        highp vec3 _21508 = vec3(0.0);
        if (_10389 > 9.9999997473787516355514526367188e-06)
        {
            _21508 = _10387 / vec3(_10389);
        }
        else
        {
            _21508 = _21417;
        }
        mp_copy_21508 = _21508;
        float _10407 = pow((dot(_21508, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10532 = _10348 - (frag_info.gi_counts.xyz * floor(_10348 / frag_info.gi_counts.xyz));
        highp float _10548 = _10532.x + (frag_info.gi_counts.x * (_10532.y + (frag_info.gi_counts.y * _10532.z)));
        float _21513 = 0.0;
        if (_9041)
        {
            highp float _10556 = floor(_10548 / frag_info.gi_counts.w);
            highp vec2 _10570 = vec2((_10548 - (_10556 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10556 * 16.0));
            vec3 _10430 = -mp_copy_21508;
            vec3 _10618 = _10430 / vec3((abs(_10430.x) + abs(_10430.y)) + abs(_10430.z));
            vec2 _21509 = vec2(0.0);
            if (_10618.z >= 0.0)
            {
                _21509 = _10618.xy;
            }
            else
            {
                _21509 = (vec2(1.0) - abs(_10618.yx)) * vec2((_10618.x >= 0.0) ? 1.0 : (-1.0), (_10618.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10434 = texture(irradiance_field, clamp((_10570 + vec2(1.0)) + (clamp((_21509 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10570 + vec2(0.5), _10570 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10439 = _10434.x * frag_info.gi_visibility.z;
            highp float _10451 = abs((_10439 * _10439) - ((_10434.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10457 = (_10389 - _10439) - frag_info.gi_visibility.y;
            highp float _21510 = 0.0;
            if (_10457 <= 0.0)
            {
                _21510 = 1.0;
            }
            else
            {
                _21510 = _10451 / (_10451 + (_10457 * _10457));
            }
            _21513 = _10407 * mix(1.0, max(0.0500000007450580596923828125, (_21510 * _21510) * _21510), frag_info.gi_visibility.x);
        }
        else
        {
            _21513 = _10407;
        }
        float _10485 = max(9.9999999747524270787835121154785e-07, _21513);
        float _21514 = 0.0;
        if (_10485 < 0.20000000298023223876953125)
        {
            _21514 = _10485 * ((_10485 * _10485) * 25.0);
        }
        else
        {
            _21514 = _10485;
        }
        float _10500 = _21514 * (((_10371.x * _10371.y) * _10371.z) * mp_copy_10365);
        highp float _10659 = floor(_10548 / frag_info.gi_counts.w);
        highp vec2 _10673 = vec2((_10548 - (_10659 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10659 * 8.0));
        vec2 _21515 = vec2(0.0);
        if (_9347)
        {
            _21515 = _9344.xy;
        }
        else
        {
            _21515 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10512 = texture(irradiance_field, clamp((_10673 + vec2(1.0)) + (clamp((_21515 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10673 + vec2(0.5), _10673 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10807 = _8848 + vec3(0.0, 0.0, 1.0);
        highp vec3 _10812 = _10807 - frag_info.gi_anchor.xyz;
        bool _10815 = any(lessThan(_10812, vec3(0.0)));
        bool _10823 = false;
        if (!_10815)
        {
            _10823 = any(greaterThanEqual(_10812, frag_info.gi_counts.xyz));
        }
        else
        {
            _10823 = _10815;
        }
        vec3 mp_copy_21517 = vec3(0.0);
        highp float _10824 = _10823 ? 0.0 : 1.0;
        float mp_copy_10824 = _10824;
        vec3 _10830 = max(mix(_8990, mp_copy_8854, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10846 = (_10807 * frag_info.gi_grid.xyz) - _8843;
        highp float _10848 = length(_10846);
        highp vec3 _21517 = vec3(0.0);
        if (_10848 > 9.9999997473787516355514526367188e-06)
        {
            _21517 = _10846 / vec3(_10848);
        }
        else
        {
            _21517 = _21417;
        }
        mp_copy_21517 = _21517;
        float _10866 = pow((dot(_21517, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10991 = _10807 - (frag_info.gi_counts.xyz * floor(_10807 / frag_info.gi_counts.xyz));
        highp float _11007 = _10991.x + (frag_info.gi_counts.x * (_10991.y + (frag_info.gi_counts.y * _10991.z)));
        float _21522 = 0.0;
        if (_9041)
        {
            highp float _11015 = floor(_11007 / frag_info.gi_counts.w);
            highp vec2 _11029 = vec2((_11007 - (_11015 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11015 * 16.0));
            vec3 _10889 = -mp_copy_21517;
            vec3 _11077 = _10889 / vec3((abs(_10889.x) + abs(_10889.y)) + abs(_10889.z));
            vec2 _21518 = vec2(0.0);
            if (_11077.z >= 0.0)
            {
                _21518 = _11077.xy;
            }
            else
            {
                _21518 = (vec2(1.0) - abs(_11077.yx)) * vec2((_11077.x >= 0.0) ? 1.0 : (-1.0), (_11077.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10893 = texture(irradiance_field, clamp((_11029 + vec2(1.0)) + (clamp((_21518 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11029 + vec2(0.5), _11029 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10898 = _10893.x * frag_info.gi_visibility.z;
            highp float _10910 = abs((_10898 * _10898) - ((_10893.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10916 = (_10848 - _10898) - frag_info.gi_visibility.y;
            highp float _21519 = 0.0;
            if (_10916 <= 0.0)
            {
                _21519 = 1.0;
            }
            else
            {
                _21519 = _10910 / (_10910 + (_10916 * _10916));
            }
            _21522 = _10866 * mix(1.0, max(0.0500000007450580596923828125, (_21519 * _21519) * _21519), frag_info.gi_visibility.x);
        }
        else
        {
            _21522 = _10866;
        }
        float _10944 = max(9.9999999747524270787835121154785e-07, _21522);
        float _21523 = 0.0;
        if (_10944 < 0.20000000298023223876953125)
        {
            _21523 = _10944 * ((_10944 * _10944) * 25.0);
        }
        else
        {
            _21523 = _10944;
        }
        float _10959 = _21523 * (((_10830.x * _10830.y) * _10830.z) * mp_copy_10824);
        highp float _11118 = floor(_11007 / frag_info.gi_counts.w);
        highp vec2 _11132 = vec2((_11007 - (_11118 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11118 * 8.0));
        vec2 _21524 = vec2(0.0);
        if (_9347)
        {
            _21524 = _9344.xy;
        }
        else
        {
            _21524 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10971 = texture(irradiance_field, clamp((_11132 + vec2(1.0)) + (clamp((_21524 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11132 + vec2(0.5), _11132 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11266 = _8848 + vec3(1.0, 0.0, 1.0);
        highp vec3 _11271 = _11266 - frag_info.gi_anchor.xyz;
        bool _11274 = any(lessThan(_11271, vec3(0.0)));
        bool _11282 = false;
        if (!_11274)
        {
            _11282 = any(greaterThanEqual(_11271, frag_info.gi_counts.xyz));
        }
        else
        {
            _11282 = _11274;
        }
        vec3 mp_copy_21526 = vec3(0.0);
        highp float _11283 = _11282 ? 0.0 : 1.0;
        float mp_copy_11283 = _11283;
        vec3 _11289 = max(mix(_8990, mp_copy_8854, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11305 = (_11266 * frag_info.gi_grid.xyz) - _8843;
        highp float _11307 = length(_11305);
        highp vec3 _21526 = vec3(0.0);
        if (_11307 > 9.9999997473787516355514526367188e-06)
        {
            _21526 = _11305 / vec3(_11307);
        }
        else
        {
            _21526 = _21417;
        }
        mp_copy_21526 = _21526;
        float _11325 = pow((dot(_21526, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11450 = _11266 - (frag_info.gi_counts.xyz * floor(_11266 / frag_info.gi_counts.xyz));
        highp float _11466 = _11450.x + (frag_info.gi_counts.x * (_11450.y + (frag_info.gi_counts.y * _11450.z)));
        float _21531 = 0.0;
        if (_9041)
        {
            highp float _11474 = floor(_11466 / frag_info.gi_counts.w);
            highp vec2 _11488 = vec2((_11466 - (_11474 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11474 * 16.0));
            vec3 _11348 = -mp_copy_21526;
            vec3 _11536 = _11348 / vec3((abs(_11348.x) + abs(_11348.y)) + abs(_11348.z));
            vec2 _21527 = vec2(0.0);
            if (_11536.z >= 0.0)
            {
                _21527 = _11536.xy;
            }
            else
            {
                _21527 = (vec2(1.0) - abs(_11536.yx)) * vec2((_11536.x >= 0.0) ? 1.0 : (-1.0), (_11536.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11352 = texture(irradiance_field, clamp((_11488 + vec2(1.0)) + (clamp((_21527 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11488 + vec2(0.5), _11488 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11357 = _11352.x * frag_info.gi_visibility.z;
            highp float _11369 = abs((_11357 * _11357) - ((_11352.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11375 = (_11307 - _11357) - frag_info.gi_visibility.y;
            highp float _21528 = 0.0;
            if (_11375 <= 0.0)
            {
                _21528 = 1.0;
            }
            else
            {
                _21528 = _11369 / (_11369 + (_11375 * _11375));
            }
            _21531 = _11325 * mix(1.0, max(0.0500000007450580596923828125, (_21528 * _21528) * _21528), frag_info.gi_visibility.x);
        }
        else
        {
            _21531 = _11325;
        }
        float _11403 = max(9.9999999747524270787835121154785e-07, _21531);
        float _21532 = 0.0;
        if (_11403 < 0.20000000298023223876953125)
        {
            _21532 = _11403 * ((_11403 * _11403) * 25.0);
        }
        else
        {
            _21532 = _11403;
        }
        float _11418 = _21532 * (((_11289.x * _11289.y) * _11289.z) * mp_copy_11283);
        highp float _11577 = floor(_11466 / frag_info.gi_counts.w);
        highp vec2 _11591 = vec2((_11466 - (_11577 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11577 * 8.0));
        vec2 _21533 = vec2(0.0);
        if (_9347)
        {
            _21533 = _9344.xy;
        }
        else
        {
            _21533 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11430 = texture(irradiance_field, clamp((_11591 + vec2(1.0)) + (clamp((_21533 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11591 + vec2(0.5), _11591 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11725 = _8848 + vec3(0.0, 1.0, 1.0);
        highp vec3 _11730 = _11725 - frag_info.gi_anchor.xyz;
        bool _11733 = any(lessThan(_11730, vec3(0.0)));
        bool _11741 = false;
        if (!_11733)
        {
            _11741 = any(greaterThanEqual(_11730, frag_info.gi_counts.xyz));
        }
        else
        {
            _11741 = _11733;
        }
        vec3 mp_copy_21535 = vec3(0.0);
        highp float _11742 = _11741 ? 0.0 : 1.0;
        float mp_copy_11742 = _11742;
        vec3 _11748 = max(mix(_8990, mp_copy_8854, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11764 = (_11725 * frag_info.gi_grid.xyz) - _8843;
        highp float _11766 = length(_11764);
        highp vec3 _21535 = vec3(0.0);
        if (_11766 > 9.9999997473787516355514526367188e-06)
        {
            _21535 = _11764 / vec3(_11766);
        }
        else
        {
            _21535 = _21417;
        }
        mp_copy_21535 = _21535;
        float _11784 = pow((dot(_21535, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11909 = _11725 - (frag_info.gi_counts.xyz * floor(_11725 / frag_info.gi_counts.xyz));
        highp float _11925 = _11909.x + (frag_info.gi_counts.x * (_11909.y + (frag_info.gi_counts.y * _11909.z)));
        float _21540 = 0.0;
        if (_9041)
        {
            highp float _11933 = floor(_11925 / frag_info.gi_counts.w);
            highp vec2 _11947 = vec2((_11925 - (_11933 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11933 * 16.0));
            vec3 _11807 = -mp_copy_21535;
            vec3 _11995 = _11807 / vec3((abs(_11807.x) + abs(_11807.y)) + abs(_11807.z));
            vec2 _21536 = vec2(0.0);
            if (_11995.z >= 0.0)
            {
                _21536 = _11995.xy;
            }
            else
            {
                _21536 = (vec2(1.0) - abs(_11995.yx)) * vec2((_11995.x >= 0.0) ? 1.0 : (-1.0), (_11995.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11811 = texture(irradiance_field, clamp((_11947 + vec2(1.0)) + (clamp((_21536 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11947 + vec2(0.5), _11947 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11816 = _11811.x * frag_info.gi_visibility.z;
            highp float _11828 = abs((_11816 * _11816) - ((_11811.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11834 = (_11766 - _11816) - frag_info.gi_visibility.y;
            highp float _21537 = 0.0;
            if (_11834 <= 0.0)
            {
                _21537 = 1.0;
            }
            else
            {
                _21537 = _11828 / (_11828 + (_11834 * _11834));
            }
            _21540 = _11784 * mix(1.0, max(0.0500000007450580596923828125, (_21537 * _21537) * _21537), frag_info.gi_visibility.x);
        }
        else
        {
            _21540 = _11784;
        }
        float _11862 = max(9.9999999747524270787835121154785e-07, _21540);
        float _21541 = 0.0;
        if (_11862 < 0.20000000298023223876953125)
        {
            _21541 = _11862 * ((_11862 * _11862) * 25.0);
        }
        else
        {
            _21541 = _11862;
        }
        float _11877 = _21541 * (((_11748.x * _11748.y) * _11748.z) * mp_copy_11742);
        highp float _12036 = floor(_11925 / frag_info.gi_counts.w);
        highp vec2 _12050 = vec2((_11925 - (_12036 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12036 * 8.0));
        vec2 _21542 = vec2(0.0);
        if (_9347)
        {
            _21542 = _9344.xy;
        }
        else
        {
            _21542 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11889 = texture(irradiance_field, clamp((_12050 + vec2(1.0)) + (clamp((_21542 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12050 + vec2(0.5), _12050 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _12184 = _8848 + vec3(1.0);
        highp vec3 _12189 = _12184 - frag_info.gi_anchor.xyz;
        bool _12192 = any(lessThan(_12189, vec3(0.0)));
        bool _12200 = false;
        if (!_12192)
        {
            _12200 = any(greaterThanEqual(_12189, frag_info.gi_counts.xyz));
        }
        else
        {
            _12200 = _12192;
        }
        vec3 mp_copy_21544 = vec3(0.0);
        highp float _12201 = _12200 ? 0.0 : 1.0;
        float mp_copy_12201 = _12201;
        vec3 _12207 = max(mp_copy_8854, vec3(0.001000000047497451305389404296875));
        highp vec3 _12223 = (_12184 * frag_info.gi_grid.xyz) - _8843;
        highp float _12225 = length(_12223);
        highp vec3 _21544 = vec3(0.0);
        if (_12225 > 9.9999997473787516355514526367188e-06)
        {
            _21544 = _12223 / vec3(_12225);
        }
        else
        {
            _21544 = _21417;
        }
        mp_copy_21544 = _21544;
        float _12243 = pow((dot(_21544, _21417) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _12368 = _12184 - (frag_info.gi_counts.xyz * floor(_12184 / frag_info.gi_counts.xyz));
        highp float _12384 = _12368.x + (frag_info.gi_counts.x * (_12368.y + (frag_info.gi_counts.y * _12368.z)));
        float _21549 = 0.0;
        if (_9041)
        {
            highp float _12392 = floor(_12384 / frag_info.gi_counts.w);
            highp vec2 _12406 = vec2((_12384 - (_12392 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12392 * 16.0));
            vec3 _12266 = -mp_copy_21544;
            vec3 _12454 = _12266 / vec3((abs(_12266.x) + abs(_12266.y)) + abs(_12266.z));
            vec2 _21545 = vec2(0.0);
            if (_12454.z >= 0.0)
            {
                _21545 = _12454.xy;
            }
            else
            {
                _21545 = (vec2(1.0) - abs(_12454.yx)) * vec2((_12454.x >= 0.0) ? 1.0 : (-1.0), (_12454.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12270 = texture(irradiance_field, clamp((_12406 + vec2(1.0)) + (clamp((_21545 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12406 + vec2(0.5), _12406 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _12275 = _12270.x * frag_info.gi_visibility.z;
            highp float _12287 = abs((_12275 * _12275) - ((_12270.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _12293 = (_12225 - _12275) - frag_info.gi_visibility.y;
            highp float _21546 = 0.0;
            if (_12293 <= 0.0)
            {
                _21546 = 1.0;
            }
            else
            {
                _21546 = _12287 / (_12287 + (_12293 * _12293));
            }
            _21549 = _12243 * mix(1.0, max(0.0500000007450580596923828125, (_21546 * _21546) * _21546), frag_info.gi_visibility.x);
        }
        else
        {
            _21549 = _12243;
        }
        float _12321 = max(9.9999999747524270787835121154785e-07, _21549);
        float _21550 = 0.0;
        if (_12321 < 0.20000000298023223876953125)
        {
            _21550 = _12321 * ((_12321 * _12321) * 25.0);
        }
        else
        {
            _21550 = _12321;
        }
        float _12336 = _21550 * (((_12207.x * _12207.y) * _12207.z) * mp_copy_12201);
        highp float _12495 = floor(_12384 / frag_info.gi_counts.w);
        highp vec2 _12509 = vec2((_12384 - (_12495 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12495 * 8.0));
        vec2 _21551 = vec2(0.0);
        if (_9347)
        {
            _21551 = _9344.xy;
        }
        else
        {
            _21551 = (vec2(1.0) - abs(_9344.yx)) * vec2((_9344.x >= 0.0) ? 1.0 : (-1.0), (_9344.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _8901 = ((((((vec4(max(_9135.xyz, vec3(0.0)) * _9123, _9123) + vec4(max(_9594.xyz, vec3(0.0)) * _9582, _9582)) + vec4(max(_10053.xyz, vec3(0.0)) * _10041, _10041)) + vec4(max(_10512.xyz, vec3(0.0)) * _10500, _10500)) + vec4(max(_10971.xyz, vec3(0.0)) * _10959, _10959)) + vec4(max(_11430.xyz, vec3(0.0)) * _11418, _11418)) + vec4(max(_11889.xyz, vec3(0.0)) * _11877, _11877)) + vec4(max(texture(irradiance_field, clamp((_12509 + vec2(1.0)) + (clamp((_21551 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12509 + vec2(0.5), _12509 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _12336, _12336);
        highp float _8903 = _8901.w;
        highp vec3 _21553 = vec3(0.0);
        if (_8903 > 9.9999999747524270787835121154785e-07)
        {
            _21553 = _8901.xyz / vec3(_8903);
        }
        else
        {
            _21553 = vec3(0.0);
        }
        _21671 = mix(_7217, _21553 * _8730, vec3(_21480));
    }
    else
    {
        _21671 = _7217;
    }
    vec2 _7243 = clamp(vec2(_7155, _21453), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _7245 = texture(brdf_lut, vec2(_7243.x * 0.3333333432674407958984375, _7243.y));
    float _7249 = _7245.x;
    float _7252 = _7245.y;
    vec3 _7254 = ((_7147 + ((max(vec3(1.0 - _21453), _7147) - _7147) * pow(clamp(1.0 - _7155, 0.0, 1.0), 5.0))) * _7249) + vec3(_7252);
    float _7260 = 1.0 - (_7249 + _7252);
    vec3 _7264 = vec3(1.0) - _7147;
    vec3 _7267 = _7147 + (_7264 * vec3(0.0476190485060214996337890625));
    vec3 _7278 = ((_7254 * _7260) * _7267) / (vec3(1.0) - (_7267 * _7260));
    float _7281 = 1.0 - _6184;
    vec3 _7282 = _7052 * _7281;
    float _22409 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _7175)
    {
        float _12617 = max(acos(clamp(exp2(((-3.321929931640625) * _21453) * _21453), 0.0, 1.0)), 0.100000001490116119384765625);
        _22409 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_21468, _7159), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _21741, 0.0, 1.0)))) + _12617) / (2.0 * _12617), 0.0, 1.0));
    }
    else
    {
        float _22410 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _22410 = clamp((pow(_7151 + _21741, exp2(((-16.0) * _21453) - 1.0)) - 1.0) + _21741, 0.0, 1.0);
        }
        else
        {
            _22410 = _21741;
        }
        _22409 = _22410;
    }
    bool _7331 = frag_info.has_directional_light > 0.5;
    float _21863 = 0.0;
    vec3 _22493 = vec3(0.0);
    if (_7331)
    {
        highp vec3 _7337 = -normalize(frag_info.directional_light_direction.xyz);
        _22493 = _7337;
        _21863 = dot(_6051, _7337);
    }
    else
    {
        _22493 = vec3(0.0);
        _21863 = 0.0;
    }
    float _7344 = clamp(_21863 * 6.666666507720947265625, 0.0, 1.0);
    bool _7353 = false;
    if (_7331)
    {
        _7353 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _7353 = _7331;
    }
    float _22100 = 0.0;
    if (_7353 && (_7344 > 0.0))
    {
        int _12738 = int(frag_info.shadow_cascade_count);
        float _13187 = max(dot(_6051, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _13190 = _13187 * _13187;
        highp vec3 _13210 = v_position + (_6051 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _13190, 0.0)) / _13190, 8.0))));
        highp float _12744 = frag_info.directional_light_color.w * 0.5;
        float _21917 = 0.0;
        float _21957 = 0.0;
        if (_12738 > 0)
        {
            highp vec4 _12761 = frag_info.light_space_matrix[0] * vec4(_13210, 1.0);
            highp vec3 _12767 = _12761.xyz / vec3(_12761.w);
            highp vec2 _12770 = _12767.xy * 0.5;
            highp vec2 _12772 = _12770 + vec2(0.5);
            highp float _12779 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
            highp float _12781 = _12772.x;
            bool _12783 = _12781 < _12779;
            bool _12792 = false;
            if (!_12783)
            {
                _12792 = _12781 > (1.0 - _12779);
            }
            else
            {
                _12792 = _12783;
            }
            bool _12800 = false;
            if (!_12792)
            {
                _12800 = _12772.y < _12779;
            }
            else
            {
                _12800 = _12792;
            }
            bool _12809 = false;
            if (!_12800)
            {
                _12809 = _12772.y > (1.0 - _12779);
            }
            else
            {
                _12809 = _12800;
            }
            bool _12816 = false;
            if (!_12809)
            {
                _12816 = _12767.z < 0.0;
            }
            else
            {
                _12816 = _12809;
            }
            bool _12823 = false;
            if (!_12816)
            {
                _12823 = _12767.z > 1.0;
            }
            else
            {
                _12823 = _12816;
            }
            float _21918 = 0.0;
            float _21958 = 0.0;
            if (!_12823)
            {
                highp vec2 _13218 = vec2(_12779);
                highp vec2 _13223 = vec2(_12779 + max(_12744, 9.9999997473787516355514526367188e-05));
                highp vec2 _13231 = vec2(0.5) - _12770;
                highp vec2 _13233 = smoothstep(_13218, _13223, _12772) * smoothstep(_13218, _13223, _13231);
                float _21864 = 0.0;
                if (_12744 > 0.0)
                {
                    _21864 = _13233.x * _13233.y;
                }
                else
                {
                    _21864 = 1.0;
                }
                float _12832 = min(_21864, 1.0);
                bool _12834 = _12832 > 0.0;
                float _21959 = 0.0;
                if (_12834)
                {
                    highp float _13345 = _12767.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                    highp float _13351 = 1.0 / (float(_12738) + frag_info.spot_shadow_params.x);
                    highp float _13353 = frag_info.directional_light_direction.w;
                    float mp_copy_13353 = _13353;
                    float _13359 = step(0.5, mp_copy_13353) * (1.0 - step(1.5, mp_copy_13353));
                    highp float _13370 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _13359);
                    float mp_copy_13370 = _13370;
                    float _13372 = cos(mp_copy_13370);
                    float _13374 = sin(mp_copy_13370);
                    highp float _21882 = 0.0;
                    if ((_13353 > 1.5) && (_13353 < 2.5))
                    {
                        highp float _13393 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _13398 = max(_13393 * _13345, frag_info.shadow_texel_size);
                        float _21872 = 0.0;
                        highp float _21873 = 0.0;
                        _21873 = 0.0;
                        _21872 = 0.0;
                        highp float _13420 = 0.0;
                        float _13423 = 0.0;
                        for (int _21871 = 0; _21871 < 9; _21873 = _13420, _21872 = _13423, _21871++)
                        {
                            vec2 _22888 = vec2(0.0);
                            do
                            {
                                if (_21871 == 0)
                                {
                                    _22888 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21871 == 1)
                                {
                                    _22888 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21871 == 2)
                                {
                                    _22888 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21871 == 3)
                                {
                                    _22888 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21871 == 4)
                                {
                                    _22888 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21871 == 5)
                                {
                                    _22888 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21871 == 6)
                                {
                                    _22888 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21871 == 7)
                                {
                                    _22888 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21871 == 8)
                                {
                                    _22888 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21871 == 9)
                                {
                                    _22888 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21871 == 10)
                                {
                                    _22888 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21871 == 11)
                                {
                                    _22888 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21871 == 12)
                                {
                                    _22888 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21871 == 13)
                                {
                                    _22888 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21871 == 14)
                                {
                                    _22888 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21871 == 15)
                                {
                                    _22888 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22888 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _13665 = clamp(_12772 + (vec2((_22888.x * _13372) - (_22888.y * _13374), (_22888.x * _13374) + (_22888.y * _13372)) * _13398), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _13674 = _13665.y;
                            highp vec2 _13675 = vec2(_13665.x * _13351, _13674);
                            _13675.y = 1.0 - _13674;
                            highp vec4 _13682 = texture(shadow_map, _13675);
                            highp float _13683 = _13682.x;
                            highp float _13415 = step(_13683, _13345);
                            float mp_copy_13415 = _13415;
                            _13420 = _21873 + (_13683 * _13415);
                            _13423 = _21872 + mp_copy_13415;
                        }
                        highp float _21874 = 0.0;
                        if (_21872 > 0.0)
                        {
                            _21874 = _21873 / _21872;
                        }
                        else
                        {
                            _21874 = _13345;
                        }
                        _21882 = clamp(_13393 * max(_13345 - _21874, 0.0), frag_info.shadow_texel_size, _12779);
                    }
                    else
                    {
                        _21882 = _12779;
                    }
                    float _21889 = 0.0;
                    if (_13353 > 2.5)
                    {
                        highp vec2 _13711 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _13715 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _13716 = clamp(_12772 + (vec2(-0.707099974155426025390625) * _21882), _13711, _13715);
                        highp vec2 _13727 = (vec2(_13716.x, 1.0 - _13716.y) / _13711) - vec2(0.5);
                        highp vec2 _13729 = floor(_13727);
                        highp vec2 _13732 = _13727 - _13729;
                        highp vec2 _13737 = (_13729 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13747 = vec2(_13737.x * _13351, _13737.y);
                        highp float _13751 = frag_info.shadow_texel_size * _13351;
                        highp vec2 _13754 = vec2(_13751, frag_info.shadow_texel_size);
                        highp vec2 _13763 = vec2(_13751, 0.0);
                        highp vec2 _13771 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _13800 = _13732.x;
                        highp float _13809 = mix(mix(float(_13345 <= texture(shadow_map, _13747).x), float(_13345 <= texture(shadow_map, _13747 + _13763).x), _13800), mix(float(_13345 <= texture(shadow_map, _13747 + _13771).x), float(_13345 <= texture(shadow_map, _13747 + _13754).x), _13800), _13732.y);
                        float mp_copy_13809 = _13809;
                        highp vec2 _13843 = clamp(_12772 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21882), _13711, _13715);
                        highp vec2 _13854 = (vec2(_13843.x, 1.0 - _13843.y) / _13711) - vec2(0.5);
                        highp vec2 _13856 = floor(_13854);
                        highp vec2 _13859 = _13854 - _13856;
                        highp vec2 _13864 = (_13856 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13874 = vec2(_13864.x * _13351, _13864.y);
                        highp float _13927 = _13859.x;
                        highp float _13936 = mix(mix(float(_13345 <= texture(shadow_map, _13874).x), float(_13345 <= texture(shadow_map, _13874 + _13763).x), _13927), mix(float(_13345 <= texture(shadow_map, _13874 + _13771).x), float(_13345 <= texture(shadow_map, _13874 + _13754).x), _13927), _13859.y);
                        float mp_copy_13936 = _13936;
                        highp vec2 _13970 = clamp(_12772 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21882), _13711, _13715);
                        highp vec2 _13981 = (vec2(_13970.x, 1.0 - _13970.y) / _13711) - vec2(0.5);
                        highp vec2 _13983 = floor(_13981);
                        highp vec2 _13986 = _13981 - _13983;
                        highp vec2 _13991 = (_13983 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14001 = vec2(_13991.x * _13351, _13991.y);
                        highp float _14054 = _13986.x;
                        highp float _14063 = mix(mix(float(_13345 <= texture(shadow_map, _14001).x), float(_13345 <= texture(shadow_map, _14001 + _13763).x), _14054), mix(float(_13345 <= texture(shadow_map, _14001 + _13771).x), float(_13345 <= texture(shadow_map, _14001 + _13754).x), _14054), _13986.y);
                        float mp_copy_14063 = _14063;
                        highp vec2 _14097 = clamp(_12772 + (vec2(0.707099974155426025390625) * _21882), _13711, _13715);
                        highp vec2 _14108 = (vec2(_14097.x, 1.0 - _14097.y) / _13711) - vec2(0.5);
                        highp vec2 _14110 = floor(_14108);
                        highp vec2 _14113 = _14108 - _14110;
                        highp vec2 _14118 = (_14110 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14128 = vec2(_14118.x * _13351, _14118.y);
                        highp float _14181 = _14113.x;
                        highp float _14190 = mix(mix(float(_13345 <= texture(shadow_map, _14128).x), float(_13345 <= texture(shadow_map, _14128 + _13763).x), _14181), mix(float(_13345 <= texture(shadow_map, _14128 + _13771).x), float(_13345 <= texture(shadow_map, _14128 + _13754).x), _14181), _14113.y);
                        float mp_copy_14190 = _14190;
                        _21889 = (((mp_copy_13809 + mp_copy_13936) + mp_copy_14063) + mp_copy_14190) * 0.25;
                    }
                    else
                    {
                        int _13486 = (_13359 > 0.5) ? 17 : 16;
                        float _21885 = 0.0;
                        _21885 = 0.0;
                        float _13514 = 0.0;
                        for (int _21875 = 0; _21875 < 17; _21885 = _13514, _21875++)
                        {
                            if (_21875 >= _13486)
                            {
                                break;
                            }
                            vec2 _21876 = vec2(0.0);
                            do
                            {
                                if (_21875 == 0)
                                {
                                    _21876 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21875 == 1)
                                {
                                    _21876 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21875 == 2)
                                {
                                    _21876 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21875 == 3)
                                {
                                    _21876 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21875 == 4)
                                {
                                    _21876 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21875 == 5)
                                {
                                    _21876 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21875 == 6)
                                {
                                    _21876 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21875 == 7)
                                {
                                    _21876 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21875 == 8)
                                {
                                    _21876 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21875 == 9)
                                {
                                    _21876 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21875 == 10)
                                {
                                    _21876 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21875 == 11)
                                {
                                    _21876 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21875 == 12)
                                {
                                    _21876 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21875 == 13)
                                {
                                    _21876 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21875 == 14)
                                {
                                    _21876 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21875 == 15)
                                {
                                    _21876 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21876 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21878 = vec2(0.0);
                            do
                            {
                                if (_21875 < 3)
                                {
                                    _21878 = vec2(float(_21875) - 1.0, -1.0);
                                    break;
                                }
                                if (_21875 < 6)
                                {
                                    _21878 = vec2((float(_21875 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21875 < 11)
                                {
                                    _21878 = vec2((float(_21875 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21875 < 14)
                                {
                                    _21878 = vec2((float(_21875 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21878 = vec2(float(_21875 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _13503 = mix(_21876, _21878, vec2(_13359));
                            float _14330 = _13503.x;
                            float _14334 = _13503.y;
                            highp vec2 _14360 = clamp(_12772 + (vec2((_14330 * _13372) - (_14334 * _13374), (_14330 * _13374) + (_14334 * _13372)) * _21882), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _14370 = vec2(_14360.x * _13351, _14360.y);
                            _14370.y = 1.0 - _14360.y;
                            highp float _14382 = float(_13345 <= texture(shadow_map, _14370).x);
                            float mp_copy_14382 = _14382;
                            _13514 = _21885 + mp_copy_14382;
                        }
                        _21889 = _21885 / float(_13486);
                    }
                    bool _13527 = 0 == (_12738 - 1);
                    bool _13533 = false;
                    if (_13527)
                    {
                        _13533 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _13533 = _13527;
                    }
                    float _21890 = 0.0;
                    if (_13533)
                    {
                        highp vec2 _13540 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                        highp vec2 _13548 = smoothstep(vec2(0.0), _13540, _12772) * smoothstep(vec2(0.0), _13540, _13231);
                        _21890 = mix(1.0, _21889, _13548.x * _13548.y);
                    }
                    else
                    {
                        _21890 = _21889;
                    }
                    _21959 = _12832 * _21890;
                }
                else
                {
                    _21959 = 0.0;
                }
                _21958 = _21959;
                _21918 = _12834 ? _12832 : 0.0;
            }
            else
            {
                _21958 = 0.0;
                _21918 = 0.0;
            }
            _21957 = _21958;
            _21917 = _21918;
        }
        else
        {
            _21957 = 0.0;
            _21917 = 0.0;
        }
        float _21976 = 0.0;
        float _22016 = 0.0;
        if ((_21917 < 1.0) && (_12738 > 1))
        {
            highp vec4 _12867 = frag_info.light_space_matrix[1] * vec4(_13210, 1.0);
            highp vec3 _12873 = _12867.xyz / vec3(_12867.w);
            highp vec2 _12876 = _12873.xy * 0.5;
            highp vec2 _12878 = _12876 + vec2(0.5);
            highp float _12885 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
            highp float _12887 = _12878.x;
            bool _12889 = _12887 < _12885;
            bool _12898 = false;
            if (!_12889)
            {
                _12898 = _12887 > (1.0 - _12885);
            }
            else
            {
                _12898 = _12889;
            }
            bool _12906 = false;
            if (!_12898)
            {
                _12906 = _12878.y < _12885;
            }
            else
            {
                _12906 = _12898;
            }
            bool _12915 = false;
            if (!_12906)
            {
                _12915 = _12878.y > (1.0 - _12885);
            }
            else
            {
                _12915 = _12906;
            }
            bool _12922 = false;
            if (!_12915)
            {
                _12922 = _12873.z < 0.0;
            }
            else
            {
                _12922 = _12915;
            }
            bool _12929 = false;
            if (!_12922)
            {
                _12929 = _12873.z > 1.0;
            }
            else
            {
                _12929 = _12922;
            }
            float _21977 = 0.0;
            float _22017 = 0.0;
            if (!_12929)
            {
                highp vec2 _14390 = vec2(_12885);
                highp vec2 _14395 = vec2(_12885 + max(_12744, 9.9999997473787516355514526367188e-05));
                highp vec2 _14403 = vec2(0.5) - _12876;
                highp vec2 _14405 = smoothstep(_14390, _14395, _12878) * smoothstep(_14390, _14395, _14403);
                float _21920 = 0.0;
                if (_12744 > 0.0)
                {
                    _21920 = _14405.x * _14405.y;
                }
                else
                {
                    _21920 = 1.0;
                }
                float _12938 = min(_21920, 1.0 - _21917);
                float _21978 = 0.0;
                float _22018 = 0.0;
                if (_12938 > 0.0)
                {
                    highp float _14517 = _12873.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                    highp float _14523 = 1.0 / (float(_12738) + frag_info.spot_shadow_params.x);
                    highp float _14525 = frag_info.directional_light_direction.w;
                    float mp_copy_14525 = _14525;
                    float _14531 = step(0.5, mp_copy_14525) * (1.0 - step(1.5, mp_copy_14525));
                    highp float _14542 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14531);
                    float mp_copy_14542 = _14542;
                    float _14544 = cos(mp_copy_14542);
                    float _14546 = sin(mp_copy_14542);
                    highp float _21938 = 0.0;
                    if ((_14525 > 1.5) && (_14525 < 2.5))
                    {
                        highp float _14565 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _14570 = max(_14565 * _14517, frag_info.shadow_texel_size);
                        float _21928 = 0.0;
                        highp float _21929 = 0.0;
                        _21929 = 0.0;
                        _21928 = 0.0;
                        highp float _14592 = 0.0;
                        float _14595 = 0.0;
                        for (int _21927 = 0; _21927 < 9; _21929 = _14592, _21928 = _14595, _21927++)
                        {
                            vec2 _22884 = vec2(0.0);
                            do
                            {
                                if (_21927 == 0)
                                {
                                    _22884 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21927 == 1)
                                {
                                    _22884 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21927 == 2)
                                {
                                    _22884 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21927 == 3)
                                {
                                    _22884 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21927 == 4)
                                {
                                    _22884 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21927 == 5)
                                {
                                    _22884 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21927 == 6)
                                {
                                    _22884 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21927 == 7)
                                {
                                    _22884 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21927 == 8)
                                {
                                    _22884 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21927 == 9)
                                {
                                    _22884 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21927 == 10)
                                {
                                    _22884 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21927 == 11)
                                {
                                    _22884 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21927 == 12)
                                {
                                    _22884 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21927 == 13)
                                {
                                    _22884 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21927 == 14)
                                {
                                    _22884 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21927 == 15)
                                {
                                    _22884 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22884 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _14837 = clamp(_12878 + (vec2((_22884.x * _14544) - (_22884.y * _14546), (_22884.x * _14546) + (_22884.y * _14544)) * _14570), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _14846 = _14837.y;
                            highp vec2 _14847 = vec2((1.0 + _14837.x) * _14523, _14846);
                            _14847.y = 1.0 - _14846;
                            highp vec4 _14854 = texture(shadow_map, _14847);
                            highp float _14855 = _14854.x;
                            highp float _14587 = step(_14855, _14517);
                            float mp_copy_14587 = _14587;
                            _14592 = _21929 + (_14855 * _14587);
                            _14595 = _21928 + mp_copy_14587;
                        }
                        highp float _21930 = 0.0;
                        if (_21928 > 0.0)
                        {
                            _21930 = _21929 / _21928;
                        }
                        else
                        {
                            _21930 = _14517;
                        }
                        _21938 = clamp(_14565 * max(_14517 - _21930, 0.0), frag_info.shadow_texel_size, _12885);
                    }
                    else
                    {
                        _21938 = _12885;
                    }
                    float _21945 = 0.0;
                    if (_14525 > 2.5)
                    {
                        highp vec2 _14883 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _14887 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _14888 = clamp(_12878 + (vec2(-0.707099974155426025390625) * _21938), _14883, _14887);
                        highp vec2 _14899 = (vec2(_14888.x, 1.0 - _14888.y) / _14883) - vec2(0.5);
                        highp vec2 _14901 = floor(_14899);
                        highp vec2 _14904 = _14899 - _14901;
                        highp vec2 _14909 = (_14901 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14919 = vec2((1.0 + _14909.x) * _14523, _14909.y);
                        highp float _14923 = frag_info.shadow_texel_size * _14523;
                        highp vec2 _14926 = vec2(_14923, frag_info.shadow_texel_size);
                        highp vec2 _14935 = vec2(_14923, 0.0);
                        highp vec2 _14943 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _14972 = _14904.x;
                        highp float _14981 = mix(mix(float(_14517 <= texture(shadow_map, _14919).x), float(_14517 <= texture(shadow_map, _14919 + _14935).x), _14972), mix(float(_14517 <= texture(shadow_map, _14919 + _14943).x), float(_14517 <= texture(shadow_map, _14919 + _14926).x), _14972), _14904.y);
                        float mp_copy_14981 = _14981;
                        highp vec2 _15015 = clamp(_12878 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21938), _14883, _14887);
                        highp vec2 _15026 = (vec2(_15015.x, 1.0 - _15015.y) / _14883) - vec2(0.5);
                        highp vec2 _15028 = floor(_15026);
                        highp vec2 _15031 = _15026 - _15028;
                        highp vec2 _15036 = (_15028 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15046 = vec2((1.0 + _15036.x) * _14523, _15036.y);
                        highp float _15099 = _15031.x;
                        highp float _15108 = mix(mix(float(_14517 <= texture(shadow_map, _15046).x), float(_14517 <= texture(shadow_map, _15046 + _14935).x), _15099), mix(float(_14517 <= texture(shadow_map, _15046 + _14943).x), float(_14517 <= texture(shadow_map, _15046 + _14926).x), _15099), _15031.y);
                        float mp_copy_15108 = _15108;
                        highp vec2 _15142 = clamp(_12878 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21938), _14883, _14887);
                        highp vec2 _15153 = (vec2(_15142.x, 1.0 - _15142.y) / _14883) - vec2(0.5);
                        highp vec2 _15155 = floor(_15153);
                        highp vec2 _15158 = _15153 - _15155;
                        highp vec2 _15163 = (_15155 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15173 = vec2((1.0 + _15163.x) * _14523, _15163.y);
                        highp float _15226 = _15158.x;
                        highp float _15235 = mix(mix(float(_14517 <= texture(shadow_map, _15173).x), float(_14517 <= texture(shadow_map, _15173 + _14935).x), _15226), mix(float(_14517 <= texture(shadow_map, _15173 + _14943).x), float(_14517 <= texture(shadow_map, _15173 + _14926).x), _15226), _15158.y);
                        float mp_copy_15235 = _15235;
                        highp vec2 _15269 = clamp(_12878 + (vec2(0.707099974155426025390625) * _21938), _14883, _14887);
                        highp vec2 _15280 = (vec2(_15269.x, 1.0 - _15269.y) / _14883) - vec2(0.5);
                        highp vec2 _15282 = floor(_15280);
                        highp vec2 _15285 = _15280 - _15282;
                        highp vec2 _15290 = (_15282 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15300 = vec2((1.0 + _15290.x) * _14523, _15290.y);
                        highp float _15353 = _15285.x;
                        highp float _15362 = mix(mix(float(_14517 <= texture(shadow_map, _15300).x), float(_14517 <= texture(shadow_map, _15300 + _14935).x), _15353), mix(float(_14517 <= texture(shadow_map, _15300 + _14943).x), float(_14517 <= texture(shadow_map, _15300 + _14926).x), _15353), _15285.y);
                        float mp_copy_15362 = _15362;
                        _21945 = (((mp_copy_14981 + mp_copy_15108) + mp_copy_15235) + mp_copy_15362) * 0.25;
                    }
                    else
                    {
                        int _14658 = (_14531 > 0.5) ? 17 : 16;
                        float _21941 = 0.0;
                        _21941 = 0.0;
                        float _14686 = 0.0;
                        for (int _21931 = 0; _21931 < 17; _21941 = _14686, _21931++)
                        {
                            if (_21931 >= _14658)
                            {
                                break;
                            }
                            vec2 _21932 = vec2(0.0);
                            do
                            {
                                if (_21931 == 0)
                                {
                                    _21932 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21931 == 1)
                                {
                                    _21932 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21931 == 2)
                                {
                                    _21932 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21931 == 3)
                                {
                                    _21932 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21931 == 4)
                                {
                                    _21932 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21931 == 5)
                                {
                                    _21932 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21931 == 6)
                                {
                                    _21932 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21931 == 7)
                                {
                                    _21932 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21931 == 8)
                                {
                                    _21932 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21931 == 9)
                                {
                                    _21932 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21931 == 10)
                                {
                                    _21932 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21931 == 11)
                                {
                                    _21932 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21931 == 12)
                                {
                                    _21932 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21931 == 13)
                                {
                                    _21932 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21931 == 14)
                                {
                                    _21932 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21931 == 15)
                                {
                                    _21932 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21932 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21934 = vec2(0.0);
                            do
                            {
                                if (_21931 < 3)
                                {
                                    _21934 = vec2(float(_21931) - 1.0, -1.0);
                                    break;
                                }
                                if (_21931 < 6)
                                {
                                    _21934 = vec2((float(_21931 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21931 < 11)
                                {
                                    _21934 = vec2((float(_21931 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21931 < 14)
                                {
                                    _21934 = vec2((float(_21931 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21934 = vec2(float(_21931 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _14675 = mix(_21932, _21934, vec2(_14531));
                            float _15502 = _14675.x;
                            float _15506 = _14675.y;
                            highp vec2 _15532 = clamp(_12878 + (vec2((_15502 * _14544) - (_15506 * _14546), (_15502 * _14546) + (_15506 * _14544)) * _21938), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _15542 = vec2((1.0 + _15532.x) * _14523, _15532.y);
                            _15542.y = 1.0 - _15532.y;
                            highp float _15554 = float(_14517 <= texture(shadow_map, _15542).x);
                            float mp_copy_15554 = _15554;
                            _14686 = _21941 + mp_copy_15554;
                        }
                        _21945 = _21941 / float(_14658);
                    }
                    bool _14699 = 1 == (_12738 - 1);
                    bool _14705 = false;
                    if (_14699)
                    {
                        _14705 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _14705 = _14699;
                    }
                    float _21946 = 0.0;
                    if (_14705)
                    {
                        highp vec2 _14712 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                        highp vec2 _14720 = smoothstep(vec2(0.0), _14712, _12878) * smoothstep(vec2(0.0), _14712, _14403);
                        _21946 = mix(1.0, _21945, _14720.x * _14720.y);
                    }
                    else
                    {
                        _21946 = _21945;
                    }
                    _22018 = _21957 + (_12938 * _21946);
                    _21978 = _21917 + _12938;
                }
                else
                {
                    _22018 = _21957;
                    _21978 = _21917;
                }
                _22017 = _22018;
                _21977 = _21978;
            }
            else
            {
                _22017 = _21957;
                _21977 = _21917;
            }
            _22016 = _22017;
            _21976 = _21977;
        }
        else
        {
            _22016 = _21957;
            _21976 = _21917;
        }
        float _22035 = 0.0;
        float _22075 = 0.0;
        if ((_21976 < 1.0) && (_12738 > 2))
        {
            highp vec4 _12973 = frag_info.light_space_matrix[2] * vec4(_13210, 1.0);
            highp vec3 _12979 = _12973.xyz / vec3(_12973.w);
            highp vec2 _12982 = _12979.xy * 0.5;
            highp vec2 _12984 = _12982 + vec2(0.5);
            highp float _12991 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
            highp float _12993 = _12984.x;
            bool _12995 = _12993 < _12991;
            bool _13004 = false;
            if (!_12995)
            {
                _13004 = _12993 > (1.0 - _12991);
            }
            else
            {
                _13004 = _12995;
            }
            bool _13012 = false;
            if (!_13004)
            {
                _13012 = _12984.y < _12991;
            }
            else
            {
                _13012 = _13004;
            }
            bool _13021 = false;
            if (!_13012)
            {
                _13021 = _12984.y > (1.0 - _12991);
            }
            else
            {
                _13021 = _13012;
            }
            bool _13028 = false;
            if (!_13021)
            {
                _13028 = _12979.z < 0.0;
            }
            else
            {
                _13028 = _13021;
            }
            bool _13035 = false;
            if (!_13028)
            {
                _13035 = _12979.z > 1.0;
            }
            else
            {
                _13035 = _13028;
            }
            float _22036 = 0.0;
            float _22076 = 0.0;
            if (!_13035)
            {
                highp vec2 _15562 = vec2(_12991);
                highp vec2 _15567 = vec2(_12991 + max(_12744, 9.9999997473787516355514526367188e-05));
                highp vec2 _15575 = vec2(0.5) - _12982;
                highp vec2 _15577 = smoothstep(_15562, _15567, _12984) * smoothstep(_15562, _15567, _15575);
                float _21979 = 0.0;
                if (_12744 > 0.0)
                {
                    _21979 = _15577.x * _15577.y;
                }
                else
                {
                    _21979 = 1.0;
                }
                float _13044 = min(_21979, 1.0 - _21976);
                float _22037 = 0.0;
                float _22077 = 0.0;
                if (_13044 > 0.0)
                {
                    highp float _15689 = _12979.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                    highp float _15695 = 1.0 / (float(_12738) + frag_info.spot_shadow_params.x);
                    highp float _15697 = frag_info.directional_light_direction.w;
                    float mp_copy_15697 = _15697;
                    float _15703 = step(0.5, mp_copy_15697) * (1.0 - step(1.5, mp_copy_15697));
                    highp float _15714 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _15703);
                    float mp_copy_15714 = _15714;
                    float _15716 = cos(mp_copy_15714);
                    float _15718 = sin(mp_copy_15714);
                    highp float _21997 = 0.0;
                    if ((_15697 > 1.5) && (_15697 < 2.5))
                    {
                        highp float _15737 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _15742 = max(_15737 * _15689, frag_info.shadow_texel_size);
                        float _21987 = 0.0;
                        highp float _21988 = 0.0;
                        _21988 = 0.0;
                        _21987 = 0.0;
                        highp float _15764 = 0.0;
                        float _15767 = 0.0;
                        for (int _21986 = 0; _21986 < 9; _21988 = _15764, _21987 = _15767, _21986++)
                        {
                            vec2 _22880 = vec2(0.0);
                            do
                            {
                                if (_21986 == 0)
                                {
                                    _22880 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21986 == 1)
                                {
                                    _22880 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21986 == 2)
                                {
                                    _22880 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21986 == 3)
                                {
                                    _22880 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21986 == 4)
                                {
                                    _22880 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21986 == 5)
                                {
                                    _22880 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21986 == 6)
                                {
                                    _22880 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21986 == 7)
                                {
                                    _22880 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21986 == 8)
                                {
                                    _22880 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21986 == 9)
                                {
                                    _22880 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21986 == 10)
                                {
                                    _22880 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21986 == 11)
                                {
                                    _22880 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21986 == 12)
                                {
                                    _22880 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21986 == 13)
                                {
                                    _22880 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21986 == 14)
                                {
                                    _22880 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21986 == 15)
                                {
                                    _22880 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22880 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _16009 = clamp(_12984 + (vec2((_22880.x * _15716) - (_22880.y * _15718), (_22880.x * _15718) + (_22880.y * _15716)) * _15742), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _16018 = _16009.y;
                            highp vec2 _16019 = vec2((2.0 + _16009.x) * _15695, _16018);
                            _16019.y = 1.0 - _16018;
                            highp vec4 _16026 = texture(shadow_map, _16019);
                            highp float _16027 = _16026.x;
                            highp float _15759 = step(_16027, _15689);
                            float mp_copy_15759 = _15759;
                            _15764 = _21988 + (_16027 * _15759);
                            _15767 = _21987 + mp_copy_15759;
                        }
                        highp float _21989 = 0.0;
                        if (_21987 > 0.0)
                        {
                            _21989 = _21988 / _21987;
                        }
                        else
                        {
                            _21989 = _15689;
                        }
                        _21997 = clamp(_15737 * max(_15689 - _21989, 0.0), frag_info.shadow_texel_size, _12991);
                    }
                    else
                    {
                        _21997 = _12991;
                    }
                    float _22004 = 0.0;
                    if (_15697 > 2.5)
                    {
                        highp vec2 _16055 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _16059 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _16060 = clamp(_12984 + (vec2(-0.707099974155426025390625) * _21997), _16055, _16059);
                        highp vec2 _16071 = (vec2(_16060.x, 1.0 - _16060.y) / _16055) - vec2(0.5);
                        highp vec2 _16073 = floor(_16071);
                        highp vec2 _16076 = _16071 - _16073;
                        highp vec2 _16081 = (_16073 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16091 = vec2((2.0 + _16081.x) * _15695, _16081.y);
                        highp float _16095 = frag_info.shadow_texel_size * _15695;
                        highp vec2 _16098 = vec2(_16095, frag_info.shadow_texel_size);
                        highp vec2 _16107 = vec2(_16095, 0.0);
                        highp vec2 _16115 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _16144 = _16076.x;
                        highp float _16153 = mix(mix(float(_15689 <= texture(shadow_map, _16091).x), float(_15689 <= texture(shadow_map, _16091 + _16107).x), _16144), mix(float(_15689 <= texture(shadow_map, _16091 + _16115).x), float(_15689 <= texture(shadow_map, _16091 + _16098).x), _16144), _16076.y);
                        float mp_copy_16153 = _16153;
                        highp vec2 _16187 = clamp(_12984 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _21997), _16055, _16059);
                        highp vec2 _16198 = (vec2(_16187.x, 1.0 - _16187.y) / _16055) - vec2(0.5);
                        highp vec2 _16200 = floor(_16198);
                        highp vec2 _16203 = _16198 - _16200;
                        highp vec2 _16208 = (_16200 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16218 = vec2((2.0 + _16208.x) * _15695, _16208.y);
                        highp float _16271 = _16203.x;
                        highp float _16280 = mix(mix(float(_15689 <= texture(shadow_map, _16218).x), float(_15689 <= texture(shadow_map, _16218 + _16107).x), _16271), mix(float(_15689 <= texture(shadow_map, _16218 + _16115).x), float(_15689 <= texture(shadow_map, _16218 + _16098).x), _16271), _16203.y);
                        float mp_copy_16280 = _16280;
                        highp vec2 _16314 = clamp(_12984 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _21997), _16055, _16059);
                        highp vec2 _16325 = (vec2(_16314.x, 1.0 - _16314.y) / _16055) - vec2(0.5);
                        highp vec2 _16327 = floor(_16325);
                        highp vec2 _16330 = _16325 - _16327;
                        highp vec2 _16335 = (_16327 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16345 = vec2((2.0 + _16335.x) * _15695, _16335.y);
                        highp float _16398 = _16330.x;
                        highp float _16407 = mix(mix(float(_15689 <= texture(shadow_map, _16345).x), float(_15689 <= texture(shadow_map, _16345 + _16107).x), _16398), mix(float(_15689 <= texture(shadow_map, _16345 + _16115).x), float(_15689 <= texture(shadow_map, _16345 + _16098).x), _16398), _16330.y);
                        float mp_copy_16407 = _16407;
                        highp vec2 _16441 = clamp(_12984 + (vec2(0.707099974155426025390625) * _21997), _16055, _16059);
                        highp vec2 _16452 = (vec2(_16441.x, 1.0 - _16441.y) / _16055) - vec2(0.5);
                        highp vec2 _16454 = floor(_16452);
                        highp vec2 _16457 = _16452 - _16454;
                        highp vec2 _16462 = (_16454 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16472 = vec2((2.0 + _16462.x) * _15695, _16462.y);
                        highp float _16525 = _16457.x;
                        highp float _16534 = mix(mix(float(_15689 <= texture(shadow_map, _16472).x), float(_15689 <= texture(shadow_map, _16472 + _16107).x), _16525), mix(float(_15689 <= texture(shadow_map, _16472 + _16115).x), float(_15689 <= texture(shadow_map, _16472 + _16098).x), _16525), _16457.y);
                        float mp_copy_16534 = _16534;
                        _22004 = (((mp_copy_16153 + mp_copy_16280) + mp_copy_16407) + mp_copy_16534) * 0.25;
                    }
                    else
                    {
                        int _15830 = (_15703 > 0.5) ? 17 : 16;
                        float _22000 = 0.0;
                        _22000 = 0.0;
                        float _15858 = 0.0;
                        for (int _21990 = 0; _21990 < 17; _22000 = _15858, _21990++)
                        {
                            if (_21990 >= _15830)
                            {
                                break;
                            }
                            vec2 _21991 = vec2(0.0);
                            do
                            {
                                if (_21990 == 0)
                                {
                                    _21991 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_21990 == 1)
                                {
                                    _21991 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_21990 == 2)
                                {
                                    _21991 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_21990 == 3)
                                {
                                    _21991 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_21990 == 4)
                                {
                                    _21991 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_21990 == 5)
                                {
                                    _21991 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_21990 == 6)
                                {
                                    _21991 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_21990 == 7)
                                {
                                    _21991 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_21990 == 8)
                                {
                                    _21991 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_21990 == 9)
                                {
                                    _21991 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_21990 == 10)
                                {
                                    _21991 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_21990 == 11)
                                {
                                    _21991 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_21990 == 12)
                                {
                                    _21991 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_21990 == 13)
                                {
                                    _21991 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_21990 == 14)
                                {
                                    _21991 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_21990 == 15)
                                {
                                    _21991 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21991 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _21993 = vec2(0.0);
                            do
                            {
                                if (_21990 < 3)
                                {
                                    _21993 = vec2(float(_21990) - 1.0, -1.0);
                                    break;
                                }
                                if (_21990 < 6)
                                {
                                    _21993 = vec2((float(_21990 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_21990 < 11)
                                {
                                    _21993 = vec2((float(_21990 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_21990 < 14)
                                {
                                    _21993 = vec2((float(_21990 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _21993 = vec2(float(_21990 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _15847 = mix(_21991, _21993, vec2(_15703));
                            float _16674 = _15847.x;
                            float _16678 = _15847.y;
                            highp vec2 _16704 = clamp(_12984 + (vec2((_16674 * _15716) - (_16678 * _15718), (_16674 * _15718) + (_16678 * _15716)) * _21997), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _16714 = vec2((2.0 + _16704.x) * _15695, _16704.y);
                            _16714.y = 1.0 - _16704.y;
                            highp float _16726 = float(_15689 <= texture(shadow_map, _16714).x);
                            float mp_copy_16726 = _16726;
                            _15858 = _22000 + mp_copy_16726;
                        }
                        _22004 = _22000 / float(_15830);
                    }
                    bool _15871 = 2 == (_12738 - 1);
                    bool _15877 = false;
                    if (_15871)
                    {
                        _15877 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _15877 = _15871;
                    }
                    float _22005 = 0.0;
                    if (_15877)
                    {
                        highp vec2 _15884 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                        highp vec2 _15892 = smoothstep(vec2(0.0), _15884, _12984) * smoothstep(vec2(0.0), _15884, _15575);
                        _22005 = mix(1.0, _22004, _15892.x * _15892.y);
                    }
                    else
                    {
                        _22005 = _22004;
                    }
                    _22077 = _22016 + (_13044 * _22005);
                    _22037 = _21976 + _13044;
                }
                else
                {
                    _22077 = _22016;
                    _22037 = _21976;
                }
                _22076 = _22077;
                _22036 = _22037;
            }
            else
            {
                _22076 = _22016;
                _22036 = _21976;
            }
            _22075 = _22076;
            _22035 = _22036;
        }
        else
        {
            _22075 = _22016;
            _22035 = _21976;
        }
        float _22094 = 0.0;
        float _22097 = 0.0;
        if ((_22035 < 1.0) && (_12738 > 3))
        {
            highp vec4 _13079 = frag_info.light_space_matrix[3] * vec4(_13210, 1.0);
            highp vec3 _13085 = _13079.xyz / vec3(_13079.w);
            highp vec2 _13088 = _13085.xy * 0.5;
            highp vec2 _13090 = _13088 + vec2(0.5);
            highp float _13097 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
            highp float _13099 = _13090.x;
            bool _13101 = _13099 < _13097;
            bool _13110 = false;
            if (!_13101)
            {
                _13110 = _13099 > (1.0 - _13097);
            }
            else
            {
                _13110 = _13101;
            }
            bool _13118 = false;
            if (!_13110)
            {
                _13118 = _13090.y < _13097;
            }
            else
            {
                _13118 = _13110;
            }
            bool _13127 = false;
            if (!_13118)
            {
                _13127 = _13090.y > (1.0 - _13097);
            }
            else
            {
                _13127 = _13118;
            }
            bool _13134 = false;
            if (!_13127)
            {
                _13134 = _13085.z < 0.0;
            }
            else
            {
                _13134 = _13127;
            }
            bool _13141 = false;
            if (!_13134)
            {
                _13141 = _13085.z > 1.0;
            }
            else
            {
                _13141 = _13134;
            }
            float _22095 = 0.0;
            float _22098 = 0.0;
            if (!_13141)
            {
                highp vec2 _16734 = vec2(_13097);
                highp vec2 _16739 = vec2(_13097 + max(_12744, 9.9999997473787516355514526367188e-05));
                highp vec2 _16747 = vec2(0.5) - _13088;
                highp vec2 _16749 = smoothstep(_16734, _16739, _13090) * smoothstep(_16734, _16739, _16747);
                float _22038 = 0.0;
                if (_12744 > 0.0)
                {
                    _22038 = _16749.x * _16749.y;
                }
                else
                {
                    _22038 = 1.0;
                }
                float _13150 = min(_22038, 1.0 - _22035);
                float _22096 = 0.0;
                float _22099 = 0.0;
                if (_13150 > 0.0)
                {
                    highp float _16861 = _13085.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                    highp float _16867 = 1.0 / (float(_12738) + frag_info.spot_shadow_params.x);
                    highp float _16869 = frag_info.directional_light_direction.w;
                    float mp_copy_16869 = _16869;
                    float _16875 = step(0.5, mp_copy_16869) * (1.0 - step(1.5, mp_copy_16869));
                    highp float _16886 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16875);
                    float mp_copy_16886 = _16886;
                    float _16888 = cos(mp_copy_16886);
                    float _16890 = sin(mp_copy_16886);
                    highp float _22056 = 0.0;
                    if ((_16869 > 1.5) && (_16869 < 2.5))
                    {
                        highp float _16909 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _16914 = max(_16909 * _16861, frag_info.shadow_texel_size);
                        float _22046 = 0.0;
                        highp float _22047 = 0.0;
                        _22047 = 0.0;
                        _22046 = 0.0;
                        highp float _16936 = 0.0;
                        float _16939 = 0.0;
                        for (int _22045 = 0; _22045 < 9; _22047 = _16936, _22046 = _16939, _22045++)
                        {
                            vec2 _22876 = vec2(0.0);
                            do
                            {
                                if (_22045 == 0)
                                {
                                    _22876 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_22045 == 1)
                                {
                                    _22876 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_22045 == 2)
                                {
                                    _22876 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_22045 == 3)
                                {
                                    _22876 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_22045 == 4)
                                {
                                    _22876 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_22045 == 5)
                                {
                                    _22876 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_22045 == 6)
                                {
                                    _22876 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_22045 == 7)
                                {
                                    _22876 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_22045 == 8)
                                {
                                    _22876 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_22045 == 9)
                                {
                                    _22876 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_22045 == 10)
                                {
                                    _22876 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_22045 == 11)
                                {
                                    _22876 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_22045 == 12)
                                {
                                    _22876 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_22045 == 13)
                                {
                                    _22876 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_22045 == 14)
                                {
                                    _22876 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_22045 == 15)
                                {
                                    _22876 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22876 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _17181 = clamp(_13090 + (vec2((_22876.x * _16888) - (_22876.y * _16890), (_22876.x * _16890) + (_22876.y * _16888)) * _16914), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _17190 = _17181.y;
                            highp vec2 _17191 = vec2((3.0 + _17181.x) * _16867, _17190);
                            _17191.y = 1.0 - _17190;
                            highp vec4 _17198 = texture(shadow_map, _17191);
                            highp float _17199 = _17198.x;
                            highp float _16931 = step(_17199, _16861);
                            float mp_copy_16931 = _16931;
                            _16936 = _22047 + (_17199 * _16931);
                            _16939 = _22046 + mp_copy_16931;
                        }
                        highp float _22048 = 0.0;
                        if (_22046 > 0.0)
                        {
                            _22048 = _22047 / _22046;
                        }
                        else
                        {
                            _22048 = _16861;
                        }
                        _22056 = clamp(_16909 * max(_16861 - _22048, 0.0), frag_info.shadow_texel_size, _13097);
                    }
                    else
                    {
                        _22056 = _13097;
                    }
                    float _22063 = 0.0;
                    if (_16869 > 2.5)
                    {
                        highp vec2 _17227 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _17231 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _17232 = clamp(_13090 + (vec2(-0.707099974155426025390625) * _22056), _17227, _17231);
                        highp vec2 _17243 = (vec2(_17232.x, 1.0 - _17232.y) / _17227) - vec2(0.5);
                        highp vec2 _17245 = floor(_17243);
                        highp vec2 _17248 = _17243 - _17245;
                        highp vec2 _17253 = (_17245 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17263 = vec2((3.0 + _17253.x) * _16867, _17253.y);
                        highp float _17267 = frag_info.shadow_texel_size * _16867;
                        highp vec2 _17270 = vec2(_17267, frag_info.shadow_texel_size);
                        highp vec2 _17279 = vec2(_17267, 0.0);
                        highp vec2 _17287 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _17316 = _17248.x;
                        highp float _17325 = mix(mix(float(_16861 <= texture(shadow_map, _17263).x), float(_16861 <= texture(shadow_map, _17263 + _17279).x), _17316), mix(float(_16861 <= texture(shadow_map, _17263 + _17287).x), float(_16861 <= texture(shadow_map, _17263 + _17270).x), _17316), _17248.y);
                        float mp_copy_17325 = _17325;
                        highp vec2 _17359 = clamp(_13090 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _22056), _17227, _17231);
                        highp vec2 _17370 = (vec2(_17359.x, 1.0 - _17359.y) / _17227) - vec2(0.5);
                        highp vec2 _17372 = floor(_17370);
                        highp vec2 _17375 = _17370 - _17372;
                        highp vec2 _17380 = (_17372 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17390 = vec2((3.0 + _17380.x) * _16867, _17380.y);
                        highp float _17443 = _17375.x;
                        highp float _17452 = mix(mix(float(_16861 <= texture(shadow_map, _17390).x), float(_16861 <= texture(shadow_map, _17390 + _17279).x), _17443), mix(float(_16861 <= texture(shadow_map, _17390 + _17287).x), float(_16861 <= texture(shadow_map, _17390 + _17270).x), _17443), _17375.y);
                        float mp_copy_17452 = _17452;
                        highp vec2 _17486 = clamp(_13090 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _22056), _17227, _17231);
                        highp vec2 _17497 = (vec2(_17486.x, 1.0 - _17486.y) / _17227) - vec2(0.5);
                        highp vec2 _17499 = floor(_17497);
                        highp vec2 _17502 = _17497 - _17499;
                        highp vec2 _17507 = (_17499 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17517 = vec2((3.0 + _17507.x) * _16867, _17507.y);
                        highp float _17570 = _17502.x;
                        highp float _17579 = mix(mix(float(_16861 <= texture(shadow_map, _17517).x), float(_16861 <= texture(shadow_map, _17517 + _17279).x), _17570), mix(float(_16861 <= texture(shadow_map, _17517 + _17287).x), float(_16861 <= texture(shadow_map, _17517 + _17270).x), _17570), _17502.y);
                        float mp_copy_17579 = _17579;
                        highp vec2 _17613 = clamp(_13090 + (vec2(0.707099974155426025390625) * _22056), _17227, _17231);
                        highp vec2 _17624 = (vec2(_17613.x, 1.0 - _17613.y) / _17227) - vec2(0.5);
                        highp vec2 _17626 = floor(_17624);
                        highp vec2 _17629 = _17624 - _17626;
                        highp vec2 _17634 = (_17626 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _17644 = vec2((3.0 + _17634.x) * _16867, _17634.y);
                        highp float _17697 = _17629.x;
                        highp float _17706 = mix(mix(float(_16861 <= texture(shadow_map, _17644).x), float(_16861 <= texture(shadow_map, _17644 + _17279).x), _17697), mix(float(_16861 <= texture(shadow_map, _17644 + _17287).x), float(_16861 <= texture(shadow_map, _17644 + _17270).x), _17697), _17629.y);
                        float mp_copy_17706 = _17706;
                        _22063 = (((mp_copy_17325 + mp_copy_17452) + mp_copy_17579) + mp_copy_17706) * 0.25;
                    }
                    else
                    {
                        int _17002 = (_16875 > 0.5) ? 17 : 16;
                        float _22059 = 0.0;
                        _22059 = 0.0;
                        float _17030 = 0.0;
                        for (int _22049 = 0; _22049 < 17; _22059 = _17030, _22049++)
                        {
                            if (_22049 >= _17002)
                            {
                                break;
                            }
                            vec2 _22050 = vec2(0.0);
                            do
                            {
                                if (_22049 == 0)
                                {
                                    _22050 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_22049 == 1)
                                {
                                    _22050 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_22049 == 2)
                                {
                                    _22050 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_22049 == 3)
                                {
                                    _22050 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_22049 == 4)
                                {
                                    _22050 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_22049 == 5)
                                {
                                    _22050 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_22049 == 6)
                                {
                                    _22050 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_22049 == 7)
                                {
                                    _22050 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_22049 == 8)
                                {
                                    _22050 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_22049 == 9)
                                {
                                    _22050 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_22049 == 10)
                                {
                                    _22050 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_22049 == 11)
                                {
                                    _22050 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_22049 == 12)
                                {
                                    _22050 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_22049 == 13)
                                {
                                    _22050 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_22049 == 14)
                                {
                                    _22050 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_22049 == 15)
                                {
                                    _22050 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _22050 = vec2(0.0);
                                break;
                            } while(false);
                            vec2 _22052 = vec2(0.0);
                            do
                            {
                                if (_22049 < 3)
                                {
                                    _22052 = vec2(float(_22049) - 1.0, -1.0);
                                    break;
                                }
                                if (_22049 < 6)
                                {
                                    _22052 = vec2((float(_22049 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_22049 < 11)
                                {
                                    _22052 = vec2((float(_22049 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_22049 < 14)
                                {
                                    _22052 = vec2((float(_22049 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _22052 = vec2(float(_22049 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            vec2 _17019 = mix(_22050, _22052, vec2(_16875));
                            float _17846 = _17019.x;
                            float _17850 = _17019.y;
                            highp vec2 _17876 = clamp(_13090 + (vec2((_17846 * _16888) - (_17850 * _16890), (_17846 * _16890) + (_17850 * _16888)) * _22056), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp vec2 _17886 = vec2((3.0 + _17876.x) * _16867, _17876.y);
                            _17886.y = 1.0 - _17876.y;
                            highp float _17898 = float(_16861 <= texture(shadow_map, _17886).x);
                            float mp_copy_17898 = _17898;
                            _17030 = _22059 + mp_copy_17898;
                        }
                        _22063 = _22059 / float(_17002);
                    }
                    bool _17043 = 3 == (_12738 - 1);
                    bool _17049 = false;
                    if (_17043)
                    {
                        _17049 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _17049 = _17043;
                    }
                    float _22064 = 0.0;
                    if (_17049)
                    {
                        highp vec2 _17056 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                        highp vec2 _17064 = smoothstep(vec2(0.0), _17056, _13090) * smoothstep(vec2(0.0), _17056, _16747);
                        _22064 = mix(1.0, _22063, _17064.x * _17064.y);
                    }
                    else
                    {
                        _22064 = _22063;
                    }
                    _22099 = _22035 + _13150;
                    _22096 = _22075 + (_13150 * _22064);
                }
                else
                {
                    _22099 = _22035;
                    _22096 = _22075;
                }
                _22098 = _22099;
                _22095 = _22096;
            }
            else
            {
                _22098 = _22035;
                _22095 = _22075;
            }
            _22097 = _22098;
            _22094 = _22095;
        }
        else
        {
            _22097 = _22035;
            _22094 = _22075;
        }
        _22100 = _22094 + (1.0 - _22097);
    }
    else
    {
        _22100 = 1.0;
    }
    bool _7366 = frag_info.ssao_lighting.w > 0.5;
    bool _7372 = false;
    if (_7366)
    {
        _7372 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _7372 = _7366;
    }
    float _22251 = 0.0;
    if (_7372)
    {
        _22251 = min(_22100, _22117.y);
    }
    else
    {
        _22251 = _22100;
    }
    float _7381 = _7344 * _22251;
    highp vec3 _7394 = ((((_7278 + (_7282 * ((vec3(1.0) - _7254) - _7278))) * _21671) * _22268) + (((_7254 * (_21479 * frag_info.environment_intensity)) * 1.0) * _22409)) * mix(1.0, _7381, frag_info.radiance_blend.y);
    highp vec3 _22666 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _22666 = _7394 + ((_22117.xyz * _7282) * _6213);
    }
    else
    {
        _22666 = _7394;
    }
    highp vec3 _22672 = vec3(0.0);
    if (_7331)
    {
        highp vec3 _22569 = vec3(0.0);
        highp vec3 _22570 = vec3(0.0);
        do
        {
            float _17964 = max(dot(_21417, _22493), 0.0);
            highp float hp_copy_17964 = _17964;
            if (_17964 <= 0.0)
            {
                _22570 = vec3(0.0);
                _22569 = vec3(0.0);
                break;
            }
            float _17970 = max(_7151, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_17970 = _17970;
            vec3 _17973 = _22493 + mp_copy_21461;
            float _17976 = dot(_17973, _17973);
            vec3 _22567 = vec3(0.0);
            vec3 _22568 = vec3(0.0);
            if (_17976 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _17984 = _17973 * inversesqrt(_17976);
                float _22566 = 0.0;
                do
                {
                    float _18041 = dot(_21417, _17984);
                    if (_18041 <= 0.0)
                    {
                        _22566 = 0.0;
                        break;
                    }
                    float _18048 = _21453 * _21453;
                    vec3 _18051 = cross(_21417, _17984);
                    float _18054 = _18041 * _18048;
                    float _18063 = _18048 / (dot(_18051, _18051) + (_18054 * _18054));
                    _22566 = min((_18063 * _18063) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _18101 = _7147 + (_7264 * pow(clamp(1.0 - max(dot(_17984, _21461), 0.0), 0.0, 1.0), 5.0));
                _22568 = (_18101 * min(_22566 * (0.5 / max(mix((2.0 * hp_copy_17964) * _17970, hp_copy_17964 + hp_copy_17970, hp_copy_21453 * hp_copy_21453), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _22567 = _18101;
            }
            else
            {
                _22568 = vec3(0.0);
                _22567 = _7147;
            }
            _22570 = (_22568 * frag_info.directional_light_color.xyz) * _17964;
            _22569 = (((((vec3(1.0) - _22567) * _7281) * _7052) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _17964;
            break;
        } while(false);
        _22672 = (_22569 + _22570) * _7381;
    }
    else
    {
        _22672 = vec3(0.0);
    }
    highp float _18125 = 0.0;
    highp vec2 _22571 = vec2(0.0);
    do
    {
        _18125 = frag_info.punctual_dims.x;
        if (_18125 < 0.5)
        {
            _22571 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _18137 = v_position - frag_info.camera_position.xyz;
            highp float _18152 = dot(_18137, frag_info.camera_forward.xyz);
            highp float _18158 = max(_18152, 9.9999997473787516355514526367188e-05);
            highp vec2 _18261 = (vec3(dot(_18137, frag_info.camera_right.xyz), dot(_18137, frag_info.camera_up.xyz), _18158).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_18158, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _18276 = float(int(((((clamp(floor((log2(max(_18152 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_18261.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_18261.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _22571 = vec2(texture(punctual_index, vec2((mod(_18276, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_18276 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z)).xy);
            break;
        }
        _22571 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _7437 = int(_22571.x + 0.5);
    mediump int _7441 = int(_22571.y + 0.5);
    highp vec3 _22670 = vec3(0.0);
    _22670 = _22672;
    highp vec3 _22992 = vec3(0.0);
    for (int _22572 = 0; _22572 < _7441; _22670 = _22992, _22572++)
    {
        highp float _18309 = float(_7437 + _22572);
        highp vec4 _18327 = texture(punctual_index, vec2((mod(_18309, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_18309 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z));
        highp float _18340 = (float(int(_18327.x + 0.5)) + 0.5) / _18125;
        highp vec2 _18341 = vec2(0.0625, _18340);
        highp vec4 _18344 = texture(punctual_lights, _18341);
        highp vec4 _18361 = texture(punctual_lights, vec2(0.1875, _18340));
        highp float _7459 = _18344.w;
        highp vec3 _7461 = _18361.xyz;
        if (_7459 > 2.5)
        {
            highp vec4 _18378 = texture(punctual_lights, vec2(0.3125, _18340));
            highp vec4 _18395 = texture(punctual_lights, vec2(0.4375, _18340));
            highp vec3 _7475 = _18378.xyz * (_18378.w * 0.5);
            highp vec3 _7481 = _18395.xyz * (_18395.w * 0.5);
            highp vec3 _7483 = _18344.xyz;
            highp vec3 _7485 = _7483 - _7475;
            highp vec3 _7487 = _7485 - _7481;
            highp vec3 _7491 = _7483 + _7475;
            highp vec3 _7493 = _7491 - _7481;
            highp vec3 _7505 = _7485 + _7481;
            highp vec3 _7509 = _7483 - v_position;
            highp float _7515 = _18361.w;
            highp float _7519 = (dot(_7509, _7509) * _7515) * _7515;
            highp float _7524 = clamp(1.0 - (_7519 * _7519), 0.0, 1.0);
            float mp_copy_7524 = _7524;
            vec2 _18402 = (clamp(vec2(_21453, sqrt(1.0 - _7151)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            float _18404 = _18402.x;
            float _18409 = _18402.y;
            vec4 _7548 = texture(brdf_lut, vec2((_18404 + 1.0) * 0.3333333432674407958984375, _18409));
            vec4 _7552 = texture(brdf_lut, vec2((_18404 + 2.0) * 0.3333333432674407958984375, _18409));
            vec3 _18452 = normalize(mp_copy_21461 - (_21417 * _7150));
            mat3 _18474 = transpose(mat3(_18452, -cross(_21417, _18452), _21417));
            mat3 _18475 = mat3(vec3(_7548.x, 0.0, _7548.y), vec3(0.0, 1.0, 0.0), vec3(_7548.z, 0.0, _7548.w)) * _18474;
            highp vec3 _18479 = _7487 - v_position;
            highp vec3 _18481 = normalize(_18475 * _18479);
            vec3 mp_copy_18481 = _18481;
            highp vec3 _18485 = _7493 - v_position;
            highp vec3 _18487 = normalize(_18475 * _18485);
            vec3 mp_copy_18487 = _18487;
            highp vec3 _18491 = (_7491 + _7481) - v_position;
            highp vec3 _18493 = normalize(_18475 * _18491);
            vec3 mp_copy_18493 = _18493;
            highp vec3 _18497 = _7505 - v_position;
            highp vec3 _18499 = normalize(_18475 * _18497);
            vec3 mp_copy_18499 = _18499;
            float _18528 = dot(_18481, _18487);
            float _18530 = abs(_18528);
            float _18544 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18530)) * _18530)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18530) * _18530));
            float _22816 = 0.0;
            if (_18528 > 0.0)
            {
                _22816 = _18544;
            }
            else
            {
                _22816 = (0.5 * inversesqrt(max(1.0 - (_18528 * _18528), 1.0000000116860974230803549289703e-07))) - _18544;
            }
            float _18577 = dot(_18487, _18493);
            float _18579 = abs(_18577);
            float _18593 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18579)) * _18579)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18579) * _18579));
            float _22817 = 0.0;
            if (_18577 > 0.0)
            {
                _22817 = _18593;
            }
            else
            {
                _22817 = (0.5 * inversesqrt(max(1.0 - (_18577 * _18577), 1.0000000116860974230803549289703e-07))) - _18593;
            }
            float _18626 = dot(_18493, _18499);
            float _18628 = abs(_18626);
            float _18642 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18628)) * _18628)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18628) * _18628));
            float _22818 = 0.0;
            if (_18626 > 0.0)
            {
                _22818 = _18642;
            }
            else
            {
                _22818 = (0.5 * inversesqrt(max(1.0 - (_18626 * _18626), 1.0000000116860974230803549289703e-07))) - _18642;
            }
            float _18675 = dot(_18499, _18481);
            float _18677 = abs(_18675);
            float _18691 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18677)) * _18677)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18677) * _18677));
            float _22819 = 0.0;
            if (_18675 > 0.0)
            {
                _22819 = _18691;
            }
            else
            {
                _22819 = (0.5 * inversesqrt(max(1.0 - (_18675 * _18675), 1.0000000116860974230803549289703e-07))) - _18691;
            }
            vec3 _18514 = (((cross(mp_copy_18481, mp_copy_18487) * _22816) + (cross(mp_copy_18487, mp_copy_18493) * _22817)) + (cross(mp_copy_18493, mp_copy_18499) * _22818)) + (cross(mp_copy_18499, mp_copy_18481) * _22819);
            float _18717 = length(_18514);
            mat3 _18777 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _18474;
            highp vec3 _18783 = normalize(_18777 * _18479);
            vec3 mp_copy_18783 = _18783;
            highp vec3 _18789 = normalize(_18777 * _18485);
            vec3 mp_copy_18789 = _18789;
            highp vec3 _18795 = normalize(_18777 * _18491);
            vec3 mp_copy_18795 = _18795;
            highp vec3 _18801 = normalize(_18777 * _18497);
            vec3 mp_copy_18801 = _18801;
            float _18830 = dot(_18783, _18789);
            float _18832 = abs(_18830);
            float _18846 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18832)) * _18832)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18832) * _18832));
            float _22820 = 0.0;
            if (_18830 > 0.0)
            {
                _22820 = _18846;
            }
            else
            {
                _22820 = (0.5 * inversesqrt(max(1.0 - (_18830 * _18830), 1.0000000116860974230803549289703e-07))) - _18846;
            }
            float _18879 = dot(_18789, _18795);
            float _18881 = abs(_18879);
            float _18895 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18881)) * _18881)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18881) * _18881));
            float _22821 = 0.0;
            if (_18879 > 0.0)
            {
                _22821 = _18895;
            }
            else
            {
                _22821 = (0.5 * inversesqrt(max(1.0 - (_18879 * _18879), 1.0000000116860974230803549289703e-07))) - _18895;
            }
            float _18928 = dot(_18795, _18801);
            float _18930 = abs(_18928);
            float _18944 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18930)) * _18930)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18930) * _18930));
            float _22822 = 0.0;
            if (_18928 > 0.0)
            {
                _22822 = _18944;
            }
            else
            {
                _22822 = (0.5 * inversesqrt(max(1.0 - (_18928 * _18928), 1.0000000116860974230803549289703e-07))) - _18944;
            }
            float _18977 = dot(_18801, _18783);
            float _18979 = abs(_18977);
            float _18993 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _18979)) * _18979)) / (3.41759395599365234375 + ((4.1616725921630859375 + _18979) * _18979));
            float _22823 = 0.0;
            if (_18977 > 0.0)
            {
                _22823 = _18993;
            }
            else
            {
                _22823 = (0.5 * inversesqrt(max(1.0 - (_18977 * _18977), 1.0000000116860974230803549289703e-07))) - _18993;
            }
            vec3 _18816 = (((cross(mp_copy_18783, mp_copy_18789) * _22820) + (cross(mp_copy_18789, mp_copy_18795) * _22821)) + (cross(mp_copy_18795, mp_copy_18801) * _22822)) + (cross(mp_copy_18801, mp_copy_18783) * _22823);
            float _19019 = length(_18816);
            _22992 = _22670 + (((_7461 * (mp_copy_7524 * mp_copy_7524)) * step(0.0, dot(cross(_7493 - _7487, _7505 - _7487), v_position - _7487))) * (((((_7147 * _7552.x) + (_7264 * _7552.y)) * max(((_18717 * _18717) + _18514.z) / (_18717 + 1.0), 0.0)) * 1.0) + (_7282 * max(((_19019 * _19019) + _18816.z) / (_19019 + 1.0), 0.0))));
        }
        else
        {
            highp float hp_copy_22760 = 0.0;
            vec3 _22733 = vec3(0.0);
            highp vec3 _22756 = vec3(0.0);
            float _22760 = 0.0;
            if (_7459 < 0.5)
            {
                _22760 = _21453;
                _22756 = _7461;
                _22733 = -normalize(texture(punctual_lights, vec2(0.3125, _18340)).xyz);
            }
            else
            {
                highp vec3 _7639 = _18344.xyz - v_position;
                highp float _7642 = dot(_7639, _7639);
                highp float _7646 = inversesqrt(max(_7642, 9.9999999392252902907785028219223e-09));
                highp vec3 _7647 = _7639 * _7646;
                vec3 mp_copy_7647 = _7647;
                highp float _7649 = _18361.w;
                highp float _7654 = (_7642 * _7649) * _7649;
                highp float _7659 = clamp(1.0 - (_7654 * _7654), 0.0, 1.0);
                float mp_copy_7659 = _7659;
                highp vec4 _19063 = texture(punctual_lights, vec2(0.4375, _18340));
                highp float _7663 = _19063.w;
                float _22764 = 0.0;
                if (_7663 > 0.0)
                {
                    highp float _7690 = (_21453 * _21453) + ((_7663 * 0.5) * _7646);
                    float mp_copy_7690 = _7690;
                    _22764 = sqrt(min(mp_copy_7690, 1.0));
                }
                else
                {
                    _22764 = _21453;
                }
                highp vec3 _7697 = _7461 * ((mp_copy_7659 * mp_copy_7659) / max(pow(max(_7642, _7663 * _7663), _19063.z * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _22757 = vec3(0.0);
                if (_7459 > 1.5)
                {
                    highp vec4 _19080 = texture(punctual_lights, vec2(0.3125, _18340));
                    highp float _7716 = clamp((dot(normalize(_19080.xyz), -mp_copy_7647) * _19080.w) + _19063.x, 0.0, 1.0);
                    float mp_copy_7716 = _7716;
                    highp vec3 _7721 = _7697 * (mp_copy_7716 * mp_copy_7716);
                    highp float _7723 = _19063.y;
                    bool _7724 = _7723 > (-0.5);
                    bool _7730 = false;
                    if (_7724)
                    {
                        _7730 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7730 = _7724;
                    }
                    highp vec3 _22758 = vec3(0.0);
                    if (_7730)
                    {
                        float _22724 = 0.0;
                        do
                        {
                            highp vec4 _19303 = texture(punctual_lights, vec2(0.5625, _18340));
                            highp vec4 _19320 = texture(punctual_lights, vec2(0.6875, _18340));
                            highp vec4 _19337 = texture(punctual_lights, vec2(0.8125, _18340));
                            highp vec4 _19354 = texture(punctual_lights, vec2(0.9375, _18340));
                            highp vec4 _19165 = mat4(_19303, _19320, _19337, _19354) * vec4(v_position + (_6051 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _19167 = _19165.w;
                            if (_19167 <= 0.0)
                            {
                                _22724 = 1.0;
                                break;
                            }
                            highp vec3 _19176 = _19165.xyz / vec3(_19167);
                            highp vec2 _19181 = (_19176.xy * 0.5) + vec2(0.5);
                            highp float _19183 = _19181.x;
                            bool _19184 = _19183 < 0.0;
                            bool _19191 = false;
                            if (!_19184)
                            {
                                _19191 = _19183 > 1.0;
                            }
                            else
                            {
                                _19191 = _19184;
                            }
                            bool _19198 = false;
                            if (!_19191)
                            {
                                _19198 = _19181.y < 0.0;
                            }
                            else
                            {
                                _19198 = _19191;
                            }
                            bool _19205 = false;
                            if (!_19198)
                            {
                                _19205 = _19181.y > 1.0;
                            }
                            else
                            {
                                _19205 = _19198;
                            }
                            bool _19212 = false;
                            if (!_19205)
                            {
                                _19212 = _19176.z < 0.0;
                            }
                            else
                            {
                                _19212 = _19205;
                            }
                            bool _19219 = false;
                            if (!_19212)
                            {
                                _19219 = _19176.z > 1.0;
                            }
                            else
                            {
                                _19219 = _19212;
                            }
                            if (_19219)
                            {
                                _22724 = 1.0;
                                break;
                            }
                            highp float _19226 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _19231 = frag_info.shadow_cascade_count + float(int(_7723 + 0.5));
                            highp float _19236 = _19176.z - frag_info.spot_shadow_params.y;
                            highp float _19239 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                            highp float _19252 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _22723 = 0.0;
                            _22723 = float(_19236 <= texture(shadow_map, vec2((_19231 + clamp(_19183, 0.0, 1.0)) / _19226, 1.0 - clamp(_19181.y, 0.0, 1.0))).x);
                            for (int _22722 = 0; _22722 < 8; )
                            {
                                highp float _19262 = _19252 + (float(_22722) * 0.785398185253143310546875);
                                float mp_copy_19262 = _19262;
                                highp vec2 _19272 = _19181 + (vec2(cos(mp_copy_19262), sin(mp_copy_19262)) * _19239);
                                highp float _19398 = float(_19236 <= texture(shadow_map, vec2((_19231 + clamp(_19272.x, 0.0, 1.0)) / _19226, 1.0 - clamp(_19272.y, 0.0, 1.0))).x);
                                float mp_copy_19398 = _19398;
                                _22723 += mp_copy_19398;
                                _22722++;
                                continue;
                            }
                            _22724 = _22723 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _22758 = _7721 * _22724;
                    }
                    else
                    {
                        _22758 = _7721;
                    }
                    _22757 = _22758;
                }
                else
                {
                    bool _7746 = _7459 > 0.5;
                    bool _7752 = false;
                    if (_7746)
                    {
                        _7752 = _19063.y > (-0.5);
                    }
                    else
                    {
                        _7752 = _7746;
                    }
                    bool _7758 = false;
                    if (_7752)
                    {
                        _7758 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7758 = _7752;
                    }
                    highp vec3 _22759 = vec3(0.0);
                    if (_7758)
                    {
                        float _22709 = 0.0;
                        do
                        {
                            highp vec4 _19711 = texture(punctual_lights, vec2(0.5625, _18340));
                            highp vec4 _19728 = texture(punctual_lights, vec2(0.6875, _18340));
                            highp vec4 _19745 = texture(punctual_lights, _18341);
                            highp vec3 _19470 = (v_position + (_6051 * _19711.z)) - _19745.xyz;
                            highp vec3 _19472 = abs(_19470);
                            highp float _19474 = _19472.x;
                            highp float _19476 = _19472.y;
                            bool _19477 = _19474 >= _19476;
                            bool _19485 = false;
                            if (_19477)
                            {
                                _19485 = _19474 >= _19472.z;
                            }
                            else
                            {
                                _19485 = _19477;
                            }
                            highp vec3 _22699 = vec3(0.0);
                            float _22701 = 0.0;
                            if (_19485)
                            {
                                highp float _19488 = _19470.x;
                                bool _19489 = _19488 >= 0.0;
                                highp vec3 _22698 = vec3(0.0);
                                if (_19489)
                                {
                                    _22698 = vec3(-_19470.z, _19470.y, _19488);
                                }
                                else
                                {
                                    _22698 = vec3(_19470.zy, -_19488);
                                }
                                _22701 = _19489 ? 0.0 : 1.0;
                                _22699 = _22698;
                            }
                            else
                            {
                                highp vec3 _22700 = vec3(0.0);
                                float _22703 = 0.0;
                                if (_19476 >= _19472.z)
                                {
                                    highp float _19522 = _19470.y;
                                    bool _19523 = _19522 >= 0.0;
                                    highp vec3 _22697 = vec3(0.0);
                                    if (_19523)
                                    {
                                        _22697 = vec3(-_19470.x, _19470.z, _19522);
                                    }
                                    else
                                    {
                                        _22697 = vec3(_19470.xz, -_19522);
                                    }
                                    _22703 = _19523 ? 2.0 : 3.0;
                                    _22700 = _22697;
                                }
                                else
                                {
                                    highp float _19550 = _19470.z;
                                    bool _19551 = _19550 >= 0.0;
                                    highp vec3 _22696 = vec3(0.0);
                                    if (_19551)
                                    {
                                        _22696 = _19470;
                                    }
                                    else
                                    {
                                        _22696 = vec3(-_19470.x, _19470.y, -_19550);
                                    }
                                    _22703 = _19551 ? 4.0 : 5.0;
                                    _22700 = _22696;
                                }
                                _22701 = _22703;
                                _22699 = _22700;
                            }
                            if (_22699.z <= 0.0)
                            {
                                _22709 = 1.0;
                                break;
                            }
                            highp vec2 _19591 = ((_22699.xy / vec2(_22699.z)) * 0.5) + vec2(0.5);
                            highp float _19602 = (_19711.x - (_19711.y / _22699.z)) - _19728.x;
                            if ((_19602 < 0.0) || (_19602 > 1.0))
                            {
                                _22709 = 1.0;
                                break;
                            }
                            highp float hp_copy_22706 = 0.0;
                            highp float _19614 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            bool _19620 = _22701 >= 4.0;
                            highp float _19622 = (frag_info.shadow_cascade_count + _19063.y) + float(_19620);
                            float _22706 = 0.0;
                            if (_19620)
                            {
                                _22706 = _22701 - 4.0;
                            }
                            else
                            {
                                _22706 = _22701;
                            }
                            hp_copy_22706 = _22706;
                            highp float _19639 = _19728.y * 0.5;
                            highp float _19642 = _19711.w * 0.0040000001899898052215576171875;
                            highp vec2 _19753 = vec2(_19639);
                            highp vec2 _19756 = vec2(1.0 - _19639);
                            highp vec2 _19762 = vec2(mod(hp_copy_22706, 2.0), 1.0 - floor(hp_copy_22706 * 0.5)) * 0.5;
                            highp vec2 _19765 = _19762 + (clamp(_19591, _19753, _19756) * 0.5);
                            highp float _19658 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            float _22708 = 0.0;
                            _22708 = float(_19602 <= texture(shadow_map, vec2((_19622 + _19765.x) / _19614, 1.0 - _19765.y)).x);
                            for (int _22707 = 0; _22707 < 8; )
                            {
                                highp float _19668 = _19658 + (float(_22707) * 0.785398185253143310546875);
                                float mp_copy_19668 = _19668;
                                highp vec2 _19802 = _19762 + (clamp(_19591 + (vec2(cos(mp_copy_19668), sin(mp_copy_19668)) * _19642), _19753, _19756) * 0.5);
                                highp float _19819 = float(_19602 <= texture(shadow_map, vec2((_19622 + _19802.x) / _19614, 1.0 - _19802.y)).x);
                                float mp_copy_19819 = _19819;
                                _22708 += mp_copy_19819;
                                _22707++;
                                continue;
                            }
                            _22709 = _22708 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _22759 = _7697 * _22709;
                    }
                    else
                    {
                        _22759 = _7697;
                    }
                    _22757 = _22759;
                }
                _22760 = _22764;
                _22756 = _22757;
                _22733 = _7647;
            }
            hp_copy_22760 = _22760;
            highp vec3 _22787 = vec3(0.0);
            highp vec3 _22788 = vec3(0.0);
            do
            {
                float _19885 = max(dot(_21417, _22733), 0.0);
                highp float hp_copy_19885 = _19885;
                if (_19885 <= 0.0)
                {
                    _22788 = vec3(0.0);
                    _22787 = vec3(0.0);
                    break;
                }
                float _19891 = max(_7151, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_19891 = _19891;
                vec3 _19894 = _22733 + mp_copy_21461;
                float _19897 = dot(_19894, _19894);
                vec3 _22785 = vec3(0.0);
                vec3 _22786 = vec3(0.0);
                if (_19897 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _19905 = _19894 * inversesqrt(_19897);
                    float _22784 = 0.0;
                    do
                    {
                        float _19962 = dot(_21417, _19905);
                        if (_19962 <= 0.0)
                        {
                            _22784 = 0.0;
                            break;
                        }
                        float _19969 = _22760 * _22760;
                        vec3 _19972 = cross(_21417, _19905);
                        float _19975 = _19962 * _19969;
                        float _19984 = _19969 / (dot(_19972, _19972) + (_19975 * _19975));
                        _22784 = min((_19984 * _19984) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _20022 = _7147 + (_7264 * pow(clamp(1.0 - max(dot(_19905, _21461), 0.0), 0.0, 1.0), 5.0));
                    _22786 = (_20022 * min(_22784 * (0.5 / max(mix((2.0 * hp_copy_19885) * _19891, hp_copy_19885 + hp_copy_19891, hp_copy_22760 * hp_copy_22760), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _22785 = _20022;
                }
                else
                {
                    _22786 = vec3(0.0);
                    _22785 = _7147;
                }
                _22788 = (_22786 * _22756) * _19885;
                _22787 = (((((vec3(1.0) - _22785) * _7281) * _7052) * 0.3183098733425140380859375) * _22756) * _19885;
                break;
            } while(false);
            _22992 = _22670 + (_22787 + _22788);
        }
    }
    bool _7815 = _FogInfo.params0.y > 0.5;
    bool _7821 = false;
    if (_7815)
    {
        _7821 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7821 = _7815;
    }
    highp vec3 _22677 = vec3(0.0);
    if (_7821)
    {
        vec3 mp_copy_22673 = vec3(0.0);
        highp vec3 _22673 = vec3(0.0);
        if (_7988)
        {
            _22673 = -view_info.camera_forward.xyz;
        }
        else
        {
            _22673 = normalize(v_viewvector);
        }
        mp_copy_22673 = _22673;
        vec3 _7826 = _7172 * (-mp_copy_22673);
        vec3 _22674 = vec3(0.0);
        do
        {
            if (_8302)
            {
                vec2 _20144 = vec2(atan(_7826.z, _7826.x), asin(clamp(_7826.y, -1.0, 1.0)));
                highp vec2 hp_copy_20144 = _20144;
                _22674 = textureLod(prefiltered_radiance, (hp_copy_20144 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _20163 = vec2(atan(_7826.z, _7826.x), asin(clamp(_7826.y, -1.0, 1.0)));
            highp vec2 hp_copy_20163 = _20163;
            highp vec2 _20168 = (hp_copy_20163 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _20075 = clamp(_20168.y, 0.00390625, 0.99609375);
            float _20081 = floor(0.0);
            highp float _20100 = _20168.x;
            _22674 = mix(texture(prefiltered_radiance, vec2(_20100, (_20081 + _20075) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_20100, (min(_20081 + 1.0, 7.0) + _20075) * 0.125)).xyz, vec3(-_20081));
            break;
        } while(false);
        highp vec3 _22676 = vec3(0.0);
        if (_7195)
        {
            vec3 _22675 = vec3(0.0);
            do
            {
                if (_8302)
                {
                    vec2 _20273 = vec2(atan(_7826.z, _7826.x), asin(clamp(_7826.y, -1.0, 1.0)));
                    highp vec2 hp_copy_20273 = _20273;
                    _22675 = textureLod(prefiltered_radiance_b, (hp_copy_20273 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _20292 = vec2(atan(_7826.z, _7826.x), asin(clamp(_7826.y, -1.0, 1.0)));
                highp vec2 hp_copy_20292 = _20292;
                highp vec2 _20297 = (hp_copy_20292 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _20204 = clamp(_20297.y, 0.00390625, 0.99609375);
                float _20210 = floor(0.0);
                highp float _20229 = _20297.x;
                _22675 = mix(texture(prefiltered_radiance_b, vec2(_20229, (_20210 + _20204) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_20229, (min(_20210 + 1.0, 7.0) + _20204) * 0.125)).xyz, vec3(-_20210));
                break;
            } while(false);
            _22676 = mix(_22674, _22675, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _22676 = _22674;
        }
        _22677 = _22676 * frag_info.environment_intensity;
    }
    else
    {
        _22677 = _FogInfo.color.xyz;
    }
    highp vec4 _7850 = vec4(min((_22666 + (_22670 * mix(1.0, _21741, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + ((mix(_6229 * vec3(0.077399380505084991455078125), pow((_6229 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _6229)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w), vec3(65504.0)), 1.0) * _23057;
    highp vec4 _22692 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _22692 = _7850;
            break;
        }
        int _20341 = int(_FogInfo.params0.x + 0.5);
        if (_20341 == 0)
        {
            _22692 = _7850;
            break;
        }
        highp float _22679 = 0.0;
        if (_7988)
        {
            _22679 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _22679 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_22679 > _FogInfo.params1.w))
        {
            _22692 = _7850;
            break;
        }
        float _22683 = 0.0;
        if (_20341 == 1)
        {
            _22683 = clamp((_22679 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _22684 = 0.0;
            if (_20341 == 2)
            {
                highp float _22682 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _22680 = vec3(0.0);
                    if (_7988)
                    {
                        _22680 = v_position - (view_info.camera_forward.xyz * _22679);
                    }
                    else
                    {
                        _22680 = v_position + v_viewvector;
                    }
                    highp float _20422 = -_FogInfo.params2.y;
                    highp float _20429 = _FogInfo.params1.x * exp(_20422 * (_22680.y - _FogInfo.params2.x));
                    highp float _20446 = _FogInfo.params2.y * (v_position.y - _22680.y);
                    highp float _22681 = 0.0;
                    if (abs(_20446) > 0.00124999997206032276153564453125)
                    {
                        _22681 = (_20429 - (_FogInfo.params1.x * exp(_20422 * (v_position.y - _FogInfo.params2.x)))) / _20446;
                    }
                    else
                    {
                        _22681 = _20429;
                    }
                    _22682 = _22681 * max(_22679 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _22682 = _FogInfo.params1.x * max(_22679 - _FogInfo.params1.y, 0.0);
                }
                _22684 = 1.0 - exp(-_22682);
            }
            else
            {
                highp float _20484 = _FogInfo.params1.x * max(_22679 - _FogInfo.params1.y, 0.0);
                _22684 = 1.0 - exp((-_20484) * _20484);
            }
            _22683 = _22684;
        }
        highp float _20496 = min(_22683, _FogInfo.params0.z);
        if (_20496 <= 0.0)
        {
            _22692 = _7850;
            break;
        }
        highp vec3 _20509 = mix(_FogInfo.color.xyz, _22677, vec3(_FogInfo.params0.w));
        bool _20512 = _FogInfo.sun.w > 0.5;
        bool _20518 = false;
        if (_20512)
        {
            _20518 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _20518 = _20512;
        }
        vec3 _22688 = vec3(0.0);
        if (_20518)
        {
            vec3 mp_copy_22685 = vec3(0.0);
            highp vec3 _22685 = vec3(0.0);
            if (_7988)
            {
                _22685 = -view_info.camera_forward.xyz;
            }
            else
            {
                _22685 = normalize(v_viewvector);
            }
            mp_copy_22685 = _22685;
            highp float _20534 = pow(max(dot(-mp_copy_22685, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_20534 = _20534;
            _22688 = _20509 + ((_FogInfo.sun.xyz * mp_copy_20534) * _FogInfo.params2.z);
        }
        else
        {
            _22688 = _20509;
        }
        highp float _20547 = _7850.w;
        float mp_copy_20547 = _20547;
        _22692 = vec4(mix(_7850.xyz, _22688 * mp_copy_20547, vec3(_20496)), _20547);
        break;
    } while(false);
    frag_color = _22692;
    float _22694 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _22694 = 1.0;
    }
    else
    {
        _22694 = abs(frag_info.fade);
    }
    frag_color *= _22694;
}

