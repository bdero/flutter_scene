# Post-processing in flutter_scene

flutter_scene applies post-processing in two ways: a suite of built-in
effects you turn on and tune, and custom effects you author as fragment
shaders. Both are configured per scene through `Scene.postProcess`.

Everything is off by default, so a fresh scene does no extra work.

## Built-in effects

`Scene.postProcess` holds one settings object per effect. Each has an
`enabled` flag (off by default) and typed parameters:

```dart
final scene = Scene();

scene.postProcess.bloom
  ..enabled = true
  ..threshold = 1.0   // HDR brightness where blooming starts
  ..intensity = 0.5   // how strongly the glow is added back
  ..scatter = 0.7;    // blur spread, 0 to 1

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

The effects run in a fixed order. Bloom and color grading operate on the
linear HDR scene color before tone mapping; vignette, chromatic
aberration, and film grain are applied around the tone-map step. You do
not reorder the built-ins; you turn them on and tune them.

## Custom effects

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
  'build/shaderbundles/my_bundle.shaderbundle',
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

## How effects compose

Built-in effects run in their fixed order. Custom effects run in
`customEffects` list order, each at its chosen insertion point: every
`beforeTonemap` effect runs (before bloom and tone mapping), then the
built-in resolve, then every `afterTonemap` effect. Each custom effect
reads the previous result and writes the next, so order in the list
matters.

## Limitations

- **One pass per custom effect.** Each custom effect is its own
  full-screen pass. Stacking many has a per-pass cost; the built-in suite
  is folded into a single pass and is cheaper.
- **No depth input yet.** Custom effects receive scene color but not scene
  depth. Depth-based effects are a planned addition.
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
