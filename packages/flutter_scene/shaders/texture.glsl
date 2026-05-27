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

vec3 SampleEnvironmentTextureLod(sampler2D tex, vec3 direction, float lod) {
  vec2 uv = SphericalToEquirectangular(direction);
  // textureLod is not supported in GLSL ES 1.0. But it doesn't matter anyway,
  // since this function will eventually use `textureCubeLod` once environment
  // maps are fixed.
  //return textureLod(tex, uv, lod).rgb;
  return texture(tex, uv).rgb;
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
/// Prefiltered radiance atlas.
///
/// The specular IBL is sampled from a "PMREM-style" atlas: kPrefilterBands
/// equirectangular bands stacked vertically, band i prefiltered for
/// perceptual roughness i / (kPrefilterBands - 1) (band 0 = mirror, the last
/// band = fully rough). Generated once by flutter_scene_prefilter_env.frag;
/// the layout here must match env_prefilter.dart.
///

const float kPrefilterBands = 8.0;
const float kPrefilterBandHeight = 256.0;
// Keep bilinear taps from bleeding across the seam between bands: clamp the
// in-band V to one texel from each edge.
const float kPrefilterBandEdgeClamp = 1.0 / kPrefilterBandHeight;

// Samples the prefiltered radiance atlas for reflection `direction` at the
// given perceptual `roughness`, interpolating between the two nearest
// bands. Sample the atlas with a horizontal-repeat / vertical-clamp sampler.
//
// `flip_v` (0 or 1) inverts the sampled latitude within each band. The atlas
// is a render-to-texture target; on backends that store render-to-texture
// bottom-up (OpenGL ES, see y_flip.dart), the prefilter's vertex-stage flip
// leaves each band's latitude inverted relative to the lookup, so the caller
// passes 1 there to compensate. 0 on Metal/Vulkan/web (stored top-down).
// Temporary, alongside the rest of the OpenGL ES Y-flip workaround.
vec3 SamplePrefilteredRadiance(sampler2D atlas, vec3 direction, float roughness,
                               float flip_v) {
  vec2 eq = SphericalToEquirectangular(direction);
  if (flip_v > 0.5) {
    eq.y = 1.0 - eq.y;
  }
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
