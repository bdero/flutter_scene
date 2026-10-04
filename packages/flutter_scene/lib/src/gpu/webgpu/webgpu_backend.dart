/// The WebGPU implementation of the web GPU shim, selected with
/// `--dart-define=flutter_scene.webgpu=true`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show FlutterError, debugPrint, kDebugMode, visibleForTesting;
import 'package:web/web.dart' as web;

import '../../generated_assets/generated_asset_fetch_web.dart';
import '../shared/encoded_image_types.dart';
import '../shared/gpu_capabilities.dart';
import '../shared/gpu_sample_types.dart';
import '../shared/sidecar_hash.dart';
import '../shared/shader_library_sources.dart';
import '../shared/wgsl_bindings.dart'
    show WgslBindingMap, parseWgslDeclarations;
import '../web/_gpu.dart';
import 'webgpu_device.dart';
import 'webgpu_interop.dart';
import 'webgpu_presenter.dart';

part 'buffer.dart';
part 'context.dart';
part 'encoded_image.dart';
part 'formats.dart';
part 'host.dart';
part 'mips.dart';
part 'pipeline.dart';
part 'readback.dart';
part 'render_pass.dart';
part 'samplers.dart';
part 'shader_library.dart';
part 'texture.dart';

/// The WebGPU backend.
WebBackend createWebGpuBackend() => _WebGpuBackend();

/// A WebGPU descriptor dictionary. Creation-time only; per-draw paths use
/// typed interop instead of converting a map.
JSObject _obj(Map<String, Object?> fields) => fields.jsify()! as JSObject;

/// A WebGPU sequence, such as an extent or origin.
JSObject _arr(List<Object?> items) => items.jsify()! as JSObject;

/// Prints WebGPU errors no error scope caught, which otherwise reach only the
/// browser console. The first few, since one bad draw repeats every frame.
void _reportUncapturedErrors(GPUDevice device) {
  var reported = 0;
  (device as web.EventTarget).addEventListener(
    'uncapturederror',
    (web.Event event) {
      if (reported++ >= 20) return;
      final error = event.getProperty<JSObject?>('error'.toJS);
      final message = error?.getProperty<JSString?>('message'.toJS)?.toDart;
      debugPrint(
        'flutter_scene (WebGPU): ${message ?? 'unknown error'}'
        '${reported == 20 ? ' (further errors not printed)' : ''}',
      );
    }.toJS,
  );
}

final class _WebGpuBackend extends WebBackend {
  _WebGpuContext? _context;

  @override
  Future<void> initialize() async {
    if (_context != null) return;
    // Forced, so a software adapter is accepted rather than silently
    // rendering nothing; the auto mode that prefers WebGL2 there is
    // TODO(webgpu-runtime-selection).
    final probe = await WebGpuDevice.request(allowFallbackAdapter: true);
    _context = _WebGpuContext(
      probe.device ??
          (throw StateError(
            '$probe. Build without --dart-define=flutter_scene.webgpu=true '
            'to use WebGL2.',
          )),
    );
    if (kDebugMode) {
      debugPrint('flutter_scene: WebGPU backend, $probe');
      _reportUncapturedErrors(probe.device!.device);
    }
  }

  @override
  _WebGpuContext get context =>
      _context ??
      (throw StateError(
        'The WebGPU backend was used before initializeGpuBackend completed.',
      ));

  @override
  late final GpuHost host = _WebGpuHost(this);

  @override
  Texture textureFromImage(GpuContext gpuContext, ui.Image image) =>
      throw Exception(
        'Texture.fromImage could not wrap the image because it is not backed '
        'by a compatible GPU texture. The web backend cannot share textures '
        'with the framework; read the image back and upload it instead.',
      );

  @override
  Future<ShaderLibrary?> loadShaderLibraryAsync(String assetName) =>
      _loadShaderLibraryAsync(context, assetName);

  @override
  Future<ShaderLibrary?> loadShaderLibraryFromBytesAsync(ByteData bytes) =>
      throw UnsupportedError(
        'The WebGPU backend loads shaders from the WGSL sidecar next to a '
        'bundle asset, so a bundle given as bytes has none. Load it by asset '
        'key with loadShaderLibraryAsync.',
      );
  // TODO(webgpu-bytes-libraries): accept the sidecar alongside the bytes, for
  // .fmat bundles loaded from a custom AssetBundle.

  @override
  Future<void> reinitializeShaderLibraryAsync(String assetKey) =>
      _reinitializeShaderLibraryAsync(context, assetKey);

  @override
  Future<String?> reinitializeShaderLibraryFromBytesAsync(
    ShaderLibrary library,
    ByteData bytes,
  ) => throw UnsupportedError(
    'The WebGPU backend cannot reload a shader library from bundle bytes; '
    'see loadShaderLibraryFromBytesAsync.',
  );

  @override
  ShaderLibrary compileShaderLibraryInline(
    Map<String, ({String source, ShaderStage stage})> shaders,
  ) => throw UnsupportedError(
    'Inline GLSL needs a GLSL to WGSL translator at runtime, which the WebGPU '
    'backend does not ship. Build the shaders into a bundle instead.',
  );

  @override
  Future<Texture?> createTextureFromEncodedImage(
    Uint8List encoded, {
    MipContent content = MipContent.color,
    bool mipmaps = true,
    int? maxMipLevels,
    int? maxSize,
  }) => _createTextureFromEncodedImage(
    context,
    encoded,
    content: content,
    mipmaps: mipmaps,
    maxMipLevels: maxMipLevels,
    maxSize: maxSize,
  );

  @override
  Future<ui.Image> presentTextureAsImage(
    Texture texture, {
    bool transferOwnership = false,
  }) async => _textureToImageSync(texture as _WebGpuTexture);

  @override
  PixelFormat get reversedDepthStencilFormat =>
      context.reversedDepthStencilFormat;

  /// One buffer for both: WebGPU, unlike WebGL2, binds one buffer as vertices
  /// and indices alike. The index range starts 4-byte aligned, which every
  /// index format's offset rule accepts.
  @override
  ({DeviceBuffer vertex, DeviceBuffer index, int indexBaseOffset})
  createGeometryBuffers(int vertexBytes, int indexBytes) {
    final indexBaseOffset = _align4(vertexBytes);
    final buffer = _WebGpuDeviceBuffer.geometry(
      context,
      indexBaseOffset + indexBytes,
    );
    return (vertex: buffer, index: buffer, indexBaseOffset: indexBaseOffset);
  }

  @override
  bool writeGeometryData(
    DeviceBuffer buffer,
    TypedData source, {
    required int destinationOffsetInBytes,
  }) =>
      (buffer as _WebGpuDeviceBuffer)._write(source, destinationOffsetInBytes);

  @override
  Surface createSurface({required int width, required int height}) =>
      _WebGpuSurface(WebGpuPresenter(context.device), width, height);
}
