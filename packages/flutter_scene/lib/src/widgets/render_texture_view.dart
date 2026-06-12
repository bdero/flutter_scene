import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/render_texture.dart';

/// Displays a live [RenderTexture] in the widget tree.
///
/// The widget repaints whenever the target re-renders (per its
/// `RenderTexture.update` policy) and shows nothing until the first render
/// completes. It fills the constraints it is given, scaling the texture
/// with [fit].
///
/// ```dart
/// final minimap = RenderTexture(width: 480, height: 270);
/// scene.views.add(RenderView(camera: topCamera, target: minimap));
/// // ... in the widget tree, typically stacked over the SceneView:
/// SizedBox(width: 240, height: 135, child: RenderTextureView(minimap))
/// ```
///
/// With [followLayout] enabled, the target is resized to match the
/// widget's layout size (times the device pixel ratio), so the capture is
/// always rendered at display resolution. Off by default, so a fixed-size
/// target is never silently reallocated by layout changes.
/// {@category Widgets}
class RenderTextureView extends StatefulWidget {
  /// Displays [renderTexture], repainting whenever it re-renders.
  const RenderTextureView(
    this.renderTexture, {
    super.key,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.followLayout = false,
  });

  /// The render target to display.
  final RenderTexture renderTexture;

  /// How the texture is inscribed into the widget's bounds.
  final BoxFit fit;

  /// The sampling quality the texture is drawn with.
  final FilterQuality filterQuality;

  /// Whether to resize [renderTexture] to the widget's layout size (times
  /// the device pixel ratio). See the class doc.
  final bool followLayout;

  @override
  State<RenderTextureView> createState() => _RenderTextureViewState();
}

class _RenderTextureViewState extends State<RenderTextureView> {
  @override
  void initState() {
    super.initState();
    widget.renderTexture.addListener(_onUpdated);
  }

  @override
  void didUpdateWidget(RenderTextureView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.renderTexture != oldWidget.renderTexture) {
      oldWidget.renderTexture.removeListener(_onUpdated);
      widget.renderTexture.addListener(_onUpdated);
    }
  }

  @override
  void dispose() {
    widget.renderTexture.removeListener(_onUpdated);
    super.dispose();
  }

  void _onUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  void _followLayout(BoxConstraints constraints, double dpr) {
    final width = (constraints.biggest.width * dpr).ceil();
    final height = (constraints.biggest.height * dpr).ceil();
    if (width > 0 && height > 0) {
      // Resizing only reallocates the texture ring (no relayout), so doing
      // it during build is safe; the next scene render picks it up.
      widget.renderTexture.resize(width, height);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.followLayout && constraints.biggest.isFinite) {
          _followLayout(constraints, MediaQuery.devicePixelRatioOf(context));
        }
        final texture = widget.renderTexture.texture;
        return SizedBox.expand(
          child: texture == null
              ? null
              : RawImage(
                  image: texture.asImage(),
                  fit: widget.fit,
                  filterQuality: widget.filterQuality,
                ),
        );
      },
    );
  }
}
