// EdgeBreaker connectivity decoding, reverse decoding of the EdgeBreaker
// symbol stream into a corner table. See the Draco Bitstream Specification,
// "EdgeBreaker Decoder", "EdgeBreaker Traversal", and "Attributes Decoder for
// EdgeBreaker" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attribute_decoders.dart';
import 'constants.dart';
import 'corner_table.dart';
import 'decoder_buffer.dart';
import 'edgebreaker_traversal.dart';
import 'mesh_decoder.dart';
import 'mesh_prediction_schemes.dart';
import 'prediction_schemes.dart';
import 'prediction_transforms.dart';
import 'traverser.dart';

/// Per attribute-data seam connectivity and traversal state.
class _AttributeData {
  _AttributeData(int numCorners) : seamCorners = Int32List(numCorners);

  int decoderId = -1;
  MeshAttributeCornerTable? connectivityData;
  bool isConnectivityUsed = true;
  final MeshAttributeIndicesEncodingData encodingData =
      MeshAttributeIndicesEncodingData();
  final Int32List seamCorners;
  int numSeamCorners = 0;
}

class _TopologySplitEvent {
  int sourceSymbolId = 0;
  int splitSymbolId = 0;
  int sourceEdge = 0; // 0 left, 1 right.
}

/// Decodes EdgeBreaker coded connectivity and drives attribute traversal.
class EdgebreakerMeshDecoder extends DracoMeshDecoder {
  EdgebreakerMeshDecoder(super.buffer);

  late CornerTable _cornerTable;
  late MeshEdgebreakerTraversalDecoder _traversalDecoder;
  final List<_TopologySplitEvent> _topologySplitData = [];
  final List<_AttributeData> _attributeData = [];
  final MeshAttributeIndicesEncodingData _posEncodingData =
      MeshAttributeIndicesEncodingData();
  int _posDataDecoderId = -1;
  late Uint8List _isVertHole;
  int _numEncodedVertices = 0;

  @override
  void decodeConnectivity() {
    final traversalDecoderType = buffer.decodeUint8();
    switch (traversalDecoderType) {
      case DracoEdgebreakerMethod.standard:
      case DracoEdgebreakerMethod.valence:
        break;
      case DracoEdgebreakerMethod.predictive:
        throw dracoError(
          'predictive EdgeBreaker traversal is not part of bitstream 2.2',
        );
      default:
        throw dracoError(
          'unknown EdgeBreaker traversal method $traversalDecoderType',
        );
    }

    _numEncodedVertices = buffer.decodeVarint();
    numFaces = buffer.decodeVarint();
    if (numFaces > 0x7FFFFFFF ~/ 3) {
      throw dracoError('too many faces');
    }
    if (_numEncodedVertices > numFaces * 3) {
      throw dracoError('invalid vertex count');
    }
    // A manifold mesh needs at least 3F/2 edges but the vertices allow at most
    // V*(V-1)/2, so reject impossible combinations early.
    final minNumFaceEdges = 3 * numFaces ~/ 2;
    final maxNumVertexEdges =
        _numEncodedVertices * (_numEncodedVertices - 1) ~/ 2;
    if (maxNumVertexEdges < minNumFaceEdges) {
      throw dracoError('invalid vertex count');
    }

    final numAttributeData = buffer.decodeUint8();
    final numEncodedSymbols = buffer.decodeVarint();
    if (numFaces < numEncodedSymbols) {
      throw dracoError('invalid symbol count');
    }
    final maxEncodedFaces = numEncodedSymbols + numEncodedSymbols ~/ 3;
    if (numFaces > maxEncodedFaces) {
      throw dracoError('invalid symbol count');
    }
    final numEncodedSplitSymbols = buffer.decodeVarint();
    if (numEncodedSplitSymbols > numEncodedSymbols) {
      throw dracoError('invalid split symbol count');
    }

    final vertexCapacity = _numEncodedVertices + numEncodedSplitSymbols;
    _cornerTable = CornerTable(numFaces, vertexCapacity);
    _attributeData.clear();
    for (var i = 0; i < numAttributeData; i++) {
      _attributeData.add(_AttributeData(numFaces * 3));
    }

    // All vertices start as boundary (hole) vertices.
    _isVertHole = Uint8List(vertexCapacity)..fillRange(0, vertexCapacity, 1);

    _decodeTopologySplitEvents();

    _traversalDecoder = traversalDecoderType == DracoEdgebreakerMethod.valence
        ? MeshEdgebreakerTraversalValenceDecoder(_cornerTable)
        : MeshEdgebreakerTraversalDecoder();
    _traversalDecoder.init(buffer);
    _traversalDecoder.setNumEncodedVertices(vertexCapacity);
    _traversalDecoder.setNumAttributeData(numAttributeData);
    final traversalEndBuffer = _traversalDecoder.start();

    final numConnectivityVerts = _decodeConnectivity(numEncodedSymbols);

    // Resume the main stream after the traversal sections.
    buffer = traversalEndBuffer;

    if (_attributeData.isNotEmpty) {
      _decodeAttributeConnectivities();
    }
    _traversalDecoder.done();

    for (final data in _attributeData) {
      final connectivity = MeshAttributeCornerTable(_cornerTable);
      for (var s = 0; s < data.numSeamCorners; s++) {
        connectivity.addSeamEdge(data.seamCorners[s]);
      }
      connectivity.recomputeVertices();
      data.connectivityData = connectivity;
    }

    _posEncodingData.init(_cornerTable.numVertices);
    for (final data in _attributeData) {
      var attConnectivityVerts = data.connectivityData!.numVertices;
      if (attConnectivityVerts < _cornerTable.numVertices) {
        attConnectivityVerts = _cornerTable.numVertices;
      }
      data.encodingData.init(attConnectivityVerts);
    }
    _assignPointsToCorners(numConnectivityVerts);
  }

