# flutter_scene silent-failure traps

Mistakes that produce wrong pixels with no exception and no console message. Each entry gives the
mistake, what you see, and what to do instead. Sorted worst-first (most likely to hit, hardest to
diagnose from the symptom).

Some of these are now caught by the engine in version 0.22.0. Those are tagged **[0.22.0 catches
this]** with what the engine does, so if you see that error you know what it means. The rest are
still silent, so you have to recognize them yourself.

---

## 1. Editing a transform in place instead of assigning it

**Mistake.** `node.localTransform.setTranslation(v)`, `node.localTransform..rotateY(t)`,
`node.position.x = 5`, or any edit of the matrix/vector a getter returns. This is the natural
`vector_math` style and the first thing most people reach for.

**Symptom.** The node does not move. Not "moves wrong", nothing happens, forever, including its
children and bounds. Reading `node.localTransform`/`node.position` back shows the value you wrote, so
the state looks correct while the render disagrees.

**Do instead.** Assign a fresh value (`node.position = ...`, `node.localTransform = node.localTransform.clone()..translateByVector3(v)`),
use the component setters `node.position`/`node.rotation`/`node.scale`, or edit the raw matrix
through `node.mutateLocalTransform((m) => m.translateByVector3(v))`, which dirties the cache for you.

**[0.22.0 catches this]** Debug builds throw a `StateError` naming the node and the fix, both for an
in-place `localTransform` edit and for editing a copy returned by `position`/`rotation`/`scale`.

---

## 2. Passing a normal or metallic-roughness map as `TextureContent.color`

**Mistake.** `material.normalTexture = await Texture2D.fromAsset('brick_normal.png')` without
`content: TextureContent.normal`. The `content` parameter defaults to `color`.

**Symptom.** The base mip is fine, so it looks right up close and progressively wrong with distance:
normals flatten and skew, roughness reads too smooth at range, specular shimmers. A
distance-dependent symptom is nearly the worst case for screenshot-driven iteration.

**Do instead.** Build non-color maps with the right content: `Texture2D.fromAsset(path, content:
TextureContent.normal)` for normal maps, `TextureContent.data` for metallic-roughness, AO, and other
linear data. Still silent, so this is on you.

---

## 3. Non-uniform scale on a lit mesh

**Mistake.** Any non-uniform scale on the node or an ancestor, e.g. `node.scale = Vector3(1, 3, 1)`.

**Symptom.** Lighting, specular, and reflections are wrong across the whole mesh. It reads as a
shading or material bug, so it sends you into the materials, never the transform.

**Do instead.** Use a uniform scale, or bake the non-uniform scale into the geometry with
`MeshData.transformed(matrix)` and build a fresh `MeshGeometry` from it. Still silent.

---

## 4. Moving a skinned mesh node

**Mistake.** `skinnedNode.localTransform = Matrix4.translation(v)` on a node that carries a `Skin`.

**Symptom.** The mesh does not move. Worse, it *does* move when the node you transformed happens to
be an ancestor of the skeleton's joints, so it looks intermittent across models.

**Do instead.** glTF requires a skinned mesh node's own transform to be ignored, so the engine passes
identity. Move the skeleton root (the common ancestor of `skin.joints`) instead, or parent both the
mesh node and the skeleton under a shared node and move that. Still silent.

---

## 5. Replacing the transform of a runtime-imported model root

**Mistake.**
```dart
final model = await Node.fromGlbAsset('assets/ship.glb');
model.localTransform = Matrix4.translation(v);   // wipes the handedness flip
```

**Symptom.** The model renders mirrored through Z (asymmetric geometry reversed, text backwards) with
normals and IBL wrong for the mirrored orientation. It still draws and is not obviously broken.

