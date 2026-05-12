#include <impeller/constants.glsl>

const float kPi = 3.14159265358979323846;

//------------------------------------------------------------------------------
/// Lighting equation.
/// See also: https://learnopengl.com/PBR/Lighting and
///           https://google.github.io/filament/Filament.html
///

const float kGamma = 2.2;

// Lower bound on perceptual roughness. Glossier than this and the GGX lobe
// collapses to a delta; on half-float mobile hardware the resulting
// denormalized `alpha` (= roughness^2) also triggers large performance
// drops, so every roughness input is clamped to this floor.
const float kMinRoughness = 0.045;

// Convert from sRGB to linear space.
// This can be removed once Impeller supports sRGB texture inputs.
vec3 SRGBToLinear(vec3 color) { return pow(color, vec3(kGamma)); }

vec3 FresnelSchlick(float cos_theta, vec3 reflectance) {
  return reflectance +
         (1.0 - reflectance) * pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

vec3 FresnelSchlickRoughness(float cos_theta, vec3 reflectance,
                             float roughness) {
  return reflectance + (max(vec3(1.0 - roughness), reflectance) - reflectance) *
                           pow(clamp(1.0 - cos_theta, 0.0, 1.0), 5.0);
}

// GGX / Trowbridge-Reitz normal distribution.
//
// fp16-safe formulation (Filament): the standard `NoH^2 (a^2 - 1) + 1`
// term suffers catastrophic cancellation in half precision. Rewriting it
// via `1 - NoH^2 == dot(cross(n, h), cross(n, h))` keeps it stable on
// mobile GPUs. `roughness` is perceptual roughness; `alpha = roughness^2`.
float DistributionGGX(vec3 normal, vec3 half_vector, float roughness) {
  float alpha = roughness * roughness;
  vec3 n_cross_h = cross(normal, half_vector);
  float n_dot_h = max(dot(normal, half_vector), 0.0);
  float a = n_dot_h * alpha;
  float k = alpha / (dot(n_cross_h, n_cross_h) + a * a);
  return k * k * (1.0 / kPi);
}

// Height-correlated Smith-GGX visibility term: V = G / (4 * NoL * NoV).
//
// This is the sqrt-free fast approximation from Filament, recommended for
// mobile. `roughness` is perceptual roughness.
float VisibilitySmithGGXCorrelated(float n_dot_v, float n_dot_l,
                                   float roughness) {
  float alpha = roughness * roughness;
  float ggx = mix(2.0 * n_dot_l * n_dot_v, n_dot_l + n_dot_v, alpha);
  return 0.5 / max(ggx, 1e-5);
}

// Legacy separable Smith geometry term (returns G, not visibility).
//
// Retained for callers that still expect the un-divided geometry term;
// new code should prefer [VisibilitySmithGGXCorrelated].
float GeometrySchlickGGX(float n_dot_v, float roughness) {
  float r = (roughness + 1.0);
  float k = (r * r) / 8.0;
  return n_dot_v / (n_dot_v * (1.0 - k) + k);
}

float GeometrySmith(vec3 normal, vec3 camera_normal, vec3 light_normal,
                    float roughness) {
  float camera_ggx =
      GeometrySchlickGGX(max(dot(normal, camera_normal), 0.0), roughness);
  float light_ggx =
      GeometrySchlickGGX(max(dot(normal, light_normal), 0.0), roughness);
  return camera_ggx * light_ggx;
}
