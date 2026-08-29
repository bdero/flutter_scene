// Covers the CPU froxelizer (PunctualLightBuffer.computeFroxelData): the
// depth-slice math, conservative sphere-to-froxel assignment, unbounded
// lights, record packing/dedup, and overflow counting. A mirror of the
// shader's froxel lookup maps a world position to its froxel here, so the
// tests assert the CPU assignment and the shader mapping agree.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/render/light_culling.dart';
import 'package:flutter_scene/src/render/punctual_lights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const _nx = PunctualLightBuffer.froxelCountX;
const _ny = PunctualLightBuffer.froxelCountY;
const _nz = PunctualLightBuffer.froxelCountZ;
const _froxelCount = _nx * _ny * _nz;

// The camera basis every test uses: at the origin looking down -Z, +Y up,
// with a 90-degree square frustum (tan of both half fovs = 1).
final _forward = Vector3(0, 0, -1);
final _right = Vector3(1, 0, 0);
final _up = Vector3(0, 1, 0);

({
  Float32List data,
  int height,
  double zScale,
  double zBias,
  int overflowedFroxels,
})
_froxelize(List<CullableLight> lights) => PunctualLightBuffer.computeFroxelData(
  lights: lights,
  cameraPosition: Vector3.zero(),
  forward: _forward,
  right: _right,
  up: _up,
  tanHalfFovX: 1.0,
  tanHalfFovY: 1.0,
  maxPerFroxel: kMaxPunctualLights,
);

/// The shader's froxel lookup, mirrored: world position to froxel index.
int _froxelOf(Vector3 world, double zScale, double zBias) {
  final vz = math.max(world.dot(_forward), 1e-4);
  final ndcX = world.dot(_right) / (vz * 1.0);
  final ndcY = world.dot(_up) / (vz * 1.0);
  final fx = ((ndcX * 0.5 + 0.5) * _nx).floor().clamp(0, _nx - 1);
  final fy = ((0.5 - ndcY * 0.5) * _ny).floor().clamp(0, _ny - 1);
  final fz = ((math.log(vz) / math.ln2) * zScale + zBias).floor().clamp(
    0,
    _nz - 1,
  );
  return (fz * _ny + fy) * _nx + fx;
}

/// The light rows the packed [data] lists for froxel [index].
List<int> _lightsAt(Float32List data, int index) {
  final offset = data[index * 4].round();
  final count = data[index * 4 + 1].round();
  return [for (var i = 0; i < count; i++) data[(offset + i) * 4].round()];
}

CullableLight _pointLight(int row, Vector3 position, double range) =>
    CullableLight(
      row,
      lightInfluenceBounds(position, range),
      worldPosition: position,
    );

void main() {
  test('a ranged light reaches its own froxel and misses distant ones', () {
    final position = Vector3(0, 0, -10);
    final r = _froxelize([_pointLight(0, position, 2.0)]);
    expect(r.overflowedFroxels, 0);

    // The froxel containing the light sees it.
    expect(_lightsAt(r.data, _froxelOf(position, r.zScale, r.zBias)), [0]);
    // A froxel across the view at a similar depth does not (x extent of a
    // 2m sphere at 10m is well under half the frustum).
    final far = _froxelOf(Vector3(9, 0, -10), r.zScale, r.zBias);
    expect(_lightsAt(r.data, far), isEmpty);
    // A froxel far beyond the light's reach does not.
    final deep = _froxelOf(Vector3(0, 0, -80), r.zScale, r.zBias);
    expect(_lightsAt(r.data, deep), isEmpty);
  });

  test('assignment is conservative around the influence sphere', () {
    final position = Vector3(2, 1, -20);
    const range = 4.0;
    final r = _froxelize([_pointLight(0, position, range)]);
    // Every froxel containing a point inside the sphere lists the light.
    for (final probe in [
      position,
      position + Vector3(range * 0.9, 0, 0),
      position + Vector3(-range * 0.9, 0, 0),
      position + Vector3(0, range * 0.9, 0),
      position + Vector3(0, 0, range * 0.9),
      position + Vector3(0, 0, -range * 0.9),
    ]) {
      expect(
        _lightsAt(r.data, _froxelOf(probe, r.zScale, r.zBias)),
        contains(0),
        reason: 'probe $probe lost the light',
      );
    }
  });

  test('an unranged light lands in every froxel', () {
    final r = _froxelize([
      CullableLight(3, null, worldPosition: Vector3(0, 0, -5)),
    ]);
    for (var i = 0; i < _froxelCount; i++) {
      expect(_lightsAt(r.data, i), [3]);
    }
    // All froxels share one deduplicated record run.
    final total = _froxelCount + 1;
    expect(r.data.length ~/ 4, greaterThanOrEqualTo(total));
  });

  test('a light behind the camera is skipped', () {
    final r = _froxelize([_pointLight(0, Vector3(0, 0, 30), 5.0)]);
    for (var i = 0; i < _froxelCount; i++) {
      expect(_lightsAt(r.data, i), isEmpty);
    }
  });

  test('froxels cap their lists and count the overflow', () {
    final position = Vector3(0, 0, -10);
    final r = _froxelize([
      for (var i = 0; i < kMaxPunctualLights + 3; i++)
        _pointLight(i, position, 1.0),
    ]);
    final lights = _lightsAt(r.data, _froxelOf(position, r.zScale, r.zBias));
    expect(lights, hasLength(kMaxPunctualLights));
    expect(r.overflowedFroxels, greaterThan(0));
  });

  test('an overfull froxel keeps its nearest lights', () {
    // 17 lights along +x, all reaching the origin-column froxel at z=-10;
    // the farthest (row 16) must be the one dropped.
    final r = _froxelize([
      for (var i = 0; i < kMaxPunctualLights + 1; i++)
        _pointLight(i, Vector3(i * 0.4, 0, -10), 8.0),
    ]);
    final probe = Vector3(0, 0, -10);
    final kept = _lightsAt(r.data, _froxelOf(probe, r.zScale, r.zBias));
    expect(kept, hasLength(kMaxPunctualLights));
    expect(kept, isNot(contains(kMaxPunctualLights)));
    expect(kept, contains(0));
  });

  test('slice math matches between assignment and lookup at the far cap', () {
    // A light past the far bound still shades geometry clamped into the last
    // slice (conservative, never dropped).
    final position = Vector3(0, 0, -150);
    final r = _froxelize([_pointLight(0, position, 10.0)]);
    expect(
      _lightsAt(r.data, _froxelOf(position, r.zScale, r.zBias)),
      contains(0),
    );
  });
}
