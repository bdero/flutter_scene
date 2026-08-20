// Connectivity-based attribute prediction schemes for EdgeBreaker decoded
// meshes. See the Draco Bitstream Specification, "Parallelogram Prediction",
// "Multi Parallelogram Prediction", "Constrained Multi Parallelogram",
// "Texture Coordinates Prediction", and "Normal Prediction"
// (https://google.github.io/draco/spec/).

import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'attributes.dart';
import 'constants.dart';
import 'corner_table.dart';
import 'decoder_buffer.dart';
import 'prediction_schemes.dart';
import 'prediction_transforms.dart';
import 'rans.dart';

/// Mesh connectivity handed to a prediction scheme, the (possibly attribute)
/// corner table plus the traversal order maps.
class MeshPredictionSchemeData {
  MeshPredictionSchemeData(
    this.table,
    this.dataToCornerMap,
    this.vertexToDataMap,
  );

  final CornerTableView table;

  /// Encoded value index to the corner it was visited at.
  final Int32List dataToCornerMap;

  /// Vertex id to encoded value index.
  final Int32List vertexToDataMap;
}

/// Builds the mesh prediction scheme for [method], or null when the method has
/// no connectivity-based decoder (the caller falls back to delta prediction).
PredictionSchemeDecoder? createMeshPredictionSchemeDecoder(
  int method,
  PredictionTransform transform,
  MeshPredictionSchemeData meshData,
) {
  // Octahedral transforms pair only with geometric normal prediction; any
  // other method decodes as delta on the transformed values.
  final transformType = transform.type;
  if (transformType == DracoPredictionTransform.normalOctahedron ||
      transformType == DracoPredictionTransform.normalOctahedronCanonicalized) {
    if (method == DracoPredictionScheme.meshGeometricNormal) {
      return MeshPredictionSchemeGeometricNormalDecoder(
        transform as NormalOctahedronTransformBase,
        meshData,
      );
    }
    return null;
  }
  switch (method) {
    case DracoPredictionScheme.meshParallelogram:
      return MeshPredictionSchemeParallelogramDecoder(transform, meshData);
    case DracoPredictionScheme.meshMultiParallelogram:
      return MeshPredictionSchemeMultiParallelogramDecoder(transform, meshData);
    case DracoPredictionScheme.meshConstrainedMultiParallelogram:
      return MeshPredictionSchemeConstrainedMultiParallelogramDecoder(
        transform,
        meshData,
      );
    case DracoPredictionScheme.meshTexCoordsPortable:
      return MeshPredictionSchemeTexCoordsPortableDecoder(transform, meshData);
    case DracoPredictionScheme.meshTexCoordsDeprecated:
      throw dracoError('deprecated tex coords prediction is not supported');
    default:
      return null;
  }
}

/// Base for prediction scheme decoders that use mesh connectivity.
abstract class MeshPredictionSchemeDecoder extends PredictionSchemeDecoder {
  MeshPredictionSchemeDecoder(super.transform, this.meshData);

  final MeshPredictionSchemeData meshData;
}

/// Computes the parallelogram prediction (next + prev - opp across the
/// opposite face) into [outPrediction]. Returns false when any of the three
/// support values is not decoded yet.
bool _computeParallelogramPrediction(
  int dataEntryId,
  int ci,
  Int32List oppositeCorners,
  Int32List cornerToVertex,
  Int32List vertexToDataMap,
  Int32List inData,
  int numComponents,
  Int32List outPrediction,
) {
  final oci = oppositeCorners[ci];
  if (oci < 0) {
    return false;
  }
  final vertOpp = vertexToDataMap[cornerToVertex[oci]];
  final vertNext = vertexToDataMap[cornerToVertex[cornerNext(oci)]];
  final vertPrev = vertexToDataMap[cornerToVertex[cornerPrevious(oci)]];
  if (vertOpp < dataEntryId &&
      vertNext < dataEntryId &&
      vertPrev < dataEntryId) {
    final oOff = vertOpp * numComponents;
    final nOff = vertNext * numComponents;
    final pOff = vertPrev * numComponents;
    for (var c = 0; c < numComponents; c++) {
      // Int32List stores wrap like the reference decoder's int32 arithmetic.
      outPrediction[c] = inData[nOff + c] + inData[pOff + c] - inData[oOff + c];
    }
    return true;
  }
  return false;
}

