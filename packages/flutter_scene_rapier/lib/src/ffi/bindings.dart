// FFI bindings for the flutter_scene_rapier native shim.
//
// The native side lives under packages/flutter_scene_rapier/native/.
// Every C ABI symbol declared in native/src/lib.rs has a matching
// @Native function here.

@DefaultAsset('package:flutter_scene_rapier/flutter_scene_rapier_native')
library;

import 'dart:ffi';

/// Opaque tag for the native `World` struct. Pointer instances are
/// allocated by [worldNew] and must be released with [worldDestroy].
final class NativeWorld extends Opaque {}

/// One hit returned by a scene query. Layout must match `FsrHit` in
/// `native/src/lib.rs`.
final class FsrHit extends Struct {
  @Uint64()
  external int collider;
  @Float()
  external double distance;
  @Float()
  external double px;
  @Float()
  external double py;
  @Float()
  external double pz;
  @Float()
  external double nx;
  @Float()
  external double ny;
  @Float()
  external double nz;
}

/// Bitmask flags for the `filter_flags` parameter on the scene-query
/// FFI entry points. Match the constants in `native/src/lib.rs`.
const int queryIncludeFixed = 1;
const int queryIncludeKinematic = 2;
const int queryIncludeDynamic = 4;
const int queryIncludeSensors = 8;

/// One collision start/stop event. Layout must match
/// `FsrCollisionEvent` in `native/src/lib.rs`.
final class FsrCollisionEvent extends Struct {
  @Uint64()
  external int colliderA;
  @Uint64()
  external int colliderB;
  @Uint8()
  external int started;
  @Uint8()
  external int sensor;

  /// Index of this event's first contact point in the world's flat
  /// contact-point buffer (see [worldContactPointAt]). Only solid
  /// `started` events carry contacts; otherwise [contactCount] is 0.
  @Uint32()
  external int contactStart;

  /// Number of contact points belonging to this event.
  @Uint32()
  external int contactCount;
}

/// One contact-manifold point on a solid collision event. Layout must
/// match `FsrContactPoint` in `native/src/lib.rs`.
final class FsrContactPoint extends Struct {
  @Float()
  external double px;
  @Float()
  external double py;
  @Float()
  external double pz;
  @Float()
  external double nx;
  @Float()
  external double ny;
  @Float()
  external double nz;
  @Float()
  external double impulse;
  @Float()
  external double separation;
}

/// Returns the sentinel value (42) hardcoded in the native shim.
/// Smoke test for verifying that the dynamic library loaded.
@Native<Int Function()>(symbol: 'fsr_proof_of_life')
external int proofOfLife();

@Native<Pointer<NativeWorld> Function()>(symbol: 'fsr_world_new')
external Pointer<NativeWorld> worldNew();

@Native<Void Function(Pointer<NativeWorld>)>(symbol: 'fsr_world_destroy')
external void worldDestroy(Pointer<NativeWorld> world);

@Native<Void Function(Pointer<NativeWorld>, Float, Float, Float)>(
  symbol: 'fsr_world_set_gravity',
)
external void worldSetGravity(
  Pointer<NativeWorld> world,
  double x,
  double y,
  double z,
);

@Native<Void Function(Pointer<NativeWorld>, Float)>(symbol: 'fsr_world_step')
external void worldStep(Pointer<NativeWorld> world, double dt);

@Native<
  Uint8 Function(
    Pointer<NativeWorld>,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Uint8,
    Pointer<FsrHit>,
  )
>(symbol: 'fsr_world_raycast')
external int worldRaycast(
  Pointer<NativeWorld> world,
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
  double maxDistance,
  int solid,
  int filterFlags,
  Pointer<FsrHit> out,
);

@Native<
  Size Function(
    Pointer<NativeWorld>,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Uint8,
  )
>(symbol: 'fsr_world_raycast_all')
external int worldRaycastAll(
  Pointer<NativeWorld> world,
  double ox,
  double oy,
  double oz,
  double dx,
  double dy,
  double dz,
  double maxDistance,
  int solid,
  int filterFlags,
);

@Native<Size Function(Pointer<NativeWorld>, Float, Float, Float, Float, Uint8)>(
  symbol: 'fsr_world_overlap_sphere',
)
external int worldOverlapSphere(
  Pointer<NativeWorld> world,
  double cx,
  double cy,
  double cz,
  double radius,
  int filterFlags,
);

@Native<
  Size Function(
    Pointer<NativeWorld>,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
  )
>(symbol: 'fsr_world_overlap_box')
external int worldOverlapBox(
  Pointer<NativeWorld> world,
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
  int filterFlags,
);

@Native<
  Uint8 Function(
    Pointer<NativeWorld>,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Pointer<FsrHit>,
  )
>(symbol: 'fsr_world_shape_cast_sphere')
external int worldShapeCastSphere(
  Pointer<NativeWorld> world,
  double ox,
  double oy,
  double oz,
  double radius,
  double dx,
  double dy,
  double dz,
  double distance,
  int filterFlags,
  Pointer<FsrHit> out,
);

