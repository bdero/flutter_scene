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

uniform SkyboxInfo {
  // 0.0 = sharp, 1.0 = fully blurred.
  float blurriness;
  // Scene.environmentIntensity * Skybox.intensity, so a default skybox
  // matches the brightness of image-based reflections.
  float intensity;
  float _pad0;
  float _pad1;
}
skybox_info;

in vec3 v_ray;

out vec4 frag_color;

#include <texture.glsl>  // SamplePrefilteredRadiance

void main() {
  vec3 direction = normalize(v_ray);
  vec3 radiance =
      SamplePrefilteredRadiance(prefiltered_radiance, direction,
                                clamp(skybox_info.blurriness, 0.0, 1.0));
  frag_color = vec4(radiance * skybox_info.intensity, 1.0);
}
