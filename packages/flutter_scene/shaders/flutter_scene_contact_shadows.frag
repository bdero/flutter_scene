// Screen-space contact shadows. Marches the linear depth prepass from each
// pixel toward up to four lights and writes each light's visibility (1 lit,
// 0 shadowed) to one channel of the mask lit materials read.
//
// Per light, the ray leaves the surface toward the light, bent toward the
// normal at grazing angles so a surface does not shadow itself, in at most
// `march.x` steps (fewer when the ray covers fewer pixels). A step hits when
// the depth buffer lies in front of the ray by less than a window that
// follows the ray's own depth change per step, capped by the thickness
// setting so a far wall never shadows through a thin pole. Hits deeper than
// half the window fade back toward lit, the ray's last quarter fades out, and
// the result fades at the screen edge and with view distance.

uniform highp sampler2D linear_depth;

uniform ContactShadowInfo {
  // xy: the mask size in pixels. zw: its reciprocal.
  highp vec4 viewport;
  // xy: the projection scale (see view_projection.glsl). z: near plane. w:
  // far plane.
  highp vec4 proj;
  // xy: the NDC position of the view axis. z: 1 for an orthographic camera.
  // w: the frame's index into the temporal noise sequence, 0 without TAA.
  highp vec4 proj_offset;
  // Maps depth texture UV to the screen UV its texels hold (xy scale, zw
  // offset). Identity, since the mask matches the depth it reads.
  highp vec4 depth_uv;
  // x: the hit window's cap (world units). y: the view depth where contact
  // shadows end. z: the view-depth range they fade out over before it. w:
  // opacity.
  highp vec4 settings;
  // x: steps per light. y: 1 packs each pixel's view depth into ba for the
  // material's depth-aware upsample. zw unused.
  highp vec4 march;
  // Per channel. xyz: the view-space direction toward a directional light,
  // or a point or spot light's view-space position. w: the light type (0
  // none, 1 directional, 2 point, 3 spot).
  highp vec4 light_vector[4];
  // Per channel. x: the march distance (world units). y: the inverse range
  // (0 unbounded). z: a spot's outer cone cosine. w unused.
  highp vec4 light_params[4];
  // Per channel. xyz: a spot's view-space travel direction. w unused.
  highp vec4 light_axis[4];
}
info;

in vec2 v_uv;
out vec4 frag_color;

#define AO_INFO info
#define SSAO_GEOMETRY_BASE_LEVEL_ONLY
#include <ssao_geometry.glsl>
#include <interleaved_gradient_noise.glsl>
#include <ssao_depth_pack.glsl>

// Constant bound, so every dialect accepts the loop; march.x breaks earlier.
#define MAX_CONTACT_STEPS 16

// How far a grazing ray bends toward the surface normal, faded out as the
// light rises above the surface.
const float kGrazingBend = 0.25;

