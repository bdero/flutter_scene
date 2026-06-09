// Projects an equirectangular radiance image onto 9 L2 diffuse-irradiance
// spherical-harmonic coefficients, on the GPU (no read-back). Rendered into a
// 9x1 texture: output texel i holds coefficient i (RGB). The conventions match
// the CPU projection in environment.dart and EvaluateDiffuseSH in
// material_lighting.glsl, so a baked sky's coefficients light identically to
// an image-based environment's.

uniform sampler2D source_equirect; // baked sky radiance, up pole at the top

in vec2 v_uv;

out vec4 frag_color;

#include <pbr.glsl>      // kPi
#include <texture.glsl>  // SphericalToEquirectangular

// Quadrature grid over the sphere. Coarser than the CPU's (the diffuse SH is
// low frequency, so this is ample), keeping the per-texel loop affordable.
const int kShTheta = 48;
const int kShPhi = 96;

vec3 _sampleRadiance(vec3 dir) {
  vec2 uv = SphericalToEquirectangular(dir);
  // The baked equirect stores the up pole at the top row (the prefilter's
  // source convention), so flip V to match.
  uv.y = 1.0 - uv.y;
  return texture(source_equirect, uv).rgb;
}

// Real-SH basis i (0..8), matching EvaluateDiffuseSH.
float _shBasis(int i, vec3 d) {
  if (i == 0) return 0.282095;
  if (i == 1) return 0.488603 * d.y;
  if (i == 2) return 0.488603 * d.z;
  if (i == 3) return 0.488603 * d.x;
  if (i == 4) return 1.092548 * d.x * d.y;
  if (i == 5) return 1.092548 * d.y * d.z;
  if (i == 6) return 0.315392 * (3.0 * d.z * d.z - 1.0);
  if (i == 7) return 1.092548 * d.x * d.z;
  return 0.546274 * (d.x * d.x - d.y * d.y);
}

// Lambertian convolution band factor A_l / pi (A_0/pi = 1, A_1/pi = 2/3,
// A_2/pi = 1/4), folded in so the eval yields E(n)/pi.
float _bandFactor(int i) {
  if (i == 0) return 1.0;
  if (i <= 3) return 2.0 / 3.0;
  return 0.25;
}

void main() {
  int coeff = int(floor(v_uv.x * 9.0));
  float cellSolidAngle = (2.0 * kPi) * kPi / float(kShPhi * kShTheta);
  vec3 sum = vec3(0.0);
  for (int j = 0; j < kShTheta; j++) {
    float v = (float(j) + 0.5) / float(kShTheta);
    float latitude = (v - 0.5) * kPi;
    float cosLat = cos(latitude);
    float dirY = sin(latitude);
    float weightRow = cosLat * cellSolidAngle;
    for (int i = 0; i < kShPhi; i++) {
      float u = (float(i) + 0.5) / float(kShPhi);
      float longitude = (u - 0.5) * 2.0 * kPi;
      vec3 dir = vec3(cosLat * cos(longitude), dirY, cosLat * sin(longitude));
      sum += _sampleRadiance(dir) * _shBasis(coeff, dir) * weightRow;
    }
  }
  frag_color = vec4(sum * _bandFactor(coeff), 1.0);
}
