import 'dart:math';
import 'dart:ui';

import 'package:vector_math/vector_math.dart' as vm;

import 'orbit_camera.dart';

/// Remote control for one viewport's orbit camera.
///
/// A host creates a handle, hands it to the [ViewportPanel] it wants to
/// steer (which attaches its camera), and drives the pose from outside the
/// widget tree, the editor's MCP camera tools being the motivating case.
class ViewportCameraHandle {
  OrbitCamera? _camera;
  VoidCallback? _onChanged;

  /// Called by the hosting viewport when it comes up.
  void attach(OrbitCamera camera, VoidCallback onChanged) {
    _camera = camera;
    _onChanged = onChanged;
  }

  /// Called by the hosting viewport on dispose. Ignored when another
  /// viewport has attached in the meantime.
  void detach(OrbitCamera camera) {
    if (identical(_camera, camera)) {
      _camera = null;
      _onChanged = null;
    }
  }

  /// The current pose, or null when no viewport is attached.
  ({
    double azimuth,
    double elevation,
    double radius,
    vm.Vector3 target,
    bool orthographic,
  })?
  get pose {
    final camera = _camera;
    if (camera == null) return null;
    return (
      azimuth: camera.azimuth,
      elevation: camera.elevation,
      radius: camera.radius,
      target: camera.target.clone(),
      orthographic: camera.orthographic,
    );
  }

  /// Applies any subset of the pose and repaints the viewport.
  void setPose({
    double? azimuth,
    double? elevation,
    double? radius,
    vm.Vector3? target,
    bool? orthographic,
  }) {
    final camera = _camera;
    if (camera == null) return;
    if (azimuth != null) camera.azimuth = azimuth;
    if (elevation != null) camera.elevation = elevation;
    if (radius != null) camera.radius = max(radius, 0.01);
    if (target != null) camera.target = target.clone();
    if (orthographic != null) camera.orthographic = orthographic;
    _onChanged?.call();
  }

  /// Aims at [bounds]' center and pulls back so the bounds' sphere fits the
  /// camera's 45 degree vertical field of view, keeping the current viewing
  /// angles. [margin] above 1 adds padding.
  void frame(vm.Aabb3 bounds, {double margin = 1.4}) {
    final camera = _camera;
    if (camera == null) return;
    final radius = max((bounds.max - bounds.min).length / 2, 1e-3);
    camera.target = bounds.center.clone();
    camera.radius = radius / sin(pi / 8) * margin;
    _onChanged?.call();
  }
}
