// Depth-of-field gather at half resolution, scatter-as-gather over a
// precomputed unit-disc kernel (Vogel spiral, optionally warped to the
// aperture polygon on the CPU, so bokeh shape costs nothing here). Each
// sample contributes where its own CoC disc covers this pixel
// (saturate((sampleCoC - dist) * 0.5 + 0.5)), with two occlusion guards: a
// sample behind the center cannot spread past twice the center's blur, and
// in-focus samples never bleed into the fields (their CoC is exactly 0).
// Outputs the blurred color plus a coverage alpha the composite blends by.

precision highp float;

uniform sampler2D coc_color; // half res, signed CoC in alpha
uniform sampler2D near_coc;  // dilated near-field CoC (r)

uniform GatherInfo {
  // x: tap vec4 count in use   yz: half-res texel size   w: unused
  vec4 params0;
  // Unit-disc tap positions, two vec2 taps per vec4.
  vec4 taps[24];
}
gather_info;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  vec4 center = texture(coc_color, v_uv);
  float nearC = texture(near_coc, v_uv).r;
  float farC = max(center.a, 0.0);
  float radius = max(nearC, farC);
  if (radius < 0.5) {
    frag_color = vec4(0.0);
    return;
  }
  vec2 texel = gather_info.params0.yz;
  float centerAbs = max(abs(center.a), 1.0);
  vec3 accum = center.rgb;
  float weightSum = 1.0;
  int pairs = int(gather_info.params0.x);

  for (int i = 0; i < 24; i++) {
    if (i >= pairs) break;
    vec4 pair = gather_info.taps[i];
    for (int j = 0; j < 2; j++) {
      vec2 k = (j == 0) ? pair.xy : pair.zw;
      float dist = length(k) * radius;
      vec2 uv = v_uv + k * radius * texel;
      vec4 s = texture(coc_color, uv);
      float sNear = texture(near_coc, uv).r;
      float sCoc = max(abs(s.a), sNear);
      // CoC is monotonic in depth around the focus plane, so a larger signed
      // CoC means farther away; clamp how far behind-samples can spread.
      if (s.a > center.a) {
        sCoc = min(sCoc, centerAbs * 2.0);
      }
      float w = clamp((sCoc - dist) * 0.5 + 0.5, 0.0, 1.0);
      accum += s.rgb * w;
      weightSum += w;
    }
  }
  float coverage = clamp(radius - 0.5, 0.0, 1.0);
  // Premultiplied by coverage: the postfilter and the composite's bilinear
  // upsample average this output against the early-out transparent-black
  // pixels at the focus boundary, and only premultiplied color survives that
  // filtering without pulling toward black (a dark seam along the focus
  // plane otherwise).
  frag_color = vec4(accum / weightSum * coverage, coverage);
}
