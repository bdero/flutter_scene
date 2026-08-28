// WaterComponent: the parts that do not need a GPU. Mounting builds geometry,
// which does, so these cover the wave field, the traversal-to-nav mapping,
// the carve volume blocked water needs, and the style presets.

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/navigation.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('surface height', () {
    test('agrees with the wave field it was built from', () {
      final waves = [
        GerstnerWave(
          direction: vm.Vector2(1, 0),
          amplitude: 0.5,
          wavelength: 10,
          speed: 1,
        ),
      ];
      final water = WaterComponent(waves: waves);
      final field = WaterSurfaceComponent(waves: waves);
      for (final x in const [-3.0, 0.0, 2.5, 7.0]) {
        expect(
          water.surfaceHeightAt(x, 0),
          closeTo(field.evaluateAt(vm.Vector2(x, 0), 0).displacement.y, 1e-9),
          reason: 'at x = $x',
        );
      }
    });

    test('moves with time', () {
      final water = WaterComponent();
      final at0 = water.surfaceHeightAt(1, 1);
      water.time = 1.7;
      expect(water.surfaceHeightAt(1, 1), isNot(closeTo(at0, 1e-6)));
      expect(water.time, 1.7);
    });

    test('a flat spectrum is a flat surface', () {
      final water = WaterComponent(waves: []);
      expect(water.surfaceHeightAt(3, -4), 0);
    });
  });

  group('footprint', () {
    test('covers the square centred on the node', () {
      final water = WaterComponent(size: 10);
      expect(water.covers(0, 0), isTrue);
      expect(water.covers(5, 5), isTrue, reason: 'the corner counts');
      expect(water.covers(5.01, 0), isFalse);
      expect(water.covers(0, -5.01), isFalse);
    });
  });

  group('traversal', () {
    test('maps onto the nav areas a bake understands', () {
      expect(
        WaterComponent(traversal: WaterTraversal.walkable).navArea,
        NavArea.walkable,
      );
      expect(
        WaterComponent(traversal: WaterTraversal.swimmable).navArea,
        NavArea.slow,
        reason: 'crossable, but a path prefers to go around',
      );
      expect(
        WaterComponent(traversal: WaterTraversal.blocked).navArea,
        NavArea.nonWalkable,
      );
    });

    test('only blocked water asks for a carve volume', () {
      expect(WaterComponent(traversal: WaterTraversal.walkable).navVolume(), isNull);
      expect(
        WaterComponent(traversal: WaterTraversal.swimmable).navVolume(),
        isNull,
      );
      expect(
        WaterComponent(traversal: WaterTraversal.blocked).navVolume(),
        isNotNull,
      );
    });

    test('the carve volume spans the footprint and reaches the bed', () {
      final water = WaterComponent(
        size: 20,
        traversal: WaterTraversal.blocked,
      );
      final volume = water.navVolume(depth: 8)!;
      expect(volume.min.x, -10);
      expect(volume.max.x, 10);
      expect(volume.min.z, -10);
      expect(volume.max.z, 10);
      expect(volume.min.y, -8, reason: 'down to the bed, not just the surface');
      expect(volume.max.y, greaterThan(0), reason: 'up to the tallest crest');
      expect(volume.area, NavArea.nonWalkable);
    });

    test('the carve volume follows the node it is placed on', () {
      final water = WaterComponent(
        size: 4,
        traversal: WaterTraversal.blocked,
      );
      final volume = water.navVolume(
        worldTransform: vm.Matrix4.translation(vm.Vector3(100, 5, -20)),
        depth: 2,
      )!;
      expect(volume.min.x, 98);
      expect(volume.max.x, 102);
      expect(volume.min.y, 3);
      expect(volume.min.z, -22);
    });

    test('navAreaOf reads a node, and leaves other nodes to the slope', () {
      final wet = Node()..addComponent(
        WaterComponent(traversal: WaterTraversal.walkable),
      );
      expect(WaterComponent.navAreaOf(wet), NavArea.walkable);
      expect(WaterComponent.navAreaOf(Node()), NavArea.nonWalkable);
    });

    test('collectNavVolumes finds every blocked surface in a subtree', () {
      final root = Node();
      final pool = Node(name: 'pool')
        ..addComponent(
          WaterComponent(size: 4, traversal: WaterTraversal.blocked),
        );
      final pond = Node(name: 'pond')
        ..addComponent(
          WaterComponent(size: 6, traversal: WaterTraversal.swimmable),
        );
      root
        ..add(pool)
        ..add(pond);

      final volumes = WaterComponent.collectNavVolumes(root);
      expect(volumes, hasLength(1), reason: 'only the blocked one carves');
      expect(volumes.single.max.x, 2);
    });
  });

  group('style presets', () {
    test('low-poly water is fewer, sharper waves than the lit styles', () {
      final faceted = WaterComponent.defaultWavesFor(WaterStyle.lowPoly);
      final lit = WaterComponent.defaultWavesFor(WaterStyle.realistic);
      expect(faceted.length, lessThan(lit.length));
      expect(
        faceted.every((w) => w.steepness >= 1.0),
        isTrue,
        reason: 'the facets have to read as a style, not as a coarse mesh',
      );
      expect(faceted.first.amplitude, greaterThan(lit.first.amplitude));
    });

    test('shimmer and realistic share a spectrum; only the material differs', () {
      final shimmer = WaterComponent.defaultWavesFor(WaterStyle.shimmer);
      final realistic = WaterComponent.defaultWavesFor(WaterStyle.realistic);
      expect(
        [for (final w in shimmer) w.wavelength],
        [for (final w in realistic) w.wavelength],
      );
    });

    test('every style has a usable default spectrum', () {
      for (final style in WaterStyle.values) {
        final waves = WaterComponent.defaultWavesFor(style);
        expect(waves, isNotEmpty, reason: style.name);
        for (final wave in waves) {
          expect(wave.amplitude, greaterThan(0), reason: style.name);
          expect(wave.wavelength, greaterThan(0), reason: style.name);
          expect(
            wave.direction.length,
            closeTo(1, 1e-6),
            reason: '${style.name} directions are normalized',
          );
        }
      }
    });
  });

  test('a clone carries the settings, not the built surface', () {
    final water = WaterComponent(
      size: 12,
      resolution: 20,
      style: WaterStyle.lowPoly,
      traversal: WaterTraversal.blocked,
      animate: false,
    );
    final clone = water.cloneFor(Node())! as WaterComponent;
    expect(clone.size, 12);
    expect(clone.resolution, 20);
    expect(clone.style, WaterStyle.lowPoly);
    expect(clone.traversal, WaterTraversal.blocked);
    expect(clone.animate, isFalse);
    // The colours are copied, not shared, so tuning one pond does not tint
    // every clone of it.
    clone.shallowColor.setValues(1, 0, 0, 1);
    expect(water.shallowColor.x, isNot(1));
  });

  test('a resolution below two is lifted to a single quad', () {
    expect(WaterComponent(resolution: 0).resolution, 2);
    expect(WaterComponent(resolution: -5).resolution, 2);
  });
}
