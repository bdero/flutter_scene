# Working in this repository

This file is loaded into Claude's context. It captures non-obvious things about flutter_scene's conventions so each session doesn't have to re-derive them.

## Repository shape

This is a Dart **pub workspace** (no melos). One published package plus two runnable example apps:

| Path | What it is |
| --- | --- |
| `packages/flutter_scene` | The entire library. Published to pub.dev. Contains the renderer, the runtime + offline glTF importer (`lib/src/importer/`), and an internal `flutter_gpu` shim (`lib/src/gpu/`). |
| `examples/flutter_app` | Runnable example app (8 examples). Not published. |
| `examples/flutter_gpu_shim_smoke` | Dev-only smoke test for the web GPU backend (6 isolation tabs). Not published. |

`flutter_scene_importer` and `flutter_gpu_shim` used to be separate published packages; both were folded into `flutter_scene` (commit `ea2f5e1`) so the single published package has no path/git deps. Old `flutter_scene_importer` pub.dev versions remain, but it is no longer published.

Root `pubspec.yaml` is `name: _`, `publish_to: none`, just lists workspace members. Each member declares `resolution: workspace`. Don't add melos.

The workspace lockfile lives at root and is gitignored (`pubspec.lock`).

## GPU backend / web shim

`lib/src/gpu/` is an internal drop-in for `package:flutter_gpu`, selected by a conditional export in `lib/src/gpu/gpu.dart`:

