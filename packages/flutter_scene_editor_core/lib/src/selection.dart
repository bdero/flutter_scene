/// The selection model: which nodes the editor is acting on.
///
/// Selection is transient editor state, not document state, so it is never a
/// change record and never lands on the undo history (D1). It is a plain
/// observable set keyed by stable [LocalId], shared by the viewport, the
/// outliner, and the inspector.
library;

import 'package:scene/scene.dart';

/// An observable set of selected node ids with a designated primary.
class Selection {
  final Set<LocalId> _ids = {};
  LocalId? _primary;

  /// The selected ids (unordered).
  Set<LocalId> get ids => Set.unmodifiable(_ids);

  /// The primary selection (the last one added), or null when empty.
  LocalId? get primary => _primary;

  /// Whether nothing is selected.
  bool get isEmpty => _ids.isEmpty;

  /// Whether anything is selected.
  bool get isNotEmpty => _ids.isNotEmpty;

  /// How many nodes are selected.
  int get length => _ids.length;

  /// Whether [id] is selected.
  bool contains(LocalId id) => _ids.contains(id);

  /// Replaces the selection with exactly [id].
  void selectOnly(LocalId id) {
    _ids
      ..clear()
      ..add(id);
    _primary = id;
    _notify();
  }

  /// Replaces the selection with [ids] (primary becomes the last).
  void set(Iterable<LocalId> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _primary = _ids.isEmpty ? null : ids.last;
    _notify();
  }

  /// Adds [id] to the selection and makes it primary.
  void add(LocalId id) {
    _ids.add(id);
    _primary = id;
    _notify();
  }

  /// Removes [id] from the selection.
  void remove(LocalId id) {
    if (!_ids.remove(id)) return;
    if (_primary == id) _primary = _ids.isEmpty ? null : _ids.last;
    _notify();
  }

  /// Toggles [id] in the selection.
  void toggle(LocalId id) => contains(id) ? remove(id) : add(id);

  /// Clears the selection.
  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    _primary = null;
    _notify();
  }

  /// Drops any selected id for which [keep] returns false (used after a
  /// delete or an undo removes nodes).
  void retainWhere(bool Function(LocalId id) keep) {
    final before = _ids.length;
    _ids.retainWhere(keep);
    if (_primary != null && !_ids.contains(_primary)) {
      _primary = _ids.isEmpty ? null : _ids.last;
    }
    if (_ids.length != before) _notify();
  }

  final List<void Function()> _listeners = [];

  /// Registers [listener], called on every selection change.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
