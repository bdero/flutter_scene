import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where the roll's score choreography is.
enum CelebrationPhase { idle, counting, multiplier, slam, afterglow }

/// What the celebration wants the host to do at this instant.
sealed class CelebrationEvent {
  const CelebrationEvent();
}

/// Die [index] (in counting order) just counted; light it up.
class DieCounted extends CelebrationEvent {
  const DieCounted(this.index, this.face, this.ordinal);

  final int index;
  final int face;

  /// 0 for the first die counted, 1 for the second, and so on.
  final int ordinal;
}

/// The matched dice were revealed with their multiplier.
class MultiplierRevealed extends CelebrationEvent {
  const MultiplierRevealed(this.multiplier, this.matchedIndices);

  final int multiplier;
  final List<int> matchedIndices;
}

/// The running number left the middle of the screen for the total.
class SlamLaunched extends CelebrationEvent {
  const SlamLaunched();
}

/// The running number hit the total.
class SlamLanded extends CelebrationEvent {
  const SlamLanded(this.scored, this.total);

  final int scored;
  final int total;
}

/// The choreography ended; highlights can come down.
class CelebrationEnded extends CelebrationEvent {
  const CelebrationEnded();
}

/// Everything the widgets need to draw one frame of the celebration.
@immutable
class CelebrationFrame {
  const CelebrationFrame({
    this.phase = CelebrationPhase.idle,
    this.counter = 0,
    this.punch = 0.0,
    this.multiplier = 1,
    this.multiplierReveal = 0.0,
    this.slam = 0.0,
    this.total = 0,
    this.totalPunch = 0.0,
    this.counterAlpha = 0.0,
  });

  final CelebrationPhase phase;

  /// The number in the middle of the screen.
  final int counter;

  /// 1 the instant the counter changes, decaying to 0.
  final double punch;

  /// 1 when the roll had no matches.
  final int multiplier;

  /// 0..1 scale-in of the multiplier badge.
  final double multiplierReveal;

  /// 0..1 flight of the counter toward the total.
  final double slam;

  /// The total as displayed (it rolls up after the slam lands).
  final int total;

  /// 1 when the slam lands, decaying to 0.
  final double totalPunch;

  /// Visibility of the counter, 0 while idle.
  final double counterAlpha;

  bool get idle => phase == CelebrationPhase.idle;

  String get multiplierLabel => switch (multiplier) {
    2 => 'DOUBLES',
    3 => 'TRIPLES',
    4 => 'QUADS',
    5 => 'FIVE OF A KIND',
    6 => 'SIX OF A KIND',
    _ => '',
  };
}

/// Scores a settled roll over time. Dice count up one by one, a matched set
/// multiplies the sum, and the running number slams into the total.
///
/// Drive it with [advance] every tick and act on the events it hands back.
/// Pure timing, no widgets or scene access, so it is testable headlessly.
class Celebration {
  Celebration({
    required List<int> faces,
    required List<int> order,
    required int total,
    required this.frame,
  }) : _faces = faces,
       _order = order,
       _startTotal = total,
       multiplier = multiplierOf(faces),
       matched = matchedIndices(faces) {
    _sum = faces.fold(0, (a, b) => a + b);
    _scored = _sum * multiplier;
    _plan();
  }

  final List<int> _faces;

  /// Die indices in the order they count.
  final List<int> _order;
  final int _startTotal;
  final int multiplier;
  final List<int> matched;
  late final int _sum;
  late final int _scored;

  /// What was added to the total.
  int get scored => _scored;

  int get endTotal => _startTotal + _scored;

  /// The frame the widgets read, owned by the host so it outlives one roll.
  final ValueNotifier<CelebrationFrame> frame;

  double _time = 0.0;
  bool _finished = false;

  // Event timestamps.
  late final List<double> _tickTimes;
  late final double _multiplierAt;
  late final double _multiplierRollStart;
  late final double _slamAt;
  late final double _landAt;
  late final double _endAt;

