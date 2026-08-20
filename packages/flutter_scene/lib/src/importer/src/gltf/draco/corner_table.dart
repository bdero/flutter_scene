// Corner table connectivity for EdgeBreaker decoding, plus the attribute
// (seam-aware) corner table. See the Draco Bitstream Specification,
// "EdgeBreaker Decoder" and "Attributes Decoder for EdgeBreaker"
// (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'decoder_buffer.dart';

/// Next corner within a face (corners are grouped in triples).
int cornerNext(int c) => c < 0 ? -1 : (c % 3 == 2 ? c - 2 : c + 1);

/// Previous corner within a face.
int cornerPrevious(int c) => c < 0 ? -1 : (c % 3 == 0 ? c + 2 : c - 1);

/// Flat connectivity shared by the base and attribute corner tables, so
/// traversal and prediction code runs on either.
abstract class CornerTableView {
  /// Corner to vertex, -1 for unset.
  Int32List get cornerToVertex;

  /// Corner to opposite corner, -1 on a boundary. Seam edges read as
  /// boundaries in the attribute table's view.
  Int32List get opposite;

  /// Vertex to its left-most corner, -1 for isolated vertices.
  Int32List get vertexLeftmost;

  int get numFaces;
  int get numCorners;
  int get numVertices;

  /// Next corner around the corner's vertex, counterclockwise.
  int swingLeft(int c) {
    final n = cornerNext(c);
    final o = n < 0 ? -1 : opposite[n];
    return o < 0 ? -1 : cornerNext(o);
  }

  /// Next corner around the corner's vertex, clockwise.
  int swingRight(int c) {
    final p = cornerPrevious(c);
    final o = p < 0 ? -1 : opposite[p];
    return o < 0 ? -1 : cornerPrevious(o);
  }
}

/// Corner table built by the EdgeBreaker connectivity decoder.
class CornerTable extends CornerTableView {
  CornerTable(int numFaces, int vertexCapacity)
    : _numFaces = numFaces,
      cornerToVertex = Int32List(numFaces * 3)..fillRange(0, numFaces * 3, -1),
      opposite = Int32List(numFaces * 3)..fillRange(0, numFaces * 3, -1),
      vertexLeftmost = Int32List(vertexCapacity)
        ..fillRange(0, vertexCapacity, -1);

  final int _numFaces;

  @override
  final Int32List cornerToVertex;

  @override
  Int32List opposite;

  @override
  Int32List vertexLeftmost;

  int _numVertices = 0;

  @override
  int get numFaces => _numFaces;

  @override
  int get numCorners => _numFaces * 3;

  @override
  int get numVertices => _numVertices;

  int addNewVertex() {
    final v = _numVertices++;
    if (v >= vertexLeftmost.length) {
      final grown = Int32List(vertexLeftmost.length + 64)
        ..fillRange(0, vertexLeftmost.length + 64, -1)
        ..setRange(0, vertexLeftmost.length, vertexLeftmost);
      vertexLeftmost = grown;
    }
    vertexLeftmost[v] = -1;
    return v;
  }
}

/// Attribute corner table, the base connectivity cut along attribute seams.
class MeshAttributeCornerTable extends CornerTableView {
  MeshAttributeCornerTable(this._base)
    : isEdgeOnSeam = Uint8List(_base.numCorners),
      isVertexOnSeam = Uint8List(_base.numVertices),
      cornerToVertex = Int32List(_base.numCorners)
        ..fillRange(0, _base.numCorners, -1);

  final CornerTable _base;

  final Uint8List isEdgeOnSeam;

  /// Per base-vertex seam flag.
  final Uint8List isVertexOnSeam;

  @override
  final Int32List cornerToVertex;

  @override
  Int32List vertexLeftmost = Int32List(0);

  Int32List? _effectiveOpposite;
  int _numVertices = 0;

  @override
  int get numFaces => _base.numFaces;

  @override
  int get numCorners => _base.numCorners;

