/// The Animation dock panel: a keyframe timeline over the document's
/// animation clips.
///
/// Shows one row per channel, grouped by the node it drives, with a key
/// marker at each keyframe time. The playhead scrubs the clip through the
/// live scene, so the viewport shows the pose under the cursor rather than a
/// separate preview. Keys drag to retime, and the transport inserts and
/// deletes them at the playhead.
///
/// Every edit runs through the editor's animation commands, so it is
/// undoable and identical to the same edit made from a script or an agent.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'animation_timeline_model.dart';

/// Height of one channel row, and of the group header above each node's
/// channels. Matches the outliner's row rhythm so the two read as one program.
const double _rowHeight = 20;

/// Height of the time ruler above the sheet.
const double _rulerHeight = 22;

/// Width of the track-name column.
const double _trackColumnWidth = 220;

/// How far the sheet extends past the clip's last key, so there is room to
/// drag a key outward.
const double _tailSeconds = 0.5;

/// Identifies one keyframe: which channel, which key.
typedef _KeyRef = ({int channel, int key});

/// The Animation panel.
class AnimationPanel extends StatefulWidget {
  const AnimationPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel>
    with SingleTickerProviderStateMixin {
  EditorController get _ctrl => widget.controller;

  LocalId? _clipId;
  double _time = 0;
  bool _playing = false;
  bool _looping = true;
  int _sampleRate = 60;
  bool _curves = false;

  /// Horizontal zoom. Held rather than fitted per build so scrubbing does not
  /// rescale the sheet under the cursor.
  double _pixelsPerSecond = 120;
  final ScrollController _sheetScroll = ScrollController();
  final ScrollController _rowScroll = ScrollController();

  final Set<String> _collapsed = {};
  _KeyRef? _selectedKey;

  // A key being dragged: its channel and index, plus the time it is currently
  // shown at. The document is only written on release, so a drag is one undo
  // step rather than one per frame.
  _KeyRef? _draggingKey;
  double? _dragTime;

  Ticker? _ticker;
  Duration _lastTick = Duration.zero;

  // The clip driving the live scene, and what it was bound to, so a
  // re-realize or a clip switch rebinds instead of posing a dead graph.
  AnimationClip? _preview;
  Node? _previewRoot;
  String? _previewName;
  int _previewEpoch = -1;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onDocumentChanged);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(AnimationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onDocumentChanged);
      widget.controller.addListener(_onDocumentChanged);
    }
  }

  @override
  void dispose() {
    _detachPreview();
    _ticker?.dispose();
    _ctrl.removeListener(_onDocumentChanged);
    _sheetScroll.dispose();
    _rowScroll.dispose();
    super.dispose();
  }

  void _onDocumentChanged() {
    if (mounted) setState(() {});
  }

  // --- clip model ----------------------------------------------------------

  Map<LocalId, AnimationSpec> get _clips => _ctrl.document.animations;

  /// The selected clip, falling back to the first one so the panel is useful
  /// the moment a scene with animations is opened.
  AnimationSpec? get _clip {
    final clips = _clips;
    if (clips.isEmpty) return null;
    final selected = _clipId == null ? null : clips[_clipId];
    return selected ?? clips.values.first;
  }

  AnimationTimeline? _buildModel() {
    final clip = _clip;
    return clip == null ? null : buildAnimationTimeline(_ctrl.document, clip);
  }

  // --- live preview --------------------------------------------------------

  /// Binds (or rebinds) a clip on the realized root and seeks it to [_time].
  ///
  /// The engine's player applies a clip's pose every frame whether or not it
  /// is playing, so scrubbing is a seek: the viewport is already ticking, and
  /// the next frame shows the pose.
  void _syncPreview() {
    final clip = _clip;
    final root = _ctrl.realizedRoot;
    if (clip == null || root == null) {
      _detachPreview();
      return;
    }
    final stale =
        _preview == null ||
        !identical(_previewRoot, root) ||
        _previewName != clip.name ||
        _previewEpoch != _ctrl.realizeEpoch;
    if (stale) {
      _detachPreview();
      final animation = root.findAnimationByName(clip.name);
      if (animation == null) return;
      _preview = root.createAnimationClip(animation)..loop = _looping;
      _previewRoot = root;
      _previewName = clip.name;
      _previewEpoch = _ctrl.realizeEpoch;
    }
    final preview = _preview;
    if (preview == null) return;
    preview
      ..loop = _looping
      ..playing = false
      ..seek(_time);
  }

  void _detachPreview() {
    final preview = _preview;
    final root = _previewRoot;
    if (preview != null && root != null) root.removeAnimationClip(preview);
    _preview = null;
    _previewRoot = null;
    _previewName = null;
    _previewEpoch = -1;
  }

  // --- transport -----------------------------------------------------------

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (!_playing) return;
    final end = _buildModel()?.endTime ?? 0;
    var next = _time + delta;
    if (next > end) {
      if (_looping && end > 0) {
        next %= end;
      } else {
        next = end;
        _playing = false;
        _ticker?.stop();
      }
    }
    setState(() => _time = next);
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _lastTick = Duration.zero;
        _ticker
          ?..stop()
          ..start();
      } else {
        _ticker?.stop();
      }
    });
  }

  void _seek(double seconds) {
    final end = _buildModel()?.endTime ?? 0;
    setState(() => _time = seconds.clamp(0.0, math.max(end + _tailSeconds, 0)));
  }

  double _snap(double seconds) => snapToSamples(seconds, _sampleRate);

  void _jumpKey(AnimationTimeline model, {required bool forward}) {
    final next = adjacentKeyTime(model.keyTimes, _time, forward: forward);
    if (next != null) _seek(next);
  }

  // --- editing -------------------------------------------------------------

  /// Inserts a key at the playhead on the selected channel, or on every
  /// channel when nothing is selected: the transport's record button.
  Future<void> _insertKeyAtPlayhead(AnimationTimeline model) async {
    final selected = _selectedKey;
    final channels = selected == null
        ? [for (final track in model.tracks) track.channelIndex]
        : [selected.channel];
    for (final channel in channels) {
      final track = model.tracks.firstWhere((t) => t.channelIndex == channel);
      // An empty weights channel has no width until its first key declares
      // one, and this panel has nothing to declare it with.
      if (track.stride == 0) continue;
      await _ctrl.run(insertAnimationKey.name, {
        'animationId': model.id.toToken(),
        'channel': channel,
        'time': _snap(_time),
      });
    }
  }

  Future<void> _deleteSelectedKey(AnimationTimeline model) async {
    final selected = _selectedKey;
    if (selected == null) return;
    setState(() => _selectedKey = null);
    await _ctrl.run(deleteAnimationKey.name, {
      'animationId': model.id.toToken(),
      'channel': selected.channel,
      'key': selected.key,
    });
  }

  Future<void> _commitDrag(AnimationTimeline model) async {
    final key = _draggingKey;
    final time = _dragTime;
    setState(() {
      _draggingKey = null;
      _dragTime = null;
    });
    if (key == null || time == null) return;
    await _ctrl.run(setAnimationKeyTime.name, {
      'animationId': model.id.toToken(),
      'channel': key.channel,
      'key': key.key,
      'time': _snap(time),
    });
  }

  // --- layout --------------------------------------------------------------

  /// The rows the sheet draws, in order: a header per target followed by its
  /// channels, unless the target is collapsed.
  List<_Row> _rows(AnimationTimeline model) {
    final rows = <_Row>[];
    for (final target in model.targets) {
      rows.add(_Row.group(target));
      if (_collapsed.contains(target)) continue;
      for (final track in model.tracksFor(target)) {
        rows.add(_Row.track(track));
      }
    }
    return rows;
  }

  double _sheetWidth(AnimationTimeline model) =>
      math.max((model.endTime + _tailSeconds) * _pixelsPerSecond, 200);

  @override
  Widget build(BuildContext context) {
    final model = _buildModel();
    _syncPreview();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context, model),
        if (model == null)
          const Expanded(child: _EmptyState())
        else
          Expanded(child: _buildSheet(context, model)),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, AnimationTimeline? model) {
    final clips = _clips.values.toList();
    return Container(
      height: editorToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          _ClipSelector(
            clips: clips,
            selected: model?.id,
            onSelected: (id) => setState(() {
              _detachPreview();
              _clipId = id;
              _time = 0;
              _selectedKey = null;
            }),
            onCreate: () => _ctrl.run(createAnimation.name, {}),
          ),
          const SizedBox(width: 8),
          _TransportButton(
            icon: Icons.fiber_manual_record,
            tooltip: model == null
                ? 'Key the playhead'
                : 'Key the playhead on '
                      '${_selectedKey == null ? 'every channel' : 'the selected channel'}',
            color: editorErrorColor,
            onPressed: model == null ? null : () => _insertKeyAtPlayhead(model),
          ),
          _TransportButton(
            icon: Icons.first_page,
            tooltip: 'Go to start',
            onPressed: model == null ? null : () => _seek(0),
          ),
          _TransportButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous key',
            onPressed: model == null
                ? null
                : () => _jumpKey(model, forward: false),
          ),
          _TransportButton(
            icon: _playing ? Icons.pause : Icons.play_arrow,
            tooltip: _playing ? 'Pause' : 'Play',
            onPressed: model == null ? null : _togglePlay,
          ),
          _TransportButton(
            icon: Icons.chevron_right,
            tooltip: 'Next key',
            onPressed: model == null
                ? null
                : () => _jumpKey(model, forward: true),
          ),
          _TransportButton(
            icon: Icons.last_page,
            tooltip: 'Go to end',
            onPressed: model == null ? null : () => _seek(model.endTime),
          ),
          _TransportButton(
            icon: Icons.repeat,
            tooltip: 'Loop',
            active: _looping,
            onPressed: () => setState(() => _looping = !_looping),
          ),
          const SizedBox(width: 8),
          _NumberField(
            label: 'Frame',
            width: 54,
            value: (_time * _sampleRate).round().toDouble(),
            onChanged: (value) =>
                _seek(_sampleRate <= 0 ? value : value / _sampleRate),
          ),
          const SizedBox(width: 6),
          _NumberField(
            label: 'Samples',
            width: 48,
            value: _sampleRate.toDouble(),
            onChanged: (value) =>
                setState(() => _sampleRate = value.round().clamp(1, 240)),
          ),
          const Spacer(),
          _TransportButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete the selected key',
            onPressed: model == null || _selectedKey == null
                ? null
                : () => _deleteSelectedKey(model),
          ),
          const SizedBox(width: 8),
          _ViewToggle(
            curves: _curves,
            onChanged: (value) => setState(() => _curves = value),
          ),
        ],
      ),
    );
  }

  Widget _buildSheet(BuildContext context, AnimationTimeline model) {
    final rows = _rows(model);
    final width = _sheetWidth(model);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _trackColumnWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: _rulerHeight,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: editorLineColor),
                    right: BorderSide(color: editorLineColor),
                  ),
                ),
                child: Text(model.name, style: editorDetailText),
              ),
              Expanded(
                child: _TrackNameColumn(
                  rows: rows,
                  scroll: _rowScroll,
                  selectedChannel: _selectedKey?.channel,
                  collapsed: _collapsed,
                  onToggleGroup: (target) => setState(() {
                    if (!_collapsed.remove(target)) _collapsed.add(target);
                  }),
                  onRemoveTrack: (track) =>
                      _ctrl.run(removeAnimationChannel.name, {
                        'animationId': model.id.toToken(),
                        'channel': track.channelIndex,
                      }),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => _Timeline(
              model: model,
              rows: rows,
              width: math.max(width, constraints.maxWidth),
              pixelsPerSecond: _pixelsPerSecond,
              time: _time,
              sampleRate: _sampleRate,
              curves: _curves,
              selectedKey: _selectedKey,
              draggingKey: _draggingKey,
              dragTime: _dragTime,
              horizontalScroll: _sheetScroll,
              verticalScroll: _rowScroll,
              onScrub: _seek,
              onZoom: (factor) => setState(() {
                _pixelsPerSecond = (_pixelsPerSecond * factor).clamp(
                  8.0,
                  2000.0,
                );
              }),
              onSelectKey: (key) => setState(() => _selectedKey = key),
              onDragKey: (key, time) => setState(() {
                _draggingKey = key;
                _dragTime = math.max(0, time);
              }),
              onDragEnd: () => _commitDrag(model),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of the sheet: a target's group header, or one of its channels.
class _Row {
  _Row.group(this.target) : track = null;
  _Row.track(AnimationTrack this.track) : target = track.targetName;

  final String target;
  final AnimationTrack? track;

  bool get isGroup => track == null;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No animation clips in this scene.\n'
        'Import a model that carries them, or create an empty clip and add '
        'channels to it.',
        textAlign: TextAlign.center,
        style: editorDetailText,
      ),
    ),
  );
}

