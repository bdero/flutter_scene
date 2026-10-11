/// Drives the vendored IWER emulator from browser tests.
///
/// IWER puts an emulated headset on `navigator.xr`, which the package's
/// WebXR runtime then talks to as it would a real one. The runtime refills
/// one `XrFrame` per frame, so tests read frames through the snapshot types
/// here, copied inside the frame callback.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Rect;

import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart' show addTearDown;
import 'package:vector_math/vector_math.dart';
import 'package:web/web.dart' as web;

import 'iwer_bundle.g.dart';

/// How long a frame wait lasts before failing. Chrome runs
/// `requestAnimationFrame` only while the test page is visible.
const Duration frameTimeout = Duration(seconds: 5);

bool _bundleInstalled = false;
IwerDevice? _installedDevice;

/// Evaluates the vendored IWER bundle once, defining `globalThis.IWER`.
void installIwerBundle() {
  if (_bundleInstalled) return;
  final script = web.HTMLScriptElement()
    ..text = utf8.decode(base64.decode(iwerBundleBase64));
  web.document.head!.append(script);
  if (!globalContext.has('IWER')) {
    throw StateError('The IWER bundle did not define globalThis.IWER.');
  }
  _bundleInstalled = true;
}

/// A Meta Quest 3 emulation, not yet installed. Stereo is on so the right
/// eye gets a viewport.
IwerDevice createIwerDevice({bool stereo = true}) {
  installIwerBundle();
  final iwer = globalContext['IWER'] as JSObject;
  final options = JSObject()..['stereoEnabled'] = stereo.toJS;
  return (iwer['XRDevice'] as JSFunction).callAsConstructor<IwerDevice>(
    iwer['metaQuest3'],
    options,
  );
}

/// Creates a device and installs its runtime over `navigator.xr`. Pair with
/// [uninstallIwer].
IwerDevice installIwer({bool stereo = true}) {
  final existing = _installedDevice;
  if (existing != null) return existing;
  final device = createIwerDevice(stereo: stereo);
  // Desktop Chrome has a native but inert navigator.xr; without the flag
  // IWER only warns and installs nothing.
  device.installRuntime(JSObject()..['forceInstall'] = true.toJS);
  _installedDevice = device;
  return device;
}

/// Restores the browser's own `navigator.xr`. Safe to call twice.
void uninstallIwer() {
  final device = _installedDevice;
  if (device == null) return;
  _installedDevice = null;
  device.uninstallRuntime();
}

/// IWER's `XRDevice`.
extension type IwerDevice._(JSObject _) implements JSObject {
  external IwerVector3 get position;
  external IwerQuaternion get quaternion;
  external double get fovy;
  external set fovy(double value);
  external double get ipd;
  external set ipd(double value);
  external bool get stereoEnabled;
  external set stereoEnabled(bool value);
  external String get primaryInputMode;
  external set primaryInputMode(String value);
  external String get visibilityState;
  external IwerControllers get controllers;
  external IwerHands get hands;
  external void installRuntime(JSObject options);
  external void uninstallRuntime();
  external void recenter();

  /// Applied at the next frame. One of `visible`, `visible-blurred`,
  /// `hidden`.
  external void updateVisibilityState(String state);
}

/// A three-component vector on an IWER object, settable in place.
extension type IwerVector3._(JSObject _) implements JSObject {
  external double get x;
  external double get y;
  external double get z;
  @JS('set')
  external void setValues(double x, double y, double z);

  Vector3 toVector3() => Vector3(x, y, z);
}

/// A quaternion on an IWER object, settable in place.
extension type IwerQuaternion._(JSObject _) implements JSObject {
  external double get x;
  external double get y;
  external double get z;
  external double get w;
  @JS('set')
  external void setValues(double x, double y, double z, double w);
}

/// The device's two controllers.
extension type IwerControllers._(JSObject _) implements JSObject {
  external IwerController get left;
  external IwerController get right;
}

/// One emulated controller. Button and axis ids follow the profile
/// (`trigger`, `squeeze`, `thumbstick`, ...). Changes apply at the next
/// frame.
extension type IwerController._(JSObject _) implements JSObject {
  external IwerVector3 get position;
  external IwerQuaternion get quaternion;
  external void updateButtonValue(String id, double value);
  external void updateButtonTouch(String id, bool touched);
  external void updateAxes(String id, double x, double y);
}

/// The device's two hands.
extension type IwerHands._(JSObject _) implements JSObject {
  external IwerHand get left;
  external IwerHand get right;
}

/// One emulated hand. [poseId] is one of `default`, `pinch`, `point`,
/// `relaxed`.
extension type IwerHand._(JSObject _) implements JSObject {
  external IwerVector3 get position;
  external IwerQuaternion get quaternion;
  external String get poseId;
  external set poseId(String value);
}

/// Requests [request] and ends the session when the test finishes.
Future<XrSession> startSession(XrSessionRequest request) async {
  final session = await XrRuntime.instance.requestSession(request);
  addTearDown(() async {
    if (!session.isEnded) await session.end();
  });
  return session;
}

/// One view's values, copied out of the frame callback.
final class ViewSnapshot {
  ViewSnapshot(XrView view)
    : eye = view.eye,
      position = view.pose.position.clone(),
      orientation = view.pose.orientation.clone(),
      tanLeft = view.projection.tanLeft,
      tanRight = view.projection.tanRight,
      tanDown = view.projection.tanDown,
      tanUp = view.projection.tanUp,
      near = view.projection.near,
      far = view.projection.far,
      fovRadiansY = view.projection.fovRadiansY,
      aspectRatio = view.projection.aspectRatio,
      viewport = view.viewport,
      hasOwnTarget = view.target != null;

