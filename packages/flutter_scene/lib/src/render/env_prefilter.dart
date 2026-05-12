import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/shaders.dart';

/// Number of roughness bands in a prefiltered-radiance atlas (band 0 =
/// mirror, band `kPrefilterBandCount - 1` = fully rough; band `i` covers
/// perceptual roughness `i / (kPrefilterBandCount - 1)`).
///
/// Must match `kPrefilterBands` in `shaders/texture.glsl`.
const int kPrefilterBandCount = 8;

/// Equirectangular width of a single roughness band in the atlas.
const int kPrefilterBandWidth = 512;

/// Equirectangular height of a single roughness band in the atlas.
///
/// Must match `kPrefilterBandHeight` in `shaders/texture.glsl`.
const int kPrefilterBandHeight = 256;

// Two triangles of NDC positions covering the whole render target (6 vec2s).
final gpu.DeviceBuffer _fullscreenQuad = gpu.gpuContext
    .createDeviceBufferWithCopy(
      ByteData.sublistView(
        Float32List.fromList(<double>[
          -1.0, -1.0, 1.0, -1.0, -1.0, 1.0, //
          -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, //
        ]),
      ),
    );
final gpu.BufferView _fullscreenQuadView = gpu.BufferView(
  _fullscreenQuad,
  offsetInBytes: 0,
  lengthInBytes: 6 * 2 * 4,
);

/// Prefilters an equirectangular radiance texture into a vertical
/// roughness-band atlas for image-based specular lighting.
///
/// Renders [kPrefilterBandCount] GGX-prefiltered equirectangular bands
/// stacked vertically into a single `r16g16b16a16Float` texture in one
/// full-screen GPU pass (see `flutter_scene_prefilter_env.frag`). Intended
/// to run once when an [EnvironmentMap] is constructed; the result is cached
/// on the environment and sampled at draw time by the standard shader's
/// `SamplePrefilteredRadiance`.
///
/// [sourceEquirect] is treated as an sRGB-encoded equirectangular radiance
/// map; the atlas stores linear radiance.
gpu.Texture prefilterEquirectRadiance(gpu.Texture sourceEquirect) {
  final atlas = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    kPrefilterBandWidth,
    kPrefilterBandHeight * kPrefilterBandCount,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );

  final fragmentShader = baseShaderLibrary['PrefilterEnvFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: atlas, clearValue: Vector4.zero()),
    ),
  );
  renderPass.bindPipeline(
    gpu.gpuContext.createRenderPipeline(
      baseShaderLibrary['FullscreenVertex']!,
      fragmentShader,
    ),
  );
  renderPass.bindVertexBuffer(_fullscreenQuadView, 6);
  renderPass.bindTexture(
    fragmentShader.getUniformSlot('source_equirect'),
    sourceEquirect,
    sampler: gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    ),
  );
  renderPass.draw();
  commandBuffer.submit();
  return atlas;
}
