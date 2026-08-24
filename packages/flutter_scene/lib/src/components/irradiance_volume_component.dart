import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/render/irradiance_bake.dart';

/// A [Component] that places the scene's irradiance volume on its node.
///
/// The volume is an axis-aligned box of half-size [extents] centered on the
/// node's world position, subdivided into [resolution] probes. Requires
/// `Scene.globalIllumination.volumeMode` to be
/// `IrradianceVolumeMode.component`.
///
/// One volume is active at a time. When several contain the camera the
/// highest [priority] wins, and the switch resets the field to a fast-
/// converge ramp rather than cross-fading two atlases. That pop is the price
/// of a receiver that stays at eight probe taps instead of sixteen.
/// {@category Lighting and environment}
class IrradianceVolumeComponent extends Component {
  IrradianceVolumeComponent({
    Vector3? extents,
    Vector3? resolution,
    this.priority = 0.0,
    this.intensity,
    this.hysteresis,
    this.visibility,
    this.bake,
  }) : extents = extents ?? Vector3.all(10.0),
       resolution = resolution ?? Vector3(16, 8, 16);

  /// Box half-size in world units, centered on the node's world position.
  Vector3 extents;

  /// Probe count along each axis.
  Vector3 resolution;

  /// Selection order among volumes containing the camera; highest wins.
  double priority;

  /// Overrides that fall back to the scene settings when null.
  double? intensity;
  double? hysteresis;
  double? visibility;

  /// An optional baked irradiance field providing the initial state.
  IrradianceFieldBake? bake;

  bool _invalidated = false;

  /// Whether this volume asked to be refilled from scratch, clearing the
  /// request.
  bool consumeInvalidation() {
    final pending = _invalidated;
    _invalidated = false;
    return pending;
  }

  /// Discards the accumulated field so it refills from scratch.
  void invalidate() => _invalidated = true;

  /// Whether [worldPosition] sits inside this volume.
  bool contains(Vector3 worldPosition) {
    final center = node.globalTransform.getTranslation();
    return (worldPosition.x - center.x).abs() <= extents.x &&
        (worldPosition.y - center.y).abs() <= extents.y &&
        (worldPosition.z - center.z).abs() <= extents.z;
  }

  /// The volume's world-space center.
  Vector3 get worldCenter => node.globalTransform.getTranslation();

  @override
  void onMount() {
    node.internalRenderScene?.addIrradianceVolumeComponent(this);
  }

  @override
  void onUnmount() {
    // Guard on attachment, not mount state: Component.unmount clears the
    // mounted flag before onUnmount and the render scene is still reachable.
    if (isAttached) {
      node.internalRenderScene?.removeIrradianceVolumeComponent(this);
    }
  }
}
