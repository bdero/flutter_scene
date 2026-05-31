import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/physics/events.dart';
import 'package:flutter_scene/src/physics/queries.dart';
import 'package:flutter_scene/src/physics/shape.dart';
import 'package:vector_math/vector_math.dart';

/// The simulation world for a subtree of the scene graph.
///
/// Attach a concrete [PhysicsWorld] subclass (from a backend package, or
/// the built-in basic backend once that ships) to a node, typically the
/// scene root. Descendant [RigidBody] and [Collider] components register
/// with the nearest ancestor world on mount.
///
/// A scene may contain more than one world. Multiple worlds are
/// independent simulations and do not collide with each other.
///
/// The scene's per-frame driver runs the world on a fixed timestep,
/// substepping to keep up when the frame interval exceeds
/// [fixedTimestep] and interpolating transforms for the rendered frame.
/// Concrete subclasses implement [step] and [interpolateTransforms].
abstract class PhysicsWorld extends Component {
  /// Identifier of the concrete backend, suitable for logging
  /// (for example `"basic"`).
  String get backendName;

  /// World-space acceleration applied to every dynamic body each step.
  Vector3 gravity = Vector3(0, -9.81, 0);

  /// Length of one physics step, in seconds. Defaults to `1/60`.
  double fixedTimestep = 1.0 / 60.0;

  /// Maximum number of fixed steps consumed per frame. When the frame
  /// interval falls behind this many steps, remaining accumulated time
  /// is dropped to keep simulation from spiralling.
  int maxSubsteps = 8;

  /// Stream of collision lifecycle events for every body in this world.
  Stream<CollisionEvent> get collisions;

  RaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<RaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<OverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<OverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  ShapeCastHit? shapeCast(
    Shape shape,
    Matrix4 from,
    Vector3 direction,
    double distance, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  /// Advances the simulation by exactly [fixedDt] seconds.
  ///
  /// Called by the scene driver inside its substepping loop. User code
  /// should not call this directly.
  @internal
  void step(double fixedDt);

  /// Interpolates dynamic-body node transforms between the previous and
  /// current physics steps for smooth rendering when the frame rate is
  /// not a multiple of the physics rate.
  ///
  /// [alpha] is the accumulator fraction in `[0, 1]`: `0` snaps to the
  /// previous step, `1` snaps to the current step.
  ///
  /// Called by the scene driver after the substepping loop. User code
  /// should not call this directly.
  @internal
  void interpolateTransforms(double alpha);
}
