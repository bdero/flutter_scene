// Decodes standard KTX2 textures (glTF KHR_texture_basisu) to RGBA8 mip
// chains. Standard files carry a Basis Universal payload (UASTC or ETC1S)
// or plain RGBA8, identified by the data format descriptor; the engine's own
// cooked KTX2 files are a separate format identified by a key/value marker
// and handled by compressed_texture.dart.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/etc1s.dart';
import 'package:flutter_scene/src/texture/basisu/uastc.dart';
import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/supercompress/zstd.dart';

// VK_FORMAT_R8G8B8A8_UNORM/_SRGB, the uncompressed formats KHR_texture_basisu
// tooling emits.
const int _vkFormatRgba8Unorm = 37;
const int _vkFormatRgba8Srgb = 43;

/// Whether [bytes] start with the KTX2 file identifier.
bool looksLikeKtx2(Uint8List bytes) {
  if (bytes.length < ktx2Identifier.length) return false;
  for (var i = 0; i < ktx2Identifier.length; i++) {
    if (bytes[i] != ktx2Identifier[i]) return false;
  }
  return true;
}

/// Whether [texture] is one of the engine's own cooked KTX2 files (the
/// private block payload marked by [kFsBlockFormatKey]) rather than a
/// standard one.
bool isInternalKtx2(Ktx2Texture texture) =>
    texture.keyValues.containsKey(kFsBlockFormatKey);

/// A standard KTX2 texture decoded to RGBA8: the file's mip levels plus the
/// data format descriptor's tagging.
class StandardKtx2Image {
  StandardKtx2Image({
    required this.levels,
    required this.srgb,
    required this.hasAlpha,
  });

  /// RGBA8 mip levels, base first, exactly the levels the file stores.
  final List<MipLevel> levels;

  /// Whether the transfer function is sRGB (otherwise linear).
  final bool srgb;

  final bool hasAlpha;
}

/// Validates that [texture] is a plausibly-sized 2D standard file and returns
/// its base dimensions.
({int width, int height}) _checkStandard2d(Ktx2Texture texture) {
  if (texture.faceCount != 1 ||
      texture.layerCount > 1 ||
      texture.pixelDepth > 1) {
    // TODO(ktx2-cube-array): array and 3D standard files still need per-image
    // slicing within each level. Uncompressed cubemaps have it in
    // material/ibl_ktx2.dart (environment radiance); a Basis-encoded cubemap
    // bound as a material texture would need the same slicing here plus a
    // cube upload path.
    throw Ktx2FormatException(
      'Only 2D non-array standard KTX2 textures are supported',
    );
  }
  final width = texture.pixelWidth;
  final height = math.max(1, texture.pixelHeight);
  // Basis encoders cap dimensions at 16K; a larger value is a corrupt header,
  // rejected here before it can size an absurd allocation.
  if (width < 1 || width > 16384 || height > 16384) {
    throw Ktx2FormatException('Implausible dimensions ${width}x$height');
  }
  return (width: width, height: height);
}

/// One repacked ASTC 4x4 mip level.
typedef AstcLevel = ({int width, int height, Uint8List blocks});

/// Repacks the stored mip levels of a UASTC [texture] into ASTC 4x4 blocks
/// (the direct compressed upload path), or returns null when [texture] does
/// not carry UASTC. At most [maxLevels] levels are produced.
List<AstcLevel>? repackStandardKtx2ToAstc(Ktx2Texture texture, int maxLevels) {
  final (:width, :height) = _checkStandard2d(texture);
  if (readDataFormat(texture).colorModel != kDfModelUastc) return null;
  final levels = <AstcLevel>[];
  final count = math.min(texture.levels.length, maxLevels);
  for (var level = 0; level < count; level++) {
    final size = mipSize(width, height, level);
    final payload = _levelPayload(texture, level);
    final blockCount = ((size.width + 3) >> 2) * ((size.height + 3) >> 2);
    levels.add((
      width: size.width,
      height: size.height,
      blocks: transcodeUastcToAstc4x4(payload, blockCount),
    ));
  }
  return levels;
}

