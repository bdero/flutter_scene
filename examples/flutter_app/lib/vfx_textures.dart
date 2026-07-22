// Procedurally baked sprite textures shared by the particle examples
// (campfire and explosions): flame and fireball flipbooks, an eroding smoke
// flipbook, and a soft dot, all generated from fbm noise at load time.
// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/src/noise/fast_noise_lite.dart';

double vfxSmoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Maps a normalized temperature to an approximate blackbody color (sRGB),
/// from extinguished black through deep red, orange, and yellow to
/// near-white.
(double, double, double) vfxBlackbody(double temp) {
  const stops = <(double, double, double, double)>[
    (0.0, 0.0, 0.0, 0.0),
    (0.20, 0.32, 0.02, 0.0),
    (0.45, 0.85, 0.22, 0.01),
    (0.70, 1.0, 0.62, 0.10),
    (0.88, 1.0, 0.86, 0.42),
    (1.0, 1.0, 0.98, 0.82),
  ];
  final t = temp.clamp(0.0, 1.0);
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i].$1) {
      final a = stops[i - 1];
      final b = stops[i];
      final f = (t - a.$1) / (b.$1 - a.$1);
      return (
        a.$2 + (b.$2 - a.$2) * f,
        a.$3 + (b.$3 - a.$3) * f,
        a.$4 + (b.$4 - a.$4) * f,
      );
    }
  }
  return (1.0, 0.98, 0.82);
}

Future<ui.Image> vfxImageFromPixels(Uint8List pixels, int size) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    size,
    size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes the 8x8 flame flipbook (frame 0 top-left, row major). Each frame is
/// one flame tongue's whole life: it grows from the base, rolls upward under
/// a domain-warped fbm field, then detaches and erodes away, with brightness
/// mapped through the blackbody ramp. A particle plays the sequence exactly
/// once over its lifetime, so erosion is baked rather than shaded.
Future<ui.Image> bakeFlameAtlas() async {
  const grid = 8;
  const cell = 96;
  const size = grid * cell;
  const frames = grid * grid;
  final pixels = Uint8List(size * size * 4);

  final warpNoise = FastNoiseLite()
    ..seed = 7
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  final mainNoise = FastNoiseLite()
    ..seed = 8
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    // Small per-frame steps keep adjacent frames similar; the sequence plays
    // at ~40-50 fps over a particle's life, so large steps read as strobing.
    final evolve = f * 0.055;
    final scroll = f * 0.10;

    // Lifecycle envelope: the flame grows in quickly, then its base lifts
    // off the ground late in life while the whole tongue shortens and
    // erodes.
    final grow = vfxSmoothstep(0.0, 0.18, t);
    final baseY = 0.5 * pow(vfxSmoothstep(0.40, 1.0, t), 1.2);
    final height =
        0.92 * (0.3 + 0.7 * grow) * (1 - 0.35 * vfxSmoothstep(0.5, 1.0, t));
    final erosion = 0.12 + 0.55 * vfxSmoothstep(0.35, 1.0, t);
    final cooling = 1.0 - 0.40 * vfxSmoothstep(0.45, 1.0, t);

    final cellX = (f % grid) * cell;
    final cellY = (f ~/ grid) * cell;
    for (var py = 0; py < cell; py++) {
      // Row 0 renders at the sprite's top, so flip to a bottom-up y.
      final y = 1.0 - (py + 0.5) / cell;
      final rowBase = ((cellY + py) * size + cellX) * 4;
      for (var px = 0; px < cell; px++) {
        final x = ((px + 0.5) / cell) * 2.0 - 1.0;

        var value = 0.0;
        var detail = 0.5;
        final h = height > 0 ? (y - baseY) / height : -1.0;
        if (h >= 0.0 && h <= 1.0) {
          // Horizontal domain warp, stronger toward the tip, makes the
          // silhouette lick and split instead of staying a teardrop.
          final w = warpNoise.getNoise3(
            x * 2.2,
            y * 2.2 - scroll * 1.6,
            evolve + 37.7,
          );
          final xw = x + w * 0.30 * (0.35 + 0.65 * h);

          final halfW =
              0.52 *
              (1 - 0.30 * t) *
              pow(1 - h, 0.65) *
              (0.30 + 0.70 * vfxSmoothstep(0.0, 0.18, h));
          if (halfW > 1e-4) {
            final d = (xw / halfW).abs();
            final radial = (1 - d * d).clamp(0.0, 1.0);
            final n =
                mainNoise.getNoise3(xw * 2.6, y * 3.2 - scroll * 2.2, evolve) *
                    0.5 +
                0.5;
            final density = radial * (0.45 + 0.55 * n) * 1.35;
            final threshold = erosion + 0.30 * h;
            value = ((density - threshold) / 0.22).clamp(0.0, 1.0);
            detail = n;
          }
        }

        // Modulate the interior by the same noise so the core keeps hot and
        // cool filaments instead of saturating to a flat white.
        final temp =
            (value *
                    (1.12 - 0.45 * h.clamp(0.0, 1.0)) *
                    (0.68 + 0.55 * detail) *
                    cooling)
                .clamp(0.0, 1.0);
        final (r, g, b) = vfxBlackbody(temp);
        final alpha = (value * 1.45).clamp(0.0, 1.0);
        final o = rowBase + px * 4;
        pixels[o] = (r * 255).round();
        pixels[o + 1] = (g * 255).round();
        pixels[o + 2] = (b * 255).round();
        pixels[o + 3] = (alpha * 255).round();
      }
    }
    // Yield between frames so the loading UI stays responsive.
    if (f % 8 == 7) await Future<void>.delayed(Duration.zero);
  }
  return vfxImageFromPixels(pixels, size);
}

