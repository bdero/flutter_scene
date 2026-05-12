# flutter_scene renderer roadmap

Status: living design doc. This is the working reference for the rendering iteration on the `bdero/renderer` branch.

## Goal

flutter_scene should be a "looks great by default" general-purpose 3D renderer (competitive with Apple's RealityKit) that scales from product configurators up to higher-fidelity mobile games, while staying flexible enough for custom rendering. Mobile (iOS/Android, tile-based GPUs) is the primary target; desktop is a superset.

## Where we are today

The renderer (`packages/flutter_scene`) is a clean but minimal **single-pass forward renderer**:

- **Frame**: `Scene.render()` → `SceneEncoder` → one opaque pass (depth write, no blend) in scene-graph order, then translucent draws queued, depth-sorted back-to-front, replayed with premultiplied source-over. Frustum + AABB culling per subtree. 2-deep render-target ring; optional 4× MSAA.
- **Materials**: `PhysicallyBasedMaterial` (glTF metallic-roughness), `UnlitMaterial`, `ShaderMaterial` (BYO fragment shader). Fixed shaders, no permutations; feature toggles via uniform flags + placeholder textures.
- **Lighting**: **IBL only; no analytic lights at all** (no directional/point/spot, no shadows). IBL = equirectangular radiance + irradiance textures + a baked BRDF LUT.
- **The "hackery"** is all in IBL: a hardcoded `2.0` brightness multiplier (`flutter_scene_standard.frag:75-77`), roughness LOD clamped to 4 mips, and a `mix(irradiance, prefiltered, pow(1.02-roughness, 12))` fudge that exists *because roughness mip levels aren't generated*. All admitted in TODO comments.
- **Tone mapping**: ACES filmic with an `exposure` uniform. LDR throughout (no HDR framebuffer). Manual gamma on non-Metal backends.
- **Skinning**: GPU, joint matrices in an RGBA32F texture. No instancing. No morph targets.
- **Static defaults**: `royal_esplanade` IBL (792 KB radiance PNG + 22 KB irradiance) + `ibl_brdf_lut.png`, loaded in `Scene.initializeStaticResources()`.

Bones are good. It's a PBR-IBL-only renderer with no direct lighting, no shadows, no post chain, and IBL that's visibly approximated because the underlying GPU API couldn't (until recently) do mipmapped cubemaps.

## What Flutter GPU gives us today

Flutter GPU is the Impeller-backed abstraction over Metal/Vulkan. It does GPU/CPU sync internally and exposes no barriers. Verified against the engine sources:

**Available now:**
- `TextureType.textureCube` **already exists**; cubemaps aren't missing from the type system, only the *upload path* is limited.
- HDR-capable float formats: `r16g16b16a16Float`, `r32g32b32a32Float`, plus `b10g10r10XR` wide-gamut. sRGB formats. So an HDR offscreen pipeline is possible today.
- Full render-target control: MRT (`List<ColorAttachment>`), per-attachment blend, depth+stencil, MSAA at **1× or 4×** (`doesSupportOffscreenMSAA` query), `multisampleResolve` store actions. **Render-to-texture then sample-later works**; offscreen passes are fully doable.
- Full pipeline state: blend equations, depth test/write, stencil ops per face, cull mode, winding, polygon mode (fill/line), primitive topology, viewport/scissor.
- Samplers: min/mag/mip filters, clamp/repeat/mirror. (No anisotropic, no depth-compare samplers.)
- Shader bundles via `flutter_gpu_shaders` (offline `impellerc`), with reflection (`getUniformSlot`, member offsets).
- `HostBuffer` bump-allocator with multi-frame cycling for transient uniforms.

**Gaps (not available):**
1. **Mipmap upload / generation / mip-chain allocation**: `Texture.overwrite()` writes base level only. *The* blocker for correct prefiltered-specular IBL and trilinear texture filtering.
2. **Cubemap face/mip upload**: type exists, no API to fill faces.
3. **No compute shaders / storage buffers**: explicitly excluded (FATAL on the compute stage).
4. **No buffer/texture readback** (GPU to CPU). No occlusion/timestamp queries.
5. **No input attachments / subpass exposure**: can't do tile-memory subpass merging.
6. **No anisotropic filtering; no depth-compare samplers** (PCF must be done manually).
7. Single-channel float formats (`r32Float`) not implemented (FATAL).
8. No depth bias / slope-scale bias (matters for shadow acne).

No cubemap/mipmap work has landed in the `bdero/flutter` fork's `lib/gpu` yet.

## Reference engines (what we're borrowing)

**Filament** is the closest analog (mobile-first PBR engine, same constraints). Steal:
- **Diffuse irradiance as spherical harmonics (SH-9)**, not a cubemap: 9 RGB coefficients, evaluated as a polynomial on the normal. No texture fetch, no float textures, no compute, no mipmaps. Bake the Lambertian `1/π` + cosine convolution into the coefficients. (2 bands / 4 coeffs as a low-end fallback.)
- **Prefiltered specular**: 256² cubemap, ~9 mips, `lod = 8·perceptualRoughness` with a γ=2 roughness-to-mip remap.
- **DFG/BRDF LUT**: 128×128, two channels (ideally RG16F), or ship the **Karis '14 analytic approximation** in-shader and skip the LUT/sampler (trade: lose multiscatter energy compensation).
- **fp16 mobile hazards**: clamp `perceptualRoughness ≥ 0.089` on mobile, fp16-safe GGX (`NxH = cross(N,H)`), sqrt-free Smith visibility.
- **Multiscatter energy compensation** for rough metals (cheap; derived from the LUT's directional-albedo term).
- **Physically-based camera + light units**: lux/lumen/nits, aperture/shutter/ISO → `EV100` → a single exposure multiply. The big "looks right by default" lever.
- **Khronos PBR Neutral tone mapper** as the default (ACES/AgX desaturate, which is poison for configurators). model-viewer, three.js, Filament all moved to PBR Neutral as the e-commerce default in 2024.
- Production IBL path is **offline** (`cmgen` bakes HDR → KTX cube + SH), which maps directly onto our `flutter_scene_importer` build-hook architecture.

**three.js** shows the **no-compute runtime IBL path**: `PMREMGenerator` prefilters with fragment-shader passes into half-float render targets: GGX importance sampling, separable Gaussian-on-sphere blur down the chain, ~6 extra low-res mips with hand-tuned sigmas, faces packed into a 2D atlas ("CubeUV") for manual filtering. Implementable on Flutter GPU as-is. `RoomEnvironment` (a procedural studio room rendered to a cube) is their "looks good with zero asset download" default. Also: three.js is migrating from ubershader-`#define`-permutations to TSL (a material node graph that lowers to GLSL *or* WGSL): the cautionary tale that permutation approaches don't scale to many features × custom materials × multiple backends.

**Bevy / Godot / Unreal / Unity** (architecture & mobile):
- Mobile consensus is **forward, not deferred** (direct lit output → cheap 4×MSAA, no G-buffer bandwidth).
- **4×MSAA is the mobile AA baseline; FXAA the fallback. TAA is not a mobile default.** We already do 4×MSAA.
- **Many lights → clustered/tiled forward ("Forward+")**: Filament does the light binning **on the CPU** when compute is unavailable (rasterize each light into the froxels it touches; upload per-froxel light lists as a texture). Viable here without compute, but a back-pocket upgrade; Godot's *mobile* renderer caps at 8 lights/mesh with no clustering and that's fine for our use cases.
- **Reflections on mobile = baked cubemap probes with nearest-probe selection.** Parallax-corrected cubemaps are the cheap quality upgrade. Nobody ships SSR as a mobile baseline.
- **Render graphs**: Frostbite's frame graph (2017) is the canonical design (passes declare read/write of virtual resources; framework topo-sorts, culls unused passes, aliases transient memory, inserts barriers). But Bevy keeps debating whether the heavy machinery was worth it (their slots ended up mostly bypassed); Granite's author calls his ~3000-line implementation "probably overkill for simpler use cases." **Since Flutter GPU already does synchronization, the barrier-insertion + transient-aliasing payoff is mostly gone; keep only the organizational half.**

## The minimal render graph

Don't build a Frostbite-grade frame graph. Build the 80/20 version (~few hundred lines):

- A **pass list / mini-DAG**: each pass declares named inputs (render targets it samples) and outputs (targets it writes). Concrete passes: `ShadowPass`, `OpaquePass`, `SkyPass`, `TransparentPass`, `BloomDownsample/Upsample`, `TonemapPass`, `FXAAPass`.
- A **transient render-target pool** keyed by `{size, format, sampleCount}`: passes request targets, pool recycles across frames. (Skip intra-frame lifetime aliasing.) This removes per-pass texture bookkeeping, the actual ergonomic win.
- **Topological execution** from declared deps; cull passes whose output nobody consumes (skip bloom when disabled, skip shadow pass when no shadow-casting light).
- A tiny typed **blackboard** so passes hand each other handles (depth target, HDR scene color, shadow atlas) without hard-wiring.

This is "Bevy's render graph minus the parts they regret." It makes "add a custom post-process pass" / "add a shadow pass" a small, local change, which is the real goal of going graph-shaped. When/if Flutter GPU exposes subpasses, "merge adjacent passes sharing attachments" is an optimization bolted on later.

## Roadmap

### Phase A: ships today, no engine changes (highest immediate impact)

Target: dramatically better default look + the structural foundation for everything after.

1. **Minimal render-graph refactor.** Replace the hardcoded opaque/translucent encoder split with a pass list + transient target pool + blackboard. Port the existing two passes onto it first (no behavior change), then everything below is "add a pass."
2. **SH-9 diffuse irradiance.** Bake 9 RGB coefficients in `flutter_scene_importer` (replace the irradiance PNG); evaluate the polynomial in `flutter_scene_standard.frag`. Kills the `2.0` hack, frees a sampler. *Do this even before mipmapped cubemaps land.*
3. **Directional light + single shadow map.** A `DirectionalLight` (direction, color, intensity). `ShadowPass` renders scene depth to an offscreen target; standard fragment shader samples it with manual PCF (normal-offset bias since Flutter GPU has no depth bias). This is the biggest perceived-quality gap vs RealityKit.
4. **HDR offscreen pipeline.** Render the scene into an `r16g16b16a16Float` target; a final full-screen `TonemapPass` does tone mapping to the swapchain. Unlocks emissive > 1.0, correct tone mapping, and is the prerequisite for bloom.
5. **Khronos PBR Neutral as the default tone mapper** (keep ACES + others selectable).
6. **Physical exposure model.** Aperture/shutter/ISO → `EV100` → exposure multiply (CPU-side, one uniform). Retires the Car example's magic `exposure=2.0`.
7. **fp16 mobile hardening** in the PBR shader: roughness clamp ≥ 0.089 on mobile, fp16-safe GGX, sqrt-free Smith visibility.
8. **Multiscatter energy compensation** for rough metals.
9. **Runtime PMREM-style prefilter path** (three.js approach, 2D-atlas variant, fragment passes only) for user-supplied `.hdr`, plus a **procedural default studio environment** so zero-config looks good.

### Phase B: as mipmap/cubemap upload lands upstream

10. **Textbook prefiltered-specular IBL.** 256² cubemap, ~9 mips, γ=2 roughness remap. Retire the `mix()` hack and the LOD-clamped-to-4 workaround.
11. **Replace the 2D-atlas PMREM** with a real mipmapped cubemap once cubemap face/mip upload exists.
12. **Trilinear texture filtering** for material textures.
13. **Cubemap reflection probes** (baked, nearest-probe blend; parallax-corrected as a follow-up).

### Phase C: longer horizon

14. **Clustered-forward ("Forward+") for many lights**: CPU-side froxel binning, per-froxel light lists uploaded as a texture (Filament's no-compute scheme).
15. **Post stack on the graph**: bloom (mip-chain), SSAO (needs depth prepass), DoF, color grading LUT.
16. **Point/spot lights** with shadows (cube/perspective shadow maps).
17. **Material-IR layer** if custom-material demand grows (the TSL lesson): a small node/graph that lowers to GLSL, instead of more `#define` permutations.
18. **GPU compute paths** once Flutter GPU exposes compute: GPU IBL prefiltering, GPU skinning/morph, GPU culling, particles.
19. **Morph targets**, **GPU instancing**.

## Flutter GPU asks (push upstream)

Ranked by leverage for flutter_scene:

1. **Mipmap support**: allocate mipmapped textures, upload to a given mip level, ideally `generateMipmaps()`. Unblocks correct prefiltered-specular IBL + trilinear filtering + clean PMREM. **Highest leverage.**
2. **Cubemap face/mip upload**: fill faces of a `textureCube`, per-face and per-mip. Pairs with #1 for textbook IBL.
3. **Compute shaders + storage buffers**: biggest single capability expansion (GPU prefiltering, skinning/morph, culling, particles). Large effort; the ceiling-raiser for "high-fidelity mobile games."
4. **Depth-compare samplers** (hardware PCF): cheaper, nicer soft shadows.
5. **Depth bias / slope-scale bias** in pipeline state: proper shadow-acne control.
6. **Subpass / input-attachment exposure**: lets the render graph do tile-memory pass merging.
7. **Buffer/texture readback**: screenshots, GPU-to-CPU validation, occlusion-driven LOD.
8. **Anisotropic filtering**: grazing-angle texture quality.

## Open questions

- Default environment: keep `royal_esplanade` (outdoor courtyard: great for showpieces, busy for product shots) or switch the default to a neutral studio? Possibly ship both and make studio the default for "no env supplied."
- Shadow-map strategy: single shadow map first; cascades (CSM) are a Phase C add-on. Atlas layout for future point/spot shadows?
- Do we keep the baked BRDF LUT PNG, or move to the analytic Karis '14 DFG and drop the asset + sampler? (Analytic loses multiscatter compensation unless we keep a small LUT for the directional-albedo term.)
- Render-graph API surface: how much do we expose to users for custom passes vs keep internal initially?

## Key sources

- Filament PBR/IBL/camera/tonemapping: https://google.github.io/filament/Filament.html · Materials: https://google.github.io/filament/Materials.html · cmgen: https://google.github.io/filament/cmgen.html
- three.js PMREM: https://threejs.org/docs/pages/PMREMGenerator.html · RoomEnvironment: https://threejs.org/docs/pages/RoomEnvironment.html · TSL: https://threejs.org/docs/TSL.html
- Khronos PBR Neutral: https://www.khronos.org/news/press/khronos-pbr-neutral-tone-mapper-released-for-true-to-life-color-rendering-of-3d-products
- Frostbite FrameGraph (GDC 2017): https://www.gdcvault.com/play/1024612/FrameGraph-Extensible-Rendering-Architecture-in
- Render graphs & Vulkan (Granite): https://themaister.net/blog/2017/08/15/render-graphs-and-vulkan-a-deep-dive/
- Bevy render graph slots retrospective: https://github.com/bevyengine/bevy/discussions/8644
- Godot renderers: https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html
- MSAA nearly free on TBDR: https://medium.com/androiddevelopers/multisampled-anti-aliasing-for-almost-free-on-tile-based-rendering-hardware-21794c479cb9
- IBL writeup (mirrors Filament w/ code): https://bruop.github.io/ibl/
