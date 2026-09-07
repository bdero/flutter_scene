/// A state machine over animation clips: what plays, when it changes, and how
/// the change is blended.
///
/// Clips already know how to be mixed — [AnimationClip.weight] blends them and
/// the player normalizes the set. What was missing is the part that *decides*
/// the weights, which is what this is.
///
/// The decision is deliberately pure: [Animator.evaluate] takes the time that
/// passed and returns a clip name to weight map, touching no clips itself.
/// That keeps the interesting logic — transitions, blend trees, cross-fades —
/// testable without a GPU, and lets the same machine drive something other
/// than an [AnimationPlayer] if it ever needs to.
library;

import 'dart:math' as math;

import 'package:flutter_scene/src/animation.dart' show AnimationMask;

/// The named values a machine's transitions read.
///
/// Numbers and flags hold until changed. A trigger is consumed by the first
/// transition that reads it, which is what makes "jump" fire once rather than
/// for every frame the button is held.
/// {@category Animation}
class AnimatorParameters {
  final Map<String, double> _numbers = {};
  final Map<String, bool> _flags = {};
  final Set<String> _triggers = {};

  /// Reads number [name], zero when unset.
  double number(String name) => _numbers[name] ?? 0.0;

  /// Sets number [name].
  void setNumber(String name, double value) => _numbers[name] = value;

  /// Reads flag [name], false when unset.
  bool flag(String name) => _flags[name] ?? false;

  /// Sets flag [name].
  void setFlag(String name, {required bool value}) => _flags[name] = value;

  /// Raises trigger [name] until something consumes it.
  void trigger(String name) => _triggers.add(name);

  /// Whether trigger [name] is currently raised, without consuming it.
  bool isTriggered(String name) => _triggers.contains(name);

  /// Consumes trigger [name], reporting whether it was raised.
  bool consumeTrigger(String name) => _triggers.remove(name);

  /// Drops every raised trigger, for a hard reset.
  void clearTriggers() => _triggers.clear();
}

/// How a condition compares its parameter.
/// {@category Animation}
enum AnimatorComparison {
  /// The number is greater than the threshold.
  greater,

  /// The number is less than the threshold.
  less,

  /// The flag is true.
  isTrue,

  /// The flag is false.
  isFalse,

  /// The trigger is raised; taking the transition consumes it.
  triggered,
}

/// One test a transition must pass.
/// {@category Animation}
class AnimatorCondition {
  /// Creates a condition on [parameter].
  const AnimatorCondition(
    this.parameter,
    this.comparison, {
    this.threshold = 0.0,
  });

  /// The parameter read.
  final String parameter;

  /// How it is compared.
  final AnimatorComparison comparison;

  /// The value compared against, for [AnimatorComparison.greater] and
  /// [AnimatorComparison.less].
  final double threshold;

  /// Whether this holds, without consuming anything.
  bool holds(AnimatorParameters parameters) => switch (comparison) {
    AnimatorComparison.greater => parameters.number(parameter) > threshold,
    AnimatorComparison.less => parameters.number(parameter) < threshold,
    AnimatorComparison.isTrue => parameters.flag(parameter),
    AnimatorComparison.isFalse => !parameters.flag(parameter),
    AnimatorComparison.triggered => parameters.isTriggered(parameter),
  };
}

/// What a state plays: one clip, or a blend across several.
/// {@category Animation}
sealed class AnimatorMotion {
  const AnimatorMotion();

  /// The weights this motion wants, by clip name, given [parameters].
  Map<String, double> weights(AnimatorParameters parameters);
}

/// A state that plays a single clip.
/// {@category Animation}
class ClipMotion extends AnimatorMotion {
  /// Plays [clip] at full weight.
  const ClipMotion(this.clip);

  /// The clip's name, as the player knows it.
  final String clip;

  @override
  Map<String, double> weights(AnimatorParameters parameters) => {clip: 1.0};
}

