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
      final expected = math.pow(0x80 / 0xff, 2.2).toDouble();
      expect(p.rawBlock.getFloat32(0, Endian.host), closeTo(expected, 1e-5));
      expect(p.rawBlock.getFloat32(4, Endian.host), closeTo(0.0, 1e-6));
      expect(
        p.rawBlock.getFloat32(12, Endian.host),
        closeTo(1.0, 1e-6),
      ); // alpha
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
}
