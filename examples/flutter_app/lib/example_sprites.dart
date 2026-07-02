import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// Phase 0 billboard/sprite primitive demo over a dark skybox: overlapping
/// alpha sprites (left), an additive pulsing cloud (center), and additive
/// velocity-stretched streaks (right). The camera orbits to show camera-facing.
class ExampleSprites extends StatefulWidget {
  const ExampleSprites({super.key});

  @override
  ExampleSpritesState createState() => ExampleSpritesState();
}

/// Pulses the additive cloud's per-instance size and color over time.
class _CloudAnimator extends Component {
  _CloudAnimator(this.geometry, this.centers, this.hues);

  final BillboardGeometry geometry;
  final List<vm.Vector3> centers;
  final List<double> hues;
  double _t = 0;

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    for (var i = 0; i < centers.length; i++) {
      final pulse = 0.5 + 0.5 * sin(_t * 2 + hues[i] * 6.28318);
      final color = _hsv(hues[i], 0.9, 1.0)..scale(0.4 + 0.6 * pulse);
      geometry.setInstance(
        i,
        center: centers[i],
        width: 0.3 + 0.2 * pulse,
        height: 0.3 + 0.2 * pulse,
        color: color,
      );
    }
    geometry.commit(centers.length);
  }
}

/// Streams velocity-stretched streaks upward, recycling them so the stretch
/// reads as motion.
class _StreakAnimator extends Component {
  _StreakAnimator(this.geometry, this.count);

  final BillboardGeometry geometry;
  final int count;
  late final List<double> _y = List.generate(
    count,
    (i) => -2.0 + 4.0 * (i / count),
  );
  late final List<double> _x = List.generate(count, (i) => (i % 5 - 2) * 0.3);
  late final List<double> _speed = List.generate(count, (i) => 2.5 + i % 4);

  @override
  void update(double deltaSeconds) {
    for (var i = 0; i < count; i++) {
      _y[i] += _speed[i] * deltaSeconds;
      if (_y[i] > 2.5) _y[i] -= 5.0;
      geometry.setInstance(
        i,
        center: vm.Vector3(_x[i], _y[i], 0),
        width: 0.1,
        height: 0.1,
        color: vm.Vector4(1.0, 0.85, 0.4, 1.0),
        velocity: vm.Vector3(0, _speed[i], 0),
      );
    }
    geometry.commit(count);
  }
}

class ExampleSpritesState extends State<ExampleSprites> {
  Scene scene = Scene();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Opaque dark background so additive sprites have something to brighten.
    scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.01, 0.01, 0.03),
        horizonColor: vm.Vector3(0.04, 0.04, 0.07),
        groundColor: vm.Vector3(0.01, 0.01, 0.02),
        sunColor: vm.Vector3(0.1, 0.1, 0.12),
      ),
    );

    final dot = GpuTextureSource(
      await gpuTextureFromImage(await _softDotImage()),
    );

    // Left: three overlapping alpha sprites at different depths.
    final colors = [
      vm.Vector4(1.0, 0.3, 0.3, 0.85),
      vm.Vector4(0.3, 1.0, 0.4, 0.85),
      vm.Vector4(0.4, 0.5, 1.0, 0.85),
    ];
    for (var i = 0; i < 3; i++) {
      final sprite = Sprite(texture: dot, width: 2.0, height: 2.0)
        ..color = colors[i];
      scene.add(
        Node(mesh: sprite.mesh)
          ..localTransform = vm.Matrix4.translation(
            vm.Vector3(-3.5, (i - 1) * 0.6, (i - 1) * 0.9),
          ),
      );
    }

    // Center: an additive pulsing cloud.
    final rng = Random(7);
    final centers = <vm.Vector3>[];
    final hues = <double>[];
    for (var i = 0; i < 300; i++) {
      final r = 1.5 * pow(rng.nextDouble(), 1 / 3);
      final theta = rng.nextDouble() * 2 * pi;
      final z = rng.nextDouble() * 2 - 1;
      final ring = sqrt(1 - z * z);
      centers.add(
        vm.Vector3(r * ring * cos(theta), r * z, r * ring * sin(theta)),
      );
      hues.add(rng.nextDouble());
    }
    final cloud = BillboardGeometry(capacity: centers.length);
    final cloudMat = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    scene.add(
      Node(mesh: Mesh(cloud, cloudMat))
        ..addComponent(_CloudAnimator(cloud, centers, hues)),
    );

    // Right: additive velocity-stretched streaks.
    const streakCount = 20;
    final streaks = BillboardGeometry(capacity: streakCount)
      ..facing = BillboardFacing.velocityStretched
      ..velocityStretch = 0.25;
    final streakMat = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    scene.add(
      Node(mesh: Mesh(streaks, streakMat))
        ..localTransform = vm.Matrix4.translation(vm.Vector3(3.5, 0, 0))
        ..addComponent(_StreakAnimator(streaks, streakCount)),
    );

    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF050507),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SceneView(
      scene,
      cameraBuilder: (elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        return PerspectiveCamera(
          position: vm.Vector3(sin(t * 0.3) * 8, 2.5, cos(t * 0.3) * 8),
          target: vm.Vector3(0, 0, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

/// Builds a 128x128 soft white dot with a Gaussian alpha falloff (smooth
/// everywhere, slope -> 0 at the rim) from exact raw pixels.
Future<ui.Image> _softDotImage() {
  const size = 128;
  final pixels = Uint8List(size * size * 4);
  const half = size / 2;
  const sigma = size * 0.22;
  final rim = _gauss(half, sigma);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final r = _hypot(x + 0.5 - half, y + 0.5 - half);
      final a = ((_gauss(r, sigma) - rim) / (1.0 - rim)).clamp(0.0, 1.0);
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = (a * 255).round();
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

double _gauss(double r, double sigma) {
  final x = r / sigma;
  return exp(-0.5 * x * x);
}

double _hypot(double a, double b) => sqrt(a * a + b * b);

/// A simple linear-RGBA color from hue/saturation/value, for the demo cloud.
vm.Vector4 _hsv(double h, double s, double v) {
  final i = (h * 6).floor() % 6;
  final f = h * 6 - (h * 6).floorToDouble();
  final p = v * (1 - s);
  final q = v * (1 - f * s);
  final t = v * (1 - (1 - f) * s);
  final (double r, double g, double b) = switch (i) {
    0 => (v, t, p),
    1 => (q, v, p),
    2 => (p, v, t),
    3 => (p, q, v),
    4 => (t, p, v),
    _ => (v, p, q),
  };
  return vm.Vector4(r, g, b, 1.0);
}
