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

/// A radiance prefilter whose passes are still being submitted over frames.
///
/// [texture] is usable immediately, holding the first band (or face) and
/// nothing else; the rest arrive over the following frames and [done]
/// completes once every pass has been submitted. [cancel] stops the fill,
/// for a caller that has replaced the texture and no longer wants the
/// remaining work.
class RadiancePrefilterFill {
  RadiancePrefilterFill._(this.texture);

  /// Wraps a radiance texture that is already complete, so a caller that does
  /// not pace its prefilter still hands back the same type.
  RadiancePrefilterFill.completed(this.texture) {
    _done.complete();
  }

  /// The radiance texture, valid from construction and refined as the fill
  /// proceeds.
  final gpu.Texture texture;

  final Completer<void> _done = Completer<void>();
  final FramePacer _pacer = FramePacer();
  bool _cancelled = false;
  bool _counted = false;

  /// Completes once every pass has been submitted, or immediately on
  /// [cancel]. Never completes with an error.
  Future<void> get done => _done.future;

  /// Whether the fill has finished or been cancelled.
  bool get isComplete => _done.isCompleted;

  /// Stops submitting further passes.
  ///
  /// The texture keeps whatever has landed so far. Called when an environment
  /// replaces its radiance before the fill finishes (the web warm-context
  /// re-bake), so the abandoned texture stops consuming GPU time.
  void cancel() {
    _cancelled = true;
    _settle();
  }

  void _settle() {
    if (_counted) {
      _counted = false;
      _pendingRadianceFills--;
    }
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  /// Completes [done] once the raster thread is past the final submission.
  ///
  /// `CommandBuffer.submit` only queues the draw on the OpenGL ES backend, so
  /// completing as the loop ends would let a caller that awaited [done] read
  /// the texture back, or capture a frame, while the last band is still
  /// unencoded.
  Future<void> _finishAfterRaster() async {
    await awaitRasterThread();
    _settle();
  }

  void _track() {
    _counted = true;
    _pendingRadianceFills++;
  }
}

int _pendingRadianceFills = 0;

/// Whether any environment is still filling its radiance over frames.
///
/// A progressive fill needs a few frames of pacing to converge, so a caller
/// that has to photograph the finished environment (a golden capture, a still
/// for export) pumps frames until this goes false rather than forcing the
/// prefilter into one submission, which is the stall the pacing avoids.
bool get radiancePrefilterPending => _pendingRadianceFills > 0;

/// Prefilters [sourceEquirect] for image-based specular lighting like
/// [prefilterEquirectRadiance], but returns as soon as the atlas exists and
/// fills its roughness bands in over the following frames.
///
/// The one-shot form hands the driver the whole prefilter as a single draw:
/// with the legacy atlas that is `kPrefilterBandWidth` x
/// `kPrefilterBandHeight * kPrefilterBandCount` texels, each running the
/// shader's `kPrefilterSamples`-tap GGX loop. Measured on a Mali-G57 (Galaxy
/// A16, Impeller GLES) that single draw is ~850 ms of GPU time, and because it
/// is flushed inside a Flutter frame, that frame's buffer never completes. The
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
///
/// Prefer [prefilterEquirectRadiance] where the atlas must be complete on
/// return, such as an offline bake or a readback.
RadiancePrefilterFill prefilterEquirectRadianceProgressive(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  bool mipLayout = false,
}) {
  final fill = RadiancePrefilterFill._(
    createPrefilterAtlasTexture(mipLayout: mipLayout),
  ).._track();
  // Seed every band with the mirror before returning. At roughness 0 the GGX
  // lobe is a delta, so a band costs one fetch instead of kPrefilterSamples,
  // and the whole seed is roughly 1/kPrefilterSamples of one real band. A
  // frame that samples the atlas while it is still filling then reads a sharp
  // environment rather than the clear color, which is the difference between
  // specular that is too crisp for a frame or two and specular that is black.
  for (var band = 0; band < kPrefilterBandCount; band++) {
    _prefilterBand(
      sourceEquirect,
      fill.texture,
      band,
      mipLayout,
      sourceIsLinear,
      // Only the first pass may clear the legacy atlas; the rest share the
      // image and load it back. Every mip-layout band owns its own level.
      clear: mipLayout || band == 0,
      forceMirror: true,
    );
  }
  // Band 0 is the mirror, so its seed is already the final value.
  unawaited(
    _fillBands(
      fill,
      sourceEquirect,
      mipLayout: mipLayout,
      sourceIsLinear: sourceIsLinear,
    ),
  );
  return fill;
}

