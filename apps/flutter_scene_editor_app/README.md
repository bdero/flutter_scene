# flutter_scene_editor_app

The standalone Flutter Scene Editor desktop application. The editor UI itself
lives in [`packages/flutter_scene_editor`](../../packages/flutter_scene_editor);
this app is the shell that owns the native windows, the MCP server, and the
packaging.

## Running it

From a fresh checkout, on Flutter 3.47 stable or newer:

```sh
flutter pub get                                   # from the repo root
cd apps/flutter_scene_editor_app
flutter run -d macos --enable-flutter-gpu
```

No patches, no `flutter config` flags. The app enables the framework's
windowing feature itself (see below), and the source is written in the
windowing names that 3.47 stable ships.

## The windowing feature

The editor's macOS runner is headless: it creates no window of its own,
because multi-view mode has to be entered before any view controller exists,
so every window originates from Dart through the framework's experimental
windowing API.

That API is gated behind `isWindowingEnabled`, which normally comes from a
`FLUTTER_ENABLED_FEATURE_FLAGS` dart-define. `flutter_tools` declares the
feature master-only, so on stable `flutter config --enable-windowing` writes
the setting but the define never reaches the build. The flag is a plain
mutable `bool` and the framework's guards read it at call time, so
[`lib/main.dart`](lib/main.dart) sets it directly instead. That is the whole
workaround, and it disappears when windowing reaches stable upstream
([flutter/flutter#30701](https://github.com/flutter/flutter/issues/30701)).

## Working on the master channel

The source targets 3.47 stable, which is what [`flutter.version`](flutter.version)
pins and what the distribution builds against. Master renamed the windowing API
(dropping the `Regular` prefix) and re-exports `ScrollCacheExtent` through
`material.dart`, so three files do not compile there as written. Patch them,
and reverse before committing:

```sh
git apply    apps/flutter_scene_editor_app/tool/patches/window_names_master.patch
git apply -R apps/flutter_scene_editor_app/tool/patches/window_names_master.patch
```

Both patch directions are exercised in CI, which analyzes the whole workspace
and builds this app on whichever channel the run targets. Delete the patch once
the pin moves to a stable carrying the rename (3.50), where the channels agree.

## Packaging a distributable

```sh
dart tool/package_editor.dart --platform macos \
    [--sign-identity "Developer ID Application: ..."] \
    [--notarize-profile <notarytool keychain profile>]
```

The packaged bundle carries the offline shader toolchain the editor needs to
compile `.fmat` materials at runtime: the SDK's `impellerc`, its `shader_lib`
includes, flutter_scene's framework GLSL, and a `tool_manifest.json` recording
the Flutter revision everything was built from. Run it on the host you are
packaging for; cross-packaging is unsupported.
