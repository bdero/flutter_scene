/// My Blueprint: everything in the blueprint, listed.
///
/// A blueprint is several graphs and a set of variables, and a canvas can only
/// show one graph at a time. Without a list of what else is in there, a
/// function you wrote last week is a thing you have to remember the name of.
///
/// Grouped the way Unreal groups it -- graphs, functions, macros, variables --
/// because that is the order they are reached for, and because a construction
/// script sitting in the middle of a list of functions reads as a function.
library;

import 'package:flutter/material.dart';
import 'package:scene/visual_script.dart';

import '../shell/editor_theme.dart';

/// The sidebar listing a blueprint's graphs and variables.
class MyBlueprintPanel extends StatelessWidget {
  const MyBlueprintPanel({
    super.key,
    required this.blueprint,
    required this.openGraph,
    required this.onOpenGraph,
    required this.onAddGraph,
    required this.onRenameGraph,
    required this.onDeleteGraph,
    required this.onAddVariable,
    required this.onRenameVariable,
    required this.onDeleteVariable,
  });

  final Blueprint blueprint;

  /// The graph the canvas is showing.
  final VisualScriptGraph? openGraph;

  final ValueChanged<VisualScriptGraph> onOpenGraph;
  final ValueChanged<VisualScriptGraphKind> onAddGraph;
  final void Function(VisualScriptGraph graph, String name) onRenameGraph;
  final ValueChanged<VisualScriptGraph> onDeleteGraph;

  final VoidCallback onAddVariable;
  final void Function(VisualScriptVariable variable, String name)
  onRenameVariable;
  final ValueChanged<VisualScriptVariable> onDeleteVariable;

  /// The kinds shown as their own sections, in the order they are reached for.
  static const List<VisualScriptGraphKind> _sections = [
    VisualScriptGraphKind.eventGraph,
    VisualScriptGraphKind.constructionScript,
    VisualScriptGraphKind.function,
    VisualScriptGraphKind.macro,
  ];

  /// What the heading over a section of [kind] says.
  static String sectionLabel(VisualScriptGraphKind kind) => switch (kind) {
    VisualScriptGraphKind.eventGraph => 'Graphs',
    VisualScriptGraphKind.constructionScript => 'Construction',
    VisualScriptGraphKind.function => 'Functions',
    VisualScriptGraphKind.macro => 'Macros',
  };

  /// The glyph a graph of [kind] is listed with.
  static IconData kindGlyph(VisualScriptGraphKind kind) => switch (kind) {
    VisualScriptGraphKind.eventGraph => Icons.account_tree_outlined,
    VisualScriptGraphKind.constructionScript => Icons.construction_outlined,
    VisualScriptGraphKind.function => Icons.functions,
    VisualScriptGraphKind.macro => Icons.unfold_more,
  };

  /// Whether a section of [kind] is shown when it holds nothing.
  ///
  /// Graphs and Construction always are, because every blueprint has or wants
  /// one. Functions and Macros appear once there is one, so a simple script
  /// is not a list of four empty headings.
  static bool showsWhenEmpty(VisualScriptGraphKind kind) =>
      kind == VisualScriptGraphKind.eventGraph ||
      kind == VisualScriptGraphKind.constructionScript;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: editorPanelColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        children: [
          for (final kind in _sections) ...[
            if (blueprint.graphsOfKind(kind).isNotEmpty || showsWhenEmpty(kind))
              _Section(
                label: sectionLabel(kind),
                onAdd: () => onAddGraph(kind),
                addTooltip: 'Add a ${kind.label.toLowerCase()}',
                children: [
                  for (final graph in blueprint.graphsOfKind(kind))
                    _GraphRow(
                      graph: graph,
                      open: identical(graph, openGraph),
                      // The last event graph is not removable: a blueprint
                      // with nowhere to draw is a panel with nothing in it.
                      onDelete:
                          kind == VisualScriptGraphKind.eventGraph &&
                              blueprint.graphsOfKind(kind).length == 1
                          ? null
                          : () => onDeleteGraph(graph),
                      onOpen: () => onOpenGraph(graph),
                      onRename: (name) => onRenameGraph(graph, name),
                    ),
                ],
              ),
          ],
          _Section(
            label: 'Variables',
            onAdd: onAddVariable,
            addTooltip: 'Add a variable',
            children: [
              if (blueprint.variables.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'A variable is remembered between ticks, and every graph '
                    'here reads the same one.',
                    style: editorMicroText,
                  ),
                ),
              for (final variable in blueprint.variables)
                _VariableRow(
                  variable: variable,
                  onDelete: () => onDeleteVariable(variable),
                  onRename: (name) => onRenameVariable(variable, name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.onAdd,
    required this.addTooltip,
    required this.children,
  });

  final String label;
  final VoidCallback onAdd;
  final String addTooltip;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 9,
                letterSpacing: 1.1,
                color: editorMutedTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 13),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 20, height: 20),
            tooltip: addTooltip,
            onPressed: onAdd,
          ),
        ],
      ),
      ...children,
      const SizedBox(height: 8),
    ],
  );
}

class _GraphRow extends StatelessWidget {
  const _GraphRow({
    required this.graph,
    required this.open,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final VisualScriptGraph graph;
  final bool open;
  final VoidCallback onOpen;
  final ValueChanged<String> onRename;

  /// Null when this graph may not be removed.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => _Row(
    icon: MyBlueprintPanel.kindGlyph(graph.kind),
    label: graph.name,
    detail: '${graph.nodes.length}',
    selected: open,
    onTap: onOpen,
    onRename: onRename,
    onDelete: onDelete,
  );
}

class _VariableRow extends StatelessWidget {
  const _VariableRow({
    required this.variable,
    required this.onRename,
    required this.onDelete,
  });

  final VisualScriptVariable variable;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _Row(
    icon: Icons.data_object,
    label: variable.name,
    detail: variable.type.label,
    selected: false,
    onTap: null,
    onRename: onRename,
    onDelete: onDelete,
  );
}

/// One row: a glyph, an editable name, what it is, and a way to remove it.
class _Row extends StatefulWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<String> onRename;
  final VoidCallback? onDelete;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;
  bool _renaming = false;
  late final TextEditingController _text = TextEditingController(
    text: widget.label,
  );

  @override
  void didUpdateWidget(_Row old) {
    super.didUpdateWidget(old);
    if (!_renaming && widget.label != _text.text) _text.text = widget.label;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _renaming = false);
    final wanted = _text.text.trim();
    if (wanted.isEmpty || wanted == widget.label) {
      _text.text = widget.label;
      return;
    }
    widget.onRename(wanted);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: () => setState(() => _renaming = true),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: BoxDecoration(
            color: widget.selected
                ? editorAccentColor.withValues(alpha: 0.16)
                : (_hovered ? editorRaisedColor : Colors.transparent),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: widget.selected
                    ? editorAccentColor
                    : editorMutedTextColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _renaming
                    ? SizedBox(
                        height: 20,
                        child: TextField(
                          controller: _text,
                          autofocus: true,
                          style: editorBodyText,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onSubmitted: (_) => _submit(),
                          onTapOutside: (_) => _submit(),
                        ),
                      )
                    : Text(
                        widget.label,
                        style: editorBodyText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              if (!_renaming) ...[
                const SizedBox(width: 6),
                Text(widget.detail, style: editorMicroText),
              ],
              if (_hovered && !_renaming && widget.onDelete != null)
                SizedBox(
                  width: 18,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 12),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 18,
                      height: 18,
                    ),
                    tooltip: 'Remove',
                    onPressed: widget.onDelete,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
