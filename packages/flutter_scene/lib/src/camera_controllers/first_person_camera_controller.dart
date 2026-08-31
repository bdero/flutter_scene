import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/node.dart';

/// The walk cycle a [FirstPersonCameraController] overlays on the eye
/// position, so movement reads as footfalls rather than as a floating camera.
///
/// The bob traces a figure-eight: the vertical component runs at twice the
/// horizontal one, which is what makes it read as alternating feet instead of
/// a side-to-side sway. It advances only while the controller is told the
/// character is moving ([FirstPersonCameraController.setMotion]), and eases
/// back to nothing when they stop.
/// {@category Scene graph}
class HeadBob {
  /// Creates a head bob. Defaults are a subtle walk; scale [amplitude] up for
  /// a heavier character and [frequency] up for a faster gait.
  HeadBob({
    this.amplitude = 0.045,
    this.frequency = 8.0,
    this.lateralRatio = 0.6,
    this.rollAmount = 0.012,
  });

  /// Vertical displacement at full speed, in world units.
  double amplitude;

  /// Steps per second at full speed (a full bob cycle is two steps).
  double frequency;

  /// Sideways displacement as a fraction of [amplitude].
  double lateralRatio;

  /// Roll, in radians, at the extremes of the sideways swing. Zero disables
  /// the roll and leaves a purely translational bob.
  double rollAmount;

  double _phase = 0.0;
  double _weight = 0.0;

  /// The current cycle phase in radians, for a caller syncing footstep audio
  /// to the bob.
  double get phase => _phase;

  /// How much of the bob is currently applied, `0` to `1`.
  double get weight => _weight;

  /// Advances the cycle. [speedFraction] is how fast the character is moving
  /// as a fraction of their top speed.
  void advance(double deltaSeconds, double speedFraction) {
    final target = speedFraction.clamp(0.0, 1.0);
    // Ease the weight rather than the phase, so stopping settles the camera
    // instead of freezing it mid-step.
    _weight += (target - _weight) * math.min(1.0, deltaSeconds * 8.0);
    if (_weight < 1e-4) {
      _weight = 0.0;
      _phase = 0.0;
      return;
    }
    _phase =
        (_phase + deltaSeconds * frequency * math.pi * target) % (math.pi * 2);
  }

  /// The current offset in camera-local space (`+X` right, `+Y` up).
  Vector3 get offset => Vector3(
    math.sin(_phase) * amplitude * lateralRatio * _weight,
    // Twice the horizontal rate: one dip per foot, two per full cycle.
    -math.cos(_phase * 2.0).abs() * amplitude * _weight,
    0.0,
  );

  /// The current roll, in radians.
  double get roll => math.sin(_phase) * rollAmount * _weight;

  /// Clears the cycle immediately (on a teleport, or a respawn).
  void reset() {
    _phase = 0.0;
    _weight = 0.0;
  }
}