@Native<Uint8 Function(Pointer<NativeWorld>, Size, Pointer<FsrHit>)>(
  symbol: 'fsr_world_query_result_at',
)
external int worldQueryResultAt(
  Pointer<NativeWorld> world,
  int index,
  Pointer<FsrHit> out,
);

@Native<Size Function(Pointer<NativeWorld>)>(
  symbol: 'fsr_world_collision_event_count',
)
external int worldCollisionEventCount(Pointer<NativeWorld> world);

@Native<Uint8 Function(Pointer<NativeWorld>, Size, Pointer<FsrCollisionEvent>)>(
  symbol: 'fsr_world_collision_event_at',
)
external int worldCollisionEventAt(
  Pointer<NativeWorld> world,
  int index,
  Pointer<FsrCollisionEvent> out,
);

@Native<Uint8 Function(Pointer<NativeWorld>, Size, Pointer<FsrContactPoint>)>(
  symbol: 'fsr_world_contact_point_at',
)
external int worldContactPointAt(
  Pointer<NativeWorld> world,
  int index,
  Pointer<FsrContactPoint> out,
);

/// Body kind bytes matching the constants in `native/src/lib.rs`.
const int bodyKindFixed = 0;
const int bodyKindKinematic = 1;
const int bodyKindDynamic = 2;

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_body_create')
external int bodyCreate(
  Pointer<NativeWorld> world,
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

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(symbol: 'fsr_body_destroy')
external void bodyDestroy(Pointer<NativeWorld> world, int handle);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Pointer<Float>)>(
  symbol: 'fsr_body_translation',
)
external void bodyTranslation(
  Pointer<NativeWorld> world,
  int handle,
  Pointer<Float> out,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Pointer<Float>)>(
  symbol: 'fsr_body_rotation',
)
external void bodyRotation(
  Pointer<NativeWorld> world,
  int handle,
  Pointer<Float> out,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Pointer<Float>)>(
  symbol: 'fsr_body_linear_velocity',
)
external void bodyLinearVelocity(
  Pointer<NativeWorld> world,
  int handle,
  Pointer<Float> out,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Pointer<Float>)>(
  symbol: 'fsr_body_angular_velocity',
)
external void bodyAngularVelocity(
  Pointer<NativeWorld> world,
  int handle,
  Pointer<Float> out,
);

@Native<
  Void Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_body_set_next_kinematic_pose')
