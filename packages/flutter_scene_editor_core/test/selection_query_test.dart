import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

EditorSession _session() =>
    EditorSession(SceneDocument(allocator: IdAllocator(session: 1)));

void main() {
  group('SceneQuery', () {
    test('navigates parents, children, subtree, and name paths', () {
      final s = _session();
      final root = s.run('createNode', {'name': 'Root'}).records.first.targetId;
      final mid = s.run('createNode', {
        'name': 'Mid',
        'parentId': root.toToken(),
      }).records.first.targetId;
      final leaf = s.run('createNode', {
        'name': 'Leaf',
        'parentId': mid.toToken(),
      }).records.first.targetId;

      expect(s.query.roots.map((n) => n.name), ['Root']);
      expect(s.query.childrenOf(root).map((n) => n.name), ['Mid']);
      expect(s.query.parentOf(leaf), mid);
      expect(s.query.parentOf(root), isNull);
      expect(s.query.subtreeOf(root), [root, mid, leaf]);
      expect(s.query.namePathOf(leaf), 'Root/Mid/Leaf');
      expect(s.query.nodeByNamePath(['Root', 'Mid', 'Leaf'])?.id, leaf);
      expect(s.query.nodeByNamePath(['Root', 'Nope']), isNull);
    });

    test('finds components by type', () {
      final s = _session();
      final id = s.run('createNode', {'name': 'A'}).records.first.targetId;
      s.run('addComponent', {
        'nodeId': id.toToken(),
        'componentType': 'directionalLight',
      });
      expect(s.query.componentOf(id, 'directionalLight'), isNotNull);
      expect(s.query.componentOf(id, 'mesh'), isNull);
    });
  });

  group('Selection', () {
    test('selectOnly, add, toggle, remove, clear with primary tracking', () {
      final sel = Selection();
      const a = LocalId(1, 1);
      const b = LocalId(1, 2);

      sel.selectOnly(a);
      expect(sel.ids, {a});
      expect(sel.primary, a);

      sel.add(b);
      expect(sel.ids, {a, b});
      expect(sel.primary, b);

      sel.toggle(b);
      expect(sel.ids, {a});
      expect(sel.primary, a);

      sel.remove(a);
      expect(sel.isEmpty, isTrue);
      expect(sel.primary, isNull);
    });

    test('notifies on change', () {
      final sel = Selection();
      var count = 0;
      sel.addListener(() => count++);
      sel.selectOnly(const LocalId(1, 1));
      sel.clear();
      expect(count, 2);
    });
  });

  test('session prunes selection when a selected node is deleted', () {
    final s = _session();
    final id = s.run('createNode', {'name': 'A'}).records.first.targetId;
    s.selection.selectOnly(id);
    expect(s.selection.contains(id), isTrue);

    s.run('deleteNode', {'nodeId': id.toToken()});
    expect(s.selection.contains(id), isFalse);
    expect(s.selection.isEmpty, isTrue);

    // Undo brings the node back; selection stays pruned (selection is not
    // undoable), which is the documented behavior.
    s.undo();
    expect(s.query.node(id), isNotNull);
    expect(s.selection.contains(id), isFalse);
  });
}
