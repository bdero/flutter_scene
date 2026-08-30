// The Pick Parent Class list. The parent decides what a blueprint's graphs may
// assume, so the picker has to offer the real set of things this build knows —
// which is the component registry, and grows when a project adds to it.

import 'package:flutter_scene_editor/src/blueprints/blueprint_file.dart';
import 'package:flutter_scene_editor/src/blueprints/blueprint_parents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/visual_script.dart';

void main() {
  group('the common list', () {
    test('leads with the two questions a blueprint answers', () {
      // Something you place, or something you add to what you placed.
      expect(commonBlueprintParents.first.key, 'node');
      expect(commonBlueprintParents[1].key, 'component');
    });

    test('stays short, or it is a second full list', () {
      expect(commonBlueprintParents.length, lessThanOrEqualTo(7));
    });

    test('every entry says what extending it gets you', () {
      // "Pawn" tells you nothing until somebody says what a pawn is.
      for (final parent in commonBlueprintParents) {
        expect(parent.label, isNotEmpty, reason: parent.key);
        expect(parent.doc, isNotEmpty, reason: parent.key);
        expect(parent.doc, endsWith('.'), reason: parent.key);
      }
    });
  });

  group('all classes', () {
    test('is the registry, with node and component first', () {
      final all = allBlueprintParents(['rigidBody', 'camera']);
      expect(all.first.key, 'node');
      expect(all[1].key, 'component');
      expect(all.map((p) => p.key), containsAll(['rigidBody', 'camera']));
    });

    test('sorts the rest, so the list is scannable', () {
      final all = allBlueprintParents(['zebra', 'alpha', 'middle']);
      expect(all.sublist(2).map((p) => p.key).toList(), [
        'alpha',
        'middle',
        'zebra',
      ]);
    });

    test('never lists the same class twice', () {
      // The same class appearing twice in one picker reads as two classes.
      final all = allBlueprintParents(['node', 'component', 'camera']);
      final keys = all.map((p) => p.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('a component with a category says which', () {
      final all = allBlueprintParents(['rigidBody'], schemaFor: (type) => null);
      expect(all.last.doc, isNotEmpty);
    });

    test('an empty registry still offers the two basics', () {
      // A project whose components have not loaded yet can still make a
      // blueprint.
      final all = allBlueprintParents(const []);
      expect(all.map((p) => p.key).toList(), ['node', 'component']);
    });
  });

  group('searching', () {
    final camera = allBlueprintParents(['camera']).last;

    test('an empty query matches everything', () {
      expect(blueprintParentMatches(camera, ''), isTrue);
      expect(blueprintParentMatches(camera, '   '), isTrue);
    });

    test('matches what you see and what you remember', () {
      // People type the label and the type name, and those differ.
      final rigid = allBlueprintParents(['rigidBody']).last;
      expect(blueprintParentMatches(rigid, 'rigid body'), isTrue);
      expect(blueprintParentMatches(rigid, 'rigidBody'), isTrue);
      expect(blueprintParentMatches(rigid, 'RIGID'), isTrue);
    });

    test('and does not match what it is not', () {
      expect(blueprintParentMatches(camera, 'terrain'), isFalse);
    });
  });

  group('labels', () {
    test('a camelCase type reads as words', () {
      expect(blueprintClassLabel('rigidBody'), 'Rigid Body');
      expect(blueprintClassLabel('camera'), 'Camera');
      expect(blueprintClassLabel(''), '');
    });

    test('an unknown parent still gets a readable name', () {
      // Opening a teammate's blueprint should say what it extends rather than
      // imply it extends nothing.
      expect(blueprintParentLabel('theirThing', const []), 'Their Thing');
    });

    test('a known parent uses its own label', () {
      final all = allBlueprintParents(['camera']);
      expect(blueprintParentLabel('node', all), 'Node');
    });
  });

  group('a new blueprint', () {
    test('opens on a graph you can draw in', () {
      // An empty list with an Add button is a worse first screen than a
      // canvas.
      final made = newBlueprint(
        name: 'Door',
        kind: BlueprintKind.blueprintClass,
        parentClass: 'node',
      );
      expect(made.graphs, hasLength(1));
      expect(made.graphs.single.kind, VisualScriptGraphKind.eventGraph);
      expect(made.name, 'Door');
      expect(made.parentClass, 'node');
    });

    test('an interface gets a function, not an event graph', () {
      final made = newBlueprint(
        name: 'Openable',
        kind: BlueprintKind.blueprintInterface,
        parentClass: 'node',
      );
      expect(made.graphs.single.kind, VisualScriptGraphKind.function);
    });

    test('a macro library gets a macro', () {
      final made = newBlueprint(
        name: 'Helpers',
        kind: BlueprintKind.macroLibrary,
        parentClass: 'node',
      );
      expect(made.graphs.single.kind, VisualScriptGraphKind.macro);
    });

    test('every kind opens on a graph its kind is allowed to hold', () {
      for (final kind in BlueprintKind.values) {
        final made = newBlueprint(name: 'X', kind: kind, parentClass: 'node');
        expect(
          kind.allowedGraphKinds,
          contains(made.graphs.single.kind),
          reason: kind.name,
        );
      }
    });

    test('every kind has a default name', () {
      for (final kind in BlueprintKind.values) {
        expect(defaultBlueprintName(kind), isNotEmpty, reason: kind.name);
      }
    });
  });
}
