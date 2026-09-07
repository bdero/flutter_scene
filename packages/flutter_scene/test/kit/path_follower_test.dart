// Covers PathFollowerComponent: it walks waypoints at a bounded speed without
// overshooting, turns to face travel, reports arrival once, and can steer a
// character instead of moving the node itself.

import 'dart:math' as math;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

Vector3 _positionOf(Node node) => node.globalTransform.getTranslation();

double _yawOf(Node node) {
  final s = node.globalTransform.storage;
  return math.atan2(s[8], s[10]);
}

void _run(
  PathFollowerComponent follower,
  double seconds, {
  double step = 1 / 60,
}) {
  for (var t = 0.0; t < seconds - 1e-9; t += step) {
    follower.update(step);
  }
}

void main() {
  group('PathFollowerComponent', () {
    late Node unit;
    late PathFollowerComponent follower;

    setUp(() {
      unit = Node();
      follower = PathFollowerComponent(speed: 4.0);
      unit.addComponent(follower);
    });

    test('starts idle', () {
      expect(follower.isMoving, isFalse);
      expect(follower.destination, isNull);
      expect(follower.remainingDistance, 0.0);
    });

    test('walks to a destination at its speed', () {
      follower.moveTo(Vector3(0.0, 0.0, 10.0));
      expect(follower.isMoving, isTrue);

      _run(follower, 1.0);
      // Four units per second, give or take one frame of arrival slack.
      expect(_positionOf(unit).z, closeTo(4.0, 0.1));
      expect(follower.isMoving, isTrue);

      _run(follower, 2.0);
      expect(follower.isMoving, isFalse);
      expect(_positionOf(unit).z, closeTo(10.0, follower.arriveRadius));
    });

    test('never overshoots on a long frame', () {
      follower.moveTo(Vector3(0.0, 0.0, 2.0));
      // One frame long enough to cover forty units at this speed.
      follower.update(10.0);
      expect(_positionOf(unit).z, lessThanOrEqualTo(2.0 + 1e-6));
    });

    test('follows a multi-point route through each waypoint', () {
      follower.follow([
        Vector3(0.0, 0.0, 0.0),
        Vector3(0.0, 0.0, 5.0),
        Vector3(5.0, 0.0, 5.0),
      ]);

      final visited = <Vector3>[];
      for (var i = 0; i < 600; i++) {
        follower.update(1 / 60);
        visited.add(_positionOf(unit));
        if (!follower.isMoving) break;
      }

      expect(follower.isMoving, isFalse);
      final end = _positionOf(unit);
      expect(end.x, closeTo(5.0, 0.2));
      expect(end.z, closeTo(5.0, 0.2));
      // It went via the corner rather than cutting straight across.
      expect(visited.any((point) => point.z > 4.5 && point.x < 1.0), isTrue);
    });

    test('skips a first waypoint it is already standing on', () {
      // Nav meshes return the start point as waypoint zero; steering toward a
      // point underfoot for a frame reads as a twitch.
      follower.follow([Vector3.zero(), Vector3(0.0, 0.0, 6.0)]);
      expect(follower.nextWaypoint!.z, closeTo(6.0, 1e-6));
    });

    test('a route that is entirely underfoot is not a journey', () {
      var arrived = 0;
      follower.onArrived = () => arrived++;
      follower.follow([Vector3.zero()]);

      expect(follower.isMoving, isFalse);
      expect(arrived, 0);
    });

    test('reports arrival exactly once', () {
      var arrived = 0;
      follower.onArrived = () => arrived++;
      follower.moveTo(Vector3(0.0, 0.0, 2.0));

      _run(follower, 3.0);
      expect(arrived, 1);
      _run(follower, 3.0);
      expect(arrived, 1);
    });

    test('stop abandons the route and says so', () {
      var stopped = 0;
      follower.onStopped = () => stopped++;
      follower.moveTo(Vector3(0.0, 0.0, 20.0));
      _run(follower, 0.5);

      final where = _positionOf(unit);
      follower.stop();
      expect(follower.isMoving, isFalse);
      expect(stopped, 1);

      _run(follower, 1.0);
      expect(_positionOf(unit).z, closeTo(where.z, 1e-6));

      // A second stop is not a second abandonment.
      follower.stop();
      expect(stopped, 1);
    });

    test('turns to face where it is going', () {
      follower.moveTo(Vector3(10.0, 0.0, 0.0));
      _run(follower, 1.0);
      // Facing +X is a yaw of pi/2 in this convention.
      expect(_yawOf(unit), closeTo(math.pi / 2, 0.05));
    });

    test('turns at a bounded rate rather than snapping', () {
      follower.turnSpeed = 1.0; // radians per second
      follower.moveTo(Vector3(10.0, 0.0, 0.0));
      follower.update(1 / 60);
      expect(_yawOf(unit).abs(), lessThan(0.1));
    });

    test('keeps its facing when told not to turn', () {
      follower.facesTravel = false;
      follower.moveTo(Vector3(10.0, 0.0, 0.0));
      _run(follower, 1.0);
      expect(_yawOf(unit), closeTo(0.0, 1e-6));
      expect(_positionOf(unit).x, greaterThan(1.0));
    });

    test('reports remaining distance along the route', () {
      follower.follow([
        Vector3.zero(),
        Vector3(0.0, 0.0, 3.0),
        Vector3(4.0, 0.0, 3.0),
      ]);
      expect(follower.remainingDistance, closeTo(7.0, 1e-5));
      _run(follower, 0.5);
      expect(follower.remainingDistance, lessThan(7.0));
    });

    test('steers a character instead of moving the node', () {
      final directions = <Vector3>[];
      follower.steer = (direction, fraction) => directions.add(direction);
      follower.moveTo(Vector3(0.0, 0.0, 10.0));

      _run(follower, 0.5);
      expect(directions, isNotEmpty);
      expect(directions.last.z, closeTo(1.0, 1e-6));
      // The node did not move: something else owns the transform.
      expect(_positionOf(unit).length, closeTo(0.0, 1e-9));
    });

    test('tells a steered character to stop on arrival', () {
      final fractions = <double>[];
      follower.steer = (direction, fraction) => fractions.add(fraction);
      follower.moveTo(Vector3(0.0, 0.0, 0.05)); // inside arriveRadius already

      follower.follow([Vector3(0.0, 0.0, 2.0)]);
      // Nothing moves the node, so it never arrives on its own; stopping is
      // what has to reset the character's input.
      _run(follower, 0.2);
      follower.stop();
      expect(fractions.last, 0.0);
    });

    test('eases off approaching the final waypoint', () {
      follower.slowRadius = 3.0;
      final fractions = <double>[];
      follower.steer = (direction, fraction) => fractions.add(fraction);
      follower.moveTo(Vector3(0.0, 0.0, 2.0));

      follower.update(1 / 60);
      expect(fractions.last, lessThan(1.0));
      expect(fractions.last, greaterThan(0.0));
    });
  });
}
