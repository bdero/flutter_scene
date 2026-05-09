//------------------------------------------------------------------------------
/// Normal resolution.
/// See also: http://www.thetenthplanet.de/archives/1180
///

mat3 CotangentFrame(vec3 normal, vec3 view_vector, vec2 uv) {
  // Get edge vectors of the pixel triangle.
  vec3 d_view_x = dFdx(view_vector);
  vec3 d_view_y = dFdy(view_vector);
  vec2 d_uv_x = dFdx(uv);
  vec2 d_uv_y = dFdy(uv);

  // Force the UV derivatives to be non-zero. This is a hack to force correct
  // behavior when UV islands are concentrated to a single point.
  if (length(d_uv_x) == 0.0) {
    d_uv_x = vec2(1.0, 0.0);
  }
  if (length(d_uv_y) == 0.0) {
    d_uv_y = vec2(0.0, 1.0);
  }

  // Solve the linear system.
  vec3 view_y_perp = cross(d_view_y, normal);
  vec3 view_x_perp = cross(normal, d_view_x);
  vec3 T = view_y_perp * d_uv_x.x + view_x_perp * d_uv_y.x;
  vec3 B = view_y_perp * d_uv_x.y + view_x_perp * d_uv_y.y;

  // Construct a scale-invariant frame.
  float invmax = inversesqrt(max(dot(T, T), dot(B, B)));
  return mat3(T * invmax, B * invmax, normal);
}

vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, vec3 view_vector,
                   vec2 texcoord) {
  vec3 map = texture(normal_tex, texcoord).xyz;
  map = map * 255. / 127. - 128. / 127.;
  // map.z = sqrt(1. - dot(map.xy, map.xy));
  // map.y = -map.y;
  mat3 TBN = CotangentFrame(normal, -view_vector, texcoord);
  return normalize(TBN * map).xyz;
}
