// The animator's document shape, read and written. Plain data, so none of it
// needs a GPU: what is at stake is that an edit to one corner of a machine
// does not quietly reshape the rest of it.

import 'package:flutter_scene_editor/src/animator/animator_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

MapValue _state(String name, {String? clip, double x = 0, double y = 0}) =>
    MapValue({
      'name': StringValue(name),
      if (clip != null) 'clip': StringValue(clip),
      'position': Vec2Value(Vector2(x, y)),
    });

MapValue _transition(
  String? from,
  String to, {
  List<MapValue> conditions = const [],
}) => MapValue({
  if (from != null) 'from': StringValue(from),
  'to': StringValue(to),
  if (conditions.isNotEmpty) 'conditions': ListValue(conditions),
});

MapValue _condition(
  String parameter,
  String comparison, [
  double threshold = 0,
]) => MapValue({
  'parameter': StringValue(parameter),
  'comparison': StringValue(comparison),
  'threshold': DoubleValue(threshold),
});

/// A flat single-layer machine, the shape a document written before layers
/// existed still has.
Map<String, PropertyValue> flatMachine() => {
  'initial': StringValue('Idle'),
  'states': ListValue([
    _state('Idle', clip: 'idle', x: 40, y: 60),
    _state('Run', clip: 'run', x: 260, y: 60),
  ]),
  'transitions': ListValue([
    _transition(
      'Idle',
      'Run',
      conditions: [_condition('speed', 'greater', 0.1)],
    ),
    _transition('Run', 'Idle', conditions: [_condition('speed', 'less', 0.1)]),
    _transition(null, 'Hit', conditions: [_condition('hit', 'triggered')]),
  ]),
};

