// Fits ETC1S endpoints (5-bit base color plus intensity table) to pixels,
// for one block or a whole cluster. Errors are squared distances in a space
// where the metric is Euclidean.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/src/texture/basisu/etc1s_tables.dart';

/// How pixel differences are weighed.
enum Etc1sMetric {
  /// Luma and chroma, weighted like basis_universal's perceptual metric.
  perceptual,

  /// Plain RGB squared error.
  rgb,
}

/// Maps RGB differences into the metric's Euclidean space.
class MetricSpace {
  MetricSpace(this.metric);

  final Etc1sMetric metric;

  // Matches basis_universal's perceptual metric up to a constant.
  static const double _lr = 14 / 64, _lg = 45 / 64, _lb = 5 / 64;
  static final double _crScale = math.sqrt(26 / 128);
  static final double _cbScale = math.sqrt(3 / 128);

  /// Writes the metric coordinates of (r, g, b) at [out]+[o].
  void transform(int r, int g, int b, Float64List out, int o) {
    if (metric == Etc1sMetric.rgb) {
      out[o] = r.toDouble();
      out[o + 1] = g.toDouble();
      out[o + 2] = b.toDouble();
      return;
    }
    final l = r * _lr + g * _lg + b * _lb;
    out[o] = l;
    out[o + 1] = (r - l) * _crScale;
    out[o + 2] = (b - l) * _cbScale;
  }
}

/// An ETC1S endpoint: 5-bit base color and intensity table.
class Etc1sEndpoint {
  Etc1sEndpoint(this.r, this.g, this.b, this.inten);

  final int r;
  final int g;
  final int b;
  final int inten;

  @override
  bool operator ==(Object other) =>
      other is Etc1sEndpoint &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.inten == inten;

  @override
  int get hashCode => ((r * 32 + g) * 32 + b) * 8 + inten;

  @override
  String toString() => 'Etc1sEndpoint($r, $g, $b, $inten)';
}

