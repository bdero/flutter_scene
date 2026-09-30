// Spot shadow tiles do not depend on the camera, so a frame with several
// views renders them once and the later views reuse them; directional
// cascades fit each view, so a frame with them renders per view.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

Scene _scene({required bool sun, MeshDrawSelector? selector}) {
  final mesh = Mesh(CuboidGeometry(Vector3.all(1)), PhysicallyBasedMaterial());
  mesh.primitives.first.drawSelector = selector;
  final scene = Scene()
    ..add(Node(name: 'box', mesh: mesh))
    ..add(
      Node(name: 'spot', localTransform: Matrix4.translation(Vector3(0, 4, 0)))
        ..addComponent(
          SpotLightComponent(
            SpotLight(direction: Vector3(0, -1, 0), castsShadow: true),
          ),
        ),
    );
  if (sun) {
    scene.directionalLight = DirectionalLight(castsShadow: true);
  }
  final target = RenderTexture(
    width: 32,
    height: 32,
    update: RenderTextureUpdate.manual,
  );
  scene.views.add(
    RenderView(
      camera: PerspectiveCamera(position: Vector3(3, 2, 3)),
      target: target,
    ),
  );
  target.requestUpdate();
  return scene;
}

/// Shadow draws per rendered view, texture views first.
List<int> _shadowDraws(Scene scene) {
  final recorder = ui.PictureRecorder();
  scene.render(
    PerspectiveCamera(position: Vector3(0, 2, 5)),
    ui.Canvas(recorder),
    viewport: const ui.Rect.fromLTWH(0, 0, 64, 64),
    pixelRatio: 1.0,
  );
  recorder.endRecording();
  return [
    for (final view in scene.renderStats.latest!.views)
      for (final pass in view.passes)
        if (pass.name == 'ShadowPass') pass.counters.draws,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('views in one frame share spot shadow tiles', () async {
    if (!_gpuAvailable()) return;
    await Scene.initializeStaticResources();
    final draws = _shadowDraws(_scene(sun: false));
    expect(draws, hasLength(2));
    expect(draws.first, greaterThan(0));
    expect(draws.last, 0);
  });

  test('views with directional cascades render their own', () async {
    if (!_gpuAvailable()) return;
    await Scene.initializeStaticResources();
    final draws = _shadowDraws(_scene(sun: true));
    expect(draws, hasLength(2));
    expect(draws.every((d) => d > 0), isTrue);
  });

  test('a caster whose draw depends on the camera renders per view', () async {
    if (!_gpuAvailable()) return;
    await Scene.initializeStaticResources();
    final draws = _shadowDraws(
      _scene(sun: false, selector: (context) => MeshDrawSelection.all),
    );
    expect(draws, hasLength(2));
    expect(draws.every((d) => d > 0), isTrue);
  });
}
