import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_rapier/flutter_scene_rapier.dart';
import 'package:vector_math/vector_math.dart';

/// One wheel of a [RaycastVehicle]: the visual node to pose, whether it is
/// driven and/or steered, plus the per-frame suspension and spin state the
/// controller writes.
class VehicleWheel {
  VehicleWheel({
    required this.node,
    required this.powered,
    required this.steered,
  });

  /// The model node posed each frame (suspension travel, steer, spin).
  final Node node;

  /// Whether engine torque is applied through this wheel.
  final bool powered;

  /// Whether this wheel turns with the steering input.
  final bool steered;

  // Captured on mount: the wheel's rest local transform and its rest center
  // in the chassis body frame (the ray's rest position). Re-captured on every
  // mount so the car can be respawned (unmount + remount).
  Matrix4 _restTransform = Matrix4.identity();
  Vector3 _mountLocal = Vector3.zero();

  // Live state.
  bool grounded = false;
  double _suspensionOffset = 0.0; // Upward visual offset from rest.
  double _spin = 0.0; // Accumulated roll angle, radians.
}

/// A raycast (arcade) car built on a single dynamic chassis body. Each wheel
/// is a downward ray from the chassis; where it hits the ground the
/// controller applies a spring/damper suspension force plus tire friction
/// (lateral grip and longitudinal drive/brake), all bounded by a per-wheel
/// friction circle. The wheel model nodes are posed to follow the
/// suspension, steering, and roll.
///
/// Attach it to the chassis node alongside a [RapierRigidBody] and a
/// collider. Drive it by writing [throttle], [steer], and [handbrake] each
/// frame.
///
/// The controller reads the live chassis pose from the Rapier body and
/// raycasts through the shared world, so it only touches Rapier for those
/// two hooks; the suspension and tire model are engine-agnostic.
class RaycastVehicle extends Component {
  RaycastVehicle({
    required this.wheels,
    this.wheelRadius = 0.58,
    this.suspensionTravel = 0.35,
    this.maxVisualLift = 0.22,
    this.suspensionStiffness = 42000.0,
    this.suspensionDamping = 4200.0,
    this.engineForce = 14000.0,
    this.boostForce = 9000.0,
    this.brakeForce = 30000.0,
    this.rollingResistance = 120.0,
    this.lateralGrip = 16000.0,
    this.tireFriction = 1.1,
    this.maxSteerAngle = 0.5,
    this.steerSpeed = 6.0,
  });

  final List<VehicleWheel> wheels;

  /// Wheel radius in world units; sets where the ray meets the ground and
  /// the roll rate.
  final double wheelRadius;

  /// Maximum suspension extension from the top mount to the wheel's rest.
  final double suspensionTravel;

  /// How far the wheel model may visually rise into its arch under
  /// compression, independent of the physics [suspensionTravel]. Kept below
  /// the arch clearance so a hard bump never pushes the wheel through the
  /// body mesh, while the physics stays compliant.
  final double maxVisualLift;

  /// Spring rate (force per unit compression) and damper rate (force per
  /// unit compression velocity).
  final double suspensionStiffness;
  final double suspensionDamping;

  /// Longitudinal force a powered wheel applies at full throttle, and the
  /// braking force at full handbrake. Both are clamped by the friction
  /// circle so grip, not the raw number, sets the limit.
  final double engineForce;
  final double brakeForce;

  /// Extra forward thrust applied at the chassis center while [boost] is held
  /// and the car is driving forward on the ground. Applied at the center of
  /// mass (not through the tires), so it is not grip-limited and does not
  /// cause wheelspin, it just accelerates harder.
  final double boostForce;

  /// Passive longitudinal drag that slows a coasting car (force per m/s).
  final double rollingResistance;

  /// Lateral grip: sideways force per m/s of side-slip, before the friction
  /// circle clamp. Higher corners harder before sliding.
  final double lateralGrip;

  /// Friction-circle coefficient: the combined tire force is capped at
  /// `tireFriction * suspensionForce`, so a lightly loaded wheel grips less.
  final double tireFriction;

  /// Steering lock in radians, and how fast the steer angle eases toward the
  /// input (per second).
  final double maxSteerAngle;
  final double steerSpeed;

  /// Control inputs, written by the driver each frame. All in `[-1, 1]`
  /// except [handbrake] and [boost].
  double throttle = 0.0;
  double steer = 0.0;
  bool handbrake = false;
  bool boost = false;

  RapierRigidBody? _body;
  RapierWorld? _world;
  double _steerAngle = 0.0;

  /// Forward speed along the chassis, in world units per second. Useful for a
  /// speedometer readout.
  double get forwardSpeed => _forwardSpeed;
  double _forwardSpeed = 0.0;

  @override
  void onMount() {
    final body = node.getComponent<RapierRigidBody>();
    if (body == null) return;
    _body = body;
    _world = body.nativeWorld;

    // Capture each wheel's rest pose and its rest center in the chassis body
    // frame. Reading it from the live transforms keeps the controller
    // agnostic to the model's import flip and layout. Capture once (the true
    // rest), but zero the live state on every mount so a respawn starts clean.
    final invBody = node.globalTransform.clone()..invert();
    for (final wheel in wheels) {
      if (!_captured) {
        wheel._restTransform = wheel.node.localTransform.clone();
        final worldCenter = wheel.node.globalTransform.getTranslation();
        wheel._mountLocal = invBody.transformed3(worldCenter);
      }
      wheel._spin = 0.0;
      wheel._suspensionOffset = 0.0;
      wheel.grounded = false;
    }
    _captured = true;
    _steerAngle = 0.0;
    _forwardSpeed = 0.0;
  }

