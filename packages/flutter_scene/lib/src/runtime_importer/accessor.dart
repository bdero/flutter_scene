import 'dart:typed_data';

import 'gltf_types.dart';

/// Resolves a glTF accessor into a flat [Float32List] of its raw component
/// values. The accessor's component type is normalized to float32 for callers,
/// since flutter_scene's vertex format is uniformly float32.
///
/// [bufferData] is the GLB binary chunk (or the resolved external buffer).
Float32List readAccessorAsFloat32(
  GltfAccessor accessor,
  GltfBufferView bufferView,
  Uint8List bufferData,
) {
  final componentCount = accessor.type.componentCount;
  final totalComponents = accessor.count * componentCount;
  final out = Float32List(totalComponents);

  final stride =
      bufferView.byteStride ?? (componentCount * accessor.componentType.bytes);
  final start = bufferView.byteOffset + accessor.byteOffset;
  final view = ByteData.sublistView(bufferData);

  for (int i = 0; i < accessor.count; i++) {
    final base = start + i * stride;
    for (int c = 0; c < componentCount; c++) {
      final off = base + c * accessor.componentType.bytes;
      double v;
      switch (accessor.componentType) {
        case GltfComponentType.byte_:
          v = view.getInt8(off).toDouble();
          if (accessor.normalized) v = (v / 127.0).clamp(-1.0, 1.0);
        case GltfComponentType.unsignedByte:
          v = view.getUint8(off).toDouble();
          if (accessor.normalized) v = v / 255.0;
        case GltfComponentType.short:
          v = view.getInt16(off, Endian.little).toDouble();
          if (accessor.normalized) v = (v / 32767.0).clamp(-1.0, 1.0);
        case GltfComponentType.unsignedShort:
          v = view.getUint16(off, Endian.little).toDouble();
          if (accessor.normalized) v = v / 65535.0;
        case GltfComponentType.unsignedInt:
          v = view.getUint32(off, Endian.little).toDouble();
        case GltfComponentType.float:
          v = view.getFloat32(off, Endian.little);
      }
      out[i * componentCount + c] = v;
    }
  }
  return out;
}

/// Resolves an integer-typed accessor (used for indices and joint indices)
/// into a [Uint32List].
Uint32List readAccessorAsUint32(
  GltfAccessor accessor,
  GltfBufferView bufferView,
  Uint8List bufferData,
) {
  final componentCount = accessor.type.componentCount;
  final totalComponents = accessor.count * componentCount;
  final out = Uint32List(totalComponents);

  final stride =
      bufferView.byteStride ?? (componentCount * accessor.componentType.bytes);
  final start = bufferView.byteOffset + accessor.byteOffset;
  final view = ByteData.sublistView(bufferData);

  for (int i = 0; i < accessor.count; i++) {
    final base = start + i * stride;
    for (int c = 0; c < componentCount; c++) {
      final off = base + c * accessor.componentType.bytes;
      int v;
      switch (accessor.componentType) {
        case GltfComponentType.byte_:
          v = view.getInt8(off);
        case GltfComponentType.unsignedByte:
          v = view.getUint8(off);
        case GltfComponentType.short:
          v = view.getInt16(off, Endian.little);
        case GltfComponentType.unsignedShort:
          v = view.getUint16(off, Endian.little);
        case GltfComponentType.unsignedInt:
          v = view.getUint32(off, Endian.little);
        case GltfComponentType.float:
          v = view.getFloat32(off, Endian.little).toInt();
      }
      out[i * componentCount + c] = v;
    }
  }
  return out;
}
