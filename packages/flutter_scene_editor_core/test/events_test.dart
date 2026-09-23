// Subscriptions are explicit and per client, and a flush delivers the state
// of the world rather than every step that got there.
import 'package:flutter_scene_editor_core/flutter_scene_editor_core.dart';
import 'package:test/test.dart';

void main() {
  test('a subscriber hears only what it asked for', () {
    final bus = EventBus();
    final pushed = <EditorEvent>[];
    bus.subscribe(const [
      EditorEventType.selectionChanged,
    ], onEvents: pushed.addAll);

    bus.emit(const EditorEvent(EditorEventType.selectionChanged));
    bus.emit(const EditorEvent(EditorEventType.documentSaved));
    bus.flush();

    expect(pushed.map((e) => e.type), [EditorEventType.selectionChanged]);
  });

  test('high-rate events coalesce, discrete ones do not', () {
    final bus = EventBus();
    final subscription = bus.subscribe(EditorEventType.all);

    for (var i = 0; i < 100; i++) {
      bus.emit(EditorEvent(EditorEventType.documentChanged, {'i': i}));
    }
    bus.emit(const EditorEvent(EditorEventType.documentSaved));
    bus.emit(const EditorEvent(EditorEventType.documentSaved));
    bus.flush();

    final drained = subscription.drain().events;
    final changes = drained.where(
      (e) => e.type == EditorEventType.documentChanged,
    );
    expect(changes, hasLength(1), reason: 'only the newest is worth sending');
    expect(changes.single.data['i'], 99);
    expect(
      drained.where((e) => e.type == EditorEventType.documentSaved),
      hasLength(2),
      reason: 'two saves are two things that happened',
    );
  });

  test('a subscription buffers for a client that polls', () {
    final bus = EventBus();
    final subscription = bus.subscribe(const [EditorEventType.documentSaved]);

    bus.emit(const EditorEvent(EditorEventType.documentSaved));
    bus.flush();
    expect(subscription.pendingCount, 1);

    final first = subscription.drain();
    expect(first.events, hasLength(1));
    expect(first.dropped, 0);
    expect(subscription.drain().events, isEmpty, reason: 'drained once');
  });

  test('a client that never drains loses the oldest, and is told', () {
    final bus = EventBus(maxBuffered: 4);
    final subscription = bus.subscribe(const [EditorEventType.documentSaved]);

    for (var i = 0; i < 10; i++) {
      bus.emit(EditorEvent(EditorEventType.documentSaved, {'i': i}));
      bus.flush();
    }

    final drained = subscription.drain();
    expect(drained.events, hasLength(4));
    expect(drained.dropped, 6);
    expect(drained.events.last.data['i'], 9, reason: 'the newest survives');
  });

  test('a cancelled subscription stops hearing anything', () {
    final bus = EventBus();
    final subscription = bus.subscribe(const [EditorEventType.documentSaved]);
    subscription.cancel();

    bus.emit(const EditorEvent(EditorEventType.documentSaved));
    bus.flush();
    expect(subscription.pendingCount, 0);
    expect(bus.subscriptions, isEmpty);
  });

  test('subscribing to nothing, or to a typo, fails loudly', () {
    final bus = EventBus();
    expect(() => bus.subscribe(const []), throwsArgumentError);
    expect(() => bus.subscribe(const ['nodeWiggled']), throwsArgumentError);
  });

  test('a session announces edits, selection, and saves', () async {
    final session = EditorSession.empty();
    final heard = <EditorEvent>[];
    session.events.subscribe(EditorEventType.all, onEvents: heard.addAll);

    session.run('createNode', {'name': 'Cube'});
    session.markSaved();
    session.events.flush();

    final types = heard.map((e) => e.type).toSet();
    expect(types, contains(EditorEventType.documentChanged));
    expect(types, contains(EditorEventType.historyChanged));
    expect(types, contains(EditorEventType.dirtyChanged));

    final history = heard.lastWhere(
      (e) => e.type == EditorEventType.historyChanged,
    );
    expect(history.data['canUndo'], isTrue);
    expect(history.data['undoLabel'], 'Create node');
  });

  test('a batch of a thousand is one document change', () {
    final session = EditorSession.empty();
    final subscription = session.events.subscribe(const [
      EditorEventType.documentChanged,
    ]);

    session.runAll([
      for (var i = 0; i < 1000; i++)
        CommandCall('createNode', {'name': 'Node$i'}),
    ]);
    session.events.flush();

    expect(subscription.drain().events, hasLength(1));
  });

  test('opening and saving are announced with their paths', () {
    final session = EditorSession.empty();
    final subscription = session.events.subscribe(const [
      EditorEventType.documentOpened,
      EditorEventType.documentSaved,
    ]);

    session.announceOpened(path: '/scenes/level.fscene');
    session.markDirty();
    session.announceSaved(path: '/scenes/level.fscene');
    session.events.flush();

    final events = subscription.drain().events;
    expect(events.map((e) => e.type), [
      EditorEventType.documentOpened,
      EditorEventType.documentSaved,
    ]);
    expect(events.first.data['path'], '/scenes/level.fscene');
    expect(session.isDirty, isFalse, reason: 'a save cleans the document');
  });

  test('a save is announced even when the document was already clean', () {
    final session = EditorSession.empty();
    final subscription = session.events.subscribe(const [
      EditorEventType.documentSaved,
    ]);

    session.announceSaved(path: '/a.fscene');
    session.events.flush();

    expect(subscription.drain().events, hasLength(1));
  });

  test('a subscription survives the document it was made against', () {
    final shared = EventBus();
    final first = EditorSession.empty()..events = shared;
    final subscription = shared.subscribe(const [
      EditorEventType.documentOpened,
      EditorEventType.documentChanged,
    ]);
    first.run('createNode', {'name': 'Old'});

    // What the editor does when a document opens: a new session, the same bus.
    final second = EditorSession.empty()..events = shared;
    second.announceOpened(path: '/new.fscene');
    second.run('createNode', {'name': 'New'});
    shared.flush();

    expect(
      subscription.drain().events.map((e) => e.type),
      containsAll([
        EditorEventType.documentOpened,
        EditorEventType.documentChanged,
      ]),
    );
  });

  test('an unheard event costs nothing when nobody subscribed', () {
    final session = EditorSession.empty();
    session.run('createNode', {'name': 'Cube'});
    // Nothing queued, so a flush with no subscribers is a no-op.
    session.events.flush();
    expect(session.events.subscriptions, isEmpty);
  });
}
