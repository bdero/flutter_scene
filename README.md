# flutter_scene

A 3D rendering library for Flutter, built on top of Flutter GPU. Currently only supported when Impeller is enabled.

This repository is a [pub workspace](https://dart.dev/tools/pub/workspaces) containing:

| Package | Description |
| --- | --- |
| [`flutter_scene`](./packages/flutter_scene/) | The core 3D rendering library. Published to pub.dev as [`flutter_scene`](https://pub.dev/packages/flutter_scene). |
| [`flutter_scene_importer`](./packages/flutter_scene_importer/) | Offline glTF → Flutter Scene model importer (build hook). Published to pub.dev as [`flutter_scene_importer`](https://pub.dev/packages/flutter_scene_importer). |
| [`examples/flutter_app`](./examples/flutter_app/) | Runnable example app exercising the library. |

For library usage, see [packages/flutter_scene/README.md](./packages/flutter_scene/README.md).

## Working in this repo

```sh
flutter pub get      # resolves all workspace members
dart analyze packages examples
```

To run the example app:

```sh
cd examples/flutter_app
flutter run --enable-flutter-gpu
```