void main() {
  group('reading', () {
    test('a flat machine reads as one base layer', () {
      final graph = readAnimatorGraph(flatMachine());
      expect(graph.layered, isFalse);
      expect(graph.layers, hasLength(1));
      final layer = graph.layers.single;
      expect(layer.name, AnimatorGraph.baseLayerName);
      expect(layer.initial, 'Idle');
      expect(layer.states.map((s) => s.name), ['Idle', 'Run']);
      expect(layer.state('Idle')!.position, const Offset(40, 60));
      expect(layer.state('Idle')!.clip, 'idle');
    });

    test('a transition with no from is from any state', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      final any = layer.transitions.firstWhere((t) => t.to == 'Hit');
      expect(any.fromAny, isTrue);
      expect(any.from, isNull);
    });

    test('a state with no position sits at the origin', () {
      final graph = readAnimatorGraph({
        'states': ListValue([
          MapValue({'name': StringValue('Idle')}),
        ]),
      });
      expect(graph.layers.single.state('Idle')!.position, Offset.zero);
    });

    test('layers read as layers, each with its own machine', () {
      final graph = readAnimatorGraph({
        'layers': ListValue([
          MapValue({
            'name': StringValue('base'),
            'states': ListValue([_state('Idle')]),
          }),
          MapValue({
            'name': StringValue('upper'),
            'weight': DoubleValue(0.5),
            'mask': MapValue({
              'joints': ListValue([StringValue('spine')]),
            }),
            'states': ListValue([_state('Aim')]),
          }),
        ]),
      });
      expect(graph.layered, isTrue);
      expect(graph.layers.map((l) => l.name), ['base', 'upper']);
      expect(graph.layers[1].weight, 0.5);
      expect(graph.layers[1].mask, isNotNull);
    });

    test('an unnamed layer still gets a name to show', () {
      final graph = readAnimatorGraph({
        'layers': ListValue([
          MapValue({
            'states': ListValue([_state('Idle')]),
          }),
        ]),
      });
      expect(graph.layers.single.name, 'layer 1');
    });
  });

  group('parameters', () {
    test('are whatever the conditions read, with the implied kind', () {
      final graph = readAnimatorGraph(flatMachine());
      expect(graph.parameters, {'hit': 'trigger', 'speed': 'number'});
    });

    test(
      'are sorted, so the list does not reorder as conditions are added',
      () {
        final graph = readAnimatorGraph({
          'transitions': ListValue([
            _transition(
              'a',
              'b',
              conditions: [
                _condition('zulu', 'isTrue'),
                _condition('alpha', 'isFalse'),
              ],
            ),
          ]),
        });
        expect(graph.parameters.keys, ['alpha', 'zulu']);
      },
    );
  });

  group('writing', () {
    test('a flat machine is written back flat', () {
      final graph = readAnimatorGraph(flatMachine());
      final written = writeAnimatorGraph(graph);
      expect(written['layers'], isA<ListValue>());
      expect((written['layers']! as ListValue).values, isEmpty);
      expect((written['states']! as ListValue).values, hasLength(2));
      expect(written['initial'], isA<StringValue>());
    });

    test('a round trip preserves what it read', () {
      final before = readAnimatorGraph(flatMachine());
      final after = readAnimatorGraph(writeAnimatorGraph(before));
      expect(after.layered, before.layered);
      final a = after.layers.single;
      final b = before.layers.single;
      expect(a.initial, b.initial);
      expect(a.states.map((s) => s.name), b.states.map((s) => s.name));
      expect(a.states.map((s) => s.position), b.states.map((s) => s.position));
      expect(
        a.transitions.map((t) => '${t.from}->${t.to}'),
        b.transitions.map((t) => '${t.from}->${t.to}'),
      );
      expect(
        a.transitions.expand((t) => t.conditions).map((c) => c.parameter),
        b.transitions.expand((t) => t.conditions).map((c) => c.parameter),
      );
    });

    test('a second layer makes a flat machine layered', () {
      final graph = readAnimatorGraph(flatMachine());
      final grown = graph.withLayers([
        ...graph.layers,
        const AnimatorLayerGraph(name: 'upper'),
      ]);
      final written = writeAnimatorGraph(grown);
      expect((written['layers']! as ListValue).values, hasLength(2));
      // The flat keys are cleared, or a reader preferring them would still see
      // the machine as it was before the second layer.
      expect((written['states']! as ListValue).values, isEmpty);
      expect((written['transitions']! as ListValue).values, isEmpty);
    });

    test('a threshold is only written where the comparison reads one', () {
      final graph = readAnimatorGraph({
        'transitions': ListValue([
          _transition(
            'a',
            'b',
            conditions: [_condition('jump', 'triggered', 4)],
          ),
        ]),
      });
      final written = writeAnimatorGraph(graph);
      final transition =
          (written['transitions']! as ListValue).values.single as MapValue;
      final condition =
          (transition.values['conditions']! as ListValue).values.single
              as MapValue;
      expect(condition.values.containsKey('threshold'), isFalse);
    });

    test("a layer's mask survives an edit that never touches it", () {
      final source = {
        'layers': ListValue([
          MapValue({
            'name': StringValue('upper'),
            'mask': MapValue({
              'joints': ListValue([StringValue('spine')]),
            }),
            'states': ListValue([_state('Aim')]),
          }),
        ]),
      };
      final graph = readAnimatorGraph(source);
      final moved = graph.withLayer(
        0,
        graph.layers.first.copyWith(
          states: [
            graph.layers.first.states.single.copyWith(
              position: const Offset(10, 10),
            ),
          ],
        ),
      );
      final written = writeAnimatorGraph(moved);
      final layer = (written['layers']! as ListValue).values.single as MapValue;
      expect(layer.values['mask'], isNotNull);
    });
  });

  group('editing', () {
    test('renaming a state carries every arrow with it', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      final renamed = renameState(layer, 'Run', 'Sprint');
      expect(renamed.states.map((s) => s.name), ['Idle', 'Sprint']);
      expect(renamed.transitions.map((t) => '${t.from}->${t.to}'), [
        'Idle->Sprint',
        'Sprint->Idle',
        'null->Hit',
      ]);
    });

    test('renaming the initial state moves the start with it', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      expect(renameState(layer, 'Idle', 'Rest').initial, 'Rest');
    });

    test('removing a state takes its arrows, and nothing else', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      final without = removeState(layer, 'Run');
      expect(without.states.map((s) => s.name), ['Idle']);
      expect(without.transitions.map((t) => t.to), ['Hit']);
    });

    test('removing the initial state hands the start to what is left', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      expect(removeState(layer, 'Idle').initial, 'Run');
    });

    test('removing the last state leaves no start pointing at nothing', () {
      var layer = readAnimatorGraph(flatMachine()).layers.single;
      layer = removeState(removeState(layer, 'Idle'), 'Run');
      expect(layer.states, isEmpty);
      expect(layer.initial, isEmpty);
    });

    test('a new state is named around the ones already there', () {
      final layer = readAnimatorGraph(flatMachine()).layers.single;
      expect(uniqueStateName(layer, 'Walk'), 'Walk');
      expect(uniqueStateName(layer, 'Idle'), 'Idle 2');
    });
  });
}
