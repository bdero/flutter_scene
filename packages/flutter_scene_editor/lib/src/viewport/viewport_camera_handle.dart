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

  ({
    double? azimuth,
    double? elevation,
    double? radius,
    vm.Vector3? target,
    bool? orthographic,
  })?
  _pendingPose;

  /// Called by the hosting viewport when it comes up. [onChanged] reports a
  /// pose something moved. A pose set before any viewport attached (restoring
  /// a saved scene's camera) applies now, unreported, since it is the pose
  /// the document already holds.
  void attach(OrbitCamera camera, VoidCallback onChanged) {
    _camera = camera;
    _onChanged = onChanged;
    final pending = _pendingPose;
    if (pending != null) {
      _pendingPose = null;
      _applyPose(
        azimuth: pending.azimuth,
        elevation: pending.elevation,
        radius: pending.radius,
        target: pending.target,
        orthographic: pending.orthographic,
        report: false,
      );
    }
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

  /// Applies any subset of the pose, repaints the viewport, and reports the
  /// move, since the pose saves with the document.
  void setPose({
    double? azimuth,
    double? elevation,
    double? radius,
    vm.Vector3? target,
    bool? orthographic,
  }) => _applyPose(
    azimuth: azimuth,
    elevation: elevation,
    radius: radius,
    target: target,
    orthographic: orthographic,
    report: true,
  );

  /// Applies a pose the document already holds (a scene restoring its saved
  /// camera), without reporting a move, so opening a file leaves it clean.
  void restorePose({
    double? azimuth,
    double? elevation,
    double? radius,
    vm.Vector3? target,
    bool? orthographic,
  }) => _applyPose(
    azimuth: azimuth,
    elevation: elevation,
    radius: radius,
    target: target,
    orthographic: orthographic,
    report: false,
  );

  void _applyPose({
    double? azimuth,
    double? elevation,
    double? radius,
    vm.Vector3? target,
    bool? orthographic,
    required bool report,
  }) {
    final camera = _camera;
    if (camera == null) {
      _pendingPose = (
        azimuth: azimuth,
        elevation: elevation,
        radius: radius,
        target: target,
        orthographic: orthographic,
      );
      return;
    }
    if (azimuth != null) camera.azimuth = azimuth;
    if (elevation != null) camera.elevation = elevation;
    if (radius != null) camera.radius = max(radius, 0.01);
    if (target != null) camera.target = target.clone();
    if (orthographic != null) camera.orthographic = orthographic;
    if (report) _onChanged?.call();
  }

  /// Aims at [bounds]' center and pulls back so the bounds' sphere fits the
  /// camera's 45 degree vertical field of view, keeping the current viewing
  /// angles. [margin] above 1 adds padding. [aspectRatio] ensures the bounds
  /// also fit a portrait viewport.
  void frame(vm.Aabb3 bounds, {double margin = 1.2, double aspectRatio = 1}) {
    final camera = _camera;
    if (camera == null) return;
    camera.frame(bounds, margin: margin, aspectRatio: aspectRatio);
    _onChanged?.call();
  }
}
