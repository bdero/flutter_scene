import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/gpu/render_pass_compat.dart';
import 'package:vector_math/vector_math.dart';

import 'package:flutter_scene/src/shaders.dart';
import 'package:flutter_scene/src/render/frame_transients.dart';
import 'package:flutter_scene/src/render/radiance_layout.dart';
import 'package:flutter_scene/src/scene_encoder.dart' show resolvePipeline;
import 'package:flutter_scene/src/gpu/raster_sync.dart';

// The layout constants and the cube face bases live in radiance_layout.dart so
// the pure-Dart importer can share them without pulling in the GPU.
export 'package:flutter_scene/src/render/radiance_layout.dart'
    show
        kMinRadianceCubeSize,
        kPrefilterBandCount,
        kPrefilterBandHeight,
        kPrefilterBandWidth,
        kRadianceCubeSize,
        radianceBandRoughness,
        radianceCubeFaceCoords,
        radianceCubeFaceDirection;

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

/// Creates an empty prefiltered-radiance cube (one roughness band per mip
/// level), for [prefilterEquirectRadianceToCube] and incremental cube bakes.
/// [size] is the base-mip face size (default [kRadianceCubeSize]), clamped up to
/// [kMinRadianceCubeSize] so the [kPrefilterBandCount] mip bands always fit.
gpu.Texture createRadianceCubeTexture({int size = kRadianceCubeSize}) =>
    gpu.gpuContext.createTexture(
      gpu.StorageMode.devicePrivate,
      size < kMinRadianceCubeSize ? kMinRadianceCubeSize : size,
      size < kMinRadianceCubeSize ? kMinRadianceCubeSize : size,
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
///
/// The result is exactly what `EnvironmentMap.fromGpuTextures` expects for the
/// cube layout, and what `EnvironmentMap.fromKtx2Bytes` reproduces from a
/// pre-baked file. [sourceEquirect] is sRGB-encoded unless [sourceIsLinear].
///
/// Prefer [prefilterEquirectRadianceToCubeProgressive] from an asynchronous
/// load: submitting all `6 * kPrefilterBandCount` passes at once hands the
/// driver one very large batch, which on some Android GLES stacks stalls the
/// display pipeline for hundreds of milliseconds.
/// {@category Lighting and environment}
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

/// Prefilters [sourceEquirect] for image-based specular lighting like
/// [prefilterEquirectRadiance], but returns the atlas immediately and fills
/// its roughness bands in over the following frames.
///
/// The one-shot form hands the driver the whole prefilter as a single draw:
/// with the legacy atlas that is `kPrefilterBandWidth` x
/// `kPrefilterBandHeight * kPrefilterBandCount` texels, each running the
/// shader's `kPrefilterSamples`-tap GGX loop. Measured on a Mali-G57 (Galaxy
/// A16, Impeller GLES) that single draw is ~850 ms of GPU time, and because it
/// is flushed inside a Flutter frame, that frame's buffer never completes: the
/// raster thread blocks in `eglSwapBuffers`, SurfaceFlinger and the vendor
/// composer wait on the buffer's fence, and the display only recovers on the
/// driver's ~880 ms `QUEUE_BUFFER_TIMEOUT`. Every environment an app builds
/// costs it the better part of a second of frozen screen.
///
/// Here each band is its own draw (~1/8 the sample work), paced one per frame.
/// The same total GPU work, but the display keeps presenting while it happens
/// and it overlaps whatever else the app is still loading. Band 0 is submitted
/// before returning, so the atlas is never entirely unwritten; the rest arrive
/// over the next [kPrefilterBandCount] - 1 frames, which is invisible while a
/// scene is still loading and reads as the specular sharpening up otherwise.
/// {@category Lighting and environment}
gpu.Texture prefilterEquirectRadianceProgressive(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  bool mipLayout = false,
}) {
  final atlas = createPrefilterAtlasTexture(mipLayout: mipLayout);
  _prefilterBand(sourceEquirect, atlas, 0, mipLayout, sourceIsLinear);
  unawaited(
    _prefilterRemainingBands(
      sourceEquirect,
      atlas,
      mipLayout: mipLayout,
      sourceIsLinear: sourceIsLinear,
    ),
  );
  return atlas;
}

