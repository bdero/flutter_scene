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

/// The transcoded bytes ready for GPU upload. Plain data so it can cross an
/// isolate boundary (no GPU types).
typedef _Prepared = ({Uint8List bytes, int mode, int width, int height});

/// Reads a flutter_scene KTX2 file from [bytes], transcodes it on a background
/// isolate, and uploads the result. Use this from async load paths so large
/// textures do not block the UI.
Future<gpu.Texture> gpuTextureFromKtx2Async(Uint8List bytes) async {
  _logFamiliesOnce();
  final mode = _selectMode();
  final prepared = await compute(_prepareFromBytes, (ktx2: bytes, mode: mode));
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
  return _upload(_prepare(texture, _selectMode()));
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
_Prepared _prepareFromBytes(({Uint8List ktx2, int mode}) input) =>
    _prepare(readKtx2(input.ktx2), input.mode);

/// Transcodes the base level of [texture] to [mode]. Pure Dart, no GPU.
_Prepared _prepare(Ktx2Texture texture, int mode) {
  final size = mipSize(
    texture.pixelWidth,
    texture.pixelHeight < 1 ? 1 : texture.pixelHeight,
    0,
  );
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
    final base = decodeKtx2Level(texture, level: 0);
    return (
      bytes: base.rgba,
      mode: _modeRgba8,
      width: base.width,
      height: base.height,
    );
  }
  final blocks = ktx2LevelBlocks(texture, 0);
  final blockCount = ((size.width + 3) ~/ 4) * ((size.height + 3) ~/ 4);
  final bytes = switch (mode) {
    _modeBc1 => transcodeUniversalToBc1(blocks, blockCount),
    _modeBc3 => transcodeUniversalToBc3(blocks, blockCount),
    _modeEtc2 => transcodeUniversalToEtc2Rgb(blocks, blockCount),
    _modeEtc2Rgba => transcodeUniversalToEtc2Rgba(blocks, blockCount),
    _ => transcodeUniversalToAstc4x4(blocks, blockCount),
  };
  return (bytes: bytes, mode: mode, width: size.width, height: size.height);
}

/// Uploads prepared bytes to a GPU texture. Must run on the main thread.
gpu.Texture _upload(_Prepared p) {
  if (p.mode == _modeRgba8) {
    final texture = gpu.gpuContext.createTexture(
      gpu.StorageMode.hostVisible,
      p.width,
      p.height,
    );
    texture.overwrite(ByteData.sublistView(p.bytes));
    return texture;
  }
  // TODO(texture-compression): upload the full mip chain once Flutter GPU can
  // mark/generate sampleable mipmaps; today the base level is uploaded alone.
  final format = switch (p.mode) {
    _modeBc1 => gpu.PixelFormat.bc1RGBAUNormInt,
    _modeBc3 => gpu.PixelFormat.bc3RGBAUNormInt,
    _modeEtc2 => gpu.PixelFormat.etc2RGB8UNormInt,
    _modeEtc2Rgba => gpu.PixelFormat.etc2RGBA8UNormInt,
    _ => gpu.PixelFormat.astc4x4LDR,
  };
  final texture = gpu.gpuContext.createTexture(
    gpu.StorageMode.hostVisible,
    p.width,
    p.height,
    format: format,
    enableRenderTargetUsage: false,
    enableShaderWriteUsage: false,
  );
  texture.overwrite(ByteData.sublistView(p.bytes));
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
