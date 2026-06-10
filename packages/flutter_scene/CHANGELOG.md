## 0.17.0

* Added `SceneView`, a widget that renders a `Scene` and drives its per-frame
  loop, so apps no longer write their own `CustomPainter`. It takes a fixed
  `camera` or a `cameraBuilder(elapsed)` and exposes the scene to descendants
  through `SceneScope`.
* Added debug-mode hot reload for assets, driven by `SceneView`. Editing a
  `.fmat` updates the running scene in place (culling, blending, shading model,
  and parameter defaults, plus the GLSL body) with no app code, and re-exporting
  a `.glb` swaps the model in place while preserving its transform and animation
  playback. Load materials and models by source path (`loadFmatMaterial`,
  `loadModel`) to participate; `loadModel` takes an optional `onReload` callback
  for re-applying per-instance customizations after a model is swapped in.
* Added DataAssets-backed GLB model import: `buildModels` can auto-discover
  `assets/**/*.glb` and register the generated `.model` files as DataAssets, and
  `loadModel` / `ModelRegistry` load them by source path. Requires Dart data
  assets (`flutter config --enable-dart-data-assets`). Imported models are
  cached, so repeated loads are cheap (`Node.fromAsset` returns a clone). The
  `dart run flutter_scene:init` hook now wires up both `buildModels` and
  `buildMaterials`. Both accept a `discoveryRoot` to auto-discover under a
  directory other than `assets/`, or an explicit list to bypass discovery.
* Added `Node.reloadFromTemplate`, `AnimationClip.rebind` / `AnimationPlayer.rebind`
  (in-place model reload with animation re-binding), and `Mesh.clone` so cloned
  model instances get independent materials.
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
* Added optional texture compression for imported models and scenes, opt in
  via `compressTextures` on the importers and build hooks. Images are stored
  as mipped, supercompressed KTX2 block payloads and transcoded at load to a
  format the device supports (BC1, ETC2, or ASTC, with an rgba8 fallback);
  transcoding runs off the main isolate.
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
* Build-hook conversions (models, scenes, and materials) are now cached by
  input content, so a hook rerun for an unrelated edit skips unchanged
  sources. Editing one `.fmat` no longer re-imports every model on hot
  reload. Set `FLUTTER_SCENE_DISABLE_BUILD_CACHE` to always reconvert.

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
