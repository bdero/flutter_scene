// Temporal Anti-Aliasing (TAA) resolve shader.
//
// Performs 3x3 velocity dilation, camera reprojection from linear depth,
// Catmull-Rom history sampling, then YCoCg variance clipping, the history
// mix, and optional sharpening, all on tone-mapped color so extreme HDR
// values stay stable. Each tone-mapped color carries its headroom
// 1 / (1 + luminance) alongside, so the mix returns to linear HDR exactly,
// up to half-float range, without inverting a value near 1.

uniform TaaInfo {
  mat4 current_to_previous_view_projection;
  vec4 camera_position;
  vec4 projection_params; // xy: projection scale (view_projection.glsl), z: far, w: near
  vec4 jitter_params; // xy: current jitter NDC, zw: previous jitter NDC
  vec4 taa_settings; // x: minimumCurrentWeight, y: varianceGamma, z: sharpness, w: objectMotion
  vec4 screen_size; // xy: width, height, zw: 1.0/width, 1.0/height
  vec4 projection_offset; // xy: NDC position of the view axis, z: 1 orthographic
} info;

#include <view_projection.glsl>

// Whether planar depth [d] is a surface inside the view volume. Orthographic
// volumes can start behind the eye, so the lower bound is the near plane.
bool IsSurfaceDepth(float d) {
  return d >= info.projection_params.w && d < info.projection_params.z;
}

uniform sampler2D current_color;
uniform sampler2D history_color;
uniform sampler2D velocity_texture;
uniform sampler2D current_depth;
uniform sampler2D previous_depth;

in vec2 v_uv;

out vec4 frag_color;

vec3 RGB2YCoCg(vec3 c) {
  return vec3(
    0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
    0.5 * c.r - 0.5 * c.b,
    -0.25 * c.r + 0.5 * c.g - 0.25 * c.b
  );
}

vec3 YCoCg2RGB(vec3 c) {
  return vec3(
    c.x + c.y - c.z,
    c.x + c.z,
    c.x - c.y - c.z
  );
}

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

// Bounds [c] to [0, half-float max] first, so a NaN or infinite sample
// cannot turn the statistics below into NaN.
vec3 Bounded(vec3 c) {
  return min(max(c, vec3(0.0)), vec3(65504.0));
}

// 1 / (1 + luminance): one minus the tone-mapped luminance, computed without
// the cancellation that subtracting from 1 suffers for bright colors.
float Headroom(vec3 c) {
  return 1.0 / (1.0 + dot(c, kLuma));
}

// How far from the neighborhood mean [mu] toward [history] stays inside
// [box_min, box_max], from 0 (the mean) to 1 (the history unchanged).
// Unlike clamping each axis, the clipped color lies between two real
// colors, so no channel goes negative and gets zeroed into a new hue.
float ClipTowardMean(vec3 history, vec3 mu, vec3 box_min, vec3 box_max) {
  vec3 offset = history - mu;
  // Nudge flat axes off zero so the division below stays finite.
  offset += step(abs(offset), vec3(1e-6)) * 1e-6;
  vec3 room = mix(box_min - mu, box_max - mu, step(vec3(0.0), offset));
  vec3 limit = max(room / offset, vec3(0.0));
  return min(1.0, min(limit.x, min(limit.y, limit.z)));
}

// 5-tap Catmull-Rom history filter to prevent texture softening.
vec4 SampleCatmullRom(sampler2D tex, vec2 uv, vec2 texel_size) {
  vec2 sample_pos = uv / texel_size;
  vec2 tc = floor(sample_pos - 0.5) + 0.5;
  vec2 f = sample_pos - tc;
  vec2 f2 = f * f;
  vec2 f3 = f2 * f;

  vec2 w0 = f2 - 0.5 * (f3 + f);
  vec2 w1 = 1.5 * f3 - 2.5 * f2 + 1.0;
  vec2 w3 = 0.5 * (f3 - f2);
  vec2 w2 = 1.0 - w0 - w1 - w3;

  vec2 w12 = w1 + w2;
  vec2 tc12 = tc + w2 / w12;

  vec2 tc0 = tc - 1.0;
  vec2 tc3 = tc + 2.0;

  vec4 result =
      textureLod(tex, vec2(tc12.x, tc0.y) * texel_size, 0.0) * (w12.x * w0.y) +
      textureLod(tex, vec2(tc0.x, tc12.y) * texel_size, 0.0) * (w0.x * w12.y) +
      textureLod(tex, vec2(tc12.x, tc12.y) * texel_size, 0.0) * (w12.x * w12.y) +
      textureLod(tex, vec2(tc3.x, tc12.y) * texel_size, 0.0) * (w3.x * w12.y) +
      textureLod(tex, vec2(tc12.x, tc3.y) * texel_size, 0.0) * (w12.x * w3.y);

  return result / (w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y);
}

