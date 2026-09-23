import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter_scene/noise.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// What a die is made of.
enum DiceFinish {
  classic('Resin', Color(0xFFE85D4A)),
  glass('Glass', Color(0xFF9BD6F5)),
  frosted('Frosted', Color(0xFFDCEBF3)),
  iridescent('Opal', Color(0xFFC9B6F0)),
  wood('Wood', Color(0xFFB0703F)),
  marble('Marble', Color(0xFFE8E4DE)),
  gold('Gold', Color(0xFFE0B04A)),
  steel('Steel', Color(0xFF9EA6AE)),
  neon('Neon', Color(0xFF3CF2B0)),
  mixed('Mix', Color(0xFFFFFFFF));

  const DiceFinish(this.label, this.swatch);

  final String label;
  final Color swatch;

  /// The finishes a die can actually be made of, in the order a mixed
  /// handful cycles through them (the first three make the default trio).
  static const List<DiceFinish> concrete = [
    glass,
    gold,
    wood,
    iridescent,
    neon,
    marble,
    steel,
    frosted,
    classic,
  ];

  bool get isGlass => this == glass || this == frosted || this == iridescent;

  /// How much of a glass die's footprint its shadow proxy covers, or null
  /// for a finish that casts its own shadow. The proxy is alpha-masked with
  /// an ordered dither at this coverage, so the shadow reads lighter once
  /// the light's softness blurs the dots.
  double? get shadowCoverage => switch (this) {
    glass => 0.38,
    iridescent => 0.5,
    frosted => 0.68,
    _ => null,
  };

  /// The landing sound set for this finish (`assets/sounds/land_<set>_*`),
  /// or null to use the table's own.
  String? get landingSet => switch (this) {
    glass || frosted || iridescent => 'glass',
    gold || steel => 'metal',
    wood => 'wood',
    marble => 'stone',
    _ => null,
  };

  /// Pitch multiplier for this finish's impact sounds. Glass rings high,
  /// wood knocks low.
  double get impactPitch => switch (this) {
    glass || iridescent => 1.3,
    frosted => 1.22,
    marble => 1.14,
    steel => 1.1,
    gold => 1.04,
    wood => 0.88,
    _ => 1.0,
  };
}

/// The die colors, one per die index, as linear RGBA.
final List<vm.Vector4> dieColors = [
  vm.Vector4(0.95, 0.93, 0.88, 1),
  vm.Vector4(0.86, 0.22, 0.20, 1),
  vm.Vector4(0.20, 0.42, 0.86, 1),
  vm.Vector4(0.22, 0.66, 0.42, 1),
  vm.Vector4(0.95, 0.70, 0.20, 1),
  vm.Vector4(0.55, 0.32, 0.80, 1),
];

/// Textures shared by every die material. Each is a 6x1 atlas, one cell per
/// face value, matching the die geometry's UV layout.
class DieTextures {
  DieTextures._({
    required this.pips,
    required this.glassPips,
    required this.pipGlow,
    required this.wood,
    required this.marble,
  });

  /// White faces, dark pips. Doubles as the transmission mask (the red
  /// channel), so glass stays clear between opaque pips.
  final Texture2D pips;

  /// [pips] with translucent faces, for glass drawn without a backdrop to
  /// refract (the pips stay solid).
  final Texture2D glassPips;

  /// Black faces, white pips, the neon emissive mask.
  final Texture2D pipGlow;

  final Texture2D wood;
  final Texture2D marble;

  /// Dithered alpha masks by coverage, for the glass shadow proxies. Pips
  /// are always solid.
  final Map<double, Texture2D> _shadowMasks = {};
  late final Float32List _pipCoverage128;

  Texture2D shadowMask(double coverage) => _shadowMasks.putIfAbsent(
    coverage,
    () => _fromCoverage(128, _pipCoverage128, (c, x, y) {
      // A 4x4 Bayer matrix over 4 px cells; a cell is solid when its
      // threshold falls under the wanted coverage.
      const bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
      final cx = (x ~/ 4) % 4, cy = (y ~/ 4) % 4;
      final threshold = (bayer[cy * 4 + cx] + 0.5) / 16.0;
      final solid = c > 0.5 || threshold < coverage;
      return (255, 255, 255, solid ? 255.0 : 0.0);
    }),
  );

