#version 300 es
precision mediump float;
precision highp int;

layout(std140) uniform ResolveInfo
{
    highp float exposure;
    highp float tone_mapping_mode;
    highp float flip_y;
    highp float grading_enabled;
    highp float brightness;
    highp float contrast;
    highp float saturation;
    highp float temperature;
    highp float tint;
    highp float _pad0;
    highp float _pad1;
    highp float _pad2;
    highp vec4 lift;
    highp vec4 gamma;
    highp vec4 gain;
    highp float chromatic_aberration_enabled;
    highp float chromatic_aberration_intensity;
    highp float time;
    highp float _pad3;
    highp float vignette_enabled;
    highp float vignette_intensity;
    highp float vignette_radius;
    highp float vignette_smoothness;
    highp float grain_enabled;
    highp float grain_intensity;
    highp float _pad4;
    highp float _pad5;
    highp float bloom_enabled;
    highp float bloom_intensity;
    highp float debug_view_active;
    highp float debug_view_split;
    highp vec4 agx_params;
    highp vec4 lut_params;
} resolve_info;

uniform highp sampler2D bloom_color;
uniform highp sampler2D grading_lut;
uniform highp sampler2D scene_color;
uniform highp sampler2D exposure_factor;

in highp vec2 v_uv;
layout(location = 0) out highp vec4 frag_color;

