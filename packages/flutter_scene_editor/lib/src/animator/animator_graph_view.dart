/// The animator canvas: states as boxes, transitions as arrows.
///
/// The machine is a graph, and a list of states beside a list of transitions
/// is a graph you have to hold in your head. Drawn, the shape of a character's
/// movement is visible at a glance: which states are reachable, which one
/// everything falls back to, and which transition never fires because nothing
/// points at the state it leaves.
///
/// Pan with a drag on empty canvas, zoom with the wheel, drag a box to move
/// it, and alt-drag from a box onto another to wire a transition. While the
/// scene is playing, the state the machine is actually in is lit.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/editor_theme.dart';
import 'animator_document.dart';
import 'animator_graph_geometry.dart';

/// What the canvas currently has selected.
sealed class AnimatorSelection {
  const AnimatorSelection();
}

/// A state box.
class AnimatorStateSelection extends AnimatorSelection {
  const AnimatorStateSelection(this.name);
  final String name;
}

/// One arrow, by its index in the layer's transition list.
class AnimatorTransitionSelection extends AnimatorSelection {
  const AnimatorTransitionSelection(this.index);
  final int index;
}

/// The canvas.
class AnimatorGraphView extends StatefulWidget {
  const AnimatorGraphView({
    super.key,
    required this.layer,
    required this.selection,
    required this.onSelect,
    required this.onMoveState,
    required this.onConnect,
    required this.onAddState,
    required this.onSetInitial,
    this.activeState,
  });

  final AnimatorLayerGraph layer;
  final AnimatorSelection? selection;
  final ValueChanged<AnimatorSelection?> onSelect;

  /// A box was dragged. Called once on release, so a drag is one undo step.
  final void Function(String state, Offset position) onMoveState;

  /// A wire was dragged from one state onto another.
  final void Function(String from, String to) onConnect;

  /// Empty canvas was double-clicked, at [position].
  final void Function(Offset position) onAddState;

  /// A state was made the one the layer starts in.
  final ValueChanged<String> onSetInitial;

  /// The state the running machine is in, lit while the scene plays.
  final String? activeState;

  @override
  State<AnimatorGraphView> createState() => _AnimatorGraphViewState();
}

class _AnimatorGraphViewState extends State<AnimatorGraphView> {
  Offset _pan = const Offset(30, 30);
  double _zoom = 1;

  /// The box being dragged and where it is now, held locally so the document
  /// is written once on release rather than once a frame.
  String? _dragging;
  Offset? _dragPosition;

  /// A wire being pulled out of a state, and where the pointer is.
  String? _wiringFrom;
  Offset? _wireTo;

  /// Where the Any State box sits: pinned above the machine rather than
  /// stored, because it is not a state and has nothing to store it on.
  Rect get _anyStateRect => Rect.fromLTWH(
    40,
    -70,
    animatorAnyStateSize.width,
    animatorAnyStateSize.height,
  );

  Offset _toCanvas(Offset local) => (local - _pan) / _zoom;

  Rect _rectFor(AnimatorStateNode state) => animatorStateRect(
    state.name == _dragging ? _dragPosition! : state.position,
  );

  /// The state under [point] in canvas space, topmost first.
  AnimatorStateNode? _stateAt(Offset point) {
    for (final state in widget.layer.states.reversed) {
      if (_rectFor(state).contains(point)) return state;
    }
    return null;
  }

