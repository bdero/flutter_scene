/// Ready-made particle effects.
///
/// The particle system is expressive enough that a plume of smoke is thirty
/// lines of shape, spawner, distributions, and modules. That expressiveness is
/// the point, but it means nobody reaches for it to put a puff of dust under a
/// footstep. These presets are the other end: one call gives a working effect
/// that already looks like the thing it is named after, and every field of it
/// stays open to edit afterwards.
///
/// Each preset is a description plus a builder, so a catalogue (the editor's
/// VFX panel, a game's own picker) can list them without instantiating any.
library;

import 'dart:math' as math;

import 'package:flutter_scene/src/components/particle_emitter_component.dart';
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/particles/distribution.dart';
import 'package:flutter_scene/src/particles/emitter_shape.dart';
import 'package:flutter_scene/src/particles/particle_collision.dart';
import 'package:flutter_scene/src/particles/particle_module.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';
import 'package:flutter_scene/src/particles/spawner.dart';
import 'package:vector_math/vector_math.dart';

/// How a preset is grouped in a catalogue.
/// {@category Particles}
enum VfxCategory {
  /// Smoke, fire, steam: the continuously emitting atmospherics.
  smokeAndFire('Smoke & Fire'),

  /// One-shot effects fired at a moment: muzzle flashes, impacts, explosions.
  impacts('Impacts'),

  /// Rain, snow, fog, ash: the effects that fill a volume rather than come
  /// from a point.
  weather('Weather'),

  /// Sparkles, wisps, embers: the stylized effects.
  magic('Magic');

  const VfxCategory(this.label);

  /// The heading a catalogue shows.
  final String label;
}

/// One ready-made effect: what it is, and how to build it.
/// {@category Particles}
class VfxPreset {
  const VfxPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.buildSystem,
    required this.style,
  });

  /// A stable identifier, so a saved reference to a preset survives a rename.
  final String id;

  /// The name a catalogue shows.
  final String name;

  final VfxCategory category;

  /// One line on what the effect is for, and what makes it that effect.
  final String description;

  /// Builds a fresh simulation: the shape, spawner, distributions, and
  /// modules that make the effect move the way it does.
  ///
  /// Separate from [style] because this half touches no GPU resource. A game
  /// driving a mesh-particle emitter, or a test checking that a preset emits
  /// anything at all, wants the simulation without the billboards.
  final ParticleSystem Function() buildSystem;

  /// Applies the effect's look to a built emitter: blend mode, soft fading,
  /// and how the billboards face.
  final void Function(ParticleEmitterComponent emitter) style;

  /// Builds a fresh emitter, simulation and look together.
  ///
  /// Called per use: an emitter owns its simulation, so two copies of one
  /// preset must not share a system. Needs the base shader bundle, so await
  /// `Scene.initializeStaticResources()` first.
  ParticleEmitterComponent build() {
    final emitter = ParticleEmitterComponent(system: buildSystem());
    style(emitter);
    return emitter;
  }
}

