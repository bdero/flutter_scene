// Sequential attribute decoders and their controller. See the Draco Bitstream
// Specification, "Attributes Decoder", "Sequential Integer Attribute Decoder",
// "Sequential Quantization Attribute Decoder", and "Sequential Normal
// Attribute Decoder" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attributes.dart';
import 'constants.dart';
import 'decoder_buffer.dart';
import 'prediction_schemes.dart';
import 'prediction_transforms.dart';
import 'symbol_decoding.dart';

/// The subset of the mesh decoder the attribute layer needs.
abstract class DracoDecoderInterface {
  DecoderBuffer get buffer;
  int get numPoints;
  List<DracoAttribute> get attributes;
  int addAttribute(DracoAttribute attribute);
  int namedAttributeId(int attributeType);
  PortableAttribute? portableAttributeFor(int attributeId);

  /// Builds a connectivity-based prediction scheme, or null when the method
  /// has none (the caller falls back to delta prediction).
  PredictionSchemeDecoder? createMeshPredictionScheme(
    int method,
    PredictionTransform transform,
    int attributeId,
  );
}

/// Produces the value decode order and the point to value mapping.
abstract class PointsSequencer {
  Int32List generateSequence();

  /// Installs the point to attribute value index mapping on [attribute].
  void updatePointToAttributeIndexMapping(DracoAttribute attribute);
}

/// Identity sequencer used by sequential connectivity.
class LinearSequencer implements PointsSequencer {
  LinearSequencer(this.numPoints);

  final int numPoints;

  @override
  Int32List generateSequence() {
    final ids = Int32List(numPoints);
    for (var i = 0; i < numPoints; i++) {
      ids[i] = i;
    }
    return ids;
  }

  @override
  void updatePointToAttributeIndexMapping(DracoAttribute attribute) {
    attribute.indicesMap = null; // Identity.
  }
}

/// One attributes decoder from the bitstream, driving a set of sequential
/// attribute decoders that share a sequencer.
class AttributesDecoderController {
  AttributesDecoderController(this.sequencer);

  final PointsSequencer sequencer;
  final List<int> attributeIds = [];
  final List<_SequentialAttributeDecoder> _decoders = [];
  Int32List _pointIds = Int32List(0);

  int get numAttributes => attributeIds.length;

  void decodeAttributesDecoderData(
    DecoderBuffer buffer,
    DracoDecoderInterface decoder,
  ) {
    final numAttributes = buffer.decodeVarint();
    if (numAttributes == 0) {
      throw dracoError('attributes decoder declares no attributes');
    }
    if (numAttributes > 5 * buffer.remainingSize) {
      throw dracoError('unreasonable attribute count');
    }
    for (var i = 0; i < numAttributes; i++) {
      final attType = buffer.decodeUint8();
      final dataType = buffer.decodeUint8();
      final numComponents = buffer.decodeUint8();
      final normalized = buffer.decodeUint8();
      if (attType >= DracoAttributeType.namedAttributesCount) {
        throw dracoError('invalid attribute type $attType');
      }
      if (dataType == DracoDataType.invalid ||
          dataType >= DracoDataType.typesCount) {
        throw dracoError('invalid attribute data type $dataType');
      }
      if (numComponents == 0) {
        throw dracoError('attribute has zero components');
      }
      final uniqueId = buffer.decodeVarint();
      final attribute = DracoAttribute(
        attributeType: attType,
        dataType: dataType,
        numComponents: numComponents,
        normalized: normalized > 0,
        uniqueId: uniqueId,
      );
      attributeIds.add(decoder.addAttribute(attribute));
    }
    // Per-attribute sequential decoder types.
    for (var i = 0; i < numAttributes; i++) {
      final decoderType = buffer.decodeUint8();
      final sequential = _createSequentialDecoder(decoderType);
      sequential.init(decoder, attributeIds[i]);
      _decoders.add(sequential);
    }
  }

  _SequentialAttributeDecoder _createSequentialDecoder(int decoderType) {
    switch (decoderType) {
      case DracoSequentialAttributeEncoderType.generic:
        return _SequentialAttributeDecoder();
      case DracoSequentialAttributeEncoderType.integer:
        return _SequentialIntegerAttributeDecoder();
      case DracoSequentialAttributeEncoderType.quantization:
        return _SequentialQuantizationAttributeDecoder();
      case DracoSequentialAttributeEncoderType.normals:
        return _SequentialNormalAttributeDecoder();
      default:
        throw dracoError('unknown sequential decoder type $decoderType');
    }
  }

  void decodeAttributes(DecoderBuffer buffer, DracoDecoderInterface decoder) {
    _pointIds = sequencer.generateSequence();
    for (final attId in attributeIds) {
      sequencer.updatePointToAttributeIndexMapping(decoder.attributes[attId]);
    }
    for (final sequential in _decoders) {
      sequential.decodePortableAttribute(_pointIds, buffer);
    }
    for (final sequential in _decoders) {
      sequential.decodeDataNeededByPortableTransform(_pointIds, buffer);
    }
    for (final sequential in _decoders) {
      sequential.transformAttributeToOriginalFormat(_pointIds);
    }
  }

