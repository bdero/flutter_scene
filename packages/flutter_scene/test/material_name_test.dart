import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_scene/src/importer/src/fscene_emitter/fscene_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

// Coverage for material-name preservation (#248): glTF material.name is
// parsed, Material carries a name, the offline importer stores it on the
// MaterialResource, and the .fscene codec round-trips it.
//
// The middle of the chain (buildMaterial and the realizer setting the name on
// a real PhysicallyBasedMaterial / UnlitMaterial) constructs engine materials,
// which need a Flutter GPU context the headless test harness doesn't provide,
// the same boundary noted in material_double_sided_test.dart.

void main() {
  group('Material.name field', () {
    test('defaults to empty', () {
      expect(ShaderMaterial().name, isEmpty);
    });

    test('is settable', () {
      expect((ShaderMaterial()..name = 'Steel').name, 'Steel');
    });
  });

  group('glTF parser reads material.name', () {
    test('present', () {
      final doc = parseGltfJson(<String, Object?>{
        'materials': [
          <String, Object?>{'name': 'Steel'},
        ],
      });
      expect(doc.materials.single.name, 'Steel');
    });

    test('null when omitted', () {
      final doc = parseGltfJson(<String, Object?>{
        'materials': [<String, Object?>{}],
      });
      expect(doc.materials.single.name, isNull);
    });
  });

  group('offline importer keeps material names', () {
    test('emitter stores the glTF name on the MaterialResource', () {
      final doc = parseGltfJson(<String, Object?>{
        'materials': [
          <String, Object?>{'name': 'Steel'},
          <String, Object?>{
            'name': 'Glow',
            'extensions': <String, Object?>{
              'KHR_materials_unlit': <String, Object?>{},
            },
          },
          <String, Object?>{},
        ],
      });
      final document = buildSceneDocument(doc, Uint8List(0));
      final names = [
        for (final r in document.resources.values)
          if (r is MaterialResource) r.name,
      ];
      expect(names, ['Steel', 'Glow', '']);
    });

    test('.fscene codec round-trips the name', () {
      final doc = SceneDocument();
      final named = doc.addResource(
        MaterialResource(doc.newId(), type: 'physicallyBased', name: 'Steel'),
      );
      final unnamed = doc.addResource(
        MaterialResource(doc.newId(), type: 'unlit'),
      );
      final back = readFscene(writeFscene(doc));
      expect((back.resource(named.id) as MaterialResource).name, 'Steel');
      expect((back.resource(unnamed.id) as MaterialResource).name, isEmpty);
    });
  });
}
