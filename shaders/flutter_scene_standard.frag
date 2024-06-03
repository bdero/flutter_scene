uniform FragInfo {
  vec4 color;
  vec4 emissive_factor;
  float vertex_color_weight;
  float exposure;
  float metallic_factor;
  float roughness_factor;
  float has_normal_map;
  float normal_scale;
  float occlusion_strength;
  float environment_intensity;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D emissive_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;
uniform sampler2D occlusion_texture;

uniform sampler2D radiance_texture;
uniform sampler2D irradiance_texture;

uniform sampler2D brdf_lut;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

#include <normals.glsl>
#include <pbr.glsl>
#include <texture.glsl>

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  vec4 base_color_srgb = texture(base_color_texture, v_texture_coords);
  vec3 albedo = SRGBToLinear(base_color_srgb.rgb) * vertex_color.rgb *
                frag_info.color.rgb;
  float alpha = base_color_srgb.a * vertex_color.a * frag_info.color.a;
  // Note: PerturbNormal needs the non-normalized view vector
  //       (camera_position - vertex_position).
  vec3 normal = normalize(v_normal);
  if (frag_info.has_normal_map > 0.5) {
    normal =
        PerturbNormal(normal_texture, normal, v_viewvector, v_texture_coords);
  }

  vec4 metallic_roughness =
      texture(metallic_roughness_texture, v_texture_coords);
  float metallic = metallic_roughness.b * frag_info.metallic_factor;
  float roughness = metallic_roughness.g * frag_info.roughness_factor;

  float occlusion = texture(occlusion_texture, v_texture_coords).r;
  occlusion = 1.0 - (1.0 - occlusion) * frag_info.occlusion_strength;

  vec3 camera_normal = normalize(v_viewvector);

  vec3 reflectance = mix(vec3(0.04), albedo, metallic);

  vec3 reflection_normal = reflect(camera_normal, normal);

  vec3 fresnel = FresnelSchlickRoughness(max(dot(normal, camera_normal), 0.0),
                                         reflectance, roughness);
  vec3 kS = fresnel;
  vec3 kD = 1.0 - kS;
  kD *= 1.0 - metallic;
  vec3 irradiance = SampleEnvironmentTexture(irradiance_texture, normal) *
                    frag_info.environment_intensity;
  vec3 diffuse = irradiance * albedo;

  const float kMaxReflectionLod = 4.0;
  vec3 prefiltered_color =
      SampleEnvironmentTextureLod(radiance_texture, reflection_normal,
                                  roughness * kMaxReflectionLod)
          .rgb *
      frag_info.environment_intensity;
  vec2 environment_brdf =
      texture(brdf_lut, vec2(max(dot(normal, camera_normal), 0.0), roughness))
          .rg;
  vec3 specular =
      prefiltered_color * (fresnel * environment_brdf.x + environment_brdf.y);

  vec3 ambient = (kD * diffuse + specular) * occlusion;

  vec3 emissive = texture(emissive_texture, v_texture_coords).rgb *
                  frag_info.emissive_factor.rgb;

  vec3 out_color = ambient + emissive;

  // Tone mapping.
  out_color = vec3(1.0) - exp(-out_color * frag_info.exposure);

#ifndef IMPELLER_TARGET_METAL
  out_color = pow(out_color, vec3(1.0 / kGamma));
#endif

  // // Catch-all for unused uniforms (useful when debugging because unused
  // //uniforms are automatically culled from the shader).
  // frag_color =
  //     vec4(albedo, alpha) + vec4(normal, 1) + vec4(ambient, 1) +
  //     vec4(emissive, 1) +
  //     metallic_roughness //
  //         * frag_info.color * frag_info.emissive_factor * frag_info.exposure
  //         * frag_info.metallic_factor * frag_info.roughness_factor *
  //         frag_info.normal_scale * frag_info.occlusion_strength *
  //         frag_info.environment_intensity;

  frag_color = vec4(out_color, 1) * alpha;
}
