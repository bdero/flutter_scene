import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/surface.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

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

  /// The policy's serialized name (`everyFrame`, `interval`, `manual`).
  @internal
  String get kindName => switch (this) {
    _EveryFrameUpdate() => 'everyFrame',
    _IntervalUpdate() => 'interval',
    _ManualUpdate() => 'manual',
  };

  /// The interval for [RenderTextureUpdate.interval] policies, else null.
  @internal
  Duration? get intervalDuration => switch (this) {
    _IntervalUpdate(:final duration) => duration,
    _ => null,
  };
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

/// Sampling options used when a material samples a [RenderTexture].
///
/// Captures default to bilinear filtering with clamped edges (the right
/// choice for screen-like content, where wrapping would bleed opposite
/// edges together). Use [gpu.MinMagFilter.nearest] for a pixelated look.
/// {@category Rendering}
class RenderTextureSampling {
  /// Creates sampling options.
  const RenderTextureSampling({
    this.filter = gpu.MinMagFilter.linear,
    this.wrap = gpu.SamplerAddressMode.clampToEdge,
  });

  /// The minification/magnification filter.
  final gpu.MinMagFilter filter;

  /// The addressing mode for texture coordinates outside `0..1`, applied
  /// to both axes.
  final gpu.SamplerAddressMode wrap;

  /// The equivalent sampler description.
  @internal
  gpu.SamplerOptions toSamplerOptions() => gpu.SamplerOptions(
    minFilter: filter,
    magFilter: filter,
    widthAddressMode: wrap,
    heightAddressMode: wrap,
  );
}

/// An offscreen render target a `RenderView` can render into.
///
/// Create one, set it as a view's `RenderView.target`, and add the view to
/// `Scene.views`; the scene renders it (subject to [update]) whenever the
/// scene itself renders. Display it in the widget tree with a
/// `RenderTextureView`, or assign it to a material texture slot (for
/// example `PhysicallyBasedMaterial.baseColorTexture` or
/// `UnlitMaterial.baseColorTexture`) to show the live capture on scene
/// geometry, the security-camera/monitor/mirror pattern. Material
/// sampling uses [sampling].
///
/// The texture holds the same display-referred premultiplied image a
/// screen view shows (tone mapping and anti-aliasing applied), sized at
/// exactly [width] x [height] physical pixels.
///
/// The engine owns the GPU textures behind this handle (a small ring, so
/// writing a new frame never races a still-displayed previous frame).
/// Consumers hold the [RenderTexture] itself and resolve [texture] when
/// they draw; notifications fire after each re-render.
///
/// Texture-target views render in `RenderView.order` before the screen
/// views, and [texture] always returns the most recently *completed*
/// frame. So a consumer drawn after this target's producing view samples
/// this frame's capture, while a consumer visible *inside* the capture
/// (including the target sampling itself, a mirror facing a mirror)
/// samples the previous frame instead of forming a feedback loop.
/// {@category Rendering}
class RenderTexture extends ChangeNotifier implements TextureSource {
  /// Creates a render target of [width] x [height] physical pixels.
  RenderTexture({
    required int width,
    required int height,
    this.update = RenderTextureUpdate.everyFrame,
    this.sampling = const RenderTextureSampling(),
  }) : assert(width > 0 && height > 0, 'RenderTexture size must be positive'),
       _size = ui.Size(width.toDouble(), height.toDouble());

  @override
  gpu.Texture? get sampledTexture => texture;

  @override
  gpu.SamplerOptions get sampledSampler => sampling.toSamplerOptions();

  // The ring + transient pool live in a single-view Surface, the same
  // machinery (and frames-in-flight depth) backing the screen swapchain.
  final Surface _surface = Surface();

  ui.Size _size;

  /// When this target re-renders. See [RenderTextureUpdate].
  RenderTextureUpdate update;

  /// Sampling options used when a material samples this target.
  RenderTextureSampling sampling;

  DateTime? _lastUpdateTime;
  bool _updateRequested = false;
  bool _hasRendered = false;
  gpu.Texture? _latest;
  gpu.Texture? _pending;

  /// The target width in physical pixels.
  int get width => _size.width.toInt();

  /// The target height in physical pixels.
  int get height => _size.height.toInt();

  /// The most recently completed frame, or null before the first render.
  ///
  /// The returned object changes identity across frames (the ring
  /// advances), so hold the [RenderTexture] and re-read this when drawing
  /// rather than caching the result. While this target's own producing
  /// view is being encoded, this still returns the previous frame, which
  /// is what makes self-sampling read one frame stale instead of forming
  /// a feedback loop (see the class doc).
  gpu.Texture? get texture => _latest;

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
  /// transient pool's frame. [texture] keeps returning the previous frame
  /// until [markUpdated] publishes the new one.
  @internal
  gpu.Texture acquireNextTexture() =>
      _pending = _surface.getNextSwapchainColorTexture(_size);

  /// The transient texture pool for this target's render passes.
  @internal
  TransientTexturePool get transientTexturePool =>
      _surface.transientTexturePool();

  /// Publishes the frame written since [acquireNextTexture] and notifies
  /// consumers.
  @internal
  void markUpdated(DateTime now) {
    _lastUpdateTime = now;
    _hasRendered = true;
    _latest = _pending ?? _latest;
    _pending = null;
    notifyListeners();
  }
}