  /// Bakes every atlas. Call after `Scene.initializeStaticResources()`.
  static DieTextures bake() {
    final pipCoverage = _pipCoverage(128);
    final grainCoverage = _pipCoverage(192);
    final textures = DieTextures._(
      pips: _fromCoverage(128, pipCoverage, (c, _, _) {
        final shade = 255 - c * 227;
        return (shade, shade, shade, 255.0);
      }),
      glassPips: _fromCoverage(128, pipCoverage, (c, _, _) {
        final shade = 255 - c * 215;
        return (shade, shade, shade, 255 * (0.6 + 0.4 * c));
      }),
      pipGlow: _fromCoverage(128, pipCoverage, (c, _, _) {
        final v = 8 + c * 247;
        return (v, v, v, 255.0);
      }),
      wood: _bakeWood(192, grainCoverage),
      marble: _bakeMarble(192, grainCoverage),
    );
    textures._pipCoverage128 = pipCoverage;
    return textures;
  }

  /// Pip coverage per texel for a 6x1 atlas of [cell]-sized faces.
  static Float32List _pipCoverage(int cell) {
    const lo = 0.27, mid = 0.5, hi = 0.73;
    const layouts = <List<(double, double)>>[
      [(mid, mid)],
      [(lo, lo), (hi, hi)],
      [(lo, lo), (mid, mid), (hi, hi)],
      [(lo, lo), (hi, lo), (lo, hi), (hi, hi)],
      [(lo, lo), (hi, lo), (mid, mid), (lo, hi), (hi, hi)],
      [(lo, lo), (hi, lo), (lo, mid), (hi, mid), (lo, hi), (hi, hi)],
    ];
    final pipRadius = cell * 0.095;
    final coverage = Float32List(cell * 6 * cell);
    for (var y = 0; y < cell; y++) {
      for (var x = 0; x < cell * 6; x++) {
        final value = x ~/ cell;
        final cx = x - value * cell + 0.5;
        final cy = y + 0.5;
        var c = 0.0;
        for (final (px, py) in layouts[value]) {
          final dx = cx - px * cell, dy = cy - py * cell;
          final d = math.sqrt(dx * dx + dy * dy);
          c = math.max(c, (pipRadius - d + 0.5).clamp(0.0, 1.0));
        }
        coverage[y * cell * 6 + x] = c;
      }
    }
    return coverage;
  }

  static Texture2D _fromCoverage(
    int cell,
    Float32List coverage,
    (double, double, double, double) Function(double coverage, int x, int y)
    shade,
  ) {
    final width = cell * 6;
    final pixels = Uint8List(width * cell * 4);
    for (var y = 0; y < cell; y++) {
      for (var x = 0; x < width; x++) {
        final (r, g, b, a) = shade(coverage[y * width + x], x, y);
        final o = (y * width + x) * 4;
        pixels[o] = r.round().clamp(0, 255);
        pixels[o + 1] = g.round().clamp(0, 255);
        pixels[o + 2] = b.round().clamp(0, 255);
        pixels[o + 3] = a.round().clamp(0, 255);
      }
    }
    return Texture2D.fromPixels(pixels, width, cell);
  }

