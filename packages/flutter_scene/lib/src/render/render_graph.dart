import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_profile.dart';
import 'package:flutter_scene/src/texture/texture_registry.dart'
    show gpuTextureBytes;

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

/// A [TransientTexturePool] view that reports acquisitions to an observer
/// while delegating to the wrapped pool (which owns all texture state).
/// {@category Rendering}
class ObservedTexturePool extends TransientTexturePool {
  ObservedTexturePool(this._inner, this._observer)
    : super._delegating(framesInFlight: _inner.framesInFlight);

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
/// same frame must distinguish them with [debugName].
class TransientTextureDescriptor {
  const TransientTextureDescriptor({
    required this.width,
    required this.height,
    required this.format,
    this.sampleCount = 1,
    this.storageMode = gpu.StorageMode.devicePrivate,
    this.enableShaderReadUsage = true,
    this.debugName,
  });

  /// A color render target at the given size/format with no MSAA.
  const TransientTextureDescriptor.color({
    required int width,
    required int height,
    required gpu.PixelFormat format,
    String? debugName,
  }) : this(
         width: width,
         height: height,
         format: format,
         storageMode: gpu.StorageMode.devicePrivate,
         enableShaderReadUsage: true,
         debugName: debugName,
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

  @override
  bool operator ==(Object other) =>
      other is TransientTextureDescriptor &&
      other.width == width &&
      other.height == height &&
      other.format == format &&
      other.sampleCount == sampleCount &&
      other.storageMode == storageMode &&
      other.enableShaderReadUsage == enableShaderReadUsage &&
      other.debugName == debugName;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    format,
    sampleCount,
    storageMode,
    enableShaderReadUsage,
    debugName,
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
  TransientTexturePool({this.framesInFlight = 2}) {
    // Swept on construction as well as on every walk, so a program that
    // churns through scenes does not grow the list between sheds.
    if (_live.length >= _sweepThreshold) {
      _live.removeWhere((ref) => ref.target == null);
    }
    _live.add(WeakReference<TransientTexturePool>(this));
  }

  /// For a pool that owns no rings and forwards everything to another pool.
  ///
  /// It stays out of [_live]: the pool it wraps is registered already, and
  /// counting or clearing through both would report the same textures twice.
  TransientTexturePool._delegating({required this.framesInFlight});

  static const int _sweepThreshold = 16;

  /// Every pool that owns rings, weakly.
  ///
  /// Pools outlive nothing in particular: a [Surface] view owns one, a
  /// [Scene] owns one for probe capture and one per planar reflection group,
  /// and none of those have a disposal hook. Strong references here would
  /// pin a discarded scene's attachments for the life of the process, which
  /// is the leak this exists to fix.
  static final List<WeakReference<TransientTexturePool>> _live = [];

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
  /// textures aren't kept alive, or to hand the memory back under pressure.
  ///
  /// Safe at any point in a frame. A pass that has already acquired a
  /// texture holds its own reference to it, so this drops only the pool's
  /// claim; the pass finishes drawing into the texture it was given and the
  /// next frame allocates a fresh one.
  void clear() => _rings.clear();

  /// Resident bytes of every texture this pool holds, summed across mip
  /// chains.
  int get residentBytes {
    var bytes = 0;
    for (final ring in _rings.values) {
      for (final texture in ring) {
        if (texture != null) bytes += gpuTextureBytes(texture);
      }
    }
    return bytes;
  }

  /// Resident bytes held by every live pool.
  static int get liveResidentBytes {
    var bytes = 0;
    _forEachLive((pool) => bytes += pool.residentBytes);
    return bytes;
  }

  /// How many pools a shed would reach.
  static int get liveCount {
    var count = 0;
    _forEachLive((_) => count++);
    return count;
  }

  /// Clears every live pool and returns the bytes released.
  static int shedLive() {
    var bytes = 0;
    _forEachLive((pool) {
      bytes += pool.residentBytes;
      pool.clear();
    });
    return bytes;
  }

  /// Visits every pool still alive, dropping references to collected ones on
  /// the way through.
  ///
  /// [visit] must not construct a pool: the list is being mutated as it is
  /// walked, and registering one mid-walk would throw. Nothing that calls
  /// this allocates.
  static void _forEachLive(void Function(TransientTexturePool pool) visit) {
    _live.removeWhere((ref) {
      final pool = ref.target;
      if (pool == null) return true;
      visit(pool);
      return false;
    });
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
  /// With an [observer] attached (a capture frame), passes run against a
  /// recording blackboard, each pass is stopwatched, and boundaries are
  /// reported; without one the steady-state path is unchanged.
  void execute({
    required TransientWriter transientsBuffer,
    required TransientTexturePool texturePool,
    RenderGraphObserver? observer,
  }) {
    _blackboard._clear();
    final context = RenderGraphContext(
      transientsBuffer: transientsBuffer,
      texturePool: texturePool,
      blackboard: observer == null
          ? _blackboard
          : _RecordingBlackboard(_blackboard, observer),
    );
    if (observer != null) {
      for (var i = 0; i < _passes.length; i++) {
        final pass = _passes[i];
        observer.onPassBegin(pass, i);
        final stopwatch = Stopwatch()..start();
        pass.execute(context);
        stopwatch.stop();
        observer.onPassEnd(pass, stopwatch.elapsedMicroseconds);
      }
      return;
    }
    for (final pass in _passes) {
      if (!profileRendering) {
        pass.execute(context);
        continue;
      }
      final stopwatch = Stopwatch()..start();
      pass.execute(context);
      stopwatch.stop();
      _profile.add(pass.name, stopwatch.elapsedMicroseconds, trackMax: true);
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
}
