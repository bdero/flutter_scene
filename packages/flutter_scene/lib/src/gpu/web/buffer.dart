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

/// A region of GPU-resident memory backed by WebGL2 buffer object(s).
///
/// WebGL2 permanently "types" a buffer the first time it is bound: a buffer
/// ever bound to `ELEMENT_ARRAY_BUFFER` can never be bound to any other
/// target, and vice-versa. flutter_gpu's DeviceBuffer is generic - and
/// flutter_scene in particular packs vertices *and* indices into one
/// DeviceBuffer and binds sub-ranges of it as both a vertex buffer and an
/// index buffer. WebGL2 forbids that with a single buffer object.
///
/// So writes are staged in a Dart-side byte array, and up to two GL buffers
/// are created lazily from it: one for element (index) use and one for
/// everything else (vertex / uniform / copy). Both mirror the full staging,
/// so the caller's absolute byte offsets line up in either. The duplication
/// is web-only and limited to buffers actually used as both.
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

  /// A float view over the whole staging buffer, used by the uniform upload
  /// path with srcOffset/srcLength so no per-draw views are created.
  late final Float32List _stagingFloats = _staging.buffer.asFloat32List(
    _staging.offsetInBytes,
    _staging.lengthInBytes >> 2,
  );
  web.WebGLBuffer? _glElementBuffer;
  web.WebGLBuffer? _glOtherBuffer;
  bool _valid = false;

  final StorageMode storageMode;
  final int sizeInBytes;

  bool get isValid => _valid;

  int get _usage => storageMode == StorageMode.devicePrivate
      ? web.WebGL2RenderingContext.STATIC_DRAW
      : web.WebGL2RenderingContext.DYNAMIC_DRAW;

  /// Internal: bind the GL buffer appropriate for [target], creating and
  /// uploading it from the staging bytes on first use. Index buffers get a
  /// dedicated element-typed buffer; all other targets share a non-element
  /// buffer.
  web.WebGLBuffer _bindForTarget(int target) {
    final gl = _gpuContext._gl;
    final isElement = target == web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER;
    var buffer = isElement ? _glElementBuffer : _glOtherBuffer;
    if (buffer == null) {
      buffer = gl.createBuffer();
      if (buffer == null) {
        throw StateError('Failed to create WebGL buffer');
      }
      if (isElement) {
        _glElementBuffer = buffer;
      } else {
        _glOtherBuffer = buffer;
      }
      gl.bindBuffer(target, buffer);
      gl.bufferData(target, _staging.toJS, _usage);
    } else {
      gl.bindBuffer(target, buffer);
    }
    return buffer;
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
    // Push the changed range to any already-resident GL buffers. Buffers not
    // yet created pick up the full staging on first bind.
    final gl = _gpuContext._gl;
    final sub = Uint8List.sublistView(
      _staging,
      destinationOffsetInBytes,
      destinationOffsetInBytes + length,
    );
    if (_glOtherBuffer != null) {
      gl.bindBuffer(web.WebGL2RenderingContext.ARRAY_BUFFER, _glOtherBuffer);
      gl.bufferSubData(
        web.WebGL2RenderingContext.ARRAY_BUFFER,
        destinationOffsetInBytes,
        sub.toJS,
      );
    }
    if (_glElementBuffer != null) {
      gl.bindBuffer(
        web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER,
        _glElementBuffer,
      );
      gl.bufferSubData(
        web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER,
        destinationOffsetInBytes,
        sub.toJS,
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
