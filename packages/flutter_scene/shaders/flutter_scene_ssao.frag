// Screen-space ambient occlusion, evaluated from the camera linear-depth
// prepass.
//
// Reconstructs each pixel's view-space position and face normal from depth,
// then averages normalized angular obscurance over a world-space sampling
// radius. The output is a single occlusion factor in the red channel: 1 is
// unoccluded, 0 is fully occluded. A bilateral blur pass cleans up the
// per-pixel noise afterwards.
//
// The depth hierarchy and sampling follow McGuire et al., "Scalable Ambient
// Obscurance" (2012),
// https://research.nvidia.com/publication/scalable-ambient-obscurance.

uniform sampler2D linear_depth;

// Downsampled copies of the depth for the SAO mip chain (half, quarter, and
// eighth resolution). When the chain is disabled these are all bound to
// linear_depth and params2.y is 1, so the sample loop only ever reads level 0.
uniform sampler2D depth_mip1;
uniform sampler2D depth_mip2;
uniform sampler2D depth_mip3;

uniform SsaoInfo {
  // x, y: occlusion target size in pixels. z, w: its reciprocal.
  vec4 viewport;
  // x: tan(fovX / 2). y: tan(fovY / 2). z: near plane. w: far plane.
  vec4 proj;
  // x: radius (world units). y: bias (world units). z: obscurance intensity.
  // w: projection scale (pixels per world unit at depth 1).
  vec4 params;
  // x: sample count. y: mip level count. z: minimum horizon sine term.
  // w: final visibility power.
  vec4 params2;
  // x: immediate-neighbour detail intensity. yzw: unused.
  vec4 params3;
  // xyz: view-space direction toward the sun. w: the contact-shadow march
  // distance in world units, 0 when contact shadows are off.
  vec4 contact;
}
ssao;

in vec2 v_uv;
out vec4 frag_color;

// Static loop bound so the sample loop is constant-bounded for the GLES
// 1.00 shader output (a uniform-bounded loop is rejected by conformant ES
// drivers); the dynamic sample count breaks out early.
#define MAX_SSAO_SAMPLES 32

const float kPi = 3.14159265359;
const float kNumericEpsilon = 0.0001;

#include <interleaved_gradient_noise.glsl>

#define AO_INFO ssao
#include <ssao_geometry.glsl>
#include <contact_shadow.glsl>

float SampleObscurance(vec3 normal, vec3 delta, float falloff_scale,
                       float horizon) {
  float distance2 = dot(delta, delta);
  float normal_dot_delta =
      dot(normal, delta) * inversesqrt(max(distance2, kNumericEpsilon));
  float falloff = max(0.0, 1.0 + distance2 * falloff_scale);
  return max(0.0, normal_dot_delta - horizon) * falloff;
}

