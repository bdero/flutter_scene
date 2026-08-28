/// Height-field terrain: a grid of samples lifted into a mesh.
///
/// The height field is kept alongside the mesh rather than thrown away after
/// building it, because everything else that wants terrain wants to *ask* it
/// something: an RTS camera needs the ground height under its focus, a follow
/// camera needs it under the character, and a character controller needs it
/// under its feet. [TerrainGeometry.heightAtWorld] is that question, and it
/// costs a bilinear sample rather than a raycast.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';
import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_scene/src/noise/fast_noise_lite.dart';

/// A grid of height samples covering a [width] by [depth] patch centred on
/// the origin, `columns` by `rows` samples across.
///
/// Sample `(0, 0)` sits at the low-X, low-Z corner. Pure data: the mesh is
/// built from it, and it answers height queries afterwards.
class HeightField {
  /// Creates a field over [heights], which must hold `columns * rows` samples
  /// in row-major order.
  HeightField({
    required this.heights,
    required this.columns,
    required this.rows,
    required this.width,
    required this.depth,
  }) : assert(columns >= 2 && rows >= 2, 'A height field needs a 2x2 grid.'),
       assert(
         heights.length == columns * rows,
         'Expected columns * rows height samples.',
       ),
       assert(width > 0 && depth > 0, 'A height field needs a positive size.');

  /// Builds a field by sampling fractal noise.
  ///
  /// [amplitude] is the peak height above and below zero, [frequency] the
  /// noise scale in world units, and [octaves] how many layers of detail are
  /// summed. The same [seed] always gives the same terrain, which is what
  /// makes a noise terrain something a document can describe in a few numbers
  /// rather than a megabyte of samples.
  factory HeightField.noise({
    required double width,
    required double depth,
    required int columns,
    required int rows,
    double amplitude = 8.0,
    double frequency = 0.02,
    int octaves = 4,
    int seed = 1337,
  }) {
    final noise = FastNoiseLite(seed: seed)
      ..noiseType = NoiseType.openSimplex2
      ..fractalType = FractalType.fbm
      ..octaves = octaves < 1 ? 1 : octaves
      ..frequency = frequency;
    final heights = Float32List(columns * rows);
    for (var r = 0; r < rows; r++) {
      final z = -depth / 2 + depth * r / (rows - 1);
      for (var c = 0; c < columns; c++) {
        final x = -width / 2 + width * c / (columns - 1);
        heights[r * columns + c] = noise.getNoise2(x, z) * amplitude;
      }
    }
    return HeightField(
      heights: heights,
      columns: columns,
      rows: rows,
      width: width,
      depth: depth,
    );
  }

  /// Reads a field from packed 32-bit floats, row-major, as
  /// [PayloadEncoding.floats] stores them.
  ///
  /// Returns null when the byte count does not match `columns * rows`, since
  /// a truncated heightmap would otherwise be read as a cliff.
  static HeightField? fromBytes(
    Uint8List bytes, {
    required int columns,
    required int rows,
    required double width,
    required double depth,
  }) {
    if (columns < 2 || rows < 2) return null;
    if (bytes.lengthInBytes != columns * rows * 4) return null;
    // A copy, not a view: the payload's buffer may be shared, and sculpting
    // mutates these samples in place.
    final heights = Float32List(columns * rows);
    heights.setAll(
      0,
      bytes.buffer.asFloat32List(bytes.offsetInBytes, columns * rows),
    );
    return HeightField(
      heights: heights,
      columns: columns,
      rows: rows,
      width: width,
      depth: depth,
    );
  }

  /// The samples as packed 32-bit floats, for a document payload.
  Uint8List toBytes() => Uint8List.view(
    heights.buffer,
    heights.offsetInBytes,
    heights.lengthInBytes,
  );

  /// The samples, row-major, `columns * rows` of them.
  final Float32List heights;

  /// Samples across X.
  final int columns;

  /// Samples across Z.
  final int rows;

  /// World size across X.
  final double width;

  /// World size across Z.
  final double depth;

  /// The height sample at column [c], row [r], clamped to the edge so a
  /// query just off the patch reads the border rather than wrapping to the
  /// far side.
  double sample(int c, int r) =>
      heights[r.clamp(0, rows - 1) * columns + c.clamp(0, columns - 1)];

  /// The interpolated height at world position ([x], [z]).
  ///
  /// Positions outside the patch clamp to its edge, so a character walking
  /// off the end walks level rather than falling through.
  double heightAtWorld(double x, double z) {
    final u = ((x + width / 2) / width) * (columns - 1);
    final v = ((z + depth / 2) / depth) * (rows - 1);
    final c = u.floor();
    final r = v.floor();
    final fu = (u - c).clamp(0.0, 1.0);
    final fv = (v - r).clamp(0.0, 1.0);
    final h00 = sample(c, r);
    final h10 = sample(c + 1, r);
    final h01 = sample(c, r + 1);
    final h11 = sample(c + 1, r + 1);
    return _mix(_mix(h00, h10, fu), _mix(h01, h11, fu), fv);
  }