  PortableAttribute? portableAttribute(int attributeId) {
    for (var i = 0; i < attributeIds.length; i++) {
      if (attributeIds[i] == attributeId) {
        return _decoders[i].portableAttributeWithMapping();
      }
    }
    return null;
  }
}

/// Generic sequential decoder, values stored raw in the original format.
class _SequentialAttributeDecoder {
  late DracoDecoderInterface decoder;
  late DracoAttribute attribute;
  int attributeId = -1;
  PortableAttribute? portable;

  void init(DracoDecoderInterface decoder, int attributeId) {
    this.decoder = decoder;
    this.attributeId = attributeId;
    attribute = decoder.attributes[attributeId];
  }

  void decodePortableAttribute(Int32List pointIds, DecoderBuffer buffer) {
    if (attribute.numComponents <= 0) {
      throw dracoError('attribute has zero components');
    }
    attribute.reset(pointIds.length);
    decodeValues(pointIds, buffer);
  }

  void decodeValues(Int32List pointIds, DecoderBuffer buffer) {
    final entrySize = attribute.byteStride;
    final numValues = pointIds.length;
    final out = attribute.bytes;
    var outPos = 0;
    for (var i = 0; i < numValues; i++) {
      final value = buffer.decodeBytes(entrySize);
      out.setRange(outPos, outPos + entrySize, value);
      outPos += entrySize;
    }
  }

  void decodeDataNeededByPortableTransform(
    Int32List pointIds,
    DecoderBuffer buffer,
  ) {}

  void transformAttributeToOriginalFormat(Int32List pointIds) {}

  /// The portable attribute carrying the final attribute's point mapping,
  /// for use as a prediction parent.
  PortableAttribute? portableAttributeWithMapping() {
    final p = portable;
    if (p != null && p.indicesMap == null && attribute.indicesMap != null) {
      p.indicesMap = attribute.indicesMap;
    }
    return p;
  }

  void initPredictionScheme(PredictionSchemeDecoder scheme) {
    for (var i = 0; i < scheme.numParentAttributes; i++) {
      final attId = decoder.namedAttributeId(scheme.parentAttributeType(i));
      if (attId == -1) {
        throw dracoError('missing prediction parent attribute');
      }
      final parent = decoder.portableAttributeFor(attId);
      if (parent == null) {
        throw dracoError('prediction parent attribute not decoded');
      }
      scheme.setParentAttribute(parent);
    }
  }
}

/// Integer attribute decoder with entropy coding and prediction.
class _SequentialIntegerAttributeDecoder extends _SequentialAttributeDecoder {
  PredictionSchemeDecoder? _predictionScheme;

  int get numValueComponents => attribute.numComponents;

  PredictionSchemeDecoder? _createIntPredictionScheme(
    int method,
    int transformType,
  ) {
    if (transformType != DracoPredictionTransform.wrap) {
      throw dracoError('unsupported prediction transform $transformType');
    }
    final transform = WrapTransform();
    return decoder.createMeshPredictionScheme(method, transform, attributeId) ??
        DeltaPredictionDecoder(transform);
  }

  @override
  void decodeValues(Int32List pointIds, DecoderBuffer buffer) {
    final method = buffer.decodeInt8();
    if (method < DracoPredictionScheme.none ||
        method >= DracoPredictionScheme.count) {
      throw dracoError('invalid prediction method $method');
    }
    if (method != DracoPredictionScheme.none) {
      final transformType = buffer.decodeInt8();
      if (transformType < DracoPredictionTransform.none ||
          transformType >= DracoPredictionTransform.count) {
        throw dracoError('invalid prediction transform $transformType');
      }
      _predictionScheme = _createIntPredictionScheme(method, transformType);
    }
    final scheme = _predictionScheme;
    if (scheme != null) {
      initPredictionScheme(scheme);
    }
    _decodeIntegerValues(pointIds, buffer);
  }

