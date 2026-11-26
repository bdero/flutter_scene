import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/render/projection_params.dart';

/// Pixels per wavefront line, the kernel's workgroup size (`WAVE_SIZE` in
/// `flutter_scene_contact_shadows_wavefront.comp`).
const int kWavefrontSize = 64;

/// How far from the screen center the light's pixel may sit. A directional
/// light nearly parallel to the image plane projects arbitrarily far, where
/// float pixel positions lose precision; pulling it in along the same
/// direction keeps the rays near parallel, which is all such a light needs.
const double kWavefrontMaxLightDistance = 32768.0;

/// Where a light lands on screen for the wavefront march.
class WavefrontLight {
  const WavefrontLight({
    required this.pixel,
    required this.depth,
    required this.towardLight,
  });

  /// The light's pixel position (+y down), possibly off screen.
  final Vector2 pixel;

  /// The light's depth as 1 / view depth, 0 for a directional light.
  final double depth;

  /// Whether the light is in front of the camera, so rays run toward [pixel]
  /// rather than away from it.
  final bool towardLight;
}

/// One dispatch: the lines of one ring whose pixels can land on screen.
class WavefrontRing {
  const WavefrontRing({
    required this.radius,
    required this.start,
    required this.count,
  });

  /// The ring's outer radius in pixels, a multiple of [kWavefrontSize].
  final int radius;

  /// The first perimeter position (0 to `8 * radius`), wrapping.
  final int start;

  /// How many perimeter positions, one workgroup each.
  final int count;

  /// The ring's perimeter length.
  int get perimeter => 8 * radius;
}

/// Projects a directional light toward view-space direction [towardLight]
/// onto a [width] x [height] pixel screen under [projection] (perspective
/// only).
WavefrontLight projectDirectionalLight(
  Vector3 towardLight,
  ProjectionParams projection,
  int width,
  int height,
) {
  // A light at infinity: its clip w is its view-space z, and its depth (as
  // 1 / view depth) is 0. The sign of w says which side of the camera it is.
  var w = towardLight.z;
  const minimumW = 1e-6;
  if (w.abs() < minimumW) w = w < 0.0 ? -minimumW : minimumW;
  final ndcX = towardLight.x / (projection.scaleX * w) + projection.offsetX;
  final ndcY = towardLight.y / (projection.scaleY * w) + projection.offsetY;
  final pixel = Vector2(
    (ndcX * 0.5 + 0.5) * width,
    (0.5 - ndcY * 0.5) * height,
  );
  final center = Vector2(width * 0.5, height * 0.5);
  final offset = pixel - center;
  final distance = offset.length;
  if (distance > kWavefrontMaxLightDistance) {
    pixel.setFrom(center + offset * (kWavefrontMaxLightDistance / distance));
  }
  return WavefrontLight(pixel: pixel, depth: 0.0, towardLight: w > 0.0);
}

/// The ring dispatches that cover a [width] x [height] screen around
/// [light]'s pixel. Rings whose lines cannot reach the screen are left out,
/// and of each remaining ring only the arc of its perimeter facing the
/// screen is dispatched.
List<WavefrontRing> planWavefrontRings(Vector2 light, int width, int height) {
  // Chebyshev distances from the light pixel to the screen rectangle.
  final dx = math.max(0.0, math.max(-light.x, light.x - width));
  final dy = math.max(0.0, math.max(-light.y, light.y - height));
  final nearest = math.max(dx, dy);
  final farthest = math.max(
    math.max(light.x.abs(), (light.x - width).abs()),
    math.max(light.y.abs(), (light.y - height).abs()),
  );
  final inside =
      light.x >= -1.0 &&
      light.y >= -1.0 &&
      light.x <= width + 1.0 &&
      light.y <= height + 1.0;
  final corners = [
    Vector2(-light.x, -light.y),
    Vector2(width - light.x, -light.y),
    Vector2(width - light.x, height - light.y),
    Vector2(-light.x, height - light.y),
  ];
  final first = math.max(0, (nearest / kWavefrontSize).floor() - 1);
  final last = (farthest / kWavefrontSize).ceil();
  final rings = <WavefrontRing>[];
  for (var ring = first; ring <= last; ring++) {
    final radius = (ring + 1) * kWavefrontSize;
    final perimeter = 8 * radius;
    if (inside) {
      rings.add(WavefrontRing(radius: radius, start: 0, count: perimeter));
      continue;
    }
    final positions = [
      for (final corner in corners) perimeterPosition(corner, radius),
    ]..sort();
    // The screen faces the light within half a turn, so the arc that holds
    // every corner is the complement of the widest gap between them.
    var gapEnd = 0;
    var widest = -1.0;
    for (var i = 0; i < positions.length; i++) {
      final next = i + 1 < positions.length
          ? positions[i + 1]
          : positions[0] + perimeter;
      final gap = next - positions[i];
      if (gap > widest) {
        widest = gap;
        gapEnd = (i + 1) % positions.length;
      }
    }
    // Two positions of margin on each end cover rounding at the corners.
    const margin = 2;
    final start = (positions[gapEnd].floor() - margin) % perimeter;
    final count = math.min(
      perimeter,
      (perimeter - widest).ceil() + 2 * margin + 1,
    );
    rings.add(WavefrontRing(radius: radius, start: start, count: count));
  }
  return rings;
}

/// Where direction [direction] (from the light pixel, +y down) crosses the
/// square ring of [radius], as a perimeter position matching the kernel's
/// `PerimeterOffset`: the top edge left to right, the right edge top to
/// bottom, the bottom edge right to left, the left edge bottom to top.
double perimeterPosition(Vector2 direction, int radius) {
  final r = radius.toDouble();
  final scale =
      r / math.max(direction.x.abs(), math.max(direction.y.abs(), 1e-9));
  final x = direction.x * scale;
  final y = direction.y * scale;
  if (y.abs() >= x.abs()) {
    return y < 0.0 ? x + r : 4.0 * r + (r - x);
  }
  return x > 0.0 ? 2.0 * r + (y + r) : 6.0 * r + (r - y);
}
