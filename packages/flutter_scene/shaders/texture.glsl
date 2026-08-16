//------------------------------------------------------------------------------
/// Equirectangular projection.
/// See also: https://learnopengl.com/PBR/IBL/Diffuse-irradiance
///

const vec2 kInvAtan = vec2(0.15915494309189535, 0.3183098861837907);

vec2 SphericalToEquirectangular(vec3 direction) {
  // asin is only defined on [-1, 1]; a reflection/normal vector that is a hair
  // over unit length from accumulated float error (or a slightly non-orthonormal
  // environment transform) makes direction.y exceed 1 and asin() return a NaN,
  // which poisons the sampled radiance. Clamp to the domain.
  vec2 uv = vec2(atan(direction.z, direction.x),
                 asin(clamp(direction.y, -1.0, 1.0)));
  uv *= kInvAtan;
  uv += 0.5;
  return uv;
}

vec3 SampleEnvironmentTexture(sampler2D tex, vec3 direction) {
  vec2 uv = SphericalToEquirectangular(direction);
  return texture(tex, uv).rgb;
}

vec3 SampleEnvironmentTextureLod(sampler2D tex, vec3 direction, float lod) {
  vec2 uv = SphericalToEquirectangular(direction);
  // Compiles to texture2DLodEXT (GL_EXT_shader_texture_lod) on the GLES
  // 1.00 dialect; the sampler must use a mipmap min filter for the lod to
  // take effect.
  return textureLod(tex, uv, lod).rgb;
}

// Inverse of SphericalToEquirectangular: maps an equirectangular UV back to
// a unit direction.
vec3 EquirectangularToSpherical(vec2 uv) {
  float phi = (uv.x - 0.5) / kInvAtan.x;  // atan(direction.z, direction.x)
  float lat = (uv.y - 0.5) / kInvAtan.y;  // asin(direction.y)
  float cos_lat = cos(lat);
  return vec3(cos_lat * cos(phi), sin(lat), cos_lat * sin(phi));
}

//------------------------------------------------------------------------------
/// Prefiltered radiance.
///
/// The specular IBL is sampled from a "PMREM-style" prefiltered equirect:
/// kPrefilterBands roughness bands, band i prefiltered for perceptual
/// roughness i / (kPrefilterBands - 1) (band 0 = mirror, the last band =
/// fully rough). Two layouts exist (see env_prefilter.dart, which this must
/// match):
///  * mip layout: one equirect whose mip level i is band i, sampled with
///    textureLod (hardware trilinear between bands).
///  * legacy band atlas: the bands stacked vertically in one texture,
///    sampled with a manual two-band lerp.
///  * cube layout: a roughness-mip cubemap, mip level i is band i, with no
///    pole distortion. Selected by FLUTTER_SCENE_RADIANCE_CUBE, which also
///    picks the prefiltered_radiance sampler type (see RadianceSampler).
/// The engine binds RadianceLayoutInfo alongside the prefiltered_radiance
/// sampler to tell the two 2D layouts apart.
///

const float kPrefilterBands = 8.0;
const float kPrefilterBandHeight = 256.0;
// Keep bilinear taps from bleeding across the seam between bands: clamp the
// in-band V to one texel from each edge (legacy band-atlas layout only).
const float kPrefilterBandEdgeClamp = 1.0 / kPrefilterBandHeight;

// The prefiltered radiance sampler type for the layout this backend builds.
// The engine defines FLUTTER_SCENE_RADIANCE_CUBE on backends that can render
// into mip levels (see EnvironmentMap.effectiveMipRadianceLayout); the rest
// build a 2D equirect. Declaring only one keeps a dead sampler off the
// per-stage texture-unit budget.
//
// TODO(radiance-layout): drop the define and declare both samplers again,
// selecting the layout at runtime, once 3.50 is the oldest supported stable.
// The engine's combined-limit validation
// (https://github.com/flutter/flutter/pull/189332) landed in the 3.49 minor,
// and stables step every third minor, so 3.50 is the first stable carrying
// it. Older engines reject a skinned shadow-casting draw at 16 fragment
// samplers because they compare the running unit index, which starts after
// the vertex stage's, against the per-stage limit. Reverting collapses the
// per-material entry count back by half.
#ifdef FLUTTER_SCENE_RADIANCE_CUBE
#define RadianceSampler samplerCube
#else
#define RadianceSampler sampler2D
#endif

