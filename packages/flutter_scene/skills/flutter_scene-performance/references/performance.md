# flutter_scene performance reference

Companion to the `flutter_scene-performance` skill. The skill states the budget, the measure-first rule, and the fixed remediation order. This file expands each step with the real API, when it helps and when it does not, the diagnosis that maps a wrong frame time to a thread, and an honest account of the measurement tooling.

Verify any symbol here against `lib/src` before relying on it; the inventory in the `flutter_scene-idioms` skill (`references/what-exists.md`) is the fuller API map.

## The two threads, concretely

A frame is built on the UI thread and drawn on the raster thread, and they overlap across frames (frame N rasters while frame N+1 builds). Either thread over budget drops the frame.

- **UI thread work** is Dart. flutter_scene walks the scene graph, computes world transforms, runs frustum culling, ticks every component's `update`, and encodes the draw list. Cost scales with node count, component count, and how much per-frame Dart you run in `onTick` or component `update`.
- **Raster thread work** is the GPU. Impeller executes the encoded passes, the shadow pass, the main color pass, and every enabled screen-space post-processing pass. Cost scales with pixels drawn, overdraw, shadow-map resolution, and how many post passes are on.

## Diagnosis, symptom to thread

Read the two thread graphs in DevTools (or the performance overlay) and match the over-budget one to a cause.

| Observation | Over-budget thread | Likely cause | Go to step |
| --- | --- | --- | --- |
| UI time high, raster fine | UI | Too many nodes/draws or heavy per-frame Dart | 1 instancing, 3 culling |
| UI time scales with object count | UI | Thousands of separate nodes for one repeated mesh | 1 instancing |
| UI time high with a huge static world | UI | No culling; whole graph walked every frame | 3 culling |
| Raster time high, UI fine | Raster | Too many pixels or post passes | 4 post stack, 5 consolidation |
| Raster time high, and it tracks resolution | Raster | Fill-bound; too many pixels | 4 `renderScale`, AA |
| Raster spikes only when shadows are on | Raster | Every caster re-encoded per frame | 6 static shadows |
| Raster time tracks the number of distinct materials | Raster | State-change churn from per-node materials/textures | 5 consolidation |
| Jank only on phone or web, smooth on desktop | Whichever is over budget there | Desktop GPU was hiding it | measure on the real target |

If both threads are near budget, fix the UI thread first (steps 1 to 3); a lighter draw list also lightens the raster thread.

## Measurement tooling, honestly

There is **no built-in frame-stats API in flutter_scene**. No `scene.frameTime`, no draw-call count, no visible-triangle count. Do not invent one or claim one exists.

- **Profile mode is mandatory.** `flutter run --profile --enable-flutter-gpu`. Debug builds carry assertions and skip AOT optimization, so their timings do not reflect a release build. A number taken in debug mode is not a performance number.
- **DevTools Performance view** is the primary tool. It shows per-frame UI time and raster time as two tracks, flags janky frames, and lets you expand a frame's timeline. This is what tells you which thread is over budget.
- **The performance overlay** gives the same two thread graphs in-app for a quick read without attaching DevTools.
- **A `Stopwatch`** around the per-frame work (the `onTick` body, or a component `update`) is a coarse UI-thread fallback. It cannot see the raster thread at all, so a good stopwatch number does not clear a raster-bound jank.
- **Editor MCP.** `get_app_state` reports lifecycle only (launching/running), not timing. The one place per-pass GPU timings surface is a render-graph capture (`Scene.captureRenderGraph`, or the editor MCP capture tool), whose result carries per-pass timing and lets you see which post pass is expensive. That is per-pass GPU detail, not a whole-frame counter, and the editor MCP is not connected in every project. When it is not, the DevTools loop above is fully sufficient.

## Step 1, instancing

`InstancedMesh` holds one `geometry`/`material` pair and one transform per copy. The whole set encodes as a single draw and, by default, a single frustum cull test.

```dart
final mesh = InstancedMesh(
  geometry: someGeometry,
  material: sharedMaterial,   // one material for the whole batch
);
for (final placement in placements) {
  mesh.addInstance(placement.transform, color: placement.tint); // matrix is cloned
}
scene.add(Node()..addComponent(InstancedMeshComponent(mesh)));
```