/// A first-person camera: the eye sits at a character's head, the mouse looks
/// around, and the view never rolls or flips over the poles.
///
/// This is the camera for an FPS, a walking simulator, or anything seen
/// through a character's eyes. It is deliberately not [FlyCameraController]
/// with `moveVertical` off: a fly camera *is* the player and moves itself,
/// while this camera *rides* a character that something else moves (a
/// [ThirdPersonControllerComponent], a physics character controller, an
/// animation). It contributes the parts a fly camera has no concept of:
///
///  * A [followTarget] whose position it tracks, plus an [eyeOffset] for the
///    head. Set [positionSmoothing] above zero for a camera that lags the
///    body slightly; leave it at zero, the default, for a rigid mount, which
///    is what most shooters want.
///  * [headBob], the walk cycle. Feed it [setMotion] each frame.
///  * [addRecoil], an additive kick to the aim that decays back. Because it
///    is additive, the player can fight it: their own look input applies on
///    top rather than being overwritten.
///  * [lens], so aiming down sights is a field-of-view change on the pose
///    rather than something the caller has to reach into the camera
///    component for.
///
/// The character's facing is usually driven *from* the camera rather than the
/// other way round: read [yaw] (or [planarForward]) and turn the character to
/// match.
///
/// ```dart
/// final camera = FirstPersonCameraController(followTarget: player);
/// cameraNode.addComponent(camera);
///
/// // Each frame, from an InputManager:
/// camera.look(Offset(lookX, lookY));
/// character.setMoveInput(move, cameraHeadingYaw: camera.yaw);
/// camera.setMotion(character.speed / character.runSpeed);
/// ```
/// {@category Scene graph}
class FirstPersonCameraController extends CameraController {
  /// Creates a first-person camera. With no [followTarget] the eye stands
  /// still at [position] and only looks around, which is enough for a fixed
  /// vantage point or a menu backdrop.
  FirstPersonCameraController({
    this.followTarget,
    Vector3? eyeOffset,
    Vector3? position,
    double yaw = 0.0,
    double pitch = 0.0,
    this.lookSensitivity = 0.005,
    this.minPitch = -_defaultPitchLimit,
    this.maxPitch = _defaultPitchLimit,
    this.headBob,
    this.lens,
    this.positionSmoothing = 0.0,
    this.recoilRecovery = 0.35,
    super.smoothing = 0.0,
  }) : eyeOffset = (eyeOffset ?? Vector3(0.0, 1.7, 0.0)).clone(),
       _position = (position ?? Vector3.zero()).clone(),
       _yaw = yaw,
       _yawGoal = yaw,
       _pitch = pitch.clamp(-_defaultPitchLimit, _defaultPitchLimit),
       _pitchGoal = pitch.clamp(-_defaultPitchLimit, _defaultPitchLimit);

  static const double _defaultPitchLimit = 1.55; // ~89 degrees

  /// The node whose position the eye rides, usually the character. Null keeps
  /// the eye at [position].
  Node? followTarget;

  /// The head offset from [followTarget]'s origin. The default puts the eye
  /// at 1.7 units, roughly eye height for a human-scaled character.
  Vector3 eyeOffset;

  /// Radians of look per logical pixel of drag.
  double lookSensitivity;

  /// Pitch clamp, in radians, kept short of vertical so the view cannot flip.
  double minPitch;
  double maxPitch;

  /// The walk cycle overlaid on the eye, or null for a rigid camera.
  HeadBob? headBob;

  /// The lens this camera asks for, or null to leave the camera's own lens
  /// alone. Assigning a new [PerspectiveProjection] with a narrower field of
  /// view is how aiming down sights is expressed.
  CameraProjection? lens;

  /// Settle time in seconds for the eye following the body. Zero, the
  /// default, is a rigid mount.
  double positionSmoothing;

  /// Settle time in seconds for recoil decaying back to the aim.
  double recoilRecovery;

  Vector3 _position;
  double _yaw;
  double _yawGoal;
  double _pitch;
  double _pitchGoal;
  double _recoilPitch = 0.0;
  double _recoilYaw = 0.0;
  double _speedFraction = 0.0;
  bool _initialized = false;

  /// The heading in radians, ignoring recoil: the value to turn a character
  /// to so they face where the player is looking.
  double get yaw => _yaw;

  /// The elevation in radians, ignoring recoil: positive looks up, matching
  /// [FlyCameraController].
  double get pitch => _pitch;

  /// The eye position, head bob included.
  Vector3 get position => _position.clone();
  set position(Vector3 value) {
    _position = value.clone();
    _initialized = true;
  }

  double get _aimYaw => _yaw + _recoilYaw;
  double get _aimPitch =>
      (_pitch + _recoilPitch).clamp(-_defaultPitchLimit, _defaultPitchLimit);

  /// The unit look direction, recoil included.
  Vector3 get forward {
    final cp = math.cos(_aimPitch);
    return Vector3(
      math.sin(_aimYaw) * cp,
      math.sin(_aimPitch),
      math.cos(_aimYaw) * cp,
    );
  }

