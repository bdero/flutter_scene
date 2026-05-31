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

@Native<Void Function(Pointer<NativeWorld>, Uint64)>(
  symbol: 'fsr_collider_destroy',
)
external void colliderDestroy(Pointer<NativeWorld> world, int handle);
