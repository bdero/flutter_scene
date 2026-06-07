import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart';

import 'character_input.dart';
import 'third_person_camera.dart';

/// A third-person playable character driven by Rapier's kinematic
/// character controller.
///
/// Attach to a node that also carries (in this order) a kinematic
/// [RapierRigidBody], a capsule [RapierCollider], and a
/// [RapierKinematicCharacterController]. The character node is positioned
/// entirely by the kinematic controller; this component owns the higher
/// level behaviour:
///
///  * reads camera-relative intent from [input] and accelerates a
///    horizontal velocity toward it (with friction when released),
///  * applies gravity and an edge-triggered jump, using the kinematic
///    controller's grounded result to know when it can jump and land,
///  * feeds the resulting motion to the controller each fixed step (which
///    slides along walls, climbs slopes, autosteps, and snaps to ground),
///  * turns a loaded model to face its motion, and
///  * blends the model's idle / walk / run / jump animations.
///
/// The model is loaded as a child of a "pivot" node so its own import
/// transform is never overwritten; the pivot carries the foot offset,
/// scale, and facing rotation.
///
/// Phases of a jump, used to weight the one-shot jump animations.
enum _JumpState {
  /// On the ground (or falling after walking off a ledge); locomotion only.
  none,

  /// Rising after a jump press; the JumpStart clip plays and holds.
  jumping,

  /// Past the apex and descending; the held JumpStart pose continues.
  falling,

  /// Just touched down; the JumpLand clip plays as a brief overlay.
  landing,
}

class CharacterController extends Component {
  CharacterController({
    required this.input,
    required this.camera,
    this.modelSource = 'assets_src/dash.glb',
    this.maxSpeed = 7.0,
    this.acceleration = 40.0,
    this.deceleration = 30.0,
    this.jumpSpeed = 8.5,
    this.gravity = 22.0,
    this.footOffset = 0.9,
    this.modelHeightOffset = 0.0,
    this.modelScale = 1.0,
    this.modelYawOffset = 0.0,
    this.turnStiffness = 16.0,
    this.fallAnimationMinHeight = 1.0,
    this.shoveStrength = 0.08,
  });

  /// Where movement intent comes from.
  final CharacterInput input;

  /// The follow camera, used as the basis for camera-relative movement.
  final ThirdPersonCamera camera;

  final String modelSource;

  /// Top horizontal speed, m/s.
  final double maxSpeed;

  /// How quickly horizontal velocity ramps toward the target, m/s^2.
  final double acceleration;

  /// How quickly horizontal velocity decays when there is no input, m/s^2.
  final double deceleration;

  /// Take-off speed of a jump, m/s.
  final double jumpSpeed;

  /// Downward acceleration, m/s^2.
  final double gravity;

  /// Distance from the capsule centre down to the model's feet, world
  /// units (capsule half-height + radius). Also where the camera's follow
  /// target sits.
  final double footOffset;

  /// Extra vertical nudge applied to the model only (not the capsule or
  /// the camera target). Negative lowers the model toward the ground, to
  /// account for the capsule's skin gap or a model whose origin sits above
  /// its feet.
  final double modelHeightOffset;

  /// Uniform scale applied to the model.
  final double modelScale;

  /// Constant added to the facing yaw to correct the model's rest
  /// orientation, radians.
  final double modelYawOffset;

  /// How quickly the model turns toward its movement direction.
  final double turnStiffness;

  /// Minimum drop below the feet, in world units, for walking off a ledge
  /// to start the falling animation. Small step-downs below this stay in
  /// the grounded locomotion and play no jump pose.
  final double fallAnimationMinHeight;

  /// Per-step impulse magnitude used to shove dynamic bodies Dash runs
  /// into, in the direction of travel. The kinematic controller's built-in
  /// push barely moves light, jointed bodies (banners, ropes) when
  /// grounded, so this gives them a direct nudge. A fixed impulse moves
  /// light bodies a lot and heavy ones little, so it leaves the box stack
  /// and bridge feeling the same. Zero disables it.
  final double shoveStrength;

  RapierKinematicCharacterController? _mover;
  RapierWorld? _world;
  Node? _pivot;
  final Map<String, AnimationClip> _clips = {};

  // World-space horizontal velocity (y is always 0) and vertical speed.
  final Vector3 _horizontalVelocity = Vector3.zero();
  double _verticalVelocity = 0.0;
  bool _grounded = false;
  bool _prevJump = false;