- **native** (`dart.library.io`): re-exports `package:flutter_gpu` verbatim (zero cost).
- **web** (`dart.library.js_interop`): a WebGL2 backend (lets flutter_scene run on web, where Impeller/Flutter GPU don't exist).
- **fallback**: a throwing stub. The analyzer resolves to the stub, so the stub must mirror the full public surface or `flutter analyze` breaks.

flutter_scene's own code imports `package:flutter_scene/src/gpu/gpu.dart as gpu`. The **curated public surface** for the custom-shader (`ShaderMaterial`) workflow is `package:flutter_scene/gpu.dart` (`Shader`, `ShaderLibrary`, `loadShaderLibraryAsync`, `Texture`, `SamplerOptions`, sampler enums). The low-level shim (contexts, passes, buffers, pipelines) stays internal; the smoke app reaches it via `lib/src` with `implementation_imports` disabled.

Web specifics worth knowing:
- Shaders: the bundle's `opengl_es` GLSL ES 1.00 is transpiled to 3.00 at load (`lib/src/gpu/shared/glsl_transpile.dart`). That transpile also negates `gl_Position.y` in vertex shaders, and `RenderPass.setWindingOrder` inverts CW/CCW, so render-to-texture is stored top-down (matching Impeller); the present blit flips Y back. Mirrors `flutter/flutter#186556`.
- `ShaderLibrary.fromAsset` is sync and throws on web; use `loadShaderLibraryAsync`. Touching `baseShaderLibrary` (every Geometry/Material ctor) must happen after `Scene.initializeStaticResources()` completes.
- `Texture.asImage()` is synchronous on web via `OffscreenCanvas.transferToImageBitmap()` + `ui_web.createImageFromImageBitmap` (both sync on CanvasKit and Skwasm), so flutter_scene's synchronous render path needs no API change.
- Run on web: `flutter run -d chrome` (`--wasm` for Skwasm). The example apps' `web/` scaffolding is gitignored; `flutter create` crashes when a direct `flutter_gpu: sdk` dep is present, so copy `web/` from another app instead.
- `lib/src/gpu/web/shader_bundle_generated.dart` is flatc output, hand-patched (`Uint64Reader` -> `Uint32Reader`, since dart2js can't read uint64). Re-apply if regenerated.

## Toolchain expectations

- **Flutter**: master channel — flutter_gpu / Impeller GPU isn't in stable. Local dev typically uses `bdero/flutter` fork.
- **CI**: macOS, Flutter master via `subosito/flutter-action@v2`. See `.github/workflows/flutter.yml`.
- **Dart format on CI**: master Flutter ships a more recent `dart_style` than fork builds, and the two disagree. Before pushing, run:
  ```sh
  dart pub global activate dart_style
  dart pub global run dart_style:format <files>
  ```
  Saves a CI round-trip — local `dart format` reformats differently from CI on master Flutter.
- **`*/third_party/*`, `*_flatbuffers.dart`, and `lib/src/gpu/web/shader_bundle_generated.dart` are excluded from format/analysis.** Don't reformat them.

## Branch protection

`master` has linear-history + 1-review-required. For solo work, merge with `gh pr merge <N> --rebase --admin --delete-branch`. Use `--rebase` (not `--merge`) — merge commits violate linear history.

## Build hooks

`flutter_scene` uses the **`hooks` package** (not `native_assets_cli` — that was discontinued) for its shader-bundle build hook (`hook/build.dart`). Imports look like:

```dart
import 'package:hooks/hooks.dart';
```

Consumer apps that pre-convert `.glb` assets to `.model` call `buildModels` from `package:flutter_scene/build_hooks.dart` in their own `hook/build.dart` (see `examples/flutter_app/hook/build.dart`, which calls both `buildModels` and `buildShaderBundleJson`).

The `--enable-experiment=native-assets` flag is **obsolete** in Dart 3.10+. Don't add it; doing so breaks the build (this was issue #82).

## Vertex layout (engine convention)

Constants live in `packages/flutter_scene/lib/src/importer/constants.dart`.

- **Unskinned**: 48 bytes per vertex = 12 floats: position(3), normal(3), tex_coords(2), color(4).
- **Skinned**: 80 bytes per vertex = 20 floats: unskinned + joints(4) + weights(4).
- No tangent attribute (the shader computes tangent space from screen-space derivatives).
- Vertex shader expects exactly this attribute order.

Match this layout exactly when emitting vertex data, or rendering breaks in subtle ways (washed-out colors, see-through faces).

## Coordinate system gotcha

glTF is right-handed (Y-up, +Z out of screen). flutter_scene's pipeline expects the opposite Z. The importers apply `MakeScale({1, 1, -1})` on the **scene root transform** to convert: the runtime GLB importer (`lib/src/runtime_importer/`) and the offline importer (`lib/src/importer/`, schema `lib/src/importer/scene.fbs`). (A former C++ importer did the same; it was deleted in commit `3f3a157`.)

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

There's now a single published package (`flutter_scene`); the old importer-first ordering is gone.

1. Bump version in `packages/flutter_scene/pubspec.yaml` and add a CHANGELOG entry.
2. `flutter pub publish --dry-run` from inside `packages/flutter_scene`.
3. Run `pana` and confirm the score is still **160/160** before publishing:
   ```sh
   dart pub global activate pana
   dart pub global run pana --no-warning packages/flutter_scene
   ```
   We held a perfect score; keep it there. The points that are easy to lose:
   - **Stale dependency constraints (40 pts).** A constraint that doesn't allow a dependency's latest *stable* stops earning points ~30 days after that stable ships. pana warns before the clock runs out, so widen the constraint proactively. (This is the `hooks` 1.x -> 2.0 situation tracked in the issue history.)
   - **Static analysis in generated files (50 pts).** pana does NOT honor `analysis_options.yaml` excludes for its analysis check. Generated files (`*_flatbuffers.dart`, `lib/src/gpu/web/shader_bundle_generated.dart`) must carry `// ignore_for_file:` headers, not just be excluded.
   - **`description` length (docs pts).** Keep the pubspec `description` at 60+ characters; a shorter one is penalized.
   - **Platform/WASM support.** `platforms:` in the pubspec must list `web:`, and the package must stay WASM-compatible (no `dart:io` on the web dependency graph; see the build-hook conditional export).
4. Publish: `flutter pub publish` from inside `packages/flutter_scene` (use `--force` to skip the prompt) on a clean `master` at the bumped version. The merge of the release-prep PR is what gets the bump onto `master` first.
5. After publishing, wait a few minutes for pub.dev's package-listing API to propagate before consumers can `flutter pub get`. The `/api/packages/<name>/versions/<version>` endpoint refreshes faster than `/api/packages/<name>` (which lists "latest").
6. SDK constraints: don't pin to a prerelease Dart version (e.g. `>=3.10.0-dev`) unless publishing as a prerelease too; pub.dev blocks the publish otherwise. The Flutter SDK constraint can capture the master-channel requirement (`flutter: ">=3.29.0-1.0.pre.242"`).
