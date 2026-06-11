import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/render_view.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/scene_pointer.dart';
import 'package:flutter_scene/src/widget_texture.dart';

/// Builds a [Camera] for the current frame from the [elapsed] time since the
/// view started ticking. Use this for time-based cameras (for example an
/// orbiting view); pass a fixed [SceneView.camera] instead when the camera does
/// not change over time.
typedef SceneCameraBuilder = Camera Function(Duration elapsed);

/// Builds the list of [RenderView]s to render for the current frame from the
/// [elapsed] time since the view started ticking. Use this for multi-view
/// rendering (split-screen, picture-in-picture); pass a single
/// [SceneView.camera] or [SceneView.cameraBuilder] for one view.
typedef SceneViewsBuilder = List<RenderView> Function(Duration elapsed);

/// Called once per frame with the total [elapsed] time and the [deltaSeconds]
/// since the previous tick. Drive per-frame app logic here, or advance the
/// scene with a supplied timestep via [Scene.update] (after which [Scene.render]
/// skips its implicit wall-clock tick for that frame).
typedef SceneTickCallback =
    void Function(Duration elapsed, double deltaSeconds);

/// A widget that renders a [Scene] and drives its per-frame repaint.
///
/// This is the supported way to display a scene: it owns the frame ticker and
/// the [CustomPaint] that calls [Scene.render], so applications do not write
/// their own `CustomPainter`. The [scene] is app-owned and mutated imperatively
/// over time (attach and detach [Node]s, swap materials); [SceneView] is a view
/// onto it, not the owner of its contents.
///
/// Provide the camera either as a fixed [camera] or, for a camera that changes
/// over time, a [cameraBuilder] that receives the elapsed time each frame.
///
/// ```dart
/// SceneView(
///   scene,
///   cameraBuilder: (elapsed) {
///     final t = elapsed.inMicroseconds / 1e6;
///     return PerspectiveCamera(
///       position: Vector3(sin(t) * 5, 2, cos(t) * 5),
///       target: Vector3.zero(),
///     );
///   },
/// )
/// ```
///
/// Place [SceneView] where it receives bounded constraints (for example inside
/// a [SizedBox.expand] or an [Expanded]); it fills the space it is given.
///
/// The active [scene] is exposed to descendants through [SceneScope], so widgets
/// below can resolve the scene from their [BuildContext].
//
// TODO(declarative): a future declarative API will add a `SceneView.builder`
// (or `child:`) form where SceneView owns an internal Scene that declarative
// node widgets populate via SceneScope. The Scene stays the substrate either
// way; reserve that constructor shape rather than reworking this one.
class SceneView extends StatefulWidget {
  /// Renders [scene], driving a repaint each frame.
  ///
  /// Exactly one of [camera], [cameraBuilder], or [viewsBuilder] must be
  /// provided.
  const SceneView(
    this.scene, {
    super.key,
    this.camera,
    this.cameraBuilder,
    this.viewsBuilder,
    this.autoTick = true,
    this.pixelRatio,
    this.onTick,
    this.debugWidgetInput = false,
  }) : assert(
         (camera != null ? 1 : 0) +
                 (cameraBuilder != null ? 1 : 0) +
                 (viewsBuilder != null ? 1 : 0) ==
             1,
         'Provide exactly one of camera, cameraBuilder, or viewsBuilder.',
       );

  /// The scene to render. Owned and mutated by the application.
  final Scene scene;

  /// A fixed camera. Mutually exclusive with [cameraBuilder] and
  /// [viewsBuilder].
  final Camera? camera;

  /// Builds the camera each frame from the elapsed time. Mutually exclusive
  /// with [camera] and [viewsBuilder].
  final SceneCameraBuilder? cameraBuilder;

  /// Builds the list of views to render each frame (split-screen,
  /// picture-in-picture). Mutually exclusive with [camera] and
  /// [cameraBuilder].
  final SceneViewsBuilder? viewsBuilder;

  /// Whether to drive a repaint every frame with an internal [Ticker].
  ///
  /// Leave `true` (the default) for animated content. Set `false` for a static
  /// scene that only needs to repaint when the app rebuilds the view (for
  /// example with a new [camera]).
  final bool autoTick;

  /// Logical-to-physical pixel multiplier for the offscreen render target,
  /// forwarded to [Scene.render]. Defaults to the view's device pixel ratio.
  final double? pixelRatio;

  /// Debug-only: overlays the automatic widget-input pointer's state (hit
  /// node, UV, distance, and a marker at the pointer position), the first
  /// tool to reach for when a widget surface does not respond to input.
  final bool debugWidgetInput;

