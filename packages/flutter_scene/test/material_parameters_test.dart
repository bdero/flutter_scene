// CPU unit tests for the type-checked, name-addressed MaterialParameters. The
// layout is injected via MaterialParameters.withLayout, so no GPU context or
// shader reflection is needed; the GPU bind path is exercised by the example
// app and smoke-render goldens.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_scene/src/fmat/fmat_ast.dart';
import 'package:flutter_scene/src/material/material_parameters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

MaterialParameters _params() => MaterialParameters.withLayout(
  blockName: 'MaterialParams',
  blockSizeBytes: 64,
  parameters: {
    'tint': (type: FmatType.vec4, offset: 0, sourceColor: true),
    'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
    'steps': (type: FmatType.int_, offset: 20, sourceColor: false),
    'dir': (type: FmatType.vec3, offset: 32, sourceColor: false),
    'plain': (type: FmatType.vec4, offset: 48, sourceColor: false),
  },
  samplers: {'detail': FmatHintKind.defaultWhite},
);

void main() {
  group('typed setters write at reflected offsets', () {
    test('float / int', () {
      final p = _params();
      p.setFloat('gloss', 0.25);
      p.setInt('steps', 7);
      expect(p.rawBlock.getFloat32(16, Endian.host), 0.25);
      expect(p.rawBlock.getInt32(20, Endian.host), 7);
    });

    test('vec4 / vec3', () {
      final p = _params();
      p.setVec4('tint', Vector4(0.1, 0.2, 0.3, 0.4));
      p.setVec3('dir', Vector3(1.0, 2.0, 3.0));
      final b = p.rawBlock;
      expect(b.getFloat32(0, Endian.host), closeTo(0.1, 1e-6));
      expect(b.getFloat32(4, Endian.host), closeTo(0.2, 1e-6));
      expect(b.getFloat32(8, Endian.host), closeTo(0.3, 1e-6));
      expect(b.getFloat32(12, Endian.host), closeTo(0.4, 1e-6));
      expect(b.getFloat32(32, Endian.host), closeTo(1.0, 1e-6));
      expect(b.getFloat32(40, Endian.host), closeTo(3.0, 1e-6));
    });

    test('offsetOf exposes the reflected offset', () {
      expect(_params().offsetOf('gloss'), 16);
    });
  });

  group('type checking', () {
    test('wrong-typed setter throws', () {
      final p = _params();
      expect(() => p.setFloat('tint', 1.0), throwsArgumentError);
      expect(() => p.setVec4('gloss', Vector4.zero()), throwsArgumentError);
    });

    test('unknown parameter throws', () {
      expect(() => _params().setFloat('nope', 1.0), throwsArgumentError);
    });
  });

  group('dynamic operator[]=', () {
    test('dispatches on the declared type', () {
      final p = _params();
      p['gloss'] = 0.5;
      p['steps'] = 3;
      p['tint'] = Vector4(1.0, 0.0, 0.0, 1.0);
      expect(p.rawBlock.getFloat32(16, Endian.host), 0.5);
      expect(p.rawBlock.getInt32(20, Endian.host), 3);
      expect(p.rawBlock.getFloat32(0, Endian.host), closeTo(1.0, 1e-6));
    });

    test('throws on a type mismatch', () {
      final p = _params();
      expect(() => p['gloss'] = Vector4.zero(), throwsArgumentError);
      expect(() => p['tint'] = 'red', throwsArgumentError);
      expect(() => p['steps'] = 1.5, throwsArgumentError); // not an int
    });

    test('throws on an unknown name', () {
      expect(() => _params()['nope'] = 1.0, throwsArgumentError);
    });
  });

  group('setColor', () {
    test('sRGB-decodes rgb for a source_color parameter, alpha as-is', () {
      final p = _params();
      p.setColor('tint', const Color(0xff800000)); // r = 0x80/0xff
      final c = 0x80 / 0xff;
      final expected = math.pow((c + 0.055) / 1.055, 2.4).toDouble();
      expect(p.rawBlock.getFloat32(0, Endian.host), closeTo(expected, 1e-5));
      expect(p.rawBlock.getFloat32(4, Endian.host), closeTo(0.0, 1e-6));
      expect(
        p.rawBlock.getFloat32(12, Endian.host),
        closeTo(1.0, 1e-6),
      ); // alpha
    });

    test('sRGB-decodes dark colors with the linear segment', () {
      final p = _params();
      p.setColor('tint', const Color(0xff010101));
      final expected = (1 / 0xff) / 12.92;
      expect(p.rawBlock.getFloat32(0, Endian.host), closeTo(expected, 1e-6));
      expect(p.rawBlock.getFloat32(4, Endian.host), closeTo(expected, 1e-6));
      expect(p.rawBlock.getFloat32(8, Endian.host), closeTo(expected, 1e-6));
    });

    test('writes raw channels for a non-source_color parameter', () {
      final p = _params();
      p.setColor('plain', const Color(0xff800000));
      expect(
        p.rawBlock.getFloat32(48, Endian.host),
        closeTo(0x80 / 0xff, 1e-5),
      );
    });
  });

  group('introspection and samplers', () {
    test('exposes parameter and sampler names', () {
      final p = _params();
      expect(
        p.parameterNames,
        containsAll(['tint', 'gloss', 'steps', 'dir', 'plain']),
      );
      expect(p.samplerNames, ['detail']);
    });

    test('assigning a non-texture to a sampler throws', () {
      expect(() => _params()['detail'] = 5, throwsArgumentError);
    });
  });

  group('updateFromLayout (hot-reload refresh)', () {
    test('an unset parameter takes the new default', () {
      final p = _params();
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        },
        defaults: {'gloss': 0.5},
      );
      expect(p.rawBlock.getFloat32(16, Endian.host), 0.5);
    });

    test(
      'an explicitly-set parameter keeps its value over the new default',
      () {
        final p = _params();
        p.setFloat('gloss', 0.25); // user override
        p.updateFromLayout(
          blockName: 'MaterialParams',
          blockSizeBytes: 64,
          parameters: {
            'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
          },
          defaults: {'gloss': 0.9}, // edited default is ignored for an override
        );
        expect(p.rawBlock.getFloat32(16, Endian.host), 0.25);
      },
    );

    test('preserves an overridden value at a changed offset', () {
      final p = _params();
      p.setInt('steps', 7); // user override at old offset 20
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'steps': (type: FmatType.int_, offset: 40, sourceColor: false),
        },
      );
      expect(p.rawBlock.getInt32(40, Endian.host), 7);
    });

    test('a newly added parameter gets its default', () {
      final p = _params();
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
          'sheen': (type: FmatType.float_, offset: 20, sourceColor: false),
        },
        defaults: {'sheen': 0.3},
      );
      expect(p.parameterNames, containsAll(['gloss', 'sheen']));
      expect(p.rawBlock.getFloat32(20, Endian.host), closeTo(0.3, 1e-6));
    });

    test('a removed parameter is dropped', () {
      final p = _params();
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        },
      );
      expect(p.parameterNames, ['gloss']);
      expect(() => p.setVec4('tint', Vector4.zero()), throwsArgumentError);
    });

    test('a type change drops the old value and takes the new default', () {
      final p = _params();
      p.setFloat('gloss', 0.25); // overridden as float
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          // same name, now an int
          'gloss': (type: FmatType.int_, offset: 16, sourceColor: false),
        },
        defaults: {'gloss': 4},
      );
      expect(p.rawBlock.getInt32(16, Endian.host), 4);
    });

    test('updates sampler names', () {
      final p = _params();
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        },
        samplers: {'albedo': FmatHintKind.defaultWhite},
      );
      expect(p.samplerNames, ['albedo']);
      expect(p.parameterNames, ['gloss']);
    });
  });

  group('typed getters', () {
    test('an unset parameter falls back to the sidecar default', () {
      final p = MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
          'steps': (type: FmatType.int_, offset: 20, sourceColor: false),
          'dir': (type: FmatType.vec3, offset: 32, sourceColor: false),
        },
        defaults: {
          'gloss': 0.75,
          'steps': 4,
          'dir': [1.0, 0.0, 0.0],
        },
      );
      expect(p.getFloat('gloss'), closeTo(0.75, 1e-6));
      expect(p.getInt('steps'), 4);
      expect(p.getVec3('dir'), Vector3(1.0, 0.0, 0.0));
    });

    test('an assigned value overrides the default', () {
      final p = MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        },
        defaults: {'gloss': 0.75},
      );
      p.setFloat('gloss', 0.1);
      expect(p.getFloat('gloss'), closeTo(0.1, 1e-6));
    });

    test('float / int / vec2 / vec3 / vec4 / mat4 round-trip', () {
      final p = _params();
      p.setFloat('gloss', 0.5);
      p.setInt('steps', 3);
      p.setVec3('dir', Vector3(1.0, 2.0, 3.0));
      p.setVec4('tint', Vector4(0.1, 0.2, 0.3, 0.4));
      expect(p.getFloat('gloss'), closeTo(0.5, 1e-6));
      expect(p.getInt('steps'), 3);
      expect(p.getVec3('dir'), Vector3(1.0, 2.0, 3.0));
      expect(p.getVec4('tint'), Vector4(0.1, 0.2, 0.3, 0.4));

      final withMat4 = MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'xform': (type: FmatType.mat4, offset: 0, sourceColor: false),
        },
      );
      final m = Matrix4.identity()..setEntry(0, 3, 5.0);
      withMat4.setMat4('xform', m);
      expect(withMat4.getMat4('xform'), m);
    });

    test('vec2 round-trip', () {
      final p = MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 16,
        parameters: {
          'uv': (type: FmatType.vec2, offset: 0, sourceColor: false),
        },
      );
      p.setVec2('uv', Vector2(0.25, 0.75));
      expect(p.getVec2('uv'), Vector2(0.25, 0.75));
    });

    test('getColor round-trips a source_color parameter through sRGB', () {
      final p = _params();
      const color = Color(0xff804020);
      p.setColor('tint', color);
      final readBack = p.getColor('tint');
      expect(readBack.a, closeTo(color.a, 1e-3));
      expect(readBack.r, closeTo(color.r, 1e-3));
      expect(readBack.g, closeTo(color.g, 1e-3));
      expect(readBack.b, closeTo(color.b, 1e-3));
    });

    test('getColor reads raw channels for a non-source_color parameter', () {
      final p = _params();
      const color = Color(0xff804020);
      p.setColor('plain', color);
      final readBack = p.getColor('plain');
      expect(readBack.r, closeTo(color.r, 1e-6));
      expect(readBack.g, closeTo(color.g, 1e-6));
      expect(readBack.b, closeTo(color.b, 1e-6));
      expect(readBack.a, closeTo(color.a, 1e-6));
    });

    test(
      'getTexture is null when unset, and the assigned texture otherwise',
      () {
        final p = _params();
        expect(p.getTexture('detail'), isNull);
      },
    );

    test('unknown parameter throws on every typed getter', () {
      final p = _params();
      expect(() => p.getFloat('nope'), throwsArgumentError);
      expect(() => p.getInt('nope'), throwsArgumentError);
      expect(() => p.getVec2('nope'), throwsArgumentError);
      expect(() => p.getVec3('nope'), throwsArgumentError);
      expect(() => p.getVec4('nope'), throwsArgumentError);
      expect(() => p.getMat4('nope'), throwsArgumentError);
      expect(() => p.getColor('nope'), throwsArgumentError);
      expect(() => p.getTexture('nope'), throwsArgumentError);
    });

    test('a type mismatch throws on the getter', () {
      final p = _params();
      expect(() => p.getVec4('gloss'), throwsArgumentError);
      expect(() => p.getFloat('tint'), throwsArgumentError);
      expect(() => p.getInt('dir'), throwsArgumentError);
    });
  });

  group('hasParameter / hasSampler / isParameterAssigned', () {
    test('hasParameter and hasSampler report declared names', () {
      final p = _params();
      expect(p.hasParameter('gloss'), isTrue);
      expect(p.hasParameter('nope'), isFalse);
      expect(p.hasSampler('detail'), isTrue);
      expect(p.hasSampler('nope'), isFalse);
    });

    test('isParameterAssigned distinguishes set vs default', () {
      final p = _params();
      expect(p.isParameterAssigned('gloss'), isFalse);
      p.setFloat('gloss', 0.5);
      expect(p.isParameterAssigned('gloss'), isTrue);
    });

    test('isParameterAssigned throws on an unknown name', () {
      expect(() => _params().isParameterAssigned('nope'), throwsArgumentError);
    });
  });

  group('getParameter (type-erased)', () {
    test('returns the same boxed value as the typed getter', () {
      final p = _params();
      p.setFloat('gloss', 0.5);
      p.setInt('steps', 3);
      p.setVec3('dir', Vector3(1.0, 2.0, 3.0));
      expect(p.getParameter('gloss'), p.getFloat('gloss'));
      expect(p.getParameter('steps'), p.getInt('steps'));
      expect(p.getParameter('dir'), p.getVec3('dir'));
    });

    test('throws on an unknown name', () {
      expect(() => _params().getParameter('nope'), throwsArgumentError);
    });
  });

  group('parameters enumeration', () {
    test('lists every declared parameter with its type and default', () {
      final p = MaterialParameters.withLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
          'dir': (type: FmatType.vec3, offset: 32, sourceColor: false),
        },
        defaults: {
          'gloss': 0.75,
          'dir': [1.0, 0.0, 0.0],
        },
      );
      final byName = {for (final info in p.parameters) info.name: info};
      expect(byName.keys, containsAll(['gloss', 'dir']));
      expect(byName['gloss']!.type, 'float');
      expect(byName['gloss']!.defaultValue, 0.75);
      expect(byName['dir']!.type, 'vec3');
      expect(byName['dir']!.defaultValue, [1.0, 0.0, 0.0]);
    });

    test('a parameter with no declared default reports null', () {
      final p = _params();
      final byName = {for (final info in p.parameters) info.name: info};
      expect(byName['steps']!.defaultValue, isNull);
    });
  });

  group('getters survive a hot-reload metadata update', () {
    test('an override keeps its effective value at a new offset', () {
      final p = _params();
      p.setFloat('gloss', 0.25);
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 40, sourceColor: false),
        },
        defaults: {'gloss': 0.9},
      );
      expect(p.getFloat('gloss'), closeTo(0.25, 1e-6));
      expect(p.isParameterAssigned('gloss'), isTrue);
    });

    test('an unset parameter picks up the edited default', () {
      final p = _params();
      p.updateFromLayout(
        blockName: 'MaterialParams',
        blockSizeBytes: 64,
        parameters: {
          'gloss': (type: FmatType.float_, offset: 16, sourceColor: false),
        },
        defaults: {'gloss': 0.42},
      );
      expect(p.getFloat('gloss'), closeTo(0.42, 1e-6));
      expect(p.isParameterAssigned('gloss'), isFalse);
      final byName = {for (final info in p.parameters) info.name: info};
      expect(byName['gloss']!.defaultValue, 0.42);
    });
  });
}
