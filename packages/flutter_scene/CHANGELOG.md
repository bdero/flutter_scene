## 0.20.0

* Physics was redesigned around a backend-agnostic simulation contract. The pure `scene` package now defines `PhysicsSimulation` (a handle-addressed driver interface with a `PoseTarget` seam instead of scene-graph references) plus the shape/material/joint-description types, and ships `BasicSimulation` (queries and triggers, no solver). flutter_scene keeps one generic component layer, `PhysicsWorld` wraps any simulation (`PhysicsWorld(RapierWorld())`), and `RigidBody`, `Collider`, `FixedJoint`/`SphericalJoint`/`RevoluteJoint`/`PrismaticJoint`/`GenericJoint`, and `KinematicCharacterController` are concrete and work with every backend. Backend packages no longer depend on Flutter at all, so servers and tooling can step the same simulations under plain `dart run`. Breaking, backend-specific component classes (`Rapier*`, `Box3d*`) are gone (use the generic components), and `BasicPhysicsWorld`/`BasicCollider`/`BasicKinematicBody` became `PhysicsWorld(BasicSimulation())` plus the generic components. Colliders without a sibling `RigidBody` now attach as static geometry instead of requiring one.
* The `.fscene` document core (the document model, stable ids, JSON and binary serialization, prefab composition, and structural diffing) moved to the new pure-Dart `scene` package, which `flutter_scene` depends on and re-exports. Existing imports through `package:flutter_scene/fscene.dart` are unchanged; the document layer is now usable from plain Dart programs (servers, tooling) with no Flutter dependency.

* New declarative scene API. Scenes can now be described in `build()`
  with widgets that own and reconcile retained scene-graph nodes:
  `SceneView.declarative` (a view-owned `Scene` configured through
  constructor props), `SceneNode` (transform, components, children),
  `SceneMesh` (geometry plus material), and `SceneModel` (async `.glb`
  loading with `placeholder`/`error` scene subtrees, sourced from the
  asset bundle or app-supplied bytes via `SceneModelSource`). Rebuilds
  apply only changed properties to the retained nodes; structure changes
  reconcile through the element tree (keys, `GlobalKey` reparenting, and
  hot reload of scene structure all work). Bridges connect the two styles
  in both directions, `SceneNodeHost` mounts an app-owned node inside a
  declarative tree, `SceneSubtree` mounts declarative children under any
  node of an app-owned scene (both `SceneView` constructors take
  `children`), and `SceneNodeController` hands imperative code the
  widget-managed node. Gated views (`loading`/`warmUp`) hold their reveal
  until declarative models finish loading, asset-sourced models
  participate in asset hot reload, template clones carry importer-attached
  components (punctual lights) through the new `Component.cloneFor` hook,
  and removing an animation spec fully unregisters its clip
  (`AnimationPlayer.removeClip`). The imperative API is unchanged and
  remains fully supported.

* Declarative animation control and shared model templates. `SceneModel`
  gained `animations`, a list of `SceneAnimationSpec`s declaring which
  imported animations play by name with per-spec `playing`/`loop`/
  `weight`/`speed`; rebuilding applies the differences to the underlying
  clips as plain property writes, so blend weights compose with ordinary
  Flutter animations. Models are also now cached and shared: widgets
  whose sources have equal cache keys load and import once, each
  mounting its own clone of the shared template (geometry, textures, and
  materials stay shared on the GPU; primitives, skins, and the variants
  component are rebound per instance), with the template evicted when
  the last user unmounts.

* `KHR_materials_variants` support in both import paths. Models
  declaring material variants get a `MaterialsVariantsComponent` (found
  via `MaterialsVariantsComponent.of(root)`, or `allOf` for multi-root
  documents) with the declared names;
  `select(name)` swaps the mapped primitives' materials in place
  (`select(null)` restores defaults), so variant switching is instant.
  The `.fscene` document format carries variants as a
  `materialsVariants` component (variant names plus per-primitive
  material mappings, the authored default, and the active selection), so
  pre-converted `.fsceneb` assets keep their variants and an editor save
  made while a variant is selected keeps the authored defaults; no
  container change was needed and existing files are unaffected. Bindings
  resolve primitives by index at selection time, so meshes rebuilt by
  scene hot reload stay bound, and re-registered render items keep
  subclass state (LOD tags) through the new mesh re-registration hook. `SceneModel` exposes selection declaratively as a
  `variant` property. The example app gained a Configurator example, a
  product configurator that live-downloads the Khronos
  MaterialsVariantsShoe and switches its colorways.

* Animation blending no longer flattens rigs with mirrored bones. Recovering
  the bind pose from the composed matrix put a mirrored axis's negative
  scale on X, so weighted blends faded the bone through zero scale and the
  attached geometry collapsed until the blend finished. Nodes built from
  TRS transforms (both importers, `.fscene` documents, and scene hot
  reload) now keep the authored decomposition and blending anchors to it.

* Automatic exposure (eye adaptation). `Scene.autoExposure` meters the
  average luminance of the rendered HDR image each frame and eases a
  correction factor toward it, so the image brightens in dark surroundings
  and darkens in bright ones. The factor multiplies on top of
  `Scene.exposure`, which stays the artistic base. Settings cover the
  correction strength, EV compensation, EV clamps relative to the base
  exposure, asymmetric adaptation speeds, and a `reset()` snap for camera
  cuts. Metering runs entirely on the GPU (a log-luminance downsample chain
  and a one-pixel adaptation state), so it works on every backend with no
  readback.

* Imported materials keep their source names. `Material` gained a `name`
  field (empty when unnamed), and both import paths set it from the glTF
  material name, so materials can be looked up after loading. `.fscene`
  documents store it as an optional `name` on material resources.

