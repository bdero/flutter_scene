# Custom materials in flutter_scene

flutter_scene gives you two ways to write a custom material:

1. **The `.fmat` declarative format (recommended).** You declare your
   parameters once and fill in a small `Surface()` function in GLSL. A build
   hook compiles it, and `PreprocessedMaterial` wires it up at runtime: typed,
   name-addressed parameters with no std140 packing by hand, and the engine's
   physically based lighting for free if you want it. This is the path most
   materials should use.
2. **`ShaderMaterial` (the low-level escape hatch).** You write complete raw
   GLSL, for the fragment stage and optionally the vertex stage too, declare
   your own uniform blocks and samplers, and bind them by name from Dart,
   packing std140 yourself. Use this when you need full control or a shader
   shape the `.fmat` format doesn't cover yet.

Both paths share the same engine contract (the vertex outputs your shader
receives and the color it must output), documented below. If you've used
Filament's `.mat` files or Godot's shaders, the `.fmat` model will feel
familiar; if you've used Three.js's `ShaderMaterial`, that's `ShaderMaterial`
here.

What is built and what is still missing is in [Current state and what's
next](#current-state-and-whats-next).

## Generated shader assets

Keep shader sources, `.fmat` files, and `.shaderbundle.json` source manifests in
version control. A `.shaderbundle.json` file only names shader entry points and
their source files. It is portable input to the build hook.

The generated `.shaderbundle` is different. It is compiled by the `impellerc`
that ships with the active Flutter engine and must be rebuilt by that same
toolchain, so the build hook writes it into `flutter_scene_generated/` and
gitignores it for you. Do not commit it or copy it anywhere else.

---

# The `.fmat` format

## Quick start

Author a material. A `.fmat` file has two blocks: a `material { }` metadata
block and a `fragment { }` GLSL block.

```
// assets/toon.fmat
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

Set the project up once from your app root.

```sh
dart run flutter_scene:init
```

The generated hook auto-discovers `assets/**/*.fmat` and compiles each material
into `flutter_scene_generated/`, alongside its `.fmat.json` sidecar and a runtime
index. `init` adds that directory to `flutter.assets` and gitignores its
contents.

Then load the material by its source path (relative to the package root, so
two materials that share a `name` in different directories do not collide):

```dart
import 'package:flutter_scene/scene.dart';

final toon = await loadFmatMaterial('assets/toon.fmat');
toon.parameters
  ..setColor('base_color', const Color(0xFFE0A030))
  ..setInt('band_count', 4)
  ..setTexture('base_color_texture', myTexture);

node.mesh!.primitives[0].material = toon;
```

Materials loaded this way **hot reload**. Render the scene with a `SceneView` and
editing `assets/toon.fmat` updates the running app in place
(see [Hot reload](#hot-reload)).

The bundle entry name and the sidecar key are the material's `name`
(`"Toon"` above). One `buildMaterials` call can compile several `.fmat` files
into one bundle; each becomes an entry keyed by its `name`.

## The `material` block

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `name` | string (required) | | The bundle entry name and sidecar key. |
| `shading_model` | `lit`, `unlit` | `lit` | `lit` runs the engine's PBR lighting; `unlit` outputs your color directly. |
| `blending` | `opaque`, `alpha`, `additive` | `opaque` | `alpha` and `additive` both route the material through the depth-sorted translucent pass. `additive` forces the output alpha to zero, so the destination is never darkened, only brightened; allowed on `lit` and `unlit` alike. |
| `culling` | `back`, `front`, `none` | `back` | Which faces are culled; `none` is double-sided. |
| `depth_write` | boolean | `false` | For `blending: alpha` surfaces, write depth in the color pass (self-sorting) and join the post-effect depth, so depth of field focuses on the surface instead of the backdrop seen through it. |
| `depth_test` | `less_equal`, `always` | `less_equal` | The depth test used in the translucent pass, so it needs `blending: alpha` or `additive`. `always` draws regardless of the opaque depth, for a projection volume whose own faces are not the surface being shaded (see Decals). |
| `parameters` | list of objects | `[]` | The material's parameters (see below). |
| `engine_inputs` | list of `scene_color`, `scene_depth`, `planar_reflection` | `[]` | Per-frame engine textures the shader samples (see below). Surface materials, `lit` or `unlit` (`planar_reflection` is lit only). |
| `scene_color_reach` | number | unbounded | How far past its own surface the shader samples, in local units. Lets readers whose screen rects are disjoint share one scene-color capture. Requires `engine_inputs`. |

## Engine inputs (`engine_inputs`)

A material can sample what the scene rendered behind it by declaring engine
inputs. The engine produces these only when a visible material asks, so they
cost nothing when unused:

- `scene_color` binds `scene_opaque_color`, a snapshot of the scene taken
  after the opaque phase (skybox + opaque draws) and before translucent
  draws. Requesting it splits the scene pass into two GPU passes with a
  resolve in between. Use it for refraction and translucent compositing.
- `scene_depth` binds `scene_depth`, the opaque geometry's linear
  (planar view-space) depth in world units. Requesting it forces the depth
  prepass (already produced when SSAO or reflections are on) and renders it at
  full resolution, so a depth-driven edge is not stair-stepped by a
  reduced-resolution occlusion chain. Use it for depth-fade absorption,
  shoreline foam, and soft-particle edges.
- `planar_reflection` binds the mirrored scene capture a
  `PlanarReflectorComponent` renders for the surface each frame, plus the
  capture's view-projection for projective sampling. Use it for mirrors and
  glossy floors; attach the component to the mirror node and it routes each
  frame's capture to the subtree's declaring materials. Unlike the other
  inputs this one costs a second scene render per reflection group per
  frame while the mirror is visible (CPU and draw calls scale with scene
  complexity, not just the capture resolution).

Declaring an input emits the sampler and these accessors into your shader:

```glsl
vec2  GetScreenUv();                  // this fragment's screen UV
vec3  GetSceneColor(vec2 uv_offset);  // opaque scene color behind the fragment
float GetSceneDepth(vec2 uv_offset);  // opaque linear depth behind the fragment
vec3  GetSceneWorldPosition(vec2 uv_offset);  // that surface's world position
float GetFragmentViewDepth();         // this fragment's own linear depth
float GetTime();                      // engine seconds, for animation
vec4  GetPlanarReflection();          // mirrored capture at this fragment
```

`GetSceneWorldPosition` unprojects the opaque surface behind the fragment (it
needs `scene_depth`), for contact softening, curved-surface thickness, and
projecting onto whatever is back there. When depth is unavailable or the camera
is not perspective it returns a point at the same huge depth `GetSceneDepth`
reports, so a reader fades out or falls outside its own volume rather than
landing on the fragment it was shading.

`GetPlanarReflection()` returns the mirrored scene color in rgb with `a` 1
when a capture is bound this draw and 0 otherwise (no reflector routed one,
or the draw is inside a capture, which never recurses). Blend toward the
environment reflection at `a == 0` so the surface degrades gracefully; the
worked mirror lives at `examples/flutter_app/assets/planar_mirror.fmat`.
Surfaces sampling a planar capture are effectively excluded from
screen-space reflections (their depth-prepass roughness reads fully rough),
so the two do not double up.

`GetFragmentViewDepth()` and `GetSceneDepth(vec2(0.0))` are directly
comparable: their difference is the world-space thickness between this
surface and whatever is behind it. When an input is unavailable for a frame
(for example a non-perspective camera produces no depth), the accessors
return inert values (black, a huge depth) so effects fade out instead of
misrendering.

Typical use, a translucent water surface:

```glsl
float thickness = GetSceneDepth(vec2(0.0)) - GetFragmentViewDepth();
float foam = 1.0 - smoothstep(0.0, foam_width, thickness);       // shoreline
vec3 refracted = GetSceneColor(normal_offset * refraction_strength);
vec3 absorbed = refracted * exp(-absorption * thickness);         // Beer-Lambert
```

Both `lit` and `unlit` surface materials may declare engine inputs (a sky may
not; it draws before any of them exist). An `unlit` reader is the right shape
for refraction and heat haze, where the background is already lit and nothing
wants shading:

```
material {
  name: "HeatHaze",
  shading_model: unlit,
  blending: alpha,
  engine_inputs: [scene_color],
  scene_color_reach: 0.5,
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetSceneColor(wobble), mask);
    PrepareMaterial(material);
  }
}
```

Budget note: the lit framework is close to Metal's 16-sampler limit, so with
both inputs declared keep the material's own samplers to two or fewer; prefer
in-shader procedural noise over noise textures. An `unlit` reader carries none
of the lighting samplers, so it has the whole budget and compiles to one bundle
entry instead of four.

## Sharing a scene-color capture (`scene_color_reach`)

Every material that reads `scene_color` needs a snapshot of the scene taken
before it draws. The engine takes one snapshot per batch of readers, and two
readers can share a batch only when neither samples into the other's screen
rect. It cannot know how far a shader samples, so by default a reader is
treated as sampling anywhere and gets its own snapshot (a full-viewport copy
plus a render pass each).

Declare the distance the shader actually samples past its own surface, in local
units, and disjoint readers collapse into one snapshot:

```
scene_color_reach: 0.25,
```

The engine scales it by the node's largest world-scale axis and inflates the
projected screen rect. Author it generously: too small a reach reads stale
color at the edges, while too large only costs a shared batch. Omit it when the
shader really can sample anywhere (a full-screen warp).

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
> full control.

---

# The `vertex` block

A surface material may add an optional `vertex { }` block to customize the
vertex stage (displace geometry, animate it, perturb normals, feed data to the
fragment). You write one function:

```glsl
vertex {
  void Vertex(inout VertexInputs vertex) {
    // Read and modify the vertex, in place.
  }
}
```

You write it once. The engine runs it on every mesh type and pass (static,
skinned, and the position-only depth/shadow pass); you never branch on whether
the mesh is skinned. Skinning is already applied when `Vertex()` runs, so the
fields below mean the same thing everywhere.

`VertexInputs` is:

```glsl
struct VertexInputs {
  vec3 position;        // object space (post-skinning on a skinned mesh)
  vec3 normal;          // object space
  vec4 tangent;         // object-space direction and bitangent sign
  vec3 world_position;  // world space, after the model/skin transform
  vec3 world_normal;    // world space
  vec4 world_tangent;   // world-space direction and bitangent sign
  vec2 uv;
  vec2 uv1;
  vec4 color;
  vec3 camera_position; // read-only, world space
};
```

Write `world_position` to displace geometry (the engine projects it to clip
space after `Vertex()` returns) and `world_normal` to change the shading normal.
The `material_params.*` values are available in `Vertex()` just as in
`Surface()`, so one parameter drives both stages.

```glsl
// A world curve: bend geometry down with distance from the camera.
void Vertex(inout VertexInputs vertex) {
  vec3 rel = vertex.world_position - vertex.camera_position;
  vertex.world_position.y -= material_params.curvature * dot(rel.xz, rel.xz);
}
```

**Derive, don't replace.** Prefer perturbing the provided value
(`vertex.world_normal = normalize(vertex.world_normal + delta)`) over assigning
a fresh one. It keeps the mesh normal meaningful, and it reads the mesh input so
the input can't be optimized away. (The engine inserts a keep-alive so a full
replacement still compiles, but deriving is the better habit.)

## Custom varyings (vertex to fragment)

Declare named interpolants in a `varyings` list; `Vertex()` writes them and
`Surface()` reads them, by name. The emitter generates the matching `out`/`in`
declarations, so you never pick a location.

```
material {
  name: "Curve",
  varyings: [ { type: float, name: curve_fade } ],   // float/vec2/vec3/vec4
}
vertex {
  void Vertex(inout VertexInputs vertex) { /* ... */ curve_fade = ...; }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color.rgb *= mix(1.0, 0.4, curve_fade);
    PrepareMaterial(material);
  }
}
```

## Custom vertex attributes (mesh to vertex)

Declare named per-vertex inputs in an `attributes` list; the mesh supplies the
data and `Vertex()` reads each by name.

```
material {
  name: "Waves",
  attributes: [ { type: float, name: phase } ],   // float/vec2/vec3/vec4
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += 0.2 * sin(phase);
  }
}
```

Supply the data on the geometry, one value per vertex, matching by name:

```dart
geometry.setCustomAttribute('phase', phaseValues, components: 1);
```

Custom attributes work on both static and skinned meshes; attaching one to a
skinned mesh switches its vertex layout to a described one, since reflection
cannot know which slot the stream was bound to (`Geometry.setCustomAttribute`).
The depth/shadow pass fetches only position, so an attribute reads zero there:
a displacement driven by a custom attribute is not reflected in the shadow,
while one driven by `world_position`/a parameter is (world position is
available in every pass).

## Custom instance attributes (instance to vertex and fragment)

Declare named per-instance inputs in an `instance_attributes` list; each
instance of an `InstancedMesh` supplies its own values.

```
material {
  name: "Foliage",
  instance_attributes: [                 // float/vec2/vec3/vec4
    { type: float, name: wobble },
    { type: vec3, name: tint_shift },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += 0.1 * sin(instance_wobble);
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color.rgb *= GetInstanceTintShift();
    PrepareMaterial(material);
  }
}
```

`Vertex()` reads the attribute as `instance_<name>`, and `Surface()` reads it
through the generated `GetInstance<Name>()` accessor, alongside the engine's
other `Get*()` inputs. The interpolant is only emitted for the attributes the
fragment body actually calls, so vertex-only attributes cost no varying slot.

Set the values per instance:

```dart
final index = mesh.addInstance(transform);
mesh.setInstanceAttribute(index, 'wobble', random.nextDouble() * 6.28);
mesh.setInstanceAttribute(index, 'tint_shift', Vector3(1.0, 0.9, 0.8));
```

`setInstanceAttributes(index, packed)` writes them all at once for hot loops,
in declaration order.

The rules:

- Declared attributes append, in declaration order, to the instance-rate vertex
  buffer, after the 80-byte block holding the model transform and instance
  color.
- Floats pack tightly at 4 bytes each, **but a `vec3` occupies 16 bytes**, so
  the attribute after one starts 16 bytes on, not 12. The bulk
  `setInstanceAttributes` path takes that pad float too.
- A declaring material requires a `vertex { }` block (the attributes are bound
  to its generated vertex variants), and is a surface material only.
- `mat3` and `mat4` are rejected; a matrix spans several instance-rate inputs.
  Pass its columns as separate `vec4` attributes.
- An instance whose attributes are never set draws with zeros, and so does a
  non-instanced draw of the same material (a single node has nowhere to take
  per-instance values from).
- The skinned and depth/shadow variants bind no instance attribute data, so
  they read zero there, matching per-vertex custom attributes.
- A declaring material **opts out of automatic cross-node batching**. That
  optimization synthesizes one instance per node, and a node carries no
  attribute values; each instanced mesh draws from its own data instead.
- The geometry must use the engine's instance-rate record. A geometry with its
  own instance buffer (a billboard batch) fails at draw setup rather than
  reading the wrong bytes.

---

# Built-in noise, `#include <noise.glsl>`

