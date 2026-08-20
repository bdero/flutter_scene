import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/importer/src/gltf/parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A synthetic document declaring one EXT_lights_image_based light with a two
/// level, six face specular chain.
Map<String, Object?> _document({
  Object? irradiance = _irradiance,
  bool referenceFromScene = true,
}) => <String, Object?>{
  'asset': <String, Object?>{'version': '2.0'},
  'scene': 0,
  'scenes': <Object?>[
    <String, Object?>{
      'nodes': <Object?>[],
      if (referenceFromScene)
        'extensions': <String, Object?>{
          'EXT_lights_image_based': <String, Object?>{'light': 0},
        },
    },
  ],
  'extensionsUsed': <Object?>['EXT_lights_image_based'],
  'extensions': <String, Object?>{
    'EXT_lights_image_based': <String, Object?>{
      'lights': <Object?>[
        <String, Object?>{
          'name': 'courtyard',
          'rotation': <Object?>[
            0.0,
            0.7071067811865476,
            0.0,
            0.7071067811865476,
          ],
          'intensity': 2.5,
          'irradianceCoefficients': irradiance,
          'specularImageSize': 256,
          'specularImages': <Object?>[
            <Object?>[0, 1, 2, 3, 4, 5],
            <Object?>[6, 7, 8, 9, 10, 11],
          ],
        },
      ],
    },
  },
};

const List<Object?> _irradiance = <Object?>[
  <Object?>[1.0, 1.1, 1.2],
  <Object?>[2.0, 2.1, 2.2],
  <Object?>[3.0, 3.1, 3.2],
  <Object?>[4.0, 4.1, 4.2],
  <Object?>[5.0, 5.1, 5.2],
  <Object?>[6.0, 6.1, 6.2],
  <Object?>[7.0, 7.1, 7.2],
  <Object?>[8.0, 8.1, 8.2],
  <Object?>[9.0, 9.1, 9.2],
];

void main() {
  test('the document extension parses into a structured light', () {
    final doc = parseGltfJson(_document());
    expect(doc.imageBasedLights, hasLength(1));
    // Recognized extension, so no unrecognized-extension warning fires;
    // keeps kRecognizedGltfExtensions and the parser from drifting apart.
    expect(doc.warnings, isEmpty);
    final light = doc.imageBasedLights.single;
    expect(light.name, 'courtyard');
    expect(light.intensity, 2.5);
    expect(light.rotation.y, closeTo(0.7071067811865476, 1e-6));
    expect(light.specularImageSize, 256);
    expect(light.specularImages, hasLength(2));
    expect(light.specularImages[1], <int>[6, 7, 8, 9, 10, 11]);
    expect(light.irradianceCoefficients, hasLength(9));
    expect(light.irradianceCoefficients[8].z, closeTo(9.2, 1e-6));
  });

  test('the scene extension references the light by index', () {
    final doc = parseGltfJson(_document());
    expect(doc.scenes.single.imageBasedLight, 0);
  });

  test('a scene without the extension references no light', () {
    final doc = parseGltfJson(_document(referenceFromScene: false));
    expect(doc.scenes.single.imageBasedLight, isNull);
    expect(doc.imageBasedLights, hasLength(1));
  });

  test('a document without the extension parses to an empty list', () {
    final doc = parseGltfJson(<String, Object?>{
      'asset': <String, Object?>{'version': '2.0'},
      'scenes': <Object?>[
        <String, Object?>{'nodes': <Object?>[]},
      ],
    });
    expect(doc.imageBasedLights, isEmpty);
    expect(doc.scenes.single.imageBasedLight, isNull);
  });

  test('a coefficient array of the wrong length is a FormatException', () {
    expect(
      () => parseGltfJson(
        _document(
          irradiance: <Object?>[
            <Object?>[1.0, 1.0, 1.0],
          ],
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('the component folds the coefficients onto the engine contract', () {
    final light = parseGltfJson(_document()).imageBasedLights.single;
    final component = ImageBasedLightComponent.internal(
      name: light.name,
      rotation: light.rotation,
      intensity: light.intensity,
      irradianceCoefficients: light.irradianceCoefficients,
      specularImageSize: light.specularImageSize,
      specularImages: const [],
    );
    final folded = component.diffuseSphericalHarmonics!;
    expect(folded, hasLength(kDiffuseShCoefficientCount));
    // A_l / pi is 1, 2/3, 1/4 for bands 0, 1, 2.
    expect(folded[0].x, closeTo(1.0, 1e-6));
    expect(folded[1].x, closeTo(2.0 * 2.0 / 3.0, 1e-6));
    expect(folded[3].x, closeTo(4.0 * 2.0 / 3.0, 1e-6));
    expect(folded[4].x, closeTo(5.0 * 0.25, 1e-6));
    expect(folded[8].z, closeTo(9.2 * 0.25, 1e-5));
  });

  test('a light with no coefficients folds to null', () {
    final component = ImageBasedLightComponent.internal(
      name: null,
      rotation: Quaternion.identity(),
      intensity: 1.0,
      irradianceCoefficients: const <Vector3>[],
      specularImageSize: 0,
      specularImages: const [],
    );
    expect(component.diffuseSphericalHarmonics, isNull);
  });
}
