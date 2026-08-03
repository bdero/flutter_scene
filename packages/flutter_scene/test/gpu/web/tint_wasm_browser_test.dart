// Verifies the Dart to wasm path end to end against a real tint_wasm build.
//
// Requires the artifact to be served. Build it once with
// tools/tint_wasm/build.sh, then:
//
//   (cd tools/tint_wasm/out && python3 -m http.server 8099 --bind 127.0.0.1 &)
//   dart test -p chrome test/gpu/web/tint_wasm_browser_test.dart
//
// Skips when nothing is listening, so it is inert in CI until the artifact is
// published.
//
// ignore_for_file: implementation_imports
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';
import 'package:flutter_scene/src/gpu/shared/wgsl_translator.dart';
import 'package:flutter_scene/src/gpu/web/tint_wasm_translator.dart';
import 'package:test/test.dart';

/// Where build.sh's output is expected to be served from locally.
const _url = String.fromEnvironment(
  'FLUTTER_SCENE_TINT_WASM_URL',
  defaultValue: 'http://127.0.0.1:8099/tint_wasm.mjs',
);

/// A minimal valid SPIR-V 1.3 fragment shader writing a constant colour.
Uint32List _trivialFragmentSpirv() => Uint32List.fromList(const [
  0x07230203,
  0x00010300,
  0x0008000a,
  0x0000000d,
  0x00000000,
  0x00020011,
  0x00000001,
  0x0006000b,
  0x00000001,
  0x4c534c47,
  0x6474732e,
  0x3035342e,
  0x00000000,
  0x0003000e,
  0x00000000,
  0x00000001,
  0x0006000f,
  0x00000004,
  0x00000004,
  0x6e69616d,
  0x00000000,
  0x00000009,
  0x00030010,
  0x00000004,
  0x00000007,
  0x00040047,
  0x00000009,
  0x0000001e,
  0x00000000,
  0x00020013,
  0x00000002,
  0x00030021,
  0x00000003,
  0x00000002,
  0x00030016,
  0x00000006,
  0x00000020,
  0x00040017,
  0x00000007,
  0x00000006,
  0x00000004,
  0x00040020,
  0x00000008,
  0x00000003,
  0x00000007,
  0x0004003b,
  0x00000008,
  0x00000009,
  0x00000003,
  0x0004002b,
  0x00000006,
  0x0000000a,
  0x00000000,
  0x0004002b,
  0x00000006,
  0x0000000b,
  0x3f800000,
  0x0007002c,
  0x00000007,
  0x0000000c,
  0x0000000a,
  0x0000000a,
  0x0000000a,
  0x0000000b,
  0x00050036,
  0x00000002,
  0x00000004,
  0x00000000,
  0x00000003,
  0x000200f8,
  0x00000005,
  0x0003003e,
  0x00000009,
  0x0000000c,
  0x000100fd,
  0x00010038,
]);

void main() {
  group('TintWasmTranslator', () {
    late TintWasmTranslator translator;
    var available = true;
    var skipReason = '';

    setUpAll(() async {
      translator = TintWasmTranslator(moduleUrl: _url);
      try {
        await translator.initialize();
      } on WgslTranslationException catch (e) {
        available = false;
        skipReason = '$e';
      }
    });

    // markTestSkipped records the skip but does not abort the body, so each
    // test returns early through this.
    bool unavailable() {
      if (available) return false;
      markTestSkipped('no tint_wasm served at $_url ($skipReason)');
      return true;
    }

    test('loads the module and reports a revision', () {
      if (unavailable()) return;
      expect(translator.isReady, isTrue);
      expect(translator.revision, isNot('uninitialized'));
      expect(translator.revision, isNotEmpty);
    });

    test('translates a trivial fragment shader to WGSL', () {
      if (unavailable()) return;
      final wgsl = translator.translate(
        _trivialFragmentSpirv(),
        shaderName: 'Trivial',
      );
      expect(wgsl, contains('@fragment'));
      expect(wgsl, contains('fn '));
    });

    test('reports a useful error for garbage input', () {
      if (unavailable()) return;
      expect(
        () => translator.translate(
          Uint32List.fromList(const [1, 2, 3, 4, 5]),
          shaderName: 'Garbage',
        ),
        throwsA(
          isA<WgslTranslationException>()
              .having((e) => e.shaderName, 'shaderName', 'Garbage')
              .having((e) => e.reason, 'reason', isNotEmpty),
        ),
      );
    });

    test('stays usable after a failed translation', () {
      if (unavailable()) return;
      try {
        translator.translate(
          Uint32List.fromList(const [1, 2, 3, 4, 5]),
          shaderName: 'Garbage',
        );
      } on WgslTranslationException {
        // expected
      }
      expect(
        translator.translate(_trivialFragmentSpirv(), shaderName: 'Trivial'),
        contains('@fragment'),
      );
    });

    test('drives the cache end to end', () {
      if (unavailable()) return;
      final cache = WgslTranslationCache(translator);
      final result = cache.get(
        'Trivial',
        _trivialFragmentSpirv(),
        const <WgslReflectedResource>[],
      );
      expect(result.wgsl, contains('@fragment'));
      expect(cache.length, 1);
    });
  });
}
