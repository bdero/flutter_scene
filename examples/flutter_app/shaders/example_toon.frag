// Toon fragment shader for the flutter_scene example app.
//
// Consumes the engine's standard vertex outputs (see MATERIALS.md)
// and produces banded N.L diffuse plus a Fresnel-style rim term.
// Drives every parameter from a single uniform block bound by name
// from the Dart side as `ToonInfo`.

uniform ToonInfo {
  // Tint multiplied with the texture sample. Alpha drives output alpha.
  vec4 base_color;
  // Color of the rim term. Alpha unused but kept for std140 alignment.
  vec4 rim_color;
  // World-space light direction (xyz). w is unused padding.
  vec4 light_direction;
  // Number of bands in the N.L term (1 = unlit, higher = more steps).
  float band_count;
  // Strength of the rim term.
  float rim_strength;
  // Rim falloff: smaller = thinner rim.
  float rim_width;
  // Ambient lighting contribution.
  float ambient;
}
// NOTE: the instance name has to fold (case- and underscore-insensitive)
// to the block name `ToonInfo` so Impeller's GLES backend can resolve
// the decomposed struct members. See flutter/flutter#186394.
toon_info;

uniform sampler2D base_color_texture;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector;
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

void main() {
  vec3 normal = normalize(v_normal);
  vec3 light_dir = normalize(toon_info.light_direction.xyz);
  vec3 view_dir = normalize(v_viewvector);

  // Banded N dot L. floor() quantizes the diffuse term into bands.
  float n_dot_l = max(dot(normal, light_dir), 0.0);
  float bands = max(toon_info.band_count, 1.0);
  float banded = floor(n_dot_l * bands + 0.001) / bands;

  // Rim term: bright when the surface is grazing.
  float n_dot_v = max(dot(normal, view_dir), 0.0);
  float rim = 1.0 - n_dot_v;
  rim = smoothstep(1.0 - toon_info.rim_width, 1.0, rim) * toon_info.rim_strength;

  vec4 albedo_sample = texture(base_color_texture, v_texture_coords);
  vec3 albedo = toon_info.base_color.rgb * albedo_sample.rgb * v_color.rgb;

  vec3 lit = albedo * (toon_info.ambient + banded * (1.0 - toon_info.ambient));
  vec3 final_color = lit + toon_info.rim_color.rgb * rim;

  float alpha = toon_info.base_color.a * albedo_sample.a * v_color.a;
  frag_color = vec4(final_color, 1.0) * alpha;
}
