part of '_gpu.dart';

// flutter_gpu's presentable surfaces, over textures the active web backend
// allocates. Native re-exports the engine's own.

/// The result of presenting a [GpuSurfaceFrame].
enum GpuPresentStatus {
  /// The frame was presented and no reconfiguration is needed.
  success,

  /// The frame was presented, but the surface should be reconfigured before
  /// the next frame.
  suboptimal,

  /// The surface is out of date and must be reconfigured before presenting
  /// again.
  outOfDate,
}

/// A presentable render target that vends [GpuSurfaceFrame]s.
sealed class GpuSurface {
  /// The next frame to render into, or null when none is available.
  GpuSurfaceFrame? acquireNextFrame();
}

/// A write lease on [colorTexture], ended by exactly one of [present] or
/// [discard].
sealed class GpuSurfaceFrame {
  /// The final color target for this frame, writable until the lease ends.
  Texture get colorTexture;

  /// Publishes the frame. [commandBuffer] is the one whose completion means
  /// the frame's color is final; call this before submitting it.
  GpuPresentStatus present(CommandBuffer commandBuffer);

  /// Releases the frame without presenting it. A no-op after [present].
  void discard();
}

final class _SurfaceRecord {
  _SurfaceRecord(this.texture);

  final Texture texture;
  bool acquired = false;
}

/// A pool of color textures whose presented frame Flutter draws as a
/// `ui.Image`.
final class GpuImageSurface implements GpuSurface {
  GpuImageSurface._(this._gpuContext, this._width, this._height, this._format) {
    _checkDimensions(_width, _height);
  }

  final GpuContext _gpuContext;
  int _width;
  int _height;
  final PixelFormat _format;

  final List<_SurfaceRecord> _records = [];
  _SurfaceRecord? _current;
  ui.Image? _currentImage;

  /// The width, in pixels, of frames acquired from this surface.
  int get width => _width;

  /// The height, in pixels, of frames acquired from this surface.
  int get height => _height;

  /// The color format of frames acquired from this surface.
  PixelFormat get format => _format;

  /// How many backing textures the surface holds, for diagnostics and tests.
  int get debugBackingTextureCount => _records.length;

  /// The most recently presented image, or null before the first present.
  ///
  /// A snapshot taken on first read after each present, so it stays valid
  /// when a later frame reuses the backing texture.
  ui.Image? get currentImage {
    final current = _current;
    if (current == null) return null;
    return (_currentImage ??= current.texture.asImage()).clone();
  }

  /// Changes the size of future frames. Throws while a frame is acquired.
  void resize(int width, int height) {
    _checkDimensions(width, height);
    if (_records.any((record) => record.acquired)) {
      throw StateError(
        'GpuSurface.resize cannot be called while a SurfaceFrame is acquired.',
      );
    }
    _width = width;
    _height = height;
    _prune();
  }

  @override
  GpuImageSurfaceFrame acquireNextFrame() {
    _prune();
    _SurfaceRecord? free;
    for (final record in _records) {
      if (!record.acquired && !identical(record, _current)) {
        free = record;
        break;
      }
    }
    if (free == null) {
      free = _SurfaceRecord(
        _gpuContext.createTexture(
          StorageMode.devicePrivate,
          _width,
          _height,
          format: _format,
          enableRenderTargetUsage: true,
          enableShaderReadUsage: true,
        ),
      );
      _records.add(free);
    }
    free.acquired = true;
    return GpuImageSurfaceFrame._(this, free);
  }

  // Drops idle textures of a size the surface no longer vends.
  void _prune() {
    _records.removeWhere((record) {
      final stale =
          !record.acquired &&
          !identical(record, _current) &&
          (record.texture.width != _width || record.texture.height != _height);
      if (stale) gpuHost.releaseTexture(record.texture);
      return stale;
    });
  }

  void _present(_SurfaceRecord record) {
    record.acquired = false;
    _current = record;
    _currentImage?.dispose();
    _currentImage = null;
  }

  static void _checkDimensions(int width, int height) {
    if (width <= 0) {
      throw ArgumentError.value(width, 'width', 'Must be greater than zero.');
    }
    if (height <= 0) {
      throw ArgumentError.value(height, 'height', 'Must be greater than zero.');
    }
  }
}

/// A writable frame acquired from a [GpuImageSurface].
final class GpuImageSurfaceFrame implements GpuSurfaceFrame {
  GpuImageSurfaceFrame._(this._surface, this._record);

  final GpuImageSurface _surface;
  final _SurfaceRecord _record;
  bool _isActive = true;

  @override
  Texture get colorTexture => _record.texture;

  /// Publishes this frame as the surface's current image. The web backends
  /// run commands in call order, so [commandBuffer] only marks the point the
  /// frame is final at.
  @override
  GpuPresentStatus present(CommandBuffer commandBuffer) {
    if (!_isActive) {
      throw StateError(
        'GpuSurfaceFrame has already been presented or discarded.',
      );
    }
    _isActive = false;
    _surface._present(_record);
    return GpuPresentStatus.success;
  }

  @override
  void discard() {
    if (!_isActive) return;
    _isActive = false;
    _record.acquired = false;
  }
}
