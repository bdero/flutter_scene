import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

LocalId _instantiate(EditorSession s) {
  final tx = s.run('instantiatePrefab', {
    'prefabAsset': 'p.fscene',
    'name': 'inst',
  });
  return tx.records.first.targetId;
}

void main() {
  test('attachToPrefabMember adds a node, child link, and attachment', () {
    final s = EditorSession.empty();
    final instId = _instantiate(s);
    final bone = s.document.newId(); // a prefab-local parent id token
    final before = s.document.nodes.length;

    s.run('attachToPrefabMember', {
      'nodeId': instId.toToken(),
      'parent': bone.toToken(),
      'name': 'prop',
    });

    expect(s.document.nodes.length, before + 1);
    final instance = s.document.nodes[instId]!.instance!;
    expect(instance.attachments, hasLength(1));
    final attached = instance.attachments.single;
    expect(attached.parent, bone);
    // The attached node is a real node and a child of the instance.
    expect(s.document.nodes.containsKey(attached.node), isTrue);
    expect(s.document.nodes[instId]!.children, contains(attached.node));
    expect(s.document.nodes[attached.node]!.name, 'prop');

    // Undo removes the attachment and the node.
    s.undo();
    expect(s.document.nodes.length, before);
    expect(s.document.nodes[instId]!.instance!.attachments, isEmpty);
  });

  test('attachToPrefabMember with no parent attaches at the instance root', () {
    final s = EditorSession.empty();
    final instId = _instantiate(s);
    s.run('attachToPrefabMember', {'nodeId': instId.toToken()});
    expect(
      s.document.nodes[instId]!.instance!.attachments.single.parent,
      isNull,
    );
  });

  test('removePrefabMember records a removed prefab node', () {
    final s = EditorSession.empty();
    final instId = _instantiate(s);
    final target = s.document.newId();

    s.run('removePrefabMember', {
      'nodeId': instId.toToken(),
      'target': target.toToken(),
    });
    expect(s.document.nodes[instId]!.instance!.removedNodes, contains(target));

    // Re-removing the same node is a no-op.
    final before = s.history.transactions.length;
    final tx = s.run('removePrefabMember', {
      'nodeId': instId.toToken(),
      'target': target.toToken(),
    });
    expect(tx.isEmpty, isTrue);
    expect(s.history.transactions.length, before);
  });

  test('the prefab member commands reject a non-instance node', () {
    final s = EditorSession.empty();
    final tx = s.run('createNode', {'name': 'plain'});
    final id = tx.records.first.targetId;
    expect(
      () => s.run('attachToPrefabMember', {'nodeId': id.toToken()}),
      throwsA(isA<CommandException>()),
    );
    expect(
      () => s.run('removePrefabMember', {
        'nodeId': id.toToken(),
        'target': id.toToken(),
      }),
      throwsA(isA<CommandException>()),
    );
  });
}
