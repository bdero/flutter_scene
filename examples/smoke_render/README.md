# smoke_render

A headless cross-backend smoke-render harness. It draws a set of deterministic
scenes and asserts each one produced a sane frame (center coverage, clear
corners), which is the cheapest way to catch "nothing drew", "unlit", or
"wrong backend" regressions.

Run one shard:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/smoke_test.dart \
  -d macos --enable-impeller --enable-flutter-gpu
```

Every platform's recipe (Metal, GLES, Vulkan, WebGL2, Android, Windows) lives in
the repo's `notes/ci/local_smoke_render_matrix.md`.

## Asset modes

By default the build hook writes every generated asset into
`flutter_scene_generated/`, which is what consumers get.

To run the Dart data assets lane instead, uncomment the `hooks: user_defines:`
block in the **workspace root** `pubspec.yaml` (user defines are read from the
workspace root, not from a member package), then clear the hook cache so the
change takes effect:

```sh
rm -rf ../../.dart_tool/hooks_runner/smoke_render .dart_tool/flutter_build build
```

The app's own materials and shader bundle then arrive as data assets, and the
tree keeps only flutter_scene's engine assets. Clean the app bundle when
switching either way, since nothing prunes assets from a previous mode.
