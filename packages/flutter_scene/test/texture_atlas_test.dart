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
