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

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart' show Vector2;

import '../blueprints/blueprint_file.dart';
import '../controller/editor_controller.dart';
import '../shell/editor_theme.dart';
import 'my_blueprint_panel.dart';
import 'visual_script_layout.dart';

/// The Visual Scripter panel.
class VisualScripterPanel extends StatefulWidget {
  const VisualScripterPanel({super.key, required this.controller, this.file});

  final EditorController controller;

  /// The blueprint asset being edited, or null to edit the selected node's
  /// script.
  ///
  /// The same editor, two sources. A graph on a node belongs to that node; a
  /// blueprint in the project is a class, edited on its own and instanced
  /// many times. Which one is open changes where a commit goes and nothing
  /// else, so there is one canvas rather than two that drift apart.
  final BlueprintFile? file;

  @override
  State<VisualScripterPanel> createState() => _VisualScripterPanelState();
}

class _VisualScripterPanelState extends State<VisualScripterPanel> {
  EditorController get _ctrl => widget.controller;

  final VisualScriptRegistry _registry = sceneVisualScriptRegistry();

  /// The blueprint being edited. Held here rather than read from the document
  /// on every frame, because a drag mutates it many times per second and only
  /// the release is worth an undo step.
  Blueprint? _blueprint;
  LocalId? _graphOwner;

  /// Which of the blueprint's graphs the canvas is showing.
  ///
  /// By name rather than by reference, so a reload from the document lands on
  /// the graph that was open rather than on one that no longer exists.
  String? _openGraphName;

