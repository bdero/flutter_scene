import 'package:flutter_gpu/gpu.dart' as gpu;

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
    this.coordinateSystem = gpu.TextureCoordinateSystem.renderToTexture,
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
         storageMode:
             shaderReadable
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
  final gpu.TextureCoordinateSystem coordinateSystem;

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
      other.coordinateSystem == coordinateSystem &&
      other.debugName == debugName;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    format,
    sampleCount,
    storageMode,
    enableShaderReadUsage,
    coordinateSystem,
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
        coordinateSystem: descriptor.coordinateSystem,
      );
      ring[_frame] = texture;
    }
    return texture;
  }

  /// Drops all cached textures. The next [acquire] for any descriptor
  /// reallocates. Call when the output size changes so stale-sized
  /// textures aren't kept alive.
  void clear() => _rings.clear();
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

  final gpu.HostBuffer transientsBuffer;
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
/// passes. See `docs/renderer-roadmap.md`.
class RenderGraph {
  final List<RenderGraphPass> _passes = [];
  final Blackboard _blackboard = Blackboard();

  /// Appends [pass] to the end of the execution order.
  void addPass(RenderGraphPass pass) => _passes.add(pass);

  /// Runs every pass in order, using [transientsBuffer] for transient
  /// uniforms and [texturePool] for transient attachments. Each pass
  /// creates and submits its own command buffer. Clears the blackboard
  /// first so state never leaks between frames.
  void execute({
    required gpu.HostBuffer transientsBuffer,
    required TransientTexturePool texturePool,
  }) {
    _blackboard._clear();
    final context = RenderGraphContext(
      transientsBuffer: transientsBuffer,
      texturePool: texturePool,
      blackboard: _blackboard,
    );
    for (final pass in _passes) {
      pass.execute(context);
    }
  }
}
