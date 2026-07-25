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
import 'package:flutter_scene/src/components/trail_component.dart';
import 'package:flutter_scene/src/geometry/primitives.dart'
    show buildIcosphereArrays;
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
import 'vfx_textures.dart';

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

/// One firefly: steers a bounded-speed wander over the grass (noise turns
/// the heading, so it can never teleport), bobbing over the terrain,
/// blinking its point light, additive sprite, and faint trail together.
class _Firefly extends Component {
  _Firefly(this.light, this.sprite, this.trail, this.phase, this.groundHeight)
    : _x = cos(phase * 2 * pi) * 4.0,
      _z = sin(phase * 2 * pi) * 4.0,
      _heading = phase * 2 * pi;

  final PointLight light;
  final SpriteMaterial sprite;
  final TrailComponent trail;
  final double phase;
  final double Function(double x, double z) groundHeight;

  // Live tuning, pushed from the panel through _applyParams.
  double speedScale = 1.0;
  double wanderScale = 1.0;
  double blinkThreshold = 0.0;
  double lightIntensity = 1.2;
  double trailWidth = 0.07;

  final FastNoiseLite _noise = FastNoiseLite()
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  double _t = 0;
  double _x;
  double _z;
  double _heading;

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    // Meander: noise steers the heading, position integrates at a bounded
    // speed, so a firefly can dart but never teleport.
    _heading +=
        _noise.getNoise2(_t * 0.6, phase * 91.7) *
        3.2 *
        wanderScale *
        deltaSeconds;
    var dx = cos(_heading);
    var dz = sin(_heading);
    // Steer back over the grass band, away from the fire and the far edge.
    final r = sqrt(_x * _x + _z * _z);
    if (r < 2.6 || r > 6.8) {
      final outward = r < 2.6 ? 1.0 : -1.0;
      dx += (_x / max(r, 1e-3)) * outward * 1.6;
      dz += (_z / max(r, 1e-3)) * outward * 1.6;
      final len = sqrt(dx * dx + dz * dz);
      dx /= len;
      dz /= len;
      _heading = atan2(dz, dx);
    }
    final speed =
        (0.55 + 0.35 * _noise.getNoise2(_t * 0.8, phase * 3.1)) * speedScale;
    _x += dx * speed * deltaSeconds;
    _z += dz * speed * deltaSeconds;
    final y =
        groundHeight(_x, _z) +
        0.55 +
        0.3 * _noise.getNoise2(_t * 0.6, phase * 7.7);
    node.localTransform = vm.Matrix4.translation(vm.Vector3(_x, y, _z));

    // Smooth on/off pulses, each firefly on its own rhythm; the threshold
    // shifts the visible duty cycle and the trail breathes with the blink.
    final blink = _smoothstep(
      blinkThreshold,
      blinkThreshold + 0.45,
      _noise.getNoise2(_t * 0.7 + phase * 11.3, 3.3),
    );
    light.intensity = lightIntensity * blink;
    sprite.tint = vm.Vector4(1.2, 2.2, 0.55, blink);
    trail.width = trailWidth * (0.35 + 0.65 * blink);
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

/// Pulses a charred log's ember-crack emissive with slow noise, offset per
/// log, so the burnt tips breathe with the coal bed.
class _EmberPulse extends Component {
  _EmberPulse(this.material, this.phase);

  final PhysicallyBasedMaterial material;
  final double phase;
  final FastNoiseLite _noise = FastNoiseLite()
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  double _t = 0;

