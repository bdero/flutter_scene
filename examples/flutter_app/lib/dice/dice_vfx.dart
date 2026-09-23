import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// The dice example's particle and screen effects. Every effect is a
/// short-lived node; call [update] each tick to reap the finished ones.
class DiceVfx {
  DiceVfx(this.scene);

  final Scene scene;
  final math.Random _random = math.Random();

  /// Whether sprites add into the scene or alpha-blend over it.
  ///
  /// Additive sprites write alpha 0, and the resolve keeps the scene's alpha,
  /// so over a transparent clear they vanish once Flutter composites the
  /// view. Turn this on only when an opaque backdrop is in the scene.
  // TODO(bloom): bloom has the same gap, it adds color but never raises alpha,
  // so a glow cannot spill onto the widgets in the composited mode. Raising
  // alpha by the bloom's luminance in the resolve would fix it engine-side.
  bool additive = false;

  late final Texture2D _dot;
  late final Texture2D _star;
  late final Texture2D _ring;
  bool _ready = false;

  // Live effect nodes with the time they may be removed.
  final List<({Node node, double deadline})> _live = [];
  final List<_RingPulse> _rings = [];
  final List<_Shockwave> _shockwaves = [];
  double _time = 0.0;

  /// Bakes the sprite textures. Call after `Scene.initializeStaticResources()`.
  void load() {
    _dot = _bakeDot(64);
    _star = _bakeStar(96);
    _ring = _bakeRing(128);
    _ready = true;
  }

  /// Reaps finished effects and advances the ones the scene does not drive.
  void update(double dt) {
    _time += dt;
    _live.removeWhere((entry) {
      if (_time < entry.deadline) return false;
      scene.remove(entry.node);
      return true;
    });
    for (final pulse in _rings) {
      pulse.advance(dt);
    }
    _rings.removeWhere((pulse) {
      if (!pulse.done) return false;
      scene.remove(pulse.node);
      return true;
    });
    for (final wave in _shockwaves) {
      wave.advance(dt);
    }
    _shockwaves.removeWhere((wave) {
      if (!wave.done) return false;
      scene.screenDistortion.pulses.remove(wave.pulse);
      return true;
    });
    scene.screenDistortion.enabled = _shockwaves.isNotEmpty;
  }

