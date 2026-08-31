// Layers and masks: what lets a character aim while it runs. The machine half
// is pure; the mask half needs a node tree but no GPU, so a rig can be built
// out of plain nodes and asked what a mask lets through.

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// A rig: hips at the root, legs and spine under it, arms under the spine.
Node rig() {
  final hips = Node(name: 'hips');
  final spine = Node(name: 'spine');
  final chest = Node(name: 'chest');
  final handL = Node(name: 'hand_l');
  final legL = Node(name: 'leg_l');
  final footL = Node(name: 'foot_l');
  chest.add(handL);
  spine.add(chest);
  legL.add(footL);
  hips
    ..add(spine)
    ..add(legL);
  return hips;
}

Node named(Node root, String name) =>
    root.name == name ? root : root.getChildByName(name)!;

AnimatorLayer locomotion() => AnimatorLayer(
  name: 'base',
  states: [
    AnimatorState(
      'move',
      BlendMotion('speed', const [(at: 0, clip: 'idle'), (at: 6, clip: 'run')]),
    ),
  ],
);

AnimatorLayer upperBody({double weight = 1.0, AnimationMask? mask}) =>
    AnimatorLayer(
      name: 'upper',
      states: const [
        AnimatorState('rest', ClipMotion('rest')),
        AnimatorState('aim', ClipMotion('aim')),
      ],
      transitions: const [
        AnimatorTransition(
          to: 'aim',
          from: 'rest',
          conditions: [AnimatorCondition('aiming', AnimatorComparison.isTrue)],
          duration: 0,
        ),
        AnimatorTransition(
          to: 'rest',
          from: 'aim',
          conditions: [AnimatorCondition('aiming', AnimatorComparison.isFalse)],
          duration: 0,
        ),
      ],
      weight: weight,
      mask: mask,
    );

void main() {
  group('masks', () {
    test('a named joint and its subtree are inside; the rest is out', () {
      final root = rig();
      final mask = AnimationMask(const ['spine']);

      expect(mask.weightFor(named(root, 'spine')), 1.0);
      expect(mask.weightFor(named(root, 'chest')), 1.0);
      expect(mask.weightFor(named(root, 'hand_l')), 1.0);
      expect(mask.weightFor(named(root, 'hips')), 0.0);
      expect(mask.weightFor(named(root, 'leg_l')), 0.0);
      expect(mask.weightFor(named(root, 'foot_l')), 0.0);
    });

    test('without descendants only the named joints are in', () {
      final root = rig();
      final mask = AnimationMask(const ['spine'], includeDescendants: false);
      expect(mask.weightFor(named(root, 'spine')), 1.0);
      expect(mask.weightFor(named(root, 'chest')), 0.0);
    });

    test('outside weight makes it a partial blend, not a cut', () {
      final root = rig();
      final mask = AnimationMask(const ['spine'], outsideWeight: 0.25);
      expect(mask.weightFor(named(root, 'chest')), 1.0);
      expect(mask.weightFor(named(root, 'leg_l')), 0.25);
    });

    test('a mask naming nothing is uniform, so it costs no per-node work', () {
      expect(AnimationMask(const []).isUniform, isTrue);
      expect(AnimationMask.everything.isUniform, isTrue);
      expect(AnimationMask.everything.uniformWeight, 1.0);
      expect(AnimationMask(const ['spine']).isUniform, isFalse);
    });

    test('scaling keeps the shape and changes the strength', () {
      final root = rig();
      final half = AnimationMask(const [
        'spine',
      ], outsideWeight: 0.4).scaled(0.5);
      expect(half.weightFor(named(root, 'chest')), closeTo(0.5, 1e-9));
      expect(half.weightFor(named(root, 'leg_l')), closeTo(0.2, 1e-9));
    });
  });

  group('layers', () {
    test('a machine built the short way has one base layer', () {
      final animator = Animator(
        states: const [AnimatorState('idle', ClipMotion('idle'))],
      );
      expect(animator.layers, hasLength(1));
      expect(animator.base.name, Animator.defaultLayerName);
      expect(animator.current, 'idle');
      expect(animator.evaluate(0), {'idle': 1.0});
    });

    test('each layer runs its own machine off the shared parameters', () {
      final animator = Animator.layered([locomotion(), upperBody()]);
      animator.parameters
        ..setNumber('speed', 6)
        ..setFlag('aiming', value: true);

      final layers = animator.evaluateLayers(1 / 60);
      expect(layers, hasLength(2));
      expect(layers[0].layer.name, 'base');
      expect(layers[0].weights, {'run': 1.0});
      expect(layers[1].layer.name, 'upper');
      expect(layers[1].weights, {'aim': 1.0});
      expect(animator.layer('upper')!.current, 'aim');
      expect(
        animator.current,
        'move',
        reason: 'the short accessors still mean the base layer',
      );
    });

    test('a silent layer asks for nothing but keeps thinking', () {
      // A layer faded out mid-reload should come back where the reload got
      // to, not where it was when it faded.
      final upper = upperBody(weight: 0);
      final animator = Animator.layered([locomotion(), upper]);
      animator.parameters.setFlag('aiming', value: true);

      final layers = animator.evaluateLayers(1 / 60);
      expect(layers[1].weights, isEmpty);
      expect(
        upper.current,
        'aim',
        reason: 'its transitions run even at zero weight',
      );

      upper.weight = 1;
      expect(animator.evaluateLayers(1 / 60)[1].weights, {'aim': 1.0});
    });

    test('layer weight scales what the layer asked for, not what it chose', () {
      final upper = upperBody(weight: 0.5);
      final animator = Animator.layered([locomotion(), upper]);
      animator.parameters.setFlag('aiming', value: true);
      // The layer still normalizes to one internally; the weight is applied
      // where the clips are set, so the machine's own arithmetic is unchanged.
      expect(animator.evaluateLayers(1 / 60)[1].weights, {'aim': 1.0});
      expect(upper.weight, 0.5);
    });

    test('an unknown layer name is null rather than an error', () {
      final animator = Animator.layered([locomotion()]);
      expect(animator.layer('nope'), isNull);
      expect(animator.layer('base'), isNotNull);
    });

    test('a layered machine needs at least one layer', () {
      expect(() => Animator.layered(const []), throwsA(isA<AssertionError>()));
    });

    test('play and crossFade still drive the base layer', () {
      final animator = Animator.layered([
        AnimatorLayer(
          name: 'base',
          states: const [
            AnimatorState('a', ClipMotion('a')),
            AnimatorState('b', ClipMotion('b')),
          ],
        ),
        upperBody(),
      ]);

      animator.crossFade('b', 0.2);
      expect(animator.isBlending, isTrue);
      expect(animator.current, 'b');
      animator.play('a');
      expect(animator.isBlending, isFalse);
      expect(animator.current, 'a');
    });
  });
}
