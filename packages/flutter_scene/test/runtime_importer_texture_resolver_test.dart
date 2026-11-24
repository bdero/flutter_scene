// Covers GltfTextureResolver routing for external images in .gltf and .glb
// documents.
//
// Headless `flutter test` has no Flutter GPU, so a resolver that returns a
// real texture cannot be exercised here, and the placeholder bound for an
// unresolved image fails to build. Each case returns null or throws from the
// resolver, then tolerates that specific GPU-absence failure and asserts what
// happened before it: the resolver's arguments and the recorded warnings.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_scene/src/runtime_importer/texture_builder.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [body], tolerating only the failure raised when it reaches GPU work.
Future<void> _untilGpu(Future<void> Function() body) async {
  try {
    await body();
  } catch (e) {
    // The wording differs across engine versions.
    expect(e.toString(), anyOf(contains('Impeller'), contains('Flutter GPU')));
  }
}

/// A GLB container holding [json] and no BIN chunk.
Uint8List _glb(Map<String, Object?> json) {
  final jsonBytes = utf8.encode(jsonEncode(json));
  final padded = Uint8List((jsonBytes.length + 3) & ~3)
    ..fillRange(0, (jsonBytes.length + 3) & ~3, 0x20)
    ..setAll(0, jsonBytes);
  final out = ByteData(12 + 8 + padded.length);
  out.setUint32(0, 0x46546C67, Endian.little); // 'glTF'
  out.setUint32(4, 2, Endian.little);
  out.setUint32(8, out.lengthInBytes, Endian.little);
  out.setUint32(12, padded.length, Endian.little);
  out.setUint32(16, 0x4E4F534A, Endian.little); // 'JSON'
  final bytes = out.buffer.asUint8List();
  bytes.setAll(20, padded);
  return bytes;
}

void main() {
  test('each external image reaches the texture resolver decoded, with the '
      'content of the material slot that samples it', () async {
    final doc = GltfDocument(
      materials: [
        GltfMaterial(
          pbrMetallicRoughness: GltfPbrMetallicRoughness(
            baseColorTexture: GltfTextureInfo(index: 0),
          ),
          normalTexture: GltfTextureInfo(index: 1),
        ),
      ],
      textures: [GltfTexture(source: 0), GltfTexture(source: 1)],
      images: [
        GltfImage(uri: '../Textures/base%20color.png'),
        GltfImage(uri: '../Textures/normal.ktx2'),
      ],
    );
    final calls = <(String, TextureContent)>[];
    var byteResolverCalls = 0;

    await _untilGpu(() async {
      await buildTextures(
        doc,
        Uint8List(0),
        resolveUri: (uri) async {
          byteResolverCalls++;
          return Uint8List(0);
        },
        resolveTexture: (uri, content) async {
          calls.add((uri, content));
          return null;
        },
        onWarning: (_) {},
      );
    });

    expect(calls, [
      ('../Textures/base color.png', TextureContent.color),
      ('../Textures/normal.ktx2', TextureContent.normal),
    ]);
    expect(byteResolverCalls, 0);
  });

  test('a data: URI image never reaches the texture resolver', () async {
    final doc = GltfDocument(
      textures: [GltfTexture(source: 0)],
      images: [GltfImage(uri: 'data:image/png;base64,AAAA')],
    );
    var resolverCalls = 0;

    await _untilGpu(() async {
      await buildTextures(
        doc,
        Uint8List(0),
        resolveTexture: (uri, content) async {
          resolverCalls++;
          return null;
        },
        onWarning: (_) {},
      );
    });

    expect(resolverCalls, 0);
  });

  test('a texture resolver returning null warns with the URI', () async {
    final doc = GltfDocument(
      textures: [GltfTexture(source: 0)],
      images: [GltfImage(uri: '../Textures/missing.png')],
    );
    final warnings = <GltfImportWarning>[];

    await _untilGpu(() async {
      await buildTextures(
        doc,
        Uint8List(0),
        resolveTexture: (uri, content) async => null,
        onWarning: warnings.add,
      );
    });

    expect(warnings, hasLength(1));
    expect(warnings.single.message, contains('../Textures/missing.png'));
  });

  test(
    'a throwing texture resolver warns with the URI and the error',
    () async {
      final doc = GltfDocument(
        textures: [GltfTexture(source: 0)],
        images: [GltfImage(uri: '../Textures/broken.png')],
      );
      final warnings = <GltfImportWarning>[];

      await _untilGpu(() async {
        await buildTextures(
          doc,
          Uint8List(0),
          resolveTexture: (uri, content) async =>
              throw const FormatException('no such file'),
          onWarning: warnings.add,
        );
      });

      expect(warnings, hasLength(1));
      expect(warnings.single.message, contains('../Textures/broken.png'));
      expect(warnings.single.message, contains('no such file'));
    },
  );

  test('textures sharing an image and role ask the resolver once', () async {
    final doc = GltfDocument(
      materials: [
        GltfMaterial(
          pbrMetallicRoughness: GltfPbrMetallicRoughness(
            baseColorTexture: GltfTextureInfo(index: 0),
          ),
          emissiveTexture: GltfTextureInfo(index: 1),
        ),
      ],
      textures: [GltfTexture(source: 0), GltfTexture(source: 0, sampler: 0)],
      samplers: [GltfSampler()],
      images: [GltfImage(uri: '../Textures/shared.png')],
    );
    final calls = <String>[];

    await _untilGpu(() async {
      await buildTextures(
        doc,
        Uint8List(0),
        resolveTexture: (uri, content) async {
          calls.add(uri);
          return null;
        },
        onWarning: (_) {},
      );
    });

    expect(calls, ['../Textures/shared.png']);
  });

  test('a malformed percent-encoded URI warns instead of throwing', () async {
    final doc = GltfDocument(
      textures: [GltfTexture(source: 0)],
      images: [GltfImage(uri: '100%_albedo.png')],
    );

    for (final withResolver in [false, true]) {
      final warnings = <GltfImportWarning>[];
      var resolverCalls = 0;
      await _untilGpu(() async {
        await buildTextures(
          doc,
          Uint8List(0),
          resolveTexture: withResolver
              ? (uri, content) async {
                  resolverCalls++;
                  return null;
                }
              : null,
          onWarning: warnings.add,
        );
      });
      expect(resolverCalls, 0, reason: 'resolver: $withResolver');
      expect(warnings, hasLength(1), reason: 'resolver: $withResolver');
      expect(warnings.single.message, contains('100%_albedo.png'));
    }
  });

  test('importGlb routes an external image to the texture resolver', () async {
    final glb = _glb({
      'asset': {'version': '2.0'},
      'textures': [
        {'source': 0},
      ],
      'images': [
        {'mimeType': 'image/png', 'uri': '../Textures/albedo.png'},
      ],
    });
    final received = <String>[];

    await _untilGpu(() async {
      await importGlb(
        glb,
        resolveTexture: (uri, content) async {
          received.add(uri);
          return null;
        },
        onWarning: (_) {},
      );
    });

    expect(received, ['../Textures/albedo.png']);
  });
}
