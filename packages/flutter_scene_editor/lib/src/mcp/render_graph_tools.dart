/// The MCP-facing render graph tools: captures armed against the live
/// scene, JSON encoding of the graph, remapped PNGs of any resource, exact
/// pixel reads, the non-finite scan, and the viewport debug-mode registry.
/// The app wires these into its [EditorToolSurface].
library;

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

  /// The debug-output registry with the active flag.
  List<Map<String, Object?>> listModes() {
    final scene = _sceneProvider();
    final active = scene == null
        ? 'final'
        : debugVisualizePassFor(scene).mode.id;
    return [
      for (final mode in viewportDebugModes)
        {'id': mode.id, 'label': mode.label, 'active': mode.id == active},
    ];
  }

  /// Selects the viewport debug output.
  Future<void> setMode(String id) async {
    final mode = viewportDebugModeById(id);
    if (mode == null) {
      throw ToolError(
        'Unknown debug mode "$id"; call list_viewport_debug_modes',
      );
    }
    if (mode.resolve != null) await loadEditorDebugShaders();
    debugVisualizePassFor(_scene).mode = mode;
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<RenderGraphCaptureResult> _arm(RenderGraphCaptureRequest request) {
    final run = _queue.then((_) => armRenderGraphCapture(_scene, request));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
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
