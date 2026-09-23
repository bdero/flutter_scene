import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A die hitting the table, in global screen coordinates.
@immutable
class DiceHit {
  const DiceHit(this.position, this.strength, this.time);

  final Offset position;

  /// 0..1, how hard.
  final double strength;

  /// Seconds on the contacts clock.
  final double time;
}

/// Where the dice touch the screen this frame, so widgets under them can
/// react. Published by the scene every tick.
@immutable
class DiceContacts {
  const DiceContacts({
    this.resting = const [],
    this.hits = const [],
    this.time = 0.0,
  });

  /// Dice sitting still on the table, with their screen radius.
  final List<(Offset, double)> resting;

  /// Recent hits, oldest first.
  final List<DiceHit> hits;

  final double time;

  /// How pressed a widget covering [rect] is, 0..1. A hit inside the rect
  /// kicks it and decays; a resting die keeps it held part way down.
  double pressOf(Rect rect) {
    var press = 0.0;
    for (final hit in hits) {
      if (!rect.inflate(6).contains(hit.position)) continue;
      final age = time - hit.time;
      press = math.max(press, hit.strength * math.exp(-age * 7.0));
    }
    for (final (position, radius) in resting) {
      if (rect.inflate(radius * 0.5).contains(position)) {
        press = math.max(press, 0.45);
      }
    }
    return press.clamp(0.0, 1.0);
  }
}

/// The press depth a [Pressable] hands its subtree, 0 when none.
class PressDepth extends InheritedWidget {
  const PressDepth({super.key, required this.press, required super.child});

  final double press;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressDepth>()?.press ?? 0.0;

  @override
  bool updateShouldNotify(PressDepth oldWidget) =>
      (oldWidget.press - press).abs() > 0.002;
}

/// Sinks its child when dice land on or rest over it. The child's own rect
/// is measured each frame, so nothing needs registering.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.contacts, required this.child});

  final ValueListenable<DiceContacts> contacts;
  final Widget child;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  double _press = 0.0;

  @override
  void initState() {
    super.initState();
    widget.contacts.addListener(_update);
  }

  @override
  void didUpdateWidget(Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.contacts, widget.contacts)) {
      oldWidget.contacts.removeListener(_update);
      widget.contacts.addListener(_update);
    }
  }

  @override
  void dispose() {
    widget.contacts.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final press = widget.contacts.value.pressOf(rect);
    if ((press - _press).abs() < 0.004) return;
    setState(() => _press = press);
  }

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.0 - 0.04 * _press,
      child: PressDepth(press: _press, child: widget.child),
    );
  }
}
