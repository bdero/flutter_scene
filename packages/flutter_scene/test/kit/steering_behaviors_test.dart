import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('Steering Behaviors', () {
    test('seek generates force towards target', () {
      final currentPos = vm.Vector3(0, 0, 0);
      final currentVel = vm.Vector3(0, 0, 0);
      final targetPos = vm.Vector3(10, 0, 0);

      final force = Steering.seek(
        currentPos,
        currentVel,
        targetPos,
        maxSpeed: 5.0,
        maxForce: 2.0,
      );
      expect(force.x, greaterThan(0.0));
      expect(force.y, equals(0.0));
      expect(force.z, equals(0.0));
      expect(force.length, lessThanOrEqualTo(2.001));
    });

    test('flee generates force away from threat', () {
      final currentPos = vm.Vector3(0, 0, 0);
      final currentVel = vm.Vector3(0, 0, 0);
      final threatPos = vm.Vector3(5, 0, 0);

      final force = Steering.flee(
        currentPos,
        currentVel,
        threatPos,
        maxSpeed: 5.0,
        maxForce: 2.0,
      );
      expect(force.x, lessThan(0.0));
    });

    test('arrive slows down within radius', () {
      final currentPos = vm.Vector3(9.5, 0, 0);
      final currentVel = vm.Vector3(5, 0, 0);
      final targetPos = vm.Vector3(10, 0, 0);

      final force = Steering.arrive(
        currentPos,
        currentVel,
        targetPos,
        slowingRadius: 2.0,
        maxSpeed: 5.0,
      );
      expect(force.x, lessThan(0.0));
    });

    test('separation pushes away from nearby neighbors', () {
      final currentPos = vm.Vector3(0, 0, 0);
      final currentVel = vm.Vector3.zero();
      final neighbors = [vm.Vector3(0.5, 0, 0)];

      final force = Steering.separation(
        currentPos,
        currentVel,
        neighbors,
        desiredDistance: 2.0,
      );
      expect(force.x, lessThan(0.0));
    });
  });
}