/// Bakes the 8x8 fireball flipbook (played once over life): a turbulent
/// radial ball that flashes white-hot, rolls as it expands, then erodes away
/// through cooling blackbody colors.
Future<ui.Image> bakeFireballAtlas() async {
  const grid = 8;
  const cell = 96;
  const size = grid * cell;
  const frames = grid * grid;
  final pixels = Uint8List(size * size * 4);

  final warpNoise = FastNoiseLite()
    ..seed = 57
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;
  final mainNoise = FastNoiseLite()
    ..seed = 58
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 3;

  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    final evolve = f * 0.05;
    // The ball reaches full radius quickly and holds while it erodes.
    final radius = 0.55 + 0.4 * vfxSmoothstep(0.0, 0.35, t);
    final erosion = 0.10 + 0.72 * vfxSmoothstep(0.25, 1.0, t);
    final cooling = 1.0 - 0.55 * vfxSmoothstep(0.2, 1.0, t);

    final cellX = (f % grid) * cell;
    final cellY = (f ~/ grid) * cell;
    for (var py = 0; py < cell; py++) {
      final y = ((py + 0.5) / cell) * 2.0 - 1.0;
      final rowBase = ((cellY + py) * size + cellX) * 4;
      for (var px = 0; px < cell; px++) {
        final x = ((px + 0.5) / cell) * 2.0 - 1.0;

        // Radial warp rolls the ball's surface as it grows.
        final w = warpNoise.getNoise3(x * 2.4, y * 2.4, evolve + 11.1);
        final r = sqrt(x * x + y * y) + w * 0.22;
        final radial = (1.0 - (r / radius) * (r / radius)).clamp(0.0, 1.0);
        final n = mainNoise.getNoise3(x * 2.8, y * 2.8, evolve) * 0.5 + 0.5;
        final density = radial * (0.4 + 0.6 * n) * 1.5;
        final value = ((density - erosion) / 0.25).clamp(0.0, 1.0);

        final temp = (value * (0.7 + 0.6 * n) * cooling).clamp(0.0, 1.0);
        final (cr, cg, cb) = vfxBlackbody(temp);
        final alpha = (value * 1.5).clamp(0.0, 1.0);
        final o = rowBase + px * 4;
        pixels[o] = (cr * 255).round();
        pixels[o + 1] = (cg * 255).round();
        pixels[o + 2] = (cb * 255).round();
        pixels[o + 3] = (alpha * 255).round();
      }
    }
    if (f % 8 == 7) await Future<void>.delayed(Duration.zero);
  }
  return vfxImageFromPixels(pixels, size);
}

