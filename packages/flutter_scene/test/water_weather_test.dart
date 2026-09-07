// Water that answers to the weather, and a sea state that can be raised and
// put back. GPU-free: the wave spectrum is arithmetic and the component's
// height query reads the same list the mesh is displaced from.

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('choppiness', () {
    test('one is the spectrum as authored', () {
      final water = WaterComponent();
      final authored = water.waves.map((w) => w.amplitude).toList();
      water.choppiness = 1.0;
      expect(water.waves.map((w) => w.amplitude), authored);
    });

    test('raising it raises every crest', () {
      final water = WaterComponent();
      final before = water.waves.map((w) => w.amplitude).toList();
      water.choppiness = 2.0;
      for (var i = 0; i < before.length; i++) {
        expect(water.waves[i].amplitude, closeTo(before[i] * 2, 1e-9));
      }
    });

    test('it leaves direction and wavelength alone', () {
      // The shape of the sea should stay the shape it was authored as; only
      // how hard it is running changes.
      final water = WaterComponent();
      final directions = water.waves.map((w) => w.direction.clone()).toList();
      final lengths = water.waves.map((w) => w.wavelength).toList();
      water.choppiness = 2.4;
      for (var i = 0; i < lengths.length; i++) {
        expect(water.waves[i].direction, directions[i]);
        expect(water.waves[i].wavelength, lengths[i]);
      }
    });

    test('calming it and raising it again returns the authored waves', () {
      // Scaling the live list repeatedly would compound; the base spectrum is
      // kept so it does not.
      final water = WaterComponent();
      final authored = water.waves.map((w) => w.amplitude).toList();
      water
        ..choppiness = 0.0
        ..choppiness = 2.0
        ..choppiness = 1.0;
      for (var i = 0; i < authored.length; i++) {
        expect(water.waves[i].amplitude, closeTo(authored[i], 1e-9));
      }
    });

    test('glassy water is flat', () {
      final water = WaterComponent()..choppiness = 0;
      expect(water.waves.every((w) => w.amplitude == 0), isTrue);
      expect(water.surfaceHeightAt(3, 7), 0);
    });

    test('steepness never exceeds a trochoid', () {
      // Past 1 the crests fold through themselves.
      final water = WaterComponent()..choppiness = 8;
      expect(water.waves.every((w) => w.steepness <= 1.0), isTrue);
    });

    test('a negative sea state is treated as glassy, not as inverted', () {
      final water = WaterComponent()..choppiness = -3;
      expect(water.choppiness, 0);
    });

    test('the height query moves with it', () {
      // surfaceHeightAt reads the same list the mesh is displaced from, which
      // is what keeps anything floating on the water on the water.
      final calm = WaterComponent()..choppiness = 0.2;
      final rough = WaterComponent()..choppiness = 3.0;
      expect(
        rough.surfaceHeightAt(5, 5).abs(),
        greaterThan(calm.surfaceHeightAt(5, 5).abs()),
      );
    });
  });

  group('weather', () {
    test('every state says what the sea is doing', () {
      for (final preset in weatherPresets) {
        expect(preset.choppiness, greaterThanOrEqualTo(0), reason: preset.id);
      }
    });

    test('a storm runs a harder sea than a clear day', () {
      expect(
        weatherPresetById('storm')!.choppiness,
        greaterThan(weatherPresetById('clear')!.choppiness),
      );
    });

    test('setting the weather raises every water surface under the root', () {
      final root = Node(name: 'root');
      final lake = Node(name: 'Lake')..addComponent(WaterComponent());
      final pond = Node(name: 'Pond')..addComponent(WaterComponent());
      root.add(lake);
      lake.add(pond);

      final moved = setWaterChoppiness(root, 2.2);
      expect(moved, 2, reason: 'a nested surface was missed');
      expect(lake.getComponent<WaterComponent>()!.choppiness, 2.2);
      expect(pond.getComponent<WaterComponent>()!.choppiness, 2.2);
    });

    test('a scene with no water reports none rather than failing', () {
      expect(setWaterChoppiness(Node(name: 'root'), 1.5), 0);
    });
  });
}
