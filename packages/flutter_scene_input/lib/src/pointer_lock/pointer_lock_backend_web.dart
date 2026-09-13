import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Offset;

import 'package:web/web.dart' as web;

import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_backend.dart';

// Pointer Lock API, https://www.w3.org/TR/pointerlock-2/

PointerLockBackend createPointerLockBackend() => _WebPointerLock();

final class _WebPointerLock implements PointerLockBackend {
  bool _listening = false;
  bool _releasing = false;
  double _dx = 0;
  double _dy = 0;
  Completer<bool>? _pending;
  void Function(PointerLockLoss reason)? _onLost;

  @override
  bool get isSupported => true;

  bool get _locked => web.document.pointerLockElement != null;

  @override
  Future<bool> request() {
    _listen();
    if (_locked) return Future<bool>.value(true);
    final existing = _pending;
    if (existing != null) return existing.future;

    // Flutter renders into <flutter-view>; locking it rather than <body> keeps
    // an embedded view from capturing the whole page.
    final target =
        web.document.querySelector('flutter-view') ?? web.document.body;
    if (target == null) return Future<bool>.value(false);

    final completer = Completer<bool>();
    _pending = completer;
    try {
      // Browsers without the promise form return undefined; a rejection also
      // fires pointerlockerror, so the events are the signal either way.
      final result = target.callMethod<JSAny?>('requestPointerLock'.toJS);
      if (result.isA<JSPromise>()) {
        (result as JSPromise).toDart.ignore();
      }
    } catch (_) {
      _pending = null;
      return Future<bool>.value(false);
    }
    // A request the browser silently drops would otherwise never settle.
    return completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _pending = null;
        return _locked;
      },
    );
  }

  @override
  void release() {
    if (!_locked) return;
    _releasing = true;
    web.document.exitPointerLock();
  }

  @override
  Offset takeMovement() {
    final movement = Offset(_dx, _dy);
    _dx = 0;
    _dy = 0;
    return movement;
  }

  @override
  set onLost(void Function(PointerLockLoss reason)? callback) {
    _onLost = callback;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    web.document.addEventListener('pointerlockchange', _handleChange.toJS);
    web.document.addEventListener('pointerlockerror', _handleError.toJS);
    web.document.addEventListener('mousemove', _handleMove.toJS);
  }

  void _handleChange(web.Event event) {
    final pending = _pending;
    _pending = null;
    if (_locked) {
      _dx = 0;
      _dy = 0;
      pending?.complete(true);
      return;
    }
    pending?.complete(false);
    if (_releasing) {
      _releasing = false;
      return;
    }
    final blurred = web.document.hidden || !web.document.hasFocus();
    _onLost?.call(
      blurred ? PointerLockLoss.focusLost : PointerLockLoss.userExit,
    );
  }

  void _handleError(web.Event event) {
    _pending?.complete(false);
    _pending = null;
  }

  void _handleMove(web.Event event) {
    if (!_locked) return;
    final move = event as web.MouseEvent;
    _dx += move.movementX;
    _dy += move.movementY;
  }
}
