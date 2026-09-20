part of '_gpu.dart';

/// Bridge helper to display an offscreen-rendered Texture in a Flutter
/// widget. Web-only at runtime; throws on Impeller (native) targets
/// because flutter_gpu's `Texture.asImage()` is the standard path there.
Future<ui.Image> presentTextureAsImage(
  Texture texture, {
  bool transferOwnership = false,
}) {
  throw UnimplementedError(
    'presentTextureAsImage is only implemented on web. On native, use '
    'Texture.asImage().',
  );
}

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
