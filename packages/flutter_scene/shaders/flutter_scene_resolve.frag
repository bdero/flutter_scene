// Resolve pass: reads the linear HDR scene color (with premultiplied
// alpha) and produces the display-referred swapchain image. In order it
// applies chromatic aberration (at sample time), exposure, color grading,
// a tone mapping operator, display encoding, then vignette and film grain.
// Each effect is gated by a flag, so a disabled effect costs only a
// branch and leaves the image unchanged.
uniform ResolveInfo {
  float exposure;
  // 0 = PBR Neutral, 1 = ACES, 2 = Reinhard, 3 = linear, 4 = AgX.
  float tone_mapping_mode;
  // 1.0 -> flip V when sampling scene_color. The scene color is a
  // render-to-texture target, and its sampled Y orientation differs by
  // backend (the OpenGL ES backend's FBO is bottom-up); the Dart side
  // sets this so the resolved image is upright everywhere. Flutter GPU
  // exposes no way to do this in the shader (no backend macro).
  float flip_y;
  // 1.0 -> apply the color grading controls below.
  float grading_enabled;

  float brightness;
  float contrast;
  float saturation;
  float temperature;

  float tint;
  float _pad0;
  float _pad1;
  float _pad2;

  // Only the xyz channels are used; w is padding.
  vec4 lift;
  vec4 gamma;
  vec4 gain;

  float chromatic_aberration_enabled;
  float chromatic_aberration_intensity;
  float time;
  float _pad3;

  float vignette_enabled;
  float vignette_intensity;
  float vignette_radius;
  float vignette_smoothness;

  float grain_enabled;
  float grain_intensity;
  float _pad4;
  float _pad5;

  float bloom_enabled;
  float bloom_intensity;
  float _pad6;
  float _pad7;

  vec4 agx_params;

  // x: grading-LUT blend, 0 disables. y: the cube edge length (the strip
  // texture is y*y wide and y tall). zw: reserved.
  vec4 lut_params;
}
resolve_info;

uniform sampler2D scene_color;
uniform sampler2D bloom_color;
// 1x1 auto exposure correction factor in r, produced by the adaptation
// pass. A white placeholder (factor 1.0) fills the slot when auto exposure
// is disabled.
uniform sampler2D exposure_factor;

// The grading LUT strip: the cube's blue slices side by side, red along x
// inside a slice, green along y.
uniform sampler2D grading_lut;

in vec2 v_uv;

out vec4 frag_color;

#include <tone_mapping.glsl>

// Samples the grading cube stored as a strip, lerping the two blue slices
// spanning the input's blue coordinate.
vec3 ApplyGradingLut(vec3 c, float size) {
  vec3 scaled = clamp(c, 0.0, 1.0) * (size - 1.0);
  float slice0 = floor(scaled.z);
  float slice1 = min(slice0 + 1.0, size - 1.0);
  vec2 texel = vec2(1.0 / (size * size), 1.0 / size);
  vec2 base = vec2(scaled.x + 0.5, scaled.y + 0.5);
  vec3 tap0 =
      texture(grading_lut, (base + vec2(slice0 * size, 0.0)) * texel).rgb;
  vec3 tap1 =
      texture(grading_lut, (base + vec2(slice1 * size, 0.0)) * texel).rgb;
  return mix(tap0, tap1, scaled.z - slice0);
}

