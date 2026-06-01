//! Flutter Scene Rapier native shim.
//!
//! Owns the Rapier PhysicsPipeline state behind opaque pointers and
//! exposes a small C ABI for the Dart bindings. All operations on the
//! world go through this surface; the Dart side never sees Rapier's
//! Rust types directly.

use rapier3d::parry;
use rapier3d::prelude::*;
use std::os::raw::c_int;

/// Owns the full set of Rapier pipeline state for one simulation.
/// Allocated by [`fsr_world_new`], freed by [`fsr_world_destroy`].
pub struct World {
    rigid_body_set: RigidBodySet,
    collider_set: ColliderSet,
    island_manager: IslandManager,
    broad_phase: BroadPhaseBvh,
    narrow_phase: NarrowPhase,
    impulse_joints: ImpulseJointSet,
    multibody_joints: MultibodyJointSet,
    ccd_solver: CCDSolver,
    physics_pipeline: PhysicsPipeline,
    integration_parameters: IntegrationParameters,
    gravity: Vector,
    /// Last query's hit list. Variable-length results are written here
    /// by the raycast / overlap / shape-cast entry points; the Dart
    /// side then reads them out via [`fsr_world_query_result_at`].
    query_hits: Vec<FsrHit>,
    /// Collects collision start/stop events during a step.
    collision_collector: CollisionCollector,
    /// The most recent step's collision events, moved out of the
    /// collector after [`fsr_world_step`] returns. Read by the Dart
    /// side via [`fsr_world_collision_event_at`].
    collision_events: Vec<FsrCollisionEvent>,
    /// Flat buffer of contact points for the most recent step's solid
    /// `started` events. Each event owns the slice
    /// `[contact_start, contact_start + contact_count)`; read by the Dart
    /// side via [`fsr_world_contact_point_at`].
    contact_points: Vec<FsrContactPoint>,
}

/// A collision start/stop event. Same layout as the Dart-side struct
/// in `lib/src/ffi/bindings.dart`.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct FsrCollisionEvent {
    pub collider_a: u64,
    pub collider_b: u64,
    /// 1 for a Started event, 0 for a Stopped event.
    pub started: u8,
    /// 1 when at least one collider in the pair is a sensor (trigger),
    /// 0 for a solid contact.
    pub sensor: u8,
    /// Index of this event's first contact point in the world's flat
    /// contact-point buffer, read via [`fsr_world_contact_point_at`].
    /// Only solid `started` events carry contacts; everything else has
    /// `contact_count == 0`.
    pub contact_start: u32,
    /// Number of contact points belonging to this event.
    pub contact_count: u32,
}

/// One contact-manifold point on a solid [`FsrCollisionEvent`]. Same
/// layout as the Dart-side struct in `lib/src/ffi/bindings.dart`.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct FsrContactPoint {
    /// World-space contact position (on collider A's surface).
    pub px: Real,
    pub py: Real,
    pub pz: Real,
    /// World-space contact normal, pointing from collider A into B.
    pub nx: Real,
    pub ny: Real,
    pub nz: Real,
    /// Normal impulse the solver applied at this contact this step.
    pub impulse: Real,
    /// Gap along the normal: positive when separated, negative when the
    /// shapes interpenetrate.
    pub separation: Real,
}

/// Thread-safe sink that Rapier writes collision events into during a
/// step. EventHandler requires Send + Sync, so the buffer lives behind
/// a Mutex even though the FFI only ever steps on one thread.
#[derive(Default)]
struct CollisionCollector {
    events: std::sync::Mutex<Vec<FsrCollisionEvent>>,
}

impl EventHandler for CollisionCollector {
    fn handle_collision_event(
        &self,
        _bodies: &RigidBodySet,
        _colliders: &ColliderSet,
        event: CollisionEvent,
        _contact_pair: Option<&ContactPair>,
    ) {
        let (a, b, flags, started) = match event {
            CollisionEvent::Started(a, b, f) => (a, b, f, 1u8),
            CollisionEvent::Stopped(a, b, f) => (a, b, f, 0u8),
        };
        let sensor = flags.contains(CollisionEventFlags::SENSOR) as u8;
        if let Ok(mut events) = self.events.lock() {
            // Contact points are resolved after the step, once the solver
            // has filled in impulses; leave the range empty here.
            events.push(FsrCollisionEvent {
                collider_a: collider_to_raw(a),
                collider_b: collider_to_raw(b),
                started,
                sensor,
                contact_start: 0,
                contact_count: 0,
            });
        }
    }

    fn handle_contact_force_event(
        &self,
        _dt: Real,
        _bodies: &RigidBodySet,
        _colliders: &ColliderSet,
        _contact_pair: &ContactPair,
        _total_force_magnitude: Real,
    ) {
    }
}

/// One hit returned by a scene query. Same layout as the Dart-side
/// struct in `lib/src/ffi/bindings.dart`.
#[repr(C)]
#[derive(Copy, Clone)]
pub struct FsrHit {
    pub collider: u64,
    pub distance: Real,
    pub px: Real,
    pub py: Real,
    pub pz: Real,
    pub nx: Real,
    pub ny: Real,
    pub nz: Real,
}

/// Filter bits for scene queries. Matches the constants on the Dart
/// side.
const QUERY_INCLUDE_FIXED: u8 = 1;
const QUERY_INCLUDE_KINEMATIC: u8 = 2;
const QUERY_INCLUDE_DYNAMIC: u8 = 4;
const QUERY_INCLUDE_SENSORS: u8 = 8;

fn query_filter(flags: u8) -> QueryFilter<'static> {
    let mut qf = QueryFilterFlags::empty();
    if flags & QUERY_INCLUDE_FIXED == 0 {
        qf |= QueryFilterFlags::EXCLUDE_FIXED;
    }
    if flags & QUERY_INCLUDE_KINEMATIC == 0 {
        qf |= QueryFilterFlags::EXCLUDE_KINEMATIC;
    }
    if flags & QUERY_INCLUDE_DYNAMIC == 0 {
        qf |= QueryFilterFlags::EXCLUDE_DYNAMIC;
    }
    if flags & QUERY_INCLUDE_SENSORS == 0 {
        qf |= QueryFilterFlags::EXCLUDE_SENSORS;
    }
    let mut filter = QueryFilter::new();
    filter.flags = qf;
    filter
}

