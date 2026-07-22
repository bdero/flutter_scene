// Stylized explosion demo. The particle configuration types live under
// lib/src/particles (not yet part of the public barrel); a dev app may
// import them directly.
// ignore_for_file: implementation_imports

import 'dart:math';

import 'package:flutter/material.dart' hide Material;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene/src/components/mesh_particle_emitter_component.dart';
import 'package:flutter_scene/src/components/particle_emitter_component.dart';
import 'package:flutter_scene/src/components/trail_component.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart' as shape;
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';
import 'vfx_textures.dart';

/// A repeating stylized explosion built from every particle renderer at
/// once: a flipbook fireball, velocity-stretched sparks, soft smoke, an
/// expanding unlit shockwave ring, tumbling instanced mesh debris, and hero
/// chunks that arc away with additive ribbon trails. A panel detonates it on
/// demand and tunes the cycle.
class ExampleExplosion extends StatefulWidget {
  const ExampleExplosion({super.key});

  @override
  ExampleExplosionState createState() => ExampleExplosionState();
}

/// One hero debris chunk: launched ballistically on each detonation, spinning
/// as it flies, dragging an additive trail. Lands, rests briefly, then hides.
class _HeroChunk extends Component {
  _HeroChunk(this.trail, this.seed);

  final TrailComponent trail;
  final int seed;
  final vm.Vector3 _velocity = vm.Vector3.zero();
  final vm.Vector3 _position = vm.Vector3.zero();
  double _spin = 0;
  double _sinceBoom = double.infinity;
  bool _flying = false;

  void boom(Random rng) {
    final angle = rng.nextDouble() * 2 * pi;
    final tilt = 0.15 + rng.nextDouble() * 0.5;
    final speed = 6.0 + rng.nextDouble() * 4.5;
    _velocity.setValues(
      sin(tilt) * cos(angle) * speed,
      cos(tilt) * speed,
      sin(tilt) * sin(angle) * speed,
    );
    _position.setValues(0, 0.5, 0);
    _spin = (rng.nextDouble() - 0.5) * 24.0;
    _sinceBoom = 0;
    _flying = true;
    node.visible = true;
    trail.clear();
    trail.emitting = true;
  }

  @override
  void update(double deltaSeconds) {
    _sinceBoom += deltaSeconds;
    if (_flying) {
      _velocity.y -= 9.8 * deltaSeconds;
      _position.addScaled(_velocity, deltaSeconds);
      if (_position.y < 0.07) {
        _position.y = 0.07;
        _flying = false;
        trail.emitting = false;
      }
    } else if (_sinceBoom > 2.4 && node.visible) {
      node.visible = false;
    }
    node.localTransform = vm.Matrix4.translation(_position)
      ..multiply(vm.Matrix4.rotationZ(_spin * min(_sinceBoom, 1.2)))
      ..multiply(vm.Matrix4.rotationX(_spin * 0.6 * min(_sinceBoom, 1.2)));
  }
}

/// Runs the explosion cycle: resets the one-shot particle systems, launches
/// the hero chunks, sweeps the shockwave ring, and pulses the light.
class _ExplosionDirector extends Component {
  _ExplosionDirector({
    required this.systems,
    required this.chunks,
    required this.shockwaveNode,
    required this.shockwaveMaterial,
    required this.light,
  });

  final List<ParticleSystem> systems;
  final List<_HeroChunk> chunks;
  final Node shockwaveNode;
  final UnlitMaterial shockwaveMaterial;
  final PointLight light;

  bool auto = true;
  double interval = 3.5;
  final Random _rng = Random(11);
  double _sinceBoom = 1000.0;

  void detonate() {
    for (final system in systems) {
      system.reset();
    }
    for (final chunk in chunks) {
      chunk.boom(_rng);
    }
    _sinceBoom = 0;
  }

