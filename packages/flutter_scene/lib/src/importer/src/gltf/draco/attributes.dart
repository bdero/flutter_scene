// Decoded attribute storage plus the quantization and octahedron attribute
// transforms. See the Draco Bitstream Specification, "Attributes Decoder",
// "Sequential Quantization Attribute Decoder", and "Sequential Normal
// Attribute Decoder" (https://google.github.io/draco/spec/).

import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'constants.dart';
import 'decoder_buffer.dart';

/// A decoded point attribute in its final (original) format.
class DracoAttribute {
  DracoAttribute({
    required this.attributeType,
    required this.dataType,
    required this.numComponents,
    required this.normalized,
    required this.uniqueId,
  }) : componentBytes = DracoDataType.byteLength(dataType) {
    if (componentBytes <= 0) {
      throw dracoError('unsupported attribute data type $dataType');
    }
  }

  final int attributeType;
  final int dataType;
  final int numComponents;
  final bool normalized;
  final int uniqueId;
  final int componentBytes;

  int get byteStride => componentBytes * numComponents;

  /// Number of unique attribute values.
  int size = 0;

  /// Final attribute values, [size] * [byteStride] bytes, little-endian.
  Uint8List bytes = Uint8List(0);

  /// Point index to value index map; null means identity.
  Uint32List? indicesMap;

  void reset(int numValues) {
    size = numValues;
    bytes = Uint8List(numValues * byteStride);
  }

  int mappedIndex(int pointIndex) =>
      indicesMap == null ? pointIndex : indicesMap![pointIndex];

  /// The attribute values gathered into point order, [numPoints] entries of
  /// [byteStride] bytes each.
  Uint8List pointBytes(int numPoints) {
    final map = indicesMap;
    if (map == null) {
      if (size < numPoints) {
        throw dracoError('attribute has fewer values than points');
      }
      return size == numPoints
          ? bytes
          : Uint8List.sublistView(bytes, 0, numPoints * byteStride);
    }
    if (map.length < numPoints) {
      throw dracoError('attribute mapping has fewer entries than points');
    }
    final stride = byteStride;
    final out = Uint8List(numPoints * stride);
    for (var i = 0; i < numPoints; i++) {
      final value = map[i];
      if (value >= size) {
        throw dracoError('attribute mapping out of range');
      }
      out.setRange(i * stride, (i + 1) * stride, bytes, value * stride);
    }
    return out;
  }
}

/// A losslessly decoded portable attribute (int32 values), used as prediction
/// parent input and as the source for the final attribute transform.
class PortableAttribute {
  PortableAttribute(this.attributeType, this.numComponents, int numValues)
    : size = numValues,
      data = Int32List(numValues * numComponents);

  final int attributeType;
  final int numComponents;
  final int size;
  final Int32List data;

  /// Point index to value index map; null means identity.
  Uint32List? indicesMap;

  int mappedIndex(int pointIndex) =>
      indicesMap == null ? pointIndex : indicesMap![pointIndex];
}

/// Dequantizes portable int32 values back to float32.
class AttributeQuantizationTransform {
  int quantizationBits = -1;
  Float32List minValues = Float32List(0);
  double range = 0;

  void decodeParameters(int numComponents, DecoderBuffer buffer) {
    minValues = Float32List(numComponents);
    for (var i = 0; i < numComponents; i++) {
      minValues[i] = buffer.decodeFloat32();
    }
    range = buffer.decodeFloat32();
    final qBits = buffer.decodeUint8();
    if (qBits < 1 || qBits > 30) {
      throw dracoError('invalid quantization bits $qBits');
    }
    quantizationBits = qBits;
  }

  void inverseTransform(PortableAttribute source, DracoAttribute target) {
    if (target.dataType != DracoDataType.float32) {
      throw dracoError('quantized attribute must dequantize to float32');
    }
    final maxQuantizedValue = (1 << quantizationBits) - 1;
    // C++ computes delta in float32; every arithmetic step below rounds to
    // float32 so output matches the reference decoder bit for bit.
    final delta = toFloat32(range / toFloat32(maxQuantizedValue.toDouble()));
    final numComponents = target.numComponents;
    final total = target.size * numComponents;
    final src = source.data;
    final dst = Float32List.view(
      target.bytes.buffer,
      target.bytes.offsetInBytes,
      total,
    );
    var o = 0;
    for (var i = 0; i < target.size; i++) {
      for (var c = 0; c < numComponents; c++) {
        dst[o] = toFloat32(toFloat32(src[o].toDouble()) * delta) + minValues[c];
        o++;
      }
    }
  }
}

/// Octahedral coordinate helpers shared by the normal attribute transform and
/// the geometric normal prediction scheme.
class OctahedronToolBox {
  int quantizationBits = -1;
  int maxQuantizedValue = -1;
  int maxValue = -1;
  double _dequantizationScale = 1.0;
  int centerValue = -1;

  bool get isInitialized => quantizationBits != -1;

