# Procedural content, the full API

Everything for building flutter_scene content from code, custom meshes, noise, instancing, and modular kits. All symbols verified against the package source. Import geometry and instancing from the main barrel, noise from its own barrel:

```dart
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/noise.dart';
import 'package:vector_math/vector_math.dart' as vm;   // NOT vector_math_64
```

---

## GeometryBuilder

The incremental way to build a custom triangle mesh. You add vertices one at a time, each carrying whatever attributes are currently set, then reference them by returned index to form triangles.

```dart
class GeometryBuilder {
  GeometryBuilder({bool deduplicate = true});

  // Sticky attribute setters (return `this`, so cascade or chain them).
  GeometryBuilder normal(vm.Vector3 value);
  GeometryBuilder texCoord(vm.Vector2 value);
  GeometryBuilder texCoord1(vm.Vector2 value);   // secondary UV set
  GeometryBuilder color(vm.Vector4 value);        // linear RGBA
  GeometryBuilder tangent(vm.Vector4 value);      // xyz + handedness in w

  int addVertex(vm.Vector3 position);             // returns the vertex index
  GeometryBuilder addTriangle(int a, int b, int c); // throws RangeError on a bad index

  int get vertexCount;
  int get triangleCount;

  Uint8List packVertices();                       // pure, no GPU context needed
  MeshGeometry build({
    GeometryStorage storage = GeometryStorage.fixed,
    GeometryBufferArena? bufferArena,
    bool retainCpuData = true,
  });
}
```

### The sticky-attribute model

The attribute setters do not apply to one vertex, they set state that every following `addVertex` inherits until you change it. This makes flat-shaded faces and per-region colors natural:

```dart
final geometry = (GeometryBuilder()
      ..color(vm.Vector4(1, 0, 0, 1))   // every vertex below is red...
      ..addVertex(vm.Vector3(0, 0, 0))
      ..addVertex(vm.Vector3(1, 0, 0))
      ..color(vm.Vector4(0, 1, 0, 1))   // ...until this changes it to green
      ..addVertex(vm.Vector3(0, 1, 0))
      ..addTriangle(0, 1, 2))
    .build();
```

### Normals, generated or authored

If you never call `normal()`, the builder generates area-weighted vertex normals from the faces you wound. That is the right default for most procedural geometry, terrain, extrusions, anything where the surface shape defines the normal.

**Calling `normal()` even once opts the whole mesh out of generated normals.** After that, any vertex you add without an explicit normal keeps the default `(0, 0, 1)`, which is almost never what you want. So either author a normal for every vertex, or author none and let generation run. Do not mix.

### Deduplication

With `deduplicate: true` (the default), `addVertex` merges a vertex equal to one already added and returns the existing index, so a shared grid corner is stored once. Pass `deduplicate: false` when you want every call to produce a distinct vertex (flat shading with per-face normals, or per-vertex data that must not collapse).

### Winding

flutter_scene's front faces wind **clockwise in model space**. For a surface that should face +Y (a heightmap, a floor), match the built-in plane's winding: for a cell with corners `v00`(x,z), `v10`(x+1,z), `v01`(x,z+1), `v11`(x+1,z+1), emit `addTriangle(v00, v10, v01)` and `addTriangle(v10, v11, v01)`.

If a mesh renders inside-out (invisible from the front, visible and inverted-lit from behind), reverse each triangle's index order. Because generated normals follow the winding, fixing the winding fixes the normals too. This freedom is only for geometry you author. Never apply a per-triangle winding flip to an imported model to correct its orientation, that leaves its normals and image-based lighting wrong.

### From builder to scene

`build()` returns a `MeshGeometry`, which is a `Geometry`. Wrap it in a `Mesh` with a material, hang the mesh on a `Node`, add the node:

```dart
final node = Node(mesh: Mesh(geometry, PhysicallyBasedMaterial()));
scene.add(node);
```

---

## MeshGeometry.fromArrays, the bulk path

When you already have attributes as flat arrays (a generator that fills typed lists), skip the per-vertex calls and hand `MeshGeometry.fromArrays` structure-of-arrays data directly. Same result, less overhead for large meshes.

```dart
MeshGeometry.fromArrays({
  required Float32List positions,   // 3 floats/vertex, required
  Float32List? normals,             // 3/vertex; omitted -> generated for triangle lists
  Float32List? texCoords,           // 2/vertex; omitted -> (0, 0)
  Float32List? texCoords1,          // 2/vertex
  Float32List? colors,              // 4/vertex; omitted -> opaque white
  Float32List? tangents,            // 4/vertex
  List<int>? indices,               // omitted -> vertex count must be a multiple of 3
  gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle,
  Aabb3? bounds,                    // skips the position scan; MUST cover every vertex
  GeometryStorage storage = GeometryStorage.fixed,
  GeometryBufferArena? bufferArena,
  bool retainCpuData = true,
});
```

