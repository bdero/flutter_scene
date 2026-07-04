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

  /// The id of the most recent submission.
  int get latestSubmission => _lastId;

  /// The highest id such that all submissions up to and including it have
  /// completed.
  int get completedThrough => _pending.isEmpty ? _lastId : _pending.first - 1;

  /// Submits [commandBuffer] and records it for completion tracking.
  void submit(gpu.CommandBuffer commandBuffer) {
    final int id = record();
    commandBuffer.submit(completionCallback: (_) => complete(id));
  }

  /// Records a submission without a command buffer. Prefer [submit].
  @visibleForTesting
  int record() {
    final int id = ++_lastId;
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

/// Rotates per-frame transient [gpu.HostBuffer]s so that one is never reset
/// while the GPU may still read data written into it.
///
/// [gpu.HostBuffer] recycles its internal storage a fixed number of resets
/// after data is written, which corrupts rendering when frames are deep in
/// flight on the GPU. The pool sidesteps that by handing out a buffer whose
/// previously submitted work has completed, or a fresh buffer when none has.
/// Buffer memory therefore grows with actual GPU queue depth and shrinks
/// back when the queue drains.
class TransientsPool {
  TransientsPool(this._tracker);

  final GpuSubmissionTracker _tracker;
  final List<_PoolEntry> _entries = [];
  _PoolEntry? _current;

  /// The number of pooled buffers. Used for tests.
  @visibleForTesting
  int get length => _entries.length;

  /// Returns a reset [gpu.HostBuffer] that is safe to write this frame.
  ///
  /// Call exactly once per frame before any emplacement.
  gpu.HostBuffer beginFrame() {
    // Everything submitted so far may reference the previous frame's buffer.
    _current?.stamp = _tracker.latestSubmission;

    final int completed = _tracker.completedThrough;
    _PoolEntry? chosen;
    for (final _PoolEntry entry in _entries) {
      if (!identical(entry, _current) && entry.stamp <= completed) {
        chosen = entry;
        break;
      }
    }
    if (chosen == null) {
      chosen = _PoolEntry(gpu.gpuContext.createHostBuffer());
      _entries.add(chosen);
    }

    // Drop surplus idle buffers so the pool shrinks after load spikes. One
    // idle spare is kept to avoid churn at steady state.
    int idleKept = 0;
    _entries.removeWhere((_PoolEntry entry) {
      final bool idle =
          !identical(entry, _current) &&
          !identical(entry, chosen) &&
          entry.stamp <= completed;
      if (!idle) {
        return false;
      }
      idleKept++;
      return idleKept > 1;
    });

    chosen.buffer.reset();
    _current = chosen;
    return chosen.buffer;
  }
}

class _PoolEntry {
  _PoolEntry(this.buffer);

  final gpu.HostBuffer buffer;

  /// The last submission id that may reference this buffer's contents.
  int stamp = 0;
}
