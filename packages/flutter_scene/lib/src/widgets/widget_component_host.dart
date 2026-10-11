import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/widget_texture.dart';

/// Invisible hosts for every [WidgetComponent] registered on [renderScene].
///
/// Each hosted subtree stays fully live (state, tickers, animations) while
/// occupying no layout space and never painting to the screen; its visual
/// output streams into the component's texture. Rebuilds as components mount
/// and unmount. `SceneView` and `WidgetHost` both render this, so the two
/// cannot drift.
@internal
class WidgetComponentHosts extends StatelessWidget {
  const WidgetComponentHosts({super.key, required this.renderScene});

  final RenderScene renderScene;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: renderScene.widgetComponentsChanged,
      builder: (context, _, _) => Stack(
        children: [
          for (final component
              in renderScene.widgetComponents.whereType<WidgetComponent>())
            WidgetTexture(
              key: ObjectKey(component),
              controller: component.controller,
              width: component.size.width,
              height: component.size.height,
              pixelRatio: component.pixelRatio,
              update: component.updatePolicy,
              // ExcludeSemantics gates the subtree's semantics by the
              // coordinator's per-frame decision (see
              // WidgetTextureController.semanticsHidden); the subtree stays
              // structurally present either way.
              child: ValueListenableBuilder<bool>(
                valueListenable: component.controller.semanticsHidden,
                builder: (context, hidden, child) =>
                    ExcludeSemantics(excluding: hidden, child: child),
                child: WidgetComponentHost(component: component),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hosts one [WidgetComponent]'s subtree inside its own [Overlay], so routes
/// and overlay entries the subtree spawns (dialogs, dropdown menus,
/// tooltips) render inside the captured texture instead of escaping to the
/// app's root overlay.
@internal
class WidgetComponentHost extends StatefulWidget {
  const WidgetComponentHost({super.key, required this.component});

  final WidgetComponent component;

  @override
  State<WidgetComponentHost> createState() => _WidgetComponentHostState();
}

class _WidgetComponentHostState extends State<WidgetComponentHost> {
  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (context) => widget.component.child),
      ],
    );
  }
}
