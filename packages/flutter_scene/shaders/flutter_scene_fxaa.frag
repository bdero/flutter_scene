// FXAA pass: anti-aliases the display-referred image produced by the
// resolve pass as a single full-screen pass, using the FXAA 3.11 quality
// algorithm (luma-contrast edge detection, an edge-endpoint walk, and a
// subpixel blend). Luma is computed from rgb per tap; the alpha channel
// carries real premultiplied coverage for compositing, so it can't hold
// precomputed luma. The input texture must have a single mip level
// (sampling here happens inside divergent control flow, which is only
// well-defined because there are no mips to select between).
//
// Derived from NVIDIA FXAA 3.11 by Timothy Lottes, as published under the
// BSD 3-clause license:
//
//   Copyright (c) 2014-2015, NVIDIA CORPORATION. All rights reserved.
//
//   Redistribution and use in source and binary forms, with or without
//   modification, are permitted provided that the following conditions
//   are met:
//    * Redistributions of source code must retain the above copyright
//      notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above copyright
//      notice, this list of conditions and the following disclaimer in
//      the documentation and/or other materials provided with the
//      distribution.
//    * Neither the name of NVIDIA CORPORATION nor the names of its
//      contributors may be used to endorse or promote products derived
//      from this software without specific prior written permission.
//
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
//   EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//   PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
//   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
//   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
//   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
//   OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

uniform FxaaInfo {
  // 1 / render target size in pixels (x = 1/width, y = 1/height).
  vec2 inv_target_size;
  float _pad0;
  float _pad1;
}
fxaa_info;

uniform sampler2D scene_color;

in vec2 v_uv;

out vec4 frag_color;

// Edge detection thresholds and subpixel blend strength (the FXAA 3.11
// quality defaults).
// TODO(antialiasing): expose these as settings if tuning demand appears.
const float kEdgeThreshold = 0.166;
const float kEdgeThresholdMin = 0.0833;
const float kSubpixelQuality = 0.75;

// Edge-walk iterations and per-iteration step scale (quality preset 39).
const int kIterations = 12;

float StepSize(int i) {
  if (i < 5) {
    return 1.0;
  }
  if (i == 5) {
    return 1.5;
  }
  if (i < 10) {
    return 2.0;
  }
  if (i == 10) {
    return 4.0;
  }
  return 8.0;
}

float Luma(vec3 color) {
  return dot(color, vec3(0.299, 0.587, 0.114));
}

float LumaAt(vec2 uv) {
  return Luma(texture(scene_color, uv).rgb);
}

