import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

FocusLockObserver createFocusLockObserver(VoidCallback onUnlocked) =>
    FocusLockObserver(onUnlocked);

class FocusLockObserver {
  FocusLockObserver(this._onUnlocked) {
    _listener = _handleChange.toJS;
    web.document.addEventListener('pointerlockchange', _listener);
  }

  final VoidCallback _onUnlocked;
  late final web.EventListener _listener;
  bool _sawLock = false;

  void _handleChange(web.Event event) {
    if (web.document.pointerLockElement != null) {
      _sawLock = true;
    } else if (_sawLock) {
      _sawLock = false;
      _onUnlocked();
    }
  }

  void dispose() {
    web.document.removeEventListener('pointerlockchange', _listener);
  }
}