  void _decodeTopologySplitEvents() {
    final numTopologySplits = buffer.decodeVarint();
    if (numTopologySplits == 0) {
      return;
    }
    if (numTopologySplits > _cornerTable.numFaces) {
      throw dracoError('invalid topology split count');
    }
    // Source and split symbol ids use delta plus varint coding.
    var lastSourceSymbolId = 0;
    for (var i = 0; i < numTopologySplits; i++) {
      final event = _TopologySplitEvent();
      event.sourceSymbolId = buffer.decodeVarint() + lastSourceSymbolId;
      final delta = buffer.decodeVarint();
      if (delta > event.sourceSymbolId) {
        throw dracoError('invalid topology split');
      }
      event.splitSymbolId = event.sourceSymbolId - delta;
      lastSourceSymbolId = event.sourceSymbolId;
      _topologySplitData.add(event);
    }
    // Split edges come from a direct bit sequence.
    buffer.startBitDecoding(sizePrefixed: false);
    for (var i = 0; i < numTopologySplits; i++) {
      _topologySplitData[i].sourceEdge =
          buffer.decodeLeastSignificantBits32(1) & 1;
    }
    buffer.endBitDecoding();
  }

  /// Pops the pending topology split for [encoderSymbolId], if any. Returns
  /// (faceEdge, encoderSplitSymbolId) or null.
  (int, int)? _popTopologySplit(int encoderSymbolId) {
    if (_topologySplitData.isEmpty) {
      return null;
    }
    final back = _topologySplitData.last;
    if (back.sourceSymbolId > encoderSymbolId) {
      throw dracoError('invalid topology split');
    }
    if (back.sourceSymbolId != encoderSymbolId) {
      return null;
    }
    _topologySplitData.removeLast();
    return (back.sourceEdge, back.splitSymbolId);
  }

