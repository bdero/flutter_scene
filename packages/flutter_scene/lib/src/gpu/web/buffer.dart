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
///
/// A caller that knows a buffer's single role does not need any of that; see
/// [DeviceBuffer._initializeTyped] and [createGeometryBuffers].
base class DeviceBuffer {
  DeviceBuffer._initialize(
    GpuContext gpuContext,
    this.storageMode,
    this.sizeInBytes,
  ) : _gpuContext = gpuContext,
      _typedTarget = null {
    _staging = Uint8List(sizeInBytes);
    _valid = true;
  }

  /// A buffer whose single GL role is known up front ([target] is
  /// `ARRAY_BUFFER` or `ELEMENT_ARRAY_BUFFER`).
  ///
  /// The staging mirror exists only because a generic DeviceBuffer may later
  /// be bound as BOTH kinds. When the caller commits to one, there is nothing
  /// to defer: the GL data store is allocated here, [overwrite] goes straight
  /// to `bufferSubData` from the caller's bytes, and no CPU copy is kept.
  DeviceBuffer._initializeTyped(
    GpuContext gpuContext,
    this.sizeInBytes,
    int target,
  ) : _gpuContext = gpuContext,
      storageMode = StorageMode.hostVisible,
      _typedTarget = target {
    final gl = gpuContext._gl;
    final buffer = gl.createBuffer();
    if (buffer == null) {
      throw StateError('Failed to create WebGL buffer');
    }
    _bindTypedForUpload(gl, target, buffer);
    gl.bufferData(
      target,
      sizeInBytes.toJS,
      web.WebGL2RenderingContext.STATIC_DRAW,
    );
    if (target == web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER) {
      _glElementBuffer = buffer;
    } else {
      _glOtherBuffer = buffer;
    }
    _staging = Uint8List(0);
    _valid = true;
  }

  /// Binds [buffer] to its own [target] for an upload outside a render pass.
  ///
  /// ELEMENT_ARRAY_BUFFER is per-VAO state, so binding it here would silently
  /// re-point whichever cached VAO the last draw left bound. Drop to the
  /// default VAO first; RenderPass re-binds its VAO on every draw.
  static void _bindTypedForUpload(
    web.WebGL2RenderingContext gl,
    int target,
    web.WebGLBuffer buffer,
  ) {
    if (target == web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER) {
      gl.bindVertexArray(null);
    }
    gl.bindBuffer(target, buffer);
  }

  final GpuContext _gpuContext;
  late final Uint8List _staging;

  /// Non-null for a buffer created by [DeviceBuffer._initializeTyped].
  final int? _typedTarget;

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

  /// Tail padding on the non-element GL data store. A uniform bind may extend
  /// past the staged bytes to reach the driver-reported block data size (see
  /// RenderPass.bindUniform); the padding keeps that range inside the buffer.
  static const int _kUniformTailPaddingBytes = 256;

  /// Internal: bind the GL buffer appropriate for [target], creating and
  /// uploading it from the staging bytes on first use. Index buffers get a
  /// dedicated element-typed buffer; all other targets share a non-element
  /// buffer.
  web.WebGLBuffer _bindForTarget(int target) {
    final gl = _gpuContext._gl;
    final isElement = target == web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER;
    var buffer = isElement ? _glElementBuffer : _glOtherBuffer;
    if (buffer == null && _typedTarget != null) {
      final role =
          _typedTarget == web.WebGL2RenderingContext.ELEMENT_ARRAY_BUFFER
          ? 'index'
          : 'vertex';
      throw StateError(
        'A DeviceBuffer created for $role use was bound to the other target.',
      );
    }
    if (buffer == null) {
      buffer = gl.createBuffer();
      if (buffer == null) {
        throw StateError('Failed to create WebGL buffer');
      }
      gl.bindBuffer(target, buffer);
      if (isElement) {
        _glElementBuffer = buffer;
        gl.bufferData(target, _staging.toJS, _usage);
      } else {
        _glOtherBuffer = buffer;
        gl.bufferData(
          target,
          (sizeInBytes + _kUniformTailPaddingBytes).toJS,
          _usage,
        );
        gl.bufferSubData(target, 0, _staging.toJS);
      }
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
    if (_typedTarget != null) {
      return overwriteTypedData(
        sourceBytes,
        destinationOffsetInBytes: destinationOffsetInBytes,
      );
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

  /// [overwrite] for a caller that still knows its data's element type.
  ///
  /// On a role-typed buffer [source] crosses to JS as the typed array it is,
  /// which matters under dart2wasm: a `Float32List` is backed by a wasm array
  /// of f32, so reading it through a byte view (what a [ByteData] over it is)
  /// goes element by element, ~35x slower than crossing it as floats. On
  /// dart2js every typed list is already a JS typed array and all of this is
  /// free. A staged buffer takes the ordinary [overwrite] path.
  bool overwriteTypedData(
    TypedData source, {
    int destinationOffsetInBytes = 0,
  }) {
    final target = _typedTarget;
    if (target == null) {
      return overwrite(
        source is ByteData ? source : ByteData.sublistView(source),
        destinationOffsetInBytes: destinationOffsetInBytes,
      );
    }
    if (destinationOffsetInBytes < 0) {
      throw Exception('destinationOffsetInBytes must be positive');
    }
    if (destinationOffsetInBytes + source.lengthInBytes > sizeInBytes) {
      return false;
    }
    final gl = _gpuContext._gl;
    _bindTypedForUpload(gl, target, (_glElementBuffer ?? _glOtherBuffer)!);
    gl.bufferSubData(target, destinationOffsetInBytes, _jsViewOf(source));
    return true;
  }

  /// [source] as a JS `ArrayBufferView`, without reinterpreting its elements.
  ///
  /// The element types mesh data arrives in cross as a view of their own kind.
  /// Anything else - a [ByteData], say - is COPIED into a byte list of its
  /// own first: handing `toJS` a byte view over someone else's typed list is
  /// the slowest thing there is under dart2wasm (see [overwriteTypedData]),
  /// several times worse than copying the bytes and crossing the copy.
  ///
  /// What decides the cost is the backing store, not the static type, so the
  /// pass-through cases below are only fast when the caller passed the type
  /// its store was allocated as. Measured on 4.65 MB under dart2wasm, a
  /// matched list crosses in 1.4 ms (floats) to 4.4 ms (bytes), a mismatched
  /// view in 90 ms to 340 ms, and the copy this falls back to in 45 ms. The
  /// copy is why a [ByteData] over float storage is not handed over as a byte
  /// view. `Geometry._uploadStreams` documents what each producer allocates.
  static JSObject _jsViewOf(TypedData source) => switch (source) {
    Float32List() => source.toJS,
    Uint16List() => source.toJS,
    Uint32List() => source.toJS,
    Uint8List() => source.toJS,
    _ => Uint8List.fromList(
      source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
    ).toJS,
  };

  /// On native this flushes host-coherent caches. WebGL2 has no equivalent;
  /// `bufferSubData` is immediately visible to the GL implementation.
  void flush({int offsetInBytes = 0, int lengthInBytes = -1}) {}
}

/// Bump allocator that hands out [BufferView] slices from a chain of
/// [DeviceBuffer] blocks. Re-cycles blocks every [frameCount] frames when
/// [reset] is called.
///
/// A faithful port of flutter_gpu's HostBuffer (block bump allocation,
/// [frameCount]-frame rotation, per-emplacement uniform alignment) so the
/// shim stays a drop-in flutter_gpu replacement. The one deliberate
/// difference: block rollover accounts for the write's own length, and an
/// emplacement into a fresh block gets a view of the data's length; the
/// upstream check hands out views that overrun the block when an aligned
/// offset fits but the write's end does not (fix submitted upstream).
///
/// flutter_scene's renderer does not use HostBuffer (its transients ride
/// the completion-aware arenas in `render/frame_transients.dart`), so the
/// buffer-ghosting cost of rewriting live GL buffers only affects direct
/// shim consumers who emplace against in-flight frames, matching what
/// flutter_gpu does natively.
base class HostBuffer {
  static const int kDefaultBlockLengthInBytes = 1024000;
  static const int _kFrameCount = 4;

  HostBuffer._initialize(
    this._gpuContext, {
    this.blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) {
    for (var frame = 0; frame < _kFrameCount; frame++) {
      _buffers.add([_allocateNewBlock(blockLengthInBytes)]);
    }
  }

  final GpuContext _gpuContext;

  /// The length of each [DeviceBuffer] block.
  final int blockLengthInBytes;

  int get frameCount => _kFrameCount;

  int _frameCursor = 0;
  int _bufferCursor = 0;
  int _offsetCursor = 0;

  /// Per-frame block chains, matching flutter_gpu's layout.
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

    var padding =
        _gpuContext.minimumUniformByteAlignment -
        (_offsetCursor % _gpuContext.minimumUniformByteAlignment);
    padding %= _gpuContext.minimumUniformByteAlignment;
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
        'Failed to write range (offset=${view.offsetInBytes}, '
        'length=${view.lengthInBytes}) to HostBuffer-managed DeviceBuffer '
        '(frame=$_frameCursor, buffer=$_bufferCursor, '
        'offset=$_offsetCursor).',
      );
    }
    return view;
  }

  /// Resets the bump allocator to the beginning of the next frame's first
  /// [DeviceBuffer] block.
  void reset() {
    _frameCursor = (_frameCursor + 1) % frameCount;
    _bufferCursor = 0;
    _offsetCursor = 0;
  }
}
