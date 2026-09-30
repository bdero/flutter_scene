// Encodes RGBA8 images as standard ETC1S/BasisLZ KTX2 files, in pure Dart.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/ktx2/dfd.dart';
import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';
import 'package:flutter_scene/src/texture/mipmap.dart';

import 'package:flutter_scene/src/texture/basisu/encode/basislz_writer.dart';
import 'package:flutter_scene/src/texture/basisu/encode/etc1s_fit.dart';
import 'package:flutter_scene/src/texture/basisu/encode/etc1s_frontend.dart';

/// Settings for [encodeEtc1sKtx2].
class Etc1sEncodeOptions {
  const Etc1sEncodeOptions({
    this.quality = 128,
    this.mipmaps = true,
    this.content = TextureContent.color,
  }) : assert(quality >= 1 && quality <= 255, 'quality is 1 to 255');

  /// 1 (smallest) to 255 (best), on basis_universal's scale.
  final int quality;

  /// Whether to store a full mip chain, downsampled for [content].
  final bool mipmaps;

  /// Color is tagged sRGB and fitted perceptually; data and normal maps are
  /// tagged linear and fitted in RGB.
  final TextureContent content;
}

/// Encodes [width] x [height] RGBA8 [rgba] as an ETC1S KTX2 file.
Uint8List encodeEtc1sKtx2(
  Uint8List rgba,
  int width,
  int height, {
  Etc1sEncodeOptions options = const Etc1sEncodeOptions(),
}) {
  if (width < 1 || height < 1 || width > 16384 || height > 16384) {
    throw ArgumentError('Unsupported size ${width}x$height');
  }
  if (rgba.length < width * height * 4) {
    throw ArgumentError('rgba is too small for ${width}x$height');
  }
  if (options.quality < 1 || options.quality > 255) {
    throw ArgumentError.value(options.quality, 'quality', 'must be 1 to 255');
  }
  final levels = options.mipmaps
      ? generateMipChain(rgba, width, height, options.content)
      : [MipLevel(width, height, rgba)];
  var hasAlpha = false;
  for (var i = 3; i < width * height * 4 && !hasAlpha; i += 4) {
    hasAlpha = rgba[i] != 255;
  }

  // TODO(etc1s-encode-scale): encoding is single-threaded, and the fit
  // buffers are sized to the largest cluster, so a 4096x4096 texture with
  // alpha takes minutes and about 1 GB. Split the work across isolates and
  // bound the per-cluster buffers.
  // Color and alpha slices share the codebooks.
  final sliceSizes = <(int, int)>[];
  var blockCount = 0;
  for (final level in levels) {
    final bx = (level.width + 3) >> 2, by = (level.height + 3) >> 2;
    sliceSizes.add((bx, by));
    blockCount += bx * by * (hasAlpha ? 2 : 1);
  }
  final blocks = Uint8List(blockCount * 48);
  var block = 0;
  for (final level in levels) {
    for (final alpha in hasAlpha ? const [false, true] : const [false]) {
      block = _gatherBlocks(level, alpha, blocks, block);
    }
  }

  final totalTexels = blockCount * 16;
  final (endpointClusters, selectorClusters) = _codebookSizes(
    options.quality,
    totalTexels,
    blockCount,
  );
  final metric = options.content == TextureContent.color
      ? Etc1sMetric.perceptual
      : Etc1sMetric.rgb;
  final quantized = quantizeEtc1s(
    Etc1sSourceBlocks(blocks, blockCount),
    Etc1sQuantizerOptions(
      endpointClusters: endpointClusters,
      selectorClusters: selectorClusters,
      metric: metric,
    ),
  );

  final images = <Etc1sImage>[];
  var first = 0;
  Etc1sSlice slice(int bx, int by) {
    final count = bx * by;
    final s = Etc1sSlice(
      bx,
      by,
      Int32List.sublistView(quantized.blockEndpoints, first, first + count),
      Int32List.sublistView(quantized.blockSelectors, first, first + count),
    );
    first += count;
    return s;
  }

  for (final (bx, by) in sliceSizes) {
    final rgb = slice(bx, by);
    images.add(Etc1sImage(rgb, hasAlpha ? slice(bx, by) : null));
  }
  final sliceStarts = <int>[];
  var start = 0;
  for (final image in images) {
    for (final s in [image.rgb, ?image.alpha]) {
      sliceStarts.add(start);
      start += s.blocksX * s.blocksY;
    }
  }
  final payload = writeBasisLz(
    endpoints: quantized.endpoints,
    selectors: quantized.selectors,
    images: images,
    rdo: _rdoFor(
      options.quality,
      _BlockErrors(quantized, sliceStarts, MetricSpace(metric)),
    ),
  );

  return writeKtx2(
    Ktx2Texture(
      vkFormat: 0,
      pixelWidth: width,
      pixelHeight: height,
      levels: [
        for (final bytes in payload.images)
          Ktx2Level(data: bytes, uncompressedByteLength: 0),
      ],
      supercompression: Ktx2Supercompression.basisLz,
      dataFormatDescriptor: _etc1sDataFormat(
        srgb: options.content == TextureContent.color,
        alpha: hasAlpha,
      ),
      keyValues: {
        'KTXwriter': Uint8List.fromList(utf8.encode('flutter_scene\u0000')),
      },
      supercompressionGlobalData: payload.globalData,
      levelAlignment: 1,
    ),
  );
}

