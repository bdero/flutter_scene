import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene_editor_core/src/change.dart';
import 'package:flutter_scene_editor_core/src/history.dart';
import 'package:test/test.dart';

Transaction _rename(NodeSpec node, String from, String to) => Transaction(
  name: 'Rename to $to',
  records: [
    ChangeRecord(
      targetId: node.id,
      slot: ChangeSlot.name,
      oldValue: StringChange(from),
      newValue: StringChange(to),
    ),
  ],
);

void main() {
  late SceneDocument doc;
  late NodeSpec node;
  late EditHistory history;

  setUp(() {
    doc = SceneDocument(allocator: IdAllocator(session: 1));
    node = doc.createNode(name: 'A', root: true);
    history = EditHistory(DocumentMutator(doc));
  });

  test('commit applies and records', () {
    history.commit(_rename(node, 'A', 'B'));
    expect(doc.node(node.id)!.name, 'B');
    expect(history.canUndo, isTrue);
    expect(history.canRedo, isFalse);
    expect(history.undoLabel, 'Rename to B');
  });

  test('undo then redo restores both ways', () {
    history.commit(_rename(node, 'A', 'B'));
    expect(history.undo(), isTrue);
    expect(doc.node(node.id)!.name, 'A');
    expect(history.canRedo, isTrue);
    expect(history.redo(), isTrue);
    expect(doc.node(node.id)!.name, 'B');
  });

  test('undo past the start returns false and is a no-op', () {
    expect(history.undo(), isFalse);
    expect(doc.node(node.id)!.name, 'A');
  });

  test('committing after an undo truncates the redo tail', () {
    history.commit(_rename(node, 'A', 'B'));
    history.commit(_rename(node, 'B', 'C'));
    history.undo(); // back to B
    expect(doc.node(node.id)!.name, 'B');

    history.commit(_rename(node, 'B', 'D')); // new branch
    expect(doc.node(node.id)!.name, 'D');
    expect(history.canRedo, isFalse);
    expect(history.transactions, hasLength(2));
  });

  test('empty transaction is not recorded', () {
    history.commit(Transaction(name: 'noop', records: const []));
    expect(history.canUndo, isFalse);
    expect(history.transactions, isEmpty);
  });

  test('notifies listeners on commit and undo', () {
    var count = 0;
    history.addListener(() => count++);
    history.commit(_rename(node, 'A', 'B'));
    history.undo();
    expect(count, 2);
  });

  test('cursor tracks applied depth across a sequence', () {
    history.commit(_rename(node, 'A', 'B'));
    history.commit(_rename(node, 'B', 'C'));
    expect(history.cursor, 2);
    history.undo();
    expect(history.cursor, 1);
  });
}
