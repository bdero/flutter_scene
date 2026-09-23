import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dice_contacts.dart';

/// The pop palette, the default look.
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
}

/// Which look the screen wears.
enum ScreenLook { pop, blueprint, washi }

/// A look for the game screen: palette, type, card geometry, and the painted
/// background. Everything is painted, so a look ships no image assets.
class ScreenTheme {
  const ScreenTheme({
    required this.look,
    required this.label,
    required this.ground,
    required this.paper,
    required this.ink,
    required this.cream,
    required this.accent,
    required this.accent2,
    required this.score,
    required this.badge,
    required this.button,
    required this.confetti,
    this.mono = false,
    this.stroke = Pop.stroke,
    this.shadow = Pop.shadow,
    this.radius = Pop.radius,
  });

  final ScreenLook look;
  final String label;

  /// The background's base color.
  final Color ground;

  /// Card fill.
  final Color paper;

  /// Outlines and body text.
  final Color ink;

  /// Display type fill.
  final Color cream;

  /// The first and second accent colors (avatars, chips).
  final Color accent;
  final Color accent2;

  /// The running number and the last-roll block.
  final Color score;

  /// The TOTAL sticker.
  final Color badge;

  /// The Roll pill.
  final Color button;

  /// Confetti and background bits.
  final List<Color> confetti;

  /// Monospaced type, for the drafting look.
  final bool mono;

  final double stroke;
  final Offset shadow;
  final double radius;

  TextStyle get labelStyle => TextStyle(
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w900,
    letterSpacing: mono ? 0.0 : 0.2,
    height: 1.1,
    fontFamily: mono ? 'Menlo' : null,
    fontFamilyFallback: mono ? const ['Courier New', 'monospace'] : null,
  );

  TextStyle get smallStyle =>
      labelStyle.copyWith(fontSize: 13, fontWeight: FontWeight.w800);

  /// Paints the background at loop phase [t] (0..1).
  void paintBackground(Canvas canvas, Size size, double t) {
    switch (look) {
      case ScreenLook.pop:
        _paintStripes(canvas, size, t, this);
      case ScreenLook.blueprint:
        _paintBlueprint(canvas, size, t, this);
      case ScreenLook.washi:
        _paintWashi(canvas, size, t, this);
    }
  }

  static const ScreenTheme pop = ScreenTheme(
    look: ScreenLook.pop,
    label: 'Pop',
    ground: Pop.cream,
    paper: Pop.paper,
    ink: Pop.ink,
    cream: Pop.cream,
    accent: Pop.coral,
    accent2: Pop.teal,
    score: Pop.mustard,
    badge: Pop.coral,
    button: Pop.coral,
    confetti: [Pop.coral, Pop.teal, Pop.mustard, Pop.mint],
  );

  static const ScreenTheme blueprint = ScreenTheme(
    look: ScreenLook.blueprint,
    label: 'Blueprint',
    ground: Color(0xFF1F6FA6),
    paper: Color(0xFFEEF6FB),
    ink: Color(0xFF15334A),
    cream: Color(0xFFF4FAFF),
    accent: Color(0xFFFFD166),
    accent2: Color(0xFF7EC8E3),
    score: Color(0xFFFFD166),
    badge: Color(0xFFF4FAFF),
    button: Color(0xFFF4FAFF),
    confetti: [
      Color(0xFFFFD166),
      Color(0xFFF4FAFF),
      Color(0xFF7EC8E3),
      Color(0xFFD9B382),
    ],
    mono: true,
    stroke: 2.5,
    shadow: Offset(3, 3),
    radius: 6,
  );

  static const ScreenTheme washi = ScreenTheme(
    look: ScreenLook.washi,
    label: 'Washi',
    ground: Color(0xFF22406B),
    paper: Color(0xFFF6EFE3),
    ink: Color(0xFF2A2623),
    cream: Color(0xFFF6EFE3),
    accent: Color(0xFFC8412B),
    accent2: Color(0xFF3F6FA8),
    score: Color(0xFFC8412B),
    badge: Color(0xFFC8412B),
    button: Color(0xFFF6EFE3),
    confetti: [
      Color(0xFFC8412B),
      Color(0xFFF6EFE3),
      Color(0xFFD9A441),
      Color(0xFF7FA6D9),
    ],
    stroke: 2.5,
    shadow: Offset(4, 4),
    radius: 10,
  );

