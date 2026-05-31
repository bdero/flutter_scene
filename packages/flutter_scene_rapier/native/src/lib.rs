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
}
