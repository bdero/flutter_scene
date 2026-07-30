// Builds a small scene document, attaches a component, and round-trips it
// through the `.fscene` text and `.fsceneb` binary formats.
// ignore_for_file: avoid_print
import 'package:scene/scene.dart';

void main() {
  final document = SceneDocument();

  // Add a root node carrying one component with a property.
  final id = document.allocator.mint();
  document.addNode(
    NodeSpec(
      id: id,
      name: 'root',
      components: [
        ComponentSpec('audioSource', properties: {'volume': DoubleValue(0.8)}),
      ],
    ),
    root: true,
  );

  // Serialize to both formats and read the text form back.
  final text = writeFscene(document);
  final bytes = writeFsceneb(document);
  final reread = readFscene(text);

  print('nodes: ${reread.nodes.length}');
  print('.fscene text: ${text.length} chars');
  print('.fsceneb binary: ${bytes.length} bytes');
}
