import 'dart:typed_data';

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

  group('animation preview control', () {
    final calls = <Map<String, Object?>>[];
    Map<String, Object?> control({
      LocalId? animationId,
      bool? playing,
      bool? loop,
      double? speed,
      double? seek,
      bool? stop,
    }) {
      calls.add({
        if (animationId != null) 'animation': animationId.toToken(),
        if (playing != null) 'playing': playing,
        if (loop != null) 'loop': loop,
        if (speed != null) 'speed': speed,
        if (seek != null) 'seek': seek,
        if (stop != null) 'stop': stop,
      });
      return {
        'animation': animationId?.toToken(),
        'playing': playing ?? false,
        'time': seek ?? 0.0,
      };
    }

    EditorToolSurface surfaceWithPreview() {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      return EditorToolSurface(() => session, animationPreview: control);
    }

    test('is offered only when a provider is present', () {
      expect(
        _surface().bootstrapTools().map((t) => t.name),
        isNot(contains('control_animation_preview')),
      );
      expect(
        surfaceWithPreview().bootstrapTools().map((t) => t.name),
        contains('control_animation_preview'),
      );
    });

    test('without a provider, dispatch throws ToolError', () {
      expect(
        () => _surface().dispatch('control_animation_preview', {}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('preview'),
          ),
        ),
      );
    });

    test('resolves an animation ref onto the playhead', () async {
      final surface = surfaceWithPreview();
      calls.clear();
      await surface.dispatch('run_command', {
        'command': 'createAnimation',
        'params': {'name': 'Spin'},
      });
      final id =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;

      final state = await surface.dispatch('control_animation_preview', {
        'ref': 'Spin',
        'seek': 0.5,
        'playing': true,
      });
      expect(state['animation'], id);
      expect(calls.single['animation'], id);
      expect(calls.single['seek'], 0.5);
      expect(calls.single['playing'], true);
    });

    test('omitted fields pass null through', () async {
      calls.clear();
      await surfaceWithPreview().dispatch('control_animation_preview', {
        'loop': false,
      });
      expect(calls.single, {'loop': false});
    });

    test('a bad ref surfaces as ToolError', () {
      expect(
        () => surfaceWithPreview().dispatch('control_animation_preview', {
          'ref': 'Nope',
        }),
        throwsA(isA<ToolError>()),
      );
    });

    test('an empty ref is rejected, not silently ignored', () {
      expect(
        () => surfaceWithPreview().dispatch('control_animation_preview', {
          'ref': '',
        }),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('non-empty'),
          ),
        ),
      );
    });

    test('stop passes through to the host', () async {
      final surface = surfaceWithPreview();
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final id =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      calls.clear();
      await surface.dispatch('control_animation_preview', {
        'ref': id,
        'stop': true,
      });
      expect(calls.single['stop'], true);
    });
  });

  group('keyframe truncation', () {
    /// A surface with one node and a 250-key animation channel.
    Future<(EditorToolSurface, String, String)> largeChannel() async {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      await surface.dispatch('run_command', {'command': 'createNode'});
      final nodeId =
          (((await surface.dispatch('describe_scene', {}))['roots'] as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final animationId =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      // 250 keys at 0.01 s spacing, authored through the real batch command.
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframes',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'keys': [
            for (var i = 0; i < 250; i++)
              {
                'time': i * 0.01,
                'translation': {'x': i * 1.0, 'y': 0.0, 'z': 0.0},
              },
          ],
        },
      });
      return (surface, animationId, nodeId);
    }

    test('get_animation caps keyframes per channel by default', () async {
      final (surface, animationId, _) = await largeChannel();
      final detail = await surface.dispatch('get_animation', {
        'ref': animationId,
      });
      final channel = (detail['channels'] as List).single as Map;
      expect(channel['totalKeys'], 250);
      expect(channel['keysTruncated'], isTrue);
      expect((channel['keyframes'] as List), hasLength(200));
    });

    test('maxKeys raises or lowers the cap', () async {
      final (surface, animationId, _) = await largeChannel();
      final full = await surface.dispatch('get_animation', {
        'ref': animationId,
        'maxKeys': 250,
      });
      final channel = (full['channels'] as List).single as Map;
      expect(channel['keysTruncated'], isFalse);
      expect((channel['keyframes'] as List), hasLength(250));

      final tiny = await surface.dispatch('get_animation', {
        'ref': animationId,
        'maxKeys': 5,
      });
      expect(
        ((tiny['channels'] as List).single as Map)['keyframes'],
        hasLength(5),
      );
    });

    test('a maxKeys below 1 is rejected', () async {
      final (surface, animationId, _) = await largeChannel();
      expect(
        () => surface.dispatch('get_animation', {
          'ref': animationId,
          'maxKeys': 0,
        }),
        throwsA(isA<ToolError>()),
      );
    });

    test('get_keyframes pages a channel by time range', () async {
      final (surface, animationId, nodeId) = await largeChannel();
      final page = await surface.dispatch('get_keyframes', {
        'ref': animationId,
        'node': nodeId,
        'property': 'translation',
        'fromTime': 0.4,
        'toTime': 0.6,
      });
      expect(page['totalKeys'], 21); // 0.40..0.60 inclusive at 0.01 spacing.
      expect(page['keysTruncated'], isFalse);
      final times = [
        for (final k in (page['keyframes'] as List)) (k as Map)['time'],
      ];
      expect(times.first, closeTo(0.4, 1e-6));
      expect(times.last, closeTo(0.6, 1e-6));

      // The cap still applies within the range.
      final capped = await surface.dispatch('get_keyframes', {
        'ref': animationId,
        'node': nodeId,
        'property': 'translation',
        'fromTime': 0.0,
        'toTime': 2.49,
        'maxKeys': 10,
      });
      expect(capped['totalKeys'], 250);
      expect(capped['keysTruncated'], isTrue);
      expect((capped['keyframes'] as List), hasLength(10));
    });

    test('get_keyframes validates its channel arguments', () async {
      final (surface, animationId, nodeId) = await largeChannel();
      // Unknown property.
      expect(
        () => surface.dispatch('get_keyframes', {
          'ref': animationId,
          'node': nodeId,
          'property': 'colour',
        }),
        throwsA(isA<ToolError>()),
      );
      // A node with no channel of that property.
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Other'},
      });
      expect(
        () => surface.dispatch('get_keyframes', {
          'ref': animationId,
          'node': 'Other',
          'property': 'translation',
        }),
        throwsA(isA<ToolError>()),
      );
      // Missing node argument.
      expect(
        () => surface.dispatch('get_keyframes', {
          'ref': animationId,
          'property': 'translation',
        }),
        throwsA(isA<ToolError>()),
      );
    });

    test('rotation keyframes carry an eulerDeg readback', () async {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      await surface.dispatch('run_command', {'command': 'createNode'});
      final nodeId =
          (((await surface.dispatch('describe_scene', {}))['roots'] as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final animationId =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      // Author in degrees; the readback must round-trip.
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframe',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'rotation',
          'time': 0.0,
          'rotationEuler': {'yaw': 90.0, 'pitch': 0.0, 'roll': 0.0},
        },
      });
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframe',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'time': 0.0,
          'translation': {'x': 1.0, 'y': 0.0, 'z': 0.0},
        },
      });

      final detail = await surface.dispatch('get_animation', {
        'ref': animationId,
      });
      for (final channel in (detail['channels'] as List)) {
        final c = channel as Map;
        if (c['property'] != 'rotation') continue;
        final keyframe = (c['keyframes'] as List).single as Map;
        final euler = keyframe['eulerDeg'] as Map;
        expect(euler['yaw'], closeTo(90.0, 1e-4));
        expect(euler['pitch'], closeTo(0.0, 1e-4));
        expect(euler['roll'], closeTo(0.0, 1e-4));
      }
      // Translation channels carry no eulerDeg.
      final translation =
          (detail['channels'] as List)
                  .where((c) => (c as Map)['property'] == 'translation')
                  .single
              as Map;
      expect(
        ((translation['keyframes'] as List).single as Map)['eulerDeg'],
        isNull,
      );
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
  group('animation perception', () {
    test('bootstrap surface offers the animation tools', () {
      final names = _surface().bootstrapTools().map((t) => t.name).toSet();
      expect(names, containsAll(['list_animations', 'get_animation']));
    });

    test('describe_scene carries an animation summary', () async {
      final surface = _surface();
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final scene = await surface.dispatch('describe_scene', {});
      final animations = scene['animations'] as List;
      expect(animations, hasLength(1));
      final summary = animations.single as Map;
      expect(summary['name'], 'Animation');
      expect(summary['id'], isNotEmpty);
      expect(summary['duration'], 0.0);
      expect((summary['channels'] as List), isEmpty);
    });

    test('keyframes authored via run_command read back decoded', () async {
      final surface = _surface();
      // A target node plus a two-keyframe translation channel.
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Cube'},
      });
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final animationId =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      final nodeId = await _firstRootId(surface);
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframe',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'time': 0.0,
          'translation': {'x': 0.0, 'y': 0.0, 'z': 0.0},
        },
      });
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframe',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'time': 1.5,
          'translation': {'x': 2.0, 'y': 4.0, 'z': -1.0},
        },
      });
      // A rotation keyframe exercises the quaternion stride.
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframe',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'rotation',
          'time': 0.5,
          'rotation': {
            'x': 0.0,
            'y': 0.7071067811865476,
            'z': 0.0,
            'w': 0.7071067811865476,
          },
        },
      });

      final detail = await surface.dispatch('get_animation', {
        'ref': animationId,
      });
      expect(detail['duration'], 1.5);
      final channels = detail['channels'] as List;
      expect(channels, hasLength(2));
      final translation =
          channels.firstWhere((c) => (c as Map)['property'] == 'translation')
              as Map;
      expect(((translation['target'] as Map)['path']), 'Cube');
      final keys = translation['keyframes'] as List;
      expect(keys, hasLength(2));
      // Keyframes come back time-sorted out of the timeline payload.
      expect((keys.first as Map)['time'], 0.0);
      expect((keys.last as Map)['time'], 1.5);
      expect((keys.last as Map)['value'], {'x': 2.0, 'y': 4.0, 'z': -1.0});

      final rotation =
          channels.firstWhere((c) => (c as Map)['property'] == 'rotation')
              as Map;
      expect(
        ((rotation['keyframes'].single as Map)['value'] as Map)['w'],
        closeTo(0.7071067811865476, 1e-6),
      );

      // The same detail resolves by exact name.
      final byName = await surface.dispatch('get_animation', {
        'ref': 'Animation',
      });
      expect(byName['id'], animationId);

      // list_animations summarizes without decoding values.
      final summary =
          ((await surface.dispatch('list_animations', {}))['animations']
                      as List)
                  .single
              as Map;
      expect(summary['duration'], 1.5);
      expect((summary['channels'] as List), hasLength(2));
    });

    test('get_animation on a missing ref throws ToolError', () {
      expect(
        () => _surface().dispatch('get_animation', {'ref': 'Nope'}),
        throwsA(isA<ToolError>()),
      );
      // The missing-ref complaint is about animations, not nodes.
      expect(
        () => _surface().dispatch('get_animation', {}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('animation'),
          ),
        ),
      );
    });

    test('an ambiguous animation name is rejected', () async {
      final surface = _surface();
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      expect(
        () => surface.dispatch('get_animation', {'ref': 'Animation'}),
        throwsA(
          isA<ToolError>().having(
            (e) => e.message,
            'message',
            contains('ambiguous'),
          ),
        ),
      );
    });

    test('weights channels decode with the flattened glTF stride', () async {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      final doc = session.document;
      await surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Mesh'},
      });
      // No command authors weight channels (they come from imported models),
      // so build one directly: 2 keyframes x 2 morph targets.
      final timelineId = doc.newId();
      final valuesId = doc.newId();
      Uint8List floatBytes(List<double> xs) =>
          Float32List.fromList(xs).buffer.asUint8List();
      doc.addPayload(
        PayloadSpec(
          timelineId,
          encoding: PayloadEncoding.floats,
          bytes: floatBytes([0, 1]),
        ),
      );
      doc.addPayload(
        PayloadSpec(
          valuesId,
          encoding: PayloadEncoding.floats,
          bytes: floatBytes([0.25, 0.5, 0.75, 1.0]),
        ),
      );
      final nodeId = LocalId.parse(await _firstRootId(surface));
      doc.addAnimation(
        AnimationSpec(
          doc.newId(),
          name: 'Blend',
          channels: [
            AnimationChannelSpec(
              target: nodeId,
              property: AnimationProperty.weights,
              timeline: timelineId,
              keyframes: valuesId,
            ),
          ],
        ),
      );

      final detail = await surface.dispatch('get_animation', {'ref': 'Blend'});
      final channel = (detail['channels'] as List).single as Map;
      expect(channel['property'], 'weights');
      final keys = channel['keyframes'] as List;
      expect(keys, hasLength(2));
      expect((keys.first as Map)['value'], [0.25, 0.5]);
      expect((keys.last as Map)['value'], [0.75, 1.0]);
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

    test(
      'session tools route through the host hooks and gate on them',
      () async {
        final log = <String>[];
        final surface = EditorToolSurface(
          () => null,
          runProject: () async {
            log.add('run');
            return true;
          },
          stopProject: () async => log.add('stop'),
          hotRestart: () async {
            log.add('restart');
            return true;
          },
          hotReload: () async {
            log.add('reload');
            return true;
          },
          reloadScene: () async {
            log.add('reloadScene');
            return true;
          },
          appState: () => {'state': 'running', 'appId': 'app-1'},
          listComponentTypes: () => [
            {'type': 'spin', 'doc': 'Spins.', 'provenance': 'live'},
          ],
          describeComponentType: (type) => type == 'spin'
              ? {
                  'type': 'spin',
                  'properties': [
                    {'name': 'speed', 'kind': 'number'},
                  ],
                }
              : null,
        );
        final names = surface.bootstrapTools().map((t) => t.name);
        expect(
          names,
          containsAll([
            'run_project',
            'stop_project',
            'hot_restart',
            'hot_reload',
            'reload_scene',
            'get_app_state',
          ]),
        );
        expect(await surface.dispatch('run_project', {}), {
          'ok': true,
          'started': true,
        });
        expect(await surface.dispatch('hot_restart', {}), {'ok': true});
        expect(await surface.dispatch('hot_reload', {}), {'ok': true});
        expect(await surface.dispatch('reload_scene', {}), {'ok': true});
        expect(
          (await surface.dispatch('get_app_state', {}))['state'],
          'running',
        );
        final types = await surface.dispatch('list_component_types', {});
        expect((types['types'] as List).single, {
          'type': 'spin',
          'doc': 'Spins.',
          'provenance': 'live',
        });
        final described = await surface.dispatch('describe_component_type', {
          'type': 'spin',
        });
        expect(described['type'], 'spin');
        expect(
          () => surface.dispatch('describe_component_type', {'type': 'nope'}),
          throwsA(isA<ToolError>()),
        );
        await surface.dispatch('stop_project', {});
        expect(log, ['run', 'restart', 'reload', 'reloadScene', 'stop']);

        // A headless surface offers none of them.
        final headless = EditorToolSurface(() => null);
        expect(
          headless.bootstrapTools().map((t) => t.name),
          isNot(contains('hot_restart')),
        );
        expect(
          () => headless.dispatch('hot_restart', {}),
          throwsA(isA<ToolError>()),
        );
      },
    );

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

  group('render graph tools', () {
    test('hidden without providers, offered with them', () async {
      final bare = _surface().bootstrapTools().map((t) => t.name).toSet();
      expect(bare, isNot(contains('list_render_passes')));
      expect(bare, isNot(contains('set_viewport_debug_mode')));

      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(
        () => session,
        renderGraphCapture: ({required thumbnails, maxDimension}) async => {
          'thumbnails': thumbnails,
          'maxDimension': maxDimension,
        },
        renderGraphImage: (key, options) async =>
            ScreenshotResult(pngBytes: Uint8List(0), width: 1, height: 1),
        renderGraphPixel: (key, x, y) async => {'key': key, 'x': x, 'y': y},
        renderGraphScan: () async => {'offenders': const []},
        listDebugModes: () => [
          {'id': 'final', 'label': 'Final output', 'active': true},
        ],
        setDebugMode: (id) async {},
      );
      final names = surface.bootstrapTools().map((t) => t.name).toSet();
      expect(
        names,
        containsAll({
          'list_render_passes',
          'capture_render_graph',
          'get_pass_output',
          'read_pass_pixel',
          'scan_for_nans',
          'list_viewport_debug_modes',
          'set_viewport_debug_mode',
        }),
      );
      final imageTools = {
        for (final def in surface.bootstrapTools())
          if (def.returnsImage) def.name,
      };
      expect(imageTools, contains('get_pass_output'));

      final metadata = await surface.dispatch('list_render_passes', {});
      expect(metadata['thumbnails'], isFalse);
      final capture = await surface.dispatch('capture_render_graph', {
        'maxDimension': 128,
      });
      expect(capture['thumbnails'], isTrue);
      expect(capture['maxDimension'], 128);
      final pixel = await surface.dispatch('read_pass_pixel', {
        'key': 'scene_color',
        'x': 3,
        'y': 4,
      });
      expect(pixel['x'], 3);
      final modes = await surface.dispatch('list_viewport_debug_modes', {});
      expect((modes['modes'] as List), hasLength(1));
      final set = await surface.dispatch('set_viewport_debug_mode', {
        'mode': 'final',
      });
      expect(set['ok'], isTrue);
      final image = await surface.dispatchImage('get_pass_output', {
        'key': 'scene_color',
      });
      expect(image['mimeType'], 'image/png');
    });

    test('image dispatch rejects non-image tools and vice versa', () {
      final surface = _surface();
      expect(
        () => surface.dispatch('screenshot_viewport', {}),
        throwsA(isA<ToolError>()),
      );
      expect(
        () => surface.dispatchImage('describe_scene', {}),
        throwsA(isA<ToolError>()),
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

  group('channel interpolation', () {
    test('channels report their interpolation mode', () async {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      await surface.dispatch('run_command', {'command': 'createNode'});
      final nodeId =
          (((await surface.dispatch('describe_scene', {}))['roots'] as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final animationId =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframes',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'keys': [
            {'time': 0.0},
            {'time': 1.0},
          ],
        },
      });
      // Default is linear.
      var detail = await surface.dispatch('get_animation', {
        'ref': animationId,
      });
      expect(
        ((detail['channels'] as List).single as Map)['interpolation'],
        'linear',
      );

      await surface.dispatch('run_command', {
        'command': 'setChannelInterpolation',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'interpolation': 'step',
        },
      });
      detail = await surface.dispatch('get_animation', {'ref': animationId});
      expect(
        ((detail['channels'] as List).single as Map)['interpolation'],
        'step',
      );
    });

    test('cubic channels decode values from their middle slot', () async {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      await surface.dispatch('run_command', {'command': 'createNode'});
      final nodeId =
          (((await surface.dispatch('describe_scene', {}))['roots'] as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {'command': 'createAnimation'});
      final animationId =
          (((await surface.dispatch('list_animations', {}))['animations']
                          as List)
                      .single
                  as Map)['id']
              as String;
      await surface.dispatch('run_command', {
        'command': 'setAnimationKeyframes',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'keys': [
            {'time': 0.0},
            {'time': 1.0},
          ],
        },
      });
      await surface.dispatch('run_command', {
        'command': 'setChannelInterpolation',
        'params': {
          'animationId': animationId,
          'nodeId': nodeId,
          'property': 'translation',
          'interpolation': 'cubic',
        },
      });
      final detail = await surface.dispatch('get_animation', {
        'ref': animationId,
      });
      final channel = (detail['channels'] as List).single as Map;
      expect(channel['interpolation'], 'cubic');
      // The keyed values live in each row's middle slot; tangent slots are
      // not reported as values.
      for (final keyframe in (channel['keyframes'] as List)) {
        expect(
          ((keyframe as Map)['value'] as Map)['x'],
          anyOf(closeTo(0.0, 1e-6), closeTo(10.0, 1e-6)),
        );
      }
    });

    test('an unknown interpolation mode is rejected', () {
      final session = EditorSession(
        SceneDocument(allocator: IdAllocator(session: 1)),
      );
      final surface = EditorToolSurface(() => session);
      expect(
        () => surface.dispatch('run_command', {
          'command': 'setChannelInterpolation',
          'params': {
            'animationId': '0000008000000',
            'nodeId': '0000008000001',
            'property': 'translation',
            'interpolation': 'bouncy',
          },
        }),
        throwsA(isA<ToolError>()),
      );
    });
  });
}