  // Capsule centre after the previous and current fixed steps, plus the
  // value interpolated between them for rendering. The kinematic body is
  // not interpolated by the engine, so the model and camera are rendered
  // at [_interpCenter] to stay smooth between physics steps.
  final Vector3 _prevCenter = Vector3.zero();
  final Vector3 _currCenter = Vector3.zero();
  final Vector3 _interpCenter = Vector3.zero();

  // Facing: target yaw from motion, and the eased display yaw.
  double _facingYaw = 0.0;
  double _displayYaw = 0.0;

  // Jump/landing animation state machine. Locomotion plays at full weight
  // except while landing, when it is briefly suppressed so the JumpLand
  // clip dominates and then fades the locomotion back in.
  _JumpState _jumpState = _JumpState.none;
  double _landingCooldown = 0.0;
  // Eased 0..1 weight of the airborne (JumpStart) pose, so leaving the
  // ground blends into the falling animation over a short window instead
  // of snapping to it.
  double _airborneBlend = 0.0;

  /// How long the landing overlay lasts, seconds.
  static const double _landingDuration = 0.4;

  /// Easing rate for [_airborneBlend]; ~1/rate seconds to transition.
  static const double _airborneBlendRate = 12.0;

  /// The character's current world position (capsule centre).
  Vector3 get position => node.globalTransform.getTranslation();

  /// The character's interpolated foot position, a smooth follow target
  /// for the camera (matches what is rendered).
  Vector3 get footPosition => _interpCenter.clone()..y -= footOffset;

  /// Snaps the character to [worldPosition] (capsule centre) and clears
  /// its velocity. Useful for spawning and respawning.
  void teleport(Vector3 worldPosition) {
    final transform = node.globalTransform.clone()
      ..setTranslation(worldPosition);
    node.globalTransform = transform;
    _horizontalVelocity.setZero();
    _verticalVelocity = 0.0;
    _jumpState = _JumpState.none;
    _landingCooldown = 0.0;
    _airborneBlend = 0.0;
    _prevCenter.setFrom(worldPosition);
    _currCenter.setFrom(worldPosition);
    _interpCenter.setFrom(worldPosition);
  }

  @override
  Future<void> onLoad() async {
    final model = await loadModel(modelSource);
    final pivot = Node()..add(model);
    node.add(pivot);
    _pivot = pivot;

    for (final name in const ['Idle', 'Walk', 'Run', 'JumpStart', 'JumpLand']) {
      final animation = model.findAnimationByName(name);
      if (animation == null) continue;
      // Locomotion clips loop and run continuously (mixed by weight). The
      // jump one-shots (JumpStart, JumpLand) do not loop: each is re-played
      // from frame zero with seek(0) when it fires and otherwise holds its
      // final pose (a finished non-loop clip stops advancing). There is no
      // separate in-air loop clip; JumpStart holds the airborne pose.
      final loop = name != 'JumpStart' && name != 'JumpLand';
      final clip = model.createAnimationClip(animation)
        ..loop = loop
        ..playing = loop
        ..weight = 0.0;
      _clips[name] = clip;
    }
    _applyPivot();
  }

  @override
  void onMount() {
    _mover = node.getComponent<RapierKinematicCharacterController>();
    _world = findAncestorRapierWorld(node);
    final centre = node.globalTransform.getTranslation();
    _prevCenter.setFrom(centre);
    _currCenter.setFrom(centre);
    _interpCenter.setFrom(centre);
  }

  @override
  void onUnmount() {
    _mover = null;
    _world = null;
  }

