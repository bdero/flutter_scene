/// Undo and redo as history rewind over [Transaction]s.
///
/// One stack holds every committed transaction plus a cursor marking how many
/// are currently applied. Undo reverts the transaction under the cursor and
/// steps back; redo re-applies the next and steps forward. Committing a new
/// transaction discards any redo tail. There are no hand-written do/undo
/// pairs, undo is the transaction's own [Transaction.revert].
library;

import 'change.dart';

/// A single undo/redo stack over a [DocumentMutator].
class EditHistory {
  /// Creates a history that commits to [mutator].
  EditHistory(this._mutator);

  final DocumentMutator _mutator;
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
    if (transaction.isEmpty) return;
    if (_cursor < _transactions.length) {
      _transactions.removeRange(_cursor, _transactions.length);
    }
    transaction.apply(_mutator);
    _transactions.add(transaction);
    _cursor++;
    _notify();
  }

  /// Reverts the most recently applied transaction. Returns false when there
  /// is nothing to undo.
  bool undo() {
    if (!canUndo) return false;
    _cursor--;
    _transactions[_cursor].revert(_mutator);
    _notify();
    return true;
  }

  /// Re-applies the next undone transaction. Returns false when there is
  /// nothing to redo.
  bool redo() {
    if (!canRedo) return false;
    _transactions[_cursor].apply(_mutator);
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