Notes that bite:

- Every supplied optional array must match the vertex count implied by `positions`.
- Out-of-range `indices` are **not** validated here (unlike `GeometryBuilder.addTriangle`), and produce stray triangles or holes silently. Keep every index in `0..vertexCount-1`.
- A `bounds` you pass that does not enclose every vertex makes the mesh over-cull and pop out of view at some angles. Omit it (the constructor scans positions) unless you computed it correctly off-thread.
- `retainCpuData: false` drops the CPU copy after upload, saving memory, but then the mesh cannot be raycast or read back with `extractMeshData`.

### Updatable geometry (animated meshes)

Pass `storage: GeometryStorage.updatable` to get a mesh you can mutate in place each frame without reallocating. The in-place updaters replace one attribute when the vertex count is unchanged:

```dart
final water = MeshGeometry.fromArrays(positions: p, storage: GeometryStorage.updatable);
// later, per frame:
water.updatePositions(newPositions);         // also updateNormals/TexCoords/Colors/Tangents
// or replace everything (may change the count):
water.rebuild(positions: p2, indices: i2);
```

An updatable mesh fixes its indexed-or-not state at construction, if you built it with `indices`, `rebuild` requires them thereafter, and vice versa. To start empty and fill later, pass a zero-length `positions` with `updatable`. Updatable geometry must retain CPU data and cannot use a buffer arena.

`GeometryBufferArena({int blockSizeInBytes = 16 * 1024 * 1024})` lets many fixed meshes share immutable GPU buffer blocks, worth it when you build a large number of small static meshes.

---

## MeshData, meshing off the render isolate

Heavy generation (remeshing a voxel chunk, a large marching-cubes surface) should not block the render isolate. `MeshData` is a pure, isolate-transferable snapshot, build it on a background isolate with `compute`, send it back, upload it there.

```dart
factory MeshData.build({
  required Float32List positions,
  Float32List? normals,          // omitted -> generated for triangle lists (the win here)
  Float32List? texCoords,
  Float32List? texCoords1,
  Float32List? colors,
  Float32List? tangents,
  List<int>? indices,
  gpu.PrimitiveType primitiveType = gpu.PrimitiveType.triangle,
  Map<String, MeshAttributeData> customAttributes = const {},
});
```

Recipe:

```dart
// Top-level or static, runs on the background isolate.
MeshData buildChunk(ChunkInput input) {
  final positions = /* your generator */;
  final indices = /* ... */;
  return MeshData.build(positions: positions, indices: indices);
}

// On the render isolate:
final data = await compute(buildChunk, input);
final geometry = MeshGeometry.fromMeshData(data);
// or, to feed an existing updatable mesh in place:
existing.applyMeshData(data);
```

The normal generation is the expensive part, and running it inside `MeshData.build` is exactly the work you moved off the render isolate.

Pure derivations on a `MeshData` (all off-isolate safe): `transformed(Matrix4)` (moves positions, carries normals by the inverse transpose so a non-uniform scale stays correct, reverses winding on a mirror), `unweld({attributes})`, `extractEdges({creaseAngleDegrees})`, static `MeshData.merge(parts)`, plus `triangleCount`/`triangles`. `Geometry.extractMeshData()` reads a loaded mesh back into one.

---

## FastNoiseLite

One configurable object evaluating several noise algorithms, sampled with `getNoise2`/`getNoise3`. Output is roughly in `[-1, 1]`.

```dart
final noise = FastNoiseLite(seed: 1337)
  ..frequency = 0.01                        // coords are multiplied by this before eval
  ..noiseType = NoiseType.openSimplex2
  ..fractalType = FractalType.fbm
  ..octaves = 5;

final h = noise.getNoise2(x, z);            // 2D
final d = noise.getNoise3(x, y, z);         // 3D
```

### Config reference

| Field | Default | Meaning |
| --- | --- | --- |
| `seed` | 1337 | Seed for every noise type. |
| `frequency` | 0.01 | Input coordinates are scaled by this. Bigger = finer features. |
| `noiseType` | `openSimplex2` | Base algorithm (see below). |
| `fractalType` | `none` | How octaves layer (see below). |
| `octaves` | 3 | Number of fractal layers. More detail, more cost. |
| `lacunarity` | 2.0 | Frequency multiplier between octaves. |
| `gain` | 0.5 | Amplitude multiplier between octaves. |
| `weightedStrength` | 0.0 | Biases octave amplitude toward stronger detail. |
| `pingPongStrength` | 2.0 | Warp strength for `FractalType.pingPong`. |
| `cellularDistanceFunction` | `euclideanSq` | Distance metric for `NoiseType.cellular`. |
| `cellularReturnType` | `distance` | What cellular returns. |
| `cellularJitterModifier` | 1.0 | Cell-point jitter; above 1 causes artifacts. |
| `domainWarpType` | `openSimplex2` | Warp algorithm for `domainWarp2`/`domainWarp3`. |
| `domainWarpAmp` | 1.0 | Max warp distance. |
| `domainWarpFractalType` | `none` | Octave layering for domain warp. |

