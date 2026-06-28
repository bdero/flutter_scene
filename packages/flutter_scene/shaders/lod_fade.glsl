// Screen-door dither for level-of-detail cross-fades.
//
// [coverage] of 1 keeps every fragment. A value in (0, 1) keeps that fraction
// of fragments in a stable screen-space dither pattern and discards the rest;
// a negative value keeps the complementary pattern of |coverage|. Drawing two
// adjacent LOD levels whose fades sum to 1, one with the positive coverage and
// one with the negative, tiles the screen between them with no overdraw, so
// the levels blend without translucency.
//
// The hash is the Weyl pattern used elsewhere in the engine (resolve grain,
// shadow PCF rotation), and gl_FragCoord behaves the same on Impeller and the
// WebGL2 backend.
void ApplyLodFade(float coverage) {
  if (coverage >= 1.0) {
    return;
  }
  float dither = fract(
      52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  if (coverage < 0.0) {
    dither = 1.0 - dither;
    coverage = -coverage;
  }
  if (dither >= coverage) {
    discard;
  }
}
