// Picks this frame's screen samples for each probe of the irradiance field.
//
// One fragment per (probe, sample) pair, laid out as an 8x8 block per probe
// in the same tile grid the field's atlas uses. Each probe projects the box
// its trilinear support covers (one cell either side) onto the screen and
// takes a jittered, stratified sample of the depth prepass inside that
// rectangle, so every probe sees a fixed number of samples whatever its
// screen size. The gather then reads only its own probe's block.
//
// A sample's weight is its trilinear share and facing term, scaled by how
// many injection texels its stratum stands for, so the gathered weight sums
// estimate the sum over every injection texel and the blend's coverage test
// reads them at the injection density.
//
// Writes the sample's offset from the probe (normalized by the farthest
// distance a probe records) and weight when `schedule.z` is 0, its radiance
// when 1.

#include <irradiance_field.glsl>
#include <view_projection.glsl>

uniform SampleInfo {
  // xy: the injection resolution in texels, the density each stratum stands
  // for. zw: unused.
  vec4 source_size;
  // xy: the projection scale (see view_projection.glsl). z: the far plane,
  // past which a texel is background. w: the firefly luminance clamp.
  vec4 proj;
  // xyz: world-space camera position. w: the emissive injection boost.
  vec4 camera_position;
  // The camera basis in xyz. camera_right.w and camera_up.w are the NDC
  // position of the view axis; camera_forward.w is 1 for an orthographic
  // camera.
  vec4 camera_right;
  vec4 camera_up;
  vec4 camera_forward;
  // xyz: world-space probe spacing. w: the farthest distance a probe records.
  vec4 grid_spacing;
  // xyz: lattice index of the volume's minimum-corner probe. w: a per-frame
  // jitter seed.
  vec4 grid_anchor;
  // xyz: probe counts per axis. w: probe tiles per row.
  vec4 grid_counts;
  // xy: the half-open range of tile rows this frame refreshes. z: 0 writes
  // the sample's offset and weight, 1 its radiance. w: unused.
  vec4 schedule;
}
info;

// The depth prepass' linear depth (r), octahedral view normal (gb), and
// roughness (a).
uniform highp sampler2D linear_depth_normal;
// The previous frame's lit scene color, the radiance a sample carries.
uniform highp sampler2D scene_radiance;

out vec4 frag_color;

// Samples per probe along each edge of its block.
const float kSampleEdge = 8.0;

vec3 DecodeViewNormal(vec2 e) {
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * ProbeOctSign(n.xy);
  }
  return normalize(n);
}

