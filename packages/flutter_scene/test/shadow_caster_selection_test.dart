// Covers which spot and point lights get a shadow slot: lights whose reach
// misses every view are skipped (unless unbounded, or seen in a mirror), and
// under budget pressure the largest on screen win, stably.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/render/point_shadow.dart';
import 'package:flutter_scene/src/render/shadow_caster_selection.dart';
import 'package:flutter_scene/src/render/spot_shadow.dart';
import 'package:flutter_scene/src/render/viewport_camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

PointLightComponent _point(
  Vector3 at, {
  double range = 2.0,
  double intensity = 1.0,
}) {
  final node = Node(localTransform: Matrix4.translation(at));
  final component = PointLightComponent(
    PointLight(range: range, intensity: intensity, castsShadow: true),
  );
  node.addComponent(component);
  return component;
}

SpotLightComponent _spot(Vector3 at, Vector3 direction, {double range = 8.0}) {
  final node = Node(localTransform: Matrix4.translation(at));
  final component = SpotLightComponent(
    SpotLight(
      range: range,
      direction: direction,
      outerConeAngle: 0.3,
      castsShadow: true,
    ),
  );
  node.addComponent(component);
  return component;
}

ShadowViewVolumes _views(Camera camera, {List<Plane> mirrors = const []}) =>
    ShadowViewVolumes(
      eyes: [camera.position],
      frustums: [cullingFrustumOf(camera, const ui.Size(800, 600))],
      mirrors: mirrors,
    );

// Looks down -Z at the origin from z = 10.
final _camera = PerspectiveCamera(position: Vector3(0, 0, 10));

