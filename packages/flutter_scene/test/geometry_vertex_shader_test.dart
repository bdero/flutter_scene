// A line segment, billboard or splat batch builds its vertices in the engine's
// own vertex shader, so a material's vertex shader must not replace it in any
// pass. A plain mesh still takes the material's vertex shader.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/geometry/splat_geometry.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/material/splat_material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

class _RecordingUnlit extends UnlitMaterial {
  final List<String> requested = [];

  @override
  gpu.Shader? materialVertexShader(String variant) {
    requested.add(variant);
    return null;
  }
}

class _RecordingSprite extends SpriteMaterial {
  final List<String> requested = [];

  @override
  gpu.Shader? materialVertexShader(String variant) {
    requested.add(variant);
    return null;
  }
}

class _RecordingSplat extends SplatMaterial {
  final List<String> requested = [];

  @override
  gpu.Shader? materialVertexShader(String variant) {
    requested.add(variant);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!gpuAvailable()) {
    test(
      'own vertex shader (skipped: no GPU device)',
      () {},
      skip: 'Requires a GPU device.',
    );
    return;
  }

  test('a geometry that builds its vertices asks no material', () async {
    await Scene.initializeStaticResources();

    final lines = _RecordingUnlit();
    final sprites = _RecordingSprite();
    final splats = _RecordingSplat();
    final mesh = _RecordingUnlit();

    final billboards = BillboardGeometry(capacity: 1)
      ..setInstance(0, center: Vector3.zero(), width: 1, height: 1)
      ..commit(1);

    final scene = Scene();
    scene.add(
      Node(
        mesh: Mesh(
          LineSegmentsGeometry(
            LineSegmentData(
              positions: Float32List.fromList([-1, 0, 0, 1, 0, 0]),
            ),
            width: 0.2,
          ),
          lines,
        ),
      ),
    );
    scene.add(Node(mesh: Mesh(billboards, sprites)));
    final splatGeometry = SplatGeometry(
      GaussianSplats.fromData(SplatData.zeroed(4)),
    );
    addTearDown(splatGeometry.disposeSorter);
    scene.add(Node(mesh: Mesh(splatGeometry, splats)));
    scene.add(Node(mesh: Mesh(CuboidGeometry(Vector3.all(0.5)), mesh)));

    final recorder = ui.PictureRecorder();
    scene.render(
      PerspectiveCamera(position: Vector3(0, 0, 5)),
      ui.Canvas(recorder),
      viewport: const ui.Rect.fromLTWH(0, 0, 32, 32),
      pixelRatio: 1.0,
    );
    recorder.endRecording();

    expect(mesh.requested, contains('unskinned'));
    expect(
      {
        'lines': lines.requested,
        'billboards': sprites.requested,
        'splats': splats.requested,
      },
      {'lines': isEmpty, 'billboards': isEmpty, 'splats': isEmpty},
    );
  });
}
