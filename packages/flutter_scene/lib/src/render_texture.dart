import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/surface.dart';

/// When a [RenderTexture] re-renders.
///
/// The same shape as `WidgetUpdatePolicy` (the widget-to-texture
/// direction), so both capture pipelines share one mental model.
/// {@category Rendering}
sealed class RenderTextureUpdate {
  const RenderTextureUpdate._();

  /// Re-render every frame the owning scene renders (the default). Use for
  /// mirrors and live monitors; each enabled target adds a full render
  /// pass per frame, so prefer [interval] or [manual] for content that
  /// changes rarely.
  static const RenderTextureUpdate everyFrame = _EveryFrameUpdate();

  /// Re-render at most once per [duration] (a minimap or telemetry view
  /// that doesn't need every frame).
  const factory RenderTextureUpdate.interval(Duration duration) =
      _IntervalUpdate;

  /// Render once when first wired, then only when
  /// [RenderTexture.requestUpdate] is called.
  static const RenderTextureUpdate manual = _ManualUpdate();
}

class _EveryFrameUpdate extends RenderTextureUpdate {
  const _EveryFrameUpdate() : super._();
}

class _IntervalUpdate extends RenderTextureUpdate {
  const _IntervalUpdate(this.duration) : super._();
  final Duration duration;
}

class _ManualUpdate extends RenderTextureUpdate {
  const _ManualUpdate() : super._();
}

/// An offscreen render target a `RenderView` can render into.
///
/// Create one, set it as a view's `RenderView.target`, and add the view to
/// `Scene.views`; the scene renders it (subject to [update]) whenever the
/// scene itself renders. Display it in the widget tree with a
/// `RenderTextureView`.
///
/// The texture holds the same display-referred premultiplied image a
/// screen view shows (tone mapping and anti-aliasing applied), sized at
/// exactly [width] x [height] physical pixels.
///
/// The engine owns the GPU textures behind this handle (a small ring, so
/// writing a new frame never races a still-displayed previous frame).
/// Consumers hold the [RenderTexture] itself and resolve [texture] when
/// they draw; notifications fire after each re-render.
/// {@category Rendering}
class RenderTexture extends ChangeNotifier {
  /// Creates a render target of [width] x [height] physical pixels.
  RenderTexture({
    required int width,
    required int height,
    this.update = RenderTextureUpdate.everyFrame,
  }) : assert(width > 0 && height > 0, 'RenderTexture size must be positive'),
       _size = ui.Size(width.toDouble(), height.toDouble());

  // The ring + transient pool live in a single-view Surface, the same
  // machinery (and frames-in-flight depth) backing the screen swapchain.
  final Surface _surface = Surface();

  ui.Size _size;

  /// When this target re-renders. See [RenderTextureUpdate].
  RenderTextureUpdate update;

  DateTime? _lastUpdateTime;
  bool _updateRequested = false;
  bool _hasRendered = false;

  /// The target width in physical pixels.
  int get width => _size.width.toInt();

  /// The target height in physical pixels.
  int get height => _size.height.toInt();

  /// The most recently rendered texture, or null before the first render.
  ///
  /// The returned object changes identity across frames (the ring
  /// advances), so hold the [RenderTexture] and re-read this when drawing
  /// rather than caching the result.
  gpu.Texture? get texture => _surface.lastSwapchainColorTexture();

  /// Reallocates the target at a new size. Consumers pick up the new
  /// textures on the next render; the next [update] check re-renders
  /// regardless of policy so the target is never displayed stale-sized.
  void resize(int width, int height) {
    assert(width > 0 && height > 0, 'RenderTexture size must be positive');
    final newSize = ui.Size(width.toDouble(), height.toDouble());
    if (newSize == _size) {
      return;
    }
    _size = newSize;
    // The Surface ring detects the size change on next acquire; force a
    // re-render so manual/interval targets don't keep a stale-sized image.
    _updateRequested = true;
  }

  /// With [RenderTextureUpdate.manual], renders once on the scene's next
  /// frame. Has no effect with the other policies (they re-render on
  /// their own schedule).
  void requestUpdate() {
    _updateRequested = true;
  }

  /// Whether the owning scene should re-render this target now. Consumes
  /// a pending [requestUpdate] when it returns true.
  @internal
  bool shouldUpdate(DateTime now) {
    if (_updateRequested) {
      _updateRequested = false;
      return true;
    }
    switch (update) {
      case _EveryFrameUpdate():
        return true;
      case _IntervalUpdate(:final duration):
        final last = _lastUpdateTime;
        return last == null || now.difference(last) >= duration;
      case _ManualUpdate():
        return !_hasRendered;
    }
  }

  /// The next ring texture to render into. Advances the ring and the
  /// transient pool's frame.
  @internal
  gpu.Texture acquireNextTexture() =>
      _surface.getNextSwapchainColorTexture(_size);

  /// The transient texture pool for this target's render passes.
  @internal
  TransientTexturePool get transientTexturePool =>
      _surface.transientTexturePool();

  /// Records that a render completed and notifies consumers.
  @internal
  void markUpdated(DateTime now) {
    _lastUpdateTime = now;
    _hasRendered = true;
    notifyListeners();
  }
}
