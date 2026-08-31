// What the water surface costs per frame, measured rather than guessed.
//
// The wave field runs on every vertex of the surface on every frame, so it is
// the one part of water whose cost is a design constraint rather than a
// detail. Skipped unless FLUTTER_SCENE_BENCH is set: the result is a number
// to read, not a thing to assert.
//
//   flutter test --dart-define=FLUTTER_SCENE_BENCH=1 \
//     test/benchmark/water_benchmark_test.dart
//
// Runs in the test VM, which is JIT. An AOT release build is typically 1.5x
// to 3x faster on this kind of scalar float loop.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _enabled = bool.hasEnvironment('FLUTTER_SCENE_BENCH');

/// One frame at 60 Hz, the budget this is measured against.
const double _frameMs = 16.67;

void bench(
  String label,
  void Function() body, {
  int runs = 20,
  int warmup = 5,
}) {
  for (var i = 0; i < warmup; i++) {
    body();
  }
  var best = double.infinity;
  final watch = Stopwatch();
  for (var i = 0; i < runs; i++) {
    watch
      ..reset()
      ..start();
    body();
    watch.stop();
    final ms = watch.elapsedMicroseconds / 1000;
    if (ms < best) best = ms;
  }
  // ignore: avoid_print
  print(
    '  ${label.padRight(46)} ${best.toStringAsFixed(3).padLeft(9)} ms'
    '  ${(best / _frameMs * 100).toStringAsFixed(1).padLeft(6)}% of a frame',
  );
}

/// A flat grid of `(n + 1)^2` points spanning [size], the water at rest.
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

/// The straightforward way: derive the phase and call sin and cos for every
/// point of every wave, every frame.
///
/// Kept as the thing [GerstnerField] is measured against, so the phase tables
/// have to keep earning the memory they cost.
void displaceWithTrig(
  Float32List rest,
  List<GerstnerWave> waves,
  double time,
  Float32List positions,
  Float32List normals,
) {
  final count = rest.length ~/ 3;
  for (var i = 0; i < count; i++) {
    final x = rest[i * 3];
    final z = rest[i * 3 + 2];
    var px = x, py = 0.0, pz = z;
    var tx = 1.0, ty = 0.0, tz = 0.0;
    var bx = 0.0, by = 0.0, bz = 1.0;
    for (final wave in waves) {
      final k = 2 * math.pi / wave.wavelength;
      final dx = wave.direction.x;
      final dz = wave.direction.y;
      final a = wave.amplitude;
      final q = wave.steepness / (k * a * waves.length);
      final phase =
          k * (dx * x + dz * z) - (wave.speed * math.sqrt(9.81 / k) * k) * time;
      final cosP = math.cos(phase);
      final sinP = math.sin(phase);
      final qa = q * a;
      final ka = k * a;
      px += qa * dx * cosP;
      py += a * sinP;
      pz += qa * dz * cosP;
      tx += -q * dx * dx * ka * sinP;
      ty += dx * ka * cosP;
      tz += -q * dx * dz * ka * sinP;
      bx += -q * dx * dz * ka * sinP;
      by += dz * ka * cosP;
      bz += -q * dz * dz * ka * sinP;
    }
    positions[i * 3] = px;
    positions[i * 3 + 1] = py;
    positions[i * 3 + 2] = pz;
    var nx = by * tz - bz * ty;
    var ny = bz * tx - bx * tz;
    var nz = bx * ty - by * tx;
    final length = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (length > 1e-9) {
      final inverse = 1 / length;
      nx *= inverse;
      ny *= inverse;
      nz *= inverse;
    }
    normals[i * 3] = nx;
    normals[i * 3 + 1] = ny;
    normals[i * 3 + 2] = nz;
  }
}

void main() {
  if (!_enabled) {
    test('water benchmarks', () {}, skip: 'Set FLUTTER_SCENE_BENCH=1.');
    return;
  }

  test('water', () {
    // ignore: avoid_print
    print('\nWater: displacing the surface grid, per frame');
    for (final resolution in const [32, 48, 96, 160]) {
      for (final waveCount in const [3, 6]) {
        final rest = restGrid(resolution, 60);
        final positions = Float32List(rest.length);
        final normals = Float32List(rest.length);
        final waves = spectrum(waveCount);
        final field = GerstnerField()..setRest(rest);
        var time = 0.0;
        bench('${resolution}x$resolution, $waveCount waves '
            '(${rest.length ~/ 3} points)', () {
          time += 1 / 60;
          field.displace(waves, time, positions, normals);
        });
      }
    }

    // ignore: avoid_print
    print('\nWater: the same work with the trig left in the loop');
    for (final resolution in const [96, 160]) {
      for (final waveCount in const [3, 6]) {
        final rest = restGrid(resolution, 60);
        final positions = Float32List(rest.length);
        final normals = Float32List(rest.length);
        final waves = spectrum(waveCount);
        var time = 0.0;
        bench('${resolution}x$resolution, $waveCount waves: direct trig', () {
          time += 1 / 60;
          displaceWithTrig(rest, waves, time, positions, normals);
        });
      }
    }

    // ignore: avoid_print
    print('\nWater: the one-off the per-frame saving is bought with');
    for (final resolution in const [96, 160]) {
      final rest = restGrid(resolution, 60);
      final positions = Float32List(rest.length);
      final normals = Float32List(rest.length);
      final waves = spectrum(3);
      bench(
        '${resolution}x$resolution, 3 waves: first frame',
        () {
          GerstnerField()
            ..setRest(rest)
            ..displace(waves, 1.0, positions, normals);
        },
        runs: 8,
        warmup: 2,
      );
      final field = GerstnerField()..setRest(rest);
      field.displace(waves, 0, positions, normals);
      // ignore: avoid_print
      print(
        '  ${'${resolution}x$resolution, 3 waves: phase tables'.padRight(46)} '
        '${(field.tableLength * 4 / 1024).toStringAsFixed(0).padLeft(9)} KB',
      );
    }

    // ignore: avoid_print
    print('\nWater: the analytic query (buoyancy, placement)');
    final surface = WaterSurfaceComponent(waves: spectrum(3));
    bench('1000 evaluateAt calls', () {
      for (var i = 0; i < 1000; i++) {
        surface.evaluateAt(vm.Vector2(i * 0.13, i * 0.07), 1.0);
      }
    });
  });
}