// A hash in [0, 1)^2 with no trigonometry, so it holds up at mobile float
// precision.
highp vec2 Hash22(highp vec2 p) {
  highp vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

highp vec3 ToView(highp vec3 world) {
  highp vec3 d = world - info.camera_position.xyz;
  return vec3(dot(d, info.camera_right.xyz), dot(d, info.camera_up.xyz),
              dot(d, info.camera_forward.xyz));
}

void main() {
  frag_color = vec4(0.0);
  highp vec2 frag = floor(gl_FragCoord.xy);
  highp vec2 tile = floor(frag / kSampleEdge);
  highp vec2 local = frag - tile * kSampleEdge;
  highp float probe_index = tile.y * info.grid_counts.w + tile.x;
  highp vec3 counts = info.grid_counts.xyz;
  if (tile.x >= info.grid_counts.w ||
      probe_index >= counts.x * counts.y * counts.z ||
      tile.y < info.schedule.x || tile.y >= info.schedule.y) {
    return;
  }

  highp vec3 slot = vec3(mod(probe_index, counts.x),
                         mod(floor(probe_index / counts.x), counts.y),
                         floor(probe_index / (counts.x * counts.y)));
  highp vec3 lattice =
      info.grid_anchor.xyz + ProbeWrapSlot(slot - info.grid_anchor.xyz, counts);
  highp vec3 spacing = info.grid_spacing.xyz;
  highp vec3 probe_position = lattice * spacing;

  // The screen rectangle of the probe's support box. A corner at or behind
  // the eye widens it to the whole screen.
  highp vec3 projection_offset =
      vec3(info.camera_right.w, info.camera_up.w, info.camera_forward.w);
  highp vec2 low = vec2(1.0);
  highp vec2 high = vec2(0.0);
  bool whole_screen = false;
  for (int i = 0; i < 8; i++) {
    highp vec3 corner = vec3(float(i - (i / 2) * 2), float((i / 2) - (i / 4) * 2),
                             float(i / 4)) * 2.0 - vec3(1.0);
    highp vec3 view = ToView(probe_position + corner * spacing);
    if (!ViewDepthProjectable(view.z, projection_offset)) {
      whole_screen = true;
    } else {
      highp vec2 uv = UvFromViewPosition(view, info.proj.xy, projection_offset);
      low = min(low, uv);
      high = max(high, uv);
    }
  }
  if (whole_screen) {
    low = vec2(0.0);
    high = vec2(1.0);
  }
  low = clamp(low, 0.0, 1.0);
  high = clamp(high, 0.0, 1.0);
  highp vec2 extent = high - low;
  if (extent.x <= 0.0 || extent.y <= 0.0) {
    return;
  }

  highp vec2 jitter = Hash22(frag + vec2(info.grid_anchor.w * 17.0,
                                         info.grid_anchor.w * 59.0));
  highp vec2 uv = low + (local + jitter) / kSampleEdge * extent;

  vec4 depth_normal = textureLod(linear_depth_normal, uv, 0.0);
  highp float depth = depth_normal.r;
  bool orthographic = info.camera_forward.w > 0.5;
  if ((!orthographic && depth <= 0.0) || depth >= info.proj.z) {
    return;
  }
  highp vec3 view_position =
      ViewPositionFromUv(uv, depth, info.proj.xy, projection_offset);
  highp vec3 world_position = info.camera_position.xyz +
                              info.camera_right.xyz * view_position.x +
                              info.camera_up.xyz * view_position.y +
                              info.camera_forward.xyz * view_position.z;

  // Outside the probe's support box the probe has no trilinear share.
  highp vec3 cell = (world_position - probe_position) / spacing;
  if (any(greaterThanEqual(abs(cell), vec3(1.0)))) {
    return;
  }
  vec3 trilinear = max(vec3(1.0) - abs(cell), vec3(0.001));
  float weight = trilinear.x * trilinear.y * trilinear.z;

  highp vec3 offset = world_position - probe_position;
  highp float distance_to_sample = length(offset);
  if (distance_to_sample <= 1e-5) {
    return;
  }
  vec3 direction = offset / distance_to_sample;
  vec3 view_normal = DecodeViewNormal(depth_normal.gb);
  vec3 world_normal = normalize(info.camera_right.xyz * view_normal.x +
                                info.camera_up.xyz * view_normal.y +
                                info.camera_forward.xyz * view_normal.z);
  // A surface facing away from the probe is not what the probe sees there.
  weight *= max(0.0, dot(-direction, world_normal));
  if (weight <= 0.0) {
    return;
  }
  // The injection texels this stratum stands for.
  weight *= extent.x * extent.y * info.source_size.x * info.source_size.y /
            (kSampleEdge * kSampleEdge);

  if (info.schedule.z < 0.5) {
    frag_color = vec4(offset / info.grid_spacing.w, weight);
    return;
  }

  vec3 radiance = textureLod(scene_radiance, uv, 0.0).rgb;
  // A linear HDR image is bounded near 1.0 for fully lit reflective surfaces,
  // so the excess above that is emission. Boosting only the excess lets a
  // small emitter light a room without brightening the direct image.
  // TODO(gi-emissive-split): route the shaded emissive term through its own
  // channel so the boost applies to emission exactly rather than to the
  // radiance above the reflective range.
  vec3 emission = max(radiance - vec3(1.0), vec3(0.0));
  // Damping reflected radiance keeps the infinite-bounce series
  // (albedo * gain)^N converging below unity.
  radiance = min(radiance, vec3(1.0)) * 0.6 +
             emission * info.camera_position.w;
  frag_color = vec4(ProbeClampLuminance(radiance, info.proj.w), 0.0);
}
