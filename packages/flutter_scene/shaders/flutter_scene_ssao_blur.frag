// Depth-aware (bilateral) blur for the screen-space ambient occlusion
// buffer. Removes the per-pixel variation of the occlusion estimate while
// preserving edges at depth discontinuities, so occlusion does not bleed
// across silhouettes.
//
// Runs once per axis as a separable 9-tap Gaussian. Each tap is weighted by
// how far its depth sits from the center's surface plane, extrapolated along
// the axis from the flatter of the two neighboring depth differences. A plane
// is linear in reciprocal depth under perspective and in depth under an
// orthographic camera, so a receding wall predicts exactly. The tolerance is
// relative to depth, so the filter behaves the same at any distance and
// resolution.

#include <ssao_depth_pack.glsl>

uniform sampler2D ao_texture;
uniform sampler2D linear_depth;

uniform BlurInfo {
  // xy: texel size (reciprocal of the occlusion target size). z: minimum
  // depth tolerance (world units). w: 1 on the final pass, otherwise 0.
  vec4 texel;
  // xy: filter axis. z: 1 when ba carries an octahedrally packed bent normal
  // that must be renormalized after filtering. w: 1 when the final pass packs
  // the depth into ba for the material's upsample.
  vec4 axis;
  // x: 1 for an orthographic camera. yzw: unused.
  vec4 params;
}
blur;

in vec2 v_uv;
out vec4 frag_color;

#define BLUR_RADIUS 4

const float kEpsilon = 0.0001;

// Plane rejection threshold as a fraction of the center depth.
const float kRelativeTolerance = 0.011;

#include <interleaved_gradient_noise.glsl>
#include <octahedral.glsl>

float GaussianWeight(int offset) {
  int i = abs(offset);
  if (i == 0) return 0.153170;
  if (i == 1) return 0.144893;
  if (i == 2) return 0.122649;
  if (i == 3) return 0.092902;
  return 0.062970;
}

highp float DepthAt(ivec2 coord, ivec2 size) {
  return texelFetch(linear_depth, clamp(coord, ivec2(0), size - ivec2(1)), 0).r;
}

// Depth in the space where a plane is linear across the screen.
highp float PlaneSpace(highp float depth, bool orthographic) {
  return orthographic ? depth : 1.0 / max(depth, 1e-6);
}

void main() {
  bool orthographic = blur.params.x > 0.5;
  ivec2 size = textureSize(linear_depth, 0);
  ivec2 center = clamp(ivec2(v_uv * vec2(size)), ivec2(0), size - ivec2(1));
  ivec2 step_axis = ivec2(blur.axis.xy);

  highp float center_depth = DepthAt(center, size);
  highp float center_plane = PlaneSpace(center_depth, orthographic);
  highp float backward =
      center_plane - PlaneSpace(DepthAt(center - step_axis, size), orthographic);
  highp float forward =
      PlaneSpace(DepthAt(center + step_axis, size), orthographic) - center_plane;
  // The flatter side, so a silhouette neighbor does not tilt the plane.
  highp float slope = abs(backward) < abs(forward) ? backward : forward;
  highp float tolerance =
      max(kRelativeTolerance * abs(center_depth), max(blur.texel.z, kEpsilon));

  vec4 ao_sum = vec4(0.0);
  float weight_sum = 0.0;
  for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; i++) {
    highp float plane = center_plane + slope * float(i);
    // Behind a perspective eye the plane has no depth, so the tap is rejected.
    highp float expected = orthographic ? plane : 1.0 / max(plane, 1e-12);
    highp float depth = DepthAt(center + step_axis * i, size);
    float delta = abs(depth - expected);
    float weight =
        GaussianWeight(i) * clamp(1.25 - delta / tolerance, 0.0, 1.0);
    vec2 uv = v_uv + blur.axis.xy * float(i) * blur.texel.xy;
    ao_sum += texture(ao_texture, uv) * weight;
    weight_sum += weight;
  }

  vec4 result = ao_sum / max(weight_sum, kEpsilon);
  if (blur.texel.w > 0.5) {
    result.r += (InterleavedGradientNoise(gl_FragCoord.xy) - 0.5) / 255.0;
    if (blur.axis.z > 0.5) {
      // Filtering octahedral coordinates off-lattice skews the direction
      // slightly; a decode/encode round trip snaps it back to unit length.
      result.ba = OctEncode(OctDecode(result.ba));
    }
    if (blur.axis.w > 0.5) {
      result.ba = PackOcclusionDepth(center_depth);
    }
    // Earlier passes keep overshoot above 1 so it averages unbiased.
    result.r = clamp(result.r, 0.0, 1.0);
  }
  frag_color = result;
}
