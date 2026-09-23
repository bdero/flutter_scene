import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'pop_theme.dart';

/// Where a card is in its break.
enum BreakPhase { cracked, shattered, reassembling }

/// One card's break, as the widgets draw it.
@immutable
class CardBreak {
  const CardBreak({
    required this.phase,
    required this.hit,
    required this.progress,
    required this.seed,
  });

  final BreakPhase phase;

  /// Where the die struck, as a fraction of the card's size.
  final Offset hit;

  /// 0..1 through the current phase.
  final double progress;

  final int seed;
}

/// The state of every breakable card, keyed by card index. The host drives
/// it; the screen's cards paint from it and register themselves so the host
/// can capture their pixels for the shards.
class CardBreakController extends ChangeNotifier {
  final Map<int, CardBreak> _breaks = {};
  final Map<int, GlobalKey> _keys = {};

  CardBreak? operator [](int index) => _breaks[index];

  bool get anyBroken => _breaks.isNotEmpty;

  void register(int index, GlobalKey key) => _keys[index] = key;

  void set(int index, CardBreak? value) {
    if (value == null) {
      if (_breaks.remove(index) == null) return;
    } else {
      _breaks[index] = value;
    }
    notifyListeners();
  }

  /// Captures the card's pixels, for texturing its shards.
  Future<ui.Image?> capture(int index, double pixelRatio) async {
    final box =
        _keys[index]?.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (box == null || !box.attached || box.debugNeedsPaint) return null;
    return box.toImage(pixelRatio: pixelRatio);
  }
}

/// Paints a card's crack, then its empty socket, over [child]. Registers
/// the card with [controller] so its pixels can be captured.
class Breakable extends StatelessWidget {
  const Breakable({
    super.key,
    required this.index,
    required this.controller,
    required this.captureKey,
    required this.child,
  });

  final int index;
  final CardBreakController controller;

  /// A repaint boundary around the card, for the capture.
  final GlobalKey captureKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    controller.register(index, captureKey);
    final theme = ScreenTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller[index];
        final card = RepaintBoundary(key: captureKey, child: child);
        if (state == null) return card;
        switch (state.phase) {
          case BreakPhase.cracked:
            return Stack(
              children: [
                card,
                Positioned.fill(
                  child: CustomPaint(painter: _CrackPainter(state, theme)),
                ),
              ],
            );
          case BreakPhase.shattered:
            // The socket the card left behind: its outline over a dark hole.
            // The card itself stays in the tree, unseen, so the capture and
            // the layout survive.
            return Stack(
              children: [
                Opacity(opacity: 0.0, child: card),
                Positioned.fill(
                  child: CustomPaint(painter: _HolePainter(theme)),
                ),
              ],
            );
          case BreakPhase.reassembling:
            final t = Curves.elasticOut.transform(state.progress);
            return Stack(
              children: [
                Positioned.fill(
                  child: Opacity(
                    opacity: (1 - state.progress * 3).clamp(0.0, 1.0),
                    child: CustomPaint(painter: _HolePainter(theme)),
                  ),
                ),
                Transform.scale(
                  scale: 0.2 + 0.8 * t,
                  alignment: state.hit.dx.isNaN
                      ? Alignment.center
                      : Alignment(state.hit.dx * 2 - 1, state.hit.dy * 2 - 1),
                  child: card,
                ),
              ],
            );
        }
      },
    );
  }
}

/// Radial fractures from the hit point with concentric rings, thickening
/// as the crack spreads.
class _CrackPainter extends CustomPainter {
  const _CrackPainter(this.state, this.theme);

  final CardBreak state;
  final ScreenTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(state.seed);
    final origin = Offset(
      state.hit.dx * size.width,
      state.hit.dy * size.height,
    );
    final spread = Curves.easeOutQuart.transform(state.progress);
    final reach = math.max(size.width, size.height) * (0.25 + 0.95 * spread);
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = theme.ink;
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..color = theme.cream.withValues(alpha: 0.7);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(theme.radius),
      ),
    );
    // Radial cracks, each a jittered polyline.
    const rays = 11;
    for (var i = 0; i < rays; i++) {
      final angle = i * math.pi * 2 / rays + random.nextDouble() * 0.5;
      final length = reach * (0.55 + random.nextDouble() * 0.6);
      final path = Path()..moveTo(origin.dx, origin.dy);
      var p = origin;
      final steps = 5;
      for (var s = 1; s <= steps; s++) {
        final along = length * s / steps;
        final wobble = (random.nextDouble() - 0.5) * along * 0.35;
        p =
            origin +
            Offset(math.cos(angle), math.sin(angle)) * along +
            Offset(-math.sin(angle), math.cos(angle)) * wobble;
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, light..strokeWidth = 4.5);
      canvas.drawPath(path, ink..strokeWidth = 1.6 + 1.2 * spread);
    }
    // Rings, broken into arcs.
    for (var r = reach * 0.22; r < reach; r += reach * 0.26) {
      var a = random.nextDouble() * math.pi * 2;
      while (a < math.pi * 2 + 1) {
        final sweep = 0.5 + random.nextDouble() * 1.1;
        final rect = Rect.fromCircle(center: origin, radius: r);
        canvas.drawArc(rect, a, sweep, false, light..strokeWidth = 3.5);
        canvas.drawArc(rect, a, sweep, false, ink..strokeWidth = 1.2);
        a += sweep + 0.3 + random.nextDouble() * 0.6;
      }
    }
    // The impact itself.
    canvas.drawCircle(origin, 5 + 4 * spread, Paint()..color = theme.ink);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrackPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.theme != theme;
}

