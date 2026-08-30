/// What the terrain tools are set to, shared by the inspector that chooses
/// them and the viewport that applies them.
///
/// Unity's shape, because it is the one people arrive knowing: a Terrain's
/// inspector carries a row of tool buttons, choosing one arms it, and the
/// armed tool owns the left mouse button in the scene view until you choose
/// another. That last part is the whole reason this lives outside the
/// viewport. The tool is picked in the inspector and used in the viewport, so
/// neither can own the state, and while it was private to the viewport the
/// only way to arm a brush was a small unlabelled button in the corner of the
/// scene — which is why dragging over a terrain moved the object instead of
/// shaping it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';

/// The terrain tools, in the order Unity's inspector shows them.
enum TerrainTool {
  /// Add a terrain tile alongside this one.
  neighbors,

  /// Sculpt and paint the surface. The one with sub-modes.
  paint,

  /// Scatter trees.
  trees,

  /// Scatter grass and rocks.
  details,

  /// Size, resolution and rendering of the terrain itself.
  settings,
}

/// What [TerrainTool.paint] does with a stroke: Unity's "Paint Terrain"
/// dropdown.
enum TerrainPaintMode {
  /// Raise the ground, or lower it with Shift held.
  raiseLower,

  /// Blend a surface layer in.
  texture,

  /// Pull the ground toward a chosen height.
  setHeight,

  /// Average a sample against its neighbours.
  smooth,

  /// Press the brush's shape in once per click.
  stamp,

  /// Cut the ground away.
  holes,
}

/// The label the inspector shows for [mode].
String terrainPaintModeLabel(TerrainPaintMode mode) => switch (mode) {
  TerrainPaintMode.raiseLower => 'Raise or Lower Terrain',
  TerrainPaintMode.texture => 'Paint Texture',
  TerrainPaintMode.setHeight => 'Set Height',
  TerrainPaintMode.smooth => 'Smooth Height',
  TerrainPaintMode.stamp => 'Stamp Terrain',
  TerrainPaintMode.holes => 'Paint Holes',
};

/// Whether a stroke in [mode] moves the ground rather than painting onto it.
bool terrainPaintModeSculpts(TerrainPaintMode mode) =>
    mode != TerrainPaintMode.texture;

/// The terrain tools' settings, and which one is armed.
class TerrainToolController extends ChangeNotifier {
  TerrainTool? _tool;
  TerrainPaintMode _paintMode = TerrainPaintMode.raiseLower;
  TerrainBrush _brush = const TerrainBrush();
  int _paintLayer = 1;
  double _targetStrength = 1.0;
  double _stampHeight = 4.0;

  /// The armed tool, or null when the gizmo has the mouse.
  ///
  /// One tool at a time, and choosing one is the only way a brush takes the
  /// left button — the same bargain Unity makes, and the reason a terrain can
  /// still be moved and rotated like any other object.
  TerrainTool? get tool => _tool;
  set tool(TerrainTool? value) {
    if (_tool == value) return;
    _tool = value;
    notifyListeners();
  }

  /// Arms [value], or disarms it when it was already armed.
  ///
  /// Clicking the lit button to put the mouse back is what people try, so it
  /// is what happens.
  void toggle(TerrainTool value) => tool = _tool == value ? null : value;

  /// Whether a brush currently owns the left mouse button.
  bool get active => _tool == TerrainTool.paint;

  /// What a paint stroke does.
  TerrainPaintMode get paintMode => _paintMode;
  set paintMode(TerrainPaintMode value) {
    if (_paintMode == value) return;
    _paintMode = value;
    notifyListeners();
  }

  /// Whether the armed tool moves the ground rather than painting onto it.
  bool get sculpting => active && terrainPaintModeSculpts(_paintMode);

  /// Whether the armed tool paints surface layers.
  bool get painting => active && _paintMode == TerrainPaintMode.texture;

  /// The brush's reach and strength.
  TerrainBrush get brush => _brush;
  set brush(TerrainBrush value) {
    _brush = value;
    notifyListeners();
  }

  /// Which of the four surface layers a texture stroke lays down.
  ///
  /// Layer 0 is what a terrain is before anyone paints it, so this opens on
  /// layer 1: the first stroke of a session almost always adds to the base
  /// rather than repainting it.
  int get paintLayer => _paintLayer;
  set paintLayer(int value) {
    final clamped = value.clamp(0, terrainSplatLayers - 1);
    if (_paintLayer == clamped) return;
    _paintLayer = clamped;
    notifyListeners();
  }

  /// How far a texture stroke takes its layer: 1 covers what it touches, less
  /// leaves the layers underneath showing through however long you hold it.
  double get targetStrength => _targetStrength;
  set targetStrength(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_targetStrength == clamped) return;
    _targetStrength = clamped;
    notifyListeners();
  }

  /// How far one press of [TerrainPaintMode.stamp] lifts the ground.
  double get stampHeight => _stampHeight;
  set stampHeight(double value) {
    if (_stampHeight == value) return;
    _stampHeight = value;
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

  /// The brush size Unity's `[` and `]` step through.
  ///
  /// Multiplicative rather than a fixed step: the useful range spans two
  /// orders of magnitude, and a step that suits a footpath is imperceptible
  /// on a mountainside.
  void nudgeRadius(double factor) =>
      updateBrush(radius: (_brush.radius * factor).clamp(0.25, 200.0));

  /// The opacity Unity's `-` and `=` step through.
  void nudgeStrength(double delta) =>
      updateBrush(strength: (_brush.strength + delta).clamp(0.05, 10.0));

  /// The brush the viewport should apply for the current mode.
  ///
  /// The paint modes are the same brush shape doing different things, so the
  /// kind is derived here rather than being a second thing to keep in step
  /// with the mode. [lower] is Shift held, which Unity uses to dig.
  TerrainBrush strokeBrush({bool lower = false}) => switch (_paintMode) {
    TerrainPaintMode.smooth => TerrainBrush(
      kind: TerrainBrushKind.smooth,
      radius: _brush.radius,
      strength: _brush.strength,
      falloff: _brush.falloff,
    ),
    TerrainPaintMode.setHeight => TerrainBrush(
      kind: TerrainBrushKind.flatten,
      radius: _brush.radius,
      strength: _brush.strength,
      falloff: _brush.falloff,
      targetHeight: _brush.targetHeight,
    ),
    TerrainPaintMode.stamp => TerrainBrush(
      kind: TerrainBrushKind.raise,
      radius: _brush.radius,
      // A stamp is one press, not a rate, so its strength is the height it
      // presses in rather than a speed.
      strength: lower ? -_stampHeight : _stampHeight,
      falloff: _brush.falloff,
    ),
    _ => TerrainBrush(
      kind: TerrainBrushKind.raise,
      radius: _brush.radius,
      strength: lower ? -_brush.strength : _brush.strength,
      falloff: _brush.falloff,
      targetHeight: _brush.targetHeight,
    ),
  };
}