  @override
  void update(double deltaSeconds) {
    _t += deltaSeconds;
    final n =
        _noise.getNoise2(_t * 1.3 + phase * 17.1, phase * 5.3) * 0.5 + 0.5;
    final s = 0.4 + 0.8 * n;
    material.emissiveFactor = vm.Vector4(2.2 * s, 0.55 * s, 0.07 * s, 1.0);
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
  double _emberSpeed = 1.0;
  double _emberLife = 1.0;
  double _fogAmount = 1.28;

  // Firefly tuning (see _applyParams).
  double _fireflySpeed = 1.4;
  double _fireflyWander = 1.0;
  double _fireflyBlink = 0.54;
  double _fireflyLight = 0.53;
  double _fireflyTrailWidth = 0.02;
  double _fireflyTrailLife = 0.74;
  double _fireflyTrailGlow = 2.65;

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
  static const double _fogRate = 2.2;

  late ParticleSystem _coreSystem;
  late ParticleSystem _tongueSystem;
  late ParticleSystem _glowSystem;
  late ParticleSystem _smokeSystem;
  late ParticleSystem _emberSystem;
  late ParticleSystem _fogSystem;
  late ParticleEmitterComponent _coreEmitter;
  late ParticleEmitterComponent _tongueEmitter;
  late PreprocessedMaterial _grassMaterial;
  late PreprocessedSky _skySource;
  late PhysicallyBasedMaterial _groundMaterial;
  late TextureSource _barkAlbedo;
  late TextureSource _barkNormal;
  late TextureSource _barkRough;
  late TextureSource _emberCracks;
  late TextureSource _logRings;
  late TextureSource _splitWood;
  late Node _groundNode;
  late Node _grassNode;
  late _FirelightFlicker _flicker;
  final List<(TurbulenceModule, double)> _flameTurbs = [];
  final List<(TurbulenceModule, double)> _emberTurbs = [];
  final List<(AccelerationModule, double)> _winds = [];
  final List<(Node, double)> _fireNodes = [];
  // Stray rocks seated on the terrain (node, x, z, half height), re-seated
  // when the hill sliders rebuild the ground.
  final List<(Node, double, double, double)> _terrainRocks = [];
  final List<_Firefly> _fireflies = [];
  final List<TrailComponent> _fireflyTrails = [];

  @override
  void initState() {
    super.initState();
    // The shared-settings side of this example's look (dim moonlight, ambient
    // occlusion, the warm grade) lives in main.dart's settingsDefaults entry.
    _load();
  }

  Future<void> _load() async {
    // A moonless starry night (a procedural `.fmat` sky: hash-grid stars and
    // an fbm milky way). The fire's own point light carries the scene, so
    // the image-based ambient stays near black and a faint blue directional
    // stands in for skylight.
    _skySource = await loadFmatSky('assets/night_sky.fmat');
    scene.skybox = Skybox(_skySource);
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
      await gpuTextureFromImage(await bakeFlameAtlas()),
    );
    final smokeAtlas = GpuTextureSource(
      await gpuTextureFromImage(await bakeSmokeAtlas()),
    );
    final dot = GpuTextureSource(
      await gpuTextureFromImage(await bakeSoftDot()),
    );
    final groundTexture = GpuTextureSource(
      await gpuTextureFromImage(await _bakeGroundTexture()),
    );
    final groundNormal = GpuTextureSource(
      await gpuTextureFromImage(await _bakeGroundNormal()),
    );
    final groundRough = GpuTextureSource(
      await gpuTextureFromImage(await _bakeGroundRoughness()),
    );
    final stoneTexture = GpuTextureSource(
      await gpuTextureFromImage(await _bakeStoneTexture()),
    );
    _barkAlbedo = GpuTextureSource(
      await gpuTextureFromImage(await _bakeBarkAlbedo()),
    );
    _barkNormal = GpuTextureSource(
      await gpuTextureFromImage(await _bakeBarkNormal()),
    );
    _barkRough = GpuTextureSource(
      await gpuTextureFromImage(await _bakeBarkRoughness()),
    );
    _emberCracks = GpuTextureSource(
      await gpuTextureFromImage(await _bakeEmberCracks()),
    );
    _logRings = GpuTextureSource(
      await gpuTextureFromImage(await _bakeLogRings()),
    );
    _splitWood = GpuTextureSource(
      await gpuTextureFromImage(await _bakeSplitWood()),
    );
    _grassMaterial = await loadFmatMaterial('assets/campfire_grass.fmat');

    _buildCampsite(groundTexture, groundNormal, groundRough, stoneTexture);

    scene.add(_flameCore(flameAtlas));
    scene.add(_flameTongues(flameAtlas));
    scene.add(_glow(dot));
    scene.add(_smoke(smokeAtlas));
    scene.add(_embers(dot));
    scene.add(_groundFog(smokeAtlas));

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

    // Fireflies drifting over the grass, each pairing a green point light
    // with a small additive sprite and a faint ribbon trail, all blinking in
    // sync.
    for (var i = 0; i < 4; i++) {
      final flyLight = PointLight(
        color: vm.Vector3(0.55, 1.0, 0.35),
        intensity: 0.0,
        range: 3.0,
      );
      final flySprite = Sprite(texture: dot, width: 0.045, height: 0.045);
      flySprite.material.blendMode = SpriteBlendMode.additive;
      final flyTrail = TrailComponent(
        width: _fireflyTrailWidth,
        lifetime: _fireflyTrailLife,
        minVertexDistance: 0.03,
        maxPoints: 48,
      );
      final fly = _Firefly(
        flyLight,
        flySprite.material,
        flyTrail,
        i / 4,
        _groundHeight,
      );
      _fireflies.add(fly);
      _fireflyTrails.add(flyTrail);
      scene.add(
        Node(mesh: flySprite.mesh)
          ..addComponent(PointLightComponent(flyLight))
          ..add(Node()..addComponent(flyTrail))
          ..addComponent(fly),
      );
    }

    // Prewarm only after the panel defaults are applied, so the scene opens
    // already-populated with particles that were simulated under the same
    // parameters they will keep running with (a constructor-time prewarm
    // would bake the raw base turbulence and lifetimes into the first
    // seconds of the fire).
    _applyParams();
    _prewarm(_coreSystem, 1.5);
    _prewarm(_tongueSystem, 1.0);
    _prewarm(_glowSystem, 1.0);
    _prewarm(_smokeSystem, 5.0);
    _prewarm(_emberSystem, 2.0);
    _prewarm(_fogSystem, 12.0);
    if (mounted) setState(() => _ready = true);
  }

