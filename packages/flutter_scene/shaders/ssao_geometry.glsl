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

// Selects the smoother one-sided derivative on each axis. This avoids joining
// foreground and background positions at silhouettes, while retaining fp32
// position differences across broad sloped surfaces.
vec3 ReconstructNormal(vec2 uv, vec3 center) {
  ivec2 size = textureSize(linear_depth, 0);
  ivec2 p = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
  vec3 center_sample = ViewPositionBase(p);
  vec3 left = ViewPositionBase(p - ivec2(1, 0));
  vec3 right = ViewPositionBase(p + ivec2(1, 0));
  vec3 down = ViewPositionBase(p - ivec2(0, 1));
  vec3 up = ViewPositionBase(p + ivec2(0, 1));
  vec3 dx;
  if (p.x == 0) {
    dx = right - center_sample;
  } else if (p.x == size.x - 1) {
    dx = center_sample - left;
  } else {
    dx = length(center_sample - left) < length(right - center_sample)
        ? center_sample - left
        : right - center_sample;
  }
  vec3 dy;
  if (p.y == 0) {
    dy = up - center_sample;
  } else if (p.y == size.y - 1) {
    dy = center_sample - down;
  } else {
    dy = length(center_sample - down) < length(up - center_sample)
        ? center_sample - down
        : up - center_sample;
  }
  vec3 normal = normalize(cross(dx, dy));
  return dot(normal, center) > 0.0 ? -normal : normal;
}
