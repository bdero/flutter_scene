/// Single-frame render graph capture: an observer that records the pass
/// list, blackboard data flow, per-pass CPU times, and (optionally) GPU
/// snapshots of every texture each pass wrote, copied at pass boundaries so
/// transient reuse cannot overwrite them.
///
/// Armed by `Scene.captureRenderGraph` for exactly one frame; steady-state
/// frames never construct any of this.
library;

import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';

/// The process-wide opt-in for render graph debugging (capture and the
/// custom-pass blackboard peek). Off by default so shipping apps tree-shake
/// the debug branches; `Scene.debugAllowRenderGraphCapture` proxies this.
/// {@category Rendering}
abstract final class RenderGraphDebug {
  static bool enabled = false;
}

/// What a capture collects. Metadata (passes, data flow, timings) is always
/// recorded; images are opt-in and can be restricted to thumbnails or to a
/// set of resource keys, since a full-resolution capture of every target
/// can exceed 150 MB at display sizes.
/// {@category Rendering}
class RenderGraphCaptureRequest {
  const RenderGraphCaptureRequest({
    this.captureImages = true,
    this.thumbnailMaxDim = 256,
    this.fullResolution = false,
    this.onlyKeys,
  });

  /// Whether to copy any texture contents at all.
  final bool captureImages;

  /// Longest thumbnail edge in pixels, or null for no thumbnails.
  final int? thumbnailMaxDim;

  /// Whether to keep full-resolution snapshots (same pixel format as the
  /// source) in addition to thumbnails.
  final bool fullResolution;

  /// When set, image capture is restricted to these resource keys
  /// (blackboard keys or transient debug names); metadata still covers
  /// everything.
  final Set<String>? onlyKeys;
}

/// One resource observed during the capture frame: a texture written by a
/// pass (under a blackboard key or a transient debug name), or a non-texture
/// blackboard entry (packed uniform data).
/// {@category Rendering}
class CapturedResource {
  CapturedResource({
    required this.key,
    required this.passIndex,
    this.debugName,
    this.width = 0,
    this.height = 0,
    this.format,
    this.sampleCount = 1,
    this.storageMode,
    this.isTexture = true,
    this.byteLength,
    this.snapshot,
    this.thumbnail,
    this.snapshotFailed = false,
  });

  /// The blackboard key or `internal:<debugName>` for unpublished targets.
  final String key;

  /// Index of the pass that wrote this content, or -1 for textures acquired
  /// while the graph was being built.
  final int passIndex;

  /// The transient descriptor's debug name, when pool-allocated.
  final String? debugName;

  final int width;
  final int height;
  final gpu.PixelFormat? format;
  final int sampleCount;

  /// The texture's storage mode (null only for non-texture entries).
  final gpu.StorageMode? storageMode;

  /// False for non-texture blackboard entries (see [byteLength]).
  final bool isTexture;

  /// For ByteData blackboard entries, the packed length.
  final int? byteLength;

  /// Full-resolution copy in the source format, when requested and
  /// shader-readable.
  gpu.Texture? snapshot;

  /// Reduced copy in the source format, when requested.
  gpu.Texture? thumbnail;

  /// Whether an attempted copy failed (an unreadable or unrenderable
  /// format); metadata is still valid.
  bool snapshotFailed;

  /// Whether this resource cannot carry image content (transient tile
  /// memory or non-shader-readable).
  bool get shaderReadable =>
      isTexture &&
      storageMode != gpu.StorageMode.deviceTransient &&
      !snapshotFailed;
}

/// One executed pass: identity, CPU time, and the blackboard keys it read
/// and wrote, in observation order.
/// {@category Rendering}
class CapturedPass {
  CapturedPass({required this.name, required this.indexInGraph});

  final String name;
  final int indexInGraph;
  int cpuMicros = 0;
  final List<String> reads = [];
  final List<String> writes = [];
}

