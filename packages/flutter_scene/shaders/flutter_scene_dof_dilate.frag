// Near-field CoC dilation for depth of field. An out-of-focus foreground
// object must blur past its geometric silhouette (the silhouette itself is
// out of focus), but a gather driven by the center pixel's own CoC stops at
// the edge. This finds the largest near-field CoC within the maximum
// foreground radius, as a separable max filter run twice (horizontal from
// the CoC, then vertical from that), so every pixel an out-of-focus object's
// blur can reach gathers far enough to find it. Alongside it rides the reach
// (the largest CoC minus its distance), which says how much of this pixel
// the spill actually covers; beyond it the sharp image stays untouched. The
// gather weights each sample by its own CoC, so only the object spreads.

precision highp float;

uniform sampler2D coc_color; // half res; signed CoC in alpha, or the last pass in rg

uniform DilateInfo {
  // x: radius in half-res pixels   yz: step between taps in uv
  // w: 0 reads the near CoC from alpha, 1 reads the previous pass from rg
  vec4 params0;
}
dilate_info;

in vec2 v_uv;

out vec4 frag_color;

// The near CoC and its reach at uv (both the CoC on the first pass).
vec2 NearAt(vec2 uv) {
  vec4 s = texture(coc_color, uv);
  if (dilate_info.params0.w > 0.5) {
    return s.rg;
  }
  float near = max(-s.a, 0.0);
  return vec2(near);
}

void main() {
  vec2 stride = dilate_info.params0.yz;
  int radius = int(ceil(dilate_info.params0.x));
  vec2 best = NearAt(v_uv);
  for (int i = 1; i <= 64; i++) {
    if (i > radius) break;
    float d = float(i);
    vec2 a = NearAt(v_uv + stride * d);
    vec2 b = NearAt(v_uv - stride * d);
    best.x = max(best.x, max(a.x, b.x));
    best.y = max(best.y, max(a.y, b.y) - d);
  }
  frag_color = vec4(best, 0.0, 1.0);
}
