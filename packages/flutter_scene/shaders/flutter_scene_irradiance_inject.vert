// Scatters one texel of the downsampled depth-normal buffer into one probe of
// the cage that encloses it.
//
// Each instance is one (screen texel, cage corner) pair: the corner arrives as
// a uniform and one draw covers all eight, so the instance stream is just the
// texel index. The stage reconstructs the texel's world position and normal
// from the depth prepass, finds the enclosing probe cell, and emits a quad
// over the octahedral texels the sample can inform. The fragment stage does
// the per-texel cosine weighting and blends additively into the accumulator.
//
// The accumulator holds one tile per probe and nothing else, so a fragment
// recovers its tile from `gl_FragCoord` alone.

#include <irradiance_field.glsl>

uniform InjectInfo {
  // xy: the depth-normal buffer's size in texels. zw: its reciprocal.
  vec4 source_size;
  // x/y: tangents of the half horizontal/vertical field of view. z: the far
  // plane, past which a texel is background. w: the firefly luminance clamp.
  vec4 proj;
  // xyz: world-space camera position. w: the emissive injection boost.
  vec4 camera_position;
  vec4 camera_right;
  vec4 camera_up;
  vec4 camera_forward;
  // xyz: world-space probe spacing. w: the distance normalization
  // (1.5 cell diagonals), so stored moments stay inside fp16's good range.
  vec4 grid_spacing;
  // xyz: lattice index of the volume's minimum-corner probe.
  vec4 grid_anchor;
  // xyz: probe counts per axis. w: probe tiles per accumulator row.
  vec4 grid_counts;
  // x: stored tile edge. y: interior edge. z: texel radius the quad covers
  // around the sample's own texel, or a negative value to cover the whole
  // interior. w: unused.
  vec4 tile;
  // xy: accumulator size in texels. zw: its reciprocal.
  vec4 target;
  // xyz: this draw's cage corner, 0 or 1 per axis.
  vec4 cage;
}
info;

// The depth prepass' linear depth (r), octahedral view normal (gb), and
// roughness (a).
uniform highp sampler2D linear_depth_normal;
// The previous frame's lit scene color, the radiance this scatter carries.
uniform highp sampler2D scene_radiance;

// Slot 0, the unit quad, corners in [0, 1].
in vec2 corner;
// Slot 1 (instance rate), this instance's texel index into the depth-normal
// buffer.
in float texel_index;

// The direction from the probe toward the sample, and the sample's distance
// normalized by the probe's maximum recorded distance.
out vec4 v_sample;
// The sample's outgoing radiance.
out vec3 v_radiance;
// The trilinear cage weight times the sample's facing term. The fragment
// stage multiplies in the per-texel lobe.
out float v_weight;

// Decodes the depth prepass' view-space normal. That encoding leaves the
// octahedral components in [-1, 1] rather than remapping them, so it needs
// its own decode rather than ProbeOctDecode.
vec3 DecodeViewNormal(vec2 e) {
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * ProbeOctSign(n.xy);
  }
  return normalize(n);
}

void cull() {
  // Behind the near plane in clip space, so the whole primitive is clipped.
  gl_Position = vec4(0.0, 0.0, 2.0, 1.0);
  v_sample = vec4(0.0, 0.0, 1.0, 1.0);
  v_radiance = vec3(0.0);
  v_weight = 0.0;
}

