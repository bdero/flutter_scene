import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Evaluated atmospheric lighting colors for a specific sun elevation.
/// {@category Gameplay kit}
class AtmosphericLighting {
  /// Directional sun light color in linear RGB.
  final vm.Vector3 sunColor;

  /// Directional sun light illuminance in lux.
  final double sunIntensity;

  /// Ambient sky illumination color in linear RGB.
  final vm.Vector3 ambientColor;

  /// Shadow darkness factor (0.0 = completely dark, 1.0 = standard shadows).
  final double shadowDarkness;

  /// Creates an atmospheric lighting record.
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

  /// Whether to automatically apply evaluated sun colors and intensities to the light.
  bool applyLightingToTarget;

  DayNightCycleComponent({
    this.timeOfDay = 12.0,
    this.timeSpeed = 0.0,
    this.latitude = 34.0,
    this.sunLightNode,
    this.applyLightingToTarget = true,
  });

  /// Evaluates the normalized sun direction vector looking towards the sun in the sky.
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
      // Daytime
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
      // Twilight transition
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
      // Night
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
        node.children.cast<Node?>().firstWhere(
          (c) => c?.getComponent<DirectionalLightComponent>() != null,
          orElse: () => null,
        );

    if (targetNode == null) return;

    final sunDir = sunDirection;
    final eye = sunDir * 100.0;
    final target = vm.Vector3.zero();

    // In flutter_scene, DirectionalLightComponent travels along local +Z
    final forward = (target - eye).normalized();
    var up = vm.Vector3(0, 1, 0);
    if (up.cross(forward).length2 < 1e-6) {
      up = vm.Vector3(0, 0, 1);
    }
    final right = up.cross(forward).normalized();
    final actualUp = forward.cross(right).normalized();

    final worldMat = vm.Matrix4.columns(
      vm.Vector4(right.x, right.y, right.z, 0.0),
      vm.Vector4(actualUp.x, actualUp.y, actualUp.z, 0.0),
      vm.Vector4(forward.x, forward.y, forward.z, 0.0),
      vm.Vector4(eye.x, eye.y, eye.z, 1.0),
    );

    final parent = targetNode.parent;
    if (parent != null) {
      final invParent = parent.globalTransform.clone()..invert();
      targetNode.localTransform = invParent * worldMat;
    } else {
      targetNode.localTransform = worldMat;
    }

    if (applyLightingToTarget) {
      final lightComp = targetNode.getComponent<DirectionalLightComponent>();
      if (lightComp != null) {
        final lighting = evaluateLighting();
        lightComp.light.color = lighting.sunColor;
        lightComp.light.intensity = lighting.sunIntensity;
      }
    }
  }

  @override
  Component? cloneFor(Node cloneOwner) {
    if (sunLightNode != null) {
      return null;
    }
    return DayNightCycleComponent(
      timeOfDay: timeOfDay,
      timeSpeed: timeSpeed,
      latitude: latitude,
      applyLightingToTarget: applyLightingToTarget,
    );
  }
}
