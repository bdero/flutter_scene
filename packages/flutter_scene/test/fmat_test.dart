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

  group('sky', () {
    const validSky = '''
material {
  name: "Sky",
  parameters: [
    { type: vec3, name: zenith, default: [0.0, 0.2, 0.6] },
    { type: float, name: sharpness, default: 400.0 },
  ],
}

sky {
  vec3 Sky(vec3 direction) {
    return mix(vec3(1.0), material_params.zenith, clamp(direction.y, 0.0, 1.0));
  }
}
''';

    test('parses a sky domain', () {
      final m = parseFmat(validSky, fileName: 'sky.fmat');
      expect(m.domain, FmatDomain.sky);
      expect(m.name, 'Sky');
      expect(m.uniformParameters.map((p) => p.name), ['zenith', 'sharpness']);
    });

    test('emits a full-screen sky main reading v_ray', () {
      final glsl = emitFragmentGlsl(parseFmat(validSky));
      expect(glsl, contains('in vec3 v_ray;'));
      expect(glsl, contains('out vec4 frag_color;'));
      expect(glsl, contains('vec3 Sky(vec3 direction)'));
      expect(glsl, contains('frag_color = vec4(Sky(normalize(v_ray)), 1.0);'));
      // The sky contract does not use the surface includes or entry point.
      expect(glsl, isNot(contains('material_varyings.glsl')));
      expect(glsl, isNot(contains('Surface')));
    });

    test('sidecar records the sky domain', () {
      final sidecar = buildSidecar(parseFmat(validSky));
      expect(sidecar['domain'], 'sky');
      expect(sidecar['uniform_block'], 'MaterialParams');
    });

    test('requires a Sky function in the sky block', () {
      expect(
        () => parseFmat('material { name: "X" }\nsky { vec3 NotSky() {} }'),
        _throwsFmat('Sky'),
      );
    });

    test('rejects both a fragment and a sky block', () {
      expect(
        () => parseFmat('''
material { name: "X" }
fragment { void Surface(inout MaterialInputs material) {} }
sky { vec3 Sky(vec3 d) { return vec3(0.0); } }
'''),
        _throwsFmat('not both'),
      );
    });

    const envSky = '''
material { name: "EnvSky", requires: [environment] }
sky {
  vec3 Sky(vec3 direction) {
    return SamplePrefilteredRadiance(prefiltered_radiance, direction, 0.5);
  }
}
''';

    test('requires: [environment] declares and records the atlas', () {
      final m = parseFmat(envSky);
      expect(m.useEnvironment, isTrue);
      final glsl = emitFragmentGlsl(m);
      expect(glsl, contains('uniform sampler2D prefiltered_radiance;'));
      expect(buildSidecar(m)['use_environment'], isTrue);
    });

    test('skies without requires do not declare the atlas', () {
      final m = parseFmat(validSky);
      expect(m.useEnvironment, isFalse);
      expect(
        emitFragmentGlsl(m),
        isNot(contains('uniform sampler2D prefiltered_radiance;')),
      );
      expect(buildSidecar(m).containsKey('use_environment'), isFalse);
    });

    test('rejects requires: [environment] on a surface material', () {
      expect(
        () => parseFmat('''
material { name: "X", requires: [environment] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('only supported in sky materials'),
      );
    });

    test('rejects an unknown requires entry', () {
      expect(
        () => parseFmat('''
material { name: "X", requires: [shadow_map] }
sky { vec3 Sky(vec3 d) { return vec3(0.0); } }
'''),
        _throwsFmat('Unknown `requires` entry'),
      );
    });
  });

  group('vertex stage', () {
    const withVertex = '''
material {
  name: "Curved",
  parameters: [
    { type: float, name: curvature, default: 0.004 },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vec3 rel = vertex.world_position - vertex.camera_position;
    vertex.world_position.y -= material_params.curvature * dot(rel.xz, rel.xz);
  }
}
fragment {
  void Surface(inout MaterialInputs material) { PrepareMaterial(material); }
}
''';

    test('parses the optional vertex block', () {
      final m = parseFmat(withVertex);
      expect(m.hasVertexStage, isTrue);
      expect(m.vertexSource, contains('void Vertex'));
      expect(m.vertexSourceLine, greaterThan(0));
    });

    test('a material without a vertex block has no vertex stage', () {
      final m = parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.hasVertexStage, isFalse);
      expect(emitVertexGlsl(m), isEmpty);
    });

    test('emits one vertex variant per mesh type, keyed by entry name', () {
      final m = parseFmat(withVertex);
      final variants = emitVertexGlsl(m);
      expect(variants.keys, <String>{
        'CurvedUnskinnedVertex',
        'CurvedSkinnedVertex',
        'CurvedUnskinnedDepthVertex',
      });
      // Each variant suppresses the no-op hook, declares the shared param
      // block, splices the author's Vertex(), and includes its mesh-type body.
      final unskinned = variants['CurvedUnskinnedVertex']!;
      expect(unskinned, contains('#define HAS_MATERIAL_VERTEX'));
      expect(unskinned, contains('#include <material_vertex.glsl>'));
      expect(unskinned, contains('uniform MaterialParams'));
      expect(unskinned, contains('void Vertex(inout VertexInputs vertex)'));
      expect(
        unskinned,
        contains('#include <flutter_scene_unskinned_body.glsl>'),
      );
      expect(
        variants['CurvedSkinnedVertex']!,
        contains('#include <flutter_scene_skinned_body.glsl>'),
      );
      expect(
        variants['CurvedUnskinnedDepthVertex']!,
        contains('#include <flutter_scene_unskinned_depth_body.glsl>'),
      );
    });

    test('sidecar records the per-variant vertex entry names', () {
      final sidecar = buildSidecar(parseFmat(withVertex));
      expect(sidecar['vertex'], <String, Object?>{
        'unskinned': 'CurvedUnskinnedVertex',
        'skinned': 'CurvedSkinnedVertex',
        'depth': 'CurvedUnskinnedDepthVertex',
      });
    });

    test('a plain material records no vertex key in the sidecar', () {
      final sidecar = buildSidecar(
        parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
      );
      expect(sidecar.containsKey('vertex'), isFalse);
    });

    test('rejects a vertex block missing the Vertex function', () {
      expect(
        () => parseFmat('''
material { name: "X" }
vertex { float noise(vec3 p) { return 0.0; } }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must define'),
      );
    });

    test('rejects a vertex block on a sky material', () {
      expect(
        () => parseFmat('''
material { name: "X" }
vertex { void Vertex(inout VertexInputs vertex) {} }
sky { vec3 Sky(vec3 d) { return vec3(0.0); } }
'''),
        _throwsFmat('cannot declare a `vertex'),
      );
    });
  });

  group('custom varyings', () {
    const withVaryings = '''
material {
  name: "Fade",
  varyings: [
    { type: float, name: curve_fade },
    { type: vec3, name: local_pos },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    curve_fade = 0.5;
    local_pos = vertex.position;
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color.rgb *= curve_fade;
    PrepareMaterial(material);
  }
}
''';

    test('parses declared varyings in order', () {
      final m = parseFmat(withVaryings);
      expect(m.varyings.map((v) => v.name), ['curve_fade', 'local_pos']);
      expect(m.varyings.map((v) => v.type), [FmatType.float_, FmatType.vec3]);
    });

    test('fragment declares each varying as an in', () {
      final frag = emitFragmentGlsl(parseFmat(withVaryings));
      expect(frag, contains('in float curve_fade;'));
      expect(frag, contains('in vec3 local_pos;'));
    });

    test('every vertex variant declares each varying as an out', () {
      final variants = emitVertexGlsl(parseFmat(withVaryings));
      for (final glsl in variants.values) {
        expect(glsl, contains('out float curve_fade;'));
        expect(glsl, contains('out vec3 local_pos;'));
      }
    });

    test('rejects a non-interpolatable varying type', () {
      expect(
        () => parseFmat('''
material { name: "X", varyings: [ { type: mat4, name: m } ] }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must be one of float, vec2, vec3, vec4'),
      );
    });

    test('rejects varyings without a vertex block', () {
      expect(
        () => parseFmat('''
material { name: "X", varyings: [ { type: float, name: f } ] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must declare a `vertex'),
      );
    });

    test('rejects a varying that collides with a parameter name', () {
      expect(
        () => parseFmat('''
material {
  name: "X",
  parameters: [ { type: float, name: tint } ],
  varyings: [ { type: float, name: tint } ],
}
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('collides with a parameter'),
      );
    });
  });
}
