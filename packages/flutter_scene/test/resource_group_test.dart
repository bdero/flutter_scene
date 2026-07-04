// Unit tests for ResourceGroup. Pure Dart (no GPU/Impeller), so these run
// under a plain `flutter test`.

import 'dart:async';

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty group is immediately ready', () async {
    final group = ResourceGroup();
    expect(group.isReady, isTrue);
    expect(group.total, 0);
    expect(group.completed, 0);
    expect(group.progress.value, 1.0);
    await group.ready; // completes without hanging
    group.dispose();
  });

  test('add returns the same future and tracks completion', () async {
    final group = ResourceGroup();
    final completer = Completer<int>();
    final returned = group.add(completer.future);

    expect(identical(returned, completer.future), isTrue);
    expect(group.total, 1);
    expect(group.completed, 0);
    expect(group.isReady, isFalse);
    expect(group.progress.value, 0.0);

    completer.complete(42);
    await group.ready;

    expect(group.completed, 1);
    expect(group.isReady, isTrue);
    expect(group.progress.value, 1.0);
    expect(await returned, 42);
    group.dispose();
  });

  test('progress advances as loads settle', () async {
    final group = ResourceGroup();
    final a = Completer<void>();
    final b = Completer<void>();
    final c = Completer<void>();
    group.addAll([a.future, b.future, c.future]);

    expect(group.total, 3);
    expect(group.progress.value, 0.0);

    a.complete();
    await Future<void>.delayed(Duration.zero);
    expect(group.completed, 1);
    expect(group.progress.value, closeTo(1 / 3, 1e-9));

    b.complete();
    c.complete();
    await group.ready;
    expect(group.progress.value, 1.0);
    group.dispose();
  });

  test(
    'a failed load counts as settled and is recorded, ready never throws',
    () async {
      final group = ResourceGroup();
      final ok = Completer<void>();
      final bad = Completer<void>();
      group.add(ok.future);
      group.add(bad.future);

      ok.complete();
      bad.completeError(StateError('boom'));

      await group.ready; // must not throw
      expect(group.isReady, isTrue);
      expect(group.hasFailures, isTrue);
      expect(group.failures, hasLength(1));
      expect(group.failures.single, isA<StateError>());
      group.dispose();
    },
  );

  test('progress notifies listeners', () async {
    final group = ResourceGroup();
    final values = <double>[];
    group.progress.addListener(() => values.add(group.progress.value));

    final a = Completer<void>();
    final b = Completer<void>();
    group.add(a.future); // total 1 -> progress 0.0
    group.add(b.future); // total 2 -> progress 0.0 (still)

    a.complete();
    await Future<void>.delayed(Duration.zero);
    b.complete();
    await group.ready;

    expect(values, isNotEmpty);
    expect(values.last, 1.0);
    group.dispose();
  });
}
