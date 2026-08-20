// Covers the runtime importer's multi-buffer normalization, percent-decoded
// URI resolution, and the asymmetric buffer/image resolver strictness.
//
// Cases that would need a real placeholder or decoded texture touch Flutter
// GPU (Impeller), which headless `flutter test` doesn't provide (see
// test/geometry_validation_test.dart for the same constraint on geometry
// upload). Those cases are built to avoid GPU entirely (an animation-only
// document has no mesh or material to build), except the two image-path
// tests, which tolerate the downstream "Impeller not enabled" failure and
// instead assert the parts that don't require a real texture: the resolver
// received the decoded URI, and the warning fired before that failure.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/animation.dart'
    show TranslationTimelineResolver;
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/runtime_importer/runtime_importer.dart';
import 'package:flutter_scene/src/runtime_importer/texture_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('multi-buffer runtime import', () {
    test(
      'a two-buffer .gltf imports correctly (bufferViews rebased)',
      () async {
        final times = Float32List.fromList([0.0, 1.0]);
        final values = Float32List.fromList([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
        final data = BytesBuilder();
        final timesOffset = data.length;
        data.add(times.buffer.asUint8List());
        final valuesOffset = data.length;
        data.add(values.buffer.asUint8List());
        final dataBytes = data.toBytes();
        // An odd-length pad buffer at index 0 forces buffer 1's rebase offset
        // to be non-zero and non-trivial, exercising the 4-byte alignment pad.
        final padBytes = Uint8List(5);

        final json = {
          'asset': {'version': '2.0'},
          'nodes': [
            {'name': 'Target'},
          ],
          'buffers': [
            {'byteLength': padBytes.length, 'uri': 'pad.bin'},
            {'byteLength': dataBytes.length, 'uri': 'data.bin'},
          ],
          'bufferViews': [
            {
              'buffer': 1,
              'byteOffset': timesOffset,
              'byteLength': times.lengthInBytes,
            },
            {
              'buffer': 1,
              'byteOffset': valuesOffset,
              'byteLength': values.lengthInBytes,
            },
          ],
          'accessors': [
            {
              'bufferView': 0,
              'componentType': 5126,
              'count': 2,
              'type': 'SCALAR',
            },
            {
              'bufferView': 1,
              'componentType': 5126,
              'count': 2,
              'type': 'VEC3',
            },
          ],
          'animations': [
            {
              'channels': [
                {
                  'sampler': 0,
                  'target': {'node': 0, 'path': 'translation'},
                },
              ],
              'samplers': [
                {'input': 0, 'output': 1},
              ],
            },
          ],
        };
        final files = {'pad.bin': padBytes, 'data.bin': dataBytes};

        final root = await importGltf(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
          resolveUri: (uri) async => files[uri]!,
        );

        final channel = root.parsedAnimations.single.channels.single;
        final resolver = channel.resolver as TranslationTimelineResolver;
        expect(resolver.times, [0.0, 1.0]);
        expect(resolver.values, [Vector3(1, 2, 3), Vector3(4, 5, 6)]);
      },
    );

    test('a percent-encoded buffer URI reaches the resolver decoded', () async {
      final times = Float32List.fromList([0.0, 1.0]);
      final values = Float32List.fromList([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
      final data = BytesBuilder();
      data.add(times.buffer.asUint8List());
      final valuesOffset = data.length;
      data.add(values.buffer.asUint8List());
      final dataBytes = data.toBytes();

      final json = {
        'asset': {'version': '2.0'},
        'nodes': [
          {'name': 'Target'},
        ],
        'buffers': [
          {'byteLength': dataBytes.length, 'uri': 'da%20ta.bin'},
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': times.lengthInBytes},
          {
            'buffer': 0,
            'byteOffset': valuesOffset,
            'byteLength': values.lengthInBytes,
          },
        ],
        'accessors': [
          {
            'bufferView': 0,
            'componentType': 5126,
            'count': 2,
            'type': 'SCALAR',
          },
          {'bufferView': 1, 'componentType': 5126, 'count': 2, 'type': 'VEC3'},
        ],
        'animations': [
          {
            'channels': [
              {
                'sampler': 0,
                'target': {'node': 0, 'path': 'translation'},
              },
            ],
            'samplers': [
              {'input': 0, 'output': 1},
            ],
          },
        ],
      };

      String? received;
      await importGltf(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
        resolveUri: (uri) async {
          received = uri;
          return dataBytes;
        },
      );

      expect(received, 'da ta.bin');
    });

    test('a buffer resolver failure throws', () async {
      final data = Float32List.fromList([0.0, 1.0]).buffer.asUint8List();
      final json = {
        'asset': {'version': '2.0'},
        'nodes': [
          {'name': 'Target'},
        ],
        'buffers': [
          {'byteLength': data.length, 'uri': 'missing.bin'},
        ],
        'bufferViews': [
          {'buffer': 0, 'byteOffset': 0, 'byteLength': data.length},
        ],
        'accessors': [
          {
            'bufferView': 0,
            'componentType': 5126,
            'count': 2,
            'type': 'SCALAR',
          },
        ],
      };

      await expectLater(
        importGltf(
          Uint8List.fromList(utf8.encode(jsonEncode(json))),
          resolveUri: (_) async => throw const FormatException('no such file'),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('image resolution (asymmetric strictness)', () {
    test(
      'a percent-encoded image URI reaches the resolver decoded, and a '
      'resolver failure warns instead of throwing a resolution error',
      () async {
        final doc = GltfDocument(
          textures: [GltfTexture(source: 0)],
          images: [GltfImage(uri: 'my%20image.png')],
        );
        final warnings = <GltfImportWarning>[];
        String? received;

        Object? caught;
        try {
          await buildTextures(
            doc,
            Uint8List(0),
            resolveUri: (uri) async {
              received = uri;
              throw Exception('not found');
            },
            onWarning: warnings.add,
          );
        } catch (e) {
          caught = e;
        }

        // The resolver saw the decoded URI, and the warning was recorded
        // before falling through to placeholder construction. Placeholder
        // construction itself needs a real GPU context this test harness
        // doesn't have; tolerate that failure specifically.
        expect(received, 'my image.png');
        expect(warnings, hasLength(1));
        expect(warnings.single.message, contains('my%20image.png'));
        if (caught != null) {
          expect(caught.toString(), contains('Impeller'));
        }
      },
    );
  });
}