  void setQuantizationBits(int q) {
    if (q < 2 || q > 30) {
      throw dracoError('invalid octahedron quantization bits $q');
    }
    quantizationBits = q;
    maxQuantizedValue = (1 << q) - 1;
    maxValue = maxQuantizedValue - 1;
    _dequantizationScale = toFloat32(2.0 / toFloat32(maxValue.toDouble()));
    centerValue = maxValue ~/ 2;
  }

  /// Canonicalizes edge points into consistent quadrants (in place on [out]).
  void canonicalizeOctahedralCoords(int s, int t, Int32List out) {
    if ((s == 0 && t == 0) ||
        (s == 0 && t == maxValue) ||
        (s == maxValue && t == 0)) {
      s = maxValue;
      t = maxValue;
    } else if (s == 0 && t > centerValue) {
      t = centerValue - (t - centerValue);
    } else if (s == maxValue && t < centerValue) {
      t = centerValue + (centerValue - t);
    } else if (t == maxValue && s < centerValue) {
      s = centerValue + (centerValue - s);
    } else if (t == 0 && s > centerValue) {
      s = centerValue - (s - centerValue);
    }
    out[0] = s;
    out[1] = t;
  }

  /// Converts an integer vector whose abs sum equals [centerValue] into
  /// quantized octahedral coordinates.
  void integerVectorToQuantizedOctahedralCoords(
    Int32List intVec,
    Int32List out,
  ) {
    int s;
    int t;
    if (intVec[0] >= 0) {
      s = intVec[1] + centerValue;
      t = intVec[2] + centerValue;
    } else {
      s = intVec[1] < 0 ? intVec[2].abs() : maxValue - intVec[2].abs();
      t = intVec[2] < 0 ? intVec[1].abs() : maxValue - intVec[1].abs();
    }
    canonicalizeOctahedralCoords(s, t, out);
  }

  /// Scales [vec] (in place) so its abs sum equals [centerValue].
  void canonicalizeIntegerVector(Int32List vec) {
    final absSum = vec[0].abs() + vec[1].abs() + vec[2].abs();
    if (absSum == 0) {
      vec[0] = centerValue;
    } else {
      vec[0] = (vec[0] * centerValue) ~/ absSum;
      vec[1] = (vec[1] * centerValue) ~/ absSum;
      if (vec[2] >= 0) {
        vec[2] = centerValue - vec[0].abs() - vec[1].abs();
      } else {
        vec[2] = -(centerValue - vec[0].abs() - vec[1].abs());
      }
    }
  }

  /// Converts quantized octahedral coordinates to a float32 unit vector.
  void quantizedOctahedralCoordsToUnitVector(
    int inS,
    int inT,
    Float32List outVector,
  ) {
    _octahedralCoordsToUnitVector(
      toFloat32(
        toFloat32(toFloat32(inS.toDouble()) * _dequantizationScale) - 1.0,
      ),
      toFloat32(
        toFloat32(toFloat32(inT.toDouble()) * _dequantizationScale) - 1.0,
      ),
      outVector,
    );
  }

  void _octahedralCoordsToUnitVector(
    double inSScaled,
    double inTScaled,
    Float32List outVector,
  ) {
    var y = inSScaled;
    var z = inTScaled;
    final x = toFloat32(toFloat32(1.0 - y.abs()) - z.abs());
    var xOffset = -x;
    if (xOffset < 0) xOffset = 0;
    y = toFloat32(y + (y < 0 ? xOffset : -xOffset));
    z = toFloat32(z + (z < 0 ? xOffset : -xOffset));
    final normSquared = toFloat32(
      toFloat32(toFloat32(x * x) + toFloat32(y * y)) + toFloat32(z * z),
    );
    if (normSquared < 1e-6) {
      outVector[0] = 0;
      outVector[1] = 0;
      outVector[2] = 0;
    } else {
      final d = toFloat32(1.0 / toFloat32(sqrt(normSquared)));
      outVector[0] = toFloat32(x * d);
      outVector[1] = toFloat32(y * d);
      outVector[2] = toFloat32(z * d);
    }
  }
}

/// Converts portable octahedral coordinates back to float32 unit normals.
class AttributeOctahedronTransform {
  int quantizationBits = -1;

  void decodeParameters(DecoderBuffer buffer) {
    quantizationBits = buffer.decodeUint8();
  }

  void inverseTransform(PortableAttribute source, DracoAttribute target) {
    if (target.dataType != DracoDataType.float32 || target.numComponents != 3) {
      throw dracoError('octahedron attribute must decode to 3 float32');
    }
    final toolBox = OctahedronToolBox()..setQuantizationBits(quantizationBits);
    final numPoints = target.size;
    final src = source.data;
    final dst = Float32List.view(
      target.bytes.buffer,
      target.bytes.offsetInBytes,
      numPoints * 3,
    );
    final outVec = Float32List(3);
    var si = 0;
    var di = 0;
    for (var i = 0; i < numPoints; i++) {
      toolBox.quantizedOctahedralCoordsToUnitVector(
        src[si],
        src[si + 1],
        outVec,
      );
      si += 2;
      dst[di] = outVec[0];
      dst[di + 1] = outVec[1];
      dst[di + 2] = outVec[2];
      di += 3;
    }
  }
}
