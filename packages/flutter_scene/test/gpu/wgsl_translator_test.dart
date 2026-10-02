// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';
import 'package:flutter_scene/src/gpu/shared/wgsl_translator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what it was asked for and returns canned WGSL.
class _FakeTranslator implements WgslTranslator {
  _FakeTranslator(this._respond);

  final String Function(String shaderName, Map<int, int> samplerBindings)
  _respond;

  int initializeCount = 0;
  int translateCount = 0;
  final List<Map<int, int>> samplerBindingCalls = [];

  @override
  Future<void> initialize() async => initializeCount++;

  @override
  String get revision => 'fake';

  @override
  String translate(
    Uint32List spirv, {
    required String shaderName,
    Map<int, int> samplerBindings = const {},
    bool allowNonUniformDerivatives = true,
    bool minify = false,
  }) {
    translateCount++;
    samplerBindingCalls.add(samplerBindings);
    return _respond(shaderName, samplerBindings);
  }
}

final _spirv = Uint32List.fromList([0x07230203, 0x00010300, 0, 1, 0]);

List<WgslReflectedResource> _resources() => [
  (name: 'FragInfo', binding: 64, kind: WgslResourceKind.uniformBuffer),
  (name: 'albedo', binding: 65, kind: WgslResourceKind.combinedTextureSampler),
];

const _matchingWgsl = '''
@group(0u) @binding(64u) var<uniform> v : S;
@group(0u) @binding(65u) var v_1 : texture_2d<f32>;
@group(0u) @binding(193u) var v_2 : sampler;
''';

void main() {
  group('WgslTranslationCache', () {
    test('translates on a miss and memoizes after', () {
      final t = _FakeTranslator((_, _) => _matchingWgsl);
      final cache = WgslTranslationCache(t);

      final a = cache.get('Unlit', _spirv, _resources());
      final b = cache.get('Unlit', _spirv, _resources());

      expect(t.translateCount, 1);
      expect(cache.length, 1);
      expect(b.wgsl, a.wgsl);
      expect(b.bindings.bindings, a.bindings.bindings);
    });

    test('retranslates when the generation changes', () {
      final t = _FakeTranslator((_, _) => _matchingWgsl);
      final cache = WgslTranslationCache(t);

      cache.get('Unlit', _spirv, _resources());
      cache.get('Unlit', _spirv, _resources(), generation: 1);

      expect(t.translateCount, 2);
    });

    test('asks the translator to place the split sampler', () {
      final t = _FakeTranslator((_, _) => _matchingWgsl);
      WgslTranslationCache(t).get('Unlit', _spirv, _resources());

      // albedo is a combined sampler at 65, so its sampler belongs at 65 + 128.
      expect(t.samplerBindingCalls.single, {65: 193});
    });

    test('exposes the predicted bindings alongside the source', () {
      final cache = WgslTranslationCache(
        _FakeTranslator((_, _) => _matchingWgsl),
      );
      final result = cache.get('Unlit', _spirv, _resources());

      expect(result.bindings['FragInfo']!.textureBinding, 64);
      expect(result.bindings['albedo']!.textureBinding, 65);
      expect(result.bindings['albedo']!.samplerBinding, 193);
    });

    test('throws when the translator disagrees with the prediction', () {
      final cache = WgslTranslationCache(
        _FakeTranslator(
          (_, _) => '@group(0u) @binding(99u) var v : texture_2d<f32>;',
        ),
      );
      expect(
        () => cache.get('Unlit', _spirv, _resources()),
        throwsA(
          isA<WgslTranslationException>().having(
            (e) => e.shaderName,
            'shaderName',
            'Unlit',
          ),
        ),
      );
    });

    test('skips verification when asked', () {
      final cache = WgslTranslationCache(_FakeTranslator((_, _) => 'garbage'));
      expect(
        cache.get('Unlit', _spirv, _resources(), verify: false).wgsl,
        'garbage',
      );
    });

    test('evict drops one entry and clear drops all', () {
      final t = _FakeTranslator((_, _) => _matchingWgsl);
      final cache = WgslTranslationCache(t);

      cache.get('A', _spirv, _resources());
      cache.get('B', _spirv, _resources());
      expect(cache.length, 2);

      cache.evict('A');
      expect(cache.length, 1);

      cache.clear();
      expect(cache.length, 0);
    });

    test('caches each shader independently', () {
      final t = _FakeTranslator((name, _) => _matchingWgsl);
      final cache = WgslTranslationCache(t);

      cache.get('A', _spirv, _resources());
      cache.get('B', _spirv, _resources());
      cache.get('A', _spirv, _resources());

      expect(t.translateCount, 2);
    });
  });

  group('WgslTranslationException', () {
    test('names the shader and the reason', () {
      final e = WgslTranslationException('StandardFragment', 'bad opcode');
      expect(e.toString(), contains('StandardFragment'));
      expect(e.toString(), contains('bad opcode'));
    });
  });
}
