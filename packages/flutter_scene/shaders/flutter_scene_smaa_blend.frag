// SMAA pass 3 of 3: neighborhood blending. Blends each pixel with its
// neighbors along the dominant edge direction using the weights from pass
// 2, resolving to the final antialiased color. See smaa.glsl for the port
// notes and the reference implementation license.

uniform SmaaInfo {
  // (1/width, 1/height, width, height) of the display target.
  vec4 rt_metrics;
  // Runtime quality (Scene.smaa): threshold, max search steps, max diagonal
  // search steps, corner rounding percentage.
  vec4 params;
}
smaa_info;

uniform sampler2D scene_color;
uniform sampler2D blend_texture;

in vec2 v_uv;
out vec4 frag_color;

#include <smaa.glsl>

void main() {
  vec4 offset =
      SMAA_RT_METRICS.xyxy * vec4(1.0, 0.0, 0.0, 1.0) + v_uv.xyxy;

  // The four directions' blending weights for this pixel.
  vec4 a;
  a.x = texture(blend_texture, offset.xy).a;
  a.y = texture(blend_texture, offset.zw).g;
  a.wz = texture(blend_texture, v_uv).xz;

  if (dot(a, vec4(1.0)) < 1e-5) {
    frag_color = textureLod(scene_color, v_uv, 0.0);
  } else {
    bool horizontal = max(a.x, a.z) > max(a.y, a.w);

    vec4 blending_offset = vec4(0.0, a.y, 0.0, a.w);
    vec2 blending_weight = a.yw;
    SmaaMovc4(bvec4(horizontal), blending_offset, vec4(a.x, 0.0, a.z, 0.0));
    SmaaMovc2(bvec2(horizontal), blending_weight, a.xz);
    blending_weight /= dot(blending_weight, vec2(1.0));

    // One bilinear fetch per side lands between the two source pixels at
    // exactly the coverage ratio.
    vec4 blending_coord = blending_offset * vec4(SMAA_RT_METRICS.xy,
                                                 -SMAA_RT_METRICS.xy) +
                          v_uv.xyxy;
    vec4 color =
        blending_weight.x * textureLod(scene_color, blending_coord.xy, 0.0);
    color +=
        blending_weight.y * textureLod(scene_color, blending_coord.zw, 0.0);
    frag_color = color;
  }
}
