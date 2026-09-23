// The protocol as a client sees it over the wire: read in bulk, edit in one
// step, hear what changed, and ask what this build can do.
import 'dart:convert';
import 'dart:typed_data';

import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

EditorSession _session() =>
    EditorSession(SceneDocument(allocator: IdAllocator(session: 1)));

void main() {
  test('the bootstrap set offers the protocol verbs', () {
    final names = EditorToolSurface.of(
      _session(),
    ).bootstrapTools().map((t) => t.name).toSet();
    expect(
      names,
      containsAll([
        'run_commands',
        'run_query',
        'search_queries',
        'subscribe_events',
        'poll_events',
        'unsubscribe_events',
        'get_protocol_info',
      ]),
    );
  });

  test('a client asks what this build speaks', () async {
    final info = await EditorToolSurface.of(
      _session(),
    ).dispatch('get_protocol_info', const {});
    expect(info['version'], EditorProtocol.version);
    expect(info['capabilities'], contains('batch'));
    expect(info['capabilities'], contains('base64Blobs'));
    expect(
      info['capabilities'],
      isNot(contains('binaryFrames')),
      reason: 'JSON-RPC cannot frame binary, and the answer should say so',
    );
    expect(info['events'], contains('selectionChanged'));
    expect(info['queryCount'], greaterThan(0));
  });

  test(
    'a client can ask what this build speaks before opening anything',
    () async {
      final info = await EditorToolSurface(
        () => null,
      ).dispatch('get_protocol_info', const {});
      expect(info['version'], EditorProtocol.version);
      expect(info['documentOpen'], isFalse);
      expect(info.containsKey('queryCount'), isFalse);
    },
  );

  test('a thousand commands land as one undo step', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);
    final result = await surface.dispatch('run_commands', {
      'commands': [
        for (var i = 0; i < 1000; i++)
          {
            'command': 'createNode',
            'params': {'name': 'Node$i'},
          },
      ],
      'name': 'Scatter',
    });

    expect(result['ok'], isTrue);
    expect(result['commandCount'], 1000);
    expect(result['applied'], 'Scatter');
    expect(session.document.nodes, hasLength(1000));
    expect(session.history.transactions, hasLength(1));

    await surface.dispatch('undo', const {});
    expect(session.document.nodes, isEmpty);
  });

  test('a batch that fails keeps nothing and says where it stopped', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);
    await expectLater(
      surface.dispatch('run_commands', {
        'commands': [
          {
            'command': 'createNode',
            'params': {'name': 'A'},
          },
          {
            'command': 'setNodeName',
            'params': {'nodeId': 'nope', 'name': 'B'},
          },
        ],
      }),
      throwsA(
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          allOf(contains('1'), contains('setNodeName')),
        ),
      ),
    );
    expect(session.document.nodes, isEmpty);
  });

  test('run_query reads a subtree in one call', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);
    await surface.dispatch('run_command', {
      'command': 'createNode',
      'params': {'name': 'Root'},
    });

    final result = await surface.dispatch('run_query', {
      'query': 'nodeSubtree',
    });
    final nodes = result['nodes'] as List;
    expect(nodes, hasLength(1));
    expect((nodes.single as Map)['name'], 'Root');
  });

  test('payload bytes come back base64 under blobs', () async {
    final session = _session();
    final payload = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned_uv1_tangent',
        bytes: Uint8List.fromList(List.generate(32, (i) => i)),
        length: 32,
      ),
    );

    final result = await EditorToolSurface.of(session).dispatch('run_query', {
      'query': 'readPayload',
      'params': {'payloadId': payload.id.toToken()},
    });

    expect(result['totalBytes'], 32);
    final blobs = result['blobs'] as Map<String, Object?>;
    final blob = blobs[result['blob']] as Map<String, Object?>;
    expect(blob['byteCount'], 32);
    expect(base64Decode(blob['base64'] as String), List.generate(32, (i) => i));
  });

  test('search_queries answers with argument schemas', () async {
    final result = await EditorToolSurface.of(
      _session(),
    ).dispatch('search_queries', {'query': 'payload'});
    final queries = result['queries'] as List;
    expect(queries.map((q) => (q as Map)['name']), contains('readPayload'));
    expect((queries.first as Map)['inputSchema'], isA<Map<String, Object?>>());
  });

  test('a bad query name is an error the client can act on', () async {
    await expectLater(
      EditorToolSurface.of(
        _session(),
      ).dispatch('run_query', {'query': 'noSuchQuery'}),
      throwsA(isA<ToolError>()),
    );
  });

  test('subscribe, edit, poll, unsubscribe', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);

    final subscribed = await surface.dispatch('subscribe_events', {
      'types': ['documentChanged', 'historyChanged'],
    });
    final id = subscribed['subscription'] as String;

    await surface.dispatch('run_commands', {
      'commands': [
        for (var i = 0; i < 10; i++)
          {
            'command': 'createNode',
            'params': {'name': 'N$i'},
          },
      ],
    });

    final polled = await surface.dispatch('poll_events', {'subscription': id});
    final events = polled['events'] as List;
    expect(
      events.map((e) => (e as Map)['type']),
      containsAll(['documentChanged', 'historyChanged']),
    );
    expect(
      events.where((e) => (e as Map)['type'] == 'documentChanged'),
      hasLength(1),
      reason: 'ten edits in one batch are one notification',
    );
    expect(polled['dropped'], 0);

    expect(
      ((await surface.dispatch('poll_events', {'subscription': id}))['events']
          as List),
      isEmpty,
      reason: 'a drain takes what it reported',
    );

    await surface.dispatch('unsubscribe_events', {'subscription': id});
    await expectLater(
      surface.dispatch('poll_events', {'subscription': id}),
      throwsA(isA<ToolError>()),
    );
  });

  test('subscribing to an event this build does not emit fails', () async {
    await expectLater(
      EditorToolSurface.of(_session()).dispatch('subscribe_events', {
        'types': ['nodeWiggled'],
      }),
      throwsA(
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          contains('nodeWiggled'),
        ),
      ),
    );
  });

  test('the compact scene view is a projection of the query', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);
    await surface.dispatch('run_commands', {
      'commands': [
        {
          'command': 'createNode',
          'params': {'name': 'Root'},
        },
      ],
    });
    final root = session.document.roots.single.toToken();
    await surface.dispatch('run_command', {
      'command': 'createNode',
      'params': {'name': 'Child', 'parentId': root},
    });

    final described = await surface.dispatch('describe_scene', const {});
    final queried = session.ask('nodeSubtree').body;

    final describedRoot = (described['roots'] as List).single as Map;
    final queriedRoot = (queried['nodes'] as List).single as Map;
    expect(describedRoot['id'], queriedRoot['id']);
    expect(describedRoot['path'], queriedRoot['path']);
    expect(
      (describedRoot['children'] as List).single,
      isA<Map<String, Object?>>().having(
        (child) => child['name'],
        'name',
        'Child',
      ),
    );
    expect(
      describedRoot['components'],
      isA<List<Object?>>(),
      reason: 'the compact view keeps component types, not whole components',
    );
  });

  test('list_resources answers with the query it wraps', () async {
    final session = _session();
    final geometry = GeometryResource(
      session.document.newId(),
      procedural: CuboidGeometrySpec(extents: Vector3.all(1)),
    );
    session.document.resources[geometry.id] = geometry;

    final listed = await EditorToolSurface.of(
      session,
    ).dispatch('list_resources', const {});
    expect(listed, session.ask('listResources').body);
  });

  test('one connection cannot reach another connection\'s events', () async {
    final session = _session();
    final mine = EditorToolSurface.of(session);
    final theirs = EditorToolSurface.of(session);

    final subscribed = await mine.dispatch('subscribe_events', {
      'types': ['documentChanged'],
    });
    final id = subscribed['subscription'] as String;

    await expectLater(
      theirs.dispatch('poll_events', {'subscription': id}),
      throwsA(
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          contains('another client'),
        ),
      ),
      reason: 'the bus is shared, the subscriptions are not',
    );
    await expectLater(
      theirs.dispatch('unsubscribe_events', {'subscription': id}),
      throwsA(isA<ToolError>()),
    );
    expect(
      ((await mine.dispatch('poll_events', {'subscription': id}))['events']
          as List),
      isEmpty,
      reason: 'and the owner still has it',
    );
  });

  test('a disconnected client leaves nothing buffering', () async {
    final session = _session();
    final surface = EditorToolSurface.of(session);
    await surface.dispatch('subscribe_events', {
      'types': ['documentChanged'],
    });
    expect(session.events.subscriptions, hasLength(1));

    surface.dispose();

    expect(session.events.subscriptions, isEmpty);
    session.run('createNode', {'name': 'Unheard'});
    session.events.flush();
  });

  test('a batch call can name what it creates for the next one', () async {
    final session = _session();
    final result = await EditorToolSurface.of(session).dispatch(
      'run_commands',
      {
        'commands': [
          {
            'command': 'createPayload',
            'as': 'verts',
            'params': {
              'bytes': base64Encode(Uint8List(144)),
              'encoding': 'vertexBuffer',
              'layout': 'unskinned_uv1_tangent',
            },
          },
          {
            'command': 'createMeshGeometry',
            'params': {'vertices': r'$verts'},
          },
        ],
        'name': 'Build a mesh',
      },
    );

    expect(result['ok'], isTrue);
    final bound = result['bindings'] as Map<String, Object?>;
    expect(bound['verts'], isA<String>());
    final geometry = session.document.resources.values
        .whereType<GeometryResource>()
        .single;
    expect(geometry.vertices!.toToken(), bound['verts']);
    expect(session.history.transactions, hasLength(1));
  });

  test('a host-routed batch goes through the host, not the session', () async {
    final session = _session();
    var routed = 0;
    final surface = EditorToolSurface(
      () => session,
      batchRunner: (calls, name, bindings) async {
        routed++;
        return session.runAll(
          calls,
          name: name ?? 'Batch edit',
          bindings: bindings,
        );
      },
    );

    await surface.dispatch('run_commands', {
      'commands': [
        {
          'command': 'createNode',
          'params': {'name': 'Routed'},
        },
      ],
    });

    expect(routed, 1);
    expect(session.document.nodes, hasLength(1));

    // A host-routed failure reads like any other, not as a stack trace.
    await expectLater(
      surface.dispatch('run_commands', {
        'commands': [
          {
            'command': 'setNodeName',
            'params': {'nodeId': 'nope', 'name': 'X'},
          },
        ],
      }),
      throwsA(
        isA<ToolError>().having(
          (e) => e.message,
          'message',
          isNot(contains('#0')),
        ),
      ),
    );
  });
}
