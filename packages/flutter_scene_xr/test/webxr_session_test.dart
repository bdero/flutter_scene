import 'dart:math' as math;

import 'package:flutter_scene/gpu.dart' as gpu show ExternalTargetHandleKind;
import 'package:flutter_scene/scene.dart' show FrameCompletion;
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_backend.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A browser in miniature: one session at a time, reference spaces granted
// from a list, frames pushed by the test.
final class _FakeBackend implements WebXrBackend {
  _FakeBackend({
    this.supported = true,
    this.grantedSpaces = const {},
    this.layersSupported = false,
    this.nativeScale = 1.0,
  });

  final bool supported;
  final Set<XrReferenceSpaceType> grantedSpaces;

  /// Whether sessions offer projection, quad and cylinder layers.
  final bool layersSupported;

  /// What sessions report as the native framebuffer scale.
  final double nativeScale;
  _FakeSession? session;
  WebXrSessionInit? lastInit;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> isSessionSupported(XrSessionMode mode) async =>
      supported && mode != XrSessionMode.inline;

  @override
  Future<WebXrBackendSession> requestSession(
    XrSessionMode mode,
    WebXrSessionInit init,
  ) async {
    lastInit = init;
    return session = _FakeSession(this);
  }

  @override
  Object? get defaultDomOverlayRoot => 'body';
}

final class _FakeSpace implements WebXrBackendSpace {
  _FakeSpace(this.name);

  final String name;
}

final class _FakeSession implements WebXrBackendSession {
  _FakeSession(this.backend);

  final _FakeBackend backend;
  WebXrFrameCallback? pending;
  int nextHandle = 1;
  int? cancelled;
  bool ended = false;
  bool madeCompatible = false;
  bool createdBaseLayer = false;

  /// Every layer created, in order, with the scale it was asked for.
  final List<_FakeLayer> createdLayers = [];

  /// The layer lists handed to `setLayers`, the projection layer first.
  final List<List<Object>> installedLayers = [];
  final List<_FakeCompositionLayer> compositionLayers = [];
  final List<_FakeInputSource> sources = [];
  void Function()? _onInputSourcesChange;
  void Function(WebXrBackendInputSource, WebXrSelectKind, WebXrSelectPhase)?
  _onSelect;
  void Function()? _onEnd;
  void Function()? _onContextLost;

  // Runs the pending animation frame with [frame], as the browser would.
  void tick(double timeMs, _FakeFrame frame) {
    final callback = pending;
    pending = null;
    callback!(timeMs, frame);
  }

  void changeSources(List<_FakeInputSource> next) {
    sources
      ..clear()
      ..addAll(next);
    _onInputSourcesChange?.call();
  }

  void select(_FakeInputSource source, WebXrSelectPhase phase) =>
      _onSelect?.call(source, WebXrSelectKind.select, phase);

  void loseContext() => _onContextLost?.call();

  void endFromBrowser() {
    ended = true;
    _onEnd?.call();
  }

  @override
  XrBlendMode get blendMode => XrBlendMode.opaque;

  @override
  Set<String>? get enabledFeatures => null;

  @override
  Future<void> makeXrCompatible() async => madeCompatible = true;

  @override
  Future<WebXrBackendSpace?> requestReferenceSpace(
    XrReferenceSpaceType type,
  ) async =>
      backend.grantedSpaces.contains(type) ? _FakeSpace(type.name) : null;

  @override
  bool get projectionLayersSupported => backend.layersSupported;

  @override
  double get nativeScaleFactor => backend.nativeScale;

  @override
  WebXrBackendLayer createBaseLayer({double scale = 1.0}) {
    createdBaseLayer = true;
    final layer = _FakeLayer(scale: scale);
    createdLayers.add(layer);
    return layer;
  }

  @override
  WebXrBackendLayer createProjectionLayer({double scale = 1.0}) {
    final layer = _FakeLayer(scale: scale, projection: true);
    createdLayers.add(layer);
    return layer;
  }

  @override
  bool get compositionLayersSupported => backend.layersSupported;

  @override
  WebXrBackendCompositionLayer createQuadLayer({
    required WebXrBackendSpace space,
    required XrPose pose,
    required int pixelWidth,
    required int pixelHeight,
    required double width,
    required double height,
  }) {
    final layer = _FakeCompositionLayer(
      space: space as _FakeSpace,
      pose: XrPose()..setFrom(pose),
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      shape: [width, height],
    );
    compositionLayers.add(layer);
    return layer;
  }