  static const List<ScreenTheme> all = [pop, blueprint, washi];

  static ScreenTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ScreenThemeScope>()?.theme ??
      pop;
}

/// Supplies a [ScreenTheme] to the widgets below it.
class ScreenThemeScope extends InheritedWidget {
  const ScreenThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final ScreenTheme theme;

  @override
  bool updateShouldNotify(ScreenThemeScope oldWidget) =>
      oldWidget.theme != theme;
}

// --- Backgrounds ------------------------------------------------------------

// Stripe colors and widths repeat in this order.
List<(Color, double)> _stripeBands(ScreenTheme theme) => [
  (theme.ground, 26),
  (theme.confetti[0], 22),
  (theme.ground, 14),
  (theme.confetti[1], 18),
  (theme.ground, 30),
  (theme.confetti[2], 20),
  (theme.ground, 12),
  (theme.confetti[3], 16),
];

void _paintStripes(Canvas canvas, Size size, double t, ScreenTheme theme) {
  canvas.drawRect(Offset.zero & size, Paint()..color = theme.ground);
  final bands = _stripeBands(theme);
  final period = bands.fold(0.0, (sum, band) => sum + band.$2);
  // Stripes climb from bottom-left to top-right and drift one band cycle
  // per loop.
  const angle = -0.72;
  final reach = size.width + size.height;
  canvas.save();
  canvas.translate(size.width / 2, size.height / 2);
  canvas.rotate(angle);
  var x = -reach - period + t * period;
  var i = 0;
  final paint = Paint();
  while (x < reach) {
    final (color, width) = bands[i % bands.length];
    if (color != theme.ground) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(x, -reach, width, reach * 2), paint);
    }
    x += width;
    i++;
  }
  canvas.restore();
  _paintBits(canvas, size, t, theme.confetti);
}

