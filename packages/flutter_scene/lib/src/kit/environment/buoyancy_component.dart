/// Floating things on water.
///
/// A water surface that nothing sits on is scenery. This is the piece that
/// makes it a place: a raft that rides the swell, a crate that bobs where it
/// was dropped, a boat that pitches into a wave and rolls out of it.
///
/// It works two ways, because scenes come both ways. With a rigid body on the
/// node it is a force: buoyancy at each probe, proportional to how deep that
/// probe is, plus the drag that stops a float from turning into a trampoline.
/// Without one it is a pose: the node is placed on the surface and tilted to
/// it. The first is what a physics scene wants; the second is what a piece of
/// set dressing wants, and it costs no simulation at all.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/kit/environment/gerstner_field.dart';
import 'package:flutter_scene/src/kit/environment/water_component.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/physics/rigid_body.dart';
import 'package:scene/physics.dart' show BodyType;
import 'package:vector_math/vector_math.dart' as vm;

/// Floats the node it is attached to on a [WaterComponent].
///
/// Attach it to the thing that floats. It finds the water by searching up to
/// the scene root and then across, so a raft dropped anywhere under the same
/// root finds the lake without being wired to it.
/// {@category Gameplay kit}
class BuoyancyComponent extends Component {
  BuoyancyComponent({
    this.hullSize = 1.0,
    this.draft = 0.0,
    this.probeCount = 4,
    this.strength = 12.0,
    this.linearDamping = 1.4,
    this.angularDamping = 2.2,
    this.alignToSurface = true,
    this.alignResponse = 6.0,
    this.water,
  }) : assert(probeCount == 1 || probeCount == 4 || probeCount == 8);

  /// How wide the floating thing is, in world units. The probes are spread
  /// over a square this size, so a long boat pitches and a small crate does
  /// not.
  double hullSize;

  /// How far the resting waterline sits below the node's origin.
  ///
  /// Positive sinks the node into the water. A hull modelled with its origin
  /// at the deck wants its own depth here, or it floats with the deck awash.
  double draft;

  /// Probes around the hull: 1 bobs without tilting, 4 is a hull, 8 is a long
  /// boat that should feel a wave pass down its length.
  ///
  /// Each probe is a wave-field sample per frame, which is the whole per-
  /// floater cost, so this is the dial to turn when a harbour full of boats
  /// gets expensive.
  int probeCount;

  /// How hard the water pushes back per unit of submersion.
  ///
  /// With a rigid body this is an acceleration per metre of depth; a value
  /// near gravity floats something roughly at its waterline, and higher makes
  /// it ride high and lively.
  double strength;

  /// Velocity bled off per second while submerged. Water is not a spring:
  /// without this a float oscillates forever.
  double linearDamping;

  /// Angular velocity bled off per second while submerged.
  double angularDamping;

  /// Whether the node tilts to the surface it is riding.
  bool alignToSurface;

  /// How fast the tilt catches up, per second. Low is a barge, high is a
  /// leaf.
  double alignResponse;

  /// The water to float on, or null to find one under the scene root.
  WaterComponent? water;

  /// Whether the node was in contact with the water on the last update.
  bool get isFloating => _isFloating;
  bool _isFloating = false;

  /// How deep the node's origin sat below the surface on the last update.
  /// Negative when it is clear of the water.
  double get submersion => _submersion;
  double _submersion = 0;

  WaterComponent? _found;
  RigidBody? _body;

  // One buffer for every probe of every frame: sampling is the per-frame
  // cost, and an allocation per sample would be most of it.
  final Float64List _sample = Float64List(GerstnerField.sampleStride);
  final vm.Vector3 _scratch = vm.Vector3.zero();

  @override
  void onMount() => _resolve();

  @override
  void onUnmount() {
    _body = null;
    _found = null;
    _resolved = false;
    _isFloating = false;
  }

  bool _resolved = false;

  // Resolved lazily as well as on mount, because a float can be assembled
  // and stepped without ever being attached to a live scene -- a test, or a
  // headless simulation deciding where the cargo drifted to.
  void _resolve() {
    if (_resolved || !isAttached) return;
    _resolved = true;
    _body = node.getComponent<RigidBody>();
    _found = water ?? _findWater();
  }

  /// The water this is floating on, once resolved.
  WaterComponent? get resolvedWater {
    _resolve();
    return water ?? _found;
  }

  /// Searches the node's ancestors and their subtrees for a water surface
  /// covering the node's position, then for any water at all.
  WaterComponent? _findWater() {
    Node root = node;
    while (root.parent != null) {
      root = root.parent!;
    }
    WaterComponent? fallback;
    final position = node.globalTransform.getTranslation();
    void walk(Node current) {
      final surface = current.getComponent<WaterComponent>();
      if (surface != null) {
        fallback ??= surface;
        final local = _toWaterFrame(current, position);
        if (surface.covers(local.x, local.z)) {
          fallback = surface;
        }
      }
      for (final child in current.children) {
        walk(child);
      }
    }

    walk(root);
    return fallback;
  }

  static vm.Vector3 _toWaterFrame(Node waterNode, vm.Vector3 worldPoint) {
    final inverse = vm.Matrix4.inverted(waterNode.globalTransform);
    return inverse.transform3(worldPoint.clone());
  }