Any `fragment`, `vertex`, or `sky` block can opt into the engine's noise
library by starting the block with an include:

```glsl
fragment {
#include <noise.glsl>

  void Surface(inout MaterialInputs material) {
    float n = NoiseSimplex3(GetWorldPosition() * 4.0, 1337);
    ...
  }
}
```

The library is a GPU port of the FastNoiseLite implementation behind
`package:flutter_scene/noise.dart`, and the two are kept in lockstep, the
same field sampled on the CPU and evaluated in a shader agree. Functions
(each also in a smoother `2S`/`3S` OpenSimplex2S flavor):

```glsl
float NoiseSimplex2(vec2 p, int seed);   // one octave, roughly [-1, 1]
float NoiseSimplex3(vec3 p, int seed);
float NoisePerlin2(vec2 p, int seed);    // also NoisePerlin3
float NoiseValue2(vec2 p, int seed);     // also NoiseValue3
float NoiseCellular2(vec2 p, int seed, int distanceFunction, int returnType, float jitter);
float NoiseFbm2(vec2 p, int seed, int octaves, float lacunarity, float gain);
float NoiseRidged2(vec2 p, int seed, int octaves, float lacunarity, float gain);
float NoisePingPong2(vec2 p, int seed, int octaves, float lacunarity, float gain, float strength);
vec2  NoiseDomainWarp2(vec2 p, int seed, float amp);  // also NoiseDomainWarp3
vec3  NoiseCurl3(vec3 p, int seed, float epsilon);    // divergence-free, for advection
int   NoiseHash2(ivec2 cell, int seed);  // hashed lattice cell, full int32
```

