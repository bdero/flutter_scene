import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

EditorToolSurface _surface() => EditorToolSurface.of(
  EditorSession(SceneDocument(allocator: IdAllocator(session: 1))),
);

void main() {
  group('bootstrap surface', () {
    test('offers a small curated set, not the full registry', () {
      final surface = _surface();
      final names = surface.bootstrapTools().map((t) => t.name).toSet();
      expect(names, contains('run_command'));
      expect(names, contains('search_commands'));
      expect(names, contains('describe_scene'));
      // The bootstrap set is far smaller than the full command set.
      expect(surface.bootstrapTools().length, lessThan(builtinCommands.length));
    });
  });

  group('command gateway', () {
    test('search_commands finds a command with its argument schema', () async {
      final result = await _surface().dispatch('search_commands', {
        'query': 'transform',
      });
      final commands = result['commands'] as List;
      final names = [for (final c in commands) (c as Map)['name']];
      expect(names, contains('setNodeTransform'));
      final entry =
          commands.firstWhere((c) => (c as Map)['name'] == 'setNodeTransform')
              as Map;
      expect((entry['inputSchema'] as Map)['properties'], contains('nodeId'));
    });

    test('run_command runs a command and reports it as undoable', () async {
      final surface = _surface();
      final created = await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Root'},
      });
      expect(created['ok'], isTrue);
      expect(created['canUndo'], isTrue);
      // The result names what the command created, so agents can chain.
      final createdIds = created['created'] as List;
      expect(createdIds, hasLength(1));
      expect((createdIds.single as Map)['kind'], 'node');
      expect((createdIds.single as Map)['id'], isNotEmpty);

      final scene = await surface.dispatch('describe_scene', {});
      final roots = scene['roots'] as List;
      expect(roots, hasLength(1));
      expect((roots.single as Map)['name'], 'Root');
    });

    test('run_command surfaces a bad command as a ToolError', () {
      expect(
        () => _surface().dispatch('run_command', {'command': 'nope'}),
        throwsA(isA<ToolError>()),
      );
    });
  });

  cameraTests();
  documentTests();

  group('perception and references', () {
    test('get_node resolves by slash path and returns detail', () async {
      final surface = _surface();
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Parent'},
      });
      final parentPath =
          (((await surface.dispatch('describe_scene', {}))['roots'] as List)
                      .single
                  as Map)['path']
              as String;
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Child', 'parentId': await _firstRootId(surface)},
      });

      final detail = await surface.dispatch('get_node', {'ref': parentPath});
      expect(detail['name'], 'Parent');
      expect(detail['children'], hasLength(1));
    });

    test('select_node by path updates the selection', () async {
      final surface = _surface();
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Target'},
      });
      final result = await surface.dispatch('select_node', {'ref': 'Target'});
      expect(result['primaryPath'], 'Target');
    });

    test('get_node on a missing ref throws ToolError', () {
      expect(
        () => _surface().dispatch('get_node', {'ref': 'Nope/Missing'}),
        throwsA(isA<ToolError>()),
      );
    });
  });
}

Future<String> _firstRootId(EditorToolSurface surface) async {
  final roots = (await surface.dispatch('describe_scene', {}))['roots'] as List;
  return (roots.first as Map)['id'] as String;
}

EditorToolSurface _surfaceWithCamera(List<ViewportCameraPose> writes) {
  var pose = ViewportCameraPose(
    azimuth: 0.4,
    elevation: 0.3,
    radius: 8,
    target: Vector3.zero(),
    orthographic: false,
  );
  final session = EditorSession(
    SceneDocument(allocator: IdAllocator(session: 1)),
  );
  return EditorToolSurface(
    () => session,
    readCamera: () => pose,
    writeCamera: (next) {
      pose = next;
      writes.add(next);
    },
    frameNode: (_) => true,
  );
}