**Do instead.** The runtime glTF importer synthesizes a root carrying a `scale(1, 1, -1)` handedness
flip. Do not overwrite it. Parent that node under a new `Node` and transform the parent, or
pre-multiply your transform by the existing `localTransform`. (The offline `.fscene`/`loadScene` path
bakes handedness into the vertices, so its roots are identity and do not have this trap.) Still
silent.

---

## 6. `EnvironmentMap.fromGpuTextures` with a raw panorama

**Mistake.**
```dart
final tex = await gpuTextureFromAsset('assets/panorama.png');
scene.environment = EnvironmentMap.fromGpuTextures(prefilteredRadiance: tex);
```

**Symptom.** Every reflective surface (and the sky) shows the top 1/8 of the panorama stretched 8x
vertically, cross-fading between slices as roughness varies. Diffuse is fully black.

**Do instead.** `fromGpuTextures` expects an already-prefiltered radiance atlas, not a plain image.
Run the source through `prefilterEquirectRadiance()` first, or just use
`EnvironmentMap.fromEquirectImageAsset(assetPath: ...)`/`fromUIImages`, which prefilter and project
SH for you. Still silent.

---

## 7. `ShaderMaterial(cullingMode: none)` for a double-sided custom material

**Mistake.** `ShaderMaterial(cullingMode: gpu.CullMode.none)`, or setting `doubleSided = true` on a
`ShaderMaterial`. The two do not agree.

**Symptom.** `cullingMode.none` draws back faces in color but leaves them out of the depth prepass, so
SSAO, SSR, and contact shadows sample the wrong surface exactly where a back face shows: dark halos,
wrong reflections, occlusion bleeding through a leaf card. `doubleSided = true` does the opposite: the
color pass still culls while the prepass draws the extra faces.

**Do instead.** For a truly double-sided `ShaderMaterial`, understand that the color cull and the
prepass cull are driven separately today; keep the mesh single-sided where the depth-based effects
need to match, or split it. Still silent.

---

## 8. Caller-supplied `bounds` that do not cover the geometry

**Mistake.** `MeshGeometry.fromArrays(positions: p, bounds: someAabb)` where the AABB does not contain
every position, or `setLocalBounds` with a guessed or stale box.

**Symptom.** The mesh pops out of existence at some camera angles and reappears at others; part of a
large mesh vanishes; shadows disappear before the caster does. Intermittent and view-dependent, so a
single screenshot can look fine.

**Do instead.** Widen the bounds to cover every vertex, or just omit the `bounds` argument and let the
constructor scan the positions. An absent bounds is safe (it means always-visible); only a wrong one
is dangerous. Still silent.

---

## 9. Binding a mipless texture to a material

**Mistake.** `material.baseColorTexture = GpuTextureSource(await gpuTextureFromAsset('brick.png'))`.
The helper's own doc even recommends this.

**Symptom.** Severe minification aliasing: crawling and shimmering on any surface at an angle or
distance, sparkling on a metallic-roughness map. `Texture2D.fromAsset` on the same file looks fine, so
two seemingly equivalent APIs disagree visually.

**Do instead.** Use `Texture2D.fromAsset`/`fromImage`/`fromPixels`, which generate a mip chain, or
supply a texture you mipped yourself. Reserve `gpuTextureFromAsset` for non-material uses. Still
silent.

---

## 10. `RenderView.layerMask`/`Node.layers` mismatch, or a zero mask

**Mistake.** Putting a node on a non-default layer and forgetting the view side (or vice versa), or
`layerMask: 0`, or `Node.layers = 2` meaning to select "layer 2" (which is actually `1 << 2 == 4`).

**Symptom.** A node, a group, or the whole scene is simply absent, with no hint a mask is involved. A
`layerMask` of 0 renders nothing.

**Do instead.** `Node.layers` is a bitmask and is NOT inherited by children, so set it on each node
you want the view to see. Use `kRenderLayerAll` to see everything, or a bitmask like `(1 << 2)`.
Match the view's `layerMask` to the nodes' `layers`. Still silent (but see #23 for the
draws-nothing diagnostic).