Enums:

- `NoiseType` = `openSimplex2` | `openSimplex2S` | `cellular` | `perlin` | `value`.
- `FractalType` = `none` | `fbm` (classic layered fractal, the usual terrain choice) | `ridged` (sharp ridges, mountains) | `pingPong`.
- `CellularDistanceFunction` = `euclidean` | `euclideanSq` | `manhattan` | `hybrid`.
- `CellularReturnType` = `cellValue` | `distance` | `distance2` | `distance2Add` | `distance2Sub` | `distance2Mul` | `distance2Div`.
- `DomainWarpType` = `openSimplex2` | `openSimplex2Reduced` | `basicGrid`.
- `DomainWarpFractalType` = `none` | `progressive` | `independent`.

### Domain warp

`domainWarp2`/`domainWarp3` distort the input coordinates before sampling, breaking up the regular look of raw fractal noise. The reference version mutates in place, this port returns the warped position for you to feed back in:

```dart
final w = noise.domainWarp2(x, z);   // ({double x, double y})
final v = noise.getNoise2(w.x, w.y);
```

### Curl noise

`noiseCurl3(x, y, z, {int seed = 1337, double epsilon = 0.25})` returns a divergence-free 3D vector `({x, y, z})` from a seeded potential field, for advecting particles so they swirl without clumping. Coordinates are taken pre-scaled (no frequency parameter), matching the GLSL `NoiseCurl3`. Advect by adding `curl * speed * dt`. A smaller `epsilon` sharpens the field and amplifies CPU/GPU divergence.

### Baking noise to a texture

Sampling many octaves per fragment is expensive. When the field is static, bake it once and sample the texture instead:

```dart
Texture2D bakeNoiseTexture(
  FastNoiseLite noise, {
  required int width,
  required int height,
  double originX = 0.0,
  double originY = 0.0,
  double cellSize = 1.0,
  TextureSampling sampling = const TextureSampling(),
});
```

It bakes `getNoise2` over a `width` x `height` grid into a grayscale `Texture2D` (content is linear `data`, so mipmaps average cleanly) ready to bind as a material sampler. It must run where GPU resources are created (the raster thread). The CPU half, `bakeNoisePixels(noise, {width, height, originX, originY, cellSize})`, returns `Uint8List` RGBA and has no engine imports, so it runs in a build hook or a background isolate, then `Texture2D.fromPixels` uploads the result.

---

## The web noise caveat, expanded

The Dart `FastNoiseLite` port relies on 32-bit integer arithmetic. On native platforms this is exact. On the web (dart2js), a Dart `int` is a JavaScript double, exact only to 53 bits, so the integer hash loses its low bits and 3D noise can overflow. The result is a plausible-looking but wrong field, silent, and web-only. A web-safe integer multiply for the Dart side is a planned follow-up.

The GLSL half of the module is unaffected, it is correct on every backend including WebGL2, and implements the same algorithms with the same tables and seeds, so a field sampled on the CPU (native) and evaluated in a shader agree. The agreement has two tiers:

- **Bit-exact**: `noiseHash2`/`noiseHash3` (and GLSL `NoiseHash2`/`NoiseHash3`) are pure integer math and match bit for bit across backends. Use them for decisions that must never disagree between machines (world generation, deterministic placement).
- **Float-close**: the float noise functions match within a small tolerance (float32 rounding differs per GPU), imperceptible visually. Do not re-derive a hard threshold from float noise on both the CPU and GPU sides, make the decision once and share the result.

Both tiers carry the web-overflow caveat on the Dart side. Strategy by target:

- **Native only**: use the Dart `FastNoiseLite` freely, on the render isolate or a background one.
- **Web, per-fragment noise**: move it to the GLSL side (`#include <noise.glsl>` in a `.fmat` block).
- **Web, a static field**: bake it with `bakeNoiseTexture` (or `bakeNoisePixels` in a build hook / native isolate) and sample the texture. This sidesteps the overflow because the baking happens where `int` is 64-bit.

---

## InstancedMesh, thousands of copies for one draw

One geometry/material pair drawn many times, each placed by its own model transform. The whole set is one render item, one pipeline, one cull test. This is how you scatter foliage, crowds, debris, or a grid of the same prop without a node per copy.

