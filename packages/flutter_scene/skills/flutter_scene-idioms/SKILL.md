---
name: flutter_scene-idioms
version: 5
description: Write correct flutter_scene code. Use this whenever building 3D with the flutter_scene Dart/Flutter engine (rendering a scene, geometry, materials, lighting, loading a .glb model, animation, custom shaders). It corrects the wrong assumptions models carry from three.js, Godot, and Unity, and names the APIs and traps that are specific to this engine.
---

# Building with flutter_scene

flutter_scene is a realtime 3D engine for Flutter, built on Flutter GPU. It has a retained scene graph (`Scene` holds `Node`s, nodes carry a `Mesh`), physically based materials, image-based lighting, and a deep post-processing stack.

**The one thing to internalize: this is not three.js, Godot, or Unity, and the API diverges from all three in specific ways.** Most first-attempt failures come from reaching for another engine's spelling. The corrections below are the highest-value part of this skill; read them before writing code.

## Do not reach for these (they do not exist or will break the build)

- **Not the master channel.** flutter_scene runs on **Flutter 3.47 stable or newer**. Do not run `flutter channel master`; it resolves worse, not better.
- **Not `--enable-impeller`, not `--enable-experiment=native-assets`.** The run flag is **`--enable-flutter-gpu`** and nothing else. `--enable-experiment=native-assets` actively breaks the build on Dart 3.10+.
- **Not `package:vector_math/vector_math_64.dart`.** flutter_scene uses **`package:vector_math/vector_math.dart`**. The `_64` types are a different, incompatible `Vector3`.
- **Not `Node.fromAsset(...)`, not `loadModel(...)`.** Load a preprocessed model with **`loadScene('assets/x.glb')`** (returns `Future<Node>`), or a runtime glTF with `Node.fromGlbAsset` / `Node.fromGlbBytes`.
- **Not a hand-rolled `CustomPainter` + `Ticker`.** Display a scene with the **`SceneView`** widget; it drives the per-frame loop for you.
- **Not `node.position.set(x, y, z)`.** See transforms below.
- **Not `.model` files or `buildModels`.** The offline format is `.fsceneb`, produced by the `flutter_scene:init` build hook; you load it by source path with `loadScene`.
- **Not the removed `Environment` class.** Environment lighting is `EnvironmentMap` on `Scene.environment`.

## Setup

```sh
flutter pub add flutter_scene
dart run flutter_scene:init      # installs the build hook, sets up assets
flutter run --enable-flutter-gpu # native; add -d chrome for web
```

`flutter_scene:init` is required setup, not optional. Rendering is gated on `Scene.initializeStaticResources()`; until it completes the engine prints "Flutter Scene is not ready to render. Skipping frame."

## Minimal scene (this compiles as-is)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const MaterialApp(home: CubeView()));

class CubeView extends StatefulWidget {
  const CubeView({super.key});
  @override
  State<CubeView> createState() => _CubeViewState();
}

class _CubeViewState extends State<CubeView> {
  final Scene scene = Scene();
  bool ready = false;

