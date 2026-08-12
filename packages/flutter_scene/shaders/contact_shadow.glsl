// Screen-space contact shadow march, shared by the occlusion shaders.
//
// Marches the linear depth buffer from the shaded point toward the light
// over a short world distance. Where the depth field crosses in front of the
// ray within a thickness window, the point is in contact shadow. Catches the
// small-scale grounding that shadow-map resolution and bias miss.
//
// The including shader must declare the `linear_depth` sampler and define
// AO_INFO as the uniform block instance carrying `proj` (xy half-fov
// tangents, z near) and `contact` (xyz view-space direction toward the
// light, w the march distance in world units, 0 disables).

float MarchContactShadow(vec3 origin, float noise) {
  vec3 to_light = AO_INFO.contact.xyz;
  float max_distance = AO_INFO.contact.w;
  const int kContactSteps = 8;
  float step_length = max_distance / float(kContactSteps);
  // The occluder acceptance window. The near bias rejects self-intersection
  // with the surface the ray leaves; the thickness bound keeps far surfaces
  // from casting through the ray.
  float bias = 0.02 * max_distance;
  float thickness = 0.3 * max_distance;
  float occlusion = 0.0;
  for (int i = 0; i < kContactSteps; i++) {
    float t = (float(i) + noise) * step_length;
    vec3 p = origin + to_light * t;
    // Stop at the near plane; the depth buffer has nothing in front of it.
    if (p.z <= AO_INFO.proj.z) {
      break;
    }
    vec2 ndc = vec2(p.x / (p.z * AO_INFO.proj.x), p.y / (p.z * AO_INFO.proj.y));
    vec2 uv = vec2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
      break;
    }
    float scene_z = texture(linear_depth, uv).r;
    float delta = p.z - scene_z;
    if (delta > bias && delta < thickness) {
      // Taper by march distance so contact shadows fade out instead of
      // cutting at the range limit.
      occlusion = max(occlusion, 1.0 - t / max_distance);
    }
  }
  return 1.0 - occlusion;
}
