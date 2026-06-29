import 'package:flutter_scene/src/components/mesh_component.dart';
import 'package:flutter_scene/src/geometry/billboard_geometry.dart';
import 'package:flutter_scene/src/material/sprite_material.dart';
import 'package:flutter_scene/src/mesh.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';

import 'package:vector_math/vector_math.dart';

// TODO(particles): export this (and the configuration types under
// lib/src/particles/) from lib/scene.dart with a `{@category Particles}` doc
// category once the authoring API settles across the later rendering phases.

/// An engine component that simulates a [ParticleSystem] on the CPU and draws
/// its live particles as one instanced batch of camera-facing billboards.
///
/// Attach it to a node like any other component; the node's transform places
/// and orients the emitter (particles simulate in the node's local space, so
/// they move with it). Each frame [update] advances the system by the frame
/// delta and copies the live particle columns into a [BillboardGeometry], which
/// the inherited mesh-component machinery renders, culls, and bounds.
///
/// Configure the effect through the [system] (shape, spawner, modules, start
/// distributions, gravity) and the [material] (texture, tint, blend mode). Set
/// [facing]/[velocityStretch] for spark-like streaks.
class ParticleEmitterComponent extends MeshComponent {
  /// Creates an emitter that drives [system]. When [material] is omitted a
  /// default [SpriteMaterial] (untextured, alpha-blended) is used; configure
  /// its texture, tint, and blend mode for the effect.
  factory ParticleEmitterComponent({
    required ParticleSystem system,
    SpriteMaterial? material,
  }) {
    final geometry = BillboardGeometry(capacity: system.storage.capacity);
    final spriteMaterial = material ?? SpriteMaterial();
    return ParticleEmitterComponent._(system, geometry, spriteMaterial);
  }

  ParticleEmitterComponent._(this.system, this._geometry, this._material)
    : super(Mesh(_geometry, _material));

  /// The simulation this emitter advances and renders.
  final ParticleSystem system;

  final BillboardGeometry _geometry;
  final SpriteMaterial _material;

  // Scratch vectors reused every frame so repacking allocates nothing.
  final Vector3 _center = Vector3.zero();
  final Vector4 _color = Vector4.zero();
  final Vector3 _velocity = Vector3.zero();

  /// The material the billboards are drawn with (texture, tint, blend mode).
  SpriteMaterial get material => _material;

  /// When true, the simulation holds (the current particles keep rendering but
  /// stop advancing). Useful for editor scrubbing or off-screen emitters.
  bool paused = false;

  /// How the billboards orient toward the camera (see [BillboardFacing]).
  BillboardFacing get facing => _geometry.facing;
  set facing(BillboardFacing value) => _geometry.facing = value;

  /// World units of extra length added per unit of speed when [facing] is
  /// [BillboardFacing.velocityStretched].
  double get velocityStretch => _geometry.velocityStretch;
  set velocityStretch(double value) => _geometry.velocityStretch = value;

  @override
  void update(double deltaSeconds) {
    if (!paused) system.step(deltaSeconds);
    _repack();
  }

  // Copies the live particle columns into the billboard instance buffer.
  void _repack() {
    final s = system.storage;
    final count = s.aliveCount;
    for (var i = 0; i < count; i++) {
      final size = s.size[i];
      _center.setValues(s.posX[i], s.posY[i], s.posZ[i]);
      _color.setValues(s.colorR[i], s.colorG[i], s.colorB[i], s.colorA[i]);
      _velocity.setValues(s.velX[i], s.velY[i], s.velZ[i]);
      _geometry.setInstance(
        i,
        center: _center,
        width: size,
        height: size,
        rotation: s.rotation[i],
        color: _color,
        velocity: _velocity,
      );
    }
    _geometry.commit(count);
  }
}
