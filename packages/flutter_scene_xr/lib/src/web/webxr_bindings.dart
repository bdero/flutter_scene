/// `dart:js_interop` bindings for the WebXR interfaces `package:web` lacks.
///
/// Only the members the runtime uses are declared. Shapes follow the WebXR
/// Device API, Layers, Hit Test, Anchors, Depth Sensing, Lighting Estimation,
/// Plane Detection and DOM Overlay drafts. `package:web` already has
/// `XRSpace`, `XRReferenceSpace`, `XRViewport`, `XRRigidTransform`, `XRPose`,
/// `XRViewerPose`, `XRInputSource`, the input events, `XRHand`,
/// `XRJointSpace` and `XRJointPose`, which are used as is.
@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `navigator.xr`.
extension NavigatorXr on web.Navigator {
  external XRSystem? get xr;
}

/// `XRSystem`.
extension type XRSystem._(JSObject _) implements web.EventTarget, JSObject {
  external JSPromise<JSBoolean> isSessionSupported(String mode);
  external JSPromise<XRSession> requestSession(
    String mode, [
    XRSessionInit options,
  ]);
}

/// `XRSessionInit`. Built member by member so absent options stay absent.
extension type XRSessionInit._(JSObject _) implements JSObject {
  XRSessionInit() : _ = JSObject();
}

/// `XRDOMOverlayInit` (DOM Overlay module).
extension type XRDOMOverlayInit._(JSObject _) implements JSObject {
  external factory XRDOMOverlayInit({required web.Element root});
}

/// `XRDepthStateInit` (Depth Sensing module).
extension type XRDepthStateInit._(JSObject _) implements JSObject {
  external factory XRDepthStateInit({
    required JSArray<JSString> usagePreference,
    required JSArray<JSString> dataFormatPreference,
  });
}

/// `XRSession`.
extension type XRSession._(JSObject _) implements web.EventTarget, JSObject {
  external String get environmentBlendMode;
  external XRRenderState get renderState;
  external XRInputSourceArray get inputSources;
  external JSArray<JSString>? get enabledFeatures;
  external String? get depthUsage;
  external String? get depthDataFormat;
  external XRDOMOverlayState? get domOverlayState;
  external void updateRenderState([XRRenderStateInit state]);
  external JSPromise<web.XRReferenceSpace> requestReferenceSpace(String type);
  external int requestAnimationFrame(JSFunction callback);
  external void cancelAnimationFrame(int handle);
  external JSPromise<JSAny?> end();
  external JSPromise<XRHitTestSource> requestHitTestSource(
    XRHitTestOptionsInit options,
  );
  external JSPromise<XRLightProbe> requestLightProbe([
    XRLightProbeInit options,
  ]);
}

/// `XRInputSourceArray`, an array-like that is not a JS `Array`.
extension type XRInputSourceArray._(JSObject _) implements JSObject {
  external int get length;

  /// The source at [index] (the indexed getter).
  web.XRInputSource operator [](int index) =>
      _.getProperty<web.XRInputSource>(index.toJS);
}

/// `XRRenderStateInit`. Built member by member, since `baseLayer` and
/// `layers` exclude each other.
extension type XRRenderStateInit._(JSObject _) implements JSObject {
  XRRenderStateInit() : _ = JSObject();
}

/// `XRRenderState`.
extension type XRRenderState._(JSObject _) implements JSObject {
  external double get depthNear;
  external double get depthFar;
  external XRWebGLLayer? get baseLayer;
}

/// `XRFrame`.
extension type XRFrame._(JSObject _) implements JSObject {
  external XRSession get session;
  external double get predictedDisplayTime;
  external web.XRViewerPose? getViewerPose(web.XRReferenceSpace space);
  external web.XRPose? getPose(web.XRSpace space, web.XRSpace baseSpace);
  external web.XRJointPose? getJointPose(
    web.XRJointSpace joint,
    web.XRSpace baseSpace,
  );
  external JSArray<XRHitTestResult> getHitTestResults(XRHitTestSource source);
  external XRAnchorSet get trackedAnchors;
  external JSPromise<XRAnchor> createAnchor(
    web.XRRigidTransform pose,
    web.XRSpace space,
  );
  external XRPlaneSet get detectedPlanes;
  external XRCPUDepthInformation? getDepthInformation(XRView view);
  external XRLightEstimate? getLightEstimate(XRLightProbe probe);
}

/// `XRView`.
extension type XRView._(JSObject _) implements JSObject {
  external String get eye;
  external JSFloat32Array get projectionMatrix;
  external web.XRRigidTransform get transform;
  external double? get recommendedViewportScale;
  external void requestViewportScale(num? scale);
}

/// `XRLayer` (Layers module), the base of every layer type.
extension type XRLayer._(JSObject _) implements web.EventTarget, JSObject {}

/// `XRWebGLLayerInit`.
extension type XRWebGLLayerInit._(JSObject _) implements JSObject {
  external factory XRWebGLLayerInit({
    bool antialias,
    bool depth,
    bool stencil,
    bool alpha,
    bool ignoreDepthValues,
    num framebufferScaleFactor,
  });
}

