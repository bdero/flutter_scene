// Mesh traversal sequencing for EdgeBreaker attribute decoding. See the Draco
// Bitstream Specification, "Attributes Decoder for EdgeBreaker" and
// "Traverser" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attribute_decoders.dart';
import 'attributes.dart';
import 'corner_table.dart';
import 'decoder_buffer.dart';

/// Records the vertex visit order during traversal into the encoding data and
/// the sequencer's point id list.
class MeshAttributeIndicesEncodingObserver {
  MeshAttributeIndicesEncodingObserver(
    this._faces,
    this._sequencer,
    this._encodingData,
  );

  final Int32List _faces;
  final MeshTraversalSequencer _sequencer;
  final MeshAttributeIndicesEncodingData _encodingData;

  void onNewVertexVisited(int vertex, int corner) {
    _sequencer.addPointId(_faces[corner]);
    final numValues = _encodingData.numValues;
    _encodingData.encodedValueIndexToCorner[numValues] = corner;
    _encodingData.vertexToEncodedValueIndex[vertex] = numValues;
    _encodingData.numValues = numValues + 1;
  }
}

/// Common traversal interface used by [MeshTraversalSequencer].
abstract class MeshTraverser {
  late CornerTableView table;
  late MeshAttributeIndicesEncodingObserver observer;
  late Uint8List isFaceVisited;
  late Uint8List isVertexVisited;
  int numVisitedFaces = 0;

  void init(
    CornerTableView cornerTable,
    MeshAttributeIndicesEncodingObserver obs,
  ) {
    table = cornerTable;
    observer = obs;
    isFaceVisited = Uint8List(cornerTable.numFaces);
    isVertexVisited = Uint8List(cornerTable.numVertices);
    numVisitedFaces = 0;
  }

  void onTraversalStart() {}
  void onTraversalEnd() {}

  void traverseFromCorner(int cornerId);
}

/// Depth-first traversal (MESH_TRAVERSAL_DEPTH_FIRST).
class DepthFirstTraverser extends MeshTraverser {
  @override
  void traverseFromCorner(int cornerId) {
    if (isFaceVisited[cornerId ~/ 3] != 0) {
      return; // Already traversed.
    }
    final cornerToVertex = table.cornerToVertex;
    final oppositeCorners = table.opposite;
    final vertexLeftmost = table.vertexLeftmost;
    final stack = Int32List(table.numCorners);
    var stackSize = 0;
    stack[stackSize++] = cornerId;

    // The first face's other two corners may not be processed yet.
    final firstNext = cornerNext(cornerId);
    final firstPrev = cornerPrevious(cornerId);
    final nextVert = cornerToVertex[firstNext];
    final prevVert = cornerToVertex[firstPrev];
    if (nextVert == -1 || prevVert == -1) {
      throw dracoError('invalid connectivity');
    }
    if (isVertexVisited[nextVert] == 0) {
      isVertexVisited[nextVert] = 1;
      observer.onNewVertexVisited(nextVert, firstNext);
    }
    if (isVertexVisited[prevVert] == 0) {
      isVertexVisited[prevVert] = 1;
      observer.onNewVertexVisited(prevVert, firstPrev);
    }

    while (stackSize > 0) {
      var corner = stack[stackSize - 1];
      var faceId = corner < 0 ? -1 : corner ~/ 3;
      if (corner == -1 || isFaceVisited[faceId] != 0) {
        stackSize--;
        continue;
      }
      while (true) {
        isFaceVisited[faceId] = 1;
        numVisitedFaces++;

        final vertId = cornerToVertex[corner];
        if (vertId == -1) {
          throw dracoError('invalid connectivity');
        }
        if (isVertexVisited[vertId] == 0) {
          final lc = vertexLeftmost[vertId];
          var onBoundary = true;
          if (lc >= 0) {
            onBoundary = oppositeCorners[cornerNext(lc)] < 0;
          }
          isVertexVisited[vertId] = 1;
          observer.onNewVertexVisited(vertId, corner);
          if (!onBoundary) {
            // Interior vertex, move to the right face.
            corner = oppositeCorners[cornerNext(corner)];
            faceId = corner ~/ 3;
            continue;
          }
        }

        // Vertex already visited or on a boundary.
        final rightCorner = oppositeCorners[cornerNext(corner)];
        final leftCorner = oppositeCorners[cornerPrevious(corner)];
        final rightFace = rightCorner == -1 ? -1 : rightCorner ~/ 3;
        final leftFace = leftCorner == -1 ? -1 : leftCorner ~/ 3;
        final rightVisited = rightFace == -1 || isFaceVisited[rightFace] != 0;
        final leftVisited = leftFace == -1 || isFaceVisited[leftFace] != 0;

        if (rightVisited) {
          if (leftVisited) {
            stackSize--;
            break;
          }
          corner = leftCorner;
          faceId = leftFace;
        } else if (leftVisited) {
          corner = rightCorner;
          faceId = rightFace;
        } else {
          // Continue left, push right to resume later.
          stack[stackSize - 1] = leftCorner;
          stack[stackSize++] = rightCorner;
          break;
        }
      }
    }
  }
}

/// Priority-bucket traversal guided by prediction degree
/// (MESH_TRAVERSAL_PREDICTION_DEGREE).
class MaxPredictionDegreeTraverser extends MeshTraverser {
  static const int _maxPriority = 3;

  final List<List<int>> _stacks = [[], [], []];
  int _bestPriority = 0;
  Int32List _predictionDegree = Int32List(0);

  @override
  void onTraversalStart() {
    _predictionDegree = Int32List(table.numVertices);
  }

