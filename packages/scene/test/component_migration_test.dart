// Renamed component types. A component whose type nothing recognizes is
// dropped on load -- the node survives and the behaviour on it does not -- so
// this is the difference between a rename and a rename that eats scenes.

import 'package:scene/scene.dart';
import 'package:test/test.dart';

/// A document written before Flow became the Visual Scripter.
///
/// Built through the real writer and then spelled back to the old type, so it
/// is a genuine document of the current format rather than JSON typed by hand
/// that might be wrong in some other way.
String legacyDocument() {
  final document = SceneDocument();
  final id = document.newId();
  document.addNode(
    NodeSpec(
      id: id,
      name: 'Door',
      components: [
        ComponentSpec(
          visualScriptComponentType,
          properties: {'graph': const StringValue('{"nodes":[]}')},
        ),
      ],
    ),
    root: true,
  );
  return writeFscene(
    document,
  ).replaceAll('"$visualScriptComponentType"', '"flow"');
}

void main() {
  test('the old spelling resolves to the current one', () {
    expect(migrateComponentType('flow'), visualScriptComponentType);
  });

  test('a name that was never renamed is left exactly alone', () {
    for (final type in ['mesh', 'camera', 'water', 'visualScript']) {
      expect(migrateComponentType(type), type);
    }
  });

  test('a scene saved as flow loads as a visual script', () {
    final document = readFscene(legacyDocument());
    final node = document.node(document.roots.single)!;
    expect(node.components, hasLength(1));
    expect(
      node.components.single.type,
      visualScriptComponentType,
      reason: 'the component would have been dropped on load',
    );
  });

  test('its properties come across with it', () {
    final document = readFscene(legacyDocument());
    final component = document.node(document.roots.single)!.components.single;
    expect(component.properties['graph'], isNotNull);
  });

  test('saving writes the current name, so a document migrates once', () {
    final document = readFscene(legacyDocument());
    final written = writeFscene(document);
    expect(written, contains(visualScriptComponentType));
    expect(
      RegExp(r'"type"\s*:\s*"flow"').hasMatch(written),
      isFalse,
      reason: 'it was written back under the old name',
    );
  });

  test('every rename points at a name, and never at itself', () {
    for (final entry in renamedComponentTypes.entries) {
      expect(entry.value, isNotEmpty);
      expect(entry.key, isNot(entry.value), reason: entry.key);
      expect(
        renamedComponentTypes.containsKey(entry.value),
        isFalse,
        reason: '${entry.key} migrates to a name that is itself renamed',
      );
    }
  });
}
