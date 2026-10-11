import 'package:flutter/widgets.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/widgets/widget_component_host.dart';

/// Mounts the live widget subtrees behind a [Scene]'s `WidgetComponent`s for
/// a scene that is rendered without a `SceneView`.
///
/// A `WidgetComponent`'s texture only updates while its subtree is mounted
/// somewhere in the app's widget tree. `SceneView` mounts them itself, so a
/// scene drawn by a `SceneView` needs no [WidgetHost], and mounting both for
/// the same scene would run every subtree twice. Use this for a scene drawn
/// through [Scene.renderViews] or a render-to-target path by code that owns
/// its own frame loop (an XR session, a headless capture). Place it anywhere
/// in the tree, typically as a sibling of the app's UI inside a `Stack`.
///
/// The host takes no layout space and paints nothing; each hosted subtree
/// stays live (state, tickers, animations) and streams into its component's
/// texture. Pointer input reaches the subtrees through a `ScenePointer` or
/// the component's `controller`, since `WidgetInput.automatic` forwarding is
/// part of `SceneView`.
///
/// ```dart
/// Stack(
///   children: [
///     MyXrHud(),
///     WidgetHost(scene: scene),
///   ],
/// )
/// ```
/// {@category Widgets}
// TODO(widget-host): nothing positions the hosted subtrees' semantics without
// a SceneView, so they stay excluded from the semantics tree; give the host
// (or the XR view model) a way to push each surface's transform.
class WidgetHost extends StatelessWidget {
  /// Creates a host for [scene]'s widget components.
  const WidgetHost({super.key, required this.scene});

  /// The scene whose `WidgetComponent` subtrees this hosts.
  final Scene scene;

  @override
  Widget build(BuildContext context) {
    // shrink rather than expand: the hosted textures size themselves to
    // zero, so a zero box keeps the host from stretching a loose Stack or
    // failing under unbounded constraints (a Column, a scroll view).
    return SizedBox.shrink(
      child: WidgetComponentHosts(renderScene: scene.renderScene),
    );
  }
}
