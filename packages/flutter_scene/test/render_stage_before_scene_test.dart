// Covers RenderStage.beforeScene: it runs before the view is drawn, it has no
// color chain, and the inputs it declares are not produced for it.

@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

// Records, for each pass that runs, its stage and what its context saw.
class _Probe extends CustomRenderPass {
  _Probe(this.stage, this.log, {this.inputs = const {}, this.drawMask = false});

  @override
  final RenderStage stage;

  @override
  final Set<RenderInput> inputs;

  final List<String> log;
  final bool drawMask;
  Object? currentColorError;
  gpu.Texture? mask;
  bool sawDepth = false;

  @override
  String get name => 'probe_${stage.name}';

  @override
  void execute(RenderPassContext context) {
    log.add(stage.name);
    sawDepth = context.sceneDepthLinear != null;
    if (drawMask) mask = context.drawObjects();
    if (stage == RenderStage.beforeScene) {
      try {
        context.currentColor;
      } catch (error) {
        currentColorError = error;
      }
    }
  }
}

void _render(Scene scene) {
  final recorder = ui.PictureRecorder();
  scene.render(
    PerspectiveCamera(position: Vector3(0, 0, -3)),
    ui.Canvas(recorder),
    viewport: const ui.Rect.fromLTWH(0, 0, 16, 16),
    pixelRatio: 1.0,
  );
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  setUpAll(() async {
    if (noGpu == null) await Scene.initializeStaticResources();
  });

  Scene sceneWithContent() => Scene()
    ..add(Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), UnlitMaterial())));

  test('beforeScene runs first and has no color chain', () {
    final log = <String>[];
    final scene = sceneWithContent();
    // Added out of order: the stage, not the add order, decides.
    final after = _Probe(RenderStage.afterScene, log);
    final before = _Probe(RenderStage.beforeScene, log);
    scene
      ..addRenderPass(after)
      ..addRenderPass(before);
    _render(scene);

    expect(log, ['beforeScene', 'afterScene']);
    expect(before.currentColorError, isA<StateError>());
  }, skip: noGpu);

  test('inputs a beforeScene pass declares are not produced', () {
    final log = <String>[];
    final scene = sceneWithContent();
    final before = _Probe(
      RenderStage.beforeScene,
      log,
      inputs: const {RenderInput.depth},
    );
    final after = _Probe(RenderStage.afterScene, log);
    scene
      ..addRenderPass(before)
      ..addRenderPass(after);
    _render(scene);

    expect(before.sawDepth, isFalse);
    // Nothing else asked for depth, so no prepass ran for the later pass
    // either.
    expect(after.sawDepth, isFalse);
  }, skip: noGpu);

  test('drawObjects works at beforeScene', () {
    final log = <String>[];
    final scene = sceneWithContent();
    final before = _Probe(RenderStage.beforeScene, log, drawMask: true);
    scene.addRenderPass(before);
    _render(scene);

    final mask = before.mask!;
    expect(mask.width, 16);
    expect(mask.height, 16);
  }, skip: noGpu);
}
