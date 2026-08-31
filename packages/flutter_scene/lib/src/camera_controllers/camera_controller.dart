import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show KeyEvent;

import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/components/component.dart';

/// Drives a camera's [pose] from continuous input.
///
/// A camera controller owns the camera's state (where it is, what it looks
/// at) and eases toward that state every frame. Input arrives as
/// device-agnostic intent (drag, scroll, keys) which the concrete controllers
/// map to their own motion; the [CameraControls] widget forwards raw Flutter
/// input here, and application code can call the same hooks (or the
/// higher-level intent methods on each subclass) directly.
///
/// A controller can be used two ways:
///
///  * **Directly**, as a [Component] on the node that carries a
///    [CameraComponent]. Each frame it advances and writes its [pose] onto
///    that node. This is the simple case and needs nothing else.
///  * **Through a [CameraDirector]**, as one shot among several. The director
///    advances every camera it holds and writes a *blend* of their poses onto
///    the one real camera node, which is what makes a smooth cut from one
///    camera to another possible. A directed controller does not need to be
///    attached to a node at all.
///
/// Smoothing is frame-rate independent: [smoothing] is the approximate time in
/// seconds the camera takes to settle after input stops, so the feel is the
/// same at any frame rate. Concrete controllers: [OrbitCameraController],
/// [FlyCameraController], [FollowCameraController],
/// [FirstPersonCameraController], [RtsCameraController], and
/// [DollyCameraController].
///
/// ## Writing your own
///
/// Override [advance] to update state and call [setPose] with where the
/// camera should be; the base class handles applying it, and the controller
/// works under a director for free. Override [update] instead only to opt out
/// of the pose contract entirely, in which case the controller cannot be
/// blended.
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
  ///
  /// Virtual so a forwarding controller (a [CameraDirector]'s [CameraDirector.input])
  /// can pass the view size through to whichever camera is live.
  // ignore: unnecessary_getters_setters -- deliberately virtual; see above.
  Size get viewportSize => _viewportSize;
  set viewportSize(Size value) => _viewportSize = value;
  Size _viewportSize = const Size(1.0, 1.0);

  static const double _kLog100 = 4.605170185988091; // -ln(0.01)
  static const double _maxFrameSeconds = 0.1;

  CameraPose _pose = CameraPose.identity;
  CameraDirectorBinding? _director;

  /// Where this controller wants the camera, as of the last advance.
  ///
  /// Freshly constructed controllers report [CameraPose.identity] until they
  /// have advanced once; read it after the first frame, or after calling
  /// [warmUp], rather than immediately after construction.
  CameraPose get pose => _pose;

  /// Whether a [CameraDirector] is driving this controller. While true the
  /// controller does not write to its own node; the director owns that.
  bool get isDirected => _director != null;

  /// Records the pose computed by [advance]. Concrete controllers call this
  /// once per advance.
  @protected
  void setPose(CameraPose value) => _pose = value;

  /// Advances the controller by [deltaSeconds] and refreshes [pose].
  ///
  /// [deltaSeconds] is already clamped by [clampDeltaSeconds]. Subclasses
  /// override this rather than [update], so the same controller works
  /// standalone and under a [CameraDirector].
  @protected
  void advance(double deltaSeconds) {}

  /// Advances the controller by [deltaSeconds] and refreshes [pose], without
  /// writing anything to a node.
  ///
  /// [update] is the normal driver and is called by the scene graph. Reach for
  /// this when the application owns the clock itself — a replay, a headless
  /// simulation, a test — or to compute a pose for something other than the
  /// camera node. A [CameraDirector] drives its cameras through it.
  void step(double deltaSeconds) => advance(clampDeltaSeconds(deltaSeconds));

  /// Advances the controller without a frame passing, so [pose] is valid
  /// before the first tick.
  ///
  /// Useful when a director needs a camera's pose to blend *from* the moment
  /// it is registered, and when framing a shot in a test.
  void warmUp() => advance(0.0);

  @override
  void update(double deltaSeconds) {
    // A director advances its cameras itself, in a defined order, so the
    // blend never reads a pose from the previous frame. Bailing here also
    // keeps a directed controller from fighting the director over a node
    // they happen to share.
    if (_director != null) return;
    advance(clampDeltaSeconds(deltaSeconds));
    _pose.applyTo(node);
  }

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

  /// Binds this controller to a director, or unbinds it with null.
  @internal
  void bindDirector(CameraDirectorBinding? director) {
    assert(
      director == null || _director == null || identical(_director, director),
      'This CameraController is already held by another CameraDirector. A '
      'controller produces one pose per frame and cannot be shared between '
      'directors; give each director its own controller instance.',
    );
    _director = director;
  }
}

/// The slice of [CameraDirector] a [CameraController] knows about, so the
/// controller does not depend on the director's implementation.
/// {@category Scene graph}
abstract class CameraDirectorBinding {}
