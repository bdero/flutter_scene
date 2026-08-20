// Component coverage for the multi parallelogram prediction scheme, which
// current encoders never emit (they use the constrained variant), so the
// end-to-end goldens cannot reach it.

import 'dart:typed_data';

import 'package:flutter_scene/src/importer/src/gltf/draco/corner_table.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/decoder_buffer.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/mesh_prediction_schemes.dart';
import 'package:flutter_scene/src/importer/src/gltf/draco/prediction_transforms.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-built fan mesh. Vertices v0=0, v1=1, v2=2, X=3, e1=4, e2=5 with
/// faces fan1=(X,v0,v1), fan2=(X,v1,v2), ear1=(v1,v0,e1), ear2=(v2,v1,e2).
/// X's two corners each face an ear across a decoded edge, giving two
/// parallelogram predictions to average.
CornerTable _buildFanTable() {
  final table = CornerTable(4, 6);
  for (var i = 0; i < 6; i++) {
    table.addNewVertex();
  }
  table.cornerToVertex.setAll(0, [3, 0, 1, 3, 1, 2, 1, 0, 4, 2, 1, 5]);
  table.opposite.setAll(0, [8, 5, -1, 11, -1, 1, -1, -1, 0, -1, -1, 3]);
  table.vertexLeftmost.setAll(0, [1, 2, 5, 0, 8, 11]);
  return table;
}

WrapTransform _wideWrapTransform() {
  final transform = WrapTransform();
  final bytes = ByteData(8)
    ..setInt32(0, -1000, Endian.little)
    ..setInt32(4, 1000, Endian.little);
  transform.decodeTransformData(
    DecoderBuffer(bytes.buffer.asUint8List(), dracoBitstreamVersion(2, 2)),
  );
  return transform;
}

void main() {
  test('multi parallelogram averages the available parallelograms', () {
    final table = _buildFanTable();
    // Decode order d0..d5 = v0, v1, e1, e2, v2, X.
    final vertexToDataMap = Int32List.fromList([0, 1, 4, 5, 2, 3]);
    final dataToCornerMap = Int32List.fromList([1, 2, 8, 11, 5, 3]);
    final meshData = MeshPredictionSchemeData(
      table,
      dataToCornerMap,
      vertexToDataMap,
    );
    final scheme = MeshPredictionSchemeMultiParallelogramDecoder(
      _wideWrapTransform(),
      meshData,
    );

    // Original values by decode order, [v0, v1, e1, e2, v2, X].
    // Predictions the scheme should form,
    //   d0 zero, d1..d4 delta from the previous value (their opposite faces
    //   contain the undecoded X), and d5 the average of two parallelograms,
    //   (v2 + v1 - e2) and (v1 + v0 - e1) = (43 + 25) / 2 = 34.
    final corrections = Int32List.fromList([10, 10, -15, 2, 23, 6]);
    final expected = [10, 20, 5, 7, 30, 40];

    scheme.computeOriginalValues(
      corrections,
      corrections,
      corrections.length,
      1,
      Int32List(0),
    );
    expect(corrections, expected);
  });

  test('multi parallelogram falls back to delta with no support', () {
    final table = _buildFanTable();
    final vertexToDataMap = Int32List.fromList([0, 1, 4, 5, 2, 3]);
    // X first visited at corner 0, swingRight hits the boundary after one
    // parallelogram, so only ear1 contributes, v1 + v0 - e1 = 25.
    final dataToCornerMap = Int32List.fromList([1, 2, 8, 11, 5, 0]);
    final meshData = MeshPredictionSchemeData(
      table,
      dataToCornerMap,
      vertexToDataMap,
    );
    final scheme = MeshPredictionSchemeMultiParallelogramDecoder(
      _wideWrapTransform(),
      meshData,
    );
    final corrections = Int32List.fromList([10, 10, -15, 2, 23, 15]);
    final expected = [10, 20, 5, 7, 30, 40];
    scheme.computeOriginalValues(
      corrections,
      corrections,
      corrections.length,
      1,
      Int32List(0),
    );
    expect(corrections, expected);
  });
}
