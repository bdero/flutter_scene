// Loads standard KTX2 textures (glTF KHR_texture_basisu) to GPU textures.
// The parse and decode run on one background isolate for a whole batch, so an
// import with several KTX2 textures builds the transcoder's lookup tables
// once; only the uploads run on the main thread.
//
// UASTC repacks to ASTC where supported. ETC1S transcodes to ETC2 (exact) or
// else BC. Everything else decodes to rgba8.
// TODO(uastc-bc7-transcode): a BC7 repack would give BC-only desktops the
// same compressed path for UASTC; they fall back to rgba8 today.

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/basisu/basis_ktx2.dart';
import 'package:flutter_scene/src/texture/basisu/etc1s_targets.dart';
import 'package:flutter_scene/src/texture/compressed_texture.dart';
import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

/// One decode request: a standard KTX2 file plus the mip downsample content
/// for a base-only file whose chain the engine generates.
typedef StandardKtx2Request = ({Uint8List bytes, TextureContent content});

/// The GPU format a standard KTX2 file uploads in.
enum StandardKtx2Upload {
  /// Decoded pixels.
  rgba8,

  /// UASTC blocks repacked to ASTC 4x4.
  astc4x4,

  /// ETC1S as ETC1 blocks, uploaded as ETC2 RGB8.
  etc2Rgb,

  /// ETC1S as ETC2 RGBA8 blocks.
  etc2Rgba,

  /// ETC1S as BC1 blocks.
  bc1,

  /// ETC1S as BC3 blocks.
  bc3,
}

/// The block-compression families a device samples.
typedef CompressionSupport = ({bool astc, bool etc2, bool bc});

/// The families the current GPU context samples.
CompressionSupport currentCompressionSupport() {
  final context = gpu.gpuContext;
  return (
    astc: context.supportsTextureCompression(gpu.TextureCompressionFamily.astc),
    etc2: context.supportsTextureCompression(gpu.TextureCompressionFamily.etc2),
    bc: context.supportsTextureCompression(gpu.TextureCompressionFamily.bc),
  );
}

/// Picks the upload format for a standard KTX2 file. A base-only file that
/// needs a mip chain ([mips] with one [storedLevels]) decodes to rgba8 so the
/// engine can build one, as does ETC1S that is not whole 4x4 blocks.
StandardKtx2Upload chooseStandardKtx2Upload({
  required int colorModel,
  required bool hasAlpha,
  required int width,
  required int height,
  required int storedLevels,
  required bool mips,
  required CompressionSupport support,
}) {
  if (mips && storedLevels < 2) return StandardKtx2Upload.rgba8;
  switch (colorModel) {
    case kDfModelUastc:
      return support.astc
          ? StandardKtx2Upload.astc4x4
          : StandardKtx2Upload.rgba8;
    case kDfModelEtc1s:
      if (width % 4 != 0 || height % 4 != 0) return StandardKtx2Upload.rgba8;
      if (support.etc2) {
        return hasAlpha
            ? StandardKtx2Upload.etc2Rgba
            : StandardKtx2Upload.etc2Rgb;
      }
      if (support.bc) {
        return hasAlpha ? StandardKtx2Upload.bc3 : StandardKtx2Upload.bc1;
      }
      return StandardKtx2Upload.rgba8;
    default:
      return StandardKtx2Upload.rgba8;
  }
}

/// A decoded file: levels in [upload]'s format, base first, or an [error].
typedef StandardKtx2Decoded = ({
  String? error,
  StandardKtx2Upload upload,
  List<MipLevel> levels,
});

/// Decodes a batch of standard KTX2 files off the main isolate and uploads
/// each to a GPU texture. A file that fails to decode yields null alongside a
/// debug message, so one bad texture cannot sink an import.
Future<List<Texture2D?>> loadStandardKtx2Batch(
  List<StandardKtx2Request> requests,
) async {
  if (requests.isEmpty) return const [];
  final decoded = await compute(_decodeBatch, (
    requests: requests,
    mips: uploadableMipChains,
    support: currentCompressionSupport(),
  ));
  final out = <Texture2D?>[];
  for (final result in decoded) {
    if (result.error != null) {
      debugPrint('Failed to decode KTX2 texture: ${result.error}');
      out.add(null);
      continue;
    }
    out.add(Texture2D.fromGpuTexture(uploadStandardKtx2(result)));
  }
  return out;
}

