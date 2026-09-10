/// Single-frame render graph capture: an observer that records the pass
/// list, blackboard data flow, per-pass CPU times, and (optionally) GPU
/// snapshots of every texture each pass wrote, copied at pass boundaries so
/// transient reuse cannot overwrite them.
///
/// Armed by `Scene.captureRenderGraph` for exactly one frame; steady-state
/// frames never construct any of this.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/fmat/material_registry.dart'
    show fmatSourcePathOf;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render/draw_recorder.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/render/render_scene.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shader_reflection/shader_reflection.dart';
import 'package:flutter_scene/src/shaders.dart';

/// The process-wide opt-in for render graph debugging (capture and the
/// custom-pass blackboard peek). Off by default so shipping apps tree-shake
/// the debug branches; `Scene.debugAllowRenderGraphCapture` proxies this.
/// {@category Debugging and profiling}
abstract final class RenderGraphDebug {
  static bool enabled = false;
}

/// What a capture collects. Metadata (passes, data flow, timings) is always
/// recorded; images are opt-in and can be restricted to thumbnails or to a
/// set of resource keys, since a full-resolution capture of every target
/// can exceed 150 MB at display sizes.
/// {@category Debugging and profiling}
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
/// {@category Debugging and profiling}
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
    this.thumbnailPng,
  });

  /// Rebuilds a resource from [toJson] output. Textures are not restored;
  /// a serialized thumbnail comes back as [thumbnailPng].
  factory CapturedResource.fromJson(Map<String, Object?> json) {
    final png = json['thumbnailPng'];
    return CapturedResource(
      key: json['key'] as String,
      passIndex: json['pass'] as int,
      debugName: json['debugName'] as String?,
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      format: _enumByName(gpu.PixelFormat.values, json['format']),
      sampleCount: json['sampleCount'] as int? ?? 1,
      storageMode: _enumByName(gpu.StorageMode.values, json['storageMode']),
      isTexture: json['isTexture'] as bool? ?? true,
      byteLength: json['byteLength'] as int?,
      snapshotFailed: json['snapshotFailed'] as bool? ?? false,
      thumbnailPng: png is String ? base64Decode(png) : null,
    );
  }

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

  /// The thumbnail as PNG bytes, set when a capture was serialized with
  /// images or loaded from one.
  Uint8List? thumbnailPng;

  /// Metadata, plus the thumbnail as base64 PNG when [includePng] and one is
  /// held (see [encodeThumbnailPng]).
  Map<String, Object?> toJson({bool includePng = true}) => {
    'key': key,
    'pass': passIndex,
    if (debugName != null) 'debugName': debugName,
    'width': width,
    'height': height,
    if (format != null) 'format': format!.name,
    'sampleCount': sampleCount,
    if (storageMode != null) 'storageMode': storageMode!.name,
    'isTexture': isTexture,
    if (byteLength != null) 'byteLength': byteLength,
    'snapshotFailed': snapshotFailed,
    if (includePng && thumbnailPng != null)
      'thumbnailPng': base64Encode(thumbnailPng!),
  };

  /// Reads [thumbnail] back as PNG into [thumbnailPng]. False when there is
  /// no thumbnail or the readback failed (a format the display path cannot
  /// present).
  Future<bool> encodeThumbnailPng() async {
    if (thumbnailPng != null) return true;
    final texture = thumbnail;
    if (texture == null) return false;
    try {
      final image = texture.asImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return false;
      thumbnailPng = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether this resource cannot carry image content (transient tile
  /// memory or non-shader-readable).
  bool get shaderReadable =>
      isTexture &&
      storageMode != gpu.StorageMode.deviceTransient &&
      !snapshotFailed;
}

/// One uniform block emplaced for a draw: the packed bytes, resolved to a
/// declared block of the draw's shaders by size when that is unambiguous.
/// {@category Debugging and profiling}
class CapturedUniformBlock {
  CapturedUniformBlock(this.bytes, {this.resolvedName, this.resolvedValues});

  /// Rebuilds a block from [toJson] output, keeping the name and values it
  /// was serialized with (a loaded capture has no shaders to resolve
  /// against).
  factory CapturedUniformBlock.fromJson(Map<String, Object?> json) {
    final raw = json['data'];
    final bytes = raw is String ? base64Decode(raw) : Uint8List(0);
    final values = json['values'];
    return CapturedUniformBlock(
      ByteData.sublistView(bytes),
      resolvedName: json['name'] as String?,
      resolvedValues: values is List
          ? [
              for (final value in values.cast<Map>())
                (
                  name: value['name'] as String,
                  type: value['type'] as String,
                  values: (value['values'] as List).cast<num>(),
                ),
            ]
          : null,
    );
  }

  /// A copy of the packed bytes.
  final ByteData bytes;

  /// The name a serialized capture resolved this block to, when loaded.
  final String? resolvedName;

  /// The values a serialized capture decoded, when loaded.
  final List<({String name, String type, List<num> values})>? resolvedValues;

  int get byteLength => bytes.lengthInBytes;

  /// Declared blocks of the draw's shaders this buffer can be (see
  /// [matchUniformBlocks]), resolved against loaded reflection. One entry
  /// means [decode] can name it.
  List<ShaderUniformBlockInfo> candidatesFor(CapturedDraw draw) {
    final index = draw.uniformBlocks.indexOf(this);
    if (index < 0) return const [];
    return draw._matchedBlocks()[index];
  }

  /// The block's name when exactly one declared block matches (or the name
  /// it was serialized with), else null.
  String? nameFor(CapturedDraw draw) {
    if (resolvedName != null) return resolvedName;
    final candidates = candidatesFor(draw);
    return candidates.length == 1 ? candidates.single.name : null;
  }

  /// The decoded members when exactly one declared block matches, else
  /// null. Needs the shaders' bundle reflection loaded (see
  /// [ShaderReflection.loadBundleInfo]).
  List<ShaderUniformValue>? decode(CapturedDraw draw) {
    final candidates = candidatesFor(draw);
    if (candidates.length != 1) return null;
    return decodeUniformBlock(candidates.single, bytes);
  }

  /// Metadata plus the decoded members when resolvable; [includeBytes] adds
  /// the packed bytes as base64 so a loaded capture can still show them.
  Map<String, Object?> toJson(CapturedDraw draw, {bool includeBytes = false}) {
    final name = nameFor(draw);
    final decoded = resolvedValues != null
        ? [
            for (final value in resolvedValues!)
              {'name': value.name, 'type': value.type, 'values': value.values},
          ]
        : decode(draw)?.map((v) => v.toJson()).toList();
    return {
      'bytes': byteLength,
      if (name != null) 'name': name,
      if (decoded != null) 'values': decoded,
      if (name == null)
        'candidates': [for (final c in candidatesFor(draw)) c.name],
      if (includeBytes)
        'data': base64Encode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
    };
  }
}

/// One draw call issued during a captured pass, with what the encoder knew
/// about it and the uniform bytes emplaced since the previous draw.
/// {@category Debugging and profiling}
class CapturedDraw {
  CapturedDraw({
    required this.passIndex,
    required this.order,
    required this.phase,
    required this.vertexCount,
    required this.instanceCount,
    required this.indexed,
    required this.batchedItems,
    required this.batchBreak,
    required this.uniformBlocks,
    this.nodePath,
    this.materialType,
    this.materialSource,
    this.vertexShader,
    this.fragmentShader,
    this.pipelineId,
    this.geometryType,
    String? vertexShaderName,
    String? fragmentShaderName,
  }) : _vertexShaderName = vertexShaderName,
       _fragmentShaderName = fragmentShaderName;

  /// Rebuilds a draw from [toJson] output. Shader objects are not restored;
  /// their names are.
  factory CapturedDraw.fromJson(Map<String, Object?> json) => CapturedDraw(
    passIndex: json['pass'] as int,
    order: json['order'] as int,
    phase: _enumByName(DrawPhase.values, json['phase']) ?? DrawPhase.other,
    vertexCount: json['vertexCount'] as int,
    instanceCount: json['instanceCount'] as int,
    indexed: json['indexed'] as bool? ?? false,
    batchedItems: json['batchedItems'] as int? ?? 1,
    batchBreak:
        _enumByName(BatchBreakReason.values, json['batchBreak']) ??
        BatchBreakReason.none,
    uniformBlocks: [
      for (final block in (json['uniformBlocks'] as List? ?? const []))
        CapturedUniformBlock.fromJson((block as Map).cast<String, Object?>()),
    ],
    nodePath: json['node'] as String?,
    materialType: json['material'] as String?,
    materialSource: json['materialSource'] as String?,
    geometryType: json['geometry'] as String?,
    pipelineId: json['pipeline'] as int?,
    vertexShaderName: json['vertexShader'] as String?,
    fragmentShaderName: json['fragmentShader'] as String?,
  );

  final int passIndex;

  /// Position among the pass's draws, from zero.
  final int order;
  final DrawPhase phase;

  /// Vertices (or indices, when [indexed]) per instance.
  final int vertexCount;
  final int instanceCount;
  final bool indexed;

  /// Scene nodes merged into this draw, or 1.
  final int batchedItems;

  /// Why the opaque run this draw ended did not continue.
  final BatchBreakReason batchBreak;

  /// Uniform blocks emplaced between the previous draw and this one, in
  /// emplacement order. Bindings the encoder kept from an earlier draw do
  /// not reappear.
  final List<CapturedUniformBlock> uniformBlocks;

  /// Slash-joined node names from the scene root, when a node drew.
  final String? nodePath;
  final String? materialType;

  /// The `.fmat` path for a preprocessed material.
  final String? materialSource;
  final String? geometryType;
  final gpu.Shader? vertexShader;
  final gpu.Shader? fragmentShader;

  /// Identity of the bound pipeline, shared by draws that used the same
  /// one.
  final int? pipelineId;

  final String? _vertexShaderName;
  final String? _fragmentShaderName;

  /// The vertex shader's bundle entry name, once its bundle reflection has
  /// loaded (or as serialized).
  String? get vertexShaderName =>
      _vertexShaderName ??
      (vertexShader == null ? null : ShaderReflection.nameOf(vertexShader!));

  String? get fragmentShaderName =>
      _fragmentShaderName ??
      (fragmentShader == null
          ? null
          : ShaderReflection.nameOf(fragmentShader!));

  /// Triangles this draw rasterizes, assuming a triangle list.
  int get triangles => vertexCount ~/ 3 * instanceCount;

  // Candidate blocks per emplaced buffer, matched together so an exact
  // match can rule a block out for the shorter buffers.
  List<List<ShaderUniformBlockInfo>> _matchedBlocks() {
    final declared = <ShaderUniformBlockInfo>[];
    for (final shader in [vertexShader, fragmentShader]) {
      if (shader == null) continue;
      final info = ShaderReflection.infoFor(shader)?.current;
      if (info == null) continue;
      for (final block in info.uniformBlocks) {
        if (!declared.contains(block)) declared.add(block);
      }
    }
    return matchUniformBlocks(declared, [
      for (final block in uniformBlocks) block.byteLength,
    ]);
  }

  /// [includeUniformBytes] adds each block's packed bytes, so a loaded
  /// capture keeps them.
  Map<String, Object?> toJson({bool includeUniformBytes = false}) => {
    'pass': passIndex,
    'order': order,
    'phase': phase.name,
    if (nodePath != null) 'node': nodePath,
    if (materialType != null) 'material': materialType,
    if (materialSource != null) 'materialSource': materialSource,
    if (geometryType != null) 'geometry': geometryType,
    if (vertexShaderName != null) 'vertexShader': vertexShaderName,
    if (fragmentShaderName != null) 'fragmentShader': fragmentShaderName,
    if (pipelineId != null) 'pipeline': pipelineId,
    'vertexCount': vertexCount,
    'instanceCount': instanceCount,
    'indexed': indexed,
    'batchedItems': batchedItems,
    'batchBreak': batchBreak.name,
    'uniformBlocks': [
      for (final block in uniformBlocks)
        block.toJson(this, includeBytes: includeUniformBytes),
    ],
  };
}

/// A submitted item that did not draw in a captured pass.
/// {@category Debugging and profiling}
class CapturedSkip {
  const CapturedSkip({required this.reason, this.nodePath});

  factory CapturedSkip.fromJson(Map<String, Object?> json) => CapturedSkip(
    reason:
        _enumByName(DrawSkipReason.values, json['reason']) ??
        DrawSkipReason.frustumCulled,
    nodePath: json['node'] as String?,
  );

  final DrawSkipReason reason;
  final String? nodePath;

  Map<String, Object?> toJson() => {
    'reason': reason.name,
    if (nodePath != null) 'node': nodePath,
  };
}

/// One executed pass: identity, CPU time, the blackboard keys it read and
/// wrote in observation order, and its draws and skipped items.
/// {@category Debugging and profiling}
class CapturedPass {
  CapturedPass({required this.name, required this.indexInGraph});

  final String name;
  final int indexInGraph;
  int cpuMicros = 0;
  final List<String> reads = [];
  final List<String> writes = [];
  final List<CapturedDraw> draws = [];
  final List<CapturedSkip> skips = [];

  factory CapturedPass.fromJson(Map<String, Object?> json) {
    final pass = CapturedPass(
      name: json['name'] as String,
      indexInGraph: json['index'] as int,
    )..cpuMicros = json['cpuMicros'] as int? ?? 0;
    pass.reads.addAll((json['reads'] as List? ?? const []).cast<String>());
    pass.writes.addAll((json['writes'] as List? ?? const []).cast<String>());
    for (final draw in json['draws'] as List? ?? const []) {
      pass.draws.add(CapturedDraw.fromJson((draw as Map).cast()));
    }
    for (final skip in json['skips'] as List? ?? const []) {
      pass.skips.add(CapturedSkip.fromJson((skip as Map).cast()));
    }
    return pass;
  }

  Map<String, Object?> toJson({bool includeUniformBytes = false}) => {
    'name': name,
    'index': indexInGraph,
    'cpuMicros': cpuMicros,
    'reads': reads,
    'writes': writes,
    'draws': [
      for (final draw in draws)
        draw.toJson(includeUniformBytes: includeUniformBytes),
    ],
    'skips': [for (final skip in skips) skip.toJson()],
  };
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// The product of one captured frame.
/// {@category Debugging and profiling}
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

  /// Every draw of the frame, in execution order.
  Iterable<CapturedDraw> get draws sync* {
    for (final pass in passes) {
      yield* pass.draws;
    }
  }

  /// Rebuilds a capture from [toJson] output. GPU textures are not restored;
  /// thumbnails serialized with images come back as
  /// [CapturedResource.thumbnailPng], and shader names and decoded uniforms
  /// keep what they were serialized with.
  factory RenderGraphCaptureResult.fromJson(Map<String, Object?> json) =>
      RenderGraphCaptureResult(
        passes: [
          for (final pass in json['passes'] as List? ?? const [])
            CapturedPass.fromJson((pass as Map).cast()),
        ],
        resources: [
          for (final resource in json['resources'] as List? ?? const [])
            CapturedResource.fromJson((resource as Map).cast()),
        ],
        pixelWidth: json['pixelWidth'] as int? ?? 0,
        pixelHeight: json['pixelHeight'] as int? ?? 0,
      );

  /// Parses [toJsonString] output.
  factory RenderGraphCaptureResult.fromJsonString(String source) =>
      RenderGraphCaptureResult.fromJson(
        (jsonDecode(source) as Map).cast<String, Object?>(),
      );

  /// Serializes the capture. With [includeImages], every thumbnail is read
  /// back as PNG first (asynchronous), and with [includeUniformBytes] each
  /// draw keeps its packed uniform bytes. The result round-trips through
  /// [RenderGraphCaptureResult.fromJson], so a capture can be attached to a
  /// bug report and opened elsewhere.
  Future<Map<String, Object?>> toJson({
    bool includeImages = true,
    bool includeUniformBytes = false,
  }) async {
    if (includeImages) {
      for (final resource in resources) {
        await resource.encodeThumbnailPng();
      }
    }
    return {
      'version': 1,
      'pixelWidth': pixelWidth,
      'pixelHeight': pixelHeight,
      'passes': [
        for (final pass in passes)
          pass.toJson(includeUniformBytes: includeUniformBytes),
      ],
      'resources': [
        for (final resource in resources)
          resource.toJson(includePng: includeImages),
      ],
    };
  }

  /// [toJson] as a JSON string.
  Future<String> toJsonString({
    bool includeImages = true,
    bool includeUniformBytes = false,
  }) async => jsonEncode(
    await toJson(
      includeImages: includeImages,
      includeUniformBytes: includeUniformBytes,
    ),
  );

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
/// {@category Debugging and profiling}
class RenderGraphCapturer implements RenderGraphObserver, DrawRecorder {
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
  DrawContext? _drawContext;
  final List<CapturedUniformBlock> _pendingUniforms = [];

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
    _drawContext = null;
    _pendingUniforms.clear();
  }

  @override
  void setContext(DrawContext context) => _drawContext = context;

  @override
  void clearContext() => _drawContext = null;

  @override
  void onUniformEmplaced(ByteData bytes) {
    if (_current == null) return;
    // The encoders reuse scratch buffers across draws, so keep a copy.
    final copy = Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    _pendingUniforms.add(CapturedUniformBlock(ByteData.sublistView(copy)));
  }

  @override
  void onDraw(int vertexCount, int instanceCount, {required bool indexed}) {
    final current = _current;
    if (current == null) return;
    final context = _drawContext;
    final item = context?.item;
    final material = context?.material;
    current.draws.add(
      CapturedDraw(
        passIndex: current.indexInGraph,
        order: current.draws.length,
        phase: context?.phase ?? DrawPhase.other,
        vertexCount: vertexCount,
        instanceCount: instanceCount,
        indexed: indexed,
        batchedItems: context?.batchedItems ?? 1,
        batchBreak: context?.batchBreak ?? BatchBreakReason.none,
        uniformBlocks: List.of(_pendingUniforms),
        nodePath: item == null ? null : nodePathOf(item),
        materialType: material?.runtimeType.toString(),
        materialSource: material == null ? null : fmatSourcePathOf(material),
        geometryType: context?.geometry?.runtimeType.toString(),
        vertexShader: context?.vertexShader,
        fragmentShader: context?.fragmentShader,
        pipelineId: context?.pipeline == null
            ? null
            : identityHashCode(context!.pipeline),
      ),
    );
    _pendingUniforms.clear();
  }

  @override
  void onSkip(RenderItem item, DrawSkipReason reason) {
    _current?.skips.add(
      CapturedSkip(reason: reason, nodePath: nodePathOf(item)),
    );
  }

  /// Slash-joined names from the scene root to the node that owns [item],
  /// or null when the item has no node.
  static String? nodePathOf(RenderItem item) {
    final source = item.sourceNode;
    if (source is! Node) return null;
    final names = <String>[];
    for (Node? node = source; node != null; node = node.parent) {
      names.add(node.name.isEmpty ? '<unnamed>' : node.name);
    }
    return names.reversed.join('/');
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