/// The product of one captured frame.
/// {@category Rendering}
class RenderGraphCaptureResult {
  RenderGraphCaptureResult({
    required this.passes,
    required this.resources,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final List<CapturedPass> passes;

  /// Every observed resource, in write order (build-time acquisitions
  /// first). A key rewritten by a later pass appears once per write, each
  /// entry carrying that write's snapshot.
  final List<CapturedResource> resources;

  /// The captured view's render size in physical pixels.
  final int pixelWidth;
  final int pixelHeight;

  /// The latest write of [key] at or before [passIndex], or null.
  CapturedResource? resourceAt(String key, int passIndex) {
    CapturedResource? best;
    for (final resource in resources) {
      if (resource.key != key) continue;
      if (resource.passIndex > passIndex) continue;
      if (best == null || resource.passIndex > best.passIndex) best = resource;
    }
    return best;
  }
}

/// The observer that performs a capture: records the graph and copies
/// written textures at pass boundaries.
/// {@category Rendering}
class RenderGraphCapturer implements RenderGraphObserver {
  RenderGraphCapturer({required this.request});

  final RenderGraphCaptureRequest request;

  final List<CapturedPass> _passes = [];
  final List<CapturedResource> _resources = [];
  final Map<gpu.Texture, TransientTextureDescriptor> _descriptors = {};
  // Written this pass: insertion-ordered key -> texture (or data).
  final Map<String, Object?> _pendingWrites = {};
  // Acquired this pass but (not yet) published to the blackboard.
  final List<gpu.Texture> _pendingAcquires = [];
  CapturedPass? _current;

  /// Finishes the capture over the executed graph.
  RenderGraphCaptureResult finish({
    required int pixelWidth,
    required int pixelHeight,
  }) => RenderGraphCaptureResult(
    passes: _passes,
    resources: _resources,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
  );

  @override
  void onPassBegin(RenderGraphPass pass, int indexInGraph) {
    _current = CapturedPass(name: pass.name, indexInGraph: indexInGraph);
    _passes.add(_current!);
    _pendingWrites.clear();
    _pendingAcquires.clear();
  }

  @override
  void onPassEnd(RenderGraphPass pass, int elapsedMicros) {
    final current = _current;
    if (current == null) return;
    current.cpuMicros = elapsedMicros;
    final published = <gpu.Texture>{};
    for (final entry in _pendingWrites.entries) {
      final value = entry.value;
      if (value is gpu.Texture) {
        published.add(value);
        _recordTexture(entry.key, value, current.indexInGraph);
      } else if (value is ByteData) {
        _resources.add(
          CapturedResource(
            key: entry.key,
            passIndex: current.indexInGraph,
            isTexture: false,
            byteLength: value.lengthInBytes,
          ),
        );
      }
    }
    // Internal targets the pass acquired but never published (bloom mips,
    // depth-of-field stages) still carry content worth showing.
    for (final texture in _pendingAcquires) {
      if (published.contains(texture)) continue;
      final debugName = _descriptors[texture]?.debugName;
      _recordTexture(
        'internal:${debugName ?? 'texture'}',
        texture,
        current.indexInGraph,
      );
    }
    _pendingWrites.clear();
    _pendingAcquires.clear();
    _current = null;
  }

  @override
  void onBlackboardRead(Object key, Object? value) {
    final current = _current;
    if (current == null || value == null) return;
    final name = key.toString();
    if (!current.reads.contains(name)) current.reads.add(name);
  }

  @override
  void onBlackboardWrite(Object key, Object? value) {
    final current = _current;
    if (current == null) return;
    final name = key.toString();
    if (!current.writes.contains(name)) current.writes.add(name);
    _pendingWrites[name] = value;
  }

  @override
  void onTextureAcquired(
    TransientTextureDescriptor descriptor,
    gpu.Texture texture,
  ) {
    _descriptors[texture] = descriptor;
    if (_current == null) {
      // Build-time acquisition (a display step or custom-pass destination):
      // metadata only; the writing pass snapshots the content later.
      _resources.add(_metadataOnly(descriptor));
      return;
    }
    if (!_pendingAcquires.contains(texture)) _pendingAcquires.add(texture);
  }

  CapturedResource _metadataOnly(TransientTextureDescriptor descriptor) =>
      CapturedResource(
        key: 'internal:${descriptor.debugName ?? 'texture'}',
        passIndex: -1,
        debugName: descriptor.debugName,
        width: descriptor.width,
        height: descriptor.height,
        format: descriptor.format,
        sampleCount: descriptor.sampleCount,
        storageMode: descriptor.storageMode,
      );

  void _recordTexture(String key, gpu.Texture texture, int passIndex) {
    final descriptor = _descriptors[texture];
    final resource = CapturedResource(
      key: key,
      passIndex: passIndex,
      debugName: descriptor?.debugName,
      width: texture.width,
      height: texture.height,
      format: texture.format,
      sampleCount: texture.sampleCount,
      storageMode: texture.storageMode,
    );
    _resources.add(resource);
    if (!request.captureImages) return;
    final only = request.onlyKeys;
    if (only != null && !only.contains(key)) return;
    // The texture's own properties gate the copy, so descriptor-less
    // textures (retained or swapchain-backed) get the same protection as
    // pool transients. Submit-time failures are asynchronous and cannot be
    // caught here; this keeps the blit from ever being recorded against a
    // source it cannot sample.
    if (texture.storageMode == gpu.StorageMode.deviceTransient ||
        !texture.enableShaderReadUsage ||
        texture.sampleCount > 1) {
      resource.snapshotFailed = true;
      return;
    }
    try {
      final thumbnailDim = request.thumbnailMaxDim;
      if (thumbnailDim != null) {
        resource.thumbnail = _copy(texture, maxDim: thumbnailDim);
      }
      if (request.fullResolution) {
        resource.snapshot = _copy(texture, maxDim: null);
      }
    } catch (_) {
      // An unreadable or unrenderable source degrades to metadata.
      resource.snapshotFailed = true;
      resource.snapshot = null;
      resource.thumbnail = null;
    }
  }

  static final gpu.Shader _vertex = baseShaderLibrary['FullscreenVertex']!;
  static final gpu.Shader _copyFragment = baseShaderLibrary['CopyFragment']!;

  static final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext
      .createDeviceBufferWithCopy(
        ByteData.sublistView(
          Float32List.fromList(<double>[
            -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
            -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
          ]),
        ),
      );
  static final gpu.BufferView _quadView = gpu.BufferView(
    _quadBuffer,
    offsetInBytes: 0,
    lengthInBytes: 6 * 2 * 4,
  );

  // fp32 sources filter nearest everywhere (float32 linear filtering is an
  // optional GL extension), so their downscaled thumbnails point-sample.
  static gpu.SamplerOptions _samplerFor(gpu.PixelFormat format) {
    final nearest =
        format == gpu.PixelFormat.r32g32b32a32Float ||
        format == gpu.PixelFormat.r32Float;
    final filter = nearest ? gpu.MinMagFilter.nearest : gpu.MinMagFilter.linear;
    return gpu.SamplerOptions(
      minFilter: filter,
      magFilter: filter,
      widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    );
  }

  /// Copies [source] into a fresh shader-readable texture of the same
  /// format, at full size or scaled down so the longest edge is [maxDim].
  gpu.Texture _copy(gpu.Texture source, {required int? maxDim}) {
    var width = source.width;
    var height = source.height;
    if (maxDim != null && (width > maxDim || height > maxDim)) {
      final scale = maxDim / (width > height ? width : height);
      width = (width * scale).round().clamp(1, source.width);
      height = (height * scale).round().clamp(1, source.height);
    }
    final copy = gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      width,
      height,
      format: source.format,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: copy)),
    );
    renderPass.bindPipeline(resolvePipeline(_vertex, _copyFragment));
    renderPass.setDepthWriteEnable(false);
    renderPass.setDepthCompareOperation(gpu.CompareFunction.always);
    renderPass.setColorBlendEnable(false);
    renderPass.setCullMode(gpu.CullMode.none);
    bindVertexBufferCompat(renderPass, _quadView, 6);
    renderPass.bindTexture(
      _copyFragment.getUniformSlot('source_texture'),
      source,
      sampler: _samplerFor(source.format),
    );
    drawCompat(renderPass, 6);
    rendererSubmissions.submit(commandBuffer);
    return copy;
  }
}
