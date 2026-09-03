import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart'
    show
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerPanZoomUpdateEvent,
        PointerScrollEvent,
        PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart'
    show AnimationChange, ChangeSlot;
import 'package:scene/scene.dart';

import '../controller/animation_sampling.dart';
import '../controller/animation_target_resolution.dart';
import '../controller/editor_controller.dart';
import '../shell/editor_dialog.dart';

// One library, several files: the panel (this file), its dialogs, the
// timeline widget, its painter, and the shared view model + tooltip chrome.
part 'animation/timeline_model.dart';
part 'animation/timeline.dart';
part 'animation/timeline_painter.dart';
part 'animation/panel_dialogs.dart';
part 'animation/panel_tip.dart';

/// The Animation panel: author document animations and preview them live.
///
/// One animation loads onto the controller's playhead at a time. Transport
/// controls play, pause, scrub, and loop it; the timeline groups each node's
/// keyframe lanes under a shared header row so a multi-node rig reads as
/// distinct blocks. Lanes show each channel's keys, which drag to retime,
/// double-tap to add (capturing the target's current pose), and delete from
/// the lane toolbar. Keying buttons
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

  /// How a multi-node key applies to the selection, per
  /// [MultiNodeMovementMode].
  MultiNodeMovementMode _movementMode = MultiNodeMovementMode.inherited;

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
  ///
  /// Pressing Key also adds crystals at the timeline's start and end where
  /// none exist, so every playthrough starts and ends on a captured key —
  /// without touching edge keys the author placed deliberately.
  ///
  /// When multiple nodes are selected, the [_movementMode] controls which
  /// nodes receive keys ([_keyTargetNodes]); each keyed node records the pose
  /// it visibly holds ([_livePoseFor]). No delta math happens here — the
  /// panel only chooses the key-target set and records what is on screen.
  Future<void> _keySelection(AnimationProperty? property) async {
    final id = _animationId;
    if (id == null) return;
    final time = _controller.previewTime;

    final commands = <(String, Map<String, Object?>)>[
      for (final nodeId in _keyTargetNodes())
        if (_controller.document.nodes.containsKey(nodeId))
          for (final p
              in property == null
                  ? const [
                      AnimationProperty.translation,
                      AnimationProperty.rotation,
                      AnimationProperty.scale,
                    ]
                  : [property])
            (
              'setAnimationKeyframe',
              {
                'animationId': id.toToken(),
                'nodeId': nodeId.toToken(),
                'property': p.name,
                'time': time,
                // Capture the pose the user actually sees. A pose landed with
                // the viewport gizmo or an inspector drag lives on the live
                // node, not the document; keying without values would make the
                // command re-read a stale document pose and snap the node back
                // to it. Recording the visible pose here keeps the authored
                // rest pose (the model's origin) untouched.
                ...?_livePoseFor(nodeId, p),
              },
            ),
    ];
    try {
      await _controller.runAll(commands);
    } on Exception catch (error) {
      _showError(error);
      return;
    }
    if (property == null) await _ensureEdgeKeys(id, time);
  }

  /// The nodes a multi-node key applies to, per [_movementMode].
  ///
  /// [MultiNodeMovementMode.inherited] keys only the selected nodes with no
  /// selected ancestor (see `EditorController.topLevelSelection`): a selected
  /// parent is keyed and its selected children ride along through the scene
  /// graph, moving with it proportionally. Keying them too would double-drive
  /// them at playback — the parent's channel moves the child while the
  /// child's own channel pins it in place.
  ///
  /// [MultiNodeMovementMode.mirrored] keys every selected node individually,
  /// including selected descendants of other selected nodes. Callers filter
  /// out ids missing from the document (prefab members), so the raw
  /// selection is returned as-is.
  List<LocalId> _keyTargetNodes() =>
      _movementMode == MultiNodeMovementMode.inherited
      ? _controller.topLevelSelection()
      : _controller.selection.ids.toList();

  /// Adds the missing edge crystals: a key at t = 0 and at the clip's end
  /// for every selected node's translation, rotation, and scale path that
  /// does not have one yet. A clip with no keyframes yet (a fresh Key at
  /// the default playhead) defaults its end crystal to t = 1s, matching the
  /// panel's default 1s timeline.
  ///
  /// Additive on purpose — an edge key the author placed deliberately keeps
  /// its pose. Keying mid-clip must never rewrite the timeline's endpoints,
  /// or posing at t = 0.5 would clobber a carefully keyed start pose.
  Future<void> _ensureEdgeKeys(LocalId id, double playhead) async {
    final spec = _controller.document.animations[id];
    if (spec == null) return;
    bool hasKeyAt(AnimationChannelSpec channel, double time) => channelTimes(
      _controller.document,
      channel,
    ).any((t) => (t - time).abs() <= 1e-3);

    // Plain node authoring matches a path's first channel regardless of its
    // stored binding name (the same rule setAnimationKeyframe applies), so
    // panel-built channels are found here after undos and renames too.
    AnimationChannelSpec? channelFor(
      LocalId nodeId,
      AnimationProperty property,
    ) {
      for (final channel in spec.channels) {
        if (channel.target == nodeId && channel.property == property) {
          return channel;
        }
      }
      return null;
    }

    // The clip's duration is its last keyframe's time — which, right after
    // the playhead capture above, is the playhead itself. A fresh clip keyed
    // at t=0 would therefore end at 0 and never receive an end crystal; the
    // timeline panel already defaults a keyless clip to 1s, so a new key
    // falls back to that 1s end to start AND end on a captured key. Clips
    // that already carry an authored end keep it untouched.
    var end = _controller.previewDuration(id);
    if (end <= 1e-4) end = 1.0;
    final edges = {0.0, end};
    final commands = <(String, Map<String, Object?>)>[];
    for (final nodeId in _keyTargetNodes()) {
      if (!_controller.document.nodes.containsKey(nodeId)) continue;
      for (final property in const [
        AnimationProperty.translation,
        AnimationProperty.rotation,
        AnimationProperty.scale,
      ]) {
        for (final edge in edges) {
          // An edge under the playhead is already keyed by the capture
          // above; an edge already carrying a crystal stays untouched. The
          // two edges of one path are distinct times, so deciding both from
          // the pre-batch document is safe: adding one never keys the other.
          if ((edge - playhead).abs() <= 1e-3) continue;
          final channel = channelFor(nodeId, property);
          if (channel != null && hasKeyAt(channel, edge)) continue;
          // A new edge keys the pose the curve already plays at that time
          // (sampled from the channel's own keyframes), falling back to the
          // node's visible pose when the channel has nothing to sample — so a
          // pose captured mid-clip can never bleed into the clip's start or
          // end and jog the model's origin.
          final pose = channel == null
              ? _livePoseFor(nodeId, property)
              : _edgePose(channel, edge);
          commands.add((
            'setAnimationKeyframe',
            {
              'animationId': id.toToken(),
              'nodeId': nodeId.toToken(),
              'property': property.name,
              'time': edge,
              ...?pose,
            },
          ));
        }
      }
    }
    if (commands.isEmpty) return;
    try {
      await _controller.runAll(commands);
    } on Exception catch (error) {
      _showError(error);
    }
  }

  /// Removes an entire channel (a node/property path) from the animation —
  /// the ✕ beside a lane label.
  Future<void> _removeChannel(AnimationChannelSpec channel) async {
    final id = _animationId;
    if (id == null) return;
    try {
      await _controller.run('removeChannel', {
        'animationId': id.toToken(),
        'nodeId': channel.target.toToken(),
        'property': channel.property.name,
        if (channel.targetName != null) 'targetName': channel.targetName,
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  /// The cleanup behind the header's broom button: drops paths that carry no
  /// motion (constant channels, missing payloads, targets that are gone).
  Future<void> _cleanUnusedPaths() async {
    final id = _animationId;
    if (id == null) return;
    final before = _controller.document.animations[id]?.channels.length ?? 0;
    if (!await _confirmCleanUnusedPaths(context)) return;
    try {
      await _controller.run('cleanAnimationChannels', {
        'animationId': id.toToken(),
      });
      final removed =
          before - (_controller.document.animations[id]?.channels.length ?? 0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed > 0
                ? 'Removed $removed unused path${removed == 1 ? '' : 's'}.'
                : 'Nothing needed cleaning — every path animates.',
          ),
        ),
      );
    } on Exception catch (error) {
      _showError(error);
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
    // The clip's duration is its last keyframe time, so a key placed (or
    // dragged) past it is what extends the clip — only guard against absurd
    // values, not against the current end.
    final clamped = toTime.clamp(0.0, _maxKeyTime).toDouble();
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
            padding: const EdgeInsets.only(
              left: 10,
              right: 10,
              bottom: 6,
              top: 6,
            ),
            child: Text(
              'Drag to scrub · double-click a lane to add a key · drag a '
              'diamond to retime · wheel scrolls (vertically when lanes '
              'overflow) · ctrl/cmd+wheel or pinch zooms (zoom out to reach '
              'past the clip\'s end)',
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
                  dragFromTime: _dragging ? _selectedKey?.time : null,
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
                  // onPanUpdate reports per-event deltas, so the offset is a
                  // running sum of how far the pointer has travelled since the
                  // pan began (not a positional snapshot).
                  onDragKeyUpdate: (delta) =>
                      setState(() => _dragOffset += delta),
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
                  onRemoveChannel: (channel) =>
                      unawaited(_removeChannel(channel)),
                ),
                if (animation.channels.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.all(16),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.92,
                            ),
                            border: Border.all(color: scheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'No keyframes yet.\n\n'
                            '1. Select a node in the Outliner\n'
                            '2. Drag the playhead where the pose belongs\n'
                            '3. Pose the node with the viewport gizmo\n'
                            '4. Press Key — repeat at other times',
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(height: 1.5),
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
  Future<void> _addKeyAt(AnimationChannelSpec channel, double time) async {
    try {
      await _controller.run('setAnimationKeyframe', {
        'animationId':
            _controller.previewAnimationId?.toToken() ??
            _animationId?.toToken(),
        'nodeId': channel.target.toToken(),
        // Lane channels carry the binding fallback name (for a prefab member,
        // the bone inside the imported instance the lane drives); repeating it
        // makes the new key land on the exact channel that was double-tapped.
        if (channel.targetName != null) 'targetName': channel.targetName,
        'property': channel.property.name,
        'time': time.clamp(0.0, _maxKeyTime).toDouble(),
        // Capture the visible pose of the channel's live target (the node, or
        // the named descendant inside a prefab instance), so the added key
        // records what the user sees rather than a stale document pose.
        ...?_livePoseFor(
          channel.target,
          channel.property,
          targetName: channel.targetName,
        ),
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  /// The payload of [id] as float32s (native-endian, matching the emitter).
  /// The controller caches its own decode for playback; this is the panel's
  /// decode for the edge sampling below. Empty when the payload is missing.
  Float32List _payloadFloatValues(LocalId id) {
    final bytes = _controller.document.payload(id)?.bytes;
    if (bytes == null) return Float32List(0);
    if (bytes.offsetInBytes % 4 == 0) {
      return bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
    }
    return Uint8List.fromList(
      bytes,
    ).buffer.asFloat32List(0, bytes.lengthInBytes ~/ 4);
  }

  /// The pose the channel's live target currently shows, as the value map
  /// `setAnimationKeyframe` accepts.
  ///
  /// Returns the nested shape the command's param schema expects — a
  /// `"translation"` / `"rotation"` / `"scale"` object with `x`/`y`/`z` (and
  /// `w` for rotation). Passing a flat `{x, y, z}` map instead makes the
  /// command's optional-value reader miss the component and silently fall
  /// back to the DOCUMENT transform — keying the rest pose and snapping the
  /// node back to it when the preview re-applies. The live node rather than
  /// the document is read so keying records exactly what the user sees — a
  /// pose landed with the viewport gizmo or an inspector drag lives on the
  /// live node until it is keyed. [targetName] resolves a prefab-member
  /// target (a bone inside an imported instance) exactly as the preview and
  /// runtime binders do. Null when the target is missing from the live graph;
  /// callers fall back to the command's own document capture.
  Map<String, Object>? _livePoseFor(
    LocalId nodeId,
    AnimationProperty property, {
    String? targetName,
  }) {
    final live = _controller.liveNode(nodeId);
    if (live == null) return null;
    final node = targetName == null
        ? live
        : resolveChannelTarget(live, targetName);
    if (node == null) return null;
    switch (property) {
      case AnimationProperty.translation:
        final t = node.position;
        return {
          'translation': {'x': t.x, 'y': t.y, 'z': t.z},
        };
      case AnimationProperty.rotation:
        final r = node.rotation;
        return {
          'rotation': {'x': r.x, 'y': r.y, 'z': r.z, 'w': r.w},
        };
      case AnimationProperty.scale:
        final s = node.scale;
        return {
          'scale': {'x': s.x, 'y': s.y, 'z': s.z},
        };
      case AnimationProperty.weights:
        return null;
    }
  }

  /// The pose [channel]'s curve already plays at [time] — the interpolation of
  /// its own keyframes — in the nested shape `setAnimationKeyframe` accepts
  /// (`translation` / `rotation` / `scale` objects).
  ///
  /// Used for edge crystals: a missing start/end key must duplicate the value
  /// the playthrough already shows there, never the pose held at the playhead
  /// when Key was pressed, or a mid-clip capture would rewrite the clip's
  /// endpoints and move the model's start pose. Falls back to the live visible
  /// pose when the channel carries no keyframes to sample.
  Map<String, Object>? _edgePose(AnimationChannelSpec channel, double time) {
    final times = _payloadFloatValues(channel.timeline);
    final values = _payloadFloatValues(channel.keyframes);
    final stride = channel.property == AnimationProperty.rotation ? 4 : 3;
    final sampled = sampleAnimationChannel(
      times,
      values,
      stride,
      time,
      interpolation: channel.interpolation,
    );
    if (sampled == null) {
      return _livePoseFor(
        channel.target,
        channel.property,
        targetName: channel.targetName,
      );
    }
    switch (channel.property) {
      case AnimationProperty.translation:
        return {
          'translation': {'x': sampled[0], 'y': sampled[1], 'z': sampled[2]},
        };
      case AnimationProperty.rotation:
        return {
          'rotation': {
            'x': sampled[0],
            'y': sampled[1],
            'z': sampled[2],
            'w': sampled[3],
          },
        };
      case AnimationProperty.scale:
        return {
          'scale': {'x': sampled[0], 'y': sampled[1], 'z': sampled[2]},
        };
      case AnimationProperty.weights:
        return null;
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
              message:
                  'The animation this panel edits and previews.\n\n'
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
            message:
                'Rename this animation.\n\nThe name is what you look up '
                'in code when you play the clip at runtime.',
            child: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              onPressed: animation == null ? null : () => _promptRename(),
            ),
          ),
          _PanelTip(
            message:
                'Clean unused paths.\n\nRemoves channels that carry no '
                'motion — constant keyframes, empty payloads, or targets '
                'whose node is gone. Keeps every path that animates.',
            child: IconButton(
              icon: const Icon(Icons.cleaning_services_outlined, size: 16),
              onPressed: animation == null ? null : _cleanUnusedPaths,
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
    final name = await _promptAnimationRename(context, animation.name);
    if (name != null) await _renameAnimation(name);
  }

  /// The walkthrough behind the header's ? button.
  Future<void> _showHelp() => _showAnimationHelpDialog(context);

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
                  PopupMenuItem(value: speed, child: Text('$speed×')),
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
          // The movement mode selector: controls which selected nodes a
          // multi-node key applies to.
          _PanelTip(
            message:
                'How a multi-node key applies to the selection.\n\n'
                'Inherited keys only the top-level selected nodes: their '
                'selected children are not keyed and ride along through the '
                'scene graph, moving with the parent proportionally.\n\n'
                'Mirrored keys every selected node individually, so selected '
                'children carry their own channels instead of riding along.\n\n'
                'The modes differ when the selection contains a node together '
                'with one of its descendants; for a selection of unrelated '
                'nodes both key every node.',
            child: SizedBox(
              height: 26,
              child: _MovementModeToggle(
                mode: _movementMode,
                onChanged: (mode) => setState(() => _movementMode = mode),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _PanelTip(
            message:
                'Key the pose: captures translation, rotation, and scale of '
                'every selected node at the playhead — and adds crystals at '
                'the timeline\'s start and end where none exist, so every '
                'playthrough begins and ends on a captured key. Existing '
                'edge keys keep their pose.\n\n'
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
            if (_channelOfSelectedKey case final selectedChannel?) ...[
              _PanelTip(
                message:
                    'How this channel interpolates between its keyframes.\n\n'
                    'Linear blends smoothly between neighbors; Step holds '
                    'each keyframe\'s value until the next one is reached.',
                child: _InterpPill(
                  height: 22,
                  segments: [
                    for (final (mode, label) in const [
                      ('linear', 'Lin'),
                      ('step', 'Step'),
                      ('cubic', 'Cubic'),
                    ])
                      (
                        label: label,
                        selected: switch (selectedChannel.interpolation) {
                          AnimationInterpolation.step => mode == 'step',
                          AnimationInterpolation.cubic => mode == 'cubic',
                          _ => mode == 'linear',
                        },
                        onTap: () => unawaited(_setChannelInterpolation(mode)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            _PanelTip(
              message:
                  'Delete this keyframe.\n\n'
                  'The channel interpolates across the gap; removing the last '
                  'key of a channel removes the channel.',
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                // Compact to match the 26px Key button and 22px interp pill;
                // the 40px default minimum inflates the whole key bar.
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ),
        ],
      ),
    );
  }

  /// The channel of the currently selected key, or null when nothing is
  /// selected or its channel no longer exists.
  AnimationChannelSpec? get _channelOfSelectedKey {
    final key = _selectedKey;
    final id = _animationId;
    if (key == null || id == null) return null;
    for (final channel in _controller.document.animations[id]!.channels) {
      if (channel.target == key.target && channel.property == key.property) {
        return channel;
      }
    }
    return null;
  }

  Future<void> _setChannelInterpolation(String mode) async {
    final key = _selectedKey;
    if (key == null) return;
    await _controller.run('setChannelInterpolation', {
      'animationId': _animationId?.toToken(),
      'nodeId': key.target.toToken(),
      'property': key.property.name,
      'interpolation': mode,
    });
  }

  String _nodeName(LocalId id) =>
      _controller.document.nodes[id]?.name ?? id.toToken();
}

/// How a multi-node key applies to the selection in the animation panel.
enum MultiNodeMovementMode {
  /// Only selected ancestors are keyed; their selected children ride along
  /// through the scene graph hierarchy, moving with the parent
  /// proportionally.
  inherited,

  /// Every selected node is keyed with its own pose, including selected
  /// descendants of other selected nodes, so each carries its own channels
  /// instead of riding along through its parent's.
  mirrored,
}

/// A segmented toggle between [MultiNodeMovementMode] values, used in the
/// animation panel's key bar to pick how a multi-node key applies.
class _MovementModeToggle extends StatelessWidget {
  const _MovementModeToggle({required this.mode, required this.onChanged});

  final MultiNodeMovementMode mode;
  final ValueChanged<MultiNodeMovementMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MultiNodeMovementMode>(
      segments: const [
        ButtonSegment(
          value: MultiNodeMovementMode.inherited,
          label: Text('Inherit', style: TextStyle(fontSize: 11)),
          icon: Icon(Icons.account_tree_outlined, size: 14),
        ),
        ButtonSegment(
          value: MultiNodeMovementMode.mirrored,
          label: Text('Mirror', style: TextStyle(fontSize: 11)),
          icon: Icon(Icons.sync_alt, size: 14),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      showSelectedIcon: false,
    );
  }
}