void main()
{
    do
    {
        highp vec2 _2861 = vec2(0.0);
        if (resolve_info.flip_y > 0.5)
        {
            _2861 = vec2(v_uv.x, 1.0 - v_uv.y);
        }
        else
        {
            _2861 = v_uv;
        }
        bool _884 = resolve_info.debug_view_active > 0.5;
        bool _900 = false;
        if (_884)
        {
            bool _890 = resolve_info.debug_view_split < 0.0;
            bool _899 = false;
            if (!_890)
            {
                _899 = v_uv.x >= resolve_info.debug_view_split;
            }
            else
            {
                _899 = _890;
            }
            _900 = _899;
        }
        else
        {
            _900 = _884;
        }
        if (_900)
        {
            frag_color = texture(scene_color, _2861);
            break;
        }
        highp vec4 _914 = texture(scene_color, _2861);
        highp float _917 = _914.w;
        highp vec3 _2867 = vec3(0.0);
        highp vec3 _2895 = vec3(0.0);
        if (resolve_info.chromatic_aberration_enabled > 0.5)
        {
            highp vec2 _932 = ((_2861 - vec2(0.5)) * resolve_info.chromatic_aberration_intensity) * 0.039999999105930328369140625;
            highp vec4 _938 = texture(scene_color, _2861 + _932);
            highp vec4 _944 = texture(scene_color, _2861 - _932);
            highp float _1097 = _938.w;
            highp vec3 _2863 = vec3(0.0);
            if (_1097 > 0.0)
            {
                _2863 = _938.xyz / vec3(_1097);
            }
            else
            {
                _2863 = vec3(0.0);
            }
            highp vec3 _2864 = vec3(0.0);
            if (_917 > 0.0)
            {
                _2864 = _914.xyz / vec3(_917);
            }
            else
            {
                _2864 = vec3(0.0);
            }
            highp float _1129 = _944.w;
            highp vec3 _2865 = vec3(0.0);
            if (_1129 > 0.0)
            {
                _2865 = _944.xyz / vec3(_1129);
            }
            else
            {
                _2865 = vec3(0.0);
            }
            _2895 = vec3(_938.x, _914.y, _944.z);
            _2867 = vec3(_2863.x, _2864.y, _2865.z);
        }
        else
        {
            highp vec3 _2862 = vec3(0.0);
            if (_917 > 0.0)
            {
                _2862 = _914.xyz / vec3(_917);
            }
            else
            {
                _2862 = vec3(0.0);
            }
            _2895 = _914.xyz;
            _2867 = _2862;
        }
        highp vec3 _2868 = vec3(0.0);
        if (resolve_info.bloom_enabled > 0.5)
        {
            highp vec2 _1176 = vec2(textureSize(bloom_color, 0));
            highp vec2 _1181 = (_2861 * _1176) - vec2(0.5);
            highp vec2 _1183 = floor(_1181);
            highp vec2 _1186 = _1181 - _1183;
            highp vec2 _1189 = _1186 * _1186;
            highp vec2 _1192 = _1189 * _1186;
            highp vec2 _1194 = _1186 * 3.0;
            highp vec2 _1198 = _1189 * 3.0;
            highp vec2 _1209 = _1192 * 3.0;
            highp vec2 _1212 = ((vec2(4.0) - (_1189 * 6.0)) + _1209) * vec2(0.16666667163372039794921875);
            highp vec2 _1227 = _1192 * vec2(0.16666667163372039794921875);
            highp vec2 _1230 = ((((vec2(1.0) - _1194) + _1198) - _1192) * vec2(0.16666667163372039794921875)) + _1212;
            highp vec2 _1233 = ((((vec2(1.0) + _1194) + _1198) - _1209) * vec2(0.16666667163372039794921875)) + _1227;
            highp vec2 _1242 = ((_1183 - vec2(0.5)) + (_1212 / _1230)) / _1176;
            highp vec2 _1251 = ((_1183 + vec2(1.5)) + (_1227 / _1233)) / _1176;
            highp float _1255 = _1230.x;
            highp float _1266 = _1233.x;
            _2868 = ((((texture(bloom_color, _1242).xyz * _1255) + (texture(bloom_color, vec2(_1251.x, _1242.y)).xyz * _1266)) * _1230.y) + (((texture(bloom_color, vec2(_1242.x, _1251.y)).xyz * _1255) + (texture(bloom_color, _1251).xyz * _1266)) * _1233.y)) * resolve_info.bloom_intensity;
        }
        else
        {
            _2868 = vec3(0.0);
        }
        highp vec4 _993 = texture(exposure_factor, vec2(0.5));
        highp float _995 = resolve_info.exposure * _993.x;
        highp float _1000 = clamp(_917 * 64.0, 0.0, 1.0);
        highp vec3 _2943 = vec3(0.0);
        if (_917 > 0.0)
        {
            highp vec3 _1325 = ((_2867 * _1000) + _2868) * _995;
            highp vec3 _2869 = vec3(0.0);
            if (resolve_info.grading_enabled > 0.5)
            {
                highp float _1448 = resolve_info.temperature * 0.20000000298023223876953125;
                highp vec3 _1465 = (_1325 * vec3(1.0 + _1448, 1.0 + (resolve_info.tint * 0.20000000298023223876953125), 1.0 - _1448)) * resolve_info.brightness;
                highp vec3 _1497 = max(((pow(max(resolve_info.gain.xyz * (_1465 + (resolve_info.lift.xyz * (vec3(1.0) - _1465))), vec3(0.0)), vec3(1.0) / max(resolve_info.gamma.xyz, vec3(9.9999997473787516355514526367188e-05))) - vec3(0.180000007152557373046875)) * resolve_info.contrast) + vec3(0.180000007152557373046875), vec3(0.0));
                _2869 = mix(vec3(dot(_1497, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))), _1497, vec3(resolve_info.saturation));
            }
            else
            {
                _2869 = _1325;
            }
            highp vec3 _2873 = vec3(0.0);
            if (resolve_info.tone_mapping_mode < 0.5)
            {
                highp vec3 _2872 = vec3(0.0);
                do
                {
                    highp float _1526 = min(_2869.x, min(_2869.y, _2869.z));
                    highp float _2870 = 0.0;
                    if (_1526 < 0.07999999821186065673828125)
                    {
                        _2870 = _1526 - ((6.25 * _1526) * _1526);
                    }
                    else
                    {
                        _2870 = 0.039999999105930328369140625;
                    }
                    highp vec3 _1542 = _2869 - vec3(_2870);
                    highp float _1550 = max(_1542.x, max(_1542.y, _1542.z));
                    if (_1550 < 0.7599999904632568359375)
                    {
                        _2872 = _1542;
                        break;
                    }
                    highp float _1560 = 1.0 - (0.057599999010562896728515625 / (_1550 + (-0.519999980926513671875)));
                    _2872 = mix(_1542 * (_1560 / _1550), vec3(1.0) * _1560, vec3(1.0 - (1.0 / ((0.1500000059604644775390625 * (_1550 - _1560)) + 1.0))));
                    break;
                } while(false);
                _2873 = _2872;
            }
            else
            {
                highp vec3 _2874 = vec3(0.0);
                if (resolve_info.tone_mapping_mode < 1.5)
                {
                    highp vec3 _1589 = mat3(vec3(0.59719002246856689453125, 0.075999997556209564208984375, 0.0284000001847743988037109375), vec3(0.354579985141754150390625, 0.908339977264404296875, 0.13382999598979949951171875), vec3(0.048229999840259552001953125, 0.0156599991023540496826171875, 0.837769985198974609375)) * (_2869 * 1.66666662693023681640625);
                    _2874 = clamp(mat3(vec3(1.60475003719329833984375, -0.10208000242710113525390625, -0.00326999998651444911956787109375), vec3(-0.5310800075531005859375, 1.108129978179931640625, -0.07276000082492828369140625), vec3(-0.0736699998378753662109375, -0.00604999996721744537353515625, 1.0760200023651123046875)) * (((_1589 * (_1589 + vec3(0.02457859925925731658935546875))) - vec3(9.0537003416102379560470581054688e-05)) / ((_1589 * ((_1589 * 0.98372900485992431640625) + vec3(0.4329510033130645751953125))) + vec3(0.23808099329471588134765625))), vec3(0.0), vec3(1.0));
                }
                else
                {
                    highp vec3 _2875 = vec3(0.0);
                    if (resolve_info.tone_mapping_mode < 2.5)
                    {
                        _2875 = _2869 / (vec3(1.0) + _2869);
                    }
                    else
                    {
                        highp vec3 _2876 = vec3(0.0);
                        if (resolve_info.tone_mapping_mode < 3.5)
                        {
                            _2876 = clamp(_2869, vec3(0.0), vec3(1.0));
                        }
                        else
                        {
                            highp vec3 _1633 = mat3(vec3(0.544814765453338623046875, 0.1404169499874114990234375, 0.088810421526432037353515625), vec3(0.373787403106689453125, 0.754137575626373291015625, 0.17887175083160400390625), vec3(0.081397853791713714599609375, 0.105445496737957000732421875, 0.73231780529022216796875)) * max(_2869, vec3(0.0));
                            highp vec3 _1652 = _1633 - vec3(0.180000007152557373046875);
                            highp vec3 _1656 = _1652 * resolve_info.agx_params.z;
                            highp vec3 _1674 = ((_1656 * (vec3(1.0) + (_1652 / vec3(resolve_info.agx_params.w)))) / (vec3(1.0) + (_1656 * vec3(1.2195122241973876953125)))) + vec3(0.180000007152557373046875);
                            highp vec3 _1679 = pow(_1633, vec3(resolve_info.agx_params.x));
                            highp vec3 _1686 = _1679 / (_1679 + vec3(resolve_info.agx_params.y));
                            bvec3 _1690 = lessThan(_1633, vec3(0.180000007152557373046875));
                            _2876 = clamp(mat3(vec3(1.9648873805999755859375, -0.299313366413116455078125, -0.1643527448177337646484375), vec3(-0.85598850250244140625, 1.32639801502227783203125, -0.2381839752197265625), vec3(-0.108898915350437164306640625, -0.0270846001803874969482421875, 1.40253674983978271484375)) * min(vec3(_1690.x ? _1686.x : _1674.x, _1690.y ? _1686.y : _1674.y, _1690.z ? _1686.z : _1674.z), vec3(1.0)), vec3(0.0), vec3(1.0));
                        }
                        _2875 = _2876;
                    }
                    _2874 = _2875;
                }
                _2873 = _2874;
            }
            highp vec3 _2878 = vec3(0.0);
            if (resolve_info.vignette_enabled > 0.5)
            {
                _2878 = _2873 * (1.0 - (smoothstep(resolve_info.vignette_radius, resolve_info.vignette_radius + resolve_info.vignette_smoothness, length((v_uv - vec2(0.5)) * 2.0)) * resolve_info.vignette_intensity));
            }
            else
            {
                _2878 = _2873;
            }
            highp vec3 _2879 = vec3(0.0);
            if (resolve_info.grain_enabled > 0.5)
            {
                highp vec3 _1696 = fract(vec3(gl_FragCoord.xy, resolve_info.time * 60.0) * 0.103100001811981201171875);
                highp vec3 _1705 = _1696 + vec3(dot(_1696, _1696.yzx + vec3(33.3300018310546875)));
                _2879 = max(_2878 + vec3((fract((_1705.x + _1705.y) * _1705.z) - 0.5) * resolve_info.grain_intensity), vec3(0.0));
            }
            else
            {
                _2879 = _2878;
            }
            highp vec3 _1728 = mix(_2879 * 12.9200000762939453125, (pow(max(_2879, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _2879));
            highp vec3 _2880 = vec3(0.0);
            if (resolve_info.lut_params.x > 0.0)
            {
                highp float _1743 = resolve_info.lut_params.y - 1.0;
                highp vec3 _1744 = clamp(_1728, vec3(0.0), vec3(1.0)) * _1743;
                highp float _1746 = _1744.z;
                highp float _1747 = floor(_1746);
                highp vec2 _1759 = vec2(1.0 / (resolve_info.lut_params.y * resolve_info.lut_params.y), 1.0 / resolve_info.lut_params.y);
                highp vec2 _1766 = vec2(_1744.x + 0.5, _1744.y + 0.5);
                _2880 = mix(_1728, mix(texture(grading_lut, (_1766 + vec2(_1747 * resolve_info.lut_params.y, 0.0)) * _1759).xyz, texture(grading_lut, (_1766 + vec2(min(_1747 + 1.0, _1743) * resolve_info.lut_params.y, 0.0)) * _1759).xyz, vec3(_1746 - _1747)), vec3(resolve_info.lut_params.x));
            }
            else
            {
                _2880 = _1728;
            }
            _2943 = _2880 * _917;
        }
        else
        {
            _2943 = vec3(0.0);
        }
        highp vec3 _2958 = vec3(0.0);
        if (_917 < 0.999000012874603271484375)
        {
            highp float _1030 = 1.0 - _917;
            highp vec3 _1033 = _2868 + (_2895 * ((1.0 - _1000) / _1030));
            highp vec3 _2959 = vec3(0.0);
            if (max(_1033.x, max(_1033.y, _1033.z)) > 0.0)
            {
                highp vec3 _1817 = _1033 * _995;
                bool _1820 = resolve_info.grading_enabled > 0.5;
                highp vec3 _2907 = vec3(0.0);
                if (_1820)
                {
                    highp float _1940 = resolve_info.temperature * 0.20000000298023223876953125;
                    highp vec3 _1957 = (_1817 * vec3(1.0 + _1940, 1.0 + (resolve_info.tint * 0.20000000298023223876953125), 1.0 - _1940)) * resolve_info.brightness;
                    highp vec3 _1989 = max(((pow(max(resolve_info.gain.xyz * (_1957 + (resolve_info.lift.xyz * (vec3(1.0) - _1957))), vec3(0.0)), vec3(1.0) / max(resolve_info.gamma.xyz, vec3(9.9999997473787516355514526367188e-05))) - vec3(0.180000007152557373046875)) * resolve_info.contrast) + vec3(0.180000007152557373046875), vec3(0.0));
                    _2907 = mix(vec3(dot(_1989, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))), _1989, vec3(resolve_info.saturation));
                }
                else
                {
                    _2907 = _1817;
                }
                bool _1827 = resolve_info.tone_mapping_mode < 0.5;
                highp vec3 _2911 = vec3(0.0);
                if (_1827)
                {
                    highp vec3 _2910 = vec3(0.0);
                    do
                    {
                        highp float _2018 = min(_2907.x, min(_2907.y, _2907.z));
                        highp float _2908 = 0.0;
                        if (_2018 < 0.07999999821186065673828125)
                        {
                            _2908 = _2018 - ((6.25 * _2018) * _2018);
                        }
                        else
                        {
                            _2908 = 0.039999999105930328369140625;
                        }
                        highp vec3 _2034 = _2907 - vec3(_2908);
                        highp float _2042 = max(_2034.x, max(_2034.y, _2034.z));
                        if (_2042 < 0.7599999904632568359375)
                        {
                            _2910 = _2034;
                            break;
                        }
                        highp float _2052 = 1.0 - (0.057599999010562896728515625 / (_2042 + (-0.519999980926513671875)));
                        _2910 = mix(_2034 * (_2052 / _2042), vec3(1.0) * _2052, vec3(1.0 - (1.0 / ((0.1500000059604644775390625 * (_2042 - _2052)) + 1.0))));
                        break;
                    } while(false);
                    _2911 = _2910;
                }
                else
                {
                    highp vec3 _2912 = vec3(0.0);
                    if (resolve_info.tone_mapping_mode < 1.5)
                    {
                        highp vec3 _2081 = mat3(vec3(0.59719002246856689453125, 0.075999997556209564208984375, 0.0284000001847743988037109375), vec3(0.354579985141754150390625, 0.908339977264404296875, 0.13382999598979949951171875), vec3(0.048229999840259552001953125, 0.0156599991023540496826171875, 0.837769985198974609375)) * (_2907 * 1.66666662693023681640625);
                        _2912 = clamp(mat3(vec3(1.60475003719329833984375, -0.10208000242710113525390625, -0.00326999998651444911956787109375), vec3(-0.5310800075531005859375, 1.108129978179931640625, -0.07276000082492828369140625), vec3(-0.0736699998378753662109375, -0.00604999996721744537353515625, 1.0760200023651123046875)) * (((_2081 * (_2081 + vec3(0.02457859925925731658935546875))) - vec3(9.0537003416102379560470581054688e-05)) / ((_2081 * ((_2081 * 0.98372900485992431640625) + vec3(0.4329510033130645751953125))) + vec3(0.23808099329471588134765625))), vec3(0.0), vec3(1.0));
                    }
                    else
                    {
                        highp vec3 _2913 = vec3(0.0);
                        if (resolve_info.tone_mapping_mode < 2.5)
                        {
                            _2913 = _2907 / (vec3(1.0) + _2907);
                        }
                        else
                        {
                            highp vec3 _2914 = vec3(0.0);
                            if (resolve_info.tone_mapping_mode < 3.5)
                            {
                                _2914 = clamp(_2907, vec3(0.0), vec3(1.0));
                            }
                            else
                            {
                                highp vec3 _2125 = mat3(vec3(0.544814765453338623046875, 0.1404169499874114990234375, 0.088810421526432037353515625), vec3(0.373787403106689453125, 0.754137575626373291015625, 0.17887175083160400390625), vec3(0.081397853791713714599609375, 0.105445496737957000732421875, 0.73231780529022216796875)) * max(_2907, vec3(0.0));
                                highp vec3 _2144 = _2125 - vec3(0.180000007152557373046875);
                                highp vec3 _2148 = _2144 * resolve_info.agx_params.z;
                                highp vec3 _2166 = ((_2148 * (vec3(1.0) + (_2144 / vec3(resolve_info.agx_params.w)))) / (vec3(1.0) + (_2148 * vec3(1.2195122241973876953125)))) + vec3(0.180000007152557373046875);
                                highp vec3 _2171 = pow(_2125, vec3(resolve_info.agx_params.x));
                                highp vec3 _2178 = _2171 / (_2171 + vec3(resolve_info.agx_params.y));
                                bvec3 _2182 = lessThan(_2125, vec3(0.180000007152557373046875));
                                _2914 = clamp(mat3(vec3(1.9648873805999755859375, -0.299313366413116455078125, -0.1643527448177337646484375), vec3(-0.85598850250244140625, 1.32639801502227783203125, -0.2381839752197265625), vec3(-0.108898915350437164306640625, -0.0270846001803874969482421875, 1.40253674983978271484375)) * min(vec3(_2182.x ? _2178.x : _2166.x, _2182.y ? _2178.y : _2166.y, _2182.z ? _2178.z : _2166.z), vec3(1.0)), vec3(0.0), vec3(1.0));
                            }
                            _2913 = _2914;
                        }
                        _2912 = _2913;
                    }
                    _2911 = _2912;
                }
                bool _1865 = resolve_info.vignette_enabled > 0.5;
                highp vec3 _2916 = vec3(0.0);
                if (_1865)
                {
                    _2916 = _2911 * (1.0 - (smoothstep(resolve_info.vignette_radius, resolve_info.vignette_radius + resolve_info.vignette_smoothness, length((v_uv - vec2(0.5)) * 2.0)) * resolve_info.vignette_intensity));
                }
                else
                {
                    _2916 = _2911;
                }
                highp vec3 _2220 = mix(_2916 * 12.9200000762939453125, (pow(max(_2916, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _2916));
                bool _1920 = resolve_info.lut_params.x > 0.0;
                highp vec3 _2918 = vec3(0.0);
                if (_1920)
                {
                    highp float _2235 = resolve_info.lut_params.y - 1.0;
                    highp vec3 _2236 = clamp(_2220, vec3(0.0), vec3(1.0)) * _2235;
                    highp float _2238 = _2236.z;
                    highp float _2239 = floor(_2238);
                    highp vec2 _2251 = vec2(1.0 / (resolve_info.lut_params.y * resolve_info.lut_params.y), 1.0 / resolve_info.lut_params.y);
                    highp vec2 _2258 = vec2(_2236.x + 0.5, _2236.y + 0.5);
                    _2918 = mix(_2220, mix(texture(grading_lut, (_2258 + vec2(_2239 * resolve_info.lut_params.y, 0.0)) * _2251).xyz, texture(grading_lut, (_2258 + vec2(min(_2239 + 1.0, _2235) * resolve_info.lut_params.y, 0.0)) * _2251).xyz, vec3(_2238 - _2239)), vec3(resolve_info.lut_params.x));
                }
                else
                {
                    _2918 = _2220;
                }
                highp vec3 _2932 = vec3(0.0);
                if ((!_1820) ? _1920 : _1820)
                {
                    highp vec3 _2920 = vec3(0.0);
                    if (_1820)
                    {
                        highp vec3 _2481 = max(((pow(max(resolve_info.gain.xyz * resolve_info.lift.xyz, vec3(0.0)), vec3(1.0) / max(resolve_info.gamma.xyz, vec3(9.9999997473787516355514526367188e-05))) - vec3(0.180000007152557373046875)) * resolve_info.contrast) + vec3(0.180000007152557373046875), vec3(0.0));
                        _2920 = mix(vec3(dot(_2481, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875))), _2481, vec3(resolve_info.saturation));
                    }
                    else
                    {
                        _2920 = vec3(0.0);
                    }
                    highp vec3 _2924 = vec3(0.0);
                    if (_1827)
                    {
                        highp vec3 _2923 = vec3(0.0);
                        do
                        {
                            highp float _2510 = min(_2920.x, min(_2920.y, _2920.z));
                            highp float _2921 = 0.0;
                            if (_2510 < 0.07999999821186065673828125)
                            {
                                _2921 = _2510 - ((6.25 * _2510) * _2510);
                            }
                            else
                            {
                                _2921 = 0.039999999105930328369140625;
                            }
                            highp vec3 _2526 = _2920 - vec3(_2921);
                            highp float _2534 = max(_2526.x, max(_2526.y, _2526.z));
                            if (_2534 < 0.7599999904632568359375)
                            {
                                _2923 = _2526;
                                break;
                            }
                            highp float _2544 = 1.0 - (0.057599999010562896728515625 / (_2534 + (-0.519999980926513671875)));
                            _2923 = mix(_2526 * (_2544 / _2534), vec3(1.0) * _2544, vec3(1.0 - (1.0 / ((0.1500000059604644775390625 * (_2534 - _2544)) + 1.0))));
                            break;
                        } while(false);
                        _2924 = _2923;
                    }
                    else
                    {
                        highp vec3 _2925 = vec3(0.0);
                        if (resolve_info.tone_mapping_mode < 1.5)
                        {
                            highp vec3 _2573 = mat3(vec3(0.59719002246856689453125, 0.075999997556209564208984375, 0.0284000001847743988037109375), vec3(0.354579985141754150390625, 0.908339977264404296875, 0.13382999598979949951171875), vec3(0.048229999840259552001953125, 0.0156599991023540496826171875, 0.837769985198974609375)) * (_2920 * 1.66666662693023681640625);
                            _2925 = clamp(mat3(vec3(1.60475003719329833984375, -0.10208000242710113525390625, -0.00326999998651444911956787109375), vec3(-0.5310800075531005859375, 1.108129978179931640625, -0.07276000082492828369140625), vec3(-0.0736699998378753662109375, -0.00604999996721744537353515625, 1.0760200023651123046875)) * (((_2573 * (_2573 + vec3(0.02457859925925731658935546875))) - vec3(9.0537003416102379560470581054688e-05)) / ((_2573 * ((_2573 * 0.98372900485992431640625) + vec3(0.4329510033130645751953125))) + vec3(0.23808099329471588134765625))), vec3(0.0), vec3(1.0));
                        }
                        else
                        {
                            highp vec3 _2926 = vec3(0.0);
                            if (resolve_info.tone_mapping_mode < 2.5)
                            {
                                _2926 = _2920 / (vec3(1.0) + _2920);
                            }
                            else
                            {
                                highp vec3 _2927 = vec3(0.0);
                                if (resolve_info.tone_mapping_mode < 3.5)
                                {
                                    _2927 = clamp(_2920, vec3(0.0), vec3(1.0));
                                }
                                else
                                {
                                    highp vec3 _2617 = mat3(vec3(0.544814765453338623046875, 0.1404169499874114990234375, 0.088810421526432037353515625), vec3(0.373787403106689453125, 0.754137575626373291015625, 0.17887175083160400390625), vec3(0.081397853791713714599609375, 0.105445496737957000732421875, 0.73231780529022216796875)) * max(_2920, vec3(0.0));
                                    highp vec3 _2636 = _2617 - vec3(0.180000007152557373046875);
                                    highp vec3 _2640 = _2636 * resolve_info.agx_params.z;
                                    highp vec3 _2658 = ((_2640 * (vec3(1.0) + (_2636 / vec3(resolve_info.agx_params.w)))) / (vec3(1.0) + (_2640 * vec3(1.2195122241973876953125)))) + vec3(0.180000007152557373046875);
                                    highp vec3 _2663 = pow(_2617, vec3(resolve_info.agx_params.x));
                                    highp vec3 _2670 = _2663 / (_2663 + vec3(resolve_info.agx_params.y));
                                    bvec3 _2674 = lessThan(_2617, vec3(0.180000007152557373046875));
                                    _2927 = clamp(mat3(vec3(1.9648873805999755859375, -0.299313366413116455078125, -0.1643527448177337646484375), vec3(-0.85598850250244140625, 1.32639801502227783203125, -0.2381839752197265625), vec3(-0.108898915350437164306640625, -0.0270846001803874969482421875, 1.40253674983978271484375)) * min(vec3(_2674.x ? _2670.x : _2658.x, _2674.y ? _2670.y : _2658.y, _2674.z ? _2670.z : _2658.z), vec3(1.0)), vec3(0.0), vec3(1.0));
                                }
                                _2926 = _2927;
                            }
                            _2925 = _2926;
                        }
                        _2924 = _2925;
                    }
                    highp vec3 _2929 = vec3(0.0);
                    if (_1865)
                    {
                        _2929 = _2924 * (1.0 - (smoothstep(resolve_info.vignette_radius, resolve_info.vignette_radius + resolve_info.vignette_smoothness, length((v_uv - vec2(0.5)) * 2.0)) * resolve_info.vignette_intensity));
                    }
                    else
                    {
                        _2929 = _2924;
                    }
                    highp vec3 _2712 = mix(_2929 * 12.9200000762939453125, (pow(max(_2929, vec3(0.003130800090730190277099609375)), vec3(0.4166666567325592041015625)) * 1.05499994754791259765625) - vec3(0.054999999701976776123046875), step(vec3(0.003130800090730190277099609375), _2929));
                    highp vec3 _2931 = vec3(0.0);
                    if (_1920)
                    {
                        highp float _2727 = resolve_info.lut_params.y - 1.0;
                        highp vec3 _2728 = clamp(_2712, vec3(0.0), vec3(1.0)) * _2727;
                        highp float _2730 = _2728.z;
                        highp float _2731 = floor(_2730);
                        highp vec2 _2743 = vec2(1.0 / (resolve_info.lut_params.y * resolve_info.lut_params.y), 1.0 / resolve_info.lut_params.y);
                        highp vec2 _2750 = vec2(_2728.x + 0.5, _2728.y + 0.5);
                        _2931 = mix(_2712, mix(texture(grading_lut, (_2750 + vec2(_2731 * resolve_info.lut_params.y, 0.0)) * _2743).xyz, texture(grading_lut, (_2750 + vec2(min(_2731 + 1.0, _2727) * resolve_info.lut_params.y, 0.0)) * _2743).xyz, vec3(_2730 - _2731)), vec3(resolve_info.lut_params.x));
                    }
                    else
                    {
                        _2931 = _2712;
                    }
                    _2932 = max(_2918 - _2931, vec3(0.0));
                }
                else
                {
                    _2932 = _2918;
                }
                _2959 = _2943 + (_2932 * _1030);
            }
            else
            {
                _2959 = _2943;
            }
            _2958 = _2959;
        }
        else
        {
            _2958 = _2943;
        }
        frag_color = vec4(_2958, _917);
        break;
    } while(false);
}

