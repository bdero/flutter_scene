// Resolve pass: reads the linear HDR scene color (with premultiplied
// alpha), applies exposure, optional color grading, a tone mapping
// operator, and the display EOTF, and writes the display-referred
// swapchain image.
uniform ResolveInfo {
  float exposure;
  // 0 = Khronos PBR Neutral, 1 = ACES filmic, 2 = Reinhard, else linear.
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
}
resolve_info;

uniform sampler2D scene_color;

in vec2 v_uv;

out vec4 frag_color;

#include <tone_mapping.glsl>

const float kGamma = 2.2;

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

void main() {
  vec2 uv = resolve_info.flip_y > 0.5 ? vec2(v_uv.x, 1.0 - v_uv.y) : v_uv;
  vec4 hdr = texture(scene_color, uv);
  // Un-premultiply so the curves see the actual surface color, then
  // re-premultiply for compositing onto the Flutter canvas.
  vec3 color = hdr.a > 0.0 ? hdr.rgb / hdr.a : vec3(0.0);

  color *= resolve_info.exposure;
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
  } else {
    mapped = clamp(color, 0.0, 1.0);
  }

#ifndef IMPELLER_TARGET_METAL
  mapped = pow(mapped, vec3(1.0 / kGamma));
#endif

  frag_color = vec4(mapped * hdr.a, hdr.a);
}