/// Every shipped preset, in catalogue order.
/// {@category Particles}
final List<VfxPreset> vfxPresets = [
  VfxPreset(
    id: 'smoke',
    name: 'Smoke',
    category: VfxCategory.smokeAndFire,
    description:
        'A slow rising plume that spreads and thins. Soft-particle fading, '
        'so it dissolves through walls rather than cutting into them.',
    buildSystem: _smokeSystem,
    style: _smokeStyle,
  ),
  VfxPreset(
    id: 'fire',
    name: 'Fire',
    category: VfxCategory.smokeAndFire,
    description:
        'Additive flames licking upward through a curl-noise field, cooling '
        'from white through orange to smoke.',
    buildSystem: _fireSystem,
    style: _fireStyle,
  ),
  VfxPreset(
    id: 'steam',
    name: 'Steam Jet',
    category: VfxCategory.smokeAndFire,
    description:
        'A narrow, fast white jet that expands and fades. A vent, a kettle, '
        'a hydraulic release.',
    buildSystem: _steamSystem,
    style: _steamStyle,
  ),
  VfxPreset(
    id: 'embers',
    name: 'Embers',
    category: VfxCategory.smokeAndFire,
    description:
        'Sparse glowing motes drifting up and out on turbulence, the debris '
        'a fire throws off.',
    buildSystem: _embersSystem,
    style: _embersStyle,
  ),
  VfxPreset(
    id: 'muzzleFlash',
    name: 'Muzzle Flash',
    category: VfxCategory.impacts,
    description:
        'A single bright burst that is gone in under a tenth of a second. '
        'Fires once per restart, so trigger it by restarting the emitter.',
    buildSystem: _muzzleFlashSystem,
    style: _muzzleFlashStyle,
  ),
  VfxPreset(
    id: 'impactSparks',
    name: 'Impact Sparks',
    category: VfxCategory.impacts,
    description:
        'A cone of stretched sparks thrown off a hit, slowed by drag and '
        'pulled down by gravity.',
    buildSystem: _impactSparksSystem,
    style: _impactSparksStyle,
  ),
  VfxPreset(
    id: 'dustPuff',
    name: 'Dust Puff',
    category: VfxCategory.impacts,
    description:
        'A low, wide puff that expands and settles: a footstep, a landing, '
        'a round hitting dirt.',
    buildSystem: _dustPuffSystem,
    style: _dustPuffStyle,
  ),
  VfxPreset(
    id: 'explosion',
    name: 'Explosion',
    category: VfxCategory.impacts,
    description:
        'A fast additive fireball that expands and darkens into smoke, over '
        'a wide burst of debris.',
    buildSystem: _explosionSystem,
    style: _explosionStyle,
  ),
  VfxPreset(
    id: 'groundFog',
    name: 'Ground Fog',
    category: VfxCategory.weather,
    description:
        'Wide, slow, nearly transparent cards drifting across a volume. '
        'Soft-particle fading keeps it from slicing through the ground.',
    buildSystem: _groundFogSystem,
    style: _groundFogStyle,
  ),
  VfxPreset(
    id: 'rain',
    name: 'Rain',
    category: VfxCategory.weather,
    description:
        'Fast velocity-stretched streaks falling through a volume overhead.',
    buildSystem: _rainSystem,
    style: _rainStyle,
  ),
  VfxPreset(
    id: 'snow',
    name: 'Snow',
    category: VfxCategory.weather,
    description:
        'Slow flakes drifting down through a turbulent field, so no two take '
        'the same path.',
    buildSystem: _snowSystem,
    style: _snowStyle,
  ),
  VfxPreset(
    id: 'sparkle',
    name: 'Sparkle',
    category: VfxCategory.magic,
    description:
        'Additive motes twinkling on and off around a point, each with its '
        'own phase.',
    buildSystem: _sparkleSystem,
    style: _sparkleStyle,
  ),
];

