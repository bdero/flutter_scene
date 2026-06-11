import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/scene_path.dart';

/// Vertex attribute arrays produced by a swept-geometry generator.
typedef SweptArrays = ({
  Float32List positions,
  Float32List normals,
  Float32List texCoords,
  List<int> indices,
});

/// How a [RibbonGeometry] orients its strip across the path.
/// {@category Geometry}
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
/// {@category Geometry}
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
      // tangent cross up (not up cross tangent) so the strip is wound
      // with its lit surface facing up, like the path-aligned branch.
      var sideways = frame.tangent.cross(up);
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

/// A round cross-section of constant radius swept along a [ScenePath].
///
/// Useful for a 3D route tube or pipe. Texture coordinates run `0..1`
/// around the circumference and by arc-length distance along the path.
/// {@category Geometry}
class TubeGeometry extends MeshGeometry {
  /// Sweeps a tube of the given [radius] along [path].
  ///
  /// [radialSegments] sets how many faces wrap the circumference and
  /// [stations] how many cross-sections run along the path. With [caps]
  /// the two ends are closed by a disk. Pass [GeometryStorage.updatable]
  /// to allow [updatePath].
  factory TubeGeometry(
    ScenePath path, {
    double radius = 0.5,
    int radialSegments = 12,
    int stations = 64,
    bool caps = true,
    GeometryStorage storage = GeometryStorage.fixed,
  }) {
    return TubeGeometry._(
      radius,
      radialSegments,
      stations,
      caps,
      buildTubeArrays(
        path,
        radius: radius,
        radialSegments: radialSegments,
        stations: stations,
        caps: caps,
      ),
      storage,
    );
  }

  TubeGeometry._(
    this._radius,
    this._radialSegments,
    this._stations,
    this._caps,
    SweptArrays arrays,
    GeometryStorage storage,
  ) : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
        storage: storage,
      );

  final double _radius;
  final int _radialSegments;
  final int _stations;
  final bool _caps;

  /// Re-sweeps the tube along [path], reusing the GPU buffers.
  ///
  /// The radius, tessellation, and caps are unchanged, so the topology
  /// is stable. Requires [GeometryStorage.updatable].
  void updatePath(ScenePath path) {
    final arrays = buildTubeArrays(
      path,
      radius: _radius,
      radialSegments: _radialSegments,
      stations: _stations,
      caps: _caps,
    );
    updatePositions(arrays.positions);
    updateNormals(arrays.normals);
    updateTexCoords(arrays.texCoords);
  }
}

/// Generates the vertex arrays for a [TubeGeometry].
SweptArrays buildTubeArrays(
  ScenePath path, {
  required double radius,
  required int radialSegments,
  required int stations,
  required bool caps,
}) {
  if (stations < 2) {
    throw ArgumentError.value(stations, 'stations', 'must be at least two');
  }
  if (radialSegments < 3) {
    throw ArgumentError.value(
      radialSegments,
      'radialSegments',
      'must be at least three',
    );
  }
  final frames = evenlySpacedFrames(path, stations);
  final length = path.length;
  final accumulator = MeshAccumulator();
  final ringBases = <int>[];

  for (var i = 0; i < stations; i++) {
    final frame = frames[i];
    final v = length * i / (stations - 1);
    ringBases.add(accumulator.vertexCount);
    // One extra vertex closes the loop so the texture seam is clean.
    for (var k = 0; k <= radialSegments; k++) {
      final theta = 2 * math.pi * k / radialSegments;
      final radial =
          frame.normal * math.cos(theta) + frame.binormal * math.sin(theta);
      accumulator.addVertex(
        frame.position + radial * radius,
        radial,
        k / radialSegments,
        v,
      );
    }
  }

  stitchRings(accumulator, ringBases, radialSegments + 1);

  if (caps) {
    _addDiskCap(
      accumulator,
      frames.first,
      radius,
      radialSegments,
      atEnd: false,
    );
    _addDiskCap(accumulator, frames.last, radius, radialSegments, atEnd: true);
  }
  return accumulator.toArrays();
}