/// Decodes every stored mip level of a standard KTX2 [texture] to RGBA8.
/// Pure data work, safe to run on a background isolate. Throws
/// [Ktx2FormatException] or [FormatException] on malformed or unsupported
/// content.
StandardKtx2Image decodeStandardKtx2(Ktx2Texture texture) {
  final (:width, :height) = _checkStandard2d(texture);
  final format = readDataFormat(texture);
  final srgb = format.isSrgb;

  switch (format.colorModel) {
    case kDfModelUastc:
      final levels = <MipLevel>[];
      for (var level = 0; level < texture.levels.length; level++) {
        final size = mipSize(width, height, level);
        final payload = _levelPayload(texture, level);
        levels.add(
          MipLevel(
            size.width,
            size.height,
            decodeUastcRgba8(payload, size.width, size.height),
          ),
        );
      }
      return StandardKtx2Image(
        levels: levels,
        srgb: srgb,
        hasAlpha: format.hasAlpha,
      );
    case kDfModelEtc1s:
      if (texture.supercompression != Ktx2Supercompression.basisLz) {
        throw Ktx2FormatException(
          'ETC1S color model without BasisLZ supercompression',
        );
      }
      final transcoder = Etc1sTranscoder(
        texture.supercompressionGlobalData,
        texture.levels.length,
      );
      final levels = <MipLevel>[];
      for (var level = 0; level < texture.levels.length; level++) {
        final size = mipSize(width, height, level);
        levels.add(
          MipLevel(
            size.width,
            size.height,
            transcoder.decodeImageRgba8(
              texture.levels[level].data,
              level,
              size.width,
              size.height,
            ),
          ),
        );
      }
      return StandardKtx2Image(
        levels: levels,
        srgb: srgb,
        hasAlpha: format.hasAlpha,
      );
    default:
      if (texture.vkFormat == _vkFormatRgba8Unorm ||
          texture.vkFormat == _vkFormatRgba8Srgb) {
        final levels = <MipLevel>[];
        for (var level = 0; level < texture.levels.length; level++) {
          final size = mipSize(width, height, level);
          final payload = _levelPayload(texture, level);
          final byteLength = size.width * size.height * 4;
          if (payload.length < byteLength) {
            throw Ktx2FormatException('Truncated RGBA8 level $level');
          }
          levels.add(
            MipLevel(
              size.width,
              size.height,
              Uint8List.sublistView(payload, 0, byteLength),
            ),
          );
        }
        return StandardKtx2Image(
          levels: levels,
          srgb: srgb || texture.vkFormat == _vkFormatRgba8Srgb,
          hasAlpha: true,
        );
      }
      throw Ktx2FormatException(
        'Unsupported KTX2 color model ${format.colorModel} '
        '(vkFormat ${texture.vkFormat})',
      );
  }
}

/// A level's bytes with the container's supercompression undone.
Uint8List _levelPayload(Ktx2Texture texture, int level) {
  final stored = texture.levels[level];
  switch (texture.supercompression) {
    case Ktx2Supercompression.none:
      return stored.data;
    case Ktx2Supercompression.zstandard:
      return zstdDecompress(stored.data, stored.uncompressedByteLength);
    case Ktx2Supercompression.zlib:
      // TODO(ktx2-zlib): no pure-Dart inflate in the dependency set; zlib
      // supercompression is rare in basis tooling output.
      throw Ktx2FormatException('Zlib supercompression is not supported');
    case Ktx2Supercompression.basisLz:
      // BasisLZ global data pairs with the ETC1S color model; reaching here
      // means the DFD disagrees with the supercompression scheme.
      throw Ktx2FormatException(
        'BasisLZ supercompression outside an ETC1S texture',
      );
  }
}