---

## 11. Mutating a `TextureTransform` in place

**Mistake.** `material.baseColorTextureTransform.offset.x = 0.5` instead of assigning a fresh
`TextureTransform`. Same shape as trap #1, for materials.

**Symptom.** UV scroll/rotation animation freezes at the first value, but ONLY for materials on the
physical-variant path (any material with clearcoat/sheen/transmission/etc). The identical code works
on a plain PBR material, so it reads as a shader bug.

**Do instead.** Assign a new transform each frame: `material.baseColorTextureTransform =
TextureTransform(offset: ...)`. Still silent.

---

## 12. Environment image that is not 2:1 equirectangular

**Mistake.** Passing a cube cross, a 1:1 angular light probe, or a cropped panorama to any environment
entry point. HDRI downloads are not reliably 2:1.

**Symptom.** The scene is lit from wildly wrong directions, reflections show mirrored or duplicated
content, the sky is smeared.

**Do instead.** Re-project the source to a 2:1 latitude-longitude panorama before loading. Cube
crosses and angular probes are not supported. Still silent.

---

## 13. Hand-built triangles wound clockwise

**Mistake.** Generating triangles with clockwise winding instead of the standard Counter-Clockwise (CCW)
right-handed convention when feeding `MeshGeometry.fromArrays` or `GeometryBuilder`.

**Symptom.** The mesh is invisible from outside and visible from inside; a closed shape looks hollow
or inside-out; lighting is inverted where it shows. ("See-through faces.")

**Do instead.** flutter_scene's front faces wind COUNTER-CLOCKWISE (CCW) in model space, matching glTF
and standard 3D conventions. Ensure triangle indices wind CCW around the outward face normal, or omit
`normals` and let `GeometryBuilder` derive them from your winding. Still silent.

---

## 14. Out-of-range indices in `fromArrays`

**Mistake.** `MeshGeometry.fromArrays(positions: p /* 100 verts */, indices: [0, 1, 100])`, e.g. from
an off-by-one or an index list built against a different vertex array.

**Symptom.** Stray triangles stretching to the origin or infinity, holes, flicker. On some backends
the fetch is clamped and on others it reads adjacent memory, so the symptom differs per backend.

**Do instead.** Keep every index in `0 .. vertexCount - 1`. (`GeometryBuilder.addTriangle` range-checks
for you and throws; the `fromArrays` index path does not.) Still silent on the `fromArrays` path.

---

## 15. A `vertexCount` that does not match the buffer in `setVertices`

**Mistake.** `geometry.setVertices(bufferView, vertexCount)` where `vertexCount` is a byte count, a
float count, or a triangle count rather than a vertex count.

**Symptom.** Too small: part of the mesh is missing. Too large: the draw reads past the buffer, giving
stray geometry or a dropped draw depending on backend. The buffer is fine, so the investigation goes
to the packing code.

