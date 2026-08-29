/// The Visual Scripter dock panel: the canvas a visual script is drawn on.
///
/// Nodes are dragged around, pins are dragged between to wire them, and the
/// palette adds more. The graph being edited belongs to the selected node's
/// visual script component, and every edit is committed back through the
/// command layer so it is undoable like any other.
///
/// The canvas is one [CustomPaint] over a transformed coordinate space rather
/// than a widget per node. A graph is a hundred small boxes and several
/// hundred wires; as widgets that is a layout pass per pan, and panning is the
/// thing the canvas does most.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'visual_script_layout.dart';

/// The Visual Scripter panel.
class VisualScripterPanel extends StatefulWidget {
  const VisualScripterPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  State<VisualScripterPanel> createState() => _VisualScripterPanelState();
}

class _VisualScripterPanelState extends State<VisualScripterPanel> {
  EditorController get _ctrl => widget.controller;

  final VisualScriptRegistry _registry = sceneVisualScriptRegistry();

  /// The graph being edited. Held here rather than read from the document on
  /// every frame, because a drag mutates it many times per second and only
  /// the release is worth an undo step.
  VisualScriptGraph? _graph;
  LocalId? _graphOwner;

  /// The history position the loaded graph came from.
  ///
  /// An undo reverts the document but has no way to reach into the canvas's
  /// own copy, so the copy is dropped whenever the cursor moves somewhere it
  /// did not put it. Without this, undoing a wire leaves it on screen.
  int _graphCursor = -1;

  /// Set across a commit, so the reload check does not throw away the graph
  /// the panel just wrote.
  bool _committing = false;

  Offset _pan = const Offset(40, 40);
  double _zoom = 1;

  int? _selected;

  /// Whether the canvas shows what the live graph is doing.
  ///
  /// Off by default: tracing rebuilds the run's context, which restarts the
  /// script, and it is not something to do to a scene nobody asked to debug.
  bool _tracing = false;
  int? _dragging;
  Offset _dragOffset = Offset.zero;

