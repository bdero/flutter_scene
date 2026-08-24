import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Adds organic sinusoidal hovering, bobbing, and wobble to collectible items and props.
/// {@category Gameplay kit}
class FloatingMotionComponent extends Component {
  /// Vertical bob amplitude in world units.
  double hoverAmplitude;

  /// Vertical bob frequency in cycles per second (Hz).
  double hoverFrequency;

  /// Angular tilt wobble amplitude in degrees.
  double wobbleDegrees;

  /// Angular tilt frequency in Hz.
  double wobbleFrequency;

  /// Continuous yaw spin speed in radians per second.
  double spinSpeed;

  vm.Vector3 _initialPosition = vm.Vector3.zero();
  vm.Quaternion _initialRotation = vm.Quaternion.identity();
  double _time = 0.0;
  bool _initialized = false;

  FloatingMotionComponent({
    this.hoverAmplitude = 0.25,
    this.hoverFrequency = 0.8,
    this.wobbleDegrees = 5.0,
    this.wobbleFrequency = 1.2,
    this.spinSpeed = 1.0,
  });

  @override
  void onMount() {
    _initialPosition = node.position.clone();
    _initialRotation = node.rotation.clone();
    _initialized = true;
  }

  @override
  void update(double deltaSeconds) {
    if (!_initialized) onMount();
    if (deltaSeconds <= 0.0 || !isAttached) return;

    _time += deltaSeconds;

    // 1. Calculate vertical bob offset
    final bobOffset =
        math.sin(_time * hoverFrequency * 2 * math.pi) * hoverAmplitude;
    final newPos = _initialPosition + vm.Vector3(0, bobOffset, 0);

    // 2. Calculate tilt and continuous spin
    final tiltRad =
        (wobbleDegrees * math.pi / 180.0) *
        math.sin(_time * wobbleFrequency * 2 * math.pi);
    final spinRad = _time * spinSpeed;

    final spinRot = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), spinRad);
    final tiltRot = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), tiltRad);
    final newRot = _initialRotation * spinRot * tiltRot;

    node.localTransform = vm.Matrix4.compose(newPos, newRot, node.scale);
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    return FloatingMotionComponent(
      hoverAmplitude: hoverAmplitude,
      hoverFrequency: hoverFrequency,
      wobbleDegrees: wobbleDegrees,
      wobbleFrequency: wobbleFrequency,
      spinSpeed: spinSpeed,
    );
  }
}