**Do instead.** `vertexCount` is a count of vertices. Prefer `uploadVertexData` (which validates the
stride, see #17) or `fromArrays` over the caller-managed `setVertices` path unless you really own the
GPU buffer. Still silent.

---

## 16. Oversized texture on a low-end device

**Mistake.** `EnvironmentMap.fromEquirectImageAsset(assetPath: 'pano_16k.hdr', maxWidth: 16384)` or
`EnvironmentMap.radianceCubeSize = 4096` on a device whose max texture size is lower.

**Symptom.** A completely black environment: no IBL, no reflections, black sky. Works on the dev
machine, black on a phone.

**Do instead.** Keep environment and texture sizes within the device limit; lower `maxWidth` or
`radianceCubeSize`. Test on the lowest-end target you support. Still silent.

---

## 17. Hand-packing vertex bytes at the wrong stride

**Mistake.** `SkinnedGeometry()..uploadVertexData(bytes, vertexCount, indices)` with the wrong stride
(a common one is 96 bytes having forgotten UV1, or the legacy 80-byte layout).

**Symptom.** Washed-out colors, see-through faces, geometry smeared toward the origin.

**Do instead.** Unskinned vertices are 72 bytes (position 3, normal 3, tex_coords 2, tex_coords_1 2,
color 4, tangent 4, all float32), skinned are 104 (+ joints 4, weights 4). Better, do not hand-pack:
use `MeshGeometry.fromArrays`, `fromMeshData`, or `GeometryBuilder`.

**[0.22.0 catches this]** `uploadVertexData` on both `SkinnedGeometry` and `UnskinnedGeometry` now
throws an `ArgumentError` when the byte length does not match `vertexCount * stride`, naming the
expected layout.

---

## 18. Custom attribute length not matching the vertex count

**Mistake.** `geometry.setCustomAttribute('a_wind', data, components: 3)` where `data` has the wrong
length, or set before uploading vertices, or not re-set after a `rebuild` changed the count.

**Symptom.** The attribute is read at the wrong stride, so every vertex gets a neighbor's value: a
displacement shader shears the mesh, a color attribute smears. Nearly right, so hard to spot.

**Do instead.** `data.length` must equal `vertexCount * components`. Set the attribute after uploading
vertices, and re-set it after any rebuild. Also note custom attributes are not fetched by depth/shadow
passes, so an attribute-driven displacement will not show in shadows.

**[0.22.0 catches this]** `setCustomAttribute` now throws an `ArgumentError` on a length mismatch
(once the vertex count is known).

---

## 19. `UnlitMaterial` with `AlphaMode.mask`

**Mistake.** `UnlitMaterial(colorTexture: foliage)..alphaMode = AlphaMode.mask` for cutout foliage.

**Symptom.** No alpha test. Cutout edges render soft and blended, the material goes through the
translucent pass, writes no depth, sorts badly against itself, and casts no cutout shadow.

**Do instead.** `UnlitMaterial` does not implement `mask` (it behaves as `blend`). Use
`PhysicallyBasedMaterial` for cutouts, or a `.fmat` unlit material that discards below your cutoff.
Still silent.

---

## 20. `vertexColorWeight` on a material that took a physical variant

**Mistake.**
```dart
final m = PhysicallyBasedMaterial()..vertexColorWeight = 0.0;
m.clearcoat = 1.0;   // or sheen/transmission/anisotropy/ior != 1.5/any extension texture
```

**Symptom.** Vertex colors snap back to full strength the moment an unrelated extension is enabled.
On a vertex-colored import, an abrupt tint change with no plausible cause. (The same gap silently
drops `specularAntiAliasingVariance` and `specularAntiAliasingThreshold` on the variant path.)

**Do instead.** Leave `vertexColorWeight` at 1.0 when using any advanced PBR feature, or drop the
extension. Still silent.

---

## 21. Vertex-stage binding on a `ShaderMaterial` with no vertex shader

**Mistake.**
```dart
final m = ShaderMaterial(fragmentShader: frag);
m.setUniformBlock('WaveInfo', bytes, stage: ShaderStage.vertex);   // never set a vertex shader
```

**Symptom.** The vertex-stage parameter has no effect; geometry stays undisplaced while the fragment
stage looks right. Reads as "my vertex shader is not running."

**Do instead.** Pass a `vertexShader` (and `skinnedVertexShader`/`depthVertexShader` for those mesh
kinds) to the constructor before binding vertex-stage blocks, or bind the block on
`ShaderStage.fragment`. Still silent.

---

## 22. A `ShaderMaterial` vertex shader on line/trail/polyline geometry

**Mistake.** Attaching a `ShaderMaterial` that supplies a vertex shader to a `LineSegmentsGeometry`, a
trail, or a polyline.

**Symptom.** Lines vanish or explode into garbage. The unskinned vertex shader is paired with the
line-segments instanced layout and never does the ribbon expansion.

**Do instead.** These geometries do their vertex expansion in the engine's own shader; a material
vertex shader cannot be used with them. Drop the vertex shader for line/trail/polyline geometry, or
use a mesh geometry. Still silent.

---

## 23. Four different causes of a blank frame

**Mistake.** Any of: a degenerate camera (target equals position, or `up` parallel to the view
direction, e.g. a top-down camera left at the default `up`), a field of view passed in degrees
(`fovRadiansY: 60`), an inverted or zero frustum, `layerMask: 0`, a zero-area draw region, or
rendering before `Scene.isReadyToRender`.

**Symptom.** The entire scene is empty. Every one of these looks identical, so it is easy to "fix"
lighting, materials, and geometry for many iterations before suspecting the camera or the mask.

**Do instead.** For a top-down/bottom-up camera set `up` to `Vector3(0, 0, 1)` or `Vector3(0, 0,
-1)`, not the default `(0, 1, 0)`. Pass FOV in radians (`60 * degrees2Radians`). Keep `near > 0` and
`far > near`. Give the view a non-zero `layerMask` and a non-empty draw region.

**[0.22.0 catches most of this]** Degenerate cameras (zero view direction, parallel `up`, degrees-valued
FOV, degenerate near/far) assert in debug. And a frame that issues zero draw calls now prints once in
debug naming the likely cause (not ready, empty region, no views, no visible meshes, or a layer mask
matching nothing).

---

## 24. Missing bounds after swapping a primitive's geometry

**Mistake.** `mesh.primitives[0].geometry = newGeometry` for hand LOD, a rebuilt procedural mesh, or a
variant swap.

**Symptom.** The new geometry is culled against the old geometry's bounds; if it is larger or
displaced, it pops in and out exactly like trap #8.

**Do instead.** Nothing extra is needed anymore.

**[0.22.0 catches this]** A `Mesh` now recomputes its bounds on its own when a primitive's geometry
identity changes, so the manual `markLocalBoundsDirty()` is no longer required.

---

## 25. A `.fmat` material that overruns the 15-sampler budget

**Mistake.** A `lit` or `physical` `.fmat` declaring several `sampler2d` parameters plus
`engine_inputs: [scene_color, scene_depth]`, on top of the lit framework's own textures.

**Symptom.** Geometry disappears on a mid-range Android device while everything is correct on Metal,
with no build-time signal. The draw is rejected on GLES drivers reporting the 16-unit minimum.

**Do instead.** The lit fragment shader budgets 15 fragment samplers. Pack channels into one texture
(an ORM-style atlas), drop an `engine_input`, or make the material unlit. Still silent (fails at
runtime on the device, not at build).

---

## 26. `RenderView.viewport` with a `target` set

**Mistake.** `RenderView(camera: cam, target: myRenderTexture, viewport: Rect.fromLTWH(0, 0, 0.5, 1))`
expecting a half-width render into the texture.

**Symptom.** The view fills the entire render texture; the passed `viewport` is ignored. Reads as
"my viewport math is off."

**Do instead.** `viewport` is ignored when `target` is set. Size the `RenderTexture` to the region you
want, or drop the target to render a sub-rect of the screen. Still silent.

---

## 27. Scaled or mirrored camera node

**Mistake.** Attaching a `CameraComponent` to a scaled node, or parenting a camera node under a scaled
one.

**Symptom.** A uniform scale rescales the world in view; a negative scale mirrors the view, so every
surface goes back-facing and the scene renders inside out. The camera's reported `forward`/`up` look
correct, which makes it hard.

**Do instead.** A camera node must carry only rotation and translation, and no ancestor may be scaled.
Still silent.

---

## 28. Hand-built `Skin` with mismatched joints and inverse-bind matrices

**Mistake.** `skin.joints.add(n)` without a matching `skin.inverseBindMatrices.add(...)` (both are
plain mutable lists).

**Symptom.** Extra inverse bind matrices are silently ignored and the mesh deforms wrongly. (Too few
throws a `RangeError`, so only the extra-matrices direction is silent.)

**Do instead.** Keep the two lists parallel: one inverse bind matrix per joint (`Matrix4.identity()`
if the joint's rest pose is the mesh's model space). Imported skins are validated; hand-built ones are
not. Still silent.

---

## 29. Cloning a mesh node whose skeleton is a sibling

**Mistake.** `meshNode.clone()` when the skeleton lives outside the cloned subtree.

**Symptom.** The clone renders collapsed or in bind-pose garbage. There is a `debugPrint`, but it says
only "Index path formation failed" and names neither the skin nor the consequence.

**Do instead.** Clone the common ancestor of the mesh node and its skeleton, not the mesh node alone.
Still effectively silent.

---

## 30. `updateInstanceTransforms(recomputeWinding: false)` with a mirroring edit

**Mistake.** Editing an instance transform to a negative determinant while asking the engine to skip
the parity refresh.

**Symptom.** Those instances render inside out (front faces culled, back faces lit).

**Do instead.** Drop `recomputeWinding: false`, or keep every instance edit orientation-preserving
(no negative/mirrored scale). Still silent.

---

## 31. Flipbook frame count vs atlas grid mismatch

**Mistake.** A `FlipbookModule(frameCount: 16)` without `emitter.flipbookColumns = 4;
emitter.flipbookRows = 4`.

**Symptom.** Particles sample the wrong atlas cells, or only the first cell; the effect animates but
shows the wrong art.

**Do instead.** Set `flipbookColumns * flipbookRows` equal to the module's `frameCount`. Still silent.

---

## 32. `LodComponent` blend bands overlapping

**Mistake.** A `blendRange` larger than the gap between adjacent LOD thresholds.

**Symptom.** An object sits permanently in the wrong cross-fade pair, dither-blending two levels that
should not blend, or skipping a level.

**Do instead.** Keep `blendRange` smaller than the smallest gap between adjacent `screenSize`
thresholds. Still silent.

---

## 33. `TextureAtlas` grid not matching its texture

**Mistake.** `TextureAtlas(columns: 16, rows: 16, tileSize: 32, padding: 2, baseColor: eightBySix)`
where the grid does not match the image, or an out-of-range tile `index`.

**Symptom.** Every UV points at the wrong tile. With the default `repeat` addressing, an out-of-range
index in release wraps to a different valid-looking tile rather than failing.

**Do instead.** Make the grid parameters produce exactly the texture's dimensions
(`columns * (tileSize + 2*padding)` etc), keep tile indices in range, and set
`TextureSampling.maxMipmapLevels` so tiles do not bleed across the padding gutter at high mips. Still
silent.

---

## 34. `useEnvironment` sky with no cube-radiance variant

**Mistake.** `ShaderSkySource(fragmentShader: myShader, useEnvironment: true)` with
`radianceCubeFragmentShader` left null.

**Symptom.** The sky contributes no image-based specular on any backend that builds the cube layout
(the default nearly everywhere), so the scene loses its reflections.

**Do instead.** Supply `radianceCubeFragmentShader`, the entry built with
`FLUTTER_SCENE_RADIANCE_CUBE`. Debug builds warn about this at bind; release builds are silent, so do
not rely on the warning.

---

## 35. `radianceCubeFragmentShader` that is not the cube build

**Mistake.** `ShaderMaterial(fragmentShader: f, radianceCubeFragmentShader: f)` (the same shader
twice), or naming the non-cube entry as the cube twin.

**Symptom.** The engine binds a cubemap into a shader whose sampler is a `sampler2D`: nothing on some
backends, garbage specular on others.

**Do instead.** The cube variant must be the entry compiled with `FLUTTER_SCENE_RADIANCE_CUBE`, whose
`prefiltered_radiance` sampler is a `samplerCube`. Pass the distinct `...Cube` entry from your bundle.
(The engine can only catch the identical-shader case, and only in debug.) Still effectively silent.

---

## 36. Reading `int`/`bool`/`uint` shader members through `setUniformBlockFromFloats`

**Mistake.** `setUniformBlockFromFloats('FragInfo', [1.0, 0.5])` where the shader declares `int mode;
float amount;`.

**Symptom.** The shader reads `mode` as the float bit pattern of `1.0` (a huge integer), so every
`if (mode == 1)` branch misses and the material takes its fallback path. The block size is correct, so
nothing complains.

**Do instead.** Pack integer members with `ByteData.setInt32` at the member's offset, or use a `.fmat`
material whose `MaterialParameters` type-checks every assignment. Unenforceable at runtime.

---

## 37. A custom fragment shader that tone-maps or writes straight alpha

**Mistake.** Ending a `ShaderMaterial`/`ShaderSkySource`/`beforeTonemap` `PostEffect` fragment
shader with `frag_color = vec4(color, alpha)` (straight alpha) or `pow(color, vec3(1.0/2.2))`
(gamma-encoded).

**Symptom.** Straight alpha gives edge halos and over-bright overlaps. sRGB output is tone-mapped and
EOTF-encoded a second time by the resolve pass, giving washed-out low-contrast color that looks like a
bad exposure.

**Do instead.** Output linear HDR premultiplied by alpha. Exposure, tone mapping, and the display
encode are applied later by the full-screen resolve pass. When sampling an sRGB texture, linearize
first. `.fmat` materials get the premultiply for free. Unenforceable at runtime.

---

## 38. `MaterialParameters.copyStateFrom` across a changed layout

**Mistake.** Applying a re-realized material onto a live instance whose shader layout changed (an
editor hot reload where the `.fmat` gained or lost a parameter).

**Symptom.** Every parameter reverts to its sidecar default while `assignedValues` still reports your
overrides, so the inspector shows the right numbers and the render shows the wrong ones.

**Do instead.** `copyStateFrom` needs both sides to come from the same compiled shader entry; remap by
name through `updateFromMetadata` across a layout change instead. Still silent.

---

## 39. Environment or widget textures with sub-255 alpha

**Mistake.** Passing an equirect image carrying alpha below 255 (an unfilled sky dome, a masked
panorama) to `fromUIImages`/`fromEquirectImageAsset`. Or, for `WidgetTexture`/`WidgetComponent`,
simply using a widget with anti-aliased or translucent edges.

**Symptom.** For environments, diffuse ambient comes out darker than the specular reflections of the
same environment, so objects look lit by two environments. For widget textures, dark halos around
anti-aliased text and rounded corners on the zero-copy path (correct on the web readback path, so it
reads as a platform quirk).

**Do instead.** Use opaque (alpha 255) environment sources. The widget-alpha double-multiply is a
backend difference you cannot fully control from the API; keep widget content opaque where you can.
Still silent.

---

## Now caught by the engine, in one place

For quick reference, these traps became loud in 0.22.0. If you hit one you get an error, not silent
wrong pixels:

- In-place edit of `localTransform`/`position`/`rotation`/`scale` -> throws in debug (#1).
- Degenerate camera and a frame that draws nothing -> asserts/prints once in debug (#23).
- `uploadVertexData` and `setCustomAttribute` length mismatches -> throw always (#17, #18).
- A `Mesh` whose primitive geometry is swapped -> recomputes bounds itself (#24).
- An `AnimationClip` binding zero of its channels -> asserts in debug naming the wanted nodes.
- A web-backend bind to a shader uniform/texture name the shader does not declare -> throws (matches
  native), instead of silently sampling whatever was bound last.
- Also fixed outright: `Node.clone()` sharing the original's matrix, the skinning joints texture being
  too narrow for small joint counts, and `ParticleSystem.reset()` not restarting its random stream.