  /// Growth rings seen at a slant, warped by noise, with fine grain along
  /// the ring direction. Pips are burnt in dark.
  static Texture2D _bakeWood(int cell, Float32List coverage) {
    final warp = FastNoiseLite()
      ..seed = 11
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 3;
    final grain = FastNoiseLite()
      ..seed = 12
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 2;
    const light = (0.80, 0.58, 0.36);
    const dark = (0.50, 0.30, 0.15);
    return _fromCoverage(cell, coverage, (c, x, y) {
      final face = x ~/ cell;
      final u = (x - face * cell + 0.5) / cell;
      final v = (y + 0.5) / cell;
      // Each face cuts the log at its own offset so the rings differ.
      final px = u * 2.2 + face * 1.7;
      final py = v * 2.2 + face * 0.6;
      final w = warp.getNoise2(px * 1.3, py * 1.3) * 0.35;
      final rings = ((px + w) * 0.55 + (py + w) * 0.15) * 4.0;
      var ring = rings - rings.floorToDouble();
      // Sharp early-wood to late-wood transition.
      ring = math.pow(ring, 2.4).toDouble();
      final streak =
          grain.getNoise2(px * 3.0, py * 40.0 + face * 9.0) * 0.5 + 0.5;
      final t = (ring * 0.7 + streak * 0.3).clamp(0.0, 1.0);
      var r = light.$1 + (dark.$1 - light.$1) * t;
      var g = light.$2 + (dark.$2 - light.$2) * t;
      var b = light.$3 + (dark.$3 - light.$3) * t;
      // Burnt pips.
      r = r + (0.12 - r) * c;
      g = g + (0.07 - g) * c;
      b = b + (0.04 - b) * c;
      return (r * 255, g * 255, b * 255, 255.0);
    });
  }

  /// White marble with grey veins and a faint gold thread.
  static Texture2D _bakeMarble(int cell, Float32List coverage) {
    final turbulence = FastNoiseLite()
      ..seed = 21
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 4;
    final thread = FastNoiseLite()
      ..seed = 22
      ..frequency = 1.0
      ..fractalType = FractalType.fbm
      ..octaves = 3;
    return _fromCoverage(cell, coverage, (c, x, y) {
      final face = x ~/ cell;
      final u = (x - face * cell + 0.5) / cell;
      final v = (y + 0.5) / cell;
      final px = u * 1.6 + face * 2.3;
      final py = v * 1.6 + face * 1.1;
      final n = turbulence.getNoise2(px, py);
      final vein = math.pow((math.sin((px + py) * 2.4 + n * 4.5)).abs(), 6.0);
      final gold = math.pow(
        (math.sin(
          (px - py * 0.7) * 3.1 + thread.getNoise2(px * 2, py * 2) * 5,
        )).abs(),
        18.0,
      );
      var r = 0.93 - 0.45 * vein + 0.02 * gold;
      var g = 0.92 - 0.47 * vein - 0.10 * gold;
      var b = 0.90 - 0.50 * vein - 0.35 * gold;
      r = r + (0.16 - r) * c;
      g = g + (0.16 - g) * c;
      b = b + (0.18 - b) * c;
      return (r * 255, g * 255, b * 255, 255.0);
    });
  }
}

