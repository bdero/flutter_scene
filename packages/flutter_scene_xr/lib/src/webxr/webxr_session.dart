import 'dart:async';

import 'package:flutter_scene/gpu.dart' as gpu show ExternalTargetHandleKind;
import 'package:flutter_scene/scene.dart' show ExternalRenderTarget;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import 'package:flutter_scene_xr/src/features/anchors.dart';
import 'package:flutter_scene_xr/src/features/depth.dart';
import 'package:flutter_scene_xr/src/features/hit_test.dart';
import 'package:flutter_scene_xr/src/features/light_estimation.dart';
import 'package:flutter_scene_xr/src/features/planes.dart';
import 'package:flutter_scene_xr/src/viewport_math.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_backend.dart';
import 'package:flutter_scene_xr/src/xr_frame.dart';
import 'package:flutter_scene_xr/src/xr_input_state.dart';
import 'package:flutter_scene_xr/src/xr_pose.dart';
import 'package:flutter_scene_xr/src/xr_runtime.dart';
import 'package:flutter_scene_xr/src/xr_session.dart';
import 'package:flutter_scene_xr/src/xr_view.dart';

/// The WebXR runtime, over whatever [WebXrBackend] reaches the browser.
final class WebXrRuntime implements XrRuntime {
  /// A runtime over [backend].
  WebXrRuntime(this.backend);

  /// The browser.
  final WebXrBackend backend;

  @override
  bool get isSupported => backend.isSupported;

  @override
  Future<bool> isSessionSupported(XrSessionMode mode) =>
      isSupported ? backend.isSessionSupported(mode) : Future.value(false);

  @override
  Object? get defaultDomOverlayRoot => backend.defaultDomOverlayRoot;

  @override
  Future<XrSession> requestSession(XrSessionRequest request) async {
    if (!isSupported) {
      throw UnsupportedError('This browser has no WebXR Device API.');
    }
    final required = <String>[...request.requiredFeatures];
    final optional = <String>[...request.optionalFeatures];
    // Reference spaces other than viewer and local are features to ask for.
    for (final type in request.referenceSpaces) {
      final name = type.webName;
      if (type == XrReferenceSpaceType.viewer ||
          type == XrReferenceSpaceType.local ||
          required.contains(name) ||
          optional.contains(name)) {
        continue;
      }
      optional.add(name);
    }
    if (request.domOverlayRoot != null &&
        !required.contains(XrFeatures.domOverlay) &&
        !optional.contains(XrFeatures.domOverlay)) {
      optional.add(XrFeatures.domOverlay);
    }
    final WebXrBackendSession backendSession;
    try {
      backendSession = await backend.requestSession(
        request.mode,
        WebXrSessionInit(
          requiredFeatures: required,
          optionalFeatures: optional,
          domOverlayRoot: request.domOverlayRoot,
          depthSensing:
              required.contains(XrFeatures.depthSensing) ||
              optional.contains(XrFeatures.depthSensing),
        ),
      );
    } catch (error) {
      throw StateError('The browser refused the XR session: $error');
    }
    final session = WebXrSession._(request, backendSession, {
      ...required,
      ...optional,
    });
    await session._initialize();
    return session;
  }
}

/// An [XrSession] over a browser's `XRSession`.
///
/// Drives the session's `requestAnimationFrame` loop, turns each `XRFrame`
/// into an [XrFrame] (views, viewport regions, the layer's framebuffer as the
/// render target, input sources, hands) and refreshes the granted features.
final class WebXrSession implements XrSession {
  WebXrSession._(this._request, this._backend, this._requestedFeatures);

  final XrSessionRequest _request;
  final WebXrBackendSession _backend;
  final Set<String> _requestedFeatures;

  final StreamController<XrFrame> _frames = StreamController.broadcast(
    sync: true,
  );
  final StreamController<void> _inputSourcesChanged =
      StreamController.broadcast(sync: true);
  final Completer<XrSessionEndReason> _ended = Completer();

  late final WebXrBackendLayer _layer;
  late final WebXrBackendSpace _referenceSpace;
  late final XrReferenceSpaceType _referenceSpaceType;
  late final Set<String> _features;
  WebXrBackendSpace? _viewerSpace;

  final XrPose _viewerPose = XrPose();
  final List<XrView> _views = [];
  final Matrix4 _projectionScratch = Matrix4.zero();
  final List<XrView> _frameViews = [];
  late final XrFrame _frame = XrFrame(
    predictedDisplayTime: Duration.zero,
    views: _frameViews,
    referenceSpaceType: XrReferenceSpaceType.local,
  );