  @override
  WebXrBackendCompositionLayer createCylinderLayer({
    required WebXrBackendSpace space,
    required XrPose pose,
    required int pixelWidth,
    required int pixelHeight,
    required double radius,
    required double centralAngle,
    required double aspectRatio,
  }) {
    final layer = _FakeCompositionLayer(
      space: space as _FakeSpace,
      pose: XrPose()..setFrom(pose),
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
      shape: [radius, centralAngle, aspectRatio],
    );
    compositionLayers.add(layer);
    return layer;
  }

  @override
  void setLayers(
    WebXrBackendLayer projection,
    List<WebXrBackendCompositionLayer> layers,
  ) => installedLayers.add([projection, ...layers]);

  @override
  int requestAnimationFrame(WebXrFrameCallback callback) {
    pending = callback;
    return nextHandle++;
  }

  @override
  void cancelAnimationFrame(int handle) => cancelled = handle;

  @override
  Future<void> end() async => ended = true;

  @override
  List<WebXrBackendInputSource> get inputSources => List.of(sources);

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
  }) async => null;

  @override
  Future<WebXrBackendLightProbe?> requestLightProbe() async => null;
}

// A 2000x1000 layer with the eyes side by side. The handle is null because
// the test runs where no backend can wrap a framebuffer, which is the
// inline-session shape; the viewport math is what this checks.
final class _FakeLayer implements WebXrBackendLayer {
  _FakeLayer({this.scale = 1.0, this.projection = false});

  /// The scale the session created the layer at.
  final double scale;

  /// Whether this is a projection layer.
  final bool projection;

  @override
  bool get presents => false;

  @override
  void present(Object image) => throw UnsupportedError('fake layer');

  @override
  WebXrViewTarget viewTarget(WebXrBackendView view) {
    final left = view.eye == XrEye.left;
    final width = (2000 * scale).round();
    final height = (1000 * scale).round();
    return WebXrViewTarget(
      handle: null,
      kind: gpu.ExternalTargetHandleKind.framebuffer,
      width: width,
      height: height,
      x: left ? 0 : width ~/ 2,
      y: 0,
      viewportWidth: width ~/ 2,
      viewportHeight: height,
    );
  }
}

// A quad or cylinder layer that records what the session tells it. It has
// no image to hand out, like a layer the browser has not composited yet.
final class _FakeCompositionLayer implements WebXrBackendCompositionLayer {
  _FakeCompositionLayer({
    required this.space,
    required this.pose,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.shape,
  });

  final _FakeSpace space;
  final XrPose pose;
  final int pixelWidth;
  final int pixelHeight;

  /// Width and height for a quad; radius, angle and aspect for a cylinder.
  List<double> shape;
  int poseUpdates = 0;
  int subImageRequests = 0;
  bool destroyed = false;

  @override
  bool needsRedraw = true;

  @override
  void setPose(XrPose value) {
    pose.setFrom(value);
    poseUpdates++;
  }

  @override
  void setQuadSize(double width, double height) => shape = [width, height];

  @override
  void setCylinderShape(
    double radius,
    double centralAngle,
    double aspectRatio,
  ) => shape = [radius, centralAngle, aspectRatio];

  @override
  WebXrViewTarget subImage(WebXrBackendFrame frame) {
    subImageRequests++;
    return WebXrViewTarget(
      handle: null,
      kind: gpu.ExternalTargetHandleKind.texture,
      width: pixelWidth,
      height: pixelHeight,
      x: 0,
      y: 0,
      viewportWidth: pixelWidth,
      viewportHeight: pixelHeight,
    );
  }

  @override
  void destroy() => destroyed = true;
}

final class _FakeView implements WebXrBackendView {
  _FakeView(this.eye, this.pose, this.projection);

  @override
  final XrEye eye;
  final XrPose pose;
  final Matrix4 projection;

  @override
  void readPose(XrPose out) => out.setFrom(pose);

  @override
  void readProjection(Matrix4 out) => out.setFrom(projection);
}

final class _FakeViewerPose implements WebXrBackendViewerPose {
  _FakeViewerPose(this.pose, this.views);

