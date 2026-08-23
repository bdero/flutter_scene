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

// Samples an equirect along a view direction, choosing the mip level from the
// projection's own geometry rather than from the UV's screen derivatives.
//
// Letting the hardware pick gets it wrong at both singularities of the
// projection, and both are visible:
//
//   * **The seam.** Longitude wraps, so U jumps a whole period where the
//     panorama joins. The quad straddling that jump measures a footprint the
//     width of the entire texture and selects the top of the mip chain, which
//     is the average of the whole sky. It prints as a one pixel bright line
//     from pole to pole.
//
//   * **The poles.** An equirect's texels are slivers 1/cos(latitude) wide, so
//     approaching a pole one row of them fans out over the whole sky. The
//     correct footprint there spans MANY columns, and a screen-space difference
//     of a rapidly-turning atan2 across a 2x2 quad badly underestimates it. The
//     level that gets picked is too fine, so instead of the row's average the
//     pole shows a handful of its columns splayed into wedges.
//
// The footprint is analytic instead. For a screen pixel covering `w` radians,
// the region it maps to spans `w` of latitude and `w / cos(latitude)` of
// longitude, which is exactly the 1/cos blow-up the hardware misses. Feeding
// that as an explicit gradient pair makes the pole resolve to the average of
// however many columns really collapse into the pixel (smooth, and progressively
// smoother toward the pole) and leaves the seam with the footprint it actually
// has (small).
//
// `direction` must be normalised. Its derivatives are used rather than the UV's
// because the direction is continuous everywhere, including across the seam.
//
// Any equirect read with an implicit mip level needs this. A texture with no
// mip chain hides the seam half of it, which is how it survives being written
// the obvious way.
vec3 SampleEquirectByFootprint(sampler2D tex, vec3 direction, vec2 uv) {
  // Radians per pixel, from the direction itself: for a unit vector the chord
  // and the angle agree to first order.
  float w = max(length(dFdx(direction)), length(dFdy(direction)));
  // Guarded, because at the exact pole this is zero and the longitude span is
  // the whole circle; the clamp lands the level at the top of the chain, which
  // is the row average, which is the right answer there.
  float cos_lat = max(sqrt(max(1.0 - direction.y * direction.y, 0.0)), 1e-4);
  return textureGrad(tex, uv, vec2(w * kInvAtan.x / cos_lat, 0.0),
                     vec2(0.0, w * kInvAtan.y))
      .rgb;
}

vec3 SampleEnvironmentTexture(sampler2D tex, vec3 direction) {
  return SampleEquirectByFootprint(tex, direction,
                                   SphericalToEquirectangular(direction));
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
