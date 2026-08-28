// The shipped VFX presets.
//
// A preset is a simulation plus a look. The simulation half touches no GPU
// resource, which is what these cover: that every preset emits something,
// that two copies are independent, and that the settings each effect's
// identity depends on are actually set. The look half builds billboards and
// needs the shader bundle, so it is exercised by the styling checks against a
// stub rather than against a built emitter.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

bool _gpuAvailable() {
  try {
    Scene();
    return true;
  } catch (_) {
    return false;
  }
}

void main() {
  group('catalogue', () {
    test('every preset has a unique id and a real description', () {
      final ids = <String>{};
      for (final preset in vfxPresets) {
        expect(ids.add(preset.id), isTrue, reason: 'duplicate ${preset.id}');
        expect(preset.name, isNotEmpty);
        expect(
          preset.description.length,
          greaterThan(20),
          reason: '${preset.id} needs a description worth reading',
        );
      }
    });

    test('lookup by id finds every preset and nothing else', () {
      for (final preset in vfxPresets) {
        expect(vfxPresetById(preset.id), same(preset));
      }
      expect(vfxPresetById('no-such-effect'), isNull);
    });

    test('every category has at least one preset, and the sets partition', () {
      var total = 0;
      for (final category in VfxCategory.values) {
        final presets = vfxPresetsIn(category);
        expect(presets, isNotEmpty, reason: category.name);
        expect(presets.every((p) => p.category == category), isTrue);
        total += presets.length;
      }
      expect(total, vfxPresets.length);
    });
  });

  group('every preset builds a system that emits', () {
    for (final preset in vfxPresets) {
      test(preset.id, () {
        final system = preset.buildSystem();

        expect(system.storage.capacity, greaterThan(0));
        expect(
          system.spawner.rate > 0 || system.spawner.bursts.isNotEmpty,
          isTrue,
          reason: 'a preset that never spawns is not an effect',
        );
        expect(system.lifetime.sample(0, 0), greaterThan(0));

        // Advance a second and track the peak, rather than the count at the
        // end: a muzzle flash is over in a tenth of a second, and checking
        // only the final frame would call it empty. A preset whose numbers
        // cancel out looks fine in the catalogue and does nothing in the
        // scene, which is what this catches.
        var peak = system.storage.aliveCount;
        for (var i = 0; i < 60; i++) {
          system.step(1 / 60);
          if (system.storage.aliveCount > peak) {
            peak = system.storage.aliveCount;
          }
          expect(
            system.storage.aliveCount,
            lessThanOrEqualTo(system.storage.capacity),
          );
        }
        expect(
          peak,
          greaterThan(0),
          reason: '${preset.id} emitted nothing in a second',
        );
      });
    }
  });

  group('two copies of a preset are independent', () {
    test('each build gets its own simulation', () {
      final a = vfxPresetById('smoke')!.buildSystem();
      final b = vfxPresetById('smoke')!.buildSystem();
      expect(identical(a, b), isFalse);
      for (var i = 0; i < 30; i++) {
        a.step(1 / 60);
      }
      expect(a.storage.aliveCount, greaterThan(0));
      expect(b.storage.aliveCount, 0, reason: 'b was never advanced');
    });
  });

  group('the settings that make each effect what it is', () {
    test('the one-shot effects burst and do not loop', () {
      for (final id in const ['muzzleFlash', 'impactSparks', 'dustPuff', 'explosion']) {
        final system = vfxPresetById(id)!.buildSystem();
        expect(system.looping, isFalse, reason: id);
        expect(system.spawner.rate, 0, reason: '$id is a burst, not a stream');
        expect(system.spawner.bursts, isNotEmpty, reason: id);
      }
    });

    test('a restart replays a one-shot effect', () {
      final system = vfxPresetById('muzzleFlash')!.buildSystem();
      for (var i = 0; i < 120; i++) {
        system.step(1 / 60);
      }
      expect(
        system.storage.aliveCount,
        0,
        reason: 'the flash is over in a tenth of a second',
      );

      system.reset();
      system.step(1 / 60);
      expect(
        system.storage.aliveCount,
        greaterThan(0),
        reason: 'restarting is how the flash is fired again',
      );
    });

    test('the weather presets prewarm so a scene opens already going', () {
      for (final id in const ['groundFog', 'rain', 'snow']) {
        expect(
          vfxPresetById(id)!.buildSystem().prewarm,
          greaterThan(0),
          reason: id,
        );
      }
      expect(
        vfxPresetById('groundFog')!.buildSystem().storage.aliveCount,
        greaterThan(0),
        reason: 'prewarmed at construction, before any step',
      );
    });

    test('rain falls and smoke rises', () {
      expect(vfxPresetById('rain')!.buildSystem().gravity.y, lessThan(0));
      expect(vfxPresetById('smoke')!.buildSystem().gravity.y, greaterThan(0));
    });

  });

  group('the look half', () {
    // Building an emitter allocates billboard geometry and a sprite
    // material, both of which need the base shader bundle.
    setUpAll(() async {
      if (_gpuAvailable()) await Scene.initializeStaticResources();
    });

    ParticleEmitterComponent built(String id) =>
        vfxPresetById(id)!.build();

    test('sparks and rain stretch along their velocity', () {
      for (final id in const ['impactSparks', 'rain']) {
        final emitter = built(id);
        expect(emitter.facing, BillboardFacing.velocityStretched, reason: id);
        expect(emitter.velocityStretch, greaterThan(0), reason: id);
      }
    }, skip: _gpuAvailable() ? null : 'Requires a GPU device.');

    test('the emissive effects are additive and the media are not', () {
      for (final id in const ['fire', 'embers', 'muzzleFlash', 'sparkle']) {
        expect(
          built(id).material.blendMode,
          SpriteBlendMode.additive,
          reason: id,
        );
      }
      for (final id in const ['smoke', 'groundFog', 'snow', 'dustPuff']) {
        expect(
          built(id).material.blendMode,
          SpriteBlendMode.alpha,
          reason: id,
        );
      }
    }, skip: _gpuAvailable() ? null : 'Requires a GPU device.');

    test('the media that intersect the world fade softly against it', () {
      // Without this they cut a hard line through terrain, which is the tell
      // that gives billboard fog away.
      for (final id in const ['smoke', 'groundFog', 'dustPuff', 'steam']) {
        expect(built(id).material.softDepthFade, greaterThan(0), reason: id);
      }
    }, skip: _gpuAvailable() ? null : 'Requires a GPU device.');
  });
}
