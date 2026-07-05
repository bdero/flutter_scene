import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// Tracks GPU completion of command buffers submitted by the renderer.
///
/// Submissions are recorded with monotonically increasing ids and marked
/// done from the command buffer completion callback. [completedThrough]
/// reports the highest id such that all submissions up to and including it
/// have completed, regardless of the order in which individual command
/// buffers finish.
class GpuSubmissionTracker {
  int _lastId = 0;
  final SplayTreeSet<int> _pending = SplayTreeSet<int>();
  final List<void Function(int id)> _beforeSubmit = [];

  /// The id of the most recent submission.
  int get latestSubmission => _lastId;

  /// The highest id such that all submissions up to and including it have
  /// completed.
  int get completedThrough => _pending.isEmpty ? _lastId : _pending.first - 1;

  /// Registers [listener] to run just before every submission, with the id
  /// the submission will get. Transient arenas use this to upload and seal
  /// their staged blocks so the submitted work reads complete data.
  void addBeforeSubmitListener(void Function(int id) listener) {
    _beforeSubmit.add(listener);
  }

  /// Submits [commandBuffer] and records it for completion tracking.
  void submit(gpu.CommandBuffer commandBuffer) {
    final int id = record();
    commandBuffer.submit(completionCallback: (_) => complete(id));
  }

  /// Records a submission without a command buffer. Prefer [submit].
  @visibleForTesting
  int record() {
    final int id = _lastId + 1;
    for (final listener in _beforeSubmit) {
      listener(id);
    }
    _lastId = id;
    _pending.add(id);
    return id;
  }

  /// Marks a recorded submission as completed.
  @visibleForTesting
  void complete(int id) {
    _pending.remove(id);
  }
}

/// The tracker for every command buffer the renderer submits.
final GpuSubmissionTracker rendererSubmissions = GpuSubmissionTracker();

/// Destination for per-frame transient GPU data (uniform blocks, instance
/// vertex data). Emplaced data is valid for the current frame only.
///
/// {@category Rendering}
abstract interface class TransientWriter {
  /// Appends [bytes] and returns a view referencing them, aligned per the
  /// writer's purpose. The view must only be used by work submitted this
  /// frame.
  gpu.BufferView emplace(ByteData bytes);
}

/// A completion-aware bump allocator for per-frame transient GPU data.
///
/// Emplacements are staged CPU-side into fixed-size blocks and returned as
/// views of the block's device buffer. Just before each command buffer
/// submission (via [GpuSubmissionTracker.addBeforeSubmitListener]), every
/// open block uploads its used range in a single write and is sealed; the
/// next emplacement opens a fresh block. A sealed block's device buffer is
/// never written again until the GPU work referencing it completes and the
/// block is recycled, so in-flight frames can never observe a partial or
/// overwritten buffer, no backend ever needs to ghost (copy) a buffer on
/// write, and per-emplacement device writes collapse into one write per
/// block per submitting pass.
///
/// Blocks are pooled: reuse is gated on the tracker's completion watermark,
/// the pool grows with actual GPU queue depth, and idle blocks beyond the
/// previous frame's usage (plus a spare) are dropped so memory shrinks back
/// after load spikes. Requests larger than [blockLengthInBytes] get a
/// dedicated buffer that is pooled the same way.
class TransientArena implements TransientWriter {
  TransientArena(
    this._tracker, {
    int? alignment,
    this.blockLengthInBytes = kDefaultBlockLengthInBytes,
  }) : _alignmentOverride = alignment {
    _tracker.addBeforeSubmitListener(_onBeforeSubmit);
  }

  /// The default block size. Small enough that sealing a barely-used block
  /// per pass is cheap, large enough that heavy frames don't roll over
  /// constantly.
  static const int kDefaultBlockLengthInBytes = 256 * 1024;

  final GpuSubmissionTracker _tracker;
  final int blockLengthInBytes;

  /// Emplacement alignment. When null, the GPU context's minimum uniform
  /// alignment is used (resolved lazily; the context itself initializes on
  /// the raster thread after startup on some backends).
  final int? _alignmentOverride;
  int? _resolvedAlignment;
  int get _alignment =>
      _resolvedAlignment ??
      (_resolvedAlignment =
          _alignmentOverride ?? gpu.gpuContext.minimumUniformByteAlignment);

  /// Blocks open for writing this frame, in fill order; the last one is the
  /// bump target. All of them seal on the next submission.
  final List<_TransientBlock> _open = [];

  /// Sealed blocks whose GPU work has not necessarily completed. Reused once
  /// the tracker's watermark passes their stamp.
  final List<_TransientBlock> _sealed = [];

  /// Standard-size blocks acquired by the previous/current frame, for the
  /// shrink policy.
  int _lastFrameBlockCount = 0;
  int _thisFrameBlockCount = 0;

  /// Total pooled blocks (open + sealed). For tests.
  @visibleForTesting
  int get blockCount => _open.length + _sealed.length;