Cellular distance functions and return types are int constants
(`kNoiseCellularEuclidean`/`EuclideanSq`/`Manhattan`/`Hybrid` and
`kNoiseCellularCellValue`/`Distance`/`Distance2`/`Distance2Add`/`Sub`/`Mul`/
`Div`) matching the Dart enums in declaration order. The GLSL domain warp
covers the default OpenSimplex2 type without warp fractals; the reduced and
basic-grid types and warp fractals are CPU-only for now.

Frequency is applied by the caller (scale `p` before the call), so
`FastNoiseLite(seed: s, frequency: f).getNoise2(x, y)` on the CPU corresponds
to `NoiseSimplex2(vec2(x, y) * f, s)` in the shader. The agreement contract
has two tiers. `NoiseHash2`/`NoiseHash3` are pure 32-bit integer math and
match the Dart `noiseHash2`/`noiseHash3` bit for bit on every backend, use
them for decisions that must never disagree. The float functions match the
CPU within a small tolerance (float32 rounding differs per GPU), enforced by
a per-backend parity test in CI; do not re-derive a hard threshold from float
noise on both sides, make the decision once and share it.

The GLSL noise is correct on every backend, including the web (WebGL2). The
Dart `FastNoiseLite` is currently correct only on native, its 32-bit integer
hash overflows on the web (where Dart `int` is a JavaScript double), so on the
web prefer the GLSL side or a `bakeNoiseTexture` built at build time or in a
native isolate. A web-safe Dart multiply is a planned follow-up.

