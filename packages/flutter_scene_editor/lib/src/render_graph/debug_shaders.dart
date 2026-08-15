/// The editor's debug shader bundle (display remap for the render graph
/// inspector and the viewport debug-output modes), compiled by this
/// package's build hook and loaded once at editor startup.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;

/// The data-asset key the build hook registers the bundle under.
const String _kBundleKey =
    'packages/flutter_scene_editor/flutter_gpu_shaders/shaderbundles/'
    'editor_debug.shaderbundle';

gpu.ShaderLibrary? _library;

/// Loads the editor debug shader bundle. Idempotent; call once at startup
/// after `Scene.initializeStaticResources`. Throws with a pointer at the
/// data-assets flag when the bundle asset is missing.
Future<void> loadEditorDebugShaders() async {
  if (_library != null) return;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  if (!manifest.listAssets().contains(_kBundleKey)) {
    throw StateError(
      'The editor debug shader bundle is missing. Build with Dart data '
      'assets enabled (flutter config --enable-dart-data-assets).',
    );
  }
  _library = await gpu.loadShaderLibraryAsync(_kBundleKey);
}

/// Whether [loadEditorDebugShaders] has completed.
bool get editorDebugShadersLoaded => _library != null;

gpu.Shader get _vertex => _library!['EditorFullscreenVertex']!;
gpu.Shader get _remapFragment => _library!['EditorDebugRemapFragment']!;

/// How [remapToImage] turns a source texture into display pixels; mirrors
/// the RemapInfo uniform block in editor_debug_remap.frag.
class RemapSettings {
  const RemapSettings({
    this.mode = RemapMode.color,
    this.channel = 0,
    this.blackPoint = 0,
    this.whitePoint = 1,
    this.exposure = 1,
    this.near = 0,
    this.far = 50,
    this.highlightNonFinite = false,
  });

  final RemapMode mode;

  /// Channel index for [RemapMode.singleChannel].
  final int channel;

  final double blackPoint;
  final double whitePoint;
  final double exposure;

  /// Depth normalization window for [RemapMode.depth].
  final double near;
  final double far;

  /// NaN magenta, Inf yellow, negative blue.
  final bool highlightNonFinite;

  RemapSettings copyWith({
    RemapMode? mode,
    int? channel,
    double? blackPoint,
    double? whitePoint,
    double? exposure,
    double? near,
    double? far,
    bool? highlightNonFinite,
  }) => RemapSettings(
    mode: mode ?? this.mode,
    channel: channel ?? this.channel,
    blackPoint: blackPoint ?? this.blackPoint,
    whitePoint: whitePoint ?? this.whitePoint,
    exposure: exposure ?? this.exposure,
    near: near ?? this.near,
    far: far ?? this.far,
    highlightNonFinite: highlightNonFinite ?? this.highlightNonFinite,
  );

  /// A sensible default per resource key; everything else displays as
  /// clamped color.
  static RemapSettings defaultsFor(gpu.PixelFormat? format, String key) {
    if (key.contains('linear_depth')) {
      return const RemapSettings(mode: RemapMode.depth, near: 0, far: 50);
    }
    if (key.contains('shadow')) {
      return const RemapSettings(mode: RemapMode.singleChannel, channel: 0);
    }
    return const RemapSettings(mode: RemapMode.color);
  }
}

/// The remap shader's display transforms.
enum RemapMode { color, singleChannel, depth, octahedralNormal }

/// Packs the RemapInfo std140 block; [weight] blends over the chain color
/// when used as a viewport pass (always 1 for offline conversion).
ByteData packRemapInfo(RemapSettings settings, {double weight = 1}) {
  final f = Float32List(12)
    ..[0] = settings.blackPoint
    ..[1] = settings.whitePoint
    ..[2] = settings.exposure
    ..[3] = settings.mode.index.toDouble()
    ..[4] = settings.channel.toDouble()
    ..[8] = settings.highlightNonFinite ? 1.0 : 0.0
    ..[9] = settings.near
    ..[10] = settings.far
    ..[11] = weight;
  return ByteData.sublistView(f);
}

final gpu.DeviceBuffer _quadBuffer = gpu.gpuContext.createDeviceBufferWithCopy(
  ByteData.sublistView(
    Float32List.fromList(<double>[
      -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
      -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
    ]),
  ),
);

gpu.SamplerOptions _samplerFor(gpu.PixelFormat format) {
  // fp32 filtering is an optional GL extension; point-sample those.
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

/// The editor's remap shader, for wiring into a viewport debug pass.
gpu.Shader get editorRemapFragment => _remapFragment;

/// Renders [source] through the display remap into an RGBA8 target and
/// returns it as a [ui.Image] (synchronously; `asImage` is sync on native
/// and the web shim).
ui.Image remapToImage(gpu.Texture source, RemapSettings settings) {
  final target = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    source.width,
    source.height,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(gpu.ColorAttachment(texture: target)),
  );
  final fragment = _remapFragment;
  renderPass.bindPipeline(resolvePipeline(_vertex, fragment));
  renderPass.setDepthWriteEnable(false);
  renderPass.setDepthCompareOperation(gpu.CompareFunction.always);
  renderPass.setColorBlendEnable(false);
  renderPass.setCullMode(gpu.CullMode.none);
  bindVertexBufferCompat(
    renderPass,
    gpu.BufferView(_quadBuffer, offsetInBytes: 0, lengthInBytes: 6 * 2 * 4),
    6,
  );
  final sampler = _samplerFor(source.format);
  renderPass.bindTexture(
    fragment.getUniformSlot('source_texture'),
    source,
    sampler: sampler,
  );
  renderPass.bindTexture(
    fragment.getUniformSlot('input_color'),
    source,
    sampler: sampler,
  );
  final info = gpu.gpuContext.createDeviceBufferWithCopy(
    packRemapInfo(settings),
  );
  renderPass.bindUniform(
    fragment.getUniformSlot('RemapInfo'),
    gpu.BufferView(
      info,
      offsetInBytes: 0,
      lengthInBytes: packRemapInfo(settings).lengthInBytes,
    ),
  );
  drawCompat(renderPass, 6);
  commandBuffer.submit();
  return target.asImage();
}

/// Reads exact float RGBA values back from [source].
///
/// Returns null when the platform cannot produce float pixels from this
/// texture (`toByteData(rawExtendedRgba128Float)` support is
/// backend-dependent); callers degrade to "values unavailable".
Future<Float32List?> readbackFloats(gpu.Texture source) async {
  final image = source.asImage();
  try {
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawExtendedRgba128,
    );
    if (data == null) return null;
    return data.buffer.asFloat32List(
      data.offsetInBytes,
      data.lengthInBytes ~/ 4,
    );
  } catch (_) {
    return null;
  } finally {
    image.dispose();
  }
}
