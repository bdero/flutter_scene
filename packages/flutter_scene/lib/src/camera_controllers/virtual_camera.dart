/// Virtual cameras: a shot described as *where to stand* and *what to watch*,
/// rather than as a controller with its own opinions about both.
///
/// A [CameraDirector] already does the half of this that people notice — it
/// picks the live shot by priority and blends between them. What it holds are
/// controllers, and a controller is a whole hand-written camera. That is the
/// wrong unit for a scene with a dozen shots in it: eleven of them are "sit
/// here relative to that, and keep this in frame", and writing eleven
/// controllers to say so means eleven places for the damping to be subtly
/// different.
///
/// So a [VirtualCamera] is a controller assembled from two parts. A
/// [CameraBody] decides where the camera *is*; a [CameraAim] decides where it
/// *points*. Both are small, both are reusable, and a shot is a choice of one
/// of each plus a priority. That split is worth making because it is the
/// decomposition the problem actually has: where to stand and what to watch
/// are chosen independently, and a shot is one answer to each.
///
/// **Damping is a time, not a factor.** Every damping value here is roughly
/// the seconds the camera takes to close the distance, and every one is
/// applied frame-rate independently, so a shot tuned at 60fps behaves the same
/// at 30 or 144. A factor-per-frame would not, and a camera that lags
/// differently on a slower machine is a camera that has to be retuned per
/// machine.
///
/// **The solve reuses its working state.** A camera solves every frame for the
/// life of a scene, so the bodies write through scratch vectors they own and
/// the context is filled in place rather than rebuilt. What is still allocated
/// each frame is the pose itself, which is a value the director keeps.
///
/// **Rotations go through [QuaternionRotate].** vector_math's `Quaternion.rotate`
/// applies the inverse of the rotation `Matrix4.compose` builds from the same
/// quaternion, and the scene graph is on the matrix side of that; a body using
/// it would put the camera in front of the character instead of behind.
///
/// Pure Dart and `vector_math` throughout: no `dart:io`, nothing
/// platform-specific, so this runs wherever the engine does.
library;

import 'dart:math' as math;

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart';

/// Moves [current] toward [target] with an exponential ease of [damping]
/// seconds, independent of frame rate.
///
/// Zero damping snaps. The curve is the one the rest of the camera code uses,
/// so a body and an aim damped by the same number settle together.
double dampScalar(
  double current,
  double target,
  double damping,
  double deltaSeconds,
) {
  if (damping <= 0 || deltaSeconds <= 0) return target;
  // 1% remaining after `damping` seconds, which is what "settle time" means
  // everywhere else in this package.
  final t = 1 - math.exp(-deltaSeconds * 4.6 / damping);
  return current + (target - current) * t;
}

/// [dampScalar] per axis, written into [out].
///
/// Per axis rather than on the vector's length, because the difference is
/// visible: a camera that eases sideways
/// faster than it eases in depth is a camera that keeps its distance while it
/// catches up laterally, which is what a follow shot wants.
void dampVector(
  Vector3 current,
  Vector3 target,
  Vector3 damping,
  double deltaSeconds,
  Vector3 out,
) {
  out
    ..x = dampScalar(current.x, target.x, damping.x, deltaSeconds)
    ..y = dampScalar(current.y, target.y, damping.y, deltaSeconds)
    ..z = dampScalar(current.z, target.z, damping.z, deltaSeconds);
}

/// What a body or an aim is given to solve with.
///
/// Reused between frames rather than rebuilt, since a camera solves sixty
/// times a second forever.
class CameraSolveContext {
  CameraSolveContext();

  /// Where the follow target is, in world space.
  final Vector3 followPosition = Vector3.zero();

  /// The follow target's rotation, for bodies that stay behind it.
  Quaternion followRotation = Quaternion.identity();

  /// Whether there is a follow target at all.
  bool hasFollow = false;

  /// Where the look-at target is, in world space.
  final Vector3 lookAtPosition = Vector3.zero();

  /// Whether there is a look-at target at all.
  bool hasLookAt = false;

  /// Where the camera was last frame, which damping eases from.
  final Vector3 previousPosition = Vector3.zero();

  /// Seconds since the last solve.
  double deltaSeconds = 1 / 60;

