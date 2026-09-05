import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/node.dart';

/// Which objects are currently selected, and a notification when that
/// changes.
///
/// A game usually needs the selection in three places at once — the renderer
/// outlining it, a UI panel describing it, and the command handling acting on
/// it — so it wants to live in one place that all three can watch rather than
/// being rebuilt from a click handler. That is all this is: a set of nodes, an
/// order, and a [ChangeNotifier].
///
/// The modifier conventions are worth following because players already know
/// them: a plain click replaces the selection ([selectOnly]), shift-click adds
/// ([add]), and ctrl-click toggles ([toggle]).
///
/// ```dart
/// final selection = SceneSelection();
///
/// void onTap(Node? picked, {required bool shiftHeld}) {
///   if (picked == null) return selection.clear();
///   shiftHeld ? selection.toggle(picked) : selection.selectOnly(picked);
/// }
/// ```
///
/// Nodes removed from the scene are not dropped automatically — nothing tells
/// the selection they went — so call [remove] when something is destroyed, or
/// [pruneDetached] periodically.
/// {@category Picking and input}
class SceneSelection extends ChangeNotifier {
  /// Creates a selection, optionally holding [initial].
  SceneSelection([Iterable<Node>? initial]) {
    if (initial != null) _nodes.addAll(initial);
  }

  // A LinkedHashSet, so iteration order is selection order: the "primary"
  // object a UI describes is the first one the player picked, and stays so.
  final Set<Node> _nodes = <Node>{};

  /// The selected objects, in the order they were selected.
  Iterable<Node> get nodes => _nodes;

  /// How many objects are selected.
  int get length => _nodes.length;

  /// Whether nothing is selected.
  bool get isEmpty => _nodes.isEmpty;

  /// Whether anything is selected.
  bool get isNotEmpty => _nodes.isNotEmpty;

  /// The first object selected, or null. The one a single-target UI describes.
  Node? get primary => _nodes.isEmpty ? null : _nodes.first;

  /// Whether [node] is selected.
  bool contains(Node node) => _nodes.contains(node);

  /// Replaces the selection with [node] alone.
  void selectOnly(Node node) {
    if (_nodes.length == 1 && _nodes.first == node) return;
    _nodes
      ..clear()
      ..add(node);
    notifyListeners();
  }

  /// Replaces the selection with [nodes].
  void setAll(Iterable<Node> nodes) {
    final next = nodes.toSet();
    if (_sameAs(next)) return;
    _nodes
      ..clear()
      ..addAll(nodes);
    notifyListeners();
  }

  /// Adds [node], keeping what is already selected.
  void add(Node node) {
    if (!_nodes.add(node)) return;
    notifyListeners();
  }

  /// Adds every node in [nodes].
  void addAll(Iterable<Node> nodes) {
    var changed = false;
    for (final node in nodes) {
      changed |= _nodes.add(node);
    }
    if (changed) notifyListeners();
  }

  /// Deselects [node]. Returns whether it was selected.
  bool remove(Node node) {
    if (!_nodes.remove(node)) return false;
    notifyListeners();
    return true;
  }

  /// Selects [node] if it is not selected, deselects it if it is.
  void toggle(Node node) {
    if (!_nodes.remove(node)) _nodes.add(node);
    notifyListeners();
  }

  /// Deselects everything.
  void clear() {
    if (_nodes.isEmpty) return;
    _nodes.clear();
    notifyListeners();
  }

  /// Drops any selected node that is no longer in a live scene.
  ///
  /// Call after destroying objects, so a dead unit does not linger in the
  /// selection and in whatever UI is reading it.
  void pruneDetached() {
    final gone = _nodes
        .where((node) => node.internalRenderScene == null)
        .toList();
    if (gone.isEmpty) return;
    _nodes.removeAll(gone);
    notifyListeners();
  }

  bool _sameAs(Set<Node> other) =>
      _nodes.length == other.length && _nodes.containsAll(other);
}
