// Weather as one named thing. The presets are plain data and the sky they
// drive is a plain object, so none of this needs a GPU.

import 'package:flutter_scene/visual_script.dart';
import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  group('presets', () {
    test('every state is offered once, driest first', () {
      expect(weatherPresets, isNotEmpty);
      expect(
        weatherPresets.map((p) => p.id).toSet(),
        hasLength(weatherPresets.length),
      );
      expect(weatherPresets.first.id, 'clear');
      for (final preset in weatherPresets) {
        expect(preset.name, isNotEmpty);
        expect(preset.description, isNotEmpty);
        expect(preset.coverage, inInclusiveRange(0, 1));
        expect(preset.density, inInclusiveRange(0, 1));
        expect(preset.stormDarkening, inInclusiveRange(0, 1));
      }
    });

    test('clear weather is clearer than overcast', () {
      expect(
        weatherPresetById('clear')!.coverage,
        lessThan(weatherPresetById('overcast')!.coverage),
      );
    });

    test('only a storm carries lightning', () {
      final stormy = weatherPresets.where((p) => p.lightning).map((p) => p.id);
      expect(stormy, ['storm']);
    });

    test('every named effect is a preset the engine actually ships', () {
      for (final preset in weatherPresets) {
        final effect = preset.effect;
        if (effect == null) continue;
        expect(
          vfxPresetById(effect),
          isNotNull,
          reason: '${preset.id} names an effect that does not exist',
        );
      }
    });

    test('an unknown id is null rather than a fallback', () {
      expect(weatherPresetById('nonsense'), isNull);
    });
  });

  group('applying', () {
    test('a preset writes its whole state onto the sky', () {
      final sky = WeatherSkySource();
      weatherPresetById('storm')!.applyTo(sky);
      expect(sky.coverage, 1.0);
      expect(sky.stormDarkening, 0.8);
      expect(sky.turbidity, 18);
    });

    test('the sun is left where it was', () {
      // What time it is and what the weather is doing are two questions.
      final sky = WeatherSkySource(sunDirection: Vector3(0, 1, 0));
      weatherPresetById('rain')!.applyTo(sky);
      expect(sky.sunDirection, Vector3(0, 1, 0));
    });
  });

  group('the flow nodes', () {
    test('Set Weather and Set Time of Day are in the palette', () {
      final registry = sceneVisualScriptRegistry();
      expect(registry['scene.setWeather'], isNotNull);
      expect(registry['scene.setTimeOfDay'], isNotNull);
    });

    test('a node outside a scene reports failure rather than throwing', () {
      // The host reaches the sky through the scene the node is mounted in,
      // and a graph can perfectly well be ticked on a detached node.
      final log = <String>[];
      final host = SceneVisualScriptHost(Node(name: 'actor'), onLog: log.add);
      expect(host.invoke('setWeather', {'weather': 'rain'}), isFalse);
      expect(host.invoke('setTimeOfDay', {'hour': 9.0}), isFalse);
      expect(log, hasLength(2));
    });

    test('an unknown weather name is reported, not guessed at', () {
      final log = <String>[];
      final host = SceneVisualScriptHost(Node(name: 'actor'), onLog: log.add);
      expect(host.invoke('setWeather', {'weather': 'brimstone'}), isFalse);
      expect(log.single, contains('brimstone'));
    });
  });
}
