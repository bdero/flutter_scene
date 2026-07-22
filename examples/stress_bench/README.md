# stress_bench

CPU stress benchmark for flutter_scene's per-frame hot paths (dev-only, not published). Builds synthetic scenes at renderer-hostile sizes, drives real frames from a ticker (rendering into a discarded `PictureRecorder`), and prints per-phase CPU timings plus direct micro-benchmarks of the hot loops.

Run in profile mode for representative numbers:

```sh
flutter run -d macos --profile --enable-flutter-gpu --enable-impeller
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
