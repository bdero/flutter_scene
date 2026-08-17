# Flutter Scene examples

The example app lives in [`flutter_app/`](./flutter_app/) and is a member of the workspace, so its dependencies are resolved automatically with the rest of the repo.

## Running an example

From the repo root:

```sh
flutter pub get                              # resolves the workspace

cd examples/flutter_app
flutter create . --platforms=macos           # gitignored platform stubs
flutter run --enable-flutter-gpu --enable-impeller
```

The build hook (`hook/build.dart`) compiles the engine's shaders, cooks the loose textures, compiles the `.fmat` materials, and converts the glTF assets in `assets_src/` into `.fsceneb` scene packages, all into `flutter_scene_generated/`.