fn make_hit(handle: ColliderHandle, distance: Real, point: Vector, normal: Vector) -> FsrHit {
    FsrHit {
        collider: collider_to_raw(handle),
        distance,
        px: point.x,
        py: point.y,
        pz: point.z,
        nx: normal.x,
        ny: normal.y,
        nz: normal.z,
    }
}

impl Default for World {
    fn default() -> Self {
        Self {
            rigid_body_set: RigidBodySet::new(),
            collider_set: ColliderSet::new(),
            island_manager: IslandManager::new(),
            broad_phase: BroadPhaseBvh::default(),
            narrow_phase: NarrowPhase::new(),
            impulse_joints: ImpulseJointSet::new(),
            multibody_joints: MultibodyJointSet::new(),
            ccd_solver: CCDSolver::new(),
            physics_pipeline: PhysicsPipeline::new(),
            integration_parameters: IntegrationParameters::default(),
            gravity: Vector::new(0.0, -9.81, 0.0),
            query_hits: Vec::new(),
            collision_collector: CollisionCollector::default(),
            collision_events: Vec::new(),
            contact_points: Vec::new(),
        }
    }
}

/// Sentinel returned by the proof-of-life entry point. The Dart side
/// can call it to verify the dynamic library loaded.
#[no_mangle]
pub extern "C" fn fsr_proof_of_life() -> c_int {
    42
}

/// Casts a ray and returns the closest hit, if any. `solid` controls
/// whether the ray starting inside a shape registers a hit at the
/// origin.
///
/// # Safety
/// `world` must be live. `out` must point to a writable [`FsrHit`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_raycast(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    max_distance: Real,
    solid: u8,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    let w = &mut *world;
    let ray = parry::query::Ray::new(Vector::new(ox, oy, oz), Vector::new(dx, dy, dz).normalize());
    let qp = w.broad_phase.as_query_pipeline(
        w.narrow_phase.query_dispatcher(),
        &w.rigid_body_set,
        &w.collider_set,
        query_filter(filter_flags),
    );
    let Some((handle, hit)) = qp.cast_ray_and_get_normal(&ray, max_distance, solid != 0) else {
        return 0;
    };
    let point = ray.point_at(hit.time_of_impact);
    *out = make_hit(handle, hit.time_of_impact, point, hit.normal);
    1
}

/// Casts a ray and collects every hit along its path. Results are
/// stashed in the world's internal buffer and read out via
/// [`fsr_world_query_result_at`].
///
/// Returns the number of hits collected. The buffer is invalidated on
/// the next scene-query call.
///
/// # Safety
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_world_raycast_all(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    max_distance: Real,
    solid: u8,
    filter_flags: u8,
) -> usize {
    let w = &mut *world;
    let ray = parry::query::Ray::new(Vector::new(ox, oy, oz), Vector::new(dx, dy, dz).normalize());
    w.query_hits.clear();
    let qp = w.broad_phase.as_query_pipeline(
        w.narrow_phase.query_dispatcher(),
        &w.rigid_body_set,
        &w.collider_set,
        query_filter(filter_flags),
    );
    for (handle, _, hit) in qp.intersect_ray(ray, max_distance, solid != 0) {
        let point = ray.point_at(hit.time_of_impact);
        w.query_hits
            .push(make_hit(handle, hit.time_of_impact, point, hit.normal));
    }
    w.query_hits.sort_by(|a, b| {
        a.distance
            .partial_cmp(&b.distance)
            .unwrap_or(core::cmp::Ordering::Equal)
    });
    w.query_hits.len()
}

/// Collects every collider intersecting a probe ball. Results land in
/// the same buffer as [`fsr_world_raycast_all`]. `distance` and the
/// hit normal are zero for overlap queries.
///
/// # Safety
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_world_overlap_sphere(
    world: *mut World,
    cx: Real,
    cy: Real,
    cz: Real,
    radius: Real,
    filter_flags: u8,
) -> usize {
    let w = &mut *world;
    w.query_hits.clear();
    let pose = Pose::from_parts(Vector::new(cx, cy, cz), Rotation::IDENTITY);
    let shape = parry::shape::Ball::new(radius);
    let qp = w.broad_phase.as_query_pipeline(
        w.narrow_phase.query_dispatcher(),
        &w.rigid_body_set,
        &w.collider_set,
        query_filter(filter_flags),
    );
    for (handle, _) in qp.intersect_shape(pose, &shape) {
        w.query_hits
            .push(make_hit(handle, 0.0, Vector::ZERO, Vector::ZERO));
    }
    w.query_hits.len()
}

/// Collects every collider intersecting an oriented box. Same result
/// semantics as [`fsr_world_overlap_sphere`].
///
/// # Safety
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_world_overlap_box(
    world: *mut World,
    cx: Real,
    cy: Real,
    cz: Real,
    hx: Real,
    hy: Real,
    hz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
    filter_flags: u8,
) -> usize {
    let w = &mut *world;
    w.query_hits.clear();
    let pose = Pose::from_parts(Vector::new(cx, cy, cz), Rotation::from_xyzw(qx, qy, qz, qw));
    let shape = parry::shape::Cuboid::new(Vector::new(hx, hy, hz));
    let qp = w.broad_phase.as_query_pipeline(
        w.narrow_phase.query_dispatcher(),
        &w.rigid_body_set,
        &w.collider_set,
        query_filter(filter_flags),
    );
    for (handle, _) in qp.intersect_shape(pose, &shape) {
        w.query_hits
            .push(make_hit(handle, 0.0, Vector::ZERO, Vector::ZERO));
    }
    w.query_hits.len()
}

/// Sweeps `shape` from `pose` along `dir` for at most `distance` and
/// writes the closest contact into `out`. Shared by every
/// `fsr_world_shape_cast_*` entry point.
///
/// # Safety
/// `world` must be live; `out` must point to a writable [`FsrHit`].
unsafe fn shape_cast_impl(
    world: *mut World,
    pose: Pose,
    dir: Vector,
    shape: &dyn parry::shape::Shape,
    distance: Real,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    let w = &mut *world;
    let options = parry::query::ShapeCastOptions {
        max_time_of_impact: distance,
        target_distance: 0.0,
        stop_at_penetration: true,
        compute_impact_geometry_on_penetration: true,
    };
    let qp = w.broad_phase.as_query_pipeline(
        w.narrow_phase.query_dispatcher(),
        &w.rigid_body_set,
        &w.collider_set,
        query_filter(filter_flags),
    );
    let Some((handle, hit)) = qp.cast_shape(&pose, dir, shape, options) else {
        return 0;
    };
    *out = make_hit(handle, hit.time_of_impact, hit.witness1, hit.normal1);
    1
}

