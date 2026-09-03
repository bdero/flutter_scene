/// Pure name→node resolution for the editor's animation preview.
///
/// Extracted from [EditorController] so the semantics are unit-testable
/// headlessly (no GPU). This mirrors the runtime clip binder's resolution
/// ([AnimationClip._bindToTarget]), so the preview drives exactly what runtime
/// playback drives.
library;

import 'package:flutter_scene/scene.dart';

/// Resolves the live node a name-targeted animation channel should drive,
/// given the node the channel's [target] bound to and the channel's
/// [targetName] bind fallback.
///
/// Mirrors the runtime resolver:
///
///     final channelTarget = nodeName == target.name
///         ? target
///         : target.getChildByName(nodeName);
///
/// A [targetName] equal to [live]'s own name is the node itself — the plain,
/// self-bound bone channels that `keyPose` / `setAnimationKeyframe(s)` author
/// (the key commands always store the bone node's own name as the binding
/// fallback). Any other [targetName] is a descendant lookup: a bone inside an
/// imported prefab instance, whose instance node carries a different name than
/// the bone it targets.
///
/// Returns [live] unchanged for a null [targetName] (document-id-bound
/// channels, which need no name resolution), and null when [targetName] is
/// non-null but matches neither [live] nor any descendant.
Node? resolveChannelTarget(Node live, String? targetName) {
  if (targetName == null) return live;
  return live.name == targetName ? live : live.getChildByName(targetName);
}
