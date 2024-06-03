#include <impeller/constants.glsl>

const float kPi = 3.14159265358979323846;

//------------------------------------------------------------------------------
/// Lighting equation.
/// See also: https://learnopengl.com/PBR/Lighting
///

const float kGamma = 2.2;

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

float DistributionGGX(vec3 normal, vec3 half_vector, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float NdotH = max(dot(normal, half_vector), 0.0);
  float NdotH2 = NdotH * NdotH;

  float num = a2;
  float denom = (NdotH2 * (a2 - 1.0) + 1.0);
  denom = kPi * denom * denom;

  return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness) {
  float r = (roughness + 1.0);
  float k = (r * r) / 8.0;

  float num = NdotV;
  float denom = NdotV * (1.0 - k) + k;

  return num / denom;
}

float GeometrySmith(vec3 normal, vec3 camera_normal, vec3 light_normal,
                    float roughness) {
  float camera_ggx =
      GeometrySchlickGGX(max(dot(normal, camera_normal), 0.0), roughness);
  float light_ggx =
      GeometrySchlickGGX(max(dot(normal, light_normal), 0.0), roughness);
  return camera_ggx * light_ggx;
}