- `addInstance(Matrix4, {Vector4? color})` returns an index; the matrix is cloned, so mutating your copy afterward is safe. Per-instance `color` is a linear RGBA multiplier.
- Edit later with `setInstanceTransform(i, m)`, `setInstanceColor(i, color)`, `removeInstanceAt(i)`, `clearInstances()`, or move the whole batch in one pass with `updateInstanceTransforms((list) { ... })`.
- **Culling default.** `cullInstances` defaults to `false`, so the batch is culled as one unit against its combined bounds, not per instance. Turn `cullInstances: true` on only for a batch spread across a large area where many instances are off-screen, since per-instance culling adds CPU work.
- **When it helps.** Repeated geometry, foliage, crowds, tiles, debris, particles-as-meshes. It is the largest UI-thread win available, because N separate nodes become one. It does nothing for a scene of distinct meshes.
- **Winding trap.** A mirrored (negative-determinant) instance edited with `updateInstanceTransforms(recomputeWinding: false)` renders inside-out. Keep instance edits orientation-preserving, or let winding recompute.

See the `flutter_scene-procedural` skill for the full scatter-on-terrain pattern.

## Step 2, level of detail

`LodComponent(List<LodLevel>)` draws one of several mesh variants per frame, chosen from how large the object appears on screen.

```dart
node.addComponent(LodComponent([
  LodLevel(geometry: high, material: mat, screenSize: 0.4),
  LodLevel(geometry: mid,  material: mat, screenSize: 0.15),
  LodLevel(geometry: low,  material: mat, screenSize: 0.04), // set 0.0 to never cull
]));
```

- `screenSize` is the projected bounding-sphere diameter as a fraction of viewport height. Levels are highest detail first, strictly descending. The engine draws the highest-detail level whose threshold the object still meets, and draws nothing below the last threshold (the cull floor).
- Selection is screen-size based, so it is field-of-view aware and resolution independent, and it is per view (a split-screen frame can pick different levels per view).
- `LodComponent(levels, {lodBias = 1.0, hysteresis = 0.1, blendRange = 0.0})`. `lodBias` above `1` keeps detail farther away; `hysteresis` is a dead-band so an object on a boundary does not flip-flop; `blendRange` above `0` dither-cross-fades adjacent levels to remove the pop (honored by the built-in lit and unlit materials).
- **Limitation that matters for shadows.** The shadow and depth-prepass passes always draw the highest-detail level and ignore the LOD cull. So LOD lightens the color pass, not shadow or depth cost. A shadow-heavy scene needs step 6, not LOD.
- **Not for instanced draws.** A `LodComponent` draws a single mesh and picks one level for the whole node; it does not combine with hardware instancing.

## Step 3, culling

Skip work for things the camera cannot see.

- **`Node.frustumCulled`** (default `true`) skips a subtree whose `combinedLocalBounds` do not intersect the camera frustum. Leave it on. Set it `false` only where the cached bound is known-stale or misleading (procedural geometry you regenerate, large terrain pieces). A subtree that reports no bound (skinned content, geometry without a computable bound) is treated as always visible regardless of the flag.
- **`RenderView.cullingPlanes`** (`List<Plane>`, default empty) adds extra clip planes beyond the frustum, for portal or region culling.
- **Layers.** `node.layers` (a 32-bit mask, default `kRenderLayerDefault` which is layer 0, not inherited by children) against `RenderView.layerMask` (default `kRenderLayerAll`) decides whether a view draws a node at all, when `node.layers & view.layerMask != 0`. Put editor gizmos, an inset viewport's contents, or a minimap's set on their own layer and give each view the mask it needs, so a view skips whole sets cheaply.
- **When it helps.** Large worlds where much of the graph is off-screen each frame. Culling is a UI-thread win (fewer nodes encoded) that also lightens the raster thread (fewer draws).

## Step 4, shrink the post stack

Every screen-space effect is a raster-thread pass. Turning off what you do not need is the most direct raster win. All the scene-wide look fields live on `EnvironmentSettings` (see the `flutter_scene-looks` skill); each effect has an `*Enabled` flag, off by default.

