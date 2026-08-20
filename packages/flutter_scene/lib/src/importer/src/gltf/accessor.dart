import 'dart:typed_data';

import 'types.dart';

/// Resolves a glTF accessor into a flat [Float32List] of its raw component
/// values. The accessor's component type is normalized to float32 for callers,
/// since flutter_scene's vertex format is uniformly float32.
///
/// [bufferViews] is the document's full bufferViews list (accessors index
/// into it, and so do a sparse accessor's own indices/values bufferViews).
/// [bufferData] is the GLB binary chunk (or the resolved external buffer).
/// When [GltfAccessor.bufferView] is null the base is a zero-filled array,
/// per spec; a [GltfAccessor.sparse] override, if present, is applied on top.
Float32List readAccessorAsFloat32(
  GltfAccessor accessor,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final componentCount = accessor.type.componentCount;
  final out = Float32List(accessor.count * componentCount);

  final bufferViewIndex = accessor.bufferView;
  if (bufferViewIndex != null) {
    final bufferView = bufferViews[bufferViewIndex];
    final stride =
        bufferView.byteStride ??
        (componentCount * accessor.componentType.bytes);
    final start = bufferView.byteOffset + accessor.byteOffset;
    final view = ByteData.sublistView(bufferData);
    for (int i = 0; i < accessor.count; i++) {
      final base = start + i * stride;
      for (int c = 0; c < componentCount; c++) {
        final off = base + c * accessor.componentType.bytes;
        out[i * componentCount + c] = _readFloatComponent(
          view,
          off,
          accessor.componentType,
          accessor.normalized,
        );
      }
    }
  }

  _applySparseFloat(accessor, bufferViews, bufferData, out, componentCount);
  return out;
}

/// Resolves an integer-typed accessor (used for indices and joint indices)
/// into a [Uint32List]. See [readAccessorAsFloat32] for the sparse/null
/// bufferView handling shared by both readers.
Uint32List readAccessorAsUint32(
  GltfAccessor accessor,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
) {
  final componentCount = accessor.type.componentCount;
  final out = Uint32List(accessor.count * componentCount);

  final bufferViewIndex = accessor.bufferView;
  if (bufferViewIndex != null) {
    final bufferView = bufferViews[bufferViewIndex];
    final stride =
        bufferView.byteStride ??
        (componentCount * accessor.componentType.bytes);
    final start = bufferView.byteOffset + accessor.byteOffset;
    final view = ByteData.sublistView(bufferData);
    for (int i = 0; i < accessor.count; i++) {
      final base = start + i * stride;
      for (int c = 0; c < componentCount; c++) {
        final off = base + c * accessor.componentType.bytes;
        out[i * componentCount + c] = _readUintComponent(
          view,
          off,
          accessor.componentType,
        );
      }
    }
  }

  _applySparseUint(accessor, bufferViews, bufferData, out, componentCount);
  return out;
}

// Applies a sparse accessor's overrides onto a dense/zero-filled float base.
// Every override index is bounds-checked against accessor.count at the write
// site; a pre-validated index is not trusted, since that ordering is a known
// exploit shape for buffer overwrites.
void _applySparseFloat(
  GltfAccessor accessor,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  Float32List out,
  int componentCount,
) {
  final sparse = accessor.sparse;
  if (sparse == null) return;
  final indicesView = bufferViews[sparse.indicesBufferView];
  final valuesView = bufferViews[sparse.valuesBufferView];
  final view = ByteData.sublistView(bufferData);
  final indexStart = indicesView.byteOffset + sparse.indicesByteOffset;
  final valueStart = valuesView.byteOffset + sparse.valuesByteOffset;
  final indexSize = sparse.indicesComponentType.bytes;
  final valueSize = accessor.componentType.bytes;
  for (int i = 0; i < sparse.count; i++) {
    final idx = _readUintComponent(
      view,
      indexStart + i * indexSize,
      sparse.indicesComponentType,
    );
    if (idx < 0 || idx >= accessor.count) {
      throw FormatException(
        'glTF sparse accessor index $idx out of range (accessor count '
        '${accessor.count})',
      );
    }
    final valueBase = valueStart + i * componentCount * valueSize;
    for (int c = 0; c < componentCount; c++) {
      out[idx * componentCount + c] = _readFloatComponent(
        view,
        valueBase + c * valueSize,
        accessor.componentType,
        accessor.normalized,
      );
    }
  }
}

// Integer-output counterpart of [_applySparseFloat]; same bounds check.
void _applySparseUint(
  GltfAccessor accessor,
  List<GltfBufferView> bufferViews,
  Uint8List bufferData,
  Uint32List out,
  int componentCount,
) {
  final sparse = accessor.sparse;
  if (sparse == null) return;
  final indicesView = bufferViews[sparse.indicesBufferView];
  final valuesView = bufferViews[sparse.valuesBufferView];
  final view = ByteData.sublistView(bufferData);
  final indexStart = indicesView.byteOffset + sparse.indicesByteOffset;
  final valueStart = valuesView.byteOffset + sparse.valuesByteOffset;
  final indexSize = sparse.indicesComponentType.bytes;
  final valueSize = accessor.componentType.bytes;
  for (int i = 0; i < sparse.count; i++) {
    final idx = _readUintComponent(
      view,
      indexStart + i * indexSize,
      sparse.indicesComponentType,
    );
    if (idx < 0 || idx >= accessor.count) {
      throw FormatException(
        'glTF sparse accessor index $idx out of range (accessor count '
        '${accessor.count})',
      );
    }
    final valueBase = valueStart + i * componentCount * valueSize;
    for (int c = 0; c < componentCount; c++) {
      out[idx * componentCount + c] = _readUintComponent(
        view,
        valueBase + c * valueSize,
        accessor.componentType,
      );
    }
  }
}

double _readFloatComponent(
  ByteData view,
  int offset,
  GltfComponentType type,
  bool normalized,
) {
  switch (type) {
    case GltfComponentType.byte_:
      final v = view.getInt8(offset).toDouble();
      return normalized ? (v / 127.0).clamp(-1.0, 1.0) : v;
    case GltfComponentType.unsignedByte:
      final v = view.getUint8(offset).toDouble();
      return normalized ? v / 255.0 : v;
    case GltfComponentType.short:
      final v = view.getInt16(offset, Endian.little).toDouble();
      return normalized ? (v / 32767.0).clamp(-1.0, 1.0) : v;
    case GltfComponentType.unsignedShort:
      final v = view.getUint16(offset, Endian.little).toDouble();
      return normalized ? v / 65535.0 : v;
    case GltfComponentType.unsignedInt:
      return view.getUint32(offset, Endian.little).toDouble();
    case GltfComponentType.float:
      return view.getFloat32(offset, Endian.little);
  }
}

int _readUintComponent(ByteData view, int offset, GltfComponentType type) {
  switch (type) {
    case GltfComponentType.byte_:
      return view.getInt8(offset);
    case GltfComponentType.unsignedByte:
      return view.getUint8(offset);
    case GltfComponentType.short:
      return view.getInt16(offset, Endian.little);
    case GltfComponentType.unsignedShort:
      return view.getUint16(offset, Endian.little);
    case GltfComponentType.unsignedInt:
      return view.getUint32(offset, Endian.little);
    case GltfComponentType.float:
      return view.getFloat32(offset, Endian.little).toInt();
  }
}
