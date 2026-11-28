// A primitive's texture reads unmirrored from outside: seen from the front,
// u runs to the right and v (0 at the top of the image) runs down.

import 'package:flutter_scene/src/geometry/primitives.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// Counts front-facing triangles whose texture is mirrored and unmirrored. A
// counter-clockwise triangle reads unmirrored when its UVs wind clockwise in
// (u, v), since v runs down the image.
({int mirrored, int unmirrored}) _orientation(
  PrimitiveArrays arrays, {
  bool skipSeam = false,
}) {
  final p = arrays.positions;
  final t = arrays.texCoords!;
  var mirrored = 0, unmirrored = 0;
  final idx = arrays.indices;
  for (var i = 0; i + 2 < idx.length; i += 3) {
    final a = idx[i], b = idx[i + 1], c = idx[i + 2];
    final e1 = Vector3(
      p[b * 3] - p[a * 3],
      p[b * 3 + 1] - p[a * 3 + 1],
      p[b * 3 + 2] - p[a * 3 + 2],
    );
    final e2 = Vector3(
      p[c * 3] - p[a * 3],
      p[c * 3 + 1] - p[a * 3 + 1],
      p[c * 3 + 2] - p[a * 3 + 2],
    );
    if (e1.cross(e2).length2 < 1e-12) continue;
    final du1 = t[b * 2] - t[a * 2], dv1 = t[b * 2 + 1] - t[a * 2 + 1];
    final du2 = t[c * 2] - t[a * 2], dv2 = t[c * 2 + 1] - t[a * 2 + 1];
    // A triangle across a wrapping seam spans most of the texture.
    if (skipSeam &&
        (du1.abs() > 0.5 || du2.abs() > 0.5 || (du1 - du2).abs() > 0.5)) {
      continue;
    }
    final det = du1 * dv2 - du2 * dv1;
    if (det.abs() < 1e-9) continue;
    if (det < 0) {
      unmirrored++;
    } else {
      mirrored++;
    }
  }
  return (mirrored: mirrored, unmirrored: unmirrored);
}

void main() {
  final primitives = <String, PrimitiveArrays>{
    'cuboid': buildCuboidArrays(Vector3(1, 2, 3)),
    'wedge': buildWedgeArrays(Vector3(1, 2, 3)),
    'plane': buildPlaneArrays(width: 2, depth: 3, segmentsX: 2, segmentsZ: 3),
    'sphere': buildSphereArrays(radius: 1, segments: 16, rings: 8),
    'cylinder': buildCylinderArrays(
      bottomRadius: 1,
      topRadius: 0.5,
      height: 2,
      radialSegments: 12,
      heightSegments: 2,
      bottomCap: true,
      topCap: true,
    ),
    'capsule': buildCapsuleArrays(
      radius: 0.5,
      height: 2,
      radialSegments: 12,
      capRings: 4,
    ),
    'torus': buildTorusArrays(
      radius: 1,
      tubeRadius: 0.3,
      radialSegments: 12,
      tubularSegments: 16,
    ),
    'disc': buildDiscArrays(radius: 1, segments: 12),
    'ring': buildRingArrays(innerRadius: 0.5, outerRadius: 1, segments: 12),
    'icosphere': buildIcosphereArrays(radius: 1, subdivisions: 2),
  };
  for (final MapEntry(:key, :value) in primitives.entries) {
    test('$key texture reads unmirrored from outside', () {
      final o = _orientation(value, skipSeam: key == 'icosphere');
      expect(o.mirrored, 0);
      expect(o.unmirrored, greaterThan(0));
    });
  }
}
