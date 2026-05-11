// ShaderMaterial accessor and storage tests. The actual GPU bind
// path (RenderPass binding via getUniformSlot) requires a real
// Flutter GPU context and is exercised by the example app smoke test,
// not by unit tests.

import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShaderMaterial uniform block storage', () {
    test('setUniformBlock round-trips ByteData', () {
      final material = ShaderMaterial();
      final bytes = ByteData.sublistView(Float32List.fromList([1, 2, 3]));
      material.setUniformBlock('FragInfo', bytes);
      expect(material.getUniformBlock('FragInfo'), same(bytes));
      expect(material.uniformBlockNames, contains('FragInfo'));
    });

    test('setUniformBlock(null) clears the binding', () {
      final material = ShaderMaterial();
      material.setUniformBlock(
        'FragInfo',
        ByteData.sublistView(Float32List.fromList([1])),
      );
      material.setUniformBlock('FragInfo', null);
      expect(material.getUniformBlock('FragInfo'), isNull);
      expect(material.uniformBlockNames, isNot(contains('FragInfo')));
    });

    test('setUniformBlockFromFloats packs as Float32List', () {
      final material = ShaderMaterial();
      material.setUniformBlockFromFloats('FragInfo', [0.5, 1.0, 1.5, 2.0]);
      final bytes = material.getUniformBlock('FragInfo');
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, 16);
      expect(bytes.getFloat32(0, Endian.host), 0.5);
      expect(bytes.getFloat32(4, Endian.host), 1.0);
      expect(bytes.getFloat32(8, Endian.host), 1.5);
      expect(bytes.getFloat32(12, Endian.host), 2.0);
    });

    test('multiple uniform blocks remain independently addressable', () {
      final material = ShaderMaterial();
      material.setUniformBlockFromFloats('FragInfo', [1]);
      material.setUniformBlockFromFloats('ExtraInfo', [9, 9]);
      expect(
        material.uniformBlockNames,
        containsAll(['FragInfo', 'ExtraInfo']),
      );
      expect(material.getUniformBlock('FragInfo')!.lengthInBytes, 4);
      expect(material.getUniformBlock('ExtraInfo')!.lengthInBytes, 8);
    });
  });

  // Texture storage uses the same Map-backed pattern as uniform blocks
  // and shares an implementation path. Constructing a real
  // `gpu.Texture` requires a Flutter GPU context, so binding behavior
  // for textures is covered by the integration smoke test (the toon
  // example) rather than unit tests.

  group('ShaderMaterial render-state flags', () {
    test('isOpaque mirrors isOpaqueOverride', () {
      final opaque = ShaderMaterial();
      expect(opaque.isOpaque(), isTrue);
      opaque.isOpaqueOverride = false;
      expect(opaque.isOpaque(), isFalse);
    });
  });
}
