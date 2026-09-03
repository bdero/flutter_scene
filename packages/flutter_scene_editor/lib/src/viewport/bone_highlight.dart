/// The MCP bone-highlight overlay.
///
/// Draws a stick figure over the bones an agent highlighted through the
/// `highlight_bones` MCP tool: a marker at each highlighted joint and a
/// segment from it to each of its live children, so the human sees exactly
/// which joints the agent is about to animate. Bones are matched by composed
/// node id ([EditorController.highlightedBones]); the painter resolves each
/// id's live transform and projects it through the viewport camera at paint
/// time, and it always repaints (see [shouldRepaint]), so the sticks track
/// the current pose as the viewport repaints on camera moves, gizmo drags,
/// and controller/preview updates.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../controller/editor_controller.dart';
import 'transform_gizmo.dart' show projectToScreen;

/// The highlight color: a distinct magenta that stays readable over the
/// selection accent (cyan outlines) and the component gizmos.
const Color kBoneHighlightColor = Color(0xFFFF2FD6);

/// Paints the agent-highlighted bones over the scene.
class BoneHighlightPainter extends CustomPainter {
  /// Creates the painter.
  BoneHighlightPainter({required this.controller, required this.camera});

  /// The controller owning the highlight state and the live scene.
  final EditorController controller;

  /// The viewport camera to project through.
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final ids = controller.highlightedBones.value;
    if (ids.isEmpty) return;
    final stick =
        Paint()
          ..color = kBoneHighlightColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round;
    final joint = Paint()..color = kBoneHighlightColor;
    final rim =
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    for (final id in ids) {
      final node = controller.liveNode(id);
      if (node == null) continue;
      final vm.Vector3 origin = node.globalTransform.getTranslation();
      final screen = projectToScreen(origin, camera, size);
      if (screen == null) continue;
      for (final child in node.children) {
        final childScreen = projectToScreen(
          child.globalTransform.getTranslation(),
          camera,
          size,
        );
        if (childScreen != null) {
          canvas.drawLine(screen, childScreen, stick);
        }
      }
      canvas.drawCircle(screen, 5, joint);
      canvas.drawCircle(screen, 5, rim);
    }
  }

  @override
  // Always repaint: the sticks are projected from the live node transforms
  // and current camera at paint time, so every viewport epoch (camera orbit,
  // gizmo drag, controller/preview update) must redraw them. Same contract
  // as TransformGizmoPainter; the viewport's RepaintBoundary keeps the cost
  // local to this overlay.
  bool shouldRepaint(BoneHighlightPainter oldDelegate) => true;
}