/// One stop in a [BlendMotion]: a clip pinned to a parameter value.
/// {@category Animation}
typedef BlendStop = ({double at, String clip});

/// A one-dimensional blend: clips placed along a parameter, mixed by where
/// the parameter currently sits.
///
/// The usual locomotion tree — idle at 0, walk at 2, run at 6 — where the
/// character's speed drives the mix and never lands on a hard cut.
/// {@category Animation}
class BlendMotion extends AnimatorMotion {
  /// Blends [stops] along [parameter]. Stops are sorted on construction, so
  /// they may be given in any order.
  BlendMotion(this.parameter, List<BlendStop> stops)
    : assert(stops.isNotEmpty, 'A blend needs at least one stop.'),
      stops = List<BlendStop>.unmodifiable(
        [...stops]..sort((a, b) => a.at.compareTo(b.at)),
      );

  /// The parameter driving the blend.
  final String parameter;

  /// The stops, in ascending order.
  final List<BlendStop> stops;

  @override
  Map<String, double> weights(AnimatorParameters parameters) {
    final value = parameters.number(parameter);
    // Outside the ends, the nearest stop holds at full weight rather than
    // extrapolating into a clip that was never authored for that speed.
    if (value <= stops.first.at) return {stops.first.clip: 1.0};
    if (value >= stops.last.at) return {stops.last.clip: 1.0};
    for (var i = 0; i < stops.length - 1; i++) {
      final low = stops[i];
      final high = stops[i + 1];
      if (value < low.at || value > high.at) continue;
      final span = high.at - low.at;
      // Two stops at the same value would divide by zero; the lower wins.
      if (span <= 0) return {low.clip: 1.0};
      final t = (value - low.at) / span;
      if (low.clip == high.clip) return {low.clip: 1.0};
      return {low.clip: 1.0 - t, high.clip: t};
    }
    return {stops.last.clip: 1.0};
  }
}

/// One stop in a [BlendMotion2D]: a clip pinned to a point on the plane.
/// {@category Animation}
typedef BlendStop2D = ({double x, double y, String clip});

/// A two-dimensional blend: clips placed on a plane, mixed by where a pair of
/// parameters currently sits.
///
/// The directional locomotion case — forward, back and both strafes around an
/// idle — where neither axis alone describes the motion.
///
/// Weights come from gradient band interpolation. For each stop, every other
/// stop defines a band: how far the sample has travelled from this stop
/// toward that one. The stop's weight is how much band is left after the
/// most restrictive of them. The result is one at a stop, smooth between
/// them, and it needs no triangulation of the stops, which matters because
/// nobody wants to author a mesh to describe four directions.
/// {@category Animation}
class BlendMotion2D extends AnimatorMotion {
  /// Blends [stops] across [parameterX] and [parameterY].
  BlendMotion2D(this.parameterX, this.parameterY, List<BlendStop2D> stops)
    : assert(stops.isNotEmpty, 'A blend needs at least one stop.'),
      stops = List<BlendStop2D>.unmodifiable(stops);

  /// The parameter driving the horizontal axis.
  final String parameterX;

  /// The parameter driving the vertical axis.
  final String parameterY;

  /// The stops, in the order given.
  final List<BlendStop2D> stops;

