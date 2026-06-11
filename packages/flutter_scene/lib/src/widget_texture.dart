import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// When a [WidgetTexture] (or a `WidgetComponent`) re-captures its child.
/// {@category Widgets}
sealed class WidgetUpdatePolicy {
  const WidgetUpdatePolicy._();

  /// Capture every frame while attached (the default). Captures are
  /// throttled to one in flight, and the recording itself reuses the
  /// child's retained layers, so the steady-state cost is the rasterize
  /// and readback of content that is actually changing.
  ///
  /// Per-frame capture is the only trigger that observes every change:
  /// repaints inside the child's own repaint boundaries (scrollable items,
  /// progress indicators) update their layers in place without notifying
  /// ancestors, so a repaint-driven trigger misses them.
  static const WidgetUpdatePolicy everyFrame = _EveryFrameUpdatePolicy();

  /// Capture at most once per [duration].
  const factory WidgetUpdatePolicy.interval(Duration duration) =
      _IntervalUpdatePolicy;

  /// Capture only when [WidgetTextureController.requestCapture] is called.
  static const WidgetUpdatePolicy manual = _ManualUpdatePolicy();
}

class _EveryFrameUpdatePolicy extends WidgetUpdatePolicy {
  const _EveryFrameUpdatePolicy() : super._();
}

class _IntervalUpdatePolicy extends WidgetUpdatePolicy {
  const _IntervalUpdatePolicy(this.duration) : super._();
  final Duration duration;
}

class _ManualUpdatePolicy extends WidgetUpdatePolicy {
  const _ManualUpdatePolicy() : super._();
}

/// Owns the [gpu.Texture] a [WidgetTexture] streams its child into.
///
/// Bind [texture] to any material texture slot (for example
/// `PhysicallyBasedMaterial.baseColorTexture`). It is null until the first
/// capture completes; listen for changes to pick it up (the texture object is
/// also replaced when the capture size changes).
///
/// Captures round-trip through the CPU today (rasterize, read back, upload),
/// so treat this as a correct-but-slow path: captures are throttled to one in
/// flight and only run when the child subtree actually repaints, but each one
/// costs a readback on the raster thread plus a byte upload.
/// {@category Widgets}
// TODO(widget-textures): keep the snapshot on the GPU once the engine can
// wrap a ui.Image's backing texture as a flutter_gpu texture (the planned
// gpu.Texture.fromImage); the capture and binding API stays the same.
class WidgetTextureController extends ChangeNotifier {
  gpu.Texture? _texture;
  Duration _lastCaptureDuration = Duration.zero;
  int _captureCount = 0;
  _RenderWidgetTexture? _host;

  /// The most recent capture, or null before the first one completes.
  gpu.Texture? get texture => _texture;

  /// Wall-clock duration of the last capture round trip (rasterize, read
  /// back, upload), for diagnostics.
  Duration get lastCaptureDuration => _lastCaptureDuration;

  /// Total completed captures, for diagnostics.
  int get captureCount => _captureCount;

