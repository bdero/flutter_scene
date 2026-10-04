import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// Whether GPU commands execute while passes are encoded (the WebGL2 backend)
// rather than after submission. Decides the default transients strategy.
import 'package:flutter_scene/src/render/transients_execution_native.dart'
    if (dart.library.js_interop) 'package:flutter_scene/src/render/transients_execution_web.dart';

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

  // Ids of the last submission of recent frames, oldest first. A frame that
  // submitted nothing (one the scene paced by re-presenting) adds no entry.
  final List<int> _frameEnds = [];
  // The display frame each of [_frameEnds] rendered for.
  final List<Object?> _frameKeys = [];
  static const int _frameHistory = 8;
  Object? _displayFrame;

  /// Starts a render for the display frame [key]. Renders sharing a non-null
  /// key (several scenes painting in one vsync) end as one frame, and
  /// [priorFramesInFlight] leaves that frame out, so each of them makes the
  /// same pacing decision.
  void beginFrame(Object? key) {
    _displayFrame = key;
  }

  /// Marks the end of a frame's submissions, so [framesInFlight] can count
  /// whole frames the GPU has not finished.
  void endFrame() {
    if (_frameEnds.isNotEmpty && _frameEnds.last == _lastId) return;
    if (_pending.isEmpty && _frameEnds.isEmpty) return;
    if (_displayFrame != null &&
        _frameKeys.isNotEmpty &&
        _frameKeys.last == _displayFrame) {
      _frameEnds.last = _lastId;
      return;
    }
    _frameEnds.add(_lastId);
    _frameKeys.add(_displayFrame);
    if (_frameEnds.length > _frameHistory) {
      _frameEnds.removeAt(0);
      _frameKeys.removeAt(0);
    }
  }

  /// Ended frames whose last submission has not completed.
  int get framesInFlight => _countInFlight(null);

  /// [framesInFlight] without the current display frame's own renders.
  int get priorFramesInFlight => _countInFlight(_displayFrame);

  int _countInFlight(Object? skip) {
    final done = completedThrough;
    var count = 0;
    for (var i = 0; i < _frameEnds.length; i++) {
      if (skip != null && _frameKeys[i] == skip) continue;
      if (_frameEnds[i] > done) count++;
    }
    return count;
  }

  /// Submits [commandBuffer] and records it for completion tracking.
  void submit(gpu.CommandBuffer commandBuffer) {
    final int id = record();
    try {
      commandBuffer.submit(completionCallback: (_) => complete(id));
    } catch (_) {
      // A submission that never reaches the GPU never completes, and a
      // pending id would hold framesInFlight up for good.
      complete(id);
      rethrow;
    }
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

  final List<void Function()> _onCompleted = [];

  /// Registers [listener] to run after any submission completes.
  void addCompletionListener(void Function() listener) {
    _onCompleted.add(listener);
  }

  void removeCompletionListener(void Function() listener) {
    _onCompleted.remove(listener);
  }

  /// Marks a recorded submission as completed.
  @visibleForTesting
  void complete(int id) {
    _pending.remove(id);
    for (final listener in List.of(_onCompleted)) {
      listener();
    }
  }
}

/// The tracker for every command buffer the renderer submits.
final GpuSubmissionTracker rendererSubmissions = GpuSubmissionTracker();

/// How many `beginFrame` calls a pooled transient buffer may sit unused
/// before it is released. Pools reuse their most recently used buffer first,
/// so a steady workload keeps cycling the same buffers and never allocates,
/// while buffers left over from a spike go idle and age out.
///
/// Sizing the idle pool to recent usage instead churned: how many buffers
/// are idle at a given moment depends on when the GPU completes in-flight
/// frames, and `beginFrame` runs once per rendered view (not per frame) and
/// on paced frames that render nothing, so every such rule dropped buffers
/// the next frame needed.
const int kTransientIdleFrames = 240;

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

final Expando<ByteData> _scratchBytes = Expando('scratch bytes');

/// A byte view of the long-lived [scratch], made once and reused, for
/// emplacing the same scratch list every draw without a view per call.
///
/// Only pass a list that outlives the call. Each new list leaves an entry.
ByteData scratchBytesOf(TypedData scratch) =>
    _scratchBytes[scratch] ??= ByteData.sublistView(scratch);

/// A [TransientWriter] with the renderer's per-frame lifecycle. Implemented
/// by [TransientArena] (deferred-execution backends) and
/// [ImmediatePoolTransients] (the immediate-execution WebGL2 backend); the
/// engine's shared instances pick per platform via [createFrameTransients].
abstract interface class FrameTransients implements TransientWriter {
  /// Recycles completed buffers and resets frame stats. Called once per
  /// frame from the render setup.
  void beginFrame();
}

