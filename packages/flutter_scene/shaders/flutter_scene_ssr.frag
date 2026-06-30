// Screen-space reflections, composited over the linear HDR scene color.
//
// Reads each pixel's view-space position and smooth view-space normal from
// the camera depth prepass (depth in red, the interpolated normal packed
// into green/blue/alpha), reflects the view ray about that normal, and
// marches the reflected ray through the depth buffer looking for the surface
// it hits. On a hit it samples the already-lit scene color at the hit point
// and blends it in, weighted by a Fresnel term and a confidence that fades at
// screen edges and with distance. A ray that leaves the screen or finds no
// hit contributes nothing, so the surface keeps the image-based reflection it
// was lit with.
//
// The scene color is premultiplied linear HDR; the output follows the same
// contract. This pass stays entirely in render-to-texture space (it samples
// the scene color and depth, both render targets, and writes another), so
// like the occlusion pass it needs no Y flip; the resolve pass handles the
// final upright orientation.

uniform sampler2D input_color;
uniform sampler2D linear_depth;

uniform SsrInfo {
  // x, y: viewport size in pixels. z, w: its reciprocal.
  vec4 viewport;
  // x: tan(fovX / 2). y: tan(fovY / 2). z: near plane. w: far plane.
  vec4 proj;
  // x: max march distance (world units). y: thickness for hit acceptance
  // (world units). z: starting bias off the surface (world units). w: step
  // count.
  vec4 march;
  // x: reflection intensity. y: debug view (0 = composite, 1 = reflected
  // UV, 2 = hit mask, 3 = normal, 4 = confidence, 5 = raw depth). z: glossy
  // blur strength (0 = sharp mirror).
  vec4 params;
}
ssr;

in vec2 v_uv;
out vec4 frag_color;

// Constant loop bound so the march is statically bounded for the GLES 1.00
// shader output (a uniform-bounded loop is rejected by conformant ES
// drivers); the dynamic step count breaks out early. Matches the occlusion
// pass's constant-loop pattern.
#define MAX_SSR_STEPS 96

// Binary-search iterations used to refine a hit once the coarse march
// brackets the surface crossing. Constant-bounded for the same reason as the
// march loop.
#define MAX_SSR_REFINE_STEPS 5

const float kEpsilon = 0.0001;
// Screen-edge fade width, as a fraction of the viewport: reflections ramp
// out over this band as the hit approaches a screen border.
const float kEdgeFade = 0.08;

// Glossy reflection blur: a small Vogel disk of taps around the hit, with a
// radius that grows with the blur strength and the march distance (a rougher
// surface, or a more distant hit, spreads the reflected cone wider).
#define SSR_BLUR_TAPS 12
const float kGoldenAngle = 2.39996323;

// Reconstructs a view-space position from a depth-buffer UV. Camera space
// places the eye at the origin looking down +Z (the convention the depth
// prepass writes), so the stored planar depth is the view-space Z and the
// X/Y follow from the projection tangents. Mirrors the occlusion pass.
vec3 ViewPositionAt(vec2 uv) {
  float z = texture(linear_depth, uv).r;
  vec2 ndc = vec2(2.0 * uv.x - 1.0, 1.0 - 2.0 * uv.y);
  return vec3(ndc.x * z * ssr.proj.x, ndc.y * z * ssr.proj.y, z);
}

// Projects a view-space position back to a depth-buffer UV (the inverse of
// the X/Y mapping in ViewPositionAt). Valid for positions in front of the
// eye (z > 0).
vec2 UvFromView(vec3 p) {
  vec2 ndc = vec2(p.x / (p.z * ssr.proj.x), p.y / (p.z * ssr.proj.y));
  return vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
}

// Un-premultiplies a sampled premultiplied-alpha color.
vec3 Unpremultiply(vec4 c) { return c.a > 0.0 ? c.rgb / c.a : vec3(0.0); }

