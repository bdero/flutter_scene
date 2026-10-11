import 'package:flutter_scene_xr/src/runtime_stub.dart'
    if (dart.library.js_interop) 'package:flutter_scene_xr/src/web/webxr_runtime.dart'
    as impl;
import 'package:flutter_scene_xr/src/xr_session.dart';

/// The XR runtime the platform offers, the entry point for sessions.
///
/// Today the only runtime is WebXR, so [isSupported] is true on the web in a
/// browser with the WebXR Device API and false everywhere else, where
/// [requestSession] throws [UnsupportedError].
/// {@category Sessions}
abstract class XrRuntime {
  /// The platform's runtime. Replaceable, so tests can install a fake.
  static XrRuntime instance = impl.createRuntime();

  /// Whether this platform has an XR runtime at all.
  bool get isSupported;

  /// Whether a [mode] session can be started right now.
  Future<bool> isSessionSupported(XrSessionMode mode);

  /// Starts a session. Throws [UnsupportedError] where [isSupported] is false
  /// and [StateError] when the runtime refuses the request.
  Future<XrSession> requestSession(XrSessionRequest request);

  /// The platform element to pass as [XrSessionRequest.domOverlayRoot] so the
  /// app's own UI shows over an `immersive-ar` session. On Flutter web this
  /// is the document body (the host of the Flutter view); null where there
  /// is no DOM.
  Object? get defaultDomOverlayRoot;
}
