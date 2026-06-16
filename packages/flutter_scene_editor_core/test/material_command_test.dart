import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
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
}
