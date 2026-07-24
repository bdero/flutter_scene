import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'orbit_camera.dart';

/// The world axes rendered by the orientation gizmo, screen-projected
/// through the viewport camera's orientation.
const _axisColors = [Color(0xFFE0483E), Color(0xFF6BB536), Color(0xFF3E7DE0)];
const _axisLabels = ['X', 'Y', 'Z'];

/// Blender-style navigation gizmo for a viewport corner.
///
/// Shows the camera's current orientation as six axis knobs. Clicking a knob
/// snaps the camera to look down that axis (switching to orthographic);
/// clicking the axis already faced snaps to its opposite side. Dragging the
/// gizmo orbits the camera.
class OrientationGizmo extends StatefulWidget {
  const OrientationGizmo({
    super.key,
    required this.camera,
    required this.onChanged,
    this.size = 88,
  });

  final OrbitCamera camera;
  final VoidCallback onChanged;
  final double size;

  @override
  State<OrientationGizmo> createState() => _OrientationGizmoState();
}

class _OrientationGizmoState extends State<OrientationGizmo> {
  bool _hovered = false;
  Offset? _lastDrag;
  bool _dragged = false;

  static const double _knobRadius = 9;

  /// Screen-space knob centers for the six axis directions, in paint order
  /// (far to near). Entries are (axis, negative, offset, depth).
  List<(int, bool, Offset, double)> _knobs(Size size) {
    final camera = widget.camera;
    final right = camera.rightVector;
    final up = camera.upVector;
    final forward = camera.forwardVector;
    final center = size.center(Offset.zero);
    final reach = size.width / 2 - _knobRadius - 2;

    final knobs = <(int, bool, Offset, double)>[];
    for (var axis = 0; axis < 3; axis++) {
      for (final negative in [false, true]) {
        final dir = vm.Vector3.zero()..[axis] = negative ? -1.0 : 1.0;
        final screen = Offset(dir.dot(right), -dir.dot(up)) * reach;
        knobs.add((axis, negative, center + screen, dir.dot(forward)));
      }
    }
    // Painter's order, farthest first. Depth is the axis tip's component
    // along the view direction, so positive means beyond the gizmo center.
    knobs.sort((a, b) => b.$4.compareTo(a.$4));
    return knobs;
  }

  void _onTapUp(TapUpDetails details) {
    if (_dragged) return;
    final size = Size.square(widget.size);
    // Topmost knob wins, so scan in reverse paint order.
    for (final (axis, negative, offset, _) in _knobs(size).reversed) {
      if ((details.localPosition - offset).distance > _knobRadius + 2) {
        continue;
      }
      final flip = _isCurrentView(axis, negative: negative);
      widget.camera.snapAxisView(axis, negative: flip ? !negative : negative);
      widget.onChanged();
      return;
    }
  }

  /// Whether the camera is already looking down this knob's axis, in which
  /// case clicking it snaps to the opposite side (matching how these gizmos
  /// behave elsewhere).
  bool _isCurrentView(int axis, {required bool negative}) {
    final dir = vm.Vector3.zero()..[axis] = negative ? -1.0 : 1.0;
    return widget.camera.forwardVector.dot(-dir) > 0.999;
  }

  @override
  Widget build(BuildContext context) {
    final size = Size.square(widget.size);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapUp: _onTapUp,
        onPanStart: (details) {
          _lastDrag = details.localPosition;
          _dragged = false;
        },
        onPanUpdate: (details) {
          final last = _lastDrag;
          if (last == null) return;
          final delta = details.localPosition - last;
          _lastDrag = details.localPosition;
          if (delta.distance > 0) _dragged = true;
          widget.camera.orbit(delta.dx, delta.dy);
          widget.onChanged();
        },
        onPanEnd: (_) => _lastDrag = null,
        child: CustomPaint(
          size: size,
          painter: _OrientationGizmoPainter(
            knobs: _knobs(size),
            hovered: _hovered,
          ),
        ),
      ),
    );
  }
}

class _OrientationGizmoPainter extends CustomPainter {
  _OrientationGizmoPainter({required this.knobs, required this.hovered});

  final List<(int, bool, Offset, double)> knobs;
  final bool hovered;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    if (hovered) {
      canvas.drawCircle(
        center,
        size.width / 2,
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );
    }

    for (final (axis, negative, offset, depth) in knobs) {
      final color = _axisColors[axis];
      // Depth cue, knobs pointing away fade toward the background.
      final fade = 0.55 + 0.45 * (-depth + 1) / 2;
      final faded = Color.lerp(const Color(0xFF303030), color, fade)!;

      if (!negative) {
        canvas.drawLine(
          center,
          offset,
          Paint()
            ..color = faded
            ..strokeWidth = 2,
        );
        canvas.drawCircle(offset, 8, Paint()..color = faded);
        final text = TextPainter(
          text: TextSpan(
            text: _axisLabels[axis],
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, offset - Offset(text.width / 2, text.height / 2));
      } else {
        // Negative axes render hollow.
        canvas.drawCircle(
          offset,
          7,
          Paint()..color = faded.withValues(alpha: 0.35),
        );
        canvas.drawCircle(
          offset,
          7,
          Paint()
            ..color = faded
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_OrientationGizmoPainter oldDelegate) =>
      hovered != oldDelegate.hovered || !_sameKnobs(oldDelegate.knobs);

  bool _sameKnobs(List<(int, bool, Offset, double)> other) {
    if (other.length != knobs.length) return false;
    for (var i = 0; i < knobs.length; i++) {
      if (knobs[i] != other[i]) return false;
    }
    return true;
  }
}

/// Perspective/orthographic toggle shown with the orientation gizmo.
class ProjectionToggle extends StatelessWidget {
  const ProjectionToggle({
    super.key,
    required this.orthographic,
    required this.onChanged,
  });

  final bool orthographic;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: orthographic
          ? 'Orthographic (switch to perspective)'
          : 'Perspective (switch to orthographic)',
      child: InkWell(
        onTap: () => onChanged(!orthographic),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 24,
          decoration: BoxDecoration(
            color: orthographic
                ? Theme.of(context).colorScheme.primary
                : Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            orthographic ? Icons.grid_on : Icons.vrpano_outlined,
            size: 15,
            color: orthographic ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
