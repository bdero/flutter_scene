@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fmat/fmat.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

// The source with `//` comments removed, so prose mentioning discard does not
// count.
String _code(String source) =>
    source.split('\n').map((line) => line.split('//').first).join('\n');

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

const _size = ui.Size(100, 100);

// Draws one mesh of two overlapping quads in [alphaMode]: the far quad comes
// first in the index order, so in the coverage color draw its fragments fail
// the equal depth test before the near quad's fragments shade.
Future<List<int>> _overlappingQuadsCentre(AlphaMode alphaMode) async {
  await Scene.initializeStaticResources();
  final scene = Scene();
  final positions = <double>[
    for (final z in const [1.0, -1.0]) ...[
      -1, -1, z, 1, -1, z, 1, 1, z, -1, 1, z, //
    ],
  ];
  scene.add(
    Node(
      mesh: Mesh(
        MeshGeometry.fromArrays(
          positions: Float32List.fromList(positions),
          indices: const [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7],
        ),
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(0.1, 0.8, 0.2, 1)
          ..alphaMode = alphaMode
          ..doubleSided = true,
      ),
    ),
  );
  final recorder = ui.PictureRecorder();
  scene.render(
    PerspectiveCamera(),
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
  final offset =
      ((_size.height ~/ 2) * _size.width.toInt() + _size.width ~/ 2) * 4;
  return [
    for (var channel = 0; channel < 4; channel++)
      bytes.getUint8(offset + channel),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = _gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  test('the opaque material shaders never discard', () {
    // A discard anywhere in a shader turns off early depth testing and
    // hidden-surface removal for its every draw on tiled GPUs; cutouts go
    // through the coverage pre-draw instead.
    for (final path in [
      'shaders/flutter_scene_standard.frag',
      'shaders/flutter_scene_unlit.frag',
    ]) {
      final code = _code(File(path).readAsStringSync());
      expect(code, isNot(contains('discard')), reason: path);
      expect(code, isNot(contains('ApplyLodFade')), reason: path);
    }
    const physical = 'assets/materials/physical_opaque.fmat';
    final compiled = compileFmat(
      File(physical).readAsStringSync(),
      fileName: physical,
    );
    expect(_code(compiled.glsl), isNot(contains('discard')));
  });

  test('the coverage pre-draw applies the cross-fade and the mask', () {
    final code = _code(
      File('shaders/flutter_scene_coverage.frag').readAsStringSync(),
    );
    expect(code, contains('ApplyLodFade(coverage_info.fade)'));
    expect(code, contains('ApplyDepthAlphaMask()'));
    final bundle =
        jsonDecode(File('shaders/base.shaderbundle.json').readAsStringSync())
            as Map<String, Object?>;
    expect(bundle['CoverageFragment'], {
      'type': 'fragment',
      'file': 'shaders/flutter_scene_coverage.frag',
    });
  });

  test('the built-in lit and unlit materials cross-fade', () {
    expect(PhysicallyBasedMaterial().lodCrossFades, isTrue);
    expect(UnlitMaterial().lodCrossFades, isTrue);
  });

  test('an alpha-masked material cuts out through its depth mask', () {
    final material = PhysicallyBasedMaterial();
    expect(material.depthAlphaMasked, isFalse);
    material.alphaMode = AlphaMode.mask;
    expect(material.depthAlphaMasked, isTrue);
  });

  test('an alpha-masked mesh whose far triangles come first in its index '
      'order draws its near triangles where they are kept, as the opaque '
      'mesh does', () async {
    final opaque = await _overlappingQuadsCentre(AlphaMode.opaque);
    final masked = await _overlappingQuadsCentre(AlphaMode.mask);
    expect(opaque[3], 255);
    for (var channel = 0; channel < 4; channel++) {
      expect(
        (masked[channel] - opaque[channel]).abs(),
        lessThanOrEqualTo(2),
        reason: 'masked $masked against opaque $opaque',
      );
    }
  }, skip: noGpu);
}
