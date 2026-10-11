import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;
import 'package:web/web.dart' as web;

import 'package:flutter_scene_xr/src/features/depth.dart';
import 'package:flutter_scene_xr/src/features/light_estimation.dart';
import 'package:flutter_scene_xr/src/features/planes.dart';
import 'package:flutter_scene_xr/src/web/webxr_bindings.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_backend.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';
import 'package:flutter_scene_xr/src/xr_view.dart';

/// The [WebXrBackend] over the browser's `navigator.xr`.
final class JsWebXrBackend implements WebXrBackend {
  /// The browser backend.
  const JsWebXrBackend();

  XRSystem? get _xr => web.window.navigator.xr;

  @override
  bool get isSupported => _xr != null;

  @override
  Future<bool> isSessionSupported(XrSessionMode mode) async {
    final xr = _xr;
    if (xr == null) return false;
    try {
      return (await xr.isSessionSupported(mode.webName).toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WebXrBackendSession> requestSession(
    XrSessionMode mode,
    WebXrSessionInit init,
  ) async {
    final xr = _xr;
    if (xr == null) {
      throw UnsupportedError('This browser has no WebXR Device API.');
    }
    final options = XRSessionInit();
    if (init.requiredFeatures.isNotEmpty) {
      options['requiredFeatures'] = _strings(init.requiredFeatures);
    }
    if (init.optionalFeatures.isNotEmpty) {
      options['optionalFeatures'] = _strings(init.optionalFeatures);
    }
    final root = init.domOverlayRoot;
    // The contract types the root as Object; this is where it becomes a DOM
    // element again.
    // ignore: invalid_runtime_check_with_js_interop_types
    if (root != null && (root as JSAny).isA<web.Element>()) {
      options['domOverlay'] = XRDOMOverlayInit(root: root as web.Element);
    }
    if (init.depthSensing) {
      options['depthSensing'] = XRDepthStateInit(
        usagePreference: _strings(const ['cpu-optimized']),
        dataFormatPreference: _strings(const ['luminance-alpha', 'float32']),
      );
    }
    final session = await xr.requestSession(mode.webName, options).toDart;
    return JsWebXrSession(session);
  }

  @override
  Object? get defaultDomOverlayRoot => web.document.body;
}

JSArray<JSString> _strings(List<String> values) =>
    [for (final value in values) value.toJS].toJS;

web.DOMPointInit _point(Vector3 v, double w) =>
    web.DOMPointInit(x: v.x, y: v.y, z: v.z, w: w);

void _copyTransform(web.XRRigidTransform transform, XrPose out) {
  final p = transform.position;
  final o = transform.orientation;
  out.setValues(p.x, p.y, p.z, o.x, o.y, o.z, o.w);
}

XrHandedness _handedness(String value) => switch (value) {
  'left' => XrHandedness.left,
  'right' => XrHandedness.right,
  _ => XrHandedness.none,
};

XrTargetRayMode _targetRayMode(String value) => switch (value) {
  'gaze' => XrTargetRayMode.gaze,
  'screen' => XrTargetRayMode.screen,
  'transient-pointer' => XrTargetRayMode.transientPointer,
  _ => XrTargetRayMode.trackedPointer,
};

/// A [WebXrBackendSession] over an `XRSession`.
final class JsWebXrSession implements WebXrBackendSession {
  /// Wraps [session], drawing with the shim's WebGL2 context.
  JsWebXrSession(this._session)
    : _gl = switch (gpu.nativeGraphicsContext) {
        final web.WebGL2RenderingContext gl => gl,
        _ => throw StateError(
          'The active GPU backend has no WebGL2 context to share with WebXR.',
        ),
      } {
    _session.addEventListener('end', _endListener);
    _session.addEventListener('inputsourceschange', _changeListener);
    _session.addEventListener('selectstart', _selectStartListener);
    _session.addEventListener('selectend', _selectEndListener);
    _session.addEventListener('squeezestart', _squeezeStartListener);
    _session.addEventListener('squeezeend', _squeezeEndListener);
    final canvas = _gl.canvas;
    if (canvas.isA<web.EventTarget>()) {
      final target = canvas as web.EventTarget;
      target.addEventListener('webglcontextlost', _contextLostListener);
      target.addEventListener('contextlost', _contextLostListener);
    }
  }

  final XRSession _session;
  final web.WebGL2RenderingContext _gl;

  void Function()? _onEnd;
  void Function()? _onContextLost;
  void Function()? _onInputSourcesChange;
  void Function(WebXrBackendInputSource, WebXrSelectKind, WebXrSelectPhase)?
  _onSelect;

  late final JSFunction _endListener = ((web.Event _) {
    _onEnd?.call();
  }).toJS;
  late final JSFunction _changeListener = ((web.Event _) {
    _onInputSourcesChange?.call();
  }).toJS;
  late final JSFunction _contextLostListener = ((web.Event _) {
    _onContextLost?.call();
  }).toJS;
  late final JSFunction _selectStartListener = _selectListener(
    WebXrSelectKind.select,
    WebXrSelectPhase.start,
  );
  late final JSFunction _selectEndListener = _selectListener(
    WebXrSelectKind.select,
    WebXrSelectPhase.end,
  );
  late final JSFunction _squeezeStartListener = _selectListener(
    WebXrSelectKind.squeeze,
    WebXrSelectPhase.start,
  );
  late final JSFunction _squeezeEndListener = _selectListener(
    WebXrSelectKind.squeeze,
    WebXrSelectPhase.end,
  );

  WebXrFrameCallback? _frameCallback;
  JSFunction? _frameListener;

  JSFunction _selectListener(WebXrSelectKind kind, WebXrSelectPhase phase) =>
      ((web.XRInputSourceEvent event) {
        _onSelect?.call(_JsInputSource(event.inputSource), kind, phase);
      }).toJS;

  @override
  XrBlendMode get blendMode => switch (_session.environmentBlendMode) {
    'additive' => XrBlendMode.additive,
    'alpha-blend' => XrBlendMode.alphaBlend,
    _ => XrBlendMode.opaque,
  };

  @override
  Set<String>? get enabledFeatures {
    final features = _session.enabledFeatures;
    if (features == null) return null;
    return {for (final feature in features.toDart) feature.toDart};
  }

  @override
  Future<void> makeXrCompatible() async {
    final attributes = _gl.getContextAttributes();
    final compatible =
        attributes?.getProperty<JSBoolean?>('xrCompatible'.toJS)?.toDart ??
        false;
    if (compatible) return;
    await _gl.makeXRCompatible().toDart;
  }

  @override
  Future<WebXrBackendSpace?> requestReferenceSpace(
    XrReferenceSpaceType type,
  ) async {
    try {
      return _JsSpace(
        await _session.requestReferenceSpace(type.webName).toDart,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool get projectionLayersSupported => globalContext.has('XRWebGLBinding');

  @override
  WebXrBackendLayer createBaseLayer() {
    // The scene resolves finished color into the layer and keeps depth in its
    // own transient, so the layer needs no depth attachment.
    // TODO(xr-depth): write the layer's depth (ignoreDepthValues false, a
    // depth copy pass) so the compositor can reproject.
    final layer = XRWebGLLayer(
      _session,
      _gl,
      XRWebGLLayerInit(
        antialias: false,
        depth: false,
        stencil: false,
        alpha: true,
        ignoreDepthValues: true,
      ),
    );
    final state = XRRenderStateInit();
    state['baseLayer'] = layer;
    _session.updateRenderState(state);
    return _JsBaseLayer(layer);
  }

  @override
  WebXrBackendLayer createProjectionLayer() {
    final binding = XRWebGLBinding(_session, _gl);
    final layer = binding.createProjectionLayer(
      XRProjectionLayerInit(textureType: 'texture'),
    );
    final state = XRRenderStateInit();
    state['layers'] = [layer].toJS;
    _session.updateRenderState(state);
    return _JsProjectionLayer(binding, layer);
  }

  @override
  int requestAnimationFrame(WebXrFrameCallback callback) {
    if (!identical(callback, _frameCallback) || _frameListener == null) {
      _frameCallback = callback;
      _frameListener = ((JSNumber time, XRFrame frame) {
        callback(time.toDartDouble, _JsFrame(frame));
      }).toJS;
    }
    return _session.requestAnimationFrame(_frameListener!);
  }

  @override
  void cancelAnimationFrame(int handle) =>
      _session.cancelAnimationFrame(handle);

  @override
  Future<void> end() async {
    try {
      await _session.end().toDart;
    } catch (_) {
      // Already ended.
    }
  }

  @override
  List<WebXrBackendInputSource> get inputSources {
    final array = _session.inputSources;
    return [for (var i = 0; i < array.length; i++) _JsInputSource(array[i])];
  }

  @override
  set onInputSourcesChange(void Function()? listener) =>
      _onInputSourcesChange = listener;

  @override
  set onSelect(
    void Function(WebXrBackendInputSource, WebXrSelectKind, WebXrSelectPhase)?
    listener,
  ) => _onSelect = listener;

  @override
  set onEnd(void Function()? listener) => _onEnd = listener;

  @override
  set onContextLost(void Function()? listener) => _onContextLost = listener;

  @override
  Future<WebXrBackendHitTestSource?> requestHitTestSource(
    WebXrBackendSpace space, {
    Ray? offsetRay,
  }) async {
    final options = XRHitTestOptionsInit();
    options['space'] = (space as _JsSpace).space;
    if (offsetRay != null) {
      options['offsetRay'] = XRRay(
        _point(offsetRay.origin, 1.0),
        _point(offsetRay.direction, 0.0),
      );
    }
    try {
      return _JsHitTestSource(
        await _session.requestHitTestSource(options).toDart,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<WebXrBackendLightProbe?> requestLightProbe() async {
    try {
      return _JsLightProbe(await _session.requestLightProbe().toDart);
    } catch (_) {
      return null;
    }
  }
}

final class _JsSpace implements WebXrBackendSpace {
  _JsSpace(this.space);

  final web.XRSpace space;

  @override
  bool operator ==(Object other) => other is _JsSpace && other.space == space;

  @override
  int get hashCode => space.hashCode;
}

final class _JsLightProbe implements WebXrBackendLightProbe {
  _JsLightProbe(this.probe);

  final XRLightProbe probe;
}

final class _JsHitTestSource implements WebXrBackendHitTestSource {
  _JsHitTestSource(this.source);

  final XRHitTestSource source;

  @override
  void cancel() => source.cancel();
}

final class _JsBaseLayer implements WebXrBackendLayer {
  _JsBaseLayer(this.layer);

  final XRWebGLLayer layer;

  @override
  WebXrViewTarget viewTarget(WebXrBackendView view) {
    final width = layer.framebufferWidth;
    final height = layer.framebufferHeight;
    final viewport = layer.getViewport((view as _JsView).view);
    return WebXrViewTarget(
      handle: layer.framebuffer,
      kind: gpu.ExternalTargetHandleKind.framebuffer,
      width: width,
      height: height,
      x: viewport?.x ?? 0,
      y: viewport?.y ?? 0,
      viewportWidth: viewport?.width ?? width,
      viewportHeight: viewport?.height ?? height,
    );
  }
}

// TODO(xr-layers): untested on a headset; a texture-array layer (one texture,
// a slice per eye) would need the image index carried through the handle.
final class _JsProjectionLayer implements WebXrBackendLayer {
  _JsProjectionLayer(this.binding, this.layer);

  final XRWebGLBinding binding;
  final XRProjectionLayer layer;

  @override
  WebXrViewTarget viewTarget(WebXrBackendView view) {
    final sub = binding.getViewSubImage(layer, (view as _JsView).view);
    final viewport = sub.viewport;
    return WebXrViewTarget(
      handle: sub.colorTexture,
      kind: gpu.ExternalTargetHandleKind.texture,
      width: sub.colorTextureWidth,
      height: sub.colorTextureHeight,
      x: viewport.x,
      y: viewport.y,
      viewportWidth: viewport.width,
      viewportHeight: viewport.height,
    );
  }
}

final class _JsView implements WebXrBackendView {
  _JsView(this.view);

  final XRView view;

  @override
  XrEye get eye => switch (view.eye) {
    'left' => XrEye.left,
    'right' => XrEye.right,
    _ => XrEye.none,
  };

  @override
  void readPose(XrPose out) => _copyTransform(view.transform, out);

  @override
  void readProjection(Matrix4 out) =>
      out.storage.setAll(0, view.projectionMatrix.toDart);
}

final class _JsViewerPose implements WebXrBackendViewerPose {
  _JsViewerPose(this.pose);

  final web.XRViewerPose pose;

  @override
  void readPose(XrPose out) {
    _copyTransform(pose.transform, out);
    out.emulatedPosition = pose.emulatedPosition;
  }

  @override
  List<WebXrBackendView> get views => [
    for (final view in pose.views.toDart) _JsView(view as XRView),
  ];
}

final class _JsInputSource implements WebXrBackendInputSource {
  _JsInputSource(this.source);

  final web.XRInputSource source;
  List<WebXrBackendSpace>? _joints;

  @override
  XrHandedness get handedness => _handedness(source.handedness);

  @override
  XrTargetRayMode get targetRayMode => _targetRayMode(source.targetRayMode);

  @override
  List<String> get profiles => [
    for (final profile in source.profiles.toDart) profile.toDart,
  ];

  @override
  WebXrBackendSpace get targetRaySpace => _JsSpace(source.targetRaySpace);

  @override
  WebXrBackendSpace? get gripSpace {
    final grip = source.gripSpace;
    return grip == null ? null : _JsSpace(grip);
  }

  @override
  bool readGamepad(XrGamepadState out) {
    final pad = source.gamepad;
    if (pad == null) return false;
    final buttons = pad.buttons.toDart;
    final axes = pad.axes.toDart;
    out.resize(buttonCount: buttons.length, axisCount: axes.length);
    out.mapping = pad.mapping;
    for (var i = 0; i < buttons.length; i++) {
      final button = buttons[i];
      out.buttonValues[i] = button.value;
      out.buttonPressed[i] = button.pressed;
      out.buttonTouched[i] = button.touched;
    }
    for (var i = 0; i < axes.length; i++) {
      out.axes[i] = axes[i].toDartDouble;
    }
    return true;
  }

  @override
  List<WebXrBackendSpace>? get handJointSpaces {
    final hand = source.hand;
    if (hand == null) return null;
    final cached = _joints;
    if (cached != null) return cached;
    final joints = <WebXrBackendSpace>[];
    for (final joint in XrHandJoint.values) {
      final space = hand.get(joint.webName);
      if (space == null) return null;
      joints.add(_JsSpace(space));
    }
    return _joints = joints;
  }

  @override
  bool operator ==(Object other) =>
      other is _JsInputSource && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

final class _JsHitTestResult implements WebXrBackendHitTestResult {
  _JsHitTestResult(this.result);

  final XRHitTestResult result;

  @override
  bool readPose(WebXrBackendSpace baseSpace, XrPose out) {
    final pose = result.getPose((baseSpace as _JsSpace).space);
    if (pose == null) return false;
    _copyTransform(pose.transform, out);
    return true;
  }

  @override
  Future<WebXrBackendAnchor?> createAnchor() async {
    try {
      return _JsAnchor(await result.createAnchor().toDart);
    } catch (_) {
      return null;
    }
  }
}

final class _JsAnchor implements WebXrBackendAnchor {
  _JsAnchor(this.anchor);

  final XRAnchor anchor;

  @override
  WebXrBackendSpace get space => _JsSpace(anchor.anchorSpace);

  @override
  void delete() => anchor.delete();

  @override
  bool operator ==(Object other) =>
      other is _JsAnchor && other.anchor == anchor;

  @override
  int get hashCode => anchor.hashCode;
}

final class _JsPlane implements WebXrBackendPlane {
  _JsPlane(this.plane);

  final XRPlane plane;

  @override
  WebXrBackendSpace get space => _JsSpace(plane.planeSpace);

  @override
  XrPlaneOrientation get orientation => switch (plane.orientation) {
    'horizontal' => XrPlaneOrientation.horizontal,
    'vertical' => XrPlaneOrientation.vertical,
    _ => XrPlaneOrientation.unknown,
  };

  @override
  List<Vector3> get polygon => [
    for (final point in plane.polygon.toDart)
      Vector3(point.x, point.y, point.z),
  ];

  @override
  double get lastChangedTime => plane.lastChangedTime;

  @override
  bool operator ==(Object other) => other is _JsPlane && other.plane == plane;

  @override
  int get hashCode => plane.hashCode;
}

final class _JsFrame implements WebXrBackendFrame {
  _JsFrame(this.frame);

  final XRFrame frame;

  @override
  WebXrBackendViewerPose? viewerPose(WebXrBackendSpace referenceSpace) {
    final pose = frame.getViewerPose(
      (referenceSpace as _JsSpace).space as web.XRReferenceSpace,
    );
    return pose == null ? null : _JsViewerPose(pose);
  }

  @override
  bool readPose(
    WebXrBackendSpace space,
    WebXrBackendSpace baseSpace,
    XrPose out,
  ) {
    final pose = frame.getPose(
      (space as _JsSpace).space,
      (baseSpace as _JsSpace).space,
    );
    if (pose == null) return false;
    _copyTransform(pose.transform, out);
    out.emulatedPosition = pose.emulatedPosition;
    return true;
  }

  @override
  double? readJointPose(
    WebXrBackendSpace jointSpace,
    WebXrBackendSpace baseSpace,
    XrPose out,
  ) {
    // TODO(xr-hands-fill): read all 25 joints at once through fillPoses and
    // fillJointRadii instead of one getJointPose call per joint.
    final pose = frame.getJointPose(
      (jointSpace as _JsSpace).space as web.XRJointSpace,
      (baseSpace as _JsSpace).space,
    );
    if (pose == null) return null;
    _copyTransform(pose.transform, out);
    return pose.radius;
  }

  @override
  List<WebXrBackendHitTestResult> hitTestResults(
    WebXrBackendHitTestSource source,
  ) => [
    for (final result
        in frame.getHitTestResults((source as _JsHitTestSource).source).toDart)
      _JsHitTestResult(result),
  ];

  @override
  List<WebXrBackendAnchor> get trackedAnchors {
    final anchors = <WebXrBackendAnchor>[];
    frame.trackedAnchors.forEach(
      ((XRAnchor anchor) {
        anchors.add(_JsAnchor(anchor));
      }).toJS,
    );
    return anchors;
  }

  @override
  Future<WebXrBackendAnchor?> createAnchor(
    XrPose pose,
    WebXrBackendSpace space,
  ) async {
    final transform = web.XRRigidTransform(
      _point(pose.position, 1.0),
      web.DOMPointInit(
        x: pose.orientation.x,
        y: pose.orientation.y,
        z: pose.orientation.z,
        w: pose.orientation.w,
      ),
    );
    try {
      return _JsAnchor(
        await frame.createAnchor(transform, (space as _JsSpace).space).toDart,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  List<WebXrBackendPlane> get detectedPlanes {
    final planes = <WebXrBackendPlane>[];
    frame.detectedPlanes.forEach(
      ((XRPlane plane) {
        planes.add(_JsPlane(plane));
      }).toJS,
    );
    return planes;
  }

  @override
  XrDepthInformation? depthInformation(WebXrBackendView view) {
    final info = frame.getDepthInformation((view as _JsView).view);
    if (info == null) return null;
    final buffer = info.data.toDart;
    final scale = info.rawValueToMeters;
    final count = info.width * info.height;
    final meters = Float32List(count);
    if (frame.session.depthDataFormat == 'float32') {
      final raw = Float32List.view(buffer, 0, count);
      for (var i = 0; i < count; i++) {
        meters[i] = raw[i] * scale;
      }
    } else {
      final raw = Uint16List.view(buffer, 0, count);
      for (var i = 0; i < count; i++) {
        meters[i] = raw[i] * scale;
      }
    }
    final transform = Matrix4.zero()
      ..storage.setAll(0, info.normDepthBufferFromNormView.matrix.toDart);
    return XrDepthInformation(
      width: info.width,
      height: info.height,
      depthMeters: meters,
      rawValueToMeters: scale,
      normDepthBufferFromNormView: transform,
    );
  }

  @override
  bool readLightEstimate(WebXrBackendLightProbe probe, XrLightEstimate out) {
    final estimate = frame.getLightEstimate((probe as _JsLightProbe).probe);
    if (estimate == null) return false;
    final coefficients = estimate.sphericalHarmonicsCoefficients.toDart;
    final n = coefficients.length < out.sphericalHarmonics.length
        ? coefficients.length
        : out.sphericalHarmonics.length;
    for (var i = 0; i < n; i++) {
      out.sphericalHarmonics[i] = coefficients[i];
    }
    final direction = estimate.primaryLightDirection;
    out.primaryLightDirection.setValues(direction.x, direction.y, direction.z);
    final intensity = estimate.primaryLightIntensity;
    out.primaryLightIntensity.setValues(intensity.x, intensity.y, intensity.z);
    return true;
  }
}
