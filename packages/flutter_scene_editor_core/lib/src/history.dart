/// Undo and redo as history rewind over [Transaction]s.
///
/// One stack holds every committed transaction plus a cursor marking how many
/// are currently applied. Undo reverts the transaction under the cursor and
/// steps back; redo re-applies the next and steps forward. Committing a new
/// transaction discards any redo tail. There are no hand-written do/undo
/// pairs, undo is the transaction's own [Transaction.revert].
library;

import 'package:scene/scene.dart';

import 'change.dart';
import 'selection.dart';

/// A single undo/redo stack over a [DocumentMutator].
class EditHistory {
  /// Creates a history that commits to [mutator].
  ///
  /// [selection] makes selection part of undo: every transaction records what
  /// was selected before and after it, so undo restores the selection the
  /// edit was made from, and a selection change on its own is a step.
  /// [maxEntries] and [maxPayloadBytes] bound the stack, dropping the oldest
  /// steps first; records carry whole specs, so an imported and deleted mesh
  /// would otherwise keep its bytes alive forever.
  EditHistory(
    this._mutator, {
    this.selection,
    this.maxEntries = 256,
    this.maxPayloadBytes = 256 * 1024 * 1024,
  });

  final DocumentMutator _mutator;

  /// The selection transactions snapshot, or null to leave it out of undo.
  Selection? selection;

  /// The most steps to keep.
  final int maxEntries;

  /// The most payload bytes to keep across the stack's records.
  final int maxPayloadBytes;
  final List<Transaction> _transactions = [];
  int _cursor = 0;

  /// The committed transactions, oldest first (applied and undone alike).
  List<Transaction> get transactions => List.unmodifiable(_transactions);

  /// How many transactions are currently applied (the undo cursor).
  int get cursor => _cursor;

  /// Whether there is an applied transaction to undo.
  bool get canUndo => _cursor > 0;

  /// Whether there is an undone transaction to redo.
  bool get canRedo => _cursor < _transactions.length;

  /// The label of the transaction undo would revert, or null.
  String? get undoLabel => canUndo ? _transactions[_cursor - 1].name : null;

  /// The label of the transaction redo would re-apply, or null.
  String? get redoLabel => canRedo ? _transactions[_cursor].name : null;

  /// Commits [transaction], applying it and pushing it onto the stack. Any
  /// redo tail is discarded. An empty transaction is ignored (no history
  /// entry, no notification), so commands that turn out to be no-ops do not
  /// clutter the undo stack.
  void commit(Transaction transaction) {
    transaction.selectionBefore ??= _snapshot();
    transaction.apply(_mutator);
    transaction.selectionAfter = _snapshot();
    // Judged before the redo tail goes, so a no-op after an undo cannot
    // destroy what redo would have re-applied.
    if (transaction.isEmpty) return;
    if (_cursor < _transactions.length) {
      _transactions.removeRange(_cursor, _transactions.length);
    }
    _transactions.add(transaction);
    _cursor++;
    _trim();
    _notify();
    // Again after listeners ran, since pruning drops ids the edit deleted.
    transaction.selectionAfter = _snapshot();
  }

  List<LocalId>? _snapshot() => selection?.ids.toList();

  /// Folds the current selection into the step just committed, for a host
  /// that selects what an edit created. Redo then restores that selection
  /// instead of leaving a second step behind.
  void syncSelectionAfter() {
    if (_cursor == 0) return;
    _transactions[_cursor - 1].selectionAfter = _snapshot();
  }

  void _restore(List<LocalId>? ids) {
    if (ids == null) return;
    selection?.set(ids);
  }

  /// Drops the oldest steps until the stack fits both bounds. Undone steps
  /// (the redo tail) are kept; only history behind the cursor is dropped.
  void _trim() {
    var bytes = 0;
    for (final transaction in _transactions) {
      bytes += _payloadBytes(transaction);
    }
    while (_transactions.length > 1 &&
        (_transactions.length > maxEntries || bytes > maxPayloadBytes) &&
        _cursor > 0) {
      bytes -= _payloadBytes(_transactions.removeAt(0));
      _cursor--;
    }
  }

  static int _payloadBytes(Transaction transaction) {
    var bytes = 0;
    for (final record in transaction.records) {
      for (final value in [record.oldValue, record.newValue]) {
        if (value is PayloadChange) {
          bytes += value.value?.bytes?.lengthInBytes ?? 0;
        }
      }
    }
    return bytes;
  }

  /// Reverts the most recently applied transaction. Returns false when there
  /// is nothing to undo.
  bool undo() {
    if (!canUndo) return false;
    _cursor--;
    final transaction = _transactions[_cursor];
    transaction.revert(_mutator);
    _restore(transaction.selectionBefore);
    _notify();
    return true;
  }

  /// Re-applies the next undone transaction. Returns false when there is
  /// nothing to redo.
  bool redo() {
    if (!canRedo) return false;
    final transaction = _transactions[_cursor];
    transaction.apply(_mutator);
    _restore(transaction.selectionAfter);
    _cursor++;
    _notify();
    return true;
  }

  /// Drops all history (the document state is left as-is). Use when loading a
  /// fresh document.
  void clear() {
    _transactions.clear();
    _cursor = 0;
    _notify();
  }

  final List<void Function()> _listeners = [];

  /// Registers [listener], called after every commit, undo, redo, or clear.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