class _ClipSelector extends StatelessWidget {
  const _ClipSelector({
    required this.clips,
    required this.selected,
    required this.onSelected,
    required this.onCreate,
  });

  final List<AnimationSpec> clips;
  final LocalId? selected;
  final ValueChanged<LocalId> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: clips.isEmpty
              ? Text('No clips', style: editorDetailText)
              : DropdownButtonHideUnderline(
                  child: DropdownButton<LocalId>(
                    value: selected,
                    isDense: true,
                    isExpanded: true,
                    style: editorBodyText.copyWith(color: editorTextColor),
                    dropdownColor: editorRaisedColor,
                    items: [
                      for (final clip in clips)
                        DropdownMenuItem(
                          value: clip.id,
                          child: Text(
                            clip.name.isEmpty ? '(unnamed)' : clip.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null) onSelected(id);
                    },
                  ),
                ),
        ),
        _TransportButton(
          icon: Icons.add,
          tooltip: 'New clip',
          onPressed: onCreate,
        ),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.curves, required this.onChanged});

  final bool curves;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) => GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        color: curves == value ? editorRaisedColor : Colors.transparent,
        child: Text(
          label,
          style: editorBodyText.copyWith(
            color: curves == value ? editorTextColor : editorMutedTextColor,
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: editorLineColor),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [tab('Dopesheet', false), tab('Curves', true)]),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 15),
        color: active ? editorAccentColor : color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 24, height: 24),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }
}

