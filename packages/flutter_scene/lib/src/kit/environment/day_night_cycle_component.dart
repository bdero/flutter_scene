import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Evaluated atmospheric lighting colors for a specific sun elevation.
/// {@category Gameplay kit}
class AtmosphericLighting {
  final vm.Vector3 sunColor;
  final double sunIntensity;
  final vm.Vector3 ambientColor;
  final double shadowDarkness;

  AtmosphericLighting({
    required this.sunColor,
    required this.sunIntensity,
    required this.ambientColor,
    required this.shadowDarkness,
  });
}

/// Controller driving time-of-day solar movement and dynamic lighting transitions.
/// {@category Gameplay kit}
class DayNightCycleComponent extends Component {
  /// Current time of day in 24-hour decimal format (0.0 to 24.0).
  double timeOfDay;

  /// Speed multiplier for time progression (e.g. 1.0 = 1 game hour per second, 0 = paused).
  double timeSpeed;

  /// Latitude of the world in degrees (-90 to +90).
  double latitude;

  /// Target node hosting the scene's primary directional sun light.
  Node? sunLightNode;

  DayNightCycleComponent({
    this.timeOfDay = 12.0,
    this.timeSpeed = 0.0,
    this.latitude = 34.0,
    this.sunLightNode,
  });

  /// Evaluates the normalized sun direction vector looking towards the sun.
  vm.Vector3 get sunDirection {
    // Solar angle: 0h = -pi, 6h = -pi/2, 12h = 0, 18h = pi/2, 24h = pi
    final solarAngle = (timeOfDay / 24.0) * 2 * math.pi - math.pi;
    final latRad = latitude * math.pi / 180.0;

    final elevation = math.cos(solarAngle) * math.cos(latRad);
    final x = math.sin(solarAngle) * math.cos(latRad);
    final z = math.cos(solarAngle) * math.sin(latRad);
    final y = elevation;

    final dir = vm.Vector3(x, y, z);
    return dir.length2 > 0 ? dir.normalized() : vm.Vector3(0, 1, 0);
  }

  /// Evaluates lighting parameters based on current sun elevation.
  AtmosphericLighting evaluateLighting() {
    final sunDir = sunDirection;
    final elevation = sunDir.y;

    if (elevation > 0.15) {
      // Daytime (Midday / Afternoon)
      final t = ((elevation - 0.15) / 0.85).clamp(0.0, 1.0);
      final sunColor =
          vm.Vector3(1.0, 0.95, 0.85) * t +
          vm.Vector3(1.0, 0.7, 0.4) * (1.0 - t);
      return AtmosphericLighting(
        sunColor: sunColor,
        sunIntensity: 100000.0 * elevation.clamp(0.2, 1.0),
        ambientColor: vm.Vector3(0.2, 0.25, 0.35),
        shadowDarkness: 1.0,
      );
    } else if (elevation > -0.05) {
      // Golden Hour / Twilight transition
      final t = ((elevation + 0.05) / 0.20).clamp(0.0, 1.0);
      final sunColor =
          vm.Vector3(1.0, 0.4, 0.1) * t + vm.Vector3(0.3, 0.1, 0.2) * (1.0 - t);
      return AtmosphericLighting(
        sunColor: sunColor,
        sunIntensity: 30000.0 * t,
        ambientColor: vm.Vector3(0.15, 0.1, 0.2),
        shadowDarkness: 0.8 * t,
      );
    } else {
      // Night (Moonlit)
      return AtmosphericLighting(
        sunColor: vm.Vector3(0.2, 0.3, 0.5),
        sunIntensity: 500.0,
        ambientColor: vm.Vector3(0.02, 0.03, 0.06),
        shadowDarkness: 0.2,
      );
    }
  }

  @override
  void update(double deltaSeconds) {
    if (timeSpeed != 0.0 && deltaSeconds > 0.0) {
      timeOfDay = (timeOfDay + timeSpeed * deltaSeconds) % 24.0;
    }

    final targetNode =
        sunLightNode ??
        (node.children.firstWhere(
          (c) => c.getComponent<DirectionalLightComponent>() != null,
          orElse: () => node,
        ));
    final sunDir = sunDirection;

    // Aim the directional light
    final lightTarget = vm.Vector3.zero();
    final lightEye = sunDir * 100.0;
    final viewMat = vm.makeViewMatrix(
      lightEye,
      lightTarget,
      vm.Vector3(0, 1, 0),
    );
    targetNode.localTransform = viewMat..invert();
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    return DayNightCycleComponent(
      timeOfDay: timeOfDay,
      timeSpeed: timeSpeed,
      latitude: latitude,
    );
  }
}
