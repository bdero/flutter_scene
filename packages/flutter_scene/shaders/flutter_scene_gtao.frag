// Ground-truth ambient occlusion, evaluated from the camera linear-depth
// prepass.
//
// Reconstructs each pixel's view-space position and normal from depth, then
// integrates hemisphere visibility over a set of screen-space slices. Each
// slice marches the depth field both ways from the pixel and either tracks
// the two horizon angles, integrating the cosine-weighted visible arc in
// closed form, or marks occluded sectors in a 32-bit visibility bitmask,
// which models occluders with a constant thickness instead of treating the
// depth buffer as an infinitely thick height field. The output is a single
// visibility factor in the red channel: 1 is unoccluded, 0 is fully
// occluded. The shared bilateral blur pass cleans up the per-pixel noise
// afterwards.
//
// The slice integration follows Jimenez et al., "Practical Realtime
// Strategies for Accurate Indirect Occlusion" (2016),
// https://www.iryoku.com/downloads/Practical-Realtime-Strategies-for-Accurate-Indirect-Occlusion.pdf
// and the visibility bitmask follows Therrien et al., "Screen Space Indirect
// Lighting with Visibility Bitmask" (2023), https://arxiv.org/abs/2301.11376.
//
// In horizon mode the pass can also accumulate the bent normal (the mean
// unoccluded direction), octahedrally packed view-space into the output's ba
// channels; the material shader samples irradiance along it and derives cone
// specular occlusion. The g channel is reserved for the screen-space
// contact-shadow term and holds 1 (unshadowed) here.

uniform sampler2D linear_depth;

// Downsampled copies of the depth (half, quarter, and eighth resolution).
// When the chain is disabled these are all bound to linear_depth and
// params2.z is 1, so the march only ever reads level 0.
uniform sampler2D depth_mip1;
uniform sampler2D depth_mip2;
uniform sampler2D depth_mip3;

uniform GtaoInfo {
  // x, y: occlusion target size in pixels. z, w: its reciprocal.
  vec4 viewport;
  // x: tan(fovX / 2). y: tan(fovY / 2). z: near plane. w: far plane.
  vec4 proj;
  // x: radius (world units). y: obscurance intensity. z: final visibility
  // power. w: projection scale (pixels per world unit at depth 1).
  vec4 params;
  // x: slice count. y: steps per slice side. z: mip level count.
  // w: thickness heuristic (horizon mode).
  vec4 params2;
  // x: 1 when the visibility bitmask is enabled. y: occluder thickness
  // (world units, bitmask mode). z: 1 when the bent normal is computed and
  // octahedrally packed into the output's ba (horizon mode only). w: unused.
  vec4 params3;
  // xyz: view-space direction toward the sun. w: the contact-shadow march
  // distance in world units, 0 when contact shadows are off.
  vec4 contact;
}
gtao;

in vec2 v_uv;
out vec4 frag_color;

// Static loop bounds so the loops are constant-bounded for the GLES shader
// output; the dynamic counts break out early.
#define MAX_GTAO_SLICES 8
#define MAX_GTAO_STEPS 8

const float kPi = 3.14159265359;
const float kHalfPi = 1.57079632679;
const float kNumericEpsilon = 0.0001;
const uint kSectorCount = 32u;

#include <interleaved_gradient_noise.glsl>

#define AO_INFO gtao
#include <ssao_geometry.glsl>
#include <octahedral.glsl>
#include <contact_shadow.glsl>

// Closed-form integral of cosine-weighted visibility over the arc from the
// slice-plane normal angle [gamma] up to the horizon angle [h].
float IntegrateArc(float h, float gamma) {
  return 0.25 * (-cos(2.0 * h - gamma) + cos(gamma) + 2.0 * h * sin(gamma));
}

// Raises the running horizon cosine with a soft falloff toward the sampling
// radius. A sample below the current horizon instead decays it slightly, so
// a thin occluder stops casting occlusion once the march walks past it.
float UpdateHorizon(vec3 delta, vec3 view_dir, float horizon_cos,
                    float inv_radius2, float thickness_heuristic) {
  float distance2 = dot(delta, delta);
  float sample_cos =
      dot(delta, view_dir) * inversesqrt(max(distance2, kNumericEpsilon));
  float falloff = clamp(distance2 * inv_radius2 * 2.0, 0.0, 1.0);
  return sample_cos > horizon_cos
      ? mix(sample_cos, horizon_cos, falloff)
      : mix(horizon_cos, sample_cos, thickness_heuristic);
}