void main() {
  float radius = ssao.params.x;
  float bias = ssao.params.y;
  float intensity = ssao.params.z;
  float proj_scale = ssao.params.w;
  int sample_count = int(ssao.params2.x);
  int mip_levels = int(ssao.params2.y);
  float horizon_angle = ssao.params2.z;
  float power = ssao.params2.w;
  float detail = ssao.params3.x;
  float far = ssao.proj.w;

  vec3 origin = ViewPositionAt(v_uv, 0);

  // Background texels (no geometry) are unoccluded.
  if (origin.z >= far) {
    frag_color = vec4(1.0, 1.0, 1.0, 1.0);
    return;
  }

  vec3 normal = ReconstructNormal(v_uv, origin);

  // Screen-space disk radius: the world radius projected to this depth.
  // Keep the full radius at viewport boundaries. Depth sampling clamps there,
  // so the same normalized kernel remains stable without a separate output
  // fade or a boundary-dependent change in contact strength.
  float screen_radius = 0.85 * proj_scale * radius / origin.z;

  // A non-repeating pixel hash avoids the screen-aligned 4x4 phase pattern
  // that survives filtering as horizontal and vertical bands.
  float noise = InterleavedGradientNoise(gl_FragCoord.xy);
  float rotation = noise * 2.0 * kPi;

  float contact_visibility = 1.0;
  if (ssao.contact.w > 0.0) {
    contact_visibility = MarchContactShadow(
        origin, InterleavedGradientNoise(gl_FragCoord.xy + vec2(47.0, 17.0)));
  }
  float spiral_turns = sample_count <= 8 ? 3.0
      : (sample_count <= 12 ? 5.0 : (sample_count <= 20 ? 7.0 : 14.0));

  float radius2 = radius * radius;
  float falloff_scale = -1.0 / max(radius2, kNumericEpsilon);
  float horizon = horizon_angle + max(bias, 0.0) / max(radius, kNumericEpsilon);
  float sum = 0.0;
  float weight_sum = 0.0;
  for (int i = 0; i < MAX_SSAO_SAMPLES; i++) {
    if (i >= sample_count) {
      break;
    }
    // The linear radial progression and prime-ish turn counts follow the SAO
    // reference kernel. Unlike sqrt spacing, this retains enough close taps to
    // resolve contact occlusion without amplifying distant depth variation.
    float sample_radius = (float(i) + 0.5) / float(sample_count);
    float theta = sample_radius * spiral_turns * 2.0 * kPi + rotation;
    float pixel_radius = sample_radius * screen_radius;
    // Fade subpixel support continuously instead of dropping taps as the
    // projected kernel shrinks. The one-pixel floor keeps depth taps distinct
    // enough for nearest sampling while the support removes their influence.
    float sample_support = smoothstep(0.0, 1.0, pixel_radius);
    pixel_radius = max(1.0, pixel_radius);
    vec2 offset = vec2(cos(theta), sin(theta)) * pixel_radius;
    vec2 sample_uv = v_uv + offset * ssao.viewport.zw;

    // Read the depth from a coarser level as the sample gets further away, so
    // far taps read pre-reduced depth (cache-friendly) and, with a full-
    // resolution level 0, near geometry is not contaminated by the surface
    // behind it where the projection compresses depth. Level 0 when the chain
    // is disabled (mip_levels <= 1).
    int level = 0;
    if (mip_levels > 1) {
      level = clamp(
          int(floor(log2(max(1.0, pixel_radius)))) - 3, 0, mip_levels - 1);
    }
    vec3 q = ViewPositionAt(sample_uv, level);
    vec3 v = q - origin;
    float reduce = clamp(
        max(0.0, -v.z) * (-1.0 / max(radius, kNumericEpsilon)) + 2.0,
        0.0, 1.0);
    float weight = 0.6 * reduce + 0.4;
    sum += SampleObscurance(normal, v, falloff_scale, horizon) * weight *
        sample_support;
    weight_sum += weight;
  }

  // Immediate neighbours recover tight contact detail before the wide kernel
  // is filtered. Rotating by the pixel hash removes screen-axis alignment
  // so curvature under perspective projection does not produce coherent
  // horizontal or vertical stripes on planar surfaces.
  float detail_sum = 0.0;
  if (detail > 0.0) {
    vec2 rot_x = vec2(cos(rotation), sin(rotation));
    vec2 rot_y = vec2(-rot_x.y, rot_x.x);
    vec3 q0 = ViewPositionAt(v_uv + rot_x * ssao.viewport.zw, 0);
    vec3 q1 = ViewPositionAt(v_uv - rot_x * ssao.viewport.zw, 0);
    vec3 q2 = ViewPositionAt(v_uv + rot_y * ssao.viewport.zw, 0);
    vec3 q3 = ViewPositionAt(v_uv - rot_y * ssao.viewport.zw, 0);
    detail_sum += SampleObscurance(
        normal, q0 - origin, falloff_scale * 4.0, horizon);
    detail_sum += SampleObscurance(
        normal, q1 - origin, falloff_scale * 4.0, horizon);
    detail_sum += SampleObscurance(
        normal, q2 - origin, falloff_scale * 4.0, horizon);
    detail_sum += SampleObscurance(
        normal, q3 - origin, falloff_scale * 4.0, horizon);
  }

  float wide_obscurance = weight_sum > 0.0 ? sum / weight_sum : 0.0;
  // Both terms are means. `detail` is therefore the additive strength of the
  // four-neighbour mean before `intensity` scales their combined obscurance.
  float obscurance = wide_obscurance + detail * detail_sum * 0.25;
  // The estimator's raw mean reads weak, so it is normalized to the tuned
  // strength here and intensity 1.0 is the calibrated default (matching the
  // ground-truth shader's convention).
  obscurance = min(intensity * 2.0 * obscurance, 0.98);
  float ao = pow(clamp(1.0 - obscurance, 0.0, 1.0), power);

  frag_color = vec4(ao, contact_visibility, ao, 1.0);
}
