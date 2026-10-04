part of 'webgpu_backend.dart';

/// Reads [length] bytes of [buffer] back from the GPU, from [offset].
@visibleForTesting
Future<Uint8List> webGpuReadBuffer(
  DeviceBuffer buffer, {
  int offset = 0,
  required int length,
}) async {
  final source = buffer as _WebGpuDeviceBuffer;
  final device = source._context.device.device;
  final staging = device.createBuffer(
    GPUBufferDescriptor(
      size: _align4(length),
      usage: GPUBufferUsage.mapRead | GPUBufferUsage.copyDst,
    ),
  );
  final encoder = device.createCommandEncoder()
    ..copyBufferToBuffer(source.buffer, offset, staging, 0, _align4(length));
  device.queue.submit([encoder.finish()].toJS);
  return _mapAndCopy(staging, length);
}

/// Reads one [mipLevel] and [slice] of [texture] back from the GPU, rows
/// packed tightly.
@visibleForTesting
Future<Uint8List> webGpuReadTexture(
  Texture texture, {
  int mipLevel = 0,
  int slice = 0,
}) async {
  final source = texture as _WebGpuTexture;
  final device = source._context.device.device;
  final format = source._format;
  final block = format.blockSize;
  final blocksX =
      (source._mipExtent(source.width, mipLevel) + block - 1) ~/ block;
  final blocksY =
      (source._mipExtent(source.height, mipLevel) + block - 1) ~/ block;
  final rowBytes = blocksX * format.bytesPerBlock;
  // copyTextureToBuffer needs 256-byte row pitch.
  final pitch = (rowBytes + 255) & ~255;
  final staging = device.createBuffer(
    GPUBufferDescriptor(
      size: pitch * blocksY,
      usage: GPUBufferUsage.mapRead | GPUBufferUsage.copyDst,
    ),
  );
  final encoder = device.createCommandEncoder()
    ..copyTextureToBuffer(
      _obj({
        'texture': source.texture,
        'mipLevel': mipLevel,
        'origin': [0, 0, slice],
      }),
      _obj({'buffer': staging, 'bytesPerRow': pitch, 'rowsPerImage': blocksY}),
      _arr([blocksX * block, blocksY * block, 1]),
    );
  device.queue.submit([encoder.finish()].toJS);
  final padded = await _mapAndCopy(staging, pitch * blocksY);
  final packed = Uint8List(rowBytes * blocksY);
  for (var row = 0; row < blocksY; row++) {
    packed.setRange(row * rowBytes, (row + 1) * rowBytes, padded, row * pitch);
  }
  return packed;
}

Future<Uint8List> _mapAndCopy(GPUBuffer staging, int length) async {
  await staging.mapAsync(1).toDart;
  final bytes = Uint8List.fromList(
    staging.getMappedRange().toDart.asUint8List(0, length),
  );
  staging
    ..unmap()
    ..destroy();
  return bytes;
}
