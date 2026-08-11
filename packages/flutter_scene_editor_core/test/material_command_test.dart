import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

void main() {
  test('setMaterialProperties merges and reverts material properties', () {
    final session = EditorSession.empty();
    final created = session.run('createMaterial', {'type': 'physicallyBased'});
    final id = created.records.single.targetId;
    MaterialResource material() =>
        session.document.resources[id]! as MaterialResource;
    expect(material().properties, isEmpty);

    session.run('setMaterialProperties', {
      'materialId': id.toToken(),
      'properties': {
        'baseColor': {'r': 1.0, 'g': 0.0, 'b': 0.0, 'a': 1.0},
        'metallic': 0.25,
        'alphaMode': 'blend',
      },
    });
    final color = material().properties['baseColor'];
    expect(color, isA<ColorValue>());
    expect((color! as ColorValue).r, 1.0);
    expect((material().properties['metallic']! as DoubleValue).value, 0.25);
    expect((material().properties['alphaMode']! as StringValue).value, 'blend');

    // A second edit merges, leaving earlier keys intact.
    session.run('setMaterialProperties', {
      'materialId': id.toToken(),
      'properties': {'roughness': 0.5},
    });
    expect(material().properties.keys, containsAll(['baseColor', 'roughness']));

    // Undo reverts the merge; the material is back to base color only.
    session.undo();
    expect(material().properties.containsKey('roughness'), isFalse);
    expect(material().properties.containsKey('baseColor'), isTrue);
  });

  test('setMaterialType changes type in place, resetting parameters', () {
    final session = EditorSession.empty();
    final id = session
        .run('createMaterial', {
          'type': 'physicallyBased',
          'properties': {'metallic': 0.5},
        })
        .records
        .single
        .targetId;
    MaterialResource material() =>
        session.document.resources[id]! as MaterialResource;

    session.run('setMaterialType', {
      'materialId': id.toToken(),
      'type': 'unlit',
    });
    expect(material().type, 'unlit');
    expect(material().asset, isNull);
    expect(material().properties, isEmpty);

    // Undo restores the original type and its parameters.
    session.undo();
    expect(material().type, 'physicallyBased');
    expect((material().properties['metallic']! as DoubleValue).value, 0.5);
  });

  test('setMaterialType to fmat requires and stores the source asset', () {
    final session = EditorSession.empty();
    final id = session
        .run('createMaterial', {'type': 'unlit'})
        .records
        .single
        .targetId;
    MaterialResource material() =>
        session.document.resources[id]! as MaterialResource;

    expect(
      () => session.run('setMaterialType', {
        'materialId': id.toToken(),
        'type': 'fmat',
      }),
      throwsA(isA<CommandException>()),
    );

    session.run('setMaterialType', {
      'materialId': id.toToken(),
      'type': 'fmat',
      'asset': 'shaders/glow.fmat',
    });
    expect(material().type, 'fmat');
    expect(material().asset?.key, 'shaders/glow.fmat');

    // Leaving fmat clears the source asset.
    session.run('setMaterialType', {
      'materialId': id.toToken(),
      'type': 'physicallyBased',
    });
    expect(material().asset, isNull);
  });

  test('clearMaterialProperty removes a single key and reverts', () {
    final session = EditorSession.empty();
    final id = session
        .run('createMaterial', {
          'type': 'physicallyBased',
          'properties': {'metallic': 0.5, 'roughness': 0.25},
        })
        .records
        .single
        .targetId;
    MaterialResource material() =>
        session.document.resources[id]! as MaterialResource;
    expect(material().properties.containsKey('roughness'), isTrue);

    session.run('clearMaterialProperty', {
      'materialId': id.toToken(),
      'key': 'roughness',
    });
    expect(material().properties.containsKey('roughness'), isFalse);
    expect(material().properties.containsKey('metallic'), isTrue);

    session.undo();
    expect(material().properties.containsKey('roughness'), isTrue);
  });
}
