import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart'
    show PipelineOwner, RenderCustomPaint, SemanticsBuilderCallback;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/widgets.dart';

import 'package:flutter_scene/src/camera.dart';
import 'package:flutter_scene/src/hot_reload/hot_reload_coordinator.dart';
import 'package:flutter_scene/src/material/environment.dart';
import 'package:flutter_scene/src/tone_mapping.dart';
import 'package:flutter_scene/src/widgets/declarative.dart';
import 'package:flutter_scene/src/render_view.dart';
import 'package:flutter_scene/src/components/widget_component.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_scene/src/resource_group.dart';
import 'package:flutter_scene/src/scene.dart';
import 'package:flutter_scene/src/scene_pointer.dart';
import 'package:flutter_scene/src/widgets/scene_view_semantics.dart';
import 'package:flutter_scene/src/widget_texture.dart';

/// Builds a [Camera] for the current frame from the [elapsed] time since the
/// view started ticking. Use this for time-based cameras (for example an
/// orbiting view); pass a fixed [SceneView.camera] instead when the camera does
/// not change over time.
/// {@category Widgets}
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
/// {@category Widgets}
typedef SceneTickCallback =
    void Function(Duration elapsed, double deltaSeconds);

/// Builds the widget shown while a [SceneView] waits for its resources to load,
/// given the current load [progress] (0 to 1). See [SceneView.loadingBuilder].
/// {@category Widgets}
typedef SceneLoadingBuilder =
    Widget Function(BuildContext context, double progress);

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
///
/// For a fully declarative scene, use [SceneView.declarative]: the view owns
/// an internal [Scene] and declarative scene widgets ([SceneNode],
/// [SceneMesh], [SceneModel]) describe its contents in [children]. Both
/// constructors accept [children], so declarative subtrees also compose over
/// an app-owned scene.
/// {@category Widgets}
class SceneView extends StatefulWidget {
  /// Renders [scene], driving a repaint each frame.
  ///
  /// At most one of [camera], [cameraBuilder], or [viewsBuilder] may be
  /// provided. When none is, the view renders through the scene's primary
  /// camera (`Scene.camera`), falling back to a default camera when the scene
  /// has none, so `SceneView(scene)` always renders something.
  const SceneView(
    Scene this.scene, {
    super.key,
    this.camera,
    this.cameraBuilder,
    this.viewsBuilder,
    this.autoTick = true,
    this.pixelRatio,
    this.onTick,
    this.loading,
    this.loadingBuilder,
    this.revealMinDuration = Duration.zero,
    this.warmUp = false,
    this.debugWidgetInput = false,
    this.children = const [],
  }) : environment = null,
       environmentIntensity = 1.0,
       exposure = 1.0,
       toneMapping = null,
       assert(
         (camera != null ? 1 : 0) +
                 (cameraBuilder != null ? 1 : 0) +
                 (viewsBuilder != null ? 1 : 0) <=
             1,
         'Provide at most one of camera, cameraBuilder, or viewsBuilder.',
       );

  /// Renders a view-owned [Scene] described declaratively by [children].
  ///
  /// The view constructs and owns an internal [Scene]; scene widgets in
  /// [children] populate it, and the scene-level props ([environment],
  /// [exposure], [toneMapping], ...) configure it. Omitted props mean the
  /// scene defaults; removing a prop on a later build restores its default.
  ///
  /// ```dart
  /// SceneView.declarative(
  ///   children: [
  ///     SceneMesh(geometry: geometry, material: material),
  ///   ],
  /// )
  /// ```
  const SceneView.declarative({
    super.key,
    this.environment,
    this.environmentIntensity = 1.0,
    this.exposure = 1.0,
    ToneMappingMode this.toneMapping = ToneMappingMode.pbrNeutral,
    this.camera,
    this.cameraBuilder,
    this.viewsBuilder,
    this.autoTick = true,
    this.pixelRatio,
    this.onTick,
    this.loading,
    this.loadingBuilder,
    this.revealMinDuration = Duration.zero,
    this.warmUp = false,
    this.debugWidgetInput = false,
    this.children = const [],
  }) : scene = null,
       assert(
         (camera != null ? 1 : 0) +
                 (cameraBuilder != null ? 1 : 0) +
                 (viewsBuilder != null ? 1 : 0) <=
             1,
         'Provide at most one of camera, cameraBuilder, or viewsBuilder.',
       );

