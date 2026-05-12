# A9 implementation plan: runtime PMREM prefilter + procedural default environment

This is the "warm up a fresh session" doc for Phase A item 9 (see
`renderer-roadmap.md`). It assumes A1–A8 are landed on the
`bdero/renderer` branch. Read this top to bottom before touching code.

## What A9 is

Two related deliverables:

1. **Runtime prefiltered specular IBL** — when an `EnvironmentMap` is
   built from a (equirectangular) radiance image, compute a *prefiltered*
   version on the GPU at load time (using only fragment-shader passes —
   Flutter GPU has no compute, no mipmap upload, no cubemap face upload),
   and have the standard fragment shader sample that instead of the raw
   radiance with the current `roughness * 4.0` LOD hack. This lets the
   `kEnvironmentMultiplier = 2.0` fudge and the
   `mix(irradiance, prefiltered, pow(1.02 - roughness, 12))` fudge in
   `flutter_scene_standard.frag` go away.
2. **A procedural default "studio" environment** so a zero-config
   `Scene()` looks good without shipping (or downloading) an HDR. The
   bundled `royal_esplanade` becomes a named option rather than the
   silent default (open question — see below).

A9 only touches the **specular** side. Diffuse irradiance is already
SH-9 (A2) and is computed from the radiance image at load time; A9 adds
the matching specular prefiltering alongside it.

## Where the renderer is now (post-A1–A8)

- **Render graph** (`lib/src/render/`): `RenderGraph` (a list of
  `RenderGraphPass`es run in order), `RenderGraphContext`
  (`transientsBuffer`, `texturePool`, `blackboard` — *no* command
  buffer; each pass creates and submits its own), `Blackboard` (typed
  per-frame key/value), `TransientTexturePool` (textures keyed by
  `TransientTextureDescriptor`, recycled across frames). Passes:
  `ShadowPass` (optional, first), `ScenePass`, `TonemapPass` (last).
- **`SceneEncoder`** records the scene-graph draws (opaque then
  depth-sorted translucent) into a `gpu.RenderPass`. `ShadowEncoder`
  does the depth-only shadow walk. Both implement `SceneDrawList`
  (`frustum`, `cullScratchAabb`, `encode(...)`); `Node.render` /
  `Mesh.render` take a `SceneDrawList`.
- **`ScenePass`** renders into an `r16g16b16a16Float` HDR color target
  (MSAA resolved in linear), publishes the resolved HDR color on the
  blackboard. **`TonemapPass`** reads it, un-premultiplies, applies
  exposure + tone-mapping operator (`ToneMappingMode`, default
  `pbrNeutral`) + the display EOTF (`#ifndef IMPELLER_TARGET_METAL`
  gamma), re-premultiplies, writes the 8-bit swapchain. Material shaders
  output **linear HDR premultiplied by alpha** — no tone mapping in them
  anymore. (`frag_info.exposure` / `frag_info.tone_mapping_mode` in the
  standard shader are now unused.)
- **`Surface`** owns the swapchain color ring (`getNextSwapchainColorTexture`,
  plain 8-bit non-MSAA) + the `transientTexturePool`.
