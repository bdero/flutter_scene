// Selection and camera are commands, so a script drives them exactly as the
// UI does. Selection is a history step; the camera is not.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

class _FakeView implements ViewHost {
  _FakeView({this.framable = true});

  final bool framable;
  final List<List<LocalId>> framed = [];

  @override
  EditorCameraSpec camera = EditorCameraSpec(
    azimuth: 1,
    elevation: 2,
    radius: 3,
    target: Vector3(4, 5, 6),
  );

  @override
  void setCamera(EditorCameraSpec pose) => camera = pose;

  @override
  bool frame(Iterable<LocalId> ids) {
    framed.add(ids.toList());
    return framable;
  }
}

LocalId _node(EditorSession s, String name) => LocalId.parse(
  s.run('createNode', {'name': name}).records.first.targetId.toToken(),
);

void main() {
  group('selection', () {
    test('selects, adds, toggles, removes, and clears', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      final b = _node(s, 'b');
      final c = _node(s, 'c');

      s.run('selectNodes', {
        'nodeIds': [a.toToken(), b.toToken()],
      });
      expect(s.selection.ids, {a, b});
      expect(s.selection.primary, b);

      s.run('selectNodes', {
        'nodeIds': [c.toToken()],
        'mode': 'add',
      });
      expect(s.selection.ids, {a, b, c});

      s.run('selectNodes', {
        'nodeIds': [a.toToken()],
        'mode': 'toggle',
      });
      expect(s.selection.ids, {b, c});

      s.run('selectNodes', {
        'nodeIds': [b.toToken()],
        'mode': 'remove',
      });
      expect(s.selection.ids, {c});

      s.run('clearSelection');
      expect(s.selection.isEmpty, isTrue);
    });

    test('rejects an unknown node and an unknown mode', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      expect(
        () => s.run('selectNodes', {
          'nodeIds': ['n:ZZZZZZZZZZZZZ'],
        }),
        throwsA(isA<CommandException>()),
      );
      expect(
        () => s.run('selectNodes', {
          'nodeIds': [a.toToken()],
          'mode': 'nope',
        }),
        throwsA(
          isA<CommandException>().having(
            (e) => e.message,
            'message',
            contains('Unknown selection mode'),
          ),
        ),
      );
    });

    test('is a history step of its own, and undo walks back through it', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      final b = _node(s, 'b');
      s.history.clear();

      s.run('selectNodes', {
        'nodeIds': [a.toToken()],
      });
      s.run('selectNodes', {
        'nodeIds': [b.toToken()],
      });
      expect(s.history.transactions, hasLength(2));
      expect(s.history.undoLabel, 'Select');

      s.undo();
      expect(s.selection.ids, {a});
      s.undo();
      expect(s.selection.isEmpty, isTrue);
      s.redo();
      expect(s.selection.ids, {a});
    });

    test('selecting the same nodes again is not a step', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      s.history.clear();
      s.run('selectNodes', {
        'nodeIds': [a.toToken()],
      });
      s.run('selectNodes', {
        'nodeIds': [a.toToken()],
      });
      expect(s.history.transactions, hasLength(1));
    });

    test('reselecting after an undo keeps redo', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      s.run('setNodeName', {'nodeId': a.toToken(), 'name': 'renamed'});
      s.undo();

      s.run('selectNodes', {
        'nodeIds': [...s.selection.ids.map((id) => id.toToken())],
      });
      expect(s.history.canRedo, isTrue);
      expect(s.redo(), isTrue);
      expect(s.document.node(a)!.name, 'renamed');
    });
  });

  group('viewport', () {
    test('view commands are inapplicable without a host, and say so', () {
      final s = EditorSession.empty();
      expect(s.canRun('setViewportCamera', {'radius': 9.0}), isFalse);
      expect(
        () => s.run('setViewportCamera', {'radius': 9.0}),
        throwsA(
          isA<CommandException>().having(
            (e) => e.message,
            'message',
            'setViewportCamera cannot run right now',
          ),
        ),
      );
    });

    test('moves the camera, keeping omitted fields', () {
      final s = EditorSession.empty();
      final view = _FakeView();
      s.viewHost = view;
      expect(s.canRun('setViewportCamera', {'radius': 9.0}), isTrue);

      s.run('setViewportCamera', {
        'radius': 9.0,
        'target': {'x': 1.0, 'y': 2.0, 'z': 3.0},
      });
      expect(view.camera.radius, 9);
      expect(view.camera.target, Vector3(1, 2, 3));
      expect(view.camera.azimuth, 1, reason: 'omitted fields hold');
      expect(view.camera.elevation, 2);
      expect(
        s.history.transactions,
        isEmpty,
        reason: 'the camera saves with the document but is not undoable',
      );
    });

    test('frames nodes, and reports when there is nothing to frame', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      final view = _FakeView();
      s.viewHost = view;
      s.run('frameNodes', {
        'nodeIds': [a.toToken()],
      });
      expect(view.framed.single, [a]);

      s.viewHost = _FakeView(framable: false);
      expect(
        () => s.run('frameNodes', {
          'nodeIds': [a.toToken()],
        }),
        throwsA(isA<CommandException>()),
      );
    });
  });

  test('commands declare what they touch', () {
    final registry = EditorSession.empty().registry;
    expect(registry.lookup('selectNodes')!.kind, CommandKind.selection);
    expect(registry.lookup('clearSelection')!.kind, CommandKind.selection);
    expect(registry.lookup('frameNodes')!.kind, CommandKind.view);
    expect(registry.lookup('setViewportCamera')!.kind, CommandKind.view);
    expect(registry.lookup('createNode')!.kind, CommandKind.document);
  });
}
