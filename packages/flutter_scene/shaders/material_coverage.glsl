#ifndef MATERIAL_COVERAGE_GLSL_
#define MATERIAL_COVERAGE_GLSL_

// Alpha to coverage for `alpha_to_coverage: true` materials. Flutter GPU has
// no pipeline switch for it, so the fragment writes the sample mask itself:
// alpha picks how many of 4 samples it covers, with an ordered dither between
// counts and a per-pixel rotation of which samples, so overlapping cutouts add
// up instead of stacking on the same samples. Sample 0 fills second, so a
// single-sample target keeps a fragment once its dithered coverage reaches
// half (a dithered 0.5 cutout).
// TODO(alpha-to-coverage): use the pipeline's alpha-to-coverage once Flutter
// GPU exposes it, which also follows the target's real sample count.
void ApplyAlphaToCoverage(float alpha) {
  // Interleaved gradient noise: a stable per-pixel threshold.
  highp vec2 p = floor(gl_FragCoord.xy);
  float dither = fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
#if defined(IMPELLER_TARGET_METAL) || defined(IMPELLER_TARGET_VULKAN)
  int count = int(clamp(alpha, 0.0, 1.0) * 4.0 + dither);
  if (count <= 0) {
    discard;
  }
  // The first covered sample is 1, 2, or 3 by pixel; sample 0 comes next.
  int first = 1 + int(fract(dither * 7.0 + 0.5 * p.y) * 3.0);
  int mask = (1 << first);
  if (count >= 2) mask |= 1;
  if (count >= 3) mask |= (1 << (first == 3 ? 1 : first + 1));
  if (count >= 4) mask = 15;
  gl_SampleMask[0] = mask;
#else
  if (alpha < 0.25 + 0.5 * dither) {
    discard;
  }
#endif
}

#endif  // MATERIAL_COVERAGE_GLSL_