`noise.glsl` carries the gradient and cell-vector lookup tables (the cellular
functions add about 1500 float constants), so a material that uses many noise
functions compiles to a large shader. That is fine on real GPU drivers, but a
software compiler (a device emulator, some headless CI) can run out of memory
on it; a material that uses one or two functions stays small. Bake to a
texture when a single field would do.

---

# Barycentric wireframes, `#include <wireframe.glsl>`

A single-pass fragment wireframe reads a per-corner barycentric coordinate
and measures screen-space distance to the nearest edge with `fwidth`. The
attribute comes from `MeshData.unweld(attributes: {UnweldAttribute.barycentric})`,
which triples the mesh into an unindexed soup and writes `(1,0,0)`/`(0,1,0)`/
`(0,0,1)` per corner under the name `barycentric`.

`unweld` also assigns each corner the flat face normal by default (correct
for shattering into shards, wrong for a surface that should keep shading
smooth). Pass `keepVertexNormals: true` to carry the source vertex normals
through instead:

```dart
final wired = source.unweld(
  attributes: {UnweldAttribute.barycentric},
  keepVertexNormals: true,
);
primitive.geometry = MeshGeometry.fromMeshData(wired);
```

`wireframe.glsl` is an opt-in include, like `noise.glsl`:

```glsl
float WireframeCoverage(vec3 bary, float width_px); // 1 on an edge, 0 inside
float EdgeDistancePixels(vec3 bary);                // distance to nearest edge, in px
```

A worked material, a cyan wire over an otherwise normal lit surface:

```
material {
  name: "Wireframe",
  shading_model: lit,
  attributes: [ { type: vec3, name: barycentric } ],
  varyings: [ { type: vec3, name: bary } ],
  parameters: [
    { type: vec4, name: wire_color, hint: source_color, default: [0.25, 0.85, 1.0, 1] },
    { type: float, name: wire_width, hint: range(0.5, 6, 0.1), default: 1.4 },
  ],
}

vertex {
  void Vertex(inout VertexInputs vertex) { bary = barycentric; }
}

fragment {
#include <wireframe.glsl>

  void Surface(inout MaterialInputs material) {
    float coverage = WireframeCoverage(bary, material_params.wire_width);
    material.base_color.rgb = mix(material.base_color.rgb,
                                   material_params.wire_color.rgb, coverage);
    material.emissive = material_params.wire_color.rgb * coverage;
    PrepareMaterial(material);
  }
}
```

No loops, no early returns, no integer math, so it is portable to every
backend without further care.

---

# Decals

A decal paints a mark (a scorch, a melt glow, a sticker) onto surfaces that are
already drawn. Two tiers, depending on how flat the receiver is.

## Mesh decals, for a flat receiver

A translucent quad parented just above the receiving surface, with a nonzero
`Material.depthBias` so it wins the depth comparison without moving:

```dart
final mark = Node(mesh: Mesh(PlaneGeometry(width: 2, depth: 2), scorch))
  ..position = impactPoint;
scorch.depthBias = 0.02;
```

The material is `blending: alpha` with the mark's coverage in `base_color.a`.
This is the whole technique, and it needs no engine support. It is correct on
flat ground and wrong on anything curved or stepped, where the quad floats over
or sinks into the receiver.

## Projected box decals, for any receiver

A `DecalNode` draws a box; each of its fragments unprojects the opaque surface
behind it, transforms that world point into the box's local space, discards
outside the box, and shades what is left. The mark conforms to whatever it lands
on, so it follows terrain, steps, and props.

Unprojection needs the opaque depth and a perspective camera, so a decal draws
nothing under an `OrthographicCamera`.

```dart
final decal = DecalNode(material: await loadFmatMaterial('assets/scorch_decal.fmat'))
  ..project(point: impactPoint, normal: groundNormal, size: 2.4, rotation: rng.nextDouble() * pi);
scene.add(decal);

// Later, fading it out.
decal.fade = 1.0 - age / lifetime;
if (age >= lifetime) scene.remove(decal);
```

`project` centers the box on `point` with its local Y along `normal`, spanning
`size` world units across and `depth` along the normal, and the node keeps the
material's `decal_inverse` (world to unit box) and `decal_fade` parameters in
sync with its world transform, so a placed decal can still be moved or
reparented. Names the material does not declare are skipped.

The material carries the projection. Three keys make a box behave as a volume
rather than as geometry: `culling: front` draws the back faces, so the decal
survives the camera entering the box; `depth_test: always` keeps those faces
from being rejected by the surface they paint (they sit behind it); and
`engine_inputs: [scene_depth]` supplies `GetSceneWorldPosition`.

```
material {
  name: "ScorchDecal",
  shading_model: unlit,
  blending: alpha,
  culling: front,
  depth_test: always,
  engine_inputs: [scene_depth],
  scene_color_reach: 0.0,

  parameters: [
    { type: mat4, name: decal_inverse },
    { type: float, name: decal_fade, hint: range(0.0, 1.0, 0.01), default: 1.0 },
    { type: sampler2d, name: decal_texture, hint: default_transparent },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec3 local = (material_params.decal_inverse *
                  vec4(GetSceneWorldPosition(vec2(0.0)), 1.0)).xyz;
    vec3 outside = step(vec3(0.5), abs(local));
    if (max(outside.x, max(outside.y, outside.z)) > 0.0) {
      discard;
    }
    float coverage = texture(decal_texture, local.xz + 0.5).a *
                     material_params.decal_fade;
    // Scorching darkens, which premultiplied source-over gives directly.
    material.base_color = vec4(0.0, 0.0, 0.0, coverage);
    PrepareMaterial(material);
  }
}
```

