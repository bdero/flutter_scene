# The look stack, knob by knob

Every field here is a constructor argument on `EnvironmentSettings` (`lib/src/environment_settings.dart`). Assigning `scene.environmentSettings = EnvironmentSettings(...)` applies all of them at once. Defaults are the constructor defaults; a preset only names what it changes. Direct lights (`scene.directionalLight` and friends) are separate and not covered by `EnvironmentSettings`.

Color fields are `vm.Vector3` (import `package:vector_math/vector_math.dart as vm`).

---

## Base look

| Field | Default | What it does |
| --- | --- | --- |
| `toneMapping` | `ToneMappingMode.pbrNeutral` | HDR to display operator. `pbrNeutral` preserves hue/saturation, `aces` is contrasty and filmic, `agx` has the gentlest highlight rolloff, `reinhard`/`linear` are simpler references. |
| `exposure` | `1.0` | Linear scene exposure multiplier. The one knob for overall brightness. Do not use `2.0`; that was an old-renderer hack. |
| `environmentIntensity` | `1.0` | Scales image-based lighting (the environment map) contribution. |
| `agxWhite` | `16.29` | AgX white point, only meaningful with `ToneMappingMode.agx`. |
| `agxContrast` | `1.25` | AgX contrast, only with `agx`. |

`environment` (an `EnvironmentMap?`) and the sky fields are also on `EnvironmentSettings`, but building environment maps is the domain of the idioms skill; a null environment resolves to a default studio IBL.

## Auto exposure (`autoExposure*`)

Meters the frame and multiplies on top of `exposure`. Off by default.

| Field | Default | What it does |
| --- | --- | --- |
| `autoExposureEnabled` | `false` | Turn metering on. |
| `autoExposureStrength` | `0.55` | How fully it drives toward the metered target (0 = none, 1 = full). |
| `autoExposureCompensation` | `0.0` | EV bias applied after metering. |
| `autoExposureMinEv` / `autoExposureMaxEv` | `-4.0` / `4.0` | Clamp range for the adaptation. |
| `autoExposureSpeedUp` / `autoExposureSpeedDown` | `3.0` / `1.0` | Adaptation rate brightening vs darkening. |

## Bloom (`bloom*`)

Blooms bright pixels. Off by default. The cheapest way to make a scene feel lit rather than rendered.

| Field | Default | What it does |
| --- | --- | --- |
| `bloomEnabled` | `false` | Turn bloom on. |
| `bloomThreshold` | `1.0` | Brightness above which a pixel blooms. Lower for more glow. |
| `bloomIntensity` | `0.15` | Strength of the added glow. |
| `bloomScatter` | `0.7` | Spread of the glow, wider values feel dreamier. |

## Color grading (`colorGrading*`)

Post-tone-map color shaping. Off by default. Reach here to change the *mood* of the color rather than the exposure.

| Field | Default | What it does |
| --- | --- | --- |
| `colorGradingEnabled` | `false` | Turn grading on. |
| `brightness` | `1.0` | Multiplicative brightness. |
| `contrast` | `1.0` | Contrast around mid-gray. |
| `saturation` | `1.0` | Color saturation. Above 1 is vivid, below 1 desaturates toward gray. |
| `temperature` | `0.0` | Warm (positive) to cool (negative) white balance. |
| `tint` | `0.0` | Green to magenta balance. |
| `lift` / `gamma` / `gain` | `Vector3(0)` / `Vector3(1)` / `Vector3(1)` | Per-channel shadow/mid/highlight color control (lift-gamma-gain). |
| `colorGradingLut` | `null` | A `ColorLut` (from a `.cube` file) applied after tone mapping. Independent of `colorGradingEnabled`. |
| `colorGradingLutBlend` | `1.0` | LUT mix amount. |

## Vignette (`vignette*`)

Darkens the frame edges. Off by default. Small amounts read as cinematic; large amounts as a peephole.

| Field | Default | What it does |
| --- | --- | --- |
| `vignetteEnabled` | `false` | Turn vignette on. |
| `vignetteIntensity` | `0.5` | Darkening strength at the edge. |
| `vignetteRadius` | `0.75` | How far in the darkening starts (smaller = tighter, more closed-in). |
| `vignetteSmoothness` | `0.5` | Falloff softness of the edge. |

## Chromatic aberration (`chromaticAberration*`)

Splits color channels toward the edges. Off by default. A touch adds a lens feel; too much looks broken.

| Field | Default | What it does |
| --- | --- | --- |
| `chromaticAberrationEnabled` | `false` | Turn it on. |
| `chromaticAberrationIntensity` | `0.2` | Channel-separation strength. |

## Film grain (`filmGrain*`)

Adds animated grain. Off by default. Sells a moody or analog look and hides banding in dark gradients.

| Field | Default | What it does |
| --- | --- | --- |
| `filmGrainEnabled` | `false` | Turn it on. |
| `filmGrainIntensity` | `0.3` | Grain strength. |

## Ambient occlusion (`ambientOcclusion*`)