  @override
  Map<String, double> weights(AnimatorParameters parameters) {
    if (stops.length == 1) return {stops.first.clip: 1.0};
    final px = parameters.number(parameterX);
    final py = parameters.number(parameterY);

    final raw = <double>[];
    for (final stop in stops) {
      var weight = 1.0;
      for (final other in stops) {
        if (identical(other, stop)) continue;
        final dx = other.x - stop.x;
        final dy = other.y - stop.y;
        final lengthSq = dx * dx + dy * dy;
        // Two stops in the same place cannot define a direction; neither
        // constrains the other.
        if (lengthSq <= 0) continue;
        final toSampleX = px - stop.x;
        final toSampleY = py - stop.y;
        final along = (toSampleX * dx + toSampleY * dy) / lengthSq;
        final remaining = 1.0 - along;
        if (remaining < weight) weight = remaining;
      }
      raw.add(weight < 0 ? 0.0 : weight);
    }

    var total = 0.0;
    for (final weight in raw) {
      total += weight;
    }
    // Every band closed: the sample sits outside every stop's influence, so
    // fall back to the nearest rather than returning nothing at all.
    if (total <= 0) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < stops.length; i++) {
        final dx = px - stops[i].x;
        final dy = py - stops[i].y;
        final distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          bestDistance = distance;
          best = i;
        }
      }
      return {stops[best].clip: 1.0};
    }

    final merged = <String, double>{};
    for (var i = 0; i < stops.length; i++) {
      if (raw[i] <= 0) continue;
      merged[stops[i].clip] = (merged[stops[i].clip] ?? 0.0) + raw[i] / total;
    }
    return merged;
  }
}

/// One state of an [Animator].
/// {@category Animation}
class AnimatorState {
  /// Creates a state named [name] playing [motion].
  const AnimatorState(
    this.name,
    this.motion, {
    this.loop = true,
    this.speed = 1.0,
  });

  /// The state's name, used by transitions.
  final String name;

  /// What it plays.
  final AnimatorMotion motion;

  /// Whether its clips loop.
  final bool loop;

  /// Playback rate applied to its clips.
  final double speed;
}

/// A move from one state to another when its conditions hold.
/// {@category Animation}
class AnimatorTransition {
  /// Creates a transition. A null [from] means "from any state", which is how
  /// a hit reaction or a death interrupts whatever is playing.
  const AnimatorTransition({
    required this.to,
    this.from,
    this.conditions = const [],
    this.duration = 0.2,
  });

  /// The state moved to.
  final String to;

  /// The state moved from, or null for any.
  final String? from;

  /// Every condition must hold. An empty list holds immediately, which makes
  /// an unconditional transition out of an intro state.
  final List<AnimatorCondition> conditions;

  /// Cross-fade length in seconds. Zero is a cut.
  final double duration;

  /// Whether this applies while [state] is current and its conditions hold.
  bool matches(String state, AnimatorParameters parameters) {
    if (from != null && from != state) return false;
    if (to == state) return false;
    for (final condition in conditions) {
      if (!condition.holds(parameters)) return false;
    }
    return true;
  }
}

/// One machine in an [Animator]: a set of states, the transitions between
/// them, and how much of the skeleton it is allowed to move.
///
/// Layers are what let a character do two things at once. A base layer runs
/// the legs; an upper-body layer masked to the spine plays an aim or a reload
/// over the top, at its own weight, driven by its own transitions. Without
/// them every combination has to be authored as its own clip, which is how a
/// four-state character becomes a sixteen-clip export.
/// {@category Animation}
class AnimatorLayer {
  /// Creates a layer named [name] over [states], starting in [initial] (the
  /// first state when omitted).
  AnimatorLayer({
    required this.name,
    required List<AnimatorState> states,
    List<AnimatorTransition> transitions = const [],
    String? initial,
    this.weight = 1.0,
    this.mask,
  }) : assert(states.isNotEmpty, 'A layer needs at least one state.'),
       _states = {for (final state in states) state.name: state},
       transitions = List<AnimatorTransition>.unmodifiable(transitions) {
    initialState = initial != null && _states.containsKey(initial)
        ? initial
        : states.first.name;
    _current = initialState;
  }

  /// The layer's name. Also how its clips are told apart from another
  /// layer's, so two layers can play the same animation at once.
  final String name;

  final Map<String, AnimatorState> _states;

  /// The transitions, in the order they are tried.
  final List<AnimatorTransition> transitions;

  /// The state this layer started in.
  ///
  /// Retained separately from [current], which moves: writing a machine back
  /// out has to record where it begins, not where it happens to be.
  late final String initialState;

