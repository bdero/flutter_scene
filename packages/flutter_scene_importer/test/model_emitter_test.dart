// ignore_for_file: avoid_print

/// Compares the byte output of the Dart-side `emitModel` (Phase 2) against
/// the offline C++ importer's `.model` for the same source `.glb`. Aims for
/// structural equivalence — flatbuffer builders may produce different but
/// semantically equal bytes — so this checks per-primitive vertex/index
/// bytes and material fields, not raw `Uint8List` equality of the whole
/// file.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_scene_importer/gltf.dart';
import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/src/fb_emitter/model_emitter.dart';
import 'package:test/test.dart';

void main() {
  for (final asset in const [
    ('fcar', false),
    ('flutter_logo_baked', false),
    ('two_triangles', true),
    ('dash', true),
  ]) {
    final name = asset.$1;
    final skinned = asset.$2;
    test('emitModel($name.glb) ≡ $name.model', () {
      final glbPath = _resolve('examples/assets_src/$name.glb');
      final modelPath = _resolve('examples/flutter_app/build/models/$name.model');
      if (!File(glbPath).existsSync() || !File(modelPath).existsSync()) {
        print('Test data missing — skipping.');
        return;
      }
      _compareSceneBytes(glbPath, modelPath, skinned: skinned);
    });
  }
}

void _compareSceneBytes(
  String glbPath,
  String modelPath, {
  required bool skinned,
}) {
  // Build .model bytes via the Dart emitter.
  final glbBytes = File(glbPath).readAsBytesSync();
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  final myModelBytes = emitModel(doc, container.binaryChunk);

  // Decode both via the existing fb reader.
  final mine = ImportedScene.fromFlatbuffer(
    ByteData.sublistView(myModelBytes),
  ).flatbuffer;
  final theirs = ImportedScene.fromFlatbuffer(
    ByteData.sublistView(File(modelPath).readAsBytesSync()),
  ).flatbuffer;

  // Top-level structure.
  expect(mine.children?.length, theirs.children?.length, reason: 'children count');
  expect(mine.nodes?.length, theirs.nodes?.length, reason: 'nodes count');
  expect(mine.textures?.length ?? 0, theirs.textures?.length ?? 0,
      reason: 'textures count');
  expect(mine.animations?.length ?? 0, theirs.animations?.length ?? 0,
      reason: 'animations count');

  // Scene-level Z-flip.
  expect(mine.transform?.m10, -1.0);

  // Per-node primitive byte equivalence.
  int matched = 0;
  int mismatched = 0;
  final theirByName = <String, fb.Node>{};
  for (final n in theirs.nodes ?? <fb.Node>[]) {
    if (n.name != null) theirByName[n.name!] = n;
  }
  for (final myNode in mine.nodes ?? <fb.Node>[]) {
    if (myNode.name == null) continue;
    final theirNode = theirByName[myNode.name];
    if (theirNode == null) continue;
    final myPrims = myNode.meshPrimitives ?? <fb.MeshPrimitive>[];
    final theirPrims = theirNode.meshPrimitives ?? <fb.MeshPrimitive>[];
    if (myPrims.length != theirPrims.length) {
      mismatched++;
      print('  ${myNode.name}: prim count ${myPrims.length}/${theirPrims.length}');
      continue;
    }
    bool ok = true;
    for (int i = 0; i < myPrims.length; i++) {
      if (!_primitivesEquivalent(myPrims[i], theirPrims[i],
          where: '${myNode.name}[$i]', skinned: skinned)) {
        ok = false;
        break;
      }
    }
    if (ok) {
      matched++;
    } else {
      mismatched++;
    }
  }
  print('  per-node match: $matched matched, $mismatched mismatched');
  expect(mismatched, 0);
  expect(matched, greaterThan(0));

  // Per-skin equivalence — would have caught the vector-of-struct reversal
  // bug fixed in this same commit. Compares the FIRST inverse-bind matrix
  // value, which is enough to detect the symptom (with reversal, mine[0]
  // would equal theirs[last]).
  for (final myNode in mine.nodes ?? <fb.Node>[]) {
    if (myNode.skin == null || myNode.name == null) continue;
    final theirNode = theirByName[myNode.name];
    if (theirNode?.skin == null) continue;
    final myIbm = myNode.skin!.inverseBindMatrices;
    final theirIbm = theirNode!.skin!.inverseBindMatrices;
    if (myIbm == null || theirIbm == null || myIbm.isEmpty) continue;
    expect(myIbm.length, theirIbm.length, reason: '${myNode.name} ibm count');
    expect(myIbm[0].m0, closeTo(theirIbm[0].m0, 1e-6),
        reason: '${myNode.name} ibm[0].m0 (vector reversal regression?)');
    expect(myIbm[0].m12, closeTo(theirIbm[0].m12, 1e-6),
        reason: '${myNode.name} ibm[0].m12');
  }

  // Per-animation equivalence — first channel of first animation, first
  // keyframe value. Same reversal-detection role for keyframe vectors.
  final myAnims = mine.animations ?? <fb.Animation>[];
  final theirAnims = theirs.animations ?? <fb.Animation>[];
  for (int i = 0; i < myAnims.length && i < theirAnims.length; i++) {
    final mc = myAnims[i].channels;
    final tc = theirAnims[i].channels;
    if (mc == null || tc == null || mc.isEmpty || tc.isEmpty) continue;
    final myK = mc[0].keyframes;
    final theirK = tc[0].keyframes;
    if (myK is fb.TranslationKeyframes && theirK is fb.TranslationKeyframes) {
      final mv = myK.values;
      final tv = theirK.values;
      if (mv != null && tv != null && mv.isNotEmpty) {
        expect(mv[0].x, closeTo(tv[0].x, 1e-6),
            reason: 'anim[$i] channel[0] keyframes[0].x');
      }
    }
  }

  // Per-texture equivalence.
  final myTextures = mine.textures ?? <fb.Texture>[];
  final theirTextures = theirs.textures ?? <fb.Texture>[];
  for (int i = 0; i < myTextures.length; i++) {
    final myT = myTextures[i];
    final theirT = theirTextures[i];
    final myEmb = myT.embeddedImage;
    final theirEmb = theirT.embeddedImage;
    if (myEmb == null || theirEmb == null) {
      expect(myEmb, isNull);
      expect(theirEmb, isNull);
      continue;
    }
    expect(myEmb.width, theirEmb.width, reason: 'tex[$i] width');
    expect(myEmb.height, theirEmb.height, reason: 'tex[$i] height');
    expect(myEmb.componentCount, theirEmb.componentCount,
        reason: 'tex[$i] componentCount');
    final myBytes = Uint8List.fromList(myEmb.bytes!);
    final theirBytes = Uint8List.fromList(theirEmb.bytes!);
    expect(myBytes.length, theirBytes.length, reason: 'tex[$i] byte length');
    // Don't byte-compare image bytes — different decoders (package:image
    // vs stb_image used by tinygltf) can produce slightly different RGBA
    // for lossy PNG decodes. Same dimensions + channel count is enough
    // for parity verification.
  }
}