  /// Whether this is the first solve, which snaps rather than eases.
  ///
  /// A shot that eased in from wherever the camera happened to be would swing
  /// across the level the first time it went live.
  bool isFirstFrame = true;
}

// --- bodies ------------------------------------------------------------------

/// Decides where a virtual camera stands.
abstract class CameraBody {
  /// Writes this frame's position into [out].
  void solve(CameraSolveContext context, Vector3 out);
}

/// How a [TransposerBody]'s offset is oriented.
enum CameraBinding {
  /// The offset is in world axes: the camera keeps its compass bearing while
  /// the target turns underneath it.
  worldSpace,

  /// The offset turns with the target's heading but stays upright, which is
  /// the usual third-person follow: behind the character, never rolled.
  lockToTargetWithWorldUp,

  /// The offset turns with the target completely, roll included. For a camera
  /// bolted to something that banks.
  lockToTarget,
}

/// Sits at a fixed offset from the target.
///
/// The simplest body there is, and the one most shots want.
class TransposerBody extends CameraBody {
  TransposerBody({
    Vector3? offset,
    this.binding = CameraBinding.lockToTargetWithWorldUp,
    Vector3? damping,
  }) : offset = offset ?? Vector3(0, 2, -6),
       damping = damping ?? Vector3.all(0.3);

  /// Where the camera sits relative to the target.
  final Vector3 offset;

  /// Which axes that offset is measured in.
  CameraBinding binding;

  /// Seconds to close the distance, per axis.
  final Vector3 damping;

  final Vector3 _wanted = Vector3.zero();
  final Vector3 _rotated = Vector3.zero();

  @override
  void solve(CameraSolveContext context, Vector3 out) {
    if (!context.hasFollow) {
      out.setFrom(context.previousPosition);
      return;
    }
    switch (binding) {
      case CameraBinding.worldSpace:
        _rotated.setFrom(offset);
      case CameraBinding.lockToTarget:
        context.followRotation.rotateVectorInto(offset, _rotated);
      case CameraBinding.lockToTargetWithWorldUp:
        // The target's heading only: a character that pitches or rolls should
        // not take the camera with it, or looking down a slope rolls the shot.
        _headingOnly(context.followRotation).rotateVectorInto(offset, _rotated);
    }
    _wanted
      ..setFrom(context.followPosition)
      ..add(_rotated);
    if (context.isFirstFrame) {
      out.setFrom(_wanted);
      return;
    }
    dampVector(
      context.previousPosition,
      _wanted,
      damping,
      context.deltaSeconds,
      out,
    );
  }
}

/// The heading part of [rotation]: its yaw about world up, with pitch and roll
/// discarded.
Quaternion _headingOnly(Quaternion rotation) {
  final forward = rotation.rotateVector(Vector3(0, 0, 1));
  final yaw = math.atan2(forward.x, forward.z);
  return Quaternion.axisAngle(Vector3(0, 1, 0), yaw);
}

/// Holds the target at a distance and lets it move inside a dead zone before
/// following.
///
/// The body that makes a follow camera feel deliberate rather than glued: without a dead zone every twitch of the
/// target moves the camera, and the shot never sits still.
class FramingTransposerBody extends CameraBody {
  FramingTransposerBody({
    this.distance = 8,
    this.height = 2,
    this.deadZone = 0.6,
    Vector3? damping,
  }) : damping = damping ?? Vector3.all(0.4);

  /// How far back the camera sits.
  double distance;

  /// How far above the target it sits.
  double height;

  /// How far the target may move, in world units, before the camera follows.
  double deadZone;

  /// Seconds to close the distance, per axis.
  final Vector3 damping;

  final Vector3 _anchor = Vector3.zero();
  final Vector3 _wanted = Vector3.zero();
  final Vector3 _back = Vector3.zero();
  bool _hasAnchor = false;

