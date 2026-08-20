// Draco mesh decoding driver, header parsing through attribute decode. See
// the Draco Bitstream Specification, "Draco Decoder" and "Connectivity
// Decoder" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attribute_decoders.dart';
import 'attributes.dart';
import 'constants.dart';
import 'decoder_buffer.dart';
import 'edgebreaker_decoder.dart';
import 'prediction_schemes.dart';
import 'prediction_transforms.dart';
import 'symbol_decoding.dart';

/// A fully decoded Draco triangle mesh.
class DracoDecodedMesh {
  DracoDecodedMesh(this.numPoints, this.numFaces, this.faces, this.attributes);

  final int numPoints;
  final int numFaces;

  /// Point indices, three per face.
  final Int32List faces;
  final List<DracoAttribute> attributes;

  DracoAttribute? attributeByUniqueId(int uniqueId) {
    for (final attribute in attributes) {
      if (attribute.uniqueId == uniqueId) {
        return attribute;
      }
    }
    return null;
  }
}

/// Decodes a complete Draco payload (as stored in a
/// `KHR_draco_mesh_compression` buffer view). Triangle meshes only; anything
/// outside the supported scope throws a [FormatException].
DracoDecodedMesh decodeDracoMesh(Uint8List data) {
  final buffer = DecoderBuffer(data);
  if (buffer.remainingSize < 11) {
    throw dracoError('stream truncated');
  }
  final magic = buffer.decodeBytes(5);
  if (magic[0] != 0x44 ||
      magic[1] != 0x52 ||
      magic[2] != 0x41 ||
      magic[3] != 0x43 ||
      magic[4] != 0x4F) {
    throw dracoError('not a Draco stream');
  }
  final versionMajor = buffer.decodeUint8();
  final versionMinor = buffer.decodeUint8();
  final encoderType = buffer.decodeUint8();
  final encoderMethod = buffer.decodeUint8();
  final flags = buffer.decodeUint16();

  if (encoderType != DracoGeometryType.triangularMesh) {
    throw dracoError('only triangle meshes are supported');
  }
  final version = dracoBitstreamVersion(versionMajor, versionMinor);
  if (version != dracoBitstreamVersion(2, 2)) {
    throw dracoError(
      'unsupported bitstream version $versionMajor.$versionMinor '
      '(only 2.2 is supported)',
    );
  }
  buffer.bitstreamVersion = version;
  if ((flags & dracoMetadataFlagMask) != 0) {
    throw dracoError('metadata is not supported');
  }

  final DracoMeshDecoder decoder;
  switch (encoderMethod) {
    case DracoMeshEncoderMethod.sequential:
      decoder = SequentialMeshDecoder(buffer);
    case DracoMeshEncoderMethod.edgebreaker:
      decoder = EdgebreakerMeshDecoder(buffer);
    default:
      throw dracoError('unknown mesh encoding method $encoderMethod');
  }
  // A corrupted stream that passes the explicit validity checks can still
  // drive connectivity indices out of range; surface that as a clean format
  // error rather than an index error.
  // TODO(draco-limits): allocation sizes are bounded only by the header
  // sanity checks (matching the reference decoder), so a crafted stream can
  // still demand large corner table allocations before failing. Cap them
  // against the payload size if that ever matters.
  try {
    return decoder.decode();
  } on RangeError {
    throw dracoError('malformed stream');
  } on ArgumentError {
    throw dracoError('malformed stream');
  }
}

/// Base driver shared by the sequential and EdgeBreaker mesh decoders.
abstract class DracoMeshDecoder implements DracoDecoderInterface {
  DracoMeshDecoder(this._buffer);

  DecoderBuffer _buffer;

  @override
  DecoderBuffer get buffer => _buffer;

  /// Replaces the active buffer (the EdgeBreaker decoder splits the stream).
  set buffer(DecoderBuffer value) {
    _buffer = value;
  }

  @override
  int numPoints = 0;

  int numFaces = 0;
  Int32List faces = Int32List(0);

  @override
  final List<DracoAttribute> attributes = [];

  final List<AttributesDecoderController> controllers = [];
  final List<int> _attributeToController = [];

