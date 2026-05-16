// ignore_for_file: avoid_print, unnecessary_brace_in_string_interps

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/gltf.dart';
import 'package:test/test.dart';

/// Side-by-side byte comparison: my Dart-only runtime parser vs the existing
/// offline (.model) import path, for the first primitive of fcar's CarBody
/// mesh. Diagnostic test for surfacing differences in vertex/index packing.

void main() {
  test('fcar: first primitive bytes via runtime importer match offline .model', () {
    final glbPath = _resolve('examples/assets_src/fcar.glb');
    final modelPath = _resolve('examples/flutter_app/build/models/fcar.model');
    if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
      print('Test data missing — skipping.');
      return;
    }

    // Path A: runtime importer.
    final glbBytes = File(glbPath).readAsBytesSync();
    final container = parseGlb(glbBytes);
    final doc = parseGltfJson(container.json);
    // Use mesh index 1, primitive 0 (CarBody) — the first primitive that
    // exercises the full unskinned vertex layout in this file.
    final myPrimitive = doc.meshes[1].primitives[0];
    final mine = packGltfPrimitive(
      primitive: myPrimitive,
      accessors: doc.accessors,
      bufferViews: doc.bufferViews,
      bufferData: container.binaryChunk,
    );

    // Path B: offline .model.
    final modelBytes = File(modelPath).readAsBytesSync();
    final imported = ImportedScene.fromFlatbuffer(
      ByteData.sublistView(modelBytes),
    );
    final fbScene = imported.flatbuffer;
    // Find the equivalent CarBody primitive in the .model.
    fb.MeshPrimitive? theirPrimitive;
    for (final node in fbScene.nodes ?? <fb.Node>[]) {
      if (node.name != 'CarBody') continue;
      for (final p in node.meshPrimitives ?? <fb.MeshPrimitive>[]) {
        theirPrimitive = p;
        break;
      }
      if (theirPrimitive != null) break;
    }
    expect(
      theirPrimitive,
      isNotNull,
      reason: 'CarBody primitive missing in .model',
    );
    final theirVertexBuffer =
        theirPrimitive!.vertices as fb.UnskinnedVertexBuffer?;
    expect(
      theirVertexBuffer,
      isNotNull,
      reason: 'CarBody is expected to be unskinned',
    );
    final theirVertexBytes = Uint8List.fromList(theirVertexBuffer!.vertices!);
    final theirIndices = theirPrimitive.indices!;
    final theirIndexBytes = Uint8List.fromList(theirIndices.data!);

    print('--- Vertex bytes ---');
    print(
      '  mine.length=${mine.vertexBytes.length} bytes (${mine.vertexCount} verts)',
    );
    print('  theirs.length=${theirVertexBytes.length} bytes');
    print('  mine.isSkinned=${mine.isSkinned}');

    print('--- Index bytes ---');
    print(
      '  mine.length=${mine.indexBytes.length} bytes, indices32Bit=${mine.indices32Bit}',
    );
    print(
      '  theirs.length=${theirIndexBytes.length} bytes, type=${theirIndices.type}',
    );

    print('  mine.vertexCount=${mine.vertexCount}');
    print('  theirs.vertexCount=${theirVertexBuffer.vertexCount}');

    // First vertex (48 bytes) interpreted as 12 floats (pos×3, normal×3, tex×2, color×4).
    final mineFloats = mine.vertexBytes.buffer.asFloat32List(
      mine.vertexBytes.offsetInBytes,
      12,
    );
    final theirFloats = theirVertexBytes.buffer.asFloat32List(
      theirVertexBytes.offsetInBytes,
      12,
    );
    print('--- First vertex (floats) ---');
    print(
      '  mine:   pos=${mineFloats.sublist(0, 3)} '
      'norm=${mineFloats.sublist(3, 6)} '
      'tex=${mineFloats.sublist(6, 8)} '
      'color=${mineFloats.sublist(8, 12)}',
    );
    print(
      '  theirs: pos=${theirFloats.sublist(0, 3)} '
      'norm=${theirFloats.sublist(3, 6)} '
      'tex=${theirFloats.sublist(6, 8)} '
      'color=${theirFloats.sublist(8, 12)}',
    );

    // Find the index-of-first-difference in the vertex buffer (just for diagnostics).
    final cmpLen =
        mine.vertexBytes.length < theirVertexBytes.length
            ? mine.vertexBytes.length
            : theirVertexBytes.length;
    int firstDiff = -1;
    for (int i = 0; i < cmpLen; i++) {
      if (mine.vertexBytes[i] != theirVertexBytes[i]) {
        firstDiff = i;
        break;
      }
    }
    print(
      '--- First differing vertex byte: ${firstDiff == -1 ? "(none)" : "@$firstDiff"} ---',
    );
    if (firstDiff != -1) {
      final start = (firstDiff ~/ 4) * 4;
      print(
        '  mine[${start}..${start + 4}]=${mine.vertexBytes.sublist(start, start + 4)}',
      );
      print(
        '  theirs[${start}..${start + 4}]=${theirVertexBytes.sublist(start, start + 4)}',
      );
    }

    // First index comparison (uint16).
    if (mine.indexBytes.length >= 6 && theirIndexBytes.length >= 6) {
      final myIndices = mine.indexBytes.buffer.asUint16List(
        mine.indexBytes.offsetInBytes,
        3,
      );
      final theirIndicesArr = theirIndexBytes.buffer.asUint16List(
        theirIndexBytes.offsetInBytes,
        3,
      );
      print('--- First triangle indices ---');
      print('  mine:   ${myIndices.toList()}');
      print('  theirs: ${theirIndicesArr.toList()}');
    }
  });

  test('two_triangles (skinned): vertex+index bytes match the .model', () {
    final glbPath = _resolve('examples/assets_src/two_triangles.glb');
    final modelPath = _resolve(
      'examples/flutter_app/build/models/two_triangles.model',
    );
    if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
      print('Test data missing — skipping.');
      return;
    }
    _comparePrimitiveBytes(glbPath, modelPath, expectSkinned: true);
  });

  test(
    'dash (skinned): first-primitive vertex+index bytes match the .model',
    () {
      final glbPath = _resolve('examples/assets_src/dash.glb');
      final modelPath = _resolve(
        'examples/flutter_app/build/models/dash.model',
      );
      if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
        print('Test data missing — skipping.');
        return;
      }
      _comparePrimitiveBytes(glbPath, modelPath, expectSkinned: true);
    },
  );

  test('flutter_logo_baked: vertex+index bytes match the .model', () {
    final glbPath = _resolve('examples/assets_src/flutter_logo_baked.glb');
    final modelPath = _resolve(
      'examples/flutter_app/build/models/flutter_logo_baked.model',
    );
    if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
      print('Test data missing — skipping.');
      return;
    }
    final glbBytes = File(glbPath).readAsBytesSync();
    final container = parseGlb(glbBytes);
    final doc = parseGltfJson(container.json);
    final mine = packGltfPrimitive(
      primitive: doc.meshes.first.primitives.first,
      accessors: doc.accessors,
      bufferViews: doc.bufferViews,
      bufferData: container.binaryChunk,
    );
    final modelBytes = File(modelPath).readAsBytesSync();
    final fbScene =
        ImportedScene.fromFlatbuffer(
          ByteData.sublistView(modelBytes),
        ).flatbuffer;
    fb.MeshPrimitive? theirPrim;
    for (final node in fbScene.nodes ?? <fb.Node>[]) {
      final prims = node.meshPrimitives;
      if (prims != null && prims.isNotEmpty) {
        theirPrim = prims.first;
        break;
      }
    }
    expect(theirPrim, isNotNull);
    final theirVB = theirPrim!.vertices as fb.UnskinnedVertexBuffer;
    final theirVertexBytes = Uint8List.fromList(theirVB.vertices!);
    final theirIndexBytes = Uint8List.fromList(theirPrim.indices!.data!);
    print(
      'flutter_logo: mine.vertexBytes=${mine.vertexBytes.length} '
      'theirs=${theirVertexBytes.length}',
    );
    expect(
      _bytesEqual(mine.vertexBytes, theirVertexBytes),
      isTrue,
      reason: 'flutter_logo vertex bytes differ',
    );
    expect(
      _bytesEqual(mine.indexBytes, theirIndexBytes),
      isTrue,
      reason: 'flutter_logo index bytes differ',
    );
  });

  test('fcar: all unskinned primitives match byte-for-byte', () {
    final glbPath = _resolve('examples/assets_src/fcar.glb');
    final modelPath = _resolve('examples/flutter_app/build/models/fcar.model');
    if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
      print('Test data missing — skipping.');
      return;
    }

    final glbBytes = File(glbPath).readAsBytesSync();
    final container = parseGlb(glbBytes);
    final doc = parseGltfJson(container.json);
    final modelBytes = File(modelPath).readAsBytesSync();
    final imported = ImportedScene.fromFlatbuffer(
      ByteData.sublistView(modelBytes),
    );
    final fbScene = imported.flatbuffer;

    // Build a name → primitive bag from the .model.
    final theirByName = <String, fb.MeshPrimitive>{};
    for (final node in fbScene.nodes ?? <fb.Node>[]) {
      if (node.name == null) continue;
      final prims = node.meshPrimitives;
      if (prims != null && prims.isNotEmpty) {
        // Just record the first primitive per node for this comparison.
        theirByName[node.name!] = prims.first;
      }
    }

    int matched = 0;
    int differing = 0;
    final differences = <String>[];
    for (int nodeIdx = 0; nodeIdx < doc.nodes.length; nodeIdx++) {
      final gn = doc.nodes[nodeIdx];
      if (gn.name == null || gn.mesh == null) continue;
      final theirPrim = theirByName[gn.name!];
      if (theirPrim == null) continue;
      final myPrims = doc.meshes[gn.mesh!].primitives;
      if (myPrims.isEmpty) continue;
      final mine = packGltfPrimitive(
        primitive: myPrims.first,
        accessors: doc.accessors,
        bufferViews: doc.bufferViews,
        bufferData: container.binaryChunk,
      );
      if (mine.isSkinned) continue;
      final theirVB = theirPrim.vertices as fb.UnskinnedVertexBuffer?;
      if (theirVB == null) continue;
      final theirBytes = Uint8List.fromList(theirVB.vertices!);
      final theirIdx = Uint8List.fromList(theirPrim.indices!.data!);
      final vertexMatch = _bytesEqual(mine.vertexBytes, theirBytes);
      final indexMatch = _bytesEqual(mine.indexBytes, theirIdx);
      if (vertexMatch && indexMatch) {
        matched++;
      } else {
        differing++;
        differences.add(
          '${gn.name}: vertex=${vertexMatch ? "match" : "DIFF"} '
          '(${mine.vertexBytes.length}/${theirBytes.length}), '
          'index=${indexMatch ? "match" : "DIFF"} '
          '(${mine.indexBytes.length}/${theirIdx.length})',
        );
      }
    }
    print('--- Per-primitive comparison ---');
    print('  matched: $matched, differing: $differing');
    for (final d in differences.take(10)) {
      print('  $d');
    }
  });
}

