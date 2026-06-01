// Compiles the package for the web. Importing the public API forces the
// js_interop backend (factory -> WasmRapierBindings -> WasmRuntime) to
// build; a stray dart:ffi import anywhere on the web path would fail the
// dart2js compile. Constructing a world needs the wasm module loaded, so
// this only checks the entry point compiles and is reachable.

@TestOn('browser')
library;

import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:test/test.dart';

void main() {
  test('public API compiles and links on web', () {
    expect(RapierWorld.ensureInitialized, isA<Function>());
  });
}
