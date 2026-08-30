// The sculpting tool's state and stroke bookkeeping. The viewport wiring
// needs a GPU; these are the parts that do not.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/viewport/terrain_tool.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' show SceneDocument;
import 'package:vector_math/vector_math.dart' as vm;

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

  group('paint mode', () {
    test('opens on sculpt, and on layer 1 rather than the base', () {
      // Layer 0 is what a terrain is before anyone paints it, so the first
      // stroke of a session is almost always adding to it, not repainting it.
      final tool = TerrainToolController();
      expect(tool.mode, TerrainToolMode.sculpt);
      expect(tool.paintLayer, 1);
      expect(tool.targetStrength, 1);
    });

    test('the mode notifies once per actual change', () {
      final tool = TerrainToolController();
      var notifications = 0;
      tool.addListener(() => notifications++);
      tool.mode = TerrainToolMode.paint;
      tool.mode = TerrainToolMode.paint;
      expect(notifications, 1);
    });

    test('the layer is held inside the four that exist', () {
      final tool = TerrainToolController();
      tool.paintLayer = 99;
      expect(tool.paintLayer, terrainSplatLayers - 1);
      tool.paintLayer = -3;
      expect(tool.paintLayer, 0);
    });

    test('the target strength is held between none and full', () {
      final tool = TerrainToolController();
      tool.targetStrength = 5;
      expect(tool.targetStrength, 1);
      tool.targetStrength = -1;
      expect(tool.targetStrength, 0);
    });

    test('switching mode leaves the brush alone', () {
      // The radius and falloff mean the same thing to both tools, so
      // switching should not make the user re-dial them.
      final tool = TerrainToolController()
        ..updateBrush(radius: 12, falloff: 0.3);
      tool.mode = TerrainToolMode.paint;
      expect(tool.brush.radius, 12);
      expect(tool.brush.falloff, 0.3);
    });
  });

  group('a paint stroke', () {
    TerrainSplatMap map() =>
        TerrainSplatMap.base(width: 32, depth: 32, columns: 32, rows: 32);

    test('a stroke that missed is not worth an undo entry', () {
      final stroke = TerrainPaintStroke(
        map: map(),
        resourceId: SceneDocument().newId(),
      );
      expect(stroke.touched, isFalse);
      stroke.dab(
        const TerrainBrush(radius: 2),
        1,
        1,
        vm.Vector3(500, 0, 500),
        1 / 60,
      );
      expect(stroke.touched, isFalse);
    });

    test('a dab on the terrain paints and is worth recording', () {
      final stroke = TerrainPaintStroke(
        map: map(),
        resourceId: SceneDocument().newId(),
      );
      for (var i = 0; i < 40; i++) {
        stroke.dab(
          const TerrainBrush(radius: 6, strength: 4, falloff: 0),
          2,
          1,
          vm.Vector3.zero(),
          1 / 60,
        );
      }
      expect(stroke.touched, isTrue);
      expect(stroke.map.dominantLayerAtWorld(0, 0), 2);
    });

    test('the target strength caps what a held brush reaches', () {
      final stroke = TerrainPaintStroke(
        map: map(),
        resourceId: SceneDocument().newId(),
      );
      for (var i = 0; i < 300; i++) {
        stroke.dab(
          const TerrainBrush(radius: 6, strength: 4, falloff: 0),
          1,
          0.5,
          vm.Vector3.zero(),
          1 / 60,
        );
      }
      expect(stroke.map.weightAt(16, 16, 1), closeTo(0.5, 0.02));
    });

    test('the finished map encodes to what the command takes', () {
      final stroke = TerrainPaintStroke(
        map: TerrainSplatMap.base(width: 32, depth: 32, columns: 16, rows: 8),
        resourceId: SceneDocument().newId(),
      );
      expect(base64Decode(stroke.encodedSplat()).lengthInBytes, 16 * 8 * 4);
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