void main() {
  test('skips a shadowed light whose range misses the view', () {
    final inView = _point(Vector3(0, 0, 0));
    final behind = _point(Vector3(0, 0, 40));
    final frame = collectPointShadows([
      behind,
      inView,
    ], views: _views(_camera))!;
    expect(frame.casters, [inView]);
    // Out of view is not over budget.
    expect(frame.dropped, isEmpty);
  });

  test('keeps an unbounded light wherever it is', () {
    final unbounded = _point(Vector3(0, 0, 40), range: 0.0);
    final frame = collectPointShadows([unbounded], views: _views(_camera))!;
    expect(frame.casters, [unbounded]);
  });

  test('keeps a light only a planar reflection sees', () {
    // Looking almost straight down at a floor mirror; the light is above and
    // out of view, but its reflection below the floor is in view.
    final camera = PerspectiveCamera(
      position: Vector3(0, 10, 1),
      target: Vector3.zero(),
    );
    final light = _point(Vector3(0, 8, -6), range: 1.0);
    final floor = Plane.normalconstant(Vector3(0, 1, 0), 0.0);
    expect(collectPointShadows([light], views: _views(camera)), isNull);
    final frame = collectPointShadows([
      light,
    ], views: _views(camera, mirrors: [floor]))!;
    expect(frame.casters, [light]);
  });

  test('an omnidirectional capture skips nothing', () {
    final behind = _point(Vector3(0, 0, 40));
    final frame = collectPointShadows([
      behind,
    ], views: ShadowViewVolumes(eyes: [Vector3.zero()]))!;
    expect(frame.casters, [behind]);
  });

  test('skips a spot whose cone points away from the view', () {
    // Both spots' range spheres reach into the view; only the one aimed at it
    // lights anything there.
    final away = _spot(Vector3(12, 0, 0), Vector3(1, 0, 0));
    final toward = _spot(Vector3(12, 0, 0), Vector3(-1, 0, 0));
    final frame = collectSpotShadows([away, toward], views: _views(_camera))!;
    expect(frame.casters, [toward]);
  });

  test('spot bounds hold the apex and the cone rim', () {
    for (final angle in [0.1, 0.5, 0.9, 1.4, 2.0]) {
      final node = Node();
      final spot = SpotLightComponent(
        SpotLight(range: 5.0, direction: Vector3(0, 0, -1)),
      )..light.outerConeAngle = angle;
      node.addComponent(spot);
      final bounds = spotInfluenceBounds(spot);
      final rimAngle = math.min(angle, math.pi);
      final points = [
        Vector3.zero(),
        Vector3(0, 0, -5),
        Vector3(5 * math.sin(rimAngle), 0, -5 * math.cos(rimAngle)),
      ];
      for (final p in points) {
        expect(
          bounds.center.distanceTo(p),
          lessThanOrEqualTo(bounds.radius + 1e-4),
          reason: 'angle $angle, point $p',
        );
      }
      expect(bounds.radius, lessThanOrEqualTo(5.0 + 1e-4));
    }
  });

  test('under pressure the largest on screen win, kept in list order', () {
    final lights = [
      for (var i = 0; i < kMaxPointShadows + 2; i++)
        _point(Vector3(i.isEven ? -1.0 : 1.0, 0, -4.0 * i)),
    ];
    // Reverse the list so first-in-list would pick the farthest lights.
    final reversed = lights.reversed.toList();
    final frame = collectPointShadows(reversed, views: _views(_camera))!;
    final nearest = lights.take(kMaxPointShadows).toSet();
    expect(frame.casters.toSet(), nearest);
    expect(frame.casters, [
      for (final light in reversed)
        if (nearest.contains(light)) light,
    ]);
    expect(frame.dropped.toSet(), lights.skip(kMaxPointShadows).toSet());
  });

  test('a larger range outranks a nearer light', () {
    final lights = [
      for (var i = 0; i < kMaxPointShadows; i++) _point(Vector3(0, 0, -2)),
      _point(Vector3(0, 0, -20), range: 30.0),
    ];
    final frame = collectPointShadows(lights, views: _views(_camera))!;
    expect(frame.casters, contains(lights.last));
  });

  test('a shadow-only light competes on its footprint, not intensity', () {
    final shadowOnly = _point(Vector3(0, 0, 0), intensity: 0.0);
    final lights = [
      for (var i = 0; i < kMaxPointShadows; i++)
        _point(Vector3(0, 0, -10), intensity: 100.0),
      shadowOnly,
    ];
    final frame = collectPointShadows(lights, views: _views(_camera))!;
    expect(frame.casters, contains(shadowOnly));
  });

  test('last frame holders keep near-ties and lose clear ones', () {
    // One slot left: four equal near lights take the rest.
    List<PointLightComponent> fill() => [
      for (var i = 0; i < kMaxPointShadows - 1; i++) _point(Vector3(0, 0, 5)),
    ];
    final holder = _point(Vector3(0, 0, 0)); // 10 from the eye
    final slightlyCloser = _point(Vector3(0, 0, 0.5)); // 9.5, 5% larger
    final muchCloser = _point(Vector3(0, 0, 2)); // 8, 25% larger

    final views = _views(_camera);
    final near = fill();
    final fresh = collectPointShadows([
      ...near,
      holder,
      slightlyCloser,
    ], views: views)!;
    expect(fresh.casters, contains(slightlyCloser));

    final held = collectPointShadows(
      [...near, holder, slightlyCloser],
      views: views,
      previous: {holder},
    )!;
    expect(held.casters, contains(holder));
    expect(held.casters, isNot(contains(slightlyCloser)));

    final overtaken = collectPointShadows(
      [...near, holder, muchCloser],
      views: views,
      previous: {holder},
    )!;
    expect(overtaken.casters, contains(muchCloser));
  });

  test('equal ranks resolve by list order, the same every frame', () {
    final lights = [
      for (var i = 0; i < kMaxPointShadows + 3; i++) _point(Vector3(0, 0, -3)),
    ];
    final views = _views(_camera);
    final first = collectPointShadows(lights, views: views)!;
    expect(first.casters, lights.take(kMaxPointShadows).toList());
    for (var frame = 0; frame < 3; frame++) {
      final again = collectPointShadows(
        lights,
        views: views,
        previous: first.casters.toSet(),
      )!;
      expect(again.casters, first.casters);
    }
  });

  test('without views the first casters in list order win', () {
    final lights = [
      for (var i = 0; i < kMaxSpotShadows + 1; i++)
        _spot(Vector3(0, 0, -4.0 * i), Vector3(0, 0, 1)),
    ];
    final frame = collectSpotShadows(lights.reversed.toList())!;
    expect(frame.casters, lights.reversed.take(kMaxSpotShadows).toList());
    expect(frame.dropped, [lights.first]);
  });
}
