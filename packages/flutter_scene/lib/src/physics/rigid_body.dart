import 'package:flutter_scene/src/components/component.dart';
import 'package:vector_math/vector_math.dart';

/// Simulation mode for a [RigidBody].
///
/// * [BodyType.fixed]: immovable environment geometry. The backend reads
///   the transform once on mount; mutating it at runtime is not
///   supported.
/// * [BodyType.kinematic]: user-driven motion. The user writes the
///   node's transform (or a velocity); the body pushes dynamic bodies it
///   contacts but is not itself pushed.
/// * [BodyType.dynamic_]: fully simulated. The backend writes the node's
///   transform each step in response to forces, contacts, and gravity.
///   The trailing underscore avoids the Dart `dynamic` keyword.
enum BodyType { fixed, kinematic, dynamic_ }

/// A simulated rigid body attached to a [Node].
///
/// One rigid body per node. Colliders attached to the same node (or to
/// descendant nodes, depending on the backend) define its collision
/// volume.
///
/// Transform sync direction depends on [type]: see [BodyType]. Mutating
/// a [BodyType.dynamic_] body's [Node.localTransform] is allowed but is
/// treated as a teleport (the backend overrides velocity and wakes the
/// body).
abstract class RigidBody extends Component {
  BodyType get type;

  /// Mass in kilograms. When null, the backend derives mass from the
  /// owning colliders' shapes and material densities.
  double? get mass;
  set mass(double? value);

  /// Local-space inertia tensor. When null, derived from the owning
  /// colliders.
  Matrix3? get inertiaTensor;
  set inertiaTensor(Matrix3? value);

  Vector3 get linearVelocity;
  set linearVelocity(Vector3 value);

  Vector3 get angularVelocity;
  set angularVelocity(Vector3 value);

  /// Per-step linear velocity damping in `[0, 1]`. `0` is no damping.
  double get linearDamping;
  set linearDamping(double value);

  /// Per-step angular velocity damping in `[0, 1]`. `0` is no damping.
  double get angularDamping;
  set angularDamping(double value);

  bool get useGravity;
  set useGravity(bool value);

  /// When `true`, the backend uses continuous collision detection to
  /// prevent fast-moving bodies from tunneling through thin colliders.
  bool get ccdEnabled;
  set ccdEnabled(bool value);

  /// Per-axis linear motion factors. Each component is in `[0, 1]`:
  /// `1` leaves the axis free, `0` locks it. Use to constrain motion
  /// to a plane (for example `(1, 1, 0)` for 2D-style motion in XY).
  Vector3 get linearAxisLocks;
  set linearAxisLocks(Vector3 value);

  /// Per-axis angular motion factors. See [linearAxisLocks].
  Vector3 get angularAxisLocks;
  set angularAxisLocks(Vector3 value);

  /// Applies a continuous [force] (in world space) for the duration of
  /// the current step. Use [applyImpulse] for an instantaneous change in
  /// momentum. When [atWorldPoint] is provided, the force produces a
  /// torque about the body's center of mass.
  void applyForce(Vector3 force, {Vector3? atWorldPoint});

  void applyImpulse(Vector3 impulse, {Vector3? atWorldPoint});

  void applyTorque(Vector3 torque);

  void applyAngularImpulse(Vector3 impulse);

  bool get isSleeping;

  void wakeUp();

  void putToSleep();
}
