part of '_gpu.dart';

Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) => _stub();

/// The buffers one mesh upload needs. Native has no per-role restriction, so
/// this is the single shared buffer it always was, indices after vertices.
({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
createGeometryBuffers(int vertexBytes, int indexBytes) {
  final buffer = gpuContext.createDeviceBuffer(
    StorageMode.hostVisible,
    vertexBytes + indexBytes,
  );
  return (vertex: buffer, index: buffer, indexBaseOffset: vertexBytes);
}

/// Writes mesh data into a buffer from [createGeometryBuffers] (or an arena's).
/// The web backend uses [source]'s element type; here bytes are bytes.
bool writeGeometryData(
  DeviceBuffer buffer,
  TypedData source, {
  required int destinationOffsetInBytes,
}) => buffer.overwrite(
  source is ByteData ? source : ByteData.sublistView(source),
  destinationOffsetInBytes: destinationOffsetInBytes,
);