// Closes one end of a tube with a fan of triangles.
void _addDiskCap(
  MeshAccumulator accumulator,
  ScenePathFrame frame,
  double radius,
  int radialSegments, {
  required bool atEnd,
}) {
  final ringPositions = <Vector3>[];
  final ringTexCoords = <Vector2>[];
  for (var k = 0; k < radialSegments; k++) {
    final theta = 2 * math.pi * k / radialSegments;
    final radial =
        frame.normal * math.cos(theta) + frame.binormal * math.sin(theta);
    ringPositions.add(frame.position + radial * radius);
    ringTexCoords.add(
      Vector2(0.5 + 0.5 * math.cos(theta), 0.5 + 0.5 * math.sin(theta)),
    );
  }
  addFanCap(
    accumulator,
    center: frame.position,
    normal: atEnd ? frame.tangent : -frame.tangent,
    ringPositions: ringPositions,
    ringTexCoords: ringTexCoords,
    centerTexCoord: Vector2(0.5, 0.5),
    reverseWinding: !atEnd,
  );
}

/// Adds a triangle fan that closes a cross-section ring.
///
/// The fan runs from [center] to each vertex of [ringPositions], which
/// must be ordered around the ring. Every vertex takes the cap [normal].
void addFanCap(
  MeshAccumulator accumulator, {
  required Vector3 center,
  required Vector3 normal,
  required List<Vector3> ringPositions,
  required List<Vector2> ringTexCoords,
  required Vector2 centerTexCoord,
  required bool reverseWinding,
}) {
  final count = ringPositions.length;
  final centerIndex = accumulator.addVertex(
    center,
    normal,
    centerTexCoord.x,
    centerTexCoord.y,
  );
  final ringIndices = <int>[
    for (var k = 0; k < count; k++)
      accumulator.addVertex(
        ringPositions[k],
        normal,
        ringTexCoords[k].x,
        ringTexCoords[k].y,
      ),
  ];
  for (var k = 0; k < count; k++) {
    final next = (k + 1) % count;
    if (reverseWinding) {
      accumulator.addTriangle(centerIndex, ringIndices[next], ringIndices[k]);
    } else {
      accumulator.addTriangle(centerIndex, ringIndices[k], ringIndices[next]);
    }
  }
}

/// An arbitrary closed 2D profile swept along a [ScenePath].
///
/// The profile is a closed polygon in the path's cross-section plane.
/// Texture coordinates run `0..1` around the profile and by arc-length
/// distance along the path. End caps assume a convex profile.
/// {@category Geometry}
class ExtrudeGeometry extends MeshGeometry {
  /// Sweeps [profile] along [path].
  ///
  /// [profile] is a closed polygon of at least three points, in the
  /// path's normal/binormal plane. [stations] is the number of
  /// cross-sections along the path. With [caps] the two ends are
  /// closed. Pass [GeometryStorage.updatable] to allow [updatePath].
  factory ExtrudeGeometry(
    ScenePath path, {
    required List<Vector2> profile,
    int stations = 64,
    bool caps = true,
    GeometryStorage storage = GeometryStorage.fixed,
  }) {
    final copied = <Vector2>[for (final p in profile) p.clone()];
    return ExtrudeGeometry._(
      copied,
      stations,
      caps,
      buildExtrudeArrays(path, profile: copied, stations: stations, caps: caps),
      storage,
    );
  }

  ExtrudeGeometry._(
    this._profile,
    this._stations,
    this._caps,
    SweptArrays arrays,
    GeometryStorage storage,
  ) : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        indices: arrays.indices,
        storage: storage,
      );

  final List<Vector2> _profile;
  final int _stations;
  final bool _caps;

  /// Re-sweeps the profile along [path], reusing the GPU buffers.
  ///
  /// The profile, station count, and caps are unchanged, so the
  /// topology is stable. Requires [GeometryStorage.updatable].
  void updatePath(ScenePath path) {
    final arrays = buildExtrudeArrays(
      path,
      profile: _profile,
      stations: _stations,
      caps: _caps,
    );
    updatePositions(arrays.positions);
    updateNormals(arrays.normals);
    updateTexCoords(arrays.texCoords);
  }
}

