/// The animator: the machine that decides which clip a character plays.
///
/// A clip is one movement. What turns a pile of clips into a character is the
/// machine over them, and a machine is a graph, so this is a canvas rather
/// than a list: states as boxes, transitions as arrows, and a panel beside it
/// for whichever of the two is selected.
///
/// It edits the `animator` component on the selected node. Every edit writes
/// the whole machine back through one command, because the states and
/// transitions are a single property bag and a partial write of one would
/// leave the rest of it describing the machine as it was.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' show AnimatorComponent;
import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'animator_document.dart';
import 'animator_graph_geometry.dart';
import 'animator_graph_view.dart';
import 'animator_side_panel.dart';

/// The document component this edits.
const String animatorComponentType = 'animator';

/// The animator editor for the selected node.
class AnimatorEditor extends StatefulWidget {
  const AnimatorEditor({super.key, required this.controller});

  final EditorController controller;

  @override
  State<AnimatorEditor> createState() => _AnimatorEditorState();
}

class _AnimatorEditorState extends State<AnimatorEditor> {
  EditorController get _ctrl => widget.controller;

  int _layerIndex = 0;
  AnimatorSelection? _selection;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    _ctrl.selection.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(AnimatorEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller
        ..removeListener(_onChanged)
        ..selection.removeListener(_onChanged);
      widget.controller
        ..addListener(_onChanged)
        ..selection.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _ctrl
      ..removeListener(_onChanged)
      ..selection.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  LocalId? get _nodeId => _ctrl.selection.primary;

  /// The animator component on the selected node, or null.
  ComponentSpec? get _component {
    final id = _nodeId;
    if (id == null) return null;
    for (final component in _ctrl.displayNode(id)?.components ?? const []) {
      if (component.type == animatorComponentType) return component;
    }
    return null;
  }

  /// The clips the selected node's model actually carries, for the pickers.
  ///
  /// A state naming a clip the model does not have loads without complaint and
  /// plays nothing, so offering the real names is most of what stops that.
  List<String> get _availableClips {
    final id = _nodeId;
    if (id == null) return const [];
    final node = _ctrl.liveNode(id);
    if (node == null) return const [];
    return [
      for (final animation in node.parsedAnimations)
        if (animation.name.isNotEmpty) animation.name,
    ]..sort();
  }

  /// The state the running machine is in on the shown layer, or null when
  /// nothing is running it.
  String? get _activeState {
    final id = _nodeId;
    if (id == null) return null;
    final live = _ctrl.liveNode(id)?.getComponent<AnimatorComponent>();
    if (live == null) return null;
    final layers = live.animator.layers;
    if (_layerIndex >= layers.length) return null;
    return layers[_layerIndex].current;
  }

  AnimatorGraph? get _graph {
    final component = _component;
    return component == null ? null : readAnimatorGraph(component.properties);
  }

  /// Writes [graph] back as one edit.
  Future<void> _commit(AnimatorGraph graph) async {
    final id = _nodeId;
    if (id == null) return;
    await _ctrl.run('setComponentProperties', {
      'nodeId': id.toToken(),
      'componentType': animatorComponentType,
      'properties': writeAnimatorGraph(graph),
    });
  }

  /// Replaces the shown layer and writes the result.
  Future<void> _commitLayer(AnimatorLayerGraph layer) async {
    final graph = _graph;
    if (graph == null) return;
    await _commit(graph.withLayer(_layerIndex, layer));
  }

  Future<void> _addAnimator() async {
    final id = _nodeId;
    if (id == null) return;
    // A machine with no state does not realize at all, so it starts with one.
    await _ctrl.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': animatorComponentType,
    });
    await _commit(
      const AnimatorGraph(
        layered: false,
        layers: [
          AnimatorLayerGraph(
            name: AnimatorGraph.baseLayerName,
            initial: 'Idle',
            states: [AnimatorStateNode(name: 'Idle', position: Offset(40, 40))],
          ),
        ],
      ),
    );
  }

  Future<void> _addState(Offset position) async {
    final graph = _graph;
    if (graph == null) return;
    final layer = graph.layers[_layerIndex];
    final name = uniqueStateName(layer, 'New State');
    await _commitLayer(
      layer.copyWith(
        states: [
          ...layer.states,
          AnimatorStateNode(name: name, position: position),
        ],
        initial: layer.states.isEmpty ? name : layer.initial,
      ),
    );
    setState(() => _selection = AnimatorStateSelection(name));
  }

  Future<void> _connect(String from, String to) async {
    final graph = _graph;
    if (graph == null) return;
    final layer = graph.layers[_layerIndex];
    await _commitLayer(
      layer.copyWith(
        transitions: [
          ...layer.transitions,
          AnimatorTransitionEdge(from: from, to: to),
        ],
      ),
    );
    setState(
      () => _selection = AnimatorTransitionSelection(layer.transitions.length),
    );
  }

  Future<void> _addLayer() async {
    final graph = _graph;
    if (graph == null) return;
    final taken = {for (final layer in graph.layers) layer.name};
    var name = 'upper';
    for (var i = 2; taken.contains(name); i++) {
      name = 'upper $i';
    }
    await _commit(
      graph.withLayers([
        ...graph.layers,
        AnimatorLayerGraph(
          name: name,
          initial: 'Idle',
          states: const [
            AnimatorStateNode(name: 'Idle', position: Offset(40, 40)),
          ],
        ),
      ]),
    );
    setState(() {
      _layerIndex = graph.layers.length;
      _selection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final graph = _graph;
    if (graph == null) {
      return _EmptyState(onAdd: _nodeId == null ? null : _addAnimator);
    }
    final layerIndex = _layerIndex.clamp(0, graph.layers.length - 1);
    if (layerIndex != _layerIndex) {
      // A layer was removed under us (an undo, or another editor).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _layerIndex = layerIndex);
      });
    }
    final layer = graph.layers[layerIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LayerBar(
          graph: graph,
          index: layerIndex,
          onSelect: (index) => setState(() {
            _layerIndex = index;
            _selection = null;
          }),
          onAddLayer: () => unawaited(_addLayer()),
          onAddState: () => unawaited(
            _addState(
              animatorFreePosition([
                for (final state in layer.states) state.position,
              ]),
            ),
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatorGraphView(
                  layer: layer,
                  selection: _selection,
                  activeState: _activeState,
                  onSelect: (selection) =>
                      setState(() => _selection = selection),
                  onMoveState: (name, position) {
                    final state = layer.state(name);
                    if (state == null) return;
                    unawaited(
                      _commitLayer(
                        layer.copyWith(
                          states: [
                            for (final candidate in layer.states)
                              if (candidate.name == name)
                                candidate.copyWith(position: position)
                              else
                                candidate,
                          ],
                        ),
                      ),
                    );
                  },
                  onConnect: (from, to) => unawaited(_connect(from, to)),
                  onAddState: (position) => unawaited(_addState(position)),
                  onSetInitial: (name) =>
                      unawaited(_commitLayer(layer.copyWith(initial: name))),
                ),
              ),
              Container(width: 1, color: editorLineColor),
              SizedBox(
                width: 268,
                child: AnimatorSidePanel(
                  graph: graph,
                  layer: layer,
                  selection: _selection,
                  availableClips: _availableClips,
                  onLayerChanged: (updated) => unawaited(_commitLayer(updated)),
                  onSelect: (selection) =>
                      setState(() => _selection = selection),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// What the layer bar is: which machine you are looking at, and the two
/// buttons that grow it.
class _LayerBar extends StatelessWidget {
  const _LayerBar({
    required this.graph,
    required this.index,
    required this.onSelect,
    required this.onAddLayer,
    required this.onAddState,
  });

  final AnimatorGraph graph;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddLayer;
  final VoidCallback onAddState;

  @override
  Widget build(BuildContext context) => Container(
    height: editorToolbarHeight,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Row(
      children: [
        const Icon(Icons.account_tree_outlined, size: 14),
        const SizedBox(width: 6),
        Text('Animator', style: editorBodyText),
        const SizedBox(width: 12),
        for (var i = 0; i < graph.layers.length; i++) ...[
          _LayerTab(
            label: graph.layers[i].name,
            selected: i == index,
            onTap: () => onSelect(i),
          ),
          const SizedBox(width: 4),
        ],
        IconButton(
          icon: const Icon(Icons.add, size: 14),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 22, height: 22),
          tooltip: 'Add a layer, so the character can do two things at once',
          onPressed: onAddLayer,
        ),
        const Spacer(),
        TextButton.icon(
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          icon: const Icon(Icons.add_box_outlined, size: 14),
          label: const Text('Add state', style: TextStyle(fontSize: 11)),
          onPressed: onAddState,
        ),
      ],
    ),
  );
}

class _LayerTab extends StatelessWidget {
  const _LayerTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? editorRaisedColor : Colors.transparent,
        border: Border.all(
          color: selected ? editorAccentColor : editorLineColor,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: editorBodyText.copyWith(
          color: selected ? editorTextColor : editorMutedTextColor,
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 24,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 10),
          Text(
            onAdd == null
                ? 'Select a node to give it an animator.'
                : 'This node has no animator.',
            style: const TextStyle(fontSize: 12, color: editorMutedTextColor),
          ),
          const SizedBox(height: 4),
          Text(
            'A clip is one movement. An animator is the machine over them '
            'that decides which one plays.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
          if (onAdd != null) ...[
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onAdd, child: const Text('Add Animator')),
          ],
        ],
      ),
    ),
  );
}
