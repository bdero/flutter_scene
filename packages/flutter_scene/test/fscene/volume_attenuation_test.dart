// The glTF volume extension defaults attenuationDistance to +infinity (no
// attenuation), which canonical JSON cannot carry; the importer omits it and
// realize reads absent as infinity.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:flutter_scene/src/importer/in_memory_import.dart';

const _gltf = {
  'asset': {'version': '2.0'},
  'scene': 0,
  'scenes': [
    {
      'nodes': [0],
    },
  ],
  'nodes': [
    {'mesh': 0},
  ],
  'meshes': [
    {
      'primitives': [
        {
          'attributes': {'POSITION': 0},
          'material': 0,
        },
      ],
    },
  ],
  'materials': [
    {
      'name': 'glass',
      'extensions': {
        'KHR_materials_transmission': {'transmissionFactor': 1.0},
        // No attenuationDistance: the spec default is +infinity.
        'KHR_materials_volume': {'thicknessFactor': 0.5},
      },
    },
  ],
  'accessors': [
    {
      'bufferView': 0,
      'componentType': 5126,
      'count': 3,
      'type': 'VEC3',
      'min': [0.0, 0.0, 0.0],
      'max': [1.0, 1.0, 0.0],
    },
  ],
  'bufferViews': [
    {'buffer': 0, 'byteOffset': 0, 'byteLength': 36},
  ],
  'buffers': [
    {
      'uri':
          'data:application/octet-stream;base64,'
          'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA',
      'byteLength': 36,
    },
  ],
};

void main() {
  test('an infinite attenuation distance omits the property and encodes', () {
    final document = importGltfToSceneDocument(
      Uint8List.fromList(utf8.encode(jsonEncode(_gltf))),
      // Data URIs only; nothing external to resolve.
      resolveUri: (uri) => throw StateError('unexpected external uri $uri'),
    );
    final material = document.resources.values
        .whereType<MaterialResource>()
        .single;
    expect(material.properties.containsKey('attenuationDistance'), isFalse);
    expect((material.properties['thickness']! as DoubleValue).value, 0.5);
    // The crash was here: canonical JSON refuses non-finite numbers.
    expect(() => writeFscene(document), returnsNormally);
  });
}
