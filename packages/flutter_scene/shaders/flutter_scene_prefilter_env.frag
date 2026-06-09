// Prefilters an equirectangular radiance map into a vertical atlas of
// roughness bands for image-based specular lighting ("PMREM"). Driven by the
// FullscreenVertex shader and rendered once into the atlas when an
// EnvironmentMap is constructed (see env_prefilter.dart). Each output texel
// is GGX-prefiltered for the perceptual roughness of its band.

uniform sampler2D source_equirect;

uniform PrefilterInfo {
  // 1.0 when source_equirect already holds linear radiance (an HDR
  // environment); 0.0 when it is sRGB-encoded and must be linearized.
  float source_is_linear;
}
prefilter_info;

in vec2 v_uv;  // [0, 1]^2 over the whole atlas; v_uv.y = 0 at the top.

out vec4 frag_color;

#include <pbr.glsl>      // kPi, SRGBToLinear
#include <texture.glsl>  // kPrefilterBands, Spherical<->Equirectangular

// Samples the source environment as linear radiance. An sRGB source is
// linearized; an HDR source (source_is_linear) already is linear.
//
// The source equirect image stores +y (up, the north pole) at the top of the
// image (texture V = 0), but SphericalToEquirectangular maps up to V = 1, so
// the source V is flipped here. Without this the prefiltered atlas (and the
// image-based lighting that samples it) comes out vertically inverted: the up
// hemisphere reads the ground and vice versa.
vec3 SampleSourceRadiance(vec3 direction) {
  vec2 uv = SphericalToEquirectangular(direction);
  uv.y = 1.0 - uv.y;
  vec3 c = texture(source_equirect, uv).rgb;
  return prefilter_info.source_is_linear > 0.5 ? c : SRGBToLinear(c);
}

// GGX importance samples accumulated per output texel. Fixed (compile-time)
// so the loop bound is constant. High enough that the per-texel-rotated
// sample set (see main) reads as fine noise rather than visible swirls.
const int kPrefilterSamples = 256;

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

  // Per-texel azimuthal rotation of the importance-sample set. The GGX
  // samples live in a tangent frame that rotates with n, so a fixed
  // sample set leaves a spatially-coherent under-sampling bias that shows
  // up as concentric swirls in the rougher bands. Rotating the set by a
  // per-texel pseudo-random angle decorrelates that bias into fine noise,
  // which the prefilter average then smooths away.
  float jitter = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  vec3 color = vec3(0.0);
  float total_weight = 0.0;
  for (int i = 0; i < kPrefilterSamples; i++) {
    vec2 xi = Hammersley(i, kPrefilterSamples);
    xi.x = fract(xi.x + jitter);
    vec3 h = ImportanceSampleGGX(xi, n, roughness);
    vec3 l = normalize(2.0 * dot(v, h) * h - v);
    float n_dot_l = dot(n, l);
    if (n_dot_l > 0.0) {
      color += SampleSourceRadiance(l) * n_dot_l;
      total_weight += n_dot_l;
    }
  }
  color = total_weight > 0.0 ? color / total_weight : SampleSourceRadiance(n);
  frag_color = vec4(color, 1.0);
}