/// Sweeps a sphere along a direction and returns the closest collider
/// it would contact.
///
/// # Safety
/// `world` must be live. `out` must point to a writable [`FsrHit`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_shape_cast_sphere(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    radius: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    distance: Real,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    // A sphere is rotation-invariant, so the probe pose carries no
    // rotation.
    let pose = Pose::from_parts(Vector::new(ox, oy, oz), Rotation::IDENTITY);
    let shape = parry::shape::Ball::new(radius);
    shape_cast_impl(
        world,
        pose,
        Vector::new(dx, dy, dz),
        &shape,
        distance,
        filter_flags,
        out,
    )
}

/// Sweeps an oriented box along a direction. `(qx, qy, qz, qw)` is the
/// probe's world rotation.
///
/// # Safety
/// `world` must be live. `out` must point to a writable [`FsrHit`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn fsr_world_shape_cast_box(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
    hx: Real,
    hy: Real,
    hz: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    distance: Real,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    let pose = Pose::from_parts(Vector::new(ox, oy, oz), Rotation::from_xyzw(qx, qy, qz, qw));
    let shape = parry::shape::Cuboid::new(Vector::new(hx, hy, hz));
    shape_cast_impl(
        world,
        pose,
        Vector::new(dx, dy, dz),
        &shape,
        distance,
        filter_flags,
        out,
    )
}

/// Sweeps an oriented Y-axis capsule along a direction.
///
/// # Safety
/// `world` must be live. `out` must point to a writable [`FsrHit`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn fsr_world_shape_cast_capsule(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
    half_height: Real,
    radius: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    distance: Real,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    let pose = Pose::from_parts(Vector::new(ox, oy, oz), Rotation::from_xyzw(qx, qy, qz, qw));
    let shape = parry::shape::Capsule::new_y(half_height, radius);
    shape_cast_impl(
        world,
        pose,
        Vector::new(dx, dy, dz),
        &shape,
        distance,
        filter_flags,
        out,
    )
}

/// Sweeps an oriented Y-axis cylinder along a direction.
///
/// # Safety
/// `world` must be live. `out` must point to a writable [`FsrHit`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn fsr_world_shape_cast_cylinder(
    world: *mut World,
    ox: Real,
    oy: Real,
    oz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
    half_height: Real,
    radius: Real,
    dx: Real,
    dy: Real,
    dz: Real,
    distance: Real,
    filter_flags: u8,
    out: *mut FsrHit,
) -> u8 {
    let pose = Pose::from_parts(Vector::new(ox, oy, oz), Rotation::from_xyzw(qx, qy, qz, qw));
    let shape = parry::shape::Cylinder::new(half_height, radius);
    shape_cast_impl(
        world,
        pose,
        Vector::new(dx, dy, dz),
        &shape,
        distance,
        filter_flags,
        out,
    )
}

/// Copies the i-th entry of the last multi-hit query into `out`.
/// Returns 0 if `index` is out of range.
///
/// # Safety
/// `world` must be live; `out` must point to a writable [`FsrHit`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_query_result_at(
    world: *const World,
    index: usize,
    out: *mut FsrHit,
) -> u8 {
    let w = &*world;
    let Some(hit) = w.query_hits.get(index) else {
        return 0;
    };
    *out = *hit;
    1
}

/// Body kinds matching the abstract `BodyType` on the Dart side.
const BODY_KIND_FIXED: u8 = 0;
const BODY_KIND_KINEMATIC: u8 = 1;
#[allow(dead_code)]
const BODY_KIND_DYNAMIC: u8 = 2;

fn index_to_raw(idx: rapier3d::data::arena::Index) -> u64 {
    let (i, g) = idx.into_raw_parts();
    ((g as u64) << 32) | (i as u64)
}

fn index_from_raw(raw: u64) -> rapier3d::data::arena::Index {
    let i = raw as u32;
    let g = (raw >> 32) as u32;
    rapier3d::data::arena::Index::from_raw_parts(i, g)
}

fn handle_to_raw(h: RigidBodyHandle) -> u64 {
    index_to_raw(h.0)
}

fn handle_from_raw(raw: u64) -> RigidBodyHandle {
    RigidBodyHandle(index_from_raw(raw))
}

fn collider_to_raw(h: ColliderHandle) -> u64 {
    index_to_raw(h.0)
}

fn collider_from_raw(raw: u64) -> ColliderHandle {
    ColliderHandle(index_from_raw(raw))
}

/// Allocates a fresh [`World`] and returns an owning pointer. Caller
/// must release the pointer with [`fsr_world_destroy`].
#[no_mangle]
pub extern "C" fn fsr_world_new() -> *mut World {
    Box::into_raw(Box::new(World::default()))
}

/// Frees a [`World`] previously returned by [`fsr_world_new`]. Null is
/// a no-op so callers can safely double-free a null handle.
///
/// # Safety
/// `world` must have come from [`fsr_world_new`] and must not be used
/// after this call.
#[no_mangle]
pub unsafe extern "C" fn fsr_world_destroy(world: *mut World) {
    if world.is_null() {
        return;
    }
    drop(Box::from_raw(world));
}

/// Overwrites the world's gravity vector (in world space, units per
/// second squared).
///
/// # Safety
/// `world` must be a live pointer returned by [`fsr_world_new`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_set_gravity(world: *mut World, x: Real, y: Real, z: Real) {
    let w = &mut *world;
    w.gravity = Vector::new(x, y, z);
}

