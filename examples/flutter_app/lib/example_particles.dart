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
import 'package:flutter_scene/src/noise/fast_noise_lite.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart' as shape;
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'example_overlay.dart';
import 'example_panel.dart';
import 'example_settings.dart';

/// A layered CPU-particle campfire at night: flipbook flames (a rolling core
/// plus fast edge tongues) baked from domain-warped fbm noise with a blackbody
/// color ramp, curl-noise turbulence, eroding smoke puffs, drifting embers, a
/// pulsing ground glow, and a flickering point light over a log teepee with a
/// glowing coal bed. A panel exposes the fire's tuning live.
class ExampleParticles extends StatefulWidget {
  const ExampleParticles({super.key});

  @override
  ExampleParticlesState createState() => ExampleParticlesState();
}

/// Flickers the campfire's point light with low-frequency noise and jitters
/// its node so the log shadows dance.
class _FirelightFlicker extends Component {
  _FirelightFlicker(this.light, this.baseIntensity);

  final PointLight light;
  double baseIntensity;
  double height = 0.9;
  final FastNoiseLite _noise = FastNoiseLite()
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  double _t = 0;

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    final n = _noise.getNoise2(_t * 3.2, 3.7) * 0.5 + 0.5;
    light.intensity = baseIntensity * (0.7 + 0.5 * n);
    final jx = _noise.getNoise2(_t * 2.2, 11.3) * 0.05;
    final jz = _noise.getNoise2(_t * 2.2, 17.9) * 0.05;
    node.localTransform = vm.Matrix4.translation(vm.Vector3(jx, height, jz));
  }
}

/// Pulses a coal's emissive with slow noise, each coal on its own phase, so
/// the bed breathes like embers being fanned.
class _CoalGlow extends Component {
  _CoalGlow(this.material, this.phase);

  final PhysicallyBasedMaterial material;
  final double phase;
  static final vm.Vector4 _base = vm.Vector4(2.4, 0.55, 0.06, 1.0);
  final FastNoiseLite _noise = FastNoiseLite()
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  double _t = 0;

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    final n = _noise.getNoise2(_t * 1.6 + phase * 13.7, phase) * 0.5 + 0.5;
    final s = 0.45 + 0.75 * n;
    material.emissiveFactor = vm.Vector4(
      _base.x * s,
      _base.y * s,
      _base.z * s,
      1.0,
    );
  }
}

class ExampleParticlesState extends State<ExampleParticles> {
  Scene scene = Scene();
  bool _ready = false;

  // Live fire tuning (see _applyParams).
  double _intensity = 1.8;
  double _flameScale = 0.94;
  double _flameWidth = 1.51;
  double _flipbookSpeed = 0.68;
  double _fireHeight = -0.24;
  double _flameTurbulence = 0.05;
  double _emberTurbulence = 0.41;
  double _wind = 0.26;
  double _smokeAmount = 0.25;
  double _emberAmount = 0.4;

  // Terrain shaping. These rebuild the ground and grass geometry, so their
  // sliders apply on release rather than per drag tick.
  double _hillFrequency = 0.11;
  double _hillHeight = 0.18;

  // Base spawn rates the intensity/density sliders scale.
  static const double _coreRate = 18.0;
  static const double _tongueRate = 22.0;
  static const double _glowRate = 7.0;
  static const double _smokeRate = 10.0;
  static const double _emberRate = 14.0;

  late ParticleSystem _coreSystem;
  late ParticleSystem _tongueSystem;
  late ParticleSystem _glowSystem;
  late ParticleSystem _smokeSystem;
  late ParticleSystem _emberSystem;
  late ParticleEmitterComponent _coreEmitter;
  late ParticleEmitterComponent _tongueEmitter;
  late PreprocessedMaterial _grassMaterial;
  late PhysicallyBasedMaterial _groundMaterial;
  late Node _groundNode;
  late Node _grassNode;
  late _FirelightFlicker _flicker;
  final List<(TurbulenceModule, double)> _flameTurbs = [];
  final List<(TurbulenceModule, double)> _emberTurbs = [];
  final List<(AccelerationModule, double)> _winds = [];
  final List<(Node, double)> _fireNodes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A moonless starry night (a procedural `.fmat` sky: hash-grid stars and
    // an fbm milky way). The fire's own point light carries the scene, so
    // the image-based ambient stays near black and a faint blue directional
    // stands in for skylight.
    scene.skybox = Skybox(await loadFmatSky('assets/night_sky.fmat'));
    scene.environmentIntensity = 0.06;
    scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(0.35, -0.75, 0.25),
      color: vm.Vector3(0.45, 0.55, 0.85),
      intensity: 0.18,
      castsShadow: true,
    );

    // Bake every texture up front (frame by frame with yields so the loading
    // spinner keeps animating): the flame and smoke flipbooks, the ember dot,
    // and the ground/stone albedos.
    final flameAtlas = GpuTextureSource(
      await gpuTextureFromImage(await _bakeFlameAtlas()),
    );
    final smokeAtlas = GpuTextureSource(
      await gpuTextureFromImage(await _bakeSmokeAtlas()),
    );
    final dot = GpuTextureSource(
      await gpuTextureFromImage(await _bakeSoftDot()),
    );
    final groundTexture = GpuTextureSource(
      await gpuTextureFromImage(await _bakeGroundTexture()),
    );
    final stoneTexture = GpuTextureSource(
      await gpuTextureFromImage(await _bakeStoneTexture()),
    );
    _grassMaterial = await loadFmatMaterial('assets/campfire_grass.fmat');

    _buildCampsite(groundTexture, stoneTexture);

    scene.add(_flameCore(flameAtlas));
    scene.add(_flameTongues(flameAtlas));
    scene.add(_glow(dot));
    scene.add(_smoke(smokeAtlas));
    scene.add(_embers(dot));

