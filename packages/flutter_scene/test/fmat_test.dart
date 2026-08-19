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
      expect(m.depthWrite, isFalse);
      expect(m.parameters, isEmpty);
    });

    test('parses translucent depth writes into the sidecar', () {
      final m = parseFmat('''
material {
  name: "Glass",
  blending: alpha,
  depth_write: true,
}
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.depthWrite, isTrue);
      expect(buildSidecar(m)['depth_write'], isTrue);
    });

    test('parses depth_test into the AST and the sidecar', () {
      final m = parseFmat('''
material {
  name: "Decal",
  blending: alpha,
  culling: front,
  depth_test: always,
}
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.depthTest, FmatDepthTest.always);
      expect(buildSidecar(m)['depth_test'], 'always');

      // The default is the plain occluding test, and it stays out of the
      // sidecar so every existing material's metadata is unchanged.
      final byDefault = parseFmat('''
material { name: "Plain", blending: alpha }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(byDefault.depthTest, FmatDepthTest.lessEqual);
      expect(buildSidecar(byDefault).containsKey('depth_test'), isFalse);

      final explicit = parseFmat('''
material { name: "Explicit", blending: alpha, depth_test: less_equal }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(explicit.depthTest, FmatDepthTest.lessEqual);

      expect(
        () => parseFmat('''
material { name: "X", blending: alpha, depth_test: greater }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must be `less_equal` or `always`'),
      );
      // The test only applies in the translucent pass.
      expect(
        () => parseFmat('''
material { name: "X", depth_test: always }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('needs `blending: alpha`'),
      );
    });

    test('parses blending: additive on lit and unlit alike', () {
      final lit = parseFmat('''
material { name: "AddLit", shading_model: lit, blending: additive }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(lit.blending, FmatBlending.additive);

      final unlit = parseFmat('''
material { name: "AddUnlit", shading_model: unlit, blending: additive }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(unlit.blending, FmatBlending.additive);
    });

    test('parses engine_inputs and rejects invalid combinations', () {
      final m = parseFmat('''
material {
  name: "Water",
  shading_model: lit,
  blending: alpha,
  engine_inputs: [scene_color, filtered_scene_color, scene_depth],
}
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.engineInputs, [
        'scene_color',
        'filtered_scene_color',
        'scene_depth',
      ]);
      final sidecar = buildSidecar(m);
      expect(sidecar['engine_inputs'], [
        'scene_color',
        'filtered_scene_color',
        'scene_depth',
      ]);
      // The samplers and accessors compile in through the shared include,
      // gated by what the material declared.
      final glsl = emitFragmentGlsl(m);
      expect(glsl, contains('#define FLUTTER_SCENE_SCENE_COLOR'));
      expect(glsl, contains('#define FLUTTER_SCENE_SCENE_DEPTH'));
      expect(glsl, contains('#include <material_engine_lighting.glsl>'));
      expect(glsl, contains('#include <filtered_scene_color.glsl>'));
      expect(glsl, isNot(contains('TransmissionWeight0')));

      // Unknown entries are rejected.
      expect(
        () => parseFmat('''
material { name: "X", engine_inputs: [shadow_map] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('Unknown `engine_inputs` entry'),
      );
      expect(
        () => parseFmat('''
material { name: "X", engine_inputs: [filtered_scene_color] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('requires `scene_color`'),
      );
    });

    test('physical materials enable layered inputs and engine textures', () {
      final material = parseFmat('''
material {
  name: "Physical",
  shading_model: physical,
  engine_inputs: [scene_color],
}
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(material.shadingModel, FmatShadingModel.physical);
      final glsl = emitFragmentGlsl(material);
      expect(glsl, contains('#define FLUTTER_SCENE_PHYSICAL_MATERIAL'));
      expect(glsl, contains('#include <material_lighting.glsl>'));
      expect(glsl, contains('#define FLUTTER_SCENE_SCENE_COLOR'));
      expect(buildSidecar(material)['shading_model'], 'physical');
    });

    test('unlit materials may declare engine inputs', () {
      final m = parseFmat('''
material {
  name: "Haze",
  shading_model: unlit,
  blending: additive,
  engine_inputs: [scene_color],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetSceneColor(vec2(0.01, 0.0)), 1.0);
  }
}
''');
      expect(m.shadingModel, FmatShadingModel.unlit);
      expect(m.engineInputs, ['scene_color']);
      expect(buildSidecar(m)['engine_inputs'], ['scene_color']);
    });

    test('parses scene_color_reach into the AST and the sidecar', () {
      final m = parseFmat('''
material {
  name: "Reach",
  shading_model: unlit,
  engine_inputs: [scene_color],
  scene_color_reach: 0.25,
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetSceneColor(vec2(0.0)), 1.0);
  }
}
''');
      expect(m.sceneColorReach, 0.25);
      expect(buildSidecar(m)['scene_color_reach'], 0.25);

      // Omitted means unbounded, so nothing lands in the sidecar.
      final unbounded = parseFmat('''
material { name: "Unbounded", engine_inputs: [scene_color] }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(unbounded.sceneColorReach, isNull);
      expect(buildSidecar(unbounded).containsKey('scene_color_reach'), isFalse);

      expect(
        () => parseFmat('''
material { name: "X", engine_inputs: [scene_color], scene_color_reach: -1.0 }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must not be negative'),
      );
      expect(
        () => parseFmat('''
material { name: "X", scene_color_reach: 0.5 }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('requires `engine_inputs`'),
      );
    });

    test('materials without engine_inputs get no scene-input samplers', () {
      final m = parseFmat('''
material { name: "Plain" }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(m.engineInputs, isEmpty);
      final glsl = emitFragmentGlsl(m);
      expect(glsl, isNot(contains('scene_opaque_color')));
      expect(glsl, isNot(contains('scene_filtered_color')));
      expect(glsl, isNot(contains('uniform sampler2D scene_depth;')));
      expect(buildSidecar(m).containsKey('engine_inputs'), isFalse);
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

    test('additive unlit zeroes output alpha, keeps premultiplied rgb', () {
      final c = compileFmat('''
material { name: "AddU", shading_model: unlit, blending: additive }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(
        c.glsl,
        contains(
          'frag_color = vec4(material.base_color.rgb * '
          'material.base_color.a, 0.0);',
        ),
      );
    });

    test('additive lit zeroes output alpha, keeps lit rgb', () {
      final c = compileFmat('''
material { name: "AddL", shading_model: lit, blending: additive }
fragment { void Surface(inout MaterialInputs material) {} }
''');
      expect(c.glsl, contains('vec4 lit = EvaluateLighting(material);'));
      expect(c.glsl, contains('frag_color = vec4(lit.rgb, 0.0);'));
    });

    test(
      'unlit engine inputs pull in the scene-input include, not lighting',
      () {
        final c = compileFmat('''
material {
  name: "UHaze",
  shading_model: unlit,
  blending: additive,
  engine_inputs: [scene_color, scene_depth],
}
fragment {
  void Surface(inout MaterialInputs material) {
    float behind = GetSceneDepth(vec2(0.0)) - GetFragmentViewDepth();
    material.base_color =
        vec4(GetSceneColor(vec2(0.01, 0.0)) * behind, 1.0);
  }
}
''');
        expect(c.glsl, contains('#define FLUTTER_SCENE_SCENE_COLOR'));
        expect(c.glsl, contains('#define FLUTTER_SCENE_SCENE_DEPTH'));
        expect(c.glsl, contains('#include <material_scene_inputs.glsl>'));
        expect(c.glsl, isNot(contains('material_engine_lighting.glsl')));
        expect(c.glsl, isNot(contains('material_lighting.glsl')));
        // FragInfo is bound for this material, so the block must survive
        // compilation even though the accessors are all the shader reads of it.
        expect(
          c.glsl,
          contains('uniform FragmentKeepAlive { vec4 keep_alive; }'),
        );
        expect(c.glsl, contains('frag_info.scene_inputs.x'));
      },
    );

    test('an unlit material without engine inputs declares no FragInfo', () {
      final c = compileFmat('''
material { name: "UPlain", shading_model: unlit }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(c.glsl, isNot(contains('material_scene_inputs.glsl')));
      expect(c.glsl, isNot(contains('material_engine_lighting.glsl')));
      expect(c.glsl, isNot(contains('frag_info')));
      expect(c.glsl, isNot(contains('FragmentKeepAlive')));
    });

    test('an unread engine input stays live through the keep-alive', () {
      // A material that declares an input its Surface() never samples still
      // has the sampler bound, so a zero-multiplied fetch keeps it live.
      final c = compileFmat('''
material { name: "UUnread", shading_model: unlit, engine_inputs: [scene_color] }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(c.glsl, contains('texture(scene_opaque_color, vec2(0.0)).x'));
    });

    test('keeps MaterialParams live when the fragment reads no parameter', () {
      // A parameter used only in the vertex stage: the fragment must still
      // reference MaterialParams (through the zero-bound keep-alive) so the
      // block is not optimized out and its uniform slot stays bindable, which
      // otherwise crashes the Metal backend when the parameters are bound.
      final c = compileFmat('''
material {
  name: "P",
  shading_model: unlit,
  parameters: [ { type: float, name: k, default: 1.0 } ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(c.glsl, contains('uniform MaterialParams {'));
      expect(
        c.glsl,
        contains('uniform FragmentKeepAlive { vec4 keep_alive; }'),
      );
      expect(
        c.glsl,
        contains('fragment_keep_alive.keep_alive.x * (material_params.k)'),
      );
    });

    test('keep-alive reads a scalar from mat4 and int leading parameters', () {
      // The keep-alive multiplies the first MaterialParams member; a plain
      // `.x` swizzle is invalid GLSL on mat4 and int members.
      final c = compileFmat('''
material {
  name: "M",
  shading_model: unlit,
  parameters: [
    { type: mat4, name: transform },
    { type: float, name: k, default: 1.0 },
  ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(
        c.glsl,
        contains(
          'fragment_keep_alive.keep_alive.x * '
          '(material_params.transform[0].x)',
        ),
      );

      final ci = compileFmat('''
material {
  name: "I",
  shading_model: unlit,
  parameters: [ { type: int, name: steps, default: 3 } ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(
        ci.glsl,
        contains(
          'fragment_keep_alive.keep_alive.x * '
          '(float(material_params.steps))',
        ),
      );
    });

    test('vertex variants keep MaterialParams live via the body macro', () {
      // A Vertex() that reads no parameter must not let the compiler strip
      // the MaterialParams block from the variant; the runtime binds it to
      // the vertex stage unconditionally.
      final c = compileFmat('''
material {
  name: "V",
  shading_model: unlit,
  parameters: [ { type: float, name: k, default: 1.0 } ],
  varyings: [ { type: float, name: h } ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    h = vertex.position.y;
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(h);
  }
}
''');
      for (final variant in c.vertexGlsl.values) {
        expect(
          variant,
          contains('#define MATERIAL_PARAMS_KEEP_ALIVE (material_params.k)'),
        );
      }
    });

    test(
      'vertex variants keep declared attributes live via the body macro',
      () {
        // An attribute Vertex() never reads must not be stripped; the geometry
        // supplies its buffer unconditionally, and a missing input breaks
        // reflection and the pipeline's vertex layout.
        final c = compileFmat('''
material {
  name: "A",
  shading_model: unlit,
  attributes: [
    { type: float, name: seed },
    { type: vec3, name: center },
  ],
  varyings: [ { type: float, name: h } ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    h = vertex.position.y;
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(h);
  }
}
''');
        for (final variant in c.vertexGlsl.values) {
          expect(
            variant,
            contains(
              '#define MATERIAL_ATTRIBUTES_KEEP_ALIVE (seed + center.x)',
            ),
          );
        }
      },
    );

    test('keep-alive fetches samplers the fragment never references', () {
      // The runtime binds every declared sampler; one the author's code never
      // samples must not be stripped from the compiled shader.
      final c = compileFmat('''
material {
  name: "S",
  shading_model: unlit,
  parameters: [
    { type: sampler2d, name: used_texture, hint: default_white },
    { type: sampler2d, name: unused_texture, hint: default_white },
    { type: samplerCube, name: unused_cube, hint: default_black },
  ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = texture(used_texture, GetUV0());
  }
}
''');
      // No MaterialParams block, but the keep-alive block is still declared
      // for the sampler fetches.
      expect(c.glsl, isNot(contains('uniform MaterialParams {')));
      expect(
        c.glsl,
        contains('uniform FragmentKeepAlive { vec4 keep_alive; }'),
      );
      expect(c.glsl, contains('texture(unused_texture, vec2(0.0)).x'));
      expect(c.glsl, contains('texture(unused_cube, vec3(0.0, 0.0, 1.0)).x'));
      // The sampler the fragment really uses pays no keep-alive fetch.
      expect(c.glsl, isNot(contains('texture(used_texture, vec2(0.0))')));
    });

    test(
      'sampler-only material with all samplers used keeps the block live',
      () {
        final c = compileFmat('''
material {
  name: "S2",
  shading_model: unlit,
  parameters: [
    { type: sampler2d, name: tex, hint: default_white },
  ],
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = texture(tex, GetUV0());
  }
}
''');
        expect(
          c.glsl,
          contains(
            'fragment_keep_alive.keep_alive.x * '
            'fragment_keep_alive.keep_alive.y',
          ),
        );
      },
    );

    test('sky shaders carry the same parameter keep-alive', () {
      final c = compileFmat('''
material {
  name: "SkyK",
  parameters: [
    { type: vec3, name: unused_color, default: [0.0, 0.0, 0.0] },
    { type: sampler2d, name: unused_texture, hint: default_white },
  ],
}
sky {
  vec3 Sky(vec3 direction) {
    return vec3(0.5);
  }
}
''');
      expect(
        c.glsl,
        contains('uniform FragmentKeepAlive { vec4 keep_alive; }'),
      );
      expect(
        c.glsl,
        contains(
          'frag_color.r += fragment_keep_alive.keep_alive.x * '
          '(material_params.unused_color.x + '
          'texture(unused_texture, vec2(0.0)).x)',
        ),
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

    test('records additive blending', () {
      final c = compileFmat('''
material { name: "Add", shading_model: unlit, blending: additive }
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(1.0);
  }
}
''');
      expect(c.sidecar['blending'], 'additive');
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
    return SampleEnvironment(direction, 0.5);
  }
}
''';

    test('requires: [environment] declares and records the samplers', () {
      final m = parseFmat(envSky);
      expect(m.useEnvironment, isTrue);
      final glsl = emitFragmentGlsl(m);
      expect(glsl, contains('uniform RadianceSampler prefiltered_radiance;'));
      expect(glsl, isNot(contains('prefiltered_radiance_cube')));
      expect(glsl, contains('vec3 SampleEnvironment('));
      expect(buildSidecar(m)['use_environment'], isTrue);
    });

    test('an unsampled environment stays live through the keep-alive', () {
      final m = parseFmat('''
material { name: "EnvSky", requires: [environment] }
sky { vec3 Sky(vec3 direction) { return vec3(0.0); } }
''');
      final glsl = emitFragmentGlsl(m);
      expect(glsl, contains('uniform FragmentKeepAlive'));
      expect(glsl, contains('SampleEnvironment(vec3(0.0, 1.0, 0.0), 1.0).x'));
    });

    test('skies without requires do not declare the atlas', () {
      final m = parseFmat(validSky);
      expect(m.useEnvironment, isFalse);
      expect(
        emitFragmentGlsl(m),
        isNot(contains('uniform RadianceSampler prefiltered_radiance;')),
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

    test('every vertex variant declares the keep-alive block', () {
      // The body includes reference it (under HAS_MATERIAL_VERTEX) to keep the
      // mesh inputs live, so a hook that replaces the outputs cannot strip an
      // attribute and break reflection.
      final variants = emitVertexGlsl(parseFmat(withVertex));
      for (final glsl in variants.values) {
        expect(glsl, contains('uniform VertexKeepAlive'));
      }
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

  group('custom attributes', () {
    const withAttributes = '''
material {
  name: "Attr",
  attributes: [
    { type: float, name: wave_phase },
    { type: vec3, name: bary },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += sin(wave_phase) + bary.x;
  }
}
fragment {
  void Surface(inout MaterialInputs material) { PrepareMaterial(material); }
}
''';

    test('parses declared attributes in order', () {
      final m = parseFmat(withAttributes);
      expect(m.attributes.map((a) => a.name), ['wave_phase', 'bary']);
      expect(m.attributes.map((a) => a.type), [FmatType.float_, FmatType.vec3]);
    });

    test('color variants declare each attribute as an in', () {
      final variants = emitVertexGlsl(parseFmat(withAttributes));
      for (final key in ['AttrUnskinnedVertex', 'AttrSkinnedVertex']) {
        expect(variants[key], contains('in float wave_phase;'));
        expect(variants[key], contains('in vec3 bary;'));
      }
    });

    test('depth variant declares zero fallbacks, not ins', () {
      final depth = emitVertexGlsl(
        parseFmat(withAttributes),
      )['AttrUnskinnedDepthVertex']!;
      expect(depth, contains('float wave_phase = 0.0;'));
      expect(depth, contains('vec3 bary = vec3(0.0);'));
      expect(depth, isNot(contains('in float wave_phase;')));
    });

    test('rejects a non-interpolatable attribute type', () {
      expect(
        () => parseFmat('''
material { name: "X", attributes: [ { type: mat4, name: m } ] }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must be one of float, vec2, vec3, vec4'),
      );
    });

    test('rejects attributes without a vertex block', () {
      expect(
        () => parseFmat('''
material { name: "X", attributes: [ { type: float, name: a } ] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must declare a `vertex'),
      );
    });

    test('rejects an attribute that collides with a varying', () {
      expect(
        () => parseFmat('''
material {
  name: "X",
  varyings: [ { type: float, name: shared } ],
  attributes: [ { type: float, name: shared } ],
}
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('collides with a parameter or varying'),
      );
    });
  });

  group('instance attributes', () {
    const withInstanceAttributes = '''
material {
  name: "Inst",
  shading_model: unlit,
  instance_attributes: [
    { type: float, name: wobble },
    { type: vec3, name: tint_shift },
    { type: vec2, name: uv_pan },
  ],
}
vertex {
  void Vertex(inout VertexInputs vertex) {
    vertex.world_position.y += sin(instance_wobble);
  }
}
fragment {
  void Surface(inout MaterialInputs material) {
    material.base_color = vec4(GetInstanceTintShift(), 1.0);
    PrepareMaterial(material);
  }
}
''';

    test('parses declared attributes in order', () {
      final m = parseFmat(withInstanceAttributes);
      expect(m.instanceAttributes.map((a) => a.name), [
        'wobble',
        'tint_shift',
        'uv_pan',
      ]);
      expect(m.instanceAttributes.map((a) => a.type), [
        FmatType.float_,
        FmatType.vec3,
        FmatType.vec2,
      ]);
    });

    test('appends after the fixed record and pads a vec3 to 16 bytes', () {
      final m = parseFmat(withInstanceAttributes);
      expect(kInstanceRecordBaseBytes, 80);
      expect(m.instanceAttributes.map((a) => a.byteOffset), [80, 84, 100]);
      // tint_shift occupies 16 bytes though it is 12 wide, so uv_pan starts at
      // 100 rather than 96.
      expect(m.instanceAttributes[1].packedFloats, 4);
      expect(m.instanceRecordBytes, 108);
    });

    test('derives the input, varying, and accessor names', () {
      final a = parseFmat(withInstanceAttributes).instanceAttributes[1];
      expect(a.inputName, 'instance_tint_shift');
      expect(a.varyingName, 'v_instance_tint_shift');
      expect(a.accessorName, 'GetInstanceTintShift');
    });

    test('the unskinned variant declares each attribute as an in', () {
      final unskinned = emitVertexGlsl(
        parseFmat(withInstanceAttributes),
      )['InstUnskinnedVertex']!;
      expect(unskinned, contains('in float instance_wobble;'));
      expect(unskinned, contains('in vec3 instance_tint_shift;'));
      expect(unskinned, contains('in vec2 instance_uv_pan;'));
      // A declared input the hook never reads must survive the optimizer.
      expect(
        unskinned,
        contains(
          '#define MATERIAL_ATTRIBUTES_KEEP_ALIVE (instance_wobble + '
          'instance_tint_shift.x + instance_uv_pan.x)',
        ),
      );
    });

    test('variants without an instance-rate slot read zero', () {
      final variants = emitVertexGlsl(parseFmat(withInstanceAttributes));
      for (final key in ['InstSkinnedVertex', 'InstUnskinnedDepthVertex']) {
        expect(variants[key], contains('float instance_wobble = 0.0;'));
        expect(
          variants[key],
          contains('vec3 instance_tint_shift = vec3(0.0);'),
        );
        expect(variants[key], isNot(contains('in float instance_wobble;')));
      }
    });

    test('forwards a varying only for the attributes Surface() reads', () {
      final material = parseFmat(withInstanceAttributes);
      expect(forwardedInstanceAttributes(material).map((a) => a.name), [
        'tint_shift',
      ]);
      final fragment = emitFragmentGlsl(material);
      expect(fragment, contains('in vec3 v_instance_tint_shift;'));
      expect(
        fragment,
        contains(
          'vec3 GetInstanceTintShift() { return v_instance_tint_shift; }',
        ),
      );
      expect(fragment, isNot(contains('v_instance_wobble')));

      final unskinned = emitVertexGlsl(material)['InstUnskinnedVertex']!;
      expect(unskinned, contains('out vec3 v_instance_tint_shift;'));
      expect(
        unskinned,
        contains(
          '#define MATERIAL_INSTANCE_VARYINGS '
          'v_instance_tint_shift = instance_tint_shift;',
        ),
      );
      expect(unskinned, isNot(contains('out float v_instance_wobble;')));
    });

    test('a material declaring none emits no instance-attribute plumbing', () {
      final material = parseFmat('''
material { name: "Plain", shading_model: unlit }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment {
  void Surface(inout MaterialInputs material) { PrepareMaterial(material); }
}
''');
      expect(emitFragmentGlsl(material), isNot(contains('v_instance_')));
      for (final glsl in emitVertexGlsl(material).values) {
        expect(glsl, isNot(contains('MATERIAL_INSTANCE_VARYINGS')));
      }
      expect(
        buildSidecar(material).containsKey('instance_attributes'),
        isFalse,
      );
    });

    test('records the resolved offsets in the sidecar', () {
      final sidecar = buildSidecar(parseFmat(withInstanceAttributes));
      expect(sidecar['instance_attributes'], [
        {'name': 'wobble', 'type': 'float', 'offset': 80},
        {'name': 'tint_shift', 'type': 'vec3', 'offset': 84},
        {'name': 'uv_pan', 'type': 'vec2', 'offset': 100},
      ]);
      expect(sidecar['instance_record_bytes'], 108);
    });

    test('rejects a matrix instance attribute', () {
      for (final type in ['mat3', 'mat4']) {
        expect(
          () => parseFmat('''
material { name: "X", instance_attributes: [ { type: $type, name: m } ] }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
          _throwsFmat('spans several instance-rate inputs'),
          reason: type,
        );
      }
    });

    test('rejects a non-interpolatable instance attribute type', () {
      expect(
        () => parseFmat('''
material { name: "X", instance_attributes: [ { type: int, name: i } ] }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must be one of float, vec2, vec3, vec4'),
      );
    });

    test('rejects a duplicate instance attribute name', () {
      expect(
        () => parseFmat('''
material {
  name: "X",
  instance_attributes: [
    { type: float, name: a },
    { type: vec2, name: a },
  ],
}
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('Duplicate instance attribute name'),
      );
    });

    test('rejects a collision with a parameter, varying, or attribute', () {
      expect(
        () => parseFmat('''
material {
  name: "X",
  attributes: [ { type: float, name: shared } ],
  instance_attributes: [ { type: float, name: shared } ],
}
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('collides with a parameter, varying, or vertex attribute'),
      );
    });

    test('rejects a name deriving a reserved vertex input', () {
      expect(
        () => parseFmat('''
material { name: "X", instance_attributes: [ { type: vec4, name: color } ] }
vertex { void Vertex(inout VertexInputs vertex) {} }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('reserved vertex input `instance_color`'),
      );
    });

    test('rejects instance attributes without a vertex block', () {
      expect(
        () => parseFmat('''
material { name: "X", instance_attributes: [ { type: float, name: a } ] }
fragment { void Surface(inout MaterialInputs material) {} }
'''),
        _throwsFmat('must declare a `vertex'),
      );
    });

    test('rejects instance attributes on a sky', () {
      expect(
        () => parseFmat('''
material { name: "X", instance_attributes: [ { type: float, name: a } ] }
sky { vec3 Sky(vec3 direction) { return vec3(0.0); } }
'''),
        _throwsFmat('only supported in surface materials'),
      );
    });

    test('stamps framework_varying_schema in sidecar', () {
      final sidecar = buildSidecar(
        parseFmat(
          'material { name: "X" } fragment { void Surface(inout MaterialInputs material) {} }',
        ),
      );
      expect(
        sidecar['framework_varying_schema'],
        kFrameworkVaryingSchemaVersion,
      );
    });
  });
}
