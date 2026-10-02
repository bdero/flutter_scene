# Depth and layering

Two surfaces that cover the same pixels at nearly the same depth flicker against each other as the camera moves (z-fighting). One screenshot rarely shows it, because each frame picks a winner and a different frame picks the other one. This page covers why it happens, the overlaps generated scenes make most, how to fix each, and how to prove a scene is clean.

## Why surfaces fight

**Exact overlaps.** Two faces in one plane built from different vertices each compute their depth from their own rounded vertex positions and from the rasterizer's sub-pixel snapping. The difference is noise whose sign changes across the surface and with any camera motion. On a surface seen at a grazing angle that noise is large, a fraction of a pixel's worth of the surface's own depth slope. No near plane, depth format, or precision fixes an exact overlap; only an order does (a layer, a content change).

**Near overlaps.** Two parallel faces a few millimetres or centimetres apart hold their order up close and fight past the distance where the depth buffer can no longer separate them. flutter_scene spends depth precision where content is: it fits the near plane it rasterizes with to visible geometry every frame, and on Metal and most browsers it stores reversed float depth, which keeps precision nearly even with distance. The `depthGap` debug view (below) shows how far apart two surfaces must be at each pixel.

## The overlaps generated scenes make, and the fix for each

| Pattern | Why it fights | Do instead |
| --- | --- | --- |
| A fence, barrier, curb, or rail of repeated pieces longer than their spacing (8.4 m pieces every 8 m) | every joint holds two faces in one plane, and alternating colors make it visible | make each piece exactly as long as the spacing, or put a slightly larger post at each joint |
| Perpendicular runs that both extend into a corner | the corner holds overlapping faces | stop one run at the other's face, or cap the corner with a post |
| Ground patches, tiles, or rugs at one height that overlap each other | same-height faces of different colors | place them without overlap (`PoissonDiscSampler` in the kit), or give each overlapping kind its own `depthLayer` |
| A screen, sign, window, poster, or road marking flush with (or a few millimetres off) its surface | exact or near overlap | `material.depthLayer = 1` on the overlay; 2 for an overlay on that overlay |
| A box wrapped by a slightly larger box (window bands, trim, a frame) | parallel faces a few centimetres apart, seen from far away | keep the wrap a clear distance proud, put wraps on separate height slots so two never overlap, or bake the detail into the material |
| The same mesh added twice (a duplicated node, a model loaded into two parents) | bit-identical faces | remove the duplicate |
| `doubleSided` forced on materials whose meshes have back-to-back faces | culling no longer hides the coincident faces | leave `doubleSided` off unless the mesh needs it |
| An object placed at a guessed surface height | it hovers or sinks a few centimetres, or sits exactly in the surface | measure the surface with `scene.raycast` or the asset's bounds before placing |

## Mechanisms, in order of preference

1. **Fix the content.** Abut, space, or merge the pieces. Nothing fights when nothing overlaps.
2. **`Material.depthLayer`.** For an overlay that lies on a surface. A higher layer draws over coplanar surfaces with a lower one at any distance and on every backend. Each layer moves the surface a quarter pixel of its own depth slope plus a few depth steps toward the camera, in the vertex stage, so it costs nothing per fragment and moves nothing on screen by more than a fraction of a pixel. Negative layers let a ground yield to everything on it. Two different materials at the same layer that overlap still fight.
3. **`DecalNode`.** Projects a mark onto uneven surfaces without creating coplanar geometry.
4. **Bake detail into the material.** A grid of lit windows as a pattern in a `.fmat` instead of thousands of boxes on a facade.
5. **`Material.depthBias`.** A world-space nudge toward the camera. It buys fewer depth steps the farther away it is seen, so it holds up close and fails far away. Prefer `depthLayer`.
6. **`Scene.coplanarTieBreak`.** An experimental safety net for generated content. It gives every unlayered material and instance an arbitrary rank so exact overlaps resolve to a stable winner. The rank is arbitrary, so an overlay can end up consistently hidden, and surfaces a sliver apart far from the camera can swap. Fix the overlap or set `depthLayer` instead where you can.

## The camera

Leave `near` at its default unless geometry clips. The engine rasterizes with the largest near plane that clips nothing visible and keeps the authored one as a floor, so a chase or aerial camera gets the precision of a much larger near for free (`Scene.fitNearPlane`, on by default). The fit falls back to the authored near when the camera sits inside an item's bounds (a sky sphere, one merged city mesh) or an item has no bounds; debug builds print which node blocked it. Draw a sky with `scene.skybox` rather than a giant sphere around the camera.

`Scene.reversedDepth` (on by default) stores depth reversed, which keeps float depth precise at every distance. Turn it off only for a custom `ShaderMaterial` vertex shader that writes clip-space depth assuming the standard mapping.

## Proving a scene is clean

Check in motion, with numbers, not with a screenshot.

- **`await scene.probeDepthConflicts()`** renders the view's object ids several times (reversed draw order, changed depth rounding, sub-pixel camera offsets, and surfaces nudged a sliver apart) and reports every pair of nodes whose pixels change hands. `report.conflicts` is empty when nothing fights; `report.describe()` is a short log with node paths, pixel counts, and distances. Probe from the cameras the app actually uses, after the scene has rendered a frame. Surfaces sharing a material still count, since vertex colors or texture coordinates can tell them apart. Blended surfaces and a `.fmat` cut by its own `Surface()` are listed in `report.untested` rather than tested.

  ```dart
  final report = await scene.probeDepthConflicts(camera: camera);
  if (report.conflicts.isNotEmpty) debugPrint(report.describe());
  ```

- **`scene.findCoplanarOverlaps()`** checks the geometry without rendering and returns every pair of faces that overlap in one plane (or sit closer than the depth buffer can separate from the camera), with the overlap area, where it is, and for repeated pieces the length that fixes it. Unlike the probe, it also catches instances of one `InstancedMesh` whose colors differ overlapping each other. Debug builds run it once the scene holds still and print a summary; set `scene.debugCheckCoplanarOverlaps = false` to silence it.
- **`scene.debug.overlays.add(DebugOverlay.depthConflicts)`** marks fighting pixels live with a crawling magenta checkerboard.
- **`scene.debug.view = const DebugView(channel: SurfaceDebugChannel.depthGap)`** colors each pixel by the gap two surfaces need there to keep their order, blue for a hundredth of a millimetre through red for a metre. An overlay closer to its surface than that gap needs a layer.
- **`SurfaceDebugChannel.objectColor`** shows two node colors interleaving where they fight.

The tells of a fight without tools: a material edit that changes nothing on screen (the other surface is winning there), a surface that looks right from one camera only, stripes or speckles that crawl as the camera moves, and flicker that only appears at grazing angles or far away.

## Habits that do not work

- **`Node.renderOrder` does not order opaque coplanar faces.** Depth decides between them, not draw order.
- **Turning off the depth test** draws the overlay through everything in front of it.
- **Forcing `doubleSided` broadly** exposes coincident back faces.
- **Shrinking the far plane** barely changes precision; the near plane dominates, and the engine already fits it.
- **A tiny fixed world offset** for distant content fails past a distance; use `depthLayer`.
- **Polygon offset factors** have no API here; `depthLayer` is the slope-aware offset.
