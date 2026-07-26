import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/instanced_mesh_component.dart';
import 'package:flutter_scene/src/geometry/geometry.dart';
import 'package:flutter_scene/src/instanced_mesh.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/particles/particle_storage.dart';
import 'package:flutter_scene/src/particles/particle_system.dart';

/// How a mesh particle orients itself.
/// {@category Particles}
enum MeshParticleFacing {
  /// Tumbles around the particle's random unit axis by its rotation (which
  /// `RotationModule` integrates from the angular velocity). The default,
  /// suited to debris and shrapnel.
  tumble,

  /// The mesh's `+Y` axis follows the particle's velocity, spinning around
  /// it by the particle's rotation. Suited to darts, shards, and anything
  /// that should fly point-first.
  velocityAligned,
}

/// An engine component that simulates a [ParticleSystem] on the CPU and draws
/// each live particle as an instance of a 3D mesh, one instanced draw per
/// geometry.
///
/// Where `ParticleEmitterComponent` renders camera-facing billboards, this
/// component renders real geometry, debris chunks, rocks, shards, coins.
/// Passing several [geometries] gives free variety: each particle picks one
/// for life by its stable per-particle random, the way sprite systems pick a
/// random flipbook cell. All geometries share one [material].
///
/// The particle's size is a uniform scale, its rotation spins it per
/// [facing], and position/velocity/lifetime behave exactly as they do for
/// sprite particles, so the same modules drive both renderers.
///
/// Per-particle color is not applied to mesh instances.
/// TODO(particles): per-instance color needs an instanced color attribute on
/// the mesh instancing path; route ColorOverLife through it once that lands.
/// {@category Particles}
class MeshParticleEmitterComponent extends Component {
  /// Creates an emitter that draws [system]'s particles as instances of
  /// [geometries] (each particle picks one), all sharing [material].
  MeshParticleEmitterComponent({
    required this.system,
    required List<Geometry> geometries,
    required Material material,
    this.facing = MeshParticleFacing.tumble,
  }) : assert(geometries.isNotEmpty),
       _meshes = [
         for (final geometry in geometries)
           InstancedMesh(geometry: geometry, material: material),
       ] {
    // Fixed instance slots (hidden when unused) so per-frame updates never
    // churn the instance lists.
    for (final mesh in _meshes) {
      for (var i = 0; i < system.storage.capacity; i++) {
        mesh.addInstance(_hiddenTransform);
      }
    }
    _liveCounts = List<int>.filled(_meshes.length, 0);
  }

  /// The simulation this emitter advances and renders.
  final ParticleSystem system;

  /// How instances orient (tumble around their axis, or fly point-first).
  MeshParticleFacing facing;

  /// When true, the simulation holds (current particles keep rendering but
  /// stop advancing).
  bool paused = false;

  final List<InstancedMesh> _meshes;
  final List<Node> _childNodes = [];
  late List<int> _liveCounts;

  // Collapsed to nothing far below any plausible scene.
  static final Matrix4 _hiddenTransform = Matrix4.compose(
    Vector3(0, -1e5, 0),
    Quaternion.identity(),
    Vector3.all(1e-6),
  );

  // Scratch objects reused every frame so repacking allocates nothing.
  final Matrix4 _scratchTransform = Matrix4.zero();
  final Quaternion _scratchRotation = Quaternion.identity();
  final Quaternion _scratchSpin = Quaternion.identity();
  final Vector3 _scratchTranslation = Vector3.zero();
  final Vector3 _scratchScale = Vector3.zero();
  final Vector3 _scratchAxis = Vector3.zero();
  final Vector3 _scratchVelocity = Vector3.zero();

  @override
  void onMount() {
    for (final mesh in _meshes) {
      final child = Node()..addComponent(InstancedMeshComponent(mesh));
      _childNodes.add(child);
      node.add(child);
    }
  }

  @override
  void onUnmount() {
    for (final child in _childNodes) {
      node.remove(child);
    }
    _childNodes.clear();
  }

  @override
  void update(double deltaSeconds) {
    if (!paused) system.step(deltaSeconds);
    _repack();
  }

  void _repack() {
    final s = system.storage;
    final buckets = _meshes.length;
    final counts = List<int>.filled(buckets, 0);
    for (var i = 0; i < s.aliveCount; i++) {
      var bucket = (s.random01[i] * buckets).floor();
      if (bucket >= buckets) bucket = buckets - 1;
      final slot = counts[bucket]++;

      _scratchTranslation.setValues(s.posX[i], s.posY[i], s.posZ[i]);
      final size = s.size[i];
      _scratchScale.setValues(size, size, size);
      _orient(s, i);
      _scratchTransform.setFromTranslationRotationScale(
        _scratchTranslation,
        _scratchRotation,
        _scratchScale,
      );
      _meshes[bucket].setInstanceTransform(slot, _scratchTransform);
    }
    // Hide only the slots that were live last frame and no longer are.
    for (var b = 0; b < buckets; b++) {
      for (var i = counts[b]; i < _liveCounts[b]; i++) {
        _meshes[b].setInstanceTransform(i, _hiddenTransform);
      }
    }
    _liveCounts = counts;
  }

  // Writes the particle's orientation into [_scratchRotation].
  void _orient(ParticleStorage s, int i) {
    if (facing == MeshParticleFacing.tumble) {
      _scratchAxis.setValues(s.axisX[i], s.axisY[i], s.axisZ[i]);
      _scratchRotation.setAxisAngle(_scratchAxis, s.rotation[i]);
      return;
    }
    // Velocity aligned: rotate +Y onto the velocity direction, then spin
    // around it. A near-still particle falls back to its tumble axis.
    _scratchVelocity.setValues(s.velX[i], s.velY[i], s.velZ[i]);
    final speed = _scratchVelocity.length;
    if (speed < 1e-5) {
      _scratchAxis.setValues(s.axisX[i], s.axisY[i], s.axisZ[i]);
      _scratchRotation.setAxisAngle(_scratchAxis, s.rotation[i]);
      return;
    }
    _scratchVelocity.scale(1.0 / speed);
    final dotUp = _scratchVelocity.y.clamp(-1.0, 1.0);
    if (dotUp > 1.0 - 1e-6) {
      _scratchRotation.setAxisAngle(_scratchVelocity, s.rotation[i]);
      return;
    }
    if (dotUp < -1.0 + 1e-6) {
      // Antiparallel: flip around any horizontal axis.
      _scratchAxis.setValues(1, 0, 0);
      _scratchRotation.setAxisAngle(_scratchAxis, math.pi);
    } else {
      // Axis = up x velocity, angle = acos(up . velocity).
      _scratchAxis.setValues(_scratchVelocity.z, 0.0, -_scratchVelocity.x);
      _scratchAxis.normalize();
      _scratchRotation.setAxisAngle(_scratchAxis, math.acos(dotUp));
    }
    _scratchSpin.setAxisAngle(_scratchVelocity, s.rotation[i]);
    _scratchRotation.setFrom(_scratchSpin * _scratchRotation);
  }
}
