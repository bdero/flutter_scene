// Tone mapping operators. Each maps a non-negative linear HDR color to a
// display-referred [0, 1] color (still in linear Rec. 709; display encoding
// is applied separately by the caller where needed).

// ACES filmic approximation (Stephen Hill fit).
// source:
// https://github.com/selfshadow/ltc_code/blob/master/webgl/shaders/ltc/ltc_blit.fs
vec3 RRTAndODTFit(vec3 v) {
  vec3 a = v * (v + 0.0245786) - 0.000090537;
  vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return a / b;
}

// source:
// https://github.com/mrdoob/three.js/blob/364f90e7b0207564ab4e163daa968ce06af8ff99/src/renderers/shaders/ShaderChunk/tonemapping_pars_fragment.glsl.js#L34-L74
vec3 ACESFilmicToneMapping(vec3 color, float exposure) {
  // sRGB => XYZ => D65_2_D60 => AP1 => RRT_SAT
  const mat3 ACESInputMat =
      mat3(vec3(0.59719, 0.07600, 0.02840), // transposed from source
           vec3(0.35458, 0.90834, 0.13383), //
           vec3(0.04823, 0.01566, 0.83777));

  // ODT_SAT => XYZ => D60_2_D65 => sRGB
  const mat3 ACESOutputMat =
      mat3(vec3(1.60475, -0.10208, -0.00327), // transposed from source
           vec3(-0.53108, 1.10813, -0.07276), //
           vec3(-0.07367, -0.00605, 1.07602));

  // The 1/0.6 brings the ACES "reference white" up to sane display levels.
  color *= exposure / 0.6;
  color = ACESInputMat * color;
  color = RRTAndODTFit(color);
  color = ACESOutputMat * color;
  return clamp(color, 0.0, 1.0);
}

// Khronos PBR Neutral tone mapper. Designed for product/e-commerce
// rendering: preserves base-color hue and saturation, only rolling off
// the highlights, so albedo colors stay true under bright light.
// source:
// https://github.com/KhronosGroup/ToneMapping/blob/main/PBR_Neutral/pbrNeutral.glsl
vec3 PBRNeutralToneMapping(vec3 color) {
  const float kStartCompression = 0.8 - 0.04;
  const float kDesaturation = 0.15;

  float x = min(color.r, min(color.g, color.b));
  float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
  color -= offset;

  float peak = max(color.r, max(color.g, color.b));
  if (peak < kStartCompression) {
    return color;
  }

  const float d = 1.0 - kStartCompression;
  float new_peak = 1.0 - d * d / (peak + d - kStartCompression);
  color *= new_peak / peak;

  float g = 1.0 - 1.0 / (kDesaturation * (peak - new_peak) + 1.0);
  return mix(color, new_peak * vec3(1.0), g);
}

// Reinhard tone mapping: c / (1 + c). Cheap, desaturates highlights.
vec3 ReinhardToneMapping(vec3 color) { return color / (1.0 + color); }

// AgX gamut transforms with the AllenWP curve.
// https://github.com/EaryChow/AgX_LUT_Gen/blob/main/AgXBasesRGB.py
// https://allenwp.com/blog/2025/05/29/allenwp-tonemapping-curve/
vec3 AllenWpToneMappingCurve(vec3 x, vec4 params) {
  const float kCrossover = 0.18;
  const float kShoulderMax = 1.0 - kCrossover;
  vec3 s = x - kCrossover;
  vec3 slope_s = params.z * s;
  s = slope_s * (1.0 + s / params.w) /
      (1.0 + slope_s / kShoulderMax);
  s += kCrossover;
  vec3 p = pow(x, vec3(params.x));
  vec3 t = p / (p + params.y);
  return mix(s, t, lessThan(x, vec3(kCrossover)));
}

vec3 AgXToneMapping(vec3 color, vec4 params) {
  const mat3 kInset = mat3(
      0.544814746488245, 0.140416948464053, 0.0888104196149096,
      0.373787398372697, 0.754137554567394, 0.178871756420858,
      0.0813978551390581, 0.105445496968552, 0.732317823964232);
  const mat3 kOutset = mat3(
      1.96488741169489, -0.299313364904742, -0.164352742528393,
      -0.855988495690215, 1.32639796461980, -0.238183969428088,
      -0.108898916004672, -0.0270845997150571, 1.40253671195648);
  color = kInset * max(color, vec3(0.0));
  color = AllenWpToneMappingCurve(color, params);
  color = min(color, vec3(1.0));
  return clamp(kOutset * color, 0.0, 1.0);
}