    final firelight = PointLight(
      color: vm.Vector3(1.0, 0.52, 0.18),
      intensity: 7.0,
      range: 16.0,
    );
    _flicker = _FirelightFlicker(firelight, 7.0);
    scene.add(
      Node()
        ..localTransform = vm.Matrix4.translation(vm.Vector3(0, 0.9, 0))
        ..addComponent(PointLightComponent(firelight))
        ..addComponent(_flicker),
    );

    _applyParams();
    if (mounted) setState(() => _ready = true);
  }

  // Pushes the slider values into the live systems: spawn rates, sprite
  // sizes and aspect, flipbook pacing (via lifetime), emitter heights,
  // turbulence strengths, wind accelerations, and the light.
  void _applyParams() {
    _coreSystem.spawner.rate = _coreRate * _intensity;
    _tongueSystem.spawner.rate = _tongueRate * _intensity;
    _glowSystem.spawner.rate = _glowRate * _intensity;
    _smokeSystem.spawner.rate = _smokeRate * _smokeAmount;
    _emberSystem.spawner.rate = _emberRate * _emberAmount;
    _coreSystem.startSize = UniformFloat(
      0.85 * _flameScale,
      1.15 * _flameScale,
    );
    _tongueSystem.startSize = UniformFloat(
      0.35 * _flameScale,
      0.55 * _flameScale,
    );
    // The flame flipbooks play once over life, so playback speed is the
    // inverse of lifetime.
    _coreSystem.lifetime = UniformFloat(
      1.1 / _flipbookSpeed,
      1.6 / _flipbookSpeed,
    );
    _tongueSystem.lifetime = UniformFloat(
      0.55 / _flipbookSpeed,
      0.85 / _flipbookSpeed,
    );
    _coreEmitter.aspectRatio = _flameWidth;
    _tongueEmitter.aspectRatio = _flameWidth;
    for (final (node, baseY) in _fireNodes) {
      node.localTransform = vm.Matrix4.translation(
        vm.Vector3(0, baseY + _fireHeight, 0),
      );
    }
    _flicker.height = 0.9 + _fireHeight;
    for (final (module, base) in _flameTurbs) {
      module.strength = base * _flameTurbulence;
    }
    for (final (module, base) in _emberTurbs) {
      module.strength = base * _emberTurbulence;
    }
    for (final (module, factor) in _winds) {
      module.acceleration.setValues(_wind * factor, 0, 0);
    }
    // The grass fmat shares the wind slider: a stronger breeze sways harder
    // and faster, and the signed value leans the blades downwind.
    _grassMaterial.parameters
      ..setFloat('wind_strength', 0.3 + 0.45 * _wind.abs())
      ..setFloat('wind_speed', 1.3 + 1.6 * _wind.abs())
      ..setFloat('wind_lean', _wind * 0.4);
    _flicker.baseIntensity = 7.0 * _intensity;
  }

  // Registers a turbulence module into [group] (whose slider scales its
  // strength) and returns it for the module list.
  TurbulenceModule _turb(
    List<(TurbulenceModule, double)> group, {
    required double strength,
    required double frequency,
    required vm.Vector3 scroll,
    required int seed,
  }) {
    final module = TurbulenceModule(
      strength: strength,
      frequency: frequency,
      scroll: scroll,
      seed: seed,
    );
    group.add((module, strength));
    return module;
  }

  // Registers a wind acceleration for this emitter ([factor] scales the wind
  // slider; light flames barely lean, smoke and embers carry).
  AccelerationModule _windFor(double factor) {
    final module = AccelerationModule(vm.Vector3.zero());
    _winds.add((module, factor));
    return module;
  }

  static const double _groundRadius = 9.0;
  final FastNoiseLite _hillNoise = FastNoiseLite()
    ..seed = 51
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  // Terrain height: flat around the campsite, rolling fbm hills beyond.
  double _groundHeight(double x, double z) {
    final r = sqrt(x * x + z * z);
    final lift = _smoothstep(1.6, 3.8, r);
    return _hillNoise.getNoise2(x * _hillFrequency, z * _hillFrequency) *
        _hillHeight *
        lift;
  }

  // The terrain: a polar heightfield grid sharing the disc's planar UVs so
  // the baked ground texture (and its scorch ring) lands the same way.
  MeshGeometry _buildGroundGeometry() {
    const rings = 40;
    const segments = 72;
    const eps = 0.15;
    final positions = <double>[];
    final normals = <double>[];
    final texCoords = <double>[];
    final indices = <int>[];
    for (var i = 0; i <= rings; i++) {
      final r = _groundRadius * i / rings;
      for (var s = 0; s <= segments; s++) {
        final theta = 2 * pi * s / segments;
        final x = r * cos(theta);
        final z = r * sin(theta);
        final y = _groundHeight(x, z);
        final hx = _groundHeight(x + eps, z) - _groundHeight(x - eps, z);
        final hz = _groundHeight(x, z + eps) - _groundHeight(x, z - eps);
        final n = vm.Vector3(-hx / (2 * eps), 1, -hz / (2 * eps))..normalize();
        positions.addAll([x, y, z]);
        normals.addAll([n.x, n.y, n.z]);
        texCoords.addAll([
          0.5 + x / (2 * _groundRadius),
          0.5 + z / (2 * _groundRadius),
        ]);
      }
    }
    for (var i = 0; i < rings; i++) {
      for (var s = 0; s < segments; s++) {
        final a = i * (segments + 1) + s;
        final b = (i + 1) * (segments + 1) + s;
        // Same rotational winding as the disc primitive (front face up).
        indices.addAll([a, b, a + 1, a + 1, b, b + 1]);
      }
    }
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      texCoords: Float32List.fromList(texCoords),
      indices: indices,
    );
  }

  // Appends one tapered, forward-arced blade standing on the terrain at
  // (x, y, z), a vertical strip of a few segments so the shader's
  // root-anchored sway curves it smoothly (the grass material culls nothing,
  // so one set of triangles reads from both sides). uv.x carries the height
  // above this blade's own root (so sway anchors correctly on the hills) and
  // uv.y the normalized 0..1 for the base-to-tip gradient; the vertex color
  // is a per-blade tint. [parched] pushes the blade shorter and straw-dry
  // (used near the fire's scorched circle).
  void _appendBlade(
    Random rng,
    List<double> positions,
    List<double> normals,
    List<double> texCoords,
    List<double> colors,
    List<int> indices, {
    required double x,
    required double y,
    required double z,
    double parched = 0.0,
  }) {
    const segments = 4;
    // Maturity: most blades roll young (shorter, greener), a minority mature
    // (taller, yellower); parched blades skew mature.
    final maturity = (pow(rng.nextDouble(), 2.4).toDouble() + 0.7 * parched)
        .clamp(0.0, 1.0);
    final height =
        (0.16 + rng.nextDouble() * 0.16) *
        (0.85 + 0.45 * maturity) *
        (1.0 - 0.5 * parched);
    final width = 0.02 + rng.nextDouble() * 0.014;
    final bendAmount = 0.05 + rng.nextDouble() * 0.07;
    final yaw = rng.nextDouble() * 2 * pi;
    final side = vm.Vector3(cos(yaw), 0, sin(yaw));
    final fwd = vm.Vector3(-sin(yaw), 0, cos(yaw));
    // A mostly-upward normal, leaned along the bend so blades catch the fire
    // and moonlight a touch differently; constant across the blade.
    final normal = vm.Vector3(fwd.x * 0.35, 1.0, fwd.z * 0.35)..normalize();
    final root = vm.Vector3(x, y, z);

    // Per-blade tint: a lightness spread plus a warm/cool push, shifted
    // toward dry yellow with maturity, then blended toward a dead grey-brown
    // by [parched] so the fire's surroundings read scorched, not just dry.
    final light = 0.78 + rng.nextDouble() * 0.4;
    final warm = 0.9 + rng.nextDouble() * 0.28;
    final cool = 0.9 + rng.nextDouble() * 0.16;
    var tintR = light * warm * (1.0 + 0.55 * maturity);
    var tintG = light * (1.0 + 0.1 * maturity);
    var tintB = light * cool * 0.88 * (1.0 - 0.55 * maturity);
    final dead = 0.75 * parched;
    tintR += (0.60 * light - tintR) * dead;
    tintG += (0.48 * light - tintG) * dead;
    tintB += (0.34 * light - tintB) * dead;

    final base = positions.length ~/ 3;
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final halfW = width * (1 - t) * 0.5;
      final center =
          root + vm.Vector3(0, height * t, 0) + fwd * (bendAmount * t * t);
      final left = center - side * halfW;
      final right = center + side * halfW;
      positions.addAll([left.x, left.y, left.z, right.x, right.y, right.z]);
      normals.addAll([
        normal.x,
        normal.y,
        normal.z,
        normal.x,
        normal.y,
        normal.z,
      ]);
      final localHeight = height * t;
      texCoords.addAll([localHeight, t, localHeight, t]);
      colors.addAll([tintR, tintG, tintB, 1, tintR, tintG, tintB, 1]);
    }
    for (var i = 0; i < segments; i++) {
      final l0 = base + i * 2;
      indices.addAll([l0, l0 + 1, l0 + 2, l0 + 1, l0 + 3, l0 + 2]);
    }
  }

  // Scatters thousands of blades into one geometry rooted on the terrain.
  // Density ramps with distance from the fire, sparse dead stragglers by the
  // scorched circle thickening into a dense carpet on the far hills, with
  // noise-masked bare patches in between. All movement and the
  // short-green/tall-yellow macro variation happen in the grass fmat.
  MeshGeometry _buildGrassGeometry() {
    final rng = Random(9);
    final positions = <double>[];
    final normals = <double>[];
    final texCoords = <double>[];
    final colors = <double>[];
    final indices = <int>[];
    var placed = 0;
    var attempts = 0;
    while (placed < 55000 && attempts < 700000) {
      attempts++;
      final x = (rng.nextDouble() * 2 - 1) * 8.4;
      final z = (rng.nextDouble() * 2 - 1) * 8.4;
      final r = sqrt(x * x + z * z);
      if (r < 1.6 || r > 8.4) continue;
      // Acceptance climbs from stragglers at the scorch circle to full
      // density within a few units.
      final accept = 0.10 + 0.90 * _smoothstep(1.8, 4.5, r);
      if (rng.nextDouble() > accept) continue;
      // A few large bald areas stay mostly bare regardless of density.
      final bald = _hillNoise.getNoise2(x * 0.28 + 120, z * 0.28 + 120);
      if (bald < -0.35 && rng.nextDouble() > 0.12) continue;
      // Fine clump mask keeps small-scale patchiness in the mid field.
      if (_hillNoise.getNoise2(x * 0.9 + 50, z * 0.9 + 50) <
          -0.15 - 0.5 * _smoothstep(5.5, 8.0, r)) {
        continue;
      }
      // Blades near the fire bake dead: short, grey-brown, sparse.
      final parched = 1.0 - _smoothstep(1.9, 3.6, r);
      _appendBlade(
        rng,
        positions,
        normals,
        texCoords,
        colors,
        indices,
        x: x,
        y: _groundHeight(x, z),
        z: z,
        parched: parched,
      );
      placed++;
    }
    return MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      texCoords: Float32List.fromList(texCoords),
      colors: Float32List.fromList(colors),
      indices: Uint32List.fromList(indices),
    );
  }

  // Rebuilds the terrain-shaped geometry (ground mesh and grass roots) after
  // the hill sliders change.
  void _rebuildTerrain() {
    _groundNode.mesh = Mesh(_buildGroundGeometry(), _groundMaterial);
    _grassNode.mesh = Mesh(_buildGrassGeometry(), _grassMaterial);
  }

  // Ground terrain, grass, stone ring, log teepee, and a glowing coal bed.
  void _buildCampsite(TextureSource ground, TextureSource stone) {
    _groundMaterial = PhysicallyBasedMaterial(baseColorTexture: ground)
      ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
      ..roughnessFactor = 0.95
      ..metallicFactor = 0.0;
    _groundNode = Node(mesh: Mesh(_buildGroundGeometry(), _groundMaterial));
    scene.add(_groundNode);
    _grassNode = Node(mesh: Mesh(_buildGrassGeometry(), _grassMaterial));
    scene.add(_grassNode);

    final rng = Random(5);
    const stoneCount = 9;
    for (var i = 0; i < stoneCount; i++) {
      final a = i * 2 * pi / stoneCount + rng.nextDouble() * 0.3;
      final r = 0.95 + rng.nextDouble() * 0.12;
      final s = 0.14 + rng.nextDouble() * 0.08;
      // Warm/cool tint and roughness variation so the ring reads as a pile of
      // different rocks under the firelight, not nine copies.
      final warm = rng.nextDouble();
      final tint = vm.Vector4(
        0.75 + 0.25 * warm,
        0.72 + 0.13 * warm,
        0.78 - 0.18 * warm,
        1,
      );
      scene.add(
        Node(
          mesh: Mesh(
            SphereGeometry(radius: 1.0),
            PhysicallyBasedMaterial(baseColorTexture: stone)
              ..baseColorFactor = tint
              ..roughnessFactor = 0.55 + rng.nextDouble() * 0.35
              ..metallicFactor = 0.0,
          ),
          localTransform:
              vm.Matrix4.translation(
                vm.Vector3(cos(a) * r, s * 0.5, sin(a) * r),
              )..multiply(
                vm.Matrix4.rotationY(rng.nextDouble() * 2 * pi)
                  ..multiply(vm.Matrix4.diagonal3Values(s, s * 0.62, s)),
              ),
        ),
      );
    }

    const logCount = 5;
    for (var i = 0; i < logCount; i++) {
      final yaw = i * 2 * pi / logCount + rng.nextDouble() * 0.25;
      final lean = 0.66 + rng.nextDouble() * 0.10;
      final brown = 0.05 + rng.nextDouble() * 0.02;
      final transform = vm.Matrix4.rotationY(yaw)
        ..multiply(vm.Matrix4.translation(vm.Vector3(0.20, 0.44, 0)))
        ..multiply(vm.Matrix4.rotationZ(lean));
      scene.add(
        Node(
          mesh: Mesh(
            CylinderGeometry(
              bottomRadius: 0.065,
              topRadius: 0.05,
              height: 0.95,
              radialSegments: 10,
            ),
            PhysicallyBasedMaterial()
              ..baseColorFactor = vm.Vector4(brown * 1.6, brown, brown * 0.6, 1)
              ..roughnessFactor = 0.92
              ..metallicFactor = 0.0,
          ),
          localTransform: transform,
        ),
      );
    }

    // Coal bed: small near-black lumps whose pulsing emissive makes the base
    // of the fire glow from within.
    const coalCount = 9;
    for (var i = 0; i < coalCount; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final r = rng.nextDouble() * 0.28;
      final s = 0.05 + rng.nextDouble() * 0.05;
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.02, 0.015, 0.01, 1)
        ..roughnessFactor = 0.9
        ..metallicFactor = 0.0;
      scene.add(
        Node(
          mesh: Mesh(SphereGeometry(radius: 1.0), material),
          localTransform: vm.Matrix4.translation(
            vm.Vector3(cos(a) * r, s * 0.4 + 0.03, sin(a) * r),
          )..multiply(vm.Matrix4.diagonal3Values(s, s * 0.6, s)),
        )..addComponent(_CoalGlow(material, i / coalCount)),
      );
    }
  }

  // The big rolling flames in the center. Upright (axis-locked) billboards
  // playing the 8x8 erosion flipbook once over each particle's life, kept
  // licking by curl-noise turbulence and buoyancy.
  Node _flameCore(TextureSource atlas) {
    _coreSystem = ParticleSystem(
      maxParticles: 64,
      shape: const shape.ConeShape(angle: 0.10, radius: 0.14),
      spawner: Spawner(rate: _coreRate),
      // Lifetime sets the flipbook pace (64 frames once over life), so keep
      // it above a second or the flames strobe.
      lifetime: const UniformFloat(1.1, 1.6),
      startSpeed: const UniformFloat(0.2, 0.35),
      startSize: const UniformFloat(0.85, 1.15),
      gravity: vm.Vector3(0, 0.42, 0),
      modules: [
        _windFor(0.5),
        // Drag bleeds off accumulated turbulence kicks, so flames wobble in
        // place instead of wandering away from the fire even at high
        // turbulence settings.
        LinearDragModule(1.2),
        // Keep flames anchored: the flipbook already carries the rise and
        // detach, so the sprite itself only wobbles. High frequency and low
        // strength give small-scale licking without displacement.
        _turb(
          _flameTurbs,
          strength: 1.6,
          frequency: 2.0,
          scroll: vm.Vector3(0, 0.7, 0),
          seed: 11,
        ),
        const FlipbookModule(frameCount: 64),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.55),
              const ParticleKeyframe(0.35, 1.0),
              const ParticleKeyframe(1.0, 0.8),
            ]),
          ),
        ),
        // HDR tints push the already-hot texture into bloom range; alpha
        // handles the fade at both ends of life.
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(1.7, 1.55, 1.4, 0.0)),
              ColorStop(0.08, vm.Vector4(1.7, 1.55, 1.4, 1.0)),
              ColorStop(0.7, vm.Vector4(1.4, 1.1, 0.9, 0.95)),
              ColorStop(1.0, vm.Vector4(1.0, 0.65, 0.5, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 2,
      prewarm: 1.5,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.additive;
    // Billboards center on the particle, so lift the emitter until the
    // quad's bottom (the flame base in the texture) sits at the coal bed
    // instead of being depth-clipped below the ground.
    final (node, emitter) = _emitterNode(
      _coreSystem,
      material,
      facing: BillboardFacing.axisLocked,
      flipbookColumns: 8,
      flipbookRows: 8,
      flipbookBlend: true,
      randomFlipX: true,
      y: 0.62,
    );
    _coreEmitter = emitter;
    return node;
  }

  // Smaller, faster tongues around the core's edge. Same atlas, shorter lives
  // and stronger turbulence, so the fire's silhouette flickers at a second
  // scale (fire reads wrong with only one flame size).
  Node _flameTongues(TextureSource atlas) {
    _tongueSystem = ParticleSystem(
      maxParticles: 64,
      shape: const shape.ConeShape(angle: 0.25, radius: 0.22),
      spawner: Spawner(rate: _tongueRate),
      lifetime: const UniformFloat(0.55, 0.85),
      startSpeed: const UniformFloat(0.3, 0.55),
      startSize: const UniformFloat(0.35, 0.55),
      gravity: vm.Vector3(0, 0.7, 0),
      modules: [
        _windFor(0.7),
        LinearDragModule(1.2),
        _turb(
          _flameTurbs,
          strength: 2.6,
          frequency: 2.4,
          scroll: vm.Vector3(0, 1.0, 0),
          seed: 23,
        ),
        const FlipbookModule(frameCount: 64),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.7),
              const ParticleKeyframe(0.3, 1.0),
              const ParticleKeyframe(1.0, 0.5),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(1.6, 1.35, 1.15, 0.0)),
              ColorStop(0.1, vm.Vector4(1.6, 1.35, 1.15, 0.9)),
              ColorStop(1.0, vm.Vector4(1.0, 0.6, 0.4, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 3,
      prewarm: 1.0,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.additive;
    final (node, emitter) = _emitterNode(
      _tongueSystem,
      material,
      facing: BillboardFacing.axisLocked,
      flipbookColumns: 8,
      flipbookRows: 8,
      flipbookBlend: true,
      randomFlipX: true,
      y: 0.48,
    );
    _tongueEmitter = emitter;
    return node;
  }

  // A large, dim additive halo around the fire's base. Overlapping short
  // lives make the halo breathe, which reads as radiant flicker.
  Node _glow(TextureSource dot) {
    _glowSystem = ParticleSystem(
      maxParticles: 16,
      shape: const shape.SphereShape(radius: 0.15),
      spawner: Spawner(rate: _glowRate),
      lifetime: const UniformFloat(0.6, 1.0),
      startSpeed: const UniformFloat(0.05, 0.15),
      startSize: const UniformFloat(2.4, 3.2),
      modules: [
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(1.9, 0.85, 0.3, 0.0)),
              ColorStop(0.35, vm.Vector4(1.9, 0.85, 0.3, 0.085)),
              ColorStop(1.0, vm.Vector4(1.5, 0.6, 0.2, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 4,
      prewarm: 1.0,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    return _emitterNode(_glowSystem, material, y: 0.5).$1;
  }

  // Alpha-blended smoke above the flames: a dense column of big, faint,
  // overlapping puffs that rotate lazily and dissolve through the eroding
  // 4x4 flipbook. Born warm (firelit) and cooling to grey as they climb.
  Node _smoke(TextureSource atlas) {
    _smokeSystem = ParticleSystem(
      maxParticles: 64,
      shape: const shape.ConeShape(angle: 0.18, radius: 0.16),
      spawner: Spawner(rate: _smokeRate),
      lifetime: const UniformFloat(3.0, 4.5),
      startSpeed: const UniformFloat(0.3, 0.55),
      startSize: const UniformFloat(0.9, 1.3),
      startRotation: const UniformFloat(0.0, 6.283),
      startAngularVelocity: const UniformFloat(-0.3, 0.3),
      gravity: vm.Vector3(0, 0.22, 0),
      modules: [
        _windFor(1.1),
        // Strong turbulence would tear the plume into separate blobs.
        _turb(
          _flameTurbs,
          strength: 0.7,
          frequency: 0.45,
          scroll: vm.Vector3(0, 0.3, 0),
          seed: 31,
        ),
        const RotationModule(),
        const FlipbookModule(frameCount: 16),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.7),
              const ParticleKeyframe(1.0, 2.4),
            ]),
          ),
        ),
        // Night smoke reads as a dark occluder, not a lit grey: keep the
        // values near-black with only a faint warm birth from the firelight.
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(0.2, 0.14, 0.1, 0.0)),
              ColorStop(0.15, vm.Vector4(0.12, 0.095, 0.08, 0.22)),
              ColorStop(0.55, vm.Vector4(0.06, 0.058, 0.06, 0.16)),
              ColorStop(1.0, vm.Vector4(0.04, 0.04, 0.045, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 5,
      prewarm: 5.0,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.alpha;
    return _emitterNode(
      _smokeSystem,
      material,
      flipbookColumns: 4,
      flipbookRows: 4,
      flipbookBlend: true,
      randomFlipX: true,
      y: 1.35,
    ).$1;
  }

  // Embers: tiny velocity-stretched streaks that ride the turbulence upward,
  // blinking (the flicker is baked into the alpha gradient) and cooling from
  // white-hot to deep red before dying.
  Node _embers(TextureSource dot) {
    _emberSystem = ParticleSystem(
      maxParticles: 96,
      shape: const shape.ConeShape(angle: 0.5, radius: 0.28),
      spawner: Spawner(
        rate: _emberRate,
        bursts: const [ParticleBurst(time: 0.8, count: 9, interval: 2.3)],
      ),
      lifetime: const UniformFloat(1.1, 2.1),
      startSpeed: const UniformFloat(1.2, 2.6),
      startSize: const UniformFloat(0.025, 0.05),
      gravity: vm.Vector3(0, 0.9, 0),
      modules: [
        _windFor(1.4),
        LinearDragModule(0.5),
        _turb(
          _emberTurbs,
          strength: 4.0,
          frequency: 1.6,
          scroll: vm.Vector3(0, 1.0, 0),
          seed: 41,
        ),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0.6))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(4.2, 2.1, 0.55, 0.0)),
              ColorStop(0.05, vm.Vector4(4.2, 2.1, 0.55, 1.0)),
              ColorStop(0.22, vm.Vector4(3.5, 1.4, 0.3, 0.25)),
              ColorStop(0.38, vm.Vector4(4.0, 1.9, 0.45, 1.0)),
              ColorStop(0.55, vm.Vector4(3.0, 1.1, 0.2, 0.3)),
              ColorStop(0.72, vm.Vector4(3.6, 1.5, 0.3, 0.9)),
              ColorStop(1.0, vm.Vector4(1.6, 0.4, 0.05, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 6,
      prewarm: 2.0,
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive;
    return _emitterNode(
      _emberSystem,
      material,
      facing: BillboardFacing.velocityStretched,
      velocityStretch: 0.045,
      y: 0.45,
    ).$1;
  }

  (Node, ParticleEmitterComponent) _emitterNode(
    ParticleSystem system,
    SpriteMaterial material, {
    BillboardFacing facing = BillboardFacing.spherical,
    double velocityStretch = 0.0,
    int flipbookColumns = 1,
    int flipbookRows = 1,
    bool flipbookBlend = false,
    bool randomFlipX = false,
    double y = 0.0,
  }) {
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = facing
      ..velocityStretch = velocityStretch
      ..flipbookColumns = flipbookColumns
      ..flipbookRows = flipbookRows
      ..flipbookBlend = flipbookBlend
      ..randomFlipX = randomFlipX;
    final node = Node()
      ..localTransform = vm.Matrix4.translation(vm.Vector3(0, y, 0))
      ..addComponent(emitter);
    // The height slider re-derives every emitter's translation from its base.
    _fireNodes.add((node, y));
    return (node, emitter);
  }

  Widget _buildPanel() {
    return ExamplePanelCard(
      icon: Icons.local_fire_department,
      title: 'Campfire',
      width: 330,
      maxBodyHeight: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SliderRow(
            label: 'Intensity',
            value: _intensity,
            min: 0.2,
            max: 2.0,
            onChanged: (v) => setState(() {
              _intensity = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Flame size',
            value: _flameScale,
            min: 0.6,
            max: 2.2,
            onChanged: (v) => setState(() {
              _flameScale = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Flame width',
            value: _flameWidth,
            min: 0.7,
            max: 1.8,
            onChanged: (v) => setState(() {
              _flameWidth = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Flicker speed',
            value: _flipbookSpeed,
            min: 0.5,
            max: 2.0,
            onChanged: (v) => setState(() {
              _flipbookSpeed = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Height',
            value: _fireHeight,
            min: -0.3,
            max: 0.8,
            onChanged: (v) => setState(() {
              _fireHeight = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Flame turb',
            value: _flameTurbulence,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => setState(() {
              _flameTurbulence = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Ember turb',
            value: _emberTurbulence,
            min: 0.0,
            max: 2.5,
            onChanged: (v) => setState(() {
              _emberTurbulence = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Wind',
            value: _wind,
            min: -1.0,
            max: 1.0,
            onChanged: (v) => setState(() {
              _wind = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Smoke',
            value: _smokeAmount,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => setState(() {
              _smokeAmount = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Embers',
            value: _emberAmount,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => setState(() {
              _emberAmount = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Hill freq',
            value: _hillFrequency,
            min: 0.05,
            max: 0.6,
            onChanged: (v) => setState(() => _hillFrequency = v),
            onChangeEnd: (v) => _rebuildTerrain(),
          ),
          _SliderRow(
            label: 'Hill height',
            value: _hillHeight,
            min: 0.0,
            max: 1.5,
            onChanged: (v) => setState(() => _hillHeight = v),
            onChangeEnd: (v) => _rebuildTerrain(),
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
                  sin(t * 0.12) * 5.5,
                  1.7,
                  cos(t * 0.12) * 5.5,
                ),
                target: vm.Vector3(0, 1.0, 0),
              );
            },
            onTick: (elapsed, deltaSeconds) {
              _grassMaterial.parameters.setFloat(
                'time',
                elapsed.inMicroseconds / 1e6,
              );
              exampleSettings.applyTo(scene);
            },
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
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// For expensive settings (terrain rebuilds), fired on release rather than
  /// per drag tick.
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Baked textures
// ---------------------------------------------------------------------------

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Maps a normalized temperature to an approximate blackbody color (sRGB),
/// from extinguished black through deep red, orange, and yellow to near-white.
(double, double, double) _blackbody(double temp) {
  const stops = <(double, double, double, double)>[
    (0.0, 0.0, 0.0, 0.0),
    (0.20, 0.32, 0.02, 0.0),
    (0.45, 0.85, 0.22, 0.01),
    (0.70, 1.0, 0.62, 0.10),
    (0.88, 1.0, 0.86, 0.42),
    (1.0, 1.0, 0.98, 0.82),
  ];
  final t = temp.clamp(0.0, 1.0);
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i].$1) {
      final a = stops[i - 1];
      final b = stops[i];
      final f = (t - a.$1) / (b.$1 - a.$1);
      return (
        a.$2 + (b.$2 - a.$2) * f,
        a.$3 + (b.$3 - a.$3) * f,
        a.$4 + (b.$4 - a.$4) * f,
      );
    }
  }
  return (1.0, 0.98, 0.82);
}

Future<ui.Image> _imageFromPixels(Uint8List pixels, int size) {
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

/// Bakes the 8x8 flame flipbook (frame 0 top-left, row major). Each frame is
/// one flame tongue's whole life: it grows from the base, rolls upward under
/// a domain-warped fbm field, then detaches and erodes away, with brightness
/// mapped through the blackbody ramp. A particle plays the sequence exactly
/// once over its lifetime, so erosion is baked rather than shaded.
Future<ui.Image> _bakeFlameAtlas() async {
  const grid = 8;
  const cell = 96;
  const size = grid * cell;
  const frames = grid * grid;
  final pixels = Uint8List(size * size * 4);

  final warpNoise = FastNoiseLite()
    ..seed = 7
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  final mainNoise = FastNoiseLite()
    ..seed = 8
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    // Small per-frame steps keep adjacent frames similar; the sequence plays
    // at ~40-50 fps over a particle's life, so large steps read as strobing.
    final evolve = f * 0.055;
    final scroll = f * 0.10;

    // Lifecycle envelope: the flame grows in quickly, then its base lifts off
    // the ground late in life while the whole tongue shortens and erodes.
    final grow = _smoothstep(0.0, 0.18, t);
    final baseY = 0.5 * pow(_smoothstep(0.40, 1.0, t), 1.2);
    final height =
        0.92 * (0.3 + 0.7 * grow) * (1 - 0.35 * _smoothstep(0.5, 1.0, t));
    final erosion = 0.12 + 0.55 * _smoothstep(0.35, 1.0, t);
    final cooling = 1.0 - 0.40 * _smoothstep(0.45, 1.0, t);

    final cellX = (f % grid) * cell;
    final cellY = (f ~/ grid) * cell;
    for (var py = 0; py < cell; py++) {
      // Row 0 renders at the sprite's top, so flip to a bottom-up y.
      final y = 1.0 - (py + 0.5) / cell;
      final rowBase = ((cellY + py) * size + cellX) * 4;
      for (var px = 0; px < cell; px++) {
        final x = ((px + 0.5) / cell) * 2.0 - 1.0;

        var value = 0.0;
        var detail = 0.5;
        final h = height > 0 ? (y - baseY) / height : -1.0;
        if (h >= 0.0 && h <= 1.0) {
          // Horizontal domain warp, stronger toward the tip, makes the
          // silhouette lick and split instead of staying a teardrop.
          final w = warpNoise.getNoise3(
            x * 2.2,
            y * 2.2 - scroll * 1.6,
            evolve + 37.7,
          );
          final xw = x + w * 0.30 * (0.35 + 0.65 * h);

          final halfW =
              0.52 *
              (1 - 0.30 * t) *
              pow(1 - h, 0.65) *
              (0.30 + 0.70 * _smoothstep(0.0, 0.18, h));
          if (halfW > 1e-4) {
            final d = (xw / halfW).abs();
            final radial = (1 - d * d).clamp(0.0, 1.0);
            final n =
                mainNoise.getNoise3(xw * 2.6, y * 3.2 - scroll * 2.2, evolve) *
                    0.5 +
                0.5;
            final density = radial * (0.45 + 0.55 * n) * 1.35;
            final threshold = erosion + 0.30 * h;
            value = ((density - threshold) / 0.22).clamp(0.0, 1.0);
            detail = n;
          }
        }

        // Modulate the interior by the same noise so the core keeps hot and
        // cool filaments instead of saturating to a flat white.
        final temp =
            (value *
                    (1.12 - 0.45 * h.clamp(0.0, 1.0)) *
                    (0.68 + 0.55 * detail) *
                    cooling)
                .clamp(0.0, 1.0);
        final (r, g, b) = _blackbody(temp);
        final alpha = (value * 1.45).clamp(0.0, 1.0);
        final o = rowBase + px * 4;
        pixels[o] = (r * 255).round();
        pixels[o + 1] = (g * 255).round();
        pixels[o + 2] = (b * 255).round();
        pixels[o + 3] = (alpha * 255).round();
      }
    }
    // Yield between frames so the loading UI stays responsive.
    if (f % 8 == 7) await Future<void>.delayed(Duration.zero);
  }
  return _imageFromPixels(pixels, size);
}

/// Bakes the 4x4 smoke flipbook (played once over life): a billowy fbm puff
/// with baked shading that is progressively eaten by a rising erosion
/// threshold, so old smoke tears apart instead of uniformly fading.
Future<ui.Image> _bakeSmokeAtlas() async {
  const grid = 4;
  const cell = 128;
  const size = grid * cell;
  const frames = grid * grid;
  final pixels = Uint8List(size * size * 4);

  final noise = FastNoiseLite()
    ..seed = 17
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;

  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    final evolve = f * 0.22;
    final erosion = 0.18 + 0.55 * _smoothstep(0.2, 1.0, t);

    final cellX = (f % grid) * cell;
    final cellY = (f ~/ grid) * cell;
    for (var py = 0; py < cell; py++) {
      final y = ((py + 0.5) / cell) * 2.0 - 1.0;
      final rowBase = ((cellY + py) * size + cellX) * 4;
      for (var px = 0; px < cell; px++) {
        final x = ((px + 0.5) / cell) * 2.0 - 1.0;
        final r2 = x * x + y * y;
        final base = (1 - r2).clamp(0.0, 1.0);

        // Billow noise (folded fbm) gives the cauliflower look.
        final n = noise.getNoise3(x * 1.9, y * 1.9, evolve);
        final billow = 1.0 - n.abs();
        final density = base * (0.35 + 0.65 * billow * billow);
        // A softer edge and a late-life fade keep eroded frames wispy rather
        // than stringy.
        final value =
            ((density - erosion) / 0.42).clamp(0.0, 1.0) *
            (1.0 - 0.45 * _smoothstep(0.5, 1.0, t));

        // Bake soft self-shading, brighter toward the puff's upper lobe.
        final shade = (0.62 + 0.38 * billow) * (0.85 - 0.15 * y);
        final o = rowBase + px * 4;
        final v = (shade.clamp(0.0, 1.0) * 255).round();
        pixels[o] = v;
        pixels[o + 1] = v;
        pixels[o + 2] = v;
        pixels[o + 3] = (value * 255).round();
      }
    }
    if (f % 4 == 3) await Future<void>.delayed(Duration.zero);
  }
  return _imageFromPixels(pixels, size);
}

/// Bakes the ground albedo: mottled dirt with a noisy-edged scorch circle
/// under the fire and a faint ash ring around it. The disc's planar UVs put
/// the fire at (0.5, 0.5); world radius 9 spans UV radius 0.5.
Future<ui.Image> _bakeGroundTexture() async {
  const size = 512;
  final pixels = Uint8List(size * size * 4);

  final dirtNoise = FastNoiseLite()
    ..seed = 27
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;
  final patchNoise = FastNoiseLite()
    ..seed = 28
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  for (var py = 0; py < size; py++) {
    final v = (py + 0.5) / size;
    for (var px = 0; px < size; px++) {
      final u = (px + 0.5) / size;
      final dx = u - 0.5;
      final dy = v - 0.5;
      final r = sqrt(dx * dx + dy * dy);

      // Mottled dirt: fine grain plus large soil patches drifting between
      // warm brown and dusty grey.
      final grain = dirtNoise.getNoise2(u * 60.0, v * 60.0) * 0.5 + 0.5;
      final patch = patchNoise.getNoise2(u * 7.0, v * 7.0) * 0.5 + 0.5;
      var red = 0.30 + 0.10 * grain + 0.06 * patch;
      var green = 0.24 + 0.08 * grain + 0.04 * patch;
      var blue = 0.18 + 0.06 * grain + 0.05 * (1 - patch);

      // Scorched earth under the fire, with a noise-warped edge and a faint
      // ash ring just outside the char.
      final edgeNoise = dirtNoise.getNoise2(u * 24.0, v * 24.0) * 0.012;
      final char = 1.0 - _smoothstep(0.045, 0.085, r + edgeNoise);
      final ash =
          _smoothstep(0.055, 0.085, r + edgeNoise) *
          (1.0 - _smoothstep(0.09, 0.13, r + edgeNoise));
      final charShade = 0.05 + 0.05 * grain;
      red = red + (charShade * 1.2 - red) * char;
      green = green + (charShade - green) * char;
      blue = blue + (charShade * 0.8 - blue) * char;
      red += (0.34 - red) * ash * 0.55;
      green += (0.32 - green) * ash * 0.55;
      blue += (0.30 - blue) * ash * 0.55;

      final o = (py * size + px) * 4;
      pixels[o] = (red.clamp(0.0, 1.0) * 255).round();
      pixels[o + 1] = (green.clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = (blue.clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  return _imageFromPixels(pixels, size);
}

/// Bakes the stone albedo: granite-like fbm mottling with darker ridged
/// veins. Per-stone tint and roughness come from the material.
Future<ui.Image> _bakeStoneTexture() async {
  const size = 128;
  final pixels = Uint8List(size * size * 4);

  final mottleNoise = FastNoiseLite()
    ..seed = 37
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;
  final veinNoise = FastNoiseLite()
    ..seed = 38
    ..frequency = 1.0
    ..fractalType = FractalType.ridged
    ..octaves = 3;

  for (var py = 0; py < size; py++) {
    final v = (py + 0.5) / size;
    for (var px = 0; px < size; px++) {
      final u = (px + 0.5) / size;
      final mottle = mottleNoise.getNoise2(u * 9.0, v * 9.0) * 0.5 + 0.5;
      final vein = (veinNoise.getNoise2(u * 5.0, v * 5.0) * 0.5 + 0.5);
      final grey = (0.42 + 0.30 * mottle - 0.22 * vein * vein).clamp(0.05, 1.0);
      final o = (py * size + px) * 4;
      pixels[o] = (grey * 255).round();
      pixels[o + 1] = (grey * 255).round();
      pixels[o + 2] = ((grey * 1.02).clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = 255;
    }
  }
  return _imageFromPixels(pixels, size);
}

/// A 64x64 white dot with a Gaussian falloff (slope zero at the rim), for the
/// embers and the ground glow.
Future<ui.Image> _bakeSoftDot() {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  const half = size / 2;
  const sigma = size * 0.20;
  final rim = exp(-0.5 * (half / sigma) * (half / sigma));
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x + 0.5 - half;
      final dy = y + 0.5 - half;
      final r = sqrt(dx * dx + dy * dy);
      final g = exp(-0.5 * (r / sigma) * (r / sigma));
      final a = ((g - rim) / (1.0 - rim)).clamp(0.0, 1.0);
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = (a * 255).round();
    }
  }
  return _imageFromPixels(pixels, size);
}
