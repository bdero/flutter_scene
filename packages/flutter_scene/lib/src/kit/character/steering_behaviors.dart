import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;

/// Mathematical steering force algorithms for autonomous NPCs, wildlife, and flocking.
/// {@category Gameplay kit}
class Steering {
  /// Computes a steering force directing the entity towards [targetPos].
  static vm.Vector3 seek(
    vm.Vector3 currentPos,
    vm.Vector3 currentVel,
    vm.Vector3 targetPos, {
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    final desired = (targetPos - currentPos);
    if (desired.length2 == 0) return vm.Vector3.zero();
    final desiredVel = desired.normalized() * maxSpeed;
    final force = desiredVel - currentVel;
    return truncate(force, maxForce);
  }

  /// Computes a steering force directing the entity away from [threatPos].
  static vm.Vector3 flee(
    vm.Vector3 currentPos,
    vm.Vector3 currentVel,
    vm.Vector3 threatPos, {
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    final desired = (currentPos - threatPos);
    if (desired.length2 == 0) return vm.Vector3.zero();
    final desiredVel = desired.normalized() * maxSpeed;
    final force = desiredVel - currentVel;
    return truncate(force, maxForce);
  }

  /// Steers towards [targetPos], decelerating smoothly inside [slowingRadius].
  static vm.Vector3 arrive(
    vm.Vector3 currentPos,
    vm.Vector3 currentVel,
    vm.Vector3 targetPos, {
    double slowingRadius = 3.0,
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    final toTarget = targetPos - currentPos;
    final distance = toTarget.length;
    if (distance < 0.001) return -currentVel;

    final rampedSpeed = maxSpeed * (distance / slowingRadius);
    final targetSpeed = math.min(rampedSpeed, maxSpeed);
    final desiredVel = (toTarget / distance) * targetSpeed;
    final force = desiredVel - currentVel;
    return truncate(force, maxForce);
  }

  /// Computes a separation steering force avoiding crowding nearby [neighbors].
  static vm.Vector3 separation(
    vm.Vector3 currentPos,
    vm.Vector3 currentVel,
    List<vm.Vector3> neighbors, {
    double desiredDistance = 2.0,
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    var pushDir = vm.Vector3.zero();
    var count = 0;

    for (final other in neighbors) {
      final diff = currentPos - other;
      final dist = diff.length;
      if (dist > 0.001 && dist < desiredDistance) {
        pushDir += diff.normalized() / dist;
        count++;
      }
    }

    if (count == 0) return vm.Vector3.zero();
    pushDir /= count.toDouble();
    if (pushDir.length2 == 0) return vm.Vector3.zero();

    final desiredVel = pushDir.normalized() * maxSpeed;
    final force = desiredVel - currentVel;
    return truncate(force, maxForce);
  }

  /// Computes an alignment force steering towards the average velocity of [neighborVelocities].
  static vm.Vector3 alignment(
    vm.Vector3 currentVel,
    List<vm.Vector3> neighborVelocities, {
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    if (neighborVelocities.isEmpty) return vm.Vector3.zero();
    var avgVel = vm.Vector3.zero();
    for (final v in neighborVelocities) {
      avgVel += v;
    }
    avgVel /= neighborVelocities.length.toDouble();
    if (avgVel.length2 == 0) return vm.Vector3.zero();

    final desired = avgVel.normalized() * maxSpeed;
    final force = desired - currentVel;
    return truncate(force, maxForce);
  }

  /// Computes a cohesion force steering towards the center of mass of [neighborPositions].
  static vm.Vector3 cohesion(
    vm.Vector3 currentPos,
    vm.Vector3 currentVel,
    List<vm.Vector3> neighborPositions, {
    double maxSpeed = 5.0,
    double maxForce = 10.0,
  }) {
    if (neighborPositions.isEmpty) return vm.Vector3.zero();
    var center = vm.Vector3.zero();
    for (final p in neighborPositions) {
      center += p;
    }
    center /= neighborPositions.length.toDouble();
    return seek(
      currentPos,
      currentVel,
      center,
      maxSpeed: maxSpeed,
      maxForce: maxForce,
    );
  }

  /// Clamps the magnitude of [vector] to [max].
  static vm.Vector3 truncate(vm.Vector3 vector, double max) {
    if (vector.length2 > max * max) {
      return vector.normalized() * max;
    }
    return vector;
  }
}