  void _publish(ByteData bytes, int width, int height, Duration elapsed) {
    var texture = _texture;
    if (texture == null || texture.width != width || texture.height != height) {
      texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        width,
        height,
        format: gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderWriteUsage: false,
      );
      _texture = texture;
    }
    texture.overwrite(bytes);
    _lastCaptureDuration = elapsed;
    _captureCount++;
    notifyListeners();
  }

  // ----- input forwarding -----
  //
  // The hosted subtree never appears on screen, so the framework's pointer
  // pipeline can't reach it. These methods synthesize pointer events at a
  // texture-space [uv] coordinate ((0,0) top-left to (1,1) bottom-right,
  // matching the sampled texture) and dispatch them through the gesture
  // system, so taps and drags raycast against scene geometry can drive the
  // widgets. Gesture recognizers (buttons, drags, scrollables) work
  // normally.
  // TODO(widget-textures): hover (MouseRegion enter/exit) needs MouseTracker
  // integration, which tracks annotations on the on-screen layer tree.

  /// Sends a pointer down at [uv]. Follow with [pointerMove] and [pointerUp]
  /// (or [pointerCancel]) to complete the interaction.
  ///
  /// [pointer] distinguishes concurrent pointers (multi-touch, several
  /// `ScenePointer`s): each carries independent capture and gesture state.
  void pointerDown(Offset uv, {int pointer = 0}) =>
      _host?._pointerDown(uv, pointer);

  /// Moves an active pointer to [uv].
  void pointerMove(Offset uv, {int pointer = 0}) =>
      _host?._pointerMove(uv, pointer);

  /// Releases an active pointer at [uv].
  void pointerUp(Offset uv, {int pointer = 0}) =>
      _host?._pointerUp(uv, pointer);

  /// Cancels an active pointer interaction, if any.
  void pointerCancel({int pointer = 0}) => _host?._pointerCancel(pointer);

  /// Sends a scroll at [uv] of [scrollDelta] logical pixels (positive y
  /// scrolls down), driving scrollables under that point.
  void pointerScroll(Offset uv, Offset scrollDelta) =>
      _host?._pointerScroll(uv, scrollDelta);

  /// Sends a complete tap (down then up) at [uv].
  void tapAt(Offset uv, {int pointer = 0}) {
    pointerDown(uv, pointer: pointer);
    pointerUp(uv, pointer: pointer);
  }

  /// Captures the child's latest recorded content now. The trigger for
  /// [WidgetUpdatePolicy.manual]; under other policies it forces an
  /// immediate capture (subject to one-in-flight throttling).
  void requestCapture() => _host?._captureNow();
}

/// Hosts a live widget subtree and streams its visual output into a
/// [WidgetTextureController]'s texture for sampling inside a scene.
///
/// The child stays fully live (state, tickers, and animations run normally)
/// but is never painted to the screen; this widget occupies zero layout space
/// in its host tree. The child is laid out at the fixed logical size
/// [width] x [height], and captures render at that size times [pixelRatio].
///
/// A capture is recorded whenever the child repaints, so a static subtree
/// costs nothing per frame. Captures are asynchronous and throttled to one in
/// flight; when the child repaints faster than captures complete, intermediate
/// frames are skipped and the texture always converges on the latest content.
///
/// Pointer input does not reach the child (the subtree never appears on
/// screen).
/// {@category Widgets}
// TODO(widget-textures): route pointer events from scene raycasts into the
// hosted subtree so textured widgets become interactive.
class WidgetTexture extends SingleChildRenderObjectWidget {
  /// Creates a widget-texture host capturing [child] at [width] x [height]
  /// logical pixels into [controller].
  const WidgetTexture({
    super.key,
    required this.controller,
    required this.width,
    required this.height,
    this.pixelRatio = 1.0,
    this.update = WidgetUpdatePolicy.everyFrame,
    required Widget super.child,
  });

  /// Receives the captured texture.
  final WidgetTextureController controller;

  /// The child's logical layout width.
  final double width;

  /// The child's logical layout height.
  final double height;

  /// Texels per logical pixel in the captured texture.
  final double pixelRatio;

  /// When the child is re-captured; see [WidgetUpdatePolicy].
  final WidgetUpdatePolicy update;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWidgetTexture(
    controller: controller,
    captureSize: Size(width, height),
    pixelRatio: pixelRatio,
    update: update,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    // ignore: library_private_types_in_public_api
    _RenderWidgetTexture renderObject,
  ) {
    renderObject
      ..controller = controller
      ..captureSize = Size(width, height)
      ..pixelRatio = pixelRatio
      ..update = update;
  }
}

/// Grants access to [PaintingContext]'s protected constructor and recording
/// control, so the child can be painted into a detached layer.
class _CapturePaintingContext extends PaintingContext {
  _CapturePaintingContext(super.containerLayer, super.estimatedBounds);

