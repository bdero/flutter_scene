// ignore_for_file: implementation_imports
// Covers the wavefront contact shadow march's CPU planning: that the ring
// dispatches write every screen pixel exactly once wherever the light lands,
// mirroring the kernel's line-to-pixel mapping and write rule in
// contact_shadows_wavefront.glsl, and how a directional light projects.

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

// The kernel's LinePosition: the major axis exactly at [distance].
Vector2 _linePosition(Vector2 light, double p, double distance, double radius) {
  final offset = _perimeterOffset(p, radius);
  final scaled = offset * (distance / radius);
  if (offset.x.abs() == radius) scaled.x = offset.x.sign * distance;
  if (offset.y.abs() == radius) scaled.y = offset.y.sign * distance;
  return light + scaled;
}

// How many times the kernel writes each pixel of a [width] x [height]
// screen with the light at [light]: each line's pixels at Chebyshev
// distances radius - 63 to radius, skipping a pixel the previous dispatched
// line in its ring also crosses.
List<int> _writes(Vector2 light, int width, int height) {
  final writes = List<int>.filled(width * height, 0);
  for (final ring in planWavefrontRings(light, width, height)) {
    final radius = ring.radius.toDouble();
    final perimeter = ring.perimeter.toDouble();
    final full = ring.count == ring.perimeter;
    for (var g = 0; g < ring.count; g++) {
      final p = ((ring.start + g) % ring.perimeter).toDouble();
      final previous = (p - 1.0 + perimeter) % perimeter;
      final previousDispatched = full || p != ring.start.toDouble();
      for (var t = 0; t < kWavefrontSize; t++) {
        final distance = radius - t;
        final position = _linePosition(light, p, distance, radius);
        final x = position.x.floor();
        final y = position.y.floor();
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        if (previousDispatched) {
          final before = _linePosition(light, previous, distance, radius);
          if (before.x.floor() == x && before.y.floor() == y) continue;
        }
        writes[y * width + x]++;
      }
    }
  }
  return writes;
}

// How many pixels no line writes.
int _uncovered(Vector2 light, int width, int height) =>
    _writes(light, width, height).where((count) => count == 0).length;

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
    }
  });

  test('every pixel has one writer', () {
    for (final light in [
      Vector2(120.3, 60.7),
      Vector2(150.0, 85.0),
      Vector2(-400.2, 80.5),
      Vector2(900.6, -300.1),
      Vector2(150.5, 2000.25),
      Vector2(-5000.0, -4000.0),
    ]) {
      final writes = _writes(light, width, height);
      expect(writes.where((count) => count > 1).length, 0, reason: '$light');
    }
  });

  test('rings launch about one line pixel per screen pixel', () {
    const wide = 1280;
    const tall = 720;
    for (final light in [
      Vector2(-1700.2, 300.5),
      Vector2(3800.6, -1200.1),
      Vector2(-500.0, 1600.0),
      Vector2(-20000.0, -16000.0),
    ]) {
      final launched = planWavefrontRings(
        light,
        wide,
        tall,
      ).fold<int>(0, (sum, ring) => sum + ring.count * kWavefrontSize);
      expect(launched, lessThan(wide * tall * 1.25), reason: '$light');
    }
  });

  test('dispatches stay within backend limits and cover every line once', () {
    for (final (light, w, h) in [
      (Vector2(-980.0, 3089.0), 3840, 2160),
      (Vector2(3000.0, 2000.0), 7680, 4320),
      (Vector2(120.3, 60.7), width, height),
    ]) {
      final rings = planWavefrontRings(light, w, h);
      // A small cap splits rings across entries and dispatches.
      for (final cap in [kWavefrontMaxWorkgroups, 1000]) {
        final dispatches = batchWavefrontRings(rings, maxGroups: cap);
        final launched = <int, Set<int>>{};
        for (final dispatch in dispatches) {
          expect(dispatch.groups, lessThanOrEqualTo(cap));
          expect(
            dispatch.entries.length,
            lessThanOrEqualTo(kWavefrontRingTableSize),
          );
          // Walk the kernel's lookup: each workgroup takes the last entry
          // whose first group is at or before it.
          for (var group = 0; group < dispatch.groups; group++) {
            final (radius, start, first, _) = dispatch.entries.lastWhere(
              (entry) => entry.$3 <= group,
            );
            final position = (start + group - first) % (8 * radius);
            expect(
              (launched[radius] ??= {}).add(position),
              isTrue,
              reason: 'ring $radius position $position launched twice',
            );
          }
        }
        for (final ring in rings) {
          expect(launched[ring.radius]!.length, ring.count);
        }
      }
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
