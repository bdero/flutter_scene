// Depth conflict overlay (full-screen, drawn over the finished scene pass).
//
// Compares object-id images of the view drawn with every surface nudged
// slightly toward or away from the camera, with those nudges negated, and
// with other nudges in reversed draw order (see depth_conflicts.dart).
// None moves a silhouette, so a patch of pixels whose owner differs between
// them is one two surfaces fight over (z-fighting), marked with a crawling
// magenta checkerboard.
//
// The id images are render-to-texture targets stored top-down on every
// backend, like the pass this draws into, so they sample at v_uv.

precision highp float;

uniform sampler2D id_nudged;
uniform sampler2D id_opposite;
uniform sampler2D id_reordered;

uniform DepthConflictInfo {
  // x: time in seconds. y: checker cell size in pixels. z: opacity.
  vec4 params;
}
info;

in vec2 v_uv;
out vec4 frag_color;

// Whether the owner of texel `q` differs between the nudged image and the
// one with nudges negated (AB), or the one drawn in reverse with other nudges
// (AC). Background in either image is a clip edge, not a fight. Fetched by
// texel, so nothing here needs derivatives.
bool ChangedAB(ivec2 q) {
  vec3 a = texelFetch(id_nudged, q, 0).rgb;
  vec3 b = texelFetch(id_opposite, q, 0).rgb;
  return dot(a, a) > 0.0 && dot(b, b) > 0.0 && any(notEqual(a, b));
}

bool ChangedAC(ivec2 q) {
  vec3 a = texelFetch(id_nudged, q, 0).rgb;
  vec3 c = texelFetch(id_reordered, q, 0).rgb;
  return dot(a, a) > 0.0 && dot(c, c) > 0.0 && any(notEqual(a, c));
}

// How many of texel `p`'s eight neighbors changed, for each comparison.
// Unrolled, and clamped at the image edge.
ivec2 ChangedNeighbors(ivec2 p, ivec2 size) {
  ivec2 lo = ivec2(0);
  ivec2 hi = size - 1;
  ivec2 n00 = clamp(p + ivec2(-1, -1), lo, hi);
  ivec2 n10 = clamp(p + ivec2(0, -1), lo, hi);
  ivec2 n20 = clamp(p + ivec2(1, -1), lo, hi);
  ivec2 n01 = clamp(p + ivec2(-1, 0), lo, hi);
  ivec2 n21 = clamp(p + ivec2(1, 0), lo, hi);
  ivec2 n02 = clamp(p + ivec2(-1, 1), lo, hi);
  ivec2 n12 = clamp(p + ivec2(0, 1), lo, hi);
  ivec2 n22 = clamp(p + ivec2(1, 1), lo, hi);
  int ab = (ChangedAB(n00) ? 1 : 0) + (ChangedAB(n10) ? 1 : 0) +
           (ChangedAB(n20) ? 1 : 0) + (ChangedAB(n01) ? 1 : 0) +
           (ChangedAB(n21) ? 1 : 0) + (ChangedAB(n02) ? 1 : 0) +
           (ChangedAB(n12) ? 1 : 0) + (ChangedAB(n22) ? 1 : 0);
  int ac = (ChangedAC(n00) ? 1 : 0) + (ChangedAC(n10) ? 1 : 0) +
           (ChangedAC(n20) ? 1 : 0) + (ChangedAC(n01) ? 1 : 0) +
           (ChangedAC(n21) ? 1 : 0) + (ChangedAC(n02) ? 1 : 0) +
           (ChangedAC(n12) ? 1 : 0) + (ChangedAC(n22) ? 1 : 0);
  return ivec2(ab, ac);
}

// A changed texel counts only when at least four of its eight neighbors
// changed too, so a moved edge, crossing, or sliver (a line) is not marked;
// see kDepthConflictAreaNeighbors.
void main() {
  ivec2 size = textureSize(id_nudged, 0);
  ivec2 p = clamp(ivec2(v_uv * vec2(size)), ivec2(0), size - 1);
  bool ab = ChangedAB(p);
  bool ac = ChangedAC(p);
  if (!ab && !ac) {
    discard;
  }
  ivec2 neighbors = ChangedNeighbors(p, size);
  if (!(ab && neighbors.x >= 4) && !(ac && neighbors.y >= 4)) {
    discard;
  }
  vec2 cell = floor(gl_FragCoord.xy / max(info.params.y, 1.0));
  float phase = mod(cell.x + cell.y + floor(info.params.x * 6.0), 2.0);
  vec3 color = mix(vec3(1.0, 0.0, 1.0), vec3(0.02, 0.0, 0.02), phase);
  // Premultiplied, like everything the scene pass blends.
  frag_color = vec4(color, 1.0) * info.params.z;
}