/// Advances the simulation by exactly `dt` seconds. After the step,
/// resets every body's user-supplied force and torque so the abstract
/// API's "force applied for one step" semantics hold: callers re-apply
/// continuous forces each frame rather than seeing them accumulate
/// across steps.
///
/// # Safety
/// `world` must be a live pointer returned by [`fsr_world_new`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_step(world: *mut World, dt: Real) {
    let w = &mut *world;
    w.integration_parameters.dt = dt;
    let hooks: () = ();
    // Clear last step's collected events before this step's run.
    if let Ok(mut events) = w.collision_collector.events.lock() {
        events.clear();
    }
    w.physics_pipeline.step(
        w.gravity,
        &w.integration_parameters,
        &mut w.island_manager,
        &mut w.broad_phase,
        &mut w.narrow_phase,
        &mut w.rigid_body_set,
        &mut w.collider_set,
        &mut w.impulse_joints,
        &mut w.multibody_joints,
        &mut w.ccd_solver,
        &hooks,
        &w.collision_collector,
    );
    for (_handle, body) in w.rigid_body_set.iter_mut() {
        body.reset_forces(false);
        body.reset_torques(false);
    }
    // Move the step's events out of the collector so the Dart side can
    // read them without holding the lock. For each solid `started` event,
    // resolve its contact manifold now: the solver has run, so the per-
    // point impulses are populated. Trigger and `stopped` events carry no
    // contacts.
    w.collision_events.clear();
    w.contact_points.clear();
    if let Ok(mut collected) = w.collision_collector.events.lock() {
        for mut event in collected.drain(..) {
            if event.started == 1 && event.sensor == 0 {
                let ca = collider_from_raw(event.collider_a);
                let cb = collider_from_raw(event.collider_b);
                if let Some(pair) = w.narrow_phase.contact_pair(ca, cb) {
                    let start = w.contact_points.len() as u32;
                    // The manifold normal points from collider1 toward
                    // collider2; flip it when the pair's ordering is the
                    // reverse of this event's (A, B) so the reported normal
                    // always points from A into B.
                    let flip = pair.collider1 != ca;
                    if let Some(c1) = w.collider_set.get(pair.collider1) {
                        let pos1 = *c1.position();
                        for manifold in &pair.manifolds {
                            let mut normal = manifold.data.normal;
                            if flip {
                                normal = -normal;
                            }
                            // TODO(compound-subshape): subshape_pos1 places
                            // a compound child's contact correctly; plain
                            // colliders leave it None (identity).
                            let to_world =
                                pos1 * manifold.subshape_pos1.unwrap_or_else(Pose::identity);
                            for point in &manifold.points {
                                // local_p1 is a point in collider A's frame;
                                // rotate then translate it into world space.
                                let world =
                                    to_world.rotation * point.local_p1 + to_world.translation;
                                w.contact_points.push(FsrContactPoint {
                                    px: world.x,
                                    py: world.y,
                                    pz: world.z,
                                    nx: normal.x,
                                    ny: normal.y,
                                    nz: normal.z,
                                    impulse: point.data.impulse,
                                    separation: point.dist,
                                });
                            }
                        }
                    }
                    event.contact_start = start;
                    event.contact_count = w.contact_points.len() as u32 - start;
                }
            }
            w.collision_events.push(event);
        }
    }
}

/// Returns the number of collision events generated by the most recent
/// [`fsr_world_step`].
///
/// # Safety
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_world_collision_event_count(world: *const World) -> usize {
    (*world).collision_events.len()
}

/// Copies the i-th collision event from the most recent step into
/// `out`. Returns 0 if `index` is out of range.
///
/// # Safety
/// `world` must be live; `out` must point to a writable
/// [`FsrCollisionEvent`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_collision_event_at(
    world: *const World,
    index: usize,
    out: *mut FsrCollisionEvent,
) -> u8 {
    let w = &*world;
    let Some(event) = w.collision_events.get(index) else {
        return 0;
    };
    *out = *event;
    1
}

/// Copies the contact point at absolute `index` in the most recent
/// step's flat contact-point buffer into `out`. An event's contacts
/// occupy `[contact_start, contact_start + contact_count)`. Returns 0 if
/// `index` is out of range.
///
/// # Safety
/// `world` must be live; `out` must point to a writable
/// [`FsrContactPoint`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_contact_point_at(
    world: *const World,
    index: usize,
    out: *mut FsrContactPoint,
) -> u8 {
    let w = &*world;
    let Some(point) = w.contact_points.get(index) else {
        return 0;
    };
    *out = *point;
    1
}

/// Inserts a rigid body into the world and returns its packed handle.
/// `kind` is one of `BODY_KIND_*`. The starting pose is given as a
/// translation `(px, py, pz)` plus a unit quaternion `(qx, qy, qz, qw)`.
/// `additional_mass` adds to the body's mass beyond what its
/// colliders' densities contribute; pass `0.0` to leave the body's
/// mass entirely up to its colliders (the usual case once a collider
/// is attached).
///
/// # Safety
/// `world` must be a live pointer returned by [`fsr_world_new`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_create(
    world: *mut World,
    kind: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
    additional_mass: Real,
) -> u64 {
    let w = &mut *world;
    let translation = Vector::new(px, py, pz);
    let rotation = Rotation::from_xyzw(qx, qy, qz, qw);
    let pose = Pose::from_parts(translation, rotation);
    let mut builder = match kind {
        BODY_KIND_FIXED => RigidBodyBuilder::fixed(),
        // Position-based: the user moves the node each tick, the
        // backend pushes the new pose with set_next_kinematic_position
        // so Rapier derives a velocity that pushes dynamic bodies.
        BODY_KIND_KINEMATIC => RigidBodyBuilder::kinematic_position_based(),
        _ => RigidBodyBuilder::dynamic(),
    }
    .pose(pose);
    if additional_mass > 0.0 {
        builder = builder.additional_mass(additional_mass);
    }
    let handle = w.rigid_body_set.insert(builder);
    // The insertion path leaves effective_inv_mass at its default
    // (zero) until the first step touches the body. Recompute now so
    // an apply_impulse called before the first step actually changes
    // velocity. Same for any attached-collider mass recomputation that
    // would otherwise wait until step.
    if let Some(body) = w.rigid_body_set.get_mut(handle) {
        body.recompute_mass_properties_from_colliders(&w.collider_set);
    }
    handle_to_raw(handle)
}

/// Removes a body and any colliders attached to it from the world.
///
/// # Safety
/// `world` must be live and `raw` must be a handle previously returned
/// by [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_destroy(world: *mut World, raw: u64) {
    let w = &mut *world;
    w.rigid_body_set.remove(
        handle_from_raw(raw),
        &mut w.island_manager,
        &mut w.collider_set,
        &mut w.impulse_joints,
        &mut w.multibody_joints,
        true,
    );
}

/// Writes the body's current world-space translation into the 3-float
/// buffer at `out`. No-op when the handle is stale.
///
/// # Safety
/// `out` must point to at least three writable f32s. `world` must be
/// live.
#[no_mangle]
pub unsafe extern "C" fn fsr_body_translation(world: *const World, raw: u64, out: *mut Real) {
    let w = &*world;
    if let Some(body) = w.rigid_body_set.get(handle_from_raw(raw)) {
        let t = body.translation();
        *out.add(0) = t.x;
        *out.add(1) = t.y;
        *out.add(2) = t.z;
    }
}