- **IBL today** (`lib/src/material/environment.dart`,
  `physically_based_material.dart`, `flutter_scene_standard.frag`,
  `texture.glsl`, `pbr.glsl`):
  - `EnvironmentMap` holds `radianceTexture` (equirect, sRGB-encoded
    PNG), and **either** `irradianceTexture` (equirect) **or**
    `diffuseSphericalHarmonics` (`List<Vector3>`, 9 RGB coeffs with the
    cosine convolution + 1/pi folded in). `fromAssets` / `fromUIImages`:
    if an irradiance image is given → texture path; else compute SH from
    the radiance image (`EnvironmentMap.computeDiffuseSphericalHarmonics`).
    `fromGpuTextures` takes already-uploaded textures (+ optional precomputed SH).
  - The bundled default: `Material.initializeStaticResources()` loads
    `packages/flutter_scene/assets/royal_esplanade.png` (radiance),
    `royal_esplanade_irradiance.png` (irradiance), `ibl_brdf_lut.png`.
    `getDefaultEnvironmentMap()` returns `fromGpuTextures(radiance,
    irradiance)` — so the default uses the **irradiance-texture path**,
    not SH, and not prefiltered radiance.
  - `flutter_scene_standard.frag` IBL section (`main()`): diffuse =
    `EvaluateDiffuseSH(normal)` if `use_diffuse_sh > 0.5` (× `environment_intensity`,
    no fudge) else `SRGBToLinear(SampleEnvironmentTexture(irradiance_texture, n))
    * environment_intensity * kEnvironmentMultiplier` (kEnvironmentMultiplier
    = 2.0). Specular `prefiltered_color = SRGBToLinear(SampleEnvironmentTextureLod(
    radiance_texture, reflect_dir, roughness * 4.0).rgb) * environment_intensity
    * kEnvironmentMultiplier`, then `mix(irradiance, prefiltered_color,
    pow(1.02 - roughness, 12.0))` (the rough-surface fudge). Then the
    Fdez-Aguera multiscatter combine (A8) using the `brdf_lut`.
  - `texture.glsl`: `SphericalToEquirectangular(dir)` =
    `vec2(atan(dir.z, dir.x), asin(dir.y)) * vec2(0.1591, 0.3183) + 0.5`
    (= `1/(2pi)`, `1/pi`). `SampleEnvironmentTexture` / `...Lod` use it
    (the `Lod` one currently ignores the LOD — there are no mips).
  - `pbr.glsl`: `kGamma = 2.2`, `SRGBToLinear`, `kMinRoughness = 0.045`,
    fp16-safe `DistributionGGX`, `VisibilitySmithGGXCorrelated` (sqrt-free),
    `FresnelSchlick*`. `kPi`.
- **`FragInfo`** (the standard shader's UBO) is **84 floats / 336 bytes**.
  Layout is documented in `physically_based_material.dart` `bind()`:
  `[0..3]` color, `[4..7]` emissive_factor, `[8..43]` 9× `diffuse_sh` vec4,
  `[44..47]` directional_light_direction, `[48..51]` directional_light_color,
  `[52..67]` light_space_matrix (mat4), `[68]` vertex_color_weight,
  `[69]` exposure, `[70]` metallic_factor, `[71]` roughness_factor,
  `[72]` has_normal_map, `[73]` normal_scale, `[74]` occlusion_strength,
  `[75]` environment_intensity, `[76]` tone_mapping_mode, `[77]` use_diffuse_sh,
  `[78]` has_directional_light, `[79]` casts_shadow, `[80]` shadow_bias,
  `[81]` shadow_normal_bias, `[82]` shadow_texel_size, `[83]` pad.
  Adding fields means re-shuffling this + updating the comment + the
  shader's `uniform FragInfo {...}` order. (`exposure` / `tone_mapping_mode`
  are dead now and could be reclaimed — or just left.)
- **Shader bundle**: `shaders/base.shaderbundle.json` lists
  `UnskinnedVertex`, `SkinnedVertex`, `UnlitFragment`, `StandardFragment`,
  `DepthOnlyFragment`, `FullscreenVertex` (a 6-vertex NDC quad VS),
  `TonemapFragment`. `TonemapPass` shows the pattern for a full-screen
  pass: static `gpu.DeviceBuffer` of 6 `vec2`s via `createDeviceBufferWithCopy`,
  `gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 48)`,
  `bindVertexBuffer(view, 6)`, `draw()`. The fullscreen VS derives UV from
  position with a **V-flip** (`v_uv = vec2(p.x*0.5+0.5, 0.5 - p.y*0.5)`)
  because it samples render-to-texture targets.

## Hard constraints / gotchas (carry-overs — do not relearn the hard way)

