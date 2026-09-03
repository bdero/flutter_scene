/// Applies an agent's animation-preview control request to a controller,
/// in the order the MCP tool documents: select, stop, loop, speed, seek,
/// then play/pause. Selecting only fires when the requested animation
/// differs from the loaded one (selecting resets the playhead); seeking
/// lands before playback starts so one call can load, position, and start
/// a clip.
library;

import 'package:scene/scene.dart';

/// The preview-transport surface the intent applies to. [EditorController]
/// implements this as-is.
abstract interface class AnimationPreviewTarget {
  /// The animation currently loaded onto the playhead.
  LocalId? get previewAnimationId;

  /// Loads [id] onto the playhead, resetting its time.
  void selectPreviewAnimation(LocalId id);

  /// Pauses, resets to t=0, and restores previewed nodes.
  void stopPreview();

  /// Sets whether playback wraps at the clip's end.
  void setPreviewLoop(bool loop);

  /// Sets the playback speed multiplier.
  void setPreviewSpeed(double speed);

  /// Moves the playhead to [time] and applies the pose there.
  void seekPreview(double time);

  /// Starts playback.
  void playPreview();

  /// Pauses playback.
  void pausePreview();
}

/// Applies any subset of the transport fields; omitted fields keep their
/// current values.
void applyAnimationPreviewRequest(
  AnimationPreviewTarget target, {
  LocalId? animationId,
  bool? playing,
  bool? loop,
  double? speed,
  double? seek,
  bool? stop,
}) {
  if (animationId != null && animationId != target.previewAnimationId) {
    target.selectPreviewAnimation(animationId);
  }
  if (stop == true) target.stopPreview();
  if (loop != null) target.setPreviewLoop(loop);
  if (speed != null) target.setPreviewSpeed(speed);
  if (seek != null) target.seekPreview(seek);
  switch (playing) {
    case true:
      target.playPreview();
    case false:
      target.pausePreview();
    default:
      break;
  }
}
