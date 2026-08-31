// The wave field, which is the part of water that runs on every vertex on
// every frame. The load-bearing property is that the phase tables are an
// optimisation and nothing else: the surface they produce has to be the one
// the trig would have produced, to float precision.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A flat grid of `(n + 1)^2` points spanning [size].
Float32List restGrid(int n, double size) {
  final points = Float32List((n + 1) * (n + 1) * 3);
  final step = size / n;
  final half = size / 2;
  for (var z = 0; z <= n; z++) {
    for (var x = 0; x <= n; x++) {
      final v = (z * (n + 1) + x) * 3;
      points[v] = -half + x * step;
      points[v + 2] = -half + z * step;
    }
  }
  return points;
}

List<GerstnerWave> spectrum(int count) => [
  for (var i = 0; i < count; i++)
    GerstnerWave(
      direction: vm.Vector2(math.cos(i * 1.1), math.sin(i * 1.1)).normalized(),
      amplitude: 0.5 / (i + 1),
      wavelength: 12.0 / (i + 1),
      speed: 1.4 + i * 0.3,
    ),
];

void main() {
  test('the surface matches the analytic field it shares with gameplay', () {
    // A boat placed with surfaceHeightAt has to sit on the mesh, not near it,
    // so the two evaluations of the same spectrum have to agree.
    final rest = restGrid(16, 40);
    final waves = spectrum(3);
    final positions = Float32List(rest.length);
    final normals = Float32List(rest.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(waves, 2.75, positions, normals);

    // evaluateAt reports the offset from the rest point; the field writes
    // where the point ended up. Same surface, stated two ways.
    final analytic = WaterSurfaceComponent(waves: waves);
    for (var i = 0; i < rest.length ~/ 3; i += 7) {
      final at = vm.Vector2(rest[i * 3], rest[i * 3 + 2]);
      final expected = analytic.evaluateAt(at, 2.75);
      expect(
        positions[i * 3] - rest[i * 3],
        closeTo(expected.displacement.x, 1e-4),
      );
      expect(positions[i * 3 + 1], closeTo(expected.displacement.y, 1e-4));
      expect(
        positions[i * 3 + 2] - rest[i * 3 + 2],
        closeTo(expected.displacement.z, 1e-4),
      );
      expect(normals[i * 3 + 1], closeTo(expected.normal.y, 1e-3));
    }
  });

  test('a reused field answers the same as a fresh one', () {
    // The tables are what a reused field keeps. Frame two must not differ
    // from frame one of a field that never saw frame zero.
    final rest = restGrid(12, 30);
    final waves = spectrum(4);
    final reused = GerstnerField()..setRest(rest);
    final a = Float32List(rest.length);
    final n = Float32List(rest.length);
    for (final time in const [0.0, 0.5, 1.25]) {
      reused.displace(waves, time, a, n);
    }

    final fresh = Float32List(rest.length);
    final freshNormals = Float32List(rest.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(waves, 1.25, fresh, freshNormals);

    for (var i = 0; i < a.length; i++) {
      expect(a[i], closeTo(fresh[i], 1e-5), reason: 'position $i');
      expect(n[i], closeTo(freshNormals[i], 1e-5), reason: 'normal $i');
    }
  });

  test('changing a wavelength retabulates rather than going stale', () {
    final rest = restGrid(8, 20);
    final field = GerstnerField()..setRest(rest);
    final positions = Float32List(rest.length);
    final normals = Float32List(rest.length);

    field.displace(spectrum(2), 1.0, positions, normals);
    final before = Float32List.fromList(positions);

    final retuned = [
      GerstnerWave(
        direction: spectrum(2)[0].direction,
        amplitude: spectrum(2)[0].amplitude,
        wavelength: 3.0,
        speed: spectrum(2)[0].speed,
      ),
      spectrum(2)[1],
    ];
    field.displace(retuned, 1.0, positions, normals);

    final fresh = Float32List(rest.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(retuned, 1.0, fresh, normals);

    expect(positions, isNot(orderedEquals(before)));
    for (var i = 0; i < positions.length; i++) {
      expect(positions[i], closeTo(fresh[i], 1e-5));
    }
  });

  test('changing only amplitude keeps the tables', () {
    // Amplitude is applied per frame and moves nothing tabulated, so a
    // slider drag must not pay for a retabulation on every step.
    final rest = restGrid(8, 20);
    final field = GerstnerField()..setRest(rest);
    final positions = Float32List(rest.length);
    final normals = Float32List(rest.length);
    final base = spectrum(2);

    field.displace(base, 1.0, positions, normals);
    final tables = field.tableLength;

    field.displace(
      [
        GerstnerWave(
          direction: base[0].direction,
          amplitude: base[0].amplitude * 2,
          wavelength: base[0].wavelength,
          speed: base[0].speed,
        ),
        base[1],
      ],
      1.0,
      positions,
      normals,
    );

    expect(field.tableLength, tables);
    expect(positions[1], isNot(0.0));
  });

  test('a silent spectrum leaves the grid flat and the normals up', () {
    final rest = restGrid(6, 12);
    final positions = Float32List(rest.length);
    final normals = Float32List(rest.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(
        [GerstnerWave(direction: vm.Vector2(1, 0), amplitude: 0)],
        3.0,
        positions,
        normals,
      );

    for (var i = 0; i < rest.length; i++) {
      expect(positions[i], rest[i]);
    }
    for (var i = 0; i < rest.length ~/ 3; i++) {
      expect(normals[i * 3], 0);
      expect(normals[i * 3 + 1], 1);
      expect(normals[i * 3 + 2], 0);
    }
  });

  test('normalization is what makes a mesh and a query agree', () {
    // Two of four waves are silent. Normalizing by the two that are left
    // would make the surface steeper than the analytic query reports, so the
    // count of the whole spectrum is what divides.
    final rest = restGrid(6, 20);
    final waves = [
      ...spectrum(2),
      GerstnerWave(direction: vm.Vector2(1, 0), amplitude: 0),
      GerstnerWave(direction: vm.Vector2(0, 1), amplitude: 0),
    ];
    final byWhole = Float32List(rest.length);
    final byActive = Float32List(rest.length);
    final normals = Float32List(rest.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(waves, 1.0, byWhole, normals, normalization: waves.length);
    GerstnerField()
      ..setRest(rest)
      ..displace(waves, 1.0, byActive, normals, normalization: 2);

    final analytic = WaterSurfaceComponent(waves: waves);
    final at = vm.Vector2(rest[0], rest[2]);
    final expected = analytic.evaluateAt(at, 1.0).displacement;
    expect(byWhole[0] - rest[0], closeTo(expected.x, 1e-4));
    expect(byActive[0] - rest[0], isNot(closeTo(expected.x, 1e-4)));
  });

  test('a field with no grid does nothing rather than throwing', () {
    final positions = Float32List(9);
    final normals = Float32List(9);
    expect(GerstnerField().pointCount, 0);
    GerstnerField().displace(spectrum(2), 1, positions, normals);
    expect(positions.every((v) => v == 0), isTrue);
  });

  test('the tables cost two floats per point per wave', () {
    final rest = restGrid(10, 20);
    final field = GerstnerField()..setRest(rest);
    final positions = Float32List(rest.length);
    field.displace(spectrum(3), 0, positions, Float32List(rest.length));
    expect(field.pointCount, 121);
    expect(field.tableLength, 121 * 3 * 2);
  });
}
