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
    highp float _7142 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_7142 = _7142;
    vec3 _7144 = normalize(v_normal);
    vec3 _7146 = _7144 * mp_copy_7142;
    vec4 _7187 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _7190 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _24464 = vec2(0.0);
    if (_7190)
    {
        highp vec2 _24463 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _24463 = v_texture_coords_1;
        }
        else
        {
            _24463 = v_texture_coords;
        }
        highp vec2 _7377 = _24463 * texture_transforms.base_color_transform.zw;
        highp float _7383 = _7377.x;
        highp float _7388 = _7377.y;
        _24464 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _7383) - (texture_transforms.base_color_rotation.y * _7388), (texture_transforms.base_color_rotation.y * _7383) + (texture_transforms.base_color_rotation.x * _7388));
    }
    else
    {
        _24464 = v_texture_coords;
    }
    vec4 _7204 = texture(base_color_texture, _24464);
    vec3 _7206 = _7204.xyz;
    vec3 _7214 = (mix(_7206 * vec3(0.077399380505084991455078125), pow((_7206 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7206)) * _7187.xyz) * frag_info.color.xyz;
    float _28037 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_7204.w * _7187.w) * frag_info.color.w);
    float _7230 = _7214.x;
    float _7231 = _7214.y;
    float _7232 = _7214.z;
    vec4 _7233 = vec4(_7230, _7231, _7232, _28037);
    vec3 _24476 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _24467 = vec2(0.0);
        if (_7190)
        {
            highp vec2 _24466 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _24466 = v_texture_coords_1;
            }
            else
            {
                _24466 = v_texture_coords;
            }
            highp vec2 _7471 = _24466 * texture_transforms.normal_transform.zw;
            highp float _7477 = _7471.x;
            highp float _7482 = _7471.y;
            _24467 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _7477) - (texture_transforms.normal_rotation.y * _7482), (texture_transforms.normal_rotation.y * _7477) + (texture_transforms.normal_rotation.x * _7482));
        }
        else
        {
            _24467 = v_texture_coords;
        }
        vec3 _7529 = ((texture(normal_texture, _24467).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _7533 = _7529.xy * vec2(frag_info.normal_scale);
        vec3 _23669 = _7529;
        _23669.x = _7533.x;
        _23669.y = _7533.y;
        highp vec3 _7539 = -v_viewvector;
        mat3 _24475 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _7569 = v_tangent.xyz - (_7146 * dot(_7146, v_tangent.xyz));
            highp float _7572 = dot(_7569, _7569);
            bool _7574 = _7572 <= 1.0000000133514319600180897396058e-10;
            bool _7582 = false;
            if (!_7574)
            {
                _7582 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _7582 = _7574;
            }
            if (_7582)
            {
                highp vec2 _7640 = dFdx(_24467);
                highp vec2 _7642 = dFdy(_24467);
                bvec2 _28039 = bvec2(length(_7640) == 0.0);
                highp vec2 _28040 = vec2(_28039.x ? vec2(1.0, 0.0).x : _7640.x, _28039.y ? vec2(1.0, 0.0).y : _7640.y);
                bvec2 _28041 = bvec2(length(_7642) == 0.0);
                highp vec2 _28042 = vec2(_28041.x ? vec2(0.0, 1.0).x : _7642.x, _28041.y ? vec2(0.0, 1.0).y : _7642.y);
                highp vec3 _7655 = cross(dFdy(_7539), _7146);
                highp vec3 _7658 = cross(_7146, dFdx(_7539));
                highp vec3 _7667 = (_7655 * _28040.x) + (_7658 * _28042.x);
                highp vec3 _7676 = (_7655 * _28040.y) + (_7658 * _28042.y);
                highp float _7685 = inversesqrt(max(max(dot(_7667, _7667), dot(_7676, _7676)), 9.9999996826552253889678874634872e-21));
                _24475 = mat3(_7667 * _7685, _7676 * _7685, _7146);
                break;
            }
            highp vec3 _7592 = _7569 * inversesqrt(_7572);
            _24475 = mat3(_7592, normalize(cross(_7146, _7592)) * sign(v_tangent.w), _7146);
            break;
        } while(false);
        _24476 = normalize(_24475 * _23669);
    }
    else
    {
        _24476 = _7146;
    }
    highp vec2 _24478 = vec2(0.0);
    if (_7190)
    {
        highp vec2 _24477 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _24477 = v_texture_coords_1;
        }
        else
        {
            _24477 = v_texture_coords;
        }
        highp vec2 _7747 = _24477 * texture_transforms.metallic_roughness_transform.zw;
        highp float _7753 = _7747.x;
        highp float _7758 = _7747.y;
        _24478 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _7753) - (texture_transforms.metallic_roughness_rotation.y * _7758), (texture_transforms.metallic_roughness_rotation.y * _7753) + (texture_transforms.metallic_roughness_rotation.x * _7758));
    }
    else
    {
        _24478 = v_texture_coords;
    }
    vec4 _7273 = texture(metallic_roughness_texture, _24478);
    float _7279 = clamp(_7273.z * frag_info.metallic_factor, 0.0, 1.0);
    float _7286 = clamp(_7273.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _24480 = vec2(0.0);
    if (_7190)
    {
        highp vec2 _24479 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _24479 = v_texture_coords_1;
        }
        else
        {
            _24479 = v_texture_coords;
        }
        highp vec2 _7817 = _24479 * texture_transforms.occlusion_transform.zw;
        highp float _7823 = _7817.x;
        highp float _7828 = _7817.y;
        _24480 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _7823) - (texture_transforms.occlusion_rotation.y * _7828), (texture_transforms.occlusion_rotation.y * _7823) + (texture_transforms.occlusion_rotation.x * _7828));
    }
    else
    {
        _24480 = v_texture_coords;
    }
    vec4 _7301 = texture(occlusion_texture, _24480);
    float _7308 = 1.0 - ((1.0 - _7301.x) * frag_info.occlusion_strength);
    highp vec2 _24482 = vec2(0.0);
    if (_7190)
    {
        highp vec2 _24481 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _24481 = v_texture_coords_1;
        }
        else
        {
            _24481 = v_texture_coords;
        }
        highp vec2 _7887 = _24481 * texture_transforms.emissive_transform.zw;
        highp float _7893 = _7887.x;
        highp float _7898 = _7887.y;
        _24482 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _7893) - (texture_transforms.emissive_rotation.y * _7898), (texture_transforms.emissive_rotation.y * _7893) + (texture_transforms.emissive_rotation.x * _7898));
    }
    else
    {
        _24482 = v_texture_coords;
    }
    vec4 _7323 = texture(emissive_texture, _24482);
    vec3 _7324 = _7323.xyz;
    vec3 _7332 = (mix(_7324 * vec3(0.077399380505084991455078125), pow((_7324 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7324)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w;
    float _24512 = 0.0;
    do
    {
        if (debug_view_info.view.x < 0.5)
        {
            _24512 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _24512 = 1.0;
            break;
        }
        _24512 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    bool _6945 = gl_FragCoord.x >= debug_view_info.view.y;
    bool _6949 = _24512 < 0.5;
    bool _6958 = false;
    if (!_6949)
    {
        _6958 = (_24512 > 1.5) && (_24512 < 2.5);
    }
    else
    {
        _6958 = _6949;
    }
    vec4 _27275 = vec4(0.0);
    if (_6958)
    {
        highp float hp_copy_24529 = 0.0;
        vec3 _8166 = _7233.xyz;
        float _24529 = 0.0;
        do
        {
            if (frag_info.specular_aa_variance <= 0.0)
            {
                _24529 = _7286;
                break;
            }
            vec3 _8984 = dFdx(_24476);
            vec3 _8986 = dFdy(_24476);
            _24529 = sqrt(clamp((_7286 * _7286) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_8984, _8984), dot(_8986, _8986))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
            break;
        } while(false);
        hp_copy_24529 = _24529;
        float _24539 = 0.0;
        vec3 _24544 = vec3(0.0);
        float _24817 = 0.0;
        vec4 _25193 = vec4(0.0);
        vec3 _25344 = vec3(0.0);
        if (frag_info.ssao_params.x > 0.5)
        {
            vec4 _8193 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
            float _24530 = 0.0;
            if (frag_info.camera_up.w > 0.5)
            {
                _24530 = _8193.w;
            }
            else
            {
                _24530 = _8193.x;
            }
            float _8206 = min(_7308, _24530);
            bool _8209 = frag_info.ssao_lighting.z > 0.5;
            bool _8215 = false;
            if (_8209)
            {
                _8215 = frag_info.camera_up.w < 0.5;
            }
            else
            {
                _8215 = _8209;
            }
            vec3 _24545 = vec3(0.0);
            if (_8215)
            {
                vec2 _9019 = (_8193.zw * 2.0) - vec2(1.0);
                float _9021 = _9019.x;
                float _9023 = _9019.y;
                float _9031 = (1.0 - abs(_9021)) - abs(_9023);
                vec3 _9032 = vec3(_9021, _9023, _9031);
                vec3 _24533 = vec3(0.0);
                if (_9031 < 0.0)
                {
                    vec2 _9045 = (vec2(1.0) - abs(_9032.yx)) * vec2((_9021 >= 0.0) ? 1.0 : (-1.0), (_9023 >= 0.0) ? 1.0 : (-1.0));
                    vec3 _23718 = _9032;
                    _23718.x = _9045.x;
                    _23718.y = _9045.y;
                    _24533 = _23718;
                }
                else
                {
                    _24533 = _9032;
                }
                vec3 _9053 = -normalize(_24533);
                _24545 = normalize(((frag_info.camera_right.xyz * _9053.x) + (frag_info.camera_up.xyz * _9053.y)) + (frag_info.camera_forward.xyz * _9053.z));
            }
            else
            {
                _24545 = vec3(0.0);
            }
            vec3 _8243 = vec3(_8206);
            _25344 = mix(_8243, max(_8243, ((((((_8166 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _8206) + ((_8166 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _8206) + ((_8166 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _8206), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
            _25193 = _8193;
            _24817 = _8206;
            _24544 = _24545;
            _24539 = float(_8215);
        }
        else
        {
            _25344 = vec3(_7308);
            _25193 = vec4(1.0);
            _24817 = _7308;
            _24544 = vec3(0.0);
            _24539 = 0.0;
        }
        vec3 mp_copy_24537 = vec3(0.0);
        bool _9102 = view_info.camera_forward.w > 0.5;
        highp vec3 _24537 = vec3(0.0);
        if (_9102)
        {
            _24537 = -view_info.camera_forward.xyz;
        }
        else
        {
            _24537 = normalize(v_viewvector);
        }
        mp_copy_24537 = _24537;
        vec3 _8261 = mix(frag_info.dielectric_f0.xyz, _8166, vec3(_7279));
        float _8264 = dot(_24476, _24537);
        float _8265 = max(_8264, 0.0);
        float _8269 = max(dot(_7146, _24537), 0.0);
        vec3 _8273 = reflect(-mp_copy_24537, _24476);
        mat3 _8286 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
        bool _8289 = _24539 > 0.5;
        bvec3 _8292 = bvec3(_8289);
        highp vec3 _8293 = vec3(_8292.x ? _24544.x : _24476.x, _8292.y ? _24544.y : _24476.y, _8292.z ? _24544.z : _24476.z);
        vec3 mp_copy_8293 = _8293;
        vec3 _8294 = _8286 * mp_copy_8293;
        vec3 _24548 = vec3(0.0);
        if (frag_info.probe_box.w > 0.5)
        {
            vec3 _9169 = _8273 + (((step(vec3(0.0), _8273) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
            highp vec3 hp_copy_9169 = _9169;
            highp vec3 _9171 = vec3(1.0) / hp_copy_9169;
            highp vec3 _9188 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _9171, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _9171);
            _24548 = normalize((v_position + (_8273 * max(min(min(_9188.x, _9188.y), _9188.z), 0.0))) - frag_info.probe_box.xyz);
        }
        else
        {
            _24548 = _8273;
        }
        bool _9416 = false;
        vec3 _8299 = _8286 * _24548;
        float _9235 = _8294.y;
        float _9236 = 0.48860299587249755859375 * _9235;
        float _9242 = _8294.z;
        float _9243 = 0.48860299587249755859375 * _9242;
        float _9249 = _8294.x;
        float _9250 = 0.48860299587249755859375 * _9249;
        float _9257 = 1.09254801273345947265625 * _9249;
        float _9260 = _9257 * _9235;
        float _9270 = (1.09254801273345947265625 * _9235) * _9242;
        float _9282 = 0.3153919875621795654296875 * (((3.0 * _9242) * _9242) - 1.0);
        float _9292 = _9257 * _9242;
        float _9308 = 0.546274006366729736328125 * ((_9249 * _9249) - (_9235 * _9235));
        vec3 _8302 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _9236)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _9243)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _9250)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _9260)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _9270)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _9282)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _9292)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _9308), vec3(0.0));
        vec3 _24549 = vec3(0.0);
        do
        {
            _9416 = radiance_layout_info.mip_layout > 0.5;
            if (_9416)
            {
                vec2 _9495 = vec2(atan(_8299.z, _8299.x), asin(clamp(_8299.y, -1.0, 1.0)));
                highp vec2 hp_copy_9495 = _9495;
                _24549 = textureLod(prefiltered_radiance, (hp_copy_9495 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24529, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9514 = vec2(atan(_8299.z, _8299.x), asin(clamp(_8299.y, -1.0, 1.0)));
            highp vec2 hp_copy_9514 = _9514;
            highp vec2 _9519 = (hp_copy_9514 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9426 = clamp(_9519.y, 0.00390625, 0.99609375);
            float _9430 = clamp(_24529, 0.0, 1.0) * 7.0;
            float _9432 = floor(_9430);
            highp float _9451 = _9519.x;
            _24549 = mix(texture(prefiltered_radiance, vec2(_9451, (_9432 + _9426) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_9451, (min(_9432 + 1.0, 7.0) + _9426) * 0.125)).xyz, vec3(_9430 - _9432));
            break;
        } while(false);
        bool _8309 = frag_info.radiance_blend.x > 0.0;
        highp vec3 _24554 = vec3(0.0);
        highp vec3 _24555 = vec3(0.0);
        if (_8309)
        {
            vec3 _24550 = vec3(0.0);
            do
            {
                if (_9416)
                {
                    vec2 _9807 = vec2(atan(_8299.z, _8299.x), asin(clamp(_8299.y, -1.0, 1.0)));
                    highp vec2 hp_copy_9807 = _9807;
                    _24550 = textureLod(prefiltered_radiance_b, (hp_copy_9807 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24529, 0.0, 1.0) * 7.0).xyz;
                    break;
                }
                vec2 _9826 = vec2(atan(_8299.z, _8299.x), asin(clamp(_8299.y, -1.0, 1.0)));
                highp vec2 hp_copy_9826 = _9826;
                highp vec2 _9831 = (hp_copy_9826 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _9738 = clamp(_9831.y, 0.00390625, 0.99609375);
                float _9742 = clamp(_24529, 0.0, 1.0) * 7.0;
                float _9744 = floor(_9742);
                highp float _9763 = _9831.x;
                _24550 = mix(texture(prefiltered_radiance_b, vec2(_9763, (_9744 + _9738) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_9763, (min(_9744 + 1.0, 7.0) + _9738) * 0.125)).xyz, vec3(_9742 - _9744));
                break;
            } while(false);
            highp vec3 _8320 = vec3(frag_info.radiance_blend.x);
            _24555 = mix(_24549, _24550, _8320);
            _24554 = mix(_8302, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _9236)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _9243)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _9250)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _9260)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _9270)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _9282)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _9292)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _9308), vec3(0.0)), _8320);
        }
        else
        {
            _24555 = _24549;
            _24554 = _8302;
        }
        highp float _9844 = 0.0;
        highp vec3 _8331 = _24554 * frag_info.environment_intensity;
        float _24556 = 0.0;
        do
        {
            _9844 = frag_info.gi_grid.w;
            if (_9844 <= 0.0)
            {
                _24556 = 0.0;
                break;
            }
            highp vec3 _9857 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
            highp vec3 _9865 = min(_9857, (frag_info.gi_counts.xyz - vec3(1.0)) - _9857);
            _24556 = clamp(min(_9865.x, min(_9865.y, _9865.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
            break;
        } while(false);
        highp vec3 _24747 = vec3(0.0);
        if (_24556 > 0.0)
        {
            highp vec3 _9957 = v_position + (((_24476 * 0.20000000298023223876953125) + (mp_copy_24537 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
            highp vec3 _9960 = _9957 / frag_info.gi_grid.xyz;
            highp vec3 _9962 = floor(_9960);
            highp vec3 _9968 = clamp(_9960 - _9962, vec3(0.0), vec3(1.0));
            vec3 mp_copy_9968 = _9968;
            highp vec3 _10090 = _9962 - frag_info.gi_anchor.xyz;
            bool _10093 = any(lessThan(_10090, vec3(0.0)));
            bool _10101 = false;
            if (!_10093)
            {
                _10101 = any(greaterThanEqual(_10090, frag_info.gi_counts.xyz));
            }
            else
            {
                _10101 = _10093;
            }
            vec3 mp_copy_24557 = vec3(0.0);
            highp float _10102 = _10101 ? 0.0 : 1.0;
            float mp_copy_10102 = _10102;
            vec3 _10104 = vec3(1.0) - mp_copy_9968;
            vec3 _10108 = max(_10104, vec3(0.001000000047497451305389404296875));
            highp vec3 _10124 = (_9962 * frag_info.gi_grid.xyz) - _9957;
            highp float _10126 = length(_10124);
            highp vec3 _24557 = vec3(0.0);
            if (_10126 > 9.9999997473787516355514526367188e-06)
            {
                _24557 = _10124 / vec3(_10126);
            }
            else
            {
                _24557 = _24476;
            }
            mp_copy_24557 = _24557;
            float _10144 = pow((dot(_24557, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10269 = _9962 - (frag_info.gi_counts.xyz * floor(_9962 / frag_info.gi_counts.xyz));
            highp float _10285 = _10269.x + (frag_info.gi_counts.x * (_10269.y + (frag_info.gi_counts.y * _10269.z)));
            bool _10155 = frag_info.gi_visibility.x > 0.0;
            float _24562 = 0.0;
            if (_10155)
            {
                highp float _10293 = floor(_10285 / frag_info.gi_counts.w);
                highp vec2 _10307 = vec2((_10285 - (_10293 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10293 * 16.0));
                vec3 _10167 = -mp_copy_24557;
                vec3 _10355 = _10167 / vec3((abs(_10167.x) + abs(_10167.y)) + abs(_10167.z));
                vec2 _24558 = vec2(0.0);
                if (_10355.z >= 0.0)
                {
                    _24558 = _10355.xy;
                }
                else
                {
                    _24558 = (vec2(1.0) - abs(_10355.yx)) * vec2((_10355.x >= 0.0) ? 1.0 : (-1.0), (_10355.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10171 = texture(irradiance_field, clamp((_10307 + vec2(1.0)) + (clamp((_24558 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10307 + vec2(0.5), _10307 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10176 = _10171.x * frag_info.gi_visibility.z;
                highp float _10188 = abs((_10176 * _10176) - ((_10171.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10194 = (_10126 - _10176) - frag_info.gi_visibility.y;
                highp float _24559 = 0.0;
                if (_10194 <= 0.0)
                {
                    _24559 = 1.0;
                }
                else
                {
                    _24559 = _10188 / (_10188 + (_10194 * _10194));
                }
                _24562 = _10144 * mix(1.0, max(0.0500000007450580596923828125, (_24559 * _24559) * _24559), frag_info.gi_visibility.x);
            }
            else
            {
                _24562 = _10144;
            }
            float _10222 = max(9.9999999747524270787835121154785e-07, _24562);
            float _24563 = 0.0;
            if (_10222 < 0.20000000298023223876953125)
            {
                _24563 = _10222 * ((_10222 * _10222) * 25.0);
            }
            else
            {
                _24563 = _10222;
            }
            float _10237 = _24563 * (((_10108.x * _10108.y) * _10108.z) * mp_copy_10102);
            highp float _10396 = floor(_10285 / frag_info.gi_counts.w);
            highp vec2 _10410 = vec2((_10285 - (_10396 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10396 * 8.0));
            vec3 _10458 = _24476 / vec3((abs(_24476.x) + abs(_24476.y)) + abs(_24476.z));
            bool _10461 = _10458.z >= 0.0;
            vec2 _24564 = vec2(0.0);
            if (_10461)
            {
                _24564 = _10458.xy;
            }
            else
            {
                _24564 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10249 = texture(irradiance_field, clamp((_10410 + vec2(1.0)) + (clamp((_24564 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10410 + vec2(0.5), _10410 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _10544 = _9962 + vec3(1.0, 0.0, 0.0);
            highp vec3 _10549 = _10544 - frag_info.gi_anchor.xyz;
            bool _10552 = any(lessThan(_10549, vec3(0.0)));
            bool _10560 = false;
            if (!_10552)
            {
                _10560 = any(greaterThanEqual(_10549, frag_info.gi_counts.xyz));
            }
            else
            {
                _10560 = _10552;
            }
            vec3 mp_copy_24566 = vec3(0.0);
            highp float _10561 = _10560 ? 0.0 : 1.0;
            float mp_copy_10561 = _10561;
            vec3 _10567 = max(mix(_10104, mp_copy_9968, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _10583 = (_10544 * frag_info.gi_grid.xyz) - _9957;
            highp float _10585 = length(_10583);
            highp vec3 _24566 = vec3(0.0);
            if (_10585 > 9.9999997473787516355514526367188e-06)
            {
                _24566 = _10583 / vec3(_10585);
            }
            else
            {
                _24566 = _24476;
            }
            mp_copy_24566 = _24566;
            float _10603 = pow((dot(_24566, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10728 = _10544 - (frag_info.gi_counts.xyz * floor(_10544 / frag_info.gi_counts.xyz));
            highp float _10744 = _10728.x + (frag_info.gi_counts.x * (_10728.y + (frag_info.gi_counts.y * _10728.z)));
            float _24571 = 0.0;
            if (_10155)
            {
                highp float _10752 = floor(_10744 / frag_info.gi_counts.w);
                highp vec2 _10766 = vec2((_10744 - (_10752 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10752 * 16.0));
                vec3 _10626 = -mp_copy_24566;
                vec3 _10814 = _10626 / vec3((abs(_10626.x) + abs(_10626.y)) + abs(_10626.z));
                vec2 _24567 = vec2(0.0);
                if (_10814.z >= 0.0)
                {
                    _24567 = _10814.xy;
                }
                else
                {
                    _24567 = (vec2(1.0) - abs(_10814.yx)) * vec2((_10814.x >= 0.0) ? 1.0 : (-1.0), (_10814.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10630 = texture(irradiance_field, clamp((_10766 + vec2(1.0)) + (clamp((_24567 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10766 + vec2(0.5), _10766 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10635 = _10630.x * frag_info.gi_visibility.z;
                highp float _10647 = abs((_10635 * _10635) - ((_10630.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10653 = (_10585 - _10635) - frag_info.gi_visibility.y;
                highp float _24568 = 0.0;
                if (_10653 <= 0.0)
                {
                    _24568 = 1.0;
                }
                else
                {
                    _24568 = _10647 / (_10647 + (_10653 * _10653));
                }
                _24571 = _10603 * mix(1.0, max(0.0500000007450580596923828125, (_24568 * _24568) * _24568), frag_info.gi_visibility.x);
            }
            else
            {
                _24571 = _10603;
            }
            float _10681 = max(9.9999999747524270787835121154785e-07, _24571);
            float _24572 = 0.0;
            if (_10681 < 0.20000000298023223876953125)
            {
                _24572 = _10681 * ((_10681 * _10681) * 25.0);
            }
            else
            {
                _24572 = _10681;
            }
            float _10696 = _24572 * (((_10567.x * _10567.y) * _10567.z) * mp_copy_10561);
            highp float _10855 = floor(_10744 / frag_info.gi_counts.w);
            highp vec2 _10869 = vec2((_10744 - (_10855 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10855 * 8.0));
            vec2 _24573 = vec2(0.0);
            if (_10461)
            {
                _24573 = _10458.xy;
            }
            else
            {
                _24573 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10708 = texture(irradiance_field, clamp((_10869 + vec2(1.0)) + (clamp((_24573 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10869 + vec2(0.5), _10869 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11003 = _9962 + vec3(0.0, 1.0, 0.0);
            highp vec3 _11008 = _11003 - frag_info.gi_anchor.xyz;
            bool _11011 = any(lessThan(_11008, vec3(0.0)));
            bool _11019 = false;
            if (!_11011)
            {
                _11019 = any(greaterThanEqual(_11008, frag_info.gi_counts.xyz));
            }
            else
            {
                _11019 = _11011;
            }
            vec3 mp_copy_24575 = vec3(0.0);
            highp float _11020 = _11019 ? 0.0 : 1.0;
            float mp_copy_11020 = _11020;
            vec3 _11026 = max(mix(_10104, mp_copy_9968, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11042 = (_11003 * frag_info.gi_grid.xyz) - _9957;
            highp float _11044 = length(_11042);
            highp vec3 _24575 = vec3(0.0);
            if (_11044 > 9.9999997473787516355514526367188e-06)
            {
                _24575 = _11042 / vec3(_11044);
            }
            else
            {
                _24575 = _24476;
            }
            mp_copy_24575 = _24575;
            float _11062 = pow((dot(_24575, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11187 = _11003 - (frag_info.gi_counts.xyz * floor(_11003 / frag_info.gi_counts.xyz));
            highp float _11203 = _11187.x + (frag_info.gi_counts.x * (_11187.y + (frag_info.gi_counts.y * _11187.z)));
            float _24580 = 0.0;
            if (_10155)
            {
                highp float _11211 = floor(_11203 / frag_info.gi_counts.w);
                highp vec2 _11225 = vec2((_11203 - (_11211 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11211 * 16.0));
                vec3 _11085 = -mp_copy_24575;
                vec3 _11273 = _11085 / vec3((abs(_11085.x) + abs(_11085.y)) + abs(_11085.z));
                vec2 _24576 = vec2(0.0);
                if (_11273.z >= 0.0)
                {
                    _24576 = _11273.xy;
                }
                else
                {
                    _24576 = (vec2(1.0) - abs(_11273.yx)) * vec2((_11273.x >= 0.0) ? 1.0 : (-1.0), (_11273.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11089 = texture(irradiance_field, clamp((_11225 + vec2(1.0)) + (clamp((_24576 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11225 + vec2(0.5), _11225 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11094 = _11089.x * frag_info.gi_visibility.z;
                highp float _11106 = abs((_11094 * _11094) - ((_11089.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11112 = (_11044 - _11094) - frag_info.gi_visibility.y;
                highp float _24577 = 0.0;
                if (_11112 <= 0.0)
                {
                    _24577 = 1.0;
                }
                else
                {
                    _24577 = _11106 / (_11106 + (_11112 * _11112));
                }
                _24580 = _11062 * mix(1.0, max(0.0500000007450580596923828125, (_24577 * _24577) * _24577), frag_info.gi_visibility.x);
            }
            else
            {
                _24580 = _11062;
            }
            float _11140 = max(9.9999999747524270787835121154785e-07, _24580);
            float _24581 = 0.0;
            if (_11140 < 0.20000000298023223876953125)
            {
                _24581 = _11140 * ((_11140 * _11140) * 25.0);
            }
            else
            {
                _24581 = _11140;
            }
            float _11155 = _24581 * (((_11026.x * _11026.y) * _11026.z) * mp_copy_11020);
            highp float _11314 = floor(_11203 / frag_info.gi_counts.w);
            highp vec2 _11328 = vec2((_11203 - (_11314 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11314 * 8.0));
            vec2 _24582 = vec2(0.0);
            if (_10461)
            {
                _24582 = _10458.xy;
            }
            else
            {
                _24582 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11167 = texture(irradiance_field, clamp((_11328 + vec2(1.0)) + (clamp((_24582 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11328 + vec2(0.5), _11328 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11462 = _9962 + vec3(1.0, 1.0, 0.0);
            highp vec3 _11467 = _11462 - frag_info.gi_anchor.xyz;
            bool _11470 = any(lessThan(_11467, vec3(0.0)));
            bool _11478 = false;
            if (!_11470)
            {
                _11478 = any(greaterThanEqual(_11467, frag_info.gi_counts.xyz));
            }
            else
            {
                _11478 = _11470;
            }
            vec3 mp_copy_24584 = vec3(0.0);
            highp float _11479 = _11478 ? 0.0 : 1.0;
            float mp_copy_11479 = _11479;
            vec3 _11485 = max(mix(_10104, mp_copy_9968, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11501 = (_11462 * frag_info.gi_grid.xyz) - _9957;
            highp float _11503 = length(_11501);
            highp vec3 _24584 = vec3(0.0);
            if (_11503 > 9.9999997473787516355514526367188e-06)
            {
                _24584 = _11501 / vec3(_11503);
            }
            else
            {
                _24584 = _24476;
            }
            mp_copy_24584 = _24584;
            float _11521 = pow((dot(_24584, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11646 = _11462 - (frag_info.gi_counts.xyz * floor(_11462 / frag_info.gi_counts.xyz));
            highp float _11662 = _11646.x + (frag_info.gi_counts.x * (_11646.y + (frag_info.gi_counts.y * _11646.z)));
            float _24589 = 0.0;
            if (_10155)
            {
                highp float _11670 = floor(_11662 / frag_info.gi_counts.w);
                highp vec2 _11684 = vec2((_11662 - (_11670 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11670 * 16.0));
                vec3 _11544 = -mp_copy_24584;
                vec3 _11732 = _11544 / vec3((abs(_11544.x) + abs(_11544.y)) + abs(_11544.z));
                vec2 _24585 = vec2(0.0);
                if (_11732.z >= 0.0)
                {
                    _24585 = _11732.xy;
                }
                else
                {
                    _24585 = (vec2(1.0) - abs(_11732.yx)) * vec2((_11732.x >= 0.0) ? 1.0 : (-1.0), (_11732.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11548 = texture(irradiance_field, clamp((_11684 + vec2(1.0)) + (clamp((_24585 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11684 + vec2(0.5), _11684 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11553 = _11548.x * frag_info.gi_visibility.z;
                highp float _11565 = abs((_11553 * _11553) - ((_11548.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11571 = (_11503 - _11553) - frag_info.gi_visibility.y;
                highp float _24586 = 0.0;
                if (_11571 <= 0.0)
                {
                    _24586 = 1.0;
                }
                else
                {
                    _24586 = _11565 / (_11565 + (_11571 * _11571));
                }
                _24589 = _11521 * mix(1.0, max(0.0500000007450580596923828125, (_24586 * _24586) * _24586), frag_info.gi_visibility.x);
            }
            else
            {
                _24589 = _11521;
            }
            float _11599 = max(9.9999999747524270787835121154785e-07, _24589);
            float _24590 = 0.0;
            if (_11599 < 0.20000000298023223876953125)
            {
                _24590 = _11599 * ((_11599 * _11599) * 25.0);
            }
            else
            {
                _24590 = _11599;
            }
            float _11614 = _24590 * (((_11485.x * _11485.y) * _11485.z) * mp_copy_11479);
            highp float _11773 = floor(_11662 / frag_info.gi_counts.w);
            highp vec2 _11787 = vec2((_11662 - (_11773 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11773 * 8.0));
            vec2 _24591 = vec2(0.0);
            if (_10461)
            {
                _24591 = _10458.xy;
            }
            else
            {
                _24591 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11626 = texture(irradiance_field, clamp((_11787 + vec2(1.0)) + (clamp((_24591 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11787 + vec2(0.5), _11787 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11921 = _9962 + vec3(0.0, 0.0, 1.0);
            highp vec3 _11926 = _11921 - frag_info.gi_anchor.xyz;
            bool _11929 = any(lessThan(_11926, vec3(0.0)));
            bool _11937 = false;
            if (!_11929)
            {
                _11937 = any(greaterThanEqual(_11926, frag_info.gi_counts.xyz));
            }
            else
            {
                _11937 = _11929;
            }
            vec3 mp_copy_24593 = vec3(0.0);
            highp float _11938 = _11937 ? 0.0 : 1.0;
            float mp_copy_11938 = _11938;
            vec3 _11944 = max(mix(_10104, mp_copy_9968, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11960 = (_11921 * frag_info.gi_grid.xyz) - _9957;
            highp float _11962 = length(_11960);
            highp vec3 _24593 = vec3(0.0);
            if (_11962 > 9.9999997473787516355514526367188e-06)
            {
                _24593 = _11960 / vec3(_11962);
            }
            else
            {
                _24593 = _24476;
            }
            mp_copy_24593 = _24593;
            float _11980 = pow((dot(_24593, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12105 = _11921 - (frag_info.gi_counts.xyz * floor(_11921 / frag_info.gi_counts.xyz));
            highp float _12121 = _12105.x + (frag_info.gi_counts.x * (_12105.y + (frag_info.gi_counts.y * _12105.z)));
            float _24598 = 0.0;
            if (_10155)
            {
                highp float _12129 = floor(_12121 / frag_info.gi_counts.w);
                highp vec2 _12143 = vec2((_12121 - (_12129 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12129 * 16.0));
                vec3 _12003 = -mp_copy_24593;
                vec3 _12191 = _12003 / vec3((abs(_12003.x) + abs(_12003.y)) + abs(_12003.z));
                vec2 _24594 = vec2(0.0);
                if (_12191.z >= 0.0)
                {
                    _24594 = _12191.xy;
                }
                else
                {
                    _24594 = (vec2(1.0) - abs(_12191.yx)) * vec2((_12191.x >= 0.0) ? 1.0 : (-1.0), (_12191.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12007 = texture(irradiance_field, clamp((_12143 + vec2(1.0)) + (clamp((_24594 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12143 + vec2(0.5), _12143 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12012 = _12007.x * frag_info.gi_visibility.z;
                highp float _12024 = abs((_12012 * _12012) - ((_12007.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12030 = (_11962 - _12012) - frag_info.gi_visibility.y;
                highp float _24595 = 0.0;
                if (_12030 <= 0.0)
                {
                    _24595 = 1.0;
                }
                else
                {
                    _24595 = _12024 / (_12024 + (_12030 * _12030));
                }
                _24598 = _11980 * mix(1.0, max(0.0500000007450580596923828125, (_24595 * _24595) * _24595), frag_info.gi_visibility.x);
            }
            else
            {
                _24598 = _11980;
            }
            float _12058 = max(9.9999999747524270787835121154785e-07, _24598);
            float _24599 = 0.0;
            if (_12058 < 0.20000000298023223876953125)
            {
                _24599 = _12058 * ((_12058 * _12058) * 25.0);
            }
            else
            {
                _24599 = _12058;
            }
            float _12073 = _24599 * (((_11944.x * _11944.y) * _11944.z) * mp_copy_11938);
            highp float _12232 = floor(_12121 / frag_info.gi_counts.w);
            highp vec2 _12246 = vec2((_12121 - (_12232 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12232 * 8.0));
            vec2 _24600 = vec2(0.0);
            if (_10461)
            {
                _24600 = _10458.xy;
            }
            else
            {
                _24600 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12085 = texture(irradiance_field, clamp((_12246 + vec2(1.0)) + (clamp((_24600 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12246 + vec2(0.5), _12246 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12380 = _9962 + vec3(1.0, 0.0, 1.0);
            highp vec3 _12385 = _12380 - frag_info.gi_anchor.xyz;
            bool _12388 = any(lessThan(_12385, vec3(0.0)));
            bool _12396 = false;
            if (!_12388)
            {
                _12396 = any(greaterThanEqual(_12385, frag_info.gi_counts.xyz));
            }
            else
            {
                _12396 = _12388;
            }
            vec3 mp_copy_24602 = vec3(0.0);
            highp float _12397 = _12396 ? 0.0 : 1.0;
            float mp_copy_12397 = _12397;
            vec3 _12403 = max(mix(_10104, mp_copy_9968, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12419 = (_12380 * frag_info.gi_grid.xyz) - _9957;
            highp float _12421 = length(_12419);
            highp vec3 _24602 = vec3(0.0);
            if (_12421 > 9.9999997473787516355514526367188e-06)
            {
                _24602 = _12419 / vec3(_12421);
            }
            else
            {
                _24602 = _24476;
            }
            mp_copy_24602 = _24602;
            float _12439 = pow((dot(_24602, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12564 = _12380 - (frag_info.gi_counts.xyz * floor(_12380 / frag_info.gi_counts.xyz));
            highp float _12580 = _12564.x + (frag_info.gi_counts.x * (_12564.y + (frag_info.gi_counts.y * _12564.z)));
            float _24607 = 0.0;
            if (_10155)
            {
                highp float _12588 = floor(_12580 / frag_info.gi_counts.w);
                highp vec2 _12602 = vec2((_12580 - (_12588 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12588 * 16.0));
                vec3 _12462 = -mp_copy_24602;
                vec3 _12650 = _12462 / vec3((abs(_12462.x) + abs(_12462.y)) + abs(_12462.z));
                vec2 _24603 = vec2(0.0);
                if (_12650.z >= 0.0)
                {
                    _24603 = _12650.xy;
                }
                else
                {
                    _24603 = (vec2(1.0) - abs(_12650.yx)) * vec2((_12650.x >= 0.0) ? 1.0 : (-1.0), (_12650.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12466 = texture(irradiance_field, clamp((_12602 + vec2(1.0)) + (clamp((_24603 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12602 + vec2(0.5), _12602 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12471 = _12466.x * frag_info.gi_visibility.z;
                highp float _12483 = abs((_12471 * _12471) - ((_12466.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12489 = (_12421 - _12471) - frag_info.gi_visibility.y;
                highp float _24604 = 0.0;
                if (_12489 <= 0.0)
                {
                    _24604 = 1.0;
                }
                else
                {
                    _24604 = _12483 / (_12483 + (_12489 * _12489));
                }
                _24607 = _12439 * mix(1.0, max(0.0500000007450580596923828125, (_24604 * _24604) * _24604), frag_info.gi_visibility.x);
            }
            else
            {
                _24607 = _12439;
            }
            float _12517 = max(9.9999999747524270787835121154785e-07, _24607);
            float _24608 = 0.0;
            if (_12517 < 0.20000000298023223876953125)
            {
                _24608 = _12517 * ((_12517 * _12517) * 25.0);
            }
            else
            {
                _24608 = _12517;
            }
            float _12532 = _24608 * (((_12403.x * _12403.y) * _12403.z) * mp_copy_12397);
            highp float _12691 = floor(_12580 / frag_info.gi_counts.w);
            highp vec2 _12705 = vec2((_12580 - (_12691 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12691 * 8.0));
            vec2 _24609 = vec2(0.0);
            if (_10461)
            {
                _24609 = _10458.xy;
            }
            else
            {
                _24609 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12544 = texture(irradiance_field, clamp((_12705 + vec2(1.0)) + (clamp((_24609 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12705 + vec2(0.5), _12705 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12839 = _9962 + vec3(0.0, 1.0, 1.0);
            highp vec3 _12844 = _12839 - frag_info.gi_anchor.xyz;
            bool _12847 = any(lessThan(_12844, vec3(0.0)));
            bool _12855 = false;
            if (!_12847)
            {
                _12855 = any(greaterThanEqual(_12844, frag_info.gi_counts.xyz));
            }
            else
            {
                _12855 = _12847;
            }
            vec3 mp_copy_24611 = vec3(0.0);
            highp float _12856 = _12855 ? 0.0 : 1.0;
            float mp_copy_12856 = _12856;
            vec3 _12862 = max(mix(_10104, mp_copy_9968, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12878 = (_12839 * frag_info.gi_grid.xyz) - _9957;
            highp float _12880 = length(_12878);
            highp vec3 _24611 = vec3(0.0);
            if (_12880 > 9.9999997473787516355514526367188e-06)
            {
                _24611 = _12878 / vec3(_12880);
            }
            else
            {
                _24611 = _24476;
            }
            mp_copy_24611 = _24611;
            float _12898 = pow((dot(_24611, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13023 = _12839 - (frag_info.gi_counts.xyz * floor(_12839 / frag_info.gi_counts.xyz));
            highp float _13039 = _13023.x + (frag_info.gi_counts.x * (_13023.y + (frag_info.gi_counts.y * _13023.z)));
            float _24616 = 0.0;
            if (_10155)
            {
                highp float _13047 = floor(_13039 / frag_info.gi_counts.w);
                highp vec2 _13061 = vec2((_13039 - (_13047 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13047 * 16.0));
                vec3 _12921 = -mp_copy_24611;
                vec3 _13109 = _12921 / vec3((abs(_12921.x) + abs(_12921.y)) + abs(_12921.z));
                vec2 _24612 = vec2(0.0);
                if (_13109.z >= 0.0)
                {
                    _24612 = _13109.xy;
                }
                else
                {
                    _24612 = (vec2(1.0) - abs(_13109.yx)) * vec2((_13109.x >= 0.0) ? 1.0 : (-1.0), (_13109.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12925 = texture(irradiance_field, clamp((_13061 + vec2(1.0)) + (clamp((_24612 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13061 + vec2(0.5), _13061 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12930 = _12925.x * frag_info.gi_visibility.z;
                highp float _12942 = abs((_12930 * _12930) - ((_12925.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12948 = (_12880 - _12930) - frag_info.gi_visibility.y;
                highp float _24613 = 0.0;
                if (_12948 <= 0.0)
                {
                    _24613 = 1.0;
                }
                else
                {
                    _24613 = _12942 / (_12942 + (_12948 * _12948));
                }
                _24616 = _12898 * mix(1.0, max(0.0500000007450580596923828125, (_24613 * _24613) * _24613), frag_info.gi_visibility.x);
            }
            else
            {
                _24616 = _12898;
            }
            float _12976 = max(9.9999999747524270787835121154785e-07, _24616);
            float _24617 = 0.0;
            if (_12976 < 0.20000000298023223876953125)
            {
                _24617 = _12976 * ((_12976 * _12976) * 25.0);
            }
            else
            {
                _24617 = _12976;
            }
            float _12991 = _24617 * (((_12862.x * _12862.y) * _12862.z) * mp_copy_12856);
            highp float _13150 = floor(_13039 / frag_info.gi_counts.w);
            highp vec2 _13164 = vec2((_13039 - (_13150 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13150 * 8.0));
            vec2 _24618 = vec2(0.0);
            if (_10461)
            {
                _24618 = _10458.xy;
            }
            else
            {
                _24618 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13003 = texture(irradiance_field, clamp((_13164 + vec2(1.0)) + (clamp((_24618 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13164 + vec2(0.5), _13164 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _13298 = _9962 + vec3(1.0);
            highp vec3 _13303 = _13298 - frag_info.gi_anchor.xyz;
            bool _13306 = any(lessThan(_13303, vec3(0.0)));
            bool _13314 = false;
            if (!_13306)
            {
                _13314 = any(greaterThanEqual(_13303, frag_info.gi_counts.xyz));
            }
            else
            {
                _13314 = _13306;
            }
            vec3 mp_copy_24620 = vec3(0.0);
            highp float _13315 = _13314 ? 0.0 : 1.0;
            float mp_copy_13315 = _13315;
            vec3 _13321 = max(mp_copy_9968, vec3(0.001000000047497451305389404296875));
            highp vec3 _13337 = (_13298 * frag_info.gi_grid.xyz) - _9957;
            highp float _13339 = length(_13337);
            highp vec3 _24620 = vec3(0.0);
            if (_13339 > 9.9999997473787516355514526367188e-06)
            {
                _24620 = _13337 / vec3(_13339);
            }
            else
            {
                _24620 = _24476;
            }
            mp_copy_24620 = _24620;
            float _13357 = pow((dot(_24620, _24476) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13482 = _13298 - (frag_info.gi_counts.xyz * floor(_13298 / frag_info.gi_counts.xyz));
            highp float _13498 = _13482.x + (frag_info.gi_counts.x * (_13482.y + (frag_info.gi_counts.y * _13482.z)));
            float _24625 = 0.0;
            if (_10155)
            {
                highp float _13506 = floor(_13498 / frag_info.gi_counts.w);
                highp vec2 _13520 = vec2((_13498 - (_13506 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13506 * 16.0));
                vec3 _13380 = -mp_copy_24620;
                vec3 _13568 = _13380 / vec3((abs(_13380.x) + abs(_13380.y)) + abs(_13380.z));
                vec2 _24621 = vec2(0.0);
                if (_13568.z >= 0.0)
                {
                    _24621 = _13568.xy;
                }
                else
                {
                    _24621 = (vec2(1.0) - abs(_13568.yx)) * vec2((_13568.x >= 0.0) ? 1.0 : (-1.0), (_13568.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _13384 = texture(irradiance_field, clamp((_13520 + vec2(1.0)) + (clamp((_24621 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13520 + vec2(0.5), _13520 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _13389 = _13384.x * frag_info.gi_visibility.z;
                highp float _13401 = abs((_13389 * _13389) - ((_13384.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _13407 = (_13339 - _13389) - frag_info.gi_visibility.y;
                highp float _24622 = 0.0;
                if (_13407 <= 0.0)
                {
                    _24622 = 1.0;
                }
                else
                {
                    _24622 = _13401 / (_13401 + (_13407 * _13407));
                }
                _24625 = _13357 * mix(1.0, max(0.0500000007450580596923828125, (_24622 * _24622) * _24622), frag_info.gi_visibility.x);
            }
            else
            {
                _24625 = _13357;
            }
            float _13435 = max(9.9999999747524270787835121154785e-07, _24625);
            float _24626 = 0.0;
            if (_13435 < 0.20000000298023223876953125)
            {
                _24626 = _13435 * ((_13435 * _13435) * 25.0);
            }
            else
            {
                _24626 = _13435;
            }
            float _13450 = _24626 * (((_13321.x * _13321.y) * _13321.z) * mp_copy_13315);
            highp float _13609 = floor(_13498 / frag_info.gi_counts.w);
            highp vec2 _13623 = vec2((_13498 - (_13609 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13609 * 8.0));
            vec2 _24627 = vec2(0.0);
            if (_10461)
            {
                _24627 = _10458.xy;
            }
            else
            {
                _24627 = (vec2(1.0) - abs(_10458.yx)) * vec2((_10458.x >= 0.0) ? 1.0 : (-1.0), (_10458.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10015 = ((((((vec4(max(_10249.xyz, vec3(0.0)) * _10237, _10237) + vec4(max(_10708.xyz, vec3(0.0)) * _10696, _10696)) + vec4(max(_11167.xyz, vec3(0.0)) * _11155, _11155)) + vec4(max(_11626.xyz, vec3(0.0)) * _11614, _11614)) + vec4(max(_12085.xyz, vec3(0.0)) * _12073, _12073)) + vec4(max(_12544.xyz, vec3(0.0)) * _12532, _12532)) + vec4(max(_13003.xyz, vec3(0.0)) * _12991, _12991)) + vec4(max(texture(irradiance_field, clamp((_13623 + vec2(1.0)) + (clamp((_24627 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13623 + vec2(0.5), _13623 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _13450, _13450);
            highp float _10017 = _10015.w;
            highp vec3 _24629 = vec3(0.0);
            if (_10017 > 9.9999999747524270787835121154785e-07)
            {
                _24629 = _10015.xyz / vec3(_10017);
            }
            else
            {
                _24629 = vec3(0.0);
            }
            _24747 = mix(_8331, _24629 * _9844, vec3(_24556));
        }
        else
        {
            _24747 = _8331;
        }
        vec2 _8357 = clamp(vec2(_8269, _24529), vec2(0.0), vec2(0.9900000095367431640625));
        vec4 _8359 = texture(brdf_lut, vec2(_8357.x * 0.3333333432674407958984375, _8357.y));
        float _8363 = _8359.x;
        float _8366 = _8359.y;
        vec3 _8368 = ((_8261 + ((max(vec3(1.0 - _24529), _8261) - _8261) * pow(clamp(1.0 - _8269, 0.0, 1.0), 5.0))) * _8363) + vec3(_8366);
        float _8374 = 1.0 - (_8363 + _8366);
        vec3 _8378 = vec3(1.0) - _8261;
        vec3 _8381 = _8261 + (_8378 * vec3(0.0476190485060214996337890625));
        vec3 _8392 = ((_8368 * _8374) * _8381) / (vec3(1.0) - (_8381 * _8374));
        float _8395 = 1.0 - _7279;
        vec3 _8396 = _8166 * _8395;
        float _25485 = 0.0;
        if ((frag_info.ssao_params.y > 1.5) && _8289)
        {
            float _13731 = max(acos(clamp(exp2(((-3.321929931640625) * _24529) * _24529), 0.0, 1.0)), 0.100000001490116119384765625);
            _25485 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_24544, _8273), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _24817, 0.0, 1.0)))) + _13731) / (2.0 * _13731), 0.0, 1.0));
        }
        else
        {
            float _25486 = 0.0;
            if (frag_info.ssao_params.y > 0.5)
            {
                _25486 = clamp((pow(_8265 + _24817, exp2(((-16.0) * _24529) - 1.0)) - 1.0) + _24817, 0.0, 1.0);
            }
            else
            {
                _25486 = _24817;
            }
            _25485 = _25486;
        }
        bool _8445 = frag_info.has_directional_light > 0.5;
        float _24939 = 0.0;
        vec3 _25569 = vec3(0.0);
        if (_8445)
        {
            highp vec3 _8451 = -normalize(frag_info.directional_light_direction.xyz);
            _25569 = _8451;
            _24939 = dot(_7146, _8451);
        }
        else
        {
            _25569 = vec3(0.0);
            _24939 = 0.0;
        }
        float _8458 = clamp(_24939 * 6.666666507720947265625, 0.0, 1.0);
        bool _8467 = false;
        if (_8445)
        {
            _8467 = frag_info.casts_shadow > 0.5;
        }
        else
        {
            _8467 = _8445;
        }
        float _25176 = 0.0;
        if (_8467 && (_8458 > 0.0))
        {
            int _13852 = int(frag_info.shadow_cascade_count);
            float _14301 = max(dot(_7146, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
            float _14304 = _14301 * _14301;
            highp vec3 _14324 = v_position + (_7146 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _14304, 0.0)) / _14304, 8.0))));
            highp float _13858 = frag_info.directional_light_color.w * 0.5;
            float _24993 = 0.0;
            float _25033 = 0.0;
            if (_13852 > 0)
            {
                highp vec4 _13875 = frag_info.light_space_matrix[0] * vec4(_14324, 1.0);
                highp vec3 _13881 = _13875.xyz / vec3(_13875.w);
                highp vec2 _13884 = _13881.xy * 0.5;
                highp vec2 _13886 = _13884 + vec2(0.5);
                highp float _13893 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
                highp float _13895 = _13886.x;
                bool _13897 = _13895 < _13893;
                bool _13906 = false;
                if (!_13897)
                {
                    _13906 = _13895 > (1.0 - _13893);
                }
                else
                {
                    _13906 = _13897;
                }
                bool _13914 = false;
                if (!_13906)
                {
                    _13914 = _13886.y < _13893;
                }
                else
                {
                    _13914 = _13906;
                }
                bool _13923 = false;
                if (!_13914)
                {
                    _13923 = _13886.y > (1.0 - _13893);
                }
                else
                {
                    _13923 = _13914;
                }
                bool _13930 = false;
                if (!_13923)
                {
                    _13930 = _13881.z < 0.0;
                }
                else
                {
                    _13930 = _13923;
                }
                bool _13937 = false;
                if (!_13930)
                {
                    _13937 = _13881.z > 1.0;
                }
                else
                {
                    _13937 = _13930;
                }
                float _24994 = 0.0;
                float _25034 = 0.0;
                if (!_13937)
                {
                    highp vec2 _14332 = vec2(_13893);
                    highp vec2 _14337 = vec2(_13893 + max(_13858, 9.9999997473787516355514526367188e-05));
                    highp vec2 _14345 = vec2(0.5) - _13884;
                    highp vec2 _14347 = smoothstep(_14332, _14337, _13886) * smoothstep(_14332, _14337, _14345);
                    float _24940 = 0.0;
                    if (_13858 > 0.0)
                    {
                        _24940 = _14347.x * _14347.y;
                    }
                    else
                    {
                        _24940 = 1.0;
                    }
                    float _13946 = min(_24940, 1.0);
                    bool _13948 = _13946 > 0.0;
                    float _25035 = 0.0;
                    if (_13948)
                    {
                        highp float _14459 = _13881.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                        highp float _14465 = 1.0 / (float(_13852) + frag_info.spot_shadow_params.x);
                        highp float _14467 = frag_info.directional_light_direction.w;
                        float mp_copy_14467 = _14467;
                        float _14473 = step(0.5, mp_copy_14467) * (1.0 - step(1.5, mp_copy_14467));
                        highp float _14484 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14473);
                        float mp_copy_14484 = _14484;
                        float _14486 = cos(mp_copy_14484);
                        float _14488 = sin(mp_copy_14484);
                        highp float _24958 = 0.0;
                        if ((_14467 > 1.5) && (_14467 < 2.5))
                        {
                            highp float _14507 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _14512 = max(_14507 * _14459, frag_info.shadow_texel_size);
                            float _24948 = 0.0;
                            highp float _24949 = 0.0;
                            _24949 = 0.0;
                            _24948 = 0.0;
                            highp float _14534 = 0.0;
                            float _14537 = 0.0;
                            for (int _24947 = 0; _24947 < 9; _24949 = _14534, _24948 = _14537, _24947++)
                            {
                                vec2 _27551 = vec2(0.0);
                                do
                                {
                                    if (_24947 == 0)
                                    {
                                        _27551 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_24947 == 1)
                                    {
                                        _27551 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_24947 == 2)
                                    {
                                        _27551 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_24947 == 3)
                                    {
                                        _27551 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_24947 == 4)
                                    {
                                        _27551 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_24947 == 5)
                                    {
                                        _27551 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_24947 == 6)
                                    {
                                        _27551 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_24947 == 7)
                                    {
                                        _27551 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_24947 == 8)
                                    {
                                        _27551 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_24947 == 9)
                                    {
                                        _27551 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_24947 == 10)
                                    {
                                        _27551 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_24947 == 11)
                                    {
                                        _27551 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_24947 == 12)
                                    {
                                        _27551 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_24947 == 13)
                                    {
                                        _27551 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_24947 == 14)
                                    {
                                        _27551 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_24947 == 15)
                                    {
                                        _27551 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27551 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _14779 = clamp(_13886 + (vec2((_27551.x * _14486) - (_27551.y * _14488), (_27551.x * _14488) + (_27551.y * _14486)) * _14512), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _14788 = _14779.y;
                                highp vec2 _14789 = vec2(_14779.x * _14465, _14788);
                                _14789.y = 1.0 - _14788;
                                highp vec4 _14796 = textureLod(shadow_map, _14789, 0.0);
                                highp float _14797 = _14796.x;
                                highp float _14529 = step(_14797, _14459);
                                float mp_copy_14529 = _14529;
                                _14534 = _24949 + (_14797 * _14529);
                                _14537 = _24948 + mp_copy_14529;
                            }
                            highp float _24950 = 0.0;
                            if (_24948 > 0.0)
                            {
                                _24950 = _24949 / _24948;
                            }
                            else
                            {
                                _24950 = _14459;
                            }
                            _24958 = clamp(_14507 * max(_14459 - _24950, 0.0), frag_info.shadow_texel_size, _13893);
                        }
                        else
                        {
                            _24958 = _13893;
                        }
                        float _24965 = 0.0;
                        if (_14467 > 2.5)
                        {
                            highp vec2 _14825 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _14829 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _14830 = clamp(_13886 + (vec2(-0.707099974155426025390625) * _24958), _14825, _14829);
                            highp vec2 _14841 = (vec2(_14830.x, 1.0 - _14830.y) / _14825) - vec2(0.5);
                            highp vec2 _14843 = floor(_14841);
                            highp vec2 _14846 = _14841 - _14843;
                            highp vec2 _14851 = (_14843 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _14861 = vec2(_14851.x * _14465, _14851.y);
                            highp float _14865 = frag_info.shadow_texel_size * _14465;
                            highp vec2 _14868 = vec2(_14865, frag_info.shadow_texel_size);
                            highp vec2 _14877 = vec2(_14865, 0.0);
                            highp vec2 _14885 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _14914 = _14846.x;
                            highp float _14923 = mix(mix(float(_14459 <= textureLod(shadow_map, _14861, 0.0).x), float(_14459 <= textureLod(shadow_map, _14861 + _14877, 0.0).x), _14914), mix(float(_14459 <= textureLod(shadow_map, _14861 + _14885, 0.0).x), float(_14459 <= textureLod(shadow_map, _14861 + _14868, 0.0).x), _14914), _14846.y);
                            float mp_copy_14923 = _14923;
                            highp vec2 _14957 = clamp(_13886 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _24958), _14825, _14829);
                            highp vec2 _14968 = (vec2(_14957.x, 1.0 - _14957.y) / _14825) - vec2(0.5);
                            highp vec2 _14970 = floor(_14968);
                            highp vec2 _14973 = _14968 - _14970;
                            highp vec2 _14978 = (_14970 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _14988 = vec2(_14978.x * _14465, _14978.y);
                            highp float _15041 = _14973.x;
                            highp float _15050 = mix(mix(float(_14459 <= textureLod(shadow_map, _14988, 0.0).x), float(_14459 <= textureLod(shadow_map, _14988 + _14877, 0.0).x), _15041), mix(float(_14459 <= textureLod(shadow_map, _14988 + _14885, 0.0).x), float(_14459 <= textureLod(shadow_map, _14988 + _14868, 0.0).x), _15041), _14973.y);
                            float mp_copy_15050 = _15050;
                            highp vec2 _15084 = clamp(_13886 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _24958), _14825, _14829);
                            highp vec2 _15095 = (vec2(_15084.x, 1.0 - _15084.y) / _14825) - vec2(0.5);
                            highp vec2 _15097 = floor(_15095);
                            highp vec2 _15100 = _15095 - _15097;
                            highp vec2 _15105 = (_15097 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15115 = vec2(_15105.x * _14465, _15105.y);
                            highp float _15168 = _15100.x;
                            highp float _15177 = mix(mix(float(_14459 <= textureLod(shadow_map, _15115, 0.0).x), float(_14459 <= textureLod(shadow_map, _15115 + _14877, 0.0).x), _15168), mix(float(_14459 <= textureLod(shadow_map, _15115 + _14885, 0.0).x), float(_14459 <= textureLod(shadow_map, _15115 + _14868, 0.0).x), _15168), _15100.y);
                            float mp_copy_15177 = _15177;
                            highp vec2 _15211 = clamp(_13886 + (vec2(0.707099974155426025390625) * _24958), _14825, _14829);
                            highp vec2 _15222 = (vec2(_15211.x, 1.0 - _15211.y) / _14825) - vec2(0.5);
                            highp vec2 _15224 = floor(_15222);
                            highp vec2 _15227 = _15222 - _15224;
                            highp vec2 _15232 = (_15224 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15242 = vec2(_15232.x * _14465, _15232.y);
                            highp float _15295 = _15227.x;
                            highp float _15304 = mix(mix(float(_14459 <= textureLod(shadow_map, _15242, 0.0).x), float(_14459 <= textureLod(shadow_map, _15242 + _14877, 0.0).x), _15295), mix(float(_14459 <= textureLod(shadow_map, _15242 + _14885, 0.0).x), float(_14459 <= textureLod(shadow_map, _15242 + _14868, 0.0).x), _15295), _15227.y);
                            float mp_copy_15304 = _15304;
                            _24965 = (((mp_copy_14923 + mp_copy_15050) + mp_copy_15177) + mp_copy_15304) * 0.25;
                        }
                        else
                        {
                            int _14600 = (_14473 > 0.5) ? 17 : 16;
                            float _24961 = 0.0;
                            _24961 = 0.0;
                            float _14628 = 0.0;
                            for (int _24951 = 0; _24951 < 17; _24961 = _14628, _24951++)
                            {
                                if (_24951 >= _14600)
                                {
                                    break;
                                }
                                vec2 _24952 = vec2(0.0);
                                do
                                {
                                    if (_24951 == 0)
                                    {
                                        _24952 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_24951 == 1)
                                    {
                                        _24952 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_24951 == 2)
                                    {
                                        _24952 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_24951 == 3)
                                    {
                                        _24952 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_24951 == 4)
                                    {
                                        _24952 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_24951 == 5)
                                    {
                                        _24952 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_24951 == 6)
                                    {
                                        _24952 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_24951 == 7)
                                    {
                                        _24952 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_24951 == 8)
                                    {
                                        _24952 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_24951 == 9)
                                    {
                                        _24952 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_24951 == 10)
                                    {
                                        _24952 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_24951 == 11)
                                    {
                                        _24952 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_24951 == 12)
                                    {
                                        _24952 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_24951 == 13)
                                    {
                                        _24952 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_24951 == 14)
                                    {
                                        _24952 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_24951 == 15)
                                    {
                                        _24952 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _24952 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _24954 = vec2(0.0);
                                do
                                {
                                    if (_24951 < 3)
                                    {
                                        _24954 = vec2(float(_24951) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_24951 < 6)
                                    {
                                        _24954 = vec2((float(_24951 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_24951 < 11)
                                    {
                                        _24954 = vec2((float(_24951 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_24951 < 14)
                                    {
                                        _24954 = vec2((float(_24951 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _24954 = vec2(float(_24951 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _14617 = mix(_24952, _24954, vec2(_14473));
                                float _15444 = _14617.x;
                                float _15448 = _14617.y;
                                highp vec2 _15474 = clamp(_13886 + (vec2((_15444 * _14486) - (_15448 * _14488), (_15444 * _14488) + (_15448 * _14486)) * _24958), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _15484 = vec2(_15474.x * _14465, _15474.y);
                                _15484.y = 1.0 - _15474.y;
                                highp float _15496 = float(_14459 <= textureLod(shadow_map, _15484, 0.0).x);
                                float mp_copy_15496 = _15496;
                                _14628 = _24961 + mp_copy_15496;
                            }
                            _24965 = _24961 / float(_14600);
                        }
                        bool _14641 = 0 == (_13852 - 1);
                        bool _14647 = false;
                        if (_14641)
                        {
                            _14647 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _14647 = _14641;
                        }
                        float _24966 = 0.0;
                        if (_14647)
                        {
                            highp vec2 _14654 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                            highp vec2 _14662 = smoothstep(vec2(0.0), _14654, _13886) * smoothstep(vec2(0.0), _14654, _14345);
                            _24966 = mix(1.0, _24965, _14662.x * _14662.y);
                        }
                        else
                        {
                            _24966 = _24965;
                        }
                        _25035 = _13946 * _24966;
                    }
                    else
                    {
                        _25035 = 0.0;
                    }
                    _25034 = _25035;
                    _24994 = _13948 ? _13946 : 0.0;
                }
                else
                {
                    _25034 = 0.0;
                    _24994 = 0.0;
                }
                _25033 = _25034;
                _24993 = _24994;
            }
            else
            {
                _25033 = 0.0;
                _24993 = 0.0;
            }
            float _25052 = 0.0;
            float _25092 = 0.0;
            if ((_24993 < 1.0) && (_13852 > 1))
            {
                highp vec4 _13981 = frag_info.light_space_matrix[1] * vec4(_14324, 1.0);
                highp vec3 _13987 = _13981.xyz / vec3(_13981.w);
                highp vec2 _13990 = _13987.xy * 0.5;
                highp vec2 _13992 = _13990 + vec2(0.5);
                highp float _13999 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
                highp float _14001 = _13992.x;
                bool _14003 = _14001 < _13999;
                bool _14012 = false;
                if (!_14003)
                {
                    _14012 = _14001 > (1.0 - _13999);
                }
                else
                {
                    _14012 = _14003;
                }
                bool _14020 = false;
                if (!_14012)
                {
                    _14020 = _13992.y < _13999;
                }
                else
                {
                    _14020 = _14012;
                }
                bool _14029 = false;
                if (!_14020)
                {
                    _14029 = _13992.y > (1.0 - _13999);
                }
                else
                {
                    _14029 = _14020;
                }
                bool _14036 = false;
                if (!_14029)
                {
                    _14036 = _13987.z < 0.0;
                }
                else
                {
                    _14036 = _14029;
                }
                bool _14043 = false;
                if (!_14036)
                {
                    _14043 = _13987.z > 1.0;
                }
                else
                {
                    _14043 = _14036;
                }
                float _25053 = 0.0;
                float _25093 = 0.0;
                if (!_14043)
                {
                    highp vec2 _15504 = vec2(_13999);
                    highp vec2 _15509 = vec2(_13999 + max(_13858, 9.9999997473787516355514526367188e-05));
                    highp vec2 _15517 = vec2(0.5) - _13990;
                    highp vec2 _15519 = smoothstep(_15504, _15509, _13992) * smoothstep(_15504, _15509, _15517);
                    float _24996 = 0.0;
                    if (_13858 > 0.0)
                    {
                        _24996 = _15519.x * _15519.y;
                    }
                    else
                    {
                        _24996 = 1.0;
                    }
                    float _14052 = min(_24996, 1.0 - _24993);
                    float _25054 = 0.0;
                    float _25094 = 0.0;
                    if (_14052 > 0.0)
                    {
                        highp float _15631 = _13987.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                        highp float _15637 = 1.0 / (float(_13852) + frag_info.spot_shadow_params.x);
                        highp float _15639 = frag_info.directional_light_direction.w;
                        float mp_copy_15639 = _15639;
                        float _15645 = step(0.5, mp_copy_15639) * (1.0 - step(1.5, mp_copy_15639));
                        highp float _15656 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _15645);
                        float mp_copy_15656 = _15656;
                        float _15658 = cos(mp_copy_15656);
                        float _15660 = sin(mp_copy_15656);
                        highp float _25014 = 0.0;
                        if ((_15639 > 1.5) && (_15639 < 2.5))
                        {
                            highp float _15679 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _15684 = max(_15679 * _15631, frag_info.shadow_texel_size);
                            float _25004 = 0.0;
                            highp float _25005 = 0.0;
                            _25005 = 0.0;
                            _25004 = 0.0;
                            highp float _15706 = 0.0;
                            float _15709 = 0.0;
                            for (int _25003 = 0; _25003 < 9; _25005 = _15706, _25004 = _15709, _25003++)
                            {
                                vec2 _27547 = vec2(0.0);
                                do
                                {
                                    if (_25003 == 0)
                                    {
                                        _27547 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25003 == 1)
                                    {
                                        _27547 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25003 == 2)
                                    {
                                        _27547 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25003 == 3)
                                    {
                                        _27547 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25003 == 4)
                                    {
                                        _27547 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25003 == 5)
                                    {
                                        _27547 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25003 == 6)
                                    {
                                        _27547 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25003 == 7)
                                    {
                                        _27547 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25003 == 8)
                                    {
                                        _27547 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25003 == 9)
                                    {
                                        _27547 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25003 == 10)
                                    {
                                        _27547 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25003 == 11)
                                    {
                                        _27547 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25003 == 12)
                                    {
                                        _27547 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25003 == 13)
                                    {
                                        _27547 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25003 == 14)
                                    {
                                        _27547 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25003 == 15)
                                    {
                                        _27547 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27547 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _15951 = clamp(_13992 + (vec2((_27547.x * _15658) - (_27547.y * _15660), (_27547.x * _15660) + (_27547.y * _15658)) * _15684), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _15960 = _15951.y;
                                highp vec2 _15961 = vec2((1.0 + _15951.x) * _15637, _15960);
                                _15961.y = 1.0 - _15960;
                                highp vec4 _15968 = textureLod(shadow_map, _15961, 0.0);
                                highp float _15969 = _15968.x;
                                highp float _15701 = step(_15969, _15631);
                                float mp_copy_15701 = _15701;
                                _15706 = _25005 + (_15969 * _15701);
                                _15709 = _25004 + mp_copy_15701;
                            }
                            highp float _25006 = 0.0;
                            if (_25004 > 0.0)
                            {
                                _25006 = _25005 / _25004;
                            }
                            else
                            {
                                _25006 = _15631;
                            }
                            _25014 = clamp(_15679 * max(_15631 - _25006, 0.0), frag_info.shadow_texel_size, _13999);
                        }
                        else
                        {
                            _25014 = _13999;
                        }
                        float _25021 = 0.0;
                        if (_15639 > 2.5)
                        {
                            highp vec2 _15997 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _16001 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _16002 = clamp(_13992 + (vec2(-0.707099974155426025390625) * _25014), _15997, _16001);
                            highp vec2 _16013 = (vec2(_16002.x, 1.0 - _16002.y) / _15997) - vec2(0.5);
                            highp vec2 _16015 = floor(_16013);
                            highp vec2 _16018 = _16013 - _16015;
                            highp vec2 _16023 = (_16015 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16033 = vec2((1.0 + _16023.x) * _15637, _16023.y);
                            highp float _16037 = frag_info.shadow_texel_size * _15637;
                            highp vec2 _16040 = vec2(_16037, frag_info.shadow_texel_size);
                            highp vec2 _16049 = vec2(_16037, 0.0);
                            highp vec2 _16057 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _16086 = _16018.x;
                            highp float _16095 = mix(mix(float(_15631 <= textureLod(shadow_map, _16033, 0.0).x), float(_15631 <= textureLod(shadow_map, _16033 + _16049, 0.0).x), _16086), mix(float(_15631 <= textureLod(shadow_map, _16033 + _16057, 0.0).x), float(_15631 <= textureLod(shadow_map, _16033 + _16040, 0.0).x), _16086), _16018.y);
                            float mp_copy_16095 = _16095;
                            highp vec2 _16129 = clamp(_13992 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25014), _15997, _16001);
                            highp vec2 _16140 = (vec2(_16129.x, 1.0 - _16129.y) / _15997) - vec2(0.5);
                            highp vec2 _16142 = floor(_16140);
                            highp vec2 _16145 = _16140 - _16142;
                            highp vec2 _16150 = (_16142 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16160 = vec2((1.0 + _16150.x) * _15637, _16150.y);
                            highp float _16213 = _16145.x;
                            highp float _16222 = mix(mix(float(_15631 <= textureLod(shadow_map, _16160, 0.0).x), float(_15631 <= textureLod(shadow_map, _16160 + _16049, 0.0).x), _16213), mix(float(_15631 <= textureLod(shadow_map, _16160 + _16057, 0.0).x), float(_15631 <= textureLod(shadow_map, _16160 + _16040, 0.0).x), _16213), _16145.y);
                            float mp_copy_16222 = _16222;
                            highp vec2 _16256 = clamp(_13992 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25014), _15997, _16001);
                            highp vec2 _16267 = (vec2(_16256.x, 1.0 - _16256.y) / _15997) - vec2(0.5);
                            highp vec2 _16269 = floor(_16267);
                            highp vec2 _16272 = _16267 - _16269;
                            highp vec2 _16277 = (_16269 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16287 = vec2((1.0 + _16277.x) * _15637, _16277.y);
                            highp float _16340 = _16272.x;
                            highp float _16349 = mix(mix(float(_15631 <= textureLod(shadow_map, _16287, 0.0).x), float(_15631 <= textureLod(shadow_map, _16287 + _16049, 0.0).x), _16340), mix(float(_15631 <= textureLod(shadow_map, _16287 + _16057, 0.0).x), float(_15631 <= textureLod(shadow_map, _16287 + _16040, 0.0).x), _16340), _16272.y);
                            float mp_copy_16349 = _16349;
                            highp vec2 _16383 = clamp(_13992 + (vec2(0.707099974155426025390625) * _25014), _15997, _16001);
                            highp vec2 _16394 = (vec2(_16383.x, 1.0 - _16383.y) / _15997) - vec2(0.5);
                            highp vec2 _16396 = floor(_16394);
                            highp vec2 _16399 = _16394 - _16396;
                            highp vec2 _16404 = (_16396 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16414 = vec2((1.0 + _16404.x) * _15637, _16404.y);
                            highp float _16467 = _16399.x;
                            highp float _16476 = mix(mix(float(_15631 <= textureLod(shadow_map, _16414, 0.0).x), float(_15631 <= textureLod(shadow_map, _16414 + _16049, 0.0).x), _16467), mix(float(_15631 <= textureLod(shadow_map, _16414 + _16057, 0.0).x), float(_15631 <= textureLod(shadow_map, _16414 + _16040, 0.0).x), _16467), _16399.y);
                            float mp_copy_16476 = _16476;
                            _25021 = (((mp_copy_16095 + mp_copy_16222) + mp_copy_16349) + mp_copy_16476) * 0.25;
                        }
                        else
                        {
                            int _15772 = (_15645 > 0.5) ? 17 : 16;
                            float _25017 = 0.0;
                            _25017 = 0.0;
                            float _15800 = 0.0;
                            for (int _25007 = 0; _25007 < 17; _25017 = _15800, _25007++)
                            {
                                if (_25007 >= _15772)
                                {
                                    break;
                                }
                                vec2 _25008 = vec2(0.0);
                                do
                                {
                                    if (_25007 == 0)
                                    {
                                        _25008 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25007 == 1)
                                    {
                                        _25008 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25007 == 2)
                                    {
                                        _25008 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25007 == 3)
                                    {
                                        _25008 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25007 == 4)
                                    {
                                        _25008 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25007 == 5)
                                    {
                                        _25008 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25007 == 6)
                                    {
                                        _25008 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25007 == 7)
                                    {
                                        _25008 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25007 == 8)
                                    {
                                        _25008 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25007 == 9)
                                    {
                                        _25008 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25007 == 10)
                                    {
                                        _25008 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25007 == 11)
                                    {
                                        _25008 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25007 == 12)
                                    {
                                        _25008 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25007 == 13)
                                    {
                                        _25008 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25007 == 14)
                                    {
                                        _25008 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25007 == 15)
                                    {
                                        _25008 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25008 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25010 = vec2(0.0);
                                do
                                {
                                    if (_25007 < 3)
                                    {
                                        _25010 = vec2(float(_25007) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25007 < 6)
                                    {
                                        _25010 = vec2((float(_25007 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25007 < 11)
                                    {
                                        _25010 = vec2((float(_25007 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25007 < 14)
                                    {
                                        _25010 = vec2((float(_25007 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25010 = vec2(float(_25007 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _15789 = mix(_25008, _25010, vec2(_15645));
                                float _16616 = _15789.x;
                                float _16620 = _15789.y;
                                highp vec2 _16646 = clamp(_13992 + (vec2((_16616 * _15658) - (_16620 * _15660), (_16616 * _15660) + (_16620 * _15658)) * _25014), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _16656 = vec2((1.0 + _16646.x) * _15637, _16646.y);
                                _16656.y = 1.0 - _16646.y;
                                highp float _16668 = float(_15631 <= textureLod(shadow_map, _16656, 0.0).x);
                                float mp_copy_16668 = _16668;
                                _15800 = _25017 + mp_copy_16668;
                            }
                            _25021 = _25017 / float(_15772);
                        }
                        bool _15813 = 1 == (_13852 - 1);
                        bool _15819 = false;
                        if (_15813)
                        {
                            _15819 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _15819 = _15813;
                        }
                        float _25022 = 0.0;
                        if (_15819)
                        {
                            highp vec2 _15826 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                            highp vec2 _15834 = smoothstep(vec2(0.0), _15826, _13992) * smoothstep(vec2(0.0), _15826, _15517);
                            _25022 = mix(1.0, _25021, _15834.x * _15834.y);
                        }
                        else
                        {
                            _25022 = _25021;
                        }
                        _25094 = _25033 + (_14052 * _25022);
                        _25054 = _24993 + _14052;
                    }
                    else
                    {
                        _25094 = _25033;
                        _25054 = _24993;
                    }
                    _25093 = _25094;
                    _25053 = _25054;
                }
                else
                {
                    _25093 = _25033;
                    _25053 = _24993;
                }
                _25092 = _25093;
                _25052 = _25053;
            }
            else
            {
                _25092 = _25033;
                _25052 = _24993;
            }
            float _25111 = 0.0;
            float _25151 = 0.0;
            if ((_25052 < 1.0) && (_13852 > 2))
            {
                highp vec4 _14087 = frag_info.light_space_matrix[2] * vec4(_14324, 1.0);
                highp vec3 _14093 = _14087.xyz / vec3(_14087.w);
                highp vec2 _14096 = _14093.xy * 0.5;
                highp vec2 _14098 = _14096 + vec2(0.5);
                highp float _14105 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
                highp float _14107 = _14098.x;
                bool _14109 = _14107 < _14105;
                bool _14118 = false;
                if (!_14109)
                {
                    _14118 = _14107 > (1.0 - _14105);
                }
                else
                {
                    _14118 = _14109;
                }
                bool _14126 = false;
                if (!_14118)
                {
                    _14126 = _14098.y < _14105;
                }
                else
                {
                    _14126 = _14118;
                }
                bool _14135 = false;
                if (!_14126)
                {
                    _14135 = _14098.y > (1.0 - _14105);
                }
                else
                {
                    _14135 = _14126;
                }
                bool _14142 = false;
                if (!_14135)
                {
                    _14142 = _14093.z < 0.0;
                }
                else
                {
                    _14142 = _14135;
                }
                bool _14149 = false;
                if (!_14142)
                {
                    _14149 = _14093.z > 1.0;
                }
                else
                {
                    _14149 = _14142;
                }
                float _25112 = 0.0;
                float _25152 = 0.0;
                if (!_14149)
                {
                    highp vec2 _16676 = vec2(_14105);
                    highp vec2 _16681 = vec2(_14105 + max(_13858, 9.9999997473787516355514526367188e-05));
                    highp vec2 _16689 = vec2(0.5) - _14096;
                    highp vec2 _16691 = smoothstep(_16676, _16681, _14098) * smoothstep(_16676, _16681, _16689);
                    float _25055 = 0.0;
                    if (_13858 > 0.0)
                    {
                        _25055 = _16691.x * _16691.y;
                    }
                    else
                    {
                        _25055 = 1.0;
                    }
                    float _14158 = min(_25055, 1.0 - _25052);
                    float _25113 = 0.0;
                    float _25153 = 0.0;
                    if (_14158 > 0.0)
                    {
                        highp float _16803 = _14093.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                        highp float _16809 = 1.0 / (float(_13852) + frag_info.spot_shadow_params.x);
                        highp float _16811 = frag_info.directional_light_direction.w;
                        float mp_copy_16811 = _16811;
                        float _16817 = step(0.5, mp_copy_16811) * (1.0 - step(1.5, mp_copy_16811));
                        highp float _16828 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16817);
                        float mp_copy_16828 = _16828;
                        float _16830 = cos(mp_copy_16828);
                        float _16832 = sin(mp_copy_16828);
                        highp float _25073 = 0.0;
                        if ((_16811 > 1.5) && (_16811 < 2.5))
                        {
                            highp float _16851 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _16856 = max(_16851 * _16803, frag_info.shadow_texel_size);
                            float _25063 = 0.0;
                            highp float _25064 = 0.0;
                            _25064 = 0.0;
                            _25063 = 0.0;
                            highp float _16878 = 0.0;
                            float _16881 = 0.0;
                            for (int _25062 = 0; _25062 < 9; _25064 = _16878, _25063 = _16881, _25062++)
                            {
                                vec2 _27543 = vec2(0.0);
                                do
                                {
                                    if (_25062 == 0)
                                    {
                                        _27543 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25062 == 1)
                                    {
                                        _27543 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25062 == 2)
                                    {
                                        _27543 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25062 == 3)
                                    {
                                        _27543 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25062 == 4)
                                    {
                                        _27543 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25062 == 5)
                                    {
                                        _27543 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25062 == 6)
                                    {
                                        _27543 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25062 == 7)
                                    {
                                        _27543 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25062 == 8)
                                    {
                                        _27543 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25062 == 9)
                                    {
                                        _27543 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25062 == 10)
                                    {
                                        _27543 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25062 == 11)
                                    {
                                        _27543 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25062 == 12)
                                    {
                                        _27543 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25062 == 13)
                                    {
                                        _27543 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25062 == 14)
                                    {
                                        _27543 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25062 == 15)
                                    {
                                        _27543 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27543 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _17123 = clamp(_14098 + (vec2((_27543.x * _16830) - (_27543.y * _16832), (_27543.x * _16832) + (_27543.y * _16830)) * _16856), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _17132 = _17123.y;
                                highp vec2 _17133 = vec2((2.0 + _17123.x) * _16809, _17132);
                                _17133.y = 1.0 - _17132;
                                highp vec4 _17140 = textureLod(shadow_map, _17133, 0.0);
                                highp float _17141 = _17140.x;
                                highp float _16873 = step(_17141, _16803);
                                float mp_copy_16873 = _16873;
                                _16878 = _25064 + (_17141 * _16873);
                                _16881 = _25063 + mp_copy_16873;
                            }
                            highp float _25065 = 0.0;
                            if (_25063 > 0.0)
                            {
                                _25065 = _25064 / _25063;
                            }
                            else
                            {
                                _25065 = _16803;
                            }
                            _25073 = clamp(_16851 * max(_16803 - _25065, 0.0), frag_info.shadow_texel_size, _14105);
                        }
                        else
                        {
                            _25073 = _14105;
                        }
                        float _25080 = 0.0;
                        if (_16811 > 2.5)
                        {
                            highp vec2 _17169 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _17173 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _17174 = clamp(_14098 + (vec2(-0.707099974155426025390625) * _25073), _17169, _17173);
                            highp vec2 _17185 = (vec2(_17174.x, 1.0 - _17174.y) / _17169) - vec2(0.5);
                            highp vec2 _17187 = floor(_17185);
                            highp vec2 _17190 = _17185 - _17187;
                            highp vec2 _17195 = (_17187 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17205 = vec2((2.0 + _17195.x) * _16809, _17195.y);
                            highp float _17209 = frag_info.shadow_texel_size * _16809;
                            highp vec2 _17212 = vec2(_17209, frag_info.shadow_texel_size);
                            highp vec2 _17221 = vec2(_17209, 0.0);
                            highp vec2 _17229 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _17258 = _17190.x;
                            highp float _17267 = mix(mix(float(_16803 <= textureLod(shadow_map, _17205, 0.0).x), float(_16803 <= textureLod(shadow_map, _17205 + _17221, 0.0).x), _17258), mix(float(_16803 <= textureLod(shadow_map, _17205 + _17229, 0.0).x), float(_16803 <= textureLod(shadow_map, _17205 + _17212, 0.0).x), _17258), _17190.y);
                            float mp_copy_17267 = _17267;
                            highp vec2 _17301 = clamp(_14098 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25073), _17169, _17173);
                            highp vec2 _17312 = (vec2(_17301.x, 1.0 - _17301.y) / _17169) - vec2(0.5);
                            highp vec2 _17314 = floor(_17312);
                            highp vec2 _17317 = _17312 - _17314;
                            highp vec2 _17322 = (_17314 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17332 = vec2((2.0 + _17322.x) * _16809, _17322.y);
                            highp float _17385 = _17317.x;
                            highp float _17394 = mix(mix(float(_16803 <= textureLod(shadow_map, _17332, 0.0).x), float(_16803 <= textureLod(shadow_map, _17332 + _17221, 0.0).x), _17385), mix(float(_16803 <= textureLod(shadow_map, _17332 + _17229, 0.0).x), float(_16803 <= textureLod(shadow_map, _17332 + _17212, 0.0).x), _17385), _17317.y);
                            float mp_copy_17394 = _17394;
                            highp vec2 _17428 = clamp(_14098 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25073), _17169, _17173);
                            highp vec2 _17439 = (vec2(_17428.x, 1.0 - _17428.y) / _17169) - vec2(0.5);
                            highp vec2 _17441 = floor(_17439);
                            highp vec2 _17444 = _17439 - _17441;
                            highp vec2 _17449 = (_17441 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17459 = vec2((2.0 + _17449.x) * _16809, _17449.y);
                            highp float _17512 = _17444.x;
                            highp float _17521 = mix(mix(float(_16803 <= textureLod(shadow_map, _17459, 0.0).x), float(_16803 <= textureLod(shadow_map, _17459 + _17221, 0.0).x), _17512), mix(float(_16803 <= textureLod(shadow_map, _17459 + _17229, 0.0).x), float(_16803 <= textureLod(shadow_map, _17459 + _17212, 0.0).x), _17512), _17444.y);
                            float mp_copy_17521 = _17521;
                            highp vec2 _17555 = clamp(_14098 + (vec2(0.707099974155426025390625) * _25073), _17169, _17173);
                            highp vec2 _17566 = (vec2(_17555.x, 1.0 - _17555.y) / _17169) - vec2(0.5);
                            highp vec2 _17568 = floor(_17566);
                            highp vec2 _17571 = _17566 - _17568;
                            highp vec2 _17576 = (_17568 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17586 = vec2((2.0 + _17576.x) * _16809, _17576.y);
                            highp float _17639 = _17571.x;
                            highp float _17648 = mix(mix(float(_16803 <= textureLod(shadow_map, _17586, 0.0).x), float(_16803 <= textureLod(shadow_map, _17586 + _17221, 0.0).x), _17639), mix(float(_16803 <= textureLod(shadow_map, _17586 + _17229, 0.0).x), float(_16803 <= textureLod(shadow_map, _17586 + _17212, 0.0).x), _17639), _17571.y);
                            float mp_copy_17648 = _17648;
                            _25080 = (((mp_copy_17267 + mp_copy_17394) + mp_copy_17521) + mp_copy_17648) * 0.25;
                        }
                        else
                        {
                            int _16944 = (_16817 > 0.5) ? 17 : 16;
                            float _25076 = 0.0;
                            _25076 = 0.0;
                            float _16972 = 0.0;
                            for (int _25066 = 0; _25066 < 17; _25076 = _16972, _25066++)
                            {
                                if (_25066 >= _16944)
                                {
                                    break;
                                }
                                vec2 _25067 = vec2(0.0);
                                do
                                {
                                    if (_25066 == 0)
                                    {
                                        _25067 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25066 == 1)
                                    {
                                        _25067 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25066 == 2)
                                    {
                                        _25067 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25066 == 3)
                                    {
                                        _25067 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25066 == 4)
                                    {
                                        _25067 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25066 == 5)
                                    {
                                        _25067 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25066 == 6)
                                    {
                                        _25067 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25066 == 7)
                                    {
                                        _25067 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25066 == 8)
                                    {
                                        _25067 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25066 == 9)
                                    {
                                        _25067 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25066 == 10)
                                    {
                                        _25067 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25066 == 11)
                                    {
                                        _25067 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25066 == 12)
                                    {
                                        _25067 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25066 == 13)
                                    {
                                        _25067 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25066 == 14)
                                    {
                                        _25067 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25066 == 15)
                                    {
                                        _25067 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25067 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25069 = vec2(0.0);
                                do
                                {
                                    if (_25066 < 3)
                                    {
                                        _25069 = vec2(float(_25066) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25066 < 6)
                                    {
                                        _25069 = vec2((float(_25066 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25066 < 11)
                                    {
                                        _25069 = vec2((float(_25066 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25066 < 14)
                                    {
                                        _25069 = vec2((float(_25066 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25069 = vec2(float(_25066 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _16961 = mix(_25067, _25069, vec2(_16817));
                                float _17788 = _16961.x;
                                float _17792 = _16961.y;
                                highp vec2 _17818 = clamp(_14098 + (vec2((_17788 * _16830) - (_17792 * _16832), (_17788 * _16832) + (_17792 * _16830)) * _25073), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _17828 = vec2((2.0 + _17818.x) * _16809, _17818.y);
                                _17828.y = 1.0 - _17818.y;
                                highp float _17840 = float(_16803 <= textureLod(shadow_map, _17828, 0.0).x);
                                float mp_copy_17840 = _17840;
                                _16972 = _25076 + mp_copy_17840;
                            }
                            _25080 = _25076 / float(_16944);
                        }
                        bool _16985 = 2 == (_13852 - 1);
                        bool _16991 = false;
                        if (_16985)
                        {
                            _16991 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _16991 = _16985;
                        }
                        float _25081 = 0.0;
                        if (_16991)
                        {
                            highp vec2 _16998 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                            highp vec2 _17006 = smoothstep(vec2(0.0), _16998, _14098) * smoothstep(vec2(0.0), _16998, _16689);
                            _25081 = mix(1.0, _25080, _17006.x * _17006.y);
                        }
                        else
                        {
                            _25081 = _25080;
                        }
                        _25153 = _25092 + (_14158 * _25081);
                        _25113 = _25052 + _14158;
                    }
                    else
                    {
                        _25153 = _25092;
                        _25113 = _25052;
                    }
                    _25152 = _25153;
                    _25112 = _25113;
                }
                else
                {
                    _25152 = _25092;
                    _25112 = _25052;
                }
                _25151 = _25152;
                _25111 = _25112;
            }
            else
            {
                _25151 = _25092;
                _25111 = _25052;
            }
            float _25170 = 0.0;
            float _25173 = 0.0;
            if ((_25111 < 1.0) && (_13852 > 3))
            {
                highp vec4 _14193 = frag_info.light_space_matrix[3] * vec4(_14324, 1.0);
                highp vec3 _14199 = _14193.xyz / vec3(_14193.w);
                highp vec2 _14202 = _14199.xy * 0.5;
                highp vec2 _14204 = _14202 + vec2(0.5);
                highp float _14211 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
                highp float _14213 = _14204.x;
                bool _14215 = _14213 < _14211;
                bool _14224 = false;
                if (!_14215)
                {
                    _14224 = _14213 > (1.0 - _14211);
                }
                else
                {
                    _14224 = _14215;
                }
                bool _14232 = false;
                if (!_14224)
                {
                    _14232 = _14204.y < _14211;
                }
                else
                {
                    _14232 = _14224;
                }
                bool _14241 = false;
                if (!_14232)
                {
                    _14241 = _14204.y > (1.0 - _14211);
                }
                else
                {
                    _14241 = _14232;
                }
                bool _14248 = false;
                if (!_14241)
                {
                    _14248 = _14199.z < 0.0;
                }
                else
                {
                    _14248 = _14241;
                }
                bool _14255 = false;
                if (!_14248)
                {
                    _14255 = _14199.z > 1.0;
                }
                else
                {
                    _14255 = _14248;
                }
                float _25171 = 0.0;
                float _25174 = 0.0;
                if (!_14255)
                {
                    highp vec2 _17848 = vec2(_14211);
                    highp vec2 _17853 = vec2(_14211 + max(_13858, 9.9999997473787516355514526367188e-05));
                    highp vec2 _17861 = vec2(0.5) - _14202;
                    highp vec2 _17863 = smoothstep(_17848, _17853, _14204) * smoothstep(_17848, _17853, _17861);
                    float _25114 = 0.0;
                    if (_13858 > 0.0)
                    {
                        _25114 = _17863.x * _17863.y;
                    }
                    else
                    {
                        _25114 = 1.0;
                    }
                    float _14264 = min(_25114, 1.0 - _25111);
                    float _25172 = 0.0;
                    float _25175 = 0.0;
                    if (_14264 > 0.0)
                    {
                        highp float _17975 = _14199.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                        highp float _17981 = 1.0 / (float(_13852) + frag_info.spot_shadow_params.x);
                        highp float _17983 = frag_info.directional_light_direction.w;
                        float mp_copy_17983 = _17983;
                        float _17989 = step(0.5, mp_copy_17983) * (1.0 - step(1.5, mp_copy_17983));
                        highp float _18000 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _17989);
                        float mp_copy_18000 = _18000;
                        float _18002 = cos(mp_copy_18000);
                        float _18004 = sin(mp_copy_18000);
                        highp float _25132 = 0.0;
                        if ((_17983 > 1.5) && (_17983 < 2.5))
                        {
                            highp float _18023 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _18028 = max(_18023 * _17975, frag_info.shadow_texel_size);
                            float _25122 = 0.0;
                            highp float _25123 = 0.0;
                            _25123 = 0.0;
                            _25122 = 0.0;
                            highp float _18050 = 0.0;
                            float _18053 = 0.0;
                            for (int _25121 = 0; _25121 < 9; _25123 = _18050, _25122 = _18053, _25121++)
                            {
                                vec2 _27539 = vec2(0.0);
                                do
                                {
                                    if (_25121 == 0)
                                    {
                                        _27539 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25121 == 1)
                                    {
                                        _27539 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25121 == 2)
                                    {
                                        _27539 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25121 == 3)
                                    {
                                        _27539 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25121 == 4)
                                    {
                                        _27539 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25121 == 5)
                                    {
                                        _27539 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25121 == 6)
                                    {
                                        _27539 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25121 == 7)
                                    {
                                        _27539 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25121 == 8)
                                    {
                                        _27539 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25121 == 9)
                                    {
                                        _27539 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25121 == 10)
                                    {
                                        _27539 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25121 == 11)
                                    {
                                        _27539 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25121 == 12)
                                    {
                                        _27539 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25121 == 13)
                                    {
                                        _27539 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25121 == 14)
                                    {
                                        _27539 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25121 == 15)
                                    {
                                        _27539 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27539 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _18295 = clamp(_14204 + (vec2((_27539.x * _18002) - (_27539.y * _18004), (_27539.x * _18004) + (_27539.y * _18002)) * _18028), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _18304 = _18295.y;
                                highp vec2 _18305 = vec2((3.0 + _18295.x) * _17981, _18304);
                                _18305.y = 1.0 - _18304;
                                highp vec4 _18312 = textureLod(shadow_map, _18305, 0.0);
                                highp float _18313 = _18312.x;
                                highp float _18045 = step(_18313, _17975);
                                float mp_copy_18045 = _18045;
                                _18050 = _25123 + (_18313 * _18045);
                                _18053 = _25122 + mp_copy_18045;
                            }
                            highp float _25124 = 0.0;
                            if (_25122 > 0.0)
                            {
                                _25124 = _25123 / _25122;
                            }
                            else
                            {
                                _25124 = _17975;
                            }
                            _25132 = clamp(_18023 * max(_17975 - _25124, 0.0), frag_info.shadow_texel_size, _14211);
                        }
                        else
                        {
                            _25132 = _14211;
                        }
                        float _25139 = 0.0;
                        if (_17983 > 2.5)
                        {
                            highp vec2 _18341 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _18345 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _18346 = clamp(_14204 + (vec2(-0.707099974155426025390625) * _25132), _18341, _18345);
                            highp vec2 _18357 = (vec2(_18346.x, 1.0 - _18346.y) / _18341) - vec2(0.5);
                            highp vec2 _18359 = floor(_18357);
                            highp vec2 _18362 = _18357 - _18359;
                            highp vec2 _18367 = (_18359 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18377 = vec2((3.0 + _18367.x) * _17981, _18367.y);
                            highp float _18381 = frag_info.shadow_texel_size * _17981;
                            highp vec2 _18384 = vec2(_18381, frag_info.shadow_texel_size);
                            highp vec2 _18393 = vec2(_18381, 0.0);
                            highp vec2 _18401 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _18430 = _18362.x;
                            highp float _18439 = mix(mix(float(_17975 <= textureLod(shadow_map, _18377, 0.0).x), float(_17975 <= textureLod(shadow_map, _18377 + _18393, 0.0).x), _18430), mix(float(_17975 <= textureLod(shadow_map, _18377 + _18401, 0.0).x), float(_17975 <= textureLod(shadow_map, _18377 + _18384, 0.0).x), _18430), _18362.y);
                            float mp_copy_18439 = _18439;
                            highp vec2 _18473 = clamp(_14204 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25132), _18341, _18345);
                            highp vec2 _18484 = (vec2(_18473.x, 1.0 - _18473.y) / _18341) - vec2(0.5);
                            highp vec2 _18486 = floor(_18484);
                            highp vec2 _18489 = _18484 - _18486;
                            highp vec2 _18494 = (_18486 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18504 = vec2((3.0 + _18494.x) * _17981, _18494.y);
                            highp float _18557 = _18489.x;
                            highp float _18566 = mix(mix(float(_17975 <= textureLod(shadow_map, _18504, 0.0).x), float(_17975 <= textureLod(shadow_map, _18504 + _18393, 0.0).x), _18557), mix(float(_17975 <= textureLod(shadow_map, _18504 + _18401, 0.0).x), float(_17975 <= textureLod(shadow_map, _18504 + _18384, 0.0).x), _18557), _18489.y);
                            float mp_copy_18566 = _18566;
                            highp vec2 _18600 = clamp(_14204 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25132), _18341, _18345);
                            highp vec2 _18611 = (vec2(_18600.x, 1.0 - _18600.y) / _18341) - vec2(0.5);
                            highp vec2 _18613 = floor(_18611);
                            highp vec2 _18616 = _18611 - _18613;
                            highp vec2 _18621 = (_18613 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18631 = vec2((3.0 + _18621.x) * _17981, _18621.y);
                            highp float _18684 = _18616.x;
                            highp float _18693 = mix(mix(float(_17975 <= textureLod(shadow_map, _18631, 0.0).x), float(_17975 <= textureLod(shadow_map, _18631 + _18393, 0.0).x), _18684), mix(float(_17975 <= textureLod(shadow_map, _18631 + _18401, 0.0).x), float(_17975 <= textureLod(shadow_map, _18631 + _18384, 0.0).x), _18684), _18616.y);
                            float mp_copy_18693 = _18693;
                            highp vec2 _18727 = clamp(_14204 + (vec2(0.707099974155426025390625) * _25132), _18341, _18345);
                            highp vec2 _18738 = (vec2(_18727.x, 1.0 - _18727.y) / _18341) - vec2(0.5);
                            highp vec2 _18740 = floor(_18738);
                            highp vec2 _18743 = _18738 - _18740;
                            highp vec2 _18748 = (_18740 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18758 = vec2((3.0 + _18748.x) * _17981, _18748.y);
                            highp float _18811 = _18743.x;
                            highp float _18820 = mix(mix(float(_17975 <= textureLod(shadow_map, _18758, 0.0).x), float(_17975 <= textureLod(shadow_map, _18758 + _18393, 0.0).x), _18811), mix(float(_17975 <= textureLod(shadow_map, _18758 + _18401, 0.0).x), float(_17975 <= textureLod(shadow_map, _18758 + _18384, 0.0).x), _18811), _18743.y);
                            float mp_copy_18820 = _18820;
                            _25139 = (((mp_copy_18439 + mp_copy_18566) + mp_copy_18693) + mp_copy_18820) * 0.25;
                        }
                        else
                        {
                            int _18116 = (_17989 > 0.5) ? 17 : 16;
                            float _25135 = 0.0;
                            _25135 = 0.0;
                            float _18144 = 0.0;
                            for (int _25125 = 0; _25125 < 17; _25135 = _18144, _25125++)
                            {
                                if (_25125 >= _18116)
                                {
                                    break;
                                }
                                vec2 _25126 = vec2(0.0);
                                do
                                {
                                    if (_25125 == 0)
                                    {
                                        _25126 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25125 == 1)
                                    {
                                        _25126 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25125 == 2)
                                    {
                                        _25126 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25125 == 3)
                                    {
                                        _25126 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25125 == 4)
                                    {
                                        _25126 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25125 == 5)
                                    {
                                        _25126 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25125 == 6)
                                    {
                                        _25126 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25125 == 7)
                                    {
                                        _25126 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25125 == 8)
                                    {
                                        _25126 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25125 == 9)
                                    {
                                        _25126 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25125 == 10)
                                    {
                                        _25126 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25125 == 11)
                                    {
                                        _25126 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25125 == 12)
                                    {
                                        _25126 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25125 == 13)
                                    {
                                        _25126 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25125 == 14)
                                    {
                                        _25126 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25125 == 15)
                                    {
                                        _25126 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25126 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25128 = vec2(0.0);
                                do
                                {
                                    if (_25125 < 3)
                                    {
                                        _25128 = vec2(float(_25125) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25125 < 6)
                                    {
                                        _25128 = vec2((float(_25125 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25125 < 11)
                                    {
                                        _25128 = vec2((float(_25125 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25125 < 14)
                                    {
                                        _25128 = vec2((float(_25125 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25128 = vec2(float(_25125 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _18133 = mix(_25126, _25128, vec2(_17989));
                                float _18960 = _18133.x;
                                float _18964 = _18133.y;
                                highp vec2 _18990 = clamp(_14204 + (vec2((_18960 * _18002) - (_18964 * _18004), (_18960 * _18004) + (_18964 * _18002)) * _25132), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _19000 = vec2((3.0 + _18990.x) * _17981, _18990.y);
                                _19000.y = 1.0 - _18990.y;
                                highp float _19012 = float(_17975 <= textureLod(shadow_map, _19000, 0.0).x);
                                float mp_copy_19012 = _19012;
                                _18144 = _25135 + mp_copy_19012;
                            }
                            _25139 = _25135 / float(_18116);
                        }
                        bool _18157 = 3 == (_13852 - 1);
                        bool _18163 = false;
                        if (_18157)
                        {
                            _18163 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _18163 = _18157;
                        }
                        float _25140 = 0.0;
                        if (_18163)
                        {
                            highp vec2 _18170 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                            highp vec2 _18178 = smoothstep(vec2(0.0), _18170, _14204) * smoothstep(vec2(0.0), _18170, _17861);
                            _25140 = mix(1.0, _25139, _18178.x * _18178.y);
                        }
                        else
                        {
                            _25140 = _25139;
                        }
                        _25175 = _25111 + _14264;
                        _25172 = _25151 + (_14264 * _25140);
                    }
                    else
                    {
                        _25175 = _25111;
                        _25172 = _25151;
                    }
                    _25174 = _25175;
                    _25171 = _25172;
                }
                else
                {
                    _25174 = _25111;
                    _25171 = _25151;
                }
                _25173 = _25174;
                _25170 = _25171;
            }
            else
            {
                _25173 = _25111;
                _25170 = _25151;
            }
            _25176 = _25170 + (1.0 - _25173);
        }
        else
        {
            _25176 = 1.0;
        }
        bool _8480 = frag_info.ssao_lighting.w > 0.5;
        bool _8486 = false;
        if (_8480)
        {
            _8486 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _8486 = _8480;
        }
        float _25327 = 0.0;
        if (_8486)
        {
            _25327 = min(_25176, _25193.y);
        }
        else
        {
            _25327 = _25176;
        }
        float _8495 = _8458 * _25327;
        highp vec3 _8508 = ((((_8392 + (_8396 * ((vec3(1.0) - _8368) - _8392))) * _24747) * _25344) + (((_8368 * (_24555 * frag_info.environment_intensity)) * 1.0) * _25485)) * mix(1.0, _8495, frag_info.radiance_blend.y);
        highp vec3 _25742 = vec3(0.0);
        if (frag_info.camera_up.w > 0.5)
        {
            _25742 = _8508 + ((_25193.xyz * _8396) * _7308);
        }
        else
        {
            _25742 = _8508;
        }
        highp vec3 _25748 = vec3(0.0);
        if (_8445)
        {
            highp vec3 _25645 = vec3(0.0);
            highp vec3 _25646 = vec3(0.0);
            do
            {
                float _19078 = max(dot(_24476, _25569), 0.0);
                highp float hp_copy_19078 = _19078;
                if (_19078 <= 0.0)
                {
                    _25646 = vec3(0.0);
                    _25645 = vec3(0.0);
                    break;
                }
                float _19084 = max(_8265, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_19084 = _19084;
                vec3 _19087 = _25569 + mp_copy_24537;
                float _19090 = dot(_19087, _19087);
                vec3 _25643 = vec3(0.0);
                vec3 _25644 = vec3(0.0);
                if (_19090 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _19098 = _19087 * inversesqrt(_19090);
                    float _25642 = 0.0;
                    do
                    {
                        float _19155 = dot(_24476, _19098);
                        if (_19155 <= 0.0)
                        {
                            _25642 = 0.0;
                            break;
                        }
                        float _19162 = _24529 * _24529;
                        vec3 _19165 = cross(_24476, _19098);
                        float _19168 = _19155 * _19162;
                        float _19177 = _19162 / (dot(_19165, _19165) + (_19168 * _19168));
                        _25642 = min((_19177 * _19177) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _19215 = _8261 + (_8378 * pow(clamp(1.0 - max(dot(_19098, _24537), 0.0), 0.0, 1.0), 5.0));
                    _25644 = (_19215 * min(_25642 * (0.5 / max(mix((2.0 * hp_copy_19078) * _19084, hp_copy_19078 + hp_copy_19084, hp_copy_24529 * hp_copy_24529), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _25643 = _19215;
                }
                else
                {
                    _25644 = vec3(0.0);
                    _25643 = _8261;
                }
                _25646 = (_25644 * frag_info.directional_light_color.xyz) * _19078;
                _25645 = (((((vec3(1.0) - _25643) * _8395) * _8166) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _19078;
                break;
            } while(false);
            _25748 = (_25645 + _25646) * _8495;
        }
        else
        {
            _25748 = vec3(0.0);
        }
        highp vec2 _25647 = vec2(0.0);
        do
        {
            if (frag_info.punctual_dims.x < 0.5)
            {
                _25647 = vec2(0.0);
                break;
            }
            if (frag_info.froxel_grid.z > 0.5)
            {
                highp vec3 _19251 = v_position - frag_info.camera_position.xyz;
                highp float _19266 = dot(_19251, frag_info.camera_forward.xyz);
                highp float _19272 = max(_19266, 9.9999997473787516355514526367188e-05);
                highp vec2 _19375 = (vec3(dot(_19251, frag_info.camera_right.xyz), dot(_19251, frag_info.camera_up.xyz), _19272).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_19272, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
                int _19343 = int(((((clamp(floor((log2(max(_19266 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_19375.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_19375.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5);
                int _19388 = int(frag_info.punctual_dims.y + 0.5);
                _25647 = vec2(texelFetch(punctual_index, ivec2(_19343 % _19388, _19343 / _19388), 0).xy);
                break;
            }
            _25647 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
            break;
        } while(false);
        mediump int _8551 = int(_25647.x + 0.5);
        mediump int _8555 = int(_25647.y + 0.5);
        highp vec3 _25746 = vec3(0.0);
        _25746 = _25748;
        highp vec3 _27655 = vec3(0.0);
        for (int _25648 = 0; _25648 < _8555; _25746 = _27655, _25648++)
        {
            int _8564 = _8551 + _25648;
            int _19411 = int(frag_info.punctual_dims.y + 0.5);
            int _8567 = int(texelFetch(punctual_index, ivec2(_8564 % _19411, _8564 / _19411), 0).x + 0.5);
            ivec2 _19427 = ivec2(0, _8567);
            highp vec4 _19429 = texelFetch(punctual_lights, _19427, 0);
            highp vec4 _19437 = texelFetch(punctual_lights, ivec2(1, _8567), 0);
            highp float _8573 = _19429.w;
            highp vec3 _8575 = _19437.xyz;
            if (_8573 > 2.5)
            {
                highp vec4 _19445 = texelFetch(punctual_lights, ivec2(2, _8567), 0);
                highp vec4 _19453 = texelFetch(punctual_lights, ivec2(3, _8567), 0);
                highp vec3 _8589 = _19445.xyz * (_19445.w * 0.5);
                highp vec3 _8595 = _19453.xyz * (_19453.w * 0.5);
                highp vec3 _8597 = _19429.xyz;
                highp vec3 _8599 = _8597 - _8589;
                highp vec3 _8601 = _8599 - _8595;
                highp vec3 _8605 = _8597 + _8589;
                highp vec3 _8607 = _8605 - _8595;
                highp vec3 _8619 = _8599 + _8595;
                highp vec3 _8623 = _8597 - v_position;
                highp float _8629 = _19437.w;
                highp float _8633 = (dot(_8623, _8623) * _8629) * _8629;
                highp float _8638 = clamp(1.0 - (_8633 * _8633), 0.0, 1.0);
                float mp_copy_8638 = _8638;
                vec2 _19460 = (clamp(vec2(_24529, sqrt(1.0 - _8265)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
                float _19462 = _19460.x;
                float _19467 = _19460.y;
                vec4 _8662 = textureLod(brdf_lut, vec2((_19462 + 1.0) * 0.3333333432674407958984375, _19467), 0.0);
                vec4 _8666 = textureLod(brdf_lut, vec2((_19462 + 2.0) * 0.3333333432674407958984375, _19467), 0.0);
                vec3 _19510 = normalize(mp_copy_24537 - (_24476 * _8264));
                mat3 _19532 = transpose(mat3(_19510, -cross(_24476, _19510), _24476));
                mat3 _19533 = mat3(vec3(_8662.x, 0.0, _8662.y), vec3(0.0, 1.0, 0.0), vec3(_8662.z, 0.0, _8662.w)) * _19532;
                highp vec3 _19537 = _8601 - v_position;
                highp vec3 _19539 = normalize(_19533 * _19537);
                vec3 mp_copy_19539 = _19539;
                highp vec3 _19543 = _8607 - v_position;
                highp vec3 _19545 = normalize(_19533 * _19543);
                vec3 mp_copy_19545 = _19545;
                highp vec3 _19549 = (_8605 + _8595) - v_position;
                highp vec3 _19551 = normalize(_19533 * _19549);
                vec3 mp_copy_19551 = _19551;
                highp vec3 _19555 = _8619 - v_position;
                highp vec3 _19557 = normalize(_19533 * _19555);
                vec3 mp_copy_19557 = _19557;
                float _19586 = dot(_19539, _19545);
                float _19588 = abs(_19586);
                float _19602 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19588)) * _19588)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19588) * _19588));
                float _27479 = 0.0;
                if (_19586 > 0.0)
                {
                    _27479 = _19602;
                }
                else
                {
                    _27479 = (0.5 * inversesqrt(max(1.0 - (_19586 * _19586), 1.0000000116860974230803549289703e-07))) - _19602;
                }
                float _19635 = dot(_19545, _19551);
                float _19637 = abs(_19635);
                float _19651 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19637)) * _19637)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19637) * _19637));
                float _27480 = 0.0;
                if (_19635 > 0.0)
                {
                    _27480 = _19651;
                }
                else
                {
                    _27480 = (0.5 * inversesqrt(max(1.0 - (_19635 * _19635), 1.0000000116860974230803549289703e-07))) - _19651;
                }
                float _19684 = dot(_19551, _19557);
                float _19686 = abs(_19684);
                float _19700 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19686)) * _19686)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19686) * _19686));
                float _27481 = 0.0;
                if (_19684 > 0.0)
                {
                    _27481 = _19700;
                }
                else
                {
                    _27481 = (0.5 * inversesqrt(max(1.0 - (_19684 * _19684), 1.0000000116860974230803549289703e-07))) - _19700;
                }
                float _19733 = dot(_19557, _19539);
                float _19735 = abs(_19733);
                float _19749 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19735)) * _19735)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19735) * _19735));
                float _27482 = 0.0;
                if (_19733 > 0.0)
                {
                    _27482 = _19749;
                }
                else
                {
                    _27482 = (0.5 * inversesqrt(max(1.0 - (_19733 * _19733), 1.0000000116860974230803549289703e-07))) - _19749;
                }
                vec3 _19572 = (((cross(mp_copy_19539, mp_copy_19545) * _27479) + (cross(mp_copy_19545, mp_copy_19551) * _27480)) + (cross(mp_copy_19551, mp_copy_19557) * _27481)) + (cross(mp_copy_19557, mp_copy_19539) * _27482);
                float _19775 = length(_19572);
                mat3 _19835 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _19532;
                highp vec3 _19841 = normalize(_19835 * _19537);
                vec3 mp_copy_19841 = _19841;
                highp vec3 _19847 = normalize(_19835 * _19543);
                vec3 mp_copy_19847 = _19847;
                highp vec3 _19853 = normalize(_19835 * _19549);
                vec3 mp_copy_19853 = _19853;
                highp vec3 _19859 = normalize(_19835 * _19555);
                vec3 mp_copy_19859 = _19859;
                float _19888 = dot(_19841, _19847);
                float _19890 = abs(_19888);
                float _19904 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19890)) * _19890)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19890) * _19890));
                float _27483 = 0.0;
                if (_19888 > 0.0)
                {
                    _27483 = _19904;
                }
                else
                {
                    _27483 = (0.5 * inversesqrt(max(1.0 - (_19888 * _19888), 1.0000000116860974230803549289703e-07))) - _19904;
                }
                float _19937 = dot(_19847, _19853);
                float _19939 = abs(_19937);
                float _19953 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19939)) * _19939)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19939) * _19939));
                float _27484 = 0.0;
                if (_19937 > 0.0)
                {
                    _27484 = _19953;
                }
                else
                {
                    _27484 = (0.5 * inversesqrt(max(1.0 - (_19937 * _19937), 1.0000000116860974230803549289703e-07))) - _19953;
                }
                float _19986 = dot(_19853, _19859);
                float _19988 = abs(_19986);
                float _20002 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19988)) * _19988)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19988) * _19988));
                float _27485 = 0.0;
                if (_19986 > 0.0)
                {
                    _27485 = _20002;
                }
                else
                {
                    _27485 = (0.5 * inversesqrt(max(1.0 - (_19986 * _19986), 1.0000000116860974230803549289703e-07))) - _20002;
                }
                float _20035 = dot(_19859, _19841);
                float _20037 = abs(_20035);
                float _20051 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20037)) * _20037)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20037) * _20037));
                float _27486 = 0.0;
                if (_20035 > 0.0)
                {
                    _27486 = _20051;
                }
                else
                {
                    _27486 = (0.5 * inversesqrt(max(1.0 - (_20035 * _20035), 1.0000000116860974230803549289703e-07))) - _20051;
                }
                vec3 _19874 = (((cross(mp_copy_19841, mp_copy_19847) * _27483) + (cross(mp_copy_19847, mp_copy_19853) * _27484)) + (cross(mp_copy_19853, mp_copy_19859) * _27485)) + (cross(mp_copy_19859, mp_copy_19841) * _27486);
                float _20077 = length(_19874);
                _27655 = _25746 + (((_8575 * (mp_copy_8638 * mp_copy_8638)) * step(0.0, dot(cross(_8607 - _8601, _8619 - _8601), v_position - _8601))) * (((((_8261 * _8666.x) + (_8378 * _8666.y)) * max(((_19775 * _19775) + _19572.z) / (_19775 + 1.0), 0.0)) * 1.0) + (_8396 * max(((_20077 * _20077) + _19874.z) / (_20077 + 1.0), 0.0))));
            }
            else
            {
                highp float hp_copy_27423 = 0.0;
                vec3 _27396 = vec3(0.0);
                highp vec3 _27419 = vec3(0.0);
                float _27423 = 0.0;
                if (_8573 < 0.5)
                {
                    _27423 = _24529;
                    _27419 = _8575;
                    _27396 = -normalize(texelFetch(punctual_lights, ivec2(2, _8567), 0).xyz);
                }
                else
                {
                    highp vec3 _8753 = _19429.xyz - v_position;
                    highp float _8756 = dot(_8753, _8753);
                    highp float _8760 = inversesqrt(max(_8756, 9.9999999392252902907785028219223e-09));
                    highp vec3 _8761 = _8753 * _8760;
                    vec3 mp_copy_8761 = _8761;
                    highp float _8763 = _19437.w;
                    highp float _8768 = (_8756 * _8763) * _8763;
                    highp float _8773 = clamp(1.0 - (_8768 * _8768), 0.0, 1.0);
                    float mp_copy_8773 = _8773;
                    highp vec4 _20103 = texelFetch(punctual_lights, ivec2(3, _8567), 0);
                    highp float _8777 = _20103.w;
                    float _27427 = 0.0;
                    if (_8777 > 0.0)
                    {
                        highp float _8804 = (_24529 * _24529) + ((_8777 * 0.5) * _8760);
                        float mp_copy_8804 = _8804;
                        _27427 = sqrt(min(mp_copy_8804, 1.0));
                    }
                    else
                    {
                        _27427 = _24529;
                    }
                    highp vec3 _8811 = _8575 * ((mp_copy_8773 * mp_copy_8773) / max(pow(max(_8756, _8777 * _8777), _20103.z * 0.5), 9.9999997473787516355514526367188e-05));
                    highp vec3 _27420 = vec3(0.0);
                    if (_8573 > 1.5)
                    {
                        highp vec4 _20111 = texelFetch(punctual_lights, ivec2(2, _8567), 0);
                        highp float _8830 = clamp((dot(normalize(_20111.xyz), -mp_copy_8761) * _20111.w) + _20103.x, 0.0, 1.0);
                        float mp_copy_8830 = _8830;
                        highp vec3 _8835 = _8811 * (mp_copy_8830 * mp_copy_8830);
                        highp float _8837 = _20103.y;
                        bool _8838 = _8837 > (-0.5);
                        bool _8844 = false;
                        if (_8838)
                        {
                            _8844 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8844 = _8838;
                        }
                        highp vec3 _27421 = vec3(0.0);
                        if (_8844)
                        {
                            float _27387 = 0.0;
                            do
                            {
                                highp vec4 _20196 = mat4(texelFetch(punctual_lights, ivec2(4, _8567), 0), texelFetch(punctual_lights, ivec2(5, _8567), 0), texelFetch(punctual_lights, ivec2(6, _8567), 0), texelFetch(punctual_lights, ivec2(7, _8567), 0)) * vec4(v_position + (_7146 * frag_info.spot_shadow_params.z), 1.0);
                                highp float _20198 = _20196.w;
                                if (_20198 <= 0.0)
                                {
                                    _27387 = 1.0;
                                    break;
                                }
                                highp vec3 _20207 = _20196.xyz / vec3(_20198);
                                highp vec2 _20212 = (_20207.xy * 0.5) + vec2(0.5);
                                highp float _20214 = _20212.x;
                                bool _20215 = _20214 < 0.0;
                                bool _20222 = false;
                                if (!_20215)
                                {
                                    _20222 = _20214 > 1.0;
                                }
                                else
                                {
                                    _20222 = _20215;
                                }
                                bool _20229 = false;
                                if (!_20222)
                                {
                                    _20229 = _20212.y < 0.0;
                                }
                                else
                                {
                                    _20229 = _20222;
                                }
                                bool _20236 = false;
                                if (!_20229)
                                {
                                    _20236 = _20212.y > 1.0;
                                }
                                else
                                {
                                    _20236 = _20229;
                                }
                                bool _20243 = false;
                                if (!_20236)
                                {
                                    _20243 = _20207.z < 0.0;
                                }
                                else
                                {
                                    _20243 = _20236;
                                }
                                bool _20250 = false;
                                if (!_20243)
                                {
                                    _20250 = _20207.z > 1.0;
                                }
                                else
                                {
                                    _20250 = _20243;
                                }
                                if (_20250)
                                {
                                    _27387 = 1.0;
                                    break;
                                }
                                highp float _20257 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                highp float _20262 = frag_info.shadow_cascade_count + float(int(_8837 + 0.5));
                                highp float _20267 = _20207.z - frag_info.spot_shadow_params.y;
                                highp float _20270 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                                highp float _20283 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27386 = 0.0;
                                _27386 = float(_20267 <= textureLod(shadow_map, vec2((_20262 + clamp(_20214, 0.0, 1.0)) / _20257, 1.0 - clamp(_20212.y, 0.0, 1.0)), 0.0).x);
                                for (int _27385 = 0; _27385 < 8; )
                                {
                                    highp float _20293 = _20283 + (float(_27385) * 0.785398185253143310546875);
                                    float mp_copy_20293 = _20293;
                                    highp vec2 _20303 = _20212 + (vec2(cos(mp_copy_20293), sin(mp_copy_20293)) * _20270);
                                    highp float _20393 = float(_20267 <= textureLod(shadow_map, vec2((_20262 + clamp(_20303.x, 0.0, 1.0)) / _20257, 1.0 - clamp(_20303.y, 0.0, 1.0)), 0.0).x);
                                    float mp_copy_20393 = _20393;
                                    _27386 += mp_copy_20393;
                                    _27385++;
                                    continue;
                                }
                                _27387 = _27386 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27421 = _8835 * _27387;
                        }
                        else
                        {
                            _27421 = _8835;
                        }
                        _27420 = _27421;
                    }
                    else
                    {
                        bool _8860 = _8573 > 0.5;
                        bool _8866 = false;
                        if (_8860)
                        {
                            _8866 = _20103.y > (-0.5);
                        }
                        else
                        {
                            _8866 = _8860;
                        }
                        bool _8872 = false;
                        if (_8866)
                        {
                            _8872 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8872 = _8866;
                        }
                        highp vec3 _27422 = vec3(0.0);
                        if (_8872)
                        {
                            float _27372 = 0.0;
                            do
                            {
                                highp vec4 _20697 = texelFetch(punctual_lights, ivec2(4, _8567), 0);
                                highp vec4 _20705 = texelFetch(punctual_lights, ivec2(5, _8567), 0);
                                highp vec3 _20465 = (v_position + (_7146 * _20697.z)) - texelFetch(punctual_lights, _19427, 0).xyz;
                                highp vec3 _20467 = abs(_20465);
                                highp float _20469 = _20467.x;
                                highp float _20471 = _20467.y;
                                bool _20472 = _20469 >= _20471;
                                bool _20480 = false;
                                if (_20472)
                                {
                                    _20480 = _20469 >= _20467.z;
                                }
                                else
                                {
                                    _20480 = _20472;
                                }
                                highp vec3 _27362 = vec3(0.0);
                                float _27364 = 0.0;
                                if (_20480)
                                {
                                    highp float _20483 = _20465.x;
                                    bool _20484 = _20483 >= 0.0;
                                    highp vec3 _27361 = vec3(0.0);
                                    if (_20484)
                                    {
                                        _27361 = vec3(-_20465.z, _20465.y, _20483);
                                    }
                                    else
                                    {
                                        _27361 = vec3(_20465.zy, -_20483);
                                    }
                                    _27364 = _20484 ? 0.0 : 1.0;
                                    _27362 = _27361;
                                }
                                else
                                {
                                    highp vec3 _27363 = vec3(0.0);
                                    float _27366 = 0.0;
                                    if (_20471 >= _20467.z)
                                    {
                                        highp float _20517 = _20465.y;
                                        bool _20518 = _20517 >= 0.0;
                                        highp vec3 _27360 = vec3(0.0);
                                        if (_20518)
                                        {
                                            _27360 = vec3(-_20465.x, _20465.z, _20517);
                                        }
                                        else
                                        {
                                            _27360 = vec3(_20465.xz, -_20517);
                                        }
                                        _27366 = _20518 ? 2.0 : 3.0;
                                        _27363 = _27360;
                                    }
                                    else
                                    {
                                        highp float _20545 = _20465.z;
                                        bool _20546 = _20545 >= 0.0;
                                        highp vec3 _27359 = vec3(0.0);
                                        if (_20546)
                                        {
                                            _27359 = _20465;
                                        }
                                        else
                                        {
                                            _27359 = vec3(-_20465.x, _20465.y, -_20545);
                                        }
                                        _27366 = _20546 ? 4.0 : 5.0;
                                        _27363 = _27359;
                                    }
                                    _27364 = _27366;
                                    _27362 = _27363;
                                }
                                if (_27362.z <= 0.0)
                                {
                                    _27372 = 1.0;
                                    break;
                                }
                                highp vec2 _20586 = ((_27362.xy / vec2(_27362.z)) * 0.5) + vec2(0.5);
                                highp float _20597 = (_20697.x - (_20697.y / _27362.z)) - _20705.x;
                                if ((_20597 < 0.0) || (_20597 > 1.0))
                                {
                                    _27372 = 1.0;
                                    break;
                                }
                                highp float hp_copy_27369 = 0.0;
                                highp float _20609 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                bool _20615 = _27364 >= 4.0;
                                highp float _20617 = (frag_info.shadow_cascade_count + _20103.y) + float(_20615);
                                float _27369 = 0.0;
                                if (_20615)
                                {
                                    _27369 = _27364 - 4.0;
                                }
                                else
                                {
                                    _27369 = _27364;
                                }
                                hp_copy_27369 = _27369;
                                highp float _20634 = _20705.y * 0.5;
                                highp float _20637 = _20697.w * 0.0040000001899898052215576171875;
                                highp vec2 _20721 = vec2(_20634);
                                highp vec2 _20724 = vec2(1.0 - _20634);
                                highp vec2 _20730 = vec2(mod(hp_copy_27369, 2.0), 1.0 - floor(hp_copy_27369 * 0.5)) * 0.5;
                                highp vec2 _20733 = _20730 + (clamp(_20586, _20721, _20724) * 0.5);
                                highp float _20653 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27371 = 0.0;
                                _27371 = float(_20597 <= textureLod(shadow_map, vec2((_20617 + _20733.x) / _20609, 1.0 - _20733.y), 0.0).x);
                                for (int _27370 = 0; _27370 < 8; )
                                {
                                    highp float _20663 = _20653 + (float(_27370) * 0.785398185253143310546875);
                                    float mp_copy_20663 = _20663;
                                    highp vec2 _20770 = _20730 + (clamp(_20586 + (vec2(cos(mp_copy_20663), sin(mp_copy_20663)) * _20637), _20721, _20724) * 0.5);
                                    highp float _20787 = float(_20597 <= textureLod(shadow_map, vec2((_20617 + _20770.x) / _20609, 1.0 - _20770.y), 0.0).x);
                                    float mp_copy_20787 = _20787;
                                    _27371 += mp_copy_20787;
                                    _27370++;
                                    continue;
                                }
                                _27372 = _27371 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27422 = _8811 * _27372;
                        }
                        else
                        {
                            _27422 = _8811;
                        }
                        _27420 = _27422;
                    }
                    _27423 = _27427;
                    _27419 = _27420;
                    _27396 = _8761;
                }
                hp_copy_27423 = _27423;
                highp vec3 _27450 = vec3(0.0);
                highp vec3 _27451 = vec3(0.0);
                do
                {
                    float _20853 = max(dot(_24476, _27396), 0.0);
                    highp float hp_copy_20853 = _20853;
                    if (_20853 <= 0.0)
                    {
                        _27451 = vec3(0.0);
                        _27450 = vec3(0.0);
                        break;
                    }
                    float _20859 = max(_8265, 9.9999997473787516355514526367188e-05);
                    highp float hp_copy_20859 = _20859;
                    vec3 _20862 = _27396 + mp_copy_24537;
                    float _20865 = dot(_20862, _20862);
                    vec3 _27448 = vec3(0.0);
                    vec3 _27449 = vec3(0.0);
                    if (_20865 > 9.9999999392252902907785028219223e-09)
                    {
                        vec3 _20873 = _20862 * inversesqrt(_20865);
                        float _27447 = 0.0;
                        do
                        {
                            float _20930 = dot(_24476, _20873);
                            if (_20930 <= 0.0)
                            {
                                _27447 = 0.0;
                                break;
                            }
                            float _20937 = _27423 * _27423;
                            vec3 _20940 = cross(_24476, _20873);
                            float _20943 = _20930 * _20937;
                            float _20952 = _20937 / (dot(_20940, _20940) + (_20943 * _20943));
                            _27447 = min((_20952 * _20952) * 0.3183098733425140380859375, 65504.0);
                            break;
                        } while(false);
                        vec3 _20990 = _8261 + (_8378 * pow(clamp(1.0 - max(dot(_20873, _24537), 0.0), 0.0, 1.0), 5.0));
                        _27449 = (_20990 * min(_27447 * (0.5 / max(mix((2.0 * hp_copy_20853) * _20859, hp_copy_20853 + hp_copy_20859, hp_copy_27423 * hp_copy_27423), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                        _27448 = _20990;
                    }
                    else
                    {
                        _27449 = vec3(0.0);
                        _27448 = _8261;
                    }
                    _27451 = (_27449 * _27419) * _20853;
                    _27450 = (((((vec3(1.0) - _27448) * _8395) * _8166) * 0.3183098733425140380859375) * _27419) * _20853;
                    break;
                } while(false);
                _27655 = _25746 + (_27450 + _27451);
            }
        }
        bool _8929 = _FogInfo.params0.y > 0.5;
        bool _8935 = false;
        if (_8929)
        {
            _8935 = _FogInfo.params0.w > 0.0;
        }
        else
        {
            _8935 = _8929;
        }
        highp vec3 _25753 = vec3(0.0);
        if (_8935)
        {
            vec3 mp_copy_25749 = vec3(0.0);
            highp vec3 _25749 = vec3(0.0);
            if (_9102)
            {
                _25749 = -view_info.camera_forward.xyz;
            }
            else
            {
                _25749 = normalize(v_viewvector);
            }
            mp_copy_25749 = _25749;
            vec3 _8940 = _8286 * (-mp_copy_25749);
            vec3 _25750 = vec3(0.0);
            do
            {
                if (_9416)
                {
                    vec2 _21112 = vec2(atan(_8940.z, _8940.x), asin(clamp(_8940.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21112 = _21112;
                    _25750 = textureLod(prefiltered_radiance, (hp_copy_21112 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _21131 = vec2(atan(_8940.z, _8940.x), asin(clamp(_8940.y, -1.0, 1.0)));
                highp vec2 hp_copy_21131 = _21131;
                highp vec2 _21136 = (hp_copy_21131 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _21043 = clamp(_21136.y, 0.00390625, 0.99609375);
                float _21049 = floor(0.0);
                highp float _21068 = _21136.x;
                _25750 = mix(texture(prefiltered_radiance, vec2(_21068, (_21049 + _21043) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_21068, (min(_21049 + 1.0, 7.0) + _21043) * 0.125)).xyz, vec3(-_21049));
                break;
            } while(false);
            highp vec3 _25752 = vec3(0.0);
            if (_8309)
            {
                vec3 _25751 = vec3(0.0);
                do
                {
                    if (_9416)
                    {
                        vec2 _21241 = vec2(atan(_8940.z, _8940.x), asin(clamp(_8940.y, -1.0, 1.0)));
                        highp vec2 hp_copy_21241 = _21241;
                        _25751 = textureLod(prefiltered_radiance_b, (hp_copy_21241 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                        break;
                    }
                    vec2 _21260 = vec2(atan(_8940.z, _8940.x), asin(clamp(_8940.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21260 = _21260;
                    highp vec2 _21265 = (hp_copy_21260 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _21172 = clamp(_21265.y, 0.00390625, 0.99609375);
                    float _21178 = floor(0.0);
                    highp float _21197 = _21265.x;
                    _25751 = mix(texture(prefiltered_radiance_b, vec2(_21197, (_21178 + _21172) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_21197, (min(_21178 + 1.0, 7.0) + _21172) * 0.125)).xyz, vec3(-_21178));
                    break;
                } while(false);
                _25752 = mix(_25750, _25751, vec3(frag_info.radiance_blend.x));
            }
            else
            {
                _25752 = _25750;
            }
            _25753 = _25752 * frag_info.environment_intensity;
        }
        else
        {
            _25753 = _FogInfo.color.xyz;
        }
        highp vec4 _8964 = vec4(min((_25742 + (_25746 * mix(1.0, _24817, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7332, vec3(65504.0)), 1.0) * _28037;
        highp vec4 _25768 = vec4(0.0);
        do
        {
            if (_FogInfo.params0.y < 0.5)
            {
                _25768 = _8964;
                break;
            }
            int _21309 = int(_FogInfo.params0.x + 0.5);
            if (_21309 == 0)
            {
                _25768 = _8964;
                break;
            }
            highp float _25755 = 0.0;
            if (_9102)
            {
                _25755 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
            }
            else
            {
                _25755 = length(v_viewvector);
            }
            if ((_FogInfo.params1.w > 0.0) && (_25755 > _FogInfo.params1.w))
            {
                _25768 = _8964;
                break;
            }
            float _25759 = 0.0;
            if (_21309 == 1)
            {
                _25759 = clamp((_25755 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
            }
            else
            {
                float _25760 = 0.0;
                if (_21309 == 2)
                {
                    highp float _25758 = 0.0;
                    if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                    {
                        highp vec3 _25756 = vec3(0.0);
                        if (_9102)
                        {
                            _25756 = v_position - (view_info.camera_forward.xyz * _25755);
                        }
                        else
                        {
                            _25756 = v_position + v_viewvector;
                        }
                        highp float _21390 = -_FogInfo.params2.y;
                        highp float _21397 = _FogInfo.params1.x * exp(_21390 * (_25756.y - _FogInfo.params2.x));
                        highp float _21414 = _FogInfo.params2.y * (v_position.y - _25756.y);
                        highp float _25757 = 0.0;
                        if (abs(_21414) > 0.00124999997206032276153564453125)
                        {
                            _25757 = (_21397 - (_FogInfo.params1.x * exp(_21390 * (v_position.y - _FogInfo.params2.x)))) / _21414;
                        }
                        else
                        {
                            _25757 = _21397;
                        }
                        _25758 = _25757 * max(_25755 - _FogInfo.params1.y, 0.0);
                    }
                    else
                    {
                        _25758 = _FogInfo.params1.x * max(_25755 - _FogInfo.params1.y, 0.0);
                    }
                    _25760 = 1.0 - exp(-_25758);
                }
                else
                {
                    highp float _21452 = _FogInfo.params1.x * max(_25755 - _FogInfo.params1.y, 0.0);
                    _25760 = 1.0 - exp((-_21452) * _21452);
                }
                _25759 = _25760;
            }
            highp float _21464 = min(_25759, _FogInfo.params0.z);
            if (_21464 <= 0.0)
            {
                _25768 = _8964;
                break;
            }
            highp vec3 _21477 = mix(_FogInfo.color.xyz, _25753, vec3(_FogInfo.params0.w));
            bool _21480 = _FogInfo.sun.w > 0.5;
            bool _21486 = false;
            if (_21480)
            {
                _21486 = _FogInfo.params2.z > 0.0;
            }
            else
            {
                _21486 = _21480;
            }
            vec3 _25764 = vec3(0.0);
            if (_21486)
            {
                vec3 mp_copy_25761 = vec3(0.0);
                highp vec3 _25761 = vec3(0.0);
                if (_9102)
                {
                    _25761 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _25761 = normalize(v_viewvector);
                }
                mp_copy_25761 = _25761;
                highp float _21502 = pow(max(dot(-mp_copy_25761, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                float mp_copy_21502 = _21502;
                _25764 = _21477 + ((_FogInfo.sun.xyz * mp_copy_21502) * _FogInfo.params2.z);
            }
            else
            {
                _25764 = _21477;
            }
            highp float _21515 = _8964.w;
            float mp_copy_21515 = _21515;
            _25768 = vec4(mix(_8964.xyz, _25764 * mp_copy_21515, vec3(_21464)), _21515);
            break;
        } while(false);
        _27275 = _25768;
    }
    else
    {
        _27275 = vec4(0.0);
    }
    bool _6966 = _24512 > 0.5;
    vec4 _27272 = vec4(0.0);
    if (_6966)
    {
        bool _6974 = (_24512 > 2.5) && (!_6945);
        vec4 _25769 = vec4(0.0);
        if (_6974)
        {
            _25769 = vec4(debug_view_info.left.x, debug_view_info.view.y, debug_view_info.left.y, debug_view_info.view.w);
        }
        else
        {
            _25769 = debug_view_info.view;
        }
        vec2 _25770 = vec2(0.0);
        if (_6974)
        {
            _25770 = debug_view_info.left.zw;
        }
        else
        {
            _25770 = debug_view_info.params.xy;
        }
        vec4 _27270 = vec4(0.0);
        do
        {
            if (_25769.x < 20.0)
            {
                vec3 _27256 = vec3(0.0);
                if (_25769.x == 1.0)
                {
                    float _21958 = length(_7146);
                    vec3 _27255 = vec3(0.0);
                    if (_21958 > 9.9999999747524270787835121154785e-07)
                    {
                        _27255 = _7146 / vec3(_21958);
                    }
                    else
                    {
                        _27255 = vec3(0.0);
                    }
                    _27256 = ((_27255 * 0.5) + vec3(0.5)) * _25769.z;
                }
                else
                {
                    vec3 _27257 = vec3(0.0);
                    if (_25769.x == 2.0)
                    {
                        float _21981 = length(_24476);
                        vec3 _27254 = vec3(0.0);
                        if (_21981 > 9.9999999747524270787835121154785e-07)
                        {
                            _27254 = _24476 / vec3(_21981);
                        }
                        else
                        {
                            _27254 = vec3(0.0);
                        }
                        _27257 = ((_27254 * 0.5) + vec3(0.5)) * _25769.z;
                    }
                    else
                    {
                        vec3 _27258 = vec3(0.0);
                        if (_25769.x == 3.0)
                        {
                            float _22004 = length(v_tangent.xyz);
                            vec3 _27253 = vec3(0.0);
                            if (_22004 > 9.9999999747524270787835121154785e-07)
                            {
                                _27253 = v_tangent.xyz / vec3(_22004);
                            }
                            else
                            {
                                _27253 = vec3(0.0);
                            }
                            _27258 = ((_27253 * 0.5) + vec3(0.5)) * _25769.z;
                        }
                        else
                        {
                            vec3 _27259 = vec3(0.0);
                            if (_25769.x == 4.0)
                            {
                                highp float _21637 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_21637 = _21637;
                                vec3 _21638 = cross(_7144, v_tangent.xyz) * mp_copy_21637;
                                float _22027 = length(_21638);
                                vec3 _27252 = vec3(0.0);
                                if (_22027 > 9.9999999747524270787835121154785e-07)
                                {
                                    _27252 = _21638 / vec3(_22027);
                                }
                                else
                                {
                                    _27252 = vec3(0.0);
                                }
                                _27259 = ((_27252 * 0.5) + vec3(0.5)) * _25769.z;
                            }
                            else
                            {
                                vec3 _27260 = vec3(0.0);
                                if (_25769.x == 5.0)
                                {
                                    _27260 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _27261 = vec3(0.0);
                                    if (_25769.x == 6.0)
                                    {
                                        _27261 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * _25769.z;
                                    }
                                    else
                                    {
                                        vec3 _27262 = vec3(0.0);
                                        if (_25769.x == 7.0)
                                        {
                                            _27262 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * _25769.z;
                                        }
                                        else
                                        {
                                            vec3 _27263 = vec3(0.0);
                                            if (_25769.x == 8.0)
                                            {
                                                vec3 _22062 = max(v_color.xyz * _25769.z, vec3(0.0));
                                                _27263 = mix(_22062 * 12.9200000762939453125, (pow(max(_22062, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22062));
                                            }
                                            else
                                            {
                                                vec3 _27264 = vec3(0.0);
                                                if (_25769.x == 9.0)
                                                {
                                                    vec3 mp_copy_27250 = vec3(0.0);
                                                    highp vec3 _27250 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _27250 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _27250 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_27250 = _27250;
                                                    float _22098 = length(mp_copy_27250);
                                                    vec3 _27251 = vec3(0.0);
                                                    if (_22098 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _27251 = mp_copy_27250 / vec3(_22098);
                                                    }
                                                    else
                                                    {
                                                        _27251 = vec3(0.0);
                                                    }
                                                    _27264 = ((_27251 * 0.5) + vec3(0.5)) * _25769.z;
                                                }
                                                else
                                                {
                                                    vec3 _27265 = vec3(0.0);
                                                    if (_25769.x == 10.0)
                                                    {
                                                        float _22141 = max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                                                        float _22142 = (v_position.x - _25770.x) / _22141;
                                                        bool _22146 = _25769.w > 1.5;
                                                        float _27244 = 0.0;
                                                        if (_22146)
                                                        {
                                                            _27244 = fract(_22142);
                                                        }
                                                        else
                                                        {
                                                            float _27245 = 0.0;
                                                            if (_25769.w > 0.5)
                                                            {
                                                                _27245 = ((_22142 < 0.0) || (_22142 > 1.0)) ? 0.0 : _22142;
                                                            }
                                                            else
                                                            {
                                                                _27245 = clamp(_22142, 0.0, 1.0);
                                                            }
                                                            _27244 = _27245;
                                                        }
                                                        float _22193 = (v_position.y - _25770.x) / _22141;
                                                        float _27246 = 0.0;
                                                        if (_22146)
                                                        {
                                                            _27246 = fract(_22193);
                                                        }
                                                        else
                                                        {
                                                            float _27247 = 0.0;
                                                            if (_25769.w > 0.5)
                                                            {
                                                                _27247 = ((_22193 < 0.0) || (_22193 > 1.0)) ? 0.0 : _22193;
                                                            }
                                                            else
                                                            {
                                                                _27247 = clamp(_22193, 0.0, 1.0);
                                                            }
                                                            _27246 = _27247;
                                                        }
                                                        float _22244 = (v_position.z - _25770.x) / _22141;
                                                        float _27248 = 0.0;
                                                        if (_22146)
                                                        {
                                                            _27248 = fract(_22244);
                                                        }
                                                        else
                                                        {
                                                            float _27249 = 0.0;
                                                            if (_25769.w > 0.5)
                                                            {
                                                                _27249 = ((_22244 < 0.0) || (_22244 > 1.0)) ? 0.0 : _22244;
                                                            }
                                                            else
                                                            {
                                                                _27249 = clamp(_22244, 0.0, 1.0);
                                                            }
                                                            _27248 = _27249;
                                                        }
                                                        _27265 = vec3(_27244 * _25769.z, _27246 * _25769.z, _27248 * _25769.z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _27266 = vec3(0.0);
                                                        if (_25769.x == 11.0)
                                                        {
                                                            bvec3 _21713 = bvec3(gl_FrontFacing);
                                                            _27266 = vec3(_21713.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _21713.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _21713.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _27267 = vec3(0.0);
                                                            if (_25769.x == 12.0)
                                                            {
                                                                highp vec2 _22271 = v_texture_coords;
                                                                vec2 mp_copy_22271 = _22271;
                                                                vec2 _22283 = floor(mp_copy_22271 * 8.0);
                                                                float _22285 = _22283.x;
                                                                float _22287 = _22283.y;
                                                                float _22295 = _22285 + (_22287 * 8.0);
                                                                vec2 _22304 = step(vec2(0.0), mp_copy_22271) * step(mp_copy_22271, vec2(1.0));
                                                                _27267 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22285 + _22287, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22295 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22295 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22304.x * _22304.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _27268 = vec3(0.0);
                                                                if (_25769.x == 13.0)
                                                                {
                                                                    highp vec2 _22354 = v_texture_coords_1;
                                                                    vec2 mp_copy_22354 = _22354;
                                                                    vec2 _22366 = floor(mp_copy_22354 * 8.0);
                                                                    float _22368 = _22366.x;
                                                                    float _22370 = _22366.y;
                                                                    float _22378 = _22368 + (_22370 * 8.0);
                                                                    vec2 _22387 = step(vec2(0.0), mp_copy_22354) * step(mp_copy_22354, vec2(1.0));
                                                                    _27268 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22368 + _22370, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22378 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22378 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22387.x * _22387.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _27269 = vec3(0.0);
                                                                    if (_25769.x == 14.0)
                                                                    {
                                                                        highp float _22453 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _22459 = debug_view_info.depth.x > 0.5;
                                                                        bool _22465 = false;
                                                                        if (_22459)
                                                                        {
                                                                            _22465 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _22465 = _22459;
                                                                        }
                                                                        highp float _27240 = 0.0;
                                                                        if (_22465)
                                                                        {
                                                                            _27240 = 1.1920928955078125e-07 / _22453;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _27241 = 0.0;
                                                                            if (_22459)
                                                                            {
                                                                                _27241 = 5.9604644775390625e-08 / (_22453 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _27241 = 5.9604644775390625e-08 / (_22453 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _27240 = _27241;
                                                                        }
                                                                        highp float _22494 = dot(_7146, view_info.camera_forward.xyz);
                                                                        highp float _22500 = sqrt(max(1.0 - (_22494 * _22494), 0.0));
                                                                        highp float _27238 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _27238 = (debug_view_info.depth.z * _22500) / max(abs(_22494), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _27238 = (((1.0 / (_22453 * _22453)) * debug_view_info.depth.z) * _22500) / max(abs(dot(_7146, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _22538 = log2(max(max(8.0 * _27240, _27238 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_22538 = _22538;
                                                                        float _22577 = (mp_copy_22538 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                                                                        float _27242 = 0.0;
                                                                        if (_25769.w > 1.5)
                                                                        {
                                                                            _27242 = fract(_22577);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _27243 = 0.0;
                                                                            if (_25769.w > 0.5)
                                                                            {
                                                                                _27243 = ((_22577 < 0.0) || (_22577 > 1.0)) ? 0.0 : _22577;
                                                                            }
                                                                            else
                                                                            {
                                                                                _27243 = clamp(_22577, 0.0, 1.0);
                                                                            }
                                                                            _27242 = _27243;
                                                                        }
                                                                        _27269 = clamp(vec3(1.5) - abs(vec3(4.0 * _27242) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * _25769.z;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _22610 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _27269 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_22610.x + _22610.y, 2.0)));
                                                                    }
                                                                    _27268 = _27269;
                                                                }
                                                                _27267 = _27268;
                                                            }
                                                            _27266 = _27267;
                                                        }
                                                        _27265 = _27266;
                                                    }
                                                    _27264 = _27265;
                                                }
                                                _27263 = _27264;
                                            }
                                            _27262 = _27263;
                                        }
                                        _27261 = _27262;
                                    }
                                    _27260 = _27261;
                                }
                                _27259 = _27260;
                            }
                            _27258 = _27259;
                        }
                        _27257 = _27258;
                    }
                    _27256 = _27257;
                }
                _27270 = vec4(_27256, 1.0);
                break;
            }
            vec3 _27217 = vec3(0.0);
            if (_25769.x < 40.0)
            {
                vec3 _27218 = vec3(0.0);
                if (_25769.x == 20.0)
                {
                    vec3 _22631 = max(_7233.xyz * _25769.z, vec3(0.0));
                    _27218 = mix(_22631 * 12.9200000762939453125, (pow(max(_22631, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22631));
                }
                else
                {
                    vec3 _27219 = vec3(0.0);
                    if (_25769.x == 21.0)
                    {
                        float _22670 = (_28037 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                        float _27215 = 0.0;
                        if (_25769.w > 1.5)
                        {
                            _27215 = fract(_22670);
                        }
                        else
                        {
                            float _27216 = 0.0;
                            if (_25769.w > 0.5)
                            {
                                _27216 = ((_22670 < 0.0) || (_22670 > 1.0)) ? 0.0 : _22670;
                            }
                            else
                            {
                                _27216 = clamp(_22670, 0.0, 1.0);
                            }
                            _27215 = _27216;
                        }
                        _27219 = vec3(_27215 * _25769.z);
                    }
                    else
                    {
                        vec3 _27220 = vec3(0.0);
                        if (_25769.x == 22.0)
                        {
                            float _22721 = (_7279 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                            float _27213 = 0.0;
                            if (_25769.w > 1.5)
                            {
                                _27213 = fract(_22721);
                            }
                            else
                            {
                                float _27214 = 0.0;
                                if (_25769.w > 0.5)
                                {
                                    _27214 = ((_22721 < 0.0) || (_22721 > 1.0)) ? 0.0 : _22721;
                                }
                                else
                                {
                                    _27214 = clamp(_22721, 0.0, 1.0);
                                }
                                _27213 = _27214;
                            }
                            _27220 = vec3(_27213 * _25769.z);
                        }
                        else
                        {
                            vec3 _27221 = vec3(0.0);
                            if (_25769.x == 23.0)
                            {
                                float _22772 = (_7286 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                                float _27211 = 0.0;
                                if (_25769.w > 1.5)
                                {
                                    _27211 = fract(_22772);
                                }
                                else
                                {
                                    float _27212 = 0.0;
                                    if (_25769.w > 0.5)
                                    {
                                        _27212 = ((_22772 < 0.0) || (_22772 > 1.0)) ? 0.0 : _22772;
                                    }
                                    else
                                    {
                                        _27212 = clamp(_22772, 0.0, 1.0);
                                    }
                                    _27211 = _27212;
                                }
                                _27221 = vec3(_27211 * _25769.z);
                            }
                            else
                            {
                                vec3 _27222 = vec3(0.0);
                                if (_25769.x == 24.0)
                                {
                                    float _22823 = (1.0 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                                    float _27209 = 0.0;
                                    if (_25769.w > 1.5)
                                    {
                                        _27209 = fract(_22823);
                                    }
                                    else
                                    {
                                        float _27210 = 0.0;
                                        if (_25769.w > 0.5)
                                        {
                                            _27210 = ((_22823 < 0.0) || (_22823 > 1.0)) ? 0.0 : _22823;
                                        }
                                        else
                                        {
                                            _27210 = clamp(_22823, 0.0, 1.0);
                                        }
                                        _27209 = _27210;
                                    }
                                    _27222 = vec3(_27209 * _25769.z);
                                }
                                else
                                {
                                    vec3 _27223 = vec3(0.0);
                                    if (_25769.x == 25.0)
                                    {
                                        float _22874 = (_7308 - _25770.x) / max(_25770.y - _25770.x, 9.9999999747524270787835121154785e-07);
                                        float _27207 = 0.0;
                                        if (_25769.w > 1.5)
                                        {
                                            _27207 = fract(_22874);
                                        }
                                        else
                                        {
                                            float _27208 = 0.0;
                                            if (_25769.w > 0.5)
                                            {
                                                _27208 = ((_22874 < 0.0) || (_22874 > 1.0)) ? 0.0 : _22874;
                                            }
                                            else
                                            {
                                                _27208 = clamp(_22874, 0.0, 1.0);
                                            }
                                            _27207 = _27208;
                                        }
                                        _27223 = vec3(_27207 * _25769.z);
                                    }
                                    else
                                    {
                                        vec3 _27224 = vec3(0.0);
                                        if (_25769.x == 26.0)
                                        {
                                            vec3 _22910 = max(_7332 * _25769.z, vec3(0.0));
                                            _27224 = mix(_22910 * 12.9200000762939453125, (pow(max(_22910, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22910));
                                        }
                                        else
                                        {
                                            vec2 _22931 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _27224 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_22931.x + _22931.y, 2.0)));
                                        }
                                        _27223 = _27224;
                                    }
                                    _27222 = _27223;
                                }
                                _27221 = _27222;
                            }
                            _27220 = _27221;
                        }
                        _27219 = _27220;
                    }
                    _27218 = _27219;
                }
                _27217 = _27218;
            }
            else
            {
                vec3 _27225 = vec3(0.0);
                if (_25769.x < 60.0)
                {
                    vec2 _22952 = floor(gl_FragCoord.xy * vec2(0.125));
                    _27225 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_22952.x + _22952.y, 2.0)));
                }
                else
                {
                    vec3 _27226 = vec3(0.0);
                    if (_25769.x < 70.0)
                    {
                        vec3 _27227 = vec3(0.0);
                        if (_25769.x == 60.0)
                        {
                            _27227 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _25769.z;
                        }
                        else
                        {
                            vec3 _27228 = vec3(0.0);
                            if (_25769.x == 61.0)
                            {
                                _27228 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _25769.z;
                            }
                            else
                            {
                                vec2 _23040 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27228 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23040.x + _23040.y, 2.0)));
                            }
                            _27227 = _27228;
                        }
                        _27226 = _27227;
                    }
                    else
                    {
                        vec3 _27229 = vec3(0.0);
                        if (_25769.x < 80.0)
                        {
                            vec3 _27230 = vec3(0.0);
                            if (_25769.x == 70.0)
                            {
                                bool _23057 = v_texture_coords.x < 0.0;
                                bool _23064 = false;
                                if (!_23057)
                                {
                                    _23064 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _23064 = _23057;
                                }
                                bool _23071 = false;
                                if (!_23064)
                                {
                                    _23071 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _23071 = _23064;
                                }
                                bool _23078 = false;
                                if (!_23071)
                                {
                                    _23078 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _23078 = _23071;
                                }
                                bvec3 _23081 = bvec3(_23078);
                                highp vec3 _23082 = vec3(_23081.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23081.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23081.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _23107 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24476), normalize(_7146)) < 0.999000012874603271484375));
                                highp vec3 _23108 = vec3(_23107.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _23082.x, _23107.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _23082.y, _23107.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _23082.z);
                                float _23122 = length(v_normal);
                                bvec3 _23129 = bvec3((_23122 < 0.300000011920928955078125) || (_23122 > 1.7000000476837158203125));
                                highp vec3 _23130 = vec3(_23129.x ? vec3(1.0, 0.5, 0.0).x : _23108.x, _23129.y ? vec3(1.0, 0.5, 0.0).y : _23108.y, _23129.z ? vec3(1.0, 0.5, 0.0).z : _23108.z);
                                bool _23135 = _7279 > 0.0500000007450580596923828125;
                                bool _23141 = false;
                                if (_23135)
                                {
                                    _23141 = _7279 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _23141 = _23135;
                                }
                                vec3 _23153 = vec3(0.0);
                                bvec3 _23143 = bvec3(_23141);
                                highp vec3 _23144 = vec3(_23143.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _23130.x, _23143.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _23130.y, _23143.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _23130.z);
                                vec3 _27205 = vec3(0.0);
                                do
                                {
                                    _23153 = _7233.xyz;
                                    float _23154 = dot(_23153, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7279 > 0.5)
                                    {
                                        _27205 = _23144;
                                        break;
                                    }
                                    if (_23154 < 0.0130000002682209014892578125)
                                    {
                                        _27205 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_23154 > 0.87000000476837158203125)
                                    {
                                        _27205 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _27205 = _23144;
                                    break;
                                } while(false);
                                vec3 _27206 = vec3(0.0);
                                do
                                {
                                    vec3 _23199 = ((_23153 + _24476) + _7332) + vec3((_7279 + _7286) + _7308);
                                    bool _23214 = min(min(_7230, _7231), _7232) < 0.0;
                                    bool _23227 = false;
                                    if (!_23214)
                                    {
                                        _23227 = min(min(_7332.x, _7332.y), _7332.z) < 0.0;
                                    }
                                    else
                                    {
                                        _23227 = _23214;
                                    }
                                    if (any(isnan(_23199)))
                                    {
                                        _27206 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_23199)))
                                    {
                                        _27206 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_23227)
                                    {
                                        _27206 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _27206 = _27205;
                                    break;
                                } while(false);
                                _27230 = _27206;
                            }
                            else
                            {
                                vec3 _27231 = vec3(0.0);
                                if (_25769.x == 71.0)
                                {
                                    vec3 _27204 = vec3(0.0);
                                    do
                                    {
                                        vec3 _23267 = ((_7233.xyz + _24476) + _7332) + vec3((_7279 + _7286) + _7308);
                                        bool _23282 = min(min(_7230, _7231), _7232) < 0.0;
                                        bool _23295 = false;
                                        if (!_23282)
                                        {
                                            _23295 = min(min(_7332.x, _7332.y), _7332.z) < 0.0;
                                        }
                                        else
                                        {
                                            _23295 = _23282;
                                        }
                                        if (any(isnan(_23267)))
                                        {
                                            _27204 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_23267)))
                                        {
                                            _27204 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_23295)
                                        {
                                            _27204 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _27204 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _27231 = _27204;
                                }
                                else
                                {
                                    vec3 _27232 = vec3(0.0);
                                    if (_25769.x == 72.0)
                                    {
                                        vec3 _27203 = vec3(0.0);
                                        do
                                        {
                                            float _23317 = dot(_7233.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7279 > 0.5)
                                            {
                                                _27203 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_23317 < 0.0130000002682209014892578125)
                                            {
                                                _27203 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_23317 > 0.87000000476837158203125)
                                            {
                                                _27203 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _27203 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _27232 = _27203;
                                    }
                                    else
                                    {
                                        vec3 _27233 = vec3(0.0);
                                        if (_25769.x == 73.0)
                                        {
                                            bool _23339 = _7279 > 0.0500000007450580596923828125;
                                            bool _23345 = false;
                                            if (_23339)
                                            {
                                                _23345 = _7279 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _23345 = _23339;
                                            }
                                            bvec3 _23347 = bvec3(_23345);
                                            _27233 = vec3(_23347.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _23347.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _23347.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _27234 = vec3(0.0);
                                            if (_25769.x == 74.0)
                                            {
                                                float _23353 = length(v_normal);
                                                bvec3 _23360 = bvec3((_23353 < 0.300000011920928955078125) || (_23353 > 1.7000000476837158203125));
                                                _27234 = vec3(_23360.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _23360.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _23360.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _27235 = vec3(0.0);
                                                if (_25769.x == 75.0)
                                                {
                                                    bvec3 _23383 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24476), normalize(_7146)) < 0.999000012874603271484375));
                                                    _27235 = vec3(_23383.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _23383.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _23383.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _27236 = vec3(0.0);
                                                    if (_25769.x == 76.0)
                                                    {
                                                        bool _23401 = v_texture_coords.x < 0.0;
                                                        bool _23408 = false;
                                                        if (!_23401)
                                                        {
                                                            _23408 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23408 = _23401;
                                                        }
                                                        bool _23415 = false;
                                                        if (!_23408)
                                                        {
                                                            _23415 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _23415 = _23408;
                                                        }
                                                        bool _23422 = false;
                                                        if (!_23415)
                                                        {
                                                            _23422 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23422 = _23415;
                                                        }
                                                        bvec3 _23425 = bvec3(_23422);
                                                        _27236 = vec3(_23425.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23425.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23425.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _23438 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _27236 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23438.x + _23438.y, 2.0)));
                                                    }
                                                    _27235 = _27236;
                                                }
                                                _27234 = _27235;
                                            }
                                            _27233 = _27234;
                                        }
                                        _27232 = _27233;
                                    }
                                    _27231 = _27232;
                                }
                                _27230 = _27231;
                            }
                            _27229 = _27230;
                        }
                        else
                        {
                            vec3 _27237 = vec3(0.0);
                            if (_25769.x == 80.0)
                            {
                                _27237 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _23456 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27237 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23456.x + _23456.y, 2.0)));
                            }
                            _27229 = _27237;
                        }
                        _27226 = _27229;
                    }
                    _27225 = _27226;
                }
                _27217 = _27225;
            }
            _27270 = vec4(_27217, 1.0);
            break;
        } while(false);
        _27272 = _27270;
    }
    else
    {
        _27272 = vec4(0.0);
    }
    bool _7019 = false;
    if (_6966)
    {
        _7019 = ((_24512 < 1.5) || (_24512 > 2.5)) || _6945;
    }
    else
    {
        _7019 = _6966;
    }
    bvec4 _7026 = bvec4(_7019);
    frag_color = vec4(_7026.x ? _27272.x : _27275.x, _7026.y ? _27272.y : _27275.y, _7026.z ? _27272.z : _27275.z, _7026.w ? _27272.w : _27275.w);
    float _27357 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _27357 = 1.0;
    }
    else
    {
        _27357 = abs(frag_info.fade);
    }
    frag_color *= _27357;
}