  @override
  int addAttribute(DracoAttribute attribute) {
    attributes.add(attribute);
    return attributes.length - 1;
  }

  @override
  int namedAttributeId(int attributeType) {
    for (var i = 0; i < attributes.length; i++) {
      if (attributes[i].attributeType == attributeType) {
        return i;
      }
    }
    return -1;
  }

  @override
  PortableAttribute? portableAttributeFor(int attributeId) {
    if (attributeId < 0 || attributeId >= _attributeToController.length) {
      return null;
    }
    return controllers[_attributeToController[attributeId]].portableAttribute(
      attributeId,
    );
  }

  @override
  PredictionSchemeDecoder? createMeshPredictionScheme(
    int method,
    PredictionTransform transform,
    int attributeId,
  ) => null;

  DracoDecodedMesh decode() {
    decodeConnectivity();
    decodePointAttributes();
    return DracoDecodedMesh(numPoints, numFaces, faces, attributes);
  }

  void decodeConnectivity();

  AttributesDecoderController createAttributesController(int controllerId);

  void decodePointAttributes() {
    final numAttributesDecoders = buffer.decodeUint8();
    for (var i = 0; i < numAttributesDecoders; i++) {
      controllers.add(createAttributesController(i));
    }
    for (final controller in controllers) {
      controller.decodeAttributesDecoderData(buffer, this);
    }
    for (var i = 0; i < controllers.length; i++) {
      for (final attId in controllers[i].attributeIds) {
        while (_attributeToController.length <= attId) {
          _attributeToController.add(0);
        }
        _attributeToController[attId] = i;
      }
    }
    for (final controller in controllers) {
      controller.decodeAttributes(buffer, this);
    }
  }
}

/// Decodes sequential (uncompressed or delta-varint) connectivity. See the
/// Draco Bitstream Specification, "Sequential Connectivity Decoder".
class SequentialMeshDecoder extends DracoMeshDecoder {
  SequentialMeshDecoder(super.buffer);

  @override
  void decodeConnectivity() {
    numFaces = buffer.decodeVarint();
    numPoints = buffer.decodeVarint();
    if (numFaces > 0xFFFFFFFF ~/ 3) {
      throw dracoError('too many faces');
    }
    if (numFaces > buffer.remainingSize ~/ 3) {
      throw dracoError('face count exceeds stream size');
    }
    faces = Int32List(numFaces * 3);
    final connectivityMethod = buffer.decodeUint8();
    if (connectivityMethod == 0) {
      _decodeCompressedIndices();
    } else if (connectivityMethod == 1) {
      _decodeUncompressedIndices();
    } else {
      throw dracoError('unknown sequential connectivity method');
    }
  }

  void _decodeCompressedIndices() {
    final numIndices = numFaces * 3;
    final symbols = Uint32List(numIndices);
    decodeSymbols(numIndices, 1, buffer, symbols);
    // Indices are coded as zigzag deltas from the previous index.
    var last = 0;
    for (var i = 0; i < numIndices; i++) {
      final encoded = symbols[i];
      var delta = encoded >> 1;
      if ((encoded & 1) != 0) {
        if (delta > last) {
          throw dracoError('negative index');
        }
        delta = -delta;
      } else if (delta > 0x7FFFFFFF - last) {
        throw dracoError('index overflow');
      }
      last += delta;
      faces[i] = last;
    }
  }

  void _decodeUncompressedIndices() {
    final numIndices = numFaces * 3;
    if (numPoints < 256) {
      for (var i = 0; i < numIndices; i++) {
        faces[i] = buffer.decodeUint8();
      }
    } else if (numPoints < (1 << 16)) {
      for (var i = 0; i < numIndices; i++) {
        faces[i] = buffer.decodeUint16();
      }
    } else if (numPoints < (1 << 21)) {
      for (var i = 0; i < numIndices; i++) {
        faces[i] = buffer.decodeVarint();
      }
    } else {
      for (var i = 0; i < numIndices; i++) {
        faces[i] = buffer.decodeUint32();
      }
    }
  }

  @override
  AttributesDecoderController createAttributesController(int controllerId) =>
      AttributesDecoderController(LinearSequencer(numPoints));
}
