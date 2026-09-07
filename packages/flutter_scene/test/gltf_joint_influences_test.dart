// Covers reading a primitive's skinning influences across more than one
// JOINTS_n/WEIGHTS_n set. The engine's vertex layout carries four influences;
// a rig authored with more spreads them over several sets, and reading only
// set 0 leaves those vertices blending a fraction of a unit of weight, which
// drags them toward the armature origin even in the rest pose.

import 'dart:typed_data';

import 'package:flutter_scene/src/importer/gltf.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Fixture = ({
  GltfMeshPrimitive primitive,
  List<GltfAccessor> accessors,
  List<GltfBufferView> bufferViews,
  Uint8List data,
});

/// Builds the accessors and buffer for a primitive whose influences are laid
/// out one set after another, four per vertex per set.
///
/// [sets] is one entry per influence set: `(joint, weight)` in vertex order,
/// four per vertex.
_Fixture _fixture(List<List<(int, double)>> sets, {int? omitWeightsForSet}) {
  final vertexCount = sets.first.length ~/ 4;
  final accessors = <GltfAccessor>[];
  final bufferViews = <GltfBufferView>[];
  final bytes = BytesBuilder();
  final attributes = <String, int>{};

  void addAccessor(Float32List values) {
    final view = values.buffer.asUint8List(
      values.offsetInBytes,
      values.lengthInBytes,
    );
    bufferViews.add(
      GltfBufferView(
        buffer: 0,
        byteOffset: bytes.length,
        byteLength: view.length,
      ),
    );
    bytes.add(view);
    accessors.add(
      GltfAccessor(
        componentType: GltfComponentType.float,
        count: values.length ~/ 4,
        type: GltfAccessorType.vec4,
        bufferView: bufferViews.length - 1,
      ),
    );
  }

  for (var s = 0; s < sets.length; s++) {
    final joints = Float32List(vertexCount * 4);
    final weights = Float32List(vertexCount * 4);
    for (var i = 0; i < sets[s].length; i++) {
      joints[i] = sets[s][i].$1.toDouble();
      weights[i] = sets[s][i].$2;
    }
    addAccessor(joints);
    attributes['JOINTS_$s'] = accessors.length - 1;
    if (omitWeightsForSet == s) continue;
    addAccessor(weights);
    attributes['WEIGHTS_$s'] = accessors.length - 1;
  }

  return (
    primitive: GltfMeshPrimitive(attributes: attributes),
    accessors: accessors,
    bufferViews: bufferViews,
    data: bytes.takeBytes(),
  );
}

JointInfluences _readFixture(_Fixture fixture, int vertexCount) =>
    readJointInfluences(
      primitive: fixture.primitive,
      accessors: fixture.accessors,
      bufferViews: fixture.bufferViews,
      bufferData: fixture.data,
      vertexCount: vertexCount,
    );

JointInfluences _read(
  List<List<(int, double)>> sets, {
  int? omitWeightsForSet,
}) => _readFixture(
  _fixture(sets, omitWeightsForSet: omitWeightsForSet),
  sets.first.length ~/ 4,
);

/// Vertex [v]'s joint indices, in slot order (strongest first once merged).
List<int> _joints(JointInfluences influences, int v) => [
  for (var c = 0; c < 4; c++) influences.joints[v * 4 + c].toInt(),
];

/// Vertex [v]'s weights, in slot order.
List<double> _weights(JointInfluences influences, int v) => [
  for (var c = 0; c < 4; c++) influences.weights[v * 4 + c],
];

double _total(JointInfluences influences, int v) =>
    _weights(influences, v).reduce((a, b) => a + b);

Matcher _closeToAll(List<double> expected) => pairwiseCompare<double, double>(
  expected,
  (e, a) => (e - a).abs() < 1e-6,
  'is close to',
);

