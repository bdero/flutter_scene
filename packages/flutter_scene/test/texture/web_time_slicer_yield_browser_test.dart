@TestOn('browser')
// ignore_for_file: implementation_imports
library;

import 'dart:async' show Timer;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_scene/src/texture/web_time_slicer_yield_web.dart';
import 'package:flutter_test/flutter_test.dart';

JSPromise<JSAny?> _resolvedPromise() => Future<JSAny?>.value(null).toJS;

void main() {
  test('prefers scheduler.yield() over postTask()', () async {
    var yieldCalls = 0;
    var postTaskCalls = 0;

    final sched = JSObject()
      ..['yield'] = (() {
        yieldCalls++;
        return _resolvedPromise();
      }).toJS
      ..['postTask'] = ((JSFunction callback, JSObject opts) {
        postTaskCalls++;
        return _resolvedPromise();
      }).toJS;

    await yieldWithScheduler(sched);

    expect(yieldCalls, 1);
    expect(postTaskCalls, 0);
  });

  test(
    'falls back to scheduler.postTask with user-visible priority when yield is absent',
    () async {
      var postTaskCalls = 0;
      String? capturedPriority;

      final sched = JSObject()
        ..['postTask'] = ((JSFunction callback, JSObject opts) {
          postTaskCalls++;
          capturedPriority = (opts['priority'] as JSString?)?.toDart;
          callback.callAsFunction();
          return _resolvedPromise();
        }).toJS;

      await yieldWithScheduler(sched);

      expect(postTaskCalls, 1);
      expect(capturedPriority, 'user-visible');
    },
  );

  test('falls back to a macrotask timer when scheduler is absent', () async {
    final events = <String>[];
    Timer.run(() => events.add('timer'));

    await yieldWithScheduler(null);
    events.add('resumed');

    expect(events, ['timer', 'resumed']);
  });

  test(
    'falls back to a macrotask timer when scheduler.yield() rejects',
    () async {
      final events = <String>[];
      final sched = JSObject()
        ..['yield'] = (() => Future<JSAny?>.error(
          StateError('aborted'),
        ).toJS).toJS;
      Timer.run(() => events.add('timer'));

      await yieldWithScheduler(sched);
      events.add('resumed');

      expect(events, ['timer', 'resumed']);
    },
  );
}
