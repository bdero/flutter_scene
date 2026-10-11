@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene_xr/flutter_scene_xr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/fake_frames.dart';
import 'support/gpu_available.dart';

/// A session whose frames a test pushes by hand.
final class _FakeSession implements XrSession {
  final StreamController<XrFrame> _frames = StreamController.broadcast(
    sync: true,
  );
  final Completer<XrSessionEndReason> _ended = Completer();

  void push(XrFrame frame) => _frames.add(frame);

  @override
  XrSessionMode get mode => XrSessionMode.immersiveVr;

  @override
  XrBlendMode get blendMode => XrBlendMode.opaque;

  @override
  XrReferenceSpaceType get referenceSpaceType =>
      XrReferenceSpaceType.localFloor;

  @override
  Set<String> get features => const {};

  @override
  Stream<XrFrame> get frames => _frames.stream;

  @override
  List<XrInputSourceState> get inputSources => const [];

  @override
  Stream<void> get inputSourcesChanged => const Stream.empty();

  @override
  XrHitTesting? get hitTest => null;

  @override
  XrAnchors? get anchors => null;

  @override
  XrPlaneDetection? get planes => null;

  @override
  XrDepthSensing? get depthSensing => null;

  @override
  XrLightEstimation? get lightEstimation => null;

  @override
  bool get isEnded => _ended.isCompleted;

  @override
  Future<XrSessionEndReason> get ended => _ended.future;

  @override
  Object? get error => null;

  @override
  Future<void> end() async {
    _ended.complete(XrSessionEndReason.ended);
    await _frames.close();
  }
}

Scene _scene() {
  final scene = Scene()..antiAliasingMode = AntiAliasingMode.none;
  scene.add(
    Node(
      mesh: Mesh(
        CuboidGeometry(Vector3(1, 1, 1)),
        PhysicallyBasedMaterial()..baseColorFactor = Vector4(0.8, 0.3, 0.2, 1),
      ),
      localTransform: Matrix4.translation(Vector3(0, 1.2, -2)),
    ),
  );
  scene.directionalLight = DirectionalLight(direction: Vector3(-0.5, -1, -0.3));
  return scene;
}

ExternalRenderTarget _target(int width, int height) =>
    ExternalRenderTarget.texture(
      gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        width,
        height,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  setUpAll(() async {
    if (noGpu != null) return;
    await Scene.initializeStaticResources();
    await Scene.preload();
  });

  test('renders the rig views once per frame into the frame target', () async {
    final scene = _scene();
    final rig = XrRig();
    scene.add(rig.origin);
    final session = _FakeSession();
    final target = _target(128, 64);
    final ticks = <double>[];
    final renderedViews = <List<RenderView>>[];
    final loop = XrSceneLoop(
      scene: scene,
      rig: rig,
      session: session,
      onTick: (frame, dt) => ticks.add(dt),
      onBeforeRender: (frame, views) => renderedViews.add(List.of(views)),
    )..start();

    session.push(
      stereoFrame(
        head: Vector3(0, 1.6, 0),
        target: target,
        time: const Duration(milliseconds: 1000),
      ),
    );
    session.push(
      stereoFrame(
        head: Vector3(0, 1.6, 0.1),
        target: target,
        time: const Duration(milliseconds: 1016),
      ),
    );

    expect(loop.framesRendered, 2);
    expect(ticks, [0.0, closeTo(0.016, 1e-9)]);
    expect(renderedViews, hasLength(2));
    for (final views in renderedViews) {
      expect(views, hasLength(2));
      expect(views.every((v) => identical(v.externalTarget, target)), isTrue);
    }
    expect(identical(renderedViews.last[0], rig.views[0]), isTrue);
    expect(loop.lastCompletion, isNotNull);
    expect(loop.lastCompletion!.skipped, isFalse);
    await loop.lastCompletion!.whenGpuDone;

    loop.stop();
    session.push(stereoFrame(head: Vector3.zero(), target: target));
    expect(loop.framesRendered, 2);
    await session.end();
  }, skip: noGpu);

  test('a frame without a target ticks the scene but renders nothing', () {
    final scene = _scene();
    final rig = XrRig();
    scene.add(rig.origin);
    final session = _FakeSession();
    var ticks = 0;
    final loop = XrSceneLoop(
      scene: scene,
      rig: rig,
      session: session,
      onTick: (frame, dt) => ticks++,
    )..start();
    session.push(stereoFrame(head: Vector3(0, 1.6, 0)));
    expect(ticks, 1);
    expect(loop.framesRendered, 0);
    expect(loop.lastCompletion!.skipped, isTrue);
  }, skip: noGpu);
}