#ifndef FLUTTER_SCENE_RADIANCE_CUBE
// Tells the two 2D layouts apart. The cube variant's bands are always mip
// levels, so it declares neither this block nor the 2D samplers below.
// Leaving them declared keeps a block whose liveness backends disagree on,
// and the engine then has no binding choice that satisfies all of them.
uniform RadianceLayoutInfo {
  // 1.0 when the bound prefiltered_radiance stores its roughness bands as
  // mip levels; 0.0 for the legacy stacked-band atlas.
  float mip_layout;
}
radiance_layout_info;

// Samples a mip-layout prefiltered radiance texture (band i in mip level
// i) for reflection `direction` at the given perceptual `roughness`. The
// sampler must use a linear mip filter for the lod to take effect.
vec3 SamplePrefilteredRadianceLod(sampler2D radiance, vec3 direction,
                                  float roughness) {
  vec2 eq = SphericalToEquirectangular(direction);
  float lod = clamp(roughness, 0.0, 1.0) * (kPrefilterBands - 1.0);
  return textureLod(radiance, eq, lod).rgb;
}

// Samples the prefiltered radiance for reflection `direction` at the given
// perceptual `roughness`, dispatching on the bound texture's layout (see
// RadianceLayoutInfo). Sample with a horizontal-repeat / vertical-clamp
// sampler.
vec3 SamplePrefilteredRadiance(sampler2D atlas, vec3 direction,
                               float roughness) {
  if (radiance_layout_info.mip_layout > 0.5) {
    return SamplePrefilteredRadianceLod(atlas, direction, roughness);
  }
  vec2 eq = SphericalToEquirectangular(direction);
  eq.y = clamp(eq.y, kPrefilterBandEdgeClamp, 1.0 - kPrefilterBandEdgeClamp);
  float band = clamp(roughness, 0.0, 1.0) * (kPrefilterBands - 1.0);
  float b0 = floor(band);
  float b1 = min(b0 + 1.0, kPrefilterBands - 1.0);
  float t = band - b0;
  float v0 = (b0 + eq.y) / kPrefilterBands;
  float v1 = (b1 + eq.y) / kPrefilterBands;
  return mix(texture(atlas, vec2(eq.x, v0)).rgb,
             texture(atlas, vec2(eq.x, v1)).rgb, t);
}

#endif  // FLUTTER_SCENE_RADIANCE_CUBE

// Samples a roughness-mip prefiltered radiance cubemap (mip i = band i) for
// reflection `direction`. The cube has no pole distortion and seamless edges.
vec3 SamplePrefilteredRadianceCube(samplerCube radiance, vec3 direction,
                                   float roughness) {
  float lod = clamp(roughness, 0.0, 1.0) * (kPrefilterBands - 1.0);
  return textureLod(radiance, direction, lod).rgb;
}

// Samples the prefiltered radiance for `direction` at the given perceptual
// `roughness`. FLUTTER_SCENE_RADIANCE_CUBE selects the roughness-mip cubemap
// layout; without it the 2D equirect atlas is read. Only the selected layout's
// sampler is declared, so the other costs no texture unit.
vec3 SampleRadianceEnv(RadianceSampler radiance, vec3 direction,
                       float roughness) {
#ifdef FLUTTER_SCENE_RADIANCE_CUBE
  return SamplePrefilteredRadianceCube(radiance, direction, roughness);
#else
  return SamplePrefilteredRadiance(radiance, direction, roughness);
#endif
}
