//! Flutter Scene Rapier native shim.
//!
//! Owns the Rapier PhysicsPipeline state behind opaque pointers and
//! exposes a small C ABI for the Dart bindings. All operations on the
//! world go through this surface; the Dart side never sees Rapier's
//! Rust types directly.

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
        }
    }
}

/// Sentinel returned by the proof-of-life entry point. The Dart side
/// can call it to verify the dynamic library loaded.
#[no_mangle]
pub extern "C" fn fsr_proof_of_life() -> c_int {
    42
}

/// Body kinds matching the abstract `BodyType` on the Dart side.
const BODY_KIND_FIXED: u8 = 0;
const BODY_KIND_KINEMATIC: u8 = 1;
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
pub unsafe extern "C" fn fsr_world_set_gravity(
    world: *mut World,
    x: Real,
    y: Real,
    z: Real,
) {
    let w = &mut *world;
    w.gravity = Vector::new(x, y, z);
}

/// Advances the simulation by exactly `dt` seconds.
///
/// # Safety
/// `world` must be a live pointer returned by [`fsr_world_new`].
#[no_mangle]
pub unsafe extern "C" fn fsr_world_step(world: *mut World, dt: Real) {
    let w = &mut *world;
    w.integration_parameters.dt = dt;
    let hooks: () = ();
    let events: () = ();
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
        &events,
    );
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
        BODY_KIND_KINEMATIC => RigidBodyBuilder::kinematic_velocity_based(),
        _ => RigidBodyBuilder::dynamic(),
    }
    .pose(pose);
    if additional_mass > 0.0 {
        builder = builder.additional_mass(additional_mass);
    }
    let handle = w.rigid_body_set.insert(builder);
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
pub unsafe extern "C" fn fsr_body_translation(
    world: *const World,
    raw: u64,
    out: *mut Real,
) {
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
pub unsafe extern "C" fn fsr_body_rotation(
    world: *const World,
    raw: u64,
    out: *mut Real,
) {
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
        .position_wrt_parent(pose);
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
    let pose = Pose::from_parts(
        Vector::new(px, py, pz),
        Rotation::from_xyzw(qx, qy, qz, qw),
    );
    let builder = ColliderBuilder::cuboid(hx, hy, hz)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .position_wrt_parent(pose);
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
    let pose = Pose::from_parts(
        Vector::new(px, py, pz),
        Rotation::from_xyzw(qx, qy, qz, qw),
    );
    let builder = ColliderBuilder::capsule_y(half_height, radius)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .position_wrt_parent(pose);
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
    let pose = Pose::from_parts(
        Vector::new(px, py, pz),
        Rotation::from_xyzw(qx, qy, qz, qw),
    );
    let builder = ColliderBuilder::cylinder(half_height, radius)
        .friction(friction)
        .restitution(restitution)
        .density(density)
        .sensor(is_sensor != 0)
        .position_wrt_parent(pose);
    let handle = w.collider_set.insert_with_parent(
        builder,
        handle_from_raw(body_handle),
        &mut w.rigid_body_set,
    );
    collider_to_raw(handle)
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
                world, BODY_KIND_FIXED, 0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 1.0,
                0.0,
            );
            fsr_collider_box(
                world, floor, 50.0, 0.5, 50.0, 0.5, 0.0, 1.0, 0, 0.0, 0.0,
                0.0, 0.0, 0.0, 0.0, 1.0,
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
                world, ball, 0.5, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0, 0.0,
                0.0, 1.0,
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
                world, BODY_KIND_FIXED, 0.0, -100.0, 0.0, 0.0, 0.0, 0.0, 1.0,
                0.0,
            );
            fsr_collider_sphere(
                world, floor_body, 100.0, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0,
                0.0, 0.0, 0.0, 1.0,
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
                world, ball_body, 0.5, 0.5, 0.0, 1.0, 0, 0.0, 0.0, 0.0, 0.0,
                0.0, 0.0, 1.0,
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
