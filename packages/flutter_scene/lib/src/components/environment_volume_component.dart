import 'dart:math' as math;

import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/environment_settings.dart';

/// The region shape of an [EnvironmentVolumeComponent].
/// {@category Lighting and environment}
enum EnvironmentVolumeShape {
  /// An axis-aligned-in-local-space box of half-size
  /// [EnvironmentVolumeComponent.extents].
  box,

  /// A sphere of radius [EnvironmentVolumeComponent.radius].
  sphere,
}

/// A [Component] that contributes a spatial environment volume: a region whose
/// look ([settings]) overrides the scene environment, blended by camera
/// position so the environment transitions as the camera moves between areas.
///
/// The region is defined in the owning node's local space (a [shape] sized by
/// [extents] or [radius]), so the node transform places, orients, and scales
/// it. Coverage is `1` inside and fades to `0` across [blendDistance] (in the
/// node's local units) outside the surface, scaled by [weight]; overlapping
/// volumes apply in [priority] order. While mounted, the component registers
/// with the scene so the renderer folds it into the environment blend.
/// {@category Lighting and environment}
class EnvironmentVolumeComponent extends Component {
  /// Creates a volume contributing [settings] over the region described by
  /// [shape]/[extents]/[radius].
  EnvironmentVolumeComponent({
    required this.settings,
    this.shape = EnvironmentVolumeShape.box,
    Vector3? extents,
    this.radius = 5.0,
    this.blendDistance = 1.0,
    this.priority = 0.0,
    this.weight = 1.0,
  }) : extents = extents ?? Vector3.all(5.0);

  /// The look this volume blends toward where it is in effect.
  EnvironmentSettings settings;

  /// The region shape.
  EnvironmentVolumeShape shape;

  /// Box half-size in local space (used when [shape] is
  /// [EnvironmentVolumeShape.box]).
  Vector3 extents;

  /// Sphere radius in local space (used when [shape] is
  /// [EnvironmentVolumeShape.sphere]).
  double radius;

  /// Local-space fade band outside the region over which the contribution falls
  /// from full to zero. `0` is a hard edge.
  double blendDistance;

  /// Blend order; higher priority volumes are applied later (on top).
  double priority;

  /// Master contribution scale, `0`..`1`.
  double weight;

  @override
  void onMount() {
    node.internalRenderScene?.addEnvironmentVolumeComponent(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state: Component.unmount clears the
    // mounted flag before onUnmount, and the render scene is still reachable
    // during teardown (mirrors DirectionalLightComponent).
    if (isAttached) {
      node.internalRenderScene?.removeEnvironmentVolumeComponent(this);
    }
  }

  /// This volume's coverage at world-space [cameraPosition], `0`..`1` (before
  /// [weight]). Transforms the camera into the node's local space and tests the
  /// local region, so the node transform (including rotation and scale) shapes
  /// the volume.
  double coverage(Vector3 cameraPosition) {
    final worldToLocal = Matrix4.tryInvert(node.globalTransform);
    if (worldToLocal == null) return 0.0;
    final local = worldToLocal.transformed3(cameraPosition);
    final dist = switch (shape) {
      EnvironmentVolumeShape.box => _boxDistance(local, extents),
      EnvironmentVolumeShape.sphere => _sphereDistance(local, radius),
    };
    if (blendDistance <= 0) return dist <= 0 ? 1.0 : 0.0;
    return (1.0 - dist / blendDistance).clamp(0.0, 1.0);
  }
}

// Distance from [point] to a box centered at the local origin with the given
// [halfExtents], `0` inside.
double _boxDistance(Vector3 point, Vector3 halfExtents) {
  final dx = point.x.abs() - halfExtents.x;
  final dy = point.y.abs() - halfExtents.y;
  final dz = point.z.abs() - halfExtents.z;
  final ox = dx > 0 ? dx : 0.0;
  final oy = dy > 0 ? dy : 0.0;
  final oz = dz > 0 ? dz : 0.0;
  return math.sqrt(ox * ox + oy * oy + oz * oz);
}

// Distance from [point] to a sphere centered at the local origin with the given
// [radius], `0` inside.
double _sphereDistance(Vector3 point, double radius) {
  final d = point.length - radius;
  return d > 0 ? d : 0.0;
}