/// Per-emplacement pooled transients for the immediate-execution WebGL2
/// backend.
///
/// GL commands run while passes are encoded, so emplaced bytes must be
/// device-resident before the caller binds the returned view, and a buffer
/// written while earlier draws reference it forces the browser to ghost
/// (copy) it, which dominated per-draw cost before per-emplacement buffers
/// were introduced. Every emplacement therefore gets its own small device
/// buffer (sized to the next power-of-two class), written exactly once via
/// `overwrite` before the view is returned and never touched again while in
/// flight. Buffers recycle through a completion-gated pool per size class
/// and are released after [kTransientIdleFrames] unused frames, the same
/// policies as [TransientArena].
class ImmediatePoolTransients implements FrameTransients {
  ImmediatePoolTransients(this._tracker) {
    _tracker.addBeforeSubmitListener(_onBeforeSubmit);
  }

  /// The smallest pooled buffer size; tiny uniform blocks share this class.
  static const int kMinBufferLengthInBytes = 512;

  final GpuSubmissionTracker _tracker;

  /// Buffers handed out since the last submission; stamped by it.
  final List<_TransientBlock> _used = [];

  /// Stamped buffers, reusable once the watermark passes their stamp.
  final List<_TransientBlock> _pooled = [];

  int _frame = 0;

  /// Total live buffers. For tests.
  @visibleForTesting
  int get bufferCount => _used.length + _pooled.length;

  /// Device buffers every [ImmediatePoolTransients] has created. For tests
  /// that check steady-state rendering allocates nothing.
  @visibleForTesting
  static int buffersCreated = 0;

  static int _sizeClassFor(int length) {
    var size = kMinBufferLengthInBytes;
    while (size < length) {
      size <<= 1;
    }
    return size;
  }

  @override
  gpu.BufferView emplace(ByteData bytes) {
    final length = bytes.lengthInBytes;
    final sizeClass = _sizeClassFor(length);
    final completed = _tracker.completedThrough;

    // Most recently used first, so surplus buffers age out.
    _TransientBlock? block;
    for (var i = _pooled.length - 1; i >= 0; i--) {
      final candidate = _pooled[i];
      if (candidate.length == sizeClass && candidate.stamp <= completed) {
        block = candidate;
        _pooled.removeAt(i);
        break;
      }
    }
    block ??= _TransientBlock(
      _createBuffer(sizeClass),
      ByteData(0), // No CPU staging: writes go straight to the device.
      sizeClass,
      false,
    );
    block.lastUsed = _frame;
    _used.add(block);

    // Device-resident before the view is returned: the immediate backend
    // consumes it as soon as the caller binds and draws.
    if (!block.device.overwrite(bytes)) {
      debugPrint(
        'ImmediatePoolTransients: failed to upload $length bytes to a '
        '$sizeClass-byte transient buffer.',
      );
    }
    return gpu.BufferView(
      block.device,
      offsetInBytes: 0,
      lengthInBytes: length,
    );
  }

  static gpu.DeviceBuffer _createBuffer(int length) {
    buffersCreated++;
    return gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      length,
    );
  }

  void _onBeforeSubmit(int id) {
    for (final block in _used) {
      block.stamp = id;
      _pooled.add(block);
    }
    _used.clear();
  }

  @override
  void beginFrame() {
    _onBeforeSubmit(_tracker.latestSubmission);
    _frame++;
    final completed = _tracker.completedThrough;
    _pooled.removeWhere(
      (block) =>
          block.stamp <= completed &&
          _frame - block.lastUsed > kTransientIdleFrames,
    );
  }
}

/// Creates the platform-default [FrameTransients]: a staged, block-based
/// [TransientArena] where GPU work executes after submission, and a
/// per-emplacement [ImmediatePoolTransients] where GL commands execute at
/// encode time and a bound buffer can never be written again.
FrameTransients createFrameTransients(
  GpuSubmissionTracker tracker, {
  int? alignment,
}) => kImmediateGpuExecution
    ? ImmediatePoolTransients(tracker)
    : TransientArena(tracker, alignment: alignment);

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
/// the pool grows with actual GPU queue depth, and blocks unused for
/// [kTransientIdleFrames] are released so memory shrinks back after load
/// spikes. Requests larger than [blockLengthInBytes] use pooled
/// power-of-two size classes so a changing visible-instance count does not
/// allocate a new CPU/GPU buffer every frame.
class TransientArena implements FrameTransients {
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

  int _frame = 0;

  /// Total pooled blocks (open + sealed). For tests.
  @visibleForTesting
  int get blockCount => _open.length + _sealed.length;

