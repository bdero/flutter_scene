import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart'
    show AnimationChange, ChangeSlot;
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_dialog.dart';

/// The Animation panel: author document animations and preview them live.
///
/// One animation loads onto the controller's playhead at a time. Transport
/// controls play, pause, scrub, and loop it; keyframe lanes show each
/// channel's keys, which drag to retime, double-tap to add (capturing the
/// target's current pose), and delete from the lane toolbar. Keying buttons
/// capture the selected nodes' current transforms at the playhead. Everything
/// commits through controller commands, so every edit is undoable and agent
/// visible.
class AnimationPanel extends StatefulWidget {
  const AnimationPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<AnimationPanel> createState() => _AnimationPanelState();
}

class _AnimationPanelState extends State<AnimationPanel> {
  // The keyframe the lane gestures target: its channel plus original time.
  ({LocalId target, AnimationProperty property, double time})? _selectedKey;

  // While a keyframe drag is in progress, the visual time offset from its
  // original position; committed as one moveAnimationKeyframe on release.
  double _dragOffset = 0;
  bool _dragging = false;

  EditorController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AnimationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    // A selected keyframe whose channel or time vanished (an undo, a delete)
    // drops back to no selection.
    final selected = _selectedKey;
    if (selected != null && !_keyExists(selected)) {
      _selectedKey = null;
    }
    setState(() {});
  }

  bool _keyExists(
    ({LocalId target, AnimationProperty property, double time}) key,
  ) {
    final id = _controller.previewAnimationId;
    if (id == null) return false;
    final spec = _controller.document.animations[id];
    if (spec == null) return false;
    for (final channel in spec.channels) {
      if (channel.target != key.target || channel.property != key.property) {
        continue;
      }
      for (final time in channelTimes(_controller.document, channel)) {
        if ((time - key.time).abs() <= 1e-3) return true;
      }
    }
    return false;
  }

  /// The animation the panel edits: the playhead's, else the document's
  /// first (kept valid across deletes and undos).
  LocalId? get _animationId {
    final controller = _controller;
    final loaded = controller.previewAnimationId;
    if (loaded != null && controller.document.animations.containsKey(loaded)) {
      return loaded;
    }
    final first = controller.document.animations.keys.isEmpty
        ? null
        : controller.document.animations.keys.first;
    return first;
  }

  AnimationSpec? get _animation {
    final id = _animationId;
    return id == null ? null : _controller.document.animations[id];
  }

  double get _duration {
    final id = _animationId;
    if (id == null) return 0;
    final duration = _controller.previewDuration(id);
    return duration > 0 ? duration : 1.0;
  }

  // -- actions ---------------------------------------------------------------

  Future<void> _createAnimation() async {
    try {
      final tx = await _controller.run('createAnimation', {});
      // Select the animation this transaction created.
      for (final record in tx.records) {
        if (record.slot == ChangeSlot.poolAnimation &&
            (record.oldValue as AnimationChange).value == null) {
          _controller.selectPreviewAnimation(record.targetId);
          return;
        }
      }
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteAnimation() async {
    final id = _animationId;
    if (id == null) return;
    try {
      await _controller.run('deleteAnimation', {'animationId': id.toToken()});
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Future<void> _renameAnimation(String name) async {
    final id = _animationId;
    if (id == null || name.trim().isEmpty) return;
    try {
      await _controller.run('renameAnimation', {
        'animationId': id.toToken(),
        'name': name.trim(),
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  /// Captures the selected nodes' current transforms at the playhead.
  Future<void> _keySelection(AnimationProperty? property) async {
    final id = _animationId;
    if (id == null) return;
    final time = _controller.previewTime;
    for (final nodeId in _controller.selection.ids) {
      if (!_controller.document.nodes.containsKey(nodeId)) continue;
      for (final p in property == null
          ? const [
              AnimationProperty.translation,
              AnimationProperty.rotation,
              AnimationProperty.scale,
            ]
          : [property]) {
        try {
          await _controller.run('setAnimationKeyframe', {
            'animationId': id.toToken(),
            'nodeId': nodeId.toToken(),
            'property': p.name,
            'time': time,
          });
        } on Exception catch (error) {
          _showError(error);
        }
      }
    }
  }

  Future<void> _deleteSelectedKey() async {
    final id = _animationId;
    final key = _selectedKey;
    if (id == null || key == null) return;
    try {
      await _controller.run('removeAnimationKeyframe', {
        'animationId': id.toToken(),
        'nodeId': key.target.toToken(),
        'property': key.property.name,
        'time': key.time,
      });
      setState(() => _selectedKey = null);
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Future<void> _moveSelectedKey(double toTime) async {
    final id = _animationId;
    final key = _selectedKey;
    if (id == null || key == null) return;
    final clamped = toTime.clamp(0.0, _duration).toDouble();
    if ((clamped - key.time).abs() <= 1e-4) return;
    try {
      await _controller.run('moveAnimationKeyframe', {
        'animationId': id.toToken(),
        'nodeId': key.target.toToken(),
        'property': key.property.name,
        'fromTime': key.time,
        'toTime': clamped,
      });
      setState(() {
        _selectedKey = (
          target: key.target,
          property: key.property,
          time: clamped,
        );
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animation = _animation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, scheme, animation),
        if (animation != null) ...[
          _transport(scheme),
          _keyBar(scheme),
          // Always-visible legend for the canvas gestures below.
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 10, bottom: 2),
            child: Text(
              'Drag the ruler or a lane to scrub · double-click a lane to add '
              'a key here · drag a diamond to retime it',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: scheme.outline,
                  ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                AnimationTimeline(
                  controller: _controller,
                  animation: animation,
                  duration: _duration,
                  draggingKey: _dragging,
                  selectedKey: (_dragging && _selectedKey != null)
                      ? (
                          target: _selectedKey!.target,
                          property: _selectedKey!.property,
                          time: _selectedKey!.time + _dragOffset,
                        )
                      : _selectedKey,
                  onTapLane: (time) {
                    setState(() => _selectedKey = null);
                    _controller.seekPreview(time);
                  },
                  onScrub: _controller.seekPreview,
                  onSelectKey: (key) => setState(() => _selectedKey = key),
                  onDragKeyStart: (key) => setState(() {
                    _selectedKey = key;
                    _dragging = true;
                    _dragOffset = 0;
                  }),
                  onDragKeyUpdate: (offset) =>
                      setState(() => _dragOffset = offset),
                  onDragKeyEnd: () {
                    final key = _selectedKey;
                    final offset = _dragOffset;
                    setState(() {
                      _dragging = false;
                      _dragOffset = 0;
                    });
                    if (key != null && offset != 0) {
                      unawaited(_moveSelectedKey(key.time + offset));
                    }
                  },
                  onDoubleTapLane: (channel, time) => _addKeyAt(channel, time),
                ),
                if (animation.channels.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.92),
                            border:
                                Border.all(color: scheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'No keyframes yet.\n\n'
                            '1. Select a node in the Outliner\n'
                            '2. Drag the playhead where the pose belongs\n'
                            '3. Pose the node with the viewport gizmo\n'
                            '4. Press Key — repeat at other times',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(height: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ] else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Animate a model in four steps:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Create an animation with + above.\n'
                    '2. Select a node in the Outliner.\n'
                    '3. Park the playhead, pose the node with the gizmo, '
                    'press Key.\n'
                    '4. Move the playhead and repeat — then press Play.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: _createAnimation,
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Create animation'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Adds one keyframe capturing the channel target's current pose.
  Future<void> _addKeyAt(
    AnimationChannelSpec channel,
    double time,
  ) async {
    try {
      await _controller.run('setAnimationKeyframe', {
        'animationId': _controller.previewAnimationId?.toToken() ??
            _animationId?.toToken(),
        'nodeId': channel.target.toToken(),
        'property': channel.property.name,
        'time': time.clamp(0.0, _duration).toDouble(),
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Widget _header(
    BuildContext context,
    ColorScheme scheme,
    AnimationSpec? animation,
  ) {
    final animations = _controller.document.animations;
    final id = _animationId;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 4),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          // Expanded + isExpanded keeps a long animation name from pushing
          // the action buttons out of the header row.
          Expanded(
            child: _PanelTip(
              message: 'The animation this panel edits and previews.\n\n'
                  'Pick one here after creating it with + below.',
              child: DropdownButton<LocalId>(
                value: id,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                hint: const Text('No animation'),
                items: [
                  for (final entry in animations.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value.name.isEmpty
                            ? entry.key.toToken()
                            : entry.value.name,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => _controller.selectPreviewAnimation(value),
              ),
            ),
          ),
          _PanelTip(
            message: 'Step-by-step guide to animating a model.',
            child: IconButton(
              tooltip: 'Animation help',
              icon: const Icon(Icons.help_outline, size: 16),
              onPressed: _showHelp,
            ),
          ),
          _PanelTip(
            message: 'Rename this animation.\n\nThe name is what you look up '
                'in code when you play the clip at runtime.',
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: animation == null ? null : () => _promptRename(),
            ),
          ),
          _PanelTip(
            message:
                'Delete this animation and all of its keyframes.\n\n'
                'Undoable like any edit.',
            child: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: animation == null ? null : _deleteAnimation,
            ),
          ),
          _PanelTip(
            message:
                'Create a new empty animation.\n\n'
                'Then select a node in the Outliner, pose it with the gizmo, '
                'and press Key to capture the pose.',
            child: IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: _createAnimation,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _promptRename() async {
    final animation = _animation;
    if (animation == null) return;
    final controller = TextEditingController(text: animation.name);
    final name = await showEditorDialog<String>(
      context,
      builder: (context) => AlertDialog(
        title: const Text('Rename animation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null) await _renameAnimation(name);
  }

  /// The walkthrough behind the header's ? button: the whole loop from
  /// empty scene to playing keyframes in an app.
  Future<void> _showHelp() async {
    await showEditorDialog<void>(
      context,
      builder: (context) => AlertDialog(
        title: const Text('Animating a model'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _helpStep(
                  '1 · Create',
                  'Press + in this panel\'s header to create an animation '
                  '(a named clip, e.g. "Spin"). Rename it to something you '
                  'will recognize in code.',
                ),
                _helpStep(
                  '2 · Pose',
                  'Select a node in the Outliner and pose it with the '
                  'viewport gizmo (move / rotate / scale).',
                ),
                _helpStep(
                  '3 · Key',
                  'Drag the playhead in this panel to where the pose belongs, '
                  'then press Key. That captures the node\'s translation, '
                  'rotation, and scale as one keyframe.',
                ),
                _helpStep(
                  '4 · Repeat',
                  'Move the playhead to another time, pose again, press Key '
                  'again. Between two keys the editor interpolates smoothly; '
                  'each lane row below shows one animated property with its '
                  'keys as diamonds.',
                ),
                _helpStep(
                  '5 · Preview',
                  'Press Play. Scrub by dragging the timeline. Stop restores '
                  'the nodes to their un-animated pose so you can keep '
                  'editing.',
                ),
                _helpStep(
                  '6 · Save & play',
                  'Save the scene — keyframes persist beside the .fscene in '
                  'a .fsceneb sidecar. In your app, load the scene and play '
                  'the clip from the root\'s parsedAnimations by name '
                  '(see the flutter_scene docs on AnimationClip).',
                ),
                const SizedBox(height: 8),
                Text(
                  'Every edit here is undoable (Cmd+Z) and also available to '
                  'agents through the same commands.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _helpStep(String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(body, style: const TextStyle(fontSize: 12, height: 1.45)),
      ],
    ),
  );

  Widget _transport(ColorScheme scheme) {
    final controller = _controller;
    final id = _animationId;
    final duration = _duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Row(
        children: [
          _PanelTip(
            message: controller.previewPlaying
                ? 'Pause the preview at the current frame.'
                : 'Play the preview in the viewport.\n\n'
                    'This is editor-only playback — what ships is the saved '
                    'keyframes, played by your app.',
            child: IconButton(
              icon: Icon(
                controller.previewPlaying ? Icons.pause : Icons.play_arrow,
                size: 20,
              ),
              onPressed: id == null ? null : controller.togglePreviewPlay,
            ),
          ),
          _PanelTip(
            message:
                'Stop: pause and put every animated node back to its authored '
                'pose (what you see in the Outliner and Inspector).',
            child: IconButton(
              icon: const Icon(Icons.stop, size: 20),
              onPressed: id == null ? null : controller.stopPreview,
            ),
          ),
          _PanelTip(
            message: controller.previewLoop
                ? 'Looping on: playback wraps at the clip\'s end.\n\n'
                    'Turn off to play once — useful for checking a single '
                    'pass frame by frame.'
                : 'Looping off: playback stops at the clip\'s end.\n\n'
                    'Turn on to preview continuously.',
            child: IconButton(
              icon: Icon(
                controller.previewLoop ? Icons.repeat : Icons.arrow_forward,
                size: 18,
              ),
              onPressed: id == null
                  ? null
                  : () => controller.setPreviewLoop(!controller.previewLoop),
            ),
          ),
          _PanelTip(
            message:
                'Preview playback speed.\n\nAffects only this panel\'s '
                'preview; keyframe times are unchanged.',
            child: PopupMenuButton<double>(
              initialValue: controller.previewSpeed,
              onSelected: controller.setPreviewSpeed,
              itemBuilder: (context) => [
                for (final speed in const [0.25, 0.5, 1.0, 2.0])
                  PopupMenuItem(
                    value: speed,
                    child: Text('$speed×'),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${controller.previewSpeed}×',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ),
          const Spacer(),
          // Playhead readout follows the tick notifier without rebuilding the
          // whole panel.
          Flexible(
            child: ListenableBuilder(
              listenable: controller.previewPlayhead,
              builder: (context, _) => Text(
                '${controller.previewTime.toStringAsFixed(2)} / '
                '${duration.toStringAsFixed(2)} s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyBar(ColorScheme scheme) {
    final hasSelection = _controller.selection.ids.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Row(
        children: [
          _PanelTip(
            message:
                'Key the pose: captures translation, rotation, and scale of '
                'every selected node at the playhead.\n\n'
                'How to use: select a node in the Outliner → drag the '
                'playhead to a time → move/rotate/scale it with the viewport '
                'gizmo → press Key. Move the playhead, pose again, press Key '
                'again — the animation interpolates between keys.',
            child: SizedBox(
              height: 26,
              child: FilledButton.tonalIcon(
                onPressed: (_animation == null || !hasSelection)
                    ? null
                    : () => unawaited(_keySelection(null)),
                icon: const Icon(Icons.key, size: 14),
                label: const Text('Key', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_selectedKey != null) ...[
            Flexible(
              child: Text(
                '${_nodeName(_selectedKey!.target)} · '
                '${_selectedKey!.property.name} @ '
                '${_selectedKey!.time.toStringAsFixed(2)}s',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Spacer(),
            _PanelTip(
              message: 'Delete this keyframe.\n\n'
                  'The channel interpolates across the gap; removing the last '
                  'key of a channel removes the channel.',
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                onPressed: _deleteSelectedKey,
              ),
            ),
          ] else
            Expanded(
              child: Text(
                hasSelection
                    ? 'Press Key to capture the selected nodes\' pose at the '
                        'playhead.'
                    : 'Select a node in the Outliner, then press Key to '
                        'capture its pose.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  String _nodeName(LocalId id) =>
      _controller.document.nodes[id]?.name ?? id.toToken();
}

/// One keyframe position on a timeline lane.
typedef TimelineKey = ({
  LocalId target,
  AnimationProperty property,
  double time,
});

const double _rulerHeight = 18;
const double _rowHeight = 22;

/// The keyframe times of [channel], read out of its timeline payload.
List<double> channelTimes(SceneDocument document, AnimationChannelSpec channel) {
  final bytes = document.payload(channel.timeline)?.bytes;
  if (bytes == null) return const [];
  final Float32List floats;
  if (bytes.offsetInBytes % 4 == 0) {
    floats = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
  } else {
    floats = Uint8List.fromList(bytes).buffer.asFloat32List(
      0,
      bytes.lengthInBytes ~/ 4,
    );
  }
  return [for (var i = 0; i < floats.length; i++) floats[i]];
}

/// The keyframe editor: a time ruler plus one lane per channel, a draggable
/// playhead, and diamonds per keyframe. Diamonds drag to retime (committed as
/// one undoable move on release), lanes scrub the playhead, and double-tapping
/// a lane adds a keyframe capturing the target's current pose.
class AnimationTimeline extends StatelessWidget {
  const AnimationTimeline({
    super.key,
    required this.controller,
    required this.animation,
    required this.duration,
    required this.selectedKey,
    required this.draggingKey,
    required this.onTapLane,
    required this.onScrub,
    required this.onSelectKey,
    required this.onDragKeyStart,
    required this.onDragKeyUpdate,
    required this.onDragKeyEnd,
    required this.onDoubleTapLane,
  });

  final EditorController controller;
  final AnimationSpec animation;
  final double duration;

  /// The highlighted keyframe (its time already includes any in-flight drag).
  final TimelineKey? selectedKey;

  /// Whether a key drag is in flight (pan moves the diamond, not the
  /// playhead).
  final bool draggingKey;

  final ValueChanged<double> onTapLane;
  final ValueChanged<double> onScrub;
  final ValueChanged<TimelineKey> onSelectKey;
  final ValueChanged<TimelineKey> onDragKeyStart;
  final ValueChanged<double> onDragKeyUpdate;
  final VoidCallback onDragKeyEnd;
  final void Function(AnimationChannelSpec channel, double time)
  onDoubleTapLane;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final document = controller.document;
    final labels = [
      for (final channel in animation.channels)
        '${document.nodes[channel.target]?.name ?? 'node'} · '
            '${channel.property.name}',
    ];
    final times = [
      for (final channel in animation.channels)
        channelTimes(document, channel),
    ];

    // Repaint on every playhead tick without rebuilding the parent panel.
    return ListenableBuilder(
      listenable: controller.previewPlayhead,
      builder: (context, _) =>
          LayoutBuilder(builder: (context, constraints) {
        return _buildCanvas(
          context,
          scheme,
          labels,
          times,
          constraints,
        );
      }),
    );
  }

  Widget _buildCanvas(
    BuildContext context,
    ColorScheme scheme,
    List<String> labels,
    List<List<double>> times,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth;
    const labelWidth = 120.0;
    final laneWidth = math.max(width - labelWidth - 8, 24.0);
    final pxPerSecond = laneWidth / duration;
    final contentHeight = _rulerHeight + math.max(times.length, 1) * _rowHeight + 4;

    int rowOf(double dy) => ((dy - _rulerHeight) / _rowHeight).floor();

    double timeAt(Offset position) =>
        ((position.dx - labelWidth) / pxPerSecond).clamp(0.0, duration).toDouble();

    TimelineKey? hitKey(Offset position) {
      final row = rowOf(position.dy);
      if (row < 0 || row >= times.length) return null;
      final channel = animation.channels[row];
      TimelineKey? nearest;
      var nearestDistance = double.infinity;
      for (final time in times[row]) {
        final dx = position.dx - (labelWidth + time * pxPerSecond);
        final dy =
            position.dy - (_rulerHeight + row * _rowHeight + _rowHeight / 2);
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
      return nearestDistance <= 9 ? nearest : null;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final position = details.localPosition;
        final key = hitKey(position);
        if (key != null) {
          onSelectKey(key);
          return;
        }
        final row = rowOf(position.dy);
        if (row < 0 || row >= times.length) return;
        onTapLane(timeAt(position));
      },
      onDoubleTapDown: (details) {
        final row = rowOf(details.localPosition.dy);
        if (row < 0 || row >= times.length) return;
        onDoubleTapLane(animation.channels[row], timeAt(details.localPosition));
      },
      onDoubleTap: () {},
      onPanStart: (details) {
        final key = hitKey(details.localPosition);
        if (key != null) onDragKeyStart(key);
      },
      onPanUpdate: (details) {
        // An in-flight key drag moves the diamond; anything else scrubs.
        if (draggingKey) {
          onDragKeyUpdate(details.delta.dx / pxPerSecond);
          return;
        }
        onScrub(timeAt(details.localPosition));
      },
      onPanEnd: (_) => onDragKeyEnd(),
      child: CustomPaint(
        size: Size(width, math.max(constraints.maxHeight, contentHeight)),
        painter: _TimelinePainter(
          scheme: scheme,
          animation: animation,
          labels: labels,
          times: times,
          duration: duration,
          playhead: controller.previewPlayhead.value,
          selectedKey: selectedKey,
          labelWidth: labelWidth,
        ),
      ),
    );
  }
}

/// Draws the ruler, lane rows, keyframe diamonds, and playhead.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.scheme,
    required this.animation,
    required this.labels,
    required this.times,
    required this.duration,
    required this.playhead,
    required this.selectedKey,
    required this.labelWidth,
  });

  final ColorScheme scheme;
  final AnimationSpec animation;
  final List<String> labels;
  final List<List<double>> times;
  final double duration;
  final double playhead;
  final TimelineKey? selectedKey;
  final double labelWidth;

  static const double _laneLeftPad = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = scheme.surfaceContainerLow,
    );
    final pxPerSecond = (size.width - labelWidth - 8) / duration;

    // Ruler.
    final rulerBottom = Offset(size.width, _rulerHeight);
    canvas.drawLine(
      const Offset(0, _rulerHeight),
      rulerBottom,
      Paint()..color = scheme.outlineVariant,
    );
    final tickStyle = Paint()
      ..color = scheme.outline.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final step = _niceStep(duration);
    final textStyle = TextStyle(fontSize: 9, color: scheme.outline);
    for (var t = 0.0; t <= duration + 1e-6; t += step) {
      final x = labelWidth + t * pxPerSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, _rulerHeight - 3), tickStyle);
      TextPainter(
        text: TextSpan(text: t.toStringAsFixed(step < 0.25 ? 2 : 1), style: textStyle),
        textDirection: TextDirection.ltr,
      )
        ..layout()
        ..paint(canvas, Offset(x + 2, 1));
    }

    // Lanes.
    for (var row = 0; row < labels.length; row++) {
      final top = _rulerHeight + row * _rowHeight;
      if (row.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, _rowHeight),
          Paint()..color = scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        );
      }
      TextPainter(
        text: TextSpan(
          text: labels[row],
          style: TextStyle(fontSize: 11, color: scheme.onSurface),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )
        ..layout(maxWidth: labelWidth - 8)
        ..paint(canvas, Offset(4, top + (_rowHeight - 11) / 2));
      canvas.drawLine(
        Offset(labelWidth + _laneLeftPad, top + _rowHeight / 2),
        Offset(labelWidth + _laneLeftPad + duration * pxPerSecond,
            top + _rowHeight / 2),
        Paint()
          ..color = scheme.outlineVariant
          ..strokeWidth = 1.5,
      );

      // Keyframe diamonds.
      for (final time in times[row]) {
        _drawDiamond(
          canvas,
          labelWidth + time * pxPerSecond,
          top + _rowHeight / 2,
          selectedKey != null &&
              selectedKey!.target == animation.channels[row].target &&
              selectedKey!.property == animation.channels[row].property &&
              (selectedKey!.time - time).abs() <= 1e-3,
        );
      }
    }

    // Playhead.
    final x = labelWidth + playhead.clamp(0.0, duration) * pxPerSecond;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(x, 5), 4, Paint()..color = scheme.primary);
  }

  void _drawDiamond(Canvas canvas, double cx, double cy, bool selected) {
    final path = Path()
      ..moveTo(cx, cy - 5)
      ..lineTo(cx + 5, cy)
      ..lineTo(cx, cy + 5)
      ..lineTo(cx - 5, cy)
      ..close();
    canvas.drawPath(path, Paint()..color = selected ? scheme.primary : scheme.secondary);
    if (selected) {
      canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = scheme.primary.withValues(alpha: 0.2));
    }
  }

  /// A ruler step near [duration] / 8 that keeps readable labels.
  double _niceStep(double duration) {
    if (duration <= 0) return 1;
    final raw = duration / 8;
    final steps = [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0];
    for (final step in steps) {
      if (raw <= step) return step;
    }
    return 60;
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.playhead != playhead ||
      oldDelegate.selectedKey != selectedKey ||
      oldDelegate.duration != duration ||
      !identical(oldDelegate.times, times) ||
      !listEquals(oldDelegate.labels, labels);
}

/// A tooltip tuned for the panel's explanatory copy: appears quickly, stays
/// readable, and wraps multi-line guidance.
class _PanelTip extends StatelessWidget {
  const _PanelTip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    waitDuration: const Duration(milliseconds: 350),
    showDuration: const Duration(seconds: 8),
    margin: const EdgeInsets.symmetric(horizontal: 40),
    padding: const EdgeInsets.all(10),
    child: child,
  );
}

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