- **Turn effects off.** `ambientOcclusionEnabled`, `screenSpaceReflectionsEnabled`, `godRaysEnabled`, `depthOfFieldEnabled`, `bloomEnabled`, and the rest default `false`. A preset the app copied may have turned several on; drop the ones the scene does not visibly need. Ambient occlusion, screen-space reflections, god rays, and depth of field are the heavy ones.
- **Half-resolution AO.** `ambientOcclusionHalfResolution` defaults `true`; keep it. Full-resolution AO roughly doubles that pass's cost for little visible gain on most content.
- **Cheaper depth of field.** `depthOfFieldQuality` (`DepthOfFieldQuality.low`/`medium`/`high`, default `medium`) trades gather taps and cleanup passes for time. Step it down to `low` on mobile.
- **Render fewer pixels.** `Scene.renderScale` (default `1.0`), or per-view `RenderView.renderScale`, renders the scene at a fraction of resolution and upscales. Dropping to `0.75` cuts fill cost by nearly half and is often barely visible after anti-aliasing. This is the biggest lever for a fill-bound (resolution-tracking) raster time.
- **Step anti-aliasing down.** `Scene.antiAliasingMode`. `AntiAliasingMode.auto` picks `msaa` where supported else `fxaa`. `msaa` is cheap on mobile tilers and highest quality; `fxaa` is a single post pass on every backend; `smaa` is cleaner than `fxaa` but three post passes (~3x its cost), so step it down to `fxaa` or `none` on a raster-bound target; `none` is free. Read what actually runs with `Scene.effectiveAntiAliasingMode`.
- **Do not re-capture reflection probes per frame.** A `ReflectionProbeComponent` capture (or `Scene.captureEnvironment`) renders the scene six times, a large one-frame spike. Let it capture once on activate and only call `requestCapture()` when the scene visibly changes, never every frame.
- **When it helps.** Any raster-bound scene. The `clean` look in the looks skill is nearly free; a full `moody` stack (AO plus SSR plus god rays plus DoF plus grain) is the heaviest. Do not stack all of those on a low-end target without profiling.

## Step 5, texture and material consolidation

Every distinct material and texture is a potential state change and bind on the raster thread. Fewer of them means a shorter, cheaper draw list.

- **`TextureAtlas`** packs many equally sized tiles (voxel faces, sprite sheets, terrain tiles) into one texture, so a single material and draw call cover every tile. Resolve a tile's UV box with `tileBounds(index)` or map a within-tile coordinate with `tileUv(index, u, v)`, write those into the mesh's texture coordinates, and build the bound material with `toMaterial()`. `generateSolidColorAtlasPixels(tileColors:, columns:, tileSize:, padding:)` builds placeholder pixels to bring the atlas path up before real art exists.
- **Share one `Material` instance** across many nodes rather than constructing a new one per node. Identical materials that are separate objects still churn binds; the same object does not. Build the material once and reuse the reference.
- **`MaterialsVariantsComponent`** switches an imported model between its named `KHR_materials_variants` sets in place (`MaterialsVariantsComponent.of(model)?.select('name')`), instead of duplicating a model per look. Read `variants` for the declared names; `select(null)` restores defaults.
- **When it helps.** Scenes whose raster time tracks the count of distinct materials or textures, tile-based worlds, and models shown in several finishes.

## Step 6, static shadows

Shadow casting re-encodes every caster into the shadow map each frame by default. `Node.shadowStatic = true` promises a caster will not change and lets the engine cache its shadow-map tiles across frames.

```dart
staticWorldNode.shadowStatic = true;  // set per mesh-bearing node; not inherited
```

- **The contract.** The node's geometry, material coverage, and world transform must not change while mounted. In return, the engine renders it into cached shadow-map tiles reused across frames instead of re-encoding it every frame. Dynamic nodes (the default) still cast per-frame shadows on top of the cache, so a moving character over a static world works.
- **Not inherited.** Set it on each mesh-bearing node, not once on a root.
- **Stale-shadow caveat.** A static node that does change (moves, remeshes, edits material coverage) shows stale shadows until its render item re-registers. Flag only genuinely static content.
- **Displacement caveat.** A material with a `vertex { }` displacement stage should stay dynamic, since its cached shadow would not follow a camera-dependent displacement.
- **When it helps.** Large static worlds with a shadow-casting `DirectionalLight`. The win scales with how many static casters you have; a mostly static level with a few moving actors is the ideal case.

## Order and stopping

Fix the measured over-budget thread first, top-down within it, and re-measure after each change so cause and effect stay legible. Stop when the frame chart clears budget on the real target; there is no reason to keep optimizing a thread that is already under budget while the other one janks. The whole point of measuring first is to avoid spending a step's effort on the thread that was never the problem.