void cameraTests() {
  group('camera tools', () {
    test('absent without a camera hook, offered with one', () {
      final without = _surface().bootstrapTools().map((t) => t.name);
      expect(without, isNot(contains('set_viewport_camera')));
      final with_ = _surfaceWithCamera([]).bootstrapTools().map((t) => t.name);
      expect(
        with_,
        containsAll([
          'get_viewport_camera',
          'set_viewport_camera',
          'frame_node',
        ]),
      );
    });

    test('set_viewport_camera merges partial poses', () async {
      final writes = <ViewportCameraPose>[];
      final surface = _surfaceWithCamera(writes);
      final result = await surface.dispatch('set_viewport_camera', {
        'radius': 3.5,
        'orthographic': true,
      });
      expect(writes.single.radius, 3.5);
      expect(writes.single.orthographic, isTrue);
      expect(writes.single.azimuth, 0.4);
      expect(result['radius'], 3.5);
    });

    test('frame_node resolves the ref and reports the new pose', () async {
      final writes = <ViewportCameraPose>[];
      final surface = _surfaceWithCamera(writes);
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Subject'},
      });
      final result = await surface.dispatch('frame_node', {'ref': 'Subject'});
      expect(result['azimuth'], 0.4);
    });

    test('camera tools error without a viewport', () {
      expect(
        () => _surface().dispatch('get_viewport_camera', {}),
        throwsA(isA<ToolError>()),
      );
    });
  });

  group('resource listing and run_command hints', () {
    test('list_resources reports orphan resources with kinds', () async {
      final surface = _surface();
      await surface.dispatch('run_command', {
        'command': 'createCuboidGeometry',
        'params': {
          'extents': {'x': 1, 'y': 1, 'z': 1},
        },
      });
      final result = await surface.dispatch('list_resources', {});
      final resources = result['resources'] as List;
      expect(resources, hasLength(1));
      expect((resources.single as Map)['kind'], 'geometry');
      expect((resources.single as Map)['id'], isNotEmpty);
    });

    test('run_command redirects undo/redo to the top-level tools', () {
      expect(
        () => _surface().dispatch('run_command', {'command': 'undo'}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('top-level tool'),
          ),
        ),
      );
    });
  });
}

void documentTests() {
  group('document lifecycle', () {
    test('session tools error when no document is open', () {
      final surface = EditorToolSurface(() => null);
      expect(
        () => surface.dispatch('describe_scene', {}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('new_document'),
          ),
        ),
      );
    });

    test('new/open/save route through the host hooks', () async {
      final log = <String>[];
      final surface = EditorToolSurface(
        () => null,
        newDocument: () async => log.add('new'),
        openDocument: (path) async => log.add('open:$path'),
        saveDocument: ({path}) async {
          log.add('save:$path');
          return path ?? '/kept.fscene';
        },
      );
      final names = surface.bootstrapTools().map((t) => t.name);
      expect(
        names,
        containsAll(['new_document', 'open_document', 'save_document']),
      );
      await surface.dispatch('new_document', {});
      await surface.dispatch('open_document', {'path': '/a.fscene'});
      final saved = await surface.dispatch('save_document', {
        'path': '/b.fscene',
      });
      expect(saved['path'], '/b.fscene');
      expect(log, ['new', 'open:/a.fscene', 'save:/b.fscene']);
    });

    test('save with no known path surfaces the failure', () {
      final surface = EditorToolSurface(
        () => null,
        saveDocument: ({path}) async =>
            throw const FormatException('never saved'),
      );
      expect(
        () => surface.dispatch('save_document', {}),
        throwsA(
          isA<ToolError>().having((e) => e.message, 'message', 'never saved'),
        ),
      );
    });
  });

  test('get_node reports world bounds from the host hook', () async {
    final session = EditorSession(
      SceneDocument(allocator: IdAllocator(session: 1)),
    );
    final surface = EditorToolSurface(
      () => session,
      nodeBounds: (_) => Aabb3.minMax(Vector3.zero(), Vector3(2, 4, 6)),
    );
    await surface.dispatch('run_command', {
      'command': 'createNode',
      'params': {'name': 'Box'},
    });
    final detail = await surface.dispatch('get_node', {'ref': 'Box'});
    final bounds = detail['worldBounds'] as Map;
    expect((bounds['max'] as Map)['y'], 4);
  });
}
