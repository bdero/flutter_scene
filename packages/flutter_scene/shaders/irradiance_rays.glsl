// The probe ray set the traced irradiance feed shoots and gathers, shared so
// both kernels agree on each ray's direction.

// Direction of ray [i] of [n], spherical Fibonacci points rotated by
// [rotation], which changes every frame so the rays sweep the sphere over
// time and the field's temporal blend integrates them.
vec3 ProbeRayDirection(float i, float n, mat3 rotation) {
  const float kGoldenAngle = 2.399963229728653;
  float cos_theta = 1.0 - (2.0 * i + 1.0) / n;
  float sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
  float phi = kGoldenAngle * i;
  return rotation * vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
}
