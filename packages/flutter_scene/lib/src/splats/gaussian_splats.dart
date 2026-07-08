import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/splats/splat_codec.dart';
import 'package:flutter_scene/src/splats/splat_data.dart';

/// A loaded Gaussian splat set: the decoded splat arrays plus the GPU
/// textures the splat shaders fetch from.
///
/// Load one with [fromAsset] or [fromBytes] (file decoding and texel packing
/// run on a background isolate), or build one procedurally with [fromData].
/// Attach it to the scene through a `SplatComponent`.
///
/// The GPU textures are created lazily on first draw, so a
/// `GaussianSplats` can be constructed before
/// `Scene.initializeStaticResources` completes.
/// {@category Gaussian splatting}
class GaussianSplats {
  GaussianSplats._(PackedSplats packed, this.colorSpace)
    : data = packed.data,
      paramsWidth = packed.paramsWidth,
      paramsHeight = packed.paramsHeight,
      shWidth = packed.shWidth,
      shHeight = packed.shHeight,
      shStride = packed.shStride,
      _paramsTexels = packed.paramsTexels,
      _shTexels = packed.shTexels {
    bounds = data.computeBounds();
  }

  /// Wraps an already-decoded-and-packed splat set. Takes the internal
  /// packer output, so it is not application API.
  @internal
  factory GaussianSplats.fromPacked(
    PackedSplats packed, {
    SplatColorSpace colorSpace = SplatColorSpace.displayReferred,
  }) => GaussianSplats._(packed, colorSpace);

  /// Packs [data] (procedurally constructed splats) synchronously on the
  /// calling thread.
  ///
  /// Procedural colors are usually already linear, so [colorSpace] defaults
  /// to [SplatColorSpace.linear]. For large captured sets prefer [fromBytes],
  /// which decodes and packs off-thread.
  factory GaussianSplats.fromData(
    SplatData data, {
    SplatColorSpace colorSpace = SplatColorSpace.linear,
  }) => GaussianSplats._(packSplats(data), colorSpace);

  /// Loads and decodes a splat file from the asset bundle.
  ///
  /// The format is sniffed from the file magic, falling back to the asset
  /// extension (`.ply` vs `.splat`); pass [format] to override. Decoding and
  /// packing run on a background isolate.
  static Future<GaussianSplats> fromAsset(
    String assetPath, {
    SplatFormat? format,
    double alphaCullThreshold = 1.0 / 255.0,
    int maxShDegree = 2,
    SplatColorSpace colorSpace = SplatColorSpace.displayReferred,
  }) async {
    final bytes = await rootBundle.load(assetPath);
    return fromBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      format:
          format ??
          (assetPath.toLowerCase().endsWith('.ply')
              ? SplatFormat.ply
              : SplatFormat.splat),
      alphaCullThreshold: alphaCullThreshold,
      maxShDegree: maxShDegree,
      colorSpace: colorSpace,
    );
  }

  /// Decodes splat file [bytes] on a background isolate.
  static Future<GaussianSplats> fromBytes(
    Uint8List bytes, {
    SplatFormat? format,
    double alphaCullThreshold = 1.0 / 255.0,
    int maxShDegree = 2,
    SplatColorSpace colorSpace = SplatColorSpace.displayReferred,
  }) async {
    final sniffed = sniffSplatFormat(bytes, fallback: format);
    final packed = await compute(decodeSplatsForIsolate, (
      bytes: bytes,
      format: sniffed,
      alphaCullThreshold: alphaCullThreshold,
      maxShDegree: maxShDegree,
    ), debugLabel: 'decodeSplats');
    return GaussianSplats._(packed, colorSpace);
  }

  /// The decoded splat arrays (positions drive depth sorting; the rest are
  /// kept for bounds and readback).
  final SplatData data;

  /// How [data]'s colors map into the linear HDR pipeline.
  final SplatColorSpace colorSpace;

  /// Local-space bounds of the set (splat centers padded by three standard
  /// deviations), or null for an empty set.
  late final vm.Aabb3? bounds;

  /// The number of splats.
  int get count => data.count;

  /// Parameter texture dimensions in texels. Consumed by `SplatGeometry` to
  /// address the data texture; not application API.
  @internal
  final int paramsWidth;

  /// See [paramsWidth].
  @internal
  final int paramsHeight;

  /// Rest-SH texture dimensions and per-splat texel stride (zero when the
  /// set carries no rest coefficients). Consumed by `SplatGeometry`; not
  /// application API.
  @internal
  final int shWidth;

  /// See [shWidth].
  @internal
  final int shHeight;

  /// See [shWidth].
  @internal
  final int shStride;

  // Texel arrays are held only until the first upload, then released.
  Float32List? _paramsTexels;
  Float32List? _shTexels;

  gpu.Texture? _paramsTexture;
  gpu.Texture? _shTexture;

  /// The RGBA32F parameter texture ([kParamsTexelsPerSplat] texels per
  /// splat). Created on first access; requires the GPU context. Consumed by
  /// `SplatGeometry`; not application API.
  @internal
  gpu.Texture get paramsTexture {
    var texture = _paramsTexture;
    if (texture == null) {
      texture = _upload(_paramsTexels!, paramsWidth, paramsHeight);
      _paramsTexture = texture;
      _paramsTexels = null;
    }
    return texture;
  }

  /// The RGBA32F rest-SH texture, or null when [SplatData.shDegree] is 0.
  /// Consumed by `SplatGeometry`; not application API.
  @internal
  gpu.Texture? get shTexture {
    if (data.shDegree == 0) return null;
    var texture = _shTexture;
    if (texture == null) {
      texture = _upload(_shTexels!, shWidth, shHeight);
      _shTexture = texture;
      _shTexels = null;
    }
    return texture;
  }

  static gpu.Texture _upload(Float32List texels, int width, int height) {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      width,
      height,
      format: gpu.PixelFormat.r32g32b32a32Float,
    );
    texture.overwrite(ByteData.sublistView(texels));
    return texture;
  }
}