  int _computePriority(int cornerId) {
    final vTip = table.cornerToVertex[cornerId];
    var priority = 0;
    if (isVertexVisited[vTip] == 0) {
      final degree = ++_predictionDegree[vTip];
      priority = degree > 1 ? 1 : 2;
    }
    if (priority >= _maxPriority) {
      priority = _maxPriority - 1;
    }
    return priority;
  }

  void _push(int cornerId, int priority) {
    _stacks[priority].add(cornerId);
    if (priority < _bestPriority) {
      _bestPriority = priority;
    }
  }

  int _popNext() {
    for (var i = _bestPriority; i < _maxPriority; i++) {
      final stack = _stacks[i];
      if (stack.isNotEmpty) {
        final ret = stack.removeLast();
        _bestPriority = i;
        return ret;
      }
    }
    return -1;
  }

  @override
  void traverseFromCorner(int cornerId) {
    if (_predictionDegree.isEmpty) {
      return;
    }
    final cornerToVertex = table.cornerToVertex;
    final oppositeCorners = table.opposite;

    _stacks[0].add(cornerId);
    _bestPriority = 0;

    final firstNext = cornerNext(cornerId);
    final firstPrev = cornerPrevious(cornerId);
    final nextVert = cornerToVertex[firstNext];
    final prevVert = cornerToVertex[firstPrev];
    if (isVertexVisited[nextVert] == 0) {
      isVertexVisited[nextVert] = 1;
      observer.onNewVertexVisited(nextVert, firstNext);
    }
    if (isVertexVisited[prevVert] == 0) {
      isVertexVisited[prevVert] = 1;
      observer.onNewVertexVisited(prevVert, firstPrev);
    }
    final tipVertex = cornerToVertex[cornerId];
    if (isVertexVisited[tipVertex] == 0) {
      isVertexVisited[tipVertex] = 1;
      observer.onNewVertexVisited(tipVertex, cornerId);
    }

    var corner = _popNext();
    while (corner != -1) {
      if (isFaceVisited[corner ~/ 3] != 0) {
        corner = _popNext();
        continue;
      }
      inner:
      while (true) {
        isFaceVisited[corner ~/ 3] = 1;
        numVisitedFaces++;

        final vertId = cornerToVertex[corner];
        if (isVertexVisited[vertId] == 0) {
          isVertexVisited[vertId] = 1;
          observer.onNewVertexVisited(vertId, corner);
        }

        final rightCorner = oppositeCorners[cornerNext(corner)];
        final leftCorner = oppositeCorners[cornerPrevious(corner)];
        final rightVisited =
            rightCorner == -1 || isFaceVisited[rightCorner ~/ 3] != 0;
        final leftVisited =
            leftCorner == -1 || isFaceVisited[leftCorner ~/ 3] != 0;

        if (!leftVisited) {
          final priority = _computePriority(leftCorner);
          if (rightVisited && priority <= _bestPriority) {
            corner = leftCorner;
            continue inner;
          }
          _push(leftCorner, priority);
        }
        if (!rightVisited) {
          final priority = _computePriority(rightCorner);
          if (priority <= _bestPriority) {
            corner = rightCorner;
            continue inner;
          }
          _push(rightCorner, priority);
        }
        break;
      }
      corner = _popNext();
    }
  }
}

/// Sequencer producing point ids in mesh traversal order.
class MeshTraversalSequencer implements PointsSequencer {
  MeshTraversalSequencer(
    this._faces,
    this._numPoints,
    this._encodingData,
    this._traverser,
  );

  /// Point index per corner.
  final Int32List _faces;
  final int _numPoints;
  final MeshAttributeIndicesEncodingData _encodingData;
  final MeshTraverser _traverser;

  Int32List _outPointIds = Int32List(0);
  int _numOutPoints = 0;

  void addPointId(int pointId) {
    _outPointIds[_numOutPoints++] = pointId;
  }

  @override
  Int32List generateSequence() {
    _numOutPoints = 0;
    _outPointIds = Int32List(_numPoints);

    _traverser.onTraversalStart();
    final numFaces = _traverser.table.numFaces;
    for (
      var i = 0;
      i < numFaces && _traverser.numVisitedFaces < numFaces;
      i++
    ) {
      _traverser.traverseFromCorner(3 * i);
    }
    _traverser.onTraversalEnd();

    if (_numOutPoints < _outPointIds.length) {
      _outPointIds = Int32List.sublistView(_outPointIds, 0, _numOutPoints);
    }
    if (_encodingData.numValues <
        _encodingData.encodedValueIndexToCorner.length) {
      _encodingData.encodedValueIndexToCorner = Int32List.sublistView(
        _encodingData.encodedValueIndexToCorner,
        0,
        _encodingData.numValues,
      );
    }
    return _outPointIds;
  }

  @override
  void updatePointToAttributeIndexMapping(DracoAttribute attribute) {
    final numCorners = _traverser.table.numFaces * 3;
    final cornerToVertex = _traverser.table.cornerToVertex;
    final vertexToValue = _encodingData.vertexToEncodedValueIndex;
    final indicesMap = Uint32List(_numPoints);
    for (var ci = 0; ci < numCorners; ci++) {
      final vertId = cornerToVertex[ci];
      if (vertId < 0) {
        throw dracoError('invalid connectivity');
      }
      final valueId = vertexToValue[vertId];
      final pointId = _faces[ci];
      if (pointId >= _numPoints || valueId >= _numPoints) {
        throw dracoError('invalid attribute mapping');
      }
      indicesMap[pointId] = valueId;
    }
    attribute.indicesMap = indicesMap;
  }
}