/// `XRWebGLLayer`.
extension type XRWebGLLayer._(JSObject _) implements XRLayer, JSObject {
  external factory XRWebGLLayer(
    XRSession session,
    web.WebGL2RenderingContext context, [
    XRWebGLLayerInit layerInit,
  ]);
  external bool get antialias;
  external bool get ignoreDepthValues;
  external web.WebGLFramebuffer? get framebuffer;
  external int get framebufferWidth;
  external int get framebufferHeight;
  external web.XRViewport? getViewport(XRView view);
}

/// `XRWebGLBinding` (Layers module).
extension type XRWebGLBinding._(JSObject _) implements JSObject {
  external factory XRWebGLBinding(
    XRSession session,
    web.WebGL2RenderingContext context,
  );
  external double get nativeProjectionScaleFactor;
  external XRProjectionLayer createProjectionLayer([
    XRProjectionLayerInit init,
  ]);
  external XRWebGLSubImage getViewSubImage(
    XRProjectionLayer layer,
    XRView view,
  );
}

/// `XRProjectionLayerInit`.
extension type XRProjectionLayerInit._(JSObject _) implements JSObject {
  external factory XRProjectionLayerInit({
    String textureType,
    int colorFormat,
    int depthFormat,
    num scaleFactor,
  });
}

/// `XRProjectionLayer`.
extension type XRProjectionLayer._(JSObject _) implements XRLayer, JSObject {
  external int get textureWidth;
  external int get textureHeight;
  external int get textureArrayLength;
  external bool get ignoreDepthValues;
}

/// `XRWebGLSubImage`.
extension type XRWebGLSubImage._(JSObject _) implements JSObject {
  external web.XRViewport get viewport;
  external web.WebGLTexture get colorTexture;
  external web.WebGLTexture? get depthStencilTexture;
  external int? get imageIndex;
  external int get colorTextureWidth;
  external int get colorTextureHeight;
}

/// `XRHitTestOptionsInit` (Hit Test module). Built member by member.
extension type XRHitTestOptionsInit._(JSObject _) implements JSObject {
  XRHitTestOptionsInit() : _ = JSObject();
}

/// `XRRay`.
extension type XRRay._(JSObject _) implements JSObject {
  external factory XRRay([web.DOMPointInit origin, web.DOMPointInit direction]);
}

/// `XRHitTestSource`.
extension type XRHitTestSource._(JSObject _) implements JSObject {
  external void cancel();
}

/// `XRHitTestResult`.
extension type XRHitTestResult._(JSObject _) implements JSObject {
  external web.XRPose? getPose(web.XRSpace baseSpace);
  external JSPromise<XRAnchor> createAnchor();
}

/// `XRAnchor` (Anchors module).
extension type XRAnchor._(JSObject _) implements JSObject {
  external web.XRSpace get anchorSpace;
  external void delete();
}

/// `XRAnchorSet`, a JS `Set`.
extension type XRAnchorSet._(JSObject _) implements JSObject {
  external int get size;
  external void forEach(JSFunction callback);
}

/// `XRPlane` (Plane Detection module).
extension type XRPlane._(JSObject _) implements JSObject {
  external web.XRSpace get planeSpace;
  external JSArray<web.DOMPointReadOnly> get polygon;
  external String get orientation;
  external double get lastChangedTime;
}

/// `XRPlaneSet`, a JS `Set`.
extension type XRPlaneSet._(JSObject _) implements JSObject {
  external int get size;
  external void forEach(JSFunction callback);
}

/// `XRCPUDepthInformation` (Depth Sensing module).
extension type XRCPUDepthInformation._(JSObject _) implements JSObject {
  external int get width;
  external int get height;
  external web.XRRigidTransform get normDepthBufferFromNormView;
  external double get rawValueToMeters;
  external JSArrayBuffer get data;
  external double getDepthInMeters(num x, num y);
}

/// `XRLightProbeInit` (Lighting Estimation module).
extension type XRLightProbeInit._(JSObject _) implements JSObject {
  external factory XRLightProbeInit({String reflectionFormat});
}

/// `XRLightProbe`.
extension type XRLightProbe._(JSObject _) implements web.EventTarget, JSObject {
  external web.XRSpace get probeSpace;
}

/// `XRLightEstimate`.
extension type XRLightEstimate._(JSObject _) implements JSObject {
  external JSFloat32Array get sphericalHarmonicsCoefficients;
  external web.DOMPointReadOnly get primaryLightDirection;
  external web.DOMPointReadOnly get primaryLightIntensity;
}

/// `XRDOMOverlayState` (DOM Overlay module).
extension type XRDOMOverlayState._(JSObject _) implements JSObject {
  external String get type;
}

/// The `XRHand` map-like members `package:web` leaves out.
extension XRHandJoints on web.XRHand {
  external int get size;

  /// The joint space named [jointName], or null for an unknown name.
  external web.XRJointSpace? get(String jointName);
}
