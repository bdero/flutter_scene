## 0.24.0

* Projected box decals via `DecalNode`, an oriented projection volume that paints a `.fmat` material onto whatever opaque surfaces it intersects (scorch marks, splats), with no mesh work at the impact site.
* Radial screen distortion pulses via `Scene.screenDistortion`, expanding shockwave rings that warp the composed image with optional chromatic fringing.
* `.fmat` materials accept `blending: additive` alongside `opaque`/`alpha`, and `depth_write`/`depth_test` configure the translucent depth state.
* Barycentric wireframe helpers, `#include <wireframe.glsl>` plus `MeshData.unweld` barycentric attributes, for wireframe and scan-line overlays on any mesh.
* `MaterialGroup` pushes one parameter value to a heterogeneous set of materials, skipping names a member does not declare.
* Unlit `.fmat` materials may declare `engine_inputs`; the screen accessors gain `GetSceneWorldPosition`, materials that read scene depth get it at full resolution, and `scene_color_reach` bounds a reader so disjoint readers share one scene-color capture.
* A draw whose render pipeline the backend rejects is skipped with a one-time console message naming the material and geometry, instead of failing the whole frame from inside paint.
* A render pipeline build that stalls a frame (8ms or more, always on its first draw) is reported in debug builds with the material and geometry that triggered it, so the fix (drawing it once behind a load screen) has a target.
* Pooled render targets are released when the platform reports memory pressure. The transient pools (shadow atlas, HDR scene color, depth, the post-process chain, probe and planar captures) never evicted, so they settled at the high-water mark of every attachment shape any frame needed and held it for the life of the process; a 512x512 shadow scene pins 114 MiB this way. Set `releaseRenderTargetsOnMemoryPressure = false` to opt out.
* `releaseTransientRenderTargets()` drops those pools on demand and returns the bytes released, for an app that knows something the platform does not.
* `takeMemoryReport()` gains a `render targets` category, so that memory is visible at all.
* glTF sources that spread more than four skin influences per vertex across `JOINTS_1`/`WEIGHTS_1` and beyond are merged to the strongest four and renormalized, instead of importing set 0 alone. Those meshes previously blended a fraction of a unit of weight per vertex and collapsed toward the armature origin even in the rest pose. The merge feeds the skinned pose-union bounds too, so a bone bound only in a later set no longer swings its part of the mesh outside the cull bound.

## 0.23.0

