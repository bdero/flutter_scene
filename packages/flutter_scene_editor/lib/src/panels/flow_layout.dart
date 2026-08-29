/// Where a flow graph's nodes, pins, and wires land on the canvas, and how
/// they are drawn.
///
/// Kept apart from the panel because it is arithmetic: given a graph and a
/// registry it says where everything is, which is what hit testing needs and
/// what the painter needs, and neither needs a widget to say it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/flow.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

import '../shell/editor_theme.dart';

/// A pin on a node, as the canvas refers to it.
typedef FlowPortRef = ({int node, String pin, bool isInput});

/// Node body metrics, in canvas units.
const double flowNodeWidth = 168;
const double flowHeaderHeight = 22;
const double flowRowHeight = 18;
const double flowPortRadius = 4.5;
const double flowGrabRadius = 9;

/// The colour a wire and its pins take, by what travels along them.
///
/// Exec is the pale one because it is the spine of a graph and should read
/// first; the data types are hued so a wire's kind is legible without
/// following it to either end.
Color flowTypeColor(FlowType type) => switch (type) {
  FlowType.exec => const Color(0xFFE8ECF0),
  FlowType.boolean => const Color(0xFFC0504E),
  FlowType.number => const Color(0xFF6FC96F),
  FlowType.integer => const Color(0xFF4EC9B0),
  FlowType.string => const Color(0xFFD98FD9),
  FlowType.vector3 => const Color(0xFFE0A84E),
  FlowType.nodeRef => const Color(0xFF4E86DE),
  FlowType.any => const Color(0xFF9099A2),
};

/// Where everything in [graph] sits.
class FlowLayout {
  FlowLayout(this.graph, this.registry);

  final FlowGraph graph;
  final FlowRegistry registry;

  /// How many rows a node's body has: the taller of its input and output
  /// columns, since the two run side by side.
  int rowsOf(FlowNodeType type) =>
      math.max(type.inputs.length, type.outputs.length);

  double heightOf(FlowNodeType type) =>
      flowHeaderHeight + rowsOf(type) * flowRowHeight + 6;

  Rect boundsOf(FlowNodeSpec node) {
    final type = registry[node.type];
    final height = type == null
        ? flowHeaderHeight + 6
        : heightOf(type);
    return Rect.fromLTWH(
      node.position.x,
      node.position.y,
      flowNodeWidth,
      height,
    );
  }

  /// The centre of a pin, in canvas space.
  ///
  /// Inputs run down the left edge and outputs down the right, each in
  /// declaration order, which is what makes a graph read left to right.
  Offset? portCentre(int nodeId, String pinId) {
    final node = graph.node(nodeId);
    if (node == null) return null;
    final type = registry[node.type];
    if (type == null) return null;
    final pin = type.pin(pinId);
    if (pin == null) return null;
    final column = pin.isInput ? type.inputs : type.outputs;
    final index = column.toList().indexWhere((p) => p.id == pinId);
    if (index < 0) return null;
    final y =
        node.position.y +
        flowHeaderHeight +
        index * flowRowHeight +
        flowRowHeight / 2;
    return Offset(
      node.position.x + (pin.isInput ? 0 : flowNodeWidth),
      y,
    );
  }

  /// The pin under [at], within a grab radius, or null.
  ///
  /// Searched newest node first, matching the paint order, so a pin on a node
  /// drawn over another is the one that gets grabbed.
  FlowPortRef? portAt(Offset at) {
    for (final node in graph.nodes.reversed) {
      final type = registry[node.type];
      if (type == null) continue;
      for (final pin in type.pins) {
        final centre = portCentre(node.id, pin.id);
        if (centre == null) continue;
        if ((centre - at).distance <= flowGrabRadius) {
          return (node: node.id, pin: pin.id, isInput: pin.isInput);
        }
      }
    }
    return null;
  }

  /// The node under [at], or null.
  int? nodeAt(Offset at) {
    for (final node in graph.nodes.reversed) {
      if (boundsOf(node).contains(at)) return node.id;
    }
    return null;
  }
}

