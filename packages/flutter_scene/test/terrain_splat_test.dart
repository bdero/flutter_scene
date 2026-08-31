// Terrain texture painting. The invariant everything else rests on is that a
// texel's four weights sum to one: painting a layer up has to paint the others
// down, or ground painted over twice comes out brighter than ground painted
// once.

import 'dart:typed_data';

import 'package:flutter_scene/src/geometry/terrain_brush.dart';
import 'package:flutter_scene/src/geometry/terrain_splat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TerrainSplatMap makeMap({int columns = 33, int rows = 33}) =>
      TerrainSplatMap.base(width: 32, depth: 32, columns: columns, rows: rows);

  /// The sum of a texel's weights, which must always be one.
  double sumAt(TerrainSplatMap map, int c, int r) {
    var total = 0.0;
    for (var layer = 0; layer < terrainSplatLayers; layer++) {
      total += map.weightAt(c, r, layer);
    }
    return total;
  }

  void expectNormalized(TerrainSplatMap map, {String? reason}) {
    for (var r = 0; r < map.rows; r++) {
      for (var c = 0; c < map.columns; c++) {
        expect(
          sumAt(map, c, r),
          closeTo(1, 1e-5),
          reason: reason ?? 'texel ($c, $r) does not sum to one',
        );
      }
    }
  }

  group('a fresh map', () {
    test('is entirely the base layer', () {
      final map = makeMap();
      expect(map.weightAt(0, 0, 0), 1);
      expect(map.weightAt(16, 16, 1), 0);
      expect(map.dominantLayerAtWorld(0, 0), 0);
      expectNormalized(map);
    });

    test('covers the terrain it paints', () {
      final map = TerrainSplatMap.base(width: 64, depth: 32);
      expect(map.width, 64);
      expect(map.depth, 32);
    });

    test('has its own resolution, not the height grid\'s', () {
      // Painting wants finer detail than sculpting: a footpath is narrower
      // than any sensible sculpting cell.
      final map = TerrainSplatMap.base(
        width: 32,
        depth: 32,
        columns: 512,
        rows: 512,
      );
      expect(map.columns, 512);
      expect(map.weights.length, 512 * 512 * 4);
    });
  });

  group('painting', () {
    test('puts the layer down under the brush', () {
      final map = makeMap();
      final touched = paintTerrainSplat(
        map,
        layer: 1,
        brush: const TerrainBrush(radius: 6, strength: 1, falloff: 0),
        x: 0,
        z: 0,
      );
      expect(touched, isNotNull);
      expect(map.dominantLayerAtWorld(0, 0), 1);
    });

    test('and leaves the ground outside it alone', () {
      final map = makeMap();
      paintTerrainSplat(
        map,
        layer: 1,
        brush: const TerrainBrush(radius: 4),
        x: 0,
        z: 0,
      );
      expect(map.dominantLayerAtWorld(-15, -15), 0);
    });

    test('paints the other layers down as it goes', () {
      // The whole point of normalizing: layer 1 arriving means layer 0
      // leaving, so two coats are not brighter than one.
      final map = makeMap();
      for (var i = 0; i < 40; i++) {
        paintTerrainSplat(
          map,
          layer: 1,
          brush: const TerrainBrush(radius: 6, strength: 2, falloff: 0),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      expectNormalized(map);
      // Layer 0 started at one and is on its way out; layer 1 now dominates.
      expect(map.weightAt(16, 16, 0), lessThan(0.4));
      expect(map.weightAt(16, 16, 1), greaterThan(map.weightAt(16, 16, 0)));
    });

    test('a soft brush fades out toward its rim', () {
      final map = makeMap();
      for (var i = 0; i < 30; i++) {
        paintTerrainSplat(
          map,
          layer: 2,
          brush: const TerrainBrush(radius: 10, strength: 2, falloff: 0.2),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      final centre = map.weightAt(16, 16, 2);
      final middle = map.weightAt(16 + 6, 16, 2);
      final outside = map.weightAt(16 + 12, 16, 2);
      expect(centre, greaterThan(middle));
      expect(middle, greaterThan(outside));
      expect(outside, 0);
    });

    test('target strength caps how far a layer gets', () {
      // What lets a brush tint ground rather than only replace it: at 0.5 the
      // layers underneath keep showing through however long you hold it.
      final map = makeMap();
      for (var i = 0; i < 400; i++) {
        paintTerrainSplat(
          map,
          layer: 1,
          brush: const TerrainBrush(radius: 6, strength: 4, falloff: 0),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
          targetStrength: 0.5,
        );
      }
      expect(map.weightAt(16, 16, 1), closeTo(0.5, 0.02));
      expect(map.weightAt(16, 16, 0), greaterThan(0.4));
      expectNormalized(map);
    });

    test('holding a full brush settles rather than creeping past one', () {
      final map = makeMap();
      for (var i = 0; i < 600; i++) {
        paintTerrainSplat(
          map,
          layer: 3,
          brush: const TerrainBrush(radius: 6, strength: 5, falloff: 0),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      expect(map.weightAt(16, 16, 3), closeTo(1, 1e-4));
      expectNormalized(map);
    });

    test('painting rate follows the time step, not the call count', () {
      // A stroke sampled twice as often must not paint twice as fast, or the
      // brush behaves differently on a machine with a better frame rate.
      final fast = makeMap();
      final slow = makeMap();
      for (var i = 0; i < 120; i++) {
        paintTerrainSplat(
          fast,
          layer: 1,
          brush: const TerrainBrush(radius: 6, strength: 1, falloff: 0),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 120,
        );
      }
      for (var i = 0; i < 60; i++) {
        paintTerrainSplat(
          slow,
          layer: 1,
          brush: const TerrainBrush(radius: 6, strength: 1, falloff: 0),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      expect(fast.weightAt(16, 16, 1), closeTo(slow.weightAt(16, 16, 1), 0.05));
    });

    test('reports the texels it touched, for a partial re-upload', () {
      final map = makeMap();
      final touched = paintTerrainSplat(
        map,
        layer: 1,
        brush: const TerrainBrush(radius: 4),
        x: 0,
        z: 0,
      )!;
      expect(touched.minColumn, greaterThan(0));
      expect(touched.maxColumn, lessThan(map.columns - 1));
      expect(touched.minRow, greaterThan(0));
      expect(touched.maxRow, lessThan(map.rows - 1));
    });

    test('a stroke off the edge reports nothing rather than throwing', () {
      final map = makeMap();
      expect(
        paintTerrainSplat(
          map,
          layer: 1,
          brush: const TerrainBrush(radius: 2),
          x: 500,
          z: 500,
        ),
        isNull,
      );
    });

    test('a stroke overhanging the edge paints what it reaches', () {
      final map = makeMap();
      final touched = paintTerrainSplat(
        map,
        layer: 1,
        brush: const TerrainBrush(radius: 6, strength: 4, falloff: 0),
        x: -16,
        z: 0,
      );
      expect(touched, isNotNull);
      expect(touched!.minColumn, 0);
      expect(map.weightAt(0, 16, 1), greaterThan(0));
      expectNormalized(map);
    });

    test('a layer outside the four is refused, not written past the end', () {
      final map = makeMap();
      final brush = const TerrainBrush(radius: 4);
      expect(
        paintTerrainSplat(map, layer: 4, brush: brush, x: 0, z: 0),
        isNull,
      );
      expect(
        paintTerrainSplat(map, layer: -1, brush: brush, x: 0, z: 0),
        isNull,
      );
    });

    test('a negative strength still paints, it does not erase', () {
      // Erasing a layer means painting a different one; a brush that quietly
      // subtracted would leave texels summing to less than one.
      final map = makeMap();
      paintTerrainSplat(
        map,
        layer: 1,
        brush: const TerrainBrush(radius: 6, strength: -2, falloff: 0),
        x: 0,
        z: 0,
      );
      expect(map.weightAt(16, 16, 1), greaterThan(0));
      expectNormalized(map);
    });

    test(
      'painting a second layer over a first blends rather than replaces',
      () {
        final map = makeMap();
        for (var i = 0; i < 60; i++) {
          paintTerrainSplat(
            map,
            layer: 1,
            brush: const TerrainBrush(radius: 8, strength: 3, falloff: 0),
            x: 0,
            z: 0,
            deltaSeconds: 1 / 60,
          );
        }
        for (var i = 0; i < 20; i++) {
          paintTerrainSplat(
            map,
            layer: 2,
            brush: const TerrainBrush(radius: 8, strength: 1, falloff: 0),
            x: 0,
            z: 0,
            deltaSeconds: 1 / 60,
            targetStrength: 0.4,
          );
        }
        expect(map.weightAt(16, 16, 1), greaterThan(0.1));
        expect(map.weightAt(16, 16, 2), greaterThan(0.1));
        expectNormalized(map);
      },
    );
  });

  group('asking what the ground is', () {
    test('the weights interpolate between texels', () {
      final map = makeMap();
      for (var i = 0; i < 30; i++) {
        paintTerrainSplat(
          map,
          layer: 1,
          brush: const TerrainBrush(radius: 8, strength: 3, falloff: 0.1),
          x: -8,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      final out = Float32List(terrainSplatLayers);
      map.weightsAtWorld(-8, 0, out);
      final atCentre = out[1];
      map.weightsAtWorld(0, 0, out);
      expect(atCentre, greaterThan(out[1]));
    });

    test('off the patch clamps to the edge rather than wrapping', () {
      // A character walking off the end reads the border, the same way it
      // reads the border height.
      final map = makeMap();
      for (var i = 0; i < 40; i++) {
        paintTerrainSplat(
          map,
          layer: 2,
          brush: const TerrainBrush(radius: 6, strength: 4, falloff: 0),
          x: -16,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      expect(map.dominantLayerAtWorld(-1000, 0), 2);
    });

    test('the dominant layer is the one showing most', () {
      final map = makeMap();
      for (var i = 0; i < 60; i++) {
        paintTerrainSplat(
          map,
          layer: 3,
          brush: const TerrainBrush(radius: 6, strength: 3, falloff: 0),
          x: 4,
          z: 4,
          deltaSeconds: 1 / 60,
        );
      }
      expect(map.dominantLayerAtWorld(4, 4), 3);
      expect(map.dominantLayerAtWorld(-12, -12), 0);
    });
  });

  group('the document form', () {
    test('a fresh map round trips', () {
      final map = makeMap();
      final back = TerrainSplatMap.fromBytes(
        map.toBytes(),
        columns: map.columns,
        rows: map.rows,
        width: map.width,
        depth: map.depth,
      )!;
      expect(back.weightAt(16, 16, 0), closeTo(1, 1e-6));
      expectNormalized(back);
    });

    test('a painted map round trips within a byte', () {
      // The payload is the control texture: four bytes a texel. That costs a
      // rounding, and the test says how much.
      final map = makeMap();
      for (var i = 0; i < 25; i++) {
        paintTerrainSplat(
          map,
          layer: 1,
          brush: const TerrainBrush(radius: 9, strength: 2, falloff: 0.3),
          x: 2,
          z: -3,
          deltaSeconds: 1 / 60,
        );
      }
      final back = TerrainSplatMap.fromBytes(
        map.toBytes(),
        columns: map.columns,
        rows: map.rows,
        width: map.width,
        depth: map.depth,
      )!;
      for (var r = 0; r < map.rows; r++) {
        for (var c = 0; c < map.columns; c++) {
          for (var layer = 0; layer < terrainSplatLayers; layer++) {
            expect(
              back.weightAt(c, r, layer),
              closeTo(map.weightAt(c, r, layer), 1.5 / 255),
              reason: 'texel ($c, $r) layer $layer',
            );
          }
        }
      }
      expectNormalized(back);
    });

    test('every texel of the payload sums to 255', () {
      // Rounding each channel on its own leaves texels at 254 or 256, which
      // reads as a faint mottling across ground painted flat.
      final map = makeMap();
      for (var i = 0; i < 15; i++) {
        paintTerrainSplat(
          map,
          layer: 2,
          brush: const TerrainBrush(radius: 7, strength: 1.7, falloff: 0.45),
          x: 0,
          z: 0,
          deltaSeconds: 1 / 60,
        );
      }
      final bytes = map.toBytes();
      for (var texel = 0; texel < map.columns * map.rows; texel++) {
        var total = 0;
        for (var layer = 0; layer < terrainSplatLayers; layer++) {
          total += bytes[texel * terrainSplatLayers + layer];
        }
        expect(total, 255, reason: 'texel $texel');
      }
    });

    test('the payload is four bytes a texel', () {
      final map = makeMap(columns: 64, rows: 32);
      expect(map.toBytes().lengthInBytes, 64 * 32 * 4);
    });

    test('a truncated payload is refused rather than half-read', () {
      final map = makeMap();
      final short = Uint8List.sublistView(map.toBytes(), 0, 16);
      expect(
        TerrainSplatMap.fromBytes(
          short,
          columns: map.columns,
          rows: map.rows,
          width: map.width,
          depth: map.depth,
        ),
        isNull,
      );
    });

    test('bytes that do not sum to 255 load as a usable surface', () {
      // Hand-edited, or written by a tool that rounded differently. Loading
      // them as-is would darken or blow out the ground.
      final zeroed = Uint8List(8 * 8 * 4);
      final map = TerrainSplatMap.fromBytes(
        zeroed,
        columns: 8,
        rows: 8,
        width: 16,
        depth: 16,
      )!;
      expect(map.weightAt(4, 4, 0), 1);
      expectNormalized(map);
    });
  });

  test('normalizing a texel with nothing in it falls back to the base', () {
    final map = makeMap();
    final base = (16 * map.columns + 16) * terrainSplatLayers;
    for (var layer = 0; layer < terrainSplatLayers; layer++) {
      map.weights[base + layer] = 0;
    }
    map.normalizeTexel(16 * map.columns + 16);
    expect(map.weightAt(16, 16, 0), 1);
  });
}
