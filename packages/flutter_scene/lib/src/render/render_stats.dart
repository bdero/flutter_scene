/// Steady-state rendering statistics: per-frame counters (draws, instances,
/// vertices, culling, batching, pipeline traffic) broken down by view and by
/// render-graph pass, each pass stopwatched on the CPU.
///
/// Always on. Counting is an integer increment at the draw funnel and each
/// frame allocates a handful of small records, so the cost is negligible next
/// to the rendering it describes. GPU times stay null until the engine
/// exposes timestamp queries.
///
/// TODO(gpu-timing): fill [RenderPassStats.gpuMicros] from pass-level
/// timestamp queries once flutter/flutter#190404 lands.
library;

/// Integer counters accumulated over a frame, a view, or a pass.
/// {@category Debugging and profiling}
class RenderCounters {
  RenderCounters();

  /// Draw calls issued (instanced draws count once).
  int draws = 0;

  /// Instances drawn across all draw calls.
  int instances = 0;

  /// Vertices (or indices, for indexed draws) processed, multiplied by the
  /// instance count.
  int vertices = 0;

  /// Render items the pass considered, including hidden ones and the whole
  /// BVH subtrees the frustum rejected.
  int submitted = 0;

  /// Items a frustum test rejected: a BVH subtree skipped whole, or the
  /// encoder's per-instance culling.
  int culled = 0;

  /// Items rejected by the view's render layer mask.
  int layerMasked = 0;

  /// Items skipped because their pipeline failed to build.
  int pipelineRejected = 0;

  /// Pipeline binds that reached the backend (the encoder skips redundant
  /// binds, so this is the state-change count).
  int pipelineBinds = 0;

  /// Pipelines built this frame. A nonzero steady-state value is a hitch.
  int pipelineBuilds = 0;

  /// Opaque draw calls that merged several nodes into one instanced draw.
  int batches = 0;

  /// Nodes folded into those merged draws.
  int batchedItems = 0;

  void reset() {
    draws = 0;
    instances = 0;
    vertices = 0;
    submitted = 0;
    culled = 0;
    layerMasked = 0;
    pipelineRejected = 0;
    pipelineBinds = 0;
    pipelineBuilds = 0;
    batches = 0;
    batchedItems = 0;
  }

  void copyFrom(RenderCounters other) {
    draws = other.draws;
    instances = other.instances;
    vertices = other.vertices;
    submitted = other.submitted;
    culled = other.culled;
    layerMasked = other.layerMasked;
    pipelineRejected = other.pipelineRejected;
    pipelineBinds = other.pipelineBinds;
    pipelineBuilds = other.pipelineBuilds;
    batches = other.batches;
    batchedItems = other.batchedItems;
  }

  /// Sets this to `now - start`.
  void setDelta(RenderCounters start, RenderCounters now) {
    draws = now.draws - start.draws;
    instances = now.instances - start.instances;
    vertices = now.vertices - start.vertices;
    submitted = now.submitted - start.submitted;
    culled = now.culled - start.culled;
    layerMasked = now.layerMasked - start.layerMasked;
    pipelineRejected = now.pipelineRejected - start.pipelineRejected;
    pipelineBinds = now.pipelineBinds - start.pipelineBinds;
    pipelineBuilds = now.pipelineBuilds - start.pipelineBuilds;
    batches = now.batches - start.batches;
    batchedItems = now.batchedItems - start.batchedItems;
  }

  Map<String, int> toJson() => {
    'draws': draws,
    'instances': instances,
    'vertices': vertices,
    'submitted': submitted,
    'culled': culled,
    'layerMasked': layerMasked,
    'pipelineRejected': pipelineRejected,
    'pipelineBinds': pipelineBinds,
    'pipelineBuilds': pipelineBuilds,
    'batches': batches,
    'batchedItems': batchedItems,
  };
}

/// The process-wide accumulator every draw funnel increments. Scopes snapshot
/// it at their boundaries and keep the delta, so attribution costs nothing
/// on the draw path.
final RenderCounters activeRenderCounters = RenderCounters();

/// One executed render-graph pass.
/// {@category Debugging and profiling}
class RenderPassStats {
  RenderPassStats({required this.name, required this.indexInGraph});

  final String name;
  final int indexInGraph;

  /// CPU time spent encoding the pass.
  int cpuMicros = 0;

  /// GPU time, or null while the engine has no timestamp queries.
  int? gpuMicros;

  final RenderCounters counters = RenderCounters();

  Map<String, Object?> toJson() => {
    'name': name,
    'index': indexInGraph,
    'cpuMicros': cpuMicros,
    if (gpuMicros != null) 'gpuMicros': gpuMicros,
    'counters': counters.toJson(),
  };
}

