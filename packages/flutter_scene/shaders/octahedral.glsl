// Octahedral packing for unit vectors in two [0, 1] channels.
//
// The encode flips the vector so directions facing the camera (view-space
// -Z, the common case for bent normals) land in the seam-free center of the
// map, keeping the blur's linear filtering off the wrap boundary.

vec2 OctSign(vec2 v) {
  return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0);
}

vec2 OctEncode(vec3 n) {
  n = -n;
  n /= abs(n.x) + abs(n.y) + abs(n.z);
  vec2 e = n.z >= 0.0 ? n.xy : (1.0 - abs(n.yx)) * OctSign(n.xy);
  return e * 0.5 + 0.5;
}

vec3 OctDecode(vec2 e) {
  e = e * 2.0 - 1.0;
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * OctSign(n.xy);
  }
  return -normalize(n);
}
