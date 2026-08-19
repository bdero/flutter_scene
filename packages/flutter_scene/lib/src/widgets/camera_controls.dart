import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/camera_controllers/camera_controller.dart';

/// Feeds pointer, scroll, and keyboard input to a [CameraController].
///
/// Wrap the widget showing the scene (typically a `SceneView`). Drag rotates
/// or looks, a two-finger gesture pinches to dolly and moves to pan, the scroll
/// wheel dollies, and while focused the keyboard drives movement. The
/// controller must be attached to a scene node (with a `CameraComponent`) so it
/// can drive that node; this widget only forwards input to it.
///
/// This is one input adapter, not the only way to drive a controller: the
/// controller's own intent methods (`orbitBy`, `dollyBy`, `look`, ...) can be
/// called from any source, so an application with its own input handling can
/// skip this widget.
/// {@category Widgets}
class CameraControls extends StatefulWidget {
  /// Wraps [child], routing its input to [controller].
  const CameraControls({
    super.key,
    required this.controller,
    this.enabled = true,
    this.autofocus = true,
    required this.child,
  });

  /// The controller to drive. Attach the same instance to a scene node.
  final CameraController controller;

  /// Whether input is forwarded. When false the child still shows but input is
  /// ignored (and held keys are released).
  final bool enabled;

  /// Whether to take keyboard focus on mount so keys work without a click.
  final bool autofocus;

  /// The widget showing the scene.
  final Widget child;

  @override
  State<CameraControls> createState() => _CameraControlsState();
}

class _CameraControlsState extends State<CameraControls> {
  double _lastScale = 1.0;

  CameraController get _controller => widget.controller;

  void _onScaleStart(ScaleStartDetails details) => _lastScale = 1.0;

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!widget.enabled) return;
    if (details.pointerCount <= 1) {
      _controller.handleDragUpdate(details.focalPointDelta);
      return;
    }
    final scaleFactor = _lastScale == 0.0 ? 1.0 : details.scale / _lastScale;
    _lastScale = details.scale;
    _controller.handleScaleUpdate(scaleFactor, details.focalPointDelta);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.enabled || event is! PointerScrollEvent) return;
    _controller.handleScroll(event.scrollDelta.dy);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    return _controller.handleKeyEvent(event)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _onFocusChange(bool hasFocus) {
    if (!hasFocus) _controller.releaseInput();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      onFocusChange: _onFocusChange,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _onPointerSignal,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.biggest.isFinite) {
              _controller.viewportSize = constraints.biggest;
            }
            return RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: <Type, GestureRecognizerFactory>{
                ScaleGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      ScaleGestureRecognizer
                    >(
                      () => ScaleGestureRecognizer(),
                      (recognizer) => recognizer
                        ..onStart = _onScaleStart
                        ..onUpdate = _onScaleUpdate,
                    ),
              },
              // TODO(camera): right-button drag pan (handleSecondaryDragUpdate)
              // once it can coexist with the scale recognizer without an arena
              // conflict.
              child: widget.child,
            );
          },
        ),
      ),
    );
  }
}
