// Covers parsing the KHR_lights_punctual extension into the GltfDocument: the
// document-level lights array and the per-node light index, for directional,
// point, and spot lights.

import 'dart:math' as math;

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses KHR_lights_punctual lights and node references', () {
    final doc = parseGltfJson(<String, Object?>{
      'extensions': {
        'KHR_lights_punctual': {
          'lights': [
            {
              'type': 'directional',
              'color': [1.0, 0.9, 0.8],
              'intensity': 2.0,
            },
            {'type': 'point', 'intensity': 5.0, 'range': 12.0},
            {
              'type': 'spot',
              'intensity': 8.0,
              'spot': {'innerConeAngle': 0.1, 'outerConeAngle': 0.5},
            },
          ],
        },
      },
      'nodes': [
        {
          'name': 'sun',
          'extensions': {
            'KHR_lights_punctual': {'light': 0},
          },
        },
        {
          'name': 'lamp',
          'extensions': {
            'KHR_lights_punctual': {'light': 1},
          },
        },
        {'name': 'nolight'},
      ],
    });

    expect(doc.lights, hasLength(3));

    final directional = doc.lights[0];
    expect(directional.type, 'directional');
    // Color is stored as a float32 Vector3, so compare loosely.
    expect(directional.color.x, closeTo(1.0, 1e-6));
    expect(directional.color.z, closeTo(0.8, 1e-6));
    expect(directional.intensity, 2.0);
    expect(directional.range, isNull);

    final point = doc.lights[1];
    expect(point.type, 'point');
    expect(point.intensity, 5.0);
    expect(point.range, 12.0);
    // Color defaults to white when omitted.
    expect(point.color.x, 1.0);

    final spot = doc.lights[2];
    expect(spot.type, 'spot');
    expect(spot.innerConeAngle, closeTo(0.1, 1e-9));
    expect(spot.outerConeAngle, closeTo(0.5, 1e-9));

    // Node light references.
    expect(doc.nodes[0].light, 0);
    expect(doc.nodes[1].light, 1);
    expect(doc.nodes[2].light, isNull);
  });

  test('a spot light without a spot block uses the default cone', () {
    final doc = parseGltfJson(<String, Object?>{
      'extensions': {
        'KHR_lights_punctual': {
          'lights': [
            {'type': 'spot'},
          ],
        },
      },
    });
    expect(doc.lights.single.outerConeAngle, closeTo(math.pi / 4, 1e-9));
    expect(doc.lights.single.innerConeAngle, 0.0);
  });

  test('a document without the extension has no lights', () {
    final doc = parseGltfJson(<String, Object?>{
      'nodes': [
        {'name': 'a'},
      ],
    });
    expect(doc.lights, isEmpty);
    expect(doc.nodes.single.light, isNull);
  });
}
