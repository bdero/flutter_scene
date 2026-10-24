// The two workloads, over whichever SampleVolume(uvw) the variant includes.
// MODE_MIP ray-marches a maximum intensity projection; otherwise a planar
// reslice takes one trilinear sample per pixel. Both write the 16-bit value
// as gray.

in vec2 v_uv;

out vec4 frag_color;

#ifdef MODE_MIP
float Project(vec2 uv) {
  vec3 origin = params.camera_position.xyz;
  vec3 direction = normalize(params.camera_forward.xyz +
                             (uv.x * 2.0 - 1.0) * params.camera_right.xyz +
                             (uv.y * 2.0 - 1.0) * params.camera_up.xyz);
  // Clip the ray to the unit cube.
  vec3 inverse = 1.0 / (direction + vec3(1e-7));
  vec3 t0 = -origin * inverse;
  vec3 t1 = (vec3(1.0) - origin) * inverse;
  vec3 near = min(t0, t1);
  vec3 far = max(t0, t1);
  float enter = max(max(near.x, near.y), max(near.z, 0.0));
  float exit = min(min(far.x, far.y), far.z);
  float step_length = params.march.y;
  int steps = int(params.march.x);
  float projected = 0.0;
  for (int i = 0; i < 2048; i++) {
    float t = enter + (float(i) + 0.5) * step_length;
    if (i >= steps || t > exit) {
      break;
    }
    projected = max(projected, SampleVolume(origin + direction * t));
  }
  return projected;
}
#endif

void main() {
#ifdef MODE_MIP
  float value = Project(v_uv);
#else
  vec3 uvw = params.plane_origin.xyz + v_uv.x * params.plane_u.xyz +
             v_uv.y * params.plane_v.xyz;
  bool inside = all(greaterThanEqual(uvw, vec3(0.0))) &&
                all(lessThanEqual(uvw, vec3(1.0)));
  float value = inside ? SampleVolume(uvw) : 0.0;
#endif
  frag_color = vec4(vec3(value), 1.0);
}