* Build hooks no longer crash on a target OS `package:code_assets` cannot name, which is how a third-party embedder announces tvOS or visionOS.
* tvOS, visionOS, and watchOS select the iOS Metal shader variant, so an app on an Apple embedded platform finds its shader bundles and materials instead of looking for a target nothing builds.
* Added `package:flutter_scene/kit.dart`, high-level gameplay, camera boom, character controller, day/night cycle, water surface, audio, pooling, and debug visualization components.
* BREAKING: model-space front faces wind Counter-Clockwise (CCW) now, across primitives, procedural builders, materials, and `.fscene` version 5, matching glTF and the rest of the ecosystem. Version 4 documents swap index pairs on read and version 4 containers migrate at realization, so assets need no action, but hand-authored index buffers and custom `Geometry` subclasses wind the other way and need their triangles swapped.
* World-space global illumination via `Scene.globalIllumination`, a grid of octahedral irradiance probes fed by scattering the visible surfaces' shaded radiance, so bounce light persists for geometry the camera is not looking at and colored bleed reads correctly. Off by default.
* Probe visibility via `GlobalIlluminationSettings.visibility`, per-direction depth moments and a Chebyshev bound so the field does not leak through walls.
* Emissive surfaces light the probe field, scaled by `GlobalIlluminationSettings.emissiveGiBoost` so a small bright emitter can light a room without brightening the direct image.
* Offline and progressive irradiance field baking via `Scene.bakeIrradianceField` and `IrradianceFieldBakeStepper`.
* `IrradianceVolumeComponent` places the irradiance volume on a node, for authored placement instead of fitting the scene or following the camera.
* `Scene.invalidateGlobalIllumination` discards the accumulated field so it refills from scratch after a hard camera cut.
* The lit shaders read the environment's diffuse coefficients with `texelFetch` from a texture the probe atlas extends, so global illumination costs no additional fragment sampler.
* Add the `flutter_scene-kit` agent skill, covering the gameplay, camera rig, character controller, day/night, water, audio, pooling, and debug components in `kit.dart`.
* Update `flutter_scene-idioms` skill (v4) with the reflection probes and lens flares the engine gained, and the traps that came with them.
* Update `flutter_scene-performance` skill (v2) with SMAA's cost next to FXAA and the per-frame reflection-probe recapture trap.
* Update `flutter_scene-procedural` skill (v2) with natural formation recipes (rock fractures, incised trails, pebble scatter, Gerstner waves, tree branching, and procedural island topographies).
* Update `flutter_scene-looks` skill (v4) with micro-surface and anti-waxiness tuning guidance.
* Update `flutter_scene-verification-loop` skill (v2) with empirical verification disciplines and blind-pairwise review rules.
* Temporal anti-aliasing via `AntiAliasingMode.taa` and `Scene.temporalAntiAliasing`, reprojecting history with camera subpixel jittering, motion vectors for unskinned and skinned geometry, and variance-guided history clamping.
* Geometric specular anti-aliasing adapts specular roughness based on screen-space normal derivatives to suppress high-frequency specular shimmer on subpixel geometry and grazing angles; `Material.specularAaThreshold` configures the threshold.
* `DirectionalShadowFilter.bilinearPcf` continuous 2x2 bilinear percentage-closer filtering.
* `CameraProjection.getProjectionMatrix` adds an optional named `jitter` parameter for temporal subpixel sampling.
* Direct lighting modulates specular and clearcoat terms with `sun_visibility`.
* Added `ExternalTexture`, a `TextureSource` fed by a platform texture id (video, camera preview) with optional `colorFilter`, captured through the compositor on frames that sample it.
* Generated scene registries are cached per asset bundle.
* `.fsceneb` payload chunks compress with gzip, cutting file sizes by ~73% in exchange for higher load-time decompression CPU.
* Static render items skip per-frame property re-assignment when their transform and bounds are unchanged.
* Instanced mesh static shadow updates track component visibility changes correctly.
* Widget-surface pointer forwarding dispatches events in the framework's global space (with the host's transform in the hit path), so widgets that convert `globalPosition` through render objects (Slider, text selection) work when the scene view is not at the window origin.
* The standard PBR shader ships a no-shadow variant, selected automatically for draws with no shadow atlas bound, roughly halving the compiled fragment program for shadow-less scenes on mobile GPUs; it also skips its five per-texture UV-transform evaluations when every transform is identity.
* `PhysicallyBasedMaterial` keeps a scalar `ior`, `specular`, and `specularColor` on the standard shader by folding them into its dielectric reflectance (the `KHR_materials_ior` / `KHR_materials_specular` formula the physical shader uses), so only specular textures and the layered features select the heavier physical variant.
* The model scale is no longer interpolated per fragment (`v_model_scale` left the vertex output interface, cutting varying bandwidth on tiler GPUs); lit materials read it from `FragInfo.model_scale` through the unchanged `GetModelScale()` accessor, now carrying the node's scale rather than per-instance or per-joint scale, and a raw `ShaderMaterial` pair that needs it passes its own varying computed from the model transform.
* glTF import validates `extensionsRequired` and surfaces warnings through an `onWarning` callback on every entry point.
* Sparse glTF accessors apply, including the zero-filled base for an absent `bufferView`.
* `KHR_draco_mesh_compression` decodes in pure Dart on every platform.
* `EXT_meshopt_compression` decodes in pure Dart; `KHR_mesh_quantization` is recognized alongside it.
* Standard KTX2 textures (`KHR_texture_basisu`) load on both import paths, transcoded in pure Dart.
* The runtime importer accepts multi-buffer `.gltf` documents and percent-decodes resource URIs.
* `MeshPrimitive.visible` and `MeshPrimitive.castsShadow` toggle one primitive's color and shadow passes independently.
* `MaterialParameters` gains typed getters, `hasParameter`, `isParameterAssigned`, and parameter enumeration.
* Light channels, `channelMask` on lights and `Node.lightChannelMask` restrict what a light illuminates; `DirectionalLight.shadowCasterChannelMask` filters shadow casters independently.
* `DirectionalLight.firstCascadeFarBound` pins the first cascade split; `cascadeOverlap` cross-fades cascade hand-offs.
* `ShadowCatcherMaterial`, an invisible ground showing only received shadows and ambient occlusion, live by default with a baked mode.
* Morph targets import on both paths, animate via `weights` channels, and blend on the CPU or a GPU morph texture; `Node.morphWeights` drives them.
* `EnvironmentMap.fromKtx2Bytes` loads a pre-baked radiance cubemap with SH-9 diffuse, skipping the load-time prefilter.
* `EXT_lights_image_based` imports as an `ImageBasedLightComponent` on the model root.
* SH-9 diffuse helpers, `parseDiffuseShSidecar`/`encodeDiffuseShSidecar`, `evaluateDiffuseSphericalHarmonics`, and `describeDiffuseSphericalHarmonics` for verifying imported coefficients.
* `PhysicallyBasedMaterial.lightmapTexture` adds a baked lightmap that replaces the SH diffuse ambient.
* `.fmat` `instance_attributes` declare typed per-instance data, set via `InstancedMesh.setInstanceAttribute`.
* A raw `ShaderMaterial` declares the same per-instance data through `ShaderInstanceAttribute`, so a custom vertex shader reads the `instance_<name>` inputs a `.fmat` would have generated.
* `PlanarReflectorComponent` renders a mirrored scene capture that `.fmat` materials sample via the `planar_reflection` engine input.
* `ShaderMaterial.sceneInputs` declares the engine's per-frame scene textures, so a raw shader can refract and measure its own thickness like a `.fmat` material. Include `<scene_inputs.glsl>` for the samplers and their accessors; `buildTargetShaderBundleJson` puts flutter_scene's `shaders/` on the include path so it resolves with no setup.
* Parallax-corrected reflection probes via `ReflectionProbeComponent`, capturing the scene into a local environment whose reflections track the probe's box.
* `Scene.captureEnvironment` renders the scene's lighting at a point into a new `EnvironmentMap`.
* SMAA anti-aliasing via `AntiAliasingMode.smaa`, cleaner edges than FXAA with far less texture blurring.
* Lens flares via `BloomSettings.lensFlare`, ghost chains and a halo with chromatic dispersion off the bloom pyramid.
* Bloom now spreads a consistent fraction of the screen across device pixel ratios, so bloom and lens flares no longer tighten on high-DPI displays; its passes also stop relying on reloaded attachments, matching every backend.
* Clearcoat now responds to rect area lights.
* Screen-space indirect light reprojects its radiance history, so the bounce stays put under camera motion.

## 0.22.2

* Four new agent skills alongside `flutter_scene-idioms`: `flutter_scene-verification-loop` (the run-settle-capture-correct visual loop and the blind-pairwise judgment rule), `flutter_scene-looks` (copy-paste `EnvironmentSettings` presets for a deliberate look), `flutter_scene-procedural` (terrain, noise, and instancing from code), and `flutter_scene-performance` (frame-budget measurement and a fixed remediation order). `dart run flutter_scene:init` and `dart run flutter_scene:skills` now install every bundled skill.

## 0.22.1

* Camera controllers `OrbitCameraController`, `FlyCameraController`, and `FollowCameraController` drive a camera node from drag, scroll, and keyboard input with frame-rate-independent smoothing and clamped pitch. The `CameraControls` widget wires Flutter input to a controller; controllers also expose intent methods (`orbitBy`, `dollyBy`, `look`, ...) for driving them from any source.
* `Node.lookAt`, `Node.lookAtFrom`, and the static `Node.lookAtTransform` orient a node's forward axis (local +Z) at a world-space target, aiming cameras, lights, and imported models without hand-building a view matrix.
* Ship the `flutter_scene-idioms` agent skill, correct-usage guidance for coding agents that corrects the wrong assumptions carried from other 3D engines. `dart run flutter_scene:init` offers to install it, asking first at a terminal and never installing unattended without `--skills`.
* Add `dart run flutter_scene:skills` to install, update, or `--check` the agent skill on its own, without touching the build hook or pubspec.

## 0.22.0