/// One rendered view: a screen view (by index) or a render texture.
/// {@category Debugging and profiling}
class RenderViewStats {
  RenderViewStats({
    required this.viewIndex,
    required this.width,
    required this.height,
    required this.offscreen,
  });

  /// The screen view index, or -1 for a render-texture view.
  final int viewIndex;
  final int width;
  final int height;

  /// True for a render-texture view (not composited to the canvas).
  final bool offscreen;

  /// CPU time spent building and executing this view's render graph.
  int cpuMicros = 0;

  final List<RenderPassStats> passes = [];
  final RenderCounters counters = RenderCounters();

  Map<String, Object?> toJson() => {
    'viewIndex': viewIndex,
    'width': width,
    'height': height,
    'offscreen': offscreen,
    'cpuMicros': cpuMicros,
    'counters': counters.toJson(),
    'passes': [for (final pass in passes) pass.toJson()],
  };
}

/// One rendered frame: every view with its passes, plus frame totals.
/// {@category Debugging and profiling}
class RenderFrameStats {
  RenderFrameStats({required this.frameIndex, required this.timestampMicros});

  /// Frames rendered by this scene so far, counting from zero.
  final int frameIndex;

  /// Wall-clock start of the frame, microseconds since the epoch.
  final int timestampMicros;

  /// CPU time from the start of `renderViews` to its end.
  int cpuMicros = 0;

  /// Pipelines held in the cache at the end of the frame.
  int pipelineCacheSize = 0;

  final List<RenderViewStats> views = [];

  /// Totals over the whole frame, including work outside any view's graph.
  final RenderCounters counters = RenderCounters();

  Map<String, Object?> toJson() => {
    'frameIndex': frameIndex,
    'timestampMicros': timestampMicros,
    'cpuMicros': cpuMicros,
    'pipelineCacheSize': pipelineCacheSize,
    'counters': counters.toJson(),
    'views': [for (final view in views) view.toJson()],
  };
}

/// A scene's rendering statistics: the last frame and a bounded history.
///
/// Read [latest] after a frame renders. Each frame is a fresh record, so a
/// retained one never changes under the caller.
/// {@category Debugging and profiling}
class RenderStats {
  RenderStats({this.historyLength = 120});

  /// Frames to retain in [history]; zero keeps only [latest].
  int historyLength;

  /// Whether the render graph emits `dart:developer` timeline events per
  /// pass (visible in DevTools). On by default; the VM drops them in
  /// release builds.
  static bool timelineEvents = true;

  RenderFrameStats? _latest;
  final List<RenderFrameStats> _history = [];
  int _frameCount = 0;

  /// The most recently completed frame, or null before the first.
  RenderFrameStats? get latest => _latest;

  /// Completed frames, oldest first, at most [historyLength].
  List<RenderFrameStats> get history => List.unmodifiable(_history);

  /// Frames completed so far.
  int get frameCount => _frameCount;

  RenderFrameStats? _active;
  final RenderCounters _frameStart = RenderCounters();
  final Stopwatch _frameWatch = Stopwatch();

  /// The frame being rendered, or null between frames.
  RenderFrameStats? get activeFrame => _active;

  /// Opens a frame. Called by the scene at the start of `renderViews`.
  RenderFrameStats beginFrame() {
    final frame = RenderFrameStats(
      frameIndex: _frameCount,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
    );
    _active = frame;
    _frameStart.copyFrom(activeRenderCounters);
    _frameWatch
      ..reset()
      ..start();
    return frame;
  }

  /// Closes the frame opened by [beginFrame].
  void endFrame({required int pipelineCacheSize}) {
    final frame = _active;
    if (frame == null) return;
    _frameWatch.stop();
    frame.cpuMicros = _frameWatch.elapsedMicroseconds;
    frame.pipelineCacheSize = pipelineCacheSize;
    frame.counters.setDelta(_frameStart, activeRenderCounters);
    _active = null;
    _latest = frame;
    _frameCount++;
    if (historyLength <= 0) {
      _history.clear();
      return;
    }
    _history.add(frame);
    while (_history.length > historyLength) {
      _history.removeAt(0);
    }
  }

  /// Opens a view scope inside the active frame, or returns null when no
  /// frame is open (a render outside `renderViews`).
  RenderViewStats? beginView({
    required int viewIndex,
    required int width,
    required int height,
    required bool offscreen,
  }) {
    final frame = _active;
    if (frame == null) return null;
    final view = RenderViewStats(
      viewIndex: viewIndex,
      width: width,
      height: height,
      offscreen: offscreen,
    );
    frame.views.add(view);
    return view;
  }
}
