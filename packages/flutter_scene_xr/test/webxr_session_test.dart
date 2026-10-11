import 'dart:math' as math;

import 'package:flutter_scene/gpu.dart' as gpu show ExternalTargetHandleKind;
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_backend.dart';
import 'package:flutter_scene_xr/src/webxr/webxr_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// A browser in miniature: one session at a time, reference spaces granted
// from a list, frames pushed by the test.
final class _FakeBackend implements WebXrBackend {
  _FakeBackend({this.supported = true, this.grantedSpaces = const {}});

  final bool supported;
  final Set<XrReferenceSpaceType> grantedSpaces;
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
  bool get projectionLayersSupported => false;

  @override
  WebXrBackendLayer createBaseLayer() {
    createdBaseLayer = true;
    return _FakeLayer();
  }

  @override
  WebXrBackendLayer createProjectionLayer() => throw UnimplementedError();

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
  @override
  bool get presents => false;

  @override
  void present(Object image) => throw UnsupportedError('fake layer');

  @override
  WebXrViewTarget viewTarget(WebXrBackendView view) {
    final left = view.eye == XrEye.left;
    return WebXrViewTarget(
      handle: null,
      kind: gpu.ExternalTargetHandleKind.framebuffer,
      width: 2000,
      height: 1000,
      x: left ? 0 : 1000,
      y: 0,
      viewportWidth: 1000,
      viewportHeight: 1000,
    );
  }
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
}
