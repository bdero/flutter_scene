import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/raycast.dart';

/// A third-person camera that eases toward following [followTarget], orbiting
/// it at [yaw] / [pitch] / [distance] and looking at a point [lookHeight] above
/// its origin. Drag orbits, scroll dollies.
///
/// Position and look point both ease each frame, so the camera trails a moving
/// target smoothly instead of rigidly. Pitch is clamped so the view stays
/// upright. The horizontal [forward] / [right] basis is exposed so movement
/// input can stay camera-relative (pressing forward walks away from the
/// camera whichever way it faces).
///
/// Attach it to a node that also carries a [CameraComponent]. Drive it with a
/// [CameraControls] widget, or call [orbitBy] / [dollyBy] directly.
/// {@category Scene graph}
class FollowCameraController extends CameraController {
  /// Creates a follow controller trailing [followTarget].
  FollowCameraController({
    this.followTarget,
    this.distance = 9.0,
    this.lookHeight = 1.4,
    double yaw = 0.0,
    double pitch = 0.42,
    this.minPitch = -0.15,
    this.maxPitch = 1.3,
    this.minDistance = 0.5,
    this.maxDistance = double.infinity,
    this.rotateSpeed = math.pi,
    this.dollySpeed = 0.15,
    this.scrollSensitivity = 1 / 120,
    super.smoothing = 0.08,
  }) : _yaw = yaw,
       _pitch = pitch.clamp(minPitch, maxPitch);

  /// The node to follow. Its world-space position drives the camera; null
  /// parks the camera around the origin.
  Node? followTarget;

  /// How the camera finds out that something is between it and its target.
  ///
  /// Given the look point and where the camera wants to be, it returns the
  /// distance from the look point to the nearest blocker, or null when the
  /// view is clear. Set it and the camera pulls itself in rather than ending
  /// up inside a wall looking at its back faces; leave it null for no
  /// collision, which is right for an open scene and costs nothing.
  ///
  /// [occludeAgainst] wires the usual case (the scene's own geometry) in one
  /// call. Assign this directly to probe something else instead — physics
  /// shapes are far cheaper than triangles, and a height map cheaper still.
  double? Function(Vector3 lookAt, Vector3 desiredEye)? occlusionProbe;

  /// How far off an obstruction the camera stops, standing in for the near
  /// plane's half-width. Too small and the wall clips into view.
  double occlusionPadding = 0.2;

  /// Closest the camera may retract to before it is better to look through
  /// the wall than to sit inside the character's head.
  double minOcclusionDistance = 0.6;

  /// How fast the camera returns to its full distance once the obstruction
  /// clears, in world units per second. Retraction itself is instant: a
  /// camera that eased *into* clear space would spend that time inside the
  /// wall.
  double occlusionRecoverySpeed = 12.0;

  /// Probes the geometry under [root] (usually `scene.root`) for occluders.
  ///
  /// [layerMask] and [where] narrow what counts as a wall; the follow target
  /// and everything under it are always ignored, since the character stands
  /// between the look point and the camera by construction and would
  /// otherwise pin the camera to its own head.
  void occludeAgainst(
    Node root, {
    int layerMask = 0xFFFFFFFF,
    bool Function(Node node)? where,
  }) {
    occlusionProbe = (lookAt, desiredEye) {
      final toEye = desiredEye - lookAt;
      final reach = toEye.length;
      if (reach < 1e-6) return null;
      final target = followTarget;
      final hit = raycastNode(
        root,
        Ray.originDirection(lookAt, toEye / reach),
        maxDistance: reach,
        layerMask: layerMask,
        where: (node) {
          if (target != null && _isSelfOrUnder(node, target)) return false;
          return where?.call(node) ?? true;
        },
      );
      return hit?.distance;
    };
  }

  /// Stops probing for occluders.
  void clearOcclusion() {
    occlusionProbe = null;
    _occludedDistance = double.infinity;
  }

  double _occludedDistance = double.infinity;

  /// Distance from the look point to the camera.
  double distance;

  /// Height above the target's origin that the camera looks at.
  double lookHeight;

