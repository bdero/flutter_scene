---
name: flutter_scene-looks
version: 4
description: Give a flutter_scene render a deliberate, polished look. Use this whenever a scene looks flat, dull, or washed out, or whenever the ask is to make it look good, because a good look is lighting plus post-processing, not geometry. Ships copy-paste EnvironmentSettings presets that configure the whole stack coherently.
---

# Making flutter_scene look good

The single most common reason a flutter_scene render looks amateur is that the post-processing stack was left at defaults. flutter_scene has a deep lit-and-post pipeline (image-based lighting, tone mapping, bloom, lens flares, ambient occlusion, screen-space reflections, fog, god rays, depth of field, color grading, vignette, film grain). Out of the box almost all of it is off, so a bare scene is technically correct and visually flat.

**The insight: a polished look is lighting and post-processing, not geometry.** Better meshes will not fix a flat render. Do not spend effort on modeling detail when the scene reads dull; spend it on the look. And a look is a *coherent* set of choices, not twelve knobs turned independently. Turning bloom, AO, SSR, fog, grain, and grading up one at a time, each by feel, lands in muddy incoherent territory. Pick one deliberate preset and paste it whole.

## Apply a look in one line

Every scene-wide look field lives on one aggregate value, `EnvironmentSettings`, assigned through a single setter:

```dart
scene.environmentSettings = EnvironmentSettings(/* fields below */);
```

That one assignment configures tone mapping, exposure, image-based-lighting intensity, and the entire post stack, **including** fog, god rays, depth of field, and auto exposure. You do not need to touch `scene.fog`, `scene.godRays`, `scene.depthOfField`, or `scene.autoExposure` separately; those are the live per-effect objects, but `EnvironmentSettings` carries all of their fields and applies them for you. Every effect is off by default, so a preset only names the fields it turns on.

`EnvironmentSettings` is also a blendable snapshot. Read the current look with `scene.environmentSettings`, and cross-fade two looks with `EnvironmentSettings.lerp(a, b, t)` driven from an animation. That is how you transition day to night or ramp an effect in.

## Lights are separate, and still matter

`EnvironmentSettings` covers image-based lighting (the `environment` map) and the whole post stack, but **direct lights are not part of it.** Shadows, god rays, and any strong key light come from the scene's lights, set separately:

```dart
scene.directionalLight = DirectionalLight(
  direction: vm.Vector3(-0.4, -1.0, -0.3),
  intensity: 4.0,
  castsShadow: true,        // shadows are off until you ask
);
```

An unset `scene.environment` still resolves to a default studio IBL, so a `PhysicallyBasedMaterial` is always lit. But a scene with no direct light is soft and shadowless. God rays require a shadow-casting `DirectionalLight`; shadows require `castsShadow: true` on the light.

## The four looks

Paste one whole. Each is a real `EnvironmentSettings` literal; import `package:vector_math/vector_math.dart as vm` for the `Vector3` color fields. AO, SSR, god rays, and depth of field require a `PerspectiveCamera` (the only built-in camera).

### showcase

Clean, bright product-viz beauty. Punchy tone mapping, soft bloom on highlights, grounded contact occlusion, and real reflections. The default reach-for-it look.

```dart
scene.environmentSettings = EnvironmentSettings(
  toneMapping: ToneMappingMode.aces,
  exposure: 1.0,
  bloomEnabled: true,
  bloomThreshold: 1.1,
  bloomIntensity: 0.2,
  bloomScatter: 0.7,
  ambientOcclusionEnabled: true,
  ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
  ambientOcclusionBentNormals: true,
  ambientOcclusionSpecularMode: SpecularAmbientOcclusionMode.bentCone,
  ambientOcclusionIntensity: 1.0,
  screenSpaceReflectionsEnabled: true,
  screenSpaceReflectionsIntensity: 1.0,
  vignetteEnabled: true,
  vignetteIntensity: 0.25,
);
```

### stylized

Vivid and graphic. Saturated, slightly warm, glowing, flatter shading (no heavy occlusion or reflections). For playful or illustrative scenes.

```dart
scene.environmentSettings = EnvironmentSettings(
  toneMapping: ToneMappingMode.aces,
  colorGradingEnabled: true,
  saturation: 1.25,
  contrast: 1.1,
  brightness: 1.05,
  temperature: 0.1,
  bloomEnabled: true,
  bloomThreshold: 0.9,
  bloomIntensity: 0.28,
  bloomScatter: 0.8,
  vignetteEnabled: true,
  vignetteIntensity: 0.2,
);
```

### moody

Dark, cinematic, atmospheric. Lower exposure, cool graded, foggy, heavy vignette, subtle grain and aberration, deep occlusion. God rays if the scene has a shadow-casting sun. Use a cool horizon-colored fog.

```dart
scene.environmentSettings = EnvironmentSettings(
  toneMapping: ToneMappingMode.aces,
  exposure: 0.8,
  colorGradingEnabled: true,
  contrast: 1.15,
  saturation: 0.9,
  temperature: -0.1,
  fogEnabled: true,
  fogMode: FogMode.exponential,
  fogColor: vm.Vector3(0.05, 0.06, 0.09),
  fogDensity: 0.03,
  ambientOcclusionEnabled: true,
  ambientOcclusionMethod: AmbientOcclusionMethod.groundTruth,
  ambientOcclusionIntensity: 1.2,
  ambientOcclusionPower: 1.8,
  vignetteEnabled: true,
  vignetteIntensity: 0.6,
  vignetteRadius: 0.6,
  filmGrainEnabled: true,
  filmGrainIntensity: 0.25,
  chromaticAberrationEnabled: true,
  chromaticAberrationIntensity: 0.15,
  godRaysEnabled: true,          // needs scene.directionalLight with castsShadow: true
  godRaysIntensity: 1.0,
  godRaysDensity: 0.6,
  godRaysColor: vm.Vector3(1.0, 0.95, 0.85),
);
```

