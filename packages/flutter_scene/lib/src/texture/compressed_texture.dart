// Uploads a flutter_scene KTX2 texture to the GPU. The CPU-heavy transcode runs
// off the main isolate; only the GPU calls stay on the main thread.
//
// The device may support a block-compressed family directly, in which case the
// block payload is transcoded to that format and uploaded compressed (less
// VRAM): BC1/ETC2-RGB for opaque textures, BC3/ETC2-RGBA8 when the texture
// is marked as carrying alpha, and ASTC either way (its blocks switch to the
// RGBA endpoint mode where needed). Otherwise the payload is decoded to
// rgba8 and uploaded uncompressed, which is always correct (alpha included)
// and the only path on web without the extensions.
//
// Either way, every mip level stored in the container is transcoded and
// uploaded (on backends that can sample hand-uploaded chains), so mipped KTX2
// textures sample with proper minification.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/block/transcode_astc.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc1.dart';
import 'package:flutter_scene/src/texture/block/transcode_bc3.dart';
import 'package:flutter_scene/src/texture/block/transcode_etc2.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/ktx2_image.dart';

/// The order in which compressed families are preferred when the device
/// supports more than one: ASTC (highest quality) > BC (desktop) > ETC2
/// (mobile/GLES3/web). Reorder for testing a specific family on a device that
/// supports several.
List<gpu.TextureCompressionFamily> compressionFamilyPreference = [
  gpu.TextureCompressionFamily.astc,
  gpu.TextureCompressionFamily.bc,
  gpu.TextureCompressionFamily.etc2,
];

// Transcode target, chosen on the main thread (from the device probe) and
// passed to the transcode isolate so it knows which format to produce.
const int _modeRgba8 = 0;
const int _modeBc1 = 1;
const int _modeEtc2 = 2;
const int _modeAstc = 3;
const int _modeBc3 = 4;
const int _modeEtc2Rgba = 5;

/// The transcoded mip levels (base first) ready for GPU upload. Plain data so
/// it can cross an isolate boundary (no GPU types).
typedef _Prepared = ({List<Uint8List> levels, int mode, int width, int height});

/// Reads a flutter_scene KTX2 file from [bytes], transcodes it on a background
/// isolate, and uploads the result. Use this from async load paths so large
/// textures do not block the UI.
Future<gpu.Texture> gpuTextureFromKtx2Async(Uint8List bytes) async {
  _logFamiliesOnce();
  final mode = _selectMode();
  final mips = gpu.gpuContext.doesSupportManuallyMippedTextures;
  final prepared = await compute(_prepareFromBytes, (
    ktx2: bytes,
    mode: mode,
    mips: mips,
  ));
  return _upload(prepared);
}

/// Synchronous variant: transcodes on the calling (usually main) thread. Heavy
/// for large textures; prefer [gpuTextureFromKtx2Async]. Kept for the sync
/// realize path.
gpu.Texture gpuTextureFromKtx2(Uint8List bytes) =>
    gpuTextureFromKtx2Texture(readKtx2(bytes));

/// As [gpuTextureFromKtx2], for an already-parsed [texture].
gpu.Texture gpuTextureFromKtx2Texture(Ktx2Texture texture) {
  _logFamiliesOnce();
  return _upload(
    _prepare(
      texture,
      _selectMode(),
      mips: gpu.gpuContext.doesSupportManuallyMippedTextures,
    ),
  );
}

/// Picks the transcode target for the current device.
int _selectMode() {
  for (final family in compressionFamilyPreference) {
    if (!gpu.gpuContext.supportsTextureCompression(family)) continue;
    switch (family) {
      case gpu.TextureCompressionFamily.astc:
        return _modeAstc;
      case gpu.TextureCompressionFamily.bc:
        return _modeBc1;
      case gpu.TextureCompressionFamily.etc2:
        return _modeEtc2;
      case gpu.TextureCompressionFamily.astcHdr:
        // The transcoder emits LDR formats only; HDR ASTC is not a
        // transcode target, so skip to the next preferred family.
        break;
    }
  }
  return _modeRgba8;
}

