// ignore_for_file: implementation_imports
// Covers the wavefront contact shadow march's CPU planning: that the ring
// dispatches reach every screen pixel wherever the light lands, mirroring the
// kernel's line-to-pixel mapping in contact_shadows_wavefront.glsl, and how a
// directional light projects.

import 'package:flutter_scene/src/render/contact_shadow_wavefront.dart';
import 'package:flutter_scene/src/render/contact_shadow_wavefront_plan.dart';
import 'package:flutter_scene/src/render/projection_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The kernel's PerimeterOffset.
Vector2 _perimeterOffset(double p, double radius) {
  final side = 2.0 * radius;
  if (p < side) return Vector2(-radius + p, -radius);
  if (p < 2.0 * side) return Vector2(radius, -radius + (p - side));
  if (p < 3.0 * side) return Vector2(radius - (p - 2.0 * side), radius);
  return Vector2(-radius, radius - (p - 3.0 * side));
}

// How many of a [width] x [height] screen's pixels no line marches as its
// own pixel, with the light at [light].
int _uncovered(Vector2 light, int width, int height, {bool toward = true}) {
  final covered = List<bool>.filled(width * height, false);
  for (final ring in planWavefrontRings(light, width, height)) {
    final radius = ring.radius.toDouble();
    for (var g = 0; g < ring.count; g++) {
      final p = ((ring.start + g) % ring.perimeter).toDouble();
      final offset = _perimeterOffset(p, radius);
      for (var t = 0; t < kWavefrontSize; t++) {
        final distance = toward
            ? radius - t
            : radius - (kWavefrontSize - 1) + t;
        final position = light + offset * (distance / radius);
        final x = position.x.floor();
        final y = position.y.floor();
        if (x >= 0 && y >= 0 && x < width && y < height) {
          covered[y * width + x] = true;
        }
      }
    }
  }
  return covered.where((c) => !c).length;
}

void main() {
  const width = 300;
  const height = 170;

  test('perimeter positions match the kernel walk', () {
    for (final p in [0.0, 37.0, 128.0, 200.0, 300.0, 444.0, 511.0]) {
      final offset = _perimeterOffset(p, 64);
      expect(perimeterPosition(offset, 64), closeTo(p, 1e-9), reason: '$p');
    }
  });

  test('rings cover the screen with the light on screen', () {
    // The light's own pixel is never a line pixel.
    expect(
      _uncovered(Vector2(120.3, 60.7), width, height),
      lessThanOrEqualTo(1),
    );
  });

  test('rings cover the screen with the light off each side', () {
    for (final light in [
      Vector2(-400.2, 80.5),
      Vector2(900.6, -300.1),
      Vector2(150.5, 2000.25),
      Vector2(-5000.0, -4000.0),
      Vector2(30000.0, 120.0),
    ]) {
      expect(_uncovered(light, width, height), 0, reason: '$light');
      expect(
        _uncovered(light, width, height, toward: false),
        0,
        reason: 'away from $light',
      );
    }
  });

  test('rings far from the screen are left out', () {
    final rings = planWavefrontRings(Vector2(-5000, 80), width, height);
    // The screen spans about five rings out there, plus a margin each side.
    expect(rings.length, lessThanOrEqualTo(8));
    for (final ring in rings) {
      expect(ring.count, lessThan(ring.perimeter ~/ 4));
    }
  });

  test('a directional light projects through the view axis', () {
    const projection = ProjectionParams(
      scaleX: 1.0,
      scaleY: 1.0,
      offsetX: 0.0,
      offsetY: 0.0,
      orthographic: false,
      near: 0.1,
      far: 100.0,
    );
    final ahead = projectDirectionalLight(
      Vector3(0, 0, 1),
      projection,
      200,
      100,
    );
    expect(ahead.pixel.x, closeTo(100, 1e-9));
    expect(ahead.pixel.y, closeTo(50, 1e-9));
    expect(ahead.towardLight, isTrue);
    expect(ahead.depth, 0.0);
    // Behind the camera, rays run away from the projected pixel.
    final behind = projectDirectionalLight(
      Vector3(0.2, 0.1, -1),
      projection,
      200,
      100,
    );
    expect(behind.towardLight, isFalse);
    // Nearly parallel to the image plane, pulled in toward the screen.
    final grazing = projectDirectionalLight(
      Vector3(1, 0, 1e-9),
      projection,
      200,
      100,
    );
    expect(
      (grazing.pixel - Vector2(100, 50)).length,
      closeTo(kWavefrontMaxLightDistance, 1e-6),
    );
  });

  test('the sample count fits the projected march distance', () {
    const projection = ProjectionParams(
      scaleX: 0.5,
      scaleY: 0.5,
      offsetX: 0.0,
      offsetY: 0.0,
      orthographic: false,
      near: 0.1,
      far: 100.0,
    );
    // 1000 pixels tall at half-height scale 0.5: 1000 px per world unit at
    // a depth of one.
    expect(wavefrontSampleCount(0.05, projection, 1000), 60);
    expect(wavefrontSampleCount(0.1, projection, 1000), 127);
    expect(wavefrontSampleCount(0.15, projection, 1000), 191);
    expect(wavefrontSampleCount(3.0, projection, 1000), 191);
  });
}
