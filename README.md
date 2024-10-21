# Flutter Scene

3D library for Flutter.

![Failed to load Screenshot](./screenshots/flutter_scene_logo.png)

## ⚠️ Early preview ⚠️

- This package is in an early preview state. Things may break!
- Relies on [Flutter GPU](https://github.com/flutter/engine/blob/main/docs/impeller/Flutter-GPU.md) for rendering, which is also in an early preview state.
- This package currently only works when [Impeller is enabled](https://docs.flutter.dev/perf/impeller#availability).
- This package uses the experimental [Dart "Native Assets"](https://github.com/dart-lang/sdk/issues/50565) feature to automate some build tasks.
- Given the reliance on non-production features, switching to the [master channel](https://docs.flutter.dev/release/upgrade#other-channels) is recommended when using Flutter Scene.

Think you can handle it.....? Then welcome aboard!

## Features

* glTF (.glb) asset import.
* PBR materials.
* Blended animation system.

https://github.com/bdero/flutter_scene/assets/919017/b44fba62-ec48-4ab4-80cc-6449cef21292

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
