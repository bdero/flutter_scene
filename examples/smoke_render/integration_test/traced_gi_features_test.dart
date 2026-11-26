// Checks what the traced irradiance feed sees beyond plain emissive walls:
// emissive textures, punctual lights, and skinned meshes, each against a
// frame without it. Saves each frame and traced_gi_features.json to
// build/smoke/.
//
// Not part of the smoke matrix. Needs compute (Flutter 3.53 or newer on Metal
// or Vulkan, or WebGPU). Run on macOS:
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/traced_gi_features_test.dart \
//     -d macos --enable-impeller --enable-flutter-gpu

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/compute_skinning.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/render/frame_transients.dart'
    show rendererSubmissions;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/gi_scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smoke_render/smoke_scenes.dart';
import 'package:vector_math/vector_math.dart' as vm;

const _size = 384.0;
const _frames = 60;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the traced feed sees textures, lights, and skins', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.expand());
    await tester.pump();
    await tester.runAsync(() => Scene.preload(smaa: true, compute: true));
    final report = <String, Object?>{'compute': gpu.supportsCompute};
    final captures = <String, String>{};
    void finish() {
      binding.reportData = {
        ...captures,
        'traced_gi_features.json': base64Encode(
          utf8.encode(jsonEncode(report)),
        ),
      };
      // ignore: avoid_print
      print('traced gi features: ${jsonEncode(report)}');
    }

    if (!gpu.supportsCompute) {
      finish();
      return;
    }
    await tester.runAsync(ComputeSkinning.instance.debugWaitUntilReady);

    Future<_Measure> render(
      String name,
      ({Scene scene, Camera camera}) setup, {
      required bool gi,
    }) async {
      final scene = setup.scene
        ..globalIllumination.enabled = gi
        ..globalIllumination.feed = IrradianceFeed.rayTraced;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: _size,
                height: _size,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _Painter(scene, setup.camera),
                ),
              ),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      for (var i = 0; i < _frames; i++) {
        boundary.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
        await _settleGpu(tester);
      }
      final stats = GiScene.debugLastFrame;
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1.0),
      ))!;
      final rgba = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      final png = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      captures['traced_gi_$name.png'] = base64Encode(png.buffer.asUint8List());
      scene.dispose();
      final measure = _Measure(rgba, image.width, image.height, stats);
      report[name] = measure.toJson();
      return measure;
    }

    final room = kSmokeScenes.firstWhere((s) => s.id == 'irradiance_field');

    // An emissive texture: the red wall emits white through a green texture,
    // so its bleed turns green.
    final plain = await render('walls', room.setup(), gi: true);
    final textured = room.setup();
    final green = _solidTexture(0, 255, 0);
    for (final material in _materials(textured.scene.root)) {
      if (material is PhysicallyBasedMaterial &&
          material.emissiveFactor.x > 10) {
        material
          ..emissiveFactor = vm.Vector4(14, 14, 14, 1)
          ..emissiveTexture = GpuTextureSource(green);
      }
    }
    final texturedMeasure = await render(
      'emissive_texture',
      textured,
      gi: true,
    );

    // A point light alone, so the only bounce is the one its traced light
    // makes.
    final lightOff = await render(
      'light_off',
      _whiteRoom(light: true),
      gi: false,
    );
    final lightTraced = await render(
      'light_traced',
      _whiteRoom(light: true),
      gi: true,
    );

    // A skinned character that only emits, off to one side, so its color
    // reaches the room only through the trace.
    Future<({Scene scene, Camera camera})> skinnedRoom() async {
      final setup = _whiteRoom(light: false);
      final model = (await tester.runAsync(
        () => Node.fromGlbAsset('assets_src/dash.glb'),
      ))!;
      for (final primitive in _primitives(model)) {
        primitive.material = UnlitMaterial()
          ..baseColorFactor = vm.Vector4(0.2, 0.4, 6.0, 1);
      }
      setup.scene.add(
        Node()
          ..localTransform = vm.Matrix4.compose(
            vm.Vector3(-1.0, 0.0, 0.6),
            vm.Quaternion.identity(),
            vm.Vector3.all(0.6),
          )
          ..add(model),
      );
      return setup;
    }

    final skinOff = await render('skinned_off', await skinnedRoom(), gi: false);
    final skinTraced = await render(
      'skinned_traced',
      await skinnedRoom(),
      gi: true,
    );
    finish();

    expect(texturedMeasure.stats?.textures, greaterThanOrEqualTo(1));
    expect(
      texturedMeasure.bleed,
      lessThan(plain.bleed - 20),
      reason: 'the textured wall bleeds green, not red',
    );
    expect(
      lightTraced.luminance,
      greaterThan(lightOff.luminance + 5),
      reason: 'the point light bounces',
    );
    expect(skinTraced.stats?.skinned, greaterThan(0));
    expect(
      skinTraced.blueness,
      greaterThan(skinOff.blueness + 5),
      reason: 'the skinned emitter tints the room',
    );
  });
}

