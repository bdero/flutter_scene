# Working in this repository

This file is loaded into Claude's context. It captures non-obvious things about flutter_scene's conventions so each session doesn't have to re-derive them.

## Repository shape

This is a Dart **pub workspace** (no melos). Three published-or-runnable members:

| Path | What it is |
| --- | --- |
| `packages/flutter_scene` | Core 3D library. Published to pub.dev. |
| `packages/flutter_scene_importer` | Offline glTF → `.model` flatbuffer importer (build hook). Published. |
| `examples/flutter_app` | Runnable example app. Not published. |

Root `pubspec.yaml` is `name: _`, `publish_to: none`, just lists workspace members. Each member declares `resolution: workspace`. Don't add melos — `dart pub publish` per-package directory works clean.

The workspace lockfile lives at root and is gitignored (`pubspec.lock`).

## Toolchain expectations

- **Flutter**: master channel — flutter_gpu / Impeller GPU isn't in stable. Local dev typically uses `bdero/flutter` fork.
- **CI**: macOS, Flutter master via `subosito/flutter-action@v2`. See `.github/workflows/flutter.yml`.
- **Dart format on CI**: master Flutter ships a more recent `dart_style` than fork builds, and the two disagree. Before pushing, run:
  ```sh
  dart pub global activate dart_style
  dart pub global run dart_style:format <files>
  ```
  Saves a CI round-trip — local `dart format` reformats differently from CI on master Flutter.
- **`*/third_party/*` and `*_flatbuffers.dart` are excluded from format checks.** Don't reformat them.

## Branch protection

`master` has linear-history + 1-review-required. For solo work, merge with `gh pr merge <N> --rebase --admin --delete-branch`. Use `--rebase` (not `--merge`) — merge commits violate linear history.

## Build hooks

Both `flutter_scene` and `flutter_scene_importer` use the **`hooks` package** (not `native_assets_cli` — that was discontinued). Imports look like:

```dart
import 'package:hooks/hooks.dart';
```

The `--enable-experiment=native-assets` flag is **obsolete** in Dart 3.10+. Don't add it; doing so breaks the build (this was issue #82).

## Vertex layout (engine convention)

Constants live in `packages/flutter_scene_importer/lib/constants.dart`.

- **Unskinned**: 48 bytes per vertex = 12 floats: position(3), normal(3), tex_coords(2), color(4).
- **Skinned**: 80 bytes per vertex = 20 floats: unskinned + joints(4) + weights(4).
- No tangent attribute (the shader computes tangent space from screen-space derivatives).
- Vertex shader expects exactly this attribute order.

Match this layout exactly when emitting vertex data, or rendering breaks in subtle ways (washed-out colors, see-through faces).

## Coordinate system gotcha

glTF is right-handed (Y-up, +Z out of screen). flutter_scene's pipeline expects the opposite Z. The C++ importer applies `MakeScale({1, 1, -1})` on the **scene root transform** to convert (`importer_gltf.cc:499`). The runtime GLB importer does the same (`runtime_importer.dart`).

If you write another importer, apply the same scene-root flip — *not* a per-triangle winding swap. Hand-rolled winding flips fix geometry orientation but leave normals and IBL sampling wrong.

## Lighting / environment / tone mapping

