// CPU unit tests for the .fmat preprocessor: parsing to the AST, GLSL
// emission, the metadata sidecar, and validation errors. No GPU context is
// needed; the emitted GLSL is exercised end to end by the example app and the
// smoke-render golden tests in later stages.

import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';

const _validLit = '''
material {
  name: "Test",
  shading_model: lit,
  blending: alpha,
  culling: none,
  parameters: [
    { type: vec4, name: tint, hint: source_color, default: [1.0, 0.5, 0.25, 1.0] },
    { type: float, name: strength, hint: range(0, 1, 0.01), default: 0.5 },
    { type: int, name: steps, default: 3 },
    { type: sampler2d, name: detail_texture, hint: default_white },
  ],
}

fragment {
  void Surface(inout MaterialInputs material) {
    vec4 d = texture(detail_texture, GetUV0());
    material.base_color = material_params.tint * d * material_params.strength;
    material.roughness = 0.5;
    PrepareMaterial(material);
  }
}
''';

Matcher _throwsFmat(String messageSubstring) => throwsA(
  isA<FmatException>().having(
    (e) => e.message,
    'message',
    contains(messageSubstring),
  ),
);

void main() {
  group('parse', () {
    test('parses metadata, parameters, hints, and defaults', () {
      final m = parseFmat(_validLit, fileName: 'test.fmat');
      expect(m.name, 'Test');
      expect(m.shadingModel, FmatShadingModel.lit);
      expect(m.blending, FmatBlending.alpha);
      expect(m.culling, FmatCulling.none);
      expect(m.parameters.length, 4);

      expect(m.uniformParameters.map((p) => p.name), [
        'tint',
        'strength',
        'steps',
      ]);
      expect(m.samplerParameters.map((p) => p.name), ['detail_texture']);

      final tint = m.parameters.firstWhere((p) => p.name == 'tint');
      expect(tint.type, FmatType.vec4);
      expect(tint.hint?.kind, FmatHintKind.sourceColor);
      expect(tint.defaultValue, [1.0, 0.5, 0.25, 1.0]);

      final strength = m.parameters.firstWhere((p) => p.name == 'strength');
      expect(strength.hint?.kind, FmatHintKind.range);
      expect(strength.hint?.rangeMin, 0.0);
      expect(strength.hint?.rangeMax, 1.0);
      expect(strength.hint?.rangeStep, 0.01);
      expect(strength.defaultValue, 0.5);

      final steps = m.parameters.firstWhere((p) => p.name == 'steps');
      expect(steps.type, FmatType.int_);
      expect(steps.defaultValue, 3);

      final tex = m.parameters.firstWhere((p) => p.name == 'detail_texture');
      expect(tex.isSampler, isTrue);
      expect(tex.hint?.kind, FmatHintKind.defaultWhite);
    });

    test('applies defaults for omitted shading_model/blending/culling', () {
      final m = parseFmat('''
material { name: "D" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.shadingModel, FmatShadingModel.lit);
      expect(m.blending, FmatBlending.opaque);
      expect(m.culling, FmatCulling.back);
      expect(m.parameters, isEmpty);
    });

    test('tracks the fragment block source line for #line mapping', () {
      // Explicit newlines so the line count is unambiguous: the fragment
      // block keyword is on line 2.
      final m = parseFmat(
        'material { name: "x" }\n'
        'fragment {\n'
        '  void Surface(inout MaterialInputs material) {}\n'
        '}',
      );
      expect(m.fragmentSourceLine, 2);
    });
  });

  group('emit', () {
    test('lit material composes the lighting framework and main()', () {
      final c = compileFmat(_validLit, fileName: 'test.fmat');
      expect(c.glsl, contains('#include <material_lighting.glsl>'));
      expect(c.glsl, contains('#include <material_engine_lighting.glsl>'));
      expect(c.glsl, contains('uniform MaterialParams {'));
      expect(c.glsl, contains('  vec4 tint;'));
      expect(c.glsl, contains('  int steps;'));
      expect(c.glsl, contains('material_params;'));
      expect(c.glsl, contains('uniform sampler2D detail_texture;'));
      expect(c.glsl, contains('#line ${c.material.fragmentSourceLine}'));
      expect(c.glsl, contains('frag_color = EvaluateLighting(material);'));
      expect(c.glsl, contains('Surface(material);'));
    });

    test('unlit material outputs premultiplied base color, no lighting', () {
      final c = compileFmat('''
material { name: "U", shading_model: unlit }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(c.glsl, isNot(contains('material_lighting.glsl')));
      expect(c.glsl, isNot(contains('EvaluateLighting')));
      expect(
        c.glsl,
        contains('vec4(material.base_color.rgb, 1.0) * material.base_color.a'),
      );
    });
  });

  group('sidecar', () {
    test('records types, defaults, hints, and samplers', () {
      final c = compileFmat(_validLit, fileName: 'test.fmat');
      final s = c.sidecar;
      expect(s['name'], 'Test');
      expect(s['shading_model'], 'lit');
      expect(s['blending'], 'alpha');
      expect(s['uniform_block'], 'MaterialParams');

      final params = (s['parameters'] as List).cast<Map<String, Object?>>();
      expect(params.map((p) => p['name']), ['tint', 'strength', 'steps']);
      final tint = params.firstWhere((p) => p['name'] == 'tint');
      expect(tint['type'], 'vec4');
      expect(tint['default'], [1.0, 0.5, 0.25, 1.0]);
      expect((tint['hint'] as Map)['kind'], 'source_color');

      final samplers = (s['samplers'] as List).cast<Map<String, Object?>>();
      expect(samplers.single['name'], 'detail_texture');
      expect((samplers.single['hint'] as Map)['kind'], 'default_white');
    });
  });

  group('validation', () {
    String wrap(String params, {String shadingModel = 'lit'}) =>
        '''
material {
  name: "V",
  shading_model: $shadingModel,
  parameters: [ $params ],
}
fragment { void Surface(inout MaterialInputs material) {} }
''';

    test('rejects mat3 with a helpful message', () {
      expect(
        () => parseFmat(wrap('{ type: mat3, name: m }')),
        _throwsFmat('mat3'),
      );
    });

    test('rejects an unknown parameter type', () {
      expect(
        () => parseFmat(wrap('{ type: frobnicate, name: x }')),
        _throwsFmat('Unknown parameter type'),
      );
    });

    test('rejects duplicate parameter names', () {
      expect(
        () => parseFmat(
          wrap('{ type: float, name: a }, { type: float, name: a }'),
        ),
        _throwsFmat('Duplicate parameter name'),
      );
    });

    test('rejects reserved identifiers', () {
      expect(
        () => parseFmat(wrap('{ type: float, name: material }')),
        _throwsFmat('reserved'),
      );
    });

    test('rejects a vector default of the wrong length', () {
      expect(
        () => parseFmat(wrap('{ type: vec4, name: c, default: [1, 2, 3] }')),
        _throwsFmat('components'),
      );
    });

    test('rejects source_color on a non-color type', () {
      expect(
        () => parseFmat(wrap('{ type: float, name: f, hint: source_color }')),
        _throwsFmat('source_color'),
      );
    });

    test('rejects range on a non-numeric type', () {
      expect(
        () =>
            parseFmat(wrap('{ type: vec4, name: v, hint: range(0, 1, 0.1) }')),
        _throwsFmat('range'),
      );
    });

    test('requires a name', () {
      expect(
        () => parseFmat('''
material { shading_model: lit }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('name'),
      );
    });

    test('requires a fragment block', () {
      expect(
        () => parseFmat('material { name: "X" }'),
        _throwsFmat('fragment'),
      );
    });

    test('requires a Surface function in the fragment block', () {
      expect(
        () => parseFmat('''
material { name: "X" }
fragment { void NotSurface() {} }
'''),
        _throwsFmat('Surface'),
      );
    });

    test('rejects unknown material keys', () {
      expect(
        () => parseFmat('''
material { name: "X", shadingmodel: lit }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('Unknown material key'),
      );
    });
  });
}
