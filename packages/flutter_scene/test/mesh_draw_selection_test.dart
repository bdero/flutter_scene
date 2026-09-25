import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/mesh_draw_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('limitInstanceIndices', () {
    test('no limit keeps the indices', () {
      expect(limitInstanceIndices(null, 10, null), isNull);
      final culled = [1, 4, 7];
      expect(limitInstanceIndices(culled, 10, null), same(culled));
      expect(limitInstanceIndices(culled, 10, 10), same(culled));
    });

    test('a limit on all instances is a prefix', () {
      expect(limitInstanceIndices(null, 10, 3), [0, 1, 2]);
      expect(limitInstanceIndices(null, 10, 0), isEmpty);
    });

    test('a limit on culled indices keeps those below it', () {
      expect(limitInstanceIndices([1, 4, 7, 9], 10, 7), [1, 4]);
      expect(limitInstanceIndices([1, 4], 10, 5), [1, 4]);
      expect(limitInstanceIndices([5, 6], 10, 2), isEmpty);
    });
  });

  test('MeshDrawSelection.all draws everything', () {
    expect(MeshDrawSelection.all.isAll, isTrue);
    expect(const MeshDrawSelection(instanceCount: 3).isAll, isFalse);
    expect(const MeshDrawSelection(firstIndex: 6).isAll, isFalse);
  });
}
