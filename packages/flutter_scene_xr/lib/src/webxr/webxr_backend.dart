/// The browser calls the WebXR session logic makes, as plain Dart interfaces.
///
/// `WebXrSession` never touches `dart:js_interop`; it talks to one of these,
/// which the web runtime implements over the real WebXR objects and tests
/// implement with fakes. Every method mirrors one WebXR call, so the session
/// logic stays checkable without a browser.
library;

import 'package:flutter_scene/gpu.dart' as gpu show ExternalTargetHandleKind;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import 'package:flutter_scene_xr/src/features/depth.dart';
import 'package:flutter_scene_xr/src/features/light_estimation.dart';
import 'package:flutter_scene_xr/src/features/planes.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';
import 'package:flutter_scene_xr/src/xr_view.dart';

/// The `XRSessionInit` dictionary a session is requested with.
class WebXrSessionInit {
  const WebXrSessionInit({
    this.requiredFeatures = const [],
    this.optionalFeatures = const [],
    this.domOverlayRoot,
    this.depthSensing = false,
  });

  /// Features the request fails without.
  final List<String> requiredFeatures;

  /// Features granted when available.
  final List<String> optionalFeatures;

  /// The DOM element for `domOverlay.root`, or null for none.
  final Object? domOverlayRoot;

  /// Whether to ask for CPU depth (`depthSensing` with `cpu-optimized`).
  final bool depthSensing;
}

/// `navigator.xr`.
abstract interface class WebXrBackend {
  /// Whether `navigator.xr` exists.
  bool get isSupported;

  /// `XRSystem.isSessionSupported`.
  Future<bool> isSessionSupported(XrSessionMode mode);

  /// `XRSystem.requestSession`. Throws when the browser rejects it.
  Future<WebXrBackendSession> requestSession(
    XrSessionMode mode,
    WebXrSessionInit init,
  );

  /// The element to hand `domOverlay.root` by default.
  Object? get defaultDomOverlayRoot;
}

/// A session's `requestAnimationFrame` callback.
typedef WebXrFrameCallback =
    void Function(double timeMilliseconds, WebXrBackendFrame frame);

/// Which primary action an input event reports.
enum WebXrSelectKind { select, squeeze }

/// Whether an input event starts or ends the action.
enum WebXrSelectPhase { start, end }

/// An `XRSession`.
abstract interface class WebXrBackendSession {
  /// `environmentBlendMode`.
  XrBlendMode get blendMode;

  /// `enabledFeatures`, or null in a browser that does not expose it.
  Set<String>? get enabledFeatures;

  /// Makes the graphics context XR compatible (`makeXRCompatible`) when it
  /// was not created so.
  Future<void> makeXrCompatible();

  /// `requestReferenceSpace`, or null when the browser rejects the type.
  Future<WebXrBackendSpace?> requestReferenceSpace(XrReferenceSpaceType type);

  /// Whether `XRWebGLBinding.createProjectionLayer` exists.
  bool get projectionLayersSupported;

  /// Creates an `XRWebGLLayer` and installs it as the base layer.
  WebXrBackendLayer createBaseLayer();

  /// Creates an `XRProjectionLayer` and installs it as the only layer.
  WebXrBackendLayer createProjectionLayer();

  /// `requestAnimationFrame`.
  int requestAnimationFrame(WebXrFrameCallback callback);

  /// `cancelAnimationFrame`.
  void cancelAnimationFrame(int handle);

  /// `end`.
  Future<void> end();

  /// `inputSources`.
  List<WebXrBackendInputSource> get inputSources;

  /// The `inputsourceschange` listener.
  set onInputSourcesChange(void Function()? listener);

  /// The `selectstart`, `selectend`, `squeezestart` and `squeezeend`
  /// listener.
  set onSelect(
    void Function(
      WebXrBackendInputSource source,
      WebXrSelectKind kind,
      WebXrSelectPhase phase,
    )?
    listener,
  );

  /// The `end` listener.
  set onEnd(void Function()? listener);

  /// The graphics context's `webglcontextlost` listener.
  set onContextLost(void Function()? listener);

  /// `requestHitTestSource`, or null when rejected.
  Future<WebXrBackendHitTestSource?> requestHitTestSource(
    WebXrBackendSpace space, {
    Ray? offsetRay,
  });

  /// `requestLightProbe`, or null when rejected.
  Future<WebXrBackendLightProbe?> requestLightProbe();
}

/// An `XRSpace`. Opaque; the frame reads poses relative to one.
abstract interface class WebXrBackendSpace {}

/// An `XRLightProbe`.
abstract interface class WebXrBackendLightProbe {}

/// An `XRHitTestSource`.
abstract interface class WebXrBackendHitTestSource {
  /// `cancel`.
  void cancel();
}

