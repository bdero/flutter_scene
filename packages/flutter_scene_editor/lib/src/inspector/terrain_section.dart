/// The Terrain section of the inspector: the tools, and the brush they use.
///
/// This is where terrain editing is *reached*. Before it existed the only way
/// to arm a brush was a small unlabelled button in the corner of the scene
/// view, disabled unless you already had the right object selected — so
/// dragging over a terrain moved the object, which is what the move gizmo is
/// for and exactly what it looked like was broken.
///
/// The shape is the conventional one, because it is the one people arrive
/// knowing: a row of tool buttons, a dropdown of what a stroke does, and the
/// brush settings under it. Choosing a tool arms it and takes the left mouse button; choosing
/// it again hands the button back to the gizmo.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import '../tools/terrain_tool_controller.dart';
import 'property_editors.dart' show SliderNumberField;

/// The terrain spec on [nodeId]'s mesh, or null when it is not terrain.
TerrainGeometrySpec? terrainSpecOf(EditorController ctrl, LocalId nodeId) =>
    terrainSpecOfDocument(
      ctrl.document,
      nodeId,
      node: ctrl.displayNode(nodeId),
    );

/// The decision itself, over a document rather than a live editor.
///
/// Split out because it is a question about a node's geometry, and because
/// the inspector asks it while drawing: a dangling geometry reference has to
/// read as "not terrain" rather than throw mid-frame.
TerrainGeometrySpec? terrainSpecOfDocument(
  SceneDocument document,
  LocalId nodeId, {
  NodeSpec? node,
}) {
  final spec = node ?? document.node(nodeId);
  if (spec == null) return null;
  for (final component in spec.components) {
    if (component.type != 'mesh') continue;
    final reference = component.properties['geometry'];
    if (reference is! ResourceRefValue) continue;
    final resource = document.resource(reference.id);
    if (resource is! GeometryResource) continue;
    final procedural = resource.procedural;
    if (procedural is TerrainGeometrySpec) return procedural;
  }
  return null;
}

/// The tools shown, with what each is for.
const List<({TerrainTool tool, IconData icon, String label, String tip})>
terrainTools = [
  (
    tool: TerrainTool.neighbors,
    icon: Icons.grid_view,
    label: 'Neighbors',
    tip: 'Create Neighbor Terrains',
  ),
  (
    tool: TerrainTool.paint,
    icon: Icons.brush,
    label: 'Paint',
    tip: 'Paint Terrain: sculpt the ground and paint its surface',
  ),
  (
    tool: TerrainTool.trees,
    icon: Icons.park_outlined,
    label: 'Trees',
    tip: 'Paint Trees',
  ),
  (
    tool: TerrainTool.details,
    icon: Icons.grass,
    label: 'Details',
    tip: 'Paint Details: grass, flowers and rocks',
  ),
  (
    tool: TerrainTool.settings,
    icon: Icons.settings_outlined,
    label: 'Settings',
    tip: 'Terrain Settings',
  ),
];

/// The Terrain section, shown for a node whose mesh is a terrain.
class TerrainSection extends StatelessWidget {
  const TerrainSection({
    super.key,
    required this.controller,
    required this.nodeId,
    required this.spec,
  });

  final EditorController controller;
  final LocalId nodeId;
  final TerrainGeometrySpec spec;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.terrainTool,
    builder: (context, _) {
      final tool = controller.terrainTool;
      return EditorCollapsibleSection(
        key: const ValueKey('section:terrain'),
        label: 'Terrain',
        icon: Icons.terrain_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ToolBar(tool: tool),
            const SizedBox(height: 10),
            switch (tool.tool) {
              TerrainTool.paint => _PaintTools(tool: tool),
              TerrainTool.settings => _Settings(spec: spec),
              null => Text(
                'Choose a tool to start editing. The tool you pick takes the '
                'left mouse button until you pick it again.',
                style: editorDetailText,
              ),
              final other => _NotYet(tool: other),
            },
          ],
        ),
      );
    },
  );
}

