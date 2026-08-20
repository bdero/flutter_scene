// Loads standard KTX2 textures (glTF KHR_texture_basisu) to GPU textures.
// The parse and decode run on one background isolate for a whole batch, so an
// import with several KTX2 textures builds the transcoder's lookup tables
// once; only the uploads run on the main thread.
//
// On devices with ASTC support, UASTC files repack straight to ASTC 4x4
// blocks and upload compressed (the blocks are pixel-identical, so no decode
// happens at all). Everything else, and every file on other devices, decodes
// to rgba8.
// TODO(uastc-bc7-transcode): a BC7 repack would give BC-only desktops the
// same compressed path; they fall back to rgba8 today.

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/basisu/basis_ktx2.dart';
import 'package:flutter_scene/src/texture/compressed_texture.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:flutter_scene/src/texture/texture2d.dart';

/// One decode request: a standard KTX2 file plus the mip downsample content
/// for a base-only file whose chain the engine generates.
typedef StandardKtx2Request = ({Uint8List bytes, TextureContent content});

/// A decoded file: rgba8 or ASTC mip levels (byte payload per level, base
/// first), or an error message.
typedef _DecodeResult = ({String? error, bool astc, List<MipLevel> levels});

/// Decodes a batch of standard KTX2 files off the main isolate and uploads
/// each to a GPU texture. A file that fails to decode yields null alongside a
/// debug message, so one bad texture cannot sink an import.
Future<List<Texture2D?>> loadStandardKtx2Batch(
  List<StandardKtx2Request> requests,
) async {
  if (requests.isEmpty) return const [];
  final mips = uploadableMipChains;
  final astc = gpu.gpuContext.supportsTextureCompression(
    gpu.TextureCompressionFamily.astc,
  );
  final decoded = await compute(_decodeBatch, (
    requests: requests,
    mips: mips,
    astc: astc,
  ));
  final out = <Texture2D?>[];
  for (final result in decoded) {
    if (result.error != null) {
      debugPrint('Failed to decode KTX2 texture: ${result.error}');
      out.add(null);
      continue;
    }
    final levels = result.levels;
    final gpu.Texture texture;
    if (result.astc) {
      texture = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        levels.first.width,
        levels.first.height,
        format: gpu.PixelFormat.astc4x4LDR,
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
    } else {
      texture = uploadMipLevels(
        levels,
        levels.first.width,
        levels.first.height,
      );
    }
    out.add(Texture2D.fromGpuTexture(texture));
  }
  return out;
}

/// Isolate entry point: parse, decompress, and transcode to RGBA8 chains or
/// ASTC blocks. Pure Dart, no GPU.
List<_DecodeResult> _decodeBatch(
  ({List<StandardKtx2Request> requests, bool mips, bool astc}) input,
) {
  final results = <_DecodeResult>[];
  for (final request in input.requests) {
    try {
      final texture = readKtx2(request.bytes);
      if (input.astc) {
        // A UASTC file's blocks repack losslessly to ASTC, but only the
        // file's own chain; a base-only file that needs generated mips takes
        // the rgba8 path instead.
        final maxLevels = input.mips
            ? engineMipLevelCount(
                texture.pixelWidth,
                texture.pixelHeight == 0 ? 1 : texture.pixelHeight,
              )
            : 1;
        final astcLevels = repackStandardKtx2ToAstc(texture, maxLevels);
        if (astcLevels != null && (!input.mips || astcLevels.length > 1)) {
          results.add((
            error: null,
            astc: true,
            levels: [
              for (final level in astcLevels)
                MipLevel(level.width, level.height, level.blocks),
            ],
          ));
          continue;
        }
      }
      final image = decodeStandardKtx2(texture);
      var levels = image.levels;
      if (!input.mips) {
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
        levels = generateMipChain(
          base.pixels,
          base.width,
          base.height,
          content,
        );
      }
      results.add((error: null, astc: false, levels: levels));
    } catch (e) {
      results.add((error: '$e', astc: false, levels: const []));
    }
  }
  return results;
}

/// Loads a single KTX2 payload, routing the engine's own cooked files through
/// the internal transcode path and standard files through the RGBA8 decode.
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
