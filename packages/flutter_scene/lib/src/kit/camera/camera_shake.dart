import 'dart:math' as math;
import 'package:flutter_scene/src/noise/fast_noise_lite.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Evaluated translational and rotational camera shake offsets.
/// {@category Gameplay kit}
class CameraShakeOffset {
  /// Translational displacement offset in local camera units.
  final vm.Vector3 translation;

  /// Rotational pitch, yaw, and roll angles in radians.
  final vm.Vector3 rotationEuler;

  /// Creates a camera shake offset.
  CameraShakeOffset({required this.translation, required this.rotationEuler});

  /// Returns a fresh zero-displacement offset instance.
  static CameraShakeOffset get zero => CameraShakeOffset(
    translation: vm.Vector3.zero(),
    rotationEuler: vm.Vector3.zero(),
  );

  /// Converts this offset into a local transform matrix.
  vm.Matrix4 toMatrix4() {
    final rot = vm.Quaternion.euler(
      rotationEuler.y,
      rotationEuler.x,
      rotationEuler.z,
    );
    return vm.Matrix4.compose(translation, rot, vm.Vector3.all(1.0));
  }
}

/// Procedural trauma-decay camera shake generator driven by deterministic noise.
/// {@category Gameplay kit}
class CameraShake {
  /// Current stress/trauma level between 0.0 (still) and 1.0 (maximum shake).
  double trauma = 0.0;

  /// Linear trauma decay rate per second.
  double decayRate;

  /// Frequency multiplier for noise evaluation.
  double frequency;

  /// Maximum translational shake vector (in local units) at trauma = 1.0.
  vm.Vector3 maxTranslation;

  /// Maximum rotational shake angles (in radians, pitch/yaw/roll) at trauma = 1.0.
  vm.Vector3 maxRotation;

  final FastNoiseLite _noise = FastNoiseLite(seed: 1337)
    ..noiseType = NoiseType.openSimplex2;

  double _time = 0.0;

  /// Creates a camera shake generator with optional decay and limit parameters.
  CameraShake({
    this.decayRate = 1.2,
    this.frequency = 25.0,
    vm.Vector3? maxTranslation,
    vm.Vector3? maxRotation,
  }) : maxTranslation = maxTranslation ?? vm.Vector3(0.2, 0.2, 0.1),
       maxRotation = maxRotation ?? vm.Vector3(0.06, 0.06, 0.04);

  /// Adds a burst of trauma (e.g. 0.3 for a footstep, 0.8 for an explosion).
  void addTrauma(double amount) {
    trauma = (trauma + amount).clamp(0.0, 1.0);
  }

  /// Advances the shake simulation by [deltaSeconds] and returns the offset.
  CameraShakeOffset update(double deltaSeconds) {
    if (deltaSeconds <= 0.0 || trauma <= 0.0) {
      return CameraShakeOffset.zero;
    }

    _time += deltaSeconds * frequency;
    final shakePower = trauma * trauma;

    final tx = _noise.getNoise2(_time, 0.0) * maxTranslation.x * shakePower;
    final ty = _noise.getNoise2(_time, 100.0) * maxTranslation.y * shakePower;
    final tz = _noise.getNoise2(_time, 200.0) * maxTranslation.z * shakePower;

    final rx = _noise.getNoise2(_time, 300.0) * maxRotation.x * shakePower;
    final ry = _noise.getNoise2(_time, 400.0) * maxRotation.y * shakePower;
    final rz = _noise.getNoise2(_time, 500.0) * maxRotation.z * shakePower;

    trauma = math.max(0.0, trauma - decayRate * deltaSeconds);

    return CameraShakeOffset(
      translation: vm.Vector3(tx, ty, tz),
      rotationEuler: vm.Vector3(rx, ry, rz),
    );
  }
}
