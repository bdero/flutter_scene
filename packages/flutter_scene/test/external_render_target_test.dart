@TestOn('vm')
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

import 'support/gpu_available.dart';

const int _w = 96;
const int _h = 64;

// A lit cube and a ground plane under a shadow-casting sun, so the frame
// exercises shadows, lighting, and the resolve, with no temporal history.
Scene _scene({bool shadows = true}) {
  final scene = Scene()..antiAliasingMode = AntiAliasingMode.none;
  scene.add(
    Node(
      mesh: Mesh(
        CuboidGeometry(Vector3(1, 1, 1)),
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(0.8, 0.3, 0.2, 1)
          ..roughnessFactor = 0.6,
      ),
    )..localTransform = Matrix4.translation(Vector3(0.3, 0.5, 0)),
  );
  scene.add(
    Node(
      mesh: Mesh(
        PlaneGeometry(width: 8, depth: 8),
        PhysicallyBasedMaterial()..baseColorFactor = Vector4(0.6, 0.6, 0.6, 1),
      ),
    ),
  );
  scene.directionalLight = DirectionalLight(
    direction: Vector3(-0.5, -1, -0.3),
    castsShadow: shadows,
  );
  return scene;
}

PerspectiveCamera _camera([double x = 0]) => PerspectiveCamera(
  position: Vector3(x, 1.5, 4),
  target: Vector3(x, 0.5, 0),
  fovNear: 0.1,
  fovFar: 50,
);

Future<Uint8List> _canvasPixels(Scene scene, List<RenderView> views) async {
  final recorder = ui.PictureRecorder();
  scene.renderViews(
    views,
    ui.Canvas(recorder),
    region: ui.Rect.fromLTWH(0, 0, _w.toDouble(), _h.toDouble()),
    pixelRatio: 1.0,
  );
  final image = await recorder.endRecording().toImage(_w, _h);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

Future<Uint8List> _texturePixels(gpu.Texture texture) async {
  final image = texture.asImage();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
}

gpu.Texture _target(int width, int height) => gpu.gpuContext.createTexture(
  gpu.StorageMode.devicePrivate,
  width,
  height,
  enableRenderTargetUsage: true,
  enableShaderReadUsage: true,
);

// Mean absolute channel difference between two RGBA buffers, and the share
// of pixels that differ by more than [threshold] in any channel.
({double mean, double fraction}) _diff(
  Uint8List a,
  Uint8List b, {
  int threshold = 8,
}) {
  expect(a.length, b.length);
  var sum = 0;
  var differing = 0;
  for (var i = 0; i < a.length; i += 4) {
    var worst = 0;
    for (var c = 0; c < 4; c++) {
      final d = (a[i + c] - b[i + c]).abs();
      sum += d;
      if (d > worst) worst = d;
    }
    if (worst > threshold) differing++;
  }
  return (mean: sum / a.length, fraction: differing / (a.length / 4));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final noGpu = gpuAvailable()
      ? null
      : 'Requires a GPU device: --enable-impeller --enable-flutter-gpu.';

  setUpAll(() async {
    if (noGpu != null) return;
    await Scene.initializeStaticResources();
    await Scene.preload();
  });

  test(
    'a view into an external texture matches the same view on a canvas',
    () async {
      final scene = _scene();
      final camera = _camera();
      final expected = await _canvasPixels(scene, [RenderView(camera: camera)]);

      final texture = _target(_w, _h);
      final frame = scene.renderViewsToTargets([
        RenderViewGroup([
          RenderView(
            camera: camera,
            externalTarget: ExternalRenderTarget.texture(texture),
          ),
        ]),
      ]);
      expect(frame.skipped, isFalse);
      await frame.whenGpuDone;
      final actual = await _texturePixels(texture);
      final diff = _diff(expected, actual);
      expect(diff.mean, lessThan(0.5), reason: 'mean channel difference');
      expect(
        diff.fraction,
        lessThan(0.002),
        reason: 'pixels off by more than 8',
      );
      // Something was drawn: the sky or ground is not the zero clear.
      expect(actual.any((v) => v != 0), isTrue);
    },
    skip: noGpu,
  );

  test(
    'two views sharing one target each equal that view rendered alone',
    () async {
      final scene = _scene();
      final left = _camera(-0.1);
      final right = _camera(0.1);
      final target = _target(_w * 2, _h);
      final shared = ExternalRenderTarget.texture(target);
      final frame = scene.renderViewsToTargets([
        RenderViewGroup([
          RenderView(
            camera: left,
            externalTarget: shared,
            viewport: const ui.Rect.fromLTWH(0, 0, 0.5, 1),
          ),
          RenderView(
            camera: right,
            externalTarget: shared,
            viewport: const ui.Rect.fromLTWH(0.5, 0, 0.5, 1),
          ),
        ]),
      ]);
      await frame.whenGpuDone;
      final pair = await _texturePixels(target);

      for (final (index, camera) in [left, right].indexed) {
        final alone = _target(_w, _h);
        final solo = scene.renderViewsToTargets([
          RenderViewGroup([
            RenderView(
              camera: camera,
              externalTarget: ExternalRenderTarget.texture(alone),
            ),
          ]),
        ]);
        await solo.whenGpuDone;
        final expected = await _texturePixels(alone);
        // Cut this eye's half out of the pair.
        final half = Uint8List(_w * _h * 4);
        for (var y = 0; y < _h; y++) {
          final src = (y * _w * 2 + index * _w) * 4;
          half.setRange(y * _w * 4, (y + 1) * _w * 4, pair, src);
        }
        final diff = _diff(expected, half);
        // The pair shares one cascade fit, so shadow texels land slightly
        // differently; the picture is otherwise the same.
        expect(diff.mean, lessThan(1.5), reason: 'eye $index mean difference');
        expect(diff.fraction, lessThan(0.03), reason: 'eye $index pixels off');
      }
    },
    skip: noGpu,
  );

  test('an off-axis symmetric lens renders like the perspective one', () async {
    final scene = _scene(shadows: false);
    final perspective = _camera();
    final expected = await _canvasPixels(scene, [
      RenderView(camera: perspective),
    ]);
    final offAxisNode = Node()
      ..addComponent(
        CameraComponent(
          projection: OffAxisProjection.symmetric(
            fovRadiansY: perspective.fovRadiansY,
            aspectRatio: _w / _h,
            near: perspective.fovNear,
            far: perspective.fovFar,
          ),
        ),
      );
    offAxisNode.localTransform = Matrix4.inverted(perspective.getViewMatrix());
    scene.add(offAxisNode);
    final camera = offAxisNode.getComponent<CameraComponent>()!.toCamera();
    final actual = await _canvasPixels(scene, [RenderView(camera: camera)]);
    final diff = _diff(expected, actual);
    expect(diff.mean, lessThan(0.5));
    expect(diff.fraction, lessThan(0.002));
  }, skip: noGpu);

  test('a frame with nothing ready reports skipped and completes', () async {
    final scene = _scene();
    final frame = scene.renderViewsToTargets(const []);
    expect(frame.skipped, isTrue);
    await frame.whenGpuDone;
  }, skip: noGpu);

  test('renderViewsToTargets rejects a view without a target', () {
    final scene = _scene();
    expect(
      () => scene.renderViewsToTargets([
        RenderViewGroup([RenderView(camera: _camera())]),
      ]),
      throwsArgumentError,
    );
  }, skip: noGpu);
}