int _clamp255(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

/// Weighted pixels, with their metric coordinates.
class FitPixels {
  FitPixels(this.space, int capacity)
    : rgb = Int32List(capacity * 3),
      coords = Float64List(capacity * 3),
      weights = Float64List(capacity);

  final MetricSpace space;
  final Int32List rgb;
  final Float64List coords;
  final Float64List weights;
  int length = 0;

  void clear() => length = 0;

  void add(int r, int g, int b, [double weight = 1]) {
    final i = length++;
    rgb[i * 3] = r;
    rgb[i * 3 + 1] = g;
    rgb[i * 3 + 2] = b;
    space.transform(r, g, b, coords, i * 3);
    weights[i] = weight;
  }
}

/// Evaluates and searches ETC1S endpoints. Reuses scratch buffers.
class Etc1sFitter {
  Etc1sFitter(this.space);

  final MetricSpace space;
  final Float64List _palette = Float64List(12);

  /// Loads the four colors of endpoint (r5, g5, b5, inten) into the palette.
  void _loadPalette(int r5, int g5, int b5, int inten) {
    final m = etc1IntenTables[inten];
    final r = expand5(r5), g = expand5(g5), b = expand5(b5);
    for (var s = 0; s < 4; s++) {
      final cr = _clamp255(r + m[s]);
      final cg = _clamp255(g + m[s]);
      final cb = _clamp255(b + m[s]);
      space.transform(cr, cg, cb, _palette, s * 3);
    }
  }

  /// Error of [pixels] with each pixel's best selector (written to
  /// [selectors] if given); stops once it reaches [limit].
  double evaluate(
    FitPixels pixels,
    int r5,
    int g5,
    int b5,
    int inten, {
    Uint8List? selectors,
    double limit = double.infinity,
  }) {
    _loadPalette(r5, g5, b5, inten);
    final p = _palette;
    final c = pixels.coords;
    final w = pixels.weights;
    var total = 0.0;
    for (var i = 0; i < pixels.length; i++) {
      final x = c[i * 3], y = c[i * 3 + 1], z = c[i * 3 + 2];
      var best = double.infinity;
      var bestS = 0;
      for (var s = 0; s < 4; s++) {
        final dx = x - p[s * 3], dy = y - p[s * 3 + 1], dz = z - p[s * 3 + 2];
        final d = dx * dx + dy * dy + dz * dz;
        if (d < best) {
          best = d;
          bestS = s;
        }
      }
      if (selectors != null) selectors[i] = bestS;
      total += best * w[i];
      if (total >= limit) return total;
    }
    return total;
  }

  /// Error of [pixels] with fixed [selectors]; stops once it reaches
  /// [limit].
  double evaluateWithSelectors(
    FitPixels pixels,
    int r5,
    int g5,
    int b5,
    int inten,
    Uint8List selectors, {
    double limit = double.infinity,
  }) {
    _loadPalette(r5, g5, b5, inten);
    final p = _palette;
    final c = pixels.coords;
    final w = pixels.weights;
    var total = 0.0;
    for (var i = 0; i < pixels.length; i++) {
      final s = selectors[i];
      final dx = c[i * 3] - p[s * 3];
      final dy = c[i * 3 + 1] - p[s * 3 + 1];
      final dz = c[i * 3 + 2] - p[s * 3 + 2];
      total += (dx * dx + dy * dy + dz * dz) * w[i];
      if (total >= limit) return total;
    }
    return total;
  }

  /// The exact best endpoint when every pixel has the same color, else
  /// null.
  ({Etc1sEndpoint endpoint, double error})? _solidFit(FitPixels pixels) {
    final rgb = pixels.rgb;
    final r = rgb[0], g = rgb[1], b = rgb[2];
    for (var i = 1; i < pixels.length; i++) {
      if (rgb[i * 3] != r || rgb[i * 3 + 1] != g || rgb[i * 3 + 2] != b) {
        return null;
      }
    }
    var weight = 0.0;
    for (var i = 0; i < pixels.length; i++) {
      weight += pixels.weights[i];
    }
    final target = Float64List(3);
    space.transform(r, g, b, target, 0);
    final decoded = Float64List(3);
    var bestError = double.infinity;
    var best = Etc1sEndpoint(0, 0, 0, 0);
    int nearest(int value, int modifier) {
      var bestV = 0;
      var bestD = 1 << 30;
      for (var v = 0; v < 32; v++) {
        final d = (_clamp255(expand5(v) + modifier) - value).abs();
        if (d < bestD) {
          bestD = d;
          bestV = v;
        }
      }
      return bestV;
    }

    for (var t = 0; t < 8; t++) {
      for (var s = 0; s < 4; s++) {
        final m = etc1IntenTables[t][s];
        final r5 = nearest(r, m), g5 = nearest(g, m), b5 = nearest(b, m);
        space.transform(
          _clamp255(expand5(r5) + m),
          _clamp255(expand5(g5) + m),
          _clamp255(expand5(b5) + m),
          decoded,
          0,
        );
        final dx = decoded[0] - target[0];
        final dy = decoded[1] - target[1];
        final dz = decoded[2] - target[2];
        final error = (dx * dx + dy * dy + dz * dz) * weight;
        if (error < bestError) {
          bestError = error;
          best = Etc1sEndpoint(r5, g5, b5, t);
        }
      }
    }
    return (endpoint: best, error: bestError);
  }

  /// Writes each pixel's error under the endpoint's four colors to [out].
  void texelErrors(
    FitPixels pixels,
    int r5,
    int g5,
    int b5,
    int inten,
    Float64List out,
  ) {
    _loadPalette(r5, g5, b5, inten);
    final p = _palette;
    final c = pixels.coords;
    for (var i = 0; i < pixels.length; i++) {
      final x = c[i * 3], y = c[i * 3 + 1], z = c[i * 3 + 2];
      final w = pixels.weights[i];
      for (var s = 0; s < 4; s++) {
        final dx = x - p[s * 3], dy = y - p[s * 3 + 1], dz = z - p[s * 3 + 2];
        out[i * 4 + s] = (dx * dx + dy * dy + dz * dz) * w;
      }
    }
  }

  final Uint8List _selectors = Uint8List(4096);

  /// Finds a good endpoint for [pixels]. [thorough] adds a neighborhood
  /// search; [start] limits the search to intensities next to its own.
  ({Etc1sEndpoint endpoint, double error}) fit(
    FitPixels pixels, {
    bool thorough = false,
    Etc1sEndpoint? start,
  }) {
    final n = pixels.length;
    final solid = _solidFit(pixels);
    if (solid != null) return solid;
    final selectors = n <= _selectors.length ? _selectors : Uint8List(n);
    // Weighted mean color and luma spread.
    var sw = 0.0, ar = 0.0, ag = 0.0, ab = 0.0;
    var minL = double.infinity, maxL = -double.infinity;
    for (var i = 0; i < n; i++) {
      final w = pixels.weights[i];
      final r = pixels.rgb[i * 3], g = pixels.rgb[i * 3 + 1];
      final b = pixels.rgb[i * 3 + 2];
      sw += w;
      ar += r * w;
      ag += g * w;
      ab += b * w;
      final l = (r + g + b) / 3;
      if (l < minL) minL = l;
      if (l > maxL) maxL = l;
    }
    ar /= sw;
    ag /= sw;
    ab /= sw;

    var bestError = double.infinity;
    var bestR = 0, bestG = 0, bestB = 0, bestT = 0;

    void consider(int r5, int g5, int b5, int t) {
      final e = evaluate(pixels, r5, g5, b5, t, limit: bestError);
      if (e < bestError) {
        bestError = e;
        bestR = r5;
        bestG = g5;
        bestB = b5;
        bestT = t;
      }
    }

    int q(double v) {
      final i = (v * 31 / 255 + 0.5).floor();
      return i < 0 ? 0 : (i > 31 ? 31 : i);
    }

    // Quick fits try the tables that best match the luma spread.
    final half = (maxL - minL) / 2;
    final tables = <int>[];
    if (start != null) {
      consider(start.r, start.g, start.b, start.inten);
      for (var t = start.inten - 1; t <= start.inten + 1; t++) {
        if (t >= 0 && t < 8) tables.add(t);
      }
    } else if (thorough) {
      for (var t = 0; t < 8; t++) {
        tables.add(t);
      }
    } else {
      var nearest = 0;
      for (var t = 1; t < 8; t++) {
        if ((etc1IntenTables[t][3] - half).abs() <
            (etc1IntenTables[nearest][3] - half).abs()) {
          nearest = t;
        }
      }
      tables.add(nearest);
      if (nearest > 0) tables.add(nearest - 1);
      if (nearest < 7) tables.add(nearest + 1);
    }

    for (final t in tables) {
      var r5 = q(ar), g5 = q(ag), b5 = q(ab);
      consider(r5, g5, b5, t);
      if (bestError == 0) break;
      // With selectors fixed, the best base is the mean minus the mean
      // modifier.
      for (var iteration = 0; iteration < 3; iteration++) {
        evaluate(pixels, r5, g5, b5, t, selectors: selectors);
        final m = etc1IntenTables[t];
        final br = expand5(r5), bg = expand5(g5), bb = expand5(b5);
        var dr = 0.0, dg = 0.0, db = 0.0;
        for (var i = 0; i < n; i++) {
          final w = pixels.weights[i];
          final d = m[selectors[i]];
          dr += (_clamp255(br + d) - br) * w;
          dg += (_clamp255(bg + d) - bg) * w;
          db += (_clamp255(bb + d) - bb) * w;
        }
        final nr = q(ar - dr / sw), ng = q(ag - dg / sw), nb = q(ab - db / sw);
        if (nr == r5 && ng == g5 && nb == b5) break;
        r5 = nr;
        g5 = ng;
        b5 = nb;
        consider(r5, g5, b5, t);
      }
      if (bestError == 0) break;
    }

    if (thorough && bestError > 0) {
      // Walk to better neighboring colors and tables.
      for (var round = 0; round < 4; round++) {
        final r0 = bestR, g0 = bestG, b0 = bestB, t0 = bestT;
        final before = bestError;
        for (var t = t0 - 1; t <= t0 + 1; t++) {
          if (t < 0 || t > 7) continue;
          for (var d = -1; d <= 1; d += 2) {
            for (final (dr, dg, db) in [
              (d, 0, 0),
              (0, d, 0),
              (0, 0, d),
              (d, d, d),
            ]) {
              final r5 = r0 + dr, g5 = g0 + dg, b5 = b0 + db;
              if (r5 < 0 || r5 > 31 || g5 < 0 || g5 > 31) continue;
              if (b5 < 0 || b5 > 31) continue;
              consider(r5, g5, b5, t);
            }
          }
          if (t != t0) consider(r0, g0, b0, t);
        }
        if (bestError >= before || bestError == 0) break;
      }
    }
    return (
      endpoint: Etc1sEndpoint(bestR, bestG, bestB, bestT),
      error: bestError,
    );
  }
}
