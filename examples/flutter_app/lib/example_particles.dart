// Particle emitter demo. The configuration types live under lib/src/particles
// (not yet part of the public barrel); a dev app may import them directly.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/components/particle_emitter_component.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart' as shape;
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_settings.dart';

/// CPU-simulated particle emitters over a dark skybox: an alpha smoke column, an
/// additive flame, an additive water fountain, and an additive spark burst
/// (velocity-stretched). The camera orbits to show the camera-facing billboards.
class ExampleParticles extends StatefulWidget {
  const ExampleParticles({super.key});

  @override
  ExampleParticlesState createState() => ExampleParticlesState();
}

class ExampleParticlesState extends State<ExampleParticles> {
  Scene scene = Scene();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Additive particles only survive the resolve over opaque content, so use a
    // dark gradient skybox as the backdrop.
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

    scene.add(_smoke(dot)..localTransform = _at(-6.0));
    scene.add(_fire(dot)..localTransform = _at(-2.0));
    scene.add(_fountain(dot)..localTransform = _at(2.0));
    scene.add(_sparks(dot)..localTransform = _at(6.0));

    if (mounted) setState(() => _ready = true);
  }

  static vm.Matrix4 _at(double x) =>
      vm.Matrix4.translation(vm.Vector3(x, -1.5, 0));

  // A rising alpha-blended smoke column: a slow upward cone, buoyant, swelling
  // and fading over life.
  Node _smoke(TextureSource dot) {
    final system = ParticleSystem(
      maxParticles: 400,
      shape: const shape.ConeShape(angle: 0.25, radius: 0.25),
      spawner: Spawner(rate: 30.0),
      lifetime: const UniformFloat(2.2, 3.2),
      startSpeed: const UniformFloat(0.6, 1.1),
      startSize: const UniformFloat(0.3, 0.5),
      startRotation: const UniformFloat(0.0, 6.283),
      startAngularVelocity: const UniformFloat(-0.6, 0.6),
      gravity: vm.Vector3(0, 0.25, 0), // buoyancy
      modules: [
        LinearDragModule(0.4),
        const RotationModule(),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.5),
              const ParticleKeyframe(1.0, 1.8),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(0.5, 0.5, 0.55, 0.0)),
              ColorStop(0.2, vm.Vector4(0.45, 0.45, 0.5, 0.5)),
              ColorStop(1.0, vm.Vector4(0.3, 0.3, 0.32, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 1,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.alpha;
    return _emitterNode(system, material);
  }

  // An additive flame: a narrow upward cone that rises, swells then shrinks, and
  // shifts yellow -> orange -> red as it fades.
  Node _fire(TextureSource dot) {
    final system = ParticleSystem(
      maxParticles: 600,
      shape: const shape.ConeShape(angle: 0.22, radius: 0.22),
      spawner: Spawner(rate: 140.0),
      lifetime: const UniformFloat(0.5, 1.0),
      startSpeed: const UniformFloat(1.2, 2.2),
      startSize: const UniformFloat(0.35, 0.6),
      gravity: vm.Vector3(0, 1.5, 0),
      modules: [
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.6),
              const ParticleKeyframe(0.3, 1.0),
              const ParticleKeyframe(1.0, 0.2),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(1.0, 0.9, 0.5, 0.0)),
              ColorStop(0.15, vm.Vector4(1.0, 0.8, 0.3, 1.0)),
              ColorStop(0.5, vm.Vector4(1.0, 0.35, 0.1, 0.8)),
              ColorStop(1.0, vm.Vector4(0.4, 0.05, 0.0, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 2,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    return _emitterNode(system, material);
  }

  // An additive water fountain: a fast tight cone under gravity, fading from
  // bright cyan to deep blue.
  Node _fountain(TextureSource dot) {
    final system = ParticleSystem(
      maxParticles: 500,
      shape: const shape.ConeShape(angle: 0.18, radius: 0.05),
      spawner: Spawner(rate: 90.0),
      lifetime: const UniformFloat(1.3, 1.8),
      startSpeed: const UniformFloat(4.2, 5.0),
      startSize: const UniformFloat(0.1, 0.16),
      gravity: vm.Vector3(0, -9.8, 0),
      modules: [
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(0.5, 0.8, 1.0, 1.0)),
              ColorStop(0.7, vm.Vector4(0.3, 0.6, 1.0, 0.9)),
              ColorStop(1.0, vm.Vector4(0.2, 0.4, 0.9, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 3,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    return _emitterNode(system, material);
  }

  // An additive spark burst: an explosion from a point every 1.4s, gravity plus
  // drag, short-lived, rendered as velocity-stretched streaks.
  Node _sparks(TextureSource dot) {
    final system = ParticleSystem(
      maxParticles: 800,
      shape: const shape.SphereShape(
        radius: 0.0,
      ), // random directions from a point
      spawner: Spawner(
        bursts: const [ParticleBurst(time: 0.4, count: 160, interval: 1.4)],
      ),
      lifetime: const UniformFloat(0.4, 0.95),
      startSpeed: const UniformFloat(3.0, 6.5),
      startSize: const UniformFloat(0.06, 0.12),
      gravity: vm.Vector3(0, -6.0, 0),
      modules: [
        LinearDragModule(0.8),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(1.0, 0.95, 0.7, 1.0)),
              ColorStop(0.4, vm.Vector4(1.0, 0.6, 0.2, 1.0)),
              ColorStop(1.0, vm.Vector4(0.6, 0.1, 0.0, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 4,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    return _emitterNode(
      system,
      material,
      facing: BillboardFacing.velocityStretched,
      velocityStretch: 0.08,
    );
  }

  Node _emitterNode(
    ParticleSystem system,
    SpriteMaterial material, {
    BillboardFacing facing = BillboardFacing.spherical,
    double velocityStretch = 0.0,
  }) {
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = facing
      ..velocityStretch = velocityStretch;
    return Node()..addComponent(emitter);
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
          position: vm.Vector3(sin(t * 0.2) * 14, 3.0, cos(t * 0.2) * 14),
          target: vm.Vector3(0, 0.5, 0),
        );
      },
      onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
    );
  }
}

/// Builds a 128x128 soft white dot with a Gaussian alpha falloff from exact raw
/// pixels (smooth everywhere, slope -> 0 at the rim).
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
