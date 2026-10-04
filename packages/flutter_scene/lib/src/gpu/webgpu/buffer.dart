part of 'webgpu_backend.dart';

int _align4(int value) => (value + 3) & ~3;

/// Every role a buffer can play in a draw, since a flutter_gpu DeviceBuffer
/// is untyped and the engine binds one range as vertices and another as
/// indices or uniforms.
const int _bufferUsage =
    GPUBufferUsage.vertex |
    GPUBufferUsage.index |
    GPUBufferUsage.uniform |
    GPUBufferUsage.copyDst |
    GPUBufferUsage.copySrc;

/// Destroys a buffer's GPU allocation once its Dart wrapper is collected.
/// WebGPU defers the destruction until submitted work using it completes.
final Finalizer<GPUBuffer> _bufferFinalizer = Finalizer(
  (buffer) => buffer.destroy(),
);

/// A [DeviceBuffer] over a `GPUBuffer`.
///
/// `writeBuffer` takes only 4-byte-aligned offsets and sizes and nothing reads
/// back synchronously, so a general host-visible buffer keeps a CPU shadow and
/// uploads the aligned span around each write, as WebGL2 keeps its staging. A
/// geometry buffer ([_WebGpuDeviceBuffer.geometry]) skips the shadow: its
/// writes start 4-byte aligned and only its own tail padding absorbs a short
/// final write.
final class _WebGpuDeviceBuffer extends DeviceBuffer {
  _WebGpuDeviceBuffer._(
    this._context,
    this.storageMode,
    this.sizeInBytes, {
    required bool shadowed,
  }) : buffer = _context.device.device.createBuffer(
         GPUBufferDescriptor(
           size: _align4(sizeInBytes < 4 ? 4 : sizeInBytes),
           usage: _bufferUsage,
         ),
       ) {
    if (shadowed) {
      // JS-backed, so handing it to writeBuffer is free under dart2wasm too.
      _shadowJs = JSUint8Array.withLength(buffer.size);
      _shadow = _shadowJs!.toDart;
    }
    _bufferFinalizer.attach(this, buffer, detach: this);
  }

  /// A host-visible buffer for [writeGeometryData], with no CPU shadow.
  _WebGpuDeviceBuffer.geometry(_WebGpuContext context, int sizeInBytes)
    : this._(context, StorageMode.hostVisible, sizeInBytes, shadowed: false);

  final _WebGpuContext _context;
  final GPUBuffer buffer;
  JSUint8Array? _shadowJs;
  Uint8List? _shadow;

  @override
  final StorageMode storageMode;

  @override
  final int sizeInBytes;

  @override
  bool get isValid => true;

  @override
  bool overwrite(ByteData sourceBytes, {int destinationOffsetInBytes = 0}) {
    if (storageMode != StorageMode.hostVisible) {
      throw Exception(
        'DeviceBuffer.overwrite can only be used with DeviceBuffers that are '
        'host visible',
      );
    }
    return _write(sourceBytes, destinationOffsetInBytes);
  }

  bool _write(TypedData source, int offset) {
    if (offset < 0) {
      throw Exception('destinationOffsetInBytes must be positive');
    }
    final length = source.lengthInBytes;
    if (offset + length > sizeInBytes) return false;
    if (length == 0) return true;
    final queue = _context.device.device.queue;
    final shadow = _shadow;
    if (shadow == null) {
      if (offset & 3 != 0) {
        throw StateError(
          'A geometry buffer write must start 4-byte aligned (offset $offset).',
        );
      }
      if (length & 3 == 0) {
        queue.writeBuffer(buffer, offset, _jsViewOf(source));
      } else {
        final padded = Uint8List(_align4(length))
          ..setRange(
            0,
            length,
            source.buffer.asUint8List(source.offsetInBytes, length),
          );
        queue.writeBuffer(buffer, offset, padded.toJS);
      }
      return true;
    }
    shadow.setRange(
      offset,
      offset + length,
      source.buffer.asUint8List(source.offsetInBytes, length),
    );
    final start = offset & ~3;
    final end = _align4(offset + length);
    queue.writeBuffer(buffer, start, _shadowJs!, start, end - start);
    return true;
  }

  /// Hands [source] to JS without a copy when its static type matches its
  /// store, which is the cheap case under dart2wasm (see the WebGL2 buffer's
  /// `_jsViewOf` for the measurements).
  static JSObject _jsViewOf(TypedData source) => switch (source) {
    Float32List() => source.toJS,
    Uint16List() => source.toJS,
    Uint32List() => source.toJS,
    Uint8List() => source.toJS,
    _ => Uint8List.fromList(
      source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
    ).toJS,
  };

  /// Host writes reach the GPU through the queue; there is nothing to flush.
  @override
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) {}
}
