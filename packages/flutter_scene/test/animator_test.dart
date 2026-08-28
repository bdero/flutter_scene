// The clip state machine: blend trees, transitions, cross-fades and trigger
// consumption. All pure, so none of it needs a GPU.
import 'package:flutter_scene/src/animation/animator.dart';
import 'package:flutter_test/flutter_test.dart';

Animator locomotion({List<AnimatorTransition> transitions = const []}) =>
    Animator(
      states: [
        AnimatorState(
          'move',
          BlendMotion('speed', const [
            (at: 0, clip: 'idle'),
            (at: 2, clip: 'walk'),
            (at: 6, clip: 'run'),
          ]),
        ),
        const AnimatorState('jump', ClipMotion('jump'), loop: false),
        const AnimatorState('hit', ClipMotion('hit'), loop: false),
      ],
      transitions: transitions,
    );

void main() {
  group('blend trees', () {
    test('a value on a stop plays that clip alone', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 2);
      expect(animator.evaluate(0), {'walk': 1.0});
    });

    test('a value between stops mixes the two either side', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 4);
      final weights = animator.evaluate(0);
      expect(weights.keys, unorderedEquals(['walk', 'run']));
      expect(weights['walk'], closeTo(0.5, 1e-9));
      expect(weights['run'], closeTo(0.5, 1e-9));
    });

    test('only the two neighbouring clips are mixed, never a third', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 1);
      expect(animator.evaluate(0).keys, unorderedEquals(['idle', 'walk']));
    });

    test('past the ends the nearest clip holds rather than extrapolating', () {
      // Running faster than the run clip was authored for should not start
      // scaling it into something nobody animated.
      final animator = locomotion();
      animator.parameters.setNumber('speed', 99);
      expect(animator.evaluate(0), {'run': 1.0});
      animator.parameters.setNumber('speed', -5);
      expect(animator.evaluate(0), {'idle': 1.0});
    });

    test('stops may be given out of order', () {
      final motion = BlendMotion('speed', const [
        (at: 6, clip: 'run'),
        (at: 0, clip: 'idle'),
        (at: 2, clip: 'walk'),
      ]);
      expect(motion.stops.map((s) => s.clip), ['idle', 'walk', 'run']);
    });
  });

  group('transitions', () {
    test('fires when its conditions hold', () {
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'jump',
            from: 'move',
            conditions: [
              AnimatorCondition('jump', AnimatorComparison.triggered),
            ],
            duration: 0,
          ),
        ],
      );
      expect(animator.current, 'move');
      animator.evaluate(0.016);
      expect(animator.current, 'move', reason: 'nothing triggered it yet');

      animator.parameters.trigger('jump');
      animator.evaluate(0.016);
      expect(animator.current, 'jump');
    });

    test('taking a transition consumes the trigger that fired it', () {
      // Otherwise a held button re-fires the jump every frame.
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'jump',
            conditions: [
              AnimatorCondition('jump', AnimatorComparison.triggered),
            ],
            duration: 0,
          ),
        ],
      );
      animator.parameters.trigger('jump');
      animator.evaluate(0.016);
      expect(animator.parameters.isTriggered('jump'), isFalse);
    });

    test('a transition with no from applies in any state', () {
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'hit',
            conditions: [AnimatorCondition('hurt', AnimatorComparison.isTrue)],
            duration: 0,
          ),
        ],
      );
      animator.play('jump');
      animator.parameters.setFlag('hurt', value: true);
      animator.evaluate(0.016);
      expect(animator.current, 'hit');
    });

    test('a transition into the current state does not re-fire', () {
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'hit',
            conditions: [AnimatorCondition('hurt', AnimatorComparison.isTrue)],
            duration: 0.2,
          ),
        ],
      );
      animator.parameters.setFlag('hurt', value: true);
      animator.evaluate(0.05);
      expect(animator.current, 'hit');
      final started = animator.blendProgress;

      // The condition still holds, but the machine is already there. The fade
      // must carry on rather than restarting from zero every frame, which
      // would leave it permanently half-blended.
      animator.evaluate(0.05);
      expect(animator.blendProgress, greaterThan(started));
      expect(animator.previous, 'move');
    });

    test('numeric conditions compare against their threshold', () {
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'jump',
            conditions: [
              AnimatorCondition(
                'speed',
                AnimatorComparison.greater,
                threshold: 5,
              ),
            ],
            duration: 0,
          ),
        ],
      );
      animator.parameters.setNumber('speed', 4);
      animator.evaluate(0.016);
      expect(animator.current, 'move');
      animator.parameters.setNumber('speed', 6);
      animator.evaluate(0.016);
      expect(animator.current, 'jump');
    });

    test('declaration order is priority', () {
      final animator = locomotion(
        transitions: const [
          AnimatorTransition(
            to: 'hit',
            conditions: [AnimatorCondition('any', AnimatorComparison.isTrue)],
            duration: 0,
          ),
          AnimatorTransition(
            to: 'jump',
            conditions: [AnimatorCondition('any', AnimatorComparison.isTrue)],
            duration: 0,
          ),
        ],
      );
      animator.parameters.setFlag('any', value: true);
      animator.evaluate(0.016);
      expect(animator.current, 'hit');
    });
  });

  group('cross-fades', () {
    test(
      'weights move from the old state to the new one over the duration',
      () {
        final animator = locomotion();
        animator.parameters.setNumber('speed', 0);
        animator.crossFade('jump', 1.0);

        final quarter = animator.evaluate(0.25);
        expect(quarter['idle'], closeTo(0.75, 1e-9));
        expect(quarter['jump'], closeTo(0.25, 1e-9));

        final half = animator.evaluate(0.25);
        expect(half['idle'], closeTo(0.5, 1e-9));
        expect(half['jump'], closeTo(0.5, 1e-9));
      },
    );

    test('the fade ends and the old state stops contributing', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 0);
      animator.crossFade('jump', 0.5);
      animator.evaluate(0.6);
      expect(animator.isBlending, isFalse);
      expect(animator.evaluate(0), {'jump': 1.0});
    });

    test('a zero-length fade is a cut', () {
      final animator = locomotion();
      animator.crossFade('jump', 0);
      expect(animator.isBlending, isFalse);
      expect(animator.current, 'jump');
    });

    test('weights always sum to one, mid-fade included', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 3);
      animator.crossFade('jump', 1.0);
      for (var i = 0; i < 5; i++) {
        final weights = animator.evaluate(0.2);
        final total = weights.values.fold(0.0, (a, b) => a + b);
        expect(total, closeTo(1.0, 1e-9));
      }
    });

    test('interrupting a fade blends from where it is, not where it began', () {
      final animator = locomotion();
      animator.parameters.setNumber('speed', 0);
      animator.crossFade('jump', 1.0);
      animator.evaluate(0.5);
      // Changing mind halfway: the outgoing side becomes the in-between
      // state, so nothing snaps back to idle.
      animator.crossFade('hit', 1.0);
      expect(animator.previous, 'jump');
      final weights = animator.evaluate(0.5);
      expect(weights['hit'], closeTo(0.5, 1e-9));
    });
  });

  group('construction', () {
    test('starts in the named initial state', () {
      final animator = Animator(
        states: const [
          AnimatorState('a', ClipMotion('a')),
          AnimatorState('b', ClipMotion('b')),
        ],
        initial: 'b',
      );
      expect(animator.current, 'b');
    });

    test('an unknown initial state falls back to the first', () {
      final animator = Animator(
        states: const [
          AnimatorState('a', ClipMotion('a')),
          AnimatorState('b', ClipMotion('b')),
        ],
        initial: 'nope',
      );
      expect(animator.current, 'a');
    });

    test('playing or fading to an unknown state is ignored', () {
      final animator = locomotion();
      animator.play('nope');
      expect(animator.current, 'move');
      animator.crossFade('nope', 1);
      expect(animator.current, 'move');
      expect(animator.isBlending, isFalse);
    });
  });

  group('2D blends', () {
    // The directional locomotion set: idle in the middle, a clip each way.
    BlendMotion2D directional() => BlendMotion2D('x', 'y', const [
      (x: 0, y: 0, clip: 'idle'),
      (x: 0, y: 1, clip: 'forward'),
      (x: 0, y: -1, clip: 'back'),
      (x: 1, y: 0, clip: 'right'),
      (x: -1, y: 0, clip: 'left'),
    ]);

    Map<String, double> at(double x, double y) {
      final parameters = AnimatorParameters()
        ..setNumber('x', x)
        ..setNumber('y', y);
      return directional().weights(parameters);
    }

    test('landing on a stop plays that clip alone', () {
      expect(at(0, 1), {'forward': 1.0});
      expect(at(-1, 0), {'left': 1.0});
      expect(at(0, 0), {'idle': 1.0});
    });

    test('weights always sum to one', () {
      for (final point in const [
        (0.0, 0.0),
        (0.5, 0.5),
        (-0.3, 0.8),
        (2.0, 2.0),
        (0.25, -0.75),
      ]) {
        final total = at(point.$1, point.$2).values.fold(0.0, (a, b) => a + b);
        expect(total, closeTo(1.0, 1e-9), reason: 'at $point');
      }
    });

    test('between two stops it mixes those two, not the opposite ones', () {
      // Halfway between idle and forward should not wake up the back clip.
      final weights = at(0, 0.5);
      expect(weights['forward'], greaterThan(0));
      expect(weights.containsKey('back'), isFalse);
      expect(weights.containsKey('left'), isFalse);
      expect(weights.containsKey('right'), isFalse);
    });

    test('a diagonal draws on both neighbouring directions', () {
      final weights = at(0.5, 0.5);
      expect(weights['forward'], greaterThan(0));
      expect(weights['right'], greaterThan(0));
      expect(weights.containsKey('back'), isFalse);
      expect(weights.containsKey('left'), isFalse);
      // Symmetric input, symmetric output.
      expect(weights['forward'], closeTo(weights['right']!, 1e-9));
    });

    test('the strongest weight is the direction actually being moved', () {
      final weights = at(0.2, 0.9);
      final strongest = weights.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      expect(strongest.key, 'forward');
    });

    test('far outside the set the nearest clip takes over', () {
      // Every band is closed out there, so rather than returning nothing it
      // falls back to whichever stop is closest.
      expect(at(0, 50), {'forward': 1.0});
      expect(at(-50, 0), {'left': 1.0});
    });

    test('two stops naming one clip sum rather than overwrite', () {
      // The same clip can be pinned in several places -- a turn used for both
      // directions -- and its weight is the total of them, not the last one.
      const positions = [(x: -1.0, y: 0.0), (x: 1.0, y: 0.0), (x: 0.0, y: 1.0)];
      final shared = BlendMotion2D('x', 'y', [
        (x: positions[0].x, y: positions[0].y, clip: 'turn'),
        (x: positions[1].x, y: positions[1].y, clip: 'turn'),
        (x: positions[2].x, y: positions[2].y, clip: 'forward'),
      ]);
      final distinct = BlendMotion2D('x', 'y', [
        (x: positions[0].x, y: positions[0].y, clip: 'left'),
        (x: positions[1].x, y: positions[1].y, clip: 'right'),
        (x: positions[2].x, y: positions[2].y, clip: 'forward'),
      ]);

      final parameters = AnimatorParameters();
      final merged = shared.weights(parameters);
      final apart = distinct.weights(parameters);

      expect(merged['turn'], closeTo(apart['left']! + apart['right']!, 1e-9));
      expect(merged['forward'], closeTo(apart['forward']!, 1e-9));
      expect(merged.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('coincident stops do not divide by zero', () {
      final motion = BlendMotion2D('x', 'y', const [
        (x: 0, y: 0, clip: 'a'),
        (x: 0, y: 0, clip: 'b'),
      ]);
      final weights = motion.weights(AnimatorParameters());
      expect(weights.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('a single stop is that clip everywhere', () {
      final motion = BlendMotion2D('x', 'y', const [
        (x: 3, y: 4, clip: 'only'),
      ]);
      expect(motion.weights(AnimatorParameters()..setNumber('x', -100)), {
        'only': 1.0,
      });
    });
  });
}