/// Builds the material for die [index] in [finish]. Glass finishes refract
/// the scene behind them when [refractive]; without a backdrop in the scene
/// there is nothing to refract, so they fall back to plain alpha blending
/// composited over the widgets.
PhysicallyBasedMaterial buildDieMaterial(
  DiceFinish finish,
  int index,
  DieTextures textures, {
  required bool refractive,
  double thickness = 0.7,
}) {
  final color = dieColors[index % dieColors.length];
  final material = PhysicallyBasedMaterial()..metallicFactor = 0.0;
  switch (finish) {
    case DiceFinish.classic:
      material
        ..baseColorTexture = textures.pips
        ..baseColorFactor = color
        ..roughnessFactor = 0.32;
    case DiceFinish.glass:
      _glass(
        material,
        textures,
        tint: vm.Vector4(
          0.55 + 0.45 * color.x,
          0.55 + 0.45 * color.y,
          0.55 + 0.45 * color.z,
          1,
        ),
        attenuation: color,
        roughness: 0.04,
        refractive: refractive,
        thickness: thickness,
      );
    case DiceFinish.frosted:
      _glass(
        material,
        textures,
        tint: vm.Vector4(0.92, 0.95, 0.98, 1),
        attenuation: vm.Vector4(
          0.7 + 0.3 * color.x,
          0.7 + 0.3 * color.y,
          0.7 + 0.3 * color.z,
          1,
        ),
        roughness: 0.42,
        refractive: refractive,
        thickness: thickness,
        compositedAlpha: 0.6,
      );
    case DiceFinish.iridescent:
      _glass(
        material,
        textures,
        tint: vm.Vector4(0.9, 0.9, 0.95, 1),
        attenuation: vm.Vector4(0.85, 0.85, 0.95, 1),
        roughness: 0.06,
        refractive: refractive,
        thickness: thickness,
      );
      material
        ..iridescence = 1.0
        ..iridescenceIor = 1.8
        ..iridescenceThicknessMinimum = 120.0 + 60.0 * (index % 3)
        ..iridescenceThicknessMaximum = 520.0 + 80.0 * (index % 3);
    case DiceFinish.wood:
      material
        ..baseColorTexture = textures.wood
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
        ..roughnessFactor = 0.55
        ..clearcoat = 0.7
        ..clearcoatRoughness = 0.12;
    case DiceFinish.marble:
      material
        ..baseColorTexture = textures.marble
        ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
        ..roughnessFactor = 0.22
        ..specular = 0.9;
    case DiceFinish.gold:
      material
        ..baseColorTexture = textures.pips
        ..baseColorFactor = vm.Vector4(1.0, 0.76, 0.33, 1)
        ..metallicFactor = 1.0
        ..roughnessFactor = 0.22;
    case DiceFinish.steel:
      material
        ..baseColorTexture = textures.pips
        ..baseColorFactor = vm.Vector4(0.82, 0.84, 0.86, 1)
        ..metallicFactor = 1.0
        ..roughnessFactor = 0.38
        ..anisotropy = 0.85
        ..anisotropyRotation = 0.35 * index;
    case DiceFinish.neon:
      material
        ..baseColorTexture = textures.pips
        ..baseColorFactor = vm.Vector4(0.07, 0.07, 0.09, 1)
        ..roughnessFactor = 0.28
        ..emissiveTexture = textures.pipGlow
        ..emissiveFactor = vm.Vector4(color.x, color.y, color.z, 1)
        ..emissiveStrength = 5.0;
    case DiceFinish.mixed:
      throw ArgumentError('mixed is a picker choice, not a finish');
  }
  return material;
}

void _glass(
  PhysicallyBasedMaterial material,
  DieTextures textures, {
  required vm.Vector4 tint,
  required vm.Vector4 attenuation,
  required double roughness,
  required bool refractive,
  required double thickness,
  double compositedAlpha = 0.45,
}) {
  material
    ..roughnessFactor = roughness
    ..ior = 1.5;
  if (refractive) {
    material
      ..baseColorTexture = textures.pips
      ..baseColorFactor = tint
      ..transmission = 1.0
      ..transmissionTexture = textures.pips
      ..thickness = thickness
      ..attenuationColor = attenuation
      ..attenuationDistance = 1.6
      ..dispersion = 0.12;
    return;
  }
  // Composited over the widgets by Flutter, so alpha stands in for
  // refraction. The pips keep full alpha through the texture.
  material
    ..baseColorTexture = textures.glassPips
    ..baseColorFactor = vm.Vector4(
      tint.x * (0.6 + 0.4 * attenuation.x),
      tint.y * (0.6 + 0.4 * attenuation.y),
      tint.z * (0.6 + 0.4 * attenuation.z),
      compositedAlpha / 0.6,
    )
    ..alphaMode = AlphaMode.blend;
}

/// The material for a glass die's shadow proxy, or null when [finish] casts
/// its own shadow. Alpha-masked so only the dithered texels cast.
PhysicallyBasedMaterial? buildShadowProxyMaterial(
  DiceFinish finish,
  DieTextures textures,
) {
  final coverage = finish.shadowCoverage;
  if (coverage == null) return null;
  return PhysicallyBasedMaterial()
    ..baseColorTexture = textures.shadowMask(coverage)
    ..alphaMode = AlphaMode.mask
    ..alphaCutoff = 0.5;
}