/// Confetti dots and squiggles, fixed per size, bobbing on the loop.
void _paintBits(Canvas canvas, Size size, double t, List<Color> colors) {
  final random = math.Random(size.width.toInt() * 31 + size.height.toInt());
  final dot = Paint();
  final squiggle = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;
  final count = (size.width * size.height / 9000).round();
  for (var n = 0; n < count; n++) {
    final bob = random.nextDouble() * math.pi * 2;
    final p = Offset(
      random.nextDouble() * size.width + math.sin(t * math.pi * 6 + bob) * 3,
      random.nextDouble() * size.height + math.cos(t * math.pi * 4 + bob) * 4,
    );
    final color = colors[random.nextInt(colors.length)];
    if (random.nextInt(3) == 0) {
      final a =
          random.nextDouble() * math.pi +
          math.sin(t * math.pi * 2 + bob) * 0.35;
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

/// Drafting paper: a fine grid, hatched bands that drift, dimension lines,
/// and a coffee ring.
void _paintBlueprint(Canvas canvas, Size size, double t, ScreenTheme theme) {
  canvas.drawRect(Offset.zero & size, Paint()..color = theme.ground);
  final fine = Paint()
    ..color = Colors.white.withValues(alpha: 0.10)
    ..strokeWidth = 1;
  final major = Paint()
    ..color = Colors.white.withValues(alpha: 0.24)
    ..strokeWidth = 1.2;
  for (var x = 0.0; x <= size.width; x += 20) {
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      x % 100 == 0 ? major : fine,
    );
  }
  for (var y = 0.0; y <= size.height; y += 20) {
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      y % 100 == 0 ? major : fine,
    );
  }
  // Diagonal hatch bands sliding down the sheet.
  final hatch = Paint()
    ..color = Colors.white.withValues(alpha: 0.14)
    ..strokeWidth = 9;
  final reach = size.width + size.height;
  const spacing = 76.0;
  canvas.save();
  canvas.translate(size.width / 2, size.height / 2);
  canvas.rotate(0.62);
  for (var x = -reach - spacing + t * spacing; x < reach; x += spacing) {
    canvas.drawLine(Offset(x, -reach), Offset(x, reach), hatch);
  }
  canvas.restore();
  // Dimension lines with ticks along two edges.
  final dim = Paint()
    ..color = Colors.white.withValues(alpha: 0.45)
    ..strokeWidth = 1.2;
  final y = size.height - 44;
  canvas.drawLine(Offset(60, y), Offset(size.width - 60, y), dim);
  for (var x = 60.0; x <= size.width - 60; x += 100) {
    canvas.drawLine(Offset(x, y - 6), Offset(x, y + 6), dim);
  }
  final x = size.width - 44;
  canvas.drawLine(Offset(x, 60), Offset(x, size.height - 60), dim);
  for (var yy = 60.0; yy <= size.height - 60; yy += 100) {
    canvas.drawLine(Offset(x - 6, yy), Offset(x + 6, yy), dim);
  }
  // A coffee ring, the drafter's signature.
  canvas.drawCircle(
    Offset(size.width * 0.72, size.height * 0.18),
    52,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = const Color(0xFF5A3A1E).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
  );
}

/// Indigo washi: seigaiha waves that drift, over paper fibre flecks.
void _paintWashi(Canvas canvas, Size size, double t, ScreenTheme theme) {
  canvas.drawRect(Offset.zero & size, Paint()..color = theme.ground);
  const r = 34.0;
  final rowH = r * 0.55;
  final wave = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.2
    ..color = const Color(0xFF6E8FC4).withValues(alpha: 0.55);
  final fill = Paint()..color = theme.ground;
  final drift = t * r * 2;
  var row = 0;
  for (var y = -rowH; y < size.height + r; y += rowH) {
    final offset = (row.isOdd ? r : 0.0) + drift;
    for (
      var x = -r * 2 - drift + (offset % (r * 2));
      x < size.width + r * 2;
      x += r * 2
    ) {
      // Each scale is a filled disc so it hides the row behind, then rings.
      canvas.drawCircle(Offset(x, y), r, fill);
      for (var k = 0; k < 4; k++) {
        canvas.drawCircle(Offset(x, y), r - k * 8.0, wave);
      }
    }
    row++;
  }
  // Fibre flecks.
  final random = math.Random(size.width.toInt() * 7 + size.height.toInt());
  final fleck = Paint()
    ..color = theme.paper.withValues(alpha: 0.10)
    ..strokeWidth = 1.2;
  final count = (size.width * size.height / 6000).round();
  for (var n = 0; n < count; n++) {
    final p = Offset(
      random.nextDouble() * size.width,
      random.nextDouble() * size.height,
    );
    final a = random.nextDouble() * math.pi;
    final len = 4 + random.nextDouble() * 8;
    canvas.drawLine(p, p + Offset(math.cos(a), math.sin(a)) * len, fleck);
  }
}

/// The themed background, driven by [animation] (0..1, looping) so
/// something always moves under the dice.
class ThemedBackground extends StatelessWidget {
  const ThemedBackground({super.key, required this.animation, this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BackgroundPainter(ScreenTheme.of(context), animation),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.theme, this.animation) : super(repaint: animation);

  final ScreenTheme theme;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) =>
      theme.paintBackground(canvas, size, animation.value);

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.animation != animation;
}

// --- Widgets ----------------------------------------------------------------

/// A panel with a thick ink outline and a hard offset shadow. Under a
/// [Pressable] it sinks toward its shadow as the press deepens.
class PopCard extends StatelessWidget {
  const PopCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(14),
    this.radius,
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    final press = PressDepth.of(context);
    return Transform.translate(
      offset: theme.shadow * (0.85 * press),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? theme.paper,
          borderRadius: BorderRadius.circular(radius ?? theme.radius),
          border: Border.all(color: theme.ink, width: theme.stroke),
          boxShadow: [
            BoxShadow(
              color: theme.ink,
              offset: theme.shadow * (1 - 0.85 * press),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Chunky display text with an ink outline and a hard shadow.
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    required this.size,
    this.fill,
    this.outline,
    this.strokeWidth,
    this.shadow = true,
    this.letterSpacing = -1.0,
  });

  final String text;
  final double size;
  final Color? fill;
  final Color? outline;
  final double? strokeWidth;
  final bool shadow;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    final ink = outline ?? theme.ink;
    final stroke = strokeWidth ?? (size * 0.12).clamp(2.0, 9.0);
    final base = theme.labelStyle.copyWith(
      fontSize: size,
      letterSpacing: letterSpacing,
      height: 1.0,
    );
    final offset = Offset(size * 0.05, size * 0.05);
    Widget outlined(Color color) => Text(
      text,
      style: base.copyWith(
        color: null,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      ),
    );
    return Stack(
      children: [
        if (shadow && stroke > 0)
          Transform.translate(offset: offset, child: outlined(ink)),
        if (stroke > 0) outlined(ink),
        Text(text, style: base.copyWith(color: fill ?? theme.cream)),
      ],
    );
  }
}

/// A small outlined die face showing [value] as pips.
class PipFace extends StatelessWidget {
  const PipFace(this.value, {super.key, this.size = 26, this.color});

  final int value;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _PipFacePainter(value, color ?? theme.paper, theme.ink),
    );
  }
}

