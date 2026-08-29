# Post-processing in flutter_scene

flutter_scene applies post-processing in three ways: a suite of built-in
parametric effects you turn on and tune, custom fragment shaders authored as
a `PostEffect`, and custom fragment shaders authored as a `CustomRenderPass`
(the richer option, which can read scene depth, normals, and the shadow
map). All three are off by default, so a fresh scene does no extra work.

## Built-in effects

Most built-in effects live on `Scene.postProcess`, one settings object per
effect, each with an `enabled` flag (off by default) and typed parameters:

```dart
final scene = Scene();

scene.postProcess.bloom
  ..enabled = true
  ..threshold = 1.0   // HDR brightness where blooming starts
  ..intensity = 0.5   // how strongly the glow is added back
  ..scatter = 0.7;    // blur spread, 0 to 1

scene.postProcess.bloom.lensFlare
  ..enabled = true              // rides the bloom chain, needs bloom on
  ..intensity = 1.0             // flare strength relative to the bloom
  ..ghostCount = 4              // internal-reflection ghosts, up to 8
  ..ghostSpacing = 0.3          // spacing along the line through center
  ..haloRadius = 0.35           // circular halo radius, in screen UV
  ..haloIntensity = 1.0         // halo strength relative to the ghosts
  ..chromaticAberration = 0.005; // radial dispersion of the features

scene.postProcess.colorGrading
  ..enabled = true
  ..brightness = 1.0
  ..contrast = 1.1
  ..saturation = 1.2
  ..temperature = 0.1 // white balance, -1 (cool) to 1 (warm)
  ..tint = 0.0        // -1 (magenta) to 1 (green)
  ..lift = Vector3.zero()    // per-channel shadows
  ..gamma = Vector3.all(1.0) // per-channel midtones
  ..gain = Vector3.all(1.0); // per-channel highlights

scene.postProcess.vignette
  ..enabled = true
  ..intensity = 0.5   // how dark the edges get
  ..radius = 0.75     // where darkening begins, from the center
  ..smoothness = 0.5; // falloff softness

scene.postProcess.chromaticAberration
  ..enabled = true
  ..intensity = 0.5;  // channel separation at the edges

scene.postProcess.filmGrain
  ..enabled = true
  ..intensity = 0.3;  // animated noise strength
```

A few effects that need more than a flat settings object, or that read
scene geometry, live directly on `Scene` instead of `Scene.postProcess`:
`Scene.depthOfField`, `Scene.godRays`, `Scene.screenSpaceReflections`,
`Scene.autoExposure`, and `Scene.screenDistortion`. Each still follows the
settings-object-with-`enabled` shape; see their dartdoc for parameters.

### Radial screen distortion

`Scene.screenDistortion` drives a ring distortion (plus an optional
chromatic split) expanding from a screen point, for shockwaves and impact
pulses. It holds a list of `DistortionPulse`s (up to
`ScreenDistortionSettings.maxPulses`, currently 4) so several can be live at
once; each pulse is plain data you animate per frame:

```dart
scene.screenDistortion.enabled = true;
final pulse = DistortionPulse(strength: 0.0);
scene.screenDistortion.pulses.add(pulse);

// Per frame, while the pulse plays.
final uv = scene.camera!.projectToScreenUv(blastWorldPosition, viewportSize);
if (uv != null) {
  pulse
    ..center = uv
    ..radius = elapsed * 1.6
    ..strength = 0.03 * (1.0 - elapsed / 0.7).clamp(0.0, 1.0)
    ..chromaticAberration = 0.6;
}

// When it ends.
scene.screenDistortion.pulses.remove(pulse);
```

`Camera.projectToScreenUv` is the counterpart of `Camera.worldToScreen` that
returns normalized screen UV (origin top-left) instead of pixels, for
placing a pulse from a world-space impact point; it returns null when the
point is behind the camera.

