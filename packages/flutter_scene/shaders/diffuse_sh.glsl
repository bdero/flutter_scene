// Diffuse-irradiance spherical harmonics read from a coefficient strip.
//
// Coefficient i (0..8) lives at texel (i, row) of the strip, row 0 the
// primary environment and row 1 the cross-fade secondary. The coefficients
// already carry the cosine convolution and the 1/pi, so the result is
// E(n)/pi, matching the CPU projection in
// EnvironmentMap.computeDiffuseSphericalHarmonics.
//
// Fetched rather than sampled so the strip can share a texture with the
// irradiance field's probe atlas: a bilinear sampler would otherwise smear a
// neighbouring probe texel into coefficient 8. texelFetch ignores the
// sampler's filter mode and needs no knowledge of the texture's height, which
// is what makes the shared atlas safe.

vec3 DiffuseShCoefficient(sampler2D coefficients, int i, int row) {
  return texelFetch(coefficients, ivec2(i, row), 0).xyz;
}

vec3 EvaluateDiffuseSH(sampler2D coefficients, vec3 n, int row) {
  return DiffuseShCoefficient(coefficients, 0, row) * 0.282095 +
         DiffuseShCoefficient(coefficients, 1, row) * (0.488603 * n.y) +
         DiffuseShCoefficient(coefficients, 2, row) * (0.488603 * n.z) +
         DiffuseShCoefficient(coefficients, 3, row) * (0.488603 * n.x) +
         DiffuseShCoefficient(coefficients, 4, row) * (1.092548 * n.x * n.y) +
         DiffuseShCoefficient(coefficients, 5, row) * (1.092548 * n.y * n.z) +
         DiffuseShCoefficient(coefficients, 6, row) *
             (0.315392 * (3.0 * n.z * n.z - 1.0)) +
         DiffuseShCoefficient(coefficients, 7, row) * (1.092548 * n.x * n.z) +
         DiffuseShCoefficient(coefficients, 8, row) *
             (0.546274 * (n.x * n.x - n.y * n.y));
}
