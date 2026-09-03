// Split out of animation_panel.dart; see the owning library there.
part of '../animation_panel.dart';

/// Draws the ruler, lane rows, keyframe diamonds, and playhead.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.scheme,
    required this.rows,
    required this.duration,
    required this.playhead,
    required this.selectedKeys,
    required this.dragFromKeys,
    required this.labelWidth,
    required this.scrollPx,
    required this.pxPerSecond,
  });

  final ColorScheme scheme;
  final List<_LaneRow> rows;
  final double duration;
  final double playhead;
  final Set<TimelineKey> selectedKeys;

  /// Original keys being dragged, so the painter hides their old diamonds and
  /// renders dragging copies at the in-flight positions.
  final Set<TimelineKey>? dragFromKeys;
  final double labelWidth;

  /// Left edge of the visible window, in pixels (0 = the lane's left edge,
  /// right after the label column). Mirrors the viewport's pixel-based
  /// `_scroll` so painted content, hit-testing, and scrolling all agree.
  final double scrollPx;

  /// Horizontal scale in px/s (fit-to-width when unzoomed).
  final double pxPerSecond;

  static const double _laneLeftPad = 4;

  /// Laid-out label cache. Painting relayouts every ruler tick and row title
  /// on each playhead frame otherwise, which dominates the paint pass during
  /// playback; label texts only change with zoom/scroll and color with the
  /// clip boundary, so key on (text, color, size, weight, layout width) and
  /// reuse the laid-out painter. Cleared wholesale when it grows stale.
  static final Map<
    (String, int, double, FontWeight, double?),
    TextPainter
  > _labelCache = {};

  static TextPainter _cachedLabel(
    String text, {
    required Color color,
    double fontSize = 11,
    FontWeight? fontWeight,
    double? maxWidth,
  }) {
    final key = (
      text,
      color.toARGB32(),
      fontSize,
      fontWeight ?? FontWeight.w400,
      maxWidth,
    );
    final cached = _labelCache[key];
    if (cached != null) return cached;
    if (_labelCache.length > 256) _labelCache.clear();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: maxWidth == null ? null : '…',
    );
    if (maxWidth != null) {
      painter.layout(maxWidth: maxWidth);
    } else {
      painter.layout();
    }
    return _labelCache[key] = painter;
  }

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
      _cachedLabel(
        t.toStringAsFixed(step < 0.25 ? 2 : 1),
        color: scheme.outline.withValues(alpha: inClip ? 1.0 : 0.45),
        fontSize: 9,
      ).paint(canvas, Offset(x + 2, 1));
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
        _cachedLabel(
          entry.title,
          color: scheme.primary,
          fontWeight: FontWeight.w600,
          maxWidth: labelWidth - 10,
        ).paint(canvas, Offset(2, top + (_rowHeight - 11) / 2));
        sawChannelInGroup = false;
      } else {
        // End before the lane's ✕ button (left: labelWidth - 20), which
        // shares the label column with this title.
        _cachedLabel(
          entry.title,
          color: scheme.onSurfaceVariant,
          maxWidth: labelWidth - 36,
        ).paint(canvas, Offset(12, top + (_rowHeight - 11) / 2));
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
        // Dragged keyframes hide their original diamonds on their own
        // channels only — other channels legitimately hold keys at the same
        // time, and theirs must stay visible. The dragging copies are drawn
        // at the cursor's in-flight times right after, on the dragged
        // channels.
        final draggingFrom =
            dragFromKeys?.any(
              (k) =>
                  k.target == channel.target &&
                  k.property == channel.property &&
                  (k.time - time).abs() <= 1e-3,
            ) ??
            false;
        if (draggingFrom) continue;
        final x = labelWidth + time * pxPerSecond - scrollPx;
        if (x < labelWidth - 6 || x > size.width - 2) continue;
        _drawDiamond(
          canvas,
          x,
          top + _rowHeight / 2,
          selectedKeys.any(
            (k) =>
                k.target == channel.target &&
                k.property == channel.property &&
                (k.time - time).abs() <= 1e-3,
          ),
        );
      }

      // Keyframes being dragged render at their in-flight positions so the
      // diamonds follow the cursor until the moves are committed on release.
      if (dragFromKeys != null) {
        for (final key in dragFromKeys!) {
          if (key.target != channel.target ||
              key.property != channel.property) {
            continue;
          }
          final x = labelWidth + key.time * pxPerSecond - scrollPx;
          if (x >= labelWidth - 6 && x <= size.width - 2) {
            _drawDiamond(canvas, x, top + _rowHeight / 2, true);
          }
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
      !setEquals(oldDelegate.selectedKeys, selectedKeys) ||
      !setEquals(oldDelegate.dragFromKeys, dragFromKeys) ||
      oldDelegate.duration != duration ||
      oldDelegate.scrollPx != scrollPx ||
      oldDelegate.pxPerSecond != pxPerSecond ||
      !identical(oldDelegate.rows, rows);
}
