import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

// Coverage for the runtime doubleSided wiring (PR #139): glTF
// material.doubleSided is parsed, and Material carries a doubleSided knob.
//
// The middle of the chain (buildMaterial setting it on a real
// PhysicallyBasedMaterial / UnlitMaterial, and Material.bind disabling
// back-face culling) constructs engine materials, which load the shader
// bundle and need a Flutter GPU context the headless test harness doesn't
// provide. That part is exercised by the example app, the same boundary noted
// in shader_material_test.dart.

void main() {
  group('Material.doubleSided field', () {
    test('defaults to false', () {
      expect(ShaderMaterial().doubleSided, isFalse);
    });

    test('is settable', () {
      expect((ShaderMaterial()..doubleSided = true).doubleSided, isTrue);
    });
  });

  group('glTF parser reads material.doubleSided', () {
    test('true when present', () {
      final doc = parseGltfJson(<String, Object?>{
        'materials': [
          <String, Object?>{'doubleSided': true},
        ],
      });
      expect(doc.materials.single.doubleSided, isTrue);
    });

    test('false when omitted (glTF default)', () {
      final doc = parseGltfJson(<String, Object?>{
        'materials': [<String, Object?>{}],
      });
      expect(doc.materials.single.doubleSided, isFalse);
    });
  });
}
