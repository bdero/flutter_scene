# stress_bench

CPU stress benchmark for flutter_scene's per-frame hot paths (dev-only, not published). Builds synthetic scenes at renderer-hostile sizes, drives real frames from a ticker (rendering into a discarded `PictureRecorder`), and prints per-phase CPU timings plus direct micro-benchmarks of the hot loops.

Run in profile mode for representative numbers:

```sh
flutter run -d macos --profile --enable-flutter-gpu --enable-impeller
```

On web, build in profile and open it in Chrome; the report goes to the browser console and ends with a `BENCH_DONE` line, since a tab cannot exit:

```sh
flutter build web --profile
python3 -m http.server -d build/web 8000
```

The app runs every scenario (20 warmup + 100 measured frames each), prints a table and a machine-readable `BENCH_JSON` line, then exits. Debug-mode runs print a warning; JIT timings do not predict AOT.

## Phases

Each frame is split into the engine's externally observable segments.

| Phase | What it covers |
| --- | --- |
| `mutate` | Scenario-side scene mutation (moving nodes, churn add/remove). Mount/unmount and render item registration costs land here. |
| `update` | `Scene.update`, the pre-pass walk (component ticks, world transform refresh, render item refresh, bounds recompute). |
| `bvh` | `RenderScene.rebuildIfDirty`, timed separately just before render so render's own call is a no-op. |
| `render` | `Scene.render` CPU time, culling, LOD, draw record + sort, encode, all passes, command submission. |
| `frame` | The sum, wall-clock. |

## Scenarios

| Scenario | Stresses |
| --- | --- |
| `static_10k` | The per-item pre-pass refresh floor with zero movers (change-detection headroom). |
| `movers_10pct_10k` | Dirty propagation, transform recompute, bounds refresh, BVH refit at a realistic mover ratio. |
| `movers_100pct_10k` | Same, worst case. |
| `translucent_4k` | Per-frame draw record allocation and the back-to-front sort. |
| `lights_256_10k` | Punctual light scatter (BVH query per light) and per-item light list assembly. |
| `instanced_50k` | Per-frame instance transform packing and the instanced encode path. |
| `churn_512_10k` | Mount/unmount, render item registration, BVH rebuild. |

## Micro benchmarks

Direct loops over the hot structures, no rendering involved, `ms/op`:

- `bvh_build_10k`, `bvh_refit_10k`, `bvh_query_10k` on 10,240 synthetic items (`bvh_query_10k_visited` reports how many items the query visits, as a sanity check).
- `pack_instances_50k`, one `packInstanceTransforms` call over 50,000 instances.
- `transform_chain_1k`, dirtying the root of a 1,000-deep node chain and reading the leaf's `globalTransform`.

## Comparing runs

Grab the `BENCH_JSON` line from two runs and diff the numbers. Scenario timings include GPU command encoding but not GPU execution; keep the machine idle and on AC power for stable results.

## Presentation benchmark

`lib/present_bench.dart` times a `SceneView` filling the window, with a gradient behind it and a HUD above, to compare web presentation modes. It reports Flutter frame timings (build, raster, and vsync interval medians) as a `BENCH_JSON` line, and marks `bench_start` and `bench_end` on the page timeline so a Chrome trace can be cut to the measured frames.

```sh
flutter build web --profile -t lib/present_bench.dart
python3 -m http.server -d build/web 8000
# open http://localhost:8000/?presentation=domCanvas (or flutterCanvas)
```

`background=0` drops the gradient and `hud=0` drops the HUD. Add `--wasm` for Skwasm, and `--dart-define=flutter_scene.webgpu=true` (with `flutter_scene_webgpu: true` under the workspace pubspec's `hooks: user_defines:` for both `flutter_scene` and `stress_bench`, as `tools/webgpu_smoke/opt_in.sh` does for the smoke app) for WebGPU.
