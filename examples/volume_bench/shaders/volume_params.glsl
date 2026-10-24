// The parameters every variant shares. Volume coordinates (uvw) span [0, 1]
// across the volume, with voxel centers at (index + 0.5) / dims.

uniform BenchParams {
  // Width, height and depth in voxels.
  vec4 dims;
  // Reslice: the plane's uvw at the viewport's bottom left, and its extent
  // across the viewport's width and height.
  vec4 plane_origin;
  vec4 plane_u;
  vec4 plane_v;
  // MIP: the camera in uvw space; right and up are scaled by the half field
  // of view.
  vec4 camera_position;
  vec4 camera_forward;
  vec4 camera_right;
  vec4 camera_up;
  // x: the most ray-march steps, y: the step length in uvw.
  vec4 march;
  // Atlas layout: slices per page row, slices per page, tile width in
  // texels (two voxels each), tile height.
  vec4 atlas;
}
params;
