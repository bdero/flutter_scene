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
  // The roughness band to compute this pass, or a negative value to compute
  // the whole atlas in one pass. Band mode discards every texel outside the
  // band before the expensive sample loop, so an incremental bake (one band
  // per frame, LoadAction.load preserving the others) costs roughly
  // 1/kPrefilterBands of the full pass.
  float band_index;
  // 1.0 when the render target is a single band covering the whole target
  // (the mip layout: the pass renders band_index into one mip level of an
  // equirect, so there is no atlas math and no discard). band_index must
  // be non-negative in this mode.
  float whole_target;
  // 1.0 to compute every band at roughness 0 (the mirror), which the delta
  // lobe answers in one fetch. A progressive fill seeds the whole atlas with
  // this before pacing the real bands, so a frame that samples the atlas
  // while it is still filling reads the environment rather than the clear
  // color. Each paced band then overwrites its seed.
  float force_mirror;
}
prefilter_info;

in vec2 v_uv;  // [0, 1]^2 over the whole atlas; v_uv.y = 0 at the top.

out vec4 frag_color;

#include <pbr.glsl>      // kPi, SRGBToLinear
// Equirect helpers only; the radiance block would be declared unread.
#define FLUTTER_SCENE_NO_ENGINE_RADIANCE
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

// The i'th point of a rank-1 lattice: stratified in x, and in y the
// golden-ratio (Kronecker) sequence, whose discrepancy matches the Hammersley
// set this replaces. Two multiplies instead of a 20-iteration float emulation
// of a base-2 radical inverse, which the integer bit operations missing from
// the GLSL dialects Impeller targets would otherwise need. That loop cost more
// than the texture fetch it fed.
//
// highp is required, not decorative: the y term grows to ~158 by the last
// sample, where fp16's 10-bit mantissa cannot resolve the fractional part at
// all and every sample would collapse onto the same few directions.
const highp float kGoldenRatioConjugate = 0.6180339887498949;

vec2 LatticePoint(int i, int n) {
  highp float kronecker = 0.5 + float(i) * kGoldenRatioConjugate;
  return vec2(float(i) / float(n), fract(kronecker));
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
  float band_index;
  float band_v;
  if (prefilter_info.whole_target > 0.5) {
    band_index = prefilter_info.band_index;
    band_v = v_uv.y;
  } else {
    band_index = floor(v_uv.y * kPrefilterBands);
    if (prefilter_info.band_index >= 0.0 &&
        band_index != prefilter_info.band_index) {
      discard;
    }
    band_v = fract(v_uv.y * kPrefilterBands);
  }
  vec3 n = normalize(EquirectangularToSpherical(vec2(v_uv.x, band_v)));
  // Standard "view == normal" prefiltering assumption.
  vec3 v = n;
  float roughness = prefilter_info.force_mirror > 0.5
                        ? 0.0
                        : band_index / max(kPrefilterBands - 1.0, 1.0);

  // Per-texel azimuthal rotation of the importance-sample set. The GGX
  // samples live in a tangent frame that rotates with n, so a fixed
  // sample set leaves a spatially-coherent under-sampling bias that shows
  // up as concentric swirls in the rougher bands. Rotating the set by a
  // per-texel pseudo-random angle decorrelates that bias into fine noise,
  // which the prefilter average then smooths away.
  float jitter = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  // Firefly suppression: cap each sample's luminance relative to the band
  // center, so a rare bright source spike in a wide rough lobe cannot leave a
  // sharp bright block. A uniformly bright lobe is unaffected, and roughness 0
  // self-disables (every sample equals the center). Mirrors the cube prefilter.
  const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);
  vec3 center = SampleSourceRadiance(n);
  // The mirror band is the source itself: at roughness 0 the GGX lobe is a
  // delta, so every one of the samples below would read exactly the center.
  // Taking it directly is the same answer for 1/256th of the work.
  if (roughness <= 0.0) {
    frag_color = vec4(center, 1.0);
    return;
  }
  float max_luma = max(dot(center, kLuma), 1.0) * 8.0;

  vec3 color = vec3(0.0);
  float total_weight = 0.0;
  for (int i = 0; i < kPrefilterSamples; i++) {
    vec2 xi = LatticePoint(i, kPrefilterSamples);
    xi.x = fract(xi.x + jitter);
    vec3 h = ImportanceSampleGGX(xi, n, roughness);
    vec3 l = normalize(2.0 * dot(v, h) * h - v);
    float n_dot_l = dot(n, l);
    if (n_dot_l > 0.0) {
      vec3 s = SampleSourceRadiance(l);
      float s_luma = dot(s, kLuma);
      if (s_luma > max_luma) s *= max_luma / s_luma;
      color += s * n_dot_l;
      total_weight += n_dot_l;
    }
  }
  color = total_weight > 0.0 ? color / total_weight : center;
  frag_color = vec4(color, 1.0);
}
