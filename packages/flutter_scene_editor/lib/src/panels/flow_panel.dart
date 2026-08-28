/// The Flow dock panel: the canvas a visual script is drawn on.
///
/// Nodes are dragged around, pins are dragged between to wire them, and the
/// palette adds more. The graph being edited belongs to the selected node's
/// Flow component, and every edit is committed back through the command layer
/// so it is undoable like any other.
///
/// The canvas is one [CustomPaint] over a transformed coordinate space rather
/// than a widget per node. A graph is a hundred small boxes and several
/// hundred wires; as widgets that is a layout pass per pan, and panning is the
/// thing the canvas does most.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/flow.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'flow_layout.dart';

/// The Flow panel.
class FlowPanel extends StatefulWidget {
  const FlowPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<FlowPanel> createState() => _FlowPanelState();
}

class _FlowPanelState extends State<FlowPanel> {
  EditorController get _ctrl => widget.controller;

  final FlowRegistry _registry = sceneFlowRegistry();

  /// The graph being edited. Held here rather than read from the document on
  /// every frame, because a drag mutates it many times per second and only
  /// the release is worth an undo step.
  FlowGraph? _graph;
  LocalId? _graphOwner;

  Offset _pan = const Offset(40, 40);
  double _zoom = 1;

  int? _selected;
  int? _dragging;
  Offset _dragOffset = Offset.zero;