/// Writes the body's current world-space rotation (unit quaternion,
/// `(x, y, z, w)` order) into the 4-float buffer at `out`.
///
/// # Safety
/// `out` must point to at least four writable f32s. `world` must be
/// live.
#[no_mangle]
pub unsafe extern "C" fn fsr_body_rotation(world: *const World, raw: u64, out: *mut Real) {
    let w = &*world;
    if let Some(body) = w.rigid_body_set.get(handle_from_raw(raw)) {
        let r = body.rotation();
        *out.add(0) = r.x;
        *out.add(1) = r.y;
        *out.add(2) = r.z;
        *out.add(3) = r.w;
    }
}

/// Attaches a sphere collider to an existing body and returns its
/// packed handle. The local pose is relative to the owning body.
///
/// # Safety
/// `world` must be live. `body_handle` must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_sphere(
    world: *mut World,
    body_handle: u64,
    radius: Real,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let translation = Vector::new(px, py, pz);
    let rotation = Rotation::from_xyzw(qx, qy, qz, qw);
    let pose = Pose::from_parts(translation, rotation);
    let builder = ColliderBuilder::ball(radius)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Attaches a cuboid (axis-aligned box) collider to an existing body.
///
/// # Safety
/// `world` must be live. `body_handle` must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_box(
    world: *mut World,
    body_handle: u64,
    hx: Real,
    hy: Real,
    hz: Real,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = ColliderBuilder::cuboid(hx, hy, hz)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Attaches a Y-axis capsule collider (cylinder segment plus two
/// hemispheres) to an existing body. `half_height` is the half length
/// of the cylindrical section, excluding the caps.
///
/// # Safety
/// `world` must be live. `body_handle` must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_capsule(
    world: *mut World,
    body_handle: u64,
    half_height: Real,
    radius: Real,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = ColliderBuilder::capsule_y(half_height, radius)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Attaches a Y-axis cylinder collider to an existing body.
/// `half_height` is half the total cylinder height.
///
/// # Safety
/// `world` must be live. `body_handle` must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_cylinder(
    world: *mut World,
    body_handle: u64,
    half_height: Real,
    radius: Real,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = ColliderBuilder::cylinder(half_height, radius)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Adds a continuous world-space force to the body for the duration of
/// the current step. When `has_world_point != 0`, the force is applied
/// at `(px, py, pz)` (creates a torque about the center of mass);
/// otherwise it acts at the center of mass.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_apply_force(
    world: *mut World,
    raw: u64,
    fx: Real,
    fy: Real,
    fz: Real,
    has_world_point: u8,
    px: Real,
    py: Real,
    pz: Real,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        let force = Vector::new(fx, fy, fz);
        if has_world_point != 0 {
            body.add_force_at_point(force, Vector::new(px, py, pz), true);
        } else {
            body.add_force(force, true);
        }
    }
}

/// Applies an instantaneous impulse (change in momentum). Same shape
/// as [`fsr_body_apply_force`].
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_apply_impulse(
    world: *mut World,
    raw: u64,
    fx: Real,
    fy: Real,
    fz: Real,
    has_world_point: u8,
    px: Real,
    py: Real,
    pz: Real,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        let impulse = Vector::new(fx, fy, fz);
        if has_world_point != 0 {
            body.apply_impulse_at_point(impulse, Vector::new(px, py, pz), true);
        } else {
            body.apply_impulse(impulse, true);
        }
    }
}

/// Adds a torque around the body's center of mass for the duration of
/// the current step.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_apply_torque(
    world: *mut World,
    raw: u64,
    tx: Real,
    ty: Real,
    tz: Real,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.add_torque(Vector::new(tx, ty, tz), true);
    }
}

/// Applies an instantaneous angular impulse (change in angular
/// momentum) around the body's center of mass.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_apply_angular_impulse(
    world: *mut World,
    raw: u64,
    tx: Real,
    ty: Real,
    tz: Real,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.apply_torque_impulse(Vector::new(tx, ty, tz), true);
    }
}

/// Writes the body's current linear velocity into `out` (3 floats).
///
/// # Safety
/// `out` must point to at least three writable f32s; `world` must be
/// live.
#[no_mangle]
pub unsafe extern "C" fn fsr_body_linear_velocity(world: *const World, raw: u64, out: *mut Real) {
    let w = &*world;
    if let Some(body) = w.rigid_body_set.get(handle_from_raw(raw)) {
        let v = body.linvel();
        *out.add(0) = v.x;
        *out.add(1) = v.y;
        *out.add(2) = v.z;
    }
}

/// Sets the next-step pose for a kinematic body. Rapier integrates
/// the displacement from the body's current pose into a velocity so
/// the body pushes dynamic bodies it contacts.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_next_kinematic_pose(
    world: *mut World,
    raw: u64,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
        body.set_next_kinematic_position(pose);
    }
}

/// Sets the body's linear velocity (world space). When `wake_up != 0`,
/// the body wakes from any sleep state.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_linear_velocity(
    world: *mut World,
    raw: u64,
    vx: Real,
    vy: Real,
    vz: Real,
    wake_up: u8,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.set_linvel(Vector::new(vx, vy, vz), wake_up != 0);
    }
}

/// Sets the body's angular velocity (world axes, radians/sec).
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_angular_velocity(
    world: *mut World,
    raw: u64,
    wx: Real,
    wy: Real,
    wz: Real,
    wake_up: u8,
) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.set_angvel(Vector::new(wx, wy, wz), wake_up != 0);
    }
}

/// Sets the body's per-step linear velocity damping factor.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_linear_damping(world: *mut World, raw: u64, damping: Real) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.set_linear_damping(damping);
    }
}

/// Sets the body's per-step angular velocity damping factor.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_angular_damping(world: *mut World, raw: u64, damping: Real) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.set_angular_damping(damping);
    }
}

/// Sets the body's additional mass (added to the mass derived from
/// the attached colliders). Triggers a mass-properties recompute so
/// subsequent impulses use the new effective mass.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_additional_mass(
    world: *mut World,
    raw: u64,
    additional_mass: Real,
) {
    let w = &mut *world;
    let bodies = &mut w.rigid_body_set;
    let colliders = &w.collider_set;
    if let Some(body) = bodies.get_mut(handle_from_raw(raw)) {
        body.set_additional_mass(additional_mass, true);
        body.recompute_mass_properties_from_colliders(colliders);
    }
}

