/// Getting a WebGPU frame into Flutter as a `ui.Image`, synchronously.
///
/// The same handoff the WebGL2 backend uses (`snapshotTextureSync` in
/// `web/gpu_context.dart`), because `Scene.render` draws the frame inside a
/// synchronous paint callback. The canvas's current texture is rendered,
/// submitted, and transferred out with `transferToImageBitmap`, which takes the
/// submitted contents and gives the canvas a fresh texture for the next frame.
library;

import 'dart:js_interop';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

import 'webgpu_device.dart';
import 'webgpu_interop.dart';

/// Owns the `OffscreenCanvas` frames are handed to Flutter through.
final class WebGpuPresenter {
  WebGpuPresenter(this.device) : _canvas = web.OffscreenCanvas(1, 1) {
    final context = _canvas.getContext('webgpu');
    if (context == null) {
      throw StateError('OffscreenCanvas has no webgpu context.');
    }
    _context = context as GPUCanvasContext;
  }

  final WebGpuDevice device;
  final web.OffscreenCanvas _canvas;
  late final GPUCanvasContext _context;
  bool _configured = false;

  /// The canvas texture format frames are rendered in.
  String get format => device.preferredCanvasFormat;

  void _resize(int width, int height) {
    if (_configured && _canvas.width == width && _canvas.height == height) {
      return;
    }
    _canvas.width = width;
    _canvas.height = height;
    // Premultiplied, matching the linear-premultiplied contract the resolve
    // pass hands to Flutter.
    _context.configure(
      GPUCanvasConfiguration(
        device: device.device,
        format: format,
        alphaMode: 'premultiplied',
      ),
    );
    _configured = true;
  }

  /// Clears a [width] by [height] frame to the given color and returns it as
  /// a `ui.Image` without awaiting anything.
  ui.Image clearToImageSync(
    int width,
    int height, {
    required double r,
    required double g,
    required double b,
    required double a,
  }) {
    _resize(width, height);
    final target = _context.getCurrentTexture();
    final encoder = device.device.createCommandEncoder();
    encoder
        .beginRenderPass(
          GPURenderPassDescriptor(
            colorAttachments: [
              GPURenderPassColorAttachment(
                view: target.createView(),
                clearValue: GPUColorDict(r: r, g: g, b: b, a: a),
                loadOp: 'clear',
                storeOp: 'store',
              ),
            ].toJS,
          ),
        )
        .end();
    device.device.queue.submit([encoder.finish()].toJS);
    return _transferSync();
  }

  ui.Image _transferSync() {
    final bitmap = _canvas.transferToImageBitmap();
    final image = ui_web.createImageFromImageBitmap(bitmap as JSAny);
    if (image is ui.Image) return image;
    throw StateError(
      'createImageFromImageBitmap returned a Future; the synchronous frame '
      'path needs a ui.Image on this renderer.',
    );
  }

  void dispose() {
    if (_configured) _context.unconfigure();
  }
}