  @override
  int get numVertices => _numVertices;

  /// Seam-aware opposite corners (seam edges read as boundaries). Built once;
  /// all seams are added before traversal.
  @override
  Int32List get opposite {
    var eff = _effectiveOpposite;
    if (eff == null) {
      final nc = _base.numCorners;
      eff = Int32List(nc);
      final baseOpp = _base.opposite;
      for (var c = 0; c < nc; c++) {
        eff[c] = isEdgeOnSeam[c] != 0 ? -1 : baseOpp[c];
      }
      _effectiveOpposite = eff;
    }
    return eff;
  }

  void addSeamEdge(int c) {
    final baseCornerToVertex = _base.cornerToVertex;
    isEdgeOnSeam[c] = 1;
    isVertexOnSeam[baseCornerToVertex[cornerNext(c)]] = 1;
    isVertexOnSeam[baseCornerToVertex[cornerPrevious(c)]] = 1;
    final opp = _base.opposite[c];
    if (opp != -1) {
      isEdgeOnSeam[opp] = 1;
      isVertexOnSeam[baseCornerToVertex[cornerNext(opp)]] = 1;
      isVertexOnSeam[baseCornerToVertex[cornerPrevious(opp)]] = 1;
    }
  }

  /// Rebuilds the attribute vertex ids from the base connectivity plus seams.
  void recomputeVertices() {
    final numBaseVertices = _base.numVertices;
    final leftMost = Int32List(numCorners);
    final seamOpp = opposite;
    final baseOpp = _base.opposite;
    final baseLeftmost = _base.vertexLeftmost;
    var numNewVertices = 0;

    for (var v = 0; v < numBaseVertices; v++) {
      final c = baseLeftmost[v];
      if (c == -1) continue; // Isolated vertex.

      if (isVertexOnSeam[v] == 0) {
        final vertId = numNewVertices++;
        leftMost[vertId] = c;
        cornerToVertex[c] = vertId;
        // Sweep the full ring clockwise (base swings, seams irrelevant here).
        var act = cornerPrevious(baseOpp[cornerPrevious(c)]);
        while (act != -1 && act != c) {
          cornerToVertex[act] = vertId;
          act = cornerPrevious(baseOpp[cornerPrevious(act)]);
        }
      } else {
        var vertId = numNewVertices++;
        // Swing left along seam-aware edges to find the ring start.
        var firstC = c;
        var act = cornerNext(seamOpp[cornerNext(firstC)]);
        while (act != -1) {
          firstC = act;
          act = cornerNext(seamOpp[cornerNext(firstC)]);
          if (act == c) {
            throw dracoError('non-manifold attribute seam');
          }
        }
        cornerToVertex[firstC] = vertId;
        leftMost[vertId] = firstC;
        // Sweep clockwise over base edges, opening a new attribute vertex at
        // each interior seam crossing.
        act = cornerPrevious(baseOpp[cornerPrevious(firstC)]);
        while (act != -1 && act != firstC) {
          if (isEdgeOnSeam[cornerNext(act)] != 0) {
            vertId = numNewVertices++;
            leftMost[vertId] = act;
          }
          cornerToVertex[act] = vertId;
          act = cornerPrevious(baseOpp[cornerPrevious(act)]);
        }
      }
    }

    _numVertices = numNewVertices;
    vertexLeftmost = Int32List.sublistView(leftMost, 0, numNewVertices);
  }
}

/// Traversal output maps for one attribute set. Vertex ids map to the order
/// their values were encoded, and each encoded value maps back to a corner.
class MeshAttributeIndicesEncodingData {
  Int32List vertexToEncodedValueIndex = Int32List(0);
  Int32List encodedValueIndexToCorner = Int32List(0);
  int numValues = 0;

  void init(int numVertices) {
    vertexToEncodedValueIndex = Int32List(numVertices);
    encodedValueIndexToCorner = Int32List(numVertices);
    numValues = 0;
  }
}
