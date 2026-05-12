// Prefilters an equirectangular radiance map into a vertical atlas of
// roughness bands for image-based specular lighting ("PMREM"). Driven by the
// FullscreenVertex shader and rendered once into the atlas when an
// EnvironmentMap is constructed (see env_prefilter.dart). Each output texel
// is GGX-prefiltered for the perceptual roughness of its band.

uniform sampler2D source_equirect;

in vec2 v_uv;  // [0, 1]^2 over the whole atlas; v_uv.y = 0 at the top.

out vec4 frag_color;

#include <pbr.glsl>      // kPi, SRGBToLinear
#include <texture.glsl>  // kPrefilterBands, Spherical<->Equirectangular

// GGX importance samples accumulated per output texel. Fixed (compile-time)
// so the loop bound is constant.
const int kPrefilterSamples = 64;

// Van der Corput radical inverse in base 2, computed with float ops only
// (no integer bit operations, which aren't reliably available in the GLSL
// dialects Impeller targets). `i` is an integer-valued float in [0, n).
float RadicalInverseVdC(float i) {
  float result = 0.0;
  float f = 0.5;
  float x = i;
  for (int k = 0; k < 20; k++) {
    result += mod(x, 2.0) * f;
    x = floor(x * 0.5);
    f *= 0.5;
  }
  return result;
}

vec2 Hammersley(int i, int n) {
  return vec2(float(i) / float(n), RadicalInverseVdC(float(i)));
}

// Samples a half-vector from the GGX normal distribution around `n`.
vec3 ImportanceSampleGGX(vec2 xi, vec3 n, float roughness) {
  float a = roughness * roughness;
  float phi = 2.0 * kPi * xi.x;
  float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (a * a - 1.0) * xi.y));
  float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
  vec3 h_tangent =
      vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
  vec3 up = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
  vec3 tangent = normalize(cross(up, n));
  vec3 bitangent = cross(n, tangent);
  return normalize(tangent * h_tangent.x + bitangent * h_tangent.y +
                   n * h_tangent.z);
}

void main() {
  float band_index = floor(v_uv.y * kPrefilterBands);
  float band_v = fract(v_uv.y * kPrefilterBands);
  vec3 n = normalize(EquirectangularToSpherical(vec2(v_uv.x, band_v)));
  // Standard "view == normal" prefiltering assumption.
  vec3 v = n;
  float roughness = band_index / max(kPrefilterBands - 1.0, 1.0);

  vec3 color = vec3(0.0);
  float total_weight = 0.0;
  for (int i = 0; i < kPrefilterSamples; i++) {
    vec3 h = ImportanceSampleGGX(Hammersley(i, kPrefilterSamples), n, roughness);
    vec3 l = normalize(2.0 * dot(v, h) * h - v);
    float n_dot_l = dot(n, l);
    if (n_dot_l > 0.0) {
      color +=
          SRGBToLinear(SampleEnvironmentTexture(source_equirect, l)) * n_dot_l;
      total_weight += n_dot_l;
    }
  }
  color = total_weight > 0.0
              ? color / total_weight
              : SRGBToLinear(SampleEnvironmentTexture(source_equirect, n));
  frag_color = vec4(color, 1.0);
}
