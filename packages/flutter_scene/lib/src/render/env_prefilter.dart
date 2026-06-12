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
//    ~32. Unblocked: textureLod compiles on every backend dialect now and
//    mip levels can be rendered to or uploaded; the remaining work is
//    building the source mip chain and the cone-angle-to-lod mapping.
//  - A prefiltered cubemap instead of the equirect: removes the pole
//    distortion (smearing on near-vertical reflections) and the
//    resolution ceiling. Render-to-slice and mipmapped textures make this
//    possible now (https://github.com/flutter/flutter/issues/145027).
/// Prefilters an equirectangular radiance texture for image-based
/// specular lighting.
///
/// Renders [kPrefilterBandCount] GGX-prefiltered roughness bands (see
/// `flutter_scene_prefilter_env.frag`). With [mipLayout] (the default
/// layout new environments use, see `EnvironmentMap.useMipRadianceLayout`)
/// the bands are the mip levels of one equirect texture, sampled with
/// hardware trilinear `textureLod`; otherwise the bands are stacked
/// vertically into the legacy atlas. Intended to run once when an
/// `EnvironmentMap` is constructed; the result is cached on the
/// environment and sampled at draw time by the standard shader's
/// `SamplePrefilteredRadiance`.
///
/// [sourceEquirect] is an equirectangular radiance map. By default it is
/// treated as sRGB-encoded; pass [sourceIsLinear] when it already holds
/// linear radiance (an HDR environment), so it is not linearized twice.
/// The result always stores linear radiance.
/// {@category Lighting and environment}
gpu.Texture prefilterEquirectRadiance(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  bool mipLayout = false,
}) {
  final atlas = createPrefilterAtlasTexture(mipLayout: mipLayout);
  if (mipLayout) {
    for (var band = 0; band < kPrefilterBandCount; band++) {
      _prefilterPass(
        sourceEquirect,
        atlas,
        band: band,
        clear: true,
        sourceIsLinear: sourceIsLinear,
      );
    }
  } else {
    _prefilterPass(
      sourceEquirect,
      atlas,
      band: -1,
      clear: true,
      sourceIsLinear: sourceIsLinear,
    );
  }
  return atlas;
}

/// Creates an empty prefiltered-radiance render target, for incremental
/// prefiltering via [prefilterEquirectRadianceBand].
///
/// With [mipLayout], an equirect with one mip level per roughness band;
/// otherwise the legacy stacked-band atlas.
gpu.Texture createPrefilterAtlasTexture({bool mipLayout = false}) {
  if (mipLayout) {
    return gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      kPrefilterBandWidth,
      kPrefilterBandHeight,
      format: gpu.PixelFormat.r16g16b16a16Float,
      mipLevelCount: kPrefilterBandCount,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
  }
  return gpu.gpuContext.createTexture(
    gpu.StorageMode.devicePrivate,
    kPrefilterBandWidth,
    kPrefilterBandHeight * kPrefilterBandCount,
    format: gpu.PixelFormat.r16g16b16a16Float,
    enableRenderTargetUsage: true,
    enableShaderReadUsage: true,
  );
}

/// Prefilters a single roughness [band] of [atlas] from [sourceEquirect],
/// preserving the other bands.
///
/// The atlas's layout is detected from its mip count (see
/// [createPrefilterAtlasTexture]): a mip-layout target renders the band
/// into mip level [band]; the legacy atlas discards texels outside the
/// band before the sample loop. Either way one band costs roughly
/// `1/kPrefilterBandCount` of the full prefilter, so an incremental bake
/// can spread the work across frames, one band per frame. The result is
/// complete only once every band has been written.
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
    clear: atlas.mipLevelCount > 1,
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
  // With a mip-layout target, each band renders into its own mip level
  // and covers the whole render area (no atlas math, no discard).
  final mipLayout = atlas.mipLevelCount > 1;
  assert(!mipLayout || band >= 0, 'Mip-layout prefilters render per band');
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      clear
          ? gpu.ColorAttachment(
              texture: atlas,
              clearValue: Vector4.zero(),
              mipLevel: mipLayout ? band : 0,
            )
          : gpu.ColorAttachment(
              texture: atlas,
              loadAction: gpu.LoadAction.load,
              mipLevel: mipLayout ? band : 0,
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
  // Three floats (std140-padded to 16 bytes): the sRGB-vs-linear flag, the
  // band index (negative computes the whole legacy atlas in one pass), and
  // the whole-target flag (mip layout, the band covers the render area).
  final info = Float32List(4)
    ..[0] = sourceIsLinear ? 1.0 : 0.0
    ..[1] = band.toDouble()
    ..[2] = mipLayout ? 1.0 : 0.0;
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterInfo'),
    gpu.gpuContext.createHostBuffer().emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  commandBuffer.submit();
}
