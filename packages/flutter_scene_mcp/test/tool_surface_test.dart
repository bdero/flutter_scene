import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:test/test.dart';

EditorToolSurface _surface() => EditorToolSurface(
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
    test('search_commands finds a command with its argument schema', () {
      final result = _surface().dispatch('search_commands', {
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

    test('run_command runs a command and reports it as undoable', () {
      final surface = _surface();
      final created = surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Root'},
      });
      expect(created['ok'], isTrue);
      expect(created['canUndo'], isTrue);

      final scene = surface.dispatch('describe_scene', {});
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

  group('perception and references', () {
    test('get_node resolves by slash path and returns detail', () {
      final surface = _surface();
      surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Parent'},
      });
      final parentPath =
          ((surface.dispatch('describe_scene', {})['roots'] as List).single
                  as Map)['path']
              as String;
      surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Child', 'parentId': _firstRootId(surface)},
      });

      final detail = surface.dispatch('get_node', {'ref': parentPath});
      expect(detail['name'], 'Parent');
      expect(detail['children'], hasLength(1));
    });

    test('select_node by path updates the selection', () {
      final surface = _surface();
      surface.dispatch('run_command', {
        'command': 'createNode',
        'params': {'name': 'Target'},
      });
      final result = surface.dispatch('select_node', {'ref': 'Target'});
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

String _firstRootId(EditorToolSurface surface) {
  final roots = surface.dispatch('describe_scene', {})['roots'] as List;
  return (roots.first as Map)['id'] as String;
}