```dart
class InstancedMesh {
  InstancedMesh({
    required Geometry geometry,
    required Material material,
    bool cullInstances = false,          // per-instance cull after the aggregate pass
    bool sortTransparentInstances = true,
  });

  int get instanceCount;

  int addInstance(vm.Matrix4 transform, {vm.Vector4? color}); // matrix is CLONED; returns index
  void setInstanceTransform(int index, vm.Matrix4 transform);
  void updateInstanceTransforms(
    void Function(List<vm.Matrix4> transforms) update, {
    bool recomputeWinding = true,
  });
  void setInstanceColor(int index, vm.Vector4 color);         // linear RGBA multiplier
  void removeInstanceAt(int index);                            // shifts later indices down
  void clearInstances();
}
```

Attach it to a node with an `InstancedMeshComponent` (it does not go on `Node(mesh:)`):

```dart
final mesh = InstancedMesh(geometry: geo, material: mat);
for (final placement in placements) {
  mesh.addInstance(placement); // a Matrix4 in the instanced mesh's local space
}
final node = Node()..addComponent(InstancedMeshComponent(mesh));
scene.add(node);
```

Practical notes:

- `addInstance` clones the matrix, so reusing one scratch `Matrix4` across the loop is fine.
- The node the component is on transforms the entire batch. Instance transforms compose under it.
- To animate all instances cheaply, use `updateInstanceTransforms`, which invalidates the batch once instead of per call. Mutate the matrices in the callback list; do not add, remove, or replace entries.
- `updateInstanceTransforms(recomputeWinding: false)` skips the parity refresh. Only pass it when no edit changes a transform's winding. A mirrored (negative-determinant) edit under it renders those instances inside-out.
- `cullInstances: true` pays for per-instance culling, worth it for a large spatial spread whose instances enter view at different times; leave it off for a small compact clump that the single aggregate cull already handles.
- Set `cullInstances` per instanced mesh based on that trade; it is not a global.

---

## Modular kits from the built-in primitives

Before authoring a mesh, remember the ten primitives assemble a surprising amount by composition, no builder needed. Each is a `Geometry`, so each goes on its own `Node`, and a parent node groups a kit piece you can clone and place.

| Class | Constructor | Notes |
| --- | --- | --- |
| `CuboidGeometry` | `CuboidGeometry(vm.Vector3 extents)` | Box from `-extents/2` to `+extents/2`. Positional. |
| `SphereGeometry` | `SphereGeometry({radius = 0.5, segments = 32, rings = 16})` | UV sphere. |
| `IcosphereGeometry` | `IcosphereGeometry({radius = 0.5, subdivisions = 2})` | Even triangle distribution. |
| `CylinderGeometry` | `CylinderGeometry({bottomRadius = 0.5, topRadius = 0.5, height = 1.0, ...})` | `topRadius: 0` makes a cone; different radii make a frustum. |
| `CapsuleGeometry` | `CapsuleGeometry({radius = 0.5, height = 1.0, ...})` | `height` is the mid-section; total Y is `height + 2*radius`. |
| `TorusGeometry` | `TorusGeometry({radius = 0.5, tubeRadius = 0.2, ...})` | Lies in XZ. |
| `PlaneGeometry` | `PlaneGeometry({width = 1.0, depth = 1.0, segmentsX = 1, segmentsZ = 1})` | XZ plane, faces +Y. |
| `DiscGeometry` | `DiscGeometry({radius = 0.5, segments = 32})` | Filled circle, XZ, faces +Y. |
| `RingGeometry` | `RingGeometry({innerRadius = 0.25, outerRadius = 0.5, segments = 32})` | Annulus, XZ, +Y. |
| `WedgeGeometry` | `WedgeGeometry(vm.Vector3 size)` | Triangular prism; base on `y = 0` (not Y-centered). |

Because a cone is just `CylinderGeometry(topRadius: 0)`, a tree is a green cone on a brown cylinder, a fence is repeated thin cuboids, a table is a plane on four cylinders. Assemble each piece as a parented `Node` subtree, then `clone()` and place it, or feed the placements to an `InstancedMesh` when the same piece repeats many times.

Every primitive except `PlaneGeometry` exposes a `Shape get collisionShape` for the physics package, so a code-built kit gets colliders for free.

### Swept geometry for shapes primitives cannot make

For paths, tubes, and profiles, sweep a `ScenePath` (`BezierPath`, `CatmullRomPath`, `PolylinePath`):

- `TubeGeometry(path, {radius = 0.5, radialSegments = 12, stations = 64, caps = true})` for pipes, cables, vines.
- `ExtrudeGeometry(path, {required List<vm.Vector2> profile, stations = 64, caps = true})` sweeps a 2D profile along the path (railings, moldings, extruded logos).
- `RibbonGeometry(path, {width = 1.0, stations = 64, alignment = RibbonAlignment.ground})` for flat strips (roads, trails).

These build detailed shapes from a curve and a few parameters, often replacing an imported model outright.
