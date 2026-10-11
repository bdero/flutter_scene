import 'package:flutter_scene_xr/src/features/anchors.dart';
import 'package:flutter_scene_xr/src/features/depth.dart';
import 'package:flutter_scene_xr/src/features/hit_test.dart';
import 'package:flutter_scene_xr/src/features/light_estimation.dart';
import 'package:flutter_scene_xr/src/features/planes.dart';
import 'package:flutter_scene_xr/src/xr_frame.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';

/// What kind of session to run.
/// {@category Sessions}
enum XrSessionMode {
  /// A headset or phone fully covered by rendered content.
  immersiveVr('immersive-vr'),

  /// Rendered content over the real world, passthrough or a camera feed.
  immersiveAr('immersive-ar'),

  /// Tracking without taking over the display; the content stays in the
  /// page.
  inline('inline');

  const XrSessionMode(this.webName);

  /// The mode's name in the WebXR Device API.
  final String webName;
}

/// Where a session's poses are measured from.
/// {@category Sessions}
enum XrReferenceSpaceType {
  /// The viewer itself; every pose is relative to the head.
  viewer('viewer'),

  /// A fixed origin near the viewer's starting position.
  local('local'),

  /// [local] with the origin on the floor.
  localFloor('local-floor'),

  /// [localFloor] with known play-area bounds.
  boundedFloor('bounded-floor'),

  /// A tracking origin that may be re-anchored as the viewer walks far.
  unbounded('unbounded');

  const XrReferenceSpaceType(this.webName);

  /// The type's name in the WebXR Device API.
  final String webName;
}

/// How rendered content combines with the real world.
/// {@category Sessions}
enum XrBlendMode {
  /// Nothing of the world shows; the scene replaces it.
  opaque,

  /// Light is added to the world (see-through optics), so black is
  /// transparent.
  additive,

  /// The scene's alpha blends over the world (camera passthrough).
  alphaBlend,
}

/// Why a session ended.
/// {@category Sessions}
enum XrSessionEndReason {
  /// The app or the runtime ended it normally.
  ended,

  /// The graphics context was lost while the session ran.
  contextLost,

  /// The runtime reported a failure.
  runtimeError,
}

/// Feature names a session may request, as the WebXR Device API spells them.
/// {@category Sessions}
abstract final class XrFeatures {
  static const String local = 'local';
  static const String localFloor = 'local-floor';
  static const String boundedFloor = 'bounded-floor';
  static const String unbounded = 'unbounded';
  static const String hitTest = 'hit-test';
  static const String anchors = 'anchors';
  static const String planeDetection = 'plane-detection';
  static const String handTracking = 'hand-tracking';
  static const String depthSensing = 'depth-sensing';
  static const String lightEstimation = 'light-estimation';
  static const String domOverlay = 'dom-overlay';
  static const String layers = 'layers';
}

/// What to ask the runtime for when starting a session.
/// {@category Sessions}
class XrSessionRequest {
  /// A request for a [mode] session.
  ///
  /// [requiredFeatures] fail the request when the runtime lacks one;
  /// [optionalFeatures] are granted when available (see [XrFeatures]).
  /// [referenceSpaces] are tried in order and the first the runtime grants
  /// becomes the session's; the matching feature is requested for you.
  /// [domOverlayRoot] is the platform element to show over the scene in
  /// `immersive-ar` on a phone; on Flutter web pass
  /// `XrRuntime.defaultDomOverlayRoot`, the document body hosting the Flutter
  /// view, so the app's own UI stays usable.
  const XrSessionRequest({
    required this.mode,
    this.requiredFeatures = const [],
    this.optionalFeatures = const [],
    this.referenceSpaces = const [
      XrReferenceSpaceType.localFloor,
      XrReferenceSpaceType.local,
      XrReferenceSpaceType.viewer,
    ],
    this.domOverlayRoot,
    this.useProjectionLayers = false,
  });

  /// What kind of session.
  final XrSessionMode mode;

  /// Features the session cannot run without.
  final List<String> requiredFeatures;

  /// Features to use when the runtime has them.
  final List<String> optionalFeatures;

  /// Reference spaces in order of preference.
  final List<XrReferenceSpaceType> referenceSpaces;

  /// The element to composite over the scene, or null for none.
  final Object? domOverlayRoot;

  /// Whether to render through per-view projection layers where the runtime
  /// offers them, instead of one shared layer framebuffer.
  // TODO(xr-layers): the projection layer path is untested on a headset;
  // flip the default once it has been seen rendering on one.
  final bool useProjectionLayers;
}

/// A running XR session, the frame source a rig and scene loop consume.
///
/// The runtime owns the cadence. Each frame arrives on [frames] inside the
/// runtime's own callback, so listeners render synchronously and return.
/// Features ([hitTest], [anchors], [planes], [depthSensing],
/// [lightEstimation]) are null when the runtime did not grant them.
/// {@category Sessions}
abstract class XrSession {
  /// What kind of session this is.
  XrSessionMode get mode;

  /// How the rendered scene combines with the world.
  XrBlendMode get blendMode;

  /// The space the frames' poses are relative to.
  XrReferenceSpaceType get referenceSpaceType;

  /// The features the runtime granted (see [XrFeatures]).
  Set<String> get features;

  /// One event per display frame, delivered synchronously inside the
  /// runtime's frame callback.
  Stream<XrFrame> get frames;

  /// The tracked input sources as of the latest frame.
  List<XrInputSourceState> get inputSources;

  /// Fires when an input source connects or disconnects.
  Stream<void> get inputSourcesChanged;

  /// Hit testing against the real world, when granted.
  XrHitTesting? get hitTest;

  /// Anchors, when granted.
  XrAnchors? get anchors;

  /// Detected planes, when granted.
  XrPlaneDetection? get planes;

  /// Real-world depth, when granted.
  XrDepthSensing? get depthSensing;

  /// Real-world lighting, when granted.
  XrLightEstimation? get lightEstimation;

  /// Whether the session has ended.
  bool get isEnded;

  /// Completes when the session ends, with why.
  Future<XrSessionEndReason> get ended;

  /// The error behind a [XrSessionEndReason.runtimeError] or
  /// [XrSessionEndReason.contextLost] end, or null.
  Object? get error;

  /// Ends the session. Completes once the runtime has released it.
  Future<void> end();
}
