# Using flutter_scene

This repository is the **flutter_scene** realtime 3D engine for Flutter, plus the packages built around it. This file orients coding agents, and the people directing them, toward using these packages correctly. It is about *using* the engine, not developing it.

flutter_scene diverges from three.js, Godot, and Unity in specific ways, and most first-attempt failures come from reaching for another engine's spelling. The rules below are the ones that are always true and expensive to get wrong. For deep, on-demand guidance, install the agent skill this repo ships (see "The agent skill"). For prose docs and live demos, see https://fscene.dev.

## The packages

The ecosystem is organized around `scene`, an engine-agnostic contract. Rendering lives in `flutter_scene`; physics and audio are pluggable backends.

| Package | What it is |
| --- | --- |
| `flutter_scene` | The engine. Rendering, geometry, materials, lighting, animation, the `.fscene` asset format, and a deep post-processing stack. Depends on `scene`. |
| `scene` | The engine-agnostic contract (physics and shared types) that the renderer and the backends share. Pure Dart, no Flutter. |
| `flutter_scene_rapier` | Physics backend over Rapier (prebuilt native binaries plus a wasm module). Implements `package:scene/physics.dart`. |
| `flutter_scene_box3d` | Physics backend over box3d. Also implements the `scene` physics contract. |
| `flutter_scene_net` | Networking: replication, client-side prediction, and reconciliation. |
| `flutter_scene_fmod` | Audio backend over FMOD (needs a user-supplied FMOD SDK). |
| `flutter_scene_soloud` | Audio backend over SoLoud (via `flutter_soloud`). |
| `flutter_scene_editor`, `flutter_scene_mcp` | The Flutter Scene Editor, a distributed desktop application (not a pub.dev library, you run it rather than depend on it), and its MCP server for agent-driven editing. In active development. |

Because the physics backends depend on `scene` rather than `flutter_scene`, they are version-independent from the renderer: a `flutter_scene` release does not force a rapier or box3d release. Pick one physics backend and one audio backend as needed; do not add both of a kind.

## Setup

```sh
flutter pub add flutter_scene
dart run flutter_scene:init      # required: installs the build hook and asset setup
flutter run --enable-flutter-gpu # native; add -d chrome for web
```

flutter_scene needs **Flutter 3.47 stable or newer**. Rendering is gated on `Scene.initializeStaticResources()`; until it completes the engine prints "Flutter Scene is not ready to render. Skipping frame", so build geometry and materials only after it resolves.

## Do not reach for these

They do not exist here, or they break the build.

- **Not the master channel.** 3.47 stable works; `flutter channel master` resolves worse, not better.
- **Not `--enable-impeller`, not `--enable-experiment=native-assets`.** The run flag is `--enable-flutter-gpu` alone. The native-assets experiment breaks the build on Dart 3.10+.
- **Not `package:vector_math/vector_math_64.dart`.** Use `package:vector_math/vector_math.dart`. The `_64` `Vector3` is a different, incompatible type.
- **Not `Node.fromAsset(...)` or `loadModel(...)`.** Load a preprocessed model with `loadScene('assets/x.glb')` (returns `Future<Node>`), or a runtime glTF with `Node.fromGlbAsset`/`Node.fromGlbBytes`.
- **Not a hand-rolled `CustomPainter` + `Ticker`.** Display a scene with the `SceneView` widget.
- **Not `node.position.set(...)`.** `Node` has `position`, `rotation` (a `Quaternion`), and `scale`, but they are whole-value get/set (`node.position = Vector3(0, 1, 0)`); the getters return copies. For a raw matrix edit use `node.mutateLocalTransform((m) => ...)`, not a bare in-place edit of `node.localTransform`.
- **Not the removed `Environment` class.** Environment lighting is `EnvironmentMap` on `Scene.environment`; unset means a default studio map, `EnvironmentMap.empty()` means none.

## It has more than you expect

