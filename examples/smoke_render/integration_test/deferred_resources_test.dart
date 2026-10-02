// The physical material shaders load on first use. A material that starts
// needing them holds the scene's previous frame until they land, then the
// scene repaints with them.
//
// Not part of the smoke matrix. Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/deferred_resources_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

// ignore_for_file: invalid_use_of_internal_member

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/material/physical_material_variant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 256;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  double meanDifference(Uint8List a, Uint8List b) {
    var sum = 0;
    for (var i = 0; i < a.length; i++) {
      sum += (a[i] - b[i]).abs();
    }
    return sum / a.length;
  }

  testWidgets('a material holds the frame until its shaders land', (
    tester,
  ) async {
    final init = Stopwatch()..start();
    await Scene.initializeStaticResources();
    final initMs = init.elapsedMilliseconds;
    expect(physicalMaterialResourcesReady, isFalse);

    final scene = Scene();
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.8, 0.1, 0.1, 1)
      ..roughnessFactor = 0.7;
    scene.add(Node(mesh: Mesh(SphereGeometry(radius: 1.2), material)));
    final camera = PerspectiveCamera(
      position: vm.Vector3(0, 0, 4),
      target: vm.Vector3.zero(),
    );
    var repaints = 0;
    scene.repaintRequested.addListener(() => repaints++);

    // Renders synchronously, so the hold decision is made at this call.
    ui.Picture render() {
      final recorder = ui.PictureRecorder();
      const area = Rect.fromLTWH(0, 0, _size * 1.0, _size * 1.0);
      scene.render(
        camera,
        Canvas(recorder, area),
        viewport: area,
        pixelRatio: 1.0,
      );
      return recorder.endRecording();
    }

    Future<Uint8List> pixels(ui.Picture picture) async {
      final image = await picture.toImage(_size, _size);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }

    for (var i = 0; i < 3; i++) {
      await pixels(render());
    }
    final before = await pixels(render());

    final load = Stopwatch()..start();
    material
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.0;
    final pendingAtSet = physicalMaterialResourcesPending;
    final pendingLoad = physicalMaterialResourcesLoad;
    final heldPicture = render();
    final pendingAtRender = pendingAtSet && physicalMaterialResourcesPending;
    final repaintsBeforeLand = repaints;
    // A capture during the load must not throw.
    scene.captureEnvironment(position: vm.Vector3(0, 0, 3));
    final held = await pixels(heldPicture);
    await pendingLoad;
    await tester.pump();
    final loadMs = load.elapsedMilliseconds;
    final repaintsOnLand = repaints - repaintsBeforeLand;
    final after = await pixels(render());

    final heldDiff = meanDifference(before, held);
    final afterDiff = meanDifference(before, after);
    // ignore: avoid_print
    print(
      'DEFERRED initMs=$initMs bundleMs=$loadMs pendingAtRender='
      '$pendingAtRender heldDiff=$heldDiff afterDiff=$afterDiff '
      'repaintsOnLand=$repaintsOnLand',
    );
    expect(pendingAtRender, isTrue);
    expect(heldDiff, lessThan(0.01));
    expect(repaintsOnLand, 1);
    expect(physicalMaterialResourcesReady, isTrue);
    expect(afterDiff, greaterThan(0.5));
  });
}
