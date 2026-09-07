/// The animator component, as a graph an editor can draw and edit.
///
/// The document holds a state machine as lists of maps: states with what they
/// play, transitions with their conditions, and — for a character doing two
/// things at once — layers holding a machine each. This reads that into
/// something with names and offsets on it, and writes edits back in the shape
/// it found them.
///
/// That last part matters. A single-layer machine is written flat, which is
/// also what every document written before layers existed looks like, and
/// rewriting one into the layered spelling on the first drag of a box would
/// be a diff nobody asked for.
///
/// Everything here is plain data over [PropertyValue], so the whole model is
/// testable without a GPU, a scene, or a frame.
library;

import 'dart:ui' show Offset;

import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

/// How a transition compares its parameter. The spellings the codec accepts.
const List<String> animatorComparisons = [
  'greater',
  'less',
  'isTrue',
  'isFalse',
  'triggered',
];

/// Whether [comparison] reads a number, and so needs a threshold beside it.
bool comparisonUsesThreshold(String comparison) =>
    comparison == 'greater' || comparison == 'less';

/// Which kind of parameter a comparison implies, for the parameter list.
String parameterKindFor(String comparison) => switch (comparison) {
  'greater' || 'less' => 'number',
  'triggered' => 'trigger',
  _ => 'flag',
};

/// A sentinel for copyWith, so a nullable field can be set back to null.
const Object _keep = Object();

/// One clip in a blend state, and where it sits in the blend.
class AnimatorStop {
  const AnimatorStop({required this.clip, this.at = 0, this.position});

  /// The animation's name on the model.
  final String clip;

  /// Where it is pinned on a 1D blend.
  final double at;

  /// Where it sits on the plane, on a 2D blend.
  final Offset? position;

  AnimatorStop copyWith({String? clip, double? at, Offset? position}) =>
      AnimatorStop(
        clip: clip ?? this.clip,
        at: at ?? this.at,
        position: position ?? this.position,
      );
}

/// One state: what it plays, and where its box is.
class AnimatorStateNode {
  const AnimatorStateNode({
    required this.name,
    this.clip,
    this.blendParameter,
    this.blendParameterY,
    this.stops = const [],
    this.loop = true,
    this.speed = 1,
    this.position = Offset.zero,
  });

  final String name;

  /// The single clip this state plays, or null when it blends.
  final String? clip;

  /// The parameter driving the blend, or null for a single clip.
  final String? blendParameter;

  /// The second blend parameter; its presence makes the blend 2D.
  final String? blendParameterY;

  final List<AnimatorStop> stops;
  final bool loop;
  final double speed;

  /// Where the box sits on the canvas.
  final Offset position;

  /// Whether this state blends across clips rather than playing one.
  bool get blends => blendParameter != null && blendParameter!.isNotEmpty;

  /// Whether the blend is over two parameters rather than one.
  bool get is2D => blendParameterY != null && blendParameterY!.isNotEmpty;

  AnimatorStateNode copyWith({
    String? name,
    Object? clip = _keep,
    Object? blendParameter = _keep,
    Object? blendParameterY = _keep,
    List<AnimatorStop>? stops,
    bool? loop,
    double? speed,
    Offset? position,
  }) => AnimatorStateNode(
    name: name ?? this.name,
    clip: clip == _keep ? this.clip : clip as String?,
    blendParameter: blendParameter == _keep
        ? this.blendParameter
        : blendParameter as String?,
    blendParameterY: blendParameterY == _keep
        ? this.blendParameterY
        : blendParameterY as String?,
    stops: stops ?? this.stops,
    loop: loop ?? this.loop,
    speed: speed ?? this.speed,
    position: position ?? this.position,
  );
}

/// One test a transition must pass.
class AnimatorConditionEdit {
  const AnimatorConditionEdit({
    required this.parameter,
    this.comparison = 'isTrue',
    this.threshold = 0,
  });

  final String parameter;
  final String comparison;
  final double threshold;

