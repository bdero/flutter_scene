// Screen-space contact shadows for the primary directional light, marched as
// wavefronts in compute. Each flutter_scene_contact_shadows_wavefront_*.comp
// defines SAMPLE_COUNT, the samples each pixel compares against, and includes
// this body.
//
// After the wavefront method of Bend Studio's screen space shadows (Graham
// Aldridge, SIGGRAPH 2023, Apache-2.0,
// https://www.bendstudio.com/blog/inside-bend-screen-space-shadows/). In
// screen space every ray toward the light runs straight to the light's
// projected pixel, and depth stored as 1 / view depth varies linearly along
// it, so (depth - light depth) / distance from the light pixel is constant
// along a ray. Square rings of WAVE_SIZE pixels around the light pixel split
// the screen; each workgroup takes the WAVE_SIZE pixels of one line through
// one ring, reads them plus the next ones toward the light into shared memory
// once, and every pixel then compares against the SAMPLE_COUNT pixels before
// it on its line. Deterministic, so it needs no temporal resolve.
//
// The ray from a receiver is lifted one thickness window toward the camera,
// and a sample casts by how close its depth comes to that lifted ray. The
// first HARD_SHADOW_SAMPLES cast alone; the rest average over four
// interleaved buckets, which softens single-pixel occluders, and the last
// FADE_OUT_SAMPLES before the march ends fade toward lit.

#ifndef SAMPLE_COUNT
#define SAMPLE_COUNT 60
#endif
#define WAVE_SIZE 64
#define READ_COUNT (SAMPLE_COUNT / WAVE_SIZE + 2)
#define HARD_SHADOW_SAMPLES 4
#define FADE_OUT_SAMPLES 8

layout(local_size_x = 64) in;

layout(std430) buffer;

uniform highp sampler2D linear_depth;

// One packed rgba8 texel per pixel (r the visibility, gba 1), rows
// `size.z` texels apart, for a copy into the sun's visibility texture.
layout(binding = 0) writeonly buffer Visibility {
  uint texels[];
}
visibility;

uniform WavefrontInfo {
  // xy: the light's pixel position. z: the light's depth as 1 / view depth
  // (0 for a directional light). w: 1 when the light is in front of the
  // camera, so rays run toward its pixel, -1 when behind, so they run away.
  highp vec4 light;
  // x: the ring's outer radius in pixels (a multiple of WAVE_SIZE). y: the
  // first perimeter position this dispatch covers. z: the perimeter's
  // length, 8 times the radius. w unused.
  highp vec4 ring;
  // xy: the depth texture's size. z: the output row stride in texels. w
  // unused.
  highp vec4 size;
  // xy: the projection scale (see view_projection.glsl). z: near plane. w:
  // far plane.
  highp vec4 proj;
  // xy: the NDC position of the view axis. z: 1 for an orthographic camera.
  // w unused.
  highp vec4 proj_offset;
  // xyz: the view-space direction toward the light. w: the march distance
  // in world units.
  highp vec4 toward_light;
  // x: thickness window (world units). y: the view depth where contact
  // shadows end. z: the range they fade out over before it. w: opacity.
  highp vec4 settings;
  // x: shadow contrast. yzw unused.
  highp vec4 shaping;
}
info;

#include <view_projection.glsl>

shared highp float stored_slope[READ_COUNT * WAVE_SIZE];

// The pixel offset from the light of perimeter position [p] on the square
// ring of radius [radius]: top edge left to right, right edge top to bottom,
// bottom edge right to left, left edge bottom to top.
vec2 PerimeterOffset(float p, float radius) {
  float side = 2.0 * radius;
  if (p < side) return vec2(-radius + p, -radius);
  if (p < 2.0 * side) return vec2(radius, -radius + (p - side));
  if (p < 3.0 * side) return vec2(radius - (p - 2.0 * side), radius);
  return vec2(-radius, radius - (p - 3.0 * side));
}

// The distance from the light pixel, in ring units (the major axis), of
// shared slot [slot]. Slots run along the ray, so a larger slot is nearer the
// light in front of the camera, and farther from it behind.
float SlotDistance(float slot, float radius) {
  return info.light.w > 0.0 ? radius - slot
                            : radius - float(WAVE_SIZE - 1) + slot;
}

