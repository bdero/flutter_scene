// Stage 3 FFI binding stubs for flutter_scene_rapier.
//
// Only the two proof-of-life symbols from native/src/lib.rs are bound
// here. The full body, collider, query, and event bindings land in
// later stages alongside the matching Rust functions.

@DefaultAsset('package:flutter_scene_rapier/flutter_scene_rapier_native')
library;

import 'dart:ffi';

/// Returns the sentinel value (42) hardcoded in the native shim.
///
/// Test hook for verifying that the dynamic library is bundled with
/// the host app, that the loader can resolve `fsr_proof_of_life`, and
/// that the C ABI is wired up correctly.
@Native<Int Function()>(symbol: 'fsr_proof_of_life')
external int proofOfLife();

/// Returns the magnitude of Earth-like gravity, computed via
/// `rapier3d::math::Vector`. Verifies that rapier3d's symbols are
/// reachable from the linked library.
@Native<Float Function()>(symbol: 'fsr_default_gravity_magnitude')
external double defaultGravityMagnitude();