// The visibility of one light from view-space point [origin] with normal
// [normal], at depth texel [origin_pixel] of a [size] depth texture.
float ContactVisibility(highp vec3 origin, vec3 normal, ivec2 origin_pixel,
                        ivec2 size, highp vec4 light_vector,
                        highp vec4 light_params, highp vec3 light_axis,
                        float noise) {
  highp vec3 to_light = light_vector.xyz;
  highp float ray_length = light_params.x;
  if (light_vector.w > 1.5) {
    highp vec3 offset = light_vector.xyz - origin;
    highp float distance = length(offset);
    to_light = offset / max(distance, 1e-6);
    if (light_params.y > 0.0 && distance * light_params.y >= 1.0) {
      return 1.0;
    }
    if (light_vector.w > 2.5 && dot(-to_light, light_axis) < light_params.z) {
      return 1.0;
    }
    // A ray past the light would find the light's own fixture.
    ray_length = min(ray_length, distance);
  }
  float n_dot_l = dot(normal, to_light);
  if (n_dot_l <= 0.0) {
    return 1.0;
  }
  highp vec3 direction = normalize(
      to_light +
      normal * (kGrazingBend * (1.0 - smoothstep(0.25, 0.45, n_dot_l))));
  // The depth buffer holds nothing in front of the near plane.
  if (info.proj_offset.z < 0.5 && direction.z < 0.0) {
    ray_length =
        min(ray_length, 0.999 * (origin.z - info.proj.z) / -direction.z);
  }
  if (ray_length <= 0.0) {
    return 1.0;
  }
  highp vec2 start_uv =
      UvFromViewPosition(origin, info.proj.xy, info.proj_offset.xyz);
  highp vec2 end_uv = UvFromViewPosition(origin + direction * ray_length,
                                         info.proj.xy, info.proj_offset.xyz);
  highp float pixels = length((end_uv - start_uv) * vec2(size));
  if (pixels < 1.0) {
    return 1.0;
  }
  int steps = int(clamp(min(info.march.x, pixels), 2.0,
                        float(MAX_CONTACT_STEPS)));
  highp float step_length = ray_length / float(steps);
  // Twice the ray's depth change per step, so a step cannot pass behind a
  // surface without landing inside the window, floored at one step for rays
  // that run across the view.
  highp float window =
      min(max(2.0 * abs(direction.z) * step_length, step_length),
          info.settings.x);
  // The receiving surface's own depth change across a pixel, so the plane a
  // ray leaves does not read as an occluder on the next texel.
  highp float pixel_size = 2.0 * info.proj.y *
                           ViewProjectionDepthFactor(origin.z,
                                                     info.proj_offset.xyz) /
                           float(size.y);
  highp float facing_view =
      abs(dot(normal, ViewDirectionAt(origin, info.proj_offset.xyz)));
  highp float bias =
      0.5 * pixel_size *
      min(sqrt(max(1.0 - facing_view * facing_view, 0.0)) /
              max(facing_view, 0.05),
          20.0);

  float occlusion = 0.0;
  for (int i = 0; i < MAX_CONTACT_STEPS; i++) {
    if (i >= steps || occlusion > 0.99) {
      break;
    }
    highp float t = (float(i) + noise) / float(steps);
    highp vec3 p = origin + direction * (t * ray_length);
    highp vec2 uv = UvFromViewPosition(p, info.proj.xy, info.proj_offset.xyz);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
      break;
    }
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
    if (all(equal(pixel, origin_pixel))) {
      continue;
    }
    highp float delta = p.z - texelFetch(linear_depth, pixel, 0).r;
    if (delta > bias && delta < window) {
      float penetration = clamp((delta / window - 0.5) * 2.0, 0.0, 1.0);
      float strength =
          (1.0 - penetration) * clamp((1.0 - t) * 4.0, 0.0, 1.0);
      vec2 edge = max(12.0 * abs(uv - 0.5) - 5.0, vec2(0.0));
      strength *= clamp(1.0 - dot(edge, edge), 0.0, 1.0);
      occlusion = max(occlusion, strength);
    }
  }
  return 1.0 - occlusion;
}

void main() {
  ivec2 size = textureSize(linear_depth, 0);
  ivec2 pixel = clamp(ivec2(v_uv * vec2(size)), ivec2(0), size - ivec2(1));
  highp vec3 origin = ViewPositionBase(pixel);
  vec4 visibility = vec4(1.0);
  if (origin.z < info.proj.w && origin.z < info.settings.y) {
    vec3 normal = ReconstructNormal(v_uv, origin);
    float noise = fract(InterleavedGradientNoise(gl_FragCoord.xy) +
                        TemporalNoiseOffset(info.proj_offset.w).x);
    float fade = info.settings.w *
                 clamp((info.settings.y - origin.z) /
                           max(info.settings.z, 1e-4),
                       0.0, 1.0);
    for (int i = 0; i < 4; i++) {
      if (info.light_vector[i].w > 0.5) {
        float v = ContactVisibility(origin, normal, pixel, size,
                                    info.light_vector[i], info.light_params[i],
                                    info.light_axis[i].xyz, noise);
        visibility =
            mix(visibility, vec4(1.0 - (1.0 - v) * fade),
                vec4(equal(ivec4(i), ivec4(0, 1, 2, 3))));
      }
    }
  }
  if (info.march.y > 0.5) {
    visibility.ba = PackOcclusionDepth(origin.z);
  }
  frag_color = visibility;
}
