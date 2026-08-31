import 'package:flutter_scene/scene.dart' show IrradianceProbeGrid;
import 'package:flutter_scene/src/render/irradiance_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('IrradianceProbeGrid', () {
    test('walks the lattice from its minimum corner', () {
      final probe = IrradianceProbeGrid(
        origin: Vector3(-4, 0, -4),
        spacing: Vector3(2, 1, 2),
        counts: Vector3(5, 3, 5),
      );
      expect(probe.probeCount, 75);
      expect(probe.probePosition(0, 0, 0), Vector3(-4, 0, -4));
      expect(probe.probePosition(1, 2, 3), Vector3(-2, 2, 2));
      // The far corner lands one spacing short of origin + counts * spacing.
      expect(probe.probePosition(4, 2, 4), Vector3(4, 2, 4));
    });

    test('agrees with the placement the renderer resolves', () {
      final layout = IrradianceFieldLayout(Vector3(16, 8, 16));
      final placement = planIrradianceGrid(
        center: Vector3(3, 1, -2),
        extents: Vector3(20, 10, 20),
        layout: layout,
      );
      // The accessor is a plain view over placement + layout, so a probe read
      // through it must match the placement's own lattice math.
      final grid = IrradianceProbeGrid(
        origin: placement.origin,
        spacing: placement.spacing,
        counts: layout.resolution,
      );
      expect(grid.origin, placement.origin);
      // The accessor steps out from the origin while the placement multiplies
      // a lattice index, so the two agree only to float32 rounding.
      final mine = grid.probePosition(2, 1, 3);
      final theirs = placement.probePosition(
        placement.anchor + Vector3(2, 1, 3),
      );
      expect(mine.x, closeTo(theirs.x, 1e-5));
      expect(mine.y, closeTo(theirs.y, 1e-5));
      expect(mine.z, closeTo(theirs.z, 1e-5));
    });
  });

  group('IrradianceFieldLayout', () {
    test('the default grid packs into the documented atlas', () {
      final layout = IrradianceFieldLayout(Vector3(16, 8, 16));
      expect(layout.probeCount, 2048);
      expect(layout.tilesPerRow, 64);
      expect(layout.tileRows, 32);
      // 64 tiles of 16 across, and 2 spherical-harmonic rows plus the state
      // strip plus both probe regions down.
      expect(layout.atlasWidth, 1024);
      expect(layout.atlasHeight, 2 + 32 + 32 * 8 + 32 * 16);
      expect(layout.irradianceOriginY, 34);
      expect(layout.depthOriginY, 34 + 256);
    });

    test('tilesPerRow stays a power of two', () {
      for (final res in <Vector3>[
        Vector3(4, 4, 4),
        Vector3(6, 3, 5),
        Vector3(16, 8, 16),
        Vector3(24, 12, 24),
      ]) {
        final layout = IrradianceFieldLayout(res);
        expect(
          layout.tilesPerRow & (layout.tilesPerRow - 1),
          0,
          reason: 'tilesPerRow ${layout.tilesPerRow} for $res',
        );
      }
    });

    test('every probe has a tile inside the atlas', () {
      final layout = IrradianceFieldLayout(Vector3(6, 3, 5));
      final seen = <int>{};
      final counts = layout.resolution;
      for (var z = 0; z < counts.z; z++) {
        for (var y = 0; y < counts.y; y++) {
          for (var x = 0; x < counts.x; x++) {
            final index = layout.probeIndex(x, y, z);
            expect(seen.add(index), isTrue, reason: 'duplicate index $index');
            expect(index, lessThan(layout.probeCount));
            expect(layout.tileColumn(index), lessThan(layout.tilesPerRow));
            expect(layout.tileRow(index), lessThan(layout.tileRows));
          }
        }
      }
      expect(seen.length, layout.probeCount);
    });

    test('an oversized grid is clamped until the atlas fits', () {
      final layout = IrradianceFieldLayout(Vector3(256, 256, 256));
      expect(
        layout.atlasWidth,
        lessThanOrEqualTo(kMaxIrradianceAtlasDimension),
      );
      expect(
        layout.atlasHeight,
        lessThanOrEqualTo(kMaxIrradianceAtlasDimension),
      );
    });

    test('regions do not overlap', () {
      final layout = IrradianceFieldLayout(Vector3(16, 8, 16));
      expect(
        layout.irradianceOriginY,
        greaterThanOrEqualTo(
          IrradianceFieldLayout.stateOriginY + layout.tileRows,
        ),
      );
      expect(
        layout.depthOriginY,
        greaterThanOrEqualTo(
          layout.irradianceOriginY +
              layout.tileRows * IrradianceFieldLayout.irradianceTile,
        ),
      );
      expect(
        layout.atlasHeight,
        greaterThanOrEqualTo(
          layout.depthOriginY +
              layout.tileRows * IrradianceFieldLayout.depthTile,
        ),
      );
    });
  });

  group('grid placement', () {
    test('probes span the requested extents', () {
      final layout = IrradianceFieldLayout(Vector3(5, 5, 5));
      final placement = planIrradianceGrid(
        center: Vector3(0, 0, 0),
        extents: Vector3(8, 8, 8),
        layout: layout,
      );
      expect(placement.spacing.x, closeTo(2.0, 1e-9));
      final maxCorner = placement.probePosition(
        placement.anchor + Vector3(4, 4, 4),
      );
      expect(maxCorner.x - placement.origin.x, closeTo(8.0, 1e-9));
    });

    test('the anchor snaps to whole cells', () {
      final layout = IrradianceFieldLayout(Vector3(5, 5, 5));
      final a = planIrradianceGrid(
        center: Vector3(0.1, 0, 0),
        extents: Vector3(8, 8, 8),
        layout: layout,
      );
      final b = planIrradianceGrid(
        center: Vector3(0.4, 0, 0),
        extents: Vector3(8, 8, 8),
        layout: layout,
      );
      // Both round to the same lattice cell, so the field is bit-stable
      // across sub-cell camera motion.
      expect(a.anchor, b.anchor);
      final c = planIrradianceGrid(
        center: Vector3(2.0, 0, 0),
        extents: Vector3(8, 8, 8),
        layout: layout,
      );
      expect(c.anchor.x, a.anchor.x + 1);
    });

    test('maxProbeDistance is 1.5 cell diagonals', () {
      final placement = IrradianceGridPlacement(
        anchor: Vector3.zero(),
        spacing: Vector3(2, 2, 2),
      );
      expect(
        placement.maxProbeDistance,
        closeTo(Vector3(2, 2, 2).length * 1.5, 1e-9),
      );
      expect(placement.minCellEdge, 2.0);
    });
  });

  group('scrolling', () {
    test('wrapProbeSlot handles negative lattice indices', () {
      expect(wrapProbeSlot(0, 8), 0);
      expect(wrapProbeSlot(9, 8), 1);
      expect(wrapProbeSlot(-1, 8), 7);
      expect(wrapProbeSlot(-9, 8), 7);
    });

    test('a one-cell scroll invalidates exactly one slab', () {
      const count = 8;
      const previous = 0;
      const anchor = 1;
      final stale = <int>[
        for (var slot = 0; slot < count; slot++)
          if (probeScrolledIn(
            slot: slot,
            count: count,
            anchor: anchor,
            previousAnchor: previous,
          ))
            slot,
      ];
      // Lattice index 8 entered and it stores in slot 0.
      expect(stale, <int>[0]);
    });

    test('a negative scroll invalidates the opposite slab', () {
      const count = 8;
      final stale = <int>[
        for (var slot = 0; slot < count; slot++)
          if (probeScrolledIn(
            slot: slot,
            count: count,
            anchor: -2,
            previousAnchor: 0,
          ))
            slot,
      ];
      // Lattice indices -2 and -1 entered, storing in slots 6 and 7.
      expect(stale..sort(), <int>[6, 7]);
    });

    test('no motion invalidates nothing', () {
      for (var slot = 0; slot < 8; slot++) {
        expect(
          probeScrolledIn(slot: slot, count: 8, anchor: 3, previousAnchor: 3),
          isFalse,
        );
      }
    });

    test('a teleport invalidates every probe and never escalates', () {
      const count = 8;
      var stale = 0;
      for (var slot = 0; slot < count; slot++) {
        if (probeScrolledIn(
          slot: slot,
          count: count,
          anchor: 1000,
          previousAnchor: 0,
        )) {
          stale++;
        }
      }
      expect(stale, count);
    });

    test('a scroll keeps interior probes bit-stable', () {
      const count = 8;
      // Slots holding lattice indices 1..7 under both anchors keep their data.
      for (var slot = 0; slot < count; slot++) {
        final scrolled = probeScrolledIn(
          slot: slot,
          count: count,
          anchor: 1,
          previousAnchor: 0,
        );
        final lattice = 1 + wrapProbeSlot(slot - 1, count);
        expect(scrolled, lattice >= 8);
      }
    });
  });
}
