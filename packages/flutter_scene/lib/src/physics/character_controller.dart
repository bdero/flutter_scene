import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/physics/collider.dart';
import 'package:flutter_scene/src/physics/pending_registration.dart';
import 'package:flutter_scene/src/physics/physics_world.dart';
import 'package:scene/physics.dart' show CharacterMovement;
import 'package:vector_math/vector_math.dart';

export 'package:scene/physics.dart' show CharacterMovement;

/// Kinematic move-and-slide against the world's colliders.
///
/// Attach beside a [Collider] describing the character's volume; the
/// backend must support characters ([UnsupportedError] otherwise). Call
/// [move] once per fixed step; the corrected translation is applied to
/// the node and returned.
/// {@category Physics}
class KinematicCharacterController extends Component
    implements PendingPhysicsRegistration {
  KinematicCharacterController({
    Vector3? up,
    this.offset = 0.01,
    this.slide = true,
    this.maxSlopeClimbAngle = pi / 4,
    this.minSlopeSlideAngle = pi / 4,
    this.snapToGround = 0.1,
    this.autostep = false,
    this.autostepMaxHeight = 0.3,
    this.autostepMinWidth = 0.1,
    this.autostepIncludeDynamicBodies = true,
    this.mass = 0.0,
  }) : up = up ?? Vector3(0, 1, 0);

  /// The character's up direction.
  final Vector3 up;

  /// Gap kept between the character and obstacles.
  final double offset;

  /// Whether blocked motion slides along obstacles.
  final bool slide;

  final double maxSlopeClimbAngle;
  final double minSlopeSlideAngle;

  /// Maximum ground distance to snap down to when walking off edges, or
  /// null to disable snapping.
  final double? snapToGround;

  final bool autostep;
  final double autostepMaxHeight;
  final double autostepMinWidth;
  final bool autostepIncludeDynamicBodies;

  /// Mass applied when pushing dynamic bodies. `0` pushes nothing.
  final double mass;

  PhysicsWorld? _world;
  Collider? _collider;

  @override
  void onMount() {
    if (!_register(silent: false)) addPendingPhysicsRegistration(this);
  }

  @override
  bool internalRetryPhysicsRegistration() => _register(silent: true);

  bool _register({required bool silent}) {
    if (_world != null) return true;
    if (!isAttached) return true;
    final world = findAncestorWorld(node);
    if (world == null) {
      if (!silent) {
        debugPrint(
          'KinematicCharacterController mounted with no PhysicsWorld '
          'ancestor; waiting for one',
        );
      }
      return false;
    }
    if (!world.simulation.supportsCharacters) {
      debugPrint('${world.backendName} has no character controller; inert');
      return true;
    }
    final collider = node.getComponent<Collider>();
    if (collider == null || collider.handles.isEmpty) {
      if (!silent) {
        debugPrint(
          'KinematicCharacterController has no registered sibling Collider; '
          'waiting for it',
        );
      }
      return false;
    }
    _world = world;
    _collider = collider;
    return true;
  }

  @override
  void onUnmount() {
    removePendingPhysicsRegistration(this);
    _world = null;
    _collider = null;
  }

  /// Moves by up to [desiredTranslation], sliding along obstacles, and
  /// applies the corrected translation to the node.
  ///
  /// [deltaSeconds] defaults to the world's fixed timestep; call once per
  /// fixed step.
  CharacterMovement move(Vector3 desiredTranslation, {double? deltaSeconds}) {
    final world = _world;
    final collider = _collider;
    if (world == null || collider == null) {
      throw StateError('move() before the controller is mounted');
    }
    final transform = node.globalTransform;
    final position = transform.getTranslation();
    final movement = world.simulation.moveCharacter(
      collider.handles.first,
      position: position,
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
      characterMass: mass,
    );
    node.globalTransform = transform.clone()
      ..setTranslation(position + movement.translation);
    return movement;
  }
}
