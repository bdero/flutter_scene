/// Releasing GPU memory when the platform reports it is running short.
library;

import 'package:flutter/foundation.dart' show internal, visibleForTesting;
import 'package:flutter/widgets.dart';

import 'surface.dart';

/// Drops every transient render-graph attachment currently held and returns
/// the bytes released.
///
/// These are the intermediate render targets — shadow atlas, HDR scene color,
/// depth, and the post-process chain — pooled per view and per frame in
/// flight. The pool has no eviction of its own, so it settles at the
/// high-water mark of every attachment shape any frame has needed and holds
/// that for the life of the process. In a scene-heavy app it is routinely the
/// largest thing the engine pins.
///
/// Everything dropped is reallocated by the next frame that needs it, so the
/// cost is one frame's allocation. Loaded textures and scene templates are not
/// touched, so a live scene keeps everything it is drawing with.
///
/// Called automatically on platform memory pressure. Call it directly when the
/// app knows something the platform does not, such as being about to decode a
/// large asset.
/// {@category Rendering}
int releaseTransientRenderTargets() => Surface.shedTransientRenderTargets();

/// Whether the automatic release runs when the platform reports pressure.
///
/// On by default, which matches `PaintingBinding` clearing the image cache and
/// `ServicesBinding` clearing `rootBundle` on the same signal. Set it false if
/// an app would rather hold the pool and give memory back another way, or pick
/// its own moment with [releaseTransientRenderTargets]. The listener stays
/// registered either way, so this can be flipped at any time.
/// {@category Rendering}
bool releaseRenderTargetsOnMemoryPressure = true;

/// Registers the platform memory-pressure listener, once per process.
///
/// Called from [Scene.initializeStaticResources], so an app gets this without
/// asking for it. Registered at initialization rather than at first render
/// because loading is when an app is most likely to be pushed over a limit,
/// and by then it should already be listening.
@internal
void listenForMemoryPressure() {
  if (memoryPressureObserver != null) return;
  // Static resource loading already goes through `rootBundle`, so a widgets
  // binding exists by the time this runs.
  memoryPressureObserver = _MemoryPressureObserver();
  WidgetsBinding.instance.addObserver(memoryPressureObserver!);
}

/// The registered observer, or null before [listenForMemoryPressure] has run.
@visibleForTesting
WidgetsBindingObserver? memoryPressureObserver;

class _MemoryPressureObserver with WidgetsBindingObserver {
  @override
  void didHaveMemoryPressure() {
    if (!releaseRenderTargetsOnMemoryPressure) return;
    releaseTransientRenderTargets();
  }
}