void main() {
  uint thread = gl_LocalInvocationID.x;
  float radius = info.ring.x;
  float perimeter = info.ring.z;
  float p = mod(info.ring.y + float(gl_WorkGroupID.x), perimeter);
  vec2 offset = PerimeterOffset(p, radius);
  vec2 depth_size = info.size.xy;

  // Read this line's pixels into shared memory, each as the slope of its
  // depth toward the light's.
  highp float own_depth = info.proj.w;
  ivec2 own_pixel = ivec2(-1);
  for (int i = 0; i < READ_COUNT; i++) {
    float slot = float(i * WAVE_SIZE) + float(thread);
    float distance = SlotDistance(slot, radius);
    highp float slope = 1e10;
    if (distance > 0.5) {
      vec2 position = info.light.xy + offset * (distance / radius);
      ivec2 pixel = ivec2(floor(position));
      highp float view_depth = info.proj.w;
      if (position.x >= 0.0 && position.y >= 0.0 &&
          position.x < depth_size.x && position.y < depth_size.y) {
        view_depth = texelFetch(linear_depth, pixel, 0).r;
      }
      slope = (1.0 / max(view_depth, 1e-6) - info.light.z) / distance;
      if (i == 0) {
        own_depth = view_depth;
        own_pixel = pixel;
      }
    }
    stored_slope[int(slot)] = slope;
  }
  // barrier() also orders the shared writes; a separate
  // memoryBarrierShared() emits an OpMemoryBarrier the WGSL translation
  // rejects.
  barrier();

  if (own_pixel.x < 0 || own_pixel.y < 0 || float(own_pixel.x) >= depth_size.x ||
      float(own_pixel.y) >= depth_size.y) {
    return;
  }
  float result = 1.0;
  if (own_depth < info.proj.w && own_depth < info.settings.y) {
    float own_distance = SlotDistance(float(thread), radius);
    highp float own_slope = stored_slope[thread];
    // The thickness window as a change of 1 / view depth at this receiver.
    highp float window = info.settings.x / (own_depth * own_depth);

    // How many samples the world-space march distance covers on screen.
    vec2 uv = (vec2(own_pixel) + 0.5) / depth_size;
    highp vec3 origin = ViewPositionFromUv(uv, own_depth, info.proj.xy,
                                           info.proj_offset.xyz);
    highp vec3 end = origin + info.toward_light.xyz * info.toward_light.w;
    float reach = float(SAMPLE_COUNT);
    if (end.z > info.proj.z) {
      vec2 end_uv = UvFromViewPosition(end, info.proj.xy, info.proj_offset.xyz);
      vec2 span = abs(end_uv - uv) * depth_size;
      reach = min(reach, max(span.x, span.y));
    }
    float fade_start = reach - float(FADE_OUT_SAMPLES);

    float hard_shadow = 1.0;
    vec4 shadow = vec4(1.0);
    for (int j = 1; j <= SAMPLE_COUNT; j++) {
      float step_index = float(j);
      if (step_index > reach) {
        break;
      }
      float sample_distance = own_distance - step_index * info.light.w;
      // How far the sample sits in front of this receiver's ray at its own
      // distance, in windows, against the ray lifted one window.
      highp float in_front =
          sample_distance * (stored_slope[int(thread) + j] - own_slope);
      float delta = abs(in_front / window - 1.0);
      if (j <= HARD_SHADOW_SAMPLES) {
        hard_shadow = min(hard_shadow, delta);
      } else {
        if (step_index > fade_start) {
          delta += (step_index - fade_start) / float(FADE_OUT_SAMPLES + 1) *
                   0.75;
        }
        int bucket = j - (j / 4) * 4;
        if (bucket == 0) shadow.x = min(shadow.x, delta);
        else if (bucket == 1) shadow.y = min(shadow.y, delta);
        else if (bucket == 2) shadow.z = min(shadow.z, delta);
        else shadow.w = min(shadow.w, delta);
      }
    }
    float contrast = info.shaping.x;
    shadow = clamp(shadow * contrast + (1.0 - contrast), 0.0, 1.0);
    hard_shadow = clamp(hard_shadow * contrast + (1.0 - contrast), 0.0, 1.0);
    float visibility_value = min(hard_shadow, dot(shadow, vec4(0.25)));
    float fade = info.settings.w *
                 clamp((info.settings.y - own_depth) /
                           max(info.settings.z, 1e-4),
                       0.0, 1.0);
    result = 1.0 - (1.0 - visibility_value) * fade;
  }
  uint byte_value = uint(clamp(result, 0.0, 1.0) * 255.0 + 0.5);
  visibility.texels[uint(own_pixel.y) * uint(info.size.z) +
                    uint(own_pixel.x)] = 0xFFFFFF00u | byte_value;
}
