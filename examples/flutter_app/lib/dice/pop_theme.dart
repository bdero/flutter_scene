import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The game screen's pop look: candy stripes, thick ink outlines with hard
/// offset shadows, chunky outlined type, and confetti. Everything is painted,
/// so the screen ships no image assets and captures crisply at any size.
abstract final class Pop {
  static const Color cream = Color(0xFFFFF4DF);
  static const Color paper = Color(0xFFFFF9EE);
  static const Color coral = Color(0xFFF4845F);
  static const Color teal = Color(0xFF2A9D8F);
  static const Color mint = Color(0xFF8ED2C6);
  static const Color mustard = Color(0xFFE9C46A);
  static const Color ink = Color(0xFF1F1B1A);

  static const double stroke = 3.0;
  static const Offset shadow = Offset(5, 5);
  static const double radius = 14.0;

  static const TextStyle label = TextStyle(
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.2,
    height: 1.1,
  );

  static const TextStyle small = TextStyle(
    color: ink,
    fontSize: 13,
    fontWeight: FontWeight.w800,
    height: 1.1,
  );
}

/// Diagonal stripes with confetti scattered over them.
class PopStripesBackground extends StatelessWidget {
  const PopStripesBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _StripesPainter(),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  // Stripe colors and widths repeat in this order.
  static const _bands = <(Color, double)>[
    (Pop.cream, 26),
    (Pop.coral, 22),
    (Pop.cream, 14),
    (Pop.teal, 18),
    (Pop.cream, 30),
    (Pop.mustard, 20),
    (Pop.cream, 12),
    (Pop.mint, 16),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Pop.cream);
    // Stripes climb from bottom-left to top-right.
    const angle = -0.72;
    final reach = size.width + size.height;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    var x = -reach;
    var i = 0;
    final paint = Paint();
    while (x < reach) {
      final (color, width) = _bands[i % _bands.length];
      if (color != Pop.cream) {
        paint.color = color;
        canvas.drawRect(Rect.fromLTWH(x, -reach, width, reach * 2), paint);
      }
      x += width;
      i++;
    }
    canvas.restore();

    // Confetti, fixed per size so it never flickers between frames.
    final random = math.Random(size.width.toInt() * 31 + size.height.toInt());
    final colors = [Pop.coral, Pop.teal, Pop.mustard, Pop.mint];
    final dot = Paint();
    final squiggle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final count = (size.width * size.height / 9000).round();
    for (var n = 0; n < count; n++) {
      final p = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final color = colors[random.nextInt(colors.length)];
      if (random.nextInt(3) == 0) {
        // A little wave.
        final a = random.nextDouble() * math.pi;
        final len = 14 + random.nextDouble() * 10;
        final path = Path()..moveTo(-len / 2, 0);
        path.cubicTo(-len / 4, -6, len / 4, 6, len / 2, 0);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(a);
        canvas.drawPath(path, squiggle..color = color);
        canvas.restore();
      } else {
        canvas.drawCircle(p, 3 + random.nextDouble() * 3, dot..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_StripesPainter oldDelegate) => false;
}

/// A panel with a thick ink outline and a hard offset shadow.
class PopCard extends StatelessWidget {
  const PopCard({
    super.key,
    required this.child,
    this.color = Pop.paper,
    this.padding = const EdgeInsets.all(14),
    this.radius = Pop.radius,
    this.shadow = Pop.shadow,
  });

  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Offset shadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Pop.ink, width: Pop.stroke),
        boxShadow: [BoxShadow(color: Pop.ink, offset: shadow)],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Chunky display text with an ink outline and a hard shadow.
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    required this.size,
    this.fill = Pop.cream,
    this.outline = Pop.ink,
    this.strokeWidth,
    this.shadow = true,
    this.letterSpacing = -1.0,
  });

  final String text;
  final double size;
  final Color fill;
  final Color outline;
  final double? strokeWidth;
  final bool shadow;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final stroke = strokeWidth ?? (size * 0.12).clamp(2.0, 9.0);
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: letterSpacing,
      height: 1.0,
    );
    final offset = Offset(size * 0.05, size * 0.05);
    return Stack(
      children: [
        if (shadow)
          Transform.translate(
            offset: offset,
            child: Text(
              text,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = stroke
                  ..strokeJoin = StrokeJoin.round
                  ..color = outline,
              ),
            ),
          ),
        Text(
          text,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        Text(text, style: base.copyWith(color: fill)),
      ],
    );
  }
}

/// A small outlined die face showing [value] as pips.
class PipFace extends StatelessWidget {
  const PipFace(
    this.value, {
    super.key,
    this.size = 26,
    this.color = Pop.paper,
  });

  final int value;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PipFacePainter(value, color),
    );
  }
}

class _PipFacePainter extends CustomPainter {
  const _PipFacePainter(this.value, this.color);

  final int value;
  final Color color;

  static const _layouts = <List<(double, double)>>[
    [(0.5, 0.5)],
    [(0.27, 0.27), (0.73, 0.73)],
    [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    [
      (0.27, 0.27),
      (0.73, 0.27),
      (0.27, 0.5),
      (0.73, 0.5),
      (0.27, 0.73),
      (0.73, 0.73),
    ],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Pop.ink,
    );
    final pip = Paint()..color = Pop.ink;
    final r = size.width * 0.09;
    for (final (x, y) in _layouts[(value - 1).clamp(0, 5)]) {
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, pip);
    }
  }

  @override
  bool shouldRepaint(_PipFacePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

/// A scalloped sticker, the TOTAL badge.
class PopBadge extends StatelessWidget {
  const PopBadge({
    super.key,
    required this.child,
    this.color = Pop.coral,
    this.size = 128,
    this.scallops = 18,
  });

  final Widget child;
  final Color color;
  final double size;
  final int scallops;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BadgePainter(color, scallops),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.color, this.scallops);

  final Color color;
  final int scallops;

  Path _scalloped(Size size, double inset) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - inset;
    final inner = outer * 0.92;
    final path = Path();
    final steps = scallops * 2;
    for (var i = 0; i <= steps; i++) {
      final a = i * math.pi * 2 / steps;
      // Rounded bumps rather than points.
      final t = 0.5 + 0.5 * math.cos(i.isEven ? 0 : math.pi);
      final r = inner + (outer - inner) * t;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prevA = (i - 1) * math.pi * 2 / steps;
        final midA = (a + prevA) / 2;
        final bulge = i.isEven ? inner : outer + (outer - inner) * 0.35;
        final ctrl = c + Offset(math.cos(midA), math.sin(midA)) * bulge;
        path.quadraticBezierTo(ctrl.dx, ctrl.dy, p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _scalloped(size, Pop.stroke);
    canvas.save();
    canvas.translate(Pop.shadow.dx, Pop.shadow.dy);
    canvas.drawPath(path, Paint()..color = Pop.ink);
    canvas.restore();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = Pop.stroke
        ..strokeJoin = StrokeJoin.round
        ..color = Pop.ink,
    );
    // An inner ring, like a sticker's print margin.
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 - Pop.stroke - size.width * 0.09,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Pop.ink.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scallops != scallops;
}

/// The coral Roll pill.
class PopButton extends StatelessWidget {
  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Pop.coral,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(40),
        child: Ink(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Pop.ink, width: Pop.stroke),
            boxShadow: const [BoxShadow(color: Pop.ink, offset: Pop.shadow)],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
            child: OutlinedText(label, size: 34, shadow: false),
          ),
        ),
      ),
    );
  }
}
