import 'package:flutter_scene_xr/src/xr_runtime.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';

/// The runtime on platforms with no XR support.
XrRuntime createRuntime() => const UnsupportedXrRuntime();

/// An [XrRuntime] that supports nothing, the default off the web.
// TODO(xr-native): native OpenXR and handheld AR runtimes replace this on
// their platforms once they exist.
final class UnsupportedXrRuntime implements XrRuntime {
  /// The unsupported runtime.
  const UnsupportedXrRuntime();

  @override
  bool get isSupported => false;

  @override
  Future<bool> isSessionSupported(XrSessionMode mode) => Future.value(false);

  @override
  Future<XrSession> requestSession(XrSessionRequest request) =>
      Future.error(UnsupportedError('This platform has no XR runtime.'));

  @override
  Object? get defaultDomOverlayRoot => null;
}
