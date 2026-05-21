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
/// We allocate with `ARRAY_BUFFER` as a neutral binding target so the
/// buffer is created cheaply; later `bindBuffer` calls re-target it as
/// needed for vertex / index / uniform use.
base class DeviceBuffer {
  DeviceBuffer._initialize(
    GpuContext gpuContext,
    this.storageMode,
    this.sizeInBytes,
  ) : _gpuContext = gpuContext {
    final gl = gpuContext._gl;
    final buffer = gl.createBuffer();
    if (buffer == null) {
      throw StateError('Failed to create WebGL buffer');
    }
    _buffer = buffer;
    gl.bindBuffer(web.WebGL2RenderingContext.ARRAY_BUFFER, _buffer);
    gl.bufferData(
      web.WebGL2RenderingContext.ARRAY_BUFFER,
      sizeInBytes.toJS,
      storageMode == StorageMode.devicePrivate
          ? web.WebGL2RenderingContext.STATIC_DRAW
          : web.WebGL2RenderingContext.DYNAMIC_DRAW,
    );
    _valid = true;
  }

  final GpuContext _gpuContext;
  late final web.WebGLBuffer _buffer;
  bool _valid = false;

  final StorageMode storageMode;
  final int sizeInBytes;

  bool get isValid => _valid;
  web.WebGLBuffer get glBuffer => _buffer;

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
    if (destinationOffsetInBytes + sourceBytes.lengthInBytes > sizeInBytes) {
      return false;
    }
    final gl = _gpuContext._gl;
    gl.bindBuffer(web.WebGL2RenderingContext.ARRAY_BUFFER, _buffer);
    final view = sourceBytes.buffer.asUint8List(
      sourceBytes.offsetInBytes,
      sourceBytes.lengthInBytes,
    );
    gl.bufferSubData(
      web.WebGL2RenderingContext.ARRAY_BUFFER,
      destinationOffsetInBytes,
      view.toJS,
    );
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
