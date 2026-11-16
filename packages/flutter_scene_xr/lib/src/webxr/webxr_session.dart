import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_scene/gpu.dart'
    as gpu
    show ExternalTargetHandleKind, textureToPlatformImage;
import 'package:flutter_scene/scene.dart'
    show ExternalRenderTarget, FrameCompletion;
import 'package:vector_math/vector_math.dart' show Matrix4, Ray, Vector3;

import 'package:flutter_scene_xr/src/features/anchors.dart';
import 'package:flutter_scene_xr/src/features/depth.dart';
import 'package:flutter_scene_xr/src/features/hit_test.dart';
import 'package:flutter_scene_xr/src/features/layers.dart';
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

  // The smallest render scale taken, a tenth of the recommended size.
  static const double _minRenderScale = 0.1;

  final XrSessionRequest _request;
  final WebXrBackendSession _backend;
  final Set<String> _requestedFeatures;

  final StreamController<XrFrame> _frames = StreamController.broadcast(
    sync: true,
  );
  final StreamController<void> _inputSourcesChanged =
      StreamController.broadcast(sync: true);
  final Completer<XrSessionEndReason> _ended = Completer();

  late WebXrBackendLayer _layer;
  // A layer made for a new render scale, which the browser draws from on
  // the frame after it was installed.
  WebXrBackendLayer? _nextLayer;
  bool _usesProjectionLayer = false;
  double _renderScale = 1.0;
  // The scale [_layer], or the one replacing it, was created at.
  double _layerScale = 1.0;
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

  // The layer's framebuffer, wrapped once and replaced when it changes. For a
  // layer that presents, a texture the session owns at the layer's size.
  ExternalRenderTarget? _sharedTarget;
  Object? _sharedHandle;
  bool _presenting = false;
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
  _WebXrLayers? _layers;

  WebXrBackendFrame? _currentFrame;
  // Whether the frame's renderer reported it drew nothing.
  bool _frameSkipped = false;
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
  XrLayers? get layers => _layers;

  @override
  double get renderScale => _renderScale;

  @override
  set renderScale(double value) {
    if (value.isNaN) return;
    _renderScale = value.clamp(_minRenderScale, maxRenderScale);
  }

  @override
  double get maxRenderScale => math.max(1.0, _backend.nativeScaleFactor);

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
    _features = _backend.enabledFeatures ?? _requestedFeatures;
    // Quad and cylinder layers stack on a projection layer; a base layer
    // excludes them.
    final wantsLayers = _features.contains(XrFeatures.layers);
    _usesProjectionLayer =
        (_request.useProjectionLayers || wantsLayers) &&
        _backend.projectionLayersSupported;
    renderScale = _request.renderScale;
    _layerScale = _renderScale;
    _layer = _createLayer(_renderScale);
    _frame.onSubmit = _handleSubmit;
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
    if (wantsLayers &&
        _usesProjectionLayer &&
        _backend.compositionLayersSupported) {
      // Head-locked layers sit in the viewer space, which a layer cannot
      // wait for when it is created.
      _viewerSpace ??= await _backend.requestReferenceSpace(
        XrReferenceSpaceType.viewer,
      );
      _layers = _WebXrLayers(this);
    }
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
    final next = _nextLayer;
    if (next != null) {
      _layer = next;
      _nextLayer = null;
    }
    _currentFrame = frame;
    _frameNumber++;
    _frameSkipped = false;
    try {
      _buildFrame(timeMilliseconds, frame);
      _frames.add(_frame);
      _presentFrame();
      _layers?._push();
      _applyRenderScale();
    } catch (error) {
      // Runtime data the frame cannot be built from fails the same way every
      // frame and would starve listeners silently (the next frame is already
      // scheduled); end the session so they hear about it once.
      unawaited(_abort(XrSessionEndReason.runtimeError, error));
      rethrow;
    } finally {
      _currentFrame = null;
    }
  }

  // Hands the frame's color to a layer that draws to a canvas. Listeners
  // render synchronously inside the frame callback, so the texture is final
  // here.
  void _presentFrame() {
    if (!_presenting || _frameViews.isEmpty || _frameSkipped) return;
    final target = _sharedTarget;
    if (target == null) return;
    final image = gpu.textureToPlatformImage(target.color);
    if (image != null) _layer.present(image);
  }

  // What the frame's renderer reported through XrFrame.submit. The browser
  // takes a headset layer when the callback returns, so only the copy onto a
  // canvas has anything to hold back.
  void _handleSubmit(FrameCompletion completion) {
    _frameSkipped = completion.skipped;
  }

  WebXrBackendLayer _createLayer(double scale) => _usesProjectionLayer
      ? _backend.createProjectionLayer(scale: scale)
      : _backend.createBaseLayer(scale: scale);

  // Replaces the layer after the render scale changed. A layer that presents
  // keeps its size, and the texture the session owns is scaled instead (see
  // _wrapTarget).
  void _applyRenderScale() {
    if (_renderScale == _layerScale || _layer.presents) return;
    _layerScale = _renderScale;
    _nextLayer = _createLayer(_renderScale);
    _layers?._install();
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
      if (!_layer.presents) {
        // A canvas the backend cannot present either; the frame carries no
        // target and the loop skips it.
        _sharedTarget = null;
        _presenting = false;
        return null;
      }
      // The session owns this texture, so the render scale sizes it and
      // the copy onto the canvas resamples.
      final width = math.max(1, (target.width * _renderScale).round());
      final height = math.max(1, (target.height * _renderScale).round());
      final shared = _sharedTarget;
      if (shared == null ||
          !_presenting ||
          shared.width != width ||
          shared.height != height) {
        _sharedTarget = ExternalRenderTarget.allocate(
          width: width,
          height: height,
        );
        _sharedHandle = null;
        _presenting = true;
      }
      return null;
    }
    if (target.kind == gpu.ExternalTargetHandleKind.framebuffer) {
      final shared = _sharedTarget;
      if (shared == null ||
          _presenting ||
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
        _presenting = false;
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

final class _WebXrLayers implements XrLayers {
  _WebXrLayers(this._session);

  final WebXrSession _session;
  final List<_WebXrLayer> _all = [];

  @override
  List<XrCompositionLayer> get layers => List.unmodifiable(_all);

  WebXrBackendSpace _spaceFor(XrLayerSpace space) => switch (space) {
    XrLayerSpace.reference => _session._referenceSpace,
    XrLayerSpace.viewer =>
      _session._viewerSpace ??
          (throw UnsupportedError(
            'The runtime granted no viewer space for a head-locked layer.',
          )),
  };

  static void _checkPixels(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('A layer image needs a positive pixel size.');
    }
  }

  @override
  XrQuadLayer createQuadLayer({
    required int pixelWidth,
    required int pixelHeight,
    required double width,
    required double height,
    XrPose? pose,
    XrLayerSpace space = XrLayerSpace.reference,
  }) {
    _checkPixels(pixelWidth, pixelHeight);
    final at = XrPose();
    if (pose != null) at.setFrom(pose);
    final layer = _WebXrQuadLayer(
      this,
      _session._backend.createQuadLayer(
        space: _spaceFor(space),
        pose: at,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        width: width,
        height: height,
      ),
      space,
      at,
      pixelWidth,
      pixelHeight,
      width,
      height,
    );
    _all.add(layer);
    _install();
    return layer;
  }

  @override
  XrCylinderLayer createCylinderLayer({
    required int pixelWidth,
    required int pixelHeight,
    required double radius,
    required double centralAngle,
    required double aspectRatio,
    XrPose? pose,
    XrLayerSpace space = XrLayerSpace.reference,
  }) {
    _checkPixels(pixelWidth, pixelHeight);
    final at = XrPose();
    if (pose != null) at.setFrom(pose);
    final layer = _WebXrCylinderLayer(
      this,
      _session._backend.createCylinderLayer(
        space: _spaceFor(space),
        pose: at,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        radius: radius,
        centralAngle: centralAngle,
        aspectRatio: aspectRatio,
      ),
      space,
      at,
      pixelWidth,
      pixelHeight,
      radius,
      centralAngle,
      aspectRatio,
    );
    _all.add(layer);
    _install();
    return layer;
  }

  // Hands the browser the projection layer with the visible layers over it.
  void _install() =>
      _session._backend.setLayers(_session._nextLayer ?? _session._layer, [
        for (final layer in _all)
          if (layer._visible) layer._backend,
      ]);

  void _push() {
    for (final layer in _all) {
      layer._push();
    }
  }

  void _remove(_WebXrLayer layer) {
    if (_all.remove(layer)) _install();
  }
}

abstract base class _WebXrLayer implements XrCompositionLayer {
  _WebXrLayer(
    this._owner,
    this._backend,
    this.space,
    this.pose,
    this.pixelWidth,
    this.pixelHeight,
  ) {
    _sentPose.setFrom(pose);
  }

  final _WebXrLayers _owner;
  final WebXrBackendCompositionLayer _backend;

  @override
  final XrLayerSpace space;

  @override
  final XrPose pose;

  @override
  final int pixelWidth;

  @override
  final int pixelHeight;

  // The pose the browser last heard, so an unmoved layer sends nothing.
  final XrPose _sentPose = XrPose();
  bool _visible = true;
  bool _disposed = false;
  ExternalRenderTarget? _target;
  Object? _targetHandle;

  @override
  bool get visible => _visible;

  @override
  set visible(bool value) {
    if (_disposed || value == _visible) return;
    _visible = value;
    _owner._install();
  }

  @override
  bool get needsRedraw => !_disposed && _backend.needsRedraw;

  @override
  ExternalRenderTarget? acquireTarget() {
    final frame = _owner._session._currentFrame;
    if (_disposed || frame == null) return null;
    final image = _backend.subImage(frame);
    final handle = image.handle;
    if (handle == null) return null;
    final existing = _target;
    if (existing != null &&
        _targetHandle == handle &&
        existing.width == image.width &&
        existing.height == image.height) {
      return existing;
    }
    _targetHandle = handle;
    return _target = ExternalRenderTarget.platform(
      handle,
      width: image.width,
      height: image.height,
      kind: image.kind,
    );
  }

  // Sends the pose and shape on when the app changed them.
  void _push() {
    if (_disposed) return;
    final p = pose.position, q = pose.orientation;
    final sp = _sentPose.position, sq = _sentPose.orientation;
    if (p != sp || q.x != sq.x || q.y != sq.y || q.z != sq.z || q.w != sq.w) {
      _sentPose.setFrom(pose);
      _backend.setPose(pose);
    }
    _pushShape();
  }

  void _pushShape();

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _target = null;
    _targetHandle = null;
    _owner._remove(this);
    _backend.destroy();
  }
}

