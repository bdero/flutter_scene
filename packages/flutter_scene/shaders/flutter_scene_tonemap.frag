// Tone-mapping resolve pass: reads the linear HDR scene color (with
// premultiplied alpha), applies exposure + a tone mapping operator + the
// display EOTF, and writes the display-referred swapchain image.
uniform TonemapInfo {
  float exposure;
  // 0 = Khronos PBR Neutral, 1 = ACES filmic, 2 = Reinhard, else linear.
  float tone_mapping_mode;
  // 1.0 -> flip V when sampling hdr_color. The HDR scene target is a
  // render-to-texture target, and its sampled Y orientation differs by
  // backend (the OpenGL ES backend's FBO is bottom-up); the Dart side
  // sets this so the resolved image is upright everywhere. Flutter GPU
  // exposes no way to do this in the shader (no backend macro).
  float flip_y;
  float _pad0;
}
tonemap_info;

uniform sampler2D hdr_color;

in vec2 v_uv;

out vec4 frag_color;

#include <tone_mapping.glsl>

const float kGamma = 2.2;

void main() {
  vec2 uv =
      tonemap_info.flip_y > 0.5 ? vec2(v_uv.x, 1.0 - v_uv.y) : v_uv;
  vec4 hdr = texture(hdr_color, uv);
  // Un-premultiply so the tone curve sees the actual surface color, then
  // re-premultiply for compositing onto the Flutter canvas.
  vec3 color = hdr.a > 0.0 ? hdr.rgb / hdr.a : vec3(0.0);

  vec3 mapped;
  if (tonemap_info.tone_mapping_mode < 0.5) {
    mapped = PBRNeutralToneMapping(color * tonemap_info.exposure);
  } else if (tonemap_info.tone_mapping_mode < 1.5) {
    mapped = ACESFilmicToneMapping(color, tonemap_info.exposure);
  } else if (tonemap_info.tone_mapping_mode < 2.5) {
    mapped = ReinhardToneMapping(color * tonemap_info.exposure);
  } else {
    mapped = clamp(color * tonemap_info.exposure, 0.0, 1.0);
  }

#ifndef IMPELLER_TARGET_METAL
  mapped = pow(mapped, vec3(1.0 / kGamma));
#endif

  frag_color = vec4(mapped * hdr.a, hdr.a);
}
