// Covers the `lighting_features` hook user-define: parsing it, and the defines
// and marker entries it adds to the engine and material bundles.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_scene/src/fmat/build_materials.dart'
    show emitFragmentShaderVariants;
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_scene/src/generated_assets/build_engine_assets.dart'
    show wrapEngineManifest;
import 'package:flutter_scene/src/generated_assets/lighting_features.dart';
import 'package:flutter_test/flutter_test.dart';

const _litFmat = '''
material {
  name: "Probe",
  shading_model: lit,
}

fragment {
  void Surface(inout MaterialInputs material) {
    PrepareMaterial(material);
  }
}
''';

void main() {
  group('parseCompiledOutLightingFeatures', () {
    test('only false compiles a feature out', () {
      expect(parseCompiledOutLightingFeatures(null), isEmpty);
      expect(
        parseCompiledOutLightingFeatures({
          'irradiance_field': false,
          'rect_area_lights': true,
          'point_shadows': false,
        }),
        {LightingFeature.irradianceField, LightingFeature.pointShadows},
      );
    });

    test('rejects unknown names and non-boolean values', () {
      expect(
        () => parseCompiledOutLightingFeatures({'irradiance': false}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('irradiance_field'),
          ),
        ),
      );
      expect(
        () => parseCompiledOutLightingFeatures({'irradiance_field': 'no'}),
        throwsFormatException,
      );
      expect(
        () => parseCompiledOutLightingFeatures(['irradiance_field']),
        throwsFormatException,
      );
    });

    test('describes a set the same way whatever its order', () {
      expect(describeCompiledOutLightingFeatures({}), '');
      expect(
        describeCompiledOutLightingFeatures({
          LightingFeature.pointShadows,
          LightingFeature.ambientOcclusion,
        }),
        'ambient_occlusion,point_shadows',
      );
      expect(lightingFeaturesVariantSuffix({}), '');
    });
  });

  test('the engine bundle defines the features out and marks each', () {
    final root = Directory.systemTemp.createTempSync('lighting_features_');
    addTearDown(() => root.deleteSync(recursive: true));
    final shaders = Directory('${root.path}/shaders')..createSync();
    final wrappers = Directory('${root.path}/wrappers')..createSync();
    File('${shaders.path}/lit.frag').writeAsStringSync('void main() {}\n');
    File('${shaders.path}/mesh.vert').writeAsStringSync('void main() {}\n');

    final wrapped = wrapEngineManifest(
      {
        'StandardFragment': {'type': 'fragment', 'file': 'shaders/lit.frag'},
        'UnskinnedVertex': {'type': 'vertex', 'file': 'shaders/mesh.vert'},
      },
      wrappers.uri,
      shaders.uri,
      lightingOff: {
        LightingFeature.pointShadows,
        LightingFeature.irradianceField,
      },
    );
    String wrapper(String key) => File.fromUri(
      wrappers.uri.resolve((wrapped[key] as Map)['file'] as String),
    ).readAsStringSync();

    expect(wrapped.keys, {
      'StandardFragment',
      'UnskinnedVertex',
      'LightingFeatureOffIrradianceField',
      'LightingFeatureOffPointShadows',
    });
    // In enum order, so the wrapper is stable whatever the set's order.
    expect(
      wrapper('StandardFragment'),
      '#define FLUTTER_SCENE_NO_IRRADIANCE_FIELD\n'
      '#define FLUTTER_SCENE_NO_POINT_SHADOWS\n'
      '#include <lit.frag>\n',
    );
    expect(wrapper('LightingFeatureOffPointShadows'), contains('void main()'));
  });

  test('materials define the features out of their shaded entries only', () {
    final compiled = compileFmat(_litFmat, fileName: 'probe.fmat');
    final variants = emitFragmentShaderVariants(
      compiled,
      generateShadowVariant: true,
      compiledOutLightingFeatures: {LightingFeature.rectAreaLights},
    );
    for (final MapEntry(:key, :value) in variants.entries) {
      expect(
        value.contains('#define FLUTTER_SCENE_NO_RECT_AREA_LIGHTS'),
        !key.contains('Depth'),
        reason: key,
      );
    }
  });
}