  @override
  void update(double deltaSeconds) {
    if (deltaSeconds <= 0) return;
    _resolve();
    final surface = water ?? _found;
    if (surface == null || !surface.isAttached) {
      _isFloating = false;
      return;
    }

    final waterNode = surface.node;
    final toWater = vm.Matrix4.inverted(waterNode.globalTransform);
    final waterToWorld = waterNode.globalTransform;
    final waves = surface.waves;
    final time = surface.time;
    // Normalized by the whole spectrum, the way the mesh is, so a float sits
    // on the surface a viewer can see rather than near it.
    final spread = waves.length;

    final half = hullSize * 0.5;
    final probes = _probeOffsets(probeCount, half);
    final probeTotal = probes.length ~/ 2;
    final body = _body;
    final dynamicBody =
        body != null && body.type == BodyType.dynamic_ && body.isMounted;

    var contacts = 0;
    var depthSum = 0.0;
    var heightSum = 0.0;
    var normalX = 0.0, normalY = 0.0, normalZ = 0.0;
    var covered = false;

    for (var i = 0; i < probes.length; i += 2) {
      _scratch.setValues(probes[i], 0, probes[i + 1]);
      final world = node.globalTransform.transform3(_scratch.clone());
      final local = toWater.transform3(world.clone());
      if (surface.covers(local.x, local.z)) covered = true;
      GerstnerField.sampleInto(
        waves,
        time,
        local.x,
        local.z,
        _sample,
        normalization: spread,
      );
      // The surface height in world terms, which is what the probe's own
      // height has to be compared against.
      _scratch.setValues(local.x, _sample[1], local.z);
      final surfaceWorld = waterToWorld.transform3(_scratch);
      final depth = surfaceWorld.y - (world.y - draft);
      heightSum += surfaceWorld.y;
      normalX += _sample[3];
      normalY += _sample[4];
      normalZ += _sample[5];

      if (depth > 0) {
        contacts++;
        depthSum += depth;
        if (dynamicBody) {
          // Archimedes, roughly: the push is proportional to how much of the
          // probe is under, capped at the hull's own size, because a hull
          // cannot be more submerged than it is tall. Without the cap a crate
          // that spawns deep underwater is launched out of the sea.
          final submerged = math.min(depth, math.max(hullSize, 0.01));
          body.applyForce(
            vm.Vector3(0, strength * submerged * 2 / probeTotal, 0),
            atWorldPoint: world,
          );
        }
      }
    }

    _submersion = contacts == 0 ? -1 : depthSum / contacts;

    if (dynamicBody) {
      // A body floats because the water pushed it. Contact is the whole
      // question: out of the water there is nothing to push.
      _isFloating = contacts > 0;
      if (!_isFloating) return;
      // Drag scaled by how much of the hull is actually wet, so a boat
      // leaving the water is not still being slowed by it.
      final wetness = contacts / probeTotal;
      final linear = math.exp(-linearDamping * wetness * deltaSeconds);
      final angular = math.exp(-angularDamping * wetness * deltaSeconds);
      body.linearVelocity = body.linearVelocity * linear;
      body.angularVelocity = body.angularVelocity * angular;
      return;
    }

    // No body, so no gravity to fall under and nothing to push against: the
    // node is placed on the surface rather than accelerated toward it. Being
    // over the water is the only condition -- a raft dropped in from above
    // lands on it, and a raft that drifts past the shore is let go.
    _isFloating = covered;
    if (!covered) return;

    final targetY = heightSum / probeTotal + draft;
    final position = node.position;
    node.position = vm.Vector3(position.x, targetY, position.z);

    if (!alignToSurface) return;
    _scratch.setValues(normalX, normalY, normalZ);
    if (_scratch.length2 < 1e-9) return;
    _scratch.normalize();
    // Damped rather than snapped: a raft matching the normal exactly would
    // jitter with every ripple that crossed a probe.
    node.rotation = node.rotation.slerp(
      _tiltTo(_scratch),
      _catchUp(alignResponse, deltaSeconds),
    );
  }

  /// The rotation that takes the node's up onto [normal], leaving its heading
  /// alone.
  vm.Quaternion _tiltTo(vm.Vector3 normal) {
    final up = vm.Vector3(0, 1, 0);
    final axis = up.cross(normal);
    final sin = axis.length;
    if (sin < 1e-6) {
      return normal.y >= 0
          ? vm.Quaternion.identity()
          : vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi);
    }
    return vm.Quaternion.axisAngle(
      axis..normalize(),
      math.atan2(sin, up.dot(normal)),
    );
  }

  /// An exponential approach turned into a per-frame fraction, so the tilt
  /// settles at the same rate whatever the frame rate is.
  static double _catchUp(double response, double deltaSeconds) =>
      response <= 0 ? 1.0 : 1 - math.exp(-response * deltaSeconds);

  /// Probe offsets in the node's own XZ plane, x then z, [count] of them.
  static Float64List _probeOffsets(int count, double half) => switch (count) {
    1 => Float64List.fromList([0, 0]),
    8 => Float64List.fromList([
      -half, -half, 0, -half, half, -half, //
      -half, 0, half, 0, //
      -half, half, 0, half, half, half,
    ]),
    _ => Float64List.fromList([
      -half, -half, half, -half, //
      -half, half, half, half,
    ]),
  };

  @override
  Component? cloneFor(Node cloneOwner) => BuoyancyComponent(
    hullSize: hullSize,
    draft: draft,
    probeCount: probeCount,
    strength: strength,
    linearDamping: linearDamping,
    angularDamping: angularDamping,
    alignToSurface: alignToSurface,
    alignResponse: alignResponse,
    water: water,
  );
}
