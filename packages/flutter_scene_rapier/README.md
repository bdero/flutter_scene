# flutter_scene_rapier

A [Rapier 3D](https://rapier.rs/) physics backend for
[flutter_scene](https://pub.dev/packages/flutter_scene). It implements the
abstract physics contract from `flutter_scene` (rigid bodies, colliders,
joints, queries, and collision events) against the Rapier engine over
`dart:ffi`, with a WebAssembly backend for the web.

> **Status: experimental.** This package requires the Flutter **master**
> channel (it builds on Flutter GPU / Impeller, which are not on stable),
> and it relies on the still-evolving Dart native-assets build hooks. The
> API may change between releases.

## Requirements

- Flutter **master** channel.
- No Rust toolchain for the supported platforms below: the build hook
  downloads a precompiled library for your target and verifies its
  checksum. Exotic targets fall back to building from source, which does
  require [Rust](https://rustup.rs/).

## Platform support

| Platform | Prebuilt binary | Notes |
| --- | --- | --- |
| Android (arm64, armv7, x64) | yes | |
| iOS (arm64 device + arm64 sim) | yes | x86_64 simulator builds from source |
| macOS (Apple Silicon) | yes | Intel builds from source |
| Linux (x64, arm64) | yes | |
| Windows (x64) | yes | |
| Web | yes | loads a WebAssembly module at runtime |

## Install

```yaml
dependencies:
  flutter_scene: ^0.16.0
  flutter_scene_rapier: ^0.1.0
```

## Quick start

Add a `RapierWorld` to the scene root, then attach a `RapierRigidBody` and
a `RapierCollider` to the nodes you want simulated (the body must be added
before the collider). The scene advances physics on a fixed timestep and
interpolates transforms for you.

```dart
import 'package:flutter_scene/scene.dart' hide Material; // see note below
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart';

final scene = Scene();
final world = RapierWorld(gravity: Vector3(0, -9.81, 0));
scene.root.addComponent(world);

// A static floor.
final floor = Node(localTransform: Matrix4.translation(Vector3(0, -0.5, 0)));
floor.addComponent(RapierRigidBody(type: BodyType.fixed));
floor.addComponent(RapierCollider(shape: BoxShape(halfExtents: Vector3(10, 0.5, 10))));
scene.add(floor);

// A falling dynamic box.
final box = Node(localTransform: Matrix4.translation(Vector3(0, 5, 0)));
box.addComponent(RapierRigidBody(type: BodyType.dynamic_, mass: 1));
box.addComponent(RapierCollider(shape: BoxShape(halfExtents: Vector3.all(0.5))));
scene.add(box);

// React to contacts and triggers.
world.collisions.listen((event) {
  // CollisionBegan / CollisionEnded / TriggerEntered / TriggerExited
});
```

Each frame, advance and render the scene:

```dart
scene.update(deltaSeconds); // steps physics + interpolates
scene.render(camera, canvas, viewport: Offset.zero & size);
```

Beyond rigid bodies and colliders, the package provides joints
(`RapierFixedJoint`, `RapierSphericalJoint`, `RapierRevoluteJoint`,
`RapierPrismaticJoint`, `RapierGenericJoint`, with limits and motors), a
kinematic character controller
(`RapierKinematicCharacterController.move`), and scene queries
(`world.raycast`, `world.shapeCast`, `world.overlapSphere`,
`world.overlapBox`). See the `example/` app for a full playground.

> **Name clashes:** `flutter_scene`'s physics `BoxShape` collides with
> Flutter's painting `BoxShape`, and its `Material` with the Flutter
> `Material` widget. In files that use both, hide the one you do not need,
> e.g. `import 'package:flutter/material.dart' hide BoxShape;` and
> `import 'package:flutter_scene/scene.dart' hide Material;`.

## Web

On the web, the package loads a WebAssembly build of the physics shim at
runtime (Flutter GPU / `dart:ffi` do not exist there; flutter_scene runs
on a WebGL2 backend). The module for each release is fetched from a
CORS-enabled host. To run against a locally built module during
development, serve it and point the loader at it:

```sh
flutter run -d chrome \
  --dart-define=FLUTTER_SCENE_RAPIER_WASM_URL=/flutter_scene_rapier_native.wasm
```

## Contributing / building from source

The native shim lives in `native/` (Rust). To build it locally instead of
downloading a prebuilt binary (required when you edit `native/src`), set:

```sh
FLUTTER_SCENE_RAPIER_BUILD_FROM_SOURCE=1
```

This needs a Rust toolchain (`rustup`). For web, build the wasm with
`cargo build --release --target wasm32-unknown-unknown` and optimize it
with `wasm-opt -Oz`.

## License

MIT (see `LICENSE`). The distributed binaries statically link Rapier and
other Rust crates under their own permissive licenses; see
`THIRD_PARTY_NOTICES.md`.
