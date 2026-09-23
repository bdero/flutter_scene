// A script that touches a thousand nodes is one undo for the user, and a
// batch that fails part way leaves nothing behind.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';

void main() {
  test('a batch is one history step', () {
    final session = EditorSession.empty();
    final transaction = session.runAll([
      for (var i = 0; i < 1000; i++)
        CommandCall('createNode', {'name': 'Node$i'}),
    ], name: 'Build a thousand');

    expect(session.document.nodes, hasLength(1000));
    expect(session.history.transactions, hasLength(1));
    expect(transaction.name, 'Build a thousand');

    session.undo();
    expect(session.document.nodes, isEmpty);
    session.redo();
    expect(session.document.nodes, hasLength(1000));
  });

  test('a call sees what the calls before it did', () {
    final session = EditorSession.empty();
    final created = session.run('createNode', {'name': 'Parent'});
    final parent = LocalId.parse(created.records.first.targetId.toToken());
    session.history.clear();

    session.runAll([
      CommandCall('createNode', {
        'name': 'Child',
        'parentId': parent.toToken(),
      }),
      CommandCall('setNodeName', {
        'nodeId': parent.toToken(),
        'name': 'Renamed',
      }),
    ]);

    expect(session.document.node(parent)!.name, 'Renamed');
    expect(session.document.node(parent)!.children, hasLength(1));
    expect(session.history.transactions, hasLength(1));
  });

  test('a failure reverts the run and names the call that stopped it', () {
    final session = EditorSession.empty();
    final before = writeFscene(session.document);

    expect(
      () => session.runAll([
        CommandCall('createNode', {'name': 'A'}),
        CommandCall('createNode', {'name': 'B'}),
        CommandCall('setNodeName', {'nodeId': 'nope', 'name': 'C'}),
      ]),
      throwsA(
        isA<BatchException>()
            .having((e) => e.index, 'index', 2)
            .having((e) => e.command, 'command', 'setNodeName'),
      ),
    );

    expect(writeFscene(session.document), before, reason: 'nothing survives');
    expect(session.history.transactions, isEmpty);
    expect(session.isDirty, isFalse);
  });

  test('an unknown command stops the batch before anything applies', () {
    final session = EditorSession.empty();
    expect(
      () => session.runAll([
        CommandCall('createNode', {'name': 'A'}),
        const CommandCall('noSuchCommand'),
      ]),
      throwsA(
        isA<BatchException>().having(
          (e) => e.message,
          'message',
          contains('noSuchCommand'),
        ),
      ),
    );
    expect(session.document.nodes, isEmpty);
  });

  test('an application command cannot ride in a batch', () {
    final session = EditorSession.empty();
    expect(
      () => session.runAll([const CommandCall('saveDocument')]),
      throwsA(
        isA<BatchException>().having(
          (e) => e.message,
          'message',
          contains('asynchronous'),
        ),
      ),
    );
  });

  test('a batch entry decodes from its wire form', () {
    final call = CommandCall.fromJson({
      'command': 'createNode',
      'params': {'name': 'Wire'},
    });
    expect(call.name, 'createNode');
    expect(call.params['name'], 'Wire');
    expect(
      () => CommandCall.fromJson(const {'params': {}}),
      throwsA(isA<CommandException>()),
    );
  });
}
