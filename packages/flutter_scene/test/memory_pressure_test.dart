import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/memory_pressure.dart';
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_scene/src/surface.dart';
import 'package:flutter_test/flutter_test.dart';

/// The byte accounting itself needs real GPU textures, so it lives in
/// `examples/smoke_render/integration_test/memory_pressure_test.dart`. What is
/// here is the wiring, which does not.
///
/// Delivers the platform's `memoryPressure` notification the way the engine
/// does, so the test exercises the real channel rather than the observer.
Future<void> _sendMemoryPressure() async {
  const message = <String, dynamic>{'type': 'memoryPressure'};
  final data = const JSONMessageCodec().encodeMessage(message)!;
  final delivered = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    SystemChannels.system.name,
    data,
    (_) => delivered.complete(),
  );
  await delivered.future;
}

/// Records what the observing pool forwards, without needing a GPU.
class _RecordingPool extends TransientTexturePool {
  int clears = 0;
  int residentBytesReads = 0;

  @override
  void clear() => clears++;

  @override
  int get residentBytes {
    residentBytesReads++;
    return 1234;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ObservedTexturePool', () {
    test('forwards clear and residentBytes to the wrapped pool', () {
      final inner = _RecordingPool();
      final observed = ObservedTexturePool(inner, _NullObserver());

      expect(observed.residentBytes, 1234);
      expect(inner.residentBytesReads, 1);

      observed.clear();
      expect(inner.clears, 1);
    });
  });

  group('Surface registry', () {
    test('a new surface joins the live set', () {
      final before = Surface.liveCount;
      final surface = Surface();
      expect(Surface.liveCount, before + 1);
      // Keeps the surface alive across the assertion above.
      expect(surface.transientBytes, 0);
    });

    test('a surface with no views sheds nothing and does not throw', () {
      final surface = Surface();
      expect(surface.shedViewRenderTargets(), 0);
      expect(surface.transientBytes, 0);
    });
  });

  group('memory pressure', () {
    test('an observer is registered', () {
      listenForMemoryPressure();
      expect(memoryPressureObserver, isNotNull);
    });

    test('registering twice keeps the same observer', () {
      listenForMemoryPressure();
      final first = memoryPressureObserver;
      listenForMemoryPressure();
      expect(memoryPressureObserver, same(first));
    });

    test('the platform notification reaches the observer', () async {
      listenForMemoryPressure();
      // With no textures allocated there is nothing to release; what is under
      // test is that the message arrives and the shed runs cleanly.
      await expectLater(_sendMemoryPressure(), completes);
    });
  });
}

class _NullObserver implements RenderGraphObserver {
  @override
  void onPassBegin(RenderGraphPass pass, int indexInGraph) {}

  @override
  void onPassEnd(RenderGraphPass pass, int elapsedMicros) {}

  @override
  void onBlackboardRead(Object key, Object? value) {}

  @override
  void onBlackboardWrite(Object key, Object? value) {}

  @override
  void onTextureAcquired(
    TransientTextureDescriptor descriptor,
    gpu.Texture texture,
  ) {}
}