  int _ticked = 0;
  bool _multiplierSent = false;
  bool _slamSent = false;
  bool _landSent = false;
  double _lastPunchAt = -1.0;

  static const double _pause = 0.3;
  static const double _tickGap = 0.26;
  static const double _holdAfterTicks = 0.5;
  static const double _multiplierReveal = 0.75;
  static const double _holdAfterMultiplier = 0.45;
  static const double _flight = 0.36;
  static const double _afterglow = 1.4;

  void _plan() {
    var t = _pause;
    _tickTimes = [];
    for (var i = 0; i < _order.length; i++) {
      _tickTimes.add(t);
      // Each tick lands a little sooner than the last.
      t += _tickGap * math.pow(0.92, i);
    }
    t += _holdAfterTicks;
    _multiplierAt = t;
    if (multiplier > 1) {
      _multiplierRollStart = t + 0.18;
      t += _multiplierReveal + _holdAfterMultiplier;
    } else {
      _multiplierRollStart = t;
    }
    _slamAt = t;
    _landAt = t + _flight;
    _endAt = _landAt + _afterglow;
  }

  /// Advances [dt] seconds and returns the events that fired.
  List<CelebrationEvent> advance(double dt) {
    if (_finished) return const [];
    _time += dt;
    final events = <CelebrationEvent>[];

    while (_ticked < _tickTimes.length && _time >= _tickTimes[_ticked]) {
      final index = _order[_ticked];
      events.add(DieCounted(index, _faces[index], _ticked));
      _lastPunchAt = _tickTimes[_ticked];
      _ticked++;
    }
    if (multiplier > 1 && !_multiplierSent && _time >= _multiplierAt) {
      _multiplierSent = true;
      _lastPunchAt = _multiplierAt;
      events.add(MultiplierRevealed(multiplier, matched));
    }
    if (!_slamSent && _time >= _slamAt) {
      _slamSent = true;
      events.add(const SlamLaunched());
    }
    if (!_landSent && _time >= _landAt) {
      _landSent = true;
      events.add(SlamLanded(_scored, endTotal));
    }
    if (_time >= _endAt) {
      _finished = true;
      events.add(const CelebrationEnded());
    }
    frame.value = _frameAt(_time);
    return events;
  }

  CelebrationFrame _frameAt(double t) {
    if (_finished) {
      return CelebrationFrame(total: endTotal);
    }
    final counted = _order
        .take(_ticked)
        .fold(0, (a, index) => a + _faces[index]);
    var counter = counted;
    var reveal = 0.0;
    if (multiplier > 1 && t >= _multiplierAt) {
      reveal = _ease((t - _multiplierAt) / 0.3);
      final roll = _ease((t - _multiplierRollStart) / 0.45);
      counter = (counted + (counted * multiplier - counted) * roll).round();
    }
    final punchAge = t - _lastPunchAt;
    final punch = _lastPunchAt < 0 || punchAge < 0
        ? 0.0
        : math.exp(-punchAge * 9.0);

    final phase = t < _multiplierAt
        ? CelebrationPhase.counting
        : t < _slamAt
        ? CelebrationPhase.multiplier
        : t < _landAt
        ? CelebrationPhase.slam
        : CelebrationPhase.afterglow;

    var slam = 0.0;
    var total = _startTotal;
    var totalPunch = 0.0;
    var alpha = _ease(t / 0.18);
    if (t >= _slamAt) {
      slam = ((t - _slamAt) / _flight).clamp(0.0, 1.0);
      // Ease in, so it winds up before it leaves.
      slam = slam * slam * slam;
    }
    if (t >= _landAt) {
      final since = t - _landAt;
      total = _startTotal + (_scored * _ease(since / 0.55)).round();
      totalPunch = math.exp(-since * 5.0);
      alpha = 0.0;
      counter = _scored;
    }
    return CelebrationFrame(
      phase: phase,
      counter: counter,
      punch: punch,
      multiplier: multiplier,
      multiplierReveal: reveal,
      slam: slam,
      total: total,
      totalPunch: totalPunch,
      counterAlpha: alpha,
    );
  }

