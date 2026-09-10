import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/draw_recorder.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_profile.dart';
import 'package:flutter_scene/src/texture/texture_registry.dart'
    show gpuTextureBytes;
import 'package:flutter_scene/src/render/render_stats.dart';

/// A typed scratch store passed between [RenderPass]es within a single
/// frame.
///
/// Passes publish handles here (a depth target, the HDR scene color, a
/// shadow atlas, ...) and downstream passes look them up by key, so a
/// pass doesn't need a hard reference to the one that produced its input.
/// Cleared at the start of every frame.
class Blackboard {
  final Map<Object, Object?> _entries = {};

  /// Returns the entry stored under [key], or `null` if absent.
  T? get<T>(Object key) => _entries[key] as T?;

  /// Returns the entry stored under [key], throwing if it is absent or
  /// not a [T].
  T require<T>(Object key) {
    final value = _entries[key];
    if (value is! T) {
      throw StateError(
        'Blackboard has no "$key" entry of type $T '
        '(got ${value.runtimeType}).',
      );
    }
    return value;
  }

  /// Stores [value] under [key], replacing any previous entry.
  void set(Object key, Object? value) => _entries[key] = value;

  void _clear() => _entries.clear();
}

/// Observes one [RenderGraph.execute] run: pass boundaries with CPU times,
/// every blackboard read/write, and every transient-texture acquisition.
///
/// Attached only for capture frames (the render graph inspector); steady
/// state frames pay nothing. Reads and writes made while a pass executes
/// belong to that pass; acquisitions made while the graph is being built
/// (before execute) arrive with no current pass.
abstract interface class RenderGraphObserver {
  void onPassBegin(RenderGraphPass pass, int indexInGraph);
  void onPassEnd(RenderGraphPass pass, int elapsedMicros);
  void onBlackboardRead(Object key, Object? value);
  void onBlackboardWrite(Object key, Object? value);
  void onTextureAcquired(
    TransientTextureDescriptor descriptor,
    gpu.Texture texture,
  );
}

/// A [Blackboard] view that reports every access to an observer while
/// delegating storage to the wrapped board.
class _RecordingBlackboard extends Blackboard {
  _RecordingBlackboard(this._inner, this._observer);

  final Blackboard _inner;
  final RenderGraphObserver _observer;

  @override
  T? get<T>(Object key) {
    final value = _inner.get<T>(key);
    _observer.onBlackboardRead(key, value);
    return value;
  }

  @override
  T require<T>(Object key) {
    final value = _inner.require<T>(key);
    _observer.onBlackboardRead(key, value);
    return value;
  }

  @override
  void set(Object key, Object? value) {
    _inner.set(key, value);
    _observer.onBlackboardWrite(key, value);
  }
}

/// A [TransientWriter] view that reports every emplacement to a draw
/// recorder, so a capture can attribute uniform bytes to the draw that
/// follows them.
class _RecordingTransientWriter implements TransientWriter {
  _RecordingTransientWriter(this._inner, this._recorder);

  final TransientWriter _inner;
  final DrawRecorder _recorder;

  @override
  gpu.BufferView emplace(ByteData bytes) {
    _recorder.onUniformEmplaced(bytes);
    return _inner.emplace(bytes);
  }
}

/// A [TransientTexturePool] view that reports acquisitions to an observer
/// while delegating to the wrapped pool (which owns all texture state).
/// {@category Rendering}
class ObservedTexturePool extends TransientTexturePool {
  ObservedTexturePool(this._inner, this._observer)
    : super(framesInFlight: _inner.framesInFlight);

  final TransientTexturePool _inner;
  final RenderGraphObserver _observer;

  @override
  void beginFrame() => _inner.beginFrame();

  @override
  gpu.Texture acquire(TransientTextureDescriptor descriptor) {
    final texture = _inner.acquire(descriptor);
    _observer.onTextureAcquired(descriptor, texture);
    return texture;
  }

  @override
  void clear() => _inner.clear();

  @override
  int get residentBytes => _inner.residentBytes;
}

/// Description of a transient GPU texture requested from a
/// [TransientTexturePool].
///
/// Two descriptors that compare equal share a pool slot, so a pass that
/// needs two live textures with otherwise-identical parameters in the
/// same frame must distinguish them with [debugName], and a color target
/// that can be rendered with more than one depth setup must distinguish
/// them with [attachmentKey].
class TransientTextureDescriptor {
  const TransientTextureDescriptor({
    required this.width,
    required this.height,
    required this.format,
    this.sampleCount = 1,
    this.storageMode = gpu.StorageMode.devicePrivate,
    this.enableShaderReadUsage = true,
    this.debugName,
    this.attachmentKey,
  });

  /// A color render target at the given size/format with no MSAA.
  const TransientTextureDescriptor.color({
    required int width,
    required int height,
    required gpu.PixelFormat format,
    String? debugName,
    String? attachmentKey,
  }) : this(
         width: width,
         height: height,
         format: format,
         storageMode: gpu.StorageMode.devicePrivate,
         enableShaderReadUsage: true,
         debugName: debugName,
         attachmentKey: attachmentKey,
       );

