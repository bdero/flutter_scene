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

// TODO(bdero): Filtered importance sampling: sample a mip chain of the source
// (mapping each GGX sample's cone solid angle to a mip LOD) so a sample
// integrates an area instead of a point. That removes the residual sampling
// noise and lets kPrefilterSamples drop back to ~32. The remaining work is
// building the source mip chain and the cone-angle-to-lod mapping.
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

/// Default width (and height) of the prefiltered radiance cube's base mip.
/// Sizes the convolved reflection/ambient cube, not the visible background
/// (which samples the full-resolution source); see
/// `EnvironmentMap.radianceCubeSize`.
const int kRadianceCubeSize = 512;

// Cube face world bases (right, up, forward), in flutter_gpu cube slice order
// (+X, -X, +Y, -Y, +Z, -Z). A face texel at (u, v) (v measured top-down, as
// FullscreenVertex emits) maps to normalize(forward + (2u-1)*right +
// (2v-1)*up), the same direction the hardware samplerCube reads back, so a
// baked direction round-trips. Verified against rendered reflections.
final List<(Vector3, Vector3, Vector3)> _cubeFaceBases = [
  (Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(1, 0, 0)), // +X
  (Vector3(0, 0, 1), Vector3(0, -1, 0), Vector3(-1, 0, 0)), // -X
  (Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)), // +Y
  (Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)), // -Y
  (Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)), // +Z
  (Vector3(-1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), // -Z
];

/// Creates an empty prefiltered-radiance cube (one roughness band per mip
/// level), for [prefilterEquirectRadianceToCube] and incremental cube bakes.
/// [size] is the base-mip face size (default [kRadianceCubeSize]).
gpu.Texture createRadianceCubeTexture({int size = kRadianceCubeSize}) =>
    gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      size,
      size,
      format: gpu.PixelFormat.r16g16b16a16Float,
      textureType: gpu.TextureType.textureCube,
      mipLevelCount: kPrefilterBandCount,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );

/// Prefilters an equirectangular radiance source into a roughness-mip cubemap
/// (mip `i` = perceptual roughness `i/(kPrefilterBandCount-1)`), sampled at
/// draw time with `textureLod(samplerCube, dir, roughness * maxLod)`. Removes
/// the equirect pole singularity from the radiance reflections sample. [size]
/// is the base-mip face size.
gpu.Texture prefilterEquirectRadianceToCube(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  int size = kRadianceCubeSize,
}) {
  final cube = createRadianceCubeTexture(size: size);
  for (var face = 0; face < 6; face++) {
    for (var band = 0; band < kPrefilterBandCount; band++) {
      prefilterEquirectRadianceCubeFace(
        sourceEquirect,
        cube,
        face,
        band,
        sourceIsLinear: sourceIsLinear,
      );
    }
  }
  return cube;
}

/// Prefilters one [face] of one roughness [band] (mip level) of [cube] from
/// [sourceEquirect]. One pass; an incremental bake spreads the 6*bands passes
/// across frames.
void prefilterEquirectRadianceCubeFace(
  gpu.Texture sourceEquirect,
  gpu.Texture cube,
  int face,
  int band, {
  bool sourceIsLinear = false,
}) {
  assert(face >= 0 && face < 6);
  assert(band >= 0 && band < kPrefilterBandCount);
  final (right, up, forward) = _cubeFaceBases[face];
  final roughness = band / (kPrefilterBandCount - 1);
  final vertexShader = baseShaderLibrary['FullscreenVertex']!;
  final fragmentShader = baseShaderLibrary['PrefilterRadianceCubeFragment']!;
  final commandBuffer = gpu.gpuContext.createCommandBuffer();
  final renderPass = commandBuffer.createRenderPass(
    gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(
        texture: cube,
        clearValue: Vector4.zero(),
        mipLevel: band,
        slice: face,
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
  // PrefilterCubeInfo: three vec4 bases + (roughness, source_is_linear) padded
  // to std140 (64 bytes / 16 floats).
  final info = Float32List(16)
    ..[0] = right.x
    ..[1] = right.y
    ..[2] = right.z
    ..[4] = up.x
    ..[5] = up.y
    ..[6] = up.z
    ..[8] = forward.x
    ..[9] = forward.y
    ..[10] = forward.z
    ..[12] = roughness
    ..[13] = sourceIsLinear ? 1.0 : 0.0;
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterCubeInfo'),
    gpu.gpuContext.createHostBuffer().emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  commandBuffer.submit();
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
