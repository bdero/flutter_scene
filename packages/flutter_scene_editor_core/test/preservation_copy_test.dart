// Duplicating or grafting a node must carry data this build does not
// understand, or an extension loses its work to a copy.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';
import 'package:test/test.dart';

void main() {
  test('duplicating a node carries its preserved data', () {
    final session = EditorSession.empty();
    final created = session.run('createNode', {'name': 'Crate'});
    final id = LocalId.parse(created.records.first.targetId.toToken());
    // Stand in for a document written by an engine that knows more than this
    // one: foreign keys on the node and on its component.
    session.document.nodes[id] = NodeSpec(
      id: id,
      name: 'Crate',
      components: [
        ComponentSpec('mesh', unknown: const {'dev.example.sdf': 'component'}),
      ],
      unknown: const {'dev.example.sdf': 'node'},
    );

    session.run('duplicateNodes', {
      'nodeIds': [id.toToken()],
    });
    final copy = session.document.nodes.values.lastWhere((n) => n.id != id);
    expect(copy.unknown['dev.example.sdf'], 'node');
    expect(copy.components.single.unknown['dev.example.sdf'], 'component');
  });
}
