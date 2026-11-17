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
uniform highp sampler2D irradiance_field;
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
    highp float _4244 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_4244 = _4244;
    vec3 _4248 = normalize(v_normal) * mp_copy_4244;
    vec4 _4290 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _4293 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _10221 = vec2(0.0);
    if (_4293)
    {
        highp vec2 _10220 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _10220 = v_texture_coords_1;
        }
        else
        {
            _10220 = v_texture_coords;
        }
        highp vec2 _4496 = _10220 * texture_transforms.base_color_transform.zw;
        highp float _4502 = _4496.x;
        highp float _4507 = _4496.y;
        _10221 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _4502) + (texture_transforms.base_color_rotation.y * _4507), ((-texture_transforms.base_color_rotation.y) * _4502) + (texture_transforms.base_color_rotation.x * _4507));
    }
    else
    {
        _10221 = v_texture_coords;
    }
    vec4 _4307 = texture(base_color_texture, _10221);
    vec3 _4309 = _4307.xyz;
    float _10740 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_4307.w * _4290.w) * frag_info.color.w);
    vec3 _10236 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _10224 = vec2(0.0);
        if (_4293)
        {
            highp vec2 _10223 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _10223 = v_texture_coords_1;
            }
            else
            {
                _10223 = v_texture_coords;
            }
            highp vec2 _4591 = _10223 * texture_transforms.normal_transform.zw;
            highp float _4597 = _4591.x;
            highp float _4602 = _4591.y;
            _10224 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _4597) + (texture_transforms.normal_rotation.y * _4602), ((-texture_transforms.normal_rotation.y) * _4597) + (texture_transforms.normal_rotation.x * _4602));
        }
        else
        {
            _10224 = v_texture_coords;
        }
        vec3 _4647 = ((texture(normal_texture, _10224).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _4651 = _4647.xy * vec2(frag_info.normal_scale);
        vec3 _9948 = _4647;
        _9948.x = _4651.x;
        _9948.y = _4651.y;
        highp vec3 _4657 = -v_viewvector;
        highp vec3 _4747 = dFdx(_4657);
        highp vec3 _4749 = dFdy(_4657);
        highp vec2 _4751 = dFdx(_10224);
        highp vec2 _4753 = dFdy(_10224);
        bvec2 _10742 = bvec2(length(_4751) == 0.0);
        highp vec2 _10743 = vec2(_10742.x ? vec2(1.0, 0.0).x : _4751.x, _10742.y ? vec2(1.0, 0.0).y : _4751.y);
        bvec2 _10744 = bvec2(length(_4753) == 0.0);
        highp vec2 _10745 = vec2(_10744.x ? vec2(0.0, 1.0).x : _4753.x, _10744.y ? vec2(0.0, 1.0).y : _4753.y);
        highp vec3 _4766 = cross(_4749, _4248);
        highp vec3 _4769 = cross(_4248, _4747);
        highp float _4794 = (dot(cross(_4747, _4749), _4248) < 0.0) ? (-1.0) : 1.0;
        highp vec3 _4797 = ((_4766 * _10743.x) + (_4769 * _10745.x)) * _4794;
        highp float _10231 = 0.0;
        if (gl_FrontFacing)
        {
            _10231 = -_4794;
        }
        else
        {
            _10231 = _4794;
        }
        highp vec3 _4807 = ((_4766 * _10743.y) + (_4769 * _10745.y)) * _10231;
        highp float _4816 = inversesqrt(max(max(dot(_4797, _4797), dot(_4807, _4807)), 9.9999996826552253889678874634872e-21));
        vec3 _4688 = v_tangent.xyz - (_4248 * dot(_4248, v_tangent.xyz));
        highp float _4691 = dot(_4688, _4688);
        bool _4693 = _4691 > 1.0000000133514319600180897396058e-10;
        bool _4700 = false;
        if (_4693)
        {
            _4700 = abs(v_tangent.w) >= 0.5;
        }
        else
        {
            _4700 = _4693;
        }
        mat3 _10234 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        if (_4700)
        {
            highp vec3 _4705 = _4688 * inversesqrt(_4691);
            _10234 = mat3(_4705, normalize(cross(_4248, _4705)) * sign(v_tangent.w), _4248);
        }
        else
        {
            _10234 = mat3(_4797 * _4816, _4807 * _4816, _4248);
        }
        _10236 = normalize(_10234 * _9948);
    }
    else
    {
        _10236 = _4248;
    }
    highp vec2 _10238 = vec2(0.0);
    if (_4293)
    {
        highp vec2 _10237 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _10237 = v_texture_coords_1;
        }
        else
        {
            _10237 = v_texture_coords;
        }
        highp vec2 _4884 = _10237 * texture_transforms.metallic_roughness_transform.zw;
        highp float _4890 = _4884.x;
        highp float _4895 = _4884.y;
        _10238 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _4890) + (texture_transforms.metallic_roughness_rotation.y * _4895), ((-texture_transforms.metallic_roughness_rotation.y) * _4890) + (texture_transforms.metallic_roughness_rotation.x * _4895));
    }
    else
    {
        _10238 = v_texture_coords;
    }
    vec4 _4376 = texture(metallic_roughness_texture, _10238);
    float _4382 = clamp(_4376.z * frag_info.metallic_factor, 0.0, 1.0);
    float _4389 = clamp(_4376.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _10240 = vec2(0.0);
    if (_4293)
    {
        highp vec2 _10239 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _10239 = v_texture_coords_1;
        }
        else
        {
            _10239 = v_texture_coords;
        }
        highp vec2 _4955 = _10239 * texture_transforms.occlusion_transform.zw;
        highp float _4961 = _4955.x;
        highp float _4966 = _4955.y;
        _10240 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _4961) + (texture_transforms.occlusion_rotation.y * _4966), ((-texture_transforms.occlusion_rotation.y) * _4961) + (texture_transforms.occlusion_rotation.x * _4966));
    }
    else
    {
        _10240 = v_texture_coords;
    }
    float _10241 = 0.0;
    if (frag_info.occlusion_strength != 0.0)
    {
        _10241 = texture(occlusion_texture, _10240).x;
    }
    else
    {
        _10241 = 1.0;
    }
    float _4416 = 1.0 - ((1.0 - _10241) * frag_info.occlusion_strength);
    highp vec2 _10243 = vec2(0.0);
    if (_4293)
    {
        highp vec2 _10242 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _10242 = v_texture_coords_1;
        }
        else
        {
            _10242 = v_texture_coords;
        }
        highp vec2 _5026 = _10242 * texture_transforms.emissive_transform.zw;
        highp float _5032 = _5026.x;
        highp float _5037 = _5026.y;
        _10243 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _5032) + (texture_transforms.emissive_rotation.y * _5037), ((-texture_transforms.emissive_rotation.y) * _5032) + (texture_transforms.emissive_rotation.x * _5037));
    }
    else
    {
        _10243 = v_texture_coords;
    }
    vec3 _4435 = frag_info.emissive_factor.xyz * frag_info.emissive_factor.w;
    vec3 _10259 = vec3(0.0);
    if (dot(abs(_4435), vec3(1.0)) > 0.0)
    {
        vec3 _4444 = texture(emissive_texture, _10243).xyz;
        _10259 = mix(_4444 * vec3(0.077399380505084991455078125), pow((_4444 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4444)) * _4435;
    }
    else
    {
        _10259 = vec3(0.0);
    }
    highp float hp_copy_10284 = 0.0;
    vec3 _5212 = vec4((mix(_4309 * vec3(0.077399380505084991455078125), pow((_4309 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _4309)) * _4290.xyz) * frag_info.color.xyz, _10740).xyz;
    vec3 _5698 = dFdx(_10236);
    vec3 _5700 = dFdy(_10236);
    float _10284 = 0.0;
    if (frag_info.specular_aa_variance > 0.0)
    {
        _10284 = sqrt(clamp((_4389 * _4389) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_5698, _5698), dot(_5700, _5700))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
    }
    else
    {
        _10284 = _4389;
    }
    hp_copy_10284 = _10284;
    float _10313 = 0.0;
    if (frag_info.ssao_params.x > 1000000015047466219876688855040.0)
    {
        _10313 = texture(ssao_texture, vec2(0.0)).x;
    }
    else
    {
        _10313 = _4416;
    }
    bool _5237 = frag_info.has_directional_light > 0.5;
    float _10285 = 0.0;
    vec3 _10327 = vec3(0.0);
    if (_5237)
    {
        highp vec3 _5243 = -normalize(frag_info.directional_light_direction.xyz);
        _10327 = _5243;
        _10285 = dot(_4248, _5243);
    }
    else
    {
        _10327 = vec3(0.0);
        _10285 = 0.0;
    }
    float _5250 = clamp(_10285 * 6.666666507720947265625, 0.0, 1.0);
    bool _5259 = false;
    if (_5237)
    {
        _5259 = frag_info.casts_shadow > 0.5;
    }
    else
    {
        _5259 = _5237;
    }
    float _10294 = 0.0;
    if (_5259 && (_5250 > 0.0))
    {
        int _5779 = int(frag_info.shadow_cascade_count);
        float _5974 = max(dot(_4248, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
        float _5977 = _5974 * _5974;
        highp vec3 _5997 = v_position + (_4248 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _5977, 0.0)) / _5977, 8.0))));
        highp float _5785 = frag_info.directional_light_color.w * 0.5;
        float _5787 = frag_info.dielectric_f0.w;
        highp float hp_copy_5787 = _5787;
        float _10286 = 0.0;
        if (_5787 > 0.0)
        {
            _10286 = smoothstep(_5787 - max(frag_info.shadow_fade, hp_copy_5787 * 0.100000001490116119384765625), _5787, dot(-v_viewvector, frag_info.camera_forward.xyz));
        }
        else
        {
            _10286 = 0.0;
        }
        float _10288 = 0.0;
        float _10290 = 0.0;
        if (_10286 < 1.0)
        {
            float _10289 = 0.0;
            float _10291 = 0.0;
            _10291 = 0.0;
            _10289 = 0.0;
            float _10574 = 0.0;
            float _10577 = 0.0;
            for (int _10287 = 0; _10287 < _5779; _10291 = _10577, _10289 = _10574, _10287++)
            {
                if (_10291 < 1.0)
                {
                    highp vec4 _5819 = vec4(_5997, 1.0);
                    highp vec4 _10446 = vec4(0.0);
                    highp float _10449 = 0.0;
                    if (_10287 == 0)
                    {
                        _10449 = frag_info.cascade_box_sizes.x;
                        _10446 = frag_info.light_space_matrix[0] * _5819;
                    }
                    else
                    {
                        highp vec4 _10447 = vec4(0.0);
                        highp float _10450 = 0.0;
                        if (_10287 == 1)
                        {
                            _10450 = frag_info.cascade_box_sizes.y;
                            _10447 = frag_info.light_space_matrix[1] * _5819;
                        }
                        else
                        {
                            highp vec4 _10448 = vec4(0.0);
                            highp float _10451 = 0.0;
                            if (_10287 == 2)
                            {
                                _10451 = frag_info.cascade_box_sizes.z;
                                _10448 = frag_info.light_space_matrix[2] * _5819;
                            }
                            else
                            {
                                _10451 = frag_info.cascade_box_sizes.w;
                                _10448 = frag_info.light_space_matrix[3] * _5819;
                            }
                            _10450 = _10451;
                            _10447 = _10448;
                        }
                        _10449 = _10450;
                        _10446 = _10447;
                    }
                    highp vec3 _5864 = _10446.xyz / vec3(_10446.w);
                    highp vec2 _5867 = _5864.xy * 0.5;
                    highp vec2 _5869 = _5867 + vec2(0.5);
                    highp float _5876 = max(frag_info.shadow_softness / _10449, frag_info.shadow_texel_size);
                    highp float _5878 = _5869.x;
                    bool _5880 = _5878 < _5876;
                    bool _5889 = false;
                    if (!_5880)
                    {
                        _5889 = _5878 > (1.0 - _5876);
                    }
                    else
                    {
                        _5889 = _5880;
                    }
                    bool _5897 = false;
                    if (!_5889)
                    {
                        _5897 = _5869.y < _5876;
                    }
                    else
                    {
                        _5897 = _5889;
                    }
                    bool _5906 = false;
                    if (!_5897)
                    {
                        _5906 = _5869.y > (1.0 - _5876);
                    }
                    else
                    {
                        _5906 = _5897;
                    }
                    bool _5913 = false;
                    if (!_5906)
                    {
                        _5913 = _5864.z < 0.0;
                    }
                    else
                    {
                        _5913 = _5906;
                    }
                    bool _5920 = false;
                    if (!_5913)
                    {
                        _5920 = _5864.z > 1.0;
                    }
                    else
                    {
                        _5920 = _5913;
                    }
                    float _10575 = 0.0;
                    float _10578 = 0.0;
                    if (!_5920)
                    {
                        highp vec2 _6013 = vec2(_5876);
                        highp vec2 _6018 = vec2(_5876 + max(_5785, 9.9999997473787516355514526367188e-05));
                        highp vec2 _6026 = vec2(0.5) - _5867;
                        highp vec2 _6028 = smoothstep(_6013, _6018, _5869) * smoothstep(_6013, _6018, _6026);
                        float _10452 = 0.0;
                        if (_5785 > 0.0)
                        {
                            _10452 = _6028.x * _6028.y;
                        }
                        else
                        {
                            _10452 = 1.0;
                        }
                        float _5929 = min(_10452, 1.0 - _10291);
                        float _10576 = 0.0;
                        float _10579 = 0.0;
                        if (_5929 > 0.0)
                        {
                            highp float _6167 = _5864.z - (frag_info.shadow_bias / (7.0 * _10449));
                            highp float _6173 = 1.0 / (float(_5779) + frag_info.spot_shadow_params.x);
                            highp float _6175 = frag_info.directional_light_direction.w;
                            float mp_copy_6175 = _6175;
                            float _6181 = step(0.5, mp_copy_6175) * (1.0 - step(1.5, mp_copy_6175));
                            float _10482 = 0.0;
                            float _10486 = 0.0;
                            if (_6181 < 0.5)
                            {
                                highp float _6192 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float mp_copy_6192 = _6192;
                                _10486 = sin(mp_copy_6192);
                                _10482 = cos(mp_copy_6192);
                            }
                            else
                            {
                                _10486 = 0.0;
                                _10482 = 1.0;
                            }
                            highp float _10489 = 0.0;
                            if ((_6175 > 1.5) && (_6175 < 2.5))
                            {
                                highp float _6216 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _6221 = max(_6216 * _6167, frag_info.shadow_texel_size);
                                float _10478 = 0.0;
                                highp float _10479 = 0.0;
                                _10479 = 0.0;
                                _10478 = 0.0;
                                highp float _6243 = 0.0;
                                float _6246 = 0.0;
                                for (int _10477 = 0; _10477 < 9; _10479 = _6243, _10478 = _6246, _10477++)
                                {
                                    vec2 _10568 = vec2(0.0);
                                    do
                                    {
                                        if (_10477 == 0)
                                        {
                                            _10568 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_10477 == 1)
                                        {
                                            _10568 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_10477 == 2)
                                        {
                                            _10568 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_10477 == 3)
                                        {
                                            _10568 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_10477 == 4)
                                        {
                                            _10568 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_10477 == 5)
                                        {
                                            _10568 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_10477 == 6)
                                        {
                                            _10568 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_10477 == 7)
                                        {
                                            _10568 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_10477 == 8)
                                        {
                                            _10568 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_10477 == 9)
                                        {
                                            _10568 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_10477 == 10)
                                        {
                                            _10568 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_10477 == 11)
                                        {
                                            _10568 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_10477 == 12)
                                        {
                                            _10568 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_10477 == 13)
                                        {
                                            _10568 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_10477 == 14)
                                        {
                                            _10568 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_10477 == 15)
                                        {
                                            _10568 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _10568 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _6550 = clamp(_5869 + (vec2((_10568.x * _10482) - (_10568.y * _10486), (_10568.x * _10486) + (_10568.y * _10482)) * _6221), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _6559 = _6550.y;
                                    highp vec2 _6560 = vec2((float(_10287) + _6550.x) * _6173, _6559);
                                    _6560.y = 1.0 - _6559;
                                    highp vec4 _6567 = textureLod(shadow_map, _6560, 0.0);
                                    highp float _6568 = _6567.x;
                                    highp float _6238 = step(_6568, _6167);
                                    float mp_copy_6238 = _6238;
                                    _6243 = _10479 + (_6568 * _6238);
                                    _6246 = _10478 + mp_copy_6238;
                                }
                                highp float _10480 = 0.0;
                                if (_10478 > 0.0)
                                {
                                    _10480 = _10479 / _10478;
                                }
                                else
                                {
                                    _10480 = _6167;
                                }
                                _10489 = clamp(_6216 * max(_6167 - _10480, 0.0), frag_info.shadow_texel_size, _5876);
                            }
                            else
                            {
                                _10489 = _5876;
                            }
                            bool _6277 = _6175 > 2.5;
                            bool _10490 = false;
                            float _10515 = 0.0;
                            if ((_6175 < 1.5) || _6277)
                            {
                                highp vec2 _6601 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _6605 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _6606 = clamp(_5869, _6601, _6605);
                                highp float _6608 = float(_10287);
                                highp float _6615 = _6606.y;
                                highp vec2 _6616 = vec2((_6608 + _6606.x) * _6173, _6615);
                                _6616.y = 1.0 - _6615;
                                highp float _6628 = float(_6167 <= textureLod(shadow_map, _6616, 0.0).x);
                                float mp_copy_6628 = _6628;
                                float _6638 = (-1.0) * _10482;
                                float _6642 = (-1.0) * _10486;
                                highp vec2 _6666 = clamp(_5869 + (vec2(_6638 - _6642, _6642 + _6638) * _10489), _6601, _6605);
                                highp float _6675 = _6666.y;
                                highp vec2 _6676 = vec2((_6608 + _6666.x) * _6173, _6675);
                                _6676.y = 1.0 - _6675;
                                highp float _6688 = float(_6167 <= textureLod(shadow_map, _6676, 0.0).x);
                                float mp_copy_6688 = _6688;
                                highp vec2 _6726 = clamp(_5869 + (vec2(_10482 - _6642, _10486 + _6638) * _10489), _6601, _6605);
                                highp float _6735 = _6726.y;
                                highp vec2 _6736 = vec2((_6608 + _6726.x) * _6173, _6735);
                                _6736.y = 1.0 - _6735;
                                highp float _6748 = float(_6167 <= textureLod(shadow_map, _6736, 0.0).x);
                                float mp_copy_6748 = _6748;
                                highp vec2 _6786 = clamp(_5869 + (vec2(_6638 - _10486, _6642 + _10482) * _10489), _6601, _6605);
                                highp float _6795 = _6786.y;
                                highp vec2 _6796 = vec2((_6608 + _6786.x) * _6173, _6795);
                                _6796.y = 1.0 - _6795;
                                highp float _6808 = float(_6167 <= textureLod(shadow_map, _6796, 0.0).x);
                                float mp_copy_6808 = _6808;
                                highp vec2 _6846 = clamp(_5869 + (vec2(_10482 - _10486, _10486 + _10482) * _10489), _6601, _6605);
                                highp float _6855 = _6846.y;
                                highp vec2 _6856 = vec2((_6608 + _6846.x) * _6173, _6855);
                                _6856.y = 1.0 - _6855;
                                highp float _6868 = float(_6167 <= textureLod(shadow_map, _6856, 0.0).x);
                                float mp_copy_6868 = _6868;
                                float _6323 = (((mp_copy_6628 + mp_copy_6688) + mp_copy_6748) + mp_copy_6808) + mp_copy_6868;
                                _10515 = _6323 * 0.20000000298023223876953125;
                                _10490 = (_6323 < 0.5) || (_6323 > 4.5);
                            }
                            else
                            {
                                _10515 = 0.0;
                                _10490 = false;
                            }
                            float _10513 = 0.0;
                            if (_10490)
                            {
                                _10513 = _10515;
                            }
                            else
                            {
                                float _10514 = 0.0;
                                if (_6277)
                                {
                                    highp vec2 _7087 = vec2(frag_info.shadow_texel_size);
                                    highp vec2 _7091 = vec2(1.0 - frag_info.shadow_texel_size);
                                    highp vec2 _7092 = clamp(_5869 + (vec2(-0.707099974155426025390625) * _10489), _7087, _7091);
                                    highp vec2 _7103 = (vec2(_7092.x, 1.0 - _7092.y) / _7087) - vec2(0.5);
                                    highp vec2 _7105 = floor(_7103);
                                    highp vec2 _7108 = _7103 - _7105;
                                    highp vec2 _7113 = (_7105 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp float _7115 = float(_10287);
                                    highp vec2 _7123 = vec2((_7115 + _7113.x) * _6173, _7113.y);
                                    highp float _7127 = frag_info.shadow_texel_size * _6173;
                                    highp vec2 _7130 = vec2(_7127, frag_info.shadow_texel_size);
                                    highp vec2 _7139 = vec2(_7127, 0.0);
                                    highp vec2 _7147 = vec2(0.0, frag_info.shadow_texel_size);
                                    highp float _7176 = _7108.x;
                                    highp float _7185 = mix(mix(float(_6167 <= textureLod(shadow_map, _7123, 0.0).x), float(_6167 <= textureLod(shadow_map, _7123 + _7139, 0.0).x), _7176), mix(float(_6167 <= textureLod(shadow_map, _7123 + _7147, 0.0).x), float(_6167 <= textureLod(shadow_map, _7123 + _7130, 0.0).x), _7176), _7108.y);
                                    float mp_copy_7185 = _7185;
                                    highp vec2 _7219 = clamp(_5869 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _10489), _7087, _7091);
                                    highp vec2 _7230 = (vec2(_7219.x, 1.0 - _7219.y) / _7087) - vec2(0.5);
                                    highp vec2 _7232 = floor(_7230);
                                    highp vec2 _7235 = _7230 - _7232;
                                    highp vec2 _7240 = (_7232 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7250 = vec2((_7115 + _7240.x) * _6173, _7240.y);
                                    highp float _7303 = _7235.x;
                                    highp float _7312 = mix(mix(float(_6167 <= textureLod(shadow_map, _7250, 0.0).x), float(_6167 <= textureLod(shadow_map, _7250 + _7139, 0.0).x), _7303), mix(float(_6167 <= textureLod(shadow_map, _7250 + _7147, 0.0).x), float(_6167 <= textureLod(shadow_map, _7250 + _7130, 0.0).x), _7303), _7235.y);
                                    float mp_copy_7312 = _7312;
                                    highp vec2 _7346 = clamp(_5869 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _10489), _7087, _7091);
                                    highp vec2 _7357 = (vec2(_7346.x, 1.0 - _7346.y) / _7087) - vec2(0.5);
                                    highp vec2 _7359 = floor(_7357);
                                    highp vec2 _7362 = _7357 - _7359;
                                    highp vec2 _7367 = (_7359 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7377 = vec2((_7115 + _7367.x) * _6173, _7367.y);
                                    highp float _7430 = _7362.x;
                                    highp float _7439 = mix(mix(float(_6167 <= textureLod(shadow_map, _7377, 0.0).x), float(_6167 <= textureLod(shadow_map, _7377 + _7139, 0.0).x), _7430), mix(float(_6167 <= textureLod(shadow_map, _7377 + _7147, 0.0).x), float(_6167 <= textureLod(shadow_map, _7377 + _7130, 0.0).x), _7430), _7362.y);
                                    float mp_copy_7439 = _7439;
                                    highp vec2 _7473 = clamp(_5869 + (vec2(0.707099974155426025390625) * _10489), _7087, _7091);
                                    highp vec2 _7484 = (vec2(_7473.x, 1.0 - _7473.y) / _7087) - vec2(0.5);
                                    highp vec2 _7486 = floor(_7484);
                                    highp vec2 _7489 = _7484 - _7486;
                                    highp vec2 _7494 = (_7486 + vec2(0.5)) * frag_info.shadow_texel_size;
                                    highp vec2 _7504 = vec2((_7115 + _7494.x) * _6173, _7494.y);
                                    highp float _7557 = _7489.x;
                                    highp float _7566 = mix(mix(float(_6167 <= textureLod(shadow_map, _7504, 0.0).x), float(_6167 <= textureLod(shadow_map, _7504 + _7139, 0.0).x), _7557), mix(float(_6167 <= textureLod(shadow_map, _7504 + _7147, 0.0).x), float(_6167 <= textureLod(shadow_map, _7504 + _7130, 0.0).x), _7557), _7489.y);
                                    float mp_copy_7566 = _7566;
                                    _10514 = (((mp_copy_7185 + mp_copy_7312) + mp_copy_7439) + mp_copy_7566) * 0.25;
                                }
                                else
                                {
                                    int _6339 = (_6181 > 0.5) ? 17 : 16;
                                    float _10509 = 0.0;
                                    _10509 = 0.0;
                                    float _6367 = 0.0;
                                    for (int _10491 = 0; _10491 < 17; _10509 = _6367, _10491++)
                                    {
                                        if (_10491 >= _6339)
                                        {
                                            break;
                                        }
                                        vec2 _10492 = vec2(0.0);
                                        do
                                        {
                                            if (_10491 == 0)
                                            {
                                                _10492 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                                break;
                                            }
                                            if (_10491 == 1)
                                            {
                                                _10492 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                                break;
                                            }
                                            if (_10491 == 2)
                                            {
                                                _10492 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                                break;
                                            }
                                            if (_10491 == 3)
                                            {
                                                _10492 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                                break;
                                            }
                                            if (_10491 == 4)
                                            {
                                                _10492 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                                break;
                                            }
                                            if (_10491 == 5)
                                            {
                                                _10492 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                                break;
                                            }
                                            if (_10491 == 6)
                                            {
                                                _10492 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                                break;
                                            }
                                            if (_10491 == 7)
                                            {
                                                _10492 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                                break;
                                            }
                                            if (_10491 == 8)
                                            {
                                                _10492 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                                break;
                                            }
                                            if (_10491 == 9)
                                            {
                                                _10492 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                                break;
                                            }
                                            if (_10491 == 10)
                                            {
                                                _10492 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                                break;
                                            }
                                            if (_10491 == 11)
                                            {
                                                _10492 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                                break;
                                            }
                                            if (_10491 == 12)
                                            {
                                                _10492 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                                break;
                                            }
                                            if (_10491 == 13)
                                            {
                                                _10492 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                                break;
                                            }
                                            if (_10491 == 14)
                                            {
                                                _10492 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                                break;
                                            }
                                            if (_10491 == 15)
                                            {
                                                _10492 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                                break;
                                            }
                                            _10492 = vec2(0.0);
                                            break;
                                        } while(false);
                                        vec2 _10494 = vec2(0.0);
                                        do
                                        {
                                            if (_10491 < 3)
                                            {
                                                _10494 = vec2(float(_10491) - 1.0, -1.0);
                                                break;
                                            }
                                            if (_10491 < 6)
                                            {
                                                _10494 = vec2((float(_10491 - 3) * 0.5) - 0.5, -0.5);
                                                break;
                                            }
                                            if (_10491 < 11)
                                            {
                                                _10494 = vec2((float(_10491 - 6) * 0.5) - 1.0, 0.0);
                                                break;
                                            }
                                            if (_10491 < 14)
                                            {
                                                _10494 = vec2((float(_10491 - 11) * 0.5) - 0.5, 0.5);
                                                break;
                                            }
                                            _10494 = vec2(float(_10491 - 14) - 1.0, 1.0);
                                            break;
                                        } while(false);
                                        vec2 _6356 = mix(_10492, _10494, vec2(_6181));
                                        float _7007 = _6356.x;
                                        float _7011 = _6356.y;
                                        highp vec2 _7037 = clamp(_5869 + (vec2((_7007 * _10482) - (_7011 * _10486), (_7007 * _10486) + (_7011 * _10482)) * _10489), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                        highp float _7046 = _7037.y;
                                        highp vec2 _7047 = vec2((float(_10287) + _7037.x) * _6173, _7046);
                                        _7047.y = 1.0 - _7046;
                                        highp float _7059 = float(_6167 <= textureLod(shadow_map, _7047, 0.0).x);
                                        float mp_copy_7059 = _7059;
                                        _6367 = _10509 + mp_copy_7059;
                                    }
                                    _10514 = _10509 / float(_6339);
                                }
                                _10513 = _10514;
                            }
                            bool _6412 = _10287 == (_5779 - 1);
                            bool _6418 = false;
                            if (_6412)
                            {
                                _6418 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _6418 = _6412;
                            }
                            float _10516 = 0.0;
                            if (_6418)
                            {
                                highp vec2 _6425 = vec2(frag_info.shadow_fade / _10449);
                                highp vec2 _6433 = smoothstep(vec2(0.0), _6425, _5869) * smoothstep(vec2(0.0), _6425, _6026);
                                _10516 = mix(1.0, _10513, _6433.x * _6433.y);
                            }
                            else
                            {
                                _10516 = _10513;
                            }
                            _10579 = _10291 + _5929;
                            _10576 = _10289 + (_5929 * _10516);
                        }
                        else
                        {
                            _10579 = _10291;
                            _10576 = _10289;
                        }
                        _10578 = _10579;
                        _10575 = _10576;
                    }
                    else
                    {
                        _10578 = _10291;
                        _10575 = _10289;
                    }
                    _10577 = _10578;
                    _10574 = _10575;
                }
                else
                {
                    _10577 = _10291;
                    _10574 = _10289;
                }
            }
            _10290 = _10291;
            _10288 = _10289;
        }
        else
        {
            _10290 = 0.0;
            _10288 = 0.0;
        }
        _10294 = mix(_10288 + (1.0 - _10290), 1.0, _10286);
    }
    else
    {
        _10294 = 1.0;
    }
    vec3 mp_copy_10295 = vec3(0.0);
    float _5272 = _5250 * _10294;
    bool _7574 = view_info.camera_forward.w > 0.5;
    highp vec3 _10295 = vec3(0.0);
    if (_7574)
    {
        _10295 = -view_info.camera_forward.xyz;
    }
    else
    {
        _10295 = normalize(v_viewvector);
    }
    highp float _7618 = 0.0;
    mp_copy_10295 = _10295;
    vec3 _5281 = mix(frag_info.dielectric_f0.xyz, _5212, vec3(_4382));
    float _5285 = max(dot(_10236, _10295), 0.0);
    float _5289 = max(dot(_4248, _10295), 0.0);
    highp vec2 _10296 = vec2(0.0);
    do
    {
        _7618 = frag_info.punctual_dims.x;
        if (_7618 < 0.5)
        {
            _10296 = vec2(0.0);
            break;
        }
        if (frag_info.froxel_grid.z > 0.5)
        {
            highp vec3 _7630 = v_position - frag_info.camera_position.xyz;
            highp float _7645 = dot(_7630, frag_info.camera_forward.xyz);
            highp float _7651 = max(_7645, 9.9999997473787516355514526367188e-05);
            highp vec2 _7754 = (vec3(dot(_7630, frag_info.camera_right.xyz), dot(_7630, frag_info.camera_up.xyz), _7651).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_7651, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
            highp float _7769 = float(int(((((clamp(floor((log2(max(_7645 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_7754.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_7754.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
            _10296 = vec2(textureLod(punctual_index, vec2((mod(_7769, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7769 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).xy);
            break;
        }
        _10296 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
        break;
    } while(false);
    mediump int _5298 = int(_10296.x + 0.5);
    mediump int _5302 = int(_10296.y + 0.5);
    highp vec3 _10341 = vec3(0.0);
    _10341 = vec3(0.0);
    highp vec3 _10690 = vec3(0.0);
    for (int _10297 = 0; _10297 < _5302; _10341 = _10690, _10297++)
    {
        highp float hp_copy_10398 = 0.0;
        highp float _7802 = float(_5298 + _10297);
        highp float _7833 = (float(int(textureLod(punctual_index, vec2((mod(_7802, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_7802 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z), 0.0).x + 0.5)) + 0.5) / _7618;
        highp vec4 _7837 = textureLod(punctual_lights, vec2(0.0625, _7833), 0.0);
        highp vec4 _7854 = textureLod(punctual_lights, vec2(0.1875, _7833), 0.0);
        highp float _5320 = _7837.w;
        highp vec3 _5322 = _7854.xyz;
        vec3 _10384 = vec3(0.0);
        highp vec3 _10395 = vec3(0.0);
        float _10398 = 0.0;
        if (_5320 < 0.5)
        {
            _10398 = _10284;
            _10395 = _5322;
            _10384 = -normalize(textureLod(punctual_lights, vec2(0.3125, _7833), 0.0).xyz);
        }
        else
        {
            highp vec3 _5330 = _7837.xyz - v_position;
            highp float _5333 = dot(_5330, _5330);
            highp float _5337 = inversesqrt(max(_5333, 9.9999999392252902907785028219223e-09));
            highp vec3 _5338 = _5330 * _5337;
            vec3 mp_copy_5338 = _5338;
            highp float _5340 = _7854.w;
            highp float _5345 = (_5333 * _5340) * _5340;
            highp float _5350 = clamp(1.0 - (_5345 * _5345), 0.0, 1.0);
            float mp_copy_5350 = _5350;
            if (_5350 <= 0.0)
            {
                _10690 = _10341;
                continue;
            }
            highp vec4 _7871 = textureLod(punctual_lights, vec2(0.4375, _7833), 0.0);
            highp float _5358 = _7871.w;
            float _10400 = 0.0;
            if (_5358 > 0.0)
            {
                highp float _5385 = (_10284 * _10284) + ((_5358 * 0.5) * _5337);
                float mp_copy_5385 = _5385;
                _10400 = sqrt(min(mp_copy_5385, 1.0));
            }
            else
            {
                _10400 = _10284;
            }
            highp vec3 _5392 = _5322 * ((mp_copy_5350 * mp_copy_5350) / max(pow(max(_5333, _5358 * _5358), _7871.z * 0.5), 9.9999997473787516355514526367188e-05));
            highp vec3 _10396 = vec3(0.0);
            if (_5320 > 1.5)
            {
                highp vec4 _7888 = textureLod(punctual_lights, vec2(0.3125, _7833), 0.0);
                highp float _5411 = clamp((dot(normalize(_7888.xyz), -mp_copy_5338) * _7888.w) + _7871.x, 0.0, 1.0);
                float mp_copy_5411 = _5411;
                highp vec3 _5416 = _5392 * (mp_copy_5411 * mp_copy_5411);
                if (_5411 <= 0.0)
                {
                    _10690 = _10341;
                    continue;
                }
                bool _5422 = _5411 > 0.0;
                bool _5428 = false;
                if (_5422)
                {
                    _5428 = _7871.y > (-0.5);
                }
                else
                {
                    _5428 = _5422;
                }
                bool _5434 = false;
                if (_5428)
                {
                    _5434 = frag_info.spot_shadow_params.x > 0.5;
                }
                else
                {
                    _5434 = _5428;
                }
                highp vec3 _10397 = vec3(0.0);
                if (_5434)
                {
                    float _10375 = 0.0;
                    do
                    {
                        highp vec4 _8000 = mat4(textureLod(punctual_lights, vec2(0.5625, _7833), 0.0), textureLod(punctual_lights, vec2(0.6875, _7833), 0.0), textureLod(punctual_lights, vec2(0.8125, _7833), 0.0), textureLod(punctual_lights, vec2(0.9375, _7833), 0.0)) * vec4(v_position + (_4248 * frag_info.spot_shadow_params.z), 1.0);
                        highp float _8002 = _8000.w;
                        if (_8002 <= 0.0)
                        {
                            _10375 = 1.0;
                            break;
                        }
                        highp vec3 _8011 = _8000.xyz / vec3(_8002);
                        highp vec2 _8016 = (_8011.xy * 0.5) + vec2(0.5);
                        highp float _8018 = _8016.x;
                        bool _8019 = _8018 < 0.0;
                        bool _8026 = false;
                        if (!_8019)
                        {
                            _8026 = _8018 > 1.0;
                        }
                        else
                        {
                            _8026 = _8019;
                        }
                        bool _8033 = false;
                        if (!_8026)
                        {
                            _8033 = _8016.y < 0.0;
                        }
                        else
                        {
                            _8033 = _8026;
                        }
                        bool _8040 = false;
                        if (!_8033)
                        {
                            _8040 = _8016.y > 1.0;
                        }
                        else
                        {
                            _8040 = _8033;
                        }
                        bool _8047 = false;
                        if (!_8040)
                        {
                            _8047 = _8011.z < 0.0;
                        }
                        else
                        {
                            _8047 = _8040;
                        }
                        bool _8054 = false;
                        if (!_8047)
                        {
                            _8054 = _8011.z > 1.0;
                        }
                        else
                        {
                            _8054 = _8047;
                        }
                        if (_8054)
                        {
                            _10375 = 1.0;
                            break;
                        }
                        highp float _8061 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                        highp float _8066 = frag_info.shadow_cascade_count + float(int(_7871.y + 0.5));
                        highp float _8071 = _8011.z - frag_info.spot_shadow_params.y;
                        highp float _8082 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                        float mp_copy_8082 = _8082;
                        highp vec2 _8089 = vec2(cos(mp_copy_8082), sin(mp_copy_8082)) * (frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875);
                        highp float _8091 = _8089.x;
                        highp float _8093 = _8089.y;
                        highp vec2 _8101 = vec2(_8091 - _8093, _8091 + _8093) * 0.707106769084930419921875;
                        highp float _8294 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8018, 0.0, 1.0)) / _8061, 1.0 - clamp(_8016.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8294 = _8294;
                        highp vec2 _8109 = _8016 + _8089;
                        highp float _8316 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8109.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8109.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8316 = _8316;
                        highp vec2 _8117 = _8016 - _8089;
                        highp float _8338 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8117.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8117.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8338 = _8338;
                        highp vec2 _8130 = _8016 + vec2(-_8093, _8091);
                        highp float _8360 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8130.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8130.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8360 = _8360;
                        highp vec2 _8143 = _8016 + vec2(_8093, -_8091);
                        highp float _8382 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8143.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8143.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8382 = _8382;
                        float _8148 = (((mp_copy_8294 + mp_copy_8316) + mp_copy_8338) + mp_copy_8360) + mp_copy_8382;
                        if ((_8148 < 0.5) || (_8148 > 4.5))
                        {
                            _10375 = _8148 * 0.20000000298023223876953125;
                            break;
                        }
                        highp vec2 _8160 = _8016 + _8101;
                        highp float _8404 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8160.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8160.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8404 = _8404;
                        highp vec2 _8167 = _8016 - _8101;
                        highp float _8426 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8167.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8167.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8426 = _8426;
                        highp float _8175 = _8101.y;
                        highp float _8178 = _8101.x;
                        highp vec2 _8180 = _8016 + vec2(-_8175, _8178);
                        highp float _8448 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8180.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8180.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8448 = _8448;
                        highp vec2 _8193 = _8016 + vec2(_8175, -_8178);
                        highp float _8470 = float(_8071 <= textureLod(shadow_map, vec2((_8066 + clamp(_8193.x, 0.0, 1.0)) / _8061, 1.0 - clamp(_8193.y, 0.0, 1.0)), 0.0).x);
                        float mp_copy_8470 = _8470;
                        _10375 = (_8148 + (((mp_copy_8404 + mp_copy_8426) + mp_copy_8448) + mp_copy_8470)) * 0.111111111938953399658203125;
                        break;
                    } while(false);
                    _10397 = _5416 * _10375;
                }
                else
                {
                    _10397 = _5416;
                }
                _10396 = _10397;
            }
            else
            {
                _10396 = _5392;
            }
            _10398 = _10400;
            _10395 = _10396;
            _10384 = _5338;
        }
        hp_copy_10398 = _10398;
        highp vec3 _10413 = vec3(0.0);
        highp vec3 _10414 = vec3(0.0);
        do
        {
            float _8553 = max(dot(_10236, _10384), 0.0);
            highp float hp_copy_8553 = _8553;
            if (_8553 <= 0.0)
            {
                _10414 = vec3(0.0);
                _10413 = vec3(0.0);
                break;
            }
            float _8559 = max(_5285, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_8559 = _8559;
            vec3 _8562 = _10384 + mp_copy_10295;
            float _8565 = dot(_8562, _8562);
            vec3 _10411 = vec3(0.0);
            vec3 _10412 = vec3(0.0);
            if (_8565 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _8573 = _8562 * inversesqrt(_8565);
                float _10410 = 0.0;
                do
                {
                    float _8630 = dot(_10236, _8573);
                    if (_8630 <= 0.0)
                    {
                        _10410 = 0.0;
                        break;
                    }
                    float _8637 = _10398 * _10398;
                    vec3 _8640 = cross(_10236, _8573);
                    float _8643 = _8630 * _8637;
                    float _8652 = _8637 / (dot(_8640, _8640) + (_8643 * _8643));
                    _10410 = min((_8652 * _8652) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _8690 = _5281 + ((vec3(1.0) - _5281) * pow(clamp(1.0 - max(dot(_8573, _10295), 0.0), 0.0, 1.0), 5.0));
                _10412 = (_8690 * min(_10410 * (0.5 / max(mix((2.0 * hp_copy_8553) * _8559, hp_copy_8553 + hp_copy_8559, hp_copy_10398 * hp_copy_10398), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10411 = _8690;
            }
            else
            {
                _10412 = vec3(0.0);
                _10411 = _5281;
            }
            _10414 = (_10412 * _10395) * _8553;
            _10413 = (((((vec3(1.0) - _10411) * (1.0 - _4382)) * _5212) * 0.3183098733425140380859375) * _10395) * _8553;
            break;
        } while(false);
        _10690 = _10341 + (_10413 + _10414);
    }
    bool _8914 = false;
    highp vec3 hp_copy_10298 = vec3(0.0);
    mat3 _5489 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
    vec3 _5497 = _5489 * vec3(_10236.x, _10236.y, _10236.z);
    vec3 _5500 = _5489 * reflect(-mp_copy_10295, _10236);
    float _8733 = _5497.y;
    float _8740 = _5497.z;
    float _8747 = _5497.x;
    float _8755 = 1.09254801273345947265625 * _8747;
    vec3 _5503 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * (0.48860299587249755859375 * _8733))) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * (0.48860299587249755859375 * _8740))) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * (0.48860299587249755859375 * _8747))) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * (_8755 * _8733))) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * ((1.09254801273345947265625 * _8733) * _8740))) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * (0.3153919875621795654296875 * (((3.0 * _8740) * _8740) - 1.0)))) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * (_8755 * _8740))) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * (0.546274006366729736328125 * ((_8747 * _8747) - (_8733 * _8733)))), vec3(0.0));
    highp vec3 hp_copy_5503 = _5503;
    vec3 _10298 = vec3(0.0);
    do
    {
        _8914 = radiance_layout_info.mip_layout > 0.5;
        if (_8914)
        {
            vec2 _8993 = vec2(atan(_5500.z, _5500.x), asin(clamp(_5500.y, -1.0, 1.0)));
            highp vec2 hp_copy_8993 = _8993;
            _10298 = textureLod(prefiltered_radiance, (hp_copy_8993 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10284, 0.0, 1.0) * 7.0).xyz;
            break;
        }
        vec2 _9012 = vec2(atan(_5500.z, _5500.x), asin(clamp(_5500.y, -1.0, 1.0)));
        highp vec2 hp_copy_9012 = _9012;
        highp vec2 _9017 = (hp_copy_9012 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
        highp float _8924 = clamp(_9017.y, 0.00390625, 0.99609375);
        float _8928 = clamp(_10284, 0.0, 1.0) * 7.0;
        float _8930 = floor(_8928);
        highp float _8949 = _9017.x;
        _10298 = mix(textureLod(prefiltered_radiance, vec2(_8949, (_8930 + _8924) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_8949, (min(_8930 + 1.0, 7.0) + _8924) * 0.125), 0.0).xyz, vec3(_8928 - _8930));
        break;
    } while(false);
    hp_copy_10298 = _10298;
    highp vec3 _10304 = vec3(0.0);
    if (frag_info.radiance_blend.x > 1000000015047466219876688855040.0)
    {
        highp vec3 hp_copy_10299 = vec3(0.0);
        vec3 _10299 = vec3(0.0);
        do
        {
            if (_8914)
            {
                vec2 _9122 = vec2(atan(_5500.z, _5500.x), asin(clamp(_5500.y, -1.0, 1.0)));
                highp vec2 hp_copy_9122 = _9122;
                _10299 = textureLod(prefiltered_radiance_b, (hp_copy_9122 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_10284, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9141 = vec2(atan(_5500.z, _5500.x), asin(clamp(_5500.y, -1.0, 1.0)));
            highp vec2 hp_copy_9141 = _9141;
            highp vec2 _9146 = (hp_copy_9141 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9053 = clamp(_9146.y, 0.00390625, 0.99609375);
            float _9057 = clamp(_10284, 0.0, 1.0) * 7.0;
            float _9059 = floor(_9057);
            highp float _9078 = _9146.x;
            _10299 = mix(textureLod(prefiltered_radiance_b, vec2(_9078, (_9059 + _9053) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance_b, vec2(_9078, (min(_9059 + 1.0, 7.0) + _9053) * 0.125), 0.0).xyz, vec3(_9057 - _9059));
            break;
        } while(false);
        hp_copy_10299 = _10299;
        _10304 = hp_copy_10298 + hp_copy_10299;
    }
    else
    {
        _10304 = _10298;
    }
    float _5518 = frag_info.environment_intensity;
    highp float hp_copy_5518 = _5518;
    vec2 _5531 = clamp(vec2(_5289, _10284), vec2(0.0), vec2(0.9900000095367431640625));
    vec4 _5533 = texture(brdf_lut, vec2(_5531.x * 0.3333333432674407958984375, _5531.y));
    float _5537 = _5533.x;
    float _5540 = _5533.y;
    vec3 _5542 = ((_5281 + ((max(vec3(1.0 - _10284), _5281) - _5281) * pow(clamp(1.0 - _5289, 0.0, 1.0), 5.0))) * _5537) + vec3(_5540);
    float _5548 = 1.0 - (_5537 + _5540);
    vec3 _5552 = vec3(1.0) - _5281;
    vec3 _5555 = _5281 + (_5552 * vec3(0.0476190485060214996337890625));
    vec3 _5566 = ((_5542 * _5548) * _5555) / (vec3(1.0) - (_5555 * _5548));
    float _5569 = 1.0 - _4382;
    float _10318 = 0.0;
    if (frag_info.ssao_params.y > 0.5)
    {
        _10318 = clamp((pow(_5285 + _10313, exp2(((-16.0) * _10284) - 1.0)) - 1.0) + _10313, 0.0, 1.0);
    }
    else
    {
        _10318 = _10313;
    }
    highp vec3 _10351 = vec3(0.0);
    if (_5237)
    {
        highp vec3 _10335 = vec3(0.0);
        highp vec3 _10336 = vec3(0.0);
        do
        {
            float _9235 = max(dot(_10236, _10327), 0.0);
            highp float hp_copy_9235 = _9235;
            if (_9235 <= 0.0)
            {
                _10336 = vec3(0.0);
                _10335 = vec3(0.0);
                break;
            }
            float _9241 = max(_5285, 9.9999997473787516355514526367188e-05);
            highp float hp_copy_9241 = _9241;
            vec3 _9244 = _10327 + mp_copy_10295;
            float _9247 = dot(_9244, _9244);
            vec3 _10333 = vec3(0.0);
            vec3 _10334 = vec3(0.0);
            if (_9247 > 9.9999999392252902907785028219223e-09)
            {
                vec3 _9255 = _9244 * inversesqrt(_9247);
                float _10332 = 0.0;
                do
                {
                    float _9312 = dot(_10236, _9255);
                    if (_9312 <= 0.0)
                    {
                        _10332 = 0.0;
                        break;
                    }
                    float _9319 = _10284 * _10284;
                    vec3 _9322 = cross(_10236, _9255);
                    float _9325 = _9312 * _9319;
                    float _9334 = _9319 / (dot(_9322, _9322) + (_9325 * _9325));
                    _10332 = min((_9334 * _9334) * 0.3183098733425140380859375, 65504.0);
                    break;
                } while(false);
                vec3 _9372 = _5281 + (_5552 * pow(clamp(1.0 - max(dot(_9255, _10295), 0.0), 0.0, 1.0), 5.0));
                _10334 = (_9372 * min(_10332 * (0.5 / max(mix((2.0 * hp_copy_9235) * _9241, hp_copy_9235 + hp_copy_9241, hp_copy_10284 * hp_copy_10284), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                _10333 = _9372;
            }
            else
            {
                _10334 = vec3(0.0);
                _10333 = _5281;
            }
            _10336 = (_10334 * frag_info.directional_light_color.xyz) * _9235;
            _10335 = (((((vec3(1.0) - _10333) * _5569) * _5212) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _9235;
            break;
        } while(false);
        _10351 = _10341 + ((_10335 + _10336) * _5272);
    }
    else
    {
        _10351 = _10341;
    }
    bool _5660 = _FogInfo.params0.y > 0.5;
    bool _5666 = false;
    if (_5660)
    {
        _5666 = _FogInfo.params0.w > 0.0;
    }
    else
    {
        _5666 = _5660;
    }
    highp vec3 _10354 = vec3(0.0);
    if (_5666)
    {
        vec3 mp_copy_10352 = vec3(0.0);
        highp vec3 _10352 = vec3(0.0);
        if (_7574)
        {
            _10352 = -view_info.camera_forward.xyz;
        }
        else
        {
            _10352 = normalize(v_viewvector);
        }
        highp vec3 hp_copy_10353 = vec3(0.0);
        mp_copy_10352 = _10352;
        vec3 _5671 = _5489 * (-mp_copy_10352);
        vec3 _10353 = vec3(0.0);
        do
        {
            if (_8914)
            {
                vec2 _9494 = vec2(atan(_5671.z, _5671.x), asin(clamp(_5671.y, -1.0, 1.0)));
                highp vec2 hp_copy_9494 = _9494;
                _10353 = textureLod(prefiltered_radiance, (hp_copy_9494 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                break;
            }
            vec2 _9513 = vec2(atan(_5671.z, _5671.x), asin(clamp(_5671.y, -1.0, 1.0)));
            highp vec2 hp_copy_9513 = _9513;
            highp vec2 _9518 = (hp_copy_9513 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9425 = clamp(_9518.y, 0.00390625, 0.99609375);
            float _9431 = floor(0.0);
            highp float _9450 = _9518.x;
            _10353 = mix(textureLod(prefiltered_radiance, vec2(_9450, (_9431 + _9425) * 0.125), 0.0).xyz, textureLod(prefiltered_radiance, vec2(_9450, (min(_9431 + 1.0, 7.0) + _9425) * 0.125), 0.0).xyz, vec3(-_9431));
            break;
        } while(false);
        hp_copy_10353 = _10353;
        _10354 = hp_copy_10353 * hp_copy_5518;
    }
    else
    {
        _10354 = _FogInfo.color.xyz;
    }
    highp vec4 _5686 = vec4(min(((((((_5566 + ((_5212 * _5569) * ((vec3(1.0) - _5542) - _5566))) * (hp_copy_5503 * hp_copy_5518)) * vec3(_4416)) + (((_5542 * (_10304 * _5518)) * 1.0) * _10318)) * mix(1.0, _5272, frag_info.radiance_blend.y)) + (_10351 * mix(1.0, _10313, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _10259, vec3(65504.0)), 1.0) * _10740;
    highp vec4 _10369 = vec4(0.0);
    do
    {
        if (_FogInfo.params0.y < 0.5)
        {
            _10369 = _5686;
            break;
        }
        int _9562 = int(_FogInfo.params0.x + 0.5);
        if (_9562 == 0)
        {
            _10369 = _5686;
            break;
        }
        highp float _10356 = 0.0;
        if (_7574)
        {
            _10356 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
        }
        else
        {
            _10356 = length(v_viewvector);
        }
        if ((_FogInfo.params1.w > 0.0) && (_10356 > _FogInfo.params1.w))
        {
            _10369 = _5686;
            break;
        }
        float _10360 = 0.0;
        if (_9562 == 1)
        {
            _10360 = clamp((_10356 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
        }
        else
        {
            float _10361 = 0.0;
            if (_9562 == 2)
            {
                highp float _10359 = 0.0;
                if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                {
                    highp vec3 _10357 = vec3(0.0);
                    if (_7574)
                    {
                        _10357 = v_position - (view_info.camera_forward.xyz * _10356);
                    }
                    else
                    {
                        _10357 = v_position + v_viewvector;
                    }
                    highp float _9653 = -_FogInfo.params2.y;
                    highp float _9660 = _FogInfo.params1.x * exp(_9653 * (_10357.y - _FogInfo.params2.x));
                    highp float _9677 = _FogInfo.params2.y * (v_position.y - _10357.y);
                    highp float _10358 = 0.0;
                    if (abs(_9677) > 0.00124999997206032276153564453125)
                    {
                        _10358 = (_9660 - (_FogInfo.params1.x * exp(_9653 * (v_position.y - _FogInfo.params2.x)))) / _9677;
                    }
                    else
                    {
                        _10358 = _9660;
                    }
                    _10359 = _10358 * max(_10356 - _FogInfo.params1.y, 0.0);
                }
                else
                {
                    _10359 = _FogInfo.params1.x * max(_10356 - _FogInfo.params1.y, 0.0);
                }
                _10361 = 1.0 - exp(-_10359);
            }
            else
            {
                highp float _9615 = _FogInfo.params1.x * max(_10356 - _FogInfo.params1.y, 0.0);
                _10361 = 1.0 - exp((-_9615) * _9615);
            }
            _10360 = _10361;
        }
        highp float _9717 = min(_10360, _FogInfo.params0.z);
        if (_9717 <= 0.0)
        {
            _10369 = _5686;
            break;
        }
        highp vec3 _9730 = mix(_FogInfo.color.xyz, _10354, vec3(_FogInfo.params0.w));
        bool _9733 = _FogInfo.sun.w > 0.5;
        bool _9739 = false;
        if (_9733)
        {
            _9739 = _FogInfo.params2.z > 0.0;
        }
        else
        {
            _9739 = _9733;
        }
        vec3 _10365 = vec3(0.0);
        if (_9739)
        {
            vec3 mp_copy_10362 = vec3(0.0);
            highp vec3 _10362 = vec3(0.0);
            if (_7574)
            {
                _10362 = -view_info.camera_forward.xyz;
            }
            else
            {
                _10362 = normalize(v_viewvector);
            }
            mp_copy_10362 = _10362;
            highp float _9755 = pow(max(dot(-mp_copy_10362, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
            float mp_copy_9755 = _9755;
            _10365 = _9730 + ((_FogInfo.sun.xyz * mp_copy_9755) * _FogInfo.params2.z);
        }
        else
        {
            _10365 = _9730;
        }
        highp float _9768 = _5686.w;
        float mp_copy_9768 = _9768;
        _10369 = vec4(mix(_5686.xyz, _10365 * mp_copy_9768, vec3(_9717)), _9768);
        break;
    } while(false);
    vec4 _10371 = vec4(0.0);
    do
    {
        if (view_info.camera_forward.w < (-1.0))
        {
            _10371 = vec4(view_info.camera_forward.xyz, 0.0);
            break;
        }
        _10371 = _10369;
        break;
    } while(false);
    frag_color = _10371;
    float _10372 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _10372 = 1.0;
    }
    else
    {
        _10372 = abs(frag_info.fade);
    }
    frag_color *= _10372;
}