/// The row of tool buttons.
class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.tool});

  final TerrainToolController tool;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final entry in terrainTools)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Tooltip(
              message: entry.tip,
              child: InkWell(
                onTap: () => tool.toggle(entry.tool),
                borderRadius: BorderRadius.circular(editorControlRadius),
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: tool.tool == entry.tool
                        ? editorAccentColor
                        : editorRaisedColor,
                    borderRadius: BorderRadius.circular(editorControlRadius),
                  ),
                  child: Icon(
                    entry.icon,
                    size: 16,
                    color: tool.tool == entry.tool
                        ? editorSurfaceColor
                        : editorTextColor,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// The Paint Terrain tool: what a stroke does, and the brush that does it.
class _PaintTools extends StatelessWidget {
  const _PaintTools({required this.tool});

  final TerrainToolController tool;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 28,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<TerrainPaintMode>(
            value: tool.paintMode,
            isExpanded: true,
            isDense: true,
            style: editorBodyText.copyWith(color: editorTextColor),
            dropdownColor: editorRaisedColor,
            items: [
              for (final mode in TerrainPaintMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: Text(terrainPaintModeLabel(mode)),
                ),
            ],
            onChanged: (picked) =>
                picked == null ? null : tool.paintMode = picked,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(_hintFor(tool.paintMode), style: editorDetailText),
      const SizedBox(height: 10),
      if (tool.painting) ...[
        Text('Layer', style: editorMicroText),
        const SizedBox(height: 4),
        _LayerRow(tool: tool),
        const SizedBox(height: 10),
      ],
      SliderNumberField(
        label: 'Brush Size',
        value: tool.brush.radius,
        min: 0.5,
        max: 60,
        fractionDigits: 2,
        onPreview: (_) {},
        onCommit: (value) => tool.updateBrush(radius: value),
      ),
      SliderNumberField(
        label: 'Opacity',
        value: tool.brush.strength,
        min: 0.1,
        max: 10,
        fractionDigits: 2,
        onPreview: (_) {},
        onCommit: (value) => tool.updateBrush(strength: value),
      ),
      SliderNumberField(
        label: 'Falloff',
        value: tool.brush.falloff,
        min: 0,
        max: 1,
        fractionDigits: 2,
        onPreview: (_) {},
        onCommit: (value) => tool.updateBrush(falloff: value),
      ),
      if (tool.paintMode == TerrainPaintMode.setHeight)
        SliderNumberField(
          label: 'Height',
          value: tool.brush.targetHeight,
          min: -50,
          max: 50,
          fractionDigits: 2,
          onPreview: (_) {},
          onCommit: (value) => tool.updateBrush(targetHeight: value),
        ),
      if (tool.paintMode == TerrainPaintMode.stamp)
        SliderNumberField(
          label: 'Stamp Height',
          value: tool.stampHeight,
          min: -50,
          max: 50,
          fractionDigits: 2,
          onPreview: (_) {},
          onCommit: (value) => tool.stampHeight = value,
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
      const SizedBox(height: 8),
      Text(
        'Brush size: [ and ]   ·   Opacity: - and =',
        style: editorMicroText,
      ),
    ],
  );
}

/// What each mode does, in one line, where the person choosing it is looking.
String _hintFor(TerrainPaintMode mode) => switch (mode) {
  TerrainPaintMode.raiseLower =>
    'Drag to raise the ground. Hold Shift to lower it.',
  TerrainPaintMode.texture =>
    'Drag to blend the chosen layer in. The layers underneath fade out to '
        'make room.',
  TerrainPaintMode.setHeight =>
    'Drag to pull the ground toward the height below.',
  TerrainPaintMode.smooth => 'Drag to average the ground against itself.',
  TerrainPaintMode.stamp =>
    'Click once to press the brush shape in. Hold Shift to press it down.',
  TerrainPaintMode.holes => 'Drag to cut the ground away.',
};

/// The four surface layers, as swatches.
class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.tool});

  final TerrainToolController tool;

  /// A distinct tint per layer, so they read as four different things before
  /// any textures are assigned to them.
  static const tints = [
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
                    color: tints[layer],
                    borderRadius: BorderRadius.circular(editorControlRadius),
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

/// Terrain Settings: what the terrain is, as opposed to what is on it.
///
/// Read-only for now. Every one of these resizes or resamples the height
/// field, which is a real operation with real choices in it — a terrain made
/// finer has to decide what the new samples are — and showing the numbers is
/// worth more than a control that silently discards a sculpt.
class _Settings extends StatelessWidget {
  const _Settings({required this.spec});

  final TerrainGeometrySpec spec;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row('Terrain Width', '${spec.width.toStringAsFixed(1)} m'),
      _row('Terrain Length', '${spec.depth.toStringAsFixed(1)} m'),
      _row('Heightmap Resolution', '${spec.columns} x ${spec.rows}'),
      _row(
        'Control Texture Resolution',
        '${spec.splatColumns} x ${spec.splatRows}',
      ),
      _row('Sculpted', spec.isSculpted ? 'yes' : 'not yet'),
      _row('Painted', spec.isPainted ? 'yes' : 'not yet'),
      const SizedBox(height: 8),
      Text(
        'Resizing a terrain resamples its heightmap, which is a choice about '
        'what the new samples are rather than a setting. Not editable here '
        'yet.',
        style: editorMicroText,
      ),
    ],
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: editorRowGap),
    child: Row(
      children: [
        Expanded(child: Text(label, style: editorDetailText)),
        Text(value, style: editorBodyText),
      ],
    ),
  );
}

/// A tool that is in the toolbar but not built yet.
///
/// Shown rather than hidden, because a gap you can see is a roadmap and a
/// missing button is a thing people hunt for.
class _NotYet extends StatelessWidget {
  const _NotYet({required this.tool});

  final TerrainTool tool;

  @override
  Widget build(BuildContext context) {
    final entry = terrainTools.firstWhere((e) => e.tool == tool);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.tip, style: editorBodyText),
        const SizedBox(height: 4),
        Text(_whatItNeeds(tool), style: editorDetailText),
      ],
    );
  }

  static String _whatItNeeds(TerrainTool tool) => switch (tool) {
    TerrainTool.neighbors =>
      'Not built yet. It needs terrains to know about the tiles beside them '
          'so their edges can be stitched, which nothing tracks today.',
    TerrainTool.trees =>
      'Not built yet, but the scatter tool places meshes over ground and is '
          'most of what this is.',
    TerrainTool.details =>
      'Not built yet. Grass and rocks want instanced billboards rather than '
          'the scattered meshes trees use.',
    _ => 'Not built yet.',
  };
}
