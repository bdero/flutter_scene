// Covers the glTF importer's optional KTX2 texture compression. Runs only when
// the source GLB corpus is present (CI without it skips). The GPU upload is
// verified in the example app; here we check the importer emits KTX2 payloads,
// that the container shrinks, and that the payload decodes back to the image.

import 'dart:io';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_test/flutter_test.dart';

String _resolve(String relative) {
  for (final prefix in ['', '../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync()) return candidate;
  }
  return relative;
}

void main() {
  group('importer texture compression', () {
    const name = 'flutter_logo_baked.glb'; // 1 texture

    Uint8List? load() {
      final file = File(_resolve('examples/assets_src/$name'));
      if (!file.existsSync()) {
        // ignore: avoid_print
        print('Test data missing ($name) - skipping.');
        return null;
      }
      return file.readAsBytesSync();
    }

    test('emits ktx2 texture payloads when asked, rgba8 otherwise', () {
      final glb = load();
      if (glb == null) return;

      final plain = importGlbToSceneDocument(glb);
      final compressed = importGlbToSceneDocument(glb, compressTextures: true);

      final plainTexPayloads = _imagePayloads(plain);
      final compressedTexPayloads = _imagePayloads(compressed);
      expect(plainTexPayloads, isNotEmpty);
      expect(compressedTexPayloads, hasLength(plainTexPayloads.length));
      expect(plainTexPayloads.every((p) => p.format == 'rgba8'), isTrue);
      expect(compressedTexPayloads.every((p) => p.format == 'ktx2'), isTrue);
    });

    test('shrinks the .fsceneb container', () {
      final glb = load();
      if (glb == null) return;

      final plain = importGlbToFscenebBytes(glb);
      final compressed = importGlbToFscenebBytes(glb, compressTextures: true);
      expect(compressed.length, lessThan(plain.length));
    });

    test('ktx2 payloads carry the engine mip chain', () {
      final glb = load();
      if (glb == null) return;

      final document = readFsceneb(
        importGlbToFscenebBytes(glb, compressTextures: true),
      );
      for (final payload in _imagePayloads(document)) {
        final texture = readKtx2(payload.bytes!);
        expect(
          texture.levels,
          hasLength(engineMipLevelCount(payload.width!, payload.height!)),
        );
        for (var level = 0; level < texture.levels.length; level++) {
          final size = mipSize(payload.width!, payload.height!, level);
          final decoded = decodeKtx2Level(texture, level: level);
          expect(decoded.width, size.width);
          expect(decoded.height, size.height);
        }
      }
    });

    test('ktx2 payloads decode back to the source image dimensions', () {
      final glb = load();
      if (glb == null) return;

      // Re-read through the container codec to exercise the real load path.
      final document = readFsceneb(
        importGlbToFscenebBytes(glb, compressTextures: true),
      );
      final payloads = _imagePayloads(document);
      for (final payload in payloads) {
        final texture = readKtx2(payload.bytes!);
        final decoded = decodeKtx2Level(texture);
        expect(decoded.width, payload.width);
        expect(decoded.height, payload.height);
      }
    });
  });
}

List<PayloadSpec> _imagePayloads(SceneDocument document) => [
  for (final payload in document.payloads.values)
    if (payload.encoding == PayloadEncoding.image) payload,
];
