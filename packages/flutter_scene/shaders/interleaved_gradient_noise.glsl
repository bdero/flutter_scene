float InterleavedGradientNoise(vec2 pixel) {
  return fract(52.9829189 *
               fract(dot(floor(pixel), vec2(0.06711056, 0.00583715))));
}

// Two decorrelated per-frame offsets for the noise (the R2 sequence), so a
// temporal resolve accumulates different samples each frame. Frame 0 gives
// no offset.
highp vec2 TemporalNoiseOffset(highp float frame) {
  return fract(frame * vec2(0.7548776662, 0.5698402910));
}
