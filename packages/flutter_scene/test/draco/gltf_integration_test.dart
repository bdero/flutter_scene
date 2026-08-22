// Importer integration for KHR_draco_mesh_compression. Packing a compressed
// primitive must produce the same vertex and index bytes as packing the
// reference-decoded copy of the same asset.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/gltf/bounds_baker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

(GltfDocument, Uint8List) _load(String name) {
  final contents = parseGlb(File('$fixtureDir/$name.glb').readAsBytesSync());
  return (parseGltfJson(contents.json), contents.binaryChunk);
}

void _comparePacked(String name) {
  final (compressedDoc, compressedBin) = _load(name);
  final (decodedDoc, decodedBin) = _load('${name}_decoded');
  for (var m = 0; m < compressedDoc.meshes.length; m++) {
    final mesh = compressedDoc.meshes[m];
    for (var p = 0; p < mesh.primitives.length; p++) {
      expect(mesh.primitives[p].draco, isNotNull);
      final packed = packGltfPrimitive(
        primitive: mesh.primitives[p],
        accessors: compressedDoc.accessors,
        bufferViews: compressedDoc.bufferViews,
        bufferData: compressedBin,
        coordinatePolicy: GltfCoordinatePolicy.bakeNative,
      );
      final reference = packGltfPrimitive(
        primitive: decodedDoc.meshes[m].primitives[p],
        accessors: decodedDoc.accessors,
        bufferViews: decodedDoc.bufferViews,
        bufferData: decodedBin,
        coordinatePolicy: GltfCoordinatePolicy.bakeNative,
      );
      expect(packed.vertexCount, reference.vertexCount);
      expect(packed.isSkinned, reference.isSkinned);
      expect(packed.indexCount, reference.indexCount);
      expect(packed.indices32Bit, reference.indices32Bit);
      expect(packed.vertexBytes, reference.vertexBytes);
      expect(packed.indexBytes, reference.indexBytes);
    }
  }
}

/// Appends [slabs] (each `vertexCount * 3` floats) to [bin] as float VEC3
/// accessors and returns the extended tables plus one accessor index per
/// slab. Used to graft synthetic morph targets onto a fixture document.
(List<GltfAccessor>, List<GltfBufferView>, Uint8List, List<int>)
_appendVec3Accessors(GltfDocument doc, Uint8List bin, List<Float32List> slabs) {
  final accessors = List.of(doc.accessors);
  final views = List.of(doc.bufferViews);
  final builder = BytesBuilder(copy: false);
  builder.add(bin);
  final pad = (4 - bin.length % 4) % 4;
  if (pad != 0) builder.add(Uint8List(pad));
  final indices = <int>[];
  for (final slab in slabs) {
    final offset = builder.length;
    builder.add(Uint8List.sublistView(slab));
    views.add(
      GltfBufferView(
        buffer: 0,
        byteLength: slab.lengthInBytes,
        byteOffset: offset,
      ),
    );
    accessors.add(
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: slab.length ~/ 3,
        type: GltfAccessorType.vec3,
        bufferView: views.length - 1,
      ),
    );
    indices.add(accessors.length - 1);
  }
  return (accessors, views, builder.takeBytes(), indices);
}

