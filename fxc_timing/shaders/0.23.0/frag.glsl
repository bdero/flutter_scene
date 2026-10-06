#version 300 es
precision mediump float;
precision highp int;

layout(std140) uniform RadianceLayoutInfo
{
    highp float mip_layout;
} radiance_layout_info;

layout(std140) uniform FogInfo
{
    highp vec4 params0;
    highp vec4 params1;
    highp vec4 params2;
    highp vec4 color;
    highp vec4 sun;
    highp vec4 sun_dir;
} _FogInfo;

layout(std140) uniform FragInfo
{
    highp vec4 color;
    highp vec4 emissive_factor;
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
    highp float vertex_color_weight;
    highp float metallic_factor;
    highp float roughness_factor;
    highp float has_normal_map;
    highp float normal_scale;
    highp float occlusion_strength;
    highp float environment_intensity;
    highp float has_directional_light;
    highp float casts_shadow;
    highp float shadow_bias;
    highp float shadow_normal_bias;
    highp float shadow_texel_size;
    highp float alpha_mode;
    highp float alpha_cutoff;
    highp float shadow_fade;
    highp float shadow_softness;
    highp float shadow_cascade_count;
    highp float fade;
    highp float specular_aa_variance;
    highp float specular_aa_threshold;
    highp mat4 environment_transform;
    highp vec4 ssao_params;
    highp vec4 radiance_blend;
    highp vec4 ssao_lighting;
    highp vec4 model_scale;
    highp vec4 dielectric_f0;
    highp vec4 gi_grid;
    highp vec4 gi_anchor;
    highp vec4 gi_counts;
    highp vec4 gi_atlas;
    highp vec4 gi_visibility;
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
uniform mediump sampler2D shadow_map;
uniform mediump sampler2D punctual_lights;
uniform mediump sampler2D punctual_index;
uniform mediump sampler2D ssao_texture;
uniform mediump sampler2D prefiltered_radiance;
uniform mediump sampler2D prefiltered_radiance_b;
uniform mediump sampler2D brdf_lut;
uniform mediump sampler2D base_color_texture;
uniform mediump sampler2D normal_texture;
uniform mediump sampler2D metallic_roughness_texture;
uniform mediump sampler2D occlusion_texture;
uniform mediump sampler2D emissive_texture;

in highp vec3 v_normal;
in highp vec2 v_texture_coords;
in highp vec2 v_texture_coords_1;
in highp vec4 v_tangent;
in highp vec3 v_viewvector;
in highp vec3 v_position;
in highp vec4 v_color;
layout(location = 0) out highp vec4 frag_color;

void main()
{
    do
    {
        if (frag_info.fade >= 1.0)
        {
            break;
        }
        highp float _5329 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125))));
        highp float _19774 = 0.0;
        highp float _19775 = 0.0;
        if (frag_info.fade < 0.0)
        {
            _19775 = -frag_info.fade;
            _19774 = 1.0 - _5329;
        }
        else
        {
            _19775 = frag_info.fade;
            _19774 = _5329;
        }
        if (_19774 >= _19775)
        {
            discard;
        }
        break;
    } while(false);
    highp vec3 _5365 = normalize(v_normal) * (gl_FrontFacing ? 1.0 : (-1.0));
    highp vec4 _5406 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _5409 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _19777 = vec2(0.0);
    if (_5409)
    {
        highp vec2 _19776 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _19776 = v_texture_coords_1;
        }
        else
        {
            _19776 = v_texture_coords;
        }
        highp vec2 _5603 = _19776 * texture_transforms.base_color_transform.zw;
        highp float _5609 = _5603.x;
        highp float _5614 = _5603.y;
        _19777 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _5609) - (texture_transforms.base_color_rotation.y * _5614), (texture_transforms.base_color_rotation.y * _5609) + (texture_transforms.base_color_rotation.x * _5614));
    }
    else
    {
        _19777 = v_texture_coords;
    }
    vec4 _5423 = texture(base_color_texture, _19777);
    vec3 _5425 = _5423.xyz;
    highp vec3 hp_copy_5425 = _5425;
    highp float _5441 = (_5423.w * _5406.w) * frag_info.color.w;
    bool _5444 = frag_info.alpha_mode == 1.0;
    if (_5444)
    {
        if (_5441 < frag_info.alpha_cutoff)
        {
            discard;
        }
    }
    highp float _21300 = _5444 ? 1.0 : _5441;
    highp vec3 _19789 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _19780 = vec2(0.0);
        if (_5409)
        {
            highp vec2 _19779 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _19779 = v_texture_coords_1;
            }
            else
            {
                _19779 = v_texture_coords;
            }
            highp vec2 _5697 = _19779 * texture_transforms.normal_transform.zw;
            highp float _5703 = _5697.x;
            highp float _5708 = _5697.y;
            _19780 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _5703) - (texture_transforms.normal_rotation.y * _5708), (texture_transforms.normal_rotation.y * _5703) + (texture_transforms.normal_rotation.x * _5708));
        }
        else
        {
            _19780 = v_texture_coords;
        }
        vec3 _5749 = texture(normal_texture, _19780).xyz;
        highp vec3 hp_copy_5749 = _5749;
        highp vec3 _5755 = ((hp_copy_5749 * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        highp vec2 _5759 = _5755.xy * vec2(frag_info.normal_scale);
        highp vec3 _19134 = _5755;
        _19134.x = _5759.x;
        _19134.y = _5759.y;
        highp vec3 _5765 = -v_viewvector;
        highp mat3 _19788 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            highp vec3 _5794 = v_tangent.xyz - (_5365 * dot(_5365, v_tangent.xyz));
            highp float _5797 = dot(_5794, _5794);
            bool _5799 = _5797 <= 1.0000000133514319600180897396058e-10;
            bool _5807 = false;
            if (!_5799)
            {
                _5807 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _5807 = _5799;
            }
            if (_5807)
            {
                highp vec2 _5863 = dFdx(_19780);
                highp vec2 _5865 = dFdy(_19780);
                bvec2 _21302 = bvec2(length(_5863) == 0.0);
                highp vec2 _21303 = vec2(_21302.x ? vec2(1.0, 0.0).x : _5863.x, _21302.y ? vec2(1.0, 0.0).y : _5863.y);
                bvec2 _21304 = bvec2(length(_5865) == 0.0);
                highp vec2 _21305 = vec2(_21304.x ? vec2(0.0, 1.0).x : _5865.x, _21304.y ? vec2(0.0, 1.0).y : _5865.y);
                highp vec3 _5878 = cross(dFdy(_5765), _5365);
                highp vec3 _5881 = cross(_5365, dFdx(_5765));
                highp vec3 _5890 = (_5878 * _21303.x) + (_5881 * _21305.x);
                highp vec3 _5899 = (_5878 * _21303.y) + (_5881 * _21305.y);
                highp float _5908 = inversesqrt(max(max(dot(_5890, _5890), dot(_5899, _5899)), 9.9999996826552253889678874634872e-21));
                _19788 = mat3(_5890 * _5908, _5899 * _5908, _5365);
                break;
            }
            highp vec3 _5817 = _5794 * inversesqrt(_5797);
            _19788 = mat3(_5817, normalize(cross(_5365, _5817)) * sign(v_tangent.w), _5365);
            break;
        } while(false);
        _19789 = normalize(_19788 * _19134);
    }
    else
    {
        _19789 = _5365;
    }
    highp vec2 _19791 = vec2(0.0);
    if (_5409)
    {
        highp vec2 _19790 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _19790 = v_texture_coords_1;
        }
        else
        {
            _19790 = v_texture_coords;
        }
        highp vec2 _5969 = _19790 * texture_transforms.metallic_roughness_transform.zw;
        highp float _5975 = _5969.x;
        highp float _5980 = _5969.y;
        _19791 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _5975) - (texture_transforms.metallic_roughness_rotation.y * _5980), (texture_transforms.metallic_roughness_rotation.y * _5975) + (texture_transforms.metallic_roughness_rotation.x * _5980));
    }
    else
    {
        _19791 = v_texture_coords;
    }
    vec4 _5498 = texture(metallic_roughness_texture, _19791);
    highp float _5504 = clamp(_5498.z * frag_info.metallic_factor, 0.0, 1.0);
    highp float _5511 = clamp(_5498.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _19793 = vec2(0.0);
    if (_5409)
    {
        highp vec2 _19792 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _19792 = v_texture_coords_1;
        }
        else
        {
            _19792 = v_texture_coords;
        }
        highp vec2 _6039 = _19792 * texture_transforms.occlusion_transform.zw;
        highp float _6045 = _6039.x;
        highp float _6050 = _6039.y;
        _19793 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _6045) - (texture_transforms.occlusion_rotation.y * _6050), (texture_transforms.occlusion_rotation.y * _6045) + (texture_transforms.occlusion_rotation.x * _6050));
    }
    else
    {
        _19793 = v_texture_coords;
    }
    float _5527 = texture(occlusion_texture, _19793).x;
    highp float hp_copy_5527 = _5527;
    highp float _5533 = 1.0 - ((1.0 - hp_copy_5527) * frag_info.occlusion_strength);
    highp vec2 _19795 = vec2(0.0);
    if (_5409)
    {
        highp vec2 _19794 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _19794 = v_texture_coords_1;
        }
        else
        {
            _19794 = v_texture_coords;
        }
        highp vec2 _6109 = _19794 * texture_transforms.emissive_transform.zw;
        highp float _6115 = _6109.x;
        highp float _6120 = _6109.y;
        _19795 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _6115) - (texture_transforms.emissive_rotation.y * _6120), (texture_transforms.emissive_rotation.y * _6115) + (texture_transforms.emissive_rotation.x * _6120));
    }
    else
    {
        _19795 = v_texture_coords;
    }
    vec3 _5549 = texture(emissive_texture, _19795).xyz;
    highp vec3 hp_copy_5549 = _5549;
    highp vec3 _6357 = vec4((mix(hp_copy_5425 * vec3(0.077399380505084991455078125), pow((hp_copy_5425 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), hp_copy_5425)) * _5406.xyz) * frag_info.color.xyz, _21300).xyz;
    highp float _19825 = 0.0;
    do
    {
        if (frag_info.specular_aa_variance <= 0.0)
        {
            _19825 = _5511;
            break;
        }
        highp vec3 _7131 = dFdx(_19789);
        highp vec3 _7133 = dFdy(_19789);
        _19825 = sqrt(clamp((_5511 * _5511) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_7131, _7131), dot(_7133, _7133))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
        break;
    } while(false);
    highp float _19833 = 0.0;
    highp vec3 _19837 = vec3(0.0);
    highp float _20109 = 0.0;
    highp vec4 _20484 = vec4(0.0);
    highp vec3 _20634 = vec3(0.0);
    if (frag_info.ssao_params.x > 0.5)
    {
        vec4 _6384 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
        highp float _19826 = 0.0;
        if (frag_info.camera_up.w > 0.5)
        {
            _19826 = _6384.w;
        }
        else
        {
            _19826 = _6384.x;
        }
        highp float _6397 = min(_5533, _19826);
        bool _6400 = frag_info.ssao_lighting.z > 0.5;
        bool _6406 = false;
        if (_6400)
        {
            _6406 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _6406 = _6400;
        }
        highp vec3 _19838 = vec3(0.0);
        if (_6406)
        {
            vec2 _6409 = _6384.zw;
            highp vec2 hp_copy_6409 = _6409;
            highp vec2 _7166 = (hp_copy_6409 * 2.0) - vec2(1.0);
            highp float _7168 = _7166.x;
            highp float _7170 = _7166.y;
            highp float _7178 = (1.0 - abs(_7168)) - abs(_7170);
            highp vec3 _7179 = vec3(_7168, _7170, _7178);
            highp vec3 _19829 = vec3(0.0);
            if (_7178 < 0.0)
            {
                highp vec2 _7192 = (vec2(1.0) - abs(_7179.yx)) * vec2((_7168 >= 0.0) ? 1.0 : (-1.0), (_7170 >= 0.0) ? 1.0 : (-1.0));
                highp vec3 _19183 = _7179;
                _19183.x = _7192.x;
                _19183.y = _7192.y;
                _19829 = _19183;
            }
            else
            {
                _19829 = _7179;
            }
            highp vec3 _7200 = -normalize(_19829);
            _19838 = normalize(((frag_info.camera_right.xyz * _7200.x) + (frag_info.camera_up.xyz * _7200.y)) + (frag_info.camera_forward.xyz * _7200.z));
        }
        else
        {
            _19838 = vec3(0.0);
        }
        highp vec3 _6434 = vec3(_6397);
        _20634 = mix(_6434, max(_6434, ((((((_6357 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _6397) + ((_6357 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _6397) + ((_6357 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _6397), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
        _20484 = _6384;
        _20109 = _6397;
        _19837 = _19838;
        _19833 = float(_6406);
    }
    else
    {
        _20634 = vec3(_5533);
        _20484 = vec4(1.0);
        _20109 = _5533;
        _19837 = vec3(0.0);
        _19833 = 0.0;
    }
    highp vec3 _6445 = normalize(v_viewvector);
    highp vec3 _6453 = mix(frag_info.dielectric_f0.xyz, _6357, vec3(_5504));
    highp float _6456 = dot(_19789, _6445);
    highp float _6457 = max(_6456, 0.0);
    highp float _6461 = max(dot(_5365, _6445), 0.0);
    highp vec3 _6463 = -_6445;
    highp vec3 _6465 = reflect(_6463, _19789);
    highp mat3 _6478 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    bool _6481 = _19833 > 0.5;
    bvec3 _6484 = bvec3(_6481);
    highp vec3 _6486 = _6478 * vec3(_6484.x ? _19837.x : _19789.x, _6484.y ? _19837.y : _19789.y, _6484.z ? _19837.z : _19789.z);
    highp vec3 _19841 = vec3(0.0);
    if (frag_info.probe_box.w > 0.5)
    {
        highp vec3 _7300 = vec3(1.0) / (_6465 + (((step(vec3(0.0), _6465) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07));
        highp vec3 _7317 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _7300, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _7300);
        _19841 = normalize((v_position + (_6465 * max(min(min(_7317.x, _7317.y), _7317.z), 0.0))) - frag_info.probe_box.xyz);
    }
    else
    {
        _19841 = _6465;
    }
    bool _7563 = false;
    highp vec3 _6491 = _6478 * _19841;
    vec3 _7449 = texelFetch(irradiance_field, ivec2(0), 0).xyz;
    highp vec3 hp_copy_7449 = _7449;
    highp float _7364 = _6486.y;
    highp float _7365 = 0.48860299587249755859375 * _7364;
    highp float _7371 = _6486.z;
    highp float _7372 = 0.48860299587249755859375 * _7371;
    highp float _7378 = _6486.x;
    highp float _7379 = 0.48860299587249755859375 * _7378;
    highp float _7386 = 1.09254801273345947265625 * _7378;
    highp float _7389 = _7386 * _7364;
    highp float _7399 = (1.09254801273345947265625 * _7364) * _7371;
    highp float _7411 = 0.3153919875621795654296875 * (((3.0 * _7371) * _7371) - 1.0);
    highp float _7421 = _7386 * _7371;
    highp float _7437 = 0.546274006366729736328125 * ((_7378 * _7378) - (_7364 * _7364));
    highp vec3 _6494 = max(((((((((hp_copy_7449 * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _7365)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _7372)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _7379)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _7389)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _7399)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _7411)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _7421)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _7437), vec3(0.0));
    highp vec3 _19842 = vec3(0.0);
    do
    {
        _7563 = radiance_layout_info.mip_layout > 0.5;
        if (_7563)
        {
            _19842 = textureLod(prefiltered_radiance, (vec2(atan(_6491.z, _6491.x), asin(clamp(_6491.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_19825, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        highp vec2 _7668 = (vec2(atan(_6491.z, _6491.x), asin(clamp(_6491.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _7573 = clamp(_7668.y, 0.00390625, 0.99609375);
        highp float _7577 = clamp(_19825, 0.0, 1.0) * 7.0;
        highp float _7579 = floor(_7577);
        highp float _7598 = _7668.x;
        _19842 = mix(texture(prefiltered_radiance, vec2(_7598, (_7579 + _7573) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_7598, (min(_7579 + 1.0, 7.0) + _7573) * 0.125)).xyz, vec3(_7577 - _7579));
        break;
    } while(false);
    bool _6501 = frag_info.radiance_blend.x > 0.0;
    highp vec3 _19847 = vec3(0.0);
    highp vec3 _19848 = vec3(0.0);
    if (_6501)
    {
        vec3 _7781 = texelFetch(irradiance_field, ivec2(0, 1), 0).xyz;
        highp vec3 hp_copy_7781 = _7781;
        highp vec3 _19843 = vec3(0.0);
        do
        {
            if (_7563)
            {
                _19843 = textureLod(prefiltered_radiance_b, (vec2(atan(_6491.z, _6491.x), asin(clamp(_6491.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_19825, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            highp vec2 _8000 = (vec2(atan(_6491.z, _6491.x), asin(clamp(_6491.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _7905 = clamp(_8000.y, 0.00390625, 0.99609375);
            highp float _7909 = clamp(_19825, 0.0, 1.0) * 7.0;
            highp float _7911 = floor(_7909);
            highp float _7930 = _8000.x;
            _19843 = mix(texture(prefiltered_radiance_b, vec2(_7930, (_7911 + _7905) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_7930, (min(_7911 + 1.0, 7.0) + _7905) * 0.125)).xyz, vec3(_7909 - _7911));
            break;
        } while(false);
        highp vec3 _6512 = vec3(frag_info.radiance_blend.x);
        _19848 = mix(_19842, _19843, _6512);
        _19847 = mix(_6494, max(((((((((hp_copy_7781 * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _7365)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _7372)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _7379)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _7389)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _7399)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _7411)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _7421)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _7437), vec3(0.0)), _6512);
    }
    else
    {
        _19848 = _19842;
        _19847 = _6494;
    }
    highp float _8012 = 0.0;
    highp vec3 _6523 = _19847 * frag_info.environment_intensity;
    highp float _19849 = 0.0;
    do
    {
        _8012 = frag_info.gi_grid.w;
        if (_8012 <= 0.0)
        {
            _19849 = 0.0;
            break;
        }
        highp vec3 _8025 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
        highp vec3 _8033 = min(_8025, (frag_info.gi_counts.xyz - vec3(1.0)) - _8025);
        _19849 = clamp(min(_8033.x, min(_8033.y, _8033.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
        break;
    } while(false);
    highp vec3 _20040 = vec3(0.0);
    if (_19849 > 0.0)
    {
        highp vec3 _8124 = v_position + (((_19789 * 0.20000000298023223876953125) + (_6445 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
        highp vec3 _8127 = _8124 / frag_info.gi_grid.xyz;
        highp vec3 _8129 = floor(_8127);
        highp vec3 _8135 = clamp(_8127 - _8129, vec3(0.0), vec3(1.0));
        highp vec3 _8257 = _8129 - frag_info.gi_anchor.xyz;
        bool _8260 = any(lessThan(_8257, vec3(0.0)));
        bool _8268 = false;
        if (!_8260)
        {
            _8268 = any(greaterThanEqual(_8257, frag_info.gi_counts.xyz));
        }
        else
        {
            _8268 = _8260;
        }
        highp vec3 _8271 = vec3(1.0) - _8135;
        highp vec3 _8275 = max(_8271, vec3(0.001000000047497451305389404296875));
        highp vec3 _8291 = (_8129 * frag_info.gi_grid.xyz) - _8124;
        highp float _8293 = length(_8291);
        highp vec3 _19850 = vec3(0.0);
        if (_8293 > 9.9999997473787516355514526367188e-06)
        {
            _19850 = _8291 / vec3(_8293);
        }
        else
        {
            _19850 = _19789;
        }
        highp float _8311 = pow((dot(_19850, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _8436 = _8129 - (frag_info.gi_counts.xyz * floor(_8129 / frag_info.gi_counts.xyz));
        highp float _8452 = _8436.x + (frag_info.gi_counts.x * (_8436.y + (frag_info.gi_counts.y * _8436.z)));
        bool _8322 = frag_info.gi_visibility.x > 0.0;
        highp float _19855 = 0.0;
        if (_8322)
        {
            highp float _8460 = floor(_8452 / frag_info.gi_counts.w);
            highp vec2 _8474 = vec2((_8452 - (_8460 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_8460 * 16.0));
            highp vec3 _8334 = -_19850;
            highp vec3 _8522 = _8334 / vec3((abs(_8334.x) + abs(_8334.y)) + abs(_8334.z));
            highp vec2 _19851 = vec2(0.0);
            if (_8522.z >= 0.0)
            {
                _19851 = _8522.xy;
            }
            else
            {
                _19851 = (vec2(1.0) - abs(_8522.yx)) * vec2((_8522.x >= 0.0) ? 1.0 : (-1.0), (_8522.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _8338 = texture(irradiance_field, clamp((_8474 + vec2(1.0)) + (clamp((_19851 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _8474 + vec2(0.5), _8474 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _8343 = _8338.x * frag_info.gi_visibility.z;
            highp float _8355 = abs((_8343 * _8343) - ((_8338.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _8361 = (_8293 - _8343) - frag_info.gi_visibility.y;
            highp float _19852 = 0.0;
            if (_8361 <= 0.0)
            {
                _19852 = 1.0;
            }
            else
            {
                _19852 = _8355 / (_8355 + (_8361 * _8361));
            }
            _19855 = _8311 * mix(1.0, max(0.0500000007450580596923828125, (_19852 * _19852) * _19852), frag_info.gi_visibility.x);
        }
        else
        {
            _19855 = _8311;
        }
        highp float _8389 = max(9.9999999747524270787835121154785e-07, _19855);
        highp float _19856 = 0.0;
        if (_8389 < 0.20000000298023223876953125)
        {
            _19856 = _8389 * ((_8389 * _8389) * 25.0);
        }
        else
        {
            _19856 = _8389;
        }
        highp float _8404 = _19856 * (((_8275.x * _8275.y) * _8275.z) * (_8268 ? 0.0 : 1.0));
        highp float _8563 = floor(_8452 / frag_info.gi_counts.w);
        highp vec2 _8577 = vec2((_8452 - (_8563 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_8563 * 8.0));
        highp vec3 _8625 = _19789 / vec3((abs(_19789.x) + abs(_19789.y)) + abs(_19789.z));
        bool _8628 = _8625.z >= 0.0;
        highp vec2 _19857 = vec2(0.0);
        if (_8628)
        {
            _19857 = _8625.xy;
        }
        else
        {
            _19857 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _8416 = texture(irradiance_field, clamp((_8577 + vec2(1.0)) + (clamp((_19857 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _8577 + vec2(0.5), _8577 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _8711 = _8129 + vec3(1.0, 0.0, 0.0);
        highp vec3 _8716 = _8711 - frag_info.gi_anchor.xyz;
        bool _8719 = any(lessThan(_8716, vec3(0.0)));
        bool _8727 = false;
        if (!_8719)
        {
            _8727 = any(greaterThanEqual(_8716, frag_info.gi_counts.xyz));
        }
        else
        {
            _8727 = _8719;
        }
        highp vec3 _8734 = max(mix(_8271, _8135, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _8750 = (_8711 * frag_info.gi_grid.xyz) - _8124;
        highp float _8752 = length(_8750);
        highp vec3 _19859 = vec3(0.0);
        if (_8752 > 9.9999997473787516355514526367188e-06)
        {
            _19859 = _8750 / vec3(_8752);
        }
        else
        {
            _19859 = _19789;
        }
        highp float _8770 = pow((dot(_19859, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _8895 = _8711 - (frag_info.gi_counts.xyz * floor(_8711 / frag_info.gi_counts.xyz));
        highp float _8911 = _8895.x + (frag_info.gi_counts.x * (_8895.y + (frag_info.gi_counts.y * _8895.z)));
        highp float _19864 = 0.0;
        if (_8322)
        {
            highp float _8919 = floor(_8911 / frag_info.gi_counts.w);
            highp vec2 _8933 = vec2((_8911 - (_8919 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_8919 * 16.0));
            highp vec3 _8793 = -_19859;
            highp vec3 _8981 = _8793 / vec3((abs(_8793.x) + abs(_8793.y)) + abs(_8793.z));
            highp vec2 _19860 = vec2(0.0);
            if (_8981.z >= 0.0)
            {
                _19860 = _8981.xy;
            }
            else
            {
                _19860 = (vec2(1.0) - abs(_8981.yx)) * vec2((_8981.x >= 0.0) ? 1.0 : (-1.0), (_8981.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _8797 = texture(irradiance_field, clamp((_8933 + vec2(1.0)) + (clamp((_19860 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _8933 + vec2(0.5), _8933 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _8802 = _8797.x * frag_info.gi_visibility.z;
            highp float _8814 = abs((_8802 * _8802) - ((_8797.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _8820 = (_8752 - _8802) - frag_info.gi_visibility.y;
            highp float _19861 = 0.0;
            if (_8820 <= 0.0)
            {
                _19861 = 1.0;
            }
            else
            {
                _19861 = _8814 / (_8814 + (_8820 * _8820));
            }
            _19864 = _8770 * mix(1.0, max(0.0500000007450580596923828125, (_19861 * _19861) * _19861), frag_info.gi_visibility.x);
        }
        else
        {
            _19864 = _8770;
        }
        highp float _8848 = max(9.9999999747524270787835121154785e-07, _19864);
        highp float _19865 = 0.0;
        if (_8848 < 0.20000000298023223876953125)
        {
            _19865 = _8848 * ((_8848 * _8848) * 25.0);
        }
        else
        {
            _19865 = _8848;
        }
        highp float _8863 = _19865 * (((_8734.x * _8734.y) * _8734.z) * (_8727 ? 0.0 : 1.0));
        highp float _9022 = floor(_8911 / frag_info.gi_counts.w);
        highp vec2 _9036 = vec2((_8911 - (_9022 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9022 * 8.0));
        highp vec2 _19866 = vec2(0.0);
        if (_8628)
        {
            _19866 = _8625.xy;
        }
        else
        {
            _19866 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _8875 = texture(irradiance_field, clamp((_9036 + vec2(1.0)) + (clamp((_19866 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9036 + vec2(0.5), _9036 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9170 = _8129 + vec3(0.0, 1.0, 0.0);
        highp vec3 _9175 = _9170 - frag_info.gi_anchor.xyz;
        bool _9178 = any(lessThan(_9175, vec3(0.0)));
        bool _9186 = false;
        if (!_9178)
        {
            _9186 = any(greaterThanEqual(_9175, frag_info.gi_counts.xyz));
        }
        else
        {
            _9186 = _9178;
        }
        highp vec3 _9193 = max(mix(_8271, _8135, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9209 = (_9170 * frag_info.gi_grid.xyz) - _8124;
        highp float _9211 = length(_9209);
        highp vec3 _19868 = vec3(0.0);
        if (_9211 > 9.9999997473787516355514526367188e-06)
        {
            _19868 = _9209 / vec3(_9211);
        }
        else
        {
            _19868 = _19789;
        }
        highp float _9229 = pow((dot(_19868, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9354 = _9170 - (frag_info.gi_counts.xyz * floor(_9170 / frag_info.gi_counts.xyz));
        highp float _9370 = _9354.x + (frag_info.gi_counts.x * (_9354.y + (frag_info.gi_counts.y * _9354.z)));
        highp float _19873 = 0.0;
        if (_8322)
        {
            highp float _9378 = floor(_9370 / frag_info.gi_counts.w);
            highp vec2 _9392 = vec2((_9370 - (_9378 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9378 * 16.0));
            highp vec3 _9252 = -_19868;
            highp vec3 _9440 = _9252 / vec3((abs(_9252.x) + abs(_9252.y)) + abs(_9252.z));
            highp vec2 _19869 = vec2(0.0);
            if (_9440.z >= 0.0)
            {
                _19869 = _9440.xy;
            }
            else
            {
                _19869 = (vec2(1.0) - abs(_9440.yx)) * vec2((_9440.x >= 0.0) ? 1.0 : (-1.0), (_9440.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9256 = texture(irradiance_field, clamp((_9392 + vec2(1.0)) + (clamp((_19869 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9392 + vec2(0.5), _9392 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9261 = _9256.x * frag_info.gi_visibility.z;
            highp float _9273 = abs((_9261 * _9261) - ((_9256.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9279 = (_9211 - _9261) - frag_info.gi_visibility.y;
            highp float _19870 = 0.0;
            if (_9279 <= 0.0)
            {
                _19870 = 1.0;
            }
            else
            {
                _19870 = _9273 / (_9273 + (_9279 * _9279));
            }
            _19873 = _9229 * mix(1.0, max(0.0500000007450580596923828125, (_19870 * _19870) * _19870), frag_info.gi_visibility.x);
        }
        else
        {
            _19873 = _9229;
        }
        highp float _9307 = max(9.9999999747524270787835121154785e-07, _19873);
        highp float _19874 = 0.0;
        if (_9307 < 0.20000000298023223876953125)
        {
            _19874 = _9307 * ((_9307 * _9307) * 25.0);
        }
        else
        {
            _19874 = _9307;
        }
        highp float _9322 = _19874 * (((_9193.x * _9193.y) * _9193.z) * (_9186 ? 0.0 : 1.0));
        highp float _9481 = floor(_9370 / frag_info.gi_counts.w);
        highp vec2 _9495 = vec2((_9370 - (_9481 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9481 * 8.0));
        highp vec2 _19875 = vec2(0.0);
        if (_8628)
        {
            _19875 = _8625.xy;
        }
        else
        {
            _19875 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9334 = texture(irradiance_field, clamp((_9495 + vec2(1.0)) + (clamp((_19875 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9495 + vec2(0.5), _9495 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _9629 = _8129 + vec3(1.0, 1.0, 0.0);
        highp vec3 _9634 = _9629 - frag_info.gi_anchor.xyz;
        bool _9637 = any(lessThan(_9634, vec3(0.0)));
        bool _9645 = false;
        if (!_9637)
        {
            _9645 = any(greaterThanEqual(_9634, frag_info.gi_counts.xyz));
        }
        else
        {
            _9645 = _9637;
        }
        highp vec3 _9652 = max(mix(_8271, _8135, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _9668 = (_9629 * frag_info.gi_grid.xyz) - _8124;
        highp float _9670 = length(_9668);
        highp vec3 _19877 = vec3(0.0);
        if (_9670 > 9.9999997473787516355514526367188e-06)
        {
            _19877 = _9668 / vec3(_9670);
        }
        else
        {
            _19877 = _19789;
        }
        highp float _9688 = pow((dot(_19877, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _9813 = _9629 - (frag_info.gi_counts.xyz * floor(_9629 / frag_info.gi_counts.xyz));
        highp float _9829 = _9813.x + (frag_info.gi_counts.x * (_9813.y + (frag_info.gi_counts.y * _9813.z)));
        highp float _19882 = 0.0;
        if (_8322)
        {
            highp float _9837 = floor(_9829 / frag_info.gi_counts.w);
            highp vec2 _9851 = vec2((_9829 - (_9837 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_9837 * 16.0));
            highp vec3 _9711 = -_19877;
            highp vec3 _9899 = _9711 / vec3((abs(_9711.x) + abs(_9711.y)) + abs(_9711.z));
            highp vec2 _19878 = vec2(0.0);
            if (_9899.z >= 0.0)
            {
                _19878 = _9899.xy;
            }
            else
            {
                _19878 = (vec2(1.0) - abs(_9899.yx)) * vec2((_9899.x >= 0.0) ? 1.0 : (-1.0), (_9899.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _9715 = texture(irradiance_field, clamp((_9851 + vec2(1.0)) + (clamp((_19878 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _9851 + vec2(0.5), _9851 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _9720 = _9715.x * frag_info.gi_visibility.z;
            highp float _9732 = abs((_9720 * _9720) - ((_9715.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _9738 = (_9670 - _9720) - frag_info.gi_visibility.y;
            highp float _19879 = 0.0;
            if (_9738 <= 0.0)
            {
                _19879 = 1.0;
            }
            else
            {
                _19879 = _9732 / (_9732 + (_9738 * _9738));
            }
            _19882 = _9688 * mix(1.0, max(0.0500000007450580596923828125, (_19879 * _19879) * _19879), frag_info.gi_visibility.x);
        }
        else
        {
            _19882 = _9688;
        }
        highp float _9766 = max(9.9999999747524270787835121154785e-07, _19882);
        highp float _19883 = 0.0;
        if (_9766 < 0.20000000298023223876953125)
        {
            _19883 = _9766 * ((_9766 * _9766) * 25.0);
        }
        else
        {
            _19883 = _9766;
        }
        highp float _9781 = _19883 * (((_9652.x * _9652.y) * _9652.z) * (_9645 ? 0.0 : 1.0));
        highp float _9940 = floor(_9829 / frag_info.gi_counts.w);
        highp vec2 _9954 = vec2((_9829 - (_9940 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_9940 * 8.0));
        highp vec2 _19884 = vec2(0.0);
        if (_8628)
        {
            _19884 = _8625.xy;
        }
        else
        {
            _19884 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _9793 = texture(irradiance_field, clamp((_9954 + vec2(1.0)) + (clamp((_19884 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _9954 + vec2(0.5), _9954 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10088 = _8129 + vec3(0.0, 0.0, 1.0);
        highp vec3 _10093 = _10088 - frag_info.gi_anchor.xyz;
        bool _10096 = any(lessThan(_10093, vec3(0.0)));
        bool _10104 = false;
        if (!_10096)
        {
            _10104 = any(greaterThanEqual(_10093, frag_info.gi_counts.xyz));
        }
        else
        {
            _10104 = _10096;
        }
        highp vec3 _10111 = max(mix(_8271, _8135, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10127 = (_10088 * frag_info.gi_grid.xyz) - _8124;
        highp float _10129 = length(_10127);
        highp vec3 _19886 = vec3(0.0);
        if (_10129 > 9.9999997473787516355514526367188e-06)
        {
            _19886 = _10127 / vec3(_10129);
        }
        else
        {
            _19886 = _19789;
        }
        highp float _10147 = pow((dot(_19886, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10272 = _10088 - (frag_info.gi_counts.xyz * floor(_10088 / frag_info.gi_counts.xyz));
        highp float _10288 = _10272.x + (frag_info.gi_counts.x * (_10272.y + (frag_info.gi_counts.y * _10272.z)));
        highp float _19891 = 0.0;
        if (_8322)
        {
            highp float _10296 = floor(_10288 / frag_info.gi_counts.w);
            highp vec2 _10310 = vec2((_10288 - (_10296 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10296 * 16.0));
            highp vec3 _10170 = -_19886;
            highp vec3 _10358 = _10170 / vec3((abs(_10170.x) + abs(_10170.y)) + abs(_10170.z));
            highp vec2 _19887 = vec2(0.0);
            if (_10358.z >= 0.0)
            {
                _19887 = _10358.xy;
            }
            else
            {
                _19887 = (vec2(1.0) - abs(_10358.yx)) * vec2((_10358.x >= 0.0) ? 1.0 : (-1.0), (_10358.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10174 = texture(irradiance_field, clamp((_10310 + vec2(1.0)) + (clamp((_19887 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10310 + vec2(0.5), _10310 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10179 = _10174.x * frag_info.gi_visibility.z;
            highp float _10191 = abs((_10179 * _10179) - ((_10174.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10197 = (_10129 - _10179) - frag_info.gi_visibility.y;
            highp float _19888 = 0.0;
            if (_10197 <= 0.0)
            {
                _19888 = 1.0;
            }
            else
            {
                _19888 = _10191 / (_10191 + (_10197 * _10197));
            }
            _19891 = _10147 * mix(1.0, max(0.0500000007450580596923828125, (_19888 * _19888) * _19888), frag_info.gi_visibility.x);
        }
        else
        {
            _19891 = _10147;
        }
        highp float _10225 = max(9.9999999747524270787835121154785e-07, _19891);
        highp float _19892 = 0.0;
        if (_10225 < 0.20000000298023223876953125)
        {
            _19892 = _10225 * ((_10225 * _10225) * 25.0);
        }
        else
        {
            _19892 = _10225;
        }
        highp float _10240 = _19892 * (((_10111.x * _10111.y) * _10111.z) * (_10104 ? 0.0 : 1.0));
        highp float _10399 = floor(_10288 / frag_info.gi_counts.w);
        highp vec2 _10413 = vec2((_10288 - (_10399 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10399 * 8.0));
        highp vec2 _19893 = vec2(0.0);
        if (_8628)
        {
            _19893 = _8625.xy;
        }
        else
        {
            _19893 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10252 = texture(irradiance_field, clamp((_10413 + vec2(1.0)) + (clamp((_19893 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10413 + vec2(0.5), _10413 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _10547 = _8129 + vec3(1.0, 0.0, 1.0);
        highp vec3 _10552 = _10547 - frag_info.gi_anchor.xyz;
        bool _10555 = any(lessThan(_10552, vec3(0.0)));
        bool _10563 = false;
        if (!_10555)
        {
            _10563 = any(greaterThanEqual(_10552, frag_info.gi_counts.xyz));
        }
        else
        {
            _10563 = _10555;
        }
        highp vec3 _10570 = max(mix(_8271, _8135, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _10586 = (_10547 * frag_info.gi_grid.xyz) - _8124;
        highp float _10588 = length(_10586);
        highp vec3 _19895 = vec3(0.0);
        if (_10588 > 9.9999997473787516355514526367188e-06)
        {
            _19895 = _10586 / vec3(_10588);
        }
        else
        {
            _19895 = _19789;
        }
        highp float _10606 = pow((dot(_19895, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _10731 = _10547 - (frag_info.gi_counts.xyz * floor(_10547 / frag_info.gi_counts.xyz));
        highp float _10747 = _10731.x + (frag_info.gi_counts.x * (_10731.y + (frag_info.gi_counts.y * _10731.z)));
        highp float _19900 = 0.0;
        if (_8322)
        {
            highp float _10755 = floor(_10747 / frag_info.gi_counts.w);
            highp vec2 _10769 = vec2((_10747 - (_10755 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10755 * 16.0));
            highp vec3 _10629 = -_19895;
            highp vec3 _10817 = _10629 / vec3((abs(_10629.x) + abs(_10629.y)) + abs(_10629.z));
            highp vec2 _19896 = vec2(0.0);
            if (_10817.z >= 0.0)
            {
                _19896 = _10817.xy;
            }
            else
            {
                _19896 = (vec2(1.0) - abs(_10817.yx)) * vec2((_10817.x >= 0.0) ? 1.0 : (-1.0), (_10817.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10633 = texture(irradiance_field, clamp((_10769 + vec2(1.0)) + (clamp((_19896 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10769 + vec2(0.5), _10769 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _10638 = _10633.x * frag_info.gi_visibility.z;
            highp float _10650 = abs((_10638 * _10638) - ((_10633.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _10656 = (_10588 - _10638) - frag_info.gi_visibility.y;
            highp float _19897 = 0.0;
            if (_10656 <= 0.0)
            {
                _19897 = 1.0;
            }
            else
            {
                _19897 = _10650 / (_10650 + (_10656 * _10656));
            }
            _19900 = _10606 * mix(1.0, max(0.0500000007450580596923828125, (_19897 * _19897) * _19897), frag_info.gi_visibility.x);
        }
        else
        {
            _19900 = _10606;
        }
        highp float _10684 = max(9.9999999747524270787835121154785e-07, _19900);
        highp float _19901 = 0.0;
        if (_10684 < 0.20000000298023223876953125)
        {
            _19901 = _10684 * ((_10684 * _10684) * 25.0);
        }
        else
        {
            _19901 = _10684;
        }
        highp float _10699 = _19901 * (((_10570.x * _10570.y) * _10570.z) * (_10563 ? 0.0 : 1.0));
        highp float _10858 = floor(_10747 / frag_info.gi_counts.w);
        highp vec2 _10872 = vec2((_10747 - (_10858 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10858 * 8.0));
        highp vec2 _19902 = vec2(0.0);
        if (_8628)
        {
            _19902 = _8625.xy;
        }
        else
        {
            _19902 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _10711 = texture(irradiance_field, clamp((_10872 + vec2(1.0)) + (clamp((_19902 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10872 + vec2(0.5), _10872 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11006 = _8129 + vec3(0.0, 1.0, 1.0);
        highp vec3 _11011 = _11006 - frag_info.gi_anchor.xyz;
        bool _11014 = any(lessThan(_11011, vec3(0.0)));
        bool _11022 = false;
        if (!_11014)
        {
            _11022 = any(greaterThanEqual(_11011, frag_info.gi_counts.xyz));
        }
        else
        {
            _11022 = _11014;
        }
        highp vec3 _11029 = max(mix(_8271, _8135, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
        highp vec3 _11045 = (_11006 * frag_info.gi_grid.xyz) - _8124;
        highp float _11047 = length(_11045);
        highp vec3 _19904 = vec3(0.0);
        if (_11047 > 9.9999997473787516355514526367188e-06)
        {
            _19904 = _11045 / vec3(_11047);
        }
        else
        {
            _19904 = _19789;
        }
        highp float _11065 = pow((dot(_19904, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11190 = _11006 - (frag_info.gi_counts.xyz * floor(_11006 / frag_info.gi_counts.xyz));
        highp float _11206 = _11190.x + (frag_info.gi_counts.x * (_11190.y + (frag_info.gi_counts.y * _11190.z)));
        highp float _19909 = 0.0;
        if (_8322)
        {
            highp float _11214 = floor(_11206 / frag_info.gi_counts.w);
            highp vec2 _11228 = vec2((_11206 - (_11214 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11214 * 16.0));
            highp vec3 _11088 = -_19904;
            highp vec3 _11276 = _11088 / vec3((abs(_11088.x) + abs(_11088.y)) + abs(_11088.z));
            highp vec2 _19905 = vec2(0.0);
            if (_11276.z >= 0.0)
            {
                _19905 = _11276.xy;
            }
            else
            {
                _19905 = (vec2(1.0) - abs(_11276.yx)) * vec2((_11276.x >= 0.0) ? 1.0 : (-1.0), (_11276.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11092 = texture(irradiance_field, clamp((_11228 + vec2(1.0)) + (clamp((_19905 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11228 + vec2(0.5), _11228 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11097 = _11092.x * frag_info.gi_visibility.z;
            highp float _11109 = abs((_11097 * _11097) - ((_11092.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11115 = (_11047 - _11097) - frag_info.gi_visibility.y;
            highp float _19906 = 0.0;
            if (_11115 <= 0.0)
            {
                _19906 = 1.0;
            }
            else
            {
                _19906 = _11109 / (_11109 + (_11115 * _11115));
            }
            _19909 = _11065 * mix(1.0, max(0.0500000007450580596923828125, (_19906 * _19906) * _19906), frag_info.gi_visibility.x);
        }
        else
        {
            _19909 = _11065;
        }
        highp float _11143 = max(9.9999999747524270787835121154785e-07, _19909);
        highp float _19910 = 0.0;
        if (_11143 < 0.20000000298023223876953125)
        {
            _19910 = _11143 * ((_11143 * _11143) * 25.0);
        }
        else
        {
            _19910 = _11143;
        }
        highp float _11158 = _19910 * (((_11029.x * _11029.y) * _11029.z) * (_11022 ? 0.0 : 1.0));
        highp float _11317 = floor(_11206 / frag_info.gi_counts.w);
        highp vec2 _11331 = vec2((_11206 - (_11317 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11317 * 8.0));
        highp vec2 _19911 = vec2(0.0);
        if (_8628)
        {
            _19911 = _8625.xy;
        }
        else
        {
            _19911 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11170 = texture(irradiance_field, clamp((_11331 + vec2(1.0)) + (clamp((_19911 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11331 + vec2(0.5), _11331 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec3 _11465 = _8129 + vec3(1.0);
        highp vec3 _11470 = _11465 - frag_info.gi_anchor.xyz;
        bool _11473 = any(lessThan(_11470, vec3(0.0)));
        bool _11481 = false;
        if (!_11473)
        {
            _11481 = any(greaterThanEqual(_11470, frag_info.gi_counts.xyz));
        }
        else
        {
            _11481 = _11473;
        }
        highp vec3 _11488 = max(_8135, vec3(0.001000000047497451305389404296875));
        highp vec3 _11504 = (_11465 * frag_info.gi_grid.xyz) - _8124;
        highp float _11506 = length(_11504);
        highp vec3 _19913 = vec3(0.0);
        if (_11506 > 9.9999997473787516355514526367188e-06)
        {
            _19913 = _11504 / vec3(_11506);
        }
        else
        {
            _19913 = _19789;
        }
        highp float _11524 = pow((dot(_19913, _19789) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
        highp vec3 _11649 = _11465 - (frag_info.gi_counts.xyz * floor(_11465 / frag_info.gi_counts.xyz));
        highp float _11665 = _11649.x + (frag_info.gi_counts.x * (_11649.y + (frag_info.gi_counts.y * _11649.z)));
        highp float _19918 = 0.0;
        if (_8322)
        {
            highp float _11673 = floor(_11665 / frag_info.gi_counts.w);
            highp vec2 _11687 = vec2((_11665 - (_11673 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11673 * 16.0));
            highp vec3 _11547 = -_19913;
            highp vec3 _11735 = _11547 / vec3((abs(_11547.x) + abs(_11547.y)) + abs(_11547.z));
            highp vec2 _19914 = vec2(0.0);
            if (_11735.z >= 0.0)
            {
                _19914 = _11735.xy;
            }
            else
            {
                _19914 = (vec2(1.0) - abs(_11735.yx)) * vec2((_11735.x >= 0.0) ? 1.0 : (-1.0), (_11735.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11551 = texture(irradiance_field, clamp((_11687 + vec2(1.0)) + (clamp((_19914 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11687 + vec2(0.5), _11687 + vec2(15.5)) * frag_info.gi_atlas.zw);
            highp float _11556 = _11551.x * frag_info.gi_visibility.z;
            highp float _11568 = abs((_11556 * _11556) - ((_11551.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
            highp float _11574 = (_11506 - _11556) - frag_info.gi_visibility.y;
            highp float _19915 = 0.0;
            if (_11574 <= 0.0)
            {
                _19915 = 1.0;
            }
            else
            {
                _19915 = _11568 / (_11568 + (_11574 * _11574));
            }
            _19918 = _11524 * mix(1.0, max(0.0500000007450580596923828125, (_19915 * _19915) * _19915), frag_info.gi_visibility.x);
        }
        else
        {
            _19918 = _11524;
        }
        highp float _11602 = max(9.9999999747524270787835121154785e-07, _19918);
        highp float _19919 = 0.0;
        if (_11602 < 0.20000000298023223876953125)
        {
            _19919 = _11602 * ((_11602 * _11602) * 25.0);
        }
        else
        {
            _19919 = _11602;
        }
        highp float _11617 = _19919 * (((_11488.x * _11488.y) * _11488.z) * (_11481 ? 0.0 : 1.0));
        highp float _11776 = floor(_11665 / frag_info.gi_counts.w);
        highp vec2 _11790 = vec2((_11665 - (_11776 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11776 * 8.0));
        highp vec2 _19920 = vec2(0.0);
        if (_8628)
        {
            _19920 = _8625.xy;
        }
        else
        {
            _19920 = (vec2(1.0) - abs(_8625.yx)) * vec2((_8625.x >= 0.0) ? 1.0 : (-1.0), (_8625.y >= 0.0) ? 1.0 : (-1.0));
        }
        highp vec4 _11629 = texture(irradiance_field, clamp((_11790 + vec2(1.0)) + (clamp((_19920 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11790 + vec2(0.5), _11790 + vec2(7.5)) * frag_info.gi_atlas.zw);
        highp vec4 _8182 = ((((((vec4(max(_8416.xyz, vec3(0.0)) * _8404, _8404) + vec4(max(_8875.xyz, vec3(0.0)) * _8863, _8863)) + vec4(max(_9334.xyz, vec3(0.0)) * _9322, _9322)) + vec4(max(_9793.xyz, vec3(0.0)) * _9781, _9781)) + vec4(max(_10252.xyz, vec3(0.0)) * _10240, _10240)) + vec4(max(_10711.xyz, vec3(0.0)) * _10699, _10699)) + vec4(max(_11170.xyz, vec3(0.0)) * _11158, _11158)) + vec4(max(_11629.xyz, vec3(0.0)) * _11617, _11617);
        highp float _8184 = _8182.w;
        highp vec3 _19922 = vec3(0.0);
        if (_8184 > 9.9999999747524270787835121154785e-07)
        {
            _19922 = _8182.xyz / vec3(_8184);
        }
        else
        {
            _19922 = vec3(0.0);
        }
        _20040 = mix(_6523, _19922 * _8012, vec3(_19849));
    }
    else
    {
        _20040 = _6523;
    }
    highp vec2 _6549 = clamp(vec2(_6461, _19825), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _6551 = texture(brdf_lut, vec2(_6549.x * 0.3333333432674407958984375, _6549.y));
    float _6555 = _6551.x;
    highp float hp_copy_6555 = _6555;
    float _6558 = _6551.y;
    highp float hp_copy_6558 = _6558;
    highp vec3 _6560 = ((_6453 + ((max(vec3(1.0 - _19825), _6453) - _6453) * pow(clamp(1.0 - _6461, 0.0, 1.0), 5.0))) * _6555) + vec3(_6558);
    highp float _6566 = 1.0 - (hp_copy_6555 + hp_copy_6558);
    highp vec3 _6570 = vec3(1.0) - _6453;
    highp vec3 _6573 = _6453 + (_6570 * vec3(0.0476190485060214996337890625));
    highp vec3 _6584 = ((_6560 * _6566) * _6573) / (vec3(1.0) - (_6573 * _6566));
    highp float _6587 = 1.0 - _5504;
    highp vec3 _6588 = _6357 * _6587;
    highp float _20775 = 0.0;
    if ((frag_info.ssao_params.y > 1.5) && _6481)
    {
        highp float _11898 = max(acos(clamp(exp2(((-3.321929931640625) * _19825) * _19825), 0.0, 1.0)), 0.100000001490116119384765625);
        _20775 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_19837, _6465), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _20109, 0.0, 1.0)))) + _11898) / (2.0 * _11898), 0.0, 1.0));
    }
    else
    {
        highp float _20776 = 0.0;
        if (frag_info.ssao_params.y > 0.5)
        {
            _20776 = clamp((pow(_6457 + _20109, exp2(((-16.0) * _19825) - 1.0)) - 1.0) + _20109, 0.0, 1.0);
        }
        else
        {
            _20776 = _20109;
        }
        _20775 = _20776;
    }
    bool _6637 = frag_info.has_directional_light > 0.5;
    highp float _20231 = 0.0;
    highp vec3 _20859 = vec3(0.0);
    if (_6637)
    {
        highp vec3 _6643 = -normalize(frag_info.directional_light_direction.xyz);
        _20859 = _6643;
        _20231 = dot(_5365, _6643);
    }
    else
    {
        _20859 = vec3(0.0);
        _20231 = 0.0;
    }
    highp float _6650 = clamp(_20231 * 6.666666507720947265625, 0.0, 1.0);
    bool _6659 = false;
    if (_6637)
    {
        _6659 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _6659 = _6637;
    }
    highp float _20468 = 0.0;
    if (_6659 && (_6650 > 0.0))
    {
        int _12019 = int(frag_info.shadow_cascade_count);
        highp float _12468 = max(dot(_5365, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        highp float _12471 = _12468 * _12468;
        highp vec3 _12491 = v_position + (_5365 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _12471, 0.0)) / _12471, 8.0))));
        highp float _12025 = frag_info.directional_light_color.w * 0.5;
        highp float _20285 = 0.0;
        highp float _20325 = 0.0;
        if (_12019 > 0)
        {
            highp vec4 _12042 = frag_info.light_space_matrix[0] * vec4(_12491, 1.0);
            highp vec3 _12048 = _12042.xyz / vec3(_12042.w);
            highp vec2 _12051 = _12048.xy * 0.5;
            highp vec2 _12053 = _12051 + vec2(0.5);
            highp float _12060 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
            highp float _12062 = _12053.x;
            bool _12064 = _12062 < _12060;
            bool _12073 = false;
            if (!_12064)
            {
                _12073 = _12062 > (1.0 - _12060);
            }
            else
            {
                _12073 = _12064;
            }
            bool _12081 = false;
            if (!_12073)
            {
                _12081 = _12053.y < _12060;
            }
            else
            {
                _12081 = _12073;
            }
            bool _12090 = false;
            if (!_12081)
            {
                _12090 = _12053.y > (1.0 - _12060);
            }
            else
            {
                _12090 = _12081;
            }
            bool _12097 = false;
            if (!_12090)
            {
                _12097 = _12048.z < 0.0;
            }
            else
            {
                _12097 = _12090;
            }
            bool _12104 = false;
            if (!_12097)
            {
                _12104 = _12048.z > 1.0;
            }
            else
            {
                _12104 = _12097;
            }
            highp float _20286 = 0.0;
            highp float _20326 = 0.0;
            if (!_12104)
            {
                highp vec2 _12499 = vec2(_12060);
                highp vec2 _12504 = vec2(_12060 + max(_12025, 9.9999997473787516355514526367188e-05));
                highp vec2 _12512 = vec2(0.5) - _12051;
                highp vec2 _12514 = smoothstep(_12499, _12504, _12053) * smoothstep(_12499, _12504, _12512);
                highp float _20232 = 0.0;
                if (_12025 > 0.0)
                {
                    _20232 = _12514.x * _12514.y;
                }
                else
                {
                    _20232 = 1.0;
                }
                highp float _12113 = min(_20232, 1.0);
                bool _12115 = _12113 > 0.0;
                highp float _20327 = 0.0;
                if (_12115)
                {
                    highp float _12626 = _12048.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                    highp float _12632 = 1.0 / (float(_12019) + frag_info.spot_shadow_params.x);
                    highp float _12640 = step(0.5, frag_info.directional_light_direction.w) * (1.0 - step(1.5, frag_info.directional_light_direction.w));
                    highp float _12651 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _12640);
                    highp float _12653 = cos(_12651);
                    highp float _12655 = sin(_12651);
                    highp float _20250 = 0.0;
                    if ((frag_info.directional_light_direction.w > 1.5) && (frag_info.directional_light_direction.w < 2.5))
                    {
                        highp float _12674 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _12679 = max(_12674 * _12626, frag_info.shadow_texel_size);
                        highp float _20240 = 0.0;
                        highp float _20241 = 0.0;
                        _20241 = 0.0;
                        _20240 = 0.0;
                        highp float _12701 = 0.0;
                        highp float _12704 = 0.0;
                        for (int _20239 = 0; _20239 < 9; _20241 = _12701, _20240 = _12704, _20239++)
                        {
                            highp vec2 _21203 = vec2(0.0);
                            do
                            {
                                if (_20239 == 0)
                                {
                                    _21203 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20239 == 1)
                                {
                                    _21203 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20239 == 2)
                                {
                                    _21203 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20239 == 3)
                                {
                                    _21203 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20239 == 4)
                                {
                                    _21203 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20239 == 5)
                                {
                                    _21203 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20239 == 6)
                                {
                                    _21203 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20239 == 7)
                                {
                                    _21203 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20239 == 8)
                                {
                                    _21203 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20239 == 9)
                                {
                                    _21203 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20239 == 10)
                                {
                                    _21203 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20239 == 11)
                                {
                                    _21203 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20239 == 12)
                                {
                                    _21203 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20239 == 13)
                                {
                                    _21203 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20239 == 14)
                                {
                                    _21203 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20239 == 15)
                                {
                                    _21203 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21203 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _12947 = clamp(_12053 + (vec2((_21203.x * _12653) - (_21203.y * _12655), (_21203.x * _12655) + (_21203.y * _12653)) * _12679), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _12956 = _12947.y;
                            highp vec2 _12957 = vec2(_12947.x * _12632, _12956);
                            _12957.y = 1.0 - _12956;
                            vec4 _12964 = texture(shadow_map, _12957);
                            float _12965 = _12964.x;
                            highp float _12696 = step(_12965, _12626);
                            _12701 = _20241 + (_12965 * _12696);
                            _12704 = _20240 + _12696;
                        }
                        highp float _20242 = 0.0;
                        if (_20240 > 0.0)
                        {
                            _20242 = _20241 / _20240;
                        }
                        else
                        {
                            _20242 = _12626;
                        }
                        _20250 = clamp(_12674 * max(_12626 - _20242, 0.0), frag_info.shadow_texel_size, _12060);
                    }
                    else
                    {
                        _20250 = _12060;
                    }
                    highp float _20257 = 0.0;
                    if (frag_info.directional_light_direction.w > 2.5)
                    {
                        highp vec2 _12993 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _12997 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _12998 = clamp(_12053 + (vec2(-0.707099974155426025390625) * _20250), _12993, _12997);
                        highp vec2 _13009 = (vec2(_12998.x, 1.0 - _12998.y) / _12993) - vec2(0.5);
                        highp vec2 _13011 = floor(_13009);
                        highp vec2 _13014 = _13009 - _13011;
                        highp vec2 _13019 = (_13011 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13029 = vec2(_13019.x * _12632, _13019.y);
                        highp float _13033 = frag_info.shadow_texel_size * _12632;
                        highp vec2 _13036 = vec2(_13033, frag_info.shadow_texel_size);
                        highp vec2 _13045 = vec2(_13033, 0.0);
                        highp vec2 _13053 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _13082 = _13014.x;
                        highp vec2 _13123 = clamp(_12053 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _20250), _12993, _12997);
                        highp vec2 _13134 = (vec2(_13123.x, 1.0 - _13123.y) / _12993) - vec2(0.5);
                        highp vec2 _13136 = floor(_13134);
                        highp vec2 _13139 = _13134 - _13136;
                        highp vec2 _13144 = (_13136 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13154 = vec2(_13144.x * _12632, _13144.y);
                        highp float _13207 = _13139.x;
                        highp vec2 _13248 = clamp(_12053 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _20250), _12993, _12997);
                        highp vec2 _13259 = (vec2(_13248.x, 1.0 - _13248.y) / _12993) - vec2(0.5);
                        highp vec2 _13261 = floor(_13259);
                        highp vec2 _13264 = _13259 - _13261;
                        highp vec2 _13269 = (_13261 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13279 = vec2(_13269.x * _12632, _13269.y);
                        highp float _13332 = _13264.x;
                        highp vec2 _13373 = clamp(_12053 + (vec2(0.707099974155426025390625) * _20250), _12993, _12997);
                        highp vec2 _13384 = (vec2(_13373.x, 1.0 - _13373.y) / _12993) - vec2(0.5);
                        highp vec2 _13386 = floor(_13384);
                        highp vec2 _13389 = _13384 - _13386;
                        highp vec2 _13394 = (_13386 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _13404 = vec2(_13394.x * _12632, _13394.y);
                        highp float _13457 = _13389.x;
                        highp float _12761 = ((mix(mix(float(_12626 <= texture(shadow_map, _13029).x), float(_12626 <= texture(shadow_map, _13029 + _13045).x), _13082), mix(float(_12626 <= texture(shadow_map, _13029 + _13053).x), float(_12626 <= texture(shadow_map, _13029 + _13036).x), _13082), _13014.y) + mix(mix(float(_12626 <= texture(shadow_map, _13154).x), float(_12626 <= texture(shadow_map, _13154 + _13045).x), _13207), mix(float(_12626 <= texture(shadow_map, _13154 + _13053).x), float(_12626 <= texture(shadow_map, _13154 + _13036).x), _13207), _13139.y)) + mix(mix(float(_12626 <= texture(shadow_map, _13279).x), float(_12626 <= texture(shadow_map, _13279 + _13045).x), _13332), mix(float(_12626 <= texture(shadow_map, _13279 + _13053).x), float(_12626 <= texture(shadow_map, _13279 + _13036).x), _13332), _13264.y)) + mix(mix(float(_12626 <= texture(shadow_map, _13404).x), float(_12626 <= texture(shadow_map, _13404 + _13045).x), _13457), mix(float(_12626 <= texture(shadow_map, _13404 + _13053).x), float(_12626 <= texture(shadow_map, _13404 + _13036).x), _13457), _13389.y);
                        _20257 = _12761 * 0.25;
                    }
                    else
                    {
                        int _12767 = (_12640 > 0.5) ? 17 : 16;
                        highp float _20253 = 0.0;
                        _20253 = 0.0;
                        highp float _12795 = 0.0;
                        for (int _20243 = 0; _20243 < 17; _20253 = _12795, _20243++)
                        {
                            if (_20243 >= _12767)
                            {
                                break;
                            }
                            highp vec2 _20244 = vec2(0.0);
                            do
                            {
                                if (_20243 == 0)
                                {
                                    _20244 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20243 == 1)
                                {
                                    _20244 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20243 == 2)
                                {
                                    _20244 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20243 == 3)
                                {
                                    _20244 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20243 == 4)
                                {
                                    _20244 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20243 == 5)
                                {
                                    _20244 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20243 == 6)
                                {
                                    _20244 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20243 == 7)
                                {
                                    _20244 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20243 == 8)
                                {
                                    _20244 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20243 == 9)
                                {
                                    _20244 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20243 == 10)
                                {
                                    _20244 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20243 == 11)
                                {
                                    _20244 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20243 == 12)
                                {
                                    _20244 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20243 == 13)
                                {
                                    _20244 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20243 == 14)
                                {
                                    _20244 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20243 == 15)
                                {
                                    _20244 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _20244 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _20246 = vec2(0.0);
                            do
                            {
                                if (_20243 < 3)
                                {
                                    _20246 = vec2(float(_20243) - 1.0, -1.0);
                                    break;
                                }
                                if (_20243 < 6)
                                {
                                    _20246 = vec2((float(_20243 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_20243 < 11)
                                {
                                    _20246 = vec2((float(_20243 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_20243 < 14)
                                {
                                    _20246 = vec2((float(_20243 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _20246 = vec2(float(_20243 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            highp vec2 _12784 = mix(_20244, _20246, vec2(_12640));
                            highp float _13595 = _12784.x;
                            highp float _13599 = _12784.y;
                            highp vec2 _13625 = clamp(_12053 + (vec2((_13595 * _12653) - (_13599 * _12655), (_13595 * _12655) + (_13599 * _12653)) * _20250), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _13634 = _13625.y;
                            highp vec2 _13635 = vec2(_13625.x * _12632, _13634);
                            _13635.y = 1.0 - _13634;
                            _12795 = _20253 + float(_12626 <= texture(shadow_map, _13635).x);
                        }
                        _20257 = _20253 / float(_12767);
                    }
                    bool _12808 = 0 == (_12019 - 1);
                    bool _12814 = false;
                    if (_12808)
                    {
                        _12814 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _12814 = _12808;
                    }
                    highp float _20258 = 0.0;
                    if (_12814)
                    {
                        highp vec2 _12821 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                        highp vec2 _12829 = smoothstep(vec2(0.0), _12821, _12053) * smoothstep(vec2(0.0), _12821, _12512);
                        _20258 = mix(1.0, _20257, _12829.x * _12829.y);
                    }
                    else
                    {
                        _20258 = _20257;
                    }
                    _20327 = _12113 * _20258;
                }
                else
                {
                    _20327 = 0.0;
                }
                _20326 = _20327;
                _20286 = _12115 ? _12113 : 0.0;
            }
            else
            {
                _20326 = 0.0;
                _20286 = 0.0;
            }
            _20325 = _20326;
            _20285 = _20286;
        }
        else
        {
            _20325 = 0.0;
            _20285 = 0.0;
        }
        highp float _20344 = 0.0;
        highp float _20384 = 0.0;
        if ((_20285 < 1.0) && (_12019 > 1))
        {
            highp vec4 _12148 = frag_info.light_space_matrix[1] * vec4(_12491, 1.0);
            highp vec3 _12154 = _12148.xyz / vec3(_12148.w);
            highp vec2 _12157 = _12154.xy * 0.5;
            highp vec2 _12159 = _12157 + vec2(0.5);
            highp float _12166 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
            highp float _12168 = _12159.x;
            bool _12170 = _12168 < _12166;
            bool _12179 = false;
            if (!_12170)
            {
                _12179 = _12168 > (1.0 - _12166);
            }
            else
            {
                _12179 = _12170;
            }
            bool _12187 = false;
            if (!_12179)
            {
                _12187 = _12159.y < _12166;
            }
            else
            {
                _12187 = _12179;
            }
            bool _12196 = false;
            if (!_12187)
            {
                _12196 = _12159.y > (1.0 - _12166);
            }
            else
            {
                _12196 = _12187;
            }
            bool _12203 = false;
            if (!_12196)
            {
                _12203 = _12154.z < 0.0;
            }
            else
            {
                _12203 = _12196;
            }
            bool _12210 = false;
            if (!_12203)
            {
                _12210 = _12154.z > 1.0;
            }
            else
            {
                _12210 = _12203;
            }
            highp float _20345 = 0.0;
            highp float _20385 = 0.0;
            if (!_12210)
            {
                highp vec2 _13655 = vec2(_12166);
                highp vec2 _13660 = vec2(_12166 + max(_12025, 9.9999997473787516355514526367188e-05));
                highp vec2 _13668 = vec2(0.5) - _12157;
                highp vec2 _13670 = smoothstep(_13655, _13660, _12159) * smoothstep(_13655, _13660, _13668);
                highp float _20288 = 0.0;
                if (_12025 > 0.0)
                {
                    _20288 = _13670.x * _13670.y;
                }
                else
                {
                    _20288 = 1.0;
                }
                highp float _12219 = min(_20288, 1.0 - _20285);
                highp float _20346 = 0.0;
                highp float _20386 = 0.0;
                if (_12219 > 0.0)
                {
                    highp float _13782 = _12154.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                    highp float _13788 = 1.0 / (float(_12019) + frag_info.spot_shadow_params.x);
                    highp float _13796 = step(0.5, frag_info.directional_light_direction.w) * (1.0 - step(1.5, frag_info.directional_light_direction.w));
                    highp float _13807 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _13796);
                    highp float _13809 = cos(_13807);
                    highp float _13811 = sin(_13807);
                    highp float _20306 = 0.0;
                    if ((frag_info.directional_light_direction.w > 1.5) && (frag_info.directional_light_direction.w < 2.5))
                    {
                        highp float _13830 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _13835 = max(_13830 * _13782, frag_info.shadow_texel_size);
                        highp float _20296 = 0.0;
                        highp float _20297 = 0.0;
                        _20297 = 0.0;
                        _20296 = 0.0;
                        highp float _13857 = 0.0;
                        highp float _13860 = 0.0;
                        for (int _20295 = 0; _20295 < 9; _20297 = _13857, _20296 = _13860, _20295++)
                        {
                            highp vec2 _21199 = vec2(0.0);
                            do
                            {
                                if (_20295 == 0)
                                {
                                    _21199 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20295 == 1)
                                {
                                    _21199 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20295 == 2)
                                {
                                    _21199 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20295 == 3)
                                {
                                    _21199 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20295 == 4)
                                {
                                    _21199 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20295 == 5)
                                {
                                    _21199 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20295 == 6)
                                {
                                    _21199 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20295 == 7)
                                {
                                    _21199 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20295 == 8)
                                {
                                    _21199 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20295 == 9)
                                {
                                    _21199 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20295 == 10)
                                {
                                    _21199 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20295 == 11)
                                {
                                    _21199 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20295 == 12)
                                {
                                    _21199 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20295 == 13)
                                {
                                    _21199 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20295 == 14)
                                {
                                    _21199 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20295 == 15)
                                {
                                    _21199 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21199 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _14103 = clamp(_12159 + (vec2((_21199.x * _13809) - (_21199.y * _13811), (_21199.x * _13811) + (_21199.y * _13809)) * _13835), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _14112 = _14103.y;
                            highp vec2 _14113 = vec2((1.0 + _14103.x) * _13788, _14112);
                            _14113.y = 1.0 - _14112;
                            vec4 _14120 = texture(shadow_map, _14113);
                            float _14121 = _14120.x;
                            highp float _13852 = step(_14121, _13782);
                            _13857 = _20297 + (_14121 * _13852);
                            _13860 = _20296 + _13852;
                        }
                        highp float _20298 = 0.0;
                        if (_20296 > 0.0)
                        {
                            _20298 = _20297 / _20296;
                        }
                        else
                        {
                            _20298 = _13782;
                        }
                        _20306 = clamp(_13830 * max(_13782 - _20298, 0.0), frag_info.shadow_texel_size, _12166);
                    }
                    else
                    {
                        _20306 = _12166;
                    }
                    highp float _20313 = 0.0;
                    if (frag_info.directional_light_direction.w > 2.5)
                    {
                        highp vec2 _14149 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _14153 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _14154 = clamp(_12159 + (vec2(-0.707099974155426025390625) * _20306), _14149, _14153);
                        highp vec2 _14165 = (vec2(_14154.x, 1.0 - _14154.y) / _14149) - vec2(0.5);
                        highp vec2 _14167 = floor(_14165);
                        highp vec2 _14170 = _14165 - _14167;
                        highp vec2 _14175 = (_14167 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14185 = vec2((1.0 + _14175.x) * _13788, _14175.y);
                        highp float _14189 = frag_info.shadow_texel_size * _13788;
                        highp vec2 _14192 = vec2(_14189, frag_info.shadow_texel_size);
                        highp vec2 _14201 = vec2(_14189, 0.0);
                        highp vec2 _14209 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _14238 = _14170.x;
                        highp vec2 _14279 = clamp(_12159 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _20306), _14149, _14153);
                        highp vec2 _14290 = (vec2(_14279.x, 1.0 - _14279.y) / _14149) - vec2(0.5);
                        highp vec2 _14292 = floor(_14290);
                        highp vec2 _14295 = _14290 - _14292;
                        highp vec2 _14300 = (_14292 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14310 = vec2((1.0 + _14300.x) * _13788, _14300.y);
                        highp float _14363 = _14295.x;
                        highp vec2 _14404 = clamp(_12159 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _20306), _14149, _14153);
                        highp vec2 _14415 = (vec2(_14404.x, 1.0 - _14404.y) / _14149) - vec2(0.5);
                        highp vec2 _14417 = floor(_14415);
                        highp vec2 _14420 = _14415 - _14417;
                        highp vec2 _14425 = (_14417 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14435 = vec2((1.0 + _14425.x) * _13788, _14425.y);
                        highp float _14488 = _14420.x;
                        highp vec2 _14529 = clamp(_12159 + (vec2(0.707099974155426025390625) * _20306), _14149, _14153);
                        highp vec2 _14540 = (vec2(_14529.x, 1.0 - _14529.y) / _14149) - vec2(0.5);
                        highp vec2 _14542 = floor(_14540);
                        highp vec2 _14545 = _14540 - _14542;
                        highp vec2 _14550 = (_14542 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _14560 = vec2((1.0 + _14550.x) * _13788, _14550.y);
                        highp float _14613 = _14545.x;
                        highp float _13917 = ((mix(mix(float(_13782 <= texture(shadow_map, _14185).x), float(_13782 <= texture(shadow_map, _14185 + _14201).x), _14238), mix(float(_13782 <= texture(shadow_map, _14185 + _14209).x), float(_13782 <= texture(shadow_map, _14185 + _14192).x), _14238), _14170.y) + mix(mix(float(_13782 <= texture(shadow_map, _14310).x), float(_13782 <= texture(shadow_map, _14310 + _14201).x), _14363), mix(float(_13782 <= texture(shadow_map, _14310 + _14209).x), float(_13782 <= texture(shadow_map, _14310 + _14192).x), _14363), _14295.y)) + mix(mix(float(_13782 <= texture(shadow_map, _14435).x), float(_13782 <= texture(shadow_map, _14435 + _14201).x), _14488), mix(float(_13782 <= texture(shadow_map, _14435 + _14209).x), float(_13782 <= texture(shadow_map, _14435 + _14192).x), _14488), _14420.y)) + mix(mix(float(_13782 <= texture(shadow_map, _14560).x), float(_13782 <= texture(shadow_map, _14560 + _14201).x), _14613), mix(float(_13782 <= texture(shadow_map, _14560 + _14209).x), float(_13782 <= texture(shadow_map, _14560 + _14192).x), _14613), _14545.y);
                        _20313 = _13917 * 0.25;
                    }
                    else
                    {
                        int _13923 = (_13796 > 0.5) ? 17 : 16;
                        highp float _20309 = 0.0;
                        _20309 = 0.0;
                        highp float _13951 = 0.0;
                        for (int _20299 = 0; _20299 < 17; _20309 = _13951, _20299++)
                        {
                            if (_20299 >= _13923)
                            {
                                break;
                            }
                            highp vec2 _20300 = vec2(0.0);
                            do
                            {
                                if (_20299 == 0)
                                {
                                    _20300 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20299 == 1)
                                {
                                    _20300 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20299 == 2)
                                {
                                    _20300 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20299 == 3)
                                {
                                    _20300 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20299 == 4)
                                {
                                    _20300 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20299 == 5)
                                {
                                    _20300 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20299 == 6)
                                {
                                    _20300 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20299 == 7)
                                {
                                    _20300 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20299 == 8)
                                {
                                    _20300 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20299 == 9)
                                {
                                    _20300 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20299 == 10)
                                {
                                    _20300 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20299 == 11)
                                {
                                    _20300 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20299 == 12)
                                {
                                    _20300 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20299 == 13)
                                {
                                    _20300 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20299 == 14)
                                {
                                    _20300 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20299 == 15)
                                {
                                    _20300 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _20300 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _20302 = vec2(0.0);
                            do
                            {
                                if (_20299 < 3)
                                {
                                    _20302 = vec2(float(_20299) - 1.0, -1.0);
                                    break;
                                }
                                if (_20299 < 6)
                                {
                                    _20302 = vec2((float(_20299 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_20299 < 11)
                                {
                                    _20302 = vec2((float(_20299 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_20299 < 14)
                                {
                                    _20302 = vec2((float(_20299 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _20302 = vec2(float(_20299 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            highp vec2 _13940 = mix(_20300, _20302, vec2(_13796));
                            highp float _14751 = _13940.x;
                            highp float _14755 = _13940.y;
                            highp vec2 _14781 = clamp(_12159 + (vec2((_14751 * _13809) - (_14755 * _13811), (_14751 * _13811) + (_14755 * _13809)) * _20306), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _14790 = _14781.y;
                            highp vec2 _14791 = vec2((1.0 + _14781.x) * _13788, _14790);
                            _14791.y = 1.0 - _14790;
                            _13951 = _20309 + float(_13782 <= texture(shadow_map, _14791).x);
                        }
                        _20313 = _20309 / float(_13923);
                    }
                    bool _13964 = 1 == (_12019 - 1);
                    bool _13970 = false;
                    if (_13964)
                    {
                        _13970 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _13970 = _13964;
                    }
                    highp float _20314 = 0.0;
                    if (_13970)
                    {
                        highp vec2 _13977 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                        highp vec2 _13985 = smoothstep(vec2(0.0), _13977, _12159) * smoothstep(vec2(0.0), _13977, _13668);
                        _20314 = mix(1.0, _20313, _13985.x * _13985.y);
                    }
                    else
                    {
                        _20314 = _20313;
                    }
                    _20386 = _20325 + (_12219 * _20314);
                    _20346 = _20285 + _12219;
                }
                else
                {
                    _20386 = _20325;
                    _20346 = _20285;
                }
                _20385 = _20386;
                _20345 = _20346;
            }
            else
            {
                _20385 = _20325;
                _20345 = _20285;
            }
            _20384 = _20385;
            _20344 = _20345;
        }
        else
        {
            _20384 = _20325;
            _20344 = _20285;
        }
        highp float _20403 = 0.0;
        highp float _20443 = 0.0;
        if ((_20344 < 1.0) && (_12019 > 2))
        {
            highp vec4 _12254 = frag_info.light_space_matrix[2] * vec4(_12491, 1.0);
            highp vec3 _12260 = _12254.xyz / vec3(_12254.w);
            highp vec2 _12263 = _12260.xy * 0.5;
            highp vec2 _12265 = _12263 + vec2(0.5);
            highp float _12272 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
            highp float _12274 = _12265.x;
            bool _12276 = _12274 < _12272;
            bool _12285 = false;
            if (!_12276)
            {
                _12285 = _12274 > (1.0 - _12272);
            }
            else
            {
                _12285 = _12276;
            }
            bool _12293 = false;
            if (!_12285)
            {
                _12293 = _12265.y < _12272;
            }
            else
            {
                _12293 = _12285;
            }
            bool _12302 = false;
            if (!_12293)
            {
                _12302 = _12265.y > (1.0 - _12272);
            }
            else
            {
                _12302 = _12293;
            }
            bool _12309 = false;
            if (!_12302)
            {
                _12309 = _12260.z < 0.0;
            }
            else
            {
                _12309 = _12302;
            }
            bool _12316 = false;
            if (!_12309)
            {
                _12316 = _12260.z > 1.0;
            }
            else
            {
                _12316 = _12309;
            }
            highp float _20404 = 0.0;
            highp float _20444 = 0.0;
            if (!_12316)
            {
                highp vec2 _14811 = vec2(_12272);
                highp vec2 _14816 = vec2(_12272 + max(_12025, 9.9999997473787516355514526367188e-05));
                highp vec2 _14824 = vec2(0.5) - _12263;
                highp vec2 _14826 = smoothstep(_14811, _14816, _12265) * smoothstep(_14811, _14816, _14824);
                highp float _20347 = 0.0;
                if (_12025 > 0.0)
                {
                    _20347 = _14826.x * _14826.y;
                }
                else
                {
                    _20347 = 1.0;
                }
                highp float _12325 = min(_20347, 1.0 - _20344);
                highp float _20405 = 0.0;
                highp float _20445 = 0.0;
                if (_12325 > 0.0)
                {
                    highp float _14938 = _12260.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                    highp float _14944 = 1.0 / (float(_12019) + frag_info.spot_shadow_params.x);
                    highp float _14952 = step(0.5, frag_info.directional_light_direction.w) * (1.0 - step(1.5, frag_info.directional_light_direction.w));
                    highp float _14963 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14952);
                    highp float _14965 = cos(_14963);
                    highp float _14967 = sin(_14963);
                    highp float _20365 = 0.0;
                    if ((frag_info.directional_light_direction.w > 1.5) && (frag_info.directional_light_direction.w < 2.5))
                    {
                        highp float _14986 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _14991 = max(_14986 * _14938, frag_info.shadow_texel_size);
                        highp float _20355 = 0.0;
                        highp float _20356 = 0.0;
                        _20356 = 0.0;
                        _20355 = 0.0;
                        highp float _15013 = 0.0;
                        highp float _15016 = 0.0;
                        for (int _20354 = 0; _20354 < 9; _20356 = _15013, _20355 = _15016, _20354++)
                        {
                            highp vec2 _21195 = vec2(0.0);
                            do
                            {
                                if (_20354 == 0)
                                {
                                    _21195 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20354 == 1)
                                {
                                    _21195 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20354 == 2)
                                {
                                    _21195 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20354 == 3)
                                {
                                    _21195 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20354 == 4)
                                {
                                    _21195 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20354 == 5)
                                {
                                    _21195 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20354 == 6)
                                {
                                    _21195 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20354 == 7)
                                {
                                    _21195 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20354 == 8)
                                {
                                    _21195 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20354 == 9)
                                {
                                    _21195 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20354 == 10)
                                {
                                    _21195 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20354 == 11)
                                {
                                    _21195 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20354 == 12)
                                {
                                    _21195 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20354 == 13)
                                {
                                    _21195 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20354 == 14)
                                {
                                    _21195 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20354 == 15)
                                {
                                    _21195 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21195 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _15259 = clamp(_12265 + (vec2((_21195.x * _14965) - (_21195.y * _14967), (_21195.x * _14967) + (_21195.y * _14965)) * _14991), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _15268 = _15259.y;
                            highp vec2 _15269 = vec2((2.0 + _15259.x) * _14944, _15268);
                            _15269.y = 1.0 - _15268;
                            vec4 _15276 = texture(shadow_map, _15269);
                            float _15277 = _15276.x;
                            highp float _15008 = step(_15277, _14938);
                            _15013 = _20356 + (_15277 * _15008);
                            _15016 = _20355 + _15008;
                        }
                        highp float _20357 = 0.0;
                        if (_20355 > 0.0)
                        {
                            _20357 = _20356 / _20355;
                        }
                        else
                        {
                            _20357 = _14938;
                        }
                        _20365 = clamp(_14986 * max(_14938 - _20357, 0.0), frag_info.shadow_texel_size, _12272);
                    }
                    else
                    {
                        _20365 = _12272;
                    }
                    highp float _20372 = 0.0;
                    if (frag_info.directional_light_direction.w > 2.5)
                    {
                        highp vec2 _15305 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _15309 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _15310 = clamp(_12265 + (vec2(-0.707099974155426025390625) * _20365), _15305, _15309);
                        highp vec2 _15321 = (vec2(_15310.x, 1.0 - _15310.y) / _15305) - vec2(0.5);
                        highp vec2 _15323 = floor(_15321);
                        highp vec2 _15326 = _15321 - _15323;
                        highp vec2 _15331 = (_15323 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15341 = vec2((2.0 + _15331.x) * _14944, _15331.y);
                        highp float _15345 = frag_info.shadow_texel_size * _14944;
                        highp vec2 _15348 = vec2(_15345, frag_info.shadow_texel_size);
                        highp vec2 _15357 = vec2(_15345, 0.0);
                        highp vec2 _15365 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _15394 = _15326.x;
                        highp vec2 _15435 = clamp(_12265 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _20365), _15305, _15309);
                        highp vec2 _15446 = (vec2(_15435.x, 1.0 - _15435.y) / _15305) - vec2(0.5);
                        highp vec2 _15448 = floor(_15446);
                        highp vec2 _15451 = _15446 - _15448;
                        highp vec2 _15456 = (_15448 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15466 = vec2((2.0 + _15456.x) * _14944, _15456.y);
                        highp float _15519 = _15451.x;
                        highp vec2 _15560 = clamp(_12265 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _20365), _15305, _15309);
                        highp vec2 _15571 = (vec2(_15560.x, 1.0 - _15560.y) / _15305) - vec2(0.5);
                        highp vec2 _15573 = floor(_15571);
                        highp vec2 _15576 = _15571 - _15573;
                        highp vec2 _15581 = (_15573 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15591 = vec2((2.0 + _15581.x) * _14944, _15581.y);
                        highp float _15644 = _15576.x;
                        highp vec2 _15685 = clamp(_12265 + (vec2(0.707099974155426025390625) * _20365), _15305, _15309);
                        highp vec2 _15696 = (vec2(_15685.x, 1.0 - _15685.y) / _15305) - vec2(0.5);
                        highp vec2 _15698 = floor(_15696);
                        highp vec2 _15701 = _15696 - _15698;
                        highp vec2 _15706 = (_15698 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _15716 = vec2((2.0 + _15706.x) * _14944, _15706.y);
                        highp float _15769 = _15701.x;
                        highp float _15073 = ((mix(mix(float(_14938 <= texture(shadow_map, _15341).x), float(_14938 <= texture(shadow_map, _15341 + _15357).x), _15394), mix(float(_14938 <= texture(shadow_map, _15341 + _15365).x), float(_14938 <= texture(shadow_map, _15341 + _15348).x), _15394), _15326.y) + mix(mix(float(_14938 <= texture(shadow_map, _15466).x), float(_14938 <= texture(shadow_map, _15466 + _15357).x), _15519), mix(float(_14938 <= texture(shadow_map, _15466 + _15365).x), float(_14938 <= texture(shadow_map, _15466 + _15348).x), _15519), _15451.y)) + mix(mix(float(_14938 <= texture(shadow_map, _15591).x), float(_14938 <= texture(shadow_map, _15591 + _15357).x), _15644), mix(float(_14938 <= texture(shadow_map, _15591 + _15365).x), float(_14938 <= texture(shadow_map, _15591 + _15348).x), _15644), _15576.y)) + mix(mix(float(_14938 <= texture(shadow_map, _15716).x), float(_14938 <= texture(shadow_map, _15716 + _15357).x), _15769), mix(float(_14938 <= texture(shadow_map, _15716 + _15365).x), float(_14938 <= texture(shadow_map, _15716 + _15348).x), _15769), _15701.y);
                        _20372 = _15073 * 0.25;
                    }
                    else
                    {
                        int _15079 = (_14952 > 0.5) ? 17 : 16;
                        highp float _20368 = 0.0;
                        _20368 = 0.0;
                        highp float _15107 = 0.0;
                        for (int _20358 = 0; _20358 < 17; _20368 = _15107, _20358++)
                        {
                            if (_20358 >= _15079)
                            {
                                break;
                            }
                            highp vec2 _20359 = vec2(0.0);
                            do
                            {
                                if (_20358 == 0)
                                {
                                    _20359 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20358 == 1)
                                {
                                    _20359 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20358 == 2)
                                {
                                    _20359 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20358 == 3)
                                {
                                    _20359 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20358 == 4)
                                {
                                    _20359 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20358 == 5)
                                {
                                    _20359 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20358 == 6)
                                {
                                    _20359 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20358 == 7)
                                {
                                    _20359 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20358 == 8)
                                {
                                    _20359 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20358 == 9)
                                {
                                    _20359 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20358 == 10)
                                {
                                    _20359 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20358 == 11)
                                {
                                    _20359 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20358 == 12)
                                {
                                    _20359 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20358 == 13)
                                {
                                    _20359 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20358 == 14)
                                {
                                    _20359 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20358 == 15)
                                {
                                    _20359 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _20359 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _20361 = vec2(0.0);
                            do
                            {
                                if (_20358 < 3)
                                {
                                    _20361 = vec2(float(_20358) - 1.0, -1.0);
                                    break;
                                }
                                if (_20358 < 6)
                                {
                                    _20361 = vec2((float(_20358 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_20358 < 11)
                                {
                                    _20361 = vec2((float(_20358 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_20358 < 14)
                                {
                                    _20361 = vec2((float(_20358 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _20361 = vec2(float(_20358 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            highp vec2 _15096 = mix(_20359, _20361, vec2(_14952));
                            highp float _15907 = _15096.x;
                            highp float _15911 = _15096.y;
                            highp vec2 _15937 = clamp(_12265 + (vec2((_15907 * _14965) - (_15911 * _14967), (_15907 * _14967) + (_15911 * _14965)) * _20365), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _15946 = _15937.y;
                            highp vec2 _15947 = vec2((2.0 + _15937.x) * _14944, _15946);
                            _15947.y = 1.0 - _15946;
                            _15107 = _20368 + float(_14938 <= texture(shadow_map, _15947).x);
                        }
                        _20372 = _20368 / float(_15079);
                    }
                    bool _15120 = 2 == (_12019 - 1);
                    bool _15126 = false;
                    if (_15120)
                    {
                        _15126 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _15126 = _15120;
                    }
                    highp float _20373 = 0.0;
                    if (_15126)
                    {
                        highp vec2 _15133 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                        highp vec2 _15141 = smoothstep(vec2(0.0), _15133, _12265) * smoothstep(vec2(0.0), _15133, _14824);
                        _20373 = mix(1.0, _20372, _15141.x * _15141.y);
                    }
                    else
                    {
                        _20373 = _20372;
                    }
                    _20445 = _20384 + (_12325 * _20373);
                    _20405 = _20344 + _12325;
                }
                else
                {
                    _20445 = _20384;
                    _20405 = _20344;
                }
                _20444 = _20445;
                _20404 = _20405;
            }
            else
            {
                _20444 = _20384;
                _20404 = _20344;
            }
            _20443 = _20444;
            _20403 = _20404;
        }
        else
        {
            _20443 = _20384;
            _20403 = _20344;
        }
        highp float _20462 = 0.0;
        highp float _20465 = 0.0;
        if ((_20403 < 1.0) && (_12019 > 3))
        {
            highp vec4 _12360 = frag_info.light_space_matrix[3] * vec4(_12491, 1.0);
            highp vec3 _12366 = _12360.xyz / vec3(_12360.w);
            highp vec2 _12369 = _12366.xy * 0.5;
            highp vec2 _12371 = _12369 + vec2(0.5);
            highp float _12378 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
            highp float _12380 = _12371.x;
            bool _12382 = _12380 < _12378;
            bool _12391 = false;
            if (!_12382)
            {
                _12391 = _12380 > (1.0 - _12378);
            }
            else
            {
                _12391 = _12382;
            }
            bool _12399 = false;
            if (!_12391)
            {
                _12399 = _12371.y < _12378;
            }
            else
            {
                _12399 = _12391;
            }
            bool _12408 = false;
            if (!_12399)
            {
                _12408 = _12371.y > (1.0 - _12378);
            }
            else
            {
                _12408 = _12399;
            }
            bool _12415 = false;
            if (!_12408)
            {
                _12415 = _12366.z < 0.0;
            }
            else
            {
                _12415 = _12408;
            }
            bool _12422 = false;
            if (!_12415)
            {
                _12422 = _12366.z > 1.0;
            }
            else
            {
                _12422 = _12415;
            }
            highp float _20463 = 0.0;
            highp float _20466 = 0.0;
            if (!_12422)
            {
                highp vec2 _15967 = vec2(_12378);
                highp vec2 _15972 = vec2(_12378 + max(_12025, 9.9999997473787516355514526367188e-05));
                highp vec2 _15980 = vec2(0.5) - _12369;
                highp vec2 _15982 = smoothstep(_15967, _15972, _12371) * smoothstep(_15967, _15972, _15980);
                highp float _20406 = 0.0;
                if (_12025 > 0.0)
                {
                    _20406 = _15982.x * _15982.y;
                }
                else
                {
                    _20406 = 1.0;
                }
                highp float _12431 = min(_20406, 1.0 - _20403);
                highp float _20464 = 0.0;
                highp float _20467 = 0.0;
                if (_12431 > 0.0)
                {
                    highp float _16094 = _12366.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                    highp float _16100 = 1.0 / (float(_12019) + frag_info.spot_shadow_params.x);
                    highp float _16108 = step(0.5, frag_info.directional_light_direction.w) * (1.0 - step(1.5, frag_info.directional_light_direction.w));
                    highp float _16119 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16108);
                    highp float _16121 = cos(_16119);
                    highp float _16123 = sin(_16119);
                    highp float _20424 = 0.0;
                    if ((frag_info.directional_light_direction.w > 1.5) && (frag_info.directional_light_direction.w < 2.5))
                    {
                        highp float _16142 = tan(frag_info.camera_right.w) * 7.0;
                        highp float _16147 = max(_16142 * _16094, frag_info.shadow_texel_size);
                        highp float _20414 = 0.0;
                        highp float _20415 = 0.0;
                        _20415 = 0.0;
                        _20414 = 0.0;
                        highp float _16169 = 0.0;
                        highp float _16172 = 0.0;
                        for (int _20413 = 0; _20413 < 9; _20415 = _16169, _20414 = _16172, _20413++)
                        {
                            highp vec2 _21191 = vec2(0.0);
                            do
                            {
                                if (_20413 == 0)
                                {
                                    _21191 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20413 == 1)
                                {
                                    _21191 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20413 == 2)
                                {
                                    _21191 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20413 == 3)
                                {
                                    _21191 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20413 == 4)
                                {
                                    _21191 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20413 == 5)
                                {
                                    _21191 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20413 == 6)
                                {
                                    _21191 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20413 == 7)
                                {
                                    _21191 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20413 == 8)
                                {
                                    _21191 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20413 == 9)
                                {
                                    _21191 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20413 == 10)
                                {
                                    _21191 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20413 == 11)
                                {
                                    _21191 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20413 == 12)
                                {
                                    _21191 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20413 == 13)
                                {
                                    _21191 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20413 == 14)
                                {
                                    _21191 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20413 == 15)
                                {
                                    _21191 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _21191 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _16415 = clamp(_12371 + (vec2((_21191.x * _16121) - (_21191.y * _16123), (_21191.x * _16123) + (_21191.y * _16121)) * _16147), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _16424 = _16415.y;
                            highp vec2 _16425 = vec2((3.0 + _16415.x) * _16100, _16424);
                            _16425.y = 1.0 - _16424;
                            vec4 _16432 = texture(shadow_map, _16425);
                            float _16433 = _16432.x;
                            highp float _16164 = step(_16433, _16094);
                            _16169 = _20415 + (_16433 * _16164);
                            _16172 = _20414 + _16164;
                        }
                        highp float _20416 = 0.0;
                        if (_20414 > 0.0)
                        {
                            _20416 = _20415 / _20414;
                        }
                        else
                        {
                            _20416 = _16094;
                        }
                        _20424 = clamp(_16142 * max(_16094 - _20416, 0.0), frag_info.shadow_texel_size, _12378);
                    }
                    else
                    {
                        _20424 = _12378;
                    }
                    highp float _20431 = 0.0;
                    if (frag_info.directional_light_direction.w > 2.5)
                    {
                        highp vec2 _16461 = vec2(frag_info.shadow_texel_size);
                        highp vec2 _16465 = vec2(1.0 - frag_info.shadow_texel_size);
                        highp vec2 _16466 = clamp(_12371 + (vec2(-0.707099974155426025390625) * _20424), _16461, _16465);
                        highp vec2 _16477 = (vec2(_16466.x, 1.0 - _16466.y) / _16461) - vec2(0.5);
                        highp vec2 _16479 = floor(_16477);
                        highp vec2 _16482 = _16477 - _16479;
                        highp vec2 _16487 = (_16479 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16497 = vec2((3.0 + _16487.x) * _16100, _16487.y);
                        highp float _16501 = frag_info.shadow_texel_size * _16100;
                        highp vec2 _16504 = vec2(_16501, frag_info.shadow_texel_size);
                        highp vec2 _16513 = vec2(_16501, 0.0);
                        highp vec2 _16521 = vec2(0.0, frag_info.shadow_texel_size);
                        highp float _16550 = _16482.x;
                        highp vec2 _16591 = clamp(_12371 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _20424), _16461, _16465);
                        highp vec2 _16602 = (vec2(_16591.x, 1.0 - _16591.y) / _16461) - vec2(0.5);
                        highp vec2 _16604 = floor(_16602);
                        highp vec2 _16607 = _16602 - _16604;
                        highp vec2 _16612 = (_16604 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16622 = vec2((3.0 + _16612.x) * _16100, _16612.y);
                        highp float _16675 = _16607.x;
                        highp vec2 _16716 = clamp(_12371 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _20424), _16461, _16465);
                        highp vec2 _16727 = (vec2(_16716.x, 1.0 - _16716.y) / _16461) - vec2(0.5);
                        highp vec2 _16729 = floor(_16727);
                        highp vec2 _16732 = _16727 - _16729;
                        highp vec2 _16737 = (_16729 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16747 = vec2((3.0 + _16737.x) * _16100, _16737.y);
                        highp float _16800 = _16732.x;
                        highp vec2 _16841 = clamp(_12371 + (vec2(0.707099974155426025390625) * _20424), _16461, _16465);
                        highp vec2 _16852 = (vec2(_16841.x, 1.0 - _16841.y) / _16461) - vec2(0.5);
                        highp vec2 _16854 = floor(_16852);
                        highp vec2 _16857 = _16852 - _16854;
                        highp vec2 _16862 = (_16854 + vec2(0.5)) * frag_info.shadow_texel_size;
                        highp vec2 _16872 = vec2((3.0 + _16862.x) * _16100, _16862.y);
                        highp float _16925 = _16857.x;
                        highp float _16229 = ((mix(mix(float(_16094 <= texture(shadow_map, _16497).x), float(_16094 <= texture(shadow_map, _16497 + _16513).x), _16550), mix(float(_16094 <= texture(shadow_map, _16497 + _16521).x), float(_16094 <= texture(shadow_map, _16497 + _16504).x), _16550), _16482.y) + mix(mix(float(_16094 <= texture(shadow_map, _16622).x), float(_16094 <= texture(shadow_map, _16622 + _16513).x), _16675), mix(float(_16094 <= texture(shadow_map, _16622 + _16521).x), float(_16094 <= texture(shadow_map, _16622 + _16504).x), _16675), _16607.y)) + mix(mix(float(_16094 <= texture(shadow_map, _16747).x), float(_16094 <= texture(shadow_map, _16747 + _16513).x), _16800), mix(float(_16094 <= texture(shadow_map, _16747 + _16521).x), float(_16094 <= texture(shadow_map, _16747 + _16504).x), _16800), _16732.y)) + mix(mix(float(_16094 <= texture(shadow_map, _16872).x), float(_16094 <= texture(shadow_map, _16872 + _16513).x), _16925), mix(float(_16094 <= texture(shadow_map, _16872 + _16521).x), float(_16094 <= texture(shadow_map, _16872 + _16504).x), _16925), _16857.y);
                        _20431 = _16229 * 0.25;
                    }
                    else
                    {
                        int _16235 = (_16108 > 0.5) ? 17 : 16;
                        highp float _20427 = 0.0;
                        _20427 = 0.0;
                        highp float _16263 = 0.0;
                        for (int _20417 = 0; _20417 < 17; _20427 = _16263, _20417++)
                        {
                            if (_20417 >= _16235)
                            {
                                break;
                            }
                            highp vec2 _20418 = vec2(0.0);
                            do
                            {
                                if (_20417 == 0)
                                {
                                    _20418 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                    break;
                                }
                                if (_20417 == 1)
                                {
                                    _20418 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                    break;
                                }
                                if (_20417 == 2)
                                {
                                    _20418 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                    break;
                                }
                                if (_20417 == 3)
                                {
                                    _20418 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                    break;
                                }
                                if (_20417 == 4)
                                {
                                    _20418 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                    break;
                                }
                                if (_20417 == 5)
                                {
                                    _20418 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                    break;
                                }
                                if (_20417 == 6)
                                {
                                    _20418 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                    break;
                                }
                                if (_20417 == 7)
                                {
                                    _20418 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                    break;
                                }
                                if (_20417 == 8)
                                {
                                    _20418 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                    break;
                                }
                                if (_20417 == 9)
                                {
                                    _20418 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                    break;
                                }
                                if (_20417 == 10)
                                {
                                    _20418 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                    break;
                                }
                                if (_20417 == 11)
                                {
                                    _20418 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                    break;
                                }
                                if (_20417 == 12)
                                {
                                    _20418 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                    break;
                                }
                                if (_20417 == 13)
                                {
                                    _20418 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                    break;
                                }
                                if (_20417 == 14)
                                {
                                    _20418 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                    break;
                                }
                                if (_20417 == 15)
                                {
                                    _20418 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                    break;
                                }
                                _20418 = vec2(0.0);
                                break;
                            } while(false);
                            highp vec2 _20420 = vec2(0.0);
                            do
                            {
                                if (_20417 < 3)
                                {
                                    _20420 = vec2(float(_20417) - 1.0, -1.0);
                                    break;
                                }
                                if (_20417 < 6)
                                {
                                    _20420 = vec2((float(_20417 - 3) * 0.5) - 0.5, -0.5);
                                    break;
                                }
                                if (_20417 < 11)
                                {
                                    _20420 = vec2((float(_20417 - 6) * 0.5) - 1.0, 0.0);
                                    break;
                                }
                                if (_20417 < 14)
                                {
                                    _20420 = vec2((float(_20417 - 11) * 0.5) - 0.5, 0.5);
                                    break;
                                }
                                _20420 = vec2(float(_20417 - 14) - 1.0, 1.0);
                                break;
                            } while(false);
                            highp vec2 _16252 = mix(_20418, _20420, vec2(_16108));
                            highp float _17063 = _16252.x;
                            highp float _17067 = _16252.y;
                            highp vec2 _17093 = clamp(_12371 + (vec2((_17063 * _16121) - (_17067 * _16123), (_17063 * _16123) + (_17067 * _16121)) * _20424), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                            highp float _17102 = _17093.y;
                            highp vec2 _17103 = vec2((3.0 + _17093.x) * _16100, _17102);
                            _17103.y = 1.0 - _17102;
                            _16263 = _20427 + float(_16094 <= texture(shadow_map, _17103).x);
                        }
                        _20431 = _20427 / float(_16235);
                    }
                    bool _16276 = 3 == (_12019 - 1);
                    bool _16282 = false;
                    if (_16276)
                    {
                        _16282 = frag_info.shadow_fade > 0.0;
                    }
                    else
                    {
                        _16282 = _16276;
                    }
                    highp float _20432 = 0.0;
                    if (_16282)
                    {
                        highp vec2 _16289 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                        highp vec2 _16297 = smoothstep(vec2(0.0), _16289, _12371) * smoothstep(vec2(0.0), _16289, _15980);
                        _20432 = mix(1.0, _20431, _16297.x * _16297.y);
                    }
                    else
                    {
                        _20432 = _20431;
                    }
                    _20467 = _20403 + _12431;
                    _20464 = _20443 + (_12431 * _20432);
                }
                else
                {
                    _20467 = _20403;
                    _20464 = _20443;
                }
                _20466 = _20467;
                _20463 = _20464;
            }
            else
            {
                _20466 = _20403;
                _20463 = _20443;
            }
            _20465 = _20466;
            _20462 = _20463;
        }
        else
        {
            _20465 = _20403;
            _20462 = _20443;
        }
        _20468 = _20462 + (1.0 - _20465);
    }
    else
    {
        _20468 = 1.0;
    }
    bool _6672 = frag_info.ssao_lighting.w > 0.5;
    bool _6678 = false;
    if (_6672)
    {
        _6678 = frag_info.camera_up.w < 0.5;
    }
    else
    {
        _6678 = _6672;
    }
    highp float _20618 = 0.0;
    if (_6678)
    {
        _20618 = min(_20468, _20484.y);
    }
    else
    {
        _20618 = _20468;
    }
    highp float _6687 = _6650 * _20618;
    highp vec3 _6700 = ((((_6584 + (_6588 * ((vec3(1.0) - _6560) + _6584))) * _20040) * _20634) + (((_6560 * (_19848 * frag_info.environment_intensity)) * 1.0) * _20775)) * mix(1.0, _6687, frag_info.radiance_blend.y);
    highp vec3 _21149 = vec3(0.0);
    if (frag_info.camera_up.w > 0.5)
    {
        _21149 = _6700 + ((_20484.xyz * _6588) * _5533);
    }
    else
    {
        _21149 = _6700;
    }
    highp vec3 _20971 = vec3(0.0);
    if (_6637)
    {
        highp vec3 _20935 = vec3(0.0);
        do
        {
            highp float _17145 = max(dot(_19789, _20859), 0.0);
            if (_17145 <= 0.0)
            {
                _20935 = vec3(0.0);
                break;
            }
            highp float _17151 = max(_6457, 9.9999997473787516355514526367188e-05);
            highp vec3 _17154 = _20859 + _6445;
            highp float _17157 = dot(_17154, _17154);
            highp vec3 _20933 = vec3(0.0);
            highp vec3 _20934 = vec3(0.0);
            if (_17157 > 9.9999999392252902907785028219223e-09)
            {
                highp vec3 _17165 = _17154 * inversesqrt(_17157);
                highp float _20932 = 0.0;
                do
                {
                    highp float _17218 = dot(_19789, _17165);
                    if (_17218 <= 0.0)
                    {
                        _20932 = 0.0;
                        break;
                    }
                    highp float _17225 = _19825 * _19825;
                    highp vec3 _17228 = cross(_19789, _17165);
                    highp float _17231 = _17218 * _17225;
                    highp float _17240 = _17225 / (dot(_17228, _17228) + (_17231 * _17231));
                    _20932 = (_17240 * _17240) * 0.3183098733425140380859375;
                    break;
                } while(false);
                highp vec3 _17277 = _6453 + (_6570 * pow(clamp(1.0 - max(dot(_17165, _6445), 0.0), 0.0, 1.0), 5.0));
                _20934 = (_17277 * (_20932 * (0.5 / max(mix((2.0 * _17145) * _17151, _17145 + _17151, _19825 * _19825), 9.9999997473787516355514526367188e-06)))) * 1.0;
                _20933 = _17277;
            }
            else
            {
                _20934 = vec3(0.0);
                _20933 = _6453;
            }
            _20935 = ((((((vec3(1.0) - _20933) * _6587) * _6357) * 0.3183098733425140380859375) + _20934) * frag_info.directional_light_color.xyz) * _17145;
            break;
        } while(false);
        _20971 = _20935 * _6687;
    }
    else
    {
        _20971 = vec3(0.0);
    }
    int _20936 = 0;
    if (frag_info.punctual_dims.x < 0.5)
    {
        _20936 = 0;
    }
    else
    {
        _20936 = int(frag_info.radiance_blend.z);
    }
    int _6751 = int(frag_info.radiance_blend.w);
    highp vec3 _20969 = vec3(0.0);
    _20969 = _20971;
    highp vec3 _21231 = vec3(0.0);
    for (int _20937 = 0; _20937 < 16; _20969 = _21231, _20937++)
    {
        if (_20937 >= _20936)
        {
            break;
        }
        highp float _17287 = float(_6751 + _20937);
        float _17306 = texture(punctual_index, vec2((mod(_17287, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_17287 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z)).x;
        highp float hp_copy_17306 = _17306;
        highp float _17321 = (float(int(hp_copy_17306 + 0.5)) + 0.5) / frag_info.punctual_dims.x;
        vec4 _17325 = texture(punctual_lights, vec2(0.0625, _17321));
        vec4 _17344 = texture(punctual_lights, vec2(0.1875, _17321));
        float _6773 = _17325.w;
        vec3 _6775 = _17344.xyz;
        if (_6773 > 2.5)
        {
            vec4 _17363 = texture(punctual_lights, vec2(0.3125, _17321));
            vec4 _17382 = texture(punctual_lights, vec2(0.4375, _17321));
            float _6786 = _17363.w;
            highp float hp_copy_6786 = _6786;
            highp vec3 _6788 = _17363.xyz * (hp_copy_6786 * 0.5);
            float _6792 = _17382.w;
            highp float hp_copy_6792 = _6792;
            highp vec3 _6794 = _17382.xyz * (hp_copy_6792 * 0.5);
            vec3 _6796 = _17325.xyz;
            highp vec3 _6798 = _6796 - _6788;
            highp vec3 _6800 = _6798 - _6794;
            highp vec3 _6804 = _6796 + _6788;
            highp vec3 _6806 = _6804 - _6794;
            highp vec3 _6818 = _6798 + _6794;
            highp vec3 _6822 = _6796 - v_position;
            float _6828 = _17344.w;
            highp float _6832 = (dot(_6822, _6822) * _6828) * _6828;
            highp float _6837 = clamp(1.0 - (_6832 * _6832), 0.0, 1.0);
            highp vec2 _17390 = (clamp(vec2(_19825, sqrt(1.0 - _6457)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
            highp float _17392 = _17390.x;
            highp float _17397 = _17390.y;
            vec4 _6861 = texture(brdf_lut, vec2((_17392 + 1.0) * 0.3333333432674407958984375, _17397));
            vec4 _6865 = texture(brdf_lut, vec2((_17392 + 2.0) * 0.3333333432674407958984375, _17397));
            highp vec3 _17440 = normalize(_6445 - (_19789 * _6456));
            highp mat3 _17462 = transpose(mat3(_17440, -cross(_19789, _17440), _19789));
            highp mat3 _17463 = mat3(vec3(_6861.x, 0.0, _6861.y), vec3(0.0, 1.0, 0.0), vec3(_6861.z, 0.0, _6861.w)) * _17462;
            highp vec3 _17467 = _6800 - v_position;
            highp vec3 _17469 = normalize(_17463 * _17467);
            highp vec3 _17473 = _6806 - v_position;
            highp vec3 _17475 = normalize(_17463 * _17473);
            highp vec3 _17479 = (_6804 + _6794) - v_position;
            highp vec3 _17481 = normalize(_17463 * _17479);
            highp vec3 _17485 = _6818 - v_position;
            highp vec3 _17487 = normalize(_17463 * _17485);
            highp float _17516 = dot(_17469, _17475);
            highp float _17518 = abs(_17516);
            highp float _17532 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17518)) * _17518)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17518) * _17518));
            highp float _20984 = 0.0;
            if (_17516 > 0.0)
            {
                _20984 = _17532;
            }
            else
            {
                _20984 = (0.5 * inversesqrt(max(1.0 - (_17516 * _17516), 1.0000000116860974230803549289703e-07))) - _17532;
            }
            highp float _17565 = dot(_17475, _17481);
            highp float _17567 = abs(_17565);
            highp float _17581 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17567)) * _17567)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17567) * _17567));
            highp float _20985 = 0.0;
            if (_17565 > 0.0)
            {
                _20985 = _17581;
            }
            else
            {
                _20985 = (0.5 * inversesqrt(max(1.0 - (_17565 * _17565), 1.0000000116860974230803549289703e-07))) - _17581;
            }
            highp float _17614 = dot(_17481, _17487);
            highp float _17616 = abs(_17614);
            highp float _17630 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17616)) * _17616)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17616) * _17616));
            highp float _20986 = 0.0;
            if (_17614 > 0.0)
            {
                _20986 = _17630;
            }
            else
            {
                _20986 = (0.5 * inversesqrt(max(1.0 - (_17614 * _17614), 1.0000000116860974230803549289703e-07))) - _17630;
            }
            highp float _17663 = dot(_17487, _17469);
            highp float _17665 = abs(_17663);
            highp float _17679 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17665)) * _17665)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17665) * _17665));
            highp float _20987 = 0.0;
            if (_17663 > 0.0)
            {
                _20987 = _17679;
            }
            else
            {
                _20987 = (0.5 * inversesqrt(max(1.0 - (_17663 * _17663), 1.0000000116860974230803549289703e-07))) - _17679;
            }
            highp vec3 _17502 = (((cross(_17469, _17475) * _20984) + (cross(_17475, _17481) * _20985)) + (cross(_17481, _17487) * _20986)) + (cross(_17487, _17469) * _20987);
            highp float _17705 = length(_17502);
            highp mat3 _17765 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _17462;
            highp vec3 _17771 = normalize(_17765 * _17467);
            highp vec3 _17777 = normalize(_17765 * _17473);
            highp vec3 _17783 = normalize(_17765 * _17479);
            highp vec3 _17789 = normalize(_17765 * _17485);
            highp float _17818 = dot(_17771, _17777);
            highp float _17820 = abs(_17818);
            highp float _17834 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17820)) * _17820)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17820) * _17820));
            highp float _20988 = 0.0;
            if (_17818 > 0.0)
            {
                _20988 = _17834;
            }
            else
            {
                _20988 = (0.5 * inversesqrt(max(1.0 - (_17818 * _17818), 1.0000000116860974230803549289703e-07))) - _17834;
            }
            highp float _17867 = dot(_17777, _17783);
            highp float _17869 = abs(_17867);
            highp float _17883 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17869)) * _17869)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17869) * _17869));
            highp float _20989 = 0.0;
            if (_17867 > 0.0)
            {
                _20989 = _17883;
            }
            else
            {
                _20989 = (0.5 * inversesqrt(max(1.0 - (_17867 * _17867), 1.0000000116860974230803549289703e-07))) - _17883;
            }
            highp float _17916 = dot(_17783, _17789);
            highp float _17918 = abs(_17916);
            highp float _17932 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17918)) * _17918)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17918) * _17918));
            highp float _20990 = 0.0;
            if (_17916 > 0.0)
            {
                _20990 = _17932;
            }
            else
            {
                _20990 = (0.5 * inversesqrt(max(1.0 - (_17916 * _17916), 1.0000000116860974230803549289703e-07))) - _17932;
            }
            highp float _17965 = dot(_17789, _17771);
            highp float _17967 = abs(_17965);
            highp float _17981 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _17967)) * _17967)) / (3.41759395599365234375 + ((4.1616725921630859375 + _17967) * _17967));
            highp float _20991 = 0.0;
            if (_17965 > 0.0)
            {
                _20991 = _17981;
            }
            else
            {
                _20991 = (0.5 * inversesqrt(max(1.0 - (_17965 * _17965), 1.0000000116860974230803549289703e-07))) - _17981;
            }
            highp vec3 _17804 = (((cross(_17771, _17777) * _20988) + (cross(_17777, _17783) * _20989)) + (cross(_17783, _17789) * _20990)) + (cross(_17789, _17771) * _20991);
            highp float _18007 = length(_17804);
            _21231 = _20969 + (((_6775 * (_6837 * _6837)) * step(0.0, dot(cross(_6806 - _6800, _6818 - _6800), v_position - _6800))) * (((((_6453 * _6865.x) + (_6570 * _6865.y)) * max(((_17705 * _17705) + _17502.z) / (_17705 + 1.0), 0.0)) * 1.0) + (_6588 * max(((_18007 * _18007) + _17804.z) / (_18007 + 1.0), 0.0))));
        }
        else
        {
            highp vec3 _20949 = vec3(0.0);
            highp vec3 _20960 = vec3(0.0);
            if (_6773 < 0.5)
            {
                vec3 _6945 = texture(punctual_lights, vec2(0.3125, _17321)).xyz;
                highp vec3 hp_copy_6945 = _6945;
                _20960 = _6775;
                _20949 = -normalize(hp_copy_6945);
            }
            else
            {
                highp vec3 _6952 = _17325.xyz - v_position;
                highp float _6955 = dot(_6952, _6952);
                highp vec3 _6960 = _6952 * inversesqrt(max(_6955, 9.9999999392252902907785028219223e-09));
                float _6962 = _17344.w;
                highp float _6967 = (_6955 * _6962) * _6962;
                highp float _6972 = clamp(1.0 - (_6967 * _6967), 0.0, 1.0);
                vec4 _18054 = texture(punctual_lights, vec2(0.4375, _17321));
                float _6980 = _18054.z;
                highp float hp_copy_6980 = _6980;
                highp vec3 _6986 = _6775 * ((_6972 * _6972) / max(pow(_6955, hp_copy_6980 * 0.5), 9.9999997473787516355514526367188e-05));
                highp vec3 _20961 = vec3(0.0);
                if (_6773 > 1.5)
                {
                    vec4 _18073 = texture(punctual_lights, vec2(0.3125, _17321));
                    vec3 _6993 = _18073.xyz;
                    highp vec3 hp_copy_6993 = _6993;
                    highp float _7005 = clamp((dot(normalize(hp_copy_6993), -_6960) * _18073.w) + _18054.x, 0.0, 1.0);
                    highp vec3 _7010 = _6986 * (_7005 * _7005);
                    float _7012 = _18054.y;
                    highp float hp_copy_7012 = _7012;
                    bool _7013 = _7012 > (-0.5);
                    bool _7019 = false;
                    if (_7013)
                    {
                        _7019 = frag_info.spot_shadow_params.x > 0.5;
                    }
                    else
                    {
                        _7019 = _7013;
                    }
                    highp vec3 _20962 = vec3(0.0);
                    if (_7019)
                    {
                        highp float _20940 = 0.0;
                        do
                        {
                            vec4 _18298 = texture(punctual_lights, vec2(0.5625, _17321));
                            vec4 _18317 = texture(punctual_lights, vec2(0.6875, _17321));
                            vec4 _18336 = texture(punctual_lights, vec2(0.8125, _17321));
                            vec4 _18355 = texture(punctual_lights, vec2(0.9375, _17321));
                            highp vec4 _18159 = mat4(_18298, _18317, _18336, _18355) * vec4(v_position + (_5365 * frag_info.spot_shadow_params.z), 1.0);
                            highp float _18161 = _18159.w;
                            if (_18161 <= 0.0)
                            {
                                _20940 = 1.0;
                                break;
                            }
                            highp vec3 _18170 = _18159.xyz / vec3(_18161);
                            highp vec2 _18175 = (_18170.xy * 0.5) + vec2(0.5);
                            highp float _18177 = _18175.x;
                            bool _18178 = _18177 < 0.0;
                            bool _18185 = false;
                            if (!_18178)
                            {
                                _18185 = _18177 > 1.0;
                            }
                            else
                            {
                                _18185 = _18178;
                            }
                            bool _18192 = false;
                            if (!_18185)
                            {
                                _18192 = _18175.y < 0.0;
                            }
                            else
                            {
                                _18192 = _18185;
                            }
                            bool _18199 = false;
                            if (!_18192)
                            {
                                _18199 = _18175.y > 1.0;
                            }
                            else
                            {
                                _18199 = _18192;
                            }
                            bool _18206 = false;
                            if (!_18199)
                            {
                                _18206 = _18170.z < 0.0;
                            }
                            else
                            {
                                _18206 = _18199;
                            }
                            bool _18213 = false;
                            if (!_18206)
                            {
                                _18213 = _18170.z > 1.0;
                            }
                            else
                            {
                                _18213 = _18206;
                            }
                            if (_18213)
                            {
                                _20940 = 1.0;
                                break;
                            }
                            highp float _18220 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                            highp float _18225 = frag_info.shadow_cascade_count + float(int(hp_copy_7012 + 0.5));
                            highp float _18230 = _18170.z - frag_info.spot_shadow_params.y;
                            highp float _18233 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                            highp float _18246 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                            highp float _20939 = 0.0;
                            _20939 = float(_18230 <= texture(shadow_map, vec2((_18225 + clamp(_18177, 0.0, 1.0)) / _18220, 1.0 - clamp(_18175.y, 0.0, 1.0))).x);
                            for (int _20938 = 0; _20938 < 8; )
                            {
                                highp float _18256 = _18246 + (float(_20938) * 0.785398185253143310546875);
                                highp vec2 _18266 = _18175 + (vec2(cos(_18256), sin(_18256)) * _18233);
                                _20939 += float(_18230 <= texture(shadow_map, vec2((_18225 + clamp(_18266.x, 0.0, 1.0)) / _18220, 1.0 - clamp(_18266.y, 0.0, 1.0))).x);
                                _20938++;
                                continue;
                            }
                            _20940 = _20939 * 0.111111111938953399658203125;
                            break;
                        } while(false);
                        _20962 = _7010 * _20940;
                    }
                    else
                    {
                        _20962 = _7010;
                    }
                    _20961 = _20962;
                }
                else
                {
                    _20961 = _6986;
                }
                _20960 = _20961;
                _20949 = _6960;
            }
            highp vec3 _20966 = vec3(0.0);
            do
            {
                highp float _18430 = max(dot(_19789, _20949), 0.0);
                if (_18430 <= 0.0)
                {
                    _20966 = vec3(0.0);
                    break;
                }
                highp float _18436 = max(_6457, 9.9999997473787516355514526367188e-05);
                highp vec3 _18439 = _20949 + _6445;
                highp float _18442 = dot(_18439, _18439);
                highp vec3 _20964 = vec3(0.0);
                highp vec3 _20965 = vec3(0.0);
                if (_18442 > 9.9999999392252902907785028219223e-09)
                {
                    highp vec3 _18450 = _18439 * inversesqrt(_18442);
                    highp float _20963 = 0.0;
                    do
                    {
                        highp float _18503 = dot(_19789, _18450);
                        if (_18503 <= 0.0)
                        {
                            _20963 = 0.0;
                            break;
                        }
                        highp float _18510 = _19825 * _19825;
                        highp vec3 _18513 = cross(_19789, _18450);
                        highp float _18516 = _18503 * _18510;
                        highp float _18525 = _18510 / (dot(_18513, _18513) + (_18516 * _18516));
                        _20963 = (_18525 * _18525) * 0.3183098733425140380859375;
                        break;
                    } while(false);
                    highp vec3 _18562 = _6453 + (_6570 * pow(clamp(1.0 - max(dot(_18450, _6445), 0.0), 0.0, 1.0), 5.0));
                    _20965 = (_18562 * (_20963 * (0.5 / max(mix((2.0 * _18430) * _18436, _18430 + _18436, _19825 * _19825), 9.9999997473787516355514526367188e-06)))) * 1.0;
                    _20964 = _18562;
                }
                else
                {
                    _20965 = vec3(0.0);
                    _20964 = _6453;
                }
                _20966 = ((((((vec3(1.0) - _20964) * _6587) * _6357) * 0.3183098733425140380859375) + _20965) * _20960) * _18430;
                break;
            } while(false);
            _21231 = _20969 + _20966;
        }
    }
    bool _7075 = _FogInfo.params0.y > 0.5;
    bool _7081 = false;
    if (_7075)
    {
        _7081 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _7081 = _7075;
    }
    highp vec3 _21180 = vec3(0.0);
    if (_7081)
    {
        highp vec3 _7087 = _6478 * normalize(-v_viewvector);
        highp vec3 _21177 = vec3(0.0);
        do
        {
            if (_7563)
            {
                _21177 = textureLod(prefiltered_radiance, (vec2(atan(_7087.z, _7087.x), asin(clamp(_7087.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            highp vec2 _18692 = (vec2(atan(_7087.z, _7087.x), asin(clamp(_7087.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _18597 = clamp(_18692.y, 0.00390625, 0.99609375);
            highp float _18603 = floor(0.0);
            highp float _18622 = _18692.x;
            _21177 = mix(texture(prefiltered_radiance, vec2(_18622, (_18603 + _18597) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_18622, (min(_18603 + 1.0, 7.0) + _18597) * 0.125)).xyz, vec3(-_18603));
            break;
        } while(false);
        highp vec3 _21179 = vec3(0.0);
        if (_6501)
        {
            highp vec3 _21178 = vec3(0.0);
            do
            {
                if (_7563)
                {
                    _21178 = textureLod(prefiltered_radiance_b, (vec2(atan(_7087.z, _7087.x), asin(clamp(_7087.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                highp vec2 _18823 = (vec2(atan(_7087.z, _7087.x), asin(clamp(_7087.y, -1.0, 1.0))) * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _18728 = clamp(_18823.y, 0.00390625, 0.99609375);
                highp float _18734 = floor(0.0);
                highp float _18753 = _18823.x;
                _21178 = mix(texture(prefiltered_radiance_b, vec2(_18753, (_18734 + _18728) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_18753, (min(_18734 + 1.0, 7.0) + _18728) * 0.125)).xyz, vec3(-_18734));
                break;
            } while(false);
            _21179 = mix(_21177, _21178, vec3(frag_info.radiance_blend.x));
        }
        else
        {
            _21179 = _21177;
        }
        _21180 = _21179 * frag_info.environment_intensity;
    }
    else
    {
        _21180 = _FogInfo.color.xyz;
    }
    highp vec4 _7111 = vec4((_21149 + (_20969 * mix(1.0, _20109, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + ((mix(hp_copy_5549 * vec3(0.077399380505084991455078125), pow((hp_copy_5549 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), hp_copy_5549)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w), 1.0) * _21300;
    highp vec4 _21190 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _21190 = _7111;
            break;
        }
        int _18864 = int(_FogInfo.params0.x + 0.5);
        if (_18864 == 0)
        {
            _21190 = _7111;
            break;
        }
        highp float _18871 = length(v_viewvector);
        if ((_FogInfo.params1.w > 0.0) && (_18871 > _FogInfo.params1.w))
        {
            _21190 = _7111;
            break;
        }
        highp float _21184 = 0.0;
        if (_18864 == 1)
        {
            _21184 = clamp((_18871 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            highp float _21185 = 0.0;
            if (_18864 == 2)
            {
                highp float _21183 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _18913 = v_position + v_viewvector;
                    highp float _18918 = -_FogInfo.params2.y;
                    highp float _18920 = _18913.y;
                    highp float _18925 = _FogInfo.params1.x * exp(_18918 * (_18920 - _FogInfo.params2.x));
                    highp float _18942 = _FogInfo.params2.y * (v_position.y - _18920);
                    highp float _21182 = 0.0;
                    if (abs(_18942) > 0.00124999997206032276153564453125)
                    {
                        _21182 = (_18925 - (_FogInfo.params1.x * exp(_18918 * (v_position.y - _FogInfo.params2.x)))) / _18942;
                    }
                    else
                    {
                        _21182 = _18925;
                    }
                    _21183 = _21182 * max(_18871 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _21183 = _FogInfo.params1.x * max(_18871 - _FogInfo.params1.y, 0.0);
                }
                _21185 = 1.0 - exp(-_21183);
            }
            else
            {
                highp float _18980 = _FogInfo.params1.x * max(_18871 - _FogInfo.params1.y, 0.0);
                _21185 = 1.0 - exp((-_18980) * _18980);
            }
            _21184 = _21185;
        }
        highp float _18992 = min(_21184, _FogInfo.params0.z);
        if (_18992 <= 0.0)
        {
            _21190 = _7111;
            break;
        }
        highp vec3 _19005 = mix(_FogInfo.color.xyz, _21180, vec3(_FogInfo.params0.w));
        bool _19008 = _FogInfo.sun.w > 0.5;
        bool _19014 = false;
        if (_19008)
        {
            _19014 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _19014 = _19008;
        }
        highp vec3 _21187 = vec3(0.0);
        if (_19014)
        {
            _21187 = _19005 + ((_FogInfo.sun.xyz * pow(max(dot(_6463, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w)) * _FogInfo.params2.z);
        }
        else
        {
            _21187 = _19005;
        }
        highp float _19044 = _7111.w;
        _21190 = vec4(mix(_7111.xyz, _21187 * _19044, vec3(_18992)), _19044);
        break;
    } while(false);
    frag_color = _21190;
}

