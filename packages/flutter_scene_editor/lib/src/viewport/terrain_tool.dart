/// The viewport's terrain sculpting tool: what the brush is set to, and the
/// stroke in progress.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../inspector/property_editors.dart' show SliderNumberField;
import '../shell/editor_theme.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart' show LocalId;
import 'package:vector_math/vector_math.dart' as vm;

/// The sculpting tool's settings: whether it is armed, and what the brush
/// does when it is.
///
/// Held apart from the viewport so the inspector can drive the same brush the
/// viewport paints with, and so the settings survive a viewport being closed
/// and reopened.
class TerrainToolController extends ChangeNotifier {
  bool _active = false;
  TerrainBrush _brush = const TerrainBrush();

  /// Whether the tool takes the primary button instead of the gizmo.
  bool get active => _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  /// What a stroke does.
  TerrainBrush get brush => _brush;
  set brush(TerrainBrush value) {
    _brush = value;
    notifyListeners();
  }

  /// Replaces one part of the brush, leaving the rest.
  void updateBrush({
    TerrainBrushKind? kind,
    double? radius,
    double? strength,
    double? falloff,
    double? targetHeight,
  }) {
    brush = TerrainBrush(
      kind: kind ?? _brush.kind,
      radius: radius ?? _brush.radius,
      strength: strength ?? _brush.strength,
      falloff: falloff ?? _brush.falloff,
      targetHeight: targetHeight ?? _brush.targetHeight,
    );
  }
}

/// One sculpting stroke, from pointer down to pointer up.
///
/// The stroke edits the live geometry's own height field so the viewport
/// shows the result immediately, and reports the samples once at the end.
/// Nothing reaches the document until then: a stroke is one undo step, and
/// writing each dab would fill the history with a hundred of them.
class TerrainStroke {
  /// Begins a stroke on [geometry], whose samples came from [resourceId].
  TerrainStroke({required this.geometry, required this.resourceId});

  /// The live mesh being sculpted.
  final TerrainGeometry geometry;

  /// The geometry resource its samples belong to.
  final LocalId resourceId;

  bool _touched = false;

  /// Whether any dab actually moved the ground. A stroke that only ever
  /// missed is not worth an undo entry.
  bool get touched => _touched;

  /// Applies one dab at world [point], and refreshes the mesh when the ground
  /// moved.
  void dab(TerrainBrush brush, vm.Vector3 point, double deltaSeconds) {
    final range = sculptTerrain(
      geometry.field,
      brush: brush,
      x: point.x,
      z: point.z,
      deltaSeconds: deltaSeconds,
    );
    if (range == null) return;
    _touched = true;
    // Only the rows the dab reached; a small brush on a large terrain should
    // not rewrite the whole map every pointer move.
    geometry.rebuildFromField(fromRow: range.minRow, toRow: range.maxRow);
  }

  /// The finished samples, as the command takes them.
  String encodedHeights() => base64Encode(geometry.field.toBytes());
}

/// A plane on [node] that could be made sculptable, with its resource, or
/// null when there is none.
///
/// Sculpting starts from a plane: a flat sheet is the thing anyone reaches
/// for first, and a separate terrain object to remember is a worse story than
/// pushing the sheet you already have.
({LocalId resourceId})? sculptablePlaneOf(
  Node? node,
  LocalId? Function(Object geometry) resourceIdOf,
) {
  final primitives = node?.mesh?.primitives;
  if (primitives == null || primitives.isEmpty) return null;
  for (final primitive in primitives) {
    final geometry = primitive.geometry;
    if (geometry is TerrainGeometry) return null;
    final id = resourceIdOf(geometry);
    if (id != null) return (resourceId: id);
  }
  return null;
}

/// The terrain under [node], with the resource its samples belong to, or null
/// when that node is not terrain.
///
/// The resource id is needed to write the stroke back, and a geometry built
/// in code rather than realized from a document has none — sculpting it would
/// show on screen and vanish on save, so it is refused instead.
({TerrainGeometry geometry, LocalId resourceId})? terrainTargetOf(
  Node? node,
  LocalId? Function(Object geometry) resourceIdOf,
) {
  final primitives = node?.mesh?.primitives;
  if (primitives == null || primitives.isEmpty) return null;
  for (final primitive in primitives) {
    final geometry = primitive.geometry;
    if (geometry is! TerrainGeometry) continue;
    final id = resourceIdOf(geometry);
    if (id == null) return null;
    return (geometry: geometry, resourceId: id);
  }
  return null;
}