// Population count for the ES 3.00 output, which has no bitCount().
uint CountBits(uint v) {
  v = v - ((v >> 1u) & 0x55555555u);
  v = (v & 0x33333333u) + ((v >> 2u) & 0x33333333u);
  v = (v + (v >> 4u)) & 0x0F0F0F0Fu;
  return (v * 0x01010101u) >> 24u;
}

// Marks the sectors covered by a sample as occluded. The sample's front face
// and an assumed back face [thickness] behind it (along the view direction)
// bound an angular range in the slice plane; the range maps onto the 32
// sectors spanning the hemisphere around the projected normal angle [gamma].
uint OccludeSectors(vec3 delta, vec3 view_dir, float side, float gamma,
                    float thickness, uint bits) {
  vec3 delta_back = delta - view_dir * thickness;
  float front = acos(clamp(
      dot(delta, view_dir) *
          inversesqrt(max(dot(delta, delta), kNumericEpsilon)),
      -1.0, 1.0));
  float back = acos(clamp(
      dot(delta_back, view_dir) *
          inversesqrt(max(dot(delta_back, delta_back), kNumericEpsilon)),
      -1.0, 1.0));
  // Angles relative to the view direction, shifted to the hemisphere around
  // the projected normal and normalized to sector space [0, 1].
  vec2 range = clamp(
      (side * -vec2(front, back) + gamma + kHalfPi) / kPi, 0.0, 1.0);
  // The march direction flips which end of the range is the sector start.
  vec2 min_max = side >= 0.0 ? range.yx : range.xy;
  uint start = min(uint(min_max.x * float(kSectorCount)), kSectorCount - 1u);
  uint count = uint(ceil(clamp(min_max.y - min_max.x, 0.0, 1.0) *
                         float(kSectorCount)));
  // Build the sector mask with left shifts only. A right shift of an
  // all-ones literal executes as a signed arithmetic shift through some
  // GLES translation layers (the ANGLE Direct3D path), which floods the
  // mask and marks every sector occluded.
  uint mask = count >= kSectorCount
      ? 0xFFFFFFFFu
      : ((1u << count) - 1u) << start;
  return bits | mask;
}

