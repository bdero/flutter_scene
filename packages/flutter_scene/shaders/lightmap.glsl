// The baked lightmap a lit material can carry, declared only in the entries
// built with FLUTTER_SCENE_LIGHTMAP. Those entries replace the SH diffuse
// ambient with this sampled radiance, so the lightmap sampler displaces
// sh_coefficients instead of extending the set (see the sampler budget in the
// contributor notes). Specular image-based lighting is untouched.
//
// Requires material_inputs.glsl (MaterialTextureUv) and the packed UV
// varyings, so it is included from material_lighting.glsl.

#ifdef FLUTTER_SCENE_LIGHTMAP
// Baked indirect diffuse radiance. Read as linear radiance unless the RGBM
// flag is set; a lightmap that carries no bake is a black placeholder.
uniform sampler2D lightmap_texture;

uniform LightmapInfo {
  // xy offset, zw scale, the same packing the material texture transforms use.
  vec4 transform;
  // x cos and y sin of the rotation, z the UV set, w the RGBM decode flag.
  vec4 rotation;
  // x scales the decoded radiance.
  vec4 params;
}
lightmap_info;

// The baked indirect diffuse radiance at this fragment, in linear space.
vec3 BakedDiffuseRadiance() {
  vec4 baked = texture(
      lightmap_texture,
      MaterialTextureUv(lightmap_info.transform, lightmap_info.rotation));
  // RGBM packs an HDR value into an LDR image, the shared multiplier in the
  // alpha channel. Off by default; the plain path reads the texture as linear
  // radiance already.
  vec3 radiance = lightmap_info.rotation.w > 0.5
                      ? baked.rgb * pow(baked.a, 2.2) * 34.4932
                      : baked.rgb;
  return radiance * lightmap_info.params.x;
}
#endif
