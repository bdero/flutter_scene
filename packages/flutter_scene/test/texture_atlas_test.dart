/// Covers the UV bookkeeping of [TextureAtlas]: grid dimensions, per-tile UV
/// bounds with and without a padding gutter, row-major indexing, and the
/// within-tile UV mapping.
library;

import 'package:flutter_scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

// Vector4/Vector2 are float32-backed, so compare with a float tolerance.
const double _eps = 1e-6;

void expectVec4(Vector4 actual, double x, double y, double z, double w) {
  expect(actual.x, closeTo(x, _eps));
  expect(actual.y, closeTo(y, _eps));
  expect(actual.z, closeTo(z, _eps));
  expect(actual.w, closeTo(w, _eps));
}

void main() {
  group('TextureAtlas grid', () {
    test('reports tile count and pixel dimensions (no padding)', () {
      final atlas = TextureAtlas(columns: 4, rows: 2, tileSize: 16);
      expect(atlas.tileCount, 8);
      expect(atlas.width, 64);
      expect(atlas.height, 32);
    });

    test('padding widens the cells', () {
      final atlas = TextureAtlas(columns: 4, rows: 2, tileSize: 16, padding: 2);
      // cell = 16 + 2*2 = 20.
      expect(atlas.width, 80);
      expect(atlas.height, 40);
    });
  });

  group('tileBounds', () {
    test('maps tiles row-major with a top-left origin (no padding)', () {
      final atlas = TextureAtlas(columns: 4, rows: 2, tileSize: 16);
      // width=64, height=32. Each tile is 0.25 wide, 0.5 tall.
      // Tile 0 = top-left.
      expectVec4(atlas.tileBounds(0), 0.0, 0.0, 0.25, 0.5);
      // Tile 3 = top-right.
      expectVec4(atlas.tileBounds(3), 0.75, 0.0, 1.0, 0.5);
      // Tile 4 = start of the second row.
      expectVec4(atlas.tileBounds(4), 0.0, 0.5, 0.25, 1.0);
      // Tile 7 = bottom-right.
      expectVec4(atlas.tileBounds(7), 0.75, 0.5, 1.0, 1.0);
    });

    test('insets past the padding gutter', () {
      final atlas = TextureAtlas(columns: 2, rows: 1, tileSize: 16, padding: 2);
      // cell=20, width=40, height=20.
      // Tile 0 content starts at (padding, padding) = (2, 2), spans 16.
      expectVec4(atlas.tileBounds(0), 2 / 40, 2 / 20, 18 / 40, 18 / 20);
      // Tile 1 content starts at (20 + 2, 2) = (22, 2).
      expectVec4(atlas.tileBounds(1), 22 / 40, 2 / 20, 38 / 40, 18 / 20);
    });
  });

  group('generateSolidColorAtlasPixels', () {
    // RGBA byte offset of pixel (x, y) in a row-major image of the given width.
    int at(int x, int y, int width) => (y * width + x) * 4;

    test('fills each cell (content and padding) with the tile color', () {
      final red = Vector4(1, 0, 0, 1);
      final green = Vector4(0, 1, 0, 1);
      final pixels = generateSolidColorAtlasPixels(
        tileColors: [red, green],
        columns: 2,
        tileSize: 2,
        padding: 1,
      );
      // cell = 4, width = 8, height = 4.
      const width = 8;
      expect(pixels.length, 8 * 4 * 4);
      // Tile 0 (red) content center at (1, 1).
      expect(pixels.sublist(at(1, 1, width), at(1, 1, width) + 4), [
        255,
        0,
        0,
        255,
      ]);
      // Tile 0 padding corner at (0, 0) is still red (no bleed).
      expect(pixels.sublist(at(0, 0, width), at(0, 0, width) + 4), [
        255,
        0,
        0,
        255,
      ]);
      // Tile 1 (green) starts at cell x = 4; content at (5, 1).
      expect(pixels.sublist(at(5, 1, width), at(5, 1, width) + 4), [
        0,
        255,
        0,
        255,
      ]);
    });

    test('leaves cells past the color list transparent', () {
      // 2 columns, 3 colors -> 2 rows, tile 3 (index 3) is empty.
      final pixels = generateSolidColorAtlasPixels(
        tileColors: [
          Vector4(1, 1, 1, 1),
          Vector4(1, 1, 1, 1),
          Vector4(1, 1, 1, 1),
        ],
        columns: 2,
        tileSize: 1,
      );
      // width = 2, height = 2. Tile 3 is bottom-right at (1, 1).
      const width = 2;
      expect(pixels.sublist(at(1, 1, width), at(1, 1, width) + 4), [
        0,
        0,
        0,
        0,
      ]);
    });

    test('lays out matching a TextureAtlas of the same params', () {
      final atlas = TextureAtlas(columns: 4, rows: 2, tileSize: 16, padding: 2);
      final pixels = generateSolidColorAtlasPixels(
        tileColors: List.filled(8, Vector4(1, 1, 1, 1)),
        columns: 4,
        tileSize: 16,
        padding: 2,
      );
      expect(pixels.length, atlas.width * atlas.height * 4);
    });
  });

  group('tileUv', () {
    test('maps within-tile corners to the tile bounds', () {
      final atlas = TextureAtlas(columns: 4, rows: 2, tileSize: 16);
      final bounds = atlas.tileBounds(5);
      final topLeft = atlas.tileUv(5, 0, 0);
      final bottomRight = atlas.tileUv(5, 1, 1);
      final center = atlas.tileUv(5, 0.5, 0.5);
      expect(topLeft.x, closeTo(bounds.x, _eps));
      expect(topLeft.y, closeTo(bounds.y, _eps));
      expect(bottomRight.x, closeTo(bounds.z, _eps));
      expect(bottomRight.y, closeTo(bounds.w, _eps));
      expect(center.x, closeTo((bounds.x + bounds.z) / 2, _eps));
      expect(center.y, closeTo((bounds.y + bounds.w) / 2, _eps));
    });
  });
}
