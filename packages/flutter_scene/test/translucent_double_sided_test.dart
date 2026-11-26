// A blended double-sided material must draw its back faces, and the near side
// of the mesh must lie over its far side whatever the triangle order.
@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

const _size = ui.Size(64, 64);

final _camera = PerspectiveCamera(
  position: Vector3.zero(),
  target: Vector3(0, 0, -1),
  up: Vector3(0, 1, 0),
);

// One quad across the view at [distance], counter-clockwise as the camera
// sees it when [facing] and clockwise otherwise.
List<double> _quad(double distance, {required bool facing}) {
  const h = 50.0;
  final z = -distance;
  final corners = [
    [-h, -h, z],
    [h, -h, z],
    [h, h, z],
    [-h, h, z],
  ];
  return [for (final corner in facing ? corners : corners.reversed) ...corner];
}

Node _glass(
  List<({double distance, bool facing, Vector4 color})> quads, {
  required bool doubleSided,
}) {
  final positions = <double>[];
  final colors = <double>[];
  final indices = <int>[];
  for (final quad in quads) {
    final first = positions.length ~/ 3;
    positions.addAll(_quad(quad.distance, facing: quad.facing));
    for (var corner = 0; corner < 4; corner++) {
      colors.addAll(quad.color.storage);
    }
    indices.addAll([first, first + 1, first + 2, first, first + 2, first + 3]);
  }
  return Node(
    mesh: Mesh(
      MeshGeometry.fromArrays(
        positions: Float32List.fromList(positions),
        colors: Float32List.fromList(colors),
        indices: indices,
      ),
      UnlitMaterial()
        ..baseColorFactor = Vector4(1, 1, 1, 0.5)
        ..alphaMode = AlphaMode.blend
        ..doubleSided = doubleSided,
    ),
  );
}

Future<List<int>> _centre(Node node) async {
  await Scene.initializeStaticResources();
  final scene = Scene()..add(node);
  final recorder = ui.PictureRecorder();
  scene.render(
    _camera,
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
  scene.dispose();
  final offset =
      ((_size.height ~/ 2) * _size.width.toInt() + _size.width ~/ 2) * 4;
  return [
    for (var channel = 0; channel < 3; channel++)
      bytes.getUint8(offset + channel),
  ];
}

final _red = Vector4(1, 0, 0, 1);
final _blue = Vector4(0, 0, 1, 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  test('a blended double-sided mesh draws a back face, and a single-sided '
      'one culls it', () async {
    final turnedAway = [(distance: 20.0, facing: false, color: _red)];
    final both = await _centre(_glass(turnedAway, doubleSided: true));
    final one = await _centre(_glass(turnedAway, doubleSided: false));

    expect(both[0], inInclusiveRange(60, 250), reason: 'back face at $both');
    expect(one[0], lessThan(10), reason: 'culled face at $one');
  }, skip: noGpu);

  test('a blended double-sided mesh draws its far side under its near side, '
      'whatever the triangle order', () async {
    final centre = await _centre(
      _glass([
        (distance: 10, facing: true, color: _red),
        (distance: 20, facing: false, color: _blue),
      ], doubleSided: true),
    );

    expect(centre[2], greaterThan(30), reason: 'far side at $centre');
    expect(
      centre[0],
      greaterThan(centre[2]),
      reason: 'near side over the far side at $centre',
    );
  }, skip: noGpu);
}
