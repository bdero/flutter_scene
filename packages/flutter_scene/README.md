<p align="center">
  <a href="https://fscene.dev">
    <img alt="Flutter Scene" width="220px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/DashColorTransparent.svg">
  </a>
</p>

<h1 align="center">Scene</h1>

<p align="center"><b>A realtime 3D engine for Flutter</b></p>

<p align="center">Scene extends Flutter into a complete toolkit for building incredible 3D multiplatform apps. Rendering, physics, audio, tooling, and a full asset pipeline.</p>

<p align="center">
  <a title="Pub" href="https://pub.dev/packages/flutter_scene"><img src="https://img.shields.io/pub/v/flutter_scene.svg?style=popout"/></a>
  <a title="Test" href="https://github.com/bdero/flutter_scene/actions/workflows/flutter.yml?query=event%3Apush+branch%3Amaster"><img src="https://github.com/bdero/flutter_scene/actions/workflows/flutter.yml/badge.svg?branch=master&event=push"/></a>
  <a title="Discord" href="https://discord.gg/BfGKrcheRj"><img src="https://img.shields.io/badge/Discord-Join-5865F2?logo=discord&logoColor=white"/></a>
</p>

<p align="center"><a href="https://fscene.dev">Website</a> · <a href="https://pub.dev/documentation/flutter_scene/latest/">Docs</a> · <a href="https://github.com/bdero/flutter_scene/tree/master/examples">Examples App</a> · <a href="https://github.com/bdero/flutter_scene?tab=readme-ov-file#faq">FAQ</a></p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/HelmetPhase2.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashgameported2.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashsurfers_run.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/DamagedHelmet2.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dash_physics.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/editor_mcp.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/hexagons3.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/menger_sky.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/cloning.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/gaussian_splats_strawberry.webp">
</p>

<p align="center">
  <img alt="Flutter Scene" width="600px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/dashmap.webp">
</p>

## Why Scene exists

Scene began its life inside the Flutter Engine, as a C++ module for Impeller with a declarative widget interface exposed through a 3D API in the Flutter SDK. Flutter GPU was built initially to set this project free, providing the low-level GPU access needed to develop Scene outside the engine, as an ordinary ecosystem of Dart packages.

That origin shapes the project's philosophy. Scene is a full 3D engine and toolkit that makes Flutter GPU practical to build on, spanning rendering, physics, audio, editor tooling, and asset support across every target Flutter runs on. And the relationship flows both ways by design. The work of building Scene continually exercises and improves Flutter's internal graphics stack, so Impeller and Flutter GPU get better because Scene exists.

The goal has always been to pave the way for advanced graphics in Flutter. In line with the goals set out in Flutter GPU's original design doc, Scene aims to de-fracture, unite, and elevate Flutter's graphics ecosystem, so that building incredible 3D experiences with Flutter and Dart no longer requires engine forks, complicated external renderer integrations, or giving up platforms to get advanced features.

Scene is built by a former core Flutter engine team member who spent four years on Flutter, most of it building Impeller and Flutter GPU.

## Requirements

