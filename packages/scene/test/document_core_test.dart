import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector3;
import 'package:test/test.dart';

void main() {
  test('ids are stable, distinct, and round trip through their tokens', () {
    final allocator = IdAllocator();
    final a = allocator.mint();
    final b = allocator.mint();
    expect(a, isNot(b));
    expect(LocalId.parse(a.toToken()), a);
    final document = DocumentId.generate();
    expect(DocumentId.parse(document.toToken()), document);
  });

  test('an empty document round trips through .fscene text', () {
    final document = SceneDocument();
    final text = writeFscene(document);
    final reread = readFscene(text);
    expect(writeFscene(reread), text);
  });

  test('editor state round trips and prunes stale selection ids', () {
    final document = SceneDocument();
    final kept = document.newId();
    document.addNode(NodeSpec(id: kept, name: 'Kept'), root: true);
    final stale = document.newId();
    document.editor = EditorStateSpec(
      camera: EditorCameraSpec(
        azimuth: 1.25,
        elevation: -0.5,
        radius: 12,
        target: Vector3(1, 2, 3),
        orthographic: true,
      ),
      selection: [stale, kept],
    );
    final reread = readFscene(writeFscene(document));
    final editor = reread.editor!;
    expect(editor.camera!.azimuth, closeTo(1.25, 1e-9));
    expect(editor.camera!.elevation, closeTo(-0.5, 1e-9));
    expect(editor.camera!.radius, closeTo(12, 1e-9));
    expect(editor.camera!.target, Vector3(1, 2, 3));
    expect(editor.camera!.orthographic, isTrue);
    // The id that no longer names a node is dropped at read.
    expect(editor.selection, [kept]);
  });

  test('a document without editor state stays without it', () {
    final document = SceneDocument();
    final reread = readFscene(writeFscene(document));
    expect(reread.editor, isNull);
    expect(writeFscene(reread), writeFscene(document));
  });
}
