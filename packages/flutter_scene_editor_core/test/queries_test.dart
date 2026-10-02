// The read half of the protocol. A caller that cannot read in bulk, or read
// payload bytes at all, cannot write a tool the engine does not ship.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

LocalId _node(EditorSession s, String name, {LocalId? parent}) => LocalId.parse(
  s
      .run('createNode', {
        'name': name,
        if (parent != null) 'parentId': parent.toToken(),
      })
      .records
      .first
      .targetId
      .toToken(),
);

void main() {
  test('a subtree comes back in one call, to the depth asked for', () {
    final session = EditorSession.empty();
    final root = _node(session, 'Root');
    final child = _node(session, 'Child', parent: root);
    _node(session, 'Grandchild', parent: child);

    final whole = session.ask('nodeSubtree', {'nodeId': root.toToken()});
    final rootJson = (whole.body['nodes'] as List).single as Map;
    expect(rootJson['name'], 'Root');
    expect(rootJson['path'], 'Root');
    final childJson = (rootJson['children'] as List).single as Map;
    expect(childJson['name'], 'Child');
    expect((childJson['children'] as List), hasLength(1));

    final shallow = session.ask('nodeSubtree', {
      'nodeId': root.toToken(),
      'depth': 0,
    });
    final shallowRoot = (shallow.body['nodes'] as List).single as Map;
    expect(shallowRoot.containsKey('children'), isFalse);
    expect(shallowRoot['childCount'], 1);
  });

  test('the roots come back when no node is named', () {
    final session = EditorSession.empty();
    _node(session, 'A');
    _node(session, 'B');
    final result = session.ask('nodeSubtree');
    expect((result.body['nodes'] as List), hasLength(2));
  });

  test('component properties are opt-in', () {
    final session = EditorSession.empty();
    final id = _node(session, 'Lit');
    session.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': 'directionalLight',
    });

    final without = session.ask('nodeSubtree', {'nodeId': id.toToken()});
    final bare =
        ((without.body['nodes'] as List).single as Map)['components'] as List;
    expect((bare.single as Map).containsKey('properties'), isFalse);

    final with_ = session.ask('nodeSubtree', {
      'nodeId': id.toToken(),
      'components': true,
    });
    final full =
        ((with_.body['nodes'] as List).single as Map)['components'] as List;
    expect((full.single as Map)['properties'], isA<Map<String, Object?>>());
  });

  test('findNodes filters and reports what it truncated', () {
    final session = EditorSession.empty();
    for (var i = 0; i < 5; i++) {
      _node(session, 'Crate$i');
    }
    _node(session, 'Floor');

    final crates = session.ask('findNodes', {'name': 'crate'});
    expect((crates.body['nodes'] as List), hasLength(5));
    expect(crates.body['truncated'], isFalse);

    final capped = session.ask('findNodes', {'name': 'crate', 'limit': 2});
    expect((capped.body['nodes'] as List), hasLength(2));
    expect(capped.body['total'], 5);
    expect(capped.body['truncated'], isTrue);

    final exact = session.ask('findNodes', {'exactName': 'Floor'});
    expect((exact.body['nodes'] as List), hasLength(1));
  });

  test('payload bytes come back as a blob the body points at', () {
    final session = EditorSession.empty();
    final payload = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned_uv1_tangent',
        bytes: Uint8List.fromList(List.generate(64, (i) => i)),
        length: 64,
      ),
    );

    final whole = session.ask('readPayload', {
      'payloadId': payload.id.toToken(),
    });
    expect(whole.body['totalBytes'], 64);
    expect(whole.body['byteCount'], 64);
    expect(whole.body['encoding'], 'vertexBuffer');
    expect(whole.body['layout'], 'unskinned_uv1_tangent');
    expect(whole.blobs.single.id, whole.body['blob']);
    expect(whole.blobs.single.bytes, hasLength(64));
    expect(whole.blobs.single.bytes.first, 0);

    final slice = session.ask('readPayload', {
      'payloadId': payload.id.toToken(),
      'offset': 60,
      'length': 16,
    });
    expect(slice.body['byteCount'], 4, reason: 'clamped to what is there');
    expect(slice.blobs.single.bytes, [60, 61, 62, 63]);
  });

  test('reading a payload that is not there says so', () {
    final session = EditorSession.empty();
    expect(
      () => session.ask('readPayload', {'payloadId': 'not-a-token'}),
      throwsA(isA<QueryException>()),
    );
    final descriptorOnly = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.bytes,
        length: 128,
      ),
    );
    expect(
      () => session.ask('readPayload', {
        'payloadId': descriptorOnly.id.toToken(),
      }),
      throwsA(
        isA<QueryException>().having(
          (e) => e.message,
          'message',
          contains('sidecar'),
        ),
      ),
    );
  });

  test('a geometry resource names the payloads behind it', () {
    final session = EditorSession.empty();
    final vertices = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned_uv1_tangent',
        bytes: Uint8List(16),
        length: 16,
      ),
    );
    final geometry = GeometryResource(
      session.document.newId(),
      vertices: vertices.id,
    );
    session.document.resources[geometry.id] = geometry;

    final result = session.ask('getResource', {
      'resourceId': geometry.id.toToken(),
    });
    expect(result.body['kind'], 'geometry');
    expect(result.body['vertices'], vertices.id.toToken());

    final listed = session.ask('listResources', {'kind': 'geometry'});
    expect((listed.body['resources'] as List), hasLength(1));
    expect(
      (session.ask('listResources', {'kind': 'texture'}).body['resources']
          as List),
      isEmpty,
    );
  });

  test('the document summary reports counts and undo state', () {
    final session = EditorSession.empty();
    _node(session, 'A');
    final summary = session.ask('documentSummary').body;
    expect(summary['nodeCount'], 1);
    expect((summary['history'] as Map)['canUndo'], isTrue);
    expect((summary['history'] as Map)['undoLabel'], isNotNull);
  });

  test('a client can learn the whole surface at runtime', () {
    final session = EditorSession.empty();
    final commands = session.ask('listCommands').body['commands'] as List;
    expect(commands, isNotEmpty);
    final first = commands.first as Map;
    expect(first['name'], isA<String>());
    expect(first['inputSchema'], isA<Map<String, Object?>>());
    expect(first['kind'], isA<String>());

    final queries = session.ask('listQueries').body['queries'] as List;
    expect(
      queries.map((q) => (q as Map)['name']),
      containsAll(['nodeSubtree', 'readPayload', 'listCommands']),
    );
  });

  test('a node carries the fields that change how it renders', () {
    final session = EditorSession.empty();
    final id = _node(session, 'Prop');
    session.document.node(id)!
      ..layers = 5
      ..shadowCastingMode = 'shadowsOnly'
      ..visible = false;

    final node =
        (session.ask('nodeSubtree', {'nodeId': id.toToken()}).body['nodes']
                    as List)
                .single
            as Map;
    expect(node['layers'], 5);
    expect(node['shadowCastingMode'], 'shadowsOnly');
    expect(node['visible'], isFalse);
  });

  test('defaults are stated, not left for a client to know', () {
    final session = EditorSession.empty();
    final id = _node(session, 'Plain');
    final node =
        (session.ask('nodeSubtree', {'nodeId': id.toToken()}).body['nodes']
                    as List)
                .single
            as Map;
    expect(node['layers'], 1);
    expect(node['shadowCastingMode'], 'on');
    expect(node['visible'], isTrue);
  });

  test('a procedural geometry keeps its descriptor and bounds', () {
    final session = EditorSession.empty();
    final created = session.run('createCuboidGeometry', {
      'extents': {'x': 2.0, 'y': 3.0, 'z': 4.0},
    });
    final id = created.records.single.targetId;

    final body = session.ask('getResource', {'resourceId': id.toToken()}).body;
    expect(body['kind'], 'geometry');
    expect(
      body['procedural'],
      isA<Map<String, Object?>>().having((p) => p['shape'], 'shape', 'cuboid'),
    );
  });

  test('a render texture keeps its update policy and sampling', () {
    final session = EditorSession.empty();
    final resource = RenderTextureResource(
      session.document.newId(),
      width: 256,
      height: 128,
      update: 'onDemand',
      intervalMilliseconds: 250,
      filter: 'nearest',
      wrap: 'repeat',
    );
    session.document.resources[resource.id] = resource;

    final body = session.ask('getResource', {
      'resourceId': resource.id.toToken(),
    }).body;
    expect(body['width'], 256);
    expect(body['update'], 'onDemand');
    expect(body['intervalMilliseconds'], 250);
    expect(body['filter'], 'nearest');
    expect(body['wrap'], 'repeat');
  });

  test('an environment keeps its lighting settings', () {
    final session = EditorSession.empty();
    final resource = EnvironmentResource(
      session.document.newId(),
      name: 'Dusk',
      exposure: 2.5,
      toneMapping: 'agx',
      environmentRotationY: 1.25,
    );
    session.document.resources[resource.id] = resource;

    final body = session.ask('getResource', {
      'resourceId': resource.id.toToken(),
    }).body;
    expect(body['name'], 'Dusk');
    expect(body['exposure'], 2.5);
    expect(body['toneMapping'], 'agx');
    expect(body['environmentRotationY'], 1.25);
    expect(body['environment'], isA<Map<String, Object?>>());
  });

  test('createPayload refuses data the renderer cannot read', () {
    final session = EditorSession.empty();
    expect(
      () => session.run('createPayload', {
        'bytes': base64Encode(Uint8List(72)),
        'encoding': 'vertexBuffer',
        'layout': 'not_a_layout',
      }),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('known "layout"'),
        ),
      ),
    );
    expect(
      () => session.run('createPayload', {
        'bytes': base64Encode(Uint8List(7)),
        'encoding': 'indexBuffer',
        'format': 'uint16',
      }),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('whole number'),
        ),
      ),
    );
  });

  test('createMeshGeometry checks each payload is for its role', () {
    final session = EditorSession.empty();
    final image = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.image,
        format: 'rgba8',
        bytes: Uint8List(16),
        length: 16,
      ),
    );
    expect(
      () => session.run('createMeshGeometry', {'vertices': image.id.toToken()}),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('needs a vertexBuffer payload'),
        ),
      ),
    );

    final verts = session.document.addPayload(
      PayloadSpec(
        session.document.newId(),
        encoding: PayloadEncoding.vertexBuffer,
        layout: 'unskinned_uv1_tangent',
        bytes: Uint8List(72),
        length: 72,
      ),
    );
    expect(
      () => session.run('createMeshGeometry', {
        'vertices': verts.id.toToken(),
        'topology': 'triangles',
      }),
      throwsA(
        isA<CommandException>().having(
          (e) => e.message,
          'message',
          contains('Unknown topology'),
        ),
      ),
    );
  });

  test('bytes go in through a command and come back out through a query', () {
    final session = EditorSession.empty();
    final data = Uint8List.fromList(List.generate(48, (i) => i * 2));

    final made = session.runAll([
      CommandCall('createPayload', {
        'bytes': base64Encode(data),
        'encoding': 'vertexBuffer',
        'layout': 'unskinned_uv1_tangent',
      }),
    ]);
    final payloadId = made.records
        .where((r) => r.slot == ChangeSlot.poolPayload)
        .single
        .targetId;

    final geometry = session.run('createMeshGeometry', {
      'vertices': payloadId.toToken(),
    });
    final geometryId = geometry.records.single.targetId;

    final read = session.ask('getResource', {
      'resourceId': geometryId.toToken(),
    });
    expect(read.body['vertices'], payloadId.toToken());

    final bytes = session.ask('readPayload', {
      'payloadId': payloadId.toToken(),
    });
    expect(bytes.blobs.single.bytes, data);
  });

  test('a mesh geometry refuses a payload that is not there', () {
    final session = EditorSession.empty();
    expect(
      () => session.run('createMeshGeometry', {'vertices': 'HQRMRD0000099'}),
      throwsA(isA<CommandException>()),
    );
  });

  test('bounds come from the host, and only when asked for', () {
    final session = EditorSession.empty()
      ..queryHost = _FixedBounds(
        Aabb3.minMax(Vector3(-1, 0, -1), Vector3(1, 2, 1)),
      );
    final id = _node(session, 'Box');

    final plain =
        (session.ask('nodeSubtree', {'nodeId': id.toToken()}).body['nodes']
                    as List)
                .single
            as Map;
    expect(plain.containsKey('worldBounds'), isFalse, reason: 'opt-in');

    final withBounds =
        (session.ask('nodeSubtree', {
                      'nodeId': id.toToken(),
                      'bounds': true,
                    }).body['nodes']
                    as List)
                .single
            as Map;
    expect(((withBounds['worldBounds'] as Map)['max'] as Map)['y'], 2);
  });

  test('a headless session says it cannot answer bounds', () {
    final session = EditorSession.empty();
    final id = _node(session, 'Box');
    final body = session.ask('nodeSubtree', {
      'nodeId': id.toToken(),
      'bounds': true,
    }).body;
    expect(body['boundsAvailable'], isFalse);
    expect(
      ((body['nodes'] as List).single as Map).containsKey('worldBounds'),
      isFalse,
    );
  });

  test('a node that draws nothing has no bounds, not zero bounds', () {
    final session = EditorSession.empty()..queryHost = _FixedBounds(null);
    final id = _node(session, 'Empty');
    final body = session.ask('nodeSubtree', {
      'nodeId': id.toToken(),
      'bounds': true,
    }).body;
    expect(body.containsKey('boundsAvailable'), isFalse);
    expect(
      ((body['nodes'] as List).single as Map).containsKey('worldBounds'),
      isFalse,
    );
  });

  test('carried properties report their declared kinds', () {
    final session = EditorSession.empty()
      ..componentSchemaLookup = (type) => type == 'spin'
          ? ComponentSchema(
              'spin',
              properties: [
                ComponentPropertyDef('speed', ComponentPropertyKind.number),
                ComponentPropertyDef('axis', ComponentPropertyKind.vec3),
              ],
            )
          : null;
    final id = _node(session, 'Wheel');
    session.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': 'spin',
      'properties': {'speed': 2.0},
    });

    final body = session.ask('nodeSubtree', {
      'nodeId': id.toToken(),
      'components': true,
    }).body;
    final node = (body['nodes'] as List).single as Map;
    final component = (node['components'] as List).single as Map;
    expect(component['kinds'], {'speed': 'number'}, reason: 'carried only');
  });

  test('an unknown query is an error, not an empty answer', () {
    final session = EditorSession.empty();
    expect(() => session.ask('noSuchQuery'), throwsArgumentError);
    expect(session.request('noSuchQuery'), throwsArgumentError);
  });

  test('request answers a document query as ask does', () async {
    final session = EditorSession.empty();
    _node(session, 'Root');
    final asked = session.ask('nodeSubtree').body;
    final requested = (await session.request('nodeSubtree')).body;
    expect(jsonEncode(requested), jsonEncode(asked));
  });

  test('a frame query awaits the renderer, and ask refuses it', () async {
    final session = EditorSession.empty();
    session.queries.register(_viewportImage(() async => [1, 2, 3]));

    expect(() => session.ask('viewportImage'), throwsA(isA<QueryException>()));
    final result = await session.request('viewportImage');
    expect(result.body['image'], 'viewport');
    expect(result.blobs.single.bytes, [1, 2, 3]);
    expect(result.blobs.single.mimeType, 'image/png');
  });

  test('a renderer failure surfaces as a query error', () async {
    final session = EditorSession.empty();
    session.queries.register(
      _viewportImage(() async => throw StateError('no frame')),
    );
    await expectLater(
      session.request('viewportImage'),
      throwsA(
        isA<QueryException>().having(
          (e) => e.message,
          'message',
          contains('no frame'),
        ),
      ),
    );
  });

  test('the schema says which reads need the renderer', () {
    final session = EditorSession.empty();
    session.queries.register(_viewportImage(() async => const []));
    expect(
      querySchema(session.queries.lookup('nodeSubtree')!)['kind'],
      'document',
    );
    expect(
      querySchema(session.queries.lookup('viewportImage')!)['kind'],
      'frame',
    );
  });
}

QueryEntry _viewportImage(Future<List<int>> Function() capture) =>
    QueryEntry.frame(
      name: 'viewportImage',
      doc: 'The viewport.',
      fetch: (ctx, params) async => QueryResult(
        {'image': 'viewport'},
        blobs: [
          QueryBlob(
            id: 'viewport',
            bytes: Uint8List.fromList(await capture()),
            mimeType: 'image/png',
          ),
        ],
      ),
    );

class _FixedBounds implements QueryHost {
  _FixedBounds(this.bounds);

  final Aabb3? bounds;

  @override
  Aabb3? worldBounds(LocalId id) => bounds;
}
