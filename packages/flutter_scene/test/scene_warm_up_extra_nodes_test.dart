// Covers Scene.warmUp's extraNodes: their pipelines build during warm-up, a
// matching node added afterwards builds none, and they leave the scene before
// any visible frame. GPU-gated; warm-up renders frames.

import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene.dart' show resolveWarmUpRegion;
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

  test(
    'resolveWarmUpRegion preserves aspect ratio within 16..128 and defaults to 64x64 when cold',
    () {
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: 0, lastSwapchainHeight: 0),
        const ui.Rect.fromLTWH(0, 0, 64, 64),
      );
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: -10, lastSwapchainHeight: 480),
        const ui.Rect.fromLTWH(0, 0, 64, 64),
      );
      // Landscape (4:3 -> 64x48) and portrait (3:4 -> 64x85).
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: 1280, lastSwapchainHeight: 960),
        const ui.Rect.fromLTWH(0, 0, 64, 48),
      );
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: 960, lastSwapchainHeight: 1280),
        const ui.Rect.fromLTWH(0, 0, 64, 85),
      );
      // Extreme aspect ratios clamp height to [16, 128].
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: 1000, lastSwapchainHeight: 100),
        const ui.Rect.fromLTWH(0, 0, 64, 16),
      );
      expect(
        resolveWarmUpRegion(lastSwapchainWidth: 100, lastSwapchainHeight: 1000),
        const ui.Rect.fromLTWH(0, 0, 64, 128),
      );
    },
  );

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

  test(
    'warmUp uses an isolated scratch surface without evicting two-slot live surface pools',
    () async {
      final scene = Scene();
      const sizeA = ui.Size(320, 180);
      const sizeB = ui.Size(400, 225);
      final ringA = {
        scene.surface.getNextSwapchainColorTexture(sizeA),
        scene.surface.getNextSwapchainColorTexture(sizeA),
      };
      final poolA = scene.surface.transientTexturePool();
      scene.surface.getNextSwapchainColorTexture(sizeB);

      await scene.warmUp(
        _views(),
        extraNodes: [_selectedCube()],
        sliceBudget: const Duration(milliseconds: 2),
      );

      // Neither sizeA nor sizeB was evicted by warmUp's miniature pass.
      final ringAAfter = {
        scene.surface.getNextSwapchainColorTexture(sizeA),
        scene.surface.getNextSwapchainColorTexture(sizeA),
      };
      expect(ringAAfter, ringA);
      expect(identical(scene.surface.transientTexturePool(), poolA), isTrue);
      scene.dispose();
    },
  );
}
