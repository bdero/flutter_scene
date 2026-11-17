part of 'webgpu_backend.dart';

int _align4(int value) => (value + 3) & ~3;

/// Compile-time check: `true` under `dart2js`, `false` under `dart2wasm` / VM.
const bool _isJsRuntime = identical(1, 1.0);

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
      // Keep the CPU shadow in native Dart 32-bit word storage rather than a
      // JS-backed Uint8Array view (`JSUint8Array.toDart`). Under dart2wasm,
      // `JSUint8ArrayImpl.setRange` from a Wasm-backed list falls back to
      // materializing a boxed `List<int>` and writing one byte per FFI call,
      // whereas writing native 32-bit words and crossing an aligned
      // `Uint32List` slice stays unboxed and transfers 4 bytes per step (and on
      // dart2js `Uint32List` / `Uint8List` views share the same JS ArrayBuffer
      // with zero copy).
      final words = Uint32List(buffer.size >> 2);
      _shadowWords = words;
      if (_isJsRuntime) {
        _shadowJsBytes = words.buffer.asUint8List();
      } else {
        _shadowByteData = ByteData.sublistView(words);
      }
    }
    _bufferFinalizer.attach(this, buffer, detach: this);
  }

  /// A host-visible buffer for [writeGeometryData], with no CPU shadow.
  _WebGpuDeviceBuffer.geometry(_WebGpuContext context, int sizeInBytes)
    : this._(context, StorageMode.hostVisible, sizeInBytes, shadowed: false);

  final _WebGpuContext _context;
  final GPUBuffer buffer;
  Uint32List? _shadowWords;
  Uint8List? _shadowJsBytes;
  ByteData? _shadowByteData;

  @override
  final StorageMode storageMode;

  @override
  final int sizeInBytes;

  @override
  bool get isValid => !_released;

  bool _released = false;

  void _release() {
    if (_released) return;
    _released = true;
    _bufferFinalizer.detach(this);
    buffer.destroy();
  }

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
    final shadowWords = _shadowWords;
    if (shadowWords == null) {
      if (offset & 3 != 0) {
        throw StateError(
          'A geometry buffer write must start 4-byte aligned (offset $offset).',
        );
      }
      if (length & 3 == 0) {
        queue.writeBuffer(buffer, offset, _jsViewOf(source));
      } else {
        final paddedWords = Uint32List(_align4(length) >> 2);
        if (_isJsRuntime) {
          paddedWords.buffer.asUint8List().setRange(
            0,
            length,
            source.buffer.asUint8List(source.offsetInBytes, length),
          );
        } else {
          _copyIntoShadowWasm(
            paddedWords,
            ByteData.sublistView(paddedWords),
            0,
            source,
            length,
          );
        }
        queue.writeBuffer(buffer, offset, paddedWords.toJS);
      }
      return true;
    }

    if (_isJsRuntime) {
      _shadowJsBytes!.setRange(
        offset,
        offset + length,
        source.buffer.asUint8List(source.offsetInBytes, length),
      );
    } else {
      _copyIntoShadowWasm(
        shadowWords,
        _shadowByteData!,
        offset,
        source,
        length,
      );
    }
    final start = offset & ~3;
    final end = _align4(offset + length);
    final span = Uint32List.sublistView(shadowWords, start >> 2, end >> 2);
    queue.writeBuffer(buffer, start, span.toJS);
    return true;
  }

  /// Copies [length] bytes from [source] into [dstWords] / [dstBytes] at
  /// [dstOffset] inside pure Wasm memory without boxing or JS FFI crossings.
  static void _copyIntoShadowWasm(
    Uint32List dstWords,
    ByteData dstBytes,
    int dstOffset,
    TypedData source,
    int length,
  ) {
    if ((dstOffset & 3) == 0 && (length & 3) == 0) {
      final dstWordBase = dstOffset >> 2;
      final wordCount = length >> 2;
      if (source is Uint32List) {
        dstWords.setRange(dstWordBase, dstWordBase + wordCount, source);
        return;
      }
      final data = source is ByteData ? source : ByteData.sublistView(source);
      for (var i = 0; i < wordCount; i++) {
        dstWords[dstWordBase + i] = data.getUint32(i << 2, Endian.host);
      }
      return;
    }

    final data = source is ByteData ? source : ByteData.sublistView(source);
    final endOffset = dstOffset + length;
    var dstPos = dstOffset;
    var srcPos = 0;
    while (dstPos < endOffset && (dstPos & 3) != 0) {
      dstBytes.setUint8(dstPos, data.getUint8(srcPos));
      dstPos++;
      srcPos++;
    }
    final middleWords = (endOffset - dstPos) >> 2;
    var dstWord = dstPos >> 2;
    for (var i = 0; i < middleWords; i++) {
      dstWords[dstWord + i] = data.getUint32(srcPos, Endian.host);
      srcPos += 4;
    }
    dstPos += middleWords << 2;
    while (dstPos < endOffset) {
      dstBytes.setUint8(dstPos, data.getUint8(srcPos));
      dstPos++;
      srcPos++;
    }
  }

  /// Hands [source] to JS without a copy when its static type matches its
  /// store, which is the cheap case under dart2wasm (see the WebGL2 buffer's
  /// `_jsViewOf` for the measurements).
  static JSObject _jsViewOf(TypedData source) => switch (source) {
    Float32List() => source.toJS,
    Uint16List() => source.toJS,
    Uint32List() => source.toJS,
    Uint8List() => source.toJS,
    Int8List() => source.toJS,
    Int16List() => source.toJS,
    Int32List() => source.toJS,
    _ => _copyTypedDataToJs(source),
  };

  static JSObject _copyTypedDataToJs(TypedData source) {
    final length = source.lengthInBytes;
    if (_isJsRuntime) {
      return source.buffer.asUint8List(source.offsetInBytes, length).toJS;
    }
    final data = source is ByteData ? source : ByteData.sublistView(source);
    if ((length & 3) == 0) {
      final wordCount = length >> 2;
      final words = Uint32List(wordCount);
      for (var i = 0; i < wordCount; i++) {
        words[i] = data.getUint32(i << 2, Endian.host);
      }
      return words.toJS;
    }
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = data.getUint8(i);
    }
    return bytes.toJS;
  }

  /// Host writes reach the GPU through the queue; there is nothing to flush.
  @override
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) {}
}
