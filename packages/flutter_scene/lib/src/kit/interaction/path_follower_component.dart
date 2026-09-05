import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';

/// Walks its node along a list of waypoints: the movement half of click-to-move.
///
/// Click-to-move is three pieces that already exist separately — a ray into
/// the world (`ScenePicker`, or `GridPicking`), a route across it
/// (`NavMeshQuery.findPath` from `package:flutter_scene/navigation.dart`, or
/// `findGridPath` from `package:flutter_scene/grid.dart`), and something that
/// actually walks the route. This is that third piece, and it takes plain
/// waypoints so it does not care which of the two produced them.
///
/// ```dart
/// final walker = PathFollowerComponent(speed: 4.0);
/// unit.addComponent(walker);
///
/// // On a click:
/// final hit = picker.hitAt(position, camera: camera, viewSize: viewSize);
/// if (hit != null) {
///   walker.follow(query.findPath(unit.globalTransform.getTranslation(),
///       hit.worldPoint).points);
/// }
/// ```
///
/// ## Moving the node, or steering a character
///
/// By default the component moves its node directly, which is right for a
/// strategy unit or anything else without physics. When the thing being moved
/// is a physical character, set [steer] instead: the component then reports
/// the direction to travel each frame and moves nothing itself, so a
/// `ThirdPersonControllerComponent` (or a physics character controller) stays
/// the only thing touching the transform.
///
/// ```dart
/// walker.steer = (direction, speedFraction) => character.setMoveInput(
///   Vector2(direction.x, direction.z) * speedFraction,
/// );
/// ```
/// {@category Gameplay kit}
class PathFollowerComponent extends Component {
  /// Creates a follower.
  PathFollowerComponent({
    this.speed = 4.0,
    this.turnSpeed = 10.0,
    this.arriveRadius = 0.15,
    this.slowRadius = 0.0,
    this.facesTravel = true,
    this.steer,
    this.onArrived,
    this.onStopped,
  });

  /// Travel rate in world units per second.
  double speed;

  /// How fast the node turns to face its travel direction, in radians per
  /// second. Ignored when [facesTravel] is false or when [steer] is set.
  double turnSpeed;

  /// How close counts as reaching a waypoint, in world units.
  ///
  /// Too small and a mover circles its destination forever, unable to land
  /// exactly on it; the default is a reasonable fraction of a human-scaled
  /// character.
  double arriveRadius;

  /// The distance from the *final* waypoint at which the mover starts easing
  /// off, in world units. Zero stops dead on arrival.
  double slowRadius;

  /// Whether the node turns to face where it is going. Off for something that
  /// keeps a fixed facing, such as a top-down sprite.
  bool facesTravel;

  /// When set, the component stops moving the node and calls this instead
  /// with the unit direction to travel and how much of [speed] to use
  /// (`0` to `1`), for driving a character controller.
  void Function(Vector3 direction, double speedFraction)? steer;

  /// Called once on reaching the last waypoint.
  void Function()? onArrived;

  /// Called when [stop] cuts a journey short.
  void Function()? onStopped;

  List<Vector3> _waypoints = const <Vector3>[];
  int _index = 0;

  /// The route being walked, empty when idle.
  List<Vector3> get waypoints => List<Vector3>.unmodifiable(_waypoints);

  /// Whether a route is being walked.
  bool get isMoving => _index < _waypoints.length;

  /// The final waypoint, or null when idle.
  Vector3? get destination =>
      _waypoints.isEmpty ? null : _waypoints.last.clone();

  /// The waypoint currently being walked toward, or null when idle.
  Vector3? get nextWaypoint => isMoving ? _waypoints[_index].clone() : null;

  /// The straight-line distance still to cover, following the remaining
  /// waypoints. Zero when idle.
  double get remainingDistance {
    if (!isMoving || !isAttached) return 0.0;
    var total =
        (_waypoints[_index] - node.globalTransform.getTranslation()).length;
    for (var i = _index + 1; i < _waypoints.length; i++) {
      total += (_waypoints[i] - _waypoints[i - 1]).length;
    }
    return total;
  }