/// Draws the canvas: grid, wires, nodes, and the wire being dragged.
class FlowCanvasPainter extends CustomPainter {
  FlowCanvasPainter({
    required this.graph,
    required this.registry,
    required this.pan,
    required this.zoom,
    required this.selected,
    required this.wireFrom,
    required this.wirePointer,
    this.trace,
  }) : layout = FlowLayout(graph, registry);

  final FlowGraph graph;
  final FlowRegistry registry;
  final Offset pan;
  final double zoom;
  final int? selected;
  final FlowPortRef? wireFrom;
  final Offset? wirePointer;

  /// What the last tick did, or null when nothing is being watched.
  ///
  /// The canvas draws the same graph either way; this is what turns it from a
  /// diagram of what could happen into a picture of what did.
  final FlowTrace? trace;
  final FlowLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorSurfaceColor);
    _paintGrid(canvas, size);

    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);

    for (final link in graph.links) {
      _paintWire(canvas, link);
    }
    final dragging = wireFrom;
    final pointer = wirePointer;
    if (dragging != null && pointer != null) {
      final start = layout.portCentre(dragging.node, dragging.pin);
      if (start != null) {
        _paintCurve(
          canvas,
          dragging.isInput ? pointer : start,
          dragging.isInput ? start : pointer,
          _typeColorOf(dragging).withValues(alpha: 0.8),
        );
      }
    }
    for (final node in graph.nodes) {
      _paintNode(canvas, node);
    }
    canvas.restore();
  }

  /// A grid that scrolls and scales with the canvas, so panning has something
  /// to read the motion against.
  void _paintGrid(Canvas canvas, Size size) {
    const spacing = 24.0;
    final step = spacing * zoom;
    if (step < 6) return;
    final paint = Paint()
      ..color = editorLineColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final firstX = pan.dx % step;
    final firstY = pan.dy % step;
    for (var x = firstX; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = firstY; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  FlowType _typeColorType(int nodeId, String pinId) {
    final node = graph.node(nodeId);
    final type = node == null ? null : registry[node.type];
    return type?.pin(pinId)?.type ?? FlowType.any;
  }

  Color _typeColorOf(FlowPortRef port) =>
      flowTypeColor(_typeColorType(port.node, port.pin));

  void _paintWire(Canvas canvas, FlowLink link) {
    final from = layout.portCentre(link.fromNode, link.fromPin);
    final to = layout.portCentre(link.toNode, link.toPin);
    if (from == null || to == null) return;
    final type = _typeColorType(link.fromNode, link.fromPin);
    final colour = flowTypeColor(type);
    final run = trace;
    if (run == null) {
      _paintCurve(canvas, from, to, colour);
      return;
    }

    // With a trace, a wire is one of three things, and telling them apart is
    // the whole point: it carried the run, it exists but the run went the
    // other way, or it is a data wire with a value on it.
    final isExec = type == FlowType.exec;
    final live = isExec
        ? run.didFire(link.fromNode, link.fromPin)
        : run.visitedNodes.contains(link.fromNode);
    _paintCurve(
      canvas,
      from,
      to,
      live ? colour : colour.withValues(alpha: 0.18),
      width: live && isExec ? 3.4 : 2.0,
    );
    if (isExec || !live) return;

    final value = run.valueOf(link.fromNode, link.fromPin);
    _paintWireLabel(canvas, (from + to) / 2, _short(value), colour);
  }

  /// The value a data wire is carrying, drawn on it.
  ///
  /// On the wire rather than in a side panel because the question is always
  /// "what went down *that* one", and a list of values keyed by node id is a
  /// second lookup the reader has to do by hand.
  void _paintWireLabel(
    Canvas canvas,
    Offset at,
    String text,
    Color colour,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 9, color: colour, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: at,
      width: painter.width + 8,
      height: painter.height + 4,
    );
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()..color = editorSurfaceColor.withValues(alpha: 0.92),
      )
      ..drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()
          ..color = colour.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    painter.paint(canvas, box.topLeft + const Offset(4, 2));
  }

  /// A value in the space a wire label has. Long text is cut rather than
  /// wrapped: a label that grows covers the graph it is describing.
  static String _short(Object? value) {
    if (value == null) return 'null';
    if (value is double) {
      return value == value.roundToDouble() && value.abs() < 1e6
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(3);
    }
    if (value is Vector3) {
      return '${_short(value.x)}, ${_short(value.y)}, ${_short(value.z)}';
    }
    final text = '$value';
    return text.length <= 18 ? text : '${text.substring(0, 17)}…';
  }

  /// A wire, as a horizontal-tangent bezier.
  ///
  /// The tangent grows with the horizontal gap so a short hop stays tight and
  /// a long one bows out of the way of what is between; a straight line
  /// between two pins on stacked nodes would run through both.
  void _paintCurve(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color, {
    double width = 1.8,
  }) {
    final reach = math.max(40.0, (to.dx - from.dx).abs() * 0.5);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..cubicTo(
        from.dx + reach,
        from.dy,
        to.dx - reach,
        to.dy,
        to.dx,
        to.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  void _paintNode(Canvas canvas, FlowNodeSpec node) {
    final type = registry[node.type];
    final bounds = layout.boundsOf(node);
    final isSelected = node.id == selected;

    final body = RRect.fromRectAndRadius(bounds, const Radius.circular(5));
    canvas
      ..drawRRect(body, Paint()..color = editorPanelColor)
      ..drawRRect(
        body,
        Paint()
          ..color = isSelected ? editorAccentColor : editorLineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 1.8 : 1,
      );

    // An event's header is tinted, because where a graph starts is the first
    // thing anyone looks for on a canvas full of boxes.
    final headerRect = Rect.fromLTWH(
      bounds.left,
      bounds.top,
      bounds.width,
      flowHeaderHeight,
    );
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(
        headerRect,
        Paint()
          ..color = (type?.isEvent ?? false)
              ? const Color(0xFF7A3A46)
              : editorRaisedColor,
      )
      ..restore();

    _text(
      canvas,
      type?.label ?? node.type,
      Offset(bounds.left + 8, bounds.top + 5),
      editorBodyText.copyWith(color: editorTextColor),
    );

    if (type == null) {
      _text(
        canvas,
        'unknown type',
        Offset(bounds.left + 8, bounds.top + flowHeaderHeight + 3),
        editorMicroText.copyWith(color: editorErrorColor),
      );
      return;
    }

    var row = 0;
    for (final pin in type.inputs) {
      _paintPin(canvas, node, pin, row++, isInput: true);
    }
    row = 0;
    for (final pin in type.outputs) {
      _paintPin(canvas, node, pin, row++, isInput: false);
    }
  }

  void _paintPin(
    Canvas canvas,
    FlowNodeSpec node,
    FlowPin pin,
    int row, {
    required bool isInput,
  }) {
    final centre = layout.portCentre(node.id, pin.id);
    if (centre == null) return;
    final color = flowTypeColor(pin.type);

    if (pin.type == FlowType.exec) {
      // Exec pins are triangles, so the spine of a graph is distinguishable
      // from its values at a glance rather than by colour alone.
      final path = Path()
        ..moveTo(centre.dx - 4, centre.dy - 5)
        ..lineTo(centre.dx + 5, centre.dy)
        ..lineTo(centre.dx - 4, centre.dy + 5)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas
        ..drawCircle(centre, flowPortRadius, Paint()..color = color)
        ..drawCircle(
          centre,
          flowPortRadius,
          Paint()
            ..color = editorSurfaceColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
    }

    if (pin.label.isEmpty) return;
    final style = editorMicroText.copyWith(color: editorMutedTextColor);
    final painter = TextPainter(
      text: TextSpan(text: pin.label, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: flowNodeWidth / 2 - 10);
    painter.paint(
      canvas,
      Offset(
        isInput
            ? centre.dx + 9
            : centre.dx - 9 - painter.width,
        centre.dy - painter.height / 2,
      ),
    );
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )
      ..layout(maxWidth: flowNodeWidth - 16)
      ..paint(canvas, at);
  }

  @override
  bool shouldRepaint(FlowCanvasPainter old) => true;
}