vec3 LinearToSRGB(vec3 color) {
  return mix(color * 12.92,
             1.055 * pow(max(color, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055,
             step(0.0031308, color));
}

// Color grading on the exposed linear HDR color, before tone mapping.
// Neutral defaults leave the color unchanged.
vec3 ApplyColorGrading(vec3 color) {
  // White balance: warm or cool on temperature, green or magenta on tint.
  vec3 white_balance = vec3(1.0 + resolve_info.temperature * 0.2,
                            1.0 + resolve_info.tint * 0.2,
                            1.0 - resolve_info.temperature * 0.2);
  color *= white_balance;

  // Brightness.
  color *= resolve_info.brightness;

  // Lift, gamma, gain (shadows, midtones, highlights).
  color = resolve_info.gain.rgb *
          (color + resolve_info.lift.rgb * (1.0 - color));
  color = pow(max(color, vec3(0.0)),
              1.0 / max(resolve_info.gamma.rgb, vec3(1e-4)));

  // Contrast around linear mid-gray.
  const float kMidGray = 0.18;
  color = (color - kMidGray) * resolve_info.contrast + kMidGray;
  color = max(color, vec3(0.0));

  // Saturation.
  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, resolve_info.saturation);

  return color;
}

// Un-premultiplies a sampled premultiplied-alpha color.
vec3 Unpremultiply(vec4 c) { return c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }

// Value noise for film grain. Mixing time in as a third coordinate
// re-randomizes every pixel each frame, rather than sliding one fixed
// noise field across the screen.
float GrainNoise(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

void main() {
  vec2 uv = resolve_info.flip_y > 0.5 ? vec2(v_uv.x, 1.0 - v_uv.y) : v_uv;

  // Sample the scene color. Chromatic aberration pulls the red and blue
  // channels from offset positions that grow toward the edges.
  vec3 color;
  float alpha;
  if (resolve_info.chromatic_aberration_enabled > 0.5) {
    vec2 offset =
        (uv - 0.5) * resolve_info.chromatic_aberration_intensity * 0.04;
    vec4 center = texture(scene_color, uv);
    color = vec3(Unpremultiply(texture(scene_color, uv + offset)).r,
                 Unpremultiply(center).g,
                 Unpremultiply(texture(scene_color, uv - offset)).b);
    alpha = center.a;
  } else {
    vec4 hdr = texture(scene_color, uv);
    color = Unpremultiply(hdr);
    alpha = hdr.a;
  }

  // Bloom is computed in HDR by BloomPass and added back here.
  if (resolve_info.bloom_enabled > 0.5) {
    color += texture(bloom_color, uv).rgb * resolve_info.bloom_intensity;
  }

  color *= resolve_info.exposure * texture(exposure_factor, vec2(0.5, 0.5)).r;
  if (resolve_info.grading_enabled > 0.5) {
    color = ApplyColorGrading(color);
  }

  vec3 mapped;
  if (resolve_info.tone_mapping_mode < 0.5) {
    mapped = PBRNeutralToneMapping(color);
  } else if (resolve_info.tone_mapping_mode < 1.5) {
    mapped = ACESFilmicToneMapping(color, 1.0);
  } else if (resolve_info.tone_mapping_mode < 2.5) {
    mapped = ReinhardToneMapping(color);
  } else if (resolve_info.tone_mapping_mode < 3.5) {
    mapped = clamp(color, 0.0, 1.0);
  } else {
    mapped = AgXToneMapping(color, resolve_info.agx_params);
  }

  // Vignette: darken toward the edges of the screen.
  if (resolve_info.vignette_enabled > 0.5) {
    float dist = length((v_uv - 0.5) * 2.0);
    float falloff = smoothstep(
        resolve_info.vignette_radius,
        resolve_info.vignette_radius + resolve_info.vignette_smoothness,
        dist);
    mapped *= 1.0 - falloff * resolve_info.vignette_intensity;
  }

  // Film grain: animated per-pixel noise.
  if (resolve_info.grain_enabled > 0.5) {
    float n =
        GrainNoise(vec3(gl_FragCoord.xy, resolve_info.time * 60.0)) - 0.5;
    mapped = max(mapped + n * resolve_info.grain_intensity, vec3(0.0));
  }

  // The swapchain texture is a plain UNorm render target, so encode the
  // resolved linear color before handing it to Texture.asImage().
  mapped = LinearToSRGB(mapped);

  // Film-look LUT on the display-encoded color, matching how grading tools
  // author display-referred .cube looks.
  if (resolve_info.lut_params.x > 0.0) {
    vec3 graded = ApplyGradingLut(mapped, resolve_info.lut_params.y);
    mapped = mix(mapped, graded, resolve_info.lut_params.x);
  }

  frag_color = vec4(mapped * alpha, alpha);
}
