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
    highp float _7182 = gl_FrontFacing ? 1.0 : (-1.0);
    float mp_copy_7182 = _7182;
    vec3 _7184 = normalize(v_normal);
    vec3 _7186 = _7184 * mp_copy_7182;
    vec4 _7227 = mix(vec4(1.0), v_color, vec4(frag_info.vertex_color_weight));
    bool _7230 = texture_transforms.base_color_rotation.w > 0.5;
    highp vec2 _24757 = vec2(0.0);
    if (_7230)
    {
        highp vec2 _24756 = vec2(0.0);
        if (int(texture_transforms.base_color_rotation.z + 0.5) == 1)
        {
            _24756 = v_texture_coords_1;
        }
        else
        {
            _24756 = v_texture_coords;
        }
        highp vec2 _7417 = _24756 * texture_transforms.base_color_transform.zw;
        highp float _7423 = _7417.x;
        highp float _7428 = _7417.y;
        _24757 = texture_transforms.base_color_transform.xy + vec2((texture_transforms.base_color_rotation.x * _7423) - (texture_transforms.base_color_rotation.y * _7428), (texture_transforms.base_color_rotation.y * _7423) + (texture_transforms.base_color_rotation.x * _7428));
    }
    else
    {
        _24757 = v_texture_coords;
    }
    vec4 _7244 = texture(base_color_texture, _24757);
    vec3 _7246 = _7244.xyz;
    vec3 _7254 = (mix(_7246 * vec3(0.077399380505084991455078125), pow((_7246 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7246)) * _7227.xyz) * frag_info.color.xyz;
    float _28246 = (frag_info.alpha_mode == 1.0) ? 1.0 : ((_7244.w * _7227.w) * frag_info.color.w);
    float _7270 = _7254.x;
    float _7271 = _7254.y;
    float _7272 = _7254.z;
    vec4 _7273 = vec4(_7270, _7271, _7272, _28246);
    vec3 _24769 = vec3(0.0);
    if (frag_info.has_normal_map > 0.5)
    {
        highp vec2 _24760 = vec2(0.0);
        if (_7230)
        {
            highp vec2 _24759 = vec2(0.0);
            if (int(texture_transforms.normal_rotation.z + 0.5) == 1)
            {
                _24759 = v_texture_coords_1;
            }
            else
            {
                _24759 = v_texture_coords;
            }
            highp vec2 _7511 = _24759 * texture_transforms.normal_transform.zw;
            highp float _7517 = _7511.x;
            highp float _7522 = _7511.y;
            _24760 = texture_transforms.normal_transform.xy + vec2((texture_transforms.normal_rotation.x * _7517) - (texture_transforms.normal_rotation.y * _7522), (texture_transforms.normal_rotation.y * _7517) + (texture_transforms.normal_rotation.x * _7522));
        }
        else
        {
            _24760 = v_texture_coords;
        }
        vec3 _7569 = ((texture(normal_texture, _24760).xyz * 255.0) * vec3(0.0078740157186985015869140625)) - vec3(1.007874011993408203125);
        vec2 _7573 = _7569.xy * vec2(frag_info.normal_scale);
        vec3 _23962 = _7569;
        _23962.x = _7573.x;
        _23962.y = _7573.y;
        highp vec3 _7579 = -v_viewvector;
        mat3 _24768 = mat3(vec3(0.0), vec3(0.0), vec3(0.0));
        do
        {
            vec3 _7609 = v_tangent.xyz - (_7186 * dot(_7186, v_tangent.xyz));
            highp float _7612 = dot(_7609, _7609);
            bool _7614 = _7612 <= 1.0000000133514319600180897396058e-10;
            bool _7622 = false;
            if (!_7614)
            {
                _7622 = abs(v_tangent.w) < 0.5;
            }
            else
            {
                _7622 = _7614;
            }
            if (_7622)
            {
                highp vec2 _7680 = dFdx(_24760);
                highp vec2 _7682 = dFdy(_24760);
                bvec2 _28248 = bvec2(length(_7680) == 0.0);
                highp vec2 _28249 = vec2(_28248.x ? vec2(1.0, 0.0).x : _7680.x, _28248.y ? vec2(1.0, 0.0).y : _7680.y);
                bvec2 _28250 = bvec2(length(_7682) == 0.0);
                highp vec2 _28251 = vec2(_28250.x ? vec2(0.0, 1.0).x : _7682.x, _28250.y ? vec2(0.0, 1.0).y : _7682.y);
                highp vec3 _7695 = cross(dFdy(_7579), _7186);
                highp vec3 _7698 = cross(_7186, dFdx(_7579));
                highp vec3 _7707 = (_7695 * _28249.x) + (_7698 * _28251.x);
                highp vec3 _7716 = (_7695 * _28249.y) + (_7698 * _28251.y);
                highp float _7725 = inversesqrt(max(max(dot(_7707, _7707), dot(_7716, _7716)), 9.9999996826552253889678874634872e-21));
                _24768 = mat3(_7707 * _7725, _7716 * _7725, _7186);
                break;
            }
            highp vec3 _7632 = _7609 * inversesqrt(_7612);
            _24768 = mat3(_7632, normalize(cross(_7186, _7632)) * sign(v_tangent.w), _7186);
            break;
        } while(false);
        _24769 = normalize(_24768 * _23962);
    }
    else
    {
        _24769 = _7186;
    }
    highp vec2 _24771 = vec2(0.0);
    if (_7230)
    {
        highp vec2 _24770 = vec2(0.0);
        if (int(texture_transforms.metallic_roughness_rotation.z + 0.5) == 1)
        {
            _24770 = v_texture_coords_1;
        }
        else
        {
            _24770 = v_texture_coords;
        }
        highp vec2 _7787 = _24770 * texture_transforms.metallic_roughness_transform.zw;
        highp float _7793 = _7787.x;
        highp float _7798 = _7787.y;
        _24771 = texture_transforms.metallic_roughness_transform.xy + vec2((texture_transforms.metallic_roughness_rotation.x * _7793) - (texture_transforms.metallic_roughness_rotation.y * _7798), (texture_transforms.metallic_roughness_rotation.y * _7793) + (texture_transforms.metallic_roughness_rotation.x * _7798));
    }
    else
    {
        _24771 = v_texture_coords;
    }
    vec4 _7313 = texture(metallic_roughness_texture, _24771);
    float _7319 = clamp(_7313.z * frag_info.metallic_factor, 0.0, 1.0);
    float _7326 = clamp(_7313.y * frag_info.roughness_factor, 0.04500000178813934326171875, 1.0);
    highp vec2 _24773 = vec2(0.0);
    if (_7230)
    {
        highp vec2 _24772 = vec2(0.0);
        if (int(texture_transforms.occlusion_rotation.z + 0.5) == 1)
        {
            _24772 = v_texture_coords_1;
        }
        else
        {
            _24772 = v_texture_coords;
        }
        highp vec2 _7857 = _24772 * texture_transforms.occlusion_transform.zw;
        highp float _7863 = _7857.x;
        highp float _7868 = _7857.y;
        _24773 = texture_transforms.occlusion_transform.xy + vec2((texture_transforms.occlusion_rotation.x * _7863) - (texture_transforms.occlusion_rotation.y * _7868), (texture_transforms.occlusion_rotation.y * _7863) + (texture_transforms.occlusion_rotation.x * _7868));
    }
    else
    {
        _24773 = v_texture_coords;
    }
    vec4 _7341 = texture(occlusion_texture, _24773);
    float _7348 = 1.0 - ((1.0 - _7341.x) * frag_info.occlusion_strength);
    highp vec2 _24775 = vec2(0.0);
    if (_7230)
    {
        highp vec2 _24774 = vec2(0.0);
        if (int(texture_transforms.emissive_rotation.z + 0.5) == 1)
        {
            _24774 = v_texture_coords_1;
        }
        else
        {
            _24774 = v_texture_coords;
        }
        highp vec2 _7927 = _24774 * texture_transforms.emissive_transform.zw;
        highp float _7933 = _7927.x;
        highp float _7938 = _7927.y;
        _24775 = texture_transforms.emissive_transform.xy + vec2((texture_transforms.emissive_rotation.x * _7933) - (texture_transforms.emissive_rotation.y * _7938), (texture_transforms.emissive_rotation.y * _7933) + (texture_transforms.emissive_rotation.x * _7938));
    }
    else
    {
        _24775 = v_texture_coords;
    }
    bool _7995 = false;
    vec4 _7363 = texture(emissive_texture, _24775);
    vec3 _7364 = _7363.xyz;
    vec3 _7372 = (mix(_7364 * vec3(0.077399380505084991455078125), pow((_7364 + vec3(0.054999999701976776123046875)) * vec3(0.947867333889007568359375), vec3(2.400000095367431640625)), step(vec3(0.040449999272823333740234375), _7364)) * frag_info.emissive_factor.xyz) * frag_info.emissive_factor.w;
    float _24805 = 0.0;
    do
    {
        _7995 = debug_view_info.view.x < 0.5;
        if (_7995)
        {
            _24805 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _24805 = 1.0;
            break;
        }
        _24805 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    bool _7978 = _24805 < 0.5;
    bool _7987 = false;
    if (!_7978)
    {
        _7987 = (_24805 > 1.5) && (_24805 < 2.5);
    }
    else
    {
        _7987 = _7978;
    }
    vec4 _27478 = vec4(0.0);
    if (_7987)
    {
        highp float hp_copy_24822 = 0.0;
        vec3 _8221 = _7273.xyz;
        float _24822 = 0.0;
        do
        {
            if (frag_info.specular_aa_variance <= 0.0)
            {
                _24822 = _7326;
                break;
            }
            vec3 _9039 = dFdx(_24769);
            vec3 _9041 = dFdy(_24769);
            _24822 = sqrt(clamp((_7326 * _7326) + min(2.0 * (frag_info.specular_aa_variance * max(dot(_9039, _9039), dot(_9041, _9041))), frag_info.specular_aa_threshold), 0.00202500005252659320831298828125, 1.0));
            break;
        } while(false);
        hp_copy_24822 = _24822;
        float _24832 = 0.0;
        vec3 _24837 = vec3(0.0);
        float _25110 = 0.0;
        vec4 _25486 = vec4(0.0);
        vec3 _25637 = vec3(0.0);
        if (frag_info.ssao_params.x > 0.5)
        {
            vec4 _8248 = texture(ssao_texture, gl_FragCoord.xy * frag_info.ssao_params.zw);
            float _24823 = 0.0;
            if (frag_info.camera_up.w > 0.5)
            {
                _24823 = _8248.w;
            }
            else
            {
                _24823 = _8248.x;
            }
            float _8261 = min(_7348, _24823);
            bool _8264 = frag_info.ssao_lighting.z > 0.5;
            bool _8270 = false;
            if (_8264)
            {
                _8270 = frag_info.camera_up.w < 0.5;
            }
            else
            {
                _8270 = _8264;
            }
            vec3 _24838 = vec3(0.0);
            if (_8270)
            {
                vec2 _9074 = (_8248.zw * 2.0) - vec2(1.0);
                float _9076 = _9074.x;
                float _9078 = _9074.y;
                float _9086 = (1.0 - abs(_9076)) - abs(_9078);
                vec3 _9087 = vec3(_9076, _9078, _9086);
                vec3 _24826 = vec3(0.0);
                if (_9086 < 0.0)
                {
                    vec2 _9100 = (vec2(1.0) - abs(_9087.yx)) * vec2((_9076 >= 0.0) ? 1.0 : (-1.0), (_9078 >= 0.0) ? 1.0 : (-1.0));
                    vec3 _24011 = _9087;
                    _24011.x = _9100.x;
                    _24011.y = _9100.y;
                    _24826 = _24011;
                }
                else
                {
                    _24826 = _9087;
                }
                vec3 _9108 = -normalize(_24826);
                _24838 = normalize(((frag_info.camera_right.xyz * _9108.x) + (frag_info.camera_up.xyz * _9108.y)) + (frag_info.camera_forward.xyz * _9108.z));
            }
            else
            {
                _24838 = vec3(0.0);
            }
            vec3 _8298 = vec3(_8261);
            _25637 = mix(_8298, max(_8298, ((((((_8221 * 2.040400028228759765625) - vec3(0.3323999941349029541015625)) * _8261) + ((_8221 * (-4.79510021209716796875)) + vec3(0.6417000293731689453125))) * _8261) + ((_8221 * 2.755199909210205078125) + vec3(0.69029998779296875))) * _8261), vec3(clamp(frag_info.ssao_lighting.y, 0.0, 1.0)));
            _25486 = _8248;
            _25110 = _8261;
            _24837 = _24838;
            _24832 = float(_8270);
        }
        else
        {
            _25637 = vec3(_7348);
            _25486 = vec4(1.0);
            _25110 = _7348;
            _24837 = vec3(0.0);
            _24832 = 0.0;
        }
        vec3 mp_copy_24830 = vec3(0.0);
        bool _9157 = view_info.camera_forward.w > 0.5;
        highp vec3 _24830 = vec3(0.0);
        if (_9157)
        {
            _24830 = -view_info.camera_forward.xyz;
        }
        else
        {
            _24830 = normalize(v_viewvector);
        }
        mp_copy_24830 = _24830;
        vec3 _8316 = mix(frag_info.dielectric_f0.xyz, _8221, vec3(_7319));
        float _8319 = dot(_24769, _24830);
        float _8320 = max(_8319, 0.0);
        float _8324 = max(dot(_7186, _24830), 0.0);
        vec3 _8328 = reflect(-mp_copy_24830, _24769);
        mat3 _8341 = mat3(frag_info.environment_transform[0].xyz, frag_info.environment_transform[1].xyz, frag_info.environment_transform[2].xyz);
        bool _8344 = _24832 > 0.5;
        bvec3 _8347 = bvec3(_8344);
        highp vec3 _8348 = vec3(_8347.x ? _24837.x : _24769.x, _8347.y ? _24837.y : _24769.y, _8347.z ? _24837.z : _24769.z);
        vec3 mp_copy_8348 = _8348;
        vec3 _8349 = _8341 * mp_copy_8348;
        vec3 _24841 = vec3(0.0);
        if (frag_info.probe_box.w > 0.5)
        {
            vec3 _9224 = _8328 + (((step(vec3(0.0), _8328) * 2.0) - vec3(1.0)) * 9.9999999747524270787835121154785e-07);
            highp vec3 hp_copy_9224 = _9224;
            highp vec3 _9226 = vec3(1.0) / hp_copy_9224;
            highp vec3 _9243 = max(((frag_info.probe_box.xyz + frag_info.probe_extents.xyz) - v_position) * _9226, ((frag_info.probe_box.xyz - frag_info.probe_extents.xyz) - v_position) * _9226);
            _24841 = normalize((v_position + (_8328 * max(min(min(_9243.x, _9243.y), _9243.z), 0.0))) - frag_info.probe_box.xyz);
        }
        else
        {
            _24841 = _8328;
        }
        bool _9471 = false;
        vec3 _8354 = _8341 * _24841;
        float _9290 = _8349.y;
        float _9291 = 0.48860299587249755859375 * _9290;
        float _9297 = _8349.z;
        float _9298 = 0.48860299587249755859375 * _9297;
        float _9304 = _8349.x;
        float _9305 = 0.48860299587249755859375 * _9304;
        float _9312 = 1.09254801273345947265625 * _9304;
        float _9315 = _9312 * _9290;
        float _9325 = (1.09254801273345947265625 * _9290) * _9297;
        float _9337 = 0.3153919875621795654296875 * (((3.0 * _9297) * _9297) - 1.0);
        float _9347 = _9312 * _9297;
        float _9363 = 0.546274006366729736328125 * ((_9304 * _9304) - (_9290 * _9290));
        vec3 _8357 = max(((((((((texelFetch(irradiance_field, ivec2(0), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1, 0), 0).xyz * _9291)) + (texelFetch(irradiance_field, ivec2(2, 0), 0).xyz * _9298)) + (texelFetch(irradiance_field, ivec2(3, 0), 0).xyz * _9305)) + (texelFetch(irradiance_field, ivec2(4, 0), 0).xyz * _9315)) + (texelFetch(irradiance_field, ivec2(5, 0), 0).xyz * _9325)) + (texelFetch(irradiance_field, ivec2(6, 0), 0).xyz * _9337)) + (texelFetch(irradiance_field, ivec2(7, 0), 0).xyz * _9347)) + (texelFetch(irradiance_field, ivec2(8, 0), 0).xyz * _9363), vec3(0.0));
        vec3 _24842 = vec3(0.0);
        do
        {
            _9471 = radiance_layout_info.mip_layout > 0.5;
            if (_9471)
            {
                vec2 _9550 = vec2(atan(_8354.z, _8354.x), asin(clamp(_8354.y, -1.0, 1.0)));
                highp vec2 hp_copy_9550 = _9550;
                _24842 = textureLod(prefiltered_radiance, (hp_copy_9550 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24822, 0.0, 1.0) * 7.0).xyz;
                break;
            }
            vec2 _9569 = vec2(atan(_8354.z, _8354.x), asin(clamp(_8354.y, -1.0, 1.0)));
            highp vec2 hp_copy_9569 = _9569;
            highp vec2 _9574 = (hp_copy_9569 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
            highp float _9481 = clamp(_9574.y, 0.00390625, 0.99609375);
            float _9485 = clamp(_24822, 0.0, 1.0) * 7.0;
            float _9487 = floor(_9485);
            highp float _9506 = _9574.x;
            _24842 = mix(texture(prefiltered_radiance, vec2(_9506, (_9487 + _9481) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_9506, (min(_9487 + 1.0, 7.0) + _9481) * 0.125)).xyz, vec3(_9485 - _9487));
            break;
        } while(false);
        bool _8364 = frag_info.radiance_blend.x > 0.0;
        highp vec3 _24847 = vec3(0.0);
        highp vec3 _24848 = vec3(0.0);
        if (_8364)
        {
            vec3 _24843 = vec3(0.0);
            do
            {
                if (_9471)
                {
                    vec2 _9862 = vec2(atan(_8354.z, _8354.x), asin(clamp(_8354.y, -1.0, 1.0)));
                    highp vec2 hp_copy_9862 = _9862;
                    _24843 = textureLod(prefiltered_radiance_b, (hp_copy_9862 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), clamp(_24822, 0.0, 1.0) * 7.0).xyz;
                    break;
                }
                vec2 _9881 = vec2(atan(_8354.z, _8354.x), asin(clamp(_8354.y, -1.0, 1.0)));
                highp vec2 hp_copy_9881 = _9881;
                highp vec2 _9886 = (hp_copy_9881 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _9793 = clamp(_9886.y, 0.00390625, 0.99609375);
                float _9797 = clamp(_24822, 0.0, 1.0) * 7.0;
                float _9799 = floor(_9797);
                highp float _9818 = _9886.x;
                _24843 = mix(texture(prefiltered_radiance_b, vec2(_9818, (_9799 + _9793) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_9818, (min(_9799 + 1.0, 7.0) + _9793) * 0.125)).xyz, vec3(_9797 - _9799));
                break;
            } while(false);
            highp vec3 _8375 = vec3(frag_info.radiance_blend.x);
            _24848 = mix(_24842, _24843, _8375);
            _24847 = mix(_8357, max(((((((((texelFetch(irradiance_field, ivec2(0, 1), 0).xyz * 0.2820949852466583251953125) + (texelFetch(irradiance_field, ivec2(1), 0).xyz * _9291)) + (texelFetch(irradiance_field, ivec2(2, 1), 0).xyz * _9298)) + (texelFetch(irradiance_field, ivec2(3, 1), 0).xyz * _9305)) + (texelFetch(irradiance_field, ivec2(4, 1), 0).xyz * _9315)) + (texelFetch(irradiance_field, ivec2(5, 1), 0).xyz * _9325)) + (texelFetch(irradiance_field, ivec2(6, 1), 0).xyz * _9337)) + (texelFetch(irradiance_field, ivec2(7, 1), 0).xyz * _9347)) + (texelFetch(irradiance_field, ivec2(8, 1), 0).xyz * _9363), vec3(0.0)), _8375);
        }
        else
        {
            _24848 = _24842;
            _24847 = _8357;
        }
        highp float _9899 = 0.0;
        highp vec3 _8386 = _24847 * frag_info.environment_intensity;
        float _24849 = 0.0;
        do
        {
            _9899 = frag_info.gi_grid.w;
            if (_9899 <= 0.0)
            {
                _24849 = 0.0;
                break;
            }
            highp vec3 _9912 = (v_position / frag_info.gi_grid.xyz) - frag_info.gi_anchor.xyz;
            highp vec3 _9920 = min(_9912, (frag_info.gi_counts.xyz - vec3(1.0)) - _9912);
            _24849 = clamp(min(_9920.x, min(_9920.y, _9920.z)) / max(frag_info.gi_visibility.w, 0.001000000047497451305389404296875), 0.0, 1.0);
            break;
        } while(false);
        highp vec3 _25040 = vec3(0.0);
        if (_24849 > 0.0)
        {
            highp vec3 _10012 = v_position + (((_24769 * 0.20000000298023223876953125) + (mp_copy_24830 * 0.800000011920928955078125)) * ((0.75 * min(frag_info.gi_grid.x, min(frag_info.gi_grid.y, frag_info.gi_grid.z))) * frag_info.gi_anchor.w));
            highp vec3 _10015 = _10012 / frag_info.gi_grid.xyz;
            highp vec3 _10017 = floor(_10015);
            highp vec3 _10023 = clamp(_10015 - _10017, vec3(0.0), vec3(1.0));
            vec3 mp_copy_10023 = _10023;
            highp vec3 _10145 = _10017 - frag_info.gi_anchor.xyz;
            bool _10148 = any(lessThan(_10145, vec3(0.0)));
            bool _10156 = false;
            if (!_10148)
            {
                _10156 = any(greaterThanEqual(_10145, frag_info.gi_counts.xyz));
            }
            else
            {
                _10156 = _10148;
            }
            vec3 mp_copy_24850 = vec3(0.0);
            highp float _10157 = _10156 ? 0.0 : 1.0;
            float mp_copy_10157 = _10157;
            vec3 _10159 = vec3(1.0) - mp_copy_10023;
            vec3 _10163 = max(_10159, vec3(0.001000000047497451305389404296875));
            highp vec3 _10179 = (_10017 * frag_info.gi_grid.xyz) - _10012;
            highp float _10181 = length(_10179);
            highp vec3 _24850 = vec3(0.0);
            if (_10181 > 9.9999997473787516355514526367188e-06)
            {
                _24850 = _10179 / vec3(_10181);
            }
            else
            {
                _24850 = _24769;
            }
            mp_copy_24850 = _24850;
            float _10199 = pow((dot(_24850, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10324 = _10017 - (frag_info.gi_counts.xyz * floor(_10017 / frag_info.gi_counts.xyz));
            highp float _10340 = _10324.x + (frag_info.gi_counts.x * (_10324.y + (frag_info.gi_counts.y * _10324.z)));
            bool _10210 = frag_info.gi_visibility.x > 0.0;
            float _24855 = 0.0;
            if (_10210)
            {
                highp float _10348 = floor(_10340 / frag_info.gi_counts.w);
                highp vec2 _10362 = vec2((_10340 - (_10348 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10348 * 16.0));
                vec3 _10222 = -mp_copy_24850;
                vec3 _10410 = _10222 / vec3((abs(_10222.x) + abs(_10222.y)) + abs(_10222.z));
                vec2 _24851 = vec2(0.0);
                if (_10410.z >= 0.0)
                {
                    _24851 = _10410.xy;
                }
                else
                {
                    _24851 = (vec2(1.0) - abs(_10410.yx)) * vec2((_10410.x >= 0.0) ? 1.0 : (-1.0), (_10410.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10226 = texture(irradiance_field, clamp((_10362 + vec2(1.0)) + (clamp((_24851 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10362 + vec2(0.5), _10362 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10231 = _10226.x * frag_info.gi_visibility.z;
                highp float _10243 = abs((_10231 * _10231) - ((_10226.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10249 = (_10181 - _10231) - frag_info.gi_visibility.y;
                highp float _24852 = 0.0;
                if (_10249 <= 0.0)
                {
                    _24852 = 1.0;
                }
                else
                {
                    _24852 = _10243 / (_10243 + (_10249 * _10249));
                }
                _24855 = _10199 * mix(1.0, max(0.0500000007450580596923828125, (_24852 * _24852) * _24852), frag_info.gi_visibility.x);
            }
            else
            {
                _24855 = _10199;
            }
            float _10277 = max(9.9999999747524270787835121154785e-07, _24855);
            float _24856 = 0.0;
            if (_10277 < 0.20000000298023223876953125)
            {
                _24856 = _10277 * ((_10277 * _10277) * 25.0);
            }
            else
            {
                _24856 = _10277;
            }
            float _10292 = _24856 * (((_10163.x * _10163.y) * _10163.z) * mp_copy_10157);
            highp float _10451 = floor(_10340 / frag_info.gi_counts.w);
            highp vec2 _10465 = vec2((_10340 - (_10451 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10451 * 8.0));
            vec3 _10513 = _24769 / vec3((abs(_24769.x) + abs(_24769.y)) + abs(_24769.z));
            bool _10516 = _10513.z >= 0.0;
            vec2 _24857 = vec2(0.0);
            if (_10516)
            {
                _24857 = _10513.xy;
            }
            else
            {
                _24857 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10304 = texture(irradiance_field, clamp((_10465 + vec2(1.0)) + (clamp((_24857 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10465 + vec2(0.5), _10465 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _10599 = _10017 + vec3(1.0, 0.0, 0.0);
            highp vec3 _10604 = _10599 - frag_info.gi_anchor.xyz;
            bool _10607 = any(lessThan(_10604, vec3(0.0)));
            bool _10615 = false;
            if (!_10607)
            {
                _10615 = any(greaterThanEqual(_10604, frag_info.gi_counts.xyz));
            }
            else
            {
                _10615 = _10607;
            }
            vec3 mp_copy_24859 = vec3(0.0);
            highp float _10616 = _10615 ? 0.0 : 1.0;
            float mp_copy_10616 = _10616;
            vec3 _10622 = max(mix(_10159, mp_copy_10023, vec3(1.0, 0.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _10638 = (_10599 * frag_info.gi_grid.xyz) - _10012;
            highp float _10640 = length(_10638);
            highp vec3 _24859 = vec3(0.0);
            if (_10640 > 9.9999997473787516355514526367188e-06)
            {
                _24859 = _10638 / vec3(_10640);
            }
            else
            {
                _24859 = _24769;
            }
            mp_copy_24859 = _24859;
            float _10658 = pow((dot(_24859, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _10783 = _10599 - (frag_info.gi_counts.xyz * floor(_10599 / frag_info.gi_counts.xyz));
            highp float _10799 = _10783.x + (frag_info.gi_counts.x * (_10783.y + (frag_info.gi_counts.y * _10783.z)));
            float _24864 = 0.0;
            if (_10210)
            {
                highp float _10807 = floor(_10799 / frag_info.gi_counts.w);
                highp vec2 _10821 = vec2((_10799 - (_10807 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_10807 * 16.0));
                vec3 _10681 = -mp_copy_24859;
                vec3 _10869 = _10681 / vec3((abs(_10681.x) + abs(_10681.y)) + abs(_10681.z));
                vec2 _24860 = vec2(0.0);
                if (_10869.z >= 0.0)
                {
                    _24860 = _10869.xy;
                }
                else
                {
                    _24860 = (vec2(1.0) - abs(_10869.yx)) * vec2((_10869.x >= 0.0) ? 1.0 : (-1.0), (_10869.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _10685 = texture(irradiance_field, clamp((_10821 + vec2(1.0)) + (clamp((_24860 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _10821 + vec2(0.5), _10821 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _10690 = _10685.x * frag_info.gi_visibility.z;
                highp float _10702 = abs((_10690 * _10690) - ((_10685.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _10708 = (_10640 - _10690) - frag_info.gi_visibility.y;
                highp float _24861 = 0.0;
                if (_10708 <= 0.0)
                {
                    _24861 = 1.0;
                }
                else
                {
                    _24861 = _10702 / (_10702 + (_10708 * _10708));
                }
                _24864 = _10658 * mix(1.0, max(0.0500000007450580596923828125, (_24861 * _24861) * _24861), frag_info.gi_visibility.x);
            }
            else
            {
                _24864 = _10658;
            }
            float _10736 = max(9.9999999747524270787835121154785e-07, _24864);
            float _24865 = 0.0;
            if (_10736 < 0.20000000298023223876953125)
            {
                _24865 = _10736 * ((_10736 * _10736) * 25.0);
            }
            else
            {
                _24865 = _10736;
            }
            float _10751 = _24865 * (((_10622.x * _10622.y) * _10622.z) * mp_copy_10616);
            highp float _10910 = floor(_10799 / frag_info.gi_counts.w);
            highp vec2 _10924 = vec2((_10799 - (_10910 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_10910 * 8.0));
            vec2 _24866 = vec2(0.0);
            if (_10516)
            {
                _24866 = _10513.xy;
            }
            else
            {
                _24866 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10763 = texture(irradiance_field, clamp((_10924 + vec2(1.0)) + (clamp((_24866 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _10924 + vec2(0.5), _10924 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11058 = _10017 + vec3(0.0, 1.0, 0.0);
            highp vec3 _11063 = _11058 - frag_info.gi_anchor.xyz;
            bool _11066 = any(lessThan(_11063, vec3(0.0)));
            bool _11074 = false;
            if (!_11066)
            {
                _11074 = any(greaterThanEqual(_11063, frag_info.gi_counts.xyz));
            }
            else
            {
                _11074 = _11066;
            }
            vec3 mp_copy_24868 = vec3(0.0);
            highp float _11075 = _11074 ? 0.0 : 1.0;
            float mp_copy_11075 = _11075;
            vec3 _11081 = max(mix(_10159, mp_copy_10023, vec3(0.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11097 = (_11058 * frag_info.gi_grid.xyz) - _10012;
            highp float _11099 = length(_11097);
            highp vec3 _24868 = vec3(0.0);
            if (_11099 > 9.9999997473787516355514526367188e-06)
            {
                _24868 = _11097 / vec3(_11099);
            }
            else
            {
                _24868 = _24769;
            }
            mp_copy_24868 = _24868;
            float _11117 = pow((dot(_24868, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11242 = _11058 - (frag_info.gi_counts.xyz * floor(_11058 / frag_info.gi_counts.xyz));
            highp float _11258 = _11242.x + (frag_info.gi_counts.x * (_11242.y + (frag_info.gi_counts.y * _11242.z)));
            float _24873 = 0.0;
            if (_10210)
            {
                highp float _11266 = floor(_11258 / frag_info.gi_counts.w);
                highp vec2 _11280 = vec2((_11258 - (_11266 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11266 * 16.0));
                vec3 _11140 = -mp_copy_24868;
                vec3 _11328 = _11140 / vec3((abs(_11140.x) + abs(_11140.y)) + abs(_11140.z));
                vec2 _24869 = vec2(0.0);
                if (_11328.z >= 0.0)
                {
                    _24869 = _11328.xy;
                }
                else
                {
                    _24869 = (vec2(1.0) - abs(_11328.yx)) * vec2((_11328.x >= 0.0) ? 1.0 : (-1.0), (_11328.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11144 = texture(irradiance_field, clamp((_11280 + vec2(1.0)) + (clamp((_24869 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11280 + vec2(0.5), _11280 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11149 = _11144.x * frag_info.gi_visibility.z;
                highp float _11161 = abs((_11149 * _11149) - ((_11144.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11167 = (_11099 - _11149) - frag_info.gi_visibility.y;
                highp float _24870 = 0.0;
                if (_11167 <= 0.0)
                {
                    _24870 = 1.0;
                }
                else
                {
                    _24870 = _11161 / (_11161 + (_11167 * _11167));
                }
                _24873 = _11117 * mix(1.0, max(0.0500000007450580596923828125, (_24870 * _24870) * _24870), frag_info.gi_visibility.x);
            }
            else
            {
                _24873 = _11117;
            }
            float _11195 = max(9.9999999747524270787835121154785e-07, _24873);
            float _24874 = 0.0;
            if (_11195 < 0.20000000298023223876953125)
            {
                _24874 = _11195 * ((_11195 * _11195) * 25.0);
            }
            else
            {
                _24874 = _11195;
            }
            float _11210 = _24874 * (((_11081.x * _11081.y) * _11081.z) * mp_copy_11075);
            highp float _11369 = floor(_11258 / frag_info.gi_counts.w);
            highp vec2 _11383 = vec2((_11258 - (_11369 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11369 * 8.0));
            vec2 _24875 = vec2(0.0);
            if (_10516)
            {
                _24875 = _10513.xy;
            }
            else
            {
                _24875 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11222 = texture(irradiance_field, clamp((_11383 + vec2(1.0)) + (clamp((_24875 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11383 + vec2(0.5), _11383 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11517 = _10017 + vec3(1.0, 1.0, 0.0);
            highp vec3 _11522 = _11517 - frag_info.gi_anchor.xyz;
            bool _11525 = any(lessThan(_11522, vec3(0.0)));
            bool _11533 = false;
            if (!_11525)
            {
                _11533 = any(greaterThanEqual(_11522, frag_info.gi_counts.xyz));
            }
            else
            {
                _11533 = _11525;
            }
            vec3 mp_copy_24877 = vec3(0.0);
            highp float _11534 = _11533 ? 0.0 : 1.0;
            float mp_copy_11534 = _11534;
            vec3 _11540 = max(mix(_10159, mp_copy_10023, vec3(1.0, 1.0, 0.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _11556 = (_11517 * frag_info.gi_grid.xyz) - _10012;
            highp float _11558 = length(_11556);
            highp vec3 _24877 = vec3(0.0);
            if (_11558 > 9.9999997473787516355514526367188e-06)
            {
                _24877 = _11556 / vec3(_11558);
            }
            else
            {
                _24877 = _24769;
            }
            mp_copy_24877 = _24877;
            float _11576 = pow((dot(_24877, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _11701 = _11517 - (frag_info.gi_counts.xyz * floor(_11517 / frag_info.gi_counts.xyz));
            highp float _11717 = _11701.x + (frag_info.gi_counts.x * (_11701.y + (frag_info.gi_counts.y * _11701.z)));
            float _24882 = 0.0;
            if (_10210)
            {
                highp float _11725 = floor(_11717 / frag_info.gi_counts.w);
                highp vec2 _11739 = vec2((_11717 - (_11725 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_11725 * 16.0));
                vec3 _11599 = -mp_copy_24877;
                vec3 _11787 = _11599 / vec3((abs(_11599.x) + abs(_11599.y)) + abs(_11599.z));
                vec2 _24878 = vec2(0.0);
                if (_11787.z >= 0.0)
                {
                    _24878 = _11787.xy;
                }
                else
                {
                    _24878 = (vec2(1.0) - abs(_11787.yx)) * vec2((_11787.x >= 0.0) ? 1.0 : (-1.0), (_11787.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _11603 = texture(irradiance_field, clamp((_11739 + vec2(1.0)) + (clamp((_24878 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _11739 + vec2(0.5), _11739 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _11608 = _11603.x * frag_info.gi_visibility.z;
                highp float _11620 = abs((_11608 * _11608) - ((_11603.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _11626 = (_11558 - _11608) - frag_info.gi_visibility.y;
                highp float _24879 = 0.0;
                if (_11626 <= 0.0)
                {
                    _24879 = 1.0;
                }
                else
                {
                    _24879 = _11620 / (_11620 + (_11626 * _11626));
                }
                _24882 = _11576 * mix(1.0, max(0.0500000007450580596923828125, (_24879 * _24879) * _24879), frag_info.gi_visibility.x);
            }
            else
            {
                _24882 = _11576;
            }
            float _11654 = max(9.9999999747524270787835121154785e-07, _24882);
            float _24883 = 0.0;
            if (_11654 < 0.20000000298023223876953125)
            {
                _24883 = _11654 * ((_11654 * _11654) * 25.0);
            }
            else
            {
                _24883 = _11654;
            }
            float _11669 = _24883 * (((_11540.x * _11540.y) * _11540.z) * mp_copy_11534);
            highp float _11828 = floor(_11717 / frag_info.gi_counts.w);
            highp vec2 _11842 = vec2((_11717 - (_11828 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_11828 * 8.0));
            vec2 _24884 = vec2(0.0);
            if (_10516)
            {
                _24884 = _10513.xy;
            }
            else
            {
                _24884 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _11681 = texture(irradiance_field, clamp((_11842 + vec2(1.0)) + (clamp((_24884 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _11842 + vec2(0.5), _11842 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _11976 = _10017 + vec3(0.0, 0.0, 1.0);
            highp vec3 _11981 = _11976 - frag_info.gi_anchor.xyz;
            bool _11984 = any(lessThan(_11981, vec3(0.0)));
            bool _11992 = false;
            if (!_11984)
            {
                _11992 = any(greaterThanEqual(_11981, frag_info.gi_counts.xyz));
            }
            else
            {
                _11992 = _11984;
            }
            vec3 mp_copy_24886 = vec3(0.0);
            highp float _11993 = _11992 ? 0.0 : 1.0;
            float mp_copy_11993 = _11993;
            vec3 _11999 = max(mix(_10159, mp_copy_10023, vec3(0.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12015 = (_11976 * frag_info.gi_grid.xyz) - _10012;
            highp float _12017 = length(_12015);
            highp vec3 _24886 = vec3(0.0);
            if (_12017 > 9.9999997473787516355514526367188e-06)
            {
                _24886 = _12015 / vec3(_12017);
            }
            else
            {
                _24886 = _24769;
            }
            mp_copy_24886 = _24886;
            float _12035 = pow((dot(_24886, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12160 = _11976 - (frag_info.gi_counts.xyz * floor(_11976 / frag_info.gi_counts.xyz));
            highp float _12176 = _12160.x + (frag_info.gi_counts.x * (_12160.y + (frag_info.gi_counts.y * _12160.z)));
            float _24891 = 0.0;
            if (_10210)
            {
                highp float _12184 = floor(_12176 / frag_info.gi_counts.w);
                highp vec2 _12198 = vec2((_12176 - (_12184 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12184 * 16.0));
                vec3 _12058 = -mp_copy_24886;
                vec3 _12246 = _12058 / vec3((abs(_12058.x) + abs(_12058.y)) + abs(_12058.z));
                vec2 _24887 = vec2(0.0);
                if (_12246.z >= 0.0)
                {
                    _24887 = _12246.xy;
                }
                else
                {
                    _24887 = (vec2(1.0) - abs(_12246.yx)) * vec2((_12246.x >= 0.0) ? 1.0 : (-1.0), (_12246.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12062 = texture(irradiance_field, clamp((_12198 + vec2(1.0)) + (clamp((_24887 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12198 + vec2(0.5), _12198 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12067 = _12062.x * frag_info.gi_visibility.z;
                highp float _12079 = abs((_12067 * _12067) - ((_12062.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12085 = (_12017 - _12067) - frag_info.gi_visibility.y;
                highp float _24888 = 0.0;
                if (_12085 <= 0.0)
                {
                    _24888 = 1.0;
                }
                else
                {
                    _24888 = _12079 / (_12079 + (_12085 * _12085));
                }
                _24891 = _12035 * mix(1.0, max(0.0500000007450580596923828125, (_24888 * _24888) * _24888), frag_info.gi_visibility.x);
            }
            else
            {
                _24891 = _12035;
            }
            float _12113 = max(9.9999999747524270787835121154785e-07, _24891);
            float _24892 = 0.0;
            if (_12113 < 0.20000000298023223876953125)
            {
                _24892 = _12113 * ((_12113 * _12113) * 25.0);
            }
            else
            {
                _24892 = _12113;
            }
            float _12128 = _24892 * (((_11999.x * _11999.y) * _11999.z) * mp_copy_11993);
            highp float _12287 = floor(_12176 / frag_info.gi_counts.w);
            highp vec2 _12301 = vec2((_12176 - (_12287 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12287 * 8.0));
            vec2 _24893 = vec2(0.0);
            if (_10516)
            {
                _24893 = _10513.xy;
            }
            else
            {
                _24893 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12140 = texture(irradiance_field, clamp((_12301 + vec2(1.0)) + (clamp((_24893 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12301 + vec2(0.5), _12301 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12435 = _10017 + vec3(1.0, 0.0, 1.0);
            highp vec3 _12440 = _12435 - frag_info.gi_anchor.xyz;
            bool _12443 = any(lessThan(_12440, vec3(0.0)));
            bool _12451 = false;
            if (!_12443)
            {
                _12451 = any(greaterThanEqual(_12440, frag_info.gi_counts.xyz));
            }
            else
            {
                _12451 = _12443;
            }
            vec3 mp_copy_24895 = vec3(0.0);
            highp float _12452 = _12451 ? 0.0 : 1.0;
            float mp_copy_12452 = _12452;
            vec3 _12458 = max(mix(_10159, mp_copy_10023, vec3(1.0, 0.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12474 = (_12435 * frag_info.gi_grid.xyz) - _10012;
            highp float _12476 = length(_12474);
            highp vec3 _24895 = vec3(0.0);
            if (_12476 > 9.9999997473787516355514526367188e-06)
            {
                _24895 = _12474 / vec3(_12476);
            }
            else
            {
                _24895 = _24769;
            }
            mp_copy_24895 = _24895;
            float _12494 = pow((dot(_24895, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _12619 = _12435 - (frag_info.gi_counts.xyz * floor(_12435 / frag_info.gi_counts.xyz));
            highp float _12635 = _12619.x + (frag_info.gi_counts.x * (_12619.y + (frag_info.gi_counts.y * _12619.z)));
            float _24900 = 0.0;
            if (_10210)
            {
                highp float _12643 = floor(_12635 / frag_info.gi_counts.w);
                highp vec2 _12657 = vec2((_12635 - (_12643 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_12643 * 16.0));
                vec3 _12517 = -mp_copy_24895;
                vec3 _12705 = _12517 / vec3((abs(_12517.x) + abs(_12517.y)) + abs(_12517.z));
                vec2 _24896 = vec2(0.0);
                if (_12705.z >= 0.0)
                {
                    _24896 = _12705.xy;
                }
                else
                {
                    _24896 = (vec2(1.0) - abs(_12705.yx)) * vec2((_12705.x >= 0.0) ? 1.0 : (-1.0), (_12705.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12521 = texture(irradiance_field, clamp((_12657 + vec2(1.0)) + (clamp((_24896 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _12657 + vec2(0.5), _12657 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12526 = _12521.x * frag_info.gi_visibility.z;
                highp float _12538 = abs((_12526 * _12526) - ((_12521.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _12544 = (_12476 - _12526) - frag_info.gi_visibility.y;
                highp float _24897 = 0.0;
                if (_12544 <= 0.0)
                {
                    _24897 = 1.0;
                }
                else
                {
                    _24897 = _12538 / (_12538 + (_12544 * _12544));
                }
                _24900 = _12494 * mix(1.0, max(0.0500000007450580596923828125, (_24897 * _24897) * _24897), frag_info.gi_visibility.x);
            }
            else
            {
                _24900 = _12494;
            }
            float _12572 = max(9.9999999747524270787835121154785e-07, _24900);
            float _24901 = 0.0;
            if (_12572 < 0.20000000298023223876953125)
            {
                _24901 = _12572 * ((_12572 * _12572) * 25.0);
            }
            else
            {
                _24901 = _12572;
            }
            float _12587 = _24901 * (((_12458.x * _12458.y) * _12458.z) * mp_copy_12452);
            highp float _12746 = floor(_12635 / frag_info.gi_counts.w);
            highp vec2 _12760 = vec2((_12635 - (_12746 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_12746 * 8.0));
            vec2 _24902 = vec2(0.0);
            if (_10516)
            {
                _24902 = _10513.xy;
            }
            else
            {
                _24902 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _12599 = texture(irradiance_field, clamp((_12760 + vec2(1.0)) + (clamp((_24902 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _12760 + vec2(0.5), _12760 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _12894 = _10017 + vec3(0.0, 1.0, 1.0);
            highp vec3 _12899 = _12894 - frag_info.gi_anchor.xyz;
            bool _12902 = any(lessThan(_12899, vec3(0.0)));
            bool _12910 = false;
            if (!_12902)
            {
                _12910 = any(greaterThanEqual(_12899, frag_info.gi_counts.xyz));
            }
            else
            {
                _12910 = _12902;
            }
            vec3 mp_copy_24904 = vec3(0.0);
            highp float _12911 = _12910 ? 0.0 : 1.0;
            float mp_copy_12911 = _12911;
            vec3 _12917 = max(mix(_10159, mp_copy_10023, vec3(0.0, 1.0, 1.0)), vec3(0.001000000047497451305389404296875));
            highp vec3 _12933 = (_12894 * frag_info.gi_grid.xyz) - _10012;
            highp float _12935 = length(_12933);
            highp vec3 _24904 = vec3(0.0);
            if (_12935 > 9.9999997473787516355514526367188e-06)
            {
                _24904 = _12933 / vec3(_12935);
            }
            else
            {
                _24904 = _24769;
            }
            mp_copy_24904 = _24904;
            float _12953 = pow((dot(_24904, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13078 = _12894 - (frag_info.gi_counts.xyz * floor(_12894 / frag_info.gi_counts.xyz));
            highp float _13094 = _13078.x + (frag_info.gi_counts.x * (_13078.y + (frag_info.gi_counts.y * _13078.z)));
            float _24909 = 0.0;
            if (_10210)
            {
                highp float _13102 = floor(_13094 / frag_info.gi_counts.w);
                highp vec2 _13116 = vec2((_13094 - (_13102 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13102 * 16.0));
                vec3 _12976 = -mp_copy_24904;
                vec3 _13164 = _12976 / vec3((abs(_12976.x) + abs(_12976.y)) + abs(_12976.z));
                vec2 _24905 = vec2(0.0);
                if (_13164.z >= 0.0)
                {
                    _24905 = _13164.xy;
                }
                else
                {
                    _24905 = (vec2(1.0) - abs(_13164.yx)) * vec2((_13164.x >= 0.0) ? 1.0 : (-1.0), (_13164.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _12980 = texture(irradiance_field, clamp((_13116 + vec2(1.0)) + (clamp((_24905 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13116 + vec2(0.5), _13116 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _12985 = _12980.x * frag_info.gi_visibility.z;
                highp float _12997 = abs((_12985 * _12985) - ((_12980.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _13003 = (_12935 - _12985) - frag_info.gi_visibility.y;
                highp float _24906 = 0.0;
                if (_13003 <= 0.0)
                {
                    _24906 = 1.0;
                }
                else
                {
                    _24906 = _12997 / (_12997 + (_13003 * _13003));
                }
                _24909 = _12953 * mix(1.0, max(0.0500000007450580596923828125, (_24906 * _24906) * _24906), frag_info.gi_visibility.x);
            }
            else
            {
                _24909 = _12953;
            }
            float _13031 = max(9.9999999747524270787835121154785e-07, _24909);
            float _24910 = 0.0;
            if (_13031 < 0.20000000298023223876953125)
            {
                _24910 = _13031 * ((_13031 * _13031) * 25.0);
            }
            else
            {
                _24910 = _13031;
            }
            float _13046 = _24910 * (((_12917.x * _12917.y) * _12917.z) * mp_copy_12911);
            highp float _13205 = floor(_13094 / frag_info.gi_counts.w);
            highp vec2 _13219 = vec2((_13094 - (_13205 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13205 * 8.0));
            vec2 _24911 = vec2(0.0);
            if (_10516)
            {
                _24911 = _10513.xy;
            }
            else
            {
                _24911 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _13058 = texture(irradiance_field, clamp((_13219 + vec2(1.0)) + (clamp((_24911 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13219 + vec2(0.5), _13219 + vec2(7.5)) * frag_info.gi_atlas.zw);
            highp vec3 _13353 = _10017 + vec3(1.0);
            highp vec3 _13358 = _13353 - frag_info.gi_anchor.xyz;
            bool _13361 = any(lessThan(_13358, vec3(0.0)));
            bool _13369 = false;
            if (!_13361)
            {
                _13369 = any(greaterThanEqual(_13358, frag_info.gi_counts.xyz));
            }
            else
            {
                _13369 = _13361;
            }
            vec3 mp_copy_24913 = vec3(0.0);
            highp float _13370 = _13369 ? 0.0 : 1.0;
            float mp_copy_13370 = _13370;
            vec3 _13376 = max(mp_copy_10023, vec3(0.001000000047497451305389404296875));
            highp vec3 _13392 = (_13353 * frag_info.gi_grid.xyz) - _10012;
            highp float _13394 = length(_13392);
            highp vec3 _24913 = vec3(0.0);
            if (_13394 > 9.9999997473787516355514526367188e-06)
            {
                _24913 = _13392 / vec3(_13394);
            }
            else
            {
                _24913 = _24769;
            }
            mp_copy_24913 = _24913;
            float _13412 = pow((dot(_24913, _24769) * 0.5) + 0.5, 2.0) + 0.20000000298023223876953125;
            highp vec3 _13537 = _13353 - (frag_info.gi_counts.xyz * floor(_13353 / frag_info.gi_counts.xyz));
            highp float _13553 = _13537.x + (frag_info.gi_counts.x * (_13537.y + (frag_info.gi_counts.y * _13537.z)));
            float _24918 = 0.0;
            if (_10210)
            {
                highp float _13561 = floor(_13553 / frag_info.gi_counts.w);
                highp vec2 _13575 = vec2((_13553 - (_13561 * frag_info.gi_counts.w)) * 16.0, frag_info.gi_atlas.y + (_13561 * 16.0));
                vec3 _13435 = -mp_copy_24913;
                vec3 _13623 = _13435 / vec3((abs(_13435.x) + abs(_13435.y)) + abs(_13435.z));
                vec2 _24914 = vec2(0.0);
                if (_13623.z >= 0.0)
                {
                    _24914 = _13623.xy;
                }
                else
                {
                    _24914 = (vec2(1.0) - abs(_13623.yx)) * vec2((_13623.x >= 0.0) ? 1.0 : (-1.0), (_13623.y >= 0.0) ? 1.0 : (-1.0));
                }
                highp vec4 _13439 = texture(irradiance_field, clamp((_13575 + vec2(1.0)) + (clamp((_24914 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 14.0), _13575 + vec2(0.5), _13575 + vec2(15.5)) * frag_info.gi_atlas.zw);
                highp float _13444 = _13439.x * frag_info.gi_visibility.z;
                highp float _13456 = abs((_13444 * _13444) - ((_13439.y * frag_info.gi_visibility.z) * frag_info.gi_visibility.z));
                highp float _13462 = (_13394 - _13444) - frag_info.gi_visibility.y;
                highp float _24915 = 0.0;
                if (_13462 <= 0.0)
                {
                    _24915 = 1.0;
                }
                else
                {
                    _24915 = _13456 / (_13456 + (_13462 * _13462));
                }
                _24918 = _13412 * mix(1.0, max(0.0500000007450580596923828125, (_24915 * _24915) * _24915), frag_info.gi_visibility.x);
            }
            else
            {
                _24918 = _13412;
            }
            float _13490 = max(9.9999999747524270787835121154785e-07, _24918);
            float _24919 = 0.0;
            if (_13490 < 0.20000000298023223876953125)
            {
                _24919 = _13490 * ((_13490 * _13490) * 25.0);
            }
            else
            {
                _24919 = _13490;
            }
            float _13505 = _24919 * (((_13376.x * _13376.y) * _13376.z) * mp_copy_13370);
            highp float _13664 = floor(_13553 / frag_info.gi_counts.w);
            highp vec2 _13678 = vec2((_13553 - (_13664 * frag_info.gi_counts.w)) * 8.0, frag_info.gi_atlas.x + (_13664 * 8.0));
            vec2 _24920 = vec2(0.0);
            if (_10516)
            {
                _24920 = _10513.xy;
            }
            else
            {
                _24920 = (vec2(1.0) - abs(_10513.yx)) * vec2((_10513.x >= 0.0) ? 1.0 : (-1.0), (_10513.y >= 0.0) ? 1.0 : (-1.0));
            }
            highp vec4 _10070 = ((((((vec4(max(_10304.xyz, vec3(0.0)) * _10292, _10292) + vec4(max(_10763.xyz, vec3(0.0)) * _10751, _10751)) + vec4(max(_11222.xyz, vec3(0.0)) * _11210, _11210)) + vec4(max(_11681.xyz, vec3(0.0)) * _11669, _11669)) + vec4(max(_12140.xyz, vec3(0.0)) * _12128, _12128)) + vec4(max(_12599.xyz, vec3(0.0)) * _12587, _12587)) + vec4(max(_13058.xyz, vec3(0.0)) * _13046, _13046)) + vec4(max(texture(irradiance_field, clamp((_13678 + vec2(1.0)) + (clamp((_24920 * 0.5) + vec2(0.5), vec2(0.0), vec2(1.0)) * 6.0), _13678 + vec2(0.5), _13678 + vec2(7.5)) * frag_info.gi_atlas.zw).xyz, vec3(0.0)) * _13505, _13505);
            highp float _10072 = _10070.w;
            highp vec3 _24922 = vec3(0.0);
            if (_10072 > 9.9999999747524270787835121154785e-07)
            {
                _24922 = _10070.xyz / vec3(_10072);
            }
            else
            {
                _24922 = vec3(0.0);
            }
            _25040 = mix(_8386, _24922 * _9899, vec3(_24849));
        }
        else
        {
            _25040 = _8386;
        }
        vec2 _8412 = clamp(vec2(_8324, _24822), vec2(0.0), vec2(0.9900000095367431640625));
        vec4 _8414 = texture(brdf_lut, vec2(_8412.x * 0.3333333432674407958984375, _8412.y));
        float _8418 = _8414.x;
        float _8421 = _8414.y;
        vec3 _8423 = ((_8316 + ((max(vec3(1.0 - _24822), _8316) - _8316) * pow(clamp(1.0 - _8324, 0.0, 1.0), 5.0))) * _8418) + vec3(_8421);
        float _8429 = 1.0 - (_8418 + _8421);
        vec3 _8433 = vec3(1.0) - _8316;
        vec3 _8436 = _8316 + (_8433 * vec3(0.0476190485060214996337890625));
        vec3 _8447 = ((_8423 * _8429) * _8436) / (vec3(1.0) - (_8436 * _8429));
        float _8450 = 1.0 - _7319;
        vec3 _8451 = _8221 * _8450;
        float _25778 = 0.0;
        if ((frag_info.ssao_params.y > 1.5) && _8344)
        {
            float _13786 = max(acos(clamp(exp2(((-3.321929931640625) * _24822) * _24822), 0.0, 1.0)), 0.100000001490116119384765625);
            _25778 = 1.0 - smoothstep(0.0, 1.0, clamp(((acos(clamp(dot(_24837, _8328), -1.0, 1.0)) - acos(sqrt(clamp(1.0 - _25110, 0.0, 1.0)))) + _13786) / (2.0 * _13786), 0.0, 1.0));
        }
        else
        {
            float _25779 = 0.0;
            if (frag_info.ssao_params.y > 0.5)
            {
                _25779 = clamp((pow(_8320 + _25110, exp2(((-16.0) * _24822) - 1.0)) - 1.0) + _25110, 0.0, 1.0);
            }
            else
            {
                _25779 = _25110;
            }
            _25778 = _25779;
        }
        bool _8500 = frag_info.has_directional_light > 0.5;
        float _25232 = 0.0;
        vec3 _25862 = vec3(0.0);
        if (_8500)
        {
            highp vec3 _8506 = -normalize(frag_info.directional_light_direction.xyz);
            _25862 = _8506;
            _25232 = dot(_7186, _8506);
        }
        else
        {
            _25862 = vec3(0.0);
            _25232 = 0.0;
        }
        float _8513 = clamp(_25232 * 6.666666507720947265625, 0.0, 1.0);
        bool _8522 = false;
        if (_8500)
        {
            _8522 = frag_info.casts_shadow > 0.5;
        }
        else
        {
            _8522 = _8500;
        }
        float _25469 = 0.0;
        if (_8522 && (_8513 > 0.0))
        {
            int _13907 = int(frag_info.shadow_cascade_count);
            float _14356 = max(dot(_7186, -normalize(frag_info.directional_light_direction.xyz)), 0.1500000059604644775390625);
            float _14359 = _14356 * _14356;
            highp vec3 _14379 = v_position + (_7186 * (frag_info.shadow_normal_bias + (frag_info.shadow_softness * min(sqrt(max(1.0 - _14359, 0.0)) / _14359, 8.0))));
            highp float _13913 = frag_info.directional_light_color.w * 0.5;
            float _25286 = 0.0;
            float _25326 = 0.0;
            if (_13907 > 0)
            {
                highp vec4 _13930 = frag_info.light_space_matrix[0] * vec4(_14379, 1.0);
                highp vec3 _13936 = _13930.xyz / vec3(_13930.w);
                highp vec2 _13939 = _13936.xy * 0.5;
                highp vec2 _13941 = _13939 + vec2(0.5);
                highp float _13948 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.x, frag_info.shadow_texel_size);
                highp float _13950 = _13941.x;
                bool _13952 = _13950 < _13948;
                bool _13961 = false;
                if (!_13952)
                {
                    _13961 = _13950 > (1.0 - _13948);
                }
                else
                {
                    _13961 = _13952;
                }
                bool _13969 = false;
                if (!_13961)
                {
                    _13969 = _13941.y < _13948;
                }
                else
                {
                    _13969 = _13961;
                }
                bool _13978 = false;
                if (!_13969)
                {
                    _13978 = _13941.y > (1.0 - _13948);
                }
                else
                {
                    _13978 = _13969;
                }
                bool _13985 = false;
                if (!_13978)
                {
                    _13985 = _13936.z < 0.0;
                }
                else
                {
                    _13985 = _13978;
                }
                bool _13992 = false;
                if (!_13985)
                {
                    _13992 = _13936.z > 1.0;
                }
                else
                {
                    _13992 = _13985;
                }
                float _25287 = 0.0;
                float _25327 = 0.0;
                if (!_13992)
                {
                    highp vec2 _14387 = vec2(_13948);
                    highp vec2 _14392 = vec2(_13948 + max(_13913, 9.9999997473787516355514526367188e-05));
                    highp vec2 _14400 = vec2(0.5) - _13939;
                    highp vec2 _14402 = smoothstep(_14387, _14392, _13941) * smoothstep(_14387, _14392, _14400);
                    float _25233 = 0.0;
                    if (_13913 > 0.0)
                    {
                        _25233 = _14402.x * _14402.y;
                    }
                    else
                    {
                        _25233 = 1.0;
                    }
                    float _14001 = min(_25233, 1.0);
                    bool _14003 = _14001 > 0.0;
                    float _25328 = 0.0;
                    if (_14003)
                    {
                        highp float _14514 = _13936.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.x));
                        highp float _14520 = 1.0 / (float(_13907) + frag_info.spot_shadow_params.x);
                        highp float _14522 = frag_info.directional_light_direction.w;
                        float mp_copy_14522 = _14522;
                        float _14528 = step(0.5, mp_copy_14522) * (1.0 - step(1.5, mp_copy_14522));
                        highp float _14539 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _14528);
                        float mp_copy_14539 = _14539;
                        float _14541 = cos(mp_copy_14539);
                        float _14543 = sin(mp_copy_14539);
                        highp float _25251 = 0.0;
                        if ((_14522 > 1.5) && (_14522 < 2.5))
                        {
                            highp float _14562 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _14567 = max(_14562 * _14514, frag_info.shadow_texel_size);
                            float _25241 = 0.0;
                            highp float _25242 = 0.0;
                            _25242 = 0.0;
                            _25241 = 0.0;
                            highp float _14589 = 0.0;
                            float _14592 = 0.0;
                            for (int _25240 = 0; _25240 < 9; _25242 = _14589, _25241 = _14592, _25240++)
                            {
                                vec2 _27748 = vec2(0.0);
                                do
                                {
                                    if (_25240 == 0)
                                    {
                                        _27748 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25240 == 1)
                                    {
                                        _27748 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25240 == 2)
                                    {
                                        _27748 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25240 == 3)
                                    {
                                        _27748 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25240 == 4)
                                    {
                                        _27748 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25240 == 5)
                                    {
                                        _27748 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25240 == 6)
                                    {
                                        _27748 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25240 == 7)
                                    {
                                        _27748 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25240 == 8)
                                    {
                                        _27748 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25240 == 9)
                                    {
                                        _27748 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25240 == 10)
                                    {
                                        _27748 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25240 == 11)
                                    {
                                        _27748 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25240 == 12)
                                    {
                                        _27748 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25240 == 13)
                                    {
                                        _27748 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25240 == 14)
                                    {
                                        _27748 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25240 == 15)
                                    {
                                        _27748 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27748 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _14834 = clamp(_13941 + (vec2((_27748.x * _14541) - (_27748.y * _14543), (_27748.x * _14543) + (_27748.y * _14541)) * _14567), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _14843 = _14834.y;
                                highp vec2 _14844 = vec2(_14834.x * _14520, _14843);
                                _14844.y = 1.0 - _14843;
                                highp vec4 _14851 = texture(shadow_map, _14844);
                                highp float _14852 = _14851.x;
                                highp float _14584 = step(_14852, _14514);
                                float mp_copy_14584 = _14584;
                                _14589 = _25242 + (_14852 * _14584);
                                _14592 = _25241 + mp_copy_14584;
                            }
                            highp float _25243 = 0.0;
                            if (_25241 > 0.0)
                            {
                                _25243 = _25242 / _25241;
                            }
                            else
                            {
                                _25243 = _14514;
                            }
                            _25251 = clamp(_14562 * max(_14514 - _25243, 0.0), frag_info.shadow_texel_size, _13948);
                        }
                        else
                        {
                            _25251 = _13948;
                        }
                        float _25258 = 0.0;
                        if (_14522 > 2.5)
                        {
                            highp vec2 _14880 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _14884 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _14885 = clamp(_13941 + (vec2(-0.707099974155426025390625) * _25251), _14880, _14884);
                            highp vec2 _14896 = (vec2(_14885.x, 1.0 - _14885.y) / _14880) - vec2(0.5);
                            highp vec2 _14898 = floor(_14896);
                            highp vec2 _14901 = _14896 - _14898;
                            highp vec2 _14906 = (_14898 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _14916 = vec2(_14906.x * _14520, _14906.y);
                            highp float _14920 = frag_info.shadow_texel_size * _14520;
                            highp vec2 _14923 = vec2(_14920, frag_info.shadow_texel_size);
                            highp vec2 _14932 = vec2(_14920, 0.0);
                            highp vec2 _14940 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _14969 = _14901.x;
                            highp float _14978 = mix(mix(float(_14514 <= texture(shadow_map, _14916).x), float(_14514 <= texture(shadow_map, _14916 + _14932).x), _14969), mix(float(_14514 <= texture(shadow_map, _14916 + _14940).x), float(_14514 <= texture(shadow_map, _14916 + _14923).x), _14969), _14901.y);
                            float mp_copy_14978 = _14978;
                            highp vec2 _15012 = clamp(_13941 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25251), _14880, _14884);
                            highp vec2 _15023 = (vec2(_15012.x, 1.0 - _15012.y) / _14880) - vec2(0.5);
                            highp vec2 _15025 = floor(_15023);
                            highp vec2 _15028 = _15023 - _15025;
                            highp vec2 _15033 = (_15025 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15043 = vec2(_15033.x * _14520, _15033.y);
                            highp float _15096 = _15028.x;
                            highp float _15105 = mix(mix(float(_14514 <= texture(shadow_map, _15043).x), float(_14514 <= texture(shadow_map, _15043 + _14932).x), _15096), mix(float(_14514 <= texture(shadow_map, _15043 + _14940).x), float(_14514 <= texture(shadow_map, _15043 + _14923).x), _15096), _15028.y);
                            float mp_copy_15105 = _15105;
                            highp vec2 _15139 = clamp(_13941 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25251), _14880, _14884);
                            highp vec2 _15150 = (vec2(_15139.x, 1.0 - _15139.y) / _14880) - vec2(0.5);
                            highp vec2 _15152 = floor(_15150);
                            highp vec2 _15155 = _15150 - _15152;
                            highp vec2 _15160 = (_15152 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15170 = vec2(_15160.x * _14520, _15160.y);
                            highp float _15223 = _15155.x;
                            highp float _15232 = mix(mix(float(_14514 <= texture(shadow_map, _15170).x), float(_14514 <= texture(shadow_map, _15170 + _14932).x), _15223), mix(float(_14514 <= texture(shadow_map, _15170 + _14940).x), float(_14514 <= texture(shadow_map, _15170 + _14923).x), _15223), _15155.y);
                            float mp_copy_15232 = _15232;
                            highp vec2 _15266 = clamp(_13941 + (vec2(0.707099974155426025390625) * _25251), _14880, _14884);
                            highp vec2 _15277 = (vec2(_15266.x, 1.0 - _15266.y) / _14880) - vec2(0.5);
                            highp vec2 _15279 = floor(_15277);
                            highp vec2 _15282 = _15277 - _15279;
                            highp vec2 _15287 = (_15279 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _15297 = vec2(_15287.x * _14520, _15287.y);
                            highp float _15350 = _15282.x;
                            highp float _15359 = mix(mix(float(_14514 <= texture(shadow_map, _15297).x), float(_14514 <= texture(shadow_map, _15297 + _14932).x), _15350), mix(float(_14514 <= texture(shadow_map, _15297 + _14940).x), float(_14514 <= texture(shadow_map, _15297 + _14923).x), _15350), _15282.y);
                            float mp_copy_15359 = _15359;
                            _25258 = (((mp_copy_14978 + mp_copy_15105) + mp_copy_15232) + mp_copy_15359) * 0.25;
                        }
                        else
                        {
                            int _14655 = (_14528 > 0.5) ? 17 : 16;
                            float _25254 = 0.0;
                            _25254 = 0.0;
                            float _14683 = 0.0;
                            for (int _25244 = 0; _25244 < 17; _25254 = _14683, _25244++)
                            {
                                if (_25244 >= _14655)
                                {
                                    break;
                                }
                                vec2 _25245 = vec2(0.0);
                                do
                                {
                                    if (_25244 == 0)
                                    {
                                        _25245 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25244 == 1)
                                    {
                                        _25245 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25244 == 2)
                                    {
                                        _25245 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25244 == 3)
                                    {
                                        _25245 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25244 == 4)
                                    {
                                        _25245 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25244 == 5)
                                    {
                                        _25245 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25244 == 6)
                                    {
                                        _25245 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25244 == 7)
                                    {
                                        _25245 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25244 == 8)
                                    {
                                        _25245 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25244 == 9)
                                    {
                                        _25245 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25244 == 10)
                                    {
                                        _25245 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25244 == 11)
                                    {
                                        _25245 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25244 == 12)
                                    {
                                        _25245 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25244 == 13)
                                    {
                                        _25245 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25244 == 14)
                                    {
                                        _25245 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25244 == 15)
                                    {
                                        _25245 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25245 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25247 = vec2(0.0);
                                do
                                {
                                    if (_25244 < 3)
                                    {
                                        _25247 = vec2(float(_25244) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25244 < 6)
                                    {
                                        _25247 = vec2((float(_25244 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25244 < 11)
                                    {
                                        _25247 = vec2((float(_25244 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25244 < 14)
                                    {
                                        _25247 = vec2((float(_25244 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25247 = vec2(float(_25244 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _14672 = mix(_25245, _25247, vec2(_14528));
                                float _15499 = _14672.x;
                                float _15503 = _14672.y;
                                highp vec2 _15529 = clamp(_13941 + (vec2((_15499 * _14541) - (_15503 * _14543), (_15499 * _14543) + (_15503 * _14541)) * _25251), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _15539 = vec2(_15529.x * _14520, _15529.y);
                                _15539.y = 1.0 - _15529.y;
                                highp float _15551 = float(_14514 <= texture(shadow_map, _15539).x);
                                float mp_copy_15551 = _15551;
                                _14683 = _25254 + mp_copy_15551;
                            }
                            _25258 = _25254 / float(_14655);
                        }
                        bool _14696 = 0 == (_13907 - 1);
                        bool _14702 = false;
                        if (_14696)
                        {
                            _14702 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _14702 = _14696;
                        }
                        float _25259 = 0.0;
                        if (_14702)
                        {
                            highp vec2 _14709 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.x);
                            highp vec2 _14717 = smoothstep(vec2(0.0), _14709, _13941) * smoothstep(vec2(0.0), _14709, _14400);
                            _25259 = mix(1.0, _25258, _14717.x * _14717.y);
                        }
                        else
                        {
                            _25259 = _25258;
                        }
                        _25328 = _14001 * _25259;
                    }
                    else
                    {
                        _25328 = 0.0;
                    }
                    _25327 = _25328;
                    _25287 = _14003 ? _14001 : 0.0;
                }
                else
                {
                    _25327 = 0.0;
                    _25287 = 0.0;
                }
                _25326 = _25327;
                _25286 = _25287;
            }
            else
            {
                _25326 = 0.0;
                _25286 = 0.0;
            }
            float _25345 = 0.0;
            float _25385 = 0.0;
            if ((_25286 < 1.0) && (_13907 > 1))
            {
                highp vec4 _14036 = frag_info.light_space_matrix[1] * vec4(_14379, 1.0);
                highp vec3 _14042 = _14036.xyz / vec3(_14036.w);
                highp vec2 _14045 = _14042.xy * 0.5;
                highp vec2 _14047 = _14045 + vec2(0.5);
                highp float _14054 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.y, frag_info.shadow_texel_size);
                highp float _14056 = _14047.x;
                bool _14058 = _14056 < _14054;
                bool _14067 = false;
                if (!_14058)
                {
                    _14067 = _14056 > (1.0 - _14054);
                }
                else
                {
                    _14067 = _14058;
                }
                bool _14075 = false;
                if (!_14067)
                {
                    _14075 = _14047.y < _14054;
                }
                else
                {
                    _14075 = _14067;
                }
                bool _14084 = false;
                if (!_14075)
                {
                    _14084 = _14047.y > (1.0 - _14054);
                }
                else
                {
                    _14084 = _14075;
                }
                bool _14091 = false;
                if (!_14084)
                {
                    _14091 = _14042.z < 0.0;
                }
                else
                {
                    _14091 = _14084;
                }
                bool _14098 = false;
                if (!_14091)
                {
                    _14098 = _14042.z > 1.0;
                }
                else
                {
                    _14098 = _14091;
                }
                float _25346 = 0.0;
                float _25386 = 0.0;
                if (!_14098)
                {
                    highp vec2 _15559 = vec2(_14054);
                    highp vec2 _15564 = vec2(_14054 + max(_13913, 9.9999997473787516355514526367188e-05));
                    highp vec2 _15572 = vec2(0.5) - _14045;
                    highp vec2 _15574 = smoothstep(_15559, _15564, _14047) * smoothstep(_15559, _15564, _15572);
                    float _25289 = 0.0;
                    if (_13913 > 0.0)
                    {
                        _25289 = _15574.x * _15574.y;
                    }
                    else
                    {
                        _25289 = 1.0;
                    }
                    float _14107 = min(_25289, 1.0 - _25286);
                    float _25347 = 0.0;
                    float _25387 = 0.0;
                    if (_14107 > 0.0)
                    {
                        highp float _15686 = _14042.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.y));
                        highp float _15692 = 1.0 / (float(_13907) + frag_info.spot_shadow_params.x);
                        highp float _15694 = frag_info.directional_light_direction.w;
                        float mp_copy_15694 = _15694;
                        float _15700 = step(0.5, mp_copy_15694) * (1.0 - step(1.5, mp_copy_15694));
                        highp float _15711 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _15700);
                        float mp_copy_15711 = _15711;
                        float _15713 = cos(mp_copy_15711);
                        float _15715 = sin(mp_copy_15711);
                        highp float _25307 = 0.0;
                        if ((_15694 > 1.5) && (_15694 < 2.5))
                        {
                            highp float _15734 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _15739 = max(_15734 * _15686, frag_info.shadow_texel_size);
                            float _25297 = 0.0;
                            highp float _25298 = 0.0;
                            _25298 = 0.0;
                            _25297 = 0.0;
                            highp float _15761 = 0.0;
                            float _15764 = 0.0;
                            for (int _25296 = 0; _25296 < 9; _25298 = _15761, _25297 = _15764, _25296++)
                            {
                                vec2 _27744 = vec2(0.0);
                                do
                                {
                                    if (_25296 == 0)
                                    {
                                        _27744 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25296 == 1)
                                    {
                                        _27744 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25296 == 2)
                                    {
                                        _27744 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25296 == 3)
                                    {
                                        _27744 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25296 == 4)
                                    {
                                        _27744 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25296 == 5)
                                    {
                                        _27744 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25296 == 6)
                                    {
                                        _27744 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25296 == 7)
                                    {
                                        _27744 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25296 == 8)
                                    {
                                        _27744 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25296 == 9)
                                    {
                                        _27744 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25296 == 10)
                                    {
                                        _27744 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25296 == 11)
                                    {
                                        _27744 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25296 == 12)
                                    {
                                        _27744 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25296 == 13)
                                    {
                                        _27744 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25296 == 14)
                                    {
                                        _27744 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25296 == 15)
                                    {
                                        _27744 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27744 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _16006 = clamp(_14047 + (vec2((_27744.x * _15713) - (_27744.y * _15715), (_27744.x * _15715) + (_27744.y * _15713)) * _15739), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _16015 = _16006.y;
                                highp vec2 _16016 = vec2((1.0 + _16006.x) * _15692, _16015);
                                _16016.y = 1.0 - _16015;
                                highp vec4 _16023 = texture(shadow_map, _16016);
                                highp float _16024 = _16023.x;
                                highp float _15756 = step(_16024, _15686);
                                float mp_copy_15756 = _15756;
                                _15761 = _25298 + (_16024 * _15756);
                                _15764 = _25297 + mp_copy_15756;
                            }
                            highp float _25299 = 0.0;
                            if (_25297 > 0.0)
                            {
                                _25299 = _25298 / _25297;
                            }
                            else
                            {
                                _25299 = _15686;
                            }
                            _25307 = clamp(_15734 * max(_15686 - _25299, 0.0), frag_info.shadow_texel_size, _14054);
                        }
                        else
                        {
                            _25307 = _14054;
                        }
                        float _25314 = 0.0;
                        if (_15694 > 2.5)
                        {
                            highp vec2 _16052 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _16056 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _16057 = clamp(_14047 + (vec2(-0.707099974155426025390625) * _25307), _16052, _16056);
                            highp vec2 _16068 = (vec2(_16057.x, 1.0 - _16057.y) / _16052) - vec2(0.5);
                            highp vec2 _16070 = floor(_16068);
                            highp vec2 _16073 = _16068 - _16070;
                            highp vec2 _16078 = (_16070 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16088 = vec2((1.0 + _16078.x) * _15692, _16078.y);
                            highp float _16092 = frag_info.shadow_texel_size * _15692;
                            highp vec2 _16095 = vec2(_16092, frag_info.shadow_texel_size);
                            highp vec2 _16104 = vec2(_16092, 0.0);
                            highp vec2 _16112 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _16141 = _16073.x;
                            highp float _16150 = mix(mix(float(_15686 <= texture(shadow_map, _16088).x), float(_15686 <= texture(shadow_map, _16088 + _16104).x), _16141), mix(float(_15686 <= texture(shadow_map, _16088 + _16112).x), float(_15686 <= texture(shadow_map, _16088 + _16095).x), _16141), _16073.y);
                            float mp_copy_16150 = _16150;
                            highp vec2 _16184 = clamp(_14047 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25307), _16052, _16056);
                            highp vec2 _16195 = (vec2(_16184.x, 1.0 - _16184.y) / _16052) - vec2(0.5);
                            highp vec2 _16197 = floor(_16195);
                            highp vec2 _16200 = _16195 - _16197;
                            highp vec2 _16205 = (_16197 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16215 = vec2((1.0 + _16205.x) * _15692, _16205.y);
                            highp float _16268 = _16200.x;
                            highp float _16277 = mix(mix(float(_15686 <= texture(shadow_map, _16215).x), float(_15686 <= texture(shadow_map, _16215 + _16104).x), _16268), mix(float(_15686 <= texture(shadow_map, _16215 + _16112).x), float(_15686 <= texture(shadow_map, _16215 + _16095).x), _16268), _16200.y);
                            float mp_copy_16277 = _16277;
                            highp vec2 _16311 = clamp(_14047 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25307), _16052, _16056);
                            highp vec2 _16322 = (vec2(_16311.x, 1.0 - _16311.y) / _16052) - vec2(0.5);
                            highp vec2 _16324 = floor(_16322);
                            highp vec2 _16327 = _16322 - _16324;
                            highp vec2 _16332 = (_16324 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16342 = vec2((1.0 + _16332.x) * _15692, _16332.y);
                            highp float _16395 = _16327.x;
                            highp float _16404 = mix(mix(float(_15686 <= texture(shadow_map, _16342).x), float(_15686 <= texture(shadow_map, _16342 + _16104).x), _16395), mix(float(_15686 <= texture(shadow_map, _16342 + _16112).x), float(_15686 <= texture(shadow_map, _16342 + _16095).x), _16395), _16327.y);
                            float mp_copy_16404 = _16404;
                            highp vec2 _16438 = clamp(_14047 + (vec2(0.707099974155426025390625) * _25307), _16052, _16056);
                            highp vec2 _16449 = (vec2(_16438.x, 1.0 - _16438.y) / _16052) - vec2(0.5);
                            highp vec2 _16451 = floor(_16449);
                            highp vec2 _16454 = _16449 - _16451;
                            highp vec2 _16459 = (_16451 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _16469 = vec2((1.0 + _16459.x) * _15692, _16459.y);
                            highp float _16522 = _16454.x;
                            highp float _16531 = mix(mix(float(_15686 <= texture(shadow_map, _16469).x), float(_15686 <= texture(shadow_map, _16469 + _16104).x), _16522), mix(float(_15686 <= texture(shadow_map, _16469 + _16112).x), float(_15686 <= texture(shadow_map, _16469 + _16095).x), _16522), _16454.y);
                            float mp_copy_16531 = _16531;
                            _25314 = (((mp_copy_16150 + mp_copy_16277) + mp_copy_16404) + mp_copy_16531) * 0.25;
                        }
                        else
                        {
                            int _15827 = (_15700 > 0.5) ? 17 : 16;
                            float _25310 = 0.0;
                            _25310 = 0.0;
                            float _15855 = 0.0;
                            for (int _25300 = 0; _25300 < 17; _25310 = _15855, _25300++)
                            {
                                if (_25300 >= _15827)
                                {
                                    break;
                                }
                                vec2 _25301 = vec2(0.0);
                                do
                                {
                                    if (_25300 == 0)
                                    {
                                        _25301 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25300 == 1)
                                    {
                                        _25301 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25300 == 2)
                                    {
                                        _25301 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25300 == 3)
                                    {
                                        _25301 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25300 == 4)
                                    {
                                        _25301 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25300 == 5)
                                    {
                                        _25301 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25300 == 6)
                                    {
                                        _25301 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25300 == 7)
                                    {
                                        _25301 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25300 == 8)
                                    {
                                        _25301 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25300 == 9)
                                    {
                                        _25301 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25300 == 10)
                                    {
                                        _25301 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25300 == 11)
                                    {
                                        _25301 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25300 == 12)
                                    {
                                        _25301 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25300 == 13)
                                    {
                                        _25301 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25300 == 14)
                                    {
                                        _25301 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25300 == 15)
                                    {
                                        _25301 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25301 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25303 = vec2(0.0);
                                do
                                {
                                    if (_25300 < 3)
                                    {
                                        _25303 = vec2(float(_25300) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25300 < 6)
                                    {
                                        _25303 = vec2((float(_25300 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25300 < 11)
                                    {
                                        _25303 = vec2((float(_25300 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25300 < 14)
                                    {
                                        _25303 = vec2((float(_25300 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25303 = vec2(float(_25300 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _15844 = mix(_25301, _25303, vec2(_15700));
                                float _16671 = _15844.x;
                                float _16675 = _15844.y;
                                highp vec2 _16701 = clamp(_14047 + (vec2((_16671 * _15713) - (_16675 * _15715), (_16671 * _15715) + (_16675 * _15713)) * _25307), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _16711 = vec2((1.0 + _16701.x) * _15692, _16701.y);
                                _16711.y = 1.0 - _16701.y;
                                highp float _16723 = float(_15686 <= texture(shadow_map, _16711).x);
                                float mp_copy_16723 = _16723;
                                _15855 = _25310 + mp_copy_16723;
                            }
                            _25314 = _25310 / float(_15827);
                        }
                        bool _15868 = 1 == (_13907 - 1);
                        bool _15874 = false;
                        if (_15868)
                        {
                            _15874 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _15874 = _15868;
                        }
                        float _25315 = 0.0;
                        if (_15874)
                        {
                            highp vec2 _15881 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.y);
                            highp vec2 _15889 = smoothstep(vec2(0.0), _15881, _14047) * smoothstep(vec2(0.0), _15881, _15572);
                            _25315 = mix(1.0, _25314, _15889.x * _15889.y);
                        }
                        else
                        {
                            _25315 = _25314;
                        }
                        _25387 = _25326 + (_14107 * _25315);
                        _25347 = _25286 + _14107;
                    }
                    else
                    {
                        _25387 = _25326;
                        _25347 = _25286;
                    }
                    _25386 = _25387;
                    _25346 = _25347;
                }
                else
                {
                    _25386 = _25326;
                    _25346 = _25286;
                }
                _25385 = _25386;
                _25345 = _25346;
            }
            else
            {
                _25385 = _25326;
                _25345 = _25286;
            }
            float _25404 = 0.0;
            float _25444 = 0.0;
            if ((_25345 < 1.0) && (_13907 > 2))
            {
                highp vec4 _14142 = frag_info.light_space_matrix[2] * vec4(_14379, 1.0);
                highp vec3 _14148 = _14142.xyz / vec3(_14142.w);
                highp vec2 _14151 = _14148.xy * 0.5;
                highp vec2 _14153 = _14151 + vec2(0.5);
                highp float _14160 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.z, frag_info.shadow_texel_size);
                highp float _14162 = _14153.x;
                bool _14164 = _14162 < _14160;
                bool _14173 = false;
                if (!_14164)
                {
                    _14173 = _14162 > (1.0 - _14160);
                }
                else
                {
                    _14173 = _14164;
                }
                bool _14181 = false;
                if (!_14173)
                {
                    _14181 = _14153.y < _14160;
                }
                else
                {
                    _14181 = _14173;
                }
                bool _14190 = false;
                if (!_14181)
                {
                    _14190 = _14153.y > (1.0 - _14160);
                }
                else
                {
                    _14190 = _14181;
                }
                bool _14197 = false;
                if (!_14190)
                {
                    _14197 = _14148.z < 0.0;
                }
                else
                {
                    _14197 = _14190;
                }
                bool _14204 = false;
                if (!_14197)
                {
                    _14204 = _14148.z > 1.0;
                }
                else
                {
                    _14204 = _14197;
                }
                float _25405 = 0.0;
                float _25445 = 0.0;
                if (!_14204)
                {
                    highp vec2 _16731 = vec2(_14160);
                    highp vec2 _16736 = vec2(_14160 + max(_13913, 9.9999997473787516355514526367188e-05));
                    highp vec2 _16744 = vec2(0.5) - _14151;
                    highp vec2 _16746 = smoothstep(_16731, _16736, _14153) * smoothstep(_16731, _16736, _16744);
                    float _25348 = 0.0;
                    if (_13913 > 0.0)
                    {
                        _25348 = _16746.x * _16746.y;
                    }
                    else
                    {
                        _25348 = 1.0;
                    }
                    float _14213 = min(_25348, 1.0 - _25345);
                    float _25406 = 0.0;
                    float _25446 = 0.0;
                    if (_14213 > 0.0)
                    {
                        highp float _16858 = _14148.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.z));
                        highp float _16864 = 1.0 / (float(_13907) + frag_info.spot_shadow_params.x);
                        highp float _16866 = frag_info.directional_light_direction.w;
                        float mp_copy_16866 = _16866;
                        float _16872 = step(0.5, mp_copy_16866) * (1.0 - step(1.5, mp_copy_16866));
                        highp float _16883 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _16872);
                        float mp_copy_16883 = _16883;
                        float _16885 = cos(mp_copy_16883);
                        float _16887 = sin(mp_copy_16883);
                        highp float _25366 = 0.0;
                        if ((_16866 > 1.5) && (_16866 < 2.5))
                        {
                            highp float _16906 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _16911 = max(_16906 * _16858, frag_info.shadow_texel_size);
                            float _25356 = 0.0;
                            highp float _25357 = 0.0;
                            _25357 = 0.0;
                            _25356 = 0.0;
                            highp float _16933 = 0.0;
                            float _16936 = 0.0;
                            for (int _25355 = 0; _25355 < 9; _25357 = _16933, _25356 = _16936, _25355++)
                            {
                                vec2 _27740 = vec2(0.0);
                                do
                                {
                                    if (_25355 == 0)
                                    {
                                        _27740 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25355 == 1)
                                    {
                                        _27740 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25355 == 2)
                                    {
                                        _27740 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25355 == 3)
                                    {
                                        _27740 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25355 == 4)
                                    {
                                        _27740 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25355 == 5)
                                    {
                                        _27740 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25355 == 6)
                                    {
                                        _27740 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25355 == 7)
                                    {
                                        _27740 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25355 == 8)
                                    {
                                        _27740 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25355 == 9)
                                    {
                                        _27740 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25355 == 10)
                                    {
                                        _27740 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25355 == 11)
                                    {
                                        _27740 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25355 == 12)
                                    {
                                        _27740 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25355 == 13)
                                    {
                                        _27740 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25355 == 14)
                                    {
                                        _27740 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25355 == 15)
                                    {
                                        _27740 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27740 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _17178 = clamp(_14153 + (vec2((_27740.x * _16885) - (_27740.y * _16887), (_27740.x * _16887) + (_27740.y * _16885)) * _16911), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _17187 = _17178.y;
                                highp vec2 _17188 = vec2((2.0 + _17178.x) * _16864, _17187);
                                _17188.y = 1.0 - _17187;
                                highp vec4 _17195 = texture(shadow_map, _17188);
                                highp float _17196 = _17195.x;
                                highp float _16928 = step(_17196, _16858);
                                float mp_copy_16928 = _16928;
                                _16933 = _25357 + (_17196 * _16928);
                                _16936 = _25356 + mp_copy_16928;
                            }
                            highp float _25358 = 0.0;
                            if (_25356 > 0.0)
                            {
                                _25358 = _25357 / _25356;
                            }
                            else
                            {
                                _25358 = _16858;
                            }
                            _25366 = clamp(_16906 * max(_16858 - _25358, 0.0), frag_info.shadow_texel_size, _14160);
                        }
                        else
                        {
                            _25366 = _14160;
                        }
                        float _25373 = 0.0;
                        if (_16866 > 2.5)
                        {
                            highp vec2 _17224 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _17228 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _17229 = clamp(_14153 + (vec2(-0.707099974155426025390625) * _25366), _17224, _17228);
                            highp vec2 _17240 = (vec2(_17229.x, 1.0 - _17229.y) / _17224) - vec2(0.5);
                            highp vec2 _17242 = floor(_17240);
                            highp vec2 _17245 = _17240 - _17242;
                            highp vec2 _17250 = (_17242 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17260 = vec2((2.0 + _17250.x) * _16864, _17250.y);
                            highp float _17264 = frag_info.shadow_texel_size * _16864;
                            highp vec2 _17267 = vec2(_17264, frag_info.shadow_texel_size);
                            highp vec2 _17276 = vec2(_17264, 0.0);
                            highp vec2 _17284 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _17313 = _17245.x;
                            highp float _17322 = mix(mix(float(_16858 <= texture(shadow_map, _17260).x), float(_16858 <= texture(shadow_map, _17260 + _17276).x), _17313), mix(float(_16858 <= texture(shadow_map, _17260 + _17284).x), float(_16858 <= texture(shadow_map, _17260 + _17267).x), _17313), _17245.y);
                            float mp_copy_17322 = _17322;
                            highp vec2 _17356 = clamp(_14153 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25366), _17224, _17228);
                            highp vec2 _17367 = (vec2(_17356.x, 1.0 - _17356.y) / _17224) - vec2(0.5);
                            highp vec2 _17369 = floor(_17367);
                            highp vec2 _17372 = _17367 - _17369;
                            highp vec2 _17377 = (_17369 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17387 = vec2((2.0 + _17377.x) * _16864, _17377.y);
                            highp float _17440 = _17372.x;
                            highp float _17449 = mix(mix(float(_16858 <= texture(shadow_map, _17387).x), float(_16858 <= texture(shadow_map, _17387 + _17276).x), _17440), mix(float(_16858 <= texture(shadow_map, _17387 + _17284).x), float(_16858 <= texture(shadow_map, _17387 + _17267).x), _17440), _17372.y);
                            float mp_copy_17449 = _17449;
                            highp vec2 _17483 = clamp(_14153 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25366), _17224, _17228);
                            highp vec2 _17494 = (vec2(_17483.x, 1.0 - _17483.y) / _17224) - vec2(0.5);
                            highp vec2 _17496 = floor(_17494);
                            highp vec2 _17499 = _17494 - _17496;
                            highp vec2 _17504 = (_17496 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17514 = vec2((2.0 + _17504.x) * _16864, _17504.y);
                            highp float _17567 = _17499.x;
                            highp float _17576 = mix(mix(float(_16858 <= texture(shadow_map, _17514).x), float(_16858 <= texture(shadow_map, _17514 + _17276).x), _17567), mix(float(_16858 <= texture(shadow_map, _17514 + _17284).x), float(_16858 <= texture(shadow_map, _17514 + _17267).x), _17567), _17499.y);
                            float mp_copy_17576 = _17576;
                            highp vec2 _17610 = clamp(_14153 + (vec2(0.707099974155426025390625) * _25366), _17224, _17228);
                            highp vec2 _17621 = (vec2(_17610.x, 1.0 - _17610.y) / _17224) - vec2(0.5);
                            highp vec2 _17623 = floor(_17621);
                            highp vec2 _17626 = _17621 - _17623;
                            highp vec2 _17631 = (_17623 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _17641 = vec2((2.0 + _17631.x) * _16864, _17631.y);
                            highp float _17694 = _17626.x;
                            highp float _17703 = mix(mix(float(_16858 <= texture(shadow_map, _17641).x), float(_16858 <= texture(shadow_map, _17641 + _17276).x), _17694), mix(float(_16858 <= texture(shadow_map, _17641 + _17284).x), float(_16858 <= texture(shadow_map, _17641 + _17267).x), _17694), _17626.y);
                            float mp_copy_17703 = _17703;
                            _25373 = (((mp_copy_17322 + mp_copy_17449) + mp_copy_17576) + mp_copy_17703) * 0.25;
                        }
                        else
                        {
                            int _16999 = (_16872 > 0.5) ? 17 : 16;
                            float _25369 = 0.0;
                            _25369 = 0.0;
                            float _17027 = 0.0;
                            for (int _25359 = 0; _25359 < 17; _25369 = _17027, _25359++)
                            {
                                if (_25359 >= _16999)
                                {
                                    break;
                                }
                                vec2 _25360 = vec2(0.0);
                                do
                                {
                                    if (_25359 == 0)
                                    {
                                        _25360 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25359 == 1)
                                    {
                                        _25360 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25359 == 2)
                                    {
                                        _25360 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25359 == 3)
                                    {
                                        _25360 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25359 == 4)
                                    {
                                        _25360 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25359 == 5)
                                    {
                                        _25360 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25359 == 6)
                                    {
                                        _25360 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25359 == 7)
                                    {
                                        _25360 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25359 == 8)
                                    {
                                        _25360 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25359 == 9)
                                    {
                                        _25360 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25359 == 10)
                                    {
                                        _25360 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25359 == 11)
                                    {
                                        _25360 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25359 == 12)
                                    {
                                        _25360 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25359 == 13)
                                    {
                                        _25360 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25359 == 14)
                                    {
                                        _25360 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25359 == 15)
                                    {
                                        _25360 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25360 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25362 = vec2(0.0);
                                do
                                {
                                    if (_25359 < 3)
                                    {
                                        _25362 = vec2(float(_25359) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25359 < 6)
                                    {
                                        _25362 = vec2((float(_25359 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25359 < 11)
                                    {
                                        _25362 = vec2((float(_25359 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25359 < 14)
                                    {
                                        _25362 = vec2((float(_25359 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25362 = vec2(float(_25359 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _17016 = mix(_25360, _25362, vec2(_16872));
                                float _17843 = _17016.x;
                                float _17847 = _17016.y;
                                highp vec2 _17873 = clamp(_14153 + (vec2((_17843 * _16885) - (_17847 * _16887), (_17843 * _16887) + (_17847 * _16885)) * _25366), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _17883 = vec2((2.0 + _17873.x) * _16864, _17873.y);
                                _17883.y = 1.0 - _17873.y;
                                highp float _17895 = float(_16858 <= texture(shadow_map, _17883).x);
                                float mp_copy_17895 = _17895;
                                _17027 = _25369 + mp_copy_17895;
                            }
                            _25373 = _25369 / float(_16999);
                        }
                        bool _17040 = 2 == (_13907 - 1);
                        bool _17046 = false;
                        if (_17040)
                        {
                            _17046 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _17046 = _17040;
                        }
                        float _25374 = 0.0;
                        if (_17046)
                        {
                            highp vec2 _17053 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.z);
                            highp vec2 _17061 = smoothstep(vec2(0.0), _17053, _14153) * smoothstep(vec2(0.0), _17053, _16744);
                            _25374 = mix(1.0, _25373, _17061.x * _17061.y);
                        }
                        else
                        {
                            _25374 = _25373;
                        }
                        _25446 = _25385 + (_14213 * _25374);
                        _25406 = _25345 + _14213;
                    }
                    else
                    {
                        _25446 = _25385;
                        _25406 = _25345;
                    }
                    _25445 = _25446;
                    _25405 = _25406;
                }
                else
                {
                    _25445 = _25385;
                    _25405 = _25345;
                }
                _25444 = _25445;
                _25404 = _25405;
            }
            else
            {
                _25444 = _25385;
                _25404 = _25345;
            }
            float _25463 = 0.0;
            float _25466 = 0.0;
            if ((_25404 < 1.0) && (_13907 > 3))
            {
                highp vec4 _14248 = frag_info.light_space_matrix[3] * vec4(_14379, 1.0);
                highp vec3 _14254 = _14248.xyz / vec3(_14248.w);
                highp vec2 _14257 = _14254.xy * 0.5;
                highp vec2 _14259 = _14257 + vec2(0.5);
                highp float _14266 = max(frag_info.shadow_softness / frag_info.cascade_box_sizes.w, frag_info.shadow_texel_size);
                highp float _14268 = _14259.x;
                bool _14270 = _14268 < _14266;
                bool _14279 = false;
                if (!_14270)
                {
                    _14279 = _14268 > (1.0 - _14266);
                }
                else
                {
                    _14279 = _14270;
                }
                bool _14287 = false;
                if (!_14279)
                {
                    _14287 = _14259.y < _14266;
                }
                else
                {
                    _14287 = _14279;
                }
                bool _14296 = false;
                if (!_14287)
                {
                    _14296 = _14259.y > (1.0 - _14266);
                }
                else
                {
                    _14296 = _14287;
                }
                bool _14303 = false;
                if (!_14296)
                {
                    _14303 = _14254.z < 0.0;
                }
                else
                {
                    _14303 = _14296;
                }
                bool _14310 = false;
                if (!_14303)
                {
                    _14310 = _14254.z > 1.0;
                }
                else
                {
                    _14310 = _14303;
                }
                float _25464 = 0.0;
                float _25467 = 0.0;
                if (!_14310)
                {
                    highp vec2 _17903 = vec2(_14266);
                    highp vec2 _17908 = vec2(_14266 + max(_13913, 9.9999997473787516355514526367188e-05));
                    highp vec2 _17916 = vec2(0.5) - _14257;
                    highp vec2 _17918 = smoothstep(_17903, _17908, _14259) * smoothstep(_17903, _17908, _17916);
                    float _25407 = 0.0;
                    if (_13913 > 0.0)
                    {
                        _25407 = _17918.x * _17918.y;
                    }
                    else
                    {
                        _25407 = 1.0;
                    }
                    float _14319 = min(_25407, 1.0 - _25404);
                    float _25465 = 0.0;
                    float _25468 = 0.0;
                    if (_14319 > 0.0)
                    {
                        highp float _18030 = _14254.z - (frag_info.shadow_bias / (7.0 * frag_info.cascade_box_sizes.w));
                        highp float _18036 = 1.0 / (float(_13907) + frag_info.spot_shadow_params.x);
                        highp float _18038 = frag_info.directional_light_direction.w;
                        float mp_copy_18038 = _18038;
                        float _18044 = step(0.5, mp_copy_18038) * (1.0 - step(1.5, mp_copy_18038));
                        highp float _18055 = (fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375) * (1.0 - _18044);
                        float mp_copy_18055 = _18055;
                        float _18057 = cos(mp_copy_18055);
                        float _18059 = sin(mp_copy_18055);
                        highp float _25425 = 0.0;
                        if ((_18038 > 1.5) && (_18038 < 2.5))
                        {
                            highp float _18078 = tan(frag_info.camera_right.w) * 7.0;
                            highp float _18083 = max(_18078 * _18030, frag_info.shadow_texel_size);
                            float _25415 = 0.0;
                            highp float _25416 = 0.0;
                            _25416 = 0.0;
                            _25415 = 0.0;
                            highp float _18105 = 0.0;
                            float _18108 = 0.0;
                            for (int _25414 = 0; _25414 < 9; _25416 = _18105, _25415 = _18108, _25414++)
                            {
                                vec2 _27736 = vec2(0.0);
                                do
                                {
                                    if (_25414 == 0)
                                    {
                                        _27736 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25414 == 1)
                                    {
                                        _27736 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25414 == 2)
                                    {
                                        _27736 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25414 == 3)
                                    {
                                        _27736 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25414 == 4)
                                    {
                                        _27736 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25414 == 5)
                                    {
                                        _27736 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25414 == 6)
                                    {
                                        _27736 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25414 == 7)
                                    {
                                        _27736 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25414 == 8)
                                    {
                                        _27736 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25414 == 9)
                                    {
                                        _27736 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25414 == 10)
                                    {
                                        _27736 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25414 == 11)
                                    {
                                        _27736 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25414 == 12)
                                    {
                                        _27736 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25414 == 13)
                                    {
                                        _27736 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25414 == 14)
                                    {
                                        _27736 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25414 == 15)
                                    {
                                        _27736 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _27736 = vec2(0.0);
                                    break;
                                } while(false);
                                highp vec2 _18350 = clamp(_14259 + (vec2((_27736.x * _18057) - (_27736.y * _18059), (_27736.x * _18059) + (_27736.y * _18057)) * _18083), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp float _18359 = _18350.y;
                                highp vec2 _18360 = vec2((3.0 + _18350.x) * _18036, _18359);
                                _18360.y = 1.0 - _18359;
                                highp vec4 _18367 = texture(shadow_map, _18360);
                                highp float _18368 = _18367.x;
                                highp float _18100 = step(_18368, _18030);
                                float mp_copy_18100 = _18100;
                                _18105 = _25416 + (_18368 * _18100);
                                _18108 = _25415 + mp_copy_18100;
                            }
                            highp float _25417 = 0.0;
                            if (_25415 > 0.0)
                            {
                                _25417 = _25416 / _25415;
                            }
                            else
                            {
                                _25417 = _18030;
                            }
                            _25425 = clamp(_18078 * max(_18030 - _25417, 0.0), frag_info.shadow_texel_size, _14266);
                        }
                        else
                        {
                            _25425 = _14266;
                        }
                        float _25432 = 0.0;
                        if (_18038 > 2.5)
                        {
                            highp vec2 _18396 = vec2(frag_info.shadow_texel_size);
                            highp vec2 _18400 = vec2(1.0 - frag_info.shadow_texel_size);
                            highp vec2 _18401 = clamp(_14259 + (vec2(-0.707099974155426025390625) * _25425), _18396, _18400);
                            highp vec2 _18412 = (vec2(_18401.x, 1.0 - _18401.y) / _18396) - vec2(0.5);
                            highp vec2 _18414 = floor(_18412);
                            highp vec2 _18417 = _18412 - _18414;
                            highp vec2 _18422 = (_18414 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18432 = vec2((3.0 + _18422.x) * _18036, _18422.y);
                            highp float _18436 = frag_info.shadow_texel_size * _18036;
                            highp vec2 _18439 = vec2(_18436, frag_info.shadow_texel_size);
                            highp vec2 _18448 = vec2(_18436, 0.0);
                            highp vec2 _18456 = vec2(0.0, frag_info.shadow_texel_size);
                            highp float _18485 = _18417.x;
                            highp float _18494 = mix(mix(float(_18030 <= texture(shadow_map, _18432).x), float(_18030 <= texture(shadow_map, _18432 + _18448).x), _18485), mix(float(_18030 <= texture(shadow_map, _18432 + _18456).x), float(_18030 <= texture(shadow_map, _18432 + _18439).x), _18485), _18417.y);
                            float mp_copy_18494 = _18494;
                            highp vec2 _18528 = clamp(_14259 + (vec2(0.707099974155426025390625, -0.707099974155426025390625) * _25425), _18396, _18400);
                            highp vec2 _18539 = (vec2(_18528.x, 1.0 - _18528.y) / _18396) - vec2(0.5);
                            highp vec2 _18541 = floor(_18539);
                            highp vec2 _18544 = _18539 - _18541;
                            highp vec2 _18549 = (_18541 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18559 = vec2((3.0 + _18549.x) * _18036, _18549.y);
                            highp float _18612 = _18544.x;
                            highp float _18621 = mix(mix(float(_18030 <= texture(shadow_map, _18559).x), float(_18030 <= texture(shadow_map, _18559 + _18448).x), _18612), mix(float(_18030 <= texture(shadow_map, _18559 + _18456).x), float(_18030 <= texture(shadow_map, _18559 + _18439).x), _18612), _18544.y);
                            float mp_copy_18621 = _18621;
                            highp vec2 _18655 = clamp(_14259 + (vec2(-0.707099974155426025390625, 0.707099974155426025390625) * _25425), _18396, _18400);
                            highp vec2 _18666 = (vec2(_18655.x, 1.0 - _18655.y) / _18396) - vec2(0.5);
                            highp vec2 _18668 = floor(_18666);
                            highp vec2 _18671 = _18666 - _18668;
                            highp vec2 _18676 = (_18668 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18686 = vec2((3.0 + _18676.x) * _18036, _18676.y);
                            highp float _18739 = _18671.x;
                            highp float _18748 = mix(mix(float(_18030 <= texture(shadow_map, _18686).x), float(_18030 <= texture(shadow_map, _18686 + _18448).x), _18739), mix(float(_18030 <= texture(shadow_map, _18686 + _18456).x), float(_18030 <= texture(shadow_map, _18686 + _18439).x), _18739), _18671.y);
                            float mp_copy_18748 = _18748;
                            highp vec2 _18782 = clamp(_14259 + (vec2(0.707099974155426025390625) * _25425), _18396, _18400);
                            highp vec2 _18793 = (vec2(_18782.x, 1.0 - _18782.y) / _18396) - vec2(0.5);
                            highp vec2 _18795 = floor(_18793);
                            highp vec2 _18798 = _18793 - _18795;
                            highp vec2 _18803 = (_18795 + vec2(0.5)) * frag_info.shadow_texel_size;
                            highp vec2 _18813 = vec2((3.0 + _18803.x) * _18036, _18803.y);
                            highp float _18866 = _18798.x;
                            highp float _18875 = mix(mix(float(_18030 <= texture(shadow_map, _18813).x), float(_18030 <= texture(shadow_map, _18813 + _18448).x), _18866), mix(float(_18030 <= texture(shadow_map, _18813 + _18456).x), float(_18030 <= texture(shadow_map, _18813 + _18439).x), _18866), _18798.y);
                            float mp_copy_18875 = _18875;
                            _25432 = (((mp_copy_18494 + mp_copy_18621) + mp_copy_18748) + mp_copy_18875) * 0.25;
                        }
                        else
                        {
                            int _18171 = (_18044 > 0.5) ? 17 : 16;
                            float _25428 = 0.0;
                            _25428 = 0.0;
                            float _18199 = 0.0;
                            for (int _25418 = 0; _25418 < 17; _25428 = _18199, _25418++)
                            {
                                if (_25418 >= _18171)
                                {
                                    break;
                                }
                                vec2 _25419 = vec2(0.0);
                                do
                                {
                                    if (_25418 == 0)
                                    {
                                        _25419 = vec2(-0.94201624393463134765625, -0.39906215667724609375);
                                        break;
                                    }
                                    if (_25418 == 1)
                                    {
                                        _25419 = vec2(0.94558608531951904296875, -0.768907248973846435546875);
                                        break;
                                    }
                                    if (_25418 == 2)
                                    {
                                        _25419 = vec2(-0.094184100627899169921875, -0.929388701915740966796875);
                                        break;
                                    }
                                    if (_25418 == 3)
                                    {
                                        _25419 = vec2(0.34495937824249267578125, 0.29387760162353515625);
                                        break;
                                    }
                                    if (_25418 == 4)
                                    {
                                        _25419 = vec2(-0.91588580608367919921875, 0.4577143192291259765625);
                                        break;
                                    }
                                    if (_25418 == 5)
                                    {
                                        _25419 = vec2(-0.8154423236846923828125, -0.87912464141845703125);
                                        break;
                                    }
                                    if (_25418 == 6)
                                    {
                                        _25419 = vec2(-0.38277542591094970703125, 0.2767684459686279296875);
                                        break;
                                    }
                                    if (_25418 == 7)
                                    {
                                        _25419 = vec2(0.9748439788818359375, 0.7564837932586669921875);
                                        break;
                                    }
                                    if (_25418 == 8)
                                    {
                                        _25419 = vec2(0.4432332515716552734375, -0.9751155376434326171875);
                                        break;
                                    }
                                    if (_25418 == 9)
                                    {
                                        _25419 = vec2(0.5374298095703125, -0.473734200000762939453125);
                                        break;
                                    }
                                    if (_25418 == 10)
                                    {
                                        _25419 = vec2(-0.2649691104888916015625, -0.418930232524871826171875);
                                        break;
                                    }
                                    if (_25418 == 11)
                                    {
                                        _25419 = vec2(0.79197514057159423828125, 0.19090187549591064453125);
                                        break;
                                    }
                                    if (_25418 == 12)
                                    {
                                        _25419 = vec2(-0.24188840389251708984375, 0.997065067291259765625);
                                        break;
                                    }
                                    if (_25418 == 13)
                                    {
                                        _25419 = vec2(-0.8140995502471923828125, 0.91437590122222900390625);
                                        break;
                                    }
                                    if (_25418 == 14)
                                    {
                                        _25419 = vec2(0.1998412609100341796875, 0.786413669586181640625);
                                        break;
                                    }
                                    if (_25418 == 15)
                                    {
                                        _25419 = vec2(0.14383161067962646484375, -0.141007900238037109375);
                                        break;
                                    }
                                    _25419 = vec2(0.0);
                                    break;
                                } while(false);
                                vec2 _25421 = vec2(0.0);
                                do
                                {
                                    if (_25418 < 3)
                                    {
                                        _25421 = vec2(float(_25418) - 1.0, -1.0);
                                        break;
                                    }
                                    if (_25418 < 6)
                                    {
                                        _25421 = vec2((float(_25418 - 3) * 0.5) - 0.5, -0.5);
                                        break;
                                    }
                                    if (_25418 < 11)
                                    {
                                        _25421 = vec2((float(_25418 - 6) * 0.5) - 1.0, 0.0);
                                        break;
                                    }
                                    if (_25418 < 14)
                                    {
                                        _25421 = vec2((float(_25418 - 11) * 0.5) - 0.5, 0.5);
                                        break;
                                    }
                                    _25421 = vec2(float(_25418 - 14) - 1.0, 1.0);
                                    break;
                                } while(false);
                                vec2 _18188 = mix(_25419, _25421, vec2(_18044));
                                float _19015 = _18188.x;
                                float _19019 = _18188.y;
                                highp vec2 _19045 = clamp(_14259 + (vec2((_19015 * _18057) - (_19019 * _18059), (_19015 * _18059) + (_19019 * _18057)) * _25425), vec2(frag_info.shadow_texel_size), vec2(1.0 - frag_info.shadow_texel_size));
                                highp vec2 _19055 = vec2((3.0 + _19045.x) * _18036, _19045.y);
                                _19055.y = 1.0 - _19045.y;
                                highp float _19067 = float(_18030 <= texture(shadow_map, _19055).x);
                                float mp_copy_19067 = _19067;
                                _18199 = _25428 + mp_copy_19067;
                            }
                            _25432 = _25428 / float(_18171);
                        }
                        bool _18212 = 3 == (_13907 - 1);
                        bool _18218 = false;
                        if (_18212)
                        {
                            _18218 = frag_info.shadow_fade > 0.0;
                        }
                        else
                        {
                            _18218 = _18212;
                        }
                        float _25433 = 0.0;
                        if (_18218)
                        {
                            highp vec2 _18225 = vec2(frag_info.shadow_fade / frag_info.cascade_box_sizes.w);
                            highp vec2 _18233 = smoothstep(vec2(0.0), _18225, _14259) * smoothstep(vec2(0.0), _18225, _17916);
                            _25433 = mix(1.0, _25432, _18233.x * _18233.y);
                        }
                        else
                        {
                            _25433 = _25432;
                        }
                        _25468 = _25404 + _14319;
                        _25465 = _25444 + (_14319 * _25433);
                    }
                    else
                    {
                        _25468 = _25404;
                        _25465 = _25444;
                    }
                    _25467 = _25468;
                    _25464 = _25465;
                }
                else
                {
                    _25467 = _25404;
                    _25464 = _25444;
                }
                _25466 = _25467;
                _25463 = _25464;
            }
            else
            {
                _25466 = _25404;
                _25463 = _25444;
            }
            _25469 = _25463 + (1.0 - _25466);
        }
        else
        {
            _25469 = 1.0;
        }
        bool _8535 = frag_info.ssao_lighting.w > 0.5;
        bool _8541 = false;
        if (_8535)
        {
            _8541 = frag_info.camera_up.w < 0.5;
        }
        else
        {
            _8541 = _8535;
        }
        float _25620 = 0.0;
        if (_8541)
        {
            _25620 = min(_25469, _25486.y);
        }
        else
        {
            _25620 = _25469;
        }
        float _8550 = _8513 * _25620;
        highp vec3 _8563 = ((((_8447 + (_8451 * ((vec3(1.0) - _8423) - _8447))) * _25040) * _25637) + (((_8423 * (_24848 * frag_info.environment_intensity)) * 1.0) * _25778)) * mix(1.0, _8550, frag_info.radiance_blend.y);
        highp vec3 _26035 = vec3(0.0);
        if (frag_info.camera_up.w > 0.5)
        {
            _26035 = _8563 + ((_25486.xyz * _8451) * _7348);
        }
        else
        {
            _26035 = _8563;
        }
        highp vec3 _26041 = vec3(0.0);
        if (_8500)
        {
            highp vec3 _25938 = vec3(0.0);
            highp vec3 _25939 = vec3(0.0);
            do
            {
                float _19133 = max(dot(_24769, _25862), 0.0);
                highp float hp_copy_19133 = _19133;
                if (_19133 <= 0.0)
                {
                    _25939 = vec3(0.0);
                    _25938 = vec3(0.0);
                    break;
                }
                float _19139 = max(_8320, 9.9999997473787516355514526367188e-05);
                highp float hp_copy_19139 = _19139;
                vec3 _19142 = _25862 + mp_copy_24830;
                float _19145 = dot(_19142, _19142);
                vec3 _25936 = vec3(0.0);
                vec3 _25937 = vec3(0.0);
                if (_19145 > 9.9999999392252902907785028219223e-09)
                {
                    vec3 _19153 = _19142 * inversesqrt(_19145);
                    float _25935 = 0.0;
                    do
                    {
                        float _19210 = dot(_24769, _19153);
                        if (_19210 <= 0.0)
                        {
                            _25935 = 0.0;
                            break;
                        }
                        float _19217 = _24822 * _24822;
                        vec3 _19220 = cross(_24769, _19153);
                        float _19223 = _19210 * _19217;
                        float _19232 = _19217 / (dot(_19220, _19220) + (_19223 * _19223));
                        _25935 = min((_19232 * _19232) * 0.3183098733425140380859375, 65504.0);
                        break;
                    } while(false);
                    vec3 _19270 = _8316 + (_8433 * pow(clamp(1.0 - max(dot(_19153, _24830), 0.0), 0.0, 1.0), 5.0));
                    _25937 = (_19270 * min(_25935 * (0.5 / max(mix((2.0 * hp_copy_19133) * _19139, hp_copy_19133 + hp_copy_19139, hp_copy_24822 * hp_copy_24822), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                    _25936 = _19270;
                }
                else
                {
                    _25937 = vec3(0.0);
                    _25936 = _8316;
                }
                _25939 = (_25937 * frag_info.directional_light_color.xyz) * _19133;
                _25938 = (((((vec3(1.0) - _25936) * _8450) * _8221) * 0.3183098733425140380859375) * frag_info.directional_light_color.xyz) * _19133;
                break;
            } while(false);
            _26041 = (_25938 + _25939) * _8550;
        }
        else
        {
            _26041 = vec3(0.0);
        }
        highp float _19294 = 0.0;
        highp vec2 _25940 = vec2(0.0);
        do
        {
            _19294 = frag_info.punctual_dims.x;
            if (_19294 < 0.5)
            {
                _25940 = vec2(0.0);
                break;
            }
            if (frag_info.froxel_grid.z > 0.5)
            {
                highp vec3 _19306 = v_position - frag_info.camera_position.xyz;
                highp float _19321 = dot(_19306, frag_info.camera_forward.xyz);
                highp float _19327 = max(_19321, 9.9999997473787516355514526367188e-05);
                highp vec2 _19430 = (vec3(dot(_19306, frag_info.camera_right.xyz), dot(_19306, frag_info.camera_up.xyz), _19327).xy / (max(vec2(frag_info.scene_inputs.w, frag_info.camera_forward.w), vec2(9.9999999747524270787835121154785e-07)) * mix(_19327, 1.0, frag_info.view_projection.z))) + frag_info.view_projection.xy;
                highp float _19445 = float(int(((((clamp(floor((log2(max(_19321 + frag_info.view_projection.w, 9.9999997473787516355514526367188e-05)) * frag_info.froxel_grid.w) + frag_info.punctual_dims.w), 0.0, frag_info.froxel_grid.z - 1.0) * frag_info.froxel_grid.y) + clamp(floor((0.5 - (_19430.y * 0.5)) * frag_info.froxel_grid.y), 0.0, frag_info.froxel_grid.y - 1.0)) * frag_info.froxel_grid.x) + clamp(floor(((_19430.x * 0.5) + 0.5) * frag_info.froxel_grid.x), 0.0, frag_info.froxel_grid.x - 1.0)) + 0.5));
                _25940 = vec2(texture(punctual_index, vec2((mod(_19445, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_19445 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z)).xy);
                break;
            }
            _25940 = vec2(frag_info.radiance_blend.w, frag_info.radiance_blend.z);
            break;
        } while(false);
        mediump int _8606 = int(_25940.x + 0.5);
        mediump int _8610 = int(_25940.y + 0.5);
        highp vec3 _26039 = vec3(0.0);
        _26039 = _26041;
        highp vec3 _27852 = vec3(0.0);
        for (int _25941 = 0; _25941 < _8610; _26039 = _27852, _25941++)
        {
            highp float _19478 = float(_8606 + _25941);
            highp vec4 _19496 = texture(punctual_index, vec2((mod(_19478, frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.y, (floor(_19478 / frag_info.punctual_dims.y) + 0.5) / frag_info.punctual_dims.z));
            highp float _19509 = (float(int(_19496.x + 0.5)) + 0.5) / _19294;
            highp vec2 _19510 = vec2(0.0625, _19509);
            highp vec4 _19513 = texture(punctual_lights, _19510);
            highp vec4 _19530 = texture(punctual_lights, vec2(0.1875, _19509));
            highp float _8628 = _19513.w;
            highp vec3 _8630 = _19530.xyz;
            if (_8628 > 2.5)
            {
                highp vec4 _19547 = texture(punctual_lights, vec2(0.3125, _19509));
                highp vec4 _19564 = texture(punctual_lights, vec2(0.4375, _19509));
                highp vec3 _8644 = _19547.xyz * (_19547.w * 0.5);
                highp vec3 _8650 = _19564.xyz * (_19564.w * 0.5);
                highp vec3 _8652 = _19513.xyz;
                highp vec3 _8654 = _8652 - _8644;
                highp vec3 _8656 = _8654 - _8650;
                highp vec3 _8660 = _8652 + _8644;
                highp vec3 _8662 = _8660 - _8650;
                highp vec3 _8674 = _8654 + _8650;
                highp vec3 _8678 = _8652 - v_position;
                highp float _8684 = _19530.w;
                highp float _8688 = (dot(_8678, _8678) * _8684) * _8684;
                highp float _8693 = clamp(1.0 - (_8688 * _8688), 0.0, 1.0);
                float mp_copy_8693 = _8693;
                vec2 _19571 = (clamp(vec2(_24822, sqrt(1.0 - _8320)), vec2(0.0), vec2(1.0)) * 0.984375) + vec2(0.0078125);
                float _19573 = _19571.x;
                float _19578 = _19571.y;
                vec4 _8717 = texture(brdf_lut, vec2((_19573 + 1.0) * 0.3333333432674407958984375, _19578));
                vec4 _8721 = texture(brdf_lut, vec2((_19573 + 2.0) * 0.3333333432674407958984375, _19578));
                vec3 _19621 = normalize(mp_copy_24830 - (_24769 * _8319));
                mat3 _19643 = transpose(mat3(_19621, -cross(_24769, _19621), _24769));
                mat3 _19644 = mat3(vec3(_8717.x, 0.0, _8717.y), vec3(0.0, 1.0, 0.0), vec3(_8717.z, 0.0, _8717.w)) * _19643;
                highp vec3 _19648 = _8656 - v_position;
                highp vec3 _19650 = normalize(_19644 * _19648);
                vec3 mp_copy_19650 = _19650;
                highp vec3 _19654 = _8662 - v_position;
                highp vec3 _19656 = normalize(_19644 * _19654);
                vec3 mp_copy_19656 = _19656;
                highp vec3 _19660 = (_8660 + _8650) - v_position;
                highp vec3 _19662 = normalize(_19644 * _19660);
                vec3 mp_copy_19662 = _19662;
                highp vec3 _19666 = _8674 - v_position;
                highp vec3 _19668 = normalize(_19644 * _19666);
                vec3 mp_copy_19668 = _19668;
                float _19697 = dot(_19650, _19656);
                float _19699 = abs(_19697);
                float _19713 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19699)) * _19699)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19699) * _19699));
                float _27676 = 0.0;
                if (_19697 > 0.0)
                {
                    _27676 = _19713;
                }
                else
                {
                    _27676 = (0.5 * inversesqrt(max(1.0 - (_19697 * _19697), 1.0000000116860974230803549289703e-07))) - _19713;
                }
                float _19746 = dot(_19656, _19662);
                float _19748 = abs(_19746);
                float _19762 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19748)) * _19748)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19748) * _19748));
                float _27677 = 0.0;
                if (_19746 > 0.0)
                {
                    _27677 = _19762;
                }
                else
                {
                    _27677 = (0.5 * inversesqrt(max(1.0 - (_19746 * _19746), 1.0000000116860974230803549289703e-07))) - _19762;
                }
                float _19795 = dot(_19662, _19668);
                float _19797 = abs(_19795);
                float _19811 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19797)) * _19797)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19797) * _19797));
                float _27678 = 0.0;
                if (_19795 > 0.0)
                {
                    _27678 = _19811;
                }
                else
                {
                    _27678 = (0.5 * inversesqrt(max(1.0 - (_19795 * _19795), 1.0000000116860974230803549289703e-07))) - _19811;
                }
                float _19844 = dot(_19668, _19650);
                float _19846 = abs(_19844);
                float _19860 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _19846)) * _19846)) / (3.41759395599365234375 + ((4.1616725921630859375 + _19846) * _19846));
                float _27679 = 0.0;
                if (_19844 > 0.0)
                {
                    _27679 = _19860;
                }
                else
                {
                    _27679 = (0.5 * inversesqrt(max(1.0 - (_19844 * _19844), 1.0000000116860974230803549289703e-07))) - _19860;
                }
                vec3 _19683 = (((cross(mp_copy_19650, mp_copy_19656) * _27676) + (cross(mp_copy_19656, mp_copy_19662) * _27677)) + (cross(mp_copy_19662, mp_copy_19668) * _27678)) + (cross(mp_copy_19668, mp_copy_19650) * _27679);
                float _19886 = length(_19683);
                mat3 _19946 = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, 1.0)) * _19643;
                highp vec3 _19952 = normalize(_19946 * _19648);
                vec3 mp_copy_19952 = _19952;
                highp vec3 _19958 = normalize(_19946 * _19654);
                vec3 mp_copy_19958 = _19958;
                highp vec3 _19964 = normalize(_19946 * _19660);
                vec3 mp_copy_19964 = _19964;
                highp vec3 _19970 = normalize(_19946 * _19666);
                vec3 mp_copy_19970 = _19970;
                float _19999 = dot(_19952, _19958);
                float _20001 = abs(_19999);
                float _20015 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20001)) * _20001)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20001) * _20001));
                float _27680 = 0.0;
                if (_19999 > 0.0)
                {
                    _27680 = _20015;
                }
                else
                {
                    _27680 = (0.5 * inversesqrt(max(1.0 - (_19999 * _19999), 1.0000000116860974230803549289703e-07))) - _20015;
                }
                float _20048 = dot(_19958, _19964);
                float _20050 = abs(_20048);
                float _20064 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20050)) * _20050)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20050) * _20050));
                float _27681 = 0.0;
                if (_20048 > 0.0)
                {
                    _27681 = _20064;
                }
                else
                {
                    _27681 = (0.5 * inversesqrt(max(1.0 - (_20048 * _20048), 1.0000000116860974230803549289703e-07))) - _20064;
                }
                float _20097 = dot(_19964, _19970);
                float _20099 = abs(_20097);
                float _20113 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20099)) * _20099)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20099) * _20099));
                float _27682 = 0.0;
                if (_20097 > 0.0)
                {
                    _27682 = _20113;
                }
                else
                {
                    _27682 = (0.5 * inversesqrt(max(1.0 - (_20097 * _20097), 1.0000000116860974230803549289703e-07))) - _20113;
                }
                float _20146 = dot(_19970, _19952);
                float _20148 = abs(_20146);
                float _20162 = (0.8543984889984130859375 + ((0.4965155124664306640625 + (0.01452060043811798095703125 * _20148)) * _20148)) / (3.41759395599365234375 + ((4.1616725921630859375 + _20148) * _20148));
                float _27683 = 0.0;
                if (_20146 > 0.0)
                {
                    _27683 = _20162;
                }
                else
                {
                    _27683 = (0.5 * inversesqrt(max(1.0 - (_20146 * _20146), 1.0000000116860974230803549289703e-07))) - _20162;
                }
                vec3 _19985 = (((cross(mp_copy_19952, mp_copy_19958) * _27680) + (cross(mp_copy_19958, mp_copy_19964) * _27681)) + (cross(mp_copy_19964, mp_copy_19970) * _27682)) + (cross(mp_copy_19970, mp_copy_19952) * _27683);
                float _20188 = length(_19985);
                _27852 = _26039 + (((_8630 * (mp_copy_8693 * mp_copy_8693)) * step(0.0, dot(cross(_8662 - _8656, _8674 - _8656), v_position - _8656))) * (((((_8316 * _8721.x) + (_8433 * _8721.y)) * max(((_19886 * _19886) + _19683.z) / (_19886 + 1.0), 0.0)) * 1.0) + (_8451 * max(((_20188 * _20188) + _19985.z) / (_20188 + 1.0), 0.0))));
            }
            else
            {
                highp float hp_copy_27620 = 0.0;
                vec3 _27593 = vec3(0.0);
                highp vec3 _27616 = vec3(0.0);
                float _27620 = 0.0;
                if (_8628 < 0.5)
                {
                    _27620 = _24822;
                    _27616 = _8630;
                    _27593 = -normalize(texture(punctual_lights, vec2(0.3125, _19509)).xyz);
                }
                else
                {
                    highp vec3 _8808 = _19513.xyz - v_position;
                    highp float _8811 = dot(_8808, _8808);
                    highp float _8815 = inversesqrt(max(_8811, 9.9999999392252902907785028219223e-09));
                    highp vec3 _8816 = _8808 * _8815;
                    vec3 mp_copy_8816 = _8816;
                    highp float _8818 = _19530.w;
                    highp float _8823 = (_8811 * _8818) * _8818;
                    highp float _8828 = clamp(1.0 - (_8823 * _8823), 0.0, 1.0);
                    float mp_copy_8828 = _8828;
                    highp vec4 _20232 = texture(punctual_lights, vec2(0.4375, _19509));
                    highp float _8832 = _20232.w;
                    float _27624 = 0.0;
                    if (_8832 > 0.0)
                    {
                        highp float _8859 = (_24822 * _24822) + ((_8832 * 0.5) * _8815);
                        float mp_copy_8859 = _8859;
                        _27624 = sqrt(min(mp_copy_8859, 1.0));
                    }
                    else
                    {
                        _27624 = _24822;
                    }
                    highp vec3 _8866 = _8630 * ((mp_copy_8828 * mp_copy_8828) / max(pow(max(_8811, _8832 * _8832), _20232.z * 0.5), 9.9999997473787516355514526367188e-05));
                    highp vec3 _27617 = vec3(0.0);
                    if (_8628 > 1.5)
                    {
                        highp vec4 _20249 = texture(punctual_lights, vec2(0.3125, _19509));
                        highp float _8885 = clamp((dot(normalize(_20249.xyz), -mp_copy_8816) * _20249.w) + _20232.x, 0.0, 1.0);
                        float mp_copy_8885 = _8885;
                        highp vec3 _8890 = _8866 * (mp_copy_8885 * mp_copy_8885);
                        highp float _8892 = _20232.y;
                        bool _8893 = _8892 > (-0.5);
                        bool _8899 = false;
                        if (_8893)
                        {
                            _8899 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8899 = _8893;
                        }
                        highp vec3 _27618 = vec3(0.0);
                        if (_8899)
                        {
                            float _27584 = 0.0;
                            do
                            {
                                highp vec4 _20472 = texture(punctual_lights, vec2(0.5625, _19509));
                                highp vec4 _20489 = texture(punctual_lights, vec2(0.6875, _19509));
                                highp vec4 _20506 = texture(punctual_lights, vec2(0.8125, _19509));
                                highp vec4 _20523 = texture(punctual_lights, vec2(0.9375, _19509));
                                highp vec4 _20334 = mat4(_20472, _20489, _20506, _20523) * vec4(v_position + (_7186 * frag_info.spot_shadow_params.z), 1.0);
                                highp float _20336 = _20334.w;
                                if (_20336 <= 0.0)
                                {
                                    _27584 = 1.0;
                                    break;
                                }
                                highp vec3 _20345 = _20334.xyz / vec3(_20336);
                                highp vec2 _20350 = (_20345.xy * 0.5) + vec2(0.5);
                                highp float _20352 = _20350.x;
                                bool _20353 = _20352 < 0.0;
                                bool _20360 = false;
                                if (!_20353)
                                {
                                    _20360 = _20352 > 1.0;
                                }
                                else
                                {
                                    _20360 = _20353;
                                }
                                bool _20367 = false;
                                if (!_20360)
                                {
                                    _20367 = _20350.y < 0.0;
                                }
                                else
                                {
                                    _20367 = _20360;
                                }
                                bool _20374 = false;
                                if (!_20367)
                                {
                                    _20374 = _20350.y > 1.0;
                                }
                                else
                                {
                                    _20374 = _20367;
                                }
                                bool _20381 = false;
                                if (!_20374)
                                {
                                    _20381 = _20345.z < 0.0;
                                }
                                else
                                {
                                    _20381 = _20374;
                                }
                                bool _20388 = false;
                                if (!_20381)
                                {
                                    _20388 = _20345.z > 1.0;
                                }
                                else
                                {
                                    _20388 = _20381;
                                }
                                if (_20388)
                                {
                                    _27584 = 1.0;
                                    break;
                                }
                                highp float _20395 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                highp float _20400 = frag_info.shadow_cascade_count + float(int(_8892 + 0.5));
                                highp float _20405 = _20345.z - frag_info.spot_shadow_params.y;
                                highp float _20408 = frag_info.spot_shadow_params.w * 0.0040000001899898052215576171875;
                                highp float _20421 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27583 = 0.0;
                                _27583 = float(_20405 <= texture(shadow_map, vec2((_20400 + clamp(_20352, 0.0, 1.0)) / _20395, 1.0 - clamp(_20350.y, 0.0, 1.0))).x);
                                for (int _27582 = 0; _27582 < 8; )
                                {
                                    highp float _20431 = _20421 + (float(_27582) * 0.785398185253143310546875);
                                    float mp_copy_20431 = _20431;
                                    highp vec2 _20441 = _20350 + (vec2(cos(mp_copy_20431), sin(mp_copy_20431)) * _20408);
                                    highp float _20567 = float(_20405 <= texture(shadow_map, vec2((_20400 + clamp(_20441.x, 0.0, 1.0)) / _20395, 1.0 - clamp(_20441.y, 0.0, 1.0))).x);
                                    float mp_copy_20567 = _20567;
                                    _27583 += mp_copy_20567;
                                    _27582++;
                                    continue;
                                }
                                _27584 = _27583 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27618 = _8890 * _27584;
                        }
                        else
                        {
                            _27618 = _8890;
                        }
                        _27617 = _27618;
                    }
                    else
                    {
                        bool _8915 = _8628 > 0.5;
                        bool _8921 = false;
                        if (_8915)
                        {
                            _8921 = _20232.y > (-0.5);
                        }
                        else
                        {
                            _8921 = _8915;
                        }
                        bool _8927 = false;
                        if (_8921)
                        {
                            _8927 = frag_info.spot_shadow_params.x > 0.5;
                        }
                        else
                        {
                            _8927 = _8921;
                        }
                        highp vec3 _27619 = vec3(0.0);
                        if (_8927)
                        {
                            float _27569 = 0.0;
                            do
                            {
                                highp vec4 _20880 = texture(punctual_lights, vec2(0.5625, _19509));
                                highp vec4 _20897 = texture(punctual_lights, vec2(0.6875, _19509));
                                highp vec4 _20914 = texture(punctual_lights, _19510);
                                highp vec3 _20639 = (v_position + (_7186 * _20880.z)) - _20914.xyz;
                                highp vec3 _20641 = abs(_20639);
                                highp float _20643 = _20641.x;
                                highp float _20645 = _20641.y;
                                bool _20646 = _20643 >= _20645;
                                bool _20654 = false;
                                if (_20646)
                                {
                                    _20654 = _20643 >= _20641.z;
                                }
                                else
                                {
                                    _20654 = _20646;
                                }
                                highp vec3 _27559 = vec3(0.0);
                                float _27561 = 0.0;
                                if (_20654)
                                {
                                    highp float _20657 = _20639.x;
                                    bool _20658 = _20657 >= 0.0;
                                    highp vec3 _27558 = vec3(0.0);
                                    if (_20658)
                                    {
                                        _27558 = vec3(-_20639.z, _20639.y, _20657);
                                    }
                                    else
                                    {
                                        _27558 = vec3(_20639.zy, -_20657);
                                    }
                                    _27561 = _20658 ? 0.0 : 1.0;
                                    _27559 = _27558;
                                }
                                else
                                {
                                    highp vec3 _27560 = vec3(0.0);
                                    float _27563 = 0.0;
                                    if (_20645 >= _20641.z)
                                    {
                                        highp float _20691 = _20639.y;
                                        bool _20692 = _20691 >= 0.0;
                                        highp vec3 _27557 = vec3(0.0);
                                        if (_20692)
                                        {
                                            _27557 = vec3(-_20639.x, _20639.z, _20691);
                                        }
                                        else
                                        {
                                            _27557 = vec3(_20639.xz, -_20691);
                                        }
                                        _27563 = _20692 ? 2.0 : 3.0;
                                        _27560 = _27557;
                                    }
                                    else
                                    {
                                        highp float _20719 = _20639.z;
                                        bool _20720 = _20719 >= 0.0;
                                        highp vec3 _27556 = vec3(0.0);
                                        if (_20720)
                                        {
                                            _27556 = _20639;
                                        }
                                        else
                                        {
                                            _27556 = vec3(-_20639.x, _20639.y, -_20719);
                                        }
                                        _27563 = _20720 ? 4.0 : 5.0;
                                        _27560 = _27556;
                                    }
                                    _27561 = _27563;
                                    _27559 = _27560;
                                }
                                if (_27559.z <= 0.0)
                                {
                                    _27569 = 1.0;
                                    break;
                                }
                                highp vec2 _20760 = ((_27559.xy / vec2(_27559.z)) * 0.5) + vec2(0.5);
                                highp float _20771 = (_20880.x - (_20880.y / _27559.z)) - _20897.x;
                                if ((_20771 < 0.0) || (_20771 > 1.0))
                                {
                                    _27569 = 1.0;
                                    break;
                                }
                                highp float hp_copy_27566 = 0.0;
                                highp float _20783 = frag_info.shadow_cascade_count + frag_info.spot_shadow_params.x;
                                bool _20789 = _27561 >= 4.0;
                                highp float _20791 = (frag_info.shadow_cascade_count + _20232.y) + float(_20789);
                                float _27566 = 0.0;
                                if (_20789)
                                {
                                    _27566 = _27561 - 4.0;
                                }
                                else
                                {
                                    _27566 = _27561;
                                }
                                hp_copy_27566 = _27566;
                                highp float _20808 = _20897.y * 0.5;
                                highp float _20811 = _20880.w * 0.0040000001899898052215576171875;
                                highp vec2 _20922 = vec2(_20808);
                                highp vec2 _20925 = vec2(1.0 - _20808);
                                highp vec2 _20931 = vec2(mod(hp_copy_27566, 2.0), 1.0 - floor(hp_copy_27566 * 0.5)) * 0.5;
                                highp vec2 _20934 = _20931 + (clamp(_20760, _20922, _20925) * 0.5);
                                highp float _20827 = fract(52.98291778564453125 * fract(dot(gl_FragCoord.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125)))) * 6.283185482025146484375;
                                float _27568 = 0.0;
                                _27568 = float(_20771 <= texture(shadow_map, vec2((_20791 + _20934.x) / _20783, 1.0 - _20934.y)).x);
                                for (int _27567 = 0; _27567 < 8; )
                                {
                                    highp float _20837 = _20827 + (float(_27567) * 0.785398185253143310546875);
                                    float mp_copy_20837 = _20837;
                                    highp vec2 _20971 = _20931 + (clamp(_20760 + (vec2(cos(mp_copy_20837), sin(mp_copy_20837)) * _20811), _20922, _20925) * 0.5);
                                    highp float _20988 = float(_20771 <= texture(shadow_map, vec2((_20791 + _20971.x) / _20783, 1.0 - _20971.y)).x);
                                    float mp_copy_20988 = _20988;
                                    _27568 += mp_copy_20988;
                                    _27567++;
                                    continue;
                                }
                                _27569 = _27568 * 0.111111111938953399658203125;
                                break;
                            } while(false);
                            _27619 = _8866 * _27569;
                        }
                        else
                        {
                            _27619 = _8866;
                        }
                        _27617 = _27619;
                    }
                    _27620 = _27624;
                    _27616 = _27617;
                    _27593 = _8816;
                }
                hp_copy_27620 = _27620;
                highp vec3 _27647 = vec3(0.0);
                highp vec3 _27648 = vec3(0.0);
                do
                {
                    float _21054 = max(dot(_24769, _27593), 0.0);
                    highp float hp_copy_21054 = _21054;
                    if (_21054 <= 0.0)
                    {
                        _27648 = vec3(0.0);
                        _27647 = vec3(0.0);
                        break;
                    }
                    float _21060 = max(_8320, 9.9999997473787516355514526367188e-05);
                    highp float hp_copy_21060 = _21060;
                    vec3 _21063 = _27593 + mp_copy_24830;
                    float _21066 = dot(_21063, _21063);
                    vec3 _27645 = vec3(0.0);
                    vec3 _27646 = vec3(0.0);
                    if (_21066 > 9.9999999392252902907785028219223e-09)
                    {
                        vec3 _21074 = _21063 * inversesqrt(_21066);
                        float _27644 = 0.0;
                        do
                        {
                            float _21131 = dot(_24769, _21074);
                            if (_21131 <= 0.0)
                            {
                                _27644 = 0.0;
                                break;
                            }
                            float _21138 = _27620 * _27620;
                            vec3 _21141 = cross(_24769, _21074);
                            float _21144 = _21131 * _21138;
                            float _21153 = _21138 / (dot(_21141, _21141) + (_21144 * _21144));
                            _27644 = min((_21153 * _21153) * 0.3183098733425140380859375, 65504.0);
                            break;
                        } while(false);
                        vec3 _21191 = _8316 + (_8433 * pow(clamp(1.0 - max(dot(_21074, _24830), 0.0), 0.0, 1.0), 5.0));
                        _27646 = (_21191 * min(_27644 * (0.5 / max(mix((2.0 * hp_copy_21054) * _21060, hp_copy_21054 + hp_copy_21060, hp_copy_27620 * hp_copy_27620), 9.9999997473787516355514526367188e-06)), 65504.0)) * 1.0;
                        _27645 = _21191;
                    }
                    else
                    {
                        _27646 = vec3(0.0);
                        _27645 = _8316;
                    }
                    _27648 = (_27646 * _27616) * _21054;
                    _27647 = (((((vec3(1.0) - _27645) * _8450) * _8221) * 0.3183098733425140380859375) * _27616) * _21054;
                    break;
                } while(false);
                _27852 = _26039 + (_27647 + _27648);
            }
        }
        bool _8984 = _FogInfo.params0.y > 0.5;
        bool _8990 = false;
        if (_8984)
        {
            _8990 = _FogInfo.params0.w > 0.0;
        }
        else
        {
            _8990 = _8984;
        }
        highp vec3 _26046 = vec3(0.0);
        if (_8990)
        {
            vec3 mp_copy_26042 = vec3(0.0);
            highp vec3 _26042 = vec3(0.0);
            if (_9157)
            {
                _26042 = -view_info.camera_forward.xyz;
            }
            else
            {
                _26042 = normalize(v_viewvector);
            }
            mp_copy_26042 = _26042;
            vec3 _8995 = _8341 * (-mp_copy_26042);
            vec3 _26043 = vec3(0.0);
            do
            {
                if (_9471)
                {
                    vec2 _21313 = vec2(atan(_8995.z, _8995.x), asin(clamp(_8995.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21313 = _21313;
                    _26043 = textureLod(prefiltered_radiance, (hp_copy_21313 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                    break;
                }
                vec2 _21332 = vec2(atan(_8995.z, _8995.x), asin(clamp(_8995.y, -1.0, 1.0)));
                highp vec2 hp_copy_21332 = _21332;
                highp vec2 _21337 = (hp_copy_21332 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                highp float _21244 = clamp(_21337.y, 0.00390625, 0.99609375);
                float _21250 = floor(0.0);
                highp float _21269 = _21337.x;
                _26043 = mix(texture(prefiltered_radiance, vec2(_21269, (_21250 + _21244) * 0.125)).xyz, texture(prefiltered_radiance, vec2(_21269, (min(_21250 + 1.0, 7.0) + _21244) * 0.125)).xyz, vec3(-_21250));
                break;
            } while(false);
            highp vec3 _26045 = vec3(0.0);
            if (_8364)
            {
                vec3 _26044 = vec3(0.0);
                do
                {
                    if (_9471)
                    {
                        vec2 _21442 = vec2(atan(_8995.z, _8995.x), asin(clamp(_8995.y, -1.0, 1.0)));
                        highp vec2 hp_copy_21442 = _21442;
                        _26044 = textureLod(prefiltered_radiance_b, (hp_copy_21442 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5), 0.0).xyz;
                        break;
                    }
                    vec2 _21461 = vec2(atan(_8995.z, _8995.x), asin(clamp(_8995.y, -1.0, 1.0)));
                    highp vec2 hp_copy_21461 = _21461;
                    highp vec2 _21466 = (hp_copy_21461 * vec2(0.15915493667125701904296875, 0.3183098733425140380859375)) + vec2(0.5);
                    highp float _21373 = clamp(_21466.y, 0.00390625, 0.99609375);
                    float _21379 = floor(0.0);
                    highp float _21398 = _21466.x;
                    _26044 = mix(texture(prefiltered_radiance_b, vec2(_21398, (_21379 + _21373) * 0.125)).xyz, texture(prefiltered_radiance_b, vec2(_21398, (min(_21379 + 1.0, 7.0) + _21373) * 0.125)).xyz, vec3(-_21379));
                    break;
                } while(false);
                _26045 = mix(_26043, _26044, vec3(frag_info.radiance_blend.x));
            }
            else
            {
                _26045 = _26043;
            }
            _26046 = _26045 * frag_info.environment_intensity;
        }
        else
        {
            _26046 = _FogInfo.color.xyz;
        }
        highp vec4 _9019 = vec4(min((_26035 + (_26039 * mix(1.0, _25110, clamp(frag_info.ssao_lighting.x, 0.0, 1.0)))) + _7372, vec3(65504.0)), 1.0) * _28246;
        highp vec4 _26061 = vec4(0.0);
        do
        {
            if (_FogInfo.params0.y < 0.5)
            {
                _26061 = _9019;
                break;
            }
            int _21510 = int(_FogInfo.params0.x + 0.5);
            if (_21510 == 0)
            {
                _26061 = _9019;
                break;
            }
            highp float _26048 = 0.0;
            if (_9157)
            {
                _26048 = max(dot(-v_viewvector, view_info.camera_forward.xyz), 0.0);
            }
            else
            {
                _26048 = length(v_viewvector);
            }
            if ((_FogInfo.params1.w > 0.0) && (_26048 > _FogInfo.params1.w))
            {
                _26061 = _9019;
                break;
            }
            float _26052 = 0.0;
            if (_21510 == 1)
            {
                _26052 = clamp((_26048 - _FogInfo.params1.y) / max(_FogInfo.params1.z - _FogInfo.params1.y, 9.9999997473787516355514526367188e-05), 0.0, 1.0);
            }
            else
            {
                float _26053 = 0.0;
                if (_21510 == 2)
                {
                    highp float _26051 = 0.0;
                    if (_FogInfo.params2.y > 9.9999997473787516355514526367188e-06)
                    {
                        highp vec3 _26049 = vec3(0.0);
                        if (_9157)
                        {
                            _26049 = v_position - (view_info.camera_forward.xyz * _26048);
                        }
                        else
                        {
                            _26049 = v_position + v_viewvector;
                        }
                        highp float _21591 = -_FogInfo.params2.y;
                        highp float _21598 = _FogInfo.params1.x * exp(_21591 * (_26049.y - _FogInfo.params2.x));
                        highp float _21615 = _FogInfo.params2.y * (v_position.y - _26049.y);
                        highp float _26050 = 0.0;
                        if (abs(_21615) > 0.00124999997206032276153564453125)
                        {
                            _26050 = (_21598 - (_FogInfo.params1.x * exp(_21591 * (v_position.y - _FogInfo.params2.x)))) / _21615;
                        }
                        else
                        {
                            _26050 = _21598;
                        }
                        _26051 = _26050 * max(_26048 - _FogInfo.params1.y, 0.0);
                    }
                    else
                    {
                        _26051 = _FogInfo.params1.x * max(_26048 - _FogInfo.params1.y, 0.0);
                    }
                    _26053 = 1.0 - exp(-_26051);
                }
                else
                {
                    highp float _21653 = _FogInfo.params1.x * max(_26048 - _FogInfo.params1.y, 0.0);
                    _26053 = 1.0 - exp((-_21653) * _21653);
                }
                _26052 = _26053;
            }
            highp float _21665 = min(_26052, _FogInfo.params0.z);
            if (_21665 <= 0.0)
            {
                _26061 = _9019;
                break;
            }
            highp vec3 _21678 = mix(_FogInfo.color.xyz, _26046, vec3(_FogInfo.params0.w));
            bool _21681 = _FogInfo.sun.w > 0.5;
            bool _21687 = false;
            if (_21681)
            {
                _21687 = _FogInfo.params2.z > 0.0;
            }
            else
            {
                _21687 = _21681;
            }
            vec3 _26057 = vec3(0.0);
            if (_21687)
            {
                vec3 mp_copy_26054 = vec3(0.0);
                highp vec3 _26054 = vec3(0.0);
                if (_9157)
                {
                    _26054 = -view_info.camera_forward.xyz;
                }
                else
                {
                    _26054 = normalize(v_viewvector);
                }
                mp_copy_26054 = _26054;
                highp float _21703 = pow(max(dot(-mp_copy_26054, -normalize(_FogInfo.sun_dir.xyz)), 0.0), _FogInfo.params2.w);
                float mp_copy_21703 = _21703;
                _26057 = _21678 + ((_FogInfo.sun.xyz * mp_copy_21703) * _FogInfo.params2.z);
            }
            else
            {
                _26057 = _21678;
            }
            highp float _21716 = _9019.w;
            float mp_copy_21716 = _21716;
            _26061 = vec4(mix(_9019.xyz, _26057 * mp_copy_21716, vec3(_21665)), _21716);
            break;
        } while(false);
        _27478 = _26061;
    }
    else
    {
        _27478 = vec4(0.0);
    }
    float _27481 = 0.0;
    do
    {
        if (_7995)
        {
            _27481 = 0.0;
            break;
        }
        if (debug_view_info.view.y < 0.0)
        {
            _27481 = 1.0;
            break;
        }
        _27481 = (debug_view_info.left.x > 0.5) ? 3.0 : 2.0;
        break;
    } while(false);
    bool _21766 = gl_FragCoord.x >= debug_view_info.view.y;
    bool _21768 = _27481 > 0.5;
    vec4 _27553 = vec4(0.0);
    if (_21768)
    {
        bool _21774 = (_27481 > 2.5) && (!_21766);
        vec4 _27482 = vec4(0.0);
        if (_21774)
        {
            _27482 = vec4(debug_view_info.left.x, debug_view_info.view.y, debug_view_info.left.y, debug_view_info.view.w);
        }
        else
        {
            _27482 = debug_view_info.view;
        }
        vec2 _27483 = vec2(0.0);
        if (_21774)
        {
            _27483 = debug_view_info.left.zw;
        }
        else
        {
            _27483 = debug_view_info.params.xy;
        }
        vec4 _27551 = vec4(0.0);
        do
        {
            if (_27482.x < 20.0)
            {
                vec3 _27537 = vec3(0.0);
                if (_27482.x == 1.0)
                {
                    float _22251 = length(_7186);
                    vec3 _27536 = vec3(0.0);
                    if (_22251 > 9.9999999747524270787835121154785e-07)
                    {
                        _27536 = _7186 / vec3(_22251);
                    }
                    else
                    {
                        _27536 = vec3(0.0);
                    }
                    _27537 = ((_27536 * 0.5) + vec3(0.5)) * _27482.z;
                }
                else
                {
                    vec3 _27538 = vec3(0.0);
                    if (_27482.x == 2.0)
                    {
                        float _22274 = length(_24769);
                        vec3 _27535 = vec3(0.0);
                        if (_22274 > 9.9999999747524270787835121154785e-07)
                        {
                            _27535 = _24769 / vec3(_22274);
                        }
                        else
                        {
                            _27535 = vec3(0.0);
                        }
                        _27538 = ((_27535 * 0.5) + vec3(0.5)) * _27482.z;
                    }
                    else
                    {
                        vec3 _27539 = vec3(0.0);
                        if (_27482.x == 3.0)
                        {
                            float _22297 = length(v_tangent.xyz);
                            vec3 _27534 = vec3(0.0);
                            if (_22297 > 9.9999999747524270787835121154785e-07)
                            {
                                _27534 = v_tangent.xyz / vec3(_22297);
                            }
                            else
                            {
                                _27534 = vec3(0.0);
                            }
                            _27539 = ((_27534 * 0.5) + vec3(0.5)) * _27482.z;
                        }
                        else
                        {
                            vec3 _27540 = vec3(0.0);
                            if (_27482.x == 4.0)
                            {
                                highp float _21930 = (v_tangent.w < 0.0) ? (-1.0) : 1.0;
                                float mp_copy_21930 = _21930;
                                vec3 _21931 = cross(_7184, v_tangent.xyz) * mp_copy_21930;
                                float _22320 = length(_21931);
                                vec3 _27533 = vec3(0.0);
                                if (_22320 > 9.9999999747524270787835121154785e-07)
                                {
                                    _27533 = _21931 / vec3(_22320);
                                }
                                else
                                {
                                    _27533 = vec3(0.0);
                                }
                                _27540 = ((_27533 * 0.5) + vec3(0.5)) * _27482.z;
                            }
                            else
                            {
                                vec3 _27541 = vec3(0.0);
                                if (_27482.x == 5.0)
                                {
                                    _27541 = vec3((v_tangent.w < 0.0) ? 0.0 : 1.0);
                                }
                                else
                                {
                                    vec3 _27542 = vec3(0.0);
                                    if (_27482.x == 6.0)
                                    {
                                        _27542 = vec3(clamp(v_texture_coords, vec2(0.0), vec2(1.0)), 0.0) * _27482.z;
                                    }
                                    else
                                    {
                                        vec3 _27543 = vec3(0.0);
                                        if (_27482.x == 7.0)
                                        {
                                            _27543 = vec3(clamp(v_texture_coords_1, vec2(0.0), vec2(1.0)), 0.0) * _27482.z;
                                        }
                                        else
                                        {
                                            vec3 _27544 = vec3(0.0);
                                            if (_27482.x == 8.0)
                                            {
                                                vec3 _22355 = max(v_color.xyz * _27482.z, vec3(0.0));
                                                _27544 = mix(_22355 * 12.9200000762939453125, (pow(max(_22355, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22355));
                                            }
                                            else
                                            {
                                                vec3 _27545 = vec3(0.0);
                                                if (_27482.x == 9.0)
                                                {
                                                    vec3 mp_copy_27531 = vec3(0.0);
                                                    highp vec3 _27531 = vec3(0.0);
                                                    if (view_info.camera_forward.w > 0.5)
                                                    {
                                                        _27531 = -view_info.camera_forward.xyz;
                                                    }
                                                    else
                                                    {
                                                        _27531 = normalize(v_viewvector);
                                                    }
                                                    mp_copy_27531 = _27531;
                                                    float _22391 = length(mp_copy_27531);
                                                    vec3 _27532 = vec3(0.0);
                                                    if (_22391 > 9.9999999747524270787835121154785e-07)
                                                    {
                                                        _27532 = mp_copy_27531 / vec3(_22391);
                                                    }
                                                    else
                                                    {
                                                        _27532 = vec3(0.0);
                                                    }
                                                    _27545 = ((_27532 * 0.5) + vec3(0.5)) * _27482.z;
                                                }
                                                else
                                                {
                                                    vec3 _27546 = vec3(0.0);
                                                    if (_27482.x == 10.0)
                                                    {
                                                        float _22434 = max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                                                        float _22435 = (v_position.x - _27483.x) / _22434;
                                                        bool _22439 = _27482.w > 1.5;
                                                        float _27525 = 0.0;
                                                        if (_22439)
                                                        {
                                                            _27525 = fract(_22435);
                                                        }
                                                        else
                                                        {
                                                            float _27526 = 0.0;
                                                            if (_27482.w > 0.5)
                                                            {
                                                                _27526 = ((_22435 < 0.0) || (_22435 > 1.0)) ? 0.0 : _22435;
                                                            }
                                                            else
                                                            {
                                                                _27526 = clamp(_22435, 0.0, 1.0);
                                                            }
                                                            _27525 = _27526;
                                                        }
                                                        float _22486 = (v_position.y - _27483.x) / _22434;
                                                        float _27527 = 0.0;
                                                        if (_22439)
                                                        {
                                                            _27527 = fract(_22486);
                                                        }
                                                        else
                                                        {
                                                            float _27528 = 0.0;
                                                            if (_27482.w > 0.5)
                                                            {
                                                                _27528 = ((_22486 < 0.0) || (_22486 > 1.0)) ? 0.0 : _22486;
                                                            }
                                                            else
                                                            {
                                                                _27528 = clamp(_22486, 0.0, 1.0);
                                                            }
                                                            _27527 = _27528;
                                                        }
                                                        float _22537 = (v_position.z - _27483.x) / _22434;
                                                        float _27529 = 0.0;
                                                        if (_22439)
                                                        {
                                                            _27529 = fract(_22537);
                                                        }
                                                        else
                                                        {
                                                            float _27530 = 0.0;
                                                            if (_27482.w > 0.5)
                                                            {
                                                                _27530 = ((_22537 < 0.0) || (_22537 > 1.0)) ? 0.0 : _22537;
                                                            }
                                                            else
                                                            {
                                                                _27530 = clamp(_22537, 0.0, 1.0);
                                                            }
                                                            _27529 = _27530;
                                                        }
                                                        _27546 = vec3(_27525 * _27482.z, _27527 * _27482.z, _27529 * _27482.z);
                                                    }
                                                    else
                                                    {
                                                        vec3 _27547 = vec3(0.0);
                                                        if (_27482.x == 11.0)
                                                        {
                                                            bvec3 _22006 = bvec3(gl_FrontFacing);
                                                            _27547 = vec3(_22006.x ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).x : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).x, _22006.y ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).y : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).y, _22006.z ? vec3(0.449999988079071044921875, 0.60000002384185791015625, 1.0).z : vec3(1.0, 0.1500000059604644775390625, 0.100000001490116119384765625).z);
                                                        }
                                                        else
                                                        {
                                                            vec3 _27548 = vec3(0.0);
                                                            if (_27482.x == 12.0)
                                                            {
                                                                highp vec2 _22564 = v_texture_coords;
                                                                vec2 mp_copy_22564 = _22564;
                                                                vec2 _22576 = floor(mp_copy_22564 * 8.0);
                                                                float _22578 = _22576.x;
                                                                float _22580 = _22576.y;
                                                                float _22588 = _22578 + (_22580 * 8.0);
                                                                vec2 _22597 = step(vec2(0.0), mp_copy_22564) * step(mp_copy_22564, vec2(1.0));
                                                                _27548 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22578 + _22580, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22588 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22588 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22597.x * _22597.y));
                                                            }
                                                            else
                                                            {
                                                                vec3 _27549 = vec3(0.0);
                                                                if (_27482.x == 13.0)
                                                                {
                                                                    highp vec2 _22647 = v_texture_coords_1;
                                                                    vec2 mp_copy_22647 = _22647;
                                                                    vec2 _22659 = floor(mp_copy_22647 * 8.0);
                                                                    float _22661 = _22659.x;
                                                                    float _22663 = _22659.y;
                                                                    float _22671 = _22661 + (_22663 * 8.0);
                                                                    vec2 _22680 = step(vec2(0.0), mp_copy_22647) * step(mp_copy_22647, vec2(1.0));
                                                                    _27549 = mix(vec3(0.60000002384185791015625, 0.0, 0.0), mix(mix(vec3(0.1500000059604644775390625), vec3(0.89999997615814208984375), vec3(mod(_22661 + _22663, 2.0))), mix(vec3(1.0), clamp(abs((fract(vec3(fract(_22671 * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(_22671 * 0.3819660246372222900390625)))) * 0.85000002384185791015625, vec3(0.3499999940395355224609375)), vec3(_22680.x * _22680.y));
                                                                }
                                                                else
                                                                {
                                                                    vec3 _27550 = vec3(0.0);
                                                                    if (_27482.x == 14.0)
                                                                    {
                                                                        highp float _22746 = max(gl_FragCoord.w, 9.9999999600419720025001879548654e-13);
                                                                        bool _22752 = debug_view_info.depth.x > 0.5;
                                                                        bool _22758 = false;
                                                                        if (_22752)
                                                                        {
                                                                            _22758 = debug_view_info.depth.y > 0.5;
                                                                        }
                                                                        else
                                                                        {
                                                                            _22758 = _22752;
                                                                        }
                                                                        highp float _27521 = 0.0;
                                                                        if (_22758)
                                                                        {
                                                                            _27521 = 1.1920928955078125e-07 / _22746;
                                                                        }
                                                                        else
                                                                        {
                                                                            highp float _27522 = 0.0;
                                                                            if (_22752)
                                                                            {
                                                                                _27522 = 5.9604644775390625e-08 / (_22746 * max(gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            else
                                                                            {
                                                                                _27522 = 5.9604644775390625e-08 / (_22746 * max(1.0 - gl_FragCoord.z, 9.9999999600419720025001879548654e-13));
                                                                            }
                                                                            _27521 = _27522;
                                                                        }
                                                                        highp float _22787 = dot(_7186, view_info.camera_forward.xyz);
                                                                        highp float _22793 = sqrt(max(1.0 - (_22787 * _22787), 0.0));
                                                                        highp float _27519 = 0.0;
                                                                        if (view_info.camera_forward.w > 0.5)
                                                                        {
                                                                            _27519 = (debug_view_info.depth.z * _22793) / max(abs(_22787), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        else
                                                                        {
                                                                            _27519 = (((1.0 / (_22746 * _22746)) * debug_view_info.depth.z) * _22793) / max(abs(dot(_7186, v_viewvector)), 9.9999999747524270787835121154785e-07);
                                                                        }
                                                                        highp float _22831 = log2(max(max(8.0 * _27521, _27519 * 0.0625), 9.9999999600419720025001879548654e-13)) * 0.3010300099849700927734375;
                                                                        float mp_copy_22831 = _22831;
                                                                        float _22870 = (mp_copy_22831 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                                                                        float _27523 = 0.0;
                                                                        if (_27482.w > 1.5)
                                                                        {
                                                                            _27523 = fract(_22870);
                                                                        }
                                                                        else
                                                                        {
                                                                            float _27524 = 0.0;
                                                                            if (_27482.w > 0.5)
                                                                            {
                                                                                _27524 = ((_22870 < 0.0) || (_22870 > 1.0)) ? 0.0 : _22870;
                                                                            }
                                                                            else
                                                                            {
                                                                                _27524 = clamp(_22870, 0.0, 1.0);
                                                                            }
                                                                            _27523 = _27524;
                                                                        }
                                                                        _27550 = clamp(vec3(1.5) - abs(vec3(4.0 * _27523) - vec3(3.0, 2.0, 1.0)), vec3(0.0), vec3(1.0)) * _27482.z;
                                                                    }
                                                                    else
                                                                    {
                                                                        vec2 _22903 = floor(gl_FragCoord.xy * vec2(0.125));
                                                                        _27550 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_22903.x + _22903.y, 2.0)));
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
                    _27537 = _27538;
                }
                _27551 = vec4(_27537, 1.0);
                break;
            }
            vec3 _27498 = vec3(0.0);
            if (_27482.x < 40.0)
            {
                vec3 _27499 = vec3(0.0);
                if (_27482.x == 20.0)
                {
                    vec3 _22924 = max(_7273.xyz * _27482.z, vec3(0.0));
                    _27499 = mix(_22924 * 12.9200000762939453125, (pow(max(_22924, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _22924));
                }
                else
                {
                    vec3 _27500 = vec3(0.0);
                    if (_27482.x == 21.0)
                    {
                        float _22963 = (_28246 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                        float _27496 = 0.0;
                        if (_27482.w > 1.5)
                        {
                            _27496 = fract(_22963);
                        }
                        else
                        {
                            float _27497 = 0.0;
                            if (_27482.w > 0.5)
                            {
                                _27497 = ((_22963 < 0.0) || (_22963 > 1.0)) ? 0.0 : _22963;
                            }
                            else
                            {
                                _27497 = clamp(_22963, 0.0, 1.0);
                            }
                            _27496 = _27497;
                        }
                        _27500 = vec3(_27496 * _27482.z);
                    }
                    else
                    {
                        vec3 _27501 = vec3(0.0);
                        if (_27482.x == 22.0)
                        {
                            float _23014 = (_7319 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                            float _27494 = 0.0;
                            if (_27482.w > 1.5)
                            {
                                _27494 = fract(_23014);
                            }
                            else
                            {
                                float _27495 = 0.0;
                                if (_27482.w > 0.5)
                                {
                                    _27495 = ((_23014 < 0.0) || (_23014 > 1.0)) ? 0.0 : _23014;
                                }
                                else
                                {
                                    _27495 = clamp(_23014, 0.0, 1.0);
                                }
                                _27494 = _27495;
                            }
                            _27501 = vec3(_27494 * _27482.z);
                        }
                        else
                        {
                            vec3 _27502 = vec3(0.0);
                            if (_27482.x == 23.0)
                            {
                                float _23065 = (_7326 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                                float _27492 = 0.0;
                                if (_27482.w > 1.5)
                                {
                                    _27492 = fract(_23065);
                                }
                                else
                                {
                                    float _27493 = 0.0;
                                    if (_27482.w > 0.5)
                                    {
                                        _27493 = ((_23065 < 0.0) || (_23065 > 1.0)) ? 0.0 : _23065;
                                    }
                                    else
                                    {
                                        _27493 = clamp(_23065, 0.0, 1.0);
                                    }
                                    _27492 = _27493;
                                }
                                _27502 = vec3(_27492 * _27482.z);
                            }
                            else
                            {
                                vec3 _27503 = vec3(0.0);
                                if (_27482.x == 24.0)
                                {
                                    float _23116 = (1.0 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                                    float _27490 = 0.0;
                                    if (_27482.w > 1.5)
                                    {
                                        _27490 = fract(_23116);
                                    }
                                    else
                                    {
                                        float _27491 = 0.0;
                                        if (_27482.w > 0.5)
                                        {
                                            _27491 = ((_23116 < 0.0) || (_23116 > 1.0)) ? 0.0 : _23116;
                                        }
                                        else
                                        {
                                            _27491 = clamp(_23116, 0.0, 1.0);
                                        }
                                        _27490 = _27491;
                                    }
                                    _27503 = vec3(_27490 * _27482.z);
                                }
                                else
                                {
                                    vec3 _27504 = vec3(0.0);
                                    if (_27482.x == 25.0)
                                    {
                                        float _23167 = (_7348 - _27483.x) / max(_27483.y - _27483.x, 9.9999999747524270787835121154785e-07);
                                        float _27488 = 0.0;
                                        if (_27482.w > 1.5)
                                        {
                                            _27488 = fract(_23167);
                                        }
                                        else
                                        {
                                            float _27489 = 0.0;
                                            if (_27482.w > 0.5)
                                            {
                                                _27489 = ((_23167 < 0.0) || (_23167 > 1.0)) ? 0.0 : _23167;
                                            }
                                            else
                                            {
                                                _27489 = clamp(_23167, 0.0, 1.0);
                                            }
                                            _27488 = _27489;
                                        }
                                        _27504 = vec3(_27488 * _27482.z);
                                    }
                                    else
                                    {
                                        vec3 _27505 = vec3(0.0);
                                        if (_27482.x == 26.0)
                                        {
                                            vec3 _23203 = max(_7372 * _27482.z, vec3(0.0));
                                            _27505 = mix(_23203 * 12.9200000762939453125, (pow(max(_23203, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _23203));
                                        }
                                        else
                                        {
                                            vec2 _23224 = floor(gl_FragCoord.xy * vec2(0.125));
                                            _27505 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23224.x + _23224.y, 2.0)));
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
                _27498 = _27499;
            }
            else
            {
                vec3 _27506 = vec3(0.0);
                if (_27482.x < 60.0)
                {
                    vec2 _23245 = floor(gl_FragCoord.xy * vec2(0.125));
                    _27506 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23245.x + _23245.y, 2.0)));
                }
                else
                {
                    vec3 _27507 = vec3(0.0);
                    if (_27482.x < 70.0)
                    {
                        vec3 _27508 = vec3(0.0);
                        if (_27482.x == 60.0)
                        {
                            _27508 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.z * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.z * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _27482.z;
                        }
                        else
                        {
                            vec3 _27509 = vec3(0.0);
                            if (_27482.x == 61.0)
                            {
                                _27509 = (mix(vec3(1.0), clamp(abs((fract(vec3(fract(debug_view_info.params.w * 0.61803400516510009765625)) + vec3(1.0, 0.666666686534881591796875, 0.3333333432674407958984375)) * 6.0) - vec3(3.0)) - vec3(1.0), vec3(0.0), vec3(1.0)), vec3(0.550000011920928955078125 + (0.3499999940395355224609375 * fract(debug_view_info.params.w * 0.3819660246372222900390625)))) * 0.85000002384185791015625) * _27482.z;
                            }
                            else
                            {
                                vec2 _23333 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27509 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23333.x + _23333.y, 2.0)));
                            }
                            _27508 = _27509;
                        }
                        _27507 = _27508;
                    }
                    else
                    {
                        vec3 _27510 = vec3(0.0);
                        if (_27482.x < 80.0)
                        {
                            vec3 _27511 = vec3(0.0);
                            if (_27482.x == 70.0)
                            {
                                bool _23350 = v_texture_coords.x < 0.0;
                                bool _23357 = false;
                                if (!_23350)
                                {
                                    _23357 = v_texture_coords.x > 1.0;
                                }
                                else
                                {
                                    _23357 = _23350;
                                }
                                bool _23364 = false;
                                if (!_23357)
                                {
                                    _23364 = v_texture_coords.y < 0.0;
                                }
                                else
                                {
                                    _23364 = _23357;
                                }
                                bool _23371 = false;
                                if (!_23364)
                                {
                                    _23371 = v_texture_coords.y > 1.0;
                                }
                                else
                                {
                                    _23371 = _23364;
                                }
                                bvec3 _23374 = bvec3(_23371);
                                highp vec3 _23375 = vec3(_23374.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23374.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23374.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                bvec3 _23400 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24769), normalize(_7186)) < 0.999000012874603271484375));
                                highp vec3 _23401 = vec3(_23400.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : _23375.x, _23400.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : _23375.y, _23400.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : _23375.z);
                                float _23415 = length(v_normal);
                                bvec3 _23422 = bvec3((_23415 < 0.300000011920928955078125) || (_23415 > 1.7000000476837158203125));
                                highp vec3 _23423 = vec3(_23422.x ? vec3(1.0, 0.5, 0.0).x : _23401.x, _23422.y ? vec3(1.0, 0.5, 0.0).y : _23401.y, _23422.z ? vec3(1.0, 0.5, 0.0).z : _23401.z);
                                bool _23428 = _7319 > 0.0500000007450580596923828125;
                                bool _23434 = false;
                                if (_23428)
                                {
                                    _23434 = _7319 < 0.949999988079071044921875;
                                }
                                else
                                {
                                    _23434 = _23428;
                                }
                                vec3 _23446 = vec3(0.0);
                                bvec3 _23436 = bvec3(_23434);
                                highp vec3 _23437 = vec3(_23436.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : _23423.x, _23436.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : _23423.y, _23436.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : _23423.z);
                                vec3 _27486 = vec3(0.0);
                                do
                                {
                                    _23446 = _7273.xyz;
                                    float _23447 = dot(_23446, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                    if (_7319 > 0.5)
                                    {
                                        _27486 = _23437;
                                        break;
                                    }
                                    if (_23447 < 0.0130000002682209014892578125)
                                    {
                                        _27486 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                        break;
                                    }
                                    if (_23447 > 0.87000000476837158203125)
                                    {
                                        _27486 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                        break;
                                    }
                                    _27486 = _23437;
                                    break;
                                } while(false);
                                vec3 _27487 = vec3(0.0);
                                do
                                {
                                    vec3 _23492 = ((_23446 + _24769) + _7372) + vec3((_7319 + _7326) + _7348);
                                    bool _23507 = min(min(_7270, _7271), _7272) < 0.0;
                                    bool _23520 = false;
                                    if (!_23507)
                                    {
                                        _23520 = min(min(_7372.x, _7372.y), _7372.z) < 0.0;
                                    }
                                    else
                                    {
                                        _23520 = _23507;
                                    }
                                    if (any(isnan(_23492)))
                                    {
                                        _27487 = vec3(1.0, 0.0, 0.0);
                                        break;
                                    }
                                    if (any(isinf(_23492)))
                                    {
                                        _27487 = vec3(0.0, 1.0, 0.0);
                                        break;
                                    }
                                    if (_23520)
                                    {
                                        _27487 = vec3(0.0, 0.25, 1.0);
                                        break;
                                    }
                                    _27487 = _27486;
                                    break;
                                } while(false);
                                _27511 = _27487;
                            }
                            else
                            {
                                vec3 _27512 = vec3(0.0);
                                if (_27482.x == 71.0)
                                {
                                    vec3 _27485 = vec3(0.0);
                                    do
                                    {
                                        vec3 _23560 = ((_7273.xyz + _24769) + _7372) + vec3((_7319 + _7326) + _7348);
                                        bool _23575 = min(min(_7270, _7271), _7272) < 0.0;
                                        bool _23588 = false;
                                        if (!_23575)
                                        {
                                            _23588 = min(min(_7372.x, _7372.y), _7372.z) < 0.0;
                                        }
                                        else
                                        {
                                            _23588 = _23575;
                                        }
                                        if (any(isnan(_23560)))
                                        {
                                            _27485 = vec3(1.0, 0.0, 0.0);
                                            break;
                                        }
                                        if (any(isinf(_23560)))
                                        {
                                            _27485 = vec3(0.0, 1.0, 0.0);
                                            break;
                                        }
                                        if (_23588)
                                        {
                                            _27485 = vec3(0.0, 0.25, 1.0);
                                            break;
                                        }
                                        _27485 = vec3(0.3499999940395355224609375);
                                        break;
                                    } while(false);
                                    _27512 = _27485;
                                }
                                else
                                {
                                    vec3 _27513 = vec3(0.0);
                                    if (_27482.x == 72.0)
                                    {
                                        vec3 _27484 = vec3(0.0);
                                        do
                                        {
                                            float _23610 = dot(_7273.xyz, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
                                            if (_7319 > 0.5)
                                            {
                                                _27484 = vec3(0.3499999940395355224609375);
                                                break;
                                            }
                                            if (_23610 < 0.0130000002682209014892578125)
                                            {
                                                _27484 = vec3(0.100000001490116119384765625, 0.300000011920928955078125, 1.0);
                                                break;
                                            }
                                            if (_23610 > 0.87000000476837158203125)
                                            {
                                                _27484 = vec3(1.0, 0.20000000298023223876953125, 0.100000001490116119384765625);
                                                break;
                                            }
                                            _27484 = vec3(0.3499999940395355224609375);
                                            break;
                                        } while(false);
                                        _27513 = _27484;
                                    }
                                    else
                                    {
                                        vec3 _27514 = vec3(0.0);
                                        if (_27482.x == 73.0)
                                        {
                                            bool _23632 = _7319 > 0.0500000007450580596923828125;
                                            bool _23638 = false;
                                            if (_23632)
                                            {
                                                _23638 = _7319 < 0.949999988079071044921875;
                                            }
                                            else
                                            {
                                                _23638 = _23632;
                                            }
                                            bvec3 _23640 = bvec3(_23638);
                                            _27514 = vec3(_23640.x ? vec3(1.0, 0.85000002384185791015625, 0.0).x : vec3(0.3499999940395355224609375).x, _23640.y ? vec3(1.0, 0.85000002384185791015625, 0.0).y : vec3(0.3499999940395355224609375).y, _23640.z ? vec3(1.0, 0.85000002384185791015625, 0.0).z : vec3(0.3499999940395355224609375).z);
                                        }
                                        else
                                        {
                                            vec3 _27515 = vec3(0.0);
                                            if (_27482.x == 74.0)
                                            {
                                                float _23646 = length(v_normal);
                                                bvec3 _23653 = bvec3((_23646 < 0.300000011920928955078125) || (_23646 > 1.7000000476837158203125));
                                                _27515 = vec3(_23653.x ? vec3(1.0, 0.5, 0.0).x : vec3(0.3499999940395355224609375).x, _23653.y ? vec3(1.0, 0.5, 0.0).y : vec3(0.3499999940395355224609375).y, _23653.z ? vec3(1.0, 0.5, 0.0).z : vec3(0.3499999940395355224609375).z);
                                            }
                                            else
                                            {
                                                vec3 _27516 = vec3(0.0);
                                                if (_27482.x == 75.0)
                                                {
                                                    bvec3 _23676 = bvec3((dot(v_tangent.xyz, v_tangent.xyz) < 9.9999999392252902907785028219223e-09) && (dot(normalize(_24769), normalize(_7186)) < 0.999000012874603271484375));
                                                    _27516 = vec3(_23676.x ? vec3(1.0, 0.0, 0.60000002384185791015625).x : vec3(0.3499999940395355224609375).x, _23676.y ? vec3(1.0, 0.0, 0.60000002384185791015625).y : vec3(0.3499999940395355224609375).y, _23676.z ? vec3(1.0, 0.0, 0.60000002384185791015625).z : vec3(0.3499999940395355224609375).z);
                                                }
                                                else
                                                {
                                                    vec3 _27517 = vec3(0.0);
                                                    if (_27482.x == 76.0)
                                                    {
                                                        bool _23694 = v_texture_coords.x < 0.0;
                                                        bool _23701 = false;
                                                        if (!_23694)
                                                        {
                                                            _23701 = v_texture_coords.x > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23701 = _23694;
                                                        }
                                                        bool _23708 = false;
                                                        if (!_23701)
                                                        {
                                                            _23708 = v_texture_coords.y < 0.0;
                                                        }
                                                        else
                                                        {
                                                            _23708 = _23701;
                                                        }
                                                        bool _23715 = false;
                                                        if (!_23708)
                                                        {
                                                            _23715 = v_texture_coords.y > 1.0;
                                                        }
                                                        else
                                                        {
                                                            _23715 = _23708;
                                                        }
                                                        bvec3 _23718 = bvec3(_23715);
                                                        _27517 = vec3(_23718.x ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).x : vec3(0.3499999940395355224609375).x, _23718.y ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).y : vec3(0.3499999940395355224609375).y, _23718.z ? vec3(0.89999997615814208984375, 0.89999997615814208984375, 0.0).z : vec3(0.3499999940395355224609375).z);
                                                    }
                                                    else
                                                    {
                                                        vec2 _23731 = floor(gl_FragCoord.xy * vec2(0.125));
                                                        _27517 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23731.x + _23731.y, 2.0)));
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
                            _27510 = _27511;
                        }
                        else
                        {
                            vec3 _27518 = vec3(0.0);
                            if (_27482.x == 80.0)
                            {
                                _27518 = vec3(0.0);
                            }
                            else
                            {
                                vec2 _23749 = floor(gl_FragCoord.xy * vec2(0.125));
                                _27518 = vec3(mix(0.2199999988079071044921875, 0.319999992847442626953125, mod(_23749.x + _23749.y, 2.0)));
                            }
                            _27510 = _27518;
                        }
                        _27507 = _27510;
                    }
                    _27506 = _27507;
                }
                _27498 = _27506;
            }
            _27551 = vec4(_27498, 1.0);
            break;
        } while(false);
        _27553 = _27551;
    }
    else
    {
        _27553 = vec4(0.0);
    }
    bool _21816 = false;
    if (_21768)
    {
        _21816 = ((_27481 < 1.5) || (_27481 > 2.5)) || _21766;
    }
    else
    {
        _21816 = _21768;
    }
    bvec4 _21820 = bvec4(_21816);
    frag_color = vec4(_21820.x ? _27553.x : _27478.x, _21820.y ? _27553.y : _27478.y, _21820.z ? _27553.z : _27478.z, _21820.w ? _27553.w : _27478.w);
    float _27554 = 0.0;
    if (frag_info.fade >= 1.0)
    {
        _27554 = 1.0;
    }
    else
    {
        _27554 = abs(frag_info.fade);
    }
    frag_color *= _27554;
}