Future<void> _fillBands(
  RadiancePrefilterFill fill,
  gpu.Texture sourceEquirect, {
  required bool mipLayout,
  required bool sourceIsLinear,
}) async {
  for (var band = 1; band < kPrefilterBandCount; band++) {
    await fill._pacer.awaitFrame();
    if (fill._cancelled) {
      return;
    }
    _prefilterBand(
      sourceEquirect,
      fill.texture,
      band,
      mipLayout,
      sourceIsLinear,
      clear: mipLayout,
    );
  }
  await fill._finishAfterRaster();
}

void _prefilterBand(
  gpu.Texture sourceEquirect,
  gpu.Texture atlas,
  int band,
  bool mipLayout,
  bool sourceIsLinear, {
  required bool clear,
  bool forceMirror = false,
}) => _prefilterPass(
  sourceEquirect,
  atlas,
  band: band,
  clear: clear,
  sourceIsLinear: sourceIsLinear,
  forceMirror: forceMirror,
);

/// Prefilters [sourceEquirect] into a roughness-mip cubemap like
/// [prefilterEquirectRadianceToCube], but returns as soon as the cube exists
/// and fills it a face at a time over the following frames, for the same
/// reason [prefilterEquirectRadianceProgressive] does: all
/// `6 * kPrefilterBandCount` passes in one submission is more than a mobile
/// display pipeline can absorb between presents. Face 0 is submitted before
/// returning.
RadiancePrefilterFill prefilterEquirectRadianceToCubeProgressive(
  gpu.Texture sourceEquirect, {
  bool sourceIsLinear = false,
  int size = kRadianceCubeSize,
}) {
  final fill = RadiancePrefilterFill._(createRadianceCubeTexture(size: size))
    .._track();
  // Seed every face of every band with the mirror before returning, for the
  // reason prefilterEquirectRadianceProgressive does. A cube is sampled in
  // every direction at once, so seeding one face would leave five directions
  // reading the clear color; and the roughness a shader asks for picks a mip,
  // so seeding one band would leave the rest unwritten.
  for (var band = 0; band < kPrefilterBandCount; band++) {
    _prefilterCubeBand(
      sourceEquirect,
      fill.texture,
      band,
      sourceIsLinear,
      forceMirror: true,
    );
  }
  unawaited(_fillCubeBands(fill, sourceEquirect, sourceIsLinear));
  return fill;
}

Future<void> _fillCubeBands(
  RadiancePrefilterFill fill,
  gpu.Texture sourceEquirect,
  bool sourceIsLinear,
) async {
  // Band major, not face major: a band is a mip level across all six faces, so
  // finishing a band leaves the cube consistent in every direction at that
  // roughness. Face-major would sharpen one direction at a time.
  for (var band = 1; band < kPrefilterBandCount; band++) {
    await fill._pacer.awaitFrame();
    if (fill._cancelled) {
      return;
    }
    _prefilterCubeBand(sourceEquirect, fill.texture, band, sourceIsLinear);
  }
  await fill._finishAfterRaster();
}

void _prefilterCubeBand(
  gpu.Texture sourceEquirect,
  gpu.Texture cube,
  int band,
  bool sourceIsLinear, {
  bool forceMirror = false,
}) {
  for (var face = 0; face < 6; face++) {
    prefilterEquirectRadianceCubeFace(
      sourceEquirect,
      cube,
      face,
      band,
      sourceIsLinear: sourceIsLinear,
      forceMirror: forceMirror,
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
  bool forceMirror = false,
}) {
  assert(face >= 0 && face < 6);
  assert(band >= 0 && band < kPrefilterBandCount);
  final (right, up, forward) = cubeFaceBases[face];
  // Roughness 0 is the delta lobe the shader answers in one fetch, so a seed
  // pass costs a fraction of the real band it stands in for.
  final roughness = forceMirror ? 0.0 : radianceBandRoughness(band);
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
  bool forceMirror = false,
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
    ..[2] = mipLayout ? 1.0 : 0.0
    ..[3] = forceMirror ? 1.0 : 0.0;
  renderPass.bindUniform(
    fragmentShader.getUniformSlot('PrefilterInfo'),
    uniformTransients.emplace(ByteData.sublistView(info)),
  );
  drawCompat(renderPass, 6);
  rendererSubmissions.submit(commandBuffer);
}