final class _WebXrQuadLayer extends _WebXrLayer implements XrQuadLayer {
  _WebXrQuadLayer(
    super._owner,
    super._backend,
    super.space,
    super.pose,
    super.pixelWidth,
    super.pixelHeight,
    this.width,
    this.height,
  ) : _sentWidth = width,
      _sentHeight = height;

  @override
  double width;

  @override
  double height;

  double _sentWidth;
  double _sentHeight;

  @override
  void _pushShape() {
    if (width == _sentWidth && height == _sentHeight) return;
    _sentWidth = width;
    _sentHeight = height;
    _backend.setQuadSize(width, height);
  }
}

final class _WebXrCylinderLayer extends _WebXrLayer implements XrCylinderLayer {
  _WebXrCylinderLayer(
    super._owner,
    super._backend,
    super.space,
    super.pose,
    super.pixelWidth,
    super.pixelHeight,
    this.radius,
    this.centralAngle,
    this.aspectRatio,
  ) : _sentRadius = radius,
      _sentAngle = centralAngle,
      _sentAspect = aspectRatio;

  @override
  double radius;

  @override
  double centralAngle;

  @override
  double aspectRatio;

  double _sentRadius;
  double _sentAngle;
  double _sentAspect;

  @override
  void _pushShape() {
    if (radius == _sentRadius &&
        centralAngle == _sentAngle &&
        aspectRatio == _sentAspect) {
      return;
    }
    _sentRadius = radius;
    _sentAngle = centralAngle;
    _sentAspect = aspectRatio;
    _backend.setCylinderShape(radius, centralAngle, aspectRatio);
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
