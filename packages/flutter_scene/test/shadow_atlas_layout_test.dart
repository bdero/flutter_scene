import 'dart:math' as math;

import 'package:flutter_scene/src/render/shadow_atlas_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every tile lies inside the atlas and no two overlap.
void _expectDisjoint(ShadowAtlasLayout layout) {
  final tiles = [
    ...layout.cascadeTiles,
    ...layout.spotTiles,
    ...layout.pointTiles,
  ];
  for (final t in tiles) {
    expect(t.x, greaterThanOrEqualTo(0));
    expect(t.y, greaterThanOrEqualTo(0));
    expect(t.x + t.size, lessThanOrEqualTo(layout.width), reason: '$t');
    expect(t.y + t.size, lessThanOrEqualTo(layout.height), reason: '$t');
  }
  for (var i = 0; i < tiles.length; i++) {
    for (var j = i + 1; j < tiles.length; j++) {
      final a = tiles[i], b = tiles[j];
      final apart =
          a.x + a.size <= b.x ||
          b.x + b.size <= a.x ||
          a.y + a.size <= b.y ||
          b.y + b.size <= a.y;
      expect(apart, isTrue, reason: '$a overlaps $b');
    }
  }
}

void main() {
  test('nothing casting plans no atlas', () {
    expect(ShadowAtlasLayout.plan(), isNull);
    expect(ShadowAtlasLayout.plan(cascadeCount: 4), isNull);
  });

  test('cascades fill a row at the top-left', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 4,
      cascadeResolution: 2048,
    )!;
    expect((layout.width, layout.height), (8192, 2048));
    expect(layout.cascadeColumns, 4);
    expect(layout.cascadeTiles, [
      for (var i = 0; i < 4; i++) ShadowAtlasTile(i * 2048, 0, 2048),
    ]);
  });

  test('cascades wider than the limit wrap into a grid', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 4,
      cascadeResolution: 4096,
    )!;
    expect((layout.width, layout.height), (8192, 8192));
    expect(layout.cascadeColumns, 2);
    expect(layout.cascadeTiles[3], const ShadowAtlasTile(4096, 4096, 4096));
    _expectDisjoint(layout);
  });

  test('a spot keeps its own resolution beside large cascades', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 4,
      cascadeResolution: 2048,
      spotResolutions: [512],
    )!;
    expect(layout.spotTiles.single, const ShadowAtlasTile(0, 2048, 512));
    expect((layout.width, layout.height), (8192, 2560));
    _expectDisjoint(layout);
  });

  test('spots and points get tiles of their own sizes', () {
    final layout = ShadowAtlasLayout.plan(
      spotResolutions: [1024, 256],
      pointFaceResolutions: [512, 128],
    )!;
    expect(layout.spotTiles.map((t) => t.size), [1024, 256]);
    expect(layout.pointTiles.map((t) => t.size), [1024, 1024, 256, 256]);
    expect(layout.cascadeTiles, isEmpty);
    _expectDisjoint(layout);
  });

  test('a tile fills the space beside short cascades', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 3,
      cascadeResolution: 1024,
      spotResolutions: [1024],
    )!;
    expect((layout.width, layout.height), (4096, 1024));
    expect(layout.spotTiles.single, const ShadowAtlasTile(3072, 0, 1024));
  });

  test('cascades shrink only once the other tiles are at the minimum', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 4,
      cascadeResolution: 4096,
      spotResolutions: [512],
    )!;
    expect(layout.cascadeResolution, 2048);
    expect(layout.spotTiles.single.size, 512);
    _expectDisjoint(layout);
  });

  test('tiles halve until the atlas fits', () {
    final layout = ShadowAtlasLayout.plan(
      cascadeCount: 4,
      cascadeResolution: 1024,
      spotResolutions: [2048, 2048, 2048, 2048],
      maxDimension: 4096,
    )!;
    expect(layout.cascadeResolution, 1024);
    expect(layout.spotTiles.map((t) => t.size), everyElement(1024));
    expect(layout.width, lessThanOrEqualTo(4096));
    expect(layout.height, lessThanOrEqualTo(4096));
    _expectDisjoint(layout);
  });

  test('random mixes stay disjoint and within the limit', () {
    final random = math.Random(7);
    const sizes = [128, 256, 512, 1024, 2048, 4096];
    for (var trial = 0; trial < 300; trial++) {
      final layout = ShadowAtlasLayout.plan(
        cascadeCount: random.nextInt(5),
        cascadeResolution: sizes[random.nextInt(sizes.length)],
        spotResolutions: [
          for (var i = random.nextInt(5); i > 0; i--)
            sizes[random.nextInt(sizes.length)],
        ],
        pointFaceResolutions: [
          for (var i = random.nextInt(5); i > 0; i--)
            sizes[random.nextInt(sizes.length)],
        ],
      );
      if (layout == null) continue;
      expect(layout.width, lessThanOrEqualTo(kShadowAtlasMaxDimension));
      expect(layout.height, lessThanOrEqualTo(kShadowAtlasMaxDimension));
      _expectDisjoint(layout);
    }
  });

  test('uvRect maps a tile into atlas UV', () {
    const tile = ShadowAtlasTile(512, 256, 256);
    final rect = tile.uvRect(1024, 512);
    expect(rect.storage, [0.5, 0.5, 0.25, 0.5]);
  });
}
