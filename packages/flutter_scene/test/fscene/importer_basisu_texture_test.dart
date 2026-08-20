// Covers the offline cooker's KHR_texture_basisu path: a KTX2 glTF image is
// transcoded to RGBA8 by the same pure-Dart decoder the runtime importer uses,
// so a cooked .fsceneb keeps the texture instead of dropping it.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scene/scene.dart';

// A single-level 32x32 sRGB UASTC file, block aligned so the compressed cook
// keeps it compressed. The .rgba sibling is the reference transcode.
const _ktx2Fixture = 'uastc_alpha_srgb_32.ktx2';
const _rgbaFixture = 'uastc_alpha_srgb_32.rgba';

Uint8List _fixture(String name) =>
    File('test/fixtures/ktx2/$name').readAsBytesSync();

void main() {
  group('offline cooker KHR_texture_basisu', () {
    test('cooks a KTX2 image to the reference rgba8 payload', () {
      final document = importGlbToSceneDocument(
        _basisuGlb(_fixture(_ktx2Fixture)),
      );

      final payload = _imagePayloads(document).single;
      expect(payload.format, 'rgba8');
      expect(payload.width, 32);
      expect(payload.height, 32);
      expect(payload.bytes, _fixture(_rgbaFixture));
    });

    test('compressTextures re-encodes the reference rgba8', () {
      final document = importGlbToSceneDocument(
        _basisuGlb(_fixture(_ktx2Fixture)),
        compressTextures: true,
      );

      final payload = _imagePayloads(document).single;
      expect(payload.format, 'ktx2');
      expect(payload.width, 32);
      expect(payload.height, 32);
      // Byte-exact against the block encoder run on the reference transcode,
      // so the compressor saw the same pixels the runtime route decodes.
      expect(
        payload.bytes,
        encodeImageToKtx2Bytes(
          _fixture(_rgbaFixture),
          32,
          32,
          generateMips: true,
          content: TextureContent.color,
          supercompress: true,
        ),
      );
      expect(
        readKtx2(payload.bytes!).levels,
        hasLength(engineMipLevelCount(32, 32)),
      );
    });

    test('the basisu image wins over the fallback source', () {
      final fallback = Uint8List.fromList(
        img.encodePng(img.Image(width: 1, height: 1)),
      );
      final document = importGlbToSceneDocument(
        _basisuGlb(_fixture(_ktx2Fixture), fallback: fallback),
      );

      final payload = _imagePayloads(document).single;
      expect(payload.width, 32);
      expect(payload.bytes, _fixture(_rgbaFixture));
    });

    test('an engine-format KTX2 image decodes through the internal path', () {
      final source = Uint8List(32 * 32 * 4);
      for (var i = 0; i < source.length; i += 4) {
        source[i] = i % 251;
        source[i + 1] = (i ~/ 4) % 253;
        source[i + 3] = 255;
      }
      final internal = encodeImageToKtx2Bytes(source, 32, 32);
      final document = importGlbToSceneDocument(_basisuGlb(internal));

      final payload = _imagePayloads(document).single;
      expect(payload.format, 'rgba8');
      expect(payload.bytes, decodeKtx2Level(readKtx2(internal)).rgba);
    });

    test(
      'a rejected KTX2 payload degrades to no texture, naming the image',
      () {
        final truncated = Uint8List.sublistView(_fixture(_ktx2Fixture), 0, 200);
        final messages = <String>[];
        final previous = sceneLog;
        sceneLog = messages.add;
        final SceneDocument document;
        try {
          document = importGlbToSceneDocument(_basisuGlb(truncated));
        } finally {
          sceneLog = previous;
        }

        expect(_imagePayloads(document), isEmpty);
        expect(document.resources, isNotEmpty);
        expect(
          messages,
          contains(predicate<String>((m) => m.contains('KTX2 glTF image 0'))),
        );
      },
    );

    test('a rejected KTX2 payload still cooks under compressTextures', () {
      final truncated = Uint8List.sublistView(_fixture(_ktx2Fixture), 0, 200);
      final previous = sceneLog;
      sceneLog = (_) {};
      try {
        final bytes = importGlbToFscenebBytes(
          _basisuGlb(truncated),
          compressTextures: true,
        );
        expect(bytes, isNotEmpty);
        expect(_imagePayloads(readFsceneb(bytes)), isEmpty);
      } finally {
        sceneLog = previous;
      }
    });
  });
}

List<PayloadSpec> _imagePayloads(SceneDocument document) => [
  for (final payload in document.payloads.values)
    if (payload.encoding == PayloadEncoding.image) payload,
];

// A minimal glb whose only material samples a KHR_texture_basisu texture. When
// [fallback] is given it becomes the texture's plain `source` image, which the
// basisu image must win over.
Uint8List _basisuGlb(Uint8List ktx2, {Uint8List? fallback}) {
  final binary = BytesBuilder();
  final images = <Map<String, Object?>>[];
  final views = <Map<String, Object?>>[];
  void addImage(Uint8List bytes, String mimeType) {
    while (binary.length % 4 != 0) {
      binary.addByte(0);
    }
    images.add({'bufferView': views.length, 'mimeType': mimeType});
    views.add({
      'buffer': 0,
      'byteOffset': binary.length,
      'byteLength': bytes.length,
    });
    binary.add(bytes);
  }

  addImage(ktx2, 'image/ktx2');
  if (fallback != null) addImage(fallback, 'image/png');

  final texture = <String, Object?>{
    'extensions': {
      'KHR_texture_basisu': {'source': 0},
    },
  };
  if (fallback != null) texture['source'] = 1;

  return _glb({
    'asset': {'version': '2.0'},
    'extensionsUsed': ['KHR_texture_basisu'],
    'buffers': [
      {'byteLength': binary.length},
    ],
    'bufferViews': views,
    'images': images,
    'textures': [texture],
    'materials': [
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {'index': 0},
        },
      },
    ],
  }, binary.toBytes());
}

Uint8List _glb(Map<String, Object?> json, Uint8List binary) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final jsonLength = (jsonBytes.length + 3) & ~3;
  final binaryLength = (binary.length + 3) & ~3;
  final output = BytesBuilder();
  void uint32(int value) => output.add(
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little),
  );
  output.add(ascii.encode('glTF'));
  uint32(2);
  uint32(12 + 8 + jsonLength + 8 + binaryLength);
  uint32(jsonLength);
  output.add(ascii.encode('JSON'));
  output.add(jsonBytes);
  output.add(
    Uint8List(jsonLength - jsonBytes.length)
      ..fillRange(0, jsonLength - jsonBytes.length, 0x20),
  );
  uint32(binaryLength);
  output.add([0x42, 0x49, 0x4e, 0]);
  output.add(binary);
  output.add(Uint8List(binaryLength - binary.length));
  return output.takeBytes();
}
