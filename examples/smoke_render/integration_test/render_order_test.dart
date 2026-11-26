// Material and node render orders deciding which overlapping translucent
// surface blends over which, against the depth sort they override.
//
// Not part of the smoke matrix. Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/render_order_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/fscene.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 64;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  UnlitMaterial translucent(vm.Vector4 color) => UnlitMaterial()
    ..baseColorFactor = color
    ..alphaMode = AlphaMode.blend
    ..doubleSided = true;

  // A 2 m quad facing the camera at depth [z].
  Node quad(UnlitMaterial material, double z) => Node(
    mesh: Mesh(
      MeshGeometry.fromArrays(
        positions: Float32List.fromList([
          -1,
          -1,
          z,
          1,
          -1,
          z,
          1,
          1,
          z,
          -1,
          1,
          z,
        ]),
        indices: const [0, 1, 2, 0, 2, 3],
      ),
      material,
    ),
  );

  // Renders [nodes] and returns the centre pixel's red and green.
  Future<(int, int)> centre(List<Node> nodes) async {
    await Scene.initializeStaticResources();
    final scene = Scene();
    for (final node in nodes) {
      scene.add(node);
    }
    final recorder = ui.PictureRecorder();
    scene.render(
      PerspectiveCamera(
        position: vm.Vector3(0, 0, 5),
        target: vm.Vector3.zero(),
      ),
      ui.Canvas(recorder),
      viewport: ui.Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble()),
      pixelRatio: 1.0,
    );
    final image = await recorder.endRecording().toImage(_size, _size);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    final offset = ((_size ~/ 2) * _size + _size ~/ 2) * 4;
    final pixel = (bytes.getUint8(offset), bytes.getUint8(offset + 1));
    // ignore: avoid_print
    print('render order probe: centre red ${pixel.$1} green ${pixel.$2}');
    return pixel;
  }

  // Whether red blended last, with a margin so a blank frame fails.
  Future<bool> redOnTop(List<Node> nodes) async {
    final (red, green) = await centre(nodes);
    expect(
      (red - green).abs(),
      greaterThan(40),
      reason: 'red $red green $green',
    );
    return red > green;
  }

  // Red sits behind green, so depth sorting alone blends green last.
  late UnlitMaterial redMaterial;
  late UnlitMaterial greenMaterial;
  late Node red;
  late Node green;
  setUp(() {
    redMaterial = translucent(vm.Vector4(1, 0, 0, 0.9));
    greenMaterial = translucent(vm.Vector4(0, 1, 0, 0.9));
    red = quad(redMaterial, -1);
    green = quad(greenMaterial, 1);
  });

  testWidgets('depth sorting blends the nearer surface last', (tester) async {
    expect(await redOnTop([red, green]), isFalse);
  });

  testWidgets('a lower material order draws first', (tester) async {
    greenMaterial.renderOrder = -1;
    expect(await redOnTop([red, green]), isTrue);
  });

  testWidgets('a lower node order draws first', (tester) async {
    green.renderOrder = -1;
    expect(await redOnTop([red, green]), isTrue);
  });

  testWidgets('the material order sorts ahead of the node order', (
    tester,
  ) async {
    // The node orders alone would keep green on top.
    red.renderOrder = -5;
    green.renderOrder = 5;
    greenMaterial.renderOrder = -1;
    expect(await redOnTop([red, green]), isTrue);
  });

  testWidgets('a material order from a document reaches the draw', (
    tester,
  ) async {
    final document = serializeScene(
      Node()..addAll([red, green..renderOrder = 0]),
    );
    for (final resource in document.resources.values) {
      if (resource is! MaterialResource) continue;
      final color = resource.properties['baseColor'];
      if (color is ColorValue && color.g > 0.5) {
        resource.properties['renderOrder'] = const DoubleValue(-1);
      }
    }
    expect(await redOnTop([realizeScene(document)]), isTrue);
  });
}
