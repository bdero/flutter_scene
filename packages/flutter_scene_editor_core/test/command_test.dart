import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/src/builtin_commands.dart';
import 'package:flutter_scene_editor_core/src/change.dart';
import 'package:flutter_scene_editor_core/src/command.dart';
import 'package:flutter_scene_editor_core/src/history.dart';
import 'package:test/test.dart';

/// A document plus a history and a registry wired to it, for command tests.
({SceneDocument doc, EditHistory history, CommandRegistry registry})
_harness() {
  final doc = SceneDocument(allocator: IdAllocator(session: 1));
  final registry = CommandRegistry();
  registerBuiltinCommands(registry);
  return (
    doc: doc,
    history: EditHistory(DocumentMutator(doc)),
    registry: registry,
  );
}

/// Runs a command by name and commits its transaction.
void _run(
  ({SceneDocument doc, EditHistory history, CommandRegistry registry}) h,
  String command,
  Map<String, Object?> params,
) {
  final entry = h.registry.lookup(command)!;
  h.history.commit(entry.execute(CommandContext(h.doc), params));
}

void main() {
  group('registry and schema', () {
    test('all built-ins register and are unique', () {
      final registry = CommandRegistry();
      registerBuiltinCommands(registry);
      expect(registry.all, hasLength(builtinCommands.length));
      expect(() => registry.register(setNodeName), throwsStateError);
    });

    test('mcp schema and ui descriptors come from one declaration', () {
      final schema = mcpToolSchema(setNodeTransform);
      expect(schema['name'], 'setNodeTransform');
      final input = schema['inputSchema'] as Map<String, Object>;
      expect(
        (input['properties'] as Map).keys,
        containsAll(['nodeId', 'translation', 'rotation', 'scale']),
      );
      expect(input['required'], ['nodeId']); // the rest are optional

      final ui = uiDescriptors(setNodeTransform);
      expect(ui.map((d) => d.field), [
        'nodeId',
        'translation',
        'rotation',
        'scale',
      ]);
      expect(ui.first.type, ParamType.nodeRef);
    });
  });

  group('built-in commands', () {
    test('createNode adds a root node, undo removes it', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'Root'});
      expect(h.doc.nodes, hasLength(1));
      expect(h.doc.roots, hasLength(1));
      final id = h.doc.roots.single;
      expect(h.doc.node(id)!.name, 'Root');

      h.history.undo();
      expect(h.doc.nodes, isEmpty);
      expect(h.doc.roots, isEmpty);
    });

    test('createNode under a parent links into children', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'Parent'});
      final parent = h.doc.roots.single;
      _run(h, 'createNode', {'name': 'Child', 'parentId': parent.toToken()});
      expect(h.doc.node(parent)!.children, hasLength(1));
      expect(h.doc.roots, hasLength(1));
    });

    test('deleteNode removes the whole subtree and undo restores it', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'Parent'});
      final parent = h.doc.roots.single;
      _run(h, 'createNode', {'name': 'Child', 'parentId': parent.toToken()});
      expect(h.doc.nodes, hasLength(2));

      _run(h, 'deleteNode', {'nodeId': parent.toToken()});
      expect(h.doc.nodes, isEmpty);
      expect(h.doc.roots, isEmpty);

      h.history.undo();
      expect(h.doc.nodes, hasLength(2));
      expect(h.doc.node(parent)!.children, hasLength(1));
    });

    test('reparentNode moves a node and undo restores the old parent', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'A'});
      _run(h, 'createNode', {'name': 'B'});
      final a = h.doc.roots.first;
      final b = h.doc.roots.last;
      _run(h, 'reparentNode', {
        'nodeId': b.toToken(),
        'newParentId': a.toToken(),
      });
      expect(h.doc.node(a)!.children, [b]);
      expect(h.doc.roots, [a]);

      h.history.undo();
      expect(h.doc.node(a)!.children, isEmpty);
      expect(h.doc.roots, [a, b]);
    });

    test('reparent under own descendant is rejected', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'A'});
      final a = h.doc.roots.single;
      _run(h, 'createNode', {'name': 'B', 'parentId': a.toToken()});
      final b = h.doc.node(a)!.children.single;
      final entry = h.registry.lookup('reparentNode')!;
      expect(
        () => entry.execute(CommandContext(h.doc), {
          'nodeId': a.toToken(),
          'newParentId': b.toToken(),
        }),
        throwsA(isA<CommandException>()),
      );
    });

    test('setNodeTransform keeps omitted components', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'A'});
      final a = h.doc.roots.single;
      _run(h, 'setNodeTransform', {
        'nodeId': a.toToken(),
        'translation': {'x': 1.0, 'y': 2.0, 'z': 3.0},
      });
      final trs = h.doc.node(a)!.transform as TrsTransform;
      expect(trs.translation.x, 1.0);
      expect(trs.scale.x, 1.0); // default kept
    });

    test('addComponent then setComponentProperties merges, undo reverts', () {
      final h = _harness();
      _run(h, 'createNode', {'name': 'A'});
      final a = h.doc.roots.single;
      _run(h, 'addComponent', {
        'nodeId': a.toToken(),
        'componentType': 'directionalLight',
        'properties': {'intensity': 1.0},
      });
      expect(h.doc.node(a)!.components, hasLength(1));

      _run(h, 'setComponentProperties', {
        'nodeId': a.toToken(),
        'componentType': 'directionalLight',
        'properties': {'castsShadow': true},
      });
      final comp = h.doc.node(a)!.components.single;
      expect((comp.properties['intensity'] as DoubleValue).value, 1.0);
      expect((comp.properties['castsShadow'] as BoolValue).value, true);

      h.history.undo();
      final reverted = h.doc.node(a)!.components.single;
      expect(reverted.properties.containsKey('castsShadow'), isFalse);
    });

    test('createMaterial adds a resource with coerced properties', () {
      final h = _harness();
      _run(h, 'createMaterial', {
        'type': 'physicallyBased',
        'properties': {
          'baseColor': {'r': 1.0, 'g': 0.0, 'b': 0.0, 'a': 1.0},
          'metallic': 0.5,
        },
      });
      final material = h.doc.resources.values.single as MaterialResource;
      expect(material.type, 'physicallyBased');
      expect(material.properties['baseColor'], isA<ColorValue>());
      expect((material.properties['metallic'] as DoubleValue).value, 0.5);
    });

    test('instantiatePrefab then setPrefabOverride edits the delta', () {
      final h = _harness();
      _run(h, 'instantiatePrefab', {
        'prefabAsset': 'assets/enemy.fscene',
        'name': 'Enemy',
      });
      final id = h.doc.roots.single;
      _run(h, 'setPrefabOverride', {
        'nodeId': id.toToken(),
        'target': id.toToken(),
        'path': 'visible',
        'value': false,
      });
      final instance = h.doc.node(id)!.instance!;
      expect(instance.source.key, 'assets/enemy.fscene');
      expect(instance.overrides, hasLength(1));
      expect(instance.overrides.single.path, 'visible');

      h.history.undo();
      expect(h.doc.node(id)!.instance!.overrides, isEmpty);
    });

    test('clearPrefabOverrides empties the delta, undo restores overrides', () {
      final h = _harness();
      _run(h, 'instantiatePrefab', {
        'prefabAsset': 'assets/tree.fscene',
        'name': 'Tree',
      });
      final id = h.doc.roots.single;
      // Add two overrides.
      _run(h, 'setPrefabOverride', {
        'nodeId': id.toToken(),
        'target': id.toToken(),
        'path': 'name',
        'value': 'Renamed',
      });
      _run(h, 'setPrefabOverride', {
        'nodeId': id.toToken(),
        'target': id.toToken(),
        'path': 'layers',
        'value': 3,
      });
      expect(h.doc.node(id)!.instance!.overrides, hasLength(2));

      // Clear all overrides.
      _run(h, 'clearPrefabOverrides', {'nodeId': id.toToken()});
      expect(h.doc.node(id)!.instance!.overrides, isEmpty);

      // Undo restores both overrides.
      h.history.undo();
      expect(h.doc.node(id)!.instance!.overrides, hasLength(2));
    });

    test(
      'clearPrefabOverrides on empty overrides is a no-op (empty transaction)',
      () {
        final h = _harness();
        _run(h, 'instantiatePrefab', {
          'prefabAsset': 'assets/tree.fscene',
          'name': 'Tree',
        });
        final id = h.doc.roots.single;
        expect(h.doc.node(id)!.instance!.overrides, isEmpty);
        final before = h.history.transactions.length;
        _run(h, 'clearPrefabOverrides', {'nodeId': id.toToken()});
        // Empty transactions are not pushed onto the history stack.
        expect(h.history.transactions.length, before);
      },
    );

    test('missing required param throws CommandException', () {
      final h = _harness();
      final entry = h.registry.lookup('setNodeName')!;
      expect(
        () => entry.execute(CommandContext(h.doc), {'nodeId': 'n:BADID'}),
        throwsA(isA<CommandException>()),
      );
    });
  });
}