Distortion runs on the display-referred image after tone mapping, so it
warps bloom along with the rest of the frame and reads the same
`Scene.postProcess.chromaticAberration` does; the two are independent and
will double up if both are on, so drive one or the other for a given pulse.

## The full pass order

The built-in pipeline is a fixed sequence; you turn stages on and tune
them, you do not reorder them. From `Scene.render` for one view, in order:

1. Shadow map (cascades and/or spot shadows), when a shadow-casting light
   needs one.
2. The depth prepass (and ambient occlusion, if enabled), when a
   perspective camera and any consumer (occlusion, reflections, a material
   sampling scene depth, or a custom pass) need scene depth.
3. The scene itself draws into linear HDR scene color, opaque then
   translucent.
4. Screen-space reflections refine the lit HDR color in place, when
   enabled.
5. God rays add volumetric in-scattered light, when enabled (`Scene.godRays`,
   requires a shadow-casting directional light and a perspective camera).
6. User `CustomRenderPass`es at `RenderStage.afterScene` run, in the order
   added.
7. Depth of field defocuses the HDR image, when enabled.
8. `PostEffect`s at `PostInsertion.beforeTonemap` run, in
   `postProcess.customEffects` list order.
9. Auto exposure meters the HDR image and derives the correction factor the
   resolve applies, when enabled.
10. Bloom runs in HDR and is composited back in by the resolve.
11. User `CustomRenderPass`es at `RenderStage.beforeToneMapping` run.
12. The resolve pass produces the first display-referred image: chromatic
    aberration (sample-time UV split), exposure, color grading, the tone
    mapping operator, display encoding, then vignette and film grain.
13. Screen distortion warps the display image, when a pulse is live
    (`Scene.screenDistortion`).
14. User `CustomRenderPass`es at `RenderStage.afterToneMapping` run.
15. FXAA anti-aliases the image, when the scene's anti-aliasing mode is
    `AntiAliasingMode.fxaa`.
16. `PostEffect`s at `PostInsertion.afterTonemap` run.
17. User `CustomRenderPass`es at `RenderStage.afterAntiAliasing` run.
18. The selection outline composites around highlighted nodes, last, when
    any node has a `Node.highlightColor` set.

Every step is skipped entirely when its settings are off (or, for the
depth prepass, when nothing needs it), so an unused stage costs nothing.

## Custom effects: PostEffect

A `PostEffect` is a fragment shader that reads the current color and
writes a new one. It is the post-processing counterpart of
`ShaderMaterial`, and the authoring workflow is the same: write a fragment
shader, compile it through the `flutter_gpu_shaders` build hook into a
`.shaderbundle`, load it, wrap it, and add it to the scene.

### Authoring workflow at a glance

1. Write a fragment shader (see the contract below).
2. Add it to your shader bundle manifest and build it with the
   `flutter_gpu_shaders` hook, exactly as in `MATERIALS.md`.
3. Load the bundle, pull out the shader, and wrap it in a `PostEffect`.
4. Add the effect to `scene.postProcess.customEffects`.

`examples/flutter_app/shaders/example_wave.frag` is a complete worked
case; read along with this doc.

### The engine contract

The engine binds the current color to a `sampler2D input_color` that your
shader samples at the `v_uv` varying, and you write to `frag_color`:

```glsl
uniform sampler2D input_color;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  frag_color = texture(input_color, v_uv);
}
```

That is a complete (pass-through) effect. The fullscreen vertex shader is
provided by the engine; you only write the fragment shader.

**Frame info.** Set `PostEffect.useFrameInfo = true` and declare a
`PostFrameInfo` block to receive the target resolution, texel size, and a
seconds time value (useful for animation and for sampling neighbors):

```glsl
uniform PostFrameInfo {
  vec2 resolution;
  vec2 texel_size; // 1.0 / resolution
  float time;      // seconds
  float _pad;
}
frame;
```

`useFrameInfo` defaults to `false`. The engine only binds `PostFrameInfo`
when you opt in, so an effect that does not use it does not have to declare
it.

