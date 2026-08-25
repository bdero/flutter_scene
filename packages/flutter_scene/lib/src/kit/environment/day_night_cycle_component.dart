import 'dart:math' as math;
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/components/directional_light_component.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/sky_sources.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Evaluated atmospheric lighting parameters for a specific sun elevation.
/// {@category Gameplay kit}
class AtmosphericLighting {
  /// Directional sun light color in linear RGB.
  final vm.Vector3 sunColor;

  /// Directional sun light illuminance in lux.
  final double sunIntensity;

  /// Ambient environment intensity multiplier for `Scene.environmentIntensity`.
  final double environmentIntensity;

  /// Shadow darkness factor (0.0 = completely dark, 1.0 = standard shadows).
  final double shadowDarkness;

  /// Creates an atmospheric lighting record.
  AtmosphericLighting({
    required this.sunColor,
    required this.sunIntensity,
    required this.environmentIntensity,
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

  /// Optional procedural physical sky whose sun direction is synchronized.
  PhysicalSkySource? skySource;

  /// Optional target scene whose environment intensity is synchronized.
  Scene? targetScene;

  /// Whether to automatically apply evaluated sun colors and intensities to the light.
  bool applyLightingToTarget;

  /// When true, the directional sun light contributes pure shadow casting with 0 direct illuminance.
  bool shadowOnly;

  DayNightCycleComponent({
    this.timeOfDay = 12.0,
    this.timeSpeed = 0.0,
    this.latitude = 34.0,
    this.sunLightNode,
    this.skySource,
    this.targetScene,
    this.applyLightingToTarget = true,
    this.shadowOnly = false,
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

    if (elevation > 0.0) {
      // Sun above horizon: smooth daylight to golden hour / sunset
      final t = elevation.clamp(0.0, 1.0);
      final smoothT = math.sin(t * math.pi * 0.5);
      final sunColor =
          vm.Vector3(1.0, 0.95, 0.88) * smoothT +
          vm.Vector3(1.0, 0.55, 0.20) * (1.0 - smoothT);
      final intensity = shadowOnly ? 0.0 : (3.0 * smoothT);
      return AtmosphericLighting(
        sunColor: sunColor,
        sunIntensity: intensity,
        environmentIntensity: (0.3 + 0.5 * smoothT).clamp(0.0, 1.0),
        shadowDarkness: (0.3 + 0.7 * smoothT).clamp(0.0, 1.0),
      );
    } else {
      // Sun below horizon: smooth transition from dusk / twilight to starry night
      final nightT = (-elevation / 0.4).clamp(0.0, 1.0);
      final duskColor = vm.Vector3(1.0, 0.55, 0.20);
      final nightSunColor = vm.Vector3(0.20, 0.30, 0.50);
      final sunColor = duskColor * (1.0 - nightT) + nightSunColor * nightT;
      return AtmosphericLighting(
        sunColor: sunColor,
        sunIntensity: 0.0,
        environmentIntensity: (0.3 * (1.0 - nightT) + 0.08 * nightT).clamp(
          0.0,
          1.0,
        ),
        shadowDarkness: 0.0,
      );
    }
  }

  @override
  void update(double deltaSeconds) {
    if (timeSpeed != 0.0 && deltaSeconds > 0.0) {
      timeOfDay = (timeOfDay + timeSpeed * deltaSeconds) % 24.0;
    }

    final sunDir = sunDirection;
    if (skySource != null) {
      skySource!.sunDirection = sunDir;
    }

    final targetNode =
        sunLightNode ??
        node.children.cast<Node?>().firstWhere(
          (c) => c?.getComponent<DirectionalLightComponent>() != null,
          orElse: () => null,
        );

    if (targetNode == null) return;

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
      final lighting = evaluateLighting();
      final lightComp = targetNode.getComponent<DirectionalLightComponent>();
      if (lightComp != null) {
        lightComp.light.color = lighting.sunColor;
        lightComp.light.intensity = lighting.sunIntensity;
        lightComp.light.castsShadow = lighting.shadowDarkness > 0.0;
        lightComp.light.shadowAmbientStrength = (1.0 - lighting.shadowDarkness)
            .clamp(0.0, 1.0);
      }
      if (targetScene != null) {
        targetScene!.environmentIntensity = lighting.environmentIntensity;
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
      skySource: skySource,
      targetScene: targetScene,
      applyLightingToTarget: applyLightingToTarget,
      shadowOnly: shadowOnly,
    );
  }
}