* Cloned skinned meshes no longer render as a single body. Clones share
  their template's skinned geometry, and the shared geometry held the
  per-frame joints texture, so every clone drew whichever skeleton
  updated last (at that skeleton's position). Joint state now rides each
  render item and is applied to the geometry per draw, so clones of a
  skinned model animate and place independently in every pass (color,
  shadows, depth prepass, and picking masks).

## 0.19.0

* Steady-state frame allocations cut sharply. Every fullscreen pass (bloom,
  ambient occlusion, reflections, god rays, depth of field, resolve, FXAA,
  the shadow and scene-split copies) now goes through the process-lifetime
  pipeline cache instead of creating its render pipeline every frame (about
  25 pipeline creations per frame in a fully featured scene), and the
  per-draw uniform packs (`FrameInfo`, the lit `FragInfo`, the single-draw
  instance transform) reuse shared scratch buffers instead of allocating. At
  high draw counts this removes hundreds of megabytes per second of garbage
  and the GC pauses that came with it.

* Draw submission binds far less. Render-pass bindings persist across
  draws, so the scene encoder now clears bindings only when the pipeline
  changes (opaque draws are already pipeline-sorted) instead of before
  every draw, and the engine lighting set (the IBL, shadow, SH,
  punctual-light, and occlusion samplers plus their uniform blocks)
  rebinds only when the pass, shader, lighting, or environment actually
  changes instead of once per item. Every bind marshals its slot name
  across the FFI, so draw-heavy scenes gain a lot; a 100-tile streaming
  scene on Metal dropped from 13.0 ms to 5.7 ms average frame build
  time with identical output.

* Cheaper `MeshGeometry.fromArrays` construction for streamed meshes.
  Supplied attributes now bulk-copy instead of walking every vertex, an
  already-typed index list (`Uint16List`/`Uint32List`) uploads without the
  width scan and repack, and a new optional `bounds` parameter accepts a
  caller-computed culling AABB (skipping the construction-time position
  scan), so an app that assembles vertex data on a worker isolate can build
  large geometry on the UI thread with nothing but memcpys and the GPU
  upload.

* Depth of field with bokeh, off by default via `scene.depthOfField`. A
  thin-lens camera model drives the blur (`fStop`, `focalLength` derived from
  the camera FOV or set explicitly, `sensorHeight`, `focusDistance`, plus an
  artistic `blurScale`), sharing the physical-camera vocabulary of
  `Scene.physicalCameraExposure`. The bokeh aperture is shaped by
  `bladeCount`/`bladeRotation`/`bladeCurvature`, baked into the gather kernel
  on the CPU so shape costs nothing per frame. Renders as half-resolution
  fragment passes (CoC downsample, near-field CoC dilation so foreground blur
  crosses silhouettes, a Vogel-disc gather with occlusion weighting, an
  optional noise postfilter, and a full-resolution composite) on the linear
  HDR scene color before bloom, on every backend including web. Three quality
  tiers via `DepthOfFieldQuality`. Requires a perspective camera and forces
  the depth prepass while enabled.

* Cached shadow tiles for static geometry. Marking a node `shadowStatic`
  promises its meshes will not move or change while mounted, letting the
  engine render them into persistent per-cascade shadow tiles that are reused
  across frames; each frame then replays the cached tiles and draws only the
  dynamic casters on top. Tiles are fit with slack so the camera can move and
  turn without re-rendering, re-fit amortized (nearest cascade first) when
  static content changes, and rebuilt outright when the light or shadow
  parameters change. Large static worlds drop from re-encoding every caster
  into every cascade every frame to near-zero steady-state shadow cost;
  scenes with no `shadowStatic` nodes render exactly as before.

* Alpha-masked materials (`AlphaMode.mask`) are now alpha-tested in the
  depth-writing passes, not just the color pass. The shadow map and the camera
  depth prepass draw them through masked fragment variants that discard below
  the material's cutoff, so cutout surfaces such as foliage cast shadows,
  occlude ambient light, block god rays, and receive screen-space effects only
  where they are actually opaque. Masked shadow casters also keep the
  material's own face culling (a double-sided cutout casts from both sides)
  instead of the light's caster-face mode. Fully opaque and translucent
  materials render exactly as before.

* Materials can declare per-frame scene inputs. A `.fmat` declaring
  `engine_inputs: [scene_color, scene_depth]` samples an opaque-phase
  color snapshot (the scene pass splits in two around the translucent
  phase) and the prepass linear depth, enabling refraction, depth-fade
  absorption, shoreline foam, and in-material reflection marches on
  translucent surfaces such as water. The accessors are emitted only
  into materials that declare them, so scenes that use none of this pay
  nothing. `MaterialInputs` also gains a `specular` scale, and the
  per-frame uniforms now carry the camera's half-fov tangents so
  materials can project between world and screen space. Documented in
  MATERIALS.md.

* `.fmat` skies declaring `requires: [environment]` now sample through a
  generated `SampleEnvironment(direction, roughness)` helper that binds every
  radiance layout correctly (the roughness-mip cube layout previously sampled
  black), and `ShaderSkySource.sampledEnvironment` pins the environment such a
  sky samples, so a sky that drives scene lighting through `SkyEnvironment`
  can reflect a fixed map instead of its own bake.

* The lit shader reads both cross-fade environments' diffuse SH through a
  single `sh_coefficients` sampler (a 9x2 composite row per environment during
  a cross-fade), dropping the fragment sampler count from 16 to 15. Skinned
  draws add a vertex-stage joints texture on top of the fragment samplers, and
  16 + 1 overflowed the texture-unit validation on GLES drivers reporting the
  minimum 16 units (ANGLE on D3D11), crashing skinned meshes on Windows. The
  engine-side validation fix is upstream; this keeps skinned rendering working
  on stable drivers today and buys back sampler headroom everywhere.

* Fixed white speckles baked into compressed textures on devices whose
  preferred compressed-texture family is BC, most visibly on the web on
  Windows, where browsers typically expose only s3tc. Near-flat BC1
  blocks that quantize both endpoints to the same RGB565 value landed
  in BC1's 3-color mode, where one index decodes to transparent black,
  and premultiplied rendering showed the holes as bright speckles.
  Equal packed endpoints now emit zero index bits, which decodes
  exactly.

* Scene-graph conveniences for working with a loaded model. `Node.meshNodes`
  iterates the drawable nodes in a subtree, `Node.combinedWorldBounds` gives
  the subtree's world-space AABB (the bound the renderer culls against), and
  `PerspectiveCamera.framing(bounds)` places a camera to fit that AABB in the
  view. Together they turn "load a model, find its meshes, frame the camera on
  it" into a few lines instead of a hand-rolled vertex loop.

* 3D Gaussian splatting. Load a `.ply` or `.splat` capture with
  `GaussianSplats.fromAsset`/`fromBytes`, attach a `SplatComponent` to
  a node, and the set composites with the forward-rendered scene, depth
  tested against opaque geometry and blended premultiplied. A set draws
  as one instanced batch of screen-space Gaussian footprints with
  per-splat covariance, color, opacity, and spherical harmonics fetched
  from vertex-stage data textures; a background worker keeps the splats
  depth sorted, and sets of at most 4096 splats sort synchronously in
  frame. `SplatComponent` exposes opacity, footprint scale, tint, SH
  degree, antialiasing, and crop boxes, with `SplatData` and the
  `SplatColorSpace`, `SplatCropMode`, and `SplatFormat` enums rounding
  out a new "Gaussian splatting" doc category. The example app gains a
  Gaussian Splats page with two real captures.

* Scene content can now be exposed to assistive technology (screen
  readers, switch access). Attaching the new `SemanticsComponent` to a
  node publishes it into the enclosing `SceneView`'s semantics tree with a
  label, value, flags, and actions (tap, increase/decrease, or a full
  `SemanticsProperties`), with its focus rectangle projected from the
  node's bounds through the view's camera each frame and traversal order
  controlled by `sortOrder`. Culled or invisible nodes leave the tree, and
  an opt-in `occlusionHiding` also removes nodes that scene geometry
  blocks from the camera. `WidgetComponent` surfaces now expose their
  hosted subtree's real semantics too, positioned on the projected
  surface, so screen readers traverse and activate in-scene widget panels
  like ordinary widgets. All of this is skipped entirely while no
  assistive technology is active. Multi-view scenes project semantics
  through the primary view (the first view rendering to the screen).

* `WidgetComponent` gained `occlusionHiding` (opt-in): while scene geometry
  occludes the surface from the camera, its hosted subtree's semantics leave
  the tree, matching how its pointer input is already blocked.

* Added `Camera.worldToScreen`, the forward counterpart of
  `Camera.screenPointToRay`.

* A failed static-resource load no longer marks the engine ready to
  render (which crashed mid-frame); the scene keeps skipping frames and
  the load is retried on the next `Scene.initializeStaticResources` call.

* Point and spot lights. `PointLightComponent` and `SpotLightComponent`
  attach lights to nodes (taking position, and for spots aim, from the
  node transform), with a range-windowed inverse-square falloff and an
  inner/outer cone for spots, and more than one directional light now
  shades as well. A scene may hold an unlimited number of lights; each
  frame the lights pack into a parameters texture and are culled per
  object through the scene BVH, so a fragment only shades the lights
  that reach its object. Spot lights cast perspective shadow maps
  through the shared shadow atlas, softened with a rotated PCF kernel
  and defaulting to a normal-offset bias. The runtime glTF importer
  reads `KHR_lights_punctual`, and `.fscene` gains `pointLight` and
  `spotLight` component codecs, so authored lights round-trip. A Lights
  example shows a grid of many culled point lights and an adjustable
  spot shadow.

* Geometry readback and derivation. `Geometry.extractMeshData()` (with
  `Geometry.isReadable`) copies a geometry's retained vertex and index
  data out as `MeshData`, an isolate-transferable structure-of-arrays
  snapshot, and `MeshData` gains pure derivation ops that compose on
  background isolates, `unweld` (flat-shaded triangle soup with
  optional canned per-triangle attributes), `extractEdges` (unique
  edges with an optional crease-angle filter), `merge`, and a
  `triangles` iterator, feeding geometry back in through
  `MeshGeometry.fromMeshData` or `applyMeshData`.
  `LineSegmentsGeometry` renders bulk disconnected segments (a
  wireframe from `extractEdges`, debug lines) as thick camera-facing
  ribbons with world-space width in one instanced draw, shaded by any
  material's fragment.

* Per-frame transient GPU data (uniform blocks, instance transforms) now
  rides an engine-owned, completion-aware arena allocator instead of
  `package:flutter_gpu`'s `HostBuffer`. Emplacements stage CPU-side and
  upload in a single write per block just before each command buffer
  submission; a block is never written again while in-flight frames may
  read it, and pooled memory grows with actual GPU queue depth and shrinks
  back afterward. This removes a redundant 4x internal buffer ring, fixes
  whole-frame aborts when a frame emplaces more than ~1MB of transients (a
  `HostBuffer` block-boundary bug), and collapses per-draw GPU buffer
  writes into a handful of block uploads per frame. On the WebGL2 backend,
  where GL commands execute during pass encoding (so a bound buffer can
  never be written again without the browser ghosting it), the same arena
  interface is backed by per-emplacement pooled buffers with identical
  completion-gated recycling and shrink behavior.

* BREAKING: the custom-pass and material/geometry `bind` surfaces take a
  `TransientWriter` (newly exported) where they previously took a
  `gpu.HostBuffer`, and `RenderPassContext.transientsBuffer` changes type
  accordingly. Call sites that only called `emplace` need no changes
  beyond the parameter type.

* Large speedup for many-draw scenes on the web backend. Per-draw uniform
  data was written into one shared GL buffer between draws that read it,
  which forces the browser's GL implementation to copy ("ghost") the buffer
  on every write; a scene with ~100 draw calls spent most of its frame time
  there, in the browser's GPU process. Transient data is now written exactly
  once per buffer before the draws that read it (see the arena entry above;
  105-draw test scene, Apple M3 Max Chrome, 35 fps to a 120 fps display
  cap). Vertex-attribute state is also cached in vertex-array objects per
  (pipeline, geometry, index buffer) instead of being re-specified every
  draw, and redundant per-draw texture sampler-state calls are skipped.

* The web shim's `HostBuffer` is a faithful port of flutter_gpu's block bump
  allocator again (with a corrected length-aware block-rollover bounds
  check), keeping the shim a drop-in flutter_gpu replacement for consumers
  that use it directly; the engine itself no longer allocates through
  `HostBuffer` on any backend.

* On the web backend, a uniform block a linked program keeps active but
  never binds no longer rejects the draw with `GL_INVALID_OPERATION`
  (Impeller tolerates the same situation). The shim pre-binds a shared
  zero-filled buffer to every active block and explicit binds override
  it, so unbound blocks read zeros instead of erroring. This fixes
  unlit `.fmat` materials rendering nothing on the web.

* Ambient occlusion and screen-space reflections no longer sample the wrong
  depth for double-sided (`culling: none`) materials. The depth prepass they
  read culled every material back-face regardless of its own mode, so a
  double-sided surface's camera-facing back faces were missing from the depth
  and the effects shaded the farther surface behind them. The prepass now culls
  each material with its own mode, matching the color pass.

* The `.fmat` compiler no longer lets a declared resource the author's
  code never reads strip out of the generated shaders. Reflection still
  listed stripped resources and the runtime binds every declared one,
  so the strips surfaced as cryptic shader-bundle build errors or
  native crashes at draw time. Every case now keeps the resource
  genuinely live at zero cost, a leading `mat4` or `int` material
  parameter, a `Vertex()` hook that fully replaces `world_position`
  (the instance transform attributes), a `Vertex()` hook that reads no
  parameter (the vertex `MaterialParams` block), a declared custom
  attribute `Vertex()` never reads, and a declared sampler the fragment
  never samples.

* Built-in noise, matched between CPU and GPU. `package:flutter_scene/noise.dart`
  adds `FastNoiseLite` (OpenSimplex2/2S, Perlin, Value, and Cellular with
  fBm/ridged/ping-pong fractals, domain warp, and a `noiseCurl3` advection
  field), plus `bakeNoisePixels`/`bakeNoiseTexture` to bake a configuration into
  a texture. Any `.fmat` `fragment`, `vertex`, or `sky` block can
  `#include <noise.glsl>` for the same functions in a shader. The two halves are
  kept in lockstep so a field sampled on the CPU and evaluated in a shader agree:
  the integer hash layer (`noiseHash2`/`NoiseHash2`) is bit-exact on every
  backend for decisions that must not disagree, and the float functions match
  within a small tolerance enforced by a per-backend parity test. The GLSL side
  is correct on every backend including the web; the Dart side is currently
  native-only (its 32-bit integer hash overflows on the web, where Dart `int` is
  a JS double), so on the web use the GLSL noise or a baked texture. A web-safe
  Dart multiply is a planned follow-up.

* `AmbientOcclusionSettings.depthMipChain` (off by default) renders the
  occlusion depth prepass at full resolution and samples it through a
  downsampled mip chain, a level per sample distance. It keeps depth accurate
  where the projection compresses a large range into few pixels (grazing
  surfaces, vertex-displaced worlds), so near geometry's occlusion is not
  contaminated by the far surface behind it, and keeps large radii
  cache-friendly. The cost is a full-resolution prepass plus the chain build, so
  it is best reserved for higher-end targets.

* Distance fog. `scene.fog` (a `Fog`, off by default) fades geometry toward a
  fog color with distance, applied per-fragment in linear HDR before tone
  mapping so it is exposed and tone-mapped along with the scene. It supports
  linear, exponential, and exponential-squared falloff (`FogMode`), a maximum
  opacity, a cutoff distance, an exponential height term that thins fog with
  altitude, and an in-scattering glow toward the directional light. Its
  `skyColorInfluence` blends the fog color toward the environment sampled in the
  view direction, so distant geometry dissolves into the sky and horizon instead
  of a flat wall.

* Custom render passes. A `CustomRenderPass` added through
  `Scene.addRenderPass` renders at a chosen `RenderStage` with a
  `RenderPassContext` (targets, camera, transients), and
  object-filtered draws through `NodeFilter` let a pass re-render a
  chosen subset of the scene. Built on it, `Node.highlightColor` plus
  `Scene.highlightStyle` (`HighlightStyle`) draw per-node selection
  outlines (a mask pass and an outline post-process), which is what the
  scene editor uses for viewport selection.

* Custom render passes can also read the scene's geometry, not just its color. A
  `CustomRenderPass` declares the buffers it needs through a `RenderInput` set
  (`depth`, `normals`, `shadowMap`); the engine produces them that frame and
  exposes them on `RenderPassContext` (`sceneDepthLinear`, `shadowMap`,
  `shadowInfo`, `cameraInfo`), so a full-screen pass can reconstruct world
  positions and sample the shadow map. This turns the custom-pass API into a
  general depth- and shadow-aware post-process system.

* Volumetric god rays. `scene.godRays` (a `GodRaysSettings`, off by default)
  draws directional light shafts by marching the view ray against the cascaded
  shadow map and adding single-scattering to the HDR scene color, with controls
  for intensity, density, Henyey-Greenstein anisotropy, step count, maximum
  distance, jitter, and a color. It requires a shadow-casting directional light
  and a perspective camera.

* Scenes can hold rendering until their content is loaded, instead of
  flashing half-built while assets stream in. `ResourceGroup` tracks a
  set of in-flight loads and reports aggregate progress; `SceneView`
  gains `loading`, `loadingBuilder`, and `revealMinDuration`, holding
  the scene off-screen behind a loading widget until the engine's
  static resources and the tracked loads settle, then revealing the
  assembled scene in one frame. `Scene.warmUp` (and the
  `SceneView.warmUp` flag) compiles the scene's render pipelines and
  uploads its GPU resources ahead of the first visible frame by
  encoding one tiny offscreen frame, so the first frame does not stall
  on shader compilation. The runtime glTF/GLB importer now packs mesh
  geometry on a background isolate, so loading a large model no longer
  stalls the UI thread, and `Scene.isReadyToRender` exposes the shared
  static-resource state. All of it is opt-in; a view with no loading
  arguments renders as before.

* Widget-texture captures (`WidgetTexture`, `WidgetComponent`) now stay on the
  GPU. Each capture wraps the rasterized image's backing texture directly
  (`Texture.fromImage`) instead of reading the pixels back and re-uploading
  them, removing the per-capture CPU round trip. Backends where the image is
  not texture-backed (the web backend, software rendering) keep the readback
  path automatically. The texture object published by
  `WidgetTextureController` is now replaced across captures on the wrapped
  path, so `WidgetComponent`'s `bind` callback re-fires per capture; listeners
  that re-bind on change (the documented contract) are unaffected.

* `.fmat` materials gain a vertex stage. A surface material may include
  a `vertex { void Vertex(inout VertexInputs vertex) }` block that
  displaces geometry, perturbs normals, and feeds data to the fragment,
  and the engine runs that one hook across every mesh type and pass
  (static, skinned, and the position-only depth/shadow variants), so a
  material never branches on skinned vs unskinned. A declarative
  `varyings` list forwards interpolants from `Vertex()` to `Surface()`,
  an `attributes` list declares named per-vertex inputs supplied
  through `Geometry.setCustomAttribute`, and `MaterialParams` are
  shared with the vertex stage. The stage applies consistently in the
  color, shadow-map, depth-prepass, and object-pick passes, so
  displaced geometry casts a matching shadow and picks on its displaced
  silhouette. Documented in MATERIALS.md ("The vertex block").

* Built-in materials and geometries can now be constructed before
  `Scene.initializeStaticResources()` finishes loading the base shader bundle.
  Each resolves its shader from the base library lazily on first render (which
  the engine already defers until resources are ready) and caches it, so
  `SceneView` handles the warm-up with no `await` or `FutureBuilder` in app
  code. The built-in gradient and physical sky sources work the same way. To
  show placeholder content during warm-up, await
  `Scene.initializeStaticResources()` yourself. Custom `ShaderMaterial` and
  `ShaderSkySource` shaders are unaffected (you still supply a loaded shader).
  `Material` and `Geometry` gain `setFragmentShaderName` and
  `setVertexShaderName` for custom subclasses that pull from the base library,
  and `ShaderSkySource` gains a `fragmentShaderName` constructor argument.

* Added a scene-tracked primary camera. `Scene.camera` is the camera a
  `SceneView` uses when it is given no `camera`, `cameraBuilder`, or
  `viewsBuilder`. It resolves to an explicit override (assign any `Camera`),
  else the first `CameraComponent` mounted in the scene (auto-promotion), else
  null. `CameraComponent` gains `makeActive` (select it as the primary,
  deferred until mount if needed) and `active`. When nothing resolves a
  camera, `SceneView` now renders through a default camera instead of
  asserting, so a bare `SceneView(scene)` always renders. The `SceneView`
  constraint relaxes from exactly one to at most one of `camera`,
  `cameraBuilder`, or `viewsBuilder`.

* Camera-facing billboards and sprites. `BillboardGeometry` draws any
  number of camera-facing quads in a single instanced call (spherical,
  axis-locked, or velocity-stretched `BillboardFacing`, with flipbook
  atlas support), `SpriteMaterial` shades them with alpha or additive
  compositing in one translucent pass (`SpriteBlendMode`), and `Sprite`
  wraps a single billboard. The example app's Sprites and Particles
  pages build on them, the latter through a CPU-simulated particle
  system that is not yet part of the public barrel. The
  selection-mask, depth-prepass, and shadow passes now honor a
  geometry that supplies its own per-instance buffer and a geometry's
  double-sidedness.

* Three directional-shadow controls, each defaulting to the previous
  behavior. `shadowAmbientStrength` lets the cast shadow also darken
  the image-based ambient, which matters when a sky-baked environment
  already contains the sun and a shadow otherwise reads as a no-op on
  ambient light. `shadowCasterFaces` selects which faces render into
  the shadow map (`front` as before, second-depth `back` to remove
  self-shadow acne on watertight geometry, or `both`). And each
  cascade's light-space box now extends far toward the sun at no
  shadow-map resolution cost, so at low sun angles the long shadows of
  occluders outside the old box no longer drop out as lit bands.

* Fixed the cascaded-shadow lookup on OpenGL ES and Windows. The lookup
  indexed the cascade uniforms with a non-literal index, which is
  invalid in GLSL ES 1.00 and misread every cascade past the first on
  GLES backends (wrong shadows on distant ground), and its early-return
  loop shape crashed the Direct3D shader compiler the moment a lit
  object rendered on Windows. The selection is now unrolled with
  literal indices and passes each cascade's data by value. A Windows
  smoke-render CI job now guards the platform.

* BREAKING: vertex layouts are described by value and unskinned
  geometry is stored as structure of arrays. Geometry carries a
  `VertexLayoutDescriptor` (attributes by name, format, slot, and
  offset, with per-buffer stride and step mode) that lowers to the GPU
  layout, `Geometry.instancedVertexLayout` changes to that type, and
  the render-pipeline cache keys on the layout so two layouts sharing a
  shader no longer collide. Each unskinned attribute (position, normal,
  texcoord, color) now lives in its own tightly packed stream end to
  end; the depth, shadow, and mask passes fetch only the 12-byte
  position stream, updatable geometry rewrites only the dirty stream
  (and the `update*` methods take an optional dirty vertex range), and
  the per-geometry `kInterleavedVertexBytes` constants are gone. The
  `.fscene` format stores unskinned vertices de-interleaved (a new
  `unskinned_soa` payload layout); old interleaved `.fsceneb` files
  still load, and skinned geometry stays interleaved.

* New procedural primitives alongside the existing
  cuboid/plane/sphere/wedge, a cylinder (separate top and bottom radii,
  so it also covers cones), capsule, torus, disc, ring, and geodesic
  icosphere, each an indexed mesh with outward normals and UVs and each
  with a `collisionShape` bridge for the physics backends (compound
  shapes preserve the torus and ring holes). `MeshData` snapshots are
  isolate-transferable so meshing can run off the render isolate and
  upload via `MeshGeometry.fromMeshData`. A Shapes example drops the
  primitives into a physics playground.

* Geometry level of detail. An `LodComponent` draws one of several
  `LodLevel` variants chosen per view from the object's projected
  on-screen size (field-of-view aware and resolution independent), with
  a per-instance bias, a hysteresis dead-band, and a cull floor;
  selection runs in the encoder next to frustum culling. An optional
  dithered cross-fade blends adjacent levels across a screen-size band
  so the switch does not pop, honored by the built-in lit and unlit
  materials. A Geometry LOD example shows a field of icospheres
  switching detail with distance.

* Image-based lighting now prefilters into a radiance cubemap, a
  roughness band per mip sampled with hardware trilinear filtering,
  with `EnvironmentMap.radianceCubeSize` selecting the face size and
  the web backend gaining cube-texture support to match. Each
  environment carries its own layout, detected from its texture, so
  environments built with the earlier equirect layouts keep loading
  and binding correctly. `EnvironmentMap.fromEquirectHdr` builds an
  environment from linear HDR equirect pixels, so radiance above 1.0
  (bright skies, the sun) survives the prefilter and lights the scene
  at its true intensity. The prefilter also pre-averages bright
  sources through a mipped source (no more firefly blocks in the rough
  bands) and no longer shows cube-face seams.

* Spatial environment volumes with camera-driven blending.
  `EnvironmentSettings` captures a scene's look (environment, skybox,
  exposure, tone mapping) as an interpolable snapshot,
  `Scene.baseEnvironment` holds the global look, and
  `EnvironmentVolume`s (box or sphere bounds, or attached to nodes via
  `EnvironmentVolumeComponent`) blend over it by camera position with
  per-volume priority, weight, and blend distance. The lit shaders
  cross-fade between two full environments while a blend is in flight,
  so lighting, reflections, and the skybox all transition smoothly
  instead of popping. `Scene.environmentSettings` applies a snapshot
  directly, and `blendEnvironmentVolumes` exposes the resolver.

