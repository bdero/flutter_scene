import 'dart:convert';

import 'package:flutter/widgets.dart';

/// Where a dragged panel lands relative to a target tab group.
enum DockZone { center, left, right, top, bottom }

/// A node in the dock layout tree. Interior nodes are [DockSplit]s; leaves are
/// [DockTabs] groups holding one or more panel ids.
sealed class DockNode {
  Map<String, Object?> toJson();

  static DockNode fromJson(Map<String, Object?> json) {
    switch (json['type']) {
      case 'split':
        final axis = json['axis'] == 'h' ? Axis.horizontal : Axis.vertical;
        final children = [
          for (final child in json['children'] as List)
            DockNode.fromJson((child as Map).cast<String, Object?>()),
        ];
        final weights = [
          for (final w in json['weights'] as List) (w as num).toDouble(),
        ];
        if (children.isEmpty || weights.length != children.length) {
          throw const FormatException('Malformed dock split');
        }
        return DockSplit(axis, children, weights);
      case 'tabs':
        final panels = (json['panels'] as List).cast<String>().toList();
        final active = (json['active'] as num?)?.toInt() ?? 0;
        return DockTabs(panels, active: active);
      default:
        throw const FormatException('Unknown dock node type');
    }
  }
}

/// Two or more children laid out along [axis], separated by draggable
/// dividers. [weights] are the children's shares of the space and sum to 1.
class DockSplit extends DockNode {
  DockSplit(this.axis, this.children, this.weights);

  final Axis axis;
  final List<DockNode> children;
  final List<double> weights;

  @override
  Map<String, Object?> toJson() => {
    'type': 'split',
    'axis': axis == Axis.horizontal ? 'h' : 'v',
    'children': [for (final child in children) child.toJson()],
    'weights': weights,
  };
}

/// A tabbed group of panels. Always a leaf of the layout tree.
class DockTabs extends DockNode {
  DockTabs(this.panels, {this.active = 0});

  final List<String> panels;
  int active;

  String? get activePanel =>
      panels.isEmpty ? null : panels[active.clamp(0, panels.length - 1)];

  @override
  Map<String, Object?> toJson() => {
    'type': 'tabs',
    'panels': panels,
    'active': active,
  };
}

/// A dockable panel arrangement, mutated by tab drags and divider drags and
/// serializable so hosts can persist it across sessions.
///
/// A panel lives in exactly one of three places, the [root] tree (docked),
/// [floating] (torn out into its own OS window), or [hidden] (disabled from
/// the View menu).
class DockLayout {
  DockLayout(this.root, {List<String>? hidden, List<String>? floating})
    : hidden = hidden ?? [],
      floating = floating ?? [];

  factory DockLayout.fromJsonString(String source) {
    final json = jsonDecode(source);
    if (json is! Map) throw const FormatException('Malformed dock layout');
    final map = json.cast<String, Object?>();
    // The original persisted shape was the root node itself.
    if (map['type'] != null) {
      return DockLayout(DockNode.fromJson(map));
    }
    final root = map['root'];
    if (root is! Map) throw const FormatException('Malformed dock layout');
    return DockLayout(
      DockNode.fromJson(root.cast<String, Object?>()),
      hidden: (map['hidden'] as List?)?.cast<String>().toList(),
      floating: (map['floating'] as List?)?.cast<String>().toList(),
    );
  }

