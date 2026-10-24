import 'dart:math' as math;
import 'dart:typed_data';

/// A synthetic 16-bit scalar field: three Gaussian blobs over a faint cosine
/// lattice. Every term is separable, so a voxel costs a few multiplies of
/// per-axis tables and even 100 million voxels generate in about a second.
class VolumeData {
  VolumeData(this.width, this.height, this.depth)
    : values = _generate(width, height, depth);

  final int width;
  final int height;
  final int depth;

  /// Row by row, slice by slice.
  final Uint16List values;

  int get sliceVoxels => width * height;

  static Uint16List _generate(int w, int h, int d) {
    // (center, sigma, weight) per blob, in normalized coordinates.
    const blobs = [
      (0.38, 0.45, 0.55, 0.16, 0.55),
      (0.66, 0.58, 0.40, 0.12, 0.45),
      (0.52, 0.30, 0.68, 0.09, 0.35),
    ];
    List<Float64List> axis(int n, double Function(double t) f) => [
      Float64List.fromList([for (var i = 0; i < n; i++) f((i + 0.5) / n)]),
    ];
    final gx = <Float64List>[], gy = <Float64List>[], gz = <Float64List>[];
    for (final (cx, cy, cz, sigma, weight) in blobs) {
      double g(double t, double c) =>
          math.exp(-(t - c) * (t - c) / (2 * sigma * sigma));
      gx.addAll(axis(w, (t) => weight * g(t, cx)));
      gy.addAll(axis(h, (t) => g(t, cy)));
      gz.addAll(axis(d, (t) => g(t, cz)));
    }
    double lattice(double t) => 0.5 + 0.5 * math.cos(2 * math.pi * 7 * t);
    final lx = axis(w, (t) => 0.12 * lattice(t)).single;
    final ly = axis(h, lattice).single;
    final lz = axis(d, lattice).single;

    final out = Uint16List(w * h * d);
    var i = 0;
    for (var z = 0; z < d; z++) {
      for (var y = 0; y < h; y++) {
        final r0 = gy[0][y] * gz[0][z];
        final r1 = gy[1][y] * gz[1][z];
        final r2 = gy[2][y] * gz[2][z];
        final rl = ly[y] * lz[z];
        for (var x = 0; x < w; x++) {
          final v = gx[0][x] * r0 + gx[1][x] * r1 + gx[2][x] * r2 + lx[x] * rl;
          out[i++] = v >= 1 ? 65535 : (v * 65535).round();
        }
      }
    }
    return out;
  }
}

/// Where each slice of a [VolumeData] lands in the atlas: tiles of
/// `ceil(width / 2)` x `height` texels (two voxels per RGBA8 texel), laid
/// out row by row on pages no larger than [maxPageSize].
class AtlasLayout {
  factory AtlasLayout(VolumeData volume, {int maxPageSize = 4096}) {
    final tileWidth = (volume.width + 1) ~/ 2;
    final tileHeight = volume.height;
    final slicesPerRow = maxPageSize ~/ tileWidth;
    final rowsPerPage = maxPageSize ~/ tileHeight;
    final slicesPerPage = slicesPerRow * rowsPerPage;
    final pageCount = (volume.depth + slicesPerPage - 1) ~/ slicesPerPage;
    if (pageCount > 4) {
      throw ArgumentError(
        'The volume needs $pageCount atlas pages; the material samples 4.',
      );
    }
    return AtlasLayout._(
      tileWidth,
      tileHeight,
      slicesPerRow,
      slicesPerPage,
      pageCount,
    );
  }

  AtlasLayout._(
    this.tileWidth,
    this.tileHeight,
    this.slicesPerRow,
    this.slicesPerPage,
    this.pageCount,
  );

  final int tileWidth;
  final int tileHeight;
  final int slicesPerRow;
  final int slicesPerPage;
  final int pageCount;

  int get pageWidth => slicesPerRow * tileWidth;

  /// Pages hold only the tile rows they use, so the last can be shorter.
  int pageHeight(int page, int depth) {
    final slices = math.min(slicesPerPage, depth - page * slicesPerPage);
    return ((slices + slicesPerRow - 1) ~/ slicesPerRow) * tileHeight;
  }
}

/// Packs [volume] into RGBA8 atlas pages: per texel, voxel 2n in RG and voxel
/// 2n + 1 in BA, high byte first.
List<Uint8List> packAtlas(VolumeData volume, AtlasLayout layout) {
  final pages = [
    for (var p = 0; p < layout.pageCount; p++)
      Uint8List(layout.pageWidth * layout.pageHeight(p, volume.depth) * 4),
  ];
  final values = volume.values;
  final w = volume.width;
  for (var z = 0; z < volume.depth; z++) {
    final page = pages[z ~/ layout.slicesPerPage];
    final tile = z % layout.slicesPerPage;
    final tileX = (tile % layout.slicesPerRow) * layout.tileWidth;
    final tileY = (tile ~/ layout.slicesPerRow) * layout.tileHeight;
    for (var y = 0; y < volume.height; y++) {
      final source = (z * volume.height + y) * w;
      var target = ((tileY + y) * layout.pageWidth + tileX) * 4;
      for (var x = 0; x < w; x += 2, target += 4) {
        final a = values[source + x];
        final b = x + 1 < w ? values[source + x + 1] : 0;
        page[target] = a >> 8;
        page[target + 1] = a & 0xFF;
        page[target + 2] = b >> 8;
        page[target + 3] = b & 0xFF;
      }
    }
  }
  return pages;
}

/// One rg8 layer per slice, high byte in red.
List<Uint8List> packRg8Slices(VolumeData volume) {
  final n = volume.sliceVoxels;
  return [
    for (var z = 0; z < volume.depth; z++)
      () {
        final layer = Uint8List(n * 2);
        final offset = z * n;
        for (var i = 0; i < n; i++) {
          final v = volume.values[offset + i];
          layer[i * 2] = v >> 8;
          layer[i * 2 + 1] = v & 0xFF;
        }
        return layer;
      }(),
  ];
}

/// One r8 layer per slice, the high byte only.
List<Uint8List> packR8Slices(VolumeData volume) {
  final n = volume.sliceVoxels;
  return [
    for (var z = 0; z < volume.depth; z++)
      () {
        final layer = Uint8List(n);
        final offset = z * n;
        for (var i = 0; i < n; i++) {
          layer[i] = volume.values[offset + i] >> 8;
        }
        return layer;
      }(),
  ];
}

/// One r32Float layer per slice, normalized to [0, 1].
List<Float32List> packR32fSlices(VolumeData volume) {
  final n = volume.sliceVoxels;
  return [
    for (var z = 0; z < volume.depth; z++)
      () {
        final layer = Float32List(n);
        final offset = z * n;
        for (var i = 0; i < n; i++) {
          layer[i] = volume.values[offset + i] / 65535;
        }
        return layer;
      }(),
  ];
}