* Sky-driven sun light. Assigning a `SunLight` to `Scene.sunLight` aims
  the scene's directional light at a sky's sun each frame and recolors
  it from the sky, so the hard shadow tracks the same sun the sky draws
  and agrees with the sky-baked image-based lighting. The built-in
  gradient and physical sky sources implement the `SunSky` interface it
  consumes and expose `sunLightColor`/`sunLightIntensity`.

* BREAKING: in the `.fscene` format, a stage's global look is now a
  referenced environment resource instead of inline stage fields
  (`StageMetadata` loses its environment/exposure/tone-mapping/skybox
  fields, and `realizeStage` takes an `environmentLoader`), backed by
  pooled `EnvironmentResource`s, and prefab host-node additions are
  expressed as `Attachment`s (replacing `PrefabInstanceSpec.addedNodes`).
  Imported textures and image or HDR environments stay external files
  next to the lean `.fscene` and are embedded into the self-contained
  `.fsceneb` at build time, multi-file `.gltf` (external resources)
  imports, prefab composition reports member origins
  (`composeScene(memberOrigins:)`) and gains `applyPrefabOverride`, and
  components declare a property schema (`ComponentPropertyDef`) that
  editors drive generically. These serve the in-development scene
  editor now hosted in the repository (unpublished, a desktop app over
  a headless command core and an MCP surface).