void main() {
  float near = ssr.proj.z;
  float far = ssr.proj.w;
  float max_distance = ssr.march.x;
  float thickness = ssr.march.y;
  float start_bias = ssr.march.z;
  int step_count = int(ssr.march.w);
  float intensity = ssr.params.x;
  int debug_view = int(ssr.params.y + 0.5);
  float blur = ssr.params.z;

  vec4 base = texture(input_color, v_uv);
  vec4 depth_sample = texture(linear_depth, v_uv);
  vec3 origin = ViewPositionAt(v_uv);

  // Debug views, evaluated before any early-out so they show what the trace
  // actually reads.
  if (debug_view == 5) {
    float g = depth_sample.r / far;
    frag_color = vec4(vec3(g), 1.0);
    return;
  }
  if (debug_view == 3) {
    vec3 dn = normalize(depth_sample.gba);
    frag_color = vec4(dn * 0.5 + 0.5, 1.0);
    return;
  }

  // Background texels (no geometry) reflect nothing.
  if (origin.z >= far) {
    frag_color = base;
    return;
  }

  // The smooth, interpolated view-space normal written by the depth prepass
  // (in green/blue/alpha). Using the shaded vertex normal rather than one
  // reconstructed from depth keeps reflections smooth across curved
  // surfaces instead of faceted per triangle.
  vec3 normal = normalize(depth_sample.gba);

  // View-space reflection of the eye-to-pixel ray about the surface normal.
  vec3 incident = normalize(origin);
  vec3 reflection = reflect(incident, normal);

  // March the reflected ray in screen space: project the ray's start and end
  // to UVs and walk the screen-space segment in equal steps. View-space
  // depth is recovered per step from a perspective-correct interpolation of
  // 1/z, which is linear across the screen.
  vec3 ray_start = origin + normal * start_bias;
  vec3 ray_end = ray_start + reflection * max_distance;
  // Clip the segment to the near plane so the projection stays in front of
  // the eye (z > near).
  if (ray_end.z < near) {
    float t = (near - ray_start.z) / (ray_end.z - ray_start.z);
    ray_end = mix(ray_start, ray_end, clamp(t, 0.0, 1.0));
  }

  vec2 uv_start = UvFromView(ray_start);
  vec2 uv_end = UvFromView(ray_end);
  float inv_z_start = 1.0 / ray_start.z;
  float inv_z_end = 1.0 / ray_end.z;

  float confidence = 0.0;
  vec2 hit_uv = vec2(0.0);
  // Parameter [0,1] of the accepted hit along the ray, used to widen the
  // glossy blur with distance.
  float hit_t = 0.0;
  // Parameter of the previous sample, the near end of the refine bracket.
  float prev_t = 0.0;

  for (int i = 1; i <= MAX_SSR_STEPS; i++) {
    if (i > step_count) {
      break;
    }
    float t = float(i) / float(step_count);
    vec2 uv = mix(uv_start, uv_end, t);
    // Stop when the ray leaves the screen.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
      break;
    }
    // Perspective-correct view-space depth of the ray at this screen point.
    float ray_z = 1.0 / mix(inv_z_start, inv_z_end, t);
    float scene_z = texture(linear_depth, uv).r;
    // Skip background (sky) texels: no geometry to reflect there.
    if (scene_z >= far) {
      prev_t = t;
      continue;
    }
    float delta = ray_z - scene_z;
    // Accept only a crossing within the surface's assumed thickness. A
    // crossing beyond it means the ray passed behind a nearer occluder into
    // open space, so keep marching: that is what lets a reflection reach an
    // object standing behind a closer one (rather than stopping at the
    // first surface the ray goes behind).
    if (delta > 0.0 && delta < thickness) {
      // Binary-search the exact crossing between the last sample and this
      // one, so the hit is pinned far more precisely than the coarse step,
      // removing most of the per-step banding.
      float lo = prev_t;
      float hi = t;
      for (int j = 0; j < MAX_SSR_REFINE_STEPS; j++) {
        float mid = 0.5 * (lo + hi);
        vec2 muv = mix(uv_start, uv_end, mid);
        float mz = 1.0 / mix(inv_z_start, inv_z_end, mid);
        if (mz - texture(linear_depth, muv).r > 0.0) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      vec2 candidate_uv = mix(uv_start, uv_end, hi);

      // Backface rejection. A real reflection lands on a surface that faces
      // the incoming ray. When the surface at the hit faces away, the ray
      // passed behind a nearer object in screen space, so the color here is
      // that occluder's, not the reflected surface's. Reject it and keep
      // marching (so a valid surface further along can still be found, and
      // if none is, the pixel falls back to its image-based reflection).
      vec3 hit_normal = normalize(texture(linear_depth, candidate_uv).gba);
      float facing_hit = -dot(reflection, hit_normal);
      if (facing_hit > 0.0) {
        hit_t = hi;
        hit_uv = candidate_uv;
        // Confidence fades the reflection where it is least reliable: a thin
        // band at the screen border (a hit there has no off-screen data
        // behind it), toward the end of the march so reflections taper off
        // with distance instead of ending in a hard line, and at grazing
        // hits where the ray skims the surface.
        vec2 edge = clamp(min(hit_uv, 1.0 - hit_uv) / kEdgeFade, 0.0, 1.0);
        float edge_fade = smoothstep(0.0, 1.0, edge.x) *
                          smoothstep(0.0, 1.0, edge.y);
        float distance_fade = 1.0 - smoothstep(0.7, 1.0, hit_t);
        float face_fade = smoothstep(0.0, 0.25, facing_hit);
        confidence = edge_fade * distance_fade * face_fade;
        break;
      }
    }
    prev_t = t;
  }

  if (debug_view == 1) {
    frag_color = vec4(hit_uv * confidence, 0.0, 1.0);
    return;
  }
  if (debug_view == 2) {
    frag_color = vec4(vec3(confidence > 0.0 ? 1.0 : 0.0), 1.0);
    return;
  }
  if (debug_view == 4) {
    frag_color = vec4(vec3(confidence), 1.0);
    return;
  }

  if (confidence <= 0.0) {
    frag_color = base;
    return;
  }

  // Fresnel weight (Schlick): reflections strengthen at grazing angles.
  // TODO(ssr): drive the reflection strength from per-pixel reflectivity and
  // roughness (a thin reflectivity prepass) instead of a global intensity.
  float facing = clamp(dot(normal, -incident), 0.0, 1.0);
  float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
  float strength = clamp(confidence * intensity * fresnel, 0.0, 1.0);

  // Glossy blur of the reflected color. The radius grows with the blur
  // strength and the hit distance, so a rougher surface (or a more distant
  // reflection) softens, which also hides the noise the trace produces at
  // grazing contact points. A zero strength keeps a single sharp tap.
  vec3 reflected_rgb;
  if (blur <= 0.0) {
    reflected_rgb = Unpremultiply(texture(input_color, hit_uv));
  } else {
    float radius = blur * (0.004 + 0.03 * hit_t);
    vec3 sum = vec3(0.0);
    for (int k = 0; k < SSR_BLUR_TAPS; k++) {
      float tap_radius =
          sqrt((float(k) + 0.5) / float(SSR_BLUR_TAPS)) * radius;
      float theta = float(k) * kGoldenAngle;
      vec2 offset = vec2(cos(theta), sin(theta)) * tap_radius;
      sum += Unpremultiply(texture(input_color, hit_uv + offset));
    }
    reflected_rgb = sum / float(SSR_BLUR_TAPS);
  }

  vec3 base_rgb = Unpremultiply(base);
  vec3 out_rgb = mix(base_rgb, reflected_rgb, strength);
  frag_color = vec4(out_rgb * base.a, base.a);
}
