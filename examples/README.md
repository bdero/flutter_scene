# Flutter Scene examples

The example app lives in [`flutter_app/`](./flutter_app/) and is a member of the workspace, so its dependencies are resolved automatically with the rest of the repo.

## Running an example

From the repo root:

```sh
flutter pub get                              # resolves the workspace
flutter config --enable-native-assets        # one-time setup

cd examples/flutter_app
flutter run --enable-flutter-gpu             # add `-d <device>` as needed
```

The build hook (`hook/build.dart`) compiles shader bundles and imports the example glTF assets in `assets_src/` to the runtime `.model` format on the fly.