  /// A depth/stencil attachment at the given size. Lives in transient
  /// (tile) memory and is not shader-readable by default.
  const TransientTextureDescriptor.depth({
    required int width,
    required int height,
    required gpu.PixelFormat format,
    bool shaderReadable = false,
    int sampleCount = 1,
    String? debugName,
  }) : this(
         width: width,
         height: height,
         format: format,
         sampleCount: sampleCount,
         storageMode: shaderReadable
             ? gpu.StorageMode.devicePrivate
             : gpu.StorageMode.deviceTransient,
         enableShaderReadUsage: shaderReadable,
         debugName: debugName,
       );

  final int width;
  final int height;
  final gpu.PixelFormat format;
  final int sampleCount;
  final gpu.StorageMode storageMode;
  final bool enableShaderReadUsage;

  /// Optional disambiguator so two otherwise-identical descriptors map to
  /// separate pool slots. Does not affect the allocated texture.
  final String? debugName;

  /// Names the depth/stencil setup a color target is rendered with, so a
  /// target that can be drawn with different depth attachments (or as an
  /// MSAA resolve target with none) gets a separate pool slot per setup.
  ///
  /// The GLES backend caches one framebuffer per color texture and attaches
  /// depth only when that framebuffer is first created, so reusing a texture
  /// with a different depth attachment silently renders with the old one
  /// (or with no depth test at all). Keeping each setup on its own texture
  /// sidesteps that on every backend at the cost of one extra ring per
  /// setup a view actually switches through. Must be stable across frames
  /// for a given configuration; a per-frame value defeats pooling.
  /// Does not affect the allocated texture.
  // TODO(gles-fbo-cache): drop once the pubspec Flutter floor carries the
  // engine fix that re-attaches depth/stencil when the cached FBO's
  // attachments differ from the requested ones.
  final String? attachmentKey;

  @override
  bool operator ==(Object other) =>
      other is TransientTextureDescriptor &&
      other.width == width &&
      other.height == height &&
      other.format == format &&
      other.sampleCount == sampleCount &&
      other.storageMode == storageMode &&
      other.enableShaderReadUsage == enableShaderReadUsage &&
      other.debugName == debugName &&
      other.attachmentKey == attachmentKey;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    format,
    sampleCount,
    storageMode,
    enableShaderReadUsage,
    debugName,
    attachmentKey,
  );
}

/// Recycles GPU textures used as transient render-graph attachments
/// across frames.
///
/// Keyed by [TransientTextureDescriptor]; for each descriptor it keeps a
/// ring of [framesInFlight] textures so a texture written this frame is
/// not overwritten while an earlier frame still references it. This is the
/// minimal "transient resource" mechanism — there is no intra-frame
/// lifetime aliasing; a pass that needs two simultaneously-live textures
/// of the same shape must give them distinct [TransientTextureDescriptor.debugName]s.
class TransientTexturePool {
  TransientTexturePool({this.framesInFlight = 2});

  final int framesInFlight;
  final Map<TransientTextureDescriptor, List<gpu.Texture?>> _rings = {};
  int _frame = 0;

  /// Advances to the next frame's ring slot. Call once per frame before
  /// any [acquire] calls.
  void beginFrame() {
    _frame = (_frame + 1) % framesInFlight;
  }

  /// Returns a texture matching [descriptor] from the pool for the
  /// current frame, allocating it on first use.
  gpu.Texture acquire(TransientTextureDescriptor descriptor) {
    final ring = _rings.putIfAbsent(
      descriptor,
      () => List<gpu.Texture?>.filled(framesInFlight, null),
    );
    var texture = ring[_frame];
    if (texture == null) {
      texture = gpu.gpuContext.createTexture(
        descriptor.storageMode,
        descriptor.width,
        descriptor.height,
        sampleCount: descriptor.sampleCount,
        format: descriptor.format,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: descriptor.enableShaderReadUsage,
      );
      ring[_frame] = texture;
    }
    return texture;
  }

  /// Drops all cached textures. The next [acquire] for any descriptor
  /// reallocates. Call when the output size changes so stale-sized
  /// textures aren't kept alive, or to give the memory back under pressure.
  ///
  /// Safe at any point in a frame, since a pass that has already acquired a
  /// texture holds its own reference and this releases only the pool's claim.
  void clear() => _rings.clear();

  /// Resident bytes of every texture the pool holds, summed across mip chains.
  int get residentBytes {
    var bytes = 0;
    for (final ring in _rings.values) {
      for (final texture in ring) {
        if (texture != null) bytes += gpuTextureBytes(texture);
      }
    }
    return bytes;
  }
}

/// Per-frame state handed to every [RenderGraphPass] when the graph
/// executes.
///
/// Carries the frame's transient-uniform allocator (shared by all
/// passes), the [TransientTexturePool], and the [Blackboard]. Each pass
/// creates and submits its own `gpu.CommandBuffer` — Flutter GPU's
/// `RenderPass` holds a live command encoder, so a command buffer can
/// host only one render pass at a time. Scene-specific inputs (camera,
/// scene root, lights, the final swapchain target) are supplied to
/// individual passes through their constructors rather than this generic
/// context.
class RenderGraphContext {
  RenderGraphContext({
    required this.transientsBuffer,
    required this.texturePool,
    required this.blackboard,
  });

