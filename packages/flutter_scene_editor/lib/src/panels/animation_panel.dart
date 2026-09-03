import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;
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
  // The keyframes the lane gestures target: each channel plus original time.
  // A set so more than one crystal can be dragged or deleted together.
  Set<TimelineKey> _selectedKeys = {};

  // The most recently selected key — the anchor for channel controls (the
  // interpolation pill) and the reference point a multi-key drag offsets from.
  TimelineKey? _primaryKey;

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
    // drops out of the set.
    if (_selectedKeys.isNotEmpty) {
      final surviving = _selectedKeys.where(_keyExists).toSet();
      _selectedKeys = surviving;
      if (_primaryKey != null && !surviving.contains(_primaryKey)) {
        _primaryKey = surviving.isEmpty ? null : surviving.last;
      }
    }
    // Refresh unconditionally: document edits with an empty selection (an
    // added key, a renamed animation) must still reach the panel.
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
    final targets = _keyTargetNodes();

    // Nodes not yet on the timeline get seeded with start/end crystals after
    // the capture below; nodes already included keep their authored edges
    // untouched — Key captures only the playhead for them. Computed BEFORE
    // the capture, which is what puts the fresh nodes on the timeline.
    final freshNodes = <LocalId>{
      for (final nodeId in targets)
        if (_controller.document.nodes.containsKey(nodeId) &&
            !_nodeHasChannels(nodeId))
          nodeId,
    };

    final commands = <(String, Map<String, Object?>)>[
      for (final nodeId in targets)
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
    if (property == null) await _ensureEdgeKeys(id, time, freshNodes);
  }

  /// Whether [nodeId] drives any channel of the current animation — i.e. its
  /// header already appears on the timeline.
  bool _nodeHasChannels(LocalId nodeId) {
    final spec = _animation;
    if (spec == null) return false;
    return spec.channels.any((c) => c.target == nodeId);
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

  /// Seeds the start and end crystals for nodes that just joined the timeline:
  /// a key at t = 0 and at the clip's end (defaulting to 1s when the clip is
  /// still empty) for each fresh node's translation, rotation, and scale path.
  ///
  /// Only [freshNodes] — the nodes that had no channel before the Key press —
  /// receive edge crystals, so every new node's playthrough spans the whole
  /// clip. A node already on the timeline keeps its authored edges untouched:
  /// Key captures only the playhead for it, and posing mid-clip can never
  /// rewrite the timeline's endpoints.
  Future<void> _ensureEdgeKeys(
    LocalId id,
    double playhead,
    Set<LocalId> freshNodes,
  ) async {
    final spec = _controller.document.animations[id];
    if (spec == null) return;

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
    for (final nodeId in freshNodes) {
      for (final property in const [
        AnimationProperty.translation,
        AnimationProperty.rotation,
        AnimationProperty.scale,
      ]) {
        for (final edge in edges) {
          // An edge under the playhead was already captured above. Every
          // other edge of a fresh node records the pose it currently shows:
          // with no curve of its own, that visible pose is what plays
          // everywhere, so seeding it at the clip's ends is exact.
          if ((edge - playhead).abs() <= 1e-3) continue;
          commands.add((
            'setAnimationKeyframe',
            {
              'animationId': id.toToken(),
              'nodeId': nodeId.toToken(),
              'property': property.name,
              'time': edge,
              ...?_livePoseFor(nodeId, property),
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
    final keys = Set<TimelineKey>.from(_selectedKeys);
    if (id == null || keys.isEmpty) return;
    setState(() {
      _selectedKeys.clear();
      _primaryKey = null;
    });
    try {
      for (final key in keys) {
        await _controller.run('removeAnimationKeyframe', {
          'animationId': id.toToken(),
          'nodeId': key.target.toToken(),
          'property': key.property.name,
          'time': key.time,
        });
      }
    } on Exception catch (error) {
      _showError(error);
    }
  }

  Future<void> _moveSelectedKeys(double offset) async {
    final id = _animationId;
    final keys = Set<TimelineKey>.from(_selectedKeys);
    if (id == null || keys.isEmpty) return;
    if (offset.abs() <= 1e-4) return;
    // The clip's duration is its last keyframe time, so a key placed (or
    // dragged) past it is what extends the clip — only guard against absurd
    // values, not against the current end.
    try {
      for (final key in keys) {
        final clamped = (key.time + offset).clamp(0.0, _maxKeyTime).toDouble();
        if ((clamped - key.time).abs() <= 1e-4) continue;
        await _controller.run('moveAnimationKeyframe', {
          'animationId': id.toToken(),
          'nodeId': key.target.toToken(),
          'property': key.property.name,
          'fromTime': key.time,
          'toTime': clamped,
        });
      }
      // Selection cleared — the keys have moved to new times.
      setState(() {
        _selectedKeys.clear();
        _primaryKey = null;
      });
    } on Exception catch (error) {
      _showError(error);
    }
  }

  // -- selection -------------------------------------------------------------

  /// A plain click on a key: select only this key, clearing the rest.
  void _selectKey(TimelineKey key) {
    setState(() {
      _selectedKeys = {key};
      _primaryKey = key;
    });
  }

  /// A ctrl/cmd+click on a key: toggle it in/out of the selection.
  void _toggleKey(TimelineKey key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys = Set<TimelineKey>.from(_selectedKeys)..remove(key);
        // The toggled-off key was the primary — promote the last survivor.
        if (_primaryKey == key) {
          _primaryKey = _selectedKeys.isEmpty ? null : _selectedKeys.last;
        }
      } else {
        _selectedKeys = Set<TimelineKey>.from(_selectedKeys)..add(key);
        _primaryKey = key;
      }
    });
  }

  /// A click on empty lane space: clear the selection.
  void _clearSelection() {
    setState(() {
      _selectedKeys.clear();
      _primaryKey = null;
    });
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
              'diamond to retime · ctrl/cmd+click to multi-select · wheel '
              'scrolls (vertically when lanes overflow) · ctrl/cmd+wheel or '
              'pinch zooms (zoom out to reach past the clip\'s end)',
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
                  selectedKeys: _selectedKeys,
                  onTapLane: (time) {
                    setState(() {
                      _selectedKeys.clear();
                      _primaryKey = null;
                    });
                    _controller.seekPreview(time);
                  },
                  onScrub: _controller.seekPreview,
                  onSelectKey: _selectKey,
                  onToggleKey: _toggleKey,
                  onClearSelection: _clearSelection,
                  // The drag gesture lives inside the timeline (per-frame
                  // updates rebuild only the timeline, not this panel); the
                  // panel picks the drag set here and commits on release.
                  onDragKeyStart: (key) {
                    // Dragging a key outside the selection re-targets the
                    // selection to just that key; dragging a selected key
                    // keeps the whole set moving together.
                    if (!_selectedKeys.contains(key)) {
                      setState(() {
                        _selectedKeys = {key};
                        _primaryKey = key;
                      });
                      return {key};
                    }
                    _primaryKey = key;
                    return Set<TimelineKey>.from(_selectedKeys);
                  },
                  onDragKeyEnd: (offset) {
                    if (offset != 0) {
                      unawaited(_moveSelectedKeys(offset));
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
          if (_primaryKey != null) ...[
            Flexible(
              child: Text(
                _selectedKeys.length > 1
                    ? '${_selectedKeys.length} keys selected'
                    : '${_nodeName(_primaryKey!.target)} · '
                      '${_primaryKey!.property.name} @ '
                      '${_primaryKey!.time.toStringAsFixed(2)}s',
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
                  'Delete the selected keyframe${_selectedKeys.length > 1 ? 's' : ''}.\n\n'
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

  /// The channel of the primary (most recently selected) key, or null when nothing is
  /// selected or its channel no longer exists.
  AnimationChannelSpec? get _channelOfSelectedKey {
    final key = _primaryKey;
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
    final key = _primaryKey;
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