  /// The scene to render, owned and mutated by the application. Null when
  /// the view owns its scene ([SceneView.declarative]).
  final Scene? scene;

  /// Declarative scene widgets mounted at the scene root (via [SceneScope]).
  ///
  /// With [SceneView.declarative] this is the whole scene description; with
  /// an app-owned [scene] it composes declarative subtrees over the
  /// imperative graph. The widgets stay mounted (and keep loading) while the
  /// view is gated behind [loading] or [warmUp].
  final List<Widget> children;

  /// The owned scene's environment map ([SceneView.declarative] only).
  /// Identity-diffed; null means the scene's default studio environment.
  final EnvironmentMap? environment;

  /// The owned scene's environment intensity ([SceneView.declarative] only).
  final double environmentIntensity;

  /// The owned scene's exposure ([SceneView.declarative] only).
  final double exposure;

  /// The owned scene's tone mapping ([SceneView.declarative] only). Null on
  /// the app-owned-scene constructor, which never writes scene properties.
  final ToneMappingMode? toneMapping;

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
  ///
  /// When the view is gated by [loading] or [loadingBuilder], it is not called
  /// while the loading widget is shown (per-frame app logic stays paused until
  /// the scene is revealed), and its first call after reveal carries a
  /// single-frame delta rather than the whole loading time.
  final SceneTickCallback? onTick;

  /// Resources this view waits for before it reveals the scene.
  ///
  /// While the group is loading (and while the engine's shared static
  /// resources are still initializing), the scene is held off-screen and
  /// [loadingBuilder] is shown in its place, so a half-built scene is never
  /// drawn. Once the group and static resources are ready, the fully assembled
  /// scene is revealed in one frame. Leave null to render as soon as static
  /// resources are ready (the historical behavior).
  final ResourceGroup? loading;

  /// Builds the widget shown while the view waits to reveal the scene.
  ///
  /// Called with the current load [progress] (the [loading] group's progress,
  /// or 0 until static resources are ready when there is no group). When null,
  /// the space is left blank until the scene is revealed.
  final SceneLoadingBuilder? loadingBuilder;

  /// The minimum time the loading widget stays up once shown, so a fast load
  /// does not flash it for a single frame. Defaults to [Duration.zero].
  final Duration revealMinDuration;

  /// Whether to compile the scene's render pipelines before revealing it, so
  /// the first visible frame does not stall while shaders compile.
  ///
  /// When true, the view calls [Scene.warmUp] with its own views once the
  /// [loading] group (if any) is ready, and reveals only after. This gates the
  /// view even without a [loading] group or [loadingBuilder]. Populate the
  /// scene before warm-up runs (loads tracked by [loading] are awaited first).
  final bool warmUp;

  /// Resolves the camera for a single-view frame.
  ///
  /// Precedence: the explicit [camera], then [cameraBuilder] evaluated at
  /// [elapsed], then [sceneCamera] (the scene's primary), then a default
  /// camera so a scene with no camera still renders. Pure given its inputs.
  @visibleForTesting
  static Camera resolveCamera(
    Duration elapsed, {
    Camera? camera,
    SceneCameraBuilder? cameraBuilder,
    Camera? sceneCamera,
  }) => camera ?? cameraBuilder?.call(elapsed) ?? sceneCamera ?? _defaultCamera;

  @override
  State<SceneView> createState() => _SceneViewState();
}

