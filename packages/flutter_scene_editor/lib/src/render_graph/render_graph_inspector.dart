/// Capture orchestration for the Render Graph panel: arms engine captures
/// against the live scene, converts snapshots into displayable images
/// through the debug remap shader, and runs the non-finite scan.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/render/render_graph_capture.dart';

import 'debug_shaders.dart';

/// One resource row the panel displays: the engine's captured metadata plus
/// the remapped thumbnail image.
class InspectedResource {
  InspectedResource(this.captured, this.thumbnail);

  final CapturedResource captured;

  /// Displayable thumbnail (default remap), or null for metadata-only rows.
  final ui.Image? thumbnail;

  String get key => captured.key;
}

/// A non-finite scan result for one resource.
class NonFiniteEntry {
  const NonFiniteEntry({
    required this.key,
    required this.passIndex,
    required this.passName,
    required this.nanCount,
    required this.infCount,
  });

  final String key;
  final int passIndex;
  final String passName;
  final int nanCount;
  final int infCount;
}

/// The whole-frame non-finite scan.
class NonFiniteReport {
  const NonFiniteReport({
    required this.offenders,
    required this.unscanned,
    required this.scannedCount,
  });

  /// Resources containing NaN/Inf, in execution order; the first entry is
  /// where non-finite values originate (downstream is contamination).
  final List<NonFiniteEntry> offenders;

  /// Float-format resources that could not be read back.
  final List<String> unscanned;

  final int scannedCount;
}

/// Drives captures for one live [Scene] and holds the latest result for the
/// panel. Exactly one capture is retained; a new one replaces it.
class RenderGraphInspector extends ChangeNotifier {
  RenderGraphInspector();

  /// The scene captures run against; rebind when the controller is replaced.
  Scene? scene;

  RenderGraphCaptureResult? _result;
  List<InspectedResource> _resources = const [];
  NonFiniteReport? _nonFinite;
  bool _busy = false;
  String? _lastError;

  RenderGraphCaptureResult? get result => _result;
  List<InspectedResource> get resources => _resources;
  NonFiniteReport? get nonFiniteReport => _nonFinite;
  bool get busy => _busy;
  String? get lastError => _lastError;

  /// Captures the next frame with thumbnails and refreshes the panel model.
  Future<void> captureFrame() async {
    await _run(() async {
      final capture = await _arm(
        const RenderGraphCaptureRequest(thumbnailMaxDim: 256),
      );
      final resources = <InspectedResource>[
        for (final resource in capture.resources)
          InspectedResource(resource, _thumbnailImage(resource)),
      ];
      _result = capture;
      _resources = resources;
      _nonFinite = null;
    });
  }

  /// Re-captures one resource at full resolution, returning its snapshot
  /// texture (same pixel format as the source), or null when it could not
  /// be captured.
  Future<gpu.Texture?> captureFullResolution(String key) async {
    gpu.Texture? snapshot;
    await _run(() async {
      final capture = await _arm(
        RenderGraphCaptureRequest(
          thumbnailMaxDim: null,
          fullResolution: true,
          onlyKeys: {key},
        ),
      );
      for (final resource in capture.resources.reversed) {
        if (resource.key == key && resource.snapshot != null) {
          snapshot = resource.snapshot;
          break;
        }
      }
    });
    return snapshot;
  }

  /// Captures every float-format target at full resolution and scans the
  /// readbacks for NaN/Inf, badging the first offending pass.
  Future<NonFiniteReport?> scanForNonFinite() async {
    await _run(() async {
      final capture = await _arm(
        const RenderGraphCaptureRequest(
          thumbnailMaxDim: null,
          fullResolution: true,
        ),
      );
      final offenders = <NonFiniteEntry>[];
      final unscanned = <String>[];
      var scanned = 0;
      for (final resource in capture.resources) {
        if (!_isFloatFormat(resource.format)) continue;
        final snapshot = resource.snapshot;
        if (snapshot == null) {
          unscanned.add(resource.key);
          continue;
        }
        final floats = await readbackFloats(snapshot);
        if (floats == null) {
          unscanned.add(resource.key);
          continue;
        }
        scanned++;
        var nans = 0;
        var infs = 0;
        for (final value in floats) {
          if (value.isNaN) {
            nans++;
          } else if (value.isInfinite) {
            infs++;
          }
        }
        if (nans > 0 || infs > 0) {
          offenders.add(
            NonFiniteEntry(
              key: resource.key,
              passIndex: resource.passIndex,
              passName:
                  resource.passIndex >= 0 &&
                      resource.passIndex < capture.passes.length
                  ? capture.passes[resource.passIndex].name
                  : '(build)',
              nanCount: nans,
              infCount: infs,
            ),
          );
        }
      }
      offenders.sort((a, b) => a.passIndex.compareTo(b.passIndex));
      _nonFinite = NonFiniteReport(
        offenders: offenders,
        unscanned: unscanned,
        scannedCount: scanned,
      );
    });
    return _nonFinite;
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await body();
    } catch (error) {
      _lastError = '$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // Arms a capture and schedules the frame that fulfills it. The primary
  // screen view (index 0) of whichever SceneView renders first wins; the
  // editor's main viewport is that view.
  // TODO(render-graph-multiview): a view selector for extra viewports and
  // RenderTexture targets.
  Future<RenderGraphCaptureResult> _arm(
    RenderGraphCaptureRequest request,
  ) async {
    final scene = this.scene;
    if (scene == null) {
      throw StateError('No scene is bound to the render graph inspector');
    }
    if (!editorDebugShadersLoaded) await loadEditorDebugShaders();
    final future = scene.captureRenderGraph(request: request);
    WidgetsBinding.instance.scheduleFrame();
    return future;
  }

  ui.Image? _thumbnailImage(CapturedResource resource) {
    final thumbnail = resource.thumbnail;
    if (thumbnail == null) return null;
    try {
      return remapToImage(
        thumbnail,
        RemapSettings.defaultsFor(resource.format, resource.key),
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isFloatFormat(gpu.PixelFormat? format) =>
      format == gpu.PixelFormat.r16g16b16a16Float ||
      format == gpu.PixelFormat.r32g32b32a32Float ||
      format == gpu.PixelFormat.r32Float;
}