  final XrEye eye;
  final Vector3 position;
  final Quaternion orientation;
  final double tanLeft;
  final double tanRight;
  final double tanDown;
  final double tanUp;
  final double near;
  final double far;
  final double fovRadiansY;
  final double aspectRatio;
  final Rect viewport;
  final bool hasOwnTarget;
}

/// One input source's values, copied out of the frame callback.
final class InputSnapshot {
  InputSnapshot(XrInputSourceState state)
    : id = state.id,
      handedness = state.handedness,
      targetRayMode = state.targetRayMode,
      profiles = List.of(state.profiles),
      targetRayPosition = state.targetRayPose?.position.clone(),
      gripPosition = state.gripPose?.position.clone(),
      mapping = state.gamepad?.mapping,
      buttonValues = _copy(state.gamepad?.buttonValues),
      buttonPressed = _copy(state.gamepad?.buttonPressed),
      axes = _copy(state.gamepad?.axes),
      selectPressed = state.selectPressed,
      squeezePressed = state.squeezePressed,
      jointPositions = state.hand == null
          ? null
          : [for (final pose in state.hand!.jointPoses) pose.position.clone()],
      jointTracked = _copy(state.hand?.jointTracked);

  final int id;
  final XrHandedness handedness;
  final XrTargetRayMode targetRayMode;
  final List<String> profiles;
  final Vector3? targetRayPosition;
  final Vector3? gripPosition;
  final String? mapping;
  final List<double>? buttonValues;
  final List<bool>? buttonPressed;
  final List<double>? axes;
  final bool selectPressed;
  final bool squeezePressed;
  final List<Vector3>? jointPositions;
  final List<bool>? jointTracked;

  bool get hasGamepad => buttonValues != null;
  bool get hasHand => jointPositions != null;

  static List<T>? _copy<T>(List<T>? values) =>
      values == null ? null : List.of(values);
}

/// A frame's values, copied out of the frame callback.
final class FrameSnapshot {
  FrameSnapshot(XrFrame frame)
    : time = frame.predictedDisplayTime,
      referenceSpaceType = frame.referenceSpaceType,
      viewerPosition = frame.viewerPose?.position.clone(),
      viewerOrientation = frame.viewerPose?.orientation.clone(),
      views = [for (final view in frame.views) ViewSnapshot(view)],
      targetWidth = frame.target?.width,
      targetHeight = frame.target?.height,
      hasTargets = frame.hasTargets,
      inputSources = [
        for (final source in frame.inputSources) InputSnapshot(source),
      ];

  final Duration time;
  final XrReferenceSpaceType referenceSpaceType;
  final Vector3? viewerPosition;
  final Quaternion? viewerOrientation;
  final List<ViewSnapshot> views;
  final int? targetWidth;
  final int? targetHeight;
  final bool hasTargets;
  final List<InputSnapshot> inputSources;

  /// The source held in [handedness], or null.
  InputSnapshot? source(XrHandedness handedness) {
    for (final source in inputSources) {
      if (source.handedness == handedness) return source;
    }
    return null;
  }
}

/// The next frame [session] delivers after skipping [skip], as a snapshot.
/// [onFrame] runs on the live frame first, inside the callback.
Future<FrameSnapshot> nextFrame(
  XrSession session, {
  int skip = 0,
  void Function(XrFrame frame)? onFrame,
  Duration timeout = frameTimeout,
}) {
  final completer = Completer<FrameSnapshot>();
  var remaining = skip;
  late final StreamSubscription<XrFrame> subscription;
  subscription = session.frames.listen(
    (frame) {
      if (remaining > 0) {
        remaining--;
        return;
      }
      subscription.cancel();
      if (completer.isCompleted) return;
      onFrame?.call(frame);
      completer.complete(FrameSnapshot(frame));
    },
    onDone: () {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('The session ended before a frame arrived.'),
        );
      }
    },
  );
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      subscription.cancel();
      throw TimeoutException(
        'No XR frame within $timeout. Chrome runs requestAnimationFrame '
        'only while the test page is visible.',
      );
    },
  );
}

/// Frames until [ready] accepts one, at most [maxFrames]. Returns the last
/// frame seen either way, so a failing assertion shows real values.
Future<FrameSnapshot> frameWhere(
  XrSession session,
  bool Function(FrameSnapshot frame) ready, {
  int maxFrames = 30,
}) async {
  late FrameSnapshot last;
  for (var i = 0; i < maxFrames; i++) {
    last = await nextFrame(session);
    if (ready(last)) return last;
  }
  return last;
}

/// Frames that arrive on [session] during [window].
Future<int> countFramesFor(XrSession session, Duration window) async {
  var count = 0;
  final subscription = session.frames.listen((_) => count++);
  await Future<void>.delayed(window);
  await subscription.cancel();
  return count;
}

/// Every `<canvas>` in the document.
int canvasCount() => web.document.querySelectorAll('canvas').length;

/// The `<canvas>` elements styled `position: fixed`, the shape of the
/// runtime's presentation canvas.
int fixedCanvasCount() {
  final canvases = web.document.querySelectorAll('canvas');
  var count = 0;
  for (var i = 0; i < canvases.length; i++) {
    final canvas = canvases.item(i) as web.HTMLElement;
    if (canvas.style.position == 'fixed') count++;
  }
  return count;
}

/// The window's inner size in CSS pixels.
(int, int) windowInnerSize() => (web.window.innerWidth, web.window.innerHeight);
