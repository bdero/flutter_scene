import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/asset_helpers.dart';
import 'package:flutter_scene/src/material/diffuse_sh.dart';
import 'package:flutter_scene/src/material/equirect_image.dart';
import 'package:flutter_scene/src/material/ibl_ktx2.dart';
import 'package:flutter_scene/src/material/material.dart';
import 'package:flutter_scene/src/render/env_prefilter.dart';
import 'package:flutter_scene/src/render/mip_sampling_probe.dart';
import 'package:flutter_scene/src/render/sky_bake.dart';
import 'package:flutter_scene/src/skybox.dart';
import 'package:flutter_scene/src/texture/half_float.dart';
import 'package:vector_math/vector_math.dart';

/// A source of image-based lighting: diffuse irradiance plus prefiltered
/// specular radiance, both derived from an equirectangular environment.
///
/// Diffuse is stored as 9 L2 spherical-harmonic RGB coefficients (cheap,
/// no texture fetch, seam-free); specular is a GPU-prefiltered "PMREM"
/// roughness-band atlas (see [prefilterEquirectRadiance]). Both are
/// computed up front, so constructing an environment from images does GPU
/// work and is best done once.
///
/// Construct one with [EnvironmentMap.fromEquirectImageAsset] /
/// [EnvironmentMap.fromEquirectImageBytes] (which detect HDR, EXR, or sRGB
/// sources and compute the SH and prefilter the radiance for you),
/// [EnvironmentMap.studio] (the built-in procedural default),
/// [EnvironmentMap.constantDiffuse] for uniform ambient radiance with black
/// reflections,
/// [EnvironmentMap.fromKtx2Bytes] / [EnvironmentMap.fromKtx2Asset] for a
/// pre-baked KTX2 radiance cubemap (no prefilter at load),
/// [EnvironmentMap.fromGpuTextures] when you already hold a prefiltered
/// atlas, or [EnvironmentMap.empty] for a no-op black environment.
///
/// Set one on a [Scene] via `Scene.environment` (it defaults to
/// [EnvironmentMap.studio]); an individual [PhysicallyBasedMaterial] can
/// override it via `PhysicallyBasedMaterial.environment`.
/// {@category Lighting and environment}
base class EnvironmentMap {
  EnvironmentMap._(
    this._prefilteredRadianceTexture,
    List<Vector3> sh, {
    gpu.Texture? rebakeSource,
    bool rebakeSourceIsLinear = false,
  }) : assert(sh.length == kDiffuseShCoefficientCount),
       _diffuseSphericalHarmonics = sh,
       _diffuseShTexture = _shTextureFromList(sh) {
    // An image environment's full-resolution source equirect, retained so the
    // visible sky samples it directly (sharp) instead of the small reflection
    // cube. The source is also the warm-rebake source on web.
    _backgroundTexture = rebakeSource;
    _backgroundIsLinear = rebakeSourceIsLinear;
    _registerForWarmupRebakeIfCold(rebakeSource, rebakeSourceIsLinear);
  }

  // Wraps an already-built prefiltered atlas and a GPU-computed SH coefficient
  // texture (the diffuse term lives only on the GPU, so the coefficient list
  // is empty). Used by [fromSky].
  EnvironmentMap._fromGpuSh(
    this._prefilteredRadianceTexture,
    this._diffuseShTexture,
  ) : _diffuseSphericalHarmonics = const <Vector3>[];

  /// World-space center of this environment's parallax box proxy, or null
  /// when reflections sample the environment at infinity (the default,
  /// correct for a sky or a distant panorama).
  ///
  /// A local environment (a reflection probe's capture of a room) sets both
  /// this and [parallaxBoxHalfExtents] to the box the capture approximates.
  /// Reflection lookups then intersect the reflected ray with the box and
  /// sample toward the hit, so reflections track nearby surfaces instead of
  /// floating at infinity (parallax-corrected cubemaps). The capture is
  /// assumed to have been taken from the box center.
  Vector3? parallaxBoxCenter;

  /// World-space half extents of the parallax box proxy; see
  /// [parallaxBoxCenter].
  Vector3? parallaxBoxHalfExtents;

  /// A black environment that contributes no image-based lighting.
  ///
  /// Specular reflections are black and the diffuse term is zero, so
  /// objects are lit only by analytic lights (if any).
  factory EnvironmentMap.empty() {
    return EnvironmentMap._(
      Material.getBlackPlaceholderTexture(),
      _zeroSphericalHarmonics(),
    );
  }

  /// A black reflection environment with uniform diffuse [ambientRadiance].
  ///
  /// The color is the linear RGB radiance a white Lambertian surface receives
  /// from the environment after its `1/pi` BRDF term. The resulting diffuse
  /// shading equals `ambientRadiance * baseColor` for every surface normal.
  /// {@category Lighting and environment}
  factory EnvironmentMap.constantDiffuse(Vector3 ambientRadiance) {
    const sh0Basis = 0.28209479177387814;
    final sh = _zeroSphericalHarmonics();
    sh[0].setValues(
      ambientRadiance.x / sh0Basis,
      ambientRadiance.y / sh0Basis,
      ambientRadiance.z / sh0Basis,
    );
    return EnvironmentMap._(Material.getBlackPlaceholderTexture(), sh);
  }

  /// Whether newly built environments store their prefiltered roughness
  /// bands as mip levels of one equirect (sampled with hardware trilinear
  /// `textureLod`) rather than the legacy vertically stacked band atlas.
  /// Defaults to true, and applies only where the backend supports the
  /// layout (see [mipRadianceLayoutSupported]).
  ///
  /// The legacy layout remains supported for comparison and as the
  /// fallback. Each environment carries its own layout (detected from its
  /// texture), so flipping this affects only environments built
  /// afterwards.
  ///
  /// Devices that report the layout as supported but sample every texture at
  /// its base mip (Adreno Vulkan, see
  /// https://github.com/flutter/flutter/issues/189965) do not need this turned
  /// off by hand; [mipRadianceLayoutSupported] measures the defect and keeps
  /// them on the atlas. Note the same clamp applies to every other mipmapped
  /// texture in the app, which no layout choice can work around.
  static bool useMipRadianceLayout = true;

  /// Base-mip face size of the prefiltered radiance cubemap new environments
  /// build (the convolved reflection/ambient cube, not the visible background).
  /// Higher is sharper reflections at more memory (a cube is `6 * size^2`
  /// texels plus mips); 256-512 is a good default, up to ~2048. Equivalent to
  /// Godot's `Sky.radiance_size`. Applies only on backends that build the cube
  /// (see [effectiveMipRadianceLayout]); affects environments built afterward.
  static int radianceCubeSize = kRadianceCubeSize;

  /// Whether the active Flutter GPU backend can build and sample the mip
  /// radiance layout: rendering into non-zero mip levels plus sampling
  /// hand-written mip chains.
  ///
  /// Currently false on the native GLES backend (Impeller does not yet
  /// implement render-to-mip-level there), where new environments build
  /// the legacy band atlas regardless of [useMipRadianceLayout]. On native
  /// Android the capability bits over-report (some engines clamp every
  /// Vulkan sampler to the base mip level on Adreno GPUs, see
  /// https://github.com/flutter/flutter/issues/161283), so support there is
  /// measured at startup by `probePlatformMipSampling` and devices where the
  /// clamp is active stay on the atlas.
  static bool get mipRadianceLayoutSupported => shouldUseMipRadianceLayout(
    isWeb: kIsWeb,
    targetPlatform: defaultTargetPlatform,
    backendSupportsMips:
        gpu.gpuContext.doesSupportFramebufferRenderMipmap &&
        gpu.gpuContext.doesSupportManuallyMippedTextures,
    platformMipSamplingWorks: platformMipSamplingWorks,
  );

  /// Applies the backend capability and the measured Android mip sampling
  /// probe. Before the probe resolves, Android conservatively stays on the
  /// atlas so environments built early are never wrong.
  @visibleForTesting
  static bool shouldUseMipRadianceLayout({
    required bool isWeb,
    required TargetPlatform targetPlatform,
    required bool backendSupportsMips,
    required bool? platformMipSamplingWorks,
  }) {
    if (!backendSupportsMips) {
      return false;
    }
    if (isWeb || targetPlatform != TargetPlatform.android) {
      return true;
    }
    return platformMipSamplingWorks ?? false;
  }

  /// The layout new environments build: [useMipRadianceLayout] resolved
  /// against backend support.
  @internal
  static bool get effectiveMipRadianceLayout =>
      useMipRadianceLayout && mipRadianceLayoutSupported;

  /// Wraps an already-built prefiltered radiance texture.
  ///
  /// [prefilteredRadiance] is either layout produced by
  /// [prefilterEquirectRadiance] (mip levels or the legacy band atlas,
  /// detected from the texture's mip count). The diffuse term comes from
  /// [diffuseSphericalHarmonics] ([kDiffuseShCoefficientCount] RGB
  /// coefficients with the Lambertian convolution and `1/pi` already folded
  /// in, as [computeDiffuseSphericalHarmonics] returns), or from
  /// [diffuseShTexture] (a 9x1 coefficient texture already on the GPU, as a
  /// sky bake produces); pass at most one. When both are omitted the diffuse
  /// term is zero.
  factory EnvironmentMap.fromGpuTextures({
    required gpu.Texture prefilteredRadiance,
    List<Vector3>? diffuseSphericalHarmonics,
    gpu.Texture? diffuseShTexture,
  }) {
    assert(
      diffuseSphericalHarmonics == null || diffuseShTexture == null,
      'Pass diffuseSphericalHarmonics or diffuseShTexture, not both.',
    );
    if (diffuseShTexture != null) {
      return EnvironmentMap._fromGpuSh(prefilteredRadiance, diffuseShTexture);
    }
    return EnvironmentMap._(
      prefilteredRadiance,
      diffuseSphericalHarmonics ?? _zeroSphericalHarmonics(),
    );
  }

  /// Loads an [EnvironmentMap] from a pre-baked KTX2 radiance cubemap, the
  /// output of an offline image-based-lighting bake (the Khronos glTF IBL
  /// sampler, or [prefilterEquirectRadianceToCube] run in tooling).
  ///
  /// The file must be a cubemap (`faceCount` 6) with square power-of-two faces
  /// at least [kMinRadianceCubeSize] a side, storing an uncompressed
  /// `R16G16B16A16_SFLOAT`, `R32G32B32A32_SFLOAT`, `E5B9G9R9_UFLOAT_PACK32`,
  /// `B10G11R11_UFLOAT_PACK32`, or `R8G8B8A8_UNORM`/`_SRGB` payload, optionally
  /// zstd-supercompressed. Block-compressed and Basis payloads are rejected;
  /// a GGX radiance chain is high dynamic range and a block codec destroys it.
  /// Anything else throws a [FormatException].
  ///
  /// **Mip-to-roughness convention.** The mip chain must be a GGX roughness
  /// series with **linear perceptual roughness per level**,
  /// `roughness = level / (levelCount - 1)`, mip 0 being the mirror level and
  /// the last level fully rough. That is the engine's own convention
  /// ([prefilterEquirectRadianceToCube] bakes mip `i` at
  /// `i / (kPrefilterBandCount - 1)`), and it is what the shader assumes when
  /// it samples at `lod = roughness * (kPrefilterBandCount - 1)`. The shader's
  /// lod scale is a constant, not the texture's mip count, so a chain of any
  /// other length is resampled here onto exactly [kPrefilterBandCount] levels
  /// (interpolating the two source levels bracketing each band's roughness).
  /// A file baked with a non-linear roughness distribution shades differently
  /// from an internally prefiltered environment; re-bake it linearly.
  ///
  /// **Face order.** Faces are taken in KTX2 order (+X, -X, +Y, -Y, +Z, -Z)
  /// with no reordering and no flip. The engine's cube sampling is the
  /// Khronos/Vulkan/GL convention verbatim (see `cubeFaceBases`), so a
  /// conforming file lands correctly as stored. Reorienting an environment for
  /// a scene is `Scene.environmentTransform`, not the loader's business.
  ///
  /// **Diffuse.** [diffuseSphericalHarmonics] wins when given; otherwise
  /// [diffuseShSidecar] is parsed ([parseDiffuseShSidecar]); otherwise the
  /// file's [kDiffuseShKtx2Key] key/value entry is read; otherwise the diffuse
  /// term is zero and only reflections light the scene. Coefficients are
  /// irradiance-domain, with the Lambertian `A_l` band factors and the `1/pi`
  /// BRDF term already folded in exactly as
  /// [computeDiffuseSphericalHarmonics] returns them. Check a bake against the
  /// contract with [describeDiffuseSphericalHarmonics].
  ///
  /// The parse and resample run on a background isolate; only the upload
  /// touches the main thread.
  /// {@category Lighting and environment}
  static Future<EnvironmentMap> fromKtx2Bytes(
    Uint8List bytes, {
    List<Vector3>? diffuseSphericalHarmonics,
    Uint8List? diffuseShSidecar,
  }) async {
    final sidecarSh = diffuseShSidecar == null
        ? null
        : parseDiffuseShSidecar(diffuseShSidecar);
    // The layout the backend can sample decides which resample runs, so it is
    // resolved here and carried into the isolate.
    final cubeLayout = effectiveMipRadianceLayout;
    final decoded = await compute(_decodeKtx2EnvironmentOnIsolate, (
      bytes,
      cubeLayout,
    ));
    final (radiance, fileSh) = cubeLayout
        ? _uploadRadianceCube(decoded as ImportedRadianceCube)
        : _uploadRadianceAtlas(decoded as ImportedRadianceAtlas);
    return EnvironmentMap._(
      radiance,
      diffuseSphericalHarmonics ??
          sidecarSh ??
          fileSh ??
          _zeroSphericalHarmonics(),
    );
  }

  /// Loads an [EnvironmentMap] from a pre-baked KTX2 radiance cubemap in the
  /// asset bundle (see [fromKtx2Bytes] for the accepted conventions).
  ///
  /// [diffuseShAssetPath], when given, is a sidecar of
  /// [kDiffuseShSidecarByteLength] bytes holding the diffuse spherical
  /// harmonics; a file that carries them in its own [kDiffuseShKtx2Key]
  /// metadata needs no sidecar.
  /// {@category Lighting and environment}
  static Future<EnvironmentMap> fromKtx2Asset({
    required String assetPath,
    String? diffuseShAssetPath,
    List<Vector3>? diffuseSphericalHarmonics,
    AssetBundle? bundle,
  }) async {
    final environment = await fromKtx2Bytes(
      await bytesFromAsset(assetPath, bundle: bundle),
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
      diffuseShSidecar: diffuseShAssetPath == null
          ? null
          : await bytesFromAsset(diffuseShAssetPath, bundle: bundle),
    );
    _environmentAssetPaths[environment] = assetPath;
    return environment;
  }

  /// Uploads a decoded radiance cube to a cube texture, face by face and mip
  /// by mip.
  static (gpu.Texture, List<Vector3>?) _uploadRadianceCube(
    ImportedRadianceCube decoded,
  ) {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      decoded.baseSize,
      decoded.baseSize,
      format: gpu.PixelFormat.r16g16b16a16Float,
      textureType: gpu.TextureType.textureCube,
      mipLevelCount: kPrefilterBandCount,
      enableRenderTargetUsage: false,
    );
    for (var mip = 0; mip < decoded.mips.length; mip++) {
      final faces = decoded.mips[mip];
      for (var face = 0; face < faces.length; face++) {
        texture.overwrite(
          ByteData.sublistView(faces[face]),
          mipLevel: mip,
          slice: face,
        );
      }
    }
    return (texture, decoded.diffuseSphericalHarmonics);
  }

  /// Uploads a decoded radiance atlas, the fallback for backends that cannot
  /// sample a mip chain.
  static (gpu.Texture, List<Vector3>?) _uploadRadianceAtlas(
    ImportedRadianceAtlas decoded,
  ) {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      decoded.width,
      decoded.height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      enableRenderTargetUsage: false,
    );
    texture.overwrite(ByteData.sublistView(decoded.pixels));
    return (texture, decoded.diffuseSphericalHarmonics);
  }

  /// Builds an [EnvironmentMap] from an already-decoded equirectangular
  /// `dart:ui` radiance image: uploads it, GPU-prefilters it for
  /// roughness-aware specular, and projects it onto diffuse SH.
  ///
  /// The image is interpreted as sRGB-encoded. Pass [diffuseSphericalHarmonics]
  /// to supply your own diffuse term instead of projecting it.
  static Future<EnvironmentMap> fromUIImages({
    required ui.Image radianceImage,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    final radianceTexture = await gpuTextureFromImage(radianceImage);
    final prefilteredRadiance = _buildRadiance(radianceTexture);
    final sh =
        diffuseSphericalHarmonics ??
        await computeDiffuseSphericalHarmonics(radianceImage);
    return EnvironmentMap._(
      prefilteredRadiance,
      sh,
      rebakeSource: radianceTexture,
    );
  }

  /// Loads an [EnvironmentMap] from an equirectangular sRGB radiance image
  /// in the asset bundle (see [fromUIImages]).
  ///
  /// [fromEquirectImageAsset] does everything this does and also detects
  /// Radiance HDR and OpenEXR sources; prefer it.
  @Deprecated('Use fromEquirectImageAsset instead')
  static Future<EnvironmentMap> fromAssets({
    required String radianceImagePath,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    final environment = await fromUIImages(
      radianceImage: await imageFromAsset(radianceImagePath),
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
    );
    _environmentAssetPaths[environment] = radianceImagePath;
    return environment;
  }

  /// Builds an [EnvironmentMap] from a high-dynamic-range equirectangular
  /// radiance map: linear (not sRGB) RGBA float pixels, row-major,
  /// [width] by [height]. Row 0 is the top of the image (the up pole), the
  /// standard equirectangular convention.
  ///
  /// Unlike [fromUIImages], the input is linear HDR, so radiance above 1.0
  /// (bright skies, the sun) is preserved through the prefilter and lights
  /// the scene at its true intensity. Pass [diffuseSphericalHarmonics] to
  /// supply your own diffuse term instead of projecting it.
  static Future<EnvironmentMap> fromEquirectHdr({
    required Float32List linearPixels,
    required int width,
    required int height,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    assert(linearPixels.length == width * height * 4);
    // The radiance texture is fp16, not fp32: the prefilter samples it
    // with a linear sampler, and 32-bit-float textures are not filterable
    // on several GPU backends (notably Apple Silicon), which would make
    // the prefiltered atlas read back as black. fp16 is universally
    // filterable and carries ample range for radiance. A CPU-built mip chain
    // lets the cube prefilter pre-average bright pixels (no firefly blocks in
    // the rough bands) where manually-mipped textures are supported.
    final radianceTexture = _createMippedRadianceSource(
      linearPixels,
      width,
      height,
    );
    final prefilteredRadiance = _buildRadiance(
      radianceTexture,
      sourceIsLinear: true,
    );
    final sh =
        diffuseSphericalHarmonics ??
        _projectLinearEquirectToSphericalHarmonics(linearPixels, width, height);
    return EnvironmentMap._(
      prefilteredRadiance,
      sh,
      rebakeSource: radianceTexture,
      rebakeSourceIsLinear: true,
    );
  }

  /// Loads an [EnvironmentMap] from an equirectangular image in the asset
  /// bundle, detecting Radiance HDR (`.hdr`), OpenEXR (`.exr`), or a standard
  /// sRGB image (`.png`/`.jpg`) from its contents. HDR and EXR are read as
  /// linear radiance, so bright skies and the sun keep their true intensity;
  /// LDR images are interpreted as sRGB.
  ///
  /// The decode runs on a background isolate. [maxWidth] caps the working
  /// equirect so a very large panorama is box-downsampled (HDR/EXR) or decoded
  /// scaled down (LDR) instead of materializing at full resolution. Pass
  /// [diffuseSphericalHarmonics] to supply your own diffuse term instead of
  /// projecting it.
  ///
  /// In debug builds, a `Scene.loadEnvironment` built on this re-runs on hot
  /// reload when the asset's content changes.
  static Future<EnvironmentMap> fromEquirectImageAsset({
    required String assetPath,
    int maxWidth = 4096,
    List<Vector3>? diffuseSphericalHarmonics,
    AssetBundle? bundle,
  }) async {
    final environment = await fromEquirectImageBytes(
      bytes: await bytesFromAsset(assetPath, bundle: bundle),
      maxWidth: maxWidth,
      diffuseSphericalHarmonics: diffuseSphericalHarmonics,
    );
    _environmentAssetPaths[environment] = assetPath;
    return environment;
  }

  /// Builds an [EnvironmentMap] from the raw bytes of an equirectangular image,
  /// detecting Radiance HDR, OpenEXR, or a standard sRGB image (see
  /// [fromEquirectImageAsset]). Useful for an image fetched over the network or
  /// picked by the user.
  ///
  /// On the web there are no isolates, so an HDR/EXR decode runs on the main
  /// thread and a large panorama can jank; prefer a modest [maxWidth] there.
  static Future<EnvironmentMap> fromEquirectImageBytes({
    required Uint8List bytes,
    int maxWidth = 4096,
    List<Vector3>? diffuseSphericalHarmonics,
  }) async {
    // LDR decodes through the platform image codec on the main isolate; only
    // the CPU-heavy HDR/EXR decode (and its SH projection) is worth an isolate.
    if (detectEquirectImageFormat(bytes) == EquirectImageFormat.ldr) {
      return fromUIImages(
        radianceImage: await imageFromBytes(bytes, maxWidth: maxWidth),
        diffuseSphericalHarmonics: diffuseSphericalHarmonics,
      );
    }
    final (pixels, width, height, shFlat) = await compute(
      _decodeEquirectHdrOnIsolate,
      (bytes, maxWidth, diffuseSphericalHarmonics == null),
    );
    return fromEquirectHdr(
      linearPixels: pixels,
      width: width,
      height: height,
      diffuseSphericalHarmonics:
          diffuseSphericalHarmonics ?? _shFromFlat(shFlat),
    );
  }

  // Rebuilds diffuse SH coefficients from the flat float triples the decode
  // isolate returns (Vector3 per coefficient), or null when none were computed.
  static List<Vector3>? _shFromFlat(Float32List? flat) {
    if (flat == null) return null;
    return [
      for (var i = 0; i < flat.length ~/ 3; i++)
        Vector3(flat[i * 3], flat[i * 3 + 1], flat[i * 3 + 2]),
    ];
  }

  /// Bakes a sky into an environment for image-based lighting.
  ///
  /// Renders [source] (a [ShaderSkySource], including a `.fmat` sky) into a
  /// prefiltered-radiance atlas plus a GPU-projected diffuse SH texture, so
  /// the sky also lights the scene. This is GPU work meant to run when the
  /// sky is set or changes, not every frame; the visible `Scene.skybox` draw
  /// is separate and cheap. To re-bake on a schedule instead of by hand, set
  /// `Scene.skyEnvironment` with a refresh policy. [faceResolution] and
  /// [equirectWidth] trade quality for bake cost.
  ///
  /// Only [ShaderSkySource]-based skies can be baked; an [EnvironmentSkySource]
  /// already is an environment.
  static EnvironmentMap fromSky(
    SkySource source, {
    int faceResolution = 128,
    int equirectWidth = 512,
  }) {
    if (source is! ShaderSkySource) {
      throw ArgumentError(
        'EnvironmentMap.fromSky requires a ShaderSkySource (or a .fmat sky); '
        'an EnvironmentSkySource already is an environment.',
      );
    }
    final baked = bakeSkyEnvironment(
      source,
      EnvironmentMap.empty(),
      faceResolution: faceResolution,
      equirectWidth: equirectWidth,
    );
    return EnvironmentMap._fromGpuSh(baked.atlas, baked.sh);
  }

  /// Creates the radiance source equirect from linear float [pixels], with a
  /// CPU-built mip chain when the backend supports manually-mipped textures (the
  /// same capability that selects the cube radiance layout). The cube prefilter
  /// reads the mips per GGX sample so bright source texels are pre-averaged,
  /// removing the firefly blocks a single bright texel leaves in the rough
  /// bands. Falls back to a single level otherwise (the prefilter's firefly
  /// clamp covers that path).
  static gpu.Texture _createMippedRadianceSource(
    Float32List pixels,
    int width,
    int height,
  ) {
    final mipCount = mipRadianceLayoutSupported
        ? _maxMipLevels(math.min(width, height))
        : 1;
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r16g16b16a16Float,
      mipLevelCount: mipCount,
    );
    texture.overwrite(
      ByteData.sublistView(floatPixelsToHalf(pixels)),
      mipLevel: 0,
    );
    var level = pixels;
    var w = width;
    var h = height;
    for (var mip = 1; mip < mipCount; mip++) {
      final nw = math.max(1, w >> 1);
      final nh = math.max(1, h >> 1);
      level = _boxDownsampleEquirect(level, w, h, nw, nh);
      texture.overwrite(
        ByteData.sublistView(floatPixelsToHalf(level)),
        mipLevel: mip,
      );
      w = nw;
      h = nh;
    }
    return texture;
  }

  /// `floor(log2(size))`, at least 1. Passing the smaller texture dimension
  /// matches flutter_gpu's `Texture.fullMipCount` (`floor(log2(min(w, h)))`),
  /// the upper bound `createTexture` accepts for `mipLevelCount`.
  static int _maxMipLevels(int size) {
    var levels = 1;
    while ((1 << (levels + 1)) <= size) {
      levels++;
    }
    return levels;
  }

  /// Box-downsamples a half-resolution mip of an equirect of linear RGBA float
  /// [src] (`width` by `height`) to `newWidth` by `newHeight`. Longitude (the
  /// horizontal axis) wraps; latitude clamps.
  static Float32List _boxDownsampleEquirect(
    Float32List src,
    int width,
    int height,
    int newWidth,
    int newHeight,
  ) {
    final dst = Float32List(newWidth * newHeight * 4);
    for (var y = 0; y < newHeight; y++) {
      final y0 = math.min(y * 2, height - 1);
      final y1 = math.min(y0 + 1, height - 1);
      for (var x = 0; x < newWidth; x++) {
        final x0 = (x * 2) % width;
        final x1 = (x0 + 1) % width;
        final i00 = (y0 * width + x0) * 4;
        final i01 = (y0 * width + x1) * 4;
        final i10 = (y1 * width + x0) * 4;
        final i11 = (y1 * width + x1) * 4;
        final o = (y * newWidth + x) * 4;
        for (var c = 0; c < 4; c++) {
          dst[o + c] =
              (src[i00 + c] + src[i01 + c] + src[i10 + c] + src[i11 + c]) *
              0.25;
        }
      }
    }
    return dst;
  }

  /// Builds the package's built-in procedural "studio" environment.
  ///
  /// A neutral image-based-lighting setup generated on the fly (no bundled
  /// HDR): a cool soft "ceiling" fading through a neutral horizon to a dim
  /// warm "floor bounce", with a broad top fill and a couple of soft
  /// key/fill light lobes that read as defined specular highlights on
  /// glossy surfaces. This is the zero-config default a [Scene] uses when
  /// no environment is configured.
  static EnvironmentMap studio() {
    final pixels = _generateStudioEquirectPixels(
      _studioEnvWidth,
      _studioEnvHeight,
    );
    final radianceTexture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      _studioEnvWidth,
      _studioEnvHeight,
    )..overwrite(ByteData.sublistView(pixels));
    return EnvironmentMap._(
      _buildRadiance(radianceTexture),
      _projectEquirectToSphericalHarmonics(
        pixels,
        _studioEnvWidth,
        _studioEnvHeight,
      ),
      rebakeSource: radianceTexture,
    );
  }

  static const int _studioEnvWidth = 256;
  static const int _studioEnvHeight = 128;

  // Generates the procedural studio equirect as sRGB-encoded RGBA8 pixels.
  // The scan order matches _projectEquirectToSphericalHarmonics / the
  // shader's SphericalToEquirectangular: row 0 is the "down" pole, the last
  // row is the "up" pole.
  static Uint8List _generateStudioEquirectPixels(int width, int height) {
    final pixels = Uint8List(width * height * 4);

    final keyDir = Vector3(0.45, 0.55, 0.70)..normalize();
    final fillDir = Vector3(-0.70, 0.22, -0.35)..normalize();

    const twoPi = 2.0 * math.pi;
    for (var py = 0; py < height; py++) {
      final v = (py + 0.5) / height;
      // Row 0 (the top of the image) is the up hemisphere (+y), matching the
      // standard equirect convention loaded images use and the way the
      // prefilter and SH projection sample the source.
      final latitude = (0.5 - v) * math.pi; // asin(dirY)
      final cosLat = math.cos(latitude);
      final dirY = math.sin(latitude);
      for (var px = 0; px < width; px++) {
        final u = (px + 0.5) / width;
        final longitude = (u - 0.5) * twoPi; // atan2(dirZ, dirX)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);

        // Vertical studio gradient (linear): a near-neutral grey, faintly
        // cool above the horizon and faintly warm below. Kept low-
        // saturation so glancing reflections on glossy floors stay clean.
        double r, g, b;
        if (dirY >= 0.0) {
          final t = _smoothstep01(dirY);
          r = _lerp(0.50, 0.76, t);
          g = _lerp(0.51, 0.78, t);
          b = _lerp(0.52, 0.82, t);
        } else {
          final t = _smoothstep01(-dirY);
          r = _lerp(0.50, 0.20, t);
          g = _lerp(0.51, 0.19, t);
          b = _lerp(0.52, 0.17, t);
        }

        // Broad (near-neutral) top fill, the "ceiling softbox".
        final top = math.max(dirY, 0.0);
        final topL = top * top; // pow(., 2)
        r += 0.85 * topL;
        g += 0.86 * topL;
        b += 0.88 * topL;

        // Tight, faintly warm key highlight.
        final keyC = math.max(
          dirX * keyDir.x + dirY * keyDir.y + dirZ * keyDir.z,
          0.0,
        );
        final keyL = math.pow(keyC, 26.0).toDouble();
        r += 1.10 * keyL;
        g += 1.06 * keyL;
        b += 1.00 * keyL;

        // Softer, faintly cool fill from behind.
        final fillC = math.max(
          dirX * fillDir.x + dirY * fillDir.y + dirZ * fillDir.z,
          0.0,
        );
        final fillL = math.pow(fillC, 16.0).toDouble();
        r += 0.46 * fillL;
        g += 0.50 * fillL;
        b += 0.56 * fillL;

        final o = (py * width + px) * 4;
        pixels[o] = _encodeSrgb(r);
        pixels[o + 1] = _encodeSrgb(g);
        pixels[o + 2] = _encodeSrgb(b);
        pixels[o + 3] = 255;
      }
    }
    return pixels;
  }

  static int _encodeSrgb(double linear) {
    final c = linear.clamp(0.0, 1.0);
    final encoded = c <= 0.0031308
        ? c * 12.92
        : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
    return (encoded * 255.0).round().clamp(0, 255).toInt();
  }

  static double _smoothstep01(double x) {
    final t = x.clamp(0.0, 1.0).toDouble();
    return t * t * (3.0 - 2.0 * t);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static List<Vector3> _zeroSphericalHarmonics() =>
      List<Vector3>.generate(kDiffuseShCoefficientCount, (_) => Vector3.zero());

  /// Projects an equirectangular radiance image onto 9 L2 spherical-
  /// harmonic coefficients suitable for diffuse irradiance.
  ///
  /// The image is interpreted as sRGB-encoded and read in the same
  /// equirectangular convention the runtime shader samples with. The
  /// returned coefficients already fold in the Lambertian cosine
  /// convolution (the `A_l` band factors) and the `1 / pi` BRDF term, so
  /// the shader just evaluates `Sum c_i * Y_i(n)` and multiplies by the
  /// diffuse albedo.
  static Future<List<Vector3>> computeDiffuseSphericalHarmonics(
    ui.Image equirectangular,
  ) async {
    final byteData = await equirectangular.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw Exception('Failed to read RGBA data from environment image.');
    }
    return _projectEquirectToSphericalHarmonics(
      byteData.buffer.asUint8List(),
      equirectangular.width,
      equirectangular.height,
    );
  }

  /// SH-9 projection over RGBA8 sRGB equirectangular [bytes].
  static List<Vector3> _projectEquirectToSphericalHarmonics(
    Uint8List bytes,
    int width,
    int height,
  ) {
    return _projectEquirect(width, height, (px, py) {
      final o = (py * width + px) * 4;
      // Linearize sRGB the same way the shader's SRGBToLinear does.
      return (
        _srgbToLinear(bytes[o] / 255.0),
        _srgbToLinear(bytes[o + 1] / 255.0),
        _srgbToLinear(bytes[o + 2] / 255.0),
      );
    });
  }

  /// SH-9 projection over linear-radiance RGBA float equirect [pixels].
  static List<Vector3> _projectLinearEquirectToSphericalHarmonics(
    Float32List pixels,
    int width,
    int height,
  ) {
    return _projectEquirect(width, height, (px, py) {
      final o = (py * width + px) * 4;
      return (pixels[o], pixels[o + 1], pixels[o + 2]);
    });
  }

  /// Core SH-9 projection over an equirectangular image of the given
  /// dimensions. [sampleLinearRgb] returns the linear RGB radiance at a
  /// pixel; callers adapt their own storage (sRGB bytes, HDR floats).
  static List<Vector3> _projectEquirect(
    int width,
    int height,
    (double, double, double) Function(int px, int py) sampleLinearRgb,
  ) {
    // Quadrature over a regular grid in equirectangular UV space. The grid
    // resolution is independent of the source image; sampling 192x96 cells
    // keeps the L2 projection accurate while staying fast on the CPU.
    const numPhi = 192;
    const numTheta = 96;
    final coefficients = _zeroSphericalHarmonics();

    const twoPi = 2.0 * math.pi;
    final cellSolidAngle = twoPi * math.pi / (numPhi * numTheta);

    for (var j = 0; j < numTheta; j++) {
      final v = (j + 0.5) / numTheta;
      final latitude =
          (v - 0.5) * math.pi; // asin(direction.y), in [-pi/2, pi/2]
      final cosLat = math.cos(latitude);
      final dirY = math.sin(latitude);
      final weightRow = cosLat * cellSolidAngle;
      // The source equirect stores +y (up) at the top of the image (row 0),
      // but increasing v here maps to increasing latitude (up). Flip the row
      // lookup so the up hemisphere reads the top of the image, matching the
      // prefilter's source sampling; otherwise the diffuse irradiance is
      // vertically inverted relative to the specular radiance.
      final py = ((1.0 - v) * height).floor().clamp(0, height - 1);

      for (var i = 0; i < numPhi; i++) {
        final u = (i + 0.5) / numPhi;
        final longitude = (u - 0.5) * twoPi; // atan2(direction.z, direction.x)
        final dirX = cosLat * math.cos(longitude);
        final dirZ = cosLat * math.sin(longitude);
        final px = (u * width).floor().clamp(0, width - 1);

        final (r, g, b) = sampleLinearRgb(px, py);
        _accumulateSh(coefficients, dirX, dirY, dirZ, r, g, b, weightRow);
      }
    }

    // Fold in the Lambertian convolution band factors (A_l) divided by pi:
    // A_0/pi = 1, A_1/pi = 2/3, A_2/pi = 1/4. Band 0 is unchanged.
    for (var k = 1; k <= 3; k++) {
      coefficients[k] = coefficients[k] * (2.0 / 3.0);
    }
    for (var k = 4; k <= 8; k++) {
      coefficients[k] = coefficients[k] * 0.25;
    }
    return coefficients;
  }

  static void _accumulateSh(
    List<Vector3> coefficients,
    double x,
    double y,
    double z,
    double r,
    double g,
    double b,
    double weight,
  ) {
    // Real spherical-harmonic basis, bands 0..2. Must match the basis the
    // standard fragment shader evaluates with.
    final basis = <double>[
      0.282095,
      0.488603 * y,
      0.488603 * z,
      0.488603 * x,
      1.092548 * x * y,
      1.092548 * y * z,
      0.315392 * (3.0 * z * z - 1.0),
      1.092548 * x * z,
      0.546274 * (x * x - y * y),
    ];
    for (var k = 0; k < kDiffuseShCoefficientCount; k++) {
      final w = basis[k] * weight;
      coefficients[k].x += r * w;
      coefficients[k].y += g * w;
      coefficients[k].z += b * w;
    }
  }

  static double _srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  // Not final: re-baked in place once the web GL context is warm (see
  // [markContextWarmAndRebakeRadiance]).
  gpu.Texture _prefilteredRadianceTexture;
  final List<Vector3> _diffuseSphericalHarmonics;
  final gpu.Texture _diffuseShTexture;

  // The full-res source equirect for an image environment's background, or null
  // (sky-baked / GPU-supplied environments have no source equirect and use the
  // reflection cube for the background).
  gpu.Texture? _backgroundTexture;
  bool _backgroundIsLinear = false;

  // The equirect source this environment was prefiltered from, retained only
  // while it awaits a warm-context re-bake (web only); dropped once re-baked
  // or when built warm, so steady-state memory is unchanged.
  gpu.Texture? _rebakeSource;
  bool _rebakeSourceIsLinear = false;

  // Environments built on a cold web GL context, before the first frame is
  // composited, get a degenerate radiance prefilter (the float
  // render-to-texture only works once the context is warm). They are tracked
  // here and re-baked once on the first warm frame.
  // TODO(web-warmup): this covers the equirect-source environments (studio,
  // fromUIImages/fromAssets, fromEquirectHdr). A sky-baked environment
  // (EnvironmentMap.fromSky, which has no equirect source) built cold is not
  // re-baked here; a Scene.skyEnvironment with a refresh policy re-bakes
  // itself, but a one-shot fromSky stays dim until the next bake. Retain the
  // SkySource to re-bake it the same way if that becomes a real case.
  static final List<EnvironmentMap> _coldBuiltEnvironments = <EnvironmentMap>[];
  static bool _contextWarm = false;

  void _registerForWarmupRebakeIfCold(gpu.Texture? source, bool isLinear) {
    // Only the web backend has the cold-context prefilter problem; elsewhere
    // the source is never retained and nothing is re-baked.
    if (source == null || !kIsWeb || _contextWarm) {
      return;
    }
    _rebakeSource = source;
    _rebakeSourceIsLinear = isLinear;
    _coldBuiltEnvironments.add(this);
  }

  void _rebakeRadianceForWarmup() {
    final source = _rebakeSource;
    if (source == null) {
      return;
    }
    _rebakeSource = null;
    _prefilteredRadianceTexture = _buildRadiance(
      source,
      sourceIsLinear: _rebakeSourceIsLinear,
    );
  }

  /// Marks the GL context warm and re-bakes the radiance of every environment
  /// built while it was cold.
  ///
  /// On the web backend the radiance prefilter (a float render-to-texture) is
  /// degenerate until the context has presented and the browser composited its
  /// first frame; environments built before then (the lazily built default,
  /// or any the app built in `initState`) hold their source equirect and
  /// re-bake here once warm, fixing the dim image-based specular lighting.
  /// Called from `Scene.renderViews` after the first frame is presented; a
  /// no-op once run and on backends that never registered an environment
  /// (everything but web).
  @internal
  static void markContextWarmAndRebakeRadiance() {
    if (_contextWarm) {
      return;
    }
    _contextWarm = true;
    for (final environment in _coldBuiltEnvironments) {
      environment._rebakeRadianceForWarmup();
    }
    _coldBuiltEnvironments.clear();
  }

  /// Whether the radiance is stored as a roughness-mip cubemap (sampled with
  /// `samplerCube`) rather than an equirect 2D layout. Detected from the
  /// texture, so an environment built either way binds correctly.
  bool get usesCubeRadianceLayout =>
      _prefilteredRadianceTexture.textureType == gpu.TextureType.textureCube;

  /// The prefiltered radiance, in whichever layout it was built. Bound to the
  /// single `prefiltered_radiance` sampler of the shader variant matching
  /// [usesCubeRadianceLayout].
  gpu.Texture get prefilteredRadiance => _prefilteredRadianceTexture;

  /// Whether this environment has a full-resolution source equirect for its
  /// background (image environments do; sky-baked / GPU-supplied ones do not).
  bool get hasBackgroundTexture => _backgroundTexture != null;

  /// The full-res source equirect sampled for the visible background, or a dummy
  /// when [hasBackgroundTexture] is false (the sampler must still be bound).
  gpu.Texture get backgroundTexture =>
      _backgroundTexture ?? Material.getBlackPlaceholderTexture();

  /// Whether [backgroundTexture] holds linear radiance (an HDR source) rather
  /// than sRGB-encoded color.
  bool get backgroundIsLinear => _backgroundIsLinear;

  /// Whether the 2D [prefilteredRadiance] stores its roughness bands as
  /// mip levels (see [useMipRadianceLayout]). Always false for the cube layout.
  bool get usesMipRadianceLayout =>
      !usesCubeRadianceLayout && _prefilteredRadianceTexture.mipLevelCount > 1;

  /// Prefilters [source] into the radiance representation this backend uses:
  /// a roughness-mip cubemap where supported (no pole distortion), the legacy
  /// equirect band atlas otherwise.
  static gpu.Texture _buildRadiance(
    gpu.Texture source, {
    bool sourceIsLinear = false,
  }) => effectiveMipRadianceLayout
      ? prefilterEquirectRadianceToCube(
          source,
          sourceIsLinear: sourceIsLinear,
          size: radianceCubeSize,
        )
      : prefilterEquirectRadiance(
          source,
          sourceIsLinear: sourceIsLinear,
          mipLayout: false,
        );

  /// The [kDiffuseShCoefficientCount] RGB L2 spherical-harmonic
  /// coefficients describing the diffuse (Lambertian) irradiance.
  ///
  /// The Lambertian cosine convolution and the `1/pi` BRDF term are
  /// already folded in, so the shader just evaluates the polynomial and
  /// multiplies by the diffuse albedo. All zero for [EnvironmentMap.empty].
  ///
  /// Empty for an environment baked from a sky ([fromSky]), whose coefficients
  /// are computed on the GPU and live only in [diffuseShTexture].
  List<Vector3> get diffuseSphericalHarmonics => _diffuseSphericalHarmonics;

  /// The diffuse SH coefficients as a `kDiffuseShCoefficientCount`-by-1
  /// `r16g16b16a16Float` texture (coefficient `i` at texel `i`, RGB used).
  ///
  /// The engine lighting samples this rather than a uniform so coefficients
  /// computed on the GPU (a baked sky) need no read-back. Built from
  /// [diffuseSphericalHarmonics] for the image-based constructors.
  gpu.Texture get diffuseShTexture => _diffuseShTexture;

  /// Uploads [sh] (9 RGB coefficients) to a 9-by-1 float texture.
  static gpu.Texture _shTextureFromList(List<Vector3> sh) {
    final half = Uint16List(kDiffuseShCoefficientCount * 4);
    for (var i = 0; i < kDiffuseShCoefficientCount; i++) {
      half[i * 4] = floatToHalfBits(sh[i].x);
      half[i * 4 + 1] = floatToHalfBits(sh[i].y);
      half[i * 4 + 2] = floatToHalfBits(sh[i].z);
      half[i * 4 + 3] = floatToHalfBits(1.0);
    }
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      kDiffuseShCoefficientCount,
      1,
      format: gpu.PixelFormat.r16g16b16a16Float,
    );
    texture.overwrite(ByteData.sublistView(half));
    return texture;
  }
}

