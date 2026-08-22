// Bridges KHR_draco_mesh_compression primitives into the glTF data model by
// decoding the payload and synthesizing in-memory buffer views for the
// decoded output, so downstream accessor readers stay unchanged.

import 'dart:typed_data';

import '../types.dart';
import 'constants.dart';
import 'decoder_buffer.dart';
import 'mesh_decoder.dart';

/// Accessor, buffer view, and buffer data substitutes for one decoded Draco
/// primitive. The primitive's accessor indices stay valid; the accessors for
/// compressed attributes and indices are repointed at synthesized views over
/// [bufferData].
class DracoPrimitiveData {
  DracoPrimitiveData(this.accessors, this.bufferViews, this.bufferData);

  final List<GltfAccessor> accessors;
  final List<GltfBufferView> bufferViews;
  final Uint8List bufferData;
}

/// Decodes [primitive]'s `KHR_draco_mesh_compression` payload and returns
/// substitute accessor tables describing the decoded data.
///
/// Counts and layout are validated against the decoded output only; the
/// original accessors supply component type expectations and normalization
/// metadata, and their buffer views (legitimately absent) are ignored.
/// Throws [FormatException] on malformed or out-of-scope payloads.
DracoPrimitiveData decodeDracoPrimitive({
  required GltfMeshPrimitive primitive,
  required List<GltfAccessor> accessors,
  required List<GltfBufferView> bufferViews,
  required Uint8List bufferData,
}) {
  final draco = primitive.draco;
  if (draco == null) {
    throw const FormatException('Primitive is not Draco compressed');
  }
  if (draco.bufferView < 0 || draco.bufferView >= bufferViews.length) {
    throw const FormatException('Draco buffer view is out of range');
  }
  final payloadView = bufferViews[draco.bufferView];
  if (payloadView.byteOffset + payloadView.byteLength > bufferData.length) {
    throw const FormatException('Draco buffer view is out of range');
  }
  final payload = Uint8List.sublistView(
    bufferData,
    payloadView.byteOffset,
    payloadView.byteOffset + payloadView.byteLength,
  );
  final decoded = decodeDracoMesh(payload);

  final outAccessors = List.of(accessors);
  final outViews = List.of(bufferViews);
  final builder = BytesBuilder(copy: false);

  // Attributes outside the extension keep their own (fallback) storage, and
  // morph target accessors always do (the extension compresses only the base
  // attributes), so the synthesized buffer must retain the original bytes
  // ahead of the decoded sections for their views to stay valid.
  var hasFallbackAttribute = false;
  for (final entry in primitive.attributes.entries) {
    if (draco.attributes.containsKey(entry.key)) continue;
    if (accessors[entry.value].bufferView == null) {
      throw FormatException(
        'Attribute ${entry.key} has no buffer view and no Draco data',
      );
    }
    hasFallbackAttribute = true;
  }
  if (hasFallbackAttribute || primitive.targets.isNotEmpty) {
    builder.add(bufferData);
    final pad = (4 - bufferData.length % 4) % 4;
    if (pad != 0) {
      builder.add(Uint8List(pad));
    }
  }

  int addView(Uint8List bytes) {
    final offset = builder.length;
    builder.add(bytes);
    // Keep every section 4-byte aligned.
    final pad = (4 - bytes.length % 4) % 4;
    if (pad != 0) {
      builder.add(Uint8List(pad));
    }
    outViews.add(
      GltfBufferView(buffer: 0, byteLength: bytes.length, byteOffset: offset),
    );
    return outViews.length - 1;
  }

  // Indices. The extension requires indexed triangles; the decoded faces
  // replace the index accessor's (possibly absent) storage.
  final indicesIndex = primitive.indices;
  if (indicesIndex == null) {
    throw const FormatException('Draco compressed primitive has no indices');
  }
  final numIndices = decoded.faces.length;
  final Uint8List indexBytes;
  final GltfComponentType indexType;
  if (decoded.numPoints <= 0x10000) {
    final narrow = Uint16List(numIndices);
    for (var i = 0; i < numIndices; i++) {
      narrow[i] = decoded.faces[i];
    }
    indexBytes = Uint8List.sublistView(narrow);
    indexType = GltfComponentType.unsignedShort;
  } else {
    final wide = Uint32List(numIndices);
    for (var i = 0; i < numIndices; i++) {
      wide[i] = decoded.faces[i];
    }
    indexBytes = Uint8List.sublistView(wide);
    indexType = GltfComponentType.unsignedInt;
  }
  outAccessors[indicesIndex] = GltfAccessor(
    componentType: indexType,
    count: numIndices,
    type: GltfAccessorType.scalar,
    bufferView: addView(indexBytes),
  );

  // Attributes named by the extension; the rest keep their own storage.
  for (final entry in draco.attributes.entries) {
    final accessorIndex = primitive.attributes[entry.key];
    if (accessorIndex == null) continue;
    final attribute = decoded.attributeByUniqueId(entry.value);
    if (attribute == null) {
      throw FormatException(
        'Draco stream is missing the ${entry.key} attribute',
      );
    }
    final accessor = accessors[accessorIndex];
    if (accessor.type.componentCount != attribute.numComponents) {
      throw FormatException(
        'Draco ${entry.key} attribute has ${attribute.numComponents} '
        'components, accessor expects ${accessor.type.componentCount}',
      );
    }
    outAccessors[accessorIndex] = GltfAccessor(
      componentType: _componentTypeFor(attribute.dataType),
      count: decoded.numPoints,
      type: accessor.type,
      bufferView: addView(attribute.pointBytes(decoded.numPoints)),
      normalized: accessor.normalized,
      min: accessor.min,
      max: accessor.max,
    );
  }

  return DracoPrimitiveData(outAccessors, outViews, builder.takeBytes());
}

GltfComponentType _componentTypeFor(int dracoDataType) {
  switch (dracoDataType) {
    case DracoDataType.int8:
      return GltfComponentType.byte_;
    case DracoDataType.uint8:
      return GltfComponentType.unsignedByte;
    case DracoDataType.int16:
      return GltfComponentType.short;
    case DracoDataType.uint16:
      return GltfComponentType.unsignedShort;
    case DracoDataType.uint32:
      return GltfComponentType.unsignedInt;
    case DracoDataType.float32:
      return GltfComponentType.float;
    default:
      throw dracoError('data type $dracoDataType has no glTF component type');
  }
}