  final XrPose pose;

  @override
  final List<WebXrBackendView> views;

  @override
  void readPose(XrPose out) => out.setFrom(pose);
}

final class _FakeInputSource implements WebXrBackendInputSource {
  _FakeInputSource(this.handedness, {this.withGamepad = true});

  @override
  final XrHandedness handedness;
  final bool withGamepad;
  final XrPose rayPose = XrPose(position: Vector3(0.2, 1.0, -0.3));
  double trigger = 0.0;

  @override
  XrTargetRayMode get targetRayMode => XrTargetRayMode.trackedPointer;

  @override
  List<String> get profiles => const ['generic-trigger'];

  @override
  final WebXrBackendSpace targetRaySpace = _FakeSpace('ray');

  @override
  WebXrBackendSpace? get gripSpace => null;

  @override
  bool readGamepad(XrGamepadState out) {
    if (!withGamepad) return false;
    out.resize(buttonCount: 1, axisCount: 0);
    out.buttonValues[0] = trigger;
    out.buttonPressed[0] = trigger > 0.5;
    return true;
  }

  @override
  List<WebXrBackendSpace>? get handJointSpaces => null;
}

final class _FakeFrame implements WebXrBackendFrame {
  _FakeFrame({this.viewer, this.sources = const [], this.unreadable = false});

  final _FakeViewerPose? viewer;
  final List<_FakeInputSource> sources;

  /// Whether reading the frame throws, as malformed runtime data does.
  final bool unreadable;

  @override
  WebXrBackendViewerPose? viewerPose(WebXrBackendSpace referenceSpace) {
    if (unreadable) throw StateError('frame data unreadable');
    return viewer;
  }

  @override
  bool readPose(
    WebXrBackendSpace space,
    WebXrBackendSpace baseSpace,
    XrPose out,
  ) {
    for (final source in sources) {
      if (identical(source.targetRaySpace, space)) {
        out.setFrom(source.rayPose);
        return true;
      }
    }
    return false;
  }

  @override
  double? readJointPose(
    WebXrBackendSpace jointSpace,
    WebXrBackendSpace baseSpace,
    XrPose out,
  ) => null;

  @override
  List<WebXrBackendHitTestResult> hitTestResults(
    WebXrBackendHitTestSource source,
  ) => const [];

  @override
  List<WebXrBackendAnchor> get trackedAnchors => const [];

  @override
  Future<WebXrBackendAnchor?> createAnchor(
    XrPose pose,
    WebXrBackendSpace space,
  ) async => null;

  @override
  List<WebXrBackendPlane> get detectedPlanes => const [];

  @override
  XrDepthInformation? depthInformation(WebXrBackendView view) => null;

  @override
  bool readLightEstimate(WebXrBackendLightProbe probe, XrLightEstimate out) =>
      false;
}

Matrix4 _glProjection(double tanLeft, double tanRight) {
  const near = 0.1, far = 100.0;
  final tanUp = math.tan(0.7);
  final width = tanRight - tanLeft;
  final height = 2 * tanUp;
  return Matrix4(
    2.0 / width,
    0,
    0,
    0,
    0,
    2.0 / height,
    0,
    0,
    (tanRight + tanLeft) / width,
    0,
    -(far + near) / (far - near),
    -1,
    0,
    0,
    -2 * far * near / (far - near),
    0,
  );
}

_FakeFrame _stereo({List<_FakeInputSource> sources = const []}) {
  final head = XrPose(position: Vector3(0, 1.6, 0));
  return _FakeFrame(
    viewer: _FakeViewerPose(head, [
      _FakeView(
        XrEye.left,
        XrPose(position: Vector3(-0.032, 1.6, 0)),
        _glProjection(-math.tan(0.9), math.tan(0.7)),
      ),
      _FakeView(
        XrEye.right,
        XrPose(position: Vector3(0.032, 1.6, 0)),
        _glProjection(-math.tan(0.7), math.tan(0.9)),
      ),
    ]),
    sources: sources,
  );
}

