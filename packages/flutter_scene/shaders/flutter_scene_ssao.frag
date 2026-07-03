// Screen-space ambient occlusion, evaluated from the camera linear-depth
// prepass.
//
// Implements Scalable Ambient Obscurance (McGuire, Mara, and Luebke 2012,
// https://research.nvidia.com/publication/scalable-ambient-obscurance): it
// reconstructs each pixel's view-space position and a face normal from
// depth alone (no normal buffer), then estimates obscurance from a spiral
// of neighbour samples. The output is a single occlusion factor in the red
// channel: 1 is unoccluded, 0 is fully occluded. A bilateral blur pass
// cleans up the per-pixel noise afterwards.

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
  // x: radius (world units). y: bias (world units). z: intensity (final
  // contrast power). w: projection scale (pixels per world unit at depth 1).
  vec4 params;
  // x: sample count. y: mip level count (1 disables the chain).
  vec4 params2;
}
ssao;

in vec2 v_uv;
out vec4 frag_color;

// Static loop bound so the sample loop is constant-bounded for the GLES
// 1.00 shader output (a uniform-bounded loop is rejected by conformant ES
// drivers); the dynamic sample count breaks out early.
#define MAX_SSAO_SAMPLES 32

const float kPi = 3.14159265359;
const float kEpsilon = 0.0001;
// Golden angle, for the Vogel-disk sample distribution.
const float kGoldenAngle = 2.39996323;
// Widest screen-edge occlusion fade, as a fraction of the viewport. Keeps the
// fade a thin border even for near, large-radius geometry.
const float kEdgeFadeMax = 0.04;

// Reconstructs a view-space position from a depth-buffer UV. Camera space
// places the eye at the origin looking down +Z (the convention the depth
// prepass writes), so the stored planar depth is the view-space Z and the
// X/Y follow from the projection tangents.
// Fetches the view-space depth at [uv] from level [level] of the depth chain.
float DepthAtLevel(vec2 uv, int level) {
  if (level <= 0) return texture(linear_depth, uv).r;
  if (level == 1) return texture(depth_mip1, uv).r;
  if (level == 2) return texture(depth_mip2, uv).r;
  return texture(depth_mip3, uv).r;
}

vec3 ViewPositionAt(vec2 uv, int level) {
  float z = DepthAtLevel(uv, level);
  // NDC from the full-screen UV (V runs downward in the UV).
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  return vec3(ndc.x * z * ssao.proj.x, ndc.y * z * ssao.proj.y, z);
}

void main() {
  float radius = ssao.params.x;
  float bias = ssao.params.y;
  float intensity = ssao.params.z;
  float proj_scale = ssao.params.w;
  int sample_count = int(ssao.params2.x);
  int mip_levels = int(ssao.params2.y);
  float far = ssao.proj.w;

  vec3 origin = ViewPositionAt(v_uv, 0);

  // Background texels (no geometry) are unoccluded.
  if (origin.z >= far) {
    frag_color = vec4(1.0, 1.0, 1.0, 1.0);
    return;
  }

  // Face normal from the screen-space gradient of the reconstructed
  // position. With precise (fp32) depth this is smooth across surfaces; the
  // single-pixel errors at silhouettes are removed by the bilateral blur
  // (see the SAO paper). A per-axis "nearest depth neighbour" reconstruction
  // is sharper at edges but compares near-equal depth steps on smooth
  // surfaces, which flips per pixel and injects normal noise, so the plain
  // gradient is preferred here. Oriented toward the camera (the eye is at
  // the origin, so the view direction is -origin).
  vec3 normal = normalize(cross(dFdx(origin), dFdy(origin)));
  if (dot(normal, origin) > 0.0) {
    normal = -normal;
  }

  // Screen-space disk radius: the world radius projected to this depth.
  float screen_radius = proj_scale * radius / origin.z;

  // Interleaved rotation: 16 well-separated angles tiled over a 4x4 screen
  // block (the golden-ratio sequence spreads them, and neighbours differ
  // sharply). The matching 4x4 box blur that follows averages all 16, which
  // resolves uniform regions to a smooth result without temporal
  // accumulation. Per-pixel random rotation instead leaves screen-locked
  // grain the blur cannot fully remove.
  vec2 tile = mod(gl_FragCoord.xy, 4.0);
  float rotation_index = tile.y * 4.0 + tile.x;
  float rotation = fract(rotation_index * 0.61803399) * 2.0 * kPi;

  float radius2 = radius * radius;
  float sum = 0.0;
  for (int i = 0; i < MAX_SSAO_SAMPLES; i++) {
    if (i >= sample_count) {
      break;
    }
    // Vogel disk: a near-uniform area distribution for any sample count. The
    // sqrt radius spreads samples evenly (rather than clustering toward the
    // center like a linear spiral, whose clusters alias into screen-axis
    // streaks on receding surfaces).
    float sample_radius = sqrt((float(i) + 0.5) / float(sample_count));
    float theta = float(i) * kGoldenAngle + rotation;
    float pixel_radius = sample_radius * screen_radius;
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
    float vv = dot(v, v);
    float vn = dot(v, normal);

    // SAO falloff: (radius^2 - vv)^3 weights nearer occluders and clamps
    // anything beyond the world radius to zero.
    float f = max(radius2 - vv, 0.0);
    sum += f * f * f * max((vn - bias) / (kEpsilon + vv), 0.0);
  }

  // Empirical normalisation (the constant follows the SAO reference); the
  // user intensity is applied as a final contrast power.
  float ao = max(
      0.0,
      1.0 - 5.0 * sum / (float(sample_count) * radius2 * radius2 * radius2));
  ao = pow(clamp(ao, 0.0, 1.0), intensity);

  // Fade occlusion toward unoccluded in a thin band at the screen edge, so an
  // occluder crossing the edge (whose samples leave the viewport and have no
  // depth to read) ramps out smoothly instead of popping. The band is the
  // sample-disk reach, capped to a small fraction of the screen so near or
  // large-radius geometry does not fade a large region.
  vec2 reach = min(vec2(screen_radius) * ssao.viewport.zw, vec2(kEdgeFadeMax));
  vec2 edge = clamp(min(v_uv, 1.0 - v_uv) / max(reach, vec2(kEpsilon)),
                    0.0, 1.0);
  float edge_fade = smoothstep(0.0, 1.0, edge.x) * smoothstep(0.0, 1.0, edge.y);
  ao = mix(1.0, ao, edge_fade);

  frag_color = vec4(ao, ao, ao, 1.0);
}