* Added `Texture2D` for textures with generated mipmaps and trilinear plus
  anisotropic filtering, built from an asset, a `ui.Image`, or raw pixels
  (`Texture2D.fromAsset`, `Texture2D.fromImage`, `Texture2D.fromPixels`).
  `TextureContent` selects how each mip level is filtered (color in linear
  light, raw data, or renormalized normals) and `TextureSampling` controls the
  mip filter, maximum mip level, and anisotropy. The runtime glTF loader now
  builds its textures as `Texture2D`, so imported models are mipmapped.

* **Breaking:** the material texture slots (`baseColorTexture`,
  `metallicRoughnessTexture`, `normalTexture`, `emissiveTexture`,
  `occlusionTexture`) now hold a `TextureSource` rather than a raw
  `gpu.Texture`. Assign a `Texture2D` or a `RenderTexture` directly, or wrap an
  existing `gpu.Texture` in `GpuTextureSource`.

* Added `TextureAtlas`, a helper for a uniform grid of packed tiles (voxel
  faces, sprite sheets, terrain) that resolves per-tile UVs and can build a
  `PhysicallyBasedMaterial` from its maps, along with
  `generateSolidColorAtlasPixels` for a placeholder atlas.

* Added geometric specular antialiasing to `PhysicallyBasedMaterial` via
  `specularAntiAliasingVariance` and `specularAntiAliasingThreshold`, which
  widen roughness where the shading normal varies quickly to curb distant
  specular sparkle.

