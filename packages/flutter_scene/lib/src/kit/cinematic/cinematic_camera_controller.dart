import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';
import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/kit/cinematic/camera_track.dart';
import 'package:flutter_scene/src/kit/cinematic/timeline.dart';
import 'package:flutter_scene/src/depth_of_field.dart';

/// Plays a [CameraTrack] on the camera node it is attached to.
///
/// The pose comes from [track] sampled at [timeline]'s playhead, which this
/// controller advances each frame unless [advancesTimeline] is false (when
/// something else owns the timeline, for example a cutscene driving several
/// tracks from one playhead). A perspective [CameraComponent] on the node
/// takes the track's field of view, and a [depthOfField], when given, takes
/// its focus distance and f-number.
///
/// {@category Animation}
class CinematicCameraController extends CameraController {
  /// Creates a controller playing [track] on [timeline].
  CinematicCameraController({
    required this.track,
    required this.timeline,
    this.depthOfField,
    this.advancesTimeline = true,
  }) : super(smoothing: 0);

  /// The camera move.
  CameraTrack track;

  /// The playhead the move is sampled at.
  final Timeline timeline;

  /// Depth of field to drive with the track's focus, or null.
  DepthOfField? depthOfField;

  /// Whether [update] advances [timeline] by the frame delta.
  bool advancesTimeline;

  /// The pose applied most recently.
  CameraSample? get lastSample => _last;
  CameraSample? _last;

  @override
  void update(double deltaSeconds) {
    if (advancesTimeline) timeline.advance(deltaSeconds);
    final sample = _last = track.sampleAt(timeline.time);
    node.lookAtFrom(sample.eye, sample.target, up: sample.up);
    final projection = node.getComponent<CameraComponent>()?.projection;
    if (projection is PerspectiveProjection) {
      projection.fovRadiansY = sample.fovRadiansY;
    }
    final dof = depthOfField;
    if (dof != null) {
      dof
        ..focusDistance = sample.focusDistance
        ..fStop = sample.fStop;
    }
  }
}
