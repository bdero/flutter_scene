import 'dart:math' as math;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  group('KeyframeCurve', () {
    test('passes through its keys and clamps outside them', () {
      final c = KeyframeCurve(const [
        Keyframe(1, 2),
        Keyframe(2, 5),
        Keyframe(4, 3),
      ]);
      expect(c.valueAt(0), 2);
      expect(c.valueAt(1), 2);
      expect(c.valueAt(2), closeTo(5, 1e-9));
      expect(c.valueAt(4), 3);
      expect(c.valueAt(9), 3);
    });

    test('never overshoots between keys', () {
      final c = KeyframeCurve(const [
        Keyframe(0, 0),
        Keyframe(1, 1),
        Keyframe(1.2, 1.05),
        Keyframe(3, 4),
        Keyframe(3.1, 4),
        Keyframe(5, 0),
      ]);
      for (var t = 0.0; t <= 5; t += 0.001) {
        expect(c.valueAt(t), inInclusiveRange(-1e-9, 4 + 1e-9));
      }
      // Monotone rise: no dip on the way up.
      var last = -1.0;
      for (var t = 0.0; t <= 3; t += 0.001) {
        final v = c.valueAt(t);
        expect(v, greaterThanOrEqualTo(last - 1e-9));
        last = v;
      }
    });

    test('a stop key comes to rest', () {
      final c = KeyframeCurve(const [
        Keyframe(0, 0),
        Keyframe(1, 1, ease: KeyframeEase.stop),
        Keyframe(2, 3),
      ]);
      const h = 1e-4;
      expect((c.valueAt(1 + h) - c.valueAt(1 - h)) / (2 * h), closeTo(0, 1e-3));
    });

    test('hold and linear keys', () {
      final hold = KeyframeCurve(const [
        Keyframe(0, 0),
        Keyframe(1, 1, ease: KeyframeEase.hold),
      ]);
      expect(hold.valueAt(0.99), 0);
      expect(hold.valueAt(1), 1);
      final linear = KeyframeCurve(const [
        Keyframe(0, 0),
        Keyframe(2, 4, ease: KeyframeEase.linear),
      ]);
      expect(linear.valueAt(0.5), closeTo(1, 1e-12));
    });
  });

  test('KeyframeTrack eases each component', () {
    final track = KeyframeTrack.vector3([
      Keyframe(0, vm.Vector3(0, 0, 0)),
      Keyframe(1, vm.Vector3(2, -2, 4)),
    ]);
    final mid = track.valueAt(0.5);
    expect(mid.x, closeTo(1, 1e-9));
    expect(mid.y, closeTo(-1, 1e-9));
    expect(mid.z, closeTo(2, 1e-9));
  });

  group('Timeline', () {
    test('fires crossed cues once, in order', () {
      final fired = <String>[];
      final timeline = Timeline(
        duration: 10,
        cues: const [Cue(2, 'b'), Cue(0, 'a'), Cue(5, 'c')],
        onCue: (c) => fired.add(c.name),
      );
      timeline.advance(0);
      expect(fired, ['a']);
      timeline.advance(2);
      expect(fired, ['a', 'b']);
      timeline.advance(2.9);
      expect(fired, ['a', 'b']);
      timeline.advance(0.2);
      expect(fired, ['a', 'b', 'c']);
      timeline.advance(100);
      expect(timeline.time, 10);
      expect(timeline.finished, isTrue);
      expect(fired, ['a', 'b', 'c']);
    });

    test('seeking forward fires skipped cues, seeking back fires none', () {
      final fired = <String>[];
      final timeline = Timeline(
        duration: 10,
        cues: const [Cue(1, 'a'), Cue(4, 'b')],
        onCue: (c) => fired.add(c.name),
      );
      timeline.seek(6);
      expect(fired, ['a', 'b']);
      timeline.seek(1);
      expect(fired, ['a', 'b']);
      timeline.advance(0.5);
      expect(fired, ['a', 'b', 'a']);
    });

    test('a looping timeline replays its cues each pass', () {
      final fired = <String>[];
      final timeline = Timeline(
        duration: 2,
        loop: true,
        cues: const [Cue(0, 'start'), Cue(1, 'mid')],
        onCue: (c) => fired.add(c.name),
      );
      timeline.advance(0.5);
      timeline.advance(1);
      timeline.advance(1);
      expect(fired, ['start', 'mid', 'start']);
      expect(timeline.time, closeTo(0.5, 1e-9));
    });
  });

  group('CameraTrack', () {
    final track = CameraTrack([
      CameraKey(time: 0, eye: vm.Vector3(0, 0, 5), target: vm.Vector3.zero()),
      CameraKey(
        time: 2,
        eye: vm.Vector3(5, 0, 0),
        target: vm.Vector3.zero(),
        fovRadiansY: 0.5,
      ),
      CameraKey(
        time: 4,
        eye: vm.Vector3(0, 0, -5),
        target: vm.Vector3(0, 1, 0),
        focusDistance: 2,
        fStop: 1.4,
      ),
    ], smoothing: 0);

    test('hits every key at its time', () {
      for (final k in track.keys) {
        final s = track.sampleAt(k.time);
        expect(s.eye.distanceTo(k.eye), lessThan(1e-6));
        expect(s.target.distanceTo(k.target), lessThan(1e-6));
      }
    });

    test('starts and ends at rest with continuous motion between', () {
      double speed(double t) =>
          track.sampleAt(t + 1e-3).eye.distanceTo(track.sampleAt(t).eye) / 1e-3;
      expect(speed(0), lessThan(0.05));
      expect(speed(4 - 1e-3), lessThan(0.05));
      var last = speed(0.01);
      for (var t = 0.02; t < 3.98; t += 0.01) {
        final v = speed(t);
        // No jumps in speed between frames at 100 Hz.
        expect((v - last).abs(), lessThan(0.25));
        last = v;
      }
    });

    test('keys carry field of view, focus, and aperture', () {
      expect(track.sampleAt(0).fovRadiansY, closeTo(0.5, 1e-9));
      expect(track.sampleAt(0).focusDistance, closeTo(5, 1e-9));
      expect(track.sampleAt(4).focusDistance, closeTo(2, 1e-9));
      expect(track.sampleAt(4).fStop, closeTo(1.4, 1e-9));
    });

    test('roll turns the camera clockwise as seen from behind', () {
      final rolled = CameraTrack([
        CameraKey(
          time: 0,
          eye: vm.Vector3(0, 0, 0),
          target: vm.Vector3(0, 0, -1),
          roll: math.pi / 2,
        ),
      ], smoothing: 0).sampleAt(0);
      // Looking down -z with +x to the right, a clockwise camera roll
      // brings its up vector to +x.
      expect(rolled.up.x, closeTo(1, 1e-9));
      expect(rolled.up.y, closeTo(0, 1e-9));
    });
  });

  group('CameraTrack smoothing', () {
    // A fast leg into a stop, then a sharp turn at closely spaced keys.
    List<CameraKey> keys() => [
      CameraKey(
        time: 0,
        eye: vm.Vector3(0, 0, 0),
        target: vm.Vector3(0, 0, -1),
      ),
      CameraKey(
        time: 2,
        eye: vm.Vector3(2, 0.5, 0),
        target: vm.Vector3(2, 0.5, -1),
      ),
      CameraKey(
        time: 3,
        eye: vm.Vector3(2.2, 0.6, 0),
        target: vm.Vector3(2.2, 0.6, -1),
        ease: KeyframeEase.stop,
      ),
      CameraKey(
        time: 3.4,
        eye: vm.Vector3(2.2, 0.7, 0.4),
        target: vm.Vector3(3, 0.7, 0.4),
      ),
      CameraKey(time: 6, eye: vm.Vector3(0, 1, 2), target: vm.Vector3(0, 1, 0)),
    ];

    // The largest change in acceleration between 240 Hz samples.
    double worstJerk(CameraTrack track) {
      const h = 1 / 240;
      vm.Vector3 acc(double t) =>
          (track.sampleAt(t + h).eye -
              track.sampleAt(t).eye * 2 +
              track.sampleAt(t - h).eye) /
          (h * h);
      var worst = 0.0;
      var last = acc(h);
      for (var t = 2 * h; t < 6 - h; t += h) {
        final a = acc(t);
        worst = math.max(worst, (a - last).length);
        last = a;
      }
      return worst;
    }

    test('keeps acceleration continuous through stops and bends', () {
      final rough = worstJerk(CameraTrack(keys(), smoothing: 0));
      final smooth = worstJerk(CameraTrack(keys(), smoothing: 0.3));
      expect(smooth, lessThan(rough / 20));
      expect(smooth, lessThan(0.2));
    });

    test('never overshoots a channel that only rises', () {
      final track = CameraTrack(keys(), smoothing: 0.5);
      var last = -1.0;
      for (var t = 0.0; t <= 6; t += 1 / 240) {
        final y = track.sampleAt(t).eye.y;
        expect(y, greaterThanOrEqualTo(last - 1e-9));
        expect(y, inInclusiveRange(-1e-9, 1 + 1e-9));
        last = y;
      }
    });

    test('stays close to the keys of a gentle move', () {
      final gentle = [
        CameraKey(
          time: 0,
          eye: vm.Vector3(0, 0, 0),
          target: vm.Vector3(0, 0, -1),
        ),
        CameraKey(
          time: 5,
          eye: vm.Vector3(1, 0, 0),
          target: vm.Vector3(1, 0, -1),
        ),
        CameraKey(
          time: 10,
          eye: vm.Vector3(2, 0.5, 0),
          target: vm.Vector3(2, 0, -1),
        ),
      ];
      final track = CameraTrack(gentle, smoothing: 0.3);
      for (final k in gentle) {
        expect(track.sampleAt(k.time).eye.distanceTo(k.eye), lessThan(0.01));
      }
    });
  });

  group('FocusPuller', () {
    test('settles on a new goal without overshoot', () {
      final puller = FocusPuller(value: 1, settleSeconds: 0.8);
      var peak = 1.0;
      for (var i = 0; i < 180; i++) {
        peak = math.max(peak, puller.update(3, 1 / 60));
      }
      expect(puller.value, closeTo(3, 1e-3));
      expect(peak, lessThanOrEqualTo(3 + 1e-6));
    });

    test('starts a pull gently', () {
      final puller = FocusPuller(value: 1, settleSeconds: 1);
      // The first frame of a pull moves a small fraction of the second's.
      final first = puller.update(0.25, 1 / 60) - 1;
      final second = puller.value;
      final step2 = puller.update(0.25, 1 / 60) - second;
      expect(first.abs(), lessThan(step2.abs() / 2));
    });

    test('eases in diopters', () {
      // Easing in diopters, a near-to-far pull and a far-to-near pull cross
      // their diopter midpoint (0.8 m, between 0.5 m and 2 m) together.
      int midpointFrame(double from, double to) {
        final puller = FocusPuller(value: from, settleSeconds: 1);
        for (var i = 1; i < 600; i++) {
          final v = puller.update(to, 1 / 240);
          if ((v - 0.8).sign == (to - 0.8).sign) return i;
        }
        return -1;
      }

      final out = midpointFrame(0.5, 2);
      final back = midpointFrame(2, 0.5);
      expect(out, greaterThan(0));
      expect((out - back).abs(), lessThanOrEqualTo(1));
    });
  });
}