bool _primitivesEquivalent(
  fb.MeshPrimitive my,
  fb.MeshPrimitive their, {
  required String where,
  required bool skinned,
}) {
  final myVB = _vertexBytes(my, skinned);
  final theirVB = _vertexBytes(their, skinned);
  if (myVB == null || theirVB == null) {
    print('  $where: vertex buffer wrong type');
    return false;
  }
  if (!_bytesEqual(myVB, theirVB)) {
    print('  $where: vertex bytes differ '
        '(mine=${myVB.length}, theirs=${theirVB.length})');
    return false;
  }
  final myIB = Uint8List.fromList(my.indices!.data!);
  final theirIB = Uint8List.fromList(their.indices!.data!);
  if (!_bytesEqual(myIB, theirIB)) {
    print('  $where: index bytes differ');
    return false;
  }
  final myM = my.material!;
  final theirM = their.material!;
  if (myM.type != theirM.type) {
    print('  $where: material.type ${myM.type}/${theirM.type}');
    return false;
  }
  return true;
}

Uint8List? _vertexBytes(fb.MeshPrimitive p, bool skinned) {
  if (skinned) {
    final v = p.vertices as fb.SkinnedVertexBuffer?;
    return v == null ? null : Uint8List.fromList(v.vertices!);
  }
  final v = p.vertices as fb.UnskinnedVertexBuffer?;
  return v == null ? null : Uint8List.fromList(v.vertices!);
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _resolve(String relative) {
  for (final prefix in ['', '../../', '../../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative;
}