// Isolate entry point for EnvironmentMap.fromKtx2Bytes. Parses the container,
// decodes the faces, and resamples them onto the radiance layout the backend
// can sample: an ImportedRadianceCube when it renders and samples mip chains,
// an ImportedRadianceAtlas otherwise.
Object _decodeKtx2EnvironmentOnIsolate((Uint8List, bool) message) {
  final (bytes, cubeLayout) = message;
  return cubeLayout
      ? decodeKtx2RadianceCube(bytes)
      : decodeKtx2RadianceAtlas(bytes);
}

// Isolate entry point for EnvironmentMap.fromEquirectImageBytes. Decodes an
// HDR/EXR equirect off the platform thread and, when projectSh is set, also
// projects its diffuse SH there (so the main isolate does not re-scan the
// pixels). Returns the linear pixels, dimensions, and the flattened SH (or
// null). The caller only reaches here after detecting a non-LDR source.
(Float32List, int, int, Float32List?) _decodeEquirectHdrOnIsolate(
  (Uint8List, int, bool) message,
) {
  final (bytes, maxWidth, projectSh) = message;
  final decoded = decodeEquirectHdrImage(bytes, maxWidth: maxWidth)!;
  Float32List? sh;
  if (projectSh) {
    final coefficients =
        EnvironmentMap._projectLinearEquirectToSphericalHarmonics(
          decoded.pixels,
          decoded.width,
          decoded.height,
        );
    sh = Float32List(coefficients.length * 3);
    for (var i = 0; i < coefficients.length; i++) {
      sh[i * 3] = coefficients[i].x;
      sh[i * 3 + 1] = coefficients[i].y;
      sh[i * 3 + 2] = coefficients[i].z;
    }
  }
  return (decoded.pixels, decoded.width, decoded.height, sh);
}

/// Radiance asset paths recorded for [EnvironmentMap.fromEquirectImageAsset]
/// (and the deprecated `fromAssets`) results, so provenance-aware tooling (the
/// scene serializer) can recover where a live environment came from.
final Expando<String> _environmentAssetPaths = Expando(
  'environment asset path',
);

/// The radiance asset path [environment] was loaded from through
/// [EnvironmentMap.fromEquirectImageAsset] (or the deprecated `fromAssets`),
/// or null for environments built another way.
/// {@category Lighting and environment}
String? environmentAssetPathOf(EnvironmentMap environment) =>
    _environmentAssetPaths[environment];
