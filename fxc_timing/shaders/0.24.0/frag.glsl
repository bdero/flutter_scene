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
    highp float _7170 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_7170 = _7170;
    vec3 _7172 = normalize(v_normal);
    vec3 _7174 = _7172 * mp_copy_7170;
    vec4 _7215 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _7218 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _30983 = vec2(0.0);
    if (_7218)
    {
        highp vec2 _30982 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _30982 = v_texture_coords_1;
        }
        else
        {
            _30982 = v_texture_coords;
        }
        highp vec2 _7405 = _30982 * texture_transforms.base_color_transform.zw;
        highp float _7411 = _7405.x;
        highp float _7416 = _7405.y;
        _30983 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _7411) - (texture_transforms.base_color_rotation.y * _7416), (texture_transforms.base_color_rotation.y * _7411) + (texture_transforms.base_color_rotation.x * _7416));
    }
    else
    {
        _30983 = v_texture_coords;
    }
    vec4 _7232 = texture(base_color_texture, _30983);
    vec3 _7234 = _7232.xyz;
    vec3 _7242 = (mix(_7234 * vec3(0.077399380505084991455078125), pow((_7234 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7234)) * _7215.xyz) * frag_info.color.xyz;
    float _35429 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_7232.w * _7215.w) * frag_info.color.w);
    float _7258 = _7242.x;
    float _7259 = _7242.y;
    float _7260 = _7242.z;
    vec4 _7261 = vec4(_7258, _7259, _7260, _35429);
    vec3 _30995 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _30986 = vec2(0.0);
        if (_7218)
        {
            highp vec2 _30985 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _30985 = v_texture_coords_1;
            }
            else
            {
                _30985 = v_texture_coords;
            }
            highp vec2 _7499 = _30985 * texture_transforms.normal_transform.zw;
            highp float _7505 = _7499.x;
            highp float _7510 = _7499.y;
            _30986 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _7505) - (texture_transforms.normal_rotation.y * _7510), (texture_transforms.normal_rotation.y * _7505) + (texture_transforms.normal_rotation.x * _7510));
        }
        else
        {
            _30986 = v_texture_coords;
        }
        vec3 _7557 = ((texture(normal_texture, _30986).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _7561 = _7557.xy * vec2(frag_info.normal_scale);
        vec3 _29894 = _7557;
        _29894.x = _7561.x;
        _29894.y = _7561.y;
        highp vec3 _7567 = -v_viewvector;
        mat3 _30994 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _7597 = v_tangent.xyz - (_7174 * dot(_7174, v_tangent.xyz));
            highp float _7600 = dot(_7597, _7597);
            bool _7602 = _7600 <= 1.0000000133514319600180897396058e-10;
            bool _7610 = false;
            if (!_7602)
            {
                _7610 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _7610 = _7602;
            }
            if (_7610)
            {
                highp vec2 _7668 = dFdx(_30986);
                highp vec2 _7670 = dFdy(_30986);
                bvec2 _35431 = bvec2(length(_7668) == 0.0);
                highp vec2 _35432 = vec2(_35431.x ? vec2(1.0, 0.0).x : _7668.x, _35431.y ? vec2(1.0, 0.0).y : _7668.y);
                bvec2 _35433 = bvec2(length(_7670) == 0.0);
                highp vec2 _35434 = vec2(_35433.x ? vec2(0.0, 1.0).x : _7670.x, _35433.y ? vec2(0.0, 1.0).y : _7670.y);
                highp vec3 _7683 = cross(dFdy(_7567), _7174);
                highp vec3 _7686 = cross(_7174, dFdx(_7567));
                highp vec3 _7695 = (_7683 * _35432.x) + (_7686 * _35434.x);
                highp vec3 _7704 = (_7683 * _35432.y) + (_7686 * _35434.y);
                highp float _7713 = inversesqrt(max(max(dot(_7695, _7695), dot(_7704, _7704)), 9.9999996826552253889678874634872e-21));
                _30994 = mat3(_7695 * _7713, _7704 * _7713, _7174);
                break;
            }
            highp vec3 _7620 = _7597 * inversesqrt(_7600);
            _30994 = mat3(_7620, normalize(cross(_7174, _7620)) * sign(v_tangent.w), _7174);
            break;
        } while(false);
        _30995 = normalize(_30994 * _29894);
    }
    else
    {
        _30995 = _7174;
    }
    highp vec2 _30997 = vec2(0.0);
    if (_7218)
    {
        highp vec2 _30996 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _30996 = v_texture_coords_1;
        }
        else
        {
            _30996 = v_texture_coords;
        }
        highp vec2 _7775 = _30996 * texture_transforms.metallic_roughness_transform.zw;
        highp float _7781 = _7775.x;
        highp float _7786 = _7775.y;
        _30997 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _7781) - (texture_transforms.metallic_roughness_rotation.y * _7786), (texture_transforms.metallic_roughness_rotation.y * _7781) + (texture_transforms.metallic_roughness_rotation.x * _7786));
    }
    else
    {
        _30997 = v_texture_coords;
    }
    vec4 _7301 = texture(metallic_roughness_texture, _30997);
    float _7307 = clamp(_7301.z * frag_info.metallic_factor, 0.0, 1.0);
    float _7314 = clamp(_7301.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _30999 = vec2(0.0);
    if (_7218)
    {
        highp vec2 _30998 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _30998 = v_texture_coords_1;
        }
        else
        {
            _30998 = v_texture_coords;
        }
        highp vec2 _7845 = _30998 * texture_transforms.occlusion_transform.zw;
        highp float _7851 = _7845.x;
        highp float _7856 = _7845.y;
        _30999 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _7851) - (texture_transforms.occlusion_rotation.y * _7856), (texture_transforms.occlusion_rotation.y * _7851) + (texture_transforms.occlusion_rotation.x * _7856));
    }
    else
    {
        _30999 = v_texture_coords;
    }
    vec4 _7329 = texture(occlusion_texture, _30999);
    float _7336 = 1.0 - ((1.0 - _7329.x) * frag_info.occlusion_strength);
    highp vec2 _31001 = vec2(0.0);
    if (_7218)
    {
        highp vec2 _31000 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _31000 = v_texture_coords_1;
        }
        else
        {
            _31000 = v_texture_coords;
        }
        highp vec2 _7915 = _31000 * texture_transforms.emissive_transform.zw;
        highp float _7921 = _7915.x;
        highp float _7926 = _7915.y;
        _31001 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _7921) - (texture_transforms.emissive_rotation.y * _7926), (texture_transforms.emissive_rotation.y * _7921) + (texture_transforms.emissive_rotation.x * _7926));
    }
    else
    {
        _31001 = v_texture_coords;
    }
    vec4 _7351 = texture(emissive_texture, _31001);
    vec3 _7352 = _7351.xyz;
    vec3 _7360 = (mix(_7352 * vec3(0.077399380505084991455078125), pow((_7352 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7352)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w;
    float _31031 = 0.0;
    do
    {
        if (debug_view_info.view.x < 0.5)
        {
            _31031 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _31031 = 1.0;
            break;
        }
        _31031 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    if (_31031 > 2.5)
    {
        vec4 _34197 = vec4(0.0);
        do
        {
            if (debug_view_info.view.x < 20.0)
            {
                vec3 _34183 = vec3(0.0);
                if (debug_view_info.view.x == 1.0)
                {
                    float _8400 = length(_7174);
                    vec3 _34181 = vec3(0.0);
                    if (_8400 > 9.9999999747524270787835121154785e-07)
                    {
                        _34181 = _7174 / vec3(_8400);
                    }
                    else
                    {
                        _34181 = vec3(0.0);
                    }
                    _34183 = ((_34181 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                }
                else
                {
                    vec3 _34184 = vec3(0.0);
                    if (debug_view_info.view.x == 2.0)
                    {
                        float _8423 = length(_30995);
                        vec3 _34179 = vec3(0.0);
                        if (_8423 > 9.9999999747524270787835121154785e-07)
                        {
                            _34179 = _30995 / vec3(_8423);
                        }
                        else
                        {
                            _34179 = vec3(0.0);
                        }
                        _34184 = ((_34179 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                    }
                    else
                    {
                        vec3 _34185 = vec3(0.0);
                        if (debug_view_info.view.x == 3.0)
                        {
                            float _8446 = length(v_tangent.xyz);
                            vec3 _34177 = vec3(0.0);
                            if (_8446 > 9.9999999747524270787835121154785e-07)
                            {
                                _34177 = v_tangent.xyz / vec3(_8446);
                            }
                            else
                            {
                                _34177 = vec3(0.0);
                            }
                            _34185 = ((_34177 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _34186 = vec3(0.0);
                            if (debug_view_info.view.x == 4.0)
                            {
                                highp float _8079 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_8079 = _8079;
                                vec3 _8080 = cross(_7172, v_tangent.xyz) * mp_copy_8079;
                                float _8469 = length(_8080);
                                vec3 _34175 = vec3(0.0);
                                if (_8469 > 9.9999999747524270787835121154785e-07)
                                {
                                    _34175 = _8080 / vec3(_8469);
                                }
                                else
                                {
                                    _34175 = vec3(0.0);
                                }
                                _34186 = ((_34175 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _34187 = vec3(0.0);
                                if (debug_view_info.view.x == 5.0)
                                {
                                    _34187 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _34188 = vec3(0.0);
                                    if (debug_view_info.view.x == 6.0)
                                    {
                                        _34188 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec3 _34189 = vec3(0.0);
                                        if (debug_view_info.view.x == 7.0)
                                        {
                                            _34189 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                        }
                                        else
                                        {
                                            vec3 _34190 = vec3(0.0);
                                            if (debug_view_info.view.x == 8.0)
                                            {
                                                vec3 _8504 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                _34190 = mix(_8504 * 12.9200000762939453125, (pow(max(_8504, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _8504));
                                            }
                                            else
                                            {
                                                vec3 _34191 = vec3(0.0);
                                                if (debug_view_info.view.x == 9.0)
                                                {
                                                    vec3 mp_copy_34171 = vec3(0.0);
                                                    highp vec3 _34171 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _34171 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _34171 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_34171 = _34171;
                                                    float _8540 = length(mp_copy_34171);
                                                    vec3 _34172 = vec3(0.0);
                                                    if (_8540 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _34172 = mp_copy_34171 / vec3(_8540);
                                                    }
                                                    else
                                                    {
                                                        _34172 = vec3(0.0);
                                                    }
                                                    _34191 = ((_34172 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                }
                                                else
                                                {
                                                    vec3 _34192 = vec3(0.0);
                                                    if (debug_view_info.view.x == 10.0)
                                                    {
                                                        float _8583 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                        float _8584 = (v_position.x - debug_view_info.params.x) / _8583;
                                                        bool _8588 = debug_view_info.view.w > 1.5;
                                                        float _34155 = 0.0;
                                                        if (_8588)
                                                        {
                                                            _34155 = fract(_8584);
                                                        }
                                                        else
                                                        {
                                                            float _34156 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34156 = ((_8584 < 0.0) || (_8584 > 1.0)) ? 0.0 : _8584;
                                                            }
                                                            else
                                                            {
                                                                _34156 = clamp(_8584, 0.0, 1.0);
                                                            }
                                                            _34155 = _34156;
                                                        }
                                                        float _8635 = (v_position.y - debug_view_info.params.x) / _8583;
                                                        float _34161 = 0.0;
                                                        if (_8588)
                                                        {
                                                            _34161 = fract(_8635);
                                                        }
                                                        else
                                                        {
                                                            float _34162 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34162 = ((_8635 < 0.0) || (_8635 > 1.0)) ? 0.0 : _8635;
                                                            }
                                                            else
                                                            {
                                                                _34162 = clamp(_8635, 0.0, 1.0);
                                                            }
                                                            _34161 = _34162;
                                                        }
                                                        float _8686 = (v_position.z - debug_view_info.params.x) / _8583;
                                                        float _34167 = 0.0;
                                                        if (_8588)
                                                        {
                                                            _34167 = fract(_8686);
                                                        }
                                                        else
                                                        {
                                                            float _34168 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34168 = ((_8686 < 0.0) || (_8686 > 1.0)) ? 0.0 : _8686;
                                                            }
                                                            else
                                                            {
                                                                _34168 = clamp(_8686, 0.0, 1.0);
                                                            }
                                                            _34167 = _34168;
                                                        }
                                                        _34192 = vec3(_34155 * debug_view_info.view.z, _34161 * debug_view_info.view.z, _34167 * debug_view_info.view.z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _34193 = vec3(0.0);
                                                        if (debug_view_info.view.x == 11.0)
                                                        {
                                                            bvec3 _8155 = bvec3(gl_FrontFacing);
                                                            _34193 = vec3(_8155.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _8155.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _8155.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _34194 = vec3(0.0);
                                                            if (debug_view_info.view.x == 12.0)
                                                            {
                                                                highp vec2 _8713 = v_texture_coords;
                                                                vec2 mp_copy_8713 = _8713;
                                                                vec2 _8725 = floor(mp_copy_8713 * 8.0);
                                                                float _8727 = _8725.x;
                                                                float _8729 = _8725.y;
                                                                float _8737 = _8727 + (_8729 * 8.0);
                                                                vec2 _8746 = step(vec2(0.0), mp_copy_8713) * step(mp_copy_8713, vec2(1.0));
                                                                _34194 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_8727 + _8729, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_8737 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_8737 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_8746.x * _8746.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _34195 = vec3(0.0);
                                                                if (debug_view_info.view.x == 13.0)
                                                                {
                                                                    highp vec2 _8796 = v_texture_coords_1;
                                                                    vec2 mp_copy_8796 = _8796;
                                                                    vec2 _8808 = floor(mp_copy_8796 * 8.0);
                                                                    float _8810 = _8808.x;
                                                                    float _8812 = _8808.y;
                                                                    float _8820 = _8810 + (_8812 * 8.0);
                                                                    vec2 _8829 = step(vec2(0.0), mp_copy_8796) * step(mp_copy_8796, vec2(1.0));
                                                                    _34195 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_8810 + _8812, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_8820 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_8820 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_8829.x * _8829.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _34196 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 14.0)
                                                                    {
                                                                        highp float _8895 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _8901 = debug_view_info.depth.x > 0.5;
                                                                        bool _8907 = false;
                                                                        if (_8901)
                                                                        {
                                                                            _8907 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _8907 = _8901;
                                                                        }
                                                                        highp float _34141 = 0.0;
                                                                        if (_8907)
                                                                        {
                                                                            _34141 = 1.1920928955078125e-07 / _8895;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _34142 = 0.0;
                                                                            if (_8901)
                                                                            {
                                                                                _34142 = 5.9604644775390625e-08 / (_8895 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _34142 = 5.9604644775390625e-08 / (_8895 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _34141 = _34142;
                                                                        }
                                                                        highp float _8936 = dot(_7174, view_info.camera_forward.xyz);
                                                                        highp float _8942 = sqrt(max(1.0 - (_8936 * _8936), 0.0));
                                                                        highp float _34139 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _34139 = (debug_view_info.depth.z * _8942) / max(abs(_8936), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _34139 = (((1.0 / (_8895 * _8895)) * debug_view_info.depth.z) * _8942) / max(abs(dot(_7174, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _8980 = log2(max(max(8.0 * _34141, _34139 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_8980 = _8980;
                                                                        float _9019 = (mp_copy_8980 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                        float _34151 = 0.0;
                                                                        if (debug_view_info.view.w > 1.5)
                                                                        {
                                                                            _34151 = fract(_9019);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _34152 = 0.0;
                                                                            if (debug_view_info.view.w > 0.5)
                                                                            {
                                                                                _34152 = ((_9019 < 0.0) || (_9019 > 1.0)) ? 0.0 : _9019;
                                                                            }
                                                                            else
                                                                            {
                                                                                _34152 = clamp(_9019, 0.0, 1.0);
                                                                            }
                                                                            _34151 = _34152;
                                                                        }
                                                                        _34196 = clamp(vec3(1.5) - abs(vec3(4.0 * _34151) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _9052 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _34196 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9052.x + _9052.y, 2.0)));
                                                                    }
                                                                    _34195 = _34196;
                                                                }
                                                                _34194 = _34195;
                                                            }
                                                            _34193 = _34194;
                                                        }
                                                        _34192 = _34193;
                                                    }
                                                    _34191 = _34192;
                                                }
                                                _34190 = _34191;
                                            }
                                            _34189 = _34190;
                                        }
                                        _34188 = _34189;
                                    }
                                    _34187 = _34188;
                                }
                                _34186 = _34187;
                            }
                            _34185 = _34186;
                        }
                        _34184 = _34185;
                    }
                    _34183 = _34184;
                }
                _34197 = vec4(_34183, 1.0);
                break;
            }
            vec3 _34118 = vec3(0.0);
            if (debug_view_info.view.x < 40.0)
            {
                vec3 _34119 = vec3(0.0);
                if (debug_view_info.view.x == 20.0)
                {
                    vec3 _9073 = max(_7261.xyz * debug_view_info.view.z, vec3(0.0));
                    _34119 = mix(_9073 * 12.9200000762939453125, (pow(max(_9073, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _9073));
                }
                else
                {
                    vec3 _34120 = vec3(0.0);
                    if (debug_view_info.view.x == 21.0)
                    {
                        float _9112 = (_35429 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                        float _34114 = 0.0;
                        if (debug_view_info.view.w > 1.5)
                        {
                            _34114 = fract(_9112);
                        }
                        else
                        {
                            float _34115 = 0.0;
                            if (debug_view_info.view.w > 0.5)
                            {
                                _34115 = ((_9112 < 0.0) || (_9112 > 1.0)) ? 0.0 : _9112;
                            }
                            else
                            {
                                _34115 = clamp(_9112, 0.0, 1.0);
                            }
                            _34114 = _34115;
                        }
                        _34120 = vec3(_34114 * debug_view_info.view.z);
                    }
                    else
                    {
                        vec3 _34121 = vec3(0.0);
                        if (debug_view_info.view.x == 22.0)
                        {
                            float _9163 = (_7307 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                            float _34110 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _34110 = fract(_9163);
                            }
                            else
                            {
                                float _34111 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _34111 = ((_9163 < 0.0) || (_9163 > 1.0)) ? 0.0 : _9163;
                                }
                                else
                                {
                                    _34111 = clamp(_9163, 0.0, 1.0);
                                }
                                _34110 = _34111;
                            }
                            _34121 = vec3(_34110 * debug_view_info.view.z);
                        }
                        else
                        {
                            vec3 _34122 = vec3(0.0);
                            if (debug_view_info.view.x == 23.0)
                            {
                                float _9214 = (_7314 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _34106 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _34106 = fract(_9214);
                                }
                                else
                                {
                                    float _34107 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _34107 = ((_9214 < 0.0) || (_9214 > 1.0)) ? 0.0 : _9214;
                                    }
                                    else
                                    {
                                        _34107 = clamp(_9214, 0.0, 1.0);
                                    }
                                    _34106 = _34107;
                                }
                                _34122 = vec3(_34106 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _34123 = vec3(0.0);
                                if (debug_view_info.view.x == 24.0)
                                {
                                    float _9265 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _34102 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _34102 = fract(_9265);
                                    }
                                    else
                                    {
                                        float _34103 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _34103 = ((_9265 < 0.0) || (_9265 > 1.0)) ? 0.0 : _9265;
                                        }
                                        else
                                        {
                                            _34103 = clamp(_9265, 0.0, 1.0);
                                        }
                                        _34102 = _34103;
                                    }
                                    _34123 = vec3(_34102 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _34124 = vec3(0.0);
                                    if (debug_view_info.view.x == 25.0)
                                    {
                                        float _9316 = (_7336 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _34098 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _34098 = fract(_9316);
                                        }
                                        else
                                        {
                                            float _34099 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _34099 = ((_9316 < 0.0) || (_9316 > 1.0)) ? 0.0 : _9316;
                                            }
                                            else
                                            {
                                                _34099 = clamp(_9316, 0.0, 1.0);
                                            }
                                            _34098 = _34099;
                                        }
                                        _34124 = vec3(_34098 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _34125 = vec3(0.0);
                                        if (debug_view_info.view.x == 26.0)
                                        {
                                            vec3 _9352 = max(_7360 * debug_view_info.view.z, vec3(0.0));
                                            _34125 = mix(_9352 * 12.9200000762939453125, (pow(max(_9352, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _9352));
                                        }
                                        else
                                        {
                                            vec2 _9373 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _34125 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9373.x + _9373.y, 2.0)));
                                        }
                                        _34124 = _34125;
                                    }
                                    _34123 = _34124;
                                }
                                _34122 = _34123;
                            }
                            _34121 = _34122;
                        }
                        _34120 = _34121;
                    }
                    _34119 = _34120;
                }
                _34118 = _34119;
            }
            else
            {
                vec3 _34126 = vec3(0.0);
                if (debug_view_info.view.x < 60.0)
                {
                    vec2 _9394 = floor(gl_FragCoord.xy * vec2(0.125));
                    _34126 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9394.x + _9394.y, 2.0)));
                }
                else
                {
                    vec3 _34127 = vec3(0.0);
                    if (debug_view_info.view.x < 70.0)
                    {
                        vec3 _34128 = vec3(0.0);
                        if (debug_view_info.view.x == 60.0)
                        {
                            _34128 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _34129 = vec3(0.0);
                            if (debug_view_info.view.x == 61.0)
                            {
                                _34129 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec2 _9482 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34129 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9482.x + _9482.y, 2.0)));
                            }
                            _34128 = _34129;
                        }
                        _34127 = _34128;
                    }
                    else
                    {
                        vec3 _34130 = vec3(0.0);
                        if (debug_view_info.view.x < 80.0)
                        {
                            vec3 _34131 = vec3(0.0);
                            if (debug_view_info.view.x == 70.0)
                            {
                                bool _9499 = v_texture_coords.x < 0.0;
                                bool _9506 = false;
                                if (!_9499)
                                {
                                    _9506 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _9506 = _9499;
                                }
                                bool _9513 = false;
                                if (!_9506)
                                {
                                    _9513 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _9513 = _9506;
                                }
                                bool _9520 = false;
                                if (!_9513)
                                {
                                    _9520 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _9520 = _9513;
                                }
                                bvec3 _9523 = bvec3(_9520);
                                highp vec3 _9524 = vec3(_9523.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _9523.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _9523.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _9549 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                highp vec3 _9550 = vec3(_9549.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _9524.x, _9549.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _9524.y, _9549.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _9524.z);
                                float _9564 = length(v_normal);
                                bvec3 _9571 = bvec3((_9564 < 0.300000011920928955078125) || (_9564 > 1.7000000476837158203125));
                                highp vec3 _9572 = vec3(_9571.x ? vec3(1.0, 0.5, 0.0).x : _9550.x, _9571.y ? vec3(1.0, 0.5, 0.0).y : _9550.y, _9571.z ? vec3(1.0, 0.5, 0.0).z : _9550.z);
                                bool _9577 = _7307 > 0.0500000007450580596923828125;
                                bool _9583 = false;
                                if (_9577)
                                {
                                    _9583 = _7307 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _9583 = _9577;
                                }
                                vec3 _9595 = vec3(0.0);
                                bvec3 _9585 = bvec3(_9583);
                                highp vec3 _9586 = vec3(_9585.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _9572.x, _9585.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _9572.y, _9585.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _9572.z);
                                vec3 _34096 = vec3(0.0);
                                do
                                {
                                    _9595 = _7261.xyz;
                                    float _9596 = dot(_9595, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7307 > 0.5)
                                    {
                                        _34096 = _9586;
                                        break;
                                    }
                                    if (_9596 < 0.0130000002682209014892578125)
                                    {
                                        _34096 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_9596 > 0.87000000476837158203125)
                                    {
                                        _34096 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _34096 = _9586;
                                    break;
                                } while(false);
                                vec3 _34097 = vec3(0.0);
                                do
                                {
                                    vec3 _9641 = ((_9595 + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                    bool _9656 = min(min(_7258, _7259), _7260) < 0.0;
                                    bool _9669 = false;
                                    if (!_9656)
                                    {
                                        _9669 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                    }
                                    else
                                    {
                                        _9669 = _9656;
                                    }
                                    if (any(isnan(_9641)))
                                    {
                                        _34097 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_9641)))
                                    {
                                        _34097 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_9669)
                                    {
                                        _34097 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _34097 = _34096;
                                    break;
                                } while(false);
                                _34131 = _34097;
                            }
                            else
                            {
                                vec3 _34132 = vec3(0.0);
                                if (debug_view_info.view.x == 71.0)
                                {
                                    vec3 _34095 = vec3(0.0);
                                    do
                                    {
                                        vec3 _9709 = ((_7261.xyz + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                        bool _9724 = min(min(_7258, _7259), _7260) < 0.0;
                                        bool _9737 = false;
                                        if (!_9724)
                                        {
                                            _9737 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                        }
                                        else
                                        {
                                            _9737 = _9724;
                                        }
                                        if (any(isnan(_9709)))
                                        {
                                            _34095 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_9709)))
                                        {
                                            _34095 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_9737)
                                        {
                                            _34095 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _34095 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _34132 = _34095;
                                }
                                else
                                {
                                    vec3 _34133 = vec3(0.0);
                                    if (debug_view_info.view.x == 72.0)
                                    {
                                        vec3 _34094 = vec3(0.0);
                                        do
                                        {
                                            float _9759 = dot(_7261.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7307 > 0.5)
                                            {
                                                _34094 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_9759 < 0.0130000002682209014892578125)
                                            {
                                                _34094 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_9759 > 0.87000000476837158203125)
                                            {
                                                _34094 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _34094 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _34133 = _34094;
                                    }
                                    else
                                    {
                                        vec3 _34134 = vec3(0.0);
                                        if (debug_view_info.view.x == 73.0)
                                        {
                                            bool _9781 = _7307 > 0.0500000007450580596923828125;
                                            bool _9787 = false;
                                            if (_9781)
                                            {
                                                _9787 = _7307 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _9787 = _9781;
                                            }
                                            bvec3 _9789 = bvec3(_9787);
                                            _34134 = vec3(_9789.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _9789.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _9789.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _34135 = vec3(0.0);
                                            if (debug_view_info.view.x == 74.0)
                                            {
                                                float _9795 = length(v_normal);
                                                bvec3 _9802 = bvec3((_9795 < 0.300000011920928955078125) || (_9795 > 1.7000000476837158203125));
                                                _34135 = vec3(_9802.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _9802.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _9802.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _34136 = vec3(0.0);
                                                if (debug_view_info.view.x == 75.0)
                                                {
                                                    bvec3 _9825 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                                    _34136 = vec3(_9825.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _9825.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _9825.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _34137 = vec3(0.0);
                                                    if (debug_view_info.view.x == 76.0)
                                                    {
                                                        bool _9843 = v_texture_coords.x < 0.0;
                                                        bool _9850 = false;
                                                        if (!_9843)
                                                        {
                                                            _9850 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _9850 = _9843;
                                                        }
                                                        bool _9857 = false;
                                                        if (!_9850)
                                                        {
                                                            _9857 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _9857 = _9850;
                                                        }
                                                        bool _9864 = false;
                                                        if (!_9857)
                                                        {
                                                            _9864 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _9864 = _9857;
                                                        }
                                                        bvec3 _9867 = bvec3(_9864);
                                                        _34137 = vec3(_9867.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _9867.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _9867.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _9880 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _34137 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9880.x + _9880.y, 2.0)));
                                                    }
                                                    _34136 = _34137;
                                                }
                                                _34135 = _34136;
                                            }
                                            _34134 = _34135;
                                        }
                                        _34133 = _34134;
                                    }
                                    _34132 = _34133;
                                }
                                _34131 = _34132;
                            }
                            _34130 = _34131;
                        }
                        else
                        {
                            vec3 _34138 = vec3(0.0);
                            if (debug_view_info.view.x == 80.0)
                            {
                                _34138 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _9898 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34138 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_9898.x + _9898.y, 2.0)));
                            }
                            _34130 = _34138;
                        }
                        _34127 = _34130;
                    }
                    _34126 = _34127;
                }
                _34118 = _34126;
            }
            _34197 = vec4(_34118, 1.0);
            break;
        } while(false);
        vec4 _34925 = vec4(0.0);
        do
        {
            if (debug_view_info.left.x < 20.0)
            {
                vec3 _34911 = vec3(0.0);
                if (debug_view_info.left.x == 1.0)
                {
                    float _10333 = length(_7174);
                    vec3 _34909 = vec3(0.0);
                    if (_10333 > 9.9999999747524270787835121154785e-07)
                    {
                        _34909 = _7174 / vec3(_10333);
                    }
                    else
                    {
                        _34909 = vec3(0.0);
                    }
                    _34911 = ((_34909 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                }
                else
                {
                    vec3 _34912 = vec3(0.0);
                    if (debug_view_info.left.x == 2.0)
                    {
                        float _10356 = length(_30995);
                        vec3 _34907 = vec3(0.0);
                        if (_10356 > 9.9999999747524270787835121154785e-07)
                        {
                            _34907 = _30995 / vec3(_10356);
                        }
                        else
                        {
                            _34907 = vec3(0.0);
                        }
                        _34912 = ((_34907 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                    }
                    else
                    {
                        vec3 _34913 = vec3(0.0);
                        if (debug_view_info.left.x == 3.0)
                        {
                            float _10379 = length(v_tangent.xyz);
                            vec3 _34905 = vec3(0.0);
                            if (_10379 > 9.9999999747524270787835121154785e-07)
                            {
                                _34905 = v_tangent.xyz / vec3(_10379);
                            }
                            else
                            {
                                _34905 = vec3(0.0);
                            }
                            _34913 = ((_34905 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                        }
                        else
                        {
                            vec3 _34914 = vec3(0.0);
                            if (debug_view_info.left.x == 4.0)
                            {
                                highp float _10012 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_10012 = _10012;
                                vec3 _10013 = cross(_7172, v_tangent.xyz) * mp_copy_10012;
                                float _10402 = length(_10013);
                                vec3 _34903 = vec3(0.0);
                                if (_10402 > 9.9999999747524270787835121154785e-07)
                                {
                                    _34903 = _10013 / vec3(_10402);
                                }
                                else
                                {
                                    _34903 = vec3(0.0);
                                }
                                _34914 = ((_34903 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                            }
                            else
                            {
                                vec3 _34915 = vec3(0.0);
                                if (debug_view_info.left.x == 5.0)
                                {
                                    _34915 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _34916 = vec3(0.0);
                                    if (debug_view_info.left.x == 6.0)
                                    {
                                        _34916 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.left.y;
                                    }
                                    else
                                    {
                                        vec3 _34917 = vec3(0.0);
                                        if (debug_view_info.left.x == 7.0)
                                        {
                                            _34917 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.left.y;
                                        }
                                        else
                                        {
                                            vec3 _34918 = vec3(0.0);
                                            if (debug_view_info.left.x == 8.0)
                                            {
                                                vec3 _10437 = max(v_color.xyz * debug_view_info.left.y, vec3(0.0));
                                                _34918 = mix(_10437 * 12.9200000762939453125, (pow(max(_10437, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _10437));
                                            }
                                            else
                                            {
                                                vec3 _34919 = vec3(0.0);
                                                if (debug_view_info.left.x == 9.0)
                                                {
                                                    vec3 mp_copy_34899 = vec3(0.0);
                                                    highp vec3 _34899 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _34899 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _34899 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_34899 = _34899;
                                                    float _10473 = length(mp_copy_34899);
                                                    vec3 _34900 = vec3(0.0);
                                                    if (_10473 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _34900 = mp_copy_34899 / vec3(_10473);
                                                    }
                                                    else
                                                    {
                                                        _34900 = vec3(0.0);
                                                    }
                                                    _34919 = ((_34900 * 0.5) + vec3(0.5)) * debug_view_info.left.y;
                                                }
                                                else
                                                {
                                                    vec3 _34920 = vec3(0.0);
                                                    if (debug_view_info.left.x == 10.0)
                                                    {
                                                        float _10516 = max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                                        float _10517 = (v_position.x - debug_view_info.left.z) / _10516;
                                                        bool _10521 = debug_view_info.view.w > 1.5;
                                                        float _34883 = 0.0;
                                                        if (_10521)
                                                        {
                                                            _34883 = fract(_10517);
                                                        }
                                                        else
                                                        {
                                                            float _34884 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34884 = ((_10517 < 0.0) || (_10517 > 1.0)) ? 0.0 : _10517;
                                                            }
                                                            else
                                                            {
                                                                _34884 = clamp(_10517, 0.0, 1.0);
                                                            }
                                                            _34883 = _34884;
                                                        }
                                                        float _10568 = (v_position.y - debug_view_info.left.z) / _10516;
                                                        float _34889 = 0.0;
                                                        if (_10521)
                                                        {
                                                            _34889 = fract(_10568);
                                                        }
                                                        else
                                                        {
                                                            float _34890 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34890 = ((_10568 < 0.0) || (_10568 > 1.0)) ? 0.0 : _10568;
                                                            }
                                                            else
                                                            {
                                                                _34890 = clamp(_10568, 0.0, 1.0);
                                                            }
                                                            _34889 = _34890;
                                                        }
                                                        float _10619 = (v_position.z - debug_view_info.left.z) / _10516;
                                                        float _34895 = 0.0;
                                                        if (_10521)
                                                        {
                                                            _34895 = fract(_10619);
                                                        }
                                                        else
                                                        {
                                                            float _34896 = 0.0;
                                                            if (debug_view_info.view.w > 0.5)
                                                            {
                                                                _34896 = ((_10619 < 0.0) || (_10619 > 1.0)) ? 0.0 : _10619;
                                                            }
                                                            else
                                                            {
                                                                _34896 = clamp(_10619, 0.0, 1.0);
                                                            }
                                                            _34895 = _34896;
                                                        }
                                                        _34920 = vec3(_34883 * debug_view_info.left.y, _34889 * debug_view_info.left.y, _34895 * debug_view_info.left.y);
                                                    }
                                                    else
                                                    {
                                                        vec3 _34921 = vec3(0.0);
                                                        if (debug_view_info.left.x == 11.0)
                                                        {
                                                            bvec3 _10088 = bvec3(gl_FrontFacing);
                                                            _34921 = vec3(_10088.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _10088.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _10088.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _34922 = vec3(0.0);
                                                            if (debug_view_info.left.x == 12.0)
                                                            {
                                                                highp vec2 _10646 = v_texture_coords;
                                                                vec2 mp_copy_10646 = _10646;
                                                                vec2 _10658 = floor(mp_copy_10646 * 8.0);
                                                                float _10660 = _10658.x;
                                                                float _10662 = _10658.y;
                                                                float _10670 = _10660 + (_10662 * 8.0);
                                                                vec2 _10679 = step(vec2(0.0), mp_copy_10646) * step(mp_copy_10646, vec2(1.0));
                                                                _34922 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_10660 + _10662, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_10670 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_10670 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_10679.x * _10679.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _34923 = vec3(0.0);
                                                                if (debug_view_info.left.x == 13.0)
                                                                {
                                                                    highp vec2 _10729 = v_texture_coords_1;
                                                                    vec2 mp_copy_10729 = _10729;
                                                                    vec2 _10741 = floor(mp_copy_10729 * 8.0);
                                                                    float _10743 = _10741.x;
                                                                    float _10745 = _10741.y;
                                                                    float _10753 = _10743 + (_10745 * 8.0);
                                                                    vec2 _10762 = step(vec2(0.0), mp_copy_10729) * step(mp_copy_10729, vec2(1.0));
                                                                    _34923 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_10743 + _10745, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_10753 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_10753 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_10762.x * _10762.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _34924 = vec3(0.0);
                                                                    if (debug_view_info.left.x == 14.0)
                                                                    {
                                                                        highp float _10828 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _10834 = debug_view_info.depth.x > 0.5;
                                                                        bool _10840 = false;
                                                                        if (_10834)
                                                                        {
                                                                            _10840 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _10840 = _10834;
                                                                        }
                                                                        highp float _34869 = 0.0;
                                                                        if (_10840)
                                                                        {
                                                                            _34869 = 1.1920928955078125e-07 / _10828;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _34870 = 0.0;
                                                                            if (_10834)
                                                                            {
                                                                                _34870 = 5.9604644775390625e-08 / (_10828 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _34870 = 5.9604644775390625e-08 / (_10828 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _34869 = _34870;
                                                                        }
                                                                        highp float _10869 = dot(_7174, view_info.camera_forward.xyz);
                                                                        highp float _10875 = sqrt(max(1.0 - (_10869 * _10869), 0.0));
                                                                        highp float _34867 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _34867 = (debug_view_info.depth.z * _10875) / max(abs(_10869), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _34867 = (((1.0 / (_10828 * _10828)) * debug_view_info.depth.z) * _10875) / max(abs(dot(_7174, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _10913 = log2(max(max(8.0 * _34869, _34867 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_10913 = _10913;
                                                                        float _10952 = (mp_copy_10913 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                                                        float _34879 = 0.0;
                                                                        if (debug_view_info.view.w > 1.5)
                                                                        {
                                                                            _34879 = fract(_10952);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _34880 = 0.0;
                                                                            if (debug_view_info.view.w > 0.5)
                                                                            {
                                                                                _34880 = ((_10952 < 0.0) || (_10952 > 1.0)) ? 0.0 : _10952;
                                                                            }
                                                                            else
                                                                            {
                                                                                _34880 = clamp(_10952, 0.0, 1.0);
                                                                            }
                                                                            _34879 = _34880;
                                                                        }
                                                                        _34924 = clamp(vec3(1.5) - abs(vec3(4.0 * _34879) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.left.y;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _10985 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _34924 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_10985.x + _10985.y, 2.0)));
                                                                    }
                                                                    _34923 = _34924;
                                                                }
                                                                _34922 = _34923;
                                                            }
                                                            _34921 = _34922;
                                                        }
                                                        _34920 = _34921;
                                                    }
                                                    _34919 = _34920;
                                                }
                                                _34918 = _34919;
                                            }
                                            _34917 = _34918;
                                        }
                                        _34916 = _34917;
                                    }
                                    _34915 = _34916;
                                }
                                _34914 = _34915;
                            }
                            _34913 = _34914;
                        }
                        _34912 = _34913;
                    }
                    _34911 = _34912;
                }
                _34925 = vec4(_34911, 1.0);
                break;
            }
            vec3 _34846 = vec3(0.0);
            if (debug_view_info.left.x < 40.0)
            {
                vec3 _34847 = vec3(0.0);
                if (debug_view_info.left.x == 20.0)
                {
                    vec3 _11006 = max(_7261.xyz * debug_view_info.left.y, vec3(0.0));
                    _34847 = mix(_11006 * 12.9200000762939453125, (pow(max(_11006, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _11006));
                }
                else
                {
                    vec3 _34848 = vec3(0.0);
                    if (debug_view_info.left.x == 21.0)
                    {
                        float _11045 = (_35429 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                        float _34842 = 0.0;
                        if (debug_view_info.view.w > 1.5)
                        {
                            _34842 = fract(_11045);
                        }
                        else
                        {
                            float _34843 = 0.0;
                            if (debug_view_info.view.w > 0.5)
                            {
                                _34843 = ((_11045 < 0.0) || (_11045 > 1.0)) ? 0.0 : _11045;
                            }
                            else
                            {
                                _34843 = clamp(_11045, 0.0, 1.0);
                            }
                            _34842 = _34843;
                        }
                        _34848 = vec3(_34842 * debug_view_info.left.y);
                    }
                    else
                    {
                        vec3 _34849 = vec3(0.0);
                        if (debug_view_info.left.x == 22.0)
                        {
                            float _11096 = (_7307 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                            float _34838 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _34838 = fract(_11096);
                            }
                            else
                            {
                                float _34839 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _34839 = ((_11096 < 0.0) || (_11096 > 1.0)) ? 0.0 : _11096;
                                }
                                else
                                {
                                    _34839 = clamp(_11096, 0.0, 1.0);
                                }
                                _34838 = _34839;
                            }
                            _34849 = vec3(_34838 * debug_view_info.left.y);
                        }
                        else
                        {
                            vec3 _34850 = vec3(0.0);
                            if (debug_view_info.left.x == 23.0)
                            {
                                float _11147 = (_7314 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                float _34834 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _34834 = fract(_11147);
                                }
                                else
                                {
                                    float _34835 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _34835 = ((_11147 < 0.0) || (_11147 > 1.0)) ? 0.0 : _11147;
                                    }
                                    else
                                    {
                                        _34835 = clamp(_11147, 0.0, 1.0);
                                    }
                                    _34834 = _34835;
                                }
                                _34850 = vec3(_34834 * debug_view_info.left.y);
                            }
                            else
                            {
                                vec3 _34851 = vec3(0.0);
                                if (debug_view_info.left.x == 24.0)
                                {
                                    float _11198 = (1.0 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                    float _34830 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _34830 = fract(_11198);
                                    }
                                    else
                                    {
                                        float _34831 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _34831 = ((_11198 < 0.0) || (_11198 > 1.0)) ? 0.0 : _11198;
                                        }
                                        else
                                        {
                                            _34831 = clamp(_11198, 0.0, 1.0);
                                        }
                                        _34830 = _34831;
                                    }
                                    _34851 = vec3(_34830 * debug_view_info.left.y);
                                }
                                else
                                {
                                    vec3 _34852 = vec3(0.0);
                                    if (debug_view_info.left.x == 25.0)
                                    {
                                        float _11249 = (_7336 - debug_view_info.left.z) / max(debug_view_info.left.w - debug_view_info.left.z, 9.9999999747524270787835121154785e-07);
                                        float _34826 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _34826 = fract(_11249);
                                        }
                                        else
                                        {
                                            float _34827 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _34827 = ((_11249 < 0.0) || (_11249 > 1.0)) ? 0.0 : _11249;
                                            }
                                            else
                                            {
                                                _34827 = clamp(_11249, 0.0, 1.0);
                                            }
                                            _34826 = _34827;
                                        }
                                        _34852 = vec3(_34826 * debug_view_info.left.y);
                                    }
                                    else
                                    {
                                        vec3 _34853 = vec3(0.0);
                                        if (debug_view_info.left.x == 26.0)
                                        {
                                            vec3 _11285 = max(_7360 * debug_view_info.left.y, vec3(0.0));
                                            _34853 = mix(_11285 * 12.9200000762939453125, (pow(max(_11285, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _11285));
                                        }
                                        else
                                        {
                                            vec2 _11306 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _34853 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11306.x + _11306.y, 2.0)));
                                        }
                                        _34852 = _34853;
                                    }
                                    _34851 = _34852;
                                }
                                _34850 = _34851;
                            }
                            _34849 = _34850;
                        }
                        _34848 = _34849;
                    }
                    _34847 = _34848;
                }
                _34846 = _34847;
            }
            else
            {
                vec3 _34854 = vec3(0.0);
                if (debug_view_info.left.x < 60.0)
                {
                    vec2 _11327 = floor(gl_FragCoord.xy * vec2(0.125));
                    _34854 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11327.x + _11327.y, 2.0)));
                }
                else
                {
                    vec3 _34855 = vec3(0.0);
                    if (debug_view_info.left.x < 70.0)
                    {
                        vec3 _34856 = vec3(0.0);
                        if (debug_view_info.left.x == 60.0)
                        {
                            _34856 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.left.y;
                        }
                        else
                        {
                            vec3 _34857 = vec3(0.0);
                            if (debug_view_info.left.x == 61.0)
                            {
                                _34857 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.left.y;
                            }
                            else
                            {
                                vec2 _11415 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34857 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11415.x + _11415.y, 2.0)));
                            }
                            _34856 = _34857;
                        }
                        _34855 = _34856;
                    }
                    else
                    {
                        vec3 _34858 = vec3(0.0);
                        if (debug_view_info.left.x < 80.0)
                        {
                            vec3 _34859 = vec3(0.0);
                            if (debug_view_info.left.x == 70.0)
                            {
                                bool _11432 = v_texture_coords.x < 0.0;
                                bool _11439 = false;
                                if (!_11432)
                                {
                                    _11439 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _11439 = _11432;
                                }
                                bool _11446 = false;
                                if (!_11439)
                                {
                                    _11446 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _11446 = _11439;
                                }
                                bool _11453 = false;
                                if (!_11446)
                                {
                                    _11453 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _11453 = _11446;
                                }
                                bvec3 _11456 = bvec3(_11453);
                                highp vec3 _11457 = vec3(_11456.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _11456.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _11456.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _11482 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                highp vec3 _11483 = vec3(_11482.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _11457.x, _11482.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _11457.y, _11482.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _11457.z);
                                float _11497 = length(v_normal);
                                bvec3 _11504 = bvec3((_11497 < 0.300000011920928955078125) || (_11497 > 1.7000000476837158203125));
                                highp vec3 _11505 = vec3(_11504.x ? vec3(1.0, 0.5, 0.0).x : _11483.x, _11504.y ? vec3(1.0, 0.5, 0.0).y : _11483.y, _11504.z ? vec3(1.0, 0.5, 0.0).z : _11483.z);
                                bool _11510 = _7307 > 0.0500000007450580596923828125;
                                bool _11516 = false;
                                if (_11510)
                                {
                                    _11516 = _7307 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _11516 = _11510;
                                }
                                vec3 _11528 = vec3(0.0);
                                bvec3 _11518 = bvec3(_11516);
                                highp vec3 _11519 = vec3(_11518.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _11505.x, _11518.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _11505.y, _11518.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _11505.z);
                                vec3 _34824 = vec3(0.0);
                                do
                                {
                                    _11528 = _7261.xyz;
                                    float _11529 = dot(_11528, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7307 > 0.5)
                                    {
                                        _34824 = _11519;
                                        break;
                                    }
                                    if (_11529 < 0.0130000002682209014892578125)
                                    {
                                        _34824 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_11529 > 0.87000000476837158203125)
                                    {
                                        _34824 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _34824 = _11519;
                                    break;
                                } while(false);
                                vec3 _34825 = vec3(0.0);
                                do
                                {
                                    vec3 _11574 = ((_11528 + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                    bool _11589 = min(min(_7258, _7259), _7260) < 0.0;
                                    bool _11602 = false;
                                    if (!_11589)
                                    {
                                        _11602 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                    }
                                    else
                                    {
                                        _11602 = _11589;
                                    }
                                    if (any(isnan(_11574)))
                                    {
                                        _34825 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_11574)))
                                    {
                                        _34825 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_11602)
                                    {
                                        _34825 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _34825 = _34824;
                                    break;
                                } while(false);
                                _34859 = _34825;
                            }
                            else
                            {
                                vec3 _34860 = vec3(0.0);
                                if (debug_view_info.left.x == 71.0)
                                {
                                    vec3 _34823 = vec3(0.0);
                                    do
                                    {
                                        vec3 _11642 = ((_7261.xyz + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                        bool _11657 = min(min(_7258, _7259), _7260) < 0.0;
                                        bool _11670 = false;
                                        if (!_11657)
                                        {
                                            _11670 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                        }
                                        else
                                        {
                                            _11670 = _11657;
                                        }
                                        if (any(isnan(_11642)))
                                        {
                                            _34823 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_11642)))
                                        {
                                            _34823 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_11670)
                                        {
                                            _34823 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _34823 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _34860 = _34823;
                                }
                                else
                                {
                                    vec3 _34861 = vec3(0.0);
                                    if (debug_view_info.left.x == 72.0)
                                    {
                                        vec3 _34822 = vec3(0.0);
                                        do
                                        {
                                            float _11692 = dot(_7261.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7307 > 0.5)
                                            {
                                                _34822 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_11692 < 0.0130000002682209014892578125)
                                            {
                                                _34822 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_11692 > 0.87000000476837158203125)
                                            {
                                                _34822 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _34822 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _34861 = _34822;
                                    }
                                    else
                                    {
                                        vec3 _34862 = vec3(0.0);
                                        if (debug_view_info.left.x == 73.0)
                                        {
                                            bool _11714 = _7307 > 0.0500000007450580596923828125;
                                            bool _11720 = false;
                                            if (_11714)
                                            {
                                                _11720 = _7307 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _11720 = _11714;
                                            }
                                            bvec3 _11722 = bvec3(_11720);
                                            _34862 = vec3(_11722.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _11722.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _11722.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _34863 = vec3(0.0);
                                            if (debug_view_info.left.x == 74.0)
                                            {
                                                float _11728 = length(v_normal);
                                                bvec3 _11735 = bvec3((_11728 < 0.300000011920928955078125) || (_11728 > 1.7000000476837158203125));
                                                _34863 = vec3(_11735.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _11735.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _11735.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _34864 = vec3(0.0);
                                                if (debug_view_info.left.x == 75.0)
                                                {
                                                    bvec3 _11758 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                                    _34864 = vec3(_11758.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _11758.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _11758.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _34865 = vec3(0.0);
                                                    if (debug_view_info.left.x == 76.0)
                                                    {
                                                        bool _11776 = v_texture_coords.x < 0.0;
                                                        bool _11783 = false;
                                                        if (!_11776)
                                                        {
                                                            _11783 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _11783 = _11776;
                                                        }
                                                        bool _11790 = false;
                                                        if (!_11783)
                                                        {
                                                            _11790 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _11790 = _11783;
                                                        }
                                                        bool _11797 = false;
                                                        if (!_11790)
                                                        {
                                                            _11797 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _11797 = _11790;
                                                        }
                                                        bvec3 _11800 = bvec3(_11797);
                                                        _34865 = vec3(_11800.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _11800.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _11800.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _11813 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _34865 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11813.x + _11813.y, 2.0)));
                                                    }
                                                    _34864 = _34865;
                                                }
                                                _34863 = _34864;
                                            }
                                            _34862 = _34863;
                                        }
                                        _34861 = _34862;
                                    }
                                    _34860 = _34861;
                                }
                                _34859 = _34860;
                            }
                            _34858 = _34859;
                        }
                        else
                        {
                            vec3 _34866 = vec3(0.0);
                            if (debug_view_info.left.x == 80.0)
                            {
                                _34866 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _11831 = floor(gl_FragCoord.xy * vec2(0.125));
                                _34866 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_11831.x + _11831.y, 2.0)));
                            }
                            _34858 = _34866;
                        }
                        _34855 = _34858;
                    }
                    _34854 = _34855;
                }
                _34846 = _34854;
            }
            _34925 = vec4(_34846, 1.0);
            break;
        } while(false);
        bvec4 _11850 = bvec4(gl_FragCoord.x >= debug_view_info.view.y);
        frag_color = vec4(_11850.x ? _34197.x : _34925.x, _11850.y ? _34197.y : _34925.y, _11850.z ? _34197.z : _34925.z, _11850.w ? _34197.w : _34925.w);
    }
    else
    {
        if ((_31031 > 0.5) && (_31031 < 1.5))
        {
            vec4 _34093 = vec4(0.0);
            do
            {
                if (debug_view_info.view.x < 20.0)
                {
                    vec3 _34079 = vec3(0.0);
                    if (debug_view_info.view.x == 1.0)
                    {
                        float _12270 = length(_7174);
                        vec3 _34077 = vec3(0.0);
                        if (_12270 > 9.9999999747524270787835121154785e-07)
                        {
                            _34077 = _7174 / vec3(_12270);
                        }
                        else
                        {
                            _34077 = vec3(0.0);
                        }
                        _34079 = ((_34077 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                    }
                    else
                    {
                        vec3 _34080 = vec3(0.0);
                        if (debug_view_info.view.x == 2.0)
                        {
                            float _12293 = length(_30995);
                            vec3 _34075 = vec3(0.0);
                            if (_12293 > 9.9999999747524270787835121154785e-07)
                            {
                                _34075 = _30995 / vec3(_12293);
                            }
                            else
                            {
                                _34075 = vec3(0.0);
                            }
                            _34080 = ((_34075 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _34081 = vec3(0.0);
                            if (debug_view_info.view.x == 3.0)
                            {
                                float _12316 = length(v_tangent.xyz);
                                vec3 _34073 = vec3(0.0);
                                if (_12316 > 9.9999999747524270787835121154785e-07)
                                {
                                    _34073 = v_tangent.xyz / vec3(_12316);
                                }
                                else
                                {
                                    _34073 = vec3(0.0);
                                }
                                _34081 = ((_34073 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _34082 = vec3(0.0);
                                if (debug_view_info.view.x == 4.0)
                                {
                                    highp float _11949 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                    float mp_copy_11949 = _11949;
                                    vec3 _11950 = cross(_7172, v_tangent.xyz) * mp_copy_11949;
                                    float _12339 = length(_11950);
                                    vec3 _34071 = vec3(0.0);
                                    if (_12339 > 9.9999999747524270787835121154785e-07)
                                    {
                                        _34071 = _11950 / vec3(_12339);
                                    }
                                    else
                                    {
                                        _34071 = vec3(0.0);
                                    }
                                    _34082 = ((_34071 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _34083 = vec3(0.0);
                                    if (debug_view_info.view.x == 5.0)
                                    {
                                        _34083 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                    }
                                    else
                                    {
                                        vec3 _34084 = vec3(0.0);
                                        if (debug_view_info.view.x == 6.0)
                                        {
                                            _34084 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                        }
                                        else
                                        {
                                            vec3 _34085 = vec3(0.0);
                                            if (debug_view_info.view.x == 7.0)
                                            {
                                                _34085 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                            }
                                            else
                                            {
                                                vec3 _34086 = vec3(0.0);
                                                if (debug_view_info.view.x == 8.0)
                                                {
                                                    vec3 _12374 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                    _34086 = mix(_12374 * 12.9200000762939453125, (pow(max(_12374, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _12374));
                                                }
                                                else
                                                {
                                                    vec3 _34087 = vec3(0.0);
                                                    if (debug_view_info.view.x == 9.0)
                                                    {
                                                        vec3 mp_copy_34067 = vec3(0.0);
                                                        highp vec3 _34067 = vec3(0.0);
                                                        if (view_info.camera_forward.w > 0.5)
                                                        {
                                                            _34067 = -view_info.camera_forward.xyz;
                                                        }
                                                        else
                                                        {
                                                            _34067 = normalize(v_viewvector);
                                                        }
                                                        mp_copy_34067 = _34067;
                                                        float _12410 = length(mp_copy_34067);
                                                        vec3 _34068 = vec3(0.0);
                                                        if (_12410 > 9.9999999747524270787835121154785e-07)
                                                        {
                                                            _34068 = mp_copy_34067 / vec3(_12410);
                                                        }
                                                        else
                                                        {
                                                            _34068 = vec3(0.0);
                                                        }
                                                        _34087 = ((_34068 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                    }
                                                    else
                                                    {
                                                        vec3 _34088 = vec3(0.0);
                                                        if (debug_view_info.view.x == 10.0)
                                                        {
                                                            float _12453 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                            float _12454 = (v_position.x - debug_view_info.params.x) / _12453;
                                                            bool _12458 = debug_view_info.view.w > 1.5;
                                                            float _34051 = 0.0;
                                                            if (_12458)
                                                            {
                                                                _34051 = fract(_12454);
                                                            }
                                                            else
                                                            {
                                                                float _34052 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _34052 = ((_12454 < 0.0) || (_12454 > 1.0)) ? 0.0 : _12454;
                                                                }
                                                                else
                                                                {
                                                                    _34052 = clamp(_12454, 0.0, 1.0);
                                                                }
                                                                _34051 = _34052;
                                                            }
                                                            float _12505 = (v_position.y - debug_view_info.params.x) / _12453;
                                                            float _34057 = 0.0;
                                                            if (_12458)
                                                            {
                                                                _34057 = fract(_12505);
                                                            }
                                                            else
                                                            {
                                                                float _34058 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _34058 = ((_12505 < 0.0) || (_12505 > 1.0)) ? 0.0 : _12505;
                                                                }
                                                                else
                                                                {
                                                                    _34058 = clamp(_12505, 0.0, 1.0);
                                                                }
                                                                _34057 = _34058;
                                                            }
                                                            float _12556 = (v_position.z - debug_view_info.params.x) / _12453;
                                                            float _34063 = 0.0;
                                                            if (_12458)
                                                            {
                                                                _34063 = fract(_12556);
                                                            }
                                                            else
                                                            {
                                                                float _34064 = 0.0;
                                                                if (debug_view_info.view.w > 0.5)
                                                                {
                                                                    _34064 = ((_12556 < 0.0) || (_12556 > 1.0)) ? 0.0 : _12556;
                                                                }
                                                                else
                                                                {
                                                                    _34064 = clamp(_12556, 0.0, 1.0);
                                                                }
                                                                _34063 = _34064;
                                                            }
                                                            _34088 = vec3(_34051 * debug_view_info.view.z, _34057 * debug_view_info.view.z, _34063 * debug_view_info.view.z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _34089 = vec3(0.0);
                                                            if (debug_view_info.view.x == 11.0)
                                                            {
                                                                bvec3 _12025 = bvec3(gl_FrontFacing);
                                                                _34089 = vec3(_12025.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _12025.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _12025.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                            }
                                                            else
                                                            {
                                                                vec3 _34090 = vec3(0.0);
                                                                if (debug_view_info.view.x == 12.0)
                                                                {
                                                                    highp vec2 _12583 = v_texture_coords;
                                                                    vec2 mp_copy_12583 = _12583;
                                                                    vec2 _12595 = floor(mp_copy_12583 * 8.0);
                                                                    float _12597 = _12595.x;
                                                                    float _12599 = _12595.y;
                                                                    float _12607 = _12597 + (_12599 * 8.0);
                                                                    vec2 _12616 = step(vec2(0.0), mp_copy_12583) * step(mp_copy_12583, vec2(1.0));
                                                                    _34090 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_12597 + _12599, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_12607 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_12607 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_12616.x * _12616.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _34091 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 13.0)
                                                                    {
                                                                        highp vec2 _12666 = v_texture_coords_1;
                                                                        vec2 mp_copy_12666 = _12666;
                                                                        vec2 _12678 = floor(mp_copy_12666 * 8.0);
                                                                        float _12680 = _12678.x;
                                                                        float _12682 = _12678.y;
                                                                        float _12690 = _12680 + (_12682 * 8.0);
                                                                        vec2 _12699 = step(vec2(0.0), mp_copy_12666) * step(mp_copy_12666, vec2(1.0));
                                                                        _34091 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_12680 + _12682, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_12690 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_12690 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_12699.x * _12699.y));
                                                                    }
                                                                    else
                                                                    {
                                                                        vec3 _34092 = vec3(0.0);
                                                                        if (debug_view_info.view.x == 14.0)
                                                                        {
                                                                            highp float _12765 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                            bool _12771 = debug_view_info.depth.x > 0.5;
                                                                            bool _12777 = false;
                                                                            if (_12771)
                                                                            {
                                                                                _12777 = debug_view_info.depth.y > 0.5;
                                                                            }
                                                                            else
                                                                            {
                                                                                _12777 = _12771;
                                                                            }
                                                                            highp float _34037 = 0.0;
                                                                            if (_12777)
                                                                            {
                                                                                _34037 = 1.1920928955078125e-07 / _12765;
                                                                            }
                                                                            else
                                                                            {
                                                                                highp float _34038 = 0.0;
                                                                                if (_12771)
                                                                                {
                                                                                    _34038 = 5.9604644775390625e-08 / (_12765 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                }
                                                                                else
                                                                                {
                                                                                    _34038 = 5.9604644775390625e-08 / (_12765 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                }
                                                                                _34037 = _34038;
                                                                            }
                                                                            highp float _12806 = dot(_7174, view_info.camera_forward.xyz);
                                                                            highp float _12812 = sqrt(max(1.0 - (_12806 * _12806), 0.0));
                                                                            highp float _34035 = 0.0;
                                                                            if (view_info.camera_forward.w > 0.5)
                                                                            {
                                                                                _34035 = (debug_view_info.depth.z * _12812) / max(abs(_12806), 9.9999999747524270787835121154785e-07);
                                                                            }
                                                                            else
                                                                            {
                                                                                _34035 = (((1.0 / (_12765 * _12765)) * debug_view_info.depth.z) * _12812) / max(abs(dot(_7174, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                            }
                                                                            highp float _12850 = log2(max(max(8.0 * _34037, _34035 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                            float mp_copy_12850 = _12850;
                                                                            float _12889 = (mp_copy_12850 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                            float _34047 = 0.0;
                                                                            if (debug_view_info.view.w > 1.5)
                                                                            {
                                                                                _34047 = fract(_12889);
                                                                            }
                                                                            else
                                                                            {
                                                                                float _34048 = 0.0;
                                                                                if (debug_view_info.view.w > 0.5)
                                                                                {
                                                                                    _34048 = ((_12889 < 0.0) || (_12889 > 1.0)) ? 0.0 : _12889;
                                                                                }
                                                                                else
                                                                                {
                                                                                    _34048 = clamp(_12889, 0.0, 1.0);
                                                                                }
                                                                                _34047 = _34048;
                                                                            }
                                                                            _34092 = clamp(vec3(1.5) - abs(vec3(4.0 * _34047) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                        }
                                                                        else
                                                                        {
                                                                            vec2 _12922 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                            _34092 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_12922.x + _12922.y, 2.0)));
                                                                        }
                                                                        _34091 = _34092;
                                                                    }
                                                                    _34090 = _34091;
                                                                }
                                                                _34089 = _34090;
                                                            }
                                                            _34088 = _34089;
                                                        }
                                                        _34087 = _34088;
                                                    }
                                                    _34086 = _34087;
                                                }
                                                _34085 = _34086;
                                            }
                                            _34084 = _34085;
                                        }
                                        _34083 = _34084;
                                    }
                                    _34082 = _34083;
                                }
                                _34081 = _34082;
                            }
                            _34080 = _34081;
                        }
                        _34079 = _34080;
                    }
                    _34093 = vec4(_34079, 1.0);
                    break;
                }
                vec3 _34014 = vec3(0.0);
                if (debug_view_info.view.x < 40.0)
                {
                    vec3 _34015 = vec3(0.0);
                    if (debug_view_info.view.x == 20.0)
                    {
                        vec3 _12943 = max(_7261.xyz * debug_view_info.view.z, vec3(0.0));
                        _34015 = mix(_12943 * 12.9200000762939453125, (pow(max(_12943, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _12943));
                    }
                    else
                    {
                        vec3 _34016 = vec3(0.0);
                        if (debug_view_info.view.x == 21.0)
                        {
                            float _12982 = (_35429 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                            float _34010 = 0.0;
                            if (debug_view_info.view.w > 1.5)
                            {
                                _34010 = fract(_12982);
                            }
                            else
                            {
                                float _34011 = 0.0;
                                if (debug_view_info.view.w > 0.5)
                                {
                                    _34011 = ((_12982 < 0.0) || (_12982 > 1.0)) ? 0.0 : _12982;
                                }
                                else
                                {
                                    _34011 = clamp(_12982, 0.0, 1.0);
                                }
                                _34010 = _34011;
                            }
                            _34016 = vec3(_34010 * debug_view_info.view.z);
                        }
                        else
                        {
                            vec3 _34017 = vec3(0.0);
                            if (debug_view_info.view.x == 22.0)
                            {
                                float _13033 = (_7307 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _34006 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _34006 = fract(_13033);
                                }
                                else
                                {
                                    float _34007 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _34007 = ((_13033 < 0.0) || (_13033 > 1.0)) ? 0.0 : _13033;
                                    }
                                    else
                                    {
                                        _34007 = clamp(_13033, 0.0, 1.0);
                                    }
                                    _34006 = _34007;
                                }
                                _34017 = vec3(_34006 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _34018 = vec3(0.0);
                                if (debug_view_info.view.x == 23.0)
                                {
                                    float _13084 = (_7314 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _34002 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _34002 = fract(_13084);
                                    }
                                    else
                                    {
                                        float _34003 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _34003 = ((_13084 < 0.0) || (_13084 > 1.0)) ? 0.0 : _13084;
                                        }
                                        else
                                        {
                                            _34003 = clamp(_13084, 0.0, 1.0);
                                        }
                                        _34002 = _34003;
                                    }
                                    _34018 = vec3(_34002 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _34019 = vec3(0.0);
                                    if (debug_view_info.view.x == 24.0)
                                    {
                                        float _13135 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _33998 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _33998 = fract(_13135);
                                        }
                                        else
                                        {
                                            float _33999 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _33999 = ((_13135 < 0.0) || (_13135 > 1.0)) ? 0.0 : _13135;
                                            }
                                            else
                                            {
                                                _33999 = clamp(_13135, 0.0, 1.0);
                                            }
                                            _33998 = _33999;
                                        }
                                        _34019 = vec3(_33998 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _34020 = vec3(0.0);
                                        if (debug_view_info.view.x == 25.0)
                                        {
                                            float _13186 = (_7336 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                            float _33994 = 0.0;
                                            if (debug_view_info.view.w > 1.5)
                                            {
                                                _33994 = fract(_13186);
                                            }
                                            else
                                            {
                                                float _33995 = 0.0;
                                                if (debug_view_info.view.w > 0.5)
                                                {
                                                    _33995 = ((_13186 < 0.0) || (_13186 > 1.0)) ? 0.0 : _13186;
                                                }
                                                else
                                                {
                                                    _33995 = clamp(_13186, 0.0, 1.0);
                                                }
                                                _33994 = _33995;
                                            }
                                            _34020 = vec3(_33994 * debug_view_info.view.z);
                                        }
                                        else
                                        {
                                            vec3 _34021 = vec3(0.0);
                                            if (debug_view_info.view.x == 26.0)
                                            {
                                                vec3 _13222 = max(_7360 * debug_view_info.view.z, vec3(0.0));
                                                _34021 = mix(_13222 * 12.9200000762939453125, (pow(max(_13222, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _13222));
                                            }
                                            else
                                            {
                                                vec2 _13243 = floor(gl_FragCoord.xy * vec2(0.125));
                                                _34021 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13243.x + _13243.y, 2.0)));
                                            }
                                            _34020 = _34021;
                                        }
                                        _34019 = _34020;
                                    }
                                    _34018 = _34019;
                                }
                                _34017 = _34018;
                            }
                            _34016 = _34017;
                        }
                        _34015 = _34016;
                    }
                    _34014 = _34015;
                }
                else
                {
                    vec3 _34022 = vec3(0.0);
                    if (debug_view_info.view.x < 60.0)
                    {
                        vec2 _13264 = floor(gl_FragCoord.xy * vec2(0.125));
                        _34022 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13264.x + _13264.y, 2.0)));
                    }
                    else
                    {
                        vec3 _34023 = vec3(0.0);
                        if (debug_view_info.view.x < 70.0)
                        {
                            vec3 _34024 = vec3(0.0);
                            if (debug_view_info.view.x == 60.0)
                            {
                                _34024 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _34025 = vec3(0.0);
                                if (debug_view_info.view.x == 61.0)
                                {
                                    _34025 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec2 _13352 = floor(gl_FragCoord.xy * vec2(0.125));
                                    _34025 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13352.x + _13352.y, 2.0)));
                                }
                                _34024 = _34025;
                            }
                            _34023 = _34024;
                        }
                        else
                        {
                            vec3 _34026 = vec3(0.0);
                            if (debug_view_info.view.x < 80.0)
                            {
                                vec3 _34027 = vec3(0.0);
                                if (debug_view_info.view.x == 70.0)
                                {
                                    bool _13369 = v_texture_coords.x < 0.0;
                                    bool _13376 = false;
                                    if (!_13369)
                                    {
                                        _13376 = v_texture_coords.x > 1.0;
                                    }
                                    else
                                    {
                                        _13376 = _13369;
                                    }
                                    bool _13383 = false;
                                    if (!_13376)
                                    {
                                        _13383 = v_texture_coords.y < 0.0;
                                    }
                                    else
                                    {
                                        _13383 = _13376;
                                    }
                                    bool _13390 = false;
                                    if (!_13383)
                                    {
                                        _13390 = v_texture_coords.y > 1.0;
                                    }
                                    else
                                    {
                                        _13390 = _13383;
                                    }
                                    bvec3 _13393 = bvec3(_13390);
                                    highp vec3 _13394 = vec3(_13393.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _13393.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _13393.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                    bvec3 _13419 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                    highp vec3 _13420 = vec3(_13419.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _13394.x, _13419.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _13394.y, _13419.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _13394.z);
                                    float _13434 = length(v_normal);
                                    bvec3 _13441 = bvec3((_13434 < 0.300000011920928955078125) || (_13434 > 1.7000000476837158203125));
                                    highp vec3 _13442 = vec3(_13441.x ? vec3(1.0, 0.5, 0.0).x : _13420.x, _13441.y ? vec3(1.0, 0.5, 0.0).y : _13420.y, _13441.z ? vec3(1.0, 0.5, 0.0).z : _13420.z);
                                    bool _13447 = _7307 > 0.0500000007450580596923828125;
                                    bool _13453 = false;
                                    if (_13447)
                                    {
                                        _13453 = _7307 < 0.949999988079071044921875;
                                    }
                                    else
                                    {
                                        _13453 = _13447;
                                    }
                                    vec3 _13465 = vec3(0.0);
                                    bvec3 _13455 = bvec3(_13453);
                                    highp vec3 _13456 = vec3(_13455.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _13442.x, _13455.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _13442.y, _13455.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _13442.z);
                                    vec3 _33992 = vec3(0.0);
                                    do
                                    {
                                        _13465 = _7261.xyz;
                                        float _13466 = dot(_13465, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                        if (_7307 > 0.5)
                                        {
                                            _33992 = _13456;
                                            break;
                                        }
                                        if (_13466 < 0.0130000002682209014892578125)
                                        {
                                            _33992 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                            break;
                                        }
                                        if (_13466 > 0.87000000476837158203125)
                                        {
                                            _33992 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                            break;
                                        }
                                        _33992 = _13456;
                                        break;
                                    } while(false);
                                    vec3 _33993 = vec3(0.0);
                                    do
                                    {
                                        vec3 _13511 = ((_13465 + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                        bool _13526 = min(min(_7258, _7259), _7260) < 0.0;
                                        bool _13539 = false;
                                        if (!_13526)
                                        {
                                            _13539 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                        }
                                        else
                                        {
                                            _13539 = _13526;
                                        }
                                        if (any(isnan(_13511)))
                                        {
                                            _33993 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_13511)))
                                        {
                                            _33993 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_13539)
                                        {
                                            _33993 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _33993 = _33992;
                                        break;
                                    } while(false);
                                    _34027 = _33993;
                                }
                                else
                                {
                                    vec3 _34028 = vec3(0.0);
                                    if (debug_view_info.view.x == 71.0)
                                    {
                                        vec3 _33991 = vec3(0.0);
                                        do
                                        {
                                            vec3 _13579 = ((_7261.xyz + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                            bool _13594 = min(min(_7258, _7259), _7260) < 0.0;
                                            bool _13607 = false;
                                            if (!_13594)
                                            {
                                                _13607 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                            }
                                            else
                                            {
                                                _13607 = _13594;
                                            }
                                            if (any(isnan(_13579)))
                                            {
                                                _33991 = vec3(1.0, 0.0, 0.0);
                                                break;
                                            }
                                            if (any(isinf(_13579)))
                                            {
                                                _33991 = vec3(0.0, 1.0, 0.0);
                                                break;
                                            }
                                            if (_13607)
                                            {
                                                _33991 = vec3(0.0, 0.25, 1.0);
                                                break;
                                            }
                                            _33991 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _34028 = _33991;
                                    }
                                    else
                                    {
                                        vec3 _34029 = vec3(0.0);
                                        if (debug_view_info.view.x == 72.0)
                                        {
                                            vec3 _33990 = vec3(0.0);
                                            do
                                            {
                                                float _13629 = dot(_7261.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                                if (_7307 > 0.5)
                                                {
                                                    _33990 = vec3(0.3499999940395355224609375);
                                                    break;
                                                }
                                                if (_13629 < 0.0130000002682209014892578125)
                                                {
                                                    _33990 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                    break;
                                                }
                                                if (_13629 > 0.87000000476837158203125)
                                                {
                                                    _33990 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                    break;
                                                }
                                                _33990 = vec3(0.3499999940395355224609375);
                                                break;
                                            } while(false);
                                            _34029 = _33990;
                                        }
                                        else
                                        {
                                            vec3 _34030 = vec3(0.0);
                                            if (debug_view_info.view.x == 73.0)
                                            {
                                                bool _13651 = _7307 > 0.0500000007450580596923828125;
                                                bool _13657 = false;
                                                if (_13651)
                                                {
                                                    _13657 = _7307 < 0.949999988079071044921875;
                                                }
                                                else
                                                {
                                                    _13657 = _13651;
                                                }
                                                bvec3 _13659 = bvec3(_13657);
                                                _34030 = vec3(_13659.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _13659.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _13659.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _34031 = vec3(0.0);
                                                if (debug_view_info.view.x == 74.0)
                                                {
                                                    float _13665 = length(v_normal);
                                                    bvec3 _13672 = bvec3((_13665 < 0.300000011920928955078125) || (_13665 > 1.7000000476837158203125));
                                                    _34031 = vec3(_13672.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _13672.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _13672.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _34032 = vec3(0.0);
                                                    if (debug_view_info.view.x == 75.0)
                                                    {
                                                        bvec3 _13695 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                                        _34032 = vec3(_13695.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _13695.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _13695.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _34033 = vec3(0.0);
                                                        if (debug_view_info.view.x == 76.0)
                                                        {
                                                            bool _13713 = v_texture_coords.x < 0.0;
                                                            bool _13720 = false;
                                                            if (!_13713)
                                                            {
                                                                _13720 = v_texture_coords.x > 1.0;
                                                            }
                                                            else
                                                            {
                                                                _13720 = _13713;
                                                            }
                                                            bool _13727 = false;
                                                            if (!_13720)
                                                            {
                                                                _13727 = v_texture_coords.y < 0.0;
                                                            }
                                                            else
                                                            {
                                                                _13727 = _13720;
                                                            }
                                                            bool _13734 = false;
                                                            if (!_13727)
                                                            {
                                                                _13734 = v_texture_coords.y > 1.0;
                                                            }
                                                            else
                                                            {
                                                                _13734 = _13727;
                                                            }
                                                            bvec3 _13737 = bvec3(_13734);
                                                            _34033 = vec3(_13737.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _13737.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _13737.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                        }
                                                        else
                                                        {
                                                            vec2 _13750 = floor(gl_FragCoord.xy * vec2(0.125));
                                                            _34033 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13750.x + _13750.y, 2.0)));
                                                        }
                                                        _34032 = _34033;
                                                    }
                                                    _34031 = _34032;
                                                }
                                                _34030 = _34031;
                                            }
                                            _34029 = _34030;
                                        }
                                        _34028 = _34029;
                                    }
                                    _34027 = _34028;
                                }
                                _34026 = _34027;
                            }
                            else
                            {
                                vec3 _34034 = vec3(0.0);
                                if (debug_view_info.view.x == 80.0)
                                {
                                    _34034 = vec3(0.0);
                                }
                                else
                                {
                                    vec2 _13768 = floor(gl_FragCoord.xy * vec2(0.125));
                                    _34034 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_13768.x + _13768.y, 2.0)));
                                }
                                _34026 = _34034;
                            }
                            _34023 = _34026;
                        }
                        _34022 = _34023;
                    }
                    _34014 = _34022;
                }
                _34093 = vec4(_34014, 1.0);
                break;
            } while(false);
            frag_color = _34093;
        }
        else
        {
            highp float hp_copy_31040 = 0.0;
            vec3 _13990 = _7261.xyz;
            float _31040 = 0.0;
            do
            {
                if (frag_info.specular_aa_variance <= 0.0)
                {
                    _31040 = _7314;
                    break;
                }
                vec3 _14808 = dFdx(_30995);
                vec3 _14810 = dFdy(_30995);
                _31040 = sqrt(clamp((_7314 * _7314) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_14808, _14808), dot(_14810, _14810))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
                break;
            } while(false);
            hp_copy_31040 = _31040;
            float _31050 = 0.0;
            vec3 _31055 = vec3(0.0);
            float _31328 = 0.0;
            vec4 _31704 = vec4(0.0);
            vec3 _31855 = vec3(0.0);
            if (frag_info.ssao_params.x > 0.5)
            {
                vec4 _14017 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
                float _31041 = 0.0;
                if (frag_info.camera_up.w > 0.5)
                {
                    _31041 = _14017.w;
                }
                else
                {
                    _31041 = _14017.x;
                }
                float _14030 = min(_7336, _31041);
                bool _14033 = frag_info.ssao_lighting.z > 0.5;
                bool _14039 = false;
                if (_14033)
                {
                    _14039 = frag_info.camera_up.w < 0.5;
                }
                else
                {
                    _14039 = _14033;
                }
                vec3 _31056 = vec3(0.0);
                if (_14039)
                {
                    vec2 _14843 = (_14017.zw * 2.0) - vec2(1.0);
                    float _14845 = _14843.x;
                    float _14847 = _14843.y;
                    float _14855 = (1.0 - abs(_14845)) - abs(_14847);
                    vec3 _14856 = vec3(_14845, _14847, _14855);
                    vec3 _31044 = vec3(0.0);
                    if (_14855 < 0.0)
                    {
                        vec2 _14869 = (vec2(1.0) - abs(_14856.yx)) * vec2((_14845 >= 0.0) ? 1.0 : (-1.0), (_14847 >= 0.0) ? 1.0 : (-1.0));
                        vec3 _30237 = _14856;
                        _30237.x = _14869.x;
                        _30237.y = _14869.y;
                        _31044 = _30237;
                    }
                    else
                    {
                        _31044 = _14856;
                    }
                    vec3 _14877 = -normalize(_31044);
                    _31056 = normalize(((frag_info.camera_right.xyz * _14877.x) + (frag_info.camera_up.xyz * _14877.y)) + (frag_info.camera_forward.xyz * _14877.z));
                }
                else
                {
                    _31056 = vec3(0.0);
                }
                vec3 _14067 = vec3(_14030);
                _31855 = mix(_14067, max(_14067, ((((((_13990 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _14030) + ((_13990 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _14030) + ((_13990 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _14030), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
                _31704 = _14017;
                _31328 = _14030;
                _31055 = _31056;
                _31050 = float(_14039);
            }
            else
            {
                _31855 = vec3(_7336);
                _31704 = vec4(1.0);
                _31328 = _7336;
                _31055 = vec3(0.0);
                _31050 = 0.0;
            }
            vec3 mp_copy_31048 = vec3(0.0);
            bool _14926 = view_info.camera_forward.w > 0.5;
            highp vec3 _31048 = vec3(0.0);
            if (_14926)
            {
                _31048 = -view_info.camera_forward.xyz;
            }
            else
            {
                _31048 = normalize(v_viewvector);
            }
            mp_copy_31048 = _31048;
            vec3 _14085 = mix(frag_info.dielectric_f0.xyz, _13990, vec3(_7307));
            float _14088 = dot(_30995, _31048);
            float _14089 = max(_14088, 0.0);
            float _14093 = max(dot(_7174, _31048), 0.0);
            vec3 _14097 = reflect(-mp_copy_31048, _30995);
            mat3 _14110 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
            bool _14113 = _31050 > 0.5;
            bvec3 _14116 = bvec3(_14113);
            highp vec3 _14117 = vec3(_14116.x ? _31055.x : _30995.x, _14116.y ? _31055.y : _30995.y, _14116.z ? _31055.z : _30995.z);
            vec3 mp_copy_14117 = _14117;
            vec3 _14118 = _14110 * mp_copy_14117;
            vec3 _31059 = vec3(0.0);
            if (frag_info.probe_box.w > 0.5)
            {
                vec3 _14993 = _14097 + (((step(vec3(0.0), _14097) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
                highp vec3 hp_copy_14993 = _14993;
                highp vec3 _14995 = vec3(1.0) / hp_copy_14993;
                highp vec3 _15012 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _14995, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _14995);
                _31059 = normalize((v_position + (_14097 * max(min(min(_15012.x, _15012.y), _15012.z), 0.0))) - frag_info.probe_box.xyz);
            }
            else
            {
                _31059 = _14097;
            }
            bool _15240 = false;
            vec3 _14123 = _14110 * _31059;
            float _15059 = _14118.y;
            float _15060 = 0.48860299587249755859375 * _15059;
            float _15066 = _14118.z;
            float _15067 = 0.48860299587249755859375 * _15066;
            float _15073 = _14118.x;
            float _15074 = 0.48860299587249755859375 * _15073;
            float _15081 = 1.09254801273345947265625 * _15073;
            float _15084 = _15081 * _15059;
            float _15094 = (1.09254801273345947265625 * _15059) * _15066;
            float _15106 = 0.3153919875621795654296875 * (((3.0 * _15066) * _15066) - 1.0);
            float _15116 = _15081 * _15066;
            float _15132 = 0.546274006366729736328125 * ((_15073 * _15073) - (_15059 * _15059));
            vec3 _14126 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _15060)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _15067)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _15074)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _15084)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _15094)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _15106)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _15116)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _15132), vec3(0.0));
            vec3 _31060 = vec3(0.0);
            do
            {
                _15240 = radiance_layout_info.mip_layout > 0.5;
                if (_15240)
                {
                    vec2 _15319 = vec2(atan(_14123.z, _14123.x), asin(clamp(_14123.y, -1.0, 1.0)));
                    highp vec2 hp_copy_15319 = _15319;
                    _31060 = textureLod(prefiltered_radiance, (hp_copy_15319 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_31040, 0.0, 1.0) * 7.0).xyz;
                    break;
                }
                vec2 _15338 = vec2(atan(_14123.z, _14123.x), asin(clamp(_14123.y, -1.0, 1.0)));
                highp vec2 hp_copy_15338 = _15338;
                highp vec2 _15343 = (hp_copy_15338 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _15250 = clamp(_15343.y, 0.00390625, 0.99609375);
                float _15254 = clamp(_31040, 0.0, 1.0) * 7.0;
                float _15256 = floor(_15254);
                highp float _15275 = _15343.x;
                _31060 = mix(texture(prefiltered_radiance, vec2(_15275, (_15256 + _15250) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_15275, (min(_15256 + 1.0, 7.0) + _15250) * 0.125)).xyz, vec3(_15254 - _15256));
                break;
            } while(false);
            bool _14133 = frag_info.radiance_blend.x > 0.0;
            highp vec3 _31065 = vec3(0.0);
            highp vec3 _31066 = vec3(0.0);
            if (_14133)
            {
                vec3 _31061 = vec3(0.0);
                do
                {
                    if (_15240)
                    {
                        vec2 _15631 = vec2(atan(_14123.z, _14123.x), asin(clamp(_14123.y, -1.0, 1.0)));
                        highp vec2 hp_copy_15631 = _15631;
                        _31061 = textureLod(prefiltered_radiance_b, (hp_copy_15631 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_31040, 0.0, 1.0) * 7.0).xyz;
                        break;
                    }
                    vec2 _15650 = vec2(atan(_14123.z, _14123.x), asin(clamp(_14123.y, -1.0, 1.0)));
                    highp vec2 hp_copy_15650 = _15650;
                    highp vec2 _15655 = (hp_copy_15650 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _15562 = clamp(_15655.y, 0.00390625, 0.99609375);
                    float _15566 = clamp(_31040, 0.0, 1.0) * 7.0;
                    float _15568 = floor(_15566);
                    highp float _15587 = _15655.x;
                    _31061 = mix(texture(prefiltered_radiance_b, vec2(_15587, (_15568 + _15562) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_15587, (min(_15568 + 1.0, 7.0) + _15562) * 0.125)).xyz, vec3(_15566 - _15568));
                    break;
                } while(false);
                highp vec3 _14144 = vec3(frag_info.radiance_blend.x);
                _31066 = mix(_31060, _31061, _14144);
                _31065 = mix(_14126, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _15060)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _15067)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _15074)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _15084)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _15094)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _15106)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _15116)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _15132), vec3(0.0)), _14144);
            }
            else
            {
                _31066 = _31060;
                _31065 = _14126;
            }
            highp float _15668 = 0.0;
            highp vec3 _14155 = _31065 * frag_info.environment_intensity;
            float _31067 = 0.0;
            do
            {
                _15668 = frag_info.gi_grid.w;
                if (_15668 <= 0.0)
                {
                    _31067 = 0.0;
                    break;
                }
                highp vec3 _15681 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
                highp vec3 _15689 = min(_15681, (frag_info.gi_counts.xyz - vec3(1.0)) - _15681);
                _31067 = clamp(min(_15689.x, min(_15689.y, _15689.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
                break;
            } while(false);
            highp vec3 _31258 = vec3(0.0);
            if (_31067 > 0.0)
            {
                highp vec3 _15781 = v_position + (((_30995 * 0.20000000298023223876953125) + (mp_copy_31048 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
                highp vec3 _15784 = _15781 / frag_info.gi_grid.xyz;
                highp vec3 _15786 = floor(_15784);
                highp vec3 _15792 = clamp(_15784 - _15786, vec3(0.0), vec3(1.0));
                vec3 mp_copy_15792 = _15792;
                highp vec3 _15914 = _15786 - frag_info.gi_anchor.xyz;
                bool _15917 = any(lessThan(_15914, vec3(0.0)));
                bool _15925 = false;
                if (!_15917)
                {
                    _15925 = any(greaterThanEqual(_15914, frag_info.gi_counts.xyz));
                }
                else
                {
                    _15925 = _15917;
                }
                vec3 mp_copy_31068 = vec3(0.0);
                highp float _15926 = _15925 ? 0.0 : 1.0;
                float mp_copy_15926 = _15926;
                vec3 _15928 = vec3(1.0) - mp_copy_15792;
                vec3 _15932 = max(_15928, vec3(0.001000000047497451305389404296875));
                highp vec3 _15948 = (_15786 * frag_info.gi_grid.xyz) - _15781;
                highp float _15950 = length(_15948);
                highp vec3 _31068 = vec3(0.0);
                if (_15950 > 9.9999997473787516355514526367188e-06)
                {
                    _31068 = _15948 / vec3(_15950);
                }
                else
                {
                    _31068 = _30995;
                }
                mp_copy_31068 = _31068;
                float _15968 = pow((dot(_31068, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _16093 = _15786 - (frag_info.gi_counts.xyz * floor(_15786 / frag_info.gi_counts.xyz));
                highp float _16109 = _16093.x + (frag_info.gi_counts.x * (_16093.y + (frag_info.gi_counts.y * _16093.z)));
                bool _15979 = frag_info.gi_visibility.x > 0.0;
                float _31073 = 0.0;
                if (_15979)
                {
                    highp float _16117 = floor(_16109 / frag_info.gi_counts.w);
                    highp vec2 _16131 = vec2((_16109 - (_16117 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16117 * 16.0));
                    vec3 _15991 = -mp_copy_31068;
                    vec3 _16179 = _15991 / vec3((abs(_15991.x) + abs(_15991.y)) + abs(_15991.z));
                    vec2 _31069 = vec2(0.0);
                    if (_16179.z >= 0.0)
                    {
                        _31069 = _16179.xy;
                    }
                    else
                    {
                        _31069 = (vec2(1.0) - abs(_16179.yx)) * vec2((_16179.x >= 0.0) ? 1.0 : (-1.0), (_16179.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _15995 = texture(irradiance_field, clamp((_16131 + vec2(1.0)) + (clamp((_31069 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16131 + vec2(0.5), _16131 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _16000 = _15995.x * frag_info.gi_visibility.z;
                    highp float _16012 = abs((_16000 * _16000) - ((_15995.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _16018 = (_15950 - _16000) - frag_info.gi_visibility.y;
                    highp float _31070 = 0.0;
                    if (_16018 <= 0.0)
                    {
                        _31070 = 1.0;
                    }
                    else
                    {
                        _31070 = _16012 / (_16012 + (_16018 * _16018));
                    }
                    _31073 = _15968 * mix(1.0, max(0.0500000007450580596923828125, (_31070 * _31070) * _31070), frag_info.gi_visibility.x);
                }
                else
                {
                    _31073 = _15968;
                }
                float _16046 = max(9.9999999747524270787835121154785e-07, _31073);
                float _31074 = 0.0;
                if (_16046 < 0.20000000298023223876953125)
                {
                    _31074 = _16046 * ((_16046 * _16046) * 25.0);
                }
                else
                {
                    _31074 = _16046;
                }
                float _16061 = _31074 * (((_15932.x * _15932.y) * _15932.z) * mp_copy_15926);
                highp float _16220 = floor(_16109 / frag_info.gi_counts.w);
                highp vec2 _16234 = vec2((_16109 - (_16220 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16220 * 8.0));
                vec3 _16282 = _30995 / vec3((abs(_30995.x) + abs(_30995.y)) + abs(_30995.z));
                bool _16285 = _16282.z >= 0.0;
                vec2 _31075 = vec2(0.0);
                if (_16285)
                {
                    _31075 = _16282.xy;
                }
                else
                {
                    _31075 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16073 = texture(irradiance_field, clamp((_16234 + vec2(1.0)) + (clamp((_31075 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16234 + vec2(0.5), _16234 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _16368 = _15786 + vec3(1.0, 0.0, 0.0);
                highp vec3 _16373 = _16368 - frag_info.gi_anchor.xyz;
                bool _16376 = any(lessThan(_16373, vec3(0.0)));
                bool _16384 = false;
                if (!_16376)
                {
                    _16384 = any(greaterThanEqual(_16373, frag_info.gi_counts.xyz));
                }
                else
                {
                    _16384 = _16376;
                }
                vec3 mp_copy_31077 = vec3(0.0);
                highp float _16385 = _16384 ? 0.0 : 1.0;
                float mp_copy_16385 = _16385;
                vec3 _16391 = max(mix(_15928, mp_copy_15792, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _16407 = (_16368 * frag_info.gi_grid.xyz) - _15781;
                highp float _16409 = length(_16407);
                highp vec3 _31077 = vec3(0.0);
                if (_16409 > 9.9999997473787516355514526367188e-06)
                {
                    _31077 = _16407 / vec3(_16409);
                }
                else
                {
                    _31077 = _30995;
                }
                mp_copy_31077 = _31077;
                float _16427 = pow((dot(_31077, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _16552 = _16368 - (frag_info.gi_counts.xyz * floor(_16368 / frag_info.gi_counts.xyz));
                highp float _16568 = _16552.x + (frag_info.gi_counts.x * (_16552.y + (frag_info.gi_counts.y * _16552.z)));
                float _31082 = 0.0;
                if (_15979)
                {
                    highp float _16576 = floor(_16568 / frag_info.gi_counts.w);
                    highp vec2 _16590 = vec2((_16568 - (_16576 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_16576 * 16.0));
                    vec3 _16450 = -mp_copy_31077;
                    vec3 _16638 = _16450 / vec3((abs(_16450.x) + abs(_16450.y)) + abs(_16450.z));
                    vec2 _31078 = vec2(0.0);
                    if (_16638.z >= 0.0)
                    {
                        _31078 = _16638.xy;
                    }
                    else
                    {
                        _31078 = (vec2(1.0) - abs(_16638.yx)) * vec2((_16638.x >= 0.0) ? 1.0 : (-1.0), (_16638.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _16454 = texture(irradiance_field, clamp((_16590 + vec2(1.0)) + (clamp((_31078 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _16590 + vec2(0.5), _16590 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _16459 = _16454.x * frag_info.gi_visibility.z;
                    highp float _16471 = abs((_16459 * _16459) - ((_16454.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _16477 = (_16409 - _16459) - frag_info.gi_visibility.y;
                    highp float _31079 = 0.0;
                    if (_16477 <= 0.0)
                    {
                        _31079 = 1.0;
                    }
                    else
                    {
                        _31079 = _16471 / (_16471 + (_16477 * _16477));
                    }
                    _31082 = _16427 * mix(1.0, max(0.0500000007450580596923828125, (_31079 * _31079) * _31079), frag_info.gi_visibility.x);
                }
                else
                {
                    _31082 = _16427;
                }
                float _16505 = max(9.9999999747524270787835121154785e-07, _31082);
                float _31083 = 0.0;
                if (_16505 < 0.20000000298023223876953125)
                {
                    _31083 = _16505 * ((_16505 * _16505) * 25.0);
                }
                else
                {
                    _31083 = _16505;
                }
                float _16520 = _31083 * (((_16391.x * _16391.y) * _16391.z) * mp_copy_16385);
                highp float _16679 = floor(_16568 / frag_info.gi_counts.w);
                highp vec2 _16693 = vec2((_16568 - (_16679 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_16679 * 8.0));
                vec2 _31084 = vec2(0.0);
                if (_16285)
                {
                    _31084 = _16282.xy;
                }
                else
                {
                    _31084 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16532 = texture(irradiance_field, clamp((_16693 + vec2(1.0)) + (clamp((_31084 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _16693 + vec2(0.5), _16693 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _16827 = _15786 + vec3(0.0, 1.0, 0.0);
                highp vec3 _16832 = _16827 - frag_info.gi_anchor.xyz;
                bool _16835 = any(lessThan(_16832, vec3(0.0)));
                bool _16843 = false;
                if (!_16835)
                {
                    _16843 = any(greaterThanEqual(_16832, frag_info.gi_counts.xyz));
                }
                else
                {
                    _16843 = _16835;
                }
                vec3 mp_copy_31086 = vec3(0.0);
                highp float _16844 = _16843 ? 0.0 : 1.0;
                float mp_copy_16844 = _16844;
                vec3 _16850 = max(mix(_15928, mp_copy_15792, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _16866 = (_16827 * frag_info.gi_grid.xyz) - _15781;
                highp float _16868 = length(_16866);
                highp vec3 _31086 = vec3(0.0);
                if (_16868 > 9.9999997473787516355514526367188e-06)
                {
                    _31086 = _16866 / vec3(_16868);
                }
                else
                {
                    _31086 = _30995;
                }
                mp_copy_31086 = _31086;
                float _16886 = pow((dot(_31086, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _17011 = _16827 - (frag_info.gi_counts.xyz * floor(_16827 / frag_info.gi_counts.xyz));
                highp float _17027 = _17011.x + (frag_info.gi_counts.x * (_17011.y + (frag_info.gi_counts.y * _17011.z)));
                float _31091 = 0.0;
                if (_15979)
                {
                    highp float _17035 = floor(_17027 / frag_info.gi_counts.w);
                    highp vec2 _17049 = vec2((_17027 - (_17035 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17035 * 16.0));
                    vec3 _16909 = -mp_copy_31086;
                    vec3 _17097 = _16909 / vec3((abs(_16909.x) + abs(_16909.y)) + abs(_16909.z));
                    vec2 _31087 = vec2(0.0);
                    if (_17097.z >= 0.0)
                    {
                        _31087 = _17097.xy;
                    }
                    else
                    {
                        _31087 = (vec2(1.0) - abs(_17097.yx)) * vec2((_17097.x >= 0.0) ? 1.0 : (-1.0), (_17097.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _16913 = texture(irradiance_field, clamp((_17049 + vec2(1.0)) + (clamp((_31087 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17049 + vec2(0.5), _17049 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _16918 = _16913.x * frag_info.gi_visibility.z;
                    highp float _16930 = abs((_16918 * _16918) - ((_16913.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _16936 = (_16868 - _16918) - frag_info.gi_visibility.y;
                    highp float _31088 = 0.0;
                    if (_16936 <= 0.0)
                    {
                        _31088 = 1.0;
                    }
                    else
                    {
                        _31088 = _16930 / (_16930 + (_16936 * _16936));
                    }
                    _31091 = _16886 * mix(1.0, max(0.0500000007450580596923828125, (_31088 * _31088) * _31088), frag_info.gi_visibility.x);
                }
                else
                {
                    _31091 = _16886;
                }
                float _16964 = max(9.9999999747524270787835121154785e-07, _31091);
                float _31092 = 0.0;
                if (_16964 < 0.20000000298023223876953125)
                {
                    _31092 = _16964 * ((_16964 * _16964) * 25.0);
                }
                else
                {
                    _31092 = _16964;
                }
                float _16979 = _31092 * (((_16850.x * _16850.y) * _16850.z) * mp_copy_16844);
                highp float _17138 = floor(_17027 / frag_info.gi_counts.w);
                highp vec2 _17152 = vec2((_17027 - (_17138 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_17138 * 8.0));
                vec2 _31093 = vec2(0.0);
                if (_16285)
                {
                    _31093 = _16282.xy;
                }
                else
                {
                    _31093 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _16991 = texture(irradiance_field, clamp((_17152 + vec2(1.0)) + (clamp((_31093 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _17152 + vec2(0.5), _17152 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _17286 = _15786 + vec3(1.0, 1.0, 0.0);
                highp vec3 _17291 = _17286 - frag_info.gi_anchor.xyz;
                bool _17294 = any(lessThan(_17291, vec3(0.0)));
                bool _17302 = false;
                if (!_17294)
                {
                    _17302 = any(greaterThanEqual(_17291, frag_info.gi_counts.xyz));
                }
                else
                {
                    _17302 = _17294;
                }
                vec3 mp_copy_31095 = vec3(0.0);
                highp float _17303 = _17302 ? 0.0 : 1.0;
                float mp_copy_17303 = _17303;
                vec3 _17309 = max(mix(_15928, mp_copy_15792, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _17325 = (_17286 * frag_info.gi_grid.xyz) - _15781;
                highp float _17327 = length(_17325);
                highp vec3 _31095 = vec3(0.0);
                if (_17327 > 9.9999997473787516355514526367188e-06)
                {
                    _31095 = _17325 / vec3(_17327);
                }
                else
                {
                    _31095 = _30995;
                }
                mp_copy_31095 = _31095;
                float _17345 = pow((dot(_31095, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _17470 = _17286 - (frag_info.gi_counts.xyz * floor(_17286 / frag_info.gi_counts.xyz));
                highp float _17486 = _17470.x + (frag_info.gi_counts.x * (_17470.y + (frag_info.gi_counts.y * _17470.z)));
                float _31100 = 0.0;
                if (_15979)
                {
                    highp float _17494 = floor(_17486 / frag_info.gi_counts.w);
                    highp vec2 _17508 = vec2((_17486 - (_17494 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17494 * 16.0));
                    vec3 _17368 = -mp_copy_31095;
                    vec3 _17556 = _17368 / vec3((abs(_17368.x) + abs(_17368.y)) + abs(_17368.z));
                    vec2 _31096 = vec2(0.0);
                    if (_17556.z >= 0.0)
                    {
                        _31096 = _17556.xy;
                    }
                    else
                    {
                        _31096 = (vec2(1.0) - abs(_17556.yx)) * vec2((_17556.x >= 0.0) ? 1.0 : (-1.0), (_17556.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _17372 = texture(irradiance_field, clamp((_17508 + vec2(1.0)) + (clamp((_31096 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17508 + vec2(0.5), _17508 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _17377 = _17372.x * frag_info.gi_visibility.z;
                    highp float _17389 = abs((_17377 * _17377) - ((_17372.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _17395 = (_17327 - _17377) - frag_info.gi_visibility.y;
                    highp float _31097 = 0.0;
                    if (_17395 <= 0.0)
                    {
                        _31097 = 1.0;
                    }
                    else
                    {
                        _31097 = _17389 / (_17389 + (_17395 * _17395));
                    }
                    _31100 = _17345 * mix(1.0, max(0.0500000007450580596923828125, (_31097 * _31097) * _31097), frag_info.gi_visibility.x);
                }
                else
                {
                    _31100 = _17345;
                }
                float _17423 = max(9.9999999747524270787835121154785e-07, _31100);
                float _31101 = 0.0;
                if (_17423 < 0.20000000298023223876953125)
                {
                    _31101 = _17423 * ((_17423 * _17423) * 25.0);
                }
                else
                {
                    _31101 = _17423;
                }
                float _17438 = _31101 * (((_17309.x * _17309.y) * _17309.z) * mp_copy_17303);
                highp float _17597 = floor(_17486 / frag_info.gi_counts.w);
                highp vec2 _17611 = vec2((_17486 - (_17597 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_17597 * 8.0));
                vec2 _31102 = vec2(0.0);
                if (_16285)
                {
                    _31102 = _16282.xy;
                }
                else
                {
                    _31102 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _17450 = texture(irradiance_field, clamp((_17611 + vec2(1.0)) + (clamp((_31102 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _17611 + vec2(0.5), _17611 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _17745 = _15786 + vec3(0.0, 0.0, 1.0);
                highp vec3 _17750 = _17745 - frag_info.gi_anchor.xyz;
                bool _17753 = any(lessThan(_17750, vec3(0.0)));
                bool _17761 = false;
                if (!_17753)
                {
                    _17761 = any(greaterThanEqual(_17750, frag_info.gi_counts.xyz));
                }
                else
                {
                    _17761 = _17753;
                }
                vec3 mp_copy_31104 = vec3(0.0);
                highp float _17762 = _17761 ? 0.0 : 1.0;
                float mp_copy_17762 = _17762;
                vec3 _17768 = max(mix(_15928, mp_copy_15792, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _17784 = (_17745 * frag_info.gi_grid.xyz) - _15781;
                highp float _17786 = length(_17784);
                highp vec3 _31104 = vec3(0.0);
                if (_17786 > 9.9999997473787516355514526367188e-06)
                {
                    _31104 = _17784 / vec3(_17786);
                }
                else
                {
                    _31104 = _30995;
                }
                mp_copy_31104 = _31104;
                float _17804 = pow((dot(_31104, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _17929 = _17745 - (frag_info.gi_counts.xyz * floor(_17745 / frag_info.gi_counts.xyz));
                highp float _17945 = _17929.x + (frag_info.gi_counts.x * (_17929.y + (frag_info.gi_counts.y * _17929.z)));
                float _31109 = 0.0;
                if (_15979)
                {
                    highp float _17953 = floor(_17945 / frag_info.gi_counts.w);
                    highp vec2 _17967 = vec2((_17945 - (_17953 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_17953 * 16.0));
                    vec3 _17827 = -mp_copy_31104;
                    vec3 _18015 = _17827 / vec3((abs(_17827.x) + abs(_17827.y)) + abs(_17827.z));
                    vec2 _31105 = vec2(0.0);
                    if (_18015.z >= 0.0)
                    {
                        _31105 = _18015.xy;
                    }
                    else
                    {
                        _31105 = (vec2(1.0) - abs(_18015.yx)) * vec2((_18015.x >= 0.0) ? 1.0 : (-1.0), (_18015.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _17831 = texture(irradiance_field, clamp((_17967 + vec2(1.0)) + (clamp((_31105 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _17967 + vec2(0.5), _17967 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _17836 = _17831.x * frag_info.gi_visibility.z;
                    highp float _17848 = abs((_17836 * _17836) - ((_17831.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _17854 = (_17786 - _17836) - frag_info.gi_visibility.y;
                    highp float _31106 = 0.0;
                    if (_17854 <= 0.0)
                    {
                        _31106 = 1.0;
                    }
                    else
                    {
                        _31106 = _17848 / (_17848 + (_17854 * _17854));
                    }
                    _31109 = _17804 * mix(1.0, max(0.0500000007450580596923828125, (_31106 * _31106) * _31106), frag_info.gi_visibility.x);
                }
                else
                {
                    _31109 = _17804;
                }
                float _17882 = max(9.9999999747524270787835121154785e-07, _31109);
                float _31110 = 0.0;
                if (_17882 < 0.20000000298023223876953125)
                {
                    _31110 = _17882 * ((_17882 * _17882) * 25.0);
                }
                else
                {
                    _31110 = _17882;
                }
                float _17897 = _31110 * (((_17768.x * _17768.y) * _17768.z) * mp_copy_17762);
                highp float _18056 = floor(_17945 / frag_info.gi_counts.w);
                highp vec2 _18070 = vec2((_17945 - (_18056 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18056 * 8.0));
                vec2 _31111 = vec2(0.0);
                if (_16285)
                {
                    _31111 = _16282.xy;
                }
                else
                {
                    _31111 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _17909 = texture(irradiance_field, clamp((_18070 + vec2(1.0)) + (clamp((_31111 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18070 + vec2(0.5), _18070 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _18204 = _15786 + vec3(1.0, 0.0, 1.0);
                highp vec3 _18209 = _18204 - frag_info.gi_anchor.xyz;
                bool _18212 = any(lessThan(_18209, vec3(0.0)));
                bool _18220 = false;
                if (!_18212)
                {
                    _18220 = any(greaterThanEqual(_18209, frag_info.gi_counts.xyz));
                }
                else
                {
                    _18220 = _18212;
                }
                vec3 mp_copy_31113 = vec3(0.0);
                highp float _18221 = _18220 ? 0.0 : 1.0;
                float mp_copy_18221 = _18221;
                vec3 _18227 = max(mix(_15928, mp_copy_15792, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _18243 = (_18204 * frag_info.gi_grid.xyz) - _15781;
                highp float _18245 = length(_18243);
                highp vec3 _31113 = vec3(0.0);
                if (_18245 > 9.9999997473787516355514526367188e-06)
                {
                    _31113 = _18243 / vec3(_18245);
                }
                else
                {
                    _31113 = _30995;
                }
                mp_copy_31113 = _31113;
                float _18263 = pow((dot(_31113, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _18388 = _18204 - (frag_info.gi_counts.xyz * floor(_18204 / frag_info.gi_counts.xyz));
                highp float _18404 = _18388.x + (frag_info.gi_counts.x * (_18388.y + (frag_info.gi_counts.y * _18388.z)));
                float _31118 = 0.0;
                if (_15979)
                {
                    highp float _18412 = floor(_18404 / frag_info.gi_counts.w);
                    highp vec2 _18426 = vec2((_18404 - (_18412 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_18412 * 16.0));
                    vec3 _18286 = -mp_copy_31113;
                    vec3 _18474 = _18286 / vec3((abs(_18286.x) + abs(_18286.y)) + abs(_18286.z));
                    vec2 _31114 = vec2(0.0);
                    if (_18474.z >= 0.0)
                    {
                        _31114 = _18474.xy;
                    }
                    else
                    {
                        _31114 = (vec2(1.0) - abs(_18474.yx)) * vec2((_18474.x >= 0.0) ? 1.0 : (-1.0), (_18474.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _18290 = texture(irradiance_field, clamp((_18426 + vec2(1.0)) + (clamp((_31114 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _18426 + vec2(0.5), _18426 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _18295 = _18290.x * frag_info.gi_visibility.z;
                    highp float _18307 = abs((_18295 * _18295) - ((_18290.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _18313 = (_18245 - _18295) - frag_info.gi_visibility.y;
                    highp float _31115 = 0.0;
                    if (_18313 <= 0.0)
                    {
                        _31115 = 1.0;
                    }
                    else
                    {
                        _31115 = _18307 / (_18307 + (_18313 * _18313));
                    }
                    _31118 = _18263 * mix(1.0, max(0.0500000007450580596923828125, (_31115 * _31115) * _31115), frag_info.gi_visibility.x);
                }
                else
                {
                    _31118 = _18263;
                }
                float _18341 = max(9.9999999747524270787835121154785e-07, _31118);
                float _31119 = 0.0;
                if (_18341 < 0.20000000298023223876953125)
                {
                    _31119 = _18341 * ((_18341 * _18341) * 25.0);
                }
                else
                {
                    _31119 = _18341;
                }
                float _18356 = _31119 * (((_18227.x * _18227.y) * _18227.z) * mp_copy_18221);
                highp float _18515 = floor(_18404 / frag_info.gi_counts.w);
                highp vec2 _18529 = vec2((_18404 - (_18515 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18515 * 8.0));
                vec2 _31120 = vec2(0.0);
                if (_16285)
                {
                    _31120 = _16282.xy;
                }
                else
                {
                    _31120 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _18368 = texture(irradiance_field, clamp((_18529 + vec2(1.0)) + (clamp((_31120 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18529 + vec2(0.5), _18529 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _18663 = _15786 + vec3(0.0, 1.0, 1.0);
                highp vec3 _18668 = _18663 - frag_info.gi_anchor.xyz;
                bool _18671 = any(lessThan(_18668, vec3(0.0)));
                bool _18679 = false;
                if (!_18671)
                {
                    _18679 = any(greaterThanEqual(_18668, frag_info.gi_counts.xyz));
                }
                else
                {
                    _18679 = _18671;
                }
                vec3 mp_copy_31122 = vec3(0.0);
                highp float _18680 = _18679 ? 0.0 : 1.0;
                float mp_copy_18680 = _18680;
                vec3 _18686 = max(mix(_15928, mp_copy_15792, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
                highp vec3 _18702 = (_18663 * frag_info.gi_grid.xyz) - _15781;
                highp float _18704 = length(_18702);
                highp vec3 _31122 = vec3(0.0);
                if (_18704 > 9.9999997473787516355514526367188e-06)
                {
                    _31122 = _18702 / vec3(_18704);
                }
                else
                {
                    _31122 = _30995;
                }
                mp_copy_31122 = _31122;
                float _18722 = pow((dot(_31122, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _18847 = _18663 - (frag_info.gi_counts.xyz * floor(_18663 / frag_info.gi_counts.xyz));
                highp float _18863 = _18847.x + (frag_info.gi_counts.x * (_18847.y + (frag_info.gi_counts.y * _18847.z)));
                float _31127 = 0.0;
                if (_15979)
                {
                    highp float _18871 = floor(_18863 / frag_info.gi_counts.w);
                    highp vec2 _18885 = vec2((_18863 - (_18871 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_18871 * 16.0));
                    vec3 _18745 = -mp_copy_31122;
                    vec3 _18933 = _18745 / vec3((abs(_18745.x) + abs(_18745.y)) + abs(_18745.z));
                    vec2 _31123 = vec2(0.0);
                    if (_18933.z >= 0.0)
                    {
                        _31123 = _18933.xy;
                    }
                    else
                    {
                        _31123 = (vec2(1.0) - abs(_18933.yx)) * vec2((_18933.x >= 0.0) ? 1.0 : (-1.0), (_18933.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _18749 = texture(irradiance_field, clamp((_18885 + vec2(1.0)) + (clamp((_31123 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _18885 + vec2(0.5), _18885 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _18754 = _18749.x * frag_info.gi_visibility.z;
                    highp float _18766 = abs((_18754 * _18754) - ((_18749.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _18772 = (_18704 - _18754) - frag_info.gi_visibility.y;
                    highp float _31124 = 0.0;
                    if (_18772 <= 0.0)
                    {
                        _31124 = 1.0;
                    }
                    else
                    {
                        _31124 = _18766 / (_18766 + (_18772 * _18772));
                    }
                    _31127 = _18722 * mix(1.0, max(0.0500000007450580596923828125, (_31124 * _31124) * _31124), frag_info.gi_visibility.x);
                }
                else
                {
                    _31127 = _18722;
                }
                float _18800 = max(9.9999999747524270787835121154785e-07, _31127);
                float _31128 = 0.0;
                if (_18800 < 0.20000000298023223876953125)
                {
                    _31128 = _18800 * ((_18800 * _18800) * 25.0);
                }
                else
                {
                    _31128 = _18800;
                }
                float _18815 = _31128 * (((_18686.x * _18686.y) * _18686.z) * mp_copy_18680);
                highp float _18974 = floor(_18863 / frag_info.gi_counts.w);
                highp vec2 _18988 = vec2((_18863 - (_18974 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_18974 * 8.0));
                vec2 _31129 = vec2(0.0);
                if (_16285)
                {
                    _31129 = _16282.xy;
                }
                else
                {
                    _31129 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _18827 = texture(irradiance_field, clamp((_18988 + vec2(1.0)) + (clamp((_31129 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _18988 + vec2(0.5), _18988 + vec2(7.5)) * frag_info.gi_atlas.zw);
                highp vec3 _19122 = _15786 + vec3(1.0);
                highp vec3 _19127 = _19122 - frag_info.gi_anchor.xyz;
                bool _19130 = any(lessThan(_19127, vec3(0.0)));
                bool _19138 = false;
                if (!_19130)
                {
                    _19138 = any(greaterThanEqual(_19127, frag_info.gi_counts.xyz));
                }
                else
                {
                    _19138 = _19130;
                }
                vec3 mp_copy_31131 = vec3(0.0);
                highp float _19139 = _19138 ? 0.0 : 1.0;
                float mp_copy_19139 = _19139;
                vec3 _19145 = max(mp_copy_15792, vec3(0.001000000047497451305389404296875));
                highp vec3 _19161 = (_19122 * frag_info.gi_grid.xyz) - _15781;
                highp float _19163 = length(_19161);
                highp vec3 _31131 = vec3(0.0);
                if (_19163 > 9.9999997473787516355514526367188e-06)
                {
                    _31131 = _19161 / vec3(_19163);
                }
                else
                {
                    _31131 = _30995;
                }
                mp_copy_31131 = _31131;
                float _19181 = pow((dot(_31131, _30995) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
                highp vec3 _19306 = _19122 - (frag_info.gi_counts.xyz * floor(_19122 / frag_info.gi_counts.xyz));
                highp float _19322 = _19306.x + (frag_info.gi_counts.x * (_19306.y + (frag_info.gi_counts.y * _19306.z)));
                float _31136 = 0.0;
                if (_15979)
                {
                    highp float _19330 = floor(_19322 / frag_info.gi_counts.w);
                    highp vec2 _19344 = vec2((_19322 - (_19330 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_19330 * 16.0));
                    vec3 _19204 = -mp_copy_31131;
                    vec3 _19392 = _19204 / vec3((abs(_19204.x) + abs(_19204.y)) + abs(_19204.z));
                    vec2 _31132 = vec2(0.0);
                    if (_19392.z >= 0.0)
                    {
                        _31132 = _19392.xy;
                    }
                    else
                    {
                        _31132 = (vec2(1.0) - abs(_19392.yx)) * vec2((_19392.x >= 0.0) ? 1.0 : (-1.0), (_19392.y >= 0.0) ? 1.0 : (-1.0));
                    }
                    highp vec4 _19208 = texture(irradiance_field, clamp((_19344 + vec2(1.0)) + (clamp((_31132 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _19344 + vec2(0.5), _19344 + vec2(15.5)) * frag_info.gi_atlas.zw);
                    highp float _19213 = _19208.x * frag_info.gi_visibility.z;
                    highp float _19225 = abs((_19213 * _19213) - ((_19208.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                    highp float _19231 = (_19163 - _19213) - frag_info.gi_visibility.y;
                    highp float _31133 = 0.0;
                    if (_19231 <= 0.0)
                    {
                        _31133 = 1.0;
                    }
                    else
                    {
                        _31133 = _19225 / (_19225 + (_19231 * _19231));
                    }
                    _31136 = _19181 * mix(1.0, max(0.0500000007450580596923828125, (_31133 * _31133) * _31133), frag_info.gi_visibility.x);
                }
                else
                {
                    _31136 = _19181;
                }
                float _19259 = max(9.9999999747524270787835121154785e-07, _31136);
                float _31137 = 0.0;
                if (_19259 < 0.20000000298023223876953125)
                {
                    _31137 = _19259 * ((_19259 * _19259) * 25.0);
                }
                else
                {
                    _31137 = _19259;
                }
                float _19274 = _31137 * (((_19145.x * _19145.y) * _19145.z) * mp_copy_19139);
                highp float _19433 = floor(_19322 / frag_info.gi_counts.w);
                highp vec2 _19447 = vec2((_19322 - (_19433 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_19433 * 8.0));
                vec2 _31138 = vec2(0.0);
                if (_16285)
                {
                    _31138 = _16282.xy;
                }
                else
                {
                    _31138 = (vec2(1.0) - abs(_16282.yx)) * vec2((_16282.x >= 0.0) ? 1.0 : (-1.0), (_16282.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _15839 = ((((((vec4(max(_16073.xyz, vec3(0.0)) * _16061, _16061) + vec4(max(_16532.xyz, vec3(0.0)) * _16520, _16520)) + vec4(max(_16991.xyz, vec3(0.0)) * _16979, _16979)) + vec4(max(_17450.xyz, vec3(0.0)) * _17438, _17438)) + vec4(max(_17909.xyz, vec3(0.0)) * _17897, _17897)) + vec4(max(_18368.xyz, vec3(0.0)) * _18356, _18356)) + vec4(max(_18827.xyz, vec3(0.0)) * _18815, _18815)) + vec4(max(texture(irradiance_field, clamp((_19447 + vec2(1.0)) + (clamp((_31138 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _19447 + vec2(0.5), _19447 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _19274, _19274);
                highp float _15841 = _15839.w;
                highp vec3 _31140 = vec3(0.0);
                if (_15841 > 9.9999999747524270787835121154785e-07)
                {
                    _31140 = _15839.xyz / vec3(_15841);
                }
                else
                {
                    _31140 = vec3(0.0);
                }
                _31258 = mix(_14155, _31140 * _15668, vec3(_31067));
            }
            else
            {
                _31258 = _14155;
            }
            vec2 _14181 = clamp(vec2(_14093, _31040), vec2(0.0), vec2(0.9900000095367431640625));
            vec4 _14183 = texture(brdf_lut, vec2(_14181.x * 0.3333333432674407958984375, _14181.y));
            float _14187 = _14183.x;
            float _14190 = _14183.y;
            vec3 _14192 = ((_14085 + ((max(vec3(1.0 - _31040), _14085) - _14085) * pow(clamp(1.0 - _14093, 0.0, 1.0), 5.0))) * _14187) + vec3(_14190);
            float _14198 = 1.0 - (_14187 + _14190);
            vec3 _14202 = vec3(1.0) - _14085;
            vec3 _14205 = _14085 + (_14202 * vec3(0.0476190485060214996337890625));
            vec3 _14216 = ((_14192 * _14198) * _14205) / (vec3(1.0) - (_14205 * _14198));
            float _14219 = 1.0 - _7307;
            vec3 _14220 = _13990 * _14219;
            float _31996 = 0.0;
            if ((frag_info.ssao_params.y > 1.5) && _14113)
            {
                float _19555 = max(acos(clamp(exp2(((-3.321929931640625) * _31040) * _31040), 0.0, 1.0)), 0.100000001490116119384765625);
                _31996 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_31055, _14097), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _31328, 0.0, 1.0)))) + _19555) / (2.0 * _19555), 0.0, 1.0));
            }
            else
            {
                float _31997 = 0.0;
                if (frag_info.ssao_params.y > 0.5)
                {
                    _31997 = clamp((pow(_14089 + _31328, exp2(((-16.0) * _31040) - 1.0)) - 1.0) + _31328, 0.0, 1.0);
                }
                else
                {
                    _31997 = _31328;
                }
                _31996 = _31997;
            }
            bool _14269 = frag_info.has_directional_light > 0.5;
            float _31450 = 0.0;
            vec3 _32080 = vec3(0.0);
            if (_14269)
            {
                highp vec3 _14275 = -normalize(frag_info.directional_light_direction.xyz);
                _32080 = _14275;
                _31450 = dot(_7174, _14275);
            }
            else
            {
                _32080 = vec3(0.0);
                _31450 = 0.0;
            }
            float _14282 = clamp(_31450 * 6.666666507720947265625, 0.0, 1.0);
            bool _14291 = false;
            if (_14269)
            {
                _14291 = frag_info.casts_shadow > 0.5;
            }
            else
            {
                _14291 = _14269;
            }
            float _31687 = 0.0;
            if (_14291 && (_14282 > 0.0))
            {
                int _19676 = int(frag_info.shadow_cascade_count);
                float _20125 = max(dot(_7174, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
                float _20128 = _20125 * _20125;
                highp vec3 _20148 = v_position + (_7174 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _20128, 0.0)) / _20128, 8.0))));
                highp float _19682 = frag_info.directional_light_color.w * 0.5;
                float _31504 = 0.0;
                float _31544 = 0.0;
                if (_19676 > 0)
                {
                    highp vec4 _19699 = frag_info.light_space_matrix[0] * vec4(_20148, 1.0);
                    highp vec3 _19705 = _19699.xyz / vec3(_19699.w);
                    highp vec2 _19708 = _19705.xy * 0.5;
                    highp vec2 _19710 = _19708 + vec2(0.5);
                    highp float _19717 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
                    highp float _19719 = _19710.x;
                    bool _19721 = _19719 < _19717;
                    bool _19730 = false;
                    if (!_19721)
                    {
                        _19730 = _19719 > (1.0 - _19717);
                    }
                    else
                    {
                        _19730 = _19721;
                    }
                    bool _19738 = false;
                    if (!_19730)
                    {
                        _19738 = _19710.y < _19717;
                    }
                    else
                    {
                        _19738 = _19730;
                    }
                    bool _19747 = false;
                    if (!_19738)
                    {
                        _19747 = _19710.y > (1.0 - _19717);
                    }
                    else
                    {
                        _19747 = _19738;
                    }
                    bool _19754 = false;
                    if (!_19747)
                    {
                        _19754 = _19705.z < 0.0;
                    }
                    else
                    {
                        _19754 = _19747;
                    }
                    bool _19761 = false;
                    if (!_19754)
                    {
                        _19761 = _19705.z > 1.0;
                    }
                    else
                    {
                        _19761 = _19754;
                    }
                    float _31505 = 0.0;
                    float _31545 = 0.0;
                    if (!_19761)
                    {
                        highp vec2 _20156 = vec2(_19717);
                        highp vec2 _20161 = vec2(_19717 + max(_19682, 9.9999997473787516355514526367188e-05));
                        highp vec2 _20169 = vec2(0.5) - _19708;
                        highp vec2 _20171 = smoothstep(_20156, _20161, _19710) * smoothstep(_20156, _20161, _20169);
                        float _31451 = 0.0;
                        if (_19682 > 0.0)
                        {
                            _31451 = _20171.x * _20171.y;
                        }
                        else
                        {
                            _31451 = 1.0;
                        }
                        float _19770 = min(_31451, 1.0);
                        bool _19772 = _19770 > 0.0;
                        float _31546 = 0.0;
                        if (_19772)
                        {
                            highp float _20283 = _19705.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                            highp float _20289 = 1.0 / (float(_19676) + frag_info.spot_shadow_params.x);
                            highp float _20291 = frag_info.directional_light_direction.w;
                            float mp_copy_20291 = _20291;
                            float _20297 = step(0.5, mp_copy_20291) * (1.0 - step(1.5, mp_copy_20291));
                            highp float _20308 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _20297);
                            float mp_copy_20308 = _20308;
                            float _20310 = cos(mp_copy_20308);
                            float _20312 = sin(mp_copy_20308);
                            highp float _31469 = 0.0;
                            if ((_20291 > 1.5) && (_20291 < 2.5))
                            {
                                highp float _20331 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _20336 = max(_20331 * _20283, frag_info.shadow_texel_size);
                                float _31459 = 0.0;
                                highp float _31460 = 0.0;
                                _31460 = 0.0;
                                _31459 = 0.0;
                                highp float _20358 = 0.0;
                                float _20361 = 0.0;
                                for (int _31458 = 0; _31458 < 9; _31460 = _20358, _31459 = _20361, _31458++)
                                {
                                    vec2 _33986 = vec2(0.0);
                                    do
                                    {
                                        if (_31458 == 0)
                                        {
                                            _33986 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31458 == 1)
                                        {
                                            _33986 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31458 == 2)
                                        {
                                            _33986 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31458 == 3)
                                        {
                                            _33986 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31458 == 4)
                                        {
                                            _33986 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31458 == 5)
                                        {
                                            _33986 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31458 == 6)
                                        {
                                            _33986 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31458 == 7)
                                        {
                                            _33986 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31458 == 8)
                                        {
                                            _33986 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31458 == 9)
                                        {
                                            _33986 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31458 == 10)
                                        {
                                            _33986 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31458 == 11)
                                        {
                                            _33986 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31458 == 12)
                                        {
                                            _33986 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31458 == 13)
                                        {
                                            _33986 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31458 == 14)
                                        {
                                            _33986 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31458 == 15)
                                        {
                                            _33986 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33986 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _20603 = clamp(_19710 + (vec2((_33986.x * _20310) - (_33986.y * _20312), (_33986.x * _20312) + (_33986.y * _20310)) * _20336), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _20612 = _20603.y;
                                    highp vec2 _20613 = vec2(_20603.x * _20289, _20612);
                                    _20613.y = 1.0 - _20612;
                                    highp vec4 _20620 = texture(shadow_map, _20613);
                                    highp float _20621 = _20620.x;
                                    highp float _20353 = step(_20621, _20283);
                                    float mp_copy_20353 = _20353;
                                    _20358 = _31460 + (_20621 * _20353);
                                    _20361 = _31459 + mp_copy_20353;
                                }
                                highp float _31461 = 0.0;
                                if (_31459 > 0.0)
                                {
                                    _31461 = _31460 / _31459;
                                }
                                else
                                {
                                    _31461 = _20283;
                                }
                                _31469 = clamp(_20331 * max(_20283 - _31461, 0.0), frag_info.shadow_texel_size, _19717);
                            }
                            else
                            {
                                _31469 = _19717;
                            }
                            float _31476 = 0.0;
                            if (_20291 > 2.5)
                            {
                                highp vec2 _20649 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _20653 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _20654 = clamp(_19710 + (vec2(-0.707099974155426025390625) * _31469), _20649, _20653);
                                highp vec2 _20665 = (vec2(_20654.x, 1.0 - _20654.y) / _20649) - vec2(0.5);
                                highp vec2 _20667 = floor(_20665);
                                highp vec2 _20670 = _20665 - _20667;
                                highp vec2 _20675 = (_20667 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20685 = vec2(_20675.x * _20289, _20675.y);
                                highp float _20689 = frag_info.shadow_texel_size * _20289;
                                highp vec2 _20692 = vec2(_20689, frag_info.shadow_texel_size);
                                highp vec2 _20701 = vec2(_20689, 0.0);
                                highp vec2 _20709 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _20738 = _20670.x;
                                highp float _20747 = mix(mix(float(_20283 <= texture(shadow_map, _20685).x), float(_20283 <= texture(shadow_map, _20685 + _20701).x), _20738), mix(float(_20283 <= texture(shadow_map, _20685 + _20709).x), float(_20283 <= texture(shadow_map, _20685 + _20692).x), _20738), _20670.y);
                                float mp_copy_20747 = _20747;
                                highp vec2 _20781 = clamp(_19710 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31469), _20649, _20653);
                                highp vec2 _20792 = (vec2(_20781.x, 1.0 - _20781.y) / _20649) - vec2(0.5);
                                highp vec2 _20794 = floor(_20792);
                                highp vec2 _20797 = _20792 - _20794;
                                highp vec2 _20802 = (_20794 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20812 = vec2(_20802.x * _20289, _20802.y);
                                highp float _20865 = _20797.x;
                                highp float _20874 = mix(mix(float(_20283 <= texture(shadow_map, _20812).x), float(_20283 <= texture(shadow_map, _20812 + _20701).x), _20865), mix(float(_20283 <= texture(shadow_map, _20812 + _20709).x), float(_20283 <= texture(shadow_map, _20812 + _20692).x), _20865), _20797.y);
                                float mp_copy_20874 = _20874;
                                highp vec2 _20908 = clamp(_19710 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31469), _20649, _20653);
                                highp vec2 _20919 = (vec2(_20908.x, 1.0 - _20908.y) / _20649) - vec2(0.5);
                                highp vec2 _20921 = floor(_20919);
                                highp vec2 _20924 = _20919 - _20921;
                                highp vec2 _20929 = (_20921 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _20939 = vec2(_20929.x * _20289, _20929.y);
                                highp float _20992 = _20924.x;
                                highp float _21001 = mix(mix(float(_20283 <= texture(shadow_map, _20939).x), float(_20283 <= texture(shadow_map, _20939 + _20701).x), _20992), mix(float(_20283 <= texture(shadow_map, _20939 + _20709).x), float(_20283 <= texture(shadow_map, _20939 + _20692).x), _20992), _20924.y);
                                float mp_copy_21001 = _21001;
                                highp vec2 _21035 = clamp(_19710 + (vec2(0.707099974155426025390625) * _31469), _20649, _20653);
                                highp vec2 _21046 = (vec2(_21035.x, 1.0 - _21035.y) / _20649) - vec2(0.5);
                                highp vec2 _21048 = floor(_21046);
                                highp vec2 _21051 = _21046 - _21048;
                                highp vec2 _21056 = (_21048 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21066 = vec2(_21056.x * _20289, _21056.y);
                                highp float _21119 = _21051.x;
                                highp float _21128 = mix(mix(float(_20283 <= texture(shadow_map, _21066).x), float(_20283 <= texture(shadow_map, _21066 + _20701).x), _21119), mix(float(_20283 <= texture(shadow_map, _21066 + _20709).x), float(_20283 <= texture(shadow_map, _21066 + _20692).x), _21119), _21051.y);
                                float mp_copy_21128 = _21128;
                                _31476 = (((mp_copy_20747 + mp_copy_20874) + mp_copy_21001) + mp_copy_21128) * 0.25;
                            }
                            else
                            {
                                int _20424 = (_20297 > 0.5) ? 17 : 16;
                                float _31472 = 0.0;
                                _31472 = 0.0;
                                float _20452 = 0.0;
                                for (int _31462 = 0; _31462 < 17; _31472 = _20452, _31462++)
                                {
                                    if (_31462 >= _20424)
                                    {
                                        break;
                                    }
                                    vec2 _31463 = vec2(0.0);
                                    do
                                    {
                                        if (_31462 == 0)
                                        {
                                            _31463 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31462 == 1)
                                        {
                                            _31463 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31462 == 2)
                                        {
                                            _31463 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31462 == 3)
                                        {
                                            _31463 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31462 == 4)
                                        {
                                            _31463 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31462 == 5)
                                        {
                                            _31463 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31462 == 6)
                                        {
                                            _31463 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31462 == 7)
                                        {
                                            _31463 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31462 == 8)
                                        {
                                            _31463 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31462 == 9)
                                        {
                                            _31463 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31462 == 10)
                                        {
                                            _31463 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31462 == 11)
                                        {
                                            _31463 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31462 == 12)
                                        {
                                            _31463 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31462 == 13)
                                        {
                                            _31463 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31462 == 14)
                                        {
                                            _31463 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31462 == 15)
                                        {
                                            _31463 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31463 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31465 = vec2(0.0);
                                    do
                                    {
                                        if (_31462 < 3)
                                        {
                                            _31465 = vec2(float(_31462) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31462 < 6)
                                        {
                                            _31465 = vec2((float(_31462 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31462 < 11)
                                        {
                                            _31465 = vec2((float(_31462 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31462 < 14)
                                        {
                                            _31465 = vec2((float(_31462 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31465 = vec2(float(_31462 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _20441 = mix(_31463, _31465, vec2(_20297));
                                    float _21268 = _20441.x;
                                    float _21272 = _20441.y;
                                    highp vec2 _21298 = clamp(_19710 + (vec2((_21268 * _20310) - (_21272 * _20312), (_21268 * _20312) + (_21272 * _20310)) * _31469), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _21308 = vec2(_21298.x * _20289, _21298.y);
                                    _21308.y = 1.0 - _21298.y;
                                    highp float _21320 = float(_20283 <= texture(shadow_map, _21308).x);
                                    float mp_copy_21320 = _21320;
                                    _20452 = _31472 + mp_copy_21320;
                                }
                                _31476 = _31472 / float(_20424);
                            }
                            bool _20465 = 0 == (_19676 - 1);
                            bool _20471 = false;
                            if (_20465)
                            {
                                _20471 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _20471 = _20465;
                            }
                            float _31477 = 0.0;
                            if (_20471)
                            {
                                highp vec2 _20478 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                                highp vec2 _20486 = smoothstep(vec2(0.0), _20478, _19710) * smoothstep(vec2(0.0), _20478, _20169);
                                _31477 = mix(1.0, _31476, _20486.x * _20486.y);
                            }
                            else
                            {
                                _31477 = _31476;
                            }
                            _31546 = _19770 * _31477;
                        }
                        else
                        {
                            _31546 = 0.0;
                        }
                        _31545 = _31546;
                        _31505 = _19772 ? _19770 : 0.0;
                    }
                    else
                    {
                        _31545 = 0.0;
                        _31505 = 0.0;
                    }
                    _31544 = _31545;
                    _31504 = _31505;
                }
                else
                {
                    _31544 = 0.0;
                    _31504 = 0.0;
                }
                float _31563 = 0.0;
                float _31603 = 0.0;
                if ((_31504 < 1.0) && (_19676 > 1))
                {
                    highp vec4 _19805 = frag_info.light_space_matrix[1] * vec4(_20148, 1.0);
                    highp vec3 _19811 = _19805.xyz / vec3(_19805.w);
                    highp vec2 _19814 = _19811.xy * 0.5;
                    highp vec2 _19816 = _19814 + vec2(0.5);
                    highp float _19823 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
                    highp float _19825 = _19816.x;
                    bool _19827 = _19825 < _19823;
                    bool _19836 = false;
                    if (!_19827)
                    {
                        _19836 = _19825 > (1.0 - _19823);
                    }
                    else
                    {
                        _19836 = _19827;
                    }
                    bool _19844 = false;
                    if (!_19836)
                    {
                        _19844 = _19816.y < _19823;
                    }
                    else
                    {
                        _19844 = _19836;
                    }
                    bool _19853 = false;
                    if (!_19844)
                    {
                        _19853 = _19816.y > (1.0 - _19823);
                    }
                    else
                    {
                        _19853 = _19844;
                    }
                    bool _19860 = false;
                    if (!_19853)
                    {
                        _19860 = _19811.z < 0.0;
                    }
                    else
                    {
                        _19860 = _19853;
                    }
                    bool _19867 = false;
                    if (!_19860)
                    {
                        _19867 = _19811.z > 1.0;
                    }
                    else
                    {
                        _19867 = _19860;
                    }
                    float _31564 = 0.0;
                    float _31604 = 0.0;
                    if (!_19867)
                    {
                        highp vec2 _21328 = vec2(_19823);
                        highp vec2 _21333 = vec2(_19823 + max(_19682, 9.9999997473787516355514526367188e-05));
                        highp vec2 _21341 = vec2(0.5) - _19814;
                        highp vec2 _21343 = smoothstep(_21328, _21333, _19816) * smoothstep(_21328, _21333, _21341);
                        float _31507 = 0.0;
                        if (_19682 > 0.0)
                        {
                            _31507 = _21343.x * _21343.y;
                        }
                        else
                        {
                            _31507 = 1.0;
                        }
                        float _19876 = min(_31507, 1.0 - _31504);
                        float _31565 = 0.0;
                        float _31605 = 0.0;
                        if (_19876 > 0.0)
                        {
                            highp float _21455 = _19811.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                            highp float _21461 = 1.0 / (float(_19676) + frag_info.spot_shadow_params.x);
                            highp float _21463 = frag_info.directional_light_direction.w;
                            float mp_copy_21463 = _21463;
                            float _21469 = step(0.5, mp_copy_21463) * (1.0 - step(1.5, mp_copy_21463));
                            highp float _21480 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _21469);
                            float mp_copy_21480 = _21480;
                            float _21482 = cos(mp_copy_21480);
                            float _21484 = sin(mp_copy_21480);
                            highp float _31525 = 0.0;
                            if ((_21463 > 1.5) && (_21463 < 2.5))
                            {
                                highp float _21503 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _21508 = max(_21503 * _21455, frag_info.shadow_texel_size);
                                float _31515 = 0.0;
                                highp float _31516 = 0.0;
                                _31516 = 0.0;
                                _31515 = 0.0;
                                highp float _21530 = 0.0;
                                float _21533 = 0.0;
                                for (int _31514 = 0; _31514 < 9; _31516 = _21530, _31515 = _21533, _31514++)
                                {
                                    vec2 _33982 = vec2(0.0);
                                    do
                                    {
                                        if (_31514 == 0)
                                        {
                                            _33982 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31514 == 1)
                                        {
                                            _33982 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31514 == 2)
                                        {
                                            _33982 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31514 == 3)
                                        {
                                            _33982 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31514 == 4)
                                        {
                                            _33982 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31514 == 5)
                                        {
                                            _33982 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31514 == 6)
                                        {
                                            _33982 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31514 == 7)
                                        {
                                            _33982 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31514 == 8)
                                        {
                                            _33982 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31514 == 9)
                                        {
                                            _33982 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31514 == 10)
                                        {
                                            _33982 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31514 == 11)
                                        {
                                            _33982 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31514 == 12)
                                        {
                                            _33982 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31514 == 13)
                                        {
                                            _33982 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31514 == 14)
                                        {
                                            _33982 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31514 == 15)
                                        {
                                            _33982 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33982 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _21775 = clamp(_19816 + (vec2((_33982.x * _21482) - (_33982.y * _21484), (_33982.x * _21484) + (_33982.y * _21482)) * _21508), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _21784 = _21775.y;
                                    highp vec2 _21785 = vec2((1.0 + _21775.x) * _21461, _21784);
                                    _21785.y = 1.0 - _21784;
                                    highp vec4 _21792 = texture(shadow_map, _21785);
                                    highp float _21793 = _21792.x;
                                    highp float _21525 = step(_21793, _21455);
                                    float mp_copy_21525 = _21525;
                                    _21530 = _31516 + (_21793 * _21525);
                                    _21533 = _31515 + mp_copy_21525;
                                }
                                highp float _31517 = 0.0;
                                if (_31515 > 0.0)
                                {
                                    _31517 = _31516 / _31515;
                                }
                                else
                                {
                                    _31517 = _21455;
                                }
                                _31525 = clamp(_21503 * max(_21455 - _31517, 0.0), frag_info.shadow_texel_size, _19823);
                            }
                            else
                            {
                                _31525 = _19823;
                            }
                            float _31532 = 0.0;
                            if (_21463 > 2.5)
                            {
                                highp vec2 _21821 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _21825 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _21826 = clamp(_19816 + (vec2(-0.707099974155426025390625) * _31525), _21821, _21825);
                                highp vec2 _21837 = (vec2(_21826.x, 1.0 - _21826.y) / _21821) - vec2(0.5);
                                highp vec2 _21839 = floor(_21837);
                                highp vec2 _21842 = _21837 - _21839;
                                highp vec2 _21847 = (_21839 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21857 = vec2((1.0 + _21847.x) * _21461, _21847.y);
                                highp float _21861 = frag_info.shadow_texel_size * _21461;
                                highp vec2 _21864 = vec2(_21861, frag_info.shadow_texel_size);
                                highp vec2 _21873 = vec2(_21861, 0.0);
                                highp vec2 _21881 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _21910 = _21842.x;
                                highp float _21919 = mix(mix(float(_21455 <= texture(shadow_map, _21857).x), float(_21455 <= texture(shadow_map, _21857 + _21873).x), _21910), mix(float(_21455 <= texture(shadow_map, _21857 + _21881).x), float(_21455 <= texture(shadow_map, _21857 + _21864).x), _21910), _21842.y);
                                float mp_copy_21919 = _21919;
                                highp vec2 _21953 = clamp(_19816 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31525), _21821, _21825);
                                highp vec2 _21964 = (vec2(_21953.x, 1.0 - _21953.y) / _21821) - vec2(0.5);
                                highp vec2 _21966 = floor(_21964);
                                highp vec2 _21969 = _21964 - _21966;
                                highp vec2 _21974 = (_21966 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _21984 = vec2((1.0 + _21974.x) * _21461, _21974.y);
                                highp float _22037 = _21969.x;
                                highp float _22046 = mix(mix(float(_21455 <= texture(shadow_map, _21984).x), float(_21455 <= texture(shadow_map, _21984 + _21873).x), _22037), mix(float(_21455 <= texture(shadow_map, _21984 + _21881).x), float(_21455 <= texture(shadow_map, _21984 + _21864).x), _22037), _21969.y);
                                float mp_copy_22046 = _22046;
                                highp vec2 _22080 = clamp(_19816 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31525), _21821, _21825);
                                highp vec2 _22091 = (vec2(_22080.x, 1.0 - _22080.y) / _21821) - vec2(0.5);
                                highp vec2 _22093 = floor(_22091);
                                highp vec2 _22096 = _22091 - _22093;
                                highp vec2 _22101 = (_22093 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _22111 = vec2((1.0 + _22101.x) * _21461, _22101.y);
                                highp float _22164 = _22096.x;
                                highp float _22173 = mix(mix(float(_21455 <= texture(shadow_map, _22111).x), float(_21455 <= texture(shadow_map, _22111 + _21873).x), _22164), mix(float(_21455 <= texture(shadow_map, _22111 + _21881).x), float(_21455 <= texture(shadow_map, _22111 + _21864).x), _22164), _22096.y);
                                float mp_copy_22173 = _22173;
                                highp vec2 _22207 = clamp(_19816 + (vec2(0.707099974155426025390625) * _31525), _21821, _21825);
                                highp vec2 _22218 = (vec2(_22207.x, 1.0 - _22207.y) / _21821) - vec2(0.5);
                                highp vec2 _22220 = floor(_22218);
                                highp vec2 _22223 = _22218 - _22220;
                                highp vec2 _22228 = (_22220 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _22238 = vec2((1.0 + _22228.x) * _21461, _22228.y);
                                highp float _22291 = _22223.x;
                                highp float _22300 = mix(mix(float(_21455 <= texture(shadow_map, _22238).x), float(_21455 <= texture(shadow_map, _22238 + _21873).x), _22291), mix(float(_21455 <= texture(shadow_map, _22238 + _21881).x), float(_21455 <= texture(shadow_map, _22238 + _21864).x), _22291), _22223.y);
                                float mp_copy_22300 = _22300;
                                _31532 = (((mp_copy_21919 + mp_copy_22046) + mp_copy_22173) + mp_copy_22300) * 0.25;
                            }
                            else
                            {
                                int _21596 = (_21469 > 0.5) ? 17 : 16;
                                float _31528 = 0.0;
                                _31528 = 0.0;
                                float _21624 = 0.0;
                                for (int _31518 = 0; _31518 < 17; _31528 = _21624, _31518++)
                                {
                                    if (_31518 >= _21596)
                                    {
                                        break;
                                    }
                                    vec2 _31519 = vec2(0.0);
                                    do
                                    {
                                        if (_31518 == 0)
                                        {
                                            _31519 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31518 == 1)
                                        {
                                            _31519 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31518 == 2)
                                        {
                                            _31519 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31518 == 3)
                                        {
                                            _31519 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31518 == 4)
                                        {
                                            _31519 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31518 == 5)
                                        {
                                            _31519 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31518 == 6)
                                        {
                                            _31519 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31518 == 7)
                                        {
                                            _31519 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31518 == 8)
                                        {
                                            _31519 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31518 == 9)
                                        {
                                            _31519 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31518 == 10)
                                        {
                                            _31519 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31518 == 11)
                                        {
                                            _31519 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31518 == 12)
                                        {
                                            _31519 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31518 == 13)
                                        {
                                            _31519 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31518 == 14)
                                        {
                                            _31519 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31518 == 15)
                                        {
                                            _31519 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31519 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31521 = vec2(0.0);
                                    do
                                    {
                                        if (_31518 < 3)
                                        {
                                            _31521 = vec2(float(_31518) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31518 < 6)
                                        {
                                            _31521 = vec2((float(_31518 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31518 < 11)
                                        {
                                            _31521 = vec2((float(_31518 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31518 < 14)
                                        {
                                            _31521 = vec2((float(_31518 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31521 = vec2(float(_31518 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _21613 = mix(_31519, _31521, vec2(_21469));
                                    float _22440 = _21613.x;
                                    float _22444 = _21613.y;
                                    highp vec2 _22470 = clamp(_19816 + (vec2((_22440 * _21482) - (_22444 * _21484), (_22440 * _21484) + (_22444 * _21482)) * _31525), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _22480 = vec2((1.0 + _22470.x) * _21461, _22470.y);
                                    _22480.y = 1.0 - _22470.y;
                                    highp float _22492 = float(_21455 <= texture(shadow_map, _22480).x);
                                    float mp_copy_22492 = _22492;
                                    _21624 = _31528 + mp_copy_22492;
                                }
                                _31532 = _31528 / float(_21596);
                            }
                            bool _21637 = 1 == (_19676 - 1);
                            bool _21643 = false;
                            if (_21637)
                            {
                                _21643 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _21643 = _21637;
                            }
                            float _31533 = 0.0;
                            if (_21643)
                            {
                                highp vec2 _21650 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                                highp vec2 _21658 = smoothstep(vec2(0.0), _21650, _19816) * smoothstep(vec2(0.0), _21650, _21341);
                                _31533 = mix(1.0, _31532, _21658.x * _21658.y);
                            }
                            else
                            {
                                _31533 = _31532;
                            }
                            _31605 = _31544 + (_19876 * _31533);
                            _31565 = _31504 + _19876;
                        }
                        else
                        {
                            _31605 = _31544;
                            _31565 = _31504;
                        }
                        _31604 = _31605;
                        _31564 = _31565;
                    }
                    else
                    {
                        _31604 = _31544;
                        _31564 = _31504;
                    }
                    _31603 = _31604;
                    _31563 = _31564;
                }
                else
                {
                    _31603 = _31544;
                    _31563 = _31504;
                }
                float _31622 = 0.0;
                float _31662 = 0.0;
                if ((_31563 < 1.0) && (_19676 > 2))
                {
                    highp vec4 _19911 = frag_info.light_space_matrix[2] * vec4(_20148, 1.0);
                    highp vec3 _19917 = _19911.xyz / vec3(_19911.w);
                    highp vec2 _19920 = _19917.xy * 0.5;
                    highp vec2 _19922 = _19920 + vec2(0.5);
                    highp float _19929 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
                    highp float _19931 = _19922.x;
                    bool _19933 = _19931 < _19929;
                    bool _19942 = false;
                    if (!_19933)
                    {
                        _19942 = _19931 > (1.0 - _19929);
                    }
                    else
                    {
                        _19942 = _19933;
                    }
                    bool _19950 = false;
                    if (!_19942)
                    {
                        _19950 = _19922.y < _19929;
                    }
                    else
                    {
                        _19950 = _19942;
                    }
                    bool _19959 = false;
                    if (!_19950)
                    {
                        _19959 = _19922.y > (1.0 - _19929);
                    }
                    else
                    {
                        _19959 = _19950;
                    }
                    bool _19966 = false;
                    if (!_19959)
                    {
                        _19966 = _19917.z < 0.0;
                    }
                    else
                    {
                        _19966 = _19959;
                    }
                    bool _19973 = false;
                    if (!_19966)
                    {
                        _19973 = _19917.z > 1.0;
                    }
                    else
                    {
                        _19973 = _19966;
                    }
                    float _31623 = 0.0;
                    float _31663 = 0.0;
                    if (!_19973)
                    {
                        highp vec2 _22500 = vec2(_19929);
                        highp vec2 _22505 = vec2(_19929 + max(_19682, 9.9999997473787516355514526367188e-05));
                        highp vec2 _22513 = vec2(0.5) - _19920;
                        highp vec2 _22515 = smoothstep(_22500, _22505, _19922) * smoothstep(_22500, _22505, _22513);
                        float _31566 = 0.0;
                        if (_19682 > 0.0)
                        {
                            _31566 = _22515.x * _22515.y;
                        }
                        else
                        {
                            _31566 = 1.0;
                        }
                        float _19982 = min(_31566, 1.0 - _31563);
                        float _31624 = 0.0;
                        float _31664 = 0.0;
                        if (_19982 > 0.0)
                        {
                            highp float _22627 = _19917.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                            highp float _22633 = 1.0 / (float(_19676) + frag_info.spot_shadow_params.x);
                            highp float _22635 = frag_info.directional_light_direction.w;
                            float mp_copy_22635 = _22635;
                            float _22641 = step(0.5, mp_copy_22635) * (1.0 - step(1.5, mp_copy_22635));
                            highp float _22652 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _22641);
                            float mp_copy_22652 = _22652;
                            float _22654 = cos(mp_copy_22652);
                            float _22656 = sin(mp_copy_22652);
                            highp float _31584 = 0.0;
                            if ((_22635 > 1.5) && (_22635 < 2.5))
                            {
                                highp float _22675 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _22680 = max(_22675 * _22627, frag_info.shadow_texel_size);
                                float _31574 = 0.0;
                                highp float _31575 = 0.0;
                                _31575 = 0.0;
                                _31574 = 0.0;
                                highp float _22702 = 0.0;
                                float _22705 = 0.0;
                                for (int _31573 = 0; _31573 < 9; _31575 = _22702, _31574 = _22705, _31573++)
                                {
                                    vec2 _33978 = vec2(0.0);
                                    do
                                    {
                                        if (_31573 == 0)
                                        {
                                            _33978 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31573 == 1)
                                        {
                                            _33978 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31573 == 2)
                                        {
                                            _33978 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31573 == 3)
                                        {
                                            _33978 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31573 == 4)
                                        {
                                            _33978 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31573 == 5)
                                        {
                                            _33978 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31573 == 6)
                                        {
                                            _33978 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31573 == 7)
                                        {
                                            _33978 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31573 == 8)
                                        {
                                            _33978 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31573 == 9)
                                        {
                                            _33978 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31573 == 10)
                                        {
                                            _33978 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31573 == 11)
                                        {
                                            _33978 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31573 == 12)
                                        {
                                            _33978 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31573 == 13)
                                        {
                                            _33978 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31573 == 14)
                                        {
                                            _33978 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31573 == 15)
                                        {
                                            _33978 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33978 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _22947 = clamp(_19922 + (vec2((_33978.x * _22654) - (_33978.y * _22656), (_33978.x * _22656) + (_33978.y * _22654)) * _22680), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _22956 = _22947.y;
                                    highp vec2 _22957 = vec2((2.0 + _22947.x) * _22633, _22956);
                                    _22957.y = 1.0 - _22956;
                                    highp vec4 _22964 = texture(shadow_map, _22957);
                                    highp float _22965 = _22964.x;
                                    highp float _22697 = step(_22965, _22627);
                                    float mp_copy_22697 = _22697;
                                    _22702 = _31575 + (_22965 * _22697);
                                    _22705 = _31574 + mp_copy_22697;
                                }
                                highp float _31576 = 0.0;
                                if (_31574 > 0.0)
                                {
                                    _31576 = _31575 / _31574;
                                }
                                else
                                {
                                    _31576 = _22627;
                                }
                                _31584 = clamp(_22675 * max(_22627 - _31576, 0.0), frag_info.shadow_texel_size, _19929);
                            }
                            else
                            {
                                _31584 = _19929;
                            }
                            float _31591 = 0.0;
                            if (_22635 > 2.5)
                            {
                                highp vec2 _22993 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _22997 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _22998 = clamp(_19922 + (vec2(-0.707099974155426025390625) * _31584), _22993, _22997);
                                highp vec2 _23009 = (vec2(_22998.x, 1.0 - _22998.y) / _22993) - vec2(0.5);
                                highp vec2 _23011 = floor(_23009);
                                highp vec2 _23014 = _23009 - _23011;
                                highp vec2 _23019 = (_23011 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23029 = vec2((2.0 + _23019.x) * _22633, _23019.y);
                                highp float _23033 = frag_info.shadow_texel_size * _22633;
                                highp vec2 _23036 = vec2(_23033, frag_info.shadow_texel_size);
                                highp vec2 _23045 = vec2(_23033, 0.0);
                                highp vec2 _23053 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _23082 = _23014.x;
                                highp float _23091 = mix(mix(float(_22627 <= texture(shadow_map, _23029).x), float(_22627 <= texture(shadow_map, _23029 + _23045).x), _23082), mix(float(_22627 <= texture(shadow_map, _23029 + _23053).x), float(_22627 <= texture(shadow_map, _23029 + _23036).x), _23082), _23014.y);
                                float mp_copy_23091 = _23091;
                                highp vec2 _23125 = clamp(_19922 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31584), _22993, _22997);
                                highp vec2 _23136 = (vec2(_23125.x, 1.0 - _23125.y) / _22993) - vec2(0.5);
                                highp vec2 _23138 = floor(_23136);
                                highp vec2 _23141 = _23136 - _23138;
                                highp vec2 _23146 = (_23138 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23156 = vec2((2.0 + _23146.x) * _22633, _23146.y);
                                highp float _23209 = _23141.x;
                                highp float _23218 = mix(mix(float(_22627 <= texture(shadow_map, _23156).x), float(_22627 <= texture(shadow_map, _23156 + _23045).x), _23209), mix(float(_22627 <= texture(shadow_map, _23156 + _23053).x), float(_22627 <= texture(shadow_map, _23156 + _23036).x), _23209), _23141.y);
                                float mp_copy_23218 = _23218;
                                highp vec2 _23252 = clamp(_19922 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31584), _22993, _22997);
                                highp vec2 _23263 = (vec2(_23252.x, 1.0 - _23252.y) / _22993) - vec2(0.5);
                                highp vec2 _23265 = floor(_23263);
                                highp vec2 _23268 = _23263 - _23265;
                                highp vec2 _23273 = (_23265 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23283 = vec2((2.0 + _23273.x) * _22633, _23273.y);
                                highp float _23336 = _23268.x;
                                highp float _23345 = mix(mix(float(_22627 <= texture(shadow_map, _23283).x), float(_22627 <= texture(shadow_map, _23283 + _23045).x), _23336), mix(float(_22627 <= texture(shadow_map, _23283 + _23053).x), float(_22627 <= texture(shadow_map, _23283 + _23036).x), _23336), _23268.y);
                                float mp_copy_23345 = _23345;
                                highp vec2 _23379 = clamp(_19922 + (vec2(0.707099974155426025390625) * _31584), _22993, _22997);
                                highp vec2 _23390 = (vec2(_23379.x, 1.0 - _23379.y) / _22993) - vec2(0.5);
                                highp vec2 _23392 = floor(_23390);
                                highp vec2 _23395 = _23390 - _23392;
                                highp vec2 _23400 = (_23392 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _23410 = vec2((2.0 + _23400.x) * _22633, _23400.y);
                                highp float _23463 = _23395.x;
                                highp float _23472 = mix(mix(float(_22627 <= texture(shadow_map, _23410).x), float(_22627 <= texture(shadow_map, _23410 + _23045).x), _23463), mix(float(_22627 <= texture(shadow_map, _23410 + _23053).x), float(_22627 <= texture(shadow_map, _23410 + _23036).x), _23463), _23395.y);
                                float mp_copy_23472 = _23472;
                                _31591 = (((mp_copy_23091 + mp_copy_23218) + mp_copy_23345) + mp_copy_23472) * 0.25;
                            }
                            else
                            {
                                int _22768 = (_22641 > 0.5) ? 17 : 16;
                                float _31587 = 0.0;
                                _31587 = 0.0;
                                float _22796 = 0.0;
                                for (int _31577 = 0; _31577 < 17; _31587 = _22796, _31577++)
                                {
                                    if (_31577 >= _22768)
                                    {
                                        break;
                                    }
                                    vec2 _31578 = vec2(0.0);
                                    do
                                    {
                                        if (_31577 == 0)
                                        {
                                            _31578 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31577 == 1)
                                        {
                                            _31578 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31577 == 2)
                                        {
                                            _31578 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31577 == 3)
                                        {
                                            _31578 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31577 == 4)
                                        {
                                            _31578 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31577 == 5)
                                        {
                                            _31578 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31577 == 6)
                                        {
                                            _31578 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31577 == 7)
                                        {
                                            _31578 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31577 == 8)
                                        {
                                            _31578 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31577 == 9)
                                        {
                                            _31578 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31577 == 10)
                                        {
                                            _31578 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31577 == 11)
                                        {
                                            _31578 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31577 == 12)
                                        {
                                            _31578 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31577 == 13)
                                        {
                                            _31578 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31577 == 14)
                                        {
                                            _31578 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31577 == 15)
                                        {
                                            _31578 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31578 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31580 = vec2(0.0);
                                    do
                                    {
                                        if (_31577 < 3)
                                        {
                                            _31580 = vec2(float(_31577) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31577 < 6)
                                        {
                                            _31580 = vec2((float(_31577 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31577 < 11)
                                        {
                                            _31580 = vec2((float(_31577 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31577 < 14)
                                        {
                                            _31580 = vec2((float(_31577 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31580 = vec2(float(_31577 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _22785 = mix(_31578, _31580, vec2(_22641));
                                    float _23612 = _22785.x;
                                    float _23616 = _22785.y;
                                    highp vec2 _23642 = clamp(_19922 + (vec2((_23612 * _22654) - (_23616 * _22656), (_23612 * _22656) + (_23616 * _22654)) * _31584), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _23652 = vec2((2.0 + _23642.x) * _22633, _23642.y);
                                    _23652.y = 1.0 - _23642.y;
                                    highp float _23664 = float(_22627 <= texture(shadow_map, _23652).x);
                                    float mp_copy_23664 = _23664;
                                    _22796 = _31587 + mp_copy_23664;
                                }
                                _31591 = _31587 / float(_22768);
                            }
                            bool _22809 = 2 == (_19676 - 1);
                            bool _22815 = false;
                            if (_22809)
                            {
                                _22815 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _22815 = _22809;
                            }
                            float _31592 = 0.0;
                            if (_22815)
                            {
                                highp vec2 _22822 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                                highp vec2 _22830 = smoothstep(vec2(0.0), _22822, _19922) * smoothstep(vec2(0.0), _22822, _22513);
                                _31592 = mix(1.0, _31591, _22830.x * _22830.y);
                            }
                            else
                            {
                                _31592 = _31591;
                            }
                            _31664 = _31603 + (_19982 * _31592);
                            _31624 = _31563 + _19982;
                        }
                        else
                        {
                            _31664 = _31603;
                            _31624 = _31563;
                        }
                        _31663 = _31664;
                        _31623 = _31624;
                    }
                    else
                    {
                        _31663 = _31603;
                        _31623 = _31563;
                    }
                    _31662 = _31663;
                    _31622 = _31623;
                }
                else
                {
                    _31662 = _31603;
                    _31622 = _31563;
                }
                float _31681 = 0.0;
                float _31684 = 0.0;
                if ((_31622 < 1.0) && (_19676 > 3))
                {
                    highp vec4 _20017 = frag_info.light_space_matrix[3] * vec4(_20148, 1.0);
                    highp vec3 _20023 = _20017.xyz / vec3(_20017.w);
                    highp vec2 _20026 = _20023.xy * 0.5;
                    highp vec2 _20028 = _20026 + vec2(0.5);
                    highp float _20035 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
                    highp float _20037 = _20028.x;
                    bool _20039 = _20037 < _20035;
                    bool _20048 = false;
                    if (!_20039)
                    {
                        _20048 = _20037 > (1.0 - _20035);
                    }
                    else
                    {
                        _20048 = _20039;
                    }
                    bool _20056 = false;
                    if (!_20048)
                    {
                        _20056 = _20028.y < _20035;
                    }
                    else
                    {
                        _20056 = _20048;
                    }
                    bool _20065 = false;
                    if (!_20056)
                    {
                        _20065 = _20028.y > (1.0 - _20035);
                    }
                    else
                    {
                        _20065 = _20056;
                    }
                    bool _20072 = false;
                    if (!_20065)
                    {
                        _20072 = _20023.z < 0.0;
                    }
                    else
                    {
                        _20072 = _20065;
                    }
                    bool _20079 = false;
                    if (!_20072)
                    {
                        _20079 = _20023.z > 1.0;
                    }
                    else
                    {
                        _20079 = _20072;
                    }
                    float _31682 = 0.0;
                    float _31685 = 0.0;
                    if (!_20079)
                    {
                        highp vec2 _23672 = vec2(_20035);
                        highp vec2 _23677 = vec2(_20035 + max(_19682, 9.9999997473787516355514526367188e-05));
                        highp vec2 _23685 = vec2(0.5) - _20026;
                        highp vec2 _23687 = smoothstep(_23672, _23677, _20028) * smoothstep(_23672, _23677, _23685);
                        float _31625 = 0.0;
                        if (_19682 > 0.0)
                        {
                            _31625 = _23687.x * _23687.y;
                        }
                        else
                        {
                            _31625 = 1.0;
                        }
                        float _20088 = min(_31625, 1.0 - _31622);
                        float _31683 = 0.0;
                        float _31686 = 0.0;
                        if (_20088 > 0.0)
                        {
                            highp float _23799 = _20023.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                            highp float _23805 = 1.0 / (float(_19676) + frag_info.spot_shadow_params.x);
                            highp float _23807 = frag_info.directional_light_direction.w;
                            float mp_copy_23807 = _23807;
                            float _23813 = step(0.5, mp_copy_23807) * (1.0 - step(1.5, mp_copy_23807));
                            highp float _23824 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _23813);
                            float mp_copy_23824 = _23824;
                            float _23826 = cos(mp_copy_23824);
                            float _23828 = sin(mp_copy_23824);
                            highp float _31643 = 0.0;
                            if ((_23807 > 1.5) && (_23807 < 2.5))
                            {
                                highp float _23847 = tan(frag_info.camera_right.w) * 7.0;
                                highp float _23852 = max(_23847 * _23799, frag_info.shadow_texel_size);
                                float _31633 = 0.0;
                                highp float _31634 = 0.0;
                                _31634 = 0.0;
                                _31633 = 0.0;
                                highp float _23874 = 0.0;
                                float _23877 = 0.0;
                                for (int _31632 = 0; _31632 < 9; _31634 = _23874, _31633 = _23877, _31632++)
                                {
                                    vec2 _33974 = vec2(0.0);
                                    do
                                    {
                                        if (_31632 == 0)
                                        {
                                            _33974 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31632 == 1)
                                        {
                                            _33974 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31632 == 2)
                                        {
                                            _33974 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31632 == 3)
                                        {
                                            _33974 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31632 == 4)
                                        {
                                            _33974 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31632 == 5)
                                        {
                                            _33974 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31632 == 6)
                                        {
                                            _33974 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31632 == 7)
                                        {
                                            _33974 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31632 == 8)
                                        {
                                            _33974 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31632 == 9)
                                        {
                                            _33974 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31632 == 10)
                                        {
                                            _33974 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31632 == 11)
                                        {
                                            _33974 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31632 == 12)
                                        {
                                            _33974 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31632 == 13)
                                        {
                                            _33974 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31632 == 14)
                                        {
                                            _33974 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31632 == 15)
                                        {
                                            _33974 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _33974 = vec2(0.0);
                                        break;
                                    } while(false);
                                    highp vec2 _24119 = clamp(_20028 + (vec2((_33974.x * _23826) - (_33974.y * _23828), (_33974.x * _23828) + (_33974.y * _23826)) * _23852), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp float _24128 = _24119.y;
                                    highp vec2 _24129 = vec2((3.0 + _24119.x) * _23805, _24128);
                                    _24129.y = 1.0 - _24128;
                                    highp vec4 _24136 = texture(shadow_map, _24129);
                                    highp float _24137 = _24136.x;
                                    highp float _23869 = step(_24137, _23799);
                                    float mp_copy_23869 = _23869;
                                    _23874 = _31634 + (_24137 * _23869);
                                    _23877 = _31633 + mp_copy_23869;
                                }
                                highp float _31635 = 0.0;
                                if (_31633 > 0.0)
                                {
                                    _31635 = _31634 / _31633;
                                }
                                else
                                {
                                    _31635 = _23799;
                                }
                                _31643 = clamp(_23847 * max(_23799 - _31635, 0.0), frag_info.shadow_texel_size, _20035);
                            }
                            else
                            {
                                _31643 = _20035;
                            }
                            float _31650 = 0.0;
                            if (_23807 > 2.5)
                            {
                                highp vec2 _24165 = vec2(frag_info.shadow_texel_size);
                                highp vec2 _24169 = vec2(1.0 - frag_info.shadow_texel_size);
                                highp vec2 _24170 = clamp(_20028 + (vec2(-0.707099974155426025390625) * _31643), _24165, _24169);
                                highp vec2 _24181 = (vec2(_24170.x, 1.0 - _24170.y) / _24165) - vec2(0.5);
                                highp vec2 _24183 = floor(_24181);
                                highp vec2 _24186 = _24181 - _24183;
                                highp vec2 _24191 = (_24183 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24201 = vec2((3.0 + _24191.x) * _23805, _24191.y);
                                highp float _24205 = frag_info.shadow_texel_size * _23805;
                                highp vec2 _24208 = vec2(_24205, frag_info.shadow_texel_size);
                                highp vec2 _24217 = vec2(_24205, 0.0);
                                highp vec2 _24225 = vec2(0.0, frag_info.shadow_texel_size);
                                highp float _24254 = _24186.x;
                                highp float _24263 = mix(mix(float(_23799 <= texture(shadow_map, _24201).x), float(_23799 <= texture(shadow_map, _24201 + _24217).x), _24254), mix(float(_23799 <= texture(shadow_map, _24201 + _24225).x), float(_23799 <= texture(shadow_map, _24201 + _24208).x), _24254), _24186.y);
                                float mp_copy_24263 = _24263;
                                highp vec2 _24297 = clamp(_20028 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _31643), _24165, _24169);
                                highp vec2 _24308 = (vec2(_24297.x, 1.0 - _24297.y) / _24165) - vec2(0.5);
                                highp vec2 _24310 = floor(_24308);
                                highp vec2 _24313 = _24308 - _24310;
                                highp vec2 _24318 = (_24310 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24328 = vec2((3.0 + _24318.x) * _23805, _24318.y);
                                highp float _24381 = _24313.x;
                                highp float _24390 = mix(mix(float(_23799 <= texture(shadow_map, _24328).x), float(_23799 <= texture(shadow_map, _24328 + _24217).x), _24381), mix(float(_23799 <= texture(shadow_map, _24328 + _24225).x), float(_23799 <= texture(shadow_map, _24328 + _24208).x), _24381), _24313.y);
                                float mp_copy_24390 = _24390;
                                highp vec2 _24424 = clamp(_20028 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _31643), _24165, _24169);
                                highp vec2 _24435 = (vec2(_24424.x, 1.0 - _24424.y) / _24165) - vec2(0.5);
                                highp vec2 _24437 = floor(_24435);
                                highp vec2 _24440 = _24435 - _24437;
                                highp vec2 _24445 = (_24437 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24455 = vec2((3.0 + _24445.x) * _23805, _24445.y);
                                highp float _24508 = _24440.x;
                                highp float _24517 = mix(mix(float(_23799 <= texture(shadow_map, _24455).x), float(_23799 <= texture(shadow_map, _24455 + _24217).x), _24508), mix(float(_23799 <= texture(shadow_map, _24455 + _24225).x), float(_23799 <= texture(shadow_map, _24455 + _24208).x), _24508), _24440.y);
                                float mp_copy_24517 = _24517;
                                highp vec2 _24551 = clamp(_20028 + (vec2(0.707099974155426025390625) * _31643), _24165, _24169);
                                highp vec2 _24562 = (vec2(_24551.x, 1.0 - _24551.y) / _24165) - vec2(0.5);
                                highp vec2 _24564 = floor(_24562);
                                highp vec2 _24567 = _24562 - _24564;
                                highp vec2 _24572 = (_24564 + vec2(0.5)) * frag_info.shadow_texel_size;
                                highp vec2 _24582 = vec2((3.0 + _24572.x) * _23805, _24572.y);
                                highp float _24635 = _24567.x;
                                highp float _24644 = mix(mix(float(_23799 <= texture(shadow_map, _24582).x), float(_23799 <= texture(shadow_map, _24582 + _24217).x), _24635), mix(float(_23799 <= texture(shadow_map, _24582 + _24225).x), float(_23799 <= texture(shadow_map, _24582 + _24208).x), _24635), _24567.y);
                                float mp_copy_24644 = _24644;
                                _31650 = (((mp_copy_24263 + mp_copy_24390) + mp_copy_24517) + mp_copy_24644) * 0.25;
                            }
                            else
                            {
                                int _23940 = (_23813 > 0.5) ? 17 : 16;
                                float _31646 = 0.0;
                                _31646 = 0.0;
                                float _23968 = 0.0;
                                for (int _31636 = 0; _31636 < 17; _31646 = _23968, _31636++)
                                {
                                    if (_31636 >= _23940)
                                    {
                                        break;
                                    }
                                    vec2 _31637 = vec2(0.0);
                                    do
                                    {
                                        if (_31636 == 0)
                                        {
                                            _31637 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                            break;
                                        }
                                        if (_31636 == 1)
                                        {
                                            _31637 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                            break;
                                        }
                                        if (_31636 == 2)
                                        {
                                            _31637 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                            break;
                                        }
                                        if (_31636 == 3)
                                        {
                                            _31637 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                            break;
                                        }
                                        if (_31636 == 4)
                                        {
                                            _31637 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                            break;
                                        }
                                        if (_31636 == 5)
                                        {
                                            _31637 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                            break;
                                        }
                                        if (_31636 == 6)
                                        {
                                            _31637 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                            break;
                                        }
                                        if (_31636 == 7)
                                        {
                                            _31637 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                            break;
                                        }
                                        if (_31636 == 8)
                                        {
                                            _31637 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                            break;
                                        }
                                        if (_31636 == 9)
                                        {
                                            _31637 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                            break;
                                        }
                                        if (_31636 == 10)
                                        {
                                            _31637 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                            break;
                                        }
                                        if (_31636 == 11)
                                        {
                                            _31637 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                            break;
                                        }
                                        if (_31636 == 12)
                                        {
                                            _31637 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                            break;
                                        }
                                        if (_31636 == 13)
                                        {
                                            _31637 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                            break;
                                        }
                                        if (_31636 == 14)
                                        {
                                            _31637 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                            break;
                                        }
                                        if (_31636 == 15)
                                        {
                                            _31637 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                            break;
                                        }
                                        _31637 = vec2(0.0);
                                        break;
                                    } while(false);
                                    vec2 _31639 = vec2(0.0);
                                    do
                                    {
                                        if (_31636 < 3)
                                        {
                                            _31639 = vec2(float(_31636) - 1.0, -1.0);
                                            break;
                                        }
                                        if (_31636 < 6)
                                        {
                                            _31639 = vec2((float(_31636 - 3) * 0.5) - 0.5, -0.5);
                                            break;
                                        }
                                        if (_31636 < 11)
                                        {
                                            _31639 = vec2((float(_31636 - 6) * 0.5) - 1.0, 0.0);
                                            break;
                                        }
                                        if (_31636 < 14)
                                        {
                                            _31639 = vec2((float(_31636 - 11) * 0.5) - 0.5, 0.5);
                                            break;
                                        }
                                        _31639 = vec2(float(_31636 - 14) - 1.0, 1.0);
                                        break;
                                    } while(false);
                                    vec2 _23957 = mix(_31637, _31639, vec2(_23813));
                                    float _24784 = _23957.x;
                                    float _24788 = _23957.y;
                                    highp vec2 _24814 = clamp(_20028 + (vec2((_24784 * _23826) - (_24788 * _23828), (_24784 * _23828) + (_24788 * _23826)) * _31643), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                    highp vec2 _24824 = vec2((3.0 + _24814.x) * _23805, _24814.y);
                                    _24824.y = 1.0 - _24814.y;
                                    highp float _24836 = float(_23799 <= texture(shadow_map, _24824).x);
                                    float mp_copy_24836 = _24836;
                                    _23968 = _31646 + mp_copy_24836;
                                }
                                _31650 = _31646 / float(_23940);
                            }
                            bool _23981 = 3 == (_19676 - 1);
                            bool _23987 = false;
                            if (_23981)
                            {
                                _23987 = frag_info.shadow_fade > 0.0;
                            }
                            else
                            {
                                _23987 = _23981;
                            }
                            float _31651 = 0.0;
                            if (_23987)
                            {
                                highp vec2 _23994 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                                highp vec2 _24002 = smoothstep(vec2(0.0), _23994, _20028) * smoothstep(vec2(0.0), _23994, _23685);
                                _31651 = mix(1.0, _31650, _24002.x * _24002.y);
                            }
                            else
                            {
                                _31651 = _31650;
                            }
                            _31686 = _31622 + _20088;
                            _31683 = _31662 + (_20088 * _31651);
                        }
                        else
                        {
                            _31686 = _31622;
                            _31683 = _31662;
                        }
                        _31685 = _31686;
                        _31682 = _31683;
                    }
                    else
                    {
                        _31685 = _31622;
                        _31682 = _31662;
                    }
                    _31684 = _31685;
                    _31681 = _31682;
                }
                else
                {
                    _31684 = _31622;
                    _31681 = _31662;
                }
                _31687 = _31681 + (1.0 - _31684);
            }
            else
            {
                _31687 = 1.0;
            }
            bool _14304 = frag_info.ssao_lighting.w > 0.5;
            bool _14310 = false;
            if (_14304)
            {
                _14310 = frag_info.camera_up.w < 0.5;
            }
            else
            {
                _14310 = _14304;
            }
            float _31838 = 0.0;
            if (_14310)
            {
                _31838 = min(_31687, _31704.y);
            }
            else
            {
                _31838 = _31687;
            }
            float _14319 = _14282 * _31838;
            highp vec3 _14332 = ((((_14216 + (_14220 * ((vec3(1.0) - _14192) - _14216))) * _31258) * _31855) + (((_14192 * (_31066 * frag_info.environment_intensity)) * 1.0) * _31996)) * mix(1.0, _14319, frag_info.radiance_blend.y);
            highp vec3 _32253 = vec3(0.0);
            if (frag_info.camera_up.w > 0.5)
            {
                _32253 = _14332 + ((_31704.xyz * _14220) * _7336);
            }
            else
            {
                _32253 = _14332;
            }
            highp vec3 _32259 = vec3(0.0);
            if (_14269)
            {
                highp vec3 _32156 = vec3(0.0);
                highp vec3 _32157 = vec3(0.0);
                do
                {
                    float _24902 = max(dot(_30995, _32080), 0.0);
                    highp float hp_copy_24902 = _24902;
                    if (_24902 <= 0.0)
                    {
                        _32157 = vec3(0.0);
                        _32156 = vec3(0.0);
                        break;
                    }
                    float _24908 = max(_14089, 9.9999997473787516355514526367188e-05);
                    highp float hp_copy_24908 = _24908;
                    vec3 _24911 = _32080 + mp_copy_31048;
                    float _24914 = dot(_24911, _24911);
                    vec3 _32154 = vec3(0.0);
                    vec3 _32155 = vec3(0.0);
                    if (_24914 > 9.9999999392252902907785028219223e-09)
                    {
                        vec3 _24922 = _24911 * inversesqrt(_24914);
                        float _32153 = 0.0;
                        do
                        {
                            float _24979 = dot(_30995, _24922);
                            if (_24979 <= 0.0)
                            {
                                _32153 = 0.0;
                                break;
                            }
                            float _24986 = _31040 * _31040;
                            vec3 _24989 = cross(_30995, _24922);
                            float _24992 = _24979 * _24986;
                            float _25001 = _24986 / (dot(_24989, _24989) + (_24992 * _24992));
                            _32153 = min((_25001 * _25001) * 0.3183098733425140380859375, 65504.0);
                            break;
                        } while(false);
                        vec3 _25039 = _14085 + (_14202 * pow(clamp(1.0 - max(dot(_24922, _31048), 0.0), 0.0, 1.0), 5.0));
                        _32155 = (_25039 * min(_32153 * (0.5 / max(mix((2.0 * hp_copy_24902) * _24908, hp_copy_24902 + hp_copy_24908, hp_copy_31040 * hp_copy_31040), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                        _32154 = _25039;
                    }
                    else
                    {
                        _32155 = vec3(0.0);
                        _32154 = _14085;
                    }
                    _32157 = (_32155 * frag_info.directional_light_color.xyz) * _24902;
                    _32156 = (((((vec3(1.0) - _32154) * _14219) * _13990) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _24902;
                    break;
                } while(false);
                _32259 = (_32156 + _32157) * _14319;
            }
            else
            {
                _32259 = vec3(0.0);
            }
            highp float _25063 = 0.0;
            highp vec2 _32158 = vec2(0.0);
            do
            {
                _25063 = frag_info.punctual_dims.x;
                if (_25063 < 0.5)
                {
                    _32158 = vec2(0.0);
                    break;
                }
                if (frag_info.froxel_grid.z > 0.5)
                {
                    highp vec3 _25075 = v_position - frag_info.camera_position.xyz;
                    highp float _25090 = dot(_25075, frag_info.camera_forward.xyz);
                    highp float _25096 = max(_25090, 9.9999997473787516355514526367188e-05);
                    highp vec2 _25199 = (vec3(dot(_25075, frag_info.camera_right.xyz), dot(_25075, frag_info.camera_up.xyz), _25096).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_25096, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
                    highp float _25214 = float(int(((((clamp(floor((log2(max(_25090 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_25199.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_25199.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
                    _32158 = vec2(texture(punctual_index, vec2((mod(_25214, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_25214 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z)).xy);
                    break;
                }
                _32158 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
                break;
            } while(false);
            mediump int _14375 = int(_32158.x + 0.5);
            mediump int _14379 = int(_32158.y + 0.5);
            highp vec3 _32257 = vec3(0.0);
            _32257 = _32259;
            highp vec3 _35027 = vec3(0.0);
            for (int _32159 = 0; _32159 < _14379; _32257 = _35027, _32159++)
            {
                highp float _25247 = float(_14375 + _32159);
                highp vec4 _25265 = texture(punctual_index, vec2((mod(_25247, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_25247 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z));
                highp float _25278 = (float(int(_25265.x + 0.5)) + 0.5) / _25063;
                highp vec2 _25279 = vec2(0.0625, _25278);
                highp vec4 _25282 = texture(punctual_lights, _25279);
                highp vec4 _25299 = texture(punctual_lights, vec2(0.1875, _25278));
                highp float _14397 = _25282.w;
                highp vec3 _14399 = _25299.xyz;
                if (_14397 > 2.5)
                {
                    highp vec4 _25316 = texture(punctual_lights, vec2(0.3125, _25278));
                    highp vec4 _25333 = texture(punctual_lights, vec2(0.4375, _25278));
                    highp vec3 _14413 = _25316.xyz * (_25316.w * 0.5);
                    highp vec3 _14419 = _25333.xyz * (_25333.w * 0.5);
                    highp vec3 _14421 = _25282.xyz;
                    highp vec3 _14423 = _14421 - _14413;
                    highp vec3 _14425 = _14423 - _14419;
                    highp vec3 _14429 = _14421 + _14413;
                    highp vec3 _14431 = _14429 - _14419;
                    highp vec3 _14443 = _14423 + _14419;
                    highp vec3 _14447 = _14421 - v_position;
                    highp float _14453 = _25299.w;
                    highp float _14457 = (dot(_14447, _14447) * _14453) * _14453;
                    highp float _14462 = clamp(1.0 - (_14457 * _14457), 0.0, 1.0);
                    float mp_copy_14462 = _14462;
                    vec2 _25340 = (clamp(vec2(_31040, sqrt(1.0 - _14089)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
                    float _25342 = _25340.x;
                    float _25347 = _25340.y;
                    vec4 _14486 = texture(brdf_lut, vec2((_25342 + 1.0) * 0.3333333432674407958984375, _25347));
                    vec4 _14490 = texture(brdf_lut, vec2((_25342 + 2.0) * 0.3333333432674407958984375, _25347));
                    vec3 _25390 = normalize(mp_copy_31048 - (_30995 * _14088));
                    mat3 _25412 = transpose(mat3(_25390, -cross(_30995, _25390), _30995));
                    mat3 _25413 = mat3(vec3(_14486.x, 0.0, _14486.y), vec3(0.0, 1.0, 0.0), vec3(_14486.z, 0.0, _14486.w)) * _25412;
                    highp vec3 _25417 = _14425 - v_position;
                    highp vec3 _25419 = normalize(_25413 * _25417);
                    vec3 mp_copy_25419 = _25419;
                    highp vec3 _25423 = _14431 - v_position;
                    highp vec3 _25425 = normalize(_25413 * _25423);
                    vec3 mp_copy_25425 = _25425;
                    highp vec3 _25429 = (_14429 + _14419) - v_position;
                    highp vec3 _25431 = normalize(_25413 * _25429);
                    vec3 mp_copy_25431 = _25431;
                    highp vec3 _25435 = _14443 - v_position;
                    highp vec3 _25437 = normalize(_25413 * _25435);
                    vec3 mp_copy_25437 = _25437;
                    float _25466 = dot(_25419, _25425);
                    float _25468 = abs(_25466);
                    float _25482 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25468)) * _25468)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25468) * _25468));
                    float _33914 = 0.0;
                    if (_25466 > 0.0)
                    {
                        _33914 = _25482;
                    }
                    else
                    {
                        _33914 = (0.5 * inversesqrt(max(1.0 - (_25466 * _25466), 1.0000000116860974230803549289703e-07))) - _25482;
                    }
                    float _25515 = dot(_25425, _25431);
                    float _25517 = abs(_25515);
                    float _25531 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25517)) * _25517)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25517) * _25517));
                    float _33915 = 0.0;
                    if (_25515 > 0.0)
                    {
                        _33915 = _25531;
                    }
                    else
                    {
                        _33915 = (0.5 * inversesqrt(max(1.0 - (_25515 * _25515), 1.0000000116860974230803549289703e-07))) - _25531;
                    }
                    float _25564 = dot(_25431, _25437);
                    float _25566 = abs(_25564);
                    float _25580 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25566)) * _25566)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25566) * _25566));
                    float _33916 = 0.0;
                    if (_25564 > 0.0)
                    {
                        _33916 = _25580;
                    }
                    else
                    {
                        _33916 = (0.5 * inversesqrt(max(1.0 - (_25564 * _25564), 1.0000000116860974230803549289703e-07))) - _25580;
                    }
                    float _25613 = dot(_25437, _25419);
                    float _25615 = abs(_25613);
                    float _25629 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25615)) * _25615)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25615) * _25615));
                    float _33917 = 0.0;
                    if (_25613 > 0.0)
                    {
                        _33917 = _25629;
                    }
                    else
                    {
                        _33917 = (0.5 * inversesqrt(max(1.0 - (_25613 * _25613), 1.0000000116860974230803549289703e-07))) - _25629;
                    }
                    vec3 _25452 = (((cross(mp_copy_25419, mp_copy_25425) * _33914) + (cross(mp_copy_25425, mp_copy_25431) * _33915)) + (cross(mp_copy_25431, mp_copy_25437) * _33916)) + (cross(mp_copy_25437, mp_copy_25419) * _33917);
                    float _25655 = length(_25452);
                    mat3 _25715 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _25412;
                    highp vec3 _25721 = normalize(_25715 * _25417);
                    vec3 mp_copy_25721 = _25721;
                    highp vec3 _25727 = normalize(_25715 * _25423);
                    vec3 mp_copy_25727 = _25727;
                    highp vec3 _25733 = normalize(_25715 * _25429);
                    vec3 mp_copy_25733 = _25733;
                    highp vec3 _25739 = normalize(_25715 * _25435);
                    vec3 mp_copy_25739 = _25739;
                    float _25768 = dot(_25721, _25727);
                    float _25770 = abs(_25768);
                    float _25784 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25770)) * _25770)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25770) * _25770));
                    float _33918 = 0.0;
                    if (_25768 > 0.0)
                    {
                        _33918 = _25784;
                    }
                    else
                    {
                        _33918 = (0.5 * inversesqrt(max(1.0 - (_25768 * _25768), 1.0000000116860974230803549289703e-07))) - _25784;
                    }
                    float _25817 = dot(_25727, _25733);
                    float _25819 = abs(_25817);
                    float _25833 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25819)) * _25819)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25819) * _25819));
                    float _33919 = 0.0;
                    if (_25817 > 0.0)
                    {
                        _33919 = _25833;
                    }
                    else
                    {
                        _33919 = (0.5 * inversesqrt(max(1.0 - (_25817 * _25817), 1.0000000116860974230803549289703e-07))) - _25833;
                    }
                    float _25866 = dot(_25733, _25739);
                    float _25868 = abs(_25866);
                    float _25882 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25868)) * _25868)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25868) * _25868));
                    float _33920 = 0.0;
                    if (_25866 > 0.0)
                    {
                        _33920 = _25882;
                    }
                    else
                    {
                        _33920 = (0.5 * inversesqrt(max(1.0 - (_25866 * _25866), 1.0000000116860974230803549289703e-07))) - _25882;
                    }
                    float _25915 = dot(_25739, _25721);
                    float _25917 = abs(_25915);
                    float _25931 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _25917)) * _25917)) / (3.41759395599365234375 + ((4.1616725921630859375 + _25917) * _25917));
                    float _33921 = 0.0;
                    if (_25915 > 0.0)
                    {
                        _33921 = _25931;
                    }
                    else
                    {
                        _33921 = (0.5 * inversesqrt(max(1.0 - (_25915 * _25915), 1.0000000116860974230803549289703e-07))) - _25931;
                    }
                    vec3 _25754 = (((cross(mp_copy_25721, mp_copy_25727) * _33918) + (cross(mp_copy_25727, mp_copy_25733) * _33919)) + (cross(mp_copy_25733, mp_copy_25739) * _33920)) + (cross(mp_copy_25739, mp_copy_25721) * _33921);
                    float _25957 = length(_25754);
                    _35027 = _32257 + (((_14399 * (mp_copy_14462 * mp_copy_14462)) * step(0.0, dot(cross(_14431 - _14425, _14443 - _14425), v_position - _14425))) * (((((_14085 * _14490.x) + (_14202 * _14490.y)) * max(((_25655 * _25655) + _25452.z) / (_25655 + 1.0), 0.0)) * 1.0) + (_14220 * max(((_25957 * _25957) + _25754.z) / (_25957 + 1.0), 0.0))));
                }
                else
                {
                    highp float hp_copy_33858 = 0.0;
                    vec3 _33831 = vec3(0.0);
                    highp vec3 _33854 = vec3(0.0);
                    float _33858 = 0.0;
                    if (_14397 < 0.5)
                    {
                        _33858 = _31040;
                        _33854 = _14399;
                        _33831 = -normalize(texture(punctual_lights, vec2(0.3125, _25278)).xyz);
                    }
                    else
                    {
                        highp vec3 _14577 = _25282.xyz - v_position;
                        highp float _14580 = dot(_14577, _14577);
                        highp float _14584 = inversesqrt(max(_14580, 9.9999999392252902907785028219223e-09));
                        highp vec3 _14585 = _14577 * _14584;
                        vec3 mp_copy_14585 = _14585;
                        highp float _14587 = _25299.w;
                        highp float _14592 = (_14580 * _14587) * _14587;
                        highp float _14597 = clamp(1.0 - (_14592 * _14592), 0.0, 1.0);
                        float mp_copy_14597 = _14597;
                        highp vec4 _26001 = texture(punctual_lights, vec2(0.4375, _25278));
                        highp float _14601 = _26001.w;
                        float _33862 = 0.0;
                        if (_14601 > 0.0)
                        {
                            highp float _14628 = (_31040 * _31040) + ((_14601 * 0.5) * _14584);
                            float mp_copy_14628 = _14628;
                            _33862 = sqrt(min(mp_copy_14628, 1.0));
                        }
                        else
                        {
                            _33862 = _31040;
                        }
                        highp vec3 _14635 = _14399 * ((mp_copy_14597 * mp_copy_14597) / max(pow(max(_14580, _14601 * _14601), _26001.z * 0.5), 9.9999997473787516355514526367188e-05));
                        highp vec3 _33855 = vec3(0.0);
                        if (_14397 > 1.5)
                        {
                            highp vec4 _26018 = texture(punctual_lights, vec2(0.3125, _25278));
                            highp float _14654 = clamp((dot(normalize(_26018.xyz), -mp_copy_14585) * _26018.w) + _26001.x, 0.0, 1.0);
                            float mp_copy_14654 = _14654;
                            highp vec3 _14659 = _14635 * (mp_copy_14654 * mp_copy_14654);
                            highp float _14661 = _26001.y;
                            bool _14662 = _14661 > (-0.5);
                            bool _14668 = false;
                            if (_14662)
                            {
                                _14668 = frag_info.spot_shadow_params.x > 0.5;
                            }
                            else
                            {
                                _14668 = _14662;
                            }
                            highp vec3 _33856 = vec3(0.0);
                            if (_14668)
                            {
                                float _33822 = 0.0;
                                do
                                {
                                    highp vec4 _26241 = texture(punctual_lights, vec2(0.5625, _25278));
                                    highp vec4 _26258 = texture(punctual_lights, vec2(0.6875, _25278));
                                    highp vec4 _26275 = texture(punctual_lights, vec2(0.8125, _25278));
                                    highp vec4 _26292 = texture(punctual_lights, vec2(0.9375, _25278));
                                    highp vec4 _26103 = mat4(_26241, _26258, _26275, _26292) * vec4(v_position + (_7174 * frag_info.spot_shadow_params.z), 1.0);
                                    highp float _26105 = _26103.w;
                                    if (_26105 <= 0.0)
                                    {
                                        _33822 = 1.0;
                                        break;
                                    }
                                    highp vec3 _26114 = _26103.xyz / vec3(_26105);
                                    highp vec2 _26119 = (_26114.xy * 0.5) + vec2(0.5);
                                    highp float _26121 = _26119.x;
                                    bool _26122 = _26121 < 0.0;
                                    bool _26129 = false;
                                    if (!_26122)
                                    {
                                        _26129 = _26121 > 1.0;
                                    }
                                    else
                                    {
                                        _26129 = _26122;
                                    }
                                    bool _26136 = false;
                                    if (!_26129)
                                    {
                                        _26136 = _26119.y < 0.0;
                                    }
                                    else
                                    {
                                        _26136 = _26129;
                                    }
                                    bool _26143 = false;
                                    if (!_26136)
                                    {
                                        _26143 = _26119.y > 1.0;
                                    }
                                    else
                                    {
                                        _26143 = _26136;
                                    }
                                    bool _26150 = false;
                                    if (!_26143)
                                    {
                                        _26150 = _26114.z < 0.0;
                                    }
                                    else
                                    {
                                        _26150 = _26143;
                                    }
                                    bool _26157 = false;
                                    if (!_26150)
                                    {
                                        _26157 = _26114.z > 1.0;
                                    }
                                    else
                                    {
                                        _26157 = _26150;
                                    }
                                    if (_26157)
                                    {
                                        _33822 = 1.0;
                                        break;
                                    }
                                    highp float _26164 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                    highp float _26169 = frag_info.shadow_cascade_count + float(int(_14661 + 0.5));
                                    highp float _26174 = _26114.z - frag_info.spot_shadow_params.y;
                                    highp float _26177 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                                    highp float _26190 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                    float _33821 = 0.0;
                                    _33821 = float(_26174 <= texture(shadow_map, vec2((_26169 + clamp(_26121, 0.0, 1.0)) / _26164, 1.0 - clamp(_26119.y, 0.0, 1.0))).x);
                                    for (int _33820 = 0; _33820 < 8; )
                                    {
                                        highp float _26200 = _26190 + (float(_33820) * 0.785398185253143310546875);
                                        float mp_copy_26200 = _26200;
                                        highp vec2 _26210 = _26119 + (vec2(cos(mp_copy_26200), sin(mp_copy_26200)) * _26177);
                                        highp float _26336 = float(_26174 <= texture(shadow_map, vec2((_26169 + clamp(_26210.x, 0.0, 1.0)) / _26164, 1.0 - clamp(_26210.y, 0.0, 1.0))).x);
                                        float mp_copy_26336 = _26336;
                                        _33821 += mp_copy_26336;
                                        _33820++;
                                        continue;
                                    }
                                    _33822 = _33821 * 0.111111111938953399658203125;
                                    break;
                                } while(false);
                                _33856 = _14659 * _33822;
                            }
                            else
                            {
                                _33856 = _14659;
                            }
                            _33855 = _33856;
                        }
                        else
                        {
                            bool _14684 = _14397 > 0.5;
                            bool _14690 = false;
                            if (_14684)
                            {
                                _14690 = _26001.y > (-0.5);
                            }
                            else
                            {
                                _14690 = _14684;
                            }
                            bool _14696 = false;
                            if (_14690)
                            {
                                _14696 = frag_info.spot_shadow_params.x > 0.5;
                            }
                            else
                            {
                                _14696 = _14690;
                            }
                            highp vec3 _33857 = vec3(0.0);
                            if (_14696)
                            {
                                float _33807 = 0.0;
                                do
                                {
                                    highp vec4 _26649 = texture(punctual_lights, vec2(0.5625, _25278));
                                    highp vec4 _26666 = texture(punctual_lights, vec2(0.6875, _25278));
                                    highp vec4 _26683 = texture(punctual_lights, _25279);
                                    highp vec3 _26408 = (v_position + (_7174 * _26649.z)) - _26683.xyz;
                                    highp vec3 _26410 = abs(_26408);
                                    highp float _26412 = _26410.x;
                                    highp float _26414 = _26410.y;
                                    bool _26415 = _26412 >= _26414;
                                    bool _26423 = false;
                                    if (_26415)
                                    {
                                        _26423 = _26412 >= _26410.z;
                                    }
                                    else
                                    {
                                        _26423 = _26415;
                                    }
                                    highp vec3 _33797 = vec3(0.0);
                                    float _33799 = 0.0;
                                    if (_26423)
                                    {
                                        highp float _26426 = _26408.x;
                                        bool _26427 = _26426 >= 0.0;
                                        highp vec3 _33796 = vec3(0.0);
                                        if (_26427)
                                        {
                                            _33796 = vec3(-_26408.z, _26408.y, _26426);
                                        }
                                        else
                                        {
                                            _33796 = vec3(_26408.zy, -_26426);
                                        }
                                        _33799 = _26427 ? 0.0 : 1.0;
                                        _33797 = _33796;
                                    }
                                    else
                                    {
                                        highp vec3 _33798 = vec3(0.0);
                                        float _33801 = 0.0;
                                        if (_26414 >= _26410.z)
                                        {
                                            highp float _26460 = _26408.y;
                                            bool _26461 = _26460 >= 0.0;
                                            highp vec3 _33795 = vec3(0.0);
                                            if (_26461)
                                            {
                                                _33795 = vec3(-_26408.x, _26408.z, _26460);
                                            }
                                            else
                                            {
                                                _33795 = vec3(_26408.xz, -_26460);
                                            }
                                            _33801 = _26461 ? 2.0 : 3.0;
                                            _33798 = _33795;
                                        }
                                        else
                                        {
                                            highp float _26488 = _26408.z;
                                            bool _26489 = _26488 >= 0.0;
                                            highp vec3 _33794 = vec3(0.0);
                                            if (_26489)
                                            {
                                                _33794 = _26408;
                                            }
                                            else
                                            {
                                                _33794 = vec3(-_26408.x, _26408.y, -_26488);
                                            }
                                            _33801 = _26489 ? 4.0 : 5.0;
                                            _33798 = _33794;
                                        }
                                        _33799 = _33801;
                                        _33797 = _33798;
                                    }
                                    if (_33797.z <= 0.0)
                                    {
                                        _33807 = 1.0;
                                        break;
                                    }
                                    highp vec2 _26529 = ((_33797.xy / vec2(_33797.z)) * 0.5) + vec2(0.5);
                                    highp float _26540 = (_26649.x - (_26649.y / _33797.z)) - _26666.x;
                                    if ((_26540 < 0.0) || (_26540 > 1.0))
                                    {
                                        _33807 = 1.0;
                                        break;
                                    }
                                    highp float hp_copy_33804 = 0.0;
                                    highp float _26552 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                    bool _26558 = _33799 >= 4.0;
                                    highp float _26560 = (frag_info.shadow_cascade_count + _26001.y) + float(_26558);
                                    float _33804 = 0.0;
                                    if (_26558)
                                    {
                                        _33804 = _33799 - 4.0;
                                    }
                                    else
                                    {
                                        _33804 = _33799;
                                    }
                                    hp_copy_33804 = _33804;
                                    highp float _26577 = _26666.y * 0.5;
                                    highp float _26580 = _26649.w * 0.0040000001899898052215576171875;
                                    highp vec2 _26691 = vec2(_26577);
                                    highp vec2 _26694 = vec2(1.0 - _26577);
                                    highp vec2 _26700 = vec2(mod(hp_copy_33804, 2.0), 1.0 - floor(hp_copy_33804 * 0.5)) * 0.5;
                                    highp vec2 _26703 = _26700 + (clamp(_26529, _26691, _26694) * 0.5);
                                    highp float _26596 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                    float _33806 = 0.0;
                                    _33806 = float(_26540 <= texture(shadow_map, vec2((_26560 + _26703.x) / _26552, 1.0 - _26703.y)).x);
                                    for (int _33805 = 0; _33805 < 8; )
                                    {
                                        highp float _26606 = _26596 + (float(_33805) * 0.785398185253143310546875);
                                        float mp_copy_26606 = _26606;
                                        highp vec2 _26740 = _26700 + (clamp(_26529 + (vec2(cos(mp_copy_26606), sin(mp_copy_26606)) * _26580), _26691, _26694) * 0.5);
                                        highp float _26757 = float(_26540 <= texture(shadow_map, vec2((_26560 + _26740.x) / _26552, 1.0 - _26740.y)).x);
                                        float mp_copy_26757 = _26757;
                                        _33806 += mp_copy_26757;
                                        _33805++;
                                        continue;
                                    }
                                    _33807 = _33806 * 0.111111111938953399658203125;
                                    break;
                                } while(false);
                                _33857 = _14635 * _33807;
                            }
                            else
                            {
                                _33857 = _14635;
                            }
                            _33855 = _33857;
                        }
                        _33858 = _33862;
                        _33854 = _33855;
                        _33831 = _14585;
                    }
                    hp_copy_33858 = _33858;
                    highp vec3 _33885 = vec3(0.0);
                    highp vec3 _33886 = vec3(0.0);
                    do
                    {
                        float _26823 = max(dot(_30995, _33831), 0.0);
                        highp float hp_copy_26823 = _26823;
                        if (_26823 <= 0.0)
                        {
                            _33886 = vec3(0.0);
                            _33885 = vec3(0.0);
                            break;
                        }
                        float _26829 = max(_14089, 9.9999997473787516355514526367188e-05);
                        highp float hp_copy_26829 = _26829;
                        vec3 _26832 = _33831 + mp_copy_31048;
                        float _26835 = dot(_26832, _26832);
                        vec3 _33883 = vec3(0.0);
                        vec3 _33884 = vec3(0.0);
                        if (_26835 > 9.9999999392252902907785028219223e-09)
                        {
                            vec3 _26843 = _26832 * inversesqrt(_26835);
                            float _33882 = 0.0;
                            do
                            {
                                float _26900 = dot(_30995, _26843);
                                if (_26900 <= 0.0)
                                {
                                    _33882 = 0.0;
                                    break;
                                }
                                float _26907 = _33858 * _33858;
                                vec3 _26910 = cross(_30995, _26843);
                                float _26913 = _26900 * _26907;
                                float _26922 = _26907 / (dot(_26910, _26910) + (_26913 * _26913));
                                _33882 = min((_26922 * _26922) * 0.3183098733425140380859375, 65504.0);
                                break;
                            } while(false);
                            vec3 _26960 = _14085 + (_14202 * pow(clamp(1.0 - max(dot(_26843, _31048), 0.0), 0.0, 1.0), 5.0));
                            _33884 = (_26960 * min(_33882 * (0.5 / max(mix((2.0 * hp_copy_26823) * _26829, hp_copy_26823 + hp_copy_26829, hp_copy_33858 * hp_copy_33858), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                            _33883 = _26960;
                        }
                        else
                        {
                            _33884 = vec3(0.0);
                            _33883 = _14085;
                        }
                        _33886 = (_33884 * _33854) * _26823;
                        _33885 = (((((vec3(1.0) - _33883) * _14219) * _13990) * 0.3183098733425140380859375) * _33854) * _26823;
                        break;
                    } while(false);
                    _35027 = _32257 + (_33885 + _33886);
                }
            }
            bool _14753 = _FogInfo.params0.y > 0.5;
            bool _14759 = false;
            if (_14753)
            {
                _14759 = _FogInfo.params0.w > 0.0;
            }
            else
            {
                _14759 = _14753;
            }
            highp vec3 _32264 = vec3(0.0);
            if (_14759)
            {
                vec3 mp_copy_32260 = vec3(0.0);
                highp vec3 _32260 = vec3(0.0);
                if (_14926)
                {
                    _32260 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _32260 = normalize(v_viewvector);
                }
                mp_copy_32260 = _32260;
                vec3 _14764 = _14110 * (-mp_copy_32260);
                vec3 _32261 = vec3(0.0);
                do
                {
                    if (_15240)
                    {
                        vec2 _27082 = vec2(atan(_14764.z, _14764.x), asin(clamp(_14764.y, -1.0, 1.0)));
                        highp vec2 hp_copy_27082 = _27082;
                        _32261 = textureLod(prefiltered_radiance, (hp_copy_27082 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                        break;
                    }
                    vec2 _27101 = vec2(atan(_14764.z, _14764.x), asin(clamp(_14764.y, -1.0, 1.0)));
                    highp vec2 hp_copy_27101 = _27101;
                    highp vec2 _27106 = (hp_copy_27101 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _27013 = clamp(_27106.y, 0.00390625, 0.99609375);
                    float _27019 = floor(0.0);
                    highp float _27038 = _27106.x;
                    _32261 = mix(texture(prefiltered_radiance, vec2(_27038, (_27019 + _27013) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_27038, (min(_27019 + 1.0, 7.0) + _27013) * 0.125)).xyz, vec3(-_27019));
                    break;
                } while(false);
                highp vec3 _32263 = vec3(0.0);
                if (_14133)
                {
                    vec3 _32262 = vec3(0.0);
                    do
                    {
                        if (_15240)
                        {
                            vec2 _27211 = vec2(atan(_14764.z, _14764.x), asin(clamp(_14764.y, -1.0, 1.0)));
                            highp vec2 hp_copy_27211 = _27211;
                            _32262 = textureLod(prefiltered_radiance_b, (hp_copy_27211 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                            break;
                        }
                        vec2 _27230 = vec2(atan(_14764.z, _14764.x), asin(clamp(_14764.y, -1.0, 1.0)));
                        highp vec2 hp_copy_27230 = _27230;
                        highp vec2 _27235 = (hp_copy_27230 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                        highp float _27142 = clamp(_27235.y, 0.00390625, 0.99609375);
                        float _27148 = floor(0.0);
                        highp float _27167 = _27235.x;
                        _32262 = mix(texture(prefiltered_radiance_b, vec2(_27167, (_27148 + _27142) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_27167, (min(_27148 + 1.0, 7.0) + _27142) * 0.125)).xyz, vec3(-_27148));
                        break;
                    } while(false);
                    _32263 = mix(_32261, _32262, vec3(frag_info.radiance_blend.x));
                }
                else
                {
                    _32263 = _32261;
                }
                _32264 = _32263 * frag_info.environment_intensity;
            }
            else
            {
                _32264 = _FogInfo.color.xyz;
            }
            highp vec4 _14788 = vec4(min((_32253 + (_32257 * mix(1.0, _31328, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7360, vec3(65504.0)), 1.0) * _35429;
            highp vec4 _32279 = vec4(0.0);
            do
            {
                if (_FogInfo.params0.y < 0.5)
                {
                    _32279 = _14788;
                    break;
                }
                int _27279 = int(_FogInfo.params0.x + 0.5);
                if (_27279 == 0)
                {
                    _32279 = _14788;
                    break;
                }
                highp float _32266 = 0.0;
                if (_14926)
                {
                    _32266 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
                }
                else
                {
                    _32266 = length(v_viewvector);
                }
                if ((_FogInfo.params1.w > 0.0) && (_32266 > _FogInfo.params1.w))
                {
                    _32279 = _14788;
                    break;
                }
                float _32270 = 0.0;
                if (_27279 == 1)
                {
                    _32270 = clamp((_32266 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
                }
                else
                {
                    float _32271 = 0.0;
                    if (_27279 == 2)
                    {
                        highp float _32269 = 0.0;
                        if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                        {
                            highp vec3 _32267 = vec3(0.0);
                            if (_14926)
                            {
                                _32267 = v_position - (view_info.camera_forward.xyz * _32266);
                            }
                            else
                            {
                                _32267 = v_position + v_viewvector;
                            }
                            highp float _27360 = -_FogInfo.params2.y;
                            highp float _27367 = _FogInfo.params1.x * exp(_27360 * (_32267.y - _FogInfo.params2.x));
                            highp float _27384 = _FogInfo.params2.y * (v_position.y - _32267.y);
                            highp float _32268 = 0.0;
                            if (abs(_27384) > 0.00124999997206032276153564453125)
                            {
                                _32268 = (_27367 - (_FogInfo.params1.x * exp(_27360 * (v_position.y - _FogInfo.params2.x)))) / _27384;
                            }
                            else
                            {
                                _32268 = _27367;
                            }
                            _32269 = _32268 * max(_32266 - _FogInfo.params1.y, 0.0);
                        }
                        else
                        {
                            _32269 = _FogInfo.params1.x * max(_32266 - _FogInfo.params1.y, 0.0);
                        }
                        _32271 = 1.0 - exp(-_32269);
                    }
                    else
                    {
                        highp float _27422 = _FogInfo.params1.x * max(_32266 - _FogInfo.params1.y, 0.0);
                        _32271 = 1.0 - exp((-_27422) * _27422);
                    }
                    _32270 = _32271;
                }
                highp float _27434 = min(_32270, _FogInfo.params0.z);
                if (_27434 <= 0.0)
                {
                    _32279 = _14788;
                    break;
                }
                highp vec3 _27447 = mix(_FogInfo.color.xyz, _32264, vec3(_FogInfo.params0.w));
                bool _27450 = _FogInfo.sun.w > 0.5;
                bool _27456 = false;
                if (_27450)
                {
                    _27456 = _FogInfo.params2.z > 0.0;
                }
                else
                {
                    _27456 = _27450;
                }
                vec3 _32275 = vec3(0.0);
                if (_27456)
                {
                    vec3 mp_copy_32272 = vec3(0.0);
                    highp vec3 _32272 = vec3(0.0);
                    if (_14926)
                    {
                        _32272 = -view_info.camera_forward.xyz;
                    }
                    else
                    {
                        _32272 = normalize(v_viewvector);
                    }
                    mp_copy_32272 = _32272;
                    highp float _27472 = pow(max(dot(-mp_copy_32272, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                    float mp_copy_27472 = _27472;
                    _32275 = _27447 + ((_FogInfo.sun.xyz * mp_copy_27472) * _FogInfo.params2.z);
                }
                else
                {
                    _32275 = _27447;
                }
                highp float _27485 = _14788.w;
                float mp_copy_27485 = _27485;
                _32279 = vec4(mix(_14788.xyz, _32275 * mp_copy_27485, vec3(_27434)), _27485);
                break;
            } while(false);
            vec4 _33792 = vec4(0.0);
            if (_31031 > 1.5)
            {
                vec4 _33791 = vec4(0.0);
                do
                {
                    if (debug_view_info.view.x < 20.0)
                    {
                        vec3 _33777 = vec3(0.0);
                        if (debug_view_info.view.x == 1.0)
                        {
                            float _27938 = length(_7174);
                            vec3 _33775 = vec3(0.0);
                            if (_27938 > 9.9999999747524270787835121154785e-07)
                            {
                                _33775 = _7174 / vec3(_27938);
                            }
                            else
                            {
                                _33775 = vec3(0.0);
                            }
                            _33777 = ((_33775 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                        }
                        else
                        {
                            vec3 _33778 = vec3(0.0);
                            if (debug_view_info.view.x == 2.0)
                            {
                                float _27961 = length(_30995);
                                vec3 _33773 = vec3(0.0);
                                if (_27961 > 9.9999999747524270787835121154785e-07)
                                {
                                    _33773 = _30995 / vec3(_27961);
                                }
                                else
                                {
                                    _33773 = vec3(0.0);
                                }
                                _33778 = ((_33773 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                            }
                            else
                            {
                                vec3 _33779 = vec3(0.0);
                                if (debug_view_info.view.x == 3.0)
                                {
                                    float _27984 = length(v_tangent.xyz);
                                    vec3 _33771 = vec3(0.0);
                                    if (_27984 > 9.9999999747524270787835121154785e-07)
                                    {
                                        _33771 = v_tangent.xyz / vec3(_27984);
                                    }
                                    else
                                    {
                                        _33771 = vec3(0.0);
                                    }
                                    _33779 = ((_33771 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _33780 = vec3(0.0);
                                    if (debug_view_info.view.x == 4.0)
                                    {
                                        highp float _27617 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                        float mp_copy_27617 = _27617;
                                        vec3 _27618 = cross(_7172, v_tangent.xyz) * mp_copy_27617;
                                        float _28007 = length(_27618);
                                        vec3 _33769 = vec3(0.0);
                                        if (_28007 > 9.9999999747524270787835121154785e-07)
                                        {
                                            _33769 = _27618 / vec3(_28007);
                                        }
                                        else
                                        {
                                            _33769 = vec3(0.0);
                                        }
                                        _33780 = ((_33769 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec3 _33781 = vec3(0.0);
                                        if (debug_view_info.view.x == 5.0)
                                        {
                                            _33781 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                        }
                                        else
                                        {
                                            vec3 _33782 = vec3(0.0);
                                            if (debug_view_info.view.x == 6.0)
                                            {
                                                _33782 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                            }
                                            else
                                            {
                                                vec3 _33783 = vec3(0.0);
                                                if (debug_view_info.view.x == 7.0)
                                                {
                                                    _33783 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * debug_view_info.view.z;
                                                }
                                                else
                                                {
                                                    vec3 _33784 = vec3(0.0);
                                                    if (debug_view_info.view.x == 8.0)
                                                    {
                                                        vec3 _28042 = max(v_color.xyz * debug_view_info.view.z, vec3(0.0));
                                                        _33784 = mix(_28042 * 12.9200000762939453125, (pow(max(_28042, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _28042));
                                                    }
                                                    else
                                                    {
                                                        vec3 _33785 = vec3(0.0);
                                                        if (debug_view_info.view.x == 9.0)
                                                        {
                                                            vec3 mp_copy_33765 = vec3(0.0);
                                                            highp vec3 _33765 = vec3(0.0);
                                                            if (_14926)
                                                            {
                                                                _33765 = -view_info.camera_forward.xyz;
                                                            }
                                                            else
                                                            {
                                                                _33765 = normalize(v_viewvector);
                                                            }
                                                            mp_copy_33765 = _33765;
                                                            float _28078 = length(mp_copy_33765);
                                                            vec3 _33766 = vec3(0.0);
                                                            if (_28078 > 9.9999999747524270787835121154785e-07)
                                                            {
                                                                _33766 = mp_copy_33765 / vec3(_28078);
                                                            }
                                                            else
                                                            {
                                                                _33766 = vec3(0.0);
                                                            }
                                                            _33785 = ((_33766 * 0.5) + vec3(0.5)) * debug_view_info.view.z;
                                                        }
                                                        else
                                                        {
                                                            vec3 _33786 = vec3(0.0);
                                                            if (debug_view_info.view.x == 10.0)
                                                            {
                                                                float _28121 = max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                float _28122 = (v_position.x - debug_view_info.params.x) / _28121;
                                                                bool _28126 = debug_view_info.view.w > 1.5;
                                                                float _33749 = 0.0;
                                                                if (_28126)
                                                                {
                                                                    _33749 = fract(_28122);
                                                                }
                                                                else
                                                                {
                                                                    float _33750 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33750 = ((_28122 < 0.0) || (_28122 > 1.0)) ? 0.0 : _28122;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33750 = clamp(_28122, 0.0, 1.0);
                                                                    }
                                                                    _33749 = _33750;
                                                                }
                                                                float _28173 = (v_position.y - debug_view_info.params.x) / _28121;
                                                                float _33755 = 0.0;
                                                                if (_28126)
                                                                {
                                                                    _33755 = fract(_28173);
                                                                }
                                                                else
                                                                {
                                                                    float _33756 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33756 = ((_28173 < 0.0) || (_28173 > 1.0)) ? 0.0 : _28173;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33756 = clamp(_28173, 0.0, 1.0);
                                                                    }
                                                                    _33755 = _33756;
                                                                }
                                                                float _28224 = (v_position.z - debug_view_info.params.x) / _28121;
                                                                float _33761 = 0.0;
                                                                if (_28126)
                                                                {
                                                                    _33761 = fract(_28224);
                                                                }
                                                                else
                                                                {
                                                                    float _33762 = 0.0;
                                                                    if (debug_view_info.view.w > 0.5)
                                                                    {
                                                                        _33762 = ((_28224 < 0.0) || (_28224 > 1.0)) ? 0.0 : _28224;
                                                                    }
                                                                    else
                                                                    {
                                                                        _33762 = clamp(_28224, 0.0, 1.0);
                                                                    }
                                                                    _33761 = _33762;
                                                                }
                                                                _33786 = vec3(_33749 * debug_view_info.view.z, _33755 * debug_view_info.view.z, _33761 * debug_view_info.view.z);
                                                            }
                                                            else
                                                            {
                                                                vec3 _33787 = vec3(0.0);
                                                                if (debug_view_info.view.x == 11.0)
                                                                {
                                                                    bvec3 _27693 = bvec3(gl_FrontFacing);
                                                                    _33787 = vec3(_27693.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _27693.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _27693.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                                }
                                                                else
                                                                {
                                                                    vec3 _33788 = vec3(0.0);
                                                                    if (debug_view_info.view.x == 12.0)
                                                                    {
                                                                        highp vec2 _28251 = v_texture_coords;
                                                                        vec2 mp_copy_28251 = _28251;
                                                                        vec2 _28263 = floor(mp_copy_28251 * 8.0);
                                                                        float _28265 = _28263.x;
                                                                        float _28267 = _28263.y;
                                                                        float _28275 = _28265 + (_28267 * 8.0);
                                                                        vec2 _28284 = step(vec2(0.0), mp_copy_28251) * step(mp_copy_28251, vec2(1.0));
                                                                        _33788 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_28265 + _28267, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_28275 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_28275 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_28284.x * _28284.y));
                                                                    }
                                                                    else
                                                                    {
                                                                        vec3 _33789 = vec3(0.0);
                                                                        if (debug_view_info.view.x == 13.0)
                                                                        {
                                                                            highp vec2 _28334 = v_texture_coords_1;
                                                                            vec2 mp_copy_28334 = _28334;
                                                                            vec2 _28346 = floor(mp_copy_28334 * 8.0);
                                                                            float _28348 = _28346.x;
                                                                            float _28350 = _28346.y;
                                                                            float _28358 = _28348 + (_28350 * 8.0);
                                                                            vec2 _28367 = step(vec2(0.0), mp_copy_28334) * step(mp_copy_28334, vec2(1.0));
                                                                            _33789 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_28348 + _28350, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_28358 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_28358 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_28367.x * _28367.y));
                                                                        }
                                                                        else
                                                                        {
                                                                            vec3 _33790 = vec3(0.0);
                                                                            if (debug_view_info.view.x == 14.0)
                                                                            {
                                                                                highp float _28433 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                                bool _28439 = debug_view_info.depth.x > 0.5;
                                                                                bool _28445 = false;
                                                                                if (_28439)
                                                                                {
                                                                                    _28445 = debug_view_info.depth.y > 0.5;
                                                                                }
                                                                                else
                                                                                {
                                                                                    _28445 = _28439;
                                                                                }
                                                                                highp float _33735 = 0.0;
                                                                                if (_28445)
                                                                                {
                                                                                    _33735 = 1.1920928955078125e-07 / _28433;
                                                                                }
                                                                                else
                                                                                {
                                                                                    highp float _33736 = 0.0;
                                                                                    if (_28439)
                                                                                    {
                                                                                        _33736 = 5.9604644775390625e-08 / (_28433 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        _33736 = 5.9604644775390625e-08 / (_28433 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                                    }
                                                                                    _33735 = _33736;
                                                                                }
                                                                                highp float _28474 = dot(_7174, view_info.camera_forward.xyz);
                                                                                highp float _28480 = sqrt(max(1.0 - (_28474 * _28474), 0.0));
                                                                                highp float _33733 = 0.0;
                                                                                if (_14926)
                                                                                {
                                                                                    _33733 = (debug_view_info.depth.z * _28480) / max(abs(_28474), 9.9999999747524270787835121154785e-07);
                                                                                }
                                                                                else
                                                                                {
                                                                                    _33733 = (((1.0 / (_28433 * _28433)) * debug_view_info.depth.z) * _28480) / max(abs(dot(_7174, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                                }
                                                                                highp float _28518 = log2(max(max(8.0 * _33735, _33733 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                                float mp_copy_28518 = _28518;
                                                                                float _28557 = (mp_copy_28518 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                                                float _33745 = 0.0;
                                                                                if (debug_view_info.view.w > 1.5)
                                                                                {
                                                                                    _33745 = fract(_28557);
                                                                                }
                                                                                else
                                                                                {
                                                                                    float _33746 = 0.0;
                                                                                    if (debug_view_info.view.w > 0.5)
                                                                                    {
                                                                                        _33746 = ((_28557 < 0.0) || (_28557 > 1.0)) ? 0.0 : _28557;
                                                                                    }
                                                                                    else
                                                                                    {
                                                                                        _33746 = clamp(_28557, 0.0, 1.0);
                                                                                    }
                                                                                    _33745 = _33746;
                                                                                }
                                                                                _33790 = clamp(vec3(1.5) - abs(vec3(4.0 * _33745) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * debug_view_info.view.z;
                                                                            }
                                                                            else
                                                                            {
                                                                                vec2 _28590 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                                _33790 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28590.x + _28590.y, 2.0)));
                                                                            }
                                                                            _33789 = _33790;
                                                                        }
                                                                        _33788 = _33789;
                                                                    }
                                                                    _33787 = _33788;
                                                                }
                                                                _33786 = _33787;
                                                            }
                                                            _33785 = _33786;
                                                        }
                                                        _33784 = _33785;
                                                    }
                                                    _33783 = _33784;
                                                }
                                                _33782 = _33783;
                                            }
                                            _33781 = _33782;
                                        }
                                        _33780 = _33781;
                                    }
                                    _33779 = _33780;
                                }
                                _33778 = _33779;
                            }
                            _33777 = _33778;
                        }
                        _33791 = vec4(_33777, 1.0);
                        break;
                    }
                    vec3 _33712 = vec3(0.0);
                    if (debug_view_info.view.x < 40.0)
                    {
                        vec3 _33713 = vec3(0.0);
                        if (debug_view_info.view.x == 20.0)
                        {
                            vec3 _28611 = max(_13990 * debug_view_info.view.z, vec3(0.0));
                            _33713 = mix(_28611 * 12.9200000762939453125, (pow(max(_28611, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _28611));
                        }
                        else
                        {
                            vec3 _33714 = vec3(0.0);
                            if (debug_view_info.view.x == 21.0)
                            {
                                float _28650 = (_35429 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                float _33708 = 0.0;
                                if (debug_view_info.view.w > 1.5)
                                {
                                    _33708 = fract(_28650);
                                }
                                else
                                {
                                    float _33709 = 0.0;
                                    if (debug_view_info.view.w > 0.5)
                                    {
                                        _33709 = ((_28650 < 0.0) || (_28650 > 1.0)) ? 0.0 : _28650;
                                    }
                                    else
                                    {
                                        _33709 = clamp(_28650, 0.0, 1.0);
                                    }
                                    _33708 = _33709;
                                }
                                _33714 = vec3(_33708 * debug_view_info.view.z);
                            }
                            else
                            {
                                vec3 _33715 = vec3(0.0);
                                if (debug_view_info.view.x == 22.0)
                                {
                                    float _28701 = (_7307 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                    float _33704 = 0.0;
                                    if (debug_view_info.view.w > 1.5)
                                    {
                                        _33704 = fract(_28701);
                                    }
                                    else
                                    {
                                        float _33705 = 0.0;
                                        if (debug_view_info.view.w > 0.5)
                                        {
                                            _33705 = ((_28701 < 0.0) || (_28701 > 1.0)) ? 0.0 : _28701;
                                        }
                                        else
                                        {
                                            _33705 = clamp(_28701, 0.0, 1.0);
                                        }
                                        _33704 = _33705;
                                    }
                                    _33715 = vec3(_33704 * debug_view_info.view.z);
                                }
                                else
                                {
                                    vec3 _33716 = vec3(0.0);
                                    if (debug_view_info.view.x == 23.0)
                                    {
                                        float _28752 = (_7314 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                        float _33700 = 0.0;
                                        if (debug_view_info.view.w > 1.5)
                                        {
                                            _33700 = fract(_28752);
                                        }
                                        else
                                        {
                                            float _33701 = 0.0;
                                            if (debug_view_info.view.w > 0.5)
                                            {
                                                _33701 = ((_28752 < 0.0) || (_28752 > 1.0)) ? 0.0 : _28752;
                                            }
                                            else
                                            {
                                                _33701 = clamp(_28752, 0.0, 1.0);
                                            }
                                            _33700 = _33701;
                                        }
                                        _33716 = vec3(_33700 * debug_view_info.view.z);
                                    }
                                    else
                                    {
                                        vec3 _33717 = vec3(0.0);
                                        if (debug_view_info.view.x == 24.0)
                                        {
                                            float _28803 = (1.0 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                            float _33696 = 0.0;
                                            if (debug_view_info.view.w > 1.5)
                                            {
                                                _33696 = fract(_28803);
                                            }
                                            else
                                            {
                                                float _33697 = 0.0;
                                                if (debug_view_info.view.w > 0.5)
                                                {
                                                    _33697 = ((_28803 < 0.0) || (_28803 > 1.0)) ? 0.0 : _28803;
                                                }
                                                else
                                                {
                                                    _33697 = clamp(_28803, 0.0, 1.0);
                                                }
                                                _33696 = _33697;
                                            }
                                            _33717 = vec3(_33696 * debug_view_info.view.z);
                                        }
                                        else
                                        {
                                            vec3 _33718 = vec3(0.0);
                                            if (debug_view_info.view.x == 25.0)
                                            {
                                                float _28854 = (_7336 - debug_view_info.params.x) / max(debug_view_info.params.y - debug_view_info.params.x, 9.9999999747524270787835121154785e-07);
                                                float _33692 = 0.0;
                                                if (debug_view_info.view.w > 1.5)
                                                {
                                                    _33692 = fract(_28854);
                                                }
                                                else
                                                {
                                                    float _33693 = 0.0;
                                                    if (debug_view_info.view.w > 0.5)
                                                    {
                                                        _33693 = ((_28854 < 0.0) || (_28854 > 1.0)) ? 0.0 : _28854;
                                                    }
                                                    else
                                                    {
                                                        _33693 = clamp(_28854, 0.0, 1.0);
                                                    }
                                                    _33692 = _33693;
                                                }
                                                _33718 = vec3(_33692 * debug_view_info.view.z);
                                            }
                                            else
                                            {
                                                vec3 _33719 = vec3(0.0);
                                                if (debug_view_info.view.x == 26.0)
                                                {
                                                    vec3 _28890 = max(_7360 * debug_view_info.view.z, vec3(0.0));
                                                    _33719 = mix(_28890 * 12.9200000762939453125, (pow(max(_28890, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _28890));
                                                }
                                                else
                                                {
                                                    vec2 _28911 = floor(gl_FragCoord.xy * vec2(0.125));
                                                    _33719 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28911.x + _28911.y, 2.0)));
                                                }
                                                _33718 = _33719;
                                            }
                                            _33717 = _33718;
                                        }
                                        _33716 = _33717;
                                    }
                                    _33715 = _33716;
                                }
                                _33714 = _33715;
                            }
                            _33713 = _33714;
                        }
                        _33712 = _33713;
                    }
                    else
                    {
                        vec3 _33720 = vec3(0.0);
                        if (debug_view_info.view.x < 60.0)
                        {
                            vec2 _28932 = floor(gl_FragCoord.xy * vec2(0.125));
                            _33720 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_28932.x + _28932.y, 2.0)));
                        }
                        else
                        {
                            vec3 _33721 = vec3(0.0);
                            if (debug_view_info.view.x < 70.0)
                            {
                                vec3 _33722 = vec3(0.0);
                                if (debug_view_info.view.x == 60.0)
                                {
                                    _33722 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                }
                                else
                                {
                                    vec3 _33723 = vec3(0.0);
                                    if (debug_view_info.view.x == 61.0)
                                    {
                                        _33723 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * debug_view_info.view.z;
                                    }
                                    else
                                    {
                                        vec2 _29020 = floor(gl_FragCoord.xy * vec2(0.125));
                                        _33723 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_29020.x + _29020.y, 2.0)));
                                    }
                                    _33722 = _33723;
                                }
                                _33721 = _33722;
                            }
                            else
                            {
                                vec3 _33724 = vec3(0.0);
                                if (debug_view_info.view.x < 80.0)
                                {
                                    vec3 _33725 = vec3(0.0);
                                    if (debug_view_info.view.x == 70.0)
                                    {
                                        bool _29037 = v_texture_coords.x < 0.0;
                                        bool _29044 = false;
                                        if (!_29037)
                                        {
                                            _29044 = v_texture_coords.x > 1.0;
                                        }
                                        else
                                        {
                                            _29044 = _29037;
                                        }
                                        bool _29051 = false;
                                        if (!_29044)
                                        {
                                            _29051 = v_texture_coords.y < 0.0;
                                        }
                                        else
                                        {
                                            _29051 = _29044;
                                        }
                                        bool _29058 = false;
                                        if (!_29051)
                                        {
                                            _29058 = v_texture_coords.y > 1.0;
                                        }
                                        else
                                        {
                                            _29058 = _29051;
                                        }
                                        bvec3 _29061 = bvec3(_29058);
                                        highp vec3 _29062 = vec3(_29061.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _29061.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _29061.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        bvec3 _29087 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                        highp vec3 _29088 = vec3(_29087.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _29062.x, _29087.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _29062.y, _29087.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _29062.z);
                                        float _29102 = length(v_normal);
                                        bvec3 _29109 = bvec3((_29102 < 0.300000011920928955078125) || (_29102 > 1.7000000476837158203125));
                                        highp vec3 _29110 = vec3(_29109.x ? vec3(1.0, 0.5, 0.0).x : _29088.x, _29109.y ? vec3(1.0, 0.5, 0.0).y : _29088.y, _29109.z ? vec3(1.0, 0.5, 0.0).z : _29088.z);
                                        bool _29115 = _7307 > 0.0500000007450580596923828125;
                                        bool _29121 = false;
                                        if (_29115)
                                        {
                                            _29121 = _7307 < 0.949999988079071044921875;
                                        }
                                        else
                                        {
                                            _29121 = _29115;
                                        }
                                        bvec3 _29123 = bvec3(_29121);
                                        highp vec3 _29124 = vec3(_29123.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _29110.x, _29123.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _29110.y, _29123.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _29110.z);
                                        vec3 _33690 = vec3(0.0);
                                        do
                                        {
                                            float _29134 = dot(_13990, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7307 > 0.5)
                                            {
                                                _33690 = _29124;
                                                break;
                                            }
                                            if (_29134 < 0.0130000002682209014892578125)
                                            {
                                                _33690 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_29134 > 0.87000000476837158203125)
                                            {
                                                _33690 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _33690 = _29124;
                                            break;
                                        } while(false);
                                        vec3 _33691 = vec3(0.0);
                                        do
                                        {
                                            vec3 _29179 = ((_13990 + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                            bool _29194 = min(min(_7258, _7259), _7260) < 0.0;
                                            bool _29207 = false;
                                            if (!_29194)
                                            {
                                                _29207 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                            }
                                            else
                                            {
                                                _29207 = _29194;
                                            }
                                            if (any(isnan(_29179)))
                                            {
                                                _33691 = vec3(1.0, 0.0, 0.0);
                                                break;
                                            }
                                            if (any(isinf(_29179)))
                                            {
                                                _33691 = vec3(0.0, 1.0, 0.0);
                                                break;
                                            }
                                            if (_29207)
                                            {
                                                _33691 = vec3(0.0, 0.25, 1.0);
                                                break;
                                            }
                                            _33691 = _33690;
                                            break;
                                        } while(false);
                                        _33725 = _33691;
                                    }
                                    else
                                    {
                                        vec3 _33726 = vec3(0.0);
                                        if (debug_view_info.view.x == 71.0)
                                        {
                                            vec3 _33689 = vec3(0.0);
                                            do
                                            {
                                                vec3 _29247 = ((_13990 + _30995) + _7360) + vec3((_7307 + _7314) + _7336);
                                                bool _29262 = min(min(_7258, _7259), _7260) < 0.0;
                                                bool _29275 = false;
                                                if (!_29262)
                                                {
                                                    _29275 = min(min(_7360.x, _7360.y), _7360.z) < 0.0;
                                                }
                                                else
                                                {
                                                    _29275 = _29262;
                                                }
                                                if (any(isnan(_29247)))
                                                {
                                                    _33689 = vec3(1.0, 0.0, 0.0);
                                                    break;
                                                }
                                                if (any(isinf(_29247)))
                                                {
                                                    _33689 = vec3(0.0, 1.0, 0.0);
                                                    break;
                                                }
                                                if (_29275)
                                                {
                                                    _33689 = vec3(0.0, 0.25, 1.0);
                                                    break;
                                                }
                                                _33689 = vec3(0.3499999940395355224609375);
                                                break;
                                            } while(false);
                                            _33726 = _33689;
                                        }
                                        else
                                        {
                                            vec3 _33727 = vec3(0.0);
                                            if (debug_view_info.view.x == 72.0)
                                            {
                                                vec3 _33688 = vec3(0.0);
                                                do
                                                {
                                                    float _29297 = dot(_13990, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                                    if (_7307 > 0.5)
                                                    {
                                                        _33688 = vec3(0.3499999940395355224609375);
                                                        break;
                                                    }
                                                    if (_29297 < 0.0130000002682209014892578125)
                                                    {
                                                        _33688 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                        break;
                                                    }
                                                    if (_29297 > 0.87000000476837158203125)
                                                    {
                                                        _33688 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                        break;
                                                    }
                                                    _33688 = vec3(0.3499999940395355224609375);
                                                    break;
                                                } while(false);
                                                _33727 = _33688;
                                            }
                                            else
                                            {
                                                vec3 _33728 = vec3(0.0);
                                                if (debug_view_info.view.x == 73.0)
                                                {
                                                    bool _29319 = _7307 > 0.0500000007450580596923828125;
                                                    bool _29325 = false;
                                                    if (_29319)
                                                    {
                                                        _29325 = _7307 < 0.949999988079071044921875;
                                                    }
                                                    else
                                                    {
                                                        _29325 = _29319;
                                                    }
                                                    bvec3 _29327 = bvec3(_29325);
                                                    _33728 = vec3(_29327.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _29327.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _29327.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _33729 = vec3(0.0);
                                                    if (debug_view_info.view.x == 74.0)
                                                    {
                                                        float _29333 = length(v_normal);
                                                        bvec3 _29340 = bvec3((_29333 < 0.300000011920928955078125) || (_29333 > 1.7000000476837158203125));
                                                        _33729 = vec3(_29340.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _29340.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _29340.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _33730 = vec3(0.0);
                                                        if (debug_view_info.view.x == 75.0)
                                                        {
                                                            bvec3 _29363 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_30995), normalize(_7174)) < 0.999000012874603271484375));
                                                            _33730 = vec3(_29363.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _29363.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _29363.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _33731 = vec3(0.0);
                                                            if (debug_view_info.view.x == 76.0)
                                                            {
                                                                bool _29381 = v_texture_coords.x < 0.0;
                                                                bool _29388 = false;
                                                                if (!_29381)
                                                                {
                                                                    _29388 = v_texture_coords.x > 1.0;
                                                                }
                                                                else
                                                                {
                                                                    _29388 = _29381;
                                                                }
                                                                bool _29395 = false;
                                                                if (!_29388)
                                                                {
                                                                    _29395 = v_texture_coords.y < 0.0;
                                                                }
                                                                else
                                                                {
                                                                    _29395 = _29388;
                                                                }
                                                                bool _29402 = false;
                                                                if (!_29395)
                                                                {
                                                                    _29402 = v_texture_coords.y > 1.0;
                                                                }
                                                                else
                                                                {
                                                                    _29402 = _29395;
                                                                }
                                                                bvec3 _29405 = bvec3(_29402);
                                                                _33731 = vec3(_29405.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _29405.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _29405.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                            }
                                                            else
                                                            {
                                                                vec2 _29418 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                _33731 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_29418.x + _29418.y, 2.0)));
                                                            }
                                                            _33730 = _33731;
                                                        }
                                                        _33729 = _33730;
                                                    }
                                                    _33728 = _33729;
                                                }
                                                _33727 = _33728;
                                            }
                                            _33726 = _33727;
                                        }
                                        _33725 = _33726;
                                    }
                                    _33724 = _33725;
                                }
                                else
                                {
                                    vec3 _33732 = vec3(0.0);
                                    if (debug_view_info.view.x == 80.0)
                                    {
                                        _33732 = vec3(0.0);
                                    }
                                    else
                                    {
                                        vec2 _29436 = floor(gl_FragCoord.xy * vec2(0.125));
                                        _33732 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_29436.x + _29436.y, 2.0)));
                                    }
                                    _33724 = _33732;
                                }
                                _33721 = _33724;
                            }
                            _33720 = _33721;
                        }
                        _33712 = _33720;
                    }
                    _33791 = vec4(_33712, 1.0);
                    break;
                } while(false);
                bvec4 _29455 = bvec4(gl_FragCoord.x >= debug_view_info.view.y);
                _33792 = vec4(_29455.x ? _33791.x : _32279.x, _29455.y ? _33791.y : _32279.y, _29455.z ? _33791.z : _32279.z, _29455.w ? _33791.w : _32279.w);
            }
            else
            {
                _33792 = _32279;
            }
            frag_color = _33792;
        }
    }
    float _34926 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _34926 = 1.0;
    }
    else
    {
        _34926 = abs(frag_info.fade);
    }
    frag_color *= _34926;
}

