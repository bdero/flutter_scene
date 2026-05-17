import 'dart:typed_data';

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/geometry/mesh_geometry.dart';

/// An axis-aligned box geometry spanning `-extents/2` to `+extents/2` on
/// each axis.
///
/// Useful as a quick placeholder or for debugging. Each corner carries a
/// distinct vertex color, which can be visualized with an unlit material.
class CuboidGeometry extends MeshGeometry {
  /// Builds a cuboid sized to [extents].
  CuboidGeometry(Vector3 extents)
    : super.fromArrays(
        positions: _positions(extents),
        texCoords: _texCoords,
        colors: _colors,
        indices: _indices,
      );

  static Float32List _positions(Vector3 extents) {
    final e = extents * 0.5;
    return Float32List.fromList(<double>[
      -e.x,
      -e.y,
      -e.z,
      e.x,
      -e.y,
      -e.z,
      e.x,
      e.y,
      -e.z,
      -e.x,
      e.y,
      -e.z,
      -e.x,
      -e.y,
      e.z,
      e.x,
      -e.y,
      e.z,
      e.x,
      e.y,
      e.z,
      -e.x,
      e.y,
      e.z,
    ]);
  }

  static final Float32List _texCoords = Float32List.fromList(<double>[
    0,
    0,
    1,
    0,
    1,
    1,
    0,
    1,
    0,
    0,
    1,
    0,
    1,
    1,
    0,
    1,
  ]);

  static final Float32List _colors = Float32List.fromList(<double>[
    1,
    0,
    0,
    1,
    0,
    1,
    0,
    1,
    0,
    0,
    1,
    1,
    0,
    0,
    0,
    1,
    0,
    1,
    1,
    1,
    1,
    0,
    1,
    1,
    1,
    1,
    0,
    1,
    1,
    1,
    1,
    1,
  ]);

  static const List<int> _indices = <int>[
    0, 1, 3, 3, 1, 2, //
    1, 5, 2, 2, 5, 6, //
    5, 4, 6, 6, 4, 7, //
    4, 0, 7, 7, 0, 3, //
    3, 2, 7, 7, 2, 6, //
    4, 5, 0, 0, 5, 1, //
  ];
}