  // The layer's framebuffer, wrapped once and replaced when it changes.
  ExternalRenderTarget? _sharedTarget;
  Object? _sharedHandle;
  final List<ExternalRenderTarget?> _viewTargets = [];
  final List<Object?> _viewHandles = [];

  final List<_SourceEntry> _sources = [];
  final List<XrInputSourceState> _sourceStates = [];
  bool _sourcesDirty = true;
  int _nextSourceId = 1;

  _WebXrHitTesting? _hitTest;
  _WebXrAnchors? _anchors;
  _WebXrPlaneDetection? _planes;
  _WebXrDepthSensing? _depth;
  _WebXrLightEstimation? _light;

  WebXrBackendFrame? _currentFrame;
  int _frameNumber = 0;
  int? _rafHandle;
  bool _isEnded = false;
  Object? _error;

  @override
  XrSessionMode get mode => _request.mode;

  @override
  XrBlendMode get blendMode => _backend.blendMode;

  @override
  XrReferenceSpaceType get referenceSpaceType => _referenceSpaceType;

  @override
  Set<String> get features => _features;

  @override
  Stream<XrFrame> get frames => _frames.stream;

  @override
  List<XrInputSourceState> get inputSources => _sourceStates;

  @override
  Stream<void> get inputSourcesChanged => _inputSourcesChanged.stream;

  @override
  XrHitTesting? get hitTest => _hitTest;

  @override
  XrAnchors? get anchors => _anchors;

  @override
  XrPlaneDetection? get planes => _planes;

  @override
  XrDepthSensing? get depthSensing => _depth;

  @override
  XrLightEstimation? get lightEstimation => _light;

  @override
  bool get isEnded => _isEnded;

  @override
  Future<XrSessionEndReason> get ended => _ended.future;

  @override
  Object? get error => _error;

  /// The frame being processed, for feature reads that are frame scoped.
  WebXrBackendFrame get _requireFrame {
    final frame = _currentFrame;
    if (frame == null) {
      throw StateError(
        'This value is only available inside the session frame callback.',
      );
    }
    return frame;
  }

  Future<void> _initialize() async {
    _backend.onEnd = _handleEnd;
    _backend.onContextLost = _handleContextLost;
    _backend.onInputSourcesChange = _handleInputSourcesChange;
    _backend.onSelect = _handleSelect;
    try {
      await _backend.makeXrCompatible();
    } catch (error) {
      await _abort(XrSessionEndReason.contextLost, error);
      throw StateError('The graphics context could not join the session.');
    }
    _layer = _request.useProjectionLayers && _backend.projectionLayersSupported
        ? _backend.createProjectionLayer()
        : _backend.createBaseLayer();
    WebXrBackendSpace? space;
    for (final type in _request.referenceSpaces) {
      space = await _backend.requestReferenceSpace(type);
      if (space == null) continue;
      _referenceSpace = space;
      _referenceSpaceType = type;
      _frame.referenceSpaceType = type;
      break;
    }
    if (space == null) {
      await _abort(XrSessionEndReason.runtimeError, null);
      throw StateError(
        'The browser granted none of ${_request.referenceSpaces}.',
      );
    }
    _features = _backend.enabledFeatures ?? _requestedFeatures;
    if (_features.contains(XrFeatures.hitTest)) {
      _hitTest = _WebXrHitTesting(this);
    }
    if (_features.contains(XrFeatures.anchors)) {
      _anchors = _WebXrAnchors(this);
    }
    if (_features.contains(XrFeatures.planeDetection)) {
      _planes = _WebXrPlaneDetection(this);
    }
    if (_features.contains(XrFeatures.depthSensing)) {
      _depth = _WebXrDepthSensing(this);
    }
    if (_features.contains(XrFeatures.lightEstimation)) {
      final probe = await _backend.requestLightProbe();
      if (probe != null) _light = _WebXrLightEstimation(probe);
    }
    _scheduleFrame();
  }

  void _scheduleFrame() {
    if (_isEnded || _rafHandle != null) return;
    _rafHandle = _backend.requestAnimationFrame(_onAnimationFrame);
  }

  void _onAnimationFrame(double timeMilliseconds, WebXrBackendFrame frame) {
    _rafHandle = null;
    if (_isEnded) return;
    // Ask for the next frame first, so a listener failure cannot stall the
    // loop.
    _scheduleFrame();
    _currentFrame = frame;
    _frameNumber++;
    try {
      _buildFrame(timeMilliseconds, frame);
      _frames.add(_frame);
    } finally {
      _currentFrame = null;
    }
  }

