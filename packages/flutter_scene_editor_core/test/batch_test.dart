// A script that touches a thousand nodes is one undo for the user, and a
// batch that fails part way leaves nothing behind.
import 'dart:convert';
import 'dart:typed_data';

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

  test('only document and selection commands ride in a batch', () {
    final session = EditorSession.empty();
    for (final refused in ['saveDocument', 'setViewportCamera', 'showPanel']) {
      expect(
        () => session.runAll([CommandCall(refused)]),
        throwsA(
          isA<BatchException>().having(
            (e) => e.message,
            'message',
            contains('only document and selection commands'),
          ),
        ),
        reason: '$refused reaches a host that cannot put anything back',
      );
    }
    expect(BatchComposer.acceptedKinds, {
      CommandKind.document,
      CommandKind.selection,
    });
  });

  test('a failed batch puts the selection back too', () {
    final session = EditorSession.empty();
    final kept = LocalId.parse(
      session
          .run('createNode', {'name': 'Kept'})
          .records
          .first
          .targetId
          .toToken(),
    );
    session.run('selectNodes', {
      'nodeIds': [kept.toToken()],
    });

    expect(
      () => session.runAll([
        CommandCall('createNode', {'name': 'Doomed'}),
        CommandCall('selectNodes', {'nodeIds': <String>[]}),
        CommandCall('setNodeName', {'nodeId': 'nope', 'name': 'X'}),
      ]),
      throwsA(isA<BatchException>()),
    );

    expect(session.selection.ids, {
      kept,
    }, reason: 'the selection a failed run changed is restored with the rest');
  });

  test('a later call names what an earlier one created', () {
    final session = EditorSession.empty();
    final bindings = <String, LocalId>{};

    session.runAll([
      CommandCall('createPayload', {
        'bytes': base64Encode(Uint8List(144)),
        'encoding': 'vertexBuffer',
        'layout': 'unskinned_uv1_tangent',
      }, 'verts'),
      CommandCall('createMeshGeometry', {'vertices': r'$verts'}, 'mesh'),
    ], bindings: bindings);

    expect(bindings.keys, containsAll(['verts', 'mesh']));
    final geometry =
        session.document.resources[bindings['mesh']]! as GeometryResource;
    expect(geometry.vertices, bindings['verts']);
    expect(geometry.topology, 'triangle');
    expect(session.history.transactions, hasLength(1));
  });

  test('a reference nothing named is an error, not a bad id', () {
    final session = EditorSession.empty();
    expect(
      () => session.runAll([
        CommandCall('createMeshGeometry', {'vertices': r'$missing'}),
      ]),
      throwsA(
        isA<BatchException>().having(
          (e) => e.message,
          'message',
          contains('no earlier call in this batch named'),
        ),
      ),
    );
  });

  test('an alias over a call that creates nothing fails at the source', () {
    final session = EditorSession.empty();
    final id = LocalId.parse(
      session.run('createNode', {'name': 'A'}).records.first.targetId.toToken(),
    );
    expect(
      () => session.runAll([
        CommandCall('selectNodes', {
          'nodeIds': [id.toToken()],
        }, 'nothing'),
      ]),
      throwsA(
        isA<BatchException>().having(
          (e) => e.message,
          'message',
          contains('created nothing'),
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
      CommandCall.fromJson({'command': 'createNode', 'as': 'made'}).alias,
      'made',
    );
    expect(
      () => CommandCall.fromJson({'command': 'createNode', 'as': ''}),
      throwsA(isA<CommandException>()),
    );
    expect(
      () => CommandCall.fromJson(const {'params': {}}),
      throwsA(isA<CommandException>()),
    );
  });
}