/// Locks or unlocks the body's translation and rotation axes. `locks`
/// is a bitfield matching the constants on the Dart side:
///   bit 0 = X translation, bit 1 = Y, bit 2 = Z,
///   bit 3 = X rotation,    bit 4 = Y, bit 5 = Z.
/// A set bit means that degree of freedom is locked.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_locked_axes(world: *mut World, raw: u64, locks: u8) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        let mut la = LockedAxes::empty();
        if locks & 0b000_001 != 0 {
            la |= LockedAxes::TRANSLATION_LOCKED_X;
        }
        if locks & 0b000_010 != 0 {
            la |= LockedAxes::TRANSLATION_LOCKED_Y;
        }
        if locks & 0b000_100 != 0 {
            la |= LockedAxes::TRANSLATION_LOCKED_Z;
        }
        if locks & 0b001_000 != 0 {
            la |= LockedAxes::ROTATION_LOCKED_X;
        }
        if locks & 0b010_000 != 0 {
            la |= LockedAxes::ROTATION_LOCKED_Y;
        }
        if locks & 0b100_000 != 0 {
            la |= LockedAxes::ROTATION_LOCKED_Z;
        }
        body.set_locked_axes(la, true);
    }
}

/// Sets the body's per-step gravity scale (1.0 = full, 0.0 = no
/// gravity). Used to wire the abstract `useGravity` flag.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_gravity_scale(world: *mut World, raw: u64, scale: Real) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.set_gravity_scale(scale, true);
    }
}

/// Enables or disables continuous collision detection on the body.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_set_ccd_enabled(world: *mut World, raw: u64, enabled: u8) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.enable_ccd(enabled != 0);
    }
}

/// Wakes a sleeping body. No-op for non-dynamic bodies.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_wake_up(world: *mut World, raw: u64) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.wake_up(true);
    }
}

/// Puts a body to sleep immediately.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_sleep(world: *mut World, raw: u64) {
    let w = &mut *world;
    if let Some(body) = w.rigid_body_set.get_mut(handle_from_raw(raw)) {
        body.sleep();
    }
}

/// Returns 1 when the body is currently sleeping, 0 otherwise. Returns
/// 0 for stale handles.
///
/// # Safety
/// `world` must be live; `raw` must come from [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_body_is_sleeping(world: *const World, raw: u64) -> u8 {
    let w = &*world;
    if let Some(body) = w.rigid_body_set.get(handle_from_raw(raw)) {
        body.is_sleeping() as u8
    } else {
        0
    }
}

/// Writes the body's current angular velocity (radians/sec, world axes)
/// into `out` (3 floats).
///
/// # Safety
/// `out` must point to at least three writable f32s; `world` must be
/// live.
#[no_mangle]
pub unsafe extern "C" fn fsr_body_angular_velocity(world: *const World, raw: u64, out: *mut Real) {
    let w = &*world;
    if let Some(body) = w.rigid_body_set.get(handle_from_raw(raw)) {
        let v = body.angvel();
        *out.add(0) = v.x;
        *out.add(1) = v.y;
        *out.add(2) = v.z;
    }
}

/// Attaches a convex hull collider built from `point_count` points
/// (packed `xyz` floats). Returns `u64::MAX` when Rapier could not
/// compute a valid hull from the input.
///
/// # Safety
/// `points` must point to at least `point_count * 3` readable `Real`s;
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_convex_hull(
    world: *mut World,
    body_handle: u64,
    points: *const Real,
    point_count: usize,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let pts: Vec<Vector> = (0..point_count)
        .map(|i| {
            Vector::new(
                *points.add(i * 3),
                *points.add(i * 3 + 1),
                *points.add(i * 3 + 2),
            )
        })
        .collect();
    let Some(builder) = ColliderBuilder::convex_hull(&pts) else {
        return u64::MAX;
    };
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = builder
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Attaches a triangle mesh collider. Vertices are packed `xyz`
/// floats; indices are packed `u32` triples per triangle. Returns
/// `u64::MAX` when Rapier rejects the mesh.
///
/// # Safety
/// `vertices` must point to at least `vertex_count * 3` readable
/// `Real`s. `indices` must point to at least `triangle_count * 3`
/// readable `u32`s. `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_trimesh(
    world: *mut World,
    body_handle: u64,
    vertices: *const Real,
    vertex_count: usize,
    indices: *const u32,
    triangle_count: usize,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let verts: Vec<Vector> = (0..vertex_count)
        .map(|i| {
            Vector::new(
                *vertices.add(i * 3),
                *vertices.add(i * 3 + 1),
                *vertices.add(i * 3 + 2),
            )
        })
        .collect();
    let tris: Vec<[u32; 3]> = (0..triangle_count)
        .map(|i| {
            [
                *indices.add(i * 3),
                *indices.add(i * 3 + 1),
                *indices.add(i * 3 + 2),
            ]
        })
        .collect();
    let Ok(builder) = ColliderBuilder::trimesh(verts, tris) else {
        return u64::MAX;
    };
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = builder
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Attaches a heightfield collider. `nrows` is the number of samples
/// along Z, `ncols` is the number of samples along X. `heights` is
/// row-major: `heights[z * ncols + x]` is the Y value at column `x`
/// row `z`. The XZ extent is `(ncols-1) * scale_x` by
/// `(nrows-1) * scale_z`, centered on the origin.
///
/// # Safety
/// `heights` must point to at least `nrows * ncols` readable `Real`s;
/// `world` must be live.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_heightfield(
    world: *mut World,
    body_handle: u64,
    nrows: u32,
    ncols: u32,
    heights: *const Real,
    scale_x: Real,
    scale_y: Real,
    scale_z: Real,
    friction: Real,
    restitution: Real,
    density: Real,
    is_sensor: u8,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) -> u64 {
    let w = &mut *world;
    let n_rows = nrows as usize;
    let n_cols = ncols as usize;
    // Parry's Array2 is column-major (data[row + col * nrows]) while
    // our input is row-major. Transpose into a fresh Vec.
    let mut data: Vec<Real> = vec![0.0; n_rows * n_cols];
    for z in 0..n_rows {
        for x in 0..n_cols {
            data[z + x * n_rows] = *heights.add(z * n_cols + x);
        }
    }
    let array = Array2::new(n_rows, n_cols, data);
    let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
    let builder = ColliderBuilder::heightfield(array, Vector::new(scale_x, scale_y, scale_z))
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .active_events(ActiveEvents::COLLISION_EVENTS)
        .active_collision_types(ActiveCollisionTypes::all())
        .position(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
}

/// Updates a collider's friction, restitution, and density (mass
/// recomputed lazily).
///
/// # Safety
/// `world` must be live; `raw` must be a live collider handle.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_set_material(
    world: *mut World,
    raw: u64,
    friction: Real,
    restitution: Real,
    density: Real,
) {
    let w = &mut *world;
    if let Some(c) = w.collider_set.get_mut(collider_from_raw(raw)) {
        c.set_friction(friction);
        c.set_restitution(restitution);
        c.set_density(density);
    }
}

