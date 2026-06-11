import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/physics/material.dart';
import 'package:flutter_scene/src/physics/shape.dart';
import 'package:vector_math/vector_math.dart';

/// Common surface for a collision volume attached to a [Node].
///
/// A collider pairs a [shape] with a [material] and a local pose. A node
/// may carry several colliders; together they form a compound around
/// that node's transform.
///
/// Concrete subclasses live in backend packages. Hold a reference as
/// [Collider] so user code stays portable between backends.
/// {@category Physics}
abstract class Collider extends Component {
  Shape get shape;
  set shape(Shape value);

  PhysicsMaterial get material;
  set material(PhysicsMaterial value);

  /// Bitmask identifying this collider's layer. A contact is generated
  /// only when each side's [collisionLayer] is set in the other side's
  /// [collisionMask].
  int get collisionLayer;
  set collisionLayer(int value);

  /// Bitmask of layers this collider responds to.
  int get collisionMask;
  set collisionMask(int value);

  /// When `true`, this collider emits [TriggerEntered] / [TriggerExited]
  /// events but does not produce a contact response.
  bool get isTrigger;
  set isTrigger(bool value);

  /// Pose of the collider relative to its owning [Node]. Used when one
  /// node carries multiple colliders, or when the collision volume is
  /// offset from the node's origin.
  Matrix4 get localPose;
  set localPose(Matrix4 value);
}
