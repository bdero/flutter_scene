import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Definition of a single directional Gerstner wave.
/// {@category Gameplay kit}
class GerstnerWave {
  /// Normalized 2D wave propagation direction vector.
  final vm.Vector2 direction;

  /// Crest height amplitude in world units.
  final double amplitude;

  /// Distance between wave crests in world units.
  final double wavelength;

  /// Propagation speed multiplier.
  final double speed;

  /// Trochoidal crest sharpness factor between 0.0 (sine) and 1.0 (sharp crests).
  final double steepness;

  GerstnerWave({
    required this.direction,
    this.amplitude = 0.5,
    this.wavelength = 10.0,
    this.speed = 1.5,
    this.steepness = 0.8,
  });
}

/// Generates and animates realistic trochoidal ocean water surfaces.
/// {@category Gameplay kit}
class WaterSurfaceComponent extends Component {
  /// Active Gerstner wave spectrum.
  final List<GerstnerWave> waves;

  double _time = 0.0;

  WaterSurfaceComponent({List<GerstnerWave>? waves})
    : waves =
          waves ??
          [
            GerstnerWave(
              direction: vm.Vector2(1.0, 0.2).normalized(),
              amplitude: 0.4,
              wavelength: 12.0,
              speed: 1.2,
            ),
            GerstnerWave(
              direction: vm.Vector2(0.5, 0.8).normalized(),
              amplitude: 0.2,
              wavelength: 6.0,
              speed: 1.8,
            ),
            GerstnerWave(
              direction: vm.Vector2(-0.3, 1.0).normalized(),
              amplitude: 0.1,
              wavelength: 3.0,
              speed: 2.2,
            ),
          ];

  /// Evaluates exact wave displacement and surface normal at [pos] at current time.
  ({vm.Vector3 displacement, vm.Vector3 normal}) evaluateAt(
    vm.Vector2 pos, [
    double? customTime,
  ]) {
    final t = customTime ?? _time;
    var disp = vm.Vector3.zero();
    var tangent = vm.Vector3(1, 0, 0);
    var binormal = vm.Vector3(0, 0, 1);

    for (final w in waves) {
      if (w.amplitude <= 0.0 || w.wavelength <= 0.0) continue;

      final k = 2 * math.pi / w.wavelength;
      final c = math.sqrt(9.81 / k);
      final phase =
          k * (w.direction.x * pos.x + w.direction.y * pos.y) -
          (w.speed * c * k) * t;
      final cosP = math.cos(phase);
      final sinP = math.sin(phase);

      final q = w.steepness / (k * w.amplitude * waves.length);

      disp.x += q * w.amplitude * w.direction.x * cosP;
      disp.y += w.amplitude * sinP;
      disp.z += q * w.amplitude * w.direction.y * cosP;

      tangent += vm.Vector3(
        -q * w.direction.x * w.direction.x * k * w.amplitude * sinP,
        w.direction.x * k * w.amplitude * cosP,
        -q * w.direction.x * w.direction.y * k * w.amplitude * sinP,
      );

      binormal += vm.Vector3(
        -q * w.direction.x * w.direction.y * k * w.amplitude * sinP,
        w.direction.y * k * w.amplitude * cosP,
        -q * w.direction.y * w.direction.y * k * w.amplitude * sinP,
      );
    }

    final norm = binormal.cross(tangent).normalized();
    return (displacement: disp, normal: norm);
  }

  @override
  void update(double deltaSeconds) {
    if (deltaSeconds <= 0.0) return;
    _time += deltaSeconds;
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    return WaterSurfaceComponent(waves: List.from(waves));
  }
}