* `Node.position`, `Node.rotation`, and `Node.scale` read and write the local transform one component at a time, and editing a returned copy in place throws in debug builds rather than silently doing nothing.
* `Node.mutateLocalTransform` edits the local matrix in place through a callback and marks the node dirty, the correct way to reach for the raw matrix.
* A frame that draws nothing now prints once in debug builds naming the likely cause (not ready, empty region, no views composite to screen, no visible meshes, or a layer mask matching nothing).
* Degenerate cameras now assert in debug builds, catching a view direction of zero length, an `up` parallel to it, and a field of view passed in degrees.
* The web backend now throws on a bind to a shader uniform or texture name that does not exist, matching native, instead of silently sampling whatever was bound last.
* `SkinnedGeometry.uploadVertexData` and `setCustomAttribute` now throw on a buffer whose length does not match the vertex count, instead of rendering garbage.
* A `Mesh` whose primitive geometry is replaced now recomputes its bounds on its own, rather than over-culling until `markLocalBoundsDirty` is called.
* An `AnimationClip` that binds zero of its channels now asserts in debug builds, naming the wanted nodes, since it otherwise plays while nothing moves.
* Fixed the second and every later `flutter run` rendering nothing, from two hook invocations writing the same shader bundle filenames with different backend trims.
* Fixed `Scene.initializeStaticResources()` reporting ready when the shader bundle loaded but held nothing this engine can read.
* Fixed `dart run flutter_scene:init` then `flutter run` failing on a new app with "Flutter failed to list directory".
* Fixed `Node.clone()` sharing the original's transform matrix.
* Fixed the skinning joints texture being too narrow for small joint counts, which duplicated matrix columns.
* Fixed `ParticleSystem.reset()` not restarting its random stream.
* Mutating `Node.localTransform` in place without `markTransformDirty()` now throws in debug builds instead of silently doing nothing.
* `SceneViewsBuilder` is now exported.
* Documentation fixes for names that no longer exist (`Environment`, `loadModel`, the master channel requirement), plus a readme scene that needs no asset files and a list of the built-in geometry.

## 0.21.1

* Documentation only. The readme spells out how to turn Flutter GPU on for each platform, shows the build hook and the pubspec entry `dart run flutter_scene:init` writes, recommends converting assets ahead of time over importing glTF at runtime, and links the guides at fscene.dev.

## 0.21.0

* Requires Flutter 3.47.0 or newer. That is the first stable carrying the Flutter GPU support this package needs, so the constraint is a real minimum rather than the loose value earlier releases carried. A master build numbered `3.47.0-1.0.pre.N` sorts below it and will not resolve.
* Assets are generated into `flutter_scene_generated/` at the app root and loaded by source path, the same way on every Flutter channel. `dart run flutter_scene:init` installs the hook, creates the directory with a `.gitignore` for its outputs, and adds the one pubspec assets entry it needs.
* `flutter pub add flutter_scene` is the whole setup. flutter_scene's own build hook compiles the engine's shaders for the app being built, on every channel, so an app with no hook of its own renders a runtime-imported `.glb` everywhere including web.
* Compiled shader bundles record the engine that built them and are rebuilt when it changes, so switching Flutter versions cannot leave a bundle the new engine refuses to read.
* `buildEngineAssets` is an optional build-hook call that puts the engine's shaders in the app's own generated tree instead of flutter_scene's.
* Breaking change, `legacyOnly` and `dataAssetsIfAvailable` are removed in favor of `generatedTree`, now the default in `SceneAssetMode`, `TextureAssetMode`, `MaterialAssetMode`, and `TargetShaderBundleAssetMode`. A hook still passing a removed mode fails the build naming its replacement, since outputs moved out of `build/` into the generated tree and an app loading by explicit asset key reads its new keys from the tree's `manifest.json`. Re-run `dart run flutter_scene:init` to migrate a hook and add the pubspec entry. The Dart data assets modes remain as explicit opt-ins and prune the tree entries they replace.
* A build with no generated assets now fails with the exact pubspec lines to add instead of producing an app that dies at its first load.
* Fixed a `.fmat` reference written against the package root binding to a path beside its scene document, which left the material unresolved at load and the geometry on an opaque fallback. A reference only rebases onto the document when a file is actually there, matching how the source-root loader reads the same scene.
* `resolveShaderBundleKey` resolves a shader bundle built by `buildTargetShaderBundleJson` (or `flutter_gpu_shaders`) by name, for `loadShaderLibraryAsync`.
* Build stamps fingerprint a source over a megabyte by size and modification time instead of reading it, cutting about 5 seconds per gigabyte off every build. Set `flutter_scene_strict_hashing: true` under `hooks: user_defines:` in the app pubspec to content-hash everything.
* Switching asset modes needs a clean build. Nothing prunes assets from a previous mode out of an app bundle.
* Breaking change, `buildScenes` and `buildTextures` no longer take `outputDirectory`. Outputs go to the app's generated tree, so a hook passing it fails to compile; drop the argument.
* Breaking change, `FmatMaterialBundleIndex.fromJson` requires `assetKey`. The bundle and its sidecar resolve from the index's own key, so a direct caller passes the key it parsed.
* `Node.extractMeshData` flattens a subtree's geometry into one `MeshData` with the descendant transforms baked in, and `MeshData.toTriMeshShape`/`toConvexHullShape` turn that into a collider, so an imported model no longer needs a hand-written walk to collide.
* `MeshData.transformed` places a snapshot by a matrix, carrying normals by the inverse transpose and, through a mirror, flipping both tangent handedness and triangle winding.
* The lit shaders declare one prefiltered-radiance sampler instead of one per layout, freeing two fragment texture units so a skinned shadow-casting draw fits GLES drivers reporting the 16-unit minimum.
* Breaking change for raw `ShaderMaterial` shaders that sample the environment, they declare `prefiltered_radiance` as `RadianceSampler` and supply a `radianceCubeFragmentShader` variant built with `FLUTTER_SCENE_RADIANCE_CUBE`. `.fmat` materials are unaffected.
* A material or sky that samples the environment without a cubemap-radiance variant now keeps its 2D sampler and is bound a placeholder instead of a mismatched cubemap, and says so in debug builds. `PreprocessedMaterial` takes `radianceCubeFragmentShader` for code that builds one directly rather than through a loader.
* Breaking change, `EnvironmentMap.prefilteredRadianceTexture` and `EnvironmentMap.prefilteredRadianceCube` are gone. The single prefiltered-radiance sampler replaces the layout pair, so code reading either field reads the one texture the map now carries.
* `RenderItem.windingFlipped` derives from its geometry instead of being assignable, so a mirrored transform reverses winding without callers tracking it.
* Breaking change, the fscene component codec API is declarative. `ComponentCodec.serialize` is abstract, `ComponentPropertyDef` and `ComponentPropertyKind` moved to the `scene` schema model (constraints replace `min`/`max`/`read`), and flat codecs extend `DeclarativeComponentCodec`, deriving schema, realization, and delta serialization from one `ComponentField` list.
* `.fscene` version 3. Component properties delta-serialize (values equal to their schema default are omitted) and audio attenuation settings nest; version 2 documents read unchanged.
* `package:flutter_scene/annotations.dart`, `@SceneComponent` and typed property annotations that lower to schema constraints for generated codecs.
* Unknown component types realize as lossless `ForeignComponent` placeholders and round-trip untouched.
* Physics components register in any mount order. A rigid body, collider, joint, or character controller added before its world (or its sibling dependency) registers when the dependency arrives instead of staying inert.
* `registerPhysicsBackend` is public, so physics backend packages can register simulation factories the way audio backends do.
* `FsceneComponentRegistry.unregister` removes a registered codec; documents carrying the type realize it as a lossless unknown-type placeholder.
* `nodeRefOf` and `resourceRefOf` recover document references from live nodes and realized resources, so custom codecs (generated ones included) round-trip them.
* Debug builds launched with `FLUTTER_SCENE_SOURCE_ROOT` read scene sources straight from the project, and `ext.flutter_scene.reloadScene` patches loaded scenes in place.
* Component schemas carry declarative editor gizmos (`ComponentSchema.gizmo`, the `GizmoSpec` primitive model, the `@SceneGizmo` annotation), and the builtin lights, camera, colliders, audio, environment volumes, and particle emitters declare them.
* Builtin component schemas declare richer editing constraints, the camera projection is a fixed-option enum, its field of view carries hard degree bounds, and shadow, area-light, and volume fields gained slider soft ranges.
* `Scene.captureRenderGraph` records one frame's render graph (passes, CPU timings, data flow, snapshot copies of written targets) behind the `Scene.debugAllowRenderGraphCapture` opt-in, and `RenderPassContext.debugBlackboardTexture` exposes raw pipeline textures to debug overlays.
* Screen-space contact shadows for the sun via `DirectionalLight.contactShadows`, grounding small contacts that shadow-map resolution and bias miss.
* Screen-space indirect light via `AmbientOcclusionSettings.indirectLight`, crediting one bounce of scene radiance to newly visible sectors of the occlusion bitmask.
* Rect area lights via `RectAreaLight` and `RectAreaLightComponent`, shaded with linearly transformed cosines so panel highlights stretch and fall off physically.
* Film-look color grading via `ColorGradingSettings.lut`, loading Adobe `.cube` tables with `ColorLut.fromCubeAsset` and blending with `lutBlend`.
* Environments persist the grading LUT (`.cube` reference and blend) in `.fscene` documents, and `ColorLut.sourceAsset` reports where a table was loaded from.
* Percentage-closer soft shadows via `DirectionalShadowFilter.pcss`, sharpening shadows at contact and widening them with caster distance scaled by `DirectionalLight.angularRadius`.
* Depth of field focuses on translucent depth-writing surfaces (fmat `depth_write: true`, transmissive `PhysicallyBasedMaterial`) instead of the backdrop seen through them.

