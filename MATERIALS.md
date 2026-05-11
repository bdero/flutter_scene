# Custom materials in flutter_scene

This doc walks through writing a custom material for flutter_scene by
authoring a fragment shader. The 0.12 release ships the foundation
for this workflow as `ShaderMaterial`; a more ergonomic declarative
material format is planned and tracked in [issue #22][issue22].

If you've worked with Three.js's `ShaderMaterial`, Bevy's `Material`
trait, or Filament's `.mat` files, the underlying mental model will
be familiar. flutter_scene's v1 surface is the most permissive of the
three: you write a complete GLSL fragment shader, declare the uniform
blocks and samplers you want, and bind them by name from Dart.

## Authoring workflow at a glance

1. Add `flutter_gpu_shaders` to your app and create a shader bundle
   manifest plus a `hook/build.dart` that compiles it.
2. Write a fragment shader. Consume the standard vertex outputs the
   engine provides; declare your own uniform blocks and textures.
3. Load the compiled bundle at runtime with
   `gpu.ShaderLibrary.fromAsset(...)` and pull out your fragment
   shader entry by name.
4. Construct a `ShaderMaterial` wrapping the shader; set its uniform
   blocks and textures by name; attach it to the `MeshPrimitive`s
   that should use it.

The toon example under `examples/flutter_app/` is a complete worked
case. Read along with this doc.

## The engine contract

flutter_scene's engine vertex shaders (`UnskinnedVertex` and
`SkinnedVertex`, both in the bundle exposed as
`baseShaderLibrary`) emit the same five outputs in both layouts.
Your fragment shader receives them as `in` declarations:

```glsl
in vec3 v_position;        // world space
in vec3 v_normal;          // world space, not necessarily unit length
in vec3 v_viewvector;      // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;           // per-vertex color, white when the model has none
```

You must write to `out vec4 frag_color;` (the location-0 fragment
output is fixed by the engine). Everything else is up to you.

The engine binds a vertex uniform block named `FrameInfo` containing
the model, camera, and camera-position matrices. You do not see this
in your fragment shader directly; the vertex outputs above are
already in world space.

When you set `ShaderMaterial.useEnvironment = true`, the engine also
binds the active `Scene`'s IBL textures to these standard sampler
names if your fragment shader declares them:

```glsl
uniform sampler2D radiance_texture;
uniform sampler2D irradiance_texture;
uniform sampler2D brdf_lut;
```

Use them if you want image-based lighting from a custom material.
Leave them undeclared if you don't.

## Writing the fragment shader

Here's the smallest possible useful shader, which renders the
per-vertex color modulated by a single uniform tint:

```glsl
// shaders/vertex_color.frag
uniform FragInfo {
  vec4 tint;
}
frag_info;

in vec2 v_texture_coords;
in vec4 v_color;

out vec4 frag_color;

void main() {
  frag_color = v_color * frag_info.tint;
}
```

Save the file under your app's shader directory, then add a manifest
entry alongside the engine's built-in shaders:

```json
{
  "VertexColorFragment": {
    "type": "fragment",
    "file": "shaders/vertex_color.frag"
  }
}
```

`flutter_gpu_shaders` compiles each entry through `impellerc` into a
single `.shaderbundle` packaged with your app.

## Building the shader bundle

In your `hook/build.dart`:

```dart
import 'package:hooks/hooks.dart';
import 'package:flutter_gpu_shaders/build.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/my_bundle.shaderbundle.json',
    );
  });
}
```

In your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_gpu:
    sdk: flutter
  flutter_gpu_shaders: ^0.4.0
  flutter_scene: ^0.12.0

flutter:
  assets:
    - build/shaderbundles/my_bundle.shaderbundle
```

The bundle is written to `build/shaderbundles/<name>.shaderbundle`,
relative to your package root. It's the same workflow flutter_scene
uses for its own shaders.

## Wiring it up in Dart

```dart
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

// If you also `import 'package:flutter/material.dart'`, hide its
// `Material` widget to avoid a clash with flutter_scene's:
//
//   import 'package:flutter/material.dart' hide Material;
//
// (flutter_scene's Material is the rendering material; Flutter
// Material is the design system widget.)

// 1. Load the bundle and pull out the fragment shader.
final library = gpu.ShaderLibrary.fromAsset(
  'build/shaderbundles/my_bundle.shaderbundle',
)!;
final fragmentShader = library['VertexColorFragment']!;

// 2. Build a ShaderMaterial.
final material = ShaderMaterial(fragmentShader: fragmentShader);

// 3. Set parameters by name.
material.setUniformBlockFromFloats('FragInfo', [
  1.0, 0.8, 0.4, 1.0, // tint
]);