/// Uploads a decoded file in its [StandardKtx2Decoded.upload] format. Must
/// run on the main thread.
gpu.Texture uploadStandardKtx2(StandardKtx2Decoded decoded) {
  final levels = decoded.levels;
  final format = switch (decoded.upload) {
    StandardKtx2Upload.rgba8 => null,
    StandardKtx2Upload.astc4x4 => gpu.PixelFormat.astc4x4LDR,
    StandardKtx2Upload.etc2Rgb => gpu.PixelFormat.etc2RGB8UNormInt,
    StandardKtx2Upload.etc2Rgba => gpu.PixelFormat.etc2RGBA8UNormInt,
    StandardKtx2Upload.bc1 => gpu.PixelFormat.bc1RGBAUNormInt,
    StandardKtx2Upload.bc3 => gpu.PixelFormat.bc3RGBAUNormInt,
  };
  if (format == null) {
    return uploadMipLevels(levels, levels.first.width, levels.first.height);
  }
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    levels.first.width,
    levels.first.height,
    format: format,
    mipLevelCount: levels.length,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
  );
  for (var level = 0; level < levels.length; level++) {
    texture.overwrite(
      ByteData.sublistView(levels[level].pixels),
      mipLevel: level,
    );
  }
  return texture;
}

/// Isolate entry point for [loadStandardKtx2Batch].
List<StandardKtx2Decoded> _decodeBatch(
  ({List<StandardKtx2Request> requests, bool mips, CompressionSupport support})
  input,
) => [
  for (final request in input.requests)
    decodeStandardKtx2ForUpload(
      request,
      mips: input.mips,
      support: input.support,
    ),
];

/// Decodes one standard KTX2 file for a device with [support]: its stored
/// chain when [mips], else the base level. Pure Dart; returns errors rather
/// than throwing.
StandardKtx2Decoded decodeStandardKtx2ForUpload(
  StandardKtx2Request request, {
  required bool mips,
  required CompressionSupport support,
}) {
  try {
    final texture = readKtx2(request.bytes);
    final format = readDataFormat(texture);
    final width = texture.pixelWidth;
    final height = texture.pixelHeight == 0 ? 1 : texture.pixelHeight;
    final maxLevels = mips ? engineMipLevelCount(width, height) : 1;
    final upload = chooseStandardKtx2Upload(
      colorModel: format.colorModel,
      hasAlpha: format.hasAlpha,
      width: width,
      height: height,
      storedLevels: texture.levels.length,
      mips: mips,
      support: support,
    );
    final List<BlockLevel>? blocks = switch (upload) {
      StandardKtx2Upload.rgba8 => null,
      StandardKtx2Upload.astc4x4 => repackStandardKtx2ToAstc(
        texture,
        maxLevels,
      ),
      StandardKtx2Upload.etc2Rgb => transcodeStandardKtx2Etc1s(
        texture,
        Etc1sTarget.etc1,
        maxLevels,
      ),
      StandardKtx2Upload.etc2Rgba => transcodeStandardKtx2Etc1s(
        texture,
        Etc1sTarget.etc2Rgba,
        maxLevels,
      ),
      StandardKtx2Upload.bc1 => transcodeStandardKtx2Etc1s(
        texture,
        Etc1sTarget.bc1,
        maxLevels,
      ),
      StandardKtx2Upload.bc3 => transcodeStandardKtx2Etc1s(
        texture,
        Etc1sTarget.bc3,
        maxLevels,
      ),
    };
    if (blocks != null) {
      return (
        error: null,
        upload: upload,
        levels: [
          for (final level in blocks)
            MipLevel(level.width, level.height, level.blocks),
        ],
      );
    }
    final image = decodeStandardKtx2(texture);
    var levels = image.levels;
    if (!mips) {
      levels = [levels.first];
    } else if (levels.length == 1) {
      // A base-only file still gets a generated chain, downsampled for the
      // texture's content like every other engine texture. The file's own
      // transfer function wins over the material role, a linear-tagged
      // color texture averages directly rather than in linear-from-sRGB.
      var content = request.content;
      if (content == TextureContent.color && !image.srgb) {
        content = TextureContent.data;
      }
      final base = levels.first;
      levels = generateMipChain(base.pixels, base.width, base.height, content);
    }
    return (error: null, upload: StandardKtx2Upload.rgba8, levels: levels);
  } catch (e) {
    return (error: '$e', upload: StandardKtx2Upload.rgba8, levels: const []);
  }
}

/// Loads a single KTX2 payload, routing the engine's own cooked files through
/// the internal transcode path and standard files through
/// [loadStandardKtx2Batch].
/// TODO(ktx2-public-loader): promote a public entry point once the API shape
/// (sampling, content, batching) settles; this stays internal until then.
Future<Texture2D?> loadKtx2Texture(
  Uint8List bytes, {
  TextureContent content = TextureContent.color,
}) async {
  final Ktx2Texture parsed;
  try {
    parsed = readKtx2(bytes);
  } on Ktx2FormatException catch (e) {
    debugPrint('Failed to parse KTX2 texture: $e');
    return null;
  }
  if (isInternalKtx2(parsed)) {
    final gpu.Texture texture = await gpuTextureFromKtx2Async(bytes);
    return Texture2D.fromGpuTexture(texture);
  }
  final results = await loadStandardKtx2Batch([
    (bytes: bytes, content: content),
  ]);
  return results.single;
}
