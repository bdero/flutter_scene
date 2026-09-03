<p align="center">
  <a href="https://fscene.dev">
    <img alt="Flutter Scene" width="220px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/DashColorTransparent.svg">
  </a>
</p>

<h1 align="center">Flutter Scene</h1>

<p align="center"><b>A complete 3D game engine for Flutter, built on Flutter GPU</b></p>

<p align="center">Rendering, physics, audio, animation, a scene editor with an MCP server, and a full asset pipeline, on every platform Flutter runs on, web included. Built and maintained by the author of Flutter GPU.</p>

<p align="center">
  <a title="Pub" href="https://pub.dev/packages/flutter_scene"><img src="https://img.shields.io/pub/v/flutter_scene.svg?style=popout"/></a>
  <a title="Test" href="https://github.com/bdero/flutter_scene/actions/workflows/flutter.yml?query=event%3Apush+branch%3Amaster"><img src="https://github.com/bdero/flutter_scene/actions/workflows/flutter.yml/badge.svg?branch=master&event=push"/></a>
  <a title="Codemagic build status" href="https://codemagic.io/app/6a758ce0a34611cf3c8db6ae/smoke-macos/latest_build"><img src="https://api.codemagic.io/apps/6a758ce0a34611cf3c8db6ae/smoke-macos/status_badge.svg"/></a>
  <a title="Covered by Argos Visual Testing" href="https://app.argos-ci.com/scene/flutter_scene"><img src="https://argos-ci.com/badge.svg" alt="Covered by Argos Visual Testing"/></a>
  <a title="Discord" href="https://discord.gg/BfGKrcheRj"><img src="https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white"/></a>
</p>

<p align="center"><a href="https://fscene.dev">Website</a> · <a href="https://fscene.dev/getting-started">Docs</a> · <a href="https://github.com/bdero/flutter_scene/tree/master/examples">Examples App</a> · <a href="#built-with-scene">Games</a> · <a href="https://github.com/bdero/flutter_scene?tab=readme-ov-file#faq">FAQ</a></p>

<p align="center">
  <img alt="Physically based rendering of the glTF DamagedHelmet sample with image-based lighting in Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/HelmetPhase2.webp">
</p>

<p align="center">
  <img alt="Dashsurfers, an endless runner game built with Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashsurfers_run.webp">
</p>

<p align="center">
  <img alt="The Flutter Scene Editor, driven by a coding agent over MCP" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/editor_mcp.webp">
</p>

## At a glance

- **Rendering.** Physically based materials, image-based lighting, directional, point, spot, and area lights with shadows, probe-based global illumination, and a full post-processing stack (bloom, depth of field, fog, god rays, screen-space reflections, color grading, SMAA and TAA). Decals, Gaussian splatting, instancing, LODs, particles, and sky materials.
- **Games.** Physics (Rapier and box3d backends), positional audio (SoLoud and FMOD), multiplayer over dashwire, skeletal and morph animation with blending, camera controllers, a gameplay kit, raycast picking, and interactive Flutter widgets on 3D surfaces.
- **Tooling.** A desktop scene editor with an MCP server for agent-driven editing, agent skills for coding assistants, a build-time asset pipeline, and hot reload for models, shaders, textures, and environments.
- **Formats.** glTF import, the `.fscene` scene document, `.fmat` custom materials in GLSL, KTX2 compressed textures, and HDR/EXR environments.
- **Platforms.** iOS, Android, macOS, Windows, Linux, and the web, where a built-in WebGL2 backend stands in for Impeller.

## Built with Scene