* Ground-truth ambient occlusion via `AmbientOcclusionSettings.method`, integrating horizon-slice visibility with `sliceCount`/`stepsPerSlice` controls and an optional constant-thickness `visibilityBitmask` mode.
* `AmbientOcclusionSettings.multiBounce` keeps albedo-tinted bounce light in occluded creases instead of darkening them to gray.
* `AmbientOcclusionSettings.bentNormals` steers indirect diffuse along the average unoccluded direction and enables `SpecularAmbientOcclusionMode.bentCone`.
* Environment resources persist every ambient-occlusion control, including the new method, slice, thickness, bent-normal, and multi-bounce fields.
* `AmbientOcclusionSettings.intensity` defaults to `1.0` and both methods are calibrated there; the obscurance estimator folds its former 2x, so halve any explicitly set obscurance intensity to keep its look.
* Retuned enable-time defaults, bloom intensity `0.15`, chromatic aberration `0.2`, and auto-exposure clamps of -4 to +4 EV.
* Breaking change, `.fscene` version 2 uses one native coordinate system and offline glTF import bakes source coordinates into it.
* Removed `Handedness`, `UpAxis`, `StageMetadata.unitsPerMeter`, `NodeSpec.excludeFromWindingParity`, `SkyEnvironmentSpec.castShadows`, and the directional-light component schema's `direction` property.
* Runtime glTF import keeps source buffers unchanged and resolves coordinate winding in the renderer.
* Directional-light nodes aim along native local +Z and support explicit primary-light priority.
* Fscene directional lights preserve the complete cascaded-shadow configuration.
* Text scenes can reference a binary payload sidecar with `payloadSource`.
* Fixed world-transform assignment under transformed parents corrupting the parent's cached transform.
* Fixed in-memory glTF import dropping punctual lights and material variants.
* GPU memory can be inspected and released. `takeMemoryReport()` reports what the engine's shared caches are pinning, `releaseTexture`/`releaseScene` give a claim back, and `clearTextureCache`/`clearSceneTemplateCache` drop everything.
* `ResourceGroup.track` scopes a load to the group's lifetime, so `dispose()` releases the claims it took. Previously `dispose()` only released the progress notifier despite the name.
* Fixed `ResourceGroup` throwing when it was disposed while a tracked load was still in flight, which is what tearing down a level mid-load does.
* Fixed `loadScene` keeping a scene template claim when it threw after the template loaded, so a caller that got no `Node` no longer has to issue a compensating `releaseScene`.

