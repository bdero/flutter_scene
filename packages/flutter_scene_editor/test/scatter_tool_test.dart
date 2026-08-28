// The painting tool's state and stroke bookkeeping. The viewport wiring needs
// a GPU; these are the parts that do not.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/viewport/scatter_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the tool', () {
    test('starts disarmed and painting rather than erasing', () {
      final tool = ScatterToolController();
      expect(tool.active, isFalse);
      expect(tool.action, ScatterAction.paint);
    });

    test('notifies on a real change only', () {
      final tool = ScatterToolController();
      var notifications = 0;
      tool.addListener(() => notifications++);

      tool.active = true;
      tool.active = true;
      expect(notifications, 1);

      tool.action = ScatterAction.erase;
      tool.action = ScatterAction.erase;
      expect(notifications, 2);
    });

    test('updating one brush setting leaves the rest', () {
      final tool = ScatterToolController()
        ..updateBrush(radius: 7, minSpacing: 2);
      tool.updateBrush(density: 20);

      expect(tool.brush.density, 20);
      expect(tool.brush.radius, 7);
      expect(tool.brush.minSpacing, 2);
    });
  });

  group('finding a layer', () {
    test('a node without one is not a target', () {
      expect(scatterLayerOf(Node(name: 'bare')), isNull);
    });

    test('a null node is not a target', () {
      expect(scatterLayerOf(null), isNull);
    });
  });
}