  /// Pitch clamp (radians).
  double minPitch;
  double maxPitch;

  /// Dolly distance clamp. [minDistance] must be > 0.
  double minDistance;
  double maxDistance;

  /// Radians of orbit per view-height of drag.
  double rotateSpeed;

  /// Proportional dolly rate (see [OrbitCameraController.dollySpeed]).
  double dollySpeed;

  /// Dolly steps per unit of scroll delta.
  double scrollSensitivity;

  double _yaw;
  double _pitch;
  final Vector3 _position = Vector3.zero();
  final Vector3 _target = Vector3.zero();
  bool _initialized = false;

  /// Orbit azimuth around the target (radians).
  double get yaw => _yaw;

  /// Orbit elevation (radians).
  double get pitch => _pitch;

  /// Unit horizontal direction the camera looks along (away from it).
  Vector3 get forward => Vector3(math.sin(_yaw), 0.0, math.cos(_yaw));

  /// Unit horizontal direction to the camera's right.
  Vector3 get right => Vector3(0.0, 1.0, 0.0).cross(forward)..normalize();

  /// Rotates the orbit by [deltaYaw] and [deltaPitch] (radians); pitch clamps.
  void orbitBy(double deltaYaw, double deltaPitch) {
    _yaw += deltaYaw;
    _pitch = (_pitch + deltaPitch).clamp(minPitch, maxPitch);
  }

  /// Dollies toward ([amount] > 0) or away from the target, proportional to
  /// the current distance and clamped to the distance limits.
  void dollyBy(double amount) {
    distance = (distance * math.exp(-amount * dollySpeed)).clamp(
      minDistance,
      maxDistance,
    );
  }

  @override
  void handleDragUpdate(Offset delta) {
    final k = rotateSpeed / viewportSize.height;
    orbitBy(-delta.dx * k, -delta.dy * k);
  }

  @override
  void handleScroll(double scrollDelta) =>
      dollyBy(-scrollDelta * scrollSensitivity);

  @override
  void advance(double deltaSeconds) {
    final base =
        followTarget?.globalTransform.getTranslation() ?? Vector3.zero();
    final lookAt = base + Vector3(0.0, lookHeight, 0.0);
    final desired = _desiredPosition(
      lookAt,
      _effectiveDistance(deltaSeconds, lookAt),
    );
    if (!_initialized) {
      _position.setFrom(desired);
      _target.setFrom(lookAt);
      _initialized = true;
    } else {
      final r = smoothingResponse(deltaSeconds);
      _position.addScaled(desired - _position, r);
      _target.addScaled(lookAt - _target, r);
    }
    setPose(CameraPose.lookAt(_position, _target));
  }

  /// The distance to actually use this frame: the requested [distance], or
  /// less when something is in the way.
  double _effectiveDistance(double deltaSeconds, Vector3 lookAt) {
    final probe = occlusionProbe;
    if (probe == null) return distance;

    final hit = probe(lookAt, _desiredPosition(lookAt, distance));
    final blocked = hit == null
        ? double.infinity
        : math.max(minOcclusionDistance, hit - occlusionPadding);

    if (blocked < _occludedDistance) {
      // Snap in. Easing here would leave the camera inside the wall for the
      // duration of the ease, which is the one failure this exists to avoid.
      _occludedDistance = blocked;
    } else {
      _occludedDistance = math.min(
        blocked,
        _occludedDistance + occlusionRecoverySpeed * deltaSeconds,
      );
    }
    return math.min(distance, _occludedDistance);
  }

  static bool _isSelfOrUnder(Node node, Node root) {
    for (Node? walk = node; walk != null; walk = walk.parent) {
      if (identical(walk, root)) return true;
    }
    return false;
  }

  Vector3 _desiredPosition(Vector3 lookAt, double atDistance) {
    final horizontal = math.cos(_pitch) * atDistance;
    return lookAt +
        Vector3(-math.sin(_yaw), 0.0, -math.cos(_yaw)) * horizontal +
        Vector3(0.0, math.sin(_pitch) * atDistance, 0.0);
  }
}
