// Covers Scene.dispose: the render targets every view holds become
// unreachable at the call, and the scene refuses to render afterwards.
// GPU-gated; rendering a frame needs a device.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

List<RenderView> _views() => [
  RenderView(
    camera: PerspectiveCamera(position: Vector3(0, 0, 5)),
    viewport: const ui.Rect.fromLTWH(0, 0, 0.5, 1),
  ),
  RenderView(
    camera: PerspectiveCamera(position: Vector3(0, 5, 5)),
    viewport: const ui.Rect.fromLTWH(0.5, 0, 0.5, 1),
  ),
];

Node _cube() =>
    Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial()));

Node _mirror(Material material) =>
    Node(mesh: Mesh(PlaneGeometry(width: 4, depth: 4), material))
      ..position = Vector3(0, -1, 0)
      ..addComponent(PlanarReflectorComponent());

void _renderViews(Scene scene) {
  final recorder = ui.PictureRecorder();
  try {
    scene.renderViews(
      _views(),
      ui.Canvas(recorder),
      region: const ui.Rect.fromLTWH(0, 0, 64, 32),
      pixelRatio: 1.0,
    );
  } finally {
    recorder.endRecording().dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!gpuAvailable()) {
    test(
      'scene dispose suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('dispose empties every view ring and transient pool', () async {
    await Scene.initializeStaticResources();
    expect(Scene.isReadyToRender, isTrue);
    final scene = Scene()..add(_cube());
    _renderViews(scene);
    _renderViews(scene);
    expect(scene.surface.debugHeldTextureCount, greaterThan(0));
    expect(scene.surface.lastSwapchainColorTexture(1), isNotNull);

    scene.dispose();

    expect(scene.isDisposed, isTrue);
    expect(scene.surface.debugHeldTextureCount, 0);
    expect(scene.surface.lastSwapchainColorTexture(), isNull);
    expect(scene.surface.lastSwapchainColorTexture(1), isNull);
  });

  test('a disposed scene throws a StateError on render', () async {
    await Scene.initializeStaticResources();
    expect(Scene.isReadyToRender, isTrue);
    final scene = Scene()..add(_cube());
    _renderViews(scene);
    scene.dispose();

    expect(() => _renderViews(scene), throwsStateError);
    final recorder = ui.PictureRecorder();
    expect(
      () => scene.render(
        PerspectiveCamera(),
        ui.Canvas(recorder),
        viewport: const ui.Rect.fromLTWH(0, 0, 16, 16),
      ),
      throwsStateError,
    );
    recorder.endRecording().dispose();
    expect(scene.surface.debugHeldTextureCount, 0);
  });

  test('dispose twice is a no-op, and a never-rendered scene disposes', () {
    final scene = Scene();
    scene.dispose();
    scene.dispose();
    expect(scene.isDisposed, isTrue);
    expect(scene.surface.debugHeldTextureCount, 0);
  });

  test('dispose drops every history target the scene holds', () async {
    await Scene.initializeStaticResources();
    final scene = Scene()
      ..antiAliasingMode = AntiAliasingMode.taa
      ..directionalLight = DirectionalLight(castsShadow: true)
      ..add(_cube()..shadowStatic = true)
      ..add(_mirror(_MirrorMaterial()))
      ..add(Node()..addComponent(PointLightComponent(PointLight())));
    scene.globalIllumination.enabled = true;
    scene.autoExposure.enabled = true;
    _renderViews(scene);
    _renderViews(scene);
    scene.captureEnvironment(position: Vector3(0, 1, 0), faceResolution: 16);
    expect(scene.debugHeldHistoryTargets, {
      'taa',
      'irradiance',
      'autoExposure',
      'shadowCache',
      'ssgi',
      'punctualLights',
      'probe',
      'planar',
    });

    scene.dispose();

    expect(scene.debugHeldHistoryTargets, isEmpty);
  });

  test('dispose clears the planar frame routed to a mirror material', () async {
    await Scene.initializeStaticResources();
    final material = _MirrorMaterial();
    final scene = Scene()..add(_mirror(material));
    _renderViews(scene);
    expect(material.planarReflectionFrame, isNotNull);

    scene.dispose();

    expect(material.planarReflectionFrame, isNull);
  });

  test('a bake stepper taken before dispose throws a StateError', () async {
    await Scene.initializeStaticResources();
    final scene = Scene()..add(_cube());
    scene.globalIllumination.resolution = Vector3.all(2);
    final stepper = scene.bakeIrradianceField(probesPerStep: 1);

    scene.dispose();

    expect(stepper.step, throwsStateError);
    expect(stepper.currentProbe, 0);
  });

  test('a warm-up in progress stops when the scene is disposed', () async {
    await Scene.initializeStaticResources();
    final scene = Scene()..add(_cube());
    final warmUp = scene.warmUp(
      _views(),
      sliceBudget: const Duration(milliseconds: 1),
    );

    scene.dispose();

    await expectLater(warmUp, completes);
    expect(scene.surface.debugHeldTextureCount, 0);
  });

  test('dispose fails a pending render graph capture', () async {
    final allowed = Scene.debugAllowRenderGraphCapture;
    Scene.debugAllowRenderGraphCapture = true;
    addTearDown(() => Scene.debugAllowRenderGraphCapture = allowed);
    final scene = Scene();
    final capture = scene.captureRenderGraph();

    scene.dispose();

    await expectLater(
      capture,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('disposed'),
        ),
      ),
    );
  });
}

class _MirrorMaterial extends UnlitMaterial {
  @override
  bool get usesPlanarReflection => true;
}
