// Split out of animation_panel.dart; see the owning library there.
part of '../animation_panel.dart';

/// The keyframe editor: a time ruler plus one lane per channel, a draggable
/// playhead, and diamonds per keyframe. Diamonds drag to retime (committed as
/// one undoable move on release), lanes scrub the playhead, and double-tapping
/// a lane adds a keyframe capturing the target's current pose.
class AnimationTimeline extends StatefulWidget {
  const AnimationTimeline({
    super.key,
    required this.controller,
    required this.animation,
    required this.duration,
    required this.selectedKey,
    required this.draggingKey,
    this.dragFromTime,
    required this.onTapLane,
    required this.onScrub,
    required this.onSelectKey,
    required this.onDragKeyStart,
    required this.onDragKeyUpdate,
    required this.onDragKeyEnd,
    required this.onDoubleTapLane,
    this.onRemoveChannel,
  });

  final EditorController controller;
  final AnimationSpec animation;
  final double duration;

  /// The highlighted keyframe (its time already includes any in-flight drag).
  final TimelineKey? selectedKey;

  /// Whether a key drag is in flight (pan moves the diamond, not the
  /// playhead).
  final bool draggingKey;

  /// The dragged keyframe's original time, so its old diamond is hidden while
  /// it is re-rendered at the cursor's in-flight position. Null when no drag
  /// is in progress.
  final double? dragFromTime;

  final ValueChanged<double> onTapLane;
  final ValueChanged<double> onScrub;
  final ValueChanged<TimelineKey> onSelectKey;
  final ValueChanged<TimelineKey> onDragKeyStart;
  final ValueChanged<double> onDragKeyUpdate;
  final VoidCallback onDragKeyEnd;
  final void Function(AnimationChannelSpec channel, double time)
  onDoubleTapLane;

  /// Removes an entire channel (a node/property path) from the animation —
  /// the lane's ✕ button. Null hides those buttons (bare-timeline embeds
  /// without editing chrome).
  final void Function(AnimationChannelSpec channel)? onRemoveChannel;

  @override
  State<AnimationTimeline> createState() => _AnimationTimelineState();
}

class _AnimationTimelineState extends State<AnimationTimeline> {
  /// Horizontal zoom as a multiple of fit-to-width; null fits the whole clip
  /// to the pane width. Stored as a factor (not an absolute px/s) so resizing
  /// the pane rescales the timeline at the same zoom percentage.
  double? _zoomFactor;

  /// Left edge of the visible window, in seconds.
  double _scroll = 0;

  /// Cumulative scale of an in-flight trackpad pinch; null when none.
  double? _pinchScale;

  /// Vertical content scroll (px) for rigs taller than the pane; 0 when the
  /// whole timeline fits. See `_buildCanvas` for how it is applied and driven.
  double _scrollY = 0;

  /// Whether the in-flight pan is a vertical content scroll (started on the
  /// label column while the lanes overflow the pane) rather than a scrub or
  /// key drag.
  bool _scrollPan = false;