  /// The transition under [point], by index, or null.
  int? _transitionAt(Offset point) {
    for (final entry in _arrows().entries) {
      if (animatorArrowHit(entry.value.start, entry.value.end, point)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Every arrow, by transition index. A self-transition is excluded: it draws
  /// as a loop above its box rather than as a line between two.
  Map<int, AnimatorArrow> _arrows() {
    // Grouped by the unordered pair, so A to B and B to A spread apart from
    // each other rather than each thinking it is alone.
    final byPair = <String, List<int>>{};
    for (var i = 0; i < widget.layer.transitions.length; i++) {
      final transition = widget.layer.transitions[i];
      if (!transition.fromAny && transition.from == transition.to) continue;
      final from = transition.fromAny ? '' : transition.from!;
      final key = ([from, transition.to]..sort()).join(' ');
      byPair.putIfAbsent(key, () => []).add(i);
    }

    final arrows = <int, AnimatorArrow>{};
    for (final indices in byPair.values) {
      for (var ordinal = 0; ordinal < indices.length; ordinal++) {
        final index = indices[ordinal];
        final transition = widget.layer.transitions[index];
        final target = widget.layer.state(transition.to);
        if (target == null) continue;
        final source = transition.fromAny
            ? null
            : widget.layer.state(transition.from!);
        if (!transition.fromAny && source == null) continue;
        arrows[index] = animatorArrowBetween(
          source == null ? _anyStateRect : _rectFor(source),
          _rectFor(target),
          ordinal: ordinal,
          count: indices.length,
        );
      }
    }
    return arrows;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    setState(() {
      final before = _toCanvas(event.localPosition);
      _zoom = (_zoom * math.exp(-event.scrollDelta.dy / 320)).clamp(0.35, 2.5);
      // Keep whatever was under the cursor under the cursor.
      _pan = event.localPosition - before * _zoom;
    });
  }

  void _onTapDown(TapDownDetails details) {
    final point = _toCanvas(details.localPosition);
    final state = _stateAt(point);
    if (state != null) {
      widget.onSelect(AnimatorStateSelection(state.name));
      return;
    }
    final transition = _transitionAt(point);
    widget.onSelect(
      transition == null ? null : AnimatorTransitionSelection(transition),
    );
  }

  void _onDoubleTapDown(TapDownDetails details) {
    final point = _toCanvas(details.localPosition);
    final state = _stateAt(point);
    if (state != null) {
      // Double-clicking a state makes it the one the layer starts in, which
      // is a gesture every machine needs and no menu is worth.
      widget.onSetInitial(state.name);
      return;
    }
    widget.onAddState(point);
  }

  void _onPanStart(DragStartDetails details) {
    final point = _toCanvas(details.localPosition);
    final state = _stateAt(point);
    if (state == null) return;
    final wiring =
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    setState(() {
      if (wiring) {
        _wiringFrom = state.name;
        _wireTo = point;
      } else {
        _dragging = state.name;
        _dragPosition = state.position;
      }
    });
    widget.onSelect(AnimatorStateSelection(state.name));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      if (_wiringFrom != null) {
        _wireTo = _toCanvas(details.localPosition);
      } else if (_dragging != null) {
        _dragPosition = _dragPosition! + details.delta / _zoom;
      } else {
        _pan += details.delta;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    final wiringFrom = _wiringFrom;
    final wireTo = _wireTo;
    final dragging = _dragging;
    final dragPosition = _dragPosition;
    setState(() {
      _wiringFrom = null;
      _wireTo = null;
      _dragging = null;
      _dragPosition = null;
    });
    if (wiringFrom != null && wireTo != null) {
      final target = _stateAt(wireTo);
      if (target != null && target.name != wiringFrom) {
        widget.onConnect(wiringFrom, target.name);
      }
      return;
    }
    if (dragging != null && dragPosition != null) {
      widget.onMoveState(dragging, dragPosition);
    }
  }

  /// Puts the whole machine in view.
  void _frame(Size viewport) {
    final bounds = animatorGraphBounds([
      for (final state in widget.layer.states) state.position,
    ]);
    if (bounds == null) {
      setState(() {
        _pan = const Offset(30, 30);
        _zoom = 1;
      });
      return;
    }
    final padded = bounds.inflate(60);
    final scale = math
        .min(viewport.width / padded.width, viewport.height / padded.height)
        .clamp(0.35, 1.4);
    setState(() {
      _zoom = scale;
      _pan =
          Offset(viewport.width, viewport.height) / 2 - padded.center * scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Listener(
        onPointerSignal: _onPointerSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _onTapDown,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: () {},
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _AnimatorGraphPainter(
                    layer: widget.layer,
                    pan: _pan,
                    zoom: _zoom,
                    rectFor: _rectFor,
                    anyStateRect: _anyStateRect,
                    arrows: _arrows(),
                    selection: widget.selection,
                    activeState: widget.activeState,
                    wiringFrom: _wiringFrom == null
                        ? null
                        : widget.layer.state(_wiringFrom!),
                    wireTo: _wireTo,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _CanvasButtons(
                  onFrame: () => _frame(constraints.biggest),
                  onZoomIn: () =>
                      setState(() => _zoom = (_zoom * 1.2).clamp(0.35, 2.5)),
                  onZoomOut: () =>
                      setState(() => _zoom = (_zoom / 1.2).clamp(0.35, 2.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasButtons extends StatelessWidget {
  const _CanvasButtons({
    required this.onFrame,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onFrame;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: editorPanelColor.withValues(alpha: 0.9),
      border: Border.all(color: editorLineColor),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(Icons.zoom_out, 'Zoom out', onZoomOut),
        _button(Icons.zoom_in, 'Zoom in', onZoomIn),
        _button(Icons.center_focus_strong, 'Frame the machine', onFrame),
      ],
    ),
  );

  Widget _button(IconData icon, String tooltip, VoidCallback onPressed) =>
      IconButton(
        icon: Icon(icon, size: 15),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 26, height: 24),
        tooltip: tooltip,
        onPressed: onPressed,
      );
}

class _AnimatorGraphPainter extends CustomPainter {
  _AnimatorGraphPainter({
    required this.layer,
    required this.pan,
    required this.zoom,
    required this.rectFor,
    required this.anyStateRect,
    required this.arrows,
    required this.selection,
    required this.activeState,
    required this.wiringFrom,
    required this.wireTo,
  });

  final AnimatorLayerGraph layer;
  final Offset pan;
  final double zoom;
  final Rect Function(AnimatorStateNode) rectFor;
  final Rect anyStateRect;
  final Map<int, AnimatorArrow> arrows;
  final AnimatorSelection? selection;
  final String? activeState;
  final AnimatorStateNode? wiringFrom;
  final Offset? wireTo;

  static const Color _arrowColor = Color(0xFF6C7681);
  static const Color _anyStateFill = Color(0xFF3A4A42);
  static const Color _initialFill = Color(0xFF3A3322);
  static const Color _activeFill = Color(0xFF2E4A38);

  bool _stateSelected(String name) =>
      selection is AnimatorStateSelection &&
      (selection! as AnimatorStateSelection).name == name;

  bool _transitionSelected(int index) =>
      selection is AnimatorTransitionSelection &&
      (selection! as AnimatorTransitionSelection).index == index;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorSurfaceColor);
    canvas.save();
    canvas
      ..translate(pan.dx, pan.dy)
      ..scale(zoom);

    _paintGrid(canvas, size);
    _paintArrows(canvas);
    _paintSelfLoops(canvas);
    if (layer.transitions.any((t) => t.fromAny)) _paintAnyState(canvas);
    _paintStates(canvas);
    _paintPendingWire(canvas);

    canvas.restore();
  }

  void _paintGrid(Canvas canvas, Size size) {
    // The grid gives the pan something to move against; without it a drag on
    // empty canvas looks like nothing happened.
    const spacing = 40.0;
    final paint = Paint()
      ..color = editorLineColor.withValues(alpha: 0.28)
      ..strokeWidth = 1 / zoom;
    final left = (-pan.dx / zoom / spacing).floor() * spacing;
    final top = (-pan.dy / zoom / spacing).floor() * spacing;
    final right = left + size.width / zoom + spacing * 2;
    final bottom = top + size.height / zoom + spacing * 2;
    for (var x = left; x < right; x += spacing) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
    for (var y = top; y < bottom; y += spacing) {
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
  }

  void _paintArrows(Canvas canvas) {
    for (final entry in arrows.entries) {
      final selected = _transitionSelected(entry.key);
      final transition = layer.transitions[entry.key];
      final color = selected ? editorAccentColor : _arrowColor;
      canvas.drawLine(
        entry.value.start,
        entry.value.end,
        Paint()
          ..color = color
          ..strokeWidth = selected ? 2.4 : 1.6
          ..style = PaintingStyle.stroke,
      );
      _paintHead(canvas, entry.value.start, entry.value.end, color);
      // An unconditional transition fires the instant its state is entered,
      // which is worth seeing without having to open it.
      if (transition.conditions.isEmpty) {
        canvas.drawCircle(
          (entry.value.start + entry.value.end) / 2,
          3,
          Paint()..color = color,
        );
      }
    }
  }

  void _paintSelfLoops(Canvas canvas) {
    for (var i = 0; i < layer.transitions.length; i++) {
      final transition = layer.transitions[i];
      if (transition.fromAny || transition.from != transition.to) continue;
      final state = layer.state(transition.to);
      if (state == null) continue;
      final selected = _transitionSelected(i);
      canvas.drawArc(
        animatorSelfLoopBounds(rectFor(state)),
        math.pi * 0.15,
        math.pi * 1.7,
        false,
        Paint()
          ..color = selected ? editorAccentColor : _arrowColor
          ..strokeWidth = selected ? 2.4 : 1.6
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _paintAnyState(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(anyStateRect, const Radius.circular(16)),
      Paint()..color = _anyStateFill,
    );
    _paintLabel(canvas, anyStateRect, 'Any State', editorTextColor, 11);
  }

  void _paintStates(Canvas canvas) {
    for (final state in layer.states) {
      final rect = rectFor(state);
      final isInitial = layer.initial.isEmpty
          ? state.name == layer.states.first.name
          : state.name == layer.initial;
      final isActive = state.name == activeState;
      final selected = _stateSelected(state.name);

      canvas
        ..drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          Paint()
            ..color = isActive
                ? _activeFill
                : (isInitial ? _initialFill : editorRaisedColor),
        )
        ..drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(5)),
          Paint()
            ..color = selected
                ? editorAccentColor
                : (isActive
                      ? editorSuccessColor
                      : (isInitial ? editorWarningColor : editorLineColor))
            ..strokeWidth = selected ? 2 : 1.2
            ..style = PaintingStyle.stroke,
        );

      _paintLabel(
        canvas,
        Rect.fromLTWH(rect.left, rect.top + 5, rect.width, 18),
        state.name,
        editorTextColor,
        12.5,
      );
      _paintLabel(
        canvas,
        Rect.fromLTWH(rect.left, rect.top + 24, rect.width, 16),
        stateSubtitle(state),
        editorMutedTextColor,
        10.5,
      );
    }
  }

  void _paintPendingWire(Canvas canvas) {
    final from = wiringFrom;
    final to = wireTo;
    if (from == null || to == null) return;
    final start = animatorBorderPoint(rectFor(from), to);
    canvas.drawLine(
      start,
      to,
      Paint()
        ..color = editorAccentColor
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );
    _paintHead(canvas, start, to, editorAccentColor);
  }

  void _paintHead(Canvas canvas, Offset start, Offset end, Color color) {
    final head = animatorArrowHead(start, end);
    canvas.drawPath(
      Path()
        ..moveTo(head[0].dx, head[0].dy)
        ..lineTo(head[1].dx, head[1].dy)
        ..lineTo(head[2].dx, head[2].dy)
        ..close(),
      Paint()..color = color,
    );
  }

  void _paintLabel(
    Canvas canvas,
    Rect rect,
    String text,
    Color color,
    double size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: math.max(0, rect.width - 16));
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_AnimatorGraphPainter old) => true;
}

/// What a state's box says under its name: the clip, or what it blends across.
String stateSubtitle(AnimatorStateNode state) {
  if (state.blends) {
    final over = state.is2D
        ? '${state.blendParameter}, ${state.blendParameterY}'
        : '${state.blendParameter}';
    return 'blend of ${state.stops.length} over $over';
  }
  final clip = state.clip;
  return clip == null || clip.isEmpty ? 'no clip' : clip;
}