  void _buildFrame(double timeMilliseconds, WebXrBackendFrame frame) {
    _frame.predictedDisplayTime = Duration(
      microseconds: (timeMilliseconds * 1000.0).round(),
    );
    final viewer = frame.viewerPose(_referenceSpace);
    if (viewer == null) {
      _frameViews.clear();
      _frame.viewerPose = null;
    } else {
      viewer.readPose(_viewerPose);
      _frame.viewerPose = _viewerPose;
      final backendViews = viewer.views;
      _ensureViews(backendViews.length);
      for (var i = 0; i < backendViews.length; i++) {
        final backendView = backendViews[i];
        final view = _views[i];
        view.eye = backendView.eye;
        backendView.readPose(view.pose);
        backendView.readProjection(_projectionScratch);
        view.setProjectionFromMatrix(_projectionScratch);
        final target = _layer.viewTarget(backendView);
        view.viewport = normalizedViewportFromGl(
          x: target.x,
          y: target.y,
          width: target.viewportWidth,
          height: target.viewportHeight,
          targetWidth: target.width,
          targetHeight: target.height,
        );
        view.target = _wrapTarget(i, target);
      }
    }
    _frame.target = _sharedTarget;
    _updateInputSources(frame);
    _anchors?._update(frame);
    _planes?._update(frame);
    _light?._update(frame);
  }

  void _ensureViews(int count) {
    while (_views.length < count) {
      _views.add(XrView(eye: XrEye.none));
      _viewTargets.add(null);
      _viewHandles.add(null);
    }
    if (_frameViews.length != count) {
      _frameViews
        ..clear()
        ..addAll(_views.take(count));
    }
  }

  // Wraps the view's color target once per distinct handle and size. A base
  // layer hands every view the same framebuffer, which becomes the frame's
  // shared target; a projection layer hands each view its own texture.
  ExternalRenderTarget? _wrapTarget(int index, WebXrViewTarget target) {
    final handle = target.handle;
    if (handle == null) {
      // TODO(xr-inline): an inline session draws to the canvas's default
      // framebuffer, which the shim cannot wrap; such frames carry no target
      // and are skipped by the loop.
      return null;
    }
    if (target.kind == gpu.ExternalTargetHandleKind.framebuffer) {
      final shared = _sharedTarget;
      if (shared == null ||
          _sharedHandle != handle ||
          shared.width != target.width ||
          shared.height != target.height) {
        _sharedTarget = ExternalRenderTarget.platform(
          handle,
          width: target.width,
          height: target.height,
          kind: target.kind,
        );
        _sharedHandle = handle;
      }
      return null;
    }
    final existing = _viewTargets[index];
    if (existing != null &&
        _viewHandles[index] == handle &&
        existing.width == target.width &&
        existing.height == target.height) {
      return existing;
    }
    final wrapped = ExternalRenderTarget.platform(
      handle,
      width: target.width,
      height: target.height,
      kind: target.kind,
    );
    _viewTargets[index] = wrapped;
    _viewHandles[index] = handle;
    return wrapped;
  }

  void _updateInputSources(WebXrBackendFrame frame) {
    if (_sourcesDirty) {
      _sourcesDirty = false;
      final current = _backend.inputSources;
      _sources.removeWhere((entry) => !current.contains(entry.backend));
      for (final source in current) {
        _entryFor(source);
      }
      _sourceStates
        ..clear()
        ..addAll(_sources.map((entry) => entry.state));
      _frame.inputSources = _sourceStates;
      _inputSourcesChanged.add(null);
    }
    for (final entry in _sources) {
      final state = entry.state;
      final backend = entry.backend;
      state.targetRayPose =
          frame.readPose(
            backend.targetRaySpace,
            _referenceSpace,
            state.targetRayStorage,
          )
          ? state.targetRayStorage
          : null;
      final grip = backend.gripSpace;
      state.gripPose =
          grip != null &&
              frame.readPose(grip, _referenceSpace, state.gripStorage)
          ? state.gripStorage
          : null;
      final pad = entry.gamepad;
      state.gamepad = backend.readGamepad(pad) ? pad : null;
      final joints = backend.handJointSpaces;
      if (joints == null) {
        state.hand = null;
      } else {
        final hand = entry.hand ??= XrHand();
        for (var j = 0; j < joints.length && j < hand.jointPoses.length; j++) {
          final radius = frame.readJointPose(
            joints[j],
            _referenceSpace,
            hand.jointPoses[j],
          );
          hand.jointTracked[j] = radius != null;
          if (radius != null) hand.jointRadii[j] = radius;
        }
        state.hand = hand;
      }
    }
  }

