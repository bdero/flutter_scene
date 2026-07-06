import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_scene/src/splats/splat_sort_service.dart';
import 'package:flutter_scene/src/splats/splat_sorter.dart';

/// Creates the isolate-backed sorter.
SplatSortService createSplatSortService(Float32List positions, int count) =>
    _IsolateSplatSortService(positions, count);

class _IsolateSplatSortService implements SplatSortService {
  _IsolateSplatSortService(this._positions, this._count);

  final Float32List _positions;
  final int _count;

  bool _disposed = false;
  Future<SendPort>? _requests;
  ReceivePort? _fromWorker;
  Completer<Float32List?>? _pending;

  // Spawns the worker on first use, copying the positions once; the copy
  // transfers into the isolate rather than being re-serialized.
  Future<SendPort> _ensureWorker() {
    return _requests ??= () async {
      final fromWorker = ReceivePort();
      _fromWorker = fromWorker;
      final ready = Completer<SendPort>();
      fromWorker.listen((message) {
        if (!ready.isCompleted) {
          ready.complete(message as SendPort);
          return;
        }
        final pending = _pending;
        _pending = null;
        pending?.complete(
          (message as TransferableTypedData).materialize().asFloat32List(),
        );
      });
      await Isolate.spawn(splatSorterIsolateMain, <Object>[
        fromWorker.sendPort,
        TransferableTypedData.fromList([_positions]),
        _count,
      ], debugName: 'flutter_scene splat sorter');
      return ready.future;
    }();
  }

  @override
  Future<Float32List?> sort(double dirX, double dirY, double dirZ) async {
    if (_disposed) return null;
    assert(_pending == null, 'A sort is already in flight.');
    final worker = await _ensureWorker();
    if (_disposed) return null;
    final pending = Completer<Float32List?>();
    _pending = pending;
    worker.send(<double>[dirX, dirY, dirZ]);
    return pending.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pending?.complete(null);
    _pending = null;
    // Ask the worker to exit once it is up (it may still be spawning).
    _requests?.then((worker) {
      worker.send(null);
      _fromWorker?.close();
    });
  }
}

/// The sorter isolate: receives the positions once at spawn, then serves
/// direction requests until a null message asks it to exit.
void splatSorterIsolateMain(List<Object> init) {
  final replyTo = init[0] as SendPort;
  final positions = (init[1] as TransferableTypedData)
      .materialize()
      .asFloat32List();
  final count = init[2] as int;

  final requests = ReceivePort();
  replyTo.send(requests.sendPort);
  requests.listen((message) {
    if (message == null) {
      requests.close();
      return;
    }
    final dir = message as List<double>;
    final order = sortSplatsBackToFront(
      positions,
      count,
      dir[0],
      dir[1],
      dir[2],
    );
    replyTo.send(TransferableTypedData.fromList([order]));
  });
}
