import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/shader_uniform_bindings.dart';

void main() {
  test('reuses a block it packed earlier at the same size', () {
    final first = packUniformFloats(null, [1, 2, 3, 4]);
    final second = packUniformFloats(first, [5, 6, 7, 8]);

    expect(identical(first, second), isTrue);
    expect(Float32List.sublistView(second), [5, 6, 7, 8]);
  });

  test('allocates a new block when the size changes', () {
    final first = packUniformFloats(null, [1, 2, 3, 4]);
    final second = packUniformFloats(first, [1, 2, 3, 4, 5, 6, 7, 8]);

    expect(identical(first, second), isFalse);
    expect(Float32List.sublistView(first), [1, 2, 3, 4]);
  });

  test('never writes into a block the caller supplied', () {
    final callers = ByteData.sublistView(Float32List.fromList([9, 9, 9, 9]));
    final packed = packUniformFloats(callers, [1, 2, 3, 4]);

    expect(identical(callers, packed), isFalse);
    expect(Float32List.sublistView(callers), [9, 9, 9, 9]);
    expect(Float32List.sublistView(packed), [1, 2, 3, 4]);
  });
}