The unit box spans -0.5 to 0.5 on each axis, and the texture is sampled across
its local XZ. A melt glow is the same material with `blending: additive` and a
lit color instead of black. The whole thing is an ordinary translucent draw, so
it sorts with everything else and costs one draw.

Known limitations:

- **One material instance per decal**, since the projection is a `mat4`
  parameter. Per-instance custom attributes are not exposed, so a hundred
  simultaneous decals are a hundred draws; pool a fixed set of `DecalNode`s to
  keep the count bounded.
- **The decal's normal is the box's, not the receiving surface's.** Correct for
  a mark projected straight down onto ground, wrong for one that should wrap a
  corner's shading.
- **Tinted multiply is not expressible.** Darken-to-black and additive both work
  in the existing blend model; a brown scorch that multiplies the receiver's
  color needs a multiply blend mode, which does not exist. The workaround is to
  declare `scene_color` too and output the product, at the cost of a capture
  batch.
- **Decals project onto opaque geometry only**, because the depth prepass is
  opaque-only. Nothing paints onto glass.

Give `depth` enough room to absorb the depth precision at the decal's distance
from the camera: the unprojected position is compared against the box in world
space, so a thin box far from the camera drops fragments.

# The engine contract (both paths)

flutter_scene's engine vertex shaders (`UnskinnedVertex` and `SkinnedVertex`)
emit the same standard outputs. The `.fmat` accessors wrap these; a raw
`ShaderMaterial` declares them directly:

```glsl
in vec3 v_position;        // world space
in vec3 v_normal;          // world space, not necessarily unit length
in vec3 v_viewvector;      // camera_position - vertex_position
in vec2 v_texture_coords;
in vec2 v_texture_coords_1;
in vec4 v_color;           // per-vertex color, white when the model has none
in vec4 v_tangent;         // world-space tangent and bitangent sign
```

The model scale is no longer one of the interpolated outputs (lit materials
read it from `FragInfo.model_scale`, which the `.fmat` `GetModelScale()`
accessor wraps). A raw shader pair that needs it computes it from the model
transform its vertex stage already receives and passes it through its own
varying.

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

# Portable shader rules

flutter_scene runs your GLSL on Metal, Vulkan, OpenGL ES 3.0, WebGL2, and
Direct3D 11 (through a GLES-to-HLSL translation on Windows). The dialect is
GLSL ES 3.00. A shader that follows these rules works on every backend on the
first try; a shader that breaks one typically works on your machine and fails
on someone else's, so treat them as hard requirements rather than advice.

**Bound loops by a compile-time constant and break inside.** A loop condition
that depends on a uniform is rejected by conforming GLES compilers. Write

```glsl
for (int i = 0; i < MAX_STEPS; i++) {  // MAX_STEPS is a #define or const
  if (i >= step_count) break;          // step_count may be a uniform
  ...
}
```

**Never `return` early from inside a loop**, and prefer a single `return` at
the end of any function that contains a loop. A mid-loop return compiles into
a construct that crashes the Direct3D shader compiler outright, so the
failure is an app crash on Windows, not an artifact. Accumulate into a local
and return it once.

**Build bit masks with left shifts.** Right-shifting a uint whose high bit is
set (`0xFFFFFFFFu >> n`) executes as a signed arithmetic shift on the
Direct3D path and smears the sign bit. A low mask of `count` bits is

```glsl
uint mask = count >= 32u ? 0xFFFFFFFFu : (1u << count) - 1u;
```

**Stay inside the ES 3.00 toolbox.** `bitCount()`, `bitfieldExtract()`, and
`textureGather()` do not exist at this floor (WebGL2 never gets them). The
texture vocabulary is `texture`, `texelFetch`, `textureLod`, and
`textureSize`. Popcounts and gathers are written by hand.

**Budget 16 texture units, counting both stages.** Minimum-spec GLES and
Direct3D 11 expose 16 combined samplers. The engine's lit framework already
binds 15 in the fragment stage, and skinned meshes bind one more in the
vertex stage, so a lit material has no free sampler slots on minimum-spec
backends; sampler-heavy work belongs in `unlit` materials or packed into
fewer textures. A sampler over budget renders correctly on desktop GL and
Metal and fails on Windows and mobile GLES.

**Reference every resource you declare.** If a declared sampler or uniform
becomes unused, dead-code elimination strips it while the runtime reflection
still lists it, which crashes at bind time on some backends. Either use it or
remove the declaration. In a `.fmat` vertex hook, derive your outputs from
the mesh inputs rather than replacing them wholesale, or the compiler strips
the vertex attribute out from under the mesh.

**Sample float32 textures as nearest.** Linear filtering of fp32 textures is
an optional extension that software rasterizers and some mobile drivers
lack. Data and depth textures are sampled nearest; interpolate in the shader
if needed.

**Declare `highp` on samplers that carry depth or data.** Samplers default to
`mediump`, and mobile GPUs honor it (desktop drivers ignore it, which hides
the bug). fp16 precision quantizes depth and packed data hard enough to break
comparisons that work everywhere else:

```glsl
uniform highp sampler2D my_data_texture;
```

**Pack into one render target.** There is no multiple-render-target support
on GLES or the web, and single-channel and float formats are not universally
renderable. Post-process style work packs its outputs into the channels of
one RGBA8 or RGBA16F target.

---

# Building: the `buildMaterials` hook

`buildMaterials` (from `package:flutter_scene/build_hooks.dart`) preprocesses
each `.fmat`, emits GLSL, compiles it through `impellerc`, and generates these
managed outputs:

- `<bundleName>.shaderbundle` — the compiled Flutter GPU shader bundle.
- `<bundleName>.fmat.json` — the parameter sidecar the runtime needs.
- `<bundleName>.index.json` — the source-path index used by
  `loadFmatMaterial`.