/// Isolate entry point: parse and transcode. Pure Dart, no GPU.
_Prepared _prepareFromBytes(({Uint8List ktx2, int mode, bool mips}) input) =>
    _prepare(readKtx2(input.ktx2), input.mode, mips: input.mips);

/// Transcodes the stored mip levels of [texture] to [mode]. Pure Dart, no GPU.
/// When [mips] is false (the backend cannot sample hand-uploaded mip chains),
/// only the base level is produced.
_Prepared _prepare(Ktx2Texture texture, int mode, {required bool mips}) {
  final width = texture.pixelWidth;
  final height = math.max(1, texture.pixelHeight);
  // The container may carry fewer levels than the allocator's chain (a
  // base-only file) or more (a chain reaching 1x1); clamp to what
  // `createTexture(mipLevelCount:)` accepts.
  final levelCount = mips
      ? math.min(texture.levels.length, engineMipLevelCount(width, height))
      : 1;
  // A texture marked as carrying alpha upgrades to the family's alpha
  // format. ASTC needs no upgrade: its transcoder switches non-opaque blocks
  // to the RGBA color endpoint mode within the same 16-byte format.
  if (ktx2HasAlpha(texture)) {
    mode = switch (mode) {
      _modeBc1 => _modeBc3,
      _modeEtc2 => _modeEtc2Rgba,
      _ => mode,
    };
  }
  if (mode == _modeRgba8) {
    final levels = [
      for (var level = 0; level < levelCount; level++)
        decodeKtx2Level(texture, level: level).rgba,
    ];
    return (levels: levels, mode: _modeRgba8, width: width, height: height);
  }
  final levels = <Uint8List>[];
  for (var level = 0; level < levelCount; level++) {
    final size = mipSize(width, height, level);
    final blocks = ktx2LevelBlocks(texture, level);
    final blockCount = ((size.width + 3) ~/ 4) * ((size.height + 3) ~/ 4);
    levels.add(switch (mode) {
      _modeBc1 => transcodeUniversalToBc1(blocks, blockCount),
      _modeBc3 => transcodeUniversalToBc3(blocks, blockCount),
      _modeEtc2 => transcodeUniversalToEtc2Rgb(blocks, blockCount),
      _modeEtc2Rgba => transcodeUniversalToEtc2Rgba(blocks, blockCount),
      _ => transcodeUniversalToAstc4x4(blocks, blockCount),
    });
  }
  return (levels: levels, mode: mode, width: width, height: height);
}

/// Uploads prepared level bytes to a GPU texture. Must run on the main thread.
gpu.Texture _upload(_Prepared p) {
  final gpu.Texture texture;
  if (p.mode == _modeRgba8) {
    texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      p.width,
      p.height,
      mipLevelCount: p.levels.length,
    );
  } else {
    final format = switch (p.mode) {
      _modeBc1 => gpu.PixelFormat.bc1RGBAUNormInt,
      _modeBc3 => gpu.PixelFormat.bc3RGBAUNormInt,
      _modeEtc2 => gpu.PixelFormat.etc2RGB8UNormInt,
      _modeEtc2Rgba => gpu.PixelFormat.etc2RGBA8UNormInt,
      _ => gpu.PixelFormat.astc4x4LDR,
    };
    texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      p.width,
      p.height,
      format: format,
      mipLevelCount: p.levels.length,
      enableRenderTargetUsage: false,
      enableShaderWriteUsage: false,
    );
  }
  for (var level = 0; level < p.levels.length; level++) {
    texture.overwrite(ByteData.sublistView(p.levels[level]), mipLevel: level);
  }
  return texture;
}

bool _logged = false;

/// Logs the device's block-compression family support once. This doubles as the
/// device probe: running an app that loads a KTX2 texture reports which
/// families are available and therefore which upload path is taken.
void _logFamiliesOnce() {
  if (_logged) return;
  _logged = true;
  final context = gpu.gpuContext;
  debugPrint(
    'flutter_scene texture compression support: '
    'bc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.bc)} '
    'etc2=${context.supportsTextureCompression(gpu.TextureCompressionFamily.etc2)} '
    'astc=${context.supportsTextureCompression(gpu.TextureCompressionFamily.astc)} '
    '(transcode runs off the main isolate; rgba8 fallback otherwise)',
  );
}
