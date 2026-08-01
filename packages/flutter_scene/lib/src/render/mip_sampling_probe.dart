import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

// ignore: implementation_imports
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/shaders.dart';
import 'package:vector_math/vector_math.dart';

/// Whether hand-uploaded mip chains sample correctly on this device, measured
/// by [probePlatformMipSampling]. Null until the probe runs (or where it does
/// not apply).
bool? platformMipSamplingWorks;

/// Whether uploading a mip chain is worth anything on this device.
///
/// False only where the probe positively measured the sampler clamp, so the
/// levels above the base would be transcoded, uploaded, and then never read.
/// A probe that could not run leaves this true, since skipping mips on a
/// healthy device would be a real quality regression.
bool get mipChainsAreSampled => platformMipSamplingWorks != false;

/// Measures whether mip sampling actually works, on platforms where the
/// backend capability bits are known to over-report it.
///
/// Android engines clamp every Vulkan sampler to the base mip level on Adreno
/// GPUs while still reporting mipmap support, which silently breaks any
/// content that relies on a hand-uploaded mip chain
/// (https://github.com/flutter/flutter/issues/161283). The probe measures the
/// defect itself instead of guessing from the GPU name, so unaffected devices
/// keep full mip support and the fallback retires on its own once fixed
/// engines reach users
/// (https://github.com/flutter/flutter/pull/190264).
///
/// Runs during `Scene.initializeStaticResources`. On other platforms (and on
/// web) the capability bits are trusted and no probe runs.
Future<void> probePlatformMipSampling() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  if (!gpu.gpuContext.doesSupportManuallyMippedTextures) {
    return;
  }
  try {
    platformMipSamplingWorks = await measureMipSampling();
  } catch (error) {
    // Leave the result unknown rather than asserting the defect. Radiance
    // layout selection already treats unknown as broken (the atlas works
    // everywhere), while [mipChainsAreSampled] stays true, so a probe that
    // could not run never costs a healthy device its mipmaps.
    debugPrint('flutter_scene: mip sampling probe failed: $error');
    return;
  }
  if (platformMipSamplingWorks == false) {
    debugPrint(
      'flutter_scene: this device samples every texture at its base mip, so '
      'mipmaps are skipped and minified textures will alias. Cooked mip '
      'chains are not uploaded, and image based lighting uses the radiance '
      'atlas. See https://github.com/flutter/flutter/issues/189965',
    );
  }
}

// Two triangles of NDC positions covering the whole render target (6 vec2s).
final gpu.BufferView _fullscreenQuadView = gpu.BufferView(
  gpu.gpuContext.createDeviceBufferWithCopy(
    ByteData.sublistView(
      Float32List.fromList(<double>[
        -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
        -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
      ]),
    ),
  ),
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

/// Renders a white-base, black-mips texture at a heavy minification and
/// returns whether the sampled result read the mip chain.
///
/// Requires the base shader library to be loaded. Exposed for tests; use
/// [probePlatformMipSampling] to apply the platform gating.
@visibleForTesting
Future<bool> measureMipSampling() async {
  // A 32x32 source with a white base level and black upper levels.
  const size = 32;
  final source = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    size,
    size,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    mipLevelCount: 5,
  );
  for (var mip = 0; mip < 5; mip++) {
    final mipSize = size >> mip;
    final pixels = Uint8List(mipSize * mipSize * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = pixels[i + 1] = pixels[i + 2] = mip == 0 ? 255 : 0;
      pixels[i + 3] = 255;
    }
    source.overwrite(ByteData.sublistView(pixels), mipLevel: mip);
  }

  // Drawing the full source into a 4x4 target minifies by 8x, so a mipping
  // sampler reads deep (black) levels while a base-clamped sampler reads
  // white.
  final target = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    4,
    4,
    format: gpu.PixelFormat.r8g8b8a8UNormInt,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['CopyFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: target, clearValue: Vector4.zero()),
    ),
  );
  renderPass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  bindVertexBufferCompat(renderPass, _fullscreenQuadView, 6);
  renderPass.bindTexture(
    fragmentShader.getUniformSlot('source_texture'),
    source,
    sampler: gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      mipFilter: gpu.MipFilter.linear,
    ),
  );
  drawCompat(renderPass, 6);
  rendererSubmissions.submit(commandBuffer);

  final ui.Image image = target.asImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (bytes == null) {
    throw StateError('Could not read back the mip sampling probe target.');
  }
  // Sample the center texel; mid-gray or darker means the chain was read.
  final center = (4 * 2 + 2) * 4;
  return bytes.getUint8(center) < 128;
}
