part of '_gpu.dart';

/// A reference to a byte range within a GPU-resident [DeviceBuffer].
class BufferView {
  const BufferView(
    this.buffer, {
    required this.offsetInBytes,
    required this.lengthInBytes,
  });

  final DeviceBuffer buffer;
  final int offsetInBytes;
  final int lengthInBytes;
}

/// A region of GPU-resident memory backed by a WebGL2 buffer object.
///
/// WebGL2 permanently "types" a buffer the first time it is bound to a
/// target: a buffer ever bound to `ELEMENT_ARRAY_BUFFER` can never be bound
/// elsewhere, and vice-versa. flutter_gpu's DeviceBuffer is generic (the
/// caller decides vertex vs index vs uniform at bind time), so we can't
/// know the correct target at construction. We therefore stage writes in a
/// Dart-side byte array and create + upload the GL buffer lazily on first
/// bind, using whatever target the RenderPass asks for.
base class DeviceBuffer {
  DeviceBuffer._initialize(
    GpuContext gpuContext,
    this.storageMode,
    this.sizeInBytes,
  ) : _gpuContext = gpuContext {
    _staging = Uint8List(sizeInBytes);
    _valid = true;
  }

  final GpuContext _gpuContext;
  late final Uint8List _staging;
  web.WebGLBuffer? _glBuffer;
  int _allocTarget = 0;
  bool _needsUpload = false;
  bool _valid = false;

  final StorageMode storageMode;
  final int sizeInBytes;

  bool get isValid => _valid;

  int get _usage =>
      storageMode == StorageMode.devicePrivate
          ? web.WebGL2RenderingContext.STATIC_DRAW
          : web.WebGL2RenderingContext.DYNAMIC_DRAW;

  /// Internal: ensure the GL buffer exists, typed for [target], bind it, and
  /// flush any staged bytes. The first call fixes the buffer's GL type; a
  /// non-element buffer may later be bound to other non-element targets
  /// (e.g. UNIFORM_BUFFER) but never to ELEMENT_ARRAY_BUFFER.
  web.WebGLBuffer _bindForTarget(int target) {
    final gl = _gpuContext._gl;
    if (_glBuffer == null) {
      final buffer = gl.createBuffer();
      if (buffer == null) {
        throw StateError('Failed to create WebGL buffer');
      }
      _glBuffer = buffer;
      _allocTarget = target;
      gl.bindBuffer(target, buffer);
      gl.bufferData(target, _staging.toJS, _usage);
      _needsUpload = false;
    } else {
      gl.bindBuffer(target, _glBuffer);
      if (_needsUpload) {
        gl.bufferSubData(target, 0, _staging.toJS);
        _needsUpload = false;
      }
    }
    return _glBuffer!;
  }

  /// Overwrite a byte range. Source bytes must fit at the destination
  /// offset. Returns true on success.
  bool overwrite(ByteData sourceBytes, {int destinationOffsetInBytes = 0}) {
    if (storageMode != StorageMode.hostVisible) {
      throw Exception(
        'DeviceBuffer.overwrite can only be used with DeviceBuffers that are host visible',
      );
    }
    if (destinationOffsetInBytes < 0) {
      throw Exception('destinationOffsetInBytes must be positive');
    }
    final length = sourceBytes.lengthInBytes;
    if (destinationOffsetInBytes + length > sizeInBytes) {
      return false;
    }
    _staging.setRange(
      destinationOffsetInBytes,
      destinationOffsetInBytes + length,
      sourceBytes.buffer.asUint8List(sourceBytes.offsetInBytes, length),
    );
    if (_glBuffer == null) {
      // Not yet on the GPU; the whole staging buffer uploads on first bind.
      _needsUpload = true;
    } else {
      // Already typed and resident: push just the changed range.
      final gl = _gpuContext._gl;
      gl.bindBuffer(_allocTarget, _glBuffer);
      gl.bufferSubData(
        _allocTarget,
        destinationOffsetInBytes,
        Uint8List.sublistView(
          _staging,
          destinationOffsetInBytes,
          destinationOffsetInBytes + length,
        ).toJS,
      );
    }
    return true;
  }

  /// On native this flushes host-coherent caches. WebGL2 has no equivalent;
  /// `bufferSubData` is immediately visible to the GL implementation.
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) {}
}

/// Bump allocator that hands out [BufferView] slices from a chain of
/// [DeviceBuffer] blocks. Re-cycles blocks every [frameCount] frames when
/// [reset] is called.
base class HostBuffer {
  static const int kDefaultBlockLengthInBytes = 1024000;
  static const int _kFrameCount = 4;

  HostBuffer._initialize(
    this._gpuContext, {
    this.blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) {
    for (int i = 0; i < frameCount; i++) {
      _buffers.add([_allocateNewBlock(blockLengthInBytes)]);
    }
  }

  final GpuContext _gpuContext;
  final int blockLengthInBytes;

  int get frameCount => _kFrameCount;

  int _frameCursor = 0;
  int _bufferCursor = 0;
  int _offsetCursor = 0;
  final List<List<DeviceBuffer>> _buffers = [];

  DeviceBuffer _allocateNewBlock(int length) =>
      _gpuContext.createDeviceBuffer(StorageMode.hostVisible, length);

  BufferView _allocateEmplacement(ByteData bytes) {
    if (bytes.lengthInBytes > blockLengthInBytes) {
      return BufferView(
        _allocateNewBlock(bytes.lengthInBytes),
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );
    }

    final alignment = _gpuContext.minimumUniformByteAlignment;
    int padding = alignment - (_offsetCursor % alignment);
    padding %= alignment;
    if (_offsetCursor + padding + bytes.lengthInBytes > blockLengthInBytes) {
      final buffer = _allocateNewBlock(blockLengthInBytes);
      _buffers[_frameCursor].add(buffer);
      _bufferCursor++;
      _offsetCursor = bytes.lengthInBytes;
      return BufferView(
        buffer,
        offsetInBytes: 0,
        lengthInBytes: bytes.lengthInBytes,
      );
    }

    _offsetCursor += padding;
    final view = BufferView(
      _buffers[_frameCursor][_bufferCursor],
      offsetInBytes: _offsetCursor,
      lengthInBytes: bytes.lengthInBytes,
    );
    _offsetCursor += bytes.lengthInBytes;
    return view;
  }

  /// Append byte data and return a view at the resulting GPU offset.
  BufferView emplace(ByteData bytes) {
    final view = _allocateEmplacement(bytes);
    if (!view.buffer.overwrite(
      bytes,
      destinationOffsetInBytes: view.offsetInBytes,
    )) {
      throw Exception(
        'HostBuffer emplace failed at offset ${view.offsetInBytes}',
      );
    }
    return view;
  }

  /// Advance the frame cursor; subsequent [emplace] calls reuse the next
  /// frame's buffers.
  void reset() {
    _frameCursor = (_frameCursor + 1) % frameCount;
    _bufferCursor = 0;
    _offsetCursor = 0;
  }
}