/// Single parallelogram prediction across the opposite face, with a delta
/// fallback when the support is not yet decoded.
class MeshPredictionSchemeParallelogramDecoder
    extends MeshPredictionSchemeDecoder {
  MeshPredictionSchemeParallelogramDecoder(super.transform, super.meshData);

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    transform.init(numComponents);
    final table = meshData.table;
    final oppositeCorners = table.opposite;
    final cornerToVertex = table.cornerToVertex;
    final vertexToDataMap = meshData.vertexToDataMap;
    final dataToCornerMap = meshData.dataToCornerMap;
    final predVals = Int32List(numComponents);

    transform.computeOriginalValue(predVals, 0, corrections, 0, output, 0);

    for (var p = 1; p < dataToCornerMap.length; p++) {
      final cornerId = dataToCornerMap[p];
      final dstOffset = p * numComponents;
      if (_computeParallelogramPrediction(
        p,
        cornerId,
        oppositeCorners,
        cornerToVertex,
        vertexToDataMap,
        output,
        numComponents,
        predVals,
      )) {
        transform.computeOriginalValue(
          predVals,
          0,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      } else {
        // No parallelogram support, delta from the previous value.
        transform.computeOriginalValue(
          output,
          dstOffset - numComponents,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      }
    }
  }
}

/// Averaged parallelogram predictions from every opposite face around the
/// vertex.
class MeshPredictionSchemeMultiParallelogramDecoder
    extends MeshPredictionSchemeDecoder {
  MeshPredictionSchemeMultiParallelogramDecoder(
    super.transform,
    super.meshData,
  );

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    transform.init(numComponents);
    final table = meshData.table;
    final oppositeCorners = table.opposite;
    final cornerToVertex = table.cornerToVertex;
    final vertexToDataMap = meshData.vertexToDataMap;
    final dataToCornerMap = meshData.dataToCornerMap;
    final predVals = Int32List(numComponents);
    final parallelogramPredVals = Int32List(numComponents);

    transform.computeOriginalValue(predVals, 0, corrections, 0, output, 0);

    for (var p = 1; p < dataToCornerMap.length; p++) {
      final startCornerId = dataToCornerMap[p];
      var cornerId = startCornerId;
      var numParallelograms = 0;
      predVals.fillRange(0, numComponents, 0);

      while (cornerId != -1) {
        if (_computeParallelogramPrediction(
          p,
          cornerId,
          oppositeCorners,
          cornerToVertex,
          vertexToDataMap,
          output,
          numComponents,
          parallelogramPredVals,
        )) {
          for (var c = 0; c < numComponents; c++) {
            predVals[c] = predVals[c] + parallelogramPredVals[c];
          }
          numParallelograms++;
        }
        cornerId = table.swingRight(cornerId);
        if (cornerId == startCornerId) {
          cornerId = -1;
        }
      }

      final dstOffset = p * numComponents;
      if (numParallelograms == 0) {
        transform.computeOriginalValue(
          output,
          dstOffset - numComponents,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      } else {
        for (var c = 0; c < numComponents; c++) {
          predVals[c] = predVals[c] ~/ numParallelograms;
        }
        transform.computeOriginalValue(
          predVals,
          0,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      }
    }
  }
}

/// Multi parallelogram prediction constrained by encoded crease edge flags,
/// which select the parallelograms that contribute.
class MeshPredictionSchemeConstrainedMultiParallelogramDecoder
    extends MeshPredictionSchemeDecoder {
  MeshPredictionSchemeConstrainedMultiParallelogramDecoder(
    super.transform,
    super.meshData,
  );

  static const int _maxNumParallelograms = 4;

  /// Crease edge flags per context (available parallelogram count minus one).
  final List<Uint8List> _isCreaseEdge = List.filled(
    _maxNumParallelograms,
    Uint8List(0),
  );

  @override
  void decodePredictionData(DecoderBuffer buffer) {
    for (var i = 0; i < _maxNumParallelograms; i++) {
      final numFlags = buffer.decodeVarint();
      if (numFlags > meshData.table.numCorners) {
        throw dracoError('invalid crease edge flag count');
      }
      if (numFlags > 0) {
        final flags = Uint8List(numFlags);
        final decoder = RAnsBitDecoder()..startDecoding(buffer);
        for (var j = 0; j < numFlags; j++) {
          flags[j] = decoder.decodeNextBit() ? 1 : 0;
        }
        _isCreaseEdge[i] = flags;
      }
    }
    super.decodePredictionData(buffer);
  }

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    transform.init(numComponents);
    final table = meshData.table;
    final oppositeCorners = table.opposite;
    final cornerToVertex = table.cornerToVertex;
    final vertexToDataMap = meshData.vertexToDataMap;
    final dataToCornerMap = meshData.dataToCornerMap;

    final predVals = List.generate(
      _maxNumParallelograms,
      (_) => Int32List(numComponents),
    );
    final isCreaseEdgePos = Int32List(_maxNumParallelograms);
    final multiPredVals = Int32List(numComponents);

    transform.computeOriginalValue(predVals[0], 0, corrections, 0, output, 0);

    for (var p = 1; p < dataToCornerMap.length; p++) {
      final startCornerId = dataToCornerMap[p];
      var cornerId = startCornerId;
      var numParallelograms = 0;
      var firstPass = true;

      while (cornerId != -1) {
        if (_computeParallelogramPrediction(
          p,
          cornerId,
          oppositeCorners,
          cornerToVertex,
          vertexToDataMap,
          output,
          numComponents,
          predVals[numParallelograms],
        )) {
          numParallelograms++;
          if (numParallelograms == _maxNumParallelograms) break;
        }
        // Swing left first; on an open boundary continue right from the start.
        if (firstPass) {
          cornerId = table.swingLeft(cornerId);
        } else {
          cornerId = table.swingRight(cornerId);
        }
        if (cornerId == startCornerId) break;
        if (cornerId == -1 && firstPass) {
          firstPass = false;
          cornerId = table.swingRight(startCornerId);
        }
      }

      var numUsedParallelograms = 0;
      if (numParallelograms > 0) {
        multiPredVals.fillRange(0, numComponents, 0);
        final context = numParallelograms - 1;
        for (var i = 0; i < numParallelograms; i++) {
          final pos = isCreaseEdgePos[context]++;
          final flags = _isCreaseEdge[context];
          if (flags.length <= pos) {
            throw dracoError('crease edge flags exhausted');
          }
          if (flags[pos] == 0) {
            numUsedParallelograms++;
            for (var c = 0; c < numComponents; c++) {
              multiPredVals[c] = multiPredVals[c] + predVals[i][c];
            }
          }
        }
      }

      final dstOffset = p * numComponents;
      if (numUsedParallelograms == 0) {
        transform.computeOriginalValue(
          output,
          dstOffset - numComponents,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      } else {
        for (var c = 0; c < numComponents; c++) {
          multiPredVals[c] = multiPredVals[c] ~/ numUsedParallelograms;
        }
        transform.computeOriginalValue(
          multiPredVals,
          0,
          corrections,
          dstOffset,
          output,
          dstOffset,
        );
      }
    }
  }
}

/// Builds a flat int32 position cache in encoded value order, so predictors
/// read positions with one indexed load.
Int32List _buildPositionCache(
  PortableAttribute position,
  Int32List entryToPointIdMap,
  int numEntries,
) {
  final cache = Int32List(numEntries * 3);
  final data = position.data;
  for (var d = 0; d < numEntries; d++) {
    final src = position.mappedIndex(entryToPointIdMap[d]) * 3;
    final o = d * 3;
    cache[o] = data[src];
    cache[o + 1] = data[src + 1];
    cache[o + 2] = data[src + 2];
  }
  return cache;
}

/// UV prediction that projects the tip position onto the opposite edge and
/// carries the ratio into UV space (the portable tex coords predictor).
class MeshPredictionSchemeTexCoordsPortableDecoder
    extends MeshPredictionSchemeDecoder {
  MeshPredictionSchemeTexCoordsPortableDecoder(super.transform, super.meshData);

  PortableAttribute? _positionAttribute;
  Uint8List _orientations = Uint8List(0);
  int _numOrientations = 0;
  final Int32List _predictedValue = Int32List(2);

  @override
  int get numParentAttributes => 1;

  @override
  int parentAttributeType(int i) => DracoAttributeType.position;

  @override
  void setParentAttribute(PortableAttribute attribute) {
    if (attribute.attributeType != DracoAttributeType.position ||
        attribute.numComponents != 3) {
      throw dracoError('tex coords prediction needs int32 vec3 positions');
    }
    _positionAttribute = attribute;
  }

  @override
  void decodePredictionData(DecoderBuffer buffer) {
    final numOrientations = buffer.decodeInt32();
    if (numOrientations < 0) {
      throw dracoError('invalid orientation count');
    }
    _orientations = Uint8List(numOrientations);
    _numOrientations = numOrientations;
    var lastOrientation = true;
    final decoder = RAnsBitDecoder()..startDecoding(buffer);
    for (var i = 0; i < numOrientations; i++) {
      if (!decoder.decodeNextBit()) {
        lastOrientation = !lastOrientation;
      }
      _orientations[i] = lastOrientation ? 1 : 0;
    }
    super.decodePredictionData(buffer);
  }

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    if (numComponents != 2) {
      throw dracoError('tex coords prediction needs 2 components');
    }
    final position = _positionAttribute;
    if (position == null) {
      throw dracoError('missing position parent attribute');
    }
    transform.init(numComponents);
    final dataToCornerMap = meshData.dataToCornerMap;
    final posCache = _buildPositionCache(
      position,
      entryToPointIdMap,
      dataToCornerMap.length,
    );
    for (var p = 0; p < dataToCornerMap.length; p++) {
      final cornerId = dataToCornerMap[p];
      _computePredictedValue(cornerId, output, p, posCache);
      final dstOffset = p * 2;
      transform.computeOriginalValue(
        _predictedValue,
        0,
        corrections,
        dstOffset,
        output,
        dstOffset,
      );
    }
  }

  // Integer products stay exact as doubles below 2^53; larger ones take the
  // 64-bit exact path.
  static const int _safeProduct = 9007199254740992;
  static const double _int64Max = 9223372036854775807.0;

  void _computePredictedValue(
    int cornerId,
    Int32List data,
    int dataId,
    Int32List posCache,
  ) {
    final cornerToVertex = meshData.table.cornerToVertex;
    final vertexToDataMap = meshData.vertexToDataMap;
    final nextDataId = vertexToDataMap[cornerToVertex[cornerNext(cornerId)]];
    final prevDataId =
        vertexToDataMap[cornerToVertex[cornerPrevious(cornerId)]];

    if (prevDataId < dataId && nextDataId < dataId) {
      final nOff = nextDataId * 2;
      final pOff = prevDataId * 2;
      final nUV0 = data[nOff];
      final nUV1 = data[nOff + 1];
      final pUV0 = data[pOff];
      final pUV1 = data[pOff + 1];

      if (pUV0 == nUV0 && pUV1 == nUV1) {
        _predictedValue[0] = pUV0;
        _predictedValue[1] = pUV1;
        return;
      }

      var o = dataId * 3;
      final tip0 = posCache[o];
      final tip1 = posCache[o + 1];
      final tip2 = posCache[o + 2];
      o = nextDataId * 3;
      final next0 = posCache[o];
      final next1 = posCache[o + 1];
      final next2 = posCache[o + 2];
      o = prevDataId * 3;
      final prev0 = posCache[o];
      final prev1 = posCache[o + 1];
      final prev2 = posCache[o + 2];

      final pn0 = prev0 - next0;
      final pn1 = prev1 - next1;
      final pn2 = prev2 - next2;
      final pnNorm2 = pn0 * pn0 + pn1 * pn1 + pn2 * pn2;

      if (pnNorm2 != 0) {
        final cn0 = tip0 - next0;
        final cn1 = tip1 - next1;
        final cn2 = tip2 - next2;
        final cnDotPn = pn0 * cn0 + pn1 * cn1 + pn2 * cn2;
        final pnUV0 = pUV0 - nUV0;
        final pnUV1 = pUV1 - nUV1;

        final nUVAbsMax = nUV0.abs() > nUV1.abs() ? nUV0.abs() : nUV1.abs();
        if (nUVAbsMax > _int64Max / pnNorm2) {
          throw dracoError('tex coords prediction overflow');
        }
        final pnUVAbsMax = pnUV0.abs() > pnUV1.abs()
            ? pnUV0.abs()
            : pnUV1.abs();
        final cnDotPnAbs = cnDotPn.abs();
        if (pnUVAbsMax > 0 && cnDotPnAbs > _int64Max / pnUVAbsMax) {
          throw dracoError('tex coords prediction overflow');
        }

        var pnAbsMax = pn0.abs();
        if (pn1.abs() > pnAbsMax) pnAbsMax = pn1.abs();
        if (pn2.abs() > pnAbsMax) pnAbsMax = pn2.abs();
        final cnNorm2 = cn0 * cn0 + cn1 * cn1 + cn2 * cn2;
        if (cnNorm2 > _safeProduct / pnNorm2 ||
            nUVAbsMax > _safeProduct / pnNorm2 ||
            (pnUVAbsMax > 0 && cnDotPnAbs > _safeProduct / pnUVAbsMax) ||
            (pnAbsMax > 0 && cnDotPnAbs > _safeProduct / pnAbsMax)) {
          _computePredictedValueBig(
            tip0,
            tip1,
            tip2,
            next0,
            next1,
            next2,
            pn0,
            pn1,
            pn2,
            nUV0,
            nUV1,
            pUV0,
            pUV1,
            pnNorm2,
          );
          return;
        }

        final xUV0 = nUV0 * pnNorm2 + cnDotPn * pnUV0;
        final xUV1 = nUV1 * pnNorm2 + cnDotPn * pnUV1;
        if (pnAbsMax > 0 && cnDotPnAbs > _int64Max / pnAbsMax) {
          throw dracoError('tex coords prediction overflow');
        }

        final xPos0 = next0 + (cnDotPn * pn0) ~/ pnNorm2;
        final xPos1 = next1 + (cnDotPn * pn1) ~/ pnNorm2;
        final xPos2 = next2 + (cnDotPn * pn2) ~/ pnNorm2;
        final cx0 = tip0 - xPos0;
        final cx1 = tip1 - xPos1;
        final cx2 = tip2 - xPos2;
        final cxNorm2 = cx0 * cx0 + cx1 * cx1 + cx2 * cx2;

        // Rotated pnUV scaled by the projected distance.
        final normSquared = sqrt((cxNorm2 * pnNorm2).toDouble()).floor();
        final cxUV0 = pnUV1 * normSquared;
        final cxUV1 = -pnUV0 * normSquared;

        if (_numOrientations == 0) {
          throw dracoError('orientation bits exhausted');
        }
        final orientation = _orientations[--_numOrientations];
        if (orientation != 0) {
          _predictedValue[0] = (xUV0 + cxUV0) ~/ pnNorm2;
          _predictedValue[1] = (xUV1 + cxUV1) ~/ pnNorm2;
        } else {
          _predictedValue[0] = (xUV0 - cxUV0) ~/ pnNorm2;
          _predictedValue[1] = (xUV1 - cxUV1) ~/ pnNorm2;
        }
        return;
      }
    }

    // Fallback, delta coding.
    int dataOffset = 0;
    if (prevDataId < dataId) {
      dataOffset = prevDataId * 2;
    }
    if (nextDataId < dataId) {
      dataOffset = nextDataId * 2;
    } else {
      if (dataId > 0) {
        dataOffset = (dataId - 1) * 2;
      } else {
        _predictedValue[0] = 0;
        _predictedValue[1] = 0;
        return;
      }
    }
    _predictedValue[0] = data[dataOffset];
    _predictedValue[1] = data[dataOffset + 1];
  }

  static final BigInt _int64MaxBig = (BigInt.one << 63) - BigInt.one;

  // Floor of the integer square root, matching the reference IntSqrt.
  static BigInt _bigIntSqrt(BigInt value) {
    if (value < BigInt.two) return value;
    var x = value;
    var y = (x + BigInt.one) >> 1;
    while (y < x) {
      x = y;
      y = (x + value ~/ x) >> 1;
    }
    return x;
  }

  // 64-bit exact projection prediction, mirroring the reference decoder's
  // int64/uint64 arithmetic (including wraparound) for high quantization.
  void _computePredictedValueBig(
    int tip0,
    int tip1,
    int tip2,
    int next0,
    int next1,
    int next2,
    int pn0,
    int pn1,
    int pn2,
    int nUV0,
    int nUV1,
    int pUV0,
    int pUV1,
    int pnNorm2,
  ) {
    final tip = [BigInt.from(tip0), BigInt.from(tip1), BigInt.from(tip2)];
    final nxt = [BigInt.from(next0), BigInt.from(next1), BigInt.from(next2)];
    final pn = [BigInt.from(pn0), BigInt.from(pn1), BigInt.from(pn2)];
    final nUVb0 = BigInt.from(nUV0);
    final nUVb1 = BigInt.from(nUV1);
    final pnN2 = BigInt.from(pnNorm2);

    final cn0 = tip[0] - nxt[0];
    final cn1 = tip[1] - nxt[1];
    final cn2 = tip[2] - nxt[2];
    final cnDotPn = pn[0] * cn0 + pn[1] * cn1 + pn[2] * cn2;
    final pnUV0 = BigInt.from(pUV0) - nUVb0;
    final pnUV1 = BigInt.from(pUV1) - nUVb1;

    final nUVAbsMax = nUVb0.abs() > nUVb1.abs() ? nUVb0.abs() : nUVb1.abs();
    if (nUVAbsMax > _int64MaxBig ~/ pnN2) {
      throw dracoError('tex coords prediction overflow');
    }
    final pnUVAbsMax = pnUV0.abs() > pnUV1.abs() ? pnUV0.abs() : pnUV1.abs();
    if (pnUVAbsMax > BigInt.zero &&
        cnDotPn.abs() > _int64MaxBig ~/ pnUVAbsMax) {
      throw dracoError('tex coords prediction overflow');
    }

    final xUV0 = (nUVb0 * pnN2 + cnDotPn * pnUV0).toSigned(64);
    final xUV1 = (nUVb1 * pnN2 + cnDotPn * pnUV1).toSigned(64);

    var pnAbsMax = pn[0].abs();
    if (pn[1].abs() > pnAbsMax) pnAbsMax = pn[1].abs();
    if (pn[2].abs() > pnAbsMax) pnAbsMax = pn[2].abs();
    if (pnAbsMax > BigInt.zero && cnDotPn.abs() > _int64MaxBig ~/ pnAbsMax) {
      throw dracoError('tex coords prediction overflow');
    }

    final xPos0 = nxt[0] + (cnDotPn * pn[0]) ~/ pnN2;
    final xPos1 = nxt[1] + (cnDotPn * pn[1]) ~/ pnN2;
    final xPos2 = nxt[2] + (cnDotPn * pn[2]) ~/ pnN2;
    final cx0 = tip[0] - xPos0;
    final cx1 = tip[1] - xPos1;
    final cx2 = tip[2] - xPos2;
    final cxNorm2 = cx0 * cx0 + cx1 * cx1 + cx2 * cx2;

    // The multiply wraps in uint64 like the reference decoder.
    final normSquared = _bigIntSqrt((cxNorm2 * pnN2).toUnsigned(64));
    final cxUV0 = (pnUV1 * normSquared).toSigned(64);
    final cxUV1 = (-pnUV0 * normSquared).toSigned(64);

    if (_numOrientations == 0) {
      throw dracoError('orientation bits exhausted');
    }
    final orientation = _orientations[--_numOrientations];

    // Unsigned add or subtract, then a signed truncating divide and an int32
    // narrowing, matching the reference decoder exactly.
    BigInt s0;
    BigInt s1;
    if (orientation != 0) {
      s0 = (xUV0.toUnsigned(64) + cxUV0.toUnsigned(64)).toUnsigned(64);
      s1 = (xUV1.toUnsigned(64) + cxUV1.toUnsigned(64)).toUnsigned(64);
    } else {
      s0 = (xUV0.toUnsigned(64) - cxUV0.toUnsigned(64)).toUnsigned(64);
      s1 = (xUV1.toUnsigned(64) - cxUV1.toUnsigned(64)).toUnsigned(64);
    }
    _predictedValue[0] = (s0.toSigned(64) ~/ pnN2).toSigned(32).toInt();
    _predictedValue[1] = (s1.toSigned(64) ~/ pnN2).toSigned(32).toInt();
  }
}

/// Normal prediction from the surrounding triangle geometry, area weighted,
/// converted to octahedral coordinates.
class MeshPredictionSchemeGeometricNormalDecoder
    extends MeshPredictionSchemeDecoder {
  MeshPredictionSchemeGeometricNormalDecoder(
    NormalOctahedronTransformBase super.transform,
    super.meshData,
  );

  NormalOctahedronTransformBase get _octahedronTransform =>
      transform as NormalOctahedronTransformBase;
  final OctahedronToolBox _toolBox = OctahedronToolBox();
  final RAnsBitDecoder _flipNormalBitDecoder = RAnsBitDecoder();
  PortableAttribute? _positionAttribute;

  @override
  int get numParentAttributes => 1;

  @override
  int parentAttributeType(int i) => DracoAttributeType.position;

  @override
  void setParentAttribute(PortableAttribute attribute) {
    if (attribute.attributeType != DracoAttributeType.position ||
        attribute.numComponents != 3) {
      throw dracoError('normal prediction needs int32 vec3 positions');
    }
    _positionAttribute = attribute;
  }

  @override
  void decodePredictionData(DecoderBuffer buffer) {
    transform.decodeTransformData(buffer);
    _flipNormalBitDecoder.startDecoding(buffer);
  }

  // Predicted integer normals are clamped so their abs sum stays below this.
  static const int _upperBound = 1 << 29;

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    final position = _positionAttribute;
    if (position == null) {
      throw dracoError('missing position parent attribute');
    }
    _toolBox.setQuantizationBits(_octahedronTransform.quantizationBits);

    final dataToCornerMap = meshData.dataToCornerMap;
    final numEntries = dataToCornerMap.length;
    final posCache = _buildPositionCache(
      position,
      entryToPointIdMap,
      numEntries,
    );

    // Corner to position cache offset, folding the double indirection.
    final table = meshData.table;
    final cornerToVertex = table.cornerToVertex;
    final oppositeCorners = table.opposite;
    final vertexToDataMap = meshData.vertexToDataMap;
    final numCorners = table.numCorners;
    final cornerToOffset = Int32List(numCorners);
    for (var c = 0; c < numCorners; c++) {
      final v = cornerToVertex[c];
      cornerToOffset[c] = v < 0 ? -1 : vertexToDataMap[v] * 3;
    }

    final predNormal = Int32List(3);
    final predOct = Int32List(2);

    for (var dataId = 0; dataId < numEntries; dataId++) {
      final cornerId = dataToCornerMap[dataId];
      _computePredictedNormal(
        cornerId,
        posCache,
        cornerToOffset,
        oppositeCorners,
        predNormal,
      );
      _toolBox.canonicalizeIntegerVector(predNormal);
      if (_flipNormalBitDecoder.decodeNextBit()) {
        predNormal[0] = -predNormal[0];
        predNormal[1] = -predNormal[1];
        predNormal[2] = -predNormal[2];
      }
      _toolBox.integerVectorToQuantizedOctahedralCoords(predNormal, predOct);
      final dataOffset = dataId * 2;
      transform.computeOriginalValue(
        predOct,
        0,
        corrections,
        dataOffset,
        output,
        dataOffset,
      );
    }
  }

  // Sums the cross products of every triangle around the corner's vertex
  // (area weighting), visiting the ring left first and then right across an
  // open boundary.
  void _computePredictedNormal(
    int cornerId,
    Int32List posCache,
    Int32List cornerToOffset,
    Int32List oppositeCorners,
    Int32List prediction,
  ) {
    final centerOffset = cornerToOffset[cornerId];
    final centX = posCache[centerOffset];
    final centY = posCache[centerOffset + 1];
    final centZ = posCache[centerOffset + 2];

    var normalX = 0;
    var normalY = 0;
    var normalZ = 0;

    var currentCorner = cornerId;
    var leftTraversal = true;
    while (currentCorner >= 0) {
      final cNext = cornerNext(currentCorner);
      final cPrev = cornerPrevious(currentCorner);
      var posOffset = cornerToOffset[cNext];
      final dNextX = posCache[posOffset] - centX;
      final dNextY = posCache[posOffset + 1] - centY;
      final dNextZ = posCache[posOffset + 2] - centZ;
      posOffset = cornerToOffset[cPrev];
      final dPrevX = posCache[posOffset] - centX;
      final dPrevY = posCache[posOffset + 1] - centY;
      final dPrevZ = posCache[posOffset + 2] - centZ;

      normalX += dNextY * dPrevZ - dNextZ * dPrevY;
      normalY += dNextZ * dPrevX - dNextX * dPrevZ;
      normalZ += dNextX * dPrevY - dNextY * dPrevX;

      if (leftTraversal) {
        final opp = oppositeCorners[cNext];
        currentCorner = opp < 0 ? -1 : cornerNext(opp);
        if (currentCorner < 0) {
          // Open boundary reached, cover the other side from the start.
          final startOpp = oppositeCorners[cornerPrevious(cornerId)];
          currentCorner = startOpp < 0 ? -1 : cornerPrevious(startOpp);
          leftTraversal = false;
        } else if (currentCorner == cornerId) {
          currentCorner = -1; // Full ring visited.
        }
      } else {
        final opp = oppositeCorners[cPrev];
        currentCorner = opp < 0 ? -1 : cornerPrevious(opp);
      }
    }

    // Scale into the int32 range with a floored quotient and truncating
    // per-component division, matching the reference decoder.
    final absSum = normalX.abs() + normalY.abs() + normalZ.abs();
    if (absSum > _upperBound) {
      final quotient = absSum ~/ _upperBound;
      normalX = normalX ~/ quotient;
      normalY = normalY ~/ quotient;
      normalZ = normalZ ~/ quotient;
    }
    prediction[0] = normalX;
    prediction[1] = normalY;
    prediction[2] = normalZ;
  }
}
