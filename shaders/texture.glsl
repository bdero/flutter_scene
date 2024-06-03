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
  return textureLod(tex, uv, lod).rgb;
}