  /// Begins a new frame: applies the shrink policy and resets frame stats.
  /// Open blocks from the previous frame (possible when a frame emplaced
  /// data but submitted nothing) seal with the latest submission stamp, so
  /// they stay safe against any in-flight work.
  void beginFrame() {
    for (final block in _open) {
      _seal(block, _tracker.latestSubmission);
    }
    _open.clear();

    // Shrink: drop completed standard blocks beyond last frame's usage plus
    // one spare. Oversize blocks are dropped as soon as they complete (they
    // are rare and their sizes rarely repeat).
    final completed = _tracker.completedThrough;
    final keepStandard = _lastFrameBlockCount + 1;
    var idleStandard = 0;
    _sealed.removeWhere((block) {
      if (block.stamp > completed) return false; // still in flight
      if (block.oversize) return true;
      idleStandard++;
      return idleStandard > keepStandard;
    });

    _lastFrameBlockCount = _thisFrameBlockCount;
    _thisFrameBlockCount = 0;
  }

  /// Decides where an emplacement of [length] lands: at the aligned offset
  /// within the current block, or at 0 in a fresh block when the write's END
  /// would cross the block's capacity. The full write length participates in
  /// the bounds check; checking only the aligned start (the flutter_gpu
  /// HostBuffer bug) hands out views that overrun the buffer.
  @visibleForTesting
  static ({bool rollOver, int offset}) planEmplacement({
    required int cursor,
    required int alignment,
    required int length,
    required int blockLength,
  }) {
    final misalignment = cursor % alignment;
    final aligned = misalignment == 0
        ? cursor
        : cursor + alignment - misalignment;
    if (aligned + length > blockLength) {
      return (rollOver: true, offset: 0);
    }
    return (rollOver: false, offset: aligned);
  }

  @override
  gpu.BufferView emplace(ByteData bytes) {
    final length = bytes.lengthInBytes;
    if (length > blockLengthInBytes) {
      return _emplaceOversize(bytes);
    }

    var block = _open.isEmpty ? null : _open.last;
    var offset = 0;
    if (block != null) {
      final plan = planEmplacement(
        cursor: block.cursor,
        alignment: _alignment,
        length: length,
        blockLength: block.length,
      );
      offset = plan.offset;
      if (plan.rollOver) block = null;
    }
    if (block == null) {
      block = _acquireBlock(blockLengthInBytes);
      _open.add(block);
      _thisFrameBlockCount++;
      offset = 0;
    }

    block.staging.buffer
        .asUint8List(block.staging.offsetInBytes)
        .setRange(
          offset,
          offset + length,
          bytes.buffer.asUint8List(bytes.offsetInBytes, length),
        );
    block.cursor = offset + length;
    return gpu.BufferView(
      block.device,
      offsetInBytes: offset,
      lengthInBytes: length,
    );
  }

  gpu.BufferView _emplaceOversize(ByteData bytes) {
    final block = _acquireBlock(bytes.lengthInBytes, oversize: true);
    _open.add(block);
    block.staging.buffer
        .asUint8List(block.staging.offsetInBytes)
        .setRange(
          0,
          bytes.lengthInBytes,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
    block.cursor = bytes.lengthInBytes;
    return gpu.BufferView(
      block.device,
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  /// Reuses a completed pooled block or creates a new one. For oversize
  /// requests, a pooled oversize block is reused when it fits without more
  /// than doubling the waste.
  _TransientBlock _acquireBlock(int length, {bool oversize = false}) {
    final completed = _tracker.completedThrough;
    for (var i = 0; i < _sealed.length; i++) {
      final block = _sealed[i];
      if (block.stamp > completed) continue;
      if (block.oversize != oversize) continue;
      if (oversize && (block.length < length || block.length > 2 * length)) {
        continue;
      }
      _sealed.removeAt(i);
      block.cursor = 0;
      return block;
    }
    final device = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      oversize ? length : blockLengthInBytes,
    );
    final capacity = oversize ? length : blockLengthInBytes;
    return _TransientBlock(device, ByteData(capacity), capacity, oversize);
  }

  /// Uploads and seals every open block. Runs just before each submission,
  /// so the submitted work reads fully-written buffers; [id] is the
  /// submission being recorded, which is the last one that may reference
  /// these blocks.
  void _onBeforeSubmit(int id) {
    for (final block in _open) {
      _seal(block, id);
    }
    _open.clear();
  }

  void _seal(_TransientBlock block, int stamp) {
    if (block.cursor > 0) {
      final ok = block.device.overwrite(
        ByteData.sublistView(block.staging, 0, block.cursor),
      );
      if (!ok) {
        // A failed upload must not throw mid-encode (an aborted frame is
        // strictly worse than one pass reading zeroes); it also cannot
        // happen by construction (the staged range always fits the buffer).
        debugPrint(
          'TransientArena: failed to upload ${block.cursor} bytes to a '
          '${block.length}-byte transient block.',
        );
      }
      block.device.flush(offsetInBytes: 0, lengthInBytes: block.cursor);
    }
    block.stamp = stamp;
    block.cursor = 0;
    _sealed.add(block);
  }
}

class _TransientBlock {
  _TransientBlock(this.device, this.staging, this.length, this.oversize);

  final gpu.DeviceBuffer device;
  final ByteData staging;
  final int length;
  final bool oversize;

  /// Bytes staged so far while open; reset when sealed.
  int cursor = 0;

  /// The last submission id that may reference this block's device buffer.
  int stamp = 0;
}

/// The renderer's per-frame uniform transients (alignment resolved from the
/// GPU context's minimum uniform alignment).
final TransientArena uniformTransients = TransientArena(rendererSubmissions);

/// The renderer's per-frame instance-rate vertex transients. Vertex fetch
/// needs only element alignment; 16 bytes covers a vec4 column.
final TransientArena instanceTransients = TransientArena(
  rendererSubmissions,
  alignment: 16,
);