  void stopRecording() => stopRecordingIfNeeded();
}

class _RenderWidgetTexture extends RenderProxyBox {
  _RenderWidgetTexture({
    required WidgetTextureController controller,
    required Size captureSize,
    required double pixelRatio,
    required WidgetUpdatePolicy update,
  }) : _controller = controller,
       _captureSize = captureSize,
       _pixelRatio = pixelRatio,
       _update = update;

  WidgetUpdatePolicy _update;
  set update(WidgetUpdatePolicy value) => _update = value;
  DateTime _lastCaptureStart = DateTime.fromMillisecondsSinceEpoch(0);

  WidgetTextureController _controller;
  set controller(WidgetTextureController value) {
    if (identical(value, _controller)) return;
    if (identical(_controller._host, this)) _controller._host = null;
    _controller = value;
    if (attached) _controller._host = this;
  }

  Size _captureSize;
  set captureSize(Size value) {
    if (value == _captureSize) return;
    _captureSize = value;
    markNeedsLayout();
  }

  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  // The most recently recorded (not yet rasterized) capture layer. Replaced
  // by newer paints; the in-flight capture rasterizes whatever is latest.
  OffsetLayer? _pendingLayer;
  bool _captureInFlight = false;

  // ----- synthetic pointer dispatch -----

  // Base offset keeps synthetic pointer ids clear of platform pointers.
  static int _nextSyntheticPointer = 0x40000000;

  // Per caller-pointer-id interaction state: each concurrent pointer gets
  // its own synthetic Flutter pointer id, hit path (captured at down, the
  // standard pointer-capture semantics), and last position.
  final Map<int, _SyntheticPointer> _pointers = {};

  Offset _uvToLocal(Offset uv) => Offset(
    (uv.dx.clamp(0.0, 1.0)) * _captureSize.width,
    (uv.dy.clamp(0.0, 1.0)) * _captureSize.height,
  );

  void _pointerDown(Offset uv, int id) {
    final child = this.child;
    if (child == null) return;
    if (_pointers.containsKey(id)) _pointerCancel(id);
    final local = _uvToLocal(uv);
    final result = HitTestResult();
    child.hitTest(BoxHitTestResult.wrap(result), position: local);
    // The trailing binding entry routes the event into the pointer router
    // and closes the gesture arena, mirroring the live pointer pipeline.
    result.add(HitTestEntry(GestureBinding.instance));
    final state = _SyntheticPointer(_nextSyntheticPointer++, result, local);
    _pointers[id] = state;
    GestureBinding.instance.dispatchEvent(
      PointerDownEvent(pointer: state.pointer, position: local),
      result,
    );
  }

  void _pointerMove(Offset uv, int id) {
    final state = _pointers[id];
    if (state == null) return;
    final local = _uvToLocal(uv);
    GestureBinding.instance.dispatchEvent(
      PointerMoveEvent(
        pointer: state.pointer,
        position: local,
        delta: local - state.lastLocal,
      ),
      state.path,
    );
    state.lastLocal = local;
  }

  void _pointerUp(Offset uv, int id) {
    final state = _pointers.remove(id);
    if (state == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerUpEvent(pointer: state.pointer, position: _uvToLocal(uv)),
      state.path,
    );
  }

  void _pointerCancel(int id) {
    final state = _pointers.remove(id);
    if (state == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerCancelEvent(pointer: state.pointer, position: state.lastLocal),
      state.path,
    );
  }