* Fixed the split-sum specular sampling the BRDF integration lookup with its
  roughness axis flipped, which gave rough surfaces mirror-strength
  reflections and washed them out.

* Fixed image-based lighting taking the shadow-ambient gate and the specular
  Fresnel term from the normal-mapped normal, which darkened bumpy surfaces
  under a low sun and made grazing reflections blotchy. Both now use the
  geometric normal; the reflection direction still follows the normal map.

* Fixed `normalScale` not being applied to the perturbed normal.

* Screen-space reflections, off by default via
  `Scene.screenSpaceReflections`. An optional pass layers sharp,
  view-dependent reflections on top of the image-based environment
  reflections every surface already receives, reconstructing each
  pixel's position and smooth normal from the shared camera depth
  prepass (no G-buffer), marching the reflected ray through the depth
  buffer in screen space, and sampling the already-lit scene color on
  a hit with the environment as the miss fallback, so it only ever
  adds detail. `ScreenSpaceReflectionsSettings` exposes intensity,
  range and thickness, `stride` (the quality dial) and `maxSteps` (a
  cost ceiling), glossy `blur`, a distance fade, `resolutionScale` to
  trace below full resolution, and a `debugView`, and a Screen-space
  Reflections example ships with a live tuning panel.

* Screen-space reflections now fade out on rough surfaces. The camera depth
  prepass carries per-pixel roughness, so smooth surfaces still reflect while
  rough ones stop.

* The split-sum environment BRDF (the DFG lookup for specular image-based
  lighting) is now generated at load as an `RGBA16F` texture instead of loading
  a bundled 8-bit PNG. The 8-bit table quantized the scale/bias terms into 256
  steps, showing up as subtle radial banding on large glossy surfaces; the
  half-float table removes it (half-float linear filtering is core in
  GLES 3.0 / WebGL2). The `ibl_brdf_lut.png` asset is removed.

## 0.18.1

* No code changes. Reworded the package description, added the Flutter Scene
  logo as a pub.dev screenshot so it shows in search results, and removed a
  stray rule from the README.

## 0.18.0

* Added offscreen render targets. A `RenderTexture` is a fixed-size target
  a `RenderView` can render into (`RenderView.target`); add such views to
  the new `Scene.views` list and they render whenever the scene renders,
  ordered before the screen views. The target's `update` policy
  (`everyFrame`, `interval`, or `manual` + `requestUpdate`, mirroring
  `WidgetUpdatePolicy`) controls re-render cadence, and `resize`
  reallocates on the fly. Display a live target in the widget tree with
  the new `RenderTextureView` widget (with an opt-in `followLayout` mode
  that sizes the target from widget layout). Views also gain a per-view
  `antiAliasingMode` override that defaults to the scene's setting.

* The prefiltered-radiance environment now stores its roughness bands as
  mip levels of one equirect texture, sampled with hardware trilinear
  `textureLod` (smoother roughness transitions, ~25% less memory, no
  band-seam clamping). Enabled by the recent Flutter GPU mip support
  (render-to-mip-level, mip samplers, and sampling manually-written mip
  chains). The legacy stacked-band atlas remains supported, selectable
  via the new `EnvironmentMap.useMipRadianceLayout` static (each
  environment carries its own layout, and the
  `SamplePrefilteredRadiance` shader contract for custom materials is
  unchanged). The web backend gained render-to-mip-level attachments and
  mip-aware sampler filtering.

* Fixed dim image-based specular lighting on the web backend. The radiance
  prefilter (a float render-to-texture) comes out degenerate on a cold
  WebGL context, before the first frame has been composited, and is correct
  once the context is warm. Environments built before then (the lazily
  built default, or any an app builds up front) now retain their source and
  re-bake their radiance once a frame has been presented, so the first frame
  may show dim specular IBL but every frame after is correct.

* The base shader bundle now loads asynchronously on every backend,
  following `ShaderLibrary.fromAsset` becoming async. Native joins web in
  requiring the bundle to be loaded ahead of time by awaiting
  `Scene.initializeStaticResources()` before constructing geometry or
  materials; the native synchronous load on first access is gone.