Future<void> _prefilterRemainingBands(
  gpu.Texture sourceEquirect,
  gpu.Texture atlas, {
  required bool mipLayout,
  required bool sourceIsLinear,
}) async {
  for (var band = 1; band < kPrefilterBandCount; band++) {
    await awaitFrame();
    _prefilterBand(sourceEquirect, atlas, band, mipLayout, sourceIsLinear);
  }
}

void _prefilterBand(
  gpu.Texture sourceEquirect,
  gpu.Texture atlas,
  int band,
  bool mipLayout,
  bool sourceIsLinear,
) => _prefilterPass(
  sourceEquirect,
  atlas,
  band: band,
  // The mip layout owns a whole mip level per band, so every pass clears its
  // own. The legacy atlas shares one image between the bands: only the first
  // pass may clear it, the rest load it back.
  clear: mipLayout || band == 0,
  sourceIsLinear: sourceIsLinear,
);

/// Prefilters [sourceEquirect] into a roughness-mip cubemap like
/// [prefilterEquirectRadianceToCube], but returns the cube immediately and
/// fills it a face at a time over the following frames, for the same reason
/// [prefilterEquirectRadianceProgressive] does: all `6 * kPrefilterBandCount`
/// passes in one submission is more than a mobile display pipeline can absorb
/// between presents. Face 0 is submitted before returning.
/// {@category Lighting and environment}
gpu.Texture prefilterEquirectRadianceToCubeProgressive(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  int size = kRadianceCubeSize,
}) {
  final cube = createRadianceCubeTexture(size: size);
  _prefilterCubeFace(sourceEquirect, cube, 0, sourceIsLinear);
  unawaited(
    (() async {
      for (var face = 1; face < 6; face++) {
        await awaitFrame();
        _prefilterCubeFace(sourceEquirect, cube, face, sourceIsLinear);
      }
    })(),
  );
  return cube;
}

void _prefilterCubeFace(
  gpu.Texture sourceEquirect,
  gpu.Texture cube,
  int face,
  bool sourceIsLinear,
) {
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
  final (right, up, forward) = cubeFaceBases[face];
  final roughness = radianceBandRoughness(band);
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
  renderPass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
  bindVertexBufferCompat(renderPass, _fullscreenQuadView, 6);
  renderPass.bindTexture(
    fragmentShader.getUniformSlot('source_equirect'),
    sourceEquirect,
    sampler: gpu.SamplerOptions(
      minFilter: gpu.MinMagFilter.linear,
      magFilter: gpu.MinMagFilter.linear,
      // A linear mip filter so the shader's textureLod reads (and interpolates)
      // the source mip chain; inert when the source has a single level.
      mipFilter: gpu.MipFilter.linear,
      widthAddressMode: gpu.SamplerAddressMode.repeat,
      heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
    ),
  );
  // PrefilterCubeInfo: three vec4 bases + (roughness, source_is_linear,
  // source_width, source_height, source_max_lod) padded to std140 (80 bytes /
  // 20 floats). source_max_lod is the source's top mip level (0 when it has no
  // mip chain), so the shader's lod clamp falls back to the base level.
  final info = Float32List(20)
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
    ..[13] = sourceIsLinear ? 1.0 : 0.0
    ..[14] = sourceEquirect.width.toDouble()
    ..[15] = sourceEquirect.height.toDouble()
    ..[16] = (sourceEquirect.mipLevelCount - 1).toDouble();
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterCubeInfo'),
    uniformTransients.emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  rendererSubmissions.submit(commandBuffer);
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
  renderPass.bindPipeline(resolvePipeline(vertexShader, fragmentShader));
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
    uniformTransients.emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  rendererSubmissions.submit(commandBuffer);
}
