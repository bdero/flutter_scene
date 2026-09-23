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
  late final Texture2D _streak;
  late final Texture2D _caustic;
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
    _streak = _bakeStreak(96);
    _caustic = _bakeCaustic(128);
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

  /// Confetti fired up out of the score. The pieces flutter down, land flat
  /// on the table, rest, and fade out. They are instanced meshes, so they
  /// cast shadows on the widgets like everything else.
  void confetti(vm.Vector3 position, List<vm.Vector4> colors) {
    if (!_ready) return;
    _spawn(
      position,
      ConfettiComponent(colors: colors, seed: _random.nextInt(1 << 30)),
      lifetime: ConfettiComponent.maxLifetime,
    );
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

  /// A short dark streak where a die scuffed the table, fading out. Always
  /// alpha-blended: ink darkens what is under it in either mode.
  void skid(vm.Vector3 position, double angle, vm.Vector4 color, double size) {
    if (!_ready) return;
    final sprite = Sprite(
      texture: _streak,
      width: size * 1.6,
      height: size * 0.55,
      rotation: angle,
      color: vm.Vector4(color.x * 0.25, color.y * 0.25, color.z * 0.25, 0.55),
    );
    final node = Node(
      mesh: sprite.mesh,
      localTransform: vm.Matrix4.translation(
        vm.Vector3(position.x, 0.012, position.z),
      ),
    )..shadowCastingMode = ShadowCastingMode.off;
    scene.add(node);
    _rings.add(_RingPulse(node, sprite, size, 2.6, sprite.color, grow: false));
  }

  /// Makes a caustic pool for a glass die; drive it with [placeCaustic] and
  /// drop it with [removeCaustic].
  Caustic createCaustic(vm.Vector4 color) {
    final node = Node()..shadowCastingMode = ShadowCastingMode.off;
    final layers = <Sprite>[];
    for (var i = 0; i < 2; i++) {
      final sprite = Sprite(
        texture: _caustic,
        color: vm.Vector4(color.x, color.y, color.z, 0.0),
        blendMode: _blend,
      );
      node.add(Node(mesh: sprite.mesh));
      layers.add(sprite);
    }
    scene.add(node);
    return Caustic._(node, layers, color);
  }

  void placeCaustic(
    Caustic caustic,
    vm.Vector3 position,
    double size,
    double intensity,
    double time,
  ) {
    caustic.node.localTransform = vm.Matrix4.translation(
      vm.Vector3(position.x, 0.02, position.z),
    );
    final c = caustic.color;
    final gain = additive ? 2.2 : 0.9;
    for (var i = 0; i < caustic.layers.length; i++) {
      final sprite = caustic.layers[i];
      final wobble = 1.0 + 0.08 * math.sin(time * (1.7 + i) + i * 2.1);
      sprite
        ..width = size * wobble
        ..height = size * (2.0 - wobble)
        ..rotation = time * (i == 0 ? 0.35 : -0.5) + i * 1.3
        ..color = vm.Vector4(
          c.x * gain,
          c.y * gain,
          c.z * gain,
          intensity * (i == 0 ? 0.55 : 0.4),
        );
    }
  }

  void removeCaustic(Caustic caustic) => scene.remove(caustic.node);

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

  /// A soft elongated smear, the skid mark.
  static Texture2D _bakeStreak(int size) {
    final half = size / 2;
    return _bake(size, (x, y) {
      final dx = (x - half) / half, dy = (y - half) / half;
      final d = math.sqrt(dx * dx * 0.5 + dy * dy * 3.0);
      return math.exp(-d * d * 2.2).clamp(0.0, 1.0) * (1 - d).clamp(0.0, 1.0);
    });
  }

  /// Bright ridges between random cells, the look of light focused through
  /// rippled glass, inside a soft disc.
  static Texture2D _bakeCaustic(int size) {
    final random = math.Random(5);
    final points = [
      for (var i = 0; i < 26; i++)
        (random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1),
    ];
    final half = size / 2;
    return _bake(size, (x, y) {
      final px = (x - half) / half, py = (y - half) / half;
      final r = math.sqrt(px * px + py * py);
      if (r >= 1) return 0.0;
      var f1 = 9.0, f2 = 9.0;
      for (final (cx, cy) in points) {
        final d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
        if (d < f1) {
          f2 = f1;
          f1 = d;
        } else if (d < f2) {
          f2 = d;
        }
      }
      final ridge = math.exp(-(f2 - f1) * 14.0);
      final disc = math.pow(1 - r, 1.4).toDouble();
      return (ridge * disc).clamp(0.0, 1.0);
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
  _RingPulse(
    this.node,
    this.sprite,
    this.radius,
    this.duration,
    this.color, {
    this.grow = true,
  });

  final Node node;
  final Sprite sprite;
  final double radius;
  final double duration;
  final vm.Vector4 color;
  final bool grow;
  double _t = 0.0;

  bool get done => _t >= duration;

  void advance(double dt) {
    _t += dt;
    final p = (_t / duration).clamp(0.0, 1.0);
    if (grow) {
      // Fast out, then coast, while fading.
      final g = 1 - math.pow(1 - p, 3).toDouble();
      final size = 0.3 + (radius - 0.3) * g;
      sprite
        ..width = size
        ..height = size;
    }
    sprite.color = vm.Vector4(
      color.x,
      color.y,
      color.z,
      color.w * (1 - p) * (1 - p),
    );
  }
}

/// A glass die's pool of focused light on the table.
class Caustic {
  Caustic._(this.node, this.layers, this.color);

  final Node node;
  final List<Sprite> layers;
  final vm.Vector4 color;
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

/// One piece of confetti through its life.
class _ConfettiPiece {
  _ConfettiPiece({
    required this.position,
    required this.velocity,
    required this.rotation,
    required this.spinAxis,
    required this.spinRate,
    required this.color,
    required this.scale,
    required this.phase,
    required this.restFor,
  });

  final vm.Vector3 position;
  final vm.Vector3 velocity;
  vm.Quaternion rotation;
  final vm.Vector3 spinAxis;
  double spinRate;
  final vm.Vector4 color;
  final vm.Vector3 scale;
  late final vm.Vector3 baseScale = scale.clone();
  final double phase;
  final double restFor;

  bool landed = false;
  double rested = 0.0;
  double fade = 0.0;
  bool get done => fade >= 1.0;
}

/// Simulates confetti that bursts, flutters down like paper, lands flat,
/// rests, and fades. Flying and resting pieces live in an opaque instanced
/// mesh so they cast shadows; a fading piece moves to a blended one.
class ConfettiComponent extends Component {
  ConfettiComponent({required List<vm.Vector4> colors, int seed = 0})
    : _random = math.Random(seed) {
    final geometry = CuboidGeometry(vm.Vector3(0.16, 0.012, 0.10));
    _opaque = InstancedMesh(
      geometry: geometry,
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.55
        ..clearcoat = 0.35
        ..clearcoatRoughness = 0.3,
    );
    _fading = InstancedMesh(
      geometry: geometry,
      material: PhysicallyBasedMaterial()
        ..metallicFactor = 0.0
        ..roughnessFactor = 0.55
        ..alphaMode = AlphaMode.blend,
      sortTransparentInstances: true,
    );
    for (var i = 0; i < 110; i++) {
      final up = vm.Vector3(0, 1, 0);
      // A cone about +y.
      final angle = _random.nextDouble() * 0.6;
      final around = _random.nextDouble() * math.pi * 2;
      final direction = vm.Vector3(
        math.sin(angle) * math.cos(around),
        math.cos(angle),
        math.sin(angle) * math.sin(around),
      )..normalize();
      final speed = 6.0 + _random.nextDouble() * 5.5;
      final axis = vm.Vector3(
        _random.nextDouble() * 2 - 1,
        _random.nextDouble() * 2 - 1,
        _random.nextDouble() * 2 - 1,
      );
      if (axis.length2 < 1e-4) axis.setFrom(up);
      _pieces.add(
        _ConfettiPiece(
          position: vm.Vector3(
            (_random.nextDouble() - 0.5) * 0.3,
            0.0,
            (_random.nextDouble() - 0.5) * 0.3,
          ),
          velocity: direction * speed,
          rotation: vm.Quaternion.random(_random),
          spinAxis: axis..normalize(),
          spinRate: 10.0 + _random.nextDouble() * 18.0,
          color: colors[i % colors.length],
          scale: vm.Vector3(
            0.7 + _random.nextDouble() * 0.6,
            1.0,
            0.7 + _random.nextDouble() * 0.6,
          ),
          phase: _random.nextDouble() * math.pi * 2,
          restFor: 1.2 + _random.nextDouble() * 1.4,
        ),
      );
    }
  }

  /// Seconds after which every piece has faded.
  static const double maxLifetime = 9.0;

  final math.Random _random;
  final List<_ConfettiPiece> _pieces = [];
  late final InstancedMesh _opaque;
  late final InstancedMesh _fading;
  Node? _opaqueNode;
  Node? _fadingNode;
  double _time = 0.0;

  // Paper falls slowly and sways; these set the feel.
  static const double _gravity = -13.0;
  static const double _terminal = 1.4;
  static const double _restHeight = 0.006;

  final vm.Matrix4 _scratch = vm.Matrix4.zero();
  final vm.Quaternion _spin = vm.Quaternion.identity();

  @override
  void onMount() {
    _opaqueNode = Node()..addComponent(InstancedMeshComponent(_opaque));
    _fadingNode = Node()
      ..shadowCastingMode = ShadowCastingMode.off
      ..addComponent(InstancedMeshComponent(_fading));
    node
      ..add(_opaqueNode!)
      ..add(_fadingNode!);
  }

  @override
  void onUnmount() {
    final o = _opaqueNode, f = _fadingNode;
    if (o != null) node.remove(o);
    if (f != null) node.remove(f);
    _opaqueNode = null;
    _fadingNode = null;
  }

  bool _seeded = false;

  @override
  void update(double deltaSeconds) {
    final dt = math.min(deltaSeconds, 1 / 30);
    _time += dt;
    // Pieces live in world space so they land on the world floor; the
    // emitter's translation is only where the burst starts.
    final origin = node.globalTransform.getTranslation();
    if (!_seeded) {
      _seeded = true;
      for (final piece in _pieces) {
        piece.position.add(origin);
      }
    }
    final inverse = vm.Matrix4.inverted(node.globalTransform);
    _opaque.clearInstances();
    _fading.clearInstances();
    for (final piece in _pieces) {
      if (piece.done) continue;
      _step(piece, dt);
      final world = _scratch
        ..setFromTranslationRotationScale(
          piece.position,
          piece.rotation,
          piece.scale,
        );
      final local = inverse * world;
      if (piece.fade > 0) {
        final c = piece.color;
        _fading.addInstance(
          local,
          color: vm.Vector4(c.x, c.y, c.z, 1.0 - piece.fade),
        );
      } else {
        _opaque.addInstance(local, color: piece.color);
      }
    }
  }

  void _step(_ConfettiPiece piece, double dt) {
    if (piece.landed) {
      piece.rested += dt;
      if (piece.rested > piece.restFor) {
        piece.fade = math.min(1.0, piece.fade + dt / 0.7);
        // Shrink into the table as it goes, so the last of it never pops.
        final s = 1.0 - piece.fade * piece.fade;
        piece.scale.x = piece.scale.x.sign * s * piece.baseScale.x;
        piece.scale.z = piece.scale.z.sign * s * piece.baseScale.z;
      }
      return;
    }
    final v = piece.velocity;
    // Ballistic while fast; once the pop is spent, paper drag takes over
    // and the piece drifts down at terminal speed, swaying side to side.
    final speed = v.length;
    final fluttering = speed < 4.0 && v.y < 0.5;
    if (fluttering) {
      final sway = math.sin(_time * 3.1 + piece.phase);
      final swayZ = math.cos(_time * 2.3 + piece.phase * 1.7);
      v.x += (sway * 1.6 - v.x) * dt * 3.0;
      v.z += (swayZ * 1.2 - v.z) * dt * 3.0;
      v.y += (-_terminal - v.y) * dt * 4.0;
      // Lazy tumble, mostly about a horizontal axis.
      piece.spinRate += (4.0 - piece.spinRate) * dt * 2.0;
    } else {
      v.y += _gravity * dt;
      v.scale(math.max(0.0, 1.0 - 1.4 * dt));
    }
    piece.position.addScaled(v, dt);
    // Air pieces spin; a piece about to land settles flat.
    _spin.setAxisAngle(piece.spinAxis, piece.spinRate * dt);
    piece.rotation = (_spin * piece.rotation)..normalize();
    if (piece.position.y <= _restHeight && v.y < 0) {
      piece.landed = true;
      piece.position.y = _restHeight;
      // Lie flat, keeping only the heading.
      final forward = piece.rotation.rotate(vm.Vector3(1, 0, 0))..y = 0;
      final yaw = forward.length2 < 1e-6
          ? _random.nextDouble() * math.pi * 2
          : math.atan2(-forward.z, forward.x);
      piece.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);
    }
  }
}