  void _pointerScroll(Offset uv, Offset scrollDelta) {
    final child = this.child;
    if (child == null) return;
    final local = _uvToLocal(uv);
    final result = HitTestResult();
    child.hitTest(BoxHitTestResult.wrap(result), position: local);
    result.add(HitTestEntry(GestureBinding.instance));
    // The binding entry's handleEvent resolves pointer signals, so
    // scrollables under the point receive the event.
    GestureBinding.instance.dispatchEvent(
      PointerScrollEvent(position: local, scrollDelta: scrollDelta),
      result,
    );
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void performLayout() {
    // Size comes from performResize (sizedByParent); only the child needs
    // laying out, at the fixed capture size.
    child?.layout(BoxConstraints.tight(_captureSize));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  // The child never appears on screen, so it has no semantics.
  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;

    // Record the child into a detached layer (display-list recording only;
    // rasterization happens asynchronously in _pumpCapture).
    final layer = OffsetLayer();
    final captureContext = _CapturePaintingContext(
      layer,
      Offset.zero & _captureSize,
    );
    captureContext.paintChild(child, Offset.zero);
    captureContext.stopRecording();

    _pendingLayer?.dispose();
    _pendingLayer = layer;
    switch (_update) {
      case _EveryFrameUpdatePolicy():
        _pumpCapture();
      case _IntervalUpdatePolicy(:final duration):
        final wait = duration - DateTime.now().difference(_lastCaptureStart);
        if (wait <= Duration.zero) {
          _pumpCapture();
        } else {
          Future<void>.delayed(wait, () {
            if (attached && _pendingLayer != null) _pumpCapture();
          });
        }
      case _ManualUpdatePolicy():
        if (_manualCaptureRequested) {
          _manualCaptureRequested = false;
          _pumpCapture();
        }
    }
    // Nothing is painted into the live tree; the subtree only exists in the
    // captured texture.
    _scheduleFramePump();
  }

  bool _manualCaptureRequested = false;
  bool _framePumpScheduled = false;

  // Re-records the child each frame (per policy) by dirtying this boundary.
  // The child's repaint boundaries (scrollable items, progress indicators)
  // repaint in place without notifying ancestors, so paint-driven capture
  // alone misses their changes; the per-frame re-record observes them, and
  // recording reuses the child's retained layers so it stays cheap.
  void _scheduleFramePump() {
    if (_framePumpScheduled || !attached) return;
    final due = switch (_update) {
      _EveryFrameUpdatePolicy() => true,
      _IntervalUpdatePolicy() => true,
      _ManualUpdatePolicy() => false,
    };
    if (!due) return;
    _framePumpScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _framePumpScheduled = false;
      if (!attached) return;
      markNeedsPaint();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Captures the child's current content (the manual-policy trigger; also
  /// forces a capture under other policies).
  void _captureNow() {
    _manualCaptureRequested = true;
    markNeedsPaint();
    if (_pendingLayer != null) {
      _manualCaptureRequested = false;
      _pumpCapture();
    }
  }

  Future<void> _pumpCapture() async {
    if (_captureInFlight) return;
    _captureInFlight = true;
    try {
      while (_pendingLayer != null && attached) {
        final layer = _pendingLayer!;
        _pendingLayer = null;
        _lastCaptureStart = DateTime.now();
        final stopwatch = Stopwatch()..start();
        try {
          final image = await layer.toImage(
            Offset.zero & _captureSize,
            pixelRatio: _pixelRatio,
          );
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          if (bytes != null && attached) {
            _controller._publish(
              bytes,
              image.width,
              image.height,
              stopwatch.elapsed,
            );
          }
          image.dispose();
        } finally {
          layer.dispose();
        }
      }
    } finally {
      _captureInFlight = false;
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller._host = this;
    _scheduleFramePump();
  }

  @override
  void detach() {
    for (final id in _pointers.keys.toList()) {
      _pointerCancel(id);
    }
    if (identical(_controller._host, this)) _controller._host = null;
    _pendingLayer?.dispose();
    _pendingLayer = null;
    super.detach();
  }
}

/// One in-flight synthetic pointer interaction.
class _SyntheticPointer {
  _SyntheticPointer(this.pointer, this.path, this.lastLocal);

  final int pointer;
  final HitTestResult path;
  Offset lastLocal;
}