  AnimatorConditionEdit copyWith({
    String? parameter,
    String? comparison,
    double? threshold,
  }) => AnimatorConditionEdit(
    parameter: parameter ?? this.parameter,
    comparison: comparison ?? this.comparison,
    threshold: threshold ?? this.threshold,
  );
}

/// One arrow: which states, how long the cross-fade, and what has to hold.
class AnimatorTransitionEdge {
  const AnimatorTransitionEdge({
    required this.to,
    this.from,
    this.duration = 0.2,
    this.conditions = const [],
  });

  /// The state left, or null for "from any state" — which is how a hit
  /// reaction or a death interrupts whatever is playing.
  final String? from;

  final String to;
  final double duration;
  final List<AnimatorConditionEdit> conditions;

  /// Whether this applies in any state rather than leaving a named one.
  bool get fromAny => from == null || from!.isEmpty;

  AnimatorTransitionEdge copyWith({
    Object? from = _keep,
    String? to,
    double? duration,
    List<AnimatorConditionEdit>? conditions,
  }) => AnimatorTransitionEdge(
    from: from == _keep ? this.from : from as String?,
    to: to ?? this.to,
    duration: duration ?? this.duration,
    conditions: conditions ?? this.conditions,
  );
}

/// One machine: its states, its arrows, and how much of the skeleton it moves.
class AnimatorLayerGraph {
  const AnimatorLayerGraph({
    required this.name,
    this.initial = '',
    this.weight = 1,
    this.states = const [],
    this.transitions = const [],
    this.mask,
  });

  final String name;

  /// The state the layer starts in. Empty means the first one.
  final String initial;

  final double weight;
  final List<AnimatorStateNode> states;
  final List<AnimatorTransitionEdge> transitions;

  /// The joint mask, carried through untouched: the graph editor does not
  /// author it, and dropping it on a write would silently unmask the layer.
  final PropertyValue? mask;

  /// The state named [name], or null.
  AnimatorStateNode? state(String name) {
    for (final candidate in states) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }

  AnimatorLayerGraph copyWith({
    String? name,
    String? initial,
    double? weight,
    List<AnimatorStateNode>? states,
    List<AnimatorTransitionEdge>? transitions,
  }) => AnimatorLayerGraph(
    name: name ?? this.name,
    initial: initial ?? this.initial,
    weight: weight ?? this.weight,
    states: states ?? this.states,
    transitions: transitions ?? this.transitions,
    mask: mask,
  );
}

/// The whole machine on one component.
class AnimatorGraph {
  const AnimatorGraph({required this.layers, required this.layered});

  final List<AnimatorLayerGraph> layers;

  /// Whether the document wrote this as layers. A flat machine stays flat
  /// until something actually needs a second layer.
  final bool layered;

  /// The name every layer uses when the document is flat.
  static const String baseLayerName = 'base';

  /// Every parameter any condition on any layer reads, with the kind its
  /// comparison implies, sorted by name.
  ///
  /// The document does not declare parameters — a machine's parameters are
  /// whatever its conditions read — so this is how the editor knows what to
  /// list, and it cannot go stale.
  Map<String, String> get parameters {
    final found = <String, String>{};
    for (final layer in layers) {
      for (final transition in layer.transitions) {
        for (final condition in transition.conditions) {
          if (condition.parameter.isEmpty) continue;
          found[condition.parameter] = parameterKindFor(condition.comparison);
        }
      }
    }
    return {for (final key in found.keys.toList()..sort()) key: found[key]!};
  }

  AnimatorGraph withLayer(int index, AnimatorLayerGraph layer) => AnimatorGraph(
    layers: [
      for (var i = 0; i < layers.length; i++)
        if (i == index) layer else layers[i],
    ],
    layered: layered,
  );

  AnimatorGraph withLayers(List<AnimatorLayerGraph> replacement) =>
      AnimatorGraph(layers: replacement, layered: layered);
}

// --- reading -----------------------------------------------------------------

double _number(PropertyValue? value, [double fallback = 0]) => switch (value) {
  DoubleValue(:final value) => value,
  IntValue(:final value) => value.toDouble(),
  _ => fallback,
};

String _string(PropertyValue? value, [String fallback = '']) =>
    value is StringValue ? value.value : fallback;

