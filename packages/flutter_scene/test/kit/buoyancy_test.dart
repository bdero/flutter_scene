// Floating things on water. Covered without a GPU: mounting a water surface
// builds geometry, but everything buoyancy reads -- the wave spectrum, the
// time, the water node's transform -- is CPU-side, so a raft can be stepped
// against a surface that was never uploaded.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A lake with a single long wave running along X, so the surface height at a
/// point is predictable rather than noise.
WaterComponent lake({double size = 40, double amplitude = 1.0}) =>
    WaterComponent(
      size: size,
      waves: [
        GerstnerWave(
          direction: vm.Vector2(1, 0),
          amplitude: amplitude,
          wavelength: 20,
          speed: 1,
        ),
      ],
    );

/// A scene with [water] under the root and a floating node at [at].
(Node root, WaterComponent water, Node floater) scene({
  WaterComponent? water,
  vm.Vector3? at,
  BuoyancyComponent? buoyancy,
}) {
  final surface = water ?? lake();
  final root = Node(name: 'level');
  final waterNode = Node(name: 'lake')..addComponent(surface);
  final floater = Node(name: 'raft')..position = at ?? vm.Vector3(0, 5, 0);
  floater.addComponent(buoyancy ?? BuoyancyComponent());
  root
    ..add(waterNode)
    ..add(floater);
  return (root, surface, floater);
}