* `PhysicallyBasedMaterial` and glTF import support every ratified `KHR_materials_*` extension with scene-native property names.
* Scene startup loads the shared physical-material shader bundle so every `PhysicallyBasedMaterial` property remains synchronous.
* Shader build hooks keep only the target platform backends in generated bundles.
* `KHR_texture_transform` applies independently to every built-in and advanced material texture.
* Geometry and material textures support both UV0 and UV1, including `textureInfo.texCoord` in both glTF import paths.
* `ShaderMaterial` owns the vertex stage too. Pass a `vertexShader` (per `MeshVariant`, so skinned and shadow passes can differ) and set uniforms and textures on either stage with `ShaderStage`, so a hand-written shader pair needs no subclassing.
* Geometry can declare its own pipeline vertex layout with `setVertexLayout`, and `VertexAttributeDescriptor`/`VertexBufferDescriptor`/`VertexLayoutDescriptor` are public.
* Custom vertex attributes work on skinned meshes.
* A `ShaderMaterial` that supplies a vertex shader for some mesh kinds but not others warns in debug builds, naming the missing variant, instead of failing opaquely at pipeline creation.
* Debug builds check a custom material's uniform blocks against the shader's reflection, so a misspelled or optimized-out block name and a buffer too small for its std140 layout raise named exceptions instead of failing at bind time or reading past the end.
* Debug builds check a caller-declared vertex layout against the buffers actually bound, so a slot count mismatch raises instead of feeding the pipeline undefined vertex data.
* `IndexType`, `VertexFormat`, and `VertexStepMode` are exported, so 32-bit indices and caller-declared layouts no longer need `lib/src` imports.
* Made first-party shader/material hooks and examples DataAssets-only, with migration guidance for legacy assets.
* `buildMaterials` registers generated outputs as DataAssets when available by default.
* Added `Node.castsShadows` for excluding individual meshes from shadow passes.
* Added `GeometryBufferArena` and `GeometryBuilder.build({bufferArena, retainCpuData})` for lower-overhead immutable mesh batches.
* Added per-instance colors through `InstancedMesh.addInstance(color:)` and `setInstanceColor`.
* Breaking change, instanced vertex layouts now require `instance_color` and use an 80-byte instance stride instead of 64 bytes.
* Added `InstancedMesh.updateInstanceTransforms` for allocation-light bulk motion and `InstancedMesh.cullInstances` for opt-in per-instance culling.
* Added `InstancedMesh.sortTransparentInstances` to skip unnecessary particle sorting.
* Added `RenderView.cullingPlanes` for application-defined frustum planes and `Scene.warmUp(includeOffscreen:)` for full-scene preparation.
* Added `SunLight.cacheStaticShadows` and `DirectionalLight.cacheStaticShadows` for continuously changing shadow lights.
* Added `SunLight.shadowFilter` and `DirectionalShadowFilter.fixedPcf` for stable lower-ALU shadow filtering.
* Tightened stable cascade fitting to increase effective shadow resolution.
* Reduced shadow-map color bandwidth with single-channel fp32 tiles.
* Fixed cascade-edge striping from normal-biased receiver positions.
* Switched material and resolve color conversion to exact sRGB transfer functions.
* Cached instanced bounds and render data to keep moving-camera culling allocation-light.
* Skipped per-instance bounds packing when instance culling is disabled.
* Skipped per-instance culling when an entire batch is inside every active plane.
* Reused large transient buffers across changing instance counts.
* Translucent instanced meshes now sort as one batch, with instances ordered within it.
* Translucent draws sort back to front by view-axis depth through their geometry bounds center.
* Double-sided lit materials reverse geometric normals on back-facing fragments.
* Fixed instanced meshes losing their lighting, shadow, and fog bindings on GLES, which drew them (and any mesh sharing their pipeline) black.
* Fixed anisotropy strength being ignored by environment lighting and using an isotropic visibility term for analytic lights.
* Fixed anisotropic materials exposing primitive triangles by importing and interpolating authored tangents.
* Vertex payload layouts include UV1 and tangents under versioned names, growing unskinned payloads by 50% and skinned payloads by 30%; older `.fscene` layouts upgrade when loaded.
* Fixed runtime glTF normal maps building color-filtered mips, which skewed minified normals and washed out reflective materials.
* Fixed uncompressed `.fsceneb` textures uploading without mipmaps, so a cooked scene is mipmapped whether or not `compressTextures` is set.
* Fixed cooked `.fsceneb` and `.fstex` textures sampling without anisotropic filtering, which blurred them at grazing angles.
* Texture resources record what their pixels represent, so mip levels downsample by role (normal maps average as vectors, color in linear light).
* `buildScenes` warns when a texture is not block aligned and falls back to uncompressed, instead of dropping the compressed form silently.
* `buildScenes` and `buildTextures` take `alignForCompression` to resample a misaligned source up to the next multiple of 4 rather than failing or storing it uncompressed.
* Cooked textures build their mip chain on a background isolate, so a large uncompressed scene no longer pays for it on the calling thread.
* Devices measured to sample every texture at its base mip skip mip chains entirely, reclaiming the memory and transcode time they were spending on levels the sampler ignores, and say so once at startup.
* Loose images cook to compressed, mipmapped `.fstex` through `buildTextures`, loaded by source path with `loadTexture` (shipped in 0.20.0, missing from its notes).
* Fixed a `RangeError` when an updatable mesh rebuilds at a smaller vertex count.
* Fixed ambient-occlusion banding and over-darkening with normalized sampling, robust normals, and depth-aware filtering.
* Ambient occlusion gains power, detail, horizon, direct-light, depth-mip, and specular controls. Intensity now scales obscurance, defaults to `2.0`, and its former contrast role is `power`.
* Baked and screen-space ambient occlusion now combine with `min` instead of multiplication.
* Added `ToneMappingMode.agx` with configurable `Scene.agxWhite` and `Scene.agxContrast`, persisted by environment resources.
* Added `Material.depthBias`, a world-space camera offset for coplanar surface details.
* Breaking change, custom `Geometry.bind` overrides must add the named parameter `double depthBias = 0.0`.
* `EnvironmentSettings` preserves every ambient-occlusion control and can apply only its environment look with `applyLookTo`.
* Added `EnvironmentMap.constantDiffuse` and declarative `ConstantEnvironment` ambient lighting.
* Added declarative torus and icosphere geometry specs.
* `ParticleSystem.prewarm` is now readable after construction.
* Nested prefab material overrides and linked material/scene references now compose and round-trip.
* Custom asset bundles can load fmat shaders from bytes and provide their own fmat material loader.
* Cooked glTF scenes import photometric punctual lights for use with physical camera exposure.