  /// A quick burst of bright stars over a die that just counted.
  void sparkle(vm.Vector3 position, vm.Vector4 color, {double scale = 1.0}) {
    if (!_ready) return;
    final system = ParticleSystem(
      maxParticles: 40,
      shape: SphereEmitterShape(radius: 0.22 * scale, surfaceOnly: true),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 22)]),
      looping: false,
      duration: 0.2,
      lifetime: const UniformFloat(0.45, 0.8),
      startSpeed: UniformFloat(1.6 * scale, 3.6 * scale),
      startSize: UniformFloat(0.14 * scale, 0.26 * scale),
      startRotation: const UniformFloat(0.0, math.pi),
      startAngularVelocity: const UniformFloat(-6.0, 6.0),
      gravity: vm.Vector3(0, -5.0, 0),
      modules: [
        LinearDragModule(2.2),
        const RotationModule(),
        SizeOverLifeModule(
          CurveFloat(
            ParticleCurve([
              const ParticleKeyframe(0.0, 0.4),
              const ParticleKeyframe(0.15, 1.0),
              const ParticleKeyframe(1.0, 0.0),
            ]),
          ),
        ),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, _hdr(vm.Vector4(1.0, 0.95, 0.8, 1.0), 4.0)),
              ColorStop(0.3, _hdr(color, 3.0)),
              ColorStop(1.0, _hdr(color, 1.2)..w = 0.0),
            ]),
          ),
        ),
      ],
      seed: _random.nextInt(1 << 30),
    );
    final material = SpriteMaterial(colorTexture: _star)..blendMode = _blend;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..randomFlipX = true;
    _spawn(position, emitter, lifetime: 1.2);
  }

  /// A ring of embers thrown out along the table, for a matched die.
  void emberRing(vm.Vector3 position, vm.Vector4 color) {
    if (!_ready) return;
    final system = ParticleSystem(
      maxParticles: 64,
      shape: const SphereEmitterShape(radius: 0.15, surfaceOnly: true),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 48)]),
      looping: false,
      duration: 0.2,
      lifetime: const UniformFloat(0.5, 0.9),
      startSpeed: const UniformFloat(4.0, 7.0),
      startSize: const UniformFloat(0.05, 0.09),
      gravity: vm.Vector3(0, -6.0, 0),
      modules: [
        LinearDragModule(3.0),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0.2))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, _hdr(vm.Vector4(1.0, 0.92, 0.72, 1.0), 5.0)),
              ColorStop(0.25, _hdr(color, 4.0)),
              ColorStop(1.0, _hdr(color, 1.0)..w = 0.0),
            ]),
          ),
        ),
      ],
      seed: _random.nextInt(1 << 30),
    );
    final material = SpriteMaterial(colorTexture: _dot)..blendMode = _blend;
    final emitter = ParticleEmitterComponent(system: system, material: material)
      ..facing = BillboardFacing.velocityStretched
      ..velocityStretch = 0.04;
    // Flatten the burst so it skims the table.
    final node = _spawn(position, emitter, lifetime: 1.2);
    node.localTransform = vm.Matrix4.compose(
      position,
      vm.Quaternion.identity(),
      vm.Vector3(1.0, 0.25, 1.0),
    );
    ringPulse(position, color, radius: 1.6);
  }

  /// A flat ring that expands and fades out on the table.
  void ringPulse(
    vm.Vector3 position,
    vm.Vector4 color, {
    double radius = 2.0,
    double duration = 0.5,
  }) {
    if (!_ready) return;
    final sprite = Sprite(
      texture: _ring,
      color: _hdr(color, 2.5),
      blendMode: _blend,
    );
    final node = Node(
      mesh: sprite.mesh,
      localTransform: vm.Matrix4.translation(position + vm.Vector3(0, 0.04, 0)),
    )..shadowCastingMode = ShadowCastingMode.off;
    scene.add(node);
    _rings.add(_RingPulse(node, sprite, radius, duration, _hdr(color, 2.5)));
  }

  /// Confetti fired up out of the score and raining down on the table, plus
  /// a glitter burst. The slabs are real meshes, so they cast shadows.
  void confetti(vm.Vector3 position, List<vm.Vector4> colors) {
    if (!_ready) return;
    for (var i = 0; i < colors.length; i++) {
      final color = colors[i];
      final system = ParticleSystem(
        maxParticles: 36,
        shape: const ConeEmitterShape(angle: 0.55, radius: 0.2),
        spawner: Spawner(bursts: [ParticleBurst(time: 0.02 * i, count: 26)]),
        looping: false,
        duration: 0.4,
        lifetime: const UniformFloat(1.5, 2.1),
        startSpeed: const UniformFloat(6.5, 11.0),
        startSize: const UniformFloat(0.7, 1.3),
        startAngularVelocity: const UniformFloat(-22.0, 22.0),
        gravity: vm.Vector3(0, -13.0, 0),
        modules: [LinearDragModule(1.1), const RotationModule()],
        seed: _random.nextInt(1 << 30),
      );
      final material = PhysicallyBasedMaterial()
        ..baseColorFactor = color
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.55
        ..clearcoat = 0.4
        ..clearcoatRoughness = 0.3;
      final emitter = MeshParticleEmitterComponent(
        system: system,
        geometries: [
          CuboidGeometry(vm.Vector3(0.16, 0.012, 0.10)),
          CuboidGeometry(vm.Vector3(0.09, 0.012, 0.14)),
          CylinderGeometry(bottomRadius: 0.06, topRadius: 0.06, height: 0.012),
        ],
        material: material,
      );
      _spawn(position, emitter, lifetime: 2.4);
    }
    // Glitter riding the pop.
    final glitter = ParticleSystem(
      maxParticles: 120,
      shape: const ConeEmitterShape(angle: 0.7, radius: 0.1),
      spawner: Spawner(bursts: const [ParticleBurst(time: 0.0, count: 90)]),
      looping: false,
      duration: 0.2,
      lifetime: const UniformFloat(0.6, 1.3),
      startSpeed: const UniformFloat(5.0, 12.0),
      startSize: const UniformFloat(0.04, 0.08),
      gravity: vm.Vector3(0, -9.0, 0),
      modules: [
        LinearDragModule(1.6),
        SizeOverLifeModule(CurveFloat(ParticleCurve.linear(from: 1, to: 0.3))),
        ColorOverLifeModule(
          GradientColor(
            ColorGradient([
              ColorStop(0.0, _hdr(vm.Vector4(1.0, 0.9, 0.58, 1.0), 6.0)),
              ColorStop(
                0.5,
                _hdr(vm.Vector4(1.0, 0.75, 0.3, 1.0), 4.0)..w = 0.9,
              ),
              ColorStop(
                1.0,
                _hdr(vm.Vector4(1.0, 0.6, 0.2, 1.0), 2.0)..w = 0.0,
              ),
            ]),
          ),
        ),
      ],
      seed: _random.nextInt(1 << 30),
    );
    final glitterMaterial = SpriteMaterial(colorTexture: _dot)
      ..blendMode = _blend;
    _spawn(
      position,
      ParticleEmitterComponent(system: glitter, material: glitterMaterial)
        ..facing = BillboardFacing.velocityStretched
        ..velocityStretch = 0.03,
      lifetime: 1.6,
    );
  }

  /// A screen-space shockwave ring from [screenUv] (origin top-left).
  void shockwave(vm.Vector2 screenUv, {double strength = 0.035}) {
    final pulse = DistortionPulse(
      center: screenUv,
      radius: 0.0,
      thickness: 0.10,
      strength: strength,
      chromaticAberration: 0.6,
    );
    if (scene.screenDistortion.pulses.length >= 4) {
      final oldest = _shockwaves.removeAt(0);
      scene.screenDistortion.pulses.remove(oldest.pulse);
    }
    scene.screenDistortion.pulses.add(pulse);
    scene.screenDistortion.enabled = true;
    _shockwaves.add(_Shockwave(pulse, strength));
  }

  Node _spawn(
    vm.Vector3 position,
    Component emitter, {
    required double lifetime,
  }) {
    final node = Node(localTransform: vm.Matrix4.translation(position))
      ..addComponent(emitter);
    scene.add(node);
    _live.add((node: node, deadline: _time + lifetime));
    return node;
  }

  void dispose() {
    for (final entry in _live) {
      scene.remove(entry.node);
    }
    _live.clear();
    for (final pulse in _rings) {
      scene.remove(pulse.node);
    }
    _rings.clear();
    scene.screenDistortion.pulses.clear();
    scene.screenDistortion.enabled = false;
  }

  SpriteBlendMode get _blend =>
      additive ? SpriteBlendMode.additive : SpriteBlendMode.alpha;

  /// Brightens [color] for a sprite. Alpha-blended sprites keep a lower gain
  /// so their hue survives the tone curve.
  vm.Vector4 _hdr(vm.Vector4 color, double gain) {
    final g = additive ? gain : 0.4 + gain * 0.3;
    return vm.Vector4(color.x * g, color.y * g, color.z * g, 1.0);
  }

  // --- Baked sprites ------------------------------------------------------

  static Texture2D _bakeDot(int size) {
    final half = size / 2;
    final sigma = size * 0.20;
    final rim = math.exp(-0.5 * (half / sigma) * (half / sigma));
    return _bake(size, (x, y) {
      final dx = x - half, dy = y - half;
      final r = math.sqrt(dx * dx + dy * dy);
      final g = math.exp(-0.5 * (r / sigma) * (r / sigma));
      return ((g - rim) / (1.0 - rim)).clamp(0.0, 1.0);
    });
  }

  /// A four-point star with a soft core.
  static Texture2D _bakeStar(int size) {
    final half = size / 2;
    return _bake(size, (x, y) {
      final dx = (x - half) / half, dy = (y - half) / half;
      final r = math.sqrt(dx * dx + dy * dy);
      if (r >= 1) return 0.0;
      // Spikes along the axes, fatter near the middle.
      final ax = dx.abs(), ay = dy.abs();
      final spike = math.pow(1 - r, 1.2) * math.exp(-math.min(ax, ay) * 18.0);
      final core = math.exp(-r * r * 22.0);
      return (spike + core).clamp(0.0, 1.0);
    });
  }

  static Texture2D _bakeRing(int size) {
    final half = size / 2;
    return _bake(size, (x, y) {
      final dx = (x - half) / half, dy = (y - half) / half;
      final r = math.sqrt(dx * dx + dy * dy);
      final d = (r - 0.82).abs();
      final ring = math.exp(-d * d * 320.0);
      final glow = math.exp(-d * d * 40.0) * 0.35;
      return r > 1 ? 0.0 : (ring + glow).clamp(0.0, 1.0);
    });
  }

  static Texture2D _bake(int size, double Function(double x, double y) alpha) {
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final a = alpha(x + 0.5, y + 0.5);
        final i = (y * size + x) * 4;
        pixels[i] = 255;
        pixels[i + 1] = 255;
        pixels[i + 2] = 255;
        pixels[i + 3] = (a * 255).round();
      }
    }
    return Texture2D.fromPixels(
      pixels,
      size,
      size,
      sampling: const TextureSampling(
        addressMode: gpu.SamplerAddressMode.clampToEdge,
      ),
    );
  }
}

class _RingPulse {
  _RingPulse(this.node, this.sprite, this.radius, this.duration, this.color);

  final Node node;
  final Sprite sprite;
  final double radius;
  final double duration;
  final vm.Vector4 color;
  double _t = 0.0;

  bool get done => _t >= duration;

  void advance(double dt) {
    _t += dt;
    final p = (_t / duration).clamp(0.0, 1.0);
    // Fast out, then coast, while fading.
    final grow = 1 - math.pow(1 - p, 3).toDouble();
    final size = 0.3 + (radius - 0.3) * grow;
    sprite
      ..width = size
      ..height = size
      ..color = vm.Vector4(color.x, color.y, color.z, (1 - p) * (1 - p));
  }
}

class _Shockwave {
  _Shockwave(this.pulse, this.strength);

  final DistortionPulse pulse;
  final double strength;
  static const double duration = 0.55;
  double _t = 0.0;

  bool get done => _t >= duration;

  void advance(double dt) {
    _t += dt;
    final p = (_t / duration).clamp(0.0, 1.0);
    pulse
      ..radius = 0.02 + 0.55 * (1 - math.pow(1 - p, 2).toDouble())
      ..strength = strength * (1 - p) * (1 - p);
  }
}