  /// Parses a persisted layout, dropping panel ids not in [knownPanels] and
  /// appending known panels the layout is missing. Returns null when [source]
  /// is null, unparsable, or contains none of the known panels.
  ///
  /// [isDynamic] admits ids created at runtime (extra viewports); they are
  /// kept where the layout has them but never appended when absent.
  static DockLayout? tryParse(
    String? source, {
    required List<String> knownPanels,
    bool Function(String id)? isDynamic,
  }) {
    if (source == null) return null;
    final DockLayout layout;
    try {
      layout = DockLayout.fromJsonString(source);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    final known = {
      ...knownPanels,
      if (isDynamic != null)
        ...{
          ...layout.panelIds(),
          ...layout.floating,
          ...layout.hidden,
        }.where(isDynamic),
    };
    for (final id in layout.panelIds().where((id) => !known.contains(id))) {
      layout.removePanel(id);
    }
    // A panel docked in the tree wins over stale hidden/floating entries, and
    // floating wins over hidden.
    final docked = layout.panelIds().toSet();
    layout.floating.retainWhere(
      (id) => known.contains(id) && !docked.contains(id),
    );
    layout.hidden.retainWhere(
      (id) =>
          known.contains(id) &&
          !docked.contains(id) &&
          !layout.floating.contains(id),
    );
    final present = {...docked, ...layout.floating, ...layout.hidden};
    if (present.isEmpty) return null;
    for (final id in knownPanels.where((id) => !present.contains(id))) {
      layout._lastGroup().panels.add(id);
    }
    return layout;
  }

  DockNode root;

  /// Panels disabled from view. Not rendered anywhere until shown again.
  final List<String> hidden;

  /// Panels torn out into their own OS windows, in creation order.
  final List<String> floating;

  String toJsonString() => jsonEncode({
    'root': root.toJson(),
    'hidden': hidden,
    'floating': floating,
  });

  /// Whether [id] is rendered anywhere (docked or floating).
  bool isVisible(String id) => floating.contains(id) || panelIds().contains(id);

  /// The tab group currently holding [id], or null when the panel is not
  /// docked in the tree.
  DockTabs? groupOf(String id) => _groupOf(id, root);

  /// Detaches [id] from view and remembers it as disabled.
  void hidePanel(String id) {
    removePanel(id);
    hidden.add(id);
  }

  /// Docks [id] (wherever it currently lives) into the last group.
  void showPanel(String id) {
    removePanel(id);
    final group = _lastGroup();
    group.panels.add(id);
    group.active = group.panels.length - 1;
    root = _collapse(root);
  }

  /// Detaches [id] from the tree into its own floating window.
  void floatPanel(String id) {
    removePanel(id);
    floating.add(id);
  }

  /// All panel ids in the tree, in depth-first order.
  List<String> panelIds([DockNode? node]) {
    final n = node ?? root;
    return switch (n) {
      DockTabs(:final panels) => List.of(panels),
      DockSplit(:final children) => [
        for (final child in children) ...panelIds(child),
      ],
    };
  }

  /// Detaches [id] from wherever it lives (tree, floating, or hidden),
  /// collapsing any group or split it empties.
  void removePanel(String id) {
    hidden.remove(id);
    floating.remove(id);
    final group = _groupOf(id, root);
    if (group == null) return;
    final index = group.panels.indexOf(id);
    group.panels.removeAt(index);
    if (group.active > index) group.active -= 1;
    if (group.panels.isNotEmpty) {
      group.active = group.active.clamp(0, group.panels.length - 1);
    } else {
      group.active = 0;
    }
    root = _collapse(root);
  }

  /// Moves panel [id] to [zone] of [target]. Center adds it as the group's
  /// last (and active) tab; an edge splits the group along that edge.
  void dock(String id, DockTabs target, DockZone zone) {
    // Dropping a group's sole tab back onto itself is a no-op.
    if (target.panels.length == 1 && target.panels.single == id) return;
    removePanel(id);
    if (!_contains(root, target)) {
      // The removal collapsed the target away (it only held the dragged
      // panel's neighbors in a nested arrangement that merged). Fall back to
      // tacking the panel onto the last group rather than losing it.
      _lastGroup().panels.add(id);
      root = _collapse(root);
      return;
    }
    if (zone == DockZone.center) {
      target.panels.add(id);
      target.active = target.panels.length - 1;
      return;
    }
    final axis = zone == DockZone.left || zone == DockZone.right
        ? Axis.horizontal
        : Axis.vertical;
    final before = zone == DockZone.left || zone == DockZone.top;
    final group = DockTabs([id]);
    final parent = _parentOf(target, root);
    if (parent != null && parent.axis == axis) {
      final index = parent.children.indexOf(target);
      final share = parent.weights[index] / 2;
      parent.weights[index] = share;
      parent.children.insert(before ? index : index + 1, group);
      parent.weights.insert(before ? index : index + 1, share);
    } else {
      final split = DockSplit(
        axis,
        before ? [group, target] : [target, group],
        [0.5, 0.5],
      );
      if (parent == null) {
        root = split;
      } else {
        parent.children[parent.children.indexOf(target)] = split;
      }
    }
    root = _collapse(root);
  }

  DockTabs? _groupOf(String id, DockNode node) {
    switch (node) {
      case DockTabs():
        return node.panels.contains(id) ? node : null;
      case DockSplit(:final children):
        for (final child in children) {
          final found = _groupOf(id, child);
          if (found != null) return found;
        }
        return null;
    }
  }

  DockSplit? _parentOf(DockNode target, DockNode node) {
    if (node is! DockSplit) return null;
    if (node.children.contains(target)) return node;
    for (final child in node.children) {
      final found = _parentOf(target, child);
      if (found != null) return found;
    }
    return null;
  }

  bool _contains(DockNode node, DockNode target) {
    if (identical(node, target)) return true;
    if (node is! DockSplit) return false;
    return node.children.any((child) => _contains(child, target));
  }

  DockTabs _lastGroup() {
    DockTabs? last;
    void walk(DockNode node) {
      switch (node) {
        case DockTabs():
          last = node;
        case DockSplit(:final children):
          children.forEach(walk);
      }
    }

    walk(root);
    if (last == null) {
      final group = DockTabs([]);
      root = group;
      return group;
    }
    return last!;
  }

  /// Removes empty groups, splices out single-child splits, inlines same-axis
  /// nested splits, and renormalizes weights.
  DockNode _collapse(DockNode node) {
    if (node is! DockSplit) return node;
    final children = <DockNode>[];
    final weights = <double>[];
    for (var i = 0; i < node.children.length; i++) {
      final child = _collapse(node.children[i]);
      if (child is DockTabs && child.panels.isEmpty) continue;
      if (child is DockSplit && child.axis == node.axis) {
        for (var j = 0; j < child.children.length; j++) {
          children.add(child.children[j]);
          weights.add(node.weights[i] * child.weights[j]);
        }
        continue;
      }
      children.add(child);
      weights.add(node.weights[i]);
    }
    if (children.isEmpty) return DockTabs([]);
    if (children.length == 1) return children.single;
    final sum = weights.fold(0.0, (a, b) => a + b);
    for (var i = 0; i < weights.length; i++) {
      weights[i] = sum > 0 ? weights[i] / sum : 1 / weights.length;
    }
    return DockSplit(node.axis, children, weights);
  }
}
