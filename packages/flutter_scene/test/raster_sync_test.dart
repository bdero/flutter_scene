// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/raster_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// [awaitFrame] paces the progressive radiance prefilter, one band per frame.
/// Where nothing presents (a headless test, a backgrounded embedding) there is
/// no frame to pace against, and waiting out a timeout per band would turn the
/// fill into one long stall. The first timeout has to switch the rest of the
/// fill over to the raster rendezvous alone.
void main() {
  const timeout = Duration(milliseconds: 40);

  setUp(debugResetFramePacing);
  tearDown(debugResetFramePacing);

  test('stops waiting for frames once one has timed out', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final firstCall = Stopwatch()..start();
    await awaitFrame(timeout: timeout);
    firstCall.stop();

    // Whether the binding served that frame decides how long the first call
    // took, so only the calls after it are asserted on. If it did serve one,
    // pacing stays on and every call is fast for the other reason.
    final laterCalls = Stopwatch()..start();
    for (var band = 0; band < 7; band++) {
      await awaitFrame(timeout: timeout);
    }
    laterCalls.stop();

    expect(
      laterCalls.elapsed,
      lessThan(timeout * 7),
      reason:
          'seven more bands must not cost seven more timeouts; the latch '
          'should have dropped frame pacing after the first one',
    );
  });

  test('completes without a GPU context', () async {
    // The rendezvous submits an empty command buffer, which throws with no
    // context. A caller still has to make progress rather than hang.
    await awaitRasterThread(timeout: timeout);
  });
}