  @override
  void update(double deltaSeconds) {
    _sinceBoom += deltaSeconds;
    if (auto && _sinceBoom >= interval) detonate();

    // Shockwave: a fast ground ring that expands and fades over 0.55 s.
    final t = (_sinceBoom / 0.55).clamp(0.0, 1.0);
    final eased = 1.0 - (1.0 - t) * (1.0 - t);
    final radius = 0.4 + 7.2 * eased;
    shockwaveNode.visible = t < 1.0;
    shockwaveNode.localTransform = vm.Matrix4.translation(
      vm.Vector3(0, 0.03, 0),
    )..multiply(vm.Matrix4.diagonal3Values(radius, 1, radius));
    shockwaveMaterial.baseColorFactor = vm.Vector4(
      2.6,
      1.9,
      1.3,
      0.85 * (1.0 - eased),
    );

    // Light: a hard flash decaying over ~0.4 s.
    light.intensity = 55.0 * exp(-_sinceBoom * 7.0);
  }
}

class ExampleExplosionState extends State<ExampleExplosion> {
  Scene scene = Scene();
  bool _ready = false;
  late _ExplosionDirector _director;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.004, 0.006, 0.016),
        horizonColor: vm.Vector3(0.02, 0.024, 0.05),
        groundColor: vm.Vector3(0.008, 0.007, 0.006),
        sunColor: vm.Vector3(0.04, 0.05, 0.08),
      ),
    );
    scene.environmentIntensity = 0.08;
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.3, -0.8, 0.35),
      color: vm.Vector3(0.5, 0.6, 0.85),
      intensity: 0.3,
      castsShadow: true,
    );

    final fireballAtlas = GpuTextureSource(
      await gpuTextureFromImage(await bakeFireballAtlas()),
    );
    final smokeAtlas = GpuTextureSource(
      await gpuTextureFromImage(await bakeSmokeAtlas()),
    );
    final dot = GpuTextureSource(
      await gpuTextureFromImage(await bakeSoftDot()),
    );

    _buildSet();

    final fireball = _fireball(fireballAtlas);
    final sparks = _sparks(dot);
    final smoke = _smoke(smokeAtlas);
    final debris = _debris();

    // Shockwave ring, swept by the director.
    final shockwaveMaterial = UnlitMaterial()
      ..alphaMode = AlphaMode.blend
      ..baseColorFactor = vm.Vector4(2.6, 1.9, 1.3, 0.0);
    final shockwaveNode = Node(
      mesh: Mesh(
        RingGeometry(innerRadius: 0.86, outerRadius: 1.0, segments: 64),
        shockwaveMaterial,
      ),
    )..visible = false;
    scene.add(shockwaveNode);

    // Hero chunks with ribbon trails.
    final chunkGeometry = CuboidGeometry(vm.Vector3(0.16, 0.11, 0.13));
    final chunkMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.16, 0.14, 0.12, 1)
      ..roughnessFactor = 0.7
      ..metallicFactor = 0.1
      ..emissiveFactor = vm.Vector4(1.3, 0.32, 0.05, 1);
    final chunks = <_HeroChunk>[];
    for (var i = 0; i < 6; i++) {
      final trail = TrailComponent(
        width: 0.16,
        lifetime: 0.5,
        minVertexDistance: 0.08,
        maxPoints: 40,
        colorOverTrail: ColorGradient([
          ColorStop(0.0, vm.Vector4(3.4, 1.6, 0.5, 0.9)),
          ColorStop(0.6, vm.Vector4(2.2, 0.7, 0.15, 0.5)),
          ColorStop(1.0, vm.Vector4(1.2, 0.25, 0.04, 0.0)),
        ]),
      );
      final chunk = _HeroChunk(trail, i);
      chunks.add(chunk);
      scene.add(
        Node(mesh: Mesh(chunkGeometry, chunkMaterial))
          ..visible = false
          ..addComponent(trail)
          ..addComponent(chunk),
      );
    }

    final light = PointLight(
      color: vm.Vector3(1.0, 0.6, 0.3),
      intensity: 0.0,
      range: 30.0,
    );
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 1.2, 0))
        ..addComponent(PointLightComponent(light)),
    );

    _director = _ExplosionDirector(
      systems: [fireball, sparks, smoke, debris],
      chunks: chunks,
      shockwaveNode: shockwaveNode,
      shockwaveMaterial: shockwaveMaterial,
      light: light,
    );
    scene.add(Node()..addComponent(_director));

    if (mounted) setState(() => _ready = true);
  }

  // A dark proving ground: a big disc and a few blocks for the shockwave,
  // debris, and soft smoke to play against.
  void _buildSet() {
    scene.add(
      Node(
        mesh: Mesh(
          DiscGeometry(radius: 14.0, segments: 48),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.10, 0.10, 0.11, 1)
            ..roughnessFactor = 0.85
            ..metallicFactor = 0.0,
        ),
      ),
    );
    final rng = Random(3);
    for (var i = 0; i < 5; i++) {
      final angle = i * 2 * pi / 5 + rng.nextDouble() * 0.5;
      final r = 3.2 + rng.nextDouble() * 1.6;
      final w = 0.7 + rng.nextDouble() * 0.9;
      final h = 0.5 + rng.nextDouble() * 0.9;
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(w, h, 0.5)),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(0.22, 0.21, 0.2, 1)
              ..roughnessFactor = 0.9
              ..metallicFactor = 0.0,
          ),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(angle) * r, h / 2, sin(angle) * r),
          )..multiply(vm.Matrix4.rotationY(rng.nextDouble() * pi)),
        ),
      );
    }
  }

  // The fireball: a one-shot burst of flipbook fireballs that grow and erode
  // in place while drifting outward, HDR-tinted into bloom range.
  ParticleSystem _fireball(TextureSource atlas) {
    final system = ParticleSystem(
      maxParticles: 24,
      shape: const shape.SphereShape(radius: 0.12),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.02, count: 13)]),
      looping: false,
      duration: 2.0,
      lifetime: const UniformFloat(0.55, 0.85),
      startSpeed: const UniformFloat(1.5, 3.2),
      startSize: const UniformFloat(0.9, 1.5),
      modules: [
        LinearDragModule(2.4),
        const FlipbookModule(frameCount: 64),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.55),
              const ParticleKeyframe(0.45, 1.25),
              const ParticleKeyframe(1.0, 1.5),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(2.4, 2.2, 2.0, 0.0)),
              ColorStop(0.06, vm.Vector4(2.4, 2.2, 2.0, 1.0)),
              ColorStop(0.6, vm.Vector4(1.7, 1.2, 0.9, 0.9)),
              ColorStop(1.0, vm.Vector4(0.9, 0.5, 0.3, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 21,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.additive;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..flipbookColumns = 8
      ..flipbookRows = 8
      ..flipbookBlend = true
      ..randomFlipX = true;
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.7, 0))
        ..addComponent(emitter),
    );
    return system;
  }

  // Sparks: a hard shell of white-hot velocity-stretched streaks under
  // gravity, blinking out through the blackbody ramp.
  ParticleSystem _sparks(TextureSource dot) {
    final system = ParticleSystem(
      maxParticles: 96,
      shape: const shape.SphereShape(radius: 0.05),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 70)]),
      looping: false,
      duration: 2.0,
      lifetime: const UniformFloat(0.5, 1.1),
      startSpeed: const UniformFloat(5.0, 12.0),
      startSize: const UniformFloat(0.03, 0.06),
      gravity: vm.Vector3(0, -9.8, 0),
      modules: [
        LinearDragModule(0.8),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0.5))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(4.5, 2.4, 0.8, 1.0)),
              ColorStop(0.35, vm.Vector4(3.8, 1.6, 0.35, 1.0)),
              ColorStop(0.6, vm.Vector4(3.0, 1.0, 0.2, 0.3)),
              ColorStop(0.8, vm.Vector4(3.2, 1.2, 0.25, 0.8)),
              ColorStop(1.0, vm.Vector4(1.5, 0.35, 0.05, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 22,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = BillboardFacing.velocityStretched
      ..velocityStretch = 0.05;
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.6, 0))
        ..addComponent(emitter),
    );
    return system;
  }

  // The smoke that follows the flash: soft, dark, rising, dissolving
  // through the eroding flipbook and depth-fading through the set blocks.
  ParticleSystem _smoke(TextureSource atlas) {
    final system = ParticleSystem(
      maxParticles: 24,
      shape: const shape.ConeShape(angle: 0.5, radius: 0.4),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.22, count: 10)]),
      looping: false,
      duration: 2.0,
      lifetime: const UniformFloat(2.0, 3.2),
      startSpeed: const UniformFloat(0.8, 1.7),
      startSize: const UniformFloat(1.1, 1.7),
      startRotation: const UniformFloat(0.0, 6.283),
      startAngularVelocity: const UniformFloat(-0.4, 0.4),
      gravity: vm.Vector3(0, 0.5, 0),
      modules: [
        LinearDragModule(0.9),
        const RotationModule(),
        const FlipbookModule(frameCount: 16),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.6),
              const ParticleKeyframe(1.0, 2.6),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(0.5, 0.32, 0.2, 0.0)),
              ColorStop(0.12, vm.Vector4(0.2, 0.16, 0.13, 0.3)),
              ColorStop(0.6, vm.Vector4(0.08, 0.08, 0.085, 0.2)),
              ColorStop(1.0, vm.Vector4(0.05, 0.05, 0.055, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 23,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.alpha
      ..softDepthFade = 0.7;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..flipbookColumns = 4
      ..flipbookRows = 4
      ..flipbookBlend = true
      ..randomFlipX = true;
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.9, 0))
        ..addComponent(emitter),
    );
    return system;
  }

  // Instanced mesh debris: a shell of tumbling chunks (three shapes picked
  // per particle) that arc under gravity, still faintly hot.
  ParticleSystem _debris() {
    final system = ParticleSystem(
      maxParticles: 40,
      shape: const shape.ConeShape(angle: 0.55, radius: 0.15),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 26)]),
      looping: false,
      duration: 2.0,
      lifetime: const UniformFloat(1.5, 2.2),
      startSpeed: const UniformFloat(4.0, 9.0),
      startSize: const UniformFloat(0.5, 1.3),
      startAngularVelocity: const UniformFloat(-14.0, 14.0),
      gravity: vm.Vector3(0, -9.8, 0),
      modules: [const RotationModule()],
      seed: 24,
    );
    final material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.17, 0.15, 0.13, 1)
      ..roughnessFactor = 0.8
      ..metallicFactor = 0.05
      ..emissiveFactor = vm.Vector4(0.9, 0.22, 0.03, 1);
    final emitter = MeshParticleEmitterComponent(
      system: system,
      geometries: [
        CuboidGeometry(vm.Vector3(0.11, 0.07, 0.09)),
        WedgeGeometry(vm.Vector3(0.1, 0.06, 0.08)),
        CuboidGeometry(vm.Vector3(0.05, 0.12, 0.05)),
      ],
      material: material,
    );
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.5, 0))
        ..addComponent(emitter),
    );
    return system;
  }

  Widget _buildPanel() {
    return ExamplePanelCard(
      icon: Icons.brightness_7,
      title: 'Explosion',
      width: 320,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _director.detonate(),
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Detonate'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Expanded(
                child: Text('Auto', style: TextStyle(color: Colors.white)),
              ),
              Switch(
                value: _director.auto,
                onChanged: (v) => setState(() => _director.auto = v),
              ),
            ],
          ),
          _SliderRow(
            label: 'Interval',
            value: _director.interval,
            min: 2.0,
            max: 8.0,
            onChanged: (v) => setState(() => _director.interval = v),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF050507),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: SceneView(
            scene,
            cameraBuilder: (elapsed) {
              final t = elapsed.inMicroseconds / 1e6;
              return PerspectiveCamera(
                position: vm.Vector3(
                  sin(t * 0.1) * 10.0,
                  3.4,
                  cos(t * 0.1) * 10.0,
                ),
                target: vm.Vector3(0, 1.2, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) => exampleSettings.applyTo(scene),
          ),
        ),
        ExampleOverlay.bottomRightPanel(paired: true, child: _buildPanel()),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            '$label: ${value.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}
