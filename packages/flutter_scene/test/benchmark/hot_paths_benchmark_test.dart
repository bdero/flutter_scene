// Where the CPU actually goes, measured rather than guessed.
//
// Not a correctness test: it prints timings so a decision about moving work
// to native code can be made against numbers. Skipped unless
// FLUTTER_SCENE_BENCH is set, because a timing run is slow and its result is
// a number to read, not a thing to assert.
//
//   FLUTTER_SCENE_BENCH=1 flutter test test/benchmark/hot_paths_benchmark_test.dart
//
// Runs in the test VM, which is JIT. An AOT release build is typically 1.5x
// to 3x faster on this kind of scalar float loop, so treat every number here
// as a pessimistic bound.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/flow.dart';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/navigation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/geometry/triangle_bvh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _enabled = bool.hasEnvironment('FLUTTER_SCENE_BENCH');

/// One frame at 60 Hz, the budget everything per-frame is measured against.
const double _frameMs = 16.67;

/// Runs [body] [runs] times after [warmup] untimed runs, and reports the best
/// time. The best rather than the mean: this is measuring how fast the code
/// can go, and the tail is the machine's other work, not the code's.
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
  final share = best / _frameMs * 100;
  // ignore: avoid_print
  print(
    '  ${label.padRight(46)} ${best.toStringAsFixed(3).padLeft(9)} ms'
    '  ${share.toStringAsFixed(1).padLeft(6)}% of a 60 Hz frame',
  );
}

void section(String name) {
  // ignore: avoid_print
  print('\n$name');
}

/// A rippled grid of triangles, the stand-in for a dense mesh.
(Float32List, Uint32List) grid(int n) {
  final positions = Float32List((n + 1) * (n + 1) * 3);
  for (var j = 0; j <= n; j++) {
    for (var i = 0; i <= n; i++) {
      final v = (j * (n + 1) + i) * 3;
      positions[v] = i.toDouble();
      positions[v + 1] = math.sin(i * 0.3) * math.cos(j * 0.3) * 2;
      positions[v + 2] = j.toDouble();
    }
  }
  final indices = Uint32List(n * n * 6);
  var k = 0;
  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      final a = j * (n + 1) + i;
      final b = a + 1;
      final c = a + (n + 1);
      final d = c + 1;
      indices[k++] = a;
      indices[k++] = b;
      indices[k++] = d;
      indices[k++] = a;
      indices[k++] = d;
      indices[k++] = c;
    }
  }
  return (positions, indices);
}

/// A flat floor with a few walls across it, as nav geometry.
NavGeometry level(double size, int walls) {
  final builder = NavGeometryBuilder();
  final half = size / 2;
  builder.addMesh(
    positions: [-half, 0, -half, half, 0, -half, half, 0, half, -half, 0, half],
    triangleIndices: [0, 2, 1, 0, 3, 2],
    area: NavArea.walkable,
  );
  for (var i = 0; i < walls; i++) {
    final x = -half + size * (i + 1) / (walls + 1);
    final reach = half * 0.7;
    builder.addMesh(
      positions: [x, 0, -reach, x, 0, reach, x, 3, reach, x, 3, -reach],
      triangleIndices: [0, 1, 2, 0, 2, 3],
    );
  }
  return builder.build();
}