  bool _captured = false;

  @override
  void onUnmount() {
    _body = null;
    _world = null;
  }

  @override
  void fixedUpdate(double fixedDt) {
    final body = _body;
    final world = _world;
    if (body == null || world == null || fixedDt <= 0) return;

    final origin = body.readNativeTranslation();
    final basis = body.readNativeRotation().asRotationMatrix();
    final up = basis.transformed(Vector3(0, 1, 0));
    final chassisForward = basis.transformed(Vector3(1, 0, 0));

    // Ease the steer angle toward the input so the wheels do not snap.
    final targetSteer = steer.clamp(-1.0, 1.0) * maxSteerAngle;
    _steerAngle +=
        (targetSteer - _steerAngle) * (1.0 - math.exp(-steerSpeed * fixedDt));

    final linVel = body.linearVelocity;
    final angVel = body.angularVelocity;
    _forwardSpeed = linVel.dot(chassisForward);

    var anyGrounded = false;
    for (final wheel in wheels) {
      final mountWorld = origin + basis.transformed(wheel._mountLocal.clone());
      final rayOrigin = mountWorld + up * suspensionTravel;
      final hit = world.raycast(
        Ray.originDirection(rayOrigin, -up),
        maxDistance: suspensionTravel + wheelRadius,
        // Rays read the drivable surface (fixed ground and ramps) and must
        // skip the car's own dynamic chassis, so dynamic bodies are excluded.
        // TODO(vehicle-ray-filter): drop this once raycast can exclude a
        // specific body, so the car can also drive over dynamic props.
        includeDynamic: false,
      );

      if (hit == null) {
        wheel.grounded = false;
        // Relax the wheel back to full droop while airborne.
        wheel._suspensionOffset +=
            (0.0 - wheel._suspensionOffset) * (1.0 - math.exp(-8.0 * fixedDt));
        continue;
      }
      wheel.grounded = true;
      anyGrounded = true;

      // Suspension length from the top mount to the wheel center.
      final currentLength = (hit.distance - wheelRadius).clamp(
        0.0,
        suspensionTravel,
      );
      // Visual lift is capped so the wheel never rises through the arch, even
      // though the physics below uses the full compression.
      wheel._suspensionOffset = math.min(
        suspensionTravel - currentLength,
        maxVisualLift,
      );

      // Velocity of the chassis at the contact point.
      final r = hit.worldPoint - origin;
      final pointVel = linVel + angVel.cross(r);

      // Spring + damper along the suspension axis, never pulling down.
      final upVel = pointVel.dot(up);
      var suspensionForce =
          suspensionStiffness * (suspensionTravel - currentLength) -
          suspensionDamping * upVel;
      if (suspensionForce < 0) suspensionForce = 0;
      body.applyForce(up * suspensionForce, atWorldPoint: mountWorld);

      // Tire basis in the contact plane. Right is up x forward; steered
      // wheels rotate their basis about the chassis up axis.
      var wheelForward = chassisForward.clone();
      var wheelRight = up.cross(chassisForward)..normalize();
      if (wheel.steered && _steerAngle != 0) {
        final c = math.cos(_steerAngle);
        final s = math.sin(_steerAngle);
        final f = wheelForward * c + wheelRight * s;
        final rt = wheelRight * c - wheelForward * s;
        wheelForward = f;
        wheelRight = rt;
      }

      final lonVel = pointVel.dot(wheelForward);
      final latVel = pointVel.dot(wheelRight);

      // Longitudinal: drive, handbrake, and passive rolling resistance.
      var lonForce = 0.0;
      if (wheel.powered) lonForce += throttle.clamp(-1.0, 1.0) * engineForce;
      lonForce -= lonVel * rollingResistance;
      if (handbrake) lonForce -= lonVel * brakeForce;

      // Lateral: resist side-slip.
      final latForce = -latVel * lateralGrip;

      // Clamp the combined tire force to the friction circle set by load.
      final maxForce = suspensionForce * tireFriction;
      var fx = lonForce;
      var fy = latForce;
      final mag = math.sqrt(fx * fx + fy * fy);
      if (maxForce > 0 && mag > maxForce) {
        final k = maxForce / mag;
        fx *= k;
        fy *= k;
      }
      body.applyForce(
        wheelForward * fx + wheelRight * fy,
        atWorldPoint: hit.worldPoint,
      );

      // Roll the wheel from the ground speed under it.
      wheel._spin += (lonVel / wheelRadius) * fixedDt;
    }

    // Boost: extra straight-line thrust at the chassis center while driving
    // forward on the ground, so holding it accelerates harder.
    final throttleForward = throttle.clamp(0.0, 1.0);
    if (boost && anyGrounded && throttleForward > 0) {
      body.applyForce(chassisForward * (boostForce * throttleForward));
    }
  }

  @override
  void update(double deltaSeconds) {
    for (final wheel in wheels) {
      final steerAngle = wheel.steered ? _steerAngle : 0.0;
      wheel.node.localTransform =
          Matrix4.translation(Vector3(0, wheel._suspensionOffset, 0)) *
          wheel._restTransform *
          Matrix4.rotationY(-steerAngle) *
          Matrix4.rotationZ(-wheel._spin);
    }
  }
}
