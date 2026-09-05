/// What flutter_scene is currently keeping resident on the GPU, what is
/// holding it, and how to hand the releasable part of it back.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'importer/scene_registry.dart';
import 'render/render_graph.dart';
import 'texture/texture_registry.dart';

/// One category of resident GPU memory.
/// {@category Assets and loading}
@immutable
class MemoryCategory {
  const MemoryCategory({
    required this.name,
    required this.bytes,
    required this.count,
  });

  /// What this category holds (`textures`, `scene templates`).
  final String name;

  /// Resident bytes, or null where the size is not knowable from Dart.
  final int? bytes;

  /// How many resources the category holds.
  final int count;

  @override
  String toString() =>
      '$name: $count${bytes == null ? '' : ' (${_mib(bytes!)} MiB)'}';
}

/// A snapshot of what flutter_scene is keeping resident.
///
/// Covers what the engine's shared caches pin, which is the memory an app has
/// no other way to see or release. Render targets are the exception: they can
/// be dropped directly with [releaseTransientRenderTargets], and are dropped
/// automatically when the platform reports memory pressure. It does not cover resources the app holds
/// itself (a [Texture2D] you constructed and kept), and it is a measure of
/// what is *pinned*, not of what the GPU has actually reclaimed. Dropping the
/// last reference to a resource makes it collectable, but the reclaim happens
/// on the engine's schedule.
/// {@category Assets and loading}
@immutable
class MemoryReport {
  const MemoryReport(this.categories);

  /// Every category, in a stable order.
  final List<MemoryCategory> categories;

  /// Total resident bytes across the categories that can report a size.
  int get totalBytes =>
      categories.fold(0, (sum, category) => sum + (category.bytes ?? 0));

  @override
  String toString() =>
      'MemoryReport(${_mib(totalBytes)} MiB)\n'
      '${categories.map((c) => '  $c').join('\n')}';
}

/// Takes a [MemoryReport] of what the engine's shared caches are holding.
///
/// Cheap enough to poll (it walks the cache maps and reads each texture's
/// reflected size), so it is reasonable to surface in a debug overlay.
/// {@category Assets and loading}
MemoryReport takeMemoryReport() {
  final textures = textureCacheFootprint();
  return MemoryReport([
    MemoryCategory(
      name: 'textures',
      bytes: textures.bytes,
      count: textures.count,
    ),
    // The render graph's transient attachments, across every live pool: the
    // per-view surface pools plus a scene's probe-capture and planar-capture
    // pools. Counted by pool rather than by texture, because a texture count
    // would say more about the attachment shapes a frame happened to need
    // than about anything an app can act on.
    MemoryCategory(
      name: 'render targets',
      bytes: TransientTexturePool.liveResidentBytes,
      count: TransientTexturePool.liveCount,
    ),
    // A template's footprint is spread across the geometry, materials, and
    // textures it realized, which are not individually measurable from here
    // yet, so only the count is reported.
    MemoryCategory(
      name: 'scene templates',
      bytes: null,
      count: sceneTemplateCacheCount(),
    ),
  ]);
}

String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(2);

/// Drops every pooled render-graph attachment currently held, and returns the
/// bytes released.
///
/// These are the intermediate targets a frame draws through — the shadow
/// atlas, HDR scene color, depth, the post-process chain, a probe capture's
/// cube faces, a planar reflection's capture attachments — pooled per view
/// and per frame in flight. The pools have no eviction of their own: they are
/// cleared when an output size changes and at no other point, so they settle
/// at the high-water mark of every attachment shape any frame has needed and
/// hold that for the life of the process. In a scene-heavy app this is
/// routinely the largest thing the engine pins, and it stays pinned after the
/// app navigates away from the scene that grew it.
///
/// Everything dropped is reallocated by the next frame that needs it, so the
/// cost is one frame's allocation. Loaded textures and scene templates are
/// left alone, so a live scene keeps everything it draws with. Swapchain
/// color rings are left alone too: the compositor may still be reading the
/// texture most recently issued, and they are two textures against pools
/// holding everything above.
///
/// Called for you on platform memory pressure unless
/// [releaseRenderTargetsOnMemoryPressure] is off. Call it directly when the
/// app knows something the platform does not — before decoding a large asset,
/// or when leaving a heavy scene for a screen that will not render for a
/// while.
/// {@category Rendering}
int releaseTransientRenderTargets() => TransientTexturePool.shedLive();

/// Whether pooled render targets are released when the platform reports
/// memory pressure.
///
/// On by default, matching `PaintingBinding` clearing the image cache and
/// `ServicesBinding` clearing `rootBundle` on the same signal. The pools are
/// the same kind of cache and usually larger than either.
///
/// Every platform raises the signal: iOS on a memory warning and again on
/// backgrounding, Android through `onTrimMemory` from `TRIM_MEMORY_RUNNING_LOW`
/// upward. Turn it off if the app would rather hold the pools and give memory
/// back another way, or pick its own moment with
/// [releaseTransientRenderTargets]. Setting it false detaches the observer
/// outright rather than leaving a registered listener that does nothing, and
/// it can be flipped at any time.
/// {@category Rendering}
bool get releaseRenderTargetsOnMemoryPressure => _releaseOnPressure;

set releaseRenderTargetsOnMemoryPressure(bool value) {
  if (_releaseOnPressure == value) return;
  _releaseOnPressure = value;
  _syncMemoryPressureObserver();
}

bool _releaseOnPressure = true;

/// Whether a binding is known to exist yet. Set by
/// [listenForMemoryPressure]; until then the setter above only records the
/// preference, so an app can turn the automatic release off before it calls
/// `Scene.initializeStaticResources()`.
bool _bindingReady = false;

_MemoryPressureObserver? _pressureObserver;

/// Starts listening for platform memory pressure, if the automatic release is
/// on.
///
/// Called from `Scene.initializeStaticResources`, so an app gets this without
/// asking. Attached at initialization rather than at first render because
/// loading is when an app is most likely to be pushed over a limit, and by
/// then it should already be listening. Static resource loading goes through
/// `rootBundle`, so a binding exists by the time this runs.
@internal
void listenForMemoryPressure() {
  _bindingReady = true;
  _syncMemoryPressureObserver();
}

/// Detaches the observer. For tests, which must not leave one registered on a
/// binding that outlives the test.
@visibleForTesting
void stopListeningForMemoryPressure() {
  _bindingReady = false;
  _syncMemoryPressureObserver();
}

/// The observer currently attached, or null when the automatic release is off
/// or has not started. Lets a test assert the wiring without reaching into
/// the binding's observer list.
@visibleForTesting
WidgetsBindingObserver? get memoryPressureObserver => _pressureObserver;

void _syncMemoryPressureObserver() {
  final wanted = _bindingReady && _releaseOnPressure;
  if (wanted == (_pressureObserver != null)) return;
  if (wanted) {
    final observer = _MemoryPressureObserver();
    _pressureObserver = observer;
    WidgetsBinding.instance.addObserver(observer);
  } else {
    WidgetsBinding.instance.removeObserver(_pressureObserver!);
    _pressureObserver = null;
  }
}

class _MemoryPressureObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    releaseTransientRenderTargets();
  }
}
