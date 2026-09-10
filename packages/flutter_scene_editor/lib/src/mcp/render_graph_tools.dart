/// The MCP-facing render graph tools: captures armed against the live
/// scene, JSON encoding of the graph, remapped PNGs of any resource, exact
/// pixel reads, draw and shader introspection, the non-finite scan, and the
/// viewport debug-mode registry. The app wires these into its
/// [EditorToolSurface].
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_mcp/flutter_scene_mcp.dart'
    show ScreenshotResult, ToolError;

import '../render_graph/debug_shaders.dart';
import '../render_graph/render_graph_inspector.dart'
    show armRenderGraphCapture, scanCaptureForNonFinite;
import '../viewport/debug_visualize.dart';

/// Render graph inspection over MCP, bound to a scene provider so one
/// connection stays valid across document swaps.
class RenderGraphMcp {
  RenderGraphMcp(this._sceneProvider);

  final Scene? Function() _sceneProvider;

  // Serializes captures: the engine holds one pending arm, so a concurrent
  // second call would fail the first with "superseded".
  Future<void> _queue = Future<void>.value();

  // The draw and shader tools read whatever the last capture recorded, so
  // an agent can list draws without re-rendering.
  RenderGraphCaptureResult? _lastCapture;

  Scene get _scene {
    final scene = _sceneProvider();
    if (scene == null) {
      throw const ToolError('No live scene to capture');
    }
    return scene;
  }

  /// Captures the next frame and returns the graph JSON.
  Future<Map<String, Object?>> capture({
    required bool thumbnails,
    int? maxDimension,
  }) async {
    final result = await _arm(
      RenderGraphCaptureRequest(
        captureImages: thumbnails,
        thumbnailMaxDim: thumbnails ? (maxDimension ?? 256) : null,
      ),
    );
    return _encode(result);
  }