  final TransientWriter transientsBuffer;
  final TransientTexturePool texturePool;
  final Blackboard blackboard;
}

/// A single unit of rendering work in a [RenderGraph].
///
/// Implementations create and submit a `gpu.CommandBuffer` (typically
/// hosting one `gpu.RenderPass` against some render target), reading
/// their inputs from and publishing their outputs to
/// [RenderGraphContext.blackboard]. Passes run in the order they were
/// added to the graph; there is no automatic reordering or culling, so
/// the code building the graph decides which passes to add.
///
/// Named `RenderGraphPass` rather than `RenderPass` to avoid colliding
/// with `gpu.RenderPass` from `package:flutter_gpu`.
abstract class RenderGraphPass {
  /// A short human-readable name, used for debugging and logging.
  String get name;

  /// Records and submits this pass's work, using [context] for transient
  /// uniforms / attachments and to read/publish cross-pass handles.
  void execute(RenderGraphContext context);
}

/// An ordered list of [RenderGraphPass]es executed once per frame.
///
/// This is the deliberately-minimal "render graph": passes are run in
/// insertion order, transient render targets come from a shared
/// [TransientTexturePool], and passes communicate through a per-frame
/// [Blackboard]. It does not insert GPU barriers (Flutter GPU handles
/// synchronization internally), alias transient memory, or cull unused
/// passes.
class RenderGraph {
  static final RenderProfileAccumulator _profile = RenderProfileAccumulator();

  final List<RenderGraphPass> _passes = [];
  final Blackboard _blackboard = Blackboard();

  /// Appends [pass] to the end of the execution order.
  void addPass(RenderGraphPass pass) => _passes.add(pass);

  /// Runs every pass in order, using [transientsBuffer] for transient
  /// uniforms and [texturePool] for transient attachments. Each pass
  /// creates and submits its own command buffer. Clears the blackboard
  /// first so state never leaks between frames.
  ///
  /// Every pass is stopwatched and its counter delta recorded into [stats]
  /// (when given), and emitted as a `dart:developer` timeline event when
  /// [RenderStats.timelineEvents] is on. With an [observer] attached (a
  /// capture frame), passes also run against a recording blackboard and
  /// boundaries are reported to it.
  void execute({
    required TransientWriter transientsBuffer,
    required TransientTexturePool texturePool,
    RenderGraphObserver? observer,
    RenderViewStats? stats,
  }) {
    _blackboard._clear();
    // An observer that also records draws gets the encoders' draw context
    // and every uniform emplacement for the frame.
    final recorder = observer is DrawRecorder ? observer as DrawRecorder : null;
    final context = RenderGraphContext(
      transientsBuffer: recorder == null
          ? transientsBuffer
          : _RecordingTransientWriter(transientsBuffer, recorder),
      texturePool: texturePool,
      blackboard: observer == null
          ? _blackboard
          : _RecordingBlackboard(_blackboard, observer),
    );
    final timeline = RenderStats.timelineEvents;
    final stopwatch = Stopwatch();
    for (var i = 0; i < _passes.length; i++) {
      final pass = _passes[i];
      final passStats = stats == null
          ? null
          : RenderPassStats(name: pass.name, indexInGraph: i);
      if (passStats != null) {
        stats!.passes.add(passStats);
        _passStart.copyFrom(activeRenderCounters);
      }
      observer?.onPassBegin(pass, i);
      if (recorder != null) {
        recorder.clearContext();
        activeDrawRecorder = recorder;
      }
      if (timeline) developer.Timeline.startSync(pass.name);
      stopwatch
        ..reset()
        ..start();
      try {
        pass.execute(context);
      } finally {
        activeDrawRecorder = null;
      }
      stopwatch.stop();
      if (timeline) developer.Timeline.finishSync();
      final elapsed = stopwatch.elapsedMicroseconds;
      // Settle the counters before the observer runs, since a capture copies
      // textures at the pass boundary and those draws are not the pass's.
      if (passStats != null) {
        passStats.cpuMicros = elapsed;
        passStats.counters.setDelta(_passStart, activeRenderCounters);
      }
      observer?.onPassEnd(pass, elapsed);
      if (profileRendering) {
        _profile.add(pass.name, elapsed, trackMax: true);
      }
    }
    if (profileRendering) {
      final snapshot = _profile.endSample();
      if (snapshot == null) return;
      final entries = snapshot.totals.keys.toList()
        ..sort((a, b) => snapshot.totals[b]!.compareTo(snapshot.totals[a]!));
      final summary = entries
          .map(
            (name) =>
                '${name}_mean_us=${snapshot.mean(name)} '
                '${name}_max_us=${snapshot.max(name)}',
          )
          .join(' ');
      // ignore: avoid_print
      print('FLUTTER_SCENE_PROFILE $summary');
    }
  }

  static final RenderCounters _passStart = RenderCounters();
}
