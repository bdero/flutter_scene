import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/texture2d.dart';

/// When an [ExternalTexture] re-captures its source.
///
/// The same shape as `WidgetUpdatePolicy` and `RenderTextureUpdate`, so every
/// live texture in the engine shares one mental model.
/// {@category Assets and loading}
sealed class ExternalTextureUpdate {
  const ExternalTextureUpdate._();

  /// Capture on every frame that draws this source (the default).
  static const ExternalTextureUpdate everyFrame = _EveryFrameUpdate();

  /// Capture at most once per [duration]. Use for a video on a distant
  /// billboard, or any source that does not need to be current.
  const factory ExternalTextureUpdate.interval(Duration duration) =
      _IntervalUpdate;

  /// Capture only when [ExternalTexture.requestCapture] is called.
  static const ExternalTextureUpdate manual = _ManualUpdate();
}

class _EveryFrameUpdate extends ExternalTextureUpdate {
  const _EveryFrameUpdate() : super._();
}

class _IntervalUpdate extends ExternalTextureUpdate {
  const _IntervalUpdate(this.duration) : super._();
  final Duration duration;
}

class _ManualUpdate extends ExternalTextureUpdate {
  const _ManualUpdate() : super._();
}

/// Sampling options used when a material samples an [ExternalTexture].
///
/// Defaults to bilinear with clamped edges, matching `RenderTextureSampling`.
/// Streamed frames carry no mip chain, so minification is not filtered; keep
/// the surface reasonably close to the camera or expect aliasing.
/// {@category Assets and loading}
class ExternalTextureSampling {
  /// Creates sampling options.
  const ExternalTextureSampling({
    this.filter = gpu.MinMagFilter.linear,
    this.wrap = gpu.SamplerAddressMode.clampToEdge,
  });

  /// The minification/magnification filter.
  final gpu.MinMagFilter filter;

  /// The addressing mode for texture coordinates outside `0..1`, applied to
  /// both axes.
  final gpu.SamplerAddressMode wrap;

  /// The equivalent sampler description.
  @internal
  gpu.SamplerOptions toSamplerOptions() => gpu.SamplerOptions(
    minFilter: filter,
    magFilter: filter,
    widthAddressMode: wrap,
    heightAddressMode: wrap,
  );
}

/// A live [TextureSource] fed by a platform texture, so video, camera
/// preview, and any other native producer can be sampled by scene materials.
///
/// Point it at the texture id a plugin registered with Flutter's texture
/// registry and assign it to a material slot. The frame is captured through
/// the same compositor path the `Texture` widget draws with, so whatever the
/// platform hands over (an Android external OES texture, a biplanar NV12
/// buffer) arrives here as an ordinary RGBA texture that any material can
/// sample.
///
/// ```dart
/// final video = ExternalTexture(
///   textureId: id,
///   width: 1920,
///   height: 1080,
/// );
/// material.baseColorTexture = video;
/// // ... later
/// video.dispose();
/// ```
///
/// [sampledTexture] is null until the first capture completes, and the
/// texture object is replaced on every capture, so read it through the
/// [TextureSource] each frame rather than caching it. Listeners fire after
/// each new frame is published.
///
/// Captures are driven by drawing rather than by a ticker, so a source
/// nothing samples costs nothing, and a source sampled every frame keeps up
/// on its own. They are throttled to one in flight, so a source producing
/// frames faster than they can be captured skips ahead to the latest instead
/// of queueing.
///
/// The capture is top-down (`v` of 0 is the top of the source), matching
/// [Texture2D].
///
/// Getting a texture id out of a plugin is not always possible. Some plugins
/// render through a platform view instead and expose no id, and some keep the
/// id private. Capture a `WidgetTexture` around the plugin's own preview
/// widget in that case; it costs an extra layout and paint but works for any
/// widget.
///
/// Platform support follows the engine's ability to resolve a texture id
/// outside a live frame. Android works. The web has no platform textures at
/// all. macOS and iOS currently capture an empty frame, because the engine
/// resolves external textures for a snapshot without an Impeller context and
/// falls back to a Skia path that is inactive under Impeller; a debug build
/// warns when it sees this. Use a `WidgetTexture` around the plugin's preview
/// widget where that matters.
/// {@category Assets and loading}
class ExternalTexture extends ChangeNotifier implements TextureSource {
  /// Creates a source capturing [textureId] at [width] x [height] pixels.
  ///
  /// [textureId] may be null when a plugin has not published one yet; set it
  /// once it has.
  ExternalTexture({
    int? textureId,
    required int width,
    required int height,
    this.update = ExternalTextureUpdate.everyFrame,
    this.sampling = const ExternalTextureSampling(),
    this.colorFilter,
  }) : assert(width > 0 && height > 0, 'ExternalTexture size must be positive'),
       _textureId = textureId,
       _width = width,
       _height = height;

  int? _textureId;
  int _width;
  int _height;

  /// When this source re-captures. See [ExternalTextureUpdate].
  ExternalTextureUpdate update;

  /// Sampling options used when a material samples this source.
  ExternalTextureSampling sampling;

  /// Optional color filter applied to the captured texture (for example color
  /// inversion or channel swizzling).
  ui.ColorFilter? colorFilter;

