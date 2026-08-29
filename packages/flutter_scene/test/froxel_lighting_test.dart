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
  maxPerFroxel: kMaxFroxelLights,
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
      for (var i = 0; i < kMaxFroxelLights + 3; i++)
        _pointLight(i, position, 1.0),
    ]);
    final lights = _lightsAt(r.data, _froxelOf(position, r.zScale, r.zBias));
    expect(lights, hasLength(kMaxFroxelLights));
    expect(r.overflowedFroxels, greaterThan(0));
  });

  test('no interior point of any influence sphere escapes coverage', () {
    // The regression behind the visible bugs: the old tile rect projected
    // center-at-light-depth plus extent-at-near-face, which undercovers by
    // vx*r/(vz*(vz-r)) and made off-center lights cut off on the ground up
    // close and vanish outright at distance. Sample many spheres (biased
    // toward the screen edges and long ranges, where the old math failed)
    // and many interior points of each; every point must land in a covered
    // froxel.
    // A realistic viewport (45-degree vertical fov, wide aspect); the tile
    // grid lives in ndc, so a narrow fov amplifies the old formula's tan-space
    // deficit past a whole tile where a square 90-degree frustum hides it.
    const tanX = 0.8;
    const tanY = 0.414;
    final random = math.Random(42);
    for (var trial = 0; trial < 300; trial++) {
      final vz = 1.0 + random.nextDouble() * 180.0;
      final vx = (random.nextDouble() * 2.4 - 1.2) * vz * tanX;
      final vy = (random.nextDouble() * 2.4 - 1.2) * vz * tanY;
      final radius = 1.0 + random.nextDouble() * 30.0;
      final position = Vector3(vx, vy, -vz);
      final result = PunctualLightBuffer.computeFroxelData(
        lights: [_pointLight(7, position, radius)],
        cameraPosition: Vector3.zero(),
        forward: _forward,
        right: _right,
        up: _up,
        tanHalfFovX: tanX,
        tanHalfFovY: tanY,
        maxPerFroxel: kMaxFroxelLights,
      );
      int froxelOf(Vector3 world) {
        final depth = math.max(world.dot(_forward), 1e-4);
        final ndcX = world.dot(_right) / (depth * tanX);
        final ndcY = world.dot(_up) / (depth * tanY);
        final fx = ((ndcX * 0.5 + 0.5) * _nx).floor().clamp(0, _nx - 1);
        final fy = ((0.5 - ndcY * 0.5) * _ny).floor().clamp(0, _ny - 1);
        final fz = ((math.log(depth) / math.ln2) * result.zScale + result.zBias)
            .floor()
            .clamp(0, _nz - 1);
        return (fz * _ny + fy) * _nx + fx;
      }

      for (var sample = 0; sample < 40; sample++) {
        final direction = Vector3(
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
          random.nextDouble() * 2 - 1,
        );
        if (direction.length2 < 1e-6) continue;
        direction.normalize();
        final probe =
            position + direction * (radius * 0.98 * random.nextDouble());
        if (probe.z > -0.01) continue; // In front of the camera only.
        expect(
          _lightsAt(result.data, froxelOf(probe)),
          contains(7),
          reason: 'light $position r=$radius lost at probe $probe',
        );
      }
    }
  });

  test('the center-plus-extent regression configuration stays covered', () {
    // A configuration the old tile rect (center at light depth, extent at
    // the near face) missed by a whole tile, found by brute-force scan; the
    // corner projection covers it. This was the visible bug, ground seams
    // near dense lights and off-center lights vanishing at distance.
    const tanX = 0.8;
    const tanY = 0.414;
    final position = Vector3(17.6, -9.108, -22.0);
    final result = PunctualLightBuffer.computeFroxelData(
      lights: [_pointLight(0, position, 2.0)],
      cameraPosition: Vector3.zero(),
      forward: _forward,
      right: _right,
      up: _up,
      tanHalfFovX: tanX,
      tanHalfFovY: tanY,
      maxPerFroxel: kMaxFroxelLights,
    );
    final probe = Vector3(16.415, -9.108, -23.485);
    final depth = -probe.z;
    final fx = ((probe.x / (depth * tanX) * 0.5 + 0.5) * _nx).floor().clamp(
      0,
      _nx - 1,
    );
    final fy = ((0.5 - probe.y / (depth * tanY) * 0.5) * _ny).floor().clamp(
      0,
      _ny - 1,
    );
    final fz = ((math.log(depth) / math.ln2) * result.zScale + result.zBias)
        .floor()
        .clamp(0, _nz - 1);
    expect(_lightsAt(result.data, (fz * _ny + fy) * _nx + fx), contains(0));
  });

  test('an off-center distant light still reaches its own froxel', () {
    // The reported symptom shape: a wide-fov edge-of-screen lamp far from
    // the camera. With the old rect math its entire influence missed the
    // covered tiles and the light popped out of existence.
    final position = Vector3(80, 0, -90);
    final r = _froxelize([_pointLight(0, position, 25.0)]);
    expect(
      _lightsAt(r.data, _froxelOf(position, r.zScale, r.zBias)),
      contains(0),
    );
    expect(
      _lightsAt(
        r.data,
        _froxelOf(position + Vector3(20, 0, 0), r.zScale, r.zBias),
      ),
      contains(0),
    );
  });

  test('a dense cluster within the froxel budget is never truncated', () {
    // The Bistro regression: worst-case unions of 21-28 lights reach single
    // far froxels, and the old 16-per-froxel budget truncated them into
    // tile-shaped lighting seams. The froxel budget must hold such clusters
    // whole.
    final r = _froxelize([
      for (var i = 0; i < 26; i++)
        _pointLight(
          i,
          Vector3((i % 6) * 2.0 - 5.0, 0, -20.0 - i ~/ 6 * 2.0),
          25.0,
        ),
    ]);
    expect(r.overflowedFroxels, 0);
    final probe = Vector3(0, 0, -22);
    expect(
      _lightsAt(r.data, _froxelOf(probe, r.zScale, r.zBias)),
      hasLength(26),
    );
  });

  test('an overfull froxel keeps its nearest lights', () {
    // One more light than the budget, all reaching the origin-column froxel
    // at z=-10; the farthest must be the one dropped.
    final r = _froxelize([
      for (var i = 0; i < kMaxFroxelLights + 1; i++)
        _pointLight(i, Vector3(i * 0.01, 0, -10), 12.0),
    ]);
    final probe = Vector3(0, 0, -10);
    final kept = _lightsAt(r.data, _froxelOf(probe, r.zScale, r.zBias));
    expect(kept, hasLength(kMaxFroxelLights));
    expect(kept, isNot(contains(kMaxFroxelLights)));
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
