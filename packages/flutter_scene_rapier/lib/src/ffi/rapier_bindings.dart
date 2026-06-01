// The operation surface RapierWorld drives, independent of how the shim
// is reached. One implementation calls the shim as a native dynamic
// library (dart:ffi); another calls it as a WebAssembly module. Both own
// their world and any scratch buffers internally and exchange plain Dart
// values here, so RapierWorld holds the maps, interpolation, event
// dispatch, and component-facing API in one place.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Body-kind bytes shared with the shim's C ABI.
const int bodyKindFixed = 0;
const int bodyKindKinematic = 1;
const int bodyKindDynamic = 2;

/// Scene-query filter bits shared with the shim's C ABI.
const int queryIncludeFixed = 1;
const int queryIncludeKinematic = 2;
const int queryIncludeDynamic = 4;
const int queryIncludeSensors = 8;

/// A single scene-query hit: the collider handle plus the contact point,
/// normal, and distance. RapierWorld resolves the handle to a component.
class RawHit {
  RawHit({
    required this.collider,
    required this.distance,
    required this.point,
    required this.normal,
  });

  final int collider;
  final double distance;
  final Vector3 point;
  final Vector3 normal;
}

/// A collision start/stop event with both collider handles and, for a
/// solid start, the slice of the contact buffer that belongs to it.
class RawCollisionEvent {
  RawCollisionEvent({
    required this.colliderA,
    required this.colliderB,
    required this.started,
    required this.sensor,
    required this.contactStart,
    required this.contactCount,
  });

  final int colliderA;
  final int colliderB;
  final bool started;
  final bool sensor;
  final int contactStart;
  final int contactCount;
}

/// One contact-manifold point on a solid collision.
class RawContactPoint {
  RawContactPoint({
    required this.position,
    required this.normal,
    required this.impulse,
    required this.separation,
  });

  final Vector3 position;
  final Vector3 normal;
  final double impulse;
  final double separation;
}

/// The corrected movement returned by a character-controller move.
typedef CharacterMovement = ({
  Vector3 translation,
  bool grounded,
  bool slidingDownSlope,
});

/// The shim operations RapierWorld depends on. Each implementation owns
/// the world it created and releases it (and any scratch) in [dispose].
/// Handles are the shim's packed `u64` values; on the web they are
/// limited to 53 bits of precision (see RapierBindings implementations).
abstract class RapierBindings {
  void setGravity(double x, double y, double z);
  void step(double dt);
  void dispose();

