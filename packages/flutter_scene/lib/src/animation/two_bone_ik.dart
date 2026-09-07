/// Analytic two-bone inverse kinematics: the arm-and-leg solver.
///
/// Given where a limb currently is and where its tip should end up, this
/// works out the two rotations that put it there, in closed form. No
/// iteration, no convergence threshold, no per-frame cost that depends on how
/// far the target moved.
///
/// The solver is pure — positions in, rotations out — so the geometry is
/// testable without a scene graph, and the component that applies it stays
/// thin.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

/// World-space rotations to apply to a limb's root and mid joints.
/// {@category Animation}
typedef TwoBoneSolution = ({Quaternion root, Quaternion mid});

/// Solves the limb `root -> mid -> tip` so the tip reaches [target].
///
/// The returned rotations are world-space deltas: apply [TwoBoneSolution.root]
/// to the root joint and [TwoBoneSolution.mid] to the mid joint, in that
/// order.
///
/// [pole] steers which way the limb bends — a knee forward, an elbow back.
/// Without one the limb keeps the bend plane it already had, which is usually
/// right for a pose coming from an animation clip and wrong for a limb that
/// happens to be perfectly straight.
///
/// A target further away than the limb can reach is pulled in to just short
/// of full extension rather than being reached for: a leg locked dead
/// straight looks broken, and the tiny bend keeps the knee readable.
/// {@category Animation}
TwoBoneSolution solveTwoBoneIk({
  required Vector3 rootPosition,
  required Vector3 midPosition,
  required Vector3 tipPosition,
  required Vector3 target,
  Vector3? pole,
  double softness = 0.01,
}) {
  final upperLength = (midPosition - rootPosition).length;
  final lowerLength = (tipPosition - midPosition).length;
  if (upperLength < 1e-6 || lowerLength < 1e-6) {
    return (root: Quaternion.identity(), mid: Quaternion.identity());
  }

  final toTarget = target - rootPosition;
  if (toTarget.length < 1e-6) {
    // The target sits on the joint itself; there is no direction to aim.
    return (root: Quaternion.identity(), mid: Quaternion.identity());
  }

  // Both ends of the range are excluded: at full extension the bend plane is
  // undefined, and inside the fold the triangle inverts.
  final maxReach =
      (upperLength + lowerLength) * (1.0 - softness.clamp(0.0, 0.5));
  final minReach = (upperLength - lowerLength).abs() + 1e-4;
  final distance = toTarget.length.clamp(minReach, maxReach);
  final aim = toTarget.normalized();

  // The bend plane: a pole picks it, otherwise the pose already has one, and
  // a perfectly straight limb has none to offer.
  Vector3 perpendicular(Vector3 hint) {
    final projected = hint - aim * hint.dot(aim);
    return projected.length2 < 1e-12 ? Vector3.zero() : projected.normalized();
  }

  var bendDirection = pole == null
      ? perpendicular(midPosition - rootPosition)
      : perpendicular(pole - rootPosition);
  if (bendDirection.length2 < 1e-12) {
    bendDirection = perpendicular(Vector3(0.0, 1.0, 0.0));
  }
  if (bendDirection.length2 < 1e-12) {
    bendDirection = perpendicular(Vector3(1.0, 0.0, 0.0));
  }

  // Law of cosines for the angle between the upper bone and the aim.
  final cosRoot =
      ((upperLength * upperLength +
                  distance * distance -
                  lowerLength * lowerLength) /
              (2 * upperLength * distance))
          .clamp(-1.0, 1.0);
  final rootAngle = math.acos(cosRoot);

  final solvedMid =
      rootPosition +
      (aim * math.cos(rootAngle) + bendDirection * math.sin(rootAngle)) *
          upperLength;
  final solvedTip = rootPosition + aim * distance;

  final root = _rotationBetween(
    midPosition - rootPosition,
    solvedMid - rootPosition,
  );
  final lowerNow = _rotate(root, tipPosition - midPosition);
  final mid = _rotationBetween(lowerNow, solvedTip - solvedMid);
  return (root: root, mid: mid);
}

/// The shortest rotation taking [from] onto [to].
Quaternion _rotationBetween(Vector3 from, Vector3 to) {
  if (from.length2 < 1e-12 || to.length2 < 1e-12) {
    return Quaternion.identity();
  }
  final a = from.normalized();
  final b = to.normalized();
  final dot = a.dot(b).clamp(-1.0, 1.0);
  if (dot > 1.0 - 1e-12) return Quaternion.identity();
  if (dot < -1.0 + 1e-12) {
    // Opposed: any perpendicular axis is a valid half turn.
    var axis = a.cross(Vector3(0.0, 1.0, 0.0));
    if (axis.length2 < 1e-12) axis = a.cross(Vector3(1.0, 0.0, 0.0));
    return Quaternion.axisAngle(axis.normalized(), math.pi);
  }
  return Quaternion.axisAngle(a.cross(b).normalized(), math.acos(dot));
}

/// Where the tip lands for a solved limb, for tests and for a caller checking
/// whether the target was actually reachable.
///
/// Rotates the way a node does, through the matrix its rotation composes
/// into. That is not the same as [Quaternion.rotated], which turns the
/// opposite way for the same quaternion — a difference nothing in the API
/// announces, and one that silently inverts an IK solve if the wrong one is
/// used to check it.
/// {@category Animation}
Vector3 twoBoneTipAfter({
  required Vector3 rootPosition,
  required Vector3 midPosition,
  required Vector3 tipPosition,
  required TwoBoneSolution solution,
}) {
  final mid = twoBoneMidAfter(
    rootPosition: rootPosition,
    midPosition: midPosition,
    solution: solution,
  );
  final tipFromMid = _rotate(
    solution.mid,
    _rotate(solution.root, tipPosition - midPosition),
  );
  return mid + tipFromMid;
}

/// Where the mid joint — the knee or elbow — lands for a solved limb.
///
/// Useful for drawing a debug marker, for a caller that wants to know where
/// the joint ended up, and for checking a solve without re-deriving which way
/// a quaternion turns.
/// {@category Animation}
Vector3 twoBoneMidAfter({
  required Vector3 rootPosition,
  required Vector3 midPosition,
  required TwoBoneSolution solution,
}) => rootPosition + _rotate(solution.root, midPosition - rootPosition);

/// Rotates [v] by [q] the way a node's transform does.
Vector3 _rotate(Quaternion q, Vector3 v) => Matrix4.compose(
  Vector3.zero(),
  q,
  Vector3(1.0, 1.0, 1.0),
).transform3(v.clone());
