// The storm driver: how strikes are scheduled, what the flash envelope looks
// like, and why thunder arrives when it does. No GPU: the component drives a
// sky and a light, and both are checked through a stand-in where the real one
// needs a device.

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('scheduling', () {
    test('strikes fall inside the configured interval', () {
      final fired = <double>[];
      var clock = 0.0;
      final storm = LightningComponent(
        minInterval: 2,
        maxInterval: 5,
        onStrike: (_) => fired.add(clock),
      );
      for (var i = 0; i < 60 * 60; i++) {
        clock += 1 / 60;
        storm.update(1 / 60);
      }
      expect(fired.length, greaterThan(10));
      for (var i = 1; i < fired.length; i++) {
        final gap = fired[i] - fired[i - 1];
        // A frame of slack: a strike lands on the first tick past its due
        // time, not exactly on it.
        expect(gap, greaterThanOrEqualTo(2 - 1 / 60));
        expect(gap, lessThanOrEqualTo(5 + 1 / 60));
      }
    });

    test('the same seed replays the same storm', () {
      List<double> run() {
        final distances = <double>[];
        final storm = LightningComponent(
          onStrike: (s) => distances.add(s.distance),
        );
        for (var i = 0; i < 60 * 120; i++) {
          storm.update(1 / 60);
        }
        return distances;
      }

      expect(run(), run());
    });

    test('a scripted strike fires now and reschedules from here', () {
      final storm = LightningComponent(minInterval: 10, maxInterval: 10);
      final before = storm.untilNextStrike;
      final struck = storm.strike(distance: 500);
      expect(struck.distance, 500);
      expect(storm.currentStrike, same(struck));
      expect(storm.untilNextStrike, 10, reason: 'the schedule restarted');
      expect(before, 10);
    });
  });

  group('the flash', () {
    test('peaks immediately and is over within its duration', () {
      final storm = LightningComponent(flashDuration: 0.4)
        ..strike(distance: 100);
      // minDistance defaults to 300, so a 100-unit strike is capped at full.
      expect(storm.flash, greaterThan(0.5), reason: 'peaks at the stroke');

      storm.update(0.5);
      expect(storm.flash, 0, reason: 'past the envelope');
    });

    test('has more than one stroke, which is what reads as lightning', () {
      final storm = LightningComponent(flashDuration: 0.4, minDistance: 100)
        ..strike(distance: 100);
      final samples = <double>[];
      for (var i = 0; i < 40; i++) {
        samples.add(storm.flash);
        storm.update(0.01);
      }
      // Count the times the envelope turns back up: a single ramp down has
      // none, and reads as a camera flash.
      var rises = 0;
      for (var i = 2; i < samples.length; i++) {
        if (samples[i] > samples[i - 1] && samples[i - 1] < samples[i - 2]) {
          rises++;
        }
      }
      expect(rises, greaterThanOrEqualTo(1));
    });

    test('a nearer bolt flashes brighter than a far one', () {
      double peakAt(double distance) {
        final storm = LightningComponent(minDistance: 200, maxDistance: 5000)
          ..strike(distance: distance);
        return storm.flash;
      }

      expect(peakAt(200), greaterThan(peakAt(4000)));
    });
  });

  group('thunder', () {
    test('arrives after the sound has covered the distance', () {
      final heard = <LightningStrike>[];
      final storm = LightningComponent(
        minInterval: 1000,
        maxInterval: 1000,
        speedOfSound: 340,
        onThunder: heard.add,
      )..strike(distance: 1700);

      // 1700 / 340 = 5 seconds.
      for (var i = 0; i < 4 * 60; i++) {
        storm.update(1 / 60);
      }
      expect(heard, isEmpty, reason: 'still travelling at four seconds');

      for (var i = 0; i < 2 * 60; i++) {
        storm.update(1 / 60);
      }
      expect(heard, hasLength(1));
      expect(heard.single.distance, 1700);
      expect(heard.single.thunderDelay, closeTo(5, 1e-6));
    });

    test('several strikes in flight all arrive, in order', () {
      final heard = <double>[];
      final storm = LightningComponent(
        minInterval: 1000,
        maxInterval: 1000,
        speedOfSound: 340,
        onThunder: (s) => heard.add(s.distance),
      )
        ..strike(distance: 3400)
        ..strike(distance: 680);

      for (var i = 0; i < 15 * 60; i++) {
        storm.update(1 / 60);
      }
      expect(heard, [680, 3400], reason: 'the nearer bolt is heard first');
    });
  });

  group('driving a sky', () {
    test('holds the overcast and clears it on unmount', () {
      // The sky source needs the shader bundle, so this drives the spec-side
      // knobs through a component with no sky and checks the light instead.
      final light = DirectionalLight(intensity: 2);
      final storm = LightningComponent(
        light: light,
        lightIntensity: 10,
        minInterval: 1000,
        maxInterval: 1000,
      );
      storm.update(1 / 60);
      expect(light.intensity, closeTo(2, 1e-9), reason: 'at rest');

      storm.strike(distance: 100);
      storm.update(1 / 60);
      expect(light.intensity, greaterThan(2), reason: 'flashed');

      storm.onUnmount();
      expect(light.intensity, closeTo(2, 1e-9), reason: 'restored');
    });

    test('a clone carries the settings', () {
      final storm = LightningComponent(
        minInterval: 1,
        maxInterval: 2,
        minDistance: 10,
        maxDistance: 20,
        speedOfSound: 300,
        stormDarkening: 0.5,
      );
      final clone = storm.cloneFor(Node())! as LightningComponent;
      expect(clone.minInterval, 1);
      expect(clone.maxDistance, 20);
      expect(clone.speedOfSound, 300);
      expect(clone.stormDarkening, 0.5);
    });
  });

  group('sunDirectionForHour', () {
    test('noon is high and midnight is below the horizon', () {
      expect(sunDirectionForHour(12).y, greaterThan(0.9));
      expect(sunDirectionForHour(0).y, lessThan(-0.9));
    });

    test('dawn and dusk sit near the horizon on opposite sides', () {
      final dawn = sunDirectionForHour(6);
      final dusk = sunDirectionForHour(18);
      expect(dawn.y.abs(), lessThan(0.2));
      expect(dusk.y.abs(), lessThan(0.2));
      expect(dawn.x * dusk.x, lessThan(0), reason: 'opposite sides');
    });

    test('the result is always a unit vector', () {
      for (var hour = 0.0; hour < 24; hour += 0.5) {
        expect(
          sunDirectionForHour(hour).length,
          closeTo(1, 1e-6),
          reason: 'at $hour',
        );
      }
    });

    test('the tilt swings the arc off the vertical plane', () {
      final flat = sunDirectionForHour(9, tilt: 0);
      final leaned = sunDirectionForHour(9, tilt: 0.6);
      expect(flat.z.abs(), lessThan(1e-9));
      expect(leaned.z.abs(), greaterThan(0.1));
    });
  });

  test('vm is the vector library the component reports in', () {
    expect(sunDirectionForHour(12), isA<vm.Vector3>());
  });
}