/// Copies [level]'s 4x4 blocks (color, or alpha as gray) into [out] from
/// block [first], clamping at the edges.
int _gatherBlocks(MipLevel level, bool alpha, Uint8List out, int first) {
  final int w = level.width, h = level.height;
  final px = level.pixels;
  var block = first;
  for (var by = 0; by < h; by += 4) {
    for (var bx = 0; bx < w; bx += 4) {
      var o = block * 48;
      for (var y = 0; y < 4; y++) {
        final sy = by + y < h ? by + y : h - 1;
        for (var x = 0; x < 4; x++) {
          final sx = bx + x < w ? bx + x : w - 1;
          final s = (sy * w + sx) * 4;
          if (alpha) {
            // TODO(etc1s-alpha-error): alpha blocks are fitted and scored in
            // RGB though the decoder reads only green; scoring green alone
            // would spend the error budget where it shows.
            out[o] = out[o + 1] = out[o + 2] = px[s + 3];
          } else {
            out[o] = px[s];
            out[o + 1] = px[s + 1];
            out[o + 2] = px[s + 2];
          }
          o += 3;
        }
      }
      block++;
    }
  }
  return block;
}

/// Codebook sizes for [quality], after basis_universal's mapping.
(int, int) _codebookSizes(int quality, int totalTexels, int totalBlocks) {
  const maxEndpoints = maxEtc1sCodebookEntries;
  const maxSelectors = maxEtc1sCodebookEntries;
  final q = quality / 255;
  const mid = 128 / 255;
  final texelBudget = totalTexels ~/ 14;
  int endpoints;
  if (q <= mid) {
    final t = 0.5 * math.pow(q / mid, 0.65);
    var budget = math.min(texelBudget.clamp(256, 4800), totalBlocks);
    budget = math.max(budget, 64);
    endpoints = (32 + (budget - 32) * t + 0.5).floor();
  } else {
    final t = math.pow((q - mid) / (1 - mid), 1.6);
    var budget = math.min(texelBudget.clamp(256, 8192), totalBlocks);
    budget = math.max(budget, 4800);
    endpoints = (4800 + (budget - 4800) * t + 0.5).floor();
  }
  final selectorBudget = math.max(
    math.min(texelBudget.clamp(256, maxSelectors), totalBlocks),
    96,
  );
  final s = math.pow(q, 2.62);
  final selectors = (96 + (selectorBudget - 96) * s + 0.5).floor();
  return (endpoints.clamp(32, maxEndpoints), selectors.clamp(8, maxSelectors));
}

