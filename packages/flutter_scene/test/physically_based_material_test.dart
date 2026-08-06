import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/material.dart' as material_internal;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  test('one material exposes core and layered physical properties', () {
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.2, 0.3, 0.4, 1.0)
      ..metallicFactor = 0.25
      ..roughnessFactor = 0.6
      ..clearcoat = 0.8
      ..clearcoatRoughness = 0.15
      ..sheenColor = Vector4(0.1, 0.2, 0.3, 1.0)
      ..anisotropy = 0.5
      ..iridescence = 0.4;

    expect(material.baseColorFactor, Vector4(0.2, 0.3, 0.4, 1.0));
    expect(material.metallicFactor, 0.25);
    expect(material.roughnessFactor, 0.6);
    expect(material.clearcoat, 0.8);
    expect(material.clearcoatRoughness, 0.15);
    expect(material.sheenColor, Vector4(0.1, 0.2, 0.3, 1.0));
    expect(material.anisotropy, 0.5);
    expect(material.iridescence, 0.4);
    expect(material.isOpaque(), isTrue);
  });

  test('transmission updates opacity and cached render requirements', () {
    final revision = material_internal.materialSceneInputsRevision;
    final material = PhysicallyBasedMaterial()..transmission = 0.75;

    expect(material.isOpaque(), isFalse);
    expect(material.sceneInputs, hasLength(2));
    expect(material.translucentDepthWrite, isTrue);
    expect(material_internal.materialSceneInputsRevision, revision + 1);

    material.transmission = 0.5;
    expect(material_internal.materialSceneInputsRevision, revision + 1);

    material.transmission = 0.0;

    expect(material.isOpaque(), isTrue);
    expect(material.sceneInputs, isEmpty);
    expect(material.translucentDepthWrite, isFalse);
    expect(material_internal.materialSceneInputsRevision, revision + 2);
  });
}
