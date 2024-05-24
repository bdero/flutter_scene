uniform FragInfo {
  vec4 color;
  float vertex_color_weight;
}
frag_info;

uniform sampler2D base_color_texture;
uniform sampler2D metallic_roughness_texture;
uniform sampler2D normal_texture;

in vec3 v_position;
in vec3 v_normal;
in vec3 v_viewvector; // camera pos - vertex pos
in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

mat3 CotangentFrame(vec3 N, vec3 p, vec2 uv) {
  // From http://www.thetenthplanet.de/archives/1180
  vec3 dp1 = dFdx(p);
  vec3 dp2 = dFdy(p);
  vec2 duv1 = dFdx(uv);
  vec2 duv2 = dFdy(uv);
  vec3 dp2perp = cross(dp2, N);
  vec3 dp1perp = cross(N, dp1);
  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
  float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
  return mat3(T * invmax, B * invmax, N);
}

vec3 PerturbNormal(vec3 N, vec3 V, vec2 texcoord) {
  // From http://www.thetenthplanet.de/archives/1180
  vec3 map = texture(normal_texture, texcoord).xyz;
  map.z = sqrt(1. - dot(map.xy, map.xy));
  // map.y = -map.y;
  mat3 TBN = CotangentFrame(N, -V, texcoord);
  return normalize(TBN * map);
}

void main() {
  vec4 vertex_color = mix(vec4(1), v_color, frag_info.vertex_color_weight);
  frag_color = texture(base_color_texture, v_texture_coords) * vertex_color *
               frag_info.color;
  vec3 normal =
      PerturbNormal(normalize(v_normal), v_viewvector, v_texture_coords);
  frag_color.rgb = normal;
}
