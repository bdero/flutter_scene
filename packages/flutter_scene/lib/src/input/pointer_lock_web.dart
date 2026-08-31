import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:flutter_scene/src/input/pointer_lock_base.dart';

/// Captures the mouse through the browser's Pointer Lock API.
///
/// See [PointerLockSource] for the contract and for why a first-person game
/// wants this. Two browser behaviours shape the implementation:
///
///  * A lock is only granted from a user gesture, so [request] has to be
///    called from a tap or click handler rather than from game logic.
///  * While locked, a `mousemove` carries `movementX`/`movementY` and a frozen
///    position. Flutter computes its pointer deltas from positions, so its own
///    events read as motionless under a lock; this source reads the movement
///    fields off the DOM event directly, which is the only place the real
///    numbers exist.
final class PointerLock extends PointerLockSource {
  /// Creates a source and starts watching the document's lock state.
  PointerLock() {
    _onChange = _handleChange.toJS;
    _onError = _handleError.toJS;
    _onMove = _handleMove.toJS;
    web.document.addEventListener('pointerlockchange', _onChange);
    web.document.addEventListener('pointerlockerror', _onError);
    web.document.addEventListener('mousemove', _onMove);
  }

  late final JSFunction _onChange;
  late final JSFunction _onError;
  late final JSFunction _onMove;

  Completer<bool>? _pending;

  @override
  bool get isSupported => true;

  @override
  bool get isLocked => web.document.pointerLockElement != null;

  @override
  Future<bool> request() {
    if (isLocked) return Future<bool>.value(true);
    final existing = _pending;
    if (existing != null) return existing.future;

    final target = web.document.body ?? web.document.documentElement;
    if (target == null) return Future<bool>.value(false);

    final completer = Completer<bool>();
    _pending = completer;
    try {
      // Older browsers return undefined rather than a promise, and a rejected
      // promise also arrives as a `pointerlockerror`, so the events are the
      // reliable signal either way and the return value is ignored.
      target.requestPointerLock();
    } catch (_) {
      _pending = null;
      return Future<bool>.value(false);
    }
    // A browser that silently drops the request would leave the caller waiting
    // forever, so give up after a moment and report what actually happened.
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _pending = null;
        return isLocked;
      },
    );
  }

  @override
  void release() {
    if (isLocked) web.document.exitPointerLock();
  }

  @override
  void detach() {
    super.detach();
    web.document.removeEventListener('pointerlockchange', _onChange);
    web.document.removeEventListener('pointerlockerror', _onError);
    web.document.removeEventListener('mousemove', _onMove);
  }

  void _handleChange(web.Event event) {
    _pending?.complete(isLocked);
    _pending = null;
    notifyLockChanged();
  }

  void _handleError(web.Event event) {
    _pending?.complete(false);
    _pending = null;
    notifyLockChanged();
  }

  void _handleMove(web.Event event) {
    if (!isLocked) return;
    final move = event as web.MouseEvent;
    publishMovement(move.movementX, move.movementY);
  }
}
