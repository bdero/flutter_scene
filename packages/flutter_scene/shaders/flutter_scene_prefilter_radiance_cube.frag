// Prefilters an equirectangular radiance source into one face of one roughness
// mip of a radiance cubemap. Driven by FullscreenVertex; the render pass
// selects the target cube face + mip level, and PrefilterCubeInfo supplies that
// face's world basis and the band roughness. Each output texel is
// GGX-prefiltered for the band roughness, sampling the source equirect.
//
// A cubemap output removes the equirect pole singularity from the radiance the
// material samples: reflections read it with a samplerCube, which has uniform
// sample density and no poles. The source is still an equirect (the integral
// averages over a hemisphere, so the source pole bias is smoothed away).

uniform sampler2D source_equirect;

uniform PrefilterCubeInfo {
  // The target cube face's world basis. A texel at v_uv maps to the direction
  // normalize(forward + (2*u-1)*right + (2*v-1)*up), with v measured top-down
  // (FullscreenVertex's v_uv.y = 0 at the top), matching the bound cube face.
  vec4 face_right;
  vec4 face_up;
  vec4 face_forward;
  // Perceptual roughness for this band/mip, in [0, 1].
  float roughness;
  // 1.0 when source_equirect already holds linear radiance; 0.0 when sRGB.
  float source_is_linear;
  // The source equirect's base dimensions and its top mip level. When the
  // source carries a mip chain (source_max_lod > 0) each GGX sample reads it at
  // a level derived from the sample's solid angle, so bright source texels are
  // pre-averaged and the rough bands come out smooth; with no mips
  // (source_max_lod = 0) every sample reads the base level and the firefly clamp
  // below keeps a stray bright texel from dominating.
  float source_width;
  float source_height;
  float source_max_lod;
}
prefilter_cube_info;

in vec2 v_uv;

out vec4 frag_color;

#include <pbr.glsl>      // kPi, SRGBToLinear
#include <texture.glsl>  // SphericalToEquirectangular

const int kPrefilterSamples = 256;

// Van der Corput radical inverse in base 2, float ops only (no integer bit ops,
// which aren't reliable across the GLSL dialects Impeller targets).
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

// The source equirect stores +y (up) at the top (V = 0), but
// SphericalToEquirectangular maps up to V = 1, so flip V here. [lod] selects
// the source mip level (0 = the sharp base); a textureLod with a clamped mip
// filter samples the base when the source has no mip chain.
vec3 SampleSourceRadianceLod(vec3 direction, float lod) {
  vec2 uv = SphericalToEquirectangular(direction);
  uv.y = 1.0 - uv.y;
  vec3 c = textureLod(source_equirect, uv, lod).rgb;
  return prefilter_cube_info.source_is_linear > 0.5 ? c : SRGBToLinear(c);
}

// The GGX normal distribution, for the importance-sample PDF that picks a source
// mip level.
float DistributionGGX(float n_dot_h, float roughness) {
  float a = roughness * roughness;
  float a2 = a * a;
  float d = (n_dot_h * n_dot_h) * (a2 - 1.0) + 1.0;
  return a2 / (kPi * d * d);
}

void main() {
  float fx = v_uv.x * 2.0 - 1.0;
  float fy = v_uv.y * 2.0 - 1.0;
  vec3 n = normalize(prefilter_cube_info.face_forward.xyz +
                     fx * prefilter_cube_info.face_right.xyz +
                     fy * prefilter_cube_info.face_up.xyz);
  // Standard "view == normal" prefiltering assumption.
  vec3 v = n;
  float roughness = prefilter_cube_info.roughness;

  // Per-texel azimuthal rotation of the importance-sample set, decorrelating
  // the under-sampling bias into fine noise the average then smooths.
  float jitter = fract(
      52.9829189 *
      fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

  // Mip selection. Each source texel covers, on average, 4*pi / (W*H)
  // steradians; each GGX sample represents 1 / (N * pdf). Reading the source at
  // the mip whose texel solid angle matches the sample's pre-averages the
  // bright pixels a wide lobe would otherwise undersample. Only meaningful when
  // the source carries a mip chain (source_max_lod > 0); otherwise the lod
  // clamps to 0 and the firefly clamp below does the work.
  float sa_texel = 4.0 * kPi /
      max(prefilter_cube_info.source_width *
              prefilter_cube_info.source_height,
          1.0);

  // Firefly clamp (a belt-and-suspenders fallback, the only defense when the
  // source has no mip chain). Cap each sample's luminance relative to the band
  // center, so a rare spike cannot dominate while a uniformly bright lobe is
  // unaffected. At roughness 0 the lobe is a point, so every sample equals the
  // center and nothing is clamped (the mirror band stays sharp).
  const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);
  vec3 center = SampleSourceRadianceLod(n, 0.0);
  float max_luma = max(dot(center, kLuma), 1.0) * 8.0;

  vec3 color = vec3(0.0);
  float total_weight = 0.0;
  for (int i = 0; i < kPrefilterSamples; i++) {
    vec2 xi = Hammersley(i, kPrefilterSamples);
    xi.x = fract(xi.x + jitter);
    vec3 h = ImportanceSampleGGX(xi, n, roughness);
    vec3 l = normalize(2.0 * dot(v, h) * h - v);
    float n_dot_l = dot(n, l);
    if (n_dot_l > 0.0) {
      float n_dot_h = max(dot(n, h), 1e-4);
      float pdf = DistributionGGX(n_dot_h, roughness) * 0.25 + 1e-4;
      float sa_sample = 1.0 / (float(kPrefilterSamples) * pdf);
      float lod = clamp(0.5 * log2(sa_sample / sa_texel), 0.0,
                        prefilter_cube_info.source_max_lod);
      vec3 s = SampleSourceRadianceLod(l, lod);
      float s_luma = dot(s, kLuma);
      if (s_luma > max_luma) s *= max_luma / s_luma;
      color += s * n_dot_l;
      total_weight += n_dot_l;
    }
  }
  color = total_weight > 0.0 ? color / total_weight : center;
  frag_color = vec4(color, 1.0);
}