  void _decodeIntegerValues(Int32List pointIds, DecoderBuffer buffer) {
    final numComponents = numValueComponents;
    if (numComponents <= 0) {
      throw dracoError('attribute has zero components');
    }
    final numEntries = pointIds.length;
    final numValues = numEntries * numComponents;
    final p = PortableAttribute(
      attribute.attributeType,
      numComponents,
      numEntries,
    );
    portable = p;
    final data = p.data;

    final compressed = buffer.decodeUint8();
    if (compressed > 0) {
      final asUint32 = Uint32List.view(
        data.buffer,
        data.offsetInBytes,
        numValues,
      );
      decodeSymbols(numValues, numComponents, buffer, asUint32);
    } else {
      final numBytes = buffer.decodeUint8();
      if (numBytes == 4) {
        final bytes = buffer.decodeBytes(4 * numValues);
        final view = ByteData.sublistView(bytes);
        for (var i = 0; i < numValues; i++) {
          data[i] = view.getInt32(i * 4, Endian.little);
        }
      } else {
        if (numBytes < 1 ||
            numBytes > 4 ||
            buffer.remainingSize < numBytes * numValues) {
          throw dracoError('invalid integer attribute encoding');
        }
        for (var i = 0; i < numValues; i++) {
          var value = 0;
          for (var b = 0; b < numBytes; b++) {
            value |= buffer.decodeUint8() << (b * 8);
          }
          data[i] = value;
        }
      }
    }

    final scheme = _predictionScheme;
    if (numValues > 0 && (scheme == null || !scheme.areCorrectionsPositive)) {
      // Zigzag decode in place; read through a uint32 view so the stored
      // two's complement bits convert like the reference decoder.
      final asUint32 = Uint32List.view(
        data.buffer,
        data.offsetInBytes,
        numValues,
      );
      for (var i = 0; i < numValues; i++) {
        data[i] = symbolToSignedInt(asUint32[i]);
      }
    }

    if (scheme != null) {
      scheme.decodePredictionData(buffer);
      if (numValues > 0) {
        scheme.computeOriginalValues(
          data,
          data,
          numValues,
          numComponents,
          pointIds,
        );
      }
    }
  }

  @override
  void transformAttributeToOriginalFormat(Int32List pointIds) {
    _storeValues(pointIds.length);
  }

  void _storeValues(int numValues) {
    final data = portable!.data;
    final total = numValues * attribute.numComponents;
    final bytes = attribute.bytes;
    // Typed-list stores truncate to the element width, matching the reference
    // decoder's per-type coercion.
    final List<int> out;
    switch (attribute.dataType) {
      case DracoDataType.uint8:
        out = bytes;
      case DracoDataType.int8:
        out = Int8List.view(bytes.buffer, bytes.offsetInBytes, total);
      case DracoDataType.uint16:
        out = Uint16List.view(bytes.buffer, bytes.offsetInBytes, total);
      case DracoDataType.int16:
        out = Int16List.view(bytes.buffer, bytes.offsetInBytes, total);
      case DracoDataType.uint32:
        out = Uint32List.view(bytes.buffer, bytes.offsetInBytes, total);
      case DracoDataType.int32:
        out = Int32List.view(bytes.buffer, bytes.offsetInBytes, total);
      default:
        throw dracoError(
          'unsupported integer attribute data type ${attribute.dataType}',
        );
    }
    for (var i = 0; i < total; i++) {
      out[i] = data[i];
    }
  }
}

/// Quantized float attribute decoder.
class _SequentialQuantizationAttributeDecoder
    extends _SequentialIntegerAttributeDecoder {
  final AttributeQuantizationTransform _quantization =
      AttributeQuantizationTransform();

  @override
  void init(DracoDecoderInterface decoder, int attributeId) {
    super.init(decoder, attributeId);
    if (attribute.dataType != DracoDataType.float32) {
      throw dracoError('quantized attribute is not float32');
    }
  }

  @override
  void decodeDataNeededByPortableTransform(
    Int32List pointIds,
    DecoderBuffer buffer,
  ) {
    _quantization.decodeParameters(portable!.numComponents, buffer);
  }

  @override
  void _storeValues(int numValues) {
    _quantization.inverseTransform(portable!, attribute);
  }
}

/// Octahedron-coded normal attribute decoder.
class _SequentialNormalAttributeDecoder
    extends _SequentialIntegerAttributeDecoder {
  final AttributeOctahedronTransform _octahedron =
      AttributeOctahedronTransform();

  @override
  void init(DracoDecoderInterface decoder, int attributeId) {
    super.init(decoder, attributeId);
    if (attribute.numComponents != 3 ||
        attribute.dataType != DracoDataType.float32) {
      throw dracoError('normal attribute is not 3 float32 components');
    }
  }

  @override
  int get numValueComponents => 2;

  @override
  PredictionSchemeDecoder? _createIntPredictionScheme(
    int method,
    int transformType,
  ) {
    final PredictionTransform transform;
    switch (transformType) {
      case DracoPredictionTransform.normalOctahedron:
        transform = NormalOctahedronTransform();
      case DracoPredictionTransform.normalOctahedronCanonicalized:
        transform = NormalOctahedronCanonicalizedTransform();
      default:
        throw dracoError(
          'unsupported normal prediction transform $transformType',
        );
    }
    return decoder.createMeshPredictionScheme(method, transform, attributeId) ??
        DeltaPredictionDecoder(transform);
  }

  @override
  void decodeDataNeededByPortableTransform(
    Int32List pointIds,
    DecoderBuffer buffer,
  ) {
    _octahedron.decodeParameters(buffer);
  }

  @override
  void _storeValues(int numValues) {
    _octahedron.inverseTransform(portable!, attribute);
  }
}