  _SourceEntry _entryFor(WebXrBackendInputSource source) {
    for (final entry in _sources) {
      if (entry.backend == source) return entry;
    }
    final entry = _SourceEntry(
      source,
      XrInputSourceState(
        id: _nextSourceId++,
        handedness: source.handedness,
        targetRayMode: source.targetRayMode,
        profiles: source.profiles,
      ),
    );
    _sources.add(entry);
    return entry;
  }

  void _handleInputSourcesChange() {
    _sourcesDirty = true;
  }

  void _handleEnd() => _finish(XrSessionEndReason.ended);

  void _handleSelect(
    WebXrBackendInputSource source,
    WebXrSelectKind kind,
    WebXrSelectPhase phase,
  ) {
    final state = _entryFor(source).state;
    final pressed = phase == WebXrSelectPhase.start;
    switch (kind) {
      case WebXrSelectKind.select:
        state.selectPressed = pressed;
      case WebXrSelectKind.squeeze:
        state.squeezePressed = pressed;
    }
  }

  void _handleContextLost() {
    // TODO(xr-context-loss): recovery means recreating every GPU resource
    // the shim holds and re-requesting the layer; nothing restores them yet,
    // so the session ends and the app starts a new one.
    unawaited(
      _abort(
        XrSessionEndReason.contextLost,
        StateError('The WebGL context was lost during the XR session.'),
      ),
    );
  }

  Future<void> _abort(XrSessionEndReason reason, Object? error) async {
    _error = error;
    try {
      await _backend.end();
    } catch (_) {
      // The browser may already have torn the session down.
    }
    _finish(reason);
  }

  void _finish(XrSessionEndReason reason) {
    if (_isEnded) return;
    _isEnded = true;
    final handle = _rafHandle;
    if (handle != null) {
      _backend.cancelAnimationFrame(handle);
      _rafHandle = null;
    }
    _frames.close();
    _inputSourcesChanged.close();
    _ended.complete(reason);
  }

  @override
  Future<void> end() async {
    if (_isEnded) return;
    await _backend.end();
    _finish(XrSessionEndReason.ended);
  }

  Future<WebXrBackendSpace?> _spaceFor(XrHitTestOrigin origin) async {
    switch (origin) {
      case XrHitTestViewerOrigin():
        return _viewerSpace ??= await _backend.requestReferenceSpace(
          XrReferenceSpaceType.viewer,
        );
      case XrHitTestInputSourceOrigin(:final source):
        for (final entry in _sources) {
          if (identical(entry.state, source)) {
            return entry.backend.targetRaySpace;
          }
        }
        return null;
    }
  }
}

final class _SourceEntry {
  _SourceEntry(this.backend, this.state);

  final WebXrBackendInputSource backend;
  final XrInputSourceState state;
  final XrGamepadState gamepad = XrGamepadState();
  XrHand? hand;
}

final class _WebXrHitTesting implements XrHitTesting {
  _WebXrHitTesting(this._session);

  final WebXrSession _session;

  @override
  Future<XrHitTestSource?> requestSource(
    XrHitTestOrigin origin, {
    Ray? offsetRay,
  }) async {
    final space = await _session._spaceFor(origin);
    if (space == null) return null;
    final source = await _session._backend.requestHitTestSource(
      space,
      offsetRay: offsetRay,
    );
    if (source == null) return null;
    return _WebXrHitTestSource(_session, source);
  }
}

final class _WebXrHitTestSource implements XrHitTestSource {
  _WebXrHitTestSource(this._session, this._source);

  final WebXrSession _session;
  final WebXrBackendHitTestSource _source;
  final List<_WebXrHitTestResult> _results = [];
  int _resultsFrame = -1;

  @override
  List<XrHitTestResult> get results {
    final frame = _session._requireFrame;
    if (_resultsFrame == _session._frameNumber) return _results;
    _resultsFrame = _session._frameNumber;
    _results.clear();
    for (final hit in frame.hitTestResults(_source)) {
      final result = _WebXrHitTestResult(_session, hit);
      if (hit.readPose(_session._referenceSpace, result.pose)) {
        _results.add(result);
      }
    }
    return _results;
  }

