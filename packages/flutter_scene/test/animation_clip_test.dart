/// Covers the public playback surface of [AnimationClip]: state setters,
/// `play`/`pause`/`stop`/`replay`/`gotoAndPlay`, `seek`, `weight`
/// clamping, and `advance` boundary behavior under both `loop = false`
/// and `loop = true`.
library;

import 'package:flutter_scene/scene.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// Builds a 1-second animation clip bound to [node] with a single
/// translation channel. The shape of the timeline doesn't matter for the
/// playback tests; only `endTime` does.
AnimationClip _makeClip(Node node, {double endTime = 1.0}) {
  final resolver = PropertyResolver.makeTranslationTimeline(
    [0.0, endTime],
    [Vector3.zero(), Vector3(1, 0, 0)],
  );
  final channel = AnimationChannel(
    bindTarget: BindKey(nodeName: node.name),
    resolver: resolver,
  );
  final animation = Animation(name: 'test', channels: [channel]);
  return node.createAnimationClip(animation);
}

/// Empty animation (no channels). `endTime` is `0`, which exercises the
/// degenerate-clip branch of `advance`.
AnimationClip _makeEmptyClip(Node node) {
  final animation = Animation(name: 'empty', channels: []);
  return node.createAnimationClip(animation);
}

void main() {
  group('initial state', () {
    test('clip starts paused at time 0 with weight 1', () {
      final clip = _makeClip(Node(name: 'n'));
      expect(clip.playing, false);
      expect(clip.playbackTime, 0);
      expect(clip.weight, 1);
      expect(clip.loop, false);
      expect(clip.playbackTimeScale, 1);
    });
  });

  group('play / pause / stop', () {
    test('play() flips playing without touching playbackTime', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.seek(0.3);
      clip.play();
      expect(clip.playing, true);
      expect(clip.playbackTime, 0.3);
    });

    test('pause() flips playing without touching playbackTime', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.seek(0.3);
      clip.pause();
      expect(clip.playing, false);
      expect(clip.playbackTime, 0.3);
    });

    test('stop() pauses and rewinds', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.seek(0.7);
      clip.stop();
      expect(clip.playing, false);
      expect(clip.playbackTime, 0);
    });
  });

  group('replay / gotoAndPlay', () {
    test('replay() rewinds to 0 and starts playing', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.seek(0.9);
      // Simulate the "non-looping clip stuck at end" condition: pause was
      // already false because we never called play(). Either way, replay
      // should land us at time 0 with playing=true.
      clip.replay();
      expect(clip.playing, true);
      expect(clip.playbackTime, 0);
    });

    test('replay() works after the clip auto-paused at end', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.advance(2.0); // Runs past the 1.0 endTime.
      expect(clip.playing, false, reason: 'auto-paused at endTime');
      expect(clip.playbackTime, 1.0);

      clip.replay();
      expect(clip.playing, true);
      expect(clip.playbackTime, 0);
    });

    test('gotoAndPlay(t) seeks and plays', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.gotoAndPlay(0.4);
      expect(clip.playing, true);
      expect(clip.playbackTime, 0.4);
    });

    test('gotoAndPlay clamps time to [0, endTime]', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.gotoAndPlay(2.5);
      expect(clip.playbackTime, 1.0);
      clip.gotoAndPlay(-0.5);
      expect(clip.playbackTime, 0);
    });
  });

  group('seek / playbackTime setter', () {
    test('seek clamps to [0, endTime]', () {
      final clip = _makeClip(Node(name: 'n'), endTime: 2.0);
      clip.seek(-1.0);
      expect(clip.playbackTime, 0);
      clip.seek(5.0);
      expect(clip.playbackTime, 2.0);
      clip.seek(1.25);
      expect(clip.playbackTime, 1.25);
    });

    test('playbackTime setter is equivalent to seek', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.playbackTime = 0.5;
      expect(clip.playbackTime, 0.5);
      clip.playbackTime = 99;
      expect(clip.playbackTime, 1.0);
    });

    test('seek does not change playing', () {
      final clip = _makeClip(Node(name: 'n'));
      expect(clip.playing, false);
      clip.seek(0.5);
      expect(clip.playing, false);

      clip.play();
      clip.seek(0.7);
      expect(clip.playing, true);
    });
  });

  group('weight clamping', () {
    test('weight setter clamps to [0, 1]', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.weight = -2;
      expect(clip.weight, 0);
      clip.weight = 5;
      expect(clip.weight, 1);
      clip.weight = 0.4;
      expect(clip.weight, 0.4);
    });
  });

  group('advance', () {
    test('does nothing when paused', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.advance(0.5);
      expect(clip.playbackTime, 0);
    });

    test('does nothing when deltaTime is non-positive', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.advance(0);
      expect(clip.playbackTime, 0);
      clip.advance(-0.1);
      expect(clip.playbackTime, 0);
    });

    test('advances playbackTime by deltaTime when playing', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.advance(0.25);
      expect(clip.playbackTime, closeTo(0.25, 1e-9));
      clip.advance(0.5);
      expect(clip.playbackTime, closeTo(0.75, 1e-9));
    });

    test('playbackTimeScale multiplies the effective delta', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.playbackTimeScale = 2.0;
      clip.advance(0.25);
      expect(clip.playbackTime, closeTo(0.5, 1e-9));
    });

    test('reverse playback (negative scale + loop=false) clamps at 0', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.seek(0.3);
      clip.playbackTimeScale = -1.0;
      clip.advance(0.5); // -0.5 effective; would land at -0.2.
      expect(clip.playbackTime, 0);
      expect(clip.playing, false, reason: 'auto-paused at start boundary');
    });

    test('non-looping clip clamps and pauses at endTime', () {
      final clip = _makeClip(Node(name: 'n'));
      clip.play();
      clip.advance(1.5); // past the 1.0 endTime.
      expect(clip.playbackTime, 1.0);
      expect(clip.playing, false);
    });

    test('looping clip wraps past endTime', () {
      final clip = _makeClip(Node(name: 'n'), endTime: 1.0);
      clip.loop = true;
      clip.play();
      clip.advance(1.25);
      expect(clip.playbackTime, closeTo(0.25, 1e-9));
      expect(clip.playing, true);
    });

    test('looping clip wraps when running negative', () {
      final clip = _makeClip(Node(name: 'n'), endTime: 1.0);
      clip.loop = true;
      clip.play();
      clip.seek(0.1);
      clip.playbackTimeScale = -1.0;
      clip.advance(0.4); // -0.4 effective from 0.1 → wraps to 0.7.
      expect(clip.playbackTime, closeTo(0.7, 1e-9));
      expect(clip.playing, true);
    });

    test('zero-length animation stays pinned at 0', () {
      final clip = _makeEmptyClip(Node(name: 'n'));
      clip.play();
      clip.advance(0.5);
      expect(clip.playbackTime, 0);
    });
  });
}