/// A small labelled numeric field, committed on submit or focus loss.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.width,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double width;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _text = TextEditingController(
    text: _format(widget.value),
  );
  final FocusNode _focus = FocusNode();

  static String _format(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // While the field has focus the user's own text wins; otherwise track the
    // value, which the playhead moves continuously.
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_text.text);
    if (parsed == null) {
      _text.text = _format(widget.value);
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.label, style: editorMicroText),
        const SizedBox(width: 4),
        SizedBox(
          width: widget.width,
          height: 20,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            style: editorBodyText,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
      ],
    );
  }
}

/// The left column: a row per group header and channel, scrolled in lockstep
/// with the sheet.
class _TrackNameColumn extends StatelessWidget {
  const _TrackNameColumn({
    required this.rows,
    required this.scroll,
    required this.selectedChannel,
    required this.collapsed,
    required this.onToggleGroup,
    required this.onRemoveTrack,
  });

  final List<_Row> rows;
  final ScrollController scroll;
  final int? selectedChannel;
  final Set<String> collapsed;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<AnimationTrack> onRemoveTrack;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: editorLineColor)),
      ),
      child: ListView.builder(
        controller: scroll,
        itemExtent: _rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row.isGroup) {
            final isCollapsed = collapsed.contains(row.target);
            return InkWell(
              onTap: () => onToggleGroup(row.target),
              child: Row(
                children: [
                  Icon(
                    isCollapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 14,
                    color: editorMutedTextColor,
                  ),
                  Expanded(
                    child: Text(
                      row.target,
                      style: editorBodyText,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }
          final track = row.track!;
          final selected = selectedChannel == track.channelIndex;
          return Container(
            color: selected ? editorAccentColor.withValues(alpha: 0.14) : null,
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    track.property.name,
                    style: editorDetailText,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${track.times.length}', style: editorMicroText),
                IconButton(
                  icon: const Icon(Icons.close, size: 12),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 18,
                    height: 18,
                  ),
                  tooltip: 'Remove channel',
                  onPressed: () => onRemoveTrack(track),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The right-hand side: the time ruler, and beneath it either the dopesheet
/// or the curve view, both painted over the same time axis.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.model,
    required this.rows,
    required this.width,
    required this.pixelsPerSecond,
    required this.time,
    required this.sampleRate,
    required this.curves,
    required this.selectedKey,
    required this.draggingKey,
    required this.dragTime,
    required this.horizontalScroll,
    required this.verticalScroll,
    required this.onScrub,
    required this.onZoom,
    required this.onSelectKey,
    required this.onDragKey,
    required this.onDragEnd,
  });

  final AnimationTimeline model;
  final List<_Row> rows;
  final double width;
  final double pixelsPerSecond;
  final double time;
  final int sampleRate;
  final bool curves;
  final _KeyRef? selectedKey;
  final _KeyRef? draggingKey;
  final double? dragTime;
  final ScrollController horizontalScroll;
  final ScrollController verticalScroll;
  final ValueChanged<double> onScrub;
  final ValueChanged<double> onZoom;
  final ValueChanged<_KeyRef?> onSelectKey;
  final void Function(_KeyRef key, double time) onDragKey;
  final VoidCallback onDragEnd;

  /// The key nearest [position] within a grab radius, or null.
  ///
  /// Only a channel row's keys are grabbable. A group header shows a summary
  /// marker standing for several channels' keys at once, and dragging that
  /// would have to retime all of them.
  _KeyRef? _keyAt(Offset position) {
    final rowIndex = position.dy ~/ _rowHeight;
    if (rowIndex < 0 || rowIndex >= rows.length) return null;
    final row = rows[rowIndex];
    if (row.isGroup) return null;
    final track = row.track!;
    final key = nearestKeyIndex(
      track.times,
      position.dx / pixelsPerSecond,
      pixelsPerSecond: pixelsPerSecond,
    );
    return key == null ? null : (channel: track.channelIndex, key: key);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final zooming =
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
        if (zooming) {
          onZoom(event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1);
        } else if (horizontalScroll.hasClients) {
          final position = horizontalScroll.position;
          horizontalScroll.jumpTo(
            (position.pixels + event.scrollDelta.dy).clamp(
              0.0,
              position.maxScrollExtent,
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _rulerHeight,
            child: _ScrollSync(
              controller: horizontalScroll,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    onScrub(details.localPosition.dx / pixelsPerSecond),
                onHorizontalDragUpdate: (details) =>
                    onScrub(details.localPosition.dx / pixelsPerSecond),
                child: CustomPaint(
                  size: Size(width, _rulerHeight),
                  painter: _RulerPainter(
                    pixelsPerSecond: pixelsPerSecond,
                    sampleRate: sampleRate,
                    time: time,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: verticalScroll,
              child: _ScrollSync(
                controller: horizontalScroll,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    final key = _keyAt(details.localPosition);
                    onSelectKey(key);
                    if (key == null) {
                      onScrub(details.localPosition.dx / pixelsPerSecond);
                    }
                  },
                  onHorizontalDragStart: (details) {
                    final key = _keyAt(details.localPosition);
                    if (key == null) {
                      onScrub(details.localPosition.dx / pixelsPerSecond);
                      return;
                    }
                    onSelectKey(key);
                    onDragKey(key, details.localPosition.dx / pixelsPerSecond);
                  },
                  onHorizontalDragUpdate: (details) {
                    final key = draggingKey;
                    if (key == null) {
                      onScrub(details.localPosition.dx / pixelsPerSecond);
                      return;
                    }
                    onDragKey(key, details.localPosition.dx / pixelsPerSecond);
                  },
                  onHorizontalDragEnd: (_) => onDragEnd(),
                  onHorizontalDragCancel: onDragEnd,
                  child: CustomPaint(
                    size: Size(width, rows.length * _rowHeight),
                    painter: curves
                        ? _CurvePainter(
                            rows: rows,
                            pixelsPerSecond: pixelsPerSecond,
                            time: time,
                            selectedKey: selectedKey,
                          )
                        : _DopesheetPainter(
                            rows: rows,
                            pixelsPerSecond: pixelsPerSecond,
                            time: time,
                            selectedKey: selectedKey,
                            draggingKey: draggingKey,
                            dragTime: dragTime,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] in a horizontal scroll view driven by a shared [controller],
/// so the ruler and the sheet pan together.
class _ScrollSync extends StatelessWidget {
  const _ScrollSync({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    controller: controller,
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: child,
  );
}

/// Time ruler: a tick ladder whose spacing adapts to the zoom, labelled in
/// `m:ss` at the major ticks, plus the playhead.
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.pixelsPerSecond,
    required this.sampleRate,
    required this.time,
  });

  final double pixelsPerSecond;
  final int sampleRate;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = editorSurfaceColor;
    canvas.drawRect(Offset.zero & size, background);

    final major = majorTickStep(
      pixelsPerSecond: pixelsPerSecond,
      sampleRate: sampleRate,
    );
    final minor = major / 5;
    final tick = Paint()
      ..color = editorLineColor
      ..strokeWidth = 1;

    for (var t = 0.0; t * pixelsPerSecond <= size.width; t += minor) {
      final x = t * pixelsPerSecond;
      canvas.drawLine(Offset(x, size.height - 4), Offset(x, size.height), tick);
    }
    for (var t = 0.0; t * pixelsPerSecond <= size.width; t += major) {
      final x = t * pixelsPerSecond;
      canvas.drawLine(Offset(x, 6), Offset(x, size.height), tick);
      final label = TextPainter(
        text: TextSpan(text: formatTimelineLabel(t), style: editorMicroText),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(x + 3, 2));
    }

    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = editorLineColor,
    );
    _paintPlayhead(canvas, size, time * pixelsPerSecond);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pixelsPerSecond != pixelsPerSecond ||
      old.sampleRate != sampleRate ||
      old.time != time;
}

void _paintPlayhead(Canvas canvas, Size size, double x) {
  final paint = Paint()
    ..color = editorAccentColor
    ..strokeWidth = 1;
  canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  canvas.drawPath(
    Path()
      ..moveTo(x - 4, 0)
      ..lineTo(x + 4, 0)
      ..lineTo(x, 6)
      ..close(),
    Paint()..color = editorAccentColor,
  );
}

/// The dopesheet: a diamond per keyframe, one row per channel, with a summary
/// row above each target's channels.
class _DopesheetPainter extends CustomPainter {
  _DopesheetPainter({
    required this.rows,
    required this.pixelsPerSecond,
    required this.time,
    required this.selectedKey,
    required this.draggingKey,
    required this.dragTime,
  });

  final List<_Row> rows;
  final double pixelsPerSecond;
  final double time;
  final _KeyRef? selectedKey;
  final _KeyRef? draggingKey;
  final double? dragTime;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorPanelColor);

    final separator = Paint()..color = editorLineColor.withValues(alpha: 0.5);
    for (var i = 0; i < rows.length; i++) {
      final y = (i + 1) * _rowHeight - 0.5;
      if (rows[i].isGroup) {
        canvas.drawRect(
          Rect.fromLTWH(0, i * _rowHeight, size.width, _rowHeight),
          Paint()..color = editorRaisedColor.withValues(alpha: 0.45),
        );
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y), separator);
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final centerY = i * _rowHeight + _rowHeight / 2;
      if (row.isGroup) {
        // A group marker stands for every key its channels have at that
        // time, so a collapsed target still shows where its keys are.
        final times = <double>{};
        for (final other in rows) {
          if (other.isGroup || other.target != row.target) continue;
          times.addAll(other.track!.times);
        }
        for (final t in times) {
          _diamond(
            canvas,
            Offset(t * pixelsPerSecond, centerY),
            3.5,
            editorMutedTextColor,
          );
        }
        continue;
      }
      final track = row.track!;
      for (var key = 0; key < track.times.length; key++) {
        final dragging =
            draggingKey != null &&
            draggingKey!.channel == track.channelIndex &&
            draggingKey!.key == key;
        final t = dragging ? (dragTime ?? track.times[key]) : track.times[key];
        final selected =
            selectedKey != null &&
            selectedKey!.channel == track.channelIndex &&
            selectedKey!.key == key;
        _diamond(
          canvas,
          Offset(t * pixelsPerSecond, centerY),
          selected || dragging ? 5 : 4,
          selected || dragging ? editorAccentColor : editorTextColor,
        );
      }
    }

    _paintPlayhead(canvas, size, time * pixelsPerSecond);
  }

  static void _diamond(Canvas canvas, Offset center, double r, Color color) {
    canvas.drawPath(
      Path()
        ..moveTo(center.dx, center.dy - r)
        ..lineTo(center.dx + r, center.dy)
        ..lineTo(center.dx, center.dy + r)
        ..lineTo(center.dx - r, center.dy)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_DopesheetPainter old) => true;
}

/// The curve view: each channel's components drawn as polylines through their
/// keys, normalized per row so a translation in metres and a rotation in
/// quaternion units are both readable.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.rows,
    required this.pixelsPerSecond,
    required this.time,
    required this.selectedKey,
  });

  final List<_Row> rows;
  final double pixelsPerSecond;
  final double time;
  final _KeyRef? selectedKey;

  /// One color per component, reusing the transform axis palette so X, Y, and
  /// Z read the same here as on a gizmo. A fourth component (a quaternion's
  /// W, or a fifth morph target) falls back to the muted text color.
  static Color _componentColor(int component) =>
      component < editorAxisColors.length
      ? editorAxisColors[component]
      : editorMutedTextColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorPanelColor);
    final separator = Paint()..color = editorLineColor.withValues(alpha: 0.5);

    for (var i = 0; i < rows.length; i++) {
      final top = i * _rowHeight;
      canvas.drawLine(
        Offset(0, top + _rowHeight - 0.5),
        Offset(size.width, top + _rowHeight - 0.5),
        separator,
      );
      final row = rows[i];
      if (row.isGroup) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, _rowHeight),
          Paint()..color = editorRaisedColor.withValues(alpha: 0.45),
        );
        continue;
      }
      _paintTrack(canvas, row.track!, top);
    }

    _paintPlayhead(canvas, size, time * pixelsPerSecond);
  }

  void _paintTrack(Canvas canvas, AnimationTrack track, double top) {
    if (track.times.isEmpty || track.stride == 0) return;

    // Normalize each row to its own value range: the rows are 20 pixels tall,
    // so a shared scale would flatten every curve that is not the largest.
    var low = double.infinity;
    var high = -double.infinity;
    for (final v in track.values) {
      if (v < low) low = v;
      if (v > high) high = v;
    }
    final span = high - low;
    final padding = 3.0;
    double yFor(double value) {
      if (span <= 1e-9) return top + _rowHeight / 2;
      final normalized = (value - low) / span;
      return top +
          _rowHeight -
          padding -
          normalized * (_rowHeight - padding * 2);
    }

    for (var component = 0; component < track.stride; component++) {
      final path = Path();
      for (var key = 0; key < track.times.length; key++) {
        final point = Offset(
          track.times[key] * pixelsPerSecond,
          yFor(track.valueAt(key, component)),
        );
        if (key == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _componentColor(component)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      for (var key = 0; key < track.times.length; key++) {
        final selected =
            selectedKey != null &&
            selectedKey!.channel == track.channelIndex &&
            selectedKey!.key == key;
        canvas.drawCircle(
          Offset(
            track.times[key] * pixelsPerSecond,
            yFor(track.valueAt(key, component)),
          ),
          selected ? 3 : 2,
          Paint()
            ..color = selected ? editorAccentColor : _componentColor(component),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