  /// Reverse decoding of the EdgeBreaker symbols, based on Spirale Reversi.
  /// Returns the connectivity vertex count.
  int _decodeConnectivity(int numSymbols) {
    final activeCornerStack = Int32List(
      numSymbols + _topologySplitData.length + 16,
    );
    var stackSize = 0;
    final topologySplitActiveCorners = <int, int>{};
    final invalidVertices = <int>[];
    final removeInvalidVertices = _attributeData.isEmpty;

    final maxNumVertices = _isVertHole.length;
    var numFacesDecoded = 0;

    final cornerToVertex = _cornerTable.cornerToVertex;
    final oppositeCorners = _cornerTable.opposite;

    for (var symbolId = 0; symbolId < numSymbols; symbolId++) {
      final faceIndex = numFacesDecoded++;
      var checkTopologySplit = false;
      final symbol = _traversalDecoder.decodeSymbol();

      if (symbol == DracoTopology.c) {
        // New face between two edges on the open boundary.
        if (stackSize == 0) {
          throw dracoError('empty active corner stack');
        }
        final cornerA = activeCornerStack[stackSize - 1];
        final vertexX = cornerToVertex[cornerNext(cornerA)];
        final cornerB = cornerNext(_cornerTable.vertexLeftmost[vertexX]);
        if (cornerA == cornerB) {
          throw dracoError('invalid C symbol');
        }
        if (oppositeCorners[cornerA] != -1 || oppositeCorners[cornerB] != -1) {
          throw dracoError('invalid C symbol');
        }

        final corner = 3 * faceIndex;
        oppositeCorners[cornerA] = corner + 1;
        oppositeCorners[corner + 1] = cornerA;
        oppositeCorners[cornerB] = corner + 2;
        oppositeCorners[corner + 2] = cornerB;

        final vertAPrev = cornerToVertex[cornerPrevious(cornerA)];
        final vertBNext = cornerToVertex[cornerNext(cornerB)];
        if (vertexX == vertAPrev || vertexX == vertBNext) {
          throw dracoError('non-manifold edge');
        }
        cornerToVertex[corner] = vertexX;
        cornerToVertex[corner + 1] = vertBNext;
        cornerToVertex[corner + 2] = vertAPrev;
        _cornerTable.vertexLeftmost[vertAPrev] = corner + 2;
        _isVertHole[vertexX] = 0; // Vertex x is now interior.
        activeCornerStack[stackSize - 1] = corner;
      } else if (symbol == DracoTopology.r || symbol == DracoTopology.l) {
        // New face extending from the open boundary edge.
        if (stackSize == 0) {
          throw dracoError('empty active corner stack');
        }
        final cornerA = activeCornerStack[stackSize - 1];
        if (oppositeCorners[cornerA] != -1) {
          throw dracoError('invalid R or L symbol');
        }

        final corner = 3 * faceIndex;
        int oppCorner;
        int cornerL;
        int cornerR;
        if (symbol == DracoTopology.r) {
          oppCorner = corner + 2;
          cornerL = corner + 1;
          cornerR = corner;
        } else {
          oppCorner = corner + 1;
          cornerL = corner;
          cornerR = corner + 2;
        }
        oppositeCorners[oppCorner] = cornerA;
        oppositeCorners[cornerA] = oppCorner;

        final newVertIndex = _cornerTable.addNewVertex();
        if (_cornerTable.numVertices > maxNumVertices) {
          throw dracoError('vertex count exceeds header');
        }
        cornerToVertex[oppCorner] = newVertIndex;
        _cornerTable.vertexLeftmost[newVertIndex] = oppCorner;

        final vertexR = cornerToVertex[cornerPrevious(cornerA)];
        cornerToVertex[cornerR] = vertexR;
        _cornerTable.vertexLeftmost[vertexR] = cornerR;
        cornerToVertex[cornerL] = cornerToVertex[cornerNext(cornerA)];

        activeCornerStack[stackSize - 1] = corner;
        checkTopologySplit = true;
      } else if (symbol == DracoTopology.s) {
        // Merge the last two active edges into a new face.
        if (stackSize == 0) {
          throw dracoError('empty active corner stack');
        }
        final cornerB = activeCornerStack[--stackSize];

        // Corner a may come from a topology split event.
        final splitCorner = topologySplitActiveCorners[symbolId];
        if (splitCorner != null) {
          activeCornerStack[stackSize++] = splitCorner;
        }
        if (stackSize == 0) {
          throw dracoError('empty active corner stack');
        }
        final cornerA = activeCornerStack[stackSize - 1];
        if (cornerA == cornerB) {
          throw dracoError('invalid S symbol');
        }
        if (oppositeCorners[cornerA] != -1 || oppositeCorners[cornerB] != -1) {
          throw dracoError('invalid S symbol');
        }

        final corner = 3 * faceIndex;
        oppositeCorners[cornerA] = corner + 2;
        oppositeCorners[corner + 2] = cornerA;
        oppositeCorners[cornerB] = corner + 1;
        oppositeCorners[corner + 1] = cornerB;

        final vertexP = cornerToVertex[cornerPrevious(cornerA)];
        cornerToVertex[corner] = vertexP;
        cornerToVertex[corner + 1] = cornerToVertex[cornerNext(cornerA)];
        final vertBPrev = cornerToVertex[cornerPrevious(cornerB)];
        cornerToVertex[corner + 2] = vertBPrev;
        _cornerTable.vertexLeftmost[vertBPrev] = corner + 2;

        var cornerN = cornerNext(cornerB);
        final vertexN = cornerToVertex[cornerN];
        _traversalDecoder.mergeVertices(vertexP, vertexN);
        // The merged vertex adopts vertex n's left-most corner.
        _cornerTable.vertexLeftmost[vertexP] =
            _cornerTable.vertexLeftmost[vertexN];

        // Relabel corner n and every corner counterclockwise from it.
        final firstCorner = cornerN;
        while (cornerN != -1) {
          cornerToVertex[cornerN] = vertexP;
          final so = oppositeCorners[cornerNext(cornerN)];
          cornerN = so < 0 ? -1 : cornerNext(so);
          if (cornerN == firstCorner) {
            throw dracoError('non-manifold S symbol');
          }
        }
        // Isolate the merged-away vertex.
        _cornerTable.vertexLeftmost[vertexN] = -1;
        if (removeInvalidVertices) {
          invalidVertices.add(vertexN);
        }
        activeCornerStack[stackSize - 1] = corner;
      } else if (symbol == DracoTopology.e) {
        final corner = 3 * faceIndex;
        final firstVertIndex = _cornerTable.addNewVertex();
        _cornerTable.addNewVertex();
        _cornerTable.addNewVertex();
        if (_cornerTable.numVertices > maxNumVertices) {
          throw dracoError('vertex count exceeds header');
        }
        cornerToVertex[corner] = firstVertIndex;
        cornerToVertex[corner + 1] = firstVertIndex + 1;
        cornerToVertex[corner + 2] = firstVertIndex + 2;
        _cornerTable.vertexLeftmost[firstVertIndex] = corner;
        _cornerTable.vertexLeftmost[firstVertIndex + 1] = corner + 1;
        _cornerTable.vertexLeftmost[firstVertIndex + 2] = corner + 2;
        activeCornerStack[stackSize++] = corner;
        checkTopologySplit = true;
      } else {
        throw dracoError('invalid EdgeBreaker symbol');
      }

      _traversalDecoder.newActiveCornerReached(
        activeCornerStack[stackSize - 1],
      );

      if (checkTopologySplit) {
        final encoderSymbolId = numSymbols - symbolId - 1;
        while (true) {
          final split = _popTopologySplit(encoderSymbolId);
          if (split == null) break;
          final (faceEdge, encoderSplitSymbolId) = split;
          final actTopCorner = activeCornerStack[stackSize - 1];
          // Edge 1 is the right face edge, 0 the left.
          final newActiveCorner = faceEdge == 1
              ? cornerNext(actTopCorner)
              : cornerPrevious(actTopCorner);
          // Convert the encoder split symbol id to a decoder symbol id.
          final decoderSplitSymbolId = numSymbols - encoderSplitSymbolId - 1;
          topologySplitActiveCorners[decoderSplitSymbolId] = newActiveCorner;
        }
      }
    }

    if (_cornerTable.numVertices > maxNumVertices) {
      throw dracoError('vertex count exceeds header');
    }

    // Decode start faces and connect them to faces from the active stack.
    while (stackSize > 0) {
      final corner = activeCornerStack[--stackSize];
      final interiorFace = _traversalDecoder.decodeStartFaceConfiguration();
      if (interiorFace) {
        if (numFacesDecoded >= _cornerTable.numFaces) {
          throw dracoError('too many interior faces');
        }
        final vertN = cornerToVertex[cornerNext(corner)];
        final cornerB = cornerNext(_cornerTable.vertexLeftmost[vertN]);
        final vertX = cornerToVertex[cornerNext(cornerB)];
        final cornerC = cornerNext(_cornerTable.vertexLeftmost[vertX]);
        if (corner == cornerB || corner == cornerC || cornerB == cornerC) {
          throw dracoError('invalid interior start face');
        }
        if (oppositeCorners[corner] != -1 ||
            oppositeCorners[cornerB] != -1 ||
            oppositeCorners[cornerC] != -1) {
          throw dracoError('invalid interior start face');
        }
        final vertP = cornerToVertex[cornerNext(cornerC)];

        final faceIndex = numFacesDecoded++;
        final newCorner = 3 * faceIndex;
        oppositeCorners[newCorner] = corner;
        oppositeCorners[corner] = newCorner;
        oppositeCorners[newCorner + 1] = cornerB;
        oppositeCorners[cornerB] = newCorner + 1;
        oppositeCorners[newCorner + 2] = cornerC;
        oppositeCorners[cornerC] = newCorner + 2;
        cornerToVertex[newCorner] = vertX;
        cornerToVertex[newCorner + 1] = vertP;
        cornerToVertex[newCorner + 2] = vertN;
        _isVertHole[vertX] = 0;
        _isVertHole[vertP] = 0;
        _isVertHole[vertN] = 0;
      }
    }

    if (numFacesDecoded != _cornerTable.numFaces) {
      throw dracoError('face count mismatch');
    }

    var numVertices = _cornerTable.numVertices;
    // Swap isolated vertices out with the last valid vertex, in encounter
    // order, matching the reference decoder.
    for (final invalidVert in invalidVertices) {
      var srcVert = numVertices - 1;
      while (_cornerTable.vertexLeftmost[srcVert] == -1) {
        srcVert = --numVertices - 1;
      }
      if (srcVert < invalidVert) continue;

      // Remap all of srcVert's corners, swinging left to a boundary then
      // right from the start.
      final startCorner = _cornerTable.vertexLeftmost[srcVert];
      var cid = startCorner;
      var leftTraversal = true;
      while (cid != -1) {
        if (cornerToVertex[cid] != srcVert) {
          throw dracoError('invalid connectivity');
        }
        cornerToVertex[cid] = invalidVert;
        if (leftTraversal) {
          final nextC = _cornerTable.swingLeft(cid);
          if (nextC == -1) {
            leftTraversal = false;
            cid = _cornerTable.swingRight(startCorner);
          } else if (nextC == startCorner) {
            break; // Closed fan.
          } else {
            cid = nextC;
          }
        } else {
          cid = _cornerTable.swingRight(cid);
        }
      }
      _cornerTable.vertexLeftmost[invalidVert] =
          _cornerTable.vertexLeftmost[srcVert];
      _cornerTable.vertexLeftmost[srcVert] = -1;
      _isVertHole[invalidVert] = _isVertHole[srcVert];
      _isVertHole[srcVert] = 0;
      numVertices--;
    }
    return numVertices;
  }

