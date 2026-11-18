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
      // Word storage, since dart2wasm hands typed data to JS one element at a
      // time. Writing into a JS-backed shadow instead boxes every byte.
      final words = Uint32List(buffer.size >> 2);
      _shadowWords = words;
      if (kIsWasm) {
        _shadowByteData = ByteData.sublistView(words);
      } else {
        _shadowBytes = words.buffer.asUint8List();
      }
    }
    _bufferFinalizer.attach(this, buffer, detach: this);
  }

  /// A host-visible buffer for [writeGeometryData], with no CPU shadow.
  _WebGpuDeviceBuffer.geometry(_WebGpuContext context, int sizeInBytes)
    : this._(context, StorageMode.hostVisible, sizeInBytes, shadowed: false);

  static int _nextId = 1;

  /// Monotonic integer identity for unboxed bind-group cache keys.
  final int _id = _nextId++;

  final _WebGpuContext _context;
  final GPUBuffer buffer;
  Uint32List? _shadowWords;
  // A byte view of the shadow for dart2js, where it shares the JS buffer.
  Uint8List? _shadowBytes;
  // The view dart2wasm writes unaligned head and tail bytes through.
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
        if (kIsWasm) {
          _copyWords(
            paddedWords,
            ByteData.sublistView(paddedWords),
            0,
            source,
            length,
          );
        } else {
          paddedWords.buffer.asUint8List().setRange(
            0,
            length,
            source.buffer.asUint8List(source.offsetInBytes, length),
          );
        }
        queue.writeBuffer(buffer, offset, paddedWords.toJS);
      }
      return true;
    }

    if (kIsWasm) {
      _copyWords(shadowWords, _shadowByteData!, offset, source, length);
    } else {
      _shadowBytes!.setRange(
        offset,
        offset + length,
        source.buffer.asUint8List(source.offsetInBytes, length),
      );
    }
    final start = offset & ~3;
    final end = _align4(offset + length);
    final span = Uint32List.sublistView(shadowWords, start >> 2, end >> 2);
    queue.writeBuffer(buffer, start, span.toJS);
    return true;
  }

  /// Copies [length] bytes of [source] to [dstOffset] in [dstWords] a word at
  /// a time, through [dstBytes] (a view of [dstWords]) for unaligned ends.
  ///
  /// Under dart2wasm this is about 7x faster than a byte `setRange` into the
  /// same words. Words are copied as integers, never floats, so NaN payloads
  /// survive.
  static void _copyWords(
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

  /// Copies [source], whose length is a multiple of 4, into a list JS can
  /// take as is.
  static JSObject _copyTypedDataToJs(TypedData source) {
    final length = source.lengthInBytes;
    if (!kIsWasm) {
      return source.buffer.asUint8List(source.offsetInBytes, length).toJS;
    }
    final words = Uint32List(length >> 2);
    _copyWords(words, ByteData.sublistView(words), 0, source, length);
    return words.toJS;
  }

  /// Host writes reach the GPU through the queue; there is nothing to flush.
  @override
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) {}
}
