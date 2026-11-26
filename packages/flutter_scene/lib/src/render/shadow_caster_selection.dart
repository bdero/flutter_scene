import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// What a frame's views can see, for choosing which local lights' shadows
/// are worth a slot in the shadow atlas.
///
/// The spot and point shadow selection is shared by every view a frame
/// renders, so this is the union of their view volumes.
class ShadowViewVolumes {
  /// Views looking from [eyes] through [frustums], plus their reflections in
  /// [mirrors]. A null [frustums] sees in every direction (an environment
  /// capture), so no light is out of view.
  ShadowViewVolumes({
    required this.eyes,
    this.frustums,
    this.mirrors = const [],
  });

  /// Camera positions, used to rank lights by how large they appear.
  final List<Vector3> eyes;

  /// The view frustums, or null when the views see everything.
  final List<Frustum>? frustums;

  /// Planar reflector planes; a light reflected in one is seen through it.
  final List<Plane> mirrors;

  final Sphere _mirrored = Sphere();

  /// Whether a light whose influence fits in [bounds] (radius `0` for
  /// unbounded) can affect anything these views see. A light's shadows fall
  /// only where it reaches, so a light that fails this casts no visible
  /// shadow.
  // TODO(shadow-slot-unbounded-reach): an unbounded light's shadows end at
  // its shadowFar, so that radius could cull it too.
  bool canSee(Sphere bounds) {
    final frustums = this.frustums;
    if (frustums == null || bounds.radius <= 0.0) return true;
    if (_intersectsAny(frustums, bounds)) return true;
    _mirrored.radius = bounds.radius;
    for (final mirror in mirrors) {
      // Reflecting the sphere through the plane is equivalent to testing the
      // original against the reflected camera.
      final distance = mirror.normal.dot(bounds.center) + mirror.constant;
      _mirrored.center
        ..setFrom(mirror.normal)
        ..scale(-2.0 * distance)
        ..add(bounds.center);
      if (_intersectsAny(frustums, _mirrored)) return true;
    }
    return false;
  }

  static bool _intersectsAny(List<Frustum> frustums, Sphere sphere) {
    for (final frustum in frustums) {
      if (frustum.intersectsWithSphere(sphere)) return true;
    }
    return false;
  }

  /// How large [bounds] appears from the nearest eye, its radius over its
  /// distance. Unbounded lights score infinite. Independent of intensity and
  /// light units, so a shadow-only light (intensity 0) competes on its
  /// footprint.
  double apparentSize(Sphere bounds) {
    if (bounds.radius <= 0.0) return double.infinity;
    return bounds.radius / math.max(nearestEyeDistance(bounds.center), 1e-4);
  }

  /// The distance from [point] to the nearest eye.
  double nearestEyeDistance(Vector3 point) {
    var nearest = double.infinity;
    for (final eye in eyes) {
      nearest = math.min(nearest, eye.distanceTo(point));
    }
    return nearest;
  }
}

/// How much a light that held a slot last frame is favored over a newcomer,
/// so two lights of near-equal rank do not trade the slot back and forth.
const double kShadowSlotHysteresis = 1.1;

/// The shadow casters picked for a frame, plus the ones the budget left out.
class ShadowCasterSelection<T> {
  ShadowCasterSelection(this.casters, this.dropped);

  /// The granted casters, in their original list order (index = slot).
  final List<T> casters;

  /// In-view lights that asked for a shadow but got no slot.
  final List<T> dropped;
}

/// Picks up to [budget] of [lights] to cast shadows.
///
/// Lights not casting ([castsShadow] false) or whose influence [bounds] (a
/// sphere, radius `0` for unbounded) misses [views] are skipped. When more
/// remain than [budget], the largest on screen win (see
/// [ShadowViewVolumes.apparentSize]), lights in [previous] winning near-ties;
/// equal ranks fall back to the nearer light, then list order.
/// Winners keep list order, so slots stay put while the chosen set does.
/// A null [views] skips nothing and takes the first [budget].
ShadowCasterSelection<T> selectShadowCasters<T extends Object>(
  List<T> lights, {
  required int budget,
  required bool Function(T) castsShadow,
  required Sphere Function(T) bounds,
  ShadowViewVolumes? views,
  Set<Object>? previous,
}) {
  final candidates = <int>[];
  final spheres = <Sphere>[];
  for (var i = 0; i < lights.length; i++) {
    final light = lights[i];
    if (!castsShadow(light)) continue;
    final sphere = bounds(light);
    if (views != null && !views.canSee(sphere)) continue;
    candidates.add(i);
    spheres.add(sphere);
  }
  if (candidates.length <= budget || views == null) {
    return ShadowCasterSelection(
      [for (final i in candidates.take(budget)) lights[i]],
      [for (final i in candidates.skip(budget)) lights[i]],
    );
  }

  final ranked = List<int>.generate(candidates.length, (i) => i);
  final scores = [
    for (var k = 0; k < candidates.length; k++)
      views.apparentSize(spheres[k]) *
          (previous != null && previous.contains(lights[candidates[k]])
              ? kShadowSlotHysteresis
              : 1.0),
  ];
  final distances = [
    for (final sphere in spheres) views.nearestEyeDistance(sphere.center),
  ];
  ranked.sort((a, b) {
    final byScore = scores[b].compareTo(scores[a]);
    if (byScore != 0) return byScore;
    final byDistance = distances[a].compareTo(distances[b]);
    if (byDistance != 0) return byDistance;
    return a.compareTo(b);
  });
  final winners = ranked.take(budget).toList()..sort();
  return ShadowCasterSelection(
    [for (final k in winners) lights[candidates[k]]],
    [for (final k in ranked.skip(budget)) lights[candidates[k]]],
  );
}