  /// The graph on the canvas, which every gesture below edits.
  VisualScriptGraph? get _graph {
    final blueprint = _blueprint;
    if (blueprint == null) return null;
    final open = _openGraphName;
    if (open != null) {
      final named = blueprint.graph(open);
      if (named != null) return named;
    }
    return blueprint.graphs.isEmpty ? null : blueprint.graphs.first;
  }

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
    // A file-backed blueprint is not the selection's, so moving the selection
    // must not throw away what is open.
    if (widget.file != null) {
      setState(() {});
      return;
    }
    final id = _ctrl.selection.primary;
    final cursor = _ctrl.history.cursor;
    final movedElsewhere =
        !_committing && _blueprint != null && cursor != _graphCursor;
    if (id != _graphOwner || movedElsewhere) {
      setState(() {
        _blueprint = null;
        // The open graph is remembered across a reload of the same node, and
        // dropped when the selection moves to a different one.
        if (id != _graphOwner) {
          _openGraphName = null;
          _selected = null;
        }
        _graphOwner = id;
        _graphCursor = cursor;
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

  /// Loads the blueprint from the document, once per selection.
  Blueprint? _ensureBlueprint() {
    final existing = _blueprint;
    if (existing != null) return existing;
    final file = widget.file;
    if (file != null) {
      final loaded = file.read();
      // A file that failed to parse shows nothing rather than a blank canvas:
      // a blank canvas is how you save over your own work.
      if (loaded == null) return null;
      if (loaded.graphs.isEmpty) {
        loaded.addGraph(
          VisualScriptGraph(),
          kind: VisualScriptGraphKind.eventGraph,
          name: defaultEventGraphName,
        );
      }
      return _blueprint = loaded;
    }
    final view = _componentView;
    if (view == null) return null;
    final source = view.spec.properties['graph'];
    final loaded = source is StringValue && source.value.isNotEmpty
        ? _tryRead(source.value)
        : Blueprint.of(VisualScriptGraph());
    // A blueprint with nothing in it still needs somewhere to draw.
    if (loaded.graphs.isEmpty) {
      loaded.addGraph(
        VisualScriptGraph(),
        kind: VisualScriptGraphKind.eventGraph,
        name: defaultEventGraphName,
      );
    }
    _blueprint = loaded;
    _graphCursor = _ctrl.history.cursor;
    return loaded;
  }

  Blueprint _tryRead(String source) {
    try {
      return readBlueprint(source);
    } on FormatException {
      return Blueprint.of(VisualScriptGraph());
    }
  }

  /// Writes the graph back to the document as one undoable edit.
  Future<void> _commit() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final file = widget.file;
    if (file != null) {
      // Straight to disk. A blueprint asset is not part of the scene
      // document, so the scene's undo stack is the wrong place for it -- an
      // undo in the level should not silently rewrite a class.
      await file.write(blueprint);
      return;
    }
    final view = _componentView;
    if (view == null) return;
    _committing = true;
    try {
      await _ctrl.run('setComponentProperties', {
        'nodeId': view.nodeId.toToken(),
        'componentType': visualScriptComponentType,
        'properties': {'graph': StringValue(writeBlueprint(blueprint))},
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
    setState(() => _blueprint = null);
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

  Future<void> _addGraph(VisualScriptGraphKind kind) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final added = blueprint.addGraph(VisualScriptGraph(), kind: kind);
    setState(() {
      _openGraphName = added.name;
      _selected = null;
    });
    await _commit();
  }

  Future<void> _renameGraph(VisualScriptGraph graph, String name) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    // Through uniqueGraphName, because a function is called by its name and
    // two graphs sharing one is a call with two possible answers.
    final wanted = blueprint.graph(name) == null
        ? name
        : blueprint.uniqueGraphName(name);
    final wasOpen = _openGraphName == graph.name;
    graph.name = wanted;
    setState(() {
      if (wasOpen) _openGraphName = wanted;
    });
    await _commit();
  }

  Future<void> _deleteGraph(VisualScriptGraph graph) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    blueprint.graphs.remove(graph);
    setState(() {
      if (_openGraphName == graph.name) {
        _openGraphName = blueprint.graphs.isEmpty
            ? null
            : blueprint.graphs.first.name;
        _selected = null;
      }
    });
    await _commit();
  }

  Future<void> _addVariable() async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    final taken = {for (final v in blueprint.variables) v.name};
    var name = 'newVar';
    for (var i = 2; taken.contains(name); i++) {
      name = 'newVar$i';
    }
    blueprint.variables.add(
      VisualScriptVariable(
        name: name,
        type: VisualScriptType.number,
        initial: 0.0,
      ),
    );
    setState(() {});
    await _commit();
  }

  Future<void> _renameVariable(
    VisualScriptVariable variable,
    String name,
  ) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    // Through the blueprint, which carries the rename into every Get and Set
    // that names it: renaming only the declaration leaves the graph reading a
    // variable that is not there, which reads as null rather than as an error.
    if (!blueprint.renameVariable(variable.name, name)) return;
    setState(() {});
    await _commit();
  }

  Future<void> _deleteVariable(VisualScriptVariable variable) async {
    final blueprint = _blueprint;
    if (blueprint == null) return;
    blueprint.variables.remove(variable);
    setState(() {});
    await _commit();
  }

  @override
  Widget build(BuildContext context) {
    final blueprint = _ensureBlueprint();
    final graph = _graph;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildToolbar(context, graph),
        Expanded(
          child: blueprint == null || graph == null
              ? _NoGraph(
                  hasSelection: _ctrl.selection.primary != null,
                  onAdd: _addFlowComponent,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 200,
                      child: MyBlueprintPanel(
                        blueprint: blueprint,
                        openGraph: graph,
                        onOpenGraph: (picked) => setState(() {
                          _openGraphName = picked.name;
                          _selected = null;
                        }),
                        onAddGraph: (kind) => unawaited(_addGraph(kind)),
                        onRenameGraph: (target, name) =>
                            unawaited(_renameGraph(target, name)),
                        onDeleteGraph: (target) =>
                            unawaited(_deleteGraph(target)),
                        onAddVariable: () => unawaited(_addVariable()),
                        onRenameVariable: (variable, name) =>
                            unawaited(_renameVariable(variable, name)),
                        onDeleteVariable: (variable) =>
                            unawaited(_deleteVariable(variable)),
                      ),
                    ),
                    Container(width: 1, color: editorLineColor),
                    Expanded(
                      child: Stack(
                        children: [
                          _buildCanvas(graph),
                          if (_paletteOpen)
                            _Palette(
                              registry: _registry,
                              onPick: (type) => _addNode(type, graph),
                              onDismiss: () =>
                                  setState(() => _paletteOpen = false),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, VisualScriptGraph? graph) {
    return EditorToolbar(
      leading: [
        const Icon(Icons.account_tree_outlined, size: 14),
        const SizedBox(width: 6),
        Text('Visual Scripter', style: editorBodyText),
        const SizedBox(width: 12),
        if (graph != null) ...[
          Icon(
            MyBlueprintPanel.kindGlyph(graph.kind),
            size: 12,
            color: editorMutedTextColor,
          ),
          const SizedBox(width: 4),
          Text(graph.name, style: editorBodyText),
          const SizedBox(width: 8),
          Text(
            '${graph.nodes.length} nodes, ${graph.links.length} wires',
            style: editorDetailText,
          ),
        ],
      ],
      trailing: [
        if (graph != null) ...[
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
        ],
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