/// The preset with [id], or null.
/// {@category Particles}
VfxPreset? vfxPresetById(String id) {
  for (final preset in vfxPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

/// The presets in [category], in catalogue order.
/// {@category Particles}
List<VfxPreset> vfxPresetsIn(VfxCategory category) =>
    [for (final preset in vfxPresets) if (preset.category == category) preset];

// ---------------------------------------------------------------------------
// Builders.
//
// Each is deliberately explicit rather than parameterized off a shared base:
// the interesting part of a preset is the handful of numbers that make it look
// like what it is, and a reader should be able to see all of them at once and
// change one.
// ---------------------------------------------------------------------------

Vector4 _rgba(double r, double g, double b, double a) => Vector4(r, g, b, a);

ParticleSystem _smokeSystem() => ParticleSystem(
  maxParticles: 400,
  shape: const ConeEmitterShape(angle: 0.28, radius: 0.25),
  spawner: Spawner(rate: 22),
  lifetime: const UniformFloat(2.4, 3.6),
  startSpeed: const UniformFloat(0.7, 1.2),
  startSize: const UniformFloat(0.5, 0.9),
  startRotation: const UniformFloat(0, math.pi * 2),
  startAngularVelocity: const UniformFloat(-0.4, 0.4),
  gravity: Vector3(0, 0.35, 0),
  modules: [
    // Smoke slows as it rises and spreads; drag is what stops the plume
    // shooting off in a straight line.
    LinearDragModule(0.9),
    TurbulenceModule(
      strength: 0.5,
      frequency: 0.35,
      scroll: Vector3(0, 0.4, 0),
    ),
    SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 1, to: 3.2)),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(0.42, 0.42, 0.45, 0)),
          ColorStop(0.12, _rgba(0.38, 0.38, 0.41, 0.55)),
          ColorStop(1, _rgba(0.30, 0.30, 0.33, 0)),
        ]),
      ),
    ),
  ],
);

void _smokeStyle(ParticleEmitterComponent emitter) {
  emitter.material
    ..blendMode = SpriteBlendMode.alpha
    ..softDepthFade = 1.2;
}

ParticleSystem _fireSystem() => ParticleSystem(
  maxParticles: 350,
  shape: const ConeEmitterShape(angle: 0.22, radius: 0.18),
  spawner: Spawner(rate: 60),
  lifetime: const UniformFloat(0.5, 0.95),
  startSpeed: const UniformFloat(1.6, 2.6),
  startSize: const UniformFloat(0.30, 0.55),
  startRotation: const UniformFloat(0, math.pi * 2),
  gravity: Vector3(0, 1.4, 0),
  modules: [
    TurbulenceModule(
      strength: 2.2,
      frequency: 1.5,
      scroll: Vector3(0, 1.6, 0),
    ),
    SizeOverLifeModule(
      CurveFloat(
        ParticleCurve(const [
          ParticleKeyframe(0, 0.5),
          ParticleKeyframe(0.25, 1.15),
          ParticleKeyframe(1, 0.25),
        ]),
      ),
    ),
    ColorOverLifeModule(
      GradientColor(
        // Cooling: the emissive range runs above 1 because the material
        // outputs linear HDR and the bloom pass is what makes a flame
        // read as bright rather than merely white.
        ColorGradient([
          ColorStop(0, _rgba(3.2, 2.4, 1.1, 1)),
          ColorStop(0.28, _rgba(2.6, 0.95, 0.20, 0.95)),
          ColorStop(0.65, _rgba(1.0, 0.22, 0.04, 0.55)),
          ColorStop(1, _rgba(0.15, 0.10, 0.09, 0)),
        ]),
      ),
    ),
  ],
);

void _fireStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
  emitter.facing = BillboardFacing.axisLocked;
}

ParticleSystem _steamSystem() => ParticleSystem(
  maxParticles: 300,
  shape: const ConeEmitterShape(angle: 0.12, radius: 0.06),
  spawner: Spawner(rate: 45),
  lifetime: const UniformFloat(0.9, 1.5),
  startSpeed: const UniformFloat(4.5, 6.5),
  startSize: const UniformFloat(0.12, 0.22),
  startRotation: const UniformFloat(0, math.pi * 2),
  modules: [
    LinearDragModule(2.4),
    SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 1, to: 5.5)),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(1, 1, 1, 0)),
          ColorStop(0.1, _rgba(1, 1, 1, 0.5)),
          ColorStop(1, _rgba(0.92, 0.94, 0.96, 0)),
        ]),
      ),
    ),
  ],
);

void _steamStyle(ParticleEmitterComponent emitter) {
  emitter.material
    ..blendMode = SpriteBlendMode.alpha
    ..softDepthFade = 0.6;
}