void main() {
  test('parses the draco extension on primitives', () {
    final (doc, _) = _load('synthetic_draco_eb');
    final draco = doc.meshes[0].primitives[0].draco;
    expect(draco, isNotNull);
    expect(draco!.attributes.keys, contains('POSITION'));
    // The compressed accessors legitimately carry no buffer views.
    final positionAccessor =
        doc.accessors[doc.meshes[0].primitives[0].attributes['POSITION']!];
    expect(positionAccessor.bufferView, isNull);
  });

  test('packs sequential draco primitives like the reference decode', () {
    _comparePacked('synthetic_draco_seq');
  });

  test('packs EdgeBreaker draco primitives like the reference decode', () {
    _comparePacked('synthetic_draco_eb');
    _comparePacked('synthetic_draco_eb_cl10');
  });

  test('packs seamed draco primitives like the reference decode', () {
    _comparePacked('cube_draco_eb');
    _comparePacked('cube_draco_eb_cl10');
  });

  test('packs skinned draco primitives like the reference decode', () {
    _comparePacked('two_triangles_draco_eb');
  });

  test('packs morph targets on draco primitives like the reference decode', () {
    // Morph target accessors always live in the original buffer (the
    // extension compresses only the base attributes), so packing a fully
    // compressed primitive with targets must still read them correctly.
    final (compressedDoc, compressedBin) = _load('synthetic_draco_seq');
    final (decodedDoc, decodedBin) = _load('synthetic_draco_seq_decoded');
    final compressedPrim = compressedDoc.meshes[0].primitives[0];
    final decodedPrim = decodedDoc.meshes[0].primitives[0];
    // Every attribute is inside the extension, the shape that previously
    // dropped the original bytes from the synthesized buffer.
    expect(
      compressedPrim.attributes.keys,
      everyElement(isIn(compressedPrim.draco!.attributes.keys)),
    );
    final vertexCount =
        compressedDoc.accessors[compressedPrim.attributes['POSITION']!].count;
    expect(
      vertexCount,
      decodedDoc.accessors[decodedPrim.attributes['POSITION']!].count,
    );

    // Two targets, each with POSITION and NORMAL deltas; the values only
    // need to be deterministic and distinct per slab.
    Float32List slab(int seed) {
      final out = Float32List(vertexCount * 3);
      for (var i = 0; i < out.length; i++) {
        out[i] = ((i * 31 + seed * 7) % 17 - 8) / 16;
      }
      return out;
    }

    final slabs = [slab(1), slab(2), slab(3), slab(4)];

    PackedPrimitive pack(
      GltfDocument doc,
      Uint8List bin,
      GltfMeshPrimitive prim,
    ) {
      final (accessors, views, data, idx) = _appendVec3Accessors(
        doc,
        bin,
        slabs,
      );
      return packGltfPrimitive(
        primitive: GltfMeshPrimitive(
          attributes: prim.attributes,
          indices: prim.indices,
          material: prim.material,
          mode: prim.mode,
          draco: prim.draco,
          targets: [
            {'POSITION': idx[0], 'NORMAL': idx[1]},
            {'POSITION': idx[2], 'NORMAL': idx[3]},
          ],
        ),
        accessors: accessors,
        bufferViews: views,
        bufferData: data,
        coordinatePolicy: GltfCoordinatePolicy.bakeNative,
      );
    }

    final packed = pack(compressedDoc, compressedBin, compressedPrim);
    final reference = pack(decodedDoc, decodedBin, decodedPrim);
    final morphs = packed.morphTargets!;
    final referenceMorphs = reference.morphTargets!;
    expect(morphs.targetCount, 2);
    expect(morphs.vertexCount, referenceMorphs.vertexCount);
    expect(morphs.positionDeltas, referenceMorphs.positionDeltas);
    expect(morphs.normalDeltas, referenceMorphs.normalDeltas);
    // The reference itself carries the grafted values, so the comparison
    // above is not vacuously matching zero-filled slabs.
    expect(referenceMorphs.positionDeltas[0], slabs[0][0]);
  });

  test('bakes skinned pose unions from draco primitives', () {
    final (compressedDoc, compressedBin) = _load('two_triangles_draco_eb');
    final (decodedDoc, decodedBin) = _load('two_triangles_draco_eb_decoded');
    final packed = bakeSkinnedPoseUnionAabbs(compressedDoc, compressedBin);
    final reference = bakeSkinnedPoseUnionAabbs(decodedDoc, decodedBin);
    expect(packed.keys, reference.keys);
    for (final node in reference.keys) {
      final unions = packed[node]!;
      final referenceUnions = reference[node]!;
      expect(unions.length, referenceUnions.length);
      for (var i = 0; i < unions.length; i++) {
        final a = unions[i];
        final b = referenceUnions[i];
        expect(a == null, b == null);
        if (a == null || b == null) continue;
        expect(a.isEmpty, b.isEmpty);
        expect(a.minX, b.minX);
        expect(a.minY, b.minY);
        expect(a.minZ, b.minZ);
        expect(a.maxX, b.maxX);
        expect(a.maxY, b.maxY);
        expect(a.maxZ, b.maxZ);
      }
    }
  });
}
