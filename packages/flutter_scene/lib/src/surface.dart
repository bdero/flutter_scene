import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;

import 'package:flutter_scene/src/render/render_graph.dart';

/// Manages the swapchain color textures a [Scene] composites onto the
/// Flutter canvas, plus the pools of transient render-graph attachments.
///
/// Each [Scene] owns one `Surface`. A scene may render several views per
/// frame (split-screen, picture-in-picture); each view gets its own
/// swapchain ring and its own transient texture pool, so simultaneous views
/// never share a render target within a frame. View 0 is the single-view
/// default.
///
/// Every view, every frame, the renderer asks the surface for that view's
/// next swapchain color texture via [getNextSwapchainColorTexture]; the
/// surface rotates through a small ring per view so the GPU isn't asked to
/// overwrite one the compositor is still reading. The tone-mapping pass
/// renders the final image into this texture, which is then drawn to the
/// canvas via `Texture.asImage`. A view keeps the ring and transient pool of
/// its two most recent sizes, so a resolution that toggles (an adaptive
/// render scale) reuses them instead of reallocating every target; a size
/// left unused for a while is released.
///
/// Applications typically don't interact with `Surface` directly; it is
/// driven internally by [Scene.render] / [Scene.renderViews].
/// {@category Rendering}
class Surface {
  Surface() {
    // Swept here as well as in the shed so a program that churns through
    // surfaces does not grow the list between sheds.
    if (_live.length >= _liveSweepThreshold) {
      _live.removeWhere((ref) => ref.target == null);
    }
    _live.add(WeakReference<Surface>(this));
  }

  // TODO(bdero): There should be a method on the Flutter GPU context to pull
  //              this information.
  static const int _maxFramesInFlight = 2;

  static const int _liveSweepThreshold = 16;

  /// Every constructed surface, weakly. A [Scene] owns its surface for as long
  /// as it lives and has no disposal hook, so strong references here would pin
  /// a discarded scene's render targets for the life of the process.
  static final List<WeakReference<Surface>> _live = [];

  final List<_ViewSurface> _views = [];

  _ViewSurface _view(int index) {
    while (_views.length <= index) {
      _views.add(_ViewSurface());
    }
    return _views[index];
  }

  /// The transient texture pool for view [viewIndex] (the intermediate
  /// render-graph attachments: HDR scene color, depth, shadow maps,
  /// post-process buffers). Each view has its own pool so simultaneous
  /// views in a frame never share an attachment.
  @internal
  TransientTexturePool transientTexturePool([int viewIndex = 0]) =>
      _view(viewIndex).pool;

  /// Returns the next 8-bit swapchain color texture for view [viewIndex] at
  /// [size], advancing that view's frame. A new [size] gets its own ring and
  /// transient pool; the previous size's are kept for a return.
  gpu.Texture getNextSwapchainColorTexture(
    Size size, [
    int viewIndex = 0,
    gpu.PixelFormat? format,
  ]) => _view(viewIndex).nextSwapchainColor(size, format);

  /// The color texture most recently issued for [viewIndex] (the previous
  /// frame's output once the next frame begins), or null before the first
  /// frame or after a resize.
  ///
  /// Sampling it from a material creates a one-frame feedback loop, the
  /// scene's own output appearing inside the scene. The ring guarantees the
  /// returned texture is not the one being rendered this frame, so reading
  /// it while the current frame draws is safe.
  gpu.Texture? lastSwapchainColorTexture([int viewIndex = 0]) =>
      _view(viewIndex)._lastIssued;

  /// Resident bytes of the transient attachments this surface's views hold.
  @internal
  int get transientBytes {
    var bytes = 0;
    for (final view in _views) {
      bytes += view.residentBytes;
    }
    return bytes;
  }

  /// Resident bytes of the transient attachments held by every live surface.
  @internal
  static int get liveTransientBytes {
    var bytes = 0;
    _forEachLive((surface) => bytes += surface.transientBytes);
    return bytes;
  }

  /// Drops every transient attachment this surface's views hold and returns
  /// the bytes released.
  ///
  /// The swapchain color ring is left alone. The compositor may still be
  /// reading the texture most recently issued, and it is two textures against
  /// a pool holding the shadow atlas, scene color, depth and the post-process
  /// chain.
  @internal
  int shedViewRenderTargets() {
    var bytes = 0;
    for (final view in _views) {
      bytes += view.shed();
    }
    return bytes;
  }