  /// Where a ray from [origin] along [direction] first meets the ground, or
  /// null when it never does within [maxDistance].
  ///
  /// Marches the ray comparing its height against the field's, then bisects
  /// the step that crossed. Against the mesh this would be a triangle
  /// raycast; against the field it is a handful of samples, it needs no mesh
  /// to exist yet, and it stays exact as the ground is sculpted under it.
  ///
  /// The march step is half a cell, so a ray cannot pass through a ridge
  /// thinner than the grid can represent in the first place.
  Vector3? raycast(
    Vector3 origin,
    Vector3 direction, {
    double maxDistance = 1000.0,
    int refinements = 24,
  }) {
    final ray = direction.normalized();
    final step = math.min(width / (columns - 1), depth / (rows - 1)) * 0.5;
    if (step <= 0) return null;

    double above(double t) {
      final p = origin + ray * t;
      return p.y - heightAtWorld(p.x, p.z);
    }

    var previousT = 0.0;
    var previousAbove = above(0);
    // A ray that starts underground has already "hit"; report where it
    // entered rather than hunting forward for a crossing that is behind it.
    if (previousAbove <= 0) return origin.clone();

    for (var t = step; t <= maxDistance; t += step) {
      final current = above(t);
      if (current <= 0) {
        // Bisect the crossing step. The surface is piecewise bilinear, so a
        // fixed number of halvings lands well inside a pixel.
        var low = previousT;
        var high = t;
        for (var i = 0; i < refinements; i++) {
          final mid = (low + high) * 0.5;
          if (above(mid) > 0) {
            low = mid;
          } else {
            high = mid;
          }
        }
        return origin + ray * ((low + high) * 0.5);
      }
      previousT = t;
      previousAbove = current;
    }
    return null;
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;
}

/// The vertex arrays for [field], a plane displaced by its samples.
///
/// Normals come from the height field by central difference rather than from
/// the triangles, so neighbouring quads agree along their shared edge and the
/// surface shades smoothly instead of faceting.
PrimitiveArrays buildTerrainArrays(HeightField field) {
  final columns = field.columns;
  final rows = field.rows;
  final vertexCount = columns * rows;
  final positions = Float32List(vertexCount * 3);
  final normals = Float32List(vertexCount * 3);
  final texCoords = Float32List(vertexCount * 2);

  final stepX = field.width / (columns - 1);
  final stepZ = field.depth / (rows - 1);

  for (var r = 0; r < rows; r++) {
    final z = -field.depth / 2 + stepZ * r;
    for (var c = 0; c < columns; c++) {
      final x = -field.width / 2 + stepX * c;
      final v = r * columns + c;
      positions[v * 3] = x;
      positions[v * 3 + 1] = field.sample(c, r);
      positions[v * 3 + 2] = z;

      // Central difference over the two neighbours on each axis; the clamp in
      // sample() makes the border one-sided instead of out of range.
      final dx =
          (field.sample(c + 1, r) - field.sample(c - 1, r)) / (2 * stepX);
      final dz =
          (field.sample(c, r + 1) - field.sample(c, r - 1)) / (2 * stepZ);
      final length = math.sqrt(dx * dx + 1.0 + dz * dz);
      normals[v * 3] = -dx / length;
      normals[v * 3 + 1] = 1.0 / length;
      normals[v * 3 + 2] = -dz / length;

      texCoords[v * 2] = c / (columns - 1);
      texCoords[v * 2 + 1] = r / (rows - 1);
    }
  }

  final indices = <int>[];
  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < columns - 1; c++) {
      final v00 = r * columns + c;
      final v10 = v00 + 1;
      final v01 = v00 + columns;
      final v11 = v01 + 1;
      // Counter-clockwise, so the lit surface faces up like a plane's.
      indices
        ..addAll([v00, v01, v10])
        ..addAll([v10, v01, v11]);
    }
  }

  return (
    positions: positions,
    normals: normals,
    texCoords: texCoords,
    colors: null,
    indices: indices,
  );
}

/// A height-field terrain mesh.
///
/// Keeps its [field], so the same object that draws the ground can also be
/// asked how high it is — see [heightAtWorld].
/// {@category Geometry}
class TerrainGeometry extends MeshGeometry {
  /// Builds a terrain mesh over [field].
  factory TerrainGeometry(HeightField field) =>
      TerrainGeometry._(field, buildTerrainArrays(field));

  /// Builds a noise terrain, the form a document can describe in a few
  /// numbers.
  factory TerrainGeometry.noise({
    double width = 64.0,
    double depth = 64.0,
    int columns = 65,
    int rows = 65,
    double amplitude = 8.0,
    double frequency = 0.02,
    int octaves = 4,
    int seed = 1337,
  }) => TerrainGeometry(
    HeightField.noise(
      width: width,
      depth: depth,
      columns: columns,
      rows: rows,
      amplitude: amplitude,
      frequency: frequency,
      octaves: octaves,
      seed: seed,
    ),
  );

  TerrainGeometry._(this.field, PrimitiveArrays arrays)
    : super.fromArrays(
        positions: arrays.positions,
        normals: arrays.normals,
        texCoords: arrays.texCoords,
        colors: arrays.colors,
        indices: arrays.indices,
      );

  /// The samples this mesh was built from.
  final HeightField field;

  /// The ground height at world ([x], [z]), for a camera or a character that
  /// needs to sit on the surface. Delegates to [HeightField.heightAtWorld].
  double heightAtWorld(double x, double z) => field.heightAtWorld(x, z);
}
