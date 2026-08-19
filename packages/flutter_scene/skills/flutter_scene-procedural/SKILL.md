---
name: flutter_scene-procedural
version: 1
description: Build flutter_scene content from code instead of asset files. Use when generating terrain, scattering vegetation or crowds, assembling modular kits, or driving a scene from noise and instancing rather than loading a .glb.
---

# Procedural content in flutter_scene

A lot of 3D work does not need an artist's `.glb` at all. Terrain, scattered foliage, debris fields, crowds, and modular buildings are cheaper and more flexible built from code, and flutter_scene has the whole path in the box. Reach for it before wiring up an asset pipeline.

**The insight: for a code-driven scene, generate geometry and draw it instanced. That path is more reliable than loading external assets, because it has no import step, no coordinate-conversion traps, no missing-file failure modes, and one draw call for thousands of copies.** Three pieces cover almost everything:

- **`GeometryBuilder`** (and the ten built-in primitives) build custom meshes without a model file.
- **`FastNoiseLite`** drives heightmaps, placement, and displacement deterministically.
- **`InstancedMesh`** draws thousands of copies of one mesh as a single render item.

Do not hand-pack a `ByteData` vertex buffer. The vertex layout is fixed (72 bytes unskinned, a specific attribute order) and a wrong stride fails silently with washed-out or see-through geometry. `GeometryBuilder` and `MeshGeometry.fromArrays` interleave the layout for you.

## Imports

Geometry and instancing live in the main barrel. **Noise is a separate barrel** and is easy to forget:

```dart
import 'package:flutter_scene/scene.dart';   // GeometryBuilder, MeshGeometry, InstancedMesh, ...
import 'package:flutter_scene/noise.dart';   // FastNoiseLite, bakeNoiseTexture, noiseCurl3
import 'package:vector_math/vector_math.dart' as vm;   // NOT vector_math_64
```

## Terrain from a noise heightmap

Sample `FastNoiseLite` on a grid, add each vertex, and wind the two triangles per cell so the lit surface faces up. Omitting normals lets the builder derive them from the actual face slopes, which is what you want for terrain.

```dart
MeshGeometry buildTerrain({int cols = 128, int rows = 128, double spacing = 0.5}) {
  final noise = FastNoiseLite(seed: 1337)
    ..noiseType = NoiseType.openSimplex2
    ..fractalType = FractalType.fbm   // stack octaves for natural detail
    ..octaves = 5
    ..frequency = 0.02;               // world units are multiplied by this

  final builder = GeometryBuilder();

  // One vertex per grid point. getNoise2 returns roughly -1..1.
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final x = c * spacing;
      final z = r * spacing;
      final height = noise.getNoise2(x, z) * 6.0;
      builder.addVertex(vm.Vector3(x, height, z));
    }
  }

  // Two triangles per cell, wound so the front face points +Y (up).
  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < cols - 1; c++) {
      final v00 = r * cols + c;
      final v10 = v00 + 1;
      final v01 = v00 + cols;
      final v11 = v01 + 1;
      builder
        ..addTriangle(v00, v10, v01)
        ..addTriangle(v10, v11, v01);
    }
  }

  return builder.build();
}
```

Attach it like any mesh:

```dart
final terrain = Node(mesh: Mesh(buildTerrain(), PhysicallyBasedMaterial()..roughnessFactor = 1.0));
scene.add(terrain);
```

If a hand-built surface renders inside-out (visible only from below, dark where lit), reverse each triangle's index order. flutter_scene's front faces wind clockwise in model space; never fix orientation with a per-triangle flip on an imported model, but for geometry you author yourself the winding is yours to set.

## Scattering thousands of copies

`InstancedMesh` holds one geometry/material pair and a transform per copy. The whole set is one pipeline and one cull test. Place instances by sampling the same terrain height so they sit on the ground.

```dart
final rng = math.Random(7);
final scatter = InstancedMesh(
  geometry: CylinderGeometry(bottomRadius: 0.0, topRadius: 0.15, height: 1.2), // a cone
  material: PhysicallyBasedMaterial()..baseColorFactor = vm.Vector4(0.2, 0.5, 0.15, 1),
);

for (var i = 0; i < 4000; i++) {
  final x = rng.nextDouble() * 64;
  final z = rng.nextDouble() * 64;
  final y = noise.getNoise2(x, z) * 6.0; // same field as the terrain
  final transform = vm.Matrix4.translation(vm.Vector3(x, y, z))
    ..rotateY(rng.nextDouble() * math.pi * 2);
  scatter.addInstance(transform); // the matrix is cloned; mutating it later is safe
}

// InstancedMesh rides on a component, not Node(mesh:).
final node = Node()..addComponent(InstancedMeshComponent(scatter));
scene.add(node);
```

`addInstance(matrix, {color})` returns an index; edit later with `setInstanceTransform(i, m)` or move the whole batch at once through `updateInstanceTransforms((list) { ... })`. Per-instance `color` is a linear RGBA multiplier. Keep instance edits orientation-preserving, a mirrored (negative-determinant) instance edited with `updateInstanceTransforms(recomputeWinding: false)` renders inside-out.

## The web noise trap

The Dart `FastNoiseLite` relies on 32-bit integer math. On the web (dart2js) a Dart `int` is a JavaScript double, exact only to 53 bits, so the hash loses its low bits and 3D noise can overflow, producing wrong values. This is silent, you get a plausible-looking but incorrect field, and only on web.

For web targets:

- Prefer the **GLSL side** (`#include <noise.glsl>` in a `.fmat` block), which is correct on every backend including WebGL2 and matches the Dart algorithms table-for-table.
- Or **bake** the field once with `bakeNoiseTexture(noise, width: ..., height: ...)` at build time or in a native isolate, then sample the texture. `bakeNoisePixels` is pure CPU with no engine imports, so it runs in a build hook or background isolate.

Native platforms are unaffected. `noiseHash2`/`noiseHash3` are the bit-exact CPU/GPU-agreeing integer path for decisions that must never disagree (world generation, placement), but they carry the same web-overflow caveat, so make the decision once and share it rather than re-deriving it on both sides.

## More depth

`references/procedural.md` has the full `GeometryBuilder` and `MeshData` API (including off-isolate meshing), the complete `FastNoiseLite` config reference, the instancing API in full, modular-kit assembly from the built-in primitives, and the web-noise caveat expanded.