A `Scene` has: `environment` (an `EnvironmentMap` — defaults to the procedural `EnvironmentMap.studio()`, built/memoized lazily in the constructor), `environmentIntensity` (scalar, default 1.0), `directionalLight` (a `DirectionalLight?`, default null — adds a `ShadowPass` when `castsShadow`), `exposure` (default 1.0 — the old 2.0 was a hack for a buggier renderer; don't reintroduce it), and `toneMapping` (`ToneMappingMode`, default `pbrNeutral`). There is no `Environment` wrapper class anymore. `Scene.physicalCameraExposure({aperture, shutterSpeed, iso})` derives an exposure multiplier.

`EnvironmentMap` always carries a prefiltered-radiance atlas (a GGX-prefiltered "PMREM-style" 8-band equirect atlas, built once at construction by `prefilterEquirectRadiance`) plus SH-9 diffuse coefficients. There is no separate radiance/irradiance texture path and no `kEnvironmentMultiplier` fudge. Construct via `fromAssets` / `fromUIImages` (auto SH + prefilter), `studio()`, `fromGpuTextures` (you supply the atlas), or `empty()`.

`Scene.initializeStaticResources()` (called from the `Scene()` constructor) only loads the BRDF LUT now. Rendering is gated on it — the engine prints `"Flutter Scene is not ready to render. Skipping frame."` until it completes.

The `Car` example loads `little_paris_eiffel_tower.png` via `EnvironmentMap.fromAssets` and bumps `scene.exposure = 2.5` (outdoor pano, no key light). The `Toon` example sets `scene.exposure = 1.5`. Other examples use the defaults. **A/B comparisons between examples can be misleading** if they don't share env/exposure setup.

Material fragment shaders output **linear HDR premultiplied by alpha**; exposure + the tone-mapping operator + the display EOTF are applied later by the full-screen `TonemapPass`. Custom `ShaderMaterial` shaders must follow the same contract (see `MATERIALS.md`).

## Test corpus

Committed source `.glb` files for testing live in `examples/assets_src/`:

| File | Properties | Best for |
| --- | --- | --- |
| `two_triangles.glb` | 10 KB, skinned, animated | Fast skinning iteration (despite the name, NOT a simple test asset) |
| `flutter_logo_baked.glb` | 288 KB, 1 texture | Texture pipeline |
| `fcar.glb` | 3.2 MB, 18 nodes / 17 meshes, no textures, no skinning | Static mesh + node hierarchy |
| `dash.glb` | 4.1 MB, 37 nodes, 2 textures, skinned, 9 animations | Full skinned + animated test |

The example app symlinks `assets_src/` for runtime loading. The corresponding `.model` files (built by the importer hook into `examples/flutter_app/build/models/`) are **gitignored** — tests that need them gracefully skip when absent so CI is green without them.

## Debugging methodology that works

When a runtime render produces visually-wrong output and the bug is in the import pipeline, **don't hypothesize**. Dump bytes at each stage and compare byte-for-byte against the working `.model` path. The runtime importer's correctness was verified this way (`runtime_importer_byte_comparison_test.dart`) and it caught two unrelated bugs the screenshots had been masking.

## Iterating against a locally built engine

For testing engine changes (e.g. an in-flight `flutter/flutter` PR) before they ship to the SDK cache. Captures the traps we hit so you don't re-derive them.

### Setup

Engine source on this machine: `~/projects/flutter/flutter/engine/src/flutter/`. Build configs go in `out/<name>/`. Use the bundled `et` script:

```sh
cd ~/projects/flutter/flutter/engine/src/flutter
bin/et build -c host_debug_unopt_arm64    # required for impellerc + tessellator
bin/et build -c android_debug_unopt_arm64 # the runtime engine for Pixel/arm64 Android
bin/et build -c ios_debug_sim_unopt_arm64 # iOS simulator, etc.
```

First Android build is ~30 min; incremental rebuilds are 1–5 min.

Run with both flags:

```sh
flutter run -d <device> --enable-flutter-gpu --enable-impeller \
  --local-engine=android_debug_unopt_arm64 \
  --local-engine-host=host_debug_unopt_arm64
```

### Trap #1: out/ doesn't track engine source branch

Switching the engine source to a different branch (e.g. for an upstream PR) **does not** rebuild `out/`. The native binaries on disk still have the old ABI; the Dart-side `flutter_gpu` bindings from the framework cache use the new one. Symptom we hit: `Texture creation failed`, with `mip_count = 121167729` (uninitialized memory at the position of an arg that doesn't exist on this branch). Always rebuild after switching engine branches.

### Trap #2: cached impellerc lags the local engine

Build hooks (e.g. `flutter_gpu_shaders`) historically walked up from the dart binary to find `impellerc` in `bin/cache/artifacts/engine/<host>/`. That binary doesn't follow `--local-engine`, so a freshly built engine can produce shader bundles in a format the cached `impellerc` doesn't speak. Symptom: `Unsupported shader bundle format version: 1, expected: 2`.

Fix landed (or landing) in two parts:
- `flutter/flutter#186300`: flutter_tools sets `IMPELLERC` env var on hook subprocesses, resolved through `Artifacts.getHostArtifact(...)` (which honors `--local-engine`).
- `flutter_gpu_shaders 0.4.2`: `findImpellerC()` honors the runtime env var.

Once both are in your tree, the workflow Just Works. If you hit the mismatch on an older combo, the manual workaround is overwriting the cached binary:

```sh
cp ~/projects/flutter/flutter/engine/src/out/host_debug_unopt_arm64/impellerc \
   ~/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc
```

(yes, `darwin-x64` even on arm64 — that's the SDK cache layout). Restore from a `.bak` when done.

### Trap #3: build hooks "skip" when outputs are missing

`flutter clean` cleans `examples/flutter_app/build/` but the hook input-hash cache in `.dart_tool/flutter_build/<hash>/native_assets.json` can still claim outputs are fresh, so the next `flutter run` skips the `build_hooks` target with no warning. Symptom: `Error: unable to find directory entry in pubspec.yaml: .../build/models/`. Recipe to fully reset:

```sh
rm -rf .dart_tool packages/*/.dart_tool examples/flutter_app/.dart_tool \
       packages/flutter_scene/build examples/flutter_app/build
flutter pub get
```

(Reported upstream as a bug; for now, this is the workaround.)

### Trap #4: Android manifest opt-in

Until `flutter/flutter#186298` lands, `--enable-flutter-gpu` is silently ignored on Android — only the `<meta-data android:name="io.flutter.embedding.android.EnableFlutterGPU" android:value="true" />` entry in the consumer's `AndroidManifest.xml` enables Flutter GPU. The CLI flag works on iOS and macOS without any plist entry.

### Platform scaffolding

`examples/flutter_app/` only commits the macOS scaffolding. For iOS or Android testing, generate the missing platform stubs (gitignored):

```sh
cd examples/flutter_app
flutter create . --platforms=ios,android --org dev.bdero
```

iOS additionally needs a one-time team-and-bundle-id setup in Xcode (`open ios/Runner.xcworkspace` → Runner target → Signing & Capabilities → pick Team).

## Issue tracker conventions

Labels we use beyond GitHub defaults:
- `bug`, `performance`, `crash`
- `needs triage`, `needs repro`, `needs info` (workflow states)
- `upstream` — root cause is in Flutter/engine/Dart, not flutter_scene
- `priority: high`
- `roadmap` — long-horizon feature work owned by maintainers
- `feature proposal` — community-requested features
- `platform:android|ios|macos|windows|linux`

Don't apply both `feature proposal` and `roadmap` to the same issue — the former is "user asked for it", the latter is "we plan to build it."

## Releasing

1. Bump version in the package's `pubspec.yaml` and add a CHANGELOG entry.
2. `flutter pub publish --dry-run` from inside the package directory.
3. If the importer is being released too, publish `flutter_scene_importer` **first**, then `flutter_scene` (which depends on it).
4. After publishing, wait a few minutes for pub.dev's package-listing API to propagate before consumers can `flutter pub get`. The `/api/packages/<name>/versions/<version>` endpoint refreshes faster than `/api/packages/<name>` (which lists "latest").
5. SDK constraints: don't pin to a prerelease Dart version (e.g. `>=3.10.0-dev`) unless publishing as a prerelease too — pub.dev blocks the publish otherwise. The Flutter SDK constraint can capture the master-channel requirement (`flutter: ">=3.29.0-1.0.pre.242"`).
