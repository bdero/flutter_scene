// Fragment half of the raw shader pair. Reads the varying the vertex stage
// added and a tint bound to the fragment stage, and outputs linear color
// premultiplied by alpha (the engine resolve pass applies exposure and tone
// mapping).

uniform TintInfo {
  vec4 crest;
  vec4 trough;
}
tint;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector;
in vec2 v_texture_coords;
in vec4 v_color;
in float v_ripple;

out vec4 frag_color;

void main() {
  vec3 normal = normalize(v_normal);
  float facing = clamp(dot(normal, normalize(v_viewvector)), 0.0, 1.0);
  vec3 base = mix(tint.trough.rgb, tint.crest.rgb, v_ripple);
  frag_color = vec4(base * mix(0.35, 1.0, facing), 1.0);
}
