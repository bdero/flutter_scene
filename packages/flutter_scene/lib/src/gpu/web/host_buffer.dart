part of '_gpu.dart';

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
/// Backend neutral: it only allocates [DeviceBuffer]s from its context. The
/// renderer does not use it (its transients ride the completion-aware arenas
/// in `render/frame_transients.dart`); direct shim consumers do.
final class BumpHostBuffer extends HostBuffer {
  static const int _kFrameCount = 4;

  BumpHostBuffer(
    this._gpuContext, {
    this.blockLengthInBytes = HostBuffer.kDefaultBlockLengthInBytes,
  }) {
    for (var frame = 0; frame < _kFrameCount; frame++) {
      _buffers.add([_allocateNewBlock(blockLengthInBytes)]);
    }
  }

  final GpuContext _gpuContext;

  /// The length of each [DeviceBuffer] block.
  @override
  final int blockLengthInBytes;

  @override
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
  @override
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
  @override
  void reset() {
    _frameCursor = (_frameCursor + 1) % frameCount;
    _bufferCursor = 0;
    _offsetCursor = 0;
  }
}
