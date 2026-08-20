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
