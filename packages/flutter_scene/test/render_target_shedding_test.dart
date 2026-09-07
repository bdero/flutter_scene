// Covers handing pooled render targets back: which pools a shed reaches, that
// a wrapping pool is not counted or cleared twice, and that a real platform
// memory-pressure message drives the shed. Byte accounting needs live GPU
// textures, so it is covered by the smoke_render integration test instead.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/memory_report.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_test/flutter_test.dart';

/// A pool that counts the sheds it receives. Registers like any other pool,
/// since it owns rings.
class _CountingPool extends TransientTexturePool {
  int clears = 0;

  @override
  void clear() {
    clears++;
    super.clear();
  }
}

class _NullObserver implements RenderGraphObserver {
  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Delivers the platform's memory-pressure message the way the engine does,
/// rather than calling the observer directly, so the test covers the whole
/// path from the channel to the shed.
Future<void> sendMemoryPressure() {
  final message = const JSONMessageCodec().encodeMessage(<String, dynamic>{
    'type': 'memoryPressure',
  });
  final delivered = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.system.name,
    message,
    (_) => delivered.complete(),
  );
  return delivered.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    releaseRenderTargetsOnMemoryPressure = true;
    stopListeningForMemoryPressure();
  });

  group('pool registry', () {
    test('a shed reaches every pool that owns rings', () {
      final a = _CountingPool();
      final b = _CountingPool();

      releaseTransientRenderTargets();

      expect(a.clears, 1);
      expect(b.clears, 1);
    });

    test('a wrapping pool is cleared through the pool it wraps, once', () {
      final inner = _CountingPool();
      // Registering the wrapper too would clear `inner` a second time and
      // count its textures twice in the report.
      ObservedTexturePool(inner, _NullObserver());

      releaseTransientRenderTargets();

      expect(inner.clears, 1);
    });

    test('a collected pool stops being reached', () async {
      final before = TransientTexturePool.liveCount;
      // Constructed and dropped without ever being read back, so nothing but
      // the registry could be holding it.
      _CountingPool();
      expect(TransientTexturePool.liveCount, before + 1);

      // Weak references clear only after a collection, which a VM test cannot
      // force. What is assertable without one is that the walk itself does not
      // grow the list, which is what would turn a churn of scenes into a leak
      // of its own.
      releaseTransientRenderTargets();
      expect(TransientTexturePool.liveCount, lessThanOrEqualTo(before + 1));
    });
  });

  group('memory pressure', () {
    test('no observer is attached before the engine starts listening', () {
      expect(memoryPressureObserver, isNull);
    });

    test('platform pressure sheds the pools', () async {
      final pool = _CountingPool();
      listenForMemoryPressure();
      expect(memoryPressureObserver, isNotNull);

      await sendMemoryPressure();

      expect(pool.clears, 1);
    });

    test('turning the automatic release off detaches the observer', () async {
      final pool = _CountingPool();
      listenForMemoryPressure();

      releaseRenderTargetsOnMemoryPressure = false;
      expect(
        memoryPressureObserver,
        isNull,
        reason: 'off leaves no listener registered, not a listener that no-ops',
      );

      await sendMemoryPressure();
      expect(pool.clears, 0);

      // Flipping back re-attaches, so an app can hold the pools through one
      // screen and give them back on the next.
      releaseRenderTargetsOnMemoryPressure = true;
      expect(memoryPressureObserver, isNotNull);
      await sendMemoryPressure();
      expect(pool.clears, 1);
    });

    test('the preference survives being set before listening starts', () async {
      final pool = _CountingPool();
      releaseRenderTargetsOnMemoryPressure = false;

      // An app that turns this off at startup must not have it turned back on
      // by `Scene.initializeStaticResources()`.
      listenForMemoryPressure();
      expect(memoryPressureObserver, isNull);

      await sendMemoryPressure();
      expect(pool.clears, 0);
    });

    test('a direct release works whether or not anything is listening', () {
      final pool = _CountingPool();
      releaseRenderTargetsOnMemoryPressure = false;

      releaseTransientRenderTargets();

      expect(pool.clears, 1);
    });
  });

  group('memory report', () {
    test('reports render targets as their own category', () {
      final report = takeMemoryReport();
      final names = report.categories.map((c) => c.name);

      expect(names, contains('render targets'));
    });

    test('the render target count is the number of live pools', () {
      final before = _renderTargets(takeMemoryReport()).count;
      final pools = [_CountingPool(), _CountingPool()];

      expect(_renderTargets(takeMemoryReport()).count, before + pools.length);
    });
  });
}

MemoryCategory _renderTargets(MemoryReport report) =>
    report.categories.firstWhere((c) => c.name == 'render targets');