void main() {
  if (!_enabled) {
    test('hot path benchmarks', () {}, skip: 'Set FLUTTER_SCENE_BENCH=1.');
    return;
  }

  test('hot paths', () async {
    // ignore: avoid_print
    print(
      '\nDart VM (JIT), ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}\n'
      'Best of 20 runs. AOT is typically 1.5-3x faster on these loops.',
    );

    // ------------------------------------------------------------------
    section('Water: the wave field, per frame');
    for (final resolution in const [32, 48, 96]) {
      final water = WaterSurfaceComponent();
      final points = (resolution + 1) * (resolution + 1);
      bench('${resolution}x$resolution grid ($points vertices, 3 waves)', () {
        for (var i = 0; i < points; i++) {
          water.evaluateAt(vm.Vector2(i * 0.1, i * 0.07), 1.0);
        }
      });
    }

    // ------------------------------------------------------------------
    section('Particles: one simulation step');
    for (final entry in const [
      (500, 'sparse'),
      (2000, 'rain'),
      (8000, 'heavy'),
    ]) {
      final system = ParticleSystem(
        maxParticles: entry.$1,
        shape: const SphereEmitterShape(radius: 2),
        spawner: Spawner(rate: entry.$1 * 2),
        lifetime: const ConstantFloat(4),
        startSpeed: const UniformFloat(1, 3),
        gravity: vm.Vector3(0, -9.8, 0),
        modules: [
          LinearDragModule(0.5),
          SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0))),
          ColorOverLifeModule(
            GradientColor(
              ColorGradient([
                ColorStop(0, vm.Vector4(1, 1, 1, 1)),
                ColorStop(1, vm.Vector4(1, 0, 0, 0)),
              ]),
            ),
          ),
        ],
      );
      for (var i = 0; i < 240; i++) {
        system.step(1 / 60);
      }
      bench('${entry.$1} particles (${entry.$2}), 3 modules', () {
        system.step(1 / 60);
      });
    }

    // ------------------------------------------------------------------
    section('Raycast: BVH build (once per mesh) and query (per pick)');
    for (final n in const [32, 64, 128]) {
      final (positions, indices) = grid(n);
      final triangles = indices.length ~/ 3;
      bench(
        'build over $triangles triangles',
        () {
          TriangleBvh.build(positions, indices);
        },
        runs: 8,
        warmup: 2,
      );
    }
    {
      final (positions, indices) = grid(128);
      final bvh = TriangleBvh.build(positions, indices);
      final random = math.Random(7);
      bench('1000 nearest-hit queries over 32768 triangles', () {
        for (var q = 0; q < 1000; q++) {
          final ox = random.nextDouble() * 128;
          final oz = random.nextDouble() * 128;
          bvh.raycast(ox, 40, oz, 0, -1, 0, 200, (first, end, limit) => limit);
        }
      });
    }

    // ------------------------------------------------------------------
    section('Nav mesh: a full bake');
    for (final entry in const [
      (40.0, 3, 'room'),
      (120.0, 8, 'level'),
      (300.0, 16, 'world'),
    ]) {
      final geometry = level(entry.$1, entry.$2);
      const config = NavMeshConfig(
        cellSize: 0.3,
        cellHeight: 0.2,
        agentRadius: 0.5,
        agentHeight: 2,
      );
      bench(
        '${entry.$1.toInt()}x${entry.$1.toInt()} ${entry.$3}, '
        '${entry.$2} walls, 0.3 voxels',
        () => buildNavMesh(geometry, config),
        runs: 5,
        warmup: 1,
      );
    }

    // ------------------------------------------------------------------
    section('Nav mesh: tiled vs single-shot');
    for (final entry in const [(120.0, 8, 'level'), (300.0, 16, 'world')]) {
      final geometry = level(entry.$1, entry.$2);
      const config = NavMeshConfig(
        cellSize: 0.3,
        cellHeight: 0.2,
        agentRadius: 0.5,
        agentHeight: 2,
      );
      bench(
        '${entry.$1.toInt()} ${entry.$3}: tiled, 64-cell tiles',
        () => bakeNavMeshTiled(
          geometry,
          config,
          tiling: const NavTileConfig(tileCells: 64),
        ),
        runs: 3,
        warmup: 1,
      );
      bench(
        '${entry.$1.toInt()} ${entry.$3}: tiled, 128-cell tiles',
        () => bakeNavMeshTiled(
          geometry,
          config,
          tiling: const NavTileConfig(tileCells: 128),
        ),
        runs: 3,
        warmup: 1,
      );
    }

    // ------------------------------------------------------------------
    section('Nav mesh: tiled across isolates');
    // ignore: avoid_print
    print(
      '  ${defaultNavBakeConcurrency()} lanes on '
      '${Platform.numberOfProcessors} cores',
    );
    for (final entry in const [(120.0, 8, 'level'), (300.0, 16, 'world')]) {
      final geometry = level(entry.$1, entry.$2);
      const config = NavMeshConfig(
        cellSize: 0.3,
        cellHeight: 0.2,
        agentRadius: 0.5,
        agentHeight: 2,
      );
      final watch = Stopwatch()..start();
      final result = await bakeNavMeshTiledAsync(
        geometry,
        config,
        tiling: const NavTileConfig(tileCells: 64),
      );
      watch.stop();
      // ignore: avoid_print
      print(
        '  ${'${entry.$1.toInt()} ${entry.$3}: parallel, 64-cell tiles'.padRight(46)} '
        '${(watch.elapsedMicroseconds / 1000).toStringAsFixed(3).padLeft(9)} ms'
        '  (${result.tiles.tileCount} tiles)',
      );
    }

    // ------------------------------------------------------------------
    section('Nav mesh: where the bake time goes (120x120 level)');
    {
      final geometry = level(120, 8);
      const config = NavMeshConfig(
        cellSize: 0.3,
        cellHeight: 0.2,
        agentRadius: 0.5,
        agentHeight: 2,
      );
      final totals = <NavBakeStage, double>{};
      final watch = Stopwatch();
      NavBakeStage? open;
      void close() {
        if (open == null) return;
        watch.stop();
        totals[open!] = (totals[open!] ?? 0) + watch.elapsedMicroseconds / 1000;
        open = null;
      }

      for (var run = 0; run < 4; run++) {
        totals.clear();
        buildNavMesh(
          geometry,
          config,
          onStage: (stage) {
            close();
            open = stage;
            watch
              ..reset()
              ..start();
          },
        );
        close();
      }
      for (final entry in totals.entries) {
        // ignore: avoid_print
        print(
          '  ${entry.key.name.padRight(46)} '
          '${entry.value.toStringAsFixed(3).padLeft(9)} ms',
        );
      }
    }

    // ------------------------------------------------------------------
    section('Flow: one graph tick');
    for (final size in const [10, 50, 200]) {
      final graph = FlowGraph();
      final tick = graph.add('event.tick');
      var previous = tick;
      var previousPin = 'then';
      for (var i = 0; i < size; i++) {
        final add = graph.add('math.add')
          ..literals['a'] = i.toDouble()
          ..literals['b'] = 1.0;
        final set = graph.add('var.set')..literals['name'] = 'v$i';
        graph
          ..connect(
            FlowLink(
              fromNode: previous.id,
              fromPin: previousPin,
              toNode: set.id,
              toPin: 'exec',
            ),
          )
          ..connect(
            FlowLink(
              fromNode: add.id,
              fromPin: 'value',
              toNode: set.id,
              toPin: 'value',
            ),
          );
        previous = set;
        previousPin = 'then';
      }
      final host = NullFlowHost();
      final runner = FlowInterpreter(sceneFlowRegistry());
      bench('$size-node chain', () {
        final context = FlowContext(graph: graph, host: host);
        runner.fire(context, onTick.id);
      });
    }

    // ignore: avoid_print
    print('');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