## 0.20.0

* The `.fscene` document core (document model, stable ids, JSON/binary serialization, prefab composition, diffing) moved to the new pure-Dart `scene` package; `flutter_scene` re-exports it, so existing imports are unchanged.
* Fixed the web backend dropping every uniform-block draw on drivers that pad uniform block sizes (Mesa on Linux).
* New declarative scene API. `SceneView.declarative`, `SceneNode`, `SceneMesh`, and `SceneModel` describe scenes in `build()`, with bridges to and from the imperative API, which is unchanged.
* Declarative animation control via `SceneModel.animations` (`SceneAnimationSpec`), plus cached model templates so equal sources load once and share GPU resources.
* `KHR_materials_variants` support in both import paths via `MaterialsVariantsComponent`, declaratively via `SceneModel.variant`, with a new Configurator example.
* Fixed animation blending collapsing rigs with mirrored bones.
* Fixed slerp taking the long arc when interpolating between quaternions in opposite hemispheres.
* Automatic exposure (eye adaptation) via `Scene.autoExposure`, metered entirely on the GPU.
* Imported materials keep their source names via the new `Material.name`.
* Fixed cloned skinned meshes all drawing with the last-updated skeleton.
* Physics backends now implement the pure `PhysicsSimulation` contract from the `scene` package and no longer depend on Flutter, so the same simulations run under plain `dart run`.
* One generic physics component layer for every backend. `PhysicsWorld(RapierWorld())`, plus concrete `RigidBody`, `Collider`, the joint components, and `KinematicCharacterController`; the backend-specific component classes are gone.
* Backend-specific physics features stay first-class. `RigidBody.handle`, `Collider.handles`, and `Joint.handle` are public, so downcasting `PhysicsWorld.simulation` to a backend reaches capabilities beyond the shared contract, and the components subclass for typed backend components.
* Physics is now an optional sub-barrel. Import `package:flutter_scene/physics.dart` (or `package:scene/physics.dart` for the pure contract); the core `package:flutter_scene/scene.dart` no longer carries physics types.
* `BasicSimulation` (queries and triggers, pure Dart) replaces `BasicPhysicsWorld`/`BasicCollider`/`BasicKinematicBody`.
* Colliders without a sibling `RigidBody` now attach as static geometry instead of throwing.
* Spatial audio through an optional pluggable-backend contract. `AudioEngine` (implemented by `flutter_scene_soloud` and `flutter_scene_fmod`), with `AudioListener`, `AudioSource`/`ClipAudioSource`, `AudioBus`, and distance attenuation. Import `package:flutter_scene/audio.dart`; it is not in the core barrel.
* CPU particle systems are now public. `ParticleEmitterComponent` (camera-facing billboards), `MeshParticleEmitterComponent` (instanced 3D debris), and `TrailComponent` (ribbon trails), all driven by a `ParticleSystem` built from emitter shapes, spawners, over-life distributions, and a module stack (acceleration, drag, size/color-over-life, rotation, flipbook, curl-noise turbulence), with new Particles and Explosion examples.
* Sprites and billboard particles depth-test against opaque geometry again, so closer objects occlude them.

## 0.19.0

