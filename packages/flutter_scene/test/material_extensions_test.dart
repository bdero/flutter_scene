import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_scene/src/runtime_importer/material_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' as scene_doc;
import 'package:vector_math/vector_math.dart';

Map<String, Object?> _extensionDocument() => <String, Object?>{
  'materials': [
    <String, Object?>{
      'name': 'Layered',
      'occlusionTexture': <String, Object?>{'index': 0, 'texCoord': 1},
      'extensions': <String, Object?>{
        'KHR_materials_anisotropy': <String, Object?>{
          'anisotropyStrength': 0.2,
          'anisotropyRotation': 0.3,
          'anisotropyTexture': <String, Object?>{'index': 0},
        },
        'KHR_materials_clearcoat': <String, Object?>{
          'clearcoatFactor': 0.4,
          'clearcoatTexture': <String, Object?>{'index': 1},
          'clearcoatRoughnessFactor': 0.5,
          'clearcoatRoughnessTexture': <String, Object?>{'index': 2},
          'clearcoatNormalTexture': <String, Object?>{'index': 3, 'scale': 0.6},
        },
        'KHR_materials_diffuse_transmission': <String, Object?>{
          'diffuseTransmissionFactor': 0.7,
          'diffuseTransmissionTexture': <String, Object?>{'index': 4},
          'diffuseTransmissionColorFactor': <double>[0.1, 0.2, 0.3],
          'diffuseTransmissionColorTexture': <String, Object?>{'index': 5},
        },
        'KHR_materials_dispersion': <String, Object?>{'dispersion': 0.8},
        'KHR_materials_emissive_strength': <String, Object?>{
          'emissiveStrength': 2.0,
        },
        'KHR_materials_ior': <String, Object?>{'ior': 1.4},
        'KHR_materials_iridescence': <String, Object?>{
          'iridescenceFactor': 0.9,
          'iridescenceTexture': <String, Object?>{'index': 6},
          'iridescenceIor': 1.2,
          'iridescenceThicknessMinimum': 110.0,
          'iridescenceThicknessMaximum': 410.0,
          'iridescenceThicknessTexture': <String, Object?>{'index': 7},
        },
        'KHR_materials_sheen': <String, Object?>{
          'sheenColorFactor': <double>[0.4, 0.5, 0.6],
          'sheenColorTexture': <String, Object?>{'index': 8},
          'sheenRoughnessFactor': 0.7,
          'sheenRoughnessTexture': <String, Object?>{'index': 9},
        },
        'KHR_materials_specular': <String, Object?>{
          'specularFactor': 0.8,
          'specularTexture': <String, Object?>{'index': 10},
          'specularColorFactor': <double>[0.7, 0.8, 0.9],
          'specularColorTexture': <String, Object?>{'index': 11},
        },
        'KHR_materials_transmission': <String, Object?>{
          'transmissionFactor': 0.6,
          'transmissionTexture': <String, Object?>{
            'index': 12,
            'texCoord': 1,
            'extensions': <String, Object?>{
              'KHR_texture_transform': <String, Object?>{
                'offset': <double>[0.1, 0.2],
                'rotation': 0.25,
                'scale': <double>[0.5, 0.75],
                'texCoord': 0,
              },
            },
          },
        },
        'KHR_materials_volume': <String, Object?>{
          'thicknessFactor': 0.4,
          'thicknessTexture': <String, Object?>{'index': 13},
          'attenuationDistance': 3.0,
          'attenuationColor': <double>[0.2, 0.3, 0.4],
        },
      },
    },
  ],
  'textures': [for (var i = 0; i < 14; i++) <String, Object?>{}],
};