ParticleSystem _embersSystem() => ParticleSystem(
  maxParticles: 120,
  shape: const ConeEmitterShape(angle: 0.5, radius: 0.3),
  spawner: Spawner(rate: 9),
  lifetime: const UniformFloat(1.6, 3.0),
  startSpeed: const UniformFloat(1.0, 2.2),
  startSize: const UniformFloat(0.04, 0.09),
  gravity: Vector3(0, 0.8, 0),
  modules: [
    LinearDragModule(0.7),
    TurbulenceModule(
      strength: 1.8,
      frequency: 0.9,
      scroll: Vector3(0, 0.8, 0),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(3.0, 1.5, 0.4, 1)),
          ColorStop(0.6, _rgba(1.6, 0.5, 0.1, 0.8)),
          ColorStop(1, _rgba(0.4, 0.1, 0.02, 0)),
        ]),
      ),
    ),
  ],
);

void _embersStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
}

ParticleSystem _muzzleFlashSystem() => ParticleSystem(
  maxParticles: 48,
  shape: const ConeEmitterShape(angle: 0.55, radius: 0.02),
  // No steady rate: the whole effect is one burst at t = 0, which is what
  // makes restarting the emitter the way to fire it.
  spawner: Spawner(
    rate: 0,
    bursts: const [ParticleBurst(time: 0, count: 14)],
  ),
  looping: false,
  duration: 0.5,
  lifetime: const UniformFloat(0.04, 0.09),
  startSpeed: const UniformFloat(6, 14),
  startSize: const UniformFloat(0.18, 0.34),
  startRotation: const UniformFloat(0, math.pi * 2),
  modules: [
    SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 1.4, to: 0.2)),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(6.0, 4.6, 2.4, 1)),
          ColorStop(0.45, _rgba(3.0, 1.4, 0.35, 0.8)),
          ColorStop(1, _rgba(0.8, 0.3, 0.05, 0)),
        ]),
      ),
    ),
  ],
);

void _muzzleFlashStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
}

ParticleSystem _impactSparksSystem() => ParticleSystem(
  maxParticles: 160,
  shape: const ConeEmitterShape(angle: 0.75, radius: 0.05),
  spawner: Spawner(
    rate: 0,
    bursts: const [ParticleBurst(time: 0, count: 40)],
  ),
  looping: false,
  duration: 1.5,
  lifetime: const UniformFloat(0.25, 0.7),
  startSpeed: const UniformFloat(4, 11),
  startSize: const UniformFloat(0.02, 0.05),
  gravity: Vector3(0, -9.8, 0),
  modules: [
    LinearDragModule(1.6),
    // Sparks land. Skittering off the floor and dimming as they do is most
    // of what tells a viewer where the impact was; without it they fall
    // through it and the shot reads as happening in mid-air.
    CollisionModule.ground(
      restitution: 0.4,
      friction: 0.35,
      lifetimeLoss: 0.25,
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(5.0, 3.4, 1.2, 1)),
          ColorStop(0.5, _rgba(2.4, 0.9, 0.15, 1)),
          ColorStop(1, _rgba(0.5, 0.12, 0.02, 0)),
        ]),
      ),
    ),
  ],
);

void _impactSparksStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
  // Sparks are their own motion blur: a stretched quad along the velocity
  // reads as a streak where a round billboard reads as confetti.
  emitter.facing = BillboardFacing.velocityStretched;
  emitter.velocityStretch = 0.055;
}

