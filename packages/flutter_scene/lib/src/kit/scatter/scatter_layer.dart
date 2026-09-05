/// Scattering instances across a surface: the trees, rocks and grass painted
/// onto ground.
///
/// A layer draws one geometry many times as a single instanced batch, and
/// keeps the placements so they can be saved, removed and re-drawn. Placement
/// itself is a pure function over a brush, so where things land is testable
/// without a scene.
library;

import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/instanced_mesh.dart';
import 'package:flutter_scene/src/material/material.dart';

/// One scattered instance.
/// {@category Scene graph}
class ScatterPlacement {
  /// Creates a placement.
  const ScatterPlacement({
    required this.position,
    this.yaw = 0.0,
    this.scale = 1.0,
  });

  /// Where it stands, in the layer's node space.
  final Vector3 position;

  /// Its turn about the vertical axis, in radians.
  final double yaw;

  /// A uniform scale, so a scattered set does not look stamped.
  final double scale;

  /// This placement's transform.
  Matrix4 toMatrix() => Matrix4.compose(
    position,
    Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), yaw),
    Vector3.all(scale),
  );
}

/// How a scatter brush places things.
/// {@category Scene graph}
class ScatterBrush {
  /// Creates a scatter brush.
  const ScatterBrush({
    this.radius = 4.0,
    this.density = 8.0,
    this.minSpacing = 1.0,
    this.minScale = 0.8,
    this.maxScale = 1.2,
    this.alignToGround = true,
  });

  /// How far the brush reaches, in world units.
  final double radius;

  /// Attempted placements per second of stroke.
  final double density;

  /// How close two instances may stand. Zero lets them overlap.
  final double minSpacing;

  /// The smallest random scale.
  final double minScale;

  /// The largest random scale.
  final double maxScale;

  /// Whether a placement takes the ground height under it.
  final bool alignToGround;
}

/// Places up to [attempts] instances inside [brush] around ([x], [z]).
///
/// Rejects a candidate that lands closer than the brush's spacing to
/// something already placed, so a stroke thickens toward a limit rather than
/// piling instances on one spot — painting over the same ground twice should
/// not double the trees standing on it.
///
/// [heightAt] supplies the ground; [random] makes a stroke reproducible in a
/// test.
/// {@category Scene graph}
List<ScatterPlacement> scatterInBrush({
  required ScatterBrush brush,
  required double x,
  required double z,
  required int attempts,
  required Iterable<ScatterPlacement> existing,
  double Function(double x, double z)? heightAt,
  math.Random? random,
}) {
  if (brush.radius <= 0 || attempts <= 0) return const [];
  final rng = random ?? math.Random();
  final placed = <ScatterPlacement>[];
  final spacingSq = brush.minSpacing * brush.minSpacing;

  bool tooClose(double px, double pz) {
    if (spacingSq <= 0) return false;
    for (final other in existing) {
      final dx = other.position.x - px;
      final dz = other.position.z - pz;
      if (dx * dx + dz * dz < spacingSq) return true;
    }
    for (final other in placed) {
      final dx = other.position.x - px;
      final dz = other.position.z - pz;
      if (dx * dx + dz * dz < spacingSq) return true;
    }
    return false;
  }

  for (var i = 0; i < attempts; i++) {
    // Square-rooted radius, or a uniform pick clusters toward the centre.
    final distance = brush.radius * math.sqrt(rng.nextDouble());
    final angle = rng.nextDouble() * 2 * math.pi;
    final px = x + math.cos(angle) * distance;
    final pz = z + math.sin(angle) * distance;
    if (tooClose(px, pz)) continue;
    final py = brush.alignToGround ? (heightAt?.call(px, pz) ?? 0.0) : 0.0;
    placed.add(
      ScatterPlacement(
        position: Vector3(px, py, pz),
        yaw: rng.nextDouble() * 2 * math.pi,
        scale:
            brush.minScale +
            rng.nextDouble() * (brush.maxScale - brush.minScale),
      ),
    );
  }
  return placed;
}

/// Draws a set of [ScatterPlacement]s as one instanced batch.
///
/// The placements are kept alongside the batch rather than only as matrices,
/// because a matrix cannot be asked where its instance stands without being
/// decomposed, and erasing needs exactly that question answered for every
/// instance under the brush.
/// {@category Scene graph}
class ScatterLayer extends Component {
  /// Creates a layer drawing [geometry] shaded by [material].
  ScatterLayer({
    required Geometry geometry,
    required Material material,
    bool cullInstances = true,
  }) : _mesh = InstancedMesh(
         geometry: geometry,
         material: material,
         cullInstances: cullInstances,
       );

  final InstancedMesh _mesh;
  final List<ScatterPlacement> _placements = [];
  InstancedMeshComponent? _drawer;

  /// The instanced mesh behind this layer.
  InstancedMesh get mesh => _mesh;

  /// Every placement, in the order they were added.
  List<ScatterPlacement> get placements => List.unmodifiable(_placements);

  /// How many instances are placed.
  int get length => _placements.length;

  /// Whether the layer is empty.
  bool get isEmpty => _placements.isEmpty;

  /// Adds [placement] to the batch.
  void add(ScatterPlacement placement) {
    _placements.add(placement);
    _mesh.addInstance(placement.toMatrix());
  }

  /// Adds every placement in [placements].
  void addAll(Iterable<ScatterPlacement> placements) {
    for (final placement in placements) {
      add(placement);
    }
  }

  /// Removes every instance whose base is within [radius] of ([x], [z]),
  /// ignoring height so the eraser works on a slope.
  ///
  /// Returns how many went.
  int removeWithin(double x, double z, double radius) {
    if (radius <= 0) return 0;
    final radiusSq = radius * radius;
    var removed = 0;
    // Backwards, so a swap-remove never moves an entry the loop has yet to
    // reach into a slot it has already passed.
    for (var i = _placements.length - 1; i >= 0; i--) {
      final position = _placements[i].position;
      final dx = position.x - x;
      final dz = position.z - z;
      if (dx * dx + dz * dz > radiusSq) continue;
      _placements.removeAt(i);
      _mesh.removeInstanceAt(i);
      removed++;
    }
    return removed;
  }

  /// Removes every instance.
  void clear() {
    _placements.clear();
    _mesh.clearInstances();
  }

  @override
  void onAttach() {
    _drawer = InstancedMeshComponent(_mesh);
    node.addComponent(_drawer!);
  }

  @override
  void onDetach() {
    final drawer = _drawer;
    if (drawer != null) {
      node.removeComponent(drawer);
      _drawer = null;
    }
  }
}
