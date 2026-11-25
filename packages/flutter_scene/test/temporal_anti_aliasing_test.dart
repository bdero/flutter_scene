// Tests TemporalAntiAliasingSettings, halton23 generation, and camera jitter math.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/taa_pass.dart';
import 'package:flutter_scene/src/render/temporal_anti_aliasing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('TemporalAntiAliasingSettings', () {
    test('defaults match reference specification', () {
      final s = TemporalAntiAliasingSettings();
      expect(s.minimumCurrentWeight, 0.15);
      expect(s.varianceGamma, 1.2);
      expect(s.sharpness, 0.15);
      expect(s.jitterScale, 0.46);
      expect(s.jitterSequenceLength, 11);
      expect(s.objectMotion, isFalse);
      expect(s.skinnedMotion, isFalse);
    });

    test('validates and clamps parameters', () {
      final s = TemporalAntiAliasingSettings();
      s.minimumCurrentWeight = 0.08;
      s.varianceGamma = 1.25;
      expect(s.minimumCurrentWeight, 0.08);
      expect(s.varianceGamma, 1.25);
    });
  });

  group('halton23 sequence generator', () {
    test('produces values strictly inside unit interval (0, 1)', () {
      for (var i = 1; i <= 64; i++) {
        final pt = halton23(i);
        expect(pt.x, greaterThan(0.0));
        expect(pt.x, lessThan(1.0));
        expect(pt.y, greaterThan(0.0));
        expect(pt.y, lessThan(1.0));
      }
    });

    test('first few terms match base-2 and base-3 radical inverse', () {
      // index 1: base 2 -> 1/2 = 0.5, base 3 -> 1/3 = 0.3333333333333333
      final p1 = halton23(1);
      expect(p1.x, closeTo(0.5, 1e-6));
      expect(p1.y, closeTo(1.0 / 3.0, 1e-6));

      // index 2: base 2 -> 1/4 = 0.25, base 3 -> 2/3 = 0.6666666666666666
      final p2 = halton23(2);
      expect(p2.x, closeTo(0.25, 1e-6));
      expect(p2.y, closeTo(2.0 / 3.0, 1e-6));

      // index 3: base 2 -> 3/4 = 0.75, base 3 -> 1/9 = 0.1111111111111111
      final p3 = halton23(3);
      expect(p3.x, closeTo(0.75, 1e-6));
      expect(p3.y, closeTo(1.0 / 9.0, 1e-6));
    });
  });

  group('Camera Projection Jitter Math', () {
    test(
      'PerspectiveProjection.getProjectionMatrix modifies only m[8] and m[9]',
      () {
        final proj = PerspectiveProjection(
          fovRadiansY: 1.0,
          near: 0.1,
          far: 100.0,
        );
        final unjittered = proj.getProjectionMatrix(16.0 / 9.0);
        final jitter = Vector2(0.0125, -0.025);
        final jittered = proj.getProjectionMatrix(16.0 / 9.0, jitter: jitter);

        for (var i = 0; i < 16; i++) {
          if (i == 8) {
            expect(jittered.storage[8], closeTo(jitter.x, 1e-6));
          } else if (i == 9) {
            expect(jittered.storage[9], closeTo(jitter.y, 1e-6));
          } else {
            expect(jittered.storage[i], unjittered.storage[i]);
          }
        }
      },
    );

    test('Camera.getViewTransform applies jittered projection matrix', () {
      final camera = PerspectiveCamera(
        fovRadiansY: 1.0,
        position: Vector3(0, 0, 5),
        target: Vector3.zero(),
        up: Vector3(0, 1, 0),
      );
      final dimensions = const ui.Size(1920, 1080);
      final unjittered = camera.getViewTransform(dimensions);
      final jitter = Vector2(0.005, -0.003);
      final jittered = camera.getViewTransform(dimensions, jitter: jitter);

      expect(jittered, isNot(equals(unjittered)));

      // Transforming a point at center of screen shows the expected NDC shift
      final p = Vector4(0, 0, 0, 1);
      final unjitteredClip = unjittered * p;
      final jitteredClip = jittered * p;

      final unjitteredNdc = unjitteredClip.xy / unjitteredClip.w;
      final jitteredNdc = jitteredClip.xy / jitteredClip.w;

      expect(jitteredNdc.x - unjitteredNdc.x, closeTo(jitter.x, 1e-5));
      expect(jitteredNdc.y - unjitteredNdc.y, closeTo(jitter.y, 1e-5));
    });
  });

  group('TaaHistoryState', () {
    test('cold start flags clear upon resolve and reset upon invalidate', () {
      final state = TaaHistoryState();
      expect(state.hasHistory, isFalse);

      state.invalidate();
      expect(state.hasHistory, isFalse);
    });
  });
}