Screen-space contact darkening. Off by default. Requires a `PerspectiveCamera`. The single biggest upgrade for "grounded" vs "floating". Half-resolution by default to stay affordable.

| Field | Default | What it does |
| --- | --- | --- |
| `ambientOcclusionEnabled` | `false` | Turn AO on. |
| `ambientOcclusionMethod` | `AmbientOcclusionMethod.obscurance` | `obscurance` is the cheap default; `groundTruth` (GTAO) is higher quality and needed for bent normals. |
| `ambientOcclusionIntensity` | `1.0` | Darkening strength. |
| `ambientOcclusionRadius` | `0.33` | World-space sampling radius. |
| `ambientOcclusionPower` | `1.5` | Contrast of the occlusion curve. |
| `ambientOcclusionBias` | `0.07` | Self-occlusion rejection. |
| `ambientOcclusionBentNormals` | `false` | Compute bent normals (needs `groundTruth`); improves indirect lighting direction and enables `bentCone` specular AO. |
| `ambientOcclusionSpecularMode` | `SpecularAmbientOcclusionMode.none` | `simple` occludes reflections cheaply; `bentCone` is directional and needs bent normals. |
| `ambientOcclusionHalfResolution` | `true` | Compute at half res. Keep on unless AO edges look too coarse. |
| `ambientOcclusionIndirectLight` | `0.0` | Above 0 turns on screen-space global illumination (SSGI) bounce; expensive. |
| `ambientOcclusionMultiBounce` | `0.0` | Approximate multi-bounce darkening recovery. |
| `ambientOcclusionSampleCount` | `16` | Samples for the `obscurance` method. |
| `ambientOcclusionSliceCount` / `ambientOcclusionStepsPerSlice` | `3` / `3` | GTAO slice sampling. |
| `ambientOcclusionDetail` | `0.5` | Fine-detail term weight (obscurance). |
| `ambientOcclusionHorizonAngle` | `0.06` | Horizon rejection angle. |
| `ambientOcclusionThickness` / `ambientOcclusionThicknessHeuristic` | `0.5` / `0.004` | Depth thickness assumptions for occlusion. |
| `ambientOcclusionDirectLightAffect` | `0.0` | How much AO also dims direct light. |
| `ambientOcclusionVisibilityBitmask` | `false` | Bitmask visibility estimator. |
| `ambientOcclusionDepthMipChain` | `false` | Build a depth mip chain for wide-radius sampling. |

## Screen-space reflections (`screenSpaceReflections*`)

Reflects on-screen geometry. Off by default. Requires a `PerspectiveCamera`. Adds realism to floors, water, and glossy surfaces, but only reflects what is on screen.

| Field | Default | What it does |
| --- | --- | --- |
| `screenSpaceReflectionsEnabled` | `false` | Turn SSR on. |
| `screenSpaceReflectionsIntensity` | `1.0` | Reflection strength. |
| `screenSpaceReflectionsMaxDistance` | `24.4` | Max world-space ray distance. |
| `screenSpaceReflectionsThickness` | `0.46` | Assumed surface thickness for hit tests. |
| `screenSpaceReflectionsStride` | `9.0` | March step size (larger = faster, coarser). |
| `screenSpaceReflectionsMaxSteps` | `90` | Ray-march step budget. |
| `screenSpaceReflectionsBlur` | `0.3` | Roughness-based blur of the reflection. |
| `screenSpaceReflectionsDistanceFadeStart` | `0.0` | Where reflections start fading with distance. |
| `screenSpaceReflectionsResolutionScale` | `1.0` | Compute resolution scale; drop below 1 to save cost. |

## Fog (`fog*`)

Distance and height fog, evaluated in linear HDR before tone mapping. Off by default. Needs both `fogEnabled` and a non-`none` `fogMode`. Applies to lit and unlit materials; the skybox is left unfogged, so set `fogColor` to your horizon color for distant blending.

| Field | Default | What it does |
| --- | --- | --- |
| `fogEnabled` | `false` | Turn fog on. |
| `fogMode` | `FogMode.exponential` | `none`, `linear`, `exponential`, `exponentialSquared`. Must be non-`none` to render. |
| `fogColor` | `Vector3(0.6, 0.7, 0.8)` | Fog tint. Match your sky/horizon. |
| `fogDensity` | `0.02` | Density for the exponential modes. |
| `fogStart` / `fogEnd` | `0.0` / `200.0` | Near/far bounds for `linear` mode. |
| `fogSkyColorInfluence` | `0.0` | Blend fog color toward the sky color. |
| `fogMaxOpacity` | `1.0` | Cap on how opaque fog gets. |
| `fogHeight` / `fogHeightFalloff` | `0.0` / `0.0` | Height-fog band and falloff. |
| `fogSunInScatter` / `fogSunInScatterExponent` | `0.0` / `8.0` | Sun in-scatter glow through the fog. |
| `fogCutoffDistance` | `0.0` | Distance beyond which fog stops accumulating. |

## God rays (`godRays*`)