* Steady-state frame allocations cut sharply. Fullscreen passes reuse cached pipelines and per-draw uniform packs reuse scratch buffers.
* Faster draw submission. Bindings clear only on pipeline change and the engine lighting set rebinds only when it actually changes.
* Cheaper `MeshGeometry.fromArrays` for streamed meshes. Bulk attribute copies, no repack for typed index lists, and an optional caller-supplied `bounds`.
* Depth of field with shaped bokeh via `scene.depthOfField`, driven by a thin-lens camera model with three quality tiers.
* Cached shadow tiles for nodes marked `shadowStatic`, making static-world shadow rendering near free.
* Alpha-masked materials are now alpha-tested in the shadow and depth passes, so cutouts cast and receive correctly.
* Materials can declare per-frame scene inputs (`scene_color`, `scene_depth`) for refraction and depth-fade effects, and `MaterialInputs` gains `specular`.
* Fixed `.fmat` skies with `requires: [environment]` sampling black on the roughness-mip layout, and `ShaderSkySource.sampledEnvironment` pins the sampled map.
* The lit shader reads diffuse SH through one sampler, fixing skinned-mesh crashes on 16-unit GLES drivers (ANGLE on Windows).
* Fixed white speckles in compressed textures on devices preferring BC formats.
* Scene-graph conveniences. `Node.meshNodes`, `Node.combinedWorldBounds`, and `PerspectiveCamera.framing`.
* 3D Gaussian splatting. Load `.ply`/`.splat` captures with `GaussianSplats` and draw them with `SplatComponent`, with a new example.
* Scene content can be exposed to assistive technology via `SemanticsComponent`, including hosted widget-surface semantics.
* `WidgetComponent` gains opt-in `occlusionHiding`.
* Added `Camera.worldToScreen`.
* A failed static-resource load no longer marks the engine ready to render; it retries instead of crashing mid-frame.
* Point and spot lights. `PointLightComponent` and `SpotLightComponent`, unlimited BVH-culled lights, spot shadows, `KHR_lights_punctual` import, and a Lights example.
* Geometry readback and derivation. `Geometry.extractMeshData()`, `MeshData` ops (`unweld`, `extractEdges`, `merge`), and `LineSegmentsGeometry` for thick lines.
* Per-frame transient GPU data rides a completion-aware arena allocator, fixing whole-frame aborts past ~1MB of transients and collapsing per-draw buffer writes.
* BREAKING: the custom-pass and material/geometry `bind` surfaces take a `TransientWriter` where they previously took a `gpu.HostBuffer`.
* Large speedup for many-draw scenes on the web backend. No more per-draw buffer ghosting, vertex state cached in VAOs, redundant sampler calls skipped.
* The web shim's `HostBuffer` is a faithful flutter_gpu port again.
* On the web backend, an active but unbound uniform block reads zeros instead of rejecting the draw, fixing unlit `.fmat` materials rendering nothing.
* Fixed ambient occlusion and reflections sampling the wrong depth for double-sided materials.
* The `.fmat` compiler no longer lets declared but unread resources strip out of the generated shaders, which surfaced as build errors or draw-time crashes.
* Built-in noise matched between CPU and GPU via `package:flutter_scene/noise.dart` and `#include <noise.glsl>` (the Dart side is native-only for now).
* `AmbientOcclusionSettings.depthMipChain` (off by default) keeps occlusion accurate on grazing surfaces and large radii.
* Distance fog via `scene.fog`, with falloff modes, a height term, light in-scatter, and sky-color blending.
* Custom render passes via `Scene.addRenderPass`, powering the new `Node.highlightColor` selection outlines.
* Custom passes can request scene buffers (`depth`, `normals`, `shadowMap`) through `RenderInput`.
* Volumetric god rays via `scene.godRays`.
* Load gating and warm-up. `ResourceGroup`, `SceneView.loading`/`revealMinDuration`, `Scene.warmUp`, and background-isolate GLB geometry packing.
* Widget-texture captures stay on the GPU on texture-backed platforms, removing the per-capture CPU round trip.
* `.fmat` materials gain a vertex stage (a `Vertex()` hook, `varyings`, custom `attributes`), applied consistently across the color, shadow, depth, and pick passes.
* Built-in materials and geometries can now be constructed before `Scene.initializeStaticResources()` completes.
* Added `Scene.camera` with `CameraComponent` auto-promotion, and a default camera so a bare `SceneView(scene)` always renders.
* Camera-facing billboards and sprites via `BillboardGeometry`, `SpriteMaterial`, and `Sprite`.
* Directional-shadow controls. `shadowAmbientStrength`, `shadowCasterFaces`, and cascades that extend toward the sun so long shadows stop dropping out.
* Fixed the cascaded-shadow lookup misreading cascades on GLES and crashing the shader compiler on Windows.
* BREAKING: vertex layouts are described by `VertexLayoutDescriptor` and unskinned geometry is structure of arrays (`.fscene` gains `unskinned_soa`; old files still load).
* New procedural primitives. Cylinder, capsule, torus, disc, ring, and icosphere, each with a `collisionShape` physics bridge.
* Geometry level of detail via `LodComponent`, with screen-size selection, hysteresis, and dithered cross-fade.
* Image-based lighting prefilters into a mipped radiance cubemap, and `EnvironmentMap.fromEquirectHdr` keeps HDR intensity through the prefilter.
* Spatial environment volumes with camera-driven blending via `EnvironmentSettings`, `Scene.baseEnvironment`, and `EnvironmentVolume`.
* Sky-driven sun light via `Scene.sunLight`, aiming and coloring the directional light from the sky.
* BREAKING: `.fscene` stages reference an environment resource instead of inline stage fields, and prefab host-node additions are `Attachment`s.
* Added `Texture2D` (generated mips, trilinear and anisotropic filtering) with `TextureContent`/`TextureSampling`; imported models are now mipmapped.
* BREAKING: material texture slots hold a `TextureSource` instead of a raw `gpu.Texture`.
* Added `TextureAtlas` for uniform tile grids.
* Added geometric specular antialiasing to `PhysicallyBasedMaterial`.
* Fixed the split-sum specular lookup sampling with its roughness axis flipped.
* Fixed image-based lighting taking the shadow-ambient gate and Fresnel term from the normal-mapped normal.
* Fixed `normalScale` not being applied to the perturbed normal.
* Screen-space reflections via `Scene.screenSpaceReflections`, with an example and live tuning panel.
* Screen-space reflections fade out on rough surfaces.
* The environment BRDF lookup is generated at load as `RGBA16F`, removing banding and the bundled PNG.

## 0.18.1

* No code changes. Reworded the package description and added the logo as a pub.dev screenshot.

## 0.18.0

* Offscreen render targets via `RenderTexture`, `Scene.views`, and the `RenderTextureView` widget.
* The prefiltered-radiance environment stores roughness bands as mips of one texture (smoother transitions, ~25% less memory).
* Fixed dim image-based specular lighting on the web backend by re-baking radiance after the first presented frame.
* The base shader bundle loads asynchronously on every backend; await `Scene.initializeStaticResources()` before constructing geometry or materials.
* The `flutter` SDK constraint is now `>=3.44.0`; the real requirement is a 2026-06-09 or later master build (see the README).
* Render targets serialize in `.fscene` via a `renderTexture` resource kind and a top-level `views` array.
* Material texture slots accept a `RenderTexture` for live render-to-texture sampling.
* Added render scaling (`Scene.renderScale`) and composite filtering (`Scene.filterQuality`), with per-view overrides.
* Added FXAA and an automatic anti-aliasing mode; `auto` is the new default, so backends without MSAA now get FXAA.
* Adopted hardware instancing for `InstancedMesh`. Breaking for direct `VertexLayout` construction, which now takes a list of `VertexBuffer`s.
* BREAKING: package exports are explicit show lists; file an issue if a symbol you used disappeared.
* Added scene raycasting via `Scene.raycast`/`raycastAll`, with layer masks and `Node.raycastable`.
* Added `WidgetComponent`, a live interactive widget subtree on a scene surface.
* Added automatic widget-surface input, with `WidgetInput.manual` opt-out and `SceneView.debugWidgetInput`.
* Added `ScenePointer` for programmatic scene input.
* Added `WidgetTexture` and `Camera.screenPointToRay`.
* Added `UnlitMaterial.alphaMode`.
* Added `Surface.lastSwapchainColorTexture` for one-frame feedback effects.
* Fixed vertically flipped texturing on the cuboid and wedge primitives.

## 0.17.0

