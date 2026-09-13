import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_scene_input/flutter_scene_input.dart';
// ignore: implementation_imports
import 'package:flutter_scene_input/src/pointer_lock/pointer_lock_backend.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeBackend implements PointerLockBackend {
  bool supported = true;
  Completer<bool>? requestResult;
  int requests = 0;
  int releases = 0;
  Offset pending = Offset.zero;
  void Function(PointerLockLoss reason)? lost;

  @override
  bool get isSupported => supported;

  @override
  Future<bool> request() {
    requests++;
    return requestResult?.future ?? Future<bool>.value(true);
  }

  @override
  void release() => releases++;

  @override
  Offset takeMovement() {
    final movement = pending;
    pending = Offset.zero;
    return movement;
  }

  @override
  set onLost(void Function(PointerLockLoss reason)? callback) =>
      lost = callback;
}

void main() {
  late FakeBackend backend;
  Duration? stamp;
  late PointerLock lock;

  setUp(() {
    backend = FakeBackend();
    stamp = null;
    lock = PointerLock.withBackend(backend, frameStamp: () => stamp);
  });

  test('lock notifies and clears movement gathered before the lock', () async {
    backend.pending = const Offset(50, 50);
    var notifications = 0;
    lock.addListener(() => notifications++);

    expect(await lock.lock(), isTrue);
    expect(lock.isLocked, isTrue);
    expect(lock.lastLoss, isNull);
    expect(notifications, 1);

    stamp = const Duration(milliseconds: 16);
    expect(lock.movement, Offset.zero);
  });

  test('the request is issued synchronously, inside the caller', () {
    backend.requestResult = Completer<bool>();
    lock.lock();
    expect(backend.requests, 1);
  });

  test('movement drains once per frame and is stable within it', () async {
    await lock.lock();

    backend.pending = const Offset(3, -2);
    stamp = const Duration(milliseconds: 16);
    expect(lock.movement, const Offset(3, -2));
    backend.pending = const Offset(10, 10);
    expect(lock.movement, const Offset(3, -2));

    stamp = const Duration(milliseconds: 33);
    expect(lock.movement, const Offset(10, 10));
  });

  test('a read between frames returns the last frame', () async {
    await lock.lock();
    backend.pending = const Offset(4, 0);
    stamp = const Duration(milliseconds: 16);
    expect(lock.movement, const Offset(4, 0));

    stamp = null;
    backend.pending = const Offset(9, 9);
    expect(lock.movement, const Offset(4, 0));
  });

  test('unlock releases and records the reason', () async {
    await lock.lock();
    lock.unlock();
    expect(lock.isLocked, isFalse);
    expect(lock.lastLoss, PointerLockLoss.unlocked);
    expect(backend.releases, 1);
    expect(lock.movement, Offset.zero);

    lock.unlock();
    expect(backend.releases, 1);
  });

  test('a platform loss notifies without a release', () async {
    await lock.lock();
    var notifications = 0;
    lock.addListener(() => notifications++);

    backend.lost!(PointerLockLoss.userExit);
    expect(lock.isLocked, isFalse);
    expect(lock.lastLoss, PointerLockLoss.userExit);
    expect(notifications, 1);
    expect(backend.releases, 0);
  });

  test('unlock during a pending request releases the late grant', () async {
    final result = Completer<bool>();
    backend.requestResult = result;
    final granted = lock.lock();
    expect(identical(lock.lock(), granted), isTrue);

    lock.unlock();
    result.complete(true);
    expect(await granted, isFalse);
    expect(lock.isLocked, isFalse);
    expect(backend.releases, 1);
  });

  test('unsupported platforms refuse without asking', () async {
    backend.supported = false;
    expect(await lock.lock(), isFalse);
    expect(backend.requests, 0);
  });

  test('the native library builds and binds on desktop hosts', () async {
    final instance = PointerLock.instance;
    expect(instance.isSupported, Platform.isMacOS || Platform.isWindows);
    // The test runner has no focused window, so the lock is refused.
    expect(await instance.lock(), isFalse);
    expect(instance.movement, Offset.zero);
  }, skip: !(Platform.isMacOS || Platform.isWindows));
}
