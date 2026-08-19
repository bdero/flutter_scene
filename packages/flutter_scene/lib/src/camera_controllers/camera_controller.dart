import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show KeyEvent;

import 'package:flutter_scene/src/components/component.dart';

/// Drives a camera node's transform from continuous input.
///
/// A camera controller is a [Component] you attach to the node that carries a
/// [CameraComponent]. It owns the camera's state (where it is, what it looks
/// at) and eases toward that state every frame, writing the owning node's
/// transform through [Node.lookAtFrom]. Input arrives as device-agnostic
/// intent (drag, scroll, keys) which the concrete controllers map to their own
/// motion; the [CameraControls] widget forwards raw Flutter input here, and
/// application code can call the same hooks (or the higher-level intent methods
/// on each subclass) directly.
///
/// Smoothing is frame-rate independent: [smoothing] is the approximate time in
/// seconds the camera takes to settle after input stops, so the feel is the
/// same at any frame rate. Concrete controllers: [OrbitCameraController],
/// [FlyCameraController], [FollowCameraController].
/// {@category Scene graph}
abstract class CameraController extends Component {
  /// Creates a controller with the given [smoothing] settle time in seconds.
  CameraController({this.smoothing = 0.12});

  /// Approximate time in seconds to settle after input stops (reach ~1% of the
  /// remaining offset). Zero moves instantly with no easing.
  double smoothing;

  /// The size of the view driving this controller, in logical pixels.
  ///
  /// Set by [CameraControls] so pixel-space input can be normalized to the
  /// view. Defaults to a unit size so a controller driven only through its
  /// intent methods still behaves.
  Size viewportSize = const Size(1.0, 1.0);

  static const double _kLog100 = 4.605170185988091; // -ln(0.01)
  static const double _maxFrameSeconds = 0.1;

  /// The fraction of the remaining offset to consume this frame for a
  /// frame-rate independent exponential settle. One when [smoothing] is zero.
  @protected
  double smoothingResponse(double deltaSeconds) =>
      settleResponse(smoothing, deltaSeconds);

  /// [smoothingResponse] for an explicit [smoothingSeconds], so a controller
  /// can settle different quantities (look versus movement) at different rates.
  @protected
  double settleResponse(double smoothingSeconds, double deltaSeconds) {
    if (smoothingSeconds <= 0.0) return 1.0;
    return 1.0 - math.exp(-_kLog100 * deltaSeconds / smoothingSeconds);
  }

  /// Clamps a frame delta so a stall or a paused view does not teleport the
  /// camera when it resumes.
  @protected
  double clampDeltaSeconds(double deltaSeconds) =>
      deltaSeconds.clamp(0.0, _maxFrameSeconds);

  /// A primary drag (one finger, or a left-button mouse drag), in logical
  /// pixels. The default rotates/looks; override to remap.
  void handleDragUpdate(Offset delta) {}

  /// A secondary drag (right-button mouse drag), in logical pixels. The
  /// default pans where the controller supports it.
  void handleSecondaryDragUpdate(Offset delta) {}

  /// A two-plus finger gesture: [scaleFactor] is the incremental pinch factor
  /// since the last update (>1 spreading, <1 pinching) and [focalDelta] is the
  /// centroid movement in logical pixels.
  void handleScaleUpdate(double scaleFactor, Offset focalDelta) {}

  /// A scroll/wheel notch; [scrollDelta] follows the platform sign (positive
  /// scrolling down/away).
  void handleScroll(double scrollDelta) {}

  /// A keyboard event; controllers that move on keys track held state here.
  /// Returns true when the key is consumed (so the driver can stop it
  /// propagating and the platform does not beep at a held movement key).
  bool handleKeyEvent(KeyEvent event) => false;

  /// Releases any held input (call when the driving view loses focus so keys
  /// released elsewhere do not stick).
  void releaseInput() {}
}