/// The floating brush palette shown while sculpting is armed.
///
/// It sits over the viewport rather than in the inspector because a brush is
/// adjusted mid-stroke, between dabs, and reaching across the window for the
/// radius breaks that rhythm.
class TerrainBrushPalette extends StatelessWidget {
  /// Shows and edits [tool]'s brush.
  const TerrainBrushPalette({required this.tool, super.key});

  /// The tool whose brush this edits.
  final TerrainToolController tool;

  static const _kinds = <(TerrainBrushKind, IconData, String)>[
    (TerrainBrushKind.raise, Icons.landscape, 'Raise, or lower with Alt'),
    (TerrainBrushKind.smooth, Icons.blur_on, 'Smooth'),
    (TerrainBrushKind.flatten, Icons.layers_clear, 'Flatten'),
  ];

  @override
  Widget build(BuildContext context) {
    final brush = tool.brush;
    return Container(
      width: 208,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: editorPanelColor.withValues(alpha: 0.95),
        border: Border.all(color: editorLineColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Terrain', style: editorSubheadText),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (kind, icon, tip) in _kinds)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: tip,
                    child: InkWell(
                      onTap: () => tool.updateBrush(kind: kind),
                      child: Container(
                        width: 30,
                        height: 26,
                        decoration: BoxDecoration(
                          color: brush.kind == kind
                              ? editorAccentColor
                              : editorRaisedColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Icon(
                          icon,
                          size: editorIconSize,
                          color: brush.kind == kind
                              ? editorSurfaceColor
                              : editorTextColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SliderNumberField(
            label: 'Size',
            value: brush.radius,
            min: 0.5,
            max: 40,
            fractionDigits: 2,
            onPreview: (_) {},
            onCommit: (value) => tool.updateBrush(radius: value),
          ),
          SliderNumberField(
            label: 'Strength',
            value: brush.strength,
            min: 0.1,
            max: 10,
            fractionDigits: 2,
            onPreview: (_) {},
            onCommit: (value) => tool.updateBrush(strength: value),
          ),
          SliderNumberField(
            label: 'Falloff',
            value: brush.falloff,
            min: 0,
            max: 1,
            fractionDigits: 2,
            onPreview: (_) {},
            onCommit: (value) => tool.updateBrush(falloff: value),
          ),
          if (brush.kind == TerrainBrushKind.flatten)
            SliderNumberField(
              label: 'Height',
              value: brush.targetHeight,
              min: -20,
              max: 20,
              fractionDigits: 2,
              onPreview: (_) {},
              onCommit: (value) => tool.updateBrush(targetHeight: value),
            ),
        ],
      ),
    );
  }
}

/// Draws the brush's footprint on the ground.
///
/// A ring on the surface rather than a circle on the glass: the brush reaches
/// a radius in world units, so on a slope or in perspective its footprint is
/// not a screen-space circle, and drawing one would lie about where the
/// stroke will land.
class TerrainBrushCursorPainter extends CustomPainter {
  /// Draws [brush] centred on [center], sampling the ground from [field].
  TerrainBrushCursorPainter({
    required this.center,
    required this.brush,
    required this.field,
    required this.project,
    required this.color,
  });

  /// Where the pointer meets the ground.
  final vm.Vector3 center;

  /// The brush being drawn.
  final TerrainBrush brush;

  /// The ground the ring follows.
  final HeightField field;

  /// Maps a world point into the view, or null when it is behind the camera.
  final Offset? Function(vm.Vector3 point) project;

  /// The ring's colour.
  final Color color;

  static const _segments = 48;

  @override
  void paint(Canvas canvas, Size size) {
    void ring(double radius, double opacity, double width) {
      if (radius <= 0) return;
      final path = Path();
      var started = false;
      for (var i = 0; i <= _segments; i++) {
        final angle = i / _segments * 2 * math.pi;
        final x = center.x + math.cos(angle) * radius;
        final z = center.z + math.sin(angle) * radius;
        final point = project(vm.Vector3(x, field.heightAtWorld(x, z), z));
        // A ring crossing behind the camera is drawn in pieces rather than
        // joined across the screen by a stray chord.
        if (point == null) {
          started = false;
          continue;
        }
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color.withValues(alpha: opacity),
      );
    }

    // The rim, and the edge where the brush stops being at full strength, so
    // the falloff is something you can see rather than a number.
    ring(brush.radius, 0.9, 1.5);
    ring(brush.radius * brush.falloff.clamp(0.0, 1.0), 0.35, 1);
  }

  @override
  bool shouldRepaint(TerrainBrushCursorPainter old) =>
      old.center != center ||
      old.brush.radius != brush.radius ||
      old.brush.falloff != brush.falloff ||
      old.color != color;
}
