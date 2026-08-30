// The layout contract shared by the prefiltered-radiance producer
// (env_prefilter.dart), the shaders that sample it (shaders/texture.glsl), and
// the importer that ingests a pre-baked one (material/ibl_ktx2.dart).
//
// Pure math, no GPU imports, so the importer's parse and resample can run on a
// background isolate and be tested headless.

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// Number of roughness bands in a prefiltered-radiance atlas (band 0 =
/// mirror, band `kPrefilterBandCount - 1` = fully rough; band `i` covers
/// perceptual roughness `i / (kPrefilterBandCount - 1)`).
///
/// Must match `kPrefilterBands` in `shaders/texture.glsl`. The shader derives
/// its sampling lod from this constant alone, so a radiance cube always stores
/// exactly this many mip levels regardless of its face size.
/// {@category Lighting and environment}
const int kPrefilterBandCount = 8;

/// Equirectangular width of a single roughness band in the atlas.
const int kPrefilterBandWidth = 512;

/// Equirectangular height of a single roughness band in the atlas.
///
/// Must match `kPrefilterBandHeight` in `shaders/texture.glsl`.
const int kPrefilterBandHeight = 256;

/// Default width (and height) of the prefiltered radiance cube's base mip.
/// Sizes the convolved reflection/ambient cube, not the visible background
/// (which samples the full-resolution source); see
/// `EnvironmentMap.radianceCubeSize`.
const int kRadianceCubeSize = 512;

/// The smallest cube face size that can hold [kPrefilterBandCount] mip levels.
/// A texture of size `S` supports `floor(log2(S))` mip levels, so the cube must
/// be at least `2^kPrefilterBandCount` to store one roughness band per mip; a
/// smaller request would fail texture creation (`mipLevelCount out of range`).
const int kMinRadianceCubeSize = 1 << kPrefilterBandCount;

/// The perceptual roughness mip level [band] of a radiance cube is prefiltered
/// for. Linear in the band index, matching the shader's
/// `lod = roughness * (kPrefilterBands - 1)`.
double radianceBandRoughness(int band) => band / (kPrefilterBandCount - 1);

// Cube face world bases (right, up, forward), in flutter_gpu cube slice order
// (+X, -X, +Y, -Y, +Z, -Z). A face texel at (u, v) (v measured top-down, as
// FullscreenVertex emits) maps to normalize(forward + (2u-1)*right +
// (2v-1)*up), the same direction the hardware samplerCube reads back, so a
// baked direction round-trips. Verified against rendered reflections.
//
// This is the Khronos/Vulkan/GL cube convention verbatim, which is also what
// KTX2 stores, so an imported cubemap's faces need no reordering or flipping.
final List<(Vector3, Vector3, Vector3)> cubeFaceBases = [
  (Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(1, 0, 0)), // +X
  (Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(-1, 0, 0)), // -X
  (Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), // +Y
  (Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)), // -Y
  (Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), // +Z
  (Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), // -Z
];

/// The unit direction a hardware `samplerCube` reads back for texel ([u], [v])
/// of cube slice [face], with [u]/[v] in `[0, 1]` and [v] measured top-down
/// (row 0 of the face's stored image is `v = 0`).
Vector3 radianceCubeFaceDirection(int face, double u, double v) {
  final (right, up, forward) = cubeFaceBases[face];
  final s = 2.0 * u - 1.0;
  final t = 2.0 * v - 1.0;
  return Vector3(
    forward.x + s * right.x + t * up.x,
    forward.y + s * right.y + t * up.y,
    forward.z + s * right.z + t * up.z,
  )..normalize();
}

/// The cube slice and face texel coordinates a `samplerCube` would read for
/// [direction]. The inverse of [radianceCubeFaceDirection]; [u]/[v] are in
/// `[0, 1]` with [v] top-down and may sit slightly outside on the seam.
({int face, double u, double v}) radianceCubeFaceCoords(Vector3 direction) {
  var bestFace = 0;
  var bestAxis = double.negativeInfinity;
  for (var face = 0; face < cubeFaceBases.length; face++) {
    final axis = direction.dot(cubeFaceBases[face].$3);
    if (axis > bestAxis) {
      bestAxis = axis;
      bestFace = face;
    }
  }
  final (right, up, forward) = cubeFaceBases[bestFace];
  final major = direction.dot(forward);
  // A direction orthogonal to every face normal cannot happen for a unit
  // vector, but a zero vector would divide by zero; pin it to the face center.
  if (major <= 0.0) return (face: bestFace, u: 0.5, v: 0.5);
  return (
    face: bestFace,
    u: 0.5 * (direction.dot(right) / major) + 0.5,
    v: 0.5 * (direction.dot(up) / major) + 0.5,
  );
}

// Reciprocals of 2*pi and pi, matching kInvAtan in shaders/texture.glsl.
const double _invTwoPi = 0.15915494309189535;
const double _invPi = 0.3183098861837907;

/// The equirectangular UV the shader's `SphericalToEquirectangular` maps
/// [direction] to.
({double u, double v}) directionToEquirectUv(Vector3 direction) => (
  u: math.atan2(direction.z, direction.x) * _invTwoPi + 0.5,
  v: math.asin(direction.y.clamp(-1.0, 1.0)) * _invPi + 0.5,
);

/// The unit direction an equirectangular ([u], [v]) samples, the inverse of
/// [directionToEquirectUv] (the shader's `EquirectangularToSpherical`).
Vector3 equirectUvToDirection(double u, double v) {
  final phi = (u - 0.5) / _invTwoPi;
  final latitude = (v - 0.5) / _invPi;
  final cosLatitude = math.cos(latitude);
  return Vector3(
    cosLatitude * math.cos(phi),
    math.sin(latitude),
    cosLatitude * math.sin(phi),
  );
}