  static double _ease(double x) {
    final t = x.clamp(0.0, 1.0);
    return 1 - math.pow(1 - t, 3).toDouble();
  }

  /// The size of the largest matched set, 1 when every face differs.
  static int multiplierOf(List<int> faces) {
    var best = 1;
    for (final face in faces.toSet()) {
      final count = faces.where((f) => f == face).length;
      if (count > best) best = count;
    }
    return best;
  }

  /// The indices of the dice in the largest matched set (the lowest face on
  /// a tie), or empty when nothing matched.
  static List<int> matchedIndices(List<int> faces) {
    final best = multiplierOf(faces);
    if (best < 2) return const [];
    final candidates = faces.toSet().where(
      (face) => faces.where((f) => f == face).length == best,
    );
    final face = candidates.reduce(math.min);
    return [
      for (var i = 0; i < faces.length; i++)
        if (faces[i] == face) i,
    ];
  }
}

/// The running number in the middle of the screen, its multiplier badge,
/// and its flight into the total. Positioned by the parent; [flightOffset]
/// is where the total sits relative to the counter's resting spot.
class RollCounter extends StatelessWidget {
  const RollCounter({
    super.key,
    required this.frame,
    required this.flightOffset,
    required this.accent,
  });

  final ValueListenable<CelebrationFrame> frame;
  final Offset flightOffset;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CelebrationFrame>(
      valueListenable: frame,
      builder: (context, f, _) {
        if (f.counterAlpha <= 0.001) return const SizedBox.shrink();
        final scale = (1.0 + 0.32 * f.punch) * (1.0 - 0.55 * f.slam);
        final offset = flightOffset * f.slam;
        final glow = (0.35 + 0.65 * f.punch) * f.counterAlpha;
        final badge = f.multiplierReveal;
        final revealed = f.multiplier > 1 && badge > 0;
        return IgnorePointer(
          child: Opacity(
            opacity: f.counterAlpha,
            child: Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${f.counter}',
                      style: TextStyle(
                        fontSize: 132,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        color: Color.lerp(accent, Colors.white, 0.2 * f.punch),
                        letterSpacing: -4,
                        shadows: [
                          Shadow(
                            color: accent.withValues(alpha: glow),
                            blurRadius: 34 + 40 * f.punch,
                          ),
                          const Shadow(
                            color: Color(0x33000000),
                            blurRadius: 6,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    if (revealed)
                      Transform.scale(
                        scale: 0.4 + 0.6 * badge + 0.25 * f.punch * badge,
                        child: Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.55 * badge),
                                blurRadius: 24,
                              ),
                            ],
                          ),
                          child: Text(
                            '${f.multiplierLabel}  x${f.multiplier}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The score total. It kicks and flashes when a slam lands.
class ScoreBanner extends StatelessWidget {
  const ScoreBanner({super.key, required this.frame, required this.accent});

  final ValueListenable<CelebrationFrame> frame;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CelebrationFrame>(
      valueListenable: frame,
      builder: (context, f, _) {
        final kick = f.totalPunch;
        // A quick shake that dies with the punch.
        final shake = Offset(
          math.sin(kick * 40) * 6 * kick,
          math.cos(kick * 31) * 3 * kick,
        );
        return Transform.translate(
          offset: shake,
          child: Transform.scale(
            scale: 1.0 + 0.28 * kick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: Color.lerp(Colors.white, accent, 0.85 * kick),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.7 * kick),
                    blurRadius: 40 * kick + 8,
                    spreadRadius: 6 * kick,
                  ),
                  const BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: Color.lerp(Colors.black45, Colors.white, kick),
                    ),
                  ),
                  Text(
                    _grouped(f.total),
                    style: TextStyle(
                      fontSize: 44,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      color: Color.lerp(accent, Colors.white, kick),
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _grouped(int value) {
    final digits = value.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
