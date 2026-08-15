#version 460 core

// Parametric display remap for the render graph inspector and the viewport
// debug-output modes: turns any captured or live pipeline texture (HDR
// color, linear depth, packed normals, AO, shadow atlas...) into a
// displayable image, with channel selection, black/white-point range
// remapping, exposure, and non-finite highlighting (NaN magenta, Inf
// yellow, negative blue).
//
// TODO(shader-headers): the octahedral decode mirrors the engine's
// shaders/octahedral.glsl; share the header once the editor bundle build
// can add include directories.

precision highp float;
// Data samplers (depth, fp32 atlases) need explicit highp.
uniform highp sampler2D source_texture;
// The stage's chain color when run through a custom render pass. Blended by
// remap_info.params.w so the sampler stays live through shader compilation
// (a stripped sampler would break the engine's automatic input binding).
uniform highp sampler2D input_color;

uniform RemapInfo {
  // x black point, y white point, z exposure multiplier, w mode:
  //   0 direct color, 1 single channel, 2 depth normalize,
  //   3 octahedral normal decode (gb).
  vec4 range;
  // Mode 1: x = channel index (0..3). Other modes ignore it.
  vec4 channels;
  // x highlight non-finite, y near, z far, w = weight of the remapped
  // output over the chain color (1 everywhere except passthrough).
  vec4 params;
}
remap_info;

in vec2 v_uv;

out vec4 frag_color;

vec2 OctSign(vec2 v) {
  return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

vec3 OctDecode(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * OctSign(n.xy);
  }
  return -normalize(n);
}

float RemapScalar(float value) {
  float black = remap_info.range.x;
  float white = remap_info.range.y;
  float span = max(white - black, 1e-6);
  return clamp((value * remap_info.range.z - black) / span, 0.0, 1.0);
}

void main() {
  vec4 raw = texture(source_texture, v_uv);
  float mode = remap_info.range.w;

  vec3 color;
  if (mode < 0.5) {
    color = vec3(RemapScalar(raw.r), RemapScalar(raw.g), RemapScalar(raw.b));
  } else if (mode < 1.5) {
    int channel = int(remap_info.channels.x + 0.5);
    float value = channel == 0
        ? raw.r
        : (channel == 1 ? raw.g : (channel == 2 ? raw.b : raw.a));
    color = vec3(RemapScalar(value));
  } else if (mode < 2.5) {
    float near = remap_info.params.y;
    float far = max(remap_info.params.z, near + 1e-4);
    color = vec3(clamp((raw.r - near) / (far - near), 0.0, 1.0));
  } else {
    color = OctDecode(raw.gb) * 0.5 + 0.5;
  }

  if (remap_info.params.x > 0.5) {
    // Non-finite channels replace the pixel outright so single bad texels
    // survive thumbnail scaling visually.
    bool anyNan = isnan(raw.r) || isnan(raw.g) || isnan(raw.b) || isnan(raw.a);
    bool anyInf = isinf(raw.r) || isinf(raw.g) || isinf(raw.b) || isinf(raw.a);
    bool anyNegative = min(min(raw.r, raw.g), min(raw.b, raw.a)) < 0.0;
    if (anyNan) {
      color = vec3(1.0, 0.0, 1.0);
    } else if (anyInf) {
      color = vec3(1.0, 1.0, 0.0);
    } else if (anyNegative) {
      color = vec3(0.15, 0.3, 1.0);
    }
  }

  vec4 base = texture(input_color, v_uv);
  float weight = remap_info.params.w;
  // mix() evaluates base * (1 - weight) even at weight 1, and NaN times
  // zero is NaN, so a non-finite chain texel would defeat the highlight
  // exactly where it matters. Select outright at the endpoints.
  if (weight >= 1.0) {
    frag_color = vec4(color, 1.0);
  } else if (weight <= 0.0) {
    frag_color = base;
  } else {
    frag_color = mix(base, vec4(color, 1.0), weight);
  }
}