/// Sets the collider's collision membership and filter as `u32`
/// bitmasks. A pair interacts when each side's membership intersects
/// the other side's filter.
///
/// # Safety
/// `world` must be live; `raw` must be a live collider handle.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_set_collision_groups(
    world: *mut World,
    raw: u64,
    memberships: u32,
    filter: u32,
) {
    let w = &mut *world;
    if let Some(c) = w.collider_set.get_mut(collider_from_raw(raw)) {
        c.set_collision_groups(InteractionGroups::new(
            Group::from(memberships),
            Group::from(filter),
            InteractionTestMode::And,
        ));
    }
}

/// Flips the collider between solid (responds to contacts) and sensor
/// (overlaps without contact response, fires events instead).
///
/// # Safety
/// `world` must be live; `raw` must be a live collider handle.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_set_sensor(world: *mut World, raw: u64, is_sensor: u8) {
    let w = &mut *world;
    if let Some(c) = w.collider_set.get_mut(collider_from_raw(raw)) {
        c.set_sensor(is_sensor != 0);
    }
}

/// Updates the collider's pose relative to its parent body.
///
/// # Safety
/// `world` must be live; `raw` must be a live collider handle.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_set_local_pose(
    world: *mut World,
    raw: u64,
    px: Real,
    py: Real,
    pz: Real,
    qx: Real,
    qy: Real,
    qz: Real,
    qw: Real,
) {
    let w = &mut *world;
    if let Some(c) = w.collider_set.get_mut(collider_from_raw(raw)) {
        let pose = Pose::from_parts(Vector::new(px, py, pz), Rotation::from_xyzw(qx, qy, qz, qw));
        c.set_position_wrt_parent(pose);
    }
}

/// Removes a collider from the world.
///
/// # Safety
/// `world` must be live. `raw` must be a handle previously returned by
/// one of the `fsr_collider_*` constructors.
#[no_mangle]
pub unsafe extern "C" fn fsr_collider_destroy(world: *mut World, raw: u64) {
    let w = &mut *world;
    w.collider_set.remove(
        collider_from_raw(raw),
        &mut w.island_manager,
        &mut w.rigid_body_set,
        true,
    );
}

fn joint_handle_to_raw(h: ImpulseJointHandle) -> u64 {
    index_to_raw(h.0)
}

fn joint_handle_from_raw(raw: u64) -> ImpulseJointHandle {
    ImpulseJointHandle(index_from_raw(raw))
}

/// Inserts a fixed joint welding two bodies together at the given local
/// anchors. Returns the packed joint handle.
///
/// # Safety
/// `world` must be live; both body handles must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_joint_fixed(
    world: *mut World,
    body_a: u64,
    body_b: u64,
    ax: Real,
    ay: Real,
    az: Real,
    bx: Real,
    by: Real,
    bz: Real,
    collisions_enabled: u8,
) -> u64 {
    let w = &mut *world;
    let mut joint = FixedJointBuilder::new()
        .local_anchor1(Vector::new(ax, ay, az))
        .local_anchor2(Vector::new(bx, by, bz))
        .build();
    joint.set_contacts_enabled(collisions_enabled != 0);
    let handle = w.impulse_joints.insert(
        handle_from_raw(body_a),
        handle_from_raw(body_b),
        joint,
        true,
    );
    joint_handle_to_raw(handle)
}

/// Inserts a spherical (ball-and-socket) joint.
///
/// # Safety
/// `world` must be live; both body handles must come from
/// [`fsr_body_create`].
#[no_mangle]
pub unsafe extern "C" fn fsr_joint_spherical(
    world: *mut World,
    body_a: u64,
    body_b: u64,
    ax: Real,
    ay: Real,
    az: Real,
    bx: Real,
    by: Real,
    bz: Real,
    collisions_enabled: u8,
) -> u64 {
    let w = &mut *world;
    let mut joint = SphericalJointBuilder::new()
        .local_anchor1(Vector::new(ax, ay, az))
        .local_anchor2(Vector::new(bx, by, bz))
        .build();
    joint.set_contacts_enabled(collisions_enabled != 0);
    let handle = w.impulse_joints.insert(
        handle_from_raw(body_a),
        handle_from_raw(body_b),
        joint,
        true,
    );
    joint_handle_to_raw(handle)
}

/// Inserts a revolute (hinge) joint about a shared axis, with optional
/// angular limits and a velocity motor.
///
/// # Safety
/// `world` must be live; both body handles must come from
/// [`fsr_body_create`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn fsr_joint_revolute(
    world: *mut World,
    body_a: u64,
    body_b: u64,
    axis_x: Real,
    axis_y: Real,
    axis_z: Real,
    ax: Real,
    ay: Real,
    az: Real,
    bx: Real,
    by: Real,
    bz: Real,
    has_limits: u8,
    lower: Real,
    upper: Real,
    has_motor: u8,
    motor_target_velocity: Real,
    motor_max_force: Real,
    collisions_enabled: u8,
) -> u64 {
    let w = &mut *world;
    let mut builder = RevoluteJointBuilder::new(Vector::new(axis_x, axis_y, axis_z))
        .local_anchor1(Vector::new(ax, ay, az))
        .local_anchor2(Vector::new(bx, by, bz));
    if has_limits != 0 {
        builder = builder.limits([lower, upper]);
    }
    if has_motor != 0 {
        builder = builder
            .motor_velocity(motor_target_velocity, 1.0e4)
            .motor_max_force(motor_max_force);
    }
    let mut joint = builder.build();
    joint.set_contacts_enabled(collisions_enabled != 0);
    let handle = w.impulse_joints.insert(
        handle_from_raw(body_a),
        handle_from_raw(body_b),
        joint,
        true,
    );
    joint_handle_to_raw(handle)
}