**Your own parameters.** Declare uniform blocks and textures and set them
by name from Dart with `setUniformBlock` / `setTexture`, exactly like
`ShaderMaterial`. The std140 packing rules are identical; see the uniform
block packing section of `MATERIALS.md`.

### Insertion points and the output contract

`PostEffect.insertion` selects where the effect runs:

- `PostInsertion.beforeTonemap` (the default): runs on the linear HDR scene
  color, before tone mapping. Output **linear HDR premultiplied by alpha**,
  the same contract as a material fragment shader. Values above 1.0 are
  fine; the tone curve rolls them off. This is the general-purpose slot.
- `PostInsertion.afterTonemap`: runs on the display-referred image, after
  tone mapping. Output a display color.

A simple resampling effect (like the wave example) works at either point.
Effects that produce or expect high dynamic range belong before tone
mapping.

### Wiring it up

```dart
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

final library = await gpu.loadShaderLibraryAsync(
  await gpu.resolveShaderBundleKey('my_bundle'),
);

final effect = PostEffect(
  fragmentShader: library!['WaveFragment']!,
  insertion: PostInsertion.beforeTonemap,
  useFrameInfo: true,
)..setUniformBlockFromFloats('WaveInfo', [
    0.008, // amplitude
    24.0,  // frequency
    3.0,   // speed
    0.0,   // padding
  ]);

scene.postProcess.customEffects.add(effect);
```

The matching shader:

```glsl
uniform sampler2D input_color;

uniform PostFrameInfo {
  vec2 resolution;
  vec2 texel_size;
  float time;
  float _pad0;
}
frame;

uniform WaveInfo {
  float amplitude;
  float frequency;
  float speed;
  float _pad1;
}
wave;

in vec2 v_uv;

out vec4 frag_color;

void main() {
  float offset =
      sin(v_uv.y * wave.frequency + frame.time * wave.speed) * wave.amplitude;
  frag_color = texture(input_color, vec2(v_uv.x + offset, v_uv.y));
}
```

## Custom effects: CustomRenderPass

A `CustomRenderPass` is the richer extension point: an object with a
`RenderStage` (one of the four named anchors in the pass order above), a
declared `Set<RenderInput>`, and a `RenderPassContext` that offers
`applyShader` (the same full-screen-shader step `PostEffect` runs) and
`drawObjects` (render a filtered set of nodes flat into a mask texture,
for outlines and highlights). The built-in god rays, screen-space
reflections, depth of field, and screen distortion passes are all ordinary
`CustomRenderPass`es, so anything they do, a custom one can.

Declaring a `RenderInput` (`depth`, `normals`, `shadowMap`) makes the
engine produce that buffer for the frame and exposes it on the context, so
a custom pass can read scene geometry, not just color:

```dart
class TintPass extends CustomRenderPass {
  TintPass(this.shader);
  final gpu.Shader shader;
  @override
  String get name => 'tint';
  @override
  RenderStage get stage => RenderStage.afterToneMapping;
  @override
  void execute(RenderPassContext context) {
    context.applyShader(shader); // reads input_color, writes the chain
  }
}

scene.addRenderPass(TintPass(shader));
```

## Limitations

- **One pass per custom effect.** Each `PostEffect` or `CustomRenderPass`
  is its own full-screen pass. Stacking many has a per-pass cost; the
  built-in suite is folded into a single resolve pass and is cheaper.
- **Editing a shader's contents needs a clean rebuild.** The shader build
  hook only re-runs on a manifest change, not on a content-only edit to an
  existing shader. After editing a `.frag`, remove the `.dart_tool` and
  `build` directories and run `flutter pub get` before rebuilding.

## See also

- `MATERIALS.md`: the custom-material (`ShaderMaterial`) workflow and the
  shared shader-bundle build steps and std140 packing rules.
- `examples/flutter_app/shaders/example_wave.frag` and the settings
  sidebar in `examples/flutter_app/lib/main.dart`: a custom effect and the
  built-in controls, end to end.