  @override
  void cancel() => _source.cancel();
}

final class _WebXrHitTestResult implements XrHitTestResult {
  _WebXrHitTestResult(this._session, this._hit);

  final WebXrSession _session;
  final WebXrBackendHitTestResult _hit;

  @override
  final XrPose pose = XrPose();

  @override
  Future<XrAnchor?> createAnchor() async {
    final anchors = _session._anchors;
    if (anchors == null) return null;
    final anchor = await _hit.createAnchor();
    if (anchor == null) return null;
    return anchors._adopt(anchor);
  }
}

final class _WebXrAnchors implements XrAnchors {
  _WebXrAnchors(this._session);

  final WebXrSession _session;
  final List<_WebXrAnchor> _anchors = [];

  @override
  List<XrAnchor> get tracked => _anchors;

  @override
  Future<XrAnchor?> createAnchor(XrPose pose) async {
    final anchor = await _session._requireFrame.createAnchor(
      pose,
      _session._referenceSpace,
    );
    if (anchor == null) return null;
    return _adopt(anchor);
  }

  _WebXrAnchor _adopt(WebXrBackendAnchor backend) {
    for (final anchor in _anchors) {
      if (anchor._backend == backend) return anchor;
    }
    final anchor = _WebXrAnchor(backend);
    _anchors.add(anchor);
    return anchor;
  }

  void _update(WebXrBackendFrame frame) {
    final current = frame.trackedAnchors;
    _anchors.removeWhere((anchor) => !current.contains(anchor._backend));
    for (final backend in current) {
      final anchor = _adopt(backend);
      anchor._tracked = frame.readPose(
        backend.space,
        _session._referenceSpace,
        anchor.pose,
      );
    }
  }
}

final class _WebXrAnchor implements XrAnchor {
  _WebXrAnchor(this._backend);

  final WebXrBackendAnchor _backend;
  bool _tracked = false;

  @override
  final XrPose pose = XrPose();

  @override
  bool get isTracked => _tracked;

  @override
  void delete() {
    _tracked = false;
    _backend.delete();
  }
}

final class _WebXrPlaneDetection implements XrPlaneDetection {
  _WebXrPlaneDetection(this._session);

  final WebXrSession _session;
  final List<_WebXrPlane> _planes = [];

  @override
  List<XrPlane> get planes => _planes;

  void _update(WebXrBackendFrame frame) {
    final current = frame.detectedPlanes;
    _planes.removeWhere((plane) => !current.contains(plane._backend));
    for (final backend in current) {
      var plane = _planes.cast<_WebXrPlane?>().firstWhere(
        (plane) => plane!._backend == backend,
        orElse: () => null,
      );
      if (plane == null) {
        plane = _WebXrPlane(backend);
        _planes.add(plane);
      }
      plane._tracked = frame.readPose(
        backend.space,
        _session._referenceSpace,
        plane._pose,
      );
    }
  }
}

final class _WebXrPlane implements XrPlane {
  _WebXrPlane(this._backend);

  final WebXrBackendPlane _backend;
  final XrPose _pose = XrPose();
  bool _tracked = false;

  @override
  XrPlaneOrientation get orientation => _backend.orientation;

  @override
  List<Vector3> get polygon => _backend.polygon;

  @override
  XrPose? get pose => _tracked ? _pose : null;

  @override
  double get lastChangedTime => _backend.lastChangedTime;
}

final class _WebXrDepthSensing implements XrDepthSensing {
  _WebXrDepthSensing(this._session);

  final WebXrSession _session;

  @override
  XrDepthInformation? depthForView(XrView view) {
    final frame = _session._requireFrame;
    final index = _session._views.indexOf(view);
    if (index < 0) return null;
    final viewer = frame.viewerPose(_session._referenceSpace);
    if (viewer == null || index >= viewer.views.length) return null;
    return frame.depthInformation(viewer.views[index]);
  }
}

final class _WebXrLightEstimation implements XrLightEstimation {
  _WebXrLightEstimation(this._probe);

  final WebXrBackendLightProbe _probe;
  final XrLightEstimate _estimate = XrLightEstimate();
  bool _hasEstimate = false;

  @override
  XrLightEstimate? get estimate => _hasEstimate ? _estimate : null;

  void _update(WebXrBackendFrame frame) {
    if (frame.readLightEstimate(_probe, _estimate)) _hasEstimate = true;
  }
}
