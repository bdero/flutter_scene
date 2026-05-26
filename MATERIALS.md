# Custom materials in flutter_scene

flutter_scene gives you two ways to write a custom material:

1. **The `.fmat` declarative format (recommended).** You declare your
   parameters once and fill in a small `Surface()` function in GLSL. A build
   hook compiles it, and `PreprocessedMaterial` wires it up at runtime: typed,
   name-addressed parameters with no std140 packing by hand, and the engine's
   physically based lighting for free if you want it. This is the path most
   materials should use.
2. **`ShaderMaterial` (the low-level escape hatch).** You write a complete raw
   GLSL fragment shader, declare your own uniform blocks and samplers, and bind
   them by name from Dart, packing std140 yourself. Use this when you need full
   control or a shader shape the `.fmat` format doesn't cover yet.

Both paths share the same engine contract (the vertex outputs your shader
receives and the color it must output), documented below. If you've used
Filament's `.mat` files or Godot's shaders, the `.fmat` model will feel
familiar; if you've used Three.js's `ShaderMaterial`, that's `ShaderMaterial`
here.

The roadmap for this surface is tracked in [issue #22][issue22].

---

# The `.fmat` format

## Quick start

Author a material. A `.fmat` file has two blocks: a `material { }` metadata
block and a `fragment { }` GLSL block.

```
// materials/toon.fmat
material {
  name: "Toon",
  shading_model: unlit,
  blending: opaque,
  culling: back,

  parameters: [
    { type: vec4,      name: base_color, hint: source_color, default: [1, 1, 1, 1] },
    { type: vec3,      name: light_direction, default: [0.4, 0.7, 0.5] },
    { type: int,       name: band_count, hint: range(1, 8, 1), default: 3 },
    { type: sampler2d, name: base_color_texture, hint: default_white },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec3 n = GetWorldNormal();
    float n_dot_l = max(dot(n, normalize(material_params.light_direction)), 0.0);
    float bands = max(float(material_params.band_count), 1.0);
    float banded = floor(n_dot_l * bands) / bands;

    vec4 tex = texture(base_color_texture, GetUV0());
    material.base_color = vec4(
        material_params.base_color.rgb * tex.rgb * banded,
        material_params.base_color.a * tex.a);
    PrepareMaterial(material);
  }
}
```

Compile it from your app's `hook/build.dart`:

```dart
import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    await buildMaterials(
      buildInput: config,
      buildOutput: output,
      materials: ['materials/toon.fmat'],
    );
  });
}
```

Declare the outputs as assets in `pubspec.yaml` (a `.shaderbundle` plus a
`.fmat.json` parameter sidecar):

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_scene: ^0.14.0
  hooks: ^1.0.0

flutter:
  assets:
    - build/shaderbundles/materials.shaderbundle
    - build/shaderbundles/materials.fmat.json
```

Then construct and use it at runtime:

```dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';

final library = gpu.ShaderLibrary.fromAsset(
  'build/shaderbundles/materials.shaderbundle',
)!;
final sidecar = (jsonDecode(
  await rootBundle.loadString('build/shaderbundles/materials.fmat.json'),
) as Map).cast<String, Object?>();

final toon = PreprocessedMaterial(
  fragmentShader: library['Toon']!,
  metadata: (sidecar['Toon'] as Map).cast<String, Object?>(),
);
toon.parameters
  ..setColor('base_color', const Color(0xFFE0A030))
  ..setInt('band_count', 4)
  ..setTexture('base_color_texture', myTexture);

node.mesh!.primitives[0].material = toon;
```

The bundle entry name and the sidecar key are the material's `name`
(`"Toon"` above). One `buildMaterials` call can compile several `.fmat` files
into one bundle; each becomes an entry keyed by its `name`.

## The `material` block

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `name` | string (required) | | The bundle entry name and sidecar key. |
| `shading_model` | `lit`, `unlit` | `lit` | `lit` runs the engine's PBR lighting; `unlit` outputs your color directly. |
| `blending` | `opaque`, `alpha` | `opaque` | `alpha` routes the material through the depth-sorted translucent pass. |
| `culling` | `back`, `front`, `none` | `back` | Which faces are culled; `none` is double-sided. |
| `parameters` | list of objects | `[]` | The material's parameters (see below). |

## Parameters

Each parameter is `{ type, name, hint?, default? }`.

**Types.** Scalar and vector types (`float`, `int`, `vec2`, `vec3`, `vec4`,
`mat4`) are packed into a uniform block named `MaterialParams`; you read them in
the shader as `material_params.<name>`. Sampler types (`sampler2d`,
`samplerCube`) are top-level uniforms; you read them by their bare name. `mat3`
is intentionally unsupported because of a std140 layout bug on the GLES backend;
use `mat4`.

**Hints** add editor and runtime semantics:

| Hint | Valid on | Effect |
| --- | --- | --- |
| `source_color` | `vec3`, `vec4` | The value is an sRGB-authored color; `setColor` decodes it to linear. |
| `range(min, max, step)` | `float`, `int` | A bounded numeric range (recorded for tooling). |
| `default_white` / `default_black` / `default_normal` / `default_transparent` | samplers | The placeholder texture used until you set one. |

**Defaults** are a number for scalars, or a list for vectors and matrices
(`default: [1, 1, 1, 1]` for a `vec4`). Samplers take a placeholder via their
hint, not a `default`. Defaults are applied when the material is constructed, so
an unset parameter still renders sensibly.

## The `fragment` block

The `fragment` block holds GLSL. A `lit` material must define
`void Surface(inout MaterialInputs material)`; you fill the surface description
and the engine runs the lighting. An `unlit` material's `Surface()` writes the
final color into `material.base_color`.

`MaterialInputs` is:

```glsl
struct MaterialInputs {
  vec4 base_color;   // linear rgb, straight (non-premultiplied) alpha
  vec3 normal;       // world-space shading normal
  vec3 emissive;     // linear emissive radiance (lit only)
  float metallic;    // 0 dielectric .. 1 conductor (lit only)
  float roughness;   // perceptual roughness, 0..1 (lit only)
  float occlusion;   // ambient occlusion, 1 = unoccluded (lit only)
};
```

Call `PrepareMaterial(material)` before returning from `Surface()` (a Filament
convention; it is reserved for derived-value setup).

**Engine inputs are read through accessors** rather than the raw varyings:

```glsl
vec3 GetWorldPosition();   // world-space fragment position
vec3 GetWorldNormal();     // normalized world-space geometric normal
vec3 GetViewDirection();   // normalized direction toward the camera
vec2 GetUV0();             // primary texture coordinates
vec4 GetVertexColor();     // interpolated per-vertex color (white if none)
```

The standard GLSL helpers from the engine's shader library are `#include`d for
you and available in `Surface()`: `SRGBToLinear`, the Cook-Torrance BRDF pieces
(`FresnelSchlick`, `DistributionGGX`, ...), `PerturbNormal` (normal-map
perturbation), and `SamplePrefilteredRadiance`.

For a `lit` material, fill `base_color` / `metallic` / `roughness` / `normal` /
`occlusion` / `emissive` and the engine produces the lit color (image-based
lighting plus the scene's directional light, with shadows). For an `unlit`
material, compute whatever you want and write it into `base_color`; the engine
outputs it premultiplied.

> The per-light `light()` hook (a custom BRDF inside the engine light loop) is
> not implemented yet; today, `lit` uses the engine BRDF and `unlit` gives you
> full control. See [issue #22][issue22].

---

# The engine contract (both paths)

flutter_scene's engine vertex shaders (`UnskinnedVertex` and `SkinnedVertex`)
emit the same five world-space outputs. The `.fmat` accessors wrap these; a raw
`ShaderMaterial` declares them directly:

```glsl
in vec3 v_position;        // world space
in vec3 v_normal;          // world space, not necessarily unit length
in vec3 v_viewvector;      // camera_position - vertex_position
in vec2 v_texture_coords;
in vec4 v_color;           // per-vertex color, white when the model has none
```

The fragment output is `out vec4 frag_color;` at location 0.

**Output linear color premultiplied by alpha.** flutter_scene renders into a
floating-point HDR scene-color target and then runs one full-screen resolve pass
that applies exposure (`Scene.exposure`), the tone-mapping operator
(`Scene.toneMapping`, Khronos PBR Neutral by default), and the display EOTF. So
your shader outputs *linear* radiance (do not tone-map or gamma-encode), and
premultiplies rgb by alpha. Values above 1.0 are fine — the tone curve rolls
them off. When you sample an sRGB texture, linearize it first (`SRGBToLinear`,
or `pow(c, vec3(2.2))`). A `.fmat` material gets the premultiplied output for
free; `EvaluateLighting` (lit) and the unlit path both handle it.

The vertex `FrameInfo` block (model / camera matrices) is engine-bound and not
visible in the fragment stage; the world-space outputs already encode it.

---

# Building: the `buildMaterials` hook

`buildMaterials` (from `package:flutter_scene/build_hooks.dart`) preprocesses
each `.fmat`, emits GLSL, compiles it through `impellerc`, and writes two outputs
under `build/shaderbundles/`:

- `<bundleName>.shaderbundle` — the compiled Flutter GPU shader bundle.
- `<bundleName>.fmat.json` — the parameter sidecar the runtime needs.

`bundleName` defaults to `materials`. List both as assets (see the quick start).
The generated shaders `#include` flutter_scene's framework GLSL; the hook puts
that directory on `impellerc`'s include path for you, so nothing is copied into
your project.

You can call `buildMaterials` alongside `buildModels` and
`buildShaderBundleJson` in the same hook.

---

# Runtime: `PreprocessedMaterial` and `MaterialParameters`

Load the bundle (`gpu.ShaderLibrary.fromAsset`, or `loadShaderLibraryAsync` on
web) and the sidecar (`rootBundle.loadString` + `jsonDecode`), then construct a
`PreprocessedMaterial` per material entry (see the quick start). Set its
parameters through `material.parameters`, a `MaterialParameters`.

`MaterialParameters` is type-checked and name-addressed. You never compute std140
offsets: parameter types come from the sidecar, byte offsets come from the
compiled shader's reflection, and a wrong-typed value throws instead of silently
corrupting the uniform block. Three tiers share one backing buffer:

```dart
// Typed setters (the safe default):
params.setFloat('rim_width', 0.2);
params.setVec4('tint', Vector4(0.5, 0.3, 1.0, 1.0));
params.setColor('base_color', const Color(0xFF8844FF)); // sRGB-decoded if source_color
params.setTexture('base_color_texture', myTexture);

// Dynamic, dispatches on the declared type and throws on a mismatch:
params['rim_width'] = 0.2;        // ok
params['rim_width'] = Vector4.zero(); // throws: rim_width is float

// Raw escape hatch for hot loops (you own correctness here):
params.rawBlock.setFloat32(params.offsetOf('rim_width'), 0.2, Endian.host);
```

A `source_color` parameter is sRGB-decoded to linear on `setColor` (matching the
shader's `SRGBToLinear`), so authored colors look right. Setting an unknown name
or a wrong type throws an `ArgumentError` with a message naming the parameter and
its declared type.

For a `lit` material, set `PreprocessedMaterial.environment` to override the
scene-wide image-based-lighting environment for that material.

---

# `ShaderMaterial`: the low-level escape hatch

When you need a shader shape the `.fmat` format doesn't cover, write a complete
raw fragment shader and drive it with `ShaderMaterial`. You declare your own
uniform blocks and samplers and bind them by name, packing std140 yourself.

```glsl
// shaders/vertex_color.frag
uniform FragInfo { vec4 tint; } frag_info;

in vec4 v_color;
out vec4 frag_color;

void main() {
  frag_color = v_color * frag_info.tint;
}
```

Add it to a `flutter_gpu_shaders` manifest, compile it with
`buildShaderBundleJson` (add a `flutter_gpu_shaders: ^0.4.4` dependency), then:

```dart
final library = gpu.ShaderLibrary.fromAsset('build/shaderbundles/my_bundle.shaderbundle')!;
final material = ShaderMaterial(fragmentShader: library['VertexColorFragment']!);
material.setUniformBlockFromFloats('FragInfo', [1.0, 0.8, 0.4, 1.0]); // tint
node.mesh!.primitives[0].material = material;
```

A uniform block is bound by its **type** name (`FragInfo`), not its instance
name (`frag_info`). Set `ShaderMaterial.useEnvironment = true` to have the engine
bind `prefiltered_radiance` and `brdf_lut` if your shader declares them (the
diffuse-irradiance SH coefficients are not bound generically).

## std140 packing (raw `ShaderMaterial` only)

With `ShaderMaterial` you fill a single byte buffer per uniform block, and its
layout must match GLSL std140 exactly. (`.fmat` materials avoid this entirely —
the runtime packs from reflection.)

| Type | Size | Alignment | Notes |
| --- | --- | --- | --- |
| `bool` / `int` / `float` | 4 | 4 | |
| `vec2` | 8 | 8 | |
| `vec3` | 12 | **16** | pads to 16 |
| `vec4` | 16 | 16 | |
| `mat4` | 64 | 16 | four `vec4` columns |
| array element | varies | **16** | each element strides to a 16-byte boundary |

The footguns are mixing `vec3` and `float`: a `float` after a `vec3` fills the
`vec3`'s trailing pad, while a `vec3` after a `float` jumps to the next 16-byte
boundary. **When in doubt, declare blocks with `vec4`s and group trailing scalars
into `vec4`-aligned rows of four**, and the layout is unambiguous.

---

# Render state

A `.fmat` material declares render state in its `material` block: `culling`
(`back` / `front` / `none`) and `blending` (`opaque` / `alpha`). A
`ShaderMaterial` exposes `cullingMode`, `windingOrder`, and `isOpaqueOverride`
constructor fields.

Today `blending` is `opaque` (depth-write on, drawn in order) or `alpha`
(depth-write off, depth-sorted, premultiplied source-over). Additive/multiply
blend modes and per-material depth state are not configurable yet; they are
encoder-controlled. See [issue #22][issue22].

---

# Current state and what's next

The `.fmat` format, its preprocessor, the `buildMaterials` hook, and
`PreprocessedMaterial` are implemented. Remaining and in-flight work, tracked in
[issue #22][issue22]:

- **Hot reload.** Today you restart to pick up a shader edit (the build hook
  reruns on a restart when an input changes). The Flutter GPU shader hot-reload
  chain is landing upstream (flutter/flutter#186346); once it rolls into the
  Flutter SDK, editing a `.fmat` will hot reload in place with no app changes.
- **The `light()` hook** for a custom per-light BRDF (toon banding inside the
  engine light loop) is not implemented; use `unlit` for fully custom shading
  for now.
- **Typed codegen.** A future step will generate a typed Dart class per `.fmat`
  (compile-time-checked setters); today you use the name-based
  `MaterialParameters` API.
- **Additive/multiply blending and per-material depth state** are not yet
  configurable.
- **Vertex-shader customization** is not exposed; materials use the engine's
  standard vertex shaders.
- **An inspector** that surfaces the parameter hints as UI does not exist (the
  metadata is emitted for future tooling).

---

# Troubleshooting

**`gpu.ShaderLibrary.fromAsset` returns null.** The bundle is not in your app's
assets. Check that `build/shaderbundles/<name>.shaderbundle` (and, for `.fmat`,
the `.fmat.json` sidecar) are under `flutter.assets`, and that your
`hook/build.dart` ran. If a shader edit doesn't take effect, the build hook's
input-hash cache may be stale; follow CLAUDE.md Trap #3's reset recipe.

**A `MaterialParameters` setter throws.** You used an unknown parameter name or a
type that doesn't match the declared type. The message names the parameter and
its type. Check the `.fmat` `parameters` list.

**"Failed to find uniform slot X" (raw `ShaderMaterial`).** Flutter GPU couldn't
resolve a block or sampler name. A block is bound by its type name, not its
instance name. Note that an instance name must fold (case- and
underscore-insensitively) to the block name on the GLES backend
(flutter/flutter#186394); the `.fmat` emitter handles this for you.

**Wrong colors / black geometry (raw `ShaderMaterial`).** Almost always a std140
packing mismatch; declare blocks without `vec3` members to rule it out. With a
`.fmat` material this class of bug is gone (the runtime packs from reflection).

**Black or unlit model.** For a `lit` material, confirm the scene has an
environment and/or a directional light. For raw `ShaderMaterial`, check
`useEnvironment` and that all declared samplers are bound (unbound samplers read
garbage on some backends).

---

# See also

- `examples/smoke_render/materials/toon.fmat` and the `fmat_toon` scene in
  `examples/smoke_render/lib/smoke_scenes.dart`: a worked `.fmat` material
  rendered through `PreprocessedMaterial`.
- `examples/flutter_app/lib/example_toon.dart`: the raw-`ShaderMaterial` toon.
- `packages/flutter_scene/shaders/flutter_scene_standard.frag` and
  `material_lighting.glsl`: the engine's PBR shader and the lighting framework a
  `lit` material composes against.
- [Issue #22][issue22]: the custom-materials roadmap.

[issue22]: https://github.com/bdero/flutter_scene/issues/22
