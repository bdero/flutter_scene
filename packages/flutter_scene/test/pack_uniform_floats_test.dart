import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/shader_uniform_bindings.dart';

List<double> _floats(ByteData? bytes) => Float32List.sublistView(bytes!);

void main() {
  test('repacks its own block in place at the same size', () {
    final bindings = ShaderUniformBindings()
      ..setUniformBlockFromFloats('Info', [1, 2, 3, 4]);
    final ownerView = bindings.getUniformBlock('Info');
    bindings.setUniformBlockFromFloats('Info', [5, 6, 7, 8]);

    // Reading the block back released it, so the repack allocated.
    expect(_floats(ownerView), [1, 2, 3, 4]);
    expect(_floats(bindings.getUniformBlock('Info')), [5, 6, 7, 8]);
  });

  test('reuses an unobserved block', () {
    final packed = PackedFloatBlocks();
    final first = packed.pack('Info', null, [1, 2, 3, 4]);
    final second = packed.pack('Info', first, [5, 6, 7, 8]);

    expect(identical(first, second), isTrue);
    expect(_floats(second), [5, 6, 7, 8]);
  });

  test('allocates when the size changes', () {
    final packed = PackedFloatBlocks();
    final first = packed.pack('Info', null, [1, 2, 3, 4]);
    final second = packed.pack('Info', first, [1, 2, 3, 4, 5, 6, 7, 8]);

    expect(identical(first, second), isFalse);
  });

  test('never writes into a block another binding owns', () {
    final a = ShaderUniformBindings()
      ..setUniformBlockFromFloats('Info', [1, 2, 3, 4]);
    final b = ShaderUniformBindings()
      ..setUniformBlock('Info', a.getUniformBlock('Info'));
    b.setUniformBlockFromFloats('Info', [5, 6, 7, 8]);
    a.setUniformBlockFromFloats('Info', [9, 9, 9, 9]);

    expect(_floats(b.getUniformBlock('Info')), [5, 6, 7, 8]);
    expect(_floats(a.getUniformBlock('Info')), [9, 9, 9, 9]);
  });

  test('never writes into a block the caller supplied', () {
    final supplied = ByteData.sublistView(Float32List.fromList([9, 9, 9, 9]));
    final bindings = ShaderUniformBindings()
      ..setUniformBlock('Info', supplied)
      ..setUniformBlockFromFloats('Info', [1, 2, 3, 4]);

    expect(_floats(supplied), [9, 9, 9, 9]);
    expect(_floats(bindings.getUniformBlock('Info')), [1, 2, 3, 4]);
  });
}
