// The sculpting tool's state and stroke bookkeeping. The viewport wiring
// needs a GPU; these are the parts that do not.
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor/src/viewport/terrain_tool.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart' show SceneDocument;
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('arming a tool', () {
    test('nothing is armed until a tool is chosen', () {
      // Which is what keeps the move gizmo working on a terrain: the brush
      // takes the mouse only when someone asks for it.
      final tool = TerrainToolController();
      expect(tool.tool, isNull);
      expect(tool.active, isFalse);
      expect(tool.sculpting, isFalse);
      expect(tool.painting, isFalse);
    });

    test('choosing the paint tool arms the brush', () {
      final tool = TerrainToolController()..tool = TerrainTool.paint;
      expect(tool.active, isTrue);
      expect(tool.sculpting, isTrue, reason: 'it opens on Raise or Lower');
    });

    test('a tool that has no brush yet does not take the mouse', () {
      // Trees and Details are in the toolbar and not built; selecting one
      // should not silently give the brush the left button.
      final tool = TerrainToolController()..tool = TerrainTool.trees;
      expect(tool.active, isFalse);
    });

    test('clicking the armed tool again hands the mouse back', () {
      final tool = TerrainToolController()..toggle(TerrainTool.paint);
      expect(tool.tool, TerrainTool.paint);
      tool.toggle(TerrainTool.paint);
      expect(tool.tool, isNull);
    });

    test('choosing a different tool switches rather than stacking', () {
      final tool = TerrainToolController()..toggle(TerrainTool.paint);
      tool.toggle(TerrainTool.settings);
      expect(tool.tool, TerrainTool.settings);
      expect(tool.active, isFalse);
    });

    test('it notifies once per actual change', () {
      final tool = TerrainToolController();
      var notifications = 0;
      tool.addListener(() => notifications++);
      tool.tool = TerrainTool.paint;
      tool.tool = TerrainTool.paint;
      expect(notifications, 1, reason: 'no change, no rebuild');
      tool.tool = null;
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

  group('what a stroke does', () {
    test('it opens on Raise or Lower, and on layer 1 rather than the base', () {
      // Layer 0 is what a terrain is before anyone paints it, so the first
      // stroke of a session is almost always adding to it, not repainting it.
      final tool = TerrainToolController();
      expect(tool.paintMode, TerrainPaintMode.raiseLower);
      expect(tool.paintLayer, 1);
      expect(tool.targetStrength, 1);
    });

    test('every mode has a label, so the dropdown has no blanks', () {
      for (final mode in TerrainPaintMode.values) {
        expect(terrainPaintModeLabel(mode), isNotEmpty, reason: mode.name);
      }
    });

    test('only Paint Texture paints; the rest move the ground', () {
      for (final mode in TerrainPaintMode.values) {
        expect(
          terrainPaintModeSculpts(mode),
          mode != TerrainPaintMode.texture,
          reason: mode.name,
        );
      }
    });

    test('the mode notifies once per actual change', () {
      final tool = TerrainToolController();
      var notifications = 0;
      tool.addListener(() => notifications++);
      tool.paintMode = TerrainPaintMode.texture;
      tool.paintMode = TerrainPaintMode.texture;
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
      // The radius and falloff mean the same thing to every mode, so
      // switching should not make the user re-dial them.
      final tool = TerrainToolController()
        ..updateBrush(radius: 12, falloff: 0.3);
      tool.paintMode = TerrainPaintMode.texture;
      expect(tool.brush.radius, 12);
      expect(tool.brush.falloff, 0.3);
    });
  });

  group('the brush a stroke applies', () {
    test('the mode picks the kind, so there is one thing to set', () {
      final tool = TerrainToolController()..paintMode = TerrainPaintMode.smooth;
      expect(tool.strokeBrush().kind, TerrainBrushKind.smooth);
      tool.paintMode = TerrainPaintMode.setHeight;
      expect(tool.strokeBrush().kind, TerrainBrushKind.flatten);
      tool.paintMode = TerrainPaintMode.raiseLower;
      expect(tool.strokeBrush().kind, TerrainBrushKind.raise);
    });

    test('Shift digs instead of raising', () {
      final tool = TerrainToolController()..updateBrush(strength: 3);
      expect(tool.strokeBrush().strength, 3);
      expect(tool.strokeBrush(lower: true).strength, -3);
    });

    test('a stamp presses its own height, not the brush opacity', () {
      // A stamp is one press of a shape; how deep it goes is a distance, and
      // reusing the per-second opacity for it would make the two settings
      // fight.
      final tool = TerrainToolController()
        ..paintMode = TerrainPaintMode.stamp
        ..updateBrush(strength: 2)
        ..stampHeight = 7;
      expect(tool.strokeBrush().strength, 7);
      expect(tool.strokeBrush(lower: true).strength, -7);
    });

    test('Set Height carries the height it pulls toward', () {
      final tool = TerrainToolController()
        ..paintMode = TerrainPaintMode.setHeight
        ..updateBrush(targetHeight: 3.5);
      expect(tool.strokeBrush().targetHeight, 3.5);
    });

    test('the radius steps multiplicatively and stays in range', () {
      // The useful range spans two orders of magnitude, so a step that suits
      // a footpath is imperceptible on a mountainside.
      final tool = TerrainToolController()..updateBrush(radius: 10);
      tool.nudgeRadius(1.25);
      expect(tool.brush.radius, closeTo(12.5, 1e-9));
      tool.nudgeRadius(1 / 1.25);
      expect(tool.brush.radius, closeTo(10, 1e-9));

      for (var i = 0; i < 60; i++) {
        tool.nudgeRadius(1 / 1.25);
      }
      expect(tool.brush.radius, greaterThan(0));
      for (var i = 0; i < 80; i++) {
        tool.nudgeRadius(1.25);
      }
      expect(tool.brush.radius, lessThanOrEqualTo(200));
    });

    test('opacity steps and stays usable at both ends', () {
      final tool = TerrainToolController()..updateBrush(strength: 1);
      tool.nudgeStrength(0.25);
      expect(tool.brush.strength, closeTo(1.25, 1e-9));
      for (var i = 0; i < 40; i++) {
        tool.nudgeStrength(-0.25);
      }
      // Never zero: a brush that does nothing looks like a broken tool.
      expect(tool.brush.strength, greaterThan(0));
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
