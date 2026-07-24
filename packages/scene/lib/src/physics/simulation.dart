import 'package:vector_math/vector_math.dart';

import 'joint_desc.dart';
import 'material.dart';
import 'pose_target.dart';
import 'shape.dart';
import 'sim_types.dart';

/// The backend driver contract, a physics engine addressed by integer
/// handles, decoupled from any scene graph through [PoseTarget]s.
///
/// Engine layers (flutter_scene's component layer, headless servers) own
/// the mapping from handles to their objects. Backends implement stepping,
/// queries, and events; unsupported capabilities throw [UnsupportedError]
/// and are advertised through the `supports*` getters where callers need
/// to branch.
abstract class PhysicsSimulation {
  /// Identifier of the concrete backend, suitable for logging (for
  /// example `"rapier3d"`).
  String get backendName;

  /// World-space acceleration applied to every dynamic body each step.
  Vector3 gravity = Vector3(0, -9.81, 0);

  /// Length of one physics step, in seconds.
  double fixedTimestep = 1.0 / 60.0;

  /// Maximum number of fixed steps consumed per frame by the driver.
  int maxSubsteps = 8;

  /// Collision lifecycle events, keyed by collider handle.
  Stream<SimCollisionEvent> get collisions;

  // --- Bodies ---

  /// Creates a body at [target]'s current pose and returns its handle.
  /// Dynamic bodies write their simulated pose back to [target] during
  /// [interpolatePoses].
  int createBody({
    required PoseTarget target,
    required BodyType type,
    double? additionalMass,
  });

  void destroyBody(int bodyHandle);

  void setBodyKind(int bodyHandle, BodyType type);

  /// Creates an invisible fixed body for anchoring world-space joints.
  int createAnchorBody();

  void destroyAnchorBody(int bodyHandle);

  (Vector3, Quaternion) readBodyPose(int bodyHandle);
  Vector3 readBodyLinearVelocity(int bodyHandle);
  Vector3 readBodyAngularVelocity(int bodyHandle);

  void setBodyLinearVelocity(int bodyHandle, Vector3 velocity);
  void setBodyAngularVelocity(int bodyHandle, Vector3 velocity);
  void setBodyLinearDamping(int bodyHandle, double damping);
  void setBodyAngularDamping(int bodyHandle, double damping);
  void setBodyGravityScale(int bodyHandle, double scale);
  void setBodyCcdEnabled(int bodyHandle, bool enabled);
  void setBodyAdditionalMass(int bodyHandle, double mass);

  /// Per-axis motion factors in `[0, 1]`, `1` free, `0` locked.
  void setBodyAxisLocks(int bodyHandle, Vector3 linear, Vector3 angular);

  /// Pushes the pose a kinematic body should reach by the next step.
  void setBodyKinematicTargetPose(
    int bodyHandle,
    Vector3 translation,
    Quaternion rotation,
  );

  void applyForce(int bodyHandle, Vector3 force, {Vector3? atWorldPoint});
  void applyImpulse(int bodyHandle, Vector3 impulse, {Vector3? atWorldPoint});
  void applyTorque(int bodyHandle, Vector3 torque);
  void applyAngularImpulse(int bodyHandle, Vector3 impulse);

  bool isBodySleeping(int bodyHandle);
  void wakeBody(int bodyHandle);
  void sleepBody(int bodyHandle);

  // --- Colliders ---

  /// Creates collision geometry on [bodyHandle] and returns one handle per
  /// created collider (compound shapes may decompose; how is backend
  /// private). Empty means the shape is unsupported by this backend.
  List<int> createColliders(
    int bodyHandle,
    Shape shape, {
    PhysicsMaterial material = PhysicsMaterial.defaultMaterial,
    bool isTrigger = false,
    Matrix4? localPose,
    int collisionLayer = 0xFFFFFFFF,
    int collisionMask = 0xFFFFFFFF,
  });

  void destroyCollider(int colliderHandle);

  void setColliderMaterial(int colliderHandle, PhysicsMaterial material);
  void setColliderFilter(int colliderHandle, int layer, int mask);

  // --- Joints ---

  bool get supportsJoints => true;

  int createJoint(JointDesc desc);

  /// Reconfigures a joint in place. Backends without native updates may
  /// destroy and recreate internally; the handle stays valid.
  void updateJoint(int jointHandle, JointDesc desc);

  void destroyJoint(int jointHandle);

  // --- Queries ---

  SimRaycastHit? raycast(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<SimRaycastHit> raycastAll(
    Ray ray, {
    double maxDistance = double.infinity,
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<SimOverlapHit> overlapSphere(
    Vector3 center,
    double radius, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  List<SimOverlapHit> overlapBox(
    Vector3 center,
    Vector3 halfExtents,
    Quaternion rotation, {
    int layerMask = 0xFFFFFFFF,
    bool includeFixed = true,
    bool includeKinematic = true,
    bool includeDynamic = true,
    bool includeTriggers = false,
  });

  SimShapeCastHit? shapeCast(
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

  // --- Characters ---

  bool get supportsCharacters => false;

  /// Kinematic character move-and-slide against [colliderHandle]'s
  /// surroundings. See the flutter_scene character controller for the
  /// parameter semantics.
  CharacterMovement moveCharacter(
    int colliderHandle, {
    required Vector3 position,
    required Vector3 desiredTranslation,
    double? deltaSeconds,
    Vector3? up,
    double offset = 0.01,
    bool slide = true,
    double maxSlopeClimbAngle = 0.7853981633974483,
    double minSlopeSlideAngle = 0.7853981633974483,
    double? snapToGround = 0.1,
    bool autostep = false,
    double autostepMaxHeight = 0.3,
    double autostepMinWidth = 0.1,
    bool autostepIncludeDynamicBodies = true,
    double characterMass = 0.0,
  }) => throw UnsupportedError('$backendName has no character controller');

  // --- Stepping ---

  /// Advances the simulation by exactly [fixedDt] seconds.
  void step(double fixedDt);

  /// Writes interpolated dynamic-body poses to their [PoseTarget]s.
  /// [alpha] is the accumulator fraction in `[0, 1]`, `0` the previous
  /// step, `1` the current step.
  void interpolatePoses(double alpha);

  /// Releases every body, collider, and joint. Called by owners when the
  /// simulation is discarded.
  void dispose();
}
