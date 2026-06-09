import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
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
  final atlas = createPrefilterAtlasTexture();
  _prefilterPass(
    sourceEquirect,
    atlas,
    band: -1,
    clear: true,
    sourceIsLinear: sourceIsLinear,
  );
  return atlas;
}

/// Creates an empty roughness-band atlas render target, for incremental
/// prefiltering via [prefilterEquirectRadianceBand].
gpu.Texture createPrefilterAtlasTexture() {
  return gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    kPrefilterBandWidth,
    kPrefilterBandHeight * kPrefilterBandCount,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
    coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture,
  );
}

/// Prefilters a single roughness [band] of [atlas] from [sourceEquirect],
/// preserving the other bands.
///
/// One band costs roughly `1/kPrefilterBandCount` of the full prefilter
/// (texels outside the band discard before the sample loop), so an
/// incremental bake can spread the atlas across frames, one band per frame.
/// The atlas holds a complete result only once every band has been written.
void prefilterEquirectRadianceBand(
  gpu.Texture sourceEquirect,
  gpu.Texture atlas,
  int band, {
  bool sourceIsLinear = false,
}) {
  assert(band >= 0 && band < kPrefilterBandCount);
  _prefilterPass(
    sourceEquirect,
    atlas,
    band: band,
    clear: false,
    sourceIsLinear: sourceIsLinear,
  );
}

void _prefilterPass(
  gpu.Texture sourceEquirect,
  gpu.Texture atlas, {
  required int band,
  required bool clear,
  required bool sourceIsLinear,
}) {
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['PrefilterEnvFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      clear
          ? gpu.ColorAttachment(texture: atlas, clearValue: Vector4.zero())
          : gpu.ColorAttachment(
              texture: atlas,
              loadAction: gpu.LoadAction.load,
            ),
    ),
  );
  renderPass.bindPipeline(
    gpu.gpuContext.createRenderPipeline(vertexShader, fragmentShader),
  );
  bindVertexBufferCompat(renderPass, _fullscreenQuadView, 6);
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
  // Two floats (std140-padded to 16 bytes): the sRGB-vs-linear flag and the
  // band index (negative computes the whole atlas in one pass).
  final info = Float32List(4)
    ..[0] = sourceIsLinear ? 1.0 : 0.0
    ..[1] = band.toDouble();
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterInfo'),
    gpu.gpuContext.createHostBuffer().emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  commandBuffer.submit();
}
