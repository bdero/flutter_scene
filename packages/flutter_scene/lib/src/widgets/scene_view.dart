import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/scene.dart';

/// Builds a [Camera] for the current frame from the [elapsed] time since the
/// view started ticking. Use this for time-based cameras (for example an
/// orbiting view); pass a fixed [SceneView.camera] instead when the camera does
/// not change over time.
typedef SceneCameraBuilder = Camera Function(Duration elapsed);

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
  /// Exactly one of [camera] or [cameraBuilder] must be provided.
  const SceneView(
    this.scene, {
    super.key,
    this.camera,
    this.cameraBuilder,
    this.autoTick = true,
    this.pixelRatio,
    this.onTick,
  }) : assert(
         (camera == null) != (cameraBuilder == null),
         'Provide exactly one of camera or cameraBuilder.',
       );

  /// The scene to render. Owned and mutated by the application.
  final Scene scene;

  /// A fixed camera. Mutually exclusive with [cameraBuilder].
  final Camera? camera;

  /// Builds the camera each frame from the elapsed time. Mutually exclusive
  /// with [camera].
  final SceneCameraBuilder? cameraBuilder;

  /// Whether to drive a repaint every frame with an internal [Ticker].
  ///
  /// Leave `true` (the default) for animated content. Set `false` for a static
  /// scene that only needs to repaint when the app rebuilds the view (for
  /// example with a new [camera]).
  final bool autoTick;

  /// Logical-to-physical pixel multiplier for the offscreen render target,
  /// forwarded to [Scene.render]. Defaults to the view's device pixel ratio.
  final double? pixelRatio;

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

  Camera _cameraForFrame() =>
      widget.camera ?? widget.cameraBuilder!(_elapsed.value);

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
      child: CustomPaint(
        // Size.infinite fills the largest bounded constraints the view is
        // given (both tight constraints and a Stack's loose ones), so the
        // scene is never collapsed to zero size. See the class doc: place
        // SceneView where it receives bounded constraints.
        size: Size.infinite,
        painter: _ScenePainter(
          scene: widget.scene,
          cameraForFrame: _cameraForFrame,
          pixelRatio: widget.pixelRatio,
          repaint: _repaint,
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.cameraForFrame,
    required this.pixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Scene scene;
  final Camera Function() cameraForFrame;
  final double? pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    scene.render(
      cameraForFrame(),
      canvas,
      viewport: Offset.zero & size,
      pixelRatio: pixelRatio,
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      scene != oldDelegate.scene ||
      cameraForFrame != oldDelegate.cameraForFrame ||
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
