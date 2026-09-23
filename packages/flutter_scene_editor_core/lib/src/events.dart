/// Editor events and the per-client subscriptions that carry them.
///
/// A client that can only poll is not scriptable in any useful sense, so the
/// session announces what changed. Two rules from the protocol design hold
/// here. Subscriptions are per client and explicit, so nobody pays for events
/// they did not ask for. And events are coalesced before delivery, since a
/// drag emits a selection change per frame and a batch emits one document
/// change per command, and no subscriber wants either stream verbatim.
library;

import 'dart:async';

/// The event names the session emits. String-typed on the wire, so a client
/// built against an older engine can subscribe to what it knows and ignore
/// the rest.
abstract final class EditorEventType {
  /// The selection changed. Coalesced.
  static const String selectionChanged = 'selectionChanged';

  /// The document changed (a command, an undo, a redo). Coalesced.
  static const String documentChanged = 'documentChanged';

  /// The undo history moved (a commit, an undo, a redo). Coalesced.
  static const String historyChanged = 'historyChanged';

  /// The document became dirty or clean. Coalesced.
  static const String dirtyChanged = 'dirtyChanged';

  /// A document was opened, replacing what was loaded. Carries its `path`
  /// when it came from a file.
  static const String documentOpened = 'documentOpened';

  /// The document was saved, carrying the `path` it went to.
  static const String documentSaved = 'documentSaved';

  /// Every name above.
  static const List<String> all = [
    selectionChanged,
    documentChanged,
    historyChanged,
    dirtyChanged,
    documentOpened,
    documentSaved,
  ];
}

/// One thing that happened, with whatever detail a subscriber needs to act
/// without immediately querying back.
class EditorEvent {
  /// Creates an event of [type] carrying [data].
  const EditorEvent(this.type, [this.data = const {}]);

  /// One of [EditorEventType]'s names.
  final String type;

  /// JSON-shaped detail.
  final Map<String, Object?> data;

  /// The wire form.
  Map<String, Object?> toJson() => {
    'type': type,
    if (data.isNotEmpty) 'data': data,
  };

  @override
  String toString() => 'EditorEvent($type, $data)';
}

/// A live subscription. Cancel it to stop receiving events and release the
/// buffer behind it.
class EventSubscription {
  EventSubscription._(this._bus, this.id, this.types, this._onEvents);

  final EventBus _bus;

  /// The subscription's id, which a client uses to poll or cancel it.
  final String id;

  /// The event names this subscription wants.
  final Set<String> types;

  final void Function(List<EditorEvent>)? _onEvents;
  final List<EditorEvent> _pending = [];
  var _dropped = 0;

  /// Whether [type] is one this subscription asked for.
  bool wants(String type) => types.contains(type);

  /// Events delivered since the last drain, oldest first, and how many were
  /// dropped to stay under the buffer cap.
  ///
  /// A subscription that is also pushed still buffers, so a client may use
  /// either path, or both after a reconnect.
  ({List<EditorEvent> events, int dropped}) drain() {
    final out = (events: List.of(_pending), dropped: _dropped);
    _pending.clear();
    _dropped = 0;
    return out;
  }

  /// How many events are waiting to be drained.
  int get pendingCount => _pending.length;

  /// Stops this subscription.
  void cancel() => _bus._cancel(this);

  void _deliver(List<EditorEvent> events) {
    for (final event in events) {
      if (_pending.length >= _bus.maxBuffered) {
        // The oldest goes, since a client that fell behind wants the current
        // state of the world more than the start of the backlog.
        _pending.removeAt(0);
        _dropped++;
      }
      _pending.add(event);
    }
    _onEvents?.call(events);
  }
}

/// Fans editor events out to the clients that asked for them.
///
/// Emitted events are held until a flush, which is when coalescing happens.
/// A host with a frame loop points [flushScheduler] at a frame callback;
/// without one, a flush lands on the next microtask.
class EventBus {
  /// Creates a bus. [maxBuffered] caps what one undrained subscription holds.
  EventBus({this.maxBuffered = 256});

  /// The most events one subscription buffers before the oldest are dropped.
  final int maxBuffered;

  /// Runs its callback when the next flush should happen. A host with a frame
  /// loop points this at a post-frame callback, which is what makes "coalesced
  /// per frame" true rather than aspirational; null flushes on the next
  /// microtask, so a headless session still delivers promptly.
  void Function(void Function())? flushScheduler;

  void _scheduleFlush(void Function() callback) =>
      (flushScheduler ?? scheduleMicrotask)(callback);

  final List<EventSubscription> _subscriptions = [];
  final List<EditorEvent> _pending = [];
  var _flushScheduled = false;
  var _nextId = 1;

  /// The live subscriptions.
  Iterable<EventSubscription> get subscriptions => _subscriptions;

  /// Subscribes to [types], optionally pushing to [onEvents] as they arrive.
  /// Every subscription buffers for [EventSubscription.drain] regardless.
  ///
  /// Throws [ArgumentError] when [types] is empty or names an event the
  /// engine does not emit, so a typo fails loudly instead of going quiet.
  EventSubscription subscribe(
    Iterable<String> types, {
    void Function(List<EditorEvent>)? onEvents,
  }) {
    final wanted = types.toSet();
    if (wanted.isEmpty) {
      throw ArgumentError('Subscribe to at least one event type');
    }
    final unknown = wanted.difference(EditorEventType.all.toSet());
    if (unknown.isNotEmpty) {
      throw ArgumentError(
        'Unknown event types: ${unknown.join(', ')}; '
        'this engine emits ${EditorEventType.all.join(', ')}',
      );
    }
    final subscription = EventSubscription._(
      this,
      'sub${_nextId++}',
      wanted,
      onEvents,
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  /// The subscription with [id], or null.
  EventSubscription? lookup(String id) =>
      _subscriptions.where((s) => s.id == id).firstOrNull;

  void _cancel(EventSubscription subscription) =>
      _subscriptions.remove(subscription);

  /// Queues [event] for the next flush. Cheap when nobody is subscribed.
  void emit(EditorEvent event) {
    if (_subscriptions.isEmpty) return;
    _pending.add(event);
    if (_flushScheduled) return;
    _flushScheduled = true;
    _scheduleFlush(flush);
  }

  /// Delivers everything queued, coalesced, and clears the queue.
  void flush() {
    _flushScheduled = false;
    if (_pending.isEmpty) return;
    final events = _coalesce(_pending);
    _pending.clear();
    for (final subscription in List.of(_subscriptions)) {
      final wanted = [
        for (final event in events)
          if (subscription.wants(event.type)) event,
      ];
      if (wanted.isNotEmpty) subscription._deliver(wanted);
    }
  }

  /// The high-rate types, where only the newest in a flush is worth
  /// delivering. Everything else is a discrete thing that happened and
  /// survives in order.
  static const Set<String> _coalescing = {
    EditorEventType.selectionChanged,
    EditorEventType.documentChanged,
    EditorEventType.historyChanged,
    EditorEventType.dirtyChanged,
  };

  /// Drops all but the last of each high-rate type, in place. A hundred
  /// document changes in one batch become one notification, while two saves
  /// stay two.
  static List<EditorEvent> _coalesce(List<EditorEvent> events) {
    final lastOfType = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      lastOfType[events[i].type] = i;
    }
    return [
      for (var i = 0; i < events.length; i++)
        if (!_coalescing.contains(events[i].type) ||
            lastOfType[events[i].type] == i)
          events[i],
    ];
  }
}