1. **No compute shaders, no mipmap upload/gen, no cubemap face upload.**
   `r16g16b16a16Float` color render targets work (HDR pass, shadow map use them).
   MSAA 1× or 4× only. `TextureType.textureCube` *exists* but you can't
   fill faces — so prefiltering must produce a **2D texture** (atlas), not
   a real mipmapped cubemap. (Phase B / item 11: replace the atlas with a
   real mipmapped cube once upstream adds cube face/mip upload.)
2. **One render pass per command buffer.** Flutter GPU's `gpu.RenderPass`
   holds a live Metal command encoder, so a `gpu.CommandBuffer` hosts at
   most one render pass. Each render-graph pass creates+submits its own
   `gpu.gpuContext.createCommandBuffer()`. For the prefilter (multiple
   passes — one per roughness band — and maybe two per band for separable
   blur) you need a command buffer per render pass. Submitting many small
   command buffers in order is fine; Impeller handles cross-cb hazards.
3. **Sampling a render-to-texture texture needs a V-flip.** The shadow map
   and the tonemap input both needed `uv.y = 1.0 - uv.y` (or baked-in flip
   in the quad). The prefilter atlas will too.
4. **A second fragment-stage UBO failed to bind under Impeller** (the
   `ShInfo` block attempted in A2 — `bindUniform` threw "Failed to bind
   uniform"). The SH coeffs were folded into `FragInfo` as individual
   `vec4` members instead. **It may have been the `vec4 sh[9]` array** in a
   UBO that was the real culprit (never isolated). For A9: prefer adding to
   `FragInfo`, or — better — bake fixed prefilter metadata (band count,
   atlas dims) as **compile-time `const` in the shader** since the
   prefilter setup is fixed. Avoid new fragment UBOs and UBO arrays unless
   you test them in isolation first.
5. **The build-hook caching trap.** `flutter_gpu_shaders`' build hook may
   not pick up new entries added to `shaders/base.shaderbundle.json` until
   a `flutter clean` invalidates the cache (this bit A4 — `FullscreenVertex`
   / `TonemapFragment` weren't in the rebuilt bundle until a clean). **But**
   `flutter clean` in `examples/flutter_app/` nukes the gitignored,
   hook-generated `build/models/` *and* `build/shaderbundles/example.shaderbundle`,
   which then **don't regenerate** on subsequent `flutter build macos`
   (root cause unknown — the `flutter_scene` hook *does* re-run; the
   example app's own hook apparently doesn't). Recovery:
   - `cd examples/flutter_app && for f in two_triangles flutter_logo_baked dash fcar; do dart run flutter_scene_importer:import -i "../assets_src/$f.glb" -o "build/models/$f.model"; done`
   - `mkdir -p build/shaderbundles && /Users/bdero/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc --sl=build/shaderbundles/example.shaderbundle --shader-bundle='{"ToonFragment":{"type":"fragment","file":"shaders/example_toon.frag"}}' --include=shaders --include=/Users/bdero/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/shader_lib`
   - The `flutter_scene` `base.shaderbundle` *does* rebuild after a clean —
     check it has the new shaders: `strings packages/flutter_scene/build/shaderbundles/base.shaderbundle | grep -c '^YourNewShaderName$'`.
   So: if a new shader doesn't show up in the bundle, `flutter clean`, then
   restore the example's `build/` as above, then rebuild.
6. **sRGB / linear.** Env PNGs are sRGB-encoded. The prefilter shader must
   `SRGBToLinear` the source samples and accumulate/store in **linear** in
   the fp16 atlas. The standard shader then samples the atlas **without**
   re-linearizing (it's already linear). Don't double-linearize. (The
   diffuse SH path already linearizes on the CPU during projection.)
7. **The `kEnvironmentMultiplier = 2.0` fudge** exists because the
   no-prefiltering specular path was wrong. When proper prefiltering lands,
   delete the fudge. The SH diffuse path already has none — so once
   specular is proper, both are consistent. If the result looks dim, retune
   the default `Environment.exposure` (currently 2.0) / light intensities,
   don't reintroduce a fudge.

## Toolchain (for testing)

- `bdero/flutter` fork (master-ish). `dart analyze packages examples`
  (run from the worktree root). `flutter test --enable-impeller` in
  `packages/flutter_scene` (70 tests). `flutter build macos --debug` in
  `examples/flutter_app` (compiles GLSL). `flutter run -d macos --debug
  --enable-impeller --enable-flutter-gpu` to actually run it (needs both
  flags — macOS desktop is Skia by default, and Flutter GPU needs the
  manifest flag too). The user pastes screenshots; ask for them.
- `impellerc`: `/Users/bdero/projects/flutter/flutter/bin/cache/artifacts/engine/darwin-x64/impellerc`,
  `shader_lib` next to it. `flutter_gpu_shaders`' invocation is
  `impellerc --sl=<out.shaderbundle> --shader-bundle='<manifest json,
  file paths relative to package root>' --include=<manifest dir>
  --include=<shader_lib>`, run with `workingDirectory: <package root>`.
- The worktree's `examples/flutter_app/macos/` was copied from the main
  checkout (gitignored; `flutter create --platforms=macos` crashes on this
  fork — can't find `packages/flutter_gpu/pubspec.yaml`).

## Proposed design

Keep v1 as simple as possible; note the upgrades for later.

### Part 1 — the prefiltered radiance representation: an equirect mip atlas

A single `r16g16b16a16Float` 2D texture holding **N roughness bands**
stacked vertically, each band an equirectangular prefiltered radiance map.
Band `i` corresponds to `perceptualRoughness = i / (N - 1)`.

- v1: **N = 8 bands**, each `256 × 128` (so the atlas is `256 × 1024`).
  Band 0 (roughness ≈ 0, mirror) at 256×128 is a bit low-res for sharp
  reflections — acceptable for v1. *Upgrade:* a separate full-res band 0,
  or 512×256 base decreasing to 64×32 for the rough bands (the three.js
  approach), or cube-faces-in-atlas to kill the pole singularity.
- Sampling in the shader: `band = perceptualRoughness * (N - 1)`,
  `i0 = floor(band)`, `i1 = i0 + 1`, `t = fract(band)`; sample band `i0`
  and `i1` at the equirect UV (scaled+offset into each band's vertical
  region — `uv.y` ∈ `[i/N, (i+1)/N]`), `mix` by `t`. Plus the V-flip.
  Band count `N` and atlas layout can be **compile-time `const`s** in the
  shader (the prefilter setup is fixed) — avoids touching `FragInfo` /
  adding a UBO.

### Part 2 — the prefilter routine (one-time, GPU, fragment passes)

Not a per-frame render-graph pass — prefiltering happens **once** when an
`EnvironmentMap` is constructed from a radiance image, and the result is
cached on the `EnvironmentMap`. A standalone routine,
`lib/src/render/env_prefilter.dart`:

```
gpu.Texture prefilterEquirectRadiance(gpu.Texture sourceEquirect, {bands, bandWidth, bandHeight}) {
  // allocate the atlas (r16g16b16a16Float, renderToTexture, shader-readable)
  // for each band i:
  //   roughness_i = i / (bands - 1)
  //   command buffer -> render pass with a viewport/scissor over band i's
  //     region of the atlas (or render the whole atlas-height each pass and
  //     let the shader pick its band from a uniform — simpler to do
  //     viewport per band) -> draw the fullscreen quad with the prefilter
  //     fragment shader (uniform: roughness_i, source, atlas layout) ->
  //     submit
  // return the atlas texture
}
```

The prefilter fragment shader (`shaders/flutter_scene_prefilter_env.frag`):
given the band's `v_uv` → an equirect UV → a direction `n` (treat `n` as
both the normal and the view direction — the standard "v = n" assumption);
prefilter radiance around `n` for `roughness_i`.

- **v1: separable Gaussian-on-sphere blur** (three.js `_blur()` style),
  not GGX importance sampling. Without source mips, GGX importance
  sampling needs hundreds of taps to converge; a separable Gaussian with
  ~16–20 taps each direction (latitude pass then longitude pass) is far
  cheaper and looks fine for IBL specular. So actually **two passes per
  band**: a latitudinal blur into a temp band, then a longitudinal blur
  into the atlas band. Sigma per band tuned roughly to the GGX lobe width
  for `roughness_i` (three.js's `EXTRA_LOD_SIGMA` table is a starting
  point; ours are coarser since we have fewer/uniform bands). Band 0
  (roughness ≈ 0) = a straight copy (no blur). *Upgrade:* GGX VNDF
  importance sampling once we can build source mips (Phase B).
- The shader reads the source as sRGB → `SRGBToLinear` → accumulates →
  writes linear to the fp16 atlas.

Wire it into `EnvironmentMap`:
- `fromUIImages` / `fromAssets`: when given a radiance image and no
  irradiance image, after `gpuTextureFromImage(radianceImage)` and
  `computeDiffuseSphericalHarmonics(radianceImage)`, also call
  `prefilterEquirectRadiance(radianceTexture)` and store the result.
- `fromGpuTextures`: optional `prefilteredRadianceTexture` param.
- `EnvironmentMap` gains `gpu.Texture? get prefilteredRadianceTexture`
  and the standard shader uses it (with a `has_prefiltered_radiance`
  flag in `FragInfo`, or just always bind it — if absent, bind the raw
  `radianceTexture` and a flag tells the shader which sampling path).
  Hmm — cleanest: always have a `prefiltered_radiance` sampler; when
  there's no real one, bind the raw `radianceTexture` (the shader will
  still sample it; the result is "unprefiltered" but not broken) — or
  bind the white placeholder and a flag forces a fallback. Decide during
  implementation; a `use_prefiltered_radiance` float in `FragInfo` is the
  flexible option (FragInfo has a spare slot at `[83]`... actually `[83]`
  is the pad-to-16; using it makes the block 84 used floats which is fine
  since 84 floats = 336 bytes = a multiple of 16).

### Part 3 — the standard shader changes

In `flutter_scene_standard.frag` (and maybe `texture.glsl`):
- Add `uniform sampler2D prefiltered_radiance;` (a 10th sampler — the
  shadow map made it 9; 10 should still be under any Metal/Vulkan/Impeller
  limit, but if `bindUniform` complains, that's the signal — see gotcha 4).
- Replace
  ```glsl
  vec3 prefiltered_color = SRGBToLinear(SampleEnvironmentTextureLod(radiance_texture, reflection_normal, roughness * 4.0).rgb) * environment_intensity * kEnvironmentMultiplier;
  prefiltered_color = mix(irradiance, prefiltered_color, pow(1.02 - roughness, 12.0));
  ```
  with a `SamplePrefilteredRadiance(reflection_normal, roughness)` that
  reads the atlas (band lerp + V-flip + equirect UV), already linear, ×
  `environment_intensity` (no `kEnvironmentMultiplier`). Keep the Fdez-
  Aguera multiscatter combine below it unchanged.
- Delete `kEnvironmentMultiplier` from the **specular** path. For the
  **diffuse** path: SH (the common case now) already has no fudge; the
  irradiance-texture fallback still has the `2.0` — leave that fallback
  alone for now, or delete it too if you also remove the
  irradiance-texture path entirely (see Part 4).

### Part 4 — the procedural default studio environment

Goal: `Scene()` with nothing configured looks good.

- v1: a **procedurally-generated equirect** `flutter_scene_procedural_env.frag`
  — not a rendered room scene (that's the three.js `RoomEnvironment`
  approach; more work). A studio-ish gradient: cool soft light from above,
  neutral mid, warm bounce from below, a couple of bright "softbox" lobes.
  Render it once into an `r16g16b16a16Float` equirect texture (a single
  fullscreen pass), then run the same SH + prefilter on it. Expose it as
  e.g. `EnvironmentMap.studio()` (or `EnvironmentMap.defaultStudio()`).
  *Upgrade:* render an actual tiny box-room scene (walls/floor/ceiling +
  emissive panels) — but rendering a scene to a cube needs per-face render
  targets, which Flutter GPU's cube support may not allow yet; rendering
  it 6× into a 2D atlas is the workaround. Defer.
- Make it the **zero-config default**: in `Material.initializeStaticResources()`,
  build the procedural studio (+ its SH + prefilter atlas) instead of
  loading `royal_esplanade.png` + `royal_esplanade_irradiance.png`.
  `getDefaultEnvironmentMap()` returns it. Keep `royal_esplanade.png` as a
  bundled asset reachable via `EnvironmentMap.fromAssets('packages/flutter_scene/assets/royal_esplanade.png')`
  (which now also prefilters it + SH). **Open question** — see below; the
  conservative alternative is "keep `royal_esplanade` via the texture path
  as the default, just add the prefilter path for user envs" (less
  visible change, but the IBL hacks stay for the default).
- If we switch the default to the SH+prefilter path, the
  `royal_esplanade_irradiance.png` asset can be dropped, and the
  irradiance-texture fallback path in the shader can eventually be removed
  (it'd only matter for someone calling `fromGpuTextures` with an
  irradiance texture they uploaded themselves — keep it for now).

### Part 5 (optional / future) — offline baking

Filament/three.js production path is offline (`cmgen`). flutter_scene has
an offline importer (`flutter_scene_importer`) and bakes
`royal_esplanade_irradiance.png` + `ibl_brdf_lut.png` as assets already. A
follow-up could add a `flutter_scene_importer` CLI / build-hook step that
bakes a `.hdr` → prefiltered atlas (+ SH coeffs as a tiny asset) at build
time. Not v1.

## File list for A9 (v1)

New:
- `shaders/flutter_scene_prefilter_env.frag` — separable spherical
  Gaussian blur of an equirect, per roughness band (mode/uniform: which
  axis, sigma, source band region).
- `shaders/flutter_scene_procedural_env.frag` — generates the default
  studio equirect.
- `lib/src/render/env_prefilter.dart` — `prefilterEquirectRadiance(...)`
  (one-time GPU prefilter) and `generateProceduralStudioEquirect(...)`.

Modified:
- `shaders/base.shaderbundle.json` — add `PrefilterEnvFragment`,
  `ProceduralEnvFragment` (and reuse `FullscreenVertex`). **Remember the
  build-hook caching trap — may need a `flutter clean` + the example
  `build/` recovery dance.**
- `shaders/flutter_scene_standard.frag` — add `prefiltered_radiance`
  sampler + `use_prefiltered_radiance` flag in `FragInfo` (`[83]` slot),
  swap the specular sampling, delete `kEnvironmentMultiplier` from the
  specular path. Update the `FragInfo` layout comment.
- `shaders/texture.glsl` — maybe add `SamplePrefilteredRadiance(dir,
  roughness)` (equirect UV + band lerp + V-flip) here.
- `lib/src/material/environment.dart` — `EnvironmentMap` gains
  `prefilteredRadianceTexture`; `fromUIImages`/`fromAssets` prefilter
  radiance-only envs; add `EnvironmentMap.studio()`/`defaultStudio()`;
  `fromGpuTextures` takes an optional precomputed prefiltered texture.
- `lib/src/material/physically_based_material.dart` — bind
  `prefiltered_radiance`; set `use_prefiltered_radiance`; update the
  `FragInfo` packing + layout comment.
- `lib/src/material/material.dart` — `initializeStaticResources()`: build
  the procedural studio (or keep `royal_esplanade` + add prefiltering —
  decide per the open question); maybe drop `royal_esplanade_irradiance.png`.
- `lib/scene.dart` — export new `EnvironmentMap` constructors if any.
- `docs/renderer-roadmap.md` — mark item 9 done.

## Open questions to decide before/while implementing

1. **Default env:** switch the zero-config default to the procedural
   studio (recommended — lets the IBL hacks go away and is "looks great
   by default")? Or keep `royal_esplanade`-via-texture-path and only add
   prefiltering for user envs (conservative)? Or use a *prefiltered*
   `royal_esplanade` as the default (compromise — keeps the familiar look,
   drops the hacks)?
2. **Prefilter algorithm:** separable Gaussian-on-sphere (recommended for
   v1 — cheap, no source mips needed) vs GGX importance sampling (more
   correct, needs source mips → Phase B)?
3. **Atlas layout:** equirect-per-band (recommended for v1 — simple,
   matches current sampling) vs cube-faces-in-atlas (kills pole
   singularity, more complex)?
4. **Band count / per-band resolution:** 8 bands × 256×128 uniform
   (recommended for v1) vs a real mip-style chain (512×256 → 64×32) vs
   three.js's "LOD chain + 6 extra clamped levels"?
5. **Prefilter metadata in the shader:** compile-time `const`s
   (recommended — fixed setup, avoids `FragInfo`/UBO churn) vs uniforms?
6. **Where to do the prefilter:** eagerly in `EnvironmentMap.fromUIImages`
   at construction (recommended — runs once, cached) — confirm there's no
   issue doing GPU work (`createCommandBuffer`, render passes) at that
   point (the GPU context is up by the time you construct an
   `EnvironmentMap` in app code, but double-check it's not called from a
   place where `gpu.gpuContext` isn't ready).
7. **Procedural studio v1:** pure procedural-gradient equirect
   (recommended) vs render a tiny box-room scene (the three.js
   `RoomEnvironment` approach — more work, and "render to a cube" may need
   per-face targets Flutter GPU doesn't expose)?

## Testing plan for A9

1. `dart analyze packages examples` → clean.
2. `flutter test --enable-impeller` in `packages/flutter_scene` → 70 pass.
3. `flutter build macos --debug` in `examples/flutter_app` → compiles the
   GLSL. If new shaders aren't in `base.shaderbundle` (`strings ... | grep`),
   `flutter clean` + restore the example `build/` (see gotcha 5) + rebuild.
4. `flutter run -d macos --debug --enable-impeller --enable-flutter-gpu`,
   ask the user for screenshots. Look for: the Car's chrome/wheels/glass
   reflections (should be smooth roughness falloff, not the blocky
   `roughness*4.0`-LOD-hack look), overall environment lighting brightness
   (should look right with `kEnvironmentMultiplier` gone — if dim, retune
   `Environment.exposure` / light intensity, don't fudge), and — if the
   default is switched — the procedural studio (a clean neutral studio
   look on the Logo / Cuboid / Animation scenes). Probably wire one example
   to a user `EnvironmentMap.fromAssets(...royal_esplanade.png...)` (no
   irradiance image) so the prefilter path is exercised even if the
   default isn't switched.
5. Mind the translucency / premultiplied-alpha behavior is unchanged (the
   Car's windows should still show the red interior correctly).

## Smaller follow-ups noted elsewhere (not A9, but adjacent)

- Update `MATERIALS.md`: `ShaderMaterial` shaders must no longer
  tone-map / gamma-encode — the engine does it now (A4). Document that
  custom shaders output linear HDR premultiplied by alpha into the scene
  color target. The Toon example's shader currently still works but its
  output is now tone-mapped on top (slightly compressed highlights).
- The `flutter clean` → example-build-broken mystery (gotcha 5) — worth a
  proper fix at some point.
- Shadow bias/intensity defaults (`DirectionalLight.shadowDepthBias` =
  0.0015, `shadowNormalBias` = 0.02, the logo example's `intensity` = 3.0)
  were tuned by eye on one scene — may want revisiting on real content.
- Consider exposing the render-graph passes / `RenderGraphPass` publicly
  for user custom passes (currently `lib/src/render/` is unexported).