String? _stringOrNull(PropertyValue? value) {
  final text = value is StringValue ? value.value : null;
  return text == null || text.isEmpty ? null : text;
}

bool _bool(PropertyValue? value, [bool fallback = false]) =>
    value is BoolValue ? value.value : fallback;

Offset? _offset(PropertyValue? value) =>
    value is Vec2Value ? Offset(value.value.x, value.value.y) : null;

List<PropertyValue> _list(PropertyValue? value) =>
    value is ListValue ? value.values : const [];

AnimatorStop _readStop(PropertyValue value) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  return AnimatorStop(
    clip: _string(map['clip']),
    at: _number(map['at']),
    position: _offset(map['position']),
  );
}

AnimatorStateNode _readState(PropertyValue value) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  return AnimatorStateNode(
    name: _string(map['name']),
    clip: _stringOrNull(map['clip']),
    blendParameter: _stringOrNull(map['blendParameter']),
    blendParameterY: _stringOrNull(map['blendParameterY']),
    stops: [for (final stop in _list(map['stops'])) _readStop(stop)],
    loop: _bool(map['loop'], true),
    speed: _number(map['speed'], 1),
    position: _offset(map['position']) ?? Offset.zero,
  );
}

AnimatorConditionEdit _readCondition(PropertyValue value) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  return AnimatorConditionEdit(
    parameter: _string(map['parameter']),
    comparison: _string(map['comparison'], 'isTrue'),
    threshold: _number(map['threshold']),
  );
}

AnimatorTransitionEdge _readTransition(PropertyValue value) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  return AnimatorTransitionEdge(
    from: _stringOrNull(map['from']),
    to: _string(map['to']),
    duration: _number(map['duration'], 0.2),
    conditions: [
      for (final condition in _list(map['conditions']))
        _readCondition(condition),
    ],
  );
}

AnimatorLayerGraph _readLayer(PropertyValue value, {required String fallback}) {
  final map = value is MapValue
      ? value.values
      : const <String, PropertyValue>{};
  return AnimatorLayerGraph(
    name: _string(map['name'], fallback),
    initial: _string(map['initial']),
    weight: _number(map['weight'], 1),
    states: [for (final state in _list(map['states'])) _readState(state)],
    transitions: [
      for (final transition in _list(map['transitions']))
        _readTransition(transition),
    ],
    mask: map['mask'],
  );
}

/// Reads the graph out of an animator component's properties.
AnimatorGraph readAnimatorGraph(Map<String, PropertyValue> properties) {
  final rawLayers = properties['layers'];
  if (rawLayers is ListValue && rawLayers.values.isNotEmpty) {
    return AnimatorGraph(
      layered: true,
      layers: [
        for (var i = 0; i < rawLayers.values.length; i++)
          _readLayer(rawLayers.values[i], fallback: 'layer ${i + 1}'),
      ],
    );
  }
  return AnimatorGraph(
    layered: false,
    layers: [
      AnimatorLayerGraph(
        name: AnimatorGraph.baseLayerName,
        initial: _string(properties['initial']),
        states: [
          for (final state in _list(properties['states'])) _readState(state),
        ],
        transitions: [
          for (final transition in _list(properties['transitions']))
            _readTransition(transition),
        ],
      ),
    ],
  );
}

// --- writing -----------------------------------------------------------------

PropertyValue _writeStop(AnimatorStop stop, {required bool is2D}) => MapValue({
  'clip': StringValue(stop.clip),
  if (is2D && stop.position != null)
    'position': Vec2Value(Vector2(stop.position!.dx, stop.position!.dy))
  else
    'at': DoubleValue(stop.at),
});

PropertyValue _writeState(AnimatorStateNode state) => MapValue({
  'name': StringValue(state.name),
  if (state.clip != null) 'clip': StringValue(state.clip!),
  if (state.blendParameter != null)
    'blendParameter': StringValue(state.blendParameter!),
  if (state.blendParameterY != null)
    'blendParameterY': StringValue(state.blendParameterY!),
  if (state.stops.isNotEmpty)
    'stops': ListValue([
      for (final stop in state.stops) _writeStop(stop, is2D: state.is2D),
    ]),
  'loop': BoolValue(state.loop),
  'speed': DoubleValue(state.speed),
  'position': Vec2Value(Vector2(state.position.dx, state.position.dy)),
});