  @override
  void solve(CameraSolveContext context, Vector3 out) {
    if (!context.hasFollow) {
      out.setFrom(context.previousPosition);
      return;
    }
    if (!_hasAnchor || context.isFirstFrame) {
      _anchor.setFrom(context.followPosition);
      _hasAnchor = true;
    } else {
      // The anchor only moves once the target has left the dead zone, and
      // then only as far as the zone's edge -- so the camera resumes from the
      // boundary rather than jumping to the target.
      final dx = context.followPosition.x - _anchor.x;
      final dy = context.followPosition.y - _anchor.y;
      final dz = context.followPosition.z - _anchor.z;
      final distanceOut = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (distanceOut > deadZone) {
        final pull = (distanceOut - deadZone) / distanceOut;
        _anchor
          ..x += dx * pull
          ..y += dy * pull
          ..z += dz * pull;
      }
    }

    _headingOnly(
      context.followRotation,
    ).rotateVectorInto(_back..setValues(0, 0, -distance), _back);
    _wanted
      ..setFrom(_anchor)
      ..add(_back)
      ..y += height;

    if (context.isFirstFrame) {
      out.setFrom(_wanted);
      return;
    }
    dampVector(
      context.previousPosition,
      _wanted,
      damping,
      context.deltaSeconds,
      out,
    );
  }
}

/// Orbits the target at a radius and a heading you drive.
///
/// No input binding of its own: the heading is a plain field, so a character
/// controller, a script or a graph can turn it without this needing to know
/// which.
class OrbitalBody extends CameraBody {
  OrbitalBody({
    this.radius = 6,
    this.height = 2,
    this.heading = 0,
    Vector3? damping,
  }) : damping = damping ?? Vector3.all(0.25);

  /// How far out the camera orbits.
  double radius;

  /// How far above the target it rides.
  double height;

  /// Where on the orbit it sits, in radians about world up.
  double heading;

  /// Seconds to close the distance, per axis.
  final Vector3 damping;

  final Vector3 _wanted = Vector3.zero();

  @override
  void solve(CameraSolveContext context, Vector3 out) {
    if (!context.hasFollow) {
      out.setFrom(context.previousPosition);
      return;
    }
    _wanted
      ..x = context.followPosition.x + math.sin(heading) * radius
      ..y = context.followPosition.y + height
      ..z = context.followPosition.z + math.cos(heading) * radius;
    if (context.isFirstFrame) {
      out.setFrom(_wanted);
      return;
    }
    dampVector(
      context.previousPosition,
      _wanted,
      damping,
      context.deltaSeconds,
      out,
    );
  }
}

// --- aims --------------------------------------------------------------------

/// Decides where a virtual camera points.
abstract class CameraAim {
  /// The rotation for this frame, given where the camera ended up.
  Quaternion solve(CameraSolveContext context, Vector3 position);
}

/// Keeps the camera pointed exactly at the target.
///
/// No easing, no framing, the target dead centre.
class HardLookAtAim extends CameraAim {
  HardLookAtAim();

  Quaternion _last = Quaternion.identity();

  @override
  Quaternion solve(CameraSolveContext context, Vector3 position) {
    if (!context.hasLookAt) return _last;
    return _last = lookRotation(context.lookAtPosition - position);
  }
}

/// Keeps the target in frame, letting it drift inside a dead zone.
///
/// The dead zone is what stops the camera answering every small movement; past it the camera turns, damped, until the target is
/// back inside. Without it a look-at camera jitters with its target and the
/// shot never settles.
class ComposerAim extends CameraAim {
  ComposerAim({this.deadZoneDegrees = 4, this.damping = 0.35});

  /// How far off centre, in degrees, the target may drift untracked.
  double deadZoneDegrees;

  /// Seconds to bring it back once it is outside.
  double damping;

  Quaternion _current = Quaternion.identity();
  bool _started = false;

  @override
  Quaternion solve(CameraSolveContext context, Vector3 position) {
    if (!context.hasLookAt) return _current;
    final wanted = lookRotation(context.lookAtPosition - position);
    if (!_started || context.isFirstFrame) {
      _started = true;
      return _current = wanted;
    }
    // Inside the dead zone the camera holds still. Measured as the angle
    // between where it points and where the target is, which is the same
    // measure whatever the distance -- a dead zone in world units would grow
    // and shrink as the target moved away.
    final apart = _angleBetween(_current, wanted);
    if (apart <= deadZoneDegrees * math.pi / 180) return _current;
    final t = damping <= 0
        ? 1.0
        : 1 - math.exp(-context.deltaSeconds * 4.6 / damping);
    return _current = _current.slerp(wanted, t);
  }
}