void main() {
  test('parses every ratified physical material extension', () {
    final material = parseGltfJson(_extensionDocument()).materials.single;

    expect(material.anisotropy?.strength, 0.2);
    expect(material.anisotropy?.rotation, 0.3);
    expect(material.clearcoat?.factor, 0.4);
    expect(material.clearcoat?.roughnessFactor, 0.5);
    expect(material.clearcoat?.normalTexture?.scale, 0.6);
    expect(material.diffuseTransmission?.factor, 0.7);
    expect(material.diffuseTransmission?.colorFactor, [0.1, 0.2, 0.3]);
    expect(material.dispersion, 0.8);
    expect(material.emissiveStrength, 2.0);
    expect(material.ior, 1.4);
    expect(material.iridescence?.factor, 0.9);
    expect(material.iridescence?.ior, 1.2);
    expect(material.iridescence?.thicknessMinimum, 110.0);
    expect(material.iridescence?.thicknessMaximum, 410.0);
    expect(material.sheen?.colorFactor, [0.4, 0.5, 0.6]);
    expect(material.sheen?.roughnessFactor, 0.7);
    expect(material.specular?.factor, 0.8);
    expect(material.specular?.colorFactor, [0.7, 0.8, 0.9]);
    expect(material.transmission?.factor, 0.6);
    expect(material.volume?.thicknessFactor, 0.4);
    expect(material.volume?.attenuationDistance, 3.0);
    expect(material.volume?.attenuationColor, [0.2, 0.3, 0.4]);

    final transformed = material.transmission!.texture!;
    expect(transformed.texCoord, 1);
    expect(transformed.transform?.offset, [0.1, 0.2]);
    expect(transformed.transform?.rotation, 0.25);
    expect(transformed.transform?.scale, [0.5, 0.75]);
    expect(transformed.transform?.texCoord, 0);
    expect(material.requiresPhysicalMaterial, isTrue);
    expect(material.occlusionTexture?.texCoord, 1);
  });

  test('uses specification defaults for empty extension objects', () {
    final material = parseGltfJson(<String, Object?>{
      'materials': [
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_anisotropy': <String, Object?>{},
            'KHR_materials_clearcoat': <String, Object?>{},
            'KHR_materials_diffuse_transmission': <String, Object?>{},
            'KHR_materials_dispersion': <String, Object?>{},
            'KHR_materials_emissive_strength': <String, Object?>{},
            'KHR_materials_ior': <String, Object?>{},
            'KHR_materials_iridescence': <String, Object?>{},
            'KHR_materials_sheen': <String, Object?>{},
            'KHR_materials_specular': <String, Object?>{},
            'KHR_materials_transmission': <String, Object?>{},
            'KHR_materials_volume': <String, Object?>{},
          },
        },
      ],
    }).materials.single;

    expect(material.anisotropy?.strength, 0.0);
    expect(material.clearcoat?.factor, 0.0);
    expect(material.diffuseTransmission?.colorFactor, [1.0, 1.0, 1.0]);
    expect(material.dispersion, 0.0);
    expect(material.emissiveStrength, 1.0);
    expect(material.ior, 1.5);
    expect(material.iridescence?.ior, 1.3);
    expect(material.iridescence?.thicknessMinimum, 100.0);
    expect(material.iridescence?.thicknessMaximum, 400.0);
    expect(material.sheen?.colorFactor, [0.0, 0.0, 0.0]);
    expect(material.specular?.factor, 1.0);
    expect(material.transmission?.factor, 0.0);
    expect(material.volume?.attenuationDistance, double.infinity);
  });

  test('offline import stores scene-native physical property names', () {
    final gltf = parseGltfJson(_extensionDocument());
    final document = buildSceneDocument(gltf, Uint8List(0));
    final material = document.resources.values
        .whereType<scene_doc.MaterialResource>()
        .single;

    expect(material.type, 'physical');
    expect(material.name, 'Layered');
    expect(
      (material.properties['clearcoat'] as scene_doc.DoubleValue).value,
      0.4,
    );
    expect(
      (material.properties['sheenRoughness'] as scene_doc.DoubleValue).value,
      0.7,
    );
    expect(
      (material.properties['transmission'] as scene_doc.DoubleValue).value,
      0.6,
    );
    expect((material.properties['ior'] as scene_doc.DoubleValue).value, 1.4);
    expect(
      (material.properties['anisotropy'] as scene_doc.DoubleValue).value,
      0.2,
    );
    expect(
      (material.properties['dispersion'] as scene_doc.DoubleValue).value,
      0.8,
    );
    final occlusionTransform =
        material.properties['occlusionTextureTransform'] as scene_doc.MapValue;
    expect(
      (occlusionTransform.values['texCoord'] as scene_doc.IntValue).value,
      1,
    );
  });

  test('runtime import uses the same scene-native descriptor', () {
    final gltf = parseGltfJson(_extensionDocument());
    final descriptor = physicalMaterialDescriptor(
      gltf.materials.single,
      const [],
    );

    expect(descriptor.name, 'Layered');
    expect(descriptor.clearcoat, 0.4);
    expect(descriptor.clearcoatNormalScale, Vector2.all(0.6));
    expect(descriptor.sheenRoughness, 0.7);
    expect(descriptor.transmission, 0.6);
    expect(descriptor.ior, 1.4);
    expect(descriptor.anisotropy, 0.2);
    expect(descriptor.dispersion, 0.8);
    expect(descriptor.transmissionTexture.texCoord, 0);
    expect(descriptor.occlusionTexture.texCoord, 1);
    expect(
      descriptor.transmissionTexture.transform.offset.x,
      closeTo(0.1, 1e-6),
    );
  });

  test('runtime clearcoat does not enable sheen implicitly', () {
    final material = parseGltfJson(<String, Object?>{
      'materials': [
        <String, Object?>{
          'name': 'Paint 1 Carmine',
          'doubleSided': true,
          'pbrMetallicRoughness': <String, Object?>{
            'baseColorFactor': <double>[0.666, 0.0, 0.0, 1.0],
            'roughnessFactor': 0.25,
          },
          'extensions': <String, Object?>{
            'KHR_materials_clearcoat': <String, Object?>{
              'clearcoatFactor': 1.0,
            },
          },
        },
      ],
    }).materials.single;
    final descriptor = physicalMaterialDescriptor(material, const []);

    expect(descriptor.clearcoat, 1.0);
    expect(descriptor.baseColor, Vector4(0.666, 0.0, 0.0, 1.0));
    expect(descriptor.sheenColor, Vector4.zero());
    expect(descriptor.specularColor, Vector4.all(1.0));
    expect(descriptor.doubleSided, isTrue);
  });

  test('runtime transmission does not enable sheen implicitly', () {
    final material = parseGltfJson(<String, Object?>{
      'materials': [
        <String, Object?>{
          'name': 'Glass',
          'doubleSided': true,
          'pbrMetallicRoughness': <String, Object?>{
            'metallicFactor': 0.0,
            'roughnessFactor': 0.0,
          },
          'extensions': <String, Object?>{
            'KHR_materials_transmission': <String, Object?>{
              'transmissionFactor': 1.0,
            },
          },
        },
      ],
    }).materials.single;
    final descriptor = physicalMaterialDescriptor(material, const []);

    expect(descriptor.transmission, 1.0);
    expect(descriptor.sheenColor, Vector4.zero());
    expect(descriptor.diffuseTransmissionColor, Vector4.all(1.0));
    expect(descriptor.attenuationColor, Vector4.all(1.0));
    expect(descriptor.doubleSided, isTrue);
  });

  test('runtime physical textures clamp unsupported UV channels', () {
    final material = parseGltfJson(<String, Object?>{
      'materials': [
        <String, Object?>{
          'extensions': <String, Object?>{
            'KHR_materials_clearcoat': <String, Object?>{
              'clearcoatFactor': 1.0,
              'clearcoatTexture': <String, Object?>{'index': 0, 'texCoord': 7},
            },
          },
        },
      ],
    }).materials.single;

    final descriptor = physicalMaterialDescriptor(material, const []);
    expect(descriptor.clearcoatTexture.texCoord, 1);
  });
}
