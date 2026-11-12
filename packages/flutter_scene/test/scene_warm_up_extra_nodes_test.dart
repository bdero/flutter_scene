// Covers Scene.warmUp's extraNodes: their pipelines build during warm-up, a
// matching node added afterwards builds none, and they leave the scene before
// any visible frame. GPU-gated; warm-up renders frames.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

List<RenderView> _views() => [
  RenderView(camera: PerspectiveCamera(position: Vector3(0, 2, 5))),
];

Node _selectedCube() =>
    Node(mesh: Mesh(CuboidGeometry(Vector3.all(1)), PhysicallyBasedMaterial()))
      ..highlightColor = Vector4(1, 0.5, 0, 1);

RenderFrameStats _render(Scene scene) {
  final recorder = ui.PictureRecorder();
  try {
    scene.renderViews(
      _views(),
      ui.Canvas(recorder),
      region: const ui.Rect.fromLTWH(0, 0, 64, 64),
      pixelRatio: 1.0,
    );
  } finally {
    recorder.endRecording().dispose();
  }
  return scene.renderStats.latest!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!gpuAvailable()) {
    test(
      'warm-up extra nodes suite (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  // First in the file, so the process-wide pipeline cache has not seen a lit
  // cube yet.
  test('extra nodes build the pipelines a later node needs', () async {
    final scene = Scene();
    await scene.warmUp(_views());
    final emptySize = scene.renderStats.latest!.pipelineCacheSize;

    await scene.warmUp(_views(), extraNodes: [_selectedCube()]);
    expect(scene.renderStats.latest!.pipelineCacheSize, greaterThan(emptySize));

    scene.add(_selectedCube());
    final frame = _render(scene);
    expect(frame.counters.submitted, greaterThan(0));
    expect(frame.counters.pipelineBuilds, 0);
    scene.dispose();
  });

  test('extra nodes leave the scene before any visible frame', () async {
    final scene = Scene();
    final cube = _selectedCube();

    await scene.warmUp(
      _views(),
      extraNodes: [cube],
      sliceBudget: const Duration(milliseconds: 1),
    );

    expect(cube.parent, isNull);
    expect(scene.root.children, isEmpty);
    expect(_render(scene).counters.submitted, 0);
    scene.dispose();
  });
}
