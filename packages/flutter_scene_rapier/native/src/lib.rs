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

fn handle_to_raw(h: RigidBodyHandle) -> u64 {
    let (idx, gen) = h.0.into_raw_parts();
    ((gen as u64) << 32) | (idx as u64)
}

fn handle_from_raw(raw: u64) -> RigidBodyHandle {
    let idx = raw as u32;
    let gen = (raw >> 32) as u32;
    RigidBodyHandle(rapier3d::data::arena::Index::from_raw_parts(idx, gen))
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