  /// Device buffers every [TransientArena] has created. For tests that
  /// check steady-state rendering allocates nothing.
  @visibleForTesting
  static int buffersCreated = 0;

  /// Begins a new frame: applies the shrink policy and resets frame stats.
  /// Open blocks from the previous frame (possible when a frame emplaced
  /// data but submitted nothing) seal with the latest submission stamp, so
  /// they stay safe against any in-flight work.
  @override
  void beginFrame() {
    for (final block in _open) {
      _seal(block, _tracker.latestSubmission);
    }
    _open.clear();
    _frame++;
    final completed = _tracker.completedThrough;
    _sealed.removeWhere(
      (block) =>
          block.stamp <= completed &&
          _frame - block.lastUsed > kTransientIdleFrames,
    );
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

    // Same math as [planEmplacement], inlined so the per-draw path builds no
    // record.
    var block = _open.isEmpty ? null : _open.last;
    var offset = 0;
    if (block != null) {
      final alignment = _alignment;
      final misalignment = block.cursor % alignment;
      offset = misalignment == 0
          ? block.cursor
          : block.cursor + alignment - misalignment;
      if (offset + length > block.length) block = null;
    }
    if (block == null) {
      block = _acquireBlock(blockLengthInBytes);
      _open.add(block);
      offset = 0;
    }

    block.stage(offset, bytes);
    block.cursor = offset + length;
    return gpu.BufferView(
      block.device,
      offsetInBytes: offset,
      lengthInBytes: length,
    );
  }

  gpu.BufferView _emplaceOversize(ByteData bytes) {
    final capacity = _oversizeSizeClass(bytes.lengthInBytes);
    final block = _acquireBlock(capacity, oversize: true);
    _open.add(block);
    block.stage(0, bytes);
    block.cursor = bytes.lengthInBytes;
    return gpu.BufferView(
      block.device,
      offsetInBytes: 0,
      lengthInBytes: bytes.lengthInBytes,
    );
  }

  int _oversizeSizeClass(int length) {
    var capacity = blockLengthInBytes;
    while (capacity < length) {
      capacity <<= 1;
    }
    return capacity;
  }

  /// Reuses a completed pooled block, most recently used first so surplus
  /// blocks age out, or creates a new one.
  _TransientBlock _acquireBlock(int length, {bool oversize = false}) {
    final completed = _tracker.completedThrough;
    for (var i = _sealed.length - 1; i >= 0; i--) {
      final block = _sealed[i];
      if (block.stamp > completed) continue;
      if (block.oversize != oversize) continue;
      if (block.length != length) continue;
      _sealed.removeAt(i);
      block
        ..cursor = 0
        ..lastUsed = _frame;
      return block;
    }
    buffersCreated++;
    final device = gpu.gpuContext.createDeviceBuffer(
      gpu.StorageMode.hostVisible,
      length,
    );
    return _TransientBlock(device, ByteData(length), length, oversize)
      ..lastUsed = _frame;
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
  _TransientBlock(this.device, this.staging, this.length, this.oversize)
    : _stagingBytes = staging.buffer.asUint8List(
        staging.offsetInBytes,
        staging.lengthInBytes,
      );

  /// Writes up to this many bytes word by word, below the cost of the source
  /// view a bulk copy needs. Uniform blocks land here.
  static const int _wordCopyLimit = 256;

  final gpu.DeviceBuffer device;
  final ByteData staging;
  final Uint8List _stagingBytes;
  final int length;
  final bool oversize;

  /// Copies [bytes] into the staging at [offset].
  void stage(int offset, ByteData bytes) {
    final length = bytes.lengthInBytes;
    if (length <= _wordCopyLimit && length & 3 == 0) {
      for (var i = 0; i < length; i += 4) {
        staging.setUint32(
          offset + i,
          bytes.getUint32(i, Endian.host),
          Endian.host,
        );
      }
      return;
    }
    _stagingBytes.setRange(
      offset,
      offset + length,
      bytes.buffer.asUint8List(bytes.offsetInBytes, length),
    );
  }

  /// Bytes staged so far while open; reset when sealed.
  int cursor = 0;

  /// The last submission id that may reference this block's device buffer.
  int stamp = 0;

  /// The owner's frame count when this block was last handed out.
  int lastUsed = 0;
}

/// The renderer's per-frame uniform transients (alignment resolved from the
/// GPU context's minimum uniform alignment).
final FrameTransients uniformTransients = createFrameTransients(
  rendererSubmissions,
);

/// The renderer's per-frame instance-rate vertex transients. Vertex fetch
/// needs only element alignment; 16 bytes covers a vec4 column.
final FrameTransients instanceTransients = createFrameTransients(
  rendererSubmissions,
  alignment: 16,
);