* The `flutter` SDK constraint is now `>=3.44.0` (the latest stable, so the
  package can be analyzed and scored on pub.dev). The actual requirement is
  newer, a Flutter master build from 2026-06-09 or later (render-to-mip-level
  Flutter GPU support, flutter/flutter#187685); see the README.

* Render targets serialize in `.fscene`. Documents gain a
  `renderTexture` resource kind (size, update policy, sampling) and a
  top-level `views` array binding camera nodes to targets with per-view
  settings; material texture slots reference the same resource id the
  producing view targets, so the wiring survives a round trip. Realize
  with the new `realizeViews` (after `realizeScene`, sharing live
  targets with the materials that sample them) and write back with
  `serializeViews`. The stage now also carries the scene's
  anti-aliasing mode, render scale, and filter quality. `CameraComponent.
  toCamera()` now returns a `NodeCamera` that tracks its node live
  (previously it snapshotted the transform), so node-driven cameras work
  in persistent views.

* Material texture slots now accept a `RenderTexture` for live
  render-to-texture sampling, the security-camera/monitor/mirror
  pattern. `PhysicallyBasedMaterial` and `UnlitMaterial` texture setters
  (and `ShaderMaterial.setTexture`) take either a `gpu.Texture` or a
  `RenderTexture`; a render texture resolves to its latest completed
  frame at draw time and brings its own sampling options (the new
  `RenderTexture.sampling`, bilinear + clamped by default). A capture
  that can see its own consumer (including a target sampling itself)
  reads the previous frame instead of forming a feedback loop, and a
  target with no completed frame yet resolves to the slot's neutral
  placeholder.

* Added render scaling and composite filtering. `Scene.renderScale`
  (default 1.0) scales the resolution screen views render at relative to
  the display's native resolution, trading sharpness for fragment work
  below 1.0 and supersampling above it, and `Scene.filterQuality`
  (default medium) sets the sampling quality the rendered image is
  composited onto the canvas with. Both have per-view overrides on
  `RenderView` (`renderScale`, `filterQuality`).

* Added FXAA and an automatic anti-aliasing mode. `AntiAliasingMode` gains
  `fxaa` (a post-process pass over the tone-mapped image, available on
  every backend) and `auto` (MSAA where the backend supports it, FXAA
  otherwise), and `auto` is the new default. Backends without offscreen
  MSAA support previously rendered with no anti-aliasing at all; they now
  get FXAA. `Scene.antiAliasingMode` now always keeps the requested mode
  (instead of ignoring unsupported assignments), the new
  `Scene.effectiveAntiAliasingMode` reports the technique that actually
  runs, and the new static `Scene.isAntiAliasingModeSupported` answers
  support queries without touching the Flutter GPU API.

* Adopted hardware instancing: `InstancedMesh` draws upload every instance
  transform to an instance-rate vertex buffer and render with a single
  instanced draw call per winding-parity group (in the color, depth-prepass,
  and shadow passes), instead of rebinding the model uniform and drawing
  once per instance. The unskinned vertex shader now consumes the model
  matrix from instance attributes, and the WebGL2 backend gained
  `VertexStepMode`/`VertexLayout` support and instanced draw calls. Custom
  geometry overriding `bind` with the standard unskinned shader picks up the
  new path automatically; custom vertex shaders with their own uniform
  layouts are unaffected. Breaking for code that builds vertex layouts
  directly, `VertexLayout` is now constructed from a list of `VertexBuffer`s
  (each carrying its own stride and step mode) instead of a single
  `strideInBytes`.

* BREAKING: the package exports are now explicit show lists; implementation
  details that previously leaked from wholesale exports (the scene encoder,
  render-graph texture pooling, environment-prefilter internals, animation
  channel/resolver plumbing, and the fscene built-in codec classes) are no
  longer exported. If something you used disappeared, please file an issue,
  re-exporting an accidentally hidden symbol is a quick patch release.

* Added scene raycasting: `Scene.raycast` / `Scene.raycastAll` cast a ray
  through the rendered meshes (no colliders or physics setup) and return
  typed hits with the distance, world point, geometric normal, barycentric
  weights, triangle index, and the texture coordinate interpolated from the
  vertex data. Filtering: invisible subtrees are skipped by default, plus a
  layer mask, the new `Node.raycastable` flag (geometry that renders but is
  transparent to rays), and an optional predicate. Distinct from the physics
  queries, which test collision shapes.
* Added `WidgetComponent`: a live widget subtree on a scene surface. The
  widget stays fully interactive (state, tickers, animations) while
  `SceneView` hosts it invisibly and streams its visual output into a
  texture. Zero-config use creates an aspect-correct alpha-blended quad;
  bring your own geometry or material (with implicit binding for the
  built-in materials or a `bind` callback), or use `bindOnly` to texture a
  surface that already exists, such as a screen inside an imported model.
  Captures follow a `WidgetUpdatePolicy` (every frame by default, interval,
  or manual) and dialogs and dropdowns render inside the texture.
* Added automatic widget-surface input: platform pointer events raycast into
  the scene, and presses, drags, and scrolls forward into the widgets at the
  hit UV, on any geometry, blocked by occluding geometry, with pointer
  capture keeping drags alive at surface edges. Opt out per component with
  `WidgetInput.manual`. `SceneView.debugWidgetInput` overlays the pointer's
  hit node, UV, and distance for input debugging.
* Added `ScenePointer` for programmatic input (a crosshair, a gamepad-driven
  cursor): point it along any ray or screen position, then `press`,
  `release`, and `scroll`. Occlusion filtering (what blocks the ray) and
  interaction filtering (which surfaces respond) are independent masks, and
  multiple pointers carry independent capture and hover state.
* Added `WidgetTexture` (the low-level capture primitive behind
  `WidgetComponent`) and `Camera.screenPointToRay` (screen position to world
  ray, for picking and custom input).
* Added `UnlitMaterial.alphaMode` (opaque or blend), routing unlit surfaces
  through the depth-sorted translucent pass.
* Added `Surface.lastSwapchainColorTexture`, the previous frame's color
  texture, safe to sample from materials for one-frame feedback effects.
* Fixed vertically flipped texturing on the cuboid and wedge primitives:
  their face UVs put v = 0 on the bottom edge, while the engine convention
  (and imported models) put v = 0 at the top of the image. Textures on these
  primitives render right side up now; scenes that compensated for the flip
  will see the change.

## 0.17.0

* Added `SceneView`, a widget that renders a `Scene` and drives its per-frame
  loop, so apps no longer write their own `CustomPainter`. It takes a fixed
  `camera` or a `cameraBuilder(elapsed)` and exposes the scene to descendants
  through `SceneScope`.
* Added debug-mode hot reload for assets, driven by `SceneView`. Editing a
  `.fmat` updates the running scene in place (culling, blending, shading model,
  and parameter defaults, plus the GLSL body) with no app code, and re-exporting
  a `.glb` (or editing a referenced prefab) patches the scene in place while
  preserving node identity, transforms, and animation playback. Load materials
  and scenes by source path (`loadFmatMaterial`, `loadScene`) to participate;
  `loadScene` takes an optional `onReload` callback for re-applying
  per-instance customizations after a scene is patched.
* Added DataAssets-backed GLB import: `buildScenes` can auto-discover
  `assets/**/*.glb` and register the generated `.fsceneb` packages as
  DataAssets, and `loadScene` / `SceneRegistry` load them by source path.
  Requires Dart data assets (`flutter config --enable-dart-data-assets`).
  The composed document and its GPU resources are cached per scene, so
  loading the same scene again instantiates a fresh node graph cheaply,
  sharing those resources. The `dart run flutter_scene:init` hook wires up
  both `buildScenes` and `buildMaterials`. Both accept a `discoveryRoot` to
  auto-discover under a directory other than `assets/`, or an explicit list
  to bypass discovery.
* Added `AnimationClip.rebind` / `AnimationPlayer.rebind` (animation
  re-binding across a hot reload, keeping playback state) and `Mesh.clone` so
  cloned scene instances get independent materials.
* Skinned geometry imported by `buildScenes` carries an offline-baked
  pose-union bound (the union of every animated pose's extent), so skinned
  content is frustum-culled soundly instead of being treated as always
  visible.
* **Breaking:** removed the `.model` format. `Node.fromAsset` and
  `Node.fromFlatbuffer` are gone, along with the `fromFlatbuffer`
  constructors on `Geometry`, `Material`, `Skin`, and `Animation`. Convert
  `.glb` sources with the `buildScenes` build hook and load them by source
  path with `loadScene`, or load glTF binaries at runtime with
  `Node.fromGlbAsset` / `Node.fromGlbBytes` (no conversion step needed).
* **Breaking:** `.fmat` materials are now auto-discovered under `assets/`
  (matching where `.glb` models are discovered) instead of `materials/`, and
  `loadFmatMaterial` resolves a material by its `.fmat` source path (for example
  `assets/toon.fmat`) instead of by material name, so materials that share a name
  in different directories no longer collide. Move `.fmat` files under `assets/`,
  or pass an explicit list to `buildMaterials`.
* Building `.fmat` materials and models now requires `flutter_gpu_shaders` 0.5.0.
* Added the `.fscene` / `.fsceneb` serialized scene format: author scenes as
  text or import them from `.glb` with `buildScenes`, and load them by source
  path with `loadScene` (with in-place hot reload, prefabs, and streaming).
  Prefab expansion is deterministic, so an unchanged scene composes to the
  same ids across sessions and platforms.
* Added scene serialization: `serializeScene` captures a live node graph back
  into a document (geometry, materials, skins, animations, visibility, and
  hand-built meshes included), and `realizeStage` / `serializeStage` apply and
  read back scene-level render settings (environment, skybox, sky lighting,
  exposure, tone mapping). A realized scene round-trips through
  `writeFsceneb` byte-stably.
* Added optional texture compression for imported scenes, opt in
  via `compressTextures` on the importers and build hooks. Images are stored
  as mipped, supercompressed KTX2 block payloads and transcoded at load to a
  format the device supports; transcoding runs off the main isolate. Opaque
  textures take BC1, ETC2 RGB8, or ASTC; textures with alpha take BC3, ETC2
  RGBA8, or ASTC with per-block RGBA endpoints, with an rgba8 fallback
  everywhere.
* **Breaking:** fixed vertically inverted image-based lighting. The
  environment prefilter and the diffuse spherical-harmonics projection read
  source equirectangular images with the up hemisphere at the bottom, so every
  image-based environment lit scenes from below and reflected upside down.
  Both now use the standard convention (up pole at the top of the image), and
  the procedural studio environment was flipped to match, so scenes lit by
  loaded panoramas or HDRs will render differently (correctly so).
* Added a skybox: assign `Scene.skybox` to draw a background behind all
  geometry, with no user geometry or draw ordering. The built-in
  `EnvironmentSkySource` shows the scene environment with a `blurriness`
  control that reuses the prefiltered roughness bands, so the backdrop always
  matches reflections.
* Added custom sky shaders. `ShaderSkySource` draws a full-screen sky fragment
  (the engine supplies the world view direction as `v_ray`), and a `.fmat`
  with a `sky { vec3 Sky(vec3 direction) }` block compiles to one through the
  existing material pipeline: load it with `loadFmatSky` for typed parameters
  and in-place hot reload, and declare `requires: [environment]` to sample the
  scene's prefiltered radiance.
* Added sky-driven lighting. `EnvironmentMap.fromSky` bakes any shader sky
  into the image-based lighting (specular and diffuse, projected on the GPU),
  and `Scene.skyEnvironment` keeps the bake fresh on a refresh policy (manual
  with `invalidate()`, an interval, or every frame). After a binding's first
  synchronous bake, re-bakes are time-sliced one GPU pass per frame into
  double-buffered targets, so refreshes never spike a frame.
* Added built-in procedural skies: `GradientSkySource` (zenith/horizon/ground
  colors with an HDR sun disk) and `PhysicalSkySource` (an analytic
  single-scattering daylight atmosphere driven by a sun direction).
* The diffuse spherical-harmonics coefficients are now sampled from a small
  texture instead of packed into a uniform, and
  `EnvironmentMap.fromGpuTextures` accepts a `diffuseShTexture` computed on
  the GPU.
* A `.fmat` that fails to compile during hot reload no longer fails the whole
  build: the last good shaders stay active and the compile error is reported
  in the console, both from the build hook and in the running app.
* Build-hook conversions (scenes and materials) are now cached by input
  content, so a hook rerun for an unrelated edit skips unchanged sources.
  Editing one `.fmat` no longer re-imports every scene on hot reload. Set
  `FLUTTER_SCENE_DISABLE_BUILD_CACHE` to always reconvert.
* Fixed progressive slowdown on the web backend during long sessions: render
  passes leaked a GL framebuffer (and ran a synchronous completeness check)
  every pass of every frame, and some passes re-linked GL programs every
  frame. Framebuffers and linked programs are now cached, and per-draw
  uniform uploads no longer allocate.

## 0.16.0

* Added an abstract physics contract so a physics engine can drive scene
  nodes: rigid bodies, colliders and shapes, joints, physics materials,
  scene queries (raycast, shape cast, overlap), and a collision/trigger
  event stream, plus a minimal built-in `Basic` kinematic world. A full
  engine backend is provided by the `flutter_scene_rapier` package.
* Added `WedgeGeometry`, a triangular-prism ramp primitive.
* Added optional screen-space ambient occlusion, configured per scene via
  `Scene.ambientOcclusion` (off by default). It darkens the indirect
  (image-based) lighting in creases and contact points for softer, more
  grounded shading. The implementation is Scalable Ambient Obscurance,
  evaluated from a camera depth prepass with no normal buffer and no compute,
  so it works on every backend including the WebGL2 fallback. Settings cover
  the radius, intensity, bias, sample count, an optional half-resolution mode
  (on by default) for lower cost, and an optional specular occlusion term.
  Requires a `PerspectiveCamera`.

## 0.15.1

* Added a DataAssets-backed `.fmat` material workflow. `buildMaterials` can now
  auto-discover `materials/**/*.fmat`, register generated shader bundles,
  sidecars, and material indexes as DataAssets, and fail fast with setup
  guidance when DataAssets are required but unavailable.
* Added `dart run flutter_scene:init` to install a DataAssets-only build hook
  for `.fmat` materials.
* Added `FmatMaterialRegistry` and `loadFmatMaterial` for loading generated
  `.fmat` materials by material name instead of manually loading the shader
  bundle and sidecar.
* Updated the `flutter_gpu_shaders` dependency to `^0.4.5` and moved the
  hook-time dependencies to the `hooks` 2.x / `data_assets` 0.20.x stack.

## 0.15.0

Custom materials and a post-processing effects chain.

* Added the `.fmat` custom-material format: declare typed parameters and a
  small `Surface()` GLSL function instead of hand-binding a raw shader. The
  `buildMaterials` build hook compiles a `.fmat` into a shader bundle plus a
  metadata sidecar; at runtime, `PreprocessedMaterial` and `MaterialParameters`
  set the parameters by name with type checking and no manual std140 packing.
  The lower-level `ShaderMaterial` remains as an escape hatch. See
  `MATERIALS.md`.
* Added a post-processing suite configured per scene via
  `Scene.postProcess`: bloom, color grading (brightness, contrast,
  saturation, white balance, lift/gamma/gain), vignette, chromatic
  aberration, and film grain. Each effect is off by default.
* Added `PostEffect`, a custom post-processing effect authored as a
  fragment shader, the post-processing counterpart of `ShaderMaterial`.
  An effect runs before or after tone mapping and reads the current color
  through `input_color`. See `POST_PROCESSING.md`.
* The tone-mapping pass is now the resolve pass: it applies exposure,
  color grading, the tone-mapping operator, and the display EOTF, and
  composites bloom.
* Fixed image-based lighting on the OpenGL ES backend.
* Building `.fmat` custom materials requires `flutter_gpu_shaders` 0.4.4 or
  newer.

## 0.14.2

Rendering fixes.

* Fixed mirrored geometry rendering inside-out. A node with a
  negative-determinant transform (a mirror or negative scale) reverses
  triangle winding, so its front faces were being culled. Cull winding now
  follows the sign of the node's world-transform determinant, matching the
  glTF 2.0 spec (section 3.7.4 Instantiation). Applies to the scene pass,
  the shadow pass, and instanced draws.
* Fixed `material.doubleSided` being ignored by the runtime glTF importer.
  Double-sided materials are no longer back-face culled.

## 0.14.1

Quality and packaging pass to a full pub.dev score.

* Now WASM-compatible: the build-hook helpers no longer pull `dart:io` onto
  the web/wasm dependency graph (they run on the native host only).
* Added a package example and a fuller description.
* Bumped `flat_buffers` to `^25.9.23`.
* Internal: lint and formatting cleanup of the generated flatbuffer readers.

## 0.14.0

Renderer overhaul. The lighting/material/scene API changed in a few
breaking ways (small consumer base, worth getting right). See below.

* **Render graph.** Rendering is now structured as an ordered list of
  passes (`RenderGraph` / `RenderGraphPass` / `RenderGraphContext` /
  `Blackboard` / `TransientTexturePool` in `lib/src/render/`), with a
  transient-texture pool and a per-frame blackboard. The frame is
  `ShadowPass?` → `ScenePass` → `TonemapPass`.
* **HDR pipeline.** The scene renders into a floating-point
  (`r16g16b16a16Float`) color target, MSAA-resolved in linear; a
  full-screen `TonemapPass` then applies exposure, the tone-mapping
  operator, and the display EOTF and writes the 8-bit swapchain.
  Material shaders output linear HDR premultiplied by alpha and no
  longer tone-map or gamma-encode (breaking for custom `ShaderMaterial`
  shaders; see `MATERIALS.md`).
* **Tone mapping & exposure moved onto `Scene`.** `Scene.exposure`
  (default `1.0`) and `Scene.toneMapping` (`ToneMappingMode`, default
  Khronos PBR Neutral; ACES / Reinhard / linear also selectable).
  `Scene.physicalCameraExposure({aperture, shutterSpeed, iso})` derives
  an exposure multiplier the photographic way. (Replaces `Environment`'s
  `exposure` / `toneMappingMode` / `exposureFromPhysicalCamera`.)
* **Directional light + shadows.** `DirectionalLight` (direction, color,
  intensity, shadow knobs), assignable as `Scene.directionalLight`,
  layered on top of the image-based lighting with a Cook-Torrance term.
  When `castsShadow` is set, a shadow-map pass renders depth from an
  orthographic light frustum; the PBR shader samples it with 3×3 PCF +
  normal-offset bias.
* **Image-based lighting rework.** Diffuse irradiance is SH-9 (computed
  from the radiance image), specular is a GPU-prefiltered "PMREM-style"
  roughness-band atlas built once at `EnvironmentMap` construction
  (`prefilterEquirectRadiance`, exported). The PBR shader picked up
  fp16-safe GGX, sqrt-free Smith visibility, a roughness floor, and
  Fdez-Agüera multiscatter energy compensation. The old brightness
  fudges (`kEnvironmentMultiplier`, the rough-surface blend) are gone.
* **`Environment` class removed.** Image-based lighting is now
  `Scene.environment` (an `EnvironmentMap`, defaulting to the new
  procedural `EnvironmentMap.studio()`) plus `Scene.environmentIntensity`
  (a scalar). `PhysicallyBasedMaterial.environment` (the per-material
  override) is now an `EnvironmentMap?`.
* **`EnvironmentMap` changes (breaking).** Always carries a prefiltered
  atlas + SH-9 (no nullable getters). New: `EnvironmentMap.studio()` (the
  built-in procedural studio environment, used as the zero-config
  default). `fromAssets` / `fromUIImages` dropped their `irradianceImage`
  params; `fromGpuTextures` now takes a prefiltered atlas (+ optional
  SH); `empty()` is a black atlas + zero SH. The bundled
  `royal_esplanade.png` is still available via `fromAssets` but is no
  longer the default; the unused `royal_esplanade_irradiance.png` asset
  was removed.
* **`ShaderMaterial.useEnvironment`** now binds `prefiltered_radiance` +
  `brdf_lut` (not the former `radiance_texture` / `irradiance_texture` /
  `brdf_lut`).
* **Web support.** `flutter_scene` now runs on Flutter web. Where Impeller
  and Flutter GPU aren't available, it renders through a built-in WebGL2
  backend (a drop-in for `flutter_gpu`), and works under both the CanvasKit
  and Skwasm web renderers. On native platforms it still uses Flutter GPU at
  zero cost.
* **Single package (breaking for direct importer users).**
  `flutter_scene_importer` has been folded into `flutter_scene` and is no
  longer published separately. Its build-hook helper now lives at
  `package:flutter_scene/build_hooks.dart` (`buildModels`). A curated
  `package:flutter_scene/gpu.dart` exposes just the GPU types needed to
  author custom `ShaderMaterial` shaders (`Shader`, `ShaderLibrary`,
  `loadShaderLibraryAsync`, `Texture`, sampler types); the rest of the GPU
  layer is internal.

## 0.13.0

* Add `ShaderMaterial`, the foundation for custom materials. Supply
  a fragment shader (compiled offline through `flutter_gpu_shaders` /
  `impellerc` into a `.shaderbundle`), then bind uniform blocks and
  textures by name with `setUniformBlock` / `setUniformBlockFromFloats`
  / `setTexture`. Render-state knobs (`cullingMode`, `windingOrder`,
  `isOpaqueOverride`) are exposed on the material. The opt-in
  `useEnvironment` flag binds the scene's IBL textures
  (`radiance_texture`, `irradiance_texture`, `brdf_lut`) when the
  fragment shader declares them.
* Add `MATERIALS.md`: an end-to-end guide to the engine uniform /
  varying contract for custom fragment shaders, std140 uniform-block
  packing, the `flutter_gpu_shaders` build-hook setup, and the
  limitations of the current surface (see issue #22 for the planned
  declarative material format).
* The example app gains a worked toon-shader demo
  (`examples/flutter_app/lib/example_toon.dart`).

## 0.12.0

* Add bounding-volume and frustum-culling infrastructure. The scene
  encoder now builds a `Frustum` once per render from the camera's
  view-projection matrix and skips entire subtrees whose combined
  local-space AABB lies outside it.
* Skinned subtrees are culled against an offline-baked pose-union
  AABB that covers every animated pose. The runtime falls through
  to the always-visible path for skinned content imported via the
  runtime GLB importer (`Node.fromGlbBytes` / `Node.fromGlbAsset`)
  since the pose-union analysis runs only in the offline importer.
* New public API:
  - `Geometry.localBounds`, `Geometry.localBoundingSphere`,
    `Geometry.setLocalBounds(aabb, sphere)`.
  - `Mesh.localBounds` (cached union of primitive bounds) and
    `Mesh.markLocalBoundsDirty()`.
  - `Node.combinedLocalBounds` (cached union including transformed
    descendants), `Node.frustumCulled` (default `true`),
    `Node.markBoundsDirty()`, `Node.isVisibleTo(camera, dimensions)`.
  - `Camera.getFrustum(dimensions)`.

## 0.0.1-dev.1

* Initial render box.

## 0.1.0

* Rewrite for Flutter GPU.
* Physically based rendering.
* More conventional interface for scene construction.

## 0.1.1

* Rename PhysicallyBasedMaterial and UnlitMaterial
* Fix environment lighting problems in PhysicallyBasedMaterial.
* Add default environment map.

## 0.2.0

* Skinned mesh import.
* Fix readme for pub.dev.

## 0.2.1-0

* Switch to pre-release versioning.
* Bump version of flutter_scene_importer.

## 0.2.1-1

* Bump flutter_scene_importer version.

## 0.3.0-0

* Add Animation/playback support (Animation, AnimationPlayer, and AnimationClip).
* Import animations from scene models.
* Add support for cloning nodes.

## 0.4.0-0

* Support node cloning for skins.
* Fix default/animation-less pose.

## 0.5.0-0

* Support non-embedded/URI-only image embeds.

## 0.6.0-0

* Fix memory leak in transients buffer.
* Optional MSAA support on iOS and Android (enabled by default).
* Cull backfaces by default.
* Fix animation blending bugs.
* Pin native_assets_cli to <0.9.0
  (https://github.com/bdero/flutter_gpu_shaders/issues/3)
* Add car model and animation blending examples.
* Fancy readme and FAQ.

## 0.7.0-0

* Update to native_assets_cli 0.9.0.
* Update to flutter_gpu_shaders 0.2.0.

## 0.8.0-0

* Update to Flutter 3.29.0-1.0.pre.242.

## 0.9.0-0

* Update to native_assets_cli 0.13.0.
* Update to flutter_gpu_shaders 0.3.0.

## 0.9.1-0

* Fix invalid usage of textureLod on desktop platforms.

## 0.9.2-0

* Fix globalTransform calculation.

## 0.11.1

* Fix `Node.globalTransform` setter. The previous implementation
  computed `transform * parent.globalTransform.invert()`, but
  `Matrix4.invert()` returns the determinant (a `double`) and mutates
  the receiver, so this was scalar-multiplying `transform` by the
  parent's determinant rather than composing with the parent's inverse.
  Coincidentally produced correct results when the parent had `det=1`,
  but produced garbage for any negative-determinant or non-uniformly-
  scaled parent.

## 0.11.0

* Add a runtime GLB importer. `Node.fromGlbBytes(Uint8List)` and
  `Node.fromGlbAsset(String)` decode a glTF binary directly at runtime:
  no offline `.model` conversion, no build-hook step. Useful for
  user-uploaded models, network-loaded assets, and model editors. (#12)
* Bump `flutter_scene_importer` to `^0.11.0` (pure-Dart `.glb` → `.model`
  build hook; CMake is no longer required).

## 0.10.0

* Migrate from `native_assets_cli` (discontinued) to `hooks` 1.0.
  Breaking: build hook authors must now `import 'package:hooks/hooks.dart'`
  instead of `package:native_assets_cli/native_assets_cli.dart`. (#82)
* Drop the `--enable-experiment=native-assets` flag from the importer
  process invocation. The flag was rejected by Dart 3.10+ and was the
  literal cause of build failures for users on recent Dart channels. (#82)
* Reorganize the repository as a pub workspace with separate `flutter_scene`
  and `flutter_scene_importer` packages and an `examples/` sibling. No
  user-facing surface changes from this; consumers see a cleaner package. (#36)
* Update `flutter_gpu_shaders` to `^0.4.0` (also migrated to `hooks`).
