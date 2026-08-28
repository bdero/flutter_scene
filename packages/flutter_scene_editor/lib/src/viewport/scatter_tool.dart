/// The viewport's object-painting tool: scattering instances onto a surface
/// and rubbing them out again.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// What a scatter stroke does.
enum ScatterAction {
  /// Places instances under the brush.
  paint,

  /// Removes the instances under it.
  erase,
}

/// The painting tool's settings.
///
/// Kept apart from the viewport so the palette and the stroke read the same
/// brush, and so settings survive a viewport closing.
class ScatterToolController extends ChangeNotifier {
  bool _active = false;
  ScatterAction _action = ScatterAction.paint;
  ScatterBrush _brush = const ScatterBrush();

  /// Whether the tool takes the primary button.
  bool get active => _active;
  set active(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  /// Whether a stroke places or removes.
  ScatterAction get action => _action;
  set action(ScatterAction value) {
    if (_action == value) return;
    _action = value;
    notifyListeners();
  }

  /// How instances are placed.
  ScatterBrush get brush => _brush;
  set brush(ScatterBrush value) {
    _brush = value;
    notifyListeners();
  }

  /// Replaces one part of the brush, leaving the rest.
  void updateBrush({
    double? radius,
    double? density,
    double? minSpacing,
    double? minScale,
    double? maxScale,
    bool? alignToGround,
  }) {
    brush = ScatterBrush(
      radius: radius ?? _brush.radius,
      density: density ?? _brush.density,
      minSpacing: minSpacing ?? _brush.minSpacing,
      minScale: minScale ?? _brush.minScale,
      maxScale: maxScale ?? _brush.maxScale,
      alignToGround: alignToGround ?? _brush.alignToGround,
    );
  }
}

/// One painting stroke, from pointer down to pointer up.
///
/// Edits the live layer so instances appear as the pointer moves, and reports
/// the finished set once at the end — a stroke is one undo step, the same way
/// a sculpting stroke is.
class ScatterStroke {
  /// Begins a stroke on [layer], attached to the node [nodeId].
  ScatterStroke({required this.layer, required this.nodeId});

  /// The live layer being painted.
  final ScatterLayer layer;

  /// The node carrying it, for writing the placements back.
  final Object nodeId;

  final math.Random _random = math.Random();
  bool _changed = false;

  /// Whether anything was placed or removed. A stroke that did nothing is not
  /// worth an undo entry.
  bool get changed => _changed;

  /// Places or removes at world [point].
  ///
  /// [deltaSeconds] turns the brush's density into a number of attempts, so a
  /// slow drag lays down as much as a fast one over the same ground rather
  /// than however many frames happened to fire.
  void dab(
    ScatterBrush brush,
    ScatterAction action,
    vm.Vector3 point,
    double deltaSeconds, {
    double Function(double x, double z)? heightAt,
  }) {
    if (action == ScatterAction.erase) {
      final removed = layer.removeWithin(point.x, point.z, brush.radius);
      if (removed > 0) _changed = true;
      return;
    }

    final attempts = (brush.density * deltaSeconds).round();
    if (attempts <= 0) return;
    final placed = scatterInBrush(
      brush: brush,
      x: point.x,
      z: point.z,
      attempts: attempts,
      existing: layer.placements,
      heightAt: heightAt,
      random: _random,
    );
    if (placed.isEmpty) return;
    layer.addAll(placed);
    _changed = true;
  }

  /// The finished placements, as the component property takes them.
  List<Object?> encodedPlacements() => [
    for (final placement in layer.placements)
      <String, Object?>{
        'position': [
          placement.position.x,
          placement.position.y,
          placement.position.z,
        ],
        if (placement.yaw != 0) 'yaw': placement.yaw,
        if (placement.scale != 1) 'scale': placement.scale,
      },
  ];
}

/// The scatter layer on [node], or null when it has none.
ScatterLayer? scatterLayerOf(Node? node) => node?.getComponent<ScatterLayer>();