  @override
  void initState() {
    super.initState();
    // Geometry and materials touch the shader bundle, so build them only
    // after the engine's static resources are up.
    Scene.initializeStaticResources().then((_) {
      scene.add(Node(
        mesh: Mesh(CuboidGeometry(vm.Vector3(1, 1, 1)), PhysicallyBasedMaterial()),
      ));
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const SizedBox.expand();
    return SceneView(scene, camera: PerspectiveCamera(position: vm.Vector3(2, 2, -4)));
  }
}
```

An unset `Scene.environment` still gives image-based lighting (a default studio map is resolved at render), so a bare `PhysicallyBasedMaterial()` is lit without any light setup.

## Choosing declarative or imperative

flutter_scene has two ways to build a scene, and picking the wrong one is a structural decision that is expensive to undo later. Choose up front by what the app does, not by which reads nicer.

**Declarative (inline widgets).** Describe the scene as Flutter widgets under `SceneView.declarative(children: [...])`, using `SceneMesh`, `SceneNode`, and `SceneModel`. Flutter's own rebuild diffing keeps the rendered scene in sync with your widget state, the same way it keeps the UI in sync. Reach for this when app state maps cleanly onto a fixed set of objects on screen and nothing is simulation-like, for example a product configurator where a few `SceneMesh`es track some `setState` values.

**Imperative (retained scene graph).** Own a `Scene`, add `Node`s, attach `Component`s, and display it with `SceneView(scene, camera: ..., onTick: ...)`. Track state the way you would in another game engine. The cleanest shape is a plain Dart `Game` class that owns the `Scene` and holds the game state, with the scene build and per-frame tick routed into it, and behavior living in custom `Component`s attached to nodes that the engine runs through the component lifecycle hooks. Reach for this for anything with real simulation.

**Go imperative when** the scene has complex physics, network replication, a character walking around, or procedural generation. Any one of these means imperative.
**Stay declarative when** state maps directly to a fixed set of shown objects and nothing ticks or simulates.

The two interoperate. A mostly-declarative scene can drop to an imperative node where it needs one, and an imperative scene can mount declarative subtrees. See `references/architecture.md` for the `Game`-class pattern, component-driven nodes, and the hybrid seam.

## The API shape (where it diverges from what you expect)

**Transforms.** `Node` has `position`, `rotation` (a `Quaternion`), and `scale`, but they are whole-value get/set, not the mutable spelling other engines use. Assign the whole vector (`node.position = vm.Vector3(0, 1, 0)` or `node.position += ...`). The getters return copies, so `node.position.x = 5` does nothing and throws in debug. For a raw matrix edit use `node.localTransform = matrix` or `node.mutateLocalTransform((m) => m.translateByVector3(...))`; a bare in-place edit of `node.localTransform` never moves the node, because the cache is not told.

**Geometry.** Ten built-in primitives (`CuboidGeometry`, `SphereGeometry`, `IcosphereGeometry`, `CylinderGeometry` with separate top/bottom radii so cones are free, `CapsuleGeometry`, `TorusGeometry`, `PlaneGeometry`, `DiscGeometry`, `RingGeometry`, `WedgeGeometry`), plus swept geometry (`ExtrudeGeometry`, `TubeGeometry`, `RibbonGeometry`), lines (`PolylineGeometry`), and `GeometryBuilder`/`MeshData` for custom meshes. Do not hand-pack a `ByteData` vertex buffer before checking these.

**Materials.** `PhysicallyBasedMaterial` (base color, metallic, roughness, normal, emissive, plus clearcoat/sheen/transmission/etc.), `UnlitMaterial`, `ShaderMaterial` for custom shaders. Texture slots take a `TextureSource` (from `loadTexture(path)`), not a raw `gpu.Texture`.

**Camera.** `PerspectiveCamera(position: ..., target: ...)`. There is no orthographic camera built in.

## What you are probably underestimating (it is all here)

Models trained on older or thinner information assume flutter_scene has no lighting, no shadows, and no post-processing. It has all of it. Before hand-rolling any of these, know they exist: **directional/point/spot/area lights, shadows (PCSS, contact shadows), GTAO ambient occlusion, screen-space reflections, parallax-corrected reflection probes, SSGI, depth of field, god rays, fog, auto exposure, LUT color grading, bloom, lens flares, MSAA/SMAA/FXAA, tone mapping, instancing, LOD.** See `references/what-exists.md` for the full surface with the class names.

## Traps that fail silently (wrong pixels, no error)

- **Custom `ShaderMaterial` output is linear HDR premultiplied by alpha.** No tone mapping or gamma in your shader; the `ResolvePass` applies exposure, tone mapping, and the display transform. Linearize sRGB texture samples yourself. See `MATERIALS.md`.
- **Never hand-roll a per-triangle winding flip to fix glTF orientation.** The importers handle the coordinate conversion; a manual flip leaves normals and IBL wrong.
- **Do not emit a vertex buffer at the wrong stride.** Unskinned is 72 bytes/vertex, skinned is 104; the attribute order is fixed. Use `GeometryBuilder`, do not guess the layout.

## More depth

- `references/architecture.md` for the declarative-vs-imperative choice in depth, the `Game`-class pattern, component-driven nodes, and hybrid interop.
- `references/what-exists.md` for the full API surface (the false-absence fix).
- `references/traps.md` for the complete silent-failure list.
- The repo-root `MATERIALS.md` for the custom-shader contract.

## Keeping this skill current

This skill ships inside the flutter_scene package, so upgrading flutter_scene can carry a newer revision of it than the copy installed in the project. To check, run:

```sh
dart run flutter_scene:skills --check
```

It reports the installed and bundled skill versions and exits non-zero when an update is available. If the installed flutter_scene ships a newer skill than what is installed, tell the user, since they are working against out-of-date guidance, and offer to update it with `dart run flutter_scene:skills` (which touches only the skill, not their build hook or pubspec). Worth a check when you start substantial flutter_scene work or when the user mentions upgrading the package.