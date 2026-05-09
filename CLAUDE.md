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

## Static resources & default environment

`Scene.initializeStaticResources()` loads the BRDF LUT and a default `royal_esplanade` IBL environment (radiance + irradiance). It's called from the `Scene()` constructor and must complete before rendering — the engine prints `"Flutter Scene is not ready to render. Skipping frame."` and skips rendering until it does.

The `Car` example overrides this with `little_paris_eiffel_tower` at `exposure=2.0, intensity=2.0`. Other examples use the default. **A/B comparisons between examples can be misleading** if they don't share env setup.

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