/// Generates the vertex arrays for an [ExtrudeGeometry].
SweptArrays buildExtrudeArrays(
  ScenePath path, {
  required List<Vector2> profile,
  required int stations,
  required bool caps,
}) {
  if (stations < 2) {
    throw ArgumentError.value(stations, 'stations', 'must be at least two');
  }
  if (profile.length < 3) {
    throw ArgumentError.value(
      profile.length,
      'profile',
      'needs at least three points',
    );
  }
  final frames = evenlySpacedFrames(path, stations);
  final length = path.length;
  final pointCount = profile.length;
  final profileNormals = _profileNormals(profile);
  final accumulator = MeshAccumulator();
  final ringBases = <int>[];

  for (var i = 0; i < stations; i++) {
    final frame = frames[i];
    final v = length * i / (stations - 1);
    ringBases.add(accumulator.vertexCount);
    // One extra vertex closes the loop so the texture seam is clean.
    for (var k = 0; k <= pointCount; k++) {
      final point = profile[k % pointCount];
      final profileNormal = profileNormals[k % pointCount];
      final position =
          frame.position + frame.normal * point.x + frame.binormal * point.y;
      final normal =
          (frame.normal * profileNormal.x + frame.binormal * profileNormal.y)
              .normalized();
      accumulator.addVertex(position, normal, k / pointCount, v);
    }
  }

  stitchRings(accumulator, ringBases, pointCount + 1);

  if (caps) {
    _addProfileCap(accumulator, frames.first, profile, atEnd: false);
    _addProfileCap(accumulator, frames.last, profile, atEnd: true);
  }
  return accumulator.toArrays();
}

// Closes one end of an extrusion with a fan over the profile.
void _addProfileCap(
  MeshAccumulator accumulator,
  ScenePathFrame frame,
  List<Vector2> profile, {
  required bool atEnd,
}) {
  var centerX = 0.0;
  var centerY = 0.0;
  for (final point in profile) {
    centerX += point.x;
    centerY += point.y;
  }
  centerX /= profile.length;
  centerY /= profile.length;

  Vector3 lift(double x, double y) =>
      frame.position + frame.normal * x + frame.binormal * y;

  addFanCap(
    accumulator,
    center: lift(centerX, centerY),
    normal: atEnd ? frame.tangent : -frame.tangent,
    ringPositions: <Vector3>[
      for (final point in profile) lift(point.x, point.y),
    ],
    ringTexCoords: <Vector2>[
      for (final point in profile) Vector2(point.x, point.y),
    ],
    centerTexCoord: Vector2(centerX, centerY),
    reverseWinding: !atEnd,
  );
}

// Per-vertex outward 2D normals for a closed profile. The polygon's
// signed area picks the outward direction, so either winding works.
List<Vector2> _profileNormals(List<Vector2> profile) {
  final count = profile.length;
  var doubledArea = 0.0;
  for (var k = 0; k < count; k++) {
    final a = profile[k];
    final b = profile[(k + 1) % count];
    doubledArea += a.x * b.y - b.x * a.y;
  }
  final sign = doubledArea >= 0.0 ? 1.0 : -1.0;

  Vector2 edgeNormal(Vector2 edge) => Vector2(edge.y, -edge.x) * sign;

  return <Vector2>[
    for (var k = 0; k < count; k++)
      () {
        final previous = profile[(k - 1 + count) % count];
        final current = profile[k];
        final next = profile[(k + 1) % count];
        var normal =
            edgeNormal(current - previous) + edgeNormal(next - current);
        if (normal.length2 < 1e-12) normal = edgeNormal(next - current);
        if (normal.length2 < 1e-12) normal = Vector2(1.0, 0.0);
        return normal.normalized();
      }(),
  ];
}
