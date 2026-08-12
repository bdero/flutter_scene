// SMAA pass 1 of 3: luma edge detection with local contrast adaptation.
// Writes the horizontal/vertical edge flags to rg; texels with no edge
// discard, leaving the cleared target. See smaa.glsl for the port notes and
// the reference implementation license.

uniform SmaaInfo {
  // (1/width, 1/height, width, height) of the display target.
  vec4 rt_metrics;
}
smaa_info;

// The tone-mapped display color (perceptual space, as luma edge detection
// expects).
uniform sampler2D scene_color;

in vec2 v_uv;
out vec4 frag_color;

#include <smaa.glsl>

void main() {
  vec4 offset0 =
      SMAA_RT_METRICS.xyxy * vec4(-1.0, 0.0, 0.0, -1.0) + v_uv.xyxy;
  vec4 offset1 =
      SMAA_RT_METRICS.xyxy * vec4(1.0, 0.0, 0.0, 1.0) + v_uv.xyxy;
  vec4 offset2 =
      SMAA_RT_METRICS.xyxy * vec4(-2.0, 0.0, 0.0, -2.0) + v_uv.xyxy;

  const vec3 weights = vec3(0.2126, 0.7152, 0.0722);
  float l = dot(texture(scene_color, v_uv).rgb, weights);
  float l_left = dot(texture(scene_color, offset0.xy).rgb, weights);
  float l_top = dot(texture(scene_color, offset0.zw).rgb, weights);

  vec4 delta;
  delta.xy = abs(l - vec2(l_left, l_top));
  vec2 edges = step(vec2(SMAA_THRESHOLD), delta.xy);
  if (dot(edges, vec2(1.0, 1.0)) == 0.0) {
    discard;
  }

  float l_right = dot(texture(scene_color, offset1.xy).rgb, weights);
  float l_bottom = dot(texture(scene_color, offset1.zw).rgb, weights);
  delta.zw = abs(l - vec2(l_right, l_bottom));
  vec2 max_delta = max(delta.xy, delta.zw);

  float l_leftleft = dot(texture(scene_color, offset2.xy).rgb, weights);
  float l_toptop = dot(texture(scene_color, offset2.zw).rgb, weights);
  delta.zw = abs(vec2(l_left, l_top) - vec2(l_leftleft, l_toptop));
  max_delta = max(max_delta.xy, delta.zw);
  float final_delta = max(max_delta.x, max_delta.y);

  // Local contrast adaptation: a much stronger neighboring edge masks this
  // one.
  edges.xy *= step(final_delta,
                   SMAA_LOCAL_CONTRAST_ADAPTATION_FACTOR * delta.xy);

  frag_color = vec4(edges, 0.0, 1.0);
}