### clean

Neutral and honest. Minimal post, no grading, no bloom, no vignette, just correct tone mapping and gentle grounding occlusion. The right look for an editor, an inspector, a UI-embedded viewer, or anywhere you want an accurate read of the actual material.

```dart
scene.environmentSettings = EnvironmentSettings(
  toneMapping: ToneMappingMode.pbrNeutral,   // the engine default
  exposure: 1.0,
  ambientOcclusionEnabled: true,
  ambientOcclusionIntensity: 0.8,
  ambientOcclusionHalfResolution: true,
);
```

## Tuning from a preset

Start from the nearest look, then move one field at a time.

- **Too dim or too bright overall.** Change `exposure` (default 1.0), not per-light intensity. Or turn on `autoExposureEnabled: true` to let the scene meter itself.
- **Highlights not glowing.** Lower `bloomThreshold` toward 1.0 or below, or raise `bloomIntensity`. `bloomScatter` widens the glow.
- **Want a lens flare off a bright source.** Turn on `lensFlareEnabled` (needs `bloomEnabled`). Keep `lensFlareIntensity` modest and drop `lensFlareHaloIntensity` first if the flare washes the frame; the halo is the broad wash, the ghosts are the crisp chain.
- **Reads flat and ungrounded.** `ambientOcclusionEnabled: true`. Use `AmbientOcclusionMethod.groundTruth` for quality, keep `ambientOcclusionHalfResolution: true` for cost.
- **Colors feel wrong.** Turn on `colorGradingEnabled` and reach for `saturation`, `contrast`, `temperature`, `tint` before anything else.
- **Wrong tone-map feel.** `ToneMappingMode.aces` is contrasty and filmic, `pbrNeutral` (default) preserves hue and saturation, `agx` is the most neutral highlight rolloff. Do not reintroduce an `exposure: 2.0` hack; that was an artifact of an older renderer.

## Micro-surface metrics and anti-waxiness tuning

When tuning procedural materials or custom shaders, use surface metrics and exposure discipline to eliminate waxiness, plastic reads, or harsh aliasing:

- **Surface reads like smooth plastic.** Increase high-frequency micro-scale variation. Low 1-pixel luminance gradients `(|dL/dx| + |dL/dy|) / 2` indicate untextured or overly smooth surfaces.
- **Blotchy macro clouds.** Balance high-frequency and low-frequency energy ratios (`hf/lf`). High variance with low fine detail indicates large-scale noise patches without adequate surface grain.
- **Harsh normal-map glitter or torn noise.** Check terminator crossing behavior under low grazing light angles (sun low on the horizon). Over-amplified normal maps flip adjacent pixels between full light and full shadow.
- **Colors look washed out in bright areas.** Tone mapping curves compress channel differences near the shoulder. A surface reading high brightness with low saturation is often over-exposed rather than under-pigmented; reduce exposure to restore natural material saturation.

## Look tools that are not on EnvironmentSettings

Anti-aliasing, reflection probes, and planar reflectors affect the look but are set outside `EnvironmentSettings`, so a preset does not turn them on.

- **Anti-aliasing** is a `Scene` field. The default `AntiAliasingMode.auto` already picks `msaa` where the backend supports it and `fxaa` otherwise, so edges are handled. Reach for `scene.antiAliasingMode = AntiAliasingMode.smaa` when `fxaa` looks mushy (it blurs texture detail) and `msaa` is unavailable; SMAA keeps edges clean without the blur, at ~3x fxaa cost.
- **Reflection probes** capture true local reflections that SSR cannot, because SSR only reflects what is on screen. Attach a `ReflectionProbeComponent` to a node placed at the reflective spot (a room, a mirror ball); it captures the surroundings into a parallax-corrected box and blends with the environment. The capture renders the scene six times, so it happens once on activate (or on an explicit `requestCapture()`), never per frame.
- **Planar reflectors** render a true per-frame mirror for one flat surface (a mirror, a glossy floor), which neither SSR nor a probe can produce. Attach a `PlanarReflectorComponent` to the mirror node and give the surface a `.fmat` material declaring `engine_inputs: [ planar_reflection ]`; the component renders the scene once more per frame from the reflected camera and the material samples it with `GetPlanarReflection()`. That extra scene render is the cost, so bound it with `resolutionScale` (default 0.5) and `layerMask`. See `references/looks.md` for all three.

## Cost

The post stack is not free. AO, SSR, depth of field, and god rays each add screen-space passes, and mobile and web are the budget. Keep `ambientOcclusionHalfResolution: true`, prefer `DepthOfFieldQuality.low` on mobile, and do not stack SSR plus god rays plus depth of field on a low-end target without profiling. The `clean` look is nearly free; `moody` is the heaviest. See `references/looks.md` for the full per-effect knob reference, defaults, and cost notes.
