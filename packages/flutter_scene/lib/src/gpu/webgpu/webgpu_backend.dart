/// The WebGPU implementation of the web GPU shim, selected with
/// `--dart-define=flutter_scene.webgpu=true`.
///
/// The device, context, buffers, textures, samplers, mip generation, shader
/// libraries from WGSL sidecars, and render pipelines work; passes and
/// present do not yet.
// TODO(webgpu-backend): implement command buffers and render passes, then
// present (see
// notes/web-backend/webgpu_web_backend_handoff.md in the development root).
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show FlutterError, debugPrint, kDebugMode, visibleForTesting;
import 'package:web/web.dart' as web;

import '../../generated_assets/generated_asset_fetch_web.dart';
import '../shared/encoded_image_types.dart';
import '../shared/gpu_sample_types.dart';
import '../shared/sidecar_hash.dart';
import '../shared/shader_library_sources.dart';
import '../shared/wgsl_bindings.dart' show parseWgslDeclarations;
import '../web/_gpu.dart';
import 'webgpu_device.dart';
import 'webgpu_interop.dart';

part 'buffer.dart';
part 'context.dart';
part 'encoded_image.dart';
part 'formats.dart';
part 'mips.dart';
part 'pipeline.dart';
part 'readback.dart';
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

Never _unimplemented(String what) => throw UnimplementedError(
  'The WebGPU backend does not implement $what yet. Build without '
  '--dart-define=flutter_scene.webgpu=true to use WebGL2.',
);

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
  }

  @override
  _WebGpuContext get context =>
      _context ??
      (throw StateError(
        'The WebGPU backend was used before initializeGpuBackend completed.',
      ));

  @override
  GpuHost get host => _unimplemented('GpuHost');

  @override
  Texture textureFromImage(GpuContext gpuContext, ui.Image image) =>
      _unimplemented('Texture.fromImage');

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
  }) => _unimplemented('presentTextureAsImage');

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
      _unimplemented('Surface');
}
