// Near-field CoC dilation for depth of field. An out-of-focus foreground
// object must blur PAST its geometric silhouette (the silhouette itself is
// out of focus), but a gather driven by the center pixel's own CoC stops dead
// at the edge. This pass blurs the near-field CoC over the maximum
// foreground radius and applies Hammon's correction (GPU Gems 3 ch. 28),
// D = 2 * max(D0, blurred) - D0, so blurriness grows outward across the
// silhouette without shrinking inside the object.

precision highp float;

uniform sampler2D coc_color; // half res, signed CoC in alpha

uniform DilateInfo {
  // x: blur radius in half-res pixels   yz: half-res texel size   w: unused
  vec4 params0;
}
dilate_info;

in vec2 v_uv;

out vec4 frag_color;

float NearAt(vec2 uv) { return max(-texture(coc_color, uv).a, 0.0); }

void main() {
  float d0 = NearAt(v_uv);
  vec2 texel = dilate_info.params0.yz;
  float radius = dilate_info.params0.x;
  // 12-tap disc average (8 outer, 4 inner) plus the center.
  float sum = d0;
  for (int i = 0; i < 8; i++) {
    float ang = float(i) * 0.7853982; // 2pi / 8
    sum += NearAt(v_uv + vec2(cos(ang), sin(ang)) * radius * texel);
  }
  for (int i = 0; i < 4; i++) {
    float ang = float(i) * 1.5707963 + 0.7853982; // 2pi / 4, offset
    sum += NearAt(v_uv + vec2(cos(ang), sin(ang)) * radius * 0.5 * texel);
  }
  float blurred = sum / 13.0;
  frag_color = vec4(2.0 * max(d0, blurred) - d0, 0.0, 0.0, 1.0);
}