`bundleName` defaults to `materials`. If `materials` is omitted,
`buildMaterials` discovers `assets/**/*.fmat` automatically; pass
`discoveryRoot` to search a directory other than `assets/`.

`assetMode` defaults to `MaterialAssetMode.generatedTree`, which is what
`dart run flutter_scene:init` installs and what every app should use. The two
Dart data assets modes are an advanced opt-in, for a package that ships materials
to its own consumers.

The generated shaders `#include` flutter_scene's framework GLSL; the hook puts
that directory on `impellerc`'s include path for you, so nothing is copied into
your project.

You can call `buildMaterials` alongside `buildScenes` and
`buildShaderBundleJson` in the same hook.

---

# Runtime: `PreprocessedMaterial` and `MaterialParameters`

Load each material by its checked-in source path with `loadFmatMaterial`, as in
the quick start. The registry resolves its generated bundle, sidecar, and entry
from the DataAsset index. Set its parameters through `material.parameters`, a
`MaterialParameters`.

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

## Broadcasting a parameter to many materials, `MaterialGroup`

A parameter lives per `PreprocessedMaterial` instance, so driving it across
every affected object (every enemy caught in a blast radius, say) means
setting it on each one yourself. `MaterialGroup` does the broadcast:

```dart
final affected = MaterialGroup(enemiesInRadius.map((e) => e.pulseMaterial));
// or, to grab every PreprocessedMaterial under a node:
final affected = MaterialGroup.of(sceneRoot);

// Once per frame.
affected
  ..setVec4('wave_origin', origin)
  ..setFloat('wave_radius', radius);
```

Unlike `MaterialParameters`, which throws on an unknown name, `MaterialGroup`
skips a member that doesn't declare the parameter, so one group can span a
heterogeneous set of materials.

---

# `ShaderMaterial`: the low-level escape hatch

When you need a shader shape the `.fmat` format doesn't cover, write a complete
raw fragment shader and drive it with `ShaderMaterial`. You declare your own
uniform blocks and samplers and bind them by name, packing std140 yourself.