void main() {
  vec2 inv_size = fxaa_info.inv_target_size;
  vec4 center = texture(scene_color, v_uv);
  float luma_center = Luma(center.rgb);

  float luma_down = LumaAt(v_uv + vec2(0.0, -inv_size.y));
  float luma_up = LumaAt(v_uv + vec2(0.0, inv_size.y));
  float luma_left = LumaAt(v_uv + vec2(-inv_size.x, 0.0));
  float luma_right = LumaAt(v_uv + vec2(inv_size.x, 0.0));

  float luma_min = min(
      luma_center,
      min(min(luma_down, luma_up), min(luma_left, luma_right)));
  float luma_max = max(
      luma_center,
      max(max(luma_down, luma_up), max(luma_left, luma_right)));
  float luma_range = luma_max - luma_min;

  // Skip pixels that aren't on a visible-contrast edge.
  if (luma_range < max(kEdgeThresholdMin, luma_max * kEdgeThreshold)) {
    frag_color = center;
    return;
  }

  float luma_down_left = LumaAt(v_uv + vec2(-inv_size.x, -inv_size.y));
  float luma_up_right = LumaAt(v_uv + vec2(inv_size.x, inv_size.y));
  float luma_up_left = LumaAt(v_uv + vec2(-inv_size.x, inv_size.y));
  float luma_down_right = LumaAt(v_uv + vec2(inv_size.x, -inv_size.y));

  float luma_down_up = luma_down + luma_up;
  float luma_left_right = luma_left + luma_right;
  float luma_left_corners = luma_down_left + luma_up_left;
  float luma_down_corners = luma_down_left + luma_down_right;
  float luma_right_corners = luma_down_right + luma_up_right;
  float luma_up_corners = luma_up_right + luma_up_left;

  // Second-derivative estimate along each axis classifies the edge as
  // horizontal or vertical.
  float edge_horizontal = abs(-2.0 * luma_left + luma_left_corners) +
                          abs(-2.0 * luma_center + luma_down_up) * 2.0 +
                          abs(-2.0 * luma_right + luma_right_corners);
  float edge_vertical = abs(-2.0 * luma_up + luma_up_corners) +
                        abs(-2.0 * luma_center + luma_left_right) * 2.0 +
                        abs(-2.0 * luma_down + luma_down_corners);
  bool is_horizontal = edge_horizontal >= edge_vertical;

  // Of the two pixels across the edge, find the steeper side.
  float luma1 = is_horizontal ? luma_down : luma_left;
  float luma2 = is_horizontal ? luma_up : luma_right;
  float gradient1 = luma1 - luma_center;
  float gradient2 = luma2 - luma_center;
  bool is_1_steepest = abs(gradient1) >= abs(gradient2);
  float gradient_scaled = 0.25 * max(abs(gradient1), abs(gradient2));

  float step_length = is_horizontal ? inv_size.y : inv_size.x;
  float luma_local_average;
  if (is_1_steepest) {
    step_length = -step_length;
    luma_local_average = 0.5 * (luma1 + luma_center);
  } else {
    luma_local_average = 0.5 * (luma2 + luma_center);
  }

  // Start at the edge midpoint between the two pixels.
  vec2 current_uv = v_uv;
  if (is_horizontal) {
    current_uv.y += step_length * 0.5;
  } else {
    current_uv.x += step_length * 0.5;
  }

  // Walk along the edge in both directions until the luma delta against
  // the local average exceeds the gradient (the edge endpoint).
  vec2 offset = is_horizontal ? vec2(inv_size.x, 0.0) : vec2(0.0, inv_size.y);
  vec2 uv1 = current_uv - offset;
  vec2 uv2 = current_uv + offset;

  float luma_end1 = LumaAt(uv1) - luma_local_average;
  float luma_end2 = LumaAt(uv2) - luma_local_average;
  bool reached1 = abs(luma_end1) >= gradient_scaled;
  bool reached2 = abs(luma_end2) >= gradient_scaled;
  bool reached_both = reached1 && reached2;
  if (!reached1) {
    uv1 -= offset;
  }
  if (!reached2) {
    uv2 += offset;
  }

  if (!reached_both) {
    for (int i = 2; i < kIterations; i++) {
      if (!reached1) {
        luma_end1 = LumaAt(uv1) - luma_local_average;
      }
      if (!reached2) {
        luma_end2 = LumaAt(uv2) - luma_local_average;
      }
      reached1 = abs(luma_end1) >= gradient_scaled;
      reached2 = abs(luma_end2) >= gradient_scaled;
      reached_both = reached1 && reached2;
      if (reached_both) {
        break;
      }
      if (!reached1) {
        uv1 -= offset * StepSize(i);
      }
      if (!reached2) {
        uv2 += offset * StepSize(i);
      }
    }
  }

  float distance1 = is_horizontal ? (v_uv.x - uv1.x) : (v_uv.y - uv1.y);
  float distance2 = is_horizontal ? (uv2.x - v_uv.x) : (uv2.y - v_uv.y);
  bool is_direction1 = distance1 < distance2;
  float distance_final = min(distance1, distance2);
  float edge_length = distance1 + distance2;
  float pixel_offset = -distance_final / edge_length + 0.5;

  // Only offset when the endpoint luma variation is consistent with the
  // center pixel sitting on the darker/lighter side of the edge.
  bool is_center_smaller = luma_center < luma_local_average;
  bool correct_variation =
      ((is_direction1 ? luma_end1 : luma_end2) < 0.0) != is_center_smaller;
  float final_offset = correct_variation ? pixel_offset : 0.0;

  // Subpixel anti-aliasing for high-frequency detail the edge walk misses.
  float luma_average =
      (1.0 / 12.0) * (2.0 * (luma_down_up + luma_left_right) +
                      luma_left_corners + luma_right_corners);
  float subpixel1 =
      clamp(abs(luma_average - luma_center) / luma_range, 0.0, 1.0);
  float subpixel2 = (-2.0 * subpixel1 + 3.0) * subpixel1 * subpixel1;
  float subpixel_offset = subpixel2 * subpixel2 * kSubpixelQuality;
  final_offset = max(final_offset, subpixel_offset);

  // Resample shifted perpendicular to the edge. The premultiplied rgba is
  // filtered as a unit, so coverage stays consistent with color.
  vec2 final_uv = v_uv;
  if (is_horizontal) {
    final_uv.y += final_offset * step_length;
  } else {
    final_uv.x += final_offset * step_length;
  }
  frag_color = texture(scene_color, final_uv);
}