  /// The wire being drawn, if any: where it started and where the pointer is.
  VisualScriptPortRef? _wireFrom;
  Offset? _wirePointer;

  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl.selection.addListener(_onSelectionChanged);
    _ctrl.history.addListener(_onSelectionChanged);
    _ctrl.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _ctrl.selection.removeListener(_onSelectionChanged);
    _ctrl.history.removeListener(_onSelectionChanged);
    _ctrl.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    final id = _ctrl.selection.primary;
    final cursor = _ctrl.history.cursor;
    final movedElsewhere =
        !_committing && _graph != null && cursor != _graphCursor;
    if (id != _graphOwner || movedElsewhere) {
      setState(() {
        _graph = null;
        _graphOwner = id;
        _graphCursor = cursor;
        if (id != _graphOwner) _selected = null;
      });
      return;
    }
    setState(() {});
  }

  /// The selected node's visual script component spec, or null.
  ComponentSpecView? get _componentView {
    final id = _ctrl.selection.primary;
    if (id == null) return null;
    final node = _ctrl.document.node(id);
    if (node == null) return null;
    for (final component in node.components) {
      if (component.type == visualScriptComponentType) {
        return (nodeId: id, spec: component);
      }
    }
    return null;
  }

  /// The live component the selected node realized, or null when the scene
  /// has not been realized or the selection carries no graph.
  ///
  /// The document holds the script; this is the thing actually running it,
  /// and the only place a trace can come from.
  VisualScriptComponent? get _liveComponent {
    final view = _componentView;
    if (view == null) return null;
    return _ctrl.liveNode(view.nodeId)?.getComponent<VisualScriptComponent>();
  }

  void _toggleTracing() {
    setState(() => _tracing = !_tracing);
    // Turning it on restarts the script, because the trace is fixed to a run
    // at construction -- which is what keeps the runtime's hot path a null
    // check rather than a flag test per node.
    _liveComponent?.tracing = _tracing;
  }

  /// Loads the graph from the document, once per selection.
  VisualScriptGraph? _ensureGraph() {
    final existing = _graph;
    if (existing != null) return existing;
    final view = _componentView;
    if (view == null) return null;
    final source = view.spec.properties['graph'];
    final loaded = source is StringValue && source.value.isNotEmpty
        ? _tryRead(source.value)
        : VisualScriptGraph();
    _graph = loaded;
    _graphCursor = _ctrl.history.cursor;
    return loaded;
  }

  VisualScriptGraph _tryRead(String source) {
    try {
      return readVisualScript(source);
    } on FormatException {
      return VisualScriptGraph();
    }
  }

  /// Writes the graph back to the document as one undoable edit.
  Future<void> _commit() async {
    final graph = _graph;
    final view = _componentView;
    if (graph == null || view == null) return;
    _committing = true;
    try {
      await _ctrl.run('setComponentProperties', {
        'nodeId': view.nodeId.toToken(),
        'componentType': visualScriptComponentType,
        'properties': {'graph': StringValue(writeVisualScript(graph))},
      });
    } finally {
      _committing = false;
      _graphCursor = _ctrl.history.cursor;
    }
  }

  Future<void> _addFlowComponent() async {
    final id = _ctrl.selection.primary;
    if (id == null) return;
    await _ctrl.run('addComponent', {
      'nodeId': id.toToken(),
      'componentType': visualScriptComponentType,
    });
    setState(() => _graph = null);
  }

  // --- canvas geometry -----------------------------------------------------

  Offset _toCanvas(Offset screen) => (screen - _pan) / _zoom;

  VisualScriptLayout _layout(VisualScriptGraph graph) =>
      VisualScriptLayout(graph, _registry);

  // --- interaction ---------------------------------------------------------

  void _onPointerDown(PointerDownEvent event, VisualScriptGraph graph) {
    final at = _toCanvas(event.localPosition);
    final layout = _layout(graph);

    final port = layout.portAt(at);
    if (port != null) {
      // Grabbing a connected input pulls the wire off it, which is how one is
      // rerouted rather than deleted and drawn again.
      final existing = port.isInput ? graph.inputTo(port.node, port.pin) : null;
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

  void _onPointerMove(PointerMoveEvent event, VisualScriptGraph graph) {
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

  Future<void> _onPointerUp(
    PointerUpEvent event,
    VisualScriptGraph graph,
  ) async {
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
          VisualScriptLink(
            fromNode: output.node,
            fromPin: output.pin,
            toNode: input.node,
            toPin: input.pin,
          ),
          // Only exec outputs are singular; a value feeds as many inputs as
          // want it.
          execOutputIsSingular: _typeOf(graph, output) == VisualScriptType.exec,
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

  VisualScriptType? _typeOf(VisualScriptGraph graph, VisualScriptPortRef port) {
    final spec = graph.node(port.node);
    if (spec == null) return null;
    return _registry[spec.type]?.pin(port.pin)?.type;
  }

  /// Whether a wire from one port to the other is legal.
  bool _canConnect(
    VisualScriptGraph graph,
    VisualScriptPortRef a,
    VisualScriptPortRef b,
  ) {
    if (a.node == b.node) return false;
    if (a.isInput == b.isInput) return false;
    final output = a.isInput ? b : a;
    final input = a.isInput ? a : b;
    final from = _typeOf(graph, output);
    final to = _typeOf(graph, input);
    if (from == null || to == null) return false;
    return from.connectsTo(to);
  }

  Future<void> _deleteSelected(VisualScriptGraph graph) async {
    final selected = _selected;
    if (selected == null) return;
    graph.removeNode(selected);
    setState(() => _selected = null);
    await _commit();
  }

  Future<void> _addNode(
    VisualScriptNodeType type,
    VisualScriptGraph graph,
  ) async {
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

  Widget _buildToolbar(BuildContext context, VisualScriptGraph? graph) {
    return EditorToolbar(
      children: [
        const Icon(Icons.account_tree_outlined, size: 14),
        const SizedBox(width: 6),
        Text('Visual Scripter', style: editorBodyText),
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
            onPressed: _selected == null ? null : () => _deleteSelected(graph),
          ),
          IconButton(
            icon: Icon(
              _tracing ? Icons.visibility : Icons.visibility_outlined,
              size: 15,
              color: _tracing ? editorAccentColor : null,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            tooltip: _tracing
                ? 'Stop watching the run'
                : 'Watch the run: which wires fire, and what is on them '
                      '(restarts the script)',
            onPressed: _toggleTracing,
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
    );
  }

  Widget _buildCanvas(VisualScriptGraph graph) {
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
          painter: VisualScriptCanvasPainter(
            graph: graph,
            registry: _registry,
            pan: _pan,
            zoom: _zoom,
            selected: _selected,
            wireFrom: _wireFrom,
            wirePointer: _wirePointer,
            trace: _tracing ? _liveComponent?.trace : null,
          ),
        ),
      ),
    );
  }
}

/// A node's visual script component, and which node it is on.
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
            'A visual script holds a graph: events on the left, wired '
            'forward through what should happen.',
            textAlign: TextAlign.center,
            style: editorDetailText,
          ),
          if (hasSelection) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add a visual script'),
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

  final VisualScriptRegistry registry;
  final ValueChanged<VisualScriptNodeType> onPick;
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
                            contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onChanged: (value) => setState(() => _query = value),
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

  final VisualScriptNodeType type;
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
