// Skybox fragment shader for EnvironmentSkySource: samples the scene's
// prefiltered-radiance atlas along the view direction and outputs linear HDR
// radiance. Drawn behind all geometry into the HDR scene-color target;
// exposure and tone mapping are applied later by the resolve pass, so this
// emits linear radiance with premultiplied alpha (the standard material
// output contract).
//
// blurriness acts as a perceptual roughness into the same atlas the specular
// IBL samples, so the background stays consistent with reflections: 0.0 is
// the sharp environment, 1.0 the fully-blurred band.

uniform sampler2D prefiltered_radiance;
uniform samplerCube prefiltered_radiance_cube;
// The secondary cross-fade environment, sampled the same way and mixed toward
// by radiance_blend so the visible sky transitions instead of switching at the
// midpoint. The primary is bound here too when no cross-fade is active (blend
// 0), so this is always a valid sample.
uniform sampler2D prefiltered_radiance_b;
uniform samplerCube prefiltered_radiance_cube_b;
// The full-resolution source equirect of an image environment, sampled
// directly so the visible sky is sharp (decoupled from the small reflection
// cube). A dummy when has_background is 0 (sky-baked environments).
uniform sampler2D environment_background;

uniform SkyboxInfo {
  // 0.0 = sharp, 1.0 = fully blurred.
  float blurriness;
  // Scene.environmentIntensity * Skybox.intensity, so a default skybox
  // matches the brightness of image-based reflections.
  float intensity;
  // 1.0 when environment_background is a real source equirect to sample sharp.
  float has_background;
  // 1.0 when environment_background holds linear radiance; 0.0 when sRGB.
  float source_is_linear;
  // Cross-fade factor toward the secondary environment (0 = primary only).
  float radiance_blend;
}
skybox_info;

in vec3 v_ray;

out vec4 frag_color;

#include <pbr.glsl>      // SRGBToLinear
#include <texture.glsl>  // SampleRadianceEnv, SphericalToEquirectangular

// Blurriness band over which the visible sky hands off from the full-res sharp
// source to the convolved cube. Above it the cube's roughness LOD carries the
// blur, so the mid-range reads as a growing blur instead of a sharp/blurred
// cross-fade.
const float kBackgroundSharpHandoff = 0.15;

void main() {
  vec3 direction = normalize(v_ray);
  float blurriness = clamp(skybox_info.blurriness, 0.0, 1.0);
  // The convolved cube/atlas gives the blurred background (and reflections).
  vec3 blurred = SampleRadianceEnv(
      prefiltered_radiance, prefiltered_radiance_cube, direction, blurriness);

  vec3 radiance;
  if (skybox_info.has_background > 0.5) {
    // Sample the full-res source for a sharp sky, blending toward the cube as
    // blurriness rises (the cube already encodes the roughness blur). The
    // source stores up at the top (V = 0), so flip V to match
    // SphericalToEquirectangular.
    vec2 uv = SphericalToEquirectangular(direction);
    uv.y = 1.0 - uv.y;
    vec3 sharp = texture(environment_background, uv).rgb;
    sharp =
        skybox_info.source_is_linear > 0.5 ? sharp : SRGBToLinear(sharp);
    // Hand off sharp -> cube over the low band, then let the cube's roughness
    // LOD (blurred is sampled at roughness = blurriness) carry the blur. A
    // plain mix by blurriness overlays a crisp and a blurred image across the
    // mid-range, which looks faded rather than blurred.
    float handoff = smoothstep(0.0, kBackgroundSharpHandoff, blurriness);
    radiance = mix(sharp, blurred, handoff);
  } else {
    radiance = blurred;
  }
  // Cross-fade the visible sky toward the secondary environment's cube, so a
  // spatial environment transition fades the background instead of popping at
  // the midpoint (the secondary is static, so its cube is its background).
  if (skybox_info.radiance_blend > 0.0) {
    vec3 blurred_b = SampleRadianceEnv(prefiltered_radiance_b,
        prefiltered_radiance_cube_b, direction, blurriness);
    radiance = mix(radiance, blurred_b, clamp(skybox_info.radiance_blend, 0.0, 1.0));
  }
  frag_color = vec4(radiance * skybox_info.intensity, 1.0);
}