  /// Called once per frame while ticking. See [SceneTickCallback].
  final SceneTickCallback? onTick;

  @override
  State<SceneView> createState() => _SceneViewState();
}

/// A [Listenable] that repaints the scene; its [notify] is called each frame so
/// only the painting layer repaints (not the whole widget subtree).
class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _SceneViewState extends State<SceneView>
    with SingleTickerProviderStateMixin {
  final _Repaint _repaint = _Repaint();
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.autoTick) {
      _ticker = createTicker(_onTick)..start();
    }
  }

  @override
  void didUpdateWidget(SceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoTick != oldWidget.autoTick) {
      _ticker?.dispose();
      _ticker = widget.autoTick ? (createTicker(_onTick)..start()) : null;
    }
    // Repaint immediately so a changed camera / scene is reflected even when
    // not auto-ticking.
    _repaint.notify();
  }

  void _onTick(Duration elapsed) {
    final deltaSeconds = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _elapsed.value = elapsed;
    widget.onTick?.call(elapsed, deltaSeconds);
    _repaint.notify();
  }

  Camera? _lastBuiltCamera;

  Camera _cameraForFrame() =>
      _lastBuiltCamera = widget.camera ?? widget.cameraBuilder!(_elapsed.value);

  List<RenderView> _viewsForFrame() => widget.viewsBuilder!(_elapsed.value);

  // ----- automatic widget input -----

  ScenePointer? _autoPointer;
  int? _activePlatformPointer;
  Size _viewSize = Size.zero;
  Offset? _debugPosition;

  ScenePointer get _pointer => _autoPointer ??= ScenePointer(widget.scene);

  bool get _autoInputAvailable =>
      widget.viewsBuilder == null &&
      widget.scene.renderScene.widgetComponents.isNotEmpty;

  void _autoPoint(Offset position) {
    final camera = _lastBuiltCamera;
    if (camera == null || _viewSize.isEmpty) return;
    _pointer.pointAt(position, camera: camera, viewSize: _viewSize);
    if (widget.debugWidgetInput) {
      setState(() => _debugPosition = position);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_autoInputAvailable || _activePlatformPointer != null) return;
    _autoPoint(event.localPosition);
    final hovered = _pointer.hoveredWidget;
    if (hovered != null && hovered.input == WidgetInput.automatic) {
      _activePlatformPointer = event.pointer;
      _pointer.press();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePlatformPointer) return;
    _autoPoint(event.localPosition);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePlatformPointer) return;
    _activePlatformPointer = null;
    _autoPoint(event.localPosition);
    _pointer.release();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePlatformPointer) return;
    _activePlatformPointer = null;
    _pointer.cancel();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_autoInputAvailable || event is! PointerScrollEvent) return;
    _autoPoint(event.localPosition);
    final hovered = _pointer.hoveredWidget;
    if (hovered != null && hovered.input == WidgetInput.automatic) {
      _pointer.scroll(event.scrollDelta);
    }
  }

  // Trackpads report scrolling as pan-zoom gestures (not scroll signals);
  // forward the pan as scroll deltas so trackpad scrolling drives widget
  // surfaces too.
  Offset _panZoomLastPan = Offset.zero;

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!_autoInputAvailable) return;
    _panZoomLastPan = Offset.zero;
    _autoPoint(event.localPosition);
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_autoInputAvailable) return;
    _autoPoint(event.localPosition);
    final hovered = _pointer.hoveredWidget;
    final delta = event.pan - _panZoomLastPan;
    _panZoomLastPan = event.pan;
    if (hovered != null && hovered.input == WidgetInput.automatic) {
      _pointer.scroll(-delta);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Debug-only hot reload: refresh changed .fmat materials in place, then
    // repaint so the change shows without restarting or app-side wiring.
    HotReloadCoordinator.instance.onReassemble();
    _repaint.notify();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _repaint.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SceneScope(
      scene: widget.scene,
      elapsed: _elapsed,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewSize = constraints.biggest;
          return Listener(
            // Translucent: forwarded events still reach the app's own
            // gesture handlers; the scene never wins a gesture arena.
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: _onPointerPanZoomStart,
            onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                CustomPaint(
                  // Size.infinite fills the largest bounded constraints the view is
                  // given (both tight constraints and a Stack's loose ones), so the
                  // scene is never collapsed to zero size. See the class doc: place
                  // SceneView where it receives bounded constraints.
                  size: Size.infinite,
                  painter: _ScenePainter(
                    scene: widget.scene,
                    cameraForFrame: widget.viewsBuilder == null
                        ? _cameraForFrame
                        : null,
                    viewsForFrame: widget.viewsBuilder == null
                        ? null
                        : _viewsForFrame,
                    pixelRatio: widget.pixelRatio,
                    repaint: _repaint,
                  ),
                ),
                if (widget.debugWidgetInput) _buildDebugOverlay(),
                // Invisible hosts for the scene's WidgetComponents: each hosted
                // subtree stays fully live (state, tickers, animations) while
                // occupying no layout space and never painting to the screen; its
                // visual output streams into the component's texture. The Overlay
                // keeps dialogs, dropdowns, and tooltips inside the capture.
                ValueListenableBuilder<int>(
                  valueListenable:
                      widget.scene.renderScene.widgetComponentsChanged,
                  builder: (context, _, _) => Stack(
                    children: [
                      for (final component
                          in widget.scene.renderScene.widgetComponents
                              .whereType<WidgetComponent>())
                        WidgetTexture(
                          key: ObjectKey(component),
                          controller: component.controller,
                          width: component.size.width,
                          height: component.size.height,
                          pixelRatio: component.pixelRatio,
                          update: component.updatePolicy,
                          child: _WidgetComponentHost(component: component),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDebugOverlay() {
    final hit = _autoPointer?.hit;
    final position = _debugPosition;
    final hovered = _autoPointer?.hoveredWidget;
    final label = hit == null
        ? 'no hit'
        : '${hit.node.name.isEmpty ? '(unnamed)' : hit.node.name}  '
              'd=${hit.distance.toStringAsFixed(2)}  '
              'uv=${hit.uv == null ? 'none' : '(${hit.uv!.x.toStringAsFixed(3)}, ${hit.uv!.y.toStringAsFixed(3)})'}'
              '${hovered != null ? '  [widget]' : ''}';
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            if (position != null)
              Positioned(
                left: position.dx - 4,
                top: position.dy - 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hovered != null
                        ? const Color(0xFF40FF80)
                        : const Color(0xFFFF8040),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0xAA000000)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 11,
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.cameraForFrame,
    required this.viewsForFrame,
    required this.pixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Scene scene;
  final Camera Function()? cameraForFrame;
  final List<RenderView> Function()? viewsForFrame;
  final double? pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final views = viewsForFrame;
    if (views != null) {
      scene.renderViews(
        views(),
        canvas,
        region: Offset.zero & size,
        pixelRatio: pixelRatio,
      );
    } else {
      scene.render(
        cameraForFrame!(),
        canvas,
        viewport: Offset.zero & size,
        pixelRatio: pixelRatio,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      scene != oldDelegate.scene ||
      cameraForFrame != oldDelegate.cameraForFrame ||
      viewsForFrame != oldDelegate.viewsForFrame ||
      pixelRatio != oldDelegate.pixelRatio;
}

/// Exposes the active [Scene] (and the per-frame [elapsed] time) to descendants
/// of a [SceneView].
///
/// Resolve the scene from a descendant's [BuildContext] with [SceneScope.of].
/// Today [SceneView] is the only producer and there are no built-in consumers;
/// this plumbing exists so a future declarative node API can attach widgets to
/// the right scene subtree without restructuring the view.
class SceneScope extends InheritedWidget {
  const SceneScope({
    super.key,
    required this.scene,
    required this.elapsed,
    required super.child,
  });

  /// The scene being rendered by the enclosing [SceneView].
  final Scene scene;

  /// The total elapsed time since the enclosing [SceneView] started ticking.
  ///
  /// A [ValueListenable] (rather than a raw value) so descendants that care
  /// about per-frame time can listen without forcing every dependent to rebuild
  /// each frame.
  final ValueListenable<Duration> elapsed;

  /// The nearest [SceneScope], or null if there is none.
  static SceneScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SceneScope>();

  /// The [Scene] of the nearest enclosing [SceneView].
  ///
  /// Throws if there is no [SceneScope] ancestor.
  static Scene of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No SceneScope found in the widget tree.');
    return scope!.scene;
  }

  @override
  bool updateShouldNotify(SceneScope oldWidget) =>
      scene != oldWidget.scene || elapsed != oldWidget.elapsed;
}

/// Hosts one [WidgetComponent]'s subtree inside its own [Overlay], so routes
/// and overlay entries the subtree spawns (dialogs, dropdown menus,
/// tooltips) render inside the captured texture instead of escaping to the
/// app's root overlay.
class _WidgetComponentHost extends StatefulWidget {
  const _WidgetComponentHost({required this.component});

  final WidgetComponent component;

  @override
  State<_WidgetComponentHost> createState() => _WidgetComponentHostState();
}

class _WidgetComponentHostState extends State<_WidgetComponentHost> {
  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (context) => widget.component.child),
      ],
    );
  }
}
