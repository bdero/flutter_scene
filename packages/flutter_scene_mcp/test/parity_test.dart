import 'package:scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart';
import 'package:test/test.dart';

// Invariant 5 as a test: an MCP-driven edit produces the same document and
// the same change records as the equivalent UI-driven edit, and both undo
// back to an identical baseline.

EditorSession _freshSession() =>
    EditorSession(SceneDocument(allocator: IdAllocator(session: 1)));

// Each document gets a random documentId, so normalize it out before
// comparing the two sessions' serialized scenes (we care about node and
// resource content parity, not the per-document identifier).
final RegExp _documentId = RegExp('"documentId": "[^"]*"');
String _normalize(String fscene) =>
    fscene.replaceAll(_documentId, '"documentId": "_"');

void main() {
  test('MCP edits match UI edits step for step and are undoable', () async {
    // The UI path drives the session directly (what EditorController.run
    // does); the MCP path goes through the tool surface's run_command. Both
    // start from an identical document with the same id allocator seed, so a
    // deterministic edit sequence must produce byte-identical output.
    final ui = _freshSession();
    final mcp = _freshSession();
    final surface = EditorToolSurface.of(mcp);

    final baseline = _normalize(ui.toFscene());
    expect(
      _normalize(mcp.toFscene()),
      baseline,
      reason: 'fresh sessions must match',
    );

    // Each step's params are computed from the (identical) current state, so
    // both paths receive the exact same arguments.
    final steps = <(String, Map<String, Object?> Function(SceneQuery))>[
      ('createNode', (_) => {'name': 'Root'}),
      ('createNode', (_) => {'name': 'Child'}),
      (
        'setNodeName',
        (q) => {'nodeId': q.roots.first.id.toToken(), 'name': 'Renamed'},
      ),
      (
        'setNodeVisible',
        (q) => {'nodeId': q.roots.last.id.toToken(), 'visible': false},
      ),
      (
        'reparentNode',
        (q) => {
          'nodeId': q.roots.last.id.toToken(),
          'newParentId': q.roots.first.id.toToken(),
        },
      ),
    ];

    var committedSteps = 0;
    for (final (command, buildParams) in steps) {
      // Compute params from the UI session; the MCP session is identical.
      final params = buildParams(ui.query);

      final uiTx = ui.run(command, params);
      final mcpResult = await surface.dispatch('run_command', {
        'command': command,
        'params': params,
      });

      expect(mcpResult['ok'], isTrue, reason: '$command should run');
      expect(
        mcpResult['recordCount'],
        uiTx.records.length,
        reason: '$command must emit the same change records on both paths',
      );
      expect(
        _normalize(mcp.toFscene()),
        _normalize(ui.toFscene()),
        reason: 'documents must stay identical after $command',
      );
      if (!uiTx.isEmpty) committedSteps++;
    }

    expect(committedSteps, greaterThan(0));
    expect(
      _normalize(mcp.toFscene()),
      isNot(baseline),
      reason: 'the scene changed',
    );

    // Undo every committed step on both paths; they must return to the same
    // baseline they started from.
    for (var i = 0; i < committedSteps; i++) {
      expect(ui.undo(), isTrue);
      expect((await surface.dispatch('undo', const {}))['undone'], isTrue);
      expect(
        _normalize(mcp.toFscene()),
        _normalize(ui.toFscene()),
        reason: 'documents must stay identical through undo',
      );
    }

    expect(_normalize(ui.toFscene()), baseline);
    expect(
      _normalize(mcp.toFscene()),
      baseline,
      reason: 'MCP undo restores the baseline',
    );
  });
}