class _PipFacePainter extends CustomPainter {
  const _PipFacePainter(this.value, this.color, this.ink);

  final int value;
  final Color color;
  final Color ink;

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
        ..color = ink,
    );
    final pip = Paint()..color = ink;
    final r = size.width * 0.09;
    for (final (x, y) in _layouts[(value - 1).clamp(0, 5)]) {
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, pip);
    }
  }

  @override
  bool shouldRepaint(_PipFacePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.ink != ink;
}

/// A scalloped sticker, the TOTAL badge.
class PopBadge extends StatelessWidget {
  const PopBadge({
    super.key,
    required this.child,
    this.color,
    this.size = 128,
    this.scallops = 18,
  });

  final Widget child;
  final Color? color;
  final double size;
  final int scallops;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    return CustomPaint(
      painter: _BadgePainter(color ?? theme.badge, theme, scallops),
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: child),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.color, this.theme, this.scallops);

  final Color color;
  final ScreenTheme theme;
  final int scallops;

  Path _scalloped(Size size, double inset) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2 - inset;
    final inner = outer * 0.92;
    final path = Path();
    final steps = scallops * 2;
    for (var i = 0; i <= steps; i++) {
      final a = i * math.pi * 2 / steps;
      final r = i.isEven ? outer : inner;
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
    final path = _scalloped(size, theme.stroke);
    canvas.save();
    canvas.translate(theme.shadow.dx, theme.shadow.dy);
    canvas.drawPath(path, Paint()..color = theme.ink);
    canvas.restore();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = theme.stroke
        ..strokeJoin = StrokeJoin.round
        ..color = theme.ink,
    );
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2 - theme.stroke - size.width * 0.09,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = theme.ink.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.theme != theme ||
      oldDelegate.scallops != scallops;
}

/// The Roll pill. Under a [Pressable] it sinks like the cards.
class PopButton extends StatelessWidget {
  const PopButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = ScreenTheme.of(context);
    final press = PressDepth.of(context);
    final fill = color ?? theme.button;
    // A light pill takes plain ink lettering; a dark one keeps the outline.
    final light = fill.computeLuminance() > 0.5;
    return Transform.translate(
      offset: theme.shadow * (0.85 * press),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(40),
          child: Ink(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: theme.ink, width: theme.stroke),
              boxShadow: [
                BoxShadow(
                  color: theme.ink,
                  offset: theme.shadow * (1 - 0.85 * press),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
              child: OutlinedText(
                label,
                size: 34,
                shadow: false,
                fill: light ? theme.ink : theme.cream,
                strokeWidth: light ? 0.0 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
