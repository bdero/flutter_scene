import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

/// When a [WidgetTexture] (or a `WidgetComponent`) re-captures its child.
sealed class WidgetUpdatePolicy {
  const WidgetUpdatePolicy._();

  /// Capture whenever the child subtree repaints (the default). A static
  /// subtree costs nothing per frame.
  static const WidgetUpdatePolicy onRepaint = _OnRepaintUpdatePolicy();

  /// Capture at most once per [duration], even when the child repaints
  /// more often.
  const factory WidgetUpdatePolicy.interval(Duration duration) =
      _IntervalUpdatePolicy;

  /// Capture only when [WidgetTextureController.requestCapture] is called.
  static const WidgetUpdatePolicy manual = _ManualUpdatePolicy();
}

class _OnRepaintUpdatePolicy extends WidgetUpdatePolicy {
  const _OnRepaintUpdatePolicy() : super._();
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
  void pointerDown(Offset uv) => _host?._pointerDown(uv);

  /// Moves the active pointer to [uv].
  void pointerMove(Offset uv) => _host?._pointerMove(uv);

  /// Releases the active pointer at [uv].
  void pointerUp(Offset uv) => _host?._pointerUp(uv);

  /// Cancels the active pointer interaction, if any.
  void pointerCancel() => _host?._pointerCancel();

  /// Sends a complete tap (down then up) at [uv].
  void tapAt(Offset uv) {
    pointerDown(uv);
    pointerUp(uv);
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
    this.update = WidgetUpdatePolicy.onRepaint,
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
  int? _activePointer;
  HitTestResult? _activePath;
  Offset _lastLocal = Offset.zero;

  Offset _uvToLocal(Offset uv) => Offset(
    (uv.dx.clamp(0.0, 1.0)) * _captureSize.width,
    (uv.dy.clamp(0.0, 1.0)) * _captureSize.height,
  );

  void _pointerDown(Offset uv) {
    final child = this.child;
    if (child == null) return;
    if (_activePointer != null) _pointerCancel();
    final local = _uvToLocal(uv);
    final result = HitTestResult();
    child.hitTest(BoxHitTestResult.wrap(result), position: local);
    // The trailing binding entry routes the event into the pointer router
    // and closes the gesture arena, mirroring the live pointer pipeline.
    result.add(HitTestEntry(GestureBinding.instance));
    _activePointer = _nextSyntheticPointer++;
    _activePath = result;
    _lastLocal = local;
    GestureBinding.instance.dispatchEvent(
      PointerDownEvent(pointer: _activePointer!, position: local),
      result,
    );
  }

  void _pointerMove(Offset uv) {
    final pointer = _activePointer;
    final path = _activePath;
    if (pointer == null || path == null) return;
    final local = _uvToLocal(uv);
    GestureBinding.instance.dispatchEvent(
      PointerMoveEvent(
        pointer: pointer,
        position: local,
        delta: local - _lastLocal,
      ),
      path,
    );
    _lastLocal = local;
  }

  void _pointerUp(Offset uv) {
    final pointer = _activePointer;
    final path = _activePath;
    if (pointer == null || path == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerUpEvent(pointer: pointer, position: _uvToLocal(uv)),
      path,
    );
    _activePointer = null;
    _activePath = null;
  }

  void _pointerCancel() {
    final pointer = _activePointer;
    final path = _activePath;
    if (pointer == null || path == null) return;
    GestureBinding.instance.dispatchEvent(
      PointerCancelEvent(pointer: pointer, position: _lastLocal),
      path,
    );
    _activePointer = null;
    _activePath = null;
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
      case _OnRepaintUpdatePolicy():
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
        break; // Holds the latest recording until requestCapture().
    }
    // Nothing is painted into the live tree; the subtree only exists in the
    // captured texture.
  }

  /// Captures the latest recorded content immediately (the manual-policy
  /// trigger; also forces a capture under other policies).
  void _captureNow() => _pumpCapture();

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
  }

  @override
  void detach() {
    _pointerCancel();
    if (identical(_controller._host, this)) _controller._host = null;
    _pendingLayer?.dispose();
    _pendingLayer = null;
    super.detach();
  }
}
