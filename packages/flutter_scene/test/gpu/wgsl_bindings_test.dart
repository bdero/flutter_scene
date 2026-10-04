// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/shared/wgsl_bindings.dart';
import 'package:flutter_test/flutter_test.dart';

WgslReflectedResource _ubo(String name, int binding) =>
    (name: name, binding: binding, kind: WgslResourceKind.uniformBuffer);

WgslReflectedResource _tex(String name, int binding) => (
  name: name,
  binding: binding,
  kind: WgslResourceKind.combinedTextureSampler,
);

void main() {
  group('WgslBindingMap.predict', () {
    test('leaves a lone uniform buffer where it was', () {
      final map = WgslBindingMap.predict([_ubo('FrameInfo', 0)]);
      expect(map['FrameInfo']!.textureBinding, 0);
      expect(map['FrameInfo']!.samplerBinding, isNull);
      expect(map['FrameInfo']!.group, 0);
    });

    test('gives a combined sampler two consecutive slots', () {
      final map = WgslBindingMap.predict([_tex('albedo', 65)]);
      expect(map['albedo']!.textureBinding, 65);
      expect(map['albedo']!.samplerBinding, 66);
    });

    // Matches UnlitFragment in the real base bundle.
    test('displaces later resources past an inserted sampler', () {
      final map = WgslBindingMap.predict([
        _ubo('FogInfo', 66),
        _ubo('FragInfo', 64),
        _tex('base_color_texture', 65),
      ]);
      expect(map['FragInfo']!.textureBinding, 64);
      expect(map['base_color_texture']!.textureBinding, 65);
      expect(map['base_color_texture']!.samplerBinding, 66);
      expect(map['FogInfo']!.textureBinding, 67);
    });

    // Matches SsrCompositeFragment, two textures ahead of a uniform.
    test('accumulates displacement across several samplers', () {
      final map = WgslBindingMap.predict([
        _ubo('CompositeInfo', 66),
        _tex('ssr_reflection', 65),
        _tex('input_color', 64),
      ]);
      expect(map['input_color']!.textureBinding, 64);
      expect(map['input_color']!.samplerBinding, 65);
      expect(map['ssr_reflection']!.textureBinding, 66);
      expect(map['ssr_reflection']!.samplerBinding, 67);
      expect(map['CompositeInfo']!.textureBinding, 68);
    });

    // The case that disproved packing densely. Impellerc leaves a gap when a
    // shader mixes vertex-stage bindings with fragment-stage ones.
    test('preserves gaps rather than packing densely', () {
      final map = WgslBindingMap.predict([
        _ubo('VertInfo', 0),
        _ubo('FragInfo', 66),
      ]);
      expect(map['VertInfo']!.textureBinding, 0);
      expect(map['FragInfo']!.textureBinding, 66);
    });

    test('is independent of input order', () {
      final a = WgslBindingMap.predict([
        _ubo('A', 64),
        _tex('T', 65),
        _ubo('B', 66),
      ]);
      final b = WgslBindingMap.predict([
        _ubo('B', 66),
        _ubo('A', 64),
        _tex('T', 65),
      ]);
      expect(b.bindings, a.bindings);
    });

    test('rejects duplicate names', () {
      expect(
        () => WgslBindingMap.predict([_ubo('X', 0), _ubo('X', 1)]),
        throwsA(isA<WgslBindingMismatch>()),
      );
    });

    test('occupiedBindings lists every slot in order', () {
      final map = WgslBindingMap.predict([_ubo('A', 64), _tex('T', 65)]);
      expect(map.occupiedBindings, [64, 65, 66]);
    });

    test('handles an empty shader', () {
      expect(WgslBindingMap.predict([]).bindings, isEmpty);
    });
  });

  group('WgslBindingMap.mapped', () {
    test(
      'keeps bundle bindings and parks samplers 128 above their texture',
      () {
        final map = WgslBindingMap.mapped([
          _ubo('FragInfo', 64),
          _tex('a', 65),
          _tex('b', 66),
        ]);
        expect(map['FragInfo']!.textureBinding, 64);
        expect(map['a']!.textureBinding, 65);
        expect(map['a']!.samplerBinding, 193);
        expect(map['b']!.textureBinding, 66);
        expect(map['b']!.samplerBinding, 194);
        expect(map.samplerMappings, {65: 193, 66: 194});
      },
    );

    test('adjacent textures never collide with a sampler', () {
      final map = WgslBindingMap.mapped([
        for (var i = 0; i < 15; i++) _tex('t$i', 64 + i),
      ]);
      expect(map.occupiedBindings.toSet(), hasLength(30));
    });

    test('rejects a resource inside the sampler range', () {
      expect(
        () => WgslBindingMap.mapped([_tex('far', 130)]),
        throwsA(isA<WgslBindingMismatch>()),
      );
    });
  });

  group('parseWgslDeclarations', () {
    const wgsl = '''
diagnostic(off, derivative_uniformity);

struct tint_symbol_3 {
  a : vec4<f32>,
}

@group(0u) @binding(64u) var<uniform> v : tint_symbol_3;

@group(0u) @binding(66u) var v_1 : sampler;

@group(0u) @binding(65u) var v_2 : texture_2d<f32>;

var<private> v_3 : vec4<f32>;
''';

    test('finds each resource and classifies it', () {
      final decls = parseWgslDeclarations(wgsl);
      expect(decls.length, 3);
      expect(
        decls.firstWhere((d) => d.binding == 64).kind,
        WgslDeclarationKind.uniform,
      );
      expect(
        decls.firstWhere((d) => d.binding == 65).kind,
        WgslDeclarationKind.texture,
      );
      expect(
        decls.firstWhere((d) => d.binding == 66).kind,
        WgslDeclarationKind.sampler,
      );
    });

    test('ignores private module-scope variables', () {
      expect(parseWgslDeclarations(wgsl).every((d) => d.group == 0), isTrue);
    });

    test('accepts bindings written without the u suffix', () {
      final decls = parseWgslDeclarations(
        '@group(1) @binding(3) var s : sampler;',
      );
      expect(decls.single.group, 1);
      expect(decls.single.binding, 3);
      expect(decls.single.kind, WgslDeclarationKind.sampler);
    });

    test('classifies comparison samplers as samplers', () {
      final decls = parseWgslDeclarations(
        '@group(0) @binding(0) var s : sampler_comparison;',
      );
      expect(decls.single.kind, WgslDeclarationKind.sampler);
    });
  });

  group('verifyAgainstWgsl', () {
    test('accepts WGSL that matches the prediction', () {
      final map = WgslBindingMap.predict([
        _ubo('FragInfo', 64),
        _tex('albedo', 65),
      ]);
      map.verifyAgainstWgsl('''
@group(0u) @binding(64u) var<uniform> v : S;
@group(0u) @binding(65u) var v_1 : texture_2d<f32>;
@group(0u) @binding(66u) var v_2 : sampler;
''');
    });

    test('throws when Tint assigns a different slot', () {
      final map = WgslBindingMap.predict([
        _ubo('FragInfo', 64),
        _tex('albedo', 65),
      ]);
      expect(
        () => map.verifyAgainstWgsl('''
@group(0u) @binding(64u) var<uniform> v : S;
@group(0u) @binding(65u) var v_1 : texture_2d<f32>;
@group(0u) @binding(99u) var v_2 : sampler;
'''),
        throwsA(isA<WgslBindingMismatch>()),
      );
    });

    test('throws when a resource is missing entirely', () {
      final map = WgslBindingMap.predict([_tex('albedo', 65)]);
      expect(
        () => map.verifyAgainstWgsl(
          '@group(0u) @binding(65u) var v : texture_2d<f32>;',
        ),
        throwsA(isA<WgslBindingMismatch>()),
      );
    });

    test('names the shader in the failure message', () {
      final map = WgslBindingMap.predict([_ubo('FragInfo', 64)]);
      expect(
        () => map.verifyAgainstWgsl('', shaderName: 'StandardFragment'),
        throwsA(
          isA<WgslBindingMismatch>().having(
            (e) => e.message,
            'message',
            contains('StandardFragment'),
          ),
        ),
      );
    });
  });
}
