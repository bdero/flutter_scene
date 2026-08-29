---
name: flutter_scene-performance
version: 3
description: Make a flutter_scene app hit frame budget. Use whenever a scene janks, stutters, or drops frames, or when the ask is to make it faster or run on mobile or web, because code-driven scenes are reliably slow and the fix depends on which thread is over budget, not on a guessed poly count.
---

# Making flutter_scene fast

A code-driven flutter_scene scene is reliably slow, and the usual reason is that nothing told you the budget or what to fix first, so optimization starts as guesswork. Guessing wastes iterations and often makes the wrong thread slower. This skill replaces the guessing with a budget, a way to measure it, and a fixed order to apply fixes in.

**The one thing to internalize: measure the actual frame, find which of the two threads is over budget, then fix that thread. Do not target a triangle or draw-call number from memory.** There is no built-in poly budget, and the same scene can be fast on desktop and jank on a phone. The number that matters is milliseconds per frame on the real target.

## The budget

A frame has a fixed wall-clock budget set by the refresh rate.

- **60 fps is 16.6 ms per frame. 120 fps is 8.3 ms.** Miss it and the frame janks.
- That budget is split across **two threads**, and either one blowing it drops the frame:
  - **UI thread** runs your Dart. flutter_scene walks the scene graph, culls, updates components, and builds the render here.
  - **Raster thread** is where Impeller draws the built frame on the GPU. The whole post-processing stack (ambient occlusion, reflections, depth of field, god rays, bloom) lands here.
- **Mobile and web are the real constraint.** Desktop GPUs hide a lot; a scene that runs smooth on a laptop can miss budget badly on a phone or in a browser. Profile on the lowest target you must support.

## Measure first (do not skip this)

There is no runtime stats API (`scene.frameTime` does not exist), but the renderer has compile-time profiling. Measurement is those defines plus Flutter's own tooling.

1. **Run in profile mode.** `flutter run --profile --enable-flutter-gpu`. Debug-mode timings are meaningless for performance (assertions, no JIT-to-AOT optimization, extra checks), so never judge speed in debug.
2. **Engine pass timing.** Add `--dart-define=FLUTTER_SCENE_PROFILE=true` and the renderer prints sampled per-pass CPU means and maxes to stdout (`ScenePass`, `DepthPrepass`, `ShadowPass`, `BloomPass`, ...) plus encoder stats (`FLUTTER_SCENE_PROFILE_ENCODER`, draw and instance counts, sort/encode/instance-pack times). A healthy mean next to a huge max is a one-off stall, not steady-state cost; find the stall (see the pipeline section below) instead of shrinking the steady state.
3. **Read the frame chart.** Open DevTools, go to the Performance view, and read **per-frame UI time vs raster time**. The jank frames are flagged. This single view tells you which thread is over budget, which decides everything below.
4. **Or use the performance overlay** for a quick in-app read of the two thread graphs without DevTools.
5. **Stopwatch as a coarse fallback.** A `Stopwatch` around the per-frame work gives a rough UI-thread number when you cannot open DevTools. It sees nothing on the raster thread.

Which thread is over budget names the fix. UI over budget means too much graph/CPU work (steps a, b, c below). Raster over budget means too much GPU work (steps d, e). See `references/performance.md` for the symptom to thread diagnosis.

## The fixed remediation order

Apply top-down. Each step lists the real API. Do the measured-over-budget thread's steps first, but the order within is deliberate, the earlier fixes are the bigger wins.

1. **Instancing** (UI thread). Many copies of one mesh collapse into one draw and one cull test. Build an `InstancedMesh(geometry:, material:)`, add a transform per copy with `addInstance(matrix, {color})`, and mount it with `InstancedMeshComponent`. The single biggest win for repeated geometry (foliage, crowds, tiles, debris). Per-instance frustum culling is off by default (`cullInstances: false`), so the batch is one cull test as a unit. See the `flutter_scene-procedural` skill for the full scatter pattern.

2. **Level of detail** (both threads). `LodComponent(List<LodLevel>)` swaps cheaper meshes as an object shrinks on screen. Each `LodLevel(geometry:, material:, screenSize:)` gives a threshold (projected size as a fraction of viewport height, highest detail first, last is the cull floor). Fewer triangles for distant objects on the GPU, and nothing drawn below the floor. Note the shadow and depth passes always draw the highest-detail level, so LOD does not lighten shadow cost.

3. **Culling** (UI thread). `Node.frustumCulled` (default true) skips off-screen subtrees; leave it on. Set it `false` only where the cached bound is known-stale or unbounded (procedural terrain you regenerate). For whole sets, `RenderView.cullingPlanes` adds extra clip planes, and `node.layers` (default `kRenderLayerDefault`) against `RenderView.layerMask` (default `kRenderLayerAll`) skips entire layers a view should not draw.

4. **Shrink the post stack** (raster thread). This is usually where raster time goes. Turn off effects you do not need via the `EnvironmentSettings` `*Enabled` flags, keep `ambientOcclusionHalfResolution: true`, lower `depthOfFieldQuality` toward `DepthOfFieldQuality.low`, drop `RenderView.renderScale` (or `Scene.renderScale`) below `1.0` to render fewer pixels, and step `Scene.antiAliasingMode` down (`msaa` to `fxaa` to `none`). See the `flutter_scene-looks` skill for what each knob does to the look.

5. **Texture and material consolidation** (raster thread). Fewer distinct textures and materials means fewer state changes and binds per frame. `TextureAtlas` (with `generateSolidColorAtlasPixels` for placeholders) packs many tiles into one texture so one material covers them all; share a single `Material` instance across many nodes instead of constructing one per node; use `MaterialsVariantsComponent` to switch a model between named material sets rather than duplicating materials.

6. **Static shadows** (raster thread). `Node.shadowStatic = true` promises a caster's geometry, material coverage, and world transform will not change while mounted, so the engine renders it into cached shadow-map tiles reused across frames instead of re-encoding every caster every frame. A large static world becomes dramatically cheaper to shadow. Flag only genuinely static content; a static node that moves shows stale shadows until its render item re-registers.

## First-draw pipeline stalls (the other kind of slow)

Percentiles clean but the **worst** frame is tens to hundreds of milliseconds, at boot, on the first placement, the first effect, the first hover? That is not steady-state cost. Each (vertex shader, fragment shader, vertex layout) triple compiles a backend pipeline synchronously on its first draw, and a heavy custom material can cost 100ms+ on that one frame.

- **Debug builds name the offenders.** Any pipeline build of 8ms or more prints `flutter_scene: pipeline build took ...` with the material and geometry. Play through the moments that hitch and collect the list; fix the list, not a guess.
- **The fix is pre-warming, not optimization.** The compile happens exactly once; move it where nobody sees it. Draw each named material once behind a load screen or during an intro, at tiny scale inside the frustum (a frustum-culled or `visible: false` node never draws, so it warms nothing).
- **Warm through the real builders.** The pipeline key includes the vertex layout, so a placeholder sphere warms a different pipeline than the real mesh. Build the actual tower/effect/overlay through its normal code path.
- **Keep warmup draws brief.** One frame compiles the pipeline. A material that samples scene depth also forces the full-resolution depth prepass while it is live, so a lingering warmup shows up as raster cost.
- **Do not trust repeat measurements.** GPU drivers cache compiled shaders across runs, so the second profiling session hits caches the first did not. First-run cost is what a fresh install pays.

## More depth

`references/performance.md` expands each step with the full API and when it helps, the UI-vs-raster symptom map (what a wrong frame time points to), and the honest note on what measurement tooling actually exists.