  /// Decodes every face's attribute seam bits in one pass over corners.
  void _decodeAttributeConnectivities() {
    final oppositeCorners = _cornerTable.opposite;
    final decoders = _traversalDecoder.attributeConnectivityDecoders;
    final numCorners = _cornerTable.numCorners;
    for (var corner = 0; corner < numCorners; corner += 3) {
      final srcFaceId = corner ~/ 3;
      for (var k = 0; k < 3; k++) {
        final cc = corner + k;
        final oppCorner = oppositeCorners[cc];
        if (oppCorner == -1) {
          // Boundary edges are seams for every attribute.
          for (final data in _attributeData) {
            data.seamCorners[data.numSeamCorners++] = cc;
          }
        } else if (oppCorner ~/ 3 >= srcFaceId) {
          for (var i = 0; i < _attributeData.length; i++) {
            if (decoders[i].decodeNextBit()) {
              final data = _attributeData[i];
              data.seamCorners[data.numSeamCorners++] = cc;
            }
          }
        }
      }
    }
  }

  /// Maps corners to point ids, deduplicating across attribute seams, and
  /// fills the mesh faces.
  void _assignPointsToCorners(int numConnectivityVerts) {
    faces = Int32List(_cornerTable.numFaces * 3);
    final cornerToVertex = _cornerTable.cornerToVertex;

    if (_attributeData.isEmpty) {
      // Position-only connectivity, vertex ids are point ids.
      faces.setAll(0, cornerToVertex);
      numPoints = numConnectivityVerts;
      return;
    }

    var pointCount = 0;
    final cornerToPointMap = Int32List(_cornerTable.numCorners);
    final numVertices = _cornerTable.numVertices;
    final vertexLeftmost = _cornerTable.vertexLeftmost;
    final numAttrData = _attributeData.length;
    final attCornerToVertex = [
      for (final data in _attributeData) data.connectivityData!.cornerToVertex,
    ];
    final attVertexOnSeam = [
      for (final data in _attributeData) data.connectivityData!.isVertexOnSeam,
    ];

    for (var v = 0; v < numVertices; v++) {
      var c = vertexLeftmost[v];
      if (c == -1) continue; // Isolated vertex.

      var isSeamVertex = _isVertHole[v] != 0;
      for (var i = 0; i < numAttrData && !isSeamVertex; i++) {
        isSeamVertex = attVertexOnSeam[i][v] != 0;
      }

      if (!isSeamVertex) {
        // Every corner in the ring shares one point id.
        final initialC = c;
        final pointId = pointCount++;
        cornerToPointMap[initialC] = pointId;
        c = _cornerTable.swingRight(initialC);
        while (c != -1 && c != initialC) {
          cornerToPointMap[c] = pointId;
          c = _cornerTable.swingRight(c);
        }
        continue;
      }

      var deduplicationFirstCorner = c;
      if (_isVertHole[v] == 0) {
        // Interior vertex with a seam, start at the first seam crossing.
        for (var i = 0; i < numAttrData; i++) {
          if (attVertexOnSeam[i][v] == 0) continue;
          final attC2V = attCornerToVertex[i];
          final vertId = attC2V[c];
          var actC = _cornerTable.swingRight(c);
          var seamFound = false;
          while (actC != c) {
            if (actC == -1) {
              throw dracoError('invalid connectivity');
            }
            if (attC2V[actC] != vertId) {
              deduplicationFirstCorner = actC;
              seamFound = true;
              break;
            }
            actC = _cornerTable.swingRight(actC);
          }
          if (seamFound) break;
        }
      }

      // Deduplication pass over the ring, clockwise.
      c = deduplicationFirstCorner;
      cornerToPointMap[c] = pointCount++;
      var prevC = c;
      c = _cornerTable.swingRight(c);
      while (c != -1 && c != deduplicationFirstCorner) {
        var attributeSeam = false;
        for (var i = 0; i < numAttrData; i++) {
          final attC2V = attCornerToVertex[i];
          if (attC2V[c] != attC2V[prevC]) {
            attributeSeam = true;
            break;
          }
        }
        cornerToPointMap[c] = attributeSeam
            ? pointCount++
            : cornerToPointMap[prevC];
        prevC = c;
        c = _cornerTable.swingRight(c);
      }
    }

    faces.setAll(0, cornerToPointMap);
    numPoints = pointCount;
  }

