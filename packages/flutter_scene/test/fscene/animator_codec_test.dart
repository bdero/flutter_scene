// The animator codec. The machine is constructor-only -- a running animator
// moves between its states, it does not rewrite them -- so the whole graph is
// read back out and rebuilt, and a round trip is the test that matters.
import 'package:flutter_scene/src/animation/animator.dart';
import 'package:flutter_scene/src/animation/animator_component.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/kit_codecs.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

void main() {
  final codec = AnimatorCodec();
  final doc = SceneDocument();

  AnimatorComponent? realize(ComponentSpec spec) =>
      codec.realize(spec, RealizeContext(doc)) as AnimatorComponent?;

  ComponentSpec? write(AnimatorComponent component) =>
      codec.serialize(component, SerializeContext(doc));

  AnimatorComponent sample() => AnimatorComponent(
    Animator(
      states: [
        AnimatorState(
          'move',
          BlendMotion('speed', const [
            (at: 0, clip: 'Idle'),
            (at: 4, clip: 'Run'),
          ]),
        ),
        const AnimatorState(
          'jump',
          ClipMotion('Jump'),
          loop: false,
          speed: 1.5,
        ),
      ],
      transitions: const [
        AnimatorTransition(
          to: 'jump',
          from: 'move',
          duration: 0.05,
          conditions: [
            AnimatorCondition('jump', AnimatorComparison.triggered),
            AnimatorCondition(
              'speed',
              AnimatorComparison.greater,
              threshold: 2,
            ),
          ],
        ),
      ],
      initial: 'jump',
    ),
  );

  test('it is registered and filed under Animation', () {
    final registry = defaultComponentRegistry();
    expect(registry.types, contains('animator'));
    expect(registry.codecFor('animator')!.schema.category, 'Animation');
  });

  test('a whole machine survives a round trip', () {
    final spec = write(sample())!;
    final back = realize(spec)!.animator;

    expect(back.initialState, 'jump');
    expect(back.states.map((s) => s.name), unorderedEquals(['move', 'jump']));

    final blend = back.states.firstWhere((s) => s.name == 'move').motion;
    expect(blend, isA<BlendMotion>());
    expect((blend as BlendMotion).parameter, 'speed');
    expect(blend.stops.map((s) => s.clip), ['Idle', 'Run']);
    expect(blend.stops.last.at, 4);

    final jump = back.states.firstWhere((s) => s.name == 'jump');
    expect((jump.motion as ClipMotion).clip, 'Jump');
    expect(jump.loop, isFalse);
    expect(jump.speed, 1.5);

    expect(back.transitions, hasLength(1));
    final transition = back.transitions.single;
    expect(transition.from, 'move');
    expect(transition.to, 'jump');
    expect(transition.duration, 0.05);
    expect(transition.conditions, hasLength(2));
    expect(
      transition.conditions.first.comparison,
      AnimatorComparison.triggered,
    );
    expect(transition.conditions.last.threshold, 2);
  });

  test('the machine it rebuilds still behaves', () {
    // Round-tripping the graph is only worth anything if the result runs.
    final back = realize(write(sample())!)!.animator;
    back.play('move');
    back.parameters.setNumber('speed', 2);
    final weights = back.evaluate(0);
    expect(weights['Idle'], closeTo(0.5, 1e-9));
    expect(weights['Run'], closeTo(0.5, 1e-9));

    back.parameters.trigger('jump');
    back.parameters.setNumber('speed', 3);
    back.evaluate(0.016);
    expect(back.current, 'jump');
  });

  test('it writes where the machine starts, not where it is', () {
    // A saved animator must reload at its beginning; recording `current`
    // would freeze whatever was on screen when someone hit save.
    final component = sample();
    component.animator.play('move');
    final spec = write(component)!;
    expect((spec.properties['initial']! as StringValue).value, 'jump');
  });

  group('malformed input', () {
    test('an animator with no usable state is skipped', () {
      expect(realize(ComponentSpec('animator')), isNull);
    });

    test('a state naming neither a clip nor a blend is dropped', () {
      // A machine that could enter it would freeze there with nothing to
      // play, so it is better not to exist.
      final spec = ComponentSpec(
        'animator',
        properties: {
          'states': ListValue([
            MapValue({'name': const StringValue('empty')}),
            MapValue({
              'name': const StringValue('ok'),
              'clip': const StringValue('Idle'),
            }),
          ]),
        },
      );
      final animator = realize(spec)!.animator;
      expect(animator.states.map((s) => s.name), ['ok']);
    });

    test('an unknown comparison falls back rather than throwing', () {
      final spec = ComponentSpec(
        'animator',
        properties: {
          'states': ListValue([
            MapValue({
              'name': const StringValue('a'),
              'clip': const StringValue('A'),
            }),
            MapValue({
              'name': const StringValue('b'),
              'clip': const StringValue('B'),
            }),
          ]),
          'transitions': ListValue([
            MapValue({
              'to': const StringValue('b'),
              'conditions': ListValue([
                MapValue({
                  'parameter': const StringValue('go'),
                  'comparison': const StringValue('sideways'),
                }),
              ]),
            }),
          ]),
        },
      );
      final animator = realize(spec)!.animator;
      expect(
        animator.transitions.single.conditions.single.comparison,
        AnimatorComparison.isTrue,
      );
    });
  });

  test('a 2D blend round-trips its plane', () {
    final component = AnimatorComponent(
      Animator(
        states: [
          AnimatorState(
            'strafe',
            BlendMotion2D('moveX', 'moveY', const [
              (x: 0, y: 0, clip: 'Idle'),
              (x: 0, y: 1, clip: 'Forward'),
              (x: -1, y: 0, clip: 'Left'),
            ]),
          ),
        ],
      ),
    );

    final back = realize(write(component)!)!.animator;
    final motion = back.states.single.motion as BlendMotion2D;
    expect(motion.parameterX, 'moveX');
    expect(motion.parameterY, 'moveY');
    expect(motion.stops.map((s) => s.clip), ['Idle', 'Forward', 'Left']);
    expect(motion.stops.last.x, -1);
    expect(motion.stops[1].y, 1);

    // And it still blends after the trip.
    back.parameters.setNumber('moveY', 1);
    expect(back.evaluate(0), {'Forward': 1.0});
  });

  test('one blend parameter is 1D, two is 2D', () {
    // The second parameter's presence is what picks the form, so a document
    // written by hand cannot land between the two.
    ComponentSpec specWith(Map<String, PropertyValue> extra) => ComponentSpec(
      'animator',
      properties: {
        'states': ListValue([
          MapValue({
            'name': const StringValue('s'),
            'blendParameter': const StringValue('a'),
            'stops': ListValue([
              MapValue({'clip': const StringValue('A')}),
            ]),
            ...extra,
          }),
        ]),
      },
    );

    expect(
      realize(specWith({}))!.animator.states.single.motion,
      isA<BlendMotion>(),
    );
    expect(
      realize(
        specWith({'blendParameterY': const StringValue('b')}),
      )!.animator.states.single.motion,
      isA<BlendMotion2D>(),
    );
  });
}