  @override
  void fixedUpdate(double fixedDt) {
    final dt = fixedDt;
    final mover = _mover;
    if (mover == null) return;

    // Camera-relative desired direction, flattened to the ground plane.
    final wish = (camera.forward * input.move.y) + (camera.right * input.move.x)
      ..y = 0.0;
    var wishMagnitude = wish.length;
    if (wishMagnitude > 1.0) {
      wish.scale(1.0 / wishMagnitude);
      wishMagnitude = 1.0;
    }
    final target = wishMagnitude > 1e-3
        ? (wish.normalized()..scale(wishMagnitude * maxSpeed))
        : Vector3.zero();
    _moveToward(
      _horizontalVelocity,
      target,
      (wishMagnitude > 1e-3 ? acceleration : deceleration) * dt,
    );

    // Jump on the press edge, only while grounded.
    final jumpEdge = input.jump && !_prevJump;
    _prevJump = input.jump;
    if (_grounded) {
      if (_verticalVelocity < 0.0) _verticalVelocity = 0.0;
      if (jumpEdge) {
        _verticalVelocity = jumpSpeed;
        // Replay the (non-looping) JumpStart clip from frame zero; it would
        // otherwise stay frozen on its last frame after the first jump.
        _jumpState = _JumpState.jumping;
        _clips['JumpStart']?.seek(0.0);
      }
    }
    _verticalVelocity -= gravity * dt;

    final desired = Vector3(
      _horizontalVelocity.x,
      _verticalVelocity,
      _horizontalVelocity.z,
    )..scale(dt);
    final result = mover.move(desired);

    _grounded = result.grounded;
    if (_grounded && _verticalVelocity < 0.0) _verticalVelocity = 0.0;

    // Advance the jump/landing state machine. JumpStart holds through the
    // rise and the fall; touching down switches to the JumpLand one-shot,
    // which counts down [_landingCooldown] and then returns to locomotion.
    switch (_jumpState) {
      case _JumpState.jumping:
        if (_verticalVelocity < 0.0) {
          _jumpState = _JumpState.falling;
        } else if (_grounded) {
          _enterLanding();
        }
        break;
      case _JumpState.falling:
        if (_grounded) _enterLanding();
        break;
      case _JumpState.landing:
        if (_landingCooldown > 0.0) {
          _landingCooldown = math.max(0.0, _landingCooldown - dt);
        } else {
          _jumpState = _JumpState.none;
        }
        break;
      case _JumpState.none:
        // Walked off a high ledge: play the airborne pose, the same as a
        // jump's descent. Small step-downs stay grounded and are ignored.
        if (!_grounded && _groundClearance() > fallAnimationMinHeight) {
          _jumpState = _JumpState.falling;
          _clips['JumpStart']?.seek(0.0);
        }
        break;
    }

    // Nudge dynamic bodies Dash is running into.
    _shoveNearbyBodies();

    // Face the direction of travel.
    final horizontalSpeed = _horizontalVelocity.length;
    if (horizontalSpeed > 0.4) {
      _facingYaw = math.atan2(_horizontalVelocity.x, _horizontalVelocity.z);
    }

    // Record this step's centre so [update] can render between steps.
    _prevCenter.setFrom(_currCenter);
    _currCenter.setFrom(node.globalTransform.getTranslation());
  }

  @override
  void update(double deltaSeconds) {
    final dt = deltaSeconds;
    if (_pivot == null) return;

    // Render between the previous and current fixed-step centres so the
    // (un-interpolated) kinematic body looks as smooth as dynamic bodies.
    final alpha = (_world?.interpolationAlpha ?? 1.0).clamp(0.0, 1.0);
    _interpCenter
      ..setFrom(_currCenter)
      ..sub(_prevCenter)
      ..scale(alpha)
      ..add(_prevCenter);

    // Ease the displayed facing toward the target along the shortest arc.
    final blend = 1.0 - math.exp(-turnStiffness * dt);
    _displayYaw += _shortestAngle(_displayYaw, _facingYaw) * blend;
    _applyPivot();

    _blendAnimations(dt);
  }

  void _enterLanding() {
    _jumpState = _JumpState.landing;
    _landingCooldown = _landingDuration;
    // Replay the (non-looping) JumpLand clip from frame zero.
    _clips['JumpLand']?.seek(0.0);
  }

  // Distance from Dash's feet straight down to the nearest ground, or
  // infinity over a void. Kinematic bodies (Dash's own capsule, moving
  // platforms) are skipped so the ray does not hit the character itself.
  double _groundClearance() {
    final world = _world;
    if (world == null) return 0.0;
    final origin = node.globalTransform.getTranslation();
    final hit = world.raycast(
      Ray.originDirection(origin, Vector3(0.0, -1.0, 0.0)),
      maxDistance: 60.0,
      includeKinematic: false,
    );
    if (hit == null) return double.infinity;
    return hit.distance - footOffset;
  }

  // Shoves dynamic bodies just ahead of Dash in his direction of travel.
  // A direct nudge so light, jointed props (banners, ropes) react to him
  // on the ground, where the controller's own push is too weak.
  void _shoveNearbyBodies() {
    final world = _world;
    if (world == null || shoveStrength <= 0.0) return;
    final speed = _horizontalVelocity.length;
    if (speed < 0.6) return;
    final center = node.globalTransform.getTranslation();
    final dir = _horizontalVelocity.normalized();
    final speedFraction = (speed / maxSpeed).clamp(0.0, 1.0);
    final hits = world.overlapSphere(
      center,
      0.9,
      includeFixed: false,
      includeKinematic: false,
      includeDynamic: true,
      includeTriggers: false,
    );
    for (final hit in hits) {
      if (hit.node == node) continue;
      final body = hit.node.getComponent<RapierRigidBody>();
      if (body == null) continue;
      // Only push bodies ahead of him, so passing alongside one does not
      // fling it.
      final toBody = hit.node.globalTransform.getTranslation()
        ..sub(center)
        ..y = 0.0;
      if (toBody.dot(dir) <= 0.0) continue;
      body.applyImpulse(dir * (shoveStrength * speedFraction));
    }
  }