  MeshAttributeCornerTable? _attributeCornerTableFor(int attributeId) {
    for (final data in _attributeData) {
      if (data.decoderId < 0 || data.decoderId >= controllers.length) continue;
      if (controllers[data.decoderId].attributeIds.contains(attributeId)) {
        return data.isConnectivityUsed ? data.connectivityData : null;
      }
    }
    return null;
  }

  MeshAttributeIndicesEncodingData _attributeEncodingDataFor(int attributeId) {
    for (final data in _attributeData) {
      if (data.decoderId < 0 || data.decoderId >= controllers.length) continue;
      if (controllers[data.decoderId].attributeIds.contains(attributeId)) {
        return data.encodingData;
      }
    }
    return _posEncodingData;
  }

  @override
  PredictionSchemeDecoder? createMeshPredictionScheme(
    int method,
    PredictionTransform transform,
    int attributeId,
  ) {
    final encodingData = _attributeEncodingDataFor(attributeId);
    final attCornerTable = _attributeCornerTableFor(attributeId);
    final meshData = MeshPredictionSchemeData(
      attCornerTable ?? _cornerTable,
      encodingData.encodedValueIndexToCorner,
      encodingData.vertexToEncodedValueIndex,
    );
    return createMeshPredictionSchemeDecoder(method, transform, meshData);
  }

