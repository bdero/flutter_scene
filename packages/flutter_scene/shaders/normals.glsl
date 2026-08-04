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

  // Construct a scale-invariant frame. An edge-on card drives T and B toward
  // zero; if the squared length underflows to zero (or a denormal the GPU
  // flushes to zero inside inversesqrt) the reciprocal is +Inf and 0 * Inf is a
  // NaN normal, which becomes a black specular hole a later gather pass spreads.
  // Floor the length so inversesqrt is always fed a normal, finite value. Any
  // real frame is far above this floor, so this is a no-op for normal shading
  // and only tames the degenerate case, where the tangents stay ~zero and the
  // normal falls back to the geometric normal.
  float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
  return mat3(T * invmax, B * invmax, normal);
}

mat3 TangentFrame(vec3 normal, vec3 view_vector, vec2 uv) {
  vec4 authored = GetWorldTangent();
  vec3 tangent = authored.xyz - normal * dot(normal, authored.xyz);
  float tangent_length_squared = dot(tangent, tangent);
  if (tangent_length_squared <= 1e-10 || abs(authored.w) < 0.5) {
    return CotangentFrame(normal, view_vector, uv);
  }
  tangent *= inversesqrt(tangent_length_squared);
  vec3 bitangent = normalize(cross(normal, tangent)) * sign(authored.w);
  return mat3(tangent, bitangent, normal);
}

vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, vec3 view_vector,
                   vec2 texcoord, vec2 scale) {
  vec3 map = texture(normal_tex, texcoord).xyz;
  map = map * 255. / 127. - 128. / 127.;
  // map.z = sqrt(1. - dot(map.xy, map.xy));
  // map.y = -map.y;
  // glTF normalScale: attenuate the tangent-plane (xy) components, leaving z, so
  // a scale below 1 flattens the perturbation toward the geometric normal.
  map.xy *= scale;
  mat3 TBN = TangentFrame(normal, -view_vector, texcoord);
  return normalize(TBN * map).xyz;
}

vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, vec3 view_vector,
                   vec2 texcoord, float scale) {
  return PerturbNormal(normal_tex, normal, view_vector, texcoord,
                       vec2(scale));
}
