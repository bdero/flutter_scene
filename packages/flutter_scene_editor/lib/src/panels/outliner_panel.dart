// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/id.dart';
// ignore: implementation_imports
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter/material.dart';

import '../controller/editor_controller.dart';

/// Scene-tree outliner panel.
///
/// Renders the hierarchy from [EditorController.query], highlights the
/// selection, and supports tap-to-select and drag-to-reparent (runs
/// [reparentNode] command). Rebuilds on controller notifications.
///
/// The tree is a custom recursive widget. The two_dimensional_scrollables
/// TreeView API requires a TreeController with a fixed node model that
/// conflicts with the live-document update pattern here (the document changes
/// identity on every realization); a custom widget is the correct call and
/// avoids fiddly adapter glue.
///
/// TODO(virtualize-outliner): replace with a two_dimensional_scrollables
/// TreeView backed by a stable-id node model for scenes with 1000+ nodes.
class OutlinerPanel extends StatelessWidget {
  const OutlinerPanel({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final roots = controller.query.roots;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              label: 'Outliner',
              trailing: IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'Create node',
                onPressed: () => controller.run('createNode', {'name': 'Node'}),
              ),
            ),
            Expanded(
              child: roots.isEmpty
                  ? const Center(
                      child: Text(
                        'Empty scene',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final node in roots)
                            _OutlinerNode(
                              node: node,
                              controller: controller,
                              depth: 0,
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// One row in the outliner, possibly expanded to show children.
class _OutlinerNode extends StatefulWidget {
  const _OutlinerNode({
    required this.node,
    required this.controller,
    required this.depth,
  });

  final NodeSpec node;
  final EditorController controller;
  final int depth;

  @override
  State<_OutlinerNode> createState() => _OutlinerNodeState();
}

class _OutlinerNodeState extends State<_OutlinerNode> {
  bool _expanded = true;
  bool _dragTarget = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final ctrl = widget.controller;
    final isSelected = ctrl.selection.contains(node.id);
    final children = ctrl.query.childrenOf(node.id);
    final hasChildren = children.isNotEmpty;

    final row = DragTarget<LocalId>(
      onWillAcceptWithDetails: (details) {
        final dragged = details.data;
        if (dragged == node.id) return false;
        // Prevent dragging a node onto one of its own descendants.
        final subtree = ctrl.query.subtreeOf(dragged);
        return !subtree.contains(node.id);
      },
      onAcceptWithDetails: (details) {
        setState(() => _dragTarget = false);
        ctrl.run('reparentNode', {
          'nodeId': details.data.toToken(),
          'newParentId': node.id.toToken(),
        });
      },
      onLeave: (_) => setState(() => _dragTarget = false),
      onMove: (_) => setState(() => _dragTarget = true),
      builder: (context, candidateData, rejectedData) {
        return Draggable<LocalId>(
          data: node.id,
          feedback: Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                node.name.isEmpty ? node.id.toToken() : node.name,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          child: InkWell(
            onTap: () => ctrl.selection.selectOnly(node.id),
            child: Container(
              color: _dragTarget
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : isSelected
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.15)
                  : null,
              padding: EdgeInsets.only(
                left: 4.0 + widget.depth * 16.0,
                right: 4,
                top: 2,
                bottom: 2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: hasChildren
                        ? GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Icon(
                              _expanded
                                  ? Icons.arrow_drop_down
                                  : Icons.arrow_right,
                              size: 16,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    node.instance != null
                        ? Icons.link
                        : hasChildren
                        ? Icons.account_tree_outlined
                        : Icons.circle_outlined,
                    size: 12,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      node.name.isEmpty ? '(${node.id.toToken()})' : node.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Visibility toggle.
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: Icon(
                        node.visible
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => ctrl.run('setNodeVisible', {
                        'nodeId': node.id.toToken(),
                        'visible': !node.visible,
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (_expanded && hasChildren)
          for (final child in children)
            _OutlinerNode(
              node: child,
              controller: ctrl,
              depth: widget.depth + 1,
            ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.label, this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