// A closed white room lit by a dim environment, optionally a point light.
({Scene scene, Camera camera}) _whiteRoom({required bool light}) {
  final scene = Scene()
    ..environmentIntensity = 0.02
    ..exposure = 1.3;
  scene.globalIllumination
    ..volumeMode = IrradianceVolumeMode.fitScene
    ..resolution = vm.Vector3(10, 6, 10)
    ..hysteresis = 0.85
    ..visibility = 0.5;
  final white = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.85, 1)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.95;
  void box(vm.Vector3 size, vm.Vector3 at) => scene.add(
    Node(mesh: Mesh(CuboidGeometry(size), white))
      ..localTransform = vm.Matrix4.translation(at),
  );
  box(vm.Vector3(3.4, 0.3, 3.4), vm.Vector3(0, -0.15, 0));
  box(vm.Vector3(3.6, 2.0, 0.3), vm.Vector3(0, 1.0, -1.65));
  box(vm.Vector3(0.3, 2.0, 3.2), vm.Vector3(-1.65, 1.0, 0.1));
  box(vm.Vector3(0.3, 2.0, 3.2), vm.Vector3(1.65, 1.0, 0.1));
  box(vm.Vector3(3.6, 0.3, 3.4), vm.Vector3(0, 2.15, 0));
  if (light) {
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(1.0, 1.4, -0.8))
        ..addComponent(
          PointLightComponent(
            PointLight(
              color: vm.Vector3(1.0, 0.3, 0.2),
              intensity: 6.0,
              range: 8.0,
            ),
          ),
        ),
    );
  }
  return (
    scene: scene,
    camera: PerspectiveCamera(
      position: vm.Vector3(0, 1.1, 4.4),
      target: vm.Vector3(0, 0.9, 0),
    ),
  );
}

gpu.Texture _solidTexture(int r, int g, int b) {
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    4,
    4,
  );
  final bytes = Uint8List(4 * 4 * 4);
  for (var i = 0; i < 16; i++) {
    bytes
      ..[i * 4] = r
      ..[i * 4 + 1] = g
      ..[i * 4 + 2] = b
      ..[i * 4 + 3] = 255;
  }
  texture.overwrite(ByteData.sublistView(bytes));
  return texture;
}

Iterable<MeshPrimitive> _primitives(Node node) sync* {
  final mesh = node.mesh;
  if (mesh != null) yield* mesh.primitives;
  for (final child in node.children) {
    yield* _primitives(child);
  }
}

Iterable<Material> _materials(Node node) =>
    _primitives(node).map((p) => p.material);

class _Measure {
  _Measure(Uint8List rgba, int width, int height, this.stats) {
    List<double> mean(int x0, int x1, int y0, int y1) {
      final sum = [0.0, 0.0, 0.0];
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final p = (y * width + x) * 4;
          for (var c = 0; c < 3; c++) {
            sum[c] += rgba[p + c];
          }
          count++;
        }
      }
      return [for (final s in sum) s / count];
    }

    left = mean(width * 3 ~/ 10, width ~/ 2, height * 2 ~/ 5, height * 4 ~/ 5);
    right = mean(width ~/ 2, width * 7 ~/ 10, height * 2 ~/ 5, height * 4 ~/ 5);
    final all = mean(width ~/ 5, width * 4 ~/ 5, height ~/ 5, height * 4 ~/ 5);
    luminance = 0.2126 * all[0] + 0.7152 * all[1] + 0.0722 * all[2];
    blueness = all[2] - all[0];
  }

  late final List<double> left;
  late final List<double> right;
  late final double luminance;
  late final double blueness;
  final ({int bounded, int skinned, int materials, int textures})? stats;

  // Positive when the right half leans red against green more than the left.
  double get bleed => (right[0] - right[1]) - (left[0] - left[1]);

  Map<String, Object?> toJson() => {
    'left': left,
    'right': right,
    'bleed': bleed,
    'luminance': luminance,
    'blueness': blueness,
    if (stats case final stats?)
      'traced': {
        'bounded': stats.bounded,
        'skinned': stats.skinned,
        'materials': stats.materials,
        'textures': stats.textures,
      },
  };
}

class _Painter extends CustomPainter {
  _Painter(this.scene, this.camera);
  final Scene scene;
  final Camera camera;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(camera, canvas, viewport: Offset.zero & size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Future<void> _settleGpu(WidgetTester tester) => tester.runAsync(() async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (rendererSubmissions.framesInFlight > 0 &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
});
