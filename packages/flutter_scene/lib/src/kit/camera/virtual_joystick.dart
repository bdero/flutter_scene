import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Callback for joystick input events emitting a normalized 2D direction vector.
///
/// In screen space, dragging upward produces a negative Y component (`direction.y < 0`).
/// {@category Widgets}
typedef JoystickCallback = void Function(vm.Vector2 direction);

/// An ergonomic on-screen multi-touch virtual thumbstick for driving game characters and cameras.
///
/// Note on coordinate space: The joystick emits raw screen-space directions (where pushing up is `-Y`
/// and right is `+X`). When feeding into character controllers expecting `+Y` as forward, invert the Y axis:
/// `controller.setMoveInput(vm.Vector2(dir.x, -dir.y))`.
/// {@category Widgets}
class VirtualJoystick extends StatefulWidget {
  /// Radius of the outer boundary circle.
  final double radius;

  /// Radius of the inner draggable knob.
  final double knobRadius;

  /// Deadzone radius (0.0 to <1.0) below which input is reported as zero.
  final double deadzone;

  /// Callback receiving the normalized direction vector in screen coordinates.
  final JoystickCallback onChanged;

  /// Optional decoration for the outer ring.
  final BoxDecoration? baseDecoration;

  /// Optional decoration for the inner knob.
  final BoxDecoration? knobDecoration;

  const VirtualJoystick({
    super.key,
    required this.onChanged,
    this.radius = 60.0,
    this.knobRadius = 24.0,
    this.deadzone = 0.1,
    this.baseDecoration,
    this.knobDecoration,
  }) : assert(
         deadzone >= 0.0 && deadzone < 1.0,
         'deadzone must be in [0.0, 1.0)',
       );

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _dragOffset = Offset.zero;

  void _updateOffset(Offset localPos, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final delta = localPos - center;
    final dist = delta.distance;
    final maxDist = widget.radius;

    if (dist <= 0.0) {
      _dragOffset = Offset.zero;
      widget.onChanged(vm.Vector2.zero());
    } else {
      final clampedDist = math.min(dist, maxDist);
      final normalizedDelta = delta / dist;
      _dragOffset = normalizedDelta * clampedDist;

      final normalizedMag = clampedDist / maxDist;
      if (normalizedMag < widget.deadzone) {
        widget.onChanged(vm.Vector2.zero());
      } else {
        final remappedMag =
            (normalizedMag - widget.deadzone) / (1.0 - widget.deadzone);
        final dir =
            vm.Vector2(normalizedDelta.dx, normalizedDelta.dy) * remappedMag;
        widget.onChanged(dir);
      }
    }
    setState(() {});
  }

  void _reset() {
    _dragOffset = Offset.zero;
    widget.onChanged(vm.Vector2.zero());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.radius * 2.0;
    final defaultBaseDeco = BoxDecoration(
      color: const Color(0x33FFFFFF),
      shape: BoxShape.circle,
      border: Border.all(color: const Color(0x66FFFFFF), width: 2.0),
    );
    final defaultKnobDeco = const BoxDecoration(
      color: Color(0xAAFFFFFF),
      shape: BoxShape.circle,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) =>
          _updateOffset(d.localPosition, Size(diameter, diameter)),
      onPanUpdate: (d) =>
          _updateOffset(d.localPosition, Size(diameter, diameter)),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: diameter,
              height: diameter,
              decoration: widget.baseDecoration ?? defaultBaseDeco,
            ),
            Transform.translate(
              offset: _dragOffset,
              child: Container(
                width: widget.knobRadius * 2.0,
                height: widget.knobRadius * 2.0,
                decoration: widget.knobDecoration ?? defaultKnobDeco,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
