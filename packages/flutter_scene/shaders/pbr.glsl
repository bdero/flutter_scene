#include <impeller/constants.glsl>

const float kPi = 3.14159265358979323846;

//------------------------------------------------------------------------------
/// Lighting equation.
/// See also: https://learnopengl.com/PBR/Lighting and
///           https://google.github.io/filament/Filament.html
///

// Lower bound on perceptual roughness. Glossier than this and the GGX lobe
// collapses to a delta; on half-float mobile hardware the resulting
// denormalized `alpha` (= roughness^2) also triggers large performance
// drops, so every roughness input is clamped to this floor.
const float kMinRoughness = 0.045;

// Convert from sRGB to linear space.
// This can be removed once Impeller supports sRGB texture inputs.
vec3 SRGBToLinear(vec3 color) {
  return mix(color / 12.92,
             pow((color + 0.055) / 1.055, vec3(2.4)),
             step(0.04045, color));
}

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
  float n_dot_h = dot(normal, half_vector);
  // Microfacets only exist in the normal's hemisphere. For a half vector in the
  // lower hemisphere (n_dot_h <= 0, e.g. a back-lit double-sided card viewed
  // from behind, where the light and view are on opposite sides of the shading
  // normal) the fp16-safe denominator below collapses to zero near the antipode
  // (|n x h|^2 -> 0 while the a^2 guard is also 0 because a uses a clamped
  // n_dot_h), so k = alpha / 0 = Inf. There is no distribution there; return 0.
  if (n_dot_h <= 0.0) {
    return 0.0;
  }
  float alpha = roughness * roughness;
  vec3 n_cross_h = cross(normal, half_vector);
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

#ifdef FLUTTER_SCENE_PHYSICAL_MATERIAL
// Estevez/Kulla Charlie sheen distribution and fitted visibility.
float DistributionCharlie(float roughness, float n_dot_h) {
  // Keep the reciprocal exponent inside mediump range on mobile fragment
  // stages.
  float alpha = max(roughness * roughness,
                    kMinRoughness * kMinRoughness);
  float inv_alpha = 1.0 / alpha;
  float sin2 = max(1.0 - n_dot_h * n_dot_h, 0.0);
  return (2.0 + inv_alpha) * pow(sin2, inv_alpha * 0.5) /
         (2.0 * kPi);
}

float _SheenLambdaHelper(float x, float alpha) {
  float one_minus_alpha_sq = (1.0 - alpha) * (1.0 - alpha);
  float a = mix(21.5473, 25.3245, one_minus_alpha_sq);
  float b = mix(3.82987, 3.32435, one_minus_alpha_sq);
  float c = mix(0.19823, 0.16801, one_minus_alpha_sq);
  float d = mix(-1.97760, -1.27393, one_minus_alpha_sq);
  float e = mix(-4.32054, -4.85967, one_minus_alpha_sq);
  return a / (1.0 + b * pow(max(x, 1e-5), c)) + d * x + e;
}

float _SheenLambda(float cosine, float alpha) {
  if (abs(cosine) < 0.5) {
    return exp(_SheenLambdaHelper(abs(cosine), alpha));
  }
  return exp(2.0 * _SheenLambdaHelper(0.5, alpha) -
             _SheenLambdaHelper(1.0 - abs(cosine), alpha));
}

float VisibilitySheen(float n_dot_l, float n_dot_v, float roughness) {
  float alpha = max(roughness * roughness,
                    kMinRoughness * kMinRoughness);
  float denominator =
      (1.0 + _SheenLambda(n_dot_v, alpha) +
       _SheenLambda(n_dot_l, alpha)) *
      (4.0 * n_dot_v * n_dot_l);
  return clamp(1.0 / max(denominator, 1e-5), 0.0, 1.0);
}

float DistributionGGXAnisotropic(vec3 n, vec3 h, vec3 tangent,
                                 vec3 bitangent, float alpha_t,
                                 float alpha_b) {
  float t_dot_h = dot(tangent, h);
  float b_dot_h = dot(bitangent, h);
  float n_dot_h = max(dot(n, h), 0.0);
  float alpha_product = alpha_t * alpha_b;
  vec3 f = vec3(alpha_b * t_dot_h, alpha_t * b_dot_h,
                alpha_product * n_dot_h);
  float denominator = max(dot(f, f), 1e-10);
  float w2 = alpha_product / denominator;
  return alpha_product * w2 * w2 * (1.0 / kPi);
}

float VisibilityGGXAnisotropic(float n_dot_l, float n_dot_v,
                               float t_dot_v, float b_dot_v,
                               float t_dot_l, float b_dot_l,
                               float alpha_t, float alpha_b) {
  float ggx_v = n_dot_l *
      length(vec3(alpha_t * t_dot_v, alpha_b * b_dot_v, n_dot_v));
  float ggx_l = n_dot_v *
      length(vec3(alpha_t * t_dot_l, alpha_b * b_dot_l, n_dot_l));
  return clamp(0.5 / max(ggx_v + ggx_l, 1e-5), 0.0, 1.0);
}

// Compact thin-film approximation. Thickness is nanometres.
// TODO(iridescence): replace the three RGB phase samples with spectral
// integration and display-response conversion.
vec3 ThinFilmFresnel(vec3 base_f0, float film_ior, float thickness,
                     float n_dot_v) {
  float optical_path = 2.0 * max(film_ior, 1.0) * thickness *
                       sqrt(max(1.0 - (1.0 - n_dot_v * n_dot_v) /
                                          (film_ior * film_ior),
                                0.0));
  vec3 phase = 6.28318530718 * optical_path /
               vec3(650.0, 510.0, 475.0);
  vec3 interference = 0.5 + 0.5 * cos(phase);
  vec3 film_f0 = vec3(pow((film_ior - 1.0) / (film_ior + 1.0), 2.0));
  return clamp(mix(base_f0, film_f0 + (1.0 - film_f0) * interference,
                   smoothstep(0.0, 50.0, thickness)),
               0.0, 1.0);
}
#endif