- [Dashsurfers](https://github.com/bdero/dashsurfers), an endless runner with skinned characters, physics, and particles.
- [Dashmap](https://github.com/bdero/dashmap), a live 3D world map with streaming terrain, OSM buildings, and a physical sky.
- The [examples app](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app), 43 runnable feature examples.

## Why Scene exists

Scene began its life inside the Flutter Engine, as a C++ module for Impeller with a declarative widget interface exposed through a 3D API in the Flutter SDK. Flutter GPU was built initially to set this project free, providing the low-level GPU access needed to develop Scene outside the engine, as an ordinary ecosystem of Dart packages.

That origin shapes the project's philosophy. Scene is a full 3D game engine and toolkit that makes Flutter GPU practical to build on, spanning rendering, physics, audio, editor tooling, and asset support across every target Flutter runs on. And the relationship flows both ways by design. Scene's cross-backend render tests are where Flutter GPU regressions get caught, so Impeller and Flutter GPU get better because Scene exists.

The goal has always been to pave the way for advanced graphics in Flutter. In line with the goals set out in Flutter GPU's original design doc, Scene aims to de-fracture, unite, and elevate Flutter's graphics ecosystem, so that building incredible 3D experiences with Flutter and Dart no longer requires engine forks, complicated external renderer integrations, or giving up platforms to get advanced features.

Scene is built by the author of Flutter GPU, a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller.

## Getting started

```sh
flutter pub add flutter_scene
dart run flutter_scene:init
```

`init` sets up the asset pipeline, which is the recommended way to use Scene.
Drop sources under `assets/`, load them by their source path, and render:

```dart
final level = await loadScene('assets/level.glb');
scene.add(level);
// ...
SceneView(scene, cameraBuilder: (elapsed) => PerspectiveCamera(...));
```

The same code runs on web, and the engine's shaders are compiled for you during
the build by flutter_scene's own build hook. Rendering goes through Flutter GPU,
which is off by default, so enable it once per platform (below). The web needs
nothing.

Impeller, which Flutter GPU builds on, is the default renderer on every native
platform as of 3.47, so there is nothing to do for it.

### Coding agents

This package ships a set of agent skills so a coding assistant writes idiomatic
Scene instead of guessing: correct usage and traps, the run-settle-capture
verification loop, copy-paste look presets, procedural content, and
performance. `dart run
flutter_scene:init` offers to install them, and `dart run flutter_scene:skills`
installs, updates, or checks them on their own without touching your build hook.
Upgrading Scene can carry newer revisions; `dart run flutter_scene:skills
--check` reports whether any are available.

### Enable Flutter GPU

While developing, pass the flags on the command line:

```sh
flutter run --enable-flutter-gpu
```

To turn it on permanently, for every run and for the app you ship, edit the
platform file:

| Platform | File | Add |
| --- | --- | --- |
| iOS | `ios/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
| Android | `android/app/src/main/AndroidManifest.xml`, in `<application>` | `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />` |
| macOS | `macos/Runner/Info.plist` | `<key>FLTEnableFlutterGPU</key><true/>` |
| Web | nothing | |

Windows and Linux set it on the `DartProject` their runner builds. This needs Flutter 3.47.1.

```c
// linux/runner/my_application.cc
g_autoptr(FlDartProject) project = fl_dart_project_new();
fl_dart_project_set_enable_flutter_gpu(project, TRUE);
```

```cpp
// windows/runner/main.cpp
flutter::DartProject project(L"data");
project.set_enable_flutter_gpu(true);
```

On 3.47.0 there is no such setting, so desktop takes the command-line flags per run, and release builds compile the engine's environment switches out, meaning a shipped Windows or Linux release needs 3.47.1.

### A scene with no assets

The built-in geometry needs no asset pipeline, so a cube renders straight after `flutter pub add flutter_scene`:

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
    // Geometry and materials touch the shader bundle, so build them once the
    // engine's static resources are up.
    Scene.initializeStaticResources().then((_) {
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(1, 1, 1)),
            PhysicallyBasedMaterial(),
          ),
        ),
      );
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const SizedBox.expand();
    return SceneView(
      scene,
      camera: PerspectiveCamera(position: vm.Vector3(2, 2, -4)),
    );
  }
}
```

The scene's default studio environment lights it, so there is nothing else to set up.

### Moving a node

Every `Node` carries a transform relative to its parent. Read and write it one
component at a time, or as a whole matrix through `node.localTransform`.

```dart
node.position = vm.Vector3(0, 1, 0);
node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.5);
node.scale = vm.Vector3.all(2);
node.position += vm.Vector3(0, 0.1, 0);
```

Each getter returns a copy, so `node.position.y = 1` moves nothing. Assign the
value back instead. Debug builds throw on an edit that cannot reach the node,
whether it is to a returned copy or to `localTransform` in place.

### Built-in geometry

Every class below builds vertex data for you and drops into a `Mesh` the same way `CuboidGeometry` does above.

- Primitives: `CuboidGeometry`, `SphereGeometry`, `IcosphereGeometry`, `CapsuleGeometry`, `CylinderGeometry`, `TorusGeometry`, `PlaneGeometry`, `DiscGeometry`, `RingGeometry`, `WedgeGeometry`.
- Swept along a path or profile: `ExtrudeGeometry`, `TubeGeometry`, `RibbonGeometry`.
- Lines and camera-facing quads: `PolylineGeometry`, `LineSegmentsGeometry`, `BillboardGeometry`.
- Your own vertex data: `MeshGeometry` and `GeometryBuilder`.

### The asset pipeline

`init` writes a `hook/build.dart` that converts your assets at build time,
creates `flutter_scene_generated/` with a `.gitignore` for its outputs, and adds
that one directory to `flutter.assets` in your `pubspec.yaml`. It is safe to run
again, and it will not overwrite a `hook/build.dart` you wrote yourself. It
prints a block to paste into your existing `build()` callback instead.

The hook it writes discovers `.glb` and `.fscene` models, `.fmat` materials, and
loose images under `assets/`, and converts each one:

```dart
// hook/build.dart
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    buildScenes(buildInput: input, buildOutput: output);
    await buildMaterials(buildInput: input, buildOutput: output);
  });
}
```

The one line it adds to your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - flutter_scene_generated/
```

Upgrading from an earlier version, run it again. Generated assets now go into
that directory on every Flutter release, so re-running `init` migrates the hook
it wrote and adds the pubspec entry. A hook still asking for a removed asset
mode fails the build and names its replacement.

From then on, drop sources under `assets/` and load them by source path:

```dart
final level = await loadScene('assets/level.glb');
final toon = await loadFmatMaterial('assets/toon.fmat');
final ground = await loadTexture('assets/ground.png');
```

A `.glb` has to be parsed and unpacked into GPU-ready form every time the app
loads it. The pipeline does that work once, at build time, into the `.fsceneb`
format the engine reads directly, so loading a model at runtime costs far less.
Prefer it for anything that ships with your app. It is also how `.fmat` custom
materials and block-compressed textures with full mip chains reach you, and
editing any source reconverts just that source and hot reloads it.

Keep your sources in version control. The generated directory holds compiled
output tied to the Flutter engine that built it, which is why the hook manages
its `.gitignore` for you.

For a model that only exists once the app is running, because you download it or
the user supplies it, import the `.glb` directly with
`Node.fromGlbAsset('assets/model.glb')`. That needs no hook, and it parses the
glTF on every load, so prefer the pipeline whenever the model ships with you.

### Where to go next

[fscene.dev](https://fscene.dev) carries the full documentation. [Your first
scene](https://fscene.dev/getting-started/your-first-scene/) renders something on
screen from here, and the [guides](https://fscene.dev/guides/) cover each
subsystem in depth with live demos, including [assets and
loading](https://fscene.dev/guides/assets-and-loading/), [materials](https://fscene.dev/guides/materials/),
[lighting and environment](https://fscene.dev/guides/lighting-and-environment/),
[animation](https://fscene.dev/guides/animation/), and [cameras](https://fscene.dev/guides/cameras/).
The [API reference](https://fscene.dev/api/flutter_scene/latest/) documents every
public symbol.

## Requirements

Flutter Scene is pre-1.0 and evolving quickly. Minor releases can carry breaking changes, and every change is documented in the [CHANGELOG](https://github.com/bdero/flutter_scene/blob/master/packages/flutter_scene/CHANGELOG.md).

- Flutter 3.47 (stable) or newer. Rendering is built on [Flutter GPU](https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md), which every platform except the web needs turned on once (see [Enable Flutter GPU](#enable-flutter-gpu)).
- On native platforms rendering runs on [Impeller](https://docs.flutter.dev/perf/impeller#availability), Flutter's default renderer on every native platform as of 3.47. The web has no Impeller, so the package ships its own WebGL2 backend and runs there without flags.

## Features

### Rendering

* Physically based materials with clearcoat, sheen, anisotropy, and transmission, lit by image-based lighting (prefiltered radiance plus spherical-harmonic diffuse), with a built-in procedural studio environment so an imported model looks good with zero lighting setup.
* Sky materials with live IBL rebaking, HDR/EXR environment import, smooth environment cross-fades, and parallax-corrected reflection probes.
* Directional, point, spot, and rect area lights, shaded through per-view froxel clustering so a scene scales to many lights, with light channels to control what each light touches.
* Shadows from directional, spot, and point lights. Cascaded directional shadows with percentage-closer soft shadows and screen-space contact shadows, cube-face point shadows, cached shadow tiles for static geometry, and alpha-masked casters.
* Global illumination from a world-space irradiance probe field with probe visibility and offline or progressive baking, plus screen-space indirect light and ground-truth ambient occlusion.
* A full post-processing stack, with HDR tone mapping, physical camera exposure, automatic eye adaptation, bloom with lens flares, fog, god rays, screen-space reflections, depth of field with bokeh, film-look color grading from `.cube` LUTs, chromatic aberration, and radial screen distortion.
* Anti-aliasing with FXAA, SMAA, and temporal anti-aliasing, geometric specular anti-aliasing, and resolution scaling.
* Projected box decals, 3D Gaussian splatting from `.ply` and `.splat` captures, instanced rendering, automatic geometry LODs, mesh chunking at import, and an allocation-light frame loop.
* A particle system driven by configurable emitter and behavior modules.

### Materials and shaders

* A custom-material workflow (`.fmat`) covering fragment, vertex, and sky stages, with per-instance attributes, engine inputs, and shader hot reload.
* Per-frame scene inputs for custom shaders, including scene depth, world position, and shadow data, plus a depth-aware and shadow-aware custom post-pass API.
* Barycentric wireframe helpers and a noise library with matched CPU and GPU implementations.

### Assets and animation

* glTF (`.glb` and multi-buffer `.gltf`) import at runtime, or pre-converted at build time into the engine's `.fsceneb` format through build hooks, loaded by source path. Sparse accessors, `KHR_materials_variants` with instant switching, and `KHR_texture_basisu`.
* The `.fscene`/`.fsceneb` scene description format, human-readable as text and fast to load as binary, with prefabs and declarative components.
* KTX2 compressed textures with full mip chains, `.fstex` texture builds, and HDR/EXR environment decoding.
* Skinned meshes, morph targets, and a blended animation system with declarative per-clip playback control.
* Hot reload for models, shaders, textures, environments, and scene documents.

### App integration

* A `SceneView` widget with both an imperative scene-graph API and a fully declarative widget API (`SceneNode`, `SceneMesh`, and `SceneModel` with async loading placeholders).
* Orbit, fly, and follow camera controllers, raycast picking, and interactive Flutter widgets embedded on 3D surfaces.
* A gameplay kit (`package:flutter_scene/kit.dart`) with a camera boom, character controller, day/night cycle, water surface, audio, pooling, and debug components.
* Screen-reader accessibility, exposing scene content through Flutter semantics.
* Render-target control, split-screen and multi-view layouts, synchronous frame capture as `ui.Image`, and platform textures (video, camera preview) as material inputs.
* Geometry readback, procedural geometry builders with derivation operations, and a GPU memory report with explicit release.
* Agent skills that teach coding assistants idiomatic Scene, installed by `dart run flutter_scene:init`.

### Ecosystem

* Physics through [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d), both implementing the engine's shared physics contract.
* Positional audio through [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud) or [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod).
* Multiplayer through [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net), binding replicated state to scene nodes over [`dashwire`](https://pub.dev/packages/dashwire).
* The Flutter Scene Editor, a desktop scene-editing app with an MCP server for agent-driven editing, in development in this repository.

## Gallery

<p align="center">
  <img alt="A 3D platformer game running on Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashgameported2.webp">
</p>

<p align="center">
  <img alt="Depth of field and bloom post-processing on a glTF model" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/DamagedHelmet2.webp">
</p>

<p align="center">
  <img alt="Rigid-body physics through flutter_scene_rapier" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dash_physics.webp">
</p>

<p align="center">
  <img alt="Instanced rendering of thousands of animated meshes" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/hexagons3.webp">
</p>

<p align="center">
  <img alt="A custom sky material written in GLSL through the .fmat format" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/menger_sky.webp">
</p>

<p align="center">
  <img alt="Skinned, animated glTF characters cloned across a scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/cloning.webp">
</p>

<p align="center">
  <img alt="3D Gaussian splatting rendered as a scene node" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/gaussian_splats_strawberry.webp">
</p>

<p align="center">
  <img alt="Dashmap, a streaming 3D world map built on Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashmap.webp">
</p>

## FAQ

### **Q:** What platforms does this package support?

On native platforms `flutter_scene` runs anywhere [Impeller](https://docs.flutter.dev/perf/impeller#availability) does. On the web it runs on a built-in WebGL2 backend.

Every native platform needs Flutter GPU turned on. Impeller, which it builds on, is already the default everywhere. [Enable Flutter GPU](#enable-flutter-gpu) has the file and the key for each.

On the web, no flags are needed; it works under both the CanvasKit and Skwasm renderers.

|         Platform | Status                          |
| ---------------: | :------------------------------ |
|              iOS | 🟢 Supported                     |
|          Android | 🟢 Supported                     |
|              Web | 🟢 Supported                     |
|            MacOS | 🟢 Supported                     |
|          Windows | 🟢 Supported (3.47.1 to ship a release) |
|            Linux | 🟢 Supported (3.47.1 to ship a release) |
| Custom embedders | 🟢 Supported                     |

### **Q:** How does web support work?

Impeller and Flutter GPU aren't available on the web, so `flutter_scene` ships a built-in WebGL2 backend (a drop-in for `flutter_gpu`) and renders through it there. It works under both the CanvasKit and Skwasm web renderers, with no extra flags or configuration.

## Sponsors

Scene's development infrastructure is supported by:

- [Codemagic](https://codemagic.io) - macOS CI on Apple silicon hardware

Interested in supporting Scene's development? Reach out: x@bdero.me

## Repository

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the engine, its companion packages, and the example apps:

| Path | Description |
| --- | --- |
| [`packages/flutter_scene`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene) | The 3D engine, including the glTF importer, the `.fscene` format, and the web (WebGL2) backend. Published to pub.dev as [`flutter_scene`](https://pub.dev/packages/flutter_scene). |
| [`packages/flutter_scene_rapier`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_rapier) | Rapier physics backend, shipping prebuilt native binaries and a wasm module. Published to pub.dev as [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier). |
| [`packages/flutter_scene_box3d`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_box3d) | box3d physics backend. Published to pub.dev as [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d). |
| [`packages/flutter_scene_soloud`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_soloud) | SoLoud audio backend. Published to pub.dev as [`flutter_scene_soloud`](https://pub.dev/packages/flutter_scene_soloud). |
| [`packages/flutter_scene_fmod`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_fmod) | FMOD Studio audio backend. Published to pub.dev as [`flutter_scene_fmod`](https://pub.dev/packages/flutter_scene_fmod). |
| [`packages/flutter_scene_net`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_net) | Multiplayer on [`dashwire`](https://pub.dev/packages/dashwire), binding replicated state to scene nodes with interpolated transforms and in-app hosting. Published to pub.dev as [`flutter_scene_net`](https://pub.dev/packages/flutter_scene_net). |
| [`packages/scene`](https://github.com/bdero/flutter_scene/tree/master/packages/scene) | The engine-agnostic `.fscene` document core and the physics contract the backends implement. Published to pub.dev as [`scene`](https://pub.dev/packages/scene). |
| [`packages/flutter_scene_codegen`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_codegen) | Static extraction and code generation for annotated components. A development-time tool, not published. |
| [`packages/flutter_scene_editor_core`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_editor_core), [`packages/flutter_scene_editor`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_editor), [`packages/flutter_scene_mcp`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_mcp) | The Flutter Scene Editor stack (headless command core, Flutter UI, and MCP tool surface). Shipped as the desktop app under `apps/`, not as pub.dev libraries. In active development. |
| [`apps/flutter_scene_editor_app`](https://github.com/bdero/flutter_scene/tree/master/apps/flutter_scene_editor_app) | The standalone Flutter Scene Editor desktop app. |
| [`examples/flutter_app`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app) | Runnable example app with 43 feature examples. |

The remaining `examples/` folders are dev-only test harnesses (the web-backend smoke test, deterministic smoke renders, and a CPU stress bench).

To run the example app from a fresh clone:

```sh
flutter pub get                                             # resolves the workspace

cd examples/flutter_app
flutter create . --platforms=macos,ios,android,linux,windows,web  # generate gitignored platform stubs
flutter run --enable-flutter-gpu                              # native; add `-d <device>` if needed
flutter run -d chrome                                         # web
```

Pass `--dart-define=FLUTTER_SCENE_PROFILE=true` to print 120-frame render graph, culling, encoding, instance packing, binding, byte, draw, and instance summaries. Multiple active `RenderView`s share the counters.