  /// Drops the transient attachments of every live surface and returns the
  /// bytes released. See [releaseTransientRenderTargets].
  @internal
  static int shedTransientRenderTargets() {
    var bytes = 0;
    _forEachLive((surface) => bytes += surface.shedViewRenderTargets());
    return bytes;
  }

  /// Visits every surface still alive, dropping references to collected ones
  /// on the way through.
  ///
  /// [visit] must not construct a [Surface]: the list is being mutated as it
  /// walks, and registering one mid-walk would throw. Nothing that calls this
  /// allocates.
  static void _forEachLive(void Function(Surface surface) visit) {
    _live.removeWhere((ref) {
      final surface = ref.target;
      if (surface == null) return true;
      visit(surface);
      return false;
    });
  }

  /// The number of live surfaces a shed would reach.
  @internal
  static int get liveCount {
    var count = 0;
    _forEachLive((_) => count++);
    return count;
  }
}

/// One output size's render targets: the swapchain color ring and the
/// transient texture pool.
class _SizedTargets {
  _SizedTargets(this.size, this.format);

  final Size size;
  final gpu.PixelFormat? format;
  final TransientTexturePool pool = TransientTexturePool(
    framesInFlight: Surface._maxFramesInFlight,
  );
  final List<gpu.Texture> swapchainColors = [];
  int cursor = 0;

  /// The view's frame count when this size last rendered.
  int lastUsed = 0;
}

/// One view's render targets, per recent output size. View 0 reproduces the
/// historical single-view behavior exactly.
class _ViewSurface {
  /// Output sizes whose targets are kept, the current one included.
  static const int _keptSizes = 2;

  /// Frames a kept size may go unused before its targets are released.
  static const int _idleFrames = 240;

  // Most recently used last.
  final List<_SizedTargets> _sizes = [];
  int _frame = 0;
  gpu.Texture? _lastIssued;

  _SizedTargets get _current {
    if (_sizes.isEmpty) _sizes.add(_SizedTargets(Size.zero, null));
    return _sizes.last;
  }

  TransientTexturePool get pool => _current.pool;

  int get residentBytes {
    var bytes = 0;
    for (final sized in _sizes) {
      bytes += sized.pool.residentBytes;
    }
    return bytes;
  }

  /// Drops every transient attachment and the other sizes' targets,
  /// returning the attachment bytes released. The current swapchain ring
  /// stays, since the compositor may still be reading its latest texture.
  int shed() {
    final bytes = residentBytes;
    for (final sized in _sizes) {
      sized.pool.clear();
    }
    if (_sizes.length > 1) _sizes.removeRange(0, _sizes.length - 1);
    return bytes;
  }

  gpu.Texture nextSwapchainColor(Size size, [gpu.PixelFormat? format]) {
    _frame++;
    var sized = _sizes.isEmpty ? null : _sizes.last;
    if (sized == null || sized.size != size || sized.format != format) {
      // Another size's previous output is the wrong size to sample.
      _lastIssued = null;
      final index = _sizes.indexWhere(
        (s) => s.size == size && s.format == format,
      );
      sized = index < 0 ? _SizedTargets(size, format) : _sizes.removeAt(index);
      _sizes.add(sized);
      while (_sizes.length > _keptSizes) {
        _sizes.removeAt(0);
      }
    }
    sized.lastUsed = _frame;
    _sizes.removeWhere((s) => _frame - s.lastUsed > _idleFrames);
    sized.pool.beginFrame();
    final colors = sized.swapchainColors;
    if (sized.cursor == colors.length) {
      colors.add(
        gpu.gpuContext.createTexture(
          gpu.StorageMode.devicePrivate,
          size.width.toInt(),
          size.height.toInt(),
          format: format ?? gpu.PixelFormat.r8g8b8a8UNormInt,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        ),
      );
    }
    final result = colors[sized.cursor];
    sized.cursor = (sized.cursor + 1) % Surface._maxFramesInFlight;
    _lastIssued = result;
    return result;
  }
}