// Used when a scene has no camera set up at all, so a bare SceneView(scene)
// still renders. The PerspectiveCamera default sits on -Z looking toward the
// origin, which frames the front of imported glTF content (whose front faces
// -Z after the scene-root flip) and centers content placed near the origin.
final Camera _defaultCamera = PerspectiveCamera();

/// A [Listenable] that repaints the scene; its [notify] is called each frame so
/// only the painting layer repaints (not the whole widget subtree).
class _Repaint extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _SceneViewState extends State<SceneView>
    with SingleTickerProviderStateMixin {
  // The internal scene for SceneView.declarative, created once per state.
  // The default environment is captured so clearing the environment prop
  // restores it (the declarative contract: omitted prop means default).
  Scene? _ownedScene;
  EnvironmentMap? _ownedDefaultEnvironment;

  Scene get _scene => widget.scene ?? _ownedScene!;

  final _Repaint _repaint = _Repaint();
  final ValueNotifier<Duration> _elapsed = ValueNotifier<Duration>(
    Duration.zero,
  );
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  // Zero-based clock: the ticker's raw elapsed at the moment the scene is
  // revealed, subtracted from later ticks so the visible scene starts its time
  // (and its first frame delta) from zero rather than from app launch.
  Duration _tickOrigin = Duration.zero;

  // Whether the scene is being drawn yet. While gated (see `_gated`) it stays
  // false until static resources and the `loading` group are ready, and the
  // loading widget shows instead. Ungated views reveal immediately, so this is
  // true from the first frame and behavior matches a view with no loading args.
  bool _revealed = false;
  // Bumps on each reveal watch so a stale async wait (after the loading group
  // is swapped) cannot reveal the wrong generation.
  int _revealGeneration = 0;

  // A view gates rendering only when it opts in with a `loading` group, a
  // `loadingBuilder`, or `warmUp`; otherwise it renders as soon as it can,
  // unchanged.
  bool get _gated =>
      widget.loading != null || widget.loadingBuilder != null || widget.warmUp;

  // Builds the semantics elements for the scene's SemanticsComponents and
  // widget surfaces; refreshed by the painter after each rendered frame.
  late SceneSemanticsCoordinator _sceneSemantics;

  @override
  void initState() {
    super.initState();
    if (widget.scene == null) {
      _ownedScene = Scene();
      _ownedDefaultEnvironment = _ownedScene!.environment;
      _applySceneProps(null);
    }
    _sceneSemantics = SceneSemanticsCoordinator(_scene);
    SemanticsBinding.instance.addSemanticsEnabledListener(_onSemanticsChanged);
    _scene.renderScene.semanticsComponentsChanged.addListener(
      _onSemanticsChanged,
    );
    if (widget.autoTick) {
      _ticker = createTicker(_onTick)..start();
    }
    _revealed = !_gated;
    if (_gated) {
      _startRevealWatch();
    }
  }

  // Applies the declarative constructor's scene-level props to the owned
  // scene, writing only what changed. Pass null to apply everything (initial
  // apply, or right after the owned scene is created).
  void _applySceneProps(SceneView? oldWidget) {
    final scene = _ownedScene!;
    if (oldWidget == null ||
        !identical(widget.environment, oldWidget.environment)) {
      scene.environment = widget.environment ?? _ownedDefaultEnvironment;
    }
    if (oldWidget == null ||
        widget.environmentIntensity != oldWidget.environmentIntensity) {
      scene.environmentIntensity = widget.environmentIntensity;
    }
    if (oldWidget == null || widget.exposure != oldWidget.exposure) {
      scene.exposure = widget.exposure;
    }
    final toneMapping = widget.toneMapping;
    if (toneMapping != null &&
        (oldWidget == null || toneMapping != oldWidget.toneMapping)) {
      scene.toneMapping = toneMapping;
    }
  }

  // Repaints so the next frame's semantics refresh sees the change (a
  // screen reader toggling on/off, or semantics components mounting and
  // unmounting), even when the view is not ticking.
  void _onSemanticsChanged() => _repaint.notify();

  @override
  void didUpdateWidget(SceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoTick != oldWidget.autoTick) {
      _ticker?.dispose();
      _ticker = widget.autoTick ? (createTicker(_onTick)..start()) : null;
    }
    final oldScene = oldWidget.scene ?? _ownedScene;
    if (widget.scene == null && _ownedScene == null) {
      // Switched from an app-owned scene to the declarative form.
      _ownedScene = Scene();
      _ownedDefaultEnvironment = _ownedScene!.environment;
    }
    if (widget.scene == null) {
      _applySceneProps(oldWidget.scene == null ? oldWidget : null);
    }
    if (!identical(_scene, oldScene)) {
      oldScene?.renderScene.semanticsComponentsChanged.removeListener(
        _onSemanticsChanged,
      );
      _scene.renderScene.semanticsComponentsChanged.addListener(
        _onSemanticsChanged,
      );
      _sceneSemantics = SceneSemanticsCoordinator(_scene);
      _autoPointer = null;
    }
    // A new set of resources to wait for (or newly gated): hold the scene again
    // until they load.
    final gatedBefore =
        oldWidget.loading != null ||
        oldWidget.loadingBuilder != null ||
        oldWidget.warmUp;
    if (widget.loading != oldWidget.loading || _gated != gatedBefore) {
      _revealed = !_gated;
      if (_gated) {
        _startRevealWatch();
      }
    }
    // Repaint immediately so a changed camera / scene is reflected even when
    // not auto-ticking.
    _repaint.notify();
  }

  // Waits for the engine's shared static resources and the `loading` group,
  // then reveals the scene (after `revealMinDuration`), so a half-built scene
  // is never drawn.
  Future<void> _startRevealWatch() async {
    final generation = ++_revealGeneration;
    final start = DateTime.now();
    await Scene.initializeStaticResources();
    if (!mounted || generation != _revealGeneration) return;
    await widget.loading?.ready;
    if (!mounted || generation != _revealGeneration) return;
    // Compile the pipelines the first frame needs while the loading widget is
    // still up, so the reveal frame does not stall.
    if (widget.warmUp) {
      await _scene.warmUp(_warmUpViews());
      if (!mounted || generation != _revealGeneration) return;
    }
    final remaining =
        widget.revealMinDuration - DateTime.now().difference(start);
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted || generation != _revealGeneration) return;
    setState(() => _revealed = true);
  }

  // The views to warm up, matching what the first rendered frame will use.
  List<RenderView> _warmUpViews() => widget.viewsBuilder != null
      ? _viewsForFrame()
      : [RenderView(camera: _cameraForFrame())];

  void _onTick(Duration elapsed) {
    if (!_revealed) {
      // Hold the origin at the latest tick so the first revealed frame's delta
      // is a single frame, not the whole time spent on the loading screen.
      _tickOrigin = elapsed;
      _lastTick = Duration.zero;
      return;
    }
    final revealElapsed = elapsed - _tickOrigin;
    final deltaSeconds = (revealElapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = revealElapsed;
    _elapsed.value = revealElapsed;
    widget.onTick?.call(revealElapsed, deltaSeconds);
    _repaint.notify();
  }

  Camera? _lastBuiltCamera;

  Camera _cameraForFrame() => _lastBuiltCamera = SceneView.resolveCamera(
    _elapsed.value,
    camera: widget.camera,
    cameraBuilder: widget.cameraBuilder,
    sceneCamera: _scene.camera,
  );

  List<RenderView> _viewsForFrame() => widget.viewsBuilder!(_elapsed.value);

  // ----- automatic widget input -----

  ScenePointer? _autoPointer;
  int? _activePlatformPointer;
  Size _viewSize = Size.zero;
  Offset? _debugPosition;

  ScenePointer get _pointer => _autoPointer ??= ScenePointer(_scene);

  bool get _autoInputAvailable =>
      widget.viewsBuilder == null &&
      _scene.renderScene.widgetComponents.isNotEmpty;

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
    SemanticsBinding.instance.removeSemanticsEnabledListener(
      _onSemanticsChanged,
    );
    _scene.renderScene.semanticsComponentsChanged.removeListener(
      _onSemanticsChanged,
    );
    _ticker?.dispose();
    _repaint.dispose();
    _elapsed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _sceneSemantics.ambientTextDirection = Directionality.maybeOf(context);
    Widget view = LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        return _buildView(context);
      },
    );
    if (widget.children.isNotEmpty) {
      // The declarative children mount outside the reveal gate so their
      // content populates (and loads) while a loading widget is up. The host
      // occupies no space and paints nothing.
      view = Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: [
          view,
          SceneSubtree(children: widget.children),
        ],
      );
    }
    return SceneScope(scene: _scene, elapsed: _elapsed, child: view);
  }

  Widget _buildView(BuildContext context) {
    if (!_revealed) {
      return _buildLoading(context);
    }
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
          _SceneCustomPaint(
            semantics: _sceneSemantics,
            painter: _ScenePainter(
              scene: _scene,
              cameraForFrame: widget.viewsBuilder == null
                  ? _cameraForFrame
                  : null,
              viewsForFrame: widget.viewsBuilder == null
                  ? null
                  : _viewsForFrame,
              pixelRatio: widget.pixelRatio,
              semantics: _sceneSemantics,
              repaint: _repaint,
            ),
            // Invisible hosts for the scene's WidgetComponents: each hosted
            // subtree stays fully live (state, tickers, animations) while
            // occupying no layout space and never painting to the screen; its
            // visual output streams into the component's texture. The Overlay
            // keeps dialogs, dropdowns, and tooltips inside the capture.
            // Riding as the paint widget's child puts each subtree's
            // semantics under the scene's semantics boundary, beside the
            // nodes synthesized for SemanticsComponents.
            child: SizedBox.expand(
              child: ValueListenableBuilder<int>(
                valueListenable: _scene.renderScene.widgetComponentsChanged,
                builder: (context, _, _) => Stack(
                  children: [
                    for (final component
                        in _scene.renderScene.widgetComponents
                            .whereType<WidgetComponent>())
                      WidgetTexture(
                        key: ObjectKey(component),
                        controller: component.controller,
                        width: component.size.width,
                        height: component.size.height,
                        pixelRatio: component.pixelRatio,
                        update: component.updatePolicy,
                        // ExcludeSemantics gates the subtree's semantics
                        // by the coordinator's per-frame decision (see
                        // WidgetTextureController.semanticsHidden); the
                        // subtree stays structurally present either way.
                        child: ValueListenableBuilder<bool>(
                          valueListenable: component.controller.semanticsHidden,
                          builder: (context, hidden, child) =>
                              ExcludeSemantics(excluding: hidden, child: child),
                          child: _WidgetComponentHost(component: component),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.debugWidgetInput) _buildDebugOverlay(),
        ],
      ),
    );
  }

  // The placeholder shown before the scene is revealed. Rebuilds as the
  // loading group's progress advances so a progress bar can animate.
  Widget _buildLoading(BuildContext context) {
    final builder = widget.loadingBuilder;
    if (builder == null) {
      return const SizedBox.expand();
    }
    final progress = widget.loading?.progress;
    if (progress == null) {
      // No group to measure: progress reads 0 until static resources flip the
      // view to revealed.
      return builder(context, 0.0);
    }
    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) => builder(context, value),
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
    required this.semantics,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Scene scene;
  final Camera Function()? cameraForFrame;
  final List<RenderView> Function()? viewsForFrame;
  final double? pixelRatio;
  final SceneSemanticsCoordinator semantics;

  @override
  void paint(Canvas canvas, Size size) {
    // Semantics refresh in a finally so assistive technology stays current
    // even on frames the engine skips or fails.
    final views = viewsForFrame;
    if (views != null) {
      final list = views();
      try {
        scene.renderViews(
          list,
          canvas,
          region: Offset.zero & size,
          pixelRatio: pixelRatio,
        );
      } finally {
        // Semantics follow the primary view: the first one rendering to the
        // screen. Views with an offscreen target contribute nothing.
        Camera? primary;
        var area = Offset.zero & size;
        for (final view in list) {
          if (view.target == null) {
            primary = view.camera;
            area = _viewArea(size, view.viewport);
            break;
          }
        }
        semantics.refreshAfterRender(primary, area);
      }
    } else {
      final camera = cameraForFrame!();
      try {
        scene.render(
          camera,
          canvas,
          viewport: Offset.zero & size,
          pixelRatio: pixelRatio,
        );
      } finally {
        semantics.refreshAfterRender(camera, Offset.zero & size);
      }
    }
  }

  // Maps a view's normalized viewport rectangle (0..1) into the scene box,
  // matching how Scene.renderViews subdivides its region.
  static Rect _viewArea(Size size, Rect? viewport) {
    if (viewport == null) return Offset.zero & size;
    return Rect.fromLTWH(
      viewport.left * size.width,
      viewport.top * size.height,
      viewport.width * size.width,
      viewport.height * size.height,
    );
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder => semantics.buildSemantics;

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      scene != oldDelegate.scene ||
      cameraForFrame != oldDelegate.cameraForFrame ||
      viewsForFrame != oldDelegate.viewsForFrame ||
      pixelRatio != oldDelegate.pixelRatio ||
      semantics != oldDelegate.semantics;
}

/// The scene's [CustomPaint], with a render object the semantics
/// coordinator can schedule updates on. The widget-surface hosts ride as
/// its child so their semantics assemble under the same boundary as the
/// nodes synthesized for the scene's SemanticsComponents.
class _SceneCustomPaint extends CustomPaint {
  const _SceneCustomPaint({
    required this.semantics,
    required _ScenePainter super.painter,
    required Widget super.child,
    // Size.infinite fills the largest bounded constraints the view is given
    // (both tight constraints and a Stack's loose ones), so the scene is
    // never collapsed to zero size. See the class doc: place SceneView
    // where it receives bounded constraints. With a child present the
    // render object sizes to it, so the child is a SizedBox.expand.
  }) : super(size: Size.infinite);

  final SceneSemanticsCoordinator semantics;

  @override
  RenderCustomPaint createRenderObject(BuildContext context) =>
      _RenderSceneCustomPaint(
        semantics: semantics,
        painter: painter,
        preferredSize: size,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSceneCustomPaint renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.semantics = semantics;
  }
}

class _RenderSceneCustomPaint extends RenderCustomPaint {
  _RenderSceneCustomPaint({
    required SceneSemanticsCoordinator semantics,
    super.painter,
    required super.preferredSize,
  }) : _semantics = semantics;

  SceneSemanticsCoordinator _semantics;
  set semantics(SceneSemanticsCoordinator value) {
    if (identical(value, _semantics)) return;
    if (identical(_semantics.renderObject, this)) {
      _semantics.renderObject = null;
    }
    _semantics = value;
    if (attached) {
      _semantics.renderObject = this;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _semantics.renderObject = this;
  }

  @override
  void detach() {
    if (identical(_semantics.renderObject, this)) {
      _semantics.renderObject = null;
    }
    super.detach();
  }
}

/// Exposes the active [Scene] (and the per-frame [elapsed] time) to descendants
/// of a [SceneView].
///
/// Resolve the scene from a descendant's [BuildContext] with [SceneScope.of].
/// Today [SceneView] is the only producer and there are no built-in consumers;
/// this plumbing exists so a future declarative node API can attach widgets to
/// the right scene subtree without restructuring the view.
/// {@category Widgets}
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
