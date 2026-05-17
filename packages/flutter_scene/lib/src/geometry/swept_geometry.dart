import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/scene_path.dart';

/// Vertex attribute arrays produced by a swept-geometry generator.
typedef SweptArrays =
    ({
      Float32List positions,
      Float32List normals,
      Float32List texCoords,
      List<int> indices,
    });

/// How a [RibbonGeometry] orients its strip across the path.
enum RibbonAlignment {
  /// The strip stays horizontal, its width running perpendicular to the
  /// path as seen from above. Suited to a route drawn on the ground.
  ground,

  /// The strip lies in the path's own frame and rolls with it.
  path,
}

/// A flat strip of constant width swept along a [ScenePath].
///
/// Useful for a route ribbon or a painted lane marking. The result is an
/// ordinary triangle mesh that works with any material; texture
/// coordinates run `0..1` across the width and by arc-length distance
/// along the path.
class RibbonGeometry extends MeshGeometry {
  /// Sweeps a ribbon of the given [width] along [path].
  ///
  /// [stations] is the number of cross-sections sampled along the path.
  /// [up] is the reference up direction for [RibbonAlignment.ground]
  /// (default `+Y`). Pass [GeometryStorage.updatable] to allow
  /// [updatePath].
  factory RibbonGeometry(
    ScenePath path, {
    double width = 1.0,
    int stations = 64,
    RibbonAlignment alignment = RibbonAlignment.ground,
    Vector3? up,
    GeometryStorage storage = GeometryStorage.fixed,
  }) {
    final resolvedUp = up ?? Vector3(0.0, 1.0, 0.0);
    return RibbonGeometry._(
      width,
      stations,
      alignment,
      resolvedUp,
      buildRibbonArrays(
        path,
        width: width,
        stations: stations,
        alignment: alignment,
        up: resolvedUp,
      ),
      storage,
    );
  }

  RibbonGeometry._(
    this._width,
    this._stations,
    this._alignment,
    this._up,
    SweptArrays arrays,
    GeometryStorage storage,
  ) : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
        storage: storage,
      );

  final double _width;
  final int _stations;
  final RibbonAlignment _alignment;
  final Vector3 _up;

  /// Re-sweeps the ribbon along [path], reusing the GPU buffers.
  ///
  /// The width, station count, and alignment are unchanged, so the
  /// topology is stable. Requires [GeometryStorage.updatable].
  void updatePath(ScenePath path) {
    final arrays = buildRibbonArrays(
      path,
      width: _width,
      stations: _stations,
      alignment: _alignment,
      up: _up,
    );
    updatePositions(arrays.positions);
    updateNormals(arrays.normals);
    updateTexCoords(arrays.texCoords);
  }
}

/// Generates the vertex arrays for a [RibbonGeometry].
SweptArrays buildRibbonArrays(
  ScenePath path, {
  required double width,
  required int stations,
  required RibbonAlignment alignment,
  required Vector3 up,
}) {
  if (stations < 2) {
    throw ArgumentError.value(stations, 'stations', 'must be at least two');
  }
  final frames = evenlySpacedFrames(path, stations);
  final length = path.length;
  final half = width / 2.0;
  final accumulator = MeshAccumulator();
  final ringBases = <int>[];

  for (var i = 0; i < stations; i++) {
    final frame = frames[i];
    final Vector3 across;
    final Vector3 normal;
    if (alignment == RibbonAlignment.ground) {
      var sideways = up.cross(frame.tangent);
      if (sideways.length2 < 1e-12) sideways = frame.binormal;
      across = sideways.normalized();
      normal = up.normalized();
    } else {
      across = frame.binormal;
      normal = frame.normal;
    }
    final v = stations == 1 ? 0.0 : length * i / (stations - 1);
    ringBases.add(accumulator.vertexCount);
    accumulator.addVertex(frame.position - across * half, normal, 0.0, v);
    accumulator.addVertex(frame.position + across * half, normal, 1.0, v);
  }

  stitchRings(accumulator, ringBases, 2);
  return accumulator.toArrays();
}

/// Samples [stations] rotation-minimizing frames along [path], spaced by
/// equal arc length.
List<ScenePathFrame> evenlySpacedFrames(ScenePath path, int stations) {
  final length = path.length;
  return <ScenePathFrame>[
    for (var i = 0; i < stations; i++)
      path.frameAtDistance(stations == 1 ? 0.0 : length * i / (stations - 1)),
  ];
}

/// Connects consecutive cross-section rings into a triangle strip.
///
/// Each ring has [ringSize] vertices; [ringBases] holds the index of the
/// first vertex of each ring. Vertex `j` of one ring joins vertex `j` of
/// the next, for `j` in `0..ringSize - 2`.
void stitchRings(
  MeshAccumulator accumulator,
  List<int> ringBases,
  int ringSize,
) {
  for (var s = 0; s < ringBases.length - 1; s++) {
    final base = ringBases[s];
    final nextBase = ringBases[s + 1];
    for (var j = 0; j < ringSize - 1; j++) {
      final a = base + j;
      final b = base + j + 1;
      final c = nextBase + j;
      final d = nextBase + j + 1;
      accumulator
        ..addTriangle(a, c, b)
        ..addTriangle(b, c, d);
    }
  }
}

/// A growable builder of interleaved-ready vertex attribute arrays.
///
/// Used by the swept-geometry generators to collect positions, normals,
/// texture coordinates, and triangle indices before producing a
/// [SweptArrays] record.
class MeshAccumulator {
  final List<double> _positions = [];
  final List<double> _normals = [];
  final List<double> _texCoords = [];
  final List<int> _indices = [];

  /// The number of vertices added so far.
  int get vertexCount => _positions.length ~/ 3;

  /// Appends a vertex and returns its index.
  int addVertex(Vector3 position, Vector3 normal, double u, double v) {
    final index = vertexCount;
    _positions
      ..add(position.x)
      ..add(position.y)
      ..add(position.z);
    _normals
      ..add(normal.x)
      ..add(normal.y)
      ..add(normal.z);
    _texCoords
      ..add(u)
      ..add(v);
    return index;
  }

  /// Appends a triangle referencing three vertex indices.
  void addTriangle(int a, int b, int c) {
    _indices
      ..add(a)
      ..add(b)
      ..add(c);
  }

  /// Produces the finished attribute arrays.
  SweptArrays toArrays() => (
    positions: Float32List.fromList(_positions),
    normals: Float32List.fromList(_normals),
    texCoords: Float32List.fromList(_texCoords),
    indices: _indices,
  );
}
