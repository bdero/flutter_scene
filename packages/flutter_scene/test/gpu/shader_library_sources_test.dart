// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/shader_library_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A cached library is handed out again by every load of its asset key, and
  // the reflection cache treats a replaced source as a rewritten bundle, so a
  // repeat load of the same key must keep the source it registered first.
  test('a library loaded again under the same asset key keeps its source', () {
    final library = Object();
    const key = 'shaders/a.shaderbundle';
    final first = ShaderLibrarySource(assetKey: key);
    registerShaderLibrarySource(library, first);
    registerShaderLibrarySource(library, ShaderLibrarySource(assetKey: key));
    expect(shaderLibrarySourceOf(library), same(first));
    expect(
      knownShaderLibraries().where((known) => identical(known, library)),
      hasLength(1),
    );
  });

  test('a library registered under new bytes takes the new source', () {
    final library = Object();
    registerShaderLibrarySource(
      library,
      ShaderLibrarySource(bytes: ByteData(4)),
    );
    final next = ShaderLibrarySource(bytes: ByteData(8));
    registerShaderLibrarySource(library, next);
    expect(shaderLibrarySourceOf(library), same(next));
  });
}