/// The empty socket: the card's outline around a dark hole with a torn
/// paper edge.
class _HolePainter extends CustomPainter {
  const _HolePainter(this.theme);

  final ScreenTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(theme.radius),
    );
    canvas.drawRRect(rect, Paint()..color = theme.ink.withValues(alpha: 0.82));
    // Inner shading, deeper toward the middle.
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.6,
          [const Color(0x00000000), const Color(0x99000000)],
        ),
    );
    final random = math.Random(7);
    final tear = Path();
    final inset = 4.0;
    final w = size.width, h = size.height;
    tear.moveTo(inset, inset);
    void edge(Offset from, Offset to) {
      const steps = 14;
      for (var i = 1; i <= steps; i++) {
        final p = Offset.lerp(from, to, i / steps)!;
        final n = Offset(to.dy - from.dy, from.dx - to.dx);
        final len = n.distance == 0 ? 1.0 : n.distance;
        final jag = n / len * ((random.nextDouble() - 0.5) * 7);
        tear.lineTo(p.dx + jag.dx, p.dy + jag.dy);
      }
    }

    edge(Offset(inset, inset), Offset(w - inset, inset));
    edge(Offset(w - inset, inset), Offset(w - inset, h - inset));
    edge(Offset(w - inset, h - inset), Offset(inset, h - inset));
    edge(Offset(inset, h - inset), Offset(inset, inset));
    tear.close();
    canvas.drawPath(
      tear,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = theme.paper.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.stroke
        ..color = theme.ink,
    );
  }

  @override
  bool shouldRepaint(_HolePainter oldDelegate) => oldDelegate.theme != theme;
}

/// A convex piece of a broken card, in the card's own 0..1 space.
class ShardShape {
  const ShardShape(this.polygon);

  /// Counter-clockwise (in y-down screen space) vertices, 0..1.
  final List<Offset> polygon;

  Offset get centroid {
    var x = 0.0, y = 0.0;
    for (final p in polygon) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / polygon.length, y / polygon.length);
  }
}

/// Splits the unit square into Voronoi cells around [count] seeds bunched
/// toward [hit], so the smallest shards sit where the die struck.
List<ShardShape> shatter(Offset hit, int count, int seed) {
  final random = math.Random(seed);
  final seeds = <Offset>[
    for (var i = 0; i < count; i++)
      () {
        // Half the seeds cluster near the hit, the rest spread out.
        final near = i < count ~/ 2;
        final r = near
            ? 0.05 + random.nextDouble() * 0.2
            : 0.2 + random.nextDouble() * 0.6;
        final a = random.nextDouble() * math.pi * 2;
        return Offset(
          (hit.dx + math.cos(a) * r).clamp(0.02, 0.98),
          (hit.dy + math.sin(a) * r).clamp(0.02, 0.98),
        );
      }(),
  ];
  final shards = <ShardShape>[];
  for (var i = 0; i < seeds.length; i++) {
    var cell = <Offset>[
      const Offset(0, 0),
      const Offset(1, 0),
      const Offset(1, 1),
      const Offset(0, 1),
    ];
    for (var j = 0; j < seeds.length; j++) {
      if (i == j) continue;
      cell = _clipHalfPlane(cell, seeds[i], seeds[j]);
      if (cell.length < 3) break;
    }
    if (cell.length >= 3) shards.add(ShardShape(cell));
  }
  return shards;
}

/// Keeps the part of [polygon] closer to [keep] than to [other].
List<Offset> _clipHalfPlane(List<Offset> polygon, Offset keep, Offset other) {
  final mid = (keep + other) / 2;
  final normal = other - keep;
  double side(Offset p) =>
      (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;
  final out = <Offset>[];
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final sa = side(a), sb = side(b);
    if (sa <= 0) out.add(a);
    if ((sa <= 0) != (sb <= 0)) {
      final t = sa / (sa - sb);
      out.add(Offset.lerp(a, b, t)!);
    }
  }
  return out;
}
