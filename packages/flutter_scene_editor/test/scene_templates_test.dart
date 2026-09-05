// What a new scene starts as. A template is a whole document built from the
// same specs a save writes, so what matters is that each one is a document
// the editor can actually open: resources that exist, references that
// resolve, and something in it worth looking at.

import 'package:flutter_scene_editor/flutter_scene_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_scene/fscene.dart' show defaultComponentRegistry;
import 'package:scene/scene.dart';

/// Every resource id any node in [document] refers to.
Set<LocalId> referencedResources(SceneDocument document) {
  final ids = <LocalId>{};
  void walk(PropertyValue value) {
    switch (value) {
      case ResourceRefValue(:final id):
        ids.add(id);
      case MapValue(:final values):
        values.values.forEach(walk);
      case ListValue(:final values):
        values.forEach(walk);
      default:
        break;
    }
  }

  for (final node in document.nodes.values) {
    for (final component in node.components) {
      component.properties.values.forEach(walk);
    }
  }
  return ids;
}

Iterable<ComponentSpec> componentsOfType(SceneDocument document, String type) =>
    document.nodes.values
        .expand((node) => node.components)
        .where((component) => component.type == type);

void main() {
  test('every template is offered exactly once, emptiest first', () {
    expect(sceneTemplates, isNotEmpty);
    expect(
      sceneTemplates.map((t) => t.id).toSet(),
      hasLength(sceneTemplates.length),
    );
    expect(sceneTemplates.first.id, 'empty');
    for (final template in sceneTemplates) {
      expect(template.name, isNotEmpty);
      expect(template.description, isNotEmpty);
    }
  });

  test('an unknown id falls back rather than throwing', () {
    expect(sceneTemplateById('outdoor').id, 'outdoor');
    expect(sceneTemplateById('nonsense').id, 'empty');
  });

  group('every template', () {
    for (final template in sceneTemplates) {
      test('${template.name} builds a document the editor can open', () {
        final document = template.build();

        expect(
          document.stage.environmentRef,
          isNotNull,
          reason: 'a scene with no environment renders as a void',
        );
        expect(
          document.resource(document.stage.environmentRef!),
          isA<EnvironmentResource>(),
        );
        for (final root in document.roots) {
          expect(
            document.node(root),
            isNotNull,
            reason: 'a root pointing at nothing is a broken document',
          );
        }
        for (final id in referencedResources(document)) {
          expect(
            document.resource(id),
            isNotNull,
            reason: 'a component references a resource that is not there',
          );
        }
      });

      test('${template.name} builds fresh objects every time', () {
        // Two new scenes from one template must share no ids, or editing one
        // would edit the other.
        final first = template.build();
        final second = template.build();
        expect(
          first.nodes.keys.toSet().intersection(second.nodes.keys.toSet()),
          isEmpty,
        );
      });
    }
  });

  test('the empty one is a sky, a sun and a camera', () {
    // "Empty" is the blank page, not a scene you cannot light and cannot
    // shoot: adding those two back was the same two gestures every time.
    final document = buildEmptyScene();
    expect(document.stage.environmentRef, isNotNull);
    expect(componentsOfType(document, 'mesh'), isEmpty);
    expect(componentsOfType(document, 'directionalLight'), hasLength(1));
    expect(componentsOfType(document, 'camera'), hasLength(1));
  });

  group('every template', () {
    for (final template in sceneTemplates) {
      test('${template.name} starts with a light and a camera', () {
        final document = template.build();
        expect(
          componentsOfType(document, 'directionalLight'),
          isNotEmpty,
          reason: 'a scene you cannot light',
        );
        expect(
          componentsOfType(document, 'camera'),
          hasLength(1),
          reason: 'a scene you cannot shoot',
        );
      });
    }
  });

  test('the studio has something to look at and light to see it by', () {
    final document = buildStudioScene();
    expect(componentsOfType(document, 'mesh'), hasLength(2));
    expect(
      componentsOfType(document, 'directionalLight').length,
      greaterThanOrEqualTo(2),
      reason: 'one light gives a shape a black side, which reads as a hole',
    );
  });

  test('the outdoor scene has ground with shape to it', () {
    final document = buildOutdoorScene();
    final terrain = document.resources.values
        .whereType<GeometryResource>()
        .where((geometry) => geometry.procedural is TerrainGeometrySpec);
    expect(terrain, hasLength(1));
    expect(
      componentsOfType(document, 'directionalLight'),
      hasLength(1),
      reason: 'terrain with no sun on it is a grey field',
    );
  });

  test('the playground can actually simulate', () {
    final document = buildPlaygroundScene();
    expect(
      componentsOfType(document, 'physicsWorld'),
      hasLength(1),
      reason: 'bodies with no world do not fall',
    );
    expect(componentsOfType(document, 'rigidBody'), hasLength(2));
    expect(componentsOfType(document, 'collider'), hasLength(2));

    final types = componentsOfType(
      document,
      'rigidBody',
    ).map((c) => (c.properties['type']! as StringValue).value).toSet();
    expect(types, {
      'fixed',
      'dynamic',
    }, reason: 'something to fall and something to land on');
  });

  test('every component a template uses is a type the engine has', () {
    // The templates are hand-built specs, so a typo in a type name or an
    // enum value would be a scene that opens with a component missing and
    // nothing saying why.
    final registry = defaultComponentRegistry();
    for (final template in sceneTemplates) {
      final document = template.build();
      for (final node in document.nodes.values) {
        for (final component in node.components) {
          final codec = registry.codecFor(component.type);
          expect(
            codec,
            isNotNull,
            reason:
                '${template.name} uses "${component.type}", which is not '
                'registered',
          );
          for (final entry in component.properties.entries) {
            final def = codec!.propertySchema
                .where((p) => p.name == entry.key)
                .firstOrNull;
            if (def == null || def.options == null) continue;
            final value = entry.value;
            if (value is! StringValue) continue;
            expect(
              def.options,
              contains(value.value),
              reason:
                  '${template.name}: ${component.type}.${entry.key} is '
                  '"${value.value}", which the schema does not offer',
            );
          }
        }
      }
    }
  });

  test('a dynamic body starts above the ground it lands on', () {
    final document = buildPlaygroundScene();
    final box = document.nodes.values.firstWhere((n) => n.name == 'Box');
    final transform = box.transform as TrsTransform;
    expect(transform.translation.y, greaterThan(1));
  });
}