// 4. Attach to a mesh primitive.
node.mesh!.primitives[0].material = material;
```

The runtime resolves uniform-block and sampler names against the
shader's reflection metadata. If you misspell a name, Flutter GPU
throws at draw time with a clear message naming the slot that
couldn't be found.

## Uniform block packing

This is the largest footgun in v1. Flutter GPU resolves a uniform
*block* by name and gives you a single byte buffer to fill. The
contents of that buffer follow the GLSL std140 layout rules, which
your packing code on the Dart side has to match exactly. The most
common rules:

| Type            | Size  | Alignment | Notes |
| --------------- | ----- | --------- | ----- |
| `bool`, `int`, `float` | 4 | 4 | |
| `vec2`          | 8     | 8         | |
| `vec3`          | 12    | **16**    | Pads up to 16 bytes |
| `vec4`          | 16    | 16        | |
| `mat3`          | 48    | 16        | Three `vec4` columns, 4 bytes padding each |
| `mat4`          | 64    | 16        | |
| Array element   | varies | **16**   | Every array element strides to the next 16-byte boundary |
| Struct          | varies | 16       | Same alignment as `vec4` |

The two cases that bite most often: declare a `vec3` followed by a
`float` and the float occupies the 4 bytes of trailing pad on the
`vec3`, not a fresh 16-byte slot. Declare a `float` followed by a
`vec3` and the `vec3` jumps to the next 16-byte boundary, leaving 12
bytes of padding before it. **When in doubt, declare your block with
`vec4`s and `float`s rounded up to multiples of four, and you'll be
right.**

A worked example: this GLSL block

```glsl
uniform ToonInfo {
  vec4 base_color;
  vec4 rim_color;
  vec4 light_direction;
  float band_count;
  float rim_strength;
  float rim_width;
  float ambient;
}
toon;
```

packs as 16 floats (64 bytes total), one `vec4` per row, with the
four trailing scalars filling the final row. Construct it in Dart
as:

```dart
material.setUniformBlock(
  'ToonInfo',
  ByteData.sublistView(
    Float32List.fromList([
      // base_color
      1, 1, 1, 1,
      // rim_color
      0.6, 0.8, 1.0, 1.0,
      // light_direction (vec4 with w=0)
      0.4, 0.8, -0.5, 0,
      // band_count, rim_strength, rim_width, ambient
      3, 1.0, 0.6, 0.3,
    ]),
  ),
);
```

The v2 preprocessor planned in issue #22 will generate this packing
code from the `.mat` source so you never write it by hand. Until
then, follow the std140 rules and document your block layouts in a
comment near the GLSL declaration.

## Render-state knobs

`ShaderMaterial` exposes a small set of render-state fields you can
configure in the constructor or mutate later:

- `cullingMode` (default `gpu.CullMode.backFace`): which faces to
  cull before rasterization.
- `windingOrder` (default `gpu.WindingOrder.counterClockwise`):
  triangle winding convention. Match this to your model's
  authoring; glTF uses counter-clockwise.
- `isOpaqueOverride` (default `true`): whether the encoder treats
  this material as opaque (depth-write enabled, drawn in submission
  order) or translucent (deferred to a back-to-front pass with
  alpha blending).

Set `cullingMode: gpu.CullMode.none` to render double-sided. Set
`isOpaqueOverride: false` to render translucent materials with
alpha blending. There are no other render-state knobs in v1;
authoring the full PSO is on the v2 roadmap.

## What's not in v1

- **No shader hot reload.** Editing a `.frag` requires a full
  restart (hot reload doesn't touch the `flutter_gpu_shaders` build
  hook). This is the single largest authoring-friction gap and is
  the top item on the v3 roadmap.
- **No engine PBR helpers exposed to your shaders.** If you want
  PBR-style shading with image-based lighting, you have to either
  inline the math in your fragment shader or extend
  `PhysicallyBasedMaterial`. The internal GLSL chunks
  (`pbr.glsl`, `normals.glsl`, etc.) are not packaged for external
  consumption yet; v2 will solve cross-package `#include`
  distribution.
- **No declarative material format.** You write GLSL plus a
  `MaterialT` subclass; v2 will introduce a `.mat`-style format
  that drives both shader source and Dart bindings from one file.
- **No inspector / hint annotations.** v2 will parse Godot-style
  uniform hints (`hint_range`, `source_color`) and surface them
  for tooling.
- **No vertex-shader customization.** Use `UnskinnedVertex` or
  `SkinnedVertex` from `baseShaderLibrary` (or whichever the
  geometry was built with). Custom vertex shaders are a v2 item.

See issue #22 for the full v2 design discussion.

## Troubleshooting

**"`gpu.ShaderLibrary.fromAsset` returns null."** The bundle wasn't
built into your app's asset directory. Check that
`build/shaderbundles/<name>.shaderbundle` is listed under
`flutter.assets` in your `pubspec.yaml`, and that your `hook/build.dart`
ran (`flutter run` should rerun the hook on each build; if it doesn't,
follow CLAUDE.md Trap #3's reset recipe).

**"Failed to find uniform slot X."** Flutter GPU couldn't find a
uniform block or sampler with the name you passed to `setUniformBlock`
or `setTexture`. Most common cause: the shader declares it under a
different name (the variable name, not the type name). For
`uniform FragInfo { ... } frag_info;` the block is bound by the
type name `FragInfo`, not the variable name `frag_info`.

**Wrong colors / black geometry.** Almost always a std140 packing
mismatch. Add a `vec3` test to your block to verify the layout: if
you read back something other than what you wrote, you have a
padding bug. The simplest defense is to declare uniform blocks with
no `vec3` members, just `vec4` and `float`/`vec2`/`vec4` aligned to
4-float boundaries.

**Black model.** Check `useEnvironment` and your sampler bindings.
Unbound samplers can read garbage on some backends.

## See also

- [Issue #22][issue22]: the v2 declarative material format and
  preprocessor design.
- `examples/flutter_app/lib/example_toon.dart`: the worked toon
  shader the v1 ships with.
- `packages/flutter_scene/shaders/flutter_scene_standard.frag`: the
  engine's PBR fragment shader, useful as a reference for what a
  full custom material can do.
- `flutter_gpu_shaders` on pub.dev: the build-hook helper that
  drives `impellerc`.

[issue22]: https://github.com/bdero/flutter_scene/issues/22
