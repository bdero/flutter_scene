// Covers glTF extensionsRequired/extensionsUsed handling in parseGltfJson.
// Pure-data layer, no Flutter GPU involved, so plain package:test suffices.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';
import 'package:test/test.dart';

void main() {
  group('extensionsRequired', () {
    test('an unsupported required extension throws, naming it', () {
      expect(
        () => parseGltfJson({
          'extensionsRequired': ['XXX_totally_unknown'],
        }),
        throwsA(
          isA<UnsupportedRequiredExtensionException>()
              .having((e) => e.extensions, 'extensions', [
                'XXX_totally_unknown',
              ])
              .having(
                (e) => e.message,
                'message',
                contains('XXX_totally_unknown'),
              ),
        ),
      );
    });

    test('every unsupported required extension is named in one message', () {
      try {
        parseGltfJson({
          'extensionsRequired': ['XXX_first', 'XXX_second'],
        });
        fail('expected UnsupportedRequiredExtensionException');
      } on UnsupportedRequiredExtensionException catch (e) {
        expect(e.extensions, ['XXX_first', 'XXX_second']);
        expect(e.message, allOf(contains('XXX_first'), contains('XXX_second')));
      }
    });

    test(
      'a required extension with planned support says so, not "unsupported"',
      () {
        try {
          parseGltfJson({
            'extensionsRequired': ['KHR_draco_mesh_compression'],
          });
          fail('expected UnsupportedRequiredExtensionException');
        } on UnsupportedRequiredExtensionException catch (e) {
          expect(e.message, contains('support planned'));
          expect(
            e.message,
            isNot(contains('KHR_draco_mesh_compression (unsupported)')),
          );
        }
      },
    );

    test('a recognized required extension does not throw', () {
      expect(
        () => parseGltfJson({
          'extensionsRequired': ['KHR_lights_punctual'],
        }),
        returnsNormally,
      );
    });
  });

  group('extensionsUsed', () {
    test('an unrecognized used extension does not throw, but warns', () {
      final doc = parseGltfJson({
        'extensionsUsed': ['XXX_unused_thing'],
      });
      expect(doc.warnings, hasLength(1));
      expect(doc.warnings.single.message, contains('XXX_unused_thing'));
    });

    test(
      'a used extension with planned support mentions that in the warning',
      () {
        final doc = parseGltfJson({
          'extensionsUsed': ['EXT_meshopt_compression'],
        });
        expect(doc.warnings, hasLength(1));
        expect(doc.warnings.single.message, contains('support planned'));
      },
    );

    test('a recognized used extension produces no warning', () {
      final doc = parseGltfJson({
        'extensionsUsed': ['KHR_materials_unlit'],
      });
      expect(doc.warnings, isEmpty);
    });
  });

  group('importGlbToSceneDocument onWarning threading', () {
    test(
      'an unrecognized extensionsUsed entry loads and reports via onWarning',
      () {
        final bytes = _glb({
          'asset': {'version': '2.0'},
          'extensionsUsed': ['XXX_offline_unused'],
        }, Uint8List(0));

        final warnings = <GltfImportWarning>[];
        final document = importGlbToSceneDocument(
          bytes,
          onWarning: warnings.add,
        );

        expect(document, isNotNull);
        expect(warnings, hasLength(1));
        expect(warnings.single.message, contains('XXX_offline_unused'));
      },
    );
  });
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
