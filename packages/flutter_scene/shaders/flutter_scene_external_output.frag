#version 460 core

// The last write into a caller-owned color target. Puts a background behind
// the finished display image, and hands an attachment that encodes sRGB on
// write linear color, so the stored image is encoded once.
//
// Both colors are display-encoded and premultiplied by alpha.

precision highp float;

uniform ExternalOutputInfo {
  // All zero for no background.
  vec4 background;
  // x is above 0.5 when the attachment encodes sRGB.
  vec4 flags;
}
output_info;

uniform sampler2D source_texture;

in vec2 v_uv;

out vec4 frag_color;

vec3 SRGBToLinear(vec3 color) {
  return mix(color / 12.92,
             pow((max(color, vec3(0.04045)) + 0.055) / 1.055, vec3(2.4)),
             step(0.04045, color));
}

void main() {
  vec4 color = texture(source_texture, v_uv);
  color += output_info.background * (1.0 - color.a);
  // The curve applies to straight color, so the premultiply comes off around
  // it. A plain attachment takes the same path with the curve skipped.
  float alpha = max(color.a, 0.00001);
  vec3 straight = color.rgb / alpha;
  vec3 decoded = mix(straight, SRGBToLinear(straight),
                     step(0.5, output_info.flags.x));
  frag_color = vec4(decoded * color.a, color.a);
}