  void _applyPivot() {
    // The character node sits at the current fixed-step centre; offset the
    // model so it renders at the interpolated centre, with its feet at the
    // capsule bottom.
    final offset = (_interpCenter - _currCenter)
      ..y -= footOffset - modelHeightOffset;
    _pivot!.localTransform = Matrix4.compose(
      offset,
      Quaternion.axisAngle(
        Vector3(0.0, 1.0, 0.0),
        _displayYaw + modelYawOffset,
      ),
      Vector3.all(modelScale),
    );
  }

  void _blendAnimations(double dt) {
    final speedFraction = (_horizontalVelocity.length / maxSpeed).clamp(
      0.0,
      1.0,
    );

    final airborne =
        _jumpState == _JumpState.jumping || _jumpState == _JumpState.falling;
    final landing = _jumpState == _JumpState.landing;

    // Ease the airborne pose in/out so entering the air (a jump or walking
    // off a ledge) transitions into the falling animation instead of
    // snapping straight to it.
    _airborneBlend +=
        ((airborne ? 1.0 : 0.0) - _airborneBlend) *
        (1.0 - math.exp(-_airborneBlendRate * dt));

    // Grounded locomotion plays at full weight except during the landing
    // window, when it is suppressed (so JumpLand dominates) and then ramps
    // back in over the tail. JumpLand starts at full weight and fades out
    // across [_landingDuration]. (Weights are normalized by the player when
    // they sum past 1, so JumpStart holding at 1 already dims locomotion in
    // the air; the explicit suppression below is only needed for landing.)
    final groundedWeight = math.max(
      _jumpState == _JumpState.none ? 1.0 : 0.0,
      math.min(1.0, 1.0 - _landingCooldown * 6.0),
    );
    final landingWeight =
        (landing ? 1.0 : 0.0) * math.min(1.0, _landingCooldown * 4.0);

    // Grounded locomotion: idle -> walk -> run across the speed range.
    final double idle, walk, run;
    if (speedFraction < 0.5) {
      idle = 1.0 - speedFraction * 2.0;
      walk = speedFraction * 2.0;
      run = 0.0;
    } else {
      idle = 0.0;
      walk = (1.0 - speedFraction) * 2.0;
      run = speedFraction * 2.0 - 1.0;
    }
    _setWeight('Idle', groundedWeight * idle);
    _setWeight('Walk', groundedWeight * walk);
    _setWeight('Run', groundedWeight * run);

    // JumpStart holds the takeoff/falling pose for the whole airborne phase,
    // eased in/out via [_airborneBlend]; JumpLand is a brief, heavily
    // weighted overlay on touchdown. Drive each clip's `playing` so the
    // one-shots advance while active (and while the airborne pose fades).
    _setClip('JumpStart', _airborneBlend, airborne || _airborneBlend > 0.01);
    _setClip('JumpLand', landingWeight, landing);
  }

  void _setWeight(String name, double weight) {
    final clip = _clips[name];
    if (clip != null) clip.weight = weight;
  }

  void _setClip(String name, double weight, bool playing) {
    final clip = _clips[name];
    if (clip == null) return;
    clip
      ..weight = weight
      ..playing = playing;
  }

  // Moves [value] toward [target] by at most [maxDelta], in place.
  static void _moveToward(Vector3 value, Vector3 target, double maxDelta) {
    final dx = target.x - value.x;
    final dy = target.y - value.y;
    final dz = target.z - value.z;
    final distance = math.sqrt(dx * dx + dy * dy + dz * dz);
    if (distance <= maxDelta || distance == 0.0) {
      value.setFrom(target);
      return;
    }
    final scale = maxDelta / distance;
    value.setValues(
      value.x + dx * scale,
      value.y + dy * scale,
      value.z + dz * scale,
    );
  }

  // Shortest signed angle from [from] to [to], in (-pi, pi].
  static double _shortestAngle(double from, double to) {
    var delta = (to - from) % (2.0 * math.pi);
    if (delta > math.pi) delta -= 2.0 * math.pi;
    if (delta < -math.pi) delta += 2.0 * math.pi;
    return delta;
  }
}