/// Where one view renders inside a layer, in GL pixel coordinates (origin
/// bottom-left).
class WebXrViewTarget {
  const WebXrViewTarget({
    required this.handle,
    required this.kind,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  /// The `WebGLFramebuffer` or `WebGLTexture`, or null when the layer draws
  /// to the canvas (an inline session).
  final Object? handle;

  /// What [handle] is.
  final gpu.ExternalTargetHandleKind kind;

  /// The handle's size in pixels.
  final int width;

  /// The handle's size in pixels.
  final int height;

  /// The viewport's left edge in pixels.
  final int x;

  /// The viewport's bottom edge in pixels, GL convention.
  final int y;

  /// The viewport's width in pixels.
  final int viewportWidth;

  /// The viewport's height in pixels.
  final int viewportHeight;
}

/// An `XRWebGLLayer` or `XRProjectionLayer`.
abstract interface class WebXrBackendLayer {
  /// Where [view] renders this frame.
  WebXrViewTarget viewTarget(WebXrBackendView view);

  /// Whether the layer draws to a surface the renderer cannot wrap (a canvas,
  /// as inline sessions and the emulated runtime hand out). The session then
  /// renders into a texture it owns and passes its image to [present].
  bool get presents;

  /// Copies [image], the platform image of the frame's color target (an
  /// `ImageBitmap` on the web), onto the layer's surface.
  void present(Object image);
}

/// An `XRView`.
abstract interface class WebXrBackendView {
  /// `eye`.
  XrEye get eye;

  /// Copies `transform` into [out].
  void readPose(XrPose out);

  /// Copies `projectionMatrix` into [out].
  void readProjection(Matrix4 out);
}

/// An `XRViewerPose`.
abstract interface class WebXrBackendViewerPose {
  /// Copies `transform` into [out].
  void readPose(XrPose out);

  /// `views`.
  List<WebXrBackendView> get views;
}

/// An `XRInputSource`. Equal to another wrapper of the same source.
abstract interface class WebXrBackendInputSource {
  /// `handedness`.
  XrHandedness get handedness;

  /// `targetRayMode`.
  XrTargetRayMode get targetRayMode;

  /// `profiles`.
  List<String> get profiles;

  /// `targetRaySpace`.
  WebXrBackendSpace get targetRaySpace;

  /// `gripSpace`.
  WebXrBackendSpace? get gripSpace;

  /// Copies `gamepad` into [out]; false when the source has none.
  bool readGamepad(XrGamepadState out);

  /// `hand`'s joint spaces in [XrHandJoint] order, or null without a hand.
  List<WebXrBackendSpace>? get handJointSpaces;
}

/// An `XRHitTestResult`.
abstract interface class WebXrBackendHitTestResult {
  /// Copies `getPose(baseSpace)` into [out]; false when untracked.
  bool readPose(WebXrBackendSpace baseSpace, XrPose out);

  /// `createAnchor`, or null when rejected.
  Future<WebXrBackendAnchor?> createAnchor();
}

/// An `XRAnchor`. Equal to another wrapper of the same anchor.
abstract interface class WebXrBackendAnchor {
  /// `anchorSpace`.
  WebXrBackendSpace get space;

  /// `delete`.
  void delete();
}

/// An `XRPlane`. Equal to another wrapper of the same plane.
abstract interface class WebXrBackendPlane {
  /// `planeSpace`.
  WebXrBackendSpace get space;

  /// `orientation`.
  XrPlaneOrientation get orientation;

  /// `polygon`.
  List<Vector3> get polygon;

  /// `lastChangedTime`.
  double get lastChangedTime;
}

/// An `XRFrame`. Valid only inside the animation frame callback.
abstract interface class WebXrBackendFrame {
  /// `getViewerPose`, or null while tracking is lost.
  WebXrBackendViewerPose? viewerPose(WebXrBackendSpace referenceSpace);

  /// Copies `getPose(space, baseSpace)` into [out]; false when untracked.
  bool readPose(
    WebXrBackendSpace space,
    WebXrBackendSpace baseSpace,
    XrPose out,
  );

  /// Copies `getJointPose` into [out] and returns the joint radius, or null
  /// when untracked.
  double? readJointPose(
    WebXrBackendSpace jointSpace,
    WebXrBackendSpace baseSpace,
    XrPose out,
  );

  /// `getHitTestResults`.
  List<WebXrBackendHitTestResult> hitTestResults(
    WebXrBackendHitTestSource source,
  );

  /// `trackedAnchors`.
  List<WebXrBackendAnchor> get trackedAnchors;

  /// `createAnchor`, or null when rejected.
  Future<WebXrBackendAnchor?> createAnchor(
    XrPose pose,
    WebXrBackendSpace space,
  );

  /// `detectedPlanes`.
  List<WebXrBackendPlane> get detectedPlanes;

  /// `getDepthInformation(view)` copied out, or null.
  XrDepthInformation? depthInformation(WebXrBackendView view);

  /// Copies `getLightEstimate(probe)` into [out]; false when there is none.
  bool readLightEstimate(WebXrBackendLightProbe probe, XrLightEstimate out);
}