/// Rate-distortion thresholds for [quality], tightening above 128 as
/// basis_universal does.
Etc1sRdo _rdoFor(int quality, Etc1sBlockErrors errors) {
  var scale = 1.0;
  if (quality >= 223) {
    scale = 0.25;
  } else if (quality >= 192) {
    scale = 0.5;
  } else if (quality >= 160) {
    scale = 0.75;
  } else if (quality >= 129) {
    scale = 1 - 0.25 * (quality - 129) / (160 - 129);
  }
  return Etc1sRdo(
    errors,
    endpointThreshold: 1.5 * scale,
    selectorThreshold: 1.25 * scale,
  );
}

/// The ETC1S data format descriptor basisu writes.
Uint8List _etc1sDataFormat({required bool srgb, required bool alpha}) {
  final samples = alpha ? 2 : 1;
  // 44 or 60 bytes, the only sizes basisu accepts.
  final size = 28 + 16 * samples;
  final dfd = ByteData(size);
  dfd
    ..setUint32(0, size, Endian.little)
    ..setUint32(4, 0, Endian.little) // vendor 0, type 0
    ..setUint16(8, 2, Endian.little) // version
    ..setUint16(10, size - 4, Endian.little)
    ..setUint8(12, kDfModelEtc1s)
    ..setUint8(13, 1) // BT.709 primaries
    ..setUint8(14, srgb ? 2 : 1) // sRGB or linear transfer
    ..setUint8(15, 0) // straight alpha
    ..setUint8(16, 3) // 4x4 texel blocks, stored minus one
    ..setUint8(17, 3)
    ..setUint8(20, 8) // bytes per plane: 8 per slice
    ..setUint8(21, alpha ? 8 : 0);
  for (var s = 0; s < samples; s++) {
    final o = 28 + s * 16;
    dfd
      ..setUint16(o, s * 64, Endian.little) // bit offset
      ..setUint8(o + 2, 63) // bit length minus one
      ..setUint8(o + 3, s == 0 ? 0 : 15) // RGB, then AAA
      ..setUint32(o + 12, 0xFFFFFFFF, Endian.little);
  }
  return dfd.buffer.asUint8List();
}

/// Block errors for the writer, in the quantizer's metric.
class _BlockErrors implements Etc1sBlockErrors {
  _BlockErrors(this.quantized, this.sliceStarts, MetricSpace space)
    : fitter = Etc1sFitter(space),
      pixels = FitPixels(space, 16);

  final Etc1sQuantized quantized;
  final List<int> sliceStarts;
  final Etc1sFitter fitter;
  final FitPixels pixels;

  /// Per texel, its error under each of the fixed endpoint's four colors.
  final Float64List _texelErrors = Float64List(64);

  @override
  void fixEndpoint(int r5, int g5, int b5, int inten) =>
      fitter.texelErrors(pixels, r5, g5, b5, inten, _texelErrors);

  @override
  double selectorError(Uint8List selectors, {double limit = double.infinity}) {
    var total = 0.0;
    for (var i = 0; i < 16; i++) {
      total += _texelErrors[i * 4 + selectors[i]];
      if (total >= limit) return total;
    }
    return total;
  }

  @override
  void load(int slice, int block) {
    final u = quantized.blockToUnique[sliceStarts[slice] + block];
    final rgb = quantized.uniqueBlocks;
    pixels.clear();
    for (var i = 0; i < 16; i++) {
      final o = u * 48 + i * 3;
      pixels.add(rgb[o], rgb[o + 1], rgb[o + 2]);
    }
  }

  @override
  double error(
    int r5,
    int g5,
    int b5,
    int inten,
    Uint8List selectors, {
    double limit = double.infinity,
  }) => fitter.evaluateWithSelectors(
    pixels,
    r5,
    g5,
    b5,
    inten,
    selectors,
    limit: limit,
  );
}