`ShaderMaterial` covers both stages. Pass only a `fragmentShader` and the
engine's vertex shader runs, which is the common case. Pass a `vertexShader`
too and the material owns the whole pipeline; see [Raw vertex
shaders](#raw-vertex-shaders) for the contract yours has to meet.

```glsl
// shaders/vertex_color.frag
uniform FragInfo { vec4 tint; } frag_info;

in vec4 v_color;
out vec4 frag_color;

void main() {
  frag_color = v_color * frag_info.tint;
}
```

Add it to a checked-in `flutter_gpu_shaders` source manifest and compile it as a
required DataAsset from `hook/build.dart`.

```dart
import 'package:flutter_gpu_shaders/build.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) {
  build(args, (config, output) async {
    await buildShaderBundleJson(
      buildInput: config,
      buildOutput: output,
      manifestFileName: 'shaders/my_bundle.shaderbundle.json',
      assetMode: ShaderBundleAssetMode.dataAssetsRequired,
    );
  });
}
```

Load the generated DataAsset using its Flutter asset key.

```dart
final library = (await gpu.loadShaderLibraryAsync(
  'packages/my_app/flutter_gpu_shaders/shaderbundles/'
  'my_bundle.shaderbundle',
))!;
final material = ShaderMaterial(fragmentShader: library['VertexColorFragment']!);
material.setUniformBlockFromFloats('FragInfo', [1.0, 0.8, 0.4, 1.0]); // tint
node.mesh!.primitives[0].material = material;
```

A uniform block is bound by its **type** name (`FragInfo`), not its instance
name (`frag_info`). Set `ShaderMaterial.useEnvironment = true` to have the engine
bind `prefiltered_radiance` and `brdf_lut` if your shader declares them (the
diffuse-irradiance SH coefficients are not bound generically).

### The prefiltered radiance layout

Backends differ in the radiance layout they can build, a roughness-mip cubemap
where the engine can render into mip levels and a 2D equirect elsewhere, so
`prefiltered_radiance` is declared as `RadianceSampler` (from `texture.glsl`),
which is `samplerCube` under `FLUTTER_SCENE_RADIANCE_CUBE` and `sampler2D`
without it. Declaring one sampler instead of one per layout keeps a dead
sampler off the per-stage texture-unit budget, which the lit framework sits
close to.

A `.fmat` material needs no action; the build hook emits both variants and the
runtime picks the one matching the bound environment. A raw `ShaderMaterial`
that samples the environment has to build both itself, adding a second bundle
entry that defines `FLUTTER_SCENE_RADIANCE_CUBE` ahead of its includes, and
pass it as `radianceCubeFragmentShader`:

```dart
final material = ShaderMaterial(
  fragmentShader: library['MyEffect']!,
  radianceCubeFragmentShader: library['MyEffectCube']!,
  useEnvironment: true,
);
```

Sample through `SampleRadianceEnv(prefiltered_radiance, direction, roughness)`
so the same source compiles either way. Without the cube variant the material
samples a 2D slot on a backend that binds a cubemap, and reflections come out
wrong.

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

# Raw vertex shaders

A `ShaderMaterial` can supply the vertex shader as well as the fragment one.
The engine's standard vertex shader then does not run, so your shader owns
everything it used to provide.

```dart
final material = ShaderMaterial(
  vertexShader: library['RippleVertex']!,
  fragmentShader: library['RippleFragment']!,
);
material.setUniformBlockFromFloats('TintInfo', [...]);            // fragment
material.setUniformBlock('RippleInfo', bytes,
    stage: ShaderStage.vertex);                                    // vertex
```

Uniform blocks and textures are set by name on either stage, chosen with
`ShaderStage`. A block declared in both stages is two bindings, so set it twice.

## The contract

For an unskinned mesh, the engine binds these and your shader declares all of
the fixed inputs:

```glsl
uniform FrameInfo {
  mat4 camera_transform;
  vec3 camera_position;
} frame_info;

in vec3 position;
in vec3 normal;
in vec2 texture_coords;
in vec2 texture_coords_1;
in vec4 color;
in vec4 tangent;

// Instance-rate model matrix columns, bound in the slot after the vertex
// streams. A non-instanced draw gets a single-element buffer.
in vec4 model_transform_0;
in vec4 model_transform_1;
in vec4 model_transform_2;
in vec4 model_transform_3;
```

The color pass adds `in vec4 instance_color` after those columns, for an 80-byte
instance record. A `.fmat` declaring `instance_attributes` appends its own
inputs after that record (see
[Custom instance attributes](#custom-instance-attributes-instance-to-vertex-and-fragment));
a raw `ShaderMaterial` has no such declaration and always sees the fixed record.

Your shader writes `gl_Position` and the standard outputs the fragment stage reads
(`v_position`, `v_normal`, `v_viewvector`, `v_texture_coords`,
`v_texture_coords_1`, `v_color`, `v_tangent`), plus any of
your own varyings. A skinned mesh
instead takes its model transform,
`enable_skinning`, and `joint_texture_size` in `FrameInfo`, and adds the
`joints` and `weights` attributes and a `joints_texture` sampler.

## Mesh kinds and passes

A vertex shader is registered per mesh kind, so one material can customize
static meshes and leave others to the engine:

```dart
material.setVertexShader(skinnedShader, variant: MeshVariant.skinned);
material.setVertexShader(depthShader, variant: MeshVariant.depth);
```

`MeshVariant.depth` is the position-only pass that draws shadow maps and the
depth prepass. Supply it when your vertex stage moves geometry, or the shadow
keeps the undisplaced shape.

Any variant you leave unset falls back to the engine's shader for that mesh
kind, which is what makes customizing only static meshes a one-shader job. The
catch is that the engine's shader writes only the engine varyings. If your
fragment shader reads a varying your own vertex shader writes, the fallback
pairs it with a vertex shader that never writes it, and pipeline creation fails
on the backend. A debug build warns and names the missing variant when this is
about to happen. So either supply every variant your scene draws, or keep the
fragment shader to the engine varyings.

## Your own vertex layout

By default your shader is fed the engine's standard layout, which is what the
declarations above describe. To feed it something else (extra channels, a
packed format, or fewer attributes), describe the layout and bind buffers to
match:

```dart
geometry.setVertexLayout(
  VertexLayoutDescriptor(buffers: [
    VertexBufferDescriptor(
      strideInBytes: 20,
      attributes: [
        VertexAttributeDescriptor(name: 'position', format: VertexFormat.float32x3),
        VertexAttributeDescriptor(
            name: 'uv2', format: VertexFormat.float32x2, offsetInBytes: 12),
      ],
    ),
  ]),
  bindsModelTransform: false,
);
```

Attributes match the shader by name, so extra UV sets and per-vertex data are
ordinary channels rather than special cases. Pass `bindsModelTransform: false`
when your shader takes the model transform some other way than the instance-rate
slot, so the encoder leaves that slot alone.

For a single extra channel alongside the standard vertex, `setCustomAttribute`
is simpler and needs no layout (it also works on skinned meshes):

```dart
geometry.setCustomAttribute('phase', phaseValues, components: 1);
```

See `examples/flutter_app/lib/example_raw_shader.dart` with
`shaders/example_ripple.vert` and `.frag` for a worked pair.

---

# Engine inputs on a raw `ShaderMaterial`

A `ShaderMaterial` can declare the same per-frame engine textures a `.fmat`
material asks for with `engine_inputs:`, which is what a translucent surface
needs to refract and to measure its own thickness.

```dart
final water = ShaderMaterial(
  vertexShader: library['WaterVertex']!,
  fragmentShader: library['WaterFragment']!,
  isOpaqueOverride: false,
  sceneInputs: const {RenderInput.opaqueSceneColor, RenderInput.depth},
);
```

`RenderInput.opaqueSceneColor` binds `scene_opaque_color`, the scene composed
behind this draw. `RenderInput.depth` binds `scene_depth`, the opaque
geometry's linear view-space depth in world units.
`RenderInput.filteredSceneColor` adds the roughness-filtered atlas as
`scene_filtered_color` for rough refraction, and implies the snapshot it is
built from. Those three are the whole set a material may declare; the rest of
`RenderInput` belongs to `CustomRenderPass.inputs` and is rejected here.

In the shader, `#include <scene_inputs.glsl>` and declare which inputs you took
so only those samplers exist:

```glsl
#define FLUTTER_SCENE_SCENE_COLOR
#define FLUTTER_SCENE_SCENE_DEPTH
#include <scene_inputs.glsl>

// v_viewvector is the engine vertex shaders' output; a material with its own
// vertex stage passes whatever it computed.
float thickness = GetSceneDepth(vec2(0.0)) - GetFragmentViewDepth(v_viewvector);
vec3 refracted = GetSceneColor(normal_offset * refraction_strength);
```

The header is the same contract the `.fmat` accessors give you, and it exists
for a reason worth stating. An input is produced only on the frames a visible
material asks for it, and it can go missing anyway (a non-perspective camera
produces no depth), so every read is gated: `GetSceneColor` returns black and
`GetSceneDepth` returns a huge depth when the input is absent, which fades an
effect out. Sampling the sampler directly instead reads an opaque-white
placeholder on those frames, which is a blown-out image rather than an inert
one. The header also derives the screen UV from a `SceneInputInfo` block the
engine binds, since a raw shader has no other way to learn the render-target
size (it is the widget size times the device pixel ratio times
`Scene.renderScale`, and the material draws into the scene color target rather
than into the widget).

`buildTargetShaderBundleJson` puts flutter_scene's `shaders/` on the include
path, so the `#include` resolves with no setup. It also reaches `noise.glsl`
and the rest of the engine's GLSL.

**Keep the defines and the Dart set in step.** They are two declarations of one
thing, and disagreeing is not a no-op. A sampler the shader declares but never
samples is eliminated by the compiler while the runtime reflection still lists
it, and the bind then writes into a slot that does not exist, which fails at
draw time. Check what a bundle really compiled with:

```sh
strings my.shaderbundle | grep -oE "[a-z_0-9]+ \[\[texture\([0-9]+\)\]\]" | sort -u
```

`sceneInputs` is settable after construction, and assigning an equal set is not
a change. Treat it as a declaration rather than a per-frame knob, though.
Producing an input is not free: `RenderInput.depth` forces the depth prepass,
and the scene-color inputs split the scene pass around every screen-reading
layer. Any non-empty set also moves the frame off its cached whole-scene
summary onto a per-view collection, and each change re-summarizes the scene.

Unlike the `.fmat` path this is available on `unlit` shading, and a raw
material pays none of the lit framework's eight engine samplers, so the
sampler budget has room for the two inputs.

---

# Render state

A `.fmat` material declares render state in its `material` block: `culling`
(`back`/`front`/`none`) and `blending` (`opaque`/`alpha`/`additive`). A
`ShaderMaterial` exposes `cullingMode`, `windingOrder`, and `isOpaqueOverride`
constructor fields.

Today `blending` is `opaque` (depth-write on, drawn in order), `alpha`
(depth-write off, depth-sorted, premultiplied source-over), or `additive`
(depth-write off, depth-sorted, output alpha forced to zero so the destination
is only ever brightened). A translucent material also picks its depth write
(`depth_write`) and its depth test (`depth_test`). Multiply blending is not
configurable; it is encoder-controlled.

---

# Hot reload

A `.fmat` material loaded with `loadFmatMaterial` hot reloads in place. Render the scene through a `SceneView`; on hot reload it asks
the framework's hot-reload coordinator to refresh any `.fmat` whose source
changed. Every part of a `.fmat` reloads with no app-side code and no restart:

- **Render state** (`culling`, `blending`, `shading_model`) and **parameter
  defaults** — re-read from the regenerated sidecar and applied to the live
  material. A value you set at runtime (`setColor`, etc.) is preserved; an
  unset parameter takes the edited default.
- **The GLSL body** (`Surface()` and the `vertex { }` block's `Vertex()`) — the
  changed `.shaderbundle` is reloaded in place via `ShaderLibrary.reinitialize`
  and the affected render pipelines are rebuilt, so a fragment or vertex edit
  shows up live. (Changing the `varyings` / `attributes` /
  `instance_attributes` lists changes the generated shaders' structure; that
  reloads too, but a new custom attribute only takes effect once the geometry
  supplies it via `setCustomAttribute`, and an edited `instance_attributes`
  list drops the instanced mesh's packed values, so set them again.)

Requirements: the build hook `dart run flutter_scene:init` installs, so a `.fmat`
edit re-runs it and re-syncs the regenerated assets, and a `SceneView` (or its
`reassemble` hook) displaying the scene. A `.fmat` edit re-runs the build hook, so the reload takes
a moment while the shader recompiles. Hot reload is debug-only and tree-shaken
from release builds. (`ShaderMaterial`, the raw escape hatch below, does not
participate; it carries no sidecar.)

---

# Current state and what's next

The `.fmat` format, its preprocessor, the `buildMaterials` hook,
`PreprocessedMaterial`, the `vertex { }` stage (with custom varyings and
attributes), and hot reload are implemented. Remaining and in-flight work:

- **The `light()` hook** for a custom per-light BRDF (toon banding inside the
  engine light loop) is not implemented; use `unlit` for fully custom shading
  for now.
- **Typed codegen.** A future step will generate a typed Dart class per `.fmat`
  (compile-time-checked setters); today you use the name-based
  `MaterialParameters` API.
- **Multiply blending** is not yet configurable (`blending: additive` is,
  alongside `opaque`/`alpha`, and `depth_write`/`depth_test` cover the
  translucent depth state).
- **Per-instance custom attributes** work on unskinned instanced meshes, but a
  declaring material opts out of automatic cross-node batching and reads zero in
  the skinned and depth/shadow variants.
- **An inspector** that surfaces the parameter hints as UI does not exist (the
  metadata is emitted for future tooling).

---

# Troubleshooting

**`loadShaderLibraryAsync` returns null.** Resolve the key with
`resolveShaderBundleKey('<name>')` rather than writing it out, and confirm the
hook builds that bundle. For `.fmat`, use `loadFmatMaterial` with the source
`.fmat` path instead of loading generated files directly. If a shader edit does
not take effect, clear the app's `.dart_tool` and `build` directories and
rebuild.

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

**Wrong reflections on one backend only (raw `ShaderMaterial`).** The material
is probably missing its `radianceCubeFragmentShader`, so it samples the 2D
radiance slot where the backend builds a cubemap.

**Works on your machine, broken or crashing on another platform.** Almost
always one of the portable shader rules above (loop shape, sampler budget,
precision, or a construct outside ES 3.00). Check the shader against that
list before suspecting the platform.

---

# See also

- `examples/smoke_render/assets/custom_material.fmat` and the
  `fmat_custom_material` scene in `examples/smoke_render/lib/smoke_scenes.dart`:
  a worked `.fmat` that customizes both the vertex stage and the fragment,
  rendered through `PreprocessedMaterial`.
- `examples/flutter_app/lib/example_vertex_curve.dart` with
  `assets/vertex_ocean.fmat` and `assets/vertex_road.fmat`: the "Custom
  vertices" example (an animated curved ocean and a curved runner road),
  showing the `vertex { }` stage, custom varyings, and custom attributes.
- `examples/flutter_app/assets/toon.fmat` and `example_toon_fmat.dart`: a
  fragment-only `.fmat`; `example_toon.dart` is the raw-`ShaderMaterial` toon.
- `packages/flutter_scene/shaders/flutter_scene_standard.frag` and
  `material_lighting.glsl`: the engine's PBR shader and the lighting framework a
  `lit` material composes against.
