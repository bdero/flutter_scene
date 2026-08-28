/// The viewport's terrain sculpting tool: what the brush is set to, and the
/// stroke in progress.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    geometry.rebuildFromField();
  }

  /// The finished samples, as the command takes them.
  String encodedHeights() => base64Encode(geometry.field.toBytes());
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
