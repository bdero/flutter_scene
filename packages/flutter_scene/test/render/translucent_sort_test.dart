import 'dart:ui';

// ignore: implementation_imports
import 'package:flutter_scene/src/scene_encoder.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test(
    'scene sorting uses transformed geometry center along the view axis',
    () {
      final bounds = Aabb3.minMax(
        Vector3(-1.0, -1.0, 9.0),
        Vector3(1.0, 1.0, 11.0),
      );
      final depth = sceneSortDepth(
        Matrix4.translationValues(0.0, 0.0, 5.0),
        bounds,
        Vector3.zero(),
        Vector3(0.0, 0.0, 1.0),
      );

      expect(depth, 15.0);
    },
  );

  test('scene sorting ignores lateral distance', () {
    final depth = sceneSortDepth(
      Matrix4.translationValues(100.0, 0.0, 4.0),
      null,
      Vector3.zero(),
      Vector3(0.0, 0.0, 1.0),
    );

    expect(depth, 4.0);
  });

  test('rough transmission atlas caps its filter pyramid', () {
    expect(transmissionFilterBandCount(1920, 1080), 8);
    expect(transmissionFilterBandCount(64, 32), 5);
    expect(transmissionFilterBandCount(1, 128), 0);
  });

  test('overlapping scene-color readers use accumulated snapshots', () {
    expect(
      sceneColorCaptureBatchCount([
        for (var i = 0; i < 3; i++)
          (
            bounds: const Rect.fromLTWH(100, 100, 200, 200),
            readsSceneColor: true,
          ),
      ], const Size(1000, 1000)),
      3,
    );
  });

  test('disjoint scene-color readers share one snapshot', () {
    expect(
      sceneColorCaptureBatchCount(const [
        (bounds: Rect.fromLTWH(50, 100, 100, 100), readsSceneColor: true),
        (bounds: Rect.fromLTWH(450, 100, 100, 100), readsSceneColor: true),
        (bounds: Rect.fromLTWH(850, 100, 100, 100), readsSceneColor: true),
      ], const Size(1000, 1000)),
      1,
    );
  });

  test('many disjoint readers keep capture cost constant', () {
    expect(
      sceneColorCaptureBatchCount([
        for (var i = 0; i < 8; i++)
          (
            bounds: Rect.fromLTWH(48.0 + i * 248.0, 100, 64, 120),
            readsSceneColor: true,
          ),
      ], const Size(2048, 1024)),
      1,
    );
  });

  test('reader captures overlapping ordinary translucency', () {
    expect(
      sceneColorCaptureBatchCount(const [
        (bounds: Rect.fromLTWH(50, 100, 100, 100), readsSceneColor: true),
        (bounds: Rect.fromLTWH(700, 100, 100, 100), readsSceneColor: false),
        (bounds: Rect.fromLTWH(720, 100, 100, 100), readsSceneColor: true),
      ], const Size(1000, 1000)),
      2,
    );
  });

  test('ordinary translucency does not create scene-color captures', () {
    expect(
      sceneColorCaptureBatchCount(const [
        (bounds: Rect.fromLTWH(100, 100, 200, 200), readsSceneColor: false),
        (bounds: Rect.fromLTWH(200, 200, 200, 200), readsSceneColor: false),
      ], const Size(1000, 1000)),
      0,
    );
  });

  test('rough transmission atlas offsets match odd-sized bands', () {
    expect(transmissionFilterBandOffset(1671, 1), 0);
    expect(transmissionFilterBandOffset(1671, 2), 835);
    expect(transmissionFilterBandOffset(1671, 3), 1253);
    expect(transmissionFilterBandOffset(1671, 8), 1657);
  });

  test('rough transmission filter retains every odd-sized source column', () {
    final coverage = _transmissionFilterCoverage(1671, 8);
    expect(coverage, everyElement(greaterThan(1e-9)));
  });
}

List<double> _transmissionFilterCoverage(int sourceSize, int levels) {
  var rows = <Map<int, double>>[
    for (var i = 0; i < sourceSize; i++) <int, double>{i: 1.0},
  ];
  // Horizontal marginal of the normalized 13-tap reduction kernel.
  const offsets = <int>[-2, -1, 0, 1, 2];
  const weights = <double>[0.125, 0.25, 0.25, 0.25, 0.125];
  for (var level = 0; level < levels && rows.length >= 2; level++) {
    final sourceLength = rows.length;
    final targetLength = sourceLength >> 1;
    final next = <Map<int, double>>[];
    for (var x = 0; x < targetLength; x++) {
      final accumulated = <int, double>{};
      for (var tap = 0; tap < offsets.length; tap++) {
        final position =
            (x + 0.5) * sourceLength / targetLength - 0.5 + offsets[tap];
        final lower = position.floor();
        final fraction = position - lower;
        for (final (sample, linearWeight) in <(int, double)>[
          (lower, 1.0 - fraction),
          (lower + 1, fraction),
        ]) {
          final clamped = sample.clamp(0, sourceLength - 1);
          final weight = weights[tap] * linearWeight;
          for (final entry in rows[clamped].entries) {
            accumulated.update(
              entry.key,
              (value) => value + entry.value * weight,
              ifAbsent: () => entry.value * weight,
            );
          }
        }
      }
      next.add(accumulated);
    }
    rows = next;
  }
  final coverage = List<double>.filled(sourceSize, 0.0);
  for (final row in rows) {
    for (final entry in row.entries) {
      coverage[entry.key] += entry.value;
    }
  }
  return coverage;
}
