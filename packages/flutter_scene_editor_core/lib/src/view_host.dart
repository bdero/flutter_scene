/// The transient viewport state view commands reach.
///
/// Selection lives on the session, but the camera belongs to whatever is
/// rendering, so the host implements this and the session holds it. A session
/// with no host (headless, tests) simply has no view commands that apply.
library;

import 'package:scene/scene.dart';

/// The viewport a view command acts on.
abstract class ViewHost {
  /// The current camera pose.
  EditorCameraSpec get camera;

  /// Moves the camera to [pose].
  void setCamera(EditorCameraSpec pose);

  /// Frames [ids]. Returns false when none of them has renderable bounds.
  bool frame(Iterable<LocalId> ids);
}
