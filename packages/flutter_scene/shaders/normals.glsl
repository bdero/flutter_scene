//------------------------------------------------------------------------------
/// Normal resolution.
/// See also: http://www.thetenthplanet.de/archives/1180
///

mat3 CotangentFrame(vec3 normal, highp vec3 view_vector, highp vec2 uv) {
  // Get edge vectors of the pixel triangle.
  highp vec3 d_view_x = dFdx(view_vector);
  highp vec3 d_view_y = dFdy(view_vector);
  highp vec2 d_uv_x = dFdx(uv);
  highp vec2 d_uv_y = dFdy(uv);

  // Force the UV derivatives to be non-zero. This is a hack to force correct
  // behavior when UV islands are concentrated to a single point.
  if (length(d_uv_x) == 0.0) {
    d_uv_x = vec2(1.0, 0.0);
  }
  if (length(d_uv_y) == 0.0) {
    d_uv_y = vec2(0.0, 1.0);
  }

  // Solve the linear system.
  highp vec3 view_y_perp = cross(d_view_y, normal);
  highp vec3 view_x_perp = cross(normal, d_view_x);
  highp vec3 T = view_y_perp * d_uv_x.x + view_x_perp * d_uv_y.x;
  highp vec3 B = view_y_perp * d_uv_x.y + view_x_perp * d_uv_y.y;

  // Construct a scale-invariant frame. An edge-on card drives T and B toward
  // zero; if the squared length underflows to zero (or a denormal the GPU
  // flushes to zero inside inversesqrt) the reciprocal is +Inf and 0 * Inf is a
  // NaN normal, which becomes a black specular hole a later gather pass spreads.
  // Floor the length so inversesqrt is always fed a normal, finite value. Any
  // real frame is far above this floor, so this is a no-op for normal shading
  // and only tames the degenerate case, where the tangents stay ~zero and the
  // normal falls back to the geometric normal.
  highp float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
  return mat3(T * invmax, B * invmax, normal);
}

mat3 TangentFrame(vec3 normal, highp vec3 view_vector, highp vec2 uv) {
  vec4 authored = GetWorldTangent();
  highp vec3 tangent = authored.xyz - normal * dot(normal, authored.xyz);
  highp float tangent_length_squared = dot(tangent, tangent);
  if (tangent_length_squared <= 1e-10 || abs(authored.w) < 0.5) {
    return CotangentFrame(normal, view_vector, uv);
  }
  tangent *= inversesqrt(tangent_length_squared);
  vec3 bitangent = normalize(cross(normal, tangent)) * sign(authored.w);
  return mat3(tangent, bitangent, normal);
}

// Samples the normal map at `texcoord` and builds the tangent frame from
// `frame_texcoord`. The two differ under parallax, where the sample is
// displaced but the frame's screen-space derivatives must come from the
// smooth, undisplaced coordinates.
vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, highp vec3 view_vector,
                   highp vec2 texcoord, highp vec2 frame_texcoord,
                   vec2 scale) {
  vec3 map = texture(normal_tex, texcoord).xyz;
  map = map * 255. / 127. - 128. / 127.;
  // map.z = sqrt(1. - dot(map.xy, map.xy));
  // map.y = -map.y;
  // glTF normalScale: attenuate the tangent-plane (xy) components, leaving z, so
  // a scale below 1 flattens the perturbation toward the geometric normal.
  map.xy *= scale;
  mat3 TBN = TangentFrame(normal, -view_vector, frame_texcoord);
  return normalize(TBN * map).xyz;
}

vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, highp vec3 view_vector,
                   highp vec2 texcoord, vec2 scale) {
  return PerturbNormal(normal_tex, normal, view_vector, texcoord, texcoord,
                       scale);
}

vec3 PerturbNormal(sampler2D normal_tex, vec3 normal, highp vec3 view_vector,
                   highp vec2 texcoord, float scale) {
  return PerturbNormal(normal_tex, normal, view_vector, texcoord,
                       vec2(scale));
}

//------------------------------------------------------------------------------
/// Parallax occlusion mapping.
///
/// The height field rides the alpha channel of the normal texture (1 at the
/// surface, 0 at the deepest point), so it costs no sampler. The view ray is
/// marched through `steps` equal depth layers in tangent space until it drops
/// below the height field, and the hit is refined by interpolating between
/// the last two layers. The frame comes from the mesh tangents when present
/// and from screen-space derivatives otherwise, the same as the normal map.
///
/// Returns the offset to add to `uv` (in that same UV space) for every texture
/// lookup of the surface. `scale` is the depth of the height field's 0 level
/// in UV units; the caller skips the call when it is 0.

const int kParallaxMaxSteps = 64;

highp vec2 ParallaxOcclusionOffset(sampler2D height_tex, vec3 normal,
                                   highp vec3 view_vector, highp vec2 uv,
                                   float scale, int steps) {
  mat3 frame = TangentFrame(normal, -view_vector, uv);
  // The derivative frame is only scale-invariant, so unitize before
  // projecting. The floors keep a degenerate frame finite.
  highp vec3 tangent = frame[0];
  highp vec3 bitangent = frame[1];
  tangent *= inversesqrt(max(dot(tangent, tangent), 1e-20));
  bitangent *= inversesqrt(max(dot(bitangent, bitangent), 1e-20));
  highp vec3 view_dir = GetViewDirection();
  highp vec3 view_ts = vec3(dot(view_dir, tangent), dot(view_dir, bitangent),
                            dot(view_dir, normal));
  // A grazing ray travels far across the surface per layer; floor the slope
  // so the march spans a bounded UV distance instead of smearing.
  highp float layer_depth = 1.0 / float(steps);
  highp vec2 delta_uv =
      view_ts.xy / max(view_ts.z, 0.05) * scale * layer_depth;
  // Explicit gradients from the undisplaced coordinates, since an implicit
  // mip selection inside the loop is undefined under divergent control flow.
  highp vec2 dx = dFdx(uv);
  highp vec2 dy = dFdy(uv);
  highp vec2 current_uv = uv;
  highp float current_depth = 0.0;
  highp float surface_depth = 1.0 - textureGrad(height_tex, uv, dx, dy).a;
  highp float previous_depth = 0.0;
  highp float previous_surface_depth = surface_depth;
  // Constant bound with a dynamic break; the loop shape every backend
  // accepts (see SampleShadow for the Direct3D note on early returns).
  for (int i = 0; i < kParallaxMaxSteps; i++) {
    if (i >= steps || current_depth >= surface_depth) break;
    previous_depth = current_depth;
    previous_surface_depth = surface_depth;
    current_uv -= delta_uv;
    current_depth += layer_depth;
    surface_depth = 1.0 - textureGrad(height_tex, current_uv, dx, dy).a;
  }
  // The ray is below the surface at the current layer and above it at the
  // previous one; the crossing is where the two signed distances agree.
  highp float after = surface_depth - current_depth;
  highp float before = previous_surface_depth - previous_depth;
  highp float weight = clamp(after / min(after - before, -1e-6), 0.0, 1.0);
  highp vec2 hit_uv = mix(current_uv, current_uv + delta_uv, weight);
  return hit_uv - uv;
}
