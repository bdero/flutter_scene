// Blueprint kinds and parent classes: the two things Unreal asks about a
// blueprint before it exists, and the two this model was missing.
import 'package:scene/visual_script.dart';
import 'package:test/test.dart';

void main() {
  group('kinds', () {
    test('every kind has a label, so no picker shows a blank', () {
      for (final kind in BlueprintKind.values) {
        expect(kind.label, isNotEmpty, reason: kind.name);
      }
    });

    test('a class can hold every graph kind', () {
      expect(
        BlueprintKind.blueprintClass.allowedGraphKinds,
        VisualScriptGraphKind.values.toSet(),
      );
    });

    test('an interface holds signatures and nothing that runs', () {
      // It promises what a class can do; it has no body to do it with, so
      // offering it an event graph would be offering something meaningless.
      expect(BlueprintKind.blueprintInterface.allowedGraphKinds, {
        VisualScriptGraphKind.function,
      });
    });

    test('a macro library holds macros and nothing to run them', () {
      expect(BlueprintKind.macroLibrary.allowedGraphKinds, {
        VisualScriptGraphKind.macro,
      });
    });

    test('an unknown kind reads as a plain class rather than failing', () {
      // A file from a newer build. Its graphs are still graphs.
      expect(BlueprintKind.parse('somethingNew'), BlueprintKind.blueprintClass);
      expect(BlueprintKind.parse(null), BlueprintKind.blueprintClass);
    });

    test('a known kind parses back to itself', () {
      for (final kind in BlueprintKind.values) {
        expect(BlueprintKind.parse(kind.name), kind, reason: kind.name);
      }
    });
  });

  group('the document form', () {
    test('a plain class extending a node writes neither field', () {
      // Deltas from the defaults, like everything else here -- and it is what
      // every blueprint written before these existed looks like.
      final json = encodeBlueprint(Blueprint(name: 'Door'));
      expect(json.containsKey('kind'), isFalse);
      expect(json.containsKey('parent'), isFalse);
    });

    test('a kind and a parent round trip', () {
      final before = Blueprint(
        name: 'HealthBar',
        kind: BlueprintKind.widgetBlueprint,
        parentClass: 'camera',
      );
      final after = decodeBlueprint(encodeBlueprint(before));
      expect(after.name, 'HealthBar');
      expect(after.kind, BlueprintKind.widgetBlueprint);
      expect(after.parentClass, 'camera');
    });

    test('a blueprint written before kinds existed still loads', () {
      final legacy = decodeBlueprint({
        'version': 1,
        'name': 'Old',
        'graphs': <Object?>[],
      });
      expect(legacy.kind, BlueprintKind.blueprintClass);
      expect(legacy.parentClass, defaultBlueprintParent);
    });

    test('a parent this build does not know is kept, not dropped', () {
      // Opening a teammate's blueprint without their components should say
      // what it extends rather than quietly reparenting it.
      final after = decodeBlueprint(
        encodeBlueprint(Blueprint(parentClass: 'theirCustomComponent')),
      );
      expect(after.parentClass, 'theirCustomComponent');
    });

    test('a bare graph still reads as a blueprint holding it', () {
      final graph = VisualScriptGraph();
      final blueprint = decodeBlueprint(encodeVisualScript(graph));
      expect(blueprint.graphs, hasLength(1));
      expect(blueprint.kind, BlueprintKind.blueprintClass);
    });

    test('the text form survives a round trip too', () {
      final before = Blueprint(
        name: 'Openable',
        kind: BlueprintKind.blueprintInterface,
        parentClass: 'component',
      );
      final after = readBlueprint(writeBlueprint(before));
      expect(after.kind, BlueprintKind.blueprintInterface);
      expect(after.parentClass, 'component');
    });
  });
}
