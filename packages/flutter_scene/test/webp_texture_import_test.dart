// Covers EXT_texture_webp: the WebP source winning over the fallback, and the
// offline importer decoding the WebP image it picks.

import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

// A 2x1 lossless WebP: red, then blue.
final _webp = Uint8List.fromList([
  82, 73, 70, 70, 30, 0, 0, 0, 87, 69, 66, 80, 86, 80, 56, 76, 17, 0, 0, 0, //
  47, 1, 0, 0, 0, 15, 16, 243, 191, 255, 243, 31, 14, 50, 162, 255, 1, 0,
]);

// A 1x1 green PNG, the fallback.
final _png = Uint8List.fromList([
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, //
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, //
  120, 218, 99, 96, 248, 207, 240, 31, 0, 4, 1, 1, 255, 174, 181, 85, 245, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

void main() {
  test('a WebP source wins over the fallback', () {
    final doc = parseGltfJson(<String, Object?>{
      'extensionsUsed': ['EXT_texture_webp'],
      'extensionsRequired': ['EXT_texture_webp'],
      'textures': [
        {
          'source': 0,
          'extensions': {
            'EXT_texture_webp': {'source': 1},
          },
        },
        {
          'extensions': {
            'EXT_texture_webp': {'source': 2},
          },
        },
        {'source': 3},
      ],
    });

    expect(doc.warnings, isEmpty);
    expect([for (final t in doc.textures) t.webpSource], [1, 2, null]);
    expect([for (final t in doc.textures) t.imageSource], [1, 2, 3]);
  });

  test('the offline importer decodes the WebP image', () {
    final doc = GltfDocument(
      bufferViews: [
        GltfBufferView(buffer: 0, byteLength: _png.length),
        GltfBufferView(
          buffer: 0,
          byteOffset: _png.length,
          byteLength: _webp.length,
        ),
      ],
      images: [
        GltfImage(bufferView: 0, mimeType: 'image/png'),
        GltfImage(bufferView: 1, mimeType: 'image/webp'),
      ],
      textures: [GltfTexture(source: 0, webpSource: 1)],
    );

    final document = buildSceneDocument(
      doc,
      Uint8List.fromList([..._png, ..._webp]),
    );
    final texture = document.resources.values
        .whereType<TextureResource>()
        .single;
    final payload = document.payloads[texture.payload]!;

    expect([payload.width, payload.height], [2, 1]);
    expect(payload.bytes, [255, 0, 0, 255, 0, 0, 255, 255]);
  });
}