  // Bodies.
  int createBody(
    int kind,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
    double additionalMass,
  );
  void destroyBody(int handle);
  Vector3 bodyTranslation(int handle);
  Quaternion bodyRotation(int handle);
  Vector3 bodyLinearVelocity(int handle);
  Vector3 bodyAngularVelocity(int handle);
  void setBodyLinearVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  );
  void setBodyAngularVelocity(
    int handle,
    double x,
    double y,
    double z,
    bool wakeUp,
  );
  void setBodyLinearDamping(int handle, double damping);
  void setBodyAngularDamping(int handle, double damping);
  void setBodyAdditionalMass(int handle, double additionalMass);
  void setBodyNextKinematicPose(
    int handle,
    double px,
    double py,
    double pz,
    double qx,
    double qy,
    double qz,
    double qw,
  );
  void setBodyLockedAxes(int handle, int bits);
  void setBodyGravityScale(int handle, double scale);
  void setBodyCcdEnabled(int handle, bool enabled);
  void wakeBody(int handle);
  void sleepBody(int handle);
  bool isBodySleeping(int handle);
  void applyBodyForce(
    int handle,
    double fx,
    double fy,
    double fz,
    bool hasPoint,
    double px,
    double py,
    double pz,
  );
  void applyBodyImpulse(
    int handle,
    double ix,
    double iy,
    double iz,
    bool hasPoint,
    double px,
    double py,
    double pz,
  );
  void applyBodyTorque(int handle, double x, double y, double z);
  void applyBodyAngularImpulse(int handle, double x, double y, double z);

  // Colliders. Local poses arrive decomposed into translation + rotation.
  int colliderSphere(
    int bodyHandle,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  int colliderBox(
    int bodyHandle,
    double hx,
    double hy,
    double hz,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  int colliderCapsule(
    int bodyHandle,
    double halfHeight,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  int colliderCylinder(
    int bodyHandle,
    double halfHeight,
    double radius,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );

  /// Returns null when Rapier rejects the hull / mesh.
  int? colliderConvexHull(
    int bodyHandle,
    Float32List points,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  int? colliderTriMesh(
    int bodyHandle,
    Float32List vertices,
    Uint32List indices,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  int colliderHeightField(
    int bodyHandle,
    int nrows,
    int ncols,
    Float32List heights,
    double scaleX,
    double scaleY,
    double scaleZ,
    PhysicsMaterial material,
    bool isTrigger,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  void setColliderMaterial(int handle, PhysicsMaterial material);
  void setColliderCollisionGroups(int handle, int memberships, int filter);
  void setColliderSensor(int handle, bool isSensor);
  void setColliderLocalPose(
    int handle,
    double tx,
    double ty,
    double tz,
    double rx,
    double ry,
    double rz,
    double rw,
  );
  void destroyCollider(int handle);

  // Joints.
  int jointFixed(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  );
  int jointSpherical(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  );
  int jointRevolute(
    int bodyA,
    int bodyB,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  );
  int jointPrismatic(
    int bodyA,
    int bodyB,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  );
  int jointGeneric(
    int bodyA,
    int bodyB,
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
    bool collisionsEnabled,
  );
  void jointUpdateFixed(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  );
  void jointUpdateSpherical(
    int joint,
    Vector3 anchorA,
    Vector3 anchorB,
    bool collisionsEnabled,
  );
  void jointUpdateRevolute(
    int joint,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  );
  void jointUpdatePrismatic(
    int joint,
    Vector3 axis,
    Vector3 anchorA,
    Vector3 anchorB,
    double? lowerLimit,
    double? upperLimit,
    double? motorTargetVelocity,
    double? motorMaxForce,
    bool collisionsEnabled,
  );
  void jointUpdateGeneric(
    int joint,
    Vector3 anchorA,
    Quaternion basisA,
    Vector3 anchorB,
    Quaternion basisB,
    List<JointAxisConfig> axes,
    bool collisionsEnabled,
  );
  void destroyJoint(int handle);

  // Scene queries. The flag bitmask is built from the query* constants.
  RawHit? raycast(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    int flags,
  );
  List<RawHit> raycastAll(
    double ox,
    double oy,
    double oz,
    double dx,
    double dy,
    double dz,
    double maxDistance,
    int flags,
  );
  List<int> overlapSphere(
    double cx,
    double cy,
    double cz,
    double radius,
    int flags,
  );
  List<int> overlapBox(
    double cx,
    double cy,
    double cz,
    double hx,
    double hy,
    double hz,
    double qx,
    double qy,
    double qz,
    double qw,
    int flags,
  );
  RawHit? shapeCastSphere(
    double ox,
    double oy,
    double oz,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  );
  RawHit? shapeCastBox(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double hx,
    double hy,
    double hz,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  );
  RawHit? shapeCastCapsule(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double halfHeight,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  );
  RawHit? shapeCastCylinder(
    double ox,
    double oy,
    double oz,
    double qx,
    double qy,
    double qz,
    double qw,
    double halfHeight,
    double radius,
    double dx,
    double dy,
    double dz,
    double distance,
    int flags,
  );

  // Collision events captured during the last step.
  int collisionEventCount();
  RawCollisionEvent? collisionEventAt(int index);
  RawContactPoint? contactPointAt(int absoluteIndex);

  // Character controller.
  CharacterMovement moveCharacter(
    int collider,
    double dtx,
    double dty,
    double dtz,
    double deltaSeconds,
    double ux,
    double uy,
    double uz,
    double offset,
    bool slide,
    double maxSlopeClimbAngle,
    double minSlopeSlideAngle,
    double snapToGround,
    bool autostep,
    double autostepMaxHeight,
    double autostepMinWidth,
    bool autostepIncludeDynamicBodies,
  );
}