/// Leaves the camera's rotation alone, for a body that aims itself.
class FixedAim extends CameraAim {
  FixedAim({Quaternion? rotation})
    : rotation = rotation ?? Quaternion.identity();

  /// The rotation held every frame.
  Quaternion rotation;

  @override
  Quaternion solve(CameraSolveContext context, Vector3 position) => rotation;
}

/// A rotation whose local `+Z` points along [direction], upright about world
/// up.
///
/// Returns identity for a degenerate direction rather than producing a NaN
/// quaternion: a camera on top of its target is a mistake to survive, not one
/// to crash on.
Quaternion lookRotation(Vector3 direction, {Vector3? up}) {
  final forward = direction.length2 < 1e-12
      ? Vector3(0, 0, 1)
      : direction.normalized();
  final reference = up ?? Vector3(0, 1, 0);
  var right = reference.cross(forward);
  if (right.length2 < 1e-12) {
    // Looking straight up or down: any right vector will do, so pick one that
    // is definitely not parallel.
    right = Vector3(1, 0, 0).cross(forward);
    if (right.length2 < 1e-12) right = Vector3(0, 0, 1).cross(forward);
  }
  right.normalize();
  final realUp = forward.cross(right)..normalize();
  return Quaternion.fromRotation(
    Matrix3.columns(right, realUp, forward),
  ).normalized();
}

/// The angle in radians between two rotations, the short way round.
double _angleBetween(Quaternion a, Quaternion b) =>
    2 * math.acos(a.dot(b).abs().clamp(-1.0, 1.0));

// --- the camera --------------------------------------------------------------

/// One shot: where to stand, what to watch, and how badly it wants to be live.
///
/// A [CameraController], so a [CameraDirector] holds and blends it like any
/// other camera — the director is the Brain, and this is what it chooses
/// between.
///
/// ```dart
/// final shoulder = VirtualCamera(
///   follow: hero,
///   lookAt: hero,
///   body: FramingTransposerBody(distance: 5, height: 1.8),
///   aim: ComposerAim(),
/// );
/// director.add(shoulder, priority: 10);
/// ```
/// {@category Scene graph}
class VirtualCamera extends CameraController {
  VirtualCamera({
    this.follow,
    this.lookAt,
    CameraBody? body,
    CameraAim? aim,
    this.priority = 0,
    super.smoothing = 0,
  }) : body = body ?? TransposerBody(),
       aim = aim ?? HardLookAtAim();

  /// The node the body positions against.
  Node? follow;

  /// The node the aim points at. Often the same node as [follow].
  Node? lookAt;

  /// Where the camera stands.
  CameraBody body;

  /// Where it points.
  CameraAim aim;

  /// What the director sorts by. Higher wins.
  ///
  /// Held here rather than only in the director's registration so a shot can
  /// take over by raising its own priority, which is the usual way a shot is
  /// handed the frame.
  double priority;

  final CameraSolveContext _context = CameraSolveContext();
  final Vector3 _position = Vector3.zero();

  /// Forgets where the camera was, so the next solve snaps into place.
  ///
  /// Called when a shot goes live after being idle: easing in from wherever
  /// the camera happened to be last would swing it across the level.
  void reset() => _context.isFirstFrame = true;

  @override
  void advance(double deltaSeconds) {
    final followNode = follow;
    final lookAtNode = lookAt;

    _context
      ..deltaSeconds = deltaSeconds
      ..hasFollow = followNode != null
      ..hasLookAt = lookAtNode != null;
    if (followNode != null) {
      final transform = followNode.globalTransform;
      _context.followPosition.setFrom(transform.getTranslation());
      _context.followRotation = Quaternion.fromRotation(
        transform.getRotation(),
      );
    }
    if (lookAtNode != null) {
      _context.lookAtPosition.setFrom(
        lookAtNode.globalTransform.getTranslation(),
      );
    }

    body.solve(_context, _position);
    final rotation = aim.solve(_context, _position);
    _context.previousPosition.setFrom(_position);
    _context.isFirstFrame = false;

    setPose(CameraPose(position: _position, rotation: rotation));
  }
}