void main() {
  float radius = gtao.params.x;
  float intensity = gtao.params.y;
  float power = gtao.params.z;
  float proj_scale = gtao.params.w;
  int slice_count = int(gtao.params2.x);
  int step_count = int(gtao.params2.y);
  int mip_levels = int(gtao.params2.z);
  float thickness_heuristic = gtao.params2.w;
  bool use_bitmask = gtao.params3.x > 0.5;
  float thickness = gtao.params3.y;
  bool compute_bent = gtao.params3.z > 0.5;
  float far = gtao.proj.w;

  vec3 origin = ViewPositionAt(v_uv, 0);

  // Background texels (no geometry) are unoccluded; the bent normal encodes
  // straight at the camera.
  if (origin.z >= far) {
    frag_color = compute_bent
        ? vec4(1.0, 1.0, OctEncode(vec3(0.0, 0.0, -1.0)))
        : vec4(1.0, 1.0, 1.0, 1.0);
    return;
  }

  vec3 normal = ReconstructNormal(v_uv, origin);
  vec3 view_dir = -normalize(origin);

  // Screen-space march radius: the world radius projected to this depth.
  float screen_radius = proj_scale * radius / origin.z;
  float step_radius = screen_radius / (float(step_count) + 1.0);

  // Spatial-only noise: the slice fan rotates per pixel and the march start
  // jitters per pixel with a decorrelated hash, trading banding for grain
  // the bilateral blur removes.
  float direction_noise = InterleavedGradientNoise(gl_FragCoord.xy);
  float offset_noise =
      InterleavedGradientNoise(gl_FragCoord.xy + vec2(47.0, 17.0));

  float contact_visibility = 1.0;
  if (gtao.contact.w > 0.0) {
    contact_visibility = MarchContactShadow(origin, offset_noise);
  }

  float inv_radius2 = 1.0 / max(radius * radius, kNumericEpsilon);
  float visibility_sum = 0.0;
  vec3 bent_sum = vec3(0.0);
  for (int i = 0; i < MAX_GTAO_SLICES; i++) {
    if (i >= slice_count) {
      break;
    }
    float phi = (float(i) + direction_noise) * kPi / float(slice_count);
    // The UV-space march direction. View-space Y points up while the UV V
    // runs down, so the in-plane view direction negates Y.
    vec2 omega = vec2(cos(phi), sin(phi));
    vec3 direction = vec3(omega.x, -omega.y, 0.0);
    vec3 ortho = direction - dot(direction, view_dir) * view_dir;
    ortho *= inversesqrt(max(dot(ortho, ortho), kNumericEpsilon));
    // The slice plane spans [ortho] and [view_dir]; [axis] is its normal.
    vec3 axis = cross(ortho, view_dir);
    vec3 proj_normal = normal - axis * dot(normal, axis);
    float proj_length = length(proj_normal);
    float cos_norm = clamp(
        dot(proj_normal, view_dir) / max(proj_length, kNumericEpsilon),
        0.0, 1.0);
    // The signed angle between the projected normal and the view direction.
    float gamma = sign(dot(ortho, proj_normal)) * acos(cos_norm);

    float horizon_cos0 = -1.0;
    float horizon_cos1 = -1.0;
    uint occluded_sectors = 0u;

    for (int j = 0; j < MAX_GTAO_STEPS; j++) {
      if (j >= step_count) {
        break;
      }
      // March at least one pixel per step so short radii still walk distinct
      // depth texels.
      float pixel_offset = max((float(j) + offset_noise) * step_radius,
                               float(j) + 1.0);
      // Read the depth from a coarser level as the march gets further out,
      // matching the obscurance shader's chain selection.
      int level = 0;
      if (mip_levels > 1) {
        level = clamp(
            int(floor(log2(max(1.0, pixel_offset)))) - 3, 0, mip_levels - 1);
      }
      vec2 uv_offset = omega * pixel_offset * gtao.viewport.zw;
      vec3 delta0 = ViewPositionAt(v_uv + uv_offset, level) - origin;
      vec3 delta1 = ViewPositionAt(v_uv - uv_offset, level) - origin;
      if (use_bitmask) {
        occluded_sectors = OccludeSectors(
            delta0, view_dir, 1.0, gamma, thickness, occluded_sectors);
        occluded_sectors = OccludeSectors(
            delta1, view_dir, -1.0, gamma, thickness, occluded_sectors);
      } else {
        horizon_cos0 = UpdateHorizon(
            delta0, view_dir, horizon_cos0, inv_radius2, thickness_heuristic);
        horizon_cos1 = UpdateHorizon(
            delta1, view_dir, horizon_cos1, inv_radius2, thickness_heuristic);
      }
    }

    if (use_bitmask) {
      visibility_sum +=
          1.0 - float(CountBits(occluded_sectors)) / float(kSectorCount);
    } else {
      // Clamp both horizons to the hemisphere around the projected normal,
      // then integrate the two visible arcs in closed form.
      float h0 = gamma + clamp(-acos(horizon_cos1) - gamma, -kHalfPi, kHalfPi);
      float h1 = gamma + clamp(acos(horizon_cos0) - gamma, -kHalfPi, kHalfPi);
      visibility_sum +=
          proj_length * (IntegrateArc(h0, gamma) + IntegrateArc(h1, gamma));
      if (compute_bent) {
        // The mid-angle of the visible arc, rotated from the view direction
        // toward the slice's in-plane axis.
        float mid = 0.5 * (h0 + h1);
        bent_sum += view_dir * cos(mid) + ortho * sin(mid);
      }
    }
  }

  float visibility = clamp(visibility_sum / float(slice_count), 0.0, 1.0);
  // Shared output shaping with the obscurance shader, so intensity and power
  // keep one meaning across both methods.
  float obscurance = min(intensity * (1.0 - visibility), 0.98);
  float ao = pow(clamp(1.0 - obscurance, 0.0, 1.0), power);

  if (compute_bent) {
    // Nudged toward the view direction so a fully occluded pixel still
    // normalizes to a valid direction.
    vec3 bent = normalize(bent_sum + view_dir * kNumericEpsilon);
    frag_color = vec4(ao, contact_visibility, OctEncode(bent));
    return;
  }
  frag_color = vec4(ao, contact_visibility, ao, 1.0);
}