  /// Renders one resource through the display remap as a PNG.
  Future<ScreenshotResult> passOutput(
    String key,
    Map<String, Object?> options,
  ) async {
    final maxDimension = (options['maxDimension'] as num?)?.toInt();
    final result = await _arm(
      RenderGraphCaptureRequest(
        thumbnailMaxDim: maxDimension,
        fullResolution: maxDimension == null,
        onlyKeys: {key},
      ),
    );
    final resource = _findCaptured(result, key);
    // With a maxDimension the reduced copy is the product; a full-resolution
    // base64 PNG of a large HDR target would swamp the model context.
    final texture = maxDimension != null
        ? (resource.thumbnail ?? resource.snapshot)
        : (resource.snapshot ?? resource.thumbnail);
    if (texture == null) {
      throw ToolError(
        'Resource "$key" carries no image (not shader-readable this frame)',
      );
    }
    var settings = RemapSettings.defaultsFor(resource.format, key);
    final channel = options['channel'];
    if (channel is String && channel.isNotEmpty) {
      const channels = {'r': 0, 'g': 1, 'b': 2, 'a': 3};
      final index = channels[channel.toLowerCase()];
      if (index == null) {
        throw ToolError('Unknown channel "$channel"; use r, g, b, or a');
      }
      settings = settings.copyWith(
        mode: RemapMode.singleChannel,
        channel: index,
      );
    }
    final rangeMin = options['rangeMin'];
    final rangeMax = options['rangeMax'];
    if (rangeMin is num) {
      settings = settings.copyWith(blackPoint: rangeMin.toDouble());
    }
    if (rangeMax is num) {
      settings = settings.copyWith(
        whitePoint: rangeMax.toDouble(),
        far: rangeMax.toDouble(),
      );
    }
    if (options['highlightNonFinite'] == true) {
      settings = settings.copyWith(highlightNonFinite: true);
    }
    final image = remapToImage(texture, settings);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const ToolError('Failed to encode the resource as PNG');
      }
      return ScreenshotResult(
        pngBytes: data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } finally {
      image.dispose();
    }
  }

  /// Reads one pixel's exact float values from [key]'s full-resolution
  /// snapshot.
  Future<Map<String, Object?>> readPixel(String key, int x, int y) async {
    final result = await _arm(
      RenderGraphCaptureRequest(
        thumbnailMaxDim: null,
        fullResolution: true,
        onlyKeys: {key},
      ),
    );
    final resource = _findCaptured(result, key);
    final snapshot = resource.snapshot;
    if (snapshot == null) {
      throw ToolError('Resource "$key" carries no image to read');
    }
    if (x < 0 || y < 0 || x >= snapshot.width || y >= snapshot.height) {
      throw ToolError(
        'Pixel ($x, $y) is outside ${snapshot.width}x${snapshot.height}',
      );
    }
    final floats = await readbackFloats(snapshot);
    if (floats == null) {
      throw const ToolError('Float readback is unavailable on this backend');
    }
    final index = (y * snapshot.width + x) * 4;
    final r = floats[index];
    final g = floats[index + 1];
    final b = floats[index + 2];
    final a = floats[index + 3];
    Object encode(double value) => value.isFinite
        ? value
        : value.isNaN
        ? 'NaN'
        : (value > 0 ? 'Inf' : '-Inf');
    final nonFinite = <String>[
      if (!r.isFinite) 'r',
      if (!g.isFinite) 'g',
      if (!b.isFinite) 'b',
      if (!a.isFinite) 'a',
    ];
    return {
      'key': key,
      'x': x,
      'y': y,
      'r': encode(r),
      'g': encode(g),
      'b': encode(b),
      'a': encode(a),
      'nonFinite': nonFinite,
      'width': snapshot.width,
      'height': snapshot.height,
    };
  }

  /// Captures a frame and scans every float target for NaN/Inf, through the
  /// same scan core as the panel.
  Future<Map<String, Object?>> scanForNans() async {
    final result = await _arm(
      const RenderGraphCaptureRequest(
        thumbnailMaxDim: null,
        fullResolution: true,
      ),
    );
    final report = await scanCaptureForNonFinite(result);
    return {
      'firstOffendingPass': report.offenders.isEmpty
          ? null
          : report.offenders.first.passName,
      'offenders': [
        for (final entry in report.offenders)
          {
            'key': entry.key,
            'passIndex': entry.passIndex,
            'pass': entry.passName,
            'nanCount': entry.nanCount,
            'infCount': entry.infCount,
          },
      ],
      'unscanned': report.unscanned,
      'scannedCount': report.scannedCount,
    };
  }

  /// The debug-output registry with the active flag: the editor's buffer
  /// views, then the engine's surface views (grouped by `group`), then the
  /// split and wireframe toggles.
  List<Map<String, Object?>> listModes() {
    final scene = _sceneProvider();
    final surfaceActive = scene?.debug.view.isActive ?? false;
    final bufferActive = scene == null
        ? 'final'
        : debugVisualizePassFor(scene).mode.id;
    final surfaceId = scene?.debug.viewId ?? 'none';
    return [
      for (final mode in viewportDebugModes)
        {
          'id': mode.id,
          'label': mode.label,
          'group': 'buffer',
          'active': !surfaceActive && mode.id == bufferActive,
        },
      for (final entry in DebugViewRegistry.entries)
        if (entry.group != SurfaceDebugGroup.none)
          {
            'id': entry.id,
            'label': entry.label,
            'group': entry.group.name,
            'active': surfaceActive && entry.id == surfaceId,
          },
      {
        'id': 'split',
        'label': 'Split against lit (toggle)',
        'group': 'toggle',
        'active': scene?.debug.split != null,
      },
      {
        'id': 'wireframe',
        'label': 'Wireframe overlay (toggle)',
        'group': 'toggle',
        'active':
            scene?.debug.overlays.contains(DebugOverlay.wireframe) ?? false,
      },
    ];
  }

  /// Selects the viewport debug output. A buffer view and a surface view are
  /// exclusive; `split` and `wireframe` toggle without changing the view.
  Future<void> setMode(String id) async {
    final scene = _scene;
    if (id == 'split') {
      scene.debug.split = scene.debug.split == null ? 0.5 : null;
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    if (id == 'wireframe') {
      final overlays = scene.debug.overlays;
      if (!overlays.remove(DebugOverlay.wireframe)) {
        overlays.add(DebugOverlay.wireframe);
      }
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final mode = viewportDebugModeById(id);
    if (mode != null) {
      if (mode.resolve != null) await loadEditorDebugShaders();
      scene.debug.view = DebugView.none;
      debugVisualizePassFor(scene).mode = mode;
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    final entry = DebugViewRegistry.byId(id);
    if (entry == null) {
      throw ToolError(
        'Unknown debug mode "$id"; call list_viewport_debug_modes',
      );
    }
    debugVisualizePassFor(scene).mode = viewportDebugModes.first;
    scene.debug.view = entry.view;
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The live scene's last frame plus [frames] of history.
  Map<String, Object?> renderStats(int frames) {
    final stats = _scene.renderStats;
    final latest = stats.latest;
    if (latest == null) {
      throw const ToolError('No frame has rendered yet');
    }
    final history = stats.history;
    final start = frames <= 0 || frames >= history.length
        ? (frames <= 0 ? history.length : 0)
        : history.length - frames;
    return {
      'frameCount': stats.frameCount,
      'latest': latest.toJson(),
      'history': [for (final frame in history.skip(start)) frame.toJson()],
    };
  }

  /// The last capture's draws, filtered and paged, with a per-pass tally of
  /// why items were skipped.
  Future<Map<String, Object?>> listDraws(Map<String, Object?> options) async {
    final capture = await _ensureCapture();
    // Draw shader names resolve through bundle reflection, so load it before
    // encoding or every draw reports null shaders.
    await ShaderReflection.loadAll();
    final phase = (options['phase'] as String?)?.toLowerCase();
    final node = (options['node'] as String?)?.toLowerCase();
    final material = (options['material'] as String?)?.toLowerCase();
    final includeUniforms = options['includeUniforms'] == true;
    final offset = (options['offset'] as num?)?.toInt() ?? 0;
    final limit = (options['limit'] as num?)?.toInt() ?? 200;

    final matched = <CapturedDraw>[];
    final skips = <String, Map<String, int>>{};
    for (final pass in capture.passes) {
      if (!_passMatches(pass, options['pass'])) continue;
      for (final draw in pass.draws) {
        if (phase != null && draw.phase.name.toLowerCase() != phase) continue;
        if (node != null &&
            !(draw.nodePath ?? '').toLowerCase().contains(node)) {
          continue;
        }
        if (material != null &&
            !'${draw.materialType ?? ''} ${draw.materialSource ?? ''}'
                .toLowerCase()
                .contains(material)) {
          continue;
        }
        matched.add(draw);
      }
      for (final skip in pass.skips) {
        final byReason = skips.putIfAbsent(pass.name, () => <String, int>{});
        byReason[skip.reason.name] = (byReason[skip.reason.name] ?? 0) + 1;
      }
    }
    final page = matched
        .skip(offset < 0 ? 0 : offset)
        .take(limit < 0 ? 0 : limit);
    return {
      'total': matched.length,
      'draws': [for (final draw in page) _drawJson(draw, includeUniforms)],
      'skips': skips,
    };
  }

  /// One draw of the last capture with its decoded uniform values.
  Future<Map<String, Object?>> readDraw(Object pass, int order) async {
    final capture = await _ensureCapture();
    await ShaderReflection.loadAll();
    for (final captured in capture.passes) {
      if (!_passMatches(captured, pass)) continue;
      for (final draw in captured.draws) {
        if (draw.order != order) continue;
        return {'pass': captured.name, ..._drawJson(draw, true)};
      }
    }
    throw ToolError(
      'No draw $order in pass "$pass"; call list_draws for what was drawn',
    );
  }

  /// Every loaded shader bundle with its entries.
  Future<Map<String, Object?>> listShaders() async {
    final bundles = await ShaderReflection.loadAll();
    return {
      'bundles': [
        for (var index = 0; index < bundles.length; index++)
          {
            'index': index,
            'shaders': [
              for (final shader in bundles[index].shaders)
                {
                  'name': shader.name,
                  if (shader.stage != null) 'stage': shader.stage!.name,
                  'backends': [
                    for (final backend in shader.backends.keys) backend.name,
                  ],
                  'uniformBlocks': [
                    for (final block
                        in shader.current?.uniformBlocks ??
                            const <ShaderUniformBlockInfo>[])
                      block.name,
                  ],
                  'textures': [
                    for (final texture
                        in shader.current?.textures ??
                            const <ShaderTextureInfo>[])
                      texture.name,
                  ],
                },
            ],
          },
      ],
    };
  }

  /// Reflection for the first entry named [name], for one backend.
  Future<Map<String, Object?>> shaderInfo(
    String name, {
    String? backend,
    bool includeSource = false,
  }) async {
    final bundles = await ShaderReflection.loadAll();
    ShaderInfo? found;
    for (final bundle in bundles) {
      found = bundle[name];
      if (found != null) break;
    }
    if (found == null) {
      throw ToolError('No shader named "$name"; call list_shaders');
    }
    ShaderBackendInfo? selected;
    if (backend == null) {
      selected = found.current;
    } else {
      for (final value in ShaderBackend.values) {
        if (value.name == backend) selected = found.backends[value];
      }
      if (selected == null) {
        throw ToolError(
          'Shader "$name" has no "$backend" output; it carries '
          '${found.backends.keys.map((b) => b.name).join(', ')}',
        );
      }
    }
    if (selected == null) {
      throw ToolError('Shader "$name" carries no compiled output');
    }
    return ShaderInfo(
      name: found.name,
      backends: {selected.backend: selected},
    ).toJson(includeSource: includeSource);
  }

  /// Writes the last capture to [path] as JSON.
  Future<Map<String, Object?>> saveCapture(
    String path, {
    bool includeImages = true,
  }) async {
    final capture = await _ensureCapture(images: includeImages);
    final json = await capture.toJsonString(
      includeImages: includeImages,
      includeUniformBytes: true,
    );
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json);
    return {
      'path': file.absolute.path,
      'bytes': await file.length(),
      'passes': capture.passes.length,
      'draws': capture.draws.length,
    };
  }

  static bool _passMatches(CapturedPass pass, Object? filter) {
    if (filter == null) return true;
    if (filter is num) return pass.indexInGraph == filter.toInt();
    return pass.name.toLowerCase() == filter.toString().toLowerCase();
  }

  // Decoded uniform values are large; they ride along only when asked for.
  static Map<String, Object?> _drawJson(CapturedDraw draw, bool uniforms) {
    final json = draw.toJson();
    if (uniforms) return json;
    for (final block in json['uniformBlocks'] as List) {
      (block as Map).remove('values');
    }
    return json;
  }

  Future<RenderGraphCaptureResult> _arm(RenderGraphCaptureRequest request) {
    final run = _queue.then((_) async {
      final result = await armRenderGraphCapture(_scene, request);
      _lastCapture = result;
      return result;
    });
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<RenderGraphCaptureResult> _ensureCapture({bool images = false}) async {
    final existing = _lastCapture;
    // A metadata-only capture cannot serve a request for images.
    if (existing != null &&
        (!images || existing.resources.any((r) => r.thumbnail != null))) {
      return existing;
    }
    return _arm(
      RenderGraphCaptureRequest(
        captureImages: images,
        thumbnailMaxDim: images ? 256 : null,
      ),
    );
  }

  CapturedResource _findCaptured(RenderGraphCaptureResult result, String key) {
    for (final resource in result.resources.reversed) {
      if (resource.key == key) return resource;
    }
    throw ToolError(
      'No resource "$key" in this frame; call list_render_passes for the '
      'available keys',
    );
  }

  Map<String, Object?> _encode(RenderGraphCaptureResult result) => {
    'pixelWidth': result.pixelWidth,
    'pixelHeight': result.pixelHeight,
    'gpuTimingsAvailable': false,
    'passes': [
      for (final pass in result.passes)
        {
          'name': pass.name,
          'index': pass.indexInGraph,
          'cpuMicros': pass.cpuMicros,
          'reads': pass.reads,
          'writes': pass.writes,
          'drawCount': pass.draws.length,
          'skipCount': pass.skips.length,
        },
    ],
    'resources': [
      for (final resource in result.resources)
        {
          'key': resource.key,
          'passIndex': resource.passIndex,
          if (resource.debugName != null) 'debugName': resource.debugName,
          'isTexture': resource.isTexture,
          if (resource.isTexture) ...{
            'width': resource.width,
            'height': resource.height,
            'format': resource.format?.name,
            'sampleCount': resource.sampleCount,
            if (resource.storageMode != null)
              'storageMode': resource.storageMode!.name,
            'shaderReadable': resource.shaderReadable,
            'captured': resource.snapshot != null || resource.thumbnail != null,
          },
          if (resource.byteLength != null) 'byteLength': resource.byteLength,
        },
    ],
  };
}