/// Inserts a prismatic (slider) joint along a shared axis, with optional
/// linear limits and a velocity motor.
///
/// # Safety
/// `world` must be live; both body handles must come from
/// [`fsr_body_create`].
#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn fsr_joint_prismatic(
    world: *mut World,
    body_a: u64,
    body_b: u64,
    axis_x: Real,
    axis_y: Real,
    axis_z: Real,
    ax: Real,
    ay: Real,
    az: Real,
    bx: Real,
    by: Real,
    bz: Real,
    has_limits: u8,
    lower: Real,
    upper: Real,
    has_motor: u8,
    motor_target_velocity: Real,
    motor_max_force: Real,
    collisions_enabled: u8,
) -> u64 {
    let w = &mut *world;
    let mut builder = PrismaticJointBuilder::new(Vector::new(axis_x, axis_y, axis_z))
        .local_anchor1(Vector::new(ax, ay, az))
        .local_anchor2(Vector::new(bx, by, bz));
    if has_limits != 0 {
        builder = builder.limits([lower, upper]);
    }
    if has_motor != 0 {
        builder = builder
            .motor_velocity(motor_target_velocity, 1.0e4)
            .motor_max_force(motor_max_force);
    }
    let mut joint = builder.build();
    joint.set_contacts_enabled(collisions_enabled != 0);
    let handle = w.impulse_joints.insert(
        handle_from_raw(body_a),
        handle_from_raw(body_b),
        joint,
        true,
    );
    joint_handle_to_raw(handle)
}

/// Removes a joint previously inserted by one of the `fsr_joint_*`
/// constructors.
///
/// # Safety
/// `world` must be live; `raw` must be a live joint handle.
#[no_mangle]
pub unsafe extern "C" fn fsr_joint_destroy(world: *mut World, raw: u64) {
    let w = &mut *world;
    w.impulse_joints.remove(joint_handle_from_raw(raw), true);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn world_steps_without_panicking() {
        unsafe {
            let world = fsr_world_new();
            fsr_world_set_gravity(world, 0.0, -9.81, 0.0);
            for _ in 0..16 {
                fsr_world_step(world, 1.0 / 60.0);
            }
            fsr_world_destroy(world);
        }
    }

    #[test]
    fn proof_of_life_returns_sentinel() {
        assert_eq!(fsr_proof_of_life(), 42);
    }

    #[test]
    fn dynamic_body_falls_under_gravity() {
        unsafe {
            let world = fsr_world_new();
            fsr_world_set_gravity(world, 0.0, -9.81, 0.0);
            let body = fsr_body_create(
                world,
                BODY_KIND_DYNAMIC,
                0.0,
                10.0,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                1.0,
            );
            for _ in 0..60 {
                fsr_world_step(world, 1.0 / 60.0);
            }
            let mut t = [0.0f32; 3];
            fsr_body_translation(world, body, t.as_mut_ptr());
            assert!(t[1] < 9.0, "body should have fallen, y = {}", t[1]);
            fsr_body_destroy(world, body);
            fsr_world_destroy(world);
        }
    }

    #[test]
    fn sphere_on_box_floor_settles() {
        unsafe {
            let world = fsr_world_new();
            fsr_world_set_gravity(world, 0.0, -9.81, 0.0);

            // Static box floor: 50x0.5x50 centered just below the origin.
            let floor = fsr_body_create(
                world,
                BODY_KIND_FIXED,
                0.0,
                -0.5,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            );
            fsr_collider_box(
                world, floor, 50.0, 0.5, 50.0, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
            );

            let ball = fsr_body_create(
                world,
                BODY_KIND_DYNAMIC,
                0.0,
                5.0,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            );
            fsr_collider_sphere(
                world, ball, 0.5, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
            );

            for _ in 0..240 {
                fsr_world_step(world, 1.0 / 60.0);
            }

            let mut t = [0.0f32; 3];
            fsr_body_translation(world, ball, t.as_mut_ptr());
            // Floor top is at y=0; ball of radius 0.5 settles at y ≈ 0.5.
            assert!(
                t[1] > 0.4 && t[1] < 0.7,
                "ball should rest near y=0.5, got {}",
                t[1]
            );
            fsr_world_destroy(world);
        }
    }

    #[test]
    fn sphere_on_floor_settles() {
        unsafe {
            let world = fsr_world_new();
            fsr_world_set_gravity(world, 0.0, -9.81, 0.0);

            // Static floor (large box collider on a fixed body, but
            // since this commit only ships sphere cooking, use a very
            // wide sphere as a stand-in floor).
            let floor_body = fsr_body_create(
                world,
                BODY_KIND_FIXED,
                0.0,
                -100.0,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            );
            fsr_collider_sphere(
                world, floor_body, 100.0, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
            );

            // Dynamic sphere above the floor.
            let ball_body = fsr_body_create(
                world,
                BODY_KIND_DYNAMIC,
                0.0,
                5.0,
                0.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            );
            fsr_collider_sphere(
                world, ball_body, 0.5, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0,
            );

            for _ in 0..240 {
                fsr_world_step(world, 1.0 / 60.0);
            }

            let mut t = [0.0f32; 3];
            fsr_body_translation(world, ball_body, t.as_mut_ptr());
            // Ball at radius 0.5 resting on a sphere of radius 100
            // centered at y=-100 sits at y ≈ 0.5.
            assert!(
                t[1] > 0.0 && t[1] < 1.0,
                "ball should rest near y=0.5, got {}",
                t[1]
            );
            fsr_world_destroy(world);
        }
    }

    #[test]
    fn fixed_body_does_not_move() {
        unsafe {
            let world = fsr_world_new();
            fsr_world_set_gravity(world, 0.0, -9.81, 0.0);
            let body = fsr_body_create(
                world,
                BODY_KIND_FIXED,
                1.0,
                2.0,
                3.0,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            );
            for _ in 0..60 {
                fsr_world_step(world, 1.0 / 60.0);
            }
            let mut t = [0.0f32; 3];
            fsr_body_translation(world, body, t.as_mut_ptr());
            assert!((t[1] - 2.0).abs() < 1e-5, "fixed body should not move");
            fsr_world_destroy(world);
        }
    }
}
