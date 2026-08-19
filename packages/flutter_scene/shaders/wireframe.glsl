// Antialiased coverage of a wireframe `width_px` pixels wide, from a
// barycentric attribute (see MeshData.unweld/UnweldAttribute.barycentric).
// 1 on an edge, 0 in the face interior.
float WireframeCoverage(vec3 bary, float width_px) {
  vec3 d = fwidth(bary);
  vec3 a = smoothstep(vec3(0.0), d * max(width_px, 1e-3), bary);
  return 1.0 - min(min(a.x, a.y), a.z);
}

// Screen-space distance to the nearest triangle edge, in pixels.
float EdgeDistancePixels(vec3 bary) {
  vec3 d = fwidth(bary);
  vec3 n = bary / max(d, vec3(1e-6));
  return min(min(n.x, n.y), n.z);
}