  gpu.Texture? _texture;
  bool _captureInFlight = false;
  bool _captureRequested = false;
  bool _disposed = false;
  DateTime? _lastCaptureStart;
  Duration _lastCaptureDuration = Duration.zero;
  int _captureCount = 0;

  // Cleared by the first capture that proves this platform cannot wrap a
  // snapshot as a GPU texture (the web), so later frames stop trying.
  bool _supported = true;

  /// The platform texture id being captured, or null if none is set yet.
  int? get textureId => _textureId;

  set textureId(int? value) {
    if (value == _textureId) return;
    _textureId = value;
    requestCapture();
  }

  /// The capture width in pixels.
  int get width => _width;

  /// The capture height in pixels.
  int get height => _height;

  /// The most recent frame, or null before the first capture completes.
  ///
  /// The object changes identity on every capture, so re-read it when drawing
  /// rather than caching it.
  gpu.Texture? get texture => _texture;

  /// The frame to sample this draw, kicking off the next capture when one is
  /// due. Capture is driven from here rather than from a ticker, so a source
  /// nothing samples costs nothing.
  @override
  gpu.Texture? get sampledTexture {
    if (shouldCapture(DateTime.now())) unawaited(_capture());
    return _texture;
  }

  @override
  gpu.SamplerOptions get sampledSampler => sampling.toSamplerOptions();

  /// Wall-clock duration of the last capture, for diagnostics.
  Duration get lastCaptureDuration => _lastCaptureDuration;

  /// Total completed captures, for diagnostics.
  int get captureCount => _captureCount;

  /// Captures at a new size. Takes effect on the next capture.
  void resize(int width, int height) {
    assert(width > 0 && height > 0, 'ExternalTexture size must be positive');
    if (width == _width && height == _height) return;
    _width = width;
    _height = height;
    requestCapture();
  }

  /// Captures on the next draw that samples this source. The trigger for
  /// [ExternalTextureUpdate.manual]; under the other policies it skips ahead
  /// of the schedule.
  void requestCapture() => _captureRequested = true;

  /// Whether a capture is due now, consuming a pending [requestCapture].
  @internal
  bool shouldCapture(DateTime now) {
    if (_disposed || !_supported || _textureId == null) return false;
    if (_captureRequested) {
      _captureRequested = false;
      return true;
    }
    switch (update) {
      case _EveryFrameUpdate():
        return true;
      case _IntervalUpdate(:final duration):
        final last = _lastCaptureStart;
        return last == null || now.difference(last) >= duration;
      case _ManualUpdate():
        return false;
    }
  }

  Future<void> _capture() async {
    final textureId = _textureId;
    if (textureId == null || _captureInFlight || _disposed) return;
    _captureInFlight = true;
    final start = DateTime.now();
    _lastCaptureStart = start;
    final stopwatch = Stopwatch()..start();
    try {
      final width = _width;
      final height = _height;
      final builder = ui.SceneBuilder();
      if (colorFilter != null) {
        builder.pushColorFilter(colorFilter!);
      }
      builder.addTexture(
        textureId,
        width: width.toDouble(),
        height: height.toDouble(),
        filterQuality: ui.FilterQuality.none,
      );
      if (colorFilter != null) {
        builder.pop();
      }
      final scene = builder.build();
      final ui.Image image;
      try {
        image = await scene.toImage(width, height);
      } finally {
        scene.dispose();
      }
      try {
        if (_disposed) return;
        // The wrapper shares the image's storage and keeps it alive, so the
        // image can be released as soon as it is wrapped.
        final wrapped = gpu.Texture.fromImage(gpu.gpuContext, image);
        _texture = wrapped;
        _lastCaptureDuration = stopwatch.elapsed;
        _captureCount++;
        notifyListeners();
        if (kDebugMode && _captureCount == 1) {
          await _debugWarnIfBlank(image, textureId);
        }
      } finally {
        image.dispose();
      }
    } catch (error) {
      // Platform textures and snapshot wrapping are not available everywhere
      // (the web has neither). Give up rather than retrying every frame.
      _supported = false;
      debugPrint(
        'ExternalTexture could not capture texture $textureId and is now '
        'inactive. $error',
      );
    } finally {
      _captureInFlight = false;
    }
  }

  /// Warns once when the first capture came back fully transparent.
  ///
  /// A platform that cannot resolve a texture id into a snapshot still hands
  /// back a well-formed empty image, which is indistinguishable from a source
  /// that has not produced a frame yet, so the material just samples nothing
  /// forever. Debug builds pay one readback to say so out loud.
  Future<void> _debugWarnIfBlank(ui.Image image, int textureId) async {
    final bytes = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null || _disposed) return;
    final totalPixels = bytes.lengthInBytes ~/ 4;
    final step = math.max(1, totalPixels ~/ 256);
    for (var i = 0; i < totalPixels; i += step) {
      if (bytes.getUint8(i * 4 + 3) != 0) return;
    }
    debugPrint(
      'ExternalTexture captured texture $textureId as a fully transparent '
      'frame. The platform reported no error, so it most likely cannot '
      'resolve platform textures into snapshots; check the logs for an '
      'external texture error from the engine. Sample the plugin through a '
      'WidgetTexture instead if this platform is required.',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _texture = null;
    super.dispose();
  }
}
