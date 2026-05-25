// PostEffect and ShaderUniformBindings accessor/storage tests. The GPU
// bind path requires a real Flutter GPU context and is exercised by the
// example app, not by unit tests.

import 'dart:typed_data';

import 'package:flutter_scene/src/post_process/post_effect.dart';
import 'package:flutter_scene/src/shader_uniform_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostEffect defaults', () {
    test('insertion, enabled, and useFrameInfo', () {
      final effect = PostEffect();
      expect(effect.insertion, PostInsertion.beforeTonemap);
      expect(effect.enabled, isTrue);
      expect(effect.useFrameInfo, isFalse);
    });

    test('fragmentShader throws until set', () {
      expect(() => PostEffect().fragmentShader, throwsStateError);
    });
  });

  group('PostEffect uniform storage', () {
    test('setUniformBlock round-trips ByteData', () {
      final effect = PostEffect();
      final bytes = ByteData.sublistView(Float32List.fromList([1, 2, 3]));
      effect.setUniformBlock('Params', bytes);
      expect(effect.getUniformBlock('Params'), same(bytes));
      expect(effect.uniformBlockNames, contains('Params'));
    });

    test('setUniformBlockFromFloats packs as Float32List', () {
      final effect = PostEffect();
      effect.setUniformBlockFromFloats('Params', [0.5, 1.0]);
      final bytes = effect.getUniformBlock('Params');
      expect(bytes, isNotNull);
      expect(bytes!.lengthInBytes, 8);
      expect(bytes.getFloat32(0, Endian.host), 0.5);
      expect(bytes.getFloat32(4, Endian.host), 1.0);
    });

    test('setUniformBlock(null) clears the binding', () {
      final effect = PostEffect();
      effect.setUniformBlockFromFloats('Params', [1]);
      effect.setUniformBlock('Params', null);
      expect(effect.getUniformBlock('Params'), isNull);
      expect(effect.uniformBlockNames, isNot(contains('Params')));
    });
  });

  group('ShaderUniformBindings', () {
    test('round-trips and clears uniform blocks', () {
      final bindings = ShaderUniformBindings();
      final bytes = ByteData.sublistView(Float32List.fromList([1, 2]));
      bindings.setUniformBlock('A', bytes);
      expect(bindings.getUniformBlock('A'), same(bytes));
      expect(bindings.uniformBlockNames, contains('A'));
      bindings.setUniformBlock('A', null);
      expect(bindings.getUniformBlock('A'), isNull);
    });
  });
}