void main() {
  group('WebXrRuntime', () {
    test('reports support from the backend', () async {
      final runtime = WebXrRuntime(_FakeBackend(supported: false));
      expect(runtime.isSupported, isFalse);
      expect(
        await runtime.isSessionSupported(XrSessionMode.immersiveVr),
        isFalse,
      );
      expect(
        runtime.requestSession(
          const XrSessionRequest(mode: XrSessionMode.immersiveVr),
        ),
        throwsUnsupportedError,
      );
    });

    test('falls back through the reference space preferences', () async {
      final backend = _FakeBackend(
        grantedSpaces: {
          XrReferenceSpaceType.local,
          XrReferenceSpaceType.viewer,
        },
      );
      final session = await WebXrRuntime(backend).requestSession(
        const XrSessionRequest(
          mode: XrSessionMode.immersiveVr,
          referenceSpaces: [
            XrReferenceSpaceType.boundedFloor,
            XrReferenceSpaceType.localFloor,
            XrReferenceSpaceType.local,
          ],
        ),
      );
      expect(session.referenceSpaceType, XrReferenceSpaceType.local);
      expect(
        backend.lastInit!.optionalFeatures,
        containsAll(['bounded-floor', 'local-floor']),
      );
      expect(backend.session!.madeCompatible, isTrue);
      expect(backend.session!.createdBaseLayer, isTrue);
      expect(backend.session!.pending, isNotNull);
    });

    test('refuses when no reference space is granted', () async {
      final backend = _FakeBackend();
      expect(
        WebXrRuntime(backend).requestSession(
          const XrSessionRequest(mode: XrSessionMode.immersiveVr),
        ),
        throwsStateError,
      );
    });

    test(
      'asks for dom-overlay and depth sensing when the request implies',
      () async {
        final backend = _FakeBackend(
          grantedSpaces: {XrReferenceSpaceType.local},
        );
        await WebXrRuntime(backend).requestSession(
          const XrSessionRequest(
            mode: XrSessionMode.immersiveAr,
            optionalFeatures: [XrFeatures.depthSensing],
            domOverlayRoot: 'body',
          ),
        );
        expect(backend.lastInit!.optionalFeatures, contains('dom-overlay'));
        expect(backend.lastInit!.depthSensing, isTrue);
        expect(backend.lastInit!.domOverlayRoot, 'body');
      },
    );
  });

  group('WebXrSession', () {
    late _FakeBackend backend;
    late XrSession session;

    setUp(() async {
      backend = _FakeBackend(grantedSpaces: {XrReferenceSpaceType.localFloor});
      session = await WebXrRuntime(
        backend,
      ).requestSession(const XrSessionRequest(mode: XrSessionMode.immersiveVr));
    });

    test('turns a browser frame into an XrFrame synchronously', () {
      XrFrame? received;
      session.frames.listen((frame) => received = frame);
      backend.session!.tick(1234.5, _stereo());

      final frame = received!;
      expect(frame.predictedDisplayTime.inMicroseconds, 1234500);
      expect(frame.referenceSpaceType, XrReferenceSpaceType.localFloor);
      expect(frame.viewerPose!.position.y, closeTo(1.6, 1e-6));
      expect(frame.views, hasLength(2));
      expect(frame.views[0].eye, XrEye.left);
      expect(frame.views[1].eye, XrEye.right);
      expect(frame.views[0].pose.position.x, closeTo(-0.032, 1e-6));
      // GL bottom-left viewports became top-left normalized rects.
      expect(frame.views[0].viewport.left, 0);
      expect(frame.views[0].viewport.width, 0.5);
      expect(frame.views[1].viewport.left, 0.5);
      expect(frame.views[1].viewport.top, 0);
      expect(frame.views[1].viewport.height, 1);
      // The GL projection decoded into tangents.
      expect(frame.views[0].projection.tanLeft, closeTo(-math.tan(0.9), 1e-6));
      expect(frame.views[0].projection.tanRight, closeTo(math.tan(0.7), 1e-6));
      expect(frame.views[1].projection.tanRight, closeTo(math.tan(0.9), 1e-6));
      expect(frame.views[0].projection.near, closeTo(0.1, 1e-6));
      expect(frame.views[0].projection.far, closeTo(100, 1e-3));
      // No wrappable framebuffer here, so no target.
      expect(frame.hasTargets, isFalse);
      // The next frame was requested before listeners ran.
      expect(backend.session!.pending, isNotNull);
    });

    test('reuses the frame and view objects', () {
      final frames = <XrFrame>[];
      session.frames.listen(frames.add);
      backend.session!.tick(0, _stereo());
      final views = List.of(frames.single.views);
      backend.session!.tick(16, _stereo());
      expect(identical(frames[0], frames[1]), isTrue);
      expect(identical(frames[1].views[0], views[0]), isTrue);
      expect(
        identical(frames[1].views[0].projection, views[0].projection),
        isTrue,
      );
    });

    test('a frame with no viewer pose has no views', () {
      XrFrame? received;
      session.frames.listen((frame) => received = frame);
      backend.session!.tick(0, _FakeFrame());
      expect(received!.hasViews, isFalse);
      expect(received!.viewerPose, isNull);
    });

    test('tracks input sources, gamepads and select events', () {
      final left = _FakeInputSource(XrHandedness.left);
      final right = _FakeInputSource(XrHandedness.right, withGamepad: false);
      var changes = 0;
      session.inputSourcesChanged.listen((_) => changes++);
      backend.session!.changeSources([left, right]);
      backend.session!.tick(0, _stereo(sources: [left, right]));

      expect(changes, 1);
      expect(session.inputSources, hasLength(2));
      final leftState = session.inputSources[0];
      expect(leftState.handedness, XrHandedness.left);
      expect(leftState.profiles, ['generic-trigger']);
      expect(leftState.targetRayPose!.position.x, closeTo(0.2, 1e-6));
      expect(leftState.gripPose, isNull);
      expect(leftState.gamepad!.buttonValues, [0.0]);
      expect(session.inputSources[1].gamepad, isNull);

      left.trigger = 0.9;
      backend.session!.select(left, WebXrSelectPhase.start);
      backend.session!.tick(16, _stereo(sources: [left, right]));
      expect(identical(session.inputSources[0], leftState), isTrue);
      expect(leftState.gamepad!.buttonValues, [0.9]);
      expect(leftState.gamepad!.buttonPressed, [true]);
      expect(leftState.selectPressed, isTrue);
      backend.session!.select(left, WebXrSelectPhase.end);
      expect(leftState.selectPressed, isFalse);

      // The frame carries the same list the session exposes.
      XrFrame? received;
      session.frames.listen((frame) => received = frame);
      backend.session!.changeSources([right]);
      backend.session!.tick(32, _stereo(sources: [right]));
      expect(changes, 2);
      expect(received!.inputSources, hasLength(1));
      expect(received!.inputSources.single.handedness, XrHandedness.right);
    });

    test('features the browser did not grant are null', () {
      expect(session.hitTest, isNull);
      expect(session.anchors, isNull);
      expect(session.planes, isNull);
      expect(session.depthSensing, isNull);
      expect(session.lightEstimation, isNull);
      // Without enabledFeatures the session assumes what it asked for, which
      // here is only the reference space.
      expect(session.features, {'local-floor'});
    });

    test('end() completes ended and stops the frame loop', () async {
      final frames = <XrFrame>[];
      session.frames.listen(frames.add);
      final pendingHandle = backend.session!.nextHandle - 1;
      await session.end();
      expect(session.isEnded, isTrue);
      expect(await session.ended, XrSessionEndReason.ended);
      expect(backend.session!.ended, isTrue);
      expect(backend.session!.cancelled, pendingHandle);
    });

    test('the browser ending the session completes ended', () async {
      backend.session!.endFromBrowser();
      expect(await session.ended, XrSessionEndReason.ended);
      expect(session.isEnded, isTrue);
    });

    test(
      'a frame that cannot be built ends the session with an error',
      () async {
        var delivered = 0;
        session.frames.listen((_) => delivered++);
        expect(
          () => backend.session!.tick(0, _FakeFrame(unreadable: true)),
          throwsStateError,
        );
        expect(await session.ended, XrSessionEndReason.runtimeError);
        expect(session.isEnded, isTrue);
        expect(delivered, 0);
      },
    );

    test('losing the context ends the session with an error', () async {
      backend.session!.loseContext();
      expect(await session.ended, XrSessionEndReason.contextLost);
      expect(session.error, isA<StateError>());
      expect(backend.session!.ended, isTrue);
    });
  });
  group('render scale', () {
    test('the request sets the first layer\'s scale, clamped', () async {
      final backend = _FakeBackend(
        grantedSpaces: {XrReferenceSpaceType.localFloor},
        nativeScale: 1.5,
      );
      final session = await WebXrRuntime(backend).requestSession(
        const XrSessionRequest(
          mode: XrSessionMode.immersiveVr,
          renderScale: 4.0,
        ),
      );
      expect(session.maxRenderScale, 1.5);
      expect(session.renderScale, 1.5);
      expect(backend.session!.createdLayers.single.scale, 1.5);
    });

    test('a new scale replaces the layer from the following frame', () async {
      final backend = _FakeBackend(
        grantedSpaces: {XrReferenceSpaceType.localFloor},
      );
      final session = await WebXrRuntime(
        backend,
      ).requestSession(const XrSessionRequest(mode: XrSessionMode.immersiveVr));
      final fake = backend.session!;
      // The fake reports the layer size through each view's viewport, which
      // the session normalizes against it, so the layer in use shows in
      // which one answered.
      expect(fake.createdLayers, hasLength(1));
      expect(session.renderScale, 1.0);

      session.renderScale = 0.5;
      expect(session.renderScale, 0.5);
      // Nothing is created until a frame ends.
      expect(fake.createdLayers, hasLength(1));
      fake.tick(0, _stereo());
      expect(fake.createdLayers, hasLength(2));
      expect(fake.createdLayers.last.scale, 0.5);

      // Unchanged scale, no further layers.
      fake.tick(16, _stereo());
      fake.tick(32, _stereo());
      expect(fake.createdLayers, hasLength(2));

      // Values out of range clamp, and nonsense is ignored.
      session.renderScale = 0.0;
      expect(session.renderScale, 0.1);
      session.renderScale = 9.0;
      expect(session.renderScale, 1.0);
      session.renderScale = double.nan;
      expect(session.renderScale, 1.0);
    });
  });

  group('frame submission', () {
    test('a frame hands its completion to the session', () async {
      final backend = _FakeBackend(
        grantedSpaces: {XrReferenceSpaceType.localFloor},
      );
      final session = await WebXrRuntime(
        backend,
      ).requestSession(const XrSessionRequest(mode: XrSessionMode.immersiveVr));
      var submitted = 0;
      session.frames.listen((frame) {
        // Submitting is safe on a runtime that needs nothing from it.
        frame.submit(FrameCompletion.skipped());
        submitted++;
      });
      backend.session!.tick(0, _stereo());
      backend.session!.tick(16, _stereo());
      expect(submitted, 2);
      expect(session.isEnded, isFalse);
    });

    test('a hand-built frame reports to its listener', () {
      FrameCompletion? heard;
      final frame = XrFrame(
        predictedDisplayTime: Duration.zero,
        views: const [],
        referenceSpaceType: XrReferenceSpaceType.local,
        onSubmit: (completion) => heard = completion,
      );
      final completion = FrameCompletion.skipped();
      frame.submit(completion);
      expect(heard, same(completion));
    });
  });

  group('composition layers', () {
    late _FakeBackend backend;
    late XrSession session;

    setUp(() async {
      backend = _FakeBackend(
        grantedSpaces: {
          XrReferenceSpaceType.localFloor,
          XrReferenceSpaceType.viewer,
        },
        layersSupported: true,
      );
      session = await WebXrRuntime(backend).requestSession(
        const XrSessionRequest(
          mode: XrSessionMode.immersiveVr,
          optionalFeatures: [XrFeatures.layers],
        ),
      );
    });

    test('are absent unless the feature was granted', () async {
      final plain = _FakeBackend(
        grantedSpaces: {XrReferenceSpaceType.localFloor},
      );
      final other = await WebXrRuntime(plain).requestSession(
        const XrSessionRequest(
          mode: XrSessionMode.immersiveVr,
          optionalFeatures: [XrFeatures.layers],
        ),
      );
      expect(other.layers, isNull);
      expect(plain.session!.createdLayers.single.projection, isFalse);
    });

    test('ride on a projection layer', () {
      expect(session.layers, isNotNull);
      expect(backend.session!.createdLayers.single.projection, isTrue);
    });

    test('a quad layer is created in the reference space and stacked', () {
      final fake = backend.session!;
      final quad = session.layers!.createQuadLayer(
        pixelWidth: 1024,
        pixelHeight: 512,
        width: 1.0,
        height: 0.5,
        pose: XrPose(position: Vector3(0, 1.4, -1.2)),
      );
      final created = fake.compositionLayers.single;
      expect(created.space.name, XrReferenceSpaceType.localFloor.name);
      expect(created.pose.position, Vector3(0, 1.4, -1.2));
      expect(created.shape, [1.0, 0.5]);
      expect((created.pixelWidth, created.pixelHeight), (1024, 512));
      expect(quad.needsRedraw, isTrue);
      expect(session.layers!.layers, [quad]);
      expect(fake.installedLayers.last, [fake.createdLayers.single, created]);
    });

    test('a head-locked cylinder sits in the viewer space', () {
      final fake = backend.session!;
      final cylinder = session.layers!.createCylinderLayer(
        pixelWidth: 2048,
        pixelHeight: 512,
        radius: 2.0,
        centralAngle: 1.2,
        aspectRatio: 4.0,
        space: XrLayerSpace.viewer,
      );
      final created = fake.compositionLayers.single;
      expect(created.space.name, XrReferenceSpaceType.viewer.name);
      expect(created.shape, [2.0, 1.2, 4.0]);
      expect(cylinder.space, XrLayerSpace.viewer);
    });

    test('a moved or resized layer is sent on once, after the frame', () {
      final fake = backend.session!;
      final quad = session.layers!.createQuadLayer(
        pixelWidth: 64,
        pixelHeight: 64,
        width: 1.0,
        height: 1.0,
      );
      final created = fake.compositionLayers.single;
      session.frames.listen((_) {});
      fake.tick(0, _stereo());
      expect(created.poseUpdates, 0);

      quad.pose.position.setValues(0.5, 1.0, -2.0);
      quad.width = 2.0;
      expect(created.poseUpdates, 0);
      fake.tick(16, _stereo());
      expect(created.poseUpdates, 1);
      expect(created.pose.position, Vector3(0.5, 1.0, -2.0));
      expect(created.shape, [2.0, 1.0]);

      fake.tick(32, _stereo());
      expect(created.poseUpdates, 1);
    });

    test('hiding and disposing restack the layers', () {
      final fake = backend.session!;
      final layers = session.layers!;
      final first = layers.createQuadLayer(
        pixelWidth: 64,
        pixelHeight: 64,
        width: 1.0,
        height: 1.0,
      );
      final second = layers.createQuadLayer(
        pixelWidth: 64,
        pixelHeight: 64,
        width: 1.0,
        height: 1.0,
      );
      final projection = fake.createdLayers.single;
      final [a, b] = fake.compositionLayers;
      expect(fake.installedLayers.last, [projection, a, b]);

      first.visible = false;
      expect(fake.installedLayers.last, [projection, b]);
      first.visible = true;
      expect(fake.installedLayers.last, [projection, a, b]);

      second.dispose();
      expect(b.destroyed, isTrue);
      expect(layers.layers, [first]);
      expect(fake.installedLayers.last, [projection, a]);
      expect(second.needsRedraw, isFalse);
    });

    test('an image is only on offer inside a frame', () {
      final fake = backend.session!;
      final quad = session.layers!.createQuadLayer(
        pixelWidth: 64,
        pixelHeight: 64,
        width: 1.0,
        height: 1.0,
      );
      final created = fake.compositionLayers.single;
      expect(quad.acquireTarget(), isNull);
      expect(created.subImageRequests, 0);

      Object? inFrame = 0;
      session.frames.listen((_) => inFrame = quad.acquireTarget());
      fake.tick(0, _stereo());
      // The browser was asked, and had no image yet.
      expect(created.subImageRequests, 1);
      expect(inFrame, isNull);

      quad.dispose();
      fake.tick(16, _stereo());
      expect(created.subImageRequests, 1);
    });

    test('a new render scale keeps the layers on the new projection', () {
      final fake = backend.session!;
      session.layers!.createQuadLayer(
        pixelWidth: 64,
        pixelHeight: 64,
        width: 1.0,
        height: 1.0,
      );
      final quad = fake.compositionLayers.single;
      session.renderScale = 0.5;
      fake.tick(0, _stereo());
      expect(fake.createdLayers, hasLength(2));
      expect(fake.createdLayers.last.projection, isTrue);
      expect(fake.installedLayers.last, [fake.createdLayers.last, quad]);
    });
  });
}