  // Advances a system in max-frame-sized chunks (step clamps a single call).
  static void _prewarm(ParticleSystem system, double seconds) {
    var remaining = seconds;
    while (remaining > 0) {
      final chunk = min(0.25, remaining);
      system.step(chunk);
      remaining -= chunk;
    }
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
    _fogSystem.spawner.rate = _fogRate * _fogAmount;
    _emberSystem.startSpeed = UniformFloat(
      1.2 * _emberSpeed,
      2.6 * _emberSpeed,
    );
    _emberSystem.lifetime = UniformFloat(1.1 * _emberLife, 2.1 * _emberLife);
    // Fireflies: motion, blink duty cycle (the noise threshold shifts how
    // often they light up), light brightness, and their trails.
    for (final fly in _fireflies) {
      fly
        ..speedScale = _fireflySpeed
        ..wanderScale = _fireflyWander
        ..blinkThreshold = 0.75 - 1.5 * _fireflyBlink
        ..lightIntensity = _fireflyLight
        ..trailWidth = _fireflyTrailWidth;
    }
    final g = _fireflyTrailGlow;
    for (final trail in _fireflyTrails) {
      trail
        ..lifetime = _fireflyTrailLife
        ..colorOverTrail = ColorGradient([
          ColorStop(0.0, vm.Vector4(2.0 * g, 3.6 * g, 0.9 * g, 0.6)),
          ColorStop(0.6, vm.Vector4(1.2 * g, 2.2 * g, 0.55 * g, 0.35)),
          ColorStop(1.0, vm.Vector4(0.5 * g, 1.0 * g, 0.25 * g, 0.0)),
        ]);
    }
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

  // Rebuilds the terrain-shaped geometry (ground mesh, grass roots, rock
  // seats) after the hill sliders change.
  void _rebuildTerrain() {
    _groundNode.mesh = Mesh(_buildGroundGeometry(), _groundMaterial);
    _grassNode.mesh = Mesh(_buildGrassGeometry(), _grassMaterial);
    _seatTerrainRocks();
  }

  // Drops each stray rock onto the terrain surface, keeping its baked
  // rotation and scale (only the translation moves).
  void _seatTerrainRocks() {
    for (final (node, x, z, halfHeight) in _terrainRocks) {
      node.localTransform.setTranslationRaw(
        x,
        _groundHeight(x, z) + halfHeight,
        z,
      );
    }
  }

  // A piece of split firewood: a wedge of trunk with bark on the outer arc
  // (lumpy, bark UVs), pale split-wood faces where the round was cleaved,
  // and wedge-slice end caps whose growth rings center on the tree's axis.
  // A char gradient bakes into the vertex colors toward the tip (row 0, the
  // end in the fire). Returns (bark arc, split faces, end caps), which carry
  // different materials.
  (MeshGeometry, MeshGeometry, MeshGeometry) _logGeometry(int seed) {
    const arcSegs = 10;
    const hs = 9;
    const length = 0.95;
    final noise = FastNoiseLite()
      ..seed = seed
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 3;
    final rng = Random(seed);
    final wedge = 1.9 + rng.nextDouble() * 1.2;
    final theta0 = rng.nextDouble() * 2 * pi;
    const charcoal = (0.05, 0.045, 0.04);

    double radiusAt(double t) => 0.082 + 0.012 * t;
    double lumpAt(double theta, double t) =>
        1.0 +
        0.08 * noise.getNoise3(cos(theta) * 2.2, sin(theta) * 2.2, t * 3.5);
    double charAt(double t, double jitterA, double jitterB) =>
        (_smoothstep(
                  0.55,
                  0.92,
                  1 - t + 0.08 * noise.getNoise2(t * 3.0, 41.0),
                ) +
                0.15 * noise.getNoise2(jitterA * 3.0, jitterB * 5.0 + 9.0))
            .clamp(0.0, 1.0);
    List<double> charColor(double char) => [
      1.0 + (charcoal.$1 - 1.0) * char,
      1.0 + (charcoal.$2 - 1.0) * char,
      1.0 + (charcoal.$3 - 1.0) * char,
      1.0,
    ];

    // Bark: the outer arc only.
    final positions = <double>[];
    final normals = <double>[];
    final texCoords = <double>[];
    final colors = <double>[];
    final indices = <int>[];
    const columns = arcSegs + 1;
    for (var r = 0; r <= hs; r++) {
      final t = r / hs; // 0 at the tip (in the fire), 1 at the ground end.
      final y = length / 2 - length * t;
      for (var s = 0; s <= arcSegs; s++) {
        final theta = theta0 + wedge * s / arcSegs;
        final ct = cos(theta);
        final st = sin(theta);
        final radius = radiusAt(t) * lumpAt(theta, t);
        positions.addAll([ct * radius, y, st * radius]);
        final n = vm.Vector3(ct, 0.06, st)..normalize();
        normals.addAll([n.x, n.y, n.z]);
        texCoords.addAll([s / arcSegs * (wedge / pi), t]);
        colors.addAll(charColor(charAt(t, ct, st)));
      }
    }
    for (var r = 0; r < hs; r++) {
      for (var s = 0; s < arcSegs; s++) {
        final a = r * columns + s;
        final b = a + 1;
        final c = a + columns;
        final d = c + 1;
        indices.addAll([a, c, b, b, c, d]);
      }
    }
    final bark = MeshGeometry.fromArrays(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      texCoords: Float32List.fromList(texCoords),
      colors: Float32List.fromList(colors),
      indices: indices,
    );

    // Split faces: two flat planes from the axis out to the bark rim, grain
    // running along the length.
    final fp = <double>[];
    final fn = <double>[];
    final fuv = <double>[];
    final fc = <double>[];
    final fi = <int>[];
    void addFace(double theta, bool flip) {
      final ct = cos(theta);
      final st = sin(theta);
      // The face's outward normal is perpendicular to the split plane.
      final n = flip ? vm.Vector3(st, 0, -ct) : vm.Vector3(-st, 0, ct);
      final base = fp.length ~/ 3;
      for (var r = 0; r <= hs; r++) {
        final t = r / hs;
        final y = length / 2 - length * t;
        final rim = radiusAt(t) * lumpAt(theta, t);
        fp.addAll([0, y, 0, ct * rim, y, st * rim]);
        fn.addAll([n.x, n.y, n.z, n.x, n.y, n.z]);
        fuv.addAll([0.0, t, 1.0, t]);
        final char = charAt(t, ct, st);
        fc.addAll([...charColor(char), ...charColor(char)]);
      }
      for (var r = 0; r < hs; r++) {
        final a = base + r * 2;
        final b = a + 1;
        final c = a + 2;
        final d = a + 3;
        fi.addAll(flip ? [a, b, c, c, b, d] : [a, c, b, b, c, d]);
      }
    }

    addFace(theta0, true);
    addFace(theta0 + wedge, false);
    final flats = MeshGeometry.fromArrays(
      positions: Float32List.fromList(fp),
      normals: Float32List.fromList(fn),
      texCoords: Float32List.fromList(fuv),
      colors: Float32List.fromList(fc),
      indices: fi,
    );

    // End caps: wedge slices fanned from the axis, with the ring texture's
    // center at the apex so the growth rings read as the tree's core.
    final cp = <double>[];
    final cn = <double>[];
    final cuv = <double>[];
    final cc = <double>[];
    final ci = <int>[];
    void addCap(double t, double ny, double char) {
      final y = length / 2 - length * t;
      final apex = cp.length ~/ 3;
      cp.addAll([0, y, 0]);
      cn.addAll([0, ny, 0]);
      cuv.addAll([0.5, 0.5]);
      cc.addAll(charColor(char));
      final rim = cp.length ~/ 3;
      const uvScale = 0.5 / 0.094;
      for (var s = 0; s <= arcSegs; s++) {
        final theta = theta0 + wedge * s / arcSegs;
        final radius = radiusAt(t) * lumpAt(theta, t);
        cp.addAll([cos(theta) * radius, y, sin(theta) * radius]);
        cn.addAll([0, ny, 0]);
        cuv.addAll([
          0.5 + cos(theta) * radius * uvScale,
          0.5 + sin(theta) * radius * uvScale,
        ]);
        cc.addAll(charColor(char));
      }
      for (var s = 0; s < arcSegs; s++) {
        final r0 = rim + s;
        final r1 = rim + s + 1;
        ci.addAll(ny > 0 ? [apex, r0, r1] : [apex, r1, r0]);
      }
    }

    // The tip cap sits in the fire, so it bakes almost fully charred.
    addCap(0.0, 1, 0.9);
    addCap(1.0, -1, 0.0);
    final caps = MeshGeometry.fromArrays(
      positions: Float32List.fromList(cp),
      normals: Float32List.fromList(cn),
      texCoords: Float32List.fromList(cuv),
      colors: Float32List.fromList(cc),
      indices: ci,
    );
    return (bark, flats, caps);
  }

  // Assembles one split log: bark arc with a per-log ember-crack material
  // (so each charred tip pulses on its own rhythm), split-wood faces, and
  // growth-ring cap children.
  Node _logNode(
    (MeshGeometry, MeshGeometry, MeshGeometry) shape,
    vm.Matrix4 transform,
    double phase,
  ) {
    final barkMaterial =
        PhysicallyBasedMaterial(
            baseColorTexture: _barkAlbedo,
            normalTexture: _barkNormal,
            metallicRoughnessTexture: _barkRough,
            emissiveTexture: _emberCracks,
          )
          ..roughnessFactor = 1.0
          ..metallicFactor = 1.0
          ..normalScale = 1.0;
    final woodMaterial = PhysicallyBasedMaterial(baseColorTexture: _splitWood)
      ..roughnessFactor = 0.8
      ..metallicFactor = 0.0;
    final capMaterial = PhysicallyBasedMaterial(baseColorTexture: _logRings)
      ..roughnessFactor = 0.85
      ..metallicFactor = 0.0;
    return Node(mesh: Mesh(shape.$1, barkMaterial), localTransform: transform)
      ..add(Node(mesh: Mesh(shape.$2, woodMaterial)))
      ..add(Node(mesh: Mesh(shape.$3, capMaterial)))
      ..addComponent(_EmberPulse(barkMaterial, phase));
  }

  // A jagged rock: an icosphere displaced by fbm noise, exploded into
  // per-face vertices so the auto-generated normals stay flat and faceted.
  MeshGeometry _rockGeometry(int seed) {
    final arrays = buildIcosphereArrays(radius: 1.0, subdivisions: 1);
    final noise = FastNoiseLite()
      ..seed = seed
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 3;
    final displaced = Float32List.fromList(arrays.positions);
    for (var i = 0; i < displaced.length; i += 3) {
      final x = displaced[i];
      final y = displaced[i + 1];
      final z = displaced[i + 2];
      final len = sqrt(x * x + y * y + z * z);
      final nx = x / len;
      final ny = y / len;
      final nz = z / len;
      final bump =
          1.0 +
          0.30 * noise.getNoise3(nx * 1.6, ny * 1.6, nz * 1.6) +
          0.10 * noise.getNoise3(nx * 4.5 + 9, ny * 4.5, nz * 4.5);
      displaced[i] = nx * bump;
      displaced[i + 1] = ny * bump;
      displaced[i + 2] = nz * bump;
    }
    final srcIndices = arrays.indices;
    final srcUv = arrays.texCoords;
    final positions = Float32List(srcIndices.length * 3);
    final texCoords = Float32List(srcIndices.length * 2);
    for (var i = 0; i < srcIndices.length; i++) {
      final v = srcIndices[i];
      positions[i * 3] = displaced[v * 3];
      positions[i * 3 + 1] = displaced[v * 3 + 1];
      positions[i * 3 + 2] = displaced[v * 3 + 2];
      if (srcUv != null) {
        texCoords[i * 2] = srcUv[v * 2];
        texCoords[i * 2 + 1] = srcUv[v * 2 + 1];
      }
    }
    return MeshGeometry.fromArrays(
      positions: positions,
      texCoords: texCoords,
      indices: List<int>.generate(srcIndices.length, (i) => i),
    );
  }

  // Ground terrain, grass, stone ring, log teepee, and a glowing coal bed.
  void _buildCampsite(
    TextureSource ground,
    TextureSource groundNormal,
    TextureSource groundRough,
    TextureSource stone,
  ) {
    _groundMaterial =
        PhysicallyBasedMaterial(
            baseColorTexture: ground,
            normalTexture: groundNormal,
            metallicRoughnessTexture: groundRough,
          )
          ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
          ..roughnessFactor = 1.0
          ..normalScale = 1.2
          ..metallicFactor = 1.0;
    _groundNode = Node(mesh: Mesh(_buildGroundGeometry(), _groundMaterial));
    scene.add(_groundNode);
    _grassNode = Node(mesh: Mesh(_buildGrassGeometry(), _grassMaterial));
    scene.add(_grassNode);

    final rng = Random(5);
    // Three jagged rock shapes shared by every stone, each placed with its
    // own tint, roughness, yaw, and squash so no two read alike.
    final rockShapes = [for (var i = 0; i < 3; i++) _rockGeometry(60 + i)];
    Node rock(double x, double y, double z, double s) {
      final warm = rng.nextDouble();
      final tint = vm.Vector4(
        0.75 + 0.25 * warm,
        0.72 + 0.13 * warm,
        0.78 - 0.18 * warm,
        1,
      );
      return Node(
        mesh: Mesh(
          rockShapes[rng.nextInt(rockShapes.length)],
          PhysicallyBasedMaterial(baseColorTexture: stone)
            ..baseColorFactor = tint
            ..roughnessFactor = 0.55 + rng.nextDouble() * 0.4
            ..metallicFactor = 0.0,
        ),
        localTransform: vm.Matrix4.translation(vm.Vector3(x, y, z))
          ..multiply(
            vm.Matrix4.rotationY(rng.nextDouble() * 2 * pi)
              ..multiply(vm.Matrix4.rotationX((rng.nextDouble() - 0.5) * 0.4))
              ..multiply(
                vm.Matrix4.diagonal3Values(
                  s * (0.85 + rng.nextDouble() * 0.3),
                  s * (0.55 + rng.nextDouble() * 0.3),
                  s,
                ),
              ),
          ),
      );
    }

    // The fire ring: a denser circle of medium stones.
    const stoneCount = 13;
    for (var i = 0; i < stoneCount; i++) {
      final a = i * 2 * pi / stoneCount + rng.nextDouble() * 0.25;
      final r = 0.95 + rng.nextDouble() * 0.14;
      final s = 0.11 + rng.nextDouble() * 0.13;
      scene.add(rock(cos(a) * r, s * 0.45, sin(a) * r, s));
    }
    // Strays scattered across the terrain, small pebbles to half-buried
    // boulders, re-seated by _rebuildTerrain when the hills change.
    for (var i = 0; i < 9; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final r = 1.9 + rng.nextDouble() * 4.8;
      final s = 0.07 + pow(rng.nextDouble(), 2.0) * 0.4;
      final x = cos(a) * r;
      final z = sin(a) * r;
      final node = rock(x, 0, z, s);
      _terrainRocks.add((node, x, z, s * 0.4));
      scene.add(node);
    }
    _seatTerrainRocks();

    // The teepee: bark-textured lumpy logs, charred where they meet the
    // fire, with pulsing ember cracks in the charred tips.
    final logShapes = [for (var i = 0; i < 3; i++) _logGeometry(80 + i)];
    const logCount = 5;
    for (var i = 0; i < logCount; i++) {
      final yaw = i * 2 * pi / logCount + rng.nextDouble() * 0.25;
      final lean = 0.66 + rng.nextDouble() * 0.10;
      final transform = vm.Matrix4.rotationY(yaw)
        ..multiply(vm.Matrix4.translation(vm.Vector3(0.20, 0.44, 0)))
        ..multiply(vm.Matrix4.rotationZ(lean));
      scene.add(
        _logNode(logShapes[i % logShapes.length], transform, i / logCount),
      );
    }
    // A collapsed log lying half-buried in the coals, charred end toward the
    // heart of the fire.
    scene.add(
      _logNode(
        logShapes[1],
        vm.Matrix4.translation(vm.Vector3(0.58, 0.09, -0.12))
          ..multiply(vm.Matrix4.rotationY(0.35))
          ..multiply(vm.Matrix4.rotationZ(1.45))
          ..multiply(vm.Matrix4.diagonal3Values(0.85, 0.85, 0.85)),
        0.5,
      ),
    );

    // Coal bed: jagged near-black shards (the same faceted rock shapes as
    // the stones, smaller and more broken) whose pulsing emissive makes the
    // base of the fire glow from within.
    const coalCount = 12;
    for (var i = 0; i < coalCount; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final r = rng.nextDouble() * 0.32;
      final s = 0.035 + rng.nextDouble() * 0.055;
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.02, 0.015, 0.01, 1)
        ..roughnessFactor = 0.9
        ..metallicFactor = 0.0;
      scene.add(
        Node(
          mesh: Mesh(rockShapes[rng.nextInt(rockShapes.length)], material),
          localTransform:
              vm.Matrix4.translation(
                vm.Vector3(cos(a) * r, s * 0.35 + 0.02, sin(a) * r),
              )..multiply(
                vm.Matrix4.rotationY(rng.nextDouble() * 2 * pi)
                  ..multiply(
                    vm.Matrix4.rotationZ((rng.nextDouble() - 0.5) * 0.8),
                  )
                  ..multiply(
                    vm.Matrix4.diagonal3Values(
                      s * (0.8 + rng.nextDouble() * 0.5),
                      s * 0.55,
                      s,
                    ),
                  ),
              ),
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
    );
    final material = SpriteMaterial(colorTexture: dot)
      ..blendMode = SpriteBlendMode.additive
      // The halo quads intersect the coal bed and ground; the soft depth
      // fade dissolves the intersection instead of clipping a hard line.
      ..softDepthFade = 1.1;
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
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.alpha
      // Soft particles: the column dissolves through the logs, terrain, and
      // grass instead of slicing them with quad edges.
      ..softDepthFade = 0.6;
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

  // Ground fog: huge, faint, slow moonlit puffs hugging the hollow. Soft
  // depth fade melts them into the hills and props, and a camera near fade
  // keeps the orbiting camera from clipping through a hard quad.
  Node _groundFog(TextureSource atlas) {
    _fogSystem = ParticleSystem(
      maxParticles: 32,
      shape: const shape.ConeShape(angle: 0.02, radius: 6.5),
      spawner: Spawner(rate: _fogRate),
      lifetime: const UniformFloat(7.0, 11.0),
      startSpeed: const UniformFloat(0.02, 0.06),
      startSize: const UniformFloat(2.6, 4.2),
      startRotation: const UniformFloat(0.0, 6.283),
      startAngularVelocity: const UniformFloat(-0.05, 0.05),
      modules: [
        _windFor(0.9),
        const RotationModule(),
        const FlipbookModule(frameCount: 16),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.8),
              const ParticleKeyframe(1.0, 1.4),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, vm.Vector4(0.30, 0.36, 0.5, 0.0)),
              ColorStop(0.25, vm.Vector4(0.30, 0.36, 0.5, 0.07)),
              ColorStop(0.75, vm.Vector4(0.26, 0.31, 0.44, 0.06)),
              ColorStop(1.0, vm.Vector4(0.22, 0.27, 0.4, 0.0)),
            ]),
          ),
        ),
      ],
      seed: 7,
    );
    final material = SpriteMaterial(colorTexture: atlas)
      ..blendMode = SpriteBlendMode.alpha
      ..softDepthFade = 1.4
      ..cameraNearFade = 2.0;
    return _emitterNode(
      _fogSystem,
      material,
      flipbookColumns: 4,
      flipbookRows: 4,
      flipbookBlend: true,
      randomFlipX: true,
      y: 0.5,
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

  // Dumps every tunable (this panel's sliders plus the shared settings
  // panel) to the log in one block, so a hand-tuned look can be copied
  // straight into code as new defaults.
  void _printSettings() {
    final s = exampleSettings;
    final ao = s.ambientOcclusion;
    final grading = s.colorGrading;
    debugPrint('''
Campfire settings dump:
  intensity: $_intensity
  flameScale: $_flameScale
  flameWidth: $_flameWidth
  flipbookSpeed: $_flipbookSpeed
  fireHeight: $_fireHeight
  flameTurbulence: $_flameTurbulence
  emberTurbulence: $_emberTurbulence
  wind: $_wind
  smokeAmount: $_smokeAmount
  emberAmount: $_emberAmount
  emberSpeed: $_emberSpeed
  emberLife: $_emberLife
  fogAmount: $_fogAmount
  fireflySpeed: $_fireflySpeed
  fireflyWander: $_fireflyWander
  fireflyBlink: $_fireflyBlink
  fireflyLight: $_fireflyLight
  fireflyTrailWidth: $_fireflyTrailWidth
  fireflyTrailLife: $_fireflyTrailLife
  fireflyTrailGlow: $_fireflyTrailGlow
  hillFrequency: $_hillFrequency
  hillHeight: $_hillHeight
Shared settings:
  directionalLightEnabled: ${s.directionalLightEnabled}
  lightAzimuthDegrees: ${s.lightAzimuthDegrees}
  lightElevationDegrees: ${s.lightElevationDegrees}
  lightIntensity: ${s.lightIntensity}
  lightColor: ${s.lightColor.x}, ${s.lightColor.y}, ${s.lightColor.z}
  lightCastsShadow: ${s.lightCastsShadow}
  shadowSoftness: ${s.shadowSoftness}
  shadowFadeRange: ${s.shadowFadeRange}
  shadowCascadeCount: ${s.shadowCascadeCount}
  shadowMaxDistance: ${s.shadowMaxDistance}
  shadowCascadeSplitLambda: ${s.shadowCascadeSplitLambda}
  shadowMapResolution: ${s.shadowMapResolution}
  shadowDepthBias: ${s.shadowDepthBias}
  shadowNormalBias: ${s.shadowNormalBias}
  shadowAmbientStrength: ${s.shadowAmbientStrength}
  ambientOcclusion: enabled ${ao.enabled}, radius ${ao.radius}, intensity ${ao.intensity}, bias ${ao.bias}, sampleCount ${ao.sampleCount}, halfResolution ${ao.halfResolution}, specularMode ${ao.specularMode}
  colorGrading: enabled ${grading.enabled}, brightness ${grading.brightness}, contrast ${grading.contrast}, saturation ${grading.saturation}, temperature ${grading.temperature}, tint ${grading.tint}
  bloom: enabled ${s.bloom.enabled}, threshold ${s.bloom.threshold}, intensity ${s.bloom.intensity}, scatter ${s.bloom.scatter}
  chromaticAberration: enabled ${s.chromaticAberration.enabled}, intensity ${s.chromaticAberration.intensity}
  vignette: enabled ${s.vignette.enabled}, intensity ${s.vignette.intensity}, radius ${s.vignette.radius}, smoothness ${s.vignette.smoothness}
  filmGrain: enabled ${s.filmGrain.enabled}, intensity ${s.filmGrain.intensity}
  antiAliasingMode: ${s.antiAliasingMode}
  renderScale: ${s.renderScale}''');
  }

  Widget _buildPanel() {
    return ExamplePanelCard(
      icon: Icons.local_fire_department,
      title: 'Campfire',
      width: 330,
      maxBodyHeight: 420,
      trailing: IconButton(
        icon: const Icon(Icons.receipt_long, size: 18, color: Colors.white70),
        tooltip: 'Print all settings to the log',
        onPressed: _printSettings,
      ),
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
            label: 'Ember speed',
            value: _emberSpeed,
            min: 0.3,
            max: 2.5,
            onChanged: (v) => setState(() {
              _emberSpeed = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Ember life',
            value: _emberLife,
            min: 0.3,
            max: 2.5,
            onChanged: (v) => setState(() {
              _emberLife = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Fog',
            value: _fogAmount,
            min: 0.0,
            max: 2.0,
            onChanged: (v) => setState(() {
              _fogAmount = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Fly speed',
            value: _fireflySpeed,
            min: 0.2,
            max: 3.0,
            onChanged: (v) => setState(() {
              _fireflySpeed = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Fly wander',
            value: _fireflyWander,
            min: 0.2,
            max: 3.0,
            onChanged: (v) => setState(() {
              _fireflyWander = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Fly blink',
            value: _fireflyBlink,
            min: 0.0,
            max: 1.0,
            onChanged: (v) => setState(() {
              _fireflyBlink = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Fly light',
            value: _fireflyLight,
            min: 0.0,
            max: 4.0,
            onChanged: (v) => setState(() {
              _fireflyLight = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Trail width',
            value: _fireflyTrailWidth,
            min: 0.0,
            max: 0.25,
            onChanged: (v) => setState(() {
              _fireflyTrailWidth = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Trail life',
            value: _fireflyTrailLife,
            min: 0.2,
            max: 3.0,
            onChanged: (v) => setState(() {
              _fireflyTrailLife = v;
              _applyParams();
            }),
          ),
          _SliderRow(
            label: 'Trail glow',
            value: _fireflyTrailGlow,
            min: 0.0,
            max: 3.0,
            onChanged: (v) => setState(() {
              _fireflyTrailGlow = v;
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
              final t = elapsed.inMicroseconds / 1e6;
              _grassMaterial.parameters.setFloat('time', t);
              // Drives the sky's star twinkle and cloud drift.
              _skySource.parameters.setFloat('time', t);
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
      // Pale ash lumps scattered through the char.
      final ashLump = _smoothstep(0.62, 0.85, grain) * char;
      red += (0.24 - red) * ashLump;
      green += (0.23 - green) * ashLump;
      blue += (0.22 - blue) * ashLump;
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
  return vfxImageFromPixels(pixels, size);
}

/// Bakes the ground's tangent-space normal map from the same grain and patch
/// noise as the albedo, so pebbly micro-relief catches the grazing
/// firelight.
Future<ui.Image> _bakeGroundNormal() async {
  const size = 512;
  final pixels = Uint8List(size * size * 4);
  final grainNoise = FastNoiseLite()
    ..seed = 27
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;
  final patchNoise = FastNoiseLite()
    ..seed = 28
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  double height(double u, double v) {
    final grain = grainNoise.getNoise2(u * 60.0, v * 60.0);
    final patch = patchNoise.getNoise2(u * 7.0, v * 7.0);
    return 0.012 * grain + 0.02 * patch;
  }

  const eps = 1.0 / size;
  const strength = 90.0;
  for (var py = 0; py < size; py++) {
    final v = (py + 0.5) / size;
    for (var px = 0; px < size; px++) {
      final u = (px + 0.5) / size;
      final du = height(u + eps, v) - height(u - eps, v);
      final dv = height(u, v + eps) - height(u, v - eps);
      final n = vm.Vector3(-du * strength, -dv * strength, 1.0)..normalize();
      final o = (py * size + px) * 4;
      pixels[o] = ((n.x * 0.5 + 0.5) * 255).round();
      pixels[o + 1] = ((n.y * 0.5 + 0.5) * 255).round();
      pixels[o + 2] = ((n.z * 0.5 + 0.5) * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  return vfxImageFromPixels(pixels, size);
}

/// Bakes the ground's metallic-roughness map (roughness in G, metallic in
/// B): rough dirt, slightly polished ash and char where the fire has baked
/// the soil.
Future<ui.Image> _bakeGroundRoughness() async {
  const size = 256;
  final pixels = Uint8List(size * size * 4);
  final grainNoise = FastNoiseLite()
    ..seed = 27
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;
  for (var py = 0; py < size; py++) {
    final v = (py + 0.5) / size;
    for (var px = 0; px < size; px++) {
      final u = (px + 0.5) / size;
      final dx = u - 0.5;
      final dy = v - 0.5;
      final r = sqrt(dx * dx + dy * dy);
      final grain = grainNoise.getNoise2(u * 60.0, v * 60.0) * 0.5 + 0.5;
      final edgeNoise = grainNoise.getNoise2(u * 24.0, v * 24.0) * 0.012;
      // Dirt stays fully rough (a specular sheen reads as wet plastic under
      // the point light); only the fire-baked char tightens slightly.
      final char = 1.0 - _smoothstep(0.045, 0.085, r + edgeNoise);
      var rough = 0.92 + 0.08 * grain;
      rough += (0.78 - rough) * char;
      final o = (py * size + px) * 4;
      pixels[o] = 0;
      pixels[o + 1] = (rough.clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = 0;
      pixels[o + 3] = 255;
    }
  }
  return vfxImageFromPixels(pixels, size);
}

/// Samples bark ridge noise seamlessly around the log: u maps to a circle in
/// noise space (so the u = 0/1 seam vanishes) and v runs along the length.
/// [noise] should be ridged fbm; the result is remapped to 0..1 where 1 is a
/// ridge crest and 0 a fissure.
double _barkRidge(FastNoiseLite noise, double u, double v) {
  final a = u * 2 * pi;
  return (noise.getNoise3(cos(a) * 4.5, sin(a) * 4.5, v * 2.2) * 0.5 + 0.5)
      .clamp(0.0, 1.0);
}

FastNoiseLite _barkNoise(int seed) => FastNoiseLite()
  ..seed = seed
  ..frequency = 1.0
  ..fractalType = FractalType.ridged
  ..octaves = 3;

/// Bakes the bark albedo (256x512, u wraps the trunk twice, v runs along the
/// log): vertical striations from ridged noise, deep fissures dark, ridge
/// crests warm brown, with large-scale patchiness.
Future<ui.Image> _bakeBarkAlbedo() async {
  const w = 256;
  const h = 512;
  final pixels = Uint8List(w * h * 4);
  final ridgeNoise = _barkNoise(71);
  final patchNoise = FastNoiseLite()
    ..seed = 72
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  for (var py = 0; py < h; py++) {
    final v = (py + 0.5) / h;
    for (var px = 0; px < w; px++) {
      final u = (px + 0.5) / w;
      final ridge = _barkRidge(ridgeNoise, u, v);
      final patch =
          patchNoise.getNoise3(cos(u * 2 * pi), sin(u * 2 * pi), v * 5.0) *
              0.5 +
          0.5;
      final shade = 0.75 + 0.25 * patch;
      final red = (0.13 + 0.25 * ridge) * shade;
      final green = (0.09 + 0.19 * ridge) * shade;
      final blue = (0.06 + 0.13 * ridge) * shade;
      final o = (py * w + px) * 4;
      pixels[o] = (red.clamp(0.0, 1.0) * 255).round();
      pixels[o + 1] = (green.clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = (blue.clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the bark tangent-space normal map from the same ridge field, strong
/// across the striations so the fissures catch the raking firelight.
Future<ui.Image> _bakeBarkNormal() async {
  const w = 256;
  const h = 512;
  final pixels = Uint8List(w * h * 4);
  final ridgeNoise = _barkNoise(71);
  const eps = 1.0 / w;
  const strength = 6.0;
  for (var py = 0; py < h; py++) {
    final v = (py + 0.5) / h;
    for (var px = 0; px < w; px++) {
      final u = (px + 0.5) / w;
      final du =
          _barkRidge(ridgeNoise, u + eps, v) -
          _barkRidge(ridgeNoise, u - eps, v);
      final dv =
          _barkRidge(ridgeNoise, u, v + eps) -
          _barkRidge(ridgeNoise, u, v - eps);
      final n = vm.Vector3(-du * strength, -dv * strength, 1.0)..normalize();
      final o = (py * w + px) * 4;
      pixels[o] = ((n.x * 0.5 + 0.5) * 255).round();
      pixels[o + 1] = ((n.y * 0.5 + 0.5) * 255).round();
      pixels[o + 2] = ((n.z * 0.5 + 0.5) * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the bark metallic-roughness map: fissures fully rough, ridge crests
/// slightly smoother.
Future<ui.Image> _bakeBarkRoughness() async {
  const w = 128;
  const h = 256;
  final pixels = Uint8List(w * h * 4);
  final ridgeNoise = _barkNoise(71);
  for (var py = 0; py < h; py++) {
    final v = (py + 0.5) / h;
    for (var px = 0; px < w; px++) {
      final u = (px + 0.5) / w;
      final ridge = _barkRidge(ridgeNoise, u, v);
      final o = (py * w + px) * 4;
      pixels[o] = 0;
      pixels[o + 1] = ((0.98 - 0.18 * ridge).clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = 0;
      pixels[o + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the ember-crack emissive map: thin bright fissure lines masked to
/// the charred tip end (low v), plus a faint all-over glow at the very tip.
/// Cracks follow the bark fissures, so the glow reads as the wood splitting.
Future<ui.Image> _bakeEmberCracks() async {
  const w = 256;
  const h = 512;
  final pixels = Uint8List(w * h * 4);
  final ridgeNoise = _barkNoise(71);
  for (var py = 0; py < h; py++) {
    final v = (py + 0.5) / h;
    // v = 0 is the tip in the fire.
    final tipMask = 1.0 - _smoothstep(0.10, 0.30, v);
    for (var px = 0; px < w; px++) {
      final u = (px + 0.5) / w;
      final ridge = _barkRidge(ridgeNoise, u, v);
      // Fissures (low ridge value) crack open and glow.
      final crack = _smoothstep(0.22, 0.05, ridge);
      final glow = (crack * tipMask + 0.25 * (1.0 - _smoothstep(0.0, 0.08, v)))
          .clamp(0.0, 1.0);
      final o = (py * w + px) * 4;
      pixels[o] = (glow * 255).round();
      pixels[o + 1] = (glow * 0.45 * 255).round();
      pixels[o + 2] = (glow * 0.10 * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the split-wood face: pale cleaved wood with long fibrous grain
/// streaks running the length of the log (v), torn and uneven the way an
/// axe leaves it.
Future<ui.Image> _bakeSplitWood() async {
  const w = 128;
  const h = 512;
  final pixels = Uint8List(w * h * 4);
  final grainNoise = FastNoiseLite()
    ..seed = 74
    ..frequency = 1.0
    ..fractalType = FractalType.ridged
    ..octaves = 3;
  final tearNoise = FastNoiseLite()
    ..seed = 75
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  for (var py = 0; py < h; py++) {
    final v = (py + 0.5) / h;
    for (var px = 0; px < w; px++) {
      final u = (px + 0.5) / w;
      // Long streaks: high frequency across the face, low along the length,
      // wavering slightly so the grain is not ruler-straight.
      final waver = 0.06 * tearNoise.getNoise2(u * 3.0, v * 1.5);
      final grain =
          grainNoise.getNoise2((u + waver) * 14.0, v * 2.0) * 0.5 + 0.5;
      final tear = tearNoise.getNoise2(u * 6.0, v * 9.0) * 0.5 + 0.5;
      final shade = (0.62 + 0.30 * grain) * (0.82 + 0.18 * tear);
      final o = (py * w + px) * 4;
      pixels[o] = ((0.72 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 1] = ((0.57 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = ((0.38 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = 255;
    }
    if (py % 128 == 127) await Future<void>.delayed(Duration.zero);
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the cut-end growth rings: concentric bands jittered by noise over a
/// pale sapwood base.
Future<ui.Image> _bakeLogRings() async {
  const size = 128;
  final pixels = Uint8List(size * size * 4);
  final jitter = FastNoiseLite()
    ..seed = 73
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 2;
  for (var py = 0; py < size; py++) {
    final v = (py + 0.5) / size - 0.5;
    for (var px = 0; px < size; px++) {
      final u = (px + 0.5) / size - 0.5;
      final r = sqrt(u * u + v * v) * 2.0;
      final wobble = 0.06 * jitter.getNoise2(u * 6.0, v * 6.0);
      final ring = 0.5 + 0.5 * sin((r + wobble) * 44.0);
      final shade = 0.72 + 0.24 * pow(ring, 2.0) - 0.18 * r;
      final o = (py * size + px) * 4;
      pixels[o] = ((0.62 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 1] = ((0.48 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 2] = ((0.32 * shade).clamp(0.0, 1.0) * 255).round();
      pixels[o + 3] = 255;
    }
  }
  return vfxImageFromPixels(pixels, size);
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
  return vfxImageFromPixels(pixels, size);
}
