import 'package:flutter/animation.dart' show Curve;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/camera_controllers/camera_path.dart';
import 'package:flutter_scene/src/camera_pose.dart';
import 'package:flutter_scene/src/node.dart';

/// A camera that travels along a [CameraPath]: the workhorse of a scripted
/// camera move.
///
/// Everything about the shot is separable. The path says *where* the camera
/// goes, [speed] or [duration] says *how fast*, and the aim says *what it
/// looks at* — a node it tracks, a fixed point, or simply ahead along its own
/// track. Change any one without disturbing the others.
///
/// Because the path is arc-length parameterized, a constant [speed] really is
/// constant: the camera does not surge through the bunched-up parts of the
/// curve. Use [duration] instead when the move has to fit an exact time, and
/// [easing] to shape its acceleration.
///
/// ```dart
/// // A slow push past the hero, aimed at them the whole way.
/// final shot = DollyCameraController(
///   path: CameraPath([Vector3(-8, 2, -6), Vector3(0, 2, -2), Vector3(8, 2, -6)]),
///   lookTarget: hero,
///   duration: 6.0,
///   easing: Curves.easeInOut,
/// );
/// director.blendTo(shot, duration: 1.0);
/// ```
///
/// The controller reports [isFinished] and fires [onFinished] when it reaches
/// the end of an unlooped path, which is the cue to hand the shot back:
///
/// ```dart
/// shot.onFinished = () => director.clearSelection();
/// ```
/// {@category Scene graph}
class DollyCameraController extends CameraController {
  /// Creates a camera riding [path].
  ///
  /// Give either a [speed] in world units per second or a [duration] in
  /// seconds for the whole path; [duration] wins when both are set.
  DollyCameraController({
    required this.path,
    this.lookTarget,
    Vector3? lookPoint,
    this.lookAhead = 2.0,
    this.speed = 4.0,
    this.duration,
    this.easing,
    this.loop = false,
    this.playing = true,
    this.lens,
    Vector3? up,
    this.onFinished,
    super.smoothing = 0.0,
  }) : _lookPoint = lookPoint?.clone(),
       up = (up ?? Vector3(0.0, 1.0, 0.0)).clone();

  /// The curve the camera travels along.
  CameraPath path;

  /// A node to keep in frame. Takes precedence over [lookPoint] and
  /// [lookAhead].
  Node? lookTarget;

  /// How far ahead along the path the camera looks when it has no other aim.
  /// Zero aims exactly along the tangent.
  double lookAhead;

  /// Travel rate in world units per second. Ignored when [duration] is set.
  double speed;

  /// How long the whole path should take, in seconds. Overrides [speed].
  double? duration;

  /// Shapes the progress when [duration] is set, so a move can ease in and
  /// out instead of starting and stopping abruptly. Ignored under [speed],
  /// where constant velocity is the point.
  Curve? easing;

  /// Whether the camera wraps to the start on reaching the end.
  bool loop;

  /// Whether the camera is advancing. False holds it wherever it is.
  bool playing;

  /// The lens this shot asks for, or null to leave the camera's own alone.
  /// Under a [CameraDirector] a lens set here blends in with the shot.
  CameraProjection? lens;

  /// The reference up for the camera's roll.
  ///
  /// Rarely changed. A shot that aims straight along this axis — a crane
  /// looking down at the floor — has no roll defined by it, so the
  /// controller substitutes a perpendicular of its own for those frames
  /// rather than failing.
  Vector3 up;

  /// Called once when an unlooped path reaches its end.
  void Function()? onFinished;

  Vector3? _lookPoint;
  double _travelled = 0.0;
  double _elapsed = 0.0;
  bool _finished = false;
  Vector3? _aim;

  /// A fixed world-space point to look at. Overridden by [lookTarget].
  Vector3? get lookPoint => _lookPoint?.clone();
  set lookPoint(Vector3? value) => _lookPoint = value?.clone();

  /// How far along the path the camera has travelled, in world units.
  double get distanceAlong => _travelled;