  /// The wire being drawn, if any: where it started and where the pointer is.
  FlowPortRef? _wireFrom;
  Offset? _wirePointer;

  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl.selection.addListener(_onSelectionChanged);
    _ctrl.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _ctrl.selection.removeListener(_onSelectionChanged);
    _ctrl.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final id = _ctrl.selection.primary;
    if (id != _graphOwner) {
      setState(() {
        _graph = null;
        _graphOwner = id;
        _selected = null;
      });
    } else {
      setState(() {});
    }
  }

  /// The selected node's flow component spec, or null.
  ComponentSpecView? get _componentView {
    final id = _ctrl.selection.primary;
    if (id == null) return null;
    final node = _ctrl.document.node(id);
    if (node == null) return null;
    for (final component in node.components) {
      if (component.type == 'flow') return (nodeId: id, spec: component);
    }
    return null;
  }

  /// Loads the graph from the document, once per selection.
  FlowGraph? _ensureGraph() {
    final existing = _graph;
    if (existing != null) return existing;
    final view = _componentView;
    if (view == null) return null;
    final source = view.spec.properties['graph'];
    final loaded = source is StringValue && source.value.isNotEmpty
        ? _tryRead(source.value)
        : FlowGraph();
    _graph = loaded;
    return loaded;
  }

  FlowGraph _tryRead(String source) {
    try {
      return readFlowGraph(source);
    } on FormatException {
      return FlowGraph();
    }
  }

  /// Writes the graph back to the document as one undoable edit.
  Future<void> _commit() async {
    final graph = _graph;
    final view = _componentView;
    if (graph == null || view == null) return;
    await _ctrl.run('setComponentProperties', {
      'nodeId': view.nodeId.toToken(),
      'componentType': 'flow',
      'properties': {'graph': StringValue(writeFlowGraph(graph))},
    });
  }

  Future<void> _addFlowComponent() async {
    final id = _ctrl.selection.primary;
    if (id == null) return;
    await _ctrl.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': 'flow',
    });
    setState(() => _graph = null);
  }

  // --- canvas geometry -----------------------------------------------------

  Offset _toCanvas(Offset screen) => (screen - _pan) / _zoom;

  FlowLayout _layout(FlowGraph graph) => FlowLayout(graph, _registry);

  // --- interaction ---------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, FlowGraph graph) {
    final at = _toCanvas(event.localPosition);
    final layout = _layout(graph);

    final port = layout.portAt(at);
    if (port != null) {
      // Grabbing a connected input pulls the wire off it, which is how one is
      // rerouted rather than deleted and drawn again.
      final existing = port.isInput
          ? graph.inputTo(port.node, port.pin)
          : null;
      if (existing != null) {
        graph.disconnect(existing);
        setState(() {
          _wireFrom = (
            node: existing.fromNode,
            pin: existing.fromPin,
            isInput: false,
          );
          _wirePointer = at;
        });
        return;
      }
      setState(() {
        _wireFrom = port;
        _wirePointer = at;
      });
      return;
    }

    final node = layout.nodeAt(at);
    if (node != null) {
      final spec = graph.node(node)!;
      setState(() {
        _selected = node;
        _dragging = node;
        _dragOffset = at - Offset(spec.position.x, spec.position.y);
      });
      return;
    }
    setState(() => _selected = null);
  }

  void _onPointerMove(PointerMoveEvent event, FlowGraph graph) {
    final at = _toCanvas(event.localPosition);
    if (_wireFrom != null) {
      setState(() => _wirePointer = at);
      return;
    }
    final dragging = _dragging;
    if (dragging != null) {
      final spec = graph.node(dragging);
      if (spec == null) return;
      final moved = at - _dragOffset;
      setState(() => spec.position.setValues(moved.dx, moved.dy));
      return;
    }
    // Nothing grabbed: drag the canvas.
    setState(() => _pan += event.delta);
  }

  Future<void> _onPointerUp(PointerUpEvent event, FlowGraph graph) async {
    final from = _wireFrom;
    if (from != null) {
      final at = _toCanvas(event.localPosition);
      final target = _layout(graph).portAt(at);
      setState(() {
        _wireFrom = null;
        _wirePointer = null;
      });
      if (target != null && _canConnect(graph, from, target)) {
        final output = from.isInput ? target : from;
        final input = from.isInput ? from : target;
        graph.connect(
          FlowLink(
            fromNode: output.node,
            fromPin: output.pin,
            toNode: input.node,
            toPin: input.pin,
          ),
          // Only exec outputs are singular; a value feeds as many inputs as
          // want it.
          execOutputIsSingular: _typeOf(graph, output) == FlowType.exec,
        );
        await _commit();
      }
      return;
    }
    if (_dragging != null) {
      setState(() => _dragging = null);
      await _commit();
    }
  }

  FlowType? _typeOf(FlowGraph graph, FlowPortRef port) {
    final spec = graph.node(port.node);
    if (spec == null) return null;
    return _registry[spec.type]?.pin(port.pin)?.type;
  }

  /// Whether a wire from one port to the other is legal.
  bool _canConnect(FlowGraph graph, FlowPortRef a, FlowPortRef b) {
    if (a.node == b.node) return false;
    if (a.isInput == b.isInput) return false;
    final output = a.isInput ? b : a;
    final input = a.isInput ? a : b;
    final from = _typeOf(graph, output);
    final to = _typeOf(graph, input);
    if (from == null || to == null) return false;
    return from.connectsTo(to);
  }

  Future<void> _deleteSelected(FlowGraph graph) async {
    final selected = _selected;
    if (selected == null) return;
    graph.removeNode(selected);
    setState(() => _selected = null);
    await _commit();
  }

  Future<void> _addNode(FlowNodeType type, FlowGraph graph) async {
    // Drop it in the middle of what is on screen, so it lands where the eye
    // is rather than at the origin.
    final centre = _toCanvas(
      Offset(context.size?.width ?? 400, context.size?.height ?? 300) / 2,
    );
    final node = graph.add(type.id, position: Vector2(centre.dx, centre.dy));
    setState(() {
      _selected = node.id;
      _paletteOpen = false;
    });
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final graph = _ensureGraph();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context, graph),
        Expanded(
          child: graph == null
              ? _NoGraph(
                  hasSelection: _ctrl.selection.primary != null,
                  onAdd: _addFlowComponent,
                )
              : Stack(
                  children: [
                    _buildCanvas(graph),
                    if (_paletteOpen)
                      _Palette(
                        registry: _registry,
                        onPick: (type) => _addNode(type, graph),
                        onDismiss: () => setState(() => _paletteOpen = false),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, FlowGraph? graph) {
    return Container(
      height: editorToolbarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 14),
          const SizedBox(width: 6),
          Text('Flow', style: editorBodyText),
          const SizedBox(width: 12),
          if (graph != null) ...[
            Text(
              '${graph.nodes.length} nodes, ${graph.links.length} wires',
              style: editorDetailText,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: 'Delete the selected node',
              onPressed: _selected == null
                  ? null
                  : () => _deleteSelected(graph),
            ),
            IconButton(
              icon: const Icon(Icons.center_focus_strong, size: 15),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
              tooltip: 'Reset the view',
              onPressed: () => setState(() {
                _pan = const Offset(40, 40);
                _zoom = 1;
              }),
            ),
            const SizedBox(width: 6),
            FilledButton.icon(
              onPressed: () => setState(() => _paletteOpen = !_paletteOpen),
              icon: const Icon(Icons.add, size: 15),
              label: const Text('Add node'),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildCanvas(FlowGraph graph) {
    return Listener(
      onPointerDown: (event) => _onPointerDown(event, graph),
      onPointerMove: (event) => _onPointerMove(event, graph),
      onPointerUp: (event) => _onPointerUp(event, graph),
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final zooming =
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed;
        setState(() {
          if (zooming) {
            final factor = event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1;
            final next = (_zoom * factor).clamp(0.25, 2.5);
            // Zoom about the pointer, so the thing under the cursor stays
            // under it.
            final anchor = _toCanvas(event.localPosition);
            _zoom = next;
            _pan = event.localPosition - anchor * _zoom;
          } else {
            _pan -= event.scrollDelta;
          }
        });
      },
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: FlowCanvasPainter(
            graph: graph,
            registry: _registry,
            pan: _pan,
            zoom: _zoom,
            selected: _selected,
            wireFrom: _wireFrom,
            wirePointer: _wirePointer,
          ),
        ),
      ),
    );
  }
}

/// A node's flow component, and which node it is on.
typedef ComponentSpecView = ({LocalId nodeId, ComponentSpec spec});

class _NoGraph extends StatelessWidget {
  const _NoGraph({required this.hasSelection, required this.onAdd});

  final bool hasSelection;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 32,
            color: editorMutedTextColor,
          ),
          const SizedBox(height: 12),
          Text(
            hasSelection
                ? 'This node has no script'
                : 'Select a node to script it',
            style: editorDialogTitleText,
          ),
          const SizedBox(height: 8),
          Text(
            'A Flow component holds a graph: events on the left, wired '
            'forward through what should happen.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
          if (hasSelection) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add a Flow component'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The node palette, grouped by category.
class _Palette extends StatefulWidget {
  const _Palette({
    required this.registry,
    required this.onPick,
    required this.onDismiss,
  });

  final FlowRegistry registry;
  final ValueChanged<FlowNodeType> onPick;
  final VoidCallback onDismiss;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final matches = [
      for (final type in widget.registry.all)
        if (needle.isEmpty ||
            type.label.toLowerCase().contains(needle) ||
            type.id.toLowerCase().contains(needle) ||
            type.doc.toLowerCase().contains(needle))
          type,
    ];
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: ColoredBox(
          color: editorSurfaceColor.withValues(alpha: 0.55),
          child: Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 300,
                margin: const EdgeInsets.all(10),
                decoration: editorPanelBox(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        height: 26,
                        child: TextField(
                          autofocus: true,
                          style: editorBodyText,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Search nodes',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                          onChanged: (value) =>
                              setState(() => _query = value),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          for (final category
                              in widget.registry.categories) ...[
                            if (matches.any((t) => t.category == category)) ...[
                              EditorSectionHeader(label: category),
                              for (final type in matches)
                                if (type.category == category)
                                  _PaletteRow(
                                    type: type,
                                    onTap: () => widget.onPick(type),
                                  ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.type, required this.onTap});

  final FlowNodeType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.label, style: editorBodyText),
          Text(
            type.doc,
            style: editorMicroText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