Cold assumptions undersell the engine. Before hand-rolling any of these, know they exist: **directional, point, spot, and area lights, shadows (PCSS and contact shadows), GTAO ambient occlusion, screen-space reflections, SSGI, depth of field, god rays, fog, auto exposure, LUT color grading, bloom, anti-aliasing, tone mapping, instancing, and LOD**, plus ten built-in primitive geometries and `GeometryBuilder` for custom meshes. Custom `ShaderMaterial` output is linear HDR premultiplied by alpha; the engine applies exposure, tone mapping, and the display transform afterward.

The same is true above the renderer. Do not hand-roll a camera, a grid, or click-to-move:

- **Cameras.** `OrbitCameraController`, `FlyCameraController`, `FollowCameraController` (with wall-collision retraction), `FirstPersonCameraController` (head bob, additive recoil), `RtsCameraController` (plus `.isometric()` and `.topDown()`, edge scrolling, terrain follow, map bounds), and `DollyCameraController` riding an arc-length-parameterized `CameraPath`. Both lenses exist: `PerspectiveProjection` and `OrthographicProjection`.
- **Cinematics.** Every controller produces a `CameraPose`, and a `CameraDirector` blends between them by priority or by an explicit `blendTo`, so a cut from one camera to another is one call. `CameraSequence` plays a shot list through it. `CameraRig.firstPerson(...)`, `.thirdPerson(...)`, `.isometric(...)` and the rest assemble node, camera, director, and controller in one call.
- **Grids.** `package:flutter_scene/grid.dart`: `SquareGrid` and `HexGrid` (axial coordinates), `GridMap` for per-cell state, `findGridPath` for A* over your own cost function, `GridPicking` to turn a click into a cell, and `GridTileLayer` to draw a tile map as one instanced batch. Isometric is a camera, not a tiling: use a `SquareGrid`.
- **Pointer and selection.** `ScenePicker` resolves a click to the *object* rather than the mesh under the cursor, and does marquee selection; `SceneSelection` holds what is selected; `PathFollowerComponent` walks a route from either pathfinder, moving a node itself or steering a character controller. `PointerLock` captures the mouse for first-person look (web only — check `isSupported`).

## The agent skills

This repo ships a set of on-demand skills under `packages/flutter_scene/skills/`, each loaded by a coding assistant when its topic comes up:

- `flutter_scene-idioms` correct usage and the traps that fail silently (the depth behind this file).
- `flutter_scene-verification-loop` the closed run-settle-capture-correct loop for seeing your own output.
- `flutter_scene-looks` copy-paste presets that make a scene look deliberate (lighting plus post).
- `flutter_scene-procedural` building content from code (terrain, noise, instancing) instead of asset files.
- `flutter_scene-performance` hitting frame budget (measure which thread is over, then a fixed remediation order).

Install them into a project:

```sh
dart run flutter_scene:skills          # install or update every bundled skill
dart run flutter_scene:skills --check  # report whether newer skills ship
```

`dart run flutter_scene:init` also offers to install them. They also install through the standard Dart skills tool, which discovers them from your dependency tree along with any other package's skills:

```sh
dart run skills@ get   # install skills shipped by your dependencies
```

Either path installs the same skills.

## Running things in this repo

- `examples/flutter_app` is the example app (many examples). It commits no platform scaffolding, so generate the platform you want first (`cd examples/flutter_app && flutter create . --platforms=macos --org dev.bdero --project-name example_app`), then `flutter run -d macos --enable-flutter-gpu`.
- `examples/smoke_render` is a headless cross-backend render harness and commits its scaffolding, so it runs straight from a checkout.
- `apps/flutter_scene_editor_app` is the standalone editor. It commits its platform scaffolding, so it runs straight from a checkout: `cd apps/flutter_scene_editor_app && flutter run -d macos --enable-flutter-gpu`. Working on the master channel needs one patch first; see the app's README.

## Where to look

- The skill above for correct-usage depth.
- The package README under `packages/flutter_scene/` for the getting-started walkthrough.
- `MATERIALS.md` for the custom-shader output contract.
- https://fscene.dev for guides and live demos.