  /// Progress along the path, `0` to `1`.
  double get progress {
    final total = path.length;
    return total <= 0.0 ? 1.0 : (_travelled / total).clamp(0.0, 1.0);
  }

  /// Whether an unlooped path has reached its end.
  bool get isFinished => _finished;

  /// Starts or resumes travel.
  void play() => playing = true;

  /// Holds the camera where it is.
  void pause() => playing = false;

  /// Jumps to [fraction] of the way along the path, `0` to `1`.
  void seek(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    _travelled = clamped * path.length;
    _elapsed = clamped * (duration ?? 0.0);
    _finished = false;
    _aim = null;
  }

  /// Returns to the start and plays from there.
  void restart() {
    seek(0.0);
    playing = true;
  }

  @override
  void advance(double deltaSeconds) {
    final total = path.length;
    if (playing && total > 0.0) {
      final fixedDuration = duration;
      if (fixedDuration != null && fixedDuration > 0.0) {
        _elapsed += deltaSeconds;
        var fraction = _elapsed / fixedDuration;
        if (loop) {
          fraction %= 1.0;
        } else if (fraction >= 1.0) {
          fraction = 1.0;
          _reachedEnd();
        }
        final curve = easing;
        _travelled =
            (curve == null ? fraction : curve.transform(fraction)) * total;
      } else {
        _travelled += speed * deltaSeconds;
        if (loop) {
          _travelled %= total;
        } else if (_travelled >= total) {
          _travelled = total;
          _reachedEnd();
        }
      }
    }

    final position = path.pointAt(_travelled);
    final desiredAim = _resolveAim(position, total);

    // Ease the aim rather than the position: the path already decides where
    // the camera is, and smoothing that would fight it. Smoothing what it
    // looks at is what keeps a tracked subject from jittering.
    final aim = _aim;
    if (aim == null || smoothing <= 0.0) {
      _aim = desiredAim;
    } else {
      aim.addScaled(desiredAim - aim, smoothingResponse(deltaSeconds));
    }

    final aimPoint = _aim!;
    setPose(
      CameraPose.lookAt(
        position,
        aimPoint,
        up: _referenceUp(aimPoint - position),
        projection: lens,
      ),
    );
  }

  /// An up vector guaranteed not to be parallel to [direction].
  ///
  /// A camera looking straight up or straight down has no roll defined by a
  /// vertical reference, and a look-at built from one is degenerate. Rather
  /// than making the caller notice, the shot falls back to its own direction
  /// of travel, flattened against the reference: the roll then stays
  /// continuous as the camera swings through vertical instead of snapping to
  /// an arbitrary axis on the frame it crosses.
  Vector3 _referenceUp(Vector3 direction) {
    if (direction.length2 < 1e-12) return up;
    final preferred = up.normalized();
    if (direction.normalized().dot(preferred).abs() < 0.999) return up;

    final tangent = path.tangentAt(_travelled);
    final flattened = tangent - preferred * tangent.dot(preferred);
    if (flattened.length2 > 1e-6) return flattened.normalized();
    // Travelling straight along the reference too (a pure vertical rise
    // looking straight down). Any perpendicular is as good as another.
    return preferred.x.abs() < 0.9
        ? Vector3(1.0, 0.0, 0.0)
        : Vector3(0.0, 0.0, 1.0);
  }

  Vector3 _resolveAim(Vector3 position, double total) {
    final target = lookTarget;
    if (target != null) return target.globalTransform.getTranslation();
    final fixed = _lookPoint;
    if (fixed != null) return fixed.clone();
    if (lookAhead > 0.0 && total > 0.0) {
      final ahead = _travelled + lookAhead;
      // Past the end of an open path there is nothing ahead to aim at, so
      // fall back to extending the tangent rather than pinning to the last
      // point (which would leave the aim undefined).
      if (path.closed || ahead < total) return path.pointAt(ahead);
    }
    return position + path.tangentAt(_travelled);
  }

  void _reachedEnd() {
    if (_finished) return;
    _finished = true;
    onFinished?.call();
  }
}