Volumetric light shafts. Off by default. Requires a shadow-casting `DirectionalLight` and a `PerspectiveCamera`; without a shadow-casting sun there is nothing to shaft.

| Field | Default | What it does |
| --- | --- | --- |
| `godRaysEnabled` | `false` | Turn shafts on. |
| `godRaysIntensity` | `1.0` | Shaft strength. |
| `godRaysDensity` | `0.5` | Medium density the light scatters through. |
| `godRaysAnisotropy` | `0.7` | Forward-scatter bias (higher = tighter shafts toward the sun). |
| `godRaysStepCount` | `24` | March steps; higher is smoother and costlier. |
| `godRaysMaxDistance` | `200.0` | Max shaft distance. |
| `godRaysJitter` | `1.0` | Dither to hide banding. |
| `godRaysColor` | `Vector3(1)` | Shaft tint. |

## Depth of field (`depthOfField*`)

Physically parameterized lens blur. Off by default. Requires a `PerspectiveCamera`. Great for a hero shot, wasteful for a full interactive scene.

| Field | Default | What it does |
| --- | --- | --- |
| `depthOfFieldEnabled` | `false` | Turn DoF on. |
| `depthOfFieldFocusDistance` | `10.0` | World distance in sharp focus. |
| `depthOfFieldFStop` | `2.8` | Aperture; lower = shallower focus, more blur. |
| `depthOfFieldFocalLength` | `0.0` | Lens focal length (0 derives from FOV). |
| `depthOfFieldSensorHeight` | `0.024` | Sensor height in meters (35mm-ish). |
| `depthOfFieldBlurScale` | `1.0` | Overall blur multiplier. |
| `depthOfFieldMaxForegroundBlur` / `depthOfFieldMaxBackgroundBlur` | `24.0` / `32.0` | Blur radius caps. |
| `depthOfFieldBladeCount` | `0` | Aperture blades for bokeh shape (0 = round). |
| `depthOfFieldBladeRotation` / `depthOfFieldBladeCurvature` | `0.0` / `0.0` | Bokeh blade shaping. |
| `depthOfFieldQuality` | `DepthOfFieldQuality.medium` | `low` (16 taps, mobile/web), `medium` (32 taps + postfilter), `high` (48 taps). |

---

## Cost and budget

Post effects are screen-space passes; they cost per output pixel, not per triangle. Rough order, cheapest first:

- **Nearly free.** Tone mapping, exposure, color grading, vignette, chromatic aberration, film grain, bloom. The `clean` and `stylized` looks live here.
- **Moderate.** Ambient occlusion (keep `ambientOcclusionHalfResolution: true`), fog.
- **Expensive.** SSR, god rays, depth of field, and especially SSGI (`ambientOcclusionIndirectLight > 0`). Each adds ray-marching or gather passes.

Budget guidance:

- **Mobile and web are the ceiling.** A look that is smooth on desktop can tank a phone. Profile the target, do not assume.
- **Keep AO at half resolution** unless the coarse edges actually show. Full-res AO rarely earns its cost.
- **Do not stack the expensive effects blindly.** SSR plus god rays plus depth of field together on a low-end device needs profiling; drop one or lower its resolution/step budget (`screenSpaceReflectionsResolutionScale`, `godRaysStepCount`, `DepthOfFieldQuality.low`).
- **Depth of field is a hero-shot tool.** It reads as intentional on a framed still and as a smear on a free-moving interactive camera. Prefer it where the camera is controlled.
- **Bloom and grading buy the most look per cost.** When you need "flashier" cheaply, reach for these before the screen-space passes.

## Why each look is built the way it is

**showcase** aims for a clean, believable, flattering render, the default for showing a model off. `aces` tone mapping gives contrast and pop; soft bloom (threshold just above 1.0) lights the highlights without haze; GTAO with bent normals and `bentCone` specular AO grounds the object and tightens reflections in its cavities; SSR adds real floor and surface reflections; a light vignette focuses the eye. Every choice supports "look at this object", nothing calls attention to itself.

**stylized** trades realism for graphic punch. It leans on color (saturation up, a warm push, contrast up) and glow (a lower bloom threshold so more of the frame blooms) and deliberately *omits* AO and SSR, because heavy occlusion and reflection read as realism and fight the flatter, poppier intent. Cheap to run, since it is all near-free passes.

**moody** is the atmospheric, cinematic end. Lower exposure and cool grading set a somber base; exponential fog with a dark horizon color adds depth and hides the far plane; strong AO deepens the shadows; a tight heavy vignette closes the frame; film grain and a touch of chromatic aberration add texture and a lens feel; god rays (given a shadow-casting sun) add drama. It is the most expensive look; on a tight budget, drop god rays first, then SSR if present.

**clean** is the honest look, for when the render must show the *actual* material and lighting without editorializing: an editor viewport, an inspector, a UI-embedded preview. Default `pbrNeutral` tone mapping preserves hue and saturation, and the only effect on is gentle half-res AO for grounding. No bloom, grading, or vignette, because each of those changes what the color and brightness actually are, which is exactly what an accurate preview must not do. Also the cheapest look by far.
