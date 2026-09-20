// ignore_for_file: implementation_imports
import 'package:flutter_scene/src/gpu/raster_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// [FramePacer] paces the progressive radiance prefilter, one band per frame.
/// Where nothing presents (a headless test, a backgrounded embedding) there is
/// no frame to pace against, and waiting out a timeout per band would turn the
/// fill into one long stall.
void main() {
  const timeout = Duration(milliseconds: 40);

  test('stops waiting for frames once one has timed out', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final pacer = FramePacer();

    // Whether the binding serves that first frame decides how long the first
    // call takes, so only the calls after it are asserted on. If it did serve
    // one, pacing stays on and every call is fast for the other reason.
    await pacer.awaitFrame(timeout: timeout);

    final laterCalls = Stopwatch()..start();
    for (var band = 0; band < 7; band++) {
      await pacer.awaitFrame(timeout: timeout);
    }
    laterCalls.stop();

    expect(
      laterCalls.elapsed,
      lessThan(timeout * 7),
      reason:
          'seven more bands must not cost seven more timeouts; the pacer '
          'should have stopped waiting after the first one',
    );
  });

  test('a later fill is willing to wait again', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The degradation above is scoped to one fill. A process that stops
    // presenting for one environment must not stop pacing every environment
    // built after it, which would queue bands faster than the GPU retires
    // them and rebuild the stall this pacing exists to avoid.
    final stalled = FramePacer();
    await stalled.awaitFrame(timeout: timeout);
    await stalled.awaitFrame(timeout: timeout);

    final fresh = FramePacer();
    expect(fresh, isNot(same(stalled)));
    await fresh.awaitFrame(timeout: timeout);
  });

  test('completes without a GPU context', () async {
    // The rendezvous submits an empty command buffer, which throws with no
    // context. A caller still has to make progress rather than hang.
    await awaitRasterThread(timeout: timeout);
  });
}
