// The starter script the editor writes has one hard requirement: the
// extractor must be able to read it back. A template that produces a file
// the generator then rejects is worse than no template, so the round trip is
// the test that matters here.
import 'package:flutter_scene_codegen/flutter_scene_codegen.dart';
import 'package:test/test.dart';

void main() {
  group('naming', () {
    test('derives a class name from loose input', () {
      expect(componentClassName('spinner'), 'Spinner');
      expect(componentClassName('health bar'), 'HealthBar');
      expect(componentClassName('enemy-spawner'), 'EnemySpawner');
      expect(componentClassName('Patrol_Route'), 'PatrolRoute');
    });

    test('type tags match the built-in lower-camel convention', () {
      expect(componentTypeTag('Spinner'), 'spinner');
      expect(componentTypeTag('HealthBar'), 'healthBar');
    });

    test('file names are snake case', () {
      expect(componentFileName('Spinner'), 'spinner.dart');
      expect(componentFileName('HealthBar'), 'health_bar.dart');
      expect(componentFileName('AIPatrol'), 'a_i_patrol.dart');
    });

    test('rejects names that would not compile', () {
      expect(componentClassNameError('Spinner'), isNull);
      expect(componentClassNameError('  '), isNotNull);
      expect(componentClassNameError('9Lives'), isNotNull);
      expect(componentClassNameError('my component'), isNotNull);
      expect(componentClassNameError('class'), isNotNull);
      // Case-insensitively, since the class name is upper-cased later.
      expect(componentClassNameError('Class'), isNotNull);
    });
  });

  group('the generated source', () {
    test('is something the extractor can read', () {
      final source = componentScriptSource('HealthBar');
      final result = extractComponents(source);

      expect(result.diagnostics, isEmpty);
      expect(result.components, hasLength(1));
      final component = result.components.single;
      expect(component.className, 'HealthBar');
      expect(component.schema.type, 'healthBar');
    });

    test('declares a property of each shape a first component wants', () {
      final component = extractComponents(
        componentScriptSource('Spinner'),
      ).components.single;
      final names = component.schema.properties.map((p) => p.name).toList();

      expect(names, containsAll(['speed', 'axis', 'enabled']));
      final kinds = {
        for (final p in component.schema.properties) p.name: p.kind.name,
      };
      expect(kinds['speed'], 'number');
      expect(kinds['axis'], 'vec3');
      expect(kinds['enabled'], 'boolean');
    });

    test('carries the doc comment through as the description', () {
      final component = extractComponents(
        componentScriptSource('Spinner'),
      ).components.single;
      expect(component.schema.doc, contains('Spinner'));
    });
  });
}
