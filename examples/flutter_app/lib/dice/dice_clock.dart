import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pop_theme.dart';

/// A live analog clock face on a paper square, the widget sealed inside a
/// glass die. Ticks on its own so it keeps time while captured.
class DieClockFace extends StatefulWidget {
  const DieClockFace({super.key, required this.theme});

  final ScreenTheme theme;

  @override
  State<DieClockFace> createState() => _DieClockFaceState();
}

class _DieClockFaceState extends State<DieClockFace>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ticker,
      builder: (context, _) => CustomPaint(
        painter: _ClockPainter(DateTime.now(), widget.theme),
        size: const Size.square(128),
      ),
    );
  }
}

class _ClockPainter extends CustomPainter {
  const _ClockPainter(this.now, this.theme);

  final DateTime now;
  final ScreenTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = theme.paper);
    canvas.drawCircle(c, r * 0.92, Paint()..color = theme.cream);
    canvas.drawCircle(
      c,
      r * 0.92,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = theme.ink,
    );
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..color = theme.ink;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final dir = Offset(math.sin(a), -math.cos(a));
      final long = i % 3 == 0;
      canvas.drawLine(
        c + dir * r * (long ? 0.68 : 0.76),
        c + dir * r * 0.84,
        tick..strokeWidth = r * (long ? 0.07 : 0.04),
      );
    }
    final seconds = now.second + now.millisecond / 1000;
    final minutes = now.minute + seconds / 60;
    final hours = now.hour % 12 + minutes / 60;
    void hand(double turns, double length, double width, Color color) {
      final a = turns * math.pi * 2;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c - dir * r * 0.12,
        c + dir * r * length,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * width
          ..color = color,
      );
    }

    hand(hours / 12, 0.45, 0.09, theme.ink);
    hand(minutes / 60, 0.66, 0.07, theme.ink);
    // The second hand snaps from tick to tick.
    hand(seconds.floorToDouble() / 60, 0.74, 0.03, theme.accent);
    canvas.drawCircle(c, r * 0.07, Paint()..color = theme.accent);
  }

  @override
  bool shouldRepaint(_ClockPainter oldDelegate) =>
      oldDelegate.now != now || oldDelegate.theme != theme;
}