void main() {
  group('one influence set', () {
    test('is returned exactly as authored', () {
      // The overwhelming majority of assets. Nothing about them may change:
      // no reordering, and no renormalizing even of weights that do not sum
      // to one, which is how they have always been imported.
      final influences = _read([
        [(3, 0.4), (1, 0.3), (7, 0.2), (0, 0.05)],
      ]);

      expect(_joints(influences, 0), [3, 1, 7, 0]);
      expect(_weights(influences, 0), _closeToAll([0.4, 0.3, 0.2, 0.05]));
    });
  });

  group('several influence sets', () {
    test('keeps the strongest four and blends a full unit of weight', () {
      // Six influences over two sets. Set 0 alone sums to 0.55, so reading it
      // and stopping would pull this vertex 45% of the way to the origin.
      final influences = _read([
        [(1, 0.30), (2, 0.15), (3, 0.05), (4, 0.05)],
        [(5, 0.35), (6, 0.10), (0, 0.0), (0, 0.0)],
      ]);

      expect(_total(influences, 0), closeTo(1.0, 1e-6));
      // 5 (0.35), 1 (0.30), 2 (0.15) and 6 (0.10) survive; 3 and 4 are cut.
      // The survivors sum to 0.90 and renormalize over that.
      expect(_joints(influences, 0), [5, 1, 2, 6]);
      expect(
        _weights(influences, 0),
        _closeToAll([0.35 / 0.9, 0.30 / 0.9, 0.15 / 0.9, 0.10 / 0.9]),
      );
    });

    test('four or fewer real influences merge exactly', () {
      // Nothing is dropped here, so the weights must survive untouched rather
      // than being renormalized into something close but different.
      final influences = _read([
        [(1, 0.5), (2, 0.25), (0, 0.0), (0, 0.0)],
        [(3, 0.25), (0, 0.0), (0, 0.0), (0, 0.0)],
      ]);

      expect(_joints(influences, 0), [1, 2, 3, 1]);
      expect(_weights(influences, 0), _closeToAll([0.5, 0.25, 0.25, 0.0]));
    });

    test('a joint listed in two sets is one influence, not two slots', () {
      // Joint 1 appears in both sets. Splitting it across two of the four
      // slots would evict joint 4 for a duplicate of a joint already there.
      final influences = _read([
        [(1, 0.20), (2, 0.20), (3, 0.20), (4, 0.15)],
        [(1, 0.25), (0, 0.0), (0, 0.0), (0, 0.0)],
      ]);

      expect(_joints(influences, 0).toSet(), {1, 2, 3, 4});
      expect(_joints(influences, 0).first, 1);
      expect(_weights(influences, 0).first, closeTo(0.45, 1e-6));
      expect(_total(influences, 0), closeTo(1.0, 1e-6));
    });

    test('empty slots carry a bound joint at weight zero', () {
      // A weight of zero contributes nothing, but the index still reaches the
      // joints texture, so it must be one the skin actually holds.
      final influences = _read([
        [(6, 1.0), (0, 0.0), (0, 0.0), (0, 0.0)],
        [(0, 0.0), (0, 0.0), (0, 0.0), (0, 0.0)],
      ]);

      expect(_joints(influences, 0), [6, 6, 6, 6]);
      expect(_weights(influences, 0), _closeToAll([1.0, 0.0, 0.0, 0.0]));
    });

    test('an all-zero vertex rides a real bone', () {
      // Left at zero the vertex blends nothing and collapses to the armature
      // origin, which reads as a spike shooting out of the mesh.
      final influences = _read([
        [
          (0, 0.0), (0, 0.0), (0, 0.0), (0, 0.0), //
          (9, 1.0), (0, 0.0), (0, 0.0), (0, 0.0),
        ],
        [
          (0, 0.0), (0, 0.0), (0, 0.0), (0, 0.0), //
          (0, 0.0), (0, 0.0), (0, 0.0), (0, 0.0),
        ],
      ]);

      expect(_total(influences, 0), 1.0);
      expect(_weights(influences, 0).first, 1.0);
      // The second vertex has a real influence and is untouched by the
      // degenerate handling of the first.
      expect(_joints(influences, 1).first, 9);
      expect(_weights(influences, 1).first, closeTo(1.0, 1e-6));
    });

    test('every vertex is merged independently', () {
      final influences = _read([
        [
          (1, 0.5), (2, 0.5), (0, 0.0), (0, 0.0), //
          (3, 0.1), (4, 0.1), (5, 0.1), (6, 0.1),
        ],
        [
          (0, 0.0), (0, 0.0), (0, 0.0), (0, 0.0), //
          (7, 0.6), (0, 0.0), (0, 0.0), (0, 0.0),
        ],
      ]);

      expect(_joints(influences, 0).take(2), [1, 2]);
      expect(_weights(influences, 0).take(2), _closeToAll([0.5, 0.5]));
      expect(_joints(influences, 1).first, 7);
      expect(_weights(influences, 1).first, closeTo(0.6 / 0.9, 1e-6));
      expect(_total(influences, 1), closeTo(1.0, 1e-6));
    });
  });

  group('malformed sources', () {
    test('a JOINTS_n with no WEIGHTS_n is ignored, not fatal', () {
      // Set 1 cannot bind anything without its weights, so the import falls
      // back to set 0 alone rather than refusing the mesh.
      final influences = _read([
        [(1, 0.6), (2, 0.4), (0, 0.0), (0, 0.0)],
        [(5, 0.5), (0, 0.0), (0, 0.0), (0, 0.0)],
      ], omitWeightsForSet: 1);

      expect(_joints(influences, 0).take(2), [1, 2]);
      expect(_weights(influences, 0).take(2), _closeToAll([0.6, 0.4]));
    });

    test('a set numbered out of sequence ends the scan', () {
      // glTF requires the suffixes to run from 0 without gaps. A file with
      // JOINTS_0 and JOINTS_2 has no set 1, and reading past the gap would
      // apply data the spec says is not there.
      final built = _fixture([
        [(1, 0.5), (2, 0.5), (0, 0.0), (0, 0.0)],
        [(8, 0.9), (0, 0.0), (0, 0.0), (0, 0.0)],
      ]);
      final attributes = Map<String, int>.from(built.primitive.attributes);
      attributes['JOINTS_2'] = attributes.remove('JOINTS_1')!;
      attributes['WEIGHTS_2'] = attributes.remove('WEIGHTS_1')!;

      final influences = _readFixture((
        primitive: GltfMeshPrimitive(attributes: attributes),
        accessors: built.accessors,
        bufferViews: built.bufferViews,
        data: built.data,
      ), 1);

      expect(_joints(influences, 0).take(2), [1, 2]);
      expect(_weights(influences, 0).take(2), _closeToAll([0.5, 0.5]));
    });
  });

  group('primitiveHasJointInfluences', () {
    test('needs both halves of set 0', () {
      expect(
        primitiveHasJointInfluences(
          GltfMeshPrimitive(attributes: const {'JOINTS_0': 0, 'WEIGHTS_0': 1}),
        ),
        isTrue,
      );
      expect(
        primitiveHasJointInfluences(
          GltfMeshPrimitive(attributes: const {'JOINTS_0': 0}),
        ),
        isFalse,
      );
      expect(primitiveHasJointInfluences(GltfMeshPrimitive()), isFalse);
    });
  });
}