external void bodySetNextKinematicPose(
  Pointer<NativeWorld> world,
  int handle,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Void Function(Pointer<NativeWorld>, Uint64, Float, Float, Float, Uint8)
>(symbol: 'fsr_body_set_linear_velocity')
external void bodySetLinearVelocity(
  Pointer<NativeWorld> world,
  int handle,
  double vx,
  double vy,
  double vz,
  int wakeUp,
);

@Native<
  Void Function(Pointer<NativeWorld>, Uint64, Float, Float, Float, Uint8)
>(symbol: 'fsr_body_set_angular_velocity')
external void bodySetAngularVelocity(
  Pointer<NativeWorld> world,
  int handle,
  double wx,
  double wy,
  double wz,
  int wakeUp,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float)>(
  symbol: 'fsr_body_set_linear_damping',
)
external void bodySetLinearDamping(
  Pointer<NativeWorld> world,
  int handle,
  double damping,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float)>(
  symbol: 'fsr_body_set_angular_damping',
)
external void bodySetAngularDamping(
  Pointer<NativeWorld> world,
  int handle,
  double damping,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float)>(
  symbol: 'fsr_body_set_additional_mass',
)
external void bodySetAdditionalMass(
  Pointer<NativeWorld> world,
  int handle,
  double additionalMass,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Uint8)>(
  symbol: 'fsr_body_set_locked_axes',
)
external void bodySetLockedAxes(
  Pointer<NativeWorld> world,
  int handle,
  int lockBits,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float)>(
  symbol: 'fsr_body_set_gravity_scale',
)
external void bodySetGravityScale(
  Pointer<NativeWorld> world,
  int handle,
  double scale,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Uint8)>(
  symbol: 'fsr_body_set_ccd_enabled',
)
external void bodySetCcdEnabled(
  Pointer<NativeWorld> world,
  int handle,
  int enabled,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(symbol: 'fsr_body_wake_up')
external void bodyWakeUp(Pointer<NativeWorld> world, int handle);

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(symbol: 'fsr_body_sleep')
external void bodySleep(Pointer<NativeWorld> world, int handle);

@Native<Uint8 Function(Pointer<NativeWorld>, Uint64)>(
  symbol: 'fsr_body_is_sleeping',
)
external int bodyIsSleeping(Pointer<NativeWorld> world, int handle);

@Native<
  Void Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_body_apply_force')
external void bodyApplyForce(
  Pointer<NativeWorld> world,
  int handle,
  double fx,
  double fy,
  double fz,
  int hasWorldPoint,
  double px,
  double py,
  double pz,
);

@Native<
  Void Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_body_apply_impulse')
external void bodyApplyImpulse(
  Pointer<NativeWorld> world,
  int handle,
  double ix,
  double iy,
  double iz,
  int hasWorldPoint,
  double px,
  double py,
  double pz,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float, Float, Float)>(
  symbol: 'fsr_body_apply_torque',
)
external void bodyApplyTorque(
  Pointer<NativeWorld> world,
  int handle,
  double tx,
  double ty,
  double tz,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float, Float, Float)>(
  symbol: 'fsr_body_apply_angular_impulse',
)
external void bodyApplyAngularImpulse(
  Pointer<NativeWorld> world,
  int handle,
  double tx,
  double ty,
  double tz,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_sphere')
external int colliderSphere(
  Pointer<NativeWorld> world,
  int bodyHandle,
  double radius,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_box')
external int colliderBox(
  Pointer<NativeWorld> world,
  int bodyHandle,
  double hx,
  double hy,
  double hz,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_capsule')
external int colliderCapsule(
  Pointer<NativeWorld> world,
  int bodyHandle,
  double halfHeight,
  double radius,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_cylinder')
external int colliderCylinder(
  Pointer<NativeWorld> world,
  int bodyHandle,
  double halfHeight,
  double radius,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Pointer<Float>,
    Size,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_convex_hull')
external int colliderConvexHull(
  Pointer<NativeWorld> world,
  int bodyHandle,
  Pointer<Float> points,
  int pointCount,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Pointer<Float>,
    Size,
    Pointer<Uint32>,
    Size,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_trimesh')
external int colliderTriMesh(
  Pointer<NativeWorld> world,
  int bodyHandle,
  Pointer<Float> vertices,
  int vertexCount,
  Pointer<Uint32> indices,
  int triangleCount,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Uint32,
    Uint32,
    Pointer<Float>,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_heightfield')
external int colliderHeightField(
  Pointer<NativeWorld> world,
  int bodyHandle,
  int nrows,
  int ncols,
  Pointer<Float> heights,
  double scaleX,
  double scaleY,
  double scaleZ,
  double friction,
  double restitution,
  double density,
  int isSensor,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Float, Float, Float)>(
  symbol: 'fsr_collider_set_material',
)
external void colliderSetMaterial(
  Pointer<NativeWorld> world,
  int handle,
  double friction,
  double restitution,
  double density,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Uint32, Uint32)>(
  symbol: 'fsr_collider_set_collision_groups',
)
external void colliderSetCollisionGroups(
  Pointer<NativeWorld> world,
  int handle,
  int memberships,
  int filter,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64, Uint8)>(
  symbol: 'fsr_collider_set_sensor',
)
external void colliderSetSensor(
  Pointer<NativeWorld> world,
  int handle,
  int isSensor,
);

@Native<
  Void Function(
    Pointer<NativeWorld>,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
  )
>(symbol: 'fsr_collider_set_local_pose')
external void colliderSetLocalPose(
  Pointer<NativeWorld> world,
  int handle,
  double px,
  double py,
  double pz,
  double qx,
  double qy,
  double qz,
  double qw,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(
  symbol: 'fsr_collider_destroy',
)
external void colliderDestroy(Pointer<NativeWorld> world, int handle);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
  )
>(symbol: 'fsr_joint_fixed')
external int jointFixed(
  Pointer<NativeWorld> world,
  int bodyA,
  int bodyB,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  int collisionsEnabled,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
  )
>(symbol: 'fsr_joint_spherical')
external int jointSpherical(
  Pointer<NativeWorld> world,
  int bodyA,
  int bodyB,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  int collisionsEnabled,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Uint8,
  )
>(symbol: 'fsr_joint_revolute')
external int jointRevolute(
  Pointer<NativeWorld> world,
  int bodyA,
  int bodyB,
  double axisX,
  double axisY,
  double axisZ,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  int hasLimits,
  double lower,
  double upper,
  int hasMotor,
  double motorTargetVelocity,
  double motorMaxForce,
  int collisionsEnabled,
);

@Native<
  Uint64 Function(
    Pointer<NativeWorld>,
    Uint64,
    Uint64,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Uint8,
    Float,
    Float,
    Uint8,
  )
>(symbol: 'fsr_joint_prismatic')
external int jointPrismatic(
  Pointer<NativeWorld> world,
  int bodyA,
  int bodyB,
  double axisX,
  double axisY,
  double axisZ,
  double ax,
  double ay,
  double az,
  double bx,
  double by,
  double bz,
  int hasLimits,
  double lower,
  double upper,
  int hasMotor,
  double motorTargetVelocity,
  double motorMaxForce,
  int collisionsEnabled,
);

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(
  symbol: 'fsr_joint_destroy',
)
external void jointDestroy(Pointer<NativeWorld> world, int handle);