ParticleSystem _dustPuffSystem() => ParticleSystem(
  maxParticles: 90,
  shape: const SphereEmitterShape(radius: 0.2, hemisphere: true),
  spawner: Spawner(
    rate: 0,
    bursts: const [ParticleBurst(time: 0, count: 18)],
  ),
  looping: false,
  duration: 2,
  lifetime: const UniformFloat(0.6, 1.1),
  startSpeed: const UniformFloat(0.8, 1.8),
  startSize: const UniformFloat(0.22, 0.4),
  startRotation: const UniformFloat(0, math.pi * 2),
  startAngularVelocity: const UniformFloat(-1.2, 1.2),
  gravity: Vector3(0, -0.6, 0),
  modules: [
    LinearDragModule(2.8),
    // A puff is placed on the surface it came off, so the emitter's own
    // origin is the ground. Sliding rather than bouncing is what dust does:
    // it rolls out along the floor instead of sinking through it.
    CollisionModule.ground(
      response: ParticleCollisionResponse.slide,
      friction: 0.35,
      radius: 0.15,
    ),
    SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 1, to: 2.4)),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(0.52, 0.45, 0.36, 0)),
          ColorStop(0.15, _rgba(0.52, 0.45, 0.36, 0.6)),
          ColorStop(1, _rgba(0.45, 0.40, 0.33, 0)),
        ]),
      ),
    ),
  ],
);

void _dustPuffStyle(ParticleEmitterComponent emitter) {
  emitter.material
    ..blendMode = SpriteBlendMode.alpha
    ..softDepthFade = 0.8;
}

ParticleSystem _explosionSystem() => ParticleSystem(
  maxParticles: 260,
  shape: const SphereEmitterShape(radius: 0.4),
  spawner: Spawner(
    rate: 0,
    bursts: const [
      ParticleBurst(time: 0, count: 46),
      // A second, slower wave a beat later is what turns a flash into an
      // explosion: the fireball rolls outward after the initial crack.
      ParticleBurst(time: 0.06, count: 30),
    ],
  ),
  looping: false,
  duration: 3,
  lifetime: const UniformFloat(0.5, 1.4),
  startSpeed: const UniformFloat(3, 12),
  startSize: const UniformFloat(0.5, 1.1),
  startRotation: const UniformFloat(0, math.pi * 2),
  gravity: Vector3(0, 1.2, 0),
  modules: [
    LinearDragModule(2.2),
    TurbulenceModule(strength: 2.6, frequency: 0.8),
    SizeOverLifeModule(
      CurveFloat(ParticleCurve.linear(from: 0.7, to: 2.6)),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(6.0, 4.0, 1.6, 1)),
          ColorStop(0.2, _rgba(3.4, 1.2, 0.25, 1)),
          ColorStop(0.55, _rgba(0.7, 0.25, 0.08, 0.8)),
          ColorStop(1, _rgba(0.12, 0.11, 0.11, 0)),
        ]),
      ),
    ),
  ],
);

void _explosionStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
}

ParticleSystem _groundFogSystem() => ParticleSystem(
  maxParticles: 90,
  shape: BoxEmitterShape(
    halfExtents: Vector3(12, 0.4, 12),
    direction: Vector3(1, 0, 0.3),
  ),
  spawner: Spawner(rate: 6),
  lifetime: const UniformFloat(9, 15),
  startSpeed: const UniformFloat(0.08, 0.2),
  startSize: const UniformFloat(5, 9),
  startRotation: const UniformFloat(0, math.pi * 2),
  startAngularVelocity: const UniformFloat(-0.03, 0.03),
  // Prewarmed, so a scene opens already fogged rather than filling in
  // over the first fifteen seconds.
  prewarm: 12,
  modules: [
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(0.62, 0.65, 0.70, 0)),
          ColorStop(0.25, _rgba(0.62, 0.65, 0.70, 0.16)),
          ColorStop(0.75, _rgba(0.62, 0.65, 0.70, 0.16)),
          ColorStop(1, _rgba(0.62, 0.65, 0.70, 0)),
        ]),
      ),
    ),
  ],
);

void _groundFogStyle(ParticleEmitterComponent emitter) {
  emitter.material
    ..blendMode = SpriteBlendMode.alpha
    // Fog that cuts a hard line through the ground is the tell; both fades
    // are what keep it reading as a medium.
    ..softDepthFade = 3.5
    ..cameraNearFade = 2.0;
  emitter.facing = BillboardFacing.axisLocked;
}