  /// Starts walking [waypoints], replacing any route in progress.
  ///
  /// An empty or single-point route is treated as "already there": the mover
  /// stops, and [onArrived] does not fire, because nothing was travelled. A
  /// route that could not reach its goal is still worth following — check the
  /// path's own status (`NavPath.status`, `GridPath.reachedGoal`) to tell the
  /// player their order failed.
  void follow(List<Vector3> waypoints) {
    _waypoints = <Vector3>[for (final point in waypoints) point.clone()];
    _index = 0;
    // The first waypoint is normally where the mover already stands; skipping
    // it avoids a frame of steering toward a point underfoot, which reads as
    // a twitch.
    _skipReachedWaypoints();
  }

  /// Walks straight to [destination] with no route-finding, for open ground.
  void moveTo(Vector3 destination) => follow(<Vector3>[destination]);

  /// Abandons the current route where it stands.
  void stop() {
    if (!isMoving) {
      _waypoints = const <Vector3>[];
      _index = 0;
      return;
    }
    _waypoints = const <Vector3>[];
    _index = 0;
    steer?.call(Vector3.zero(), 0.0);
    onStopped?.call();
  }

  @override
  void update(double deltaSeconds) {
    if (!isMoving || deltaSeconds <= 0.0) return;

    final position = node.globalTransform.getTranslation();
    final target = _waypoints[_index];
    final toTarget = target - position;
    // Travel is planar: the ground decides height, not the route.
    final planar = Vector3(toTarget.x, 0.0, toTarget.z);
    final distance = planar.length;

    if (distance <= arriveRadius) {
      _index++;
      if (!isMoving) {
        _arrive();
        return;
      }
      return;
    }

    final direction = planar / distance;
    final fraction = _speedFraction(distance);

    final drive = steer;
    if (drive != null) {
      // Something else owns the transform; only report the intent.
      drive(direction, fraction);
      return;
    }

    final step = speed * fraction * deltaSeconds;
    // Never overshoot: a fast mover and a slow frame would otherwise sail
    // past the waypoint and turn back on the next one.
    final travelled = math.min(step, distance);
    final moved = position + direction * travelled;
    node.globalTransform = _transformFacing(direction, moved, deltaSeconds);
  }

  /// How much of [speed] to use, easing off inside [slowRadius] of the final
  /// waypoint.
  double _speedFraction(double distanceToWaypoint) {
    if (slowRadius <= 0.0 || _index != _waypoints.length - 1) return 1.0;
    return (distanceToWaypoint / slowRadius).clamp(0.05, 1.0);
  }

  Matrix4 _transformFacing(
    Vector3 direction,
    Vector3 position,
    double deltaSeconds,
  ) {
    final world = node.globalTransform;
    if (!facesTravel) {
      return world.clone()..setTranslation(position);
    }
    final scale = Vector3(
      Vector3(world[0], world[1], world[2]).length,
      Vector3(world[4], world[5], world[6]).length,
      Vector3(world[8], world[9], world[10]).length,
    );
    final current = Vector3(world[8], world[9], world[10]);
    final facing = Vector3(current.x, 0.0, current.z);
    // Turn toward the direction of travel at a bounded rate, so a sharp
    // corner is a turn rather than a snap.
    final desiredYaw = math.atan2(direction.x, direction.z);
    final currentYaw = facing.length2 < 1e-9
        ? desiredYaw
        : math.atan2(facing.x, facing.z);
    var delta = desiredYaw - currentYaw;
    // Take the short way round.
    while (delta > math.pi) {
      delta -= math.pi * 2;
    }
    while (delta < -math.pi) {
      delta += math.pi * 2;
    }
    final maxTurn = turnSpeed * deltaSeconds;
    final yaw = currentYaw + delta.clamp(-maxTurn, maxTurn);

    return Matrix4.compose(
      position,
      Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw),
      scale,
    );
  }

  void _skipReachedWaypoints() {
    if (!isAttached || _waypoints.isEmpty) return;
    final position = node.globalTransform.getTranslation();
    while (isMoving) {
      final target = _waypoints[_index];
      final planar = Vector3(target.x - position.x, 0.0, target.z - position.z);
      if (planar.length > arriveRadius) return;
      _index++;
    }
    // Every waypoint was already underfoot: there was no journey to make, so
    // this is not an arrival.
    _waypoints = const <Vector3>[];
    _index = 0;
  }

  void _arrive() {
    _waypoints = const <Vector3>[];
    _index = 0;
    steer?.call(Vector3.zero(), 0.0);
    onArrived?.call();
  }
}