  EditorController get controller => widget.controller;
  AnimationSpec get animation => widget.animation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = controller.document;
    // One header row per animated node followed by that node's property
    // lanes, keeping each node's first-appearance order: a multi-node
    // animation reads as distinct blocks rather than interleaved channels.
    final nodeOrder = <LocalId>[];
    final channelIndexesByNode = <LocalId, List<int>>{};
    for (var i = 0; i < animation.channels.length; i++) {
      final target = animation.channels[i].target;
      final bucket = channelIndexesByNode[target];
      if (bucket == null) {
        channelIndexesByNode[target] = [i];
        nodeOrder.add(target);
      } else {
        bucket.add(i);
      }
    }
    // A bone's lanes always read in the same order — translation, rotation,
    // scale — regardless of which channel happened to be authored first.
    int rankOf(AnimationProperty property) => switch (property) {
      AnimationProperty.translation => 0,
      AnimationProperty.rotation => 1,
      AnimationProperty.scale => 2,
      AnimationProperty.weights => 3,
    };
    for (final bucket in channelIndexesByNode.values) {
      bucket.sort((a, b) {
        final byRank = rankOf(
          animation.channels[a].property,
        ).compareTo(rankOf(animation.channels[b].property));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    }
    final rows = <_LaneRow>[
      for (final node in nodeOrder) ...[
        (
          isHeader: true,
          title: document.nodes[node]?.name ?? 'node',
          times: null,
          channel: null,
          groupChannels: [
            for (final i in channelIndexesByNode[node]!) animation.channels[i],
          ],
        ),
        for (final i in channelIndexesByNode[node]!)
          (
            isHeader: false,
            title: animation.channels[i].property.name,
            times: channelTimes(document, animation.channels[i]),
            channel: animation.channels[i],
            groupChannels: null,
          ),
      ],
    ];

    // The playhead listener now wraps only the canvas paint (see
    // _buildCanvas): per-tick updates repaint the diamonds and playhead via
    // the painter without rebuilding the header/label overlays, the panel,
    // or the parent editor.
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildCanvas(context, scheme, rows, constraints);
      },
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    ColorScheme scheme,
    List<_LaneRow> rows,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth;
    const labelWidth = 120.0;
    final laneWidth = math.max(width - labelWidth - 8, 24.0);
    // Fit-to-width unless the user has zoomed. The zoom floor sits below fit
    // so the window can show empty time past the clip's end; fit itself always
    // stays reachable. The zoom is kept as a multiple of fit so resizing the
    // pane rescales the timeline at the same zoom percentage.
    final fitViewport = TimelineViewport(
      laneWidth: laneWidth,
      duration: widget.duration,
    );
    final fitPxPerSecond = fitViewport.fitPxPerSecond;
    final zoomFactor = _zoomFactor;
    final viewport = TimelineViewport(
      laneWidth: laneWidth,
      duration: widget.duration,
      zoomPx: zoomFactor == null ? null : fitPxPerSecond * zoomFactor,
      scroll: _scroll,
    );
    final pxPerSecond = viewport.pxPerSecond;
    final maxScroll = viewport.maxScroll;
    _scroll = viewport.scroll;
    final contentHeight =
        _rulerHeight + math.max(rows.length, 1) * _rowHeight + 4;

    // Vertical overflow: rigs with many lanes exceed the pane height. The
    // content scrolls vertically (wheel, or a drag on the label column) while
    // the ruler stays pinned — it is painted above the translated content —
    // and the zoom pill and scrollbar stay fixed to the viewport. With tight
    // pane constraints this is a no-op and the wheel keeps panning time.
    final hasBoundedHeight = constraints.maxHeight.isFinite;
    final viewportHeight = hasBoundedHeight
        ? constraints.maxHeight
        : contentHeight;
    final verticalOverflow = hasBoundedHeight
        ? math.max(0.0, contentHeight - constraints.maxHeight)
        : 0.0;
    final scrollY = _scrollY.clamp(0.0, verticalOverflow).toDouble();

    double xOf(double time) => labelWidth + time * pxPerSecond - _scroll;

    // Times past the clip's end are reachable on purpose: a key dropped out
    // there extends the clip.
    double timeAt(Offset position) =>
        ((position.dx - labelWidth + _scroll) / pxPerSecond)
            .clamp(0.0, _maxKeyTime)
            .toDouble();

    int rowOf(double dy) => ((dy - _rulerHeight) / _rowHeight).floor();

    // Pointer events arrive in viewport coordinates; the content is
    // translated up by scrollY, so lane lookups need the content-space point.
    Offset contentPos(Offset position) =>
        Offset(position.dx, position.dy + scrollY);

    // Scales by [factor], keeping [anchorTime] fixed under its pixel column.
    void zoom(double factor, {double? anchorTime}) {
      final next = viewport.scaledBy(factor);
      if ((next - pxPerSecond).abs() < 1e-6) return;
      final anchor = anchorTime ?? (_scroll + laneWidth / 2) / pxPerSecond;
      setState(() {
        _zoomFactor = fitPxPerSecond > 0 ? next / fitPxPerSecond : _zoomFactor;
        _scroll = viewport.scrollForAnchor(anchor, next);
      });
    }

    // Wheel: plain scroll pans toward higher/lower times; ctrl/cmd+wheel
    // zooms around the cursor.
    void handleWheel(PointerSignalEvent event) {
      if (event is! PointerScrollEvent) return;
      final delta = event.scrollDelta.dy + event.scrollDelta.dx;
      if (delta == 0) return;
      final zooming =
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      if (zooming) {
        final anchor = timeAt(event.localPosition);
        zoom(math.exp(-delta * 0.002), anchorTime: anchor);
      } else if (verticalOverflow > 0 && event.scrollDelta.dy != 0) {
        // The rig is taller than the pane: the wheel scrolls the lanes
        // vertically; a horizontal wheel delta still pans time.
        setState(() {
          _scrollY = (_scrollY + event.scrollDelta.dy)
              .clamp(0.0, verticalOverflow)
              .toDouble();
          if (event.scrollDelta.dx != 0) {
            _scroll = (_scroll + event.scrollDelta.dx)
                .clamp(0.0, maxScroll)
                .toDouble();
          }
        });
      } else {
        setState(() {
          _scroll = (_scroll + delta).clamp(0.0, maxScroll).toDouble();
        });
      }
    }

    // Trackpad pinch: two-finger translation pans, spreading or pinching
    // scales around the window center.
    void handlePanZoomStart(PointerPanZoomStartEvent _) {
      _pinchScale = 1;
    }

    void handlePanZoomUpdate(PointerPanZoomUpdateEvent event) {
      final last = _pinchScale;
      if (last == null || last <= 0) return;
      _pinchScale = event.scale;
      if (event.panDelta.dx != 0) {
        setState(() {
          _scroll = (_scroll - event.panDelta.dx)
              .clamp(0.0, maxScroll)
              .toDouble();
        });
      }
      if ((event.scale - last).abs() > 1e-9) {
        zoom(event.scale / last);
      }
    }

    void handlePanZoomEnd(PointerPanZoomEndEvent _) {
      _pinchScale = null;
    }

    // Nearest keyframe within reach of the pointer, across all lanes — no
    // need to land precisely on a row. Group headers hold no keys.
    TimelineKey? hitKey(Offset position) {
      TimelineKey? nearest;
      var nearestDistance = double.infinity;
      for (var row = 0; row < rows.length; row++) {
        final entry = rows[row];
        final channel = entry.channel;
        if (entry.isHeader || channel == null) continue;
        final cy = _rulerHeight + row * _rowHeight + _rowHeight / 2;
        for (final time in entry.times!) {
          final dx = position.dx - xOf(time);
          final dy = position.dy - cy;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearest = (
              target: channel.target,
              property: channel.property,
              time: time,
            );
          }
        }
      }
      return nearestDistance <= 12 ? nearest : null;
    }

