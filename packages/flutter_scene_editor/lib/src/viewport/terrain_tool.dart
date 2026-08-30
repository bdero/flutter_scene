/// The viewport's terrain sculpting tool: what the brush is set to, and the
/// stroke in progress.
library;

export '../tools/terrain_tool_controller.dart';

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../inspector/property_editors.dart' show SliderNumberField;
import '../shell/editor_theme.dart';
import 'package:flutter_scene/scene.dart';

import '../tools/terrain_tool_controller.dart';
import 'package:scene/scene.dart' show LocalId;
import 'package:vector_math/vector_math.dart' as vm;

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

/// One painting stroke, from pointer down to pointer up.
///
/// The sibling of [TerrainStroke], and the same bargain: it edits the live
/// geometry's control map so the viewport can show the result, and reports the
/// finished map once at the end, because a stroke is one thing the user did.
class TerrainPaintStroke {
  /// Begins a stroke into [map], which belongs to [resourceId].
  TerrainPaintStroke({required this.map, required this.resourceId});

  /// Begins a stroke on [geometry].
  ///
  /// A terrain painted for the first time has no control map yet, so one is
  /// minted here — entirely the base layer, which is exactly what the terrain
  /// already looked like — and attached to the geometry so the next stroke
  /// carries on painting the same map.
  factory TerrainPaintStroke.on(
    TerrainGeometry geometry, {
    required LocalId resourceId,
    int columns = 256,
    int rows = 256,
  }) => TerrainPaintStroke(
    resourceId: resourceId,
    map:
        geometry.splat ??
        (geometry.splat = TerrainSplatMap.base(
          width: geometry.field.width,
          depth: geometry.field.depth,
          columns: columns,
          rows: rows,
        )),
  );

  /// The geometry resource this control map belongs to.
  final LocalId resourceId;

  /// The map being painted into.
  final TerrainSplatMap map;

  bool _touched = false;

  /// Whether any dab actually changed the ground's surface.
  bool get touched => _touched;

  /// Applies one dab of [layer] at world [point].
  void dab(
    TerrainBrush brush,
    int layer,
    double targetStrength,
    vm.Vector3 point,
    double deltaSeconds,
  ) {
    final range = paintTerrainSplat(
      map,
      layer: layer,
      brush: brush,
      x: point.x,
      z: point.z,
      deltaSeconds: deltaSeconds,
      targetStrength: targetStrength,
    );
    if (range != null) _touched = true;
  }

  /// The finished control map, as the command takes it.
  String encodedSplat() => base64Encode(map.toBytes());
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

/// The floating brush readout shown while a terrain tool is armed.
///
/// It sits over the viewport rather than only in the inspector because a brush
/// is adjusted mid-stroke, between dabs, and reaching across the window for
/// the radius breaks that rhythm. *Which* tool is armed is chosen in the
/// inspector, the way it is in Unity; this is the size and strength of
/// whichever one that is.
class TerrainBrushPalette extends StatelessWidget {
  /// Shows and edits [tool]'s brush.
  const TerrainBrushPalette({required this.tool, super.key});

  /// The tool whose brush this edits.
  final TerrainToolController tool;

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
          Text(
            terrainPaintModeLabel(tool.paintMode),
            style: editorSubheadText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          if (tool.painting) ...[
            _LayerPicker(tool: tool),
            const SizedBox(height: 10),
          ],
          SliderNumberField(
            label: 'Brush Size',
            value: brush.radius,
            min: 0.5,
            max: 40,
            fractionDigits: 2,
            onPreview: (_) {},
            onCommit: (value) => tool.updateBrush(radius: value),
          ),
          SliderNumberField(
            label: 'Opacity',
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
          if (tool.painting)
            SliderNumberField(
              label: 'Target Strength',
              value: tool.targetStrength,
              min: 0,
              max: 1,
              fractionDigits: 2,
              onPreview: (_) {},
              onCommit: (value) => tool.targetStrength = value,
            ),
          if (tool.paintMode == TerrainPaintMode.setHeight)
            SliderNumberField(
              label: 'Height',
              value: brush.targetHeight,
              min: -20,
              max: 20,
              fractionDigits: 2,
              onPreview: (_) {},
              onCommit: (value) => tool.updateBrush(targetHeight: value),
            ),
          if (tool.paintMode == TerrainPaintMode.stamp)
            SliderNumberField(
              label: 'Stamp Height',
              value: tool.stampHeight,
              min: -20,
              max: 20,
              fractionDigits: 2,
              onPreview: (_) {},
              onCommit: (value) => tool.stampHeight = value,
            ),
        ],
      ),
    );
  }
}

/// Which of the four surface layers a paint stroke lays down.
///
/// Four swatches rather than a dropdown: the layer is switched between
/// strokes constantly, and a menu that has to be opened to see what is in it
/// is the wrong control for something chosen that often.
class _LayerPicker extends StatelessWidget {
  const _LayerPicker({required this.tool});

  final TerrainToolController tool;

  /// A distinct tint per layer, so the picker reads as four different things
  /// before any textures are assigned to them.
  static const _tints = [
    Color(0xFF6B8F4E),
    Color(0xFF8A7B5C),
    Color(0xFF7E8489),
    Color(0xFFC9BC93),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var layer = 0; layer < terrainSplatLayers; layer++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: layer == 0 ? 'Layer 1 (base)' : 'Layer ${layer + 1}',
              child: InkWell(
                onTap: () => tool.paintLayer = layer,
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    color: _tints[layer],
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: tool.paintLayer == layer
                          ? editorAccentColor
                          : editorLineColor,
                      width: tool.paintLayer == layer ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
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
