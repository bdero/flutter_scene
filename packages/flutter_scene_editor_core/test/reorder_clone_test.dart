import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/property_value.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

/// Creates a node (optionally under [parent]) and returns its new id.
LocalId _create(EditorSession s, String name, {LocalId? parent}) {
  final tx = s.run('createNode', {
    'name': name,
    if (parent != null) 'parentId': parent.toToken(),
  });
  return tx.records.first.targetId;
}

List<String> _names(EditorSession s, List<LocalId> ids) => [
  for (final id in ids) s.document.nodes[id]!.name,
];

void main() {
  group('reparentNode reorder and unparent', () {
    test('reorders a root to the front by index', () {
      final s = EditorSession.empty();
      _create(s, 'A');
      _create(s, 'B');
      final c = _create(s, 'C');
      expect(_names(s, s.document.roots), ['A', 'B', 'C']);

      s.run('reparentNode', {'nodeId': c.toToken(), 'index': 0});
      expect(_names(s, s.document.roots), ['C', 'A', 'B']);
    });

    test('reorder to the current position is a no-op (no history entry)', () {
      final s = EditorSession.empty();
      final a = _create(s, 'A');
      _create(s, 'B');
      final before = s.history.transactions.length;
      // A is already at index 0.
      final tx = s.run('reparentNode', {'nodeId': a.toToken(), 'index': 0});
      expect(tx.isEmpty, isTrue);
      expect(s.history.transactions.length, before);
    });

    test('omitting the index keeps the old same-parent no-op behavior', () {
      final s = EditorSession.empty();
      final a = _create(s, 'A');
      final tx = s.run('reparentNode', {'nodeId': a.toToken()});
      expect(tx.isEmpty, isTrue);
    });

    test('unparents a child to the root list', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final x = _create(s, 'X', parent: p);
      expect(s.document.nodes[p]!.children, [x]);

      s.run('reparentNode', {'nodeId': x.toToken()}); // no parent -> root
      expect(s.document.nodes[p]!.children, isEmpty);
      expect(s.document.roots, contains(x));
    });

    test('reparents into a parent at a specific index', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final c0 = _create(s, 'C0', parent: p);
      _create(s, 'C1', parent: p);
      final loose = _create(s, 'Loose');

      s.run('reparentNode', {
        'nodeId': loose.toToken(),
        'newParentId': p.toToken(),
        'index': 1,
      });
      expect(_names(s, s.document.nodes[p]!.children), ['C0', 'Loose', 'C1']);
      expect(s.document.roots, isNot(contains(loose)));
      expect(s.document.nodes[p]!.children.first, c0);
    });

    test('rejects reparenting under a descendant', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final c = _create(s, 'C', parent: p);
      expect(
        () => s.run('reparentNode', {
          'nodeId': p.toToken(),
          'newParentId': c.toToken(),
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });

  group('duplicateNodes', () {
    test('clones a subtree in place with fresh ids, after the original', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      _create(s, 'Child', parent: p);
      final nodesBefore = s.document.nodes.length;

      final tx = s.run('duplicateNodes', {
        'nodeIds': [p.toToken()],
      });
      // Two new nodes (P' and Child').
      expect(s.document.nodes.length, nodesBefore + 2);
      // The clone is a root right after the original.
      expect(s.document.roots.length, 2);
      expect(s.document.roots.first, p);
      final cloneRoot = s.document.roots[1];
      expect(cloneRoot, isNot(p));
      expect(s.document.nodes[cloneRoot]!.name, 'P');
      expect(s.document.nodes[cloneRoot]!.children, hasLength(1));
      // The clone's child is a fresh node, not the original's child.
      final origChild = s.document.nodes[p]!.children.single;
      expect(s.document.nodes[cloneRoot]!.children.single, isNot(origChild));

      // Undo removes exactly the clones.
      s.undo();
      expect(s.document.nodes.length, nodesBefore);
      expect(s.document.roots, [p]);
      // The transaction's attach record exposes the new root.
      expect(tx.records.whereType<ChangeRecord>().isNotEmpty, isTrue);
    });

    test('duplicates several siblings in one parent in order', () {
      final s = EditorSession.empty();
      final a = _create(s, 'A');
      final b = _create(s, 'B');
      s.run('duplicateNodes', {
        'nodeIds': [a.toToken(), b.toToken()],
      });
      expect(_names(s, s.document.roots), ['A', 'A', 'B', 'B']);
      // The clones are distinct ids from the originals.
      expect(s.document.roots.toSet(), hasLength(4));
      expect(s.document.roots[0], a);
      expect(s.document.roots[2], b);
    });

    test('skips a selected node nested under another selected node', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final c = _create(s, 'C', parent: p);
      final before = s.document.nodes.length;
      s.run('duplicateNodes', {
        'nodeIds': [p.toToken(), c.toToken()], // c is under p
      });
      // Only P's subtree (P + C) is duplicated: +2, not +3.
      expect(s.document.nodes.length, before + 2);
    });

    test('remaps in-subtree node references in the clone', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final c = _create(s, 'C', parent: p);
      // Give P a component referencing its child C by node ref.
      s.run('addComponent', {
        'nodeId': p.toToken(),
        'componentType': 'lookAt',
        'properties': {
          'target': {'\$node': c.toToken()},
        },
      });

      s.run('duplicateNodes', {
        'nodeIds': [p.toToken()],
      });
      final cloneRoot = s.document.roots[1];
      final cloneChild = s.document.nodes[cloneRoot]!.children.single;
      final ref =
          s.document.nodes[cloneRoot]!.components.single.properties['target']
              as NodeRefValue;
      // The clone references its own child, not the original's child.
      expect(ref.id, cloneChild);
      expect(ref.id, isNot(c));
    });
  });

  group('pasteNodes', () {
    test('inserts captured subtrees with fresh ids under a parent', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      _create(s, 'Child', parent: p);
      final clip = captureSubtree(s.document, p);
      final target = _create(s, 'Target');
      final before = s.document.nodes.length;

      s.run('pasteNodes', {
        'parentId': target.toToken(),
        'subtrees': [clip],
      });
      // P + Child cloned under Target.
      expect(s.document.nodes.length, before + 2);
      expect(s.document.nodes[target]!.children, hasLength(1));
      final pasted = s.document.nodes[target]!.children.single;
      expect(s.document.nodes[pasted]!.name, 'P');
      expect(pasted, isNot(p));
    });

    test('captured subtree is immune to later edits of the source', () {
      final s = EditorSession.empty();
      final p = _create(s, 'P');
      final clip = captureSubtree(s.document, p);
      s.run('setNodeName', {'nodeId': p.toToken(), 'name': 'Renamed'});

      s.run('pasteNodes', {
        'subtrees': [clip],
      });
      final pasted = s.document.roots.last;
      expect(s.document.nodes[pasted]!.name, 'P');
    });
  });

  group('deleteNodes', () {
    test('deletes several subtrees in one undoable step', () {
      final s = EditorSession.empty();
      final a = _create(s, 'A');
      _create(s, 'A-child', parent: a);
      final b = _create(s, 'B');
      final before = s.history.transactions.length;

      s.run('deleteNodes', {
        'nodeIds': [a.toToken(), b.toToken()],
      });
      expect(s.document.nodes, isEmpty);
      expect(s.document.roots, isEmpty);
      expect(s.history.transactions.length, before + 1);

      s.undo();
      expect(_names(s, s.document.roots), ['A', 'B']);
      expect(s.document.nodes[a]!.children, hasLength(1));
    });
  });
}