/// Bakes the 4x4 smoke flipbook (played once over life): a billowy fbm puff
/// with baked shading that is progressively eaten by a rising erosion
/// threshold, so old smoke tears apart instead of uniformly fading.
Future<ui.Image> bakeSmokeAtlas() async {
  const grid = 4;
  const cell = 128;
  const size = grid * cell;
  const frames = grid * grid;
  final pixels = Uint8List(size * size * 4);

  final noise = FastNoiseLite()
    ..seed = 17
    ..frequency = 1.0
    ..fractalType = FractalType.fbm
    ..octaves = 4;

  for (var f = 0; f < frames; f++) {
    final t = f / (frames - 1);
    final evolve = f * 0.22;
    final erosion = 0.18 + 0.55 * vfxSmoothstep(0.2, 1.0, t);

    final cellX = (f % grid) * cell;
    final cellY = (f ~/ grid) * cell;
    for (var py = 0; py < cell; py++) {
      final y = ((py + 0.5) / cell) * 2.0 - 1.0;
      final rowBase = ((cellY + py) * size + cellX) * 4;
      for (var px = 0; px < cell; px++) {
        final x = ((px + 0.5) / cell) * 2.0 - 1.0;
        final r2 = x * x + y * y;
        final base = (1 - r2).clamp(0.0, 1.0);

        // Billow noise (folded fbm) gives the cauliflower look.
        final n = noise.getNoise3(x * 1.9, y * 1.9, evolve);
        final billow = 1.0 - n.abs();
        final density = base * (0.35 + 0.65 * billow * billow);
        // A softer edge and a late-life fade keep eroded frames wispy rather
        // than stringy.
        final value =
            ((density - erosion) / 0.42).clamp(0.0, 1.0) *
            (1.0 - 0.45 * vfxSmoothstep(0.5, 1.0, t));

        // Bake soft self-shading, brighter toward the puff's upper lobe.
        final shade = (0.62 + 0.38 * billow) * (0.85 - 0.15 * y);
        final o = rowBase + px * 4;
        final v = (shade.clamp(0.0, 1.0) * 255).round();
        pixels[o] = v;
        pixels[o + 1] = v;
        pixels[o + 2] = v;
        pixels[o + 3] = (value * 255).round();
      }
    }
    if (f % 4 == 3) await Future<void>.delayed(Duration.zero);
  }
  return vfxImageFromPixels(pixels, size);
}

/// A 64x64 white dot with a Gaussian falloff (slope zero at the rim), for
/// embers, sparks, and glows.
Future<ui.Image> bakeSoftDot() {
  const size = 64;
  final pixels = Uint8List(size * size * 4);
  const half = size / 2;
  const sigma = size * 0.20;
  final rim = exp(-0.5 * (half / sigma) * (half / sigma));
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x + 0.5 - half;
      final dy = y + 0.5 - half;
      final r = sqrt(dx * dx + dy * dy);
      final g = exp(-0.5 * (r / sigma) * (r / sigma));
      final a = ((g - rim) / (1.0 - rim)).clamp(0.0, 1.0);
      final i = (y * size + x) * 4;
      pixels[i] = 255;
      pixels[i + 1] = 255;
      pixels[i + 2] = 255;
      pixels[i + 3] = (a * 255).round();
    }
  }
  return vfxImageFromPixels(pixels, size);
}
