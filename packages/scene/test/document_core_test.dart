import 'package:scene/scene.dart';
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
}
