import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/src/rapier_collider.dart';
import 'package:flutter_scene_rapier/src/rapier_world.dart';
import 'package:vector_math/vector_math.dart';

/// The outcome of a [RapierKinematicCharacterController.move] call.
class CharacterMovement {
  /// The world-space translation that was applied to the character after
  /// sliding, slope handling, autostep, and snap-to-ground.
  final Vector3 translation;

  /// Whether the character is touching the ground after the move.
  final bool grounded;

  /// Whether the character is sliding down a slope steeper than the
  /// controller's `minSlopeSlideAngle`.
  final bool slidingDownSlope;

  CharacterMovement({
    required this.translation,
    required this.grounded,
    required this.slidingDownSlope,
  });
}

/// A kinematic character controller backed by Rapier's move-and-slide
/// solver.
///
/// Attach it to a node that also carries a kinematic [RapierRigidBody] and
/// a [RapierCollider] (the character's shape, typically a capsule), then
/// call [move] each fixed step with the motion you want. [move] does not
/// apply forces: it shape-casts the desired translation against the world,
/// resolves it (sliding along walls, climbing slopes up to
/// [maxSlopeClimbAngle], stepping over obstacles when [autostep] is set,
/// and snapping to the ground within [snapToGround]), writes the corrected
/// motion onto the owning node's transform, and returns what happened. The
/// kinematic body carries the new pose into the simulation on the next
/// step, so call [move] once per fixed step.
///
/// This is a Rapier-specific component with no portable abstract
/// equivalent.
class RapierKinematicCharacterController extends Component {
  RapierKinematicCharacterController({
    Vector3? up,
    this.offset = 0.01,
    this.slide = true,
    this.maxSlopeClimbAngle = math.pi / 4,
    this.minSlopeSlideAngle = math.pi / 4,
    this.snapToGround = 0.1,
    this.autostep = false,
    this.autostepMaxHeight = 0.3,
    this.autostepMinWidth = 0.1,
    this.autostepIncludeDynamicBodies = true,
  }) : up = up ?? Vector3(0, 1, 0);

  /// The "up" direction used to find the floor and measure slope angles.
  Vector3 up;

  /// A small skin gap kept between the character and its surroundings, in
  /// world units. Must be greater than zero.
  double offset;

  /// Whether the character slides along surfaces it hits instead of
  /// stopping dead.
  bool slide;

  /// The steepest floor angle (radians away from [up]) the character can
  /// climb.
  double maxSlopeClimbAngle;

  /// The shallowest floor angle (radians away from [up]) at which the
  /// character starts sliding back down.
  double minSlopeSlideAngle;

  /// Maximum distance to snap the character down onto the ground, or null
  /// to disable snapping.
  double? snapToGround;

  /// Whether the character automatically steps over small obstacles.
  bool autostep;

  /// Maximum obstacle height the character steps over when [autostep] is
  /// set, in world units.
  double autostepMaxHeight;

  /// Minimum free width required on top of a step, in world units.
  double autostepMinWidth;

  /// Whether autostep also steps over dynamic bodies.
  bool autostepIncludeDynamicBodies;

  RapierWorld? _world;
  RapierCollider? _collider;

  @override
  void onMount() {
    _world = findAncestorRapierWorld(node);
    _collider = node.getComponent<RapierCollider>();
  }

  @override
  void onUnmount() {
    _world = null;
    _collider = null;
  }

  /// Resolves [desiredTranslation] against the world and applies the
  /// corrected motion to the owning node, returning the result. Call once
  /// per fixed step. [deltaSeconds] defaults to the world's fixed
  /// timestep.
  ///
  /// Throws if the controller is not mounted under a [RapierWorld], or if
  /// its node has no mounted [RapierCollider] to use as the character
  /// shape. The node should also carry a kinematic [RapierRigidBody] so
  /// the applied motion reaches the simulation.
  CharacterMovement move(Vector3 desiredTranslation, {double? deltaSeconds}) {
    final world = _world;
    if (world == null) {
      throw StateError(
        'RapierKinematicCharacterController must be mounted under a node '
        'carrying a RapierWorld.',
      );
    }
    final handle = _collider?.nativeHandle;
    if (handle == null) {
      throw StateError(
        'RapierKinematicCharacterController requires a mounted '
        'RapierCollider on its node to use as the character shape.',
      );
    }
    final result = world.moveCharacter(
      handle,
      desiredTranslation: desiredTranslation,
      deltaSeconds: deltaSeconds ?? world.fixedTimestep,
      up: up,
      offset: offset,
      slide: slide,
      maxSlopeClimbAngle: maxSlopeClimbAngle,
      minSlopeSlideAngle: minSlopeSlideAngle,
      snapToGround: snapToGround,
      autostep: autostep,
      autostepMaxHeight: autostepMaxHeight,
      autostepMinWidth: autostepMinWidth,
      autostepIncludeDynamicBodies: autostepIncludeDynamicBodies,
    );
    // Apply the corrected world-space translation to the node. Writing
    // the global transform keeps it correct for nested nodes; the
    // kinematic body picks the new pose up on the next step.
    final t = result.translation;
    if (t.x != 0 || t.y != 0 || t.z != 0) {
      final g = node.globalTransform.clone();
      g.setTranslation(g.getTranslation()..add(t));
      node.globalTransform = g;
    }
    return CharacterMovement(
      translation: t,
      grounded: result.grounded,
      slidingDownSlope: result.slidingDownSlope,
    );
  }
}