void main() {
  float row = floor((texel_index + 0.5) * info.source_size.z);
  float column = texel_index - row * info.source_size.x;
  vec2 uv = (vec2(column, row) + vec2(0.5)) * info.source_size.zw;

  vec4 depth_normal = textureLod(linear_depth_normal, uv, 0.0);
  float depth = depth_normal.r;
  if (depth <= 0.0 || depth >= info.proj.z) {
    cull();
    return;
  }

  // The prepass writes planar view depth with the eye at the origin looking
  // down +z, so the lateral offsets follow from the projection tangents.
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  vec3 view_position = vec3(ndc.x * depth * info.proj.x,
                            ndc.y * depth * info.proj.y, depth);
  vec3 world_position = info.camera_position.xyz +
                        info.camera_right.xyz * view_position.x +
                        info.camera_up.xyz * view_position.y +
                        info.camera_forward.xyz * view_position.z;
  vec3 view_normal = DecodeViewNormal(depth_normal.gb);
  vec3 world_normal = normalize(info.camera_right.xyz * view_normal.x +
                                info.camera_up.xyz * view_normal.y +
                                info.camera_forward.xyz * view_normal.z);

  vec3 lattice = world_position / info.grid_spacing.xyz;
  vec3 base = floor(lattice);
  vec3 alpha = clamp(lattice - base, 0.0, 1.0);
  vec3 probe_lattice = base + info.cage.xyz;

  // A cage corner outside the volume has no probe to write.
  vec3 relative = probe_lattice - info.grid_anchor.xyz;
  if (any(lessThan(relative, vec3(0.0))) ||
      any(greaterThanEqual(relative, info.grid_counts.xyz))) {
    cull();
    return;
  }

  vec3 trilinear = max(mix(vec3(1.0) - alpha, alpha, info.cage.xyz),
                       vec3(0.001));
  float weight = trilinear.x * trilinear.y * trilinear.z;

  vec3 probe_position = probe_lattice * info.grid_spacing.xyz;
  vec3 to_sample = world_position - probe_position;
  float distance_to_sample = length(to_sample);
  vec3 direction = distance_to_sample > 1e-5
      ? to_sample / distance_to_sample
      : world_normal;
  // A surface facing away from the probe is not what the probe sees in this
  // direction, so it fades out rather than contributing.
  weight *= max(0.0, dot(-direction, world_normal));
  if (weight <= 0.0) {
    cull();
    return;
  }

  float probe_index = ProbeLinearIndex(
      ProbeWrapSlot(probe_lattice, info.grid_counts.xyz), info.grid_counts.xyz);
  vec2 tile_origin =
      ProbeTileOrigin(probe_index, info.grid_counts.w, 0.0, info.tile.x);

  vec2 interior_low = tile_origin + vec2(1.0);
  vec2 interior_high = interior_low + vec2(info.tile.y);
  vec2 low = interior_low;
  vec2 high = interior_high;
  if (info.tile.z >= 0.0) {
    // A sharply peaked lobe only reaches a few texels, so cover a box around
    // the sample's own texel instead of the whole interior.
    vec2 center = interior_low + clamp(ProbeOctEncode(direction), 0.0, 1.0) *
                                     info.tile.y;
    low = clamp(floor(center) - vec2(info.tile.z), interior_low, interior_high);
    high = clamp(floor(center) + vec2(info.tile.z + 1.0), interior_low,
                 interior_high);
  }

  vec2 position = mix(low, high, corner);
  // Offscreen targets are stored top-down on every backend, so clip-space
  // +y is atlas row 0.
  gl_Position = vec4(position.x * info.target.z * 2.0 - 1.0,
                     1.0 - position.y * info.target.w * 2.0, 0.0, 1.0);

  vec3 radiance = textureLod(scene_radiance, uv, 0.0).rgb;
  // A linear HDR image is bounded near 1.0 for fully lit reflective surfaces,
  // so the excess above that is emission. Boosting only the excess lets a
  // small emitter light a room without brightening the direct image.
  // TODO(gi-emissive-split): route the shaded emissive term through its own
  // channel so the boost applies to emission exactly rather than to the
  // radiance above the reflective range.
  if (info.camera_position.w != 1.0) {
    vec3 excess = max(radiance - vec3(1.0), vec3(0.0));
    radiance += excess * (info.camera_position.w - 1.0);
  }
  // Energy conservation on recursive diffuse feedback: damp reflective radiance
  // so the infinite-bounce geometric series (albedo * gain)^N converges strictly
  // below unity and avoids chromatic saturation runaway.
  vec3 diffuse_reflected = min(radiance, vec3(1.0)) * 0.6;
  vec3 emission_excess = max(radiance - vec3(1.0), vec3(0.0));
  radiance = diffuse_reflected + emission_excess;
  v_radiance = ProbeClampLuminance(radiance, info.proj.w);
  v_sample = vec4(direction, distance_to_sample / info.grid_spacing.w);
  v_weight = weight;
}