  /// How strongly this layer contributes, `0` to `1`.
  ///
  /// A layer at zero is skipped entirely rather than applied at no weight,
  /// so a reload layer costs nothing on the frames nobody is reloading.
  double weight;

  /// Which nodes this layer may move, or null for all of them.
  AnimationMask? mask;

  late String _current;
  String? _previous;
  double _blend = 0.0;
  double _blendDuration = 0.0;

  /// The state being played, or blended toward while [isBlending].
  String get current => _current;

  /// The state being blended away from, or null when settled.
  String? get previous => _previous;

  /// Whether a cross-fade is running.
  bool get isBlending => _previous != null;

  /// How far through the cross-fade, `0` to `1`; one when settled.
  double get blendProgress =>
      _blendDuration <= 0 ? 1.0 : (_blend / _blendDuration).clamp(0.0, 1.0);

  /// Every state, by name.
  Iterable<AnimatorState> get states => _states.values;

  /// The state named [name], or null.
  AnimatorState? state(String name) => _states[name];

  /// Jumps straight to [state], with no blend. Unknown names are ignored.
  void play(String state) {
    if (!_states.containsKey(state)) return;
    _current = state;
    _previous = null;
    _blend = 0.0;
    _blendDuration = 0.0;
  }

  /// Starts a cross-fade to [state] over [duration] seconds.
  ///
  /// Interrupting a fade blends from where it currently *is* rather than from
  /// the state it was leaving, so a change of mind mid-transition does not
  /// snap backwards.
  void crossFade(String state, double duration) {
    if (!_states.containsKey(state) || state == _current) return;
    if (duration <= 0) {
      play(state);
      return;
    }
    _previous = _current;
    _current = state;
    _blend = 0.0;
    _blendDuration = duration;
  }

  /// Advances this layer by [deltaSeconds] and returns the weight of every
  /// clip it wants, by name, summing to one.
  Map<String, double> evaluate(
    double deltaSeconds,
    AnimatorParameters parameters,
  ) {
    _takeTransition(parameters);

    if (_previous != null) {
      _blend += math.max(deltaSeconds, 0.0);
      if (_blend >= _blendDuration) {
        _previous = null;
        _blend = 0.0;
        _blendDuration = 0.0;
      }
    }

    final target = _states[_current]!.motion.weights(parameters);
    final from = _previous;
    if (from == null) return _normalized(target);

    final t = blendProgress;
    final outgoing = _states[from]!.motion.weights(parameters);
    final mixed = <String, double>{};
    for (final entry in outgoing.entries) {
      mixed[entry.key] = entry.value * (1 - t);
    }
    for (final entry in target.entries) {
      mixed[entry.key] = (mixed[entry.key] ?? 0.0) + entry.value * t;
    }
    return _normalized(mixed);
  }

  /// Takes the first transition whose conditions hold, consuming the triggers
  /// it read. First rather than best: the order they were declared in is the
  /// priority, which is easier to reason about than a scoring rule.
  void _takeTransition(AnimatorParameters parameters) {
    for (final transition in transitions) {
      if (!_states.containsKey(transition.to)) continue;
      if (!transition.matches(_current, parameters)) continue;
      for (final condition in transition.conditions) {
        if (condition.comparison == AnimatorComparison.triggered) {
          parameters.consumeTrigger(condition.parameter);
        }
      }
      crossFade(transition.to, transition.duration);
      return;
    }
  }

  static Map<String, double> _normalized(Map<String, double> weights) {
    var total = 0.0;
    for (final weight in weights.values) {
      total += weight;
    }
    if (total <= 0) return weights;
    return {
      for (final entry in weights.entries)
        if (entry.value > 0) entry.key: entry.value / total,
    };
  }
}

