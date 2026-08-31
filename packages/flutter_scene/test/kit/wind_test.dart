// One wind, read by everything. What matters is that the sharing works: a
// gust has to reach the rain and the clouds on the same frame, and the
// alternative -- a constant per effect -- is what this replaces.

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// A system with [count] particles already alive, moving at rest.
ParticleSystem still({required List<ParticleModule> modules, int count = 8}) {
  final system = ParticleSystem(
    maxParticles: 16,
    spawner: Spawner(bursts: [ParticleBurst(time: 0, count: count)]),
    shape: PointEmitterShape(),
    modules: modules,
    gravity: vm.Vector3.zero(),
    lifetime: const ConstantFloat(30),
    startSpeed: const ConstantFloat(0),
  );
  system.step(1 / 60);
  return system;
}

void main() {
  group('the wind itself', () {
    test('blows along its direction, on the ground plane', () {
      final wind = Wind(
        direction: vm.Vector2(0, 2),
        speed: 5,
        gustAmplitude: 0,
      );
      final velocity = wind.velocity;
      expect(velocity.x, closeTo(0, 1e-9));
      expect(velocity.y, 0, reason: 'wind is horizontal');
      expect(velocity.z, closeTo(5, 1e-9));
    });

    test('the direction is normalized however it is given', () {
      final wind = Wind(direction: vm.Vector2(3, 4), gustAmplitude: 0);
      // Vector2 is float32-backed, so unit means unit to float precision.
      expect(wind.direction.length, closeTo(1, 1e-6));
      wind.setDirection(vm.Vector2(0, -10));
      expect(wind.direction.y, closeTo(-1, 1e-6));
    });

    test('a zero heading is ignored rather than making it directionless', () {
      final wind = Wind(direction: vm.Vector2(1, 0));
      wind.setDirection(vm.Vector2.zero());
      expect(wind.direction.x, closeTo(1, 1e-9));
    });

    test('the gust rises and falls, and never reverses the wind', () {
      final wind = Wind(speed: 4, gustAmplitude: 1.5, gustFrequency: 1);
      var minimum = double.infinity;
      var maximum = -double.infinity;
      for (var i = 0; i < 600; i++) {
        wind.advance(1 / 60);
        final speed = wind.gustedSpeed;
        expect(speed, greaterThanOrEqualTo(0));
        if (speed < minimum) minimum = speed;
        if (speed > maximum) maximum = speed;
      }
      expect(maximum, greaterThan(4));
      expect(minimum, lessThan(4));
    });

    test('no gust amplitude is a constant', () {
      final wind = Wind(speed: 7, gustAmplitude: 0);
      for (var i = 0; i < 30; i++) {
        wind.advance(1 / 60);
        expect(wind.gustedSpeed, closeTo(7, 1e-9));
      }
    });

    test('the same time gives the same wind, so a replay matches', () {
      final a = Wind(speed: 5, seed: 42)..advance(3.25);
      final b = Wind(speed: 5, seed: 42)..time = 3.25;
      expect(a.gustedSpeed, closeTo(b.gustedSpeed, 1e-12));
    });

    test('different seeds gust at different moments', () {
      final a = Wind(speed: 5, seed: 1)..advance(2);
      final b = Wind(speed: 5, seed: 900)..advance(2);
      expect(a.gustedSpeed, isNot(closeTo(b.gustedSpeed, 1e-6)));
    });
  });

  group('particles in the wind', () {
    test('particles are carried toward the wind, not accelerated past it', () {
      final wind = Wind(
        direction: vm.Vector2(1, 0),
        speed: 6,
        gustAmplitude: 0,
      );
      final system = still(modules: [WindModule(wind: wind, response: 4)]);
      for (var i = 0; i < 300; i++) {
        system.step(1 / 60);
      }
      expect(system.storage.velX[0], closeTo(6, 1e-3));
      expect(system.storage.velY[0], closeTo(0, 1e-9));
    });

    test('response is how much of the wind a particle takes', () {
      final wind = Wind(
        direction: vm.Vector2(1, 0),
        speed: 10,
        gustAmplitude: 0,
      );
      final leaf = still(modules: [WindModule(wind: wind, response: 4)]);
      final stone = still(modules: [WindModule(wind: wind, response: 0.2)]);
      for (var i = 0; i < 30; i++) {
        leaf.step(1 / 60);
        stone.step(1 / 60);
      }
      expect(leaf.storage.velX[0], greaterThan(stone.storage.velX[0]));
    });

    test('no response is a module that does nothing', () {
      final wind = Wind(speed: 10, gustAmplitude: 0);
      final system = still(modules: [WindModule(wind: wind, response: 0)]);
      for (var i = 0; i < 30; i++) {
        system.step(1 / 60);
      }
      expect(system.storage.velX[0], closeTo(0, 1e-9));
    });

    test('two effects on one wind lean together', () {
      // The whole point. Both systems read the same object, so the gust that
      // moves one moves the other on the same frame.
      final wind = Wind(
        direction: vm.Vector2(1, 0),
        speed: 8,
        gustAmplitude: 0.9,
        gustFrequency: 0.5,
      );
      final rain = still(modules: [WindModule(wind: wind, response: 0.5)]);
      final snow = still(modules: [WindModule(wind: wind, response: 0.5)]);
      for (var i = 0; i < 120; i++) {
        wind.advance(1 / 60);
        rain.step(1 / 60);
        snow.step(1 / 60);
      }
      expect(rain.storage.velX[0], closeTo(snow.storage.velX[0], 1e-9));
      expect(rain.storage.velX[0], greaterThan(0));
    });

    test('a module with no wind of its own reads the scene ambient', () {
      final module = WindModule();
      expect(module.wind, same(Wind.ambient));
    });
  });

  group('the component', () {
    test('advances the wind it drives', () {
      final wind = Wind(speed: 5, gustAmplitude: 0.5, gustFrequency: 1);
      final component = WindComponent(wind: wind);
      Node(name: 'stage').addComponent(component);

      final before = wind.gustedSpeed;
      for (var i = 0; i < 30; i++) {
        component.update(1 / 60);
      }
      expect(wind.time, closeTo(0.5, 1e-6));
      expect(wind.gustedSpeed, isNot(closeTo(before, 1e-6)));
    });

    test('with no wind of its own it drives the scene ambient', () {
      expect(WindComponent().wind, same(Wind.ambient));
    });

    test('a scene with no weather sky is not an error', () {
      final component = WindComponent();
      Node(name: 'stage').addComponent(component);
      component.update(1 / 60);
      expect(component.driveSky, isTrue);
    });

    test('a clone drives the same wind', () {
      final wind = Wind(speed: 3);
      final original = WindComponent(wind: wind, driveSky: false)
        ..skyScale = 0.5;
      final clone = original.cloneFor(Node())! as WindComponent;
      expect(clone.wind, same(wind));
      expect(clone.driveSky, isFalse);
      expect(clone.skyScale, 0.5);
    });
  });
}
