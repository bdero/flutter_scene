// Selection and camera are commands, so a script drives them exactly as the
// UI does, and neither touches the undo history.
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

    test('never reaches the undo history', () {
      final s = EditorSession.empty();
      final a = _node(s, 'a');
      s.history.clear();
      s.run('selectNodes', {
        'nodeIds': [a.toToken()],
      });
      s.run('clearSelection');
      expect(s.history.transactions, isEmpty);
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
      expect(s.history.transactions, isEmpty);
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

  test('view commands declare their kind, document commands keep theirs', () {
    final registry = EditorSession.empty().registry;
    expect(registry.lookup('selectNodes')!.kind, CommandKind.view);
    expect(registry.lookup('frameNodes')!.kind, CommandKind.view);
    expect(registry.lookup('createNode')!.kind, CommandKind.document);
  });
}
