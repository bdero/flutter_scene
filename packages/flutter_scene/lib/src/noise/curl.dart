// Curl noise for particle advection, built on the FastNoiseLite port.
//
// A vector potential is assembled from three seeded single-octave
// OpenSimplex2 3D fields (seed, seed + 1, seed + 2), and its curl is taken
// with central differences. The curl of any smooth field is divergence
// free, which is what makes particles advected along it swirl without
// clumping.
//
// The GLSL counterpart in noise.glsl (NoiseCurl3) uses the same
// construction, the same seeds, and the same epsilon, so the two agree
// within the float tolerance of the underlying noise. Coordinates are taken
// pre-scaled (no frequency parameter), matching the stateless GLSL side.

import 'package:flutter_scene/src/noise/fast_noise_lite.dart';

final FastNoiseLite _curlNoise = FastNoiseLite()..frequency = 1.0;

double _potential(int seed, double x, double y, double z) {
  _curlNoise.seed = seed;
  return _curlNoise.getNoise3(x, y, z);
}

/// The curl of a seeded vector noise field at the pre-scaled position
/// ([x], [y], [z]).
///
/// Components are roughly in [-1, 1] divided by [epsilon]'s scale; advect
/// particles by adding `curl * speed * dt`. [epsilon] is the central
/// difference half-step; smaller values sharpen the field and amplify the
/// CPU/GPU float divergence proportionally. Matches the GLSL
/// `NoiseCurl3(vec3(x, y, z), seed, epsilon)`.
/// {@category Noise}
({double x, double y, double z}) noiseCurl3(
  double x,
  double y,
  double z, {
  int seed = 1337,
  double epsilon = 0.25,
}) {
  final inv = 1.0 / (2.0 * epsilon);

  // Partial derivatives of the three potential components.
  final p0y1 = _potential(seed, x, y + epsilon, z);
  final p0y0 = _potential(seed, x, y - epsilon, z);
  final p0z1 = _potential(seed, x, y, z + epsilon);
  final p0z0 = _potential(seed, x, y, z - epsilon);

  final p1x1 = _potential(seed + 1, x + epsilon, y, z);
  final p1x0 = _potential(seed + 1, x - epsilon, y, z);
  final p1z1 = _potential(seed + 1, x, y, z + epsilon);
  final p1z0 = _potential(seed + 1, x, y, z - epsilon);

  final p2x1 = _potential(seed + 2, x + epsilon, y, z);
  final p2x0 = _potential(seed + 2, x - epsilon, y, z);
  final p2y1 = _potential(seed + 2, x, y + epsilon, z);
  final p2y0 = _potential(seed + 2, x, y - epsilon, z);

  return (
    x: ((p2y1 - p2y0) - (p1z1 - p1z0)) * inv,
    y: ((p0z1 - p0z0) - (p2x1 - p2x0)) * inv,
    z: ((p1x1 - p1x0) - (p0y1 - p0y0)) * inv,
  );
}
