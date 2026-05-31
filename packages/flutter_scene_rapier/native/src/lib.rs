//! Flutter Scene Rapier native shim.
//!
//! Stage 3 scaffold. Depends on rapier3d and exposes a tiny C ABI so
//! the Flutter side can verify linkage and call into the library
//! without crashing. The full body, collider, query, and event
//! bindings land in subsequent stages.
//!
//! All symbols here are placeholders that go away when the real
//! bindings land. They exist so that the build hook has something
//! concrete to link against during the scaffold stage.

use rapier3d::math::Vector;
use std::os::raw::c_int;

/// Returns a sentinel value (42) the Dart side can call as a smoke
/// test that the dynamic library loaded and the C ABI works.
#[no_mangle]
pub extern "C" fn fsr_proof_of_life() -> c_int {
    42
}

/// Returns the magnitude of Earth-like gravity, computed through
/// rapier3d's vector type. Forces rapier3d symbols into the link so
/// the dependency cannot be optimized out of the scaffold build.
#[no_mangle]
pub extern "C" fn fsr_default_gravity_magnitude() -> f32 {
    let g: Vector = Vector::new(0.0, -9.81, 0.0);
    g.length()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn proof_of_life_returns_sentinel() {
        assert_eq!(fsr_proof_of_life(), 42);
    }

    #[test]
    fn gravity_magnitude_matches_constant() {
        assert!((fsr_default_gravity_magnitude() - 9.81).abs() < 1e-5);
    }
}