/// A clip state machine: one or more layers of states, the transitions
/// between them, and the cross-fades in progress.
///
/// Drive it by setting [parameters] and calling [evaluate] once a frame. It
/// returns the weight every clip should have; applying them is the caller's
/// job (see `AnimatorComponent`).
///
/// The single-layer spelling is the common one and stays the short one: pass
/// states and transitions straight to the constructor and the machine reads
/// exactly as it did before layers existed. Pass [layers] when a character
/// has to do two things at once.
/// {@category Animation}
class Animator {
  /// Creates a machine over [states], starting in [initial] (the first state
  /// when omitted).
  Animator({
    required List<AnimatorState> states,
    List<AnimatorTransition> transitions = const [],
    String? initial,
  }) : layers = List<AnimatorLayer>.unmodifiable([
         AnimatorLayer(
           name: defaultLayerName,
           states: states,
           transitions: transitions,
           initial: initial,
         ),
       ]);

  /// Creates a machine over [layers], base layer first.
  ///
  /// Order is priority: a later layer is applied over an earlier one on the
  /// nodes its mask covers.
  Animator.layered(List<AnimatorLayer> layers)
    : assert(layers.isNotEmpty, 'An animator needs at least one layer.'),
      layers = List<AnimatorLayer>.unmodifiable(layers);

  /// The name the single-layer constructor gives its one layer.
  static const String defaultLayerName = 'base';

  /// The layers, base first.
  final List<AnimatorLayer> layers;

  /// The parameters transitions read, shared by every layer. Set these from
  /// gameplay.
  ///
  /// Shared rather than per layer because the things a machine reacts to --
  /// speed, grounded, a fire trigger -- are facts about the character, not
  /// about one of its halves.
  final AnimatorParameters parameters = AnimatorParameters();

  /// The base layer, which is the only one for a machine built the short way.
  AnimatorLayer get base => layers.first;

  /// The layer named [name], or null.
  AnimatorLayer? layer(String name) {
    for (final layer in layers) {
      if (layer.name == name) return layer;
    }
    return null;
  }

  /// The base layer's current state.
  String get current => base.current;

  /// The base layer's outgoing state, or null when settled.
  String? get previous => base.previous;

  /// Whether the base layer is cross-fading.
  bool get isBlending => base.isBlending;

  /// How far through the base layer's cross-fade.
  double get blendProgress => base.blendProgress;

  /// The base layer's starting state.
  String get initialState => base.initialState;

  /// The base layer's transitions.
  List<AnimatorTransition> get transitions => base.transitions;

  /// Every state on the base layer.
  Iterable<AnimatorState> get states => base.states;

  /// Jumps the base layer straight to [state].
  void play(String state) => base.play(state);

  /// Cross-fades the base layer to [state] over [duration] seconds.
  void crossFade(String state, double duration) =>
      base.crossFade(state, duration);

  /// Advances every layer by [deltaSeconds] and returns what each wants
  /// played, in layer order.
  ///
  /// A layer at zero weight is skipped, so it costs nothing on the frames it
  /// is silent -- but its transitions still run, or a reload layer faded out
  /// mid-reload would come back where it left off.
  List<AnimatorLayerWeights> evaluateLayers(double deltaSeconds) {
    final out = <AnimatorLayerWeights>[];
    for (final layer in layers) {
      final weights = layer.evaluate(deltaSeconds, parameters);
      out.add(
        AnimatorLayerWeights(
          layer: layer,
          weights: layer.weight <= 0 ? const {} : weights,
        ),
      );
    }
    return out;
  }

  /// Advances the machine and returns the base layer's clip weights.
  ///
  /// The single-layer answer, kept because it is what most machines want and
  /// what every machine wanted before layers. A layered machine wants
  /// [evaluateLayers], which can say which layer asked for what.
  Map<String, double> evaluate(double deltaSeconds) {
    final all = evaluateLayers(deltaSeconds);
    return all.first.weights;
  }
}

/// What one layer wants played this frame.
/// {@category Animation}
class AnimatorLayerWeights {
  const AnimatorLayerWeights({required this.layer, required this.weights});

  /// The layer that asked.
  final AnimatorLayer layer;

  /// Clip weights within the layer, summing to one. Empty when the layer is
  /// silent.
  final Map<String, double> weights;
}
