<p align="center">
  <a href="https://fscene.dev">
    <img alt="Flutter Scene" width="220px" src="https://raw.githubusercontent.com/bdero/flutter_scene_media/main/DashColorTransparent.svg">
  </a>
</p>

<h1 align="center">Scene</h1>

<p align="center"><b>A realtime 3D engine for Flutter</b></p>

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

## Early preview! ⚠️

- This package is in an early preview state. Things may break!
- Relies on [Flutter GPU](https://github.com/flutter/flutter/blob/main/docs/engine/impeller/Flutter-GPU.md) for rendering, which is also in preview state.
- On native platforms this package requires [Impeller](https://docs.flutter.dev/perf/impeller#availability) to be enabled. On the web it runs on a built-in WebGL2 backend instead.
- This package uses the experimental [Dart "Native Assets"](https://github.com/dart-lang/sdk/issues/50565) feature to automate some build tasks.
- Zero-manifest `.fmat` material builds use the experimental Dart DataAssets feature. On supported Flutter master builds, enable it with `flutter config --enable-dart-data-assets`.
- Given the reliance on non-production features, Flutter Scene requires the Flutter [master channel](https://docs.flutter.dev/release/upgrade#other-channels). Version 0.19.0 needs a master build from 2026-06-09 or later, which is when render-to-mip-level Flutter GPU support landed (flutter/flutter#187685). The `flutter` lower bound in `pubspec.yaml` is set to the latest stable instead (so pub.dev can resolve and score the package), which is looser than the real requirement, so a recent master is what you actually want.

## Features

* glTF (.glb) asset import.
* PBR materials.
* Environment maps/image-based lighting.
* Blended animation system.

## FAQ

### **Q:** What platforms does this package support?

On native platforms `flutter_scene` runs anywhere [Impeller](https://docs.flutter.dev/perf/impeller#availability) does. On the web it runs on a built-in WebGL2 backend.

On iOS and Android, Impeller is Flutter's default production renderer. So on these platforms, `flutter_scene` works without any additional project configuration.

On MacOS, Windows, and Linux, Impeller is able to run, but is not on by default and must be enabled. When invoking `flutter run`, Impeller can be enabled by passing the `--enable-impeller` flag.

On the web, no flags are needed; it works under both the CanvasKit and Skwasm renderers.

|         Platform | Status          |
| ---------------: | :-------------- |
|              iOS | 🟢 Supported     |
|          Android | 🟢 Supported     |
|              Web | 🟢 Supported     |
|            MacOS | 🟡 Preview       |
|          Windows | 🟡 Preview       |
|            Linux | 🟡 Preview       |
| Custom embedders | 🟢 Supported     |

### **Q:** How does web support work?

Impeller and Flutter GPU aren't available on the web, so `flutter_scene` ships a built-in WebGL2 backend (a drop-in for `flutter_gpu`) and renders through it there. It works under both the CanvasKit and Skwasm web renderers. Web support is new and in preview, so expect rough edges.

## Repository

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing the library and the example apps:

| Path | Description |
| --- | --- |
| [`packages/flutter_scene`](https://github.com/bdero/flutter_scene/tree/master/packages/flutter_scene) | The 3D rendering library, including the offline glTF importer and the web (WebGL2) backend. Published to pub.dev as [`flutter_scene`](https://pub.dev/packages/flutter_scene). |
| [`examples/flutter_app`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_app) | Runnable example app exercising the library. |
| [`examples/flutter_gpu_shim_smoke`](https://github.com/bdero/flutter_scene/tree/master/examples/flutter_gpu_shim_smoke) | Dev-only smoke test for the web backend. |

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