Flutter Scene is pre-1.0 and evolving quickly. Minor releases can carry breaking changes, and every change is documented in the [CHANGELOG](https://github.com/bdero/flutter_scene/blob/master/packages/flutter_scene/CHANGELOG.md).

- Rendering is built on [Flutter GPU](https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md), which hasn't shipped to the stable channel yet, so Flutter Scene requires the Flutter [master channel](https://docs.flutter.dev/release/upgrade#other-channels). Version 0.19.0 needs a master build from 2026-06-09 or later, which is when render-to-mip-level Flutter GPU support landed (flutter/flutter#187685). The `flutter` lower bound in `pubspec.yaml` is set to the latest stable instead (so pub.dev can resolve and score the package), which is looser than the real requirement, so a recent master is what you actually want.
- On native platforms rendering runs on [Impeller](https://docs.flutter.dev/perf/impeller#availability), which is Flutter's default renderer on iOS and Android and enabled with a flag on desktop. The web has no Impeller, so the package ships its own WebGL2 backend and runs there without flags.
- Build automation (shader bundles, scene and texture pre-conversion) uses [Dart native assets](https://github.com/dart-lang/sdk/issues/50565); enable it once with `flutter config --enable-native-assets`. Zero-manifest `.fmat` material builds additionally use the Dart DataAssets feature, enabled with `flutter config --enable-dart-data-assets`.

## Features

### Rendering

* Physically based materials with image-based lighting, plus a built-in procedural studio environment so an imported model looks good with zero lighting setup.
* Directional, point, and spot lights. Directional and spot lights cast shadows, with cached shadow tiles for static geometry and alpha-masked shadow casters.
* A full post-processing stack, with HDR tone mapping, physical camera exposure, automatic eye adaptation, bloom, fog, god rays, screen-space reflections, depth of field with bokeh, and anti-aliasing with resolution scaling.
* Sky materials with live IBL rebaking, HDR/EXR environment import, and smooth environment cross-fades.
* 3D Gaussian splatting, loading `.ply` and `.splat` captures as scene nodes.
* Instanced rendering, automatic geometry LODs, and an allocation-light frame loop.
* A particle system driven by configurable emitter and behavior modules.

### Materials and shaders

* A custom-material workflow (`.fmat`) covering both fragment and vertex stages, with shader hot reload.
* Per-frame scene inputs for custom shaders, including scene depth and shadow data, plus a depth-aware and shadow-aware custom post-pass API.
* A noise library with matched CPU and GPU implementations.

### Assets and animation

* glTF (`.glb`) import at runtime, or pre-converted at build time into the engine's `.fsceneb` format through build hooks.
* The `.fscene`/`.fsceneb` scene description format, human-readable as text and fast to load as binary, with prefab support.
* KTX2 compressed textures with full mip chains, `.fstex` texture builds, and HDR/EXR environment decoding.
* Skinned meshes and a blended animation system, with declarative per-clip playback control.
* `KHR_materials_variants` support in both import paths, with instant variant switching.
* Hot reload for models, shaders, textures, and environments.

### App integration

* A `SceneView` widget with both an imperative scene-graph API and a fully declarative widget API (`SceneNode`, `SceneMesh`, and `SceneModel` with async loading placeholders).
* Interactive Flutter widgets embedded on 3D surfaces, with pointer raycasting into the scene.
* Screen-reader accessibility, exposing scene content through Flutter semantics.
* Render-target control, split-screen and multi-view layouts, and synchronous frame capture as `ui.Image`.
* Geometry readback and procedural geometry builders with derivation operations.

### Ecosystem

* Physics through [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier) or [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d), both implementing the engine's shared physics contract.
* Audio components with SoLoud and FMOD backends, developed in this repository.
* The Flutter Scene Editor, a desktop scene-editing app with an MCP server for agent-driven editing, in development in this repository.

## FAQ

### **Q:** What platforms does this package support?

On native platforms `flutter_scene` runs anywhere [Impeller](https://docs.flutter.dev/perf/impeller#availability) does. On the web it runs on a built-in WebGL2 backend.

On iOS and Android, Impeller is Flutter's default production renderer. So on these platforms, `flutter_scene` works without any additional project configuration.

On MacOS, Windows, and Linux, Impeller is able to run, but is not on by default and must be enabled. When invoking `flutter run`, Impeller can be enabled by passing the `--enable-impeller` flag.

On the web, no flags are needed; it works under both the CanvasKit and Skwasm renderers.

|         Platform | Status                          |
| ---------------: | :------------------------------ |
|              iOS | 🟢 Supported                     |
|          Android | 🟢 Supported                     |
|              Web | 🟢 Supported                     |
|            MacOS | 🟢 Supported (enable Impeller)   |
|          Windows | 🟢 Supported (enable Impeller)   |
|            Linux | 🟢 Supported (enable Impeller)   |
| Custom embedders | 🟢 Supported                     |

### **Q:** How does web support work?

Impeller and Flutter GPU aren't available on the web, so `flutter_scene` ships a built-in WebGL2 backend (a drop-in for `flutter_gpu`) and renders through it there. It works under both the CanvasKit and Skwasm web renderers, with no extra flags or configuration.

## Repository

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the engine, its companion packages, and the example apps:

| Path | Description |
| --- | --- |
| [`packages/flutter_scene`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene) | The 3D engine, including the glTF importer, the `.fscene` format, and the web (WebGL2) backend. Published to pub.dev as [`flutter_scene`](https://pub.dev/packages/flutter_scene). |
| [`packages/flutter_scene_rapier`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_rapier) | Rapier physics backend, shipping prebuilt native binaries and a wasm module. Published to pub.dev as [`flutter_scene_rapier`](https://pub.dev/packages/flutter_scene_rapier). |
| [`packages/flutter_scene_box3d`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_box3d) | box3d physics backend. Published to pub.dev as [`flutter_scene_box3d`](https://pub.dev/packages/flutter_scene_box3d). |
| [`packages/flutter_scene_soloud`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_soloud) | SoLoud audio backend. Not yet published. |
| [`packages/flutter_scene_fmod`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_fmod) | FMOD Studio audio backend. Not yet published. |
| [`packages/flutter_scene_editor_core`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_editor_core), [`packages/flutter_scene_editor`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_editor), [`packages/flutter_scene_mcp`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene_mcp) | The scene editor stack (headless command core, Flutter UI, and MCP tool surface). In development, not yet published. |
| [`apps/flutter_scene_editor_app`](https://github.com/bdero/flutter_scene/tree/master/apps/flutter_scene_editor_app) | The standalone Flutter Scene Editor desktop app. |
| [`examples/flutter_app`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app) | Runnable example app with 40 feature examples. |

The remaining `examples/` folders are dev-only test harnesses (the web-backend smoke test, deterministic smoke renders, and a CPU stress bench).

To run the example app from a fresh clone:

```sh
flutter pub get                                             # resolves the workspace
flutter config --enable-native-assets                       # one-time setup
flutter config --enable-dart-data-assets                    # one-time setup for DataAssets-backed .fmat materials

cd examples/flutter_app
flutter create . --platforms=macos,ios,android,linux,windows,web  # generate gitignored platform stubs
flutter run --enable-flutter-gpu --enable-impeller            # native; add `-d <device>` if needed
flutter run -d chrome                                         # web
```
