uniform FragInfo {
  vec4 color;
  float vertex_color_weight;
  float exposure;
  float metallic_factor;
  float roughness_factor;
  float normal_scale;
  float occlusion_strength;
  float environment_intensity;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;
uniform sampler2D radiance_texture;
uniform sampler2D irradiance_texture;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

#include <impeller/constants.glsl>

const float kPi = 3.14159265358979323846;

const vec3 kLightNormal = normalize(vec3(2.0, 5.0, -5.0));
const vec3 kLightColor = vec3(1.0, 0.8, 0.8) * 3.0;

const vec3 kHighlightNormal = normalize(vec3(-2.0, -3.0, 0.0));
const vec3 kHighlightColor = vec3(1.0, 0.1, 0.0) * 1.5;

//------------------------------------------------------------------------------
/// Equirectangular projection.
/// See also: https://learnopengl.com/PBR/IBL/Diffuse-irradiance
///

const vec2 kInvAtan = vec2(0.1591, 0.3183);

vec2 SphericalToEquirectangular(vec3 direction) {
  vec2 uv = vec2(atan(direction.z, direction.x), asin(direction.y));
  uv *= kInvAtan;
  uv += 0.5;
  return uv;
}

vec3 SampleEnvironmentTexture(sampler2D tex, vec3 direction) {
  vec2 uv = SphericalToEquirectangular(direction);
  return texture(tex, uv).rgb;
}

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

vec3 LightFormula(vec3 light_color, vec3 camera_normal, vec3 light_normal,
                  vec3 albedo, vec3 normal, float metallic, float roughness,
                  vec3 reflectance) {
  vec3 half_vector = normalize(camera_normal + light_normal);

  // Cook-Torrance BRDF.
  float distribution = DistributionGGX(normal, half_vector, roughness);
  float geometry =
      GeometrySmith(normal, camera_normal, light_normal, roughness);
  vec3 fresnel =
      FresnelSchlick(max(dot(half_vector, camera_normal), 0.0), reflectance);

  vec3 kS = fresnel;
  vec3 kD = vec3(1.0) - kS;
  kD *= 1.0 - metallic;

  vec3 numerator = distribution * geometry * fresnel;
  float denominator = 4.0 * max(dot(normal, camera_normal), 0.0) *
                          max(dot(normal, light_normal), 0.0) +
                      0.0001;
  vec3 specular = numerator / denominator;

  float NdotL = max(dot(normal, light_normal), 0.0);
  return (kD * albedo / kPi + specular) * light_color * NdotL;
}

//------------------------------------------------------------------------------
/// Normal resolution.
/// See also: http://www.thetenthplanet.de/archives/1180
///

mat3 CotangentFrame(vec3 N, vec3 p, vec2 uv) {
  vec3 dp1 = dFdx(p);
  vec3 dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv);
  vec2 duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, N);
  vec3 dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
  float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
  return mat3(T * invmax, B * invmax, N);
}

vec3 PerturbNormal(vec3 N, vec3 V, vec2 texcoord) {
  vec3 map = texture(normal_texture, texcoord).xyz;
  map = map * 255. / 127. - 128. / 127.;
  // map.z = sqrt(1. - dot(map.xy, map.xy));
  // map.y = -map.y;
  mat3 TBN = CotangentFrame(N, -V, texcoord);
  return normalize(TBN * map).xzy * vec3(1, -1, -1);
}

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, v_texture_coords);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // Note: PerturbNormal needs the non-normalized view vector
  //       (camera_position - vertex_position).
  vec3 normal =
      PerturbNormal(normalize(v_normal), v_viewvector, v_texture_coords);
  vec4 metallic_roughness =
      texture(metallic_roughness_texture, v_texture_coords);
  float metallic = metallic_roughness.b * frag_info.metallic_factor;
  float roughness = metallic_roughness.g * frag_info.roughness_factor;

  float occlusion = texture(occlusion_texture, v_texture_coords).r;

  vec3 camera_normal = normalize(v_viewvector);

  vec3 reflectance = mix(vec3(0.04), albedo, metallic);

  vec3 reflection_normal = reflect(camera_normal, normal);
  vec3 environment_radiance =
      SampleEnvironmentTexture(radiance_texture, reflection_normal);

  vec3 out_radiance =
      LightFormula(kLightColor, camera_normal, kLightNormal, albedo, normal,
                   metallic, roughness, reflectance);
  out_radiance +=
      LightFormula(kHighlightColor, camera_normal, kHighlightNormal, albedo,
                   normal, metallic, roughness, reflectance);

  vec3 kS = FresnelSchlickRoughness(max(dot(normal, camera_normal), 0.0),
                                    reflectance, roughness);
  vec3 kD = 1.0 - kS;
  vec3 irradiance = SampleEnvironmentTexture(irradiance_texture, normal);
  vec3 diffuse = irradiance * albedo;
  vec3 ambient = (kD * diffuse) * occlusion;

  vec3 out_color = ambient + out_radiance;

  // Tone mapping.
  out_color = vec3(1.0) - exp(-out_color * frag_info.exposure);

#ifndef IMPELLER_TARGET_METAL
  out_color = pow(out_color, vec3(1.0 / kGamma));
#endif

  frag_color =
      // Catch-all for unused uniforms
      vec4(albedo, alpha) + vec4(normal, 1) + vec4(environment_radiance, 1) +
      vec4(ambient, 1) +
      metallic_roughness //
          * frag_info.color * frag_info.exposure * frag_info.metallic_factor *
          frag_info.roughness_factor * frag_info.normal_scale *
          frag_info.occlusion_strength * frag_info.environment_intensity;

  frag_color = vec4(out_color, 1);
}
