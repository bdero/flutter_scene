<p align="center">
  <a href="https://github.com/bdero/flutter_scene">
    <img alt="Flutter Scene" width="200px" src="https://raw.githubusercontent.com/gist/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/086f1b421981733da1182656668b940080c54456/DashColorTransparent.svg">
  </a>
</p>

<h3>
<p align="center">
Scene: 3D library for Flutter
</p>
</h3>

<p align="center">
  <a title="Pub" href="https://pub.dev/packages/flutter_scene"><img src="https://img.shields.io/pub/v/flutter_scene.svg?style=popout"/></a>
  <!--<a title="Test" href="https://github.com/bdero/flutter_scene/actions?query=workflow%3Acicd+branch%3Amaster"><img src="https://github.com/bdero/flutter_scene/workflows/cicd/badge.svg?branch=master&event=push"/></a>-->
</p>

Scene is a general purpose realtime 3D rendering library for Flutter. It started life as a C++ component of the Impeller rendering backend in Flutter Engine, and is currently being actively developed as a pure Dart package powered by the Flutter GPU API.

The primary goal of this project is to make performant cross platform 3D easy in Flutter.

<p align="center"><a href="https://github.com/bdero/flutter_scene/tree/master/examples">Examples App</a> — <a href="https://github.com/bdero/flutter-scene-example">Example Game</a> — <a href="https://pub.dev/documentation/flutter_scene/latest/">Docs</a> — <a href="https://github.com/bdero/flutter_scene?tab=readme-ov-file#faq">FAQ</a></p>

---

<p align="center">
  <img alt="Flutter Scene" width="500px" src="https://gist.github.com/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/8156b23a0fb446865554d4fda029f28bc659ef07/dashgameported2.gif">
</p>

<p align="center">
  <img alt="Flutter Scene" width="500px" src="https://gist.github.com/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/8156b23a0fb446865554d4fda029f28bc659ef07/hexagons3.gif">
</p>

<p align="center">
  <img alt="Flutter Scene" width="500px" src="https://gist.github.com/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/ff137e3fdd0b1bb8808d5ff08f5c1c94e8a30665/DamagedHelmet.gif">
</p>

<p align="center">
  <img alt="Flutter Scene" width="500px" src="https://gist.github.com/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/8156b23a0fb446865554d4fda029f28bc659ef07/car_example.gif">
</p>

<p align="center">
  <img alt="Flutter Scene" width="500px" src="https://gist.github.com/bdero/4f34a4dfe78a4a83d54788bc4f5bcf07/raw/ff137e3fdd0b1bb8808d5ff08f5c1c94e8a30665/cloning.gif">
</p>

## Early preview! ⚠️

- This package is in an early preview state. Things may break!
- Relies on [Flutter GPU](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md) for rendering, which is also in preview state.
- This package currently only works when [Impeller is enabled](https://docs.flutter.dev/perf/impeller#availability).
- This package uses the experimental [Dart "Native Assets"](https://github.com/dart-lang/sdk/issues/50565) feature to automate some build tasks.
- Given the reliance on non-production features, switching to the [master channel](https://docs.flutter.dev/release/upgrade#other-channels) is recommended when using Flutter Scene.

## Features

* glTF (.glb) asset import.
* PBR materials.
* Environment maps/image-based lighting.
* Blended animation system.

## FAQ

### **Q:** What platforms does this package support?

`flutter_scene` supports all platforms that [Impeller](https://docs.flutter.dev/perf/impeller#availability) currently supports.

On iOS and Android, Impeller is Flutter's default production renderer. So on these platforms, `flutter_scene` works without any additional project configuration.

On MacOS, Windows, and Linux, Impeller is able to run, but is not on by default and must be enabled. When invoking `flutter run`, Impeller can be enabled by passing the `--enable-impeller` flag.

|         Platform | Status          |
| ---------------: | :-------------- |
|              iOS | 🟢 Supported     |
|          Android | 🟢 Supported     |
|            MacOS | 🟡 Preview       |
|          Windows | 🟡 Preview       |
|            Linux | 🟡 Preview       |
|              Web | 🔴 Not Supported |
| Custom embedders | 🟢 Supported     |

### **Q:** When will web be supported?

Although there has been some very promising experimentation with porting Impeller to web, there is currently no ETA on web platform support.

Web is an important platform, and both `flutter_gpu` and `flutter_scene` will eventually support Flutter web.

### **Q:** I'm seeing errors when running the importer: `ProcessException: No such file or directory`. How do I fix it?

Install [CMake](https://cmake.org/download/).