    // The scrollbar thumb: proportional to the visible fraction of the
    // content, positioned by scrollY. Only shown when the lanes overflow.
    final thumbHeight = math.min(
      viewportHeight,
      math.max(24.0, viewportHeight * viewportHeight / contentHeight),
    );
    final thumbTop = (scrollY / contentHeight * viewportHeight).clamp(
      0.0,
      viewportHeight - thumbHeight,
    );

    return Listener(
      onPointerSignal: handleWheel,
      onPointerPanZoomStart: handlePanZoomStart,
      onPointerPanZoomUpdate: handlePanZoomUpdate,
      onPointerPanZoomEnd: handlePanZoomEnd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final position = contentPos(details.localPosition);
          final key = hitKey(position);
          if (key != null) {
            widget.onSelectKey(key);
            return;
          }
          final row = rowOf(position.dy);
          if (row < 0 || row >= rows.length) return;
          // Tapping a node header neither seeks nor deselects; only lanes do.
          if (rows[row].isHeader) return;
          widget.onTapLane(timeAt(position));
        },
        onDoubleTapDown: (details) {
          final position = contentPos(details.localPosition);
          final row = rowOf(position.dy);
          if (row < 0 || row >= rows.length) return;
          final entry = rows[row];
          if (entry.isHeader || entry.channel == null) return;
          widget.onDoubleTapLane(entry.channel!, timeAt(details.localPosition));
        },
        onPanStart: (details) {
          final key = hitKey(contentPos(details.localPosition));
          if (key != null) {
            widget.onDragKeyStart(key);
            return;
          }
          // Dragging the label column pans the lanes vertically when they
          // overflow the pane; anywhere else the pan scrubs or drags keys.
          _scrollPan =
              verticalOverflow > 0 && details.localPosition.dx < labelWidth;
        },
        onPanUpdate: (details) {
          if (_scrollPan) {
            setState(() {
              _scrollY = (_scrollY - details.delta.dy)
                  .clamp(0.0, verticalOverflow)
                  .toDouble();
            });
            return;
          }
          // An in-flight key drag moves the diamond; anything else scrubs.
          if (widget.draggingKey) {
            widget.onDragKeyUpdate(details.delta.dx / pxPerSecond);
            return;
          }
          widget.onScrub(timeAt(details.localPosition));
        },
        onPanEnd: (_) {
          _scrollPan = false;
          widget.onDragKeyEnd();
        },
        child: SizedBox(
          width: width,
          height: viewportHeight,
          // The viewport Stack clips content outside its bounds; the inner
          // stack is content-sized and translated up by scrollY so its lane
          // rows scroll vertically. The ruler is painted at the top of the
          // content, so it scrolls with the time grid. The zoom pill and
          // scrollbar below are positioned in the viewport and never scroll.
          child: Stack(
            children: [
              Transform.translate(
                offset: Offset(0, -scrollY),
                child: SizedBox(
                  width: width,
                  height: contentHeight,
                  child: Stack(
                    children: [
                      // Repaint (and only repaint) on every playhead tick: the
                      // listener scopes to the canvas paint, so the overlays around it
                      // don't rebuild during playback.
                      ListenableBuilder(
                        listenable: controller.previewPlayhead,
                        builder: (context, _) => CustomPaint(
                          size: Size(width, contentHeight),
                          painter: _TimelinePainter(
                            scheme: scheme,
                            rows: rows,
                            duration: widget.duration,
                            playhead: controller.previewPlayhead.value,
                            selectedKey: widget.selectedKey,
                            dragFromTime: widget.dragFromTime,
                            labelWidth: labelWidth,
                            scrollPx: _scroll,
                            pxPerSecond: pxPerSecond,
                          ),
                        ),
                      ),
                      // Header and lane extras sit above the canvas paint, so their hit
                      // testing wins over the gesture handlers wrapping this stack
                      // (scrubbing, key drags).
                      for (var i = 0; i < rows.length; i++)
                        if (rows[i].isHeader &&
                            (rows[i].groupChannels?.isNotEmpty ?? false))
                          Positioned(
                            left: labelWidth + 6,
                            top:
                                _rulerHeight +
                                i * _rowHeight +
                                (_rowHeight - _interpControlHeight) / 2,
                            child: _groupInterpolationControl(
                              context,
                              rows[i].groupChannels!,
                            ),
                          ),
                      for (var i = 0; i < rows.length; i++)
                        if (!rows[i].isHeader && widget.onRemoveChannel != null)
                          Positioned(
                            left: labelWidth - 20,
                            top:
                                _rulerHeight +
                                i * _rowHeight +
                                (_rowHeight - 16) / 2,
                            child: _PanelTip(
                              message:
                                  'Remove this ${rows[i].title} path from this '
                                  'bone\'s timeline.\n\nThe channel and its keys are '
                                  'deleted; undoable like any edit.',
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 12,
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                onPressed: () =>
                                    widget.onRemoveChannel!(rows[i].channel!),
                                icon: const Icon(Icons.close, size: 12),
                                color: scheme.outline,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (verticalOverflow > 0)
                Positioned(
                  right: 2,
                  top: thumbTop,
                  child: Container(
                    width: 4,
                    height: thumbHeight,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 4,
                child: _zoomControls(context, scheme, zoom),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Height of the compact Lin | Step | Cubic pill inside a header row.
  static const double _interpControlHeight = 14;

  /// The per-bone interpolation mode: one control per node group, aligned
  /// with the bone's label row, driving every lane beneath it. Mixed groups
  /// select nothing until a mode is picked (which then applies to all).
  Widget _groupInterpolationControl(
    BuildContext context,
    List<AnimationChannelSpec> channels,
  ) {
    String normalize(AnimationInterpolation? value) =>
        value == AnimationInterpolation.step
        ? 'step'
        : value == AnimationInterpolation.cubic
        ? 'cubic'
        : 'linear';
    final common = normalize(channels.first.interpolation);
    final mixed = channels.any((c) => normalize(c.interpolation) != common);
    return _PanelTip(
      message:
          'How this bone\'s paths interpolate between keyframes.\n\n'
          'Linear blends smoothly; Step holds each key\'s value until the '
          'next one is reached; Cubic uses per-key tangents for eased '
          'motion.${mixed ? '\n\nThis bone\'s paths mix modes right now — '
                    'picking one applies it to all of them.' : ''}',
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'linear', label: Text('Lin')),
          ButtonSegment(value: 'step', label: Text('Step')),
          ButtonSegment(value: 'cubic', label: Text('Cubic')),
        ],
        selected: mixed ? const <String>{} : {common},
        emptySelectionAllowed: true,
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: WidgetStatePropertyAll(Size(0, _interpControlHeight)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
          textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 9)),
          side: WidgetStatePropertyAll(BorderSide(width: 0.5)),
        ),
        onSelectionChanged: (selection) {
          // Re-tapping the already-shown mode selects it again; keep that a
          // no-op. An empty selection (only reachable in mixed state) does
          // nothing until a mode is actually picked.
          final mode = selection.isEmpty ? null : selection.first;
          if (mode == null || (!mixed && mode == common)) return;
          unawaited(() async {
            for (final channel in channels) {
              try {
                await controller.run('setChannelInterpolation', {
                  'animationId': animation.id.toToken(),
                  'nodeId': channel.target.toToken(),
                  'property': channel.property.name,
                  if (channel.targetName != null)
                    'targetName': channel.targetName,
                  'interpolation': mode,
                });
              } on Exception catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          }());
        },
      ),
    );
  }

  /// The floating zoom pill: out / current scale / in / back-to-fit.
  Widget _zoomControls(
    BuildContext context,
    ColorScheme scheme,
    void Function(double factor, {double? anchorTime}) zoom,
  ) {
    final percent = ((_zoomFactor ?? 1.0) * 100).round();
    Widget control(IconData icon, String tip, VoidCallback onTap) => _PanelTip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.95),
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          control(
            Icons.zoom_out_map,
            'Zoom out (or ctrl/cmd + scroll wheel down)',
            () => zoom(1 / 1.3),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '$percent%',
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
            ),
          ),
          control(
            Icons.zoom_in,
            'Zoom in — easier to pick keyframes (or ctrl/cmd + wheel up)',
            () => zoom(1.3),
          ),
          control(
            Icons.center_focus_strong,
            'Fit the whole clip back into the panel',
            () => setState(() {
              _zoomFactor = null;
              _scroll = 0;
            }),
          ),
        ],
      ),
    );
  }
}