void main() {
  vec2 uv = v_uv;
  vec2 texel_size = info.screen_size.zw;

  // 1. Velocity dilation: find closest depth in 3x3 neighborhood.
  float closest_depth = 1e8;
  vec2 closest_uv = uv;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 tap_uv = uv + vec2(float(dx), float(dy)) * texel_size;
      float d = textureLod(current_depth, tap_uv, 0.0).r;
      if (IsSurfaceDepth(d) && d < closest_depth) {
        closest_depth = d;
        closest_uv = tap_uv;
      }
    }
  }

  // 2. Sample object velocity.
  vec4 obj_vel = textureLod(velocity_texture, closest_uv, 0.0);
  vec2 object_delta = (obj_vel.b > 0.5 && info.taa_settings.w > 0.5) ? obj_vel.rg : vec2(0.0);

  // 3. Compute camera velocity at closest depth.
  float depth = closest_depth < 1e7 ? closest_depth : textureLod(current_depth, uv, 0.0).r;
  vec2 screen_ndc = vec2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
  vec2 unjittered_ndc = screen_ndc - info.jitter_params.xy;

  vec4 prev_clip;
  if (IsSurfaceDepth(depth)) {
    vec3 view_pos = ViewPositionFromNdc(unjittered_ndc, depth,
                                        info.projection_params.xy,
                                        info.projection_offset.xyz);
    prev_clip = info.current_to_previous_view_projection * vec4(view_pos, 1.0);
  } else if (info.projection_offset.z > 0.5) {
    // Parallel rays have no point at infinity; reproject the far plane.
    vec3 far_pos = ViewPositionFromNdc(unjittered_ndc, info.projection_params.z,
                                       info.projection_params.xy,
                                       info.projection_offset.xyz);
    prev_clip = info.current_to_previous_view_projection * vec4(far_pos, 1.0);
  } else {
    vec3 view_dir = ViewPositionFromNdc(unjittered_ndc, 1.0,
                                       info.projection_params.xy,
                                       info.projection_offset.xyz);
    prev_clip = info.current_to_previous_view_projection * vec4(view_dir, 0.0);
  }

  bool history_valid = true;
  vec2 total_velocity_uv;
  vec2 history_uv;
  vec2 unjittered_uv = vec2(unjittered_ndc.x * 0.5 + 0.5, 0.5 - unjittered_ndc.y * 0.5);

  if (prev_clip.w <= 1e-6) {
    history_valid = false;
    history_uv = unjittered_uv;
    total_velocity_uv = vec2(0.0);
  } else {
    vec2 prev_screen_ndc = prev_clip.xy / prev_clip.w;
    vec2 prev_uv_camera = vec2(prev_screen_ndc.x * 0.5 + 0.5, 0.5 - prev_screen_ndc.y * 0.5);
    vec2 camera_velocity_uv = unjittered_uv - prev_uv_camera;

    total_velocity_uv = camera_velocity_uv + object_delta;
    history_uv = unjittered_uv - total_velocity_uv;

    // 4. History rejection.
    if (history_uv.x < 0.0 || history_uv.x > 1.0 || history_uv.y < 0.0 || history_uv.y > 1.0) {
      history_valid = false;
    } else if (IsSurfaceDepth(depth)) {
      float prev_depth = textureLod(previous_depth, history_uv, 0.0).r;
      // Planar depth in the previous frame: clip w under perspective, the
      // depth range mapping under an orthographic camera.
      float expected_depth = info.projection_offset.z > 0.5
          ? prev_clip.z * (info.projection_params.z - info.projection_params.w) +
                info.projection_params.w
          : prev_clip.w;
      if (IsSurfaceDepth(prev_depth) && abs(prev_depth - expected_depth) / max(abs(depth), 1.0) > 0.2) {
        history_valid = false;
      }
    }
  }

  // 5. Neighborhood statistics, tone-mapped like the mix below so one
  // extreme HDR pixel cannot blow open the clip box, then variance clipping
  // in YCoCg.
  vec3 curr = Bounded(textureLod(current_color, uv, 0.0).rgb);
  float headroom_curr = Headroom(curr);
  vec3 tm_curr = curr * headroom_curr;
  vec3 m1 = vec3(0.0);
  float headroom_sum = 0.0;
  vec3 m2 = vec3(0.0);
  vec3 neighbor_min = vec3(1e6);
  vec3 neighbor_max = vec3(-1e6);
  float luma_min = 1e6;
  float luma_max = 0.0;

  float cross_luma = 0.0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      vec2 tap_uv = uv + vec2(float(dx), float(dy)) * texel_size;
      vec3 tap = Bounded(textureLod(current_color, tap_uv, 0.0).rgb);
      float headroom = Headroom(tap);
      headroom_sum += headroom;
      vec3 col = tap * headroom;
      float luma = dot(col, kLuma);
      if (abs(dx) + abs(dy) == 1) {
        cross_luma += luma;
      }
      luma_min = min(luma_min, luma);
      luma_max = max(luma_max, luma);
      vec3 ycocg = RGB2YCoCg(col);
      m1 += ycocg;
      m2 += ycocg * ycocg;
      neighbor_min = min(neighbor_min, ycocg);
      neighbor_max = max(neighbor_max, ycocg);
    }
  }

  vec3 mu = m1 / 9.0;
  vec3 sigma = sqrt(max(vec3(0.0), m2 / 9.0 - mu * mu));
  float gamma = info.taa_settings.y;
  vec3 box_min = max(neighbor_min, mu - sigma * gamma);
  vec3 box_max = min(neighbor_max, mu + sigma * gamma);

  // 6. History sampling and clipping. The Catmull-Rom lobes can undershoot
  // beside a bright edge, so the sample is kept non-negative first.
  // Tone mapping and the color transform are linear past the per-color
  // headroom scale, so the clipped color's headroom is the same blend of the
  // mean's and the history's.
  vec3 history_sample = Bounded(SampleCatmullRom(history_color, history_uv, texel_size).rgb);
  float headroom_hist = Headroom(history_sample);
  vec3 history_ycocg = RGB2YCoCg(history_sample * headroom_hist);
  float clip = ClipTowardMean(history_ycocg, mu, box_min, box_max);
  vec3 tm_hist = max(vec3(0.0), YCoCg2RGB(mix(mu, history_ycocg, clip)));
  headroom_hist = mix(headroom_sum / 9.0, headroom_hist, clip);

  // 7. Tone-mapped mix.
  float vel_len = length(total_velocity_uv * info.screen_size.xy);
  float weight = max(info.taa_settings.x, min(0.2, vel_len * 0.02));
  if (!history_valid) {
    weight = 1.0;
  }
  vec3 resolved_tm = mix(tm_hist, tm_curr, weight);
  float resolved_headroom = mix(headroom_hist, headroom_curr, weight);

  // 8. Optional sharpening of luminance only, tone-mapped and held inside
  // the neighborhood's luminance range, then applied as one scale on every
  // channel so the hue cannot change. Sharpening each channel in linear HDR
  // overshot negative beside a far brighter pixel, and the clamp turned it
  // blue or magenta in the history it feeds.
  // Scaling the tone-mapped color by s scales its luminance by s too, which
  // leaves a headroom of 1 - s * (1 - h).
  if (info.taa_settings.z > 0.0) {
    float luma = dot(resolved_tm, kLuma);
    float sharpened = clamp(luma + (luma - cross_luma * 0.25) * info.taa_settings.z,
                            luma_min, luma_max);
    float s = sharpened / max(luma, 1e-6);
    resolved_tm *= s;
    resolved_headroom = 1.0 - s + s * resolved_headroom;
  }

  // Back to linear HDR. The headroom is a blend of positive terms, so this
  // divides by nothing near zero until half-float range, where it is capped.
  vec3 resolved = Bounded(resolved_tm / max(resolved_headroom, 1.0 / 65505.0));

  frag_color = vec4(resolved, 1.0);
}
