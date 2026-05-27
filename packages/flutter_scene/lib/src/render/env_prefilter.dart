import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
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

// TODO(bdero): Prefilter-quality follow-ups, roughly in priority order:
//  - Filtered importance sampling: sample a mip chain of the source
//    equirect (mapping each GGX sample's cone solid angle to a mip LOD)
//    so a sample integrates an area instead of a point. That removes the
//    residual sampling noise and lets kPrefilterSamples drop back to
//    ~32. Blocked on two Flutter GPU gaps worth upstreaming: `textureLod`
//    is unavailable in the shader dialect (see `SampleEnvironmentTextureLod`
//    in texture.glsl), and there is no API to generate or upload texture
//    mip levels.
//  - A prefiltered cubemap instead of this equirectangular atlas: removes
//    the pole distortion (smearing on near-vertical reflections) and the
//    resolution ceiling. Needs mipmapped cubemap texture support in
//    Flutter GPU (https://github.com/flutter/flutter/issues/145027).
//  - A mip-style atlas: one large sharp band plus progressively smaller
//    rough bands, rather than equal-size bands, so mirror reflections get
//    real resolution without bloating the rough bands.
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
/// [sourceEquirect] is an equirectangular radiance map. By default it is
/// treated as sRGB-encoded; pass [sourceIsLinear] when it already holds
/// linear radiance (an HDR environment), so it is not linearized twice.
/// The atlas always stores linear radiance.
gpu.Texture prefilterEquirectRadiance(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
}) {
  final atlas = gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    kPrefilterBandWidth,
    kPrefilterBandHeight * kPrefilterBandCount,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );

  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['PrefilterEnvFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: atlas, clearValue: Vector4.zero()),
    ),
  );
  renderPass.bindPipeline(
    gpu.gpuContext.createRenderPipeline(vertexShader, fragmentShader),
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
  // A single float (std140-padded to 16 bytes): the sRGB-vs-linear flag.
  final info = Float32List(4)..[0] = sourceIsLinear ? 1.0 : 0.0;
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterInfo'),
    gpu.gpuContext.createHostBuffer().emplace(ByteData.sublistView(info)),
  );
  renderPass.draw();
  commandBuffer.submit();
  return atlas;
}
