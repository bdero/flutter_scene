// Turns a sampled texel into the normalized value. DECODE_RG reads a 16-bit
// value stored high byte in red, low byte in green; since filtering is
// linear, a filtered pair still decodes to the filtered value. Otherwise the
// value is the red channel (r8, r32Float).

float Decode(vec4 texel) {
#ifdef DECODE_RG
  return (texel.r * 65280.0 + texel.g * 255.0) / 65535.0;
#else
  return texel.r;
#endif
}
