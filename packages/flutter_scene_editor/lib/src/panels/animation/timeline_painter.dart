// Split out of animation_panel.dart; see the owning library there.
part of '../animation_panel.dart';

/// Draws the ruler, lane rows, keyframe diamonds, and playhead.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.scheme,
    required this.rows,
    required this.duration,
    required this.playhead,
    required this.selectedKey,
    required this.dragFromTime,
    required this.labelWidth,
    required this.scrollPx,
    required this.pxPerSecond,
  });

  final ColorScheme scheme;
  final List<_LaneRow> rows;
  final double duration;
  final double playhead;
  final TimelineKey? selectedKey;

  /// Original time of a keyframe being dragged, so the painter hides its old
  /// diamond and renders the dragging copy at the in-flight position.
  final double? dragFromTime;
  final double labelWidth;

  /// Left edge of the visible window, in pixels (0 = the lane's left edge,
  /// right after the label column). Mirrors the viewport's pixel-based
  /// `_scroll` so painted content, hit-testing, and scrolling all agree.
  final double scrollPx;

  /// Horizontal scale in px/s (fit-to-width when unzoomed).
  final double pxPerSecond;

  static const double _laneLeftPad = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = scheme.surfaceContainerLow,
    );

    // Ruler. Ticks cover only the visible window.
    final rulerBottom = Offset(size.width, _rulerHeight);
    canvas.drawLine(
      const Offset(0, _rulerHeight),
      rulerBottom,
      Paint()..color = scheme.outlineVariant,
    );
    final visibleSeconds = (size.width - labelWidth - 8) / pxPerSecond;
    final step = _niceStep(visibleSeconds);
    final tStart = scrollPx / pxPerSecond;
    final tEnd = tStart + visibleSeconds;
    for (
      var t = (tStart / step).floorToDouble() * step;
      t <= tEnd + 1e-6;
      t += step
    ) {
      // Ticks run across the whole visible window; those past the clip's end
      // are dimmed — that region is empty time the clip can grow into.
      if (t < -1e-6) continue;
      final inClip = t <= duration + 1e-6;
      final tickStyle = Paint()
        ..color = scheme.outline.withValues(alpha: inClip ? 0.5 : 0.22)
        ..strokeWidth = 1;
      final x = labelWidth + t * pxPerSecond - scrollPx;
      canvas.drawLine(Offset(x, 0), Offset(x, _rulerHeight - 3), tickStyle);
      TextPainter(
          text: TextSpan(
            text: t.toStringAsFixed(step < 0.25 ? 2 : 1),
            style: TextStyle(
              fontSize: 9,
              color: scheme.outline.withValues(alpha: inClip ? 1.0 : 0.45),
            ),
          ),
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, Offset(x + 2, 1));
    }

    // Clip-end boundary between the clip and the empty region past it.
    final clipEndX = labelWidth + duration * pxPerSecond - scrollPx;
    if (clipEndX >= labelWidth && clipEndX <= size.width) {
      canvas.drawLine(
        Offset(clipEndX, 0),
        Offset(clipEndX, size.height),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1,
      );
    }

    // Rows. Each node gets a full-width header band plus a hairline separator
    // closing the previous group, so a multi-node rig reads as distinct
    // blocks; property lanes sit indented beneath their node's header.
    var sawChannelInGroup = false;
    for (var row = 0; row < rows.length; row++) {
      final entry = rows[row];
      final top = _rulerHeight + row * _rowHeight;
      if (entry.isHeader) {
        if (sawChannelInGroup) {
          canvas.drawLine(
            Offset(0, top),
            Offset(size.width, top),
            Paint()..color = scheme.outlineVariant.withValues(alpha: 0.7),
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, _rowHeight),
          Paint()
            ..color = scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        );
        TextPainter(
            text: TextSpan(
              text: entry.title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )
          ..layout(maxWidth: labelWidth - 10)
          ..paint(canvas, Offset(2, top + (_rowHeight - 11) / 2));
        sawChannelInGroup = false;
      } else {
        TextPainter(
            text: TextSpan(
              text: entry.title,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )
          // End before the lane's ✕ button (left: labelWidth - 20), which
          // shares the label column with this title.
          ..layout(maxWidth: labelWidth - 36)
          ..paint(canvas, Offset(12, top + (_rowHeight - 11) / 2));
        sawChannelInGroup = true;
      }
    }

    // Lane content (lines, diamonds) is clipped to the lane column so
    // scrolled-out keys never paint over the labels. Headers carry no lane.
    final laneClip = Rect.fromLTRB(
      labelWidth,
      0,
      size.width - 8 + _laneLeftPad,
      size.height,
    );
    canvas.save();
    canvas.clipRect(laneClip);
    for (var row = 0; row < rows.length; row++) {
      final entry = rows[row];
      if (entry.isHeader) continue;
      final channel = entry.channel!;
      final top = _rulerHeight + row * _rowHeight;
      canvas.drawLine(
        Offset(labelWidth + _laneLeftPad, top + _rowHeight / 2),
        Offset(
          labelWidth + _laneLeftPad + duration * pxPerSecond - scrollPx,
          top + _rowHeight / 2,
        ),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1.5,
      );

      // Keyframe diamonds (only those inside the visible window).
      for (final time in entry.times!) {
        // A lifted keyframe (mid-drag) hides its old diamond on its own
        // channel only — other channels legitimately hold keys at the same
        // time, and theirs must stay visible. The dragging copy is drawn at
        // the cursor's in-flight time right after, on the dragged channel.
        if (dragFromTime != null &&
            selectedKey != null &&
            channel.target == selectedKey!.target &&
            channel.property == selectedKey!.property &&
            (time - dragFromTime!).abs() <= 1e-3) {
          continue;
        }
        final x = labelWidth + time * pxPerSecond - scrollPx;
        if (x < labelWidth - 6 || x > size.width - 2) continue;
        _drawDiamond(
          canvas,
          x,
          top + _rowHeight / 2,
          selectedKey != null &&
              selectedKey!.target == channel.target &&
              selectedKey!.property == channel.property &&
              (selectedKey!.time - time).abs() <= 1e-3,
        );
      }

      // The keyframe being dragged renders at its in-flight position so the
      // diamond follows the cursor until the move is committed on release.
      if (dragFromTime != null &&
          selectedKey != null &&
          selectedKey!.target == channel.target &&
          selectedKey!.property == channel.property) {
        final x = labelWidth + selectedKey!.time * pxPerSecond - scrollPx;
        if (x >= labelWidth - 6 && x <= size.width - 2) {
          _drawDiamond(canvas, x, top + _rowHeight / 2, true);
        }
      }
    }

    // Playhead (clipped to the visible window).
    if (playhead >= tStart && playhead <= tEnd) {
      final x = labelWidth + playhead * pxPerSecond - scrollPx;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = scheme.primary
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(x, 5), 4, Paint()..color = scheme.primary);
    }
    canvas.restore();
  }

  void _drawDiamond(Canvas canvas, double cx, double cy, bool selected) {
    if (selected) {
      canvas.drawCircle(
        Offset(cx, cy),
        8,
        Paint()..color = scheme.primary.withValues(alpha: 0.25),
      );
    }
    final path = Path()
      ..moveTo(cx, cy - 5.5)
      ..lineTo(cx + 5.5, cy)
      ..lineTo(cx, cy + 5.5)
      ..lineTo(cx - 5.5, cy)
      ..close();
    // The fill alone can sit near-identical to the lane band and its line
    // (surfaceContainerLow / outlineVariant vs secondary), so every crystal
    // carries a thin foreground outline that reads on any surface tone.
    canvas.drawPath(
      path,
      Paint()..color = selected ? scheme.primary : scheme.secondary,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = scheme.onSurface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// A ruler step near [duration] / 8 that keeps readable labels.
  double _niceStep(double duration) {
    if (duration <= 0) return 1;
    final raw = duration / 8;
    const steps = [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0];
    for (final step in steps) {
      if (raw <= step) return step;
    }
    return 60;
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.playhead != playhead ||
      oldDelegate.selectedKey != selectedKey ||
      oldDelegate.dragFromTime != dragFromTime ||
      oldDelegate.duration != duration ||
      oldDelegate.scrollPx != scrollPx ||
      oldDelegate.pxPerSecond != pxPerSecond ||
      !identical(oldDelegate.rows, rows);
}
