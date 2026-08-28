// The sculpting tool's state and stroke bookkeeping. The viewport wiring
// needs a GPU; these are the parts that do not.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/viewport/terrain_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the tool', () {
    test('starts disarmed', () {
      expect(TerrainToolController().active, isFalse);
    });

    test('notifies when it is armed, and not when set to what it is', () {
      final tool = TerrainToolController();
      var notifications = 0;
      tool.addListener(() => notifications++);

      tool.active = true;
      expect(notifications, 1);
      tool.active = true;
      expect(notifications, 1, reason: 'no change, no rebuild');
      tool.active = false;
      expect(notifications, 2);
    });

    test('updating one brush setting leaves the rest', () {
      final tool = TerrainToolController()..updateBrush(radius: 9, strength: 3);
      tool.updateBrush(kind: TerrainBrushKind.smooth);

      expect(tool.brush.kind, TerrainBrushKind.smooth);
      expect(tool.brush.radius, 9, reason: 'the radius survived');
      expect(tool.brush.strength, 3);
    });
  });

  group('finding a target', () {
    test('a node with no mesh is not a target', () {
      expect(terrainTargetOf(Node(name: 'empty'), (_) => null), isNull);
    });

    test('a null node is not a target', () {
      expect(terrainTargetOf(null, (_) => null), isNull);
    });
  });
}