PropertyValue _writeCondition(AnimatorConditionEdit condition) => MapValue({
  'parameter': StringValue(condition.parameter),
  'comparison': StringValue(condition.comparison),
  if (comparisonUsesThreshold(condition.comparison))
    'threshold': DoubleValue(condition.threshold),
});

PropertyValue _writeTransition(AnimatorTransitionEdge transition) => MapValue({
  if (!transition.fromAny) 'from': StringValue(transition.from!),
  'to': StringValue(transition.to),
  'duration': DoubleValue(transition.duration),
  if (transition.conditions.isNotEmpty)
    'conditions': ListValue([
      for (final condition in transition.conditions) _writeCondition(condition),
    ]),
});

PropertyValue _writeLayer(AnimatorLayerGraph layer) => MapValue({
  'name': StringValue(layer.name),
  if (layer.initial.isNotEmpty) 'initial': StringValue(layer.initial),
  'weight': DoubleValue(layer.weight),
  if (layer.mask != null) 'mask': layer.mask!,
  'states': ListValue([for (final state in layer.states) _writeState(state)]),
  'transitions': ListValue([
    for (final transition in layer.transitions) _writeTransition(transition),
  ]),
});

/// The properties to set on the component for [graph].
///
/// A flat machine is written flat and a layered one as layers, so an edit to
/// one is an edit rather than a reshaping of the whole component. A flat
/// machine that has grown a second layer is written as layers, because at
/// that point it genuinely is one.
Map<String, PropertyValue> writeAnimatorGraph(AnimatorGraph graph) {
  if (graph.layered || graph.layers.length > 1) {
    return {
      'layers': ListValue([
        for (final layer in graph.layers) _writeLayer(layer),
      ]),
      // The flat keys are cleared, or a reader that prefers them would go on
      // seeing the machine as it was before the second layer.
      'states': ListValue(const []),
      'transitions': ListValue(const []),
      'initial': StringValue(''),
    };
  }
  final layer = graph.layers.single;
  return {
    'initial': StringValue(layer.initial),
    'states': ListValue([for (final state in layer.states) _writeState(state)]),
    'transitions': ListValue([
      for (final transition in layer.transitions) _writeTransition(transition),
    ]),
    'layers': ListValue(const []),
  };
}

/// A name like [wanted] that no state in [layer] already has.
String uniqueStateName(AnimatorLayerGraph layer, String wanted) {
  final taken = {for (final state in layer.states) state.name};
  if (!taken.contains(wanted)) return wanted;
  for (var i = 2; ; i++) {
    final candidate = '$wanted $i';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Renames [from] to [to] across the layer, arrows included.
///
/// A transition names its endpoints by string, so a rename that touched only
/// the state would leave every arrow into it pointing at a state that no
/// longer exists — and the machine would still load, silently missing them.
AnimatorLayerGraph renameState(
  AnimatorLayerGraph layer,
  String from,
  String to,
) => layer.copyWith(
  initial: layer.initial == from ? to : layer.initial,
  states: [
    for (final state in layer.states)
      state.name == from ? state.copyWith(name: to) : state,
  ],
  transitions: [
    for (final transition in layer.transitions)
      transition.copyWith(
        from: transition.from == from ? to : transition.from,
        to: transition.to == from ? to : transition.to,
      ),
  ],
);

/// Removes [name] and every arrow touching it.
AnimatorLayerGraph removeState(AnimatorLayerGraph layer, String name) {
  final states = [
    for (final state in layer.states)
      if (state.name != name) state,
  ];
  return layer.copyWith(
    states: states,
    initial: layer.initial == name
        ? (states.isEmpty ? '' : states.first.name)
        : layer.initial,
    transitions: [
      for (final transition in layer.transitions)
        if (transition.from != name && transition.to != name) transition,
    ],
  );
}