  @override
  AttributesDecoderController createAttributesController(int controllerId) {
    final attDataId = buffer.decodeInt8();
    final elementType = buffer.decodeUint8();
    if (attDataId >= 0) {
      if (attDataId >= _attributeData.length) {
        throw dracoError('invalid attribute data id');
      }
      if (_attributeData[attDataId].decoderId >= 0) {
        throw dracoError('duplicate attribute data id');
      }
      _attributeData[attDataId].decoderId = controllerId;
    } else {
      if (_posDataDecoderId >= 0) {
        throw dracoError('duplicate position attribute decoder');
      }
      _posDataDecoderId = controllerId;
    }

    final traversalMethod = buffer.decodeUint8();
    if (traversalMethod >= DracoTraversalMethod.count) {
      throw dracoError('unknown traversal method $traversalMethod');
    }

    final MeshAttributeIndicesEncodingData encodingData;
    final CornerTableView table;
    if (elementType == DracoMeshAttributeElementType.vertex) {
      if (attDataId < 0) {
        encodingData = _posEncodingData;
      } else {
        encodingData = _attributeData[attDataId].encodingData;
        _attributeData[attDataId].isConnectivityUsed = false;
      }
      table = _cornerTable;
    } else if (elementType == DracoMeshAttributeElementType.corner) {
      if (traversalMethod != DracoTraversalMethod.depthFirst || attDataId < 0) {
        throw dracoError('invalid corner attribute decoder');
      }
      encodingData = _attributeData[attDataId].encodingData;
      table = _attributeData[attDataId].connectivityData!;
    } else {
      throw dracoError('unsupported attribute element type $elementType');
    }

    final traverser = traversalMethod == DracoTraversalMethod.predictionDegree
        ? MaxPredictionDegreeTraverser()
        : DepthFirstTraverser();
    final sequencer = MeshTraversalSequencer(
      faces,
      numPoints,
      encodingData,
      traverser,
    );
    final observer = MeshAttributeIndicesEncodingObserver(
      faces,
      sequencer,
      encodingData,
    );
    traverser.init(table, observer);
    return AttributesDecoderController(sequencer);
  }
}
