// Covers Scene.depthPriming: when the scene pass reuses the prepass depth,
// and that doing so leaves the image unchanged. GPU-gated.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/scene_pass.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

const _size = ui.Size(64, 64);

// Overlapping planes in far-to-near order, each with its own material, so the
// color pass draws hidden fragments unless the prepass rejects them.
Scene _overlappingPlanes(AntiAliasingMode mode) {
  final scene = Scene()..antiAliasingMode = mode;
  final plane = PlaneGeometry(width: 4, depth: 4);
  for (var i = 0; i < 4; i++) {
    scene.add(
      Node(
          mesh: Mesh(
            plane,
            PhysicallyBasedMaterial()
              ..baseColorFactor = Vector4(0.2 * i, 0.8 - 0.2 * i, 0.3, 1),
          ),
        )
        ..localTransform =
            Matrix4.translation(Vector3(0.3 * i, 0, -1.0 - i * 0.5)) *
            Matrix4.rotationX(1.5707963),
    );
  }
  return scene;
}

// Renders [scene] and returns its pixels and how many scene passes primed.
Future<(Uint8List, int)> _render(Scene scene) async {
  final before = ScenePass.debugPrimedPassCount;
  final recorder = ui.PictureRecorder();
  scene.render(
    PerspectiveCamera(position: Vector3(0, 0, 3), target: Vector3(0, 0, -2)),
    ui.Canvas(recorder),
    viewport: ui.Offset.zero & _size,
    pixelRatio: 1.0,
  );
  final image = await recorder.endRecording().toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return (bytes.buffer.asUint8List(), ScenePass.debugPrimedPassCount - before);
}

void main() {
  if (!gpuAvailable()) {
    test('depth priming suite (skipped: no GPU device)', () {}, skip: true);
    return;
  }

  setUpAll(Scene.initializeStaticResources);

  test('a full-size prepass primes the scene pass', () async {
    final (_, primed) = await _render(_overlappingPlanes(AntiAliasingMode.taa));
    expect(primed, 1);
  });

  test('MSAA and the setting turn it off', () async {
    if (Scene.isAntiAliasingModeSupported(AntiAliasingMode.msaa)) {
      final msaa = _overlappingPlanes(AntiAliasingMode.msaa)
        ..ambientOcclusion.enabled = true;
      expect((await _render(msaa)).$2, 0);
    }
    final off = _overlappingPlanes(AntiAliasingMode.taa)..depthPriming = false;
    expect((await _render(off)).$2, 0);
  });

  test('priming leaves the image unchanged', () async {
    final primed = _overlappingPlanes(AntiAliasingMode.taa);
    final unprimed = _overlappingPlanes(AntiAliasingMode.taa)
      ..depthPriming = false;
    final (a, _) = await _render(primed);
    final (b, _) = await _render(unprimed);
    expect(a, b);
  });
}