ParticleSystem _rainSystem() => ParticleSystem(
  maxParticles: 2000,
  shape: BoxEmitterShape(
    halfExtents: Vector3(14, 0.1, 14),
    direction: Vector3(0, -1, 0),
  ),
  spawner: Spawner(rate: 450),
  lifetime: const UniformFloat(0.9, 1.2),
  startSpeed: const UniformFloat(16, 20),
  startSize: const UniformFloat(0.012, 0.022),
  gravity: Vector3(0, -6, 0),
  prewarm: 1.2,
  // No collider here on purpose. A rain volume hangs above the scene, so a
  // ground plane at the emitter's own origin is the sky, not the floor, and
  // the height of the actual ground is something only the author knows. Add
  // a CollisionModule with the right plane and drops stop where they land.
  modules: [
    ColorOverLifeModule(
      GradientColor(
        ColorGradient.constant(_rgba(0.55, 0.62, 0.72, 0.5)),
      ),
    ),
  ],
);

void _rainStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.alpha;
  emitter.facing = BillboardFacing.velocityStretched;
  emitter.velocityStretch = 0.03;
}

ParticleSystem _snowSystem() => ParticleSystem(
  maxParticles: 1200,
  shape: BoxEmitterShape(
    halfExtents: Vector3(14, 0.1, 14),
    direction: Vector3(0, -1, 0),
  ),
  spawner: Spawner(rate: 90),
  lifetime: const UniformFloat(7, 11),
  startSpeed: const UniformFloat(0.5, 1.1),
  startSize: const UniformFloat(0.03, 0.075),
  startRotation: const UniformFloat(0, math.pi * 2),
  startAngularVelocity: const UniformFloat(-0.8, 0.8),
  gravity: Vector3(0, -0.25, 0),
  prewarm: 8,
  modules: [
    LinearDragModule(0.6),
    // The drift is the whole effect: without it every flake falls down
    // the same straight line and it reads as static.
    TurbulenceModule(
      strength: 0.55,
      frequency: 0.25,
      scroll: Vector3(0.3, -0.1, 0.2),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(1, 1, 1, 0)),
          ColorStop(0.08, _rgba(1, 1, 1, 0.85)),
          ColorStop(0.9, _rgba(1, 1, 1, 0.85)),
          ColorStop(1, _rgba(1, 1, 1, 0)),
        ]),
      ),
    ),
  ],
);

void _snowStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.alpha;
}

ParticleSystem _sparkleSystem() => ParticleSystem(
  maxParticles: 160,
  shape: const SphereEmitterShape(radius: 0.9),
  spawner: Spawner(rate: 34),
  lifetime: const UniformFloat(0.7, 1.6),
  startSpeed: const UniformFloat(0.1, 0.4),
  startSize: const UniformFloat(0.05, 0.12),
  modules: [
    LinearDragModule(1.2),
    // Up and down over the life, so each mote twinkles once rather than
    // simply fading; the random per-particle lifetime desynchronizes them.
    SizeOverLifeModule(
      CurveFloat(
        ParticleCurve(const [
          ParticleKeyframe(0, 0),
          ParticleKeyframe(0.35, 1.3),
          ParticleKeyframe(1, 0),
        ]),
      ),
    ),
    ColorOverLifeModule(
      GradientColor(
        ColorGradient([
          ColorStop(0, _rgba(1.4, 1.9, 3.2, 0)),
          ColorStop(0.4, _rgba(2.2, 2.6, 3.6, 1)),
          ColorStop(1, _rgba(0.9, 1.2, 2.4, 0)),
        ]),
      ),
    ),
  ],
);

void _sparkleStyle(ParticleEmitterComponent emitter) {
  emitter.material.blendMode = SpriteBlendMode.additive;
}