  /// The unit horizontal look direction, for movement that should not tilt
  /// into the floor when the player looks down.
  Vector3 get planarForward => Vector3(math.sin(_yaw), 0.0, math.cos(_yaw));

  /// The unit horizontal direction to the camera's right.
  Vector3 get planarRight => Vector3(math.cos(_yaw), 0.0, -math.sin(_yaw));

  /// Turns the view by a drag delta in logical pixels (positive `dy` looks
  /// down, matching a mouse).
  void look(Offset delta) =>
      lookBy(delta.dx * lookSensitivity, -delta.dy * lookSensitivity);

  /// Turns the view by explicit angles in radians (positive [deltaPitch]
  /// looks up). Pitch is clamped to [minPitch]..[maxPitch].
  void lookBy(double deltaYaw, double deltaPitch) {
    _yawGoal += deltaYaw;
    _pitchGoal = (_pitchGoal + deltaPitch).clamp(minPitch, maxPitch);
  }

  /// Points the view at [target] in world space.
  void lookAtPoint(Vector3 target) {
    final delta = target - _position;
    if (delta.length2 < 1e-9) return;
    _yawGoal = math.atan2(delta.x, delta.z);
    final horizontal = math.sqrt(delta.x * delta.x + delta.z * delta.z);
    _pitchGoal = math.atan2(delta.y, horizontal).clamp(minPitch, maxPitch);
  }

  /// Reports how fast the character is moving, as a fraction of their top
  /// speed, to drive [headBob]. Ignored when there is no head bob.
  void setMotion(double speedFraction) => _speedFraction = speedFraction;

  /// Kicks the aim by [pitch] radians up and [yaw] radians sideways, decaying
  /// back over [recoilRecovery] seconds.
  ///
  /// The kick is additive rather than a change to the aim, so it recovers to
  /// wherever the player has since looked instead of yanking them back.
  void addRecoil(double pitch, {double yaw = 0.0}) {
    _recoilPitch += pitch;
    _recoilYaw += yaw;
  }

  /// Drops any recoil immediately.
  void clearRecoil() {
    _recoilPitch = 0.0;
    _recoilYaw = 0.0;
  }

  /// Places the eye at the follow target at once, skipping the position
  /// easing. Call after a teleport so the camera does not sweep across the
  /// level.
  void snapToTarget() {
    _initialized = false;
    headBob?.reset();
  }

  @override
  void handleDragUpdate(Offset delta) => look(delta);

  @override
  void advance(double deltaSeconds) {
    final lookResponse = smoothingResponse(deltaSeconds);
    _yaw += (_yawGoal - _yaw) * lookResponse;
    _pitch += (_pitchGoal - _pitch) * lookResponse;

    final recoilResponse = settleResponse(recoilRecovery, deltaSeconds);
    _recoilPitch -= _recoilPitch * recoilResponse;
    _recoilYaw -= _recoilYaw * recoilResponse;

    final target = followTarget;
    if (target != null) {
      final desired = target.globalTransform.getTranslation() + eyeOffset;
      if (!_initialized || positionSmoothing <= 0.0) {
        _position.setFrom(desired);
        _initialized = true;
      } else {
        _position.addScaled(
          desired - _position,
          settleResponse(positionSmoothing, deltaSeconds),
        );
      }
    }

    final bob = headBob;
    var pose = CameraPose.lookAt(
      _position,
      _position + forward,
      projection: lens,
    );
    if (bob != null) {
      bob.advance(deltaSeconds, _speedFraction);
      if (bob.weight > 0.0) {
        pose = pose
            .translatedLocal(bob.offset)
            .rotatedLocal(
              Quaternion.axisAngle(Vector3(0.0, 0.0, 1.0), bob.roll),
            );
      }
    }
    setPose(pose);
  }
}