void main() {
  group('finding the water', () {
    test('a float finds the surface under the same root', () {
      final (_, water, floater) = scene();
      final buoyancy = floater.getComponent<BuoyancyComponent>()!;
      expect(buoyancy.resolvedWater, same(water));
    });

    test('an explicit surface wins over the search', () {
      final other = lake();
      final (_, water, floater) = scene(
        buoyancy: BuoyancyComponent(water: other),
      );
      final buoyancy = floater.getComponent<BuoyancyComponent>()!;
      expect(buoyancy.resolvedWater, same(other));
      expect(buoyancy.resolvedWater, isNot(same(water)));
    });

    test('no water anywhere is not an error, it just does not float', () {
      final root = Node(name: 'level');
      final floater = Node(name: 'crate')..position = vm.Vector3(0, 3, 0);
      final buoyancy = BuoyancyComponent();
      floater.addComponent(buoyancy);
      root.add(floater);

      buoyancy.update(1 / 60);
      expect(buoyancy.resolvedWater, isNull);
      expect(buoyancy.isFloating, isFalse);
      expect(floater.position.y, 3);
    });
  });

  group('floating without a body', () {
    test('a raft above the water settles onto it', () {
      final (_, water, floater) = scene(at: vm.Vector3(0, 12, 0));
      final buoyancy = floater.getComponent<BuoyancyComponent>()!;

      buoyancy.update(1 / 60);
      expect(buoyancy.isFloating, isTrue);
      expect(
        floater.position.y,
        closeTo(water.surfaceHeightAt(0, 0), 0.6),
        reason: 'placed on the surface, not pushed toward it',
      );
    });

    test('it rides the wave rather than sitting at a fixed height', () {
      final (_, water, floater) = scene();
      final buoyancy = floater.getComponent<BuoyancyComponent>()!;
      buoyancy.update(1 / 60);
      final atRest = floater.position.y;

      water.time = 2.5;
      buoyancy.update(1 / 60);
      expect(floater.position.y, isNot(closeTo(atRest, 1e-3)));
    });

    test('draft sinks it by exactly that much', () {
      final surface = lake();
      final shallow = Node(name: 'a')
        ..position = vm.Vector3(0, 6, 0)
        ..addComponent(BuoyancyComponent(water: surface));
      final deep = Node(name: 'b')
        ..position = vm.Vector3(0, 6, 0)
        ..addComponent(BuoyancyComponent(water: surface, draft: -1.5));
      final root = Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(shallow)
        ..add(deep);
      expect(root.children, hasLength(3));

      shallow.getComponent<BuoyancyComponent>()!.update(1 / 60);
      deep.getComponent<BuoyancyComponent>()!.update(1 / 60);
      expect(deep.position.y, closeTo(shallow.position.y - 1.5, 1e-4));
    });

    test('the node keeps its X and Z: water lifts, it does not push', () {
      final (_, _, floater) = scene(at: vm.Vector3(3.5, 9, -2.25));
      floater.getComponent<BuoyancyComponent>()!.update(1 / 60);
      expect(floater.position.x, 3.5);
      expect(floater.position.z, -2.25);
    });

    test('a hull spanning a wave tilts on it', () {
      // One wave along X and a hull wide enough to span a good part of it, so
      // its two ends really are at different heights.
      final surface = lake(amplitude: 1.5);
      final boat = Node(name: 'boat')
        ..position = vm.Vector3(0, 4, 0)
        ..addComponent(
          BuoyancyComponent(water: surface, hullSize: 8, alignResponse: 1000),
        );
      Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(boat);

      boat.getComponent<BuoyancyComponent>()!.update(1 / 60);
      expect(
        boat.rotation.rotateVector(vm.Vector3(0, 1, 0)).y,
        lessThan(0.9999),
      );
    });

    test('a hull rides its average; a point float rides its own point', () {
      // This is what the probe count buys. Over a curved surface the mean of
      // four heights is not the height at the middle, so a wide hull sits
      // where the whole hull is supported rather than where its centre is.
      final surface = lake(amplitude: 1.5);
      final hull = Node(name: 'boat')
        ..position = vm.Vector3(2, 4, 0)
        ..addComponent(
          BuoyancyComponent(water: surface, hullSize: 8, alignToSurface: false),
        );
      final buoy = Node(name: 'buoy')
        ..position = vm.Vector3(2, 4, 0)
        ..addComponent(
          BuoyancyComponent(
            water: surface,
            hullSize: 8,
            probeCount: 1,
            alignToSurface: false,
          ),
        );
      Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(hull)
        ..add(buoy);

      hull.getComponent<BuoyancyComponent>()!.update(1 / 60);
      buoy.getComponent<BuoyancyComponent>()!.update(1 / 60);

      expect(buoy.position.y, closeTo(surface.surfaceHeightAt(2, 0), 1e-4));
      expect(hull.position.y, isNot(closeTo(buoy.position.y, 1e-3)));
    });

    test('alignToSurface off keeps it upright', () {
      final surface = lake(amplitude: 1.5);
      final flat = Node(name: 'barge')
        ..position = vm.Vector3(0, 4, 0)
        ..addComponent(
          BuoyancyComponent(water: surface, hullSize: 8, alignToSurface: false),
        );
      Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(flat);

      for (var i = 0; i < 30; i++) {
        flat.getComponent<BuoyancyComponent>()!.update(1 / 60);
      }
      expect(
        flat.rotation.rotateVector(vm.Vector3(0, 1, 0)).y,
        closeTo(1.0, 1e-9),
      );
    });

    test('the tilt is damped, so a ripple does not snap it', () {
      final surface = lake(amplitude: 1.5);
      final slow = Node(name: 'barge')
        ..position = vm.Vector3(0, 4, 0)
        ..addComponent(
          BuoyancyComponent(water: surface, hullSize: 8, alignResponse: 0.5),
        );
      Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(slow);

      final buoyancy = slow.getComponent<BuoyancyComponent>()!;
      buoyancy.update(1 / 60);
      final afterOne = slow.rotation.rotateVector(vm.Vector3(0, 1, 0)).y;
      for (var i = 0; i < 120; i++) {
        buoyancy.update(1 / 60);
      }
      final afterMany = slow.rotation.rotateVector(vm.Vector3(0, 1, 0)).y;
      expect(
        afterOne,
        greaterThan(afterMany),
        reason: 'one frame of a slow response must not reach the target',
      );
    });
  });

  group('the water frame', () {
    test('a moved lake moves the surface the raft sits on', () {
      // The probes are sampled in the water's own frame, so raising the lake
      // has to raise what floats on it.
      final surface = lake();
      final waterNode = Node(name: 'lake')..position = vm.Vector3(0, 7, 0);
      waterNode.addComponent(surface);
      final floater = Node(name: 'raft')..position = vm.Vector3(0, 20, 0);
      final buoyancy = BuoyancyComponent();
      floater.addComponent(buoyancy);
      Node(name: 'level')
        ..add(waterNode)
        ..add(floater);

      buoyancy.update(1 / 60);
      expect(
        floater.position.y,
        closeTo(7 + surface.surfaceHeightAt(0, 0), 0.6),
      );
    });
  });

  group('submersion', () {
    test('reports how deep it is, and clears when it is out', () {
      final surface = lake(amplitude: 0.0);
      final under = Node(name: 'sunk')
        ..position = vm.Vector3(0, -3, 0)
        ..addComponent(
          BuoyancyComponent(water: surface, alignToSurface: false),
        );
      Node(name: 'level')
        ..add(Node(name: 'lake')..addComponent(surface))
        ..add(under);

      final buoyancy = under.getComponent<BuoyancyComponent>()!;
      buoyancy.update(1 / 60);
      expect(buoyancy.isFloating, isTrue);
      expect(buoyancy.submersion, closeTo(3, 1e-4));
    });
  });

  test('a clone floats the same way', () {
    final buoyancy = BuoyancyComponent(
      hullSize: 4,
      draft: 0.75,
      probeCount: 8,
      strength: 20,
    );
    Node(name: 'boat').addComponent(buoyancy);
    final clone = buoyancy.cloneFor(Node())! as BuoyancyComponent;
    expect(clone.hullSize, 4);
    expect(clone.draft, 0.75);
    expect(clone.probeCount, 8);
    expect(clone.strength, 20);
  });

  test('probe count is the per-frame cost, so it is bounded', () {
    // A value outside the supported set would silently spread probes wrong,
    // so the constructor refuses it rather than approximating.
    expect(() => BuoyancyComponent(probeCount: 3), throwsA(isA<Error>()));
    expect(BuoyancyComponent(probeCount: 8).probeCount, 8);
  });

  test('sampling one point agrees with displacing a grid of them', () {
    // Buoyancy samples points; the mesh displaces a grid. They have to be the
    // same surface or a boat floats next to the water it is on.
    final waves = lake().waves;
    final out = Float64List(GerstnerField.sampleStride);
    for (final x in const [-8.0, 0.0, 3.3, 11.0]) {
      GerstnerField.sampleInto(waves, 1.75, x, 0, out);
      final analytic = WaterSurfaceComponent(
        waves: waves,
      ).evaluateAt(vm.Vector2(x, 0), 1.75);
      // To float32, which is what the analytic side accumulates in: its
      // Vector3 is backed by a Float32List, while sampling keeps doubles all
      // the way through. Same surface, one of them carried more carefully.
      expect(out[1], closeTo(analytic.displacement.y, 1e-6));
      expect(out[4], closeTo(analytic.normal.y, 1e-6));
      expect(
        math.sqrt(out[3] * out[3] + out[4] * out[4] + out[5] * out[5]),
        closeTo(1, 1e-9),
      );
    }
  });
}
