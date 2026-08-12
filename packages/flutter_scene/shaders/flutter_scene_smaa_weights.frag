// SMAA pass 2 of 3: blending-weight calculation. For each edge texel,
// searches along the edge for the line ends (accelerated by the packed
// search texture), classifies the pattern, and reads the precomputed
// coverage from the area texture, with diagonal handling and corner
// rounding. See smaa.glsl for the port notes and the reference
// implementation license.

uniform SmaaInfo {
  // (1/width, 1/height, width, height) of the display target.
  vec4 rt_metrics;
}
smaa_info;

uniform sampler2D edges_texture;
uniform sampler2D area_texture;
uniform sampler2D search_texture;

in vec2 v_uv;
out vec4 frag_color;

#include <smaa.glsl>

void main() {
  vec2 pixcoord = v_uv * SMAA_RT_METRICS.zw;
  // The pre-offset search coordinates (see @PSEUDO_GATHER4 in the
  // reference; computed in the vertex stage there).
  vec4 offset0 = SMAA_RT_METRICS.xyxy * vec4(-0.25, -0.125, 1.25, -0.125) +
                 v_uv.xyxy;
  vec4 offset1 = SMAA_RT_METRICS.xyxy * vec4(-0.125, -0.25, -0.125, 1.25) +
                 v_uv.xyxy;
  vec4 offset2 = SMAA_RT_METRICS.xxyy *
                     (vec4(-2.0, 2.0, -2.0, 2.0) *
                      float(SMAA_MAX_SEARCH_STEPS)) +
                 vec4(offset0.xz, offset1.yw);

  vec4 weights = vec4(0.0);
  vec2 e = texture(edges_texture, v_uv).rg;

  if (e.g > 0.0) {
    // Edge at north. Diagonals have both north and west edges, so checking
    // one boundary is enough; a found diagonal skips the orthogonal search.
    weights.rg =
        SmaaCalculateDiagWeights(edges_texture, area_texture, v_uv, e);
    if (weights.r == -weights.g) {
      vec2 d;
      vec3 coords;
      coords.x =
          SmaaSearchXLeft(edges_texture, search_texture, offset0.xy,
                          offset2.x);
      coords.y = offset1.y;
      d.x = coords.x;

      float e1 = textureLod(edges_texture, coords.xy, 0.0).r;

      coords.z = SmaaSearchXRight(edges_texture, search_texture, offset0.zw,
                                  offset2.y);
      d.y = coords.z;

      d = abs(round(SMAA_RT_METRICS.zz * d - pixcoord.xx));
      vec2 sqrt_d = sqrt(d);

      float e2 =
          textureLodOffset(edges_texture, coords.zy, 0.0, ivec2(1, 0)).r;

      weights.rg = SmaaArea(area_texture, sqrt_d, e1, e2);

      coords.y = v_uv.y;
      SmaaDetectHorizontalCornerPattern(edges_texture, weights.rg,
                                        coords.xyzy, d);
    } else {
      // Skip the vertical processing for this diagonal.
      e.r = 0.0;
    }
  }

  if (e.r > 0.0) {
    // Edge at west.
    vec2 d;
    vec3 coords;
    coords.y =
        SmaaSearchYUp(edges_texture, search_texture, offset1.xy, offset2.z);
    coords.x = offset0.x;
    d.x = coords.y;

    float e1 = textureLod(edges_texture, coords.xy, 0.0).g;

    coords.z =
        SmaaSearchYDown(edges_texture, search_texture, offset1.zw,
                        offset2.w);
    d.y = coords.z;

    d = abs(round(SMAA_RT_METRICS.ww * d - pixcoord.yy));
    vec2 sqrt_d = sqrt(d);

    float e2 =
        textureLodOffset(edges_texture, coords.xz, 0.0, ivec2(0, 1)).g;

    weights.ba = SmaaArea(area_texture, sqrt_d, e1, e2);

    coords.x = v_uv.x;
    SmaaDetectVerticalCornerPattern(edges_texture, weights.ba, coords.xyxz,
                                    d);
  }

  frag_color = weights;
}
