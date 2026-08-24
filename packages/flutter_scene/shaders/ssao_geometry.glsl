// View-space reconstruction shared by the screen-space occlusion shaders.
//
// The including shader must declare the samplers `linear_depth` and
// `depth_mip1`..`depth_mip3`, and define AO_INFO as the uniform block instance
// whose `proj.xy` holds the half-fov tangents.

// Fetches the view-space depth at [uv] from level [level] of the depth chain.
float DepthAtLevel(vec2 uv, int level) {
  if (level <= 0) return texture(linear_depth, uv).r;
  if (level == 1) return texture(depth_mip1, uv).r;
  if (level == 2) return texture(depth_mip2, uv).r;
  return texture(depth_mip3, uv).r;
}

// Reconstructs a view-space position from a depth-buffer UV. Camera space
// places the eye at the origin looking down +Z (the convention the depth
// prepass writes), so the stored planar depth is the view-space Z and the
// X/Y follow from the projection tangents.
vec3 ViewPositionAt(vec2 uv, int level) {
  float z = DepthAtLevel(uv, level);
  // NDC from the full-screen UV (V runs downward in the UV).
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  return vec3(ndc.x * z * AO_INFO.proj.x, ndc.y * z * AO_INFO.proj.y, z);
}

vec3 ViewPositionBase(ivec2 coord) {
  ivec2 size = textureSize(linear_depth, 0);
  coord = clamp(coord, ivec2(0), size - ivec2(1));
  float z = texelFetch(linear_depth, coord, 0).r;
  vec2 uv = (vec2(coord) + vec2(0.5)) / vec2(size);
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  return vec3(ndc.x * z * AO_INFO.proj.x, ndc.y * z * AO_INFO.proj.y, z);
}

// Reconstructs the view-space geometric normal from linear depth.
// Uses smooth central differences on continuous surfaces, avoiding the
// alternating one-sided derivative switching that produces screen-space
// grid and rectangular self-occlusion artifacts. Falls back to the smaller
// one-sided derivative only across true geometric silhouette edges.
vec3 ReconstructNormal(vec2 uv, vec3 center) {
  ivec2 size = textureSize(linear_depth, 0);
  ivec2 p = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
  vec3 center_sample = ViewPositionBase(p);
  vec3 left = ViewPositionBase(p - ivec2(1, 0));
  vec3 right = ViewPositionBase(p + ivec2(1, 0));
  vec3 top = ViewPositionBase(p - ivec2(0, 1));
  vec3 bottom = ViewPositionBase(p + ivec2(0, 1));

  float dl = abs(center_sample.z - left.z);
  float dr = abs(right.z - center_sample.z);
  vec3 dx;
  if (p.x == 0) {
    dx = right - center_sample;
  } else if (p.x == size.x - 1) {
    dx = center_sample - left;
  } else if (abs(dl - dr) < 0.02 * max(center_sample.z, 0.1)) {
    dx = (right - left) * 0.5;
  } else {
    dx = dl < dr ? (center_sample - left) : (right - center_sample);
  }

  float dt = abs(center_sample.z - top.z);
  float db = abs(bottom.z - center_sample.z);
  vec3 dy;
  if (p.y == 0) {
    dy = bottom - center_sample;
  } else if (p.y == size.y - 1) {
    dy = center_sample - top;
  } else if (abs(dt - db) < 0.02 * max(center_sample.z, 0.1)) {
    dy = (bottom - top) * 0.5;
  } else {
    dy = dt < db ? (center_sample - top) : (bottom - center_sample);
  }

  vec3 normal = normalize(cross(dx, dy));
  return dot(normal, center) > 0.0 ? -normal : normal;
}