* Added `SceneView`, a widget that renders a `Scene` and drives its frame loop.
* Added debug-mode hot reload for `.fmat` materials and re-exported `.glb` scenes, patched in place.
* Added DataAssets-backed GLB import with auto-discovery, cached composed documents, and `dart run flutter_scene:init` wiring.
* Added `AnimationClip.rebind`/`AnimationPlayer.rebind` and `Mesh.clone`.
* Skinned geometry from `buildScenes` carries a pose-union bound for sound frustum culling.
* BREAKING: removed the `.model` format; convert with `buildScenes` or load GLBs at runtime.
* BREAKING: `.fmat` materials are discovered under `assets/` and loaded by source path via `loadFmatMaterial`.
* Building `.fmat` materials and models requires `flutter_gpu_shaders` 0.5.0.
* Added the `.fscene`/`.fsceneb` serialized scene format with prefabs, hot reload, and deterministic composition.
* Added scene serialization via `serializeScene` and `realizeStage`/`serializeStage`, round-tripping byte-stably.
* Added opt-in KTX2 texture compression for imported scenes, transcoded at load off the main isolate.
* BREAKING: fixed vertically inverted image-based lighting; loaded panoramas now light correctly.
* Added a skybox via `Scene.skybox` and the built-in `EnvironmentSkySource`.
* Added custom sky shaders via `ShaderSkySource` and `.fmat` `sky` blocks.
* Added sky-driven lighting via `EnvironmentMap.fromSky` and `Scene.skyEnvironment`, with time-sliced re-bakes.
* Added built-in procedural skies, `GradientSkySource` and `PhysicalSkySource`.
* Diffuse SH coefficients are sampled from a texture, and `fromGpuTextures` accepts a GPU-computed `diffuseShTexture`.
* A `.fmat` compile failure during hot reload keeps the last good shaders and reports the error.
* Build-hook conversions are cached by input content; set `FLUTTER_SCENE_DISABLE_BUILD_CACHE` to always reconvert.
* Fixed progressive slowdown on the web backend from leaked framebuffers and per-frame program re-links.

## 0.16.0

* Added an abstract physics contract (bodies, colliders, joints, queries, events) with a built-in kinematic world; a full backend ships in `flutter_scene_rapier`.
* Added `WedgeGeometry`, a triangular-prism ramp primitive.
* Added optional screen-space ambient occlusion via `Scene.ambientOcclusion`, working on every backend.

## 0.15.1

* Added a DataAssets-backed `.fmat` material workflow with auto-discovery.
* Added `dart run flutter_scene:init`.
* Added `FmatMaterialRegistry` and `loadFmatMaterial`.
* Updated `flutter_gpu_shaders` to `^0.4.5` and moved hook-time dependencies to `hooks` 2.x/`data_assets` 0.20.x.

## 0.15.0

* Added the `.fmat` custom-material format, compiled by `buildMaterials` and driven at runtime with typed parameters. See `MATERIALS.md`.
* Added a post-processing suite via `Scene.postProcess` (bloom, color grading, vignette, chromatic aberration, film grain), each off by default.
* Added `PostEffect` for custom post-processing shaders. See `POST_PROCESSING.md`.
* The tone-mapping pass is now the resolve pass (exposure, grading, tone map, EOTF, bloom composite).
* Fixed image-based lighting on the OpenGL ES backend.
* Building `.fmat` custom materials requires `flutter_gpu_shaders` 0.4.4 or newer.

## 0.14.2

* Fixed mirrored geometry rendering inside-out; cull winding now follows the world-transform determinant.
* Fixed `material.doubleSided` being ignored by the runtime glTF importer.

## 0.14.1

* Now WASM-compatible; build-hook helpers no longer pull `dart:io` onto the web graph.
* Added a package example and a fuller description.
* Bumped `flat_buffers` to `^25.9.23`.
* Internal lint and formatting cleanup.

## 0.14.0

Renderer overhaul, with several breaking changes.

* Rendering is structured as a render graph (`ShadowPass?` -> `ScenePass` -> `TonemapPass`) with a transient-texture pool.
* HDR pipeline. The scene renders to a float target and a tone-map pass writes the swapchain; custom shaders now output linear HDR premultiplied by alpha (see `MATERIALS.md`).
* Tone mapping and exposure moved onto `Scene` (`exposure`, `toneMapping`, `physicalCameraExposure`).
* Added `DirectionalLight` with PCF shadow mapping, assignable as `Scene.directionalLight`.
* Image-based lighting rework. SH-9 diffuse, a GPU-prefiltered specular atlas, and the old brightness fudges removed.
* BREAKING: `Environment` removed in favor of `Scene.environment` (an `EnvironmentMap`) and `Scene.environmentIntensity`.
* BREAKING: `EnvironmentMap` always carries a prefiltered atlas plus SH-9; the procedural `EnvironmentMap.studio()` is the new default.
* `ShaderMaterial.useEnvironment` now binds `prefiltered_radiance` and `brdf_lut`.
* Web support. flutter_scene runs on Flutter web through a built-in WebGL2 backend, under both CanvasKit and Skwasm.
* BREAKING: `flutter_scene_importer` folded into `flutter_scene` (`package:flutter_scene/build_hooks.dart`), with a curated `gpu.dart` for custom shaders.

## 0.13.0

* Added `ShaderMaterial`, custom fragment shaders with uniform and texture binding by name and render-state knobs.
* Added `MATERIALS.md`, the custom-shader contract guide.
* The example app gains a toon-shader demo.

## 0.12.0

* Added bounding-volume and frustum culling, with offline pose-union bounds for skinned content.
* New bounds API on `Geometry`, `Mesh`, and `Node`, plus `Camera.getFrustum`.

## 0.0.1-dev.1

* Initial render box.

## 0.1.0

* Rewrite for Flutter GPU.
* Physically based rendering.
* More conventional interface for scene construction.

## 0.1.1

* Rename PhysicallyBasedMaterial and UnlitMaterial.
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

* Add animation playback (Animation, AnimationPlayer, AnimationClip).
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
* Pin native_assets_cli to <0.9.0.
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

* Fixed the `Node.globalTransform` setter scaling by the parent's determinant instead of composing with its inverse.

## 0.11.0

* Added a runtime GLB importer, `Node.fromGlbBytes` and `Node.fromGlbAsset`. (#12)
* Bumped `flutter_scene_importer` to `^0.11.0` (pure Dart, no CMake).

## 0.10.0

* Migrated from the discontinued `native_assets_cli` to `hooks` 1.0; build hooks now import `package:hooks/hooks.dart`. (#82)
* Dropped the obsolete `--enable-experiment=native-assets` flag that broke builds on Dart 3.10+. (#82)
* Reorganized the repository as a pub workspace. (#36)
* Updated `flutter_gpu_shaders` to `^0.4.0`.