/// Compares the first primitive's packed vertex/index bytes between the
/// runtime importer and the offline .model. Throws if they differ.
void _comparePrimitiveBytes(
  String glbPath,
  String modelPath, {
  required bool expectSkinned,
}) {
  final glbBytes = File(glbPath).readAsBytesSync();
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  // Find the first node with a mesh (some files have empty placeholder nodes).
  GltfMeshPrimitive? myPrim;
  for (final node in doc.nodes) {
    if (node.mesh != null) {
      final prims = doc.meshes[node.mesh!].primitives;
      if (prims.isNotEmpty) {
        myPrim = prims.first;
        break;
      }
    }
  }
  expect(myPrim, isNotNull);
  final mine = packGltfPrimitive(
    primitive: myPrim!,
    accessors: doc.accessors,
    bufferViews: doc.bufferViews,
    bufferData: container.binaryChunk,
  );

  final modelBytes = File(modelPath).readAsBytesSync();
  final fbScene =
      ImportedScene.fromFlatbuffer(ByteData.sublistView(modelBytes)).flatbuffer;
  fb.MeshPrimitive? theirPrim;
  for (final node in fbScene.nodes ?? <fb.Node>[]) {
    final prims = node.meshPrimitives;
    if (prims != null && prims.isNotEmpty) {
      theirPrim = prims.first;
      break;
    }
  }
  expect(theirPrim, isNotNull);

  Uint8List theirVertexBytes;
  if (expectSkinned) {
    final vb = theirPrim!.vertices as fb.SkinnedVertexBuffer;
    theirVertexBytes = Uint8List.fromList(vb.vertices!);
    expect(mine.isSkinned, isTrue);
  } else {
    final vb = theirPrim!.vertices as fb.UnskinnedVertexBuffer;
    theirVertexBytes = Uint8List.fromList(vb.vertices!);
    expect(mine.isSkinned, isFalse);
  }
  final theirIndexBytes = Uint8List.fromList(theirPrim.indices!.data!);

  print(
    '  mine.vertexBytes=${mine.vertexBytes.length} '
    'theirs=${theirVertexBytes.length} (skinned=${mine.isSkinned})',
  );
  expect(
    _bytesEqual(mine.vertexBytes, theirVertexBytes),
    isTrue,
    reason: 'vertex bytes differ',
  );
  expect(
    _bytesEqual(mine.indexBytes, theirIndexBytes),
    isTrue,
    reason: 'index bytes differ',
  );
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative; // will be reported by caller's existsSync check
}